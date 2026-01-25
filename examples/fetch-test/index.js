// Fetch test app - tests synchronous fetch() usage
let requestCount = 0;

__setDefault({
    fetch(request) {
        requestCount++;
        const urlStr = request.url();

        console.log("Request", requestCount, "to", urlStr);

        // Test fetch - the Promise resolves synchronously in our implementation
        if (urlStr.includes("/proxy")) {
            // Use .then() to handle the Promise
            const promise = fetch("https://httpbin.org/json");

            // Since our fetch is synchronous, the Promise should be resolved immediately
            // We can access the result directly
            let result = { error: "fetch not completed" };

            promise.then(function(response) {
                console.log("Fetch completed, status:", response.status());
                result = {
                    status: response.status(),
                    body: response.text()
                };
            }).catch(function(error) {
                console.log("Fetch error:", error);
                result = { error: String(error) };
            });

            // Return a response based on the fetch result
            return new Response(JSON.stringify(result), {
                status: 200,
                headers: { "Content-Type": "application/json" }
            });
        }

        // Test simple endpoint
        if (urlStr.includes("/test")) {
            return new Response(JSON.stringify({
                message: "Simple test works",
                requestCount: requestCount
            }), {
                status: 200,
                headers: { "Content-Type": "application/json" }
            });
        }

        // Default response
        return new Response(JSON.stringify({
            message: "Fetch test app",
            requestCount: requestCount,
            endpoints: ["/test", "/proxy"]
        }), {
            status: 200,
            headers: { "Content-Type": "application/json" }
        });
    }
});
