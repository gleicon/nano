# Phase 2: App Lifecycle & Hot Reload - Research

**Researched:** 2026-02-01
**Domain:** Zig runtime, file watching, graceful reload, admin APIs
**Confidence:** MEDIUM

## Summary

This phase adds dynamic app management to NANO: adding/removing apps via admin API, watching config files for changes, and graceful app shutdown without dropping requests. The research covers three areas: (1) file watching mechanisms in Zig, (2) graceful reload patterns for zero-downtime, and (3) admin API design.

The primary challenge is that NANO is single-threaded with a blocking accept() loop, and V8 isolate cleanup requires careful ordering. File watching in Zig is immature - libxev doesn't support filesystem events yet, and std.fs.Watch is not yet a stable API. The recommended approach is poll-based mtime checking on a timer, which is simple, portable, and sufficient for config file watching.

For graceful reload, the pattern is: (1) load new app, (2) atomically swap into routing table, (3) drain existing requests to old app, (4) dispose old V8 isolate. Since NANO is single-threaded and synchronous, this simplifies to: load new app, swap pointer, deinit old app (no concurrent requests to old app possible).

**Primary recommendation:** Use poll-based config watching (check mtime every 2-5 seconds), atomic app swaps in the HashMap, and a simple JSON-over-HTTP admin API at `/admin/apps`.

## Standard Stack

Since this is pure Zig with libxev, there are no external libraries to add. The implementation uses existing standard library facilities.

### Core
| Component | Source | Purpose | Why Standard |
|-----------|--------|---------|--------------|
| std.time.Timer | stdlib | Poll interval timing | Built into Zig stdlib |
| std.fs.stat() | stdlib | Check file mtime | Cross-platform file stats |
| std.StringHashMap | stdlib | App registry | Already used for apps |
| xev.Timer | libxev | Async timer for config polling | Already in use for JS timers |

### Supporting
| Component | Source | Purpose | When to Use |
|-----------|--------|---------|-------------|
| std.json | stdlib | Admin API request/response | Already used for config |
| std.atomic.Value | stdlib | Thread-safe counters | If adding metrics for reload |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Poll-based mtime | fzwatch library | External dep, but more responsive |
| Poll-based mtime | std.fs.Watch (future) | Not yet stable API in Zig |
| Poll-based mtime | libxev filesystem events | Not implemented in libxev yet |
| JSON admin API | Binary protocol | JSON simpler, already have parser |

## Architecture Patterns

### Recommended Changes to HttpServer

```
HttpServer (existing):
├── apps: StringHashMap(*App)     # hostname -> App (keep)
├── app_storage: ArrayList(App)   # Owns App memory (keep)
├── default_app: ?*App            # First loaded app (keep)
│
├── config_path: ?[]const u8      # NEW: Path to config file
├── config_mtime: i128            # NEW: Last known mtime
├── reload_timer: ?xev.Timer      # NEW: Poll timer for config changes
│
└── admin_enabled: bool           # NEW: Enable /admin/* endpoints
```

### Pattern 1: Poll-Based Config Watching

**What:** Check config file mtime periodically using a timer, reload if changed.
**When to use:** When event-based file watching is unavailable or unreliable.
**Example:**
```zig
// Source: Zig std.fs.stat API
fn checkConfigChanged(self: *HttpServer) !bool {
    const file = try std.fs.cwd().openFile(self.config_path.?, .{});
    defer file.close();
    const stat = try file.stat();

    if (stat.mtime != self.config_mtime) {
        self.config_mtime = stat.mtime;
        return true;
    }
    return false;
}

// Called from event loop timer callback
fn onConfigPollTimer(self: *HttpServer) void {
    if (self.checkConfigChanged() catch false) {
        self.reloadConfig() catch |err| {
            log.err("config_reload_failed", .{ .error = @errorName(err) });
        };
    }
}
```

### Pattern 2: Atomic App Swap

