const std = @import("std");
const v8 = @import("v8");

/// Register FormData API
pub fn registerFormDataAPI(isolate: v8.Isolate, context: v8.Context) void {
    const global = context.getGlobal();

    // Register FormData constructor
    const formdata_tmpl = v8.FunctionTemplate.initCallback(isolate, formDataConstructor);
    const formdata_proto = formdata_tmpl.getPrototypeTemplate();

    // FormData.append(name, value, filename?)
    const append_fn = v8.FunctionTemplate.initCallback(isolate, formDataAppend);
    formdata_proto.set(v8.String.initUtf8(isolate, "append").toName(), append_fn, v8.PropertyAttribute.None);

    // FormData.delete(name)
    const delete_fn = v8.FunctionTemplate.initCallback(isolate, formDataDelete);
    formdata_proto.set(v8.String.initUtf8(isolate, "delete").toName(), delete_fn, v8.PropertyAttribute.None);

    // FormData.get(name)
    const get_fn = v8.FunctionTemplate.initCallback(isolate, formDataGet);
    formdata_proto.set(v8.String.initUtf8(isolate, "get").toName(), get_fn, v8.PropertyAttribute.None);

    // FormData.getAll(name)
    const getall_fn = v8.FunctionTemplate.initCallback(isolate, formDataGetAll);
    formdata_proto.set(v8.String.initUtf8(isolate, "getAll").toName(), getall_fn, v8.PropertyAttribute.None);

    // FormData.has(name)
    const has_fn = v8.FunctionTemplate.initCallback(isolate, formDataHas);
    formdata_proto.set(v8.String.initUtf8(isolate, "has").toName(), has_fn, v8.PropertyAttribute.None);

    // FormData.set(name, value, filename?)
    const set_fn = v8.FunctionTemplate.initCallback(isolate, formDataSet);
    formdata_proto.set(v8.String.initUtf8(isolate, "set").toName(), set_fn, v8.PropertyAttribute.None);

    // FormData.entries()
    const entries_fn = v8.FunctionTemplate.initCallback(isolate, formDataEntries);
    formdata_proto.set(v8.String.initUtf8(isolate, "entries").toName(), entries_fn, v8.PropertyAttribute.None);

    // FormData.keys()
    const keys_fn = v8.FunctionTemplate.initCallback(isolate, formDataKeys);
    formdata_proto.set(v8.String.initUtf8(isolate, "keys").toName(), keys_fn, v8.PropertyAttribute.None);

    // FormData.values()
    const values_fn = v8.FunctionTemplate.initCallback(isolate, formDataValues);
    formdata_proto.set(v8.String.initUtf8(isolate, "values").toName(), values_fn, v8.PropertyAttribute.None);

    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "FormData"),
        formdata_tmpl.getFunction(context),
    );
}

// === FormData implementation ===
// Uses a simple object to store key-value pairs
// Keys map to arrays of values (for multiple values with same name)

fn formDataConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    // Create internal storage object
    const storage = isolate.initObjectTemplateDefault().initInstance(context);
    _ = this.setValue(context, v8.String.initUtf8(isolate, "_storage"), v8.Value{ .handle = @ptrCast(storage.handle) });

    // Track key order for iteration
    const keys_arr = v8.Array.init(isolate, 0);
    _ = this.setValue(context, v8.String.initUtf8(isolate, "_keys"), v8.Value{ .handle = @ptrCast(keys_arr.handle) });
}

fn formDataAppend(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    if (info.length() < 2) return;

    const name_arg = info.getArg(0);
    const value_arg = info.getArg(1);

    // Get name as string
    const name_str = name_arg.toString(context) catch return;
    var name_buf: [256]u8 = undefined;
    const name_len = name_str.writeUtf8(isolate, &name_buf);
    const name = name_buf[0..name_len];

    // Get storage
    const storage_val = this.getValue(context, v8.String.initUtf8(isolate, "_storage")) catch return;
    if (!storage_val.isObject()) return;
    const storage = v8.Object{ .handle = @ptrCast(storage_val.handle) };

    // Get or create array for this key
    const existing = storage.getValue(context, v8.String.initUtf8(isolate, name)) catch null;
    var arr: v8.Array = undefined;
    if (existing == null or existing.?.isUndefined()) {
        arr = v8.Array.init(isolate, 0);
        _ = storage.setValue(context, v8.String.initUtf8(isolate, name), v8.Value{ .handle = @ptrCast(arr.handle) });

        // Add to keys list
        const keys_val = this.getValue(context, v8.String.initUtf8(isolate, "_keys")) catch return;
        if (keys_val.isArray()) {
            const keys_arr = v8.Array{ .handle = @ptrCast(keys_val.handle) };
            const len = keys_arr.length();
            _ = keys_arr.castTo(v8.Object).setValueAtIndex(context, len, name_str.toValue());
        }
    } else {
        arr = v8.Array{ .handle = @ptrCast(existing.?.handle) };
    }

    // Append value
    const len = arr.length();
    _ = arr.castTo(v8.Object).setValueAtIndex(context, len, value_arg);
}

