# Domain Pitfalls: NANO Backlog Cleanup Phase

**Project:** NANO Backlog Cleanup (7 fixes to async/stream/crypto APIs)
**Researched:** 2026-02-15
**Scope:** Common mistakes when implementing these specific fixes

---

## Critical Pitfalls

### Pitfall 1: V8 Persistent Handle Lifecycle Corruption

**What goes wrong:**
- Async callbacks (fetch, write promises) store `PromiseResolver` as persistent V8 handles
- If isolate is destroyed/reloaded before callback fires, accessing the handle crashes
- Common scenario: user edits app code, hot-reload destroys old isolate, pending fetch still tries to resolve

**Why it happens:**
- NANO reuses isolate across requests (optimization for app startup)
- Async operations may span across app reloads
- No cleanup of in-flight promises when app unloads
- No isolate validity checking in async callbacks

**Consequences:**
- SEGFAULT in `onFetchComplete` or timer callbacks
- Impossible to hot-reload while async operations are pending
- Users can't iterate rapidly during development

**Prevention:**

1. **Pair persistent handles with isolate reference:**
   ```zig
   const StoredPromiseResolver = struct {
       resolver: v8.Persistent(v8.PromiseResolver),
       isolate: v8.Isolate,
       isolate_id: u64,  // Generation ID for isolate
       created_at_ns: i128,
   };

   // On callback:
   if (self.isolate_id != current_isolate.generationId()) {
       // Isolate was replaced, skip this callback
       allocator.destroy(self);
       return;
   }
   ```

2. **Implement timeout for pending operations:**
   ```zig
   fn isExpired(self: @This(), timeout_ns: i128) bool {
       return (std.time.nanoTimestamp() - self.created_at_ns) > timeout_ns;
   }

   // In event loop tick:
   for (pending_operations.items) |op| {
       if (op.isExpired(30_000_000_000)) {  // 30s timeout
           op.reject("Operation timeout");
           pending_operations.remove(i);
       }
   }
   ```

3. **Disable async operations during app reload:**
   ```zig
   // In http.zig reloadConfig():
   server.draining = true;
   // Wait for pending operations to timeout/complete
   while (pending_ops.len > 0) {
       sleep(100ms);
   }
   server.draining = false;
   ```

**Detection:**
- Crash in `PromiseResolver.resolve()` or `PromiseResolver.reject()`
- SEGFAULT with stack trace pointing into V8 API
- Hot-reload causes SEGFAULT in async callback

---

### Pitfall 2: Request Allocator Use-After-Free

**What goes wrong:**
- Request allocator is freed after HTTP response sent (per request)
- If async callback fires AFTER response is sent, callback tries to use freed allocator
- Scenario: fetch() takes 10 seconds, but user closes connection after 1s, allocator freed, callback tries to allocate

**Why it happens:**
- Request lifetime = response sent, not when callbacks complete
- Allocator is freed in `http.zig` after sending response
- Callbacks don't validate allocator is still alive
- No "request context" that survives beyond response

**Consequences:**
- Use-after-free → memory corruption → crashes (may be delayed, hard to debug)
- Sporadic crashes on slow network requests
- Hard to reproduce because timing-dependent

**Prevention:**

1. **Extend allocator lifetime to include all pending async operations:**
   ```zig
   pub const RequestContext = struct {
       allocator: std.mem.Allocator,
       pending_operations: u32 = 0,
       freed: bool = false,

       pub fn increment(self: *@This()) void {
           self.pending_operations += 1;
       }

       pub fn decrement(self: *@This()) void {
           self.pending_operations -= 1;
           if (self.pending_operations == 0 and self.freed) {
               allocator.destroy(self);
           }
       }

       pub fn markForDeletion(self: *@This()) void {
           self.freed = true;
           if (self.pending_operations == 0) {
               allocator.destroy(self);
           }
       }
   };
   ```

2. **Attach request context to each async operation:**
   ```zig
   // In fetchCallback:
   request_context.increment();
   defer request_context.decrement();

   loop.addSocketOp(..., request_context, onFetchComplete);
   ```

3. **In callbacks, check if context is valid:**
   ```zig
   fn onFetchComplete(ctx: *RequestContext, result: SocketOpResult) void {
       defer ctx.decrement();

       if (ctx.freed) {
           // Request already completed, ignore this result
           return;
       }
       // Safe to use ctx.allocator now
   }
   ```

