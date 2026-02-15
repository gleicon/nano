# Research Summary: NANO Backlog Cleanup Phase

**Project:** NANO (Zig+V8 runtime)
**Domain:** Async I/O, Streams, Cryptography APIs for backlog closure
**Researched:** 2026-02-15
**Overall Confidence:** HIGH (architecture traced, integration points identified, pitfalls catalogued)

---

## Executive Summary

NANO has 7 identified backlog fixes that collectively transform it from a proof-of-concept to a functional WinterCG-compliant runtime. These are not new features — they fix broken/incomplete implementations:

1. **Heap buffers** — Stack buffers (65KB) limit fetch/crypto body sizes
2. **Async fetch** — fetch() returns promises that never resolve
3. **WritableStream backpressure** — write() doesn't respect flow control
4. **crypto.subtle expansion** — Only SHA available, no AES/ECDSA
5. **ReadableStream.tee()** — Single shared queue instead of per-branch queues
6. **structuredClone** — Missing global function
7. **URL setters** — href/pathname/search read-only

**Architecture Assessment:** All 7 fixes integrate cleanly with existing single-threaded event loop design. No breaking changes. **Critical path:** Fixes #1 → #2 → #3 (26-34 hours). Fixes #4-7 are independent (21-25 hours). **Total: ~51 hours across 10 modified/new files.**

**Confidence breakdown:**
- **Architecture:** HIGH (source code hand-traced)
- **Integration points:** HIGH (all callback patterns documented)
- **Build order:** MEDIUM-HIGH (dependencies mapped, some unknown interactions)
- **Effort estimates:** MEDIUM (complexity flags identified, but no historical data)

---

## Key Findings

### Stack

| Layer | Current | Post-Backlog |
|-------|---------|--------------|
| **Async I/O** | Event loop (xev timers only) | xev timers + socket operations |
| **Memory** | Page allocator per-request | Request context with allocator + refcounting |
| **Promises** | Manual PromiseResolver creation | Systematized Promise lifecycle (timeout, GC cleanup) |
| **Cryptography** | SHA family only | SHA, AES-GCM, ECDSA (RSA deferred) |
| **Streams** | Partial (missing tee, backpressure) | Complete (tee, backpressure, all WHATWG features) |
| **URL** | Read-only properties | Full mutation support |

**No new external dependencies.** Uses existing Zig std.crypto, libxev, V8 APIs.

### Features

**Table stakes (must-have):**
- Async fetch working (currently broken)
- Stream backpressure (currently ignored)
- tee() working correctly (currently broken)
- AES/ECDSA available (SHA only now)

**Differentiators:**
- structuredClone (convenient, not strictly required)
- URL mutations (WHATWG standard, nice-to-have)

**Anti-features:**
- RSA (deferred: complex, lower priority)
- TransformStream (not on critical path)

### Architecture

**Core insight:** NANO's single-threaded, request-based architecture is well-suited to async fixes:

```
Request Lifecycle (current):
├─ Accept connection
├─ Parse HTTP
├─ handleRequest()
│  ├─ Spin event loop tick() until Promise resolves
│  └─ Extract response
└─ Send response + free allocator

Post-backlog:
├─ Accept connection
├─ Parse HTTP
├─ handleRequest()
│  ├─ PromiseResolver returned immediately
│  └─ Spin event loop ticks until resolved (or timeout)
│     ├─ Socket operations fire (fetch complete)
│     ├─ Microtasks drain (Promises resolve)
│     └─ Loop continues until Promise state != pending
├─ Send response
└─ Cleanup: timeout remaining promises, free allocator + request context
```

**New component:** Request context (wraps allocator, tracks pending operations)

**Most complex fix:** #2 (async fetch) — requires xev socket integration, HTTP parsing, Promise callback plumbing. **Estimated 16-20 hours.**

### Pitfalls

**Critical (will ship broken if not fixed):**
1. **V8 Persistent handle lifecycle** — Async callback fires after isolate destroyed → SEGFAULT
2. **Request allocator use-after-free** — Callback uses allocator after response freed → memory corruption
3. **Promise never resolved** — Promise stored in JS object, never resolved/rejected → persistent handle leak
4. **Socket queue unbounded** — Pending operations grow without limit → OOM

