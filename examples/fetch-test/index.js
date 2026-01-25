// Fetch test app - tests async/await with fetch()
let requestCount = 0;

__setDefault({
    // Async handler - returns a Promise that nano will await
    async fetch(request) {
        requestCount++;
        const urlStr = request.url();

        console.log("Request", requestCount, "to", urlStr);

        // Test async fetch with await
        if (urlStr.includes("/proxy")) {
            try {
                console.log("Starting fetch to httpbin.org...");
                const response = await fetch("https://httpbin.org/json");
                const status = response.status();
                const body = response.text();

                console.log("Fetch completed, status:", status);

                return new Response(body, {
                    status: 200,
                    headers: { "Content-Type": "application/json" }
                });
            } catch (error) {
                console.log("Fetch error:", error);
                return new Response(JSON.stringify({ error: String(error) }), {
                    status: 500,
                    headers: { "Content-Type": "application/json" }
                });
            }
        }

        // Test simple async handler
        if (urlStr.includes("/async")) {
            // Simulate async work with a resolved Promise
            const data = await Promise.resolve({ message: "Async works!", count: requestCount });
            return new Response(JSON.stringify(data), {
                status: 200,
                headers: { "Content-Type": "application/json" }
            });
        }

        // Default response
        return new Response(JSON.stringify({
            message: "Fetch test app with async/await",
            requestCount: requestCount,
            endpoints: ["/async", "/proxy"]
        }), {
            status: 200,
            headers: { "Content-Type": "application/json" }
        });
    }
});
