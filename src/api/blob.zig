const std = @import("std");
const v8 = @import("v8");

/// Allocator for blob data
const blob_allocator = std.heap.page_allocator;

/// Register Blob and File APIs
pub fn registerBlobAPI(isolate: v8.Isolate, context: v8.Context) void {
    const global = context.getGlobal();

    // Register Blob constructor
    const blob_tmpl = v8.FunctionTemplate.initCallback(isolate, blobConstructor);
    const blob_proto = blob_tmpl.getPrototypeTemplate();

    // Blob.size getter
    const size_fn = v8.FunctionTemplate.initCallback(isolate, blobSize);
    blob_proto.set(v8.String.initUtf8(isolate, "size").toName(), size_fn, v8.PropertyAttribute.None);

    // Blob.type getter
    const type_fn = v8.FunctionTemplate.initCallback(isolate, blobType);
    blob_proto.set(v8.String.initUtf8(isolate, "type").toName(), type_fn, v8.PropertyAttribute.None);

    // Blob.text() method
    const text_fn = v8.FunctionTemplate.initCallback(isolate, blobText);
    blob_proto.set(v8.String.initUtf8(isolate, "text").toName(), text_fn, v8.PropertyAttribute.None);

    // Blob.arrayBuffer() method
    const arraybuffer_fn = v8.FunctionTemplate.initCallback(isolate, blobArrayBuffer);
    blob_proto.set(v8.String.initUtf8(isolate, "arrayBuffer").toName(), arraybuffer_fn, v8.PropertyAttribute.None);

    // Blob.slice() method
    const slice_fn = v8.FunctionTemplate.initCallback(isolate, blobSlice);
    blob_proto.set(v8.String.initUtf8(isolate, "slice").toName(), slice_fn, v8.PropertyAttribute.None);

    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "Blob"),
        blob_tmpl.getFunction(context),
    );

    // Register File constructor (extends Blob)
    const file_tmpl = v8.FunctionTemplate.initCallback(isolate, fileConstructor);
    const file_proto = file_tmpl.getPrototypeTemplate();

    // Inherit Blob methods
    file_proto.set(v8.String.initUtf8(isolate, "size").toName(), size_fn, v8.PropertyAttribute.None);
    file_proto.set(v8.String.initUtf8(isolate, "type").toName(), type_fn, v8.PropertyAttribute.None);
    file_proto.set(v8.String.initUtf8(isolate, "text").toName(), text_fn, v8.PropertyAttribute.None);
    file_proto.set(v8.String.initUtf8(isolate, "arrayBuffer").toName(), arraybuffer_fn, v8.PropertyAttribute.None);
    file_proto.set(v8.String.initUtf8(isolate, "slice").toName(), slice_fn, v8.PropertyAttribute.None);

    // File-specific methods
    const name_fn = v8.FunctionTemplate.initCallback(isolate, fileName);
    file_proto.set(v8.String.initUtf8(isolate, "name").toName(), name_fn, v8.PropertyAttribute.None);

    const lastmodified_fn = v8.FunctionTemplate.initCallback(isolate, fileLastModified);
    file_proto.set(v8.String.initUtf8(isolate, "lastModified").toName(), lastmodified_fn, v8.PropertyAttribute.None);

    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "File"),
        file_tmpl.getFunction(context),
    );
}

