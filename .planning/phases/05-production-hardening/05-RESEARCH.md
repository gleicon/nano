# Phase 5 Research: Production Hardening

## Requirements

### RLIM-01: Infinite loops terminate after timeout (50ms default)
- V8 has TerminateExecution() API
- Need a watchdog thread or timer to enforce

### RLIM-02: Memory-hungry scripts fail at limit (128MB default) without crashing host
- V8 heap size limits via CreateParams
- NearHeapLimit callback for graceful handling

### RLIM-03: CPU time limits per request
- Related to RLIM-01, track execution time

### OBSV-01: Structured JSON logging includes app name, request ID, timestamp
- Replace std.debug.print with structured logger
- Generate request IDs (UUID or counter)

### OBSV-03: Prometheus metrics endpoint exposes isolate count, memory, latency
- Add /metrics endpoint
- Track: request count, latency histogram, memory usage

## Code Cleanup Findings

### Dead Code
| File | Item | Action |
|------|------|--------|
| src/api/fetch.zig:352 | `createResponse()` function | Remove - never used |

### Stub/Mock Implementations
| File | Item | Status |
|------|------|--------|
| src/api/fetch.zig:56-61 | `fetch()` throws "not implemented" | Document as intentional sync-only |
| src/engine/inspector_stubs.* | V8 inspector callbacks | Required stubs, keep |

### TODO Items to Address
| File:Line | TODO | Priority |
|-----------|------|----------|
| src/api/crypto.zig:144 | TypedArray input support | LOW - strings work |
| src/api/encoding.zig:233 | TypedArray decode support | LOW - strings work |

### Synchronous Design Decisions
The runtime is intentionally synchronous for v1.0:
- **fetch()**: Throws error (async HTTP would need Promise integration)
- **crypto.subtle.digest()**: Returns ArrayBuffer sync (Web Crypto is Promise-based)
- **Request handling**: Synchronous, one request at a time

These are acceptable for v1.0 but should be documented.

## Production Hardening Plan

### Plan 05-01: Code Cleanup - DONE
1. Removed unused `createResponse()` function
2. Removed "coming soon" and future promise language from error messages
3. Updated fetch.zig comment to be factual, not promissory

### Plan 05-02: Resource Limits
1. Add execution timeout via V8 TerminateExecution
2. Add memory limits via heap size configuration
3. Graceful error handling when limits hit

### Plan 05-03: Structured Logging - DONE
Created `src/log.zig` logging library:
- Structured JSON output with timestamp, level, event, fields
- Log levels: debug, info, warn, err
- Server uses logger for request/error logging
- CLI/REPL remain plain text (interactive output)

### Plan 05-04: Metrics Endpoint (Optional for v1.0)
1. Add /metrics endpoint
2. Expose basic counters
3. Prometheus-compatible format

## Success Criteria

1. Infinite loops terminate after timeout
2. Memory limits prevent OOM crashes
3. All requests have structured log entries
4. No dead code in codebase
