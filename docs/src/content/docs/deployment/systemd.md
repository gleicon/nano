---
title: systemd Service
description: Configure NANO as a systemd service for auto-start and process management
sidebar:
  order: 5
---

This guide covers setting up NANO as a systemd service for automatic startup, restart on failure, and centralized log management.

## Why systemd?

systemd is the standard init system on modern Linux distributions, providing:

- **Auto-start**: NANO starts automatically on server boot
- **Auto-restart**: Restart on crash or unexpected exit
- **Resource limits**: CPU, memory, file descriptor constraints
- **Logging**: Centralized logs via journald
- **Dependency management**: Start after network is ready
- **User isolation**: Run as non-root user

## Prerequisites

- NANO binary installed (see [Self-Hosted Deployment](/deployment/self-hosted))
- Configuration file at known path
- systemd-based Linux distribution (Ubuntu 16.04+, Debian 8+, CentOS 7+, etc.)
- Root or sudo access

## Step 1: Create nano User

Run NANO as a dedicated non-root user:

```bash
# Create nano user (no login shell)
sudo useradd --system --no-create-home --shell /usr/sbin/nologin nano

# Or with home directory for logs
sudo useradd --system --home /opt/nano --shell /usr/sbin/nologin nano
```

## Step 2: Set Up Directory Permissions

Ensure NANO user can access required files:

```bash
# NANO binary
sudo chown root:root /opt/nano/nano
sudo chmod 755 /opt/nano/nano

# Config directory
sudo chown -R nano:nano /opt/nano/configs
sudo chmod 700 /opt/nano/configs
sudo chmod 600 /opt/nano/configs/*.json

# App directories
sudo chown -R nano:nano /opt/nano/apps
sudo chmod 755 /opt/nano/apps

# Log directory (if using file logging)
sudo mkdir -p /var/log/nano
sudo chown nano:nano /var/log/nano
sudo chmod 755 /var/log/nano
```

## Step 3: Create systemd Service File

Create `/etc/systemd/system/nano.service`:

```ini
[Unit]
Description=NANO JavaScript Server
Documentation=https://github.com/yourusername/nano
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=nano
Group=nano

# Working directory
WorkingDirectory=/opt/nano

# Start command
ExecStart=/opt/nano/nano serve --config /opt/nano/configs/config.json

# Reload command (graceful reload via SIGHUP)
ExecReload=/bin/kill -HUP $MAINPID

# Restart policy
Restart=always
RestartSec=10

# Timeout settings (must be > NANO timeout)
TimeoutStartSec=30
TimeoutStopSec=60

# Resource limits
LimitNOFILE=65536
LimitNPROC=512

# Memory limit (optional - adjust based on your needs)
# MemoryMax=2G
# MemoryHigh=1.5G

# CPU quota (optional - 100% = 1 core)
# CPUQuota=200%

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/nano/apps

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=nano

[Install]
WantedBy=multi-user.target
```

## Step 4: Enable and Start Service

```bash
# Reload systemd to read new service file
sudo systemctl daemon-reload

# Enable service (start on boot)
sudo systemctl enable nano

# Start service now
sudo systemctl start nano

# Check status
sudo systemctl status nano
```

Expected output:

```
● nano.service - NANO JavaScript Server
     Loaded: loaded (/etc/systemd/system/nano.service; enabled; vendor preset: enabled)
     Active: active (running) since Sat 2026-02-09 10:00:00 UTC; 5s ago
       Docs: https://github.com/yourusername/nano
   Main PID: 12345 (nano)
      Tasks: 1 (limit: 4915)
     Memory: 50.3M
        CPU: 123ms
     CGroup: /system.slice/nano.service
             └─12345 /opt/nano/nano serve --config /opt/nano/configs/config.json

Feb 09 10:00:00 server systemd[1]: Started NANO JavaScript Server.
Feb 09 10:00:00 server nano[12345]: [INFO] NANO server starting
Feb 09 10:00:00 server nano[12345]: [INFO] Port: 3000
Feb 09 10:00:00 server nano[12345]: [INFO] Loaded app: example.com
Feb 09 10:00:00 server nano[12345]: [INFO] Server listening on 127.0.0.1:3000
```

