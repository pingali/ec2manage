#!/usr/bin/env ruby

#
# http://pauldowman.com/2008/02/17/smtp-mail-from-ec2-web-server-setup/
#
# This is a simple script to send mail via an alternate server when
# there are errors with the normal queueing mail sender. The subject
# is the first command-line arg and the body is received on stdin

#################################
# Load the configuration from /etc/ec2manage/ec2manage-mail.conf'
#################################
require 'yaml'

CONFIG_FILE = '/etc/ec2manage/ec2manage-mail.conf'
unless File.exists?(CONFIG_FILE) and File.readable?(CONFIG_FILE) 
  raise "Configuration file missing or unreadable #{CONFIG_FILE}" 
end

config = YAML::load( File.read(CONFIG_FILE))
raise "Misconfigured file" unless config

from_address             = config['from_address']
from_name                = config['from_name']
to_address               = config['to_address']
to_name                  = config['to_name']
smtp_server              = config['smtp_server']
smtp_port                = config['smtp_port']
smtp_mail_from_domain    = config['smtp_mail_from_domain']
smtp_account_name        = config['smtp_account_name']
smtp_password            = config['smtp_password']
smtp_authentication_type = config['smtp_authentication_type']
debug                    = config['debug']

#################################
# Construct the message
#################################

subject = ARGV[0]
body = $stdin.read

require 'rubygems'
require 'net/smtp'
require 'tlsmail'

exit if body.nil? || body == ""

msgstr = <<END_OF_MESSAGE
From: #{from_name} <#{from_address}>
To:  #{to_name} <#{to_address}>
Subject: #{subject}
Date: #{Time.now.getlocal}

#{body}
END_OF_MESSAGE

#################################
# Send the message
#################################
begin 

  #Net::SMTP.enable_tls(OpenSSL::SSL::VERIFY_NONE)
  smtp = Net::SMTP.new(smtp_server, smtp_port)
  smtp.set_debug_output $stderr if debug

  puts "Sending out message #{msgstr}" 

  smtp.start(smtp_mail_from_domain, smtp_account_name, smtp_password, smtp_authentication_type) do |s|
    puts "Connected...sending" 
    s.send_message msgstr, from_address, to_address
    puts "Connected...completed delivery" 
  end
rescue Exception => e 
  puts "#{ e } (#{ e.class })!" + e.message
end
