---
title: Graceful Shutdown
description: Understand NANO's graceful shutdown and connection draining behavior
sidebar:
  order: 6
---

This guide explains how NANO handles graceful shutdown, ensuring in-flight requests complete before the server stops.

## Overview

NANO implements graceful shutdown to prevent abrupt connection termination. When NANO receives a shutdown signal, it:

1. **Stops accepting new requests** - New connections receive 503 Service Unavailable
2. **Waits for in-flight requests** - Existing requests have up to 30 seconds to complete
3. **Shuts down after drain** - Server exits once all requests complete (or timeout expires)

This ensures zero dropped requests during deployment updates or server maintenance.

## How It Works

### Shutdown Sequence

```
1. SIGTERM/SIGINT received
   ↓
2. Server enters DRAINING state
   ↓
3. New requests return 503
   ↓
4. Wait for existing requests (max 30s)
   ↓
5. All requests complete (or timeout)
   ↓
6. Server exits
```

### Signal Handling

NANO responds to these signals:

- **SIGTERM** (15): Graceful shutdown (default from systemd, Docker, Kubernetes)
- **SIGINT** (2): Graceful shutdown (Ctrl+C in terminal)
- **SIGKILL** (9): Immediate termination (not graceful, avoid if possible)

```bash
# Graceful shutdown (recommended)
kill -SIGTERM <pid>

# Or with systemd
sudo systemctl stop nano

# Emergency kill (not graceful, loses in-flight requests)
kill -9 <pid>
```

## Connection Draining

### Drain Timeout

NANO waits **30 seconds** for in-flight requests to complete. This timeout is currently hardcoded (configurable timeout planned for v1.3).

```
Request starts at T+0
SIGTERM received at T+25 (request has 25s left)
↓
Request continues processing
↓
Request completes at T+28 (before timeout)
↓
Server exits successfully
```

If request exceeds timeout:

```
Request starts at T+0
SIGTERM received at T+20 (request has 20s left)
↓
Request still processing
↓
T+50 (30s timeout expired)
↓
Server force-exits, request is terminated
```

### 503 During Drain

Once NANO starts draining, new requests receive:

```http
HTTP/1.1 503 Service Unavailable
Content-Type: text/plain

Server is shutting down
```

This signals to load balancers (Nginx, Caddy) to remove NANO from the upstream pool.

## Per-App Draining

NANO also drains individual apps when removed from config:

```json
// config.json before
{
  "apps": [
    {"hostname": "app1.com", "path": "/opt/nano/apps/app1"},
    {"hostname": "app2.com", "path": "/opt/nano/apps/app2"}
  ]
}

// config.json after (app2 removed)
{
  "apps": [
    {"hostname": "app1.com", "path": "/opt/nano/apps/app1"}
  ]
}
```

After reloading config (via file watcher or `/admin/reload`):

1. **app2.com enters drain state** - New requests to app2.com get 503
2. **Existing app2.com requests complete** - Up to 30s timeout
3. **app2 is unloaded** - V8 isolate destroyed, memory freed
4. **app1.com continues normally** - Zero downtime

This enables **zero-downtime deployments** for individual apps.

## Deployment Strategies

### Rolling Update with systemd

For a single NANO instance behind Nginx:

```bash
# 1. Update app code
rsync -av ./my-app/ server:/opt/nano/apps/my-app/

# 2. Reload NANO (graceful)
sudo systemctl reload nano

# Or restart (graceful shutdown, then start)
sudo systemctl restart nano
```

**Timeline:**

```
T+0: systemctl restart nano issued
T+1: SIGTERM sent to NANO
T+1: NANO stops accepting new requests (503)
T+1: Nginx detects 503, stops routing to NANO
T+1-31: In-flight requests complete
T+31: NANO exits
T+32: systemd starts new NANO process
T+33: New NANO ready, Nginx routes traffic
```

Total downtime: ~2 seconds (between old NANO exit and new NANO ready).

### Zero-Downtime with Multiple Instances

Run multiple NANO instances behind Nginx load balancer:

