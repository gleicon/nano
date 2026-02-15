# NANO Backlog Cleanup Milestone: Research Summary

**Milestone:** v1.3 — Fix Critical Limitations
**Research Date:** 2026-02-15
**Status:** Complete

## What Was Researched

Four capability gaps identified in NANO v1.2:

1. **Heap Buffer Allocation** — 64KB hardcoded limits break large operations
2. **Synchronous Fetch** — Network I/O blocks entire request; no true async
3. **Limited Crypto** — HMAC only; missing AES-GCM, RSA-PSS, ECDSA
4. **No structuredClone** — Deep cloning objects requires manual JS

## Key Findings

### 1. Heap Allocation: Use Arena Pattern (Already in Use)

**Recommendation:** Extend existing per-request arena allocator from HTTP server to all API modules.

- NANO already uses arena allocator for HTTP server requests
- Pattern proven; zero risk
- All buffer sizes can become dynamic (no hardcoded limits)
- Memory cleanup automatic (arena.deinit() at request end)

**Implementation:** Pass `allocator: *std.mem.Allocator` parameter through V8 callback contexts.

**Effort:** Low (straightforward refactoring)

---

### 2. Async Fetch: xev Event Loop + Promise Integration

**Recommendation:** Keep synchronous `fetch()` API; return Promise immediately; run I/O on xev event loop.

**Architecture:**
```
fetch() → Create Promise + PromiseResolver → Queue FetchOperation on xev
        → Return Promise (unresolved)
        → xev socket I/O runs in parallel
        → On completion, callback enters isolate, resolves Promise
        → Microtask queue drains, JS .then() handlers execute
```

**Why this approach:**
- Doesn't require async/await at language level (NANO uses explicit event loop)
- Integrates seamlessly with existing xev timer system
- Single-threaded model preserved

**Critical complexity:** V8 isolate enter/exit protocol + microtask queue flushing

**Effort:** High (most complex change; requires careful Promise/V8 interaction)

---

### 3. Crypto Expansion: Use Zig std.crypto (No External Deps)

**Recommendation:** Implement AES-GCM, RSA-PSS, ECDSA using Zig 0.15 stdlib.

**Why NOT OpenSSL:**
- 1MB+ binary bloat
- C FFI overhead
- NANO philosophy: minimal dependencies
- Zig stdlib already has battle-tested implementations (in TLS module)

**Algorithms available in Zig std.crypto:**
| Algorithm | Status | Why |
|-----------|--------|-----|
| AES-GCM | Full support | Hardware acceleration (AES-NI) |
| RSA-PSS | Verify ready, Sign requires minor impl | Used in TLS cert verification |
| ECDSA (P-256/P-384/P-521) | Full support | RFC 6979 deterministic nonce |
| HMAC-SHA256/384/512 | Already working | Keep as-is |

**Implementation:** Expose WebCrypto API on `crypto.subtle`:
```javascript
await crypto.subtle.encrypt({ name: "AES-GCM" }, key, data)
await crypto.subtle.sign({ name: "RSA-PSS" }, privateKey, data)
await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, publicKey, sig, data)
```

**Effort:** Medium (algorithm implementation straightforward; key format parsing is tedious)

---

### 4. structuredClone: V8 Serialization API Wrapper

**Recommendation:** Expose V8's native `ValueSerializer` + `ValueDeserializer` as JS global function.

