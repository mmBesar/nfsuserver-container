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
    lighttpd \
    php83 \
    php83-fpm \
    php83-json \
    php83-session \
    php83-pdo \
    php83-pdo_sqlite \
    php83-sqlite3 \
    php83-mbstring \
    php83-openssl \
    php83-curl \
    php83-xml \
    php83-dom \
    php83-ctype \
    php83-fileinfo \
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
RUN mkdir -p /data /var/log/nfsu /var/log/lighttpd /var/lib/lighttpd /run/lighttpd /run/php && \
    chown -R nfsu:nfsu /data /var/log/nfsu /var/www/html && \
    chown -R lighttpd:lighttpd /var/log/lighttpd /var/lib/lighttpd /run/lighttpd && \
    chown -R nfsu:nfsu /run/php

# Configure lighttpd for web UI
RUN cat > /etc/lighttpd/lighttpd.conf << 'EOF'
server.modules = (
    "mod_access",
    "mod_alias",
    "mod_compress",
    "mod_redirect",
    "mod_rewrite",
    "mod_fastcgi",
    "mod_accesslog"
)

server.document-root        = "/var/www/html"
server.upload-dirs          = ( "/var/cache/lighttpd/uploads" )
server.errorlog             = "/var/log/lighttpd/error.log"
server.pid-file             = "/run/lighttpd/lighttpd.pid"
server.username             = "lighttpd"
server.groupname            = "lighttpd"
server.port                 = 8080

index-file.names            = ( "index.php", "index.html", "index.lighttpd.html" )
url.access-deny             = ( "~", ".inc" )
static-file.exclude-extensions = ( ".php", ".pl", ".fcgi" )

compress.cache-dir          = "/var/cache/lighttpd/compress/"
compress.filetype           = ( "application/javascript", "text/css", "text/html", "text/plain" )

# default listening port for IPv6 falls back to the IPv4 port
include_shell "/usr/share/lighttpd/use-ipv6.pl " + server.port
include_shell "/usr/share/lighttpd/create-mime.assign.pl"
include_shell "/usr/share/lighttpd/include-conf-enabled.pl"

# FastCGI for PHP
fastcgi.server = (
    ".php" => (
        "localhost" => (
            "socket"                => "/run/php/php83-fpm.sock",
            "broken-scriptfilename" => "enable"
        )
    )
)
EOF

# Configure PHP-FPM
RUN cat > /etc/php83/php-fpm.d/www.conf << 'EOF'
[www]
user = nfsu
group = nfsu
listen = /run/php/php83-fpm.sock
listen.owner = nfsu
listen.group = nfsu
listen.mode = 0660
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
EOF

# Configure supervisor to run both services
RUN cat > /etc/supervisor/conf.d/nfsuserver.conf << 'EOF'
[supervisord]
nodaemon=true
user=root
pidfile=/var/run/supervisord.pid
logfile=/var/log/supervisor/supervisord.log

[program:nfsuserver]
command=/usr/local/bin/nfsuserver
directory=/data
user=nfsu
autostart=true
autorestart=true
stdout_logfile=/var/log/nfsu/server.log
stderr_logfile=/var/log/nfsu/server.error.log
environment=HOME="/home/nfsu",USER="nfsu"

[program:php-fpm]
command=/usr/sbin/php-fpm83 --nodaemonize --fpm-config /etc/php83/php-fpm.conf
user=root
autostart=true
autorestart=true
stdout_logfile=/var/log/php-fpm.log
stderr_logfile=/var/log/php-fpm.error.log

[program:lighttpd]
command=/usr/sbin/lighttpd -D -f /etc/lighttpd/lighttpd.conf
user=root
autostart=true
autorestart=true
stdout_logfile=/var/log/lighttpd/access.log
stderr_logfile=/var/log/lighttpd/error.log
EOF

# Create cache directory for lighttpd
RUN mkdir -p /var/cache/lighttpd/compress /var/cache/lighttpd/uploads && \
    chown -R lighttpd:lighttpd /var/cache/lighttpd

# Set working directory
WORKDIR /data

# Expose all NFSU ports and web UI port
EXPOSE 10900/tcp \
       10901/tcp \
       10980/tcp \
       10800/tcp \
       10800/udp \
       8080/tcp

# Health check - check both nfsuserver and lighttpd
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD pgrep nfsuserver && pgrep lighttpd || exit 1

# Create startup script to handle permissions and initialization
RUN cat > /usr/local/bin/docker-entrypoint.sh << 'EOF'
#!/bin/sh
set -e

# Ensure correct permissions
chown -R nfsu:nfsu /data /var/www/html
chown -R lighttpd:lighttpd /var/log/lighttpd /var/lib/lighttpd /run/lighttpd /var/cache/lighttpd
chown -R nfsu:nfsu /run/php

# Create required directories if they don't exist
mkdir -p /var/log/supervisor /var/log/nfsu

# Start supervisor
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/nfsuserver.conf
EOF

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Run with supervisor managing both services
CMD ["/usr/local/bin/docker-entrypoint.sh"]
