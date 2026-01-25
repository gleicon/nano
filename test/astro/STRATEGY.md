# Astro Compatibility Strategy

## Why Astro?

1. **Cloudflare acquisition** - Astro is now the flagship Workers framework
2. **SSR-first** - Server-side rendering validates our core APIs
3. **Adapter pattern** - `@astrojs/cloudflare` adapter targets Workers runtime
4. **Content-focused** - Real-world workload (MDX, markdown, components)

## Compatibility Tiers

### Tier 1: Minimal (Phase 2)
Run basic Astro SSR without framework features.

**Required APIs:**
- `Request` / `Response`
- `Headers`
- `URL` / `URLSearchParams`
- `TextEncoder` / `TextDecoder`
- `crypto.randomUUID()` (for Astro's internal IDs)

**Test:** Static HTML page renders

### Tier 2: Core (Phase 3)
Run Astro with content collections and routing.

**Additional APIs:**
- `fetch()` (for data fetching in pages)
- `ReadableStream` / `WritableStream`
- `console.*` (for dev feedback)
- `setTimeout` / `clearTimeout`

**Test:** Blog with markdown content renders

### Tier 3: Full (Phase 4-5)
Production-ready Astro deployment.

**Additional APIs:**
- `crypto.subtle` (for content hashing)
- `caches` API (for edge caching)
- `waitUntil()` (for background tasks)
- Environment bindings (KV, D1, R2 equivalents)

**Test:** Full Astro site with API routes, auth, database

---

## Test Apps

### App 1: `astro-minimal`
Bare minimum SSR test.

```
astro-minimal/
├── src/pages/index.astro    # Static HTML
├── src/pages/api/ping.ts    # API route returning JSON
└── astro.config.mjs         # Cloudflare adapter
```

**Success criteria:**
- `GET /` returns HTML with correct Content-Type
- `GET /api/ping` returns `{"pong": true}`

### App 2: `astro-blog`
Content-driven site.

```
astro-blog/
├── src/content/posts/       # Markdown posts
├── src/pages/index.astro    # Post listing
├── src/pages/[slug].astro   # Dynamic routes
└── astro.config.mjs
```

**Success criteria:**
- Markdown renders to HTML
- Dynamic routes resolve correctly
- Content collections work

### App 3: `astro-full`
Production simulation.

```
astro-full/
├── src/pages/
├── src/api/
│   ├── auth.ts              # Uses crypto
│   └── data.ts              # Uses fetch
├── src/middleware.ts        # Request middleware
└── astro.config.mjs
```

**Success criteria:**
- Middleware executes
- API routes work
- External fetch works
- Crypto operations work

---

## Implementation Phases

### Phase 2 Milestone
- [ ] Create `astro-minimal` test app
- [ ] Implement missing Request/Response APIs
- [ ] Run: `nano serve astro-minimal/dist`
- [ ] Verify: Homepage renders

### Phase 3 Milestone
- [ ] Create `astro-blog` test app
- [ ] Implement fetch, streams
- [ ] Run: Multiple Astro apps on different ports
- [ ] Verify: Content collections work

### Phase 5 Milestone
- [ ] Create `astro-full` test app
- [ ] Implement crypto.subtle, caches
- [ ] Benchmark: Cold start < 5ms
- [ ] Verify: Production-ready

---

## Adapter Compatibility

Astro uses `@astrojs/cloudflare` adapter which expects:

```typescript
// Worker entry point shape
export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response>
}
```

NANO must support:
1. ES module syntax (`export default`)
2. `Request` object from incoming HTTP
3. `env` bindings (can be empty object initially)
4. `ctx.waitUntil()` for background work

---

## Reference Links

- [Astro Cloudflare Adapter](https://docs.astro.build/en/guides/integrations-guide/cloudflare/)
- [Cloudflare Workers Runtime APIs](https://developers.cloudflare.com/workers/runtime-apis/)
- [WinterCG Minimum Common API](https://common-min-api.proposal.wintercg.org/)
