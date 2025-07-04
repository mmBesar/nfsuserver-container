# Use Alpine Linux for minimal size, especially good for Pi4
FROM alpine:3.19 AS builder

# Install build dependencies
RUN apk add --no-cache \
    git \
    make \
    gcc \
    g++ \
    musl-dev

# Clone and build the server
WORKDIR /build
RUN git clone https://github.com/HarpyWar/nfsuserver.git
WORKDIR /build/nfsuserver/nfsuserver
RUN make

# Runtime stage - minimal Alpine image with web server support
FROM alpine:3.19

# Install runtime dependencies including web server and PHP
RUN apk add --no-cache \
    libstdc++ \
    libgcc \
    nginx \
    php82 \
    php82-fpm \
    php82-json \
    php82-session \
    php82-mbstring \
    php82-curl \
    php82-pdo \
    php82-pdo_sqlite \
    php82-sqlite3 \
    php82-xml \
    php82-simplexml \
    php82-dom \
    php82-ctype \
    php82-fileinfo \
    php82-opcache \
    php82-sockets \
    supervisor \
    curl \
    && ln -sf /usr/bin/php82 /usr/bin/php

# Create non-root user for security
RUN addgroup -g 1000 nfsu && \
    adduser -D -u 1000 -G nfsu nfsu

# Copy the built binary
COPY --from=builder /build/nfsuserver/nfsuserver/nfsuserver /usr/local/bin/

# Copy the original web UI files
COPY --from=builder /build/nfsuserver/web /var/www/html

# Create necessary directories
RUN mkdir -p /data /var/log/nfsu /var/www/html /run/nginx /run/php /etc/supervisor/conf.d && \
    chown -R nfsu:nfsu /data /var/log/nfsu && \
    chown -R nginx:nginx /var/www/html /run/nginx && \
    chown -R nfsu:nfsu /run/php

# Configure nginx for the web UI
RUN cat > /etc/nginx/nginx.conf << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /run/nginx/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    
    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        
        root /var/www/html;
        index index.php index.html index.htm;
        
        server_name _;
        
        # Allow larger file uploads for web UI
        client_max_body_size 32M;
        
        location / {
            try_files $uri $uri/ /index.php?$query_string;
        }
        
        location ~ \.php$ {
            fastcgi_split_path_info ^(.+\.php)(/.+)$;
            fastcgi_pass 127.0.0.1:9000;
            fastcgi_index index.php;
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            fastcgi_param PATH_INFO $fastcgi_path_info;
            fastcgi_param DOCUMENT_ROOT $document_root;
            
            # Pass server data directory to PHP
            fastcgi_param NFSU_DATA_DIR /data;
            fastcgi_param NFSU_LOG_DIR /var/log/nfsu;
        }
        
        # Deny access to sensitive files
        location ~ /\.ht {
            deny all;
        }
        
        location ~ /\.git {
            deny all;
        }
        
        location ~ \.(log|dat|conf)$ {
            deny all;
        }
        
        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "no-referrer-when-downgrade" always;
        add_header Content-Security-Policy "default-src 'self' 'unsafe-inline' 'unsafe-eval' data: blob:" always;
    }
}
EOF

# Configure PHP-FPM
RUN cat > /etc/php82/php-fpm.d/www.conf << 'EOF'
[www]
user = nginx
group = nginx
listen = 127.0.0.1:9000
listen.owner = nginx
listen.group = nginx
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
chdir = /
php_admin_value[upload_max_filesize] = 32M
php_admin_value[post_max_size] = 32M
php_admin_value[memory_limit] = 128M
php_admin_value[max_execution_time] = 60
php_admin_value[session.save_path] = /tmp
php_admin_value[error_log] = /var/log/nfsu/php_errors.log
EOF

# Configure PHP
RUN cat > /etc/php82/conf.d/99-nfsu.ini << 'EOF'
; NFSU Server Web UI Configuration
display_errors = Off
log_errors = On
error_log = /var/log/nfsu/php_errors.log
date.timezone = UTC
session.cookie_httponly = On
session.use_strict_mode = On
session.cookie_secure = Off
session.gc_maxlifetime = 3600
upload_max_filesize = 32M
post_max_size = 32M
max_input_vars = 3000
memory_limit = 128M
max_execution_time = 60

; Enable sockets for server communication
extension=sockets
EOF

# Configure supervisord
RUN cat > /etc/supervisor/conf.d/nfsuserver.conf << 'EOF'
[supervisord]
nodaemon=true
user=root
logfile=/var/log/nfsu/supervisord.log
pidfile=/run/supervisord.pid

[program:nfsuserver]
command=/usr/local/bin/nfsuserver
directory=/data
user=nfsu
autostart=true
autorestart=true
stderr_logfile=/var/log/nfsu/nfsuserver.err.log
stdout_logfile=/var/log/nfsu/nfsuserver.out.log
environment=HOME="/data",USER="nfsu"