**What:** Replace app in HashMap without blocking concurrent requests.
**When to use:** When updating an existing app's code/config.
**Example:**
```zig
// Source: Based on Zig HashMap semantics
fn replaceApp(self: *HttpServer, hostname: []const u8, new_app: *App) !?*App {
    // Single-threaded: no locking needed
    // getOrPutAdapted returns pointer to entry
    const result = self.apps.getPtr(hostname);
    if (result) |ptr| {
        const old_app = ptr.*;
        ptr.* = new_app;  // Atomic pointer write
        return old_app;   // Caller deinits after all refs released
    }
    // New hostname - just add
    try self.apps.put(hostname, new_app);
    return null;
}
```

### Pattern 3: Admin API Endpoint Routing

**What:** Handle /admin/* paths before app routing.
**When to use:** For management endpoints.
**Example:**
```zig
// In handleConnection, before app routing:
if (std.mem.startsWith(u8, path, "/admin/")) {
    if (!self.admin_enabled) {
        return self.sendResponse(conn, 403, "text/plain", "Admin API disabled");
    }
    return self.handleAdminRequest(conn, method, path);
}
```

### Anti-Patterns to Avoid

- **Concurrent isolate access:** V8 isolates are not thread-safe. Never access an isolate from multiple threads. NANO's single-threaded design avoids this.
- **Disposing entered isolate:** Always `isolate.exit()` before `isolate.deinit()`. The App.deinit() method already does this correctly.
- **Forgetting persistent handle cleanup:** V8 persistent handles must be `deinit()` before isolate disposal. App.deinit() handles this.
- **Blocking the accept loop for file I/O:** Config reload should be fast. Parse JSON synchronously is fine for small config files.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON parsing | Custom parser | std.json | Already used, well-tested |
| File stat | Raw syscalls | std.fs.stat() | Cross-platform |
| Timer scheduling | Manual polling loop | xev.Timer | Already integrated |
| Hostname comparison | Manual string compare | std.StringHashMap | Already used |

**Key insight:** The existing infrastructure (libxev timers, std.json, HashMap) provides everything needed. No new dependencies required.

## Common Pitfalls

### Pitfall 1: V8 Isolate Disposal Order
**What goes wrong:** Crash when disposing isolate that still has active contexts or handles.
**Why it happens:** V8 requires specific cleanup order: exit context, deinit persistent handles, exit isolate, deinit isolate.
**How to avoid:** Always follow App.deinit() pattern - it correctly orders cleanup.
**Warning signs:** Segfault during app removal or server shutdown.

### Pitfall 2: Memory Leak on App Reload
**What goes wrong:** Old app's V8 heap not fully released, memory grows over time.
**Why it happens:** V8 isolate memory is held until GC runs; Dispose() doesn't guarantee immediate release.
**How to avoid:** Call `lowMemoryNotification()` before dispose, accept that some memory may be retained temporarily.
**Warning signs:** Resident memory grows after repeated reloads.

### Pitfall 3: Race Between Reload and Request
**What goes wrong:** Request routes to app being disposed.
**Why it happens:** In multi-threaded systems, swap and dispose aren't atomic.
**How to avoid:** NANO is single-threaded with synchronous request handling. The swap happens between requests, so no race is possible.
**Warning signs:** N/A for single-threaded design.

### Pitfall 4: Config File Permissions
**What goes wrong:** Reload fails silently or crashes when config file is temporarily inaccessible.
**Why it happens:** File being written by editor (vim swap files, atomic saves).
**How to avoid:** Catch stat/open errors, log warning, retry on next poll cycle.
**Warning signs:** "Permission denied" or "File not found" during normal operation.

### Pitfall 5: Debouncing Config Changes
**What goes wrong:** Multiple rapid reloads when editor saves multiple times.
**Why it happens:** Editors often write temp file, rename, update metadata.
**How to avoid:** Add debounce delay (e.g., 500ms) after detecting change before reload.
**Warning signs:** Log shows multiple reloads in quick succession.

## Code Examples

### Config File Watching with xev Timer
```zig
// Source: Based on NANO's existing event_loop.zig pattern
const ConfigWatcher = struct {
    timer: xev.Timer,
    config_path: []const u8,
    last_mtime: i128,
    server: *HttpServer,

    pub fn init(server: *HttpServer, config_path: []const u8) !ConfigWatcher {
        const file = try std.fs.cwd().openFile(config_path, .{});
        defer file.close();
        const stat = try file.stat();

        return ConfigWatcher{
            .timer = try xev.Timer.init(),
            .config_path = config_path,
            .last_mtime = stat.mtime,
            .server = server,
        };
    }

    pub fn start(self: *ConfigWatcher, loop: *xev.Loop) void {
        // Poll every 2 seconds
        self.timer.run(loop, &self.completion, 2000, ConfigWatcher, self, onTimer);
    }

    fn onTimer(self: ?*ConfigWatcher, loop: *xev.Loop, c: *xev.Completion, result: xev.Timer.RunError!void) xev.CallbackAction {
        _ = result catch return .disarm;
        const watcher = self orelse return .disarm;

        // Check mtime
        const file = std.fs.cwd().openFile(watcher.config_path, .{}) catch return .rearm;
        defer file.close();
        const stat = file.stat() catch return .rearm;

        if (stat.mtime != watcher.last_mtime) {
            watcher.last_mtime = stat.mtime;
            watcher.server.reloadConfig() catch |err| {
                // Log error but keep watching
            };
        }
        return .rearm;  // Continue polling
    }
};
```

### Admin API Handler
```zig
// Source: Based on NANO's handleConnection pattern
fn handleAdminRequest(self: *HttpServer, conn: std.net.Server.Connection, method: []const u8, path: []const u8) !void {
    if (std.mem.eql(u8, path, "/admin/apps")) {
        if (std.mem.eql(u8, method, "GET")) {
            return self.handleListApps(conn);
        } else if (std.mem.eql(u8, method, "POST")) {
            // Add app - read JSON body, parse, load app
            return self.handleAddApp(conn);
        } else if (std.mem.eql(u8, method, "DELETE")) {
            // Remove app - parse hostname from query/body
            return self.handleRemoveApp(conn);
        }
    }
    if (std.mem.eql(u8, path, "/admin/reload")) {
        if (std.mem.eql(u8, method, "POST")) {
            return self.handleReloadConfig(conn);
        }
    }
    try self.sendResponse(conn, 404, "application/json", "{\"error\":\"Not found\"}");
}

fn handleListApps(self: *HttpServer, conn: std.net.Server.Connection) !void {
    // Build JSON array of app info
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try writer.writeAll("{\"apps\":[");
    var first = true;
    var iter = self.apps.iterator();
    while (iter.next()) |entry| {
        if (!first) try writer.writeAll(",");
        first = false;
        try std.json.stringify(.{
            .hostname = entry.key_ptr.*,
            .path = entry.value_ptr.*.app_path,
            .memory_percent = entry.value_ptr.*.getMemoryUsagePercent(),
        }, .{}, writer);
    }
    try writer.writeAll("]}");

    try self.sendResponse(conn, 200, "application/json", fbs.getWritten());
}
```

### Graceful App Removal
```zig
// Source: Based on NANO's App.deinit() pattern
fn removeApp(self: *HttpServer, hostname: []const u8) !void {
    // Find and remove from HashMap
    if (self.apps.fetchRemove(hostname)) |kv| {
        const app_ptr = kv.value;

        // Free the hostname key (we allocated it)
        self.allocator.free(kv.key);

        // Find in storage and mark for removal
        for (self.app_storage.items, 0..) |*stored_app, i| {
            if (stored_app == app_ptr) {
                // Cleanup V8 resources (follows correct order)
                stored_app.deinit();
                _ = self.app_storage.swapRemove(i);
                break;
            }
        }

        // Update default_app if we removed it
        if (self.default_app == app_ptr) {
            self.default_app = if (self.app_storage.items.len > 0)
                &self.app_storage.items[0]
            else
                null;
        }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| inotify/kqueue direct | Poll-based for simplicity | N/A | Simpler, more portable |
| Full server restart | Atomic app swap | Modern practice | Zero-downtime reloads |
| Kill existing connections | Graceful drain | Modern practice | No request drops |

**Not applicable (Zig-specific):**
- std.fs.Watch: Proposed but not yet a stable API
- libxev filesystem events: Listed as future roadmap item
- fzwatch: Third-party option, adds dependency

## Open Questions

1. **Should admin API require authentication?**
   - What we know: Currently no auth mechanism in NANO
   - What's unclear: Whether to add basic auth, API keys, or leave unsecured
   - Recommendation: Add `--admin-token` CLI flag, require Bearer token for admin endpoints

2. **What happens to in-flight requests during app removal?**
   - What we know: NANO is single-threaded, request handling is synchronous
   - What's unclear: Whether long-running async fetch() calls could be interrupted
   - Recommendation: Single-threaded design means request completes before removal can start - no special handling needed

3. **Should removed apps be logged/recorded?**
   - What we know: Currently no audit trail
   - What's unclear: Whether to keep history of app changes
   - Recommendation: Log all add/remove operations with timestamps (defer to phase 3 if complex)

4. **How to handle config parse errors during reload?**
   - What we know: Current parseConfig returns errors
   - What's unclear: Whether to roll back or partial-apply changes
   - Recommendation: Fail reload entirely on parse error, keep existing apps running

## Sources

### Primary (HIGH confidence)
- NANO codebase: src/server/http.zig, src/server/app.zig, src/runtime/event_loop.zig - Direct code analysis
- Zig stdlib: std.fs, std.time, std.json - Standard library documentation

### Secondary (MEDIUM confidence)
- [libxev GitHub](https://github.com/mitchellh/libxev) - README confirms no filesystem events yet
- [V8 Isolate documentation](https://v8.github.io/api/head/classv8_1_1Isolate.html) - Disposal sequence
- [Zig fs.Watch issue #20682](https://github.com/ziglang/zig/issues/20682) - Status of std.fs.Watch
- [graceful reload patterns](https://github.com/kuangchanglang/graceful) - Go patterns for reference

### Tertiary (LOW confidence)
- [fzwatch](https://github.com/freref/fzwatch) - Zig file watcher library (untested)
- WebSearch results on hot reload patterns - General patterns, not Zig-specific

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Using existing NANO dependencies
- Architecture: MEDIUM - Patterns derived from codebase analysis, not battle-tested
- Pitfalls: MEDIUM - V8 disposal issues documented, but Zig-specific edge cases unknown
- File watching: MEDIUM - Poll-based is reliable but libxev integration untested

**Research date:** 2026-02-01
**Valid until:** 60 days (stable domain, no rapid changes expected)

---

## Appendix: Admin API Design

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | /admin/apps | List all loaded apps |
| POST | /admin/apps | Add new app from config |
| DELETE | /admin/apps?hostname=X | Remove app by hostname |
| POST | /admin/reload | Reload config file |
| GET | /admin/health | Admin API health check |

### Request/Response Examples

**GET /admin/apps**
```json
{
  "apps": [
    {
      "hostname": "a.local",
      "name": "app-a",
      "path": "./test/multi-app/app-a",
      "memory_percent": 12.5,
      "requests": 1234
    }
  ]
}
```

**POST /admin/apps**
```json
{
  "name": "new-app",
  "hostname": "new.local",
  "path": "./apps/new-app",
  "timeout_ms": 5000,
  "memory_mb": 64
}
```

**DELETE /admin/apps?hostname=old.local**
```json
{
  "success": true,
  "removed": "old.local"
}
```

**POST /admin/reload**
```json
{
  "success": true,
  "apps_loaded": 3,
  "apps_added": ["new.local"],
  "apps_removed": ["old.local"],
  "apps_unchanged": ["a.local"]
}
```
