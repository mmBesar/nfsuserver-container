# NFS Underground Server Container

A multi-architecture container for [nfsuserver](https://github.com/HarpyWar/nfsuserver) - a server emulator for **Need for Speed: Underground (2003)**.

> ⚠️ **Important**: This server only supports the original Need for Speed: Underground (2003), **NOT** Underground 2.

## 🏗️ Multi-Architecture Support

Pre-built images are available for:
- `linux/amd64` (x86_64)
- `linux/arm64` (ARM64/AArch64) 
- `linux/arm/v7` (ARMv7/armhf)

Perfect for Raspberry Pi, ARM-based servers, and traditional x86 systems.

## 🚀 Quick Start

### Using Docker Run

```bash
docker run -d \
  --name nfsus \
  --restart unless-stopped \
  -p 10900:10900/tcp \
  -p 10901:10901/tcp \
  -p 10980:10980/tcp \
  -p 10800:10800/udp \
  -p 10800:10800/tcp \
  -v ./nfsu-server/data:/data \
  -v ./nfsu-server/logs:/var/log/nfsu \
  ghcr.io/mmbesar/nfsuserver-container:latest
```

### Using Docker Compose

```yaml
services:
  nfsus:
    image: ghcr.io/mmbesar/nfsuserver-container:latest
    container_name: nfsus
    restart: unless-stopped
    user: "1000:1000"  # Adjust to match your host user
    ports:
      - "10900:10900/tcp"  # Redirector connections
      - "10901:10901/tcp"  # Listener connections
      - "10980:10980/tcp"  # Reporter connections
      - "10800:10800/udp"  # ClientReporter UDP
      - "10800:10800/tcp"  # ClientReporter TCP
    volumes:
      - ./config/nfsu.conf:/data/nfsu.conf:ro  # Optional: custom config
      - ./config/news.txt:/data/news.txt:ro    # Optional: custom news
      - ./data:/data                           # User data persistence
      - ./logs:/var/log/nfsu                   # Server logs
    environment:
      TZ: "Africa/Cairo"  # Set your timezone
    # Optional: Resource limits for low-power devices
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 256M
        reservations:
          cpus: '0.25'
          memory: 64M
    # Health check
    healthcheck:
      test: ["CMD", "pgrep", "nfsuserver"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

## 🌐 DNS Setup (Recommended Method)

The most reliable way to connect clients to your server is through DNS redirection. This eliminates the need for client-side applications and works seamlessly across all platforms.

### Why DNS Method?

- **Clean Setup**: No additional client software required
- **Linux-Friendly**: Avoids compatibility issues with client applications
- **Transparent**: Game connects automatically without manual server entry
- **Network-Wide**: Works for all devices on your network

### Router-Based DNS (OpenWrt Example)

Add these lines to your OpenWrt router configuration:

```bash
# Edit /etc/config/dhcp
config dnsmasq
    # ... existing config ...
    list address '/ps2nfs04.ea.com/192.168.100.100'  # Replace with your server IP
    list address '/ps2nfs04.ea.com/::1'

# Apply changes
/etc/init.d/dnsmasq restart
```

### Alternative DNS Methods

**Linux Hosts File:**
```bash
# Add to /etc/hosts
192.168.100.100 ps2nfs04.ea.com

# Flush DNS cache
sudo systemctl flush-dns  # or equivalent for your system
```

**Pi-hole:**
```bash
# Add to Pi-hole custom DNS
ps2nfs04.ea.com 192.168.100.100
```

**Local dnsmasq:**
```bash
# Add to /etc/dnsmasq.conf
address=/ps2nfs04.ea.com/192.168.100.100
```

## ⚙️ Configuration

### Server Configuration (nfsu.conf)

Create a `nfsu.conf` file to customize your server:

```ini
# NFS Underground Server Configuration
# Configuration file for Need For Speed: Underground server

# Server Basic Settings
ServerName=HS Underground Server
MaxPlayers=16
ServerPassword=

# Network Settings - IMPORTANT: Set your server's IP
ServerIP=0.0.0.0
# Set this to your Pi4's IP address that clients connect to
ServerExternalIP=192.168.100.100

RedirectorPort      = 10900
ListenerPort        = 10901
ReporterPort        = 10980

; ClientReporter uses the same port for UDP and (fallback) TCP:
ClientReporterPort  = 10800
ClientReporterPortUDP   = 10800
ClientReporterPortTCP   = 10800

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

# Car Settings
AllowTuning=1
DefaultCar=0
MaxCarLevel=5

# Room Settings
MaxRooms=10
DefaultRoomName=Race Room
PasswordProtectedRooms=1

# Anti-cheat Settings
EnableAntiCheat=1
SpeedCheckTolerance=1.2
PositionCheckTolerance=100

# Logging Settings
LogLevel=2
LogToFile=1
LogFileName=/var/log/nfsu/server.log
LogRotate=1
MaxLogSize=10485760

# Database Settings
DatabaseFile=/data/users.dat
BackupDatabase=1
BackupInterval=3600

# Message of the Day
MOTD=Welcome to the NFS Underground Server! Have fun racing!

# Admin Settings
AdminPassword=MyP@ssW0rd
AdminPort=9998
EnableRemoteAdmin=1

# Performance Settings
MaxBandwidth=1000
UpdateInterval=50
NetworkBuffer=8192

```

### News File (news.txt)

Create a `news.txt` file for server announcements:

```
===============================================
    WELCOME TO HS NFS UNDERGROUND SERVER
===============================================

📰 NEWS & ANNOUNCEMENTS:
• Server is now online and stable
• New players welcome - register your profile!
• Race when ever you feel like it

🏎️ SERVER RULES:
• No cheating, hacking, or exploiting
• Respect other players
• No offensive language or behavior
• Report issues to admin

🏁 RACING TIPS:
• Use practice mode to learn tracks
• Tune your car for better performance  
• Communication wins races!

🔧 TECHNICAL INFO:
• Server supports up to 16 players
• All original NFSU tracks available
• Custom rooms can be created
• Spectator mode enabled

📞 SUPPORT:
Contact admin if you experience:
• Connection issues
• Gameplay problems  
• Player misconduct
• Technical difficulties

===============================================
        HAVE FUN AND RACE SAFELY!
===============================================

Last updated: $(date)
Server version: 1.0.5
```

## 🎮 Game Setup & Troubleshooting

### For Game Clients

1. **Get the Game**: Download NFS Underground v1.4 (no-CD patch recommended)

2. **Server Connection** - Choose one method:

   **Method A: DNS Redirection (Recommended for Linux)**
   
   The cleanest approach is to redirect the game's DNS requests to your server. This avoids client-side tools and works seamlessly.
   
   **OpenWrt Router Configuration:**
   ```bash
   # Add to /etc/config/dhcp under config dnsmasq
   list address '/ps2nfs04.ea.com/192.168.100.100'  # Your server IP
   list address '/ps2nfs04.ea.com/::1'             # IPv6 localhost
   
   # Restart dnsmasq
   /etc/init.d/dnsmasq restart
   ```
   
   **Other Linux DNS Options:**
   ```bash
   # Add to /etc/hosts
   192.168.100.100 ps2nfs04.ea.com
   
   # Or use dnsmasq locally
   echo "address=/ps2nfs04.ea.com/192.168.100.100" >> /etc/dnsmasq.conf
   ```

   **Method B: Client Application (Windows-friendly)**
   
   Use the official nfsuclient.exe tool:
   - Download from [nfsuserver releases](https://github.com/HarpyWar/nfsuserver/releases)
   - Add your server IP manually or use public server list
   - Works well on Windows, can be problematic on Linux

3. **Join Server**: 
   - Open game → Play Online → Create Profile
   - Server should appear automatically (DNS method) or be available in your server list
   - Use your profile to connect to the server

### Starting Races - IMPORTANT! 

❗ **Common Issue**: Race challenges getting stuck

**Solution**: 
1. Join a room with other players
2. Go to the **Games page** within the room
3. **Create a game** (don't just send challenges)
4. Other players can then join the created game
5. Race will start properly

> This is the correct workflow for NFS Underground multiplayer - direct challenges often don't work properly.

### Network Requirements

- **DNS Setup** (Recommended): Redirect `ps2nfs04.ea.com` to your server IP via DNS
- **Firewall**: No special client-side firewall configuration needed
- **NAT**: Server should be accessible from clients (port forwarding if behind NAT)
- **Latency**: Keep ping under 150ms for best racing experience

## 📁 Directory Structure

```
your-server-folder/
├── docker-compose.yml
├── config/
│   ├── nfsu.conf          # Server configuration
│   └── news.txt           # Server news/announcements
├── data/
│   └── rusers.dat         # User database (auto-created)
└── logs/
    └── server.log         # Server logs
```

## 🔧 Advanced Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `TZ` | Timezone for logs | `UTC` |
| `PUID` | User ID for file permissions | `1000` |
| `PGID` | Group ID for file permissions | `1000` |

### Health Monitoring

The container includes a health check that monitors the nfsuserver process:

```bash
# Check container health
docker ps  # Look for "healthy" status

# View health check logs
docker inspect nfsus | grep -A 10 Health
```

### Logs and Debugging

```bash
# View real-time server logs
docker logs -f nfsus

# View log files
tail -f ./logs/server.log

# Enable verbose logging in nfsu.conf
Verbose=1
EnableLogFile=1
```

## 🐛 Common Issues

### Container Won't Start
- Check port conflicts: `netstat -tulpn | grep :10900`
- Verify volume permissions: `chown -R 1000:1000 ./data ./logs`
- Check Docker logs: `docker logs nfsus`

### Players Can't Connect
- **DNS Issues**: Ensure `ps2nfs04.ea.com` resolves to your server IP
  - Test: `nslookup ps2nfs04.ea.com` should return your server IP
  - For OpenWrt: Check dnsmasq configuration and restart service
  - For local hosts file: Verify entry syntax and flush DNS cache
- Verify server IP in `nfsu.conf` matches your actual IP
- Check firewall settings on host system
- Ensure ports 10800, 10900, 10901, 10980 are accessible

### Races Won't Start
- Use "Create Game" instead of sending challenges
- Ensure all players are in the same room
- Check server logs for connection errors

### Permission Issues
- Set correct user in compose file: `user: "1000:1000"`
- Fix volume permissions: `sudo chown -R 1000:1000 ./data ./logs`

## 📊 Server Management

### Backup User Database

```bash
# Backup user data
cp ./data/rusers.dat ./data/rusers.dat.backup

# Backup with timestamp
cp ./data/rusers.dat ./data/rusers.dat.$(date +%Y%m%d)
```

### Monitor Server Performance

```bash
# View resource usage
docker stats nfsus

# Check active connections
docker exec nfsus netstat -an | grep :10900
```

## 🏷️ Version Information

- **Server Version**: Based on nfsuserver v1.0.5
- **Container**: Built with Alpine Linux for minimal size
- **Supported Game**: Need for Speed: Underground (2003) v1.4 recommended

## 🙏 Credits

- **Original Server**: [HarpyWar/nfsuserver](https://github.com/HarpyWar/nfsuserver)
- **Initial Development**: 3 PriedeZ
- **Container Maintainer**: mmBesar

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/mmBesar/nfsuserver-container/issues)
- **Original Server Issues**: [nfsuserver Issues](https://github.com/HarpyWar/nfsuserver/issues)

---

🏁 **Ready to race? Start your engines and enjoy the underground racing scene!**
