// App B - Should NOT see App A's data
// Phase 3: Multi-app isolation test

// App-specific secret
globalThis.APP_B_SECRET = "secret-from-app-b-67890";
globalThis.APP_NAME = "app-b";

// Handler
export default {
  async fetch(request) {
    return new Response(JSON.stringify({
      app: globalThis.APP_NAME,
      hasOwnSecret: !!globalThis.APP_B_SECRET,
      // ISOLATION TEST: These should all be undefined/not-found
      appASecret: globalThis.APP_SECRET || "not-found",
      sharedData: globalThis.sharedData || "not-found",
      // Verify we can't enumerate app-a's globals
      globalKeys: Object.keys(globalThis).filter(k => k.includes("APP")),
    }), {
      headers: { "Content-Type": "application/json" }
    });
  }
};
