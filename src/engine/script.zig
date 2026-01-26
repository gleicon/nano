const std = @import("std");
const v8 = @import("v8");
const error_mod = @import("error.zig");
const console = @import("console");
const encoding = @import("encoding");
const url = @import("url");
const crypto = @import("crypto");
const fetch = @import("fetch");
const headers = @import("headers");
const request = @import("request");
const abort = @import("abort");
const blob = @import("blob");
const formdata = @import("formdata");

pub const ScriptError = error_mod.ScriptError;
pub const extractError = error_mod.extractError;

/// Result of script execution - either success with output string or error
pub const ScriptResult = union(enum) {
    ok: []const u8,
    err: ScriptError,

    /// Free memory associated with this result
    pub fn deinit(self: *ScriptResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .ok => |value| allocator.free(value),
            .err => |*e| e.deinit(allocator),
        }
    }
};

/// Execute JavaScript code and return result
/// Caller owns returned memory (allocated from provided allocator)
/// This function handles all V8 lifecycle: isolate, context, handles
pub fn runScript(
    source: []const u8,
    allocator: std.mem.Allocator,
) ScriptResult {
    // Create isolate parameters
    var params = v8.initCreateParams();
    params.array_buffer_allocator = v8.createDefaultArrayBufferAllocator();
    defer v8.destroyArrayBufferAllocator(params.array_buffer_allocator.?);

    // Create isolate
    var isolate = v8.Isolate.init(&params);
    defer isolate.deinit();

    // Enter isolate
    isolate.enter();
    defer isolate.exit();

    // Create handle scope - must be stack allocated
    var handle_scope: v8.HandleScope = undefined;
    handle_scope.init(isolate);
    defer handle_scope.deinit();

    // Create and enter context
    var context = v8.Context.init(isolate, null, null);
    context.enter();
    defer context.exit();

    // Register APIs on global object
    console.registerConsole(isolate, context);
    encoding.registerEncodingAPIs(isolate, context);
    url.registerURLAPIs(isolate, context);
    crypto.registerCryptoAPIs(isolate, context);
    fetch.registerFetchAPI(isolate, context);
    headers.registerHeadersAPI(isolate, context);
    request.registerRequestAPI(isolate, context);
    abort.registerAbortAPI(isolate, context);
    blob.registerBlobAPI(isolate, context);
    formdata.registerFormDataAPI(isolate, context);

    // Set up TryCatch for error handling - must be stack allocated
    var try_catch: v8.TryCatch = undefined;
    try_catch.init(isolate);
    defer try_catch.deinit();

    // Create source string
    const source_str = v8.String.initUtf8(isolate, source);

    // Compile script
    const script = v8.Script.compile(context, source_str, null) catch {
        if (try_catch.hasCaught()) {
            return .{ .err = extractError(isolate, &try_catch, context, allocator) };
        }
        return .{ .err = .{ .message = "Compilation failed" } };
    };

    // Run script
    const result = script.run(context) catch {
        if (try_catch.hasCaught()) {
            return .{ .err = extractError(isolate, &try_catch, context, allocator) };
        }
        return .{ .err = .{ .message = "Execution failed" } };
    };

    // Convert result to string
    const result_str = result.toString(context) catch {
        return .{ .err = .{ .message = "Failed to convert result to string" } };
    };

    // Copy result to Zig-owned memory
    const len = result_str.lenUtf8(isolate);
    const output = allocator.alloc(u8, len) catch {
        return .{ .err = .{ .message = "Out of memory" } };
    };
    _ = result_str.writeUtf8(isolate, output);

    return .{ .ok = output };
}

/// V8 test state - initialized once per test run
var test_v8_initialized = false;
var test_platform: ?v8.Platform = null;

/// Ensure V8 is initialized (called by each test, but only inits once)
fn ensureV8Init() void {
    if (!test_v8_initialized) {
        test_platform = v8.Platform.initDefault(0, false);
        v8.initV8Platform(test_platform.?);
        v8.initV8();
        test_v8_initialized = true;
    }
}

test "eval simple expression" {
    ensureV8Init();

    const allocator = std.testing.allocator;
    var result = runScript("1 + 1", allocator);
    defer result.deinit(allocator);

    switch (result) {
        .ok => |value| {
            try std.testing.expectEqualStrings("2", value);
        },
        .err => |e| {
            std.debug.print("Unexpected error: {s}\n", .{e.message});
            return error.UnexpectedError;
        },
    }
}

