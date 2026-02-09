---
title: WinterCG Compliance Status
description: Detailed compliance status for all WinterCG APIs in NANO
sidebar:
  order: 2
---

This page provides a detailed breakdown of NANO's compliance with WinterCG (Web-interoperable Runtimes Community Group) specifications.

## Compliance Levels

- ✅ **Fully Supported**: API implemented and compliant with WinterCG spec
- ⚠️ **Partially Supported**: API implemented but with known limitations
- 🔨 **Planned**: Not yet implemented, planned for future version
- ❌ **Not Supported**: Not planned for implementation

## HTTP and Networking APIs

| API | Status | Notes |
|-----|--------|-------|
| **Request** | ✅ | Properties accessed as methods: `url()`, `method()`, `headers()` |
| **Response** | ✅ | Properties are getters. Static methods `Response.json()`, `Response.redirect()` supported |
| **Headers** | ✅ | Full WHATWG spec compliance. `append()` uses comma-separated format |
| **fetch()** | ⚠️ | Fully functional but synchronous (blocks event loop). See [B-02 limitation](/api/limitations#b-02-synchronous-fetch) |
| **URL** | ⚠️ | Fully functional but read-only properties. See [B-08 limitation](/api/limitations#b-08-url-read-only) |
| **URLSearchParams** | 🔨 | Planned for v1.3 |

## Streams APIs

| API | Status | Notes |
|-----|--------|-------|
| **ReadableStream** | ⚠️ | Implemented but `tee()` has data loss bug. See [B-05 limitation](/api/limitations#b-05-tee-data-loss) |
| **WritableStream** | ⚠️ | Implemented but sinks must be synchronous. See [B-03 limitation](/api/limitations#b-03-writable-async) |
| **TransformStream** | ✅ | Fully functional |
| **ReadableStreamDefaultReader** | ✅ | Fully functional |
| **WritableStreamDefaultWriter** | ✅ | Fully functional |
| **ReadableStreamBYOBReader** | ❌ | Not planned (low priority) |

## Binary Data APIs

| API | Status | Notes |
|-----|--------|-------|
| **Blob** | ⚠️ | Implemented with 64KB constructor limit. See [B-01 limitation](/api/limitations#b-01-buffer-limits) |
| **File** | ⚠️ | Implemented with same 64KB limit as Blob |
| **ArrayBuffer** | ✅ | Fully functional |
| **TypedArray** (Uint8Array, etc.) | ✅ | Fully functional |
| **DataView** | ✅ | Fully functional |

## Cryptography APIs

| API | Status | Notes |
|-----|--------|-------|
| **crypto.randomUUID()** | ✅ | Fully functional |
| **crypto.getRandomValues()** | ✅ | Fully functional |
| **crypto.subtle.digest()** | ✅ | Supports SHA-256, SHA-384, SHA-512 |
| **crypto.subtle.sign()** | ⚠️ | HMAC only. No RSA-PSS or ECDSA. See [B-04 limitation](/api/limitations#b-04-crypto-subtle-limited) |
| **crypto.subtle.verify()** | ⚠️ | HMAC only. No RSA-PSS or ECDSA |
| **crypto.subtle.encrypt()** | ❌ | Not yet implemented. Planned for v1.3 (AES-GCM priority) |
| **crypto.subtle.decrypt()** | ❌ | Not yet implemented. Planned for v1.3 (AES-GCM priority) |
| **crypto.subtle.importKey()** | ⚠️ | HMAC raw keys only |
| **crypto.subtle.exportKey()** | ❌ | Not yet implemented |
| **crypto.subtle.generateKey()** | ❌ | Not yet implemented |
| **crypto.subtle.deriveKey()** | ❌ | Not yet implemented (HKDF, PBKDF2) |
| **crypto.subtle.deriveBits()** | ❌ | Not yet implemented |

## Encoding APIs

| API | Status | Notes |
|-----|--------|-------|
| **TextEncoder** | ✅ | UTF-8 encoding only |
| **TextDecoder** | ✅ | UTF-8 decoding only |
| **atob()** | ⚠️ | 8KB buffer limit. See [B-01 limitation](/api/limitations#b-01-buffer-limits) |
| **btoa()** | ⚠️ | 8KB buffer limit. See [B-01 limitation](/api/limitations#b-01-buffer-limits) |

## Timer APIs

| API | Status | Notes |
|-----|--------|-------|
| **setTimeout()** | ✅ | Iteration-based timing (not wall-clock) |
| **setInterval()** | ✅ | Iteration-based timing |
| **clearTimeout()** | ✅ | Fully functional |
| **clearInterval()** | ✅ | Fully functional |

## Abort APIs

| API | Status | Notes |
|-----|--------|-------|
| **AbortController** | ✅ | Fully functional |
| **AbortSignal** | ✅ | Fully functional |
| **AbortSignal.timeout()** | ✅ | Uses `Error` with `name="TimeoutError"` (not `DOMException`) |

## Console APIs

| API | Status | Notes |
|-----|--------|-------|
| **console.log()** | ⚠️ | 4KB per-value buffer limit. See [B-01 limitation](/api/limitations#b-01-buffer-limits) |
| **console.info()** | ⚠️ | Alias for log() with same limit |
| **console.debug()** | ⚠️ | Alias for log() with same limit |
| **console.warn()** | ⚠️ | Same 4KB limit |
| **console.error()** | ⚠️ | Same 4KB limit |
| **console.assert()** | 🔨 | Planned for v1.3 |
| **console.table()** | ❌ | Not planned (low priority) |
| **console.time()** / **console.timeEnd()** | 🔨 | Planned for v1.3 |

## Foundational APIs

| API | Status | Notes |
|-----|--------|-------|
| **structuredClone()** | 🔨 | Planned for v1.3. See [B-06 limitation](/api/limitations#b-06-missing-apis) |
| **queueMicrotask()** | 🔨 | Planned for v1.3. Use `Promise.resolve().then()` workaround |
| **performance.now()** | 🔨 | Planned for v1.3. Use `Date.now()` workaround |
| **DOMException** | ❌ | Not implemented. Use `Error` with `.name` property |
| **EventTarget** | ❌ | Not yet planned. Complex dependency |
| **Event** | ❌ | Not yet planned. Requires EventTarget |

## Storage and Caching APIs

| API | Status | Notes |
|-----|--------|-------|
| **Cache** | ❌ | Not yet planned. Requires storage backend |
| **CacheStorage** | ❌ | Not yet planned |

## Compression APIs

| API | Status | Notes |
|-----|--------|-------|
| **CompressionStream** | ❌ | Not yet planned. Requires zlib bindings |
| **DecompressionStream** | ❌ | Not yet planned |

## WebSocket APIs

| API | Status | Notes |
|-----|--------|-------|
| **WebSocket** | ❌ | Not yet planned. Requires persistent connection support |

## Navigator APIs

| API | Status | Notes |
|-----|--------|-------|
| **navigator** | ❌ | Not yet planned. Low priority for server runtime |
| **navigator.userAgent** | ❌ | Not yet planned |

## Summary by Category

### Fully Supported (✅)

16 APIs are fully WinterCG-compliant:

- Response, Headers, TransformStream
- ArrayBuffer, TypedArray, DataView
- crypto.randomUUID(), crypto.getRandomValues(), crypto.subtle.digest()
- TextEncoder, TextDecoder
- setTimeout, setInterval, clearTimeout, clearInterval
- AbortController, AbortSignal

### Partially Supported (⚠️)

11 APIs work but have known limitations:

- Request (method access pattern)
- fetch (synchronous)
- URL (read-only)
- ReadableStream (tee() bug)
- WritableStream (sync sinks only)
- Blob, File (64KB limit)
- crypto.subtle.sign/verify (HMAC only)
- atob, btoa (8KB limit)
- console.* (4KB limit)

### Planned (🔨)

5 APIs planned for v1.3:

- URLSearchParams
- structuredClone()
- queueMicrotask()
- performance.now()
- console.assert(), console.time()

### Not Supported (❌)

14 APIs not yet planned:

- ReadableStreamBYOBReader
- crypto.subtle.encrypt/decrypt/generateKey/exportKey
- console.table()
- DOMException, EventTarget, Event
- Cache, CacheStorage
- CompressionStream, DecompressionStream
- WebSocket
- navigator

## Compliance Rate

**Overall WinterCG compliance:** ~60% of common APIs

- Core HTTP/Fetch: 100%
- Streams: 80% (tee() bug + async sink limitation)
- Crypto: 40% (HMAC + hashing only, no encryption)
- Encoding: 100%
- Timers: 100%
- Utilities: 85%

## Testing Compliance

NANO's compliance is verified through:

1. **Unit tests**: Individual API behavior tests
2. **Integration tests**: Real Workers code from `test/cloudflare-worker/`
3. **UAT tests**: User acceptance scenarios in `test/apps/`

## Reporting Issues

Found a compliance issue? Please report with:

- API name and method
- Expected behavior (WinterCG spec or browser)
- Actual behavior in NANO
- Minimal reproduction code

## Related Pages

- [Known Limitations](/api/limitations) - Detailed limitation documentation
- [Differences from Workers](/wintercg/diffs-from-workers) - Migration guide
- [API Reference](/api/) - Complete API documentation
