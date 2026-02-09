---
title: Differences from Cloudflare Workers
description: Key differences between NANO and Cloudflare Workers for code migration
sidebar:
  order: 3
---

NANO aims for high compatibility with Cloudflare Workers, but there are some key differences to be aware of when migrating code. This page documents those differences and provides migration guidance.

## Primary Difference: Request Properties as Methods

The most significant difference is how Request object properties are accessed.

### NANO (WinterCG-compliant)

In NANO, `url`, `method`, and `headers` are **methods** that must be called with parentheses:

```javascript
export default {
  async fetch(request) {
    const url = request.url();         // Method call
    const method = request.method();   // Method call
    const headers = request.headers(); // Method call

    return new Response("OK");
  }
};
```

### Cloudflare Workers

In Cloudflare Workers, these are **properties** accessed without parentheses:

```javascript
export default {
  async fetch(request) {
    const url = request.url;         // Property access
    const method = request.method;   // Property access
    const headers = request.headers; // Property access

    return new Response("OK");
  }
};
```

### Why the Difference?

NANO follows a strict interpretation of the WinterCG specification where these are defined as methods. This provides clearer semantics and allows for lazy evaluation if needed in the future.

### Migration Pattern

When migrating from Cloudflare Workers to NANO, add parentheses:

```javascript
// Before (Cloudflare Workers)
const url = request.url;
const method = request.method;
const headers = request.headers;

// After (NANO)
const url = request.url();
const method = request.method();
const headers = request.headers();
```

This is a simple find-and-replace operation:

- Find: `request.url`
- Replace: `request.url()`

- Find: `request.method`
- Replace: `request.method()`

- Find: `request.headers`
- Replace: `request.headers()`

:::tip[Automated Migration]
Use a regex find-and-replace in your editor:

Find: `request\.(url|method|headers)\b(?!\()`

Replace: `request.$1()`

This adds parentheses only where they're missing.
:::

## Response Properties: Getters (No Parentheses)

Response properties are **getters** in NANO (same as Workers):

```javascript
// Both NANO and Workers
const status = response.status;      // No parentheses
const ok = response.ok;              // No parentheses
const headers = response.headers;    // No parentheses
const body = response.body;          // No parentheses
```

**No migration needed for Response properties.**

## Buffer Limitations

NANO has stricter buffer limits than Cloudflare Workers:

| Operation | NANO Limit | Workers Limit |
|-----------|------------|---------------|
| fetch() request body | 64KB | 100MB+ |
| Blob constructor | 64KB | 100MB+ |
| atob() / btoa() | 8KB | No practical limit |
| console.log() per value | 4KB | No practical limit |

### Migration Guidance

For applications handling large payloads:

**Option 1: Chunk large data**

```javascript
// Instead of one large fetch
await fetch(url, {
  method: "POST",
  body: largeData // > 64KB
});

// Chunk the upload
const chunkSize = 32768; // 32KB
for (let i = 0; i < largeData.length; i += chunkSize) {
  const chunk = largeData.slice(i, i + chunkSize);
  await fetch(url, {
    method: "POST",
    headers: {
      "Content-Range": `bytes ${i}-${i + chunk.length}`
    },
    body: chunk
  });
}
```

**Option 2: Use streaming**

```javascript
// Stream large response
const response = await fetch(url);
const reader = response.body.getReader();

while (true) {
  const { done, value } = await reader.read();
  if (done) break;
  // Process chunk (< 64KB each)
}
```