fn formDataDelete(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
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

    // Get storage and delete key
    const storage_val = this.getValue(context, v8.String.initUtf8(isolate, "_storage")) catch return;
    if (!storage_val.isObject()) return;
    const storage = v8.Object{ .handle = @ptrCast(storage_val.handle) };

    // Set to undefined to "delete"
    _ = storage.setValue(context, v8.String.initUtf8(isolate, name), isolate.initUndefined().toValue());
}

fn formDataGet(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
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
    var name_buf: [256]u8 = undefined;
    const name_len = name_str.writeUtf8(isolate, &name_buf);
    const name = name_buf[0..name_len];

    // Get storage
    const storage_val = this.getValue(context, v8.String.initUtf8(isolate, "_storage")) catch {
        info.getReturnValue().set(isolate.initNull().toValue());
        return;
    };
    if (!storage_val.isObject()) {
        info.getReturnValue().set(isolate.initNull().toValue());
        return;
    }
    const storage = v8.Object{ .handle = @ptrCast(storage_val.handle) };

    // Get array for this key
    const arr_val = storage.getValue(context, v8.String.initUtf8(isolate, name)) catch {
        info.getReturnValue().set(isolate.initNull().toValue());
        return;
    };

    if (arr_val.isUndefined() or !arr_val.isArray()) {
        info.getReturnValue().set(isolate.initNull().toValue());
        return;
    }

    const arr = v8.Array{ .handle = @ptrCast(arr_val.handle) };
    if (arr.length() == 0) {
        info.getReturnValue().set(isolate.initNull().toValue());
        return;
    }

    // Return first value
    const first = arr.castTo(v8.Object).getAtIndex(context, 0) catch {
        info.getReturnValue().set(isolate.initNull().toValue());
        return;
    };
    info.getReturnValue().set(first);
}

fn formDataGetAll(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    if (info.length() < 1) {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(v8.Array.init(isolate, 0).handle) });
        return;
    }

    const name_arg = info.getArg(0);
    const name_str = name_arg.toString(context) catch {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(v8.Array.init(isolate, 0).handle) });
        return;
    };
    var name_buf: [256]u8 = undefined;
    const name_len = name_str.writeUtf8(isolate, &name_buf);
    const name = name_buf[0..name_len];

    // Get storage
    const storage_val = this.getValue(context, v8.String.initUtf8(isolate, "_storage")) catch {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(v8.Array.init(isolate, 0).handle) });
        return;
    };
    if (!storage_val.isObject()) {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(v8.Array.init(isolate, 0).handle) });
        return;
    }
    const storage = v8.Object{ .handle = @ptrCast(storage_val.handle) };

    // Get array for this key
    const arr_val = storage.getValue(context, v8.String.initUtf8(isolate, name)) catch {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(v8.Array.init(isolate, 0).handle) });
        return;
    };

    if (arr_val.isUndefined() or !arr_val.isArray()) {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(v8.Array.init(isolate, 0).handle) });
        return;
    }

    info.getReturnValue().set(arr_val);
}

fn formDataHas(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
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

    // Get storage
    const storage_val = this.getValue(context, v8.String.initUtf8(isolate, "_storage")) catch {
        info.getReturnValue().set(v8.Value{ .handle = v8.Boolean.init(isolate, false).handle });
        return;
    };
    if (!storage_val.isObject()) {
        info.getReturnValue().set(v8.Value{ .handle = v8.Boolean.init(isolate, false).handle });
        return;
    }
    const storage = v8.Object{ .handle = @ptrCast(storage_val.handle) };

    // Check if key exists
    const arr_val = storage.getValue(context, v8.String.initUtf8(isolate, name)) catch {
        info.getReturnValue().set(v8.Value{ .handle = v8.Boolean.init(isolate, false).handle });
        return;
    };

    const has = !arr_val.isUndefined() and arr_val.isArray();
    info.getReturnValue().set(v8.Value{ .handle = v8.Boolean.init(isolate, has).handle });
}