**Detection:**
- Crash in `allocator.alloc()` or `allocator.free()` from async callback
- `DEBUG: heap corruption` messages from allocator
- Valgrind/ASAN: "use-after-free" error

---

### Pitfall 3: PromiseResolver Lifecycle — Promise Unresolved on GC

**What goes wrong:**
- Promise resolver stored in JS object (e.g., `_pendingResolves` array)
- Promise is never resolved or rejected
- If JS object is GC'd, the unresolved promise leaks
- Scenario: stream is GC'd while writes are pending, promises unresolved forever

**Why it happens:**
- No cleanup callback when JS object is GC'd
- Promise resolvers don't have automatic cleanup
- Forgetting to resolve promises in error paths (e.g., socket timeout)

**Consequences:**
- Memory leak of persistent handles (1-2KB per unresolved promise)
- With 1000 pending writes, 2MB+ leaked
- Application gradually accumulates persistent handle leak
- Eventually hits V8 memory limit

**Prevention:**

1. **Use weak references with cleanup callbacks:**
   ```zig
   // In WritableStream constructor:
   const weak_stream = v8.WeakValueReference.init(isolate, ctx.this.toValue());
   weak_stream.setCallback(onStreamGC);

   fn onStreamGC(weak_ref: *v8.WeakValueReference) void {
       // Stream was GC'd
       const stream_ptr: *StreamData = weak_ref.getUserData();
       // Clean up pending resolvers
       for (stream_ptr.pending_resolvers.items) |resolver| {
           resolver.reject("Stream was garbage collected");
           resolver.deinit();
       }
       allocator.destroy(stream_ptr);
   }
   ```

2. **Maintain an audit log of all unresolved promises:**
   ```zig
   var global_unresolved_promises: std.ArrayList(PromiseInfo) = ...;

   fn trackPromise(resolver: v8.Persistent(v8.PromiseResolver)) void {
       global_unresolved_promises.append(.{
           .resolver = resolver,
           .created_at = std.time.nanoTimestamp(),
           .source = @src(),
       }) catch {};
   }

   fn untrackPromise(resolver: v8.Persistent(v8.PromiseResolver)) void {
       var found = false;
       for (global_unresolved_promises.items, 0..) |promise, i| {
           if (promise.resolver.equals(resolver)) {
               _ = global_unresolved_promises.orderedRemove(i);
               found = true;
               break;
           }
       }
       if (!found) {
           std.debug.print("WARNING: Promise {p} was never tracked\n", .{resolver});
       }
   }

   // Periodically log unresolved promises older than 10 seconds:
   fn auditUnresolvedPromises() void {
       const now = std.time.nanoTimestamp();
       for (global_unresolved_promises.items) |promise| {
           if ((now - promise.created_at) > 10_000_000_000) {
               std.debug.print("WARNING: Unresolved promise from {s}:{d} for {d}ms\n",
                   .{ promise.source.file, promise.source.line, (now - promise.created_at) / 1_000_000 });
           }
       }
   }
   ```

3. **Resolve all promises in error paths:**
   ```zig
   fn writerWrite(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
       const ctx = js.CallbackContext.init(raw_info);
       const write_resolver = v8.PromiseResolver.init(ctx.context);

       // Create persistent handle
       const persistent = persistent_allocator.create(...) catch {
           // ERROR: Can't allocate persistent handle
           // Must resolve promise synchronously with error
           _ = write_resolver.reject(ctx.context, js.string(ctx.isolate, "OOM").toValue());
           js.ret(ctx, write_resolver.getPromise());
           return;
       };

       // ... rest of function, with early returns that resolve promise
   }
   ```

**Detection:**
- Memory growth in persistent handle count (V8 heap stats)
- Valgrind/ASAN: persistent handle leaks
- Manual audit: search for unresolved promises > 10s old

---

### Pitfall 4: Socket Operation Backlog Unbounded Growth

**What goes wrong:**
- Socket operations are queued in event loop but never complete (network slow, downstream blocked)
- Queue grows without bound: 1000, 10,000, 100,000 pending operations
- Each operation holds persistent handle, allocator context, buffers
- Eventually OOMs or hits operation count limit

**Why it happens:**
- No cap on pending socket operations
- No timeout for slow/stuck operations
- No per-connection limit
- Exponential backoff not implemented

**Consequences:**
- Memory OOM
- V8 heap exhaustion
- Latency spike for new operations (queue traversal)
- Can't gracefully degrade

