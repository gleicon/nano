---
title: WinterCG Compliance
description: NANO's compliance with WinterCG (Web-interoperable Runtimes Community Group) standards
sidebar:
  order: 1
---

NANO follows the [WinterCG (Web-interoperable Runtimes Community Group)](https://wintercg.org/) specifications to ensure compatibility with other JavaScript runtimes like Cloudflare Workers, Deno, and Vercel Edge Runtime.

## What is WinterCG?

WinterCG is a community group focused on standardizing JavaScript APIs for server-side and edge runtimes. The goal is to create a common API surface so that code written for one runtime can run on another with minimal changes.

### Core Principles

- **Web-standard APIs**: Use browser-standard APIs (fetch, Request, Response, etc.) instead of Node.js-specific APIs
- **Minimal runtime surface**: Keep the global API surface small and focused
- **No Node.js compatibility layer**: Explicitly avoid Node.js APIs like `fs`, `http`, `Buffer`
- **Interoperability**: Code should be portable across compliant runtimes

## Why NANO Follows WinterCG

By following WinterCG specifications, NANO ensures:

1. **Code portability**: Workers code runs on NANO with minimal changes
2. **Standard compliance**: APIs match browser and web standards
3. **Future compatibility**: As WinterCG specs evolve, NANO can adopt new standards
4. **Developer familiarity**: Developers know these APIs from browser development

## Supported API Categories

NANO implements WinterCG APIs across these categories:

### HTTP APIs ✅

- [Request](/api/request) - HTTP request object
- [Response](/api/response) - HTTP response object
- [Headers](/api/headers) - HTTP header manipulation
- [fetch()](/api/fetch) - Outbound HTTP requests
- [URL](/api/url) - URL parsing and manipulation

### Streams APIs ✅

- [ReadableStream](/api/streams#readablestream)
- [WritableStream](/api/streams#writablestream)
- [TransformStream](/api/streams#transformstream)

### Binary Data ✅

- [Blob](/api/blob) - Binary large objects
- [File](/api/blob#file) - File objects with metadata
- [ArrayBuffer / TypedArray](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/ArrayBuffer)

### Cryptography ⚠️

- [crypto.randomUUID()](/api/crypto#cryptorandomuuid) ✅
- [crypto.getRandomValues()](/api/crypto#cryptogetrandomvalues) ✅
- [crypto.subtle.digest()](/api/crypto#cryptosubtledigest) ✅ (SHA-256, SHA-384, SHA-512)
- [crypto.subtle.sign()](/api/crypto#cryptosubtlesign) ⚠️ (HMAC only)
- [crypto.subtle.verify()](/api/crypto#cryptosubtleverify) ⚠️ (HMAC only)
- crypto.subtle.encrypt/decrypt ❌ (not yet implemented)
- crypto.subtle with RSA/ECDSA ❌ (not yet implemented)

See [crypto limitations](/api/limitations#b-04-crypto-subtle-limited).

### Encoding ✅

- [TextEncoder](/api/encoding#textencoder) - UTF-8 encoding
- [TextDecoder](/api/encoding#textdecoder) - UTF-8 decoding
- [atob()](/api/encoding#atob) - Base64 decode
- [btoa()](/api/encoding#btoa) - Base64 encode

### Timers ✅

- [setTimeout()](/api/timers#settimeout)
- [setInterval()](/api/timers#setinterval)
- [clearTimeout()](/api/timers#cleartimeout)
- [clearInterval()](/api/timers#clearinterval)

### Utilities ✅

- [console](/api/console) - Logging methods
- [AbortController](/api/abort) - Request cancellation
- [AbortSignal](/api/abort#abortsignal)

## Not Yet Implemented

These WinterCG APIs are planned for future versions:

### Planned for v1.3

- `structuredClone()` - Deep object cloning
- `queueMicrotask()` - Microtask scheduling
- `performance.now()` - High-resolution timing

### Future Considerations

- `EventTarget` / `Event` - Event system foundation
- `WebSocket` - Persistent connections
- `Cache` / `CacheStorage` - HTTP caching
- `CompressionStream` / `DecompressionStream` - Gzip/deflate

See [missing APIs limitation](/api/limitations#b-06-missing-apis) for details.

## Key Differences from Browser APIs

While NANO follows WinterCG specs, there are some intentional differences from browser implementations:

### Request Properties are Methods

NANO's Request object uses **methods** instead of properties for `url`, `method`, and `headers`:

```javascript
// NANO (WinterCG-compliant)
const url = request.url();      // Method call
const method = request.method(); // Method call
const headers = request.headers(); // Method call

// Browser (property access)
const url = request.url;        // Property
const method = request.method;   // Property
const headers = request.headers; // Property
```

This follows a strict interpretation of the WinterCG spec. Response properties (`status`, `ok`, `headers`) are **getters** (no parentheses).

See [Differences from Workers](/wintercg/diffs-from-workers) for migration guidance.

### No DOM APIs

NANO is a server-side runtime with no DOM:

- No `document`, `window`, `navigator`
- No `localStorage`, `sessionStorage`
- No `XMLHttpRequest` (use `fetch()` instead)
- No browser-specific APIs (Geolocation, Notifications, etc.)

This is consistent with all WinterCG runtimes — they're server-side only.

## Compliance Resources

- [Compliance Status](/wintercg/compliance-notes) - Detailed API support table
- [Differences from Workers](/wintercg/diffs-from-workers) - Migration guide
- [Known Limitations](/api/limitations) - Current limitations and workarounds

## External Resources

- [WinterCG Website](https://wintercg.org/)
- [WinterCG Minimum Common API Proposal](https://github.com/wintercg/proposal-common-minimum-api)
- [Cloudflare Workers Docs](https://developers.cloudflare.com/workers/)
- [Deno Runtime APIs](https://deno.land/api)
