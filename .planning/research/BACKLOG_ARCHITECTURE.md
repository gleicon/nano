# Architecture Patterns: NANO Backlog Fixes Integration

**Project:** NANO (Zig+V8 runtime, ~11,000 LoC)
**Researched:** 2026-02-15
**Scope:** How 7 backlog fixes integrate with existing single-threaded, arena-allocated architecture
**Confidence:** HIGH (architecture hand-traced from source, patterns confirmed across codebase)

---

## Current Architecture Overview

### Core Components

```
┌─────────────────────────────────────────────────────────┐
│ src/main.zig — CLI Entry (eval, repl, serve)           │
└──────────────────┬──────────────────────────────────────┘
                   │
        ┌──────────┴──────────┐
        │                     │
┌───────▼──────────┐  ┌──────▼─────────────┐
│ src/server/      │  │ src/runtime/       │
│  http.zig        │  │  event_loop.zig    │
│  app.zig         │  │  timers.zig        │
└────┬─────────────┘  │  watchdog.zig      │
     │                └─────────────────────┘
     │
┌────▼──────────────────────────────────────────────────┐
│ src/api/* — API implementations                       │
│  fetch.zig, readable_stream.zig, writable_stream.zig │
│  crypto.zig, url.zig, blob.zig, headers.zig, etc.   │
└────────────────────────────────────────────────────────┘
```

### Memory Architecture

| Tier | Allocator | Lifetime | Usage |
|------|-----------|----------|-------|
| **Request-level** | `page_allocator` (per request) | Request lifetime | Buffer writes, response body assembly |
| **Persistent Callbacks** | `page_allocator` | Timer lifetime | V8 persistent handles for setTimeout/setInterval |
| **Server-level** | `std.mem.Allocator` (gpa) | Server lifetime | Apps, hostname maps, event loop |
| **V8 Heap** | V8's allocator | Isolate lifetime | JS values, strings, objects |
| **Stack** | Stack | Scope lifetime | URL buffers, parsing buffers, headers |

**Key pattern:** Request allocator is NOT arena — it's page_allocator. **Problem #1 manifests here.**

### Event Loop Architecture

```
Event Loop (xev-based):
  ├─ Timers (xev.Timer)
  │   ├─ setTimeout/setInterval → add to timer map
  │   └─ Fire → callback_ptr (heap-allocated persistent handle)
  │
  ├─ Config Watcher (ConfigWatcher)
  │   └─ Poll every 10s, trigger reload if mtime changed
  │
  └─ Completion Handlers
      └─ Called after events fire (socket, timer, etc.)
```

**Async Pattern:** Timers fire in event loop's `run(.no_wait)`, callbacks stored as persistent V8 handles allocated from `page_allocator`. During request, `handleRequest` calls `loop.tick()` to drain pending timers.

### V8 Integration

- **Isolate:** Shared per app (persistent across requests)
- **Context:** Persistent handle, re-entered for each request
- **HandleScope:** Created fresh for each request
- **Promise handling:** In `handleRequest`, create `PromiseResolver`, call handler, wait for resolution by spinning event loop
- **Persistent handles:** Used for timers, fetch responses stored as properties on JS objects

---

## Integration Analysis: The 7 Backlog Fixes

### Fix 1: Heap Buffers (Large Body Handling)

**Current Problem:** Stack-allocated buffers throughout `src/api/*.zig`:
```zig
var url_buf: [4096]u8 = undefined;  // fetch.zig:167
var data_storage: [8192]u8 = undefined;  // crypto.zig:114
var body_buf: [65536]u8 = undefined;  // fetch.zig:172
```

**Integration Points:**
- `fetch.zig:167-172` — URL, method, body parsing use fixed stacks
- `crypto.zig:114-154` — Digest input data cached on stack
- `readable_stream.zig:87` — Queued chunks stored as JS objects (no heap issue)
- `writable_stream.zig:81` — Write queue also JS objects

**Integration Strategy:**

1. **For API input parsing (fetch URLs, crypto data):**
   - Keep stack buffers but add allocation fallback
   - Pattern: Try stack, fallback to request allocator if buffer > threshold
   ```zig
   var url_buf: [4096]u8 = undefined;
   var url_data: []u8 = undefined;
   if (input_len <= 4096) {
       url_data = &url_buf;
   } else {
       url_data = allocator.alloc(u8, input_len) catch {
           js.throw(isolate, "URL too large");
           return;
       };
       defer allocator.free(url_data);
   }
   ```

