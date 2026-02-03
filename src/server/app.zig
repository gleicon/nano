const std = @import("std");
const v8 = @import("v8");
const console = @import("console");
const encoding = @import("encoding");
const url = @import("url");
const crypto = @import("crypto");
const fetch_api = @import("fetch");
const headers = @import("headers");
const request_api = @import("request");
const timers = @import("timers");
const EventLoop = @import("event_loop").EventLoop;
const watchdog = @import("watchdog");
const abort = @import("abort");
const blob = @import("blob");
const formdata = @import("formdata");

// Get the array buffer allocator type
const ArrayBufferAllocator = @TypeOf(v8.createDefaultArrayBufferAllocator());

/// Default memory limit per isolate (128 MB)
pub const DEFAULT_MEMORY_LIMIT_MB: usize = 128;

/// Memory thresholds for graceful handling
const GC_TRIGGER_THRESHOLD: f64 = 0.80; // Trigger GC at 80% usage
const REJECT_THRESHOLD: f64 = 0.95; // Reject requests at 95% usage

/// A loaded JavaScript application with V8 runtime and cached state
pub const App = struct {
    allocator: std.mem.Allocator,
    script_source: []const u8,
    app_path: []const u8,
    // V8 runtime state - persists across requests
    isolate: v8.Isolate,
    array_buffer_allocator: ArrayBufferAllocator,
    // Cached compiled state - avoids recompilation per request
    persistent_context: v8.Persistent(v8.Context),
    persistent_exports: v8.Persistent(v8.Value),
    persistent_fetch: v8.Persistent(v8.Value),
    initialized: bool,
    // Event loop reference for async operations (set by server)
    event_loop: ?*EventLoop = null,
    // Timeout for script execution (default 5s for requests with external calls)
    timeout_ms: u64 = watchdog.EXTENDED_TIMEOUT_MS,
    // Memory limit in MB (0 = no limit, default 128MB)
    memory_limit_mb: usize = DEFAULT_MEMORY_LIMIT_MB,
    // Environment variables (App owns this HashMap - deep copy from AppConfig)
    env: std.StringHashMap([]const u8),

    pub fn deinit(self: *App) void {
        // Enter isolate to clean up persistent handles
        var isolate = self.isolate;
        isolate.enter();

        // Clean up persistent handles
        if (self.initialized) {
            var ctx_handle = self.persistent_context;
            ctx_handle.deinit();
            var exports_handle = self.persistent_exports;
            exports_handle.deinit();
            var fetch_handle = self.persistent_fetch;
            fetch_handle.deinit();
        }

        // Exit and destroy isolate
        isolate.exit();
        isolate.deinit();

        // Clean up environment variables HashMap
        var it = self.env.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.env.deinit();

        self.allocator.free(self.script_source);
        self.allocator.free(self.app_path);
    }

    /// Check memory usage and take action if needed
    /// Returns: null if OK to proceed, error message if request should be rejected
    pub fn checkMemory(self: *App) ?[]const u8 {
        const stats = self.isolate.getHeapStatistics();
        const limit = stats.heap_size_limit;
        const used = stats.used_heap_size;

        if (limit == 0) return null; // No limit set

        const usage_ratio = @as(f64, @floatFromInt(used)) / @as(f64, @floatFromInt(limit));

        // If usage exceeds GC threshold, trigger garbage collection
        if (usage_ratio > GC_TRIGGER_THRESHOLD) {
            const used_mb = @as(f64, @floatFromInt(used)) / (1024 * 1024);
            const limit_mb = @as(f64, @floatFromInt(limit)) / (1024 * 1024);
            std.debug.print("Memory warning: {d:.1}MB / {d:.1}MB ({d:.0}%) - triggering GC\n", .{ used_mb, limit_mb, usage_ratio * 100 });

            self.isolate.lowMemoryNotification();

            // Recheck after GC
            const stats_after = self.isolate.getHeapStatistics();
            const used_after = stats_after.used_heap_size;
            const usage_after = @as(f64, @floatFromInt(used_after)) / @as(f64, @floatFromInt(limit));

            const freed_mb = @as(f64, @floatFromInt(used -| used_after)) / (1024 * 1024);
            std.debug.print("GC completed: freed {d:.1}MB, now at {d:.0}%\n", .{ freed_mb, usage_after * 100 });

            // If still critically high, reject the request
            if (usage_after > REJECT_THRESHOLD) {
                std.debug.print("Memory critical: rejecting request ({d:.0}% > {d:.0}% threshold)\n", .{ usage_after * 100, REJECT_THRESHOLD * 100 });
                return "Memory limit exceeded - request rejected";
            }
        }

        return null;
    }

    /// Get current memory usage as percentage
    pub fn getMemoryUsagePercent(self: *App) f64 {
        const stats = self.isolate.getHeapStatistics();
        const limit = stats.heap_size_limit;
        if (limit == 0) return 0;
        return @as(f64, @floatFromInt(stats.used_heap_size)) / @as(f64, @floatFromInt(limit)) * 100.0;
    }
};

