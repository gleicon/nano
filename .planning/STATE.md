# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-01)

**Core value:** Skip the container fleet entirely — one process hosts many isolated JS apps
**Current focus:** Phase v1.2-03 Response Body Integration COMPLETE

## Current Position

Phase: v1.2-03 of 5 (Response Body Integration)
Plan: 1 of 1 complete
Status: Phase complete - ready for v1.2-04
Last activity: 2026-02-07 — Completed v1.2-03-01-PLAN.md (Response.body getter, ReadableStream reading fix)

Progress: [##########] 100% (v1.0)
Progress: [##########] 100% (v1.1)
Progress: [########░░] 80% (v1.2)

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
- v1.2: 4 plans (Response Body Integration complete)
- Total: 24 plans, 11 phases

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

**Recent (v1.2-03-01):**
- Response.body must use setAccessorGetter (property) not set (method) for WinterCG spec compliance
- pull()-based ReadableStream avoids start()+close() synchronous hang bug
- After calling pull() in readerRead, must re-check queue (V8 runs JS synchronously)
- Guard V8 pending exceptions: check pull_fn.call() result before further V8 API calls

### Pending Todos

None.

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-02-07
Stopped at: Completed v1.2-03-01 Response Body Integration
Resume file: None

## Next Steps

Phase v1.2-03 complete (1/1 plans). Continue to v1.2-04:
- v1.2-04: Graceful Shutdown

**Phase v1.2-03 Deliverables Complete:**
- Response.body returns ReadableStream for string and stream bodies
- Response constructor accepts ReadableStream body argument
- response.text() and response.json() read from stream bodies
- Pull-based ReadableStream reading works via reader.read()

---
*Last updated: 2026-02-07 after v1.2-03-01 execution*