See [B-01 limitation](/api/limitations#b-01-buffer-limits) for details.

## Synchronous fetch()

NANO's `fetch()` blocks the event loop (single-threaded). Cloudflare Workers uses an async I/O model.

### Impact

```javascript
// On Workers: concurrent requests handled efficiently
// On NANO: this blocks all other requests for 5+ seconds
const response = await fetch("https://slow-api.example.com");
```

### Migration Guidance

**Add timeouts to all fetches:**

```javascript
const controller = new AbortController();
const timeoutId = setTimeout(() => controller.abort(), 3000);

try {
  const response = await fetch(url, { signal: controller.signal });
  clearTimeout(timeoutId);
  return new Response(await response.text());
} catch (error) {
  clearTimeout(timeoutId);
  return Response.json({ error: "Timeout" }, { status: 504 });
}
```

**Or use AbortSignal.timeout():**

```javascript
try {
  const response = await fetch(url, {
    signal: AbortSignal.timeout(3000)
  });
  return new Response(await response.text());
} catch (error) {
  return Response.json({ error: "Timeout" }, { status: 504 });
}
```

See [B-02 limitation](/api/limitations#b-02-synchronous-fetch) for details.

## crypto.subtle Differences

NANO supports a smaller subset of crypto.subtle than Cloudflare Workers:

| Operation | NANO | Workers |
|-----------|------|---------|
| SHA-256/384/512 digest | ✅ | ✅ |
| HMAC sign/verify | ✅ | ✅ |
| RSA sign/verify | ❌ | ✅ |
| ECDSA sign/verify | ❌ | ✅ |
| AES encrypt/decrypt | ❌ | ✅ |
| Key generation | ❌ | ✅ |

### Migration Guidance

**For JWT verification:** Use HMAC instead of RSA:

```javascript
// Workers: RSA verification
const isValid = await crypto.subtle.verify(
  { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
  publicKey,
  signature,
  data
);

// NANO: HMAC verification
const key = await crypto.subtle.importKey(
  "raw",
  new TextEncoder().encode(SECRET),
  { name: "HMAC", hash: "SHA-256" },
  false,
  ["verify"]
);

const isValid = await crypto.subtle.verify(
  "HMAC",
  key,
  signature,
  data
);
```

**For AES encryption:** Use external service or pre-encrypted data.

See [B-04 limitation](/api/limitations#b-04-crypto-subtle-limited) for details.

## Missing APIs

These Cloudflare Workers APIs are not yet implemented in NANO:

### KV Storage

```javascript
// Workers
await env.MY_KV.put("key", "value");
const value = await env.MY_KV.get("key");

// NANO: Use external storage
const response = await fetch("https://storage.example.com/kv/key", {
  method: "PUT",
  body: "value"
});
```

### Durable Objects

Not supported. Redesign application to use external state storage.

### Environment Variables

**Workers:**

```javascript
export default {
  async fetch(request, env) {
    const apiKey = env.API_KEY;
    return new Response(apiKey);
  }
};
```

**NANO:** Use per-app environment in config:

```json
{
  "apps": [{
    "hostname": "example.com",
    "path": "./app",
    "env": {
      "API_KEY": "secret-key"
    }
  }]
}
```

Access via global `process.env` (not available in v1.2, planned for v1.3).

### Cron Triggers

Not supported. Use external cron service to call NANO endpoints.

### Workers Analytics Engine

Not supported. Use external analytics service.

## Comparison Table

| Feature | Cloudflare Workers | NANO |
|---------|-------------------|------|
| **Request properties** | Property access | Method calls |
| **Response properties** | Getters | Getters (same) |
| **fetch() model** | Async I/O | Synchronous (blocking) |
| **Request body limit** | 100MB+ | 64KB |
| **crypto.subtle** | Full suite | HMAC + SHA only |
| **KV storage** | Built-in | External required |
| **Durable Objects** | Supported | Not supported |
| **Environment variables** | `env` parameter | Config file (v1.3) |
| **Cron triggers** | Supported | External required |
| **WebSocket** | Supported | Not supported |
| **HTMLRewriter** | Supported | Not supported |

## Full Migration Example

Here's a complete Cloudflare Workers example migrated to NANO:

### Before (Cloudflare Workers)

```javascript
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const method = request.method;

    // GET /api/data
    if (url.pathname === "/api/data" && method === "GET") {
      const data = await env.MY_KV.get("data");
      return Response.json({ data });
    }

    // POST /api/data
    if (url.pathname === "/api/data" && method === "POST") {
      const body = await request.json();
      await env.MY_KV.put("data", JSON.stringify(body));
      return Response.json({ success: true });
    }

    return new Response("Not Found", { status: 404 });
  }
};
```

### After (NANO)

```javascript
// In-memory storage (replace with external service for production)
const storage = new Map();

export default {
  async fetch(request) {
    const url = new URL(request.url());      // Added ()
    const method = request.method();         // Added ()

    // GET /api/data
    if (url.pathname === "/api/data" && method === "GET") {
      const data = storage.get("data") || null;
      return Response.json({ data });
    }

    // POST /api/data
    if (url.pathname === "/api/data" && method === "POST") {
      const body = request.json();
      storage.set("data", JSON.stringify(body));
      return Response.json({ success: true });
    }

    return new Response("Not Found", { status: 404 });
  }
};
```

### Changes Made

1. ✅ Added parentheses to `request.url()` and `request.method()`
2. ✅ Replaced `env.MY_KV` with in-memory Map (or external storage)
3. ✅ Removed `env` parameter (not used in NANO v1.2)

## Migration Checklist

When migrating from Cloudflare Workers to NANO:

- [ ] Add parentheses to `request.url()`, `request.method()`, `request.headers()`
- [ ] Review fetch() calls for timeouts (add AbortSignal.timeout())
- [ ] Check request body sizes (limit to <64KB or chunk)
- [ ] Replace KV storage with external storage or in-memory Map
- [ ] Remove Durable Objects (redesign if needed)
- [ ] Replace `env` parameter with config file environment
- [ ] Replace crypto.subtle RSA/AES with HMAC or external service
- [ ] Remove Workers-specific features (HTMLRewriter, cron, etc.)
- [ ] Test console.log() with large objects (may be truncated)

## Getting Help

If you encounter issues migrating from Cloudflare Workers:

1. Check the [API Reference](/api/) for NANO-specific behavior
2. Review [Known Limitations](/api/limitations) for workarounds
3. See [WinterCG Compliance](/wintercg/compliance-notes) for API support status
4. Report migration issues to the project repository

## Related Pages

- [API Reference](/api/) - Complete API documentation
- [Known Limitations](/api/limitations) - All limitations with workarounds
- [WinterCG Compliance](/wintercg/compliance-notes) - Detailed compliance status
