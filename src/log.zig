const std = @import("std");
const posix = std.posix;

pub const Level = enum {
    debug,
    info,
    warn,
    err,

    pub fn string(self: Level) []const u8 {
        return switch (self) {
            .debug => "debug",
            .info => "info",
            .warn => "warn",
            .err => "error",
        };
    }
};

pub const Format = enum {
    json,
    text,
    apache, // Apache Combined Log Format for HTTP requests
};

pub const Output = enum {
    stdout,
    stderr,
};

pub const Config = struct {
    output: Output = .stdout,
    format: Format = .json,
    min_level: Level = .info,
};

pub const Logger = struct {
    config: Config,
    context_buf: [256]u8 = undefined,
    context_len: usize = 0,

    pub fn init(config: Config) Logger {
        return Logger{
            .config = config,
        };
    }

    pub fn debug(self: *Logger, event: []const u8, fields: anytype) void {
        self.log(.debug, event, fields);
    }

    pub fn info(self: *Logger, event: []const u8, fields: anytype) void {
        self.log(.info, event, fields);
    }

    pub fn warn(self: *Logger, event: []const u8, fields: anytype) void {
        self.log(.warn, event, fields);
    }

    pub fn err(self: *Logger, event: []const u8, fields: anytype) void {
        self.log(.err, event, fields);
    }

    pub fn log(self: *Logger, level: Level, event: []const u8, fields: anytype) void {
        if (@intFromEnum(level) < @intFromEnum(self.config.min_level)) return;

        const fd: posix.fd_t = switch (self.config.output) {
            .stdout => posix.STDOUT_FILENO,
            .stderr => posix.STDERR_FILENO,
        };

        const file = std.fs.File{ .handle = fd };

        switch (self.config.format) {
            .json => self.writeJson(file, level, event, fields),
            .text => self.writeText(file, level, event, fields),
            .apache => self.writeApache(file, level, event, fields),
        }
    }

    fn writeJson(self: *Logger, file: std.fs.File, level: Level, event: []const u8, fields: anytype) void {
        _ = self;
        var buf: [1024]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buf);
        const writer = stream.writer();

        const ts = std.time.timestamp();

        writer.print("{{\"ts\":{d},\"level\":\"{s}\",\"event\":\"{s}\"", .{
            ts,
            level.string(),
            event,
        }) catch return;

        // Write fields
        const T = @TypeOf(fields);
        const type_info = @typeInfo(T);

        if (type_info == .@"struct") {
            inline for (type_info.@"struct".fields) |field| {
                const value = @field(fields, field.name);
                writeField(writer, field.name, value) catch return;
            }
        }

        writer.writeAll("}\n") catch return;
        file.writeAll(stream.getWritten()) catch {};
    }

    fn writeText(self: *Logger, file: std.fs.File, level: Level, event: []const u8, fields: anytype) void {
        _ = self;
        var buf: [1024]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buf);
        const writer = stream.writer();

        // Format: [LEVEL] event key=value key=value
        writer.print("[{s}] {s}", .{ level.string(), event }) catch return;

        const T = @TypeOf(fields);
        const type_info = @typeInfo(T);

        if (type_info == .@"struct") {
            inline for (type_info.@"struct".fields) |field| {
                const value = @field(fields, field.name);
                writer.writeAll(" ") catch return;
                writer.writeAll(field.name) catch return;
                writer.writeAll("=") catch return;
                writeTextValue(writer, value) catch return;
            }
        }

        writer.writeAll("\n") catch return;
        file.writeAll(stream.getWritten()) catch {};
    }

    /// Apache Combined Log Format for HTTP requests
    /// Format: %h %l %u %t "%r" %>s %b
    /// Example: 127.0.0.1 - - [25/Jan/2026:12:00:00 +0000] "GET /path HTTP/1.1" 200 1234
    fn writeApache(self: *Logger, file: std.fs.File, level: Level, event: []const u8, fields: anytype) void {
        _ = self;
        _ = level;
        _ = event;

        var buf: [1024]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buf);
        const writer = stream.writer();

        const T = @TypeOf(fields);
        const type_info = @typeInfo(T);

        // Extract fields by name
        var method: []const u8 = "-";
        var path: []const u8 = "-";
        var status: u16 = 0;
        var bytes: usize = 0;

        if (type_info == .@"struct") {
            inline for (type_info.@"struct".fields) |field| {
                const value = @field(fields, field.name);
                if (comptime std.mem.eql(u8, field.name, "method")) {
                    method = value;
                } else if (comptime std.mem.eql(u8, field.name, "path")) {
                    path = value;
                } else if (comptime std.mem.eql(u8, field.name, "status")) {
                    status = value;
                } else if (comptime std.mem.eql(u8, field.name, "bytes")) {
                    bytes = value;
                }
            }
        }

        // Get timestamp in Apache format: [DD/Mon/YYYY:HH:MM:SS +0000]
        const ts = std.time.timestamp();
        const epoch_seconds: u64 = @intCast(ts);
        const epoch_day = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
        const day_seconds = epoch_day.getDaySeconds();
        const year_day = epoch_day.getEpochDay().calculateYearDay();

        const months = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
        const month_day = year_day.calculateMonthDay();

        writer.print("127.0.0.1 - - [{d:0>2}/{s}/{d}:{d:0>2}:{d:0>2}:{d:0>2} +0000] \"{s} {s} HTTP/1.1\" {d} {d}\n", .{
            month_day.day_index + 1,
            months[month_day.month.numeric() - 1],
            year_day.year,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
            method,
            path,
            status,
            bytes,
        }) catch return;

        file.writeAll(stream.getWritten()) catch {};
    }
};

