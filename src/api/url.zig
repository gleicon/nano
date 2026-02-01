const std = @import("std");
const v8 = @import("v8");
const js = @import("js");

/// Register URL APIs on global object
pub fn registerURLAPIs(isolate: v8.Isolate, context: v8.Context) void {
    const global = context.getGlobal();

    // Register URL constructor
    const url_tmpl = v8.FunctionTemplate.initCallback(isolate, urlConstructor);
    const url_proto = url_tmpl.getPrototypeTemplate();

    // URL property getters
    js.addMethod(url_proto, isolate, "href", urlGetHref);
    js.addMethod(url_proto, isolate, "origin", urlGetOrigin);
    js.addMethod(url_proto, isolate, "protocol", urlGetProtocol);
    js.addMethod(url_proto, isolate, "host", urlGetHost);
    js.addMethod(url_proto, isolate, "hostname", urlGetHostname);
    js.addMethod(url_proto, isolate, "port", urlGetPort);
    js.addMethod(url_proto, isolate, "pathname", urlGetPathname);
    js.addMethod(url_proto, isolate, "search", urlGetSearch);
    js.addMethod(url_proto, isolate, "hash", urlGetHash);
    js.addMethod(url_proto, isolate, "toString", urlGetHref);

    js.addGlobalClass(global, context, isolate, "URL", url_tmpl);

    // Register URLSearchParams constructor
    const params_tmpl = v8.FunctionTemplate.initCallback(isolate, searchParamsConstructor);
    const params_proto = params_tmpl.getPrototypeTemplate();

    js.addMethod(params_proto, isolate, "get", searchParamsGet);
    js.addMethod(params_proto, isolate, "has", searchParamsHas);
    js.addMethod(params_proto, isolate, "set", searchParamsSet);
    js.addMethod(params_proto, isolate, "append", searchParamsAppend);
    js.addMethod(params_proto, isolate, "delete", searchParamsDelete);
    js.addMethod(params_proto, isolate, "toString", searchParamsToString);

    js.addGlobalClass(global, context, isolate, "URLSearchParams", params_tmpl);
}

// ============================================================================
// URL Implementation
// ============================================================================

fn urlConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) {
        js.throw(ctx.isolate, "URL requires a url argument");
        return;
    }

    const str = ctx.arg(0).toString(ctx.context) catch {
        js.throw(ctx.isolate, "URL: invalid argument");
        return;
    };

    var url_buf: [4096]u8 = undefined;
    const url_str = js.readString(ctx.isolate, str, &url_buf);

    // Parse URL using Zig's std.Uri
    const uri = std.Uri.parse(url_str) catch {
        js.throw(ctx.isolate, "URL: invalid URL");
        return;
    };

    // Store the original href
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_href", js.string(ctx.isolate, url_str));

    // Store parsed components
    if (uri.scheme.len > 0) {
        var proto_buf: [64]u8 = undefined;
        const proto_str = std.fmt.bufPrint(&proto_buf, "{s}:", .{uri.scheme}) catch "";
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_protocol", js.string(ctx.isolate, proto_str));
    } else {
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_protocol", js.string(ctx.isolate, ""));
    }

    if (uri.host) |host| {
        const host_str = switch (host) {
            .raw => |r| r,
            .percent_encoded => |p| p,
        };
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_hostname", js.string(ctx.isolate, host_str));
    } else {
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_hostname", js.string(ctx.isolate, ""));
    }

    if (uri.port) |port| {
        var port_buf: [8]u8 = undefined;
        const port_str = std.fmt.bufPrint(&port_buf, "{d}", .{port}) catch "";
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_port", js.string(ctx.isolate, port_str));
    } else {
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_port", js.string(ctx.isolate, ""));
    }

    // Path
    const path_str = switch (uri.path) {
        .raw => |r| r,
        .percent_encoded => |p| p,
    };
    if (path_str.len > 0) {
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_pathname", js.string(ctx.isolate, path_str));
    } else {
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_pathname", js.string(ctx.isolate, "/"));
    }

    // Query
    if (uri.query) |query| {
        const query_str = switch (query) {
            .raw => |r| r,
            .percent_encoded => |p| p,
        };
        var search_buf: [2048]u8 = undefined;
        const search_str = std.fmt.bufPrint(&search_buf, "?{s}", .{query_str}) catch "";
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_search", js.string(ctx.isolate, search_str));
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_query", js.string(ctx.isolate, query_str));
    } else {
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_search", js.string(ctx.isolate, ""));
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_query", js.string(ctx.isolate, ""));
    }

    // Fragment
    if (uri.fragment) |fragment| {
        const frag_str = switch (fragment) {
            .raw => |r| r,
            .percent_encoded => |p| p,
        };
        var hash_buf: [1024]u8 = undefined;
        const hash_str = std.fmt.bufPrint(&hash_buf, "#{s}", .{frag_str}) catch "";
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_hash", js.string(ctx.isolate, hash_str));
    } else {
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_hash", js.string(ctx.isolate, ""));
    }
}

