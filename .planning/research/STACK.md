# Stack Research: JavaScript Isolate Runtime

**Project:** NANO - Ultra-dense JavaScript runtime with V8 isolates
**Researched:** 2026-01-19
**Overall Confidence:** MEDIUM-HIGH

---

## Recommended Stack

| Component | Choice | Version | Confidence | Rationale |
|-----------|--------|---------|------------|-----------|
| **JS Engine** | V8 | 12.4+ (Chrome 124+) | HIGH | Industry standard, best isolate support, extensive embedding APIs |
| **Language** | Zig | 0.13.0 or 0.14.0 | HIGH | First-class C interop, comptime metaprogramming, explicit allocators |
| **V8 Bindings** | Custom C shim via rusty_v8 headers | - | MEDIUM | Lightpanda approach proven; direct C++ interop not possible in Zig |
| **Build System** | Zig build + V8's GN/Ninja | - | MEDIUM | V8 requires GN; Zig links against resulting static lib |
| **Async I/O (Linux)** | io_uring via zig-aio or libxev | - | MEDIUM | Sub-microsecond latency; Zig 0.15+ will have native support |
| **Async I/O (macOS)** | kqueue via libxev/zio | - | MEDIUM | Fallback for dev; production targets Linux |

---

## V8 Embedding

### Version Selection

**Recommendation:** V8 12.4+ (aligned with Node.js 22 LTS)

| Version | Node.js | Chrome | Status | Notes |
|---------|---------|--------|--------|-------|
| V8 12.4 | Node 22 | 124 | LTS candidate | Maglev enabled, WebAssembly GC |
| V8 13.x | - | 130+ | Current | More features, less stable for embedding |

**Rationale:** V8 12.4 is used by Node.js 22 (entering LTS October 2024), providing battle-tested stability. The Maglev compiler improves performance for short-lived CLI/isolate scenarios - exactly our use case.

