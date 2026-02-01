export default {
  fetch(request) {
    return new Response(JSON.stringify({
      app: "app-b",
      message: "Hello from App B!",
      url: request.url
    }), {
      headers: { "Content-Type": "application/json" }
    });
  }
}