```nginx
upstream nano {
    server 127.0.0.1:3000;
    server 127.0.0.1:3001;
    server 127.0.0.1:3002;
}
```

Rolling restart:

```bash
# Update instance 1
sudo systemctl restart nano@3000
# Wait for drain (30s)
sleep 30

# Update instance 2
sudo systemctl restart nano@3001
sleep 30

# Update instance 3
sudo systemctl restart nano@3002
```

At any time, 2 out of 3 instances are serving traffic. **Zero downtime.**

### Health Check Integration

Configure Nginx to detect NANO drain state:

```nginx
upstream nano {
    server 127.0.0.1:3000 max_fails=3 fail_timeout=10s;
    server 127.0.0.1:3001 max_fails=3 fail_timeout=10s;

    # Health check (Nginx Plus or open source module)
    check interval=3000 rise=2 fall=3 timeout=1000 type=http;
    check_http_send "GET /health HTTP/1.1\r\nHost: example.com\r\n\r\n";
    check_http_expect_alive http_2xx;
}
```

When NANO enters drain state, `/health` returns 503, and Nginx removes it from pool immediately.

## Testing Graceful Shutdown

### Manual Test

Terminal 1 - Start long request:

```bash
# Request that takes 10 seconds
curl http://127.0.0.1:3000/slow -H "Host: example.com"
```

Your app:

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());

    if (url.pathname === "/slow") {
      // Simulate slow processing
      const start = Date.now();
      while (Date.now() - start < 10000) {
        // Busy wait
      }
      return new Response("Completed after 10s");
    }

    return new Response("OK");
  }
};
```

Terminal 2 - Send SIGTERM:

```bash
# Get PID
NANO_PID=$(pgrep nano)

# Send graceful shutdown after 2s
sleep 2 && kill -SIGTERM $NANO_PID
```

**Expected behavior:**
- Slow request completes successfully after 10s
- NANO waits for request, then exits
- Total shutdown time: ~10s

### Automated Test

```bash
#!/bin/bash
# test-graceful-shutdown.sh

# Start NANO in background
./zig-out/bin/nano serve --config test-config.json &
NANO_PID=$!

# Wait for startup
sleep 2

# Start 5 long requests in background
for i in {1..5}; do
    curl -s http://127.0.0.1:3000/slow -H "Host: example.com" > /tmp/response$i.txt &
done

# Wait 1s, then send SIGTERM
sleep 1
echo "Sending SIGTERM to PID $NANO_PID"
kill -SIGTERM $NANO_PID

# Wait for all requests to complete
wait

# Check all requests succeeded
for i in {1..5}; do
    if grep -q "Completed" /tmp/response$i.txt; then
        echo "Request $i: SUCCESS"
    else
        echo "Request $i: FAILED"
    fi
done

# Cleanup
rm /tmp/response*.txt
```

Run test:

```bash
chmod +x test-graceful-shutdown.sh
./test-graceful-shutdown.sh
```

Expected output:

```
Sending SIGTERM to PID 12345
Request 1: SUCCESS
Request 2: SUCCESS
Request 3: SUCCESS
Request 4: SUCCESS
Request 5: SUCCESS
```

## Drain Timeout Configuration (Future)

In v1.2, drain timeout is hardcoded to 30 seconds. Planned for v1.3:

```json
{
  "port": 3000,
  "drain_timeout_ms": 60000,
  "apps": [...]
}
```

Current workaround - increase systemd stop timeout:

```ini
[Service]
# Give NANO 60s to drain before force-kill
TimeoutStopSec=60
```

## Best Practices

### 1. Always Use Graceful Signals

```bash
# ✅ Good - graceful shutdown
sudo systemctl stop nano
kill -SIGTERM $PID

# ❌ Bad - abrupt termination
kill -9 $PID
sudo systemctl kill -s SIGKILL nano
```

### 2. Set Appropriate Timeouts

Ensure all timeouts align:

```
NANO app timeout:        5s (in config)
NANO request timeout:   30s (in config)
NANO drain timeout:     30s (hardcoded)
systemd stop timeout:   60s (in service file)
Nginx proxy timeout:    60s (in nginx.conf)
```

**Rule**: Each layer should have timeout ≥ previous layer + buffer.

### 3. Monitor Drain Duration

Add logging to track how long drains actually take:

```bash
# View drain logs
sudo journalctl -u nano | grep -i drain

