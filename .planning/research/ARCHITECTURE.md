# Architecture Research: JavaScript Isolate Runtime

## Core Components

| Component | Responsibility | Isolation Level |
|-----------|---------------|-----------------|
| **Isolate Manager** | V8 isolate lifecycle (create, enter, exit, dispose) | Per-process |
| **Context Factory** | Creates execution contexts within isolates | Per-app |
| **Snapshot Cache** | Precompiled V8 snapshots for fast cold starts | Shared |
| **I/O Bridge** | Maps JS APIs (fetch, timers) to native calls | Per-isolate |
| **Request Router** | Routes HTTP requests to correct app/isolate | Per-process |
| **Resource Limiter** | Enforces CPU time, memory, I/O quotas | Per-isolate |
| **Event Loop** | Polls async operations, drives execution | Per-isolate |

### Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                      NANO Process                           │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   App A     │    │   App B     │    │   App C     │     │
│  │  (Isolate)  │    │  (Isolate)  │    │  (Isolate)  │     │
│  │  ┌───────┐  │    │  ┌───────┐  │    │  ┌───────┐  │     │
│  │  │Context│  │    │  │Context│  │    │  │Context│  │     │
│  │  └───────┘  │    │  └───────┘  │    │  └───────┘  │     │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘     │
│         │                  │                  │             │
│  ┌──────┴──────────────────┴──────────────────┴──────┐     │
│  │                    I/O Bridge                      │     │
│  │         (fetch, timers, console, crypto)           │     │
│  └──────────────────────┬────────────────────────────┘     │
│                         │                                   │
│  ┌──────────────────────┴────────────────────────────┐     │
│  │              Native Event Loop (Zig)               │     │
│  │         (epoll/kqueue/io_uring)                    │     │
│  └────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

## Request Lifecycle

**1. HTTP Request Arrives**
```
Client → TCP Accept → Parse Headers → Extract Host/Path
```

**2. Route to App**
```
Host header → App Registry lookup → Get/Create Isolate
```

**3. Isolate Acquisition**
```
IF warm isolate available:
  → Enter existing isolate (< 0.1ms)
ELSE IF snapshot exists:
  → Create from snapshot (< 2ms)
ELSE:
  → Cold create isolate (40-100ms) ← avoid this path
```

**4. Execute JavaScript**
```
Create HandleScope → Get Context → Create Request object →
Call fetch handler → Await Response → Extract body
```

**5. Return Response**
```
Response object → Extract status/headers/body →
Write HTTP response → Release isolate back to pool
```

**6. Cleanup**
```
Arena allocator reset (instant) → Isolate returned to pool
```

## Isolation Model

### What's SHARED (across all isolates)

| Resource | Rationale |
|----------|-----------|
| V8 platform instance | One per process, thread-safe |
| Snapshot blob | Read-only, same for all apps |
| Native event loop | Single-threaded, multiplexed |
| HTTP server socket | Routes to correct isolate |

### What's ISOLATED (per app)

| Resource | Mechanism |
|----------|-----------|
| V8 Isolate | Complete JS heap isolation |
| Global object | Fresh globalThis per context |
| Memory limits | `SetMaxOldGenerationSize()` |
| CPU time | Watchdog timer, `TerminateExecution()` |
| File handles | None exposed (fetch-only I/O) |
| Environment vars | Not exposed by default |

### Security Boundaries

```
┌─────────────────────────────────────────┐
│           Process Boundary              │
│  ┌───────────────────────────────────┐  │
│  │        V8 Isolate Boundary        │  │
│  │  ┌─────────────────────────────┐  │  │
│  │  │    Context Boundary         │  │  │
│  │  │    (globalThis, builtins)   │  │  │
│  │  └─────────────────────────────┘  │  │
│  │  - Heap is isolated               │  │
│  │  - No cross-isolate references    │  │
│  │  - No shared ArrayBuffers         │  │
│  └───────────────────────────────────┘  │
│                                         │
│  Native code has full process access    │
│  → Must validate all JS ↔ native calls  │
└─────────────────────────────────────────┘
```

## V8 Snapshot System

### How Snapshots Enable Fast Cold Starts

**Without snapshots:**
```
Create Isolate → Initialize builtins → Parse globals →
Compile standard library → Ready
Total: 40-100ms
```

