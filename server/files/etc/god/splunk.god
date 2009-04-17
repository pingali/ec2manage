God.watch do |w|
  w.name = 'splunk'
  w.group = 'monitoring'
  w.autostart = true
  
  w.start    = "/opt/splunk/bin/splunk start" 
  w.stop    = "/opt/splunk/bin/splunk stop" 
  w.restart    = "/opt/splunk/bin/splunk restart" 
  
  w.pid_file = "/opt/splunk/var/run/splunk/splunkd.pid"
  w.grace    = 60.seconds

  default_configurations(w)
  create_pid_dir(w)
  restart_if_resource_hog(w, :memory_usage => 200.megabytes) do |restart|
      restart.condition(:http_response_code) do |c|
        c.code_is_not = %w(200 304)
        c.host = '127.0.0.1'
        c.path = '/'
        c.port = 12800
        c.timeout = 10.seconds
        c.times = 2
      end
    end

    monitor_lifecycle(w)

end
