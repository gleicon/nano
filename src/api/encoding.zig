const std = @import("std");
const v8 = @import("v8");
const js = @import("js");

/// Register encoding APIs on global object
pub fn registerEncodingAPIs(isolate: v8.Isolate, context: v8.Context) void {
    const global = context.getGlobal();

    // Register global functions
    js.addGlobalFn(global, context, isolate, "atob", atobCallback);
    js.addGlobalFn(global, context, isolate, "btoa", btoaCallback);

    // Register TextEncoder constructor
    const encoder_tmpl = v8.FunctionTemplate.initCallback(isolate, textEncoderConstructor);
    const encoder_proto = encoder_tmpl.getPrototypeTemplate();
    js.addMethod(encoder_proto, isolate, "encode", textEncoderEncode);
    js.addGlobalClass(global, context, isolate, "TextEncoder", encoder_tmpl);

    // Register TextDecoder constructor
    const decoder_tmpl = v8.FunctionTemplate.initCallback(isolate, textDecoderConstructor);
    const decoder_proto = decoder_tmpl.getPrototypeTemplate();
    js.addMethod(decoder_proto, isolate, "decode", textDecoderDecode);
    js.addGlobalClass(global, context, isolate, "TextDecoder", decoder_tmpl);
}

fn atobCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) {
        js.throw(ctx.isolate, "atob requires 1 argument");
        return;
    }

    const str = ctx.arg(0).toString(ctx.context) catch {
        js.throw(ctx.isolate, "atob: invalid argument");
        return;
    };

    // Stack+heap fallback for input buffer
    const str_len = str.lenUtf8(ctx.isolate);
    var stack_input_buf: [8192]u8 = undefined;
    const heap_input_buf = if (str_len > 8192)
        std.heap.page_allocator.alloc(u8, str_len) catch {
            js.throw(ctx.isolate, "atob: out of memory");
            return;
        }
    else
        null;
    defer if (heap_input_buf) |buf| std.heap.page_allocator.free(buf);
    const input = js.readString(ctx.isolate, str, if (heap_input_buf) |buf| buf else &stack_input_buf);

    const decoder = std.base64.standard.Decoder;
    const decoded_size = decoder.calcSizeForSlice(input) catch {
        js.throw(ctx.isolate, "atob: invalid base64");
        return;
    };

    // Stack+heap fallback for output buffer
    var stack_output_buf: [8192]u8 = undefined;
    const heap_output_buf = if (decoded_size > 8192)
        std.heap.page_allocator.alloc(u8, decoded_size) catch {
            js.throw(ctx.isolate, "atob: out of memory");
            return;
        }
    else
        null;
    defer if (heap_output_buf) |buf| std.heap.page_allocator.free(buf);
    const output_buf = if (heap_output_buf) |buf| buf else stack_output_buf[0..decoded_size];

    decoder.decode(output_buf, input) catch {
        js.throw(ctx.isolate, "atob: invalid base64");
        return;
    };

    js.retString(ctx, output_buf);
}

fn btoaCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) {
        js.throw(ctx.isolate, "btoa requires 1 argument");
        return;
    }

    const str = ctx.arg(0).toString(ctx.context) catch {
        js.throw(ctx.isolate, "btoa: invalid argument");
        return;
    };

    // Stack+heap fallback for input buffer
    const str_len = str.lenUtf8(ctx.isolate);
    var stack_input_buf: [8192]u8 = undefined;
    const heap_input_buf = if (str_len > 8192)
        std.heap.page_allocator.alloc(u8, str_len) catch {
            js.throw(ctx.isolate, "btoa: out of memory");
            return;
        }
    else
        null;
    defer if (heap_input_buf) |buf| std.heap.page_allocator.free(buf);
    const input = js.readString(ctx.isolate, str, if (heap_input_buf) |buf| buf else &stack_input_buf);

    const encoder = std.base64.standard.Encoder;

    // Stack+heap fallback for output buffer (base64 expands by ~4/3)
    const encoded_size = encoder.calcSize(input.len);
    var stack_output_buf: [16384]u8 = undefined;
    const heap_output_buf = if (encoded_size > 16384)
        std.heap.page_allocator.alloc(u8, encoded_size) catch {
            js.throw(ctx.isolate, "btoa: out of memory");
            return;
        }
    else
        null;
    defer if (heap_output_buf) |buf| std.heap.page_allocator.free(buf);
    const output_buf = if (heap_output_buf) |buf| buf else stack_output_buf[0..encoded_size];

    const encoded = encoder.encode(output_buf, input);

    js.retString(ctx, encoded);
}

