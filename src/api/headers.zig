const std = @import("std");
const v8 = @import("v8");
const js = @import("js");

/// Register Headers class on global object
pub fn registerHeadersAPI(isolate: v8.Isolate, context: v8.Context) void {
    const global = context.getGlobal();

    // Create Headers constructor
    const headers_tmpl = v8.FunctionTemplate.initCallback(isolate, headersConstructor);
    const proto = headers_tmpl.getPrototypeTemplate();

    // Register methods
    js.addMethod(proto, isolate, "get", headersGet);
    js.addMethod(proto, isolate, "set", headersSet);
    js.addMethod(proto, isolate, "has", headersHas);
    js.addMethod(proto, isolate, "delete", headersDelete);
    js.addMethod(proto, isolate, "append", headersAppend);
    js.addMethod(proto, isolate, "entries", headersEntries);
    js.addMethod(proto, isolate, "keys", headersKeys);
    js.addMethod(proto, isolate, "values", headersValues);

    js.addGlobalClass(global, context, isolate, "Headers", headers_tmpl);
}

fn headersConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    // Store headers as a plain object internally
    const headers_obj = js.object(ctx.isolate, ctx.context);
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_headers", headers_obj);

    // Track key order for iteration (like FormData)
    const keys_arr = js.array(ctx.isolate, 0);
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_keys", keys_arr);

    // If init object provided, copy headers from it
    if (ctx.argc() >= 1) {
        const init_arg = ctx.arg(0);
        if (init_arg.isObject()) {
            const init_obj = js.asObject(init_arg);
            // Get own property names from the init object
            const prop_names = init_obj.getOwnPropertyNames(ctx.context);
            const prop_count = prop_names.length();

            var i: u32 = 0;
            while (i < prop_count) : (i += 1) {
                const key_val = js.getIndex(prop_names.castTo(v8.Object), ctx.context, i) catch continue;
                const key_str = key_val.toString(ctx.context) catch continue;
                var key_buf: [256]u8 = undefined;
                const key = js.readString(ctx.isolate, key_str, &key_buf);

                const val = init_obj.getValue(ctx.context, key_str) catch continue;
                if (val.isUndefined()) continue;

                // Lowercase the key
                var lower_buf: [256]u8 = undefined;
                const lower_key = js.toLower(key, &lower_buf);

                // Set on internal headers
                const val_str = val.toString(ctx.context) catch continue;
                _ = js.setProp(headers_obj, ctx.context, ctx.isolate, lower_key, val_str);

                // Add to keys list
                const keys_len = keys_arr.length();
                _ = js.setIndex(keys_arr.castTo(v8.Object), ctx.context, keys_len, js.string(ctx.isolate, lower_key).toValue());
            }
        }
    }
}

fn headersGet(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) return js.retNull(ctx);

    const name_str = ctx.arg(0).toString(ctx.context) catch return js.retNull(ctx);
    var name_buf: [256]u8 = undefined;
    const name = js.readString(ctx.isolate, name_str, &name_buf);

    // Convert to lowercase for case-insensitive lookup
    var lower_buf: [256]u8 = undefined;
    const lower_name = js.toLower(name, &lower_buf);

    // Get internal headers object
    const headers_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_headers") catch return js.retNull(ctx);
    const headers_obj = js.asObject(headers_val);

    const value = js.getProp(headers_obj, ctx.context, ctx.isolate, lower_name) catch return js.retNull(ctx);

    if (value.isUndefined()) {
        js.retNull(ctx);
    } else {
        js.ret(ctx, value);
    }
}

fn headersSet(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 2) return;

    const name_str = ctx.arg(0).toString(ctx.context) catch return;
    const value_arg = ctx.arg(1);

    var name_buf: [256]u8 = undefined;
    const name = js.readString(ctx.isolate, name_str, &name_buf);

    var lower_buf: [256]u8 = undefined;
    const lower_name = js.toLower(name, &lower_buf);

    // Get internal headers object
    const headers_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_headers") catch return;
    const headers_obj = js.asObject(headers_val);

    // Check if this is a new key
    const existing = js.getProp(headers_obj, ctx.context, ctx.isolate, lower_name) catch null;
    const is_new = (existing == null or existing.?.isUndefined());

    // Set the value
    const value_str = value_arg.toString(ctx.context) catch return;
    _ = js.setProp(headers_obj, ctx.context, ctx.isolate, lower_name, value_str);

    // Add to keys list if new
    if (is_new) {
        const keys_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_keys") catch return;
        if (keys_val.isArray()) {
            const keys_arr = js.asArray(keys_val);
            const len = keys_arr.length();
            _ = js.setIndex(keys_arr.castTo(v8.Object), ctx.context, len, js.string(ctx.isolate, lower_name).toValue());
        }
    }
}

