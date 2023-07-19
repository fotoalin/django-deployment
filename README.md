# Deploy Django/Python app on AWS Lightsail packaged by Bitnami with Apache on Linux

### This is intended to be a detailed refference on how to deploy a Python/Django web app that uses Celery, Redis, Django-Channels.

I've built a Django app that interacts with different external APIs and uses: 
> **Celery** to offload very long tasks
> **Redis** as a backend for Celery
> **Django Channels** to send task updates to the UI.

At the moment I'm having hard times in deploying this app as vhost on AWS Lightsail with Apache on Linux.

I'm suspecting the issue to be somewhere in a custom middleware I created to attach a unique UUID to the request object and also in the configuration of the Apache vhost.ƒ

The app work fine locally over HTTP and WS, but not in production where it has to be over HTTPS and WSS.
Also there are no issues when using Apache mod_wsgi to interact with django.

The issue came up because I had to switch on using Daphne (and it has to be used) in order to interact with django channels over web sockets.

> **Domain name**: staging.bakery.webdev.co.uk, managed by AWS (accessible within bakery network only)
> 
> **Dependencies**: Celery, Redis, Django-Channels (installed and configured)
> 
> **HTTPS**: generated and set self signed SSL certificates
> 
> **Supervisor**: installed and used to manage Celery and Daphne services. Both Celery and Daphne seem to run properly with no errors.

The Django web app mainly uses HTTPS to operate, but some functionalities uses Redis & Celery for creating and executing tasks and Django-Channels for sending task progress updates to the UI.

**The following are enabled:**

```bash
mod_proxy
mod_proxy_http
mod_proxy_wstunnel
mod_ssl
```

**External traffic is blocked by UFW.**

**Created supervisor services:**

> **/etc/supervisor/conf.d/daphne.conf
> /etc/supervisor/conf.d/celery.conf**

#### django settings.py

```python
...
MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",

    "usersapp.middleware.SetComputerUUIDMiddlewareWSGI",
    
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "django.middleware.locale.LocaleMiddleware'" 
    "django_htmx.middleware.HtmxMiddleware",
]


CHANNELS = {
    'default': {
        'middleware': [
            'usersapp.middleware.SetComputerUUIDMiddlewareASGI',
        ],
    },
...
}
```

#### middleware.py

```python
import datetime
import uuid

from channels.middleware import BaseMiddleware
from channels.db import database_sync_to_async

class SetComputerUUIDMiddlewareWSGI():
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)

        request.client_computer_uuid = request.COOKIES.get('client_computer_uuid')
        

        if not request.client_computer_uuid:
            expiration_date = datetime.datetime.now() + datetime.timedelta(days=365*10) # 10 years
            uuid_value = uuid.uuid4()
            uuid_string = str(uuid_value)
            response.set_cookie('client_computer_uuid', uuid_string, expires=expiration_date)
            request.client_computer_uuid = uuid_string

        return response


class SetComputerUUIDMiddlewareASGI(BaseMiddleware):
    def __init__(self, inner):
        super().__init__(inner)

    async def __call__(self, scope, receive, send):
        if scope["type"] == "http":
            headers = dict(scope["headers"])
            cookie_header = headers.get(b"cookie")
            client_computer_uuid = None

            if cookie_header:
                cookies = cookie_header.decode().split("; ")
                for cookie in cookies:
                    name, value = cookie.split("=")
                    if name == "client_computer_uuid":
                        client_computer_uuid = value

            if not client_computer_uuid:
                expiration_date = datetime.datetime.now() + datetime.timedelta(days=365 * 10)  # 10 years
                uuid_value = uuid.uuid4()
                uuid_string = str(uuid_value)
                response_headers = [
                    (b"Set-Cookie", f"client_computer_uuid={uuid_string}; Expires={expiration_date.strftime('%a, %d-%b-%Y %H:%M:%S GMT')}".encode())
                ]
                client_computer_uuid = uuid_string

                # Set the response headers containing the new client_computer_uuid cookie
                await send({
                    "type": "http.response.start",
                    "status": 200,
                    "headers": response_headers,
                })

            # Add the client_computer_uuid to the ASGI scope for further processing
            scope["client_computer_uuid"] = client_computer_uuid

        await super().__call__(scope, receive, send)
```

#### wsgi.py

```python
import os

from django.core.wsgi import get_wsgi_application

from usersapp.middleware import SetComputerUUIDMiddlewareWSGI



os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'project_core.settings')


django_wsgi_application = get_wsgi_application()
application = SetComputerUUIDMiddlewareWSGI(django_wsgi_application)
# application = django_wsgi_application
```


#### asgi.py