fn formDataSet(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    if (info.length() < 2) return;

    const name_arg = info.getArg(0);
    const value_arg = info.getArg(1);

    // Get name as string
    const name_str = name_arg.toString(context) catch return;
    var name_buf: [256]u8 = undefined;
    const name_len = name_str.writeUtf8(isolate, &name_buf);
    const name = name_buf[0..name_len];

    // Get storage
    const storage_val = this.getValue(context, v8.String.initUtf8(isolate, "_storage")) catch return;
    if (!storage_val.isObject()) return;
    const storage = v8.Object{ .handle = @ptrCast(storage_val.handle) };

    // Check if key already exists
    const existing = storage.getValue(context, v8.String.initUtf8(isolate, name)) catch null;
    const is_new = (existing == null or existing.?.isUndefined());

    // Create new array with single value
    const arr = v8.Array.init(isolate, 1);
    _ = arr.castTo(v8.Object).setValueAtIndex(context, 0, value_arg);
    _ = storage.setValue(context, v8.String.initUtf8(isolate, name), v8.Value{ .handle = @ptrCast(arr.handle) });

    // Add to keys list if new
    if (is_new) {
        const keys_val = this.getValue(context, v8.String.initUtf8(isolate, "_keys")) catch return;
        if (keys_val.isArray()) {
            const keys_arr = v8.Array{ .handle = @ptrCast(keys_val.handle) };
            const len = keys_arr.length();
            _ = keys_arr.castTo(v8.Object).setValueAtIndex(context, len, name_str.toValue());
        }
    }
}

fn formDataEntries(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    // Return array of [key, value] pairs (simplified - not a true iterator)
    const result = v8.Array.init(isolate, 0);

    const storage_val = this.getValue(context, v8.String.initUtf8(isolate, "_storage")) catch {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
        return;
    };
    if (!storage_val.isObject()) {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
        return;
    }
    const storage = v8.Object{ .handle = @ptrCast(storage_val.handle) };

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

        const values_val = storage.getValue(context, v8.String.initUtf8(isolate, key_name)) catch continue;
        if (!values_val.isArray()) continue;
        const values_arr = v8.Array{ .handle = @ptrCast(values_val.handle) };
        const values_len = values_arr.length();

        var j: u32 = 0;
        while (j < values_len) : (j += 1) {
            const val = values_arr.castTo(v8.Object).getAtIndex(context, j) catch continue;

            // Create [key, value] pair
            const pair = v8.Array.init(isolate, 2);
            _ = pair.castTo(v8.Object).setValueAtIndex(context, 0, key);
            _ = pair.castTo(v8.Object).setValueAtIndex(context, 1, val);
            _ = result.castTo(v8.Object).setValueAtIndex(context, result_idx, v8.Value{ .handle = @ptrCast(pair.handle) });
            result_idx += 1;
        }
    }

    info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
}

fn formDataKeys(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    const keys_val = this.getValue(context, v8.String.initUtf8(isolate, "_keys")) catch {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(v8.Array.init(isolate, 0).handle) });
        return;
    };
    info.getReturnValue().set(keys_val);
}

fn formDataValues(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    // Collect all values
    const result = v8.Array.init(isolate, 0);

    const storage_val = this.getValue(context, v8.String.initUtf8(isolate, "_storage")) catch {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
        return;
    };
    if (!storage_val.isObject()) {
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
        return;
    }
    const storage = v8.Object{ .handle = @ptrCast(storage_val.handle) };

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

        const values_val = storage.getValue(context, v8.String.initUtf8(isolate, key_name)) catch continue;
        if (!values_val.isArray()) continue;
        const values_arr = v8.Array{ .handle = @ptrCast(values_val.handle) };
        const values_len = values_arr.length();

        var j: u32 = 0;
        while (j < values_len) : (j += 1) {
            const val = values_arr.castTo(v8.Object).getAtIndex(context, j) catch continue;
            _ = result.castTo(v8.Object).setValueAtIndex(context, result_idx, val);
            result_idx += 1;
        }
    }

    info.getReturnValue().set(v8.Value{ .handle = @ptrCast(result.handle) });
}
