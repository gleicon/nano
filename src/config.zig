const std = @import("std");

/// Single App Configuration 
pub const AppConfig = struct {
    name: []const u8,
    path: []const u8,
    hostname: []const u8, // Host header value for routing (e.g., "app-a.local")
    port: u16, // backwards compatibility, ignored in multi-app mode
    timeout_ms: u64,
    memory_mb: usize,
    env: ?std.StringHashMap([]const u8),
};

/// Default config
pub const Defaults = struct {
    timeout_ms: u64 = 5000,
    memory_mb: usize = 128,
};

/// Root config
pub const Config = struct {
    apps: []AppConfig,
    defaults: Defaults,
    allocator: std.mem.Allocator,
    port: u16, // Global port for virtual host mode

    pub fn deinit(self: *Config) void {
        for (self.apps) |app| {
            self.allocator.free(app.name);
            self.allocator.free(app.path);
            self.allocator.free(app.hostname);

            // Clean up environment variables HashMap
            if (app.env) |env_map| {
                var mut_map = env_map;
                var it = mut_map.iterator();
                while (it.next()) |entry| {
                    self.allocator.free(entry.key_ptr.*);
                    self.allocator.free(entry.value_ptr.*);
                }
                mut_map.deinit();
            }
        }
        self.allocator.free(self.apps);
    }
};

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

    // Parse global port (default 8080)
    var global_port: u16 = 8080;
    if (root.object.get("port")) |port_val| {
        if (port_val == .integer) {
            global_port = @intCast(port_val.integer);
        }
    }

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

        if (name_val != .string or path_val != .string) {
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
        errdefer allocator.free(path);

        // Hostname for routing (defaults to app name if not specified)
        const hostname_val = app_obj.get("hostname");
        const hostname = if (hostname_val) |hv|
            if (hv == .string) allocator.dupe(u8, hv.string) catch {
                return ParseError.OutOfMemory;
            } else allocator.dupe(u8, name_val.string) catch {
                return ParseError.OutOfMemory;
            }
        else
            allocator.dupe(u8, name_val.string) catch {
                return ParseError.OutOfMemory;
            };

        // Per-app port (optional, for backwards compatibility)
        var app_port = global_port;
        if (app_obj.get("port")) |port_val| {
            if (port_val == .integer) {
                app_port = @intCast(port_val.integer);
            }
        }

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

        // Parse optional environment variables
        var env_map: ?std.StringHashMap([]const u8) = null;
        if (app_obj.get("env")) |env_val| {
            if (env_val == .object) {
                var map = std.StringHashMap([]const u8).init(allocator);
                errdefer {
                    var it = map.iterator();
                    while (it.next()) |entry| {
                        allocator.free(entry.key_ptr.*);
                        allocator.free(entry.value_ptr.*);
                    }
                    map.deinit();
                }

                var env_it = env_val.object.iterator();
                while (env_it.next()) |entry| {
                    if (entry.value_ptr.* == .string) {
                        const key_copy = allocator.dupe(u8, entry.key_ptr.*) catch {
                            return ParseError.OutOfMemory;
                        };
                        errdefer allocator.free(key_copy);

                        const val_copy = allocator.dupe(u8, entry.value_ptr.*.string) catch {
                            return ParseError.OutOfMemory;
                        };
                        errdefer allocator.free(val_copy);

                        map.put(key_copy, val_copy) catch {
                            return ParseError.OutOfMemory;
                        };
                    }
                }
                env_map = map;
            }
        }

        apps[i] = AppConfig{
            .name = name,
            .path = path,
            .hostname = hostname,
            .port = app_port,
            .timeout_ms = timeout_ms,
            .memory_mb = memory_mb,
            .env = env_map,
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
        .port = global_port,
    };
}

// === Tests ===

test "parse valid config" {
    const json =
        \\{
        \\  "port": 8080,
        \\  "apps": [
        \\    {
        \\      "name": "test-app",
        \\      "path": "./test/app",
        \\      "hostname": "test.local",
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

    var cfg = try parseConfig(std.testing.allocator, json);
    defer cfg.deinit();

    try std.testing.expectEqual(@as(usize, 1), cfg.apps.len);
    try std.testing.expectEqual(@as(u16, 8080), cfg.port);
    try std.testing.expectEqualStrings("test-app", cfg.apps[0].name);
    try std.testing.expectEqualStrings("./test/app", cfg.apps[0].path);
    try std.testing.expectEqualStrings("test.local", cfg.apps[0].hostname);
    try std.testing.expectEqual(@as(u64, 3000), cfg.apps[0].timeout_ms);
    try std.testing.expectEqual(@as(usize, 64), cfg.apps[0].memory_mb);
}

test "parse config with defaults" {
    const json =
        \\{
        \\  "apps": [
        \\    {
        \\      "name": "app-with-defaults",
        \\      "path": "./app"
        \\    }
        \\  ],
        \\  "defaults": {
        \\    "timeout_ms": 10000,
        \\    "memory_mb": 256
        \\  }
        \\}
    ;

    var cfg = try parseConfig(std.testing.allocator, json);
    defer cfg.deinit();

    try std.testing.expectEqual(@as(usize, 1), cfg.apps.len);
    // Hostname defaults to name when not specified
    try std.testing.expectEqualStrings("app-with-defaults", cfg.apps[0].hostname);
    // App should use defaults
    try std.testing.expectEqual(@as(u64, 10000), cfg.apps[0].timeout_ms);
    try std.testing.expectEqual(@as(usize, 256), cfg.apps[0].memory_mb);
}

test "parse multiple apps" {
    const json =
        \\{
        \\  "port": 8080,
        \\  "apps": [
        \\    {"name": "app-a", "path": "./a", "hostname": "a.local"},
        \\    {"name": "app-b", "path": "./b", "hostname": "b.local"}
        \\  ]
        \\}
    ;

    var cfg = try parseConfig(std.testing.allocator, json);
    defer cfg.deinit();

    try std.testing.expectEqual(@as(usize, 2), cfg.apps.len);
    try std.testing.expectEqual(@as(u16, 8080), cfg.port);
    try std.testing.expectEqualStrings("app-a", cfg.apps[0].name);
    try std.testing.expectEqualStrings("a.local", cfg.apps[0].hostname);
    try std.testing.expectEqualStrings("app-b", cfg.apps[1].name);
    try std.testing.expectEqualStrings("b.local", cfg.apps[1].hostname);
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
