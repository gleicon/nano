# NANO v1.3 Backlog Cleanup: Research Summary

**Project:** NANO (Zig+V8 runtime)
**Milestone:** v1.3 Backlog Cleanup
**Researched:** 2026-02-15
**Confidence:** HIGH (all fixes are known patterns from existing codebase and standard libraries)

---

## Executive Summary

NANO v1.3 backlog cleanup targets seven specific defects and missing features in the Zig+V8 runtime, spanning memory allocation, async I/O, streams, cryptography, and API completeness. All fixes are well-understood: they address stack buffer overflows (B-01), synchronous fetch blocking (B-02), async-unaware WritableStream (B-03), limited crypto.subtle (B-04), ReadableStream.tee() data loss (B-05), missing WinterCG globals (B-06), and read-only URL properties (B-08).

The recommended approach is **two-phase delivery**: Phase 1 (26-34 hours) establishes async foundation by fixing memory allocation, async fetch, and Promise-aware streams. Phase 2 (20-25 hours) completes APIs independently (crypto expansion, tee() fix, structuredClone, URL setters). Phase 1 is critical path with xev socket integration as the main complexity; Phase 2 fixes are parallelizable.

**Key risk:** Promise/isolate lifecycle management in async callbacks. NANO's current event loop enters/exits isolate correctly for timers, but fetch completion callbacks will follow the same pattern—requiring careful testing. All other fixes are additive with low integration risk.

---

## Key Findings

### Recommended Stack (No Changes)

V8 12.4+ (Node.js 22 LTS) with Zig 0.14.0 remains optimal. Research confirms:

**Core technologies:**
- **V8 12.4+** — JavaScript engine with proven isolate architecture, used in Node.js 22 LTS
- **Zig 0.14.0** — Language for binding; std.crypto provides all needed algorithms (AES, ECDSA, HMAC), no external crypto dependencies required
- **libxev** — Already integrated for event loop; capable of socket operations for async fetch

**Why unchanged:** Stack choice from v1.2 research is sound. This phase adds implementation details, not new technologies. All backlog fixes use existing infrastructure (V8 APIs, Zig stdlib, libxev).

---

### Expected Features: B-01 through B-08

**Table stakes (blocking v1.3 release):**
- **B-01: Heap buffers for large bodies** — Stack buffers (4KB URL, 8KB crypto, 64KB fetch) fail on large inputs. Fallback to heap allocation when input exceeds threshold.
- **B-02: Async fetch()** — Currently stub; blocks event loop. Requires async socket ops via xev, Promise resolution on completion.
- **B-03: WritableStream async** — write() must return Promise that resolves when queue < highWaterMark (backpressure awareness).
- **B-04: crypto.subtle expansion** — Add AES-GCM (symmetric), RSA-PSS (asymmetric sign/verify), ECDSA P-256/384/521 (signing).
- **B-05: ReadableStream.tee()** — Create independent per-branch queues; current code shares single queue causing data loss.
- **B-06: WinterCG globals** — Add structuredClone() (V8 serializer wrapper), queueMicrotask() (expose microtask queue), performance.now() (high-res timer).
- **B-08: URL setters** — Add property setters (pathname, search, hash, port, hostname) with re-serialization to href.

**Differentiators (nice-to-have, defer to v1.4):**
- RSA-PSS signing (Zig stdlib has verify but signing requires custom implementation)
- TransformStream implementation
- Connection pooling in fetch

**Anti-features:**
- Synchronous fetch() — document as unsupported
- Non-backpressured WritableStream — enforce Promise-aware write()
- CBC encryption without constant-time padding check — use AES-GCM by default

