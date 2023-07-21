# -- INSTALLATION --
sudo apt-get update
sudo apt-get upgrade

-- BITNAMI --
sudo /opt/bitnami/ctlscript.sh status
sudo /opt/bitnami/ctlscript.sh start
sudo /opt/bitnami/ctlscript.sh restart apache
sudo /opt/bitnami/ctlscript.sh stop
sudo /opt/bitnami/ctlscript.sh restart

- check if mod_proxy, mod_proxy_http, mod_proxy_wstunnel are enabled
sudo /opt/bitnami/apache2/bin/apachectl -M | grep proxy

- check if mod_rewrite is enabled
sudo /opt/bitnami/apache2/bin/apachectl -M | grep rewrite

- check if mod_ssl is enabled
sudo /opt/bitnami/apache2/bin/apachectl -M | grep ssl

- check if mod_socache_shmcb is enabled
sudo /opt/bitnami/apache2/bin/apachectl -M | grep socache_shmcb

-- SSL using Bitnami tool --
sudo /opt/bitnami/bncert-tool





-- UFW --
sudo ufw allow 22
sudo ufw allow ssh
sudo ufw allow from xxx.xxx.xxx.xxx to any port 443

sudo ufw delete allow 8000

sudo ufw enable
sudo ufw status


-- SUPERVISOR --
sudo apt install supervisor
sudo cp /etc/supervisor/supervisord.conf /etc/supervisor/supervisord.conf.bak
sudo nano /etc/supervisor/supervisord.conf

sudo nano /etc/supervisor/conf.d/daphne.conf
sudo nano /etc/supervisor/conf.d/celery.conf

pip install -U "celery[redis]"
sudo apt install redis-server
sudo nano /etc/supervisor/conf.d/celery.conf

[program:celery]
process_name=%(program_name)s_%(process_num)02d
command=/bin/bash -c 'source /opt/bitnami/projects/Barcode_Scanner_APP_v20/venv/bin/activate && /opt/bitnami/projects/Barcode_Scanner_APP_v20/venv/bin/celery -A project_core.celery worker --loglevel=INFO'
directory=/opt/bitnami/projects/Barcode_Scanner_APP_v20
autostart=true
autorestart=true
user=bitnami
numprocs=1
redirect_stderr=true
stdout_logfile=/var/log/celery.log


sudo nano /etc/supervisor/conf.d/daphne.conf

[program:daphne]
command=/bin/bash -c 'source /opt/bitnami/projects/Barcode_Scanner_APP_v20/venv/bin/activate && /opt/bitnami/projects/Barcode_Scanner_APP_v20/venv/bin/daphne -u /tmp/daphne.sock project_core.asgi:application'
directory=/opt/bitnami/projects/Barcode_Scanner_APP_v20
autostart=true
autorestart=true
user=bitnami
redirect_stderr=true
stdout_logfile=/var/log/daphne.log



sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl status

sudo service supervisor restart
sudo supervisorctl restart all
sudo supervisorctl start all
sudo supervisorctl status




-- APACHE vhost when using HTTPS and WS with Django on Daphne and asgi and SSL is enabled --
sudo nano /opt/bitnami/apache/conf/vhosts/bakery-https-vhost.conf


