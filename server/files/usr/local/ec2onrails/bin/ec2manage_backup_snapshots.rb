#!/usr/bin/ruby
      
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
    
# exit if the current application is not deployed, meaning there is
# nothing to back up!
#

RAILS_ROOT="/mnt/www/myfavorite-app1/current"
exit unless File.exists?(RAILS_ROOT)
  

# Snapshots every 2 hours & fullbackup every night at 5:01 (see /etc/cron.d/ec2onrails) 
# 
# dump.sql.gz will be stored in location like
#   /ec2manage-staging/full-backup-2009-03-06-05-14/all-ec2-72-44-59-75/dump.sql.gz
#    ^^^^ bucket-base     ^^^^date&time       ^^^database ^^^^^host
#
#   incremental backup will look like...
#   /ec2manage-staging/incremental-backup-2009-03-06-05-13/all-ec2-72-44-59-75/mysql-bin.000004
#

require "rubygems"
require "optiflag"
require "fileutils"
require 'EC2'
require "#{File.dirname(__FILE__)}/../lib/mysql_helper"
require "#{File.dirname(__FILE__)}/../lib/s3_helper"
require "#{File.dirname(__FILE__)}/../lib/aws_helper"
require "#{File.dirname(__FILE__)}/../lib/roles_helper"
require "#{File.dirname(__FILE__)}/../lib/backup_helper"
require "#{File.dirname(__FILE__)}/../lib/utils"


###############################################################
# Configuration...
###############################################################

# Only run if this instance is the db_pimrary
# The original code would run on any instance that had /etc/init.d/mysql
# Which was pretty much all instances no matter what role
include Ec2onrails::RolesHelper
exit unless in_role?(:db_primary)
    
module CommandLineArgs extend OptiFlagSet
  optional_flag "bucket"  
  optional_flag "dir"
  optional_flag "num_backups"
  optional_switch_flag "incremental"
  optional_switch_flag "reset"
  optional_switch_flag "logical"
  and_process!
end

# Configuration files from the myfavorite-app1 deployment
s3_config = "#{RAILS_ROOT}/config/s3.yml"
database_config = "#{RAILS_ROOT}/config/database.yml"

# Backups happen every 5 mins. so keep one days' worth of backups.
max_incremental_backups =  ARGV.flags.num_backups || ((60*24)/5)

# Read the other configuration files 
@mysql = Ec2onrails::MysqlHelper.new database_config
@aws   = Ec2onrails::AwsHelper.new s3_config

if File.exists?("/etc/mysql/conf.d/mysql-ec2-ebs.cnf") and !ARGV.flags.logical 
  
  ##################################################
  # Obtain the snapshots 
  ##################################################

  # we have ebs enabled....
        
  vols = YAML::load(File.read("/etc/ec2onrails/ebs_info.yml"))
  ec2 = EC2::Base.new( :access_key_id => @aws.aws_access_key, :secret_access_key => @aws.aws_secret_access_key )
  
  #puts "aws = " + @aws.inspect
  #puts "vols = " + vols.inspect
  #puts "ec2 = " + ec2.inspect

  #lets make sure we have space: AMAZON puts a 500 limit on the number of snapshots
  snaps = ec2.describe_snapshots['snapshotSet']['item'] rescue nil
  #puts "snaps = " + snaps.inspect
  if snaps && snaps.size > 450
    # TODO:
    # can we make this a bit smarter?  With a limit of 500, that is difficult.  
    # possible ideas (and some commented out code below)
    #  * only apply cleanups to the volume_ids attached to this instance
    #  * keep the last week worth (at hrly snapshots), then daily for a month, then monthly
    #  * a sweeper task 
    #
    # vol_ids = []
    # vols.each_pair{|k,v| vol_ids << v['volume_id']}
    # #lets only work on those that apply for these volumnes attached 
    # snaps = snaps.collect{|sn| vol_ids.index(sn['volumeId']) ? sn : nil}.compact
    # # get them sorted
    snaps = snaps.sort_by{|snapshot| snapshot['startTime']}.reverse
    curr_batch = {}
    remaining = []
    snaps[200..-1].each do |sn| 
      next if sn.blank? || sn['status'] != 'completed'
      today = Date.parse(sn['startTime']).to_s
      if curr_batch[sn['volumeId']] != today
        curr_batch[sn['volumeId']] = today
        remaining << sn
      else
        ec2.delete_snapshot(:snapshot_id => sn['snapshotId'])
      end
      # next unless vol_ids.index(sn['volumeId'])
    end
    if remaining.size > 400
      puts "  WARNING: still contains #{remaining.size} snapshots; removing the oldest 100 to clean up space"
      remaining[350..-1].each do |sn|
        ec2.delete_snapshot(:snapshot_id => sn['snapshotId'])
      end
    end
  else
    puts "Could not retrieve snapshots: auto archiving cleanup will not occur" unless snaps
  end
  
  @mysql.execute do |conn|
    begin
      #puts "Running mysql commands" 
      conn.query "FLUSH TABLES WITH READ LOCK;"
      
      res = conn.query "SHOW MASTER STATUS"
      logfile, position = res.fetch_row[0..1]
      puts "Snapshot occuring at: log: #{logfile}, #{position}"
      vols.each_pair do |mount, ebs_info|
        begin
          `sudo xfs_freeze -f #{mount}`
          output = ec2.create_snapshot(:volume_id => ebs_info['volume_id'])
          puts "Snapshot of #{ebs_info['volume_id']}: #{output.inspect}"
          snap_id = output['CreateSnapshotResponse']['snapshotId'] rescue nil
          snap_id ||= output['snapshotId'] rescue nil #this is for the old version of the amazon-ec2
          if snap_id.nil? || snap_id.empty?
            puts "Snapshot for #{ebs_info['volume_id']} FAILED"
            exit
          end
          vol_id  = ebs_info['volume_id']
       ensure
          `sudo xfs_freeze -u #{mount}`
        end
      end
    ensure
      conn.query <<-SQL
      UNLOCK TABLES;
      SQL
    end
  end

