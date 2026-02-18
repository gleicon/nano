---
title: Event Loop & Async Model
description: How NANO's event loop coordinates timers, fetch, streams, and Promises
sidebar:
  order: 8
---

NANO uses a cooperative polling event loop built on [libxev](https://github.com/Vexu/libxev) to coordinate all async operations: timers, fetch requests, WritableStream sinks, and Promise resolution. Understanding the event loop is key to writing correct async handlers and diagnosing timeout issues.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    HTTP Request                          │
│                         │                               │
│                    handler(req)                          │
│                         │                               │
│                  returns Promise?                        │
│                    ╱         ╲                           │
│                 no             yes                       │
│                  │              │                        │
│           return Response   ┌───▼──────────────────────┐ │
│                             │   Promise Wait Loop      │ │
│                             │                          │ │
│                             │  ┌─── xev tick ───────┐  │ │
│                             │  │  timer callbacks    │  │ │
│                             │  │  fetch completions  │  │ │
│                             │  └────────────────────┘  │ │
│                             │  ┌─── Zig polling ────┐  │ │
│                             │  │  async sink polls   │  │ │
│                             │  └────────────────────┘  │ │
│                             │  ┌─── V8 ─────────────┐  │ │
│                             │  │  microtask checkpoint│ │ │
│                             │  └────────────────────┘  │ │
│                             │         │                │ │
│                             │    sleep 1ms             │ │
│                             │    (yield to workers)    │ │
│                             │         │                │ │
│                             │   promise resolved?      │ │
│                             │    ╱           ╲         │ │
│                             │  no          yes         │ │
│                             │   │           │          │ │
│                             │  loop     extract        │ │
│                             │  (max     Response       │ │
│                             │  10000)                  │ │
│                             └──────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### Components

| Layer | File | Role |
|-------|------|------|
| **xev Loop** | `src/runtime/event_loop.zig` | Timer scheduling, tick dispatch, fetch queue |
| **Timers** | `src/runtime/timers.zig` | `setTimeout`/`setInterval` via Persistent callbacks |
| **Async Fetch** | `src/api/fetch.zig` | Thread pool workers, resolver registry |
| **Async Sinks** | `src/api/writable_stream.zig` | Promise-returning `write()` detection + polling |
| **Wait Loop** | `src/server/app.zig` | Coordinates all subsystems per request |
| **Between Requests** | `src/server/http.zig` | Ticks event loop, fires stale callbacks |

## The Promise Wait Loop

When a handler returns a Promise (i.e., an `async` handler), NANO enters a polling loop that drives all async subsystems until the Promise resolves, rejects, or times out.

Each iteration does this, in order:

1. **xev tick** — `loop.run(.no_wait)` processes all ready events (timer expirations, I/O completions)
2. **Timer callbacks** — fires any `setTimeout`/`setInterval` callbacks whose timers expired
3. **Fetch completions** — drains the completed-fetch queue, resolves/rejects fetch Promises
4. **Async sink polls** — checks each pending WritableStream sink Promise for state change
5. **Microtask checkpoint** — runs V8's microtask queue (`.then()` chains, `Promise.resolve()` continuations)
6. **Sleep 1ms** — yields CPU so worker threads (fetch) can complete

```javascript
// This handler exercises all subsystems in one request:
export default {
  async fetch(request) {
    // 1. Timer fires during fetch wait (step 2)
    const timerResult = await new Promise(resolve =>
      setTimeout(() => resolve("timer-ok"), 20)
    );

    // 2. Fetch runs on worker thread (steps 3 + 6)
    const resp = await fetch("https://api.example.com/data");
    const data = await resp.json();

    // 3. Microtask resolves immediately (step 5)
    const val = await Promise.resolve(42);

    return Response.json({ timerResult, data, val });
  }
};
```

### Timeout Behavior

The loop runs a maximum of **10,000 iterations** with 1ms sleep each, giving roughly a **10-second timeout**. If the Promise is still pending after 10,000 iterations, NANO returns:

```
HTTP 500: "Promise did not resolve in time"
```

This protects the server from handlers that accidentally create Promises that never resolve.

### Between Requests

After each HTTP response is sent, `http.zig` also ticks the event loop once to fire any stale timer or fetch callbacks that completed during response serialization. This ensures `setInterval` callbacks don't drift.

## How Async Fetch Works

`fetch()` uses a **thread pool model**: each call spawns a detached `std.Thread` that performs blocking HTTP I/O, then posts results back to the main thread.

```
  Main Thread                    Worker Thread
  ───────────                    ─────────────
  fetchCallback()
    │
    ├─ create PromiseResolver
    ├─ store Persistent handle → resolver registry (mutex)
    ├─ heap-copy url, method, body
    ├─ spawn std.Thread ──────────► fetchWorker()
    ├─ return unresolved Promise       │
    │                                  ├─ doFetch() (blocking HTTP)
    │   ... other work ...             │
    │                                  ├─ build CompletedFetch
    │                                  └─ addCompletedFetch() ◄── mutex
    │
    ├─ resolveCompletedFetches()
    │     drain queue
    │     take resolver by ID
    │     resolver.resolve(Response) or resolver.reject(Error)
    └─ microtask checkpoint
```

**Key design decisions:**

- **Thread pool over xev sockets** — simpler than a state-machine HTTP client, avoids unvalidated xev.Tcp API
- **Persistent handles** — V8 garbage-collects local handles after `HandleScope` exits. `v8.Persistent(PromiseResolver)` keeps the resolver alive across event loop ticks
- **Resolver registry** — maps unique `usize` IDs to persistent resolvers, protected by `std.Thread.Mutex`
- **Atomic pending count** — `pending_fetch_count` tracks in-flight fetches so `hasPendingWork()` keeps the loop alive

### Sync Fallback

In eval/REPL mode (`nano eval`, `nano repl`), there's no event loop. `fetch()` detects `global_event_loop == null` and falls back to synchronous blocking HTTP.

### SSRF Protection

`fetch()` blocks requests to private/loopback addresses:
- `127.0.0.0/8`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`
- `169.254.169.254` (cloud metadata)
- `localhost` hostnames

```javascript
// Blocked — returns rejected Promise
await fetch("http://127.0.0.1:8080/internal"); // "BlockedHost"
await fetch("http://169.254.169.254/metadata"); // "BlockedHost"
```

## How Async WritableStream Sinks Work

When a `WritableStream`'s `write()` sink returns a Promise, NANO detects it and defers the write promise resolution until the sink promise settles.

```
  processWriteQueue()
    │
    ├─ dequeue chunk from _queue
    ├─ call write_fn.call(chunk)
    ├─ check result.isPromise()
    │     ╱         ╲
    │   no           yes
    │    │            │
    │  resolve      store _pendingSinkPromise on stream
    │  write        store _pendingWriteResolver
    │  promise      register in pending_async_streams list
    │  immediately  (leave _writing = true)
    │                │
    │    ◄───────────┘
    │
    │  ... event loop ticks ...
    │
    ├─ processPendingAsyncSinks()
    │     for each pending stream:
    │       check _pendingSinkPromise.getState()
    │       kPending → skip
    │       kFulfilled → resolve write promise, dequeue, continue queue
    │       kRejected → reject write promise, error the stream
    └─
```

This means async sinks correctly sequence writes:

```javascript
const chunks = [];
const stream = new WritableStream({
  write(chunk) {
    return new Promise(resolve => {
      setTimeout(() => { chunks.push(chunk); resolve(); }, 10);
    });
  }
});

const writer = stream.getWriter();
await writer.write('a');
await writer.write('b');
await writer.write('c');
// chunks === ['a', 'b', 'c'] — correct order, each waits for previous
```

## Timer Internals

Timers use xev's kernel-level timer facility. When a timer fires, xev calls back into Zig, which queues a `TimerCallback` struct. The main thread then executes the stored V8 callback.

**Critical implementation detail:** xev timers must **never** use `.rearm` with `run(.no_wait)`. Rearming re-inserts the timer at the same absolute past time, causing `run(.no_wait)` to fire it infinitely in a tight loop. Instead, NANO always calls `timer.run()` with a fresh delay to compute a new absolute target time.

```javascript
// setTimeout: fires once, Persistent callback freed after execution
setTimeout(() => console.log("once"), 100);

// setInterval: fires repeatedly, timer rescheduled with fresh delay
const id = setInterval(() => console.log("tick"), 1000);
clearInterval(id); // marks timer inactive, frees Persistent handle
```

### Timer Ordering

Timers with shorter delays fire before longer ones, as expected:

```javascript
const order = [];
setTimeout(() => order.push('a'), 10);  // fires first
setTimeout(() => order.push('b'), 20);  // fires second
setTimeout(() => order.push('c'), 30);  // fires third
// order === ['a', 'b', 'c']
```

### Timer Precision

Timer delays are approximate. The event loop polls with `run(.no_wait)` which processes all ready events in a batch. Combined with the 1ms sleep per iteration, effective resolution is ~1-2ms. Sub-millisecond timers are not meaningful.

`Date.now()` precision in embedded V8 may not reflect real wall-clock time accurately — a 50ms timer may show elapsed time of 1ms when measured with `Date.now()`. The timer callback itself fires correctly; only the timestamp measurement is imprecise.

## Known Behaviors and Edge Cases

These behaviors are verified by the regression test suite in `test/event-loop-test/`.

### Verified Working

| Behavior | Test | Notes |
|----------|------|-------|
| setTimeout fires callback | `/test-timer-basic` | Verified via `fired` flag, not elapsed time |
| Timer ordering preserved | `/test-timer-ordering` | 10ms < 20ms < 30ms |
| Promise.resolve chains | `/test-promise-basic` | `.then()` chains work |
| Promise.all with timers | `/test-promise-all` | Mixed sync + timer promises |
| Deep promise chains (100) | `/test-deep-promise-chain` | 100-deep `.then()` chain resolves correctly |
| Async fetch non-blocking | `/test-async-fetch` | Timer fires while fetch in-flight |
| Concurrent fetches | `/test-concurrent-fetch` | Two fetches resolve independently |
| fetch().json() | `/test-fetch-json` | JSON parsing works |
| fetch error handling | `/test-fetch-error` | Invalid host rejects with "ConnectionFailed" |
| WritableStream sync sink | `/test-writable-sync` | Sync write() works as before |
| WritableStream async sink | `/test-writable-async` | Promise-returning write() correctly sequenced |
| WritableStream error | `/test-writable-error` | Thrown error rejects write promise |
| 50 sync writes | `/test-writable-many-sync` | Bulk sync writes in order |
| 10 async writes | `/test-writable-many-async` | Bulk async writes in order |
| ReadableStream pull() | `/test-readable-basic` | Pull-based stream works |
| 1MB Blob round-trip | `/test-blob-large` | No truncation (was 64KB limit) |
| 50KB base64 round-trip | `/test-encoding-large` | atob/btoa handle large strings |
| SSRF blocking | `/test-ssrf-blocked` | localhost/private IPs blocked |
| Mixed async patterns | `/test-mixed-async` | Timer + fetch + Promise.resolve in one handler |

### Known Issues

| Behavior | Test | Status |
|----------|------|--------|
| Promise that never resolves | `/test-promise-never-resolves` | Returns HTTP 500 after ~10s (correct) |
| ReadableStream `start()` with sync `close()` | `/test-start-sync-close` | **Hangs** — use `pull()` pattern instead |

### What Will Hang or Timeout

These patterns cause the promise wait loop to exhaust its 10,000 iterations and return HTTP 500:

**Infinite synchronous loop:**
```javascript
export default {
  async fetch(request) {
    while (true) {} // Blocks V8 completely — no event loop ticks
    return new Response("never reached");
  }
};
```

**Promise that never resolves:**
```javascript
export default {
  async fetch(request) {
    await new Promise(() => {}); // No resolve/reject call
    // Returns "Promise did not resolve in time" after ~10s
  }
};
```

**ReadableStream start() with synchronous close:**
```javascript
// BUG: This hangs indefinitely
const stream = new ReadableStream({
  start(controller) {
    controller.enqueue("data");
    controller.close(); // Closing in start() causes hang
  }
});
const reader = stream.getReader();
await reader.read(); // Never resolves

// WORKAROUND: Use pull() instead
const stream = new ReadableStream({
  pull(controller) {
    controller.enqueue("data");
    controller.close(); // Closing in pull() works correctly
  }
});
```

## Running the Test Suite

The event loop regression tests live in `test/event-loop-test/`. To run them:

```bash
# Build NANO
zig build

# Start the test server
./zig-out/bin/nano serve --config test/event-loop-test/nano.json &

# Run all local tests (no network required)
curl -s -H "Host: event-loop-test" http://127.0.0.1:8080/test-all-local | python3 -m json.tool

# Run edge case tests
curl -s -H "Host: event-loop-test" http://127.0.0.1:8080/test-edge-cases | python3 -m json.tool

# Run individual network tests
curl -s -H "Host: event-loop-test" http://127.0.0.1:8080/test-async-fetch
curl -s -H "Host: event-loop-test" http://127.0.0.1:8080/test-concurrent-fetch
```

Expected results: 10/10 local tests PASS, 4/4 edge cases PASS.

## Implementation Files

| File | What it does |
|------|--------------|
| `src/runtime/event_loop.zig` | xev loop wrapper, timer storage, fetch queue with mutex |
| `src/runtime/timers.zig` | setTimeout/setInterval/clear* callbacks, `executePendingTimers` |
| `src/api/fetch.zig` | Resolver registry, `FetchOperation`, thread workers, `resolveCompletedFetches` |
| `src/api/writable_stream.zig` | Async sink detection (`isPromise`), `pending_async_streams` polling |
| `src/server/app.zig` | Promise wait loop (lines 540-600) — the central coordinator |
| `src/server/http.zig` | `processEventLoop` — inter-request tick for stale callbacks |

## Related APIs

- [Timers](/api/timers) — setTimeout, setInterval, clearTimeout, clearInterval
- [fetch](/api/fetch) — Non-blocking HTTP requests with thread pool
- [Streams](/api/streams) — ReadableStream, WritableStream with async sink support
- [Known Limitations](/api/limitations) — Remaining issues and workarounds
