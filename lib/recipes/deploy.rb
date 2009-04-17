Capistrano::Configuration.instance.load do

  # This is from
  #http://groups.google.com/group/ec2-on-rails-discuss/browse_thread/thread/5f1aa6bf4561c62c

  require 'right_aws' 

  namespace :ec2manage do 

    namespace :deploy do 
      
      desc "List hosts and roles " 
      #task :list_host_roles, :roles => [ :web, :app, :db ] do
      task :list_host_roles do 
        role_assignment = host_config['role_assignment']
        puts "Role\t\tHost"
        puts "----------------------------------------------"
        role_assignment.each_key do |name| 
          r = role_assignment[name] 
          host = r['host'] 
          next if ENV['NAME'] and name != ENV['NAME']
          puts "#{name.ljust(10, ' ')}\t#{host}"
        end
      end

      
      desc "The spinner task is used by :cold_deploy to start the application up"
      task :spinner, :roles => [:app] do
        run "/etc/init.d/mongrel start" 
      end
      
      desc "Setup /mnt/www" 
      task :host_setup do 
        ec2onrails.server.allow_sudo do 

          sudo "mkdir -p /mnt/www" 
          sudo "chown -R app:app /mnt/www"
          
          sudo "mkdir -p /mnt/tmp/mysql" 
          sudo "chown -R mysql:mysql /mnt/tmp/mysql"
          
        end
      end

      desc "Upload files that are specific to ec2manage" 
      task :shared_files, :roles => [:app] do 
        
        # Assumes a variable shared_file_list
        
        shared_files_list.each_pair do |filename, localpath| 
          data = File.read(localpath)
          put data, "/tmp/#{filename}", :mode => 0644 
          run "mv /tmp/#{filename} #{shared_path}/system/#{filename}"
        end

      end
      
      
      desc "Symbolic linking after deploy"
      task :symlink, :roles => [:app] do
        #run "sed -e \"s/^# ENV/ENV/\" -i #{current_path}/config/environment.rb"        
        shared_files_list.each_pair do |filename, localpath| 
          run "ln -nfs #{shared_path}/system/#{filename} #{current_path}/config/#{filename}"
        end
      end
      
      desc "    Uploads the private key to the AWS instance" 
      task :upload_root_pvt_key_to_server  do
        
        host = find_servers_for_task(current_task).first.host
        privkey = ssh_options[:keys][0]
        
        msg = <<-MSG
         Your first key in ssh_options[:keys] is #{privkey}, presumably thats
         your EC2 private key. The private key will be copied to the host
         named '#{host}'. Continue? [y/n]
         MSG
        
        choice = get_user_approval(msg)
        if choice == "y"
          
          pvt_key_exists = true if quiet_capture("test -e /home/app/.ssh/id_rsa || echo ''").empty?
          config_updated = true if quiet_capture("grep id_rsa /home/app/.ssh/config || echo ''").empty?
        
        if pvt_key_exists
          puts "Private key has already been uploaded" 
        else
          run_local "scp -i '#{privkey}' #{privkey} app@#{host}:.ssh/id_rsa"
        end
          
          unless config_updated
            run "echo \"IdentityFile /home/app/.ssh/id_rsa\" >> /home/app/.ssh/config"
          end
        end
      end
      
      desc "    Uploads the git key to the AWS instance" 
      task :upload_git_private_key  do
        
        host = find_servers_for_task(current_task).first.host
        
        privkey = ssh_options[:keys][0]
        
        # Find the git key to upload...
        gitkey = nil
        ssh_options[:keys].each do |key| 
          if !gitkey and key.match(/git/)
            gitkey = key
          end
        end
        
        msg = <<-MSG
      Uploading GitHub private key. Your EC2 private key is assumed to 
      be ssh_options[:keys][0]= #{privkey} and the git key is #{gitkey}. 
      The git private key will be copied to the host named '#{host}'. 
      Continue? [y/n]
      MSG
        
        choice = nil
        while choice != "y" && choice != "n"
          choice = Capistrano::CLI.ui.ask(msg).downcase
          msg = "Please enter 'y' or 'n'."
        end
        
        if choice == "y"
          
          git_key_exists = true if quiet_capture("test -e /home/app/.ssh/pk-git || echo 'something'").empty?
          config_updated = true if quiet_capture("grep GitHub /home/app/.ssh/config || echo 'something'").empty?
          
          if git_key_exists
            puts "GitHub private key has already been uploaded" 
          else
            run_local "scp -i '#{privkey}' #{gitkey} app@#{host}:.ssh/pk-git"
          end
          
          unless config_updated
            run "echo \"IdentityFile /home/app/.ssh/pk-git\" >> /home/app/.ssh/config"
            run "echo \"Host github.com\\nStrictHostKeyChecking no\\n\" >> /home/app/.ssh/config"
          end        
        end
      end
      
      
      # Uncomment if needed in future.
      # 
      #desc "Warm up the ssh known hosts so that git will succeed" 
      #task :warm_ssh_knownhosts, :roles => [:app] do 
      #  
      #  run "rm -rf /home/app/application"
      #  #run "git clone #{repository} /home/app/application" do |channel, stream, data|
      #  run "ssh github.com" do |channel, stream, data|
      #    puts data
      #    if data =~ /(Are you sure)/
      #      channel.send_data "yes\n"
      #    end
      #  end
      #  run "rm -rf /home/app/application" 
      #end
      
      desc :verify_setup do 
        # Do nothing for now...
        
      end
    end
  end
  
end
