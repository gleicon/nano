---
title: URL
description: Parse and manipulate URLs with the URL API
sidebar:
  order: 6
  badge:
    text: WinterCG
    variant: success
---

The `URL` object provides methods for parsing and manipulating URLs. It follows the WHATWG URL standard.

## Constructor

Create a new URL object from a string.

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());
    console.log("Pathname:", url.pathname);
    console.log("Search:", url.search);

    return Response.json({
      pathname: url.pathname,
      search: url.search
    });
  }
};
```

**Signature:** `new URL(urlString: string)`

## Properties (Getters)

All URL properties are **getters** (access without parentheses).

:::note[Read-Only Properties]
URL properties are currently read-only in NANO. Assignment like `url.pathname = "/new"` will silently do nothing. See [B-08 limitation](/api/limitations#b-08-url-read-only).
:::

### href

The complete URL as a string.

```javascript
const url = new URL("https://example.com/api/users?page=1");
console.log(url.href); // "https://example.com/api/users?page=1"
```

**Type:** `string`

### origin

The origin (protocol + host) of the URL.

```javascript
const url = new URL("https://example.com:8080/api/users");
console.log(url.origin); // "https://example.com:8080"
```

**Type:** `string`

### protocol

The protocol scheme including the trailing colon.

```javascript
const url = new URL("https://example.com/path");
console.log(url.protocol); // "https:"
```

**Type:** `string` (includes colon: `"https:"`, `"http:"`)

### host

The host including port (if non-default).

```javascript
const url = new URL("https://example.com:8080/path");
console.log(url.host); // "example.com:8080"
```

**Type:** `string`

### hostname

The hostname without port.

```javascript
const url = new URL("https://example.com:8080/path");
console.log(url.hostname); // "example.com"
```

**Type:** `string`

### port

The port number as a string. Empty string for default ports (80, 443).

```javascript
const url = new URL("https://example.com:8080/path");
console.log(url.port); // "8080"

const defaultPort = new URL("https://example.com/path");
console.log(defaultPort.port); // ""
```

**Type:** `string`

### pathname

The path portion of the URL, starting with `/`.

```javascript
const url = new URL("https://example.com/api/users/123");
console.log(url.pathname); // "/api/users/123"
```

**Type:** `string`

### search

The query string including the leading `?`.

```javascript
const url = new URL("https://example.com/api?page=1&limit=10");
console.log(url.search); // "?page=1&limit=10"
```

**Type:** `string` (includes `?` prefix, or empty string if no query)

### hash

The fragment identifier including the leading `#`.

```javascript
const url = new URL("https://example.com/page#section");
console.log(url.hash); // "#section"
```

**Type:** `string` (includes `#` prefix, or empty string if no fragment)

## Methods

### toString()

Returns the complete URL as a string. Same as `href`.

```javascript
const url = new URL("https://example.com/api/users");
console.log(url.toString()); // "https://example.com/api/users"
```

**Type:** `() => string`

## Complete Examples

### Parse Request URL

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());

    return Response.json({
      protocol: url.protocol,
      host: url.host,
      pathname: url.pathname,
      search: url.search,
      hash: url.hash
    });
  }
};
```

### Route by Pathname

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());
    const path = url.pathname;

    if (path === "/") {
      return new Response("Home page");
    } else if (path === "/api/users") {
      return Response.json({ users: [] });
    } else if (path.startsWith("/api/")) {
      return Response.json({ error: "API endpoint not found" }, { status: 404 });
    } else {
      return new Response("Not Found", { status: 404 });
    }
  }
};
```

### Parse Query Parameters

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());
    const search = url.search;

    // Manual query parsing (URLSearchParams not yet implemented)
    const params = {};
    if (search) {
      const pairs = search.slice(1).split("&");
      for (const pair of pairs) {
        const [key, value] = pair.split("=");
        params[decodeURIComponent(key)] = decodeURIComponent(value || "");
      }
    }

    return Response.json({
      pathname: url.pathname,
      params: params
    });
  }
};
```

### Extract Path Segments

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());
    const segments = url.pathname.split("/").filter(Boolean);

    // GET /api/users/123 -> ["api", "users", "123"]
    if (segments[0] === "api" && segments[1] === "users") {
      const userId = segments[2];
      return Response.json({ userId });
    }

    return new Response("Not Found", { status: 404 });
  }
};
```

### Build Outbound URL

```javascript
export default {
  async fetch(request) {
    // Build URL for external API
    const apiUrl = new URL("https://api.example.com/users");

    // Note: Can't modify properties directly (read-only)
    // Instead, build URL string manually
    const queryParams = "?page=1&limit=10";
    const fullUrl = apiUrl.href + queryParams;

    const response = await fetch(fullUrl);
    const data = await response.json();

    return Response.json(data);
  }
};
```

### Extract Domain from URL

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());

    return Response.json({
      domain: url.hostname,
      isSecure: url.protocol === "https:",
      port: url.port || "default"
    });
  }
};
```

### Normalize URLs

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());

    // Remove trailing slash
    let pathname = url.pathname;
    if (pathname.endsWith("/") && pathname !== "/") {
      pathname = pathname.slice(0, -1);
    }

    return Response.json({
      original: url.pathname,
      normalized: pathname
    });
  }
};
```

## Known Limitations

### Read-Only Properties (B-08)

URL properties cannot be modified after construction. Assignment like `url.pathname = "/new"` silently does nothing.

**Current behavior:**

```javascript
const url = new URL("https://example.com/old");
url.pathname = "/new"; // No effect
console.log(url.pathname); // Still "/old"
```

**Workaround:** Build new URL strings manually:

```javascript
const oldUrl = new URL("https://example.com/old");
const newUrl = new URL("https://example.com/new");
```

**Planned fix:** Setters for mutable properties in v1.3.

See [Limitations](/api/limitations#b-08-url-read-only) for details.

## Related APIs

- [Request](/api/request) - Get request URL via `request.url()`
- [fetch](/api/fetch) - Use URL objects for outbound requests
- [Response.redirect()](/api/response#responseredirect) - Create redirects with URLs
