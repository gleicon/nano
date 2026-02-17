const std = @import("std");
const posix = std.posix;
const v8 = @import("v8");
const app_module = @import("app");
const log = @import("log");
const metrics_mod = @import("metrics");
const event_loop_mod = @import("event_loop");
const EventLoop = event_loop_mod.EventLoop;
const ConfigWatcher = event_loop_mod.ConfigWatcher;
const timers = @import("timers");
const fetch_api = @import("fetch");
const config_mod = @import("config");

// Get the actual type from the function return type
const ArrayBufferAllocator = @TypeOf(v8.createDefaultArrayBufferAllocator());

/// Per-app connection tracking for graceful drain
const AppDrainState = struct {
    active_connections: u64 = 0,
    draining: bool = false,
    drain_start_ns: i128 = 0,
};

pub const HttpServer = struct {
    address: std.net.Address,
    server: std.net.Server,
    running: bool,
    // Single app mode (backwards compatible)
    app: ?app_module.App,
    // Multi-app mode: hostname -> App
    apps: std.StringHashMap(*app_module.App),
    app_storage: std.ArrayList(app_module.App), // Owns the App memory
    default_app: ?*app_module.App,
    allocator: std.mem.Allocator,
    platform: v8.Platform,
    array_buffer_allocator: ArrayBufferAllocator,
    request_counter: u64,
    metrics: metrics_mod.Metrics,
    event_loop: EventLoop,
    // Config file watching for hot reload
    config_path: ?[]const u8,
    config_watcher: ?ConfigWatcher,
    // Admin API
    admin_enabled: bool,
    // Per-app connection tracking for graceful shutdown
    app_drain_state: std.StringHashMap(AppDrainState),

    pub fn init(port: u16, allocator: std.mem.Allocator) !HttpServer {
        const address = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, port);
        const tcp_server = try address.listen(.{
            .reuse_address = true,
        });

        // Initialize V8 platform once for the server
        const platform = v8.Platform.initDefault(0, false);
        v8.initV8Platform(platform);
        v8.initV8();

        // Create shared array buffer allocator
        const array_buffer_allocator = v8.createDefaultArrayBufferAllocator();

        // Initialize event loop for async operations
        const event_loop = try EventLoop.init(allocator);

        return HttpServer{
            .address = address,
            .server = tcp_server,
            .running = true,
            .app = null, // Single app mode (backwards compatible)
            .apps = std.StringHashMap(*app_module.App).init(allocator), // Multi-app mode
            .app_storage = .empty,
            .default_app = null,
            .allocator = allocator,
            .platform = platform,
            .array_buffer_allocator = array_buffer_allocator,
            .request_counter = 0,
            .metrics = metrics_mod.Metrics.init(),
            .event_loop = event_loop,
            .config_path = null,
            .config_watcher = null,
            .admin_enabled = true,
            .app_drain_state = std.StringHashMap(AppDrainState).init(allocator),
        };
    }

    /// Load app after server init (event loop pointer must be stable first)
    pub fn loadApp(self: *HttpServer, app_path: []const u8) !void {
        // Set global event loop reference BEFORE loading app (app init may use timers)
        timers.setEventLoop(&self.event_loop);
        fetch_api.setEventLoop(&self.event_loop);

        self.app = app_module.loadApp(self.allocator, app_path, self.array_buffer_allocator, null, null) catch |err| {
            logError("Failed to load app", app_path, err);
            return err;
        };

        // Set event loop reference on the app for async handler support
        if (self.app) |*a| {
            a.event_loop = &self.event_loop;
        }
    }

    /// Load multiple apps from config (virtual host mode)
    pub fn loadApps(self: *HttpServer, cfg: config_mod.Config) !void {
        // Set global event loop reference BEFORE loading apps
        timers.setEventLoop(&self.event_loop);
        fetch_api.setEventLoop(&self.event_loop);

        var logger = log.stdout();

        for (cfg.apps) |app_cfg| {
            // Load the app
            var loaded_app = app_module.loadApp(self.allocator, app_cfg.path, self.array_buffer_allocator, app_cfg.env, app_cfg.max_buffer_size_mb) catch |err| {
                logError("Failed to load app", app_cfg.name, err);
                continue; // Skip failed apps, continue loading others
            };

            // Apply config settings
            loaded_app.timeout_ms = app_cfg.timeout_ms;
            loaded_app.memory_limit_mb = app_cfg.memory_mb;
            loaded_app.event_loop = &self.event_loop;

            // Store the app
            try self.app_storage.append(self.allocator, loaded_app);
            const app_ptr = &self.app_storage.items[self.app_storage.items.len - 1];

            // Register hostname -> app mapping
            // Need to dupe the hostname since cfg will be freed
            const hostname_key = try self.allocator.dupe(u8, app_cfg.hostname);
            try self.apps.put(hostname_key, app_ptr);

            // Register connection tracking for this app
            try self.app_drain_state.put(hostname_key, AppDrainState{});

            // First app becomes default
            if (self.default_app == null) {
                self.default_app = app_ptr;
            }

            logger.info("app_loaded", .{
                .name = app_cfg.name,
                .hostname = app_cfg.hostname,
                .path = app_cfg.path,
            });
        }

        logger.info("multi_app_ready", .{
            .app_count = self.app_storage.items.len,
            .port = self.address.getPort(),
        });
    }

    /// Start watching config file for changes (hot reload)
    pub fn startConfigWatcher(self: *HttpServer, path: []const u8) !void {
        var logger = log.stdout();

        // Store config path (dupe it since original may be freed)
        self.config_path = try self.allocator.dupe(u8, path);

        // Initialize config watcher with callback to reloadConfigCallback
        self.config_watcher = try ConfigWatcher.init(
            self.config_path.?,
            @ptrCast(self),
            reloadConfigCallback,
        );

        // Start the watcher on the event loop
        self.config_watcher.?.start(&self.event_loop.loop);

        logger.info("config_watcher_started", .{
            .path = path,
            .poll_interval_ms = 2000,
        });
    }

    /// Callback invoked by ConfigWatcher when config file changes
    fn reloadConfigCallback(server_ptr: *anyopaque) void {
        const self: *HttpServer = @ptrCast(@alignCast(server_ptr));
        self.reloadConfig() catch |err| {
            var logger = log.stderr();
            logger.err("config_reload_failed", .{
                .@"error" = @errorName(err),
            });
        };
    }

    /// Reload config file and update apps
    pub fn reloadConfig(self: *HttpServer) !void {
        const path = self.config_path orelse return error.NoConfigPath;

        var logger = log.stdout();
        logger.info("config_reload_start", .{
            .path = path,
        });

        // Load new config
        var new_cfg = config_mod.loadConfig(self.allocator, path) catch |err| {
            // Parse error - log but don't crash, keep existing apps running
            var err_logger = log.stderr();
            err_logger.err("config_parse_error", .{
                .path = path,
                .@"error" = @errorName(err),
            });
            return err;
        };
        defer new_cfg.deinit();

        // Build set of new hostnames
        var new_hostnames = std.StringHashMap(config_mod.AppConfig).init(self.allocator);
        defer new_hostnames.deinit();

        for (new_cfg.apps) |app_cfg| {
            try new_hostnames.put(app_cfg.hostname, app_cfg);
        }

        // Find apps to remove (in current but not in new)
        var to_remove: std.ArrayListUnmanaged([]const u8) = .{};
        defer to_remove.deinit(self.allocator);

        var current_iter = self.apps.keyIterator();
        while (current_iter.next()) |key| {
            if (!new_hostnames.contains(key.*)) {
                try to_remove.append(self.allocator, key.*);
            }
        }

        // Remove old apps
        var removed_count: usize = 0;
        for (to_remove.items) |hostname| {
            self.removeApp(hostname);
            removed_count += 1;
        }

        // Find apps to add (in new but not in current)
        var added_count: usize = 0;
        var new_iter = new_hostnames.iterator();
        while (new_iter.next()) |entry| {
            if (!self.apps.contains(entry.key_ptr.*)) {
                self.addApp(entry.value_ptr.*) catch |err| {
                    var err_logger = log.stderr();
                    err_logger.err("app_add_failed", .{
                        .hostname = entry.key_ptr.*,
                        .@"error" = @errorName(err),
                    });
                    continue;
                };
                added_count += 1;
            }
        }

        // Detect changed apps (same hostname, different path) — remove and re-add
        var changed_count: usize = 0;
        var change_iter = new_hostnames.iterator();
        while (change_iter.next()) |entry| {
            if (self.apps.get(entry.key_ptr.*)) |existing_app| {
                // Compare paths: if different, the app script changed
                if (!std.mem.eql(u8, existing_app.app_path, entry.value_ptr.*.path)) {
                    self.removeApp(entry.key_ptr.*);
                    self.addApp(entry.value_ptr.*) catch |err| {
                        var err_logger = log.stderr();
                        err_logger.err("app_reload_failed", .{
                            .hostname = entry.key_ptr.*,
                            .@"error" = @errorName(err),
                        });
                        continue;
                    };
                    changed_count += 1;
                }
            }
        }

        const unchanged_count = self.apps.count() - added_count - changed_count;

        logger.info("config_reload_complete", .{
            .added = added_count,
            .removed = removed_count,
            .changed = changed_count,
            .unchanged = unchanged_count,
        });
    }

    /// Remove an app by hostname (drains active connections first)
    fn removeApp(self: *HttpServer, hostname: []const u8) void {
        var logger = log.stdout();

        // Mark app as draining to prevent new connections (returns 503)
        if (self.app_drain_state.getPtr(hostname)) |drain| {
            drain.draining = true;
            drain.drain_start_ns = std.time.nanoTimestamp();
        }

        logger.info("app_drain_start", .{ .hostname = hostname });

        // Wait for active connections to complete (with 30s timeout)
        const drain_timeout_ns: i128 = 30_000 * 1_000_000;
        const drain_start = std.time.nanoTimestamp();

        while (true) {
            if (self.app_drain_state.get(hostname)) |drain| {
                if (drain.active_connections == 0) {
                    logger.info("app_drained", .{ .hostname = hostname });
                    break;
                }
                const elapsed = std.time.nanoTimestamp() - drain_start;
                if (elapsed > drain_timeout_ns) {
                    var warn_logger = log.stderr();
                    warn_logger.err("app_drain_timeout", .{
                        .hostname = hostname,
                        .active = drain.active_connections,
                    });
                    break;
                }
            } else {
                break;
            }
            std.Thread.sleep(10_000_000); // 10ms poll
        }

        // Now safe to remove and deallocate
        if (self.apps.fetchRemove(hostname)) |kv| {
            const app_ptr = kv.value;

            // Find in storage and remove
            for (self.app_storage.items, 0..) |*stored_app, i| {
                const stored_ptr: *app_module.App = stored_app;
                if (stored_ptr == app_ptr) {
                    stored_app.deinit();
                    _ = self.app_storage.swapRemove(i);
                    break;
                }
            }

            // Clean up drain state (before freeing hostname key)
            _ = self.app_drain_state.remove(hostname);

            // Update default_app if we removed it
            if (self.default_app == app_ptr) {
                self.default_app = if (self.app_storage.items.len > 0)
                    &self.app_storage.items[0]
                else
                    null;
            }

            // Free the hostname key last (after all map lookups are done)
            self.allocator.free(kv.key);

            logger.info("app_removed", .{
                .hostname = hostname,
            });
        }
    }

    /// Add a new app from config
    fn addApp(self: *HttpServer, app_cfg: config_mod.AppConfig) !void {
        var logger = log.stdout();

        // Load the app
        var loaded_app = app_module.loadApp(self.allocator, app_cfg.path, self.array_buffer_allocator, app_cfg.env, app_cfg.max_buffer_size_mb) catch |err| {
            logError("Failed to load app", app_cfg.name, err);
            return err;
        };

        // Apply config settings
        loaded_app.timeout_ms = app_cfg.timeout_ms;
        loaded_app.memory_limit_mb = app_cfg.memory_mb;
        loaded_app.event_loop = &self.event_loop;

        // Store the app
        try self.app_storage.append(self.allocator, loaded_app);
        const app_ptr = &self.app_storage.items[self.app_storage.items.len - 1];

        // Register hostname -> app mapping
        const hostname_key = try self.allocator.dupe(u8, app_cfg.hostname);
        try self.apps.put(hostname_key, app_ptr);

        // Register connection tracking for this app
        try self.app_drain_state.put(hostname_key, AppDrainState{});

        // First app becomes default if none set
        if (self.default_app == null) {
            self.default_app = app_ptr;
        }

        logger.info("app_added", .{
            .name = app_cfg.name,
            .hostname = app_cfg.hostname,
            .path = app_cfg.path,
        });
    }

    pub fn deinit(self: *HttpServer) void {
        // Clean up config watcher
        if (self.config_watcher) |*watcher| {
            watcher.deinit();
        }
        if (self.config_path) |path| {
            self.allocator.free(path);
        }

        // Clean up single app mode
        if (self.app) |*a| {
            a.deinit();
        }

        // Clean up multi-app mode
        // Free hostname keys
        var key_iter = self.apps.keyIterator();
        while (key_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.apps.deinit();
        for (self.app_storage.items) |*stored_app| {
            stored_app.deinit();
        }
        self.app_storage.deinit(self.allocator);

        self.app_drain_state.deinit();
        self.server.deinit();
        self.event_loop.deinit();

        // Clean up V8
        v8.destroyArrayBufferAllocator(self.array_buffer_allocator);
        _ = v8.deinitV8();
        v8.deinitV8Platform();
        self.platform.deinit();
    }

    pub fn run(self: *HttpServer) !void {
        // Ensure event loop is set (may not be if no app loaded)
        timers.setEventLoop(&self.event_loop);
        fetch_api.setEventLoop(&self.event_loop);

        var logger = log.stdout();
        logger.info("server_start", .{
            .port = self.address.getPort(),
            .app = if (self.app) |a| a.app_path else "none",
        });

        while (self.running) {
            // Accept connection
            const conn = self.server.accept() catch |err| {
                // If we're shutting down, any error is expected (socket was closed)
                if (!self.running) break;

                // Handle signal interruption (EINTR)
                if (err == error.Interrupted) continue;

                // Handle connection-level errors that don't stop the server
                if (err == error.ConnectionAborted) continue;

                return err;
            };

            // Double-check running flag after accept returns
            if (!self.running) {
                conn.stream.close();
                break;
            }

            // Handle the request
            self.handleConnection(conn) catch |err| {
                logConnectionError(err);
            };
        }
    }

    fn handleConnection(self: *HttpServer, conn: std.net.Server.Connection) !void {
        defer conn.stream.close();

        // Start timing
        const start_time = std.time.nanoTimestamp();

        // Generate request ID
        self.request_counter += 1;
        const request_id = self.request_counter;

        var buf: [8192]u8 = undefined;

        // Read request
        const n = try conn.stream.read(&buf);
        if (n == 0) return;

        const request_data = buf[0..n];

        // Parse request line
        const request_line_end = std.mem.indexOf(u8, request_data, "\r\n") orelse return;
        const request_line = request_data[0..request_line_end];

        // Split request line: METHOD PATH HTTP/1.x
        var parts = std.mem.splitSequence(u8, request_line, " ");
        const method = parts.next() orelse return;
        const path = parts.next() orelse return;
        _ = parts.next(); // HTTP version

        // Extract body (everything after \r\n\r\n)
        var body: []const u8 = "";
        if (std.mem.indexOf(u8, request_data, "\r\n\r\n")) |body_start| {
            body = request_data[body_start + 4 ..];
        }

        // Handle admin endpoints before app routing
        if (self.admin_enabled and std.mem.startsWith(u8, path, "/admin/")) {
            const admin_result = self.handleAdminRequest(conn, method, path, body);
            // Log and return
            const latency_ns: u64 = @intCast(std.time.nanoTimestamp() - start_time);
            self.metrics.recordRequest(latency_ns, admin_result.status >= 400);
            logRequest(request_id, method, path, admin_result.status, admin_result.body_len, @as(f64, @floatFromInt(latency_ns)) / 1_000_000.0);
            return;
        }

        // Handle built-in endpoints first
        if (std.mem.eql(u8, path, "/health") or std.mem.eql(u8, path, "/healthz")) {
            const health_response = "{\"status\":\"ok\"}";
            try self.sendResponse(conn, 200, "application/json", health_response);
            const latency_ns: u64 = @intCast(std.time.nanoTimestamp() - start_time);
            self.metrics.recordRequest(latency_ns, false);
            logRequest(request_id, method, path, 200, health_response.len, @as(f64, @floatFromInt(latency_ns)) / 1_000_000.0);
            return;
        }

        if (std.mem.eql(u8, path, "/metrics")) {
            var metrics_buf: [2048]u8 = undefined;
            const metrics_body = self.metrics.formatPrometheus(&metrics_buf) catch "{\"error\":\"metrics format failed\"}";
            try self.sendResponse(conn, 200, "text/plain", metrics_body);
            const latency_ns: u64 = @intCast(std.time.nanoTimestamp() - start_time);
            self.metrics.recordRequest(latency_ns, false);
            logRequest(request_id, method, path, 200, metrics_body.len, @as(f64, @floatFromInt(latency_ns)) / 1_000_000.0);
            return;
        }

        // Extract Host header for multi-app routing
        const host = extractHostHeader(request_data);

        // Find the app to handle this request
        // Priority: multi-app by hostname > single app > default app > no app
        var target_app: ?*app_module.App = null;

        if (host) |hostname| {
            // Try multi-app lookup by hostname
            if (self.apps.get(hostname)) |app_ptr| {
                target_app = app_ptr;
            }
        }

        // Fall back to single app mode
        if (target_app == null and self.app != null) {
            target_app = &self.app.?;
        }

        // Fall back to default app in multi-app mode
        if (target_app == null) {
            target_app = self.default_app;
        }

        // Graceful shutdown: check if target app is draining, count active connections
        var active_connection_tracked = false;
        defer {
            if (active_connection_tracked) {
                if (host) |hostname| {
                    if (self.app_drain_state.getPtr(hostname)) |drain| {
                        drain.active_connections -|= 1;
                    }
                }
            }
        }

        if (target_app != null) {
            if (host) |hostname| {
                if (self.app_drain_state.get(hostname)) |drain| {
                    if (drain.draining) {
                        const drain_body = "{\"error\":\"Service draining\",\"retry_after_s\":30}";
                        try self.sendResponse(conn, 503, "application/json", drain_body);
                        const latency_ns: u64 = @intCast(std.time.nanoTimestamp() - start_time);
                        self.metrics.recordRequest(latency_ns, true);
                        logRequest(request_id, method, path, 503, drain_body.len, @as(f64, @floatFromInt(latency_ns)) / 1_000_000.0);
                        return;
                    }
                }
                if (self.app_drain_state.getPtr(hostname)) |drain_mut| {
                    drain_mut.active_connections += 1;
                    active_connection_tracked = true;
                }
            }
        }

        // Handle app request
        var status: u16 = 200;
        var response_body: []const u8 = "Hello from NANO!\n";
        var content_type: []const u8 = "text/plain";
        var should_free_body = false;
        var should_free_ct = false;

        if (target_app) |a| {
            const result = app_module.handleRequest(a, method, path, body, self.allocator);
            status = result.status;
            response_body = result.body;
            content_type = result.content_type;
            should_free_body = true;
            should_free_ct = !std.mem.eql(u8, content_type, "text/plain");

            // Process event loop for timers scheduled during request handling
            self.processEventLoop(a);
        } else if (self.apps.count() > 0) {
            // Multi-app mode but no matching host - return 404
            status = 404;
            response_body = "{\"error\":\"No app configured for this host\"}";
            content_type = "application/json";
        }

        defer {
            if (should_free_body) {
                self.allocator.free(response_body);
            }
            if (should_free_ct) {
                self.allocator.free(content_type);
            }
        }

        // Build and send response headers, then body separately (no size cap)
        var header_buf: [1024]u8 = undefined;
        const headers = std.fmt.bufPrint(&header_buf,
            "HTTP/1.1 {d} {s}\r\n" ++
            "Content-Type: {s}\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n" ++
            "\r\n",
            .{
                status,
                statusText(status),
                content_type,
                response_body.len,
            },
        ) catch return;

        _ = try conn.stream.writeAll(headers);
        _ = try conn.stream.writeAll(response_body);

        // Calculate latency and record metrics
        const end_time = std.time.nanoTimestamp();
        const latency_ns = end_time - start_time;
        const latency_ms = @as(f64, @floatFromInt(latency_ns)) / 1_000_000.0;

        self.metrics.recordRequest(@intCast(latency_ns), status >= 400);

        // Log request
        logRequest(request_id, method, path, status, response_body.len, latency_ms);
    }

    fn sendResponse(self: *HttpServer, conn: std.net.Server.Connection, status: u16, content_type: []const u8, body: []const u8) !void {
        _ = self;
        var header_buf: [1024]u8 = undefined;
        const headers = std.fmt.bufPrint(&header_buf,
            "HTTP/1.1 {d} {s}\r\n" ++
                "Content-Type: {s}\r\n" ++
                "Content-Length: {d}\r\n" ++
                "Connection: close\r\n" ++
                "\r\n",
            .{
                status,
                statusText(status),
                content_type,
                body.len,
            },
        ) catch return error.ResponseTooLarge;

        try conn.stream.writeAll(headers);
        try conn.stream.writeAll(body);
    }

    pub fn stop(self: *HttpServer) void {
        self.running = false;

        // Unblock accept() by making a dummy connection to ourselves
        // This is a classic pattern - more reliable than shutdown() on listening sockets
        const wake_conn = std.net.tcpConnectToAddress(self.address) catch null;
        if (wake_conn) |conn| {
            conn.close();
        }

        var logger = log.stdout();
        logger.info("server_stop", .{
            .requests = self.metrics.request_count,
            .errors = self.metrics.error_count,
            .uptime_s = self.metrics.uptimeSeconds(),
        });

        // Drain active connections before exit (30s timeout)
        self.initiateGracefulShutdown(30_000);
    }

    /// Wait for all active connections to complete or timeout
    fn initiateGracefulShutdown(self: *HttpServer, timeout_ms: u64) void {
        var logger = log.stdout();

        // Mark all apps as draining
        var iter = self.app_drain_state.valueIterator();
        while (iter.next()) |drain| {
            drain.draining = true;
            drain.drain_start_ns = std.time.nanoTimestamp();
        }

        logger.info("shutdown_graceful", .{ .timeout_ms = timeout_ms });

        const start_ns = std.time.nanoTimestamp();
        const timeout_ns: i128 = @intCast(timeout_ms * 1_000_000);
        var poll_count: u32 = 0;

        while (true) {
            var all_drained = true;
            var check_iter = self.app_drain_state.valueIterator();
            while (check_iter.next()) |drain| {
                if (drain.active_connections > 0) {
                    all_drained = false;
                    break;
                }
            }

            if (all_drained) {
                logger.info("shutdown_drained", .{ .polls = poll_count });
                break;
            }

            const elapsed_ns = std.time.nanoTimestamp() - start_ns;
            if (elapsed_ns > timeout_ns) {
                var warn_logger = log.stderr();
                warn_logger.err("shutdown_timeout_reached", .{
                    .elapsed_ms = @divTrunc(elapsed_ns, 1_000_000),
                    .timeout_ms = timeout_ms,
                });
                break;
            }

            std.Thread.sleep(10_000_000); // 10ms poll
            poll_count += 1;
        }
    }

    /// Process event loop - tick and execute any pending timer/fetch callbacks
    fn processEventLoop(self: *HttpServer, app: *app_module.App) void {
        // Tick the event loop to check for completed timers
        _ = self.event_loop.tick() catch return;

        // Check if there are completed timer callbacks or fetch results to process
        const completed = self.event_loop.getCompletedCallbacks();
        const has_fetches = self.event_loop.completed_fetches.items.len > 0;

        if (completed.len > 0 or has_fetches) {
            // Must enter isolate + HandleScope since handleRequest already exited
            var isolate = app.isolate;
            isolate.enter();
            defer isolate.exit();

            var handle_scope: v8.HandleScope = undefined;
            handle_scope.init(isolate);
            defer handle_scope.deinit();

            const context = app.persistent_context.castToContext();
            context.enter();
            defer context.exit();

            // Execute any pending timer callbacks
            if (completed.len > 0) {
                timers.executePendingTimers(isolate, context, &self.event_loop);
            }

            // Resolve any completed fetch promises
            if (has_fetches) {
                fetch_api.resolveCompletedFetches(isolate, context, &self.event_loop);
            }
        }

        // Clean up inactive timers
        self.event_loop.cleanup();
    }

    // Admin API result type
    const AdminResult = struct {
        status: u16,
        body_len: usize,
    };

    /// Handle admin API requests
    fn handleAdminRequest(self: *HttpServer, conn: std.net.Server.Connection, method: []const u8, path: []const u8, body: []const u8) AdminResult {
        // /admin/apps endpoint
        if (std.mem.eql(u8, path, "/admin/apps")) {
            if (std.mem.eql(u8, method, "GET")) {
                return self.handleListApps(conn);
            } else if (std.mem.eql(u8, method, "POST")) {
                return self.handleAddApp(conn, body);
            } else if (std.mem.eql(u8, method, "DELETE")) {
                return self.handleRemoveApp(conn, path, body);
            }
            return self.sendAdminResponse(conn, 405, "{\"error\":\"Method not allowed\"}");
        }

        // DELETE /admin/apps?hostname=X - path contains query string
        if (std.mem.startsWith(u8, path, "/admin/apps?")) {
            if (std.mem.eql(u8, method, "DELETE")) {
                return self.handleRemoveApp(conn, path, body);
            }
            return self.sendAdminResponse(conn, 405, "{\"error\":\"Method not allowed\"}");
        }

        // /admin/reload endpoint
        if (std.mem.eql(u8, path, "/admin/reload")) {
            if (std.mem.eql(u8, method, "POST")) {
                return self.handleReloadConfig(conn);
            }
            return self.sendAdminResponse(conn, 405, "{\"error\":\"Method not allowed\"}");
        }

        // /admin/health endpoint
        if (std.mem.eql(u8, path, "/admin/health")) {
            return self.sendAdminResponse(conn, 200, "{\"status\":\"ok\",\"admin\":true}");
        }

        return self.sendAdminResponse(conn, 404, "{\"error\":\"Not found\"}");
    }

    /// Send admin JSON response
    fn sendAdminResponse(self: *HttpServer, conn: std.net.Server.Connection, status: u16, body: []const u8) AdminResult {
        self.sendResponse(conn, status, "application/json", body) catch {};
        return .{ .status = status, .body_len = body.len };
    }

    /// GET /admin/apps - List all loaded apps with stats
    fn handleListApps(self: *HttpServer, conn: std.net.Server.Connection) AdminResult {
        var buf: [8192]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const writer = fbs.writer();

        writer.writeAll("{\"apps\":[") catch return self.sendAdminResponse(conn, 500, "{\"error\":\"Buffer overflow\"}");

        var first = true;
        var iter = self.apps.iterator();
        while (iter.next()) |entry| {
            if (!first) writer.writeAll(",") catch {};
            first = false;

            const app_ptr = entry.value_ptr.*;
            const memory_pct = app_ptr.getMemoryUsagePercent();

            // Manual JSON building (simpler than std.json for this case)
            std.fmt.format(writer, "{{\"hostname\":\"{s}\",\"path\":\"{s}\",\"memory_percent\":{d:.1},\"timeout_ms\":{d}}}", .{
                entry.key_ptr.*,
                app_ptr.app_path,
                memory_pct,
                app_ptr.timeout_ms,
            }) catch {};
        }

        writer.writeAll("]}") catch {};

        const json_body = fbs.getWritten();
        self.sendResponse(conn, 200, "application/json", json_body) catch {};
        return .{ .status = 200, .body_len = json_body.len };
    }

    /// POST /admin/apps - Add a new app dynamically
    fn handleAddApp(self: *HttpServer, conn: std.net.Server.Connection, body: []const u8) AdminResult {
        // Parse JSON body
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, body, .{}) catch {
            return self.sendAdminResponse(conn, 400, "{\"error\":\"Invalid JSON\"}");
        };
        defer parsed.deinit();

        const root = parsed.value;

        // Ensure root is an object
        if (root != .object) {
            return self.sendAdminResponse(conn, 400, "{\"error\":\"Expected JSON object\"}");
        }

        // Extract required fields
        const hostname_val = root.object.get("hostname") orelse {
            return self.sendAdminResponse(conn, 400, "{\"error\":\"Missing hostname\"}");
        };
        const path_val = root.object.get("path") orelse {
            return self.sendAdminResponse(conn, 400, "{\"error\":\"Missing path\"}");
        };

        if (hostname_val != .string or path_val != .string) {
            return self.sendAdminResponse(conn, 400, "{\"error\":\"Invalid field types\"}");
        }

        // Check if hostname already exists
        if (self.apps.contains(hostname_val.string)) {
            return self.sendAdminResponse(conn, 409, "{\"error\":\"Hostname already exists\"}");
        }

        // Create AppConfig and add
        const name_val = root.object.get("name");
        const name = if (name_val) |n| (if (n == .string) n.string else hostname_val.string) else hostname_val.string;

        const timeout: u64 = if (root.object.get("timeout_ms")) |t| (if (t == .integer) @as(u64, @intCast(t.integer)) else 5000) else 5000;
        const memory: usize = if (root.object.get("memory_mb")) |m| (if (m == .integer) @as(usize, @intCast(m.integer)) else 128) else 128;

        const app_cfg = config_mod.AppConfig{
            .name = self.allocator.dupe(u8, name) catch return self.sendAdminResponse(conn, 500, "{\"error\":\"Out of memory\"}"),
            .path = self.allocator.dupe(u8, path_val.string) catch return self.sendAdminResponse(conn, 500, "{\"error\":\"Out of memory\"}"),
            .hostname = self.allocator.dupe(u8, hostname_val.string) catch return self.sendAdminResponse(conn, 500, "{\"error\":\"Out of memory\"}"),
            .port = 0,
            .timeout_ms = timeout,
            .memory_mb = memory,
            .env = null,
            .max_buffer_size_mb = null,
        };

        self.addApp(app_cfg) catch |err| {
            // Free allocated strings on error
            self.allocator.free(app_cfg.name);
            self.allocator.free(app_cfg.path);
            self.allocator.free(app_cfg.hostname);

            var err_buf: [256]u8 = undefined;
            const err_msg = std.fmt.bufPrint(&err_buf, "{{\"error\":\"Failed to load app: {s}\"}}", .{@errorName(err)}) catch "{\"error\":\"Failed to load app\"}";
            return self.sendAdminResponse(conn, 500, err_msg);
        };

        return self.sendAdminResponse(conn, 201, "{\"success\":true}");
    }

    /// DELETE /admin/apps?hostname=X - Remove an app by hostname
    fn handleRemoveApp(self: *HttpServer, conn: std.net.Server.Connection, path: []const u8, body: []const u8) AdminResult {
        _ = body;

        // Parse hostname from query string
        const query_start = std.mem.indexOf(u8, path, "?") orelse {
            return self.sendAdminResponse(conn, 400, "{\"error\":\"Missing hostname parameter\"}");
        };
        const query = path[query_start + 1 ..];

        // Simple query parsing for hostname=X
        var hostname: ?[]const u8 = null;
        var params = std.mem.splitSequence(u8, query, "&");
        while (params.next()) |param| {
            if (std.mem.startsWith(u8, param, "hostname=")) {
                hostname = param[9..];
                break;
            }
        }

        const target_hostname = hostname orelse {
            return self.sendAdminResponse(conn, 400, "{\"error\":\"Missing hostname parameter\"}");
        };

        // Check app exists
        if (!self.apps.contains(target_hostname)) {
            return self.sendAdminResponse(conn, 404, "{\"error\":\"App not found\"}");
        }

        // Don't allow removing the last app
        if (self.apps.count() == 1) {
            return self.sendAdminResponse(conn, 400, "{\"error\":\"Cannot remove last app\"}");
        }

        self.removeApp(target_hostname);
        return self.sendAdminResponse(conn, 200, "{\"success\":true}");
    }

    /// POST /admin/reload - Trigger config file reload
    fn handleReloadConfig(self: *HttpServer, conn: std.net.Server.Connection) AdminResult {
        if (self.config_path == null) {
            return self.sendAdminResponse(conn, 400, "{\"error\":\"No config file configured\"}");
        }

        self.reloadConfig() catch |err| {
            var err_buf: [256]u8 = undefined;
            const err_msg = std.fmt.bufPrint(&err_buf, "{{\"error\":\"Reload failed: {s}\"}}", .{@errorName(err)}) catch "{\"error\":\"Reload failed\"}";
            return self.sendAdminResponse(conn, 500, err_msg);
        };

        return self.sendAdminResponse(conn, 200, "{\"success\":true}");
    }
};

