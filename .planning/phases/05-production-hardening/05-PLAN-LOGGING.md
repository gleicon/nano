# Plan: Zig Logging Library

## Goal
Create a standalone logging library to consolidate logging patterns across NANO, with potential for external release.

## Current State

### Logging Patterns Found

| Location | Pattern | Output |
|----------|---------|--------|
| `src/server/http.zig:189-230` | `logRequest()`, `logError()`, `logConnectionError()` | Structured JSON to stdout/stderr |
| `src/main.zig` | Direct `file.writeAll()` | Plain text CLI messages |
| `src/repl.zig` | Direct `file.writeAll()` | REPL prompts and output |
| `src/api/console.zig` | `writeArgs()` | JS console API (log/error/warn) |

### Issues
1. Repeated buffer allocation patterns (`var buf: [N]u8 = undefined`)
2. Repeated `std.fmt.bufPrint` error handling
3. Inconsistent timestamp handling
4. No log level filtering
5. Verbose code for simple log operations

## Proposed API

```zig
const log = @import("log");

// Initialize with output configuration
var logger = log.init(.{
    .output = .stdout,  // or .stderr, or custom fd
    .format = .json,    // or .text
    .level = .info,     // minimum level to output
});

// Simple logging
logger.info("server_start", .{ .port = 8080 });
logger.err("connection_failed", .{ .error = "timeout" });
logger.warn("deprecated_api", .{ .api = "fetch" });

// Structured fields
logger.with(.{ .request_id = 123 }).info("request_complete", .{ .status = 200 });
```

## Implementation Plan

### Step 1: Create `src/log.zig`
- Log level enum: `debug`, `info`, `warn`, `err`
- Output writer abstraction
- JSON serializer for structured fields
- Text formatter for CLI output

### Step 2: Migrate `src/server/http.zig`
- Replace `logRequest()`, `logError()`, `logConnectionError()` with logger calls
- Remove local buffer allocations

### Step 3: Update `src/main.zig`
- Use logger for CLI error messages
- Keep usage text as-is (not a log)

### Step 4: Update `src/repl.zig`
- Use logger for error output
- Keep REPL prompts as direct writes (interactive, not logs)

### Step 5: Keep `src/api/console.zig` separate
- JS console API has different semantics (user-facing, not system logs)
- Keep as-is

## File Changes

| File | Action |
|------|--------|
| `src/log.zig` | Create - new logging library |
| `src/server/http.zig` | Modify - use logger |
| `src/main.zig` | Modify - use logger for errors |
| `src/repl.zig` | Modify - use logger for errors |

## Implementation Status

### Completed
- [x] Created `src/log.zig` - standalone logging library
- [x] Migrated `src/server/http.zig` to use logger
- [x] Build system updated with log module

### Kept As-Is
- `src/main.zig` - CLI messages are interactive, not logs
- `src/repl.zig` - REPL output is interactive, not logs
- `src/api/console.zig` - JS console API has different semantics

### Design Decision
The logging library is for **structured machine-readable logs** (server events, request tracking).
CLI and REPL output remain **human-readable plain text** for interactive use.

## Success Criteria
1. Server logging uses single library - DONE
2. Reduced code duplication in http.zig - DONE
3. Consistent JSON format for structured logs - DONE
4. Library is self-contained (no NANO-specific dependencies) - DONE