2. **Allocator choice:** Use request-level allocator from context
   - `Context-aware allocator passing:` Modify V8 callback context to carry request allocator
   ```zig
   pub const CallbackContext = struct {
       allocator: std.mem.Allocator,  // NEW
       // ... existing fields
   };
   ```
   - Problem: `CallbackContext.init()` doesn't have access to request allocator currently
   - **Solution:** Store request allocator on Context as internal property
     ```zig
     // In handleRequest (app.zig)
     const request_allocator = allocator;  // Already passed in
     // Store on context (before calling fetch)
     _ = js.setProp(context.getGlobal(), context, isolate, "__nano_request_allocator", ...);

     // In callbacks, retrieve it
     const ctx_global = ctx.context.getGlobal();
     const alloc_val = js.getProp(ctx_global, ctx.context, ctx.isolate, "__nano_request_allocator");
     // Extract allocator pointer from V8 external value
     ```

3. **Lifetime:** Request allocator is freed after response sent (in `http.zig:606-613`)

**New Component:** `src/allocator_context.zig` — Helper for storing/retrieving request allocator from V8 context

---

### Fix 2: Async Fetch (Socket Completion Integration)

**Current Problem:** fetch.zig creates promises but doesn't actually execute HTTP in background. Returns immediately (returns promise but never populates it).

**Current Pattern:**
```zig
// fetch.zig:162-163
const resolver = v8.PromiseResolver.init(context);
const promise = resolver.getPromise();
// ... but never calls resolver.resolve() or resolver.reject()
```

**Integration Points:**
- `fetch.zig:151-272` — fetchCallback creates promise, builds request, but doesn't actually send
- `event_loop.zig` — Has xev event loop, can support async I/O
- `app.zig:550-558` — Promise wait loop spins event loop

**Integration Strategy:**

1. **Store promise resolver as persistent handle:**
   ```zig
   // In fetchCallback
   const persistent_resolver = persistent_allocator.create(v8.Persistent(v8.PromiseResolver)) catch {
       js.throw(isolate, "OOM");
       return;
   };
   persistent_resolver.* = v8.Persistent(v8.PromiseResolver).init(isolate, resolver);
   ```

2. **Schedule xev socket operation:**
   ```zig
   // Create socket connection via xev
   // Schedule async TCP connect + HTTP request send/receive
   // Store completion handler that resolves promise
   loop.addSocketOp(hostname, port, request_data, persistent_resolver, onFetchComplete);
   ```

3. **Completion callback pattern:**
   ```zig
   fn onFetchComplete(
       resolver_ptr: *v8.Persistent(v8.PromiseResolver),
       result: SocketOpResult,
   ) void {
       const isolate = resolver_ptr.getIsolate();  // Need to recover isolate
       const resolver = resolver_ptr.castToPromiseResolver();
       const context = isolate.getCurrentContext();

       if (result.success) {
           // Parse HTTP response
           const response_obj = buildResponseObject(...);
           _ = resolver.resolve(context, response_obj.toValue());
       } else {
           _ = resolver.reject(context, js.string(isolate, result.error).toValue());
       }
       resolver_ptr.deinit();
       persistent_allocator.destroy(resolver_ptr);
   }
   ```

4. **EventLoop expansion needed:**
   - Add socket operation support to `event_loop.zig`
   - Use libxev's socket APIs (already imported in build.zig)
   - Structure: `xev.Tcp` for connections, `xev.Completion` for I/O tracking

**New Components:**
- `src/runtime/socket_ops.zig` — Async socket operations, completion callbacks
- Expand `event_loop.zig` with socket operation queue and completion handling

**Build Dependencies:**
- libxev already available (build.zig:16)

---

### Fix 3: WritableStream Async Write Queue (Promise-Aware)

**Current Problem:** `writable_stream.zig` has synchronous write queue. Needs to resolve `ready` promise when backpressure cleared.

**Current State:**
```zig
// writable_stream.zig:80-84
_ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_queue", js.array(ctx.isolate, 0));
_ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_queueByteSize", js.number(ctx.isolate, 0));
_ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_writing", js.boolean(ctx.isolate, false));
// No tracking of pending write promises
```

**Integration Points:**
- `writable_stream.zig:41` — `write()` method adds to queue
- `writable_stream.zig:47-51` — `ready` property getter (returns pending promise)
- No backpressure mechanism currently

