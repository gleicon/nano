---
phase: v1.1-01-multi-app-server
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - src/server/http.zig
  - src/main.zig
autonomous: true

must_haves:
  truths:
    - "Multiple apps load from config file"
    - "Host header routes to correct app"
    - "Unknown hosts return 404"
    - "Apps share single port"
  artifacts:
    - path: "src/server/http.zig"
      provides: "Multi-app HTTP server"
      exports: ["HttpServer", "serveMultiApp"]
---

<objective>
Implement virtual host routing: multiple apps on a single port, routed by Host header.

Purpose: Enable hosting multiple Workers-style apps on one NANO instance, Cloudflare-style.

Output: `nano serve --config nano.json` loads all apps on port 8080, routes by Host.
</objective>

<context>
Current state:
- config.zig parses multi-app config (name, path, port, timeout, memory)
- HttpServer holds single `app: ?App`
- serveMultiApp() only starts first app (TODO comment)

Target state:
- HttpServer holds `apps: StringHashMap(App)` keyed by hostname
- Parse Host header from request
- Route to matching app
- 404 for unknown hosts
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add multi-app support to HttpServer</name>
  <files>src/server/http.zig</files>
  <action>
1. Change `app: ?App` to `apps: std.StringHashMap(*app_module.App)`
2. Add `default_app: ?*app_module.App` for fallback
3. Add `loadApps(config: Config)` method
4. Modify `handleConnection` to:
   - Extract Host header from request
   - Look up app in apps HashMap
   - Use default_app or return 404 if not found
5. Update deinit to clean up all apps
  </action>
  <verify>
Build succeeds.
  </verify>
</task>

<task type="auto">
  <name>Task 2: Implement Host header parsing</name>
  <files>src/server/http.zig</files>
  <action>
Add function to extract Host header from HTTP request:
- Scan headers for "Host:" (case-insensitive)
- Extract value, strip port if present
- Return hostname for app lookup
  </action>
  <verify>
Build succeeds.
  </verify>
</task>

<task type="auto">
  <name>Task 3: Update serveMultiApp to load all apps</name>
  <files>src/main.zig</files>
  <action>
Modify serveMultiApp() to:
1. Create HttpServer with shared port from config (or first app's port)
2. Call server.loadApps(cfg) to load all apps
3. Remove TODO comment and single-app limitation
4. Log all loaded apps with their hostnames
  </action>
  <verify>
`nano serve --config nano.json` loads multiple apps.
  </verify>
</task>

<task type="auto">
  <name>Task 4: Add hostname to AppConfig</name>
  <files>src/config.zig</files>
  <action>
Add `hostname: []const u8` field to AppConfig.
This is the Host header value used for routing.
Parse from config JSON.
  </action>
  <verify>
Config with "hostname" field parses correctly.
  </verify>
</task>

</tasks>

<success_criteria>
- Config file with 2+ apps loads successfully
- Request with `Host: app-a.local` hits app-a handler
- Request with `Host: app-b.local` hits app-b handler
- Request with unknown Host gets 404
- Apps share single port (from config or CLI)
</success_criteria>
