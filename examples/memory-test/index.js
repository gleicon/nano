// Memory test app - tests memory limits
export default {
    fetch(request) {
        const url = new URL(request.url());
        const path = url.pathname();

        console.log("Request to", path);

        // Allocate lots of memory
        if (path === "/oom") {
            console.log("Attempting to allocate excessive memory...");
            const arrays = [];
            try {
                // Try to allocate 200MB (exceeds 128MB limit)
                for (let i = 0; i < 200; i++) {
                    // Each array is ~1MB
                    arrays.push(new Array(256 * 1024).fill(i));
                    if (i % 10 === 0) {
                        console.log("Allocated", i, "MB");
                    }
                }
                return new Response(JSON.stringify({
                    error: "Should have run out of memory",
                    allocated: arrays.length
                }), {
                    status: 200,
                    headers: { "Content-Type": "application/json" }
                });
            } catch (e) {
                return new Response(JSON.stringify({
                    error: "Memory allocation failed",
                    message: String(e),
                    allocated: arrays.length
                }), {
                    status: 500,
                    headers: { "Content-Type": "application/json" }
                });
            }
        }

        // Normal endpoint
        return new Response(JSON.stringify({
            message: "Memory test app",
            memoryLimit: "128 MB",
            endpoints: ["/oom"]
        }), {
            status: 200,
            headers: { "Content-Type": "application/json" }
        });
    }
});
