---
title: API Reference
description: Complete API reference for NANO's Workers-compatible runtime
sidebar:
  order: 1
---

NANO implements a Workers-compatible API surface that follows the WinterCG (Web-interoperable Runtimes Community Group) specifications. This means code written for Cloudflare Workers, Deno, or other WinterCG-compliant runtimes can run on NANO with minimal changes.

## API Organization

NANO's API is organized into these categories:

### HTTP APIs

Core APIs for handling HTTP requests and responses:

- [Request](/api/request) - Access request URL, method, headers, and body
- [Response](/api/response) - Create HTTP responses with status codes and headers
- [Headers](/api/headers) - Manipulate HTTP headers
- [fetch](/api/fetch) - Make outbound HTTP requests
- [URL](/api/url) - Parse and manipulate URLs

### Streams APIs

WinterCG-compliant streaming APIs:

- [Streams](/api/streams) - ReadableStream, WritableStream, TransformStream
- [Blob](/api/blob) - Binary data handling
- [AbortController](/api/abort) - Request cancellation

### Cryptography

Web Crypto API subset:

- [crypto](/api/crypto) - Hashing, HMAC, random values, UUIDs

### Encoding

Text and binary encoding:

- [Encoding](/api/encoding) - TextEncoder, TextDecoder, atob, btoa

### Utilities

Runtime utilities:

- [Timers](/api/timers) - setTimeout, setInterval
- [Console](/api/console) - Logging and debugging

## Known Limitations

NANO has some intentional limitations compared to full browser or Node.js environments:

- **Buffer limits**: Some APIs have stack-allocated buffer limits (detailed in each API page)
- **Synchronous fetch**: `fetch()` blocks the event loop (see [Limitations](/api/limitations))
- **Partial crypto**: Only HMAC and SHA hashing (no RSA/ECDSA/AES yet)

For a complete list of known limitations and planned fixes, see the [Limitations](/api/limitations) page.

## WinterCG Compliance

NANO follows WinterCG specifications with one notable difference:

:::note[Method vs Property Access]
NANO's Request object uses **methods** (not properties) for `url`, `method`, and `headers`:

```javascript
// NANO (WinterCG-compliant)
const url = request.url();
const method = request.method();
const headers = request.headers();

// Cloudflare Workers (property access)
const url = request.url;
const method = request.method;
const headers = request.headers;
```

This follows the WinterCG spec more strictly. Response properties (`status`, `ok`, `headers`, `body`) are **getters** (no parentheses needed).
:::

See [WinterCG Compliance](/wintercg/) for detailed compliance notes and migration guidance.

## Example Application

Here's a complete example using NANO's API:

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());
    const path = url.pathname;

    // GET /api/hello
    if (path === "/api/hello") {
      return Response.json({
        message: "Hello from NANO!",
        method: request.method(),
        timestamp: Date.now()
      });
    }

    // POST /api/hash
    if (path === "/api/hash" && request.method() === "POST") {
      const body = await request.text();
      const data = new TextEncoder().encode(body);
      const hash = await crypto.subtle.digest("SHA-256", data);

      const hashArray = new Uint8Array(hash);
      const hashHex = Array.from(hashArray)
        .map(b => b.toString(16).padStart(2, "0"))
        .join("");

      return Response.json({ input: body, sha256: hashHex });
    }

    // 404
    return new Response("Not Found", { status: 404 });
  }
};
```

## Next Steps

- Browse the API reference by category above
- Check [Known Limitations](/api/limitations) for edge cases
- See [WinterCG Compliance](/wintercg/) for portability notes
