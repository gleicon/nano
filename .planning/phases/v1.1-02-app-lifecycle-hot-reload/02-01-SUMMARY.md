---
phase: v1.1-02-app-lifecycle-hot-reload
plan: 01
subsystem: runtime
tags: [config-watcher, hot-reload, xev-timer, poll-based]

dependency-graph:
  requires: [v1.1-01-multi-app-routing]
  provides: [config-file-watching, hot-reload, app-lifecycle]
  affects: [v1.1-02-02-admin-api, v1.1-02-03-graceful-shutdown]

tech-stack:
  added: []
  patterns: [poll-based-mtime, callback-function-pointer, opaque-pointer]

key-files:
  created: []
  modified:
    - src/runtime/event_loop.zig
    - src/server/http.zig
    - src/main.zig

decisions:
  - id: config-watcher-poll
    choice: Poll-based mtime checking (2s interval)
    reason: libxev lacks filesystem events, std.fs.Watch not stable
  - id: callback-pattern
    choice: Function pointer with opaque server pointer
    reason: Avoid circular import between event_loop and http modules
  - id: debounce-timing
    choice: 500ms debounce after change detection
    reason: Editors often write multiple times during save

metrics:
  duration: 4 minutes
  completed: 2026-02-01
---

# Phase v1.1-02 Plan 01: Config File Watching Summary

Poll-based config watcher using xev.Timer with 2-second interval and 500ms debounce for hot-reloading apps.

## What Was Built

### ConfigWatcher (event_loop.zig)
New struct that polls config file mtime every 2 seconds:
- Uses xev.Timer for async polling
- Stores last_mtime (i128) and last_change_time (i128) for debounce
- Uses function pointer callback to avoid circular imports
- Graceful error handling for temporarily inaccessible files (editor saves)

### HttpServer Hot Reload (http.zig)
Added config watching and reload capability:
- `config_path` and `config_watcher` fields
- `startConfigWatcher()` - initializes and starts polling
- `reloadConfig()` - diffs config and updates apps atomically
- `removeApp()` - graceful removal with V8 cleanup
- `addApp()` - loads new app and registers hostname
- Updated `deinit()` for config watcher cleanup
- Updated `serveMultiApp()` to accept and pass config_path

### main.zig Update
Passes config path to serveMultiApp for hot reload support.

## Key Files Modified

| File | Changes |
|------|---------|
| `src/runtime/event_loop.zig` | Added ConfigWatcher struct with poll-based timer |
| `src/server/http.zig` | Added config watching, reload, add/remove app methods |
| `src/main.zig` | Updated serveMultiApp call to pass config_path |

## Commits

| Hash | Description |
|------|-------------|
| 743774f | Add ConfigWatcher to event_loop.zig |
| cc95ef4 | Add config watcher and reload methods to HttpServer |
| 2c0b4fb | Fix ConfigWatcher type for i128 timestamps |
| 6b268d4 | Pass config path to enable hot reload |

## Decisions Made

### 1. Poll-based watching over filesystem events
**Choice:** Use xev.Timer to check mtime every 2 seconds
**Reason:** libxev doesn't support filesystem events yet, std.fs.Watch is not stable in Zig
**Trade-off:** Slightly higher latency (up to 2s) but simple and portable

### 2. Function pointer callback pattern
**Choice:** Use `ReloadCallback = *const fn (*anyopaque) void`
**Reason:** Avoids circular import between event_loop.zig and http.zig
**Alternative considered:** Import http module from event_loop (would create cycle)

### 3. Debounce timing
**Choice:** 500ms debounce after change detection
**Reason:** Editors often write temp file, rename, update metadata in rapid succession
**Trade-off:** Adds slight delay but prevents multiple rapid reloads

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed i128 type mismatch**
- **Found during:** Task 2 verification
- **Issue:** `std.time.nanoTimestamp()` returns i128, but `last_change_time` was i64
- **Fix:** Changed `last_change_time` and `DEBOUNCE_NS` to i128
- **Files modified:** src/runtime/event_loop.zig
- **Commit:** 2c0b4fb

**2. [Rule 3 - Blocking] Fixed ArrayList API change**
- **Found during:** Task 2 verification
- **Issue:** `std.ArrayList(T).init()` no longer exists in Zig 0.15
- **Fix:** Used `std.ArrayListUnmanaged(T)` with `.{}` initialization pattern
- **Files modified:** src/server/http.zig
- **Commit:** cc95ef4

## Verification

Build verification:
```bash
zig build  # Compiles successfully
```

Runtime verification (manual):
1. Start server: `./zig-out/bin/nano serve --config test/multi-app/nano.json`
2. Observe "config_watcher_started" in logs with poll_interval_ms: 2000
3. Modify test/multi-app/nano.json
4. Within 3 seconds, observe "config_reload_start" and "config_reload_complete"

## Next Phase Readiness

Ready for:
- **02-02-PLAN (Admin API):** Server has addApp/removeApp infrastructure
- **02-03-PLAN (Graceful Shutdown):** Config reload provides atomic swap pattern

No blockers identified.
