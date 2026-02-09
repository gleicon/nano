const std = @import("std");
const v8 = @import("v8");
const js = @import("js");

/// Register crypto APIs on global object
pub fn registerCryptoAPIs(isolate: v8.Isolate, context: v8.Context) void {
    const global = context.getGlobal();

    // Create crypto object
    const crypto_tmpl = isolate.initObjectTemplateDefault();

    js.addMethod(crypto_tmpl, isolate, "randomUUID", randomUUIDCallback);
    js.addMethod(crypto_tmpl, isolate, "getRandomValues", getRandomValuesCallback);

    // Create crypto.subtle object
    const subtle_tmpl = isolate.initObjectTemplateDefault();

    js.addMethod(subtle_tmpl, isolate, "digest", digestCallback);
    js.addMethod(subtle_tmpl, isolate, "sign", signCallback);
    js.addMethod(subtle_tmpl, isolate, "verify", verifyCallback);

    // Add subtle to crypto
    const subtle_obj = subtle_tmpl.initInstance(context);
    const crypto_obj = crypto_tmpl.initInstance(context);
    _ = js.setProp(crypto_obj, context, isolate, "subtle", subtle_obj);

    // Add crypto to global
    js.addGlobalObj(global, context, isolate, "crypto", crypto_obj);
}

fn randomUUIDCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

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
        js.throw(ctx.isolate, "Failed to generate UUID");
        return;
    };

    js.retString(ctx, &uuid_buf);
}

fn getRandomValuesCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) {
        js.throw(ctx.isolate, "getRandomValues requires a TypedArray argument");
        return;
    }

    const arg = ctx.arg(0);

    if (!arg.isArrayBufferView()) {
        js.throw(ctx.isolate, "getRandomValues requires a TypedArray argument");
        return;
    }

    const view = js.asArrayBufferView(arg);
    const len = view.getByteLength();

    if (len > 65536) {
        js.throw(ctx.isolate, "getRandomValues: quota exceeded (max 65536 bytes)");
        return;
    }

    // Create new random data and return new array
    const backing = v8.BackingStore.init(ctx.isolate, len);
    const data = backing.getData();

    if (data) |ptr| {
        const slice: []u8 = @as([*]u8, @ptrCast(ptr))[0..len];
        std.crypto.random.bytes(slice);
    }

    const shared_ptr = backing.toSharedPtr();
    const array_buffer = v8.ArrayBuffer.initWithBackingStore(ctx.isolate, &shared_ptr);
    const uint8_array = v8.Uint8Array.init(array_buffer, 0, len);
    js.ret(ctx, uint8_array);
}