**Integration Strategy:**

1. **Track pending write resolvers:**
   ```zig
   // In WritableStream constructor
   _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_pendingWriteResolvers", js.array(ctx.isolate, 0));
   // Array stores persistent handles to PromiseResolver objects
   ```

2. **write() method returns Promise:**
   ```zig
   fn writerWrite(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
       const ctx = js.CallbackContext.init(raw_info);

       // Create promise for this write
       const write_resolver = v8.PromiseResolver.init(ctx.context);
       const write_promise = write_resolver.getPromise();

       // Persist the resolver
       const persistent = persistent_allocator.create(...) catch return;
       persistent.* = v8.Persistent(v8.PromiseResolver).init(ctx.isolate, write_resolver);

       // Add to pending resolvers list
       // Check queue size against highWaterMark
       if (queue_size > hwm) {
           // Backpressure: store resolver, resolve later when queue drains
           appendToPendingResolvers(ctx.this, ctx.context, ctx.isolate, persistent);
       } else {
           // Resolve immediately
           _ = write_resolver.resolve(ctx.context, js.undefined_(ctx.isolate).toValue());
           persistent.deinit();
           persistent_allocator.destroy(persistent);
       }

       js.ret(ctx, write_promise);
   }
   ```

3. **Queue drain resolution:**
   - When sink's write() completes (via async callback from Fix 2), resolve pending write promises
   - Coordinate with underlying sink's backpressure mechanism

4. **ready property should return pending promise:**
   ```zig
   fn writerReadyGetter(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
       const ctx = js.CallbackContext.init(raw_info);

       const pending = js.getProp(ctx.this, ctx.context, ctx.isolate, "_pendingReady") catch null;
       if (pending) |p| {
           js.ret(ctx, p);
       } else {
           // Create resolved promise
           const resolver = v8.PromiseResolver.init(ctx.context);
           _ = resolver.resolve(ctx.context, js.undefined_(ctx.isolate).toValue());
           js.ret(ctx, resolver.getPromise());
       }
   }
   ```

**New Mechanism:** Promise-aware backpressure queue (vs current synchronous queue)

---

### Fix 4: crypto.subtle Expansion (AES/RSA/ECDSA)

**Current State:** `crypto.zig` implements SHA-256/384/512, SHA-1, randomUUID. No AES, RSA, ECDSA.

**Integration Points:**
- `crypto.zig:18-20` — crypto.subtle object registered
- `crypto.zig:96-177` — digest() implemented (SHA family)
- `crypto.zig:193+` — sign/verify stubs exist but minimal

**Zig std.crypto Capabilities:**
```
std.crypto.hash.*       — SHA, MD5, BLAKE2, etc. (already using)
std.crypto.aes          — AES128, AES256
std.crypto.dsa          — ECDSA (elliptic curve)
std.crypto.rsa          — RSA operations
```

**Integration Strategy:**

1. **For each algorithm (AES, RSA, ECDSA):**
   - Expand `digest()` to recognize algorithm name (e.g., "AES-GCM")
   - Parse algorithm parameters from `algorithm` object (key size, mode, etc.)
   ```zig
   // Input: { name: "AES-GCM", length: 256 }
   // data: plaintext, key: encryption key
   ```

2. **AES-GCM (symmetric):**
   ```zig
   if (std.mem.eql(u8, algo, "AES-GCM")) {
       const key_len: usize = @intFromFloat(key_len_f); // 128, 192, or 256 bits
       const key: []const u8 = extractKey(key_arg);
       const iv: []const u8 = extractIV(iv_arg);
       const aad: []const u8 = extractAAD(aad_arg);

       var ciphertext: [8192]u8 = undefined;
       var tag: [16]u8 = undefined;

       std.crypto.aes.Gcm(std.crypto.aes.Aes256).encrypt(
           &ciphertext, &tag, data, aad, iv, key
       );

       returnEncryptedAsPromise(ctx, &ciphertext, &tag);
   }
   ```

3. **ECDSA (asymmetric signing):**
   ```zig
   if (std.mem.eql(u8, algo, "ECDSA")) {
       const curve: []const u8 = extractCurve(algo_obj); // "P-256", "P-384", etc.
       const key: []const u8 = extractPrivateKey(key_arg);
       const hash: []const u8 = extractHash(data_arg);

       var signature: [132]u8 = undefined; // Max for P-521

       std.crypto.dsa.ecdsaSign(curve, key, hash, &signature);

       returnSignatureAsPromise(ctx, &signature);
   }
   ```

