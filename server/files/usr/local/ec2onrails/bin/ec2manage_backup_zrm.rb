#!/usr/bin/ruby
#

#    This file is part of EC2 on Rails.
#    http://rubyforge.org/projects/ec2onrails/
#
#    Copyright 2007 Paul Dowman, http://pauldowman.com/
#
#    EC2 on Rails is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    EC2 on Rails is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
    
#
# This script is called by zrm-scheduler 
#

# mysql-zrm.conf(5) configuration file.
# First parameter is the value of "post-backup-plugin-options" from the
# Second parameter is the data being backed up. It will be either
# '--all-databases' or
# '--databases <"db1 db2 ...">' or
# '--database <db>' and  '--tables <"table1 table2 ...">'
# Third parameter will be --backup-directory <path>
# Fourth parameter will be --checksum-pending
#
# The second time the post-backup-plugin is called it will have 2 parameters
# First parameter will be --backup-directory <path>
# Second parameter will be --checksum-finished


require "rubygems"
require "optiflag"
require "fileutils"
require 'EC2' 
require 'find'
require 'yaml' 

#################################################################
#
# Read the configuration file and set the global variables 
#
#################################################################
# XXX This directory should be obtained from a configuration file?
CONFIG_FILE = '/etc/ec2manage/ec2manage-zrm.conf'
unless File.exists?(CONFIG_FILE) and File.readable?(CONFIG_FILE) 
  raise "Configuration file missing or unreadable #{CONFIG_FILE}" 
end

config = YAML::load( File.read(CONFIG_FILE))
raise "Misconfigured file" unless config

puts config.inspect 

ZRM_BACKUP_ROOT             = config['zrm_backup_root'] || '/mnt/mysql-zrm/backup'
RAILS_ROOT                  = config['rails_root'] || '/mnt/www/myfavorite-app1/current' 
ZRM_S3_PREFIX               = config['zrm_s3_prefix'] || 'zrm' 

NUM_INCREMENTAL_BACKUPS_AUX = config['max_num_incremental_backups'] || '((60*24)/5)'
NUM_FULL_BACKUPS_AUX        = config['max_num_full_backups'] || '100' 
BACKUP_SLEEP_DURATION_AUX   = config['backup_sleep_duration'] || '0' 

NUM_INCREMENTAL_BACKUPS     = NUM_INCREMENTAL_BACKUPS_AUX.to_i
NUM_FULL_BACKUPS            = NUM_FULL_BACKUPS_AUX.to_i
BACKUP_SLEEP_DURATION       = BACKUP_SLEEP_DURATION_AUX.to_i

# Sanity check.
exit unless File.exists?(RAILS_ROOT)  
exit unless File.exists?(ZRM_BACKUP_ROOT)

# How much time to wait to let the checksum be completed
# and files created in place?
sleep(BACKUP_SLEEP_DURATION) unless BACKUP_SLEEP_DURATION <= 0

# Configuration files from the myfavorite-app1 deployment
s3_config = "#{RAILS_ROOT}/config/s3.yml"
database_config = "#{RAILS_ROOT}/config/database.yml"

# Aargh! Ruby ARGV strings are frozen. So we cant edit them in place
# # and Optiflag doesnt like - in the command name
ARGV.each_index do |i| 
   # --all-databases => __all_databases => --all-databases
   if ARGV[i] =~ /^\-/ 
     x = ARGV[i].gsub("-", "_")
     ARGV[i] = x.gsub("__","--")
   else 
     #unfreze ARGV
     x = ARGV[i].dup
     ARGV[i] = x
   end
end

#################################################################
#
# Load all the modules
#
#################################################################
require "#{File.dirname(__FILE__)}/../lib/mysql_helper"
require "#{File.dirname(__FILE__)}/../lib/s3_helper"
require "#{File.dirname(__FILE__)}/../lib/aws_helper"
require "#{File.dirname(__FILE__)}/../lib/roles_helper"
require "#{File.dirname(__FILE__)}/../lib/backup_helper"
require "#{File.dirname(__FILE__)}/../lib/utils"


