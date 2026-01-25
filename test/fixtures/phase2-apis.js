// Phase 2: Workers API tests (will fail until Phase 2)
// These test the API surface we need to implement

// Console (should appear in host logs)
console.log("Starting phase 2 tests");
console.error("This is an error message");

// TextEncoder/TextDecoder
const encoder = new TextEncoder();
const encoded = encoder.encode("hello");
const decoder = new TextDecoder();
const decoded = decoder.decode(encoded);

// URL parsing
const url = new URL("https://example.com/path?query=value");
const params = url.searchParams.get("query");

// Crypto - random
const randomBytes = crypto.getRandomValues(new Uint8Array(16));

// Crypto - hashing
const hashBuffer = await crypto.subtle.digest(
  "SHA-256",
  encoder.encode("hello world")
);

// Fetch (async)
const response = await fetch("https://httpbin.org/json");
const data = await response.json();

JSON.stringify({ decoded, params, data })