**Why V8 API:**
- Handles Map/Set/typed arrays (JSON doesn't)
- Zero overhead (direct V8 internals)
- Matches web standard behavior exactly

**Implementation:** ~50 lines C++ binding code in v8-zig fork.

**Effort:** Low (simple wrapper; no algorithm complexity)

---

## Implications for Roadmap

### Phase Structure (Recommended)

**Phase 1: Foundation (Heap Allocation)**
- Per-request arena allocator passed to all API modules
- Replace all hardcoded buffer sizes
- Duration: 1-2 weeks
- Risk: Medium (touches request lifecycle)
- Why first: All other phases depend on dynamic allocation

**Phase 2: Async Fetch (Highest Risk)**
- xev socket integration
- Promise + microtask queue
- Duration: 2-3 weeks
- Risk: High (V8 callback complexity)
- Why second: Foundation must be solid first

**Phase 3: Crypto Expansion (Can Parallel with Phase 2)**
- AES-GCM, RSA-PSS, ECDSA implementation
- Duration: 1-2 weeks
- Risk: Low (isolated algorithm work)
- Why: No coupling to other phases

**Phase 4: structuredClone (Last)**
- V8 binding + JS wrapper
- Duration: 1 week
- Risk: Low (independent feature)
- Why last: Nice-to-have; doesn't block other work

### Ordering Rationale

1. **Foundation first:** Can't proceed with async I/O or large operations without dynamic allocation
2. **Async fetch second:** Most complex change; needs solid foundation + full team focus
3. **Crypto parallel:** No coupling to fetch; can distribute work
4. **structuredClone last:** Independent; polish feature after core work complete

---

## Stack Recommendations Summary

| Category | Recommendation | Why | Confidence |
|----------|-----------------|-----|------------|
| **Memory** | Arena per-request | Already used; simple pattern | HIGH |
| **Async I/O** | xev + Promise | Existing event loop; proven pattern | HIGH |
| **Fetch HTTP** | std.http.Client (async) | Already used; Zig stdlib handles async well | HIGH |
| **Crypto** | Zig std.crypto | Hardware-accelerated, no deps, battle-tested | HIGH |
| **RSA** | Zig std.crypto RSA | Verify in TLS; signing needs custom impl | MEDIUM |
| **ECDSA** | Zig std.crypto ECDSA | Full support P-256/P-384/P-521 | HIGH |
| **AES-GCM** | Zig std.crypto Aes256Gcm | Direct TLS usage; very reliable | HIGH |
| **structuredClone** | V8 ValueSerializer | Direct V8 API; no overhead | MEDIUM-HIGH |

---

## No External Dependencies Required

**Key finding:** All stack changes use existing NANO dependencies:
- Zig 0.15 (already required)
- V8 12.x (already embedded)
- libxev (already in use)
- std.crypto (Zig builtin)

**No new build.zig.zon entries needed.**

This keeps NANO's "ultra-dense" philosophy intact.

---

## What Each Phase Needs to Succeed

### Phase 1 (Heap Allocation)

**Research flags:** None (straightforward pattern)

**Before starting:** None

**During implementation:**
- [ ] Audit all API modules for hardcoded buffers
- [ ] Ensure arena allocator passed through callback context
- [ ] Test large operations (>8KB buffers)
- [ ] Valgrind for memory leaks

---

### Phase 2 (Async Fetch)

**Research flags:**
- Deep dive into V8 microtask queue flushing (see ASYNC_FETCH_ARCHITECTURE.md)
- Validate Promise resolver lifecycle with V8 garbage collection
- Test concurrent fetches under load (memory safety)

**Before starting:**
- [ ] Read "V8 Embedder API" documentation completely
- [ ] Review Node.js libuv fetch implementation (inspiration)
- [ ] Write FetchOperation + state machine in pseudocode first

**During implementation:**
- [ ] Handle DNS resolution (blocking vs async)
- [ ] Implement timeout + cancellation
- [ ] Test redirection (follow HTTP 3xx)
- [ ] Error handling (network, timeout, protocol errors)
- [ ] Microtask queue integration (when to drain)

---

### Phase 3 (Crypto Expansion)

**Research flags:**
- ASN.1 DER parsing for key import (see CRYPTO_ALGORITHMS_RESEARCH.md)
- RFC 6979 deterministic nonce availability in Zig (verify)
- Performance baseline of Zig crypto vs Node.js

**Before starting:**
- [ ] Study Zig TLS implementation for reference
- [ ] Write key import/export in pseudocode
- [ ] Create test vectors from WebCrypto spec

**During implementation:**
- [ ] Support PKCS#8 private key import
- [ ] Support X.509 public key import
- [ ] Test each algorithm (P-256, P-384, P-521 for ECDSA)
- [ ] Security: ensure constant-time comparisons
- [ ] Performance: benchmark against threshold

---

### Phase 4 (structuredClone)

**Research flags:** None (simple wrapper)

**Before starting:**
- [ ] Identify v8-zig fork contact/maintenance status
- [ ] Write C++ binding code for ValueSerializer

**During implementation:**
- [ ] Expose V8 serialization to V8 embedder context
- [ ] Register on global object
- [ ] Test circular references
- [ ] Test Map/Set preservation

---

## Known Limitations (Intentional)

| Limitation | Reason | Impact |
|-----------|--------|--------|
| No streaming request body | Buffer upfront | POST with large body must fit in memory |
| No redirect following | Manual fetch in JS | Requires user code to handle HTTP 3xx |
| DNS via OS resolver | Simplicity | No custom DNS; no DoH |
| Single HTTP connection per fetch | Simplicity | No connection pooling |
| Nonce user-provided (AES-GCM) | Security by default | User responsible for uniqueness |

---

## Success Criteria

**Phase 1 (Heap Allocation):**
- Large operations (>8KB) succeed without buffer overflow
- Memory usage stable under load
- No memory leaks (valgrind clean)

**Phase 2 (Async Fetch):**
- fetch() returns Promise immediately
- Multiple concurrent fetches run in parallel
- Network errors reject promise
- Timeout rejects promise after 30s

**Phase 3 (Crypto Expansion):**
- AES-GCM encrypt/decrypt round-trip works
- ECDSA sign/verify all curves
- RSA-PSS sign/verify (2048 + 4096 bit)
- All 3 algorithms pass WebCrypto test vector

**Phase 4 (structuredClone):**
- Deep clone of nested objects
- Clone preserves Map/Set/typed array types
- Circular references handled

---

## Confidence Assessment

| Area | Level | Notes |
|------|-------|-------|
| **Heap allocation strategy** | HIGH | Standard pattern; already in codebase |
| **xev event loop integration** | HIGH | xev mature; NANO already uses for timers |
| **Promise/microtask queue** | MEDIUM-HIGH | V8 API stable; complexity in integration details |
| **Crypto algorithms** | HIGH | Zig stdlib mature; already in TLS implementation |
| **Key import/export (DER)** | MEDIUM | ASN.1 parsing requires careful work; no Zig stdlib support |
| **V8 Serialization wrapper** | MEDIUM-HIGH | V8 API stable; requires fork modification (low-risk code) |
| **Overall milestone** | HIGH | All components use proven, existing technologies |

---

## Risk Summary

| Risk | Severity | Mitigation |
|------|----------|-----------|
| V8 isolate enter/exit protocol errors | High | Thorough code review; test under load |
| Promise resolver GC during I/O | High | Persistent handle management; valgrind testing |
| Concurrent fetch race conditions | Medium | Careful state machine; event loop is single-threaded |
| DER parsing bugs in key import | Medium | Comprehensive test vectors; manual hex tracing |
| Zig crypto performance regression | Low | Baseline before/after performance tests |

---

## Files Created

1. **STACK_BACKLOG_CLEANUP.md** — Main technology recommendations
2. **ASYNC_FETCH_ARCHITECTURE.md** — Deep dive on Promise/xev integration
3. **CRYPTO_ALGORITHMS_RESEARCH.md** — AES-GCM/RSA-PSS/ECDSA technical details
4. **BACKLOG_CLEANUP_SUMMARY.md** — This file (executive overview)

---

## Next Steps

1. **Share research with team** — Discuss phase ordering, risk mitigation
2. **Create tickets** — One per phase; link to research docs
3. **Begin Phase 1** — Heap allocation (foundation)
4. **Parallel planning** — Phase 2 (async fetch) design while Phase 1 executes
5. **Monthly review** — Reassess after each phase; adjust roadmap if needed

---

## References

**Official Documentation:**
- [Zig Standard Library](https://ziglang.org/)
- [V8 Embedder Guide](https://v8.dev/docs/embed)
- [libxev GitHub](https://github.com/mitchellh/libxev)

**Specifications:**
- [WebCrypto W3C Spec](https://w3c.github.io/webcrypto/)
- [RFC 3447 (RSA-PSS)](https://tools.ietf.org/html/rfc3447)
- [FIPS 186-4 (ECDSA)](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.186-4.pdf)

**Prior Art:**
- NANO v1.2 codebase (existing patterns)
- Node.js runtime (libuv reference)
- Cloudflare Workers (WebCrypto implementation)

---

## Questions for Review

1. **Async fetch design:** Is xev socket approach the right fit for single-threaded model?
2. **RSA signing:** Should we skip RSA-PSS signing (only support verify)?
3. **Key formats:** Support only PKCS#8/SPKI, or also raw keys?
4. **structuredClone timing:** Is Phase 4 actually needed, or nice-to-have?
5. **Performance budgets:** Any latency targets for crypto operations?

