Capistrano::Configuration.instance.load do
  
  namespace :ec2manage do 
    
    desc "How to use this script" 
    task :help do 
      
      msg = <<-END
       
    General usage:
        NAME=<alias-from-hosts.yml> cap <command> 
  
        Make sure that the following are correct
  
        1. database.yml 
        2. hosts.ym: Hostnames and roles
        3. dns.yml: dns aliases, passwords 
        4. s3.yml: account, access and secret 
  
    To setup: 
        NAME=master cap deploy:cold 
  
    General sequence of commands to deploy on a new instance:
  
      deploy:cold      
        ec2onrails:setup 
          ec2onrails:server:install_packages
            ec2manage:server:install_packages
          ec2onrails:db:enable_ebs 
            ec2manage:db:move_host_directories_to_ebs 
        deploy:setup    
          ec2manage:deploy:shared_files
          ec2manage:deploy:upload_pvt_key_to_server
        deploy:update_code 
            ec2manage:deploy:upload_git_private_key
        deploy:symlink 
          ec2manage:deploy:symlink 
        db:migrate 
        ec2onrails:db:init_backup
        ec2onrails:db:optimize
        ec2onrails:server:restrict_sudo_access
  
        Note that the dependencies are already setup and if this
        sequence breaks (as it will, it is not easy to continue from
        where it broke! Aaargh!
  
    To update code: 
        NAME=master cap deploy:update
  
    To connect to machine: 
        NAME=master cap ec2manage:server:ssh_connection 
    
    The above command may fail. So you can follow this sequence to 
    setup a machine
    
       NAME=master cap ec2onrails:setup   # this will set up the machine
       NAME=master cap deploy:cold 
  
    To update a deployed repository 
  
       NAME=master cap deploy:update_code 
       NAME=master cap deploy:symlink  
               ^^^^^^^^^^ NOTE: Should be executed before migrate
       NAME=master cap deploy:migrate 
       NAME=master cap deploy:restart 
  
    To rollback: (UNTESTED)
   
       NAME=master cap deploy:rollback 
  
       Note that this only rollsback code changes. TODO rollback 
       for the rest of the changes 
  
    To restore a version from the s3 repository (UNTESTED)
  
       NAME=master cap ec2onrails:restore_db_and_deploy 
  
    END
      puts msg 
    end
  end
end
