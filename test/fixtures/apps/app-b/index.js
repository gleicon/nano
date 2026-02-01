// App B - Multi-app config test
// Returns different app identifier

export default {
  fetch(request) {
    const url = new URL(request.url());
    return new Response(JSON.stringify({
      app: "app-b",
      path: url.pathname(),
      timestamp: Date.now()
    }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });
  }
});
