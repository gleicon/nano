// Security: Fetch restrictions
// Status: Should FAIL until Phase 2, then PASS
// These fetches must be BLOCKED by the runtime

async function testFetchSecurity() {
  const blocked = [];
  const allowed = [];

  async function expectBlocked(url, reason) {
    try {
      await fetch(url);
      allowed.push({ url, reason, status: "FAIL - should be blocked" });
    } catch (e) {
      blocked.push({ url, reason, status: "PASS - blocked" });
    }
  }

  async function expectAllowed(url) {
    try {
      const r = await fetch(url);
      allowed.push({ url, status: "PASS", code: r.status });
    } catch (e) {
      blocked.push({ url, status: "FAIL - should be allowed", error: e.message });
    }
  }

  // MUST BLOCK: file:// protocol
  await expectBlocked("file:///etc/passwd", "file protocol");
  await expectBlocked("file:///etc/shadow", "file protocol");

  // MUST BLOCK: localhost variants
  await expectBlocked("http://localhost/", "localhost");
  await expectBlocked("http://localhost:3000/", "localhost with port");
  await expectBlocked("http://127.0.0.1/", "loopback IPv4");
  await expectBlocked("http://[::1]/", "loopback IPv6");
  await expectBlocked("http://0.0.0.0/", "all interfaces");

  // MUST BLOCK: private IP ranges (RFC 1918)
  await expectBlocked("http://10.0.0.1/", "private 10.x");
  await expectBlocked("http://172.16.0.1/", "private 172.16.x");
  await expectBlocked("http://192.168.1.1/", "private 192.168.x");

  // MUST BLOCK: link-local
  await expectBlocked("http://169.254.169.254/", "AWS metadata");
  await expectBlocked("http://metadata.google.internal/", "GCP metadata");

  // SHOULD ALLOW: public HTTPS
  await expectAllowed("https://httpbin.org/status/200");

  return JSON.stringify({
    test: "fetch-security",
    passed: blocked.length >= 10 && allowed.length >= 1,
    blocked,
    allowed
  }, null, 2);
}

testFetchSecurity();
