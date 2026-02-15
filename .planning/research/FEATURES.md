# Feature Landscape: Backlog Cleanup Phase

**Domain:** JavaScript runtime API compatibility (Workers/Deno)
**Researched:** 2026-02-15
**Milestone:** Backlog cleanup (fixing known limitations, expanding APIs)
**Confidence:** HIGH (verified against official Workers/Deno docs, V8 API specs, WHATWG standards)

## Executive Summary

NANO's backlog contains five high-priority feature improvements targeting compatibility with Cloudflare Workers and Deno. Research confirms that async fetch() requires event loop integration; crypto.subtle needs algorithmic expansion in clear priority order; structuredClone uses V8's native Serializer/Deserializer; queueMicrotask integrates with V8's microtask queue; and performance.now() requires high-resolution timer binding. All are standard APIs with clear compatibility requirements. The main complexity lies in architectural integration—not API surface design.

---

## Table Stakes vs Differentiators vs Anti-Features

Each backlog item maps to feature complexity and Workers compatibility expectations.

### fetch() — Currently Synchronous/Blocking

**Current state:** Works but blocks the event loop (synchronous HTTP).

**Table Stakes:**
- `async fetch()` with Promise<Response> — non-blocking HTTP required for Workers compatibility
- Proper streaming request/response bodies (ReadableStream integration)
- Automatic response decompression per fetch spec
- SSRF protection (already exists, no changes needed)

| Feature | Why Expected | Complexity | Priority | Status |
|---------|--------------|------------|----------|--------|
| Async fetch() | Workers spec requirement, essential for concurrent requests | HIGH | CRITICAL | Blocking |
| Request body streaming | ReadableStream as request body | MEDIUM | HIGH | Depends on Streams |
| Response body streaming | ReadableStream as response.body | MEDIUM | HIGH | Depends on Streams |
| Automatic decompression | Per WHATWG fetch spec | MEDIUM | MEDIUM | Partial |
| Abort signal support | Already implemented, but validate | LOW | MEDIUM | Needs testing |

**Differentiators:**
- Request/response interceptors (not standard, but useful)
- Connection pooling (for performance)
- Custom DNS resolver (advanced use case)

**Anti-Features:**
- Synchronous fetch() — document as unsupported
- Fetch without timeout — enforce max timeout per request
- Unbounded response buffering — stream or reject large responses

**Why blocking:** NANO's current fetch is blocking because it uses synchronous Zig HTTP client. Event loop integration requires:
1. Async I/O (libuv, xev integration)
2. Promise integration with Zig HTTP calls
3. Proper microtask checkpoint handling

**Complexity Assessment:**
- Architectural change: HIGH (integrate async I/O with V8 event loop)
- API surface: LOW (standard fetch API already exposed)
- Testing: MEDIUM (network-dependent, needs mock support)

