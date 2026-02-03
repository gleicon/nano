export default {
  async fetch(request, env) {
    return new Response(JSON.stringify(env), {
      headers: { "content-type": "application/json" }
    });
  }
};
