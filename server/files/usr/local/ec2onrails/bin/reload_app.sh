#!/bin/sh

# Restart the application after deploying

# Install apache sites
a2dissite default
a2dissite default-ssl
a2ensite myfavorite-app1
a2ensite myfavorite-app1-ssl
a2ensite myfavorite-app2-ssl

# Reload apache
/etc/init.d/apache2 reload

# Restart god
/etc/init.d/god stop
/etc/init.d/god start
god status
god monitor db 
god monitor myfavorite-app2
god monitor myfavorite-app1
god monitor splunk
god monitor web 
god restart myfavorite-app1
god restart myfavorite-app2
god restart web
god status