/// Create a Blob object from data (internal helper)
pub fn createBlob(isolate: v8.Isolate, context: v8.Context, data: []const u8, mime_type: []const u8) v8.Object {
    const global = context.getGlobal();
    const blob_ctor_val = global.getValue(context, v8.String.initUtf8(isolate, "Blob")) catch {
        return isolate.initObjectTemplateDefault().initInstance(context);
    };
    const blob_ctor = v8.Function{ .handle = @ptrCast(blob_ctor_val.handle) };

    var args: [0]v8.Value = .{};
    const blob = blob_ctor.initInstance(context, &args) orelse {
        return isolate.initObjectTemplateDefault().initInstance(context);
    };

    // Store data as base64 string (simple approach for now)
    // For production, use ArrayBuffer backing store
    const base64_encoder = std.base64.standard;
    const encoded_len = base64_encoder.Encoder.calcSize(data.len);
    const encoded = blob_allocator.alloc(u8, encoded_len) catch {
        return blob;
    };
    defer blob_allocator.free(encoded);
    _ = base64_encoder.Encoder.encode(encoded, data);

    _ = blob.setValue(context, v8.String.initUtf8(isolate, "_data"), v8.String.initUtf8(isolate, encoded).toValue());
    _ = blob.setValue(context, v8.String.initUtf8(isolate, "_size"), v8.Number.init(isolate, @floatFromInt(data.len)).toValue());
    _ = blob.setValue(context, v8.String.initUtf8(isolate, "_type"), v8.String.initUtf8(isolate, mime_type).toValue());

    return blob;
}

// === Blob implementation ===

fn blobConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    var total_size: usize = 0;
    var mime_type: []const u8 = "";

    // First argument: array of parts (optional)
    if (info.length() >= 1) {
        const parts_arg = info.getArg(0);
        if (parts_arg.isArray()) {
            // Process array of parts (strings, ArrayBuffers, Blobs)
            const arr = v8.Array{ .handle = @ptrCast(parts_arg.handle) };
            const len = arr.length();

            // Accumulate data (simplified - just count size for now)
            var i: u32 = 0;
            while (i < len) : (i += 1) {
                const elem = arr.castTo(v8.Object).getAtIndex(context, i) catch continue;
                if (elem.isString()) {
                    const str = elem.toString(context) catch continue;
                    total_size += str.lenUtf8(isolate);
                }
            }
        }
    }

    // Second argument: options (optional)
    if (info.length() >= 2) {
        const opts_arg = info.getArg(1);
        if (opts_arg.isObject()) {
            const opts = v8.Object{ .handle = @ptrCast(opts_arg.handle) };
            const type_val = opts.getValue(context, v8.String.initUtf8(isolate, "type")) catch null;
            if (type_val) |tv| {
                if (tv.isString()) {
                    var type_buf: [128]u8 = undefined;
                    const type_str = tv.toString(context) catch null;
                    if (type_str) |ts| {
                        const type_len = ts.writeUtf8(isolate, &type_buf);
                        mime_type = type_buf[0..type_len];
                    }
                }
            }
        }
    }

    // Store blob data
    _ = this.setValue(context, v8.String.initUtf8(isolate, "_data"), v8.String.initUtf8(isolate, "").toValue());
    _ = this.setValue(context, v8.String.initUtf8(isolate, "_size"), v8.Number.init(isolate, @floatFromInt(total_size)).toValue());
    _ = this.setValue(context, v8.String.initUtf8(isolate, "_type"), v8.String.initUtf8(isolate, mime_type).toValue());

    // If we have parts, concatenate them
    if (info.length() >= 1) {
        const parts_arg = info.getArg(0);
        if (parts_arg.isArray()) {
            const arr = v8.Array{ .handle = @ptrCast(parts_arg.handle) };
            const len = arr.length();

            // Build concatenated data
            var data_buf: [65536]u8 = undefined;
            var offset: usize = 0;

            var i: u32 = 0;
            while (i < len) : (i += 1) {
                const elem = arr.castTo(v8.Object).getAtIndex(context, i) catch continue;
                if (elem.isString()) {
                    const str = elem.toString(context) catch continue;
                    const str_len = str.writeUtf8(isolate, data_buf[offset..]);
                    offset += str_len;
                }
            }

            // Store as base64
            const base64_encoder = std.base64.standard;
            const encoded_len = base64_encoder.Encoder.calcSize(offset);
            if (encoded_len <= 65536) {
                var encoded_buf: [65536]u8 = undefined;
                _ = base64_encoder.Encoder.encode(encoded_buf[0..encoded_len], data_buf[0..offset]);
                _ = this.setValue(context, v8.String.initUtf8(isolate, "_data"), v8.String.initUtf8(isolate, encoded_buf[0..encoded_len]).toValue());
                _ = this.setValue(context, v8.String.initUtf8(isolate, "_size"), v8.Number.init(isolate, @floatFromInt(offset)).toValue());
            }
        }
    }
}

