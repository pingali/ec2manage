#!/usr/bin/ruby

# The purpose of this script is suppress output of the zrm backup
# service. Otherwise the service generates too many mails. Only there
# is an error, a message must be sent to the support staff. A mail can
# be sent every 2-3 hours too. Change the condition at the end.

require 'rubygems' 
require 'fileutils'
require 'find'
require 'yaml' 
require 'optiflag' 


#################################################################
# Read the command line
#################################################################

module CommandLineArgs extend OptiFlagSet
  flag "backupset"
  flag "backuplevel"
  and_process!
end

backupset = ARGV.flags.backupset 
backuplevel = ARGV.flags.backuplevel 
unless backupset and backuplevel
  raise "Usage #{ARGV[0]} --backupset <set-name> --backuplevel [0|1]"
end


#################################################################
# Read the configuration file and set the global variables 
#################################################################

CONFIG_FILE = '/etc/ec2manage/ec2manage-zrm.conf'
unless File.exists?(CONFIG_FILE) and File.readable?(CONFIG_FILE) 
  raise "Configuration file missing or unreadable #{CONFIG_FILE}" 
end

config = YAML::load( File.read(CONFIG_FILE))
raise "Misconfigured file" unless config

#################################################################
# Create the log directory in case it doesnt exist
#################################################################
log_directory_prefix = config['zrm_backup_log'] || '/var/local/log/mysql-zrm'
log_directory = "#{log_directory_prefix}/#{backupset}"
unless File.exists?(log_directory) and File.directory?(log_directory)
  system("mkdir -p #{log_directory}")  
end

#################################################################
# Generate the output filename
#################################################################
t = Time.now
log_file = t.strftime("#{log_directory}/%Y%m%d%H%M%S")
#puts "Capturing output in #{log_file}"

# Now run the backup command and capture the output 
zrm_cmd = "/usr/bin/mysql-zrm-backup --backup-set #{backupset} --backup-level #{backuplevel}"
success = system("#{zrm_cmd} 2>>#{log_file} 1>>#{log_file}")

#=> Before you exit fix up the ownership 
# Correct the ownership 
#=> Misc information to be used later on 
username = `/usr/bin/id -un`
username.chop! 
if username == "root" 
  #puts "Modifying the ownership to mysql" 
  system("chown -R mysql:mysql #{log_directory_prefix}")
end

#=> If there is output, it is caught by cron and sent by email. So 
# output only if there is an error
unless success 
  system("cat #{log_file}")
  exit(1) 
end

exit(0)
