# NANO: Ultra-Dense JavaScript Isolate Runtime

## Product Description

NANO is a high-performance JavaScript runtime built for extreme density and sub-5ms cold start times. Written in Zig with embedded V8, NANO enables running thousands of lightweight JavaScript “nanoservices” in a single process—achieving 10x better resource efficiency than traditional Node.js deployments and outperforming Deno’s isolate model through manual memory control. The goal of this runtime is to optimize for hosting, to run more than one process and to be simple and nimble, not like a J2EE serv, way less bureaucractic and straight to the point. Think about a browser and its tabs.

**Target Market:** Platform engineers and infrastructure teams running multi-tenant JavaScript workloads (API gateways, edge functions, webhook processors, serverless platforms) who need Cloudflare Workers-like performance without vendor lock-in.

**Key Differentiators:**

- **Sub-5ms cold starts** via V8 startup snapshots
- **<2MB memory overhead per isolate** vs 30MB+ for Node.js processes
- **Zero-copy I/O** using Zig’s direct epoll/io_uring integration
- **Arena-based memory management** eliminating GC pauses
- **Native Brazilian market support** (integrates with mcp-osv security scanning)

-----

## Technical Architecture

### Core Components

**1. Isolate Manager (Zig Core)**

- V8 embedding layer with C++ interop
- Arena allocator per request (instant cleanup)
- V8 startup snapshot system for <1ms initialization
- Stack/heap limits per isolate for blast radius control

**2. I/O Bridge**

- Native Zig event loop (std.event or direct io_uring)
- Zero-copy buffer management
- `fetch()` API implementation mapping to Zig HTTP client
- WebSocket and streaming response support

**3. Control Plane**

- Multi-tenant scheduler handling thousands of isolates
- URL-based routing to correct isolate
- Resource quotas (CPU time, memory, I/O operations)
- Hot reload via snapshot replacement

**4. Security Integration (MCPfier Bridge)**

- Pre-deployment code scanning
- Runtime PII detection
- Compliance audit logging for Brazilian regulations

-----

## Implementation Plan for Claude Code

### Phase 1: Foundation (Weeks 1-3)

**Goal: Hello World from V8 inside Zig**

```
Project Structure:
nano/
├── build.zig                 # V8 C++ header compilation
├── src/
│   ├── main.zig             # Entry point
│   ├── v8_wrapper.zig       # V8 isolate lifecycle
│   └── allocator.zig        # Arena per-request
└── examples/
    └── hello.js             # Test script
```

**Learning Path:**

1. **V8 Embedding Basics** (3 days)

- Study: V8 official embedding guide (v8.dev/docs/embed)
- Practice: Compile V8 from source, link against Zig
- Milestone: Execute `console.log("Hello from NANO")`

1. **Zig ↔ C++ Interop** (4 days)

- Study: Zig `@cImport` and `extern` functions
- Practice: Wrap V8’s `Isolate::New()`, `Context::New()`, `Script::Compile()`
- Milestone: Pass JavaScript strings between Zig and V8

1. **Arena Allocator Pattern** (3 days)

- Study: Zig’s `std.heap.ArenaAllocator` docs
- Practice: Create arena on request start, destroy on completion
- Milestone: Measure memory usage (should be ~0 leaked bytes)

**Claude Code Prompts:**

```
"Help me create a Zig build.zig that links against V8's C++ headers 
using zig c++ compilation. V8 is installed at /usr/local/v8."

"Write a Zig wrapper for V8's Isolate lifecycle: New(), Enter(), Exit(), 
Dispose(). Use arena allocator for all Zig-side memory."

"Create a function that executes JavaScript code in a V8 isolate and 
returns the result as a Zig string. Handle V8 exceptions gracefully."
```

-----

### Phase 2: HTTP & fetch() (Weeks 4-6)

**Goal: Handle HTTP requests and execute fetch() from JS**

**Learning Path:**

1. **Zig HTTP Server** (5 days)

- Study: Zig’s `std.http.Server` or use `zhp` library
- Practice: Accept connections, parse headers, respond
- Milestone: Basic HTTP echo server in pure Zig

1. **JavaScript ↔ Native Bridge** (5 days)

- Study: V8’s `FunctionTemplate` and `ObjectTemplate`
- Practice: Expose Zig functions as global JS functions
- Milestone: `globalThis.zigLog()` callable from JavaScript

1. **fetch() Implementation** (5 days)

- Study: Cloudflare Workers fetch API spec
- Practice: Map `fetch(url, options)` to Zig HTTP client
- Milestone: `await fetch("https://api.github.com")` works

**Claude Code Prompts:**

```
"Create a Zig HTTP server using std.http that routes requests based on 
the Host header. Each host should map to a different V8 isolate."

"Implement a V8 FunctionTemplate that exposes a Zig HTTP client as 
globalThis.fetch(). Support GET/POST with headers and JSON bodies."

"Write the Request and Response JavaScript classes matching the Fetch API 
spec, backed by Zig structs. Include .json(), .text(), .arrayBuffer()."
```

-----

### Phase 3: Multi-Tenancy (Weeks 7-9)

**Goal: Run 1000+ isolates in one process**

**Learning Path:**

1. **Isolate Pooling** (4 days)

- Study: workerd’s isolate recycling logic
- Practice: Maintain a pool of “warm” isolates
- Milestone: Reuse isolates across requests (avoid New() overhead)

1. **Snapshot System** (5 days)

