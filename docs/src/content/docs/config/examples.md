---
title: Configuration Examples
description: Real-world NANO configuration examples
sidebar:
  order: 3
---

This page provides ready-to-use configuration examples for common deployment scenarios.

## Single-App Configuration

The simplest config for hosting one application:

```json title="config.json"
{
  "port": 3000,
  "apps": [
    {
      "name": "my-app",
      "hostname": "localhost",
      "path": "./my-app"
    }
  ]
}
```

Run with:

```bash
nano serve --config config.json
```

Access at: `http://localhost:3000/`

:::tip[CLI Alternative]
For single apps, CLI mode is simpler:
```bash
nano serve --port 3000 --app ./my-app
```
:::

## Multi-App Virtual Hosting

Host multiple apps on the same port using virtual host routing:

```json title="config.json"
{
  "port": 3000,
  "apps": [
    {
      "name": "api",
      "hostname": "api.local",
      "path": "./apps/api"
    },
    {
      "name": "admin",
      "hostname": "admin.local",
      "path": "./apps/admin"
    },
    {
      "name": "webhooks",
      "hostname": "webhooks.local",
      "path": "./apps/webhooks"
    }
  ]
}
```

Test with curl:

```bash
# Route to api app
curl -H "Host: api.local" http://127.0.0.1:3000/

# Route to admin app
curl -H "Host: admin.local" http://127.0.0.1:3000/

# Route to webhooks app
curl -H "Host: webhooks.local" http://127.0.0.1:3000/
```

For browser testing, add to `/etc/hosts`:

```
127.0.0.1 api.local admin.local webhooks.local
```

Then visit: `http://api.local:3000/`, `http://admin.local:3000/`, etc.

## Production Configuration

Production config with resource limits, defaults, and environment variables:

```json title="config.json"
{
  "port": 8080,
  "defaults": {
    "timeout_ms": 5000,
    "memory_mb": 128
  },
  "apps": [
    {
      "name": "api-gateway",
      "hostname": "api.example.com",
      "path": "./apps/api-gateway",
      "timeout_ms": 3000,
      "memory_mb": 256,
      "env": {
        "DATABASE_URL": "postgresql://db.example.com/production",
        "REDIS_URL": "redis://cache.example.com:6379",
        "LOG_LEVEL": "info",
        "ENVIRONMENT": "production"
      }
    },
    {
      "name": "admin-panel",
      "hostname": "admin.example.com",
      "path": "./apps/admin",
      "timeout_ms": 10000,
      "memory_mb": 512,
      "env": {
        "DATABASE_URL": "postgresql://db.example.com/production",
        "ADMIN_SECRET": "change-this-secret",
        "SESSION_TIMEOUT": "3600"
      }
    },
    {
      "name": "webhooks",
      "hostname": "webhooks.example.com",
      "path": "./apps/webhooks",
      "timeout_ms": 15000,
      "memory_mb": 256,
      "env": {
        "WEBHOOK_SECRET": "webhook-signing-key",
        "QUEUE_URL": "redis://queue.example.com:6379"
      }
    }
  ]
}
```

**Key features:**
- Global defaults reduce repetition
- Per-app timeouts based on workload (API: 3s, admin: 10s, webhooks: 15s)
- Per-app memory based on needs (admin needs more for UI)
- Environment variables isolated per app
- Production-ready resource limits

## Development Configuration

Config optimized for development with relaxed limits:

```json title="config-dev.json"
{
  "port": 3000,
  "defaults": {
    "timeout_ms": 30000,
    "memory_mb": 512
  },
  "apps": [
    {
      "name": "frontend",
      "hostname": "localhost",
      "path": "./apps/frontend",
      "env": {
        "API_URL": "http://localhost:3001",
        "LOG_LEVEL": "debug"
      }
    },
    {
      "name": "backend",
      "hostname": "api.localhost",
      "path": "./apps/backend",
      "env": {
        "DATABASE_URL": "postgresql://localhost/dev",
        "LOG_LEVEL": "debug",
        "ENABLE_DEBUG": "true"
      }
    }
  ]
}
```

**Development features:**
- Higher timeouts (30s) for debugging
- More memory (512 MB) to avoid limits during development
- Debug logging enabled
- Local database connections

## Microservices Configuration

Multiple specialized services with different resource profiles:

