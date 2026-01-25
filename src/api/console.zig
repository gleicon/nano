const std = @import("std");
const v8 = @import("v8");

/// Register console object on the global object
/// Must be called after context is created but before script execution
pub fn registerConsole(isolate: v8.Isolate, context: v8.Context) void {
    // Create console object template
    const console_tmpl = isolate.initObjectTemplateDefault();

    // Add log method
    const log_fn = v8.FunctionTemplate.initCallback(isolate, logCallback);
    console_tmpl.set(
        v8.String.initUtf8(isolate, "log").toName(),
        log_fn,
        v8.PropertyAttribute.None,
    );

    // Add error method
    const error_fn = v8.FunctionTemplate.initCallback(isolate, errorCallback);
    console_tmpl.set(
        v8.String.initUtf8(isolate, "error").toName(),
        error_fn,
        v8.PropertyAttribute.None,
    );

    // Add warn method
    const warn_fn = v8.FunctionTemplate.initCallback(isolate, warnCallback);
    console_tmpl.set(
        v8.String.initUtf8(isolate, "warn").toName(),
        warn_fn,
        v8.PropertyAttribute.None,
    );

    // Create console instance and set on global
    const console_obj = console_tmpl.initInstance(context);
    const global = context.getGlobal();
    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "console"),
        console_obj,
    );
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
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const len = info.length();

    const file = std.fs.File{ .handle = fd };

    // Write prefix if provided
    if (prefix) |p| {
        file.writeAll(p) catch {};
    }

    // Write each argument
    var i: u32 = 0;
    while (i < len) : (i += 1) {
        if (i > 0) {
            file.writeAll(" ") catch {};
        }

        const arg = info.getArg(i);
        writeValue(file, isolate, context, arg);
    }

    file.writeAll("\n") catch {};
}

fn writeValue(file: std.fs.File, isolate: v8.Isolate, context: v8.Context, value: v8.Value) void {
    // Try to convert to string
    // For objects, V8's toString will give us [object Object] unless we JSON.stringify
    // For now, simple string conversion is fine
    if (value.isString()) {
        const str = value.toString(context) catch return;
        var buf: [4096]u8 = undefined;
        const written = str.writeUtf8(isolate, &buf);
        file.writeAll(buf[0..written]) catch {};
    } else if (value.isNumber()) {
        const str = value.toString(context) catch return;
        var buf: [64]u8 = undefined;
        const written = str.writeUtf8(isolate, &buf);
        file.writeAll(buf[0..written]) catch {};
    } else if (value.isBoolean()) {
        if (value.isTrue()) {
            file.writeAll("true") catch {};
        } else {
            file.writeAll("false") catch {};
        }
    } else if (value.isUndefined()) {
        file.writeAll("undefined") catch {};
    } else if (value.isNull()) {
        file.writeAll("null") catch {};
    } else {
        // For objects/arrays, try toString
        const str = value.toString(context) catch {
            file.writeAll("[object]") catch {};
            return;
        };
        var buf: [4096]u8 = undefined;
        const written = str.writeUtf8(isolate, &buf);
        file.writeAll(buf[0..written]) catch {};
    }
}
