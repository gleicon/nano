// Cloudflare Workers API Demo
// This demonstrates nano's compatibility with the Cloudflare Workers API
// Run with: nano serve --port 8787 --app ./test/cloudflare-worker

// KV simulation (in-memory for demo purposes)
const KV = new Map();

// Helper: generate ETag from content
function generateETag(content) {
  let hash = 0;
  for (let i = 0; i < content.length; i++) {
    hash = ((hash << 5) - hash) + content.charCodeAt(i);
    hash |= 0;
  }
  return `"${Math.abs(hash).toString(16)}"`;
}

// Helper: CORS headers
function corsHeaders(origin = "*") {
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization"
  };
}

// Route: Home page with API documentation
function handleHome(request) {
  const html = `<!DOCTYPE html>
<html>
<head>
  <title>Cloudflare Workers Demo on NANO</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 800px; margin: 2rem auto; padding: 0 1rem; }
    code { background: #f4f4f4; padding: 0.2em 0.4em; border-radius: 3px; }
    pre { background: #f4f4f4; padding: 1rem; border-radius: 5px; overflow-x: auto; }
    .endpoint { margin: 1rem 0; padding: 1rem; border-left: 3px solid #f6821f; background: #fff8f0; }
    h1 { color: #f6821f; }
  </style>
</head>
<body>
  <h1>Cloudflare Workers Demo</h1>
  <p>Running on <strong>NANO</strong> - a lightweight JavaScript runtime</p>

  <h2>Available Endpoints</h2>

  <div class="endpoint">
    <h3>GET /api/hello</h3>
    <p>Simple JSON response with request metadata</p>
  </div>

  <div class="endpoint">
    <h3>GET /api/crypto</h3>
    <p>Demonstrates crypto.randomUUID() and crypto.subtle.digest()</p>
  </div>

  <div class="endpoint">
    <h3>GET /api/headers</h3>
    <p>Echo back request headers</p>
  </div>

  <div class="endpoint">
    <h3>POST /api/json</h3>
    <p>Parse and echo JSON body</p>
    <pre>curl -X POST -H "Content-Type: application/json" -d '{"name":"test"}' http://localhost:8787/api/json</pre>
  </div>

  <div class="endpoint">
    <h3>GET/PUT /api/kv/:key</h3>
    <p>Simulated KV store operations</p>
    <pre>curl -X PUT -d "hello world" http://localhost:8787/api/kv/mykey
curl http://localhost:8787/api/kv/mykey</pre>
  </div>

  <div class="endpoint">
    <h3>GET /api/redirect</h3>
    <p>HTTP redirect example</p>
  </div>

  <div class="endpoint">
    <h3>OPTIONS /*</h3>
    <p>CORS preflight handling</p>
  </div>

  <footer style="margin-top: 2rem; color: #666;">
    <p>Request ID: ${crypto.randomUUID()}</p>
    <p>Rendered at: ${new Date().toISOString()}</p>
  </footer>
</body>
</html>`;

  return new Response(html, {
    headers: { "Content-Type": "text/html; charset=utf-8" }
  });
}

// Route: Hello World with request info
function handleHello(request) {
  const url = new URL(request.url());

  return Response.json({
    message: "Hello from Cloudflare Workers on NANO!",
    cf: {
      // Simulated CF properties (would be real on Cloudflare)
      colo: "LOCAL",
      country: "XX",
      city: "Development"
    },
    request: {
      method: request.method(),
      url: request.url(),
      pathname: url.pathname()
    },
    timestamp: Date.now()
  });
}

// Route: Crypto demo
async function handleCrypto(request) {
  const uuid = crypto.randomUUID();
  const message = "Hello, NANO!";

  // Hash the message using SHA-256
  const encoder = new TextEncoder();
  const data = encoder.encode(message);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);

  // Convert to hex string
  const hashArray = new Uint8Array(hashBuffer);
  let hashHex = "";
  for (let i = 0; i < hashArray.length; i++) {
    hashHex += hashArray[i].toString(16).padStart(2, "0");
  }

  return Response.json({
    uuid: uuid,
    message: message,
    sha256: hashHex,
    randomBytes: btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(16))))
  });
}

