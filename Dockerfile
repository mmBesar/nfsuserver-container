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

# Runtime stage - minimal Alpine image
FROM alpine:3.19

# Install only runtime dependencies
RUN apk add --no-cache \
    libstdc++ \
    libgcc

# Create non-root user for security
RUN addgroup -g 1000 nfsu && \
    adduser -D -u 1000 -G nfsu nfsu

# Copy the built binary
COPY --from=builder /build/nfsuserver/nfsuserver/nfsuserver /usr/local/bin/

# Create data directory
RUN mkdir -p /data && chown nfsu:nfsu /data

# Set working directory and switch to non-root user
WORKDIR /data
USER nfsu

# Expose all NFSU ports (Redirector, Listener, Reporter, ClientReporter)
EXPOSE 10900/tcp \
       10901/tcp \
       10980/tcp \
       10800/tcp \
       10800/udp

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD pgrep nfsuserver || exit 1

# Run the server
CMD ["/usr/local/bin/nfsuserver"]