fn headersHas(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) return js.retBool(ctx, false);

    const name_str = ctx.arg(0).toString(ctx.context) catch return js.retBool(ctx, false);
    var name_buf: [256]u8 = undefined;
    const name = js.readString(ctx.isolate, name_str, &name_buf);

    var lower_buf: [256]u8 = undefined;
    const lower_name = js.toLower(name, &lower_buf);

    const headers_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_headers") catch return js.retBool(ctx, false);
    const headers_obj = js.asObject(headers_val);

    const value = js.getProp(headers_obj, ctx.context, ctx.isolate, lower_name) catch return js.retBool(ctx, false);

    js.retBool(ctx, !value.isUndefined());
}

fn headersDelete(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) return;

    const name_str = ctx.arg(0).toString(ctx.context) catch return;
    var name_buf: [256]u8 = undefined;
    const name = js.readString(ctx.isolate, name_str, &name_buf);

    var lower_buf: [256]u8 = undefined;
    const lower_name = js.toLower(name, &lower_buf);

    const headers_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_headers") catch return;
    const headers_obj = js.asObject(headers_val);

    // Set to undefined to mark as deleted
    _ = js.setProp(headers_obj, ctx.context, ctx.isolate, lower_name, js.undefined_(ctx.isolate));

    // Remove from keys array
    const keys_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_keys") catch return;
    if (keys_val.isArray()) {
        const keys_arr = js.asArray(keys_val);
        const keys_len = keys_arr.length();

        // Find and remove the key from the array by rebuilding it
        const new_keys = js.array(ctx.isolate, 0);
        var new_idx: u32 = 0;
        var i: u32 = 0;
        while (i < keys_len) : (i += 1) {
            const key = js.getIndex(keys_arr.castTo(v8.Object), ctx.context, i) catch continue;
            const key_str = key.toString(ctx.context) catch continue;
            var key_buf_cmp: [256]u8 = undefined;
            const key_name = js.readString(ctx.isolate, key_str, &key_buf_cmp);

            // Only keep keys that don't match the deleted key
            if (!std.mem.eql(u8, key_name, lower_name)) {
                _ = js.setIndex(new_keys.castTo(v8.Object), ctx.context, new_idx, key);
                new_idx += 1;
            }
        }
        // Replace the keys array
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_keys", new_keys);
    }
}

fn headersAppend(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 2) return;

    const name_str = ctx.arg(0).toString(ctx.context) catch return;
    var name_buf: [256]u8 = undefined;
    const name = js.readString(ctx.isolate, name_str, &name_buf);

    var lower_buf: [256]u8 = undefined;
    const lower_name = js.toLower(name, &lower_buf);

    const headers_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_headers") catch return;
    const headers_obj = js.asObject(headers_val);

    const value_str = ctx.arg(1).toString(ctx.context) catch return;
    var val_buf: [4096]u8 = undefined;
    const new_val = js.readString(ctx.isolate, value_str, &val_buf);

    // Check if key already exists
    const existing = js.getProp(headers_obj, ctx.context, ctx.isolate, lower_name) catch null;
    const exists = (existing != null and !existing.?.isUndefined());

    if (exists) {
        // Combine with comma separator per WHATWG spec
        const existing_str = existing.?.toString(ctx.context) catch return;
        var existing_buf: [4096]u8 = undefined;
        const old_val = js.readString(ctx.isolate, existing_str, &existing_buf);

        var combined_buf: [8192]u8 = undefined;
        const combined = std.fmt.bufPrint(&combined_buf, "{s}, {s}", .{ old_val, new_val }) catch return;
        _ = js.setProp(headers_obj, ctx.context, ctx.isolate, lower_name, js.string(ctx.isolate, combined));
    } else {
        // New key: set value and track in _keys
        _ = js.setProp(headers_obj, ctx.context, ctx.isolate, lower_name, js.string(ctx.isolate, new_val));
        const keys_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_keys") catch return;
        if (keys_val.isArray()) {
            const keys_arr = js.asArray(keys_val);
            const len = keys_arr.length();
            _ = js.setIndex(keys_arr.castTo(v8.Object), ctx.context, len, js.string(ctx.isolate, lower_name).toValue());
        }
    }
}

