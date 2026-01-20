# Requirements: NANO

**Defined:** 2026-01-19
**Core Value:** Skip the container fleet entirely — one process hosts many isolated JS apps

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Core Runtime

- [ ] **CORE-01**: V8 isolate can execute JavaScript code and return results
- [ ] **CORE-02**: Arena allocator per request provides instant memory cleanup
- [ ] **CORE-03**: V8 snapshots enable <5ms cold start for new isolates
- [ ] **CORE-04**: Isolate pool maintains warm isolates for reuse between requests

### Web APIs

- [ ] **WAPI-01**: console.log, console.warn, console.error output to structured logs
- [ ] **WAPI-02**: TextEncoder and TextDecoder handle UTF-8 encoding/decoding
- [ ] **WAPI-03**: atob and btoa handle Base64 encoding/decoding
- [ ] **WAPI-04**: URL and URLSearchParams parse and manipulate URLs
- [ ] **WAPI-05**: setTimeout, clearTimeout, setInterval provide timer functionality
- [ ] **WAPI-06**: ReadableStream, WritableStream, TransformStream for streaming

### HTTP/Fetch

- [ ] **HTTP-01**: Headers class implements standard Headers API
- [ ] **HTTP-02**: Request class implements standard Request API
- [ ] **HTTP-03**: Response class implements standard Response API
- [ ] **HTTP-04**: fetch() function makes HTTP requests with full options support
- [ ] **HTTP-05**: AbortController and AbortSignal enable request cancellation
- [ ] **HTTP-06**: FormData handles multipart form data
- [ ] **HTTP-07**: Blob and File handle binary data

### Crypto

- [ ] **CRYP-01**: crypto.getRandomValues() fills typed arrays with random values
- [ ] **CRYP-02**: crypto.randomUUID() generates RFC 4122 UUIDs
- [ ] **CRYP-03**: crypto.subtle.digest() computes SHA-256, SHA-384, SHA-512 hashes
- [ ] **CRYP-04**: crypto.subtle.sign() and verify() handle HMAC and RSA signatures

### Multi-App Hosting

- [ ] **HOST-01**: Apps deploy by pointing NANO at a folder path
- [ ] **HOST-02**: App registry tracks app names and configurations
- [ ] **HOST-03**: HTTP server routes requests to apps by port

### Observability

- [ ] **OBSV-01**: Structured JSON logging includes app name, request ID, timestamp
- [ ] **OBSV-02**: HTTP errors return proper status codes and clean error messages
- [ ] **OBSV-03**: Prometheus metrics endpoint exposes isolate count, memory, latency

### Resource Limits

- [ ] **RLIM-01**: Memory limit per isolate enforced at creation (128MB default)
- [ ] **RLIM-02**: CPU watchdog terminates scripts exceeding time limit (50ms default)
- [ ] **RLIM-03**: Per-app configuration allows custom resource limits

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Routing

- **ROUT-01**: Virtual host routing (multiple apps on same port by hostname)
- **ROUT-02**: Path-based routing within single app

### Advanced APIs

- **ADVP-01**: WebSocket server support
- **ADVP-02**: Cache API for response caching
- **ADVP-03**: crypto.subtle.encrypt() and decrypt()
- **ADVP-04**: crypto.subtle key generation and import/export

### Toolchain

- **TOOL-01**: CLI for app deployment and management
- **TOOL-02**: Hot reload without process restart
- **TOOL-03**: TypeScript compilation support

### Storage Bindings

- **STOR-01**: KV-compatible storage API
- **STOR-02**: SQLite binding for local database access

## Out of Scope

| Feature | Reason |
|---------|--------|
| Node.js API compatibility | Workers API is simpler, safer; Node compat adds complexity |
| Durable Objects | Too complex for v1; fundamentally different programming model |
| Dynamic code eval | Security risk; deliberately disabled in edge runtimes |
| Global mutable state | Isolates are ephemeral; would create subtle bugs |
| Direct DB connections | Connection pooling nightmare; use storage bindings |
| Built-in HTTPS | Use external reverse proxy (nginx, Caddy) |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CORE-01 | Phase 1 | Pending |
| CORE-02 | Phase 1 | Pending |
| CORE-03 | Phase 4 | Pending |
| CORE-04 | Phase 4 | Pending |
| WAPI-01 | Phase 2 | Pending |
| WAPI-02 | Phase 2 | Pending |
| WAPI-03 | Phase 2 | Pending |
| WAPI-04 | Phase 2 | Pending |
| WAPI-05 | Phase 2 | Pending |
| WAPI-06 | Phase 2 | Pending |
| HTTP-01 | Phase 2 | Pending |
| HTTP-02 | Phase 2 | Pending |
| HTTP-03 | Phase 2 | Pending |
| HTTP-04 | Phase 2 | Pending |
| HTTP-05 | Phase 2 | Pending |
| HTTP-06 | Phase 2 | Pending |
| HTTP-07 | Phase 2 | Pending |
| CRYP-01 | Phase 2 | Pending |
| CRYP-02 | Phase 2 | Pending |
| CRYP-03 | Phase 2 | Pending |
| CRYP-04 | Phase 2 | Pending |
| HOST-01 | Phase 3 | Pending |
| HOST-02 | Phase 3 | Pending |
| HOST-03 | Phase 3 | Pending |
| OBSV-01 | Phase 5 | Pending |
| OBSV-02 | Phase 3 | Pending |
| OBSV-03 | Phase 5 | Pending |
| RLIM-01 | Phase 5 | Pending |
| RLIM-02 | Phase 5 | Pending |
| RLIM-03 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 28 total
- Mapped to phases: 28
- Unmapped: 0 ✓

---
*Requirements defined: 2026-01-19*
*Last updated: 2026-01-19 after initial definition*
