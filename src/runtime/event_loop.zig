const std = @import("std");
const xev = @import("xev");

// Forward declaration for HttpServer reload callback
// with a function pointer to avoid circular import conflicts with http module
pub const ReloadCallback = *const fn (*anyopaque) void;

/// Config file watcher using poll-based mtime checking
/// Polls config file every 10 seconds, triggers reload callback on changes
pub const ConfigWatcher = struct {
    timer: xev.Timer,
    completion: xev.Completion,
    config_path: []const u8,
    last_mtime: i128,
    last_change_time: i128, // For debounce (nanoseconds)
    server_ptr: *anyopaque, // Pointer to HttpServer (opaque to avoid circular dep)
    reload_callback: ReloadCallback,
    active: bool,

    const POLL_INTERVAL_MS: u64 = 10000; // Poll every 10 seconds
    const DEBOUNCE_NS: i128 = 500_000_000; // 500ms debounce

    /// Initialize config watcher with path and server reference
    pub fn init(config_path: []const u8, server_ptr: *anyopaque, reload_callback: ReloadCallback) !ConfigWatcher {
        // Get initial mtime
        const file = std.fs.cwd().openFile(config_path, .{}) catch |err| {
            // Log error but return with mtime=0 to retry on first poll
            std.debug.print("ConfigWatcher: failed to open config file: {s}\n", .{@errorName(err)});
            return ConfigWatcher{
                .timer = try xev.Timer.init(),
                .completion = undefined,
                .config_path = config_path,
                .last_mtime = 0,
                .last_change_time = 0,
                .server_ptr = server_ptr,
                .reload_callback = reload_callback,
                .active = true,
            };
        };
        defer file.close();
        const stat = try file.stat();

        return ConfigWatcher{
            .timer = try xev.Timer.init(),
            .completion = undefined,
            .config_path = config_path,
            .last_mtime = stat.mtime,
            .last_change_time = 0,
            .server_ptr = server_ptr,
            .reload_callback = reload_callback,
            .active = true,
        };
    }

    /// Start the config watcher timer on the event loop
    pub fn start(self: *ConfigWatcher, loop: *xev.Loop) void {
        self.timer.run(loop, &self.completion, POLL_INTERVAL_MS, ConfigWatcher, self, onTimer);
    }

    /// Stop the config watcher
    pub fn stop(self: *ConfigWatcher) void {
        self.active = false;
    }

    /// Cleanup resources
    pub fn deinit(self: *ConfigWatcher) void {
        self.active = false;
        self.timer.deinit();
    }

    /// Timer callback - check config file mtime and trigger reload if changed
    fn onTimer(
        watcher_ptr: ?*ConfigWatcher,
        loop: *xev.Loop,
        completion: *xev.Completion,
        result: xev.Timer.RunError!void,
    ) xev.CallbackAction {
        _ = loop;
        _ = completion;
        _ = result catch return .disarm;

        const watcher = watcher_ptr orelse return .disarm;

        if (!watcher.active) {
            return .disarm;
        }

        // Try to stat the config file
        const file = std.fs.cwd().openFile(watcher.config_path, .{}) catch {
            // File temporarily inaccessible (editor save in progress), retry next poll
            return .rearm;
        };
        defer file.close();

        const stat = file.stat() catch {
            // Stat failed, retry next poll
            return .rearm;
        };

        // Check if mtime changed
        if (stat.mtime != watcher.last_mtime) {
            const now = std.time.nanoTimestamp();

            // Debounce: only reload if enough time has passed since last change detected
            if (watcher.last_change_time == 0 or (now - watcher.last_change_time) >= DEBOUNCE_NS) {
                watcher.last_mtime = stat.mtime;
                watcher.last_change_time = now;

                // Call the reload callback on the server
                watcher.reload_callback(watcher.server_ptr);
            }
        }

        return .rearm; // Continue polling
    }
};

/// Timer callback info stored for V8 integration
pub const TimerCallback = struct {
    id: u32,
    callback_ptr: usize, // Pointer to stored callback data
    interval: bool, // true for setInterval, false for setTimeout
    delay_ms: u64,
};

/// Stored timer with its completion and timer instance
const PendingTimer = struct {
    id: u32,
    timer: xev.Timer,
    completion: xev.Completion,
    callback_ptr: usize,
    interval: bool,
    delay_ms: u64,
    active: bool,
    event_loop: *EventLoop,
};

