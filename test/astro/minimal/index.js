// Astro minimal SSR - converted to NANO format
// Tests core API compatibility

// Required APIs check
const REQUIRED_APIS = [
  'Request', 'Response', 'Headers', 'URL', 'URLSearchParams',
  'TextEncoder', 'TextDecoder', 'crypto'
];

function checkAPIs() {
  const missing = REQUIRED_APIS.filter(api => typeof globalThis[api] === 'undefined');
  return { ok: missing.length === 0, missing };
}

// Simple HTML template (what Astro SSR produces)
function renderHomePage() {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Astro on NANO</title>
</head>
<body>
  <h1>Hello from Astro!</h1>
  <p>Server-rendered at ${new Date().toISOString()}</p>
  <p>Request ID: ${crypto.randomUUID()}</p>
</body>
</html>`;
}

// API route handler
function handleApiPing() {
  return Response.json({ pong: true, timestamp: Date.now() });
}

// Router (simplified Astro routing)
function router(pathname) {
  if (pathname === '/' || pathname === '/index.html') {
    return { handler: renderHomePage, type: 'html' };
  }
  if (pathname === '/api/ping') {
    return { handler: handleApiPing, type: 'json' };
  }
  if (pathname === '/api/check') {
    return { handler: () => Response.json(checkAPIs()), type: 'json' };
  }
  return null;
}

// NANO entry point
export default {
  fetch(request) {
    const url = new URL(request.url());
    const route = router(url.pathname());

    if (!route) {
      return new Response('Not Found', { status: 404 });
    }

    if (route.type === 'json') {
      return route.handler();
    }

    return new Response(route.handler(), {
      headers: { 'Content-Type': 'text/html; charset=utf-8' }
    });
  }
});
