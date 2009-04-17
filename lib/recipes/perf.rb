Capistrano::Configuration.instance.load do

  namespace :ec2manage do 

    namespace :performance do 
      
      desc "Raw Disk I/O on /mnt" 
      task :raw_disk_io, :roles => :app do

        # Create a 10G file        
        file = "/mnt/tmp/10Gfile" 

        run "sh -c 'dd if=/dev/zero of=#{file} bs=1024M count=10'" 
        run "rm -f #{file}"
      end

      desc "EBS Disk I/O on /var/local" 
      task :raw_ebs_io, :roles => :app do

        # Create a 2G file        
        file = "/var/local/mnt/www/2Gfile" 
        
        run "sh -c 'dd if=/dev/zero of=#{file} bs=1024M count=2'" 
        run "rm -f #{file}"
      end

    end
  end  
end
