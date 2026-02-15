# Requirements: NANO

**Defined:** 2026-02-15
**Core Value:** Skip the container fleet entirely — one process hosts many isolated JS apps

## v1.3 Requirements

Requirements for v1.3 Backlog Cleanup. Each maps to roadmap phases.

### Memory & Buffers

- [ ] **BUF-01**: Blob constructor handles data >64KB without truncation
- [ ] **BUF-02**: Blob.text() and Blob.arrayBuffer() handle >64KB data
- [ ] **BUF-03**: fetch() request body handles >64KB payloads
- [ ] **BUF-04**: atob()/btoa() handle >8KB input
- [ ] **BUF-05**: console.log handles >4KB per value

### Async I/O

- [ ] **ASYNC-01**: fetch() returns Promise without blocking event loop
- [ ] **ASYNC-02**: Multiple concurrent fetch() calls execute in parallel
- [ ] **ASYNC-03**: WritableStream write() supports async sink functions (Promise-returning)

### Crypto

- [ ] **CRYPT-01**: crypto.subtle.encrypt/decrypt with AES-GCM
- [ ] **CRYPT-02**: crypto.subtle.sign/verify with RSA-PSS
- [ ] **CRYPT-03**: crypto.subtle.sign/verify with ECDSA (P-256, P-384)
- [ ] **CRYPT-04**: crypto.subtle.generateKey for AES, RSA, and ECDSA
- [ ] **CRYPT-05**: crypto.subtle.importKey/exportKey (raw, JWK formats)

### Streams

- [ ] **STRM-01**: ReadableStream.tee() delivers all chunks to both branches independently
- [ ] **STRM-02**: tee() branches handle unbalanced consumption without data loss

### WinterCG Essentials

- [ ] **WNCG-01**: structuredClone() deep-copies objects (including Map, Set, TypedArray, circular refs)
- [ ] **WNCG-02**: queueMicrotask() enqueues function on V8 microtask queue
- [ ] **WNCG-03**: performance.now() returns high-resolution monotonic timestamp

### URL

- [ ] **URL-01**: URL properties (pathname, search, hash, host, hostname, port, protocol) are settable
- [ ] **URL-02**: Setting URL properties re-serializes the full URL string (href updates)

## Future Requirements

### Performance (v1.4+)

- **PERF-01**: Multi-threaded request handling (thread pool or multi-process)
- **PERF-02**: Sub-5ms cold start for new isolates (V8 snapshots)
- **PERF-03**: Isolate pooling (warm isolate reuse)

### Extended APIs (v2+)

- **API-01**: WebSocket support
- **API-02**: EventTarget / Event APIs
- **API-03**: CompressionStream / DecompressionStream
- **API-04**: Cache / CacheStorage APIs

## Out of Scope

| Feature | Reason |
|---------|--------|
| AES-CBC encryption | Padding oracle vulnerability risk — AES-GCM only (AEAD) |
| Full WebCrypto key wrapping | wrapKey/unwrapKey deferred — importKey/exportKey sufficient for v1.3 |
| HTTP/2 for async fetch | HTTP/1.1 first — H2 adds multiplexing complexity |
| WebSocket | Requires persistent connection architecture — separate milestone |
| Node.js API compatibility | Workers API only — explicit project constraint |
| Multi-threading (B-07) | Deferred to v1.4+ — too complex for backlog cleanup |
| DOMException class | Error with .name property sufficient for v1.3 |
| navigator object | Low priority — feature detection via other means |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| BUF-01 | v1.3-01 | Pending |
| BUF-02 | v1.3-01 | Pending |
| BUF-03 | v1.3-01 | Pending |
| BUF-04 | v1.3-01 | Pending |
| BUF-05 | v1.3-01 | Pending |
| ASYNC-01 | v1.3-01 | Pending |
| ASYNC-02 | v1.3-01 | Pending |
| ASYNC-03 | v1.3-01 | Pending |
| CRYPT-01 | v1.3-02 | Pending |
| CRYPT-02 | v1.3-02 | Pending |
| CRYPT-03 | v1.3-02 | Pending |
| CRYPT-04 | v1.3-02 | Pending |
| CRYPT-05 | v1.3-02 | Pending |
| STRM-01 | v1.3-02 | Pending |
| STRM-02 | v1.3-02 | Pending |
| WNCG-01 | v1.3-03 | Pending |
| WNCG-02 | v1.3-03 | Pending |
| WNCG-03 | v1.3-03 | Pending |
| URL-01 | v1.3-03 | Pending |
| URL-02 | v1.3-03 | Pending |

**Coverage:**
- v1.3 requirements: 20 total
- Mapped to phases: 20
- Unmapped: 0

---
*Requirements defined: 2026-02-15*
*Last updated: 2026-02-15 after v1.3 roadmap creation*
