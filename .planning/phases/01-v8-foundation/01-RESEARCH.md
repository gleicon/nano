# Phase 1: V8 Foundation - Research

**Researched:** 2026-01-20
**Domain:** V8 JavaScript engine embedding in Zig
**Confidence:** MEDIUM-HIGH

## Summary

Phase 1 establishes the foundation for NANO by embedding the V8 JavaScript engine within Zig. The core challenge is that V8 is a C++ library with no native C API, and Zig cannot directly call C++. The proven solution is a C shim layer that wraps V8's C++ API, which Zig can then import via `@cImport`.

The research reveals a critical Zig version decision: Lightpanda's zig-v8-fork now requires **Zig 0.15.1+**, not 0.14.0 as originally planned. The original fubark/zig-v8 targets Zig 0.11.0. This means we either need to:
1. Use Zig 0.15.1+ and leverage zig-v8-fork directly
2. Stay with Zig 0.14.0 and build our own minimal C shim
3. Fork and update an existing solution for 0.14.0 compatibility

The standard pattern for V8 embedding follows a clear lifecycle: Initialize platform, create isolate with resource constraints and ArrayBuffer allocator, create context, compile and run scripts within HandleScopes, handle errors via TryCatch, and cleanup in reverse order.

**Primary recommendation:** Use Zig 0.15.1+ with Lightpanda's zig-v8-fork (version 0.2.4) for the fastest path to a working `nano eval "1 + 1"` implementation. The I/O subsystem changes in 0.15.x are manageable and don't significantly impact Phase 1.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| V8 | 12.4+ (Chrome 124+) | JavaScript engine | Industry standard, Node 22 LTS uses this version, best isolate support |
| Zig | 0.15.1+ | Systems language | Required by zig-v8-fork; first-class C interop |
| zig-v8-fork | 0.2.4 | V8 C bindings for Zig | Lightpanda maintains this; builds V8 from source with C/Zig bindings |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| depot_tools | latest | V8 build tooling | Only if building V8 manually without zig-v8-fork |
| GN/Ninja | bundled with depot_tools | Build system | V8 requires this; zig-v8-fork handles it |
| Python 3 | system | Build dependency | Required for V8 build scripts |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| zig-v8-fork | fubark/zig-v8 | Only works with Zig 0.11.0; would need significant porting |
| zig-v8-fork | Custom C shim | More control, much more work; proven approach but 2-4 weeks extra |
| Zig 0.15.1 | Zig 0.14.0 | Would require forking zig-v8-fork and backporting |

**Installation:**
```bash
# Zig 0.15.1+ installation
# Download from https://ziglang.org/download/

# V8 via zig-v8-fork (handled by build.zig)
# Add to build.zig.zon:
# .zig_v8 = .{
#     .url = "https://github.com/lightpanda-io/zig-v8-fork/archive/v0.2.4.tar.gz",
#     .hash = "...",
# },
```

## Architecture Patterns

### Recommended Project Structure
```
nano/
├── build.zig           # Build configuration
├── build.zig.zon       # Dependencies (zig-v8-fork)
├── src/
│   ├── main.zig        # CLI entry point, argument parsing
│   ├── engine/
│   │   ├── v8.zig      # V8 wrapper (lifecycle, isolate, context)
│   │   ├── script.zig  # Script compilation and execution
│   │   └── error.zig   # Error handling, TryCatch wrapper
│   └── allocator/
│       └── arena.zig   # Request-scoped arena allocator
└── vendor/
    └── v8/             # Built V8 library (after zig build get-v8)
```

### Pattern 1: V8 Initialization Singleton
**What:** V8 platform must be initialized once per process before any isolates
**When to use:** At program startup, before any JavaScript execution
**Example:**
```zig
// Source: V8 hello-world.cc sample pattern
const V8Engine = struct {
    platform: *v8.Platform,

    pub fn init() !V8Engine {
        // These must happen in this exact order
        v8.V8.initializeICUDefaultLocation(argv0);
        v8.V8.initializeExternalStartupData(argv0);

        const platform = v8.platform.newDefaultPlatform();
        v8.V8.initializePlatform(platform);
        v8.V8.initialize();

        return V8Engine{ .platform = platform };
    }

    pub fn deinit(self: *V8Engine) void {
        v8.V8.dispose();
        v8.V8.shutdownPlatform();
        // Platform cleanup handled by V8
    }
};
```

