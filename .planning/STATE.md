# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-01)

**Core value:** Skip the container fleet entirely — one process hosts many isolated JS apps
**Current focus:** Phase v1.2-05 API Spec Compliance — Plan 02 complete (Headers/Blob/crypto binary support)

## Current Position

Phase: v1.2-05 of 6 (API Spec Compliance)
Plan: 2 of 3 complete
Status: Plan 02 complete — Headers API fixes and binary data support
Last activity: 2026-02-09 — Completed v1.2-05-02 Headers/Blob/crypto binary support

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
- v1.2: 9 plans complete (4 phases done + v1.2-05 plans 1-2)
- Total: 29 plans, 12 phases

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

### Pending Todos

None.

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-02-09
Stopped at: Completed v1.2-05-02-PLAN.md (Headers/Blob/crypto binary support)
Resume file: None

## Next Steps

Phase v1.2-05 plan 02 complete (2/3 plans). Continue with:
- v1.2-05-03: Final compliance fixes (remaining spec gaps)

**v1.2-05-02 Deliverables Complete:**
- Headers.delete() properly removes keys (undefined marker + _keys rebuild)
- Headers.append() with WHATWG comma-separated multi-value
- Blob/File constructors accept ArrayBuffer and Uint8Array parts
- crypto.subtle.digest accepts ArrayBuffer/Uint8Array input

**Remaining for v1.2-05:**
- Plan 03: Final compliance fixes per RESEARCH.md

---
*Last updated: 2026-02-09 after v1.2-05-02 completion*
