---
title: Deployment
description: Deploy NANO to production with reverse proxy and systemd
sidebar:
  order: 1
---

NANO is designed for self-hosted deployment on Linux servers. This guide covers production deployment patterns, reverse proxy setup, and process management.

## Deployment Architecture

The recommended production architecture is:

```
Internet → Nginx/Caddy (reverse proxy) → NANO (127.0.0.1:3000)
             ↓
          - SSL termination
          - Security headers
          - Gzip compression
          - Request buffering
```

:::caution[Don't Expose NANO Directly]
**Never expose NANO directly to the internet.** Always place it behind a reverse proxy (Nginx or Caddy) for:

- **SSL/TLS termination**: NANO doesn't handle HTTPS
- **Security headers**: HSTS, CSP, X-Frame-Options
- **DDoS protection**: Rate limiting, request buffering
- **Load balancing**: Multiple NANO instances if needed
:::

## Key Concepts

### Reverse Proxy Benefits

- **SSL termination**: Let Nginx/Caddy handle HTTPS
- **Security**: Add security headers, hide internal topology
- **Performance**: Gzip compression, static file serving
- **Flexibility**: Easy to add caching, rate limiting, WAF

### Internal Binding

NANO should bind to `127.0.0.1` (localhost) to prevent external access:

```json
{
  "port": 3000,
  "host": "127.0.0.1",
  "apps": [...]
}
```

### Process Management

Use systemd to:

- **Auto-start**: NANO starts on server boot
- **Auto-restart**: Restart on crash
- **Resource limits**: CPU, memory constraints
- **Logging**: Centralized log management

## Deployment Options

### Option 1: Nginx Reverse Proxy (Recommended)

Most battle-tested option with extensive ecosystem.

**Pros:**
- Mature, well-documented
- Excellent performance
- Rich module ecosystem
- Fine-grained configuration

**Cons:**
- More complex configuration
- Manual SSL certificate renewal (with certbot)

See [Nginx Reverse Proxy](/deployment/nginx) for complete setup.

### Option 2: Caddy Reverse Proxy

Modern alternative with automatic HTTPS.

**Pros:**
- Automatic SSL (Let's Encrypt)
- Simple configuration
- Automatic certificate renewal
- Modern HTTP/2, HTTP/3 support

**Cons:**
- Smaller ecosystem than Nginx
- Less familiar to many ops teams

See [Caddy Reverse Proxy](/deployment/caddy) for complete setup.

## Deployment Steps

1. **[Self-Hosted Setup](/deployment/self-hosted)** - Build or copy NANO binary, create config
2. **[Reverse Proxy](/deployment/nginx)** - Set up Nginx or Caddy in front of NANO
3. **[systemd Service](/deployment/systemd)** - Configure NANO as system service
4. **[Graceful Shutdown](/deployment/graceful-shutdown)** - Understand connection draining

## Security Checklist

Before deploying to production:

- [ ] NANO binds to `127.0.0.1` (not `0.0.0.0`)
- [ ] Reverse proxy handles SSL/TLS
- [ ] Security headers configured (HSTS, CSP, X-Frame-Options)
- [ ] Rate limiting enabled at reverse proxy
- [ ] Firewall rules allow only reverse proxy port (80/443)
- [ ] NANO runs as non-root user
- [ ] Log rotation configured
- [ ] Resource limits set (CPU, memory)
- [ ] Graceful shutdown tested

## Performance Considerations

### Single-Threaded Limitation

NANO is single-threaded in v1.2. For high concurrency:

**Option 1: Vertical scaling** - Run multiple NANO instances on different ports:

```nginx
upstream nano {
  server 127.0.0.1:3000;
  server 127.0.0.1:3001;
  server 127.0.0.1:3002;
  server 127.0.0.1:3003;
}
```

**Option 2: Horizontal scaling** - Multiple servers behind load balancer.

### fetch() Blocking

NANO's synchronous fetch() can block the event loop. Mitigate with:

- Timeouts on all fetch() calls (AbortSignal.timeout())
- Reverse proxy request buffering
- Aggressive caching
- External async workers for slow operations

See [B-02 limitation](/api/limitations#b-02-synchronous-fetch).

## Monitoring

### Health Check Endpoint

Add a health check endpoint to your app:

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());

    if (url.pathname === "/health") {
      return Response.json({
        status: "ok",
        timestamp: Date.now()
      });
    }

    // ... rest of app
  }
};
```

Configure reverse proxy to use `/health` for upstream checks.

### Metrics to Track

- **Request rate**: Requests per second
- **Response time**: P50, P95, P99 latencies
- **Error rate**: 4xx, 5xx responses
- **Memory usage**: RSS, heap size
- **CPU usage**: System, user time

Use reverse proxy access logs or external monitoring tools.

## Example Production Setup

Complete production setup with Nginx + systemd:

1. **Server**: Ubuntu 22.04 LTS
2. **NANO**: Running on 127.0.0.1:3000
3. **Nginx**: SSL termination, security headers, gzip
4. **systemd**: Auto-start, auto-restart
5. **Let's Encrypt**: Free SSL certificates
6. **Monitoring**: Nginx access logs + external tool

Total setup time: ~30 minutes

## Quick Start

For a quick production deployment:

```bash
# 1. Copy NANO binary
scp ./zig-out/bin/nano server:/opt/nano/

# 2. Create config
ssh server 'cat > /opt/nano/config.json' << 'EOF'
{
  "port": 3000,
  "host": "127.0.0.1",
  "apps": [{
    "hostname": "example.com",
    "path": "/opt/nano/apps/example"
  }]
}
EOF

# 3. Set up systemd (see systemd guide)
# 4. Set up Nginx (see Nginx guide)
# 5. Get SSL cert and start
```

## Next Steps

- [Self-Hosted Deployment](/deployment/self-hosted) - Set up NANO binary and config
- [Nginx Setup](/deployment/nginx) - Configure reverse proxy
- [systemd Service](/deployment/systemd) - Process management
- [Graceful Shutdown](/deployment/graceful-shutdown) - Connection draining

## Related Resources

- [Configuration Schema](/config/schema) - Complete config reference
- [Known Limitations](/api/limitations) - Production gotchas