4. **RSA (asymmetric encryption/signing):**
   - Larger effort: RSA requires big integer arithmetic
   - **Zig std.crypto has limited RSA support** → Consider BoringSSL binding
   - Option A: Use `std.crypto.rsa` (if available in current Zig version)
   - Option B: FFI to OpenSSL/BoringSSL for RSA (adds C dependency)
   - **Recommendation: Skip RSA in backlog, defer to separate milestone** (RSA is complex, lower priority than AES/ECDSA)

5. **Key format handling:**
   - JWKS format (JSON Web Key Set) parsing
   - PEM format parsing
   - Raw key bytes
   ```zig
   fn extractKey(key_arg: v8.Value, format: []const u8) ![]const u8 {
       if (std.mem.eql(u8, format, "raw")) {
           // ArrayBuffer -> bytes
           return asArrayBuffer(key_arg);
       } else if (std.mem.eql(u8, format, "jwk")) {
           // Parse JSON, extract `k` field
           ...
       }
   }
   ```

**Dependencies:**
- `std.crypto.aes` — Available in Zig 0.11+
- `std.crypto.dsa` — Available in Zig 0.11+
- RSA — Consider BoringSSL binding if needed

**Allocator:** Use request allocator for temporary buffers, return results as V8 ArrayBuffer

---

### Fix 5: ReadableStream.tee() Fix (Per-Branch Queue)

**Current Problem:** `tee()` not implemented or has single shared queue. Needs independent queues per branch.

**Expected Behavior:**
```js
const [branch1, branch2] = readable.tee();
// Each branch reads independently with its own queue
```

**Integration Points:**
- `readable_stream.zig:19` — `tee()` method registered
- `readable_stream.zig:81-150+` — ReadableStream constructor and state

**Integration Strategy:**

1. **tee() returns tuple of two ReadableStreams:**
   ```zig
   fn readableStreamTee(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
       const ctx = js.CallbackContext.init(raw_info);

       // Get original stream's controller
       const orig_stream = ctx.this;
       const orig_controller = js.getProp(orig_stream, ctx.context, ctx.isolate, "_controller");

       // Create two new streams (branch1, branch2)
       const branch1_ctor = getReadableStreamConstructor(...);
       const branch2_ctor = getReadableStreamConstructor(...);

       const branch1 = branch1_ctor.initInstance(...);
       const branch2 = branch2_ctor.initInstance(...);

       // Link both branches to original controller
       _ = js.setProp(branch1, ctx.context, ctx.isolate, "_sourceController", orig_controller);
       _ = js.setProp(branch2, ctx.context, ctx.isolate, "_sourceController", orig_controller);

       // Each branch has its OWN queue
       _ = js.setProp(branch1, ctx.context, ctx.isolate, "_queue", js.array(ctx.isolate, 0));
       _ = js.setProp(branch2, ctx.context, ctx.isolate, "_queue", js.array(ctx.isolate, 0));

       // Return array [branch1, branch2]
       const result_array = v8.Array.init(ctx.isolate, 2);
       _ = result_array.set(ctx.context, 0, branch1.toValue());
       _ = result_array.set(ctx.context, 1, branch2.toValue());

       js.ret(ctx, result_array);
   }
   ```

2. **Branch coordination:**
   - Original controller tracks all branches
   - When original emits chunk: send to all branches' independent queues
   ```zig
   // In controllerEnqueue (original stream's controller)
   fn controllerEnqueue(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
       const ctx = js.CallbackContext.init(raw_info);
       const chunk = ctx.arg(0);

       const stream = js.getProp(ctx.this, ctx.context, ctx.isolate, "_stream");

       // Check if stream has branches
       const branches = js.getProp(stream, ctx.context, ctx.isolate, "_teeBranches") catch null;
       if (branches) |b| {
           if (b.isArray()) {
               const branches_array = v8.Array{ .handle = @ptrCast(b.handle) };
               const num_branches = branches_array.length();

               // Enqueue to each branch independently
               for (0..num_branches) |i| {
                   const branch = branches_array.get(ctx.context, @intCast(i));
                   const branch_queue = js.getProp(branch.asObject(), ctx.context, ctx.isolate, "_queue");
                   appendToQueue(branch_queue.asArray(), chunk);
               }
           }
       } else {
           // No branches, normal enqueue
           const queue = js.getProp(stream, ctx.context, ctx.isolate, "_queue");
           appendToQueue(queue.asArray(), chunk);
       }
   }
   ```

