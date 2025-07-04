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
    php82-iconv \
    php82-openssl \
    supervisor \
    curl \
    bash \
    && ln -sf /usr/bin/php82 /usr/bin/php

# Create non-root user for security
RUN addgroup -g 1000 nfsu && \
    adduser -D -u 1000 -G nfsu nfsu

# Copy the built binary
COPY --from=builder /build/nfsuserver/nfsuserver/nfsuserver /usr/local/bin/

# Copy the original web UI files
COPY --from=builder /build/nfsuserver/web /var/www/html

# Create necessary directories
RUN mkdir -p /data /var/log/nfsu /var/www/html /run/nginx /run/php /etc/supervisor/conf.d /tmp/php-sessions && \
    chown -R nfsu:nfsu /data /var/log/nfsu && \
    chown -R nginx:nginx /var/www/html /run/nginx /tmp/php-sessions && \
    chown -R nfsu:nfsu /run/php && \
    chmod 755 /var/www/html && \
    chmod 700 /tmp/php-sessions

# Configure nginx for the web UI
RUN cat > /etc/nginx/nginx.conf << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
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
        
        # Main location block
        location / {
            try_files $uri $uri/ /index.php?$query_string;
        }
        
        # PHP processing
        location ~ \.php$ {
            include fastcgi_params;
            fastcgi_pass 127.0.0.1:9000;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            fastcgi_param PATH_INFO $fastcgi_path_info;
            fastcgi_param DOCUMENT_ROOT $document_root;
            
            # Pass server data directory to PHP
            fastcgi_param NFSU_DATA_DIR /data;
            fastcgi_param NFSU_LOG_DIR /var/log/nfsu;
            fastcgi_param NFSU_SERVER_HOST 127.0.0.1;
            fastcgi_param NFSU_SERVER_PORT 10900;
            
            # Security
            fastcgi_param HTTP_PROXY "";
            fastcgi_split_path_info ^(.+\.php)(/.+)$;
            
            # Timeouts
            fastcgi_connect_timeout 60;
            fastcgi_send_timeout 180;
            fastcgi_read_timeout 180;
            fastcgi_buffer_size 128k;
            fastcgi_buffers 4 256k;
            fastcgi_busy_buffers_size 256k;
            fastcgi_temp_file_write_size 256k;
        }
        
        # Deny access to sensitive files
        location ~ /\.ht {
            deny all;
        }
        
        location ~ /\.git {
            deny all;
        }
        
        location ~ \.(log|dat|conf|bak|backup)$ {
            deny all;
        }
        
        # Allow static assets with caching
        location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
            access_log off;
        }
        
        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "no-referrer-when-downgrade" always;
        add_header Content-Security-Policy "default-src 'self' 'unsafe-inline' 'unsafe-eval' data: blob:; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline';" always;
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
listen.mode = 0660
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.max_requests = 500
chdir = /
php_admin_value[upload_max_filesize] = 32M
php_admin_value[post_max_size] = 32M
php_admin_value[memory_limit] = 128M
php_admin_value[max_execution_time] = 60
php_admin_value[max_input_time] = 60
php_admin_value[session.save_path] = /tmp/php-sessions
php_admin_value[error_log] = /var/log/nfsu/php_errors.log
php_admin_value[log_errors] = on
php_admin_value[display_errors] = off
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
session.save_path = /tmp/php-sessions
upload_max_filesize = 32M
post_max_size = 32M
max_input_vars = 3000
memory_limit = 128M
max_execution_time = 60
max_input_time = 60

; Enable required extensions
extension=sockets
extension=json
extension=session
extension=mbstring
extension=curl
extension=pdo
extension=pdo_sqlite
extension=sqlite3
extension=xml
extension=simplexml
extension=dom
extension=ctype
extension=fileinfo
extension=iconv
extension=openssl
EOF

# Configure supervisord
RUN cat > /etc/supervisor/conf.d/nfsuserver.conf << 'EOF'
[supervisord]
nodaemon=true
user=root
logfile=/var/log/nfsu/supervisord.log
pidfile=/run/supervisord.pid
childlogdir=/var/log/nfsu

[program:nfsuserver]
command=/usr/local/bin/nfsuserver
directory=/data
user=nfsu
autostart=true
autorestart=true
startsecs=5
stderr_logfile=/var/log/nfsu/nfsuserver.err.log
stdout_logfile=/var/log/nfsu/nfsuserver.out.log
stdout_logfile_maxbytes=50MB
stdout_logfile_backups=10
stderr_logfile_maxbytes=50MB
stderr_logfile_backups=10
environment=HOME="/data",USER="nfsu"

