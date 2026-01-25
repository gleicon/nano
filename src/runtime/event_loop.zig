const std = @import("std");
const xev = @import("xev");

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
    pub fn cancelTimer(self: *EventLoop, timer_id: u32) bool {
        for (self.timers.items) |*timer| {
            if (timer.id == timer_id and timer.active) {
                timer.active = false;
                return true;
            }
        }
        return false;
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
