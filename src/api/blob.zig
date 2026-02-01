const std = @import("std");
const v8 = @import("v8");
const js = @import("js");

/// Allocator for blob data
const blob_allocator = std.heap.page_allocator;

/// Register Blob and File APIs
pub fn registerBlobAPI(isolate: v8.Isolate, context: v8.Context) void {
    const global = context.getGlobal();

    // Register Blob constructor
    const blob_tmpl = v8.FunctionTemplate.initCallback(isolate, blobConstructor);
    const blob_proto = blob_tmpl.getPrototypeTemplate();

    js.addMethod(blob_proto, isolate, "size", blobSize);
    js.addMethod(blob_proto, isolate, "type", blobType);
    js.addMethod(blob_proto, isolate, "text", blobText);
    js.addMethod(blob_proto, isolate, "arrayBuffer", blobArrayBuffer);
    js.addMethod(blob_proto, isolate, "slice", blobSlice);

    js.addGlobalClass(global, context, isolate, "Blob", blob_tmpl);

    // Register File constructor (extends Blob)
    const file_tmpl = v8.FunctionTemplate.initCallback(isolate, fileConstructor);
    const file_proto = file_tmpl.getPrototypeTemplate();

    // Inherit Blob methods
    js.addMethod(file_proto, isolate, "size", blobSize);
    js.addMethod(file_proto, isolate, "type", blobType);
    js.addMethod(file_proto, isolate, "text", blobText);
    js.addMethod(file_proto, isolate, "arrayBuffer", blobArrayBuffer);
    js.addMethod(file_proto, isolate, "slice", blobSlice);

    // File-specific methods
    js.addMethod(file_proto, isolate, "name", fileName);
    js.addMethod(file_proto, isolate, "lastModified", fileLastModified);

    js.addGlobalClass(global, context, isolate, "File", file_tmpl);
}

/// Create a Blob object from data (internal helper)
pub fn createBlob(isolate: v8.Isolate, context: v8.Context, data: []const u8, mime_type: []const u8) v8.Object {
    const global = context.getGlobal();
    const blob_ctor_val = js.getProp(global, context, isolate, "Blob") catch {
        return isolate.initObjectTemplateDefault().initInstance(context);
    };
    const blob_ctor = js.asFunction(blob_ctor_val);

    var args: [0]v8.Value = .{};
    const blob = blob_ctor.initInstance(context, &args) orelse {
        return isolate.initObjectTemplateDefault().initInstance(context);
    };

    // Store data as base64 string
    const base64_encoder = std.base64.standard;
    const encoded_len = base64_encoder.Encoder.calcSize(data.len);
    const encoded = blob_allocator.alloc(u8, encoded_len) catch {
        return blob;
    };
    defer blob_allocator.free(encoded);
    _ = base64_encoder.Encoder.encode(encoded, data);

    _ = js.setProp(blob, context, isolate, "_data", js.string(isolate, encoded));
    _ = js.setProp(blob, context, isolate, "_size", js.number(isolate, data.len));
    _ = js.setProp(blob, context, isolate, "_type", js.string(isolate, mime_type));

    return blob;
}

// === Blob implementation ===

