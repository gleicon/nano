export default {
  async fetch(request) {
    const url = new URL(request.url());
    const path = url.pathname();

    // === crypto.subtle Promise returns ===
    if (path === "/crypto-digest") {
      const data = new TextEncoder().encode("hello");
      const hash = await crypto.subtle.digest("SHA-256", data);
      return new Response(JSON.stringify({
        ok: hash instanceof ArrayBuffer,
        byteLength: hash.byteLength
      }), { headers: { "content-type": "application/json" } });
    }

    if (path === "/crypto-sign-verify") {
      const algo = { name: "HMAC", hash: "SHA-256" };
      const key = { raw: new TextEncoder().encode("secret-key-1234567890123456") };
      const data = new TextEncoder().encode("test data");
      const sig = await crypto.subtle.sign(algo, key, data);
      const valid = await crypto.subtle.verify(algo, key, sig, data);
      return new Response(JSON.stringify({
        signed: sig instanceof ArrayBuffer,
        sigBytes: sig.byteLength,
        valid: valid
      }), { headers: { "content-type": "application/json" } });
    }

    // === Request.text() / Request.json() Promise returns ===
    if (path === "/request-text") {
      const req = new Request("https://example.com", {
        method: "POST",
        body: "hello world"
      });
      const text = await req.text();
      return new Response(JSON.stringify({
        ok: typeof text === "string",
        value: text
      }), { headers: { "content-type": "application/json" } });
    }

    if (path === "/request-json") {
      const req = new Request("https://example.com", {
        method: "POST",
        body: '{"key":"value"}'
      });
      const obj = await req.json();
      return new Response(JSON.stringify({
        ok: obj.key === "value"
      }), { headers: { "content-type": "application/json" } });
    }

    // === Headers constructor with init object ===
    if (path === "/headers-init") {
      const h = new Headers({
        "Content-Type": "text/html",
        "X-Custom": "test"
      });
      return new Response(JSON.stringify({
        ct: h.get("content-type"),
        custom: h.get("x-custom"),
        has: h.has("content-type"),
        missing: h.has("nonexistent")
      }), { headers: { "content-type": "application/json" } });
    }

    // === Blob.slice() actual data ===
    if (path === "/blob-slice") {
      const blob = new Blob(["Hello, World!"]);
      const sliced = blob.slice(0, 5);
      const text = await sliced.text();
      return new Response(JSON.stringify({
        original: blob.size,
        slicedSize: sliced.size,
        text: text
      }), { headers: { "content-type": "application/json" } });
    }

    // === AbortSignal.timeout() ===
    if (path === "/abort-timeout") {
      const signal = AbortSignal.timeout(5000);
      return new Response(JSON.stringify({
        aborted: signal.aborted,
        hasReason: signal.reason !== undefined
      }), { headers: { "content-type": "application/json" } });
    }

    // === AbortController + AbortSignal.abort() ===
    if (path === "/abort-controller") {
      const controller = new AbortController();
      const sig = controller.signal();
      const before = sig.aborted;
      controller.abort("test reason");
      const after = sig.aborted;
      return new Response(JSON.stringify({
        before: before,
        after: after,
        reason: sig.reason
      }), { headers: { "content-type": "application/json" } });
    }

    // === ReadableStream basic (start-based, sync) ===
    if (path === "/stream-basic") {
      const stream = new ReadableStream({
        pull(controller) {
          controller.enqueue("hello");
          controller.close();
        }
      });
      const reader = stream.getReader();
      const r1 = await reader.read();
      const r2 = await reader.read();
      return new Response(JSON.stringify({
        value: r1.value,
        done1: r1.done,
        done2: r2.done
      }), { headers: { "content-type": "application/json" } });
    }

    // === ReadableStream async pending reads (pull-based, 2 reads) ===
    if (path === "/stream-async-pull") {
      let count = 0;
      const stream = new ReadableStream({
        pull(controller) {
          count++;
          if (count <= 2) {
            controller.enqueue("chunk" + count);
          } else {
            controller.close();
          }
        }
      });
      const reader = stream.getReader();
      const r1 = await reader.read();
      const r2 = await reader.read();
      const r3 = await reader.read();
      return new Response(JSON.stringify({
        r1: r1,
        r2: r2,
        r3done: r3.done,
        count: count
      }), { headers: { "content-type": "application/json" } });
    }

    // === ReadableStream closedPromise (uses pull pattern) ===
    if (path === "/stream-closed-promise") {
      let sent = false;
      const stream = new ReadableStream({
        pull(controller) {
          if (!sent) {
            controller.enqueue("data");
            sent = true;
          } else {
            controller.close();
          }
        }
      });
      const reader = stream.getReader();
      const r1 = await reader.read(); // consume data
      const r2 = await reader.read(); // done: true
      // closed promise should resolve
      await reader.closed;
      return new Response(JSON.stringify({
        value: r1.value,
        done2: r2.done,
        closedResolved: true
      }), { headers: { "content-type": "application/json" } });
    }

    // === WritableStream releaseLock ===
    if (path === "/writable-release-lock") {
      let written = [];
      const stream = new WritableStream({
        write(chunk) { written.push(chunk); }
      });
      const writer = stream.getWriter();
      await writer.write("hello");
      writer.releaseLock();
      // After release, stream should be unlocked
      const locked = stream.locked;
      return new Response(JSON.stringify({
        written: written,
        lockedAfterRelease: locked
      }), { headers: { "content-type": "application/json" } });
    }

    // === WritableStream close-after-drain ===
    if (path === "/writable-close-drain") {
      let chunks = [];
      let closeCalled = false;
      const stream = new WritableStream({
        write(chunk) { chunks.push(chunk); },
        close() { closeCalled = true; }
      });
      const writer = stream.getWriter();
      await writer.write("a");
      await writer.write("b");
      await writer.close();
      return new Response(JSON.stringify({
        chunks: chunks,
        closeCalled: closeCalled
      }), { headers: { "content-type": "application/json" } });
    }

    // === Large response body (> 64KB) ===
    if (path === "/large-response") {
      const size = 100000; // 100KB
      const body = "x".repeat(size);
      return new Response(body, {
        headers: { "content-type": "text/plain" }
      });
    }

    // === Summary endpoint: run all tests ===
    if (path === "/all") {
      const results = {};
      const tests = [
        "/crypto-digest", "/crypto-verify",
        "/request-text", "/request-json",
        "/headers-init",
        "/blob-slice",
        "/abort-timeout", "/abort-controller",
        "/stream-async-pull", "/stream-closed-promise",
        "/writable-release-lock", "/writable-close-drain",
        "/large-response"
      ];
      return new Response(JSON.stringify({
        tests: tests,
        note: "Run each test individually via its path"
      }), { headers: { "content-type": "application/json" } });
    }

    return new Response("Not Found", { status: 404 });
  }
};
