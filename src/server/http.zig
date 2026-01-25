const std = @import("std");
const posix = std.posix;
const v8 = @import("v8");
const app_module = @import("app");
const log = @import("log");
const metrics_mod = @import("metrics");
const EventLoop = @import("event_loop").EventLoop;
const timers = @import("timers");

// Get the actual type from the function return type
const ArrayBufferAllocator = @TypeOf(v8.createDefaultArrayBufferAllocator());

pub const HttpServer = struct {
    address: std.net.Address,
    server: std.net.Server,
    running: bool,
    app: ?app_module.App,
    allocator: std.mem.Allocator,
    platform: v8.Platform,
    array_buffer_allocator: ArrayBufferAllocator,
    request_counter: u64,
    metrics: metrics_mod.Metrics,
    event_loop: EventLoop,

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
            .app = null, // App loaded separately after event loop pointer is stable
            .allocator = allocator,
            .platform = platform,
            .array_buffer_allocator = array_buffer_allocator,
            .request_counter = 0,
            .metrics = metrics_mod.Metrics.init(),
            .event_loop = event_loop,
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

    pub fn deinit(self: *HttpServer) void {
        if (self.app) |*a| {
            a.deinit();
        }
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
                if (err == error.ConnectionAborted) continue;
                return err;
            };

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

        // Handle app request
        var status: u16 = 200;
        var response_body: []const u8 = "Hello from NANO!\n";
        var content_type: []const u8 = "text/plain";
        var should_free_body = false;
        var should_free_ct = false;

        if (self.app) |*a| {
            const result = app_module.handleRequest(a, method, path, body, self.allocator);
            status = result.status;
            response_body = result.body;
            content_type = result.content_type;
            should_free_body = true;
            should_free_ct = !std.mem.eql(u8, content_type, "text/plain");

            // Process event loop for timers scheduled during request handling
            self.processEventLoop(a);
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
    var server = try HttpServer.init(port, std.heap.page_allocator);
    defer server.deinit();

    // Load app after server init (event loop pointer is now stable)
    if (app_path) |path| {
        try server.loadApp(path);
    }

    // Install signal handlers for graceful shutdown
    global_server = &server;
    const sigterm_action = posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    _ = posix.sigaction(posix.SIG.TERM, &sigterm_action, null);
    _ = posix.sigaction(posix.SIG.INT, &sigterm_action, null);

    try server.run();
}
