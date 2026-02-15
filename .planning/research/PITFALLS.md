# Domain Pitfalls: Adding Features to Zig+V8+xev Runtime

**Domain:** Zig runtime with V8 engine and libxev event loop (WinterCG-compatible server)
**Researched:** 2026-02-15
**Confidence:** MEDIUM-HIGH
**Context:** NANO project — adding async fetch, crypto.subtle, structuredClone, tee(), and heap allocation

---

## Critical Pitfalls

### Pitfall 1: Arena Allocator Lifetime Mismatch — Heap Pointers Outlive Arena

**What goes wrong:**
Memory allocated within an arena continues to be referenced by V8 handles or JavaScript objects after the arena is freed at request end. Accessing these pointers later causes use-after-free, data corruption, and crashes. Example: Storing a pointer to a heap-allocated buffer in a V8 Persistent handle, then freeing the arena at request end, leaving the handle pointing to freed memory.

**Why it happens:**
- NANO uses request-scoped ArenaAllocators that deinit after each request
- V8 Persistent handles (for callbacks, timers, promises) survive request scope
- Developer assumes arena cleanup is sufficient, forgetting that some pointers escape request scope
- No automatic tracking of pointer ownership across request/isolate boundaries
- Easy to allocate in arena for "temporary" use, then accidentally store reference

**How to avoid:**
1. **Allocator segregation:** Use arena only for request-lifetime data (response body, temporary buffers). Use persistent allocator (page_allocator or GPA) for data referenced by V8 handles or timers.
2. **Explicit ownership annotation:** Document which allocator each buffer/pointer came from. Never mix allocators in the same data structure without clear ownership semantics.
3. **Defer-free pattern:** If arena-allocated data must survive request, copy it to persistent allocator before returning:
   ```zig
   // WRONG: Returning arena-allocated string from callback
   const temp_buf = arena.alloc(u8, len) catch return;

   // CORRECT: Copy to persistent allocator
   const persistent_buf = persistent_allocator.dupe(u8, temp_buf) catch {
       js.throw(isolate, "OOM");
       return;
   };
   ```
4. **Callback data must be persistent:** Any data passed to V8 callbacks (timer handlers, Promise continuations) must use non-arena allocators
5. **Test with debug allocator:** Run with `std.heap.debug_allocator` to detect use-after-free early.

**Warning signs:**
- Segfaults or data corruption after request completion
- Crashes in microtask processing or timer callbacks
- ASAN reports "heap-use-after-free" or "attempting to free already-freed memory"
- Memory address patterns in backtraces suggest addresses from freed arena

**Phase to address:**
**Phase 1 (Heap allocation)** — Establish allocator discipline before async work adds callback complexity.

---

### Pitfall 2: Promise Resolution Out-of-Context — V8 Microtask Corruption

**What goes wrong:**
Async operations (fetch, timers) complete and attempt to resolve Promises, but the V8 isolate/context is not entered when the Promise callback executes. This causes V8 API calls to crash, or silently corrupt Promise state. Symptoms: "Isolate is not available," crashes in Promise::Resolve(), or infinite pending Promises.

**Why it happens:**
- libxev completion callbacks run asynchronously
- V8 requires explicit isolate.enter()/context.enter() before any API call
- Promise resolution happens in microtask queue, which only processes when isolate is active
- Single-threaded runtime means callbacks and request handlers interleave
- Previous NANO bug: xev timer callbacks not entering isolate+HandleScope+context → fatal crash

**How to avoid:**
1. **Always wrap completion handlers:** Every xev completion callback must establish V8 context before calling V8 API
2. **Microtask checkpoint after callbacks:** After xev event loop tick, call `isolate.performMicrotasksCheckpoint()` to process Promise resolutions
3. **Per-completion state storage:** Use userdata pointer to access isolate/app from stateless callbacks
4. **Avoid nested Promise resolution:** Don't resolve Promises from within callbacks; queue to next tick

**Warning signs:**
- "Isolate is not available" errors from V8 API calls
- V8 crashes (segfault) in Promise-related code
- Promises that never resolve (appear to hang forever)
- Stack traces showing crash inside V8_Promise or V8_Microtask

**Phase to address:**
**Phase 2 (Async fetch + timers refinement)** — Make isolate/context management a required pattern.

---

### Pitfall 3: ReadableStream.tee() Unbounded Memory Accumulation

**What goes wrong:**
When a ReadableStream is teed into two branches, if one branch reads slower than the other (or not at all), data accumulates in the slower branch's queue **without backpressure**. In a server environment, this causes memory to grow unbounded. Example: A large file is teed; one branch streams to network (fast), the other caches to disk (slow) — memory fills up.

