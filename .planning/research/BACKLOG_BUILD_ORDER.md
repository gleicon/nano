# Build Order & Integration Map: NANO Backlog Fixes

**Research Date:** 2026-02-15
**Scope:** Detailed build sequence for 7 backlog fixes
**Total Effort:** ~51 hours across 2 phases

---

## Build Order At A Glance

```
PHASE 1: ASYNC FOUNDATION (26-34 hours)
├─ Fix #1: Heap Buffers (4-6h) ─────────┐
├─ Fix #2: Async Fetch (16-20h) ◄──────┤ CRITICAL PATH
└─ Fix #3: WritableStream Async (6-8h) ┘

PHASE 2: API COMPLETION (20-25 hours)
├─ Fix #4: crypto.subtle (8-10h) ┐
├─ Fix #5: tee() Fix (4-6h)       ├─ PARALLEL
├─ Fix #6: structuredClone (4-6h) │
└─ Fix #7: URL Setters (2-3h)     ┘
```

---

## Fix-by-Fix Sequence

### FIX #1: Heap Buffers for Large Bodies (4-6 hours)

**Depends On:** Nothing (foundation)
**Unblocks:** Fix #2, indirectly #3-7 (allocator plumbing)

**Implementation Sequence:**
1. Create `src/allocator_context.zig` — helper module for storing request allocator on V8 context
2. Extend `src/js.zig` CallbackContext to include allocator field
3. Modify `src/server/app.zig` handleRequest() to store allocator on context
4. Update `src/api/fetch.zig:167-172` — replace fixed url_buf with fallback to heap
5. Update `src/api/crypto.zig:114-154` — replace fixed data_storage with fallback to heap
6. Add tests: allocator context storage, fallback on large inputs
7. Benchmark: verify no performance regression for < 4KB buffers (stay on stack)

**Files Modified:** 3 new (allocator_context.zig), 5 modified (js.zig, app.zig, fetch.zig, crypto.zig, url.zig)

**Validation:** fetch(10MB_url) works, crypto.digest(1MB_data) works, stack buffers used for small inputs

---

### FIX #2: Async Fetch (16-20 hours) ⭐ Most Complex

**Depends On:** Fix #1 (allocator context)
**Unblocks:** Fix #3 (Promise patterns stabilize)

**Prerequisite Research:** xev socket API, HTTP 1.1 parsing strategy

**Implementation Sequence:**

**2a: Socket Operations Infrastructure (6-8h)**
1. Create `src/runtime/socket_ops.zig` — async socket operation management
   - Define `SocketOp` struct (operation, resolver, timeout)
   - Implement `SocketOpQueue` with max limit (1000 ops)
   - Implement operation timeout cleanup
2. Expand `src/runtime/event_loop.zig`
   - Add `socket_ops_queue: SocketOpQueue` field
   - Implement `addSocketOp(hostname, port, request)` method
   - Modify `tick()` to process socket completions
   - Implement timeout checking and cleanup

**2b: fetch() Implementation (6-8h)**
1. Modify `src/api/fetch.zig`
   - Replace stub promises with real PromiseResolver storage
   - Implement persistent handle creation (page_allocator)
   - Schedule socket operation instead of returning early
   - Create `onFetchComplete` callback
2. Implement HTTP response parsing
   - Read response line + headers
   - Parse status, headers
   - Extract body (chunked or content-length)
3. Build Response object with parsed data
4. Resolve promise with Response

**2c: Event Loop Integration (2-4h)**
1. Ensure microtasks drain between event loop ticks
2. Integrate socket completion callbacks with Promise resolution
3. Handle errors: connection refused, timeout, DNS errors

**Files Modified:** 2 new (socket_ops.zig), 2 modified (event_loop.zig, fetch.zig)

**Validation:**
- `fetch("http://httpbin.org/get")` returns valid Response
- `await fetch()` resolves after ~100ms network delay
- Concurrent fetches don't interfere
- Network timeout returns rejected promise
- 1000 concurrent fetches don't OOM

**Checkpoint:** fetch() fully functional, promises resolve/reject correctly

---

### FIX #3: WritableStream Async Write Queue (6-8 hours)

**Depends On:** Fix #2 (Promise infrastructure stable)
**Unblocks:** Nothing (non-blocking for other fixes)

**Implementation Sequence:**
1. Modify `src/api/writable_stream.zig`
   - Add `_pendingWriteResolvers: []*v8.Persistent(v8.PromiseResolver)` field to WritableStream
   - Modify `write()` to create Promise + PromiseResolver
   - Check queue size against highWaterMark
   - If queue < HWM: resolve immediately
   - If queue >= HWM: store resolver, resolve later
2. Implement queue drain callback
   - Called when underlying sink writes complete
   - Resolve all pending write promises
3. Modify `ready` property getter
   - Return pending promise if backpressured
   - Return resolved promise if ready

**Files Modified:** 1 (writable_stream.zig)

