---
title: Request
description: Request object API for accessing HTTP request data
sidebar:
  order: 2
  badge:
    text: WinterCG
    variant: success
---

The `Request` object represents an incoming HTTP request. It provides access to the request URL, method, headers, and body.

## Properties (Methods)

:::note[WinterCG Compliance]
NANO's Request follows the WinterCG spec where `url`, `method`, and `headers` are **methods** (not properties). Call them with parentheses: `request.url()`, not `request.url`.
:::

### url()

Returns the full request URL as a string.

```javascript
export default {
  async fetch(request) {
    const url = request.url();
    console.log("Request URL:", url);
    // Logs: "Request URL: http://localhost:3000/api/users"

    return new Response(`You requested: ${url}`);
  }
};
```

**Type:** `() => string`

**Example URL:** `"http://localhost:3000/api/users?page=1"`

### method()

Returns the HTTP method as an uppercase string.

```javascript
export default {
  async fetch(request) {
    const method = request.method();

    if (method === "POST") {
      return new Response("Creating resource...");
    } else if (method === "GET") {
      return new Response("Fetching resource...");
    } else {
      return new Response("Method not allowed", { status: 405 });
    }
  }
};
```

**Type:** `() => string`

**Values:** `"GET"`, `"POST"`, `"PUT"`, `"DELETE"`, `"PATCH"`, `"OPTIONS"`, `"HEAD"`

### headers()

Returns a [Headers](/api/headers) object containing request headers.

```javascript
export default {
  async fetch(request) {
    const headers = request.headers();
    const contentType = headers.get("content-type");
    const userAgent = headers.get("user-agent");

    return Response.json({
      contentType,
      userAgent
    });
  }
};
```

**Type:** `() => Headers`

See the [Headers API](/api/headers) documentation for available methods.

## Body Methods

Request body can be consumed **only once**. After calling one of these methods, the body is exhausted and subsequent calls will fail.

### text()

Reads the request body as text.

```javascript
export default {
  async fetch(request) {
    if (request.method() !== "POST") {
      return new Response("POST required", { status: 405 });
    }

    const body = await request.text();
    console.log("Received text:", body);

    return new Response(`Echo: ${body}`);
  }
};
```

**Type:** `() => Promise<string>`

**Note:** Limited by 64KB buffer (see [Limitations](/api/limitations#b-01-buffer-limits)).

### json()

Parses the request body as JSON. Does **not** return a Promise (synchronous).

```javascript
export default {
  async fetch(request) {
    if (request.method() !== "POST") {
      return new Response("POST required", { status: 405 });
    }

    try {
      const data = request.json();
      console.log("Received JSON:", data);

      return Response.json({
        received: data,
        type: typeof data
      });
    } catch (error) {
      return Response.json(
        { error: "Invalid JSON" },
        { status: 400 }
      );
    }
  }
};
```

**Type:** `() => any`

**Note:** Throws if body is not valid JSON. Does not return a Promise.

## Complete Example

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());
    const path = url.pathname;
    const method = request.method();

    // GET /info
    if (path === "/info" && method === "GET") {
      const headers = request.headers();

      return Response.json({
        url: request.url(),
        method: method,
        host: headers.get("host"),
        userAgent: headers.get("user-agent")
      });
    }

    // POST /echo
    if (path === "/echo" && method === "POST") {
      const contentType = request.headers().get("content-type");

      if (contentType?.includes("application/json")) {
        try {
          const data = request.json();
          return Response.json({ echo: data });
        } catch (error) {
          return Response.json(
            { error: "Invalid JSON" },
            { status: 400 }
          );
        }
      } else {
        const text = await request.text();
        return new Response(`Echo: ${text}`);
      }
    }

    return new Response("Not Found", { status: 404 });
  }
};
```

## Migration from Cloudflare Workers

If migrating from Cloudflare Workers, add parentheses to property access:

```javascript
// Cloudflare Workers
const url = request.url;
const method = request.method;
const headers = request.headers;

// NANO (WinterCG-compliant)
const url = request.url();
const method = request.method();
const headers = request.headers();
```

See [Differences from Workers](/wintercg/diffs-from-workers) for more details.

## Related APIs

- [Response](/api/response) - Creating HTTP responses
- [Headers](/api/headers) - Manipulating headers
- [URL](/api/url) - Parsing URLs
- [fetch](/api/fetch) - Making outbound requests
