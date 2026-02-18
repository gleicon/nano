---
title: Streams
description: ReadableStream, WritableStream, and TransformStream APIs
sidebar:
  order: 11
  badge:
    text: WinterCG
    variant: success
---

NANO implements the WinterCG Streams API: ReadableStream, WritableStream, and TransformStream. These provide efficient handling of streaming data like HTTP responses, file processing, and data transformation.

## ReadableStream

A source of streaming data that can be read chunk by chunk.

### Constructor

Create a ReadableStream with an underlying source.

```javascript
const stream = new ReadableStream({
  start(controller) {
    // Called immediately when stream is created
    controller.enqueue("Hello, ");
    controller.enqueue("world!");
    controller.close();
  },

  pull(controller) {
    // Called when consumer wants more data (optional)
  },

  cancel(reason) {
    // Called when stream is cancelled (optional)
  }
});
```

**Controller methods:**
- `controller.enqueue(chunk)` - Add chunk to stream
- `controller.close()` - Close stream (no more data)
- `controller.error(error)` - Signal error

### Properties

#### locked

Returns `true` if stream has an active reader.

```javascript
const stream = new ReadableStream({
  start(controller) {
    controller.enqueue("data");
    controller.close();
  }
});

console.log(stream.locked); // false

const reader = stream.getReader();
console.log(stream.locked); // true

reader.releaseLock();
console.log(stream.locked); // false
```

**Type:** `boolean` (getter)

### Methods

#### getReader()

Acquire a reader to consume the stream.

```javascript
export default {
  async fetch(request) {
    const stream = new ReadableStream({
      start(controller) {
        controller.enqueue("Line 1\n");
        controller.enqueue("Line 2\n");
        controller.enqueue("Line 3\n");
        controller.close();
      }
    });

    const reader = stream.getReader();
    const chunks = [];

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
    }

    reader.releaseLock();

    return new Response(chunks.join(""));
  }
};
```

**Signature:** `getReader() => ReadableStreamDefaultReader`

**Reader methods:**
- `read()` - Returns `Promise<{done: boolean, value: any}>`
- `releaseLock()` - Release reader lock on stream
- `cancel(reason)` - Cancel stream

#### tee()

Split stream into two independent branches.

