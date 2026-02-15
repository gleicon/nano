# Feature Landscape: NANO Backlog Fixes

**Project:** NANO Backlog Cleanup Phase
**Researched:** 2026-02-15
**Scope:** 7 identified fixes to existing Zig+V8 runtime

---

## The 7 Backlog Fixes

### Fix 1: Heap Buffers for Large Bodies

**Status:** In-progress (foundation for others)
**User Impact:** Currently limited by 65KB stack buffers for HTTP bodies, crypto inputs
**Implementation:** Request allocator plumbing, fallback from stack to heap

| Aspect | Details |
|--------|---------|
| **Table Stakes?** | YES — affects all large inputs |
| **User-Visible Change?** | No (transparent) |
| **Blocking Other Fixes?** | YES (#2, #3, #6 need allocator) |
| **Complexity** | Low-Medium |
| **Time Estimate** | 4-6 hours |

**Why Expected:**
- Web services handle multi-MB request bodies routinely
- Crypto operations on large data sets expected
- Current 65KB limit breaks real use cases

---

### Fix 2: Async Fetch (Real Socket Operations)

**Status:** Blocked (needs #1)
**User Impact:** fetch() returns promises that never resolve (broken)
**Implementation:** xev socket integration, Promise lifecycle management

| Aspect | Details |
|--------|---------|
| **Table Stakes?** | YES — fundamental async API |
| **User-Visible Change?** | YES — fetch actually works |
| **Blocking Other Fixes?** | YES (#3 uses this pattern) |
| **Complexity** | High |
| **Time Estimate** | 16-20 hours |

**Why Expected:**
- fetch() is required by WinterCG spec
- Users expect real HTTP requests to work
- Current stub implementation is unusable

**API Contract After Fix:**
```javascript
const response = await fetch("http://example.com/api");
const data = await response.json();
console.log(data);
```

---

### Fix 3: WritableStream Async Write Queue

**Status:** Blocked (waits for async patterns from #2)
**User Impact:** write() doesn't respect backpressure, ready property not tracking state
**Implementation:** Promise-aware queue, pending write resolver tracking

| Aspect | Details |
|--------|---------|
| **Table Stakes?** | YES — backpressure is spec requirement |
| **User-Visible Change?** | YES — write() now returns Promise, respects backpressure |
| **Blocking Other Fixes?** | No |
| **Complexity** | Medium |
| **Time Estimate** | 6-8 hours |

**Why Expected:**
- Streams without backpressure cause memory bloat
- Users need to handle write() promises to prevent overflow
- required by WHATWG spec

**API Contract After Fix:**
```javascript
const writer = writable.getWriter();
try {
    await writer.write(largeChunk);
    // write() returns promise that resolves when ready
} finally {
    await writer.close();
}
```

---

### Fix 4: crypto.subtle Expansion (AES/ECDSA)

**Status:** Independent (no blockers)
**User Impact:** Only SHA available, AES/RSA/ECDSA missing
**Implementation:** Expand crypto.zig to handle symmetric (AES) and asymmetric (ECDSA) algorithms

| Aspect | Details |
|--------|---------|
| **Table Stakes?** | PARTIAL (SHA available, but AES/ECDSA expected) |
| **User-Visible Change?** | YES — new crypto algorithms available |
| **Blocking Other Fixes?** | No |
| **Complexity** | Medium |
| **Time Estimate** | 8-10 hours |

**Why Expected:**
- crypto.subtle is part of WinterCG spec
- Users expect AES-GCM for encryption
- Users expect ECDSA for signing (JWT, etc.)
- Zig std.crypto has these already available

**Algorithms Included:**
- AES-128, AES-192, AES-256 (symmetric encryption)
- AES-GCM mode (authenticated encryption)
- ECDSA with P-256, P-384, P-521 curves
- SHA-256, SHA-384, SHA-512 (already exist)

**Algorithms Deferred:**
- RSA (needs big integer math, complex, lower priority)
- ChaCha20, Poly1305 (not as common)

**API Contract After Fix:**
```javascript
// Encrypt with AES-GCM
const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: new Uint8Array(12) },
    key,
    data
);

// Sign with ECDSA
const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    data
);
```

---

### Fix 5: ReadableStream.tee() Implementation

**Status:** Blocked (partial implementation exists, needs branch queue fix)
**User Impact:** tee() not working correctly (single shared queue instead of independent branches)
**Implementation:** Per-branch queue architecture, branch coordination

| Aspect | Details |
|--------|---------|
| **Table Stakes?** | YES (tee is spec requirement) |
| **User-Visible Change?** | YES — tee() now returns working independent streams |
| **Blocking Other Fixes?** | No |
| **Complexity** | Medium |
| **Time Estimate** | 4-6 hours |

**Why Expected:**
- tee() is required by WinterCG spec
- Users need to split streams (e.g., logging + processing)
- Current implementation has shared queue (wrong behavior)

**API Contract After Fix:**
```javascript
const [branch1, branch2] = readable.tee();
// Each branch consumes independently
const promise1 = readAll(branch1);
const promise2 = readAll(branch2);
const [data1, data2] = await Promise.all([promise1, promise2]);
```

---

### Fix 6: WinterCG Essentials (structuredClone + Microtasks)

**Status:** Independent (no blockers)
**User Impact:** structuredClone() not available, microtasks may not drain properly
**Implementation:** V8 serialization API, ensure microtasks drain in event loop

| Aspect | Details |
|--------|---------|
| **Table Stakes?** | YES (part of WinterCG spec) |
| **User-Visible Change?** | YES — structuredClone becomes available |
| **Blocking Other Fixes?** | No |
| **Complexity** | Low |
| **Time Estimate** | 4-6 hours |

**Why Expected:**
- structuredClone() is WinterCG standard
- Users need deep cloning of objects
- Currently must implement custom clone logic
- V8 already has serialization API available

**API Contract After Fix:**
```javascript
const original = { a: 1, b: { c: 2 } };
const cloned = structuredClone(original);
cloned.b.c = 99;
console.log(original.b.c); // still 2
```

---

### Fix 7: URL Property Setters (href, pathname, search, hash, port)

**Status:** Independent (no blockers)
**User Impact:** URL properties read-only, can't mutate URL (workaround: create new URL)
**Implementation:** Add setters, re-serialize href from components

| Aspect | Details |
|--------|---------|
| **Table Stakes?** | NO (workarounds exist, but standard requires) |
| **User-Visible Change?** | YES — URL mutations work |
| **Blocking Other Fixes?** | No |
| **Complexity** | Low |
| **Time Estimate** | 2-3 hours |

**Why Expected:**
- WHATWG URL spec requires setters
- Users expect to modify URL components
- Currently forces workaround of creating new URL

**API Contract After Fix:**
```javascript
const url = new URL("http://example.com/path");
url.pathname = "/new-path";
url.search = "?foo=bar";
console.log(url.href); // "http://example.com/new-path?foo=bar"
```

---

## Feature Dependencies & Implementation Order

```
Fix #1: Heap Buffers (Foundation)
  ├─ Fix #2: Async Fetch (uses allocator)
  │   └─ Fix #3: WritableStream async (uses Promise pattern)
  │
  ├─ Fix #4: Crypto Expansion (independent)
  │
  ├─ Fix #5: tee() Fix (independent)
  │
  ├─ Fix #6: structuredClone (independent)
  │
  └─ Fix #7: URL Setters (independent)
```

**Critical Path:** #1 → #2 → #3 (17 hours minimum)
**Parallel Work:** #4, #5, #6, #7 can work in any order

---

## WinterCG Spec Mapping

| WinterCG Feature | Status | Fix |
|------------------|--------|-----|
| fetch() | Broken (promises don't resolve) | #2 |
| Response | Partial (no body streaming) | #2 (later) |
| ReadableStream | Partial (missing tee) | #5 |
| ReadableStream.tee() | Missing | #5 |
| WritableStream | Sync only (no backpressure) | #3 |
| WritableStreamDefaultWriter | Partial (no Promise wrapping) | #3 |
| crypto.subtle.digest() | SHA only | #4 |
| crypto.subtle.sign() | Stub | #4 |
| crypto.subtle.verify() | Stub | #4 |
| structuredClone() | Missing | #6 |
| URL | Partial (no setters) | #7 |

---

## After-Fix User Experience

### Before (Current State)

```javascript
// fetch doesn't work
const response = await fetch("http://api.example.com/data");
// ^ Returns a promise that never resolves ✗

// WritableStream doesn't handle backpressure
for (const chunk of hugeArray) {
    writer.write(chunk);  // No backpressure, can OOM ✗
}

// Crypto limited to SHA
const hash = await crypto.subtle.digest("SHA-256", data); // ✓ Works
const encrypted = await crypto.subtle.encrypt(...);       // ✗ Not implemented

// tee() doesn't work properly
const [a, b] = stream.tee();
// Both branches see same queue, data lost ✗

// No structuredClone
const copy = JSON.parse(JSON.stringify(obj));  // Workaround ✗

// URL immutable
const url = new URL("http://example.com");
url.pathname = "/new";  // Ignored ✗
```

### After (Post-Backlog)

```javascript
// fetch works
const response = await fetch("http://api.example.com/data");
const data = await response.json();  // ✓ Works

// WritableStream respects backpressure
for (const chunk of hugeArray) {
    await writer.write(chunk);  // Waits for backpressure ✓
}

// Crypto supports common algorithms
const hash = await crypto.subtle.digest("SHA-256", data);        // ✓
const encrypted = await crypto.subtle.encrypt("AES-GCM", ...);   // ✓
const signature = await crypto.subtle.sign("ECDSA", ...);        // ✓

// tee() works correctly
const [a, b] = stream.tee();
const dataA = await readAll(a);
const dataB = await readAll(b);  // Both get full data ✓

// structuredClone available
const copy = structuredClone(obj);  // Native API ✓

// URL mutations work
const url = new URL("http://example.com");
url.pathname = "/new";
url.search = "?foo=bar";
console.log(url.href);  // "http://example.com/new?foo=bar" ✓
```

---

## Validation Checklist

After each fix is complete, verify:

### Fix #1 (Heap Buffers)
- [ ] fetch() accepts 10MB URL
- [ ] crypto.subtle.digest() works with 1MB data
- [ ] Stack buffers still used for < 4KB inputs (optimization)
- [ ] No performance regression from heap allocation

### Fix #2 (Async Fetch)
- [ ] fetch("http://example.com") returns resolving Promise
- [ ] Handles redirects (3xx)
- [ ] Handles errors (DNS, connection refused, timeout)
- [ ] Multiple concurrent fetches don't interfere

### Fix #3 (WritableStream Async)
- [ ] write() returns Promise
- [ ] write() Promise resolves when queue below highWaterMark
- [ ] ready property returns pending Promise when backpressured
- [ ] No deadlocks or hangs

### Fix #4 (Crypto Expansion)
- [ ] AES-GCM encrypt/decrypt round-trips
- [ ] ECDSA sign/verify works
- [ ] SHA-256/384/512 still work (no regression)
- [ ] Invalid algorithm names throw errors

### Fix #5 (tee())
- [ ] tee() returns array of 2 ReadableStreams
- [ ] Each branch reads independently
- [ ] Chunks delivered to both branches (not just one)
- [ ] Canceling one branch doesn't affect other

### Fix #6 (structuredClone)
- [ ] structuredClone(obj) available globally
- [ ] Handles objects, arrays, primitives
- [ ] Handles nested structures
- [ ] Rejects circular references (or handles them)

### Fix #7 (URL Setters)
- [ ] url.pathname = "..." updates href
- [ ] url.search = "..." updates href
- [ ] url.hash = "..." updates href
- [ ] url.port = "..." updates href
- [ ] Invalid port silently ignored (per spec)

---

## Success Metrics

### Code Quality
- **Test Coverage:** ≥ 80% for new code
- **Integration Tests:** All fix combinations tested
- **Load Tests:** 1000 concurrent operations without memory leak
- **Performance:** No regression in benchmarks

### Spec Compliance
- **WinterCG:** All 7 fixes improve compliance score
- **WHATWG:** URL, Fetch, Streams specs align

### User Experience
- **Error Messages:** Clear, actionable
- **Documentation:** Updated for each API
- **Examples:** Working examples for each fix

---

## Rollout Plan

### Alpha (Internal Testing)
- Complete all 7 fixes
- Run full test suite
- Load test with 1000 concurrent ops
- Dogfood with real workload

### Beta (Community Testing)
- Release preview build
- Collect feedback
- Fix critical issues
- 1-2 week window

### Stable Release
- Full release with all 7 fixes
- Version bump (v1.3 or v2.0 depending on breaking change assessment)
- Update docs
- Blog post: "NANO now supports async fetch, streams, and more"

---

## Not Included (Deferred)

These features are NOT part of this backlog cleanup:

| Feature | Why Deferred |
|---------|--------------|
| RSA Encryption | Requires big integer math, adds complexity, lower priority than AES/ECDSA |
| TransformStream | Not critical path, can add in next milestone |
| ReadableStream.from() | Partial implementation exists, may need future fixes |
| WebSocket | Significant async infrastructure, separate project |
| setTimeout/setInterval improvements | Already working, not a blocker |

---

## Conclusion

These 7 fixes transform NANO from a toy runtime with broken async APIs to a functional WinterCG-compliant environment suitable for real web applications.

**Quick wins:** Fixes #4, #6, #7 are low-risk, high-value
**Critical path:** Fixes #1 → #2 → #3 form the core async infrastructure
**Total scope:** ~51 hours to implement all 7 across 10 files
