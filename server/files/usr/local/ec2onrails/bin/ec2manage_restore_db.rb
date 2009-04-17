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


RAILS_ROOT="/mnt/www/myfavorite-app1/current"
exit unless File.exists?(RAILS_ROOT)

require "rubygems"
require "optiflag"
require "fileutils"
require "#{File.dirname(__FILE__)}/../lib/mysql_helper"
require "#{File.dirname(__FILE__)}/../lib/s3_helper"
require "#{File.dirname(__FILE__)}/../lib/utils"

# Snapshots every 2 hours & fullbackup every night at 5:01 (see /etc/cron.d/ec2onrails) 
# 
# dump.sql.gz will be stored in location like
#   /ec2manage-staging/backup-2009-03-06-05-14/all-ec2-72-44-59-75/dump.sql.gz
#    ^^^^ bucket-base     ^^^^date&time       ^^^database ^^^^^host
#
#   incremental backup will look like...
#   /ec2manage-staging/backup-2009-03-06-05-13/all-ec2-72-44-59-75/mysql-bin.000004
# 
#   bucket = ec2manage-staging
#   dir = backup-2009-03-06-05-13/all-ec2-72-44-59-75
#

module CommandLineArgs extend OptiFlagSet
  optional_flag "bucket"
  optional_flag "dir"
  optional_flag "incremental"
  and_process!
end

s3_config = "#{RAILS_ROOT}/config/s3.yml"

# Create a AWS helper object
@aws   = Ec2onrails::AwsHelper.new s3_config

# Extract the default bucket information
bucket = ARGV.flags.bucket
bucket_base_name  = @aws.bucket_base_name
bucket = bucket || "#{bucket_base_name}"

# May be nil is specified as the directory
dir = ARGV.flags.dir 

# Connect
@s3 = Ec2onrails::S3Helper.new(bucket, dir, s3_config)

# Extract the list of backups 
# o
if ARGV.flags.incremental 
   keys = @s3.list_keys("incremental-backup")
else 
   keys = @s3.list_keys("full-backup")
end

puts "retrieving " + keys.first 
exit 0

@mysql = Ec2onrails::MysqlHelper.new
@temp_dir = "/mnt/tmp/ec2onrails-backup-#{@s3.bucket}-#{dir.gsub(/\//, "-")}"
if File.exists?(@temp_dir)
  puts "Temp dir exists (#{@temp_dir}), aborting. Is another backup process running?"
  exit
end

begin
  FileUtils.mkdir_p @temp_dir
  
  file = "#{@temp_dir}/dump.sql.gz"
  @s3.retrieve_file(file)
  @mysql.load_from_dump(file)
  
  @s3.retrieve_files("mysql-bin.", @temp_dir)
  logs = Dir.glob("#{@temp_dir}/mysql-bin.[0-9]*").sort
  logs.each {|log| @mysql.execute_binary_log(log) }
  
  @mysql.execute_sql "reset master" # TODO  maybe we shouldn't do this if we're not going to delete the logs from the S3 bucket because this restarts the numbering again
ensure
  FileUtils.rm_rf(@temp_dir)
end
