# Phase 3 Research: Multi-App Hosting

## Goal
Multiple apps run on the same NANO process, routed by port.

## Requirements Analysis

### HOST-01: Apps deploy by pointing NANO at a folder path
- Command: `nano serve ./my-app --port 8080`
- App folder contains `index.js` or `worker.js`
- JavaScript exports a fetch handler

### HOST-02: App registry tracks app names and configurations
- Track which apps are loaded
- Store port mappings
- Support multiple apps simultaneously

### HOST-03: HTTP server routes requests to apps by port
- Each app listens on its own port
- HTTP requests invoke the app's fetch handler
- Support GET, POST, PUT, DELETE, etc.

### OBSV-02: HTTP errors return proper status codes
- JavaScript errors → 500 Internal Server Error
- Missing routes → 404 Not Found
- Parse errors → 400 Bad Request

## Architecture Design

### Workers Fetch Handler Pattern

Standard Cloudflare Workers pattern:
```javascript
// Modern export syntax
export default {
  async fetch(request, env, ctx) {
    return new Response("Hello from NANO!");
  }
}

// Or legacy addEventListener (defer to later)
addEventListener('fetch', event => {
  event.respondWith(new Response("Hello"));
});
```

### Request/Response Classes

Need proper Web API compatible classes:

**Request** (incoming from HTTP server):
- url: string
- method: string
- headers: Headers
- body: ReadableStream (or null)

**Response** (returned from handler):
- status: number
- headers: Headers
- body: string | ArrayBuffer | ReadableStream

### Component Architecture

```
┌─────────────────────────────────────────────────┐
│                    main.zig                      │
│         (CLI: nano serve ./app --port)          │
└─────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────┐
│                  server.zig                      │
│     (HTTP server using std.net/std.http)        │
└─────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────┐
│                   app.zig                        │
│  (App loader: reads JS, creates V8 context)     │
└─────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────┐
│               api/request.zig                    │
│               api/response.zig                   │
│         (Request/Response V8 bindings)          │
└─────────────────────────────────────────────────┘
```

## Technical Approach

### Plan 03-01: HTTP Server Foundation
- Create basic HTTP server using Zig's std.net
- Accept connections, parse HTTP requests
- Return static responses initially
- Test with curl

### Plan 03-02: Request/Response APIs
- Implement Request class for V8 (url, method, headers)
- Implement Response class for V8 (status, body, headers)
- Headers class for header manipulation
- These complete the Phase 2 HTTP-* requirements

### Plan 03-03: App Loader
- Load JavaScript from folder path
- Parse and compile the script
- Extract the default export's fetch method
- Create isolated V8 context per app

### Plan 03-04: Request Routing
- Wire HTTP request → Request object → JS fetch handler
- Convert Response object → HTTP response
- Error handling (500, 404, etc.)
- Multiple apps on different ports

## Zig 0.15.2 HTTP Server

Based on std.http.Server API:
```zig
const server = std.net.Server.init(.{
    .reuse_address = true,
});
server.listen(address);

while (true) {
    const conn = server.accept();
    // Handle connection in thread or inline
    var http_server = std.http.Server.init(conn.reader(), conn.writer());
    const request = http_server.receiveHead();
    // Process request
    http_server.respond(status, headers, body);
}
```

## Risks and Mitigations

1. **Async/Promises**: fetch handlers return Promises
   - Mitigation: For Phase 3, support sync handlers first
   - Full async support in Phase 4 with event loop

2. **Request body streaming**: Large bodies need streaming
   - Mitigation: Buffer small bodies (<1MB) initially

3. **Concurrent requests**: Thread safety
   - Mitigation: Single-threaded initially, one request at a time

## Plan Breakdown

| Plan | Focus | Output |
|------|-------|--------|
| 03-01 | HTTP Server | Basic server responding to requests |
| 03-02 | Request/Response | V8-compatible Request/Response classes |
| 03-03 | App Loader | Load JS apps from folders |
| 03-04 | Integration | Wire everything together, multiple apps |

## Success Criteria Mapping

1. "Pointing NANO at a folder starts an app serving HTTP requests"
   - Plans 03-01, 03-03, 03-04

2. "Two apps on different ports run independently"
   - Plan 03-04

3. "HTTP errors return proper status codes"
   - Plan 03-04
