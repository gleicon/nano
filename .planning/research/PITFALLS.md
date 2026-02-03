# Pitfalls Research: JavaScript Isolate Runtime

## Critical Pitfalls

These will **definitely break the project** if ignored.

### 1. HandleScope Mismanagement

**The Problem:** V8 local handles are garbage collected. Without proper HandleScope, handles become invalid mid-execution.

```cpp
// WRONG - handle becomes invalid
v8::Local<v8::String> GetString(v8::Isolate* isolate) {
  return v8::String::NewFromUtf8(isolate, "hello").ToLocalChecked();
  // Handle is on stack, becomes invalid when function returns
}

// CORRECT - caller's HandleScope keeps handle alive
v8::Local<v8::String> GetString(v8::Isolate* isolate) {
  v8::EscapableHandleScope scope(isolate);
  auto str = v8::String::NewFromUtf8(isolate, "hello").ToLocalChecked();
  return scope.Escape(str);  // Moves to outer scope
}
```

**Prevention:**
- Every function touching V8 values needs HandleScope
- Use EscapableHandleScope to return values
- Never store Local<> handles long-term (use Persistent<> or Global<>)

**Phase Impact:** Phase 1 - must be correct from the start

### 2. Isolate Threading Violations

**The Problem:** V8 isolates are **single-threaded**. Touching an isolate from wrong thread = undefined behavior (usually crash).

```cpp
// WRONG - calling from wrong thread
std::thread([isolate]() {
  isolate->Enter();  // CRASH: wrong thread
}).detach();

// CORRECT - use Locker for multi-threaded access
std::thread([isolate]() {
  v8::Locker lock(isolate);
  v8::Isolate::Scope isolate_scope(isolate);
  // Now safe
}).join();
```

**Prevention:**
- One thread owns each isolate
- If sharing isolates, use v8::Locker
- Design for single-threaded isolates, multiple isolates per process

**Phase Impact:** Phase 3 - when adding concurrency

### 3. Memory Limits Not Enforced

**The Problem:** Without explicit limits, one app can exhaust process memory and crash everything.

```cpp
// WRONG - no limits
v8::Isolate* isolate = v8::Isolate::New(create_params);

// CORRECT - enforce limits
v8::ResourceConstraints constraints;
constraints.set_max_old_generation_size_in_bytes(128 * 1024 * 1024);  // 128MB
constraints.set_max_young_generation_size_in_bytes(16 * 1024 * 1024); // 16MB
create_params.constraints = constraints;
v8::Isolate* isolate = v8::Isolate::New(create_params);
```

**Prevention:**
- Set memory limits at isolate creation
- Monitor heap usage with `isolate->GetHeapStatistics()`
- Terminate and recreate if limits exceeded

**Phase Impact:** Phase 5 - production hardening

### 4. CPU Time Bombs

**The Problem:** Infinite loops or expensive computations block the entire process.

```javascript
// Malicious or buggy code
while(true) {}  // Blocks forever
```

**Prevention:**
```cpp
// Set execution timeout
isolate->SetCaptureStackTraceForUncaughtExceptions(true);

// Watchdog thread
std::thread watchdog([isolate, &done]() {
  std::this_thread::sleep_for(std::chrono::milliseconds(50));
  if (!done) {
    isolate->TerminateExecution();
  }
});
```

**Phase Impact:** Phase 5 - must have before any untrusted code

## V8 Embedding Gotchas

### GC Callback Timing

**The Problem:** V8's GC can run at unexpected times, invalidating assumptions.

```cpp
// WRONG - pointer may be invalid after allocation
char* data = GetExternalData();
auto str = v8::String::NewFromUtf8(isolate, "trigger GC");  // GC might run here
UseData(data);  // data pointer may be invalid if GC moved things

// CORRECT - pin external data or re-acquire after V8 calls
```

**Prevention:**
- Assume any V8 call can trigger GC
- Don't hold raw pointers across V8 calls
- Use SetData()/GetData() for persistent embedder data

### TryCatch Scope Confusion

