---
phase: v1.1-02-app-lifecycle-hot-reload
plan: 02
subsystem: runtime
tags: [admin-api, rest, json, app-management, http]

dependency-graph:
  requires: [v1.1-02-01]
  provides: [admin-api, runtime-app-management]
  affects: [v1.1-02-03-graceful-shutdown]

tech-stack:
  added: []
  patterns: [admin-routing, json-api, query-string-parsing]

key-files:
  created: []
  modified:
    - src/server/http.zig

decisions:
  - id: admin-path-prefix
    choice: /admin/* prefix for all admin endpoints
    reason: Clear separation from app routes, easy to gate behind auth later
  - id: fixed-buffer-json
    choice: Fixed buffer stream for JSON building
    reason: No allocation needed for small responses, simpler error handling
  - id: protect-last-app
    choice: Prevent removal of last app
    reason: Server needs at least one app to serve requests

metrics:
  duration: 8 minutes
  completed: 2026-02-01
---

# Phase v1.1-02 Plan 02: Admin API Summary

REST Admin API at /admin/* for listing, adding, removing apps and triggering config reload without server restart.

## Performance

- **Duration:** 8 min
- **Started:** 2026-02-01T10:30:00Z
- **Completed:** 2026-02-01T10:38:00Z
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments

- Admin endpoint routing in handleConnection before app routing
- GET /admin/apps returns JSON list with hostname, path, memory_percent, timeout_ms
- POST /admin/apps adds apps dynamically with JSON body
- DELETE /admin/apps?hostname=X removes apps (protects last app)
- POST /admin/reload triggers config file reload
- Proper error responses for all edge cases (400, 404, 405, 409, 500)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add admin endpoint routing** - `98fdce0` (feat)
2. **Task 2: Implement GET /admin/apps** - `a64e1eb` (feat)
3. **Task 3: Implement POST/DELETE admin endpoints** - `134b92d` (feat)

## Files Modified

- `src/server/http.zig` - Added AdminResult struct, handleAdminRequest dispatcher, sendAdminResponse helper, handleListApps, handleAddApp, handleRemoveApp, handleReloadConfig

## API Reference

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/admin/health` | GET | Admin health check |
| `/admin/apps` | GET | List all loaded apps with stats |
| `/admin/apps` | POST | Add new app (JSON: hostname, path, optional name/timeout_ms/memory_mb) |
| `/admin/apps?hostname=X` | DELETE | Remove app by hostname |
| `/admin/reload` | POST | Reload config file |

## Response Examples

**GET /admin/apps:**
```json
{"apps":[{"hostname":"a.local","path":"./test/multi-app/app-a","memory_percent":0.1,"timeout_ms":5000}]}
```

**POST /admin/apps (201):**
```json
{"success":true}
```

**Error responses:**
```json
{"error":"Hostname already exists"}  // 409
{"error":"App not found"}            // 404
{"error":"Method not allowed"}       // 405
```

## Decisions Made

### 1. Admin path prefix routing
**Choice:** Check for /admin/* prefix before extracting Host header
**Reason:** Admin endpoints should be accessible regardless of Host header, allows central management

### 2. Fixed buffer JSON building
**Choice:** Use fixedBufferStream with 8KB buffer for list apps response
**Reason:** Avoids allocations, sufficient for ~100 apps in list

### 3. Protect last app
**Choice:** Return 400 error when trying to delete the last remaining app
**Reason:** Server needs at least one app to handle requests, prevents accidental empty state

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Verification Results

All endpoints tested successfully:
- GET /admin/health - 200 with admin health JSON
- GET /admin/apps - 200 with app list
- POST /admin/apps - 201, new app appears in list
- DELETE /admin/apps?hostname=X - 200, app removed from list
- POST /admin/reload - 200, config reloaded
- Error cases return appropriate 4xx/5xx codes

## Next Phase Readiness

Ready for:
- **02-03-PLAN (Graceful Shutdown):** Admin API provides foundation for drain commands
- **Future:** Admin endpoint authentication (add middleware before admin routing)

No blockers identified.

---
*Phase: v1.1-02-app-lifecycle-hot-reload*
*Completed: 2026-02-01*
