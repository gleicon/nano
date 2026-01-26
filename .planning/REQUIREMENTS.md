# Requirements: NANO

**Defined:** 2026-01-19
**Core Value:** Skip the container fleet entirely — one process hosts many isolated JS apps

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Core Runtime

- [x] **CORE-01**: V8 isolate can execute JavaScript code and return results
- [x] **CORE-02**: Arena allocator per request provides instant memory cleanup
- [ ] **CORE-03**: V8 snapshots enable <5ms cold start for new isolates (deferred v2)
- [ ] **CORE-04**: Isolate pool maintains warm isolates for reuse between requests (deferred v2)

### Web APIs

- [x] **WAPI-01**: console.log, console.warn, console.error output to structured logs
- [x] **WAPI-02**: TextEncoder and TextDecoder handle UTF-8 encoding/decoding
- [x] **WAPI-03**: atob and btoa handle Base64 encoding/decoding
- [x] **WAPI-04**: URL and URLSearchParams parse and manipulate URLs
- [x] **WAPI-05**: setTimeout, clearTimeout, setInterval provide timer functionality
- [ ] **WAPI-06**: ReadableStream, WritableStream, TransformStream for streaming (deferred v2)

### HTTP/Fetch

- [x] **HTTP-01**: Headers class implements standard Headers API (partial: get/set/has/delete)
- [x] **HTTP-02**: Request class implements standard Request API
- [x] **HTTP-03**: Response class implements standard Response API
- [x] **HTTP-04**: fetch() function makes HTTP requests with Promise support
- [ ] **HTTP-05**: AbortController and AbortSignal enable request cancellation (deferred v2)
- [ ] **HTTP-06**: FormData handles multipart form data (deferred v2)
- [ ] **HTTP-07**: Blob and File handle binary data (deferred v2)

### Crypto

- [x] **CRYP-01**: crypto.getRandomValues() fills typed arrays with random values
- [x] **CRYP-02**: crypto.randomUUID() generates RFC 4122 UUIDs
- [x] **CRYP-03**: crypto.subtle.digest() computes SHA-1, SHA-256, SHA-384, SHA-512 hashes
- [ ] **CRYP-04**: crypto.subtle.sign() and verify() handle HMAC and RSA signatures (deferred v2)

### Multi-App Hosting

- [x] **HOST-01**: Apps deploy by pointing NANO at a folder path
- [ ] **HOST-02**: App registry tracks app names and configurations (deferred v2)
- [x] **HOST-03**: HTTP server routes requests to apps by port

### Observability

- [x] **OBSV-01**: Structured JSON logging includes app name, request ID, timestamp
- [x] **OBSV-02**: HTTP errors return proper status codes and clean error messages
- [x] **OBSV-03**: Prometheus metrics endpoint exposes request count, errors, latency

### Resource Limits (Deferred to v2)

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
| CORE-01 | Phase 1 | Complete |
| CORE-02 | Phase 1 | Complete |
| CORE-03 | Phase 4 | Deferred v2 |
| CORE-04 | Phase 4 | Deferred v2 |
| WAPI-01 | Phase 2 | Complete |
| WAPI-02 | Phase 2 | Complete |
| WAPI-03 | Phase 2 | Complete |
| WAPI-04 | Phase 2 | Complete |
| WAPI-05 | Phase 6 | Complete |
| WAPI-06 | - | Deferred v2 |
| HTTP-01 | Phase 2 | Complete (partial) |
| HTTP-02 | Phase 2 | Complete |
| HTTP-03 | Phase 2 | Complete |
| HTTP-04 | Phase 6 | Complete |
| HTTP-05 | - | Deferred v2 |
| HTTP-06 | - | Deferred v2 |
| HTTP-07 | - | Deferred v2 |
| CRYP-01 | Phase 2 | Complete |
| CRYP-02 | Phase 2 | Complete |
| CRYP-03 | Phase 2 | Complete |
| CRYP-04 | - | Deferred v2 |
| HOST-01 | Phase 3 | Complete |
| HOST-02 | - | Deferred v2 |
| HOST-03 | Phase 3 | Complete |
| OBSV-01 | Phase 5 | Complete |
| OBSV-02 | Phase 3 | Complete |
| OBSV-03 | Phase 5 | Complete |
| RLIM-01 | - | Deferred v2 |
| RLIM-02 | - | Deferred v2 |
| RLIM-03 | - | Deferred v2 |

**Coverage:**
- v1 requirements: 28 total
- Complete: 18
- Partial: 1 (HTTP-01)
- Deferred v2: 9

---
*Requirements defined: 2026-01-19*
*Last updated: 2026-01-26 after Phase 6 completion*
