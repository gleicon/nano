const std = @import("std");
const v8 = @import("v8");

/// Register Headers class on global object
pub fn registerHeadersAPI(isolate: v8.Isolate, context: v8.Context) void {
    const global = context.getGlobal();

    // Create Headers constructor
    const headers_tmpl = v8.FunctionTemplate.initCallback(isolate, headersConstructor);
    const headers_proto = headers_tmpl.getPrototypeTemplate();

    // Headers methods
    const get_fn = v8.FunctionTemplate.initCallback(isolate, headersGet);
    headers_proto.set(v8.String.initUtf8(isolate, "get").toName(), get_fn, v8.PropertyAttribute.None);

    const set_fn = v8.FunctionTemplate.initCallback(isolate, headersSet);
    headers_proto.set(v8.String.initUtf8(isolate, "set").toName(), set_fn, v8.PropertyAttribute.None);

    const has_fn = v8.FunctionTemplate.initCallback(isolate, headersHas);
    headers_proto.set(v8.String.initUtf8(isolate, "has").toName(), has_fn, v8.PropertyAttribute.None);

    const delete_fn = v8.FunctionTemplate.initCallback(isolate, headersDelete);
    headers_proto.set(v8.String.initUtf8(isolate, "delete").toName(), delete_fn, v8.PropertyAttribute.None);

    const entries_fn = v8.FunctionTemplate.initCallback(isolate, headersEntries);
    headers_proto.set(v8.String.initUtf8(isolate, "entries").toName(), entries_fn, v8.PropertyAttribute.None);

    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "Headers"),
        headers_tmpl.getFunction(context),
    );
}

fn headersConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    // Store headers as a plain object internally
    const headers_obj = isolate.initObjectTemplateDefault().initInstance(context);
    _ = this.setValue(context, v8.String.initUtf8(isolate, "_headers"), headers_obj);

    // If init object provided, copy headers from it
    if (info.length() >= 1) {
        const init_arg = info.getArg(0);
        if (init_arg.isObject()) {
            // Copy headers from init object (simplified - just support object literal)
            // Full implementation would handle Headers instance, array of tuples, etc.
        }
    }
}

fn headersGet(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    if (info.length() < 1) {
        info.getReturnValue().set(isolate.initNull().toValue());
        return;
    }

    const name_arg = info.getArg(0);
    const name_str = name_arg.toString(context) catch {
        info.getReturnValue().set(isolate.initNull().toValue());
        return;
    };

    // Get lowercase name for case-insensitive lookup
    var name_buf: [256]u8 = undefined;
    const name_len = name_str.writeUtf8(isolate, &name_buf);
    const name = name_buf[0..name_len];

    // Convert to lowercase
    var lower_buf: [256]u8 = undefined;
    for (name, 0..) |c, i| {
        lower_buf[i] = std.ascii.toLower(c);
    }
    const lower_name = lower_buf[0..name_len];

    // Get internal headers object
    const headers_val = this.getValue(context, v8.String.initUtf8(isolate, "_headers")) catch {
        info.getReturnValue().set(isolate.initNull().toValue());
        return;
    };

    const headers_obj = v8.Object{ .handle = @ptrCast(headers_val.handle) };
    const value = headers_obj.getValue(context, v8.String.initUtf8(isolate, lower_name)) catch {
        info.getReturnValue().set(isolate.initNull().toValue());
        return;
    };

    if (value.isUndefined()) {
        info.getReturnValue().set(isolate.initNull().toValue());
    } else {
        info.getReturnValue().set(value);
    }
}

fn headersSet(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    if (info.length() < 2) return;

    const name_arg = info.getArg(0);
    const value_arg = info.getArg(1);

    const name_str = name_arg.toString(context) catch return;

    // Get lowercase name
    var name_buf: [256]u8 = undefined;
    const name_len = name_str.writeUtf8(isolate, &name_buf);
    const name = name_buf[0..name_len];

    var lower_buf: [256]u8 = undefined;
    for (name, 0..) |c, i| {
        lower_buf[i] = std.ascii.toLower(c);
    }
    const lower_name = lower_buf[0..name_len];

    // Get internal headers object
    const headers_val = this.getValue(context, v8.String.initUtf8(isolate, "_headers")) catch return;
    const headers_obj = v8.Object{ .handle = @ptrCast(headers_val.handle) };

    // Set the value
    const value_str = value_arg.toString(context) catch return;
    _ = headers_obj.setValue(context, v8.String.initUtf8(isolate, lower_name), value_str.toValue());
}

fn headersHas(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    if (info.length() < 1) {
        info.getReturnValue().set(v8.Value{ .handle = v8.Boolean.init(isolate, false).handle });
        return;
    }

    const name_arg = info.getArg(0);
    const name_str = name_arg.toString(context) catch {
        info.getReturnValue().set(v8.Value{ .handle = v8.Boolean.init(isolate, false).handle });
        return;
    };

    var name_buf: [256]u8 = undefined;
    const name_len = name_str.writeUtf8(isolate, &name_buf);
    const name = name_buf[0..name_len];

    var lower_buf: [256]u8 = undefined;
    for (name, 0..) |c, i| {
        lower_buf[i] = std.ascii.toLower(c);
    }
    const lower_name = lower_buf[0..name_len];

    const headers_val = this.getValue(context, v8.String.initUtf8(isolate, "_headers")) catch {
        info.getReturnValue().set(v8.Value{ .handle = v8.Boolean.init(isolate, false).handle });
        return;
    };

    const headers_obj = v8.Object{ .handle = @ptrCast(headers_val.handle) };
    const value = headers_obj.getValue(context, v8.String.initUtf8(isolate, lower_name)) catch {
        info.getReturnValue().set(v8.Value{ .handle = v8.Boolean.init(isolate, false).handle });
        return;
    };

    const has = !value.isUndefined();
    info.getReturnValue().set(v8.Value{ .handle = v8.Boolean.init(isolate, has).handle });
}

fn headersDelete(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    if (info.length() < 1) return;

    const name_arg = info.getArg(0);
    const name_str = name_arg.toString(context) catch return;

    var name_buf: [256]u8 = undefined;
    const name_len = name_str.writeUtf8(isolate, &name_buf);
    const name = name_buf[0..name_len];

    var lower_buf: [256]u8 = undefined;
    for (name, 0..) |c, i| {
        lower_buf[i] = std.ascii.toLower(c);
    }
    const lower_name = lower_buf[0..name_len];

    const headers_val = this.getValue(context, v8.String.initUtf8(isolate, "_headers")) catch return;
    const headers_obj = v8.Object{ .handle = @ptrCast(headers_val.handle) };

    // Set to undefined to "delete"
    _ = headers_obj.setValue(context, v8.String.initUtf8(isolate, lower_name), isolate.initUndefined().toValue());
}

fn headersEntries(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    // Return the internal headers object for now
    // Full implementation would return an iterator
    const headers_val = this.getValue(context, v8.String.initUtf8(isolate, "_headers")) catch {
        info.getReturnValue().set(isolate.initObjectTemplateDefault().initInstance(context));
        return;
    };

    info.getReturnValue().set(headers_val);
}