**With snapshots:**
```
Create Isolate from blob → Ready
Total: 1-2ms
```

### Snapshot Creation (build time)

```cpp
// Simplified snapshot creation
v8::SnapshotCreator creator;
v8::Isolate* isolate = creator.GetIsolate();
{
  v8::HandleScope scope(isolate);
  v8::Local<v8::Context> context = v8::Context::New(isolate);

  // Add all globals: fetch, Request, Response, console, etc.
  InstallWorkerAPIs(context);

  creator.SetDefaultContext(context);
}
v8::StartupData blob = creator.CreateBlob(
  v8::SnapshotCreator::FunctionCodeHandling::kClear
);
// Write blob to disk
```

### Snapshot Usage (runtime)

```cpp
// Load from snapshot
v8::StartupData blob = LoadFromDisk("nano.snapshot");
v8::Isolate::CreateParams params;
params.snapshot_blob = &blob;
v8::Isolate* isolate = v8::Isolate::New(params);
// Isolate ready with all APIs pre-installed
```

### What Goes in the Snapshot

| Include | Exclude |
|---------|---------|
| Global object template | User code |
| Built-in APIs (fetch, crypto) | Request-specific data |
| Compiled helper functions | Mutable state |
| Standard library polyfills | External bindings |

## Suggested Build Order

### Phase 1: V8 Integration Foundation
**Goal:** Hello World from V8 in Zig

1. Build V8 with embedding flags
2. Create C shim for V8 C++ → Zig
3. Basic isolate lifecycle (new, enter, exit, dispose)
4. Execute simple JavaScript, get result
5. Arena allocator integration

**Milestone:** `nano eval "1 + 1"` returns `2`

### Phase 2: API Surface
**Goal:** Workers-compatible globals

1. Implement `console.log()` (validate binding pattern)
2. Implement `Request` and `Response` classes
3. Implement `Headers` class
4. Implement `fetch()` with native HTTP client
5. Implement timers (`setTimeout`, `setInterval`)

**Milestone:** Run simple Workers script that fetches URL

### Phase 3: HTTP Server + Routing
**Goal:** Accept HTTP requests, route to apps

1. Zig HTTP server (std.http or custom)
2. App registry (folder path → app config)
3. Request routing by host/path
4. Response writing back to client

**Milestone:** Multiple apps on different ports

### Phase 4: Snapshots + Cold Start
**Goal:** Sub-5ms cold starts

1. Snapshot creation tooling
2. Load isolates from snapshot
3. Measure and optimize cold start
4. Isolate pool (warm isolates)

**Milestone:** p99 cold start < 5ms

### Phase 5: Resource Limits + Observability
**Goal:** Production-ready isolation

1. CPU time limits (watchdog)
2. Memory limits per isolate
3. Structured logging per app
4. Prometheus metrics endpoint

**Milestone:** Can't crash host with runaway script

## Reference Implementation Notes

### From Cloudflare workerd

- **Isolate reuse:** Keep isolates warm between requests to same app
- **Startup snapshots:** Include all APIs in snapshot, not just V8 builtins
- **Memory limits:** 128MB default, configurable per worker
- **CPU limits:** 50ms default for free tier, configurable
- **Eviction:** LRU eviction when memory pressure detected

### From Deno

- **Ops system:** Clean pattern for JS → native calls (sync and async)
- **Resource table:** Integer handles for external resources (like file descriptors)
- **Module loading:** Import maps and URL-based module resolution
- **Event loop:** Poll-based, integrates with tokio (Rust) / could use io_uring

### From Bun (JSC, but patterns apply)

- **Zig integration:** Proves Zig can embed a JS engine effectively
- **Arena allocators:** Per-request arenas for zero-overhead cleanup
- **Native HTTP:** Direct integration beats libuv/libevent

## Open Questions for Implementation

1. **Isolate pooling strategy:** How many warm isolates per app? LRU vs FIFO?
2. **Snapshot per-app or global?** Single snapshot with all APIs vs per-app customization?
3. **Module resolution:** URL-based (Deno-style) or package.json (Node-style)?
4. **io_uring integration:** Worth the complexity for Linux-only optimization?
5. **Hot reload:** How to update app code without full process restart?
