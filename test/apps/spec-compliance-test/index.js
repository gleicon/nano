export default {
  async fetch(request) {
    const results = [];

    // SPEC-01: Properties as getters (no parentheses needed)
    const blob = new Blob(["hello"], { type: "text/plain" });
    results.push(`blob.size=${blob.size}`);
    results.push(`blob.type=${blob.type}`);

    const req = new Request("https://example.com/path?q=1");
    results.push(`req.url=${req.url}`);
    results.push(`req.method=${req.method}`);

    const resp = new Response("body", { status: 201 });
    results.push(`resp.status=${resp.status}`);
    results.push(`resp.ok=${resp.ok}`);
    results.push(`resp.statusText=${resp.statusText}`);

    const url = new URL("https://example.com:8080/path?q=1#hash");
    results.push(`url.hostname=${url.hostname}`);
    results.push(`url.pathname=${url.pathname}`);
    results.push(`url.port=${url.port}`);
    results.push(`url.search=${url.search}`);
    results.push(`url.hash=${url.hash}`);

    const ac = new AbortController();
    results.push(`ac.signal.aborted=${ac.signal.aborted}`);

    // SPEC-02: Headers.delete and append
    const h = new Headers({ foo: "bar" });
    h.delete("foo");
    results.push(`headers.has(foo)=${h.has("foo")}`);

    const h2 = new Headers();
    h2.append("x-test", "a");
    h2.append("x-test", "b");
    results.push(`headers.get(x-test)=${h2.get("x-test")}`);

    // SPEC-03: Blob with binary parts
    const binBlob = new Blob([new Uint8Array([72, 101, 108, 108, 111])]);
    results.push(`binBlob.size=${binBlob.size}`);

    // SPEC-04: crypto.subtle.digest with binary
    try {
      const hash = await crypto.subtle.digest("SHA-256", new Uint8Array([1, 2, 3]));
      results.push(`digest.byteLength=${hash.byteLength}`);
    } catch (e) {
      results.push(`digest.error=${e.message}`);
    }

    // SPEC-05: console.log object inspection (check output in server logs)
    console.log({ spec: "compliance", test: true });

    return new Response(results.join("\n"), {
      headers: { "Content-Type": "text/plain" }
    });
  }
};
