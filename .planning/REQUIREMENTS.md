# Requirements: NANO v1.2 Production Polish

**Defined:** 2026-02-02
**Core Value:** Skip the container fleet entirely — one process hosts many isolated JS apps

## v1.2 Requirements

### Streams API

- [ ] **STRM-01**: ReadableStream class with WinterCG-compliant interface
- [ ] **STRM-02**: WritableStream class with WinterCG-compliant interface
- [ ] **STRM-03**: ReadableStreamDefaultReader with read()/cancel() methods
- [ ] **STRM-04**: ReadableStreamDefaultController with enqueue()/close()/error()
- [ ] **STRM-05**: WritableStreamDefaultWriter with write()/close()/abort()
- [ ] **STRM-06**: WritableStreamDefaultController with error() method
- [ ] **STRM-07**: Backpressure handling via desiredSize/ready promise
- [ ] **STRM-08**: Response.body returns ReadableStream for response content
- [ ] **STRM-09**: fetch() Response supports streaming body consumption

### Environment Variables

- [ ] **ENVV-01**: Config JSON supports `env` object per app definition
- [ ] **ENVV-02**: Environment variables injected as second parameter to fetch handler
- [ ] **ENVV-03**: Complete isolation — app A cannot access app B's env vars
- [ ] **ENVV-04**: Env vars updated on config reload (hot reload support)

### Graceful Shutdown

- [ ] **SHUT-01**: SIGTERM/SIGINT triggers graceful shutdown sequence
- [ ] **SHUT-02**: Stop accepting new connections on shutdown signal
- [ ] **SHUT-03**: Drain in-flight requests before exit (30s default timeout)
- [ ] **SHUT-04**: App removal via config watcher drains that app's connections
- [ ] **SHUT-05**: New requests to draining app receive 503 Service Unavailable
- [ ] **SHUT-06**: Connection tracking per app for accurate drain completion

### Documentation

- [ ] **DOCS-01**: Astro + Starlight documentation site
- [ ] **DOCS-02**: Getting started guide (install, first app, run)
- [ ] **DOCS-03**: Configuration reference (config.json schema, all options)
- [ ] **DOCS-04**: API reference (all Workers-compatible APIs)
- [ ] **DOCS-05**: WinterCG compliance documentation (what's supported)
- [ ] **DOCS-06**: Deployment guide (production setup, reverse proxy)

## Future Requirements (v1.3+)

### Streams Extensions
- **STRM-10**: TransformStream class
- **STRM-11**: BYOB (Bring Your Own Buffer) readers
- **STRM-12**: CompressionStream/DecompressionStream

### Environment Variables Extensions
- **ENVV-05**: Runtime env updates via Admin API
- **ENVV-06**: Secrets distinction (encrypted at rest)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Native C++ streams | Too complex; polyfill sufficient for v1.2 |
| BYOB readers | Advanced use case, defer to v1.3 |
| Compression streams | Defer to v1.3 |
| Admin API env updates | Config reload sufficient for v1.2 |
| Request.body streaming | Focus on Response first |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| STRM-01 | TBD | Pending |
| STRM-02 | TBD | Pending |
| STRM-03 | TBD | Pending |
| STRM-04 | TBD | Pending |
| STRM-05 | TBD | Pending |
| STRM-06 | TBD | Pending |
| STRM-07 | TBD | Pending |
| STRM-08 | TBD | Pending |
| STRM-09 | TBD | Pending |
| ENVV-01 | TBD | Pending |
| ENVV-02 | TBD | Pending |
| ENVV-03 | TBD | Pending |
| ENVV-04 | TBD | Pending |
| SHUT-01 | TBD | Pending |
| SHUT-02 | TBD | Pending |
| SHUT-03 | TBD | Pending |
| SHUT-04 | TBD | Pending |
| SHUT-05 | TBD | Pending |
| SHUT-06 | TBD | Pending |
| DOCS-01 | TBD | Pending |
| DOCS-02 | TBD | Pending |
| DOCS-03 | TBD | Pending |
| DOCS-04 | TBD | Pending |
| DOCS-05 | TBD | Pending |
| DOCS-06 | TBD | Pending |

**Coverage:**
- v1.2 requirements: 25 total
- Mapped to phases: 0
- Unmapped: 25

---
*Requirements defined: 2026-02-02*
*Last updated: 2026-02-02 after initial definition*
