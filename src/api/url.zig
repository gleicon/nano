const std = @import("std");
const v8 = @import("v8");

/// Register URL APIs on global object
pub fn registerURLAPIs(isolate: v8.Isolate, context: v8.Context) void {
    const global = context.getGlobal();

    // Register URL constructor
    const url_tmpl = v8.FunctionTemplate.initCallback(isolate, urlConstructor);
    const url_proto = url_tmpl.getPrototypeTemplate();

    // URL property getters
    addGetter(isolate, url_proto, "href", urlGetHref);
    addGetter(isolate, url_proto, "origin", urlGetOrigin);
    addGetter(isolate, url_proto, "protocol", urlGetProtocol);
    addGetter(isolate, url_proto, "host", urlGetHost);
    addGetter(isolate, url_proto, "hostname", urlGetHostname);
    addGetter(isolate, url_proto, "port", urlGetPort);
    addGetter(isolate, url_proto, "pathname", urlGetPathname);
    addGetter(isolate, url_proto, "search", urlGetSearch);
    addGetter(isolate, url_proto, "hash", urlGetHash);

    // toString method
    const tostring_fn = v8.FunctionTemplate.initCallback(isolate, urlGetHref);
    url_proto.set(
        v8.String.initUtf8(isolate, "toString").toName(),
        tostring_fn,
        v8.PropertyAttribute.None,
    );

    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "URL"),
        url_tmpl.getFunction(context),
    );

    // Register URLSearchParams constructor
    const params_tmpl = v8.FunctionTemplate.initCallback(isolate, searchParamsConstructor);
    const params_proto = params_tmpl.getPrototypeTemplate();

    // URLSearchParams methods
    addMethod(isolate, params_proto, "get", searchParamsGet);
    addMethod(isolate, params_proto, "has", searchParamsHas);
    addMethod(isolate, params_proto, "set", searchParamsSet);
    addMethod(isolate, params_proto, "append", searchParamsAppend);
    addMethod(isolate, params_proto, "delete", searchParamsDelete);
    addMethod(isolate, params_proto, "toString", searchParamsToString);

    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "URLSearchParams"),
        params_tmpl.getFunction(context),
    );
}

fn addGetter(isolate: v8.Isolate, proto: v8.ObjectTemplate, name: []const u8, callback: *const fn (?*const v8.C_FunctionCallbackInfo) callconv(.c) void) void {
    const fn_tmpl = v8.FunctionTemplate.initCallback(isolate, callback);
    proto.set(
        v8.String.initUtf8(isolate, name).toName(),
        fn_tmpl,
        v8.PropertyAttribute.None,
    );
}

fn addMethod(isolate: v8.Isolate, proto: v8.ObjectTemplate, name: []const u8, callback: *const fn (?*const v8.C_FunctionCallbackInfo) callconv(.c) void) void {
    const fn_tmpl = v8.FunctionTemplate.initCallback(isolate, callback);
    proto.set(
        v8.String.initUtf8(isolate, name).toName(),
        fn_tmpl,
        v8.PropertyAttribute.None,
    );
}

// ============================================================================
// URL Implementation
// ============================================================================

