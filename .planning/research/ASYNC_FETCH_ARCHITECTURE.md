# Async Fetch Architecture: Deep Dive

**Component:** fetch() → Promise integration with xev event loop
**Status:** Pre-implementation research
**Confidence:** HIGH

## Current State (Synchronous)

```
fetch("https://example.com")
  → doFetch(url) blocks until HTTP response received
  → Returns resolved Promise immediately
  → Script continues (promise already "resolved" synchronously)
```

**Problem:** Blocks entire request handler for network latency. Single slow external API blocks all other JS execution.

## Target State (Asynchronous)

```
fetch("https://example.com")
  → Create PromiseResolver
  → Queue FetchOperation on xev event loop
  → Return Promise immediately (unresolved)
  → Control returns to script or timers
  → xev socket I/O completes
  → Callback enters V8, creates Response, resolves Promise
  → Process microtasks before next JS execution
  → Repeat
```

**Benefit:** Network I/O hidden behind Promise; script can continue with timers, other work.

## Key Implementation Details

### 1. FetchOperation Struct

```zig
const FetchOperation = struct {
    // Promise metadata
    resolver_persistent: v8.Persistent(v8.PromiseResolver),
    isolate: v8.Isolate,
    context_persistent: v8.Persistent(v8.Context),

    // Request parameters (owned copies)
    url: []u8,
    method: []u8,
    body: []u8,
    headers: std.StringHashMap([]u8),

    // xev integration
    completion: xev.Completion,
    socket: ?std.net.Stream = null,

    // HTTP state machine
    state: enum { dns, connect, send, receive_head, receive_body } = .dns,
    buffer: []u8, // For receiving response

    // Allocator for this operation (request-scoped)
    allocator: std.mem.Allocator,

    // DNS resolution
    gpa: std.heap.GeneralPurposeAllocator(.{}) = .{},
};
```

### 2. Promise & Resolver Lifecycle

**Why Persistent handles?**
- Promise returned to JS before I/O completes
- Need to keep resolver alive while waiting for socket
- Persistent handles survive garbage collection

**Registration:**
```zig
fn fetchCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const isolate = getIsolate(...);
    const context = getCurrentContext(...);

    // Create promise + resolver
    const resolver = v8.PromiseResolver.init(context);
    const promise = resolver.getPromise();

    // Create FetchOperation
    var op = try allocator.create(FetchOperation);
    op.resolver_persistent = v8.Persistent(v8.PromiseResolver).init(isolate, resolver);
    op.isolate = isolate;
    op.context_persistent = v8.Persistent(v8.Context).init(isolate, context);

    // Queue on event loop
    event_loop.queueFetchOperation(op);

    // Return promise immediately (unresolved)
    return promise;
}
```

### 3. xev Socket Integration

libxev provides `Socket` type for non-blocking I/O:

```zig
// In FetchOperation callback registered with xev:
fn onSocketReady(
    op_ptr: ?*FetchOperation,
    loop: *xev.Loop,
    completion: *xev.Completion,
    result: xev.Socket.ReadError!usize,
) xev.CallbackAction {
    const op = op_ptr orelse return .disarm;

    // Read bytes from socket
    const bytes_read = result catch {
        rejectWithError(op, "Socket error");
        return .disarm; // Stop polling
    };

    if (bytes_read == 0) {
        // All data received, process response
        op.state = .receive_body;
        const response = parseResponse(op.buffer[0..op.bytes_received]);
        resolveWithResponse(op, response);
        return .disarm;
    }

    // More data to read; reschedule
    return .rearm;
}
```

### 4. V8 Isolate Entry/Exit Protocol

**Critical:** V8 APIs can ONLY be called from within isolate context.

```zig
fn resolveWithResponse(op: *FetchOperation, response_data: ResponseData) void {
    // ENTER isolate + context before V8 calls
    op.isolate.enter();
    const context_handle = op.context_persistent.get(op.isolate);
    context_handle.enter();
    var scope = v8.HandleScope.init(op.isolate);
    defer scope.exit();

    // NOW safe to call V8 APIs
    const resolver = op.resolver_persistent.get(op.isolate);
    const response_obj = createResponseObject(op.isolate, context_handle, response_data);
    _ = resolver.resolve(context_handle, response_obj.toValue());

    // EXIT isolate + context
    context_handle.exit();
    op.isolate.exit();

    // Cleanup
    op.resolver_persistent.deinit();
    op.context_persistent.deinit();
    op.allocator.destroy(op);
}
```

### 5. Microtask Queue Flushing

After promise is resolved, microtasks (`.then()` handlers) must run before returning to JS:

```zig
// In EventLoop.run() after each xev callback:
fn processEventLoop() void {
    while (true) {
        // Process xev I/O, timers
        const action = event_loop.run(.no_wait);

        if (action == .more_work) {
            // Drain microtask queue (promises, queueMicrotask)
            // This runs all .then() handlers registered on promises
            while (isolate.hasPendingMicrotasks()) {
                isolate.runMicrotasks();
            }
            continue;
        } else {
            break;
        }
    }
}
```

---

## Socket Connection Flow (State Machine)

```
START
  ↓
DNS Resolution (std.net.getAddressList) → FetchOperation.state = .dns
  ↓
Connect (std.net.tcpConnectToAddress) → FetchOperation.state = .connect
  ↓
Send HTTP Request (socket.writeAll) → FetchOperation.state = .send
  ↓
Receive Response Headers (socket.read until \r\n\r\n) → FetchOperation.state = .receive_head
  ↓
Receive Response Body (socket.read until Content-Length) → FetchOperation.state = .receive_body
  ↓
Parse Response → Create Response object
  ↓
V8 Enter/Exit → resolver.resolve(response_obj)
  ↓
Process Microtasks → JS .then() handlers execute
  ↓
DONE
```

