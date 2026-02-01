///! JavaScript interop helpers for cleaner V8 API usage
///! Usage: const js = @import("js");
const std = @import("std");
const v8 = @import("v8");

// ============================================================================
// Callback Context - eliminates 4-line boilerplate in every callback
// ============================================================================

/// Convenience struct for V8 callback context
pub const CallbackContext = struct {
    info: v8.FunctionCallbackInfo,
    isolate: v8.Isolate,
    context: v8.Context,
    this: v8.Object,

    pub fn init(raw_info: ?*const v8.C_FunctionCallbackInfo) CallbackContext {
        const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
        const isolate = info.getIsolate();
        return .{
            .info = info,
            .isolate = isolate,
            .context = isolate.getCurrentContext(),
            .this = info.getThis(),
        };
    }

    /// Get argument count
    pub fn argc(self: CallbackContext) u32 {
        return self.info.length();
    }

    /// Get argument by index
    pub fn arg(self: CallbackContext, index: u32) v8.Value {
        return self.info.getArg(index);
    }
};

// ============================================================================
// Value Creation - shorter names for common V8 value constructors
// ============================================================================

/// Create a V8 string from Zig string
pub inline fn string(isolate: v8.Isolate, text: []const u8) v8.String {
    return v8.String.initUtf8(isolate, text);
}

/// Create a V8 number
pub inline fn number(isolate: v8.Isolate, n: anytype) v8.Number {
    return v8.Number.init(isolate, switch (@typeInfo(@TypeOf(n))) {
        .int, .comptime_int => @floatFromInt(n),
        .float, .comptime_float => n,
        else => @compileError("number() expects numeric type"),
    });
}

/// Create a V8 boolean
pub inline fn boolean(isolate: v8.Isolate, b: bool) v8.Boolean {
    return v8.Boolean.init(isolate, b);
}

/// Create V8 null value
pub inline fn null_(isolate: v8.Isolate) v8.Primitive {
    return isolate.initNull();
}

/// Create V8 undefined value
pub inline fn undefined_(isolate: v8.Isolate) v8.Primitive {
    return isolate.initUndefined();
}

/// Create an empty V8 object
pub inline fn object(isolate: v8.Isolate, context: v8.Context) v8.Object {
    return isolate.initObjectTemplateDefault().initInstance(context);
}

/// Create a V8 array with given length
pub inline fn array(isolate: v8.Isolate, len: u32) v8.Array {
    return v8.Array.init(isolate, len);
}

// ============================================================================
// Property Access - cleaner get/set with automatic string conversion
// ============================================================================

/// Get property from object by name
pub inline fn get(obj: v8.Object, ctx: CallbackContext, key: []const u8) !v8.Value {
    return obj.getValue(ctx.context, string(ctx.isolate, key));
}

/// Set property on object by name
pub inline fn set(obj: v8.Object, ctx: CallbackContext, key: []const u8, value: anytype) bool {
    const v8_value = toValue(ctx.isolate, value);
    return obj.setValue(ctx.context, string(ctx.isolate, key), v8_value);
}

/// Get property using isolate and context directly (for non-callback contexts)
pub inline fn getProp(obj: v8.Object, context: v8.Context, isolate: v8.Isolate, key: []const u8) !v8.Value {
    return obj.getValue(context, string(isolate, key));
}

/// Set property using isolate and context directly (for non-callback contexts)
pub inline fn setProp(obj: v8.Object, context: v8.Context, isolate: v8.Isolate, key: []const u8, value: anytype) bool {
    const v8_value = toValue(isolate, value);
    return obj.setValue(context, string(isolate, key), v8_value);
}

/// Get array element by index
pub inline fn getIndex(obj: v8.Object, context: v8.Context, index: u32) !v8.Value {
    return obj.getAtIndex(context, index);
}

/// Set array element by index
pub inline fn setIndex(obj: v8.Object, context: v8.Context, index: u32, value: v8.Value) bool {
    return obj.setValueAtIndex(context, index, value);
}

// ============================================================================
// Return Value Helpers - simplify callback return patterns
// ============================================================================

/// Return a value from callback
pub inline fn ret(ctx: CallbackContext, value: anytype) void {
    ctx.info.getReturnValue().set(toValue(ctx.isolate, value));
}

/// Return null from callback
pub inline fn retNull(ctx: CallbackContext) void {
    ctx.info.getReturnValue().set(null_(ctx.isolate).toValue());
}

/// Return undefined from callback
pub inline fn retUndefined(ctx: CallbackContext) void {
    ctx.info.getReturnValue().set(undefined_(ctx.isolate).toValue());
}

/// Return a string from callback
pub inline fn retString(ctx: CallbackContext, text: []const u8) void {
    ctx.info.getReturnValue().set(string(ctx.isolate, text).toValue());
}

/// Return a number from callback
pub inline fn retNumber(ctx: CallbackContext, n: anytype) void {
    ctx.info.getReturnValue().set(number(ctx.isolate, n).toValue());
}

/// Return a boolean from callback
pub inline fn retBool(ctx: CallbackContext, b: bool) void {
    ctx.info.getReturnValue().set(v8.Value{ .handle = boolean(ctx.isolate, b).handle });
}

/// Return an empty array from callback
pub inline fn retEmptyArray(ctx: CallbackContext) void {
    ctx.info.getReturnValue().set(v8.Value{ .handle = @ptrCast(array(ctx.isolate, 0).handle) });
}