**Moderate (will cause production issues):**
5. Promise resolution from wrong isolate/context
6. Stream queue memory unbounded
7. Crypto key format confusion

**Minor (edge cases):**
8-10. URL protocol validation, branch deletion, redirect loops

**Mitigation strategy:** Ref-counting on request context, isolate + context tracking, operation timeouts, queue limits, cleanup callbacks.

---

## Implications for Roadmap

### Suggested Phase Structure

**Phase 1: Async Foundation (26-34 hours)**
- Fix #1: Heap buffers (request allocator context)
- Fix #2: Async fetch (socket operations)
- Fix #3: WritableStream async (Promise awareness)

*Dependencies:* #1 blocks #2; #2 informs #3

*Checkpoint:* fetch() works end-to-end, streams have backpressure

**Phase 2: Crypto & APIs (20-25 hours)**
- Fix #4: crypto.subtle expansion
- Fix #5: ReadableStream.tee()
- Fix #6: structuredClone
- Fix #7: URL setters

*Dependencies:* None (all independent)

*Checkpoint:* WinterCG spec compliance near-complete

### Why This Order

1. **Fix #1 unblocks allocator usage** in API callbacks — without it, can't implement heap buffers for #2, #4, etc.
2. **Fix #2 is most complex** — socket integration, Promise callback plumbing, event loop integration. Deserves focused effort.
3. **Fix #3 depends on Promise patterns** from #2 stabilizing.
4. **Fixes #4-7 are independent** — can parallelize or sequence arbitrarily.

### Research Flags (Phase-Specific)

| Phase | Topic | Research Needed |
|-------|-------|-----------------|
| #1-2 | xev socket integration | MEDIUM — libxev API docs needed for HTTP-over-TCP |
| #2 | HTTP parsing | MEDIUM — standard request/response format; consider std.http |
| #3 | V8 weak references | LOW — documented in V8 API |
| #4 | Zig std.crypto APIs | LOW — already used for SHA |
| #5 | Stream branch coordination | LOW — architecture clear |
| #6 | V8 serialization API | LOW — V8 provides this |
| #7 | URL re-serialization | LOW — basic string concatenation |

---

## Quality Assessment

| Area | Confidence | Justification |
|------|------------|---------------|
| **Stack** | HIGH | All dependencies verified (Zig std, libxev, V8), no unknowns |
| **Architecture** | HIGH | Source hand-traced, integration points explicit |
| **Features** | HIGH | WinterCG spec clear, scope defined |
| **Pitfalls** | MEDIUM | Identified common failure modes, but no historical NANO backlog data |
| **Effort estimates** | MEDIUM | No historical velocity, estimates based on complexity analysis |
| **Build order** | MEDIUM-HIGH | Dependencies clear, but unknown interaction effects |

---

## Gaps to Address

### Pre-Implementation Research
1. **xev socket API** — Review libxev docs for TCP connect/send/recv completion integration
2. **HTTP parsing** — Decide: std.http or minimal custom parser for HTTP 1.1
3. **Persistent handle cleanup** — Audit all V8 Persistent usages; ensure cleanup paths exist

### Phase-Specific Research
- **Phase #2:** Socket timeout strategy, backlog limits, graceful degradation design
- **Phase #3:** Backpressure flow control design, queue drain timing
- **Phase #4:** Key format parsing (raw, JWK, PEM)
- **Phase #5:** tee() specification compliance (WHATWG Streams spec)

### Unknown Unknowns
- V8 GC behavior with persistent handles under memory pressure
- xev completion callback timing (synchronous vs deferred)
- Interaction between Watchdog (timeout) and long-running socket ops
- Memory pressure on concurrent fetch operations (1000+)

---

## Roadmap Recommendations

### Immediate (Next 1-2 weeks)
- [ ] Deeper research: xev socket API, std.http capabilities
- [ ] Prototype: request context ref-counting, allocator plumbing
- [ ] Architecture review: event loop tick redesign for socket ops

### Short-term (Week 3-4)
- [ ] Implement Fix #1 (heap buffers, request context)
- [ ] Begin Fix #2 (async fetch, socket infrastructure)
- [ ] Parallel: Fix #4 (crypto expansion, independent)

