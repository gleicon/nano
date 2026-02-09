---
title: Crypto
description: Web Crypto API for cryptographic operations
sidebar:
  order: 9
  badge:
    text: Partial
    variant: caution
---

NANO implements a subset of the Web Crypto API for cryptographic operations: random values, UUIDs, hashing, and HMAC. Full encryption/decryption and key management are not yet supported.

:::caution[Limited crypto.subtle Support]
NANO supports only **HMAC** and **SHA digests**. RSA, ECDSA, AES encryption/decryption, and key import/export are not yet implemented. See [B-04 limitation](/api/limitations#b-04-crypto-subtle-limited).
:::

## crypto.randomUUID()

Generate a random UUID v4.

```javascript
export default {
  async fetch(request) {
    const requestId = crypto.randomUUID();
    console.log("Request ID:", requestId);

    return Response.json({
      requestId: requestId,
      timestamp: Date.now()
    });
  }
};
```

**Signature:** `crypto.randomUUID() => string`

**Returns:** UUID v4 string (e.g., `"550e8400-e29b-41d4-a716-446655440000"`)

## crypto.getRandomValues()

Fill a typed array with cryptographically secure random values.

```javascript
export default {
  async fetch(request) {
    const buffer = new Uint8Array(16);
    crypto.getRandomValues(buffer);

    // Convert to base64 for transmission
    const base64 = btoa(String.fromCharCode(...buffer));

    return Response.json({
      randomBytes: base64,
      length: buffer.length
    });
  }
};
```

**Signature:** `crypto.getRandomValues(typedArray: TypedArray) => TypedArray`

**Parameters:**
- `typedArray`: Uint8Array, Uint16Array, Uint32Array, or other typed array

**Returns:** The same typed array, filled with random values

**Example generating random token:**

```javascript
function generateToken() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);

  return Array.from(bytes)
    .map(b => b.toString(16).padStart(2, "0"))
    .join("");
}

export default {
  async fetch(request) {
    const token = generateToken();
    return Response.json({ token });
  }
};
```

## crypto.subtle.digest()

Generate a cryptographic hash of data.

**Supported algorithms:** `SHA-256`, `SHA-384`, `SHA-512`

```javascript
export default {
  async fetch(request) {
    const message = "Hello, NANO!";
    const encoder = new TextEncoder();
    const data = encoder.encode(message);

    const hashBuffer = await crypto.subtle.digest("SHA-256", data);

    // Convert to hex string
    const hashArray = new Uint8Array(hashBuffer);
    const hashHex = Array.from(hashArray)
      .map(b => b.toString(16).padStart(2, "0"))
      .join("");

    return Response.json({
      message: message,
      sha256: hashHex
    });
  }
};
```

**Signature:** `crypto.subtle.digest(algorithm: string, data: BufferSource) => Promise<ArrayBuffer>`

**Parameters:**
- `algorithm`: `"SHA-256"`, `"SHA-384"`, or `"SHA-512"`
- `data`: Uint8Array or ArrayBuffer

**Returns:** Promise resolving to ArrayBuffer containing hash

### Hashing Request Body

```javascript
export default {
  async fetch(request) {
    if (request.method() !== "POST") {
      return new Response("POST required", { status: 405 });
    }

    const body = await request.text();
    const data = new TextEncoder().encode(body);
    const hash = await crypto.subtle.digest("SHA-256", data);

    const hashHex = Array.from(new Uint8Array(hash))
      .map(b => b.toString(16).padStart(2, "0"))
      .join("");

    return Response.json({
      bodyLength: body.length,
      sha256: hashHex
    });
  }
};
```

## crypto.subtle.sign()

Generate HMAC signature.

**Supported algorithm:** `HMAC` (with SHA-256, SHA-384, or SHA-512)

```javascript
export default {
  async fetch(request) {
    const message = "Sign this message";
    const secret = "my-secret-key";

    const encoder = new TextEncoder();
    const keyData = encoder.encode(secret);
    const messageData = encoder.encode(message);

    // Import HMAC key
    const key = await crypto.subtle.importKey(
      "raw",
      keyData,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"]
    );

    // Generate signature
    const signature = await crypto.subtle.sign(
      "HMAC",
      key,
      messageData
    );

    const signatureHex = Array.from(new Uint8Array(signature))
      .map(b => b.toString(16).padStart(2, "0"))
      .join("");

    return Response.json({
      message: message,
      signature: signatureHex
    });
  }
};
```

**Signature:** `crypto.subtle.sign(algorithm: string | object, key: CryptoKey, data: BufferSource) => Promise<ArrayBuffer>`

**Note:** Currently only HMAC is supported. RSA-PSS and ECDSA are not yet implemented.

## crypto.subtle.verify()

Verify HMAC signature.

```javascript
export default {
  async fetch(request) {
    const message = "Verify this message";
    const secret = "my-secret-key";
    const providedSignature = "..."; // hex string from client

    const encoder = new TextEncoder();
    const keyData = encoder.encode(secret);
    const messageData = encoder.encode(message);

    // Convert hex signature to ArrayBuffer
    const signatureBytes = new Uint8Array(
      providedSignature.match(/.{2}/g).map(byte => parseInt(byte, 16))
    );

    // Import key
    const key = await crypto.subtle.importKey(
      "raw",
      keyData,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"]
    );

    // Verify
    const isValid = await crypto.subtle.verify(
      "HMAC",
      key,
      signatureBytes,
      messageData
    );

    return Response.json({ valid: isValid });
  }
};
```

**Signature:** `crypto.subtle.verify(algorithm: string | object, key: CryptoKey, signature: BufferSource, data: BufferSource) => Promise<boolean>`

## Complete Examples

### Generate API Key

```javascript
export default {
  async fetch(request) {
    const apiKey = crypto.randomUUID();
    const secret = new Uint8Array(32);
    crypto.getRandomValues(secret);

    const secretHex = Array.from(secret)
      .map(b => b.toString(16).padStart(2, "0"))
      .join("");

    return Response.json({
      apiKey: apiKey,
      secret: secretHex
    });
  }
};
```

### Content Integrity Hash

```javascript
export default {
  async fetch(request) {
    const content = "File content here...";
    const data = new TextEncoder().encode(content);
    const hash = await crypto.subtle.digest("SHA-256", data);

    const hashHex = Array.from(new Uint8Array(hash))
      .map(b => b.toString(16).padStart(2, "0"))
      .join("");

    return new Response(content, {
      headers: {
        "Content-Type": "text/plain",
        "X-Content-Hash": hashHex
      }
    });
  }
};
```

### HMAC Request Signing

```javascript
const SECRET_KEY = "your-secret-key";

async function signRequest(method, path, body) {
  const message = `${method}:${path}:${body || ""}`;
  const encoder = new TextEncoder();
  const keyData = encoder.encode(SECRET_KEY);
  const messageData = encoder.encode(message);

  const key = await crypto.subtle.importKey(
    "raw",
    keyData,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign("HMAC", key, messageData);

  return Array.from(new Uint8Array(signature))
    .map(b => b.toString(16).padStart(2, "0"))
    .join("");
}

export default {
  async fetch(request) {
    const url = new URL(request.url());
    const method = request.method();
    const body = method === "POST" ? await request.text() : null;

    const signature = await signRequest(method, url.pathname, body);

    return Response.json({
      method: method,
      path: url.pathname,
      signature: signature
    });
  }
};
```

## Known Limitations

### Limited crypto.subtle (B-04)

NANO currently supports only:
- **Hashing:** SHA-256, SHA-384, SHA-512
- **HMAC:** Sign and verify with SHA hashes

**Not supported:**
- RSA (sign, verify, encrypt, decrypt)
- ECDSA (sign, verify)
- AES (encrypt, decrypt)
- Key derivation (HKDF, PBKDF2)
- Key generation for RSA/ECDSA
- Full key import/export

**Workaround:** Use external service for RSA/AES operations, or pre-compute keys offline.

**Planned fix:** Incremental crypto expansion in v1.3 (AES-GCM priority).

See [Limitations](/api/limitations#b-04-crypto-subtle-limited) for details.

## Related APIs

- [Encoding](/api/encoding) - TextEncoder for converting strings to bytes
- [Blob](/api/blob) - Binary data handling
- [Headers](/api/headers) - Adding signature headers
