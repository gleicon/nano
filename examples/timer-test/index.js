// Timer test app - tests setTimeout, setInterval, clearTimeout, clearInterval
let requestCount = 0;

export default {
    fetch(request) {
        requestCount++;
        const urlStr = request.url();

        if (urlStr.includes("/interval")) {
            // Test setInterval - will fire on subsequent request event loop ticks
            let count = 0;
            const intervalId = setInterval(() => {
                count++;
                console.log("Interval tick:", count);
                if (count >= 3) {
                    clearInterval(intervalId);
                    console.log("Interval cleared after 3 ticks");
                }
            }, 100);

            return new Response(JSON.stringify({
                test: "setInterval",
                intervalId: intervalId
            }), {
                status: 200,
                headers: { "Content-Type": "application/json" }
            });
        }

        if (urlStr.includes("/cancel")) {
            // Test clearTimeout
            const timerId = setTimeout(() => {
                console.log("This should NOT print - timer was cancelled");
            }, 100);
            clearTimeout(timerId);
            console.log("Timer", timerId, "scheduled and immediately cancelled");

            return new Response(JSON.stringify({
                test: "clearTimeout",
                cancelledTimerId: timerId
            }), {
                status: 200,
                headers: { "Content-Type": "application/json" }
            });
        }

        // Default: test setTimeout
        const timerId = setTimeout(() => {
            console.log("setTimeout fired for request", requestCount);
        }, 50);

        return new Response(JSON.stringify({
            test: "setTimeout",
            requestCount: requestCount,
            timerId: timerId
        }), {
            status: 200,
            headers: { "Content-Type": "application/json" }
        });
    }
});
