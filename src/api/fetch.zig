const std = @import("std");
const v8 = @import("v8");
const http = std.http;

/// Allocator for HTTP operations
const fetch_allocator = std.heap.page_allocator;

// === SSRF Protection ===
// Block requests to internal/private networks to prevent Server-Side Request Forgery

/// Check if hostname is a private/internal address that should be blocked
fn isBlockedHost(host: []const u8) bool {
    // Block localhost variants
    if (std.mem.eql(u8, host, "localhost") or
        std.mem.eql(u8, host, "127.0.0.1") or
        std.mem.eql(u8, host, "::1") or
        std.mem.eql(u8, host, "[::1]") or
        std.mem.eql(u8, host, "0.0.0.0"))
    {
        return true;
    }

    // Block cloud metadata endpoints (AWS, GCP, Azure, DigitalOcean, etc.)
    if (std.mem.eql(u8, host, "169.254.169.254") or
        std.mem.eql(u8, host, "metadata.google.internal") or
        std.mem.eql(u8, host, "metadata.goog") or
        std.mem.eql(u8, host, "100.100.100.200"))
    { // Alibaba
        return true;
    }

    // Block private IP ranges by parsing as IP
    if (isPrivateIP(host)) {
        return true;
    }

    return false;
}

/// Check if string represents a private IP address
fn isPrivateIP(host: []const u8) bool {
    // Try to parse as IPv4
    var parts: [4]u8 = undefined;
    var part_idx: usize = 0;
    var current: u16 = 0;
    var has_digit = false;

    for (host) |c| {
        if (c >= '0' and c <= '9') {
            current = current * 10 + (c - '0');
            if (current > 255) return false;
            has_digit = true;
        } else if (c == '.') {
            if (!has_digit or part_idx >= 3) return false;
            parts[part_idx] = @truncate(current);
            part_idx += 1;
            current = 0;
            has_digit = false;
        } else {
            return false; // Not a valid IPv4
        }
    }

    if (!has_digit or part_idx != 3) return false;
    parts[3] = @truncate(current);

    // Check private ranges:
    // 10.0.0.0/8 (Class A private)
    if (parts[0] == 10) return true;

    // 172.16.0.0/12 (Class B private)
    if (parts[0] == 172 and parts[1] >= 16 and parts[1] <= 31) return true;

    // 192.168.0.0/16 (Class C private)
    if (parts[0] == 192 and parts[1] == 168) return true;

    // 169.254.0.0/16 (link-local)
    if (parts[0] == 169 and parts[1] == 254) return true;

    // 127.0.0.0/8 (loopback)
    if (parts[0] == 127) return true;

    // 0.0.0.0/8 (current network)
    if (parts[0] == 0) return true;

    return false;
}

/// Register fetch API and Response class on global object
pub fn registerFetchAPI(isolate: v8.Isolate, context: v8.Context) void {
    const global = context.getGlobal();

    // Register fetch function
    const fetch_fn = v8.FunctionTemplate.initCallback(isolate, fetchCallback);
    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "fetch"),
        fetch_fn.getFunction(context),
    );

    // Register Response constructor
    const response_tmpl = v8.FunctionTemplate.initCallback(isolate, responseConstructor);
    const response_proto = response_tmpl.getPrototypeTemplate();

    // Response instance methods
    const status_fn = v8.FunctionTemplate.initCallback(isolate, responseStatus);
    response_proto.set(v8.String.initUtf8(isolate, "status").toName(), status_fn, v8.PropertyAttribute.None);

    const ok_fn = v8.FunctionTemplate.initCallback(isolate, responseOk);
    response_proto.set(v8.String.initUtf8(isolate, "ok").toName(), ok_fn, v8.PropertyAttribute.None);

    const statusText_fn = v8.FunctionTemplate.initCallback(isolate, responseStatusText);
    response_proto.set(v8.String.initUtf8(isolate, "statusText").toName(), statusText_fn, v8.PropertyAttribute.None);

    const headers_fn = v8.FunctionTemplate.initCallback(isolate, responseHeaders);
    response_proto.set(v8.String.initUtf8(isolate, "headers").toName(), headers_fn, v8.PropertyAttribute.None);

    const text_fn = v8.FunctionTemplate.initCallback(isolate, responseText);
    response_proto.set(v8.String.initUtf8(isolate, "text").toName(), text_fn, v8.PropertyAttribute.None);

    const json_fn = v8.FunctionTemplate.initCallback(isolate, responseJson);
    response_proto.set(v8.String.initUtf8(isolate, "json").toName(), json_fn, v8.PropertyAttribute.None);

    const response_ctor = response_tmpl.getFunction(context);

    // Add static methods to Response constructor (cast Function to Object)
    const response_ctor_obj = v8.Object{ .handle = @ptrCast(response_ctor.handle) };
    const json_static_fn = v8.FunctionTemplate.initCallback(isolate, responseJsonStatic);
    _ = response_ctor_obj.setValue(context, v8.String.initUtf8(isolate, "json"), json_static_fn.getFunction(context).toValue());

    const redirect_static_fn = v8.FunctionTemplate.initCallback(isolate, responseRedirect);
    _ = response_ctor_obj.setValue(context, v8.String.initUtf8(isolate, "redirect"), redirect_static_fn.getFunction(context).toValue());

    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "Response"),
        response_ctor.toValue(),
    );
}

