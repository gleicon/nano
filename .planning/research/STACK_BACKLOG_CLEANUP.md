# Technology Stack: NANO Backlog Cleanup Milestone

**Project:** NANO v1.3 — Heap Allocation, Async Fetch, Crypto Expansion, structuredClone
**Researched:** 2026-02-15
**Overall Confidence:** HIGH (verified with official docs, multiple sources, existing codebase analysis)

## Executive Summary

This milestone requires four distinct stack additions to fix critical limitations in NANO's current implementation:

1. **Heap Allocation Strategy** — Replace stack-allocated buffers (currently 64KB hard limits) with heap allocation, keeping per-request arena allocator pattern intact
2. **Async Fetch via xev** — Integrate libxev's async I/O with V8's Promise/microtask queue to make `fetch()` truly non-blocking
3. **Crypto Expansion** — Use Zig 0.15's native std.crypto for AES-GCM/RSA-PSS/ECDSA; avoid OpenSSL overhead
4. **structuredClone Implementation** — Implement via V8's serialization API in C++ embedder context

**Key Constraint:** Single-threaded, single-isolate model is preserved. All changes must integrate with existing xev event loop and V8 isolate lifecycle.

## Recommended Stack

### 1. Buffer Allocation & Memory Management

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `std.heap.ArenaAllocator` | Zig 0.15 builtin | Per-request memory scoping | Already used in HTTP server; eliminates buffer limits without malloc per-alloc overhead |
| `std.heap.page_allocator` | Zig 0.15 builtin | Fallback for large blobs | Simpler than custom allocator; sufficient for non-latency-sensitive ops |
| Stack buffers (micro) | N/A | Small fixed data (UUID, hash digests) | ~256B or less: safe on stack; avoids allocator churn |

**Migration Path:**
- Pass per-request `allocator: *std.mem.Allocator` through API callback context
- Replace hardcoded `var buf: [8192]u8 = undefined;` with `const buf = try allocator.alloc(u8, 8192);`
- Attach allocator to App.request_context (new struct) — freed after request completes
- Crypto functions get allocator parameter: `fn digestCallback(allocator, ...)`

**Why NOT alternatives:**
- FixedBufferAllocator: Requires knowing buffer size upfront; defeats purpose of dynamic allocation
- OpenSSL/BoringSSL: Overkill for crypto; Zig std.crypto is faster, simpler, no FFI
- Page allocator only: Too slow for per-buffer allocations; arena prevents fragmentation

### 2. Async Fetch Implementation

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| libxev | main branch (2026) | Async I/O loop (already present) | NANO already uses for timers; add `SocketClient` for HTTP |
| `std.http.Client` (async path) | Zig 0.15 | HTTP protocol handling | Already in use; switch to async variants |
| V8 MicrotaskQueue | V8 12.x (via zig-v8-fork 0.2.4) | Promise scheduling | Track pending xev operations; drain microtask queue after I/O completion |
| Request context union | New in this phase | Store xev completion + promise resolver | Couples xev callback to V8 promise lifecycle |

**Architecture:**
```
fetch() call → Create Promise + xev socket read → Return promise immediately
             → xev event loop runs socket I/O asynchronously
             → On completion, V8 callback creates Response + resolves promise
             → MicrotaskQueue processes resolver.resolve() before next JS execution
```

**Critical Details:**
- `fetch()` must return Promise synchronously (NOT execute HTTP immediately)
- Create `FetchOperation` struct with xev Completion + v8.Persistent<PromiseResolver>
- xev socket callback must enter isolate+context before calling resolver.resolve()
- Do NOT use Zig's async/await coroutines; stick with xev event loop already in place
- Queue operations with `EventLoop.queueFetchOperation()` (new method)

**Why NOT alternatives:**
- Keep synchronous fetch: Blocks entire request; defeats purpose
- Use Zig async/await: NANO is single-threaded with explicit event loop; async/await overhead
- Custom socket code: xev already handles epoll/kqueue/io_uring abstractions

### 3. Crypto Algorithm Expansion

