# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-01)

**Core value:** Skip the container fleet entirely — one process hosts many isolated JS apps
**Current focus:** Phase v1.2-02 Streams Foundation COMPLETE

## Current Position

Phase: v1.2-02 of 5 (Streams Foundation)
Plan: 3 of 3 complete
Status: Phase complete - ready for v1.2-03
Last activity: 2026-02-07 — Completed v1.2-02-03-PLAN.md (TransformStream, Pipe Operations, Utilities)

Progress: [##########] 100% (v1.0)
Progress: [##########] 100% (v1.1)
Progress: [######░░░░] 60% (v1.2)

## Shipped Milestones

| Version | Name | Phases | Plans | Shipped |
|---------|------|--------|-------|---------|
| v1.0 | MVP | 6 | 14 | 2026-01-26 |
| v1.1 | Multi-App Hosting | 2 | 3 | 2026-02-01 |

See `.planning/MILESTONES.md` for details.

## Performance Metrics

**Velocity:**
- v1.0: 14 plans in 8 days
- v1.1: 3 plans in 14 days (includes research + audit time)
- v1.2: 3 plans (Streams Foundation complete)
- Total: 23 plans, 10 phases

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Key architectural decisions:
- Zig + V8 for memory control and battle-tested JS engine
- Workers API over Node API for simpler surface
- Single-threaded MVP (pooling deferred)
- Poll-based config watching (libxev lacks filesystem events)
- Function pointer callbacks avoid circular imports
- Admin /admin/* prefix for clear API separation

**Recent (v1.2-01-01):**
- Deep copy env HashMap for hot-reload safety (prevents use-after-free)
- Pass env as second fetch parameter (Cloudflare Workers pattern)
- Empty env object when no vars defined (consistent API)

**Recent (v1.2-02-01):**
- Simplified async for MVP - full pending reads deferred to future iteration
- Per-app stream buffer size limits (config.json max_buffer_size_mb, default 64MB)
- V8 handle-based conversions for Boolean, Promise, Array types

**Recent (v1.2-02-03):**
- Embedded JavaScript for complex async stream operations (TransformStream, pipeTo, tee)
- V8 Function.call() pattern simpler than replicating full async state machines in Zig
- Simplified tee() implementation without perfect reader sharing (MVP focus)

### Pending Todos

None.

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-02-07
Stopped at: Completed v1.2-02-03 TransformStream, Pipe Operations, Utilities
Resume file: None

## Next Steps

Phase v1.2-02 complete (3/3 plans). Continue to v1.2-03:
- v1.2-03: HTTP Response Body Integration

**Phase v1.2-02 Deliverables Complete:**
- ReadableStream, WritableStream, TransformStream APIs
- pipeTo(), pipeThrough(), tee(), from() operations
- TextEncoderStream, TextDecoderStream
- Async iteration support
- Per-app buffer limits and backpressure

---
*Last updated: 2026-02-07 after v1.2-02-03 execution*