**Prevention:**

1. **Implement operation queue limits:**
   ```zig
   const MAX_PENDING_OPS = 1000;
   const OP_TIMEOUT_MS = 30_000;

   fn addSocketOp(self: *EventLoop, ...) !u32 {
       if (self.pending_ops.items.len >= MAX_PENDING_OPS) {
           return error.OperationQueueFull;
       }

       const op = SocketOp{...};
       self.pending_ops.append(op) catch return error.OOM;
       return op.id;
   }
   ```

2. **Return 503 when queue is full:**
   ```zig
   // In fetchCallback:
   loop.addSocketOp(...) catch |err| {
       if (err == error.OperationQueueFull) {
           _ = resolver.reject(ctx.context, js.string(isolate, "Server busy").toValue());
           js.ret(ctx, resolver.getPromise());
           return;
       }
       js.throw(isolate, "Failed to queue operation");
       return;
   };
   ```

3. **Implement per-operation timeout:**
   ```zig
   pub const SocketOp = struct {
       id: u32,
       created_at_ns: i128,
       timeout_ns: i128 = 30_000_000_000, // 30s

       fn isExpired(self: @This()) bool {
           return (std.time.nanoTimestamp() - self.created_at_ns) > self.timeout_ns;
       }
   };

   pub fn tick(self: *EventLoop) !void {
       _ = self.loop.run(.no_wait) catch {};

       // Timeout expired operations
       var i: usize = 0;
       while (i < self.pending_ops.items.len) {
           if (self.pending_ops.items[i].isExpired()) {
               const op = self.pending_ops.orderedRemove(i);
               op.resolver.reject(ctx.context, js.string(isolate, "Operation timeout").toValue());
               op.resolver.deinit();
               persistent_allocator.destroy(&op);
           } else {
               i += 1;
           }
       }
   }
   ```

4. **Monitor queue depth in metrics:**
   ```zig
   pub const Metrics = struct {
       max_queue_depth: usize = 0,

       pub fn recordQueueDepth(self: *Metrics, depth: usize) void {
           self.max_queue_depth = @max(self.max_queue_depth, depth);
       }
   };

   // In /metrics endpoint:
   // gauge_socket_queue_depth: {depth}
   // gauge_socket_queue_max: {max_depth}
   ```

**Detection:**
- Metrics: gauge_socket_queue_depth trending upward
- Manual: inspect pending_ops list size
- Load test: add 1000 slow requests, check memory

---

## Moderate Pitfalls

### Pitfall 5: Promise Resolution from Wrong Isolate/Context

**What goes wrong:**
- Async callback fires in different context than promise was created
- Calling `resolver.resolve()` from wrong isolate causes crash or undefined behavior
- Scenario: fetch callback from event loop thread, but isolate is in different thread

**Why it happens:**
- NANO is single-threaded, but xev socket operations might fire from different stack
- No validation that resolver matches current isolate/context
- V8 API requires correct isolate/context for resolver operations

**Prevention:**

1. **Validate isolate before using resolver:**
   ```zig
   fn onFetchComplete(resolver_ptr: *StoredPromiseResolver, result: SocketOpResult) void {
       // Ensure we're in the right isolate
       const expected_isolate = resolver_ptr.isolate;
       const current_isolate = v8.Isolate.getCurrent();

       if (expected_isolate.handle != current_isolate.handle) {
           std.debug.print("ERROR: Promise callback in wrong isolate\n", .{});
           return; // Skip this callback
       }

       expected_isolate.enter();
       defer expected_isolate.exit();

       // Now safe to use resolver
       _ = resolver_ptr.resolver.resolve(...);
   }
   ```

2. **Store context with resolver, re-enter it:**
   ```zig
   const StoredPromiseResolver = struct {
       resolver: v8.Persistent(v8.PromiseResolver),
       context: v8.Persistent(v8.Context),
       isolate: v8.Isolate,
   };

   fn onFetchComplete(resolver_ptr: *StoredPromiseResolver, result: SocketOpResult) void {
       const isolate = resolver_ptr.isolate;
       isolate.enter();
       defer isolate.exit();

       const context = resolver_ptr.context.castToContext();
       context.enter();
       defer context.exit();

       _ = resolver_ptr.resolver.resolve(context, ...);
   }
   ```

**Detection:**
- Crash in `v8::Promise::Resolver::Resolve()` with specific isolate handle mismatch
- V8 assertion: "Persistent handle used in wrong isolate"