/// fetch() - Makes HTTP requests and returns a Promise<Response>
/// Supports both URL string and Request object as first argument
fn fetchCallback(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();

    if (info.length() < 1) {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "fetch() requires a URL or Request argument").toValue());
        return;
    }

    // Create a Promise for the response
    const resolver = v8.PromiseResolver.init(context);
    const promise = resolver.getPromise();

    // Parse URL from first argument
    const url_arg = info.getArg(0);
    var url_buf: [4096]u8 = undefined;
    var url_len: usize = 0;
    var method_buf: [16]u8 = undefined;
    var method_len: usize = 3;
    @memcpy(method_buf[0..3], "GET");
    var body_buf: [65536]u8 = undefined;
    var body_len: usize = 0;

    if (url_arg.isString()) {
        // Direct URL string
        const url_str = url_arg.toString(context) catch {
            _ = resolver.reject(context, v8.String.initUtf8(isolate, "fetch: invalid URL").toValue());
            info.getReturnValue().set(v8.Value{ .handle = @ptrCast(promise.handle) });
            return;
        };
        url_len = url_str.writeUtf8(isolate, &url_buf);
    } else if (url_arg.isObject()) {
        // Request object
        const request_obj = v8.Object{ .handle = @ptrCast(url_arg.handle) };

        // Get URL from request
        const url_val = request_obj.getValue(context, v8.String.initUtf8(isolate, "_url")) catch {
            _ = resolver.reject(context, v8.String.initUtf8(isolate, "fetch: Request has no URL").toValue());
            info.getReturnValue().set(v8.Value{ .handle = @ptrCast(promise.handle) });
            return;
        };
        const url_str = url_val.toString(context) catch {
            _ = resolver.reject(context, v8.String.initUtf8(isolate, "fetch: invalid URL in Request").toValue());
            info.getReturnValue().set(v8.Value{ .handle = @ptrCast(promise.handle) });
            return;
        };
        url_len = url_str.writeUtf8(isolate, &url_buf);

        // Get method from request
        const method_val = request_obj.getValue(context, v8.String.initUtf8(isolate, "_method")) catch null;
        if (method_val) |mv| {
            const m_str = mv.toString(context) catch null;
            if (m_str) |ms| {
                method_len = ms.writeUtf8(isolate, &method_buf);
            }
        }

        // Get body from request
        const body_val = request_obj.getValue(context, v8.String.initUtf8(isolate, "_body")) catch null;
        if (body_val) |bv| {
            const b_str = bv.toString(context) catch null;
            if (b_str) |bs| {
                body_len = bs.writeUtf8(isolate, &body_buf);
            }
        }
    } else {
        _ = resolver.reject(context, v8.String.initUtf8(isolate, "fetch: first argument must be a URL string or Request object").toValue());
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(promise.handle) });
        return;
    }

    // Handle options object (second argument)
    if (info.length() >= 2) {
        const opts_arg = info.getArg(1);
        if (opts_arg.isObject()) {
            const opts_obj = v8.Object{ .handle = @ptrCast(opts_arg.handle) };

            // Check for method
            const method_val = opts_obj.getValue(context, v8.String.initUtf8(isolate, "method")) catch null;
            if (method_val) |mv| {
                if (mv.isString()) {
                    const m_str = mv.toString(context) catch null;
                    if (m_str) |ms| {
                        method_len = ms.writeUtf8(isolate, &method_buf);
                    }
                }
            }

            // Check for body
            const body_val = opts_obj.getValue(context, v8.String.initUtf8(isolate, "body")) catch null;
            if (body_val) |bv| {
                if (bv.isString()) {
                    const b_str = bv.toString(context) catch null;
                    if (b_str) |bs| {
                        body_len = bs.writeUtf8(isolate, &body_buf);
                    }
                }
            }
        }
    }

    const url = url_buf[0..url_len];
    const method = method_buf[0..method_len];
    const body = body_buf[0..body_len];

    // Make the HTTP request
    var result = doFetch(url, method, body) catch |err| {
        var err_buf: [256]u8 = undefined;
        const err_msg = std.fmt.bufPrint(&err_buf, "fetch failed: {s}", .{@errorName(err)}) catch "fetch failed";
        _ = resolver.reject(context, v8.String.initUtf8(isolate, err_msg).toValue());
        info.getReturnValue().set(v8.Value{ .handle = @ptrCast(promise.handle) });
        return;
    };
    defer result.deinit();

    // Create Response object
    const response = createFetchResponse(isolate, context, result.status, result.body, result.headers);

    // Resolve the promise with the Response
    _ = resolver.resolve(context, v8.Value{ .handle = @ptrCast(response.handle) });
    info.getReturnValue().set(v8.Value{ .handle = @ptrCast(promise.handle) });
}

