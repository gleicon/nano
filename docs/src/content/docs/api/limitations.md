---
title: Known Limitations
description: Known limitations and planned fixes for NANO v1.2
sidebar:
  order: 99
---

NANO v1.2 has several known limitations that were intentionally deferred during development. This page documents each limitation with workarounds and planned fixes.

All limitations are tracked in the project backlog. Most will be addressed in v1.3.

---

## B-01: Stack Buffer Limits {#b-01-buffer-limits}

**Severity:** High — silently truncates user data

**Discovered:** v1.2-04 (GA quality audit)

### Affected APIs

Multiple APIs use stack-allocated buffers with fixed size limits:

| API | Buffer | Limit | Impact |
|-----|--------|-------|--------|
| Blob constructor | `encoded_buf` | 64KB | Large blobs truncated |
| Blob.text() | `data_buf` + `decoded_buf` | 64KB each | Large blob reads fail |
| Blob.arrayBuffer() | same pattern | 64KB | Large blob reads fail |
| fetch() request body | `body_buf` | 64KB | Large POST/PUT bodies truncated |
| atob() | input + output buffers | 8KB | Large base64 decode fails |
| btoa() | input + output buffers | 8KB | Large base64 encode fails |
| console.log() | per-value buffer | 4KB | Large objects truncated |

### Examples

```javascript
// May be truncated if body > 64KB
const largeBody = "x".repeat(70000);
await fetch("https://api.example.com", {
  method: "POST",
  body: largeBody // Silently truncated to 64KB
});

// May be truncated if data > 8KB
const largeData = "x".repeat(10000);
const base64 = btoa(largeData); // Truncated to 8KB

// May be truncated if object is large
const largeObject = { data: "x".repeat(5000) };
console.log("Object:", largeObject); // May be truncated
```

### Workarounds

**For fetch:** Stream large bodies or chunk uploads:

```javascript
// Chunk large data
const chunkSize = 32768; // 32KB
for (let i = 0; i < largeData.length; i += chunkSize) {
  const chunk = largeData.slice(i, i + chunkSize);
  await fetch(url, {
    method: "POST",
    headers: { "Content-Range": `bytes ${i}-${i + chunk.length}` },
    body: chunk
  });
}
```

**For atob/btoa:** Process in chunks:

```javascript
function encodeChunks(data, chunkSize = 4096) {
  const chunks = [];
  for (let i = 0; i < data.length; i += chunkSize) {
    chunks.push(btoa(data.slice(i, i + chunkSize)));
  }
  return chunks.join("");
}
```

**For console.log:** Log specific fields:

```javascript
// Instead of logging entire large object
console.log("User:", user); // May be truncated

// Log specific fields
console.log("User ID:", user.id);
console.log("User name:", user.name);
```

### Planned Fix

Replace stack buffers with heap allocation using `allocator.alloc()`. For hot-path APIs (Blob, fetch), consider pooled buffers or configurable max size.

**Target:** v1.3 TBD

---

## B-02: Synchronous fetch() Blocks Event Loop {#b-02-synchronous-fetch}

**Severity:** High — single slow fetch stalls entire server

**Discovered:** v1.0 (by design for MVP)

### Current Behavior

`fetch()` makes blocking TCP connections using `std.net.tcpConnectToHost`. Since NANO is single-threaded, during a fetch **no other requests can be accepted**.

```javascript
export default {
  async fetch(request) {
    // This blocks the entire server for 10+ seconds
    const response = await fetch("https://very-slow-api.com/data");

    // No other requests can be processed during the wait
    return new Response(await response.text());
  }
};
```

### Impact

- Single slow upstream API blocks all client requests
- Cascading failures if upstream is down
- Poor throughput under concurrent load

### Workarounds

**Keep fetch fast:** Only fetch from fast APIs (<1 second response time):

```javascript
const controller = new AbortController();
setTimeout(() => controller.abort(), 1000);

try {
  const response = await fetch(url, {
    signal: controller.signal
  });
  return new Response(await response.text());
} catch (error) {
  return Response.json({ error: "Timeout" }, { status: 504 });
}
```