**Complexity Assessment:**
| Fix | LOC | Hours | Risk | Blocking |
|-----|-----|-------|------|----------|
| B-01 | ~200 | 4-6 | LOW | #2 depends on it |
| B-02 | ~600 | 16-20 | MEDIUM | All other async |
| B-03 | ~100 | 6-8 | MEDIUM | None |
| B-04 | ~400 | 8-10 | MEDIUM | None |
| B-05 | ~150 | 4-6 | LOW | None |
| B-06 | ~250 | 4-6 | LOW | None |
| B-08 | ~100 | 2-3 | LOW | None |
| **Total** | **~1800** | **44-59** | — | — |

---

### Architecture Approach

NANO's existing architecture cleanly accommodates all seven fixes with no structural changes. Current pattern: per-request arena allocator, persistent isolate, xev event loop, V8 callback context. Fixes extend this pattern:

**Major components to add/modify:**
1. `src/allocator_context.zig` — NEW — Request allocator helpers for B-01
2. `src/runtime/socket_ops.zig` — NEW — Async socket operation queue for B-02
3. `src/api/structured_clone.zig` — NEW — structuredClone implementation for B-06
4. `src/api/fetch.zig` — MODIFY — Async socket ops, Promise resolution for B-02
5. `src/api/writable_stream.zig` — MODIFY — Pending resolver tracking for B-03
6. `src/api/readable_stream.zig` — MODIFY — tee() with branch queues for B-05
7. `src/api/crypto.zig` — MODIFY — AES-GCM, ECDSA expansion for B-04
8. `src/api/url.zig` — MODIFY — Property setters for B-08
9. `src/runtime/event_loop.zig` — MODIFY — Socket operation queue integration for B-02
10. `src/js.zig` — MODIFY — Extend CallbackContext with allocator for B-01

**Integration detail:** B-02 (async fetch) follows the same pattern as existing timer callbacks—completion callback enters isolate/context, calls V8 API, returns. Persistent PromiseResolver handle is stored, resolved on socket completion.

---

### Critical Pitfalls

**Top 5 from Pitfalls research (and how each phase addresses them):**

1. **Arena allocator lifetime mismatch** — B-01 fixes: Use request allocator (freed after response) and defer allocations for Promise data to persistent allocator. Segregate allocators—stack/arena for request-scoped data, persistent (page_allocator) for V8 handle data.

2. **Promise resolution out-of-context** — B-02 risk: Async socket callbacks fire outside request handler. Mitigation: Every xev completion callback wraps V8 operations in `isolate.enter(); defer isolate.exit()`. Copy pattern from existing timer callbacks in `timers.zig`.

3. **ReadableStream.tee() unbounded memory** — B-05 risk: If one branch reads slowly, data accumulates without backpressure. Mitigation: Document tee() as unsafe for unbounded streams. Implement queue size monitoring in tests (verify no unbounded growth on 1GB stream with 10:1 read ratio).

4. **Timing side-channels in crypto** — B-04 risk: AES-CBC padding oracle vulnerability. Mitigation: Default to AES-GCM (AEAD, no padding). If CBC required, implement constant-time padding check. Don't expose CBC in v1.3.

5. **structuredClone with circular references** — B-06 risk: V8 Serializer state corruption on pathological inputs. Mitigation: Use V8's built-in serialization (proven). Add depth limit (max 1000 nesting levels). Test with circular objects, large objects, mixed types.

---

## Implications for Roadmap

Research suggests a **2-phase structure** with clear dependencies and parallelization:

### Phase 1: Async Foundation (26-34 hours)

**Rationale:** B-01, B-02, B-03 form critical path. B-01 provides allocator context; B-02 is most complex (socket integration); B-03 depends on Promise patterns stabilizing. Phase 1 must complete before Phase 2 APIs.

**Delivers:**
- Heap allocation fallback for large buffers (fixes B-01)
- Async fetch with real Promise resolution (fixes B-02)
- Promise-aware WritableStream backpressure (fixes B-03)

