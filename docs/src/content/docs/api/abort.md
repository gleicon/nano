---
title: AbortController & AbortSignal
description: Request cancellation APIs
sidebar:
  order: 13
  badge:
    text: WinterCG
    variant: success
---

The `AbortController` and `AbortSignal` APIs provide a standard way to cancel asynchronous operations like `fetch()` requests or custom timeouts.

## AbortController

Creates an AbortSignal that can be used to cancel operations.

### Constructor

```javascript
const controller = new AbortController();
console.log(controller.signal); // AbortSignal
```

No parameters needed.

### Properties

#### signal

The AbortSignal associated with this controller.

```javascript
const controller = new AbortController();
const signal = controller.signal;

console.log(signal.aborted); // false

controller.abort();

console.log(signal.aborted); // true
```

**Type:** `AbortSignal` (getter)

### Methods

#### abort()

Signal that the operation should be cancelled.

```javascript
export default {
  async fetch(request) {
    const controller = new AbortController();

    // Abort after 1 second
    setTimeout(() => {
      controller.abort();
      console.log("Request aborted");
    }, 1000);

    try {
      const response = await fetch("https://slow-api.example.com", {
        signal: controller.signal
      });

      return new Response(await response.text());

    } catch (error) {
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

**Signature:** `abort(reason?: any) => void`

**Parameters:**
- `reason` (optional): Abort reason (stored in signal)

## AbortSignal

Represents a signal that can be checked or listened to for cancellation.

### Properties

#### aborted

Returns `true` if the signal has been aborted.

```javascript
const controller = new AbortController();
const signal = controller.signal;

console.log(signal.aborted); // false

controller.abort();

console.log(signal.aborted); // true
```

**Type:** `boolean` (getter)

### Static Methods

#### AbortSignal.timeout()

Create a signal that aborts after a specified delay.

```javascript
export default {
  async fetch(request) {
    try {
      const response = await fetch("https://api.example.com/data", {
        signal: AbortSignal.timeout(5000) // 5 second timeout
      });

      return new Response(await response.text());

    } catch (error) {
      if (error.name === "TimeoutError") {
        return Response.json(
          { error: "Request timeout after 5s" },
          { status: 504 }
        );
      }
      throw error;
    }
  }
};
```

**Signature:** `AbortSignal.timeout(ms: number) => AbortSignal`

**Parameters:**
- `ms`: Timeout in milliseconds

**Returns:** AbortSignal that aborts after timeout

:::note[Error Type]
Timeout uses `Error` with `name="TimeoutError"`, not `DOMException`. See implementation notes below.
:::

## Complete Examples

### Fetch with Timeout

```javascript
export default {
  async fetch(request) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 3000);

    try {
      const response = await fetch("https://api.example.com/data", {
        signal: controller.signal,
        headers: { "User-Agent": "NANO/1.2" }
      });

      clearTimeout(timeoutId);

      const data = await response.json();
      return Response.json(data);

    } catch (error) {
      clearTimeout(timeoutId);

      if (error.name === "AbortError") {
        return Response.json(
          { error: "Request aborted or timed out" },
          { status: 504 }
        );
      }

      return Response.json(
        { error: "Request failed", message: String(error) },
        { status: 502 }
      );
    }
  }
};
```

### AbortSignal.timeout() Pattern

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());
    const timeout = parseInt(url.searchParams.get("timeout") || "5000");

    try {
      const response = await fetch("https://api.example.com/slow", {
        signal: AbortSignal.timeout(timeout)
      });

      const data = await response.json();
      return Response.json(data);

    } catch (error) {
      if (error.name === "TimeoutError") {
        return Response.json(
          { error: `Timeout after ${timeout}ms` },
          { status: 504 }
        );
      }

      return Response.json(
        { error: String(error) },
        { status: 500 }
      );
    }
  }
};
```

### Conditional Abort

