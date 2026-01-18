# NANO

## What This Is

NANO is an ultra-dense JavaScript runtime that hosts multiple applications in a single process using V8 isolates. Think of it like a browser with tabs — each tab is an isolated app, but they share one process. Built in Zig with embedded V8, it targets platform engineers who want Cloudflare Workers-like density without container orchestration overhead.

## Core Value

**Skip the container fleet entirely.** One NANO process replaces dozens of Node containers, their image builds, fleet management, and routing infrastructure — while maintaining isolation between apps.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Sub-5ms cold start for new isolates (via V8 snapshots)
- [ ] Hard isolation between apps (memory, CPU, no cross-app access)
- [ ] Workers-compatible API surface (fetch, Request/Response, Headers, console)
- [ ] Folder-based deployment (point at directory, app runs)
- [ ] App name tracking (internal registry for routing)
- [ ] Proper HTTP error responses to clients
- [ ] Structured logging per app
- [ ] <2MB memory overhead per isolate

### Out of Scope

- Toolchain/CLI for bundling/deploying — v2 (start with manual folder deployment)
- KV storage API — v2 (can use external storage initially)
- Built-in HTTPS termination — use external reverse proxy
- Node.js API compatibility — Workers API only
- WebSocket support — v2
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

- **Runtime**: Zig 0.13.0+ stable (avoid nightly instability)
- **V8 version**: Pin to V8 12.x LTS (Node 22 compatibility)
- **Platform**: Linux first (io_uring), macOS for development
- **API surface**: Workers-compatible (code portable from Vercel/Cloudflare)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Zig over Rust | Better C++ interop, arena allocators, learning goal | — Pending |
| V8 over JSC | Better documented embedding, snapshot system | — Pending |
| Workers API over Node API | Simpler surface, isolation-friendly, portable | — Pending |
| Ports-first routing | Simple start, external proxy handles SSL/vhosts | — Pending |

---
*Last updated: 2025-01-18 after initialization*
