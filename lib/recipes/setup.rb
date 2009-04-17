Capistrano::Configuration.instance.load do

  # This is from
  #http://groups.google.com/group/ec2-on-rails-discuss/browse_thread/thread/5f1aa6bf4561c62c

  namespace :ec2manage do 

    namespace :setup do 
      
      desc "Default setup - begin " 
      task :default_setup_begin do
        ec2onrails.server.set_mail_forward_address
        ec2onrails.server.set_timezone
        ec2onrails.server.install_packages
        ec2manage.server.install_packages 
        ec2onrails.server.install_gems
        ec2manage.deploy.host_setup
        ec2onrails.server.deploy_files
        ec2manage.server.configure_packages
        ec2manage.deploy.upload_git_private_key
        ec2manage.deploy.upload_root_pvt_key_to_server
        ec2onrails.server.setup_web_proxy
        ec2onrails.server.set_roles
        ec2onrails.server.enable_ssl if ec2onrails_config[:enable_ssl]
        ec2onrails.server.set_rails_env
      end
      
      desc "Default setup - begin " 
      task :default_setup_end do
        ec2onrails.server.restart_services
        ec2manage.server.harden 
      end

      desc "Prepare a new instance with new volume" 
      task :with_fresh_volume do
        ec2onrails.server.allow_sudo do
          default_setup_begin
          ec2onrails.db.create
          ec2onrails.server.harden_server
          ec2onrails.db.first_time_enable_ebs
          ec2manage.files.initialize_ebs_directories_from_host
          ec2onrails.db.start           
          ec2onrails.db.set_root_password
          ec2manage.deploy.verify_setup
          default_setup_end
        end
      end
      
      desc "Prepare a new instance with old volume" 
      task :with_old_volume do
        ec2onrails.server.allow_sudo do
          default_setup_begin 
          ec2onrails.server.harden_server
          ec2onrails.db.shutdown
          ec2onrails.db.mount_ebs
          ec2manage.files.initialize_host_directories_from_ebs
          ec2onrails.db.start
          db.set_root_password
          ec2manage.deploy.verify_setup
          default_setup_end
        end
      end
      
    end
  end
end
