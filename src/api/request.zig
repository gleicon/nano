const std = @import("std");
const v8 = @import("v8");
const js = @import("js");

/// Register Request class on global object
pub fn registerRequestAPI(isolate: v8.Isolate, context: v8.Context) void {
    const global = context.getGlobal();

    // Create Request constructor
    const request_tmpl = v8.FunctionTemplate.initCallback(isolate, requestConstructor);
    const request_proto = request_tmpl.getPrototypeTemplate();

    // url, method, headers are getter properties per WinterCG spec (accessed without parentheses)
    const url_getter = v8.FunctionTemplate.initCallback(isolate, requestUrl);
    request_proto.setAccessorGetter(js.string(isolate, "url").toName(), url_getter);

    const method_getter = v8.FunctionTemplate.initCallback(isolate, requestMethod);
    request_proto.setAccessorGetter(js.string(isolate, "method").toName(), method_getter);

    const headers_getter = v8.FunctionTemplate.initCallback(isolate, requestHeaders);
    request_proto.setAccessorGetter(js.string(isolate, "headers").toName(), headers_getter);

    js.addMethod(request_proto, isolate, "text", requestText);
    js.addMethod(request_proto, isolate, "json", requestJson);

    js.addGlobalClass(global, context, isolate, "Request", request_tmpl);
}

fn requestConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) {
        js.throw(ctx.isolate, "Request requires a URL argument");
        return;
    }

    const url_str = ctx.arg(0).toString(ctx.context) catch {
        js.throw(ctx.isolate, "Request: invalid URL");
        return;
    };

    // Store URL
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_url", url_str);

    // Default values
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_method", js.string(ctx.isolate, "GET"));
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_body", js.string(ctx.isolate, ""));

    // Create headers object
    const headers_obj = js.object(ctx.isolate, ctx.context);
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_headers", headers_obj);

    // Second argument: options (optional)
    if (ctx.argc() >= 2) {
        const opts_arg = ctx.arg(1);
        if (opts_arg.isObject()) {
            const opts = js.asObject(opts_arg);

            const method_val = js.getProp(opts, ctx.context, ctx.isolate, "method") catch null;
            if (method_val) |mv| {
                if (mv.isString()) {
                    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_method", mv);
                }
            }

            const body_val = js.getProp(opts, ctx.context, ctx.isolate, "body") catch null;
            if (body_val) |bv| {
                if (bv.isString()) {
                    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_body", bv);
                }
            }

            const hdrs_val = js.getProp(opts, ctx.context, ctx.isolate, "headers") catch null;
            if (hdrs_val) |hv| {
                if (hv.isObject()) {
                    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_headers", hv);
                }
            }
        }
    }
}

fn requestUrl(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_url") catch {
        js.retString(ctx, "");
        return;
    };
    js.ret(ctx, val);
}

fn requestMethod(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_method") catch {
        js.retString(ctx, "GET");
        return;
    };
    js.ret(ctx, val);
}

fn requestHeaders(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_headers") catch {
        js.ret(ctx, js.object(ctx.isolate, ctx.context));
        return;
    };
    js.ret(ctx, val);
}

fn requestText(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_body") catch {
        js.retResolvedPromise(ctx, js.string(ctx.isolate, "").toValue());
        return;
    };
    js.retResolvedPromise(ctx, val);
}

fn requestJson(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const body_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_body") catch {
        js.retRejectedPromise(ctx, js.string(ctx.isolate, "Request.json: no body").toValue());
        return;
    };

    const body_str = body_val.toString(ctx.context) catch {
        js.retRejectedPromise(ctx, js.string(ctx.isolate, "Request.json: invalid body").toValue());
        return;
    };

    var body_buf: [65536]u8 = undefined;
    const body = js.readString(ctx.isolate, body_str, &body_buf);

    // Use V8's JSON.parse
    const global = ctx.context.getGlobal();
    const json_val = js.getProp(global, ctx.context, ctx.isolate, "JSON") catch {
        js.retRejectedPromise(ctx, js.string(ctx.isolate, "Request.json: JSON not found").toValue());
        return;
    };

    const json_obj = js.asObject(json_val);
    const parse_fn_val = js.getProp(json_obj, ctx.context, ctx.isolate, "parse") catch {
        js.retRejectedPromise(ctx, js.string(ctx.isolate, "Request.json: JSON.parse not found").toValue());
        return;
    };

    const parse_fn = js.asFunction(parse_fn_val);
    var args: [1]v8.Value = .{js.string(ctx.isolate, body).toValue()};
    const result = parse_fn.call(ctx.context, json_val, &args) orelse {
        js.retRejectedPromise(ctx, js.string(ctx.isolate, "Request.json: parse failed").toValue());
        return;
    };

    js.retResolvedPromise(ctx, result);
}

/// Create a Request object from Zig HTTP request data
pub fn createRequest(
    isolate: v8.Isolate,
    context: v8.Context,
    url: []const u8,
    method: []const u8,
    body: []const u8,
) v8.Object {
    const global = context.getGlobal();
    const ctor_val = js.getProp(global, context, isolate, "Request") catch {
        return isolate.initObjectTemplateDefault().initInstance(context);
    };
    const ctor = js.asFunction(ctor_val);

    const url_v8 = js.string(isolate, url).toValue();
    const opts = js.object(isolate, context);
    _ = js.setProp(opts, context, isolate, "method", js.string(isolate, method));
    _ = js.setProp(opts, context, isolate, "body", js.string(isolate, body));

    var args: [2]v8.Value = .{ url_v8, js.objToValue(opts) };
    const result = ctor.initInstance(context, &args) orelse {
        return isolate.initObjectTemplateDefault().initInstance(context);
    };

    return result;
}