fn digestCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 2) {
        js.throw(ctx.isolate, "digest requires algorithm and data arguments");
        return;
    }

    // Get algorithm name
    const algo_str = ctx.arg(0).toString(ctx.context) catch {
        js.throw(ctx.isolate, "digest: invalid algorithm");
        return;
    };

    var algo_buf: [32]u8 = undefined;
    const algo = js.readString(ctx.isolate, algo_str, &algo_buf);

    // Get data — support string, ArrayBuffer, or ArrayBufferView
    var data_storage: [8192]u8 = undefined;
    var data: []const u8 = undefined;

    if (ctx.arg(1).isArrayBuffer()) {
        const ab = js.asArrayBuffer(ctx.arg(1));
        const ab_len = ab.getByteLength();
        const shared_ptr = ab.getBackingStore();
        const backing_store = v8.BackingStore.sharedPtrGet(&shared_ptr);
        const ab_data = backing_store.getData();
        if (ab_data) |ptr| {
            const copy_len = @min(ab_len, data_storage.len);
            const byte_ptr: [*]const u8 = @ptrCast(ptr);
            @memcpy(data_storage[0..copy_len], byte_ptr[0..copy_len]);
            data = data_storage[0..copy_len];
        } else {
            data = &[_]u8{};
        }
    } else if (ctx.arg(1).isArrayBufferView()) {
        const view = js.asArrayBufferView(ctx.arg(1));
        const view_len = view.getByteLength();
        const view_offset = view.getByteOffset();
        const ab = view.getBuffer();
        const shared_ptr = ab.getBackingStore();
        const backing_store = v8.BackingStore.sharedPtrGet(&shared_ptr);
        const ab_data = backing_store.getData();
        if (ab_data) |ptr| {
            const copy_len = @min(view_len, data_storage.len);
            const byte_ptr: [*]const u8 = @ptrCast(ptr);
            @memcpy(data_storage[0..copy_len], byte_ptr[view_offset .. view_offset + copy_len]);
            data = data_storage[0..copy_len];
        } else {
            data = &[_]u8{};
        }
    } else {
        // Fall back to string input
        const data_str = ctx.arg(1).toString(ctx.context) catch {
            js.throw(ctx.isolate, "digest: invalid data");
            return;
        };
        data = js.readString(ctx.isolate, data_str, &data_storage);
    }

    // Compute hash based on algorithm
    if (std.mem.eql(u8, algo, "SHA-256") or std.mem.eql(u8, algo, "sha-256")) {
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(data, &hash, .{});
        returnHashAsPromise(ctx, &hash);
    } else if (std.mem.eql(u8, algo, "SHA-384") or std.mem.eql(u8, algo, "sha-384")) {
        var hash: [48]u8 = undefined;
        std.crypto.hash.sha2.Sha384.hash(data, &hash, .{});
        returnHashAsPromise(ctx, &hash);
    } else if (std.mem.eql(u8, algo, "SHA-512") or std.mem.eql(u8, algo, "sha-512")) {
        var hash: [64]u8 = undefined;
        std.crypto.hash.sha2.Sha512.hash(data, &hash, .{});
        returnHashAsPromise(ctx, &hash);
    } else if (std.mem.eql(u8, algo, "SHA-1") or std.mem.eql(u8, algo, "sha-1")) {
        var hash: [20]u8 = undefined;
        std.crypto.hash.Sha1.hash(data, &hash, .{});
        returnHashAsPromise(ctx, &hash);
    } else {
        js.throw(ctx.isolate, "digest: unsupported algorithm");
        return;
    }
}

fn returnHashAsPromise(ctx: js.CallbackContext, hash: []const u8) void {
    const backing = v8.BackingStore.init(ctx.isolate, hash.len);
    const data = backing.getData();

    if (data) |ptr| {
        const slice: []u8 = @as([*]u8, @ptrCast(ptr))[0..hash.len];
        @memcpy(slice, hash);
    }

    const shared_ptr = backing.toSharedPtr();
    const array_buffer = v8.ArrayBuffer.initWithBackingStore(ctx.isolate, &shared_ptr);
    js.retResolvedPromise(ctx, v8.Value{ .handle = array_buffer.handle });
}

