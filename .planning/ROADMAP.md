# Roadmap: NANO

## Milestones

- ✅ **v1.0 MVP** — Phases v1.0-01 to v1.0-05 (shipped 2026-01-25)
- ✅ **v1.1 Multi-App Hosting** — Phases v1.1-01 to v1.1-02 (shipped 2026-02-01)
- ✅ **v1.2 Production Polish** — Phases v1.2-01 to v1.2-06 (shipped 2026-02-09)
- 🚧 **v1.3 Backlog Cleanup** — Phases v1.3-01 to v1.3-03 (in progress)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases v1.0-01 to v1.0-05) — SHIPPED 2026-01-25</summary>

Phases v1.0-01 through v1.0-05 delivered core JavaScript runtime with V8 isolates, Workers-compatible APIs, HTTP server, and safety features.

See `milestones/v1.0-ROADMAP.md` for full details.

</details>

<details>
<summary>✅ v1.1 Multi-App Hosting (Phases v1.1-01 to v1.1-02) — SHIPPED 2026-02-01</summary>

- v1.1-01: Multi-App Foundation — Config-based app loading, virtual host routing, hot reload
- v1.1-02: App Lifecycle — Admin API for runtime management

See `milestones/v1.1-ROADMAP.md` for full details.

</details>

<details>
<summary>✅ v1.2 Production Polish (Phases v1.2-01 to v1.2-06) — SHIPPED 2026-02-09</summary>

- v1.2-01: Per-App Environment Variables — Isolated config per app
- v1.2-02: Streams Foundation — ReadableStream/WritableStream/TransformStream
- v1.2-03: Response Body Integration — Streaming HTTP responses
- v1.2-04: Graceful Shutdown & Stability — Connection draining, V8 timer fixes
- v1.2-05: API Spec Compliance — 24 getter properties, Headers fixes, binary data
- v1.2-06: Documentation Site — 34-page Astro + Starlight site

See `milestones/v1.2-ROADMAP.md` for full details.

</details>

### 🚧 v1.3 Backlog Cleanup (In Progress)

**Milestone Goal:** Fix all known limitations from v1.0–v1.2: heap buffers, async fetch, WritableStream async, crypto expansion, ReadableStream.tee(), WinterCG essentials, and URL setters.

## Phases

- [ ] **Phase v1.3-01: Async Foundation** — Heap-allocated buffers and non-blocking async fetch with Promise-aware WritableStream
- [ ] **Phase v1.3-02: Crypto & Streams** — crypto.subtle algorithm expansion (AES-GCM, RSA-PSS, ECDSA, key management) and ReadableStream.tee() fix
- [ ] **Phase v1.3-03: API Completion** — WinterCG globals (structuredClone, queueMicrotask, performance.now) and URL property setters

## Phase Details

### Phase v1.3-01: Async Foundation
**Goal**: Buffers never truncate on large inputs, and fetch() runs non-blocking with proper Promise resolution and backpressure-aware WritableStream
**Depends on**: v1.2 (shipped — provides arena allocator, xev event loop, Promise infrastructure)
**Requirements**: BUF-01, BUF-02, BUF-03, BUF-04, BUF-05, ASYNC-01, ASYNC-02, ASYNC-03
**Success Criteria** (what must be TRUE):
  1. A handler creating a Blob with 1MB data returns the full 1MB from Blob.text() — no truncation at 64KB
  2. A fetch() call to a slow external endpoint returns a Promise immediately; other setTimeout callbacks fire while the fetch is in-flight
  3. Two concurrent fetch() calls to different hosts resolve independently without one blocking the other
  4. A WritableStream with an async sink function (returning a Promise) accepts writes and signals backpressure correctly — write() returns a Promise that resolves when the sink drains
  5. atob()/btoa() with a 50KB base64 string round-trips correctly; console.log of a 10KB string prints the full value
**Plans**: 3 plans

Plans:
- [ ] v1.3-01-01-PLAN.md — Heap buffer fallback for blob.zig, encoding.zig, console.zig (BUF-01..05)
- [ ] v1.3-01-02-PLAN.md — Async fetch with thread pool + Promise resolver lifecycle (ASYNC-01, ASYNC-02, BUF-03)
- [ ] v1.3-01-03-PLAN.md — WritableStream async sink detection and deferred write resolution (ASYNC-03)

### Phase v1.3-02: Crypto & Streams
**Goal**: crypto.subtle supports symmetric (AES-GCM) and asymmetric (RSA-PSS, ECDSA) algorithms with key import/export, and ReadableStream.tee() delivers all chunks to both branches without data loss
**Depends on**: Phase v1.3-01
**Requirements**: CRYPT-01, CRYPT-02, CRYPT-03, CRYPT-04, CRYPT-05, STRM-01, STRM-02
**Success Criteria** (what must be TRUE):
  1. A handler encrypts a string with AES-GCM, passes the ciphertext to another call, and decrypts it back to the original value
  2. A handler generates an ECDSA P-256 key pair, signs a message, and verifies the signature — all within one request
  3. A handler imports a raw AES key via importKey(), encrypts data, exports the key as JWK, re-imports it, and decrypts successfully
  4. ReadableStream.tee() on a 10-chunk stream delivers all 10 chunks to both branch readers independently — even when one branch reads faster than the other
  5. A tee() branch that reads slowly does not cause data loss in either branch (both eventually receive all chunks)
**Plans**: TBD

Plans:
- [ ] v1.3-02-01: AES-GCM encrypt/decrypt (CRYPT-01) and ECDSA sign/verify (CRYPT-03)
- [ ] v1.3-02-02: RSA-PSS sign/verify (CRYPT-02) and key management (CRYPT-04, CRYPT-05)
- [ ] v1.3-02-03: ReadableStream.tee() per-branch queues (STRM-01, STRM-02)

### Phase v1.3-03: API Completion
**Goal**: WinterCG globals (structuredClone, queueMicrotask, performance.now) work correctly, and URL properties are fully mutable with href re-serialization
**Depends on**: Phase v1.3-01
**Requirements**: WNCG-01, WNCG-02, WNCG-03, URL-01, URL-02
**Success Criteria** (what must be TRUE):
  1. structuredClone() of an object containing a Map, a Set, a TypedArray, and a circular reference produces an independent deep copy with no shared references
  2. queueMicrotask(() => { /* ... */ }) executes the callback before the next macrotask (observable by interleaving with setTimeout(fn, 0))
  3. performance.now() returns a monotonically increasing number across calls within the same request; two calls separated by a real delay differ by at least that delay in milliseconds
  4. Setting url.pathname = '/new-path' on a URL object updates url.href to reflect the new path immediately
  5. Setting url.search = '?q=test' updates both url.search and url.href; href re-serializes with all modified components combined
**Plans**: TBD

Plans:
- [ ] v1.3-03-01: WinterCG globals (WNCG-01, WNCG-02, WNCG-03) — structuredClone via V8 Serializer, queueMicrotask, performance.now
- [ ] v1.3-03-02: URL property setters (URL-01, URL-02) — pathname/search/hash/host/hostname/port/protocol setters with href re-serialization

## Progress

**Execution Order:** v1.3-01 → v1.3-02 → v1.3-03

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| v1.3-01: Async Foundation | 0/3 | Not started | - |
| v1.3-02: Crypto & Streams | 0/3 | Not started | - |
| v1.3-03: API Completion | 0/2 | Not started | - |

---
*Last updated: 2026-02-17 — v1.3-01 plans created (3 plans, 2 waves)*
