#
# Public webserver deployment code...
#

load 'lib/recipes/util' 

# Set the local variables...
set :application, "spree-schof"
set :repository, "git@github.com:schof/spree.git"
set :scm, "git"
set :branch, "master"
set :scm_verbose, true

set :database_config, "#{ENV['HOME']}/.ec2/database.yml"
set :s3_config, "#{ENV['HOME']}/.ec2/s3.yml"

set :user, "app"
set :runner, "root"
set :admin_runner, "root"

# Read the host configuration and fix any links 
set :files_config, read_config('files.yml', {:erb => true})

set :synchronize,             files_config['synchronize']
set :verify,                  files_config['verify']
set :mnt_directories_to_move, files_config['mnt_directories_to_move'] 
set :etc_directories_to_move, files_config['etc_directories_to_move']

#
# XXX - There has to be a better way to do this...extract the 
# instances from ec2-describe-instances? 
# 
# Your EC2 instances. Use the ec2-xxx....amazonaws.com hostname, not
# any other name (in case you have your own DNS alias) or it won't
# be able to resolve to the internal IP address.

# Read the host configuration 
set :host_config, read_config('hosts.yml', {:erb => true})

# 
# Configuration: ENV['NAME'] restricts the role assignment
#
assign_roles(host_config)

# NOTE: for some reason Capistrano requires you to have both the public and
# the private key in the same folder, the public key should have the 
# extension ".pub".
#
# XXX: Pass the location of the certificate in an environment file 
#
ssh_options[:keys] = host_config['keys'] 
ssh_options[:forward_agent] = true


# role :memcache, "ec2-12-xx-xx-xx.z-1.compute-1.amazonaws.com"
# role :db,       "ec2-12-xx-xx-xx.z-1.compute-1.amazonaws.com", 
#                 :primary => true, :ebs_vol_id => 'vol-12345abc'

# Whatever you set here will be taken set as the default RAILS_ENV value
# on the server. Your app and your hourly/daily/weekly/monthly scripts
# will run with RAILS_ENV set to this value.
set :rails_env, "production"

# mount point and devices...
set :mysql_dir_root, '/var/local'
set :block_mnt, '/dev/sdh'

# EC2 on Rails config. 
# NOTE: Some of these should be omitted if not needed.
set :ec2onrails_config, {

  # S3 bucket and "subdir" used by the ec2onrails:db:restore task
  # NOTE: this only applies if you are not using EBS
  :restore_from_bucket => "ec2manage-db",
  :restore_from_bucket_subdir => "db-archive",
  
  # S3 bucket and "subdir" used by the ec2onrails:db:archive task
  # This does not affect the automatic backup of your MySQL db to S3, it's
  # just for manually archiving a db snapshot to a different bucket if 
  # desired.
  # NOTE: this only applies if you are not using EBS
  :archive_to_bucket => "ec2manage-db",
  :archive_to_bucket_subdir => "db-archive/#{Time.new.strftime('%Y-%m-%d--%H-%M-%S')}",
  
  # Set a root password for MySQL. Run "cap ec2onrails:db:set_root_password"
  # to enable this. This is optional, and after doing this the
  # ec2onrails:db:drop task won't work, but be aware that MySQL accepts 
  # connections on the public network interface (you should block the MySQL
  # port with the firewall anyway). 
  # If you don't care about setting the mysql root password then remove this.
  :mysql_root_password => "hello",
  
  # Zmanda backup manager
  :db_zrm_backup_user => 'zrm',
  :db_zrm_restore_user => 'zrm',
  :db_zrm_password => 'hello',
  
  # Any extra Ubuntu packages to install if desired
  # If you don't want to install extra packages then remove this.
  :packages => ["logwatch", "imagemagick", "libmagick9-dev", "unison", 
                "libxml-parser-perl", "libdbd-mysql-perl", 
                "logtail", "libsqlite3-0", "libsqlite3-dev",
                "munin", "munin-node" ],
  
  # Any extra RubyGems to install if desired: can be "gemname" or if a 
  # particular version is desired "gemname -v 1.0.1"
  # If you don't want to install extra rubygems then remove this
  # NOTE: if you are using rails 2.1, ec2onrails calls 'sudo rake gem:install',
  # which will install gems defined in your rails configuration
  :rubygems => ["rmagick", "highline", "activemerchant", "tlsmail", 
                "activerecord-tableless", "searchlogic", "ruby-debug", 
                "twitter", "sqlite3-ruby", 'aws-s3', 'right_aws', "main", 
                "highline"  ],
  
  # Defines the web proxy that will be used.  Choices are :apache or :nginx
  :web_proxy_server => :apache,
  
  # extra security measures are taken if this is true, BUT it makes initial
  # experimentation and setup a bit tricky.  For example, if you do not
  # have your ssh keys setup correctly, you will be locked out of your
  # server after 3 attempts for upto 3 months.  
  #:harden_server => false,
  
  # Set the server timezone. run "cap -e ec2onrails:server:set_timezone" for 
  # details
  :timezone => "UTC",
  
  # Files to deploy to the server (they'll be owned by root). It's intended
  # mainly for customized config files for new packages installed via the 
  # ec2onrails:server:install_packages task. Subdirectories and files inside
  # here will be placed in the same structure relative to the root of the
  # server's filesystem. 
  # If you don't need to deploy customized config files to the server then
  # remove this.
  :server_config_files_root => File.join(File.dirname(__FILE__), "/../server/files"),
  :server_config_templates_root => File.join(File.dirname(__FILE__), "/../server/templates"),
  
  # If config files are deployed, some services might need to be restarted.
  # If you don't need to deploy customized config files to the server then
  # remove this.
  #:services_to_restart => %w(postfix sysklogd),
  :services_to_restart => %w(splunk myfavorite-app2 myfavorite-app1),
  
  # Set an email address to forward admin mail messages to. If you don't
  # want to receive mail from the server (e.g. monit alert messages) then
  # remove this.
  #:mail_forward_address => "you@yourdomain.com",
  
  # Set this if you want SSL to be enabled on the web server. The SSL cert 
  # and key files need to exist on the server, The cert file should be in
  # /etc/ssl/certs/default.pem and the key file should be in
  # /etc/ssl/private/default.key (see :server_config_files_root).
  :enable_ssl => true
}

# EC2onRails setup related dependencies 
#before "ec2onrails:setup", "ec2manage:server:make_app_symlink"
#after "ec2onrails:server:install_packages", "ec2manage:server:install_packages"

# Capistrano setup-related dependencies 
#after "deploy:setup", "ec2manage:deploy:shared_files" 
#after "deploy:setup", "ec2manage:deploy:upload_pvt_key_to_server"

# Capistrano deploy related depenencies 
#before "deploy:update_code", "ec2manage:deploy:upload_git_private_key"
#after "ec2onrails:db:enable_ebs", "ec2manage:db:move_host_directories_to_ebs"
#after "deploy:symlink", "ec2manage:deploy:symlink" 


