# NANO

## What This Is

NANO is an ultra-dense JavaScript runtime that hosts multiple applications in a single process using V8 isolates. Think of it like a browser with tabs — each tab is an isolated app, but they share one process. Built in Zig with embedded V8, it targets platform engineers who want Cloudflare Workers-like density without container orchestration overhead.

## Core Value

**Skip the container fleet entirely.** One NANO process replaces dozens of Node containers, their image builds, fleet management, and routing infrastructure — while maintaining isolation between apps.

## Current State (v1.2 Shipped)

**Version:** v1.2 Production Polish (shipped 2026-02-09)
**Codebase:** ~11,000 lines of Zig across 100+ files
**Documentation:** 34-page Astro + Starlight site
**Status:** Production-ready with streaming, graceful shutdown, and full documentation

### What's Working

**Runtime (v1.0):**
- V8 isolate execution with arena allocator per request
- Workers-compatible APIs: console, TextEncoder/Decoder, atob/btoa, URL/URLSearchParams
- Crypto: randomUUID, getRandomValues, subtle.digest, subtle.sign/verify
- HTTP: fetch(), Request, Response, Headers, FormData, Blob, File
- Async: event loop (libxev), setTimeout/setInterval, Promise-based handlers
- Safety: CPU watchdog (5s), memory limits (128MB), AbortController

**Multi-App (v1.1):**
- Virtual host routing (Host header -> app on single port)
- Config-based app loading (JSON with hostname, path, limits)
- Hot reload via config file watcher (2s poll, 500ms debounce)
- Admin REST API: GET/POST/DELETE /admin/apps, POST /admin/reload
- Atomic app add/remove without request drops

**Production Polish (v1.2):**
- WinterCG Streams: ReadableStream, WritableStream, TransformStream with pipe operations
- Per-app environment variables with isolation and hot-reload
- Graceful shutdown with connection draining (SIGTERM/SIGINT + app removal)
- API spec compliance: 24 getter properties, Headers.delete/append, binary data support
- Response.body streaming via ReadableStream
- 34-page documentation site (Getting Started, API reference, deployment guides)

### Known Limitations

- Stack buffer limits: Blob 64KB, fetch 64KB, atob 8KB, console 4KB (B-01)
- Synchronous fetch() blocks event loop (B-02)
- WritableStream sync-only sinks (B-03)
- crypto.subtle limited to HMAC + hashing (B-04)
- ReadableStream.tee() data loss (B-05)
- Missing WinterCG APIs: structuredClone, queueMicrotask, performance.now (B-06)
- Single-threaded server (B-07)
- URL read-only properties (B-08)

See BACKLOG.md for full details and suggested approaches.

## Requirements

### Validated (v1.0)

- Workers-compatible API surface (fetch, Request/Response, Headers, console) — v1.0
- Folder-based deployment (point at directory, app runs) — v1.0
- Proper HTTP error responses to clients — v1.0
- Structured logging per app — v1.0
- Hard isolation between apps (memory, CPU limits enforced) — v1.0

### Validated (v1.1)

- Multi-app registry (config file + folder discovery) — v1.1
- Virtual host routing (multiple apps on same port) — v1.1
- Hot reload apps without restart — v1.1

### Validated (v1.2)

- Streams API (ReadableStream/WritableStream/TransformStream) — v1.2
- Per-app environment variables (config JSON, isolated per app) — v1.2
- Graceful shutdown with connection draining — v1.2
- API spec compliance (getter properties, Headers fixes, binary data) — v1.2
- Documentation website (Astro + Starlight, 34 pages) — v1.2

### Future (v2 candidates)

- [ ] Sub-5ms cold start for new isolates (via V8 snapshots)
- [ ] Isolate pooling (warm isolate reuse)

### Out of Scope

- Toolchain/CLI for bundling/deploying — v2+ (manual folder deployment works)
- KV storage API — v2+ (use external storage initially)
- Built-in HTTPS termination — use external reverse proxy
- Node.js API compatibility — Workers API only
- Durable Objects — out of scope entirely (too complex, different model)

## Context

**Why Zig + V8:**
- Zig provides manual memory control (arena allocators for instant cleanup)
- V8 is battle-tested, has snapshot system for fast cold starts
- Zig's C/C++ interop makes V8 embedding feasible
- Alternative (Bun's JSC) is less documented for embedding

**Reference implementations:**
- Cloudflare workerd — production isolate runtime (C++, open source)
- Deno — V8 embedding patterns (Rust)
- Bun — Zig + JS engine patterns (uses JSC, not V8)

**Target workloads:**
- API gateways
- Edge functions
- Webhook processors
- Multi-tenant serverless platforms

## Constraints

- **Runtime**: Zig 0.15.2 (adapted from 0.13.0 original target)
- **V8 version**: V8 12.x via nickelca/v8-zig fork
- **Platform**: macOS for development, Linux for production
- **API surface**: Workers-compatible (code portable from Vercel/Cloudflare)

## Key Decisions

| Decision                       | Rationale                                         | Outcome                           |
| ------------------------------ | ------------------------------------------------- | --------------------------------- |
| Zig over Rust                  | Better C++ interop, arena allocators              | Good — clean V8 integration       |
| V8 over JSC                    | Better documented embedding, snapshot system      | Good — stable runtime             |
| Workers API over Node API      | Simpler surface, isolation-friendly, portable     | Good — clean API                  |
| Ports-first routing            | Simple start, external proxy handles SSL          | Good — works for MVP              |
| Script caching over snapshots  | Snapshots too complex (callback serialization)    | Good — fast enough for v1         |
| Single-threaded MVP            | Isolate pooling adds complexity                   | Good — simpler debugging          |
| libxev for event loop          | Cross-platform, async I/O                         | Good — timer + fetch work         |
| Poll-based config watching     | libxev lacks filesystem events                    | Good — simple and portable        |
| Function pointer callbacks     | Avoids circular imports                           | Good — clean module separation    |
| Admin /admin/* prefix          | Clear separation, easy to gate                    | Good — extensible                 |
| Embedded JS for streams        | V8 Function.call() simpler than Zig state machine | Good — TransformStream/pipeTo/tee |
| setAccessorGetter for props    | Standard WinterCG pattern for spec properties     | Good — 24 properties converted    |
| Astro + Starlight for docs     | Built-in search, MDX support, fast                | Good — 34 pages, low maintenance  |

---

<details>
<summary>v1.0 → v1.1 Migration Notes</summary>

**Breaking changes:** None. v1.1 is backwards compatible.

**New features:**
- Config file format extended with `hostname` field per app
- Global `port` field in config for single-port hosting
- Admin API at `/admin/*` endpoints

**Upgrade path:**
1. Update config to include `hostname` for each app
2. (Optional) Use Admin API for runtime management

</details>

<details>
<summary>v1.1 → v1.2 Migration Notes</summary>

**Breaking changes:** None. v1.2 is backwards compatible.

**New features:**
- Streams API: ReadableStream, WritableStream, TransformStream
- Per-app `env` object in config.json, accessible as second fetch handler parameter
- Graceful shutdown on SIGTERM/SIGINT with connection draining
- Properties now use getter accessors (backwards compatible — methods still work)

**Upgrade path:**
1. (Optional) Add `env` to app configs for environment variables
2. (Optional) Use `request.url` instead of `request.url()` (both work)
3. (Optional) Use Response.body for streaming

</details>

---
*Last updated: 2026-02-09 after v1.2 milestone completion*
