# Project Milestones: NANO

## v1.2 Production Polish (Shipped: 2026-02-09)

**Delivered:** WinterCG Streams API, per-app environment variables, graceful shutdown with connection draining, API spec compliance (24 getter properties), and 34-page documentation site.

**Phases completed:** v1.2-01 through v1.2-06 (13 plans total)

**Key accomplishments:**

- WinterCG Streams — ReadableStream, WritableStream, TransformStream with pipe operations and text streams
- Per-App Environment Variables — Isolated `env` parameter in fetch handler with hot-reload support
- Graceful Shutdown — Connection draining, SIGTERM/SIGINT handlers, V8 timer lifecycle fixes
- API Spec Compliance — 24 properties migrated to getters, Headers.delete/append, binary data support
- Response.body Streaming — ReadableStream body support for HTTP responses
- Documentation Site — 34-page Astro + Starlight site with API reference, WinterCG compliance, deployment guides

**Stats:**

- 101 files changed
- +27,745 lines (10,988 LOC Zig total)
- 6 phases, 13 plans
- 8 days (2026-02-02 → 2026-02-09)

**Git range:** `4038380` → `6e8b135`

**What's next:** v1.3 with buffer limits, async fetch, crypto expansion, WinterCG essentials

---

## v1.1 Multi-App Hosting (Shipped: 2026-02-01)

**Delivered:** Multi-app runtime with virtual host routing, config-based loading, hot reload, and Admin REST API.

**Phases completed:** v1.1-01, v1.1-02 (3 plans total)

**Key accomplishments:**

- Multi-App Virtual Host Routing — Single HTTP port routes requests to different apps based on Host header
- Config-based App Loading — Multiple apps from JSON config with hostname, path, and limits
- Hot Reload Infrastructure — Poll-based config watcher with 2s interval and 500ms debounce
- Admin REST API — `/admin/apps` endpoints for listing, adding, removing apps at runtime
- Atomic App Updates — Apps can be added/removed without service interruption

**Stats:**

- 20 files modified
- +2,607 lines of Zig
- 2 phases, 3 plans
- 14 days from start to ship (2026-01-18 -> 2026-02-01)

**Git range:** `362347d` -> `d9d29a2`

**What's next:** v1.2 with graceful shutdown, or v2.0 with V8 snapshots/isolate pooling

---

## v1.0 MVP (Shipped: 2026-01-26)

**Delivered:** Ultra-dense JavaScript runtime with Workers-compatible APIs, HTTP server, async support, and production hardening.

**Phases completed:** 1-6 (14 plans total)

**Key accomplishments:**

- V8 Foundation — Zig executes JavaScript via embedded V8 with arena allocator for per-request memory cleanup
- Workers-Compatible APIs — console, TextEncoder/Decoder, atob/btoa, URL/URLSearchParams, crypto (randomUUID, getRandomValues, subtle.digest, subtle.sign/verify)
- HTTP Server — Multi-app hosting with folder deployment, Request/Response/Headers APIs, proper status codes
- Script Caching — Compile once, reuse per request via V8 persistent handles
- Production Ready — Structured JSON logging, Prometheus metrics, health endpoints, graceful shutdown
- Async Runtime — Event loop with libxev, setTimeout/setInterval, async fetch() with Promises
- Bonus: CPU watchdog, memory limits, AbortController, Blob/File/FormData

**Stats:**

- 85 files created/modified
- 6,261 lines of Zig
- 6 phases, 14 plans
- 8 days from project init to ship (2026-01-18 → 2026-01-26)

**Git range:** `227e3f3` → `08688c8`

**What's next:** v2 with multi-app registry, V8 snapshots, or isolate pooling

---
