const std = @import("std");

/// Configuration for a single app
pub const AppConfig = struct {
    name: []const u8,
    path: []const u8,
    port: u16,
    timeout_ms: u64,
    memory_mb: usize,
};

/// Default configuration values
pub const Defaults = struct {
    timeout_ms: u64 = 5000,
    memory_mb: usize = 128,
};

/// Root configuration structure
pub const Config = struct {
    apps: []AppConfig,
    defaults: Defaults,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Config) void {
        for (self.apps) |app| {
            self.allocator.free(app.name);
            self.allocator.free(app.path);
        }
        self.allocator.free(self.apps);
    }
};

/// Parse error types
pub const ParseError = error{
    FileNotFound,
    InvalidJson,
    MissingField,
    InvalidType,
    OutOfMemory,
};

/// Load and parse config from file path
pub fn loadConfig(allocator: std.mem.Allocator, path: []const u8) ParseError!Config {
    // Read file
    const file = std.fs.cwd().openFile(path, .{}) catch {
        return ParseError.FileNotFound;
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch {
        return ParseError.OutOfMemory;
    };
    defer allocator.free(content);

    return parseConfig(allocator, content);
}

/// Parse config from JSON string
pub fn parseConfig(allocator: std.mem.Allocator, json_content: []const u8) ParseError!Config {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_content, .{}) catch {
        return ParseError.InvalidJson;
    };
    defer parsed.deinit();

    const root = parsed.value;

    // Parse defaults
    var defaults = Defaults{};
    if (root.object.get("defaults")) |defaults_val| {
        if (defaults_val.object.get("timeout_ms")) |timeout| {
            if (timeout == .integer) {
                defaults.timeout_ms = @intCast(timeout.integer);
            }
        }
        if (defaults_val.object.get("memory_mb")) |memory| {
            if (memory == .integer) {
                defaults.memory_mb = @intCast(memory.integer);
            }
        }
    }

    // Parse apps array
    const apps_val = root.object.get("apps") orelse {
        return ParseError.MissingField;
    };
    if (apps_val != .array) {
        return ParseError.InvalidType;
    }

    const apps_array = apps_val.array.items;
    var apps = allocator.alloc(AppConfig, apps_array.len) catch {
        return ParseError.OutOfMemory;
    };
    errdefer allocator.free(apps);

    var i: usize = 0;
    for (apps_array) |app_val| {
        if (app_val != .object) {
            continue;
        }

        const app_obj = app_val.object;

        // Required fields
        const name_val = app_obj.get("name") orelse continue;
        const path_val = app_obj.get("path") orelse continue;
        const port_val = app_obj.get("port") orelse continue;

        if (name_val != .string or path_val != .string or port_val != .integer) {
            continue;
        }

        const name = allocator.dupe(u8, name_val.string) catch {
            return ParseError.OutOfMemory;
        };
        errdefer allocator.free(name);

        const path = allocator.dupe(u8, path_val.string) catch {
            allocator.free(name);
            return ParseError.OutOfMemory;
        };

        // Optional fields with defaults
        var timeout_ms = defaults.timeout_ms;
        var memory_mb = defaults.memory_mb;

        if (app_obj.get("timeout_ms")) |timeout| {
            if (timeout == .integer) {
                timeout_ms = @intCast(timeout.integer);
            }
        }
        if (app_obj.get("memory_mb")) |memory| {
            if (memory == .integer) {
                memory_mb = @intCast(memory.integer);
            }
        }

        apps[i] = AppConfig{
            .name = name,
            .path = path,
            .port = @intCast(port_val.integer),
            .timeout_ms = timeout_ms,
            .memory_mb = memory_mb,
        };
        i += 1;
    }

    // Trim apps array to actual size
    if (i < apps.len) {
        apps = allocator.realloc(apps, i) catch apps[0..i];
    }

    return Config{
        .apps = apps[0..i],
        .defaults = defaults,
        .allocator = allocator,
    };
}

// === Tests ===

test "parse valid config" {
    const json =
        \\{
        \\  "apps": [
        \\    {
        \\      "name": "test-app",
        \\      "path": "./test/app",
        \\      "port": 8080,
        \\      "timeout_ms": 3000,
        \\      "memory_mb": 64
        \\    }
        \\  ],
        \\  "defaults": {
        \\    "timeout_ms": 5000,
        \\    "memory_mb": 128
        \\  }
        \\}
    ;

    var config = try parseConfig(std.testing.allocator, json);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 1), config.apps.len);
    try std.testing.expectEqualStrings("test-app", config.apps[0].name);
    try std.testing.expectEqualStrings("./test/app", config.apps[0].path);
    try std.testing.expectEqual(@as(u16, 8080), config.apps[0].port);
    try std.testing.expectEqual(@as(u64, 3000), config.apps[0].timeout_ms);
    try std.testing.expectEqual(@as(usize, 64), config.apps[0].memory_mb);
}

test "parse config with defaults" {
    const json =
        \\{
        \\  "apps": [
        \\    {
        \\      "name": "app-with-defaults",
        \\      "path": "./app",
        \\      "port": 9000
        \\    }
        \\  ],
        \\  "defaults": {
        \\    "timeout_ms": 10000,
        \\    "memory_mb": 256
        \\  }
        \\}
    ;

    var config = try parseConfig(std.testing.allocator, json);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 1), config.apps.len);
    // App should use defaults
    try std.testing.expectEqual(@as(u64, 10000), config.apps[0].timeout_ms);
    try std.testing.expectEqual(@as(usize, 256), config.apps[0].memory_mb);
}

test "parse multiple apps" {
    const json =
        \\{
        \\  "apps": [
        \\    {"name": "app-a", "path": "./a", "port": 8081},
        \\    {"name": "app-b", "path": "./b", "port": 8082}
        \\  ]
        \\}
    ;

    var config = try parseConfig(std.testing.allocator, json);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 2), config.apps.len);
    try std.testing.expectEqualStrings("app-a", config.apps[0].name);
    try std.testing.expectEqual(@as(u16, 8081), config.apps[0].port);
    try std.testing.expectEqualStrings("app-b", config.apps[1].name);
    try std.testing.expectEqual(@as(u16, 8082), config.apps[1].port);
}

test "parse invalid json returns error" {
    const result = parseConfig(std.testing.allocator, "not valid json");
    try std.testing.expectError(ParseError.InvalidJson, result);
}

test "parse missing apps field returns error" {
    const json = "{}";
    const result = parseConfig(std.testing.allocator, json);
    try std.testing.expectError(ParseError.MissingField, result);
}
