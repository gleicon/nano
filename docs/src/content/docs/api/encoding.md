---
title: Encoding
description: Text and binary encoding APIs
sidebar:
  order: 10
  badge:
    text: WinterCG
    variant: success
---

NANO provides standard APIs for converting between text and binary data: TextEncoder, TextDecoder, atob (base64 decode), and btoa (base64 encode).

## TextEncoder

Encode text strings to UTF-8 bytes.

### Constructor

```javascript
const encoder = new TextEncoder();
```

No parameters needed. Always uses UTF-8 encoding.

### encode()

Convert a string to Uint8Array.

```javascript
export default {
  async fetch(request) {
    const text = "Hello, NANO!";
    const encoder = new TextEncoder();
    const bytes = encoder.encode(text);

    console.log("Text length:", text.length); // 12
    console.log("Byte length:", bytes.length); // 12 (ASCII)

    return Response.json({
      text: text,
      byteLength: bytes.length
    });
  }
};
```

**Signature:** `encode(text: string) => Uint8Array`

**Returns:** Uint8Array containing UTF-8 encoded bytes

### Example: Encoding for Crypto

```javascript
export default {
  async fetch(request) {
    const message = "Hash this message";
    const encoder = new TextEncoder();
    const data = encoder.encode(message);

    const hash = await crypto.subtle.digest("SHA-256", data);

    const hashHex = Array.from(new Uint8Array(hash))
      .map(b => b.toString(16).padStart(2, "0"))
      .join("");

    return Response.json({
      message: message,
      sha256: hashHex
    });
  }
};
```

## TextDecoder

Decode UTF-8 bytes to text strings.

### Constructor

```javascript
const decoder = new TextDecoder();
```

Optional `encoding` parameter (defaults to `"utf-8"`). Only UTF-8 is currently supported.

### decode()

Convert Uint8Array to string.

```javascript
export default {
  async fetch(request) {
    const bytes = new Uint8Array([72, 101, 108, 108, 111]); // "Hello"
    const decoder = new TextDecoder();
    const text = decoder.decode(bytes);

    console.log("Decoded text:", text); // "Hello"

    return new Response(text);
  }
};
```

**Signature:** `decode(buffer: BufferSource) => string`

**Parameters:** Uint8Array or ArrayBuffer

**Returns:** Decoded string

### Example: Decoding Binary Response

```javascript
export default {
  async fetch(request) {
    const response = await fetch("https://api.example.com/data");
    const buffer = await response.arrayBuffer();

    const decoder = new TextDecoder();
    const text = decoder.decode(buffer);

    console.log("Response text:", text);

    return new Response(text);
  }
};
```

## atob()

Decode base64 string to binary string.

```javascript
export default {
  async fetch(request) {
    const base64 = "SGVsbG8sIE5BTk8h"; // "Hello, NANO!" in base64
    const decoded = atob(base64);

    console.log("Decoded:", decoded); // "Hello, NANO!"

    return new Response(decoded);
  }
};
```

**Signature:** `atob(base64: string) => string`

**Parameters:** Base64-encoded string

**Returns:** Decoded binary string