# Example output:
# [INFO] Received SIGTERM, entering drain state
# [INFO] Waiting for 3 in-flight requests
# [INFO] All requests completed, shutting down
# [INFO] Drain took 8.3 seconds
```

### 4. Test Before Production

Always test graceful shutdown with realistic load before deploying:

```bash
# Load test during shutdown
ab -n 1000 -c 50 http://example.com/ &
sleep 5
sudo systemctl restart nano
wait

# Check for failed requests
# Should be 0 or minimal (only new requests during drain)
```

### 5. Plan for Drain Failures

If requests exceed 30s timeout:

- **Increase timeout** (via systemd `TimeoutStopSec`)
- **Reduce request duration** (optimize slow endpoints)
- **Use async processing** (return 202, process in background)

## Troubleshooting

### Requests Still Dropped on Restart

**Cause**: Reverse proxy not detecting drain state fast enough.

**Fix**: Add health check endpoint that returns 503 during drain:

```javascript
// In your app
let draining = false;

// NANO sets this somehow (future feature)
addEventListener('drain', () => { draining = true; });

export default {
  async fetch(request) {
    const url = new URL(request.url());

    if (url.pathname === "/health") {
      if (draining) {
        return new Response("Draining", { status: 503 });
      }
      return new Response("OK", { status: 200 });
    }

    // ... rest of app
  }
};
```

### Drain Takes Full 30s Every Time

**Cause**: Long-running requests or event loop not yielding.

**Fix**: Ensure requests complete in < 30s:

```javascript
// Use timeouts for external calls
export default {
  async fetch(request) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);

    try {
      const response = await fetch("https://api.example.com", {
        signal: controller.signal
      });
      return response;
    } finally {
      clearTimeout(timeout);
    }
  }
};
```

### systemd Force-Kills Before Drain Completes

**Cause**: `TimeoutStopSec` is < 30s.

**Fix**: Increase systemd stop timeout:

```bash
sudo systemctl edit nano
```

Add:

```ini
[Service]
TimeoutStopSec=60
```

Reload:

```bash
sudo systemctl daemon-reload
sudo systemctl restart nano
```

## Example Production Workflow

Complete zero-downtime deployment:

```bash
#!/bin/bash
# deploy.sh - Zero-downtime deployment script

set -e

echo "Step 1: Copy new app code"
rsync -av --delete ./dist/ /opt/nano/apps/my-app/

echo "Step 2: Trigger graceful reload"
sudo systemctl reload nano

echo "Step 3: Wait for drain (30s + buffer)"
sleep 35

echo "Step 4: Verify new version"
curl -f http://127.0.0.1:3000/version -H "Host: example.com"

echo "Deployment complete!"
```

With multiple instances:

```bash
#!/bin/bash
# rolling-deploy.sh

INSTANCES=(3000 3001 3002)

for PORT in "${INSTANCES[@]}"; do
    echo "Updating instance on port $PORT"

    # Update code
    rsync -av --delete ./dist/ /opt/nano/apps/my-app/

    # Restart instance
    sudo systemctl restart nano@$PORT

    # Wait for drain
    sleep 35

    # Verify
    curl -f http://127.0.0.1:$PORT/health -H "Host: example.com"

    echo "Instance $PORT updated successfully"
done

echo "Rolling deployment complete!"
```

## Next Steps

- [systemd Service](/deployment/systemd) - Configure process management
- [Nginx Setup](/deployment/nginx) - Add load balancer
- [Self-Hosted Deployment](/deployment/self-hosted) - Complete setup guide

## Related Resources

- [Linux Signal Handling](https://man7.org/linux/man-pages/man7/signal.7.html)
- [systemd Service Management](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [Zero Downtime Deployments](https://www.nginx.com/blog/nginx-plus-r8-released/)
