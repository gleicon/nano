const std = @import("std");
const v8 = @import("v8");
const js = @import("js");

/// Register FormData API
pub fn registerFormDataAPI(isolate: v8.Isolate, context: v8.Context) void {
    const global = context.getGlobal();

    // Register FormData constructor
    const formdata_tmpl = v8.FunctionTemplate.initCallback(isolate, formDataConstructor);
    const formdata_proto = formdata_tmpl.getPrototypeTemplate();

    js.addMethod(formdata_proto, isolate, "append", formDataAppend);
    js.addMethod(formdata_proto, isolate, "delete", formDataDelete);
    js.addMethod(formdata_proto, isolate, "get", formDataGet);
    js.addMethod(formdata_proto, isolate, "getAll", formDataGetAll);
    js.addMethod(formdata_proto, isolate, "has", formDataHas);
    js.addMethod(formdata_proto, isolate, "set", formDataSet);
    js.addMethod(formdata_proto, isolate, "entries", formDataEntries);
    js.addMethod(formdata_proto, isolate, "keys", formDataKeys);
    js.addMethod(formdata_proto, isolate, "values", formDataValues);

    js.addGlobalClass(global, context, isolate, "FormData", formdata_tmpl);
}

fn formDataConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    // Create internal storage object
    const storage = js.object(ctx.isolate, ctx.context);
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_storage", storage);

    // Track key order for iteration
    const keys_arr = js.array(ctx.isolate, 0);
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_keys", keys_arr);
}

fn formDataAppend(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 2) return;

    const name_str = ctx.arg(0).toString(ctx.context) catch return;
    const value_arg = ctx.arg(1);

    var name_buf: [256]u8 = undefined;
    const name = js.readString(ctx.isolate, name_str, &name_buf);

    // Get storage
    const storage_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_storage") catch return;
    if (!storage_val.isObject()) return;
    const storage = js.asObject(storage_val);

    // Get or create array for this key
    const existing = js.getProp(storage, ctx.context, ctx.isolate, name) catch null;
    var arr: v8.Array = undefined;
    if (existing == null or existing.?.isUndefined()) {
        arr = js.array(ctx.isolate, 0);
        _ = js.setProp(storage, ctx.context, ctx.isolate, name, arr);

        // Add to keys list
        const keys_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_keys") catch return;
        if (keys_val.isArray()) {
            const keys_arr = js.asArray(keys_val);
            const len = keys_arr.length();
            _ = js.setIndex(keys_arr.castTo(v8.Object), ctx.context, len, name_str.toValue());
        }
    } else {
        arr = js.asArray(existing.?);
    }

    // Append value
    const len = arr.length();
    _ = js.setIndex(arr.castTo(v8.Object), ctx.context, len, value_arg);
}

fn formDataDelete(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) return;

    const name_str = ctx.arg(0).toString(ctx.context) catch return;
    var name_buf: [256]u8 = undefined;
    const name = js.readString(ctx.isolate, name_str, &name_buf);

    // Get storage and delete key
    const storage_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_storage") catch return;
    if (!storage_val.isObject()) return;
    const storage = js.asObject(storage_val);

    _ = js.setProp(storage, ctx.context, ctx.isolate, name, js.undefined_(ctx.isolate));
}

fn formDataGet(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) {
        js.retNull(ctx);
        return;
    }

    const name_str = ctx.arg(0).toString(ctx.context) catch {
        js.retNull(ctx);
        return;
    };
    var name_buf: [256]u8 = undefined;
    const name = js.readString(ctx.isolate, name_str, &name_buf);

    // Get storage
    const storage_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_storage") catch {
        js.retNull(ctx);
        return;
    };
    if (!storage_val.isObject()) {
        js.retNull(ctx);
        return;
    }
    const storage = js.asObject(storage_val);

    // Get array for this key
    const arr_val = js.getProp(storage, ctx.context, ctx.isolate, name) catch {
        js.retNull(ctx);
        return;
    };

    if (arr_val.isUndefined() or !arr_val.isArray()) {
        js.retNull(ctx);
        return;
    }

    const arr = js.asArray(arr_val);
    if (arr.length() == 0) {
        js.retNull(ctx);
        return;
    }

    // Return first value
    const first = js.getIndex(arr.castTo(v8.Object), ctx.context, 0) catch {
        js.retNull(ctx);
        return;
    };
    js.ret(ctx, first);
}

fn formDataGetAll(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) {
        js.retEmptyArray(ctx);
        return;
    }

    const name_str = ctx.arg(0).toString(ctx.context) catch {
        js.retEmptyArray(ctx);
        return;
    };
    var name_buf: [256]u8 = undefined;
    const name = js.readString(ctx.isolate, name_str, &name_buf);

    // Get storage
    const storage_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_storage") catch {
        js.retEmptyArray(ctx);
        return;
    };
    if (!storage_val.isObject()) {
        js.retEmptyArray(ctx);
        return;
    }
    const storage = js.asObject(storage_val);

    // Get array for this key
    const arr_val = js.getProp(storage, ctx.context, ctx.isolate, name) catch {
        js.retEmptyArray(ctx);
        return;
    };

    if (arr_val.isUndefined() or !arr_val.isArray()) {
        js.retEmptyArray(ctx);
        return;
    }

    js.ret(ctx, arr_val);
}

