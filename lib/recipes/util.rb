# This is from
#http://groups.google.com/group/ec2-on-rails-discuss/browse_thread/thread/5f1aa6bf4561c62c

require 'right_aws' 

#---------------------------------------------------
#
# Misc functions that are used by deploy.rb and this file.
#
#---------------------------------------------------

def full_path (caller, config_file) 
  File.join(File.dirname(caller), "/", config_file)
end

# Assumes that hosts.yml is in config directory
def read_config (config_file, opts = {}) 
  
  unless config_file.grep(/^\//).empty?
    config_file_path = config_file
  else 
    config_file_path = File.join(File.dirname(__FILE__), "/../../config/", config_file)    
  end

  data = begin 
           data = File.read(config_file_path)
           if opts[:erb]
             result   = ERB.new(data).result(binding)
             # This is to take care of the inclusion of other
             # yml files...
             while !result.grep(/<\%/).empty? 
               result   = ERB.new(result).result(binding)
             end
           else 
             result = data
           end
           YAML.load(result)
         rescue Exception => e
           puts "Error! Unable to read the file. " + e
         end    
  #puts data.inspect
  data 
end

def get_user_approval(msg)

  choice = nil
  while choice != "y" && choice != "n"
    choice = Capistrano::CLI.ui.ask(msg).downcase
    msg = "Please enter 'y' or 'n'."
  end
  choice
end

def list_ec2_hosts (aws_access_key_id, aws_secret_access_key) 
  begin 
    @ec2   = RightAws::Ec2.new(aws_access_key_id, aws_secret_access_key)
    instances = @ec2.describe_instances
  rescue 
    puts "Unknown error! " 
  end
end

# Extract host config information and generate roles based on
# that...
def assign_roles (config)
  
  role_assignment = config['role_assignment']
  role_assignment.each_key do |name| 
    
    h    = role_assignment[name]
    host = h['host'] 
    id   = h[id] 
    
    #puts "name = #{name} host = #{host}"
    next if ENV['NAME'] and name != ENV['NAME']
    
    h['roles'].each do |r| 

      #puts "role = #{r.inspect}"
      
      case r['role']
      when 'web': 
          role :web, host
      when 'app':
          role :app, host
      when 'memcache':
          role :memcache, host
      when 'db':
          if r['slave'] 
            master_name = r['master_name']
            master_host = role_assignment[master_name]['localhost']
            if r['volume'] 
              role :db, host, :master => master_host, 
                :primary => false, :ebs_vol_id => r['volume']
            else
              role :db, host, :master => master_host, :primary => false
            end
          else
            if r['volume'] 
              role :db, host, :primary => true, :ebs_vol_id => r['volume']
            else
              role :db, host, :primary => true
            end
          end
      end
    end    
  end
end

