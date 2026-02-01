# Summary: v1.1 Phase 1 - Multi-App Virtual Host Routing

## Status: Complete

## What Was Built

Virtual host routing enabling multiple JavaScript apps on a single port, routed by HTTP Host header.

### Deliverables

1. **src/config.zig** - Extended config parser
   - Added `hostname` field to AppConfig
   - Added global `port` field to Config
   - Hostname defaults to app name if not specified

2. **src/server/http.zig** - Multi-app HTTP server
   - `apps: StringHashMap(*App)` for hostname → app lookup
   - `extractHostHeader()` parses Host from requests
   - Falls back to default_app for unknown hosts
   - Proper cleanup of hostname keys and app storage

3. **src/server/app.zig** - V8 isolate fixes
   - Added `isolate.enter()/exit()` around request handling
   - Fixed isolate cleanup in deinit
   - Supports concurrent isolates for multi-app

4. **src/main.zig** - Updated CLI
   - `serveMultiApp()` now loads all apps from config
   - Logs each app's hostname and settings

### Key Implementation Details

- Host header parsed case-insensitively
- Port stripped from Host value (e.g., "app.local:8080" → "app.local")
- First app in config becomes default for unmatched hosts
- Each app maintains separate V8 isolate for memory isolation

## Verification

```bash
# Start multi-app server
./zig-out/bin/nano serve --config test/multi-app/nano.json

# Test routing
curl -H "Host: a.local" http://localhost:8080/  # → app-a
curl -H "Host: b.local" http://localhost:8080/  # → app-b
curl -H "Host: unknown" http://localhost:8080/  # → app-a (default)
```

## Commits

- 362347d: feat(v1.1): add multi-app virtual host routing
- 4b3a6c0: test(v1.1): add multi-app routing test fixtures
