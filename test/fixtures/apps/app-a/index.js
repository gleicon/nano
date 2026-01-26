// App A - Multi-app config test
// Returns app identifier and timestamp

__setDefault({
  fetch(request) {
    const url = new URL(request.url());
    return new Response(JSON.stringify({
      app: "app-a",
      path: url.pathname(),
      timestamp: Date.now()
    }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });
  }
});