// ============================================================================
// Exception Handling - cleaner throw syntax
// ============================================================================

/// Throw a JavaScript exception with message
pub inline fn throw(isolate: v8.Isolate, message: []const u8) void {
    _ = isolate.throwException(string(isolate, message).toValue());
}

/// Throw using callback context
pub inline fn throwCtx(ctx: CallbackContext, message: []const u8) void {
    throw(ctx.isolate, message);
}

// ============================================================================
// Template Registration - simplify method/property registration
// ============================================================================

/// Add a method to a prototype template
pub inline fn addMethod(
    proto: v8.ObjectTemplate,
    isolate: v8.Isolate,
    name: []const u8,
    callback: *const fn (?*const v8.C_FunctionCallbackInfo) callconv(.c) void,
) void {
    const fn_tmpl = v8.FunctionTemplate.initCallback(isolate, callback);
    proto.set(string(isolate, name).toName(), fn_tmpl, v8.PropertyAttribute.None);
}

/// Register a global function
pub inline fn addGlobalFn(
    global: v8.Object,
    context: v8.Context,
    isolate: v8.Isolate,
    name: []const u8,
    callback: *const fn (?*const v8.C_FunctionCallbackInfo) callconv(.c) void,
) void {
    const fn_tmpl = v8.FunctionTemplate.initCallback(isolate, callback);
    _ = global.setValue(context, string(isolate, name), fn_tmpl.getFunction(context));
}

/// Register a global object
pub inline fn addGlobalObj(
    global: v8.Object,
    context: v8.Context,
    isolate: v8.Isolate,
    name: []const u8,
    obj: anytype,
) void {
    _ = global.setValue(context, string(isolate, name), toValue(isolate, obj));
}

/// Register a constructor on global
pub inline fn addGlobalClass(
    global: v8.Object,
    context: v8.Context,
    isolate: v8.Isolate,
    name: []const u8,
    tmpl: v8.FunctionTemplate,
) void {
    _ = global.setValue(context, string(isolate, name), tmpl.getFunction(context));
}

// ============================================================================
// Type Casting - cleaner handle casts
// ============================================================================

/// Cast a Value to Object
pub inline fn asObject(val: v8.Value) v8.Object {
    return v8.Object{ .handle = @ptrCast(val.handle) };
}

/// Cast a Value to Array
pub inline fn asArray(val: v8.Value) v8.Array {
    return v8.Array{ .handle = @ptrCast(val.handle) };
}

/// Cast a Value to Function
pub inline fn asFunction(val: v8.Value) v8.Function {
    return v8.Function{ .handle = @ptrCast(val.handle) };
}

/// Cast a Value to ArrayBuffer
pub inline fn asArrayBuffer(val: v8.Value) v8.ArrayBuffer {
    return v8.ArrayBuffer{ .handle = @ptrCast(val.handle) };
}

/// Cast a Value to ArrayBufferView
pub inline fn asArrayBufferView(val: v8.Value) v8.ArrayBufferView {
    return v8.ArrayBufferView{ .handle = @ptrCast(val.handle) };
}

/// Cast Object to Value
pub inline fn objToValue(obj: v8.Object) v8.Value {
    return v8.Value{ .handle = @ptrCast(obj.handle) };
}

/// Cast Array to Value
pub inline fn arrayToValue(arr: v8.Array) v8.Value {
    return v8.Value{ .handle = @ptrCast(arr.handle) };
}

// ============================================================================
// String Extraction - read V8 strings into Zig buffers
// ============================================================================

/// Extract V8 string to buffer, returns slice
pub inline fn readString(isolate: v8.Isolate, str: v8.String, buf: []u8) []u8 {
    const len = str.writeUtf8(isolate, buf);
    return buf[0..len];
}

/// Extract V8 value as string to buffer (calls toString if needed)
pub inline fn readValue(ctx: CallbackContext, val: v8.Value, buf: []u8) ?[]u8 {
    const str = val.toString(ctx.context) catch return null;
    return readString(ctx.isolate, str, buf);
}

// ============================================================================
// Conversion Helpers
// ============================================================================

/// Convert various Zig types to V8 Value
pub inline fn toValue(isolate: v8.Isolate, val: anytype) v8.Value {
    const T = @TypeOf(val);
    return switch (@typeInfo(T)) {
        .pointer => |ptr| switch (ptr.size) {
            .Slice => if (ptr.child == u8) string(isolate, val).toValue() else @compileError("unsupported slice type"),
            else => @compileError("unsupported pointer type"),
        },
        .int, .comptime_int => number(isolate, val).toValue(),
        .float, .comptime_float => number(isolate, val).toValue(),
        .bool => boolean(isolate, val).toValue(),
        .@"struct" => blk: {
            // Handle V8 types that have .toValue() or need casting
            if (@hasDecl(T, "toValue")) {
                break :blk val.toValue();
            } else if (@hasField(T, "handle")) {
                // V8 Object, Array, etc.
                break :blk v8.Value{ .handle = @ptrCast(val.handle) };
            } else {
                @compileError("unsupported struct type for toValue");
            }
        },
        else => @compileError("unsupported type for toValue: " ++ @typeName(T)),
    };
}

/// Convert to lowercase in buffer
pub inline fn toLower(src: []const u8, dst: []u8) []u8 {
    const len = @min(src.len, dst.len);
    for (src[0..len], 0..) |c, i| {
        dst[i] = std.ascii.toLower(c);
    }
    return dst[0..len];
}