**The Problem:** Exception handling in V8 is scope-based, not stack-based.

```cpp
// WRONG - exception lost
void Outer(v8::Isolate* isolate) {
  v8::TryCatch try_catch(isolate);
  Inner(isolate);  // Exception in Inner
  // try_catch sees the exception here, but...
}

void Inner(v8::Isolate* isolate) {
  v8::TryCatch inner_catch(isolate);
  ThrowError();
  // inner_catch catches it, outer never sees it
}
```

**Prevention:**
- TryCatch at the right level (usually outermost)
- Check `try_catch.HasCaught()` immediately after risky calls
- Use `try_catch.ReThrow()` to propagate

### Context vs Isolate Confusion

**The Problem:** Multiple contexts in one isolate can cross-contaminate.

```
Isolate
├── Context A (App 1)
│   └── globalThis.secret = "password"
└── Context B (App 2)
    └── Can potentially access Context A?
```

**Prevention:**
- One context per isolate for multi-tenant (NANO's approach)
- Don't share contexts between apps
- If using multiple contexts, understand security implications

## Isolation Failures

### Spectre/Meltdown Side Channels

**The Problem:** CPU timing attacks can leak data across isolate boundaries.

**Cloudflare's Response:**
- Disable `SharedArrayBuffer` (prevents precise timing)
- Reduce `performance.now()` precision
- Isolate groups with different security levels in different processes

**NANO Prevention:**
- Don't expose SharedArrayBuffer initially
- Limit timer precision
- Document that same-process isolation is not cryptographic

### Prototype Pollution

**The Problem:** Modifying built-in prototypes affects all code in the context.

```javascript
// App A
Array.prototype.forEach = function() { /* malicious */ };

// App B (same context - BAD)
[1,2,3].forEach(x => console.log(x));  // Runs malicious code
```

**NANO Prevention:**
- Separate isolates per app (not just contexts)
- Freeze built-in prototypes if sharing contexts
- Never share contexts between untrusted apps

### Native Binding Escapes

**The Problem:** Bugs in native bindings can expose host capabilities.

```javascript
// If fetch() binding has a bug...
fetch("file:///etc/passwd")  // Should be blocked but might not be
```

**Prevention:**
- Allowlist protocols (http, https only)
- Validate all inputs in native code
- Never pass raw file paths from JS to native

## Performance Traps

### Creating Isolates Per Request

**The Problem:** Isolate creation is expensive (40-100ms without snapshots).

```cpp
// WRONG - slow path on every request
void HandleRequest() {
  v8::Isolate* isolate = v8::Isolate::New(params);  // 40ms+
  // handle request
  isolate->Dispose();
}
```

**Prevention:**
- Pool isolates (reuse warm isolates)
- Use snapshots for fast creation
- Pre-warm isolates during low traffic

### String Encoding Conversions

**The Problem:** UTF-8 ↔ UTF-16 conversion on every string crossing.

```cpp
// Every JS string → native crosses encoding boundary
v8::String::Utf8Value utf8(isolate, js_string);  // Allocates, converts
```

**Prevention:**
- Minimize string crossings
- Use ArrayBuffer for binary data (no encoding)
- Cache converted strings when possible
- Use V8's one-byte strings when ASCII-only

### Synchronous Native Calls Blocking Event Loop

**The Problem:** Blocking native calls freeze all apps in the process.

```javascript
// If fetch() is synchronous...
const resp = fetch(slow_url);  // Blocks entire process for 5 seconds
```

**Prevention:**
- All I/O must be async
- Use non-blocking native event loop
- Offload slow work to thread pool

### Cold Start Hidden in Warm Paths

**The Problem:** Lazy initialization that triggers on first request.

```cpp
// First request pays initialization cost
static bool initialized = false;
if (!initialized) {
  HeavyInitialization();  // 100ms one-time cost
  initialized = true;
}
```

**Prevention:**
- Initialize everything at startup
- Measure first-request vs subsequent latency
- Put heavy init in snapshot creation

## Zig + C++ Interop Issues

### Zig Allocator vs C++ new/delete

**The Problem:** Memory allocated by C++ must be freed by C++, and vice versa.

```zig
// WRONG - freeing C++ memory with Zig allocator
const ptr = v8_get_string();  // C++ allocated
allocator.free(ptr);  // Zig trying to free - CRASH

// CORRECT - use matching deallocation
const ptr = v8_get_string();
v8_free_string(ptr);  // C++ frees its own memory
```

**Prevention:**
- Clear ownership rules (who allocates, who frees)
- Wrapper functions that handle allocation on one side
- Arena allocator on Zig side, let C++ manage its own

### C++ Exception Propagation

**The Problem:** C++ exceptions don't propagate through Zig stack frames.

```cpp
// C++ throws
void cpp_function() {
  throw std::runtime_error("error");
}

// Zig calls it
extern fn cpp_function() void;  // No exception handling
```

**Prevention:**
- Wrap all C++ calls in try/catch at the boundary
- Return error codes instead of throwing
- V8 uses TryCatch, not C++ exceptions (good)

### Callback Function Pointer Lifetimes

**The Problem:** Zig function pointers passed to C++ can become invalid.

```zig
// WRONG - closure might be freed
const callback = struct {
  fn call() void { ... }
}.call;
v8_set_callback(&callback);  // Pointer to stack

// CORRECT - use persistent function pointers
fn myCallback() callconv(.C) void { ... }
v8_set_callback(&myCallback);  // Function pointer always valid
```

**Prevention:**
- Use `callconv(.C)` for C-compatible functions
- No closures passed to C (capture state differently)
- Keep callback data alive for duration of use

### String Encoding Between Zig and V8

**The Problem:** Zig uses UTF-8, V8 uses UTF-16 internally.

```zig
// Need conversion layer
const zig_string: []const u8 = "hello";  // UTF-8
// Must convert to V8's expected format
```

**Prevention:**
- Use V8's UTF-8 APIs where available
- Write conversion helpers once, test thoroughly
- Consider ExternalOneByteString for ASCII content

---

## v1.2 Production Polish: Key Pitfalls

### Streams Pitfalls

**S1: Unbounded Queue Growth**
- Arena allocator exhausted by streaming responses where producer > consumer
- Check `controller.desiredSize` before enqueue; implement pull-based streaming
- Phase: 01-streams

**S2: TransformStream Backpressure Bypass**
- `controller.enqueue()` ignores backpressure, violates WHATWG spec
- Check `desiredSize <= 0`, return Promise if queue full
- Phase: 01-streams

**S3: Chunk Lifetime Across V8/Zig Boundary**
- Zig arena memory freed while V8 holds stream chunk reference → use-after-free
- Clear ownership: V8 owns ArrayBuffer OR Zig copies on boundary; use `ArrayBuffer::Externalize()`
- Phase: 01-streams

**Integration - Arena + Streams**
- Streams outlive request; arena freed mid-streaming
- Separate allocator for stream buffers OR reference counting OR copy to V8 heap
- Phase: 01-streams CRITICAL

**Integration - Watchdog + Streams**
- CPU watchdog (5s) terminates long-running streams → corrupted response
- Track CPU time not wall clock; I/O wait doesn't count; extend timeout for streams
- Phase: 01-streams

### Graceful Shutdown Pitfalls

**G1: Signal Handler Race**
- Signal handler modifies state while V8 executing → inconsistent state (CWE-364)
- Handler ONLY sets atomic flag; use `signalfd()` or self-pipe for integration
- Phase: 02-shutdown

**G2: No In-Flight Request Tracking**
- Server closes socket while processing request → partial response, connection reset
- Add atomic counter for in-flight; shutdown waits counter==0 or 30s timeout
- Phase: 02-shutdown

**G3: App Removal Without Drain**
- `DELETE /admin/apps` removes immediately; in-flight requests lose isolate → crash
- Mark app "draining" first (stop routing); wait for in-flight; return 503 for new
- Phase: 02-shutdown

**Integration - Hot Reload + Shutdown**
- Config reload and full shutdown use different paths → bugs in one but not other
- Extract common "app drain + dispose" logic; use same path for all removal scenarios
- Phase: 02-shutdown

### Environment Variable Pitfalls

**E1: Process.env Contamination**
- Modifying global `process.env` leaks one app's secrets to other apps (critical multi-tenant)
- Per-isolate env on context global; freeze after creation; each isolate gets copy
- Phase: 03-env-vars

**E2: Prototype Pollution**
- Plain JS env object allows `env.__proto__.SECRET = "hack"` → prototype chain pollution
- Create with `Object.create(null)`, freeze, use V8 template with null prototype
- Phase: 03-env-vars

**E3: Leakage via Side Channels**
- Secrets leak through error messages, logs, stack traces even with isolation
- Sanitize errors; never log env values; separate "secrets" from "config"; redact traces
- Phase: 03-env-vars

**Integration - Multi-App Env Isolation**
- Env vars stored on shared structures → isolation fails
- Env vars per-isolate, not per-platform; test with multiple apps same key, different values
- Phase: 03-env-vars

---

## Prevention Checklist by Phase

### Phase 1: V8 Foundation
- [ ] HandleScope in every V8-touching function
- [ ] EscapableHandleScope for returning handles
- [ ] TryCatch at execution boundaries
- [ ] Clear allocator ownership rules
- [ ] No closures passed to C++

### Phase 2: API Surface
- [ ] All native bindings return errors, not throw
- [ ] Protocol validation in fetch (http/https only)
- [ ] Timer precision limits (1ms minimum)
- [ ] No SharedArrayBuffer exposure

### Phase 3: Multi-App Routing
- [ ] One isolate per app (not shared contexts)
- [ ] Isolate affinity (same thread always)
- [ ] No cross-app references possible

### Phase 4: Snapshots
- [ ] Snapshot creation tested with all APIs
- [ ] Cold start measured and validated
- [ ] Snapshot versioning (rebuild on API change)

### Phase 5: Production Hardening
- [ ] Memory limits enforced at creation
- [ ] CPU watchdog terminates runaways
- [ ] Heap statistics monitoring
- [ ] Structured error responses (no stack traces to clients)

### v1.2: Streams API
- [ ] Pull-based streaming (not pump/start)
- [ ] Backpressure check before enqueue
- [ ] Chunk ownership model clear (V8 or Zig)
- [ ] Memory bounded (highWaterMark enforced)
- [ ] Arena vs stream allocator separation

### v1.2: Graceful Shutdown
- [ ] Signal handler only sets atomic flag
- [ ] In-flight request counter
- [ ] Drain timeout separate from request timeout
- [ ] App removal drains requests first
- [ ] Config watcher stops first in shutdown

### v1.2: Environment Variables
- [ ] Per-isolate env storage (not global)
- [ ] Object.create(null), then freeze
- [ ] No `process.env` modification
- [ ] Error sanitization (no env leaks)
- [ ] Env var size limits (64 vars, 5KB each)

## Testing Strategies

### Memory Leak Detection
```bash
zig build -Drelease-safe -fsanitize=address
```

### Isolation Verification
```javascript
// App A
globalThis.secret = "A's secret";
// App B
console.assert(globalThis.secret === undefined);
```

### Shutdown Testing
```bash
for i in {1..100}; do curl "http://localhost:8080/slow" & done
kill -TERM $NANO_PID
# Verify: no crashes, graceful completion or errors
```

### Streams Memory Test
```javascript
const rs = new ReadableStream({
  pull(c) { c.enqueue(new Uint8Array(1024)); }
});
const ws = new WritableStream({
  write(chunk) { return new Promise(r => setTimeout(r, 100)); }
});
rs.pipeTo(ws);
// Memory should stay bounded
```

### Env Isolation Test
```javascript
// App A: env.SECRET = "A"
// App B: console.assert(env.SECRET === "B")
```