/// Transform "export default X" to "__default = X" for ESM compatibility
/// This allows using standard JavaScript module syntax
fn transformExportDefault(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    // Find "export default" and replace with "__default ="
    const pattern = "export default";
    const replacement = "__default =";

    // Count occurrences to calculate new size
    var count: usize = 0;
    var pos: usize = 0;
    while (pos < source.len) {
        if (std.mem.indexOf(u8, source[pos..], pattern)) |idx| {
            count += 1;
            pos += idx + pattern.len;
        } else {
            break;
        }
    }

    if (count == 0) {
        // No transformation needed, return original
        return source;
    }

    // Calculate new size (replacement is shorter, but allocate same size for safety)
    const new_size = source.len - (count * (pattern.len - replacement.len));
    const result = try allocator.alloc(u8, new_size);

    // Perform replacement
    var write_pos: usize = 0;
    var read_pos: usize = 0;
    while (read_pos < source.len) {
        if (std.mem.indexOf(u8, source[read_pos..], pattern)) |idx| {
            // Copy everything before the pattern
            @memcpy(result[write_pos .. write_pos + idx], source[read_pos .. read_pos + idx]);
            write_pos += idx;
            // Write replacement
            @memcpy(result[write_pos .. write_pos + replacement.len], replacement);
            write_pos += replacement.len;
            read_pos += idx + pattern.len;
        } else {
            // Copy remaining
            const remaining = source.len - read_pos;
            @memcpy(result[write_pos .. write_pos + remaining], source[read_pos..]);
            write_pos += remaining;
            break;
        }
    }

    return result[0..write_pos];
}