fn urlGetHref(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);
    const val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_href") catch js.string(ctx.isolate, "").toValue();
    js.ret(ctx, val);
}

fn urlGetOrigin(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const protocol = js.getProp(ctx.this, ctx.context, ctx.isolate, "_protocol") catch return;
    const hostname = js.getProp(ctx.this, ctx.context, ctx.isolate, "_hostname") catch return;
    const port = js.getProp(ctx.this, ctx.context, ctx.isolate, "_port") catch return;

    var proto_buf: [64]u8 = undefined;
    var host_buf: [256]u8 = undefined;
    var port_buf: [8]u8 = undefined;

    const proto_str = protocol.toString(ctx.context) catch return;
    const host_str = hostname.toString(ctx.context) catch return;
    const port_str = port.toString(ctx.context) catch return;

    const proto = js.readString(ctx.isolate, proto_str, &proto_buf);
    const host = js.readString(ctx.isolate, host_str, &host_buf);
    const p = js.readString(ctx.isolate, port_str, &port_buf);

    var origin_buf: [512]u8 = undefined;
    var origin: []const u8 = undefined;

    if (p.len > 0) {
        origin = std.fmt.bufPrint(&origin_buf, "{s}//{s}:{s}", .{ proto, host, p }) catch "";
    } else {
        origin = std.fmt.bufPrint(&origin_buf, "{s}//{s}", .{ proto, host }) catch "";
    }

    js.retString(ctx, origin);
}

fn urlGetProtocol(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);
    const val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_protocol") catch js.string(ctx.isolate, "").toValue();
    js.ret(ctx, val);
}

fn urlGetHost(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const hostname = js.getProp(ctx.this, ctx.context, ctx.isolate, "_hostname") catch return;
    const port = js.getProp(ctx.this, ctx.context, ctx.isolate, "_port") catch return;

    var host_buf: [256]u8 = undefined;
    var port_buf: [8]u8 = undefined;

    const host_str = hostname.toString(ctx.context) catch return;
    const port_str = port.toString(ctx.context) catch return;

    const host = js.readString(ctx.isolate, host_str, &host_buf);
    const p = js.readString(ctx.isolate, port_str, &port_buf);

    var result_buf: [280]u8 = undefined;
    var result: []const u8 = undefined;

    if (p.len > 0) {
        result = std.fmt.bufPrint(&result_buf, "{s}:{s}", .{ host, p }) catch "";
    } else {
        result = host;
    }

    js.retString(ctx, result);
}

fn urlGetHostname(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);
    const val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_hostname") catch js.string(ctx.isolate, "").toValue();
    js.ret(ctx, val);
}

fn urlGetPort(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);
    const val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_port") catch js.string(ctx.isolate, "").toValue();
    js.ret(ctx, val);
}

fn urlGetPathname(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);
    const val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_pathname") catch js.string(ctx.isolate, "").toValue();
    js.ret(ctx, val);
}

