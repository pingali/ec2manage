Capistrano::Configuration.instance.load do

  namespace :ec2manage do 

    namespace :ami do 
      
      desc "Install Java" 
      task :install_java do 
        ec2onrails.server.allow_sudo do 
          sudo "aptitude install -y sun-java6-jre" do |channel, stream, data|
            puts data
            if data =~ /ok/ 
              channel.send_data "\r\n"
            end
            if data =~ /terms/ 
              channel.send_data "y\r\n"
            end
          end
        end
      end
      

      before "ec2manage:ami:bundle_instance", "ec2manage:ami:install_java" 

      desc "Bundle a deployed instance" 
      task :bundle_cleanup do

        if !quiet_capture("mount | grep -inr '/mnt/img-mnt' || echo ''").empty?
          sudo "umount /mnt/img-mnt"
        end

        sudo "rm -rf /mnt/aws-config" 
        sudo "rm -rf /mnt/image" 
        sudo "rm -rf /mnt/image.*" 
        sudo "rm -rf /mnt/img-mnt"         
      end

      desc "Bundle a deployed instance" 
      task :bundle_instance do
        
        s3 = read_config(s3_config, {:erb => true})
        s3_prefix='production'

        ec2onrails.server.allow_sudo do 
          
          # Cleanup
          ec2manage.ami.bundle_cleanup

          # Bundle 
          set :bundle, host_config['bundle'] 
          
          # capture the entire instance including /mnt 
          # except /var/local - which is EBS volume 
          
          host = find_servers_for_task(current_task).first.host
          privkey = ssh_options[:keys][0]
          
          msg =<<-END

  Uploading your AWS cert and key to /tmp on the instance.
           
      cert: #{bundle['cert']}
      key: #{bundle['key']}
            

  Your first key in ssh_options[:keys] #{privkey}, presumably thats
  your EC2 private key. The private key will be copied to the host
  named '#{host}'. Continue? [y/n]
      END

          choice = get_user_approval(msg)
          if choice == "y"
            
            # Generate the configuration file 
            sudo "mkdir -p /mnt/aws-config"             
            run_local "scp -i '#{privkey}' #{bundle['cert']} root@#{host}:/mnt/aws-config/cert.pem"
            run_local "scp -i '#{privkey}' #{bundle['key']} root@#{host}:/mnt/aws-config/pk.pem"
            config =<<-END
KEY_FILE_NAME=pk.pem
CERT_FILE_NAME=cert.pem 
BUCKET_BASE_NAME=ec2manage-ec2onrails-ami
AWS_ACCOUNT_ID=#{s3[s3_prefix]['aws_account_id']} 
AWS_ACCESS_KEY_ID=#{s3[s3_prefix]['aws_access_key']}
AWS_SECRET_ACCESS_KEY=#{s3[s3_prefix]['aws_secret_access_key']}
EXTRA_EXCLUDE_DIRS=#{mysql_dir_root}
export AWS_ACCOUNT_ID
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export EXTRA_EXCLUDE_DIRS 
           END
            put config, "/tmp/config" 
            sudo "mv /tmp/config /mnt/aws-config/config" 
            
            # execute the rebuild command
            sudo "sh /usr/local/ec2onrails/bin/rebundle.sh" do |channel, stream, data|
              puts data 
              if data =~ /arch/ 
                channel.send_data("i386\n")
              end
              if (data =~ /continue/)
                channel.send_data("y\n")
              end
              
            end

            # Cleanup
            ec2manage.ami.bundle_cleanup            

          end
        end
      end
      
      desc "Prepare a system created from snapshot" 
      task :process_deployed_host_image do 
        
        ec2onrails.server.allow_sudo do 
          
          # Check if the device has been attached
          dev_exists = true if quiet_capture("test -e /dev/sdh || echo 'something'").empty?
          unless dev_exists
            raise "/dev/sdh does not exist"
          end
          
          # First mount the volume 
          volume_mounted = true if !quiet_capture("mount | grep -inr 'sdh' || echo ''").empty?
          if !volume_mounted
            sudo "sh -c 'mkdir -p #{mysql_dir_root} && mount -a 2>/dev/null' "
          end
          
          var_dir_exists = true if quiet_capture("test -d #{mysql_dir_root} || echo 'something'").empty?
          volume_mounted = true if !quiet_capture("mount | grep -inr 'sdh' || echo ''").empty?
          unless var_dir_exists and volume_mounted
            raise "#{mysql_dir_root} has not been created or mounted!"
          end

          #sync up the code 
          #sudo "rsync -a #{mysql_dir_root}/mnt/www /mnt" 
          #sudo "rsync -a #{mysql_dir_root}/mnt/splunk /mnt" 
          ec2manage.files.initialize_host_directories_with_ebs
          
          # Create the appropriate link
          #app_dir_exists = true if quiet_capture("test -d /mnt/app || echo 'something'").empty?
          app_dir_exists = true if quiet_capture("test -d /mnt/www/myfavorite-app1 || echo 'something'").empty?
          
          if app_dir_exists
            sudo "sh -c 'mv /mnt/app /mnt/app.old && ln -fs /mnt/www/myfavorite-app1 /mnt/app'" 
          end

          # Create the appropriate link
          mysql_dir_exists = true if quiet_capture("test -d /mnt/mysql_data || echo 'something'").empty?
          
          if mysql_dir_exists
            sudo "sh -c 'mv /mnt/mysql_data /mnt/mysql_data.old && ln -fs #{mysql_dir_root}/mysql_data /mnt/mysql_data'" 
          end
          
          sudo "sh -c 'mkdir -p /mnt/tmp/mysql && chmod -R 777 /mnt/tmp'"

        end        
      end

      desc "Reboot a processed host"
      task :reboot_processed_deployed_host_image do 

        ec2onrails.server.allow_sudo do 
          sudo "reboot now" 
        end
      end

    end
  end
end
