# fetch() Analysis

## Current State
- `fetch()` throws: "fetch() is not available - NANO v1.0 uses synchronous request handlers"
- Response class exists and works for returning responses from handlers
- Request class exists for parsing incoming requests

## The Question: Do We Need fetch()?

### What fetch() Would Enable
1. **Outbound HTTP requests** - call external APIs from JS handlers
2. **Service composition** - proxy requests, aggregate data from multiple sources
3. **Webhooks** - forward events to external services

### The Async Problem
Standard `fetch()` returns a Promise. This requires:
1. **V8 Promise integration** - hook into V8's microtask queue
2. **Event loop** - run pending promises between request handling
3. **Async HTTP client** - non-blocking network I/O in Zig

Current NANO is strictly synchronous:
- One request at a time
- No event loop
- No promise execution

### Options

#### Option A: No fetch() (Current)
- Handlers are pure functions: Request → Response
- All data must come from request or be precomputed
- Use case: edge compute, simple transformations, routing

**Pros:**
- Simpler runtime
- Predictable latency
- No async complexity

**Cons:**
- Cannot call external APIs
- Limited use cases

#### Option B: Synchronous fetch()
- Block on HTTP request, return result directly
- No promises, no async

```javascript
// Hypothetical synchronous API
const data = fetchSync("https://api.example.com/data");
return Response.json(data);
```

**Pros:**
- Simple mental model
- No event loop needed

**Cons:**
- Blocks entire server during outbound request
- Terrible for concurrent requests
- Non-standard API

#### Option C: Full Async (Major Rework)
- Implement event loop
- Promise support
- async/await handlers

```javascript
export default {
  async fetch(request) {
    const data = await fetch("https://api.example.com");
    return Response.json(await data.json());
  }
}
```

**Pros:**
- Standard Cloudflare Workers compatibility
- Full fetch() API

**Cons:**
- Significant implementation effort
- V8 microtask integration
- Requires threading or async I/O

## Recommendation

For NANO v1.0, keep Option A (no fetch). Document clearly:
- NANO handles incoming requests only
- For outbound HTTP, use different architecture patterns:
  - Sidecar proxy
  - Message queues
  - Pre-aggregated data

For NANO v2.0, consider:
- Option C with proper async support
- Or a hybrid where "bindings" provide sync access to external data

## Decision Needed
- [ ] Confirm v1.0 scope: no outbound fetch
- [ ] Decide v2.0 direction: async vs sync fetch
