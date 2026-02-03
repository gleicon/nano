# Architecture Research: v1.2 Production Polish

**Project:** NANO v1.2
**Researched:** 2026-02-02
**Focus:** Integration of Streams API, Per-app Environment Variables, Graceful Shutdown

---

## Current Architecture Summary

NANO v1.1 has a well-structured architecture with clear module boundaries:

```
src/
  main.zig           - CLI entry point, command parsing
  config.zig         - JSON config parsing (AppConfig, Config structs)
  js.zig             - V8 helper utilities (CallbackContext, value creation)
  log.zig            - Structured JSON logging

  server/
    http.zig         - HttpServer struct, connection handling, admin API
    app.zig          - App struct (V8 isolate + persistent handles), request handling
    metrics.zig      - Prometheus metrics

  runtime/
    event_loop.zig   - EventLoop (xev wrapper), ConfigWatcher, TimerCallback
    timers.zig       - setTimeout/setInterval implementation
    watchdog.zig     - CPU timeout enforcement

  api/
    fetch.zig        - fetch(), Response class
    request.zig      - Request class
    headers.zig      - Headers class
    blob.zig         - Blob, File classes
    formdata.zig     - FormData class
    url.zig          - URL, URLSearchParams
    encoding.zig     - TextEncoder, TextDecoder
    crypto.zig       - crypto.subtle, randomUUID
    console.zig      - console.log/warn/error
    abort.zig        - AbortController, AbortSignal
```

### Key Architectural Patterns

1. **V8 Isolate Per App** - Each app has its own V8 isolate with persistent handles for context, exports, and fetch handler
2. **Arena Allocator Per Request** - Memory isolation, instant cleanup after request
3. **Function Pointer Callbacks** - Avoids circular imports between modules (e.g., ConfigWatcher -> HttpServer reload)
4. **libxev Event Loop** - Single-threaded async I/O via xev.Loop wrapper
5. **Poll-based Config Watching** - 2s poll interval, 500ms debounce for hot reload

---

## Streams Integration

### Current Response/fetch Flow

```
Current flow (v1.1):
1. fetch() in JS calls doFetch() in Zig
2. doFetch() uses std.http.Client to make request
3. Full response body read into []u8 buffer
4. FetchResult{status, body, headers} returned
5. createFetchResponse() builds V8 Response object with _body string

Current Response construction:
- new Response(body, options) stores body as _body string
- response.text() returns _body directly
- response.json() parses _body as JSON
- No streaming - entire body buffered in memory
```

### Streams API Integration Points

**ReadableStream integration with Response:**

```
Integration points:
1. Response._body can be either:
   - string (current, for backwards compatibility)
   - ReadableStream (new, for streaming)

2. Response.body getter:
   - Returns ReadableStream if body is streamable
   - Returns null if body was consumed

3. Response.text() / Response.json() / Response.arrayBuffer():
   - If _body is string: return directly (current behavior)
   - If _body is ReadableStream: collect chunks, return when done
```

**Streaming fetch response:**

```
New flow for streaming:
1. fetch() creates Response immediately after headers received
2. Response.body = ReadableStream wrapping the HTTP connection
3. User code can:
   - await response.text() - buffers entire body (current behavior)
   - Use response.body.getReader() - read chunks incrementally
   - Pipe to WritableStream - zero-copy forwarding
```

**Implementation approach:**

```zig
// In api/streams.zig (NEW FILE)
pub const StreamState = struct {
    reader_ptr: usize,       // Pointer to HTTP reader
    done: bool,
    cancelled: bool,
};

// ReadableStream stores StreamState in V8 internal field
// ReadableStreamDefaultReader provides read() method
// Each read() returns Promise that resolves with {value, done}
```

**V8 integration pattern:**

```
ReadableStream needs:
1. FunctionTemplate for constructor
2. ObjectTemplate with internal field for StreamState
3. Prototype methods: getReader(), cancel(), pipeTo(), pipeThrough()

ReadableStreamDefaultReader needs:
1. FunctionTemplate for construction via getReader()
2. Prototype methods: read(), cancel(), releaseLock()
3. read() returns Promise - uses existing Promise resolution pattern from fetch.zig
```

### Build Order Implication

Streams must be built BEFORE Response refactoring because:
- Response.body getter returns ReadableStream
- Response.text()/json() must handle ReadableStream input
- fetch() must create streaming Response

---

## Graceful Shutdown Integration

### Current Shutdown Flow

```
Current flow (v1.1):
1. SIGTERM/SIGINT caught by handleSignal()
2. handleSignal() calls server.stop()
3. stop() sets running=false, makes dummy connection to unblock accept()
4. run() loop exits, deferred deinit() cleans up

For app removal via config reload:
1. ConfigWatcher detects mtime change
2. reloadConfigCallback() called
3. reloadConfig() compares old vs new hostnames
4. removeApp() calls app.deinit() immediately
5. No connection draining - in-flight requests may fail
```

### Connection Draining Requirements

**Two shutdown scenarios:**

