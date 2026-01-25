# Phase 4 Research: Snapshots + Pooling

## Requirements

### CORE-03: V8 snapshots enable <5ms cold start for new isolates
- Without snapshots: 40-100ms for isolate creation + API registration
- With snapshots: <2ms (snapshot contains pre-initialized state)
- Snapshot includes all Workers-compatible APIs from Phase 2

### CORE-04: Isolate pool maintains warm isolates for reuse between requests
- Pool of pre-created isolates ready to handle requests
- Avoids creation overhead even with snapshots
- LRU eviction when pool is full

## V8 Snapshot System

### How Snapshots Work

1. **Build Time**: Create a snapshot with all APIs registered
2. **Runtime**: Load isolates from snapshot instead of creating fresh

**Without snapshots (current approach):**
```
1. Create isolate (10-20ms)
2. Create context (1-2ms)
3. Register console API (1ms)
4. Register encoding APIs (2ms)
5. Register URL APIs (2ms)
6. Register crypto APIs (2ms)
7. Register fetch/Response APIs (2ms)
8. Register Request/Headers APIs (2ms)
= ~22-33ms total cold start
```

**With snapshots:**
```
1. Load isolate from snapshot (<2ms)
2. Create context from snapshot (<1ms)
= <3ms total cold start
```

### zig-v8 Snapshot API

```zig
const v8 = @import("v8");

// Creating a snapshot (build-time tool)
var params = v8.initCreateParams();
params.array_buffer_allocator = v8.createDefaultArrayBufferAllocator();

var snapshot_creator: v8.SnapshotCreator = undefined;
snapshot_creator.init(&params);

var isolate = snapshot_creator.getIsolate();
isolate.enter();

// Create context with all APIs
var context = v8.Context.init(isolate, null, null);
context.enter();

// Register all APIs
console.registerConsole(isolate, context);
encoding.registerEncodingAPIs(isolate, context);
// ... etc

// Set as default context for snapshot
snapshot_creator.setDefaultContext(context);

context.exit();
isolate.exit();

// Create the blob
const blob: v8.StartupData = snapshot_creator.createBlob(0); // 0 = kClear
// blob.data and blob.raw_size contain the snapshot

snapshot_creator.deinit();
```

```zig
// Loading from snapshot (runtime)
var params = v8.initCreateParams();
params.array_buffer_allocator = array_buffer_allocator;
params.snapshot_blob = &snapshot_data;

var isolate = v8.Isolate.init(&params);
// Isolate now has all APIs pre-registered!

// Create context from snapshot
var context = v8.Context.fromSnapshot(isolate, 0) orelse {
    // Fall back to regular context creation
    return v8.Context.init(isolate, null, null);
};
```

## Implementation Approach

### Plan 04-01: Snapshot Creation Tool

Create a build-time tool that generates a snapshot blob with all APIs:

1. Create `src/snapshot/create.zig` - standalone executable
2. Register all Phase 2 APIs in a context
3. Generate `nano.snapshot` blob
4. Embed blob in main binary (or load at runtime)

### Plan 04-02: Load Isolates from Snapshot

Modify app loading to use snapshots:

1. Load snapshot blob at server startup
2. Set `params.snapshot_blob` when creating isolates
3. Use `Context.fromSnapshot()` instead of `Context.init()`
4. Benchmark cold start improvement

### Plan 04-03: Isolate Pooling

Create a pool of warm isolates:

1. Pre-create N isolates at server startup
2. Request takes isolate from pool instead of creating
3. After request, return isolate to pool (reset state)
4. Pool grows/shrinks based on demand

## Technical Considerations

### Snapshot Compatibility
- Snapshots are V8-version-specific
- Must rebuild snapshot when V8 is upgraded
- Snapshot includes only serializable state

### What Can Be Snapshotted
- JavaScript built-ins
- Global objects and their properties
- Function templates (constructor blueprints)
- Object templates (property layouts)

### What Cannot Be Snapshotted
- C++ callbacks (function pointers change between runs)
- External resources (file handles, sockets)
- Typed arrays with external backing stores

### Solution for Callbacks
- Snapshot contains placeholders
- At runtime, replace placeholders with actual callbacks
- Use `FunctionTemplate::SetCallHandler()` after loading

## Current Cold Start Measurement

Before implementing, measure current cold start:

```bash
# Measure time to first response
time curl http://localhost:8080/

# Multiple measurements for p99
for i in {1..100}; do
  time curl -s http://localhost:8080/ > /dev/null
done
```

## Success Criteria

1. p99 cold start latency under 5ms (measured)
2. Warm isolates are reused for subsequent requests
3. Snapshot contains all Phase 2 APIs pre-initialized
4. No functionality regression from Phase 3

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Callbacks not restoring correctly | MEDIUM | HIGH | Test all APIs post-snapshot load |
| Snapshot size too large | LOW | MEDIUM | Measure and optimize if needed |
| Pooling memory overhead | LOW | MEDIUM | Configurable pool size |
| State leaking between requests | MEDIUM | HIGH | Full context reset between uses |

## Plan Structure

1. **04-01**: Snapshot Creation Tool
2. **04-02**: Load Isolates from Snapshot
3. **04-03**: Isolate Pool Implementation
