// Inspector callback stubs - required by v8-zig bindings
// These are no-op implementations since we don't use the V8 inspector (yet)

const v8 = @import("v8");
const c = v8.c;

// Channel callbacks
pub export fn v8_inspector__Channel__IMPL__sendResponse(
    _: *c.InspectorChannelImpl,
    _: *anyopaque,
    _: c_int,
    _: [*c]u8,
    _: usize,
) callconv(.c) void {}

pub export fn v8_inspector__Channel__IMPL__sendNotification(
    _: *c.InspectorChannelImpl,
    _: *anyopaque,
    _: [*c]u8,
    _: usize,
) callconv(.c) void {}

pub export fn v8_inspector__Channel__IMPL__flushProtocolNotifications(
    _: *c.InspectorChannelImpl,
    _: *anyopaque,
) callconv(.c) void {}

// Client callbacks
pub export fn v8_inspector__Client__IMPL__runMessageLoopOnPause(
    _: *c.InspectorClientImpl,
    _: *anyopaque,
    _: c_int,
) callconv(.c) void {}

pub export fn v8_inspector__Client__IMPL__quitMessageLoopOnPause(
    _: *c.InspectorClientImpl,
    _: *anyopaque,
) callconv(.c) void {}

pub export fn v8_inspector__Client__IMPL__runIfWaitingForDebugger(
    _: *c.InspectorClientImpl,
    _: *anyopaque,
    _: c_int,
) callconv(.c) void {}

pub export fn v8_inspector__Client__IMPL__consoleAPIMessage(
    _: *c.InspectorClientImpl,
    _: *anyopaque,
    _: c_int,
    _: c_int,
    _: [*c]const c.v8_inspector__StringView,
    _: [*c]const c.v8_inspector__StringView,
    _: c_uint,
    _: c_uint,
    _: ?*anyopaque,
) callconv(.c) void {}

pub export fn v8_inspector__Client__IMPL__ensureDefaultContextInGroup(
    _: *c.InspectorClientImpl,
    _: *anyopaque,
    _: c_int,
) callconv(.c) void {}

pub export fn v8_inspector__Client__IMPL__generateUniqueId(
    _: *c.InspectorClientImpl,
    _: *anyopaque,
) callconv(.c) i64 {
    return 0;
}