/// crypto.subtle.sign(algorithm, key, data)
fn signCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 3) {
        js.throw(ctx.isolate, "sign requires algorithm, key, and data arguments");
        return;
    }

    // Parse algorithm
    const algo_arg = ctx.arg(0);
    var hash_algo: []const u8 = "SHA-256";

    if (algo_arg.isObject()) {
        const algo_obj = js.asObject(algo_arg);
        const hash_val = js.getProp(algo_obj, ctx.context, ctx.isolate, "hash") catch null;
        if (hash_val) |hv| {
            const hash_str = hv.toString(ctx.context) catch null;
            if (hash_str) |hs| {
                var hash_buf: [32]u8 = undefined;
                hash_algo = js.readString(ctx.isolate, hs, &hash_buf);
            }
        }
    } else if (algo_arg.isString()) {
        const algo_str = algo_arg.toString(ctx.context) catch {
            js.throw(ctx.isolate, "sign: invalid algorithm");
            return;
        };
        var algo_buf: [32]u8 = undefined;
        hash_algo = js.readString(ctx.isolate, algo_str, &algo_buf);
    }

    // Get key
    const key_arg = ctx.arg(1);
    var key_buf: [256]u8 = undefined;
    var key_len: usize = 0;

    if (key_arg.isObject()) {
        const key_obj = js.asObject(key_arg);
        const raw_val = js.getProp(key_obj, ctx.context, ctx.isolate, "raw") catch null;
        if (raw_val) |rv| {
            const key_str = rv.toString(ctx.context) catch {
                js.throw(ctx.isolate, "sign: invalid key");
                return;
            };
            key_len = key_str.writeUtf8(ctx.isolate, &key_buf);
        } else {
            js.throw(ctx.isolate, "sign: key must have 'raw' property");
            return;
        }
    } else {
        const key_str = key_arg.toString(ctx.context) catch {
            js.throw(ctx.isolate, "sign: invalid key");
            return;
        };
        key_len = key_str.writeUtf8(ctx.isolate, &key_buf);
    }
    const key = key_buf[0..key_len];

    // Get data
    const data_str = ctx.arg(2).toString(ctx.context) catch {
        js.throw(ctx.isolate, "sign: invalid data");
        return;
    };

    var data_buf: [8192]u8 = undefined;
    const data = js.readString(ctx.isolate, data_str, &data_buf);

    // Compute HMAC based on hash algorithm
    if (std.mem.eql(u8, hash_algo, "SHA-256") or std.mem.eql(u8, hash_algo, "sha-256") or std.mem.eql(u8, hash_algo, "HMAC")) {
        var mac: [32]u8 = undefined;
        var hmac = std.crypto.auth.hmac.sha2.HmacSha256.init(key);
        hmac.update(data);
        hmac.final(&mac);
        returnHashAsPromise(ctx, &mac);
    } else if (std.mem.eql(u8, hash_algo, "SHA-384") or std.mem.eql(u8, hash_algo, "sha-384")) {
        var mac: [48]u8 = undefined;
        var hmac = std.crypto.auth.hmac.sha2.HmacSha384.init(key);
        hmac.update(data);
        hmac.final(&mac);
        returnHashAsPromise(ctx, &mac);
    } else if (std.mem.eql(u8, hash_algo, "SHA-512") or std.mem.eql(u8, hash_algo, "sha-512")) {
        var mac: [64]u8 = undefined;
        var hmac = std.crypto.auth.hmac.sha2.HmacSha512.init(key);
        hmac.update(data);
        hmac.final(&mac);
        returnHashAsPromise(ctx, &mac);
    } else {
        js.throw(ctx.isolate, "sign: unsupported algorithm (use HMAC with SHA-256/384/512)");
        return;
    }
}

