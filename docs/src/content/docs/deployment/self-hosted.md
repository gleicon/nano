---
title: Self-Hosted Deployment
description: Deploy NANO on your own server or VPS
sidebar:
  order: 2
---

This guide covers deploying NANO on a self-hosted server or VPS (DigitalOcean, Linode, AWS EC2, etc.).

## Prerequisites

- Linux server (Ubuntu 22.04 LTS recommended)
- Root or sudo access
- Basic command-line familiarity

## Step 1: Get NANO Binary

### Option A: Build from Source

If you have Zig installed on the server:

```bash
# Clone repository
git clone https://github.com/yourusername/nano.git
cd nano

# Build release binary
zig build -Doptimize=ReleaseFast

# Binary location
ls -lh ./zig-out/bin/nano
```

### Option B: Copy Pre-Built Binary

Build on your development machine and copy to server:

```bash
# On dev machine: build
zig build -Doptimize=ReleaseFast

# Copy to server
scp ./zig-out/bin/nano user@server:/opt/nano/nano

# On server: make executable
ssh user@server 'chmod +x /opt/nano/nano'
```

### Option C: Download Release (Future)

Once releases are published, download pre-built binaries:

```bash
# Example (not yet available)
wget https://github.com/yourusername/nano/releases/download/v1.2.0/nano-linux-x64
chmod +x nano-linux-x64
sudo mv nano-linux-x64 /usr/local/bin/nano
```

## Step 2: Create Directory Structure

Organize NANO files:

```bash
# Create directories
sudo mkdir -p /opt/nano/{apps,configs}
sudo chown -R $USER:$USER /opt/nano

# Directory structure:
# /opt/nano/
#   ├── nano              (binary)
#   ├── configs/
#   │   └── config.json   (configuration)
#   └── apps/
#       ├── example-app/  (app 1)
#       │   └── index.js
#       └── api-app/      (app 2)
#           └── index.js
```

## Step 3: Create Configuration

Create `/opt/nano/configs/config.json`:

```json
{
  "port": 3000,
  "host": "127.0.0.1",
  "timeout": 30000,
  "max_memory_mb": 128,
  "apps": [
    {
      "hostname": "example.com",
      "path": "/opt/nano/apps/example-app",
      "timeout": 5000,
      "max_memory_mb": 64
    },
    {
      "hostname": "api.example.com",
      "path": "/opt/nano/apps/api-app",
      "timeout": 10000,
      "max_memory_mb": 128
    }
  ]
}
```

:::tip[Bind to Localhost]
Always use `"host": "127.0.0.1"` for production. Never use `"0.0.0.0"` — expose NANO through reverse proxy only.
:::

## Step 4: Create Example App

Create `/opt/nano/apps/example-app/index.js`:

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());

    if (url.pathname === "/") {
      return new Response("Hello from NANO!", {
        headers: { "Content-Type": "text/plain" }
      });
    }

    if (url.pathname === "/health") {
      return Response.json({
        status: "ok",
        timestamp: Date.now()
      });
    }

    return new Response("Not Found", { status: 404 });
  }
};
```

## Step 5: Test Run

Test NANO manually before setting up systemd:

```bash
cd /opt/nano
./nano serve --config configs/config.json
```

Expected output:

```
[INFO] NANO server starting
[INFO] Port: 3000
[INFO] Loaded app: example.com -> /opt/nano/apps/example-app
[INFO] Server listening on 127.0.0.1:3000
```

Test with curl:

```bash
# In another terminal
curl http://127.0.0.1:3000/ -H "Host: example.com"
# Output: Hello from NANO!

curl http://127.0.0.1:3000/health -H "Host: example.com"
# Output: {"status":"ok","timestamp":1234567890}
```

:::note[Host Header Required]
NANO uses virtual host routing. Always include `-H "Host: example.com"` in curl commands.
:::

Stop the test server with Ctrl+C.

## Step 6: Configure Firewall

Ensure only the reverse proxy port is exposed:

```bash
# Ubuntu with ufw
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 22/tcp    # SSH (if needed)
sudo ufw enable