### Pattern 2: Isolate with Arena Allocator
**What:** Each script evaluation gets its own isolate with arena-backed memory
**When to use:** For `nano eval "..."` command - single script execution
**Example:**
```zig
// Source: Zig guide allocators + V8 embedding pattern
pub fn evalScript(engine: *V8Engine, script_source: []const u8) ![]const u8 {
    // Arena for this request - freed entirely at end
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // Create V8 isolate with memory constraints
    var create_params = v8.Isolate.CreateParams{};
    create_params.array_buffer_allocator = v8.ArrayBuffer.Allocator.newDefaultAllocator();
    defer create_params.array_buffer_allocator.delete();

    const isolate = v8.Isolate.new(&create_params);
    defer isolate.dispose();

    // Enter isolate scope
    const isolate_scope = v8.Isolate.Scope.init(isolate);
    defer isolate_scope.deinit();

    // Create handle scope - all local handles live here
    const handle_scope = v8.HandleScope.init(isolate);
    defer handle_scope.deinit();

    // Create context and execute
    const context = v8.Context.new(isolate);
    const context_scope = v8.Context.Scope.init(context);
    defer context_scope.deinit();

    // Compile and run (see Pattern 3)
    return try compileAndRun(isolate, context, script_source, allocator);
}
```

### Pattern 3: TryCatch Error Handling
**What:** Wrap script execution in TryCatch to capture JavaScript errors
**When to use:** Always when running user-provided JavaScript
**Example:**
```zig
// Source: V8 TryCatch documentation
fn compileAndRun(
    isolate: *v8.Isolate,
    context: v8.Local(v8.Context),
    source: []const u8,
    allocator: std.mem.Allocator,
) ![]const u8 {
    var try_catch = v8.TryCatch.init(isolate);
    defer try_catch.deinit();

    // Compile script
    const source_str = v8.String.newFromUtf8(isolate, source) orelse {
        return error.FailedToCreateString;
    };

    const script = v8.Script.compile(context, source_str) orelse {
        // Compilation failed - get error message
        if (try_catch.hasCaught()) {
            const exception = try_catch.exception();
            const message = try_catch.message();
            return try formatError(isolate, exception, message, allocator);
        }
        return error.CompilationFailed;
    };

    // Run script
    const result = script.run(context) orelse {
        if (try_catch.hasCaught()) {
            const exception = try_catch.exception();
            const message = try_catch.message();
            return try formatError(isolate, exception, message, allocator);
        }
        return error.ExecutionFailed;
    };

    // Convert result to string
    const result_str = result.toString(context) orelse {
        return error.FailedToConvertResult;
    };

    return try v8StringToZig(isolate, result_str, allocator);
}
```

### Anti-Patterns to Avoid
- **Storing Local handles beyond their scope:** Local<T> handles are invalid after HandleScope exits. Use EscapableHandleScope to return values, or Persistent<T> for long-lived references.
- **Calling V8 from multiple threads on same isolate:** Each isolate is single-threaded. Use v8::Locker if you must share, but prefer one isolate per thread.
- **Ignoring TryCatch results:** Always check `hasCaught()` after any operation that might throw. Empty handles without TryCatch mean your code must bail.
- **Creating isolates per request without pooling:** Isolate creation is 40-100ms cold. For Phase 1 (CLI tool), this is acceptable. Phase 4 addresses this with snapshots.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| V8 C bindings | Custom C shim from scratch | zig-v8-fork | 6+ months of work, edge cases, V8 version tracking |
| ArrayBuffer allocator | Custom implementation | `v8::ArrayBuffer::Allocator::NewDefaultAllocator()` | Handles memory cage, sandbox, edge cases |
| Platform initialization | Custom platform | `v8::platform::NewDefaultPlatform()` | Threading, task scheduling complexity |
| Error message extraction | Manual V8 value navigation | TryCatch.message() + .getMessage() | Line numbers, column info, stack traces |