fn urlConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();

    if (info.length() < 1) {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "URL requires a url argument").toValue());
        return;
    }

    const arg = info.getArg(0);
    const str = arg.toString(context) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "URL: invalid argument").toValue());
        return;
    };

    var url_buf: [4096]u8 = undefined;
    const url_len = str.writeUtf8(isolate, &url_buf);
    const url_str = url_buf[0..url_len];

    // Parse URL using Zig's std.Uri
    const uri = std.Uri.parse(url_str) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "URL: invalid URL").toValue());
        return;
    };

    const this = info.getThis();

    // Store the original href
    _ = this.setValue(context, v8.String.initUtf8(isolate, "_href"), v8.String.initUtf8(isolate, url_str).toValue());

    // Store parsed components
    if (uri.scheme.len > 0) {
        var proto_buf: [64]u8 = undefined;
        const proto_str = std.fmt.bufPrint(&proto_buf, "{s}:", .{uri.scheme}) catch "";
        _ = this.setValue(context, v8.String.initUtf8(isolate, "_protocol"), v8.String.initUtf8(isolate, proto_str).toValue());
    } else {
        _ = this.setValue(context, v8.String.initUtf8(isolate, "_protocol"), v8.String.initUtf8(isolate, "").toValue());
    }

    if (uri.host) |host| {
        const host_str = switch (host) {
            .raw => |r| r,
            .percent_encoded => |p| p,
        };
        _ = this.setValue(context, v8.String.initUtf8(isolate, "_hostname"), v8.String.initUtf8(isolate, host_str).toValue());
    } else {
        _ = this.setValue(context, v8.String.initUtf8(isolate, "_hostname"), v8.String.initUtf8(isolate, "").toValue());
    }

    if (uri.port) |port| {
        var port_buf: [8]u8 = undefined;
        const port_str = std.fmt.bufPrint(&port_buf, "{d}", .{port}) catch "";
        _ = this.setValue(context, v8.String.initUtf8(isolate, "_port"), v8.String.initUtf8(isolate, port_str).toValue());
    } else {
        _ = this.setValue(context, v8.String.initUtf8(isolate, "_port"), v8.String.initUtf8(isolate, "").toValue());
    }

    // Path
    const path_str = switch (uri.path) {
        .raw => |r| r,
        .percent_encoded => |p| p,
    };
    if (path_str.len > 0) {
        _ = this.setValue(context, v8.String.initUtf8(isolate, "_pathname"), v8.String.initUtf8(isolate, path_str).toValue());
    } else {
        _ = this.setValue(context, v8.String.initUtf8(isolate, "_pathname"), v8.String.initUtf8(isolate, "/").toValue());
    }

    // Query
    if (uri.query) |query| {
        const query_str = switch (query) {
            .raw => |r| r,
            .percent_encoded => |p| p,
        };
        var search_buf: [2048]u8 = undefined;
        const search_str = std.fmt.bufPrint(&search_buf, "?{s}", .{query_str}) catch "";
        _ = this.setValue(context, v8.String.initUtf8(isolate, "_search"), v8.String.initUtf8(isolate, search_str).toValue());
        _ = this.setValue(context, v8.String.initUtf8(isolate, "_query"), v8.String.initUtf8(isolate, query_str).toValue());
    } else {
        _ = this.setValue(context, v8.String.initUtf8(isolate, "_search"), v8.String.initUtf8(isolate, "").toValue());
        _ = this.setValue(context, v8.String.initUtf8(isolate, "_query"), v8.String.initUtf8(isolate, "").toValue());
    }

    // Fragment
    if (uri.fragment) |fragment| {
        const frag_str = switch (fragment) {
            .raw => |r| r,
            .percent_encoded => |p| p,
        };
        var hash_buf: [1024]u8 = undefined;
        const hash_str = std.fmt.bufPrint(&hash_buf, "#{s}", .{frag_str}) catch "";
        _ = this.setValue(context, v8.String.initUtf8(isolate, "_hash"), v8.String.initUtf8(isolate, hash_str).toValue());
    } else {
        _ = this.setValue(context, v8.String.initUtf8(isolate, "_hash"), v8.String.initUtf8(isolate, "").toValue());
    }
}

fn getStoredProperty(info: v8.FunctionCallbackInfo, prop: []const u8) v8.Value {
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();
    return this.getValue(context, v8.String.initUtf8(isolate, prop)) catch v8.String.initUtf8(isolate, "").toValue();
}

fn urlGetHref(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    info.getReturnValue().set(getStoredProperty(info, "_href"));
}

fn urlGetOrigin(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    // Origin = protocol + "//" + host
    const protocol = this.getValue(context, v8.String.initUtf8(isolate, "_protocol")) catch return;
    const hostname = this.getValue(context, v8.String.initUtf8(isolate, "_hostname")) catch return;
    const port = this.getValue(context, v8.String.initUtf8(isolate, "_port")) catch return;

    var proto_buf: [64]u8 = undefined;
    var host_buf: [256]u8 = undefined;
    var port_buf: [8]u8 = undefined;

    const proto_str = protocol.toString(context) catch return;
    const host_str = hostname.toString(context) catch return;
    const port_str = port.toString(context) catch return;

    const proto_len = proto_str.writeUtf8(isolate, &proto_buf);
    const host_len = host_str.writeUtf8(isolate, &host_buf);
    const port_len = port_str.writeUtf8(isolate, &port_buf);

    var origin_buf: [512]u8 = undefined;
    var origin_str: []const u8 = undefined;

    if (port_len > 0) {
        origin_str = std.fmt.bufPrint(&origin_buf, "{s}//{s}:{s}", .{
            proto_buf[0..proto_len],
            host_buf[0..host_len],
            port_buf[0..port_len],
        }) catch "";
    } else {
        origin_str = std.fmt.bufPrint(&origin_buf, "{s}//{s}", .{
            proto_buf[0..proto_len],
            host_buf[0..host_len],
        }) catch "";
    }

    info.getReturnValue().set(v8.String.initUtf8(isolate, origin_str).toValue());
}

fn urlGetProtocol(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    info.getReturnValue().set(getStoredProperty(info, "_protocol"));
}