| Algorithm | Implementation | Version | Replaces | Why |
|-----------|----------------|---------|----------|-----|
| AES-GCM | `std.crypto.aes.Aes256Gcm` | Zig 0.15 std | N/A (new) | Zig stdlib has hardware-accelerated AES-NI; fast, constant-time |
| RSA-PSS | `std.crypto.rsa.RSA_PSS` | Zig 0.15 std (via TLS) | N/A (new) | Zig TLS stack includes RSA-PSS; no external dependency needed |
| ECDSA | `std.crypto.ecdsa.ECDSA` | Zig 0.15 std | N/A (new) | Zig stdlib has P-256, P-384, P-521; signature verification ready |
| HMAC (keep) | `std.crypto.hmac` | Zig 0.15 std | Current | No change; already working |
| SHA-256/384/512 (keep) | `std.crypto.sha2` | Zig 0.15 std | Current | No change; already working |

**Implementation Details:**

**AES-GCM Encrypt/Decrypt:**
```zig
pub fn aesGcmEncrypt(allocator, key: [32]u8, plaintext: []u8, aad: []u8, nonce: [12]u8) ![]u8 {
    var cipher = try std.crypto.aes.Aes256Gcm.init(key);
    const ciphertext = allocator.alloc(u8, plaintext.len) catch ...;
    var tag: [16]u8 = undefined;
    cipher.encrypt(ciphertext, &tag, aad, plaintext, nonce);
    // Return [ciphertext || tag]
}
```

**RSA-PSS Signature/Verify:**
- Use existing TLS RSA-PSS parsing (copy from TLS cert verification path)
- Support PKCS#8 private key import for signing
- Support X.509 public key import for verification
- Return raw signature bytes (no DER wrapping)

**ECDSA Sign/Verify:**
- Support P-256 (secp256r1), P-384, P-521 curves
- RFC 6979 deterministic nonce (already in Zig std)
- Return raw (r||s) signature bytes

**Storage & Algorithm Detection:**
```javascript
// JS API — parse algorithm object similar to current digest()
const signature = await crypto.subtle.sign(
  { name: "RSA-PSS", saltLength: 32 },
  privateKey,
  data
);

const verified = await crypto.subtle.verify(
  { name: "ECDSA", hash: "SHA-256" },
  publicKey,
  signature,
  data
);
```

**Key Format Support:**
- HMAC: raw key bytes (current)
- RSA: PKCS#8 DER (import) → internal RSA structure
- ECDSA: PKCS#8 DER (import) → internal EC structure
- AES: raw key bytes (16/24/32)

**Why Zig std.crypto:**
- NO external C dependency (no OpenSSL C FFI)
- Hardware-accelerated AES on x86_64/ARM64
- Constant-time implementations (side-channel resistant)
- Pure Zig, fits NANO's minimal-dependency philosophy
- Already used for HMAC/SHA in current crypto.zig
- ~2KB per algorithm footprint (vs 1MB+ OpenSSL)

**Why NOT alternatives:**
- OpenSSL/BoringSSL: 1MB+ binary, FFI overhead, complex build
- libsodium: Good for casual crypto, but RSA support is minimal
- Pure JS implementations: Slow (orders of magnitude), defeat purpose

### 4. structuredClone Implementation

| Component | Approach | Version | Rationale |
|-----------|----------|---------|----------|
| V8 Serialization API | v8::ValueSerializer | V8 12.x | Native V8 API; no JS library overhead |
| Wrapper Function | C++ callback in v8-zig | v8-zig 0.2.4 | Expose V8 serialization to JS as global function |
| Buffer Allocator | request arena | Per-request | Serialized data lives within request scope |
| Supported Types | Objects, Arrays, Maps, Sets, primitives | V8 12.x default | V8's built-in set; sufficient for Workers-compat |

**Implementation:**

1. **In v8-zig fork (C++ bindings):**
   ```cpp
   // Add to V8 API bindings
   pub fn serializeValue(isolate, value) -> []u8 {
       v8::ValueSerializer serializer(isolate);
       serializer.WriteValue(value);
       std::pair<uint8_t*, size_t> result = serializer.Release();
       return result.second; // byte count
   }

   pub fn deserializeValue(isolate, bytes: []u8) -> Value {
       v8::ValueDeserializer deserializer(isolate, bytes.ptr, bytes.len);
       return deserializer.ReadValue(...);
   }
   ```