/// Load an app from a folder path and compile the script
pub fn loadApp(allocator: std.mem.Allocator, path: []const u8, array_buffer_allocator: ArrayBufferAllocator, app_config_env: ?std.StringHashMap([]const u8)) !App {
    // Build path to index.js
    var path_buf: [4096]u8 = undefined;
    const index_path = std.fmt.bufPrint(&path_buf, "{s}/index.js", .{path}) catch {
        return error.PathTooLong;
    };

    // Read the file
    const file = std.fs.cwd().openFile(index_path, .{}) catch |err| {
        std.debug.print("Failed to open {s}: {}\n", .{ index_path, err });
        return error.FileNotFound;
    };
    defer file.close();

    const source = file.readToEndAlloc(allocator, 1024 * 1024) catch {
        return error.FileReadError;
    };

    const app_path_copy = allocator.dupe(u8, path) catch {
        allocator.free(source);
        return error.OutOfMemory;
    };

    // Create isolate for this app - it persists for app lifetime
    var params = v8.initCreateParams();
    params.array_buffer_allocator = array_buffer_allocator;

    // Configure memory limits (128 MB default)
    const initial_heap_size = 4 * 1024 * 1024; // 4 MB initial
    const max_heap_size = DEFAULT_MEMORY_LIMIT_MB * 1024 * 1024;
    v8.c.v8__ResourceConstraints__ConfigureDefaultsFromHeapSize(
        &params.constraints,
        initial_heap_size,
        max_heap_size,
    );

    var isolate = v8.Isolate.init(&params);
    isolate.enter();

    // Pre-compile the script and cache the fetch handler
    var handle_scope: v8.HandleScope = undefined;
    handle_scope.init(isolate);

    // Create context with all APIs
    var context = v8.Context.init(isolate, null, null);
    context.enter();

    // Register all APIs
    console.registerConsole(isolate, context);
    encoding.registerEncodingAPIs(isolate, context);
    url.registerURLAPIs(isolate, context);
    crypto.registerCryptoAPIs(isolate, context);
    fetch_api.registerFetchAPI(isolate, context);
    headers.registerHeadersAPI(isolate, context);
    request_api.registerRequestAPI(isolate, context);
    timers.registerTimerAPIs(isolate, context);
    abort.registerAbortAPI(isolate, context);
    blob.registerBlobAPI(isolate, context);
    formdata.registerFormDataAPI(isolate, context);

    // Wrap and compile the script
    const wrapped_source_buf = allocator.alloc(u8, 1024 * 1024 + 1024) catch {
        context.exit();
        handle_scope.deinit();
        isolate.exit();
        isolate.deinit();
        allocator.free(source);
        allocator.free(app_path_copy);
        return error.OutOfMemory;
    };
    defer allocator.free(wrapped_source_buf);

    // Transform "export default" to "__default =" for ESM compatibility
    const transformed_source = transformExportDefault(allocator, source) catch source;
    defer if (transformed_source.ptr != source.ptr) allocator.free(transformed_source);

    const wrapped_source = std.fmt.bufPrint(wrapped_source_buf,
        \\(function() {{
        \\  var __exports = {{}};
        \\  var __default = null;
        \\
        \\  // Support both "export default" (transformed) and legacy "__setDefault"
        \\  globalThis.__setDefault = function(obj) {{ __default = obj; }};
        \\
        \\  // User script
        \\  {s}
        \\
        \\  return __default || __exports;
        \\}})()
    , .{transformed_source}) catch {
        context.exit();
        handle_scope.deinit();
        isolate.exit();
        isolate.deinit();
        allocator.free(source);
        allocator.free(app_path_copy);
        return error.ScriptTooLarge;
    };

    // Compile and run
    const source_str = v8.String.initUtf8(isolate, wrapped_source);
    const script = v8.Script.compile(context, source_str, null) catch {
        std.debug.print("Failed to compile app script\n", .{});
        context.exit();
        handle_scope.deinit();
        isolate.exit();
        isolate.deinit();
        allocator.free(source);
        allocator.free(app_path_copy);
        return error.CompilationFailed;
    };

    const exports = script.run(context) catch {
        std.debug.print("Failed to run app script\n", .{});
        context.exit();
        handle_scope.deinit();
        isolate.exit();
        isolate.deinit();
        allocator.free(source);
        allocator.free(app_path_copy);
        return error.ExecutionFailed;
    };

    // Validate exports has fetch method
    if (!exports.isObject()) {
        std.debug.print("App must export an object with fetch method\n", .{});
        context.exit();
        handle_scope.deinit();
        isolate.exit();
        isolate.deinit();
        allocator.free(source);
        allocator.free(app_path_copy);
        return error.InvalidExports;
    }

    const exports_obj = v8.Object{ .handle = @ptrCast(exports.handle) };
    const fetch_val = exports_obj.getValue(context, v8.String.initUtf8(isolate, "fetch")) catch {
        std.debug.print("App must export a fetch method\n", .{});
        context.exit();
        handle_scope.deinit();
        isolate.exit();
        isolate.deinit();
        allocator.free(source);
        allocator.free(app_path_copy);
        return error.MissingFetch;
    };

    if (!fetch_val.isFunction()) {
        std.debug.print("fetch must be a function\n", .{});
        context.exit();
        handle_scope.deinit();
        isolate.exit();
        isolate.deinit();
        allocator.free(source);
        allocator.free(app_path_copy);
        return error.FetchNotFunction;
    }

    // Create persistent handles to survive across HandleScope boundaries
    const persistent_context = isolate.initPersistent(v8.Context, context);
    const persistent_exports = isolate.initPersistent(v8.Value, exports);
    const persistent_fetch = isolate.initPersistent(v8.Value, fetch_val);

    // Exit context and isolate after initialization
    // handleRequest will enter them again for each request (required for multi-app mode)
    context.exit();
    handle_scope.deinit();
    isolate.exit();

    // Initialize App-owned environment variables HashMap (deep copy from AppConfig)
    var env_map = std.StringHashMap([]const u8).init(allocator);
    if (app_config_env) |config_env| {
        var it = config_env.iterator();
        while (it.next()) |entry| {
            const key_copy = allocator.dupe(u8, entry.key_ptr.*) catch {
                // Cleanup on error
                var cleanup_it = env_map.iterator();
                while (cleanup_it.next()) |cleanup_entry| {
                    allocator.free(cleanup_entry.key_ptr.*);
                    allocator.free(cleanup_entry.value_ptr.*);
                }
                env_map.deinit();
                allocator.free(source);
                allocator.free(app_path_copy);
                return error.OutOfMemory;
            };
            errdefer allocator.free(key_copy);

            const val_copy = allocator.dupe(u8, entry.value_ptr.*) catch {
                allocator.free(key_copy);
                // Cleanup on error
                var cleanup_it = env_map.iterator();
                while (cleanup_it.next()) |cleanup_entry| {
                    allocator.free(cleanup_entry.key_ptr.*);
                    allocator.free(cleanup_entry.value_ptr.*);
                }
                env_map.deinit();
                allocator.free(source);
                allocator.free(app_path_copy);
                return error.OutOfMemory;
            };
            errdefer allocator.free(val_copy);

            env_map.put(key_copy, val_copy) catch {
                allocator.free(key_copy);
                allocator.free(val_copy);
                // Cleanup on error
                var cleanup_it = env_map.iterator();
                while (cleanup_it.next()) |cleanup_entry| {
                    allocator.free(cleanup_entry.key_ptr.*);
                    allocator.free(cleanup_entry.value_ptr.*);
                }
                env_map.deinit();
                allocator.free(source);
                allocator.free(app_path_copy);
                return error.OutOfMemory;
            };
        }
    }

    return App{
        .allocator = allocator,
        .script_source = source,
        .app_path = app_path_copy,
        .isolate = isolate,
        .array_buffer_allocator = array_buffer_allocator,
        .persistent_context = persistent_context,
        .persistent_exports = persistent_exports,
        .persistent_fetch = persistent_fetch,
        .initialized = true,
        .env = env_map,
    };
}

