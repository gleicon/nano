# Production Hardening Gaps

## Status Summary

| Item | Status | Priority |
|------|--------|----------|
| Code Cleanup | DONE | - |
| Structured Logging | DONE | - |
| Apache Log Format | DONE | - |
| Execution Timeout | DEFERRED | HIGH (needs async) |
| Memory Limits | NOT DONE | HIGH |
| Metrics Endpoint | DONE | - |
| Graceful Shutdown | DONE | - |
| Health Endpoint | DONE | - |
| Error Responses | PARTIAL | LOW |

## Critical Gaps (Must Have for Production)

### 1. Execution Timeout (RLIM-01)
**Problem:** Infinite loop in JS hangs the server forever.

```javascript
// This kills the server
export default {
  fetch(request) {
    while(true) {} // Never returns
  }
}
```

**Solution Options:**
1. **V8 TerminateExecution()** - requires separate thread to call after timeout
2. **Zig async with timeout** - would need async HTTP handling
3. **Process-level timeout** - external watchdog kills worker

**Effort:** HIGH - requires threading or significant architecture change

### 2. Memory Limits (RLIM-02)
**Problem:** JS can allocate unbounded memory, crashing the host.

```javascript
// This crashes the server
export default {
  fetch(request) {
    const arr = [];
    while(true) arr.push(new Array(1000000));
  }
}
```

**Solution:**
V8 CreateParams allows setting heap limits:
```cpp
create_params.constraints.set_max_heap_size(128 * 1024 * 1024);
```

**Effort:** MEDIUM - need to expose V8 heap configuration through zig-v8

## Completed Items

### 3. Metrics Endpoint (OBSV-03) - DONE
- `/metrics` endpoint with Prometheus format
- Request counter, error counter
- Latency stats (avg, min, max)
- Uptime tracking

### 4. Graceful Shutdown - DONE
- SIGTERM/SIGINT signal handlers
- Logs final stats on shutdown
- Clean V8 shutdown

### 5. Health Endpoint - DONE
- `/health` and `/healthz` endpoints
- Returns `{"status":"ok"}`

### 5. Error Response Formatting
**Current:** Returns generic "Hello from NANO!" on some errors.

**Missing:**
- Proper 500 responses for JS errors
- Error details in logs (not response)
- Consistent error JSON format

**Effort:** LOW

## Nice to Have (v1.1+)

### 6. Health Check Endpoint
- `/health` or `/healthz`
- Returns 200 when ready
- Could include V8 status

### 7. Request ID Propagation
- Accept `X-Request-ID` header
- Generate if not present
- Include in all logs

### 8. Configuration File
- Port, log format, limits in config
- Environment variable overrides
- Default config discovery

## Recommended Priority for v1.0

1. **Memory Limits** - prevents OOM crashes
2. **Error Response Formatting** - basic reliability
3. **Graceful Shutdown** - clean restarts
4. **Metrics** - observability

Execution timeout is important but complex - may defer to v1.1 with async architecture.