1. **Process shutdown (SIGTERM):**
   - Stop accepting new connections
   - Wait for in-flight requests to complete (with timeout)
   - Clean up all resources

2. **App removal (config change):**
   - Stop routing new requests to removed app
   - Wait for in-flight requests to that app to complete
   - Clean up only that app's resources

### Integration Points

**HttpServer changes:**

```zig
pub const HttpServer = struct {
    // Existing fields...

    // NEW: Connection tracking
    active_connections: std.AutoHashMap(u64, ConnectionState),
    connection_counter: u64,

    // NEW: Shutdown state
    shutdown_requested: bool,
    shutdown_timeout_ms: u64,  // Default 30s like Cloudflare

    // NEW: Per-app pending request count
    // (or track in App struct itself)
};

const ConnectionState = struct {
    conn_id: u64,
    app_hostname: ?[]const u8,  // Which app is handling this
    start_time: i64,
};
```

**App struct changes:**

```zig
pub const App = struct {
    // Existing fields...

    // NEW: Lifecycle state
    state: enum { active, draining, stopped },
    pending_requests: std.atomic.Value(u32),
};
```

**Shutdown sequence:**

```
Process shutdown:
1. Set shutdown_requested = true
2. Stop ConfigWatcher
3. Stop accepting new connections (close listening socket)
4. Wait for active_connections to drain (with timeout)
5. For each remaining connection after timeout: close forcibly
6. Cleanup apps in parallel (they have no pending requests)

App removal:
1. Set app.state = .draining
2. Remove from hostname routing (new requests get 404)
3. Check app.pending_requests periodically
4. When pending_requests == 0: call app.deinit()
5. If timeout exceeded: force deinit anyway
```

### Integration with ConfigWatcher

```
ConfigWatcher currently calls reloadConfigCallback immediately.
For graceful shutdown:

1. reloadConfig() identifies apps to remove
2. Instead of calling removeApp() immediately:
   - Mark app as draining
   - Start drain timer
   - removeApp() called when drain completes or times out

Need: DrainWatcher or extend ConfigWatcher to track draining apps
```

### Build Order Implication

Graceful shutdown has TWO levels:
1. **Basic** (app removal draining) - depends on connection tracking
2. **Full** (process shutdown draining) - depends on basic + signal handling changes

Suggest building in order:
1. Connection tracking infrastructure
2. App removal draining
3. Process shutdown draining

---

## Environment Variables Integration

### Current Isolate Setup Flow

```
Current flow in app.zig:
1. loadApp() creates isolate with v8.Isolate.init(&params)
2. isolate.enter()
3. Create HandleScope, Context
4. Register APIs on global object:
   - console.registerConsole()
   - encoding.registerEncodingAPIs()
   - url.registerURLAPIs()
   - crypto.registerCryptoAPIs()
   - fetch_api.registerFetchAPI()
   - headers.registerHeadersAPI()
   - request_api.registerRequestAPI()
   - timers.registerTimerAPIs()
   - abort.registerAbortAPI()
   - blob.registerBlobAPI()
   - formdata.registerFormDataAPI()
5. Compile and run user script
6. Store persistent handles
```

### Environment Variables Injection Point

**Config format extension:**

```json
{
  "apps": [
    {
      "name": "my-app",
      "path": "./apps/my-app",
      "hostname": "my-app.local",
      "env": {
        "API_KEY": "secret123",
        "DEBUG": "true",
        "DATABASE_URL": "postgres://..."
      }
    }
  ]
}
```

**Integration in AppConfig:**

```zig
// In config.zig
pub const AppConfig = struct {
    name: []const u8,
    path: []const u8,
    hostname: []const u8,
    port: u16,
    timeout_ms: u64,
    memory_mb: usize,
    // NEW
    env: ?std.StringHashMap([]const u8),
};
```

**Injection point in loadApp:**

```zig
// After registering all APIs, before compiling user script:

// Register process.env or Deno.env-style env object
if (app_config.env) |env_vars| {
    registerEnvVars(isolate, context, env_vars);
}
```

**API style options:**

1. **Cloudflare Workers style** - `env` parameter to fetch handler:
   ```javascript
   export default {
     async fetch(request, env) {
       const key = env.API_KEY;
     }
   }
   ```

2. **Deno style** - `Deno.env.get()`:
   ```javascript
   const key = Deno.env.get("API_KEY");
   ```

3. **Node.js style** - `process.env`:
   ```javascript
   const key = process.env.API_KEY;
   ```

**Recommendation: Cloudflare Workers style**

Rationale:
- Already passing Request to fetch handler
- Adding `env` as second parameter is minimal change
- Explicit about which vars are available (no global state)
- Aligns with WinterCG patterns

### Implementation Approach

```zig
// In app.zig, modify handleRequest:

// Build env object from app config
const env_obj = buildEnvObject(isolate, context, app.env_vars);

// Call fetch with two arguments: (request, env)
var fetch_args: [2]v8.Value = .{
    v8.Value{ .handle = @ptrCast(request_obj.handle) },
    v8.Value{ .handle = @ptrCast(env_obj.handle) },
};
const handler_result = fetch_fn.call(context, exports, &fetch_args);
```

