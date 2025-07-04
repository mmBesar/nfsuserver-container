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
RUN mkdir -p /data /var/log/nfsu /var/log/lighttpd /var/lib/lighttpd /run/lighttpd /run/php \
    /etc/supervisor/conf.d /var/log/supervisor /var/cache/lighttpd/compress /var/cache/lighttpd/uploads && \
    chown -R nfsu:nfsu /data /var/log/nfsu /var/www/html && \
    chown -R lighttpd:lighttpd /var/log/lighttpd /var/lib/lighttpd /run/lighttpd /var/cache/lighttpd && \
    chown -R nfsu:nfsu /run/php

# Configure lighttpd for web UI
RUN echo 'server.modules = (' > /etc/lighttpd/lighttpd.conf && \
    echo '    "mod_access",' >> /etc/lighttpd/lighttpd.conf && \
    echo '    "mod_alias",' >> /etc/lighttpd/lighttpd.conf && \
    echo '    "mod_compress",' >> /etc/lighttpd/lighttpd.conf && \
    echo '    "mod_redirect",' >> /etc/lighttpd/lighttpd.conf && \
    echo '    "mod_rewrite",' >> /etc/lighttpd/lighttpd.conf && \
    echo '    "mod_fastcgi",' >> /etc/lighttpd/lighttpd.conf && \
    echo '    "mod_accesslog"' >> /etc/lighttpd/lighttpd.conf && \
    echo ')' >> /etc/lighttpd/lighttpd.conf && \
    echo '' >> /etc/lighttpd/lighttpd.conf && \
    echo 'server.document-root        = "/var/www/html"' >> /etc/lighttpd/lighttpd.conf && \
    echo 'server.upload-dirs          = ( "/var/cache/lighttpd/uploads" )' >> /etc/lighttpd/lighttpd.conf && \
    echo 'server.errorlog             = "/var/log/lighttpd/error.log"' >> /etc/lighttpd/lighttpd.conf && \
    echo 'server.pid-file             = "/run/lighttpd/lighttpd.pid"' >> /etc/lighttpd/lighttpd.conf && \
    echo 'server.username             = "lighttpd"' >> /etc/lighttpd/lighttpd.conf && \
    echo 'server.groupname            = "lighttpd"' >> /etc/lighttpd/lighttpd.conf && \
    echo 'server.port                 = 8080' >> /etc/lighttpd/lighttpd.conf && \
    echo '' >> /etc/lighttpd/lighttpd.conf && \
    echo 'index-file.names            = ( "index.php", "index.html", "index.lighttpd.html" )' >> /etc/lighttpd/lighttpd.conf && \
    echo 'url.access-deny             = ( "~", ".inc" )' >> /etc/lighttpd/lighttpd.conf && \
    echo 'static-file.exclude-extensions = ( ".php", ".pl", ".fcgi" )' >> /etc/lighttpd/lighttpd.conf && \
    echo '' >> /etc/lighttpd/lighttpd.conf && \
    echo 'compress.cache-dir          = "/var/cache/lighttpd/compress/"' >> /etc/lighttpd/lighttpd.conf && \
    echo 'compress.filetype           = ( "application/javascript", "text/css", "text/html", "text/plain" )' >> /etc/lighttpd/lighttpd.conf && \
    echo '' >> /etc/lighttpd/lighttpd.conf && \
    echo 'include_shell "/usr/share/lighttpd/use-ipv6.pl " + server.port' >> /etc/lighttpd/lighttpd.conf && \
    echo 'include_shell "/usr/share/lighttpd/create-mime.assign.pl"' >> /etc/lighttpd/lighttpd.conf && \
    echo 'include_shell "/usr/share/lighttpd/include-conf-enabled.pl"' >> /etc/lighttpd/lighttpd.conf && \
    echo '' >> /etc/lighttpd/lighttpd.conf && \
    echo 'fastcgi.server = (' >> /etc/lighttpd/lighttpd.conf && \
    echo '    ".php" => (' >> /etc/lighttpd/lighttpd.conf && \
    echo '        "localhost" => (' >> /etc/lighttpd/lighttpd.conf && \
    echo '            "socket"                => "/run/php/php83-fpm.sock",' >> /etc/lighttpd/lighttpd.conf && \
    echo '            "broken-scriptfilename" => "enable"' >> /etc/lighttpd/lighttpd.conf && \
    echo '        )' >> /etc/lighttpd/lighttpd.conf && \
    echo '    )' >> /etc/lighttpd/lighttpd.conf && \
    echo ')' >> /etc/lighttpd/lighttpd.conf