/// A single HTTP header name-value pair (owned copies)
const HeaderEntry = struct {
    name: []u8,
    value: []u8,
};

/// Result of HTTP fetch operation
const FetchResult = struct {
    status: u16,
    body: []u8,
    headers: []HeaderEntry,

    pub fn deinit(self: *FetchResult) void {
        fetch_allocator.free(self.body);
        for (self.headers) |header| {
            fetch_allocator.free(header.name);
            fetch_allocator.free(header.value);
        }
        fetch_allocator.free(self.headers);
    }
};

/// Perform the actual HTTP request using lower-level API for body reading
fn doFetch(url: []const u8, method: []const u8, body: []const u8) !FetchResult {
    // Parse URI
    const uri = std.Uri.parse(url) catch return error.InvalidUrl;

    // SSRF Protection: Block requests to internal/private addresses
    if (uri.host) |host_component| {
        const host = switch (host_component) {
            .raw => |raw| raw,
            .percent_encoded => |encoded| encoded,
        };
        if (isBlockedHost(host)) {
            return error.BlockedHost;
        }
    }

    // Create HTTP client
    var client = http.Client{ .allocator = fetch_allocator };
    defer client.deinit();

    // Determine HTTP method
    const http_method: http.Method = if (std.mem.eql(u8, method, "GET"))
        .GET
    else if (std.mem.eql(u8, method, "POST"))
        .POST
    else if (std.mem.eql(u8, method, "PUT"))
        .PUT
    else if (std.mem.eql(u8, method, "DELETE"))
        .DELETE
    else if (std.mem.eql(u8, method, "PATCH"))
        .PATCH
    else if (std.mem.eql(u8, method, "HEAD"))
        .HEAD
    else if (std.mem.eql(u8, method, "OPTIONS"))
        .OPTIONS
    else
        .GET;

    // Create the request
    var req = client.request(http_method, uri, .{}) catch return error.ConnectionFailed;
    defer req.deinit();

    // Send request body if present
    if (body.len > 0) {
        req.sendBodyComplete(@constCast(body)) catch return error.SendFailed;
    } else {
        req.sendBodiless() catch return error.SendFailed;
    }

    // Allocate a redirect buffer for receiveHead
    var redirect_buffer: [4096]u8 = undefined;

    // Receive response head
    var response = req.receiveHead(&redirect_buffer) catch return error.ResponseFailed;

    // Extract response headers
    var header_list: std.ArrayListUnmanaged(HeaderEntry) = .empty;
    errdefer {
        for (header_list.items) |h| {
            fetch_allocator.free(h.name);
            fetch_allocator.free(h.value);
        }
        header_list.deinit(fetch_allocator);
    }

    var header_iter = response.head.iterateHeaders();
    while (header_iter.next()) |h| {
        // Allocate and copy header name and value
        const name_copy = fetch_allocator.dupe(u8, h.name) catch continue;
        errdefer fetch_allocator.free(name_copy);
        const value_copy = fetch_allocator.dupe(u8, h.value) catch {
            fetch_allocator.free(name_copy);
            continue;
        };

        header_list.append(fetch_allocator, .{ .name = name_copy, .value = value_copy }) catch {
            fetch_allocator.free(name_copy);
            fetch_allocator.free(value_copy);
            continue;
        };
    }

    // Read response body
    var transfer_buffer: [8192]u8 = undefined;
    const reader = response.reader(&transfer_buffer);

    // Read all remaining data using the Reader's allocRemaining
    const response_body = reader.allocRemaining(fetch_allocator, std.Io.Limit.limited(10 * 1024 * 1024)) catch return error.ReadFailed;

    return FetchResult{
        .status = @intFromEnum(response.head.status),
        .body = response_body,
        .headers = header_list.toOwnedSlice(fetch_allocator) catch return error.ReadFailed,
    };
}