### Medium-term (Week 5-8)
- [ ] Complete Fix #2 + #3 (async foundation phase)
- [ ] Verify: no performance regression, handle lifecycle correct
- [ ] Implement Fixes #5-7 in parallel

### Release (Week 9)
- [ ] Load testing: 1000 concurrent operations
- [ ] Integration testing: fetch + streams + crypto
- [ ] Release as v1.3 or v2.0 (depends on breaking change assessment)

---

## Success Criteria

### Code Quality
- [ ] All 7 fixes have ≥80% unit test coverage
- [ ] Integration tests for all fix combinations
- [ ] Load test: 1000 concurrent fetch + stream operations, no memory leak
- [ ] Static analysis: no warnings from `zig build -Doptimize=ReleaseSafe`

### Spec Compliance
- [ ] All WinterCG features tested against spec
- [ ] WHATWG Fetch, Streams, URL specs honored
- [ ] Error messages match spec (e.g., "TypeError: ...")

### Performance
- [ ] No regression in single-request latency (< 5% increase)
- [ ] Throughput improvement under load (async + backpressure)
- [ ] Memory stable after 10M requests (no leaks)

### User Experience
- [ ] Clear error messages for all failure paths
- [ ] Documentation updated for async APIs
- [ ] Example code for fetch, streams, crypto

---

## Files Created

This research produced 4 documents in `.planning/research/`:

1. **BACKLOG_ARCHITECTURE.md** (13KB)
   - Detailed integration analysis of each fix
   - Component boundaries, data flow
   - Build order rationale
   - Risks and mitigations

2. **BACKLOG_FEATURES.md** (8KB)
   - Feature landscape: table stakes vs differentiators
   - User impact of each fix
   - WinterCG spec mapping
   - Validation checklist

3. **BACKLOG_PITFALLS.md** (12KB)
   - 10 identified pitfall scenarios
   - Root cause analysis
   - Prevention strategies with code examples
   - Phase-specific warnings
   - Testing scenarios

4. **BACKLOG_SUMMARY.md** (this file)
   - Executive overview
   - Key findings synthesized
   - Roadmap recommendations
   - Quality assessment

---

## Confidence Assessment

| Area | Level | Reason | Next Steps |
|------|-------|--------|-----------|
| **Stack** | HIGH | All tech verified | Proceed |
| **Architecture** | HIGH | Patterns documented | Proceed |
| **Features** | HIGH | Spec clear | Proceed |
| **Integration** | MEDIUM | Some unknowns (xev socket details) | Research before #2 |
| **Pitfalls** | MEDIUM | Identified, but not tested | Monitor during implementation |
| **Effort** | MEDIUM | No historical NANO data | Re-estimate after week 1 |

---

## Open Questions

1. **xev socket API** — How does completion callback work? Synchronous or deferred to next event loop tick?
2. **HTTP parsing** — Use std.http or custom? Performance impact?
3. **Backpressure design** — When does write() Promise resolve? Immediately when queue < HWM, or wait for actual send?
4. **GC cleanup** — Do V8 weak references + callbacks work correctly with persistent handles?
5. **Graceful shutdown** — How to timeout pending operations when app reloads?
6. **Memory pressure** — V8 isolate callback on OOM? Can we pause socket ops?

---

## Conclusion

The NANO backlog cleanup is a **high-confidence, medium-complexity project** that transforms the runtime from proof-of-concept to production-ready.

**Strong signals:**
- Clear problem statement (fixes specific broken features)
- No breaking changes required
- Clean integration with existing architecture
- Existing tech stack (no new dependencies)

**Risk mitigations:**
- 10 common pitfalls identified with prevention strategies
- Modular build order (independent phases)
- Comprehensive testing plan

**Next step:** Proceed to Phase 1 (Fix #1) with deeper xev/HTTP research in parallel.

---

## Appendix: File Locations

All research files written to: `/Users/gleicon/code/zig/nano/.planning/research/`

- `BACKLOG_ARCHITECTURE.md` — Architecture integration details
- `BACKLOG_FEATURES.md` — Feature landscape and validation
- `BACKLOG_PITFALLS.md` — Failure modes and prevention
- `BACKLOG_SUMMARY.md` — This executive summary