/// crypto.subtle.verify(algorithm, key, signature, data)
fn verifyCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 4) {
        js.throw(ctx.isolate, "verify requires algorithm, key, signature, and data arguments");
        return;
    }

    // Parse algorithm
    const algo_arg = ctx.arg(0);
    var hash_algo: []const u8 = "SHA-256";

    if (algo_arg.isObject()) {
        const algo_obj = js.asObject(algo_arg);
        const hash_val = js.getProp(algo_obj, ctx.context, ctx.isolate, "hash") catch null;
        if (hash_val) |hv| {
            const hash_str = hv.toString(ctx.context) catch null;
            if (hash_str) |hs| {
                var hash_buf: [32]u8 = undefined;
                hash_algo = js.readString(ctx.isolate, hs, &hash_buf);
            }
        }
    } else if (algo_arg.isString()) {
        const algo_str = algo_arg.toString(ctx.context) catch {
            js.throw(ctx.isolate, "verify: invalid algorithm");
            return;
        };
        var algo_buf: [32]u8 = undefined;
        hash_algo = js.readString(ctx.isolate, algo_str, &algo_buf);
    }

    // Get key
    const key_arg = ctx.arg(1);
    var key_buf: [256]u8 = undefined;
    var key_len: usize = 0;

    if (key_arg.isObject()) {
        const key_obj = js.asObject(key_arg);
        const raw_val = js.getProp(key_obj, ctx.context, ctx.isolate, "raw") catch null;
        if (raw_val) |rv| {
            const key_str = rv.toString(ctx.context) catch {
                js.throw(ctx.isolate, "verify: invalid key");
                return;
            };
            key_len = key_str.writeUtf8(ctx.isolate, &key_buf);
        } else {
            js.throw(ctx.isolate, "verify: key must have 'raw' property");
            return;
        }
    } else {
        const key_str = key_arg.toString(ctx.context) catch {
            js.throw(ctx.isolate, "verify: invalid key");
            return;
        };
        key_len = key_str.writeUtf8(ctx.isolate, &key_buf);
    }
    const key = key_buf[0..key_len];

    // Get signature
    const sig_arg = ctx.arg(2);
    var sig_buf: [64]u8 = undefined;
    var sig_len: usize = 0;

    if (sig_arg.isArrayBuffer()) {
        const ab = js.asArrayBuffer(sig_arg);
        const ab_len = ab.getByteLength();
        const shared_ptr = ab.getBackingStore();
        const backing_store = v8.BackingStore.sharedPtrGet(&shared_ptr);
        const sig_data = backing_store.getData();
        if (sig_data) |ptr| {
            sig_len = @min(ab_len, 64);
            const byte_ptr: [*]const u8 = @ptrCast(ptr);
            @memcpy(sig_buf[0..sig_len], byte_ptr[0..sig_len]);
        }
    } else if (sig_arg.isArrayBufferView()) {
        const view = js.asArrayBufferView(sig_arg);
        const ab = view.getBuffer();
        const ab_len = view.getByteLength();
        const shared_ptr = ab.getBackingStore();
        const backing_store = v8.BackingStore.sharedPtrGet(&shared_ptr);
        const sig_data = backing_store.getData();
        if (sig_data) |ptr| {
            const offset = view.getByteOffset();
            sig_len = @min(ab_len, 64);
            const byte_ptr: [*]const u8 = @ptrCast(ptr);
            @memcpy(sig_buf[0..sig_len], byte_ptr[offset .. offset + sig_len]);
        }
    } else {
        js.throw(ctx.isolate, "verify: signature must be ArrayBuffer or TypedArray");
        return;
    }
    const signature = sig_buf[0..sig_len];

    // Get data
    const data_str = ctx.arg(3).toString(ctx.context) catch {
        js.throw(ctx.isolate, "verify: invalid data");
        return;
    };

    var data_buf: [8192]u8 = undefined;
    const data = js.readString(ctx.isolate, data_str, &data_buf);

    // Compute expected MAC and compare
    var result: bool = false;

    if (std.mem.eql(u8, hash_algo, "SHA-256") or std.mem.eql(u8, hash_algo, "sha-256") or std.mem.eql(u8, hash_algo, "HMAC")) {
        if (sig_len == 32) {
            var expected_mac: [32]u8 = undefined;
            var hmac = std.crypto.auth.hmac.sha2.HmacSha256.init(key);
            hmac.update(data);
            hmac.final(&expected_mac);
            result = std.mem.eql(u8, signature, &expected_mac);
        }
    } else if (std.mem.eql(u8, hash_algo, "SHA-384") or std.mem.eql(u8, hash_algo, "sha-384")) {
        if (sig_len == 48) {
            var expected_mac: [48]u8 = undefined;
            var hmac = std.crypto.auth.hmac.sha2.HmacSha384.init(key);
            hmac.update(data);
            hmac.final(&expected_mac);
            result = std.mem.eql(u8, signature, &expected_mac);
        }
    } else if (std.mem.eql(u8, hash_algo, "SHA-512") or std.mem.eql(u8, hash_algo, "sha-512")) {
        if (sig_len == 64) {
            var expected_mac: [64]u8 = undefined;
            var hmac = std.crypto.auth.hmac.sha2.HmacSha512.init(key);
            hmac.update(data);
            hmac.final(&expected_mac);
            result = std.mem.eql(u8, signature, &expected_mac);
        }
    }

    js.retResolvedPromise(ctx, v8.Value{ .handle = js.boolean(ctx.isolate, result).handle });
}
