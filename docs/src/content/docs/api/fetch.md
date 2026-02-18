---
title: fetch
description: Make outbound HTTP requests with the fetch API
sidebar:
  order: 5
  badge:
    text: WinterCG
    variant: success
---

The `fetch()` API allows you to make outbound HTTP requests from your NANO application. It follows the standard Fetch API specification.

:::tip[Non-Blocking Fetch (v1.3)]
Since v1.3, `fetch()` is fully non-blocking. Each call spawns a background worker thread for HTTP I/O while the event loop continues processing timers, other fetches, and Promise callbacks. Multiple concurrent `fetch()` calls resolve independently. See [Event Loop](/api/event-loop) for details.
:::

## Basic Usage

```javascript
export default {
  async fetch(request) {
    // Simple GET request
    const response = await fetch("https://api.example.com/data");
    const data = await response.json();

    return Response.json(data);
  }
};
```

## Signature

```typescript
fetch(url: string | URL, options?: RequestInit): Promise<Response>
```

## Parameters

### url

The URL to fetch. Can be a string or URL object.

```javascript
// String URL
const response = await fetch("https://api.example.com/users");

// URL object
const url = new URL("https://api.example.com/users");
url.searchParams.set("page", "1");
const response = await fetch(url);
```

### options

Optional configuration object with these properties:

#### method

HTTP method to use. Defaults to `"GET"`.

**Supported methods:** `GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `OPTIONS`, `HEAD`

```javascript
const response = await fetch("https://api.example.com/users", {
  method: "POST"
});
```

#### headers

Request headers as an object or Headers instance.

```javascript
const response = await fetch("https://api.example.com/data", {
  headers: {
    "Content-Type": "application/json",
    "Authorization": "Bearer token123",
    "User-Agent": "NANO/1.2"
  }
});
```

#### body

Request body for POST, PUT, PATCH requests. Can be a string, Blob, or Uint8Array.

```javascript
// JSON body
const response = await fetch("https://api.example.com/users", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ name: "Alice", email: "alice@example.com" })
});