[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"
autostart=true
autorestart=true
stderr_logfile=/var/log/nfsu/nginx.err.log
stdout_logfile=/var/log/nfsu/nginx.out.log

[program:php-fpm]
command=/usr/sbin/php-fpm82 -F
autostart=true
autorestart=true
stderr_logfile=/var/log/nfsu/php-fpm.err.log
stdout_logfile=/var/log/nfsu/php-fpm.out.log
EOF

# Create web UI configuration script
RUN cat > /usr/local/bin/configure-webui.sh << 'EOF'
#!/bin/sh
set -e

echo "Configuring NFSU Web UI..."

# Create web UI config if it doesn't exist
if [ ! -f /var/www/html/config.php ]; then
    cat > /var/www/html/config.php << 'WEBEOF'
<?php
// NFSU Server Web UI Configuration
// This file connects the web UI to the server

// Server connection settings
define('NFSU_SERVER_HOST', '127.0.0.1');
define('NFSU_SERVER_PORT', 10900);
define('NFSU_ADMIN_PORT', 9998);  // Admin port for server management

// Data directories
define('NFSU_DATA_DIR', '/data');
define('NFSU_LOG_DIR', '/var/log/nfsu');
define('NFSU_USERS_FILE', '/data/rusers.dat');
define('NFSU_CONFIG_FILE', '/data/nfsu.conf');
define('NFSU_NEWS_FILE', '/data/news.txt');
define('NFSU_LOG_FILE', '/var/log/nfsu/nfsuserver.out.log');

// Web UI settings
define('WEBUI_TITLE', 'NFS Underground Server Admin');
define('WEBUI_ADMIN_PASSWORD', 'admin123'); // Change this!
define('WEBUI_SESSION_TIMEOUT', 3600);
define('WEBUI_REFRESH_INTERVAL', 10);

// Server executable path
define('NFSU_SERVER_BINARY', '/usr/local/bin/nfsuserver');

// Enable web UI features
define('ENABLE_SERVER_CONTROL', true);
define('ENABLE_USER_MANAGEMENT', true);
define('ENABLE_LOG_VIEWER', true);
define('ENABLE_CONFIG_EDITOR', true);
?>
WEBEOF
fi

# Create .htaccess for better security if not exists
if [ ! -f /var/www/html/.htaccess ]; then
    cat > /var/www/html/.htaccess << 'WEBEOF'
# Deny access to sensitive files
<Files ~ "\.(dat|log|conf)$">
    Deny from all
</Files>

<Files ~ "^\.">
    Deny from all
</Files>

# PHP settings
php_value upload_max_filesize 32M
php_value post_max_size 32M
php_value max_execution_time 60
php_value memory_limit 128M
WEBEOF
fi

# Set proper permissions for web UI
chown -R nginx:nginx /var/www/html
find /var/www/html -type f -exec chmod 644 {} \;
find /var/www/html -type d -exec chmod 755 {} \;

# Make sure PHP can read data directory
chmod 755 /data
chmod 644 /data/* 2>/dev/null || true

# Create web UI session directory
mkdir -p /tmp/php-sessions
chown nginx:nginx /tmp/php-sessions
chmod 700 /tmp/php-sessions

# Create web UI log directory
mkdir -p /var/log/nfsu
chown nfsu:nfsu /var/log/nfsu
chmod 755 /var/log/nfsu

echo "Web UI configured successfully!"
echo "Web UI files:"
ls -la /var/www/html/
echo "Access the web UI at: http://your-server-ip:80"
echo "Default admin password: admin123 (please change this!)"
EOF

RUN chmod +x /usr/local/bin/configure-webui.sh

# Create startup script
RUN cat > /usr/local/bin/start-nfsuserver.sh << 'EOF'
#!/bin/sh
set -e

echo "Starting NFSU Server with Web UI..."

# Create necessary directories
mkdir -p /data /var/log/nfsu /run/nginx /run/php /tmp/php-sessions

# Configure web UI
/usr/local/bin/configure-webui.sh

# Set proper permissions
chown -R nfsu:nfsu /data /var/log/nfsu /run/php
chown -R nginx:nginx /run/nginx /tmp/php-sessions

# Create default config if it doesn't exist
if [ ! -f /data/nfsu.conf ]; then
    cat > /data/nfsu.conf << 'CONFEOF'
# NFSU Server Configuration
ServerName=Docker NFSU Server
ServerIP=0.0.0.0
MaxPlayers=16
RedirectorPort=10900
ListenerPort=10901
ReporterPort=10980
ClientReporterPort=10800
ClientReporterPortUDP=10800
ClientReporterPortTCP=10800
Verbose=1
EnableLogFile=1
LogLevel=2
AdminPassword=admin123
AdminPort=9998
EnableRemoteAdmin=1
CONFEOF
    chown nfsu:nfsu /data/nfsu.conf
fi

# Create default news file if it doesn't exist
if [ ! -f /data/news.txt ]; then
    cat > /data/news.txt << 'NEWSEOF'
=======================================
WELCOME TO NFSU SERVER
=======================================

Server is online and ready for racing!

- Web UI available at port 80
- Default admin password: admin123
- Please change the default password!

Have fun racing!
=======================================
NEWSEOF
    chown nfsu:nfsu /data/news.txt
fi

# Test nginx configuration
echo "Testing nginx configuration..."
/usr/sbin/nginx -t

# Start supervisord which manages all services
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/nfsuserver.conf
EOF

RUN chmod +x /usr/local/bin/start-nfsuserver.sh

# Set working directory
WORKDIR /data

# Expose all NFSU ports + web UI port
EXPOSE 10900/tcp \
       10901/tcp \
       10980/tcp \
       10800/tcp \
       10800/udp \
       80/tcp

# Health check (check both nfsuserver and nginx)
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD pgrep nfsuserver && pgrep nginx && curl -f http://localhost:80/ || exit 1

# Run the startup script
CMD ["/usr/local/bin/start-nfsuserver.sh"]
