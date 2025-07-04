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
    supervisor \
    curl \
    && ln -sf /usr/bin/php82 /usr/bin/php

# Create non-root user for security
RUN addgroup -g 1000 nfsu && \
    adduser -D -u 1000 -G nfsu nfsu

# Copy the built binary
COPY --from=builder /build/nfsuserver/nfsuserver/nfsuserver /usr/local/bin/

# Copy the web UI files
COPY --from=builder /build/nfsuserver/web /var/www/html

# Create necessary directories
RUN mkdir -p /data /var/log/nfsu /var/www/html /run/nginx /run/php /etc/supervisor/conf.d && \
    chown -R nfsu:nfsu /data /var/log/nfsu && \
    chown -R nginx:nginx /var/www/html /run/nginx && \
    chown -R nfsu:nfsu /run/php

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
        }
        
        location ~ /\.ht {
            deny all;
        }
        
        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "no-referrer-when-downgrade" always;
        add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    }
}
EOF

# Configure PHP-FPM
RUN cat > /etc/php82/php-fpm.d/www.conf << 'EOF'
[www]
user = nfsu
group = nfsu
listen = 127.0.0.1:9000
listen.owner = nfsu
listen.group = nfsu
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
chdir = /
php_admin_value[upload_max_filesize] = 32M
php_admin_value[post_max_size] = 32M
php_admin_value[memory_limit] = 128M
php_admin_value[max_execution_time] = 60
php_admin_value[session.save_path] = /tmp
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
# Configure web UI to connect to the local nfsuserver

echo "Configuring Web UI..."
echo "Contents of /var/www/html:"
ls -la /var/www/html/ || echo "Directory doesn't exist!"

# If web directory is empty, create a simple index page
if [ ! -f /var/www/html/index.php ] && [ ! -f /var/www/html/index.html ]; then
    echo "Creating basic web UI since original web directory is empty..."
    cat > /var/www/html/index.php << 'WEBEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NFS Underground Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f4f4f4; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; text-align: center; }
        .status { background: #e8f5e8; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .info { background: #f0f8ff; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .server-info { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin: 20px 0; }
        .card { background: #f9f9f9; padding: 15px; border-radius: 5px; border-left: 4px solid #007cba; }
        .footer { text-align: center; margin-top: 30px; color: #666; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🏎️ NFS Underground Server</h1>
        
        <div class="status">
            <h3>✅ Server Status: Online</h3>
            <p>The NFS Underground server is running and ready for connections.</p>
        </div>

        <div class="server-info">
            <div class="card">
                <h4>🌐 Server Info</h4>
                <p><strong>Server:</strong> <?php echo gethostname(); ?></p>
                <p><strong>Time:</strong> <?php echo date('Y-m-d H:i:s'); ?></p>
                <p><strong>Uptime:</strong> <?php echo shell_exec('uptime -p') ?: 'N/A'; ?></p>
            </div>
            
            <div class="card">
                <h4>🎮 Game Ports</h4>
                <p><strong>Redirector:</strong> 10900/tcp</p>
                <p><strong>Listener:</strong> 10901/tcp</p>
                <p><strong>Reporter:</strong> 10980/tcp</p>
                <p><strong>ClientReporter:</strong> 10800/tcp+udp</p>
            </div>
        </div>

        <div class="info">
            <h4>📋 Server Files</h4>
            <p><strong>Data Directory:</strong> /data</p>
            <p><strong>Config File:</strong> <?php echo file_exists('/data/nfsu.conf') ? '✅ Found' : '❌ Missing'; ?></p>
            <p><strong>Users Database:</strong> <?php echo file_exists('/data/rusers.dat') ? '✅ Found (' . filesize('/data/rusers.dat') . ' bytes)' : '❌ Not created yet'; ?></p>
            <p><strong>News File:</strong> <?php echo file_exists('/data/news.txt') ? '✅ Found' : '❌ Missing'; ?></p>
        </div>

        <div class="info">
            <h4>🔧 Process Status</h4>
            <p><strong>NFSU Server:</strong> <?php echo shell_exec('pgrep nfsuserver') ? '✅ Running (PID: ' . trim(shell_exec('pgrep nfsuserver')) . ')' : '❌ Not running'; ?></p>
            <p><strong>Nginx:</strong> <?php echo shell_exec('pgrep nginx') ? '✅ Running' : '❌ Not running'; ?></p>
            <p><strong>PHP-FPM:</strong> <?php echo shell_exec('pgrep php-fpm') ? '✅ Running' : '❌ Not running'; ?></p>
        </div>

        <div class="info">
            <h4>📊 Server Logs (Last 10 lines)</h4>
            <pre style="background: #000; color: #0f0; padding: 10px; border-radius: 5px; overflow-x: auto; font-size: 0.8em;"><?php
                $logFile = '/var/log/nfsu/nfsuserver.out.log';
                if (file_exists($logFile)) {
                    echo htmlspecialchars(shell_exec("tail -n 10 $logFile"));
                } else {
                    echo "No log file found yet.";
                }
            ?></pre>
        </div>

        <div class="footer">
            <p>NFSU Server Web UI - Container Version</p>
            <p>Original server by <a href="https://github.com/HarpyWar/nfsuserver">HarpyWar/nfsuserver</a></p>
        </div>
    </div>
</body>
</html>
WEBEOF
fi

# Create basic web UI config if it doesn't exist
if [ ! -f /var/www/html/config.php ]; then
    cat > /var/www/html/config.php << 'WEBEOF'
<?php
// NFSU Server Web UI Configuration
define('NFSU_SERVER_HOST', 'localhost');
define('NFSU_SERVER_PORT', 10900);
define('NFSU_DATA_DIR', '/data');
define('NFSU_LOG_DIR', '/var/log/nfsu');
define('NFSU_USERS_FILE', '/data/rusers.dat');
define('NFSU_CONFIG_FILE', '/data/nfsu.conf');
define('NFSU_NEWS_FILE', '/data/news.txt');

// Web UI Settings
define('WEBUI_TITLE', 'NFS Underground Server');
define('WEBUI_ADMIN_PASSWORD', 'admin123'); // Change this!
define('WEBUI_SESSION_TIMEOUT', 3600);
define('WEBUI_LOG_LEVEL', 'info');

// Database settings (if using database features)
define('DB_TYPE', 'sqlite');
define('DB_PATH', '/data/webui.db');
?>
WEBEOF
fi

# Set proper permissions
chown -R nginx:nginx /var/www/html
chmod 755 /var/www/html
find /var/www/html -type f -name "*.php" -exec chmod 644 {} \;

# Create web UI database if it doesn't exist
if [ ! -f /data/webui.db ]; then
    touch /data/webui.db
    chown nfsu:nfsu /data/webui.db
    chmod 644 /data/webui.db
fi

# Ensure log directory exists and has proper permissions
mkdir -p /var/log/nfsu
chown nfsu:nfsu /var/log/nfsu
chmod 755 /var/log/nfsu

echo "Web UI configured successfully!"
echo "Web files in /var/www/html:"
ls -la /var/www/html/
EOF

RUN chmod +x /usr/local/bin/configure-webui.sh

# Create startup script
RUN cat > /usr/local/bin/start-nfsuserver.sh << 'EOF'
#!/bin/sh
set -e

echo "Starting NFSU Server with Web UI..."

# Configure web UI
/usr/local/bin/configure-webui.sh

# Create necessary directories
mkdir -p /data /var/log/nfsu /run/nginx /run/php

# Set proper permissions
chown -R nfsu:nfsu /data /var/log/nfsu /run/php
chown -R nginx:nginx /run/nginx

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