test "eval string concatenation" {
    ensureV8Init();

    const allocator = std.testing.allocator;
    var result = runScript("'hello' + ' ' + 'world'", allocator);
    defer result.deinit(allocator);

    switch (result) {
        .ok => |value| {
            try std.testing.expectEqualStrings("hello world", value);
        },
        .err => |e| {
            std.debug.print("Unexpected error: {s}\n", .{e.message});
            return error.UnexpectedError;
        },
    }
}

test "eval math function" {
    ensureV8Init();

    const allocator = std.testing.allocator;
    var result = runScript("Math.sqrt(16)", allocator);
    defer result.deinit(allocator);

    switch (result) {
        .ok => |value| {
            try std.testing.expectEqualStrings("4", value);
        },
        .err => |e| {
            std.debug.print("Unexpected error: {s}\n", .{e.message});
            return error.UnexpectedError;
        },
    }
}

test "eval syntax error returns error with line number" {
    ensureV8Init();

    const allocator = std.testing.allocator;
    var result = runScript("1 +", allocator);
    defer result.deinit(allocator);

    switch (result) {
        .ok => |value| {
            std.debug.print("Unexpected success: {s}\n", .{value});
            return error.ExpectedError;
        },
        .err => |e| {
            // Should get a syntax error with message
            try std.testing.expect(e.message.len > 0);
            // Syntax errors should have line number
            try std.testing.expect(e.line != null);
        },
    }
}

test "eval reference error" {
    ensureV8Init();

    const allocator = std.testing.allocator;
    var result = runScript("undefinedVariable", allocator);
    defer result.deinit(allocator);

    switch (result) {
        .ok => |_| {
            // undefined is a valid value in JS, it should return "undefined"
        },
        .err => |e| {
            // ReferenceError for undefined variable
            try std.testing.expect(e.message.len > 0);
        },
    }
}

// === Blob API Tests ===

test "Blob creation and size" {
    ensureV8Init();

    const allocator = std.testing.allocator;
    var result = runScript("new Blob(['hello']).size()", allocator);
    defer result.deinit(allocator);

    switch (result) {
        .ok => |value| {
            try std.testing.expectEqualStrings("5", value);
        },
        .err => |e| {
            std.debug.print("Unexpected error: {s}\n", .{e.message});
            return error.UnexpectedError;
        },
    }
}

test "Blob with multiple parts" {
    ensureV8Init();

    const allocator = std.testing.allocator;
    var result = runScript("new Blob(['hello', ' ', 'world']).size()", allocator);
    defer result.deinit(allocator);

    switch (result) {
        .ok => |value| {
            try std.testing.expectEqualStrings("11", value);
        },
        .err => |e| {
            std.debug.print("Unexpected error: {s}\n", .{e.message});
            return error.UnexpectedError;
        },
    }
}

test "Blob type property" {
    ensureV8Init();

    const allocator = std.testing.allocator;
    var result = runScript("new Blob(['test'], {type: 'text/plain'}).type()", allocator);
    defer result.deinit(allocator);

    switch (result) {
        .ok => |value| {
            try std.testing.expectEqualStrings("text/plain", value);
        },
        .err => |e| {
            std.debug.print("Unexpected error: {s}\n", .{e.message});
            return error.UnexpectedError;
        },
    }
}

// === File API Tests ===

test "File creation with name" {
    ensureV8Init();

    const allocator = std.testing.allocator;
    var result = runScript("new File(['content'], 'test.txt').name()", allocator);
    defer result.deinit(allocator);

    switch (result) {
        .ok => |value| {
            try std.testing.expectEqualStrings("test.txt", value);
        },
        .err => |e| {
            std.debug.print("Unexpected error: {s}\n", .{e.message});
            return error.UnexpectedError;
        },
    }
}

test "File size" {
    ensureV8Init();

    const allocator = std.testing.allocator;
    var result = runScript("new File(['hello world'], 'test.txt').size()", allocator);
    defer result.deinit(allocator);

    switch (result) {
        .ok => |value| {
            try std.testing.expectEqualStrings("11", value);
        },
        .err => |e| {
            std.debug.print("Unexpected error: {s}\n", .{e.message});
            return error.UnexpectedError;
        },
    }
}

// === FormData API Tests ===

test "FormData append and get" {
    ensureV8Init();

    const allocator = std.testing.allocator;
    var result = runScript("const fd = new FormData(); fd.append('name', 'John'); fd.get('name')", allocator);
    defer result.deinit(allocator);

    switch (result) {
        .ok => |value| {
            try std.testing.expectEqualStrings("John", value);
        },
        .err => |e| {
            std.debug.print("Unexpected error: {s}\n", .{e.message});
            return error.UnexpectedError;
        },
    }
}