**Use reverse proxy:** Place NANO behind Nginx/Caddy with request queuing to buffer slow upstream responses.

**Cache aggressively:** Avoid repeated fetches:

```javascript
const cache = new Map();

export default {
  async fetch(request) {
    const cacheKey = "api-data";

    if (cache.has(cacheKey)) {
      return Response.json(cache.get(cacheKey));
    }

    const response = await fetch("https://api.example.com/data");
    const data = await response.json();

    cache.set(cacheKey, data);
    setTimeout(() => cache.delete(cacheKey), 60000); // 1 min TTL

    return Response.json(data);
  }
};
```

### Planned Fix

Async HTTP client integrated with xev event loop. Options:

1. Non-blocking HTTP client using xev sockets + completion callbacks
2. Thread pool for fetch operations (simpler but adds concurrency)
3. Connection pooling with keep-alive

**Target:** v1.3 TBD

---

## B-03: WritableStream Sync-Only Sinks {#b-03-writable-async}

**Severity:** Medium — async write sinks don't work correctly

**Discovered:** v1.2-02 (Streams Foundation)

### Current Behavior

The `write()` sink callback is called synchronously. If it returns a Promise, NANO doesn't await it — the write completes immediately and the next write begins.

```javascript
const stream = new WritableStream({
  async write(chunk) {
    await database.insert(chunk); // NOT awaited by NANO
    // Next write starts immediately
  }
});

const writer = stream.getWriter();
await writer.write("chunk1");
await writer.write("chunk2");
// Both writes may execute in parallel, corrupting data
```

### Impact

- Database writes may overlap and corrupt data
- File writes may interleave incorrectly
- Any async sink operation is unreliable

### Workarounds

**Use synchronous sinks:** Only perform sync operations in write():

```javascript
const buffer = [];

const stream = new WritableStream({
  write(chunk) {
    buffer.push(chunk); // Sync operation only
  },
  close() {
    // Process buffer after stream closes
    processBuffer(buffer);
  }
});
```

**Implement manual queue:** Queue writes yourself:

```javascript
const queue = [];
let processing = false;

async function processQueue() {
  if (processing) return;
  processing = true;

  while (queue.length > 0) {
    const chunk = queue.shift();
    await database.insert(chunk); // Now properly awaited
  }

  processing = false;
}

const stream = new WritableStream({
  write(chunk) {
    queue.push(chunk);
    processQueue(); // Don't await
  }
});
```

### Planned Fix

Promise-aware write queue in `src/api/writable_stream.zig:577`. After calling `write_fn.call()`, check if result is a Promise. If so, attach `.then()` callback that processes next queued write.

**Target:** v1.3 TBD

---

## B-04: crypto.subtle Limited to HMAC {#b-04-crypto-subtle-limited}

**Severity:** Medium — many real-world apps need RSA/ECDSA/AES

**Discovered:** v1.0 (by design for MVP)

### Supported

- ✅ Hashing: SHA-256, SHA-384, SHA-512
- ✅ HMAC: Sign and verify with SHA hashes
- ✅ Random: crypto.randomUUID(), crypto.getRandomValues()

### Not Supported

- ❌ RSA: sign, verify, encrypt, decrypt (RSA-PSS, RSA-OAEP)
- ❌ ECDSA: sign, verify (P-256, P-384, P-521)
- ❌ AES: encrypt, decrypt (AES-GCM, AES-CBC)
- ❌ Key derivation: HKDF, PBKDF2
- ❌ ECDH: deriveKey, deriveBits
- ❌ Key management: generateKey, importKey, exportKey (partial support for HMAC only)

### Examples

```javascript
// ✅ Works - SHA-256 hash
const hash = await crypto.subtle.digest("SHA-256", data);

// ✅ Works - HMAC sign
const signature = await crypto.subtle.sign("HMAC", key, data);

// ❌ Not supported - RSA sign
const rsaSignature = await crypto.subtle.sign("RSA-PSS", key, data);
// Error: Algorithm not supported

// ❌ Not supported - AES encrypt
const encrypted = await crypto.subtle.encrypt("AES-GCM", key, data);
// Error: Algorithm not supported
```