- Study: V8’s `Snapshot::Create()` and `Isolate::CreateFromSnapshot()`
- Practice: Snapshot a “base” environment with common libraries
- Milestone: <1ms time from snapshot to executable isolate

1. **Resource Limits & Scheduling** (6 days)

- Study: V8’s `SetStackLimit()`, `SetMaxOldGenerationSize()`
- Practice: Implement CPU quota using Zig timers
- Milestone: Kill runaway scripts after 50ms execution

**Claude Code Prompts:**

```
"Design a Zig struct 'IsolatePool' that maintains 100 pre-warmed V8 
isolates. Implement acquire() and release() with LIFO semantics."

"Create a V8 snapshot that includes fetch(), console, and crypto APIs. 
Show how to create new isolates from this snapshot in <1ms."

"Implement a CPU quota system: if a JavaScript execution exceeds 50ms, 
terminate the isolate and return 'Execution Timeout' to the caller."
```

-----

### Phase 4: Production Hardening (Weeks 10-12)

**Goal: Production-ready with monitoring and MCP OSV and/or Spotter integration**

**Learning Path:**

1. **Zero-Copy I/O** (4 days)

- Study: io_uring fundamentals (if on Linux 5.10+)
- Practice: Pass network buffers directly to V8 without copying
- Milestone: Measure throughput (target: 100k req/s on single core)

1. **Observability** (3 days)

- Study: Prometheus metrics format
- Practice: Export isolate count, memory usage, request latency
- Milestone: Grafana dashboard showing live NANO metrics

1. **MCPfier Security Bridge** (5 days)

- Study: Your spotter and mcp-osv. it should be part of the cli toolchain to prevent supply chain attacks
- Practice: Scan JavaScript before isolate creation
- Milestone: Block scripts with SQL injection patterns or PII leaks

**Claude Code Prompts:**

```
"Implement zero-copy HTTP body parsing using io_uring. Bodies should be 
mapped directly into V8 ArrayBuffers without intermediate copies."

"Add Prometheus metrics: nano_isolates_active, nano_requests_total, 
nano_request_duration_ms, nano_active_apps. Export via /metrics endpoint."

```

-----

## Learning Resources (Prioritized)

### Critical Path (Study First)

1. **V8 Embedding Guide** - <https://v8.dev/docs/embed>

- Focus on: Isolate, Context, HandleScope, TryCatch

1. **Bun Source Code** - <https://github.com/oven-sh/bun>

- Files: `src/bun.js/bindings/` (Zig ↔ JSC patterns apply to V8)

1. **workerd** - <https://github.com/cloudflare/workerd>

- Files: `src/workerd/io/worker.c++` (isolate lifecycle management)

### Supporting Materials

1. **Zig’s std.http** - <https://ziglang.org/documentation/master/std/#std.http>
1. **deno_core** - <https://github.com/denoland/deno/tree/main/core>

- (Rust, but best-documented V8 platform code)

1. **io_uring Tutorial** - <https://kernel.dk/io_uring.pdf>

-----

## Success Metrics

**Technical:**

- Cold start: <5ms (measure with `perf stat`)
- Memory per isolate: <2MB (measure with `pmap`)
- Density: >1000 concurrent isolates on 1GB RAM
- Throughput: >100k req/s (single-threaded, simple echo handler)

**Business:**

- Deployment target: Self-hosted alternative to Cloudflare Workers
- Integration: Works with Guvnor for process management
- Security: MCPfier scans all deployed code
- Market: Brazilian SaaS companies needing multi-tenant JS execution

-----

## Claude Code Workflow

### Initial Session

```bash
# Start with architecture scaffolding
claude-code "Create the NANO project structure: build.zig with V8 linking, 
main.zig with basic isolate creation, and a README explaining the 
architecture. Use arena allocators for all memory management."
```

### Iterative Development Pattern

Each week, use this loop:

1. **Research** → Read 1-2 priority resources above
1. **Specify** → Write a 3-paragraph “mini-spec” of what to build
1. **Delegate to Claude Code** → Paste spec + ask for implementation
1. **Test** → Run `zig test` and measure performance
1. **Document** → Update README with learnings

### Example Week 4 Workflow

```
Day 1: Read Zig std.http docs
Day 2: Write spec: "HTTP server that routes by Host header to isolates"
Day 3: Claude Code implements it
Day 4-5: Test with wrk benchmark, fix memory leaks
```

-----

## Risk Mitigation

**V8 API Instability:** Pin to V8 12.x LTS branch (used by Node 22)  
**Zig Immaturity:** Use Zig 0.13.0 (latest stable), avoid nightly  
**Performance Unknowns:** Benchmark early (Week 2), iterate on hot paths  
**Scope Creep:** Ship “fetch + console” first, add crypto/WebSocket afterwards

-----

## Integration with Your Ecosystem

**With Lathe:** NANO becomes Lathe’s deployment target for “infrastructure-as-code that runs JS”  
**With Guvnor:** Guvnor manages NANO processes, provides HTTPS termination  
**With MCPfier:** Pre-deployment scanning + runtime monitoring

This creates your “Claude Code for DevOps” stack: Lathe (provision) → MCPfier (scan) → NANO (execute) → Guvnor (manage).

-----

This plan is designed to be **fed to Claude Code in chunks**—each phase’s prompts are self-contained. Start with Phase 1, measure success, then proceed. The learning path ensures you understand V8 deeply enough to debug production issues, while Claude Code handles the tedious C++ interop boilerplate.

