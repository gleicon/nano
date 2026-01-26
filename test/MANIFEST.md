# NANO Test Manifest

## Astro Compatibility (Primary Target)
See `test/astro/STRATEGY.md` for full plan.

| App | Phase | Status | Tests |
|-----|-------|--------|-------|
| astro-minimal | 2 | [ ] | Basic SSR, API routes |
| astro-blog | 3 | [ ] | Content, dynamic routes |
| astro-full | 5 | [ ] | Auth, fetch, crypto |

## Test Strategy
- **TDD**: Tests written before implementation - expected to FAIL initially
- **Security-first**: Each feature has security tests alongside functional tests
- **Spec compliance**: Tests reference Workers API / WinterCG specs

## Test Status Legend
- `[ ]` Not implemented (test should FAIL)
- `[P]` Partial (some tests pass)
- `[x]` Complete (all tests pass)

---

## Phase 1: V8 Foundation ✓ COMPLETE
| Test | Status | File | Verified |
|------|--------|------|----------|
| Basic arithmetic | [x] | phase1/eval.js | 2026-01-24 |
| String operations | [x] | phase1/eval.js | 2026-01-24 |
| JSON parse/stringify | [x] | phase1/eval.js | 2026-01-24 |
| Syntax error messages | [x] | phase1/errors.js | 2026-01-24 |
| Runtime error messages | [x] | phase1/errors.js | 2026-01-24 |

---

## Phase 2: API Surface

### Console API
| Test | Status | File | Security |
|------|--------|------|----------|
| console.log output | [ ] | phase2/console.js | N/A |
| console.error output | [ ] | phase2/console.js | N/A |
| console.warn output | [ ] | phase2/console.js | N/A |

### Encoding APIs
| Test | Status | File | Security |
|------|--------|------|----------|
| TextEncoder | [ ] | phase2/encoding.js | N/A |
| TextDecoder | [ ] | phase2/encoding.js | N/A |
| atob/btoa | [ ] | phase2/encoding.js | N/A |

### URL APIs
| Test | Status | File | Security |
|------|--------|------|----------|
| URL parsing | [ ] | phase2/url.js | N/A |
| URLSearchParams | [ ] | phase2/url.js | N/A |

### Crypto APIs
| Test | Status | File | Security |
|------|--------|------|----------|
| crypto.randomUUID | [x] | phase2/crypto.js | |
| crypto.getRandomValues | [x] | phase2/crypto.js | sec/crypto.js |
| crypto.subtle.digest | [x] | phase2/crypto.js | sec/crypto.js |
| crypto.subtle.sign | [x] | phase2/v2-apis.js | CRYP-04 |
| crypto.subtle.verify | [x] | phase2/v2-apis.js | CRYP-04 |

### Fetch API
| Test | Status | File | Security |
|------|--------|------|----------|
| GET request | [ ] | phase2/fetch.js | sec/fetch.js |
| POST request | [ ] | phase2/fetch.js | sec/fetch.js |
| Headers API | [ ] | phase2/fetch.js | |
| Response API | [ ] | phase2/fetch.js | |
| Request API | [ ] | phase2/fetch.js | |
| **SSRF prevention** | [ ] | | sec/fetch.js |
| **No file:// access** | [ ] | | sec/fetch.js |
| **No internal IPs** | [ ] | | sec/fetch.js |

### Blob/File APIs (HTTP-06/07)
| Test | Status | File | Security |
|------|--------|------|----------|
| Blob creation | [x] | phase2/v2-apis.js | |
| Blob.size | [x] | phase2/v2-apis.js | |
| Blob.type | [x] | phase2/v2-apis.js | |
| File creation | [x] | phase2/v2-apis.js | |
| File.name | [x] | phase2/v2-apis.js | |
| File.lastModified | [x] | phase2/v2-apis.js | |

### FormData API (HTTP-06)
| Test | Status | File | Security |
|------|--------|------|----------|
| FormData.append | [x] | phase2/v2-apis.js | |
| FormData.get | [x] | phase2/v2-apis.js | |
| FormData.getAll | [x] | phase2/v2-apis.js | |
| FormData.has | [x] | phase2/v2-apis.js | |
| FormData.set | [x] | phase2/v2-apis.js | |
| FormData.delete | [x] | phase2/v2-apis.js | |
| FormData.entries | [x] | phase2/v2-apis.js | |
| FormData.keys | [x] | phase2/v2-apis.js | |
| FormData.values | [x] | phase2/v2-apis.js | |

### AbortController API (HTTP-05)
| Test | Status | File | Security |
|------|--------|------|----------|
| AbortController creation | [x] | phase2/v2-apis.js | |
| AbortController.abort | [x] | phase2/v2-apis.js | |
| AbortSignal.aborted | [x] | phase2/v2-apis.js | |
| AbortSignal.reason | [x] | phase2/v2-apis.js | |

### Streams API
| Test | Status | File | Security |
|------|--------|------|----------|
| ReadableStream | [ ] | phase2/streams.js | |
| WritableStream | [ ] | phase2/streams.js | |
| TransformStream | [ ] | phase2/streams.js | |

---

## Phase 3: Multi-App Hosting

### HTTP Server
| Test | Status | File | Security |
|------|--------|------|----------|
| Basic request/response | [ ] | phase3/http.js | |
| Route by port | [ ] | phase3/routing.js | |
| Headers forwarding | [ ] | phase3/http.js | |

### Isolation
| Test | Status | File | Security |
|------|--------|------|----------|
| **globalThis isolated** | [ ] | | sec/isolation.js |
| **No cross-app data** | [ ] | | sec/isolation.js |
| **Prototype isolation** | [ ] | | sec/isolation.js |

---

## Phase 4: Snapshots + Pooling
| Test | Status | File | Security |
|------|--------|------|----------|
| Cold start < 5ms | [ ] | phase4/perf.js | |
| Snapshot load | [ ] | phase4/snapshot.js | |
| Isolate reuse | [ ] | phase4/pooling.js | sec/pooling.js |
| **No state leak on reuse** | [ ] | | sec/pooling.js |

---

## Phase 5: Production Hardening

### Resource Limits (RLIM-01, RLIM-02)
| Test | Status | File | Security |
|------|--------|------|----------|
| CPU timeout (5s default) | [x] | phase5/limits.js | sec/limits.js |
| Memory limit (128MB) | [x] | phase5/limits.js | sec/limits.js |
| **Infinite loop terminates** | [x] | | sec/limits.js |
| **Memory bomb contained** | [P] | | sec/limits.js |

### Observability
| Test | Status | File | Security |
|------|--------|------|----------|
| Structured logging | [ ] | phase5/logging.js | |
| Prometheus metrics | [ ] | phase5/metrics.js | |

---

## Security Test Categories

### sec/no-node-apis.js
- `process` undefined
- `require` undefined
- `__dirname` undefined
- `__filename` undefined
- `Buffer` (Node's) undefined

### sec/no-runtime-apis.js
- `Deno` undefined
- `Bun` undefined

### sec/fetch.js
- Cannot fetch `file://`
- Cannot fetch `localhost` / `127.0.0.1` / `::1`
- Cannot fetch private IPs (10.x, 172.16.x, 192.168.x)
- Cannot fetch metadata endpoints (169.254.169.254)

### sec/isolation.js
- App A cannot see App B globals
- Prototype changes don't leak
- Timers don't persist across requests

### sec/limits.js
- `while(true){}` terminates
- `new Array(1e9)` fails gracefully