**Weekly breakdown:**
- **Week 1:** B-01 implementation (allocator context, fallback logic, tests) — 4-6 hours
- **Week 2:** B-02 Phase A (socket ops infrastructure, xev integration) — 6-8 hours
- **Week 2-3:** B-02 Phase B (fetch HTTP parsing, Promise lifecycle) — 8-12 hours
- **Week 3:** B-03 implementation (pending resolver tracking, backpressure) — 6-8 hours
- **End of Week 3:** Phase 1 checkpoint (all async tests pass, 100 concurrent fetches succeed)

**Research flags:**
- **xev socket API:** Need pre-research on libxev Tcp/socket completions to validate architecture (estimate: 4-6 hours in Week 0)
- **Promise callback lifecycle:** Validate isolate context management matches timer pattern (low risk, standard pattern)

**Standard patterns (no research):**
- Arena allocator fallback (proven pattern in Zig ecosystem)
- V8 Promise lifecycle (documented in V8 blogs)

---

### Phase 2: API Completion (20-25 hours)

**Rationale:** B-04, B-05, B-06, B-08 are independent of each other and depend only on Phase 1's async foundation. Can parallelize into two tracks.

**Delivers:**
- Crypto algorithm expansion (B-04): AES-GCM, ECDSA
- ReadableStream.tee() fix with per-branch queues (B-05)
- WinterCG essentials: structuredClone, queueMicrotask, performance.now (B-06)
- URL property setters with re-serialization (B-08)

**Track A (Crypto, 8-10 hours):**
- Expand crypto.zig with AES-GCM symmetric encryption/decryption
- Add ECDSA P-256/384/521 signing via Zig std.crypto
- Test against NIST test vectors
- Documentation: algorithm support matrix, security notes on CBC

**Track B (APIs, 12-15 hours):**
- Implement tee() with branch queue tracking (4-6h)
- Implement structuredClone via V8 Serializer (4-6h)
- Add queueMicrotask (1-2h)
- Add performance.now (1-2h)
- Add URL property setters (2-3h)

**Research flags:**
- **ECDSA key format parsing:** Minimal DER parser needed for PKCS#8/SPKI import. Zig stdlib doesn't include DER parser; may need lightweight ASN.1 decoder or raw format fallback.
- **tee() backpressure semantics:** Confirm WHATWG spec requirements for branch queue independence (low risk, well-documented)

**No research needed (standard patterns):**
- queueMicrotask: V8 API already used in app.zig
- performance.now: Simple clock arithmetic
- URL setters: Straightforward property mutation
- AES-GCM: Zig std.crypto proven in TLS implementation
- ECDSA: Zig std.crypto proven in TLS implementation

---

### Phase 3: Integration & Release (4-6 hours)

**Rationale:** After Phase 1 + 2, all code is merged. Integration testing verifies no regressions.

**Deliverables:**
- Cross-fix integration tests (e.g., fetch → tee → writable stream)
- Load test: 1000 concurrent operations
- Memory leak detection (debug allocator run)
- Documentation: examples for each new API
- Release notes: migration guide for v1.2 to v1.3

---

## Phase Ordering Rationale

1. **B-01 unblocks B-02:** Async fetch needs request allocator context to store Promise data safely.
2. **B-02 is longest:** 16-20 hours; deserves focused attention before Phase 2 parallelization.
3. **B-03 pairs with B-02:** Uses Promise resolver pattern from B-02; natural to build together.
4. **B-04, B-05, B-06, B-08 are independent:** Can split between engineers in Phase 2 once B-01-03 checkpoint passes.
5. **Phase 3 validates:** Integration testing ensures no subtle interactions between fixes.