**Why it happens:**
- WHATWG Streams spec allows tee() to buffer data from origin stream to both branches
- Origin stream only knows about faster consumer's pull rate
- If one branch has no active reader, all data accumulates in its queue
- No built-in limit or backpressure between branches
- ReadableStream.tee() is a common operation, making this easy to trigger
- Difficult to detect until memory exhaustion

**How to avoid:**
1. **Never use built-in tee() for large unbounded streams:** Replace with explicit buffering logic that respects both consumers
2. **Set explicit highWaterMark on both branches:** Reduces default buffering
3. **Monitor queue sizes at runtime:** Alert when one branch's queue exceeds threshold
4. **Document tee() limitations:** Make clear it's only safe for small or balanced-consumption streams
5. **Rate-limit or timeout slow consumers:** Cancel unread branches after N seconds

**Warning signs:**
- Memory usage grows steadily with each teed stream operation
- Process memory exceeds limits despite completed requests recycling
- One branch of teed stream is created but never consumed
- Garbage collection logs show retention of large buffers

**Phase to address:**
**Phase 3 (ReadableStream.tee() feature)** — Include backpressure in tee() or provide "safe-tee" wrapper.

---

### Pitfall 4: Timing Side-Channels in Padding Validation (AES-CBC Crypto)

**What goes wrong:**
When implementing AES-CBC decryption with padding validation, execution time leaks information about plaintext. An attacker measures response times and reconstructs plaintext byte-by-byte without knowing the key. This is the "padding oracle" attack, exploited via Lucky Thirteen (2013).

**Why it happens:**
- Crypto operations must validate padding
- Most implementations check with straightforward code with timing branches
- Microsecond-level differences accumulate across requests
- Network timing can measure these differences
- Easy oversight: padding validation often not considered cryptographically sensitive

