---
title: Response
description: Response object API for creating HTTP responses
sidebar:
  order: 3
  badge:
    text: WinterCG
    variant: success
---

The `Response` object represents an HTTP response. It's used to return data from your fetch handler with status codes, headers, and body content.

## Constructor

Create a new Response with a body and optional configuration.

```javascript
export default {
  async fetch(request) {
    // Text response
    return new Response("Hello, World!");

    // With status and headers
    return new Response("Not Found", {
      status: 404,
      headers: {
        "Content-Type": "text/plain",
        "X-Custom-Header": "value"
      }
    });
  }
};
```

**Signature:** `new Response(body?, options?)`

**Parameters:**
- `body` (optional): string, ReadableStream, Blob, or null
- `options` (optional):
  - `status`: HTTP status code (default: 200)
  - `statusText`: Status text (auto-generated if omitted)
  - `headers`: Object or Headers instance

## Properties (Getters)

:::note[Getter Access]
Response properties are **getters** (not methods). Access them without parentheses: `response.status`, not `response.status()`.
:::

### status

HTTP status code (200, 404, 500, etc.).

```javascript
export default {
  async fetch(request) {
    const response = new Response("OK", { status: 200 });
    console.log(response.status); // 200

    return response;
  }
};
```

**Type:** `number`

### ok

`true` if status is in the 2xx range (200-299), `false` otherwise.

```javascript
export default {
  async fetch(request) {
    const response = new Response("Created", { status: 201 });
    console.log(response.ok); // true

    const error = new Response("Not Found", { status: 404 });
    console.log(error.ok); // false

    return response;
  }
};
```

**Type:** `boolean`

### statusText

HTTP status reason phrase (e.g., "OK", "Not Found", "Internal Server Error").

```javascript
export default {
  async fetch(request) {
    const response = new Response("", { status: 404 });
    console.log(response.statusText); // "Not Found"

    return response;
  }
};
```

**Type:** `string`

**Note:** Auto-generated from status code using standard HTTP reason phrases.

### headers

Headers object for accessing response headers.

```javascript
export default {
  async fetch(request) {
    const response = new Response("OK", {
      headers: {
        "Content-Type": "text/plain",
        "X-Request-ID": crypto.randomUUID()
      }
    });

    console.log(response.headers.get("content-type")); // "text/plain"

    return response;
  }
};
```

**Type:** `Headers`

See [Headers API](/api/headers) for available methods.

### body

ReadableStream of the response body. Useful for streaming responses.

```javascript
export default {
  async fetch(request) {
    const response = new Response("Hello");

    // Access the body stream
    const stream = response.body;
    console.log(stream); // ReadableStream

    return response;
  }
};
```

**Type:** `ReadableStream | null`

See [Streams API](/api/streams) for working with streams.

## Static Methods

### Response.json()

Create a JSON response with automatic `Content-Type: application/json` header.

```javascript
export default {
  async fetch(request) {
    return Response.json({
      message: "Hello from NANO!",
      timestamp: Date.now(),
      data: { id: 1, name: "Example" }
    });
  }
};
```

**Signature:** `Response.json(data, options?)`

**Parameters:**
- `data`: Any JSON-serializable value
- `options` (optional): Same as Response constructor (`status`, `headers`)

**Example with status:**

```javascript
export default {
  async fetch(request) {
    return Response.json(
      { error: "Resource not found" },
      { status: 404 }
    );
  }
};
```

### Response.redirect()

Create an HTTP redirect response.

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());

    // Temporary redirect (302)
    if (url.pathname === "/old-path") {
      return Response.redirect("http://localhost:3000/new-path", 302);
    }

    // Permanent redirect (301)
    if (url.pathname === "/legacy") {
      return Response.redirect("http://localhost:3000/current", 301);
    }

    return new Response("OK");
  }
};
```

**Signature:** `Response.redirect(url, status?)`

**Parameters:**
- `url`: Redirect destination URL (string)
- `status` (optional): Redirect status code (default: 302)
  - `301`: Permanent redirect
  - `302`: Temporary redirect (default)
  - `307`: Temporary redirect (preserves method)
  - `308`: Permanent redirect (preserves method)

## Body Methods

### text()

Read response body as text. Returns a Promise.

```javascript
export default {
  async fetch(request) {
    const response = new Response("Hello, World!");
    const text = await response.text();
    console.log(text); // "Hello, World!"

    // Return a different response
    return Response.json({ received: text });
  }
};
```

**Type:** `() => Promise<string>`

### json()

Parse response body as JSON. Returns a Promise.

```javascript
export default {
  async fetch(request) {
    const response = Response.json({ message: "test" });
    const data = await response.json();
    console.log(data.message); // "test"

    return new Response("OK");
  }
};
```

**Type:** `() => Promise<any>`

## Complete Examples

### API with Error Handling

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());

    try {
      if (url.pathname === "/api/data") {
        const data = { items: [1, 2, 3], total: 3 };
        return Response.json(data);
      }

      if (url.pathname === "/api/error") {
        return Response.json(
          { error: "Something went wrong", code: "ERR_001" },
          { status: 500 }
        );
      }

      // 404 for unmatched routes
      return Response.json(
        { error: "Not Found", path: url.pathname },
        { status: 404 }
      );
    } catch (error) {
      return Response.json(
        { error: "Internal Server Error", message: String(error) },
        { status: 500 }
      );
    }
  }
};
```

### Custom Headers

```javascript
export default {
  async fetch(request) {
    return new Response("Success", {
      status: 200,
      headers: {
        "Content-Type": "text/plain",
        "X-Request-ID": crypto.randomUUID(),
        "X-Response-Time": String(Date.now()),
        "Cache-Control": "public, max-age=3600"
      }
    });
  }
};
```

### Streaming Response

```javascript
export default {
  async fetch(request) {
    const stream = new ReadableStream({
      start(controller) {
        controller.enqueue("Hello, ");
        controller.enqueue("streaming ");
        controller.enqueue("world!");
        controller.close();
      }
    });

    return new Response(stream, {
      headers: { "Content-Type": "text/plain" }
    });
  }
};
```

## Related APIs

- [Request](/api/request) - Handling incoming requests
- [Headers](/api/headers) - Manipulating headers
- [Streams](/api/streams) - Streaming responses
- [fetch](/api/fetch) - Making outbound requests
