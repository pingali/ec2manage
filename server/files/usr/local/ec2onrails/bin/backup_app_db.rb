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
    
#exit if the current application is not deployed, meaning there is nothing to back up!
exit unless File.exists?("/mnt/app/current")
  
require "rubygems"
require "optiflag"
require "fileutils"
require 'EC2'
require "#{File.dirname(__FILE__)}/../lib/mysql_helper"
require "#{File.dirname(__FILE__)}/../lib/s3_helper"
require "#{File.dirname(__FILE__)}/../lib/aws_helper"
require "#{File.dirname(__FILE__)}/../lib/roles_helper"

require "#{File.dirname(__FILE__)}/../lib/utils"

# Only run if this instance is the db_pimrary
# The original code would run on any instance that had /etc/init.d/mysql
# Which was pretty much all instances no matter what role
include Ec2onrails::RolesHelper
exit unless in_role?(:db_primary)

    
module CommandLineArgs extend OptiFlagSet
  optional_flag "bucket"  
  optional_flag "dir"
  optional_switch_flag "incremental"
  optional_switch_flag "reset"
  optional_switch_flag "logical"
  and_process!
end
@mysql = Ec2onrails::MysqlHelper.new


if File.exists?("/etc/mysql/conf.d/mysql-ec2-ebs.cnf") and !ARGV.flags.logical 
  # we have ebs enabled....
        
  @aws   = Ec2onrails::AwsHelper.new
  vols = YAML::load(File.read("/etc/ec2onrails/ebs_info.yml"))
  ec2 = EC2::Base.new( :access_key_id => @aws.aws_access_key, :secret_access_key => @aws.aws_secret_access_key )
  
  #lets make sure we have space: AMAZON puts a 500 limit on the number of snapshots
  snaps = ec2.describe_snapshots['snapshotSet']['item'] rescue nil
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
      conn.query "FLUSH TABLES WITH READ LOCK;"
      
      res = conn.query "SHOW MASTER STATUS"
      logfile, position = res.fetch_row[0..1]
# puts "Snapshot occuring at: log: #{logfile}, #{position}"
      vols.each_pair do |mount, ebs_info|
        begin
          `sudo xfs_freeze -f #{mount}`
          output = ec2.create_snapshot(:volume_id => ebs_info['volume_id'])
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
  #not persisted, so lets push the binary log files to s3
  # include the hostname in the bucket name so test instances don't accidentally clobber real backups
  bucket = ARGV.flags.bucket
  dir = ARGV.flags.dir || "database"
  @s3 = Ec2onrails::S3Helper.new(bucket, dir)
  @temp_dir = "/mnt/tmp/ec2onrails-backup-#{@s3.bucket}-#{dir.gsub(/\//, "-")}"
  if File.exists?(@temp_dir)
    puts "Temp dir exists (#{@temp_dir}), aborting. Is another backup process running?"
    exit
  end

  begin
    FileUtils.mkdir_p @temp_dir
    if ARGV.flags.incremental
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
  ensure
    FileUtils.rm_rf(@temp_dir)
  end

end