fn blobConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    var total_size: usize = 0;
    var mime_type: []const u8 = "";

    // First argument: array of parts (optional)
    if (ctx.argc() >= 1) {
        const parts_arg = ctx.arg(0);
        if (parts_arg.isArray()) {
            const arr = js.asArray(parts_arg);
            const len = arr.length();

            var i: u32 = 0;
            while (i < len) : (i += 1) {
                const elem = js.getIndex(arr.castTo(v8.Object), ctx.context, i) catch continue;
                if (elem.isString()) {
                    const str = elem.toString(ctx.context) catch continue;
                    total_size += str.lenUtf8(ctx.isolate);
                }
            }
        }
    }

    // Second argument: options (optional)
    if (ctx.argc() >= 2) {
        const opts_arg = ctx.arg(1);
        if (opts_arg.isObject()) {
            const opts = js.asObject(opts_arg);
            const type_val = js.getProp(opts, ctx.context, ctx.isolate, "type") catch null;
            if (type_val) |tv| {
                if (tv.isString()) {
                    var type_buf: [128]u8 = undefined;
                    const type_str = tv.toString(ctx.context) catch null;
                    if (type_str) |ts| {
                        mime_type = js.readString(ctx.isolate, ts, &type_buf);
                    }
                }
            }
        }
    }

    // Store blob data
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_data", js.string(ctx.isolate, ""));
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_size", js.number(ctx.isolate, total_size));
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_type", js.string(ctx.isolate, mime_type));

    // If we have parts, concatenate them
    if (ctx.argc() >= 1) {
        const parts_arg = ctx.arg(0);
        if (parts_arg.isArray()) {
            const arr = js.asArray(parts_arg);
            const len = arr.length();

            var data_buf: [65536]u8 = undefined;
            var offset: usize = 0;

            var i: u32 = 0;
            while (i < len) : (i += 1) {
                const elem = js.getIndex(arr.castTo(v8.Object), ctx.context, i) catch continue;
                if (elem.isString()) {
                    const str = elem.toString(ctx.context) catch continue;
                    const str_len = str.writeUtf8(ctx.isolate, data_buf[offset..]);
                    offset += str_len;
                }
            }

            // Store as base64
            const base64_encoder = std.base64.standard;
            const encoded_len = base64_encoder.Encoder.calcSize(offset);
            if (encoded_len <= 65536) {
                var encoded_buf: [65536]u8 = undefined;
                _ = base64_encoder.Encoder.encode(encoded_buf[0..encoded_len], data_buf[0..offset]);
                _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_data", js.string(ctx.isolate, encoded_buf[0..encoded_len]));
                _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_size", js.number(ctx.isolate, offset));
            }
        }
    }
}

fn blobSize(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const size_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_size") catch {
        js.retNumber(ctx, 0);
        return;
    };
    js.ret(ctx, size_val);
}

fn blobType(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const type_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_type") catch {
        js.retString(ctx, "");
        return;
    };
    js.ret(ctx, type_val);
}

fn blobText(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    // Get base64 encoded data
    const data_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_data") catch {
        const resolver = v8.PromiseResolver.init(ctx.context);
        _ = resolver.resolve(ctx.context, js.string(ctx.isolate, "").toValue());
        js.ret(ctx, resolver.getPromise());
        return;
    };

    // Decode base64
    var data_buf: [65536]u8 = undefined;
    const data_str = data_val.toString(ctx.context) catch {
        const resolver = v8.PromiseResolver.init(ctx.context);
        _ = resolver.resolve(ctx.context, js.string(ctx.isolate, "").toValue());
        js.ret(ctx, resolver.getPromise());
        return;
    };
    const encoded_data = js.readString(ctx.isolate, data_str, &data_buf);

    const base64_decoder = std.base64.standard;
    const decoded_len = base64_decoder.Decoder.calcSizeForSlice(encoded_data) catch {
        const resolver = v8.PromiseResolver.init(ctx.context);
        _ = resolver.resolve(ctx.context, js.string(ctx.isolate, "").toValue());
        js.ret(ctx, resolver.getPromise());
        return;
    };

    var decoded_buf: [65536]u8 = undefined;
    base64_decoder.Decoder.decode(decoded_buf[0..decoded_len], encoded_data) catch {
        const resolver = v8.PromiseResolver.init(ctx.context);
        _ = resolver.resolve(ctx.context, js.string(ctx.isolate, "").toValue());
        js.ret(ctx, resolver.getPromise());
        return;
    };

    const resolver = v8.PromiseResolver.init(ctx.context);
    _ = resolver.resolve(ctx.context, js.string(ctx.isolate, decoded_buf[0..decoded_len]).toValue());
    js.ret(ctx, resolver.getPromise());
}

