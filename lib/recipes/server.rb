Capistrano::Configuration.instance.load do

  namespace :ec2manage do 

    namespace :server do 

      desc <<-DESC
        Deploy a set of config files to the server from the templates.
      DESC
      task :deploy_files do

        # This is EC2onRails's copy of deploy_files. This should do some 
        # transformation of the templates (to be added in future) as well
        # based on the role
        if cfg[:server_config_files_root]
          begin
            filename = "config_files.tar"
            local_file = "#{Dir.tmpdir}/#{filename}"
            remote_file = "/tmp/#{filename}"
            FileUtils.cd(cfg[:server_config_files_root]) do
              File.open(local_file, 'wb') { |tar| Minitar.pack(".", tar) }
            end
            put File.read(local_file), remote_file
            sudo "tar xvf #{remote_file} -o -C /"
          ensure
            rm_rf local_file
            sudo "rm -f #{remote_file}"
          end
        end
      end 

      desc "Harden the server" 
      task :harden do 
        ec2onrails.server.allow_sudo do 
          sudo "rm -f /root/.mysql_history" 
        end
      end
      
      desc "Get the status of the server" 
      task :get_status do 
        ec2onrails.server.allow_sudo do 
          run "god status" 
        end
      end
      desc "Watch tail production log files" 
      task :watch_tail_logs, :roles => :app do
        run "tail -f #{shared_path}/log/production.log" do |channel, stream, data|
          puts  # for an extra line break before the host name
          puts "#{channel[:host]}: #{data}" 
          break if stream == :err    
        end
      end
      
      desc "remotely console" 
      task :console, :roles => :app do
        input = ''
        run "cd #{current_path} && ./script/console #{ENV['RAILS_ENV']}" do |channel, stream, data|
          next if data.chomp == input.chomp || data.chomp == ''
          print data
          channel.send_data(input = $stdin.gets) if data =~ /^(>|\?)>/
        end
      end
            
      desc "Install Splunk" 
      task :install_splunk do 
        
        ec2onrails.server.allow_sudo do
          
          # Prepare the splunk directories. Move them /opt because the
          # root file system has little space 
          sudo "sh -c \"mkdir -p /mnt/splunk/splunk /mnt/splunk/local && \
                ln -fs /mnt/splunk/splunk /opt/splunk && \
                ln -fs /mnt/splunk/local /opt/local\""
        
          # Download and install
          run "wget -c -q -O /tmp/splunk.deb 'http://www.splunk.com/index.php/download_track?file=3.4.5/linux/splunk-3.4.5-47883-linux-2.6-intel.deb&ac=ga0108_s_logmanagement&wget=true&name=wget&typed=releases' && sudo dpkg -i /tmp/splunk.deb"
          
          # Check the status
          package_status = quiet_capture("dpkg --status splunk")
          if !package_status.grep(/Status: install ok installed/)
            raise "Splunk may not have been installed. " 
          end
        end
      end
      
      desc "Configure Splunk" 
      task :configure_splunk do 
        
        ec2onrails.server.allow_sudo do
          
          # Copy the splunk configuration files.
          sudo "cp -ur  /etc/ec2manage/splunk/etc /opt/splunk"
          
          # Fix permissions
          sudo "chown -R splunk:splunk /opt/local" 
          sudo "chown -R splunk:splunk /opt/splunk"           
          
          # The install command will ask for acceptance of the license
          # etc.        
          sudo "/opt/splunk/bin/splunk start" do |channel, stream, data|
            puts data
            if data =~ /(license|changes)/
              channel.send_data "y\n"
            end
          end
          
          # Run splunk at boot time 
          sudo "/opt/splunk/bin/splunk enable boot-start -user  splunk"                     
          
          # Stop; restart it later...
          sudo "/opt/splunk/bin/splunk stop" 

        end        
      end

      desc "Install Zmanda" 
      task :install_zrm do 
        ec2onrails.server.allow_sudo do
          
          # Download and install
          run "wget -c -q -O /tmp/zrm.deb 'http://www.zmanda.com/downloads/community/ZRM-MySQL/2.1/Debian/mysql-zrm_2.1_all.deb'"
          sudo "dpkg -i /tmp/zrm.deb"
          
          # Check the status
          package_status = quiet_capture("dpkg --status zrm")
          if !package_status.grep(/Status: install ok installed/)
            raise "MySQL ZRM may not have been installed. "
          end
        end
      end

      desc "Configure zrm" 
      task :configure_zrm do 
        
        ec2onrails.server.allow_sudo do
          
          #The backup should be performed on another EBS volume? 
          
          run "mkdir -p /mnt/mysql-zrm/backup" 
          run "mkdir -p /var/local/mnt/www/mysql-zrm/reports/html" 

          # Fix ownerships
          sudo "chown -R mysql:mysql /etc/mysql-zrm"
          sudo "chown -R mysql:mysql /var/local/mnt/www/mysql-zrm"
          
          # Make sure apache configuration is in place 
          sudo "a2ensite mysql-zrm" 

        end

      end

      desc "Configure munin" 
      task :configure_munin do 

        ec2onrails.server.allow_sudo do
          
          #The backup should be performed on another EBS volume? 
          
          sudo "mkdir -p /mnt/log/munin"
          sudo "sh -c 'test ! -d /mnt/www/munin && mv /var/www/munin /mnt/www/munin'"
          sudo "ln -fs /mnt/www/munin /var/www/munin" 

          # Fix ownerships
          sudo "chown -R munin:munin /mnt/log/munin"
          sudo "chown -R munin:munin /mnt/www/munin"

          # Make sure apache configuration is in place 
          sudo "a2ensite munin" 
        end

      end

      desc "Install ec2manage-specific packages" 
      task :install_packages do 
        install_splunk
        install_zrm 
      end

      desc "Configure ec2manage-specific packages" 
      task :configure_packages do 
        configure_splunk 
        configure_zrm 
        configure_munin
      end
      
      desc "MySQL ZRM status" 
      task :backup_status, :roles => [ :db ] do 
        ec2onrails.server.allow_sudo do 
          run %{sudo -u mysql  mysql-zrm-reporter --where backup-set=app1 --show backup-status-info}
        end
      end

      desc "MySQL ZRM performance" 
      task :backup_performance, :roles => [ :db ] do 
        ec2onrails.server.allow_sudo do 
          run %{sudo -u mysql  mysql-zrm-reporter --where backup-set=app1 --show backup-performance-info}
        end
      end

      desc "MySQL ZRM restore information" 
      task :backup_restore_info, :roles => [ :db ] do 
        ec2onrails.server.allow_sudo do 
          run %{sudo -u mysql  mysql-zrm-reporter --where backup-set=app1 --show backup-restore-info}
        end
      end

      desc "MySQL ZRM restore" 
      task :backup_restore, :roles => [ :db ] do 
        cfg = ec2onrails_config         
        ec2onrails.server.allow_sudo do 
          run %{sudo -u mysql  mysql-zrm-restore --user=#{cfg[:db_zrm_restore_user]} --password=#{cfg[:db_zrm_password]} --backup-set app1 --source-directory=/mnt/mysql-zrm/backup/app1/20090326052742}
        end
      end
      
      desc "Tunnel to port 8000@master" 
      task :ssh_tunnel_to_splunk do 
        host = find_servers_for_task(current_task).first.host
        privkey = ssh_options[:keys][0]
        
        puts "This cmd will open a terminal. Connection will be on until " +
          "you exit the terminal"
        run_local "ssh -l root -i #{privkey} -L:12800:localhost:12800 root@#{host}"
      end

      desc "Tunnel to (ZRM)18001@master" 
      task :ssh_tunnel_to_zrm do 
        host = find_servers_for_task(current_task).first.host
        privkey = ssh_options[:keys][0]
        
        puts "This cmd will open a terminal. Connection will be on until " +
          "you exit the terminal"
        run_local "ssh -l root -i #{privkey} -L:18001:localhost:18001 root@#{host}"
      end

      desc "Tunnel to (Munin)18002@master" 
      task :ssh_tunnel_to_munin do 
        host = find_servers_for_task(current_task).first.host
        privkey = ssh_options[:keys][0]
        
        puts "This cmd will open a terminal. Connection will be on until " +
          "you exit the terminal"
        run_local "ssh -l root -i #{privkey} -L:18002:localhost:18002 root@#{host}"
      end
      
      desc "Tunnel to (MySQL) 3306@master"
      task :ssh_tunnel_to_mysql do 
        host = find_servers_for_task(current_task).first.host
        privkey = ssh_options[:keys][0]
        
        puts "This cmd will open a terminal. Connection will be on until " +
             "you exit the terminal"
        run_local "ssh -l root -i #{privkey} -L:5000:localhost:3306 root@#{host}"
        puts "Connect using: mysql -u root -P 5000" 
      end
      
      
      desc "Make /mnt/app a link" 
      task :make_app_symlink do 
        
        # Move app 
        mnt_app_dir_exists = true if quiet_capture("test -d /mnt/app || echo 'something'").empty?
        
        if mnt_app_dir_exists 
          ec2onrails.server.allow_sudo do 
            
            sudo "sh -c 'test ! -d /mnt/www && mkdir -p /mnt/www && chown -R app:app /mnt/www'"
            sudo "sh -c 'mv /mnt/app /mnt/www/#{application} && ln -fs /mnt/www/#{application} /mnt/app'"
            
          end
        end
      end
      
      
      desc "Connect to instance" 
      task :ssh_connection do 
        host = find_servers_for_task(current_task).first.host
        privkey = ssh_options[:keys][0]
        
        puts "This cmd will open a terminal to #{host}. Connection will " +
             "be on until you exit the terminal"
        run_local "ssh -l root -i #{privkey} #{host}"
      end
      
    end
  end  
end
