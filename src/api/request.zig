const std = @import("std");
const v8 = @import("v8");

/// Register Request class on global object
pub fn registerRequestAPI(isolate: v8.Isolate, context: v8.Context) void {
    const global = context.getGlobal();

    // Create Request constructor
    const request_tmpl = v8.FunctionTemplate.initCallback(isolate, requestConstructor);
    const request_proto = request_tmpl.getPrototypeTemplate();

    // Request property getters (implemented as methods for simplicity)
    const url_fn = v8.FunctionTemplate.initCallback(isolate, requestUrl);
    request_proto.set(v8.String.initUtf8(isolate, "url").toName(), url_fn, v8.PropertyAttribute.None);

    const method_fn = v8.FunctionTemplate.initCallback(isolate, requestMethod);
    request_proto.set(v8.String.initUtf8(isolate, "method").toName(), method_fn, v8.PropertyAttribute.None);

    const headers_fn = v8.FunctionTemplate.initCallback(isolate, requestHeaders);
    request_proto.set(v8.String.initUtf8(isolate, "headers").toName(), headers_fn, v8.PropertyAttribute.None);

    const text_fn = v8.FunctionTemplate.initCallback(isolate, requestText);
    request_proto.set(v8.String.initUtf8(isolate, "text").toName(), text_fn, v8.PropertyAttribute.None);

    const json_fn = v8.FunctionTemplate.initCallback(isolate, requestJson);
    request_proto.set(v8.String.initUtf8(isolate, "json").toName(), json_fn, v8.PropertyAttribute.None);

    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "Request"),
        request_tmpl.getFunction(context),
    );
}

fn requestConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    // First argument: URL (required)
    if (info.length() < 1) {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "Request requires a URL argument").toValue());
        return;
    }

    const url_arg = info.getArg(0);
    const url_str = url_arg.toString(context) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "Request: invalid URL").toValue());
        return;
    };

    // Store URL
    _ = this.setValue(context, v8.String.initUtf8(isolate, "_url"), url_str.toValue());

    // Default values
    _ = this.setValue(context, v8.String.initUtf8(isolate, "_method"), v8.String.initUtf8(isolate, "GET").toValue());
    _ = this.setValue(context, v8.String.initUtf8(isolate, "_body"), v8.String.initUtf8(isolate, "").toValue());

    // Create headers object
    const headers_obj = isolate.initObjectTemplateDefault().initInstance(context);
    _ = this.setValue(context, v8.String.initUtf8(isolate, "_headers"), headers_obj);

    // Second argument: options (optional)
    if (info.length() >= 2) {
        const opts_arg = info.getArg(1);
        if (opts_arg.isObject()) {
            const opts_obj = v8.Object{ .handle = @ptrCast(opts_arg.handle) };

            // Check for method
            const method_val = opts_obj.getValue(context, v8.String.initUtf8(isolate, "method")) catch null;
            if (method_val) |mv| {
                if (mv.isString()) {
                    _ = this.setValue(context, v8.String.initUtf8(isolate, "_method"), mv);
                }
            }

            // Check for body
            const body_val = opts_obj.getValue(context, v8.String.initUtf8(isolate, "body")) catch null;
            if (body_val) |bv| {
                if (bv.isString()) {
                    _ = this.setValue(context, v8.String.initUtf8(isolate, "_body"), bv);
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
}

fn requestUrl(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    const url_val = this.getValue(context, v8.String.initUtf8(isolate, "_url")) catch {
        info.getReturnValue().set(v8.String.initUtf8(isolate, "").toValue());
        return;
    };
    info.getReturnValue().set(url_val);
}

fn requestMethod(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    const method_val = this.getValue(context, v8.String.initUtf8(isolate, "_method")) catch {
        info.getReturnValue().set(v8.String.initUtf8(isolate, "GET").toValue());
        return;
    };
    info.getReturnValue().set(method_val);
}

fn requestHeaders(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    const headers_val = this.getValue(context, v8.String.initUtf8(isolate, "_headers")) catch {
        info.getReturnValue().set(isolate.initObjectTemplateDefault().initInstance(context));
        return;
    };
    info.getReturnValue().set(headers_val);
}

fn requestText(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
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

fn requestJson(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    const body_val = this.getValue(context, v8.String.initUtf8(isolate, "_body")) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "Request.json: no body").toValue());
        return;
    };

    const body_str = body_val.toString(context) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "Request.json: invalid body").toValue());
        return;
    };

    var body_buf: [65536]u8 = undefined;
    const body_len = body_str.writeUtf8(isolate, &body_buf);
    const body = body_buf[0..body_len];

    // Use V8's JSON.parse
    const global = context.getGlobal();
    const json_val = global.getValue(context, v8.String.initUtf8(isolate, "JSON")) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "Request.json: JSON not found").toValue());
        return;
    };

    const json_obj = v8.Object{ .handle = @ptrCast(json_val.handle) };
    const parse_fn_val = json_obj.getValue(context, v8.String.initUtf8(isolate, "parse")) catch {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "Request.json: JSON.parse not found").toValue());
        return;
    };

    const parse_fn = v8.Function{ .handle = @ptrCast(parse_fn_val.handle) };
    var args: [1]v8.Value = .{v8.String.initUtf8(isolate, body).toValue()};
    const result = parse_fn.call(context, json_val, &args) orelse {
        _ = isolate.throwException(v8.String.initUtf8(isolate, "Request.json: parse failed").toValue());
        return;
    };

    info.getReturnValue().set(result);
}

/// Create a Request object from Zig HTTP request data
/// This is called from the HTTP server to create Request objects for JS handlers
pub fn createRequest(
    isolate: v8.Isolate,
    context: v8.Context,
    url: []const u8,
    method: []const u8,
    body: []const u8,
) v8.Object {
    // Get Request constructor
    const global = context.getGlobal();
    const ctor_val = global.getValue(context, v8.String.initUtf8(isolate, "Request")) catch {
        return isolate.initObjectTemplateDefault().initInstance(context);
    };
    const ctor = v8.Function{ .handle = @ptrCast(ctor_val.handle) };

    // Create URL string and options object
    const url_v8 = v8.String.initUtf8(isolate, url).toValue();
    const opts = isolate.initObjectTemplateDefault().initInstance(context);
    _ = opts.setValue(context, v8.String.initUtf8(isolate, "method"), v8.String.initUtf8(isolate, method).toValue());
    _ = opts.setValue(context, v8.String.initUtf8(isolate, "body"), v8.String.initUtf8(isolate, body).toValue());

    // Call constructor
    var args: [2]v8.Value = .{ url_v8, v8.Value{ .handle = @ptrCast(opts.handle) } };
    const result = ctor.initInstance(context, &args) orelse {
        return isolate.initObjectTemplateDefault().initInstance(context);
    };

    return result;
}