fn formDataHas(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) {
        js.retBool(ctx, false);
        return;
    }

    const name_str = ctx.arg(0).toString(ctx.context) catch {
        js.retBool(ctx, false);
        return;
    };
    var name_buf: [256]u8 = undefined;
    const name = js.readString(ctx.isolate, name_str, &name_buf);

    // Get storage
    const storage_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_storage") catch {
        js.retBool(ctx, false);
        return;
    };
    if (!storage_val.isObject()) {
        js.retBool(ctx, false);
        return;
    }
    const storage = js.asObject(storage_val);

    // Check if key exists
    const arr_val = js.getProp(storage, ctx.context, ctx.isolate, name) catch {
        js.retBool(ctx, false);
        return;
    };

    const has = !arr_val.isUndefined() and arr_val.isArray();
    js.retBool(ctx, has);
}

fn formDataSet(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 2) return;

    const name_str = ctx.arg(0).toString(ctx.context) catch return;
    const value_arg = ctx.arg(1);

    var name_buf: [256]u8 = undefined;
    const name = js.readString(ctx.isolate, name_str, &name_buf);

    // Get storage
    const storage_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_storage") catch return;
    if (!storage_val.isObject()) return;
    const storage = js.asObject(storage_val);

    // Check if key already exists
    const existing = js.getProp(storage, ctx.context, ctx.isolate, name) catch null;
    const is_new = (existing == null or existing.?.isUndefined());

    // Create new array with single value
    const arr = js.array(ctx.isolate, 1);
    _ = js.setIndex(arr.castTo(v8.Object), ctx.context, 0, value_arg);
    _ = js.setProp(storage, ctx.context, ctx.isolate, name, arr);

    // Add to keys list if new
    if (is_new) {
        const keys_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_keys") catch return;
        if (keys_val.isArray()) {
            const keys_arr = js.asArray(keys_val);
            const len = keys_arr.length();
            _ = js.setIndex(keys_arr.castTo(v8.Object), ctx.context, len, name_str.toValue());
        }
    }
}

fn formDataEntries(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const result = js.array(ctx.isolate, 0);

    const storage_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_storage") catch {
        js.ret(ctx, result);
        return;
    };
    if (!storage_val.isObject()) {
        js.ret(ctx, result);
        return;
    }
    const storage = js.asObject(storage_val);

    const keys_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_keys") catch {
        js.ret(ctx, result);
        return;
    };
    if (!keys_val.isArray()) {
        js.ret(ctx, result);
        return;
    }
    const keys_arr = js.asArray(keys_val);
    const keys_len = keys_arr.length();

    var result_idx: u32 = 0;
    var i: u32 = 0;
    while (i < keys_len) : (i += 1) {
        const key = js.getIndex(keys_arr.castTo(v8.Object), ctx.context, i) catch continue;
        const key_str = key.toString(ctx.context) catch continue;
        var key_buf: [256]u8 = undefined;
        const key_name = js.readString(ctx.isolate, key_str, &key_buf);

        const values_val = js.getProp(storage, ctx.context, ctx.isolate, key_name) catch continue;
        if (!values_val.isArray()) continue;
        const values_arr = js.asArray(values_val);
        const values_len = values_arr.length();

        var j: u32 = 0;
        while (j < values_len) : (j += 1) {
            const val = js.getIndex(values_arr.castTo(v8.Object), ctx.context, j) catch continue;

            const pair = js.array(ctx.isolate, 2);
            _ = js.setIndex(pair.castTo(v8.Object), ctx.context, 0, key);
            _ = js.setIndex(pair.castTo(v8.Object), ctx.context, 1, val);
            _ = js.setIndex(result.castTo(v8.Object), ctx.context, result_idx, js.arrayToValue(pair));
            result_idx += 1;
        }
    }

    js.ret(ctx, result);
}

fn formDataKeys(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const keys_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_keys") catch {
        js.retEmptyArray(ctx);
        return;
    };
    js.ret(ctx, keys_val);
}

fn formDataValues(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const result = js.array(ctx.isolate, 0);

    const storage_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_storage") catch {
        js.ret(ctx, result);
        return;
    };
    if (!storage_val.isObject()) {
        js.ret(ctx, result);
        return;
    }
    const storage = js.asObject(storage_val);

    const keys_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_keys") catch {
        js.ret(ctx, result);
        return;
    };
    if (!keys_val.isArray()) {
        js.ret(ctx, result);
        return;
    }
    const keys_arr = js.asArray(keys_val);
    const keys_len = keys_arr.length();

    var result_idx: u32 = 0;
    var i: u32 = 0;
    while (i < keys_len) : (i += 1) {
        const key = js.getIndex(keys_arr.castTo(v8.Object), ctx.context, i) catch continue;
        const key_str = key.toString(ctx.context) catch continue;
        var key_buf: [256]u8 = undefined;
        const key_name = js.readString(ctx.isolate, key_str, &key_buf);

        const values_val = js.getProp(storage, ctx.context, ctx.isolate, key_name) catch continue;
        if (!values_val.isArray()) continue;
        const values_arr = js.asArray(values_val);
        const values_len = values_arr.length();

        var j: u32 = 0;
        while (j < values_len) : (j += 1) {
            const val = js.getIndex(values_arr.castTo(v8.Object), ctx.context, j) catch continue;
            _ = js.setIndex(result.castTo(v8.Object), ctx.context, result_idx, val);
            result_idx += 1;
        }
    }

    js.ret(ctx, result);
}
