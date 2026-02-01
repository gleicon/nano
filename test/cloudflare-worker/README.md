# Cloudflare Workers Compatibility Demo

This demo showcases NANO's compatibility with the Cloudflare Workers API.

## Run

```bash
nano serve --port 8787 --app ./test/cloudflare-worker
```

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | HTML documentation page |
| `/api/hello` | GET | JSON response with request metadata |
| `/api/crypto` | GET | crypto.randomUUID() and crypto.subtle.digest() |
| `/api/headers` | GET | Echo request headers |
| `/api/json` | POST | Parse and return JSON body |
| `/api/kv/:key` | GET/PUT/DELETE | Simulated KV store |
| `/api/redirect` | GET | HTTP 302 redirect |

## Tested APIs

- `Request` - url(), method(), headers(), text(), json()
- `Response` - constructor, Response.json(), Response.redirect()
- `Headers` - get(), set(), has()
- `URL` - constructor, pathname, searchParams
- `crypto` - randomUUID(), getRandomValues(), subtle.digest()
- `TextEncoder` / `TextDecoder`
- `btoa` / `atob`
- `console.log` / `console.error`

## Example Usage

```bash
# Hello endpoint
curl http://localhost:8787/api/hello

# Crypto demo
curl http://localhost:8787/api/crypto

# Post JSON
curl -X POST -H "Content-Type: application/json" \
  -d '{"name":"test","value":42}' \
  http://localhost:8787/api/json

# KV store
curl -X PUT -d "my value" http://localhost:8787/api/kv/mykey
curl http://localhost:8787/api/kv/mykey
curl -X DELETE http://localhost:8787/api/kv/mykey
```

## Cloudflare Workers Compatibility

This demo uses the standard `export default { fetch() {} }` pattern that works on:
- Cloudflare Workers
- Deno Deploy
- NANO

The same code can run on any of these platforms with minimal changes.
