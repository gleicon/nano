# Environment Variable Isolation Testing

## Test Configuration

This directory contains test configuration for verifying:
- ENVV-03: Environment variable isolation between apps
- ENVV-04: Hot reload updates environment variables safely

## Manual Test Steps

### 1. Isolation Test

Start the server:
```bash
./zig-out/bin/nano serve --config test/env-isolation/nano.json
```

In separate terminal, test App A:
```bash
curl -H "Host: a.local" http://localhost:8080/
# Expected: {"API_KEY":"key-a","APP_NAME":"A"}
```

Test App B:
```bash
curl -H "Host: b.local" http://localhost:8080/
# Expected: {"API_KEY":"key-b","APP_NAME":"B"}
```

### 2. Hot Reload Test

While server is running, modify `nano.json`:
```bash
# Change app-a's API_KEY from "key-a" to "key-a-updated"
```

Wait 3 seconds for config reload, then test:
```bash
curl -H "Host: a.local" http://localhost:8080/
# Expected: {"API_KEY":"key-a-updated","APP_NAME":"A"}
```

Verify no crash occurred - this validates no use-after-free when AppConfig is freed.

### 3. Memory Safety Test

Run with leak detection:
```bash
leaks -atExit -- ./zig-out/bin/nano serve --config test/env-isolation/nano.json
```

Send requests, trigger hot reload multiple times, send more requests.
Stop server and check for leaks.

Expected: No "definitely lost" memory, no use-after-free errors.

## Implementation Notes

- **Deep Copy:** App owns its env HashMap (not a reference to AppConfig.env)
- **Hot Reload Safety:** When config reloads, new App gets fresh copy of new env
- **Cleanup:** App.deinit frees all env keys, values, and HashMap
- **Isolation:** Each App has its own HashMap - no sharing
