// App A - Sets secret data that App B should NOT see
// Phase 3: Multi-app isolation test

// App-specific secret
globalThis.APP_SECRET = "secret-from-app-a-12345";
globalThis.APP_NAME = "app-a";

// Attempt to pollute global scope
globalThis.sharedData = { owner: "app-a", sensitive: "credit-card-1234" };

// Handler
export default {
  async fetch(request) {
    return new Response(JSON.stringify({
      app: globalThis.APP_NAME,
      hasSecret: !!globalThis.APP_SECRET,
      sharedData: globalThis.sharedData,
      // Try to access app-b's data (should be undefined)
      appBSecret: globalThis.APP_B_SECRET || "not-found",
    }), {
      headers: { "Content-Type": "application/json" }
    });
  }
};