**Validation:**
- `writer.write()` returns Promise
- Promise resolves when queue < highWaterMark
- ready property reflects backpressure state
- No deadlocks or unresolved promises

**Checkpoint:** WritableStream respects backpressure

---

## PHASE 2: API COMPLETION (20-25 hours)

All 4 fixes are independent. Recommend sequential implementation for clarity, but could parallelize.

---

### FIX #4: crypto.subtle Expansion (8-10 hours)

**Depends On:** Nothing (independent)
**Unblocks:** Nothing (independent)

**Implementation Sequence:**
1. Modify `src/api/crypto.zig`
2. Expand `digest()` to recognize:
   - "AES-GCM" → symmetric encryption (2h)
   - "ECDSA" → asymmetric signing (3h)
   - Keep existing "SHA-256", "SHA-384", "SHA-512" (no changes)
3. Implement AES-GCM:
   - Extract key (raw, JWK, or PEM format)
   - Extract IV, AAD, plaintext
   - Use `std.crypto.aes.Gcm()`
   - Return ciphertext + tag as ArrayBuffer
4. Implement ECDSA:
   - Support P-256, P-384, P-521 curves
   - Extract private key, message hash
   - Use `std.crypto.dsa.ecdsa*`
   - Return signature as ArrayBuffer
5. Add tests: NIST test vectors for AES, ECDSA

**Files Modified:** 1 (crypto.zig)

**Validation:**
- AES-256-GCM encrypt/decrypt round-trip succeeds
- ECDSA sign/verify with P-256 works
- Matches NIST test vectors
- Invalid key sizes raise clear errors
- SHA algorithms still work (no regression)

---

### FIX #5: ReadableStream.tee() Fix (4-6 hours)

**Depends On:** Nothing (independent)
**Unblocks:** Nothing (independent)

**Implementation Sequence:**
1. Modify `src/api/readable_stream.zig`
2. Implement `tee()` method
   - Create two new ReadableStream instances (branch1, branch2)
   - Add both to original stream's `_teeBranches` array
   - Each branch has independent `_queue`
3. Modify `controllerEnqueue()`
   - Check if stream has branches
   - If yes: enqueue chunk to each branch's queue independently
   - If no: normal enqueue
4. Each branch tracks own `_queueByteSize`, `_pulling`, etc.

**Files Modified:** 1 (readable_stream.zig)

**Validation:**
- `[b1, b2] = readable.tee()` returns 2 streams
- Read from b1: gets data
- Read from b2: gets same data (independent)
- Canceling b1 doesn't affect b2

---

### FIX #6: WinterCG Essentials (4-6 hours)

**Depends On:** Nothing (independent)
**Unblocks:** Nothing (independent)

**Implementation Sequence:**
1. Create `src/api/structured_clone.zig`
   - Register `structuredClone()` on global object
   - Use V8 `ValueSerializer` to serialize value
   - Use V8 `ValueDeserializer` to deserialize → deep copy
2. Ensure microtasks drain properly
   - Verify `performMicrotasksCheckpoint()` called after Promise resolution
   - No changes needed (already done in app.zig)

**Files Modified:** 1 new (structured_clone.zig), 1 modified (app.zig for registration)

**Validation:**
- `structuredClone({a:1,b:{c:2}})` returns independent copy
- Mutations to clone don't affect original
- Arrays, primitives, nested objects all work

---

### FIX #7: URL Property Setters (2-3 hours)

**Depends On:** Nothing (independent)
**Unblocks:** Nothing (independent)

**Implementation Sequence:**
1. Modify `src/api/url.zig`
2. Add setter for each property:
   - `pathname` setter → validate, update `_pathname`, re-serialize
   - `search` setter → validate, update `_search`, re-serialize
   - `hash` setter → validate, update `_hash`, re-serialize
   - `port` setter → validate (0-65535), update `_port`, re-serialize
   - `hostname` setter → validate, update `_hostname`, re-serialize
3. Implement `reserializeHref()` helper
   - Concatenates: protocol + hostname + port + pathname + search + hash
   - Updates `_href` property

**Files Modified:** 1 (url.zig)

**Validation:**
- `url.pathname = "/new"` updates `url.href`
- `url.search = "?foo=bar"` updates `url.href`
- Invalid port ignored (per spec)
- Original URL object and href getter still work

---

## Integration Dependencies Map

```
Fix #1 ─────┐
            ├─→ Fix #2 ─────┐
            │               └─→ Fix #3
            │
Fix #4 (independent)
Fix #5 (independent)
Fix #6 (independent)
Fix #7 (independent)
```

**Can parallelize in Phase 2:**
- 1 engineer on Fix #4 (crypto)
- 1 engineer on Fixes #5-7 (streams, URL)
- Meet in the middle for integration testing

---

## Time Breakdown

