// Security: Node.js APIs must NOT exist
// Status: Should PASS (all checks return true = APIs absent)

const results = {
  // Core Node.js globals
  noProcess: typeof process === "undefined",
  noRequire: typeof require === "undefined",
  noModule: typeof module === "undefined",
  noExports: typeof exports === "undefined",
  noDirname: typeof __dirname === "undefined",
  noFilename: typeof __filename === "undefined",

  // Node.js Buffer (different from ArrayBuffer)
  noNodeBuffer: typeof Buffer === "undefined" || Buffer === ArrayBuffer,

  // Node.js specific globals
  noGlobal: typeof global === "undefined" || global === globalThis,
  noSetImmediate: typeof setImmediate === "undefined",
};

// All must be true
JSON.stringify({
  test: "no-node-apis",
  passed: Object.values(results).every(v => v === true),
  results
});