fn writeField(writer: anytype, name: []const u8, value: anytype) !void {
    const T = @TypeOf(value);

    try writer.writeAll(",\"");
    try writer.writeAll(name);
    try writer.writeAll("\":");

    switch (@typeInfo(T)) {
        .int, .comptime_int => try writer.print("{d}", .{value}),
        .float, .comptime_float => try writer.print("{d:.2}", .{value}),
        .bool => try writer.writeAll(if (value) "true" else "false"),
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                try writer.writeAll("\"");
                try writer.writeAll(value);
                try writer.writeAll("\"");
            } else {
                try writer.writeAll("\"[pointer]\"");
            }
        },
        .optional => {
            if (value) |v| {
                try writeFieldValue(writer, v);
            } else {
                try writer.writeAll("null");
            }
        },
        else => try writer.writeAll("\"[unsupported]\""),
    }
}

fn writeFieldValue(writer: anytype, value: anytype) !void {
    const T = @TypeOf(value);

    switch (@typeInfo(T)) {
        .int, .comptime_int => try writer.print("{d}", .{value}),
        .float, .comptime_float => try writer.print("{d:.2}", .{value}),
        .bool => try writer.writeAll(if (value) "true" else "false"),
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                try writer.writeAll("\"");
                try writer.writeAll(value);
                try writer.writeAll("\"");
            } else {
                try writer.writeAll("\"[pointer]\"");
            }
        },
        else => try writer.writeAll("\"[unsupported]\""),
    }
}

fn writeTextValue(writer: anytype, value: anytype) !void {
    const T = @TypeOf(value);

    switch (@typeInfo(T)) {
        .int, .comptime_int => try writer.print("{d}", .{value}),
        .float, .comptime_float => try writer.print("{d:.2}", .{value}),
        .bool => try writer.writeAll(if (value) "true" else "false"),
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                try writer.writeAll(value);
            } else {
                try writer.writeAll("[pointer]");
            }
        },
        .optional => {
            if (value) |v| {
                try writeTextValue(writer, v);
            } else {
                try writer.writeAll("null");
            }
        },
        else => try writer.writeAll("[unsupported]"),
    }
}

// Convenience: create default logger
pub fn init(config: Config) Logger {
    return Logger.init(config);
}

// Global default loggers for common use
pub fn stdout() Logger {
    return init(.{ .output = .stdout, .format = .json });
}

pub fn stderr() Logger {
    return init(.{ .output = .stderr, .format = .json });
}

pub fn apache() Logger {
    return init(.{ .output = .stdout, .format = .apache });
}
