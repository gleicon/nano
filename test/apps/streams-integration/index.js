export default {
  async fetch(request) {
    const url = new URL(request.url());
    const pathname = url.pathname(); // pathname is a method in nano

    // Test 1: Transform stream pipeline
    if (pathname === "/transform") {
      const source = new ReadableStream({
        start(controller) {
          controller.enqueue("hello");
          controller.enqueue("world");
          controller.close();
        }
      });

      const upperTransform = new TransformStream({
        transform(chunk, controller) {
          controller.enqueue(chunk.toUpperCase());
        }
      });

      const chunks = [];
      const destination = new WritableStream({
        write(chunk) { chunks.push(chunk); }
      });

      await source.pipeThrough(upperTransform).pipeTo(destination);
      return new Response(JSON.stringify(chunks));
    }

    // Test 2: Tee operation
    if (pathname === "/tee") {
      const source = new ReadableStream({
        start(controller) {
          controller.enqueue("a");
          controller.enqueue("b");
          controller.close();
        }
      });

      const [branch1, branch2] = source.tee();

      const results1 = [];
      const results2 = [];

      await branch1.pipeTo(new WritableStream({
        write(chunk) { results1.push(chunk); }
      }));

      await branch2.pipeTo(new WritableStream({
        write(chunk) { results2.push(chunk); }
      }));

      return new Response(JSON.stringify({ branch1: results1, branch2: results2 }));
    }

    // Test 3: ReadableStream.from()
    if (pathname === "/from") {
      const stream = ReadableStream.from([1, 2, 3, 4, 5]);
      const chunks = [];
      await stream.pipeTo(new WritableStream({
        write(chunk) { chunks.push(chunk); }
      }));
      return new Response(JSON.stringify(chunks));
    }

    // Test 4: Text streams
    if (pathname === "/text-streams") {
      const source = new ReadableStream({
        start(controller) {
          controller.enqueue("Hello");
          controller.enqueue("World");
          controller.close();
        }
      });

      // Encode to bytes
      const encoder = new TextEncoderStream();
      const decoder = new TextDecoderStream();

      // Pipeline: string -> bytes -> string
      const result = source.pipeThrough(encoder).pipeThrough(decoder);

      const chunks = [];
      await result.pipeTo(new WritableStream({
        write(chunk) { chunks.push(chunk); }
      }));

      return new Response(JSON.stringify(chunks));
    }

    return new Response("Test suite - try /transform, /tee, /from, /text-streams", { status: 200 });
  }
};
