// SECURITY TEST: Verifies isolation is working
// This app attempts various attacks - ALL should fail
// Used to verify NANO's sandboxing is effective

export default {
  async fetch(request) {
    const results = {};

    // Test 1: Node.js APIs should not exist
    results.noProcess = typeof process === "undefined";
    results.noRequire = typeof require === "undefined";

    // Test 2: Other runtime APIs should not exist
    results.noDeno = typeof Deno === "undefined";
    results.noBun = typeof Bun === "undefined";

    // Test 3: Prototype pollution should not persist across requests
    try {
      Object.prototype._test_ = "test";
      results.prototypeWritable = true;
      delete Object.prototype._test_;
    } catch (e) {
      results.prototypeWritable = false;
    }

    // Test 4: Cannot access other apps' globals
    results.noAppASecret = typeof globalThis.APP_SECRET === "undefined";
    results.noAppBSecret = typeof globalThis.APP_B_SECRET === "undefined";

    // Test 5: globalThis is isolated
    results.isolatedGlobal = !globalThis._otherAppMarker;
    globalThis._otherAppMarker = true; // Mark for next request

    return new Response(JSON.stringify({
      testName: "Security isolation verification",
      results,
      // For secure implementation: all should be true
      allPassed: Object.values(results).every(v => v === true)
    }, null, 2));
  }
};