[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"
autostart=true
autorestart=true
startsecs=5
stderr_logfile=/var/log/nfsu/nginx.err.log
stdout_logfile=/var/log/nfsu/nginx.out.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=3
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=3

[program:php-fpm]
command=/usr/sbin/php-fpm82 -F
autostart=true
autorestart=true
startsecs=5
stderr_logfile=/var/log/nfsu/php-fpm.err.log
stdout_logfile=/var/log/nfsu/php-fpm.out.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=3
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=3
EOF

# Create web UI configuration and setup script
RUN cat > /usr/local/bin/setup-webui.sh << 'EOF'
#!/bin/bash
set -e

echo "Setting up NFSU Web UI..."

# Create necessary directories
mkdir -p /data /var/log/nfsu /tmp/php-sessions /run/nginx /run/php

# Set proper permissions
chown -R nfsu:nfsu /data /var/log/nfsu /run/php
chown -R nginx:nginx /var/www/html /run/nginx /tmp/php-sessions
chmod 755 /var/www/html
chmod 700 /tmp/php-sessions

# Create web UI configuration file if it doesn't exist
if [ ! -f /var/www/html/config.php ]; then
    echo "Creating web UI configuration..."
    cat > /var/www/html/config.php << 'WEBEOF'
<?php
// NFSU Server Web UI Configuration
// This file connects the web UI to the server

// Server connection settings
define('NFSU_SERVER_HOST', '127.0.0.1');
define('NFSU_SERVER_PORT', 10900);
define('NFSU_ADMIN_PORT', 9998);

// Data directories
define('NFSU_DATA_DIR', '/data');
define('NFSU_LOG_DIR', '/var/log/nfsu');
define('NFSU_USERS_FILE', '/data/rusers.dat');
define('NFSU_CONFIG_FILE', '/data/nfsu.conf');
define('NFSU_NEWS_FILE', '/data/news.txt');
define('NFSU_LOG_FILE', '/var/log/nfsu/nfsuserver.out.log');
define('NFSU_ERROR_LOG', '/var/log/nfsu/nfsuserver.err.log');

// Web UI settings
define('WEBUI_TITLE', 'NFS Underground Server Admin');
define('WEBUI_ADMIN_USERNAME', 'admin');
define('WEBUI_ADMIN_PASSWORD', 'admin123'); // CHANGE THIS!
define('WEBUI_SESSION_TIMEOUT', 3600);
define('WEBUI_REFRESH_INTERVAL', 30);

// Server executable path
define('NFSU_SERVER_BINARY', '/usr/local/bin/nfsuserver');

// Enable web UI features
define('ENABLE_SERVER_CONTROL', true);
define('ENABLE_USER_MANAGEMENT', true);
define('ENABLE_LOG_VIEWER', true);
define('ENABLE_CONFIG_EDITOR', true);
define('ENABLE_NEWS_EDITOR', true);

// Security settings
define('ENABLE_BRUTE_FORCE_PROTECTION', true);
define('MAX_LOGIN_ATTEMPTS', 5);
define('LOCKOUT_DURATION', 300); // 5 minutes

// Log settings
define('WEBUI_LOG_LEVEL', 'INFO');
define('WEBUI_LOG_FILE', '/var/log/nfsu/webui.log');
?>
WEBEOF
fi

# Create .htaccess for better security
if [ ! -f /var/www/html/.htaccess ]; then
    echo "Creating .htaccess file..."
    cat > /var/www/html/.htaccess << 'WEBEOF'
# Deny access to sensitive files
<Files ~ "\.(dat|log|conf|bak|backup)$">
    Deny from all
</Files>

<Files ~ "^\.">
    Deny from all
</Files>

<Files "config.php">
    Deny from all
</Files>

# Security headers
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-XSS-Protection "1; mode=block"
Header always set X-Content-Type-Options "nosniff"

# PHP settings
php_value upload_max_filesize 32M
php_value post_max_size 32M
php_value max_execution_time 60
php_value memory_limit 128M
php_value session.cookie_httponly 1
php_value session.use_strict_mode 1
WEBEOF
fi

# Set final permissions
chown -R nginx:nginx /var/www/html
find /var/www/html -type f -exec chmod 644 {} \;
find /var/www/html -type d -exec chmod 755 {} \;
chmod 600 /var/www/html/config.php

echo "Web UI setup completed successfully!"
echo "Web UI files:"
ls -la /var/www/html/
echo ""
echo "Access the web UI at: http://your-server-ip:80"
echo "Default credentials: admin / admin123"
echo "⚠️  IMPORTANT: Please change the default password in config.php!"
EOF

RUN chmod +x /usr/local/bin/setup-webui.sh

# Create startup script
RUN cat > /usr/local/bin/start-nfsuserver.sh << 'EOF'
#!/bin/bash
set -e

echo "Starting NFSU Server with Web UI..."

# Setup web UI
/usr/local/bin/setup-webui.sh

# Create default server config if it doesn't exist
if [ ! -f /data/nfsu.conf ]; then
    echo "Creating default server configuration..."
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
LogFile=/var/log/nfsu/nfsuserver.out.log
AdminPassword=admin123
AdminPort=9998
EnableRemoteAdmin=1
EnableWebUI=1
WebUIPort=80
DatabaseFile=/data/rusers.dat
NewsFile=/data/news.txt
TrackRotation=1
DefaultLaps=3
MaxLaps=10
AllowSpectators=1
AutoStartRace=0
RaceTimeout=300
LobbyTimeout=60
AllowDuplicateNames=0
RequireRegistration=0
MaxNameLength=20
BanDuration=3600
AllowTuning=1
MaxRooms=10
EnableAntiCheat=1
CONFEOF
    chown nfsu:nfsu /data/nfsu.conf
    echo "Default configuration created."
fi

# Create default news file if it doesn't exist
if [ ! -f /data/news.txt ]; then
    echo "Creating default news file..."
    cat > /data/news.txt << 'NEWSEOF'
=======================================
WELCOME TO NFSU SERVER
=======================================

🏁 Server is online and ready for racing!

📋 Server Information:
• Web UI available at port 80
• Maximum players: 16
• All original tracks available
• Tuning enabled

🔧 Web Admin Panel:
• Username: admin
• Password: admin123
• Please change default password!

🏎️ Racing Rules:
• No cheating or hacking
• Respect other players
• Use "Create Game" not challenges
• Have fun racing!

⚠️ Support:
Report issues through web UI or
contact server administrator.

=======================================
Last updated: $(date)
=======================================
NEWSEOF
    chown nfsu:nfsu /data/news.txt
    echo "Default news file created."
fi

# Test nginx configuration
echo "Testing nginx configuration..."
/usr/sbin/nginx -t

# Create log files with proper permissions
touch /var/log/nfsu/nfsuserver.out.log /var/log/nfsu/nfsuserver.err.log
touch /var/log/nfsu/nginx.out.log /var/log/nfsu/nginx.err.log
touch /var/log/nfsu/php-fpm.out.log /var/log/nfsu/php-fpm.err.log
touch /var/log/nfsu/php_errors.log /var/log/nfsu/webui.log
chown nfsu:nfsu /var/log/nfsu/nfsuserver.* /var/log/nfsu/webui.log
chown nginx:nginx /var/log/nfsu/nginx.* /var/log/nfsu/php-fpm.* /var/log/nfsu/php_errors.log

echo "Starting services with supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/nfsuserver.conf
EOF

RUN chmod +x /usr/local/bin/start-nfsuserver.sh

# Set working directory
WORKDIR /data

# Expose NFSU server ports + web UI port
EXPOSE 10900/tcp \
       10901/tcp \
       10980/tcp \
       10800/tcp \
       10800/udp \
       80/tcp

# Health check - check all services
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD pgrep -f nfsuserver > /dev/null && \
        pgrep -f nginx > /dev/null && \
        pgrep -f php-fpm > /dev/null && \
        curl -f http://localhost:80/ > /dev/null 2>&1 || exit 1

# Labels for better container management
LABEL org.opencontainers.image.title="NFSU Server with Web UI" \
      org.opencontainers.image.description="Need for Speed Underground Server with Web Management Interface" \
      org.opencontainers.image.source="https://github.com/mmBesar/nfsuserver-container" \
      org.opencontainers.image.version="1.0" \
      org.opencontainers.image.vendor="mmBesar" \
      maintainer="mmBesar"

# Run the startup script
CMD ["/usr/local/bin/start-nfsuserver.sh"]
