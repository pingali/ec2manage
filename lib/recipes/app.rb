Capistrano::Configuration.instance.load do

  # This is from
  #http://groups.google.com/group/ec2-on-rails-discuss/browse_thread/thread/5f1aa6bf4561c62c

  namespace :ec2manage do 
    namespace :deploy do 
      
      desc "Deploy App1" 
      task :deploy_app_cleanup do 
        run_local "rm -rf /tmp/myfavorite-app1" 
        run_local "rm -rf /tmp/myfavorite-app2"
        run_local "rm -rf /tmp/myfavorite-app1.sh" 
        run_local "rm -rf /tmp/myfavorite-app2.sh"
      end

      desc "Deploy App1" 
      task :deploy_app1_cold do 
        
        host_path = File.join(File.dirname(File.expand_path(__FILE__)),"/../../config/hosts.yml")
        name = ENV['NAME'] || 'master'
        
        # Deploy app1
        app1 =<<-END
#!/bin/sh
cd /tmp
rm -rf myfavorite-app1
git clone git@github.com:schof/spree.git /tmp/myfavorite-app1
cd myfavorite-app1
rm config/application.yml
echo "---\nmode: data" > config/application.yml
cp #{database_config} config/database.yml
cp -f #{host_path} config/hosts.yml
NAME=#{name} cap deploy:setup
NAME=#{name} cap deploy:shared_files
NAME=#{name} cap deploy:cold 
rm -rf /tmp/myfavorite-app1
        END
        
        File.open('/tmp/myfavorite-app1.sh', 'w') {|f| f.write(app1) }
        run_local "chmod 755 /tmp/myfavorite-app1.sh" 
        run_local "sh -C /tmp/myfavorite-app1.sh" 
      end

      desc "Deploy App2" 
      task :deploy_app2_cold do 

        host_path = File.join(File.dirname(File.expand_path(__FILE__)),"/../../config/hosts.yml")
        name = ENV['NAME'] || 'master'

        # Deploy app2
        app2 =<<-END
#!/bin/sh
cd /tmp
rm -rf myfavorite-app2
git clone git@github.com:schof/spree.git /tmp/myfavorite-app2
cd myfavorite-app2
rm config/application.yml
echo "---\nmode: admin" > config/application.yml
cp #{database_config} config/database.yml
cp -f #{host_path} config/hosts.yml
NAME=#{name} cap deploy:setup
NAME=#{name} cap deploy:shared_files
NAME=#{name} cap deploy:cold 
rm -rf /tmp/myfavorite-app2
        END
        
        File.open('/tmp/myfavorite-app2.sh', 'w') {|f| f.write(app2) }
        run_local "chmod 755 /tmp/myfavorite-app2.sh" 
        run_local "sh -C /tmp/myfavorite-app2.sh" 
      end
      
      desc "Reload application" 
      task :reload_app do 
        sudo "/usr/local/ec2onrails/bin/reload_app.sh"
      end
      
    end
  end
end
