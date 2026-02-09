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

| API                | Status | Notes                                         |
| ------------------ | ------ | --------------------------------------------- |
| **Request**        | ✅     | Properties via methods: `url()`, `method()`   |
| **Response**       | ✅     | Getter properties. `json()`, `redirect()`     |
| **Headers**        | ✅     | Full WHATWG spec. `append()` comma-separated   |
| **fetch()**        | ⚠️     | Synchronous (blocks event loop). See [B-02]   |
| **URL**            | ⚠️     | Read-only properties. See [B-08]              |
| **URLSearchParams**| 🔨     | Planned for v1.3                              |

## Streams APIs

| API                             | Status | Notes                                  |
| ------------------------------- | ------ | -------------------------------------- |
| **ReadableStream**              | ⚠️     | `tee()` has data loss. See [B-05]      |
| **WritableStream**              | ⚠️     | Sync sinks only. See [B-03]            |
| **TransformStream**             | ✅     | Fully functional                       |
| **ReadableStreamDefaultReader** | ✅     | Fully functional                       |
| **WritableStreamDefaultWriter** | ✅     | Fully functional                       |
| **ReadableStreamBYOBReader**    | ❌     | Not planned (low priority)             |

## Binary Data APIs

| API                          | Status | Notes                                   |
| ---------------------------- | ------ | --------------------------------------- |
| **Blob**                     | ⚠️     | 64KB constructor limit. See [B-01]      |
| **File**                     | ⚠️     | Same 64KB limit as Blob                 |
| **ArrayBuffer**              | ✅     | Fully functional                        |
| **TypedArray** (Uint8Array)  | ✅     | Fully functional                        |
| **DataView**                 | ✅     | Fully functional                        |

## Cryptography APIs

| API                            | Status | Notes                                  |
| ------------------------------ | ------ | -------------------------------------- |
| **crypto.randomUUID()**        | ✅     | Fully functional                       |
| **crypto.getRandomValues()**   | ✅     | Fully functional                       |
| **crypto.subtle.digest()**     | ✅     | SHA-256, SHA-384, SHA-512              |
| **crypto.subtle.sign()**       | ⚠️     | HMAC only. See [B-04]                  |
| **crypto.subtle.verify()**     | ⚠️     | HMAC only                              |
| **crypto.subtle.encrypt()**    | ❌     | Planned v1.3 (AES-GCM)                |
| **crypto.subtle.decrypt()**    | ❌     | Planned v1.3 (AES-GCM)                |
| **crypto.subtle.importKey()**  | ⚠️     | HMAC raw keys only                     |
| **crypto.subtle.exportKey()**  | ❌     | Not yet implemented                    |
| **crypto.subtle.generateKey()**| ❌     | Not yet implemented                    |
| **crypto.subtle.deriveKey()**  | ❌     | Not yet implemented                    |
| **crypto.subtle.deriveBits()** | ❌     | Not yet implemented                    |

## Encoding APIs

| API             | Status | Notes                                          |
| --------------- | ------ | ---------------------------------------------- |
| **TextEncoder** | ✅     | UTF-8 encoding only                            |
| **TextDecoder** | ✅     | UTF-8 decoding only                            |
| **atob()**      | ⚠️     | 8KB buffer limit. See [B-01]                   |
| **btoa()**      | ⚠️     | 8KB buffer limit. See [B-01]                   |

## Timer APIs

| API                 | Status | Notes                                      |
| ------------------- | ------ | ------------------------------------------ |
| **setTimeout()**    | ✅     | Iteration-based timing (not wall-clock)    |
| **setInterval()**   | ✅     | Iteration-based timing                     |
| **clearTimeout()**  | ✅     | Fully functional                           |
| **clearInterval()** | ✅     | Fully functional                           |

## Abort APIs

| API                      | Status | Notes                                     |
| ------------------------ | ------ | ----------------------------------------- |
| **AbortController**      | ✅     | Fully functional                          |
| **AbortSignal**          | ✅     | Fully functional                          |
| **AbortSignal.timeout()**| ✅     | Uses `Error` with `name="TimeoutError"`   |

## Console APIs

| API                                  | Status | Notes                          |
| ------------------------------------ | ------ | ------------------------------ |
| **console.log()**                    | ⚠️     | 4KB per-value limit. See [B-01]|
| **console.info()**                   | ⚠️     | Alias for log(), same limit    |
| **console.debug()**                  | ⚠️     | Alias for log(), same limit    |
| **console.warn()**                   | ⚠️     | Same 4KB limit                 |
| **console.error()**                  | ⚠️     | Same 4KB limit                 |
| **console.assert()**                 | 🔨     | Planned for v1.3               |
| **console.table()**                  | ❌     | Not planned (low priority)     |
| **console.time()** / **timeEnd()**   | 🔨     | Planned for v1.3               |

## Foundational APIs

| API                    | Status | Notes                                        |
| ---------------------- | ------ | -------------------------------------------- |
| **structuredClone()**  | 🔨     | Planned v1.3. See [B-06]                     |
| **queueMicrotask()**   | 🔨     | Planned v1.3. Use `Promise.resolve().then()` |
| **performance.now()**  | 🔨     | Planned v1.3. Use `Date.now()` workaround    |
| **DOMException**       | ❌     | Use `Error` with `.name` property            |
| **EventTarget**        | ❌     | Not yet planned                              |
| **Event**              | ❌     | Not yet planned                              |

## Storage and Caching APIs

| API              | Status | Notes                                          |
| ---------------- | ------ | ---------------------------------------------- |
| **Cache**        | ❌     | Requires storage backend                       |
| **CacheStorage** | ❌     | Not yet planned                                |

## Compression APIs

| API                     | Status | Notes                                   |
| ----------------------- | ------ | --------------------------------------- |
| **CompressionStream**   | ❌     | Requires zlib bindings                  |
| **DecompressionStream** | ❌     | Not yet planned                         |

## WebSocket APIs

| API           | Status | Notes                                          |
| ------------- | ------ | ---------------------------------------------- |
| **WebSocket** | ❌     | Requires persistent connection support         |

## Navigator APIs

| API                    | Status | Notes                                     |
| ---------------------- | ------ | ----------------------------------------- |
| **navigator**          | ❌     | Low priority for server runtime           |
| **navigator.userAgent**| ❌     | Not yet planned                           |

## Limitation References

| ID   | Summary                      | Details                                                               |
| ---- | ---------------------------- | --------------------------------------------------------------------- |
| B-01 | Stack buffer limits          | [Known Limitations](/api/limitations#b-01-stack-buffer-size-limits)    |
| B-02 | Synchronous fetch            | [Known Limitations](/api/limitations#b-02-synchronous-fetch)          |
| B-03 | WritableStream sync-only     | [Known Limitations](/api/limitations#b-03-writable-async)             |
| B-04 | crypto.subtle HMAC only      | [Known Limitations](/api/limitations#b-04-crypto-subtle-limited)      |
| B-05 | ReadableStream.tee() bug     | [Known Limitations](/api/limitations#b-05-tee-data-loss)              |
| B-06 | Missing WinterCG APIs        | [Known Limitations](/api/limitations#b-06-missing-apis)               |
| B-08 | URL read-only properties     | [Known Limitations](/api/limitations#b-08-url-read-only)              |

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