Sources: [Node.js 22 Release](https://nodejs.org/en/blog/announcements/v22-release-announce)

### Build Flags (args.gn)

```gn
# Core embedding configuration
is_component_build = false          # Build as static library
v8_static_library = true            # Required for embedding
v8_monolithic = true                # Single libc_v8.a output

# Snapshot configuration - CRITICAL for sub-5ms cold start
v8_use_external_startup_data = false  # Embed snapshot in binary
v8_embed_script = ""                  # Custom bootstrap if needed

# Memory optimization
v8_enable_pointer_compression = true  # 50% heap reduction, 4GB limit
v8_enable_sandbox = true              # Security isolation

# Performance
v8_enable_maglev = true               # Fast JIT for short-lived code
v8_enable_turbofan = true             # Full optimization tier

# Development
is_debug = false                      # Release build
target_cpu = "x64"                    # or "arm64"
use_custom_libcxx = false             # Use system libc++
```

**Critical Build Mismatches to Avoid:**
- `V8_COMPRESS_POINTERS` must match between V8 and embedder
- `V8_ENABLE_CHECKS` must be consistent
- Failure causes cryptic crashes

Sources: [V8 Build with GN](https://v8.dev/docs/build-gn), [V8 BUILD.gn](https://github.com/v8/v8/blob/main/BUILD.gn)

### Key V8 APIs for Isolate Management

```cpp
// Core isolate lifecycle
v8::Isolate::CreateParams     // Configuration before creation
v8::Isolate::New()            // Create isolate with params
v8::Isolate::Dispose()        // Cleanup (not delete!)

// Memory constraints (via CreateParams.constraints)
v8::ResourceConstraints::set_max_old_generation_size_in_bytes()
v8::ResourceConstraints::set_max_young_generation_size_in_bytes()
v8::ResourceConstraints::set_initial_old_generation_size_in_bytes()

// Snapshot support (CRITICAL for cold start)
v8::V8::CreateSnapshotDataBlob()     // Create snapshot from script
v8::Isolate::CreateParams::snapshot_blob  // Load snapshot on creation

// Handle management
v8::HandleScope              // Stack-allocated handle container
v8::EscapableHandleScope     // Return handles from functions
v8::Persistent<T>            // Cross-scope references
v8::Local<T>                 // Scoped references

// Context and execution
v8::Context::New()           // Create execution context
v8::Script::Compile()        // Parse JavaScript
v8::Script::Run()            // Execute

// Template system (for native bindings)
v8::FunctionTemplate         // JS function -> C++ callback
v8::ObjectTemplate           // Configure object instances
```

Sources: [V8 Embed Guide](https://v8.dev/docs/embed), [V8 Isolate API](https://v8.github.io/api/head/classv8_1_1Isolate.html)

### Memory Configuration for <2MB Overhead

Based on Cloudflare Workers research (128MB per isolate limit):

```cpp
v8::ResourceConstraints constraints;

// For <2MB base overhead target:
constraints.set_max_old_generation_size_in_bytes(64 * 1024 * 1024);  // 64MB max
constraints.set_max_young_generation_size_in_bytes(2 * 1024 * 1024); // 2MB young gen
constraints.set_initial_old_generation_size_in_bytes(512 * 1024);    // 512KB initial
constraints.set_initial_young_generation_size_in_bytes(256 * 1024);  // 256KB initial young

v8::Isolate::CreateParams params;
params.constraints = constraints;
params.snapshot_blob = &startup_data;  // Pre-built snapshot
```

**Key insight from Cloudflare:** They tuned young generation size in 2017 but found V8's 2025 GC heuristics work better with less manual tuning. Start with constraints, then back off if needed.

Sources: [Cloudflare Workers Limits](https://developers.cloudflare.com/workers/platform/limits/), [V8 ResourceConstraints](https://v8.github.io/api/head/classv8_1_1ResourceConstraints.html)

---

## Zig Integration

### Version Recommendation

| Version | Status | Recommendation |
|---------|--------|----------------|
| **Zig 0.13.0** | Stable | Safe choice for production |
| **Zig 0.14.0** | Current | Lightpanda uses this; zig-js-runtime requires it |
| **Zig 0.15.0** | Future | Native async I/O rewrite |

**Recommendation:** Start with **Zig 0.14.0** because:
1. Lightpanda's zig-js-runtime requires 0.14.0
2. Better C interop than 0.13.0
3. 0.15.0's async changes will require rewrites anyway

### C++ Interop Approach

Zig cannot directly call C++ code. The proven pattern (used by Lightpanda):

```
V8 C++ API
    |
    v
C shim layer (thin wrapper exposing C functions)
    |
    v
Zig @cImport() of C headers
    |
    v
Zig code with comptime bindings
```

**Option 1: Use rusty_v8's C headers** (Recommended)
- Deno team maintains these
- Already battle-tested
- Updated with each V8 release

**Option 2: Write custom C shim**
- More control
- More maintenance burden
- Only if rusty_v8 headers insufficient

**Option 3: Use zig-v8 fork** (Lightpanda's approach)
- Pre-built bindings
- Available at: https://github.com/lightpanda-io/zig-v8-fork
- Integrated with zig-js-runtime

Sources: [Lightpanda Zig Blog](https://lightpanda.io/blog/posts/why-we-built-lightpanda-in-zig), [Zig C++ Interop](https://tuple.app/blog/zig-cpp-interop)

### Build System Integration

```zig
// build.zig approach
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "nano",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link V8 static library (pre-built via GN/Ninja)
    exe.addObjectFile(b.path("vendor/v8/libc_v8.a"));

    // Link C++ standard library
    exe.linkLibCpp();

    // Include V8 headers
    exe.addIncludePath(b.path("vendor/v8/include"));

    // System libraries V8 needs
    exe.linkSystemLibrary("pthread");

    b.installArtifact(exe);
}
```

**Build Steps:**
1. Build V8 separately with GN/Ninja -> `libc_v8.a`
2. Zig build.zig links against the static library
3. C shim layer compiled as part of Zig build

Sources: [Zig Build System](https://ziglang.org/learn/build-system/), [zig-js-runtime](https://github.com/lightpanda-io/zig-js-runtime)

---

## Memory Management

### Arena Allocator Patterns

Zig's explicit allocators are perfect for isolate lifecycle management:

```zig
const std = @import("std");

pub const IsolateAllocator = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init() IsolateAllocator {
        return .{
            .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
        };
    }

    pub fn allocator(self: *IsolateAllocator) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn deinit(self: *IsolateAllocator) void {
        // Frees ALL allocations at once - perfect for isolate teardown
        self.arena.deinit();
    }

    pub fn reset(self: *IsolateAllocator) void {
        // Reuse for isolate pooling
        _ = self.arena.reset(.retain_capacity);
    }
};
```

**Pattern: Request-scoped arena**
```zig
fn handleRequest(global_allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(global_allocator);
    defer arena.deinit();  // All request memory freed at once

    const alloc = arena.allocator();
    // ... handle request with alloc ...
}
```

**Pattern: Isolate pool with arena reset**
```zig
const IsolatePool = struct {
    isolates: []Isolate,
    arenas: []std.heap.ArenaAllocator,

    pub fn returnToPool(self: *IsolatePool, idx: usize) void {
        // Reset arena keeps memory but marks as reusable
        _ = self.arenas[idx].reset(.retain_capacity);
        // Reset V8 isolate state
        self.isolates[idx].reset();
    }
};
```

Sources: [Zig Allocators Guide](https://zig.guide/standard-library/allocators/), [Leveraging Zig Allocators](https://www.openmymind.net/Leveraging-Zigs-Allocators/)

### V8 Heap Configuration

**Pointer Compression Tradeoff:**
- Enabled: 50% memory savings, max 4GB heap per isolate
- Disabled: No 4GB limit, higher memory usage

For <2MB per isolate, pointer compression is mandatory.

```cpp
// args.gn
v8_enable_pointer_compression = true
```

**ArrayBuffer Allocator:**
V8 requires an `ArrayBuffer::Allocator` for TypedArray backing stores:

```zig
// Custom allocator bridging Zig arena to V8
const V8ArrayBufferAllocator = struct {
    zig_allocator: std.mem.Allocator,

    pub fn allocate(self: *V8ArrayBufferAllocator, length: usize) ?*anyopaque {
        return self.zig_allocator.alloc(u8, length) catch null;
    }

    pub fn free(self: *V8ArrayBufferAllocator, data: *anyopaque, length: usize) void {
        const slice = @as([*]u8, @ptrCast(data))[0..length];
        self.zig_allocator.free(slice);
    }
};
```

---

## What NOT to Use

| Alternative | Why Rejected |
|-------------|--------------|
| **JavaScriptCore** | Faster startup than V8, but: less embedding documentation, smaller ecosystem, Safari-only testing. Bun uses JSC successfully but their scale differs. |
| **QuickJS** | Tiny footprint but: no JIT (10-100x slower), no WebAssembly, not Workers-compatible API surface. Good for config scripts, not runtime. |
| **SpiderMonkey** | Mozilla's engine: harder to embed than V8, less documentation, Rust-centric tooling. |
| **Hermes** | React Native focused: mobile-optimized, not server workloads, limited API surface. |
| **Zig 0.13.0** | Stable but: zig-js-runtime requires 0.14.0, C interop improvements in 0.14.0 |
| **Zig 0.15.0** | Native async I/O but: not released, will require rewrites when it lands |
| **Custom V8 C++ bindings** | Don't write from scratch: use rusty_v8 headers or zig-v8 fork |
| **epoll (Linux)** | Works but: io_uring is significantly faster for high-throughput scenarios |

Sources: [Bun V8 API Compatibility](https://bun.com/blog/how-bun-supports-v8-apis-without-using-v8-part-1), [Deno vs Bun 2025](https://pullflow.com/blog/deno-vs-bun-2025)

---

## Async I/O Strategy

### Linux: io_uring

```zig
// Using zig-aio or similar
const IoEngine = @import("zig-aio").IoUring;

pub fn main() !void {
    var ring = try IoEngine.init(256);  // 256 SQE ring
    defer ring.deinit();

    // Submit async operations
    try ring.queue_read(fd, buffer, offset);
    try ring.submit();

    // Process completions
    while (ring.cq_ready() > 0) {
        const cqe = ring.cq_pop();
        handleCompletion(cqe);
    }
}
```

### macOS: kqueue (dev fallback)

```zig
// libxev provides cross-platform interface
const xev = @import("xev");

pub fn main() !void {
    var loop = try xev.Loop.init(.{});
    defer loop.deinit();

    // Same API, different backend
    // ...
}
```

**Library Options:**

| Library | io_uring | kqueue | Windows | Maturity |
|---------|----------|--------|---------|----------|
| zig-aio | Yes | Emulated | No | Medium |
| libxev | Yes | Yes | IOCP | High |
| zio | Yes | Yes | IOCP | Medium |

**Recommendation:** libxev for cross-platform, zig-aio for Linux-first with best io_uring support.

Sources: [Zig New Async I/O](https://kristoff.it/blog/zig-new-async-io/), [zig-aio](https://github.com/Cloudef/zig-aio), [libxev](https://github.com/lalinsky/zio)

---

## Open Questions

### HIGH Priority (Need Validation Early)

1. **V8 snapshot size vs cold start tradeoff**
   - How large is a Workers-compatible API snapshot?
   - Does embedding snapshot in binary impact binary size acceptably?
   - Need to benchmark: external blob vs embedded

2. **Zig 0.14 C++ linking stability**
   - Known issues with C++ symbol linking in 0.13
   - Test V8 linking thoroughly before committing to version

3. **Memory overhead baseline**
   - What's the actual per-isolate overhead with our configuration?
   - Need to measure: empty isolate, Workers API loaded, running script

### MEDIUM Priority

4. **io_uring + V8 event loop integration**
   - V8 has its own event loop expectations
   - How to integrate io_uring completions with V8 microtasks?

5. **zig-v8 fork maintenance**
   - Is Lightpanda's fork actively maintained?
   - Alternative: extract just the C headers from rusty_v8

6. **Snapshot versioning**
   - Snapshots are V8-version-specific
   - Strategy for V8 upgrades without breaking deployed snapshots?

### LOW Priority (Can Defer)

7. **Multi-cage mode for >4GB scenarios**
   - Pointer compression limits heap to 4GB
   - V8 isolate groups can work around this if needed later

8. **Maglev vs TurboFan tuning**
   - Default should work
   - May need tuning for specific workload patterns

---

## Installation Commands

```bash
# Zig installation (0.14.0)
# Download from https://ziglang.org/download/

# V8 build dependencies (Ubuntu/Debian)
sudo apt-get install -y \
    git \
    python3 \
    pkg-config \
    libglib2.0-dev \
    clang \
    lld \
    ninja-build

# V8 source (using depot_tools)
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH="$PATH:$(pwd)/depot_tools"

# Fetch V8 (specific version)
mkdir v8 && cd v8
fetch v8
cd v8
git checkout branch-heads/12.4  # Match Node.js 22 LTS

# Generate build files
gn gen out/release --args='
  is_component_build=false
  v8_static_library=true
  v8_monolithic=true
  v8_use_external_startup_data=false
  v8_enable_pointer_compression=true
  is_debug=false
  target_cpu="x64"
  use_custom_libcxx=false
'

# Build
ninja -C out/release v8_monolith

# Result: out/release/obj/libv8_monolith.a
```

---

## Sources

### HIGH Confidence (Official Documentation)
- [V8 Embedding Guide](https://v8.dev/docs/embed)
- [V8 Build with GN](https://v8.dev/docs/build-gn)
- [V8 Custom Startup Snapshots](https://v8.dev/blog/custom-startup-snapshots)
- [V8 Isolate API Reference](https://v8.github.io/api/head/classv8_1_1Isolate.html)
- [V8 ResourceConstraints API](https://v8.github.io/api/head/classv8_1_1ResourceConstraints.html)
- [Zig Build System](https://ziglang.org/learn/build-system/)
- [Zig Allocators](https://zig.guide/standard-library/allocators/)
- [Cloudflare Workers Limits](https://developers.cloudflare.com/workers/platform/limits/)

### MEDIUM Confidence (Verified with Multiple Sources)
- [Lightpanda Zig Blog](https://lightpanda.io/blog/posts/why-we-built-lightpanda-in-zig)
- [zig-js-runtime](https://github.com/lightpanda-io/zig-js-runtime)
- [rusty_v8 Repository](https://github.com/denoland/rusty_v8)
- [Deno Rusty V8 Announcement](https://deno.com/blog/rusty-v8-stabilized)
- [Zig C++ Interop](https://tuple.app/blog/zig-cpp-interop)

### LOW Confidence (Single Source / Blog Posts)
- [Cloudflare CPU Benchmarks](https://blog.cloudflare.com/unpacking-cloudflare-workers-cpu-performance-benchmarks/) - GC tuning insights
- [V8 Isolates Serverless](https://ceamkrier.com/post/v8-isolates-the-future-of-serverless/) - General context
