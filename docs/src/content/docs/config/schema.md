---
title: Config Schema Reference
description: Complete reference for all config.json fields
sidebar:
  order: 2
---

This page documents every field available in NANO's `config.json` format.

## Top-Level Fields

### `port` (required)

**Type:** `number`
**Default:** None (required)

The port NANO will listen on for HTTP requests.

```json title="config.json"
{
  "port": 3000
}
```

All apps in the config share this port. Virtual host routing uses the `Host` header to route requests to the correct app.

### `apps` (required)

**Type:** `array` of app objects
**Default:** None (required)

Array of application configurations. Each app runs in its own V8 isolate with separate resources.

```json title="config.json"
{
  "apps": [
    {
      "name": "app-one",
      "hostname": "app-one.local",
      "path": "./apps/app-one"
    }
  ]
}
```

See [App Object Fields](#app-object-fields) for complete app configuration options.

### `defaults` (optional)

**Type:** `object`
**Default:** `{ "timeout_ms": 5000, "memory_mb": 128 }`

Default values applied to all apps unless overridden per-app.

```json title="config.json"
{
  "defaults": {
    "timeout_ms": 10000,
    "memory_mb": 256
  }
}
```

Available fields:
- `timeout_ms` - Default watchdog timeout
- `memory_mb` - Default memory limit

## App Object Fields

Each object in the `apps` array can have the following fields:

### `name` (required)

**Type:** `string`
**Default:** None (required)

Unique identifier for the app. Used in logs and metrics.

```json
{
  "name": "api-gateway"
}
```

:::note[Hostname Default]
If `hostname` is not specified, it defaults to the value of `name`.
:::

### `hostname` (required or defaults to `name`)

**Type:** `string`
**Default:** Same as `name` if not specified

The `Host` header value used for routing requests to this app.

```json
{
  "name": "api",
  "hostname": "api.example.com"
}
```

**Routing behavior:**
- Requests with `Host: api.example.com` → routed to this app
- Host header matching is **case-insensitive**
- Host header matching requires **exact match** (including port if present)

:::caution[Port in Host Header]
When testing locally, be careful with port numbers in the Host header:
- `Host: localhost:3000` will NOT match `hostname: "localhost"`
- `Host: localhost` WILL match `hostname: "localhost"`

For reliable testing, use: `curl -H "Host: localhost" http://127.0.0.1:3000/`
:::

### `path` (required)

**Type:** `string`
**Default:** None (required)

Filesystem path to the app directory. Must contain an `index.js` file with the fetch handler.

```json
{
  "path": "./apps/my-app"
}
```

**Path rules:**
- Relative paths are relative to the config file location
- Absolute paths are supported
- Directory must exist and contain `index.js`
- Path is validated on app load

### `timeout_ms` (optional)

**Type:** `number` (milliseconds)
**Default:** From `defaults.timeout_ms` or `5000`

CPU watchdog timeout in milliseconds. Controls how long the isolate can run before being terminated.

```json
{
  "timeout_ms": 3000
}
```

**Timeout behavior:**
- Applied per request handler execution
- Counts V8 execution iterations, not wall-clock time
- If exceeded, request is terminated with 503 error
- Prevents infinite loops and runaway code

:::caution[Not Wall-Clock Time]
The timeout is **iteration-based**, not wall-clock. Async operations (fetch, timers) don't count toward timeout while waiting. Only CPU execution time counts.

This means a handler can take longer than `timeout_ms` if it's mostly waiting on I/O.
:::

**Recommended values:**
- Development: 5000-10000ms (5-10 seconds)
- Production APIs: 3000-5000ms (3-5 seconds)
- Background jobs: 30000ms+ (30+ seconds)

### `memory_mb` (optional)

**Type:** `number` (megabytes)
**Default:** From `defaults.memory_mb` or `128`

Maximum memory the isolate can use, in megabytes.

```json
{
  "memory_mb": 256
}
```

**Memory behavior:**
- Enforced by V8 isolate limits
- Includes all JavaScript objects and buffers
- If exceeded, isolate throws out-of-memory error
- Arena allocator ensures cleanup between requests

**Recommended values:**
- Lightweight APIs: 64-128 MB
- Standard apps: 128-256 MB
- Data processing: 256-512 MB

### `env` (optional)

**Type:** `object` (key-value pairs)
**Default:** `null` (no environment variables)

Environment variables available to the app via `process.env` (if implemented) or passed to the handler context.

```json
{
  "env": {
    "DATABASE_URL": "postgresql://localhost/mydb",
    "API_KEY": "secret-key-here",
    "LOG_LEVEL": "debug"
  }
}
```

**Environment behavior:**
- Variables are isolated per-app
- Not shared between apps
- Available during handler execution
- Useful for configuration without code changes

:::tip[Secrets Management]
For production, consider using a secrets manager (AWS Secrets Manager, HashiCorp Vault) and loading secrets at startup rather than storing them in config files.
:::

### `max_buffer_size_mb` (optional)

**Type:** `number` (megabytes)
**Default:** `64`

Maximum buffer size for streaming responses, in megabytes.

```json
{
  "max_buffer_size_mb": 128
}
```

**Buffer behavior:**
- Controls ReadableStream internal buffer size
- Prevents unbounded memory growth from streams
- If exceeded, stream operations may fail
- Separate from `memory_mb` limit

**Recommended values:**
- Standard APIs: 64 MB (default)
- File uploads: 128-256 MB
- Large data processing: 512+ MB

## Complete Example

Here's a complete config showing all available fields:

```json title="config.json"
{
  "port": 3000,
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
      "max_buffer_size_mb": 128,
      "env": {
        "DATABASE_URL": "postgresql://localhost/mydb",
        "REDIS_URL": "redis://localhost:6379",
        "LOG_LEVEL": "info"
      }
    },
    {
      "name": "admin-panel",
      "hostname": "admin.example.com",
      "path": "./apps/admin",
      "timeout_ms": 10000,
      "memory_mb": 512,
      "env": {
        "ADMIN_SECRET": "secret-key",
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
        "WEBHOOK_SECRET": "webhook-signing-key"
      }
    }
  ]
}
```

## Field Summary Table

| Field | Required | Type | Default | Description |
|-------|----------|------|---------|-------------|
| `port` | ✓ | number | - | Server port |
| `apps` | ✓ | array | - | App configurations |
| `defaults.timeout_ms` | ✗ | number | 5000 | Default CPU timeout |
| `defaults.memory_mb` | ✗ | number | 128 | Default memory limit |
| `app.name` | ✓ | string | - | App identifier |
| `app.hostname` | ✗ | string | `name` | Host header for routing |
| `app.path` | ✓ | string | - | App directory path |
| `app.timeout_ms` | ✗ | number | from defaults | CPU watchdog timeout |
| `app.memory_mb` | ✗ | number | from defaults | Memory limit |
| `app.env` | ✗ | object | `null` | Environment variables |
| `app.max_buffer_size_mb` | ✗ | number | 64 | Stream buffer size |

## Next Steps

- **[Configuration Examples](/config/examples/)** - See real-world configs
- **[CLI Options](/config/cli-options/)** - Command-line alternatives
