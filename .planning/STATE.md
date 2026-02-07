# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-01)

**Core value:** Skip the container fleet entirely — one process hosts many isolated JS apps
**Current focus:** Phase v1.2-02 Streams Foundation

## Current Position

Phase: v1.2-02 of 5 (Streams Foundation)
Plan: 01 of 3 complete
Status: In progress
Last activity: 2026-02-07 — Completed v1.2-02-01-PLAN.md (ReadableStream Foundation)

Progress: [##########] 100% (v1.0)
Progress: [##########] 100% (v1.1)
Progress: [####░░░░░░] 40% (v1.2)

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
- v1.2: 2 plans (in progress: ReadableStream, WritableStream complete)
- Total: 20 plans, 9 phases

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

### Pending Todos

None.

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-02-07
Stopped at: Completed v1.2-02-01 ReadableStream Foundation
Resume file: None

## Next Steps

Phase v1.2-02 in progress (1/3 plans complete). Continue with remaining plans:
- v1.2-02-02: WritableStream (parallel - likely complete)
- v1.2-02-03: HTTP Response Body Integration

---
*Last updated: 2026-02-07 after v1.2-02-01 execution*