// Route: Headers echo
function handleHeaders(request) {
  const headers = request.headers();
  const headerObj = {};

  // Note: In a full implementation, Headers would be iterable
  // For now, we check common headers
  const commonHeaders = [
    "host", "user-agent", "accept", "content-type",
    "authorization", "x-forwarded-for", "x-real-ip"
  ];

  for (const name of commonHeaders) {
    const value = headers.get(name);
    if (value) {
      headerObj[name] = value;
    }
  }

  return Response.json({
    headers: headerObj,
    note: "Common headers extracted from request"
  });
}

// Route: JSON body parsing
async function handleJson(request) {
  if (request.method() !== "POST") {
    return Response.json({ error: "POST required" }, { status: 405 });
  }

  try {
    const body = request.json();
    return Response.json({
      received: body,
      type: typeof body,
      timestamp: Date.now()
    });
  } catch (e) {
    return Response.json({ error: "Invalid JSON", message: String(e) }, { status: 400 });
  }
}

// Route: KV operations
function handleKV(request, key) {
  const method = request.method();

  if (method === "GET") {
    const value = KV.get(key);
    if (value === undefined) {
      return Response.json({ error: "Key not found" }, { status: 404 });
    }
    return new Response(value, {
      headers: {
        "Content-Type": "text/plain",
        "ETag": generateETag(value)
      }
    });
  }

  if (method === "PUT") {
    const value = request.text();
    KV.set(key, value);
    return Response.json({
      success: true,
      key: key,
      size: value.length
    }, { status: 201 });
  }

  if (method === "DELETE") {
    const existed = KV.has(key);
    KV.delete(key);
    return Response.json({
      success: true,
      deleted: existed
    });
  }

  return Response.json({ error: "Method not allowed" }, { status: 405 });
}

// Route: Redirect
function handleRedirect(request) {
  return Response.redirect("https://workers.cloudflare.com/", 302);
}

// CORS preflight handler
function handleOptions(request) {
  return new Response(null, {
    status: 204,
    headers: corsHeaders()
  });
}

// Main fetch handler - Cloudflare Workers style
export default {
  async fetch(request) {
    const url = new URL(request.url());
    const path = url.pathname();
    const method = request.method();

    // Handle CORS preflight
    if (method === "OPTIONS") {
      return handleOptions(request);
    }

    // Router
    try {
      // Home page
      if (path === "/" || path === "/index.html") {
        return handleHome(request);
      }

      // API routes
      if (path === "/api/hello") {
        return handleHello(request);
      }

      if (path === "/api/crypto") {
        return await handleCrypto(request);
      }

      if (path === "/api/headers") {
        return handleHeaders(request);
      }

      if (path === "/api/json") {
        return await handleJson(request);
      }

      if (path.startsWith("/api/kv/")) {
        const key = path.slice(8); // Remove "/api/kv/"
        if (!key) {
          return Response.json({ error: "Key required" }, { status: 400 });
        }
        return handleKV(request, key);
      }

      if (path === "/api/redirect") {
        return handleRedirect(request);
      }

      // 404 for unmatched routes
      return Response.json({
        error: "Not Found",
        path: path,
        availableRoutes: [
          "/",
          "/api/hello",
          "/api/crypto",
          "/api/headers",
          "/api/json",
          "/api/kv/:key",
          "/api/redirect"
        ]
      }, { status: 404 });

    } catch (error) {
      // Error handling - important for production workers
      console.error("Request failed:", String(error));
      return Response.json({
        error: "Internal Server Error",
        message: String(error)
      }, { status: 500 });
    }
  }
};
