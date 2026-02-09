# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-01)

**Core value:** Skip the container fleet entirely — one process hosts many isolated JS apps
**Current focus:** Phase v1.2-05 API Spec Compliance — Plan 01 complete (properties to getters)

## Current Position

Phase: v1.2-05 of 6 (API Spec Compliance)
Plan: 1 of 3 complete
Status: Plan 01 complete — converted 24 WinterCG properties to accessor getters
Last activity: 2026-02-09 — Completed v1.2-05-01 property-to-getter migration

Progress: [##########] 100% (v1.0)
Progress: [##########] 100% (v1.1)
Progress: [########░░] 78% (v1.2)

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
- v1.2: 8 plans complete (4 phases done + v1.2-05 plan 1)
- Total: 28 plans, 12 phases

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

**Recent (v1.2-04):**
- xev timer .rearm causes infinite spin with run(.no_wait) — use manual timer.run() with .disarm instead
- processEventLoop must enter V8 isolate/HandleScope/Context independently of handleRequest
- TryCatch around timer callbacks prevents exceptions from corrupting V8 state
- DOMException not available in NANO runtime — use Error with name="TimeoutError"
- js.throw() and js.retResolvedPromise/retRejectedPromise helpers eliminate boilerplate
- Always force rebuild (rm -rf .zig-cache) — stale binaries cause phantom bugs

**Recent (v1.2-05-01):**
- setAccessorGetter with .toName() is the standard pattern for all WinterCG spec properties
- Getter vs method distinction: properties that return data use getters, actions (text/json/etc) use methods

### Pending Todos

None.

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-02-09
Stopped at: Completed v1.2-05-01-PLAN.md (property-to-getter migration)
Resume file: None

## Next Steps

Phase v1.2-05 plan 01 complete (1/3 plans). Continue with:
- v1.2-05-02: Headers API fixes (delete, append, entries iteration)
- v1.2-05-03: Remaining compliance (Blob binary parts, crypto BufferSource, console inspection)

**v1.2-05-01 Deliverables Complete:**
- 24 WinterCG properties converted to V8 accessor getters
- blob.zig: Blob.size/type, File.size/type/name/lastModified
- request.zig: Request.url/method/headers
- fetch.zig: Response.status/ok/statusText/headers
- url.zig: URL href/origin/protocol/host/hostname/port/pathname/search/hash
- abort.zig: AbortController.signal

**Remaining pre-existing issues for v1.2-05:**
- Headers.delete/append, Blob binary parts, crypto digest BufferSource
- console.log object inspection

---
*Last updated: 2026-02-09 after v1.2-05-01 completion*
