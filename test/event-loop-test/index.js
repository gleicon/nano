// Comprehensive Event Loop & Async Regression Test
// Covers: timers, Promises, async fetch, concurrent fetch, WritableStream (sync + async),
// ReadableStream, large buffers, blocking I/O interleaving, error handling.
//
// Use /test-all for a single-request regression check or /test-<name> for individual tests.

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;

    // ─── Individual test endpoints ───

    if (path === "/test-timer-basic") {
      // Verify setTimeout fires and callback executes
      // Note: Date.now() precision in embedded V8 may not reflect real wall time,
      // so we only check that the timer actually fired (not elapsed time accuracy).
      let fired = false;
      await new Promise(resolve => setTimeout(() => { fired = true; resolve(); }, 50));
      return json({ pass: fired, fired });
    }

    if (path === "/test-timer-ordering") {
      const order = [];
      await new Promise(resolve => {
        setTimeout(() => order.push('a'), 10);
        setTimeout(() => order.push('b'), 20);
        setTimeout(() => { order.push('c'); resolve(); }, 30);
      });
      return json({ pass: order.join(',') === 'a,b,c', order: order.join(',') });
    }

    if (path === "/test-promise-basic") {
      const val = await Promise.resolve(42).then(v => v * 2);
      return json({ pass: val === 84, val });
    }

    if (path === "/test-promise-all") {
      const [a, b, c] = await Promise.all([
        Promise.resolve(1),
        new Promise(resolve => setTimeout(() => resolve(2), 10)),
        Promise.resolve(3)
      ]);
      return json({ pass: a === 1 && b === 2 && c === 3, values: [a, b, c] });
    }

    if (path === "/test-async-fetch") {
      let timerFired = false;
      setTimeout(() => { timerFired = true; }, 10);
      const resp = await fetch("https://httpbin.org/get");
      const text = await resp.text();
      return json({
        pass: timerFired && resp.status === 200 && text.length > 50,
        timer_fired: timerFired, status: resp.status, body_len: text.length
      });
    }

    if (path === "/test-concurrent-fetch") {
      const [r1, r2] = await Promise.all([
        fetch("https://httpbin.org/get"),
        fetch("https://httpbin.org/ip")
      ]);
      const [t1, t2] = await Promise.all([r1.text(), r2.text()]);
      return json({
        pass: r1.status === 200 && r2.status === 200 && t1.length > 0 && t2.length > 0,
        fetch1_status: r1.status, fetch2_status: r2.status
      });
    }

    if (path === "/test-fetch-json") {
      const resp = await fetch("https://httpbin.org/get");
      const data = await resp.json();
      return json({
        pass: typeof data === 'object' && data.url === 'https://httpbin.org/get',
        has_url: !!data.url
      });
    }

    if (path === "/test-fetch-error") {
      try {
        await fetch("https://this-domain-does-not-exist-12345.invalid/");
        return json({ pass: false, error: "should have thrown" });
      } catch (e) {
        return json({ pass: true, error: String(e) });
      }
    }

    if (path === "/test-writable-sync") {
      const chunks = [];
      const stream = new WritableStream({ write(chunk) { chunks.push(chunk); } });
      const writer = stream.getWriter();
      await writer.write('x'); await writer.write('y'); await writer.write('z');
      await writer.close();
      return json({ pass: chunks.join(',') === 'x,y,z', chunks: chunks.join(',') });
    }

    if (path === "/test-writable-async") {
      const chunks = [];
      const stream = new WritableStream({
        write(chunk) {
          return new Promise(resolve => {
            setTimeout(() => { chunks.push(chunk); resolve(); }, 10);
          });
        }
      });
      const writer = stream.getWriter();
      await writer.write('a'); await writer.write('b'); await writer.write('c');
      await writer.close();
      return json({ pass: chunks.join(',') === 'a,b,c', chunks: chunks.join(','), count: chunks.length });
    }

    if (path === "/test-writable-error") {
      const stream = new WritableStream({
        write(chunk) { throw new Error("sink error: " + chunk); }
      });
      const writer = stream.getWriter();
      try {
        await writer.write('bad');
        return json({ pass: false, error: "should have thrown" });
      } catch (e) {
        return json({ pass: String(e).includes("sink error"), error: String(e) });
      }
    }

    if (path === "/test-readable-basic") {
      let i = 0;
      const stream = new ReadableStream({
        pull(controller) {
          if (i < 3) { controller.enqueue("chunk" + i); i++; }
          else controller.close();
        }
      });
      const reader = stream.getReader();
      const chunks = [];
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        chunks.push(value);
      }
      return json({ pass: chunks.join(',') === 'chunk0,chunk1,chunk2', chunks: chunks.join(',') });
    }

    if (path === "/test-blob-large") {
      const size = 1024 * 1024;
      const big = "B".repeat(size);
      const blob = new Blob([big]);
      const text = await blob.text();
      return json({ pass: text.length === size, blob_size: blob.size, text_len: text.length });
    }

    if (path === "/test-encoding-large") {
      const big = "A".repeat(50000);
      const encoded = btoa(big);
      const decoded = atob(encoded);
      return json({ pass: decoded === big, original: big.length, encoded: encoded.length, decoded: decoded.length });
    }

    if (path === "/test-mixed-async") {
      const timerResult = await new Promise(resolve => setTimeout(() => resolve("timer-ok"), 20));
      const fetchResp = await fetch("https://httpbin.org/ip");
      const fetchData = await fetchResp.json();
      const promiseVal = await Promise.resolve(99);
      return json({
        pass: timerResult === "timer-ok" && fetchResp.status === 200 && promiseVal === 99,
        timer: timerResult, fetch_status: fetchResp.status, promise_val: promiseVal
      });
    }

    // ─── Run all local tests (no network) ───
    if (path === "/test-all-local") {
      const results = {};
      // Timer tests
      try {
        let fired = false;
        await new Promise(resolve => setTimeout(() => { fired = true; resolve(); }, 50));
        results["timer-basic"] = fired ? "PASS" : "FAIL";
      } catch(e) { results["timer-basic"] = "ERROR: " + e; }

      try {
        const order = [];
        await new Promise(resolve => {
          setTimeout(() => order.push('a'), 10);
          setTimeout(() => order.push('b'), 20);
          setTimeout(() => { order.push('c'); resolve(); }, 30);
        });
        results["timer-ordering"] = order.join(',') === 'a,b,c' ? "PASS" : "FAIL: " + order.join(',');
      } catch(e) { results["timer-ordering"] = "ERROR: " + e; }

      // Promise tests
      try {
        const val = await Promise.resolve(42).then(v => v * 2);
        results["promise-basic"] = val === 84 ? "PASS" : "FAIL: " + val;
      } catch(e) { results["promise-basic"] = "ERROR: " + e; }

      try {
        const [a, b, c] = await Promise.all([
          Promise.resolve(1),
          new Promise(resolve => setTimeout(() => resolve(2), 10)),
          Promise.resolve(3)
        ]);
        results["promise-all"] = (a===1 && b===2 && c===3) ? "PASS" : "FAIL";
      } catch(e) { results["promise-all"] = "ERROR: " + e; }

      // WritableStream sync
      try {
        const chunks = [];
        const stream = new WritableStream({ write(chunk) { chunks.push(chunk); } });
        const writer = stream.getWriter();
        await writer.write('x'); await writer.write('y'); await writer.write('z');
        await writer.close();
        results["writable-sync"] = chunks.join(',') === 'x,y,z' ? "PASS" : "FAIL: " + chunks.join(',');
      } catch(e) { results["writable-sync"] = "ERROR: " + e; }

      // WritableStream async
      try {
        const chunks = [];
        const stream = new WritableStream({
          write(chunk) {
            return new Promise(resolve => {
              setTimeout(() => { chunks.push(chunk); resolve(); }, 10);
            });
          }
        });
        const writer = stream.getWriter();
        await writer.write('a'); await writer.write('b'); await writer.write('c');
        await writer.close();
        results["writable-async"] = chunks.join(',') === 'a,b,c' ? "PASS" : "FAIL: " + chunks.join(',');
      } catch(e) { results["writable-async"] = "ERROR: " + e; }

      // WritableStream error
      try {
        const stream = new WritableStream({ write(chunk) { throw new Error("sink error"); } });
        const writer = stream.getWriter();
        await writer.write('bad');
        results["writable-error"] = "FAIL: should have thrown";
      } catch(e) {
        results["writable-error"] = String(e).includes("sink error") ? "PASS" : "FAIL: " + e;
      }

      // ReadableStream
      try {
        let i = 0;
        const stream = new ReadableStream({
          pull(controller) {
            if (i < 3) { controller.enqueue("chunk" + i); i++; }
            else controller.close();
          }
        });
        const reader = stream.getReader();
        const chunks = [];
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          chunks.push(value);
        }
        results["readable-basic"] = chunks.join(',') === 'chunk0,chunk1,chunk2' ? "PASS" : "FAIL: " + chunks.join(',');
      } catch(e) { results["readable-basic"] = "ERROR: " + e; }

      // Blob large
      try {
        const size = 1024 * 1024;
        const blob = new Blob(["B".repeat(size)]);
        const text = await blob.text();
        results["blob-large"] = text.length === size ? "PASS" : "FAIL: " + text.length;
      } catch(e) { results["blob-large"] = "ERROR: " + e; }

      // Encoding large
      try {
        const big = "A".repeat(50000);
        const decoded = atob(btoa(big));
        results["encoding-large"] = decoded === big ? "PASS" : "FAIL";
      } catch(e) { results["encoding-large"] = "ERROR: " + e; }

      const total = Object.keys(results).length;
      const passed = Object.values(results).filter(v => v === "PASS").length;
      return json({ total, passed, failed: total - passed, results });
    }

    // ─── Edge case & known issue tests ───

    if (path === "/test-deep-promise-chain") {
      let val = Promise.resolve(0);
      for (let i = 0; i < 100; i++) val = val.then(v => v + 1);
      const result = await val;
      return json({ pass: result === 100, result });
    }

    if (path === "/test-writable-many-sync") {
      const chunks = [];
      const stream = new WritableStream({ write(chunk) { chunks.push(chunk); } });
      const writer = stream.getWriter();
      for (let i = 0; i < 50; i++) await writer.write("w" + i);
      await writer.close();
      return json({ pass: chunks.length === 50, count: chunks.length });
    }

    if (path === "/test-writable-many-async") {
      const chunks = [];
      const stream = new WritableStream({
        write(chunk) {
          return new Promise(resolve => setTimeout(() => { chunks.push(chunk); resolve(); }, 1));
        }
      });
      const writer = stream.getWriter();
      for (let i = 0; i < 10; i++) await writer.write("a" + i);
      await writer.close();
      return json({ pass: chunks.length === 10, count: chunks.length });
    }

    if (path === "/test-ssrf-blocked") {
      try {
        await fetch("http://127.0.0.1:8080/anything");
        return json({ pass: false, error: "should have been blocked" });
      } catch (e) {
        return json({ pass: String(e).includes("BlockedHost"), error: String(e) });
      }
    }

    if (path === "/test-sequential-fetches") {
      const results = [];
      for (let i = 0; i < 3; i++) {
        const resp = await fetch("https://httpbin.org/get?seq=" + i);
        results.push(resp.status);
      }
      return json({ pass: results.every(s => s === 200), statuses: results });
    }

    // Promise that never resolves — should return 500 after handler timeout
    if (path === "/test-promise-never-resolves") {
      return new Promise(() => {});
    }

    // [KNOWN ISSUE] ReadableStream start() with sync close causes hang
    if (path === "/test-start-sync-close") {
      try {
        const stream = new ReadableStream({
          start(controller) {
            controller.enqueue("only-chunk");
            controller.close();
          }
        });
        const reader = stream.getReader();
        const { value } = await reader.read();
        return json({ pass: value === "only-chunk", value, issue: "start() sync close" });
      } catch (e) {
        return json({ pass: false, error: String(e), issue: "start() sync close" });
      }
    }

    // ─── Run all edge case tests (local) ───
    if (path === "/test-edge-cases") {
      const results = {};

      try {
        let val = Promise.resolve(0);
        for (let i = 0; i < 100; i++) val = val.then(v => v + 1);
        results["deep-promise-chain"] = (await val) === 100 ? "PASS" : "FAIL";
      } catch(e) { results["deep-promise-chain"] = "ERROR: " + e; }

      try {
        const chunks = [];
        const stream = new WritableStream({ write(chunk) { chunks.push(chunk); } });
        const writer = stream.getWriter();
        for (let i = 0; i < 50; i++) await writer.write("w" + i);
        await writer.close();
        results["writable-many-sync"] = chunks.length === 50 ? "PASS" : "FAIL: " + chunks.length;
      } catch(e) { results["writable-many-sync"] = "ERROR: " + e; }

      try {
        const chunks = [];
        const stream = new WritableStream({
          write(chunk) {
            return new Promise(resolve => setTimeout(() => { chunks.push(chunk); resolve(); }, 1));
          }
        });
        const writer = stream.getWriter();
        for (let i = 0; i < 10; i++) await writer.write("a" + i);
        await writer.close();
        results["writable-many-async"] = chunks.length === 10 ? "PASS" : "FAIL: " + chunks.length;
      } catch(e) { results["writable-many-async"] = "ERROR: " + e; }

      try {
        await fetch("http://127.0.0.1:8080/anything");
        results["ssrf-blocked"] = "FAIL: should block";
      } catch(e) {
        results["ssrf-blocked"] = String(e).includes("BlockedHost") ? "PASS" : "FAIL: " + e;
      }

      const total = Object.keys(results).length;
      const passed = Object.values(results).filter(v => v === "PASS").length;
      return json({ total, passed, failed: total - passed, results });
    }

    return new Response("Event Loop Test Server\nEndpoints: /test-all-local, /test-edge-cases, /test-<name>");
  }
};

function json(data) {
  return new Response(JSON.stringify(data), { headers: { "Content-Type": "application/json" } });
}