fn textEncoderConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "encoding", js.string(ctx.isolate, "utf-8"));
}

fn textEncoderEncode(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) {
        const array_buffer = v8.ArrayBuffer.init(ctx.isolate, 0);
        const uint8_array = v8.Uint8Array.init(array_buffer, 0, 0);
        js.ret(ctx, uint8_array);
        return;
    }

    const str = ctx.arg(0).toString(ctx.context) catch {
        js.throw(ctx.isolate, "encode: invalid argument");
        return;
    };

    const len = str.lenUtf8(ctx.isolate);
    if (len == 0) {
        const array_buffer = v8.ArrayBuffer.init(ctx.isolate, 0);
        const uint8_array = v8.Uint8Array.init(array_buffer, 0, 0);
        js.ret(ctx, uint8_array);
        return;
    }

    const backing = v8.BackingStore.init(ctx.isolate, len);
    const data = backing.getData();

    if (data) |ptr| {
        const slice: []u8 = @as([*]u8, @ptrCast(ptr))[0..len];
        _ = str.writeUtf8(ctx.isolate, slice);
    }

    const shared_ptr = backing.toSharedPtr();
    const array_buffer = v8.ArrayBuffer.initWithBackingStore(ctx.isolate, &shared_ptr);
    const uint8_array = v8.Uint8Array.init(array_buffer, 0, len);
    js.ret(ctx, uint8_array);
}

fn textDecoderConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() >= 1) {
        const arg = ctx.arg(0);
        if (arg.isString()) {
            const str = arg.toString(ctx.context) catch {
                _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "encoding", js.string(ctx.isolate, "utf-8"));
                return;
            };
            var buf: [32]u8 = undefined;
            const enc_str = js.readString(ctx.isolate, str, &buf);
            if (!std.mem.eql(u8, enc_str, "utf-8") and !std.mem.eql(u8, enc_str, "utf8")) {
                js.throw(ctx.isolate, "TextDecoder: only utf-8 supported");
                return;
            }
        }
    }

    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "encoding", js.string(ctx.isolate, "utf-8"));
}

fn textDecoderDecode(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) {
        js.retString(ctx, "");
        return;
    }

    const arg = ctx.arg(0);

    // Handle ArrayBuffer input
    if (arg.isArrayBuffer()) {
        const ab = js.asArrayBuffer(arg);
        const ab_len = ab.getByteLength();
        if (ab_len == 0) {
            js.retString(ctx, "");
            return;
        }
        const shared_ptr = ab.getBackingStore();
        const backing_store = v8.BackingStore.sharedPtrGet(&shared_ptr);
        const data = backing_store.getData();
        if (data) |ptr| {
            const byte_ptr: [*]const u8 = @ptrCast(ptr);
            js.retString(ctx, byte_ptr[0..ab_len]);
            return;
        }
        js.retString(ctx, "");
        return;
    }

    // Handle TypedArray (ArrayBufferView) input
    if (arg.isArrayBufferView()) {
        const view = js.asArrayBufferView(arg);
        const ab = view.getBuffer();
        const byte_len = view.getByteLength();
        const byte_offset = view.getByteOffset();
        if (byte_len == 0) {
            js.retString(ctx, "");
            return;
        }
        const shared_ptr = ab.getBackingStore();
        const backing_store = v8.BackingStore.sharedPtrGet(&shared_ptr);
        const data = backing_store.getData();
        if (data) |ptr| {
            const byte_ptr: [*]const u8 = @ptrCast(ptr);
            js.retString(ctx, byte_ptr[byte_offset .. byte_offset + byte_len]);
            return;
        }
        js.retString(ctx, "");
        return;
    }

    // Convert string argument directly
    if (arg.isString()) {
        const str = arg.toString(ctx.context) catch {
            js.throw(ctx.isolate, "decode: invalid input");
            return;
        };
        js.ret(ctx, str);
        return;
    }

    js.throw(ctx.isolate, "decode: expected ArrayBuffer, TypedArray, or string");
}
