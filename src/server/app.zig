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

// Get the array buffer allocator type
const ArrayBufferAllocator = @TypeOf(v8.createDefaultArrayBufferAllocator());

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

    pub fn deinit(self: *App) void {
        // Clean up persistent handles first
        if (self.initialized) {
            var ctx_handle = self.persistent_context;
            ctx_handle.deinit();
            var exports_handle = self.persistent_exports;
            exports_handle.deinit();
            var fetch_handle = self.persistent_fetch;
            fetch_handle.deinit();
        }
        // Clean up V8 in reverse order
        self.isolate.exit();
        self.isolate.deinit();
        self.allocator.free(self.script_source);
        self.allocator.free(self.app_path);
    }
};

/// Load an app from a folder path and compile the script
pub fn loadApp(allocator: std.mem.Allocator, path: []const u8, array_buffer_allocator: ArrayBufferAllocator) !App {
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

    const wrapped_source = std.fmt.bufPrint(wrapped_source_buf,
        \\(function() {{
        \\  var __exports = {{}};
        \\  var __default = null;
        \\
        \\  // Simulate export default
        \\  globalThis.__setDefault = function(obj) {{ __default = obj; }};
        \\
        \\  // User script
        \\  {s}
        \\
        \\  return __default || __exports;
        \\}})()
    , .{source}) catch {
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

    // Don't exit context here - leave it entered for request handling
    // handle_scope will be destroyed but persistent handles survive

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

/// Handle an HTTP request using the cached fetch handler
pub fn handleRequest(
    app: *App,
    method: []const u8,
    path: []const u8,
    body: []const u8,
    allocator: std.mem.Allocator,
) HandleResult {
    const isolate = app.isolate;

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

    // Build full URL for the request
    var url_buf: [2048]u8 = undefined;
    const full_url = std.fmt.bufPrint(&url_buf, "http://localhost{s}", .{path}) catch path;

    // Create Request object
    const request_obj = request_api.createRequest(isolate, context, full_url, method, body);

    // Call the cached fetch handler
    const fetch_fn = v8.Function{ .handle = @ptrCast(fetch_val.handle) };
    var fetch_args: [1]v8.Value = .{v8.Value{ .handle = @ptrCast(request_obj.handle) }};
    const handler_result = fetch_fn.call(context, exports, &fetch_args) orelse {
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