### Workarounds

**Use external service:** Offload crypto operations to external service:

```javascript
export default {
  async fetch(request) {
    const data = await request.text();

    // Use external crypto service
    const response = await fetch("https://crypto-service.example.com/encrypt", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ algorithm: "AES-GCM", data })
    });

    const { encrypted } = await response.json();
    return Response.json({ encrypted });
  }
};
```

**Pre-compute keys:** Generate keys offline and import as HMAC secrets:

```javascript
// Generate RSA key offline, use signature verification only
const knownGoodSignature = "..."; // From offline tool

export default {
  async fetch(request) {
    const body = await request.text();

    // Use HMAC instead of RSA for verification
    const hmacKey = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(SECRET),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"]
    );

    // Verify with HMAC instead of RSA
    const isValid = await crypto.subtle.verify("HMAC", hmacKey, signature, body);
    return Response.json({ valid: isValid });
  }
};
```

### Planned Fix

Incremental crypto expansion using OpenSSL/BoringSSL bindings or Zig's `std.crypto`:

**Priority:**
1. AES-GCM (encrypt/decrypt) — most common need
2. RSA-PSS (sign/verify) — JWT verification
3. ECDSA (sign/verify) — modern signatures
4. Key import/export

**Target:** v1.3 TBD

---

## B-05: ReadableStream.tee() Data Loss {#b-05-tee-data-loss}

**Severity:** Medium — tee() is part of Streams spec, used by frameworks

**Discovered:** v1.2-02 (Streams Foundation)

### Current Behavior

Both tee() branches share a single reader. Each chunk goes to only one branch (whichever reads first), causing data loss in the other.

```javascript
const stream = new ReadableStream({
  start(controller) {
    controller.enqueue("chunk1");
    controller.enqueue("chunk2");
    controller.enqueue("chunk3");
    controller.close();
  }
});

const [branch1, branch2] = stream.tee();

const reader1 = branch1.getReader();
const reader2 = branch2.getReader();

const { value: value1 } = await reader1.read(); // Gets "chunk1"
const { value: value2 } = await reader2.read(); // Gets "chunk2" (not "chunk1"!)
// Data loss - branch2 never sees chunk1
```

### Impact

- Frameworks using tee() for logging/metrics get incomplete data
- Response cloning may lose data
- Any multi-consumer pattern broken

### Workarounds

**Read once, create two new streams:**

```javascript
// Read entire stream into array
const reader = stream.getReader();
const chunks = [];
while (true) {
  const { done, value } = await reader.read();
  if (done) break;
  chunks.push(value);
}
reader.releaseLock();

// Create two new streams from buffered data
const branch1 = new ReadableStream({
  start(controller) {
    chunks.forEach(chunk => controller.enqueue(chunk));
    controller.close();
  }
});

const branch2 = new ReadableStream({
  start(controller) {
    chunks.forEach(chunk => controller.enqueue(chunk));
    controller.close();
  }
});
```

**Avoid tee():** Restructure code to read stream once.

### Planned Fix

Spec-compliant branch queuing in `src/api/readable_stream.zig:237-283`. Implement internal queue per branch. When source stream produces chunk, copy it into both branch queues. Each branch reads independently from its own queue.

**Target:** v1.3 TBD

---

## B-06: Missing Foundational WinterCG APIs {#b-06-missing-apis}

**Severity:** Low-Medium — needed for framework compatibility, not basic apps

**Discovered:** v1.2-04 (GA quality audit)

### Not Implemented

| API | Priority | Use Case |
|-----|----------|----------|
| `structuredClone()` | Medium | Deep copy objects (used by many frameworks) |
| `queueMicrotask()` | Medium | Promise polyfills and framework internals |
| `performance.now()` | Medium | Timing and profiling |
| `DOMException` | Low | `Error` with `.name` works for most cases |
| `EventTarget` / `Event` | Low | Foundation for addEventListener pattern |
| `navigator` object | Low | `navigator.userAgent` for feature detection |
| `WebSocket` | Low | Requires persistent connection support |
| `Cache` / `CacheStorage` | Low | Requires storage backend |
| `CompressionStream` / `DecompressionStream` | Low | Requires zlib bindings |

