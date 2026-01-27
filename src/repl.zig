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
const posix = std.posix;

/// Simple line editor with history support
const LineEditor = struct {
    allocator: std.mem.Allocator,
    history: std.ArrayListUnmanaged([]u8),
    history_index: usize,
    line_buf: [4096]u8,
    line_len: usize,
    cursor: usize,
    original_termios: ?posix.termios,

    pub fn init(allocator: std.mem.Allocator) LineEditor {
        return .{
            .allocator = allocator,
            .history = .empty,
            .history_index = 0,
            .line_buf = undefined,
            .line_len = 0,
            .cursor = 0,
            .original_termios = null,
        };
    }

    pub fn deinit(self: *LineEditor) void {
        for (self.history.items) |item| {
            self.allocator.free(item);
        }
        self.history.deinit(self.allocator);
        self.restoreTerminal();
    }

    fn enableRawMode(self: *LineEditor) !void {
        if (!posix.isatty(posix.STDIN_FILENO)) return;

        self.original_termios = posix.tcgetattr(posix.STDIN_FILENO) catch return;
        var raw = self.original_termios.?;

        // Disable echo and canonical mode
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.ISIG = false;
        raw.lflag.IEXTEN = false;

        // Disable input processing
        raw.iflag.IXON = false;
        raw.iflag.ICRNL = false;
        raw.iflag.BRKINT = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;

        // Set character size
        raw.cflag.CSIZE = .CS8;

        // Read returns after 1 byte or 100ms timeout
        raw.cc[@intFromEnum(posix.V.MIN)] = 1;
        raw.cc[@intFromEnum(posix.V.TIME)] = 0;

        posix.tcsetattr(posix.STDIN_FILENO, .NOW, raw) catch {};
    }

    fn restoreTerminal(self: *LineEditor) void {
        if (self.original_termios) |termios| {
            posix.tcsetattr(posix.STDIN_FILENO, .NOW, termios) catch {};
            self.original_termios = null;
        }
    }

    fn readByte() ?u8 {
        var buf: [1]u8 = undefined;
        const n = posix.read(posix.STDIN_FILENO, &buf) catch return null;
        if (n == 0) return null;
        return buf[0];
    }

    fn writeStr(s: []const u8) void {
        _ = posix.write(posix.STDOUT_FILENO, s) catch {};
    }

    fn writeChar(c: u8) void {
        _ = posix.write(posix.STDOUT_FILENO, &[_]u8{c}) catch {};
    }

    fn refreshLine(self: *LineEditor, prompt: []const u8) void {
        // Move to start of line, clear, write prompt and buffer
        writeStr("\r\x1b[K"); // Carriage return + clear to end of line
        writeStr(prompt);
        writeStr(self.line_buf[0..self.line_len]);

        // Move cursor to correct position
        if (self.cursor < self.line_len) {
            var move_buf: [32]u8 = undefined;
            const move_len = std.fmt.bufPrint(&move_buf, "\x1b[{d}D", .{self.line_len - self.cursor}) catch return;
            writeStr(move_len);
        }
    }

    pub fn readline(self: *LineEditor, prompt: []const u8) ?[]const u8 {
        self.line_len = 0;
        self.cursor = 0;
        self.history_index = self.history.items.len;

        self.enableRawMode() catch {};
        defer self.restoreTerminal();

        writeStr(prompt);

        while (true) {
            const c = readByte() orelse {
                // EOF
                writeStr("\n");
                return null;
            };

            switch (c) {
                '\r', '\n' => {
                    writeStr("\n");
                    if (self.line_len > 0) {
                        return self.line_buf[0..self.line_len];
                    }
                    return "";
                },
                3 => { // Ctrl+C
                    writeStr("^C\n");
                    self.line_len = 0;
                    self.cursor = 0;
                    return "";
                },
                4 => { // Ctrl+D (EOF)
                    if (self.line_len == 0) {
                        writeStr("\n");
                        return null;
                    }
                },
                127, 8 => { // Backspace
                    if (self.cursor > 0) {
                        // Move chars after cursor back
                        if (self.cursor < self.line_len) {
                            std.mem.copyForwards(
                                u8,
                                self.line_buf[self.cursor - 1 .. self.line_len - 1],
                                self.line_buf[self.cursor..self.line_len],
                            );
                        }
                        self.cursor -= 1;
                        self.line_len -= 1;
                        self.refreshLine(prompt);
                    }
                },
                1 => { // Ctrl+A - go to start
                    self.cursor = 0;
                    self.refreshLine(prompt);
                },
                5 => { // Ctrl+E - go to end
                    self.cursor = self.line_len;
                    self.refreshLine(prompt);
                },
                21 => { // Ctrl+U - clear line
                    self.line_len = 0;
                    self.cursor = 0;
                    self.refreshLine(prompt);
                },
                27 => { // Escape sequence
                    const seq1 = readByte() orelse continue;
                    if (seq1 == '[') {
                        const seq2 = readByte() orelse continue;
                        switch (seq2) {
                            'A' => { // Up arrow - previous history
                                if (self.history_index > 0) {
                                    self.history_index -= 1;
                                    const entry = self.history.items[self.history_index];
                                    const copy_len = @min(entry.len, self.line_buf.len);
                                    @memcpy(self.line_buf[0..copy_len], entry[0..copy_len]);
                                    self.line_len = copy_len;
                                    self.cursor = copy_len;
                                    self.refreshLine(prompt);
                                }
                            },
                            'B' => { // Down arrow - next history
                                if (self.history_index < self.history.items.len) {
                                    self.history_index += 1;
                                    if (self.history_index < self.history.items.len) {
                                        const entry = self.history.items[self.history_index];
                                        const copy_len = @min(entry.len, self.line_buf.len);
                                        @memcpy(self.line_buf[0..copy_len], entry[0..copy_len]);
                                        self.line_len = copy_len;
                                        self.cursor = copy_len;
                                    } else {
                                        self.line_len = 0;
                                        self.cursor = 0;
                                    }
                                    self.refreshLine(prompt);
                                }
                            },
                            'C' => { // Right arrow
                                if (self.cursor < self.line_len) {
                                    self.cursor += 1;
                                    writeStr("\x1b[C");
                                }
                            },
                            'D' => { // Left arrow
                                if (self.cursor > 0) {
                                    self.cursor -= 1;
                                    writeStr("\x1b[D");
                                }
                            },
                            'H' => { // Home
                                self.cursor = 0;
                                self.refreshLine(prompt);
                            },
                            'F' => { // End
                                self.cursor = self.line_len;
                                self.refreshLine(prompt);
                            },
                            '3' => { // Delete key (ESC[3~)
                                _ = readByte(); // consume '~'
                                if (self.cursor < self.line_len) {
                                    std.mem.copyForwards(
                                        u8,
                                        self.line_buf[self.cursor .. self.line_len - 1],
                                        self.line_buf[self.cursor + 1 .. self.line_len],
                                    );
                                    self.line_len -= 1;
                                    self.refreshLine(prompt);
                                }
                            },
                            else => {},
                        }
                    }
                },
                else => {
                    // Printable character
                    if (c >= 32 and self.line_len < self.line_buf.len - 1) {
                        // Insert at cursor
                        if (self.cursor < self.line_len) {
                            std.mem.copyBackwards(
                                u8,
                                self.line_buf[self.cursor + 1 .. self.line_len + 1],
                                self.line_buf[self.cursor..self.line_len],
                            );
                        }
                        self.line_buf[self.cursor] = c;
                        self.cursor += 1;
                        self.line_len += 1;
                        self.refreshLine(prompt);
                    }
                },
            }
        }
    }

    pub fn addHistory(self: *LineEditor, line: []const u8) void {
        if (line.len == 0) return;

        // Don't add duplicates of the last entry
        if (self.history.items.len > 0) {
            const last = self.history.items[self.history.items.len - 1];
            if (std.mem.eql(u8, last, line)) return;
        }

        const copy = self.allocator.dupe(u8, line) catch return;
        self.history.append(self.allocator, copy) catch {
            self.allocator.free(copy);
            return;
        };

        // Limit history size
        if (self.history.items.len > 1000) {
            self.allocator.free(self.history.items[0]);
            _ = self.history.orderedRemove(0);
        }
    }
};

/// Run interactive REPL with persistent context
pub fn runRepl() !void {
    const stdout = std.fs.File{ .handle = posix.STDOUT_FILENO };
    const stderr = std.fs.File{ .handle = posix.STDERR_FILENO };
    const allocator = std.heap.page_allocator;

    // Initialize line editor with history
    var editor = LineEditor.init(allocator);
    defer editor.deinit();

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
    stdout.writeAll("Type 'exit' or Ctrl+D to quit. Arrow keys for history.\n\n") catch {};

    var accumulated: std.ArrayListUnmanaged(u8) = .empty;
    defer accumulated.deinit(allocator);

    var continuation = false;

    while (true) {
        // Get prompt based on state
        const prompt: []const u8 = if (continuation) "...  " else "nano> ";

        // Read line with editing support
        const line = editor.readline(prompt) orelse {
            // EOF (Ctrl+D)
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

        // Add to history (non-empty lines only)
        if (trimmed.len > 0) {
            editor.addHistory(line);
        }

        // Accumulate lines
        accumulated.appendSlice(allocator, line) catch continue;
        accumulated.append(allocator, '\n') catch continue;

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