/// Event loop wrapper around libxev
pub const EventLoop = struct {
    loop: xev.Loop,
    allocator: std.mem.Allocator,
    running: bool,
    next_timer_id: u32,
    timers: std.ArrayListUnmanaged(PendingTimer),
    completed_callbacks: std.ArrayListUnmanaged(TimerCallback),

    pub fn init(allocator: std.mem.Allocator) !EventLoop {
        return EventLoop{
            .loop = try xev.Loop.init(.{}),
            .allocator = allocator,
            .running = false,
            .next_timer_id = 1,
            .timers = .{},
            .completed_callbacks = .{},
        };
    }

    pub fn deinit(self: *EventLoop) void {
        self.timers.deinit(self.allocator);
        self.completed_callbacks.deinit(self.allocator);
        self.loop.deinit();
    }

    /// Add a timer (setTimeout or setInterval)
    pub fn addTimer(self: *EventLoop, delay_ms: u64, callback_ptr: usize, interval: bool) !u32 {
        const timer_id = self.next_timer_id;
        self.next_timer_id += 1;

        const pending = PendingTimer{
            .id = timer_id,
            .timer = try xev.Timer.init(),
            .completion = undefined,
            .callback_ptr = callback_ptr,
            .interval = interval,
            .delay_ms = delay_ms,
            .active = true,
            .event_loop = self,
        };

        try self.timers.append(self.allocator, pending);

        // Get pointer to the timer in the array
        const timer_ptr = &self.timers.items[self.timers.items.len - 1];

        // Start the timer
        timer_ptr.timer.run(&self.loop, &timer_ptr.completion, delay_ms, PendingTimer, timer_ptr, timerFired);

        return timer_id;
    }

    /// Cancel a timer by ID (marks as inactive)
    /// Returns the callback_ptr for cleanup, or null if timer not found
    pub fn cancelTimer(self: *EventLoop, timer_id: u32) ?usize {
        for (self.timers.items) |*timer| {
            if (timer.id == timer_id and timer.active) {
                timer.active = false;
                return timer.callback_ptr;
            }
        }
        return null;
    }

    /// Run one iteration of the event loop (non-blocking)
    pub fn tick(self: *EventLoop) !bool {
        try self.loop.run(.no_wait);
        return self.hasPendingWork();
    }

    /// Run until a specific condition or timeout
    pub fn runOnce(self: *EventLoop) !void {
        try self.loop.run(.once);
    }

    /// Check if there's pending work
    pub fn hasPendingWork(self: *EventLoop) bool {
        for (self.timers.items) |timer| {
            if (timer.active) return true;
        }
        return false;
    }

    /// Get completed timer callbacks
    pub fn getCompletedCallbacks(self: *EventLoop) []TimerCallback {
        return self.completed_callbacks.items;
    }

    /// Clear completed callbacks after processing
    pub fn clearCompletedCallbacks(self: *EventLoop) void {
        self.completed_callbacks.clearRetainingCapacity();
    }

    /// Clean up inactive timers
    pub fn cleanup(self: *EventLoop) void {
        var i: usize = 0;
        while (i < self.timers.items.len) {
            if (!self.timers.items[i].active) {
                self.timers.items[i].timer.deinit();
                _ = self.timers.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Stop the event loop
    pub fn stop(self: *EventLoop) void {
        self.running = false;
    }

    fn timerFired(
        timer_ptr: ?*PendingTimer,
        loop: *xev.Loop,
        completion: *xev.Completion,
        result: xev.Timer.RunError!void,
    ) xev.CallbackAction {
        _ = loop;
        _ = completion;

        const timer = timer_ptr orelse return .disarm;
        const self = timer.event_loop;

        // Check result
        _ = result catch return .disarm;

        if (!timer.active) {
            // Timer was cancelled
            return .disarm;
        }

        // Add to completed list
        self.completed_callbacks.append(self.allocator, .{
            .id = timer.id,
            .callback_ptr = timer.callback_ptr,
            .interval = timer.interval,
            .delay_ms = timer.delay_ms,
        }) catch {};

        if (timer.interval) {
            // Rearm for setInterval
            return .rearm;
        } else {
            // Disarm for setTimeout
            timer.active = false;
            return .disarm;
        }
    }
};
