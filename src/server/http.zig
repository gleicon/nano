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
const config_mod = @import("config");

// Get the actual type from the function return type
const ArrayBufferAllocator = @TypeOf(v8.createDefaultArrayBufferAllocator());

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
        };
    }

    /// Load app after server init (event loop pointer must be stable first)
    pub fn loadApp(self: *HttpServer, app_path: []const u8) !void {
        // Set global event loop reference BEFORE loading app (app init may use timers)
        timers.setEventLoop(&self.event_loop);

        self.app = app_module.loadApp(self.allocator, app_path, self.array_buffer_allocator) catch |err| {
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

        var logger = log.stdout();

        for (cfg.apps) |app_cfg| {
            // Load the app
            var loaded_app = app_module.loadApp(self.allocator, app_cfg.path, self.array_buffer_allocator) catch |err| {
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

        // TODO: Handle changed apps (same hostname, different path) - for now, just track unchanged
        const unchanged_count = self.apps.count() - added_count;

        logger.info("config_reload_complete", .{
            .added = added_count,
            .removed = removed_count,
            .unchanged = unchanged_count,
        });
    }

    /// Remove an app by hostname
    fn removeApp(self: *HttpServer, hostname: []const u8) void {
        var logger = log.stdout();

        // Find and remove from HashMap
        if (self.apps.fetchRemove(hostname)) |kv| {
            const app_ptr = kv.value;

            // Free the hostname key (we allocated it)
            self.allocator.free(kv.key);

            // Find in storage and remove
            for (self.app_storage.items, 0..) |*stored_app, i| {
                // Compare by pointer - app_ptr points into app_storage.items
                const stored_ptr: *app_module.App = stored_app;
                if (stored_ptr == app_ptr) {
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

            logger.info("app_removed", .{
                .hostname = hostname,
            });
        }
    }

    /// Add a new app from config
    fn addApp(self: *HttpServer, app_cfg: config_mod.AppConfig) !void {
        var logger = log.stdout();

        // Load the app
        var loaded_app = app_module.loadApp(self.allocator, app_cfg.path, self.array_buffer_allocator) catch |err| {
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

        // Build response
        var response_buf: [65536 + 256]u8 = undefined;
        const response = std.fmt.bufPrint(&response_buf,
            "HTTP/1.1 {d} {s}\r\n" ++
            "Content-Type: {s}\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n" ++
            "\r\n" ++
            "{s}",
            .{
                status,
                statusText(status),
                content_type,
                response_body.len,
                response_body,
            },
        ) catch return;

        // Send response
        _ = try conn.stream.writeAll(response);

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
        var response_buf: [65536 + 256]u8 = undefined;
        const response = std.fmt.bufPrint(&response_buf,
            "HTTP/1.1 {d} {s}\r\n" ++
                "Content-Type: {s}\r\n" ++
                "Content-Length: {d}\r\n" ++
                "Connection: close\r\n" ++
                "\r\n" ++
                "{s}",
            .{
                status,
                statusText(status),
                content_type,
                body.len,
                body,
            },
        ) catch return error.ResponseTooLarge;

        try conn.stream.writeAll(response);
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
    }

    /// Process event loop - tick and execute any pending timer callbacks
    fn processEventLoop(self: *HttpServer, app: *app_module.App) void {
        // Tick the event loop to check for completed timers
        _ = self.event_loop.tick() catch return;

        // Get V8 context from the app
        const isolate = app.isolate;
        const context = app.persistent_context.castToContext();

        // Execute any pending timer callbacks
        timers.executePendingTimers(isolate, context, &self.event_loop);

        // Clean up inactive timers
        self.event_loop.cleanup();
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
