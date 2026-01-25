const std = @import("std");
const v8 = @import("v8");

/// Register encoding APIs on global object
pub fn registerEncodingAPIs(isolate: v8.Isolate, context: v8.Context) void {
    const global = context.getGlobal();

    // Register atob function
    const atob_fn = v8.FunctionTemplate.initCallback(isolate, atobCallback);
    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "atob"),
        atob_fn.getFunction(context),
    );

    // Register btoa function
    const btoa_fn = v8.FunctionTemplate.initCallback(isolate, btoaCallback);
    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "btoa"),
        btoa_fn.getFunction(context),
    );

    // Register TextEncoder constructor
    const encoder_tmpl = v8.FunctionTemplate.initCallback(isolate, textEncoderConstructor);
    const encoder_proto = encoder_tmpl.getPrototypeTemplate();
    const encode_fn = v8.FunctionTemplate.initCallback(isolate, textEncoderEncode);
    encoder_proto.set(
        v8.String.initUtf8(isolate, "encode").toName(),
        encode_fn,
        v8.PropertyAttribute.None,
    );
    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "TextEncoder"),
        encoder_tmpl.getFunction(context),
    );

    // Register TextDecoder constructor
    const decoder_tmpl = v8.FunctionTemplate.initCallback(isolate, textDecoderConstructor);
    const decoder_proto = decoder_tmpl.getPrototypeTemplate();
    const decode_fn = v8.FunctionTemplate.initCallback(isolate, textDecoderDecode);
    decoder_proto.set(
        v8.String.initUtf8(isolate, "decode").toName(),
        decode_fn,
        v8.PropertyAttribute.None,
    );
    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "TextDecoder"),
        decoder_tmpl.getFunction(context),
    );
}

fn atobCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();

    if (info.length() < 1) {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "atob requires 1 argument").toValue());
        return;
    }

    const arg = info.getArg(0);
    const str = arg.toString(context) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "atob: invalid argument").toValue());
        return;
    };

    // Get input string
    var input_buf: [8192]u8 = undefined;
    const input_len = str.writeUtf8(isolate, &input_buf);
    const input = input_buf[0..input_len];

    // Calculate decoded size and decode
    const decoder = std.base64.standard.Decoder;
    const decoded_size = decoder.calcSizeForSlice(input) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "atob: invalid base64").toValue());
        return;
    };

    var output_buf: [8192]u8 = undefined;
    if (decoded_size > output_buf.len) {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "atob: input too long").toValue());
        return;
    }

    decoder.decode(output_buf[0..decoded_size], input) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "atob: invalid base64").toValue());
        return;
    };

    const result = v8.String.initUtf8(isolate, output_buf[0..decoded_size]);
    info.getReturnValue().set(result.toValue());
}

fn btoaCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();

    if (info.length() < 1) {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "btoa requires 1 argument").toValue());
        return;
    }

    const arg = info.getArg(0);
    const str = arg.toString(context) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "btoa: invalid argument").toValue());
        return;
    };

    // Get input string
    var input_buf: [8192]u8 = undefined;
    const input_len = str.writeUtf8(isolate, &input_buf);
    const input = input_buf[0..input_len];

    // Encode to base64
    const encoder = std.base64.standard.Encoder;
    var output_buf: [16384]u8 = undefined;
    const encoded = encoder.encode(&output_buf, input);

    const result = v8.String.initUtf8(isolate, encoded);
    info.getReturnValue().set(result.toValue());
}

fn textEncoderConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();

    // Set encoding property on this object
    const this = info.getThis();
    _ = this.setValue(
        context,
        v8.String.initUtf8(isolate, "encoding"),
        v8.String.initUtf8(isolate, "utf-8").toValue(),
    );
}

fn textEncoderEncode(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();

    if (info.length() < 1) {
        // Return empty Uint8Array
        const array_buffer = v8.ArrayBuffer.init(isolate, 0);
        const uint8_array = v8.Uint8Array.init(array_buffer, 0, 0);
        info.getReturnValue().set(uint8_array.toValue());
        return;
    }

    const arg = info.getArg(0);
    const str = arg.toString(context) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "encode: invalid argument").toValue());
        return;
    };

    // Get UTF-8 length and create ArrayBuffer
    const len = str.lenUtf8(isolate);
    if (len == 0) {
        const array_buffer = v8.ArrayBuffer.init(isolate, 0);
        const uint8_array = v8.Uint8Array.init(array_buffer, 0, 0);
        info.getReturnValue().set(uint8_array.toValue());
        return;
    }

    // Create backing store and write data
    const backing = v8.BackingStore.init(isolate, len);
    const data = backing.getData();

    if (data) |ptr| {
        const slice: []u8 = @as([*]u8, @ptrCast(ptr))[0..len];
        _ = str.writeUtf8(isolate, slice);
    }

    // Create ArrayBuffer from backing store
    const shared_ptr = backing.toSharedPtr();
    const array_buffer = v8.ArrayBuffer.initWithBackingStore(isolate, &shared_ptr);
    const uint8_array = v8.Uint8Array.init(array_buffer, 0, len);
    info.getReturnValue().set(uint8_array.toValue());
}

fn textDecoderConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();

    // Default encoding is utf-8
    const encoding = v8.String.initUtf8(isolate, "utf-8");

    // Check for encoding argument
    if (info.length() >= 1) {
        const arg = info.getArg(0);
        if (arg.isString()) {
            const str = arg.toString(context) catch encoding;
            // For now, only support utf-8
            var buf: [32]u8 = undefined;
            const len = str.writeUtf8(isolate, &buf);
            const enc_str = buf[0..len];
            if (!std.mem.eql(u8, enc_str, "utf-8") and !std.mem.eql(u8, enc_str, "utf8")) {
                _ = isolate.throwException(v8.String.initUtf8(isolate, "TextDecoder: only utf-8 supported").toValue());
                return;
            }
        }
    }

    // Set encoding property on this object
    const this = info.getThis();
    _ = this.setValue(
        context,
        v8.String.initUtf8(isolate, "encoding"),
        encoding.toValue(),
    );
}

fn textDecoderDecode(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();

    if (info.length() < 1) {
        // Return empty string
        info.getReturnValue().set(v8.String.initUtf8(isolate, "").toValue());
        return;
    }

    const arg = info.getArg(0);

    // TypedArray/ArrayBuffer decoding not yet supported (V8-zig backing store access limitation)
    // Use string input or atob() for base64 decoding
    if (arg.isArrayBufferView() or arg.isArrayBuffer()) {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "TextDecoder.decode() requires string input in NANO v1.0").toValue());
        return;
    }

    // Convert string argument directly
    if (arg.isString()) {
        const str = arg.toString(context) catch {
            _ = isolate.throwException(v8.String.initUtf8(isolate, "decode: invalid input").toValue());
            return;
        };
        info.getReturnValue().set(str.toValue());
        return;
    }

    _ = isolate.throwException(v8.String.initUtf8(isolate, "decode: expected string input").toValue());
}