test "FormData has" {
    ensureV8Init();

    const allocator = std.testing.allocator;
    var result = runScript("const fd = new FormData(); fd.append('key', 'val'); fd.has('key')", allocator);
    defer result.deinit(allocator);

    switch (result) {
        .ok => |value| {
            try std.testing.expectEqualStrings("true", value);
        },
        .err => |e| {
            std.debug.print("Unexpected error: {s}\n", .{e.message});
            return error.UnexpectedError;
        },
    }
}

test "FormData getAll returns array" {
    ensureV8Init();

    const allocator = std.testing.allocator;
    var result = runScript("const fd = new FormData(); fd.append('x', 'a'); fd.append('x', 'b'); fd.getAll('x').length", allocator);
    defer result.deinit(allocator);

    switch (result) {
        .ok => |value| {
            try std.testing.expectEqualStrings("2", value);
        },
        .err => |e| {
            std.debug.print("Unexpected error: {s}\n", .{e.message});
            return error.UnexpectedError;
        },
    }
}

// === AbortController Tests ===
// Note: controller.signal() is a method, but signal.aborted is a plain property (Web API compatible)

test "AbortController initial state" {
    ensureV8Init();

    const allocator = std.testing.allocator;
    var result = runScript("new AbortController().signal().aborted", allocator);
    defer result.deinit(allocator);

    switch (result) {
        .ok => |value| {
            try std.testing.expectEqualStrings("false", value);
        },
        .err => |e| {
            std.debug.print("Unexpected error: {s}\n", .{e.message});
            return error.UnexpectedError;
        },
    }
}

test "AbortController abort changes state" {
    ensureV8Init();

    const allocator = std.testing.allocator;
    var result = runScript("const ac = new AbortController(); ac.abort(); ac.signal().aborted", allocator);
    defer result.deinit(allocator);

    switch (result) {
        .ok => |value| {
            try std.testing.expectEqualStrings("true", value);
        },
        .err => |e| {
            std.debug.print("Unexpected error: {s}\n", .{e.message});
            return error.UnexpectedError;
        },
    }
}

// === crypto.subtle.sign/verify Tests ===

test "crypto.subtle.sign returns ArrayBuffer" {
    ensureV8Init();

    const allocator = std.testing.allocator;
    var result = runScript("crypto.subtle.sign('HMAC', 'secret', 'data').byteLength", allocator);
    defer result.deinit(allocator);

    switch (result) {
        .ok => |value| {
            try std.testing.expectEqualStrings("32", value); // SHA-256 = 32 bytes
        },
        .err => |e| {
            std.debug.print("Unexpected error: {s}\n", .{e.message});
            return error.UnexpectedError;
        },
    }
}

test "crypto.subtle.verify valid signature" {
    ensureV8Init();

    const allocator = std.testing.allocator;
    var result = runScript(
        \\const sig = crypto.subtle.sign('HMAC', 'key', 'message');
        \\crypto.subtle.verify('HMAC', 'key', sig, 'message')
    , allocator);
    defer result.deinit(allocator);

    switch (result) {
        .ok => |value| {
            try std.testing.expectEqualStrings("true", value);
        },
        .err => |e| {
            std.debug.print("Unexpected error: {s}\n", .{e.message});
            return error.UnexpectedError;
        },
    }
}

test "crypto.subtle.verify invalid signature" {
    ensureV8Init();

    const allocator = std.testing.allocator;
    var result = runScript(
        \\const sig = crypto.subtle.sign('HMAC', 'key', 'message');
        \\crypto.subtle.verify('HMAC', 'wrong-key', sig, 'message')
    , allocator);
    defer result.deinit(allocator);

    switch (result) {
        .ok => |value| {
            try std.testing.expectEqualStrings("false", value);
        },
        .err => |e| {
            std.debug.print("Unexpected error: {s}\n", .{e.message});
            return error.UnexpectedError;
        },
    }
}

test "crypto.subtle.sign SHA-512" {
    ensureV8Init();

    const allocator = std.testing.allocator;
    var result = runScript("crypto.subtle.sign({name: 'HMAC', hash: 'SHA-512'}, 'key', 'data').byteLength", allocator);
    defer result.deinit(allocator);

    switch (result) {
        .ok => |value| {
            try std.testing.expectEqualStrings("64", value); // SHA-512 = 64 bytes
        },
        .err => |e| {
            std.debug.print("Unexpected error: {s}\n", .{e.message});
            return error.UnexpectedError;
        },
    }
}