```python
import os

from channels.auth import AuthMiddlewareStack
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.security.websocket import AllowedHostsOriginValidator
from django.core.asgi import get_asgi_application
from usersapp.middleware import SetComputerUUIDMiddlewareASGI, SetComputerUUIDMiddlewareWSGI
import ws.routing

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "project_core.settings")
django_asgi_app = get_asgi_application()

application = ProtocolTypeRouter(
    {
        # Django's ASGI application to handle traditional HTTP requests
        # "http": SetComputerUUIDMiddlewareASGI(django_asgi_app),
        "http": SetComputerUUIDMiddlewareASGI(django_asgi_app),

        # WebSocket chat handler
        "websocket": SetComputerUUIDMiddlewareWSGI(
            AllowedHostsOriginValidator(
                AuthMiddlewareStack(
                    URLRouter(
                        ws.routing.websocket_urlpatterns
                    )
                )
            )
        ),
    }
)
```

### CONFIG FILES:

#### /etc/supervisor/conf.d/daphne.conf

```ini
[program:daphne]
command=/bin/bash -c 'source /opt/bitnami/projects/Barcode_Scanner_APP_v20/venv/bin/activate && /opt/bitnami/projects/Barcode_Scanner_APP_v20/venv/bin/daphne -u /tmp/daphne.sock project_core.asgi:application'
directory=/opt/bitnami/projects/Barcode_Scanner_APP_v20
autostart=true
autorestart=true
user=bitnami
redirect_stderr=true
stdout_logfile=/var/log/daphne.log
```

#### /etc/supervisor/conf.d/celery.conf

```ini
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
```


#### /opt/bitnami/apache/conf/vhosts/bakery-https-vhost.conf

```conf
<VirtualHost *:443 _default_:443>
    Protocols h2 http/1.1

    # SSL Configuration
    SSLEngine on
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
    RewriteCond %{HTTP_HOST} !^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?$
    RewriteCond %{REQUEST_URI} !^/\.well-known
    RewriteRule ^/(.*) https://%{SERVER_NAME}/$1 [R,L]
    # END: Enable HTTP to HTTPS redirection

    # Proxy Configuration for Daphne
    <Location />
        ProxyPass unix:/tmp/daphne.sock|http://127.xxx.xxx.xxx/
        ProxyPassReverse unix:/tmp/daphne.sock|http://127.xxx.xxx.xxx/
    </Location>
</VirtualHost>
```

#### /opt/bitnami/apache/conf/vhosts/bakery-vhost.conf

```conf
<IfDefine !IS_BAKERY_LOADED>
    Define IS_BAKERY_LOADED
    WSGIDaemonProcess BAKERY python-home=/opt/bitnami/projects/Barcode_Scanner_APP_v20/venv python-path=/opt/bitnami/projects/Barcode_Scanner_APP_v20
    WSGIProcessGroup BAKERY
</IfDefine>

<VirtualHost *:443>
    ServerName staging.bakery.webdev.co.uk
    ServerAlias www.staging.bakery.webdev.co.uk
    ServerAdmin ops@webdev.co.uk

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

    WSGIScriptAlias / /opt/bitnami/projects/Barcode_Scanner_APP_v20/project_core/wsgi.py
    <Directory /opt/bitnami/projects/Barcode_Scanner_APP_v20/project_core>
        <Files wsgi.py>
            Require all granted
        </Files>
    </Directory>
</VirtualHost>
```

### LOGS

> `/opt/bitnami/ctlscript.sh status`

```bash

apache already running
mariadb already running
postgresql already running
```

> `sudo ufw status`

```bash
Status: active
To                         Action      From
--                         ------      ----
22/tcp                     ALLOW       Anywhere                  
443                        ALLOW       212.xxx.xxx.xxx            
443                        ALLOW       86.xxx.xxx.xxx               
443                        ALLOW       212.xxx.xxx.xxx           
443                        ALLOW       109.xxx.xxx.xxx           
443                        ALLOW       109.xxx.xxx.xxx           
22/tcp (v6)                ALLOW       Anywhere (v6)
```

> `sudo supervisorctl status`

```bash
celery:celery_00                 RUNNING   pid 693, uptime 0:08:51
daphne                           RUNNING   pid 694, uptime 0:08:51
```

> `tail -n 10 /opt/bitnami/apache/logs/error_log`

