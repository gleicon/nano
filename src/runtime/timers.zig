const std = @import("std");
const v8 = @import("v8");
const EventLoop = @import("event_loop").EventLoop;

/// Global event loop reference (set during server init)
var global_event_loop: ?*EventLoop = null;

/// Allocator for persistent handles (heap allocated to survive beyond callback stack)
const persistent_allocator = std.heap.page_allocator;

/// Set the global event loop reference
pub fn setEventLoop(loop: *EventLoop) void {
    global_event_loop = loop;
}

/// Register timer APIs (setTimeout, setInterval, clearTimeout, clearInterval)
pub fn registerTimerAPIs(isolate: v8.Isolate, context: v8.Context) void {
    const global = context.getGlobal();

    // setTimeout
    const set_timeout_fn = v8.FunctionTemplate.initCallback(isolate, setTimeoutCallback);
    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "setTimeout"),
        set_timeout_fn.getFunction(context),
    );

    // setInterval
    const set_interval_fn = v8.FunctionTemplate.initCallback(isolate, setIntervalCallback);
    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "setInterval"),
        set_interval_fn.getFunction(context),
    );

    // clearTimeout
    const clear_timeout_fn = v8.FunctionTemplate.initCallback(isolate, clearTimeoutCallback);
    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "clearTimeout"),
        clear_timeout_fn.getFunction(context),
    );

    // clearInterval
    const clear_interval_fn = v8.FunctionTemplate.initCallback(isolate, clearIntervalCallback);
    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "clearInterval"),
        clear_interval_fn.getFunction(context),
    );
}

fn setTimeoutCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    scheduleTimer(raw_info, false);
}

fn setIntervalCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    scheduleTimer(raw_info, true);
}

fn scheduleTimer(raw_info: ?*const v8.C_FunctionCallbackInfo, interval: bool) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();

    if (info.length() < 1) {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "setTimeout/setInterval requires a callback").toValue());
        return;
    }

    const callback_arg = info.getArg(0);
    if (!callback_arg.isFunction()) {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "First argument must be a function").toValue());
        return;
    }

    // Get delay (default 0)
    var delay_ms: u64 = 0;
    if (info.length() >= 2) {
        const delay_arg = info.getArg(1);
        if (delay_arg.isNumber()) {
            const delay_f = delay_arg.toF64(context) catch 0;
            if (delay_f > 0) {
                delay_ms = @intFromFloat(delay_f);
            }
        }
    }

    // Store callback as persistent handle - must be heap-allocated to survive beyond this function
    const callback_fn = v8.Function{ .handle = @ptrCast(callback_arg.handle) };
    const persistent_ptr = persistent_allocator.create(v8.Persistent(v8.Function)) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "Failed to allocate timer callback").toValue());
        return;
    };
    persistent_ptr.* = v8.Persistent(v8.Function).init(isolate, callback_fn);

    // Get event loop
    const loop = global_event_loop orelse {
        persistent_allocator.destroy(persistent_ptr);
        _ = isolate.throwException(v8.String.initUtf8(isolate, "Event loop not initialized").toValue());
        return;
    };

    // Add timer
    const timer_id = loop.addTimer(delay_ms, @intFromPtr(persistent_ptr), interval) catch {
        persistent_allocator.destroy(persistent_ptr);
        _ = isolate.throwException(v8.String.initUtf8(isolate, "Failed to create timer").toValue());
        return;
    };

    // Return timer ID
    info.getReturnValue().set(v8.Number.init(isolate, @floatFromInt(timer_id)).toValue());
}

fn clearTimeoutCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    clearTimer(raw_info);
}

fn clearIntervalCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    clearTimer(raw_info);
}

fn clearTimer(raw_info: ?*const v8.C_FunctionCallbackInfo) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();

    if (info.length() < 1) {
        return; // No-op if no timer ID provided (matches browser behavior)
    }

    const id_arg = info.getArg(0);
    if (!id_arg.isNumber()) {
        return; // No-op for invalid ID
    }

    const timer_id_f = id_arg.toF64(context) catch return;
    const timer_id: u32 = @intFromFloat(timer_id_f);

    // Get event loop
    const loop = global_event_loop orelse return;

    // Cancel timer and clean up persistent handle to prevent memory leak
    if (loop.cancelTimer(timer_id)) |callback_ptr| {
        const persistent_ptr: *v8.Persistent(v8.Function) = @ptrFromInt(callback_ptr);
        persistent_ptr.deinit();
        persistent_allocator.destroy(persistent_ptr);
    }
}

/// Execute pending timer callbacks
/// Called from the event loop after timers fire
pub fn executePendingTimers(isolate: v8.Isolate, context: v8.Context, loop: *EventLoop) void {
    const completed = loop.getCompletedCallbacks();

    for (completed) |timer_info| {
        // Recover heap-allocated persistent handle
        const persistent_ptr: *v8.Persistent(v8.Function) = @ptrFromInt(timer_info.callback_ptr);
        const callback = persistent_ptr.castToFunction();

        // Call the callback with no arguments
        var args: [0]v8.Value = .{};
        _ = callback.call(context, isolate.initUndefined().toValue(), &args);

        // Clean up persistent handle and heap allocation for setTimeout (not interval)
        if (!timer_info.interval) {
            persistent_ptr.deinit();
            persistent_allocator.destroy(persistent_ptr);
        }
    }

    loop.clearCompletedCallbacks();
}