else

  ##################################################
  # Logical backups...
  ##################################################

  #not persisted, so lets push the binary log files to s3 include the
  # hostname in the bucket name so test instances don't accidentally
  # clobber real backups

  bucket = ARGV.flags.bucket

  if ARGV.flags.incremental
     prefix = "incremental"
  else 
     prefix = "full"
  end
  
  #=> Generate the bucket name, directory names
  t = Time.now
  backup_t = t.strftime("#{prefix}/backup-%Y-%m-%d-%H-%M")
  bucket_base_name  = @aws.bucket_base_name
  bucket = bucket || "#{bucket_base_name}"

  # directory in which the backup will be stored
  dir = ARGV.flags.dir || "#{backup_t}/all-#{Ec2onrails::Utils.hostname}"
  @s3 = Ec2onrails::S3Helper.new(bucket, dir, s3_config )

  #=> temp directory for dumping database
  @temp_dir = "/mnt/tmp/ec2onrails-backup-#{@s3.bucket}-#{dir.gsub(/\//, "-")}"
  if File.exists?(@temp_dir)
    puts "Temp dir exists (#{@temp_dir}), aborting. Is another backup process running?"
    exit
  end

  begin
    FileUtils.mkdir_p @temp_dir

    if ARGV.flags.incremental
      
      #=> Keep only last n around.
      keys = @s3.list_keys_2("incremental/backup-")
      if keys and ! keys.empty?
        keys_to_be_removed = Ec2onrails::Utils.extract_keys_to_be_removed(keys, max_incremental_backups) 
        #puts "Number of keys: #{max_incremental_backups}"
        #puts "To remove: " + keys_to_be_removed.inspect 
        keys_to_be_removed.each do |k|
          puts "Removing #{k}"
          @s3.delete_files_2(k)
        end
      end

      # Incremental backup
      @mysql.execute_sql "flush logs"
      logs = Dir.glob("/mnt/log/mysql/mysql-bin.[0-9]*").sort
      logs_to_archive = logs[0..-2] # all logs except the last
      logs_to_archive.each {|log| @s3.store_file log}
      @mysql.execute_sql "purge master logs to '#{File.basename(logs[-1])}'"
            
    else

      # Full backup
      file = "#{@temp_dir}/dump.sql.gz"
      @mysql.dump(file, ARGV.flags.reset)
      @s3.store_file file
      @s3.delete_files("mysql-bin")
      
    end
    
    # Store the status 
    @mysql.execute do |conn|
      # Store the bin position as well 
      file = "#{@temp_dir}/status.txt"
      res = conn.query "SHOW MASTER STATUS"
      logfile, position = res.fetch_row[0..1]
      notes = "log: #{logfile}, #{position}"
      File.open(file, 'w') {|f| f.write(notes) }
      @s3.store_file file
    end

  ensure
    FileUtils.rm_rf(@temp_dir)
  end

end