### Build Order Implication

Environment variables are self-contained:
- Config parsing extension
- V8 object creation at request time
- Pass to fetch handler

No dependencies on Streams or Graceful Shutdown. Can be built in any order relative to other features.

---

## New Components Needed

| Component | File | Purpose |
|-----------|------|---------|
| ReadableStream | `src/api/streams.zig` | WinterCG ReadableStream implementation |
| WritableStream | `src/api/streams.zig` | WinterCG WritableStream implementation |
| TransformStream | `src/api/streams.zig` | Optional, for piping transforms |
| StreamState | `src/api/streams.zig` | Internal state for stream lifecycle |
| ConnectionTracker | `src/server/connections.zig` | Track active connections for draining |
| DrainManager | `src/server/drain.zig` | Coordinate graceful shutdown |

## Modified Components

| Component | File | Changes |
|-----------|------|---------|
| AppConfig | `src/config.zig` | Add `env` field for environment variables |
| Config parsing | `src/config.zig` | Parse `env` object from JSON |
| App struct | `src/server/app.zig` | Add state enum, pending_requests counter, env_vars |
| loadApp | `src/server/app.zig` | Accept env vars, store in App |
| handleRequest | `src/server/app.zig` | Build env object, pass to fetch handler |
| Response | `src/api/fetch.zig` | Add body getter returning ReadableStream |
| fetch() | `src/api/fetch.zig` | Option for streaming response |
| HttpServer | `src/server/http.zig` | Add connection tracking, shutdown state |
| removeApp | `src/server/http.zig` | Use draining instead of immediate deinit |
| stop | `src/server/http.zig` | Implement connection draining |

---

## Suggested Build Order

Based on dependencies analysis:

### Phase 1: Environment Variables (Lowest Risk, No Dependencies)

**Why first:**
- Self-contained feature
- Config parsing is well-understood pattern
- No changes to request/response flow
- Quick win, immediately useful

**Components:**
1. Extend AppConfig with `env` field
2. Parse env from config JSON
3. Store env in App struct
4. Build V8 object in handleRequest
5. Pass to fetch handler as second arg

### Phase 2: Streams API Foundation

**Why second:**
- Required before Response refactoring
- No dependencies on other v1.2 features
- Enables streaming patterns for future features

**Components:**
1. Create `src/api/streams.zig`
2. Implement ReadableStream class
3. Implement ReadableStreamDefaultReader
4. Add read() returning Promise

### Phase 3: Response/fetch Integration

**Why third:**
- Depends on Streams from Phase 2
- Changes existing API (Response.body)
- Requires careful backwards compatibility

**Components:**
1. Modify Response to support ReadableStream body
2. Add Response.body getter
3. Modify fetch() for streaming option
4. Update text()/json() to handle streams

### Phase 4: Connection Tracking

**Why fourth:**
- Foundation for graceful shutdown
- Low risk, additive change
- Useful for debugging/metrics even without draining

**Components:**
1. Create ConnectionState struct
2. Add tracking HashMap to HttpServer
3. Instrument handleConnection for tracking
4. Add connection count to metrics

### Phase 5: Graceful Shutdown

**Why last:**
- Depends on connection tracking
- Most complex orchestration
- Two sub-features: app removal + process shutdown

**Components:**
1. Add lifecycle state to App
2. Implement app removal draining
3. Implement process shutdown draining
4. Add shutdown timeout configuration

---

## Risk Assessment

| Feature | Risk | Mitigation |
|---------|------|------------|
| Streams API | Medium - New V8 class pattern | Follow existing fetch.zig patterns for Response class |
| Env vars | Low - Config extension | Additive, no breaking changes |
| Connection tracking | Low - Additive instrumentation | Can be added without changing request flow |
| App removal draining | Medium - Async coordination | Test with slow requests, verify no race conditions |
| Process shutdown | Medium - Signal handling timing | Test SIGTERM during active requests |

## Open Questions for Implementation

1. **Streams memory management:** How to handle backpressure? If JS reads slowly, HTTP buffer grows.
2. **Drain timeout:** What's the right default? Cloudflare uses 30s. Should it be configurable per-app?
3. **Env var inheritance:** Should apps inherit process env vars, or only explicit config vars?
4. **TransformStream:** Required for WinterCG compliance, or defer to v1.3?

---

## Sources

- [WHATWG Streams Standard](https://streams.spec.whatwg.org/)
- [Cloudflare Workers ReadableStream](https://developers.cloudflare.com/workers/runtime-apis/streams/readablestream/)
- [Cloudflare Workers WritableStream](https://developers.cloudflare.com/workers/runtime-apis/streams/writablestream/)
- [workerd Graceful Shutdown Issue #101](https://github.com/cloudflare/workerd/issues/101)
- [Cloudflare Workers Limits - Memory and Isolation](https://developers.cloudflare.com/workers/platform/limits/)
- NANO v1.1 source code analysis
