# Multi-Arch NFSUserver Docker Image

This repository provides a **multi-architecture** Docker image for [nfsuserver](https://github.com/HarpyWar/nfsuserver), a lightweight user-space NFS server.
Supported architectures: **amd64**, **arm64**, **armhf**.

---

## 📦 Features

* **Multi-Arch** builds for:

  * `linux/amd64`
  * `linux/arm64`
  * `linux/arm/v7` (armhf)
* Configurable exports via environment variables or mounted config
* Based on a minimal Alpine Linux base image

---

## 🧑‍💻 Usage

Pull and run the container with:

```bash
docker pull ghcr.io/mmbesar/nfsuserver-container:latest
```

Compose file:

```yml
services:

  nfsus:
    image: ghcr.io/mmbesar/nfsuserver-container:latest
    container_name: nfsus
    restart: unless-stopped
    # Set user to match host user (1000:1000)
    user: "1000:1000"
    # Expose port for direct UDP/TCP game traffic
    ports:
      - "10900:10900/tcp"  # Redirector connections
      - "10901:10901/tcp"  # Listener connections
      - "10980:10980/tcp"  # Reporter connections
      - "10800:10800/udp"  # ClientReporter UDP
      - "10800:10800/tcp"  # ClientReporter TCP
    # Volume mounts for configuration and data persistence
    volumes:
      - ./nfsu-server/config/nfsu.conf:/data/nfsu.conf:ro
      - ./nfsu-server/config/news.txt:/data/news.txt:ro
      - ./nfsu-server/data:/data
      - ./nfsu-server/logs:/var/log/nfsu
    # Environment variables
    environment:
      TZ: Africa/Cairo
    # Resource limits for Pi4
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 256M
        reservations:
          cpus: '0.25'
          memory: 64M
    # Logging configuration
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    # Health check
    healthcheck:
      test: ["CMD", "pgrep", "nfsuserver"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

---

## 🙏 Credits & Thanks

* **Original project**: [HarpyWar/nfsuserver](https://github.com/HarpyWar/nfsuserver)
  Thank you to **HarpyWar** for creating this simple and effective user-space NFS server!

---

## 📄 License

This repository is licensed under the **MIT License**. See [LICENSE](LICENSE) for details.