# Block port 3000 from external access (it's on 127.0.0.1 anyway)
# No action needed - localhost binding prevents external access
```

## Step 7: Set Up systemd (Optional Now)

For process management, see [systemd Service](/deployment/systemd) guide.

For now, NANO can run manually or in a screen/tmux session.

## Step 8: Set Up Reverse Proxy

NANO is now running on `127.0.0.1:3000`. Next, configure a reverse proxy:

- [Nginx Setup](/deployment/nginx) - Recommended for most deployments
- [Caddy Setup](/deployment/caddy) - Easier setup with automatic SSL

## Step 9: Deploy Your Apps

To deploy a new app:

```bash
# 1. Copy app to server
scp -r ./my-app user@server:/opt/nano/apps/

# 2. Update config
ssh user@server
nano /opt/nano/configs/config.json

# Add new app:
# {
#   "hostname": "myapp.com",
#   "path": "/opt/nano/apps/my-app"
# }

# 3. Reload NANO (if using systemd)
sudo systemctl reload nano

# Or manually trigger reload via admin API:
curl -X POST http://127.0.0.1:3000/admin/reload -H "Host: example.com"
```

## Directory Permissions

Ensure correct ownership:

```bash
# NANO binary and config
sudo chown nano:nano /opt/nano/nano
sudo chown -R nano:nano /opt/nano/configs

# App directories
sudo chown -R nano:nano /opt/nano/apps

# Make binary executable
sudo chmod +x /opt/nano/nano

# Config files readable only by nano user
sudo chmod 600 /opt/nano/configs/*.json
```

## Environment Variables (Future)

Per-app environment variables (planned for v1.3):

```json
{
  "apps": [{
    "hostname": "example.com",
    "path": "/opt/nano/apps/example",
    "env": {
      "API_KEY": "secret-key",
      "DATABASE_URL": "postgres://..."
    }
  }]
}
```

Not yet available in v1.2.

## Monitoring

### Manual Monitoring

Check if NANO is running:

```bash
# Process check
ps aux | grep nano

# Port check
sudo netstat -tlnp | grep 3000

# Test health endpoint
curl http://127.0.0.1:3000/health -H "Host: example.com"
```

### Log Files

NANO logs to stdout. When run via systemd, logs go to journald:

```bash
# View logs (systemd)
sudo journalctl -u nano -f

# Last 100 lines
sudo journalctl -u nano -n 100
```

For manual runs, redirect stdout/stderr:

```bash
./nano serve --config config.json >> /var/log/nano.log 2>&1
```

## Troubleshooting

### Port Already in Use

```bash
# Error: Address already in use
# Check what's using port 3000
sudo lsof -i :3000

# Kill process
sudo kill -9 <PID>
```

### Permission Denied

```bash
# Error: Permission denied when binding port
# Don't use port < 1024 without capabilities or run as root (not recommended)
# Use port >= 1024 and reverse proxy
```

### App Not Loading

```bash
# Check config syntax
cat /opt/nano/configs/config.json | jq .

# Check app file exists
ls -la /opt/nano/apps/example-app/index.js

# Check NANO logs for error details
```

### Host Header Mismatch

```bash
# Error: 404 even though app exists
# Ensure Host header matches config

# In config: "hostname": "example.com"
# In request: -H "Host: example.com"  (must match exactly)
```

## Next Steps

- [Nginx Setup](/deployment/nginx) - Configure reverse proxy with SSL
- [systemd Service](/deployment/systemd) - Auto-start and process management
- [Graceful Shutdown](/deployment/graceful-shutdown) - Connection draining

## Security Best Practices

- ✅ Run NANO as non-root user (`nano` user)
- ✅ Bind to `127.0.0.1`, not `0.0.0.0`
- ✅ Use reverse proxy for SSL termination
- ✅ Set restrictive file permissions (600 for config)
- ✅ Enable firewall (ufw/iptables)
- ✅ Keep NANO binary and dependencies updated
- ✅ Use resource limits in systemd
- ✅ Rotate logs to prevent disk fill

## Related Pages

- [Configuration Schema](/config/schema) - Complete config reference
- [Nginx Reverse Proxy](/deployment/nginx) - Reverse proxy setup
- [systemd Service](/deployment/systemd) - Process management