# Configure PHP-FPM
RUN echo '[www]' > /etc/php83/php-fpm.d/www.conf && \
    echo 'user = nfsu' >> /etc/php83/php-fpm.d/www.conf && \
    echo 'group = nfsu' >> /etc/php83/php-fpm.d/www.conf && \
    echo 'listen = /run/php/php83-fpm.sock' >> /etc/php83/php-fpm.d/www.conf && \
    echo 'listen.owner = nfsu' >> /etc/php83/php-fpm.d/www.conf && \
    echo 'listen.group = nfsu' >> /etc/php83/php-fpm.d/www.conf && \
    echo 'listen.mode = 0660' >> /etc/php83/php-fpm.d/www.conf && \
    echo 'pm = dynamic' >> /etc/php83/php-fpm.d/www.conf && \
    echo 'pm.max_children = 5' >> /etc/php83/php-fpm.d/www.conf && \
    echo 'pm.start_servers = 2' >> /etc/php83/php-fpm.d/www.conf && \
    echo 'pm.min_spare_servers = 1' >> /etc/php83/php-fpm.d/www.conf && \
    echo 'pm.max_spare_servers = 3' >> /etc/php83/php-fpm.d/www.conf

# Configure supervisor to run both services
RUN echo '[supervisord]' > /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'nodaemon=true' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'user=root' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'pidfile=/var/run/supervisord.pid' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'logfile=/var/log/supervisor/supervisord.log' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo '' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo '[program:nfsuserver]' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'command=/usr/local/bin/nfsuserver' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'directory=/data' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'user=nfsu' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'stdout_logfile=/var/log/nfsu/server.log' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'stderr_logfile=/var/log/nfsu/server.error.log' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'environment=HOME="/home/nfsu",USER="nfsu"' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo '' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo '[program:php-fpm]' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'command=/usr/sbin/php-fpm83 --nodaemonize --fpm-config /etc/php83/php-fpm.conf' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'user=root' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'stdout_logfile=/var/log/php-fpm.log' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'stderr_logfile=/var/log/php-fpm.error.log' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo '' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo '[program:lighttpd]' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'command=/usr/sbin/lighttpd -D -f /etc/lighttpd/lighttpd.conf' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'user=root' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'stdout_logfile=/var/log/lighttpd/access.log' >> /etc/supervisor/conf.d/nfsuserver.conf && \
    echo 'stderr_logfile=/var/log/lighttpd/error.log' >> /etc/supervisor/conf.d/nfsuserver.conf

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
RUN echo '#!/bin/sh' > /usr/local/bin/docker-entrypoint.sh && \
    echo 'set -e' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Ensure correct permissions' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'chown -R nfsu:nfsu /data /var/www/html' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'chown -R lighttpd:lighttpd /var/log/lighttpd /var/lib/lighttpd /run/lighttpd /var/cache/lighttpd' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'chown -R nfsu:nfsu /run/php' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Create required directories if they do not exist' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'mkdir -p /var/log/supervisor /var/log/nfsu' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '' >> /usr/local/bin/docker-entrypoint.sh && \
    echo '# Start supervisor' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'exec /usr/bin/supervisord -c /etc/supervisor/conf.d/nfsuserver.conf' >> /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Run with supervisor managing both services
CMD ["/usr/local/bin/docker-entrypoint.sh"]
