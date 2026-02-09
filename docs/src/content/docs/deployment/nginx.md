---
title: Nginx Reverse Proxy
description: Configure Nginx as reverse proxy for NANO with SSL and security headers
sidebar:
  order: 3
---

This guide covers setting up Nginx as a reverse proxy for NANO with SSL/TLS termination, security headers, and production best practices.

## Why Nginx?

Nginx is the most battle-tested reverse proxy with:

- **Mature ecosystem**: Extensive documentation and modules
- **Excellent performance**: Handles 10,000+ concurrent connections
- **Fine-grained control**: Detailed configuration options
- **Wide adoption**: Most ops teams are familiar with it

## Prerequisites

- NANO running on `127.0.0.1:3000` (see [Self-Hosted Deployment](/deployment/self-hosted))
- Ubuntu/Debian server with root access
- Domain name pointing to your server

## Step 1: Install Nginx

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install nginx

# Verify installation
nginx -v

# Start and enable Nginx
sudo systemctl start nginx
sudo systemctl enable nginx
```

## Step 2: Basic Reverse Proxy Configuration

Create `/etc/nginx/sites-available/nano`:

```nginx
upstream nano {
    server 127.0.0.1:3000;
    keepalive 32;
}

server {
    listen 80;
    server_name example.com www.example.com;

    location / {
        proxy_pass http://nano;
        proxy_http_version 1.1;

        # Required headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support (future)
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Timeouts (must be >= NANO timeout)
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

Enable the site:

```bash
# Create symlink
sudo ln -s /etc/nginx/sites-available/nano /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx
```

Test without SSL:

```bash
curl http://example.com/
```

## Step 3: Add SSL with Let's Encrypt

Install Certbot:

```bash
# Ubuntu/Debian
sudo apt install certbot python3-certbot-nginx

# Get certificate
sudo certbot --nginx -d example.com -d www.example.com

# Follow prompts - choose redirect HTTP to HTTPS
```

Certbot automatically updates your Nginx config. Verify auto-renewal:

```bash
# Test renewal
sudo certbot renew --dry-run

# Auto-renewal is configured via systemd timer
sudo systemctl status certbot.timer
```

## Step 4: Production Configuration with SSL

Full production config at `/etc/nginx/sites-available/nano`:

```nginx
# Upstream NANO servers
upstream nano {
    server 127.0.0.1:3000;
    keepalive 32;
}

# HTTP to HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name example.com www.example.com;

    # Let's Encrypt ACME challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Redirect all HTTP to HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name example.com www.example.com;

    # SSL certificate (managed by Certbot)
    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/example.com/chain.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_stapling on;
    ssl_stapling_verify on;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Compression
    gzip on;
    gzip_vary on;
    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml+rss application/rss+xml;
    gzip_min_length 1024;

    # Request buffering
    client_max_body_size 10M;
    client_body_buffer_size 128k;

    # Proxy to NANO
    location / {
        proxy_pass http://nano;
        proxy_http_version 1.1;

        # Required headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;

        # WebSocket support (for future NANO features)
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Timeouts (must be >= NANO timeout)
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # Buffering
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        proxy_busy_buffers_size 8k;

        # Error handling
        proxy_next_upstream error timeout http_502 http_503 http_504;
    }

    # Health check endpoint (bypass caching)
    location /health {
        proxy_pass http://nano;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        access_log off;
    }

    # Admin API (restrict access)
    location /admin/ {
        # Allow only from specific IPs
        allow 127.0.0.1;
        allow 10.0.0.0/8;  # Adjust to your internal network
        deny all;

        proxy_pass http://nano;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
    }
}
```

Apply configuration:

```bash
# Test
sudo nginx -t

# Reload
sudo systemctl reload nginx
```

## Step 5: Test HTTPS Setup

```bash
# Test HTTPS
curl https://example.com/

# Test HTTP redirect
curl -I http://example.com/
# Should see: HTTP/1.1 301 Moved Permanently

# Test security headers
curl -I https://example.com/ | grep -i strict
# Should see: Strict-Transport-Security: max-age=31536000

# Test SSL grade
# Visit: https://www.ssllabs.com/ssltest/analyze.html?d=example.com
```

## Multiple Apps (Virtual Hosts)

To serve multiple apps on different domains:

```nginx
upstream nano {
    server 127.0.0.1:3000;
    keepalive 32;
}

# App 1: example.com
server {
    listen 443 ssl http2;
    server_name example.com www.example.com;

    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    location / {
        proxy_pass http://nano;
        proxy_set_header Host $host;
        # ... other headers
    }
}

# App 2: api.example.com
server {
    listen 443 ssl http2;
    server_name api.example.com;

    ssl_certificate /etc/letsencrypt/live/api.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.example.com/privkey.pem;

    location / {
        proxy_pass http://nano;
        proxy_set_header Host $host;
        # ... other headers
    }
}
```

NANO will route requests based on the `Host` header.

## Load Balancing (Multiple NANO Instances)

For high traffic, run multiple NANO instances:

```nginx
upstream nano {
    least_conn;  # Load balancing method

    server 127.0.0.1:3000 max_fails=3 fail_timeout=30s;
    server 127.0.0.1:3001 max_fails=3 fail_timeout=30s;
    server 127.0.0.1:3002 max_fails=3 fail_timeout=30s;
    server 127.0.0.1:3003 max_fails=3 fail_timeout=30s;

    keepalive 64;
}

server {
    # ... rest of config
    location / {
        proxy_pass http://nano;
        # ... headers and timeouts
    }
}
```

Each NANO instance needs its own config with different port:

```bash
# /opt/nano/configs/config-3000.json (port 3000)
# /opt/nano/configs/config-3001.json (port 3001)
# ...
```

## Rate Limiting

Protect against abuse with rate limiting:

```nginx
# In http block
limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=api:10m rate=100r/s;

server {
    # ...

    # General rate limit (10 req/s per IP)
    location / {
        limit_req zone=general burst=20 nodelay;
        proxy_pass http://nano;
        # ...
    }

    # Higher limit for API endpoints
    location /api/ {
        limit_req zone=api burst=200 nodelay;
        proxy_pass http://nano;
        # ...
    }
}
```

## Logging

Configure access and error logs:

```nginx
server {
    # ...

    # Access log with detailed format
    access_log /var/log/nginx/nano_access.log combined;

    # Error log
    error_log /var/log/nginx/nano_error.log warn;

    # Disable logging for health checks
    location /health {
        access_log off;
        proxy_pass http://nano;
    }
}
```

View logs:

```bash
# Access log
sudo tail -f /var/log/nginx/nano_access.log

# Error log
sudo tail -f /var/log/nginx/nano_error.log

# Real-time monitoring
sudo tail -f /var/log/nginx/nano_access.log | grep -v /health
```

## Troubleshooting

### 502 Bad Gateway

**Cause**: Nginx can't connect to NANO.

**Fix**:
```bash
# Check NANO is running
ps aux | grep nano

# Check NANO is listening
sudo netstat -tlnp | grep 3000

# Check Nginx error log
sudo tail -f /var/log/nginx/error.log
```

### 504 Gateway Timeout

**Cause**: NANO response took longer than `proxy_read_timeout`.

**Fix**: Increase timeout in Nginx config:
```nginx
proxy_read_timeout 120s;  # Increase from 60s
```

### SSL Certificate Errors

**Cause**: Certificate expired or path incorrect.

**Fix**:
```bash
# Check certificate expiry
sudo certbot certificates

# Renew if needed
sudo certbot renew

# Verify paths in Nginx config
ls -l /etc/letsencrypt/live/example.com/
```

### Headers Not Being Set

**Cause**: `proxy_set_header` missing or incorrect.

**Fix**: Ensure all required headers are set:
```nginx
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
```

Test headers reach NANO:
```javascript
// In your NANO app
export default {
  async fetch(request) {
    const headers = {};
    request.headers().forEach((value, key) => {
      headers[key] = value;
    });
    return Response.json({ headers });
  }
};
```

## Performance Tuning

For high-traffic sites:

```nginx
# In /etc/nginx/nginx.conf (http block)
worker_processes auto;
worker_connections 4096;

# Keepalive
keepalive_timeout 65;
keepalive_requests 1000;

# Buffers
client_body_buffer_size 128k;
client_max_body_size 10M;
client_header_buffer_size 1k;
large_client_header_buffers 4 8k;

# Caching (if serving static assets through NANO)
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=nano_cache:10m max_size=1g inactive=60m;

server {
    # Enable caching for specific paths
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff2)$ {
        proxy_pass http://nano;
        proxy_cache nano_cache;
        proxy_cache_valid 200 60m;
        proxy_cache_key "$scheme$request_method$host$request_uri";
        add_header X-Cache-Status $upstream_cache_status;
    }
}
```

## Next Steps

- [systemd Service](/deployment/systemd) - Auto-start NANO on boot
- [Graceful Shutdown](/deployment/graceful-shutdown) - Connection draining
- [Caddy Alternative](/deployment/caddy) - Simpler reverse proxy option

## Related Resources

- [Nginx Documentation](https://nginx.org/en/docs/)
- [Let's Encrypt](https://letsencrypt.org/)
- [SSL Labs Test](https://www.ssllabs.com/ssltest/)