// Plain text body
const response = await fetch("https://api.example.com/log", {
  method: "POST",
  headers: { "Content-Type": "text/plain" },
  body: "Log message here"
});
```

:::note[Large Body Support]
Since v1.3, request bodies larger than 64KB are automatically heap-allocated. There is no practical size limit for `body` strings.
:::

## Response Handling

The `fetch()` function returns a Promise that resolves to a [Response](/api/response) object.

### Check Status

```javascript
export default {
  async fetch(request) {
    const response = await fetch("https://api.example.com/data");

    if (!response.ok) {
      return Response.json(
        { error: "Upstream error", status: response.status },
        { status: 502 }
      );
    }

    const data = await response.json();
    return Response.json(data);
  }
};
```

### Read Response Body

```javascript
export default {
  async fetch(request) {
    const response = await fetch("https://api.example.com/data");

    // JSON response
    const data = await response.json();

    // Text response
    const text = await response.text();

    // Access headers
    const contentType = response.headers.get("content-type");

    return Response.json({ data, contentType });
  }
};
```

## Complete Examples

### GET Request with Query Parameters

```javascript
export default {
  async fetch(request) {
    const url = new URL("https://api.example.com/users");
    url.searchParams.set("page", "1");
    url.searchParams.set("limit", "10");

    const response = await fetch(url);
    const data = await response.json();

    return Response.json(data);
  }
};
```

### POST Request with JSON Body

```javascript
export default {
  async fetch(request) {
    const newUser = {
      name: "Alice Smith",
      email: "alice@example.com",
      role: "developer"
    };

    const response = await fetch("https://api.example.com/users", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer secret-token"
      },
      body: JSON.stringify(newUser)
    });

    if (!response.ok) {
      return Response.json(
        { error: "Failed to create user", status: response.status },
        { status: response.status }
      );
    }

    const created = await response.json();
    return Response.json(created, { status: 201 });
  }
};
```

### PUT Request to Update Resource

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());
    const userId = url.pathname.split("/").pop();

    const updates = {
      name: "Alice Johnson",
      email: "alice.j@example.com"
    };

    const response = await fetch(`https://api.example.com/users/${userId}`, {
      method: "PUT",
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer secret-token"
      },
      body: JSON.stringify(updates)
    });

    if (response.status === 404) {
      return Response.json({ error: "User not found" }, { status: 404 });
    }

    const updated = await response.json();
    return Response.json(updated);
  }
};
```

### DELETE Request

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());
    const userId = url.pathname.split("/").pop();

    const response = await fetch(`https://api.example.com/users/${userId}`, {
      method: "DELETE",
      headers: {
        "Authorization": "Bearer secret-token"
      }
    });

    if (!response.ok) {
      return Response.json(
        { error: "Failed to delete user" },
        { status: response.status }
      );
    }

    return Response.json({ success: true, deleted: userId });
  }
};
```

### Error Handling

```javascript
export default {
  async fetch(request) {
    try {
      const response = await fetch("https://api.example.com/data", {
        headers: { "User-Agent": "NANO/1.2" }
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const data = await response.json();
      return Response.json(data);

    } catch (error) {
      console.error("Fetch failed:", String(error));

      return Response.json(
        {
          error: "Failed to fetch upstream data",
          message: String(error)
        },
        { status: 502 }
      );
    }
  }
};
```

### Proxy Pattern

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());

    // Proxy to different backend based on path
    let backendUrl;
    if (url.pathname.startsWith("/api/users")) {
      backendUrl = "https://users-api.example.com" + url.pathname;
    } else if (url.pathname.startsWith("/api/products")) {
      backendUrl = "https://products-api.example.com" + url.pathname;
    } else {
      return new Response("Not Found", { status: 404 });
    }

    // Forward request
    const response = await fetch(backendUrl, {
      method: request.method(),
      headers: request.headers()
    });

    // Return upstream response
    return new Response(response.body, {
      status: response.status,
      headers: response.headers
    });
  }
};
```

### Custom Headers and Timeouts

```javascript
export default {
  async fetch(request) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 5000);

    try {
      const response = await fetch("https://api.example.com/slow", {
        headers: {
          "User-Agent": "NANO/1.2",
          "X-Request-ID": crypto.randomUUID(),
          "Accept": "application/json"
        },
        signal: controller.signal
      });

      clearTimeout(timeoutId);

      const data = await response.json();
      return Response.json(data);

    } catch (error) {
      clearTimeout(timeoutId);

      if (error.name === "AbortError") {
        return Response.json(
          { error: "Request timeout" },
          { status: 504 }
        );
      }

      throw error;
    }
  }
};
```

## Async Behavior

### Non-Blocking Execution

`fetch()` runs on a background worker thread. While the HTTP request is in flight, the event loop continues to process:
- `setTimeout` / `setInterval` callbacks
- Other concurrent `fetch()` calls
- Promise resolution chains
- WritableStream async sinks

```javascript
export default {
  async fetch(request) {
    let timerFired = false;
    setTimeout(() => { timerFired = true; }, 10);

    // Timer fires while fetch is in progress
    const resp = await fetch("https://api.example.com/slow");
    console.log(timerFired); // true
    return new Response(await resp.text());
  }
};
```

### Concurrent Fetches

Multiple `fetch()` calls run in parallel when used with `Promise.all()`:

```javascript
const [users, products] = await Promise.all([
  fetch("https://api.example.com/users"),
  fetch("https://api.example.com/products")
]);
// Both requests run concurrently on separate threads
```

### SSRF Protection

`fetch()` blocks requests to private and loopback addresses to prevent Server-Side Request Forgery:

```javascript
await fetch("http://127.0.0.1:8080/internal");    // Rejected: "BlockedHost"
await fetch("http://169.254.169.254/metadata");    // Rejected: "BlockedHost"
```

Blocked ranges: `127.0.0.0/8`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.169.254`.

### Sync Fallback

In eval/REPL mode (`nano eval`, `nano repl`), `fetch()` runs synchronously since there is no event loop. Behavior is identical but blocking.

See [Event Loop](/api/event-loop) for a detailed description of how async fetch integrates with the promise wait loop.

## Related APIs

- [Event Loop](/api/event-loop) - How async fetch integrates with timers and promises
- [Request](/api/request) - Incoming request object
- [Response](/api/response) - Response object returned by fetch
- [Headers](/api/headers) - Manipulating HTTP headers
- [AbortController](/api/abort) - Canceling fetch requests
- [URL](/api/url) - Building request URLs