fn urlGetHost(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    const hostname = this.getValue(context, v8.String.initUtf8(isolate, "_hostname")) catch return;
    const port = this.getValue(context, v8.String.initUtf8(isolate, "_port")) catch return;

    var host_buf: [256]u8 = undefined;
    var port_buf: [8]u8 = undefined;

    const host_str = hostname.toString(context) catch return;
    const port_str = port.toString(context) catch return;

    const host_len = host_str.writeUtf8(isolate, &host_buf);
    const port_len = port_str.writeUtf8(isolate, &port_buf);

    var result_buf: [280]u8 = undefined;
    var result_str: []const u8 = undefined;

    if (port_len > 0) {
        result_str = std.fmt.bufPrint(&result_buf, "{s}:{s}", .{
            host_buf[0..host_len],
            port_buf[0..port_len],
        }) catch "";
    } else {
        result_str = host_buf[0..host_len];
    }

    info.getReturnValue().set(v8.String.initUtf8(isolate, result_str).toValue());
}

fn urlGetHostname(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    info.getReturnValue().set(getStoredProperty(info, "_hostname"));
}

fn urlGetPort(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    info.getReturnValue().set(getStoredProperty(info, "_port"));
}

fn urlGetPathname(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    info.getReturnValue().set(getStoredProperty(info, "_pathname"));
}

fn urlGetSearch(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    info.getReturnValue().set(getStoredProperty(info, "_search"));
}

fn urlGetHash(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    info.getReturnValue().set(getStoredProperty(info, "_hash"));
}

// ============================================================================
// URLSearchParams Implementation
// ============================================================================

fn searchParamsConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    // Initialize empty params string
    var init_str: []const u8 = "";

    if (info.length() >= 1) {
        const arg = info.getArg(0);
        if (arg.isString()) {
            const str = arg.toString(context) catch {
                _ = this.setValue(context, v8.String.initUtf8(isolate, "_params"), v8.String.initUtf8(isolate, "").toValue());
                return;
            };
            var buf: [4096]u8 = undefined;
            const len = str.writeUtf8(isolate, &buf);
            // Remove leading ? if present
            if (len > 0 and buf[0] == '?') {
                init_str = buf[1..len];
            } else {
                init_str = buf[0..len];
            }
        }
    }

    _ = this.setValue(context, v8.String.initUtf8(isolate, "_params"), v8.String.initUtf8(isolate, init_str).toValue());
}

fn searchParamsGet(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();

    if (info.length() < 1) {
        info.getReturnValue().set(isolate.initNull().toValue());
        return;
    }

    const key_arg = info.getArg(0);
    const key_str = key_arg.toString(context) catch {
        info.getReturnValue().set(isolate.initNull().toValue());
        return;
    };

    var key_buf: [256]u8 = undefined;
    const key_len = key_str.writeUtf8(isolate, &key_buf);
    const key = key_buf[0..key_len];

    // Get stored params
    const this = info.getThis();
    const params_val = this.getValue(context, v8.String.initUtf8(isolate, "_params")) catch {
        info.getReturnValue().set(isolate.initNull().toValue());
        return;
    };
    const params_str = params_val.toString(context) catch {
        info.getReturnValue().set(isolate.initNull().toValue());
        return;
    };

    var params_buf: [4096]u8 = undefined;
    const params_len = params_str.writeUtf8(isolate, &params_buf);
    const params = params_buf[0..params_len];

    // Parse and find key
    var iter = std.mem.splitScalar(u8, params, '&');
    while (iter.next()) |pair| {
        if (std.mem.indexOfScalar(u8, pair, '=')) |eq_pos| {
            const k = pair[0..eq_pos];
            const v = pair[eq_pos + 1 ..];
            if (std.mem.eql(u8, k, key)) {
                info.getReturnValue().set(v8.String.initUtf8(isolate, v).toValue());
                return;
            }
        }
    }

    info.getReturnValue().set(isolate.initNull().toValue());
}

fn searchParamsHas(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();

    if (info.length() < 1) {
        info.getReturnValue().set(v8.Value{ .handle = v8.Boolean.init(isolate, false).handle });
        return;
    }

    const key_arg = info.getArg(0);
    const key_str = key_arg.toString(context) catch {
        info.getReturnValue().set(v8.Value{ .handle = v8.Boolean.init(isolate, false).handle });
        return;
    };

    var key_buf: [256]u8 = undefined;
    const key_len = key_str.writeUtf8(isolate, &key_buf);
    const key = key_buf[0..key_len];

    // Get stored params
    const this = info.getThis();
    const params_val = this.getValue(context, v8.String.initUtf8(isolate, "_params")) catch {
        info.getReturnValue().set(v8.Value{ .handle = v8.Boolean.init(isolate, false).handle });
        return;
    };
    const params_str = params_val.toString(context) catch {
        info.getReturnValue().set(v8.Value{ .handle = v8.Boolean.init(isolate, false).handle });
        return;
    };

    var params_buf: [4096]u8 = undefined;
    const params_len = params_str.writeUtf8(isolate, &params_buf);
    const params = params_buf[0..params_len];

    // Parse and find key
    var iter = std.mem.splitScalar(u8, params, '&');
    while (iter.next()) |pair| {
        if (std.mem.indexOfScalar(u8, pair, '=')) |eq_pos| {
            const k = pair[0..eq_pos];
            if (std.mem.eql(u8, k, key)) {
                info.getReturnValue().set(v8.Value{ .handle = v8.Boolean.init(isolate, true).handle });
                return;
            }
        }
    }

    info.getReturnValue().set(v8.Value{ .handle = v8.Boolean.init(isolate, false).handle });
}