fn blobSize(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    const size_val = this.getValue(context, v8.String.initUtf8(isolate, "_size")) catch {
        info.getReturnValue().set(v8.Number.init(isolate, 0).toValue());
        return;
    };
    info.getReturnValue().set(size_val);
}

fn blobType(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    const type_val = this.getValue(context, v8.String.initUtf8(isolate, "_type")) catch {
        info.getReturnValue().set(v8.String.initUtf8(isolate, "").toValue());
        return;
    };
    info.getReturnValue().set(type_val);
}

fn blobText(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    // Get base64 encoded data
    const data_val = this.getValue(context, v8.String.initUtf8(isolate, "_data")) catch {
        // Return resolved Promise with empty string
        const resolver = v8.PromiseResolver.init(context);
        _ = resolver.resolve(context, v8.String.initUtf8(isolate, "").toValue());
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(resolver.getPromise().handle) });
        return;
    };

    // Decode base64
    var data_buf: [65536]u8 = undefined;
    const data_str = data_val.toString(context) catch {
        const resolver = v8.PromiseResolver.init(context);
        _ = resolver.resolve(context, v8.String.initUtf8(isolate, "").toValue());
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(resolver.getPromise().handle) });
        return;
    };
    const data_len = data_str.writeUtf8(isolate, &data_buf);
    const encoded_data = data_buf[0..data_len];

    // Decode from base64
    const base64_decoder = std.base64.standard;
    const decoded_len = base64_decoder.Decoder.calcSizeForSlice(encoded_data) catch {
        const resolver = v8.PromiseResolver.init(context);
        _ = resolver.resolve(context, v8.String.initUtf8(isolate, "").toValue());
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(resolver.getPromise().handle) });
        return;
    };

    var decoded_buf: [65536]u8 = undefined;
    base64_decoder.Decoder.decode(decoded_buf[0..decoded_len], encoded_data) catch {
        const resolver = v8.PromiseResolver.init(context);
        _ = resolver.resolve(context, v8.String.initUtf8(isolate, "").toValue());
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(resolver.getPromise().handle) });
        return;
    };

    // Return Promise resolved with decoded text
    const resolver = v8.PromiseResolver.init(context);
    _ = resolver.resolve(context, v8.String.initUtf8(isolate, decoded_buf[0..decoded_len]).toValue());
    info.getReturnValue().set(v8.Value{ .handle = @ptrCast(resolver.getPromise().handle) });
}

fn blobArrayBuffer(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    // Get size
    const size_val = this.getValue(context, v8.String.initUtf8(isolate, "_size")) catch {
        const resolver = v8.PromiseResolver.init(context);
        _ = resolver.reject(context, v8.String.initUtf8(isolate, "Failed to get blob size").toValue());
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(resolver.getPromise().handle) });
        return;
    };

    const size_f = size_val.toF64(context) catch 0;
    const size: usize = @intFromFloat(size_f);

    // Create ArrayBuffer
    const ab = v8.ArrayBuffer.init(isolate, size);

    // Get data and decode
    const data_val = this.getValue(context, v8.String.initUtf8(isolate, "_data")) catch {
        const resolver = v8.PromiseResolver.init(context);
        _ = resolver.resolve(context, v8.Value{ .handle = @ptrCast(ab.handle) });
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(resolver.getPromise().handle) });
        return;
    };

    var data_buf: [65536]u8 = undefined;
    const data_str = data_val.toString(context) catch {
        const resolver = v8.PromiseResolver.init(context);
        _ = resolver.resolve(context, v8.Value{ .handle = @ptrCast(ab.handle) });
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(resolver.getPromise().handle) });
        return;
    };
    const data_len = data_str.writeUtf8(isolate, &data_buf);

    // Decode base64 and copy to ArrayBuffer
    const base64_decoder = std.base64.standard;
    const decoded_len = base64_decoder.Decoder.calcSizeForSlice(data_buf[0..data_len]) catch {
        const resolver = v8.PromiseResolver.init(context);
        _ = resolver.resolve(context, v8.Value{ .handle = @ptrCast(ab.handle) });
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(resolver.getPromise().handle) });
        return;
    };

    const shared_ptr = ab.getBackingStore();
    const backing_store = v8.BackingStore.sharedPtrGet(&shared_ptr);
    const ab_data = backing_store.getData();
    if (ab_data) |ptr| {
        var decoded_buf: [65536]u8 = undefined;
        base64_decoder.Decoder.decode(decoded_buf[0..decoded_len], data_buf[0..data_len]) catch {};
        const byte_ptr: [*]u8 = @ptrCast(ptr);
        @memcpy(byte_ptr[0..decoded_len], decoded_buf[0..decoded_len]);
    }

    const resolver = v8.PromiseResolver.init(context);
    _ = resolver.resolve(context, v8.Value{ .handle = @ptrCast(ab.handle) });
    info.getReturnValue().set(v8.Value{ .handle = @ptrCast(resolver.getPromise().handle) });
}