fn urlGetSearch(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);
    const val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_search") catch js.string(ctx.isolate, "").toValue();
    js.ret(ctx, val);
}

fn urlGetHash(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);
    const val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_hash") catch js.string(ctx.isolate, "").toValue();
    js.ret(ctx, val);
}

// ============================================================================
// URLSearchParams Implementation
// ============================================================================

fn searchParamsConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    var init_str: []const u8 = "";

    if (ctx.argc() >= 1) {
        const arg = ctx.arg(0);
        if (arg.isString()) {
            const str = arg.toString(ctx.context) catch {
                _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_params", js.string(ctx.isolate, ""));
                return;
            };
            var buf: [4096]u8 = undefined;
            const full_str = js.readString(ctx.isolate, str, &buf);
            // Remove leading ? if present
            if (full_str.len > 0 and full_str[0] == '?') {
                init_str = full_str[1..];
            } else {
                init_str = full_str;
            }
        }
    }

    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_params", js.string(ctx.isolate, init_str));
}

fn searchParamsGet(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) {
        js.retNull(ctx);
        return;
    }

    const key_str = ctx.arg(0).toString(ctx.context) catch {
        js.retNull(ctx);
        return;
    };

    var key_buf: [256]u8 = undefined;
    const key = js.readString(ctx.isolate, key_str, &key_buf);

    const params_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_params") catch {
        js.retNull(ctx);
        return;
    };
    const params_str = params_val.toString(ctx.context) catch {
        js.retNull(ctx);
        return;
    };

    var params_buf: [4096]u8 = undefined;
    const params = js.readString(ctx.isolate, params_str, &params_buf);

    // Parse and find key
    var iter = std.mem.splitScalar(u8, params, '&');
    while (iter.next()) |pair| {
        if (std.mem.indexOfScalar(u8, pair, '=')) |eq_pos| {
            const k = pair[0..eq_pos];
            const v = pair[eq_pos + 1 ..];
            if (std.mem.eql(u8, k, key)) {
                js.retString(ctx, v);
                return;
            }
        }
    }

    js.retNull(ctx);
}

fn searchParamsHas(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) {
        js.retBool(ctx, false);
        return;
    }

    const key_str = ctx.arg(0).toString(ctx.context) catch {
        js.retBool(ctx, false);
        return;
    };

    var key_buf: [256]u8 = undefined;
    const key = js.readString(ctx.isolate, key_str, &key_buf);

    const params_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_params") catch {
        js.retBool(ctx, false);
        return;
    };
    const params_str = params_val.toString(ctx.context) catch {
        js.retBool(ctx, false);
        return;
    };

    var params_buf: [4096]u8 = undefined;
    const params = js.readString(ctx.isolate, params_str, &params_buf);

    var iter = std.mem.splitScalar(u8, params, '&');
    while (iter.next()) |pair| {
        if (std.mem.indexOfScalar(u8, pair, '=')) |eq_pos| {
            const k = pair[0..eq_pos];
            if (std.mem.eql(u8, k, key)) {
                js.retBool(ctx, true);
                return;
            }
        }
    }

    js.retBool(ctx, false);
}