---

### Pitfall 6: Stream Queue Memory Unbounded

**What goes wrong:**
- ReadableStream or WritableStream queues chunks without limit
- Source produces chunks faster than consumer reads
- Queue grows: 1000 chunks, 10,000 chunks → OOM

**Why it happens:**
- Queue is just a JS array, no size limit enforced
- highWaterMark is advisory, not enforced
- No backpressure from reader to source
- Consumer slow (network I/O, CPU), producer fast (memory)

**Consequences:**
- OOM crash
- Latency spike (large queue traversal)
- Application hangs

**Prevention:**

1. **Enforce queue size limit:**
   ```zig
   const max_queue_size_bytes = 64 * 1024 * 1024; // 64MB

   fn controllerEnqueue(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
       const ctx = js.CallbackContext.init(raw_info);
       const chunk = ctx.arg(0);

       const stream = js.getProp(ctx.this, ctx.context, ctx.isolate, "_stream");
       const queue = js.getProp(stream, ctx.context, ctx.isolate, "_queue");
       const queue_byte_size = js.getProp(stream, ctx.context, ctx.isolate, "_queueByteSize");

       const chunk_size = getChunkSize(chunk);
       const current_size: u64 = @intFromFloat(queue_byte_size.toF64(ctx.context) catch 0);

       if (current_size + chunk_size > max_queue_size_bytes) {
           js.throw(ctx.isolate, "Stream queue size exceeded");
           return;
       }

       // ... normal enqueue
   }
   ```

2. **Track queue statistics:**
   ```zig
   pub const StreamMetrics = struct {
       max_queue_size_bytes: u64 = 0,
       max_queue_length: u32 = 0,

       pub fn recordQueue(self: *StreamMetrics, size: u64, len: u32) void {
           self.max_queue_size_bytes = @max(self.max_queue_size_bytes, size);
           self.max_queue_length = @max(self.max_queue_length, len);
       }
   };
   ```

**Detection:**
- Metrics: max_queue_size_bytes trending toward limit
- V8 OOM error: "JavaScript heap out of memory"
- Load test: slow consumer, fast producer

---

### Pitfall 7: Crypto Key Format Confusion

**What goes wrong:**
- User provides key in wrong format (PEM instead of raw, etc.)
- AES-GCM expects 16/24/32 byte key, but gets key object
- No validation → garbage encryption
- Scenario: user passes JWK object, code treats it as raw bytes

**Why it happens:**
- Multiple key formats: raw, JWK, PEM, PKCS8
- Conversion between formats is non-obvious
- No error message if key format is wrong
- Partial implementation of key parsing

**Consequences:**
- Silent encryption failure (garbled output)
- Security issue: key treated as wrong length
- Hard to debug (everything "works" but data is corrupt)

**Prevention:**

1. **Validate key format and size explicitly:**
   ```zig
   fn extractAESKey(key_arg: v8.Value, ctx: js.CallbackContext) ![]const u8 {
       // Expect ArrayBuffer with exactly 16, 24, or 32 bytes
       if (!key_arg.isArrayBuffer()) {
           js.throw(ctx.isolate, "AES key must be an ArrayBuffer");
           return error.InvalidKeyFormat;
       }

       const ab = js.asArrayBuffer(key_arg);
       const key_len = ab.getByteLength();

       if (key_len != 16 and key_len != 24 and key_len != 32) {
           var error_buf: [128]u8 = undefined;
           const error_msg = std.fmt.bufPrint(&error_buf,
               "AES key must be 128, 192, or 256 bits ({} bytes), got {}",
               .{ key_len * 8, key_len }
           ) catch "AES key length invalid";
           js.throw(ctx.isolate, error_msg);
           return error.InvalidKeySize;
       }

       const backing = v8.BackingStore.sharedPtrGet(&ab.getBackingStore());
       const data = backing.getData() orelse return error.NoBackingStore;
       return @as([*]const u8, @ptrCast(data))[0..key_len];
   }
   ```

2. **Provide clear error messages:**
   ```zig
   // Instead of: "invalid key"
   // Say: "AES-256 requires 32-byte key, got 16 bytes. Expected ArrayBuffer with 32 bytes."
   ```