3. **Queue independence:**
   - Each branch track its own `_queueByteSize`, `_pulling`, `desiredSize`
   - When branch's reader reads: consume from that branch's queue only

**New Component:** tee() coordination state tracking within ReadableStream

---

### Fix 6: WinterCG Essentials (structuredClone + Microtasks)

**Current Problem:**
- `structuredClone()` not available globally
- Microtasks not fully integrated with event loop

**Integration Points:**
- Global object registration in `app.zig:200+` (registerXXXAPI calls)
- `event_loop.zig` — Event loop tick
- `app.zig:544` — `performMicrotasksCheckpoint()` called but microtasks may not queue properly

**Integration Strategy:**

1. **structuredClone() implementation:**
   ```zig
   // In new file: src/api/structured_clone.zig
   pub fn registerStructuredCloneAPI(isolate: v8.Isolate, context: v8.Context) void {
       const global = context.getGlobal();
       const clone_fn = v8.FunctionTemplate.initCallback(isolate, structuredCloneCallback);
       _ = global.setValue(context, v8.String.initUtf8(isolate, "structuredClone"), clone_fn.getFunction(context));
   }

   fn structuredCloneCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
       const ctx = js.CallbackContext.init(raw_info);

       if (ctx.argc() < 1) {
           js.throw(ctx.isolate, "structuredClone requires an argument");
           return;
       }

       const value = ctx.arg(0);

       // V8 provides serialization API
       const serializer = v8.ValueSerializer.init(ctx.isolate);
       const bytes = serializer.serialize(ctx.context, value) catch {
           js.throw(ctx.isolate, "Failed to serialize value");
           return;
       };

       // Deserialize in same context (creates deep copy)
       const deserializer = v8.ValueDeserializer.init(ctx.isolate, bytes);
       const cloned = deserializer.deserialize(ctx.context) catch {
           js.throw(ctx.isolate, "Failed to deserialize value");
           return;
       };

       js.ret(ctx, cloned);
   }
   ```

2. **Microtask queue integration:**
   - Microtasks are already called via `performMicrotasksCheckpoint()` in app.zig:544, 556
   - Ensure they're also drained between event loop ticks
   ```zig
   // In event_loop.zig tick()
   pub fn tick(self: *EventLoop) !void {
       // Run one event loop iteration
       _ = self.loop.run(.no_wait) catch {};

       // Run microtasks after event loop tick
       // (need isolate reference — pass from handleRequest context)
   }
   ```

3. **Promise integration:**
   - Promises automatically queue microtasks in V8
   - Ensure `performMicrotasksCheckpoint()` is called after Promise resolution
   - Already done in app.zig:556

**New Component:** `src/api/structured_clone.zig` — Serialization/deserialization API

**Build:** No new dependencies, V8 API already available

---

### Fix 7: URL Property Setters (Re-serialization)

**Current Problem:** URL getters work, but setters (url.pathname = "/new") don't exist or don't re-serialize.

**Current State:**
```zig
// url.zig:14-39 — All getters, no setters
const href_getter = v8.FunctionTemplate.initCallback(isolate, urlGetHref);
url_proto.setAccessorGetter(js.string(isolate, "href").toName(), href_getter);
// No setter!
```

**Expected Behavior:**
```js
const url = new URL("http://example.com/path");
url.pathname = "/newpath";
console.log(url.href); // "http://example.com/newpath"
```

**Integration Points:**
- `url.zig:10-44` — URL template registration
- `url.zig:64-150+` — URL constructor and storage

**Integration Strategy:**

1. **Add setter for each property:**
   ```zig
   // url.zig
   const pathname_setter = v8.FunctionTemplate.initCallback(isolate, urlSetPathname);
   url_proto.setAccessorSetter(js.string(isolate, "pathname").toName(), pathname_setter);

   const search_setter = v8.FunctionTemplate.initCallback(isolate, urlSetSearch);
   url_proto.setAccessorSetter(js.string(isolate, "search").toName(), search_setter);

   // ... similar for port, hash, hostname, etc.
   ```

