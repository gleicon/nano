# NANO

A lightweight JavaScript runtime for serverless workloads, built with Zig and V8.

NANO is designed to run Cloudflare Workers-compatible JavaScript code with minimal overhead and fast startup times.

## Features

- **V8 JavaScript Engine** - Full ES2023+ support via V8
- **Cloudflare Workers Compatible** - Run Workers code with familiar APIs
- **Async/Await Support** - Native Promise handling in request handlers
- **Event Loop** - libxev-based async runtime for timers and I/O
- **Production Ready** - Structured logging, metrics, graceful shutdown

## Quick Start

### Prerequisites

- Zig 0.15.x
- macOS, Linux, or Windows (with WSL)

### Building

```bash
# Clone the repository
git clone https://github.com/your-org/nano.git
cd nano

# Build
zig build

# The binary is at zig-out/bin/nano
```

### Running

```bash
# Start REPL
./zig-out/bin/nano

# Run a script
./zig-out/bin/nano run script.js

# Start HTTP server with an app
./zig-out/bin/nano serve --port 3000 --app ./my-app
```

### Example App

Create `my-app/index.js`:

```javascript
__setDefault({
    async fetch(request) {
        const url = new URL(request.url());

        if (url.pathname === "/api/hello") {
            return Response.json({ message: "Hello, World!" });
        }

        if (url.pathname === "/api/proxy") {
            const response = await fetch("https://api.example.com/data");
            return new Response(response.text(), {
                headers: { "Content-Type": "application/json" }
            });
        }

        return new Response("Not Found", { status: 404 });
    }
});
```

Run it:

```bash
./zig-out/bin/nano serve --port 3000 --app ./my-app
```

## API Reference

### Global APIs

| API | Status | Notes |
|-----|--------|-------|
| `console.log/warn/error/info/debug` | Full | Standard console output |
| `setTimeout(fn, ms)` | Full | One-time delayed execution |
| `setInterval(fn, ms)` | Full | Repeating execution |
| `clearTimeout(id)` | Full | Cancel timeout |
| `clearInterval(id)` | Full | Cancel interval |
| `fetch(url, options)` | Full | HTTP client, returns Promise |

### Web APIs

| API | Status | Notes |
|-----|--------|-------|
| `URL` | Full | URL parsing and manipulation |
| `URLSearchParams` | Full | Query string handling |
| `TextEncoder` | Full | UTF-8 encoding |
| `TextDecoder` | Full | UTF-8 encoding, accepts string/ArrayBuffer/TypedArray |
| `Headers` | Full | get/set/has/delete/entries/keys/values |
| `Request` | Full | HTTP request representation |
| `Response` | Full | HTTP response with static methods |
| `crypto.randomUUID()` | Full | UUID v4 generation |
| `crypto.getRandomValues()` | Full | Cryptographic random bytes |
| `atob/btoa` | Full | Base64 encoding/decoding |

### Request Handler

Handlers can be sync or async:

```javascript
// Sync handler
__setDefault({
    fetch(request) {
        return new Response("Hello!");
    }
});

// Async handler
__setDefault({
    async fetch(request) {
        const data = await fetch("https://api.example.com/data");
        return new Response(data.text());
    }
});
```

### Request Object

```javascript
request.url()      // Full URL string
request.method()   // HTTP method
request.headers()  // Headers object
request.text()     // Body as string
request.json()     // Body parsed as JSON
```

### Response Object

```javascript
// Constructor
new Response(body, { status: 200, headers: { ... } })

// Static methods
Response.json(data)           // JSON response with Content-Type
Response.redirect(url, 302)   // Redirect response

// Instance methods
response.status()      // Status code
response.ok()          // true if 200-299
response.statusText()  // Status text
response.headers()     // Response headers
response.text()        // Body as string
response.json()        // Body parsed as JSON
```

## Built-in Endpoints

| Path | Description |
|------|-------------|
| `/health` or `/healthz` | Health check, returns `{"status":"ok"}` |
| `/metrics` | Prometheus-format metrics |

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NANO_PORT` | 3000 | Server port |
| `NANO_LOG_FORMAT` | json | `json`, `text`, or `apache` |

### Command Line

```bash
nano serve [options]
  --port, -p <port>    Server port (default: 3000)
  --app, -a <path>     Path to app directory
  --help, -h           Show help

nano run <script>      Run a JavaScript file

nano                   Start REPL
```

## Known Limitations

### Not Yet Implemented

- WebSocket API
- Streams API (ReadableStream, WritableStream)
- Service Worker lifecycle events
- KV/Durable Objects (Cloudflare-specific)

### Partial Implementations

- **Headers.entries()**: Returns array, not iterator (works with for-of loops)
- **Crypto**: SHA-1/256/384/512 digests and HMAC sign/verify; no AES/ECDH

### Behavior Differences

- `request.url()` and `request.method()` are methods, not properties (Workers uses properties)
- Promise timeout is iteration-based, not time-based

## Metrics

NANO exposes Prometheus-format metrics at `/metrics`:

```
# HELP nano_requests_total Total HTTP requests
# TYPE nano_requests_total counter
nano_requests_total 1234

# HELP nano_errors_total Total error responses
# TYPE nano_errors_total counter
nano_errors_total 5

# HELP nano_latency_seconds_avg Average request latency
# TYPE nano_latency_seconds_avg gauge
nano_latency_seconds_avg 0.0123

# HELP nano_uptime_seconds Server uptime
# TYPE nano_uptime_seconds counter
nano_uptime_seconds 3600
```

## Development

### Project Structure

```
nano/
├── src/
│   ├── main.zig           # CLI entry point
│   ├── api/               # JavaScript API implementations
│   │   ├── console.zig
│   │   ├── crypto.zig
│   │   ├── encoding.zig
│   │   ├── fetch.zig
│   │   ├── headers.zig
│   │   ├── request.zig
│   │   └── url.zig
│   ├── engine/            # V8 integration
│   │   ├── script.zig
│   │   └── error.zig
│   ├── runtime/           # Async runtime
│   │   ├── event_loop.zig
│   │   └── timers.zig
│   └── server/            # HTTP server
│       ├── http.zig
│       ├── app.zig
│       └── metrics.zig
├── examples/              # Example apps
├── test/                  # Test fixtures
└── build.zig              # Build configuration
```

### Running Tests

```bash
zig build test
```

### Dependencies

- [zig-v8](https://github.com/nicetytony/zig-v8-fork) - V8 bindings for Zig
- [libxev](https://github.com/mitchellh/libxev) - Cross-platform event loop

## License

MIT
