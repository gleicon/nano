# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-01)

**Core value:** Skip the container fleet entirely — one process hosts many isolated JS apps
**Current focus:** Phase v1.2-05 API Spec Compliance COMPLETE — ready for verification

## Current Position

Phase: v1.2-05 of 6 (API Spec Compliance)
Plan: 3 of 3 complete
Status: Phase complete — All WinterCG spec compliance fixes verified end-to-end
Last activity: 2026-02-09 — Completed v1.2-05-03 spec compliance verification

Progress: [##########] 100% (v1.0)
Progress: [##########] 100% (v1.1)
Progress: [#########░] 83% (v1.2)

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
- v1.2: 10 plans complete (5 phases done)
- Total: 30 plans, 13 phases

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

**Recent (v1.2-05-02):**
- Headers.delete() requires rebuilding _keys array to properly remove deleted entries from iteration
- Headers.append() uses WHATWG comma-separated multi-value pattern for headers like Set-Cookie
- V8 BackingStore pattern (getData + @ptrCast) is standard for ArrayBuffer/Uint8Array access
- Binary data support extends to Blob/File constructors and crypto.subtle.digest

**Recent (v1.2-05-03):**
- console.log uses V8 global JSON.stringify for object inspection (not toString())
- Response.ok correctly returns true for 2xx status range (200-299 inclusive)
- Response statusText now maps status codes to standard reason phrases via std.http.Status.phrase()
- crypto.subtle.digest with binary Uint8Array input verified working (await works in fetch handlers)
- All WinterCG spec compliance fixes verified end-to-end via test app

### Pending Todos

None.

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-02-09
Stopped at: Completed v1.2-05-03-PLAN.md (spec compliance verification)
Resume file: None

## Next Steps

Phase v1.2-05 complete (3/3 plans). Ready to proceed with phase v1.2-06 (Graceful Shutdown).

**v1.2-05 Phase Complete:**
- All WinterCG spec properties converted to getters (no parentheses needed)
- Headers.delete() and Headers.append() fully functional
- Binary data support for Blob/File constructors and crypto.subtle.digest
- console.log object inspection using JSON.stringify
- Comprehensive end-to-end verification via test app

**Ready for:**
- v1.2-06: Documentation Site

---
*Last updated: 2026-02-09 after v1.2-05-03 completion*