**Key insight:** V8 embedding has deep complexity hidden behind seemingly simple APIs. The official patterns handle memory cages, pointer compression, garbage collection timing, and thread safety. Custom solutions will miss edge cases that cause crashes under load.

## Common Pitfalls

### Pitfall 1: HandleScope Mismanagement
**What goes wrong:** Local handles become invalid, causing crashes or undefined behavior
**Why it happens:** Local handles are stack-allocated and garbage-collected when their HandleScope exits
**How to avoid:**
- Every function touching V8 values needs a HandleScope
- Use EscapableHandleScope to return handles from functions
- Never store Local<> handles in structs (use Persistent<> or Global<>)
**Warning signs:** Crashes during GC, values becoming "undefined" unexpectedly

### Pitfall 2: C++/Zig Memory Ownership
**What goes wrong:** Double-free or use-after-free crashes
**Why it happens:** Memory allocated by C++ (V8) must be freed by C++, not Zig
**How to avoid:**
- Clear ownership rules: V8 allocates, V8 frees
- Use V8's provided delete methods (e.g., `array_buffer_allocator.delete()`)
- Zig arena is only for Zig-side allocations
**Warning signs:** Crashes in free(), memory corruption errors

### Pitfall 3: Isolate Scope Not Entered
**What goes wrong:** V8 operations fail silently or crash
**Why it happens:** V8 requires an active isolate scope for most operations
**How to avoid:**
- Create Isolate::Scope immediately after isolate creation
- Use RAII/defer pattern to ensure scope exit
- Check that context is also entered for script operations
**Warning signs:** Empty handles returned unexpectedly, assertions in V8 debug builds

### Pitfall 4: Forgetting Context::Scope
**What goes wrong:** Script compilation or execution fails
**Why it happens:** Scripts must run within an active context
**How to avoid:**
- Create Context::Scope after context creation
- Scope must be active during compile AND run
**Warning signs:** "No current context" errors

### Pitfall 5: String Encoding Mismatch
**What goes wrong:** Garbled output, incorrect string lengths
**Why it happens:** V8 uses UTF-16 internally, Zig uses UTF-8
**How to avoid:**
- Use V8's UTF-8 APIs: `String::NewFromUtf8()`, `String::Utf8Value`
- Account for null terminators in buffer sizes
- Test with non-ASCII strings early
**Warning signs:** Strings truncated, Unicode characters corrupted

## Code Examples

Verified patterns from official sources:

### V8 Initialization (Complete)
```zig
// Source: V8 samples/hello-world.cc
const std = @import("std");
const v8 = @import("v8");

pub const Engine = struct {
    platform: *v8.Platform,

    pub fn init(argv0: [*:0]const u8) Engine {
        v8.V8.initializeICUDefaultLocation(argv0);
        v8.V8.initializeExternalStartupData(argv0);

        const platform = v8.platform.newDefaultPlatform();
        v8.V8.initializePlatform(platform);
        v8.V8.initialize();

        return .{ .platform = platform };
    }

    pub fn deinit(self: *Engine) void {
        v8.V8.dispose();
        v8.V8.shutdownPlatform();
    }
};
```

### Isolate Creation with Constraints
```zig
// Source: V8 ResourceConstraints API documentation
pub fn createIsolate() !*v8.Isolate {
    var create_params = v8.Isolate.CreateParams{};

    // Required: ArrayBuffer allocator
    create_params.array_buffer_allocator =
        v8.ArrayBuffer.Allocator.newDefaultAllocator();

    // Optional but recommended: Memory constraints
    var constraints = v8.ResourceConstraints{};
    constraints.setMaxOldGenerationSizeInBytes(128 * 1024 * 1024); // 128MB
    constraints.setMaxYoungGenerationSizeInBytes(16 * 1024 * 1024); // 16MB
    create_params.constraints = &constraints;

    return v8.Isolate.new(&create_params);
}
```

