# Phase 6: Async Runtime & Fetch API

## Goal
Enable outbound HTTP requests from JS handlers, compatible with Node.js and Cloudflare Workers patterns.

## Target Compatibility

### Cloudflare Workers Pattern
```javascript
export default {
  async fetch(request) {
    const data = await fetch("https://api.example.com/data");
    return Response.json(await data.json());
  }
}
```

### Node.js Pattern
```javascript
const response = await fetch("https://api.example.com/data");
const json = await response.json();
```

## Architecture Options

### Option A: Full Async (Recommended)
**Description:** Implement event loop with V8 microtask integration.

**Components:**
1. Event loop in Zig (epoll/kqueue based)
2. Async HTTP client (using Zig's async or thread pool)
3. V8 Promise integration via microtask queue
4. async/await handler support

**Pros:**
- Full compatibility with Workers/Node.js
- Non-blocking, can handle concurrent requests
- Standard API

**Cons:**
- Most complex implementation
- Requires significant architecture changes

**Effort:** HIGH (2-3 weeks)

### Option B: Sync fetch() + Async Facade
**Description:** Synchronous HTTP under the hood, but exposed as Promise API.

```javascript
// User writes:
const data = await fetch(url);

// Runtime actually:
// 1. Blocks on HTTP request
// 2. Resolves Promise immediately with result
```

**Pros:**
- Compatible API surface
- Simpler implementation
- No event loop needed

**Cons:**
- Blocks server during outbound requests
- Bad for concurrent workloads
- Not truly async

**Effort:** MEDIUM (1 week)

### Option C: Hybrid with Thread Pool
**Description:** Sync API for simple cases, thread pool for parallel requests.

```javascript
// Sync (blocks, but simple):
const data = fetchSync(url);

// Async (thread pool, returns Promise):
const data = await fetch(url);
```

**Pros:**
- Both patterns available
- Thread pool prevents total blocking
- Incremental migration path

**Cons:**
- Two APIs to maintain
- Thread pool complexity
- Still not full event loop

**Effort:** MEDIUM-HIGH (1.5-2 weeks)

## Recommended Approach: Option A (Full Async)

### Rationale
1. **Compatibility** - True Workers/Node.js compatibility
2. **Performance** - Non-blocking allows concurrent requests
3. **Future-proof** - Foundation for timers, WebSockets, etc.

### Implementation Plan

#### Phase 6.1: Event Loop Foundation
- Implement basic event loop using Zig's async or manual epoll/kqueue
- Add timer primitives (needed for timeouts)
- Test with simple setTimeout/setInterval

#### Phase 6.2: V8 Microtask Integration
- Hook into V8's microtask queue
- Run pending microtasks after each event
- Implement Promise resolution from Zig

#### Phase 6.3: Async HTTP Client
- Build HTTP/1.1 client with connection pooling
- Non-blocking socket I/O
- Timeout and error handling
- Response streaming support

#### Phase 6.4: fetch() API
- Implement fetch() returning Promise
- Request/Response objects
- Headers, body, status
- Streaming responses (ReadableStream)

#### Phase 6.5: Handler Integration
- Support `async fetch(request)` handlers
- Wait for handler Promise to resolve
- Convert resolved Response to HTTP response

### Technical Details

#### Event Loop Design
```
┌─────────────────────────────────────────┐
│              Event Loop                  │
├──────────────┬──────────────────────────┤
│   I/O Poll   │   Timer Queue            │
│  (kqueue)    │   (min-heap)             │
├──────────────┴──────────────────────────┤
│          Microtask Queue                │
│    (V8 Promise callbacks)               │
├─────────────────────────────────────────┤
│          Request Handler                │
│    (runs until await/return)            │
└─────────────────────────────────────────┘
```

#### Request Flow
1. Accept HTTP connection
2. Parse request, create Request object
3. Enter V8 isolate, call handler
4. Handler runs until first await
5. V8 returns pending Promise
6. Event loop handles I/O (fetch, timers)
7. Microtasks run (Promise callbacks)
8. When handler Promise resolves, extract Response
9. Send HTTP response

#### Zig Async vs Thread Pool

**Zig Async:**
- Uses stackless coroutines
- Very lightweight
- Requires async-compatible code throughout

**Thread Pool:**
- Simpler to implement
- Heavier resource usage
- Easier to integrate with blocking V8 calls

**Recommendation:** Start with thread pool for fetch, migrate to Zig async later.

### File Changes

| File | Action |
|------|--------|
| `src/runtime/event_loop.zig` | Create - event loop |
| `src/runtime/promises.zig` | Create - Promise integration |
| `src/runtime/http_client.zig` | Create - async HTTP client |
| `src/api/fetch.zig` | Modify - real fetch() impl |
| `src/server/http.zig` | Modify - async handler support |
| `src/server/app.zig` | Modify - Promise-returning handlers |

### Dependencies
- Phase 5 (Hardening) must be complete
- V8 microtask API understanding
- Zig async/thread pool decision

### Milestones

1. **M1: setTimeout works** - Event loop + V8 microtasks
2. **M2: fetch() blocks** - Sync HTTP client with Promise facade
3. **M3: fetch() non-blocking** - Thread pool or async HTTP
4. **M4: Handler async** - async fetch(request) works end-to-end

### Success Criteria
1. `await fetch(url)` works in handlers
2. Multiple concurrent outbound requests
3. Timeout support for requests
4. Compatible with Cloudflare Workers examples
5. No server deadlock under load

## Fallback: Option B (Sync Facade)

If Option A proves too complex for v1.0, implement Option B:

1. Sync HTTP client in Zig
2. fetch() returns "already resolved" Promise
3. await works but blocks server
4. Document limitation clearly

This provides API compatibility without full async, allowing migration to Option A in v2.0.

## Questions to Decide

1. **Priority:** Full async now or sync facade for v1.0?
2. **HTTP Client:** Use existing Zig HTTP or build custom?
3. **Threading:** Thread pool for fetch or Zig async throughout?
4. **Scope:** Just fetch() or also setTimeout/setInterval?