2. **Re-serialization on setter:**
   ```zig
   fn urlSetPathname(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
       const ctx = js.CallbackContext.init(raw_info);

       const new_pathname_str = ctx.arg(0).toString(ctx.context) catch {
           js.throw(ctx.isolate, "pathname must be a string");
           return;
       };

       var pathname_buf: [2048]u8 = undefined;
       const new_pathname = js.readString(ctx.isolate, new_pathname_str, &pathname_buf);

       // Update stored pathname
       _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_pathname", js.string(ctx.isolate, new_pathname));

       // Re-serialize full URL from components
       const protocol = js.getProp(ctx.this, ctx.context, ctx.isolate, "_protocol") catch "";
       const hostname = js.getProp(ctx.this, ctx.context, ctx.isolate, "_hostname") catch "";
       const port = js.getProp(ctx.this, ctx.context, ctx.isolate, "_port") catch "";
       const search = js.getProp(ctx.this, ctx.context, ctx.isolate, "_search") catch "";
       const hash = js.getProp(ctx.this, ctx.context, ctx.isolate, "_hash") catch "";

       var href_buf: [4096]u8 = undefined;
       const href = std.fmt.bufPrint(&href_buf, "{s}{s}{s}{s}{s}{s}",
           .{ protocol, hostname, port, new_pathname, search, hash }
       ) catch "";

       _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_href", js.string(ctx.isolate, href));
   }
   ```

3. **Port setter special case:**
   ```zig
   fn urlSetPort(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
       const ctx = js.CallbackContext.init(raw_info);
       const port_str = ctx.arg(0).toString(ctx.context) catch "";

       // Validate port is 0-65535
       const port_num = std.fmt.parseInt(u16, port_str, 10) catch {
           // Invalid port — ignore (per WHATWG URL spec)
           return;
       };

       var port_buf: [8]u8 = undefined;
       const port_formatted = std.fmt.bufPrint(&port_buf, "{d}", .{port_num}) catch "";
       _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_port", js.string(ctx.isolate, port_formatted));

       // Re-serialize href
       reserializeHref(ctx);
   }
   ```

4. **Helper function for href re-serialization:**
   ```zig
   fn reserializeHref(ctx: js.CallbackContext) void {
       const protocol = js.getProp(ctx.this, ctx.context, ctx.isolate, "_protocol") catch "";
       const hostname = js.getProp(ctx.this, ctx.context, ctx.isolate, "_hostname") catch "";
       const port = js.getProp(ctx.this, ctx.context, ctx.isolate, "_port") catch "";
       const pathname = js.getProp(ctx.this, ctx.context, ctx.isolate, "_pathname") catch "";
       const search = js.getProp(ctx.this, ctx.context, ctx.isolate, "_search") catch "";
       const hash = js.getProp(ctx.this, ctx.context, ctx.isolate, "_hash") catch "";

       var href_buf: [4096]u8 = undefined;
       const href = std.fmt.bufPrint(&href_buf, "{s}{s}{s}{s}{s}{s}",
           .{ protocol, hostname, port, pathname, search, hash }
       ) catch "";

       _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_href", js.string(ctx.isolate, href));
   }
   ```

**Setters Required:** pathname, search, hash, port, hostname (protocol and origin are read-only per spec)

**No new component needed** — expand existing `url.zig`

---

## Component Boundaries & Data Flow

### New Components Introduced

| Component | File | Responsibility | Lifetime |
|-----------|------|-----------------|----------|
| AllocatorContext | `src/allocator_context.zig` | Store/retrieve request allocator from V8 context | Module-level helpers |
| SocketOps | `src/runtime/socket_ops.zig` | Async socket operations, xev integration | Event loop lifetime |
| StructuredClone | `src/api/structured_clone.zig` | Clone JS values via serialization | Per-call |
| ExpandedCrypto | `src/api/crypto.zig` (expanded) | AES, ECDSA (keep existing SHA) | Per-call |

### Modified Components

| Component | Changes | Impact |
|-----------|---------|--------|
| `src/api/fetch.zig` | Use SocketOps for async HTTP, Promise-aware | Async fetch returns actual working Promise |
| `src/api/writable_stream.zig` | Add pending write resolver tracking | write() returns backpressure-aware Promise |
| `src/api/readable_stream.zig` | Implement tee() with branch queues | tee() returns two independent streams |
| `src/api/url.zig` | Add setters for all properties | URL mutations re-serialize |
| `src/runtime/event_loop.zig` | Add socket operation queue | Supports async I/O completion |
| `src/server/app.zig` | Store request allocator on context | Fixes #1 |
| `src/allocator_context.zig` | NEW — context allocator helpers | Fixes #1 |
| `src/js.zig` | Extend CallbackContext with allocator | Fixes #1 |

