
require 'open-uri'

Capistrano::Configuration.instance.load do

  namespace :ec2manage do 
    namespace :server do 
    
      desc "Register host" 
      task :update_dns do 
      
        name = ENV['NAME'] || 'master' 
        
        prefix = "http://www.dnsmadeeasy.com/servlet/updateip?"
        role_assignment = host_config['role_assignment'] 
        dns_config = read_config('dns.yml', :erb => true)
        
        if role_assignment[name]['dns']
        
          # config/hosts.yml
          #
          #master: 
          #  host: ec2-174-129-105-82.compute-1.amazonaws.com
          #  localhost: domU-12-31-39-03-BC-E8.compute-1.internal
          #  dns:
          #    - alias: dbmaster
          #      use: host
          #    - alias: dbmaster-int
          #      use: localhost
          
          # config/dns.yml 
          #
          #domainname: myfavoritedomain.com
          #username: myname
          #hosts:
          #  - dbmaster: 
          #    ddnsid: yyy
          #    password: xxxx
          #  - dbmaster-int: 
          #    ddns_id: yyyy
          #    ddns_password: jjjj
          
        

          # First gather the required information
          # Resolve host information first. 
          hostmap = {}
          aws_name = role_assignment[name]['host']
          aws_ip = `host #{aws_name} | cut -d' ' -f4`
          hostmap['host'] = { 
            'aws_ip' => aws_ip.strip,
            'aws_name' => aws_name
          }
          
          # This must be resolved on the remote host
          aws_name = role_assignment[name]['localhost']
          aws_ip = quiet_capture("host #{aws_name} | cut -d' ' -f4")
          hostmap['localhost'] = { 
            'aws_ip' => aws_ip.strip,
            'aws_name' => aws_name
          }        
          
          
          # From the dns 
          username = dns_config['username'] 
          
          # For each of the dns registrations to be performed...
          all_dns_entries = role_assignment[name]['dns']
          all_dns_entries.each do |entry|
            
            dns_alias = entry['alias'] # dbmaster
            use_name = entry['use'] # This is host/localhost
            aws_ip = hostmap[use_name]['aws_ip']
            
            # See if you can find the dnsname in the dns.yml 
            unless dns_config['hosts'][dns_alias] 
              puts "There is no dns.yml setting corresponding to host"+
                   " #{dns_alias} "
              next
            end
          
            ddns_id  = dns_config['hosts'][dns_alias]['ddns_id']
            ddns_password  = dns_config['hosts'][dns_alias]['ddns_password']
            
            unless username and ddns_password and ddns_id and aws_ip
              puts "Error in the configuration for #{dns_alias}"
              next 
            end
            
            # Now we are ready to construct the URL 
            #http://www.dnsmadeeasy.com/servlet/updateip?username=xxx&password=yyy&id=3991712&ip=1.2.3.4
            url = prefix + 
              "username=#{username}" +
              "&password=#{ddns_password}" + 
              "&id=#{ddns_id}" + 
              "&ip=#{aws_ip}" 
            
            #puts url 
            #puts hostmap.inspect 
            #puts url.inspect 
            
            
            # print the first three lines
            open(url) do |f|
              no = 1
              f.each do |line|
                print "[#{dns_alias}] update status: #{line}"
                no += 1
                break if no > 4
              end
              
            end
          end
        end
      end
    end
  end
end
