const std = @import("std");
const v8 = @import("v8");

/// CPU watchdog for terminating long-running scripts
/// Uses a separate thread to monitor execution time and terminate if exceeded
pub const Watchdog = struct {
    isolate: v8.Isolate,
    timeout_ms: u64,
    thread: ?std.Thread,
    should_stop: std.atomic.Value(bool),
    started: bool,

    /// Initialize watchdog (does not start it)
    pub fn init(isolate: v8.Isolate, timeout_ms: u64) Watchdog {
        return Watchdog{
            .isolate = isolate,
            .timeout_ms = timeout_ms,
            .thread = null,
            .should_stop = std.atomic.Value(bool).init(false),
            .started = false,
        };
    }

    /// Start the watchdog timer
    /// Must be called before executing untrusted code
    pub fn start(self: *Watchdog) !void {
        if (self.started) return;

        self.should_stop.store(false, .release);
        self.thread = try std.Thread.spawn(.{}, watchdogThread, .{self});
        self.started = true;
    }

    /// Stop the watchdog timer
    /// Must be called after code execution completes (success or failure)
    pub fn stop(self: *Watchdog) void {
        if (!self.started) return;

        // Signal thread to stop
        self.should_stop.store(true, .release);

        // Wait for thread to finish
        if (self.thread) |t| {
            t.join();
        }

        self.thread = null;
        self.started = false;

        // Cancel any pending termination (in case timer fired just as we stopped)
        self.isolate.cancelTerminateExecution();
    }

    /// Check if execution was terminated by the watchdog
    pub fn wasTerminated(self: *Watchdog) bool {
        return self.isolate.isExecutionTerminating();
    }

    fn watchdogThread(self: *Watchdog) void {
        // Sleep in small increments to allow early cancellation
        const check_interval_ms: u64 = 5;
        var elapsed_ms: u64 = 0;

        while (elapsed_ms < self.timeout_ms) {
            // Check if we should stop
            if (self.should_stop.load(.acquire)) {
                return;
            }

            // Sleep for check interval
            std.Thread.sleep(check_interval_ms * std.time.ns_per_ms);
            elapsed_ms += check_interval_ms;
        }

        // Check one more time before terminating
        if (self.should_stop.load(.acquire)) {
            return;
        }

        // Timeout exceeded - terminate execution
        self.isolate.terminateExecution();
    }
};

/// Default timeout for script execution (50ms as per spec)
pub const DEFAULT_TIMEOUT_MS: u64 = 50;

/// Extended timeout for requests that make external calls (5 seconds)
pub const EXTENDED_TIMEOUT_MS: u64 = 5000;
