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

    const keys_fn = v8.FunctionTemplate.initCallback(isolate, headersKeys);
    headers_proto.set(v8.String.initUtf8(isolate, "keys").toName(), keys_fn, v8.PropertyAttribute.None);

    const values_fn = v8.FunctionTemplate.initCallback(isolate, headersValues);
    headers_proto.set(v8.String.initUtf8(isolate, "values").toName(), values_fn, v8.PropertyAttribute.None);

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

    // Track key order for iteration (like FormData)
    const keys_arr = v8.Array.init(isolate, 0);
    _ = this.setValue(context, v8.String.initUtf8(isolate, "_keys"), v8.Value{ .handle = @ptrCast(keys_arr.handle) });

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

    // Check if this is a new key
    const existing = headers_obj.getValue(context, v8.String.initUtf8(isolate, lower_name)) catch null;
    const is_new = (existing == null or existing.?.isUndefined());

    // Set the value
    const value_str = value_arg.toString(context) catch return;
    _ = headers_obj.setValue(context, v8.String.initUtf8(isolate, lower_name), value_str.toValue());

    // Add to keys list if new
    if (is_new) {
        const keys_val = this.getValue(context, v8.String.initUtf8(isolate, "_keys")) catch return;
        if (keys_val.isArray()) {
            const keys_arr = v8.Array{ .handle = @ptrCast(keys_val.handle) };
            const len = keys_arr.length();
            _ = keys_arr.castTo(v8.Object).setValueAtIndex(context, len, v8.String.initUtf8(isolate, lower_name).toValue());
        }
    }
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

    // Return array of [key, value] pairs (matches FormData pattern)
    const result = v8.Array.init(isolate, 0);

    const headers_val = this.getValue(context, v8.String.initUtf8(isolate, "_headers")) catch {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
        return;
    };
    if (!headers_val.isObject()) {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
        return;
    }
    const headers_obj = v8.Object{ .handle = @ptrCast(headers_val.handle) };

    const keys_val = this.getValue(context, v8.String.initUtf8(isolate, "_keys")) catch {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
        return;
    };
    if (!keys_val.isArray()) {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
        return;
    }
    const keys_arr = v8.Array{ .handle = @ptrCast(keys_val.handle) };
    const keys_len = keys_arr.length();

    var result_idx: u32 = 0;
    var i: u32 = 0;
    while (i < keys_len) : (i += 1) {
        const key = keys_arr.castTo(v8.Object).getAtIndex(context, i) catch continue;
        const key_str = key.toString(context) catch continue;
        var key_buf: [256]u8 = undefined;
        const key_len = key_str.writeUtf8(isolate, &key_buf);
        const key_name = key_buf[0..key_len];

        const val = headers_obj.getValue(context, v8.String.initUtf8(isolate, key_name)) catch continue;
        if (val.isUndefined()) continue; // Skip deleted headers

        // Create [key, value] pair
        const pair = v8.Array.init(isolate, 2);
        _ = pair.castTo(v8.Object).setValueAtIndex(context, 0, key);
        _ = pair.castTo(v8.Object).setValueAtIndex(context, 1, val);
        _ = result.castTo(v8.Object).setValueAtIndex(context, result_idx, v8.Value{ .handle = @ptrCast(pair.handle) });
        result_idx += 1;
    }

    info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
}

fn headersKeys(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    // Return array of keys (filter out deleted ones)
    const result = v8.Array.init(isolate, 0);

    const headers_val = this.getValue(context, v8.String.initUtf8(isolate, "_headers")) catch {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
        return;
    };
    if (!headers_val.isObject()) {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
        return;
    }
    const headers_obj = v8.Object{ .handle = @ptrCast(headers_val.handle) };

    const keys_val = this.getValue(context, v8.String.initUtf8(isolate, "_keys")) catch {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
        return;
    };
    if (!keys_val.isArray()) {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
        return;
    }
    const keys_arr = v8.Array{ .handle = @ptrCast(keys_val.handle) };
    const keys_len = keys_arr.length();

    var result_idx: u32 = 0;
    var i: u32 = 0;
    while (i < keys_len) : (i += 1) {
        const key = keys_arr.castTo(v8.Object).getAtIndex(context, i) catch continue;
        const key_str = key.toString(context) catch continue;
        var key_buf: [256]u8 = undefined;
        const key_len = key_str.writeUtf8(isolate, &key_buf);
        const key_name = key_buf[0..key_len];

        const val = headers_obj.getValue(context, v8.String.initUtf8(isolate, key_name)) catch continue;
        if (val.isUndefined()) continue; // Skip deleted headers

        _ = result.castTo(v8.Object).setValueAtIndex(context, result_idx, key);
        result_idx += 1;
    }

    info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
}

fn headersValues(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    // Return array of values
    const result = v8.Array.init(isolate, 0);

    const headers_val = this.getValue(context, v8.String.initUtf8(isolate, "_headers")) catch {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
        return;
    };
    if (!headers_val.isObject()) {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
        return;
    }
    const headers_obj = v8.Object{ .handle = @ptrCast(headers_val.handle) };

    const keys_val = this.getValue(context, v8.String.initUtf8(isolate, "_keys")) catch {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
        return;
    };
    if (!keys_val.isArray()) {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
        return;
    }
    const keys_arr = v8.Array{ .handle = @ptrCast(keys_val.handle) };
    const keys_len = keys_arr.length();

    var result_idx: u32 = 0;
    var i: u32 = 0;
    while (i < keys_len) : (i += 1) {
        const key = keys_arr.castTo(v8.Object).getAtIndex(context, i) catch continue;
        const key_str = key.toString(context) catch continue;
        var key_buf: [256]u8 = undefined;
        const key_len = key_str.writeUtf8(isolate, &key_buf);
        const key_name = key_buf[0..key_len];

        const val = headers_obj.getValue(context, v8.String.initUtf8(isolate, key_name)) catch continue;
        if (val.isUndefined()) continue; // Skip deleted headers

        _ = result.castTo(v8.Object).setValueAtIndex(context, result_idx, val);
        result_idx += 1;
    }

    info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
}
