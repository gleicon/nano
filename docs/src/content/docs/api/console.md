---
title: Console
description: Console API for logging and debugging
sidebar:
  order: 8
  badge:
    text: Standard
    variant: note
---

The `console` object provides logging methods for debugging and monitoring your NANO applications. Logs are written to standard output (stdout) for info/log/debug and standard error (stderr) for warn/error.

## Methods

### console.log()

Log informational messages.

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());
    console.log("Request received:", url.pathname);

    return new Response("OK");
  }
};
```

**Signature:** `console.log(...values: any[]) => void`

**Output:** Writes to stdout

### console.info()

Log informational messages (alias for `console.log()`).

```javascript
console.info("Server started on port 3000");
```

**Signature:** `console.info(...values: any[]) => void`

**Output:** Writes to stdout

### console.debug()

Log debug messages (alias for `console.log()`).

```javascript
console.debug("Debug info:", { userId: 123, action: "login" });
```

**Signature:** `console.debug(...values: any[]) => void`

**Output:** Writes to stdout

### console.warn()

Log warning messages.

```javascript
export default {
  async fetch(request) {
    const headers = request.headers();

    if (!headers.has("authorization")) {
      console.warn("Request missing authorization header");
    }

    return new Response("OK");
  }
};
```

**Signature:** `console.warn(...values: any[]) => void`

**Output:** Writes to stderr

### console.error()

Log error messages.

```javascript
export default {
  async fetch(request) {
    try {
      // Some operation
      throw new Error("Something went wrong");
    } catch (error) {
      console.error("Request failed:", String(error));
      return Response.json({ error: "Internal error" }, { status: 500 });
    }
  }
};
```

**Signature:** `console.error(...values: any[]) => void`

**Output:** Writes to stderr

## Object Logging

NANO uses `JSON.stringify()` for object inspection, not `[object Object]` like some environments.

```javascript
const user = {
  id: 123,
  name: "Alice",
  roles: ["admin", "user"]
};

console.log("User data:", user);
// Output: User data: {"id":123,"name":"Alice","roles":["admin","user"]}
```

:::note[Buffer Limit]
Each logged value has a 4KB buffer limit. Large objects may be truncated. See [B-01 limitation](/api/limitations#b-01-buffer-limits).
:::

## Complete Examples

### Request Logging

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());
    const method = request.method();

    console.log("Incoming request:", {
      method: method,
      path: url.pathname,
      timestamp: new Date().toISOString()
    });

    return Response.json({ status: "ok" });
  }
};
```

### Error Logging

```javascript
export default {
  async fetch(request) {
    try {
      const data = request.json();

      if (!data.name) {
        throw new Error("Missing required field: name");
      }

      return Response.json({ success: true });

    } catch (error) {
      console.error("Request validation failed:", {
        error: String(error),
        url: request.url()
      });

      return Response.json(
        { error: String(error) },
        { status: 400 }
      );
    }
  }
};
```

### Performance Logging

```javascript
export default {
  async fetch(request) {
    const startTime = Date.now();

    // Process request
    const response = Response.json({ data: "example" });

    const duration = Date.now() - startTime;
    console.log("Request processed in", duration, "ms");

    return response;
  }
};
```

### Structured Logging

```javascript
function logRequest(level, message, metadata) {
  const logEntry = {
    level: level,
    message: message,
    timestamp: new Date().toISOString(),
    ...metadata
  };

  if (level === "error") {
    console.error(logEntry);
  } else if (level === "warn") {
    console.warn(logEntry);
  } else {
    console.log(logEntry);
  }
}

export default {
  async fetch(request) {
    const url = new URL(request.url());

    logRequest("info", "Request received", {
      method: request.method(),
      path: url.pathname
    });

    try {
      // Process request
      return Response.json({ status: "ok" });

    } catch (error) {
      logRequest("error", "Request failed", {
        error: String(error),
        path: url.pathname
      });

      return Response.json({ error: "Internal error" }, { status: 500 });
    }
  }
};
```

### Conditional Logging

```javascript
const DEBUG = true; // Set from environment variable in production

function debug(...args) {
  if (DEBUG) {
    console.debug(...args);
  }
}

export default {
  async fetch(request) {
    debug("Debug mode enabled");

    const url = new URL(request.url());
    debug("Parsed URL:", {
      pathname: url.pathname,
      search: url.search
    });

    return Response.json({ debug: DEBUG });
  }
};
```

### Rate Limit Warnings

```javascript
const requestCounts = new Map();

export default {
  async fetch(request) {
    const clientIp = request.headers().get("x-real-ip") || "unknown";
    const count = (requestCounts.get(clientIp) || 0) + 1;
    requestCounts.set(clientIp, count);

    if (count > 100) {
      console.warn("Rate limit approaching for client:", clientIp, "count:", count);
    }

    if (count > 200) {
      console.error("Rate limit exceeded for client:", clientIp);
      return Response.json({ error: "Too many requests" }, { status: 429 });
    }

    return Response.json({ requestCount: count });
  }
};
```

## Output Format

Console output includes the log level prefix:

```
[INFO] Request received: /api/users
[WARN] Missing authorization header
[ERROR] Database connection failed
```

## Known Limitations

### Buffer Size (B-01)

Each logged value has a 4KB buffer limit. Large objects or strings may be truncated.

**Workaround:** Log large objects in chunks or write to external logging service.

```javascript
// May be truncated if object is large
const largeObject = { /* ... */ };
console.log("Large object:", largeObject);

// Better: log specific fields
console.log("User ID:", largeObject.id);
console.log("User name:", largeObject.name);
```

See [Limitations](/api/limitations#b-01-buffer-limits) for details.

### No Console Formatting

NANO doesn't support console formatting directives like `%s`, `%d`, `%o`:

```javascript
// Not supported
console.log("User %s has ID %d", name, id);

// Use template strings instead
console.log(`User ${name} has ID ${id}`);
```

## Related APIs

- [Timers](/api/timers) - Logging from timer callbacks
- [fetch](/api/fetch) - Logging outbound requests
