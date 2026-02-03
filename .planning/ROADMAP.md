# Roadmap: NANO v1.2 Production Polish

## Overview

v1.2 adds production-essential features: WinterCG Streams API for streaming responses, per-app environment variables for configuration, graceful shutdown with connection draining, and documentation. The phase order prioritizes low-risk foundation (env vars) before complex streaming and shutdown logic.

## Milestones

- ✅ **v1.0 MVP** - Phases v1.0-01 to v1.0-05 (shipped 2026-01-25)
- ✅ **v1.1 Multi-App Hosting** - Phases v1.1-01 to v1.1-02 (shipped 2026-02-01)
- 🚧 **v1.2 Production Polish** - Phases v1.2-01 to v1.2-05 (in progress)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases v1.0-01 to v1.0-05) - SHIPPED 2026-01-25</summary>

Phases v1.0-01 through v1.0-05 delivered core JavaScript runtime with V8 isolates, Workers-compatible APIs, HTTP server, and safety features.

</details>

<details>
<summary>✅ v1.1 Multi-App Hosting (Phases v1.1-01 to v1.1-02) - SHIPPED 2026-02-01</summary>

**v1.1-01: Multi-App Foundation** - Config-based app loading, virtual host routing, hot reload
**v1.1-02: App Lifecycle** - Admin API for runtime management

</details>

### 🚧 v1.2 Production Polish (In Progress)

**Milestone Goal:** Add Streams API, environment variables, graceful shutdown, and documentation

- [ ] **Phase v1.2-01: Per-App Environment Variables** - Isolated config per app
- [ ] **Phase v1.2-02: Streams Foundation** - ReadableStream/WritableStream core
- [ ] **Phase v1.2-03: Response Body Integration** - Streaming HTTP responses
- [ ] **Phase v1.2-04: Graceful Shutdown** - Connection draining on app removal and process shutdown
- [ ] **Phase v1.2-05: Documentation Site** - Astro + Starlight with WinterCG reference

## Phase Details

### Phase v1.2-01: Per-App Environment Variables

**Goal:** Apps can access isolated environment variables from config

**Depends on:** Phase v1.1-02 (config system exists)

**Requirements:** ENVV-01, ENVV-02, ENVV-03, ENVV-04

**Success Criteria** (what must be TRUE):
1. App can read environment variables via second fetch handler parameter
2. Environment variables are defined in config.json per app
3. App A cannot access App B's environment variables
4. Environment variables update when config is hot-reloaded

**Plans:** TBD

Plans:
- [ ] v1.2-01-01: TBD

### Phase v1.2-02: Streams Foundation

**Goal:** WinterCG-compliant ReadableStream and WritableStream classes work independently

**Depends on:** Nothing (independent feature)

**Requirements:** STRM-01, STRM-02, STRM-03, STRM-04, STRM-05, STRM-06, STRM-07

**Success Criteria** (what must be TRUE):
1. ReadableStream can be created with controller callbacks
2. Reader can read chunks via read() and cancel stream
3. WritableStream can accept writes via writer.write()
4. Backpressure signals work (desiredSize, ready promise)
5. Stream errors propagate correctly through controllers

**Plans:** TBD

Plans:
- [ ] v1.2-02-01: TBD

### Phase v1.2-03: Response Body Integration

**Goal:** HTTP responses support streaming bodies via ReadableStream

**Depends on:** Phase v1.2-02 (streams exist)

**Requirements:** STRM-08, STRM-09

**Success Criteria** (what must be TRUE):
1. Response.body returns a ReadableStream for response content
2. fetch() Response supports streaming consumption via .body.getReader()
3. Large responses can stream without buffering entire content

**Plans:** TBD

Plans:
- [ ] v1.2-03-01: TBD

### Phase v1.2-04: Graceful Shutdown

**Goal:** Process and apps shutdown cleanly with connection draining

**Depends on:** Nothing (independent feature, touches HTTP layer)

**Requirements:** SHUT-01, SHUT-02, SHUT-03, SHUT-04, SHUT-05, SHUT-06

**Success Criteria** (what must be TRUE):
1. SIGTERM/SIGINT stops accepting new connections
2. In-flight requests complete before process exits
3. Removing an app via config watcher drains only that app's connections
4. New requests to draining app receive 503 Service Unavailable
5. Process exits after drain timeout (30s default) even if connections hang

**Plans:** TBD

Plans:
- [ ] v1.2-04-01: TBD

### Phase v1.2-05: Documentation Site

**Goal:** Public documentation site explains NANO setup, APIs, and deployment

**Depends on:** Nothing (documents existing + new features)

**Requirements:** DOCS-01, DOCS-02, DOCS-03, DOCS-04, DOCS-05, DOCS-06

**Success Criteria** (what must be TRUE):
1. Documentation site builds and serves locally via Astro + Starlight
2. Getting started guide walks through first app deployment
3. Config.json schema is fully documented with examples
4. All Workers-compatible APIs are documented with WinterCG compliance notes
5. Production deployment guide covers reverse proxy setup

**Plans:** TBD

Plans:
- [ ] v1.2-05-01: TBD

## Progress

**Execution Order:** v1.2-01 → v1.2-02 → v1.2-03 → v1.2-04 → v1.2-05

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| v1.2-01. Per-App Env Vars | v1.2 | 0/0 | Not started | - |
| v1.2-02. Streams Foundation | v1.2 | 0/0 | Not started | - |
| v1.2-03. Response Body | v1.2 | 0/0 | Not started | - |
| v1.2-04. Graceful Shutdown | v1.2 | 0/0 | Not started | - |
| v1.2-05. Documentation | v1.2 | 0/0 | Not started | - |

---
*Last updated: 2026-02-02 after v1.2 roadmap creation*