/// Result of handling a request
pub const HandleResult = struct {
    status: u16,
    body: []const u8,
    content_type: []const u8,

    pub fn deinit(self: *HandleResult, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
    }
};

/// Build V8 object from app environment variables
fn buildEnvObject(
    isolate: v8.Isolate,
    context: v8.Context,
    app_env: *const std.StringHashMap([]const u8),
) v8.Object {
    const env_obj = v8.Object.init(isolate);

    var it = app_env.iterator();
    while (it.next()) |entry| {
        const key_str = v8.String.initUtf8(isolate, entry.key_ptr.*);
        const val_str = v8.String.initUtf8(isolate, entry.value_ptr.*);
        _ = env_obj.setValue(context, key_str, val_str.toValue());
    }

    return env_obj;
}

/// Handle an HTTP request using the cached fetch handler
pub fn handleRequest(
    app: *App,
    method: []const u8,
    path: []const u8,
    body: []const u8,
    allocator: std.mem.Allocator,
) HandleResult {
    // Check memory before processing request (graceful OOM prevention)
    if (app.checkMemory()) |mem_err| {
        return .{
            .status = 503,
            .body = allocator.dupe(u8, mem_err) catch "Memory limit exceeded",
            .content_type = "text/plain",
        };
    }

    var isolate = app.isolate;

    // Enter isolate for this request (required for multi-app mode)
    isolate.enter();
    defer isolate.exit();

    // Create handle scope for this request
    var handle_scope: v8.HandleScope = undefined;
    handle_scope.init(isolate);
    defer handle_scope.deinit();

    // Get cached context and fetch function
    const context = app.persistent_context.castToContext();
    const exports = app.persistent_exports.toValue();
    const fetch_val = app.persistent_fetch.toValue();

    // Enter context for this request
    context.enter();
    defer context.exit();

    var try_catch: v8.TryCatch = undefined;
    try_catch.init(isolate);
    defer try_catch.deinit();

    // Start CPU watchdog to prevent infinite loops
    var wd = watchdog.Watchdog.init(isolate, app.timeout_ms);
    wd.start() catch {
        return .{
            .status = 500,
            .body = allocator.dupe(u8, "Failed to start execution watchdog") catch "Error",
            .content_type = "text/plain",
        };
    };
    defer wd.stop();

    // Build full URL for the request
    var url_buf: [2048]u8 = undefined;
    const full_url = std.fmt.bufPrint(&url_buf, "http://localhost{s}", .{path}) catch path;

    // Create Request object
    const request_obj = request_api.createRequest(isolate, context, full_url, method, body);

    // Build environment object
    const env_obj = buildEnvObject(isolate, context, &app.env);

    // Call the cached fetch handler with request and env
    const fetch_fn = v8.Function{ .handle = @ptrCast(fetch_val.handle) };
    var fetch_args: [2]v8.Value = .{
        v8.Value{ .handle = @ptrCast(request_obj.handle) },
        v8.Value{ .handle = @ptrCast(env_obj.handle) },
    };
    const handler_result = fetch_fn.call(context, exports, &fetch_args) orelse {
        // Check if terminated by watchdog
        if (wd.wasTerminated()) {
            return .{
                .status = 408,
                .body = allocator.dupe(u8, "Script execution timed out") catch "Timeout",
                .content_type = "text/plain",
            };
        }
        if (try_catch.hasCaught()) {
            return errorResponse(isolate, &try_catch, context, allocator);
        }
        return .{
            .status = 500,
            .body = allocator.dupe(u8, "fetch handler returned null") catch "Error",
            .content_type = "text/plain",
        };
    };

    // Handle Promise returns (async handlers)
    var response = handler_result;
    if (handler_result.isPromise()) {
        const promise = v8.Promise{ .handle = @ptrCast(handler_result.handle) };

        // Run microtasks to process Promise callbacks
        isolate.performMicrotasksCheckpoint();

        // Wait for Promise to resolve (with timeout to prevent infinite loops)
        var iterations: u32 = 0;
        const max_iterations: u32 = 10000; // Safety limit

        while (promise.getState() == .kPending and iterations < max_iterations) {
            // Run event loop tick if available
            if (app.event_loop) |loop| {
                _ = loop.tick() catch {};
            }
            // Run microtasks again
            isolate.performMicrotasksCheckpoint();
            iterations += 1;
        }

        if (promise.getState() == .kRejected) {
            promise.markAsHandled();
            const rejection = promise.getResult();
            const rejection_str = rejection.toString(context) catch {
                return .{
                    .status = 500,
                    .body = allocator.dupe(u8, "Promise rejected") catch "Error",
                    .content_type = "text/plain",
                };
            };
            var err_buf: [1024]u8 = undefined;
            const err_len = rejection_str.writeUtf8(isolate, &err_buf);
            return .{
                .status = 500,
                .body = allocator.dupe(u8, err_buf[0..err_len]) catch "Error",
                .content_type = "text/plain",
            };
        }

        if (promise.getState() == .kPending) {
            return .{
                .status = 500,
                .body = allocator.dupe(u8, "Promise did not resolve in time") catch "Error",
                .content_type = "text/plain",
            };
        }

        // Get the resolved value
        response = promise.getResult();
    }

    // Extract Response data
    if (!response.isObject()) {
        return .{
            .status = 500,
            .body = allocator.dupe(u8, "fetch handler must return a Response") catch "Error",
            .content_type = "text/plain",
        };
    }

    const response_obj = v8.Object{ .handle = @ptrCast(response.handle) };

    // Get status
    const status_val = response_obj.getValue(context, v8.String.initUtf8(isolate, "_status")) catch {
        return .{ .status = 200, .body = allocator.dupe(u8, "") catch "", .content_type = "text/plain" };
    };
    const status_f64 = status_val.toF64(context) catch 200;
    const status: u16 = @intFromFloat(status_f64);

    // Get body
    const body_val = response_obj.getValue(context, v8.String.initUtf8(isolate, "_body")) catch {
        return .{ .status = status, .body = allocator.dupe(u8, "") catch "", .content_type = "text/plain" };
    };
    const body_str = body_val.toString(context) catch {
        return .{ .status = status, .body = allocator.dupe(u8, "") catch "", .content_type = "text/plain" };
    };

    var body_buf: [65536]u8 = undefined;
    const body_len = body_str.writeUtf8(isolate, &body_buf);
    const response_body = allocator.dupe(u8, body_buf[0..body_len]) catch {
        return .{ .status = 500, .body = "Out of memory", .content_type = "text/plain" };
    };

    // Get content-type from headers
    var content_type: []const u8 = "text/plain";
    const headers_val = response_obj.getValue(context, v8.String.initUtf8(isolate, "_headers")) catch null;
    if (headers_val) |hv| {
        if (hv.isObject()) {
            const headers_obj = v8.Object{ .handle = @ptrCast(hv.handle) };
            const ct_val = headers_obj.getValue(context, v8.String.initUtf8(isolate, "content-type")) catch null;
            if (ct_val) |ctv| {
                if (ctv.isString()) {
                    var ct_buf: [128]u8 = undefined;
                    const ct_str = ctv.toString(context) catch null;
                    if (ct_str) |s| {
                        const ct_len = s.writeUtf8(isolate, &ct_buf);
                        content_type = allocator.dupe(u8, ct_buf[0..ct_len]) catch "text/plain";
                    }
                }
            }
        }
    }

    return .{
        .status = status,
        .body = response_body,
        .content_type = content_type,
    };
}

fn errorResponse(isolate: v8.Isolate, try_catch: *v8.TryCatch, context: v8.Context, allocator: std.mem.Allocator) HandleResult {
    const msg = try_catch.getMessage() orelse {
        return .{
            .status = 500,
            .body = allocator.dupe(u8, "Unknown error") catch "Error",
            .content_type = "text/plain",
        };
    };

    const msg_str = msg.getMessage();
    var buf: [1024]u8 = undefined;
    const len = msg_str.writeUtf8(isolate, &buf);

    const line = msg.getLineNumber(context);
    if (line != null and line.? > 0) {
        var err_buf: [1100]u8 = undefined;
        const err_msg = std.fmt.bufPrint(&err_buf, "Error at line {d}: {s}", .{ line.?, buf[0..len] }) catch buf[0..len];
        return .{
            .status = 500,
            .body = allocator.dupe(u8, err_msg) catch "Error",
            .content_type = "text/plain",
        };
    }

    return .{
        .status = 500,
        .body = allocator.dupe(u8, buf[0..len]) catch "Error",
        .content_type = "text/plain",
    };
}
