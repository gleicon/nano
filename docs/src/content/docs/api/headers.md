---
title: Headers
description: Headers object API for manipulating HTTP headers
sidebar:
  order: 4
  badge:
    text: WinterCG
    variant: success
---

The `Headers` object provides methods for reading and manipulating HTTP request and response headers. Header names are case-insensitive.

## Constructor

Create a new Headers object, optionally initialized with header values.

```javascript
// Empty headers
const headers = new Headers();

// Initialize with object
const headers = new Headers({
  "Content-Type": "application/json",
  "X-Custom-Header": "value"
});

// Initialize from another Headers instance
const copy = new Headers(headers);
```

## Methods

### get()

Retrieve a header value by name. Returns `null` if header doesn't exist.

```javascript
export default {
  async fetch(request) {
    const headers = request.headers();
    const contentType = headers.get("content-type");
    const userAgent = headers.get("user-agent");

    console.log("Content-Type:", contentType);
    // Logs: "Content-Type: application/json" or null

    return Response.json({ contentType, userAgent });
  }
};
```

**Signature:** `get(name: string) => string | null`

**Note:** Header names are case-insensitive. `get("Content-Type")` and `get("content-type")` are equivalent.

### set()

Set a header to a value. Replaces existing value if header already exists.

```javascript
export default {
  async fetch(request) {
    const headers = new Headers();
    headers.set("Content-Type", "application/json");
    headers.set("X-Request-ID", crypto.randomUUID());

    return new Response("OK", { headers });
  }
};
```

**Signature:** `set(name: string, value: string) => void`

### has()

Check if a header exists.

```javascript
export default {
  async fetch(request) {
    const headers = request.headers();

    if (headers.has("authorization")) {
      const token = headers.get("authorization");
      // Process authenticated request
      return new Response("Authenticated");
    } else {
      return new Response("Unauthorized", { status: 401 });
    }
  }
};
```

**Signature:** `has(name: string) => boolean`

### delete()

Remove a header.

```javascript
export default {
  async fetch(request) {
    const headers = new Headers({
      "Content-Type": "text/plain",
      "X-Debug": "true"
    });

    console.log(headers.has("x-debug")); // true
    headers.delete("X-Debug");
    console.log(headers.has("x-debug")); // false

    return new Response("OK", { headers });
  }
};
```

**Signature:** `delete(name: string) => void`

**Note:** Properly removes the header from iteration (not just set to `undefined`).

### append()

Add a value to a header. For headers that support multiple values (like `Set-Cookie`), this creates a comma-separated list per WHATWG spec.

```javascript
export default {
  async fetch(request) {
    const headers = new Headers();

    // Single value
    headers.append("X-Custom", "value1");

    // Append creates comma-separated list
    headers.append("X-Custom", "value2");
    console.log(headers.get("X-Custom")); // "value1, value2"

    return new Response("OK", { headers });
  }
};
```

**Signature:** `append(name: string, value: string) => void`

**Note:** NANO uses WHATWG comma-separated format. For headers like `Set-Cookie` that don't support comma separation, use multiple `set()` calls or use a cookie library.

### entries()

Get an iterator of all headers as `[name, value]` pairs.

```javascript
export default {
  async fetch(request) {
    const headers = request.headers();
    const headerList = [];

    for (const [name, value] of headers.entries()) {
      headerList.push({ name, value });
    }

    return Response.json({ headers: headerList });
  }
};
```

**Signature:** `entries() => Iterator<[string, string]>`

### forEach()

Iterate over headers with a callback function.

```javascript
export default {
  async fetch(request) {
    const headers = request.headers();
    const headerObj = {};

    headers.forEach((value, name) => {
      headerObj[name] = value;
    });

    return Response.json({ headers: headerObj });
  }
};
```

**Signature:** `forEach(callback: (value: string, name: string) => void) => void`

## Complete Examples

### Request Header Inspection

```javascript
export default {
  async fetch(request) {
    const headers = request.headers();
    const info = {
      host: headers.get("host"),
      userAgent: headers.get("user-agent"),
      contentType: headers.get("content-type"),
      authorization: headers.has("authorization") ? "present" : "missing"
    };

    return Response.json(info);
  }
};
```

### Custom Response Headers

```javascript
export default {
  async fetch(request) {
    const headers = new Headers();
    headers.set("Content-Type", "application/json");
    headers.set("X-Request-ID", crypto.randomUUID());
    headers.set("X-Response-Time", String(Date.now()));
    headers.set("Cache-Control", "public, max-age=3600");

    // Security headers
    headers.set("X-Content-Type-Options", "nosniff");
    headers.set("X-Frame-Options", "DENY");

    const data = { message: "Hello from NANO!" };

    return new Response(JSON.stringify(data), { headers });
  }
};
```

### CORS Headers

```javascript
function corsHeaders(origin = "*") {
  const headers = new Headers();
  headers.set("Access-Control-Allow-Origin", origin);
  headers.set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
  headers.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  return headers;
}

export default {
  async fetch(request) {
    const method = request.method();

    // Handle CORS preflight
    if (method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: corsHeaders()
      });
    }

    // Regular request with CORS
    const headers = corsHeaders();
    headers.set("Content-Type", "application/json");

    return new Response(
      JSON.stringify({ message: "CORS enabled" }),
      { headers }
    );
  }
};
```

### Multi-Value Headers

```javascript
export default {
  async fetch(request) {
    const headers = new Headers();

    // WHATWG comma-separated format
    headers.append("X-Custom", "value1");
    headers.append("X-Custom", "value2");
    headers.append("X-Custom", "value3");

    console.log(headers.get("X-Custom")); // "value1, value2, value3"

    return new Response("OK", { headers });
  }
};
```

### Header Iteration

```javascript
export default {
  async fetch(request) {
    const headers = request.headers();
    const debugInfo = [];

    // Log all headers
    headers.forEach((value, name) => {
      debugInfo.push(`${name}: ${value}`);
    });

    return new Response(debugInfo.join("\n"), {
      headers: { "Content-Type": "text/plain" }
    });
  }
};
```

## Migration Notes

NANO's Headers implementation follows the WHATWG Fetch standard:

- Header names are case-insensitive
- `append()` creates comma-separated values (not separate headers)
- `delete()` properly removes headers from iteration
- All standard Headers methods are supported

## Related APIs

- [Request](/api/request) - Access request headers via `request.headers()`
- [Response](/api/response) - Set response headers
- [fetch](/api/fetch) - Add headers to outbound requests