:::caution[Data Loss Issue]
`tee()` has a known data loss bug (B-05). Each chunk only goes to one branch. See [Limitations](/api/limitations#b-05-tee-data-loss).
:::

```javascript
const stream = new ReadableStream({
  start(controller) {
    controller.enqueue("data");
    controller.close();
  }
});

const [branch1, branch2] = stream.tee();

// Both branches should receive same data (currently broken)
```

**Signature:** `tee() => [ReadableStream, ReadableStream]`

## WritableStream

A destination for streaming data.

### Constructor

Create a WritableStream with an underlying sink.

```javascript
const stream = new WritableStream({
  write(chunk, controller) {
    // Process each chunk
    console.log("Received chunk:", chunk);
  },

  close(controller) {
    // Called when stream is closed (optional)
    console.log("Stream closed");
  },

  abort(reason) {
    // Called when stream is aborted (optional)
    console.log("Stream aborted:", reason);
  }
});
```

:::tip[Async Sinks Supported (v1.3)]
Since v1.3, WritableStream sinks can return a Promise from `write()`. NANO detects the Promise and defers the next write until the sink promise resolves, providing correct backpressure handling. See [Event Loop](/api/event-loop) for details.
:::

### Properties

#### locked

Returns `true` if stream has an active writer.

```javascript
const stream = new WritableStream({
  write(chunk) {
    console.log(chunk);
  }
});

console.log(stream.locked); // false

const writer = stream.getWriter();
console.log(stream.locked); // true

writer.releaseLock();
console.log(stream.locked); // false
```

**Type:** `boolean` (getter)

### Methods

#### getWriter()

Acquire a writer to write to the stream.

```javascript
export default {
  async fetch(request) {
    const chunks = [];

    const stream = new WritableStream({
      write(chunk) {
        chunks.push(chunk);
      }
    });

    const writer = stream.getWriter();
    await writer.write("Hello, ");
    await writer.write("world!");
    await writer.close();

    return new Response(chunks.join(""));
  }
};
```

**Signature:** `getWriter() => WritableStreamDefaultWriter`

**Writer methods:**
- `write(chunk)` - Returns `Promise<void>`
- `close()` - Returns `Promise<void>`
- `abort(reason)` - Returns `Promise<void>`
- `releaseLock()` - Release writer lock

## TransformStream

Combines a readable and writable side for data transformation.

### Constructor

Create a TransformStream with transformation logic.

```javascript
const transform = new TransformStream({
  transform(chunk, controller) {
    // Transform each chunk
    const transformed = chunk.toUpperCase();
    controller.enqueue(transformed);
  },

  flush(controller) {
    // Called when writable side is closed (optional)
    controller.enqueue("[END]");
  }
});
```

### Properties

#### readable

The readable side of the transform.

```javascript
const transform = new TransformStream();
const reader = transform.readable.getReader();
```

**Type:** `ReadableStream`

#### writable

The writable side of the transform.

```javascript
const transform = new TransformStream();
const writer = transform.writable.getWriter();
```

**Type:** `WritableStream`

## Complete Examples

### Streaming Response

```javascript
export default {
  async fetch(request) {
    const stream = new ReadableStream({
      start(controller) {
        controller.enqueue("Event: start\n");
        controller.enqueue(`Data: ${new Date().toISOString()}\n`);
        controller.enqueue("Event: end\n");
        controller.close();
      }
    });

    return new Response(stream, {
      headers: { "Content-Type": "text/event-stream" }
    });
  }
};
```

### Generate Data Stream

```javascript
export default {
  async fetch(request) {
    let count = 0;

    const stream = new ReadableStream({
      pull(controller) {
        if (count < 10) {
          controller.enqueue(`Line ${count}\n`);
          count++;
        } else {
          controller.close();
        }
      }
    });

    return new Response(stream, {
      headers: { "Content-Type": "text/plain" }
    });
  }
};
```

### Read Stream Completely

```javascript
export default {
  async fetch(request) {
    const response = await fetch("https://api.example.com/stream");
    const stream = response.body; // ReadableStream

    const reader = stream.getReader();
    const chunks = [];

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
    }

    reader.releaseLock();

    return Response.json({
      chunks: chunks.length,
      totalSize: chunks.reduce((sum, chunk) => sum + chunk.length, 0)
    });
  }
};
```

### WritableStream Logger

```javascript
export default {
  async fetch(request) {
    const logs = [];

    const logger = new WritableStream({
      write(chunk) {
        const timestamp = new Date().toISOString();
        logs.push(`[${timestamp}] ${chunk}`);
      },
      close() {
        logs.push("[Stream closed]");
      }
    });

    const writer = logger.getWriter();
    await writer.write("Request received");
    await writer.write("Processing...");
    await writer.write("Complete");
    await writer.close();

    return Response.json({ logs });
  }
};
```

### Transform Stream - Uppercase

```javascript
export default {
  async fetch(request) {
    const { readable, writable } = new TransformStream({
      transform(chunk, controller) {
        const upper = chunk.toUpperCase();
        controller.enqueue(upper);
      }
    });

    // Write to writable side
    const writer = writable.getWriter();
    writer.write("hello ");
    writer.write("world!");
    writer.close();

    // Read from readable side
    return new Response(readable, {
      headers: { "Content-Type": "text/plain" }
    });
  }
};
```

### Transform Stream - JSON Line Parser

```javascript
export default {
  async fetch(request) {
    let buffer = "";

    const lineParser = new TransformStream({
      transform(chunk, controller) {
        buffer += chunk;
        const lines = buffer.split("\n");

        // Process complete lines
        for (let i = 0; i < lines.length - 1; i++) {
          const line = lines[i].trim();
          if (line) {
            try {
              const obj = JSON.parse(line);
              controller.enqueue(obj);
            } catch (e) {
              console.error("Invalid JSON:", line);
            }
          }
        }

        // Keep incomplete line in buffer
        buffer = lines[lines.length - 1];
      },

      flush(controller) {
        // Process remaining buffer
        if (buffer.trim()) {
          try {
            const obj = JSON.parse(buffer);
            controller.enqueue(obj);
          } catch (e) {
            console.error("Invalid JSON:", buffer);
          }
        }
      }
    });

    const writer = lineParser.writable.getWriter();
    writer.write('{"id": 1}\n');
    writer.write('{"id": 2}\n');
    writer.write('{"id": 3}\n');
    writer.close();

    const reader = lineParser.readable.getReader();
    const objects = [];

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      objects.push(value);
    }

    return Response.json({ parsed: objects });
  }
};
```

### Pipe Through Transform

```javascript
export default {
  async fetch(request) {
    const source = new ReadableStream({
      start(controller) {
        controller.enqueue("hello ");
        controller.enqueue("world");
        controller.close();
      }
    });

    const upperTransform = new TransformStream({
      transform(chunk, controller) {
        controller.enqueue(chunk.toUpperCase());
      }
    });

    // Pipe source through transform
    const transformed = source.pipeThrough(upperTransform);

    return new Response(transformed, {
      headers: { "Content-Type": "text/plain" }
    });
  }
};
```

### Async WritableStream Sink

Since v1.3, `write()` sinks can return a Promise. NANO will wait for it to resolve before processing the next queued write:

```javascript
export default {
  async fetch(request) {
    const chunks = [];

    const stream = new WritableStream({
      write(chunk) {
        // Return a Promise — NANO waits for it before next write
        return new Promise(resolve => {
          setTimeout(() => {
            chunks.push(chunk);
            resolve();
          }, 10);
        });
      }
    });

    const writer = stream.getWriter();
    await writer.write('a');
    await writer.write('b');
    await writer.write('c');
    await writer.close();

    // chunks === ['a', 'b', 'c'] — correct sequential order
    return Response.json({ chunks });
  }
};
```

If the sink Promise rejects, the write Promise also rejects and the stream transitions to an errored state:

```javascript
const stream = new WritableStream({
  write(chunk) {
    throw new Error("sink error: " + chunk);
  }
});

const writer = stream.getWriter();
try {
  await writer.write('bad'); // Rejects with "sink error: bad"
} catch (e) {
  console.log(e); // Error: sink error: bad
}
```

## Known Limitations

### ReadableStream.tee() Data Loss (B-05)

`tee()` doesn't properly duplicate stream data. Each chunk goes to only one branch.

**Workaround:** Read stream once and create two new streams from buffered data.

**Planned fix:** Spec-compliant branch queuing in v1.3.

See [Limitations](/api/limitations#b-05-tee-data-loss) for details.

## Related APIs

- [Event Loop](/api/event-loop) - How async WritableStream sinks integrate with the event loop
- [Response](/api/response) - Response.body returns ReadableStream
- [fetch](/api/fetch) - Response bodies are streams
- [Blob](/api/blob) - Convert streams to/from blobs