<VirtualHost *:443>
    <IfDefine !IS_BAKERY_LOADED>
        Define IS_BAKERY_LOADED
        WSGIDaemonProcess BAKERY python-home=/opt/bitnami/projects/Barcode_Scanner_APP_v20/venv python-path=/opt/bitnami/projects/Barcode_Scanner_APP_v20 processes=2 threads=15
        WSGIProcessGroup BAKERY
    </IfDefine>

    Protocols h2 http/1.1

    ServerName staging.bakery.webdev.co.uk
    ServerAlias www.staging.bakery.webdev.co.uk
    ServerAdmin alin@cupcakes.co.uk

    SSLEngine on
    
    SSLProxyEngine on # Add this line to enable SSL support for the proxy

    SSLCertificateFile "/opt/bitnami/apache/conf/staging.bakery.webdev.co.uk.crt"
    SSLCertificateKeyFile "/opt/bitnami/apache/conf/staging.bakery.webdev.co.uk.key"


    # BEGIN: Configuration for letsencrypt
    Include "/opt/bitnami/apps/letsencrypt/conf/httpd-prefix.conf"
    # END: Configuration for letsencrypt

    # BEGIN: Support domain renewal when using mod_proxy without Location
    <IfModule mod_proxy.c>
        ProxyPass /.well-known !
    </IfModule>
    # END: Support domain renewal when using mod_proxy without Location

    # BEGIN: Enable HTTP to HTTPS redirection
    RewriteEngine On
    RewriteCond %{HTTPS} !=on
    RewriteCond %{HTTP_HOST} !^localhost
    RewriteCond %{HTTP_HOST} !^[0-9]+.[0-9]+.[0-9]+.[0-9]+(:[0-9]+)?$
    RewriteCond %{REQUEST_URI} !^/\.well-known
    RewriteRule ^/(.*) https://%{SERVER_NAME}/$1 [R,L]
    # END: Enable HTTP to HTTPS redirection


    DocumentRoot "/opt/bitnami/projects/Barcode_scanner_APP_v20"

    # ErrorLog "/opt/bitnami/projects/Barcode_scanner_APP_v20/logs/error_log"
    # CustomLog "/opt/bitnami/projects/Barcode_scanner_APP_v20/logs/access_log" common

    
    Alias /static/ /opt/bitnami/projects/local_cdn/staticfiles/
    <Directory /opt/bitnami/projects/local_cdn/staticfiles>
        Require all granted
    </Directory>

    Alias /media/ /opt/bitnami/projects/local_cdn/media/
    <Directory /opt/bitnami/projects/local_cdn/media>
        Require all granted
    </Directory>
    
    WSGIScriptAlias / /opt/bitnami/projects/Barcode_scanner_APP_v20/project_core/wsgi.py
    <Directory /opt/bitnami/projects/Barcode_scanner_APP_v20/project_core>
        <Files wsgi.py>
            Require all granted
        </Files>
    </Directory>

    # WSGIScriptAlias / /opt/bitnami/projects/Barcode_Scanner_APP_v20/project_core/wsgi.py
    #   <Directory /opt/bitnami/projects/Barcode_Scanner_APP_v20/project_core>
    #     <Files wsgi.py>
    #       Require all granted
    #     </Files>
    #   </Directory>


    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} =websocket [NC]
    RewriteRule /(.*)           ws://
    RewriteCond %{HTTP:Upgrade} !=websocket [NC]
    RewriteRule /(.*)           http://
    # Include "/opt/bitnami/projects/Barcode_scanner_APP_v20/conf/httpd-app.conf"

    # BEGIN: Support domain renewal when using mod_proxy within Location
    <Location /.well-known>
        <IfModule mod_proxy.c>
        ProxyPass !
        </IfModule>
    </Location>
    # END: Support domain renewal when using mod_proxy within Location
    
</VirtualHost>



-- APACHE logs --
tail -n 10 /opt/bitnami/apache/logs/error_log
tail -n 10 /opt/bitnami/apache/logs/access_log

-- CELERY logs --
tail -n 10 /var/log/celery.log

-- DAPHNE logs --
tail -n 10 /var/log/daphne.log



Please write a complete production grade vhost file for staging.bakery.webdev.co.uk domain that hosts a Django web app which uses Celery, Redis for tasks, Django-Channels for tasks progress updates, on HTTS and WSS
The app is run by Daphne server which is run by supervisor.

python-home=/opt/bitnami/projects/Barcode_Scanner_APP_v20/venv and python-path=/opt/bitnami/projects/Barcode_Scanner_APP_v20. 

static files are located on /opt/bitnami/projects/local_cdn/staticfiles/
media files are located on /opt/bitnami/projects/local_cdn/media/

    SSLCertificateFile "/opt/bitnami/apache/conf/staging.bakery.webdev.co.uk.crt"
    SSLCertificateKeyFile "/opt/bitnami/apache/conf/staging.bakery.webdev.co.uk.key"

    # BEGIN: Configuration for letsencrypt
    Include "/opt/bitnami/apps/letsencrypt/conf/httpd-prefix.conf"
    # END: Configuration for letsencrypt
    # BEGIN: Support domain renewal when using mod_proxy without Location
    <IfModule mod_proxy.c>
        ProxyPass /.well-known !
    </IfModule>
    # END: Support domain renewal when using mod_proxy without Location
    # BEGIN: Enable HTTP to HTTPS redirection
    RewriteEngine On
    RewriteCond %{HTTPS} !=on
    RewriteCond %{HTTP_HOST} !^localhost
    RewriteCond %{HTTP_HOST} !^[0-9]+.[0-9]+.[0-9]+.[0-9]+(:[0-9]+)?$
    RewriteCond %{REQUEST_URI} !^/\.well-known
    RewriteRule ^/(.*) https://%{SERVER_NAME}/$1 [R,L]
    # END: Enable HTTP to HTTPS redirection

the web socket connection is triggered by the following, inside a fetch command: const websocketConnection = new WebSocket(`wss://${window.location.host}/ws/task_status/${socketGroupName}/`, {rejectUnauthorized: false});