**Why this grouping avoids pitfalls:**
- Phase 1 establishes allocator discipline (avoids Pitfall 1: arena lifetime)
- Phase 1 validates isolate context entry in callbacks (avoids Pitfall 2: Promise out-of-context)
- Phase 2 builds on stable async foundation (avoids Promise lifecycle bugs)
- Phased integration allows catch pitfalls early (avoids hidden memory leaks)

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|-----------|-------|
| **Stack** | HIGH | V8 12.4 + Zig 0.14 proven in v1.2; std.crypto algorithms verified in Zig TLS implementation |
| **Features** | HIGH | All fixes are known defects; specifications (WHATWG, WebCrypto, WinterCG) are concrete and official |
| **Architecture** | HIGH | Backlog architecture research hand-traced from current source; patterns match existing code (allocator context, Promise callbacks, event loop) |
| **Pitfalls** | MEDIUM-HIGH | Generic pitfalls (allocator lifetime, Promise context) are proven risks; crypto-specific pitfalls (timing, nonce reuse) are documented in security literature |
| **Overall** | **HIGH** | All 7 fixes are well-understood problems with clear solutions. Phase 1 is most complex (xev integration) but low-risk given existing timer pattern. |

### Gaps to Address During Implementation

1. **xev socket API details:** Research (Week 0) should confirm libxev Tcp completion callback signature and usage pattern.
2. **ECDSA key import:** ASN.1 DER parsing for PKCS#8/SPKI formats—may need lightweight parser or fallback to raw keys only.
3. **Promise isolate lifetime:** Validate that persistent PromiseResolver handles remain valid across async completion callbacks; implement timeout cleanup if needed.
4. **Stream backpressure semantics:** Confirm desiredSize behavior in tee() branches matches WHATWG spec (likely no issue, but worth validation).
5. **Crypto performance baseline:** Verify AES-GCM and ECDSA operations don't exceed fetch timeout budget (<100µs for typical operations).

---

## Sources

### Primary (HIGH confidence)
- **STACK.md** — V8 embedding, Zig integration, async I/O options; sourced from official docs (V8 embedding guide, Zig build system)
- **FEATURES.md** — WebCrypto, Fetch, Streams, WinterCG APIs; verified against WHATWG standards, MDN, official Workers/Deno docs
- **ARCHITECTURE.md** — Current NANO structure, integration patterns; hand-traced from src/ (v1.1/v1.2 codebase analysis)
- **PITFALLS.md** — Known risks in Zig+V8+xev; sourced from allocator guides, V8 blogs, proven bugs from NANO history
- **BACKLOG_BUILD_ORDER.md** — Detailed 7-fix sequence, effort estimates, weekly milestones
- **BACKLOG_ARCHITECTURE.md** — Component-level design for each fix, allocator patterns, Promise lifecycle
- **CRYPTO_ALGORITHMS_RESEARCH.md** — Zig stdlib capabilities (AES, ECDSA), WebCrypto API mapping, security considerations

### Secondary (MEDIUM confidence)
- [WHATWG Fetch Standard](https://fetch.spec.whatwg.org/) — async fetch requirements
- [W3C Web Crypto API](https://www.w3.org/TR/WebCryptoAPI/) — crypto.subtle algorithm specs
- [WHATWG Streams Standard](https://streams.spec.whatwg.org/) — ReadableStream.tee() semantics
- [Zig TLS module](https://github.com/ziglang/zig/blob/master/lib/std/crypto/tls.zig) — proof that Zig crypto algorithms work at scale

### Tertiary (documentation, needs validation)
- Lightpanda zig-js-runtime — example of Zig+V8 integration
- Deno fetch implementation — async fetch pattern reference
- Node.js WebCrypto — API surface reference

---

## Summary: Ready for Roadmap Creation

**Confidence:** All research is conclusive. NANO v1.3 backlog contains 7 well-defined fixes with known effort and clear integration points.

**Roadmap structure:** 2-phase delivery (Phase 1: 26-34h critical path, Phase 2: 20-25h parallel work, Phase 3: 4-6h integration).

**Next step:** Proceed to roadmap creation with suggested phase structure. Phase 1 should include Week 0 pre-research on xev socket API (4-6h) before implementation begins.

---

*Research completed: 2026-02-15*
*Ready for roadmap: YES*
