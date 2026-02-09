const std = @import("std");
const v8 = @import("v8");
const js = @import("js");

/// Register console object on the global object
pub fn registerConsole(isolate: v8.Isolate, context: v8.Context) void {
    const global = context.getGlobal();

    // Create console object template
    const console_tmpl = isolate.initObjectTemplateDefault();

    // Add methods
    js.addMethod(console_tmpl, isolate, "log", logCallback);
    js.addMethod(console_tmpl, isolate, "error", errorCallback);
    js.addMethod(console_tmpl, isolate, "warn", warnCallback);

    // Create console instance and set on global
    const console_obj = console_tmpl.initInstance(context);
    js.addGlobalObj(global, context, isolate, "console", console_obj);
}

fn logCallback(info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    writeArgs(info, std.posix.STDOUT_FILENO, null);
}

fn errorCallback(info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    writeArgs(info, std.posix.STDERR_FILENO, null);
}

fn warnCallback(info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    writeArgs(info, std.posix.STDERR_FILENO, "[WARN] ");
}

fn writeArgs(raw_info: ?*const v8.C_FunctionCallbackInfo, fd: std.posix.fd_t, prefix: ?[]const u8) void {
    const ctx = js.CallbackContext.init(raw_info);
    const file = std.fs.File{ .handle = fd };

    if (prefix) |p| {
        file.writeAll(p) catch {};
    }

    var i: u32 = 0;
    while (i < ctx.argc()) : (i += 1) {
        if (i > 0) file.writeAll(" ") catch {};
        writeValue(file, ctx.isolate, ctx.context, ctx.arg(i));
    }

    file.writeAll("\n") catch {};
}

fn writeValue(file: std.fs.File, isolate: v8.Isolate, context: v8.Context, value: v8.Value) void {
    if (value.isString()) {
        const str = value.toString(context) catch return;
        var buf: [4096]u8 = undefined;
        file.writeAll(js.readString(isolate, str, &buf)) catch {};
    } else if (value.isNumber()) {
        const str = value.toString(context) catch return;
        var buf: [64]u8 = undefined;
        file.writeAll(js.readString(isolate, str, &buf)) catch {};
    } else if (value.isBoolean()) {
        file.writeAll(if (value.isTrue()) "true" else "false") catch {};
    } else if (value.isUndefined()) {
        file.writeAll("undefined") catch {};
    } else if (value.isNull()) {
        file.writeAll("null") catch {};
    } else if (value.isObject()) {
        // Use JSON.stringify for proper object inspection
        const global = context.getGlobal();
        const json_val = js.getProp(global, context, isolate, "JSON") catch {
            file.writeAll("[object]") catch {};
            return;
        };
        const json_obj = js.asObject(json_val);
        const stringify_fn_val = js.getProp(json_obj, context, isolate, "stringify") catch {
            file.writeAll("[object]") catch {};
            return;
        };
        const stringify_fn = js.asFunction(stringify_fn_val);
        var args: [1]v8.Value = .{value};
        const result = stringify_fn.call(context, json_val, &args) orelse {
            // Fall back if stringify fails (circular references, etc.)
            const str = value.toString(context) catch {
                file.writeAll("[object]") catch {};
                return;
            };
            var buf: [4096]u8 = undefined;
            file.writeAll(js.readString(isolate, str, &buf)) catch {};
            return;
        };
        const result_str = result.toString(context) catch {
            file.writeAll("[object]") catch {};
            return;
        };
        var buf: [4096]u8 = undefined;
        file.writeAll(js.readString(isolate, result_str, &buf)) catch {};
    } else {
        const str = value.toString(context) catch {
            file.writeAll("[object]") catch {};
            return;
        };
        var buf: [4096]u8 = undefined;
        file.writeAll(js.readString(isolate, str, &buf)) catch {};
    }
}