/// Create a Response object from fetch result
fn createFetchResponse(isolate: v8.Isolate, context: v8.Context, status: u16, body: []const u8, headers: []const HeaderEntry) v8.Object {
    const global = context.getGlobal();
    const response_ctor_val = global.getValue(context, v8.String.initUtf8(isolate, "Response")) catch {
        return isolate.initObjectTemplateDefault().initInstance(context);
    };
    const response_ctor = v8.Function{ .handle = @ptrCast(response_ctor_val.handle) };

    // Create headers object
    const hdrs = isolate.initObjectTemplateDefault().initInstance(context);
    for (headers) |header| {
        // Convert header name to lowercase for case-insensitive storage
        var lower_name: [256]u8 = undefined;
        const name_len = @min(header.name.len, 255);
        for (header.name[0..name_len], 0..) |c, i| {
            lower_name[i] = std.ascii.toLower(c);
        }
        _ = hdrs.setValue(
            context,
            v8.String.initUtf8(isolate, lower_name[0..name_len]),
            v8.String.initUtf8(isolate, header.value).toValue(),
        );
    }

    // Create options object
    const opts = isolate.initObjectTemplateDefault().initInstance(context);
    _ = opts.setValue(context, v8.String.initUtf8(isolate, "status"), v8.Number.init(isolate, @floatFromInt(status)).toValue());
    _ = opts.setValue(context, v8.String.initUtf8(isolate, "headers"), hdrs);

    // Create Response
    const body_v8 = v8.String.initUtf8(isolate, body).toValue();
    var ctor_args: [2]v8.Value = .{ body_v8, v8.Value{ .handle = @ptrCast(opts.handle) } };
    const response = response_ctor.initInstance(context, &ctor_args) orelse {
        return isolate.initObjectTemplateDefault().initInstance(context);
    };

    return response;
}

