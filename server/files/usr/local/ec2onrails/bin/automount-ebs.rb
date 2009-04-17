#!/usr/bin/ruby

# Automatically mount the EBS volume if it has been specified as part
# of the user-data. The user-data must also specify the 

require 'rubygems'
require 'right_aws'
require 'net/http'
require 'yaml' 
require 'fileutils' 

#example_instance_id = "i-1231132" 
#example_user_data =<<END
#---
#aws_access_key_id: jhsdfjhdsfjh128782137abdja
#aws_secret_access_key: jhsdfjhdsfjh128782137abdja
#ebs_volumes: 
# - dev: /dev/sdh 
#   vol_id: vol-172518
#   mount_point: /var/local 
# - dev: /dev/sdi
#   vol_id: vol-121222
#   mount_point: /mnt/local
#END
#user_data = example_user_data 
#instance_id = example_instance_id 

##################################################
#=> Extract information from the meta-data
##################################################
url = 'http://169.254.169.254/2008-02-01/meta-data/instance-id'
instance_id = Net::HTTP.get_response(URI.parse(url)).body

#=> Get the user data from the launch and use it to 
url_user_data = 'http://169.254.169.254/2008-02-01/user-data'
user_data = Net::HTTP.get_response(URI.parse(url_user_data)).body

#=> Read the configuration file 
begin 
  config = YAML::load(user_data)
rescue Exception => e
  raise "Configuration provided in user-data is incorrect. Exact error message is: #{e.message}" 
end

##################################################
#=> Connect to AWS 
##################################################
aws_access_key_id = config['aws_access_key_id'] 
aws_secret_access_key = config['aws_secret_access_key'] 
begin 
  ec2 = RightAws::Ec2.new(aws_access_key_id, aws_secret_access_key)
rescue Exception => e  
  raise "Unable to connect to EC2. Check the access/secret ids. Exact error message is: #{e.message}" 
end


##################################################
#=> For each volume, extract the information and mount the device
##################################################
ebs_volumes = config['ebs_volumes']
ebs_volumes.each do |ebs| 
  dev         = ebs['dev']
  vol_id      = ebs['vol_id']
  mount_point = ebs['mount_point']

  puts "auto mounting #{vol_id} as #{dev} on #{instance_id}:#{mount_point}" 
  vol = ec2.attach_volume(vol_id, instance_id, dev)
  
  #=> Wait until the device has been attached
  count = 5
  while count > 0 do
    break if (File.exists?(dev) and File.blockdev?(dev))
    sleep 20 
  end
  
  #=> Now mount the device
  if (File.exists?(dev) and File.blockdev?(dev))
    system('mkdir -p #{mount_point}')
    system('mount #{dev} #{mount_point}')
  else
    puts "Unable to mount #{vol_id} as #{dev} on #{instance_id}:#{mount_point}" 
  end
  
end
