export default {
  async fetch(request) {
    const url = new URL(request.url());

    // Test 1: Basic enqueue and read
    if (url.pathname === "/basic") {
      const stream = new ReadableStream({
        start(controller) {
          controller.enqueue("Hello");
          controller.enqueue("World");
          controller.close();
        }
      });
      const reader = stream.getReader();
      const results = [];
      let done = false;
      while (!done) {
        const result = await reader.read();
        results.push(result);
        done = result.done;
      }
      return new Response(JSON.stringify(results), {
        headers: { "content-type": "application/json" }
      });
    }

    // Test 2: Pull callback (backpressure simulation)
    if (url.pathname === "/pull") {
      let i = 0;
      const stream = new ReadableStream({
        pull(controller) {
          if (i < 3) {
            controller.enqueue(`chunk${i++}`);
          } else {
            controller.close();
          }
        }
      });
      const reader = stream.getReader();
      const results = [];
      let done = false;
      while (!done) {
        const result = await reader.read();
        results.push(result);
        done = result.done;
      }
      return new Response(JSON.stringify(results), {
        headers: { "content-type": "application/json" }
      });
    }

    // Test 3: Cancel stream
    if (url.pathname === "/cancel") {
      let cancelled = false;
      const stream = new ReadableStream({
        start(controller) {
          controller.enqueue("first");
        },
        cancel(reason) {
          cancelled = true;
        }
      });
      const reader = stream.getReader();
      await reader.read();
      await reader.cancel("test cancel");
      return new Response(JSON.stringify({ cancelled }), {
        headers: { "content-type": "application/json" }
      });
    }

    // Test 4: Error handling
    if (url.pathname === "/error") {
      const stream = new ReadableStream({
        start(controller) {
          controller.enqueue("ok");
          controller.error(new Error("stream error"));
        }
      });
      const reader = stream.getReader();
      await reader.read(); // ok
      try {
        await reader.read(); // should throw
        return new Response("ERROR: should have thrown", { status: 500 });
      } catch (e) {
        return new Response(JSON.stringify({ error: "caught" }), {
          headers: { "content-type": "application/json" }
        });
      }
    }

    // Test 5: Buffer size overflow (1MB limit in config)
    if (url.pathname === "/buffer-overflow") {
      try {
        const stream = new ReadableStream({
          start(controller) {
            // Enqueue 2MB of data (exceeds 1MB limit)
            const chunk = "x".repeat(1024 * 1024); // 1MB
            controller.enqueue(chunk); // OK
            controller.enqueue(chunk); // Should error stream
          }
        });
        return new Response("ERROR: should have errored stream", { status: 500 });
      } catch (e) {
        return new Response(JSON.stringify({
          error: "buffer overflow caught",
          message: e.message
        }), {
          headers: { "content-type": "application/json" }
        });
      }
    }

    // Test 6: Locked property
    if (url.pathname === "/locked") {
      const stream = new ReadableStream({
        start(controller) {
          controller.enqueue("test");
          controller.close();
        }
      });
      const lockedBefore = stream.locked;
      const reader = stream.getReader();
      const lockedAfter = stream.locked;
      reader.releaseLock();
      const lockedReleased = stream.locked;

      return new Response(JSON.stringify({
        lockedBefore,
        lockedAfter,
        lockedReleased
      }), {
        headers: { "content-type": "application/json" }
      });
    }

    return new Response("Not Found", { status: 404 });
  }
};