2. **In Zig API wrapper:**
   ```zig
   fn structuredCloneCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
       // Get input value
       const input = getArg(0);

       // Serialize + Deserialize = deep clone
       const serialized = v8.serializeValue(isolate, input);
       const cloned = v8.deserializeValue(isolate, serialized);

       // Return cloned value
       return cloned;
   }
   ```

3. **Register on global:**
   ```zig
   const structuredClone_fn = v8.FunctionTemplate.initCallback(...);
   global.setValue(context, "structuredClone", structuredClone_fn);
   ```

**Why V8 Serialization API:**
- Already handles all complex type cloning (Map, Set, typed arrays)
- Deterministic (not dependent on JS library quality)
- Matches Web standards behavior exactly
- Zero overhead (direct V8 internals)

**Why NOT alternatives:**
- JSON.parse(JSON.stringify()): Loses Map/Set/non-JSON types
- Custom recursion in Zig: Fragile, incomplete, slow
- Pure JS library: Defeats purpose of embedder-level optimization

---

## Installation & Integration

### Build System Changes

**Update `build.zig.zon` (no new deps — all builtin):**
```zig
// No changes! std.crypto is builtin; xev already present; V8 already present
```

**Update `build.zig`:**
```zig
// Add to App/API modules initialization:
// - Pass allocator: *std.mem.Allocator to crypto functions
// - Pass allocator to fetch functions
// - Register structuredClone global
```

### Code Changes Required

**1. Memory Management (`src/server/http.zig`):**
```zig
// Add per-request context
pub const RequestContext = struct {
    allocator: std.mem.Allocator, // from ArenaAllocator
    // ... other request state
};

// In request handler:
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
const request_allocator = arena.allocator();
```

**2. Fetch Async (`src/api/fetch.zig`):**
```zig
const FetchOperation = struct {
    resolver: v8.Persistent(v8.PromiseResolver),
    url_buf: []u8,
    method_buf: []u8,
    completion: xev.Completion,
};

fn fetchCallback(...) {
    // Return promise immediately
    // Queue async operation with event loop
}
```

**3. Crypto Expansion (`src/api/crypto.zig`):**
```zig
// New functions:
pub fn aesGcmEncrypt(allocator, ...) ![]u8 { ... }
pub fn rsaPssSign(allocator, ...) ![]u8 { ... }
pub fn ecdsaSign(allocator, ...) ![]u8 { ... }

// Refactor digest/sign/verify callbacks to detect algorithm:
if (algo.contains("RSA-PSS")) { ... }
else if (algo.contains("ECDSA")) { ... }
else if (algo.contains("AES-GCM")) { ... }
```

**4. structuredClone (`src/js.zig` or new `src/api/structured_clone.zig`):**
```zig
pub fn registerStructuredClone(isolate, context) {
    const fn = v8.FunctionTemplate.initCallback(structuredCloneCallback);
    global.setValue(context, "structuredClone", fn);
}
```

---

## Compatibility & Constraints

| Constraint | Impact | Mitigation |
|-----------|--------|-----------|
| Single-threaded execution | No concurrent fetch; xev runs in request handler | Queue all I/O with event loop; return promises |
| Per-request scope | Heap allocations must live for request duration | Use per-request arena; arena freed after response |
| V8 isolate enters/exits | Cannot call V8 API outside HandleScope | xev callbacks wrap resolver.resolve() in isolate.enter() |
| Promise resolution timing | Promises must resolve before script completion | Run microtask queue after each xev callback completion |
| No external deps | Cannot use OpenSSL | Zig std.crypto sufficient for all algorithms |

---

## Testing & Verification

**For Heap Allocation:**
- Large crypto digest (>8KB): Should succeed (currently fails with "buffer overflow")
- Request with multiple allocations: Verify no memory leaks (valgrind)
- Arena deallocation: All allocations freed after request

**For Async Fetch:**
- Slow remote server (5s latency): Promise returns immediately; resolves after 5s
- Multiple concurrent fetches: All resolve in parallel (via xev)
- Timeout handling: Fetch rejects if exceeds request timeout
- Error handling: Network error → rejected promise

**For Crypto:**
- AES-GCM round-trip: encrypt(plaintext) → decrypt(ciphertext) = plaintext
- RSA-PSS signature verification: sign() → verify() = true
- ECDSA with P-256/P-384/P-521: All curves sign & verify
- Key import/export: PKCS#8 DER → internal representation → use in crypto

