# NANO

A lightweight JavaScript runtime for serverless workloads, built with Zig and V8.

NANO hosts multiple isolated JavaScript applications in a single process using V8 isolates. Think of it like a browser with tabs — each tab is an isolated app sharing one process. It runs Cloudflare Workers-compatible code with minimal overhead.

## Features

- **V8 JavaScript Engine** — Full ES2023+ support
- **Cloudflare Workers Compatible** — Run Workers code with familiar APIs
- **Multi-App Hosting** — Multiple isolated apps on a single port via virtual host routing
- **Streams API** — WinterCG-compliant ReadableStream, WritableStream, TransformStream
- **Async/Await** — Native Promise handling with libxev event loop
- **Hot Reload** — Config file watcher for zero-downtime updates
- **Graceful Shutdown** — Connection draining on SIGTERM/SIGINT
- **Production Ready** — Structured logging, metrics, per-app resource limits

## Quick Start

### Prerequisites

- Zig 0.15.x — [download](https://ziglang.org/download/)
- macOS or Linux (Windows via WSL)

### Build

```bash
git clone https://github.com/gleicon/nano.git
cd nano
zig build
```

The binary is at `zig-out/bin/nano`.

### Run

```bash
# Start REPL
./zig-out/bin/nano

# Run a single app
./zig-out/bin/nano serve --port 3000 --app ./my-app

# Run multi-app with config
./zig-out/bin/nano serve --config config.json
```

### Example App

Create `my-app/index.js`:

```javascript
export default {
  async fetch(request, env) {
    const url = new URL(request.url());

    if (url.pathname === "/api/hello") {
      return Response.json({
        message: "Hello from NANO!",
        app: env.APP_NAME
      });
    }

    return new Response("Not Found", { status: 404 });
  }
};
```

```bash
./zig-out/bin/nano serve --port 3000 --app ./my-app
curl http://localhost:3000/api/hello
```

### Multi-App Config

Create `config.json`:

```json
{
  "port": 3000,
  "apps": [
    {
      "name": "api",
      "hostname": "api.example.com",
      "path": "./apps/api",
      "env": { "DB_URL": "postgres://..." }
    },
    {
      "name": "web",
      "hostname": "www.example.com",
      "path": "./apps/web"
    }
  ]
}
```

```bash
./zig-out/bin/nano serve --config config.json
```

## API Reference

### Global APIs

| API                                | Status | Notes                            |
| ---------------------------------- | ------ | -------------------------------- |
| `console.log/warn/error/info/debug`| Full   | JSON.stringify for objects       |
| `setTimeout(fn, ms)`              | Full   | Delayed execution via event loop |
| `setInterval(fn, ms)`             | Full   | Repeating execution              |
| `clearTimeout(id)`                | Full   | Cancel timeout                   |
| `clearInterval(id)`               | Full   | Cancel interval                  |
| `fetch(url, options)`             | Full   | HTTP client, returns Promise     |

### Web APIs

| API                       | Status  | Notes                                   |
| ------------------------- | ------- | --------------------------------------- |
| `URL`                     | Full    | Parsing and manipulation                |
| `URLSearchParams`         | Full    | Query string handling                   |
| `TextEncoder`             | Full    | UTF-8 encoding                          |
| `TextDecoder`             | Full    | UTF-8 decoding, ArrayBuffer input       |
| `Headers`                 | Full    | get/set/has/delete/append/entries       |
| `Request`                 | Full    | HTTP request representation             |
| `Response`                | Full    | HTTP response with static methods       |
| `Blob`                    | Full    | Binary data (string + ArrayBuffer)      |
| `File`                    | Full    | Extends Blob with name/lastModified     |
| `AbortController`         | Full    | Request cancellation                    |
| `AbortSignal.timeout()`   | Full    | Timeout-based abort                     |
| `crypto.randomUUID()`     | Full    | UUID v4 generation                      |
| `crypto.getRandomValues()`| Full    | Cryptographic random bytes              |
| `crypto.subtle.digest()`  | Full    | SHA-256/384/512                         |
| `crypto.subtle.sign()`    | Partial | HMAC only                               |
| `atob/btoa`               | Full    | Base64 encoding/decoding                |

### Streams APIs

| API                  | Status | Notes                              |
| -------------------- | ------ | ---------------------------------- |
| `ReadableStream`     | Full   | Controller, reader, async iterator |
| `WritableStream`     | Full   | Controller, writer, backpressure   |
| `TransformStream`    | Full   | Transform with pipe operations     |
| `TextEncoderStream`  | Full   | String to UTF-8 stream             |
| `TextDecoderStream`  | Full   | UTF-8 to string stream             |
| `Response.body`      | Full   | Streaming response bodies          |

### Request Handler

```javascript
export default {
  async fetch(request, env) {
    // request.url()      — Full URL string
    // request.method()   — HTTP method
    // request.headers()  — Headers object
    // request.text()     — Body as string
    // request.json()     — Body parsed as JSON
    // env.MY_VAR         — Per-app environment variable

    return new Response("OK");
  }
};
```

## Built-in Endpoints

| Path                     | Description                        |
| ------------------------ | ---------------------------------- |
| `/health` or `/healthz`  | Returns `{"status":"ok"}`         |
| `/metrics`               | Prometheus-format metrics          |

## Admin API

| Method | Path              | Description               |
| ------ | ----------------- | ------------------------- |
| GET    | `/admin/apps`     | List loaded apps          |
| POST   | `/admin/apps`     | Add app at runtime        |
| DELETE | `/admin/apps/:id` | Remove app (with drain)   |
| POST   | `/admin/reload`   | Reload config from disk   |

## Configuration

### CLI Options

```
nano serve [options]
  --port, -p <port>      Server port (default: 3000)
  --app, -a <path>       Path to app directory (single-app)
  --config, -c <path>    Path to config.json (multi-app)
  --help, -h             Show help

nano run <script>        Run a JavaScript file
nano                     Start REPL
```

### Environment Variables

| Variable          | Default | Description              |
| ----------------- | ------- | ------------------------ |
| `NANO_PORT`       | 3000    | Server port              |
| `NANO_LOG_FORMAT` | json    | `json`, `text`, `apache` |

## Known Limitations

| ID   | Description                | Severity | Target |
| ---- | -------------------------- | -------- | ------ |
| B-01 | Stack buffer limits (64KB) | High     | v1.3   |
| B-02 | Synchronous fetch          | High     | v1.3   |
| B-03 | WritableStream sync sinks  | Medium   | v1.3   |
| B-04 | crypto.subtle HMAC only    | Medium   | v1.3   |
| B-05 | tee() data loss            | Medium   | v1.3   |
| B-06 | Missing WinterCG APIs      | Low      | v1.3   |
| B-07 | Single-threaded            | Low      | v1.4+  |
| B-08 | URL read-only properties   | Low      | v1.3   |

See [docs/src/content/docs/api/limitations.md](docs/src/content/docs/api/limitations.md) for details and workarounds.

## Project Structure

```
nano/
├── src/
│   ├── main.zig              # CLI entry point
│   ├── api/                   # JavaScript API implementations
│   │   ├── console.zig
│   │   ├── crypto.zig
│   │   ├── encoding.zig
│   │   ├── fetch.zig
│   │   ├── headers.zig
│   │   ├── readable_stream.zig
│   │   ├── writable_stream.zig
│   │   ├── transform_stream.zig
│   │   ├── request.zig
│   │   └── url.zig
│   ├── engine/                # V8 integration
│   │   ├── script.zig
│   │   └── error.zig
│   ├── runtime/               # Async runtime
│   │   ├── event_loop.zig
│   │   └── timers.zig
│   └── server/                # HTTP server
│       ├── http.zig
│       ├── app.zig
│       └── metrics.zig
├── docs/                      # Astro + Starlight documentation site
├── test/                      # Test apps and fixtures
└── build.zig                  # Build configuration
```

## Documentation

Full documentation is in `docs/`. To build and preview:

```bash
cd docs
npm install
npm run dev
```

Topics covered: getting started, configuration, API reference, WinterCG compliance, deployment guides.

## Development

```bash
# Build
zig build

# Run tests
zig build test

# Clean rebuild (if you see stale behavior)
rm -rf .zig-cache zig-out && zig build
```

### Dependencies

- [zig-v8](https://github.com/nickelca/v8-zig) — V8 bindings for Zig
- [libxev](https://github.com/mitchellh/libxev) — Cross-platform event loop

## License

MIT
