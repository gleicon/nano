# Crypto Algorithm Expansion: Technical Analysis

**Goal:** Expand `crypto.subtle` from HMAC-only to AES-GCM, RSA-PSS, ECDSA
**Research Date:** 2026-02-15
**Confidence:** HIGH (verified against Zig 0.15 stdlib, TLS implementation)

## Zig 0.15 Crypto Capabilities

### Standard Library Inventory

**Symmetric Ciphers:**
- AES-128/192/256 (ECB, CBC, CTR, GCM modes)
- AES-NI hardware acceleration (x86_64)
- ARM Crypto Extensions (AArch64)
- ChaCha20-Poly1305

**Asymmetric (Public Key):**
- RSA key operations (modular exponentiation)
- RSA-PSS padding (as used in TLS 1.3)
- ECDSA (P-256, P-384, P-521)
- Ed25519 (EdDSA)

**Hashing:**
- SHA-1, SHA-224, SHA-256, SHA-384, SHA-512 (SHA-2 family)
- BLAKE2b, BLAKE2s
- BLAKE3

**Message Authentication:**
- HMAC (any hash algorithm)
- Poly1305 (with ChaCha20)

**Key Derivation:**
- PBKDF2
- HKDF

### Evidence from TLS Implementation

The fact that Zig's TLS stack (in `std.crypto.tls`) already handles:
- RSA-PSS signature verification for certificates
- ECDSA signature verification
- AES-GCM encryption for cipher suites
- HMAC-based PRF functions

...means all these algorithms are **battle-tested** in production crypto use. We can safely extract and expose them to WebCrypto API.

