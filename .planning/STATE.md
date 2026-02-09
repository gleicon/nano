# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-01)

**Core value:** Skip the container fleet entirely — one process hosts many isolated JS apps
**Current focus:** Phase v1.2-06 Documentation Site — plan 01 of 2 complete

## Current Position

Phase: v1.2-06 of 6 (Documentation Site)
Plan: 2 of 2 complete
Status: Complete — All documentation complete (34 pages)
Last activity: 2026-02-09 — Completed v1.2-06-02 API reference and deployment documentation

Progress: [##########] 100% (v1.0)
Progress: [##########] 100% (v1.1)
Progress: [##########] 100% (v1.2)

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
- v1.2: 13 plans complete (6 phases done)
- Total: 33 plans, 14 phases

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

**Recent (v1.2-06-02):**
- Document all B-01 through B-08 limitations in api/limitations.md with workarounds
- Explain WinterCG property-as-method pattern in diffs-from-workers.md
- Provide complete working configs for Nginx and Caddy (not partial snippets)
- Document graceful shutdown with realistic deployment workflows
- 34 total documentation pages created (11 from 06-01 + 23 from 06-02)

### Pending Todos

None.

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-02-09
Stopped at: Completed v1.2-06-02-PLAN.md (API reference and deployment documentation)
Resume file: None

## Next Steps

**Phase v1.2-06 COMPLETE** (2/2 plans done). All v1.2 phases complete.

**v1.2 Milestone Status:** READY TO SHIP
- 6 phases complete (v1.2-01 through v1.2-06)
- 13 plans executed
- Documentation site complete with 34 pages

**Ready for:**
- Optional: Deploy documentation site to static hosting (Vercel, Netlify, GitHub Pages)
- Optional: Announce v1.2 release with documentation link
- v1.3 planning (buffer limits, async fetch, crypto expansion, WinterCG essentials)

---
*Last updated: 2026-02-09 after v1.2-06-02 completion (v1.2 milestone complete)*