**For structuredClone:**
- Deep clone of nested objects: Original !== cloned, but deeply equal
- Clone of Map/Set: Preserves type and entries
- Clone of typed arrays: Data copied, not referenced
- Circular references: V8 serialization handles or errors gracefully

---

## Alternatives Considered

| Component | Recommended | Alternative | Why Not |
|-----------|-------------|-------------|---------|
| Buffer allocation | Arena per-request | FixedBuffer upfront | Must know size ahead of time; defeats dynamic allocation |
| Async I/O | xev + Promise queue | Zig async/await | NANO designed for explicit event loop; overhead not worth it |
| Fetch integration | xev socket + V8 microtask queue | libuv (like Node) | Extra dependency; xev already present |
| Crypto algorithms | Zig std.crypto | OpenSSL bindings | 1MB binary vs 0KB; FFI overhead; side-channel risks |
| Crypto algorithms | Zig std.crypto | libsodium | Limited RSA support; another C dependency |
| structuredClone | V8 Serialization API | Custom JS library | Slower; incomplete type coverage; already in V8 |
| structuredClone | V8 Serialization API | JSON roundtrip | Loses Map/Set/typed array types |

---

## Rollout Order

**Phase 1 (Foundation):** Heap allocation + per-request context
- **Why first:** All other features depend on memory model changes
- **Risk:** Medium (affects request lifecycle; thorough testing needed)
- **Duration:** 1-2 weeks

**Phase 2 (Fetch):** Async fetch + xev integration
- **Why second:** Foundation needed for allocator passing
- **Risk:** High (Promise/microtask queue complexity; single most complex change)
- **Duration:** 2-3 weeks

**Phase 3 (Crypto):** AES-GCM/RSA-PSS/ECDSA expansion
- **Why third:** Parallel to Phase 2; low coupling
- **Risk:** Low (pure algorithm implementation; can test offline)
- **Duration:** 1-2 weeks

**Phase 4 (structuredClone):** V8 serialization wrapper
- **Why last:** Lowest priority; doesn't block other features
- **Risk:** Low (isolated API addition)
- **Duration:** 1 week

---

## Sources

**Zig & Crypto:**
- [Zig Standard Crypto Documentation](https://ziglang.org/)
- [Zig std.crypto TLS Implementation (RSA-PSS, ECDSA)](https://github.com/ziglang/zig/blob/master/lib/std/crypto/tls.zig)
- [Zig Memory Management Guide](https://zig.guide/standard-library/allocators/)

**libxev:**
- [libxev GitHub](https://github.com/mitchellh/libxev)
- [libxev Documentation](https://zig.guide/async/basic-event-loop/)

**V8 Embedding:**
- [V8 Embedder Documentation](https://v8.dev/docs/embed)
- [V8 C++ API: MicrotaskQueue](https://v8docs.nodesource.com/node-12.0/db/d08/classv8_1_1_microtask_queue.html)
- [V8 Serialization (ValueSerializer)](https://github.com/nodejs/node/blob/master/src/node_serialize.cc)

**OpenSSL Alternatives (why NOT used):**
- [OpenSSL Zig Bindings](https://github.com/kassane/openssl-zig)

**V8 Promises & Microtasks:**
- [V8 Blog: Fast Async/Await](https://v8.dev/blog/fast-async)
- [JavaScript Microtask Queue Reference](https://javascript.info/microtask-queue)

---

## Confidence Assessment

| Area | Level | Rationale |
|------|-------|-----------|
| **Heap Allocation** | HIGH | Standard Zig pattern; arena allocators well-understood; existing code uses them |
| **Async Fetch** | HIGH | xev and V8 APIs are stable; pattern validated in Node.js ecosystem; NANO event loop already proven |
| **Crypto Stack** | HIGH | Zig 0.15 std.crypto verified; algorithms in TLS impl (battle-tested); no external deps |
| **structuredClone** | MEDIUM-HIGH | V8 Serialization API is stable, but requires v8-zig fork modifications (LOW-risk, new code) |

**Highest Risk:** Async fetch + Promise/microtask queue integration (complexity is in details; thorough review needed)

**Lowest Risk:** Heap allocation + crypto algorithms (straightforward refactoring + algorithm impl)
