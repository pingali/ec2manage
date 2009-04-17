#!/usr/bin/ruby

# Simple command that sets up the twitter account in case 
# it is not already there

# Use this as /usr/local/ec2onrails/bin/ec2manage_twitter.rb --post <message>

require 'rubygems' 
require 'yaml' 
require 'optiflag' 
require 'twitter' 

#################################################################
# Read the command line
#################################################################

module CommandLineArgs extend OptiFlagSet
  flag "post"
  and_process!
end


#################################################################
# Read the configuration file and set the global variables 
#################################################################

CONFIG_FILE = '/etc/ec2manage/ec2manage-twitter.conf'
unless File.exists?(CONFIG_FILE) and File.readable?(CONFIG_FILE) 
  raise "Configuration file missing or unreadable #{CONFIG_FILE}" 
end

config = YAML::load( File.read(CONFIG_FILE))
raise "Misconfigured file" unless config

username = config['username']
password = config['password']

raise "Unknown twitter user and password" unless (username and password)

#################################################################
# Now post the update 
#################################################################
if ARGV.flags.post
  message = ARGV.flags.post 
  twitter = Twitter::Base.new(username, password)
  twitter.post(message) 
end