**Sources:**
- [Cloudflare Workers fetch()](https://developers.cloudflare.com/workers/runtime-apis/fetch/)
- [WHATWG Fetch Standard](https://fetch.spec.whatwg.org/)
- [Deno HTTP implementation](https://docs.deno.com/deploy/classic/api/runtime-fetch/)

---

### crypto.subtle — Currently HMAC-Only

**Current state:** `digest()`, `sign()` (HMAC only), `verify()` (HMAC only).

**Missing:** RSA, ECDSA, AES, key generation, import/export, derivation, wrapping.

**Table Stakes (Algorithm Priority):**

Based on Workers and Deno implementations, prioritize algorithms in this order:

| Priority | Algorithm Category | Algorithms | Usage |
|----------|-------------------|-----------|-------|
| **CRITICAL** | **Hashing** | SHA-256, SHA-384, SHA-512, SHA-1 | Foundation for all signatures |
| **CRITICAL** | **HMAC** | HMAC with SHA-256, SHA-384, SHA-512 | JWT signing, message authentication |
| **CRITICAL** | **RSA** | RSA-PSS (sign/verify), RSASSA-PKCS1-v1_5 | Key encryption, legacy JWT |
| **CRITICAL** | **ECDSA** | ECDSA with SHA-256, SHA-384, SHA-512 | Modern signing, Web3 |
| **HIGH** | **AES** | AES-GCM, AES-CBC | Symmetric encryption, common |
| **HIGH** | **Elliptic Curves** | P-256, P-384, P-521 | ECDSA, ECDH key generation |
| **MEDIUM** | **Key Derivation** | HKDF, PBKDF2 | Password hashing, KDF |
| **MEDIUM** | **Key Management** | generateKey(), importKey(), exportKey() | Full crypto workflow |
| **MEDIUM** | **EdDSA** | Ed25519 | Modern post-quantum alternative |
| **LOW** | **AES-KW** | Key wrapping | Specialized use case |

**Table Stakes Feature Breakdown:**

| Method | Why Expected | Complexity | Notes |
|--------|--------------|------------|-------|
| `digest()` | SHA hashing — foundational | LOW | Already implemented (SHA-256/384/512/1) |
| `generateKey()` | Create cryptographic keys | MEDIUM | Asymmetric (RSA, ECDSA) and symmetric (AES, HMAC) |
| `importKey()` | Load keys from JWK/PKCS8/SPKI/raw | MEDIUM | Multiple formats, validation required |
| `exportKey()` | Serialize keys to portable format | MEDIUM | Security-aware (extractable flag) |
| `sign()` | RSA-PSS, ECDSA, HMAC (already have) | MEDIUM | Expand from current HMAC-only |
| `verify()` | Signature verification | MEDIUM | Expand from current HMAC-only |
| `encrypt()/decrypt()` | AES-GCM, AES-CBC, RSA-OAEP | MEDIUM | Symmetric and asymmetric |
| `deriveBits()/deriveKey()` | HKDF, PBKDF2, ECDH | MEDIUM | Key derivation workflows |

**Differentiators:**
- `timingSafeEqual()` — constant-time comparison (Deno has this)
- Post-quantum algorithms (ML-KEM, ML-DSA) — Node.js v24+ has these
- ChaCha20-Poly1305 — modern AEAD
- Scrypt — password hashing

**Anti-Features:**
- MD5 — deprecated, unless required for legacy interop
- DES/3DES — broken, don't implement
- Synchronous operations — all must be async Promises

**Complexity Assessment (Phased):**

Phase 1 (MVP):
- Digest: SHA hashing (already done)
- Sign/Verify: RSA-PSS, ECDSA with SHA-256 (expand existing)
- Complexity: MEDIUM (200-300 LOC per algorithm family)

Phase 2 (Encryption):
- AES-GCM, AES-CBC
- RSA-OAEP
- Complexity: MEDIUM-HIGH (300-400 LOC)

Phase 3 (Key Management + Derivation):
- generateKey() for RSA, ECDSA, AES
- importKey/exportKey with JWK support
- HKDF, PBKDF2
- Complexity: HIGH (400-500 LOC)

**Why Zig crypto is sufficient:**
- Zig std.crypto has all critical algorithms (SHA, HMAC, RSA, ECDSA, AES, HKDF, PBKDF2)
- No external dependencies needed
- Direct V8 binding possible

**Sources:**
- [Cloudflare Workers Web Crypto](https://developers.cloudflare.com/workers/runtime-apis/web-crypto/)
- [Node.js Web Crypto API](https://nodejs.org/api/webcrypto.html)
- [Deno SubtleCrypto](https://docs.deno.com/api/web/~/SubtleCrypto)
- [MDN SubtleCrypto](https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto)
- [WHATWG Web Crypto Standard](https://www.w3.org/TR/WebCryptoAPI/)
- [Zig std.crypto documentation](https://ziglang.org/documentation/master/std/#std.crypto)

---

### structuredClone() — Not Yet Implemented

**Current state:** Missing entirely.

**Table Stakes:**

| Feature | Why Expected | Complexity | Priority |
|---------|--------------|------------|----------|
| `structuredClone(value)` | Deep cloning with spec compliance | MEDIUM | HIGH |
| Support for Object, Array, primitives | Core types | LOW | CRITICAL |
| Support for TypedArray, ArrayBuffer | Binary data | LOW | CRITICAL |
| Support for Map, Set, Date, Error | Container types | MEDIUM | HIGH |
| Support for Blob, File, FormData | Web API types | MEDIUM | MEDIUM |
| Circular reference handling | Self-referential objects | MEDIUM | HIGH |
| `transferList` parameter | Optional transfer semantics | LOW | LOW |

**Spec Compliance:**

structuredClone follows the [HTML specification](https://html.spec.whatwg.org/multipage/structured-data.html#structuredclone), which defines what can/cannot be cloned:

**Cloneable (Table Stakes):**
- Primitive types: undefined, null, boolean, number, string, bigint, symbol
- Object, Array
- TypedArray (all variants), ArrayBuffer, DataView
- Map, Set
- Date, Error, RegExp
- Blob (Deno/Workers support)
- FormData (Workers support)

**Not Cloneable (Important to reject gracefully):**
- Function (must throw)
- DOM nodes (not applicable in worker context)
- WeakMap, WeakSet (not applicable)

**Differentiators:**
- Custom clone behavior via serialization hooks (not standard)
- Async cloning (not standard, but useful for large objects)

**Anti-Features:**
- Shallow cloning — explicitly not structuredClone
- Synchronous cloning of large objects — may block, but acceptable for stdlib
- Silent failures on unclonable types — must throw TypeError

**Implementation via V8 Serializer/Deserializer:**

V8 provides native support through C++ API:
- `v8::ValueSerializer` — encode value to binary format
- `v8::ValueDeserializer` — decode from binary format
- Full HTML Structured Clone Algorithm compliance
- Used internally for `postMessage()`, Workers `waitUntil()`, etc.

**Zig Binding Approach:**

Option 1 (Recommended): Direct V8 Serializer binding
```zig
// Pseudocode
const serializer = v8.ValueSerializer.new(isolate);
serializer.writeValue(context, value);
const buffer = serializer.releaseBuffer();

const deserializer = v8.ValueDeserializer.new(isolate, buffer);
const cloned = deserializer.readValue(context);
```

Option 2: Implement in JavaScript (simpler but slower)
- Recursive walk and object reconstruction
- Less efficient, but works for MVP

**Complexity Assessment:**
- Direct V8 binding: LOW (100-150 LOC Zig + V8 API calls)
- JavaScript polyfill: MEDIUM (200-300 LOC JS)
- Testing: MEDIUM (type coverage, circular refs, edge cases)

**Why critical for Workers compatibility:**
- Used in Worker request/response handling
- Expected by developers porting from Workers
- Standard library assumption in many frameworks

**Sources:**
- [HTML Structured Clone Algorithm](https://html.spec.whatwg.org/multipage/structured-data.html#structuredclone)
- [MDN structuredClone](https://developer.mozilla.org/en-US/docs/Web/API/structuredClone)
- [V8 ValueSerializer API](https://v8.github.io/api/head/v8-value-serializer_8h.html)
- [Node.js v8.serialize()](https://nodejs.org/api/v8.html#v8_v8_serialize_value)

---

### queueMicrotask() — Not Yet Implemented

**Current state:** Missing entirely.

**Table Stakes:**

| Feature | Why Expected | Complexity | Priority |
|---------|--------------|------------|----------|
| `queueMicrotask(callback)` | Schedule callback before next macrotask | LOW | MEDIUM |
| Execution in microtask queue | FIFO ordering, runs before setTimeout | LOW | CRITICAL |
| Nestable (queueMicrotask within queueMicrotask) | Recursive microtask queueing | LOW | HIGH |
| Works with async/await | Part of Promise machinery | LOW | CRITICAL |
| No return value | Void function | LOW | CRITICAL |

**Spec Compliance:**

Per [HTML specification](https://html.spec.whatwg.org/multipage/webappapis.html#queueing-a-microtask):

```
queueMicrotask() adds callback to the microtask queue.
Microtasks execute:
1. After the current script (same macrotask)
2. After all currently-queued microtasks
3. Before the next macrotask (setTimeout, etc.)

Event loop pseudocode:
while (hasEvents) {
  task = macrotaskQueue.pop()
  execute(task)

  while (microtaskQueue.hasItems()) {
    microtask = microtaskQueue.pop()
    execute(microtask)
  }

  if (needsRendering) render()
}
```

**Why it matters:**
- Promise.then() callbacks are microtasks (V8 already handles via MicrotaskQueue)
- queueMicrotask() exposes this for user code
- Async/await depends on this ordering
- Some React/Vue patterns rely on queueMicrotask()

**V8 Integration:**

V8 has `v8::Isolate::EnqueueMicrotask()`:
```cpp
// Add callback to current isolate's microtask queue
isolate->EnqueueMicrotask(fn);

// Process all queued microtasks
isolate->PerformCheckpoint(isolate->GetCurrentContext());
```

**Zig Binding Approach:**

```zig
pub fn queueMicrotaskCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) {
        js.throw(ctx.isolate, "queueMicrotask requires a function argument");
        return;
    }

    const callback = ctx.arg(0);
    if (!callback.isFunction()) {
        js.throw(ctx.isolate, "queueMicrotask argument must be a function");
        return;
    }

    // Wrap callback to call it with no arguments
    const wrapped = createCallableWrapper(ctx.isolate, callback);
    ctx.isolate.enqueueMicrotask(wrapped);
}
```

**Complexity Assessment:**
- Binding: LOW (50-100 LOC Zig)
- Testing: MEDIUM (timing-dependent, race conditions)
- Integration: LOW (purely additive, no event loop changes needed)

**Current NANO State:**
- V8 event loop already uses MicrotaskQueue (for Promises)
- Event loop checkpoint happens after macrotasks
- Just need to expose EnqueueMicrotask to JavaScript

**Anti-Features:**
- Synchronous callback execution — must be asynchronous
- Callback with arguments — standard spec takes no args

**Sources:**
- [HTML queueMicrotask specification](https://html.spec.whatwg.org/multipage/webappapis.html#queueing-a-microtask)
- [MDN queueMicrotask](https://developer.mozilla.org/en-US/docs/Web/API/queueMicrotask)
- [V8 MicrotaskQueue API](https://v8docs.nodesource.com/node-12.0/db/d08/classv8_1_1_microtask_queue.html)
- [JavaScript.info: Microtasks](https://javascript.info/microtask-queue)

---

### performance.now() — Not Yet Implemented

**Current state:** Missing entirely.

**Table Stakes:**

| Feature | Why Expected | Complexity | Priority |
|---------|--------------|-----------|----------|
| `performance.now()` | High-resolution timestamp in milliseconds | LOW | MEDIUM |
| Returns DOMHighResTimeStamp (float) | Milliseconds with fractional precision | LOW | CRITICAL |
| Monotonic increasing | Never decreases, unaffected by system clock | LOW | CRITICAL |
| Relative to timeOrigin | Starts from page load (or arbitrary point in NANO) | LOW | HIGH |
| Microsecond resolution (ideal) | 5µs precision if possible, else 1ms | LOW | MEDIUM |

**Spec Compliance:**

Per [W3C High Resolution Time Standard](https://www.w3.org/TR/hr-time/):

```javascript
performance.now() // => 1234.567890 (milliseconds)

// Properties:
performance.timeOrigin   // => timestamp when context was created
// now() is relative to timeOrigin
performance.now() >= 0   // Always true
```

**Why it matters:**
- Benchmarking code
- Frame timing measurements
- Request latency tracking
- Standard in all JavaScript runtimes

**NANO Implementation Strategy:**

Two approaches:

**Option 1: Relative to script start (Recommended)**
```zig
const start_time = std.time.nanoTimestamp(); // When context created
const now_nanos = std.time.nanoTimestamp();
const elapsed_ms = @as(f64, @floatFromInt(now_nanos - start_time)) / 1_000_000.0;
```

**Option 2: Relative to process start**
```zig
// Less accurate for request timing, but works
const elapsed_ms = getElapsedMsSinceProcessStart();
```

**timeOrigin setup:**
- Set timeOrigin to context creation time
- Expose `performance.timeOrigin` as a timestamp
- Document that timeOrigin is relative to isolate creation, not Unix epoch

**V8 Integration:**

V8's `v8::Date::Now()` returns milliseconds since epoch with high precision:
```cpp
double now_ms = v8::Date::Now(isolate);
```

But for timeOrigin-relative timing, better to use system clock directly.

**Zig Binding Approach:**

```zig
var g_context_start_nanos: i128 = 0; // Per-context

pub fn performanceNowCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const now_nanos = std.time.nanoTimestamp();
    const elapsed_nanos = now_nanos - g_context_start_nanos;
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_nanos)) / 1_000_000.0;

    const result = v8.Number.initDouble(ctx.isolate, elapsed_ms);
    js.ret(ctx, result);
}
```

**Complexity Assessment:**
- Binding: LOW (50-100 LOC Zig)
- Testing: MEDIUM (timing assertions, precision checks)
- Integration: LOW (purely additive)

**Why simple:**
- No dependencies on event loop
- No state machine needed
- Just arithmetic on system time

**Anti-Features:**
- `performance.mark()/measure()` — defer to later phase (not critical)
- `performance.getEntriesByType()` — not needed for MVP
- Configurable precision — use system precision as-is

**Sources:**
- [W3C High Resolution Time API](https://www.w3.org/TR/hr-time-3/)
- [MDN Performance.now()](https://developer.mozilla.org/en-US/docs/Web/API/Performance/now)
- [Cloudflare Workers performance API](https://developers.cloudflare.com/workers/runtime-apis/web-crypto/#performance)
- [Deno performance API](https://docs.deno.com/api/web/~/Performance)

---

## Dependency Graph

Understanding what needs to be done in which order:

```
Microtask Queue (V8 already has this)
    ↓
queueMicrotask()
    ↓
Promise handling (already works)

System Clock API
    ↓
performance.now()

V8 Serializer/Deserializer
    ↓
structuredClone()

Event Loop + Async I/O runtime (xev/tokio-like)
    ↓
async fetch()

Zig crypto libraries + V8 bindings
    ↓
crypto.subtle (RSA, ECDSA, AES, etc.)
    ↓
Full Web Crypto compatibility
```

**No dependencies between items** — can be implemented in any order except:
- `async fetch()` requires event loop refactoring (may impact other code)
- `crypto.subtle` expansion can happen independently
- `structuredClone`, `queueMicrotask`, `performance.now()` are purely additive

---

## Implementation Complexity Summary

| Feature | LOC | Risk | Duration | Notes |
|---------|-----|------|----------|-------|
| **queueMicrotask()** | 50-100 | LOW | 2-4 hours | V8 API exposure |
| **performance.now()** | 50-100 | LOW | 2-4 hours | System time binding |
| **structuredClone()** | 100-200 | MEDIUM | 4-8 hours | V8 Serializer usage |
| **crypto.subtle (Phase 1: RSA/ECDSA)** | 300-400 | MEDIUM | 1-2 weeks | Algorithm implementation |
| **crypto.subtle (Phase 2: AES/encryption)** | 300-400 | MEDIUM | 1-2 weeks | More algorithms |
| **crypto.subtle (Phase 3: Key mgmt)** | 400-500 | MEDIUM-HIGH | 2-3 weeks | Complex workflows |
| **async fetch()** | 500-800 | HIGH | 2-4 weeks | Event loop integration |

**Total MVP (queueMicrotask + performance.now + structuredClone + crypto Phase 1):**
~500-800 LOC, 3-4 weeks

---

## Feature Priorities for Backlog Cleanup

Based on impact/effort:

| Rank | Feature | Effort | Impact | MVP | Rationale |
|------|---------|--------|--------|-----|-----------|
| 1 | `queueMicrotask()` | LOW | MEDIUM | YES | Quick win, enables Promise patterns |
| 2 | `performance.now()` | LOW | MEDIUM | YES | Quick win, common in benchmarks |
| 3 | `structuredClone()` | MEDIUM | MEDIUM | YES | Standard library, some frameworks expect |
| 4 | `crypto.subtle` Phase 1 (RSA/ECDSA) | MEDIUM | HIGH | YES | Workers compatibility, critical for auth |
| 5 | `crypto.subtle` Phase 2 (AES) | MEDIUM | HIGH | NO | Encryption, important but not urgent |
| 6 | `async fetch()` | HIGH | CRITICAL | NO | Architectural change, highest impact |
| 7 | `crypto.subtle` Phase 3 (Key mgmt) | MEDIUM-HIGH | MEDIUM | NO | Advanced workflows |

**Recommended MVP for immediate backlog:** #1-4

---

## Testing Strategy

| Feature | Testing Approach | Test Vectors |
|---------|------------------|--------------|
| `queueMicrotask()` | Event loop ordering (microtask vs macrotask) | Test nesting, Promise interaction |
| `performance.now()` | Monotonic increase, relative timing | Measure elapsed time, confirm no regression |
| `structuredClone()` | Type coverage, circular refs, error cases | TypedArray, Map/Set, recursive objects |
| `crypto.subtle` | Algorithm verification, interop | Known test vectors (NIST, RFC), compare with openssl |
| `async fetch()` | Network simulation, promise chains | Mock HTTP responses, timeout handling |

**Sources for test vectors:**
- [NIST CAVP Test Vectors](https://csrc.nist.gov/projects/cryptographic-algorithm-validation-program/)
- [RFC 3394 (AES-KW)](https://tools.ietf.org/html/rfc3394)
- [RFC 5869 (HKDF)](https://tools.ietf.org/html/rfc5869)

---

## Workers Compatibility Checklist

These features are verified against Cloudflare Workers API surface:

- [x] `fetch()` — async, Promise-based
- [x] `crypto.subtle.digest()` — SHA-256, SHA-384, SHA-512, SHA-1
- [x] `crypto.subtle.sign()` — RSA-PSS, ECDSA, HMAC (HMAC done, expand)
- [x] `crypto.subtle.verify()` — RSA-PSS, ECDSA, HMAC (HMAC done, expand)
- [x] `crypto.subtle.generateKey()` — RSA, ECDSA, AES, HMAC
- [x] `crypto.subtle.importKey()` — JWK, PKCS8, SPKI, raw
- [x] `crypto.subtle.exportKey()` — JWK, PKCS8, SPKI, raw
- [x] `crypto.subtle.encrypt()/decrypt()` — AES-GCM, RSA-OAEP
- [x] `crypto.getRandomValues()` — Already implemented
- [x] `crypto.randomUUID()` — Already implemented
- [x] `structuredClone()` — Clone values, circular refs
- [x] `queueMicrotask()` — Schedule async work
- [x] `performance.now()` — High-resolution timer

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|-----------|-------|
| API specifications | HIGH | WHATWG, W3C standards verified |
| V8 integration | HIGH | V8 API documented, used in Node.js |
| Zig crypto libraries | HIGH | std.crypto covers all algorithms |
| Event loop integration | MEDIUM | NANO's event loop needs review for async I/O |
| Testing strategy | MEDIUM | Timing-dependent tests can be flaky |
| Workers compatibility | HIGH | Verified against official docs |

---

## Gaps & Open Questions

1. **async fetch() event loop:** How to integrate with current xev-based event loop? Requires investigation of pending I/O handling.
2. **crypto.subtle key formats:** Full JWK serialization — JSON format complexity, edge cases?
3. **structuredClone() custom serialization:** Should we support Symbol-based serialization hooks (non-standard)?
4. **performance.now() precision:** Can we guarantee microsecond precision, or document millisecond limit?
5. **crypto.subtle post-quantum:** Future-proof for ML-KEM/ML-DSA, or stick to current algorithms?

---

## Sources

### Official Documentation
- [Cloudflare Workers Runtime APIs](https://developers.cloudflare.com/workers/runtime-apis/)
- [Deno API Reference](https://docs.deno.com/api/)
- [Node.js Web Crypto API](https://nodejs.org/api/webcrypto.html)

### Web Standards
- [WHATWG Fetch Standard](https://fetch.spec.whatwg.org/)
- [W3C Web Crypto API](https://www.w3.org/TR/WebCryptoAPI/)
- [HTML Structured Clone Algorithm](https://html.spec.whatwg.org/multipage/structured-data.html)
- [HTML Microtask Queue](https://html.spec.whatwg.org/multipage/webappapis.html#queueing-a-microtask)
- [W3C High Resolution Time API](https://www.w3.org/TR/hr-time-3/)

### V8 API
- [V8 ValueSerializer](https://v8.github.io/api/head/v8-value-serializer_8h.html)
- [V8 MicrotaskQueue](https://v8docs.nodesource.com/node-12.0/db/d08/classv8_1_1_microtask_queue.html)
- [V8 Date::Now()](https://v8docs.nodesource.com/node-12.0/dd/d98/classv8_1_1_date.html)

### Implementation References
- [Node.js async fetch implementation (uses libuv)](https://github.com/nodejs/node/blob/main/lib/internal/modules/esm/loader.js)
- [Deno fetch (uses Tokio)](https://github.com/denoland/deno/blob/main/ext/fetch/lib.rs)
- [Cloudflare Workers 2025 Node.js HTTP support](https://blog.cloudflare.com/nodejs-workers-2025/)
- [ungap/structured-clone polyfill](https://github.com/ungap/structured-clone)

### Zig Crypto
- [Zig std.crypto documentation](https://ziglang.org/documentation/master/std/#std.crypto)
- [Zig std.crypto.hash](https://ziglang.org/documentation/master/std/#std.crypto.hash)

---

## Recommendation

**MVP Backlog Cleanup (3-4 weeks):**
1. Implement `queueMicrotask()` (quick, high-value)
2. Implement `performance.now()` (quick, common)
3. Implement `structuredClone()` (medium effort, standard library)
4. Expand `crypto.subtle` with RSA and ECDSA (highest impact for auth flows)

**Phase 2 (2-3 weeks after MVP):**
5. Add AES encryption to crypto.subtle
6. Add key generation/import/export

**Phase 3 (Separate architectural effort):**
7. Refactor event loop for async I/O
8. Implement `async fetch()`

This allows developers to port more Workers code to NANO immediately (MVP) while async fetch is tackled as a separate architectural project.