fn blobArrayBuffer(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    // Get size
    const size_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_size") catch {
        const resolver = v8.PromiseResolver.init(ctx.context);
        _ = resolver.reject(ctx.context, js.string(ctx.isolate, "Failed to get blob size").toValue());
        js.ret(ctx, resolver.getPromise());
        return;
    };

    const size_f = size_val.toF64(ctx.context) catch 0;
    const size: usize = @intFromFloat(size_f);

    // Create ArrayBuffer
    const ab = v8.ArrayBuffer.init(ctx.isolate, size);

    // Get data and decode
    const data_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_data") catch {
        const resolver = v8.PromiseResolver.init(ctx.context);
        _ = resolver.resolve(ctx.context, v8.Value{ .handle = @ptrCast(ab.handle) });
        js.ret(ctx, resolver.getPromise());
        return;
    };

    var data_buf: [65536]u8 = undefined;
    const data_str = data_val.toString(ctx.context) catch {
        const resolver = v8.PromiseResolver.init(ctx.context);
        _ = resolver.resolve(ctx.context, v8.Value{ .handle = @ptrCast(ab.handle) });
        js.ret(ctx, resolver.getPromise());
        return;
    };
    const encoded_data = js.readString(ctx.isolate, data_str, &data_buf);

    // Decode base64 and copy to ArrayBuffer
    const base64_decoder = std.base64.standard;
    const decoded_len = base64_decoder.Decoder.calcSizeForSlice(encoded_data) catch {
        const resolver = v8.PromiseResolver.init(ctx.context);
        _ = resolver.resolve(ctx.context, v8.Value{ .handle = @ptrCast(ab.handle) });
        js.ret(ctx, resolver.getPromise());
        return;
    };

    const shared_ptr = ab.getBackingStore();
    const backing_store = v8.BackingStore.sharedPtrGet(&shared_ptr);
    const ab_data = backing_store.getData();
    if (ab_data) |ptr| {
        var decoded_buf: [65536]u8 = undefined;
        base64_decoder.Decoder.decode(decoded_buf[0..decoded_len], encoded_data) catch {};
        const byte_ptr: [*]u8 = @ptrCast(ptr);
        @memcpy(byte_ptr[0..decoded_len], decoded_buf[0..decoded_len]);
    }

    const resolver = v8.PromiseResolver.init(ctx.context);
    _ = resolver.resolve(ctx.context, v8.Value{ .handle = @ptrCast(ab.handle) });
    js.ret(ctx, resolver.getPromise());
}

fn blobSlice(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    // Get current size
    const size_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_size") catch {
        js.ret(ctx, ctx.this);
        return;
    };
    const size_f = size_val.toF64(ctx.context) catch 0;
    const size: i64 = @intFromFloat(size_f);

    // Parse arguments
    var start: i64 = 0;
    var end: i64 = size;

    if (ctx.argc() >= 1) {
        const start_arg = ctx.arg(0);
        if (start_arg.isNumber()) {
            start = @intFromFloat(start_arg.toF64(ctx.context) catch 0);
            if (start < 0) start = @max(size + start, 0);
        }
    }

    if (ctx.argc() >= 2) {
        const end_arg = ctx.arg(1);
        if (end_arg.isNumber()) {
            end = @intFromFloat(end_arg.toF64(ctx.context) catch size_f);
            if (end < 0) end = @max(size + end, 0);
        }
    }

    // Clamp values
    start = @min(@max(start, 0), size);
    end = @min(@max(end, 0), size);
    if (end < start) end = start;

    // Get content type
    var content_type: []const u8 = "";
    if (ctx.argc() >= 3) {
        const type_arg = ctx.arg(2);
        if (type_arg.isString()) {
            var type_buf: [128]u8 = undefined;
            const type_str = type_arg.toString(ctx.context) catch null;
            if (type_str) |ts| {
                content_type = js.readString(ctx.isolate, ts, &type_buf);
            }
        }
    } else {
        // Use original type
        const type_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_type") catch null;
        if (type_val) |tv| {
            var type_buf: [128]u8 = undefined;
            const type_str = tv.toString(ctx.context) catch null;
            if (type_str) |ts| {
                content_type = js.readString(ctx.isolate, ts, &type_buf);
            }
        }
    }

    // Create new blob
    const global = ctx.context.getGlobal();
    const blob_ctor_val = js.getProp(global, ctx.context, ctx.isolate, "Blob") catch {
        js.ret(ctx, ctx.this);
        return;
    };
    const blob_ctor = js.asFunction(blob_ctor_val);

    var args: [0]v8.Value = .{};
    const new_blob = blob_ctor.initInstance(ctx.context, &args) orelse {
        js.ret(ctx, ctx.this);
        return;
    };

    // Copy sliced data (simplified)
    const slice_size: usize = @intCast(end - start);
    _ = js.setProp(new_blob, ctx.context, ctx.isolate, "_size", js.number(ctx.isolate, slice_size));
    _ = js.setProp(new_blob, ctx.context, ctx.isolate, "_type", js.string(ctx.isolate, content_type));
    _ = js.setProp(new_blob, ctx.context, ctx.isolate, "_data", js.string(ctx.isolate, ""));

    js.ret(ctx, new_blob);
}

