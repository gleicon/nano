export default {
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/test-async") {
      // Test that fetch is non-blocking: setTimeout should fire while fetch is in-flight
      let timerFired = false;
      setTimeout(() => { timerFired = true; }, 10);

      const resp = await fetch("https://httpbin.org/get");
      const text = await resp.text();
      return new Response(JSON.stringify({
        timer_fired: timerFired,
        status: resp.status,
        body_len: text.length,
        body_preview: text.substring(0, 50)
      }), { headers: { "Content-Type": "application/json" } });
    }

    if (path === "/test-concurrent") {
      // Test two concurrent fetches
      const [r1, r2] = await Promise.all([
        fetch("https://httpbin.org/get"),
        fetch("https://httpbin.org/ip")
      ]);
      const [t1, t2] = await Promise.all([r1.text(), r2.text()]);
      return new Response(JSON.stringify({
        fetch1_status: r1.status,
        fetch1_len: t1.length,
        fetch2_status: r2.status,
        fetch2_len: t2.length
      }), { headers: { "Content-Type": "application/json" } });
    }

    if (path === "/test-writable-async") {
      // Test WritableStream with async sink
      const results = [];
      const stream = new WritableStream({
        write(chunk) {
          return new Promise((resolve) => {
            setTimeout(() => {
              results.push(chunk);
              resolve();
            }, 10);
          });
        }
      });

      const writer = stream.getWriter();
      await writer.write('chunk1');
      await writer.write('chunk2');
      await writer.write('chunk3');
      await writer.close();

      return new Response(JSON.stringify({
        order: results.join(','),
        count: results.length
      }), { headers: { "Content-Type": "application/json" } });
    }

    if (path === "/test-writable-sync") {
      // Regression test: sync sink still works
      const results = [];
      const stream = new WritableStream({
        write(chunk) {
          results.push(chunk);
          // No Promise returned — sync sink
        }
      });

      const writer = stream.getWriter();
      await writer.write('a');
      await writer.write('b');
      await writer.write('c');
      await writer.close();

      return new Response(JSON.stringify({
        order: results.join(','),
        count: results.length
      }), { headers: { "Content-Type": "application/json" } });
    }

    return new Response("async test server - paths: /test-async, /test-concurrent, /test-writable-async, /test-writable-sync");
  }
};
