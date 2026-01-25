// Security: Isolate isolation tests
// Status: Should FAIL until Phase 3, then PASS
// Run as two separate apps, verify no data leakage

// This file is a TEST TEMPLATE - actual test requires two running apps

const ISOLATION_MARKERS = {
  // Each app sets its own marker
  setMarker: (appId) => {
    globalThis[`__MARKER_${appId}__`] = true;
    globalThis.__LAST_APP__ = appId;
  },

  // Check if we can see other app's marker
  checkIsolation: (myAppId, otherAppId) => {
    const results = {
      myMarkerSet: globalThis[`__MARKER_${myAppId}__`] === true,
      otherMarkerVisible: globalThis[`__MARKER_${otherAppId}__`] !== undefined,
      lastAppCorrect: globalThis.__LAST_APP__ === myAppId,
    };

    return {
      test: "isolation",
      app: myAppId,
      passed: results.myMarkerSet && !results.otherMarkerVisible && results.lastAppCorrect,
      results
    };
  }
};

// Prototype pollution test
function testPrototypeIsolation() {
  // Try to pollute Object prototype
  const original = Object.prototype.toString;
  try {
    Object.prototype.__污染__ = "polluted";
    const polluted = ({}).__污染__ === "polluted";
    delete Object.prototype.__污染__;

    return {
      test: "prototype-isolation",
      // Pollution within same request is OK, but must not persist
      note: "Verify pollution does not persist across requests or apps"
    };
  } finally {
    Object.prototype.toString = original;
  }
}

JSON.stringify({
  markers: ISOLATION_MARKERS,
  prototype: testPrototypeIsolation()
});