```javascript
export default {
  async fetch(request) {
    const controller = new AbortController();
    let requestCount = 0;

    // Abort if too many pending requests
    setTimeout(() => {
      requestCount++;
      if (requestCount > 10) {
        controller.abort("Too many concurrent requests");
      }
    }, 100);

    try {
      const response = await fetch("https://api.example.com/data", {
        signal: controller.signal
      });

      return new Response(await response.text());

    } catch (error) {
      if (error.name === "AbortError") {
        return Response.json(
          { error: "Request aborted", reason: "Rate limit" },
          { status: 429 }
        );
      }
      throw error;
    } finally {
      requestCount--;
    }
  }
};
```

### Manual Cancellation Check

```javascript
export default {
  async fetch(request) {
    const controller = new AbortController();
    const signal = controller.signal;

    // Simulate long operation with cancellation checks
    const processData = async () => {
      for (let i = 0; i < 100; i++) {
        if (signal.aborted) {
          throw new Error("Operation cancelled");
        }

        // Process chunk
        console.log("Processing chunk", i);

        // Simulate work
        await new Promise(resolve => setTimeout(resolve, 50));
      }

      return "Complete";
    };

    // Abort after 2 seconds
    setTimeout(() => controller.abort(), 2000);

    try {
      const result = await processData();
      return Response.json({ result });

    } catch (error) {
      return Response.json(
        { error: String(error) },
        { status: 499 }
      );
    }
  }
};
```

### Multiple Requests with Shared Abort

```javascript
export default {
  async fetch(request) {
    const controller = new AbortController();
    const timeout = 5000;

    setTimeout(() => controller.abort(), timeout);

    try {
      // Make multiple requests with same abort signal
      const [users, posts, comments] = await Promise.all([
        fetch("https://api.example.com/users", { signal: controller.signal }),
        fetch("https://api.example.com/posts", { signal: controller.signal }),
        fetch("https://api.example.com/comments", { signal: controller.signal })
      ]);

      const data = {
        users: await users.json(),
        posts: await posts.json(),
        comments: await comments.json()
      };

      return Response.json(data);

    } catch (error) {
      if (error.name === "AbortError" || error.name === "TimeoutError") {
        return Response.json(
          { error: "One or more requests timed out" },
          { status: 504 }
        );
      }

      return Response.json(
        { error: String(error) },
        { status: 500 }
      );
    }
  }
};
```

### Graceful Shutdown

```javascript
let globalAbortController = new AbortController();

// In production, this would be triggered by SIGTERM
function initiateShutdown() {
  console.log("Shutting down gracefully...");
  globalAbortController.abort("Server shutting down");
}

export default {
  async fetch(request) {
    if (globalAbortController.signal.aborted) {
      return Response.json(
        { error: "Server is shutting down" },
        { status: 503 }
      );
    }

    try {
      const response = await fetch("https://api.example.com/data", {
        signal: globalAbortController.signal
      });

      return new Response(await response.text());

    } catch (error) {
      if (error.name === "AbortError") {
        return Response.json(
          { error: "Request cancelled due to shutdown" },
          { status: 503 }
        );
      }
      throw error;
    }
  }
};
```

## Implementation Notes

### Error Types

NANO uses standard `Error` with `name` property for abort errors:

- `AbortError`: When controller.abort() is called manually
- `TimeoutError`: When AbortSignal.timeout() expires

**Note:** NANO doesn't use `DOMException` (not available in runtime). Use `error.name` to distinguish error types.

```javascript
try {
  await fetch(url, { signal: AbortSignal.timeout(1000) });
} catch (error) {
  if (error.name === "TimeoutError") {
    // Timeout occurred
  } else if (error.name === "AbortError") {
    // Manual abort
  }
}
```

### Signal Reuse

Don't reuse an aborted signal. Create a new AbortController for each operation:

```javascript
// Bad - reusing aborted controller
const controller = new AbortController();
controller.abort();
await fetch(url, { signal: controller.signal }); // Immediately aborted

// Good - new controller per operation
const controller1 = new AbortController();
await fetch(url1, { signal: controller1.signal });

const controller2 = new AbortController();
await fetch(url2, { signal: controller2.signal });
```

## Related APIs

- [fetch](/api/fetch) - Use signal option to cancel requests
- [Timers](/api/timers) - setTimeout for timeout implementation
- [Streams](/api/streams) - Cancel stream reads with signals
