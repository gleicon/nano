export default {
  fetch(request) {
    return new Response(JSON.stringify({
      app: "app-a",
      message: "Hello from App A!",
      url: request.url
    }), {
      headers: { "Content-Type": "application/json" }
    });
  }
}