/// Extract Host header from HTTP request, stripping port if present
fn extractHostHeader(request_data: []const u8) ?[]const u8 {
    // Find headers section (after first \r\n)
    const headers_start = (std.mem.indexOf(u8, request_data, "\r\n") orelse return null) + 2;
    const headers_end = std.mem.indexOf(u8, request_data, "\r\n\r\n") orelse request_data.len;
    const headers = request_data[headers_start..headers_end];

    // Search for Host header (case-insensitive)
    var lines = std.mem.splitSequence(u8, headers, "\r\n");
    while (lines.next()) |line| {
        // Check if line starts with "Host:" (case-insensitive)
        if (line.len >= 5) {
            const prefix = line[0..5];
            if (std.ascii.eqlIgnoreCase(prefix, "host:")) {
                // Extract value, trim whitespace
                var value = line[5..];
                while (value.len > 0 and value[0] == ' ') {
                    value = value[1..];
                }
                // Strip port if present (e.g., "example.com:8080" -> "example.com")
                if (std.mem.indexOf(u8, value, ":")) |colon_pos| {
                    return value[0..colon_pos];
                }
                return value;
            }
        }
    }
    return null;
}

fn logRequest(request_id: u64, method: []const u8, path: []const u8, status: u16, bytes: usize, latency_ms: f64) void {
    var logger = log.stdout();
    logger.info("request", .{
        .req = request_id,
        .method = method,
        .path = path,
        .status = status,
        .bytes = bytes,
        .latency_ms = latency_ms,
    });
}