// === File implementation ===

fn fileConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    // Initialize as empty blob
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_data", js.string(ctx.isolate, ""));
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_size", js.number(ctx.isolate, 0));
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_type", js.string(ctx.isolate, ""));
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_name", js.string(ctx.isolate, ""));

    // Get current timestamp
    const now = std.time.milliTimestamp();
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_lastModified", js.number(ctx.isolate, now));

    // First argument: file bits (array)
    if (ctx.argc() >= 1) {
        const parts_arg = ctx.arg(0);
        if (parts_arg.isArray()) {
            const arr = js.asArray(parts_arg);
            const len = arr.length();

            var data_buf: [65536]u8 = undefined;
            var offset: usize = 0;

            var i: u32 = 0;
            while (i < len) : (i += 1) {
                const elem = js.getIndex(arr.castTo(v8.Object), ctx.context, i) catch continue;
                if (elem.isString()) {
                    const str = elem.toString(ctx.context) catch continue;
                    const str_len = str.writeUtf8(ctx.isolate, data_buf[offset..]);
                    offset += str_len;
                }
            }

            // Store as base64
            const base64_encoder = std.base64.standard;
            const encoded_len = base64_encoder.Encoder.calcSize(offset);
            if (encoded_len <= 65536) {
                var encoded_buf: [65536]u8 = undefined;
                _ = base64_encoder.Encoder.encode(encoded_buf[0..encoded_len], data_buf[0..offset]);
                _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_data", js.string(ctx.isolate, encoded_buf[0..encoded_len]));
                _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_size", js.number(ctx.isolate, offset));
            }
        }
    }

    // Second argument: filename
    if (ctx.argc() >= 2) {
        const name_arg = ctx.arg(1);
        if (name_arg.isString()) {
            _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_name", name_arg);
        }
    }

    // Third argument: options
    if (ctx.argc() >= 3) {
        const opts_arg = ctx.arg(2);
        if (opts_arg.isObject()) {
            const opts = js.asObject(opts_arg);

            const type_val = js.getProp(opts, ctx.context, ctx.isolate, "type") catch null;
            if (type_val) |tv| {
                if (tv.isString()) {
                    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_type", tv);
                }
            }

            const lm_val = js.getProp(opts, ctx.context, ctx.isolate, "lastModified") catch null;
            if (lm_val) |lv| {
                if (lv.isNumber()) {
                    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_lastModified", lv);
                }
            }
        }
    }
}

fn fileName(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const name_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_name") catch {
        js.retString(ctx, "");
        return;
    };
    js.ret(ctx, name_val);
}

fn fileLastModified(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const lm_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_lastModified") catch {
        js.retNumber(ctx, 0);
        return;
    };
    js.ret(ctx, lm_val);
}
