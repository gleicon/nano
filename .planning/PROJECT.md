# NANO

## What This Is

NANO is an ultra-dense JavaScript runtime that hosts multiple applications in a single process using V8 isolates. Think of it like a browser with tabs — each tab is an isolated app, but they share one process. Built in Zig with embedded V8, it targets platform engineers who want Cloudflare Workers-like density without container orchestration overhead.

## Core Value

**Skip the container fleet entirely.** One NANO process replaces dozens of Node containers, their image builds, fleet management, and routing infrastructure — while maintaining isolation between apps.

## Current State (v1.0 Shipped)

**Version:** v1.0 MVP (shipped 2026-01-26)
**Codebase:** 6,261 lines of Zig across 85 files
**Status:** Production-ready for single-app hosting

### What's Working

- V8 isolate execution with arena allocator per request
- Workers-compatible APIs: console, TextEncoder/Decoder, atob/btoa, URL/URLSearchParams
- Crypto: randomUUID, getRandomValues, subtle.digest, subtle.sign/verify
- HTTP: fetch(), Request, Response, Headers, FormData, Blob, File
- Async: event loop (libxev), setTimeout/setInterval, Promise-based handlers
- Server: HTTP routing, health endpoints, Prometheus metrics, graceful shutdown
- Safety: CPU watchdog (5s), memory limits (128MB), AbortController

### Known Limitations

- Single-app per process (multi-app registry deferred)
- No V8 snapshots (compile-time caching only)
- No isolate pooling (single-threaded)
- REPL doesn't support timers
- Response headers limited to content-type

## Requirements

### Validated (v1.0)

- Workers-compatible API surface (fetch, Request/Response, Headers, console) — v1.0
- Folder-based deployment (point at directory, app runs) — v1.0
- Proper HTTP error responses to clients — v1.0
- Structured logging per app — v1.0
- Hard isolation between apps (memory, CPU limits enforced) — v1.0

### Active (v2 candidates)

- [ ] Sub-5ms cold start for new isolates (via V8 snapshots)
- [ ] Multi-app registry (multiple apps in single process)
- [ ] Per-app configuration (custom limits, settings)
- [ ] Streams API (ReadableStream, WritableStream)
- [ ] Virtual host routing (multiple apps on same port)

### Out of Scope

- Toolchain/CLI for bundling/deploying — v2+ (manual folder deployment works)
- KV storage API — v2+ (use external storage initially)
- Built-in HTTPS termination — use external reverse proxy
- Node.js API compatibility — Workers API only
- WebSocket support — v2+
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

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Zig over Rust | Better C++ interop, arena allocators, learning goal | Good — clean V8 integration |
| V8 over JSC | Better documented embedding, snapshot system | Good — stable runtime |
| Workers API over Node API | Simpler surface, isolation-friendly, portable | Good — clean API |
| Ports-first routing | Simple start, external proxy handles SSL/vhosts | Good — works for MVP |
| Script caching over snapshots | Snapshots too complex (callback serialization) | Good — fast enough for v1 |
| Single-threaded MVP | Isolate pooling adds complexity | Good — simpler debugging |
| libxev for event loop | Cross-platform, async I/O | Good — timer + fetch work |

---
*Last updated: 2026-01-26 after v1.0 milestone*