fn blobSlice(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    // Get current size
    const size_val = this.getValue(context, v8.String.initUtf8(isolate, "_size")) catch {
        info.getReturnValue().set(this);
        return;
    };
    const size_f = size_val.toF64(context) catch 0;
    const size: i64 = @intFromFloat(size_f);

    // Parse arguments
    var start: i64 = 0;
    var end: i64 = size;

    if (info.length() >= 1) {
        const start_arg = info.getArg(0);
        if (start_arg.isNumber()) {
            start = @intFromFloat(start_arg.toF64(context) catch 0);
            if (start < 0) start = @max(size + start, 0);
        }
    }

    if (info.length() >= 2) {
        const end_arg = info.getArg(1);
        if (end_arg.isNumber()) {
            end = @intFromFloat(end_arg.toF64(context) catch size_f);
            if (end < 0) end = @max(size + end, 0);
        }
    }

    // Clamp values
    start = @min(@max(start, 0), size);
    end = @min(@max(end, 0), size);
    if (end < start) end = start;

    // Get content type
    var content_type: []const u8 = "";
    if (info.length() >= 3) {
        const type_arg = info.getArg(2);
        if (type_arg.isString()) {
            var type_buf: [128]u8 = undefined;
            const type_str = type_arg.toString(context) catch null;
            if (type_str) |ts| {
                const type_len = ts.writeUtf8(isolate, &type_buf);
                content_type = type_buf[0..type_len];
            }
        }
    } else {
        // Use original type
        const type_val = this.getValue(context, v8.String.initUtf8(isolate, "_type")) catch null;
        if (type_val) |tv| {
            var type_buf: [128]u8 = undefined;
            const type_str = tv.toString(context) catch null;
            if (type_str) |ts| {
                const type_len = ts.writeUtf8(isolate, &type_buf);
                content_type = type_buf[0..type_len];
            }
        }
    }

    // Create new blob (simplified - just adjust size metadata)
    const global = context.getGlobal();
    const blob_ctor_val = global.getValue(context, v8.String.initUtf8(isolate, "Blob")) catch {
        info.getReturnValue().set(this);
        return;
    };
    const blob_ctor = v8.Function{ .handle = @ptrCast(blob_ctor_val.handle) };

    var args: [0]v8.Value = .{};
    const new_blob = blob_ctor.initInstance(context, &args) orelse {
        info.getReturnValue().set(this);
        return;
    };

    // Copy sliced data (simplified)
    const slice_size: usize = @intCast(end - start);
    _ = new_blob.setValue(context, v8.String.initUtf8(isolate, "_size"), v8.Number.init(isolate, @floatFromInt(slice_size)).toValue());
    _ = new_blob.setValue(context, v8.String.initUtf8(isolate, "_type"), v8.String.initUtf8(isolate, content_type).toValue());

    // Note: Full implementation would slice the actual data
    // For now, just return empty blob with correct size metadata
    _ = new_blob.setValue(context, v8.String.initUtf8(isolate, "_data"), v8.String.initUtf8(isolate, "").toValue());

    info.getReturnValue().set(v8.Value{ .handle = @ptrCast(new_blob.handle) });
}