**How to avoid:**
1. **Use AEAD modes (GCM, ChaCha20Poly1305) instead of CBC:** These authenticate ciphertext and don't require padding. This is TLS 1.3 recommendation (RFC 8446)
2. **If CBC required, use constant-time padding check:** Check ALL padding bytes in constant time, not branching on validity
3. **Document crypto.subtle.decrypt() with warnings:** Note CBC is deprecated and unsafe
4. **Test with timing analysis tools:** Use valgrind --tool=cachegrind or timing test harnesses
5. **Avoid manual crypto:** Use established libraries (libcrypto, ring, Zig's std.crypto) that are audited

**Warning signs:**
- Using AES-CBC mode in new code
- Padding validation code with branches (`if (valid) ... else ...`)
- Mixed use of CBC alongside GCM
- No documentation warning users about CBC limitations

**Phase to address:**
**Phase 4 (Expanding crypto.subtle)** — Declare crypto operations with clear CBC deprecation. Implement only GCM; CBC requires explicit opt-in with warning.

---

### Pitfall 5: structuredClone with Circular References and V8 Serialization State

**What goes wrong:**
When implementing structuredClone, circular references or non-cloneable types (functions, DOM nodes, WeakMap) can cause V8's serialization machinery to enter an inconsistent state. Subsequent clone attempts fail mysteriously, or the serializer hangs during deep traversal. Large circular structures can cause stack overflow.

**Why it happens:**
- structuredClone() must detect and handle circular references
- V8's Serializer API maintains state (visited objects, pending references)
- If state isn't reset between clones, it carries over
- Non-cloneable types must be explicitly rejected; detecting all edge cases is hard
- User code may create highly nested or pathological structures
- Easy to implement a simple version that works 90% of the time

**How to avoid:**
1. **Use V8's built-in structured clone when possible:** V8 provides safe, audited implementation
2. **Validate cloneable types upfront:** Check object graph before attempting clone to catch non-cloneable types early
3. **Reset serializer state between clones:** Or create new serializer for each clone
4. **Limit recursion depth:** Detect and prevent stack overflow from deeply nested structures (cap at ~1000 levels)
5. **Document limitations:** Make clear which types are not cloneable (functions, Symbols, WeakMap, WeakSet, DOM nodes, Proxy)
6. **Test with pathological inputs:** Circular references, huge objects, mixed cloneable/non-cloneable types

**Warning signs:**
- Clone operation hangs or times out on certain objects
- V8 crashes with "Serializer::serialize()" in stack
- Performance degrades when cloning large objects with many circular refs
- Subsequent clones fail after one pathological clone attempt
- Stack overflow (segfault with stack exhaustion) on deeply nested objects

**Phase to address:**
**Phase 5 (Adding structuredClone)** — Use V8's native implementation where available. Include extensive testing.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| **Single allocator for all request data** | Simpler code | Memory leaks when data outlives request | Never |
| **No context enter/exit in callbacks** | Slightly faster | Crashes, data corruption, Promise hangs | Never |
| **Use tee() for any stream splitting** | Fast to implement | Unbounded memory on unbalanced consumers | Only for small/balanced streams |
| **Padding validation with branches** | Matches common pattern | Timing oracle vulnerability | Never |
| **Custom structuredClone from scratch** | Full control | Edge case crashes, security issues | Only if V8 API unavailable |
| **Skip error handling in callbacks** | Shorter code | Unhandled rejections, hangs | Never |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| **Fetch + Arena Allocator** | Allocate buffer in arena, pass to callback | Copy to persistent allocator before resolving |
| **xev Timer + V8 Context** | Call V8 API without entering isolate | Always isolate.enter(); context.enter() before V8 calls |
| **Streams + Backpressure** | Ignore desiredSize from controller | Check desiredSize; pause source if negative |
| **crypto.subtle + Key Format** | Assume key format from parameter name | Validate algorithm.format matches actual key data |
| **Async/await + Event Loop** | Assume Promise resolves immediately | Remember microtasks don't run until checkpoint() called |
| **ReadableStream + Piping** | Pipe without checking return value | Always await result; handle backpressure errors |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| **Memory accumulation in tee()** | Steady growth; no GC recovery | Monitor queue sizes; cap slow consumers | >10MB streams with 2+ tee() branches |
| **Promise chaining in callbacks** | Tick count grows; CPU stuck | Resolve on next tick, not recursively | >100 chained Promises per request |
| **Allocator fragmentation** | free() accumulate; arena not freed | Use arena.deinit() properly; segregate allocators | Thousands of allocs per request |
| **Microtask queue overflow** | performMicrotasksCheckpoint() hangs | Limit pending Promises | >10K pending Promises per isolate |
| **Deep object cloning** | structuredClone() hangs; CPU 100% | Implement depth limit | Objects with >1000 nesting levels |
| **Crypto stream processing** | CPU spikes; latency jitter | Chunk crypto operations | >100MB files encrypted at once |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|-----------|
| **AES-CBC without constant-time check** | Padding oracle; plaintext recovery | Use AES-GCM; document CBC deprecated |
| **Exposing key material in errors** | Key disclosure; Cryptanalysis | Never log keys; generic error messages |
| **Trusting keys without format validation** | Wrong key; cipher mismatch; OOM | Validate algorithm.format before import |
| **Not checking verify() return value** | Unsigned data accepted; Auth bypass | Always check result explicitly |
| **Large structuredClone without limits** | DOS via memory exhaustion | Implement size/depth limits |
| **Fetch without timeout** | Hanging requests; Resource exhaustion | Always set AbortSignal.timeout() |
| **Stream data without validation** | Malformed data processed; DOS | Validate chunks before enqueue |

---

## "Looks Done But Isn't" Checklist

- [ ] **Async fetch:** AbortSignal timeout actually cancels request (test with slow network)
- [ ] **Async fetch:** Promise resolves in correct isolate/context (access response properties)
- [ ] **Async fetch:** Backpressure works (slow consumer doesn't OOM server)
- [ ] **crypto.subtle:** Key import with all formats (raw, pkcs8, spki, jwk)
- [ ] **crypto.subtle:** Error handling for invalid algorithms
- [ ] **crypto.subtle:** Constant-time comparison in verify() (timing analysis tool)
- [ ] **ReadableStream.tee():** Memory constant during 1GB tee() with 10:1 ratio
- [ ] **ReadableStream.tee():** Cancellation of one branch; other continues
- [ ] **structuredClone:** Circular references (must not hang)
- [ ] **structuredClone:** Non-cloneable types throw DataCloneError
- [ ] **structuredClone:** Deeply nested objects don't stack overflow
- [ ] **All allocations:** Debug allocator finds no use-after-free or double-free
- [ ] **All async ops:** Max iteration limit catches infinite loops
- [ ] **All Promises:** Eventually settle (test with watchdog)

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| **Arena use-after-free** | HIGH | Identify outliving data; migrate to persistent allocator; audit all callbacks |
| **Promise hanging** | HIGH | Check for missing isolate/context enter; verify microtask checkpoint; add watchdog |
| **Stream unbounded memory** | MEDIUM | Monitor queue sizes; pause if exceeds limit; replace tee() with backpressure-aware |
| **Padding oracle** | MEDIUM | Migrate from AES-CBC to GCM; implement constant-time if CBC required |
| **structuredClone crash** | MEDIUM | Add depth/size limits; reset serializer state; test pathological inputs |
| **Memory corruption** | HIGH | Use ASAN; audit allocators; implement lifecycle validation |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Arena allocator lifetime | Phase 1 | Debug allocator finds no use-after-free |
| Promise resolution context | Phase 2 | Fetch completes; Promise resolves; response access works |
| Stream.tee() unbounded memory | Phase 3 | Memory constant during 1GB tee() with 10:1 ratio; no OOM |
| Padding oracle in crypto | Phase 4 | AES-CBC deprecated; GCM default; constant-time checks |
| structuredClone edge cases | Phase 5 | Circular refs handled; non-cloneable rejected; depth limit |
| xev timer context | Phase 2 | Timers fire and update V8 state; no isolate errors |
| Fetch timeout handling | Phase 2 | AbortSignal timeout cancels; no hanging requests |
| Stream backpressure | Phase 3 | desiredSize checked; source paused when full |

---

## Critical Implementation Rules

1. **Allocator discipline is non-negotiable:** Every allocation must have an owner and clear lifetime. Document allocator choice in code.

2. **Always enter isolate before V8 API:** No exceptions. Wrap all V8 calls in isolate.enter()/context.enter() pairs. Use defer for cleanup.

3. **Microtasks must run:** After every event loop tick, call `isolate.performMicrotasksCheckpoint()`. Without this, Promises hang.

4. **Test error paths:** Ensure every callback, Promise, and stream operation has error handling. Test with invalid inputs.

5. **Use AEAD crypto, not CBC:** Default to AES-GCM. If CBC required for compatibility, document the risk and implement constant-time validation.

6. **Monitor stream queues:** Track byte size; implement backpressure. Never trust tee() for large unbounded streams.

7. **structuredClone needs limits:** Implement depth and size limits upfront. Test with pathological inputs.

---

## Sources

- [Allocators | zig.guide](https://zig.guide/standard-library/allocators/)
- [Learning Zig - Heap Memory & Allocators](https://www.openmymind.net/learning_zig/heap_memory/)
- [Be Careful When Assigning ArenaAllocators](https://www.openmymind.net/Be-Careful-When-Assigning-ArenaAllocators/)
- [How (memory) safe is zig?](https://www.scattered-thoughts.net/writing/how-safe-is-zig/)
- [Faster async functions and promises · V8](https://v8.dev/blog/fast-async)
- [Proposal: ReadableStream tee() backpressure · Issue #1235 · whatwg/streams](https://github.com/whatwg/streams/issues/1235)
- [ReadableStream: tee() method - Web APIs | MDN](https://developer.mozilla.org/en-US/docs/Web/API/ReadableStream/tee)
- [Padding oracle attack - Wikipedia](https://en.wikipedia.org/wiki/Padding_oracle_attack)
- [CBC decryption vulnerability - .NET | Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/standard/security/vulnerabilities-cbc-mode)
- [Cryptopals: Exploiting CBC Padding Oracles | NCC Group](https://www.nccgroup.com/research-blog/cryptopals-exploiting-cbc-padding-oracles/)
- [Window: structuredClone() method - Web APIs | MDN](https://developer.mozilla.org/en-US/docs/Web/API/Window/structuredClone)
- [Deep-copying in JavaScript using structuredClone | Articles | web.dev](https://web.dev/articles/structured-clone)
- [SubtleCrypto - Web APIs | MDN](https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto)
- [Web Crypto API | Node.js v25.6.1 Documentation](https://nodejs.org/api/webcrypto.html)
- [AbortSignal - Web APIs | MDN](https://developer.mozilla.org/en-US/docs/Web/API/AbortSignal)
- [Everything about the AbortSignals | Code Driven Development](https://codedrivendevelopment.com/posts/everything-about-abort-signal-timeout)
- [The Node.js Event Loop, Timers, and process.nextTick() | Node.js](https://nodejs.org/en/docs/guides/event-loop-timers-and-nexttick)
- [GitHub - mitchellh/libxev: libxev is a cross-platform, high-performance event loop](https://github.com/mitchellh/libxev)

---

*Pitfalls research for: Adding async fetch, crypto.subtle, structuredClone, tee(), and heap allocation to Zig+V8+xev runtime*
*Researched: 2026-02-15*
