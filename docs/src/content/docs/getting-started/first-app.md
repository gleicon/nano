---
title: Your First App
description: Create and deploy your first NANO application
sidebar:
  order: 3
---

This guide walks you through creating a simple NANO application, running it, and testing the endpoints.

## Create Your App

### 1. Create App Directory

```bash
mkdir my-app
cd my-app
```

### 2. Create Handler File

Create `index.js` with a basic fetch handler:

```javascript
// my-app/index.js
export default {
    async fetch(request) {
        const url = new URL(request.url());

        // Handle different routes
        if (url.pathname === "/api/hello") {
            return Response.json({
                message: "Hello from NANO!",
                timestamp: Date.now()
            });
        }

        if (url.pathname === "/api/echo") {
            const method = request.method();
            return Response.json({
                method: method,
                path: url.pathname,
                query: Object.fromEntries(url.searchParams)
            });
        }

        if (url.pathname === "/api/crypto") {
            // Demonstrate crypto API
            const uuid = crypto.randomUUID();
            return Response.json({
                uuid: uuid,
                random: Array.from(crypto.getRandomValues(new Uint8Array(16)))
            });
        }

        // 404 for unmatched routes
        return Response.json({
            error: "Not Found",
            availableRoutes: ["/api/hello", "/api/echo", "/api/crypto"]
        }, { status: 404 });
    }
};
```

## Run Your App

Start NANO with your app:

```bash
cd ..  # Back to nano repository root
./zig-out/bin/nano serve --port 3000 --app ./my-app
```

You should see output like:

```
[INFO] Starting NANO server
[INFO] Loaded app from ./my-app
[INFO] Server listening on http://0.0.0.0:3000
```

:::tip[Keep It Running]
Leave this terminal open with NANO running. Open a new terminal for testing.
:::

## Test Your App

### Basic Hello Endpoint

```bash
curl http://127.0.0.1:3000/api/hello
```

Expected output:

```json
{
  "message": "Hello from NANO!",
  "timestamp": 1707484821234
}
```

### Echo Endpoint

```bash
curl "http://127.0.0.1:3000/api/echo?name=test&value=123"
```

Expected output:

```json
{
  "method": "GET",
  "path": "/api/echo",
  "query": {
    "name": "test",
    "value": "123"
  }
}
```

### Crypto Endpoint

```bash
curl http://127.0.0.1:3000/api/crypto
```

Expected output:

```json
{
  "uuid": "550e8400-e29b-41d4-a716-446655440000",
  "random": [123, 45, 67, ...]
}
```

## Understanding the Code

### Handler Structure

NANO expects an export default object with a `fetch` method:

```javascript
export default {
    async fetch(request) {
        // Handler logic
        return response;
    }
};
```

The handler can be sync or async. If you use `await`, mark it as `async`.

### Request Object

The `request` parameter provides:

- `request.url()` - Full URL string
- `request.method()` - HTTP method (GET, POST, etc.)
- `request.headers()` - Headers object
- `request.text()` - Body as text (for POST/PUT)
- `request.json()` - Body parsed as JSON

:::note[Method Calls]
Note that `url()` and `method()` are **methods** (with parentheses), not properties. This differs from Cloudflare Workers but will be aligned in future versions.
:::

### Response Object

Create responses using:

- `new Response(body, options)` - Basic response
- `Response.json(data)` - JSON response with proper Content-Type
- `Response.redirect(url, status)` - Redirect response

### URL Parsing

Use the standard `URL` class for parsing:

```javascript
const url = new URL(request.url());
console.log(url.pathname);        // "/api/hello"
console.log(url.searchParams.get("name"));  // Query parameter
```

## Add More Features

### POST Request Handling

```javascript
if (request.method() === "POST" && url.pathname === "/api/data") {
    const body = request.json();
    return Response.json({
        received: body,
        processed: true
    });
}
```

### External Fetch Calls

```javascript
if (url.pathname === "/api/proxy") {
    const response = await fetch("https://api.example.com/data");
    const data = await response.json();
    return Response.json(data);
}
```

### Timers

```javascript
if (url.pathname === "/api/delayed") {
    await new Promise(resolve => setTimeout(resolve, 1000));
    return Response.json({ message: "Waited 1 second" });
}
```

## Built-in Endpoints

NANO provides some endpoints automatically:

- `/health` or `/healthz` - Health check, returns `{"status":"ok"}`
- `/metrics` - Prometheus-format metrics

```bash
curl http://127.0.0.1:3000/health
curl http://127.0.0.1:3000/metrics
```

## Next Steps

Congratulations! You've created and tested your first NANO app.

Next, explore:

- **[Configuration](/config/)** - Learn about multi-app hosting with config files
- **[API Reference](/api/)** - Discover all available JavaScript APIs
- **[Examples](/config/examples/)** - See real-world configuration examples

### Multi-App Hosting

To host multiple apps on the same port with virtual host routing, see the [Configuration Guide](/config/).
