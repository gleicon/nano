export default {
  async fetch(request) {
    const url = new URL(request.url());

    // Test 1: Basic write and close
    if (url.pathname === "/basic") {
      const chunks = [];
      const stream = new WritableStream({
        write(chunk) {
          chunks.push(chunk);
        }
      });
      const writer = stream.getWriter();
      await writer.write("Hello");
      await writer.write("World");
      await writer.close();
      return new Response(JSON.stringify(chunks), {
        headers: { "content-type": "application/json" }
      });
    }

    // Test 2: Backpressure (desiredSize)
    if (url.pathname === "/backpressure") {
      let desiredSizes = [];
      const stream = new WritableStream({
        write(chunk) {
          // Intentionally slow write
        }
      }, { highWaterMark: 2 });
      const writer = stream.getWriter();
      desiredSizes.push(writer.desiredSize); // Should be 2
      writer.write("chunk1");
      desiredSizes.push(writer.desiredSize); // Should be 1
      writer.write("chunk2");
      desiredSizes.push(writer.desiredSize); // Should be 0
      writer.write("chunk3");
      desiredSizes.push(writer.desiredSize); // Should be -1 (backpressure)
      await writer.close();
      return new Response(JSON.stringify(desiredSizes), {
        headers: { "content-type": "application/json" }
      });
    }

    // Test 3: Abort stream
    if (url.pathname === "/abort") {
      let aborted = false;
      const stream = new WritableStream({
        write(chunk) {
          // no-op
        },
        abort(reason) {
          aborted = true;
        }
      });
      const writer = stream.getWriter();
      await writer.write("chunk");
      await writer.abort("test abort");
      return new Response(JSON.stringify({ aborted }), {
        headers: { "content-type": "application/json" }
      });
    }

    // Test 4: Error handling (sink throw)
    if (url.pathname === "/error") {
      const stream = new WritableStream({
        write(chunk) {
          if (chunk === "error") {
            throw new Error("write error");
          }
        }
      });
      const writer = stream.getWriter();
      await writer.write("ok");
      try {
        await writer.write("error");
        return new Response("ERROR: should have thrown", { status: 500 });
      } catch (e) {
        return new Response(JSON.stringify({ error: "caught" }), {
          headers: { "content-type": "application/json" }
        });
      }
    }

    // Test 5: Ready promise (backpressure signal)
    if (url.pathname === "/ready") {
      const stream = new WritableStream({
        write(chunk) {
          // Fast write
        }
      }, { highWaterMark: 1 });
      const writer = stream.getWriter();
      const ready1 = writer.ready; // Should resolve immediately (empty queue)
      await writer.write("chunk1");
      const ready2 = writer.ready; // Should resolve after write completes
      await ready2;
      await writer.close();
      return new Response(JSON.stringify({ ready: "ok" }), {
        headers: { "content-type": "application/json" }
      });
    }

    // Test 6: Buffer size overflow (1MB limit in config)
    if (url.pathname === "/buffer-overflow") {
      const chunks = [];
      const stream = new WritableStream({
        write(chunk) {
          chunks.push(chunk);
        }
      });
      const writer = stream.getWriter();
      try {
        // Write 2MB of data (exceeds 1MB limit)
        const chunk = "x".repeat(1024 * 1024); // 1MB
        await writer.write(chunk); // OK
        await writer.write(chunk); // Should reject
        return new Response("ERROR: should have rejected write", { status: 500 });
      } catch (e) {
        return new Response(JSON.stringify({
          error: "buffer overflow caught",
          message: e.message
        }), {
          headers: { "content-type": "application/json" }
        });
      }
    }

    // Test 7: Console.log formatting
    if (url.pathname === "/console-format") {
      const stream = new WritableStream({
        write(chunk) {
          // no-op
        }
      });
      // This will be verified manually via server logs
      console.log(stream);
      return new Response(JSON.stringify({ logged: true }), {
        headers: { "content-type": "application/json" }
      });
    }

    return new Response("Not Found", { status: 404 });
  }
};