###############################################################
#
# Parse the command line..
#
###############################################################

# Only run if this instance is the db_pimrary
# The original code would run on any instance that had /etc/init.d/mysql
# Which was pretty much all instances no matter what role
include Ec2onrails::RolesHelper
exit unless in_role?(:db_primary)


module CommandLineArgs extend OptiFlagSet
  optional_switch_flag "all_databases" 
  optional_flag "databases"
  optional_flag "database"
  optional_flag "tables"
  flag "backup_directory" 
  optional_switch_flag "checksum_pending" 
  optional_switch_flag "checksum_finished" 
  optional_switch_flag "incremental" 
  optional_switch_flag "full" 
  optional_flag "num_backups"
  
  and_process!
end

#puts ARGV.inspect
#puts ARGV.flags.inspect

exit unless ARGV.flags.checksum_finished 

#=> Do the sanity check to enforce the command line 

if !ARGV.flags.checksum_finished and 
           (ARGV.flags.all_databases or 
            ARGV.flags.databases or 
            ARGV.flags.database )
  raise "Databases flag not passed" 
end

if ARGV.flags.database
  unless ARGV.flags.tables 
    raise "tables flag not specified with database flag"
  end
end
  
unless ARGV.flags.checksum_pending or ARGV.flags.checksum_finished 
  raise "Checksum pending/completed flag not specified" 
end

# Comment this in case you want to do this only 
if ARGV.flags.incremental 
  # Last 12 hours
  num_backups =  ARGV.flags.num_backups || NUM_INCREMENTAL_BACKUPS 
else  
  # 100 days of full backup
  num_backups =  ARGV.flags.num_backups || NUM_FULL_BACKUPS
end

##################################################
# Now process the backed up database
##################################################
@aws   = Ec2onrails::AwsHelper.new s3_config

#
bucket = ARGV.flags.bucket
bucket_base_name  = @aws.bucket_base_name
bucket = bucket || "#{bucket_base_name}"
prefix = ZRM_S3_PREFIX

begin

  # Directory where the backup is currently located 
  # /mnt/mysql-zrm/backup/ec2manage-incremental/20090328023539
  
  # Strip the backup directory prefix 
  # ZRM_BACKUP_ROOT=/mnt/mysql-zrm/backup
  dir = ARGV.flags.backup_directory.dup
  dir.sub!(ZRM_BACKUP_ROOT, prefix)
  
  # Now dir is either 
  # zrm/ec2manage-incremental/20090328023539
  # or
  # zrm/ec2manage-full/20090328023539
  
  # Extract the bucket-set 
  arr = dir.split(/\//)
  bucketset = arr[1]
  prefix_for_keys = prefix + "/" + bucketset
  puts "Bucket set = #{bucketset}; prefix_for_keys = #{prefix_for_keys}"

  #
  # Now connect 
  @s3 = Ec2onrails::S3Helper.new(bucket, dir, s3_config )
  
  #=> Keep only last n around.
  keys = @s3.list_keys_zrm(prefix_for_keys)
  
  #puts "keys = " + keys.inspect 

  #=> Cleanup the old backups 
  if keys and ! keys.empty?
    keys_to_be_removed = Ec2onrails::Utils.extract_keys_to_be_removed_zrm(keys, num_backups) 
    #puts "Number of keys: #{num_backups}"
    #puts "To remove: " + keys_to_be_removed.inspect 
    keys_to_be_removed.each do |k|
      puts "Removing #{k}"
      @s3.delete_files_2(k)
    end
  end
  
  #=> Go through the directory structure and co
  # /mnt/mysql-zrm/backup/ec2manage-full/20090328023539
  
  backup_directory = ARGV.flags.backup_directory
  Find.find(backup_directory) do |path|
    if FileTest.file?(path)
      puts "Storing the file #{path}"
      @s3.store_file path
    end
  end
ensure
  # Do nothing for now...
end

