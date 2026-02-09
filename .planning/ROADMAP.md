# Roadmap: NANO

## Milestones

- ✅ **v1.0 MVP** — Phases v1.0-01 to v1.0-05 (shipped 2026-01-25)
- ✅ **v1.1 Multi-App Hosting** — Phases v1.1-01 to v1.1-02 (shipped 2026-02-01)
- ✅ **v1.2 Production Polish** — Phases v1.2-01 to v1.2-06 (shipped 2026-02-09)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases v1.0-01 to v1.0-05) — SHIPPED 2026-01-25</summary>

Phases v1.0-01 through v1.0-05 delivered core JavaScript runtime with V8 isolates, Workers-compatible APIs, HTTP server, and safety features.

See `milestones/v1.0-ROADMAP.md` for full details.

</details>

<details>
<summary>✅ v1.1 Multi-App Hosting (Phases v1.1-01 to v1.1-02) — SHIPPED 2026-02-01</summary>

- v1.1-01: Multi-App Foundation — Config-based app loading, virtual host routing, hot reload
- v1.1-02: App Lifecycle — Admin API for runtime management

See `milestones/v1.1-ROADMAP.md` for full details.

</details>

<details>
<summary>✅ v1.2 Production Polish (Phases v1.2-01 to v1.2-06) — SHIPPED 2026-02-09</summary>

- v1.2-01: Per-App Environment Variables — Isolated config per app
- v1.2-02: Streams Foundation — ReadableStream/WritableStream/TransformStream
- v1.2-03: Response Body Integration — Streaming HTTP responses
- v1.2-04: Graceful Shutdown & Stability — Connection draining, V8 timer fixes
- v1.2-05: API Spec Compliance — 24 getter properties, Headers fixes, binary data
- v1.2-06: Documentation Site — 34-page Astro + Starlight site

See `milestones/v1.2-ROADMAP.md` for full details.

</details>

## Known Limitations (from BACKLOG.md)

- B-01: Stack buffer limits (Blob 64KB, fetch 64KB, atob 8KB, console 4KB)
- B-02: Synchronous fetch() blocks event loop
- B-03: WritableStream sync-only sinks
- B-04: crypto.subtle limited to HMAC
- B-05: ReadableStream.tee() data loss
- B-06: Missing WinterCG APIs (structuredClone, queueMicrotask, performance.now)
- B-07: Single-threaded server
- B-08: URL read-only properties

## Future Milestones (placeholder)

- **v1.3 (TBD):** Buffer limits + async fetch + crypto expansion + WinterCG essentials (B-01 through B-06, B-08)
- **v1.4+ (TBD):** Connection pooling / multi-threading (B-07), WebSocket, Cache API

---
*Last updated: 2026-02-09 after v1.2 milestone completion*
