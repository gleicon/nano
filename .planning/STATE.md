# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-01)

**Core value:** Skip the container fleet entirely — one process hosts many isolated JS apps
**Current focus:** Phase v1.2-06 Documentation Site — plan 01 of 2 complete

## Current Position

Phase: v1.2-06 of 6 (Documentation Site)
Plan: 1 of 2 complete
Status: In progress — Documentation foundation complete, API reference and deployment docs next
Last activity: 2026-02-09 — Completed v1.2-06-01 documentation foundation

Progress: [##########] 100% (v1.0)
Progress: [##########] 100% (v1.1)
Progress: [#########░] 92% (v1.2)

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
- v1.2: 11 plans complete (5.5 phases done)
- Total: 31 plans, 13.5 phases

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

**Recent (v1.2-06-01):**
- Astro + Starlight chosen for documentation site (fast, built-in search, MDX support)
- Auto-generate sidebars from filesystem structure for maintainability
- Starlight v0.33+ requires social config as array format (not object)
- Complete config.json reference documented with all fields and constraints

### Pending Todos

None.

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-02-09
Stopped at: Completed v1.2-06-01-PLAN.md (documentation foundation)
Resume file: None

## Next Steps

Phase v1.2-06 in progress (1/2 plans complete). Ready to proceed with plan 02 (API reference and deployment docs).

**v1.2-06-01 Plan Complete:**
- Astro + Starlight documentation site scaffolded with NANO branding
- Getting Started guides (installation, first app tutorial)
- Complete config.json schema reference with all fields
- Configuration examples for 6 common scenarios
- CLI options documented (serve, run, REPL)
- Site builds successfully, search working, 11 pages indexed

**Ready for:**
- v1.2-06-02: API Reference and Deployment Documentation

---
*Last updated: 2026-02-09 after v1.2-06-01 completion*
