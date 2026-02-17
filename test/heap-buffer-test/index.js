export default {
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/test-btoa") {
      // Test btoa with 50KB string (exceeds 8192 stack buffer)
      const big = "A".repeat(50000);
      const encoded = btoa(big);
      const decoded = atob(encoded);
      return new Response(JSON.stringify({
        original_len: big.length,
        encoded_len: encoded.length,
        decoded_len: decoded.length,
        match: big === decoded
      }), { headers: { "Content-Type": "application/json" } });
    }

    if (path === "/test-console") {
      // Test console.log with 10KB string
      const big = "X".repeat(10000);
      console.log(big);
      console.log(JSON.stringify({ key: "Y".repeat(10000) }));
      return new Response("console test done");
    }

    if (path === "/test-blob") {
      // Test Blob with 1MB data
      const size = 1024 * 1024;
      const big = "B".repeat(size);
      const blob = new Blob([big]);
      const text = await blob.text();
      return new Response(JSON.stringify({
        blob_size: blob.size,
        text_len: text.length,
        match: text.length === size
      }), { headers: { "Content-Type": "application/json" } });
    }

    if (path === "/test-encoder") {
      // Test TextEncoder with large string
      const big = "E".repeat(50000);
      const encoder = new TextEncoder();
      const encoded = encoder.encode(big);
      const decoder = new TextDecoder();
      const decoded = decoder.decode(encoded);
      return new Response(JSON.stringify({
        original_len: big.length,
        encoded_len: encoded.length,
        decoded_len: decoded.length,
        match: big === decoded
      }), { headers: { "Content-Type": "application/json" } });
    }

    return new Response("heap buffer test server");
  }
};
