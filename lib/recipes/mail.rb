Capistrano::Configuration.instance.load do

  namespace :ec2manage do 
    namespace :server do 
      namespace :mail do 
        
        desc "Check postfix mailq" 
        task :check_mailq do 
          ec2onrails.server.allow_sudo do 
            input = ''
            sudo  "mailq" do |channel, stream, data|
              next if data.chomp == input.chomp || data.chomp == ''
              print data
              channel.send_data(input = $stdin.gets) if data =~ /^(>|\?)>/
            end
          end
        end
      end
    end
  end
end
