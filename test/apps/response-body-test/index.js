export default {
  async fetch(request) {
    const path = request._url || '/';

    // Debug endpoint
    if (path === '/debug') {
      return Response.json({ path, hasUrl: !!request._url, request: Object.keys(request) });
    }

    // Test 1: String body becomes ReadableStream
    if (path === '/test-string-body') {
      const response = new Response("hello world");
      return Response.json({
        bodyType: response.body !== null ? "ReadableStream" : "null",
        locked: response.body !== null ? response.body.locked : undefined,
        hasGetReader: response.body !== null ? typeof response.body.getReader === 'function' : false
      });
    }

    // Test 2: ReadableStream constructor argument
    if (path === '/test-stream-body') {
      const stream = new ReadableStream({
        start(controller) {
          controller.enqueue("chunk1");
          controller.enqueue("chunk2");
          controller.close();
        }
      });
      const response = new Response(stream);
      return Response.json({
        bodyType: response.body !== null ? "ReadableStream" : "null",
        locked: response.body !== null ? response.body.locked : undefined,
        isSameReference: response.body === stream
      });
    }

    // Test 3: Null body handling
    if (path === '/test-null-body') {
      const response = new Response(null);
      return Response.json({
        bodyIsNull: response.body === null
      });
    }

    // Test 4: Streaming large response
    if (path === '/test-fetch-streaming') {
      // Create a mock large response with multiple chunks
      const stream = new ReadableStream({
        start(controller) {
          // Send 10 chunks of ~10KB each
          for (let i = 0; i < 10; i++) {
            const chunk = "x".repeat(10240); // 10KB chunk
            controller.enqueue(chunk);
          }
          controller.close();
        }
      });

      const response = new Response(stream);
      const reader = response.body.getReader();

      let chunksReceived = 0;
      let totalBytes = 0;

      while (true) {
        const {done, value} = await reader.read();
        if (done) break;
        chunksReceived++;
        totalBytes += value.length;
      }

      await reader.releaseLock();

      return Response.json({
        chunksReceived,
        totalBytes
      });
    }

    // Test 5: Response.text() with stream body
    if (path === '/test-text-from-stream') {
      const stream = new ReadableStream({
        start(controller) {
          controller.enqueue("hello");
          controller.enqueue(" ");
          controller.enqueue("world");
          controller.close();
        }
      });

      const response = new Response(stream);
      const text = await response.text();

      return Response.json({
        text: text,
        expected: "hello world",
        match: text === "hello world"
      });
    }

    // Test 6: Response.json() with stream body
    if (path === '/test-json-from-stream') {
      const stream = new ReadableStream({
        start(controller) {
          controller.enqueue('{"key":"value"}');
          controller.close();
        }
      });

      const response = new Response(stream);
      const parsed = await response.json();

      return Response.json({
        parsed: parsed,
        keyValue: parsed.key
      });
    }

    return Response.json({ error: 'Unknown endpoint' }, { status: 404 });
  }
};
