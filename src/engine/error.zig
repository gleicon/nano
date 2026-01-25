const std = @import("std");
const v8 = @import("v8");

/// Represents an error from JavaScript execution
pub const ScriptError = struct {
    message: []const u8,
    line: ?u32 = null,
    column: ?u32 = null,
    source_line: ?[]const u8 = null,

    /// Format the error as a human-readable string
    /// Caller owns the returned memory
    pub fn format(self: ScriptError, allocator: std.mem.Allocator) ![]const u8 {
        if (self.line) |line| {
            if (self.column) |col| {
                return std.fmt.allocPrint(allocator, "Error at line {d}, column {d}: {s}", .{ line, col, self.message });
            }
            return std.fmt.allocPrint(allocator, "Error at line {d}: {s}", .{ line, self.message });
        }
        return std.fmt.allocPrint(allocator, "Error: {s}", .{self.message});
    }

    /// Free memory allocated for this error (message and source_line)
    pub fn deinit(self: *ScriptError, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        if (self.source_line) |sl| {
            allocator.free(sl);
        }
    }
};

/// Extract error information from a V8 TryCatch
/// Returns ScriptError with message and location info
/// The message and source_line strings are allocated using the provided allocator
pub fn extractError(
    isolate: v8.Isolate,
    try_catch: *v8.TryCatch,
    context: v8.Context,
    allocator: std.mem.Allocator,
) ScriptError {
    // Get the exception message
    const message = try_catch.getMessage() orelse {
        return ScriptError{ .message = "Unknown error" };
    };

    // Get the message string
    const msg_str = message.getMessage();
    const msg_len = msg_str.lenUtf8(isolate);
    const msg_buf = allocator.alloc(u8, msg_len) catch {
        return ScriptError{ .message = "Error extracting message (out of memory)" };
    };
    _ = msg_str.writeUtf8(isolate, msg_buf);

    // Get line number
    const line = message.getLineNumber(context);

    // Get column
    const column = message.getStartColumn();

    // Get source line if available
    var source_line: ?[]const u8 = null;
    if (message.getSourceLine(context)) |src_line_str| {
        const src_len = src_line_str.lenUtf8(isolate);
        if (allocator.alloc(u8, src_len)) |src_buf| {
            _ = src_line_str.writeUtf8(isolate, src_buf);
            source_line = src_buf;
        } else |_| {
            // Ignore allocation failure for source line - it's optional
        }
    }

    return ScriptError{
        .message = msg_buf,
        .line = line,
        .column = column,
        .source_line = source_line,
    };
}
