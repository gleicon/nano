export default {
  async fetch(request) {
    try {
      const url = new URL(request.url());
      const path = url.pathname(); // pathname is a method in nano

      // Test 1: String body becomes ReadableStream
      if (path === '/test-string-body') {
        const response = new Response("hello world");
        const body = response.body;
        const bodyType = body !== null ? "ReadableStream" : "null";
        const locked = body !== null ? body.locked : null;
        const hasGetReader = body !== null ? typeof body.getReader === 'function' : false;
        return new Response(JSON.stringify({ bodyType, locked, hasGetReader }), {
          headers: { "content-type": "application/json" }
        });
      }

      // Test 2: ReadableStream constructor argument (using pull to avoid start+close hang)
      if (path === '/test-stream-body') {
        let count = 0;
        const stream = new ReadableStream({
          pull(controller) {
            if (count < 2) {
              controller.enqueue("chunk" + (count + 1));
              count++;
            } else {
              controller.close();
            }
          }
        });
        const response = new Response(stream);
        const bodyType = response.body !== null ? "ReadableStream" : "null";
        const locked = response.body !== null ? response.body.locked : null;
        const isSameReference = response.body === stream;
        return new Response(JSON.stringify({ bodyType, locked, isSameReference }), {
          headers: { "content-type": "application/json" }
        });
      }

      // Test 3: Null body handling
      if (path === '/test-null-body') {
        const response = new Response(null);
        return new Response(JSON.stringify({ bodyIsNull: response.body === null }), {
          headers: { "content-type": "application/json" }
        });
      }

      // Test 4: Streaming large response via pull-based ReadableStream
      if (path === '/test-fetch-streaming') {
        let pullCount = 0;
        const stream = new ReadableStream({
          pull(controller) {
            if (pullCount < 10) {
              controller.enqueue("x".repeat(10240)); // 10KB chunks
              pullCount++;
            } else {
              controller.close();
            }
          }
        });

        const response = new Response(stream);
        const reader = response.body.getReader();

        let chunksReceived = 0;
        let totalBytes = 0;

        for (let i = 0; i < 20; i++) { // safety limit
          const result = await reader.read();
          if (result.done) break;
          chunksReceived++;
          totalBytes += result.value.length;
        }

        reader.releaseLock();

        return new Response(JSON.stringify({ chunksReceived, totalBytes }), {
          headers: { "content-type": "application/json" }
        });
      }

      // Test 5: Response.text() with stream body
      if (path === '/test-text-from-stream') {
        const parts = ["hello", " ", "world"];
        let idx = 0;
        const stream = new ReadableStream({
          pull(controller) {
            if (idx < parts.length) {
              controller.enqueue(parts[idx++]);
            } else {
              controller.close();
            }
          }
        });

        const response = new Response(stream);
        const text = await response.text();

        return new Response(JSON.stringify({
          text: text,
          expected: "hello world",
          match: text === "hello world"
        }), {
          headers: { "content-type": "application/json" }
        });
      }

      // Test 6: Response.json() with stream body
      if (path === '/test-json-from-stream') {
        let sent = false;
        const stream = new ReadableStream({
          pull(controller) {
            if (!sent) {
              controller.enqueue('{"key":"value"}');
              sent = true;
            } else {
              controller.close();
            }
          }
        });

        const response = new Response(stream);
        const parsed = await response.json();

        return new Response(JSON.stringify({
          parsed: parsed,
          keyValue: parsed.key
        }), {
          headers: { "content-type": "application/json" }
        });
      }

      return new Response(JSON.stringify({ error: "Unknown endpoint" }), {
        status: 404,
        headers: { "content-type": "application/json" }
      });
    } catch (e) {
      return new Response(JSON.stringify({ error: e.message, stack: e.stack }), {
        status: 500,
        headers: { "content-type": "application/json" }
      });
    }
  }
};
