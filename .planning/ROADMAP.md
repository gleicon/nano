# Roadmap: NANO v1.2 Production Polish

## Overview

v1.2 adds production-essential features: WinterCG Streams API for streaming responses, per-app environment variables for configuration, graceful shutdown with connection draining, API spec compliance, and documentation. The phase order prioritizes low-risk foundation (env vars) before complex streaming, shutdown logic, and spec fixes.

## Milestones

- ✅ **v1.0 MVP** - Phases v1.0-01 to v1.0-05 (shipped 2026-01-25)
- ✅ **v1.1 Multi-App Hosting** - Phases v1.1-01 to v1.1-02 (shipped 2026-02-01)
- 🚧 **v1.2 Production Polish** - Phases v1.2-01 to v1.2-06 (in progress)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases v1.0-01 to v1.0-05) - SHIPPED 2026-01-25</summary>

Phases v1.0-01 through v1.0-05 delivered core JavaScript runtime with V8 isolates, Workers-compatible APIs, HTTP server, and safety features.

</details>

<details>
<summary>✅ v1.1 Multi-App Hosting (Phases v1.1-01 to v1.1-02) - SHIPPED 2026-02-01</summary>

**v1.1-01: Multi-App Foundation** - Config-based app loading, virtual host routing, hot reload
**v1.1-02: App Lifecycle** - Admin API for runtime management

</details>

### 🚧 v1.2 Production Polish (In Progress)

**Milestone Goal:** Add Streams API, environment variables, graceful shutdown, API spec compliance, and documentation

- [x] **Phase v1.2-01: Per-App Environment Variables** - Isolated config per app
- [x] **Phase v1.2-02: Streams Foundation** - ReadableStream/WritableStream core
- [x] **Phase v1.2-03: Response Body Integration** - Streaming HTTP responses
- [x] **Phase v1.2-04: Graceful Shutdown & Stability** - Connection draining, V8 lifecycle fixes, timer system
- [x] **Phase v1.2-05: API Spec Compliance** - Fix properties-as-methods, buffer limits, missing methods
- [ ] **Phase v1.2-06: Documentation Site** - Astro + Starlight with WinterCG reference

## Phase Details

### Phase v1.2-01: Per-App Environment Variables

**Goal:** Apps can access isolated environment variables from config

**Depends on:** Phase v1.1-02 (config system exists)

**Requirements:** ENVV-01, ENVV-02, ENVV-03, ENVV-04

**Success Criteria** (what must be TRUE):
1. App can read environment variables via second fetch handler parameter
2. Environment variables are defined in config.json per app
3. App A cannot access App B's environment variables
4. Environment variables update when config is hot-reloaded

**Plans:** 1 plan

Plans:
- [x] v1.2-01-01-PLAN.md — Extend config parsing, pass env to fetch handler, verify isolation

### Phase v1.2-02: Streams Foundation

**Goal:** WinterCG-compliant ReadableStream and WritableStream classes work independently

**Depends on:** Nothing (independent feature)

**Requirements:** STRM-01, STRM-02, STRM-03, STRM-04, STRM-05, STRM-06, STRM-07

**Success Criteria** (what must be TRUE):
1. ReadableStream can be created with controller callbacks
2. Reader can read chunks via read() and cancel stream
3. WritableStream can accept writes via writer.write()
4. Backpressure signals work (desiredSize, ready promise)
5. Stream errors propagate correctly through controllers

**Plans:** 3 plans in 2 waves

Plans:
- [x] v1.2-02-01-PLAN.md — ReadableStream foundation (Wave 1)
- [x] v1.2-02-02-PLAN.md — WritableStream foundation (Wave 1, parallel with 01)
- [x] v1.2-02-03-PLAN.md — TransformStream, pipe ops, utilities, text streams (Wave 2)

### Phase v1.2-03: Response Body Integration

**Goal:** HTTP responses support streaming bodies via ReadableStream

**Depends on:** Phase v1.2-02 (streams exist)

**Requirements:** STRM-08, STRM-09

**Success Criteria** (what must be TRUE):
1. Response.body returns a ReadableStream for response content
2. fetch() Response supports streaming consumption via .body.getReader()
3. Large responses can stream without buffering entire content

**Plans:** 1 plan

Plans:
- [x] v1.2-03-01-PLAN.md — Extend Response with .body getter, ReadableStream constructor support, streaming text()/json()

### Phase v1.2-04: Graceful Shutdown & Stability

**Goal:** Process and apps shutdown cleanly with connection draining; server remains stable under timer-driven workloads

**Depends on:** Nothing (independent feature, touches HTTP layer)

**Requirements:** SHUT-01, SHUT-02, SHUT-03, SHUT-04, SHUT-05, SHUT-06

**Success Criteria** (what must be TRUE):
1. SIGTERM/SIGINT stops accepting new connections
2. In-flight requests complete before process exits
3. Removing an app via config watcher drains only that app's connections
4. New requests to draining app receive 503 Service Unavailable
5. Process exits after drain timeout (30s default) even if connections hang
6. Server stays stable when xev timers fire (config watcher, AbortSignal.timeout)
7. V8 timer callbacks execute safely with proper isolate/HandleScope lifecycle

**Plans:** 2 plans (executed inline during GA quality fixes)

Plans:
- [x] v1.2-04-01 — AppDrainState, per-app connection tracking, 503 drain routing, removeApp drain-wait (inline)
- [x] v1.2-04-02 — processEventLoop V8 lifecycle fix, TryCatch for timer callbacks, xev timer rearm fix, DOMException→Error (inline)

