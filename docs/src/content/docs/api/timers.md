---
title: Timers
description: setTimeout and setInterval APIs for scheduling tasks
sidebar:
  order: 7
  badge:
    text: WinterCG
    variant: success
---

NANO provides standard timer APIs for scheduling deferred and recurring tasks: `setTimeout`, `setInterval`, `clearTimeout`, and `clearInterval`.

## setTimeout()

Schedule a function to run after a delay.

```javascript
export default {
  async fetch(request) {
    console.log("Request received");

    setTimeout(() => {
      console.log("Delayed log (500ms later)");
    }, 500);

    return new Response("Timer scheduled");
  }
};
```

**Signature:** `setTimeout(callback: Function, delay: number) => number`

**Parameters:**
- `callback`: Function to execute after delay
- `delay`: Delay in milliseconds

**Returns:** Timer ID (number) for use with `clearTimeout()`

## setInterval()

Schedule a function to run repeatedly at intervals.

```javascript
export default {
  async fetch(request) {
    let count = 0;

    const intervalId = setInterval(() => {
      count++;
      console.log("Interval fired:", count);

      if (count >= 5) {
        clearInterval(intervalId);
        console.log("Interval stopped");
      }
    }, 1000);

    return new Response("Interval scheduled");
  }
};
```

**Signature:** `setInterval(callback: Function, interval: number) => number`

**Parameters:**
- `callback`: Function to execute at each interval
- `interval`: Interval in milliseconds

**Returns:** Timer ID (number) for use with `clearInterval()`

## clearTimeout()

Cancel a scheduled timeout.

```javascript
export default {
  async fetch(request) {
    const timeoutId = setTimeout(() => {
      console.log("This won't run");
    }, 5000);

    // Cancel the timeout
    clearTimeout(timeoutId);

    return new Response("Timeout cancelled");
  }
};
```

**Signature:** `clearTimeout(id: number) => void`

## clearInterval()

Cancel a recurring interval.

```javascript
export default {
  async fetch(request) {
    let count = 0;

    const intervalId = setInterval(() => {
      count++;
      console.log("Count:", count);
    }, 100);

    // Stop after 1 second
    setTimeout(() => {
      clearInterval(intervalId);
      console.log("Interval cleared");
    }, 1000);

    return new Response("Interval with auto-stop");
  }
};
```

**Signature:** `clearInterval(id: number) => void`

## Complete Examples

### Delayed Response Processing

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());

    if (url.pathname === "/delayed") {
      setTimeout(() => {
        console.log("Processing completed after delay");
      }, 2000);

      return Response.json({
        message: "Processing scheduled",
        delay: 2000
      });
    }

    return new Response("OK");
  }
};
```

### Periodic Background Task

```javascript
let requestCount = 0;

// Start background counter
const counterId = setInterval(() => {
  console.log("Total requests processed:", requestCount);
}, 10000); // Log every 10 seconds

export default {
  async fetch(request) {
    requestCount++;

    return Response.json({
      requestNumber: requestCount
    });
  }
};
```

### Timeout with Cleanup

```javascript
export default {
  async fetch(request) {
    const timers = [];

    // Schedule multiple timeouts
    timers.push(setTimeout(() => console.log("Task 1"), 100));
    timers.push(setTimeout(() => console.log("Task 2"), 200));
    timers.push(setTimeout(() => console.log("Task 3"), 300));

    // Cleanup function
    const cleanup = () => {
      timers.forEach(id => clearTimeout(id));
      console.log("All timers cleared");
    };

    // Auto-cleanup after 5 seconds
    setTimeout(cleanup, 5000);

    return Response.json({
      scheduled: timers.length,
      message: "Timers scheduled with auto-cleanup"
    });
  }
};
```

### Rate Limiting with Intervals

```javascript
const requestLog = [];

// Clean old entries every minute
setInterval(() => {
  const oneMinuteAgo = Date.now() - 60000;
  const before = requestLog.length;

  // Remove old entries
  while (requestLog.length > 0 && requestLog[0] < oneMinuteAgo) {
    requestLog.shift();
  }

  console.log(`Cleaned ${before - requestLog.length} old entries`);
}, 60000);

export default {
  async fetch(request) {
    const now = Date.now();
    requestLog.push(now);

    // Count requests in last minute
    const oneMinuteAgo = now - 60000;
    const recentCount = requestLog.filter(t => t >= oneMinuteAgo).length;

    if (recentCount > 100) {
      return Response.json(
        { error: "Rate limit exceeded" },
        { status: 429 }
      );
    }

    return Response.json({
      requestsInLastMinute: recentCount
    });
  }
};
```

### Debounced Logging

```javascript
let logTimer = null;
let pendingLogs = [];

function flushLogs() {
  if (pendingLogs.length > 0) {
    console.log("Batch log:", pendingLogs.join(", "));
    pendingLogs = [];
  }
}

export default {
  async fetch(request) {
    const url = new URL(request.url());
    pendingLogs.push(url.pathname);

    // Clear existing timer
    if (logTimer) {
      clearTimeout(logTimer);
    }

    // Schedule flush after 1 second of inactivity
    logTimer = setTimeout(flushLogs, 1000);

    return new Response("OK");
  }
};
```

## Implementation Notes

### Event Loop Integration

Timers are integrated with NANO's event loop (libxev). Timer callbacks execute between request processing cycles.

### Timing Model

NANO uses an **iteration-based** timing model, not wall-clock timing. Timer delays are approximate and depend on event loop iterations. For precise timing, timers may fire slightly later than scheduled.

### Timer Resolution

Timer resolution depends on event loop iteration frequency. Delays under 10ms may be less precise than longer delays.

### Cleanup

Always clear timers when done to avoid memory leaks and unnecessary processing:

```javascript
// Good - cleanup when done
const timerId = setTimeout(() => {
  console.log("Task complete");
}, 1000);

// Later...
clearTimeout(timerId);

// Bad - timer never cleared
setInterval(() => {
  console.log("This runs forever");
}, 1000); // Leaks if never cleared
```

## Known Limitations

### REPL Timer Support

Timers are not fully supported in REPL mode. They work in production `serve` mode.

### No Arguments to Callbacks

Unlike browser `setTimeout`, NANO's timers don't support passing arguments to callbacks:

```javascript
// Not supported
setTimeout(console.log, 1000, "arg1", "arg2");

// Use arrow function instead
setTimeout(() => {
  console.log("arg1", "arg2");
}, 1000);
```

## Related APIs

- [Console](/api/console) - Logging from timer callbacks
- [fetch](/api/fetch) - Making requests from timers
- [AbortController](/api/abort) - Timeout pattern for fetch
