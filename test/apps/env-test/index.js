export default {
  async fetch(request, env) {
    return new Response(JSON.stringify({
      hasEnv: !!env,
      apiKey: env.API_KEY,
      debug: env.DEBUG
    }), {
      headers: { "content-type": "application/json" }
    });
  }
};
