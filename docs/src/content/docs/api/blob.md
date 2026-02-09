---
title: Blob & File
description: Binary large object APIs for handling file-like data
sidebar:
  order: 12
  badge:
    text: WinterCG
    variant: success
---

The `Blob` and `File` APIs provide methods for handling binary large objects - file-like data in memory. They're used for file uploads, binary data processing, and creating downloadable content.

## Blob

Represents immutable binary data.

### Constructor

Create a new Blob from various data sources.

```javascript
export default {
  async fetch(request) {
    // From string
    const blob1 = new Blob(["Hello, world!"]);

    // From ArrayBuffer
    const buffer = new Uint8Array([72, 101, 108, 108, 111]);
    const blob2 = new Blob([buffer]);

    // With MIME type
    const blob3 = new Blob(
      ['{"message": "Hello"}'],
      { type: "application/json" }
    );

    return new Response(blob3);
  }
};
```

**Signature:** `new Blob(parts: Array, options?: BlobOptions)`

**Parameters:**
- `parts`: Array of strings, ArrayBuffer, or Uint8Array
- `options` (optional):
  - `type`: MIME type string (default: `""`)

:::note[Constructor Limit]
Total size of parts limited to 64KB. See [B-01 limitation](/api/limitations#b-01-buffer-limits).
:::

### Properties (Getters)

#### size

Size of blob in bytes.

```javascript
const blob = new Blob(["Hello"]);
console.log(blob.size); // 5
```

**Type:** `number`

#### type

MIME type of blob.

```javascript
const blob = new Blob(["data"], { type: "text/plain" });
console.log(blob.type); // "text/plain"
```

**Type:** `string`

### Methods

#### text()

Read blob content as text.

```javascript
export default {
  async fetch(request) {
    const blob = new Blob(["Hello, NANO!"]);
    const text = await blob.text();

    console.log(text); // "Hello, NANO!"

    return new Response(text);
  }
};
```

**Signature:** `text() => Promise<string>`

:::note[Buffer Limit]
Reading blobs larger than 64KB may be truncated. See [B-01 limitation](/api/limitations#b-01-buffer-limits).
:::

#### arrayBuffer()

Read blob content as ArrayBuffer.

```javascript
export default {
  async fetch(request) {
    const blob = new Blob(["Hello"]);
    const buffer = await blob.arrayBuffer();
    const bytes = new Uint8Array(buffer);

    console.log(bytes); // Uint8Array [72, 101, 108, 108, 111]

    return Response.json({ bytes: Array.from(bytes) });
  }
};
```

**Signature:** `arrayBuffer() => Promise<ArrayBuffer>`

#### slice()

Create a new Blob containing a subset of data.

```javascript
export default {
  async fetch(request) {
    const blob = new Blob(["Hello, world!"]);
    const slice = blob.slice(0, 5); // "Hello"

    const text = await slice.text();
    console.log(text); // "Hello"

    return new Response(slice);
  }
};
```

**Signature:** `slice(start?: number, end?: number, contentType?: string) => Blob`

**Parameters:**
- `start` (optional): Start offset (default: 0)
- `end` (optional): End offset (default: blob.size)
- `contentType` (optional): MIME type for new blob

## File

Extends Blob with file-specific metadata (name, lastModified).

### Constructor

Create a File with name and modification time.

```javascript
export default {
  async fetch(request) {
    const content = "File content here";
    const file = new File(
      [content],
      "example.txt",
      { type: "text/plain", lastModified: Date.now() }
    );

    console.log(file.name); // "example.txt"
    console.log(file.size); // 17
    console.log(file.type); // "text/plain"

    return new Response(file);
  }
};
```

**Signature:** `new File(parts: Array, name: string, options?: FileOptions)`

**Parameters:**
- `parts`: Same as Blob constructor
- `name`: File name string
- `options` (optional):
  - `type`: MIME type (default: `""`)
  - `lastModified`: Unix timestamp (default: `Date.now()`)

### Properties

File inherits all Blob properties plus:

#### name

File name.

```javascript
const file = new File(["data"], "report.txt");
console.log(file.name); // "report.txt"
```

**Type:** `string` (getter)

#### lastModified

Last modification timestamp (Unix epoch milliseconds).

```javascript
const file = new File(["data"], "file.txt", { lastModified: 1234567890000 });
console.log(file.lastModified); // 1234567890000
```

**Type:** `number` (getter)

### Methods

File inherits all Blob methods: `text()`, `arrayBuffer()`, `slice()`.

## Complete Examples

### Create JSON Blob

```javascript
export default {
  async fetch(request) {
    const data = {
      users: [
        { id: 1, name: "Alice" },
        { id: 2, name: "Bob" }
      ]
    };

    const json = JSON.stringify(data, null, 2);
    const blob = new Blob([json], { type: "application/json" });

    return new Response(blob, {
      headers: {
        "Content-Type": "application/json",
        "Content-Length": String(blob.size)
      }
    });
  }
};
```

### Read Blob as Text

```javascript
export default {
  async fetch(request) {
    const blob = new Blob(["Line 1\nLine 2\nLine 3"]);
    const text = await blob.text();
    const lines = text.split("\n");

    return Response.json({
      lineCount: lines.length,
      lines: lines
    });
  }
};
```

### Binary Data Processing

```javascript
export default {
  async fetch(request) {
    // Create blob from bytes
    const bytes = new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0]); // JPEG header
    const blob = new Blob([bytes], { type: "image/jpeg" });

    // Read as ArrayBuffer
    const buffer = await blob.arrayBuffer();
    const view = new Uint8Array(buffer);

    return Response.json({
      size: blob.size,
      type: blob.type,
      header: Array.from(view)
    });
  }
};
```

### Slice Blob

```javascript
export default {
  async fetch(request) {
    const data = "0123456789";
    const blob = new Blob([data]);

    // Extract middle section
    const slice = blob.slice(2, 7); // "23456"
    const text = await slice.text();

    return Response.json({
      original: data,
      slice: text,
      sliceSize: slice.size
    });
  }
};
```

### Create Downloadable File

```javascript
export default {
  async fetch(request) {
    const content = "Report data\nGenerated: " + new Date().toISOString();
    const file = new File(
      [content],
      "report.txt",
      { type: "text/plain" }
    );

    return new Response(file, {
      headers: {
        "Content-Type": file.type,
        "Content-Disposition": `attachment; filename="${file.name}"`
      }
    });
  }
};
```

### File Upload Echo

```javascript
export default {
  async fetch(request) {
    if (request.method() !== "POST") {
      return new Response("POST required", { status: 405 });
    }

    // Assume request contains file data
    const blob = await request.blob();

    return Response.json({
      size: blob.size,
      type: blob.type,
      received: new Date().toISOString()
    });
  }
};
```

### CSV Generation

```javascript
export default {
  async fetch(request) {
    const data = [
      ["Name", "Email", "Role"],
      ["Alice", "alice@example.com", "Admin"],
      ["Bob", "bob@example.com", "User"]
    ];

    const csv = data.map(row => row.join(",")).join("\n");
    const file = new File([csv], "users.csv", { type: "text/csv" });

    return new Response(file, {
      headers: {
        "Content-Type": "text/csv",
        "Content-Disposition": "attachment; filename=\"users.csv\""
      }
    });
  }
};
```

### Combine Multiple Blobs

```javascript
export default {
  async fetch(request) {
    const header = new Blob(["# Report\n\n"], { type: "text/plain" });
    const body = new Blob(["Data: 123\n"], { type: "text/plain" });
    const footer = new Blob(["\nGenerated: " + Date.now()], { type: "text/plain" });

    // Combine using text
    const headerText = await header.text();
    const bodyText = await body.text();
    const footerText = await footer.text();

    const combined = new Blob([headerText, bodyText, footerText], {
      type: "text/plain"
    });

    return new Response(combined);
  }
};
```

## Known Limitations

### Constructor Size Limit (B-01)

Blob/File constructor limited to 64KB total input size.

**Workaround:** Stream large files instead of loading into Blob.

**Planned fix:** Heap allocation in v1.3.

See [Limitations](/api/limitations#b-01-buffer-limits) for details.

### Read Method Limits (B-01)

`text()` and `arrayBuffer()` have 64KB buffer limits.

**Workaround:** Use streaming for large files.

**Planned fix:** Heap allocation in v1.3.

See [Limitations](/api/limitations#b-01-buffer-limits) for details.

## Related APIs

- [Response](/api/response) - Return blobs as response body
- [fetch](/api/fetch) - Response.blob() method
- [Streams](/api/streams) - Stream large binary data
- [Encoding](/api/encoding) - Convert text to/from bytes
