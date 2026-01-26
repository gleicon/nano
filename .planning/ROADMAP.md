# Roadmap: NANO

## Overview

NANO is built in six phases that follow the natural dependency chain: first make V8 run JavaScript from Zig, then expose Workers-compatible APIs, then add HTTP routing for multi-app hosting, then optimize cold starts with snapshots and pooling, add async runtime for event loop and timers, and finally harden for production with resource limits. Each phase delivers a verifiable capability that the next phase builds upon.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: V8 Foundation** - Zig can execute JavaScript and manage memory
- [x] **Phase 2: API Surface** - Workers-compatible APIs (fetch, crypto, console)
- [x] **Phase 3: Multi-App Hosting** - HTTP server routes requests to apps
- [x] **Phase 4: Snapshots + Pooling** - Script caching (snapshots/pooling deferred)
- [x] **Phase 5: Production Hardening** - Logging, metrics, graceful shutdown
- [x] **Phase 6: Async Runtime** - Event loop, timers, async fetch, Promise handlers

## Phase Details

### Phase 1: V8 Foundation
**Goal**: Zig can execute JavaScript code via V8 with per-request memory management
**Depends on**: Nothing (first phase)
**Requirements**: CORE-01, CORE-02
**Success Criteria** (what must be TRUE):
  1. Running `nano eval "1 + 1"` returns `2` to stdout
  2. JavaScript syntax errors return meaningful error messages
  3. Memory allocated during script execution is freed when request ends
**Plans**: 3 plans

Plans:
- [x] 01-01-PLAN.md — Project setup and V8 integration via zig-v8-fork
- [x] 01-02-PLAN.md — Script execution with TryCatch error handling
- [x] 01-03-PLAN.md — CLI interface and arena allocator integration

### Phase 2: API Surface
**Goal**: Scripts have access to Workers-compatible APIs (fetch, crypto, console, streams) + REPL for development
**Depends on**: Phase 1
**Requirements**: WAPI-01, WAPI-02, WAPI-03, WAPI-04, WAPI-05, WAPI-06, HTTP-01, HTTP-02, HTTP-03, HTTP-04, HTTP-05, HTTP-06, HTTP-07, CRYP-01, CRYP-02, CRYP-03, CRYP-04
**Success Criteria** (what must be TRUE):
  1. Script can fetch an external URL and read the response body
  2. Script can compute SHA-256 hash via crypto.subtle.digest()
  3. console.log output appears in host process logs
  4. Script can encode/decode text, base64, and URL parameters
  5. `nano repl` starts interactive JavaScript session
**Plans**: 5 plans

Plans:
- [x] 02-01-PLAN.md — Console API (console.log/error/warn)
- [x] 02-02-PLAN.md — Encoding APIs (TextEncoder/Decoder, atob/btoa)
- [x] 02-03-PLAN.md — URL APIs (URL, URLSearchParams)
- [x] 02-04-PLAN.md — REPL command with persistent isolate
- [x] 02-05-PLAN.md — Crypto and Fetch APIs (stub, async requires Phase 3)

### Phase 3: Multi-App Hosting
**Goal**: Multiple apps run on the same NANO process, routed by port
**Depends on**: Phase 2
**Requirements**: HOST-01, HOST-02, HOST-03, OBSV-02
**Success Criteria** (what must be TRUE):
  1. Pointing NANO at a folder starts an app serving HTTP requests
  2. Two apps on different ports run independently without interference
  3. HTTP errors return proper status codes (4xx, 5xx) with clean messages
**Plans**: TBD

Plans:
- [x] 03-01-PLAN.md — HTTP Server Foundation
- [x] 03-02-PLAN.md — Request/Response/Headers APIs
- [x] 03-03-PLAN.md — App Loader and JavaScript Handler Integration

Note: HOST-02 (multi-app registry) deferred to post-v1.0. Single-app hosting is the MVP.

### Phase 4: Snapshots + Pooling
**Goal**: Cold starts under 5ms via V8 snapshots and warm isolate pooling
**Depends on**: Phase 3
**Requirements**: CORE-03, CORE-04
**Success Criteria** (what must be TRUE):
  1. p99 cold start latency is under 5ms (measured, not estimated)
  2. Warm isolates are reused for subsequent requests to same app
  3. Snapshot contains all Phase 2 APIs pre-initialized
**Plans**: TBD

Plans:
- [x] 04-01-PLAN.md — Script Caching (compile once, reuse per request)
- [ ] 04-02-PLAN.md — V8 Snapshots (deferred - callback serialization complex)
- [ ] 04-03-PLAN.md — Isolate Pooling (deferred - single-threaded for v1.0)

### Phase 5: Production Hardening
**Goal**: NANO has production-ready observability
**Depends on**: Phase 4
**Requirements**: OBSV-01, OBSV-03
**Success Criteria** (what must be TRUE):
  1. Structured logs include app name, request ID, and timestamp
  2. Prometheus endpoint exposes request count, error count, and latency metrics
  3. Health endpoints return status for load balancer probes
  4. Graceful shutdown handles SIGTERM/SIGINT
**Plans**: 1 plan

Plans:
- [x] 05-01-PLAN.md — Logging, metrics, health endpoints, graceful shutdown

### Phase 6: Async Runtime
**Goal**: NANO supports async JavaScript with event loop and timers
**Depends on**: Phase 5
**Requirements**: WAPI-05, HTTP-04 (async)
**Success Criteria** (what must be TRUE):
  1. setTimeout/setInterval execute callbacks after delay
  2. clearTimeout/clearInterval cancel pending timers
  3. fetch() returns a Promise that resolves with Response
  4. async/await works in request handlers
**Plans**: 1 plan

Plans:
- [x] 06-01-PLAN.md — Event loop (libxev), timers, async fetch, Promise handlers

## Backlog (Deferred to v2)

These items were part of original v1 scope but deferred for complexity:

| Item | Reason | Original Requirement |
|------|--------|---------------------|
| V8 Snapshots | Callback serialization complex | CORE-03 |
| Isolate Pooling | Single-threaded for v1.0 | CORE-04 |
| Multi-App Registry | Single-app MVP sufficient | HOST-02 |
| CPU Watchdog (infinite loops) | V8 interrupt API needs investigation | RLIM-02 |
| Memory Limits | V8 heap limit configuration needed | RLIM-01 |
| Per-App Config | Requires config file format design | RLIM-03 |
| Streams API | Complex, rarely needed for Workers | WAPI-06 |
| AbortController | Requires async cancellation design | HTTP-05 |
| FormData/Blob/File | Requires binary data handling | HTTP-06, HTTP-07 |
| crypto.subtle.sign/verify | Requires HMAC/RSA implementation | CRYP-04 |

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. V8 Foundation | 3/3 | Complete | 2026-01-24 |
| 2. API Surface | 5/5 | Complete | 2026-01-24 |
| 3. Multi-App Hosting | 3/3 | Complete | 2026-01-25 |
| 4. Snapshots + Pooling | 1/3 | Complete (deferred) | 2026-01-25 |
| 5. Production Hardening | 1/1 | Complete | 2026-01-26 |
| 6. Async Runtime | 1/1 | Complete | 2026-01-26 |
