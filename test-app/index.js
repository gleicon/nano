// Simple NANO app
export default {
  fetch(request) {
    const url = request.url();
    const method = request.method();

    if (url.includes("/json")) {
      return Response.json({
        message: "Hello from NANO!",
        method: method,
        url: url
      });
    }

    if (url.includes("/echo")) {
      const body = request.text();
      return new Response("Echo: " + body, { status: 200 });
    }

    return new Response("Hello from NANO app!\nPath: " + url + "\nMethod: " + method, {
      status: 200,
      headers: { "content-type": "text/plain" }
    });
  }
});
