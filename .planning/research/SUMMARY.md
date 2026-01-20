# Research Summary: NANO JavaScript Isolate Runtime

**Project:** NANO - Ultra-dense JavaScript runtime with V8 isolates
**Research Completed:** 2026-01-19
**Overall Confidence:** HIGH

---

## Executive Summary

NANO is viable. The technology stack is proven (V8 + Zig via C shim), the architecture patterns are documented (workerd, Deno), and the API surface is standardized (WinterCG). Key risks are manageable with proper phasing.

---

## Key Findings

### Stack (What to Build With)

| Component | Recommendation | Confidence |
|-----------|---------------|------------|
| **JS Engine** | V8 12.4+ (Node 22 LTS) | HIGH |
| **Language** | Zig 0.14.0 | HIGH |
| **V8 Bindings** | C shim via zig-v8 fork or rusty_v8 headers | MEDIUM |
| **Async I/O** | io_uring (Linux), kqueue (macOS dev) | MEDIUM |

**Critical Insight:** V8 snapshots are mandatory for sub-5ms cold starts. Without snapshots: 40-100ms. With snapshots: <2ms.

### Features (What to Build)

**Table Stakes (Must Have for v1):**
- fetch(), Request, Response, Headers
- URL, URLSearchParams
- TextEncoder/TextDecoder
- console.log/warn/error
- crypto.subtle (digest, sign, verify)
- setTimeout/clearTimeout
- atob/btoa

**Differentiators (Competitive Advantage):**
- Direct local storage access (SQLite, Redis) — impossible for edge platforms
- Per-tenant resource limits with transparency
- Self-hosted alternative to Cloudflare Workers

**Anti-Features (Do NOT Build):**
- Global mutable state persistence
- Full Node.js API surface
- Dynamic code evaluation (eval, Function constructor from strings)
- Unlimited resources (memory, CPU)
- Direct database connections without proxy layer

### Architecture (How to Structure)

**Core Components:**
1. Isolate Manager — V8 lifecycle (create, enter, exit, dispose)
2. Context Factory — Execution contexts with APIs
3. Snapshot Cache — Pre-built blobs for fast cold starts
4. I/O Bridge — fetch, timers mapped to native calls
5. Request Router — HTTP → correct app/isolate
6. Resource Limiter — CPU time, memory quotas

**Isolation Model:**
- **Shared:** V8 platform, snapshot blob, event loop, HTTP socket
- **Isolated:** V8 isolate, global object, memory limits, CPU time

**Build Order:**
1. V8 integration (hello world from Zig)
2. API surface (fetch, console, crypto)
3. HTTP server + routing
4. Snapshots + cold start optimization
5. Resource limits + observability

### Pitfalls (What Will Break)

**Critical (Will Definitely Break If Ignored):**

| Pitfall | Prevention |
|---------|------------|
| HandleScope mismanagement | EscapableHandleScope for returns, never store Local handles |
| Isolate threading violations | One thread per isolate, use Locker if sharing |
| Memory limits not enforced | Set ResourceConstraints at isolate creation |
| CPU time bombs (infinite loops) | Watchdog thread + TerminateExecution() |

**V8-Specific:**
- GC can run at any V8 call — don't hold raw pointers across calls
- TryCatch is scope-based — check HasCaught() immediately
- One context per isolate for multi-tenant (not multiple contexts)

**Zig-Specific:**
- Memory allocated by C++ must be freed by C++
- No closures passed to C — use callconv(.C) functions
- C++ exceptions don't propagate through Zig — wrap in try/catch at boundary

---

## Roadmap Implications

### Phase 1: V8 Foundation
- Build V8 with correct flags (pointer compression, snapshots)
- Create C shim layer using zig-v8 fork approach
- Arena allocator per request pattern
- **Milestone:** `nano eval "1 + 1"` returns `2`

### Phase 2: API Surface
- Start with console.log (validates binding pattern)
- Then Headers → Request → Response → fetch()
- crypto.subtle for auth use cases
- **Milestone:** Run Workers script that fetches URL

### Phase 3: HTTP Server + Multi-App
- Zig HTTP server (std.http or custom)
- App registry (folder → config)
- Request routing by host/path
- **Milestone:** Multiple apps on different ports

### Phase 4: Snapshots + Performance
- Create snapshot with all APIs pre-loaded
- Load isolates from snapshot
- Isolate pooling (warm isolates)
- **Milestone:** p99 cold start < 5ms

### Phase 5: Production Hardening
- CPU watchdog (50ms default timeout)
- Memory limits per isolate (128MB default)
- Structured logging per app
- Prometheus metrics endpoint
- **Milestone:** Can't crash host with runaway script

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| V8 build complexity | HIGH | HIGH | Use pre-built or follow exact GN flags documented |
| Zig C++ interop issues | MEDIUM | HIGH | Use zig-v8 fork, test early |
| Sub-5ms cold start miss | LOW | MEDIUM | Snapshots proven; measure early |
| Memory target miss (<2MB) | MEDIUM | LOW | Pointer compression + constraints; measure |
| API compatibility gaps | MEDIUM | MEDIUM | Start with WinterCG minimum; test against real Workers |

---

## Open Questions (Need Validation)

### Before Phase 1
1. Does zig-v8 fork work with Zig 0.14.0 out of the box?
2. What's the V8 build time on target hardware?

### Before Phase 4
3. What's the snapshot size with full Workers API?
4. What's the actual per-isolate memory overhead?

### Before Production
5. How to handle V8 upgrades without breaking deployed snapshots?
6. io_uring + V8 microtask integration pattern?

---

## Files Reference

| File | Purpose |
|------|---------|
| `STACK.md` | Technology choices, versions, build configuration |
| `FEATURES.md` | API surface, table stakes vs differentiators |
| `ARCHITECTURE.md` | Components, request lifecycle, isolation model |
| `PITFALLS.md` | Known gotchas, prevention strategies |

---

## Bottom Line

**Build NANO.** The path is clear:

1. V8 12.4 + Zig 0.14 + zig-v8 fork is the proven stack
2. WinterCG defines the API surface — no guessing
3. Snapshots solve cold starts — <2ms is achievable
4. Isolate-per-app provides real isolation — unlike shared contexts
5. Arena allocators give instant cleanup — matches Zig's strengths

The main risk is V8 build complexity. Everything else is documented and proven by Cloudflare, Deno, and Lightpanda.

**Next step:** `/gsd:plan-phase 1` to create the V8 foundation.