:::note[Buffer Limit]
Input limited to 8KB. See [B-01 limitation](/api/limitations#b-01-buffer-limits).
:::

### Example: Decode Base64 to Bytes

```javascript
export default {
  async fetch(request) {
    const base64 = "SGVsbG8=";
    const binaryString = atob(base64);

    // Convert to Uint8Array
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i);
    }

    console.log("Bytes:", bytes); // Uint8Array [72, 101, 108, 108, 111]

    return Response.json({ bytes: Array.from(bytes) });
  }
};
```

## btoa()

Encode binary string to base64.

```javascript
export default {
  async fetch(request) {
    const text = "Hello, NANO!";
    const base64 = btoa(text);

    console.log("Base64:", base64); // "SGVsbG8sIE5BTk8h"

    return Response.json({ base64 });
  }
};
```

**Signature:** `btoa(data: string) => string`

**Parameters:** Binary string (characters with code points 0-255)

**Returns:** Base64-encoded string

:::note[Buffer Limit]
Input limited to 8KB. See [B-01 limitation](/api/limitations#b-01-buffer-limits).
:::

### Example: Encode Bytes to Base64

```javascript
export default {
  async fetch(request) {
    const bytes = new Uint8Array([72, 101, 108, 108, 111]); // "Hello"
    const binaryString = String.fromCharCode(...bytes);
    const base64 = btoa(binaryString);

    console.log("Base64:", base64); // "SGVsbG8="

    return Response.json({ base64 });
  }
};
```

## Complete Examples

### Base64 Encode/Decode API

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url());
    const path = url.pathname;

    // POST /encode - encode text to base64
    if (path === "/encode" && request.method() === "POST") {
      const text = await request.text();
      const base64 = btoa(text);

      return Response.json({
        input: text,
        base64: base64
      });
    }

    // POST /decode - decode base64 to text
    if (path === "/decode" && request.method() === "POST") {
      const base64 = await request.text();

      try {
        const text = atob(base64);
        return Response.json({
          base64: base64,
          decoded: text
        });
      } catch (error) {
        return Response.json(
          { error: "Invalid base64" },
          { status: 400 }
        );
      }
    }

    return new Response("Not Found", { status: 404 });
  }
};
```

### UTF-8 Encoding Info

```javascript
export default {
  async fetch(request) {
    const text = "Hello, 世界! 🌍";
    const encoder = new TextEncoder();
    const bytes = encoder.encode(text);

    return Response.json({
      text: text,
      charCount: text.length,
      byteCount: bytes.length,
      bytes: Array.from(bytes)
    });
  }
};
```

### Binary Data Processing

```javascript
export default {
  async fetch(request) {
    if (request.method() !== "POST") {
      return new Response("POST required", { status: 405 });
    }

    // Read binary data
    const buffer = await request.arrayBuffer();
    const bytes = new Uint8Array(buffer);

    // Process bytes
    const processed = new Uint8Array(bytes.length);
    for (let i = 0; i < bytes.length; i++) {
      processed[i] = bytes[i] ^ 0xFF; // XOR with 0xFF
    }

    // Convert to base64 for response
    const binaryString = String.fromCharCode(...processed);
    const base64 = btoa(binaryString);

    return Response.json({
      inputSize: bytes.length,
      outputBase64: base64
    });
  }
};
```

### Random Token Generation

```javascript
export default {
  async fetch(request) {
    // Generate 32 random bytes
    const bytes = new Uint8Array(32);
    crypto.getRandomValues(bytes);

    // Encode to base64
    const binaryString = String.fromCharCode(...bytes);
    const base64Token = btoa(binaryString);

    // Also create hex version
    const hexToken = Array.from(bytes)
      .map(b => b.toString(16).padStart(2, "0"))
      .join("");

    return Response.json({
      base64: base64Token,
      hex: hexToken,
      bytes: bytes.length
    });
  }
};
```

## Known Limitations

### Buffer Limits (B-01)

`atob()` and `btoa()` have 8KB buffer limits for input and output.

**Workaround:** Process large data in chunks or use streaming.

```javascript
// May fail if input > 8KB
const large = "x".repeat(10000);
const base64 = btoa(large); // May be truncated

// Better: chunk large data
function encodeChunks(data, chunkSize = 4096) {
  const chunks = [];
  for (let i = 0; i < data.length; i += chunkSize) {
    chunks.push(btoa(data.slice(i, i + chunkSize)));
  }
  return chunks.join("");
}
```

See [Limitations](/api/limitations#b-01-buffer-limits) for details.

### TextDecoder Encoding Support

Only UTF-8 is currently supported. Other encodings (UTF-16, ISO-8859-1, etc.) are not implemented.

## Related APIs

- [Crypto](/api/crypto) - Hashing and HMAC require encoded bytes
- [Blob](/api/blob) - Binary data handling
- [fetch](/api/fetch) - Encoding request bodies
- [Response](/api/response) - Decoding response bodies