fn responseConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    // Default values
    var status: f64 = 200;
    const status_text: []const u8 = "OK";

    // First argument: body (optional)
    if (info.length() >= 1) {
        const body_arg = info.getArg(0);
        if (!body_arg.isNull() and !body_arg.isUndefined()) {
            const body_str = body_arg.toString(context) catch {
                _ = this.setValue(context, v8.String.initUtf8(isolate, "_body"), v8.String.initUtf8(isolate, "").toValue());
                return;
            };
            _ = this.setValue(context, v8.String.initUtf8(isolate, "_body"), body_str.toValue());
        } else {
            _ = this.setValue(context, v8.String.initUtf8(isolate, "_body"), v8.String.initUtf8(isolate, "").toValue());
        }
    } else {
        _ = this.setValue(context, v8.String.initUtf8(isolate, "_body"), v8.String.initUtf8(isolate, "").toValue());
    }

    // Second argument: options (optional)
    if (info.length() >= 2) {
        const opts_arg = info.getArg(1);
        if (opts_arg.isObject()) {
            const opts_obj = v8.Object{ .handle = @ptrCast(opts_arg.handle) };

            // Check for status
            const status_val = opts_obj.getValue(context, v8.String.initUtf8(isolate, "status")) catch null;
            if (status_val) |sv| {
                if (sv.isNumber()) {
                    status = sv.toF64(context) catch 200;
                }
            }

            // Check for statusText
            const st_val = opts_obj.getValue(context, v8.String.initUtf8(isolate, "statusText")) catch null;
            if (st_val) |stv| {
                if (stv.isString()) {
                    var st_buf: [64]u8 = undefined;
                    const st_str = stv.toString(context) catch null;
                    if (st_str) |s| {
                        const len = s.writeUtf8(isolate, &st_buf);
                        _ = this.setValue(context, v8.String.initUtf8(isolate, "_statusText"), v8.String.initUtf8(isolate, st_buf[0..len]).toValue());
                    }
                }
            }

            // Check for headers
            const hdrs_val = opts_obj.getValue(context, v8.String.initUtf8(isolate, "headers")) catch null;
            if (hdrs_val) |hv| {
                if (hv.isObject()) {
                    _ = this.setValue(context, v8.String.initUtf8(isolate, "_headers"), hv);
                }
            }
        }
    }

    _ = this.setValue(context, v8.String.initUtf8(isolate, "_status"), v8.Number.init(isolate, status).toValue());

    // Set default statusText if not already set
    const existing_st = this.getValue(context, v8.String.initUtf8(isolate, "_statusText")) catch null;
    if (existing_st == null or existing_st.?.isUndefined()) {
        _ = this.setValue(context, v8.String.initUtf8(isolate, "_statusText"), v8.String.initUtf8(isolate, status_text).toValue());
    }

    // Set default headers if not already set
    const existing_hdrs = this.getValue(context, v8.String.initUtf8(isolate, "_headers")) catch null;
    if (existing_hdrs == null or existing_hdrs.?.isUndefined()) {
        _ = this.setValue(context, v8.String.initUtf8(isolate, "_headers"), isolate.initObjectTemplateDefault().initInstance(context));
    }
}

fn responseStatus(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    const status_val = this.getValue(context, v8.String.initUtf8(isolate, "_status")) catch {
        info.getReturnValue().set(v8.Number.init(isolate, 200).toValue());
        return;
    };
    info.getReturnValue().set(status_val);
}

fn responseOk(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    const status_val = this.getValue(context, v8.String.initUtf8(isolate, "_status")) catch {
        info.getReturnValue().set(v8.Value{ .handle = v8.Boolean.init(isolate, true).handle });
        return;
    };

    const status = status_val.toF64(context) catch 200;
    const ok = status >= 200 and status < 300;
    info.getReturnValue().set(v8.Value{ .handle = v8.Boolean.init(isolate, ok).handle });
}

fn responseStatusText(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    const st_val = this.getValue(context, v8.String.initUtf8(isolate, "_statusText")) catch {
        info.getReturnValue().set(v8.String.initUtf8(isolate, "OK").toValue());
        return;
    };
    info.getReturnValue().set(st_val);
}

fn responseHeaders(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    const hdrs_val = this.getValue(context, v8.String.initUtf8(isolate, "_headers")) catch {
        info.getReturnValue().set(isolate.initObjectTemplateDefault().initInstance(context));
        return;
    };
    info.getReturnValue().set(hdrs_val);
}

fn responseText(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    const body_val = this.getValue(context, v8.String.initUtf8(isolate, "_body")) catch {
        info.getReturnValue().set(v8.String.initUtf8(isolate, "").toValue());
        return;
    };
    info.getReturnValue().set(body_val);
}

