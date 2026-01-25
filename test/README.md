# NANO Test Fixtures

## Phase 1: Basic Execution
```bash
# Single expression
./zig-out/bin/nano eval "1 + 1"
# Expected: 2

# Multi-line script
./zig-out/bin/nano eval "$(cat test/fixtures/basic.js)"
# Expected: {"result":2,"greeting":"hello world"}

# Syntax error
./zig-out/bin/nano eval "function() {"
# Expected: Error with line number, exit code 1
```

## Phase 2: Workers APIs
```bash
./zig-out/bin/nano eval "$(cat test/fixtures/phase2-apis.js)"
# Currently fails - APIs not implemented
# Success criteria:
# - console.log appears in stderr/stdout
# - TextEncoder/Decoder work
# - URL parsing works
# - crypto.subtle.digest returns hash
# - fetch() makes HTTP request
```

## Phase 3: Isolation Tests

### Setup
```bash
# Start app-a on port 3001
./zig-out/bin/nano serve test/fixtures/apps/app-a --port 3001 &

# Start app-b on port 3002
./zig-out/bin/nano serve test/fixtures/apps/app-b --port 3002 &
```

### Verify Isolation
```bash
# App A response
curl http://localhost:3001
# Expected: sees own APP_SECRET, sharedData
# Expected: appBSecret = "not-found"

# App B response
curl http://localhost:3002
# Expected: sees own APP_B_SECRET
# Expected: appASecret = "not-found"
# Expected: sharedData = "not-found"
# Expected: globalKeys only contains ["APP_B_SECRET", "APP_NAME"]
```

### Isolation Criteria (MUST PASS)
1. App A cannot read App B's globalThis properties
2. App B cannot read App A's globalThis properties
3. Global pollution in one app doesn't affect others
4. Each app has independent memory space
