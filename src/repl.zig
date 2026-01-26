const std = @import("std");
const v8 = @import("v8");
const console = @import("console");
const encoding = @import("encoding");
const url = @import("url");
const crypto = @import("crypto");
const fetch = @import("fetch");
const headers_api = @import("headers");
const request_api = @import("request");
const abort = @import("abort");
const blob = @import("blob");
const formdata = @import("formdata");

/// Read a line from stdin into buffer, returns slice or null on EOF
fn readLine(buf: []u8) ?[]u8 {
    var i: usize = 0;
    while (i < buf.len) {
        var byte_buf: [1]u8 = undefined;
        const n = std.posix.read(std.posix.STDIN_FILENO, &byte_buf) catch return null;
        if (n == 0) {
            // EOF
            if (i == 0) return null;
            return buf[0..i];
        }
        const byte = byte_buf[0];
        if (byte == '\n') {
            return buf[0..i];
        }
        buf[i] = byte;
        i += 1;
    }
    // Buffer full
    return buf[0..i];
}

/// Run interactive REPL with persistent context
pub fn runRepl() !void {
    const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    const stderr = std.fs.File{ .handle = std.posix.STDERR_FILENO };

    // Initialize V8 platform once
    const platform = v8.Platform.initDefault(0, false);
    defer platform.deinit();

    v8.initV8Platform(platform);
    v8.initV8();
    defer {
        _ = v8.deinitV8();
        v8.deinitV8Platform();
    }

    // Create persistent isolate
    var params = v8.initCreateParams();
    params.array_buffer_allocator = v8.createDefaultArrayBufferAllocator();
    defer v8.destroyArrayBufferAllocator(params.array_buffer_allocator.?);

    var isolate = v8.Isolate.init(&params);
    defer isolate.deinit();

    isolate.enter();
    defer isolate.exit();

    var handle_scope: v8.HandleScope = undefined;
    handle_scope.init(isolate);
    defer handle_scope.deinit();

    // Create persistent context
    var context = v8.Context.init(isolate, null, null);
    context.enter();
    defer context.exit();

    // Register APIs
    console.registerConsole(isolate, context);
    encoding.registerEncodingAPIs(isolate, context);
    url.registerURLAPIs(isolate, context);
    crypto.registerCryptoAPIs(isolate, context);
    fetch.registerFetchAPI(isolate, context);
    headers_api.registerHeadersAPI(isolate, context);
    request_api.registerRequestAPI(isolate, context);
    abort.registerAbortAPI(isolate, context);
    blob.registerBlobAPI(isolate, context);
    formdata.registerFormDataAPI(isolate, context);

    // Print banner
    stdout.writeAll("nano REPL (V8 ") catch {};
    stdout.writeAll(v8.getVersion()) catch {};
    stdout.writeAll(")\n") catch {};
    stdout.writeAll("Type 'exit' or Ctrl+D to quit\n\n") catch {};

    var line_buf: [4096]u8 = undefined;
    var accumulated: std.ArrayList(u8) = .{};
    defer accumulated.deinit(std.heap.page_allocator);

    var continuation = false;

    while (true) {
        // Print prompt
        if (continuation) {
            stdout.writeAll("...  ") catch {};
        } else {
            stdout.writeAll("nano> ") catch {};
        }

        // Read line
        const line = readLine(&line_buf) orelse {
            // EOF (Ctrl+D)
            stdout.writeAll("\n") catch {};
            break;
        };

        // Check for exit commands
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (!continuation) {
            if (std.mem.eql(u8, trimmed, "exit") or
                std.mem.eql(u8, trimmed, ".exit") or
                std.mem.eql(u8, trimmed, "quit"))
            {
                break;
            }

            // Skip empty lines
            if (trimmed.len == 0) continue;
        }

        // Accumulate lines
        accumulated.appendSlice(std.heap.page_allocator, line) catch continue;
        accumulated.append(std.heap.page_allocator, '\n') catch continue;

        // Try to compile
        const source = accumulated.items;

        var try_catch: v8.TryCatch = undefined;
        try_catch.init(isolate);
        defer try_catch.deinit();

        const source_str = v8.String.initUtf8(isolate, source);
        const script_opt = v8.Script.compile(context, source_str, null) catch {
            // Check if it's an incomplete expression
            if (try_catch.hasCaught()) {
                const msg = try_catch.getMessage();
                if (msg) |m| {
                    const msg_str = m.getMessage();
                    var msg_buf: [256]u8 = undefined;
                    const msg_len = msg_str.writeUtf8(isolate, &msg_buf);
                    const msg_text = msg_buf[0..msg_len];

                    // Check for incomplete expression
                    if (std.mem.indexOf(u8, msg_text, "Unexpected end of input") != null) {
                        continuation = true;
                        continue;
                    }
                }

                // Real syntax error
                printError(isolate, &try_catch, context, stderr);
            }
            accumulated.clearRetainingCapacity();
            continuation = false;
            continue;
        };

        // Run script
        const result_opt = script_opt.run(context) catch {
            if (try_catch.hasCaught()) {
                printError(isolate, &try_catch, context, stderr);
            }
            accumulated.clearRetainingCapacity();
            continuation = false;
            continue;
        };

        // Print result
        if (result_opt.isUndefined()) {
            stdout.writeAll("undefined\n") catch {};
        } else {
            const result_str = result_opt.toString(context) catch {
                stdout.writeAll("[object]\n") catch {};
                accumulated.clearRetainingCapacity();
                continuation = false;
                continue;
            };
            var result_buf: [4096]u8 = undefined;
            const result_len = result_str.writeUtf8(isolate, &result_buf);
            stdout.writeAll(result_buf[0..result_len]) catch {};
            stdout.writeAll("\n") catch {};
        }

        accumulated.clearRetainingCapacity();
        continuation = false;
    }
}

fn printError(isolate: v8.Isolate, try_catch: *v8.TryCatch, context: v8.Context, stderr: std.fs.File) void {
    const msg = try_catch.getMessage() orelse {
        stderr.writeAll("Error: unknown\n") catch {};
        return;
    };

    const msg_str = msg.getMessage();
    var buf: [1024]u8 = undefined;
    const len = msg_str.writeUtf8(isolate, &buf);

    const line = msg.getLineNumber(context);
    if (line != null and line.? > 0) {
        var line_buf: [32]u8 = undefined;
        const line_str = std.fmt.bufPrint(&line_buf, "{d}", .{line.?}) catch "?";
        stderr.writeAll("Error at line ") catch {};
        stderr.writeAll(line_str) catch {};
        stderr.writeAll(": ") catch {};
    } else {
        stderr.writeAll("Error: ") catch {};
    }
    stderr.writeAll(buf[0..len]) catch {};
    stderr.writeAll("\n") catch {};
}
