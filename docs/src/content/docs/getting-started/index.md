---
title: Getting Started with NANO
description: Learn how to install and start using NANO JavaScript runtime
sidebar:
  order: 1
---

NANO is a JavaScript runtime designed for serverless workloads. It combines the power of V8 with efficient multi-app hosting in a single process.

## What You'll Learn

This section guides you through:

1. **[Installation](/getting-started/install/)** - Building NANO from source
2. **[Your First App](/getting-started/first-app/)** - Creating and running a simple application

## Why NANO?

### Ultra-Dense Hosting

One NANO process can host dozens of isolated JavaScript applications, replacing entire container fleets. Each app runs in its own V8 isolate with strict CPU and memory limits.

### Familiar API Surface

NANO implements the Cloudflare Workers API, making your code portable across platforms:

```javascript
export default {
    async fetch(request) {
        return Response.json({ message: "Hello!" });
    }
};
```

### Production Features

- **Virtual host routing** - Multiple apps on a single port
- **Hot reload** - Update apps without restart
- **Built-in metrics** - Prometheus-compatible endpoints
- **Resource limits** - Per-app CPU and memory controls
- **Async runtime** - Full Promise and timer support

## Prerequisites

Before you begin, ensure you have:

- **Zig 0.15.x** - NANO is built with Zig
- **macOS, Linux, or Windows with WSL** - Supported platforms
- **Git** - For cloning the repository
- **Basic JavaScript knowledge** - Familiarity with async/await

## Next Steps

Ready to get started? Head to the [Installation Guide](/getting-started/install/) to build NANO from source.

Already installed? Jump to [Your First App](/getting-started/first-app/) to deploy your first application.
