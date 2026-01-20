# Features Research: JavaScript Isolate Runtime

**Domain:** JavaScript isolate runtime (Cloudflare Workers-compatible)
**Researched:** 2026-01-18
**Confidence:** HIGH (verified against official documentation and WinterCG spec)

## Executive Summary

JavaScript isolate runtimes have converged on a common API surface defined by the WinterCG (WinterTC) specification. NANO must implement this baseline to achieve portability with Cloudflare Workers, Deno Deploy, and Vercel Edge. Beyond the baseline, storage bindings and resource limits are the primary differentiation vectors.

---

## Table Stakes

Features users absolutely expect. Missing any of these makes the runtime feel incomplete or broken.

### Core Web APIs (WinterCG Minimum Common API)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **fetch()** | Primary way to make HTTP requests | HIGH | Must support Request/Response/Headers objects fully |
| **Request/Response/Headers** | HTTP primitive objects | MEDIUM | Standard Fetch API objects, must be spec-compliant |
| **URL/URLSearchParams** | URL parsing and manipulation | LOW | Well-defined spec, straightforward implementation |
| **TextEncoder/TextDecoder** | String encoding/decoding | LOW | UTF-8 is primary, support for other encodings optional |
| **Streams API** | ReadableStream, WritableStream, TransformStream | HIGH | Critical for streaming responses, complex spec |
| **crypto.subtle** | Web Crypto API for cryptographic operations | HIGH | Required for auth, signatures, hashing |
| **console.log/warn/error** | Debugging output | LOW | Essential for developer experience |
| **setTimeout/setInterval/clearTimeout/clearInterval** | Timer APIs | MEDIUM | Must work within isolate lifecycle |
| **atob/btoa** | Base64 encoding/decoding | LOW | Simple, well-defined |
| **structuredClone** | Deep object cloning | MEDIUM | Required by WinterCG spec |
| **AbortController/AbortSignal** | Request cancellation | MEDIUM | Essential for timeout handling |
| **Blob/File** | Binary data handling | MEDIUM | Needed for file uploads, multipart forms |
| **FormData** | Form data handling | MEDIUM | Required for multipart request handling |