fn searchParamsSet(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 2) return;

    const key_str = ctx.arg(0).toString(ctx.context) catch return;
    const val_str = ctx.arg(1).toString(ctx.context) catch return;

    var key_buf: [256]u8 = undefined;
    var val_buf: [1024]u8 = undefined;
    const key = js.readString(ctx.isolate, key_str, &key_buf);
    const value = js.readString(ctx.isolate, val_str, &val_buf);

    const params_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_params") catch return;
    const params_str = params_val.toString(ctx.context) catch return;

    var params_buf: [4096]u8 = undefined;
    const params = js.readString(ctx.isolate, params_str, &params_buf);

    // Build new params, replacing existing key
    var result_buf: [8192]u8 = undefined;
    var result_len: usize = 0;
    var found = false;

    var iter = std.mem.splitScalar(u8, params, '&');
    while (iter.next()) |pair| {
        if (pair.len == 0) continue;

        if (std.mem.indexOfScalar(u8, pair, '=')) |eq_pos| {
            const k = pair[0..eq_pos];
            if (std.mem.eql(u8, k, key)) {
                if (result_len > 0) {
                    result_buf[result_len] = '&';
                    result_len += 1;
                }
                @memcpy(result_buf[result_len .. result_len + key.len], key);
                result_len += key.len;
                result_buf[result_len] = '=';
                result_len += 1;
                @memcpy(result_buf[result_len .. result_len + value.len], value);
                result_len += value.len;
                found = true;
            } else {
                if (result_len > 0) {
                    result_buf[result_len] = '&';
                    result_len += 1;
                }
                @memcpy(result_buf[result_len .. result_len + pair.len], pair);
                result_len += pair.len;
            }
        }
    }

    if (!found) {
        if (result_len > 0) {
            result_buf[result_len] = '&';
            result_len += 1;
        }
        @memcpy(result_buf[result_len .. result_len + key.len], key);
        result_len += key.len;
        result_buf[result_len] = '=';
        result_len += 1;
        @memcpy(result_buf[result_len .. result_len + value.len], value);
        result_len += value.len;
    }

    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_params", js.string(ctx.isolate, result_buf[0..result_len]));
}

fn searchParamsAppend(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 2) return;

    const key_str = ctx.arg(0).toString(ctx.context) catch return;
    const val_str = ctx.arg(1).toString(ctx.context) catch return;

    var key_buf: [256]u8 = undefined;
    var val_buf: [1024]u8 = undefined;
    const key_len = key_str.writeUtf8(ctx.isolate, &key_buf);
    const val_len = val_str.writeUtf8(ctx.isolate, &val_buf);

    const params_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_params") catch return;
    const params_str = params_val.toString(ctx.context) catch return;

    var params_buf: [4096]u8 = undefined;
    const params_len = params_str.writeUtf8(ctx.isolate, &params_buf);

    var result_buf: [8192]u8 = undefined;
    var result_len: usize = 0;

    if (params_len > 0) {
        @memcpy(result_buf[0..params_len], params_buf[0..params_len]);
        result_len = params_len;
        result_buf[result_len] = '&';
        result_len += 1;
    }

    @memcpy(result_buf[result_len .. result_len + key_len], key_buf[0..key_len]);
    result_len += key_len;
    result_buf[result_len] = '=';
    result_len += 1;
    @memcpy(result_buf[result_len .. result_len + val_len], val_buf[0..val_len]);
    result_len += val_len;

    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_params", js.string(ctx.isolate, result_buf[0..result_len]));
}

fn searchParamsDelete(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) return;

    const key_str = ctx.arg(0).toString(ctx.context) catch return;

    var key_buf: [256]u8 = undefined;
    const key = js.readString(ctx.isolate, key_str, &key_buf);

    const params_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_params") catch return;
    const params_str = params_val.toString(ctx.context) catch return;

    var params_buf: [4096]u8 = undefined;
    const params = js.readString(ctx.isolate, params_str, &params_buf);

    var result_buf: [8192]u8 = undefined;
    var result_len: usize = 0;

    var iter = std.mem.splitScalar(u8, params, '&');
    while (iter.next()) |pair| {
        if (pair.len == 0) continue;

        if (std.mem.indexOfScalar(u8, pair, '=')) |eq_pos| {
            const k = pair[0..eq_pos];
            if (!std.mem.eql(u8, k, key)) {
                if (result_len > 0) {
                    result_buf[result_len] = '&';
                    result_len += 1;
                }
                @memcpy(result_buf[result_len .. result_len + pair.len], pair);
                result_len += pair.len;
            }
        }
    }

    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_params", js.string(ctx.isolate, result_buf[0..result_len]));
}

fn searchParamsToString(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);
    const val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_params") catch js.string(ctx.isolate, "").toValue();
    js.ret(ctx, val);
}