| Fix | Hours | Phase | Critical Path |
|-----|-------|-------|---|
| #1 | 4-6 | 1 | YES (blocks #2) |
| #2 | 16-20 | 1 | YES (longest) |
| #3 | 6-8 | 1 | YES (after #2) |
| #4 | 8-10 | 2 | NO |
| #5 | 4-6 | 2 | NO |
| #6 | 4-6 | 2 | NO |
| #7 | 2-3 | 2 | NO |
| **Total** | **44-59** | — | **26-34h critical** |

---

## Weekly Milestone Plan

### Week 1: Fix #1 (Foundation)
- **Mon-Wed:** Create allocator context infrastructure, update js.zig + app.zig
- **Wed-Thu:** Update fetch.zig, crypto.zig with heap buffer fallback
- **Thu-Fri:** Tests + benchmarking, verify no regression
- **Checkpoint:** Heap buffers working, allocator plumbing tested

### Week 2: Fix #2 (Async Fetch - Part 1)
- **Mon-Tue:** xev socket integration research, create socket_ops.zig
- **Tue-Wed:** Event loop socket queue + completion handlers
- **Wed-Thu:** HTTP response parsing, basic fetch() implementation
- **Thu-Fri:** Error handling, Promise callback plumbing
- **Checkpoint:** fetch() returns resolving promises

### Week 3: Fix #2 Complete + Fix #3 Start
- **Mon:** Fix #2 integration testing, load testing (100 concurrent)
- **Tue-Wed:** Fix #3 implementation — Promise-aware write queue
- **Wed-Thu:** Backpressure flow control, ready property
- **Thu-Fri:** Fix #3 tests + integration with fetch
- **Checkpoint:** Async foundation complete (Phase 1 done)

### Week 4: Fixes #4-7 Parallel
- **Track A (1 engineer):** Fix #4 (crypto expansion)
  - AES-GCM (Tue-Wed)
  - ECDSA (Thu-Fri)
  - Tests against NIST vectors

- **Track B (1 engineer):** Fixes #5-7 (APIs)
  - Fix #5 tee() (Mon-Tue)
  - Fix #6 structuredClone (Wed)
  - Fix #7 URL setters (Wed-Thu)
  - Tests + validation (Fri)

### Week 5: Integration & Release
- **Mon-Tue:** Cross-fix integration testing
- **Tue-Wed:** Load testing: 1000 concurrent operations
- **Wed-Thu:** Documentation, examples
- **Thu-Fri:** Release candidate testing, bug fixes
- **Checkpoint:** All 7 fixes tested, release candidate ready

---

## Testing Cadence

| Phase | When | What | Pass Criteria |
|-------|------|------|---|
| Per-fix | Daily | Unit tests for modified module | 80%+ coverage |
| Cross-fix | Weekly | Integration tests (fixes A+B together) | No regressions |
| Load | Week 3-4 | 1000 concurrent fetch + stream ops | No memory leak, < 5% latency hit |
| Spec | Week 5 | WinterCG compliance | All features work |

---

## Risk Mitigation Schedule

| Week | Risk | Mitigation |
|------|------|-----------|
| 1 | Allocator plumbing complexity | Early prototype, peer review |
| 2 | xev socket integration unknown | Pre-research, dedicated design doc |
| 3 | Promise callback lifecycle | Isolation tests, crash monitoring |
| 4 | Independent fixes interact | Integration matrix testing |
| 5 | Performance regression | Baseline benchmarking before release |

---

## Files to Modify/Create

### New Files (3)
- `src/allocator_context.zig` — Request allocator helpers
- `src/runtime/socket_ops.zig` — Async socket operations
- `src/api/structured_clone.zig` — structuredClone() implementation

### Modified Files (7)
- `src/js.zig` — Extend CallbackContext
- `src/server/app.zig` — Store allocator on context
- `src/api/fetch.zig` — Async fetch with socket ops
- `src/runtime/event_loop.zig` — Socket operation queue
- `src/api/writable_stream.zig` — Promise-aware write queue
- `src/api/readable_stream.zig` — tee() implementation
- `src/api/url.zig` — Property setters + re-serialization
- `src/api/crypto.zig` — AES/ECDSA expansion

### Total: 10 files (3 new, 7 modified, 0 deleted)

---

## Rollout Checklist

- [ ] Week 1: Fix #1 merged, tested
- [ ] Week 2: Fix #2 Phase 1 merged
- [ ] Week 3: Fixes #2-3 merged, Phase 1 checkpoint
- [ ] Week 4: Fixes #4-7 merged
- [ ] Week 5: Integration tests pass, load tests pass
- [ ] Week 5: Documentation updated
- [ ] Week 5: Release candidate tagged
- [ ] Week 6: Community feedback, bug fixes
- [ ] Week 6: Stable release published

---

## Conclusion

The build order prioritizes **critical path** (Fixes #1→2→3) while **enabling parallelization** in Phase 2 (Fixes #4-7). Total ~51 hours with clear weekly milestones and risk mitigations.

**Start date:** After xev socket API research complete (Week 0)
**Target release:** Week 6 (stable)
