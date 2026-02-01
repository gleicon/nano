const std = @import("std");
const v8 = @import("v8");
const script = @import("script");
const repl = @import("repl");
const server = @import("server");
const config = @import("config");

const usage =
    \\Usage: nano <command> [arguments]
    \\
    \\Commands:
    \\  eval <script>    Evaluate JavaScript and print result
    \\  repl             Start interactive JavaScript session
    \\  serve [options]  Start HTTP server
    \\  help             Show this help message
    \\
    \\Serve options:
    \\  --port <port>    Port to listen on (default: 8080)
    \\  --config <file>  Load multi-app configuration from JSON file
    \\  <path>           App directory path (single app mode)
    \\
    \\Examples:
    \\  nano eval "1 + 1"
    \\  nano eval "Math.sqrt(16)"
    \\  nano repl
    \\  nano serve --port 8080
    \\  nano serve ./my-app --port 3000
    \\  nano serve --config nano.json
    \\
;

pub fn main() !void {
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    const stderr_file = std.fs.File{ .handle = std.posix.STDERR_FILENO };

    // Parse arguments
    var args = std.process.args();
    _ = args.skip(); // Skip program name

    const command = args.next() orelse {
        stderr_file.writeAll(usage) catch {};
        std.process.exit(1);
    };

    if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        stdout_file.writeAll(usage) catch {};
        return;
    }

    if (std.mem.eql(u8, command, "eval")) {
        const script_source = args.next() orelse {
            stderr_file.writeAll("Error: eval requires a script argument\n\n") catch {};
            stderr_file.writeAll(usage) catch {};
            std.process.exit(1);
        };
        try evalCommand(script_source, stdout_file, stderr_file);
        return;
    }

    if (std.mem.eql(u8, command, "repl")) {
        try repl.runRepl();
        return;
    }

    if (std.mem.eql(u8, command, "serve")) {
        var port: u16 = 8080; // default port
        var app_path: ?[]const u8 = null;
        var config_path: ?[]const u8 = null;

        // Parse serve options
        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "--port")) {
                const port_str = args.next() orelse {
                    stderr_file.writeAll("Error: --port requires a value\n") catch {};
                    std.process.exit(1);
                };
                port = std.fmt.parseInt(u16, port_str, 10) catch {
                    stderr_file.writeAll("Error: invalid port number\n") catch {};
                    std.process.exit(1);
                };
            } else if (std.mem.eql(u8, arg, "--config")) {
                config_path = args.next() orelse {
                    stderr_file.writeAll("Error: --config requires a file path\n") catch {};
                    std.process.exit(1);
                };
            } else if (!std.mem.startsWith(u8, arg, "-")) {
                // Non-option argument is the app path
                app_path = arg;
            }
        }

        // Multi-app mode with config file
        if (config_path) |cfg_path| {
            serveMultiApp(cfg_path, stderr_file) catch |err| {
                stderr_file.writeAll("Config error: ") catch {};
                const err_name = @errorName(err);
                stderr_file.writeAll(err_name) catch {};
                stderr_file.writeAll("\n") catch {};
                std.process.exit(1);
            };
            return;
        }

        // Single app mode
        server.serve(port, app_path) catch |err| {
            stderr_file.writeAll("Server error: ") catch {};
            const err_name = @errorName(err);
            stderr_file.writeAll(err_name) catch {};
            stderr_file.writeAll("\n") catch {};
            std.process.exit(1);
        };
        return;
    }

    stderr_file.writeAll("Unknown command: ") catch {};
    stderr_file.writeAll(command) catch {};
    stderr_file.writeAll("\n\n") catch {};
    stderr_file.writeAll(usage) catch {};
    std.process.exit(1);
}

fn serveMultiApp(config_path: []const u8, stderr: std.fs.File) !void {
    const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    const allocator = std.heap.page_allocator;

    // Load config
    var cfg = config.loadConfig(allocator, config_path) catch |err| {
        stderr.writeAll("Failed to load config: ") catch {};
        stderr.writeAll(config_path) catch {};
        stderr.writeAll("\n") catch {};
        return err;
    };
    defer cfg.deinit();

    stdout.writeAll("NANO Multi-App Mode (Virtual Host)\n") catch {};
    stdout.writeAll("===================================\n\n") catch {};

    // Print loaded apps
    var buf: [256]u8 = undefined;
    const app_count = std.fmt.bufPrint(&buf, "Loading {d} app(s) on port {d}:\n\n", .{ cfg.apps.len, cfg.port }) catch "Apps loaded\n";
    stdout.writeAll(app_count) catch {};

    for (cfg.apps) |app| {
        const line = std.fmt.bufPrint(&buf, "  [{s}] Host: {s}\n    path: {s}, timeout:{d}ms, memory:{d}MB\n\n", .{
            app.name,
            app.hostname,
            app.path,
            app.timeout_ms,
            app.memory_mb,
        }) catch continue;
        stdout.writeAll(line) catch {};
    }

    if (cfg.apps.len == 0) {
        stderr.writeAll("No apps defined in config\n") catch {};
        return error.NoApps;
    }

    // Start multi-app server with virtual host routing
    try server.serveMultiApp(cfg);
}

fn evalCommand(script_source: []const u8, stdout: std.fs.File, stderr: std.fs.File) !void {
    // Arena allocator for instant cleanup (CORE-02)
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Initialize V8 platform
    const platform = v8.Platform.initDefault(0, false);
    defer platform.deinit();

    v8.initV8Platform(platform);
    v8.initV8();
    defer {
        _ = v8.deinitV8();
        v8.deinitV8Platform();
    }

    // Execute script
    const result = script.runScript(script_source, allocator);

    switch (result) {
        .ok => |value| {
            stdout.writeAll(value) catch {};
            stdout.writeAll("\n") catch {};
        },
        .err => |e| {
            const formatted = e.format(allocator) catch e.message;
            stderr.writeAll(formatted) catch {};
            stderr.writeAll("\n") catch {};
            std.process.exit(1);
        },
    }
}
