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

# Runtime stage - minimal Alpine image with web server
FROM alpine:3.19

# Install runtime dependencies including web server
RUN apk add --no-cache \
    libstdc++ \
    libgcc \
    nginx \
    php83 \
    php83-fpm \
    php83-json \
    php83-session \
    php83-mbstring \
    php83-curl \
    php83-xml \
    php83-simplexml \
    php83-dom \
    php83-pdo \
    php83-pdo_sqlite \
    php83-sqlite3 \
    php83-fileinfo \
    php83-opcache \
    supervisor \
    && ln -sf /usr/bin/php83 /usr/bin/php

# Create non-root user for security
RUN addgroup -g 1000 nfsu && \
    adduser -D -u 1000 -G nfsu nfsu

# Copy the built binary
COPY --from=builder /build/nfsuserver/nfsuserver/nfsuserver /usr/local/bin/

# Copy web UI files
COPY --from=builder /build/nfsuserver/web /var/www/html/

# Create necessary directories
RUN mkdir -p /data \
    /var/log/nfsu \
    /var/log/nginx \
    /var/log/supervisor \
    /run/nginx \
    /run/php-fpm83 \
    && chown -R nfsu:nfsu /data /var/log/nfsu \
    && chown -R nginx:nginx /var/www/html /var/log/nginx /run/nginx \
    && chown -R nfsu:nfsu /run/php-fpm83

# Configure Nginx
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
        server_name _;
        root /var/www/html;
        index index.php index.html index.htm;

        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;

        # PHP handling
        location ~ \.php$ {
            try_files $uri =404;
            fastcgi_split_path_info ^(.+\.php)(/.+)$;
            fastcgi_pass unix:/run/php-fpm83/php-fpm.sock;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            include fastcgi_params;
        }

        # Static files
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }

        # Deny access to sensitive files
        location ~ /\. {
            deny all;
        }

        location ~ ~$ {
            deny all;
        }
    }
}
EOF

# Configure PHP-FPM
RUN cat > /etc/php83/php-fpm.d/www.conf << 'EOF'
[www]
user = nfsu
group = nfsu
listen = /run/php-fpm83/php-fpm.sock
listen.owner = nginx
listen.group = nginx
listen.mode = 0660
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.max_requests = 500
php_admin_value[error_log] = /var/log/nfsu/php_errors.log
php_admin_flag[log_errors] = on
php_value[session.save_path] = /tmp
EOF

# Configure PHP settings
RUN cat > /etc/php83/conf.d/99-nfsu.ini << 'EOF'
; NFSU Server Web UI Configuration
memory_limit = 128M
upload_max_filesize = 16M
post_max_size = 16M
max_execution_time = 30
max_input_time = 60
display_errors = Off
log_errors = On
error_log = /var/log/nfsu/php_errors.log

; Session configuration
session.save_path = /tmp
session.gc_maxlifetime = 1440
session.cookie_httponly = On
session.use_strict_mode = On

; Security
expose_php = Off
allow_url_fopen = Off
allow_url_include = Off
EOF

# Create supervisor configuration
RUN cat > /etc/supervisor/conf.d/supervisord.conf << 'EOF'
[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisor/supervisord.log
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

[program:php-fpm]
command=/usr/sbin/php-fpm83 --nodaemonize --fpm-config /etc/php83/php-fpm.conf
user=root
autostart=true
autorestart=true
stderr_logfile=/var/log/nfsu/php-fpm.err.log
stdout_logfile=/var/log/nfsu/php-fpm.out.log

[program:nginx]
command=/usr/sbin/nginx -g 'daemon off;'
user=root
autostart=true
autorestart=true
stderr_logfile=/var/log/nginx/nginx.err.log
stdout_logfile=/var/log/nginx/nginx.out.log
EOF

# Create startup script
RUN cat > /usr/local/bin/start-nfsuserver.sh << 'EOF'
#!/bin/sh
set -e

# Create necessary directories if they don't exist
mkdir -p /data /var/log/nfsu /tmp
chown -R nfsu:nfsu /data /var/log/nfsu

# Create default config if it doesn't exist
if [ ! -f /data/nfsu.conf ]; then
    cat > /data/nfsu.conf << 'EOC'
# NFS Underground Server Configuration
ServerName=NFSU Docker Server
MaxPlayers=16
ServerPassword=

# Network Settings
ServerIP=0.0.0.0
ServerExternalIP=0.0.0.0
RedirectorPort=10900
ListenerPort=10901
ReporterPort=10980
ClientReporterPort=10800
ClientReporterPortUDP=10800
ClientReporterPortTCP=10800

# Game Settings
TrackRotation=1
DefaultLaps=3
MaxLaps=10
AllowSpectators=1
AutoStartRace=0
RaceTimeout=300
LobbyTimeout=60

# Player Settings
AllowDuplicateNames=0
RequireRegistration=0
MaxNameLength=20
BanDuration=3600

# Logging Settings
LogLevel=2
LogToFile=1
LogFileName=/var/log/nfsu/server.log
LogRotate=1
MaxLogSize=10485760

# Database Settings
DatabaseFile=/data/rusers.dat
BackupDatabase=1
BackupInterval=3600

# Web UI Settings
WebUIEnabled=1
WebUIPort=80
WebUIPath=/var/www/html
EOC
    chown nfsu:nfsu /data/nfsu.conf
fi

# Create default news.txt if it doesn't exist
if [ ! -f /data/news.txt ]; then
    cat > /data/news.txt << 'EOC'
===============================================
WELCOME TO NFS UNDERGROUND SERVER
===============================================
📰 NEWS & ANNOUNCEMENTS:
• Server is now online with Web UI!
• Access web interface at http://your-server-ip
• New players welcome - register your profile!

🏎️ SERVER RULES:
• No cheating, hacking, or exploiting
• Respect other players
• No offensive language or behavior

🔧 WEB INTERFACE:
• Monitor server status
• View connected players
• Manage server settings
• Check race statistics

===============================================
HAVE FUN AND RACE SAFELY!
===============================================
EOC
    chown nfsu:nfsu /data/news.txt
fi

# Set proper permissions for web files
chown -R nginx:nginx /var/www/html
find /var/www/html -type f -exec chmod 644 {} \;
find /var/www/html -type d -exec chmod 755 {} \;

# Start supervisor
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
EOF

RUN chmod +x /usr/local/bin/start-nfsuserver.sh

# Set working directory
WORKDIR /data

# Expose all NFSU ports plus HTTP for web UI
EXPOSE 10900/tcp \
       10901/tcp \
       10980/tcp \
       10800/tcp \
       10800/udp \
       80/tcp

# Health check for both server and web UI
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD pgrep nfsuserver && pgrep nginx && pgrep php-fpm83 || exit 1

# Run the startup script
CMD ["/usr/local/bin/start-nfsuserver.sh"]