## Step 5: Verify Service is Running

```bash
# Check service status
sudo systemctl status nano

# Check if listening on port
sudo netstat -tlnp | grep 3000
# Or with ss
sudo ss -tlnp | grep 3000

# Test with curl
curl http://127.0.0.1:3000/ -H "Host: example.com"

# Check if service will start on boot
sudo systemctl is-enabled nano
# Output: enabled
```

## Managing the Service

### Start, Stop, Restart

```bash
# Start service
sudo systemctl start nano

# Stop service (graceful shutdown with 60s timeout)
sudo systemctl stop nano

# Restart service (stop then start)
sudo systemctl restart nano

# Reload configuration (graceful, no downtime)
sudo systemctl reload nano
```

### Enable/Disable Auto-Start

```bash
# Enable auto-start on boot
sudo systemctl enable nano

# Disable auto-start
sudo systemctl disable nano

# Check if enabled
sudo systemctl is-enabled nano
```

### View Status

```bash
# Detailed status
sudo systemctl status nano

# Just check if running (exit code)
sudo systemctl is-active nano

# Check if failed
sudo systemctl is-failed nano
```

## Viewing Logs

### journalctl Commands

```bash
# View all logs for NANO
sudo journalctl -u nano

# Follow logs in real-time
sudo journalctl -u nano -f

# Last 100 lines
sudo journalctl -u nano -n 100

# Logs since 1 hour ago
sudo journalctl -u nano --since "1 hour ago"

# Logs between times
sudo journalctl -u nano --since "2026-02-09 10:00" --until "2026-02-09 11:00"

# Logs with priority (errors only)
sudo journalctl -u nano -p err

# Reverse order (newest first)
sudo journalctl -u nano -r

# Export logs to file
sudo journalctl -u nano > /tmp/nano-logs.txt
```

### Log Rotation

journald automatically rotates logs. Configure limits in `/etc/systemd/journald.conf`:

```ini
[Journal]
SystemMaxUse=1G
SystemMaxFileSize=100M
MaxRetentionSec=30day
```

Apply changes:

```bash
sudo systemctl restart systemd-journald
```

## Multiple NANO Instances

Run multiple NANO instances on different ports:

### Template Service File

Create `/etc/systemd/system/nano@.service`:

```ini
[Unit]
Description=NANO JavaScript Server (instance %i)
Documentation=https://github.com/yourusername/nano
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=nano
Group=nano
WorkingDirectory=/opt/nano

# Use instance name in config path
ExecStart=/opt/nano/nano serve --config /opt/nano/configs/config-%i.json

Restart=always
RestartSec=10
TimeoutStopSec=60

LimitNOFILE=65536
NoNewPrivileges=true
PrivateTmp=true

StandardOutput=journal
StandardError=journal
SyslogIdentifier=nano-%i

[Install]
WantedBy=multi-user.target
```

### Start Multiple Instances

```bash
# Create config files
# /opt/nano/configs/config-3000.json (port 3000)
# /opt/nano/configs/config-3001.json (port 3001)
# /opt/nano/configs/config-3002.json (port 3002)

# Enable and start instances
sudo systemctl enable nano@3000
sudo systemctl enable nano@3001
sudo systemctl enable nano@3002

sudo systemctl start nano@3000
sudo systemctl start nano@3001
sudo systemctl start nano@3002

# Check status of all
sudo systemctl status 'nano@*'

# View logs for specific instance
sudo journalctl -u nano@3000 -f
```

## Environment Variables

Pass environment variables to NANO:

```ini
[Service]
Environment="NODE_ENV=production"
Environment="LOG_LEVEL=info"
EnvironmentFile=/opt/nano/configs/.env

ExecStart=/opt/nano/nano serve --config /opt/nano/configs/config.json
```

Create `/opt/nano/configs/.env`:

```bash
NODE_ENV=production
LOG_LEVEL=info
```

Secure the env file:

```bash
sudo chown nano:nano /opt/nano/configs/.env
sudo chmod 600 /opt/nano/configs/.env
```

## Resource Limits