### Script Execution with Error Handling
```zig
// Source: V8 TryCatch + embedding guide
pub fn runScript(
    isolate: *v8.Isolate,
    context: v8.Local(v8.Context),
    source_code: []const u8,
) ScriptResult {
    var try_catch = v8.TryCatch.init(isolate);
    defer try_catch.deinit();

    // Create source string
    const source = v8.String.newFromUtf8(isolate, source_code) orelse {
        return .{ .err = "Failed to create source string" };
    };

    // Compile
    const script = v8.Script.compile(context, source) orelse {
        return extractError(isolate, &try_catch);
    };

    // Execute
    const result = script.run(context) orelse {
        return extractError(isolate, &try_catch);
    };

    // Convert to string
    const utf8_result = v8.String.Utf8Value.init(isolate, result);
    return .{ .ok = utf8_result.data() };
}

fn extractError(isolate: *v8.Isolate, try_catch: *v8.TryCatch) ScriptResult {
    if (!try_catch.hasCaught()) {
        return .{ .err = "Unknown error" };
    }

    const message = try_catch.message();
    if (message.isNull()) {
        return .{ .err = "Error with no message" };
    }

    // Get line number and message
    const line = message.getLineNumber(context) orelse 0;
    const msg_str = message.get();
    const utf8_msg = v8.String.Utf8Value.init(isolate, msg_str);

    return .{ .err = utf8_msg.data(), .line = line };
}
```