// === File implementation ===

fn fileConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    // Initialize as empty blob
    _ = this.setValue(context, v8.String.initUtf8(isolate, "_data"), v8.String.initUtf8(isolate, "").toValue());
    _ = this.setValue(context, v8.String.initUtf8(isolate, "_size"), v8.Number.init(isolate, 0).toValue());
    _ = this.setValue(context, v8.String.initUtf8(isolate, "_type"), v8.String.initUtf8(isolate, "").toValue());
    _ = this.setValue(context, v8.String.initUtf8(isolate, "_name"), v8.String.initUtf8(isolate, "").toValue());

    // Get current timestamp
    const now = std.time.milliTimestamp();
    _ = this.setValue(context, v8.String.initUtf8(isolate, "_lastModified"), v8.Number.init(isolate, @floatFromInt(now)).toValue());

    // First argument: file bits (array)
    if (info.length() >= 1) {
        const parts_arg = info.getArg(0);
        if (parts_arg.isArray()) {
            const arr = v8.Array{ .handle = @ptrCast(parts_arg.handle) };
            const len = arr.length();

            var data_buf: [65536]u8 = undefined;
            var offset: usize = 0;

            var i: u32 = 0;
            while (i < len) : (i += 1) {
                const elem = arr.castTo(v8.Object).getAtIndex(context, i) catch continue;
                if (elem.isString()) {
                    const str = elem.toString(context) catch continue;
                    const str_len = str.writeUtf8(isolate, data_buf[offset..]);
                    offset += str_len;
                }
            }

            // Store as base64
            const base64_encoder = std.base64.standard;
            const encoded_len = base64_encoder.Encoder.calcSize(offset);
            if (encoded_len <= 65536) {
                var encoded_buf: [65536]u8 = undefined;
                _ = base64_encoder.Encoder.encode(encoded_buf[0..encoded_len], data_buf[0..offset]);
                _ = this.setValue(context, v8.String.initUtf8(isolate, "_data"), v8.String.initUtf8(isolate, encoded_buf[0..encoded_len]).toValue());
                _ = this.setValue(context, v8.String.initUtf8(isolate, "_size"), v8.Number.init(isolate, @floatFromInt(offset)).toValue());
            }
        }
    }

    // Second argument: filename
    if (info.length() >= 2) {
        const name_arg = info.getArg(1);
        if (name_arg.isString()) {
            _ = this.setValue(context, v8.String.initUtf8(isolate, "_name"), name_arg);
        }
    }

    // Third argument: options
    if (info.length() >= 3) {
        const opts_arg = info.getArg(2);
        if (opts_arg.isObject()) {
            const opts = v8.Object{ .handle = @ptrCast(opts_arg.handle) };

            const type_val = opts.getValue(context, v8.String.initUtf8(isolate, "type")) catch null;
            if (type_val) |tv| {
                if (tv.isString()) {
                    _ = this.setValue(context, v8.String.initUtf8(isolate, "_type"), tv);
                }
            }

            const lm_val = opts.getValue(context, v8.String.initUtf8(isolate, "lastModified")) catch null;
            if (lm_val) |lv| {
                if (lv.isNumber()) {
                    _ = this.setValue(context, v8.String.initUtf8(isolate, "_lastModified"), lv);
                }
            }
        }
    }
}

fn fileName(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    const name_val = this.getValue(context, v8.String.initUtf8(isolate, "_name")) catch {
        info.getReturnValue().set(v8.String.initUtf8(isolate, "").toValue());
        return;
    };
    info.getReturnValue().set(name_val);
}

fn fileLastModified(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    const lm_val = this.getValue(context, v8.String.initUtf8(isolate, "_lastModified")) catch {
        info.getReturnValue().set(v8.Number.init(isolate, 0).toValue());
        return;
    };
    info.getReturnValue().set(lm_val);
}