### Memory Limits

```ini
[Service]
# Hard limit (kills process if exceeded)
MemoryMax=2G

# Soft limit (triggers pressure notifications)
MemoryHigh=1.5G

# OOM killer adjustment
OOMScoreAdjust=500
```

### CPU Limits

```ini
[Service]
# CPU quota: 100% = 1 core, 200% = 2 cores
CPUQuota=150%

# CPU weight (relative priority, 1-10000, default 100)
CPUWeight=100
```

### File Descriptor Limits

```ini
[Service]
LimitNOFILE=65536
LimitNPROC=512
```

Check current limits:

```bash
# Get PID
NANO_PID=$(systemctl show --property MainPID --value nano)

# Check limits
cat /proc/$NANO_PID/limits
```

## Security Hardening

Full security-hardened service file:

```ini
[Service]
User=nano
Group=nano

# Security
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/nano/apps
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
RestrictNamespaces=true
LockPersonality=true
RestrictRealtime=true
RestrictSUIDSGID=true
RemoveIPC=true

# System calls
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM
SystemCallArchitectures=native

# Capabilities
CapabilityBoundingSet=
AmbientCapabilities=
```

Test hardened service:

```bash
# Analyze security
sudo systemd-analyze security nano

# Score: 0.0 = perfect, 10.0 = worst
```

## Monitoring and Alerts

### Service Failure Alerts

Set up email alerts on failure (requires mail configured):

Create `/etc/systemd/system/nano-failure-notify@.service`:

```ini
[Unit]
Description=Send email on NANO failure

[Service]
Type=oneshot
ExecStart=/usr/local/bin/notify-failure.sh %i
```

Create `/usr/local/bin/notify-failure.sh`:

```bash
#!/bin/bash
SERVICE=$1
echo "Service $SERVICE failed at $(date)" | mail -s "NANO Service Failure" admin@example.com
```

Update nano.service:

```ini
[Unit]
OnFailure=nano-failure-notify@%n.service
```

### Integration with Monitoring Tools

Export metrics for Prometheus, Grafana, etc.:

```bash
# Add health check endpoint to NANO
# Monitor via systemd-exporter or node_exporter

# Example with Prometheus systemd exporter
sudo apt install prometheus-systemd-exporter
```

## Troubleshooting

### Service Won't Start

```bash
# Check detailed status
sudo systemctl status nano -l

# View logs
sudo journalctl -u nano -n 50

# Common issues:
# 1. Config file syntax error
cat /opt/nano/configs/config.json | jq .

# 2. Permission denied
ls -la /opt/nano/nano /opt/nano/configs/config.json

# 3. Port already in use
sudo netstat -tlnp | grep 3000
```

### Service Crashes Repeatedly

```bash
# Check crash logs
sudo journalctl -u nano -p err

# Check resource limits
sudo systemctl show nano | grep -i limit

# Increase restart delay
sudo systemctl edit nano
# Add:
[Service]
RestartSec=30
```

### Graceful Shutdown Not Working

```bash
# Increase stop timeout
sudo systemctl edit nano
# Add:
[Service]
TimeoutStopSec=120

# Check if NANO handles SIGTERM
# See: /deployment/graceful-shutdown
```

## Best Practices

1. **Always run as non-root user** (`User=nano`)
2. **Set resource limits** (`MemoryMax`, `CPUQuota`)
3. **Enable auto-restart** (`Restart=always`)
4. **Use security hardening** options
5. **Monitor logs** regularly (`journalctl -u nano -f`)
6. **Test reload** before using in production
7. **Document custom settings** in comments
8. **Use template services** for multiple instances

## Next Steps

- [Graceful Shutdown](/deployment/graceful-shutdown) - Understand connection draining
- [Nginx Setup](/deployment/nginx) - Add reverse proxy
- [Caddy Setup](/deployment/caddy) - Alternative reverse proxy

## Related Resources

- [systemd Service Documentation](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [systemd Resource Control](https://www.freedesktop.org/software/systemd/man/systemd.resource-control.html)
- [journalctl Manual](https://www.freedesktop.org/software/systemd/man/journalctl.html)
