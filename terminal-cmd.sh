# -- APACHE --
sudo vim /etc/apache2/sites-available/bakery-vhost.conf 
sudo cat /etc/apache2/sites-available/bakery-vhost.conf 

sudo service apache2 restart
sudo systemctl restart apache2

tail -n 10 /var/log/apache2/error-bakery.log
# ------------





# -- SUPERVISOR --
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl restart all
sudo supervisorctl restart bakery

sudo vim /etc/supervisor/conf.d/bakery.conf
sudo cat /etc/supervisor/conf.d/bakery.conf
tail -n 10 /var/log/supervisor/bakery.log
# ----------------


sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl restart bakery
sudo systemctl restart apache2