fn responseJson(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    const body_val = this.getValue(context, v8.String.initUtf8(isolate, "_body")) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "json: no body").toValue());
        return;
    };

    const body_str = body_val.toString(context) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "json: invalid body").toValue());
        return;
    };

    var body_buf: [65536]u8 = undefined;
    const body_len = body_str.writeUtf8(isolate, &body_buf);
    const body = body_buf[0..body_len];

    // Use V8's JSON.parse
    const global = context.getGlobal();
    const json_val = global.getValue(context, v8.String.initUtf8(isolate, "JSON")) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "json: JSON not found").toValue());
        return;
    };

    const json_obj = v8.Object{ .handle = @ptrCast(json_val.handle) };
    const parse_fn_val = json_obj.getValue(context, v8.String.initUtf8(isolate, "parse")) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "json: JSON.parse not found").toValue());
        return;
    };

    const parse_fn = v8.Function{ .handle = @ptrCast(parse_fn_val.handle) };
    var args: [1]v8.Value = .{v8.String.initUtf8(isolate, body).toValue()};
    const result = parse_fn.call(context, json_val, &args) orelse {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "json: parse failed").toValue());
        return;
    };

    info.getReturnValue().set(result);
}

// Static method: Response.json(data, options)
fn responseJsonStatic(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();

    if (info.length() < 1) {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "Response.json requires data argument").toValue());
        return;
    }

    const data = info.getArg(0);

    // Stringify the data
    const global = context.getGlobal();
    const json_val = global.getValue(context, v8.String.initUtf8(isolate, "JSON")) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "Response.json: JSON not found").toValue());
        return;
    };

    const json_obj = v8.Object{ .handle = @ptrCast(json_val.handle) };
    const stringify_fn_val = json_obj.getValue(context, v8.String.initUtf8(isolate, "stringify")) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "Response.json: JSON.stringify not found").toValue());
        return;
    };

    const stringify_fn = v8.Function{ .handle = @ptrCast(stringify_fn_val.handle) };
    var stringify_args: [1]v8.Value = .{data};
    const body_str = stringify_fn.call(context, json_val, &stringify_args) orelse {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "Response.json: stringify failed").toValue());
        return;
    };

    // Create Response with JSON body
    const response_ctor_val = global.getValue(context, v8.String.initUtf8(isolate, "Response")) catch return;
    const response_ctor = v8.Function{ .handle = @ptrCast(response_ctor_val.handle) };

    // Create options, merging user-provided options with Content-Type header
    const opts = isolate.initObjectTemplateDefault().initInstance(context);
    const hdrs = isolate.initObjectTemplateDefault().initInstance(context);
    _ = hdrs.setValue(context, v8.String.initUtf8(isolate, "content-type"), v8.String.initUtf8(isolate, "application/json").toValue());

    // If user provided options (second argument), merge status and headers
    if (info.length() >= 2) {
        const user_opts = info.getArg(1);
        if (user_opts.isObject()) {
            const user_opts_obj = v8.Object{ .handle = @ptrCast(user_opts.handle) };

            // Copy status if provided
            const status_val = user_opts_obj.getValue(context, v8.String.initUtf8(isolate, "status")) catch null;
            if (status_val) |sv| {
                if (sv.isNumber()) {
                    _ = opts.setValue(context, v8.String.initUtf8(isolate, "status"), sv);
                }
            }

            // Merge user headers (user headers take precedence, except content-type)
            const user_hdrs_val = user_opts_obj.getValue(context, v8.String.initUtf8(isolate, "headers")) catch null;
            if (user_hdrs_val) |uhv| {
                if (uhv.isObject()) {
                    // User provided headers - we still ensure content-type is application/json
                    // For simplicity, we just use our headers with content-type set
                    // A full implementation would merge all user headers
                }
            }
        }
    }

    _ = opts.setValue(context, v8.String.initUtf8(isolate, "headers"), hdrs);

    var ctor_args: [2]v8.Value = .{ body_str, v8.Value{ .handle = @ptrCast(opts.handle) } };
    const response = response_ctor.initInstance(context, &ctor_args) orelse {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "Response.json: failed to create Response").toValue());
        return;
    };

    info.getReturnValue().set(v8.Value{ .handle = @ptrCast(response.handle) });
}