fn headersEntries(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    // Return array of [key, value] pairs
    const result = js.array(ctx.isolate, 0);

    const headers_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_headers") catch return js.ret(ctx, result);
    if (!headers_val.isObject()) return js.ret(ctx, result);
    const headers_obj = js.asObject(headers_val);

    const keys_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_keys") catch return js.ret(ctx, result);
    if (!keys_val.isArray()) return js.ret(ctx, result);
    const keys_arr = js.asArray(keys_val);
    const keys_len = keys_arr.length();

    var result_idx: u32 = 0;
    var i: u32 = 0;
    while (i < keys_len) : (i += 1) {
        const key = js.getIndex(keys_arr.castTo(v8.Object), ctx.context, i) catch continue;
        const key_str = key.toString(ctx.context) catch continue;
        var key_buf: [256]u8 = undefined;
        const key_name = js.readString(ctx.isolate, key_str, &key_buf);

        const val = js.getProp(headers_obj, ctx.context, ctx.isolate, key_name) catch continue;
        if (val.isUndefined()) continue;

        // Create [key, value] pair
        const pair = js.array(ctx.isolate, 2);
        _ = js.setIndex(pair.castTo(v8.Object), ctx.context, 0, key);
        _ = js.setIndex(pair.castTo(v8.Object), ctx.context, 1, val);
        _ = js.setIndex(result.castTo(v8.Object), ctx.context, result_idx, js.arrayToValue(pair));
        result_idx += 1;
    }

    js.ret(ctx, result);
}

fn headersKeys(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const result = js.array(ctx.isolate, 0);

    const headers_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_headers") catch return js.ret(ctx, result);
    if (!headers_val.isObject()) return js.ret(ctx, result);
    const headers_obj = js.asObject(headers_val);

    const keys_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_keys") catch return js.ret(ctx, result);
    if (!keys_val.isArray()) return js.ret(ctx, result);
    const keys_arr = js.asArray(keys_val);
    const keys_len = keys_arr.length();

    var result_idx: u32 = 0;
    var i: u32 = 0;
    while (i < keys_len) : (i += 1) {
        const key = js.getIndex(keys_arr.castTo(v8.Object), ctx.context, i) catch continue;
        const key_str = key.toString(ctx.context) catch continue;
        var key_buf: [256]u8 = undefined;
        const key_name = js.readString(ctx.isolate, key_str, &key_buf);

        const val = js.getProp(headers_obj, ctx.context, ctx.isolate, key_name) catch continue;
        if (val.isUndefined()) continue;

        _ = js.setIndex(result.castTo(v8.Object), ctx.context, result_idx, key);
        result_idx += 1;
    }

    js.ret(ctx, result);
}

fn headersValues(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const result = js.array(ctx.isolate, 0);

    const headers_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_headers") catch return js.ret(ctx, result);
    if (!headers_val.isObject()) return js.ret(ctx, result);
    const headers_obj = js.asObject(headers_val);

    const keys_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_keys") catch return js.ret(ctx, result);
    if (!keys_val.isArray()) return js.ret(ctx, result);
    const keys_arr = js.asArray(keys_val);
    const keys_len = keys_arr.length();

    var result_idx: u32 = 0;
    var i: u32 = 0;
    while (i < keys_len) : (i += 1) {
        const key = js.getIndex(keys_arr.castTo(v8.Object), ctx.context, i) catch continue;
        const key_str = key.toString(ctx.context) catch continue;
        var key_buf: [256]u8 = undefined;
        const key_name = js.readString(ctx.isolate, key_str, &key_buf);

        const val = js.getProp(headers_obj, ctx.context, ctx.isolate, key_name) catch continue;
        if (val.isUndefined()) continue;

        _ = js.setIndex(result.castTo(v8.Object), ctx.context, result_idx, val);
        result_idx += 1;
    }

    js.ret(ctx, result);
}