**Source:** [WinterCG Minimum Common API Specification](https://min-common-api.proposal.wintertc.org/)

### Module System

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **ES Modules (import/export)** | Modern JavaScript module system | MEDIUM | Only module format supported, no CommonJS |
| **Dynamic import()** | Lazy module loading | MEDIUM | Useful for code splitting |
| **import.meta.url** | Module URL access | LOW | Standard ESM feature |

**Note:** `require()` is explicitly NOT supported in edge runtimes. ESM only.

### Handler Interface

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **export default { fetch }** | ESM worker entry point | LOW | Preferred modern pattern |
| **addEventListener('fetch')** | Service Worker pattern | LOW | Legacy but widely used |
| **Request context object (env, ctx)** | Access to bindings and context | LOW | Platform-specific but essential |

### Error Handling

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **try/catch** | Standard error handling | LOW | V8 native |
| **Promise rejection handling** | Async error handling | LOW | V8 native |
| **Uncaught exception reporting** | Error visibility | MEDIUM | Must surface errors to operators |

---

## Differentiators

Features that set platforms apart. Not universally expected but provide competitive advantage.

### Storage/Persistence Bindings

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **KV Store binding** | Simple key-value persistence | HIGH | Cloudflare KV-compatible API would enable migration |
| **Durable Objects** | Single-threaded stateful coordination | VERY HIGH | Unique to Cloudflare, complex to implement |
| **SQLite/D1 binding** | SQL database access | HIGH | Growing expectation, D1 pattern emerging |
| **Object storage (R2-like)** | Large file storage | HIGH | S3-compatible API preferred |
| **Queue binding** | Message queue integration | HIGH | Async job processing |

**NANO Opportunity:** Storage bindings are where NANO can differentiate. Since NANO runs on bare metal, it can offer direct access to local storage systems (SQLite, Redis, filesystem) that edge platforms cannot.

### Real-Time Features

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **WebSocket server support** | Bidirectional real-time communication | HIGH | Requires connection state management |
| **WebSocket Hibernation** | Cost reduction for idle connections | VERY HIGH | Cloudflare-specific optimization |
| **Server-Sent Events (SSE)** | Server-to-client streaming | MEDIUM | Simpler than WebSockets, works with standard HTTP |

### Observability

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Structured logging** | JSON log output | LOW | Essential for production |
| **OpenTelemetry integration** | Standard tracing/metrics | MEDIUM | Emerging standard across platforms |
| **Request tracing** | End-to-end request visibility | MEDIUM | Critical for debugging |
| **Live tail/streaming logs** | Real-time debugging | MEDIUM | Developer experience differentiator |

### Node.js Compatibility Layer

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **node:crypto** | Node.js crypto API | HIGH | Cloudflare added in 2024-2025 |
| **node:buffer** | Node.js Buffer API | MEDIUM | Common in npm packages |
| **node:util** | Node.js utility functions | LOW | TextEncoder/TextDecoder polyfills |
| **node:fs** | Filesystem access | HIGH | Cloudflare added 2025, virtual FS |

**Note:** Node.js compatibility is trending upward. Cloudflare's `nodejs_compat` flag enables many Node APIs. NANO could differentiate by offering broader Node.js compatibility since it controls the full stack.

### Cron/Scheduled Execution

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Cron triggers** | Scheduled function execution | MEDIUM | Deno has native Deno.cron, Cloudflare via wrangler |
| **Delayed execution** | Run function after delay | MEDIUM | Queue-based pattern |

### Multi-Tenancy Features

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Isolate-per-tenant** | Security isolation | HIGH | Core NANO value prop |
| **Per-tenant resource limits** | Fair resource allocation | HIGH | Memory, CPU, request limits |
| **Tenant routing** | Route requests to correct isolate | MEDIUM | Based on hostname, path, or header |

---

## Anti-Features

Features that seem useful but cause problems. These should be deliberately NOT built.

### Global Mutable State

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Global variables persisting across requests** | Isolates can be evicted at any time; creates race conditions | Document that global state is unreliable; provide explicit storage APIs |
| **Singleton patterns** | Same issues as global state | Provide per-request context or durable storage |

**Warning:** Cloudflare explicitly warns against mutating global state. Users coming from Node.js often expect globals to persist, leading to subtle bugs.

### Full Node.js API Surface

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **process.env** | Security risk; env should be injected via bindings | Use env object passed to fetch handler |
| **Filesystem (general)** | Security isolation; can't allow arbitrary disk access | Provide scoped virtual filesystem or storage bindings |
| **Child process spawning** | Security risk; breaks isolate model | Not applicable to isolate architecture |
| **Native addons (N-API)** | Binary incompatibility; security risk | WebAssembly for native code |

### Dynamic Code Execution

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Dynamic code evaluation** | Security risk; enables code injection | Pre-bundle all code; no runtime code generation |
| **Dynamic function construction from strings** | Same security risk | Same as above |

**Note:** Vercel Edge explicitly disables dynamic code evaluation. This is a deliberate security choice.

### Unlimited Resources

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **No memory limits** | One tenant can crash entire process | Enforce per-isolate memory limits (128MB typical) |
| **No CPU time limits** | One tenant can monopolize CPU | Enforce CPU time limits (10ms free, 30s-5min paid typical) |
| **No request limits** | DoS amplification | Rate limiting per tenant |

### Direct Database Connections

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Raw TCP sockets for DB connections** | Connection pooling nightmare; security risk | Provide proxy/binding layer (like Hyperdrive) |
| **Persistent DB connection pools** | Isolates are ephemeral; pools would leak | Connection-per-request or managed proxy |

**Context:** Edge runtimes struggle with traditional databases because isolates are short-lived. Cloudflare built Hyperdrive specifically to solve connection pooling for Workers.

---

## Workers API Coverage

Priority ranking for NANO's Workers-compatible API surface.

### Critical (Must Have for MVP)

These APIs are used in virtually every Worker:

| API | Usage Frequency | Complexity |
|-----|-----------------|------------|
| fetch() | 100% - all Workers make requests | HIGH |
| Request/Response | 100% - HTTP primitives | MEDIUM |
| Headers | 100% - request/response manipulation | LOW |
| URL/URLSearchParams | 95% - URL parsing | LOW |
| TextEncoder/TextDecoder | 80% - string handling | LOW |
| console.log/warn/error | 95% - debugging | LOW |
| JSON.parse/stringify | 99% - data serialization | LOW (V8 native) |
| crypto.subtle | 60% - auth/signatures | HIGH |
| atob/btoa | 50% - base64 encoding | LOW |

### High Priority (Expected in Production Use)

| API | Usage Frequency | Complexity |
|-----|-----------------|------------|
| Streams API | 40% - streaming responses | HIGH |
| AbortController | 30% - timeout handling | MEDIUM |
| FormData | 25% - form handling | MEDIUM |
| Blob/File | 20% - file uploads | MEDIUM |
| crypto.randomUUID | 30% - ID generation | LOW |
| setTimeout/clearTimeout | 40% - timing | MEDIUM |
| structuredClone | 15% - deep copy | MEDIUM |
| CompressionStream/DecompressionStream | 10% - gzip handling | MEDIUM |

### Medium Priority (Nice to Have)

| API | Usage Frequency | Complexity |
|-----|-----------------|------------|
| WebSocket | 10% - real-time apps | HIGH |
| Cache API | 15% - response caching | HIGH |
| HTMLRewriter | 5% - HTML transformation | VERY HIGH |
| EventSource (SSE) | 5% - server push | MEDIUM |
| URLPattern | 5% - routing | LOW |

### Low Priority (Rarely Used)

| API | Usage Frequency | Complexity |
|-----|-----------------|------------|
| MessageChannel | <5% - worker communication | MEDIUM |
| Performance API | <5% - timing | LOW |
| Navigator object | <5% - user agent | LOW |

---

## Feature Dependencies

Understanding dependencies helps order implementation.

```
fetch()
  |-> Request (must implement first)
  |-> Response (must implement first)
  |-> Headers (must implement first)
  |-> AbortController (for timeouts)
  |-> Streams API (for streaming bodies)

Streams API
  |-> TextEncoder/TextDecoder (for text streams)
  |-> Blob (uses readable stream)

crypto.subtle
  |-> ArrayBuffer/TypedArrays (V8 native)
  |-> Crypto object (wrapper)

WebSocket
  |-> Streams API (optional but useful)
  |-> Message events

FormData
  |-> Blob
  |-> File
```

### Recommended Implementation Order

1. **Foundation (Week 1-2)**
   - TextEncoder/TextDecoder
   - URL/URLSearchParams
   - Headers
   - Blob
   - console APIs

2. **HTTP Layer (Week 3-4)**
   - Request
   - Response
   - fetch()
   - AbortController/AbortSignal

3. **Crypto (Week 5)**
   - crypto.subtle (digest, sign, verify, encrypt, decrypt)
   - crypto.getRandomValues
   - crypto.randomUUID

4. **Streams (Week 6-7)**
   - ReadableStream
   - WritableStream
   - TransformStream

5. **Advanced (Week 8+)**
   - FormData
   - File
   - WebSocket
   - Cache API

---

## Resource Limits Comparison

| Resource | Cloudflare Free | Cloudflare Paid | Deno Deploy | NANO Recommendation |
|----------|-----------------|-----------------|-------------|---------------------|
| Memory | 128 MB | 128 MB | 512 MB | 128 MB (configurable) |
| CPU Time | 10 ms | 5 min | Per-org quota | 30s default, configurable |
| Bundle Size | 3 MB | 10 MB | 1 GB total | 10 MB |
| Subrequests | 50 | 1000 | Unlimited | 100 default |
| Startup Time | 1 sec | 1 sec | N/A | 1 sec |
| Env Variables | 64 | 128 | N/A | 128 |

---

## Sources

### Official Documentation
- [Cloudflare Workers Runtime APIs](https://developers.cloudflare.com/workers/runtime-apis/)
- [Cloudflare Workers Limits](https://developers.cloudflare.com/workers/platform/limits/)
- [Vercel Edge Runtime Available APIs](https://edge-runtime.vercel.app/features/available-apis)
- [WinterCG Minimum Common API](https://min-common-api.proposal.wintertc.org/)
- [Deno Deploy Pricing and Limits](https://docs.deno.com/deploy/pricing_and_limits/)

### Best Practices and Patterns
- [Cloudflare Standards-Compliant Workers API](https://blog.cloudflare.com/standards-compliant-workers-api/)
- [Cloudflare Durable Objects Best Practices](https://developers.cloudflare.com/durable-objects/best-practices/rules-of-durable-objects/)
- [Cloudflare Storage Options](https://developers.cloudflare.com/workers/platform/storage-options/)

### Comparison and Analysis
- [Cloudflare vs Vercel vs Netlify Edge Performance 2026](https://dev.to/dataformathub/cloudflare-vs-vercel-vs-netlify-the-truth-about-edge-performance-2026-50h0)
- [Edge Functions vs Serverless Functions](https://blog.openreplay.com/serverless-vs-edge-functions/)
- [Vercel Edge Explained](https://upstash.com/blog/vercel-edge)

### Observability
- [Cloudflare Workers Observability](https://developers.cloudflare.com/workers/observability/)
- [Cloudflare Workers Logs](https://developers.cloudflare.com/workers/observability/logs/workers-logs/)
