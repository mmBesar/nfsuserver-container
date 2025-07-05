# Use Alpine Linux for minimal size
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

# Runtime stage - minimal Alpine with web server
FROM alpine:3.19

# Install runtime dependencies
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
    php82-fileinfo \
    php82-sockets \
    supervisor \
    curl \
    && ln -sf /usr/bin/php82 /usr/bin/php

# Create user and directories
RUN addgroup -g 1000 nfsu && \
    adduser -D -u 1000 -G nfsu nfsu && \
    mkdir -p /data /var/log/nfsu /var/www/html /run/nginx /run/php /etc/supervisor/conf.d

# Copy server binary
COPY --from=builder /build/nfsuserver/nfsuserver/nfsuserver /usr/local/bin/

# Copy web UI files
COPY --from=builder /build/nfsuserver/web /var/www/html/

# Configure nginx
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
    
    access_log /var/log/nginx/access.log;
    sendfile on;
    keepalive_timeout 65;
    
    server {
        listen 80;
        root /var/www/html;
        index index.php index.html;
        
        client_max_body_size 32M;
        
        location / {
            try_files $uri $uri/ /index.php?$query_string;
        }
        
        location ~ \.php$ {
            fastcgi_pass 127.0.0.1:9000;
            fastcgi_index index.php;
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            fastcgi_param NFSU_DATA_DIR /data;
            fastcgi_param NFSU_LOG_DIR /var/log/nfsu;
        }
        
        location ~ /\.(ht|git) {
            deny all;
        }
    }
}
EOF

# Configure PHP-FPM
RUN cat > /etc/php82/php-fpm.d/www.conf << 'EOF'
[www]
user = nginx
group = nginx
listen = 127.0.0.1:9000
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
php_admin_value[upload_max_filesize] = 32M
php_admin_value[post_max_size] = 32M
php_admin_value[memory_limit] = 64M
EOF

# Configure supervisord
RUN cat > /etc/supervisor/conf.d/services.conf << 'EOF'
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

# Create startup script
RUN cat > /usr/local/bin/start-server.sh << 'EOF'
#!/bin/sh
set -e

# Create directories and set permissions
mkdir -p /data /var/log/nfsu /run/nginx /run/php
chown -R nfsu:nfsu /data /var/log/nfsu /run/php
chown -R nginx:nginx /var/www/html /run/nginx

# Create default server config if not exists
if [ ! -f /data/nfsu.conf ]; then
    cat > /data/nfsu.conf << 'CONFEOF'
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

# Create default news file if not exists
if [ ! -f /data/news.txt ]; then
    cat > /data/news.txt << 'NEWSEOF'
Welcome to NFSU Docker Server!
Web UI is available at port 80
Default admin password: admin123
Please change the default password!
NEWSEOF
    chown nfsu:nfsu /data/news.txt
fi

# Create web UI config if not exists
if [ ! -f /var/www/html/config.php ]; then
    cat > /var/www/html/config.php << 'WEBEOF'
<?php
// Web UI Configuration
define('NFSU_DATA_DIR', '/data');
define('NFSU_LOG_DIR', '/var/log/nfsu');
define('NFSU_SERVER_HOST', '127.0.0.1');
define('NFSU_SERVER_PORT', 10900);
define('NFSU_ADMIN_PORT', 9998);
define('WEBUI_ADMIN_PASSWORD', 'admin123');
?>
WEBEOF
    chown nginx:nginx /var/www/html/config.php
fi

# Set proper permissions
chmod 755 /data
chmod 644 /data/* 2>/dev/null || true

# Start supervisord
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/services.conf
EOF

RUN chmod +x /usr/local/bin/start-server.sh

# Set working directory
WORKDIR /data

# Expose ports
EXPOSE 10900/tcp 10901/tcp 10980/tcp 10800/tcp 10800/udp 80/tcp

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD pgrep nfsuserver && pgrep nginx && curl -f http://localhost:80/ || exit 1

# Run startup script
CMD ["/usr/local/bin/start-server.sh"]