**Delivered (2026-02-08):**
- AppDrainState struct with per-app active_connections tracking
- 503 Service Unavailable for draining apps
- removeApp() with 30s drain timeout
- initiateGracefulShutdown() marks all apps as draining
- SIGTERM/SIGINT signal handlers in both serve modes
- processEventLoop enters isolate+HandleScope+Context before V8 calls
- TryCatch wrapper around timer callback execution
- xev timer reschedule fix (manual timer.run instead of .rearm to prevent spin loop)
- AbortSignal.timeout uses Error instead of undefined DOMException
- Code cleanup: js.throw() and js.retResolvedPromise/retRejectedPromise helpers

### Phase v1.2-05: API Spec Compliance

**Goal:** Fix systematic WinterCG spec violations so standard Workers code runs unmodified

**Depends on:** Phase v1.2-03 (all APIs exist)

**Requirements:** SPEC-01, SPEC-02, SPEC-03, SPEC-04, SPEC-05

**Success Criteria** (what must be TRUE):
1. All spec-defined properties use getter accessors (not methods): Blob.size/type, Request.url/method/headers, Response.status/ok/statusText/headers, URL.href/origin/protocol/hostname/port/pathname/search/hash, AbortController.signal, File.name/lastModified
2. Headers.delete() actually removes the key (not sets to undefined)
3. Headers.append() supports multi-value headers
4. Blob constructor accepts ArrayBuffer and Uint8Array parts (not just strings)
5. crypto.subtle.digest accepts ArrayBuffer/Uint8Array input (not just strings)
6. console.log inspects objects with JSON.stringify (not [object Object])

**Known limitations (deferred — not in scope):**
- Buffer size limits (Blob 64KB, fetch body 64KB, atob 8KB) — requires heap allocation refactor
- fetch() synchronous I/O — requires async event loop integration
- WritableStream async sinks — requires Promise-aware write queue
- crypto.subtle RSA/ECDSA/encrypt/decrypt — significant new crypto work
- ReadableStream.tee() data sharing — requires spec-compliant branch queuing
- EventTarget/Event system — foundational API not yet needed
- DOMException class — low priority, Error works for most cases

**Plans:** 3 plans in 3 waves

Plans:
- [x] v1.2-05-01 — Properties→getters migration (Blob, Request, Response, URL, AbortController)
- [x] v1.2-05-02 — Headers fixes (delete, append) + Blob binary parts + crypto digest BufferSource
- [x] v1.2-05-03 — Console object inspection + test verification

### Phase v1.2-06: Documentation Site

**Goal:** Public documentation site explains NANO setup, APIs, and deployment

**Depends on:** Phase v1.2-05 (API behavior is finalized before documenting)

**Requirements:** DOCS-01, DOCS-02, DOCS-03, DOCS-04, DOCS-05, DOCS-06

**Success Criteria** (what must be TRUE):
1. Documentation site builds and serves locally via Astro + Starlight
2. Getting started guide walks through first app deployment
3. Config.json schema is fully documented with examples
4. All Workers-compatible APIs are documented with WinterCG compliance notes
5. Production deployment guide covers reverse proxy setup

**Plans:** TBD

Plans:
- [ ] v1.2-06-01: TBD

## Progress

**Execution Order:** v1.2-01 → v1.2-02 → v1.2-03 → v1.2-04 → v1.2-05 → v1.2-06

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| v1.2-01. Per-App Env Vars | v1.2 | 1/1 | ✓ Complete | 2026-02-02 |
| v1.2-02. Streams Foundation | v1.2 | 3/3 | ✓ Complete | 2026-02-07 |
| v1.2-03. Response Body | v1.2 | 1/1 | ✓ Complete | 2026-02-07 |
| v1.2-04. Graceful Shutdown | v1.2 | 2/2 | ✓ Complete | 2026-02-08 |
| v1.2-05. API Spec Compliance | v1.2 | 3/3 | ✓ Complete | 2026-02-08 |
| v1.2-06. Documentation | v1.2 | 0/0 | Not started | - |

## Pre-existing Issues Registry

### Resolved in v1.2-05
- ~~Properties as methods~~ → converted to getter accessors (24 properties)
- ~~Headers.delete() → undefined~~ → now properly removes keys
- ~~Missing Headers.append()~~ → implemented with multi-value support
- ~~Blob constructor string-only~~ → accepts ArrayBuffer/Uint8Array
- ~~crypto.subtle.digest string-only~~ → accepts ArrayBuffer/Uint8Array
- ~~console.log [object Object]~~ → uses JSON.stringify
- ~~Response.statusText hardcoded "OK"~~ → maps via std.http.Status.phrase()

### Known Limitations (deferred → BACKLOG.md)

8 items tracked in **[BACKLOG.md](BACKLOG.md)** with full context, file references, and suggested approaches:
- B-01: Stack buffer limits (Blob 64KB, fetch 64KB, atob 8KB, console 4KB)
- B-02: Synchronous fetch() blocks event loop
- B-03: WritableStream sync-only sinks
- B-04: crypto.subtle limited to HMAC
- B-05: ReadableStream.tee() data loss
- B-06: Missing WinterCG APIs (structuredClone, queueMicrotask, performance.now, etc.)
- B-07: Single-threaded server
- B-08: URL read-only properties

### Future Milestones (placeholder)

- **v1.3 (TBD):** Buffer limits + async fetch + crypto expansion + WinterCG essentials (B-01 through B-06, B-08)
- **v1.4+ (TBD):** Connection pooling / multi-threading (B-07), WebSocket, Cache API

---
*Last updated: 2026-02-08 after v1.2-05 completion*
