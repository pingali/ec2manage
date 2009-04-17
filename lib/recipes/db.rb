
Capistrano::Configuration.instance.load do
  
  # Put all the database operations here...
  namespace :ec2manage do 
    
    namespace :db do 
      
      
      desc "Check EBS mount status"
      task :check_ebs_mount_status do 
        
        servers = find_servers_for_task(current_task)
        
        if servers.empty?
          raise Capistrano::NoMatchingServersError, "'#{task.fully_qualified_name}' is only run for servers matching #{task.options.inspect}, but no servers matched"
        elsif servers.size > 1
          raise Capistrano::Error, "`#{task.fully_qualified_name}' is can only be run on one server, not #{server.size}"
        end
        
        vol_id = ENV['VOLUME_ID'] || servers.first.options[:ebs_vol_id]
        
        # Check if the volume has been attached
        if !system( "ec2-describe-volumes | grep #{vol_id} | grep attached" )
          raise "Volume #{vol_id} is not attached to #{task.fully_qualified_name}"
        end
        
        # Check if the volume has been mounted
        if !quiet_capture("mount | grep -inr '#{mysql_dir_root}' || echo ''").empty?
          raise "Volume #{vol_id} is not mounted on #{mysql_dir_root} on host #{task.fully_qualified_name}"
        end
      end
      
      desc "Check EBS status "
      task :ebs_status, :depends => [:check_ebs_mount_status] do 
        puts "EBS is corectly mounted on #{mysql_dir_root}"
      end
      
      desc "Check the status of the slave db"
      task :slave_status, :roles => [ :db ], :except => [:primary => true] do
        run "mysql -u root -e 'show slave status \G'"
      end
      
      desc "Check the replication log status of the slave db"
      task :slave_replication_status, :roles => [ :db ], :except => [:primary => true] do
        data = run "mysql -u root -e 'show slave status \\G'"
        puts data.grep('Slave_IO_Status')
      end
      
      desc "Check the status of the slave db"
      task :master_status, :roles => [ :db ], :only => [:primary => true] do
        run "mysql -u root -e 'show master status \\G'"
        run "mysql -u root -e 'show processlist\\G'"
      end
      
      desc "Check the status of the slave db"
      task :replica_setup_master, :roles => [ :db ], 
                                 :only => [ :primary => true ] do
        run "mysql -u root < /etc/ec2manage/maatkit-setup.sql"
      end
      

      desc "Set the root password" 
      task :lock_root, :roles => [:db ] do 

        msg = "Please enter password(assumes no initial password):" 
        choice = Capistrano::CLI.ui.ask(msg)      
        run "mysql -u root -e \"set password = 'PASSWORD(#{choice}');" 
        
      end    
      
      desc "Unset the root password" 
      task :unlock_root, :roles => [:db ] do 
        
        msg = "Please enter exising password:" 
        choice = Capistrano::CLI.ui.ask(msg)      
        run "mysql -u root --password='#{choice}' -e \"set password = ''\"" 
      end    
      
      desc "Unset the root password" 
      task :setup_master_for_replication, :roles => [:db], 
                                         :only => [:primary => true] do 

        run %{mysql -u root -e "grant replication slave on *.* to 'repl'@'%' identified by PASSWORD('xxxx');"}
        
      end
      
      desc "Unset the root password" 
      task :promote_slave_to_master, :roles => [:db], 
                                    :except => [:primary => true] do 


        run %{mysql -u root -e "RESET MASTER"}
        run %{mysql -u root -e "SET MASTER=''"}
        
      end
      
      desc "Unset the root password" 
      task :prepare_master_for_demotion, :roles => [:db], 
                                         :except => [:primary => true] do 
        run %{mysql -u root -e "FLUSH LOGS;"}
        run %{mysql -u root -e "SHOW MASTER STATUS;"}
      end
      
    end
  end
end
