const std = @import("std");
const v8 = @import("v8");

/// Register crypto APIs on global object
pub fn registerCryptoAPIs(isolate: v8.Isolate, context: v8.Context) void {
    const global = context.getGlobal();

    // Create crypto object
    const crypto_tmpl = isolate.initObjectTemplateDefault();

    // crypto.randomUUID()
    const uuid_fn = v8.FunctionTemplate.initCallback(isolate, randomUUIDCallback);
    crypto_tmpl.set(
        v8.String.initUtf8(isolate, "randomUUID").toName(),
        uuid_fn,
        v8.PropertyAttribute.None,
    );

    // crypto.getRandomValues()
    const random_fn = v8.FunctionTemplate.initCallback(isolate, getRandomValuesCallback);
    crypto_tmpl.set(
        v8.String.initUtf8(isolate, "getRandomValues").toName(),
        random_fn,
        v8.PropertyAttribute.None,
    );

    // Create crypto.subtle object
    const subtle_tmpl = isolate.initObjectTemplateDefault();

    // crypto.subtle.digest()
    const digest_fn = v8.FunctionTemplate.initCallback(isolate, digestCallback);
    subtle_tmpl.set(
        v8.String.initUtf8(isolate, "digest").toName(),
        digest_fn,
        v8.PropertyAttribute.None,
    );

    // Add subtle to crypto
    const subtle_obj = subtle_tmpl.initInstance(context);
    const crypto_obj = crypto_tmpl.initInstance(context);
    _ = crypto_obj.setValue(
        context,
        v8.String.initUtf8(isolate, "subtle"),
        subtle_obj,
    );

    // Add crypto to global
    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "crypto"),
        crypto_obj,
    );
}

fn randomUUIDCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();

    // Generate 16 random bytes
    var bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&bytes);

    // Set version (4) and variant bits
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant 1

    // Format as UUID string
    var uuid_buf: [36]u8 = undefined;
    _ = std.fmt.bufPrint(&uuid_buf, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
        bytes[0],  bytes[1],  bytes[2],  bytes[3],
        bytes[4],  bytes[5],
        bytes[6],  bytes[7],
        bytes[8],  bytes[9],
        bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15],
    }) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "Failed to generate UUID").toValue());
        return;
    };

    info.getReturnValue().set(v8.String.initUtf8(isolate, &uuid_buf).toValue());
}

fn getRandomValuesCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();

    if (info.length() < 1) {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "getRandomValues requires a TypedArray argument").toValue());
        return;
    }

    const arg = info.getArg(0);

    if (!arg.isArrayBufferView()) {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "getRandomValues requires a TypedArray argument").toValue());
        return;
    }

    // Get the view and fill with random bytes
    const view = v8.ArrayBufferView{ .handle = @ptrCast(arg.handle) };
    const len = view.getByteLength();

    if (len > 65536) {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "getRandomValues: quota exceeded (max 65536 bytes)").toValue());
        return;
    }

    // Create new random data and return new array
    const backing = v8.BackingStore.init(isolate, len);
    const data = backing.getData();

    if (data) |ptr| {
        const slice: []u8 = @as([*]u8, @ptrCast(ptr))[0..len];
        std.crypto.random.bytes(slice);
    }

    const shared_ptr = backing.toSharedPtr();
    const array_buffer = v8.ArrayBuffer.initWithBackingStore(isolate, &shared_ptr);
    const uint8_array = v8.Uint8Array.init(array_buffer, 0, len);
    info.getReturnValue().set(uint8_array.toValue());
}

fn digestCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();

    if (info.length() < 2) {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "digest requires algorithm and data arguments").toValue());
        return;
    }

    // Get algorithm name
    const algo_arg = info.getArg(0);
    const algo_str = algo_arg.toString(context) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "digest: invalid algorithm").toValue());
        return;
    };

    var algo_buf: [32]u8 = undefined;
    const algo_len = algo_str.writeUtf8(isolate, &algo_buf);
    const algo = algo_buf[0..algo_len];

    // Get data as string (TypedArray/ArrayBuffer input not yet supported)
    const data_arg = info.getArg(1);
    const data_str = data_arg.toString(context) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "digest: invalid data").toValue());
        return;
    };

    var data_buf: [8192]u8 = undefined;
    const data_len = data_str.writeUtf8(isolate, &data_buf);
    const data = data_buf[0..data_len];

    // Compute hash based on algorithm
    if (std.mem.eql(u8, algo, "SHA-256") or std.mem.eql(u8, algo, "sha-256")) {
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(data, &hash, .{});
        returnHashAsArrayBuffer(isolate, info, &hash);
    } else if (std.mem.eql(u8, algo, "SHA-384") or std.mem.eql(u8, algo, "sha-384")) {
        var hash: [48]u8 = undefined;
        std.crypto.hash.sha2.Sha384.hash(data, &hash, .{});
        returnHashAsArrayBuffer(isolate, info, &hash);
    } else if (std.mem.eql(u8, algo, "SHA-512") or std.mem.eql(u8, algo, "sha-512")) {
        var hash: [64]u8 = undefined;
        std.crypto.hash.sha2.Sha512.hash(data, &hash, .{});
        returnHashAsArrayBuffer(isolate, info, &hash);
    } else if (std.mem.eql(u8, algo, "SHA-1") or std.mem.eql(u8, algo, "sha-1")) {
        var hash: [20]u8 = undefined;
        std.crypto.hash.Sha1.hash(data, &hash, .{});
        returnHashAsArrayBuffer(isolate, info, &hash);
    } else {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "digest: unsupported algorithm").toValue());
        return;
    }
}

fn returnHashAsArrayBuffer(isolate: v8.Isolate, info: v8.FunctionCallbackInfo, hash: []const u8) void {
    const backing = v8.BackingStore.init(isolate, hash.len);
    const data = backing.getData();

    if (data) |ptr| {
        const slice: []u8 = @as([*]u8, @ptrCast(ptr))[0..hash.len];
        @memcpy(slice, hash);
    }

    const shared_ptr = backing.toSharedPtr();
    const array_buffer = v8.ArrayBuffer.initWithBackingStore(isolate, &shared_ptr);
    info.getReturnValue().set(v8.Value{ .handle = array_buffer.handle });
}