fn searchParamsSet(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();

    if (info.length() < 2) {
        return;
    }

    const key_arg = info.getArg(0);
    const val_arg = info.getArg(1);

    const key_str = key_arg.toString(context) catch return;
    const val_str = val_arg.toString(context) catch return;

    var key_buf: [256]u8 = undefined;
    var val_buf: [1024]u8 = undefined;
    const key_len = key_str.writeUtf8(isolate, &key_buf);
    const val_len = val_str.writeUtf8(isolate, &val_buf);
    const key = key_buf[0..key_len];
    const value = val_buf[0..val_len];

    // Get current params
    const this = info.getThis();
    const params_val = this.getValue(context, v8.String.initUtf8(isolate, "_params")) catch return;
    const params_str = params_val.toString(context) catch return;

    var params_buf: [4096]u8 = undefined;
    const params_len = params_str.writeUtf8(isolate, &params_buf);
    const params = params_buf[0..params_len];

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
                // Replace with new value
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
                // Keep existing pair
                if (result_len > 0) {
                    result_buf[result_len] = '&';
                    result_len += 1;
                }
                @memcpy(result_buf[result_len .. result_len + pair.len], pair);
                result_len += pair.len;
            }
        }
    }

    // If key wasn't found, append it
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

    _ = this.setValue(context, v8.String.initUtf8(isolate, "_params"), v8.String.initUtf8(isolate, result_buf[0..result_len]).toValue());
}

fn searchParamsAppend(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();

    if (info.length() < 2) {
        return;
    }

    const key_arg = info.getArg(0);
    const val_arg = info.getArg(1);

    const key_str = key_arg.toString(context) catch return;
    const val_str = val_arg.toString(context) catch return;

    var key_buf: [256]u8 = undefined;
    var val_buf: [1024]u8 = undefined;
    const key_len = key_str.writeUtf8(isolate, &key_buf);
    const val_len = val_str.writeUtf8(isolate, &val_buf);

    // Get current params
    const this = info.getThis();
    const params_val = this.getValue(context, v8.String.initUtf8(isolate, "_params")) catch return;
    const params_str = params_val.toString(context) catch return;

    var params_buf: [4096]u8 = undefined;
    const params_len = params_str.writeUtf8(isolate, &params_buf);

    // Build new params string
    var result_buf: [8192]u8 = undefined;
    var result_len: usize = 0;

    // Copy existing
    if (params_len > 0) {
        @memcpy(result_buf[0..params_len], params_buf[0..params_len]);
        result_len = params_len;
        result_buf[result_len] = '&';
        result_len += 1;
    }

    // Append new
    @memcpy(result_buf[result_len .. result_len + key_len], key_buf[0..key_len]);
    result_len += key_len;
    result_buf[result_len] = '=';
    result_len += 1;
    @memcpy(result_buf[result_len .. result_len + val_len], val_buf[0..val_len]);
    result_len += val_len;

    _ = this.setValue(context, v8.String.initUtf8(isolate, "_params"), v8.String.initUtf8(isolate, result_buf[0..result_len]).toValue());
}

fn searchParamsDelete(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();

    if (info.length() < 1) {
        return;
    }

    const key_arg = info.getArg(0);
    const key_str = key_arg.toString(context) catch return;

    var key_buf: [256]u8 = undefined;
    const key_len = key_str.writeUtf8(isolate, &key_buf);
    const key = key_buf[0..key_len];

    // Get current params
    const this = info.getThis();
    const params_val = this.getValue(context, v8.String.initUtf8(isolate, "_params")) catch return;
    const params_str = params_val.toString(context) catch return;

    var params_buf: [4096]u8 = undefined;
    const params_len = params_str.writeUtf8(isolate, &params_buf);
    const params = params_buf[0..params_len];

    // Build new params without the key
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

    _ = this.setValue(context, v8.String.initUtf8(isolate, "_params"), v8.String.initUtf8(isolate, result_buf[0..result_len]).toValue());
}

fn searchParamsToString(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    info.getReturnValue().set(getStoredProperty(info, "_params"));
}
