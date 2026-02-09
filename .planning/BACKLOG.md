# Backlog: Deferred Known Limitations

Items here are real issues discovered during v1.2 development that were explicitly deferred.
Each item has enough context to be picked up later without re-investigation.

**Rule:** Nothing leaves this file without either being completed or moved to a roadmap phase.

---

## B-01: Stack buffer limits across APIs

**Severity:** High — silently truncates user data
**Discovered:** v1.2-04 (GA quality audit)
**Fix requires:** Replace stack-allocated buffers with heap allocation via `allocator.alloc()`

| API | Buffer | Limit | File:Line |
|-----|--------|-------|-----------|
| Blob constructor | `encoded_buf` | 64KB | `src/api/blob.zig:127-148` |
| Blob.text() | `data_buf` + `decoded_buf` | 64KB each | `src/api/blob.zig:176-200` |
| Blob.arrayBuffer() | same pattern | 64KB | `src/api/blob.zig:210-240` |
| fetch() request body | `body_buf` | 64KB | `src/api/fetch.zig:170` |
| atob() | input + output buffers | 8KB | `src/api/encoding.zig:39,48` |
| btoa() | input + output buffers | 8KB | `src/api/encoding.zig:75,80` |
| console.log | per-value buffer | 4KB | `src/api/console.zig:55,71` |

**Approach:** Allocate from `self.allocator` with proper `defer free()`. For hot-path APIs (Blob, fetch), consider a pooled buffer or configurable max size.

---

## B-02: Synchronous fetch() blocks event loop

**Severity:** High — single blocking fetch stalls all other connections
**Discovered:** v1.0 (by design for MVP)
**Fix requires:** Async HTTP client integrated with xev event loop

**Current behavior:** `doFetch()` in `src/api/fetch.zig:258-264` makes a blocking TCP connection using `std.net.tcpConnectToHost`. The entire server is single-threaded, so during a fetch, no other requests can be accepted.

**Approach options:**
1. Non-blocking HTTP client using xev sockets + completion callbacks
2. Thread pool for fetch operations (simpler but adds concurrency complexity)
3. Connection pooling with keep-alive for repeated fetches to same host

---

## B-03: WritableStream sync-only sinks

**Severity:** Medium — async write sinks (e.g., database writes) don't work correctly
**Discovered:** v1.2-02 (Streams Foundation)
**Fix requires:** Promise-aware write queue in `src/api/writable_stream.zig:577`

**Current behavior:** The `write()` sink callback is called synchronously. If it returns a Promise, NANO doesn't await it — the write completes immediately and the next write begins before the previous one finishes.

**Approach:** After calling `write_fn.call()`, check if result is a Promise. If so, attach a `.then()` callback that processes the next queued write.

---

## B-04: crypto.subtle limited to HMAC

**Severity:** Medium — many real-world apps need RSA/ECDSA/AES
**Discovered:** v1.0 (by design for MVP)
**Fix requires:** Significant new crypto implementation

**Missing operations:**
- `importKey` / `exportKey` / `generateKey`
- `encrypt` / `decrypt` (AES-GCM, AES-CBC, RSA-OAEP)
- `sign` / `verify` with RSA-PSS, ECDSA, Ed25519
- `deriveKey` / `deriveBits` (HKDF, PBKDF2, ECDH)

**Approach:** Use OpenSSL/BoringSSL bindings or Zig's `std.crypto` for algorithm implementations. Prioritize: AES-GCM (encrypt/decrypt) → RSA-PSS (sign/verify) → ECDSA → key import/export.

---

## B-05: ReadableStream.tee() data loss

**Severity:** Medium — tee() is part of the Streams spec and used by frameworks
**Discovered:** v1.2-02 (Streams Foundation)
**Fix requires:** Spec-compliant branch queuing in `src/api/readable_stream.zig:237-283`

**Current behavior:** Both tee() branches share a single reader. Each chunk goes to only one branch (whichever reads first), causing data loss in the other.

**Approach:** Implement internal queue per branch. When the source stream produces a chunk, copy it into both branch queues. Each branch reads independently from its own queue.

---

## B-06: Missing foundational WinterCG APIs

**Severity:** Low-Medium — needed for framework compatibility, not basic apps
**Discovered:** v1.2-04 (GA quality audit)

| API | Priority | Notes |
|-----|----------|-------|
| `structuredClone()` | Medium | Used by many frameworks for deep copy |
| `queueMicrotask()` | Medium | Used by Promise polyfills and frameworks |
| `performance.now()` | Medium | Used for timing/profiling |
| `DOMException` | Low | `Error` with `.name` works for most cases |
| `EventTarget` / `Event` | Low | Foundation for addEventListener pattern |
| `navigator` object | Low | `navigator.userAgent` used for feature detection |
| `WebSocket` | Low | Requires persistent connection support |
| `Cache` / `CacheStorage` | Low | Requires storage backend |
| `CompressionStream` / `DecompressionStream` | Low | Requires zlib bindings |

**Approach:** Prioritize `structuredClone`, `queueMicrotask`, `performance.now` as a "WinterCG Essentials" phase. EventTarget/WebSocket/Cache are larger features that should be their own milestones.

---

## B-07: Single-threaded server (no connection pooling)

**Severity:** Low (for current use case) — limits throughput under concurrent load
**Discovered:** v1.0 (by design for MVP)
**Fix requires:** Thread pool or multi-process architecture

**Current behavior:** One blocking accept loop handles all connections sequentially. Under concurrent load, requests queue behind each other.

**Approach options:**
1. Thread pool: spawn N worker threads, each with its own V8 isolate
2. Multi-process: fork N processes sharing the listening socket
3. Async I/O: convert to fully async with xev for accept + read + write (most complex)

---

## B-08: URL properties are read-only

**Severity:** Low — most Workers code only reads URL properties
**Discovered:** v1.2-04 (GA quality audit)
**File:** `src/api/url.zig`

**Current behavior:** URL has getters but no setters. `url.pathname = "/new"` silently does nothing.

**Approach:** Add `setAccessorSetter()` for mutable properties (pathname, search, hash, etc.) that re-serialize the URL string.

---

## Tracking

| ID | Summary | Target Phase | Status |
|----|---------|-------------|--------|
| B-01 | Stack buffer limits | v1.3 TBD | Deferred |
| B-02 | Synchronous fetch | v1.3 TBD | Deferred |
| B-03 | WritableStream async sinks | v1.3 TBD | Deferred |
| B-04 | crypto.subtle beyond HMAC | v1.3 TBD | Deferred |
| B-05 | ReadableStream.tee() data loss | v1.3 TBD | Deferred |
| B-06 | Missing WinterCG APIs | v1.3 TBD | Deferred |
| B-07 | Single-threaded server | v1.4+ | Deferred |
| B-08 | URL read-only properties | v1.3 TBD | Deferred |

---
*Created: 2026-02-08 during v1.2-04 completion*
*Last updated: 2026-02-08*
