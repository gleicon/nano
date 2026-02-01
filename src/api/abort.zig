const std = @import("std");
const v8 = @import("v8");
const js = @import("js");

/// Register AbortController and AbortSignal APIs
pub fn registerAbortAPI(isolate: v8.Isolate, context: v8.Context) void {
    const global = context.getGlobal();

    // Register AbortSignal constructor
    const signal_tmpl = v8.FunctionTemplate.initCallback(isolate, abortSignalConstructor);
    const signal_proto = signal_tmpl.getPrototypeTemplate();

    js.addMethod(signal_proto, isolate, "throwIfAborted", signalThrowIfAborted);

    const signal_ctor = signal_tmpl.getFunction(context);
    const signal_ctor_obj = js.asObject(signal_ctor.toValue());

    // Static methods
    js.addGlobalFn(signal_ctor_obj, context, isolate, "abort", signalAbortStatic);
    js.addGlobalFn(signal_ctor_obj, context, isolate, "timeout", signalTimeoutStatic);

    js.addGlobalObj(global, context, isolate, "AbortSignal", signal_ctor);

    // Register AbortController constructor
    const controller_tmpl = v8.FunctionTemplate.initCallback(isolate, abortControllerConstructor);
    const controller_proto = controller_tmpl.getPrototypeTemplate();

    js.addMethod(controller_proto, isolate, "signal", controllerSignal);
    js.addMethod(controller_proto, isolate, "abort", controllerAbort);

    js.addGlobalClass(global, context, isolate, "AbortController", controller_tmpl);
}

/// Create an AbortSignal object (internal helper)
pub fn createAbortSignal(isolate: v8.Isolate, context: v8.Context, aborted: bool, reason: ?v8.Value) v8.Object {
    const signal = v8.Object.init(isolate);

    _ = js.setProp(signal, context, isolate, "aborted", js.boolean(isolate, aborted));
    if (reason) |r| {
        _ = js.setProp(signal, context, isolate, "reason", r);
    } else {
        _ = js.setProp(signal, context, isolate, "reason", js.undefined_(isolate));
    }

    // throwIfAborted remains a method
    const throw_fn = v8.FunctionTemplate.initCallback(isolate, signalThrowIfAborted);
    _ = js.setProp(signal, context, isolate, "throwIfAborted", throw_fn.getFunction(context));

    return signal;
}

/// Check if a signal is aborted
pub fn isSignalAborted(isolate: v8.Isolate, context: v8.Context, signal: v8.Object) bool {
    const aborted_val = js.getProp(signal, context, isolate, "aborted") catch return false;
    if (aborted_val.isBoolean()) {
        return aborted_val.toBoolean(isolate);
    }
    return false;
}

/// Get the abort reason from a signal
pub fn getSignalReason(isolate: v8.Isolate, context: v8.Context, signal: v8.Object) v8.Value {
    return js.getProp(signal, context, isolate, "reason") catch js.undefined_(isolate).toValue();
}

// === AbortSignal implementation ===

fn abortSignalConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "aborted", js.boolean(ctx.isolate, false));
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "reason", js.undefined_(ctx.isolate));
}

fn signalThrowIfAborted(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const aborted_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "aborted") catch return;
    if (aborted_val.isBoolean() and aborted_val.isTrue()) {
        const reason = js.getProp(ctx.this, ctx.context, ctx.isolate, "reason") catch {
            js.throw(ctx.isolate, "AbortError: The operation was aborted");
            return;
        };
        if (reason.isUndefined()) {
            js.throw(ctx.isolate, "AbortError: The operation was aborted");
        } else {
            _ = ctx.isolate.throwException(reason);
        }
    }
}

fn signalAbortStatic(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    var reason: ?v8.Value = null;
    if (ctx.argc() >= 1) {
        reason = ctx.arg(0);
    }

    const signal = createAbortSignal(ctx.isolate, ctx.context, true, reason);
    js.ret(ctx, signal);
}

fn signalTimeoutStatic(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    // Simplified: creates non-aborted signal (full impl needs timer integration)
    const signal = createAbortSignal(ctx.isolate, ctx.context, false, null);
    js.ret(ctx, signal);
}

// === AbortController implementation ===

fn abortControllerConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const signal = createAbortSignal(ctx.isolate, ctx.context, false, null);
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_signal", signal);
}

fn controllerSignal(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const signal_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_signal") catch return js.retUndefined(ctx);
    js.ret(ctx, signal_val);
}

fn controllerAbort(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    var reason = js.undefined_(ctx.isolate).toValue();
    if (ctx.argc() >= 1) {
        reason = ctx.arg(0);
    }

    const signal_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_signal") catch return;
    if (!signal_val.isObject()) return;
    const signal = js.asObject(signal_val);

    _ = js.setProp(signal, ctx.context, ctx.isolate, "aborted", js.boolean(ctx.isolate, true));
    _ = js.setProp(signal, ctx.context, ctx.isolate, "reason", reason);
}