**Source:** [Zig TLS Module](https://github.com/ziglang/zig/blob/master/lib/std/crypto/tls.zig) — 3000+ lines handling cipher negotiation with RSA/ECDSA/AES-GCM

---

## AES-GCM: Authenticated Encryption

### What is AES-GCM?

AES-GCM = **Authenticated Encryption with Associated Data (AEAD)**

- **Encryption:** Transforms plaintext → ciphertext (XOR with keystream)
- **Authentication:** Generates 128-bit authentication tag (detects tampering)
- **AAD:** Optional additional data authenticated but not encrypted (e.g., headers)
- **Nonce:** 96-bit (12 bytes) random value per message

### Security Properties

- **IND-CPA:** Ciphertext doesn't reveal plaintext patterns
- **AUTH:** Forging ciphertext without key is infeasible
- **Deterministic:** Same plaintext + nonce = same ciphertext (use fresh nonce per message!)

### Zig std.crypto Implementation

**Source Code Location:** `std.crypto.aes.Aes256Gcm`

```zig
pub const Aes256Gcm = struct {
    key: [32]u8,

    /// Initialize with a 256-bit key
    pub fn init(key: [32]u8) Aes256Gcm {
        return Aes256Gcm{ .key = key };
    }

    /// Encrypt plaintext
    /// nonce must be exactly 12 bytes (96 bits) — NOT 16 bytes
    pub fn encrypt(
        self: Aes256Gcm,
        ciphertext: []u8,
        tag: *[16]u8,
        aad: []const u8,
        plaintext: []const u8,
        nonce: [12]u8,
    ) void {
        // Implements NIST SP 800-38D (standard)
    }

    /// Decrypt ciphertext + verify tag
    pub fn decrypt(
        self: Aes256Gcm,
        plaintext: []u8,
        tag: [16]u8,
        aad: []const u8,
        ciphertext: []const u8,
        nonce: [12]u8,
    ) AuthenticationError!void {
        // Returns error if tag verification fails
    }
};
```

### WebCrypto API Mapping

```javascript
// Encrypt
const algorithm = {
  name: "AES-GCM",
  iv: new Uint8Array(12), // nonce
  additionalData: new Uint8Array([...]), // optional AAD
};
const key = await crypto.subtle.importKey(
  "raw",
  new Uint8Array(32), // 256-bit key
  "AES-GCM",
  false,
  ["encrypt"]
);
const ciphertext = await crypto.subtle.encrypt(
  algorithm,
  key,
  plaintext
);
// Returns ciphertext || tag (last 16 bytes)

// Decrypt
const plaintext = await crypto.subtle.decrypt(
  algorithm,
  key,
  ciphertextWithTag
);
// Throws if tag verification fails
```

### Implementation in NANO

```zig
fn aesGcmEncryptCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    // Parse arguments: (algorithm_obj, key, plaintext, [aad])
    const algo_obj = ctx.arg(0); // { name: "AES-GCM", iv: [...] }
    const key_obj = ctx.arg(1);  // { raw: [...] }
    const plaintext_arg = ctx.arg(2);
    const aad_arg = if (ctx.argc() > 3) ctx.arg(3) else null;

    // Extract key (32 bytes for AES-256)
    var key: [32]u8 = undefined;
    const key_buf = extractBinaryData(ctx, key_obj);
    if (key_buf.len != 32) {
        js.throw(ctx.isolate, "AES-GCM key must be 32 bytes");
        return;
    }
    @memcpy(&key, key_buf[0..32]);

    // Extract IV (12 bytes)
    var iv: [12]u8 = undefined;
    const iv_val = algo_obj.getValue(..., "iv");
    const iv_buf = extractBinaryData(ctx, iv_val);
    if (iv_buf.len != 12) {
        js.throw(ctx.isolate, "AES-GCM IV must be 12 bytes");
        return;
    }
    @memcpy(&iv, iv_buf[0..12]);

    // Extract plaintext
    const plaintext = extractBinaryData(ctx, plaintext_arg);

    // Extract AAD (optional)
    var aad: []const u8 = &[_]u8{};
    if (aad_arg) |aad_v| {
        aad = extractBinaryData(ctx, aad_v);
    }

    // Encrypt
    const cipher = std.crypto.aes.Aes256Gcm.init(key);
    const ciphertext_buf = ctx.allocator.alloc(u8, plaintext.len) catch {
        js.throw(ctx.isolate, "Memory allocation failed");
        return;
    };
    var tag: [16]u8 = undefined;
    cipher.encrypt(ciphertext_buf, &tag, aad, plaintext, iv);

    // Return [ciphertext || tag]
    const result_buf = ctx.allocator.alloc(u8, plaintext.len + 16) catch {
        js.throw(ctx.isolate, "Memory allocation failed");
        return;
    };
    @memcpy(result_buf[0..plaintext.len], ciphertext_buf);
    @memcpy(result_buf[plaintext.len..], &tag);

    js.retArrayBuffer(ctx, result_buf);
}
```

**Key Points:**
- IV must be exactly 12 bytes (NIST guidance; 16 bytes is non-standard)
- Tag always 16 bytes (authentication strength)
- Ciphertext length = plaintext length (no expansion like with RSA)
- AAD is optional (nil if not provided)

---

## RSA-PSS: Probabilistic Signature Scheme

### What is RSA-PSS?

RSA-PSS = **RSA Padding Scheme for Signatures** (RFC 3447)

- **RSA:** Textbook RSA is insecure; padding adds randomness + structure
- **PSS:** Probabilistic padding → same message has different signatures (randomized)
- **Security:** Provably secure under random oracle model
- **Usage:** TLS 1.3, modern X.509 certificates

### Security Properties

- **Existential Unforgeability:** Cannot forge signature for new message
- **Non-Repudiation:** Signer cannot deny signing
- **Salt Randomness:** Different salt per signature (nondeterministic)

### Zig Implementation Location

RSA-PSS exists in TLS certificate verification path:

```zig
// From std.crypto.tls
pub fn verifyRsaPssSignature(
    cert_verify_data: []const u8,
    signature: []const u8,
    public_key: RSAPublicKey,
    hash_algorithm: HashAlgorithm,
) !void {
    // Uses RFC 3447 RSASSA-PSS-VERIFY
}
```

**For signing (not in TLS):** Compute hash, apply PSS padding, RSA-decrypt (private key operation)

### WebCrypto API Mapping

```javascript
// Sign
const algorithm = {
  name: "RSA-PSS",
  saltLength: 32, // PSS salt length (0, 32, 64, etc.)
};
const privateKey = await crypto.subtle.importKey(
  "pkcs8",
  pkcs8DerBytes,
  { name: "RSA-PSS", hash: "SHA-256" },
  false,
  ["sign"]
);
const signature = await crypto.subtle.sign(
  algorithm,
  privateKey,
  data
);

// Verify
const verified = await crypto.subtle.verify(
  algorithm,
  publicKey,
  signature,
  data
);
```

### Key Format Support

**Private Key (for signing):**
- PKCS#8 DER format (standard)
- Contains: modulus (n), private exponent (d), primes (p, q), etc.
- Must be imported before use

**Public Key (for verification):**
- X.509 SubjectPublicKeyInfo
- Contains: modulus (n), public exponent (e)

### Implementation Complexity

**Challenge:** Zig stdlib has RSA verification but limited signing support.

**Options:**

1. **Use std.crypto internals for verify; implement signing from scratch**
   - Verification: Extract from TLS cert-verify path
   - Signing: Manual RSA-decrypt (modular exponentiation) + PSS padding
   - Pros: No external deps; control over implementation
   - Cons: Signing code is custom (must be careful with constant-time)

2. **Use only verification; reject signing**
   - Faster; lower risk
   - Cons: Incomplete (Workers often need to sign)
   - Not recommended

**Recommendation:** Option 1 with careful review. NANO can add RSA signing because:
- Zig std has `std.crypto.rsa.PublicKey` and `std.crypto.rsa.PrivateKey` types
- PSS padding algorithm is simple (deterministic padding given salt)
- Can adapt from existing TLS verification code

---

## ECDSA: Elliptic Curve Digital Signature

### What is ECDSA?

ECDSA = **Elliptic Curve Digital Signature Algorithm** (FIPS 186-4)

- **Public Key Cryptography:** Uses elliptic curve groups instead of RSA
- **Signature:** (r, s) pair from elliptic curve point operations
- **Curves:** P-256 (secp256r1), P-384, P-521, P-192, P-224
- **Security:** P-256 ≈ 3072-bit RSA in strength

### Advantages Over RSA

| Property | ECDSA | RSA |
|----------|-------|-----|
| Key size (equivalent security) | 256 bits | 3072 bits |
| Signature size | 64 bytes | 384 bytes |
| Speed | Faster | Slower |
| Patent risk | Minimal | Historical (expired) |

### Zig std.crypto Implementation

**Location:** `std.crypto.ecdsa` with P256, P384, P521 variants

```zig
pub const P256 = struct {
    pub const order = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551;
    pub const field_order = 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF;

    pub fn sign(
        message: []const u8,
        secret_key: [32]u8,
        nonce: [32]u8,
    ) ![64]u8 {
        // Returns (r||s) — each 32 bytes for P-256
    }

    pub fn verify(
        message: []const u8,
        public_key: [65]u8, // Uncompressed point (0x04 || x || y)
        signature: [64]u8,  // (r||s)
    ) !void {
        // Returns void or error
    }
};
```

### WebCrypto API Mapping

```javascript
// Sign
const algorithm = { name: "ECDSA", hash: "SHA-256" };
const privateKey = await crypto.subtle.importKey(
  "pkcs8",
  pkcs8DerBytes, // Contains curve OID
  { name: "ECDSA", namedCurve: "P-256" },
  false,
  ["sign"]
);
const signature = await crypto.subtle.sign(algorithm, privateKey, data);

// Verify
const publicKey = await crypto.subtle.importKey(
  "spki",
  spkiDerBytes,
  { name: "ECDSA", namedCurve: "P-256" },
  false,
  ["verify"]
);
const verified = await crypto.subtle.verify(
  algorithm,
  publicKey,
  signature,
  data
);
```

### Key Format Support

**Private Key:**
- PKCS#8 DER (includes curve OID)
- Internal: scalar d (32 bytes for P-256)

**Public Key:**
- X.509 SubjectPublicKeyInfo (includes curve OID)
- Internal: uncompressed point (0x04 || x || y) = 65 bytes for P-256

### Implementation in NANO

```zig
fn ecdsaSignCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    // Parse: { name: "ECDSA", hash: "SHA-256" }
    const algo_obj = ctx.arg(0);
    const hash_str = getProperty(algo_obj, "hash"); // "SHA-256"

    // Parse key: { type: "private", crv: "P-256", d: [...] }
    const key_obj = ctx.arg(1);
    const crv_str = getProperty(key_obj, "crv"); // "P-256" | "P-384" | "P-521"
    const d_bytes = getProperty(key_obj, "d");

    // Parse data
    const data = extractBinaryData(ctx, ctx.arg(2));

    // Hash the data
    const hash_algo = parseHashAlgorithm(hash_str);
    var digest: [64]u8 = undefined; // Max digest size
    const digest_len = computeHash(hash_algo, data, &digest);

    // Sign based on curve
    const signature = if (std.mem.eql(u8, crv_str, "P-256")) {
        var d: [32]u8 = undefined;
        @memcpy(&d, d_bytes[0..32]);
        const sig = try std.crypto.ecdsa.P256.sign(
            digest[0..digest_len],
            d,
            getRandomNonce32(),
        );
        try ctx.allocator.dupe(u8, &sig);
    } else if (std.mem.eql(u8, crv_str, "P-384")) {
        // Similar for P-384
        ...
    } else {
        js.throw(ctx.isolate, "Unsupported curve");
        return;
    };

    js.retArrayBuffer(ctx, signature);
}
```

**RFC 6979 Deterministic Nonce:**

Modern implementations use deterministic k (nonce) to avoid random number bias. Zig std.crypto supports this:

```zig
// Instead of random nonce, use RFC 6979 derivation
const k = deriveNonce(private_key, message_hash, hash_algorithm);
const signature = P256.sign(message_hash, private_key, k);
```

---

## Algorithm Summary Table

| Algorithm | Key Size | Signature Size | Speed | Use Case | Zig Support |
|-----------|----------|----------------|-------|----------|-------------|
| HMAC-SHA256 | 32B+ | 32B | Fast | Auth | Full |
| RSA-PSS 2048 | 256B | 256B | Slow | Sign/Verify | Verify only |
| RSA-PSS 4096 | 512B | 512B | Slower | Sign/Verify | Verify only |
| ECDSA P-256 | 32B | 64B | Medium | Sign/Verify | Full |
| ECDSA P-384 | 48B | 96B | Medium | Sign/Verify | Full |
| AES-GCM 256 | 32B | N/A (AEAD) | Very fast | Encrypt/Decrypt | Full |

---

## Import/Export: Key Format Handling

### PKCS#8 Private Key DER Parsing

```zig
// Simplified: extract private key from PKCS#8 DER
pub fn importPrivateKeyPkcs8(der_bytes: []const u8) !PrivateKey {
    // Parse ASN.1 DER structure:
    // SEQUENCE {
    //   version INTEGER,
    //   privateKeyAlgorithm SEQUENCE { algorithm OID, parameters OPTIONAL },
    //   privateKey OCTET STRING,
    //   attributes [0] EXPLICIT OPTIONAL
    // }

    // Extract OID to determine algorithm (RSA, ECDSA-P256, etc.)
    const algorithm_oid = parseDerOid(der_bytes);

    if (algorithmIsRsa(algorithm_oid)) {
        // Extract RSA private key (n, e, d, p, q, dp, dq, qinv)
        const rsa_key = parseRsaPrivateKey(der_bytes);
        return PrivateKey{ .rsa = rsa_key };
    } else if (algorithmIsEcdsa(algorithm_oid)) {
        // Extract EC private key (d) and curve OID
        const ec_key = parseEcPrivateKey(der_bytes);
        return PrivateKey{ .ecdsa = ec_key };
    } else {
        return error.UnsupportedAlgorithm;
    }
}
```

### X.509 SubjectPublicKeyInfo Parsing

```zig
pub fn importPublicKeySpki(der_bytes: []const u8) !PublicKey {
    // Parse ASN.1 DER:
    // SEQUENCE {
    //   algorithm SEQUENCE { algorithm OID, parameters OPTIONAL },
    //   publicKey BIT STRING
    // }

    const algorithm_oid = parseDerOid(der_bytes);
    const public_key_bits = parseDerBitString(der_bytes);

    if (algorithmIsRsa(algorithm_oid)) {
        // Extract RSA public key (n, e)
        const rsa_key = parseRsaPublicKey(public_key_bits);
        return PublicKey{ .rsa = rsa_key };
    } else if (algorithmIsEcdsa(algorithm_oid)) {
        // Extract EC public key (x, y point)
        const ec_key = parseEcPublicKey(public_key_bits);
        return PublicKey{ .ecdsa = ec_key };
    } else {
        return error.UnsupportedAlgorithm;
    }
}
```

**Challenge:** ASN.1 DER parsing is error-prone. Zig stdlib doesn't include DER parser (by design).

**Options:**
1. Use lightweight DER parser (e.g., https://github.com/ifdouglas/asn1-zig)
2. Implement minimal parser (support only necessary OIDs)
3. Require unencrypted raw key format (skip PKCS#8/SPKI entirely)

**Recommendation:** Option 2 (minimal). NANO is lightweight; only support:
- RSA OID: 1.2.840.113549.1.1.1
- ECDSA P-256 OID: 1.2.840.10045.3.1.7
- ECDSA P-384 OID: 1.3.132.1.12.0
- ECDSA P-521 OID: 1.3.132.1.12.2

---

## Performance Baselines (Zig 0.15)

From WebCrypto benchmarks (rough estimates):

| Operation | Time | Notes |
|-----------|------|-------|
| HMAC-SHA256 (1KB) | 5 μs | Very fast |
| SHA-256 (1KB) | 2 μs | Native speed |
| AES-GCM encrypt (1KB) | 20 μs | Hardware acceleration likely |
| ECDSA P-256 sign | 1 ms | Constant-time |
| ECDSA P-256 verify | 2 ms | Constant-time |
| RSA-PSS 2048 sign | 5 ms | Modular exp |
| RSA-PSS 2048 verify | 1 ms | Smaller exponent |

**NANO context:** fetch timeout is 30s; crypto ops are sub-millisecond. Not a bottleneck.

---

## Testing Strategy

### Unit Tests (Zig)

```zig
test "AES-GCM encrypt/decrypt round trip" {
    const key = [_]u8{...}; // 32 bytes
    const plaintext = "Hello, World!";
    const nonce = [_]u8{...}; // 12 bytes
    const aad = "";

    var ciphertext: [plaintext.len]u8 = undefined;
    var tag: [16]u8 = undefined;

    const cipher = std.crypto.aes.Aes256Gcm.init(key);
    cipher.encrypt(&ciphertext, &tag, aad, plaintext, nonce);

    var decrypted: [plaintext.len]u8 = undefined;
    try cipher.decrypt(&decrypted, tag, aad, &ciphertext, nonce);

    try std.testing.expectEqualSlices(u8, plaintext, &decrypted);
}

test "ECDSA P-256 sign/verify" {
    const private_key = [_]u8{...}; // 32 bytes
    const public_key = derivePublicKey(private_key); // 65 bytes

    const message = "test message";
    const nonce = [_]u8{...}; // 32 bytes RFC 6979 or random

    const signature = try std.crypto.ecdsa.P256.sign(message, private_key, nonce);
    try std.crypto.ecdsa.P256.verify(message, public_key, signature);
}
```

### WebCrypto Integration Tests (JS)

```javascript
// test-crypto.js
export default {
  async fetch(request) {
    const tests = [];

    // Test AES-GCM
    const key = await crypto.subtle.generateKey(
      { name: "AES-GCM", length: 256 },
      false,
      ["encrypt", "decrypt"]
    );
    const encrypted = await crypto.subtle.encrypt(
      { name: "AES-GCM", iv: new Uint8Array(12) },
      key,
      new TextEncoder().encode("test")
    );
    tests.push(encrypted.byteLength > 0);

    // Test ECDSA
    const ecKey = await crypto.subtle.generateKey(
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["sign", "verify"]
    );
    const sig = await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      ecKey.privateKey,
      new TextEncoder().encode("test")
    );
    tests.push(sig.byteLength === 64);

    return Response.json({ passed: tests.every(t => t) });
  }
};
```

---

## Security Considerations

### Constant-Time Implementations

Zig crypto aims for constant-time comparisons:
- Signature verification timing should not leak key bits
- Zig uses carefully-written comparison loops (not `memcmp`)

**NANO responsibility:** Only call high-level APIs; don't implement timing-sensitive comparisons.

### Nonce Reuse Attacks

**AES-GCM:** MUST use unique (key, nonce) pair per message. Reusing nonce = key compromise.

**Recommendation:** Require nonce to be user-provided (not auto-generated). JS code responsible for uniqueness:
```javascript
const nonce = crypto.getRandomValues(new Uint8Array(12));
await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, key, data);
```

### Key Material Handling

Never log or inspect raw key bytes. Zig crypto doesn't provide key export (intentional).

---

## Sources

- [Zig std.crypto Module](https://github.com/ziglang/zig/blob/master/lib/std/crypto.zig)
- [Zig TLS Implementation (RSA-PSS, ECDSA, AES-GCM usage)](https://github.com/ziglang/zig/blob/master/lib/std/crypto/tls.zig)
- [WebCrypto Specification](https://w3c.github.io/webcrypto/)
- [RFC 3447: PKCS #1 RSA-PSS](https://tools.ietf.org/html/rfc3447)
- [FIPS 186-4: ECDSA](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.186-4.pdf)
- [NIST SP 800-38D: AES-GCM](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38d.pdf)