**Why State Machine?**
- Each step is async (can block for I/O)
- xev callback triggered when socket ready
- Must track where we are in the flow

---

## Error Handling

```zig
// Network errors → rejected promise
fn rejectWithError(op: *FetchOperation, err_msg: []const u8) void {
    op.isolate.enter();
    defer op.isolate.exit();

    const context = op.context_persistent.get(op.isolate);
    context.enter();
    defer context.exit();

    const resolver = op.resolver_persistent.get(op.isolate);
    const err_val = v8.String.initUtf8(op.isolate, err_msg).toValue();
    _ = resolver.reject(context, err_val);
}
```

**Errors that reject promise:**
- DNS resolution failure
- Connection refused
- Socket timeout
- Invalid response
- Content-Length mismatch
- TLS verification failure

---

## Timeout Handling

```zig
const FetchOperation = struct {
    // ...
    timeout_completion: xev.Completion,
    timeout_timer: xev.Timer,
    timeout_ms: u64 = 30_000, // 30s default
};

// Register timeout alongside socket:
pub fn queueFetchOperation(loop: *xev.Loop, op: *FetchOperation) void {
    // Start socket I/O
    loop.socket_read(op, &op.completion, op.socket, &op.buffer, onSocketReady);

    // Start timeout timer
    op.timeout_timer.run(loop, &op.timeout_completion, op.timeout_ms, FetchOperation, op, onTimeout);
}

fn onTimeout(op: ?*FetchOperation, loop: *xev.Loop, completion: *xev.Completion, result: xev.Timer.RunError!void) xev.CallbackAction {
    _ = completion; _ = result;
    const fetch_op = op orelse return .disarm;

    // Close socket (unblock read)
    if (fetch_op.socket) |s| {
        s.close();
        fetch_op.socket = null;
    }

    // Reject promise
    rejectWithError(fetch_op, "fetch timeout");
    return .disarm;
}
```

---

## Concurrency: Multiple Fetches

```javascript
// Both promises returned immediately
const p1 = fetch("https://api1.example.com/data");
const p2 = fetch("https://api2.example.com/data");

// Both I/O happens in parallel on xev event loop
const [r1, r2] = await Promise.all([p1, p2]);
```

**How it works:**
1. First `fetch()` → creates FetchOperation #1, queues on xev, returns promise #1
2. Second `fetch()` → creates FetchOperation #2, queues on xev, returns promise #2
3. Event loop runs both sockets in parallel
4. Whichever completes first (socket ready) gets callback → resolves that promise
5. Both promises resolve when respective I/O completes

---

## Memory Safety

**Arena Allocator Pattern:**
```zig
// In http.zig request handler:
var arena = std.heap.ArenaAllocator.init(general_allocator);
defer arena.deinit(); // Frees ALL FetchOperations at end of request

const request_allocator = arena.allocator();

// Each FetchOperation allocated from request_allocator
var op = try request_allocator.create(FetchOperation);
op.allocator = request_allocator;

// When operation completes and promise resolves:
// - op is destroyed
// - Memory freed at end of request (not per-fetch)
```

**Why not free immediately after resolution?**
- Promise might be passed to async code (stored in global)
- Ensure operation lives for entire request lifetime
- Arena deinit handles cleanup atomically

---

## Testing Strategy

### Unit Tests
```zig
test "fetch returns promise immediately" {
    // Create mock promise resolver
    // Call fetch()
    // Verify return value is Promise (not Response)
    // Verify promise is unresolved
}

test "fetch resolves with Response on success" {
    // Mock xev socket with response data
    // Call fetch()
    // Run event loop until promise resolves
    // Verify response status/headers
}

test "fetch rejects on network error" {
    // Mock xev socket failure
    // Call fetch()
    // Run event loop
    // Verify promise rejected with error message
}

test "multiple fetches run in parallel" {
    // Queue 3 fetch operations
    // All should complete in O(max_latency), not O(sum_latency)
}
```

### Integration Tests
```javascript
// In test app:
export default {
  async fetch(request) {
    const [r1, r2] = await Promise.all([
      fetch("https://httpbin.org/delay/1"),
      fetch("https://httpbin.org/delay/2"),
    ]);
    return new Response("OK");
  }
};
```

Expected: Request completes in ~2s (parallel), not ~3s (serial)

---

## Known Limitations

1. **DNS over HTTPS:** Uses OS resolver (simplicity). TLS not added to DNS.
2. **Redirects:** Not followed automatically (HTTP 3xx requires manual fetch in JS)
3. **Streaming request body:** Not supported (must buffer full body upfront)
4. **Streaming response body:** Supported (ReadableStream returned in response.body)
5. **Cancellation:** No AbortController timeout via xev (use JS timeout instead)

---

## Comparison to Node.js/Deno

| Feature | NANO | Node.js | Deno |
|---------|------|---------|------|
| Event loop | xev | libuv | tokio |
| Promise tracking | xev callbacks | libuv handles | tokio tasks |
| Socket API | std.net | libuv wrapper | Deno HTTP |
| DNS | OS resolver | getaddrinfo | OS resolver |
| Timeout | xev Timer | setTimeoutInternal | tokio sleep |

NANO's approach is simplest (fewest dependencies), but lacks Node's mature error recovery.
