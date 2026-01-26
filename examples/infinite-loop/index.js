// Test app with infinite loop - should be terminated by watchdog
__setDefault({
    fetch(request) {
        const url = new URL(request.url());
        const path = url.pathname();

        console.log("Request to", path);

        // Infinite loop endpoint
        if (path === "/loop") {
            console.log("Starting infinite loop...");
            while (true) {
                // This should be terminated by the watchdog
            }
            // Never reached
            return new Response("Done", { status: 200 });
        }

        // CPU-intensive endpoint (takes ~100ms)
        if (path === "/slow") {
            console.log("Starting slow computation...");
            let result = 0;
            for (let i = 0; i < 10000000; i++) {
                result += Math.sqrt(i);
            }
            return new Response(JSON.stringify({ result: result }), {
                status: 200,
                headers: { "Content-Type": "application/json" }
            });
        }

        // Normal endpoint
        return new Response(JSON.stringify({
            message: "Watchdog test app",
            endpoints: ["/loop", "/slow"]
        }), {
            status: 200,
            headers: { "Content-Type": "application/json" }
        });
    }
});