fn logError(message: []const u8, detail: []const u8, err: anyerror) void {
    var logger = log.stderr();
    logger.err(message, .{
        .detail = detail,
        .@"error" = @errorName(err),
    });
}

fn logConnectionError(err: anyerror) void {
    var logger = log.stderr();
    logger.err("connection_error", .{
        .@"error" = @errorName(err),
    });
}

fn statusText(status: u16) []const u8 {
    return switch (status) {
        200 => "OK",
        201 => "Created",
        204 => "No Content",
        301 => "Moved Permanently",
        302 => "Found",
        304 => "Not Modified",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        500 => "Internal Server Error",
        502 => "Bad Gateway",
        503 => "Service Unavailable",
        else => "OK",
    };
}

// Global server reference for signal handler
var global_server: ?*HttpServer = null;

fn handleSignal(_: c_int) callconv(.c) void {
    if (global_server) |s| {
        s.stop();
    }
}

/// Start HTTP server on specified port with optional app path
pub fn serve(port: u16, app_path: ?[]const u8) !void {
    try serveWithConfig(port, app_path, null, null);
}

/// Start HTTP server with full configuration options
pub fn serveWithConfig(port: u16, app_path: ?[]const u8, timeout_ms: ?u64, memory_mb: ?usize) !void {
    var http_server = try HttpServer.init(port, std.heap.page_allocator);
    defer http_server.deinit();

    // Load app after server init (event loop pointer is now stable)
    if (app_path) |path| {
        try http_server.loadApp(path);

        // Apply config settings to the loaded app
        if (http_server.app) |*app| {
            if (timeout_ms) |t| {
                app.timeout_ms = t;
            }
            if (memory_mb) |m| {
                app.memory_limit_mb = m;
            }
        }
    }

    // Install signal handlers for graceful shutdown
    global_server = &http_server;
    const sigterm_action = posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    _ = posix.sigaction(posix.SIG.TERM, &sigterm_action, null);
    _ = posix.sigaction(posix.SIG.INT, &sigterm_action, null);

    try http_server.run();
}

/// Start HTTP server in multi-app mode with virtual host routing
pub fn serveMultiApp(cfg: config_mod.Config, config_path: []const u8) !void {
    var http_server = try HttpServer.init(cfg.port, std.heap.page_allocator);
    defer http_server.deinit();

    // Load all apps from config
    try http_server.loadApps(cfg);

    // Start config file watcher for hot reload
    try http_server.startConfigWatcher(config_path);

    // Install signal handlers for graceful shutdown
    global_server = &http_server;
    const sigterm_action = posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    _ = posix.sigaction(posix.SIG.TERM, &sigterm_action, null);
    _ = posix.sigaction(posix.SIG.INT, &sigterm_action, null);

    try http_server.run();
}