```bash
[Tue Jul 18 12:30:05.119459 2023] [mpm_event:notice] [pid 2908:tid 139712707017984] AH00489: Apache/2.4.57 (Unix) OpenSSL/1.1.1n mod_wsgi/4.9.4 Python/3.8 configured -- resuming normal operations
[Tue Jul 18 12:30:05.119589 2023] [core:notice] [pid 2908:tid 139712707017984] AH00094: Command line: '/opt/bitnami/apache/bin/httpd -f /opt/bitnami/apache/conf/httpd.conf'
[Tue Jul 18 12:30:58.428682 2023] [proxy_http:error] [pid 2912:tid 139712635840256] (20014)Internal error (specific information not available): [remote 212.xxx.xxx.xxx:56370] AH01102: error reading status line from remote server httpd-UDS:0
[Tue Jul 18 12:30:59.680423 2023] [mpm_event:notice] [pid 2908:tid 139712707017984] AH00491: caught SIGTERM, shutting down
[Tue Jul 18 12:33:43.734503 2023] [mpm_event:notice] [pid 770:tid 139994677853440] AH00489: Apache/2.4.57 (Unix) OpenSSL/1.1.1n mod_wsgi/4.9.4 Python/3.8 configured -- resuming normal operations
[Tue Jul 18 12:33:43.737921 2023] [core:notice] [pid 770:tid 139994677853440] AH00094: Command line: '/opt/bitnami/apache/bin/httpd -f /opt/bitnami/apache/conf/httpd.conf'
[Tue Jul 18 12:35:16.132002 2023] [proxy_http:error] [pid 774:tid 139994657031936] (70007)The timeout specified has expired: [remote 212.xxx.xxx.xxx:57057] AH01102: error reading status line from remote server httpd-UDS:0
[Tue Jul 18 12:35:16.135960 2023] [proxy:error] [pid 774:tid 139994657031936] [remote 212.xxx.xxx.xxx:57057] AH00898: Error reading from remote server returned by /
[Tue Jul 18 12:36:16.378169 2023] [proxy_http:error] [pid 774:tid 139994665424640] (70007)The timeout specified has expired: [remote 212.xxx.xxx.xxx:57057] AH01102: error reading status line from remote server httpd-UDS:0, referer: https://staging.bakery.webdev.co.uk/
[Tue Jul 18 12:36:16.378212 2023] [proxy:error] [pid 774:tid 139994665424640] [remote 212.xxx.xxx.xxx:57057] AH00898: Error reading from remote server returned by /favicon.ico, referer: https://staging.bakery.webdev.co.uk/
```

> `tail -n 10 /opt/bitnami/apache/logs/access_log`

```bash
212.xxx.xxx.xxx - - [18/Jul/2023:11:09:33 +0000] "GET / HTTP/2.0" 502 341
212.xxx.xxx.xxx - - [18/Jul/2023:11:10:33 +0000] "GET /favicon.ico HTTP/2.0" 502 341
212.xxx.xxx.xxx - - [18/Jul/2023:11:13:03 +0000] "GET / HTTP/2.0" 502 341
212.xxx.xxx.xxx - - [18/Jul/2023:11:42:10 +0000] "GET / HTTP/2.0" 503 299
212.xxx.xxx.xxx - - [18/Jul/2023:11:42:10 +0000] "GET /favicon.ico HTTP/2.0" 503 299
212.xxx.xxx.xxx - - [18/Jul/2023:12:16:45 +0000] "GET / HTTP/2.0" 502 341
212.xxx.xxx.xxx - - [18/Jul/2023:12:17:45 +0000] "GET /favicon.ico HTTP/2.0" 502 341
212.xxx.xxx.xxx - - [18/Jul/2023:12:30:43 +0000] "GET / HTTP/2.0" 502 -
212.xxx.xxx.xxx - - [18/Jul/2023:12:34:16 +0000] "GET / HTTP/2.0" 502 341
212.xxx.xxx.xxx - - [18/Jul/2023:12:35:16 +0000] "GET /favicon.ico HTTP/2.0" 502 341
```

> `tail -n 10 /var/log/celery.log`

```bash
  . apicbaseapp.tasks.fetch_apicbase_recipe_details
  . apicbaseapp.tasks.fetch_apicbase_recipe_list
  . apicbaseapp.tasks.fetch_recipe_nutritional_data
  . apicbaseapp.tasks.update_shopify_products
  . project_core.celery.debug_task

[2023-07-18 13:33:48,476: INFO/MainProcess] Connected to redis://localhost:6379/0
[2023-07-18 13:33:48,479: INFO/MainProcess] mingle: searching for neighbors
[2023-07-18 13:33:49,487: INFO/MainProcess] mingle: all alone
[2023-07-18 13:33:49,497: INFO/MainProcess] celery@ip-172-26-13-25 ready.
```

> `tail -n 10 /var/log/daphne.log`

```python
    await self.handle(scope, receive, send)
  File "/opt/bitnami/projects/Barcode_Scanner_APP_v20/venv/lib/python3.8/site-packages/django/core/handlers/asgi.py", line 187, in handle
    await self.send_response(response, send)
  File "/opt/bitnami/projects/Barcode_Scanner_APP_v20/venv/lib/python3.8/site-packages/django/core/handlers/asgi.py", line 255, in send_response
    await send(
  File "/opt/bitnami/projects/Barcode_Scanner_APP_v20/venv/lib/python3.8/site-packages/daphne/server.py", line 240, in handle_reply
    protocol.handle_reply(message)
  File "/opt/bitnami/projects/Barcode_Scanner_APP_v20/venv/lib/python3.8/site-packages/daphne/http_protocol.py", line 241, in handle_reply
    raise ValueError("HTTP response has already been started")
ValueError: HTTP response has already been started
```
