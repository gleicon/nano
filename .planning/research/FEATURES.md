# Features Research: v1.2 Production Polish

**Domain:** JavaScript isolate runtime (WinterCG-aligned)
**Researched:** 2026-02-02
**Milestone:** v1.2 Production Polish
**Confidence:** HIGH (verified against WinterTC spec, official docs, and platform implementations)

## Executive Summary

v1.2 targets three feature areas: WinterCG Streams API, graceful shutdown with connection draining, and per-app environment variables. Research confirms clear standards exist for all three. Streams has the most complexity due to WinterTC specification requirements. Graceful shutdown patterns are well-established across the ecosystem. Environment variable isolation is straightforward but requires careful security design.

---

## Streams API (WinterCG/WinterTC)

### Table Stakes

These interfaces are **mandatory** per the [WinterTC Minimum Common Web API](https://min-common-api.proposal.wintertc.org/) specification. NANO must implement all of these for WinterCG alignment.

| Interface | Purpose | Complexity | Dependencies |
|-----------|---------|------------|--------------|
| **ReadableStream** | Consume data from a source (e.g., fetch response body) | HIGH | None |
| **WritableStream** | Accept data as a destination | HIGH | None |
| **TransformStream** | Modify data as it flows through | HIGH | ReadableStream, WritableStream |
| **ReadableStreamDefaultReader** | Standard reading mechanism | MEDIUM | ReadableStream |
| **ReadableStreamBYOBReader** | Bring-your-own-buffer reading | MEDIUM | ReadableStream |
| **ReadableByteStreamController** | Controller for byte streams | MEDIUM | ReadableStream |
| **ReadableStreamDefaultController** | Controller for default streams | MEDIUM | ReadableStream |
| **ReadableStreamBYOBRequest** | BYOB request handling | LOW | ReadableStreamBYOBReader |
| **WritableStreamDefaultWriter** | Standard writing mechanism | MEDIUM | WritableStream |
| **WritableStreamDefaultController** | Controller for writable streams | MEDIUM | WritableStream |
| **TransformStreamDefaultController** | Controller for transform streams | MEDIUM | TransformStream |
| **ByteLengthQueuingStrategy** | Queuing strategy based on byte length | LOW | None |
| **CountQueuingStrategy** | Queuing strategy based on chunk count | LOW | None |

**Sources:**
- [WinterTC Minimum Common API](https://min-common-api.proposal.wintertc.org/)
- [WHATWG Streams Standard](https://streams.spec.whatwg.org/)
- [Cloudflare Workers Streams](https://developers.cloudflare.com/workers/runtime-apis/streams/)

#### Required Methods on ReadableStream

Per [MDN ReadableStream documentation](https://developer.mozilla.org/en-US/docs/Web/API/ReadableStream):

| Method | Purpose | Priority |
|--------|---------|----------|
| `cancel()` | Signal loss of interest, returns Promise | HIGH |
| `getReader()` | Create reader, lock stream | HIGH |
| `pipeTo(destination)` | Pipe to WritableStream with backpressure | HIGH |
| `pipeThrough(transform)` | Chain through TransformStream | HIGH |
| `tee()` | Split into two branches | MEDIUM |
| `[Symbol.asyncIterator]()` | Enable `for await...of` | MEDIUM |

**Note:** `pipeTo()` and `pipeThrough()` handle backpressure automatically per the WHATWG spec. Backpressure propagates backwards through the pipe chain when a destination cannot accept more data.

#### Required Methods on WritableStream

| Method | Purpose | Priority |
|--------|---------|----------|
| `getWriter()` | Create writer, lock stream | HIGH |
| `close()` | Close the stream | HIGH |
| `abort(reason)` | Abort the stream | HIGH |

#### Constructor Callbacks (Underlying Source/Sink)

**ReadableStream underlying source:**
- `start(controller)` - Called by constructor, can enqueue initial chunks
- `pull(controller)` - Called when queue is empty
- `cancel(reason)` - Called when stream is canceled

**WritableStream underlying sink:**
- `start(controller)` - Called on construction
- `write(chunk, controller)` - Called for each chunk
- `close(controller)` - Called when closing
- `abort(reason)` - Called on abort

**TransformStream transformer:**
- `start(controller)` - Called on construction
- `transform(chunk, controller)` - Called for each chunk, use `controller.enqueue()`
- `flush(controller)` - Called when all chunks processed

### Differentiators

Features that could give NANO an advantage over cloud platforms.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **ReadableStream.from()** | Create stream from async iterable | LOW | Modern convenience API, [MDN docs](https://developer.mozilla.org/en-US/docs/Web/API/ReadableStream/from_static) |
| **Native async iteration** | `for await (const chunk of stream)` | MEDIUM | Better DX than manual reader loop |
| **TextEncoderStream / TextDecoderStream** | Streaming text encoding | MEDIUM | WinterCG includes these, useful for text processing |
| **CompressionStream / DecompressionStream** | gzip/deflate streaming | MEDIUM | WinterCG mandates, useful for bandwidth |
| **Direct Response body streaming** | `new Response(readableStream)` | HIGH | Already partially supported via fetch |

**NANO-Specific Opportunity:** Since NANO runs on bare metal with direct file access, we could offer streaming file reads/writes more efficiently than edge platforms that must proxy through storage APIs.

### Anti-Features

Things to deliberately NOT implement or implement with restrictions.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Unrestricted stream lifetime** | Streams that outlive the request handler leak memory | Tie stream lifecycle to request context |
| **Unbounded internal queues** | Memory exhaustion in slow consumer scenarios | Enforce high water mark limits |
| **Synchronous stream reads** | Blocks the isolate | All stream reads must be async |
| **Streams outside request context** | Cloudflare explicitly limits Streams to request context | Document limitation, enforce at runtime |

**Warning from Cloudflare:** "The Streams API is only available inside of the Request context." NANO should follow this pattern to prevent resource leaks.

### Implementation Complexity Assessment

| Component | Estimated LOC | Risk Level | Notes |
|-----------|---------------|------------|-------|
| ReadableStream core | 400-600 | HIGH | Most complex, many edge cases |
| WritableStream core | 300-400 | MEDIUM | Simpler than ReadableStream |
| TransformStream | 200-300 | MEDIUM | Combines Read+Write |
| Controllers (4 types) | 400-500 | MEDIUM | State machine management |
| Readers/Writers | 200-300 | LOW | Relatively straightforward |
| Queuing strategies | 50-100 | LOW | Simple calculation |
| Backpressure handling | 200-300 | HIGH | Critical for correctness |
| **Total** | ~1800-2500 | HIGH | Significant undertaking |

### Integration with Existing NANO Features

| Existing Feature | Integration Point | Notes |
|-----------------|-------------------|-------|
| fetch() Response.body | Must return ReadableStream | Currently returns full body |
| fetch() Request body | Should accept ReadableStream | For streaming uploads |
| FormData | Uses Blob which uses ReadableStream | May need updates |
| TextEncoder/TextDecoder | Used by TextEncoderStream/TextDecoderStream | Already implemented |

---

## Graceful Shutdown

### Table Stakes

Behaviors users universally expect when a process or app is shutting down.

| Behavior | Why Expected | Complexity | Notes |
|----------|--------------|------------|-------|
| **Handle SIGTERM** | Standard Unix shutdown signal | LOW | Process signal handling |
| **Handle SIGINT** | Ctrl+C during development | LOW | Process signal handling |
| **Stop accepting new connections** | Prevent new work during shutdown | LOW | `server.close()` equivalent |
| **Drain in-flight requests** | Complete work already started | MEDIUM | Track active requests |
| **Configurable timeout** | Force exit if drain takes too long | LOW | Typically 5-30 seconds |
| **SIGKILL after timeout** | Guaranteed exit | LOW | Process terminates |

**Sources:**
- [Node.js Graceful Shutdown Best Practices](https://blog.risingstack.com/graceful-shutdown-node-js-kubernetes/)
- [PM2 Graceful Shutdown](https://pm2.io/docs/runtime/best-practices/graceful-shutdown/)
- [Bun Server Stop](https://bun.com/docs/runtime/http/server)

#### Standard Shutdown Sequence

Per industry best practices:

```
1. SIGTERM received
2. Stop accepting new connections immediately
3. Allow in-flight requests to complete (up to timeout)
4. Close database connections, flush logs
5. Exit process gracefully

If timeout exceeded:
6. Force close remaining connections
7. Exit with non-zero status (optional)
```

#### Two Shutdown Contexts for NANO

NANO has two distinct shutdown scenarios:

| Context | Trigger | Scope | Notes |
|---------|---------|-------|-------|
| **App Removal** | Admin API DELETE or config change | Single app | Other apps continue running |
| **Process Shutdown** | SIGTERM/SIGINT to main process | All apps | Full server shutdown |

**App Removal Flow:**
1. Mark app as "draining" - reject new requests with 503
2. Wait for in-flight requests to that app to complete
3. Destroy V8 isolate
4. Remove from routing table

**Process Shutdown Flow:**
1. Stop accepting new connections on server socket
2. Mark all apps as "draining"
3. Wait for all in-flight requests across all apps
4. Destroy all isolates
5. Exit process

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Per-app drain status** | Show which apps are draining via Admin API | LOW | Operational visibility |
| **Configurable per-app timeout** | Different drain times per app | LOW | Some apps need longer |
| **Pre-shutdown hooks** | Notify apps before shutdown | MEDIUM | `addEventListener('shutdown')` |
| **Request count visibility** | `pendingRequests` per app | LOW | Like Bun's API |
| **Zero-downtime app reload** | Remove + add atomically | MEDIUM | Already have hot reload |

**NANO-Specific Opportunity:** Since NANO manages multiple apps, we can offer granular control over which apps drain and when, with per-app visibility through the Admin API.

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Immediate process.exit()** | Drops in-flight requests, loses data | Always drain first |
| **Unlimited drain timeout** | Process hangs forever in Kubernetes | Cap at reasonable max (e.g., 5 min) |
| **Silent shutdown** | No visibility into what's happening | Log shutdown events, provide hooks |
| **Keep-alive connection leak** | Connections stay open preventing shutdown | Track and close keep-alive connections |

**Critical Warning:** Keep-alive connections prevent `server.close()` from completing. Must track all connections and explicitly close them after timeout.

### Integration with Existing NANO Features

| Existing Feature | Integration Point | Notes |
|-----------------|-------------------|-------|
| Admin API DELETE /admin/apps | Should drain before removing | Currently removes immediately |
| Admin API POST /admin/reload | Should drain changed apps | Currently reloads immediately |
| Config file watcher | Removed apps should drain | Same as admin API |
| Multi-app routing | Must track in-flight requests per app | New state needed |

---

## Per-App Environment Variables

### Table Stakes

Standard approach across all Workers-compatible platforms.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Config-defined env vars** | Define vars in config, not code | LOW | JSON/TOML config |
| **Access via env object** | `env.MY_VAR` in handler | LOW | Passed to fetch handler |
| **String values** | Simple key-value strings | LOW | Basic requirement |
| **Complete isolation** | App A cannot see App B's vars | LOW | Separate env objects per isolate |
| **Local development override** | `.env` file for local vars | LOW | Standard DX pattern |

**Sources:**
- [Cloudflare Workers Environment Variables](https://developers.cloudflare.com/workers/configuration/environment-variables/)
- [Deno Deploy Environment Variables](https://docs.deno.com/deploy/reference/env_vars_and_contexts/)
- [Vercel Edge Runtime](https://vercel.com/docs/functions/runtimes/edge)

#### Cloudflare Workers Pattern

```toml
# wrangler.toml
[vars]
API_HOST = "https://api.example.com"
API_VERSION = "v2"
```

```javascript
export default {
  async fetch(request, env, ctx) {
    // env.API_HOST, env.API_VERSION available here
  }
}
```

#### NANO Config Pattern (Proposed)

```json
{
  "apps": [
    {
      "hostname": "api.example.com",
      "path": "./apps/api",
      "env": {
        "DATABASE_URL": "postgres://...",
        "API_KEY": "secret123"
      }
    }
  ]
}
```

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **JSON values** | Objects/arrays in env, not just strings | LOW | Cloudflare supports this |
| **Secrets vs vars distinction** | Encrypted vs plaintext | MEDIUM | Important for security |
| **Environment-specific files** | `.env.production`, `.env.development` | LOW | Common DX pattern |
| **Admin API env management** | GET/PUT env vars at runtime | MEDIUM | Hot-update without reload |
| **Env var validation** | Schema validation on load | LOW | Fail fast on missing required vars |
| **process.env compatibility** | `process.env.VAR` access | LOW | Node.js compat flag |

**NANO-Specific Opportunity:** Since NANO has full Admin API, we can offer runtime env var updates without app restart - something edge platforms typically don't support.

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Global process.env** | Cross-app leakage risk | Isolated env object per app |
| **Env vars in code** | Secrets in git | Config file or Admin API |
| **No secrets distinction** | Sensitive values logged/exposed | Redact in logs, separate handling |
| **Mutable env at runtime from app code** | Confusing state | Env is read-only from app perspective |

**Security Warning:** Per [Cloudflare docs](https://developers.cloudflare.com/workers/configuration/secrets/): "Do not use vars to store sensitive information. Use secrets instead."

### Implementation Considerations

| Consideration | Approach | Notes |
|---------------|----------|-------|
| **Storage location** | Config JSON, separate secrets file | Keep secrets out of main config |
| **Memory isolation** | Each isolate gets copy of its env | No shared references |
| **Admin API access** | Auth required for env management | Prevent unauthorized access |
| **Logging** | Redact env values in logs | Prevent secret leakage |
| **Hot reload** | Env changes apply on next request | Don't restart isolate |

### Integration with Existing NANO Features

| Existing Feature | Integration Point | Notes |
|-----------------|-------------------|-------|
| Config parser | Add `env` field per app | Extend existing parser |
| V8 isolate creation | Inject env object into context | At isolate setup |
| Admin API | Add GET/PUT /admin/apps/:hostname/env | New endpoints |
| Logging | Redact env values | Sanitization layer |

---

## Feature Dependencies Matrix

Understanding dependencies for phase ordering.

```
Streams API
  |-> fetch() Response.body (streams enable streaming responses)
  |-> TextEncoder/TextDecoder (already implemented)
  |-> AbortController (already implemented)

Graceful Shutdown
  |-> Admin API (already implemented)
  |-> Multi-app routing (already implemented)
  |-> NEW: Request tracking per app

Per-App Env Vars
  |-> Config parser (already implemented)
  |-> V8 isolate setup (already implemented)
  |-> Admin API (already implemented)
```

### Recommended Implementation Order

1. **Per-App Environment Variables** (Lowest complexity, no dependencies)
   - Extend config parser
   - Inject env object into isolate
   - Add Admin API endpoints

2. **Graceful Shutdown** (Medium complexity, needs request tracking)
   - Add in-flight request tracking
   - Implement drain logic for app removal
   - Implement process shutdown handling

3. **Streams API** (Highest complexity, largest scope)
   - Start with ReadableStream core
   - Add WritableStream
   - Add TransformStream
   - Integrate with fetch() Response.body

---

## Resource Limits for New Features

| Resource | Recommendation | Rationale |
|----------|----------------|-----------|
| **Stream buffer size** | 64KB high water mark | Balance memory vs throughput |
| **Drain timeout** | 30 seconds default | Long enough for most requests |
| **Max env vars per app** | 128 | Match Cloudflare paid tier |
| **Max env value size** | 5KB | Prevent abuse, sufficient for tokens |

---

## Sources

### WinterCG/WinterTC
- [WinterTC Minimum Common Web API](https://min-common-api.proposal.wintertc.org/)
- [WinterTC FAQ](https://wintertc.org/faq)
- [WinterCG to WinterTC Transition](https://www.w3.org/community/wintercg/2025/01/10/goodbye-wintercg-welcome-wintertc/)

### Streams Specification
- [WHATWG Streams Standard](https://streams.spec.whatwg.org/)
- [MDN ReadableStream](https://developer.mozilla.org/en-US/docs/Web/API/ReadableStream)
- [MDN WritableStream](https://developer.mozilla.org/en-US/docs/Web/API/WritableStream)
- [MDN TransformStream](https://developer.mozilla.org/en-US/docs/Web/API/TransformStream)
- [web.dev Streams Guide](https://web.dev/articles/streams)

### Platform Implementations
- [Cloudflare Workers Streams](https://developers.cloudflare.com/workers/runtime-apis/streams/)
- [Cloudflare Workers Environment Variables](https://developers.cloudflare.com/workers/configuration/environment-variables/)
- [Cloudflare Workers Secrets](https://developers.cloudflare.com/workers/configuration/secrets/)
- [Cloudflare Workers Context (waitUntil)](https://developers.cloudflare.com/workers/runtime-apis/context/)
- [Cloudflare waitUntil Import](https://developers.cloudflare.com/changelog/2025-08-08-add-waituntil-cloudflare-workers/)
- [Deno Environment Variables](https://docs.deno.com/runtime/reference/env_variables/)
- [Vercel Edge Runtime](https://vercel.com/docs/functions/runtimes/edge)
- [Vercel Edge Config](https://vercel.com/docs/edge-config)
- [Bun Server API](https://bun.com/docs/runtime/http/server)

### Graceful Shutdown
- [Node.js Graceful Shutdown with Kubernetes](https://blog.risingstack.com/graceful-shutdown-node-js-kubernetes/)
- [PM2 Graceful Shutdown](https://pm2.io/docs/runtime/best-practices/graceful-shutdown/)
- [Hono + Bun Graceful Shutdown Discussion](https://github.com/orgs/honojs/discussions/3731)
- [Cloudflare Containers Lifecycle](https://developers.cloudflare.com/containers/platform-details/architecture/)

### Security Model
- [Cloudflare Workers Security Model](https://developers.cloudflare.com/workers/reference/security-model/)
- [V8 Isolates and Edge Runtime](https://medium.com/@jade.awesome.fisher/edge-runtime-its-not-magic-it-s-v8-isolates-c07c7547bea2)

---

## Confidence Assessment

| Area | Level | Rationale |
|------|-------|-----------|
| Streams API Spec | HIGH | Verified against WinterTC and WHATWG specs |
| Graceful Shutdown | HIGH | Well-established patterns across ecosystem |
| Per-App Env Vars | HIGH | Standard approach across all platforms |
| Implementation Complexity | MEDIUM | Estimates based on spec complexity |
| Integration Points | HIGH | Based on existing NANO codebase review |
