---
title: CLI Options
description: Command-line interface reference for NANO
sidebar:
  order: 4
---

NANO provides a command-line interface for running apps, managing configuration, and interactive development.

## Commands

### `nano serve`

Start the HTTP server with one or more applications.

**Syntax:**

```bash
nano serve [options]
```

**Options:**

| Option | Alias | Type | Description |
|--------|-------|------|-------------|
| `--port <number>` | `-p` | number | Port to listen on (single-app mode) |
| `--app <path>` | `-a` | string | Path to app directory (single-app mode) |
| `--config <path>` | `-c` | string | Path to config.json file (multi-app mode) |
| `--help` | `-h` | - | Show help message |

#### Single-App Mode

Run one application without a config file:

```bash
nano serve --port 3000 --app ./my-app
```

**Example:**

```bash
# Start app on port 8080
nano serve -p 8080 -a ./apps/api

# Short form
nano serve -p 3000 -a ./my-app
```

**Requirements:**
- Both `--port` and `--app` must be provided
- App directory must contain `index.js`
- No virtual host routing (all requests go to the app)

#### Multi-App Mode

Run multiple applications with a config file:

```bash
nano serve --config config.json
```

**Example:**

```bash
# Use config.json in current directory
nano serve --config config.json

# Use config from different location
nano serve -c /etc/nano/production.json

# Use custom config name
nano serve -c config.production.json
```

**Features:**
- Virtual host routing (Host header based)
- Per-app resource limits
- Per-app environment variables
- Hot reload on config changes

### `nano run`

Execute a JavaScript file directly (REPL mode):

```bash
nano run <script.js>
```

**Example:**

```bash
# Run a script
nano run ./scripts/test.js

# Output goes to stdout
nano run ./scripts/report.js > output.txt
```

**Limitations:**
- No HTTP server
- No fetch handler
- Timers not fully supported in REPL mode
- Useful for testing and scripting

### `nano` (REPL)

Start an interactive JavaScript REPL:

```bash
nano
```

**Example:**

```bash
$ nano
> console.log("Hello from NANO")
Hello from NANO
> const x = 1 + 2
> x
3
> const uuid = crypto.randomUUID()
> uuid
"550e8400-e29b-41d4-a716-446655440000"
```

**Available APIs:**
- console (log, warn, error, info, debug)
- crypto (randomUUID, getRandomValues)
- TextEncoder/TextDecoder
- atob/btoa
- URL/URLSearchParams

**Limitations:**
- No fetch (no HTTP client in REPL)
- Timers not fully supported
- No Request/Response objects
- For testing only, not production use

### `nano --help`

Show help message with all commands and options:

```bash
nano --help
```

### `nano --version`

Show NANO version:

```bash
nano --version
```

## Environment Variables

NANO respects these environment variables:

### `NANO_PORT`

**Type:** number
**Default:** 3000

Default port when `--port` is not specified (single-app mode only).

```bash
export NANO_PORT=8080
nano serve --app ./my-app  # Uses port 8080
```

### `NANO_LOG_FORMAT`

**Type:** `json` | `text` | `apache`
**Default:** `json`

Log output format:

- `json` - Structured JSON logs (production)
- `text` - Human-readable plain text (development)
- `apache` - Apache common log format (compatibility)

```bash
export NANO_LOG_FORMAT=text
nano serve --config config.json
```

**Example outputs:**

**JSON format:**
```json
{"level":"info","timestamp":"2026-02-09T12:00:00Z","message":"Server started","port":3000}
```

**Text format:**
```
[INFO] 2026-02-09T12:00:00Z Server started port=3000
```

**Apache format:**
```
127.0.0.1 - - [09/Feb/2026:12:00:00 +0000] "GET /api/hello HTTP/1.1" 200 42
```

## Common Usage Patterns

### Development

Quick start for development:

```bash
# Single app, text logs
export NANO_LOG_FORMAT=text
nano serve --port 3000 --app ./my-app
```

### Production

Production server with config file:

```bash
# Multi-app, JSON logs
export NANO_LOG_FORMAT=json
nano serve --config /etc/nano/production.json
```

### Testing

Run test app on different port:

```bash
nano serve --port 3001 --app ./test/fixtures/test-app
```

### Multiple Environments

Use different config files per environment:

```bash
# Development
nano serve --config config.dev.json

# Staging
nano serve --config config.staging.json

# Production
nano serve --config config.production.json
```

## Exit Codes

NANO uses standard exit codes:

| Code | Meaning |
|------|---------|
| 0 | Success (clean shutdown) |
| 1 | General error (config error, app load failure) |
| 2 | Invalid command-line arguments |

## Signals

NANO handles these signals:

### `SIGTERM` / `SIGINT`

Graceful shutdown:

1. Stop accepting new requests
2. Wait for in-flight requests to complete
3. Close server socket
4. Exit with code 0

```bash
# Send SIGTERM
kill <nano-pid>

# Send SIGINT (Ctrl+C)
^C
```

### `SIGHUP`

Reload configuration (multi-app mode only):

```bash
# Manually trigger config reload
kill -HUP <nano-pid>
```

:::note[Auto-Reload]
Config file changes are detected automatically (2s poll, 500ms debounce). Manual SIGHUP is rarely needed.
:::

## Examples

### Complete Examples

**Start single app:**

```bash
nano serve --port 3000 --app ./apps/api
```

**Start with config:**

```bash
nano serve --config config.json
```

**Development with text logs:**

```bash
NANO_LOG_FORMAT=text nano serve -p 3000 -a ./my-app
```

**Production with custom config:**

```bash
NANO_LOG_FORMAT=json nano serve -c /etc/nano/prod.json
```

**Test script:**

```bash
nano run ./scripts/test-crypto.js
```

**Interactive REPL:**

```bash
nano
> console.log(crypto.randomUUID())
```

## Next Steps

- **[Configuration Examples](/config/examples/)** - See example config files
- **[Config Schema Reference](/config/schema/)** - Complete config documentation
- **[Getting Started](/getting-started/)** - First app tutorial
