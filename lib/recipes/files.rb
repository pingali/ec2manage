#
# Looks at directories/files/permissions 
# originally in db.rb 
#
Capistrano::Configuration.instance.load do
  
  # Put all the database operations here...
  namespace :ec2manage do 
    
    #All files-based operations
    namespace :files do 
  
      # This function should be in utilities but for some reason skippy
      # put the enable ebs in the db functions.
      desc "(rsync) Initialize directories with EBS content" 
      task :initialize_host_directories_from_ebs, 
                            :depends => [ :check_ebs_mount_status ], 
                            :roles => [:app, :db, :web] do 
        
        #Move the app
        ec2onrails.server.allow_sudo do
  
          synchronize.each do |m|
              
            ebs_dir       = m['ebs_dir']
            ebs_location  = m['ebs_location']
            host_dir      = m['host_dir']
            host_location = m['host_location']
            ownership     = m['ownership']
            
            ebs_dir_exists = true if quiet_capture("test -d #{mysql_dir_root}#{ebs_dir} || echo 'something'").empty?
            host_location_exists = true if quiet_capture("test -d #{host_location} || echo 'something'").empty? 


            # Copy the code over...
            if (ebs_dir and host_location and ebs_dir_exists) 
              unless host_location_exists
                sudo "mkdir -p #{host_location}"
              end
              sudo "rsync -arpgouv #{mysql_dir_root}#{ebs_dir} #{host_location}"
              
              if (ownership)
                sudo "chown -R #{ownership} #{host_dir}"
              end
            end
          end  
        end
      end
        
      # This function should be in utilities but for some reason skippy
      # put the enable ebs in the db functions.
      desc "(rsync) Initialize directories with EBS content" 
      task :initialize_ebs_directories_from_host,
                        :depends => [ :check_ebs_mount_status ], 
                        :roles => [:app, :db, :web] do 

  
        #Move the app
        ec2onrails.server.allow_sudo do
          
          synchronize.each do |m|
            
            ebs_dir       = m['ebs_dir']
            ebs_location  = m['ebs_location']
            host_dir      = m['host_dir']
            host_location = m['host_location']
            ownership     = m['ownership']
              
            host_dir_exists = true if quiet_capture("test -e #{host_dir} || echo 'something'").empty?            
            ebs_location_exists = true if quiet_capture("test -e #{mysql_dir_root}#{ebs_location} || echo 'something'").empty? 

            # Copy the code over...
            if (host_dir and host_dir_exists and ebs_location)
              unless ebs_location_exists
                sudo "mkdir -p #{mysql_dir_root}#{ebs_location}"
              end

              sudo "rsync -arpoguv #{host_dir} #{mysql_dir_root}#{ebs_location}"

              if (ownership)
                sudo "chown -R #{ownership} #{mysql_dir_root}#{ebs_dir}"
              end
            end                        
          end  
        end
      end
        
      # This function should be in utilities but for some reason skipy
      # put the enable ebs in the db functions. 
      desc "(unison) Synchronize the host directories with the EBS"
      task :sync_host_directories_with_ebs,
                        :depends => [ :check_ebs_mount_status ], 
                        :roles => [:app, :db, :web] do 
  
        #Move the app
        ec2onrails.server.allow_sudo do
  
          sudo "rm -rf /home/app/.unison" 
          
          synchronize.each do |m|
            
            ebs_dir       = m['ebs_dir']
            ebs_location  = m['ebs_location']
            host_dir      = m['host_dir']
            host_location = m['host_location']
            ownership     = m['ownership']
          
            ebs_dir_exists = true if quiet_capture("test -d #{mysql_dir_root}#{ebs_dir} || echo 'something'").empty?
            host_dir_exists = true if quiet_capture("test -d #{host_dir} || echo 'something'").empty?

            # Copy the code over...
            if (ebs_dir and host_dir and ebs_dir_exists and host_dir_exists)
              sudo "unison -auto #{mysql_dir_root}#{ebs_dir} #{host_dir}" do |channel, stream, data|
                print "-#{data}-\n"

                if data =~ /(continue)/
                  channel.send_data "\n"
                end
                
                next unless data =~ /\?/
                
                # Transfer from the host to the EBS 
                #if data =~ /(\[\] \?)/
                #  channel.send_data "<\n"
                #end
                #
                if data =~ /(updates\? \[\])/
                  channel.send_data "y\n"
                end

                #if data =~ /(^\])/
                #  channel.send_data "<\n"
                #end               
                
                if data =~ /(\] )/
                  input = Capistrano::CLI.ui.ask("Enter:")
                  puts "Sending #{input}"
                  channel.send_data(input)
                end
              end
            end            
          end  
        end
      end
        
      # This function should be in utilities but for some reason skipy
      # put the enable ebs in the db functions. 
      desc "Move the rest of the source to EBS" 
      task :move_host_directories_to_ebs,
                         :depends  => [ :check_ebs_mount_status ], 
                         :roles => [:app, :db, :web] do 
  
        unless mnt_directories_to_move or etc_directories_to_move
          raise "Either mnt_directories_to_move or etc_directories_to_move have to be defined for this task"
        end
        
        #Move the app
        ec2onrails.server.allow_sudo do
            
          if mnt_directories_to_move 
            
            if mnt_directories_to_move.length == 0 
              puts "No directories /mnt directories to move" 
            end
            
            if mnt_directories_to_move.length > 0 
              
              # Move other directories... /mnt/
              msg = "Moving /mnt directories #{mnt_directories_to_move.join(',')} to EBS. Proceed..\?"
              choice = get_user_approval(msg) 
              if choice == 'y'
                mnt_directories_to_move.each do |dir| 
                  
                  mnt_dir_exists = true if !quiet_capture("test -d /mnt/#{dir} || echo ''").empty?
                  mnt_dir_link = true if !quiet_capture("test -L /mnt/#{dir} || echo ''").empty?
                  ebs_mnt_dir_exists = true if !quiet_capture("test -d #{mysql_dir_root}/mnt/#{dir} || echo 'something'").empty?
                  
                  # EBS move not happened yet...
                  if (mnt_dir_exists and !ebs_mnt_dir_exists)
                    msg = "/mnt/#{dir} is a directory. Should I move /mnt/#{dir} to EBS?"
                    choice = get_user_approval(msg)
                    if choice == 'y'
                      sudo "mv /mnt/#{dir} #{mysql_dir_root}/mnt && \
                              ln -fs #{mysql_dir_root}/mnt/#{dir} /mnt/"
                    end
                      
                    # We are probably running the setup multiple times...
                  elsif (mnt_dir_link and ebs_mnt_dir_exists) 
                    link_target = quiet_capture("ls -l /etc/#{dir} | cut -d\" \" -f10")
                    msg = "/mnt/#{dir} is a link to #{link_target}. Should I move the link to EBS instead? "
                    choice = get_user_approval(msg)
                    if choice == 'y'
                      sudo "rm /mnt/#{dir} && ln -fs #{mysql_dir_root}/mnt/#{dir} /mnt"
                    end
                      
                    # New system setup; so create the links...
                  elsif (ebs_mnt_dir_exists and !mnt_dir_exists and !mnt_dir_link)
                    msg = "/mnt/#{dir} does not exist. Should I create the link to EBS instead?" 
                    if choice == 'y'
                      sudo "mkdir -p /mnt && ln -fs #{mysql_dir_root}/mnt/#{dir} /mnt"
                    end
                  else
                    msg = "Nothing to be done for /mnt/#{dir}" 
                    puts msg 
                  end
                end
              end
            end
          end
            
            
          if etc_directories_to_move.length == 0 
            puts "No directories /etc directories to move" 
          end
          
          if etc_directories_to_move.length > 0 
            # Move /etc/
            msg = "Moving /etc directories #{etc_directories_to_move.join(',')} to EBS. Proceed\?"
            choice = get_user_approval(msg)
            if choice == 'y' 
              etc_directories_to_move.each do |dir| 
                etc_dir_exists = true if !quiet_capture("test -d /etc/#{dir} || echo ''").empty?
                etc_dir_link = true if !quiet_capture("test -L /etc/#{dir} || echo ''").empty?
                ebs_etc_dir_exists = true if !quiet_capture("test -d #{mysql_dir_root}/etc/#{dir} || echo ''").empty?
                
                # EBS move not happened yet...
                if (etc_dir_exists and !ebs_mnt_dir_exists)
                  msg = "Should I move /etc/#{dir} to EBS?"
                  choice = get_user_approval(msg)
                  if choice == 'y'
                    sudo "mkdir -p #{mysql_dir_root}/etc && \
                            mv /etc/#{dir} #{mysql_dir_root}/etc && \
                            ln -fs #{mysql_dir_root}/etc/#{dir} /etc"
                  end
                elsif (ebs_etc_dir_exists && etc_dir_link)
                  link_target = quiet_capture("ls -l /etc/#{dir} | cut -d\" \" -f10")
                  msg = "/etc/#{dir} is a link to #{link_target}. Should I move the link to EBS instead? "
                  choice = get_user_approval(msg)
                  if choice == 'y'
                    sudo "rm /etc/#{dir} && ln -fs #{mysql_dir_root}/etc/#{dir} /etc"
                  end
                elsif (ebs_etc_dir_exists and !etc_dir_exists and !etc_dir_link)
                  msg = "/etc/#{dir} does not exist. Should I create the link to EBS instead?" 
                  if choice == 'y'
                    sudo "ln -fs #{mysql_dir_root}/etc/#{dir} /etc"
                  end
                end
              end                  
            end
          end
        end
      end
    end
  end
end
  