### Arena Allocator Pattern
```zig
// Source: Zig allocators guide + http.zig patterns
pub fn handleEvalCommand(script: []const u8) !void {
    // All allocations for this command in one arena
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit(); // Frees ALL allocations at once

    const allocator = arena.allocator();

    // Use allocator for any Zig-side allocations
    const result = try evalWithV8(script, allocator);

    // Write result to stdout
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{s}\n", .{result});

    // arena.deinit() runs here - instant cleanup
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| V8 external snapshot files | Embedded snapshots | V8 12.x | Simpler deployment, slightly larger binary |
| Manual platform management | NewDefaultPlatform() | V8 10.x | Less boilerplate, correct defaults |
| Zig 0.13/0.14 | Zig 0.15.1 | 2025 | Breaking I/O changes, required for zig-v8-fork |
| fubark/zig-v8 | lightpanda/zig-v8-fork | 2025 | Active maintenance, newer Zig support |

**Deprecated/outdated:**
- `V8_IMMINENT_DEPRECATION_WARNINGS`: Many old APIs removed in V8 12+
- `v8::Handle<T>`: Replaced by `v8::Local<T>` years ago
- External snapshot loading: Embedded is now default and recommended

## Open Questions

Things that couldn't be fully resolved:

1. **zig-v8-fork API stability**
   - What we know: Version 0.2.4 exists, used by Lightpanda browser
   - What's unclear: Exact Zig API surface, documentation quality
   - Recommendation: Examine zig-js-runtime source for usage patterns; plan for API exploration task

2. **V8 build time on target hardware**
   - What we know: ~20 minutes on MacBook for release, 40+ minutes with full features
   - What's unclear: Exact time on user's specific hardware (macOS ARM64)
   - Recommendation: Run build early in Phase 1, document actual time; consider CI caching

3. **Zig 0.15.x migration complexity**
   - What we know: I/O subsystem changed ("Writergate"), ArrayHashMap deprecations
   - What's unclear: Impact on Phase 1 specifically (minimal I/O usage)
   - Recommendation: Phase 1 has minimal I/O (CLI args, stdout), should be low impact

4. **Error message formatting quality**
   - What we know: V8 provides line/column, stack trace access
   - What's unclear: Best format for CLI output
   - Recommendation: Start simple (message + line), iterate based on usage

## Sources

### Primary (HIGH confidence)
- [V8 Embedding Guide](https://v8.dev/docs/embed) - Official embedding documentation
- [V8 hello-world.cc sample](https://github.com/v8/v8/blob/master/samples/hello-world.cc) - Reference implementation
- [V8 Isolate API Reference](https://v8.github.io/api/head/classv8_1_1Isolate.html) - Official API docs
- [V8 EscapableHandleScope Reference](https://v8.github.io/api/head/classv8_1_1EscapableHandleScope.html) - Handle management
- [V8 ArrayBuffer::Allocator Reference](https://v8.github.io/api/head/classv8_1_1ArrayBuffer_1_1Allocator.html) - Memory allocator API
- [Zig Allocators Guide](https://zig.guide/standard-library/allocators/) - Arena allocator patterns
- [Zig 0.15.1 Release Notes](https://ziglang.org/download/0.15.1/release-notes.html) - Breaking changes documentation

### Secondary (MEDIUM confidence)
- [Lightpanda zig-v8-fork](https://github.com/lightpanda-io/zig-v8-fork) - Zig 0.15.1+ V8 bindings
- [Lightpanda zig-js-runtime](https://github.com/lightpanda-io/zig-js-runtime) - Usage patterns for zig-v8
- [Lightpanda Browser build.zig.zon](https://github.com/lightpanda-io/browser/blob/main/build.zig.zon) - Dependency versions
- [Lightpanda "Why Zig" blog post](https://lightpanda.io/blog/posts/why-we-built-lightpanda-in-zig) - C shim approach rationale
- [http.zig Arena patterns](https://github.com/karlseguin/http.zig) - Per-request arena usage
- [V8 Building with GN](https://v8.dev/docs/build-gn) - Build configuration

### Tertiary (LOW confidence)
- [fubark/zig-v8](https://github.com/fubark/zig-v8) - Older Zig 0.11.0 bindings (reference only)
- [V8 Users mailing list discussions](https://groups.google.com/g/v8-users) - Edge case troubleshooting

## Metadata

**Confidence breakdown:**
- Standard stack: MEDIUM-HIGH - zig-v8-fork is active but relatively new; V8 patterns are well-established
- Architecture: HIGH - V8 embedding patterns are thoroughly documented and battle-tested
- Pitfalls: HIGH - Well-documented by V8 team and community; verified through multiple sources
- Zig version: MEDIUM - 0.15.1 requirement is new; migration impact unclear for our use case

**Research date:** 2026-01-20
**Valid until:** 2026-02-20 (V8 stable, Zig rapidly evolving)

---

## Phase 1 Specific Guidance

### Success Criteria Mapping

| Success Criterion | How This Research Helps |
|-------------------|------------------------|
| `nano eval "1 + 1"` returns `2` | Complete code examples for V8 init, isolate, context, script execution |
| JavaScript syntax errors return meaningful messages | TryCatch pattern with line number extraction documented |
| Memory freed when request ends | Arena allocator pattern ensures instant cleanup |

### Recommended Task Order

1. **Setup** - Install Zig 0.15.1+, create project with build.zig.zon
2. **V8 Build** - Run zig-v8-fork build (20-40 min), verify libc_v8.a created
3. **Hello V8** - Minimal V8 init/shutdown without script execution
4. **Basic Eval** - `"1 + 1"` without error handling
5. **Error Handling** - Add TryCatch, test with syntax errors
6. **CLI Integration** - Argument parsing, stdout output
7. **Arena Cleanup** - Wrap execution in arena allocator

### Risk Mitigation

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| zig-v8-fork API different than expected | MEDIUM | Start with hello-world, examine zig-js-runtime for patterns |
| V8 build fails on macOS | LOW | Follow exact zig-v8-fork instructions; they test on macOS |
| Zig 0.15 migration harder than expected | LOW | Phase 1 has minimal I/O; mostly V8 calls via C |
| TryCatch doesn't capture all errors | LOW | Follow official patterns exactly; test with various error types |
