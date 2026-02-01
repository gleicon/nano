# NANO Roadmap

## Current Milestone: v1.1 Multi-App Hosting

**Goal:** Transform NANO from single-app to multi-app runtime with virtual host routing on a single port.

**Target features:**
- Multi-app registry (load multiple apps from config)
- Virtual host routing (Host header -> app routing on same port)
- Per-app configuration (limits, entry point)

---

## Phases

### Phase 1: Multi-App Server

**Goal:** HttpServer holds and routes to multiple apps based on Host header.

**Requirements:** MULTI-01, MULTI-02

**Key changes:**
- `HttpServer.apps` as HashMap (host -> App)
- Parse Host header from incoming requests
- Route request to correct app based on Host
- Default app for unmatched hosts

**Success criteria:**
- Two apps loaded from config
- Request with `Host: app-a.local` routes to app-a
- Request with `Host: app-b.local` routes to app-b
- Unknown hosts get 404 or default response

**Plans:** 1 plan
- [x] 01-PLAN.md - Multi-app virtual host routing

---

### Phase 2: App Lifecycle & Hot Reload (Optional)

**Goal:** Support app addition/removal without server restart.

**Requirements:** MULTI-03

**Key changes:**
- Add/remove apps via API endpoint
- File watcher for config changes
- Graceful app shutdown

**Success criteria:**
- `/admin/apps` endpoint lists loaded apps
- Config file change triggers reload
- No request drops during reload

**Plans:** 2 plans
- [ ] 02-01-PLAN.md - Config file watcher and reload infrastructure
- [ ] 02-02-PLAN.md - Admin API endpoints for app management

---

## Progress

| Phase | Name | Status | Plans |
|-------|------|--------|-------|
| 1 | Multi-App Server | Complete | 1/1 |
| 2 | App Lifecycle | In Progress | 0/2 |

Progress: █████░░░░░ 50%

---

## Requirements Traceability

| REQ-ID | Requirement | Phase | Status |
|--------|-------------|-------|--------|
| MULTI-01 | Load multiple apps from config | 1 | Complete |
| MULTI-02 | Route by Host header on single port | 1 | Complete |
| MULTI-03 | Hot reload apps without restart | 2 | Pending |

---

*Last updated: 2026-02-01*