### Data Flow: Async Fetch Example

```
1. User JS calls: fetch("http://example.com/api")

2. fetchCallback (fetch.zig:151)
   ├─ Create PromiseResolver
   ├─ Parse URL, method, body
   ├─ Create persistent handle for resolver
   └─ Schedule SocketOp with completion callback
   └─ Return Promise immediately

3. Event loop continues spinning (app.zig:550-558)
   └─ loop.tick() processes socket operations

4. xev socket operation completes
   └─ onFetchComplete fires (socket_ops.zig)
       ├─ Parse HTTP response
       ├─ Build Response object
       └─ resolver.resolve(context, response) → Promise resolves

5. JS awaits promise resolution
   └─ Microtask runs
   └─ .then() callbacks execute
```

---

## Build Order for the 7 Fixes

**Recommended implementation order** (dependency-based):

### Phase 1: Foundation
1. **Fix #1 — Heap Buffers (Request Allocator Context)**
   - Minimal risk, high impact on other fixes
   - Creates allocator plumbing other fixes depend on
   - No external dependencies
   - **Build time:** 4-6 hours

2. **Fix #4 — crypto.subtle Expansion (AES/ECDSA)**
   - Independent from other fixes
   - Zig std.crypto already available
   - Cryptography features don't block other APIs
   - **Build time:** 8-10 hours

### Phase 2: Async Infrastructure
3. **Fix #2 — Async Fetch (Socket Operations)**
   - Depends on: Fix #1 (allocator context)
   - Foundation for real async I/O
   - Most complex: xev socket integration, completion callbacks, Promise lifecycle
   - **Build time:** 16-20 hours

4. **Fix #6 — WinterCG Essentials (structuredClone)**
   - Independent from fetch, but pairs well with async APIs
   - V8 serialization already available
   - **Build time:** 4-6 hours

### Phase 3: Stream Improvements
5. **Fix #3 — WritableStream Async Write Queue**
   - Depends on: Fix #2 (Promise infrastructure maturing)
   - Uses PromiseResolver pattern from fix #2
   - **Build time:** 6-8 hours

6. **Fix #5 — ReadableStream.tee() Fix**
   - Independent technically, but benefits from async patterns stabilized
   - **Build time:** 4-6 hours

### Phase 4: Polish
7. **Fix #7 — URL Property Setters**
   - Completely independent, low-risk additions
   - **Build time:** 2-3 hours

**Rationale:**
- Fix #1 unblocks allocator usage in fixes #2+
- Fix #2 is most complex, deserves focused attention
- Fixes #3, #5, #6, #7 have minimal ordering constraints
- URL setters last (pure additions, no dependencies)

**Total estimated:** 44-59 hours

---

## Architecture Risks & Mitigations

### Risk 1: V8 Persistent Handle Lifecycle

