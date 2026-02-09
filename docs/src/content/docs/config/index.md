---
title: Configuration
description: Overview of NANO's configuration system
sidebar:
  order: 1
---

NANO supports two modes of operation: single-app mode (via CLI flags) and multi-app mode (via config file). This guide covers both approaches.

## Configuration Modes

### Single-App Mode

For simple deployments, use CLI flags to run one app:

```bash
nano serve --port 3000 --app ./my-app
```

This is ideal for:
- Development and testing
- Single application deployments
- Quick prototyping

### Multi-App Mode

For production deployments hosting multiple apps, use a config file:

```bash
nano serve --config config.json
```

This enables:
- Virtual host routing (multiple apps on one port)
- Per-app resource limits
- Per-app environment variables
- Hot reload on config changes

## Config File Location

By default, NANO looks for `config.json` in the current directory. Specify a different location with `--config`:

```bash
nano serve --config /path/to/my-config.json
```

## Hot Reload

NANO watches the config file for changes and automatically reloads when modified. This enables:

- Adding new apps without restart
- Removing apps without restart
- Updating environment variables
- Changing resource limits

:::note[Debouncing]
Config changes are debounced by 500ms to prevent rapid reloads during editing. The config file is polled every 2 seconds.
:::

## Config File vs CLI Flags

| Feature | CLI Flags | Config File |
|---------|-----------|-------------|
| Single app | ✓ | ✓ |
| Multiple apps | ✗ | ✓ |
| Virtual host routing | ✗ | ✓ |
| Per-app limits | ✗ | ✓ |
| Per-app env vars | ✗ | ✓ |
| Hot reload | ✗ | ✓ |
| Global defaults | ✗ | ✓ |

## Configuration Structure

A NANO config file has three main sections:

1. **`port`** (required) - The port to listen on
2. **`apps`** (required) - Array of application configurations
3. **`defaults`** (optional) - Default values for all apps

```json
{
  "port": 3000,
  "apps": [
    {
      "name": "my-app",
      "hostname": "my-app.local",
      "path": "./apps/my-app"
    }
  ],
  "defaults": {
    "timeout_ms": 5000,
    "memory_mb": 128
  }
}
```

## Next Steps

- **[Config Schema Reference](/config/schema/)** - Complete field documentation
- **[Configuration Examples](/config/examples/)** - Real-world config files
- **[CLI Options](/config/cli-options/)** - Command-line flag reference
