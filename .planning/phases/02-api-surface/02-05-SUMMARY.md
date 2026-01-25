# Summary 02-05: Crypto and Fetch APIs

## Completed: 2026-01-24

## What Was Built

### Crypto APIs (src/api/crypto.zig)
1. **crypto.randomUUID()** - Generates UUID v4 strings using std.crypto.random
2. **crypto.getRandomValues(arr)** - Fills TypedArray with random bytes (returns new array)
3. **crypto.subtle.digest(algo, data)** - Hashing with SHA-1, SHA-256, SHA-384, SHA-512

### Fetch API Stub (src/api/fetch.zig)
1. **fetch()** - Throws "not implemented" (requires Promise integration from Phase 3)
2. **Response** constructor with status(), ok(), text(), json() methods
   - Response object ready for use once fetch is fully implemented

## Technical Notes

### Crypto Implementation
- Uses Zig's std.crypto for all cryptographic operations
- randomUUID formats bytes as RFC 4122 UUID v4 string
- digest returns ArrayBuffer containing hash bytes
- getRandomValues creates new array with random bytes (deviation from Web API which fills in-place)

### Fetch Stub Rationale
- Zig 0.15.2 changed std.http.Client API significantly
- Synchronous fetch would block V8 event loop anyway
- Proper implementation requires V8 Promise integration (Phase 3)
- Response class scaffolding ready for future use

### Build System Updates
- Added crypto_module and fetch_module to build.zig
- Registered APIs in script.zig and repl.zig

## Verification

```javascript
// Crypto works
crypto.randomUUID()  // "2daccd08-a23f-4383-86e3-377695d6f0fc"
crypto.subtle.digest("SHA-256", "hello")  // [object ArrayBuffer]
crypto.getRandomValues(new Uint8Array(8))  // Uint8Array with random bytes

// Fetch shows pending status
fetch("https://example.com")  // Error: async HTTP not implemented yet

// Response constructor works
const r = new Response()
r.status()  // 200
r.ok()      // true
r.text()    // ""
```

## Deferred to Phase 3
- Full async fetch with HTTP client
- Promise-based Response methods (text(), json() returning Promises)
- Request body support for POST/PUT