```json title="config.json"
{
  "port": 8080,
  "defaults": {
    "timeout_ms": 5000,
    "memory_mb": 128
  },
  "apps": [
    {
      "name": "auth-service",
      "hostname": "auth.services.local",
      "path": "./services/auth",
      "timeout_ms": 2000,
      "memory_mb": 128,
      "env": {
        "JWT_SECRET": "secret-key",
        "TOKEN_EXPIRY": "3600"
      }
    },
    {
      "name": "user-service",
      "hostname": "users.services.local",
      "path": "./services/users",
      "timeout_ms": 3000,
      "memory_mb": 256,
      "env": {
        "DATABASE_URL": "postgresql://localhost/users"
      }
    },
    {
      "name": "notification-service",
      "hostname": "notifications.services.local",
      "path": "./services/notifications",
      "timeout_ms": 10000,
      "memory_mb": 256,
      "env": {
        "SMTP_HOST": "smtp.example.com",
        "SMTP_PORT": "587",
        "FROM_EMAIL": "noreply@example.com"
      }
    },
    {
      "name": "analytics-service",
      "hostname": "analytics.services.local",
      "path": "./services/analytics",
      "timeout_ms": 30000,
      "memory_mb": 512,
      "max_buffer_size_mb": 256,
      "env": {
        "CLICKHOUSE_URL": "http://clickhouse:8123"
      }
    }
  ]
}
```

**Service profiles:**
- **auth-service**: Low latency (2s timeout), minimal memory (128 MB)
- **user-service**: Standard profile (3s, 256 MB)
- **notification-service**: Longer timeout (10s) for email/SMS APIs
- **analytics-service**: Heavy processing (30s, 512 MB, large buffers)

## Environment-Based Configuration

Using environment variables for different deployment environments:

```json title="config.json"
{
  "port": 3000,
  "apps": [
    {
      "name": "api",
      "hostname": "api.example.com",
      "path": "./apps/api",
      "env": {
        "NODE_ENV": "production",
        "DATABASE_URL": "${DATABASE_URL}",
        "REDIS_URL": "${REDIS_URL}",
        "API_KEY": "${API_KEY}"
      }
    }
  ]
}
```

:::note[Environment Variable Substitution]
NANO does not currently support `${VAR}` substitution in config files. Environment variables must be literal values.

For environment-specific configs, use multiple config files:
- `config.dev.json`
- `config.staging.json`
- `config.production.json`

Then run: `nano serve --config config.production.json`
:::

## Testing Configuration

Config for running integration tests:

```json title="config.test.json"
{
  "port": 3001,
  "defaults": {
    "timeout_ms": 10000,
    "memory_mb": 256
  },
  "apps": [
    {
      "name": "test-app",
      "hostname": "localhost",
      "path": "./test/fixtures/test-app",
      "env": {
        "NODE_ENV": "test",
        "DATABASE_URL": "postgresql://localhost/test",
        "LOG_LEVEL": "error"
      }
    }
  ]
}
```

**Test features:**
- Different port (3001) to avoid conflicts
- Higher limits to avoid test failures
- Test database
- Error-only logging for clean test output

## Common Patterns

### Shared Database Across Apps

```json
{
  "apps": [
    {
      "name": "api",
      "hostname": "api.local",
      "path": "./apps/api",
      "env": {
        "DATABASE_URL": "postgresql://localhost/shared"
      }
    },
    {
      "name": "admin",
      "hostname": "admin.local",
      "path": "./apps/admin",
      "env": {
        "DATABASE_URL": "postgresql://localhost/shared"
      }
    }
  ]
}
```

### Per-App Databases

```json
{
  "apps": [
    {
      "name": "api",
      "hostname": "api.local",
      "path": "./apps/api",
      "env": {
        "DATABASE_URL": "postgresql://localhost/api_db"
      }
    },
    {
      "name": "admin",
      "hostname": "admin.local",
      "path": "./apps/admin",
      "env": {
        "DATABASE_URL": "postgresql://localhost/admin_db"
      }
    }
  ]
}
```

### Health Check App

Add a dedicated health check app:

```json
{
  "apps": [
    {
      "name": "health",
      "hostname": "health.local",
      "path": "./apps/health",
      "timeout_ms": 1000,
      "memory_mb": 64
    }
  ]
}
```

## Next Steps

- **[Config Schema Reference](/config/schema/)** - Complete field documentation
- **[CLI Options](/config/cli-options/)** - Command-line alternatives