### Workarounds

**structuredClone:** Use JSON round-trip for simple objects:

```javascript
// Poor man's structuredClone
function clone(obj) {
  return JSON.parse(JSON.stringify(obj));
}
```

**queueMicrotask:** Use Promise.resolve():

```javascript
// Instead of queueMicrotask(fn)
Promise.resolve().then(fn);
```

**performance.now:** Use Date.now():

```javascript
// Instead of performance.now()
const start = Date.now();
// ... operation ...
const duration = Date.now() - start;
```

### Planned Fix

Prioritize as "WinterCG Essentials" phase in v1.3:
- `structuredClone()`
- `queueMicrotask()`
- `performance.now()`

EventTarget/WebSocket/Cache are larger features for later milestones.

**Target:** v1.3 TBD

---

## B-07: Single-Threaded Server {#b-07-single-threaded}

**Severity:** Low (for current use case) — limits throughput under concurrent load

**Discovered:** v1.0 (by design for MVP)

### Current Behavior

One blocking accept loop handles all connections sequentially. Under concurrent load, requests queue behind each other.

### Impact

- Limited throughput (one request at a time)
- CPU-bound requests block I/O
- Can't utilize multi-core CPUs

### Workarounds

**Horizontal scaling:** Run multiple NANO processes behind load balancer:

```bash
# Start 4 NANO processes on different ports
./nano serve --config config.json --port 3000 &
./nano serve --config config.json --port 3001 &
./nano serve --config config.json --port 3002 &
./nano serve --config config.json --port 3003 &

# Use Nginx to load balance
upstream nano {
  server 127.0.0.1:3000;
  server 127.0.0.1:3001;
  server 127.0.0.1:3002;
  server 127.0.0.1:3003;
}
```

**Keep handlers fast:** Offload heavy work to external services.

### Planned Fix

Options:
1. Thread pool: spawn N worker threads, each with own V8 isolate
2. Multi-process: fork N processes sharing listening socket
3. Fully async I/O: convert to async with xev for accept + read + write

**Target:** v1.4+

---

## B-08: URL Properties Are Read-Only {#b-08-url-read-only}

**Severity:** Low — most Workers code only reads URL properties

**Discovered:** v1.2-04 (GA quality audit)

### Current Behavior

URL has getters but no setters. Assignment like `url.pathname = "/new"` silently does nothing.

```javascript
const url = new URL("https://example.com/old");
url.pathname = "/new"; // No effect
console.log(url.pathname); // Still "/old"
```

### Impact

- Can't modify URLs after construction
- Must rebuild URLs from scratch

### Workarounds

**Build new URL strings manually:**

```javascript
// Instead of modifying url.pathname
const oldUrl = new URL("https://example.com/old");
const newUrl = new URL("https://example.com/new");

// Or construct from parts
const newUrl = new URL(`${url.protocol}//${url.host}/new-path${url.search}`);
```

### Planned Fix

Add `setAccessorSetter()` for mutable properties (pathname, search, hash, etc.) that re-serialize URL string.

**Target:** v1.3 TBD

---

## Summary Table

| ID | Summary | Severity | Workaround | Target |
|----|---------|----------|------------|--------|
| B-01 | Buffer limits | High | Chunking | v1.3 |
| B-02 | Sync fetch | High | Timeouts + cache | v1.3 |
| B-03 | Async WritableStream | Medium | Sync sinks only | v1.3 |
| B-04 | Limited crypto | Medium | External service | v1.3 |
| B-05 | tee() data loss | Medium | Read + recreate | v1.3 |
| B-06 | Missing APIs | Low-Medium | Polyfills | v1.3 |
| B-07 | Single-threaded | Low | Multi-process | v1.4+ |
| B-08 | URL read-only | Low | Rebuild URLs | v1.3 |

---

## Reporting New Issues

Found a limitation not listed here? Please report it with:

1. Minimal reproduction case
2. Expected vs actual behavior
3. Impact on your use case
4. Proposed workaround (if any)

See the project repository for issue tracking.
