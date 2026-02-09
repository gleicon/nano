---
title: Caddy Reverse Proxy
description: Configure Caddy as reverse proxy for NANO with automatic HTTPS
sidebar:
  order: 4
---

This guide covers setting up Caddy as a reverse proxy for NANO. Caddy provides automatic HTTPS with Let's Encrypt, making it simpler than Nginx for many deployments.

## Why Caddy?

Caddy offers several advantages:

- **Automatic HTTPS**: Let's Encrypt certificates obtained and renewed automatically
- **Simple configuration**: Caddyfile is much easier to read and write than Nginx config
- **Modern defaults**: HTTP/2, HTTP/3, security headers out of the box
- **Zero-config HTTPS**: Just provide domain name, Caddy handles the rest

## Prerequisites

- NANO running on `127.0.0.1:3000` (see [Self-Hosted Deployment](/deployment/self-hosted))
- Ubuntu/Debian server with root access
- Domain name pointing to your server
- Ports 80 and 443 open (for Let's Encrypt validation)

## Step 1: Install Caddy

### Ubuntu/Debian

```bash
# Add Caddy repository
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list

# Install
sudo apt update
sudo apt install caddy

# Verify installation
caddy version

# Caddy is automatically started and enabled
sudo systemctl status caddy
```

### Other Methods

```bash
# Using xcaddy (custom builds)
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
xcaddy build

# Pre-built binary
curl -O https://caddyserver.com/api/download?os=linux&arch=amd64
chmod +x caddy
sudo mv caddy /usr/local/bin/
```

## Step 2: Basic Reverse Proxy Configuration

Edit `/etc/caddy/Caddyfile`:

```caddyfile
example.com {
    reverse_proxy localhost:3000
}
```

That's it! This configuration:
- Automatically obtains SSL certificate from Let's Encrypt
- Redirects HTTP to HTTPS
- Forwards requests to NANO on port 3000
- Sets required headers automatically

Reload Caddy:

```bash
# Test configuration
sudo caddy validate --config /etc/caddy/Caddyfile

# Reload
sudo systemctl reload caddy
```

Test:

```bash
# Should work over HTTPS automatically
curl https://example.com/
```

## Step 3: Production Configuration

Full production Caddyfile with security headers and timeouts:

```caddyfile
# Global options
{
    # Email for Let's Encrypt notifications
    email admin@example.com

    # Admin API (optional, for metrics)
    admin localhost:2019
}

# Main site
example.com www.example.com {
    # Automatic HTTPS is enabled by default

    # Security headers
    header {
        # HSTS
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"

        # XSS Protection
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"

        # Referrer Policy
        Referrer-Policy "strict-origin-when-cross-origin"

        # Remove server header (security through obscurity)
        -Server
    }

    # Compression (automatic by default)
    encode gzip zstd

    # Health check endpoint (no logging)
    handle /health {
        reverse_proxy localhost:3000 {
            header_up Host {host}
        }
    }

    # Admin API (restrict access)
    handle /admin/* {
        # Allow only from localhost
        @local {
            remote_ip 127.0.0.1 ::1
        }
        handle @local {
            reverse_proxy localhost:3000 {
                header_up Host {host}
            }
        }
        handle {
            respond "Forbidden" 403
        }
    }

    # Main application
    handle {
        reverse_proxy localhost:3000 {
            # Headers
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
            header_up X-Forwarded-Host {host}

            # Timeouts (in seconds)
            transport http {
                dial_timeout 10s
                response_header_timeout 60s
                read_timeout 60s
                write_timeout 60s
            }

            # Health checks
            health_uri /health
            health_interval 10s
            health_timeout 5s
        }
    }

    # Access logging
    log {
        output file /var/log/caddy/nano_access.log {
            roll_size 100mb
            roll_keep 5
            roll_keep_for 720h
        }
        format json
    }
}
```

Reload configuration:

```bash
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

## Step 4: Multiple Apps (Virtual Hosts)

Serve multiple apps on different domains:

```caddyfile
# App 1
example.com www.example.com {
    reverse_proxy localhost:3000 {
        header_up Host {host}
    }

    log {
        output file /var/log/caddy/example_access.log
    }
}

# App 2
api.example.com {
    reverse_proxy localhost:3000 {
        header_up Host {host}
    }

    log {
        output file /var/log/caddy/api_access.log
    }
}

# App 3
staging.example.com {
    reverse_proxy localhost:3000 {
        header_up Host {host}
    }

    # Staging-specific settings
    basicauth {
        # Generate hash: caddy hash-password --plaintext 'password'
        admin $2a$14$xyz...
    }
}
```

NANO routes based on `Host` header. Each domain can point to a different app in your NANO config.

## Step 5: Load Balancing (Multiple NANO Instances)

Distribute traffic across multiple NANO instances:

```caddyfile
example.com {
    reverse_proxy localhost:3000 localhost:3001 localhost:3002 localhost:3003 {
        # Load balancing policy
        lb_policy least_conn

        # Health checks
        health_uri /health
        health_interval 10s
        health_timeout 5s

        # Retries
        lb_try_duration 10s
        lb_try_interval 500ms

        # Headers
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
    }
}
```

Each NANO instance needs its own config file with different port.

## Step 6: Rate Limiting

Protect against abuse (requires Caddy plugin):

```bash
# Build Caddy with rate limit plugin
xcaddy build --with github.com/mholt/caddy-ratelimit
```

Caddyfile with rate limiting:

```caddyfile
example.com {
    rate_limit {
        zone general {
            key {remote_host}
            events 100
            window 1m
        }

        zone api {
            key {remote_host}
            events 1000
            window 1m
        }
    }

    # Apply general limit
    handle {
        rate_limit general
        reverse_proxy localhost:3000
    }

    # Higher limit for API
    handle /api/* {
        rate_limit api
        reverse_proxy localhost:3000
    }
}
```

## Step 7: Custom SSL Certificates

Use your own certificates instead of Let's Encrypt:

```caddyfile
example.com {
    tls /path/to/cert.pem /path/to/key.pem

    reverse_proxy localhost:3000
}
```

Or use Caddy's DNS challenge for wildcard certificates:

```bash
# Build with DNS provider plugin
xcaddy build --with github.com/caddy-dns/cloudflare
```

```caddyfile
{
    email admin@example.com
}

*.example.com {
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }

    reverse_proxy localhost:3000 {
        header_up Host {host}
    }
}
```

## Caddyfile Snippets

Reuse common config blocks:

```caddyfile
# Define snippet
(nano_proxy) {
    reverse_proxy localhost:3000 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}

        transport http {
            read_timeout 60s
            write_timeout 60s
        }
    }
}

# Use snippet
example.com {
    import nano_proxy
}

api.example.com {
    import nano_proxy
}
```

## Environment Variables

Use environment variables in Caddyfile:

```caddyfile
{
    email {env.CADDY_EMAIL}
}

example.com {
    reverse_proxy localhost:{env.NANO_PORT}
}
```

Set variables:

```bash
# In /etc/systemd/system/caddy.service
[Service]
Environment="CADDY_EMAIL=admin@example.com"
Environment="NANO_PORT=3000"
```

## Logging

View Caddy logs:

```bash
# systemd logs (errors and admin)
sudo journalctl -u caddy -f

# Access logs (configured in Caddyfile)
sudo tail -f /var/log/caddy/nano_access.log

# JSON format makes parsing easy
sudo tail -f /var/log/caddy/nano_access.log | jq .
```

## Monitoring

Caddy provides built-in metrics:

```caddyfile
{
    admin localhost:2019
}

example.com {
    reverse_proxy localhost:3000
}
```

Query metrics:

```bash
# Get config
curl http://localhost:2019/config/

# Get metrics (Prometheus format)
curl http://localhost:2019/metrics
```

Integrate with Prometheus:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'caddy'
    static_configs:
      - targets: ['localhost:2019']
```

## Troubleshooting

### Certificate Errors

**Problem**: "Failed to obtain certificate"

**Fix**:
```bash
# Check domain DNS
dig example.com

# Check ports are open
sudo netstat -tlnp | grep -E '80|443'

# Check Caddy logs
sudo journalctl -u caddy -n 50

# Test ACME manually
caddy validate --config /etc/caddy/Caddyfile
```

### Can't Connect to Backend

**Problem**: "dial tcp 127.0.0.1:3000: connect: connection refused"

**Fix**:
```bash
# Check NANO is running
ps aux | grep nano

# Check NANO port
sudo netstat -tlnp | grep 3000

# Test NANO directly
curl http://127.0.0.1:3000/ -H "Host: example.com"
```

### Wrong Host Header

**Problem**: NANO returns 404 even though it's running

**Fix**: Ensure `header_up Host {host}` is set in reverse_proxy block.

Test headers reach NANO:
```javascript
// In your NANO app
export default {
  async fetch(request) {
    return Response.json({
      url: request.url(),
      headers: Object.fromEntries(request.headers().entries())
    });
  }
};
```

### Configuration Not Reloading

**Problem**: Changes to Caddyfile not taking effect

**Fix**:
```bash
# Validate syntax first
sudo caddy validate --config /etc/caddy/Caddyfile

# Reload (graceful)
sudo systemctl reload caddy

# Or restart (harder)
sudo systemctl restart caddy

# Check for errors
sudo journalctl -u caddy -n 20
```

## Performance Tuning

For high traffic:

```caddyfile
{
    # Increase buffer sizes
    max_header_size 16KB
}

example.com {
    # Enable HTTP/3 (QUIC)
    protocols h1 h2 h3

    # Tune connection settings
    reverse_proxy localhost:3000 {
        transport http {
            # Connection pooling
            max_conns_per_host 100

            # Timeouts
            dial_timeout 10s
            read_timeout 60s
            write_timeout 60s

            # Keepalive
            keepalive 90s
            keepalive_idle_conns 100
        }
    }
}
```

## Caddy vs Nginx

| Feature | Caddy | Nginx |
|---------|-------|-------|
| **Automatic HTTPS** | ✅ Built-in | ❌ Requires certbot |
| **Configuration** | Simple Caddyfile | More complex |
| **HTTP/3** | ✅ Native | Requires compilation |
| **Ecosystem** | Smaller | Larger |
| **Learning curve** | Easy | Moderate |
| **Performance** | Excellent | Excellent |

**Choose Caddy if:**
- You want automatic HTTPS without hassle
- You prefer simpler configuration
- You're building a new deployment

**Choose Nginx if:**
- Your team is already familiar with it
- You need specific Nginx modules
- You have existing Nginx infrastructure

## Next Steps

- [systemd Service](/deployment/systemd) - Auto-start NANO on boot
- [Graceful Shutdown](/deployment/graceful-shutdown) - Connection draining
- [Nginx Alternative](/deployment/nginx) - Traditional reverse proxy

## Related Resources

- [Caddy Documentation](https://caddyserver.com/docs/)
- [Caddyfile Syntax](https://caddyserver.com/docs/caddyfile)
- [Caddy Community](https://caddy.community/)