**Problem:** Async callbacks (Fix #2, #3) store PromiseResolver as persistent handles. If isolate is destroyed before callback fires, crash.

**Mitigation:**
- Store isolate reference with persistent handle
- Check isolate validity before using in callback
- Implement timer/timeout on persistent handles (clean up after N seconds)
- Test with rapid app reload/unload cycles

**Code Pattern:**
```zig
const StoredPromiseResolver = struct {
    resolver: v8.Persistent(v8.PromiseResolver),
    isolate: v8.Isolate,
    created_at_ns: i128,

    fn isStale(self: @This(), timeout_ns: i128) bool {
        return (std.time.nanoTimestamp() - self.created_at_ns) > timeout_ns;
    }
};
```

### Risk 2: Request Allocator Lifetime

**Problem:** Storing request allocator on V8 context — if context outlives request, allocator use-after-free.

**Mitigation:**
- Request allocator lifetime = request lifetime (freed in http.zig after response)
- Don't cache allocator references beyond request
- Validate that stored allocator pointer is still valid (store arena marker alongside)
- Add allocator validity check in helper functions

### Risk 3: Socket Operation Backlog

**Problem:** If socket operations back up, memory grows unbounded in xev operation queue.

**Mitigation:**
- Cap pending socket operations (e.g., max 1000)
- Return "503 Too Many Requests" if queue full
- Implement operation timeout (e.g., 30s, auto-reject if no completion)
- Monitor queue depth in metrics

### Risk 4: Promise Memory Leaks

**Problem:** Promise resolvers stored in JS objects may not be cleaned up if JS object is GC'd.

**Mitigation:**
- Use V8 weak references for promise handles in JS objects
- Pair weak reference with cleanup callback
- Audit all PromiseResolver storage: ensure cleanup path exists
- Add request-scoped promise tracking to detect leaked promises

---

## Testing Strategy (Backlog Phase)

### Unit Tests
- **Allocator context:** Store/retrieve request allocator, validate lifetime
- **Socket ops:** Mock xev, test completion callbacks, promise resolution
- **WritableStream backpressure:** Test write() promise resolution, queue threshold crossing
- **tee():** Verify branch independence, chunk delivery to both queues
- **structuredClone:** Test cloning of objects, arrays, primitives, cycles
- **URL setters:** Test pathname/search/hash mutations, href re-serialization
- **Crypto:** Test AES/ECDSA against known test vectors

### Integration Tests
- **Async fetch:** Real HTTP request, verify response arrives, promise resolves
- **Stream composition:** Fetch → ReadableStream → tee() → write to WritableStream
- **Backpressure flow:** Slow consumer, verify write() blocks appropriately
- **Concurrent operations:** Multiple simultaneous fetches, stream I/O
- **Error cases:** Network errors, timeout, crypto failures

### Load Tests
- **Memory:** 1000 concurrent fetch operations, verify no leak
- **Socket limit:** Hit max pending operations, verify graceful degradation
- **Promise accumulation:** 10000 unresolved promises, verify memory stays bounded

---

## Compatibility & WinterCG Spec Alignment

### Current WinterCG Compliance

| Feature | Status | Fix Required |
|---------|--------|--------------|
| fetch() | Stub (no-op promise) | #2 |
| ReadableStream | Partial (missing tee, async bugs) | #5 |
| WritableStream | Sync queue, no backpressure | #3 |
| crypto.subtle.digest | SHA only | #4 |
| crypto.subtle.sign/verify | Stubs | #4 |
| structuredClone | Missing | #6 |
| URL getters | Complete | None |
| URL setters | Missing | #7 |

### Post-Backlog Coverage

After all 7 fixes:
- **Fetch API:** Fully async, standards-compliant
- **Streams:** Both readable and writable with backpressure, tee() support
- **Crypto:** SHA, AES-GCM (symmetric), ECDSA (asymmetric signing)
- **Serialization:** structuredClone for deep copies
- **URL:** Full WHATWG URL standard support (getters + setters)

**Remaining WinterCG gaps:**
- RSA encryption (deferred, complexity)
- TransformStream (not critical, can add later)
- ReadableStream.from() static method (partially implemented, may need fixes)

---

## Summary Table: Fixes → Components → Dependencies

| Fix | New Component | Modified Components | External Deps | Est. Effort |
|-----|---------------|---------------------|---------------|-------------|
| #1 | allocator_context.zig | js.zig, app.zig, all API files | None | 4h |
| #2 | socket_ops.zig | fetch.zig, event_loop.zig | libxev (existing) | 18h |
| #3 | None | writable_stream.zig | None | 7h |
| #4 | None (expand crypto.zig) | crypto.zig | std.crypto (existing) | 9h |
| #5 | None | readable_stream.zig | None | 5h |
| #6 | structured_clone.zig | app.zig | V8 API (existing) | 5h |
| #7 | None | url.zig | None | 3h |
| **Total** | **3** | **7** | **0 new** | **51h** |

---

## Conclusion

The 7 backlog fixes integrate cleanly with NANO's existing architecture:

1. **Memory:** Fixes #1 provides request-level allocator context, enabling heap buffers without exposing allocator to API layer
2. **Async:** Fixes #2, #3, #6 leverage V8 Promise infrastructure and event loop; xev socket integration is the main complexity
3. **Streams:** Fixes #3, #5 enhance existing stream APIs with backpressure and tee() via per-branch queues
4. **Crypto:** Fix #4 uses Zig std.crypto directly (no new dependencies)
5. **Web API:** Fix #7 adds URL mutation support via re-serialization

**No breaking changes** to existing APIs. **Build order** prioritizes allocator context (unblocks others) and async fetch (most complex). Total ~51 hours of implementation across 10 modified/new files.