3. **Add test vectors:**
   ```zig
   // Test encrypt/decrypt with known vectors from NIST
   test "AES-256-GCM with NIST test vector" {
       const key = [_]u8{ ... };  // Known key
       const plaintext = [_]u8{ ... };  // Known plaintext
       const ciphertext = [_]u8{ ... };  // Expected ciphertext

       var output: [32]u8 = undefined;
       aes256.encrypt(&output, plaintext, key);
       try std.testing.expectEqualSlices(u8, &ciphertext, &output);
   }
   ```

**Detection:**
- Encryption output doesn't match expected (use NIST test vectors)
- Decryption produces garbage instead of plaintext
- User reports: "my crypto doesn't work"

---

## Minor Pitfalls

### Pitfall 8: URL Setter Protocol Validation

**What goes wrong:**
- User sets `url.protocol = "invalid://"`
- No validation → invalid URL stored
- User tries to use URL later → undefined behavior

**Prevention:**
- Validate protocol format (alphanumeric + colon)
- Silently ignore invalid protocols (per WHATWG spec)

---

### Pitfall 9: tee() Branch Deletion

**What goes wrong:**
- User creates tee(), reads from branch 1, discards branch 2
- Branch 2 is GC'd, but source still holds reference
- Source tries to enqueue to deleted branch → crash or memory leak

**Prevention:**
- Use weak references for branches
- Check validity before enqueueing
- Auto-remove invalid branches from source

---

### Pitfall 10: fetch() Redirect Loop

**What goes wrong:**
- redirect_url → redirect_url → ... (infinite loop)
- fetch() follows redirects, but doesn't track redirect count
- Server redirects forever, fetch() hangs

**Prevention:**
- Limit redirect count (e.g., max 5)
- Reject if limit exceeded
- Return early if redirect_url == request_url

---

## Phase-Specific Warnings

| Phase | Likely Pitfall | Mitigation |
|-------|---|---|
| #1: Allocators | Use-after-free (Pitfall 2) | Ref-counting on request context |
| #2: Async Fetch | Handle lifecycle (Pitfall 1), Socket backlog (Pitfall 4) | Isolate + context tracking, queue limits |
| #3: WritableStream Async | Unresolved promises (Pitfall 3) | Weak refs, cleanup callbacks |
| #4: Crypto | Key format confusion (Pitfall 7) | Explicit validation, test vectors |
| #5: tee() | Branch deletion (Pitfall 9) | Weak references |
| #6: structuredClone | Circular references | Depth limit or reference tracking |
| #7: URL Setters | Protocol validation (Pitfall 8) | Spec-compliant validation |

---

## Testing Pitfall Scenarios

### Test 1: Hot Reload with Pending Fetch
```zig
test "hot reload while fetch is pending" {
    // Start fetch that takes 10 seconds
    const promise = fetch("http://slow.example.com");
    // Hot-reload app (destroy isolate)
    app.reload();
    // Check: no SEGFAULT, promise rejects with error
    const rejected = await promiseRejectReason(promise);
    expect(rejected).toContain("Isolate destroyed");
}
```

### Test 2: Socket Queue Exhaustion
```zig
test "socket queue fills up" {
    // Start 1000 slow fetches
    for (0..1000) {
        fetch("http://slow.example.com/forever");
    }
    // 1001st fetch should return 503 Service Unavailable
    const result = fetch("http://example.com");
    expect(result.status).toBe(503);
    expect(result.body).toContain("Server busy");
}
```

### Test 3: Unresolved Promise Leak
```zig
test "unresolved promise leak detection" {
    // Create 100 write promises that never resolve
    for (0..100) {
        writer.write(data);  // Promise created but not awaited
    }
    // Run GC
    isolate.lowMemoryNotification();
    // Check: audit log reports 100 unresolved promises
    const unresolved = auditUnresolvedPromises();
    expect(unresolved.len).toBe(100);
}
```

### Test 4: Stream Queue Overflow
```zig
test "stream queue size limit enforced" {
    const source = new ReadableStream({
        start(controller) {
            // Try to enqueue 100MB of data
            for (0..10_000) {
                const chunk = new Uint8Array(10_240);  // 10KB
                controller.enqueue(chunk);  // Should fail after ~64MB
            }
        }
    });
}
```

---

## Conclusion

These 10 pitfalls represent the most likely failure modes when implementing the 7 backlog fixes. **Prioritize testing pitfalls 1-4** (critical), then 5-7 (moderate), then 8-10 (nice-to-have).

The common thread: **Always validate that persistent handles, allocators, and promises are alive before using them.**