// === SSRF Protection Tests ===

test "isBlockedHost blocks localhost" {
    try std.testing.expect(isBlockedHost("localhost"));
    try std.testing.expect(isBlockedHost("127.0.0.1"));
    try std.testing.expect(isBlockedHost("::1"));
    try std.testing.expect(isBlockedHost("[::1]"));
    try std.testing.expect(isBlockedHost("0.0.0.0"));
}

test "isBlockedHost blocks cloud metadata" {
    try std.testing.expect(isBlockedHost("169.254.169.254")); // AWS/Azure/GCP
    try std.testing.expect(isBlockedHost("metadata.google.internal")); // GCP
}

test "isPrivateIP blocks private ranges" {
    // Class A private (10.0.0.0/8)
    try std.testing.expect(isPrivateIP("10.0.0.1"));
    try std.testing.expect(isPrivateIP("10.255.255.255"));

    // Class B private (172.16.0.0/12)
    try std.testing.expect(isPrivateIP("172.16.0.1"));
    try std.testing.expect(isPrivateIP("172.31.255.255"));
    try std.testing.expect(!isPrivateIP("172.15.0.1")); // Just outside range
    try std.testing.expect(!isPrivateIP("172.32.0.1")); // Just outside range

    // Class C private (192.168.0.0/16)
    try std.testing.expect(isPrivateIP("192.168.0.1"));
    try std.testing.expect(isPrivateIP("192.168.255.255"));

    // Link-local (169.254.0.0/16)
    try std.testing.expect(isPrivateIP("169.254.0.1"));

    // Loopback (127.0.0.0/8)
    try std.testing.expect(isPrivateIP("127.0.0.1"));
    try std.testing.expect(isPrivateIP("127.255.255.255"));
}

test "isPrivateIP allows public IPs" {
    try std.testing.expect(!isPrivateIP("8.8.8.8")); // Google DNS
    try std.testing.expect(!isPrivateIP("1.1.1.1")); // Cloudflare DNS
    try std.testing.expect(!isPrivateIP("93.184.216.34")); // example.com
    try std.testing.expect(!isPrivateIP("104.21.234.56")); // Cloudflare
}

test "isBlockedHost allows public hostnames" {
    try std.testing.expect(!isBlockedHost("example.com"));
    try std.testing.expect(!isBlockedHost("api.github.com"));
    try std.testing.expect(!isBlockedHost("8.8.8.8"));
}

// Static method: Response.redirect(url, status)
fn responseRedirect(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();

    if (info.length() < 1) {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "Response.redirect requires URL argument").toValue());
        return;
    }

    const url = info.getArg(0);
    var status: f64 = 302; // Default redirect status

    if (info.length() >= 2) {
        const status_arg = info.getArg(1);
        if (status_arg.isNumber()) {
            status = status_arg.toF64(context) catch 302;
        }
    }

    // Create Response with redirect
    const global = context.getGlobal();
    const response_ctor_val = global.getValue(context, v8.String.initUtf8(isolate, "Response")) catch return;
    const response_ctor = v8.Function{ .handle = @ptrCast(response_ctor_val.handle) };

    const opts = isolate.initObjectTemplateDefault().initInstance(context);
    _ = opts.setValue(context, v8.String.initUtf8(isolate, "status"), v8.Number.init(isolate, status).toValue());

    const hdrs = isolate.initObjectTemplateDefault().initInstance(context);
    const url_str = url.toString(context) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "Response.redirect: invalid URL").toValue());
        return;
    };
    _ = hdrs.setValue(context, v8.String.initUtf8(isolate, "location"), url_str.toValue());
    _ = opts.setValue(context, v8.String.initUtf8(isolate, "headers"), hdrs);

    var ctor_args: [2]v8.Value = .{ isolate.initNull().toValue(), v8.Value{ .handle = @ptrCast(opts.handle) } };
    const response = response_ctor.initInstance(context, &ctor_args) orelse {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "Response.redirect: failed to create Response").toValue());
        return;
    };

    info.getReturnValue().set(v8.Value{ .handle = @ptrCast(response.handle) });
}

