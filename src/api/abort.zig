const std = @import("std");
const v8 = @import("v8");

/// Register AbortController and AbortSignal APIs
pub fn registerAbortAPI(isolate: v8.Isolate, context: v8.Context) void {
    const global = context.getGlobal();

    // Register AbortSignal constructor (not directly constructable, but needed for instanceof)
    const signal_tmpl = v8.FunctionTemplate.initCallback(isolate, abortSignalConstructor);
    const signal_proto = signal_tmpl.getPrototypeTemplate();

    // AbortSignal.aborted getter (returns boolean)
    const aborted_fn = v8.FunctionTemplate.initCallback(isolate, signalAborted);
    signal_proto.set(v8.String.initUtf8(isolate, "aborted").toName(), aborted_fn, v8.PropertyAttribute.None);

    // AbortSignal.reason getter (returns reason or undefined)
    const reason_fn = v8.FunctionTemplate.initCallback(isolate, signalReason);
    signal_proto.set(v8.String.initUtf8(isolate, "reason").toName(), reason_fn, v8.PropertyAttribute.None);

    // AbortSignal.throwIfAborted() method
    const throw_fn = v8.FunctionTemplate.initCallback(isolate, signalThrowIfAborted);
    signal_proto.set(v8.String.initUtf8(isolate, "throwIfAborted").toName(), throw_fn, v8.PropertyAttribute.None);

    const signal_ctor = signal_tmpl.getFunction(context);

    // Add static methods to AbortSignal
    const signal_ctor_obj = v8.Object{ .handle = @ptrCast(signal_ctor.handle) };

    // AbortSignal.abort(reason) - creates an already-aborted signal
    const abort_static_fn = v8.FunctionTemplate.initCallback(isolate, signalAbortStatic);
    _ = signal_ctor_obj.setValue(context, v8.String.initUtf8(isolate, "abort"), abort_static_fn.getFunction(context).toValue());

    // AbortSignal.timeout(ms) - creates a signal that aborts after timeout
    const timeout_static_fn = v8.FunctionTemplate.initCallback(isolate, signalTimeoutStatic);
    _ = signal_ctor_obj.setValue(context, v8.String.initUtf8(isolate, "timeout"), timeout_static_fn.getFunction(context).toValue());

    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "AbortSignal"),
        signal_ctor.toValue(),
    );

    // Register AbortController constructor
    const controller_tmpl = v8.FunctionTemplate.initCallback(isolate, abortControllerConstructor);
    const controller_proto = controller_tmpl.getPrototypeTemplate();

    // AbortController.signal getter
    const signal_getter_fn = v8.FunctionTemplate.initCallback(isolate, controllerSignal);
    controller_proto.set(v8.String.initUtf8(isolate, "signal").toName(), signal_getter_fn, v8.PropertyAttribute.None);

    // AbortController.abort(reason) method
    const controller_abort_fn = v8.FunctionTemplate.initCallback(isolate, controllerAbort);
    controller_proto.set(v8.String.initUtf8(isolate, "abort").toName(), controller_abort_fn, v8.PropertyAttribute.None);

    _ = global.setValue(
        context,
        v8.String.initUtf8(isolate, "AbortController"),
        controller_tmpl.getFunction(context),
    );
}

/// Create an AbortSignal object (internal helper)
pub fn createAbortSignal(isolate: v8.Isolate, context: v8.Context, aborted: bool, reason: ?v8.Value) v8.Object {
    const global = context.getGlobal();
    const signal_ctor_val = global.getValue(context, v8.String.initUtf8(isolate, "AbortSignal")) catch {
        return isolate.initObjectTemplateDefault().initInstance(context);
    };
    const signal_ctor = v8.Function{ .handle = @ptrCast(signal_ctor_val.handle) };

    var args: [0]v8.Value = .{};
    const signal = signal_ctor.initInstance(context, &args) orelse {
        return isolate.initObjectTemplateDefault().initInstance(context);
    };

    // Set internal state
    _ = signal.setValue(context, v8.String.initUtf8(isolate, "_aborted"), v8.Value{ .handle = v8.Boolean.init(isolate, aborted).handle });
    if (reason) |r| {
        _ = signal.setValue(context, v8.String.initUtf8(isolate, "_reason"), r);
    } else {
        _ = signal.setValue(context, v8.String.initUtf8(isolate, "_reason"), isolate.initUndefined().toValue());
    }

    return signal;
}

/// Check if a signal is aborted (for use by fetch and other APIs)
pub fn isSignalAborted(isolate: v8.Isolate, context: v8.Context, signal: v8.Object) bool {
    const aborted_val = signal.getValue(context, v8.String.initUtf8(isolate, "_aborted")) catch return false;
    if (aborted_val.isBoolean()) {
        return aborted_val.toBoolean(isolate);
    }
    return false;
}

/// Get the abort reason from a signal
pub fn getSignalReason(isolate: v8.Isolate, context: v8.Context, signal: v8.Object) v8.Value {
    return signal.getValue(context, v8.String.initUtf8(isolate, "_reason")) catch isolate.initUndefined().toValue();
}

// === AbortSignal implementation ===

fn abortSignalConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    // Initialize as not aborted
    _ = this.setValue(context, v8.String.initUtf8(isolate, "_aborted"), v8.Value{ .handle = v8.Boolean.init(isolate, false).handle });
    _ = this.setValue(context, v8.String.initUtf8(isolate, "_reason"), isolate.initUndefined().toValue());
}

fn signalAborted(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    const aborted_val = this.getValue(context, v8.String.initUtf8(isolate, "_aborted")) catch {
        info.getReturnValue().set(v8.Value{ .handle = v8.Boolean.init(isolate, false).handle });
        return;
    };
    info.getReturnValue().set(aborted_val);
}

fn signalReason(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    const reason_val = this.getValue(context, v8.String.initUtf8(isolate, "_reason")) catch {
        info.getReturnValue().set(isolate.initUndefined().toValue());
        return;
    };
    info.getReturnValue().set(reason_val);
}

fn signalThrowIfAborted(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    const aborted_val = this.getValue(context, v8.String.initUtf8(isolate, "_aborted")) catch return;
    if (aborted_val.isBoolean() and aborted_val.isTrue()) {
        const reason = this.getValue(context, v8.String.initUtf8(isolate, "_reason")) catch {
            _ = isolate.throwException(v8.String.initUtf8(isolate, "AbortError: The operation was aborted").toValue());
            return;
        };
        if (reason.isUndefined()) {
            _ = isolate.throwException(v8.String.initUtf8(isolate, "AbortError: The operation was aborted").toValue());
        } else {
            _ = isolate.throwException(reason);
        }
    }
}

fn signalAbortStatic(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();

    // Get optional reason argument
    var reason: ?v8.Value = null;
    if (info.length() >= 1) {
        reason = info.getArg(0);
    }

    const signal = createAbortSignal(isolate, context, true, reason);
    info.getReturnValue().set(v8.Value{ .handle = @ptrCast(signal.handle) });
}

fn signalTimeoutStatic(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();

    // For now, create a non-aborted signal
    // Full implementation would integrate with setTimeout to auto-abort
    // This is a simplified version that returns a signal that can be manually checked
    _ = info.length(); // Would use timeout_ms

    const signal = createAbortSignal(isolate, context, false, null);

    // Note: Full implementation needs event loop integration to auto-abort after timeout
    // For now, this just creates a signal. Real timeout behavior requires timer integration.

    info.getReturnValue().set(v8.Value{ .handle = @ptrCast(signal.handle) });
}

// === AbortController implementation ===

fn abortControllerConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    // Create associated AbortSignal
    const signal = createAbortSignal(isolate, context, false, null);
    _ = this.setValue(context, v8.String.initUtf8(isolate, "_signal"), v8.Value{ .handle = @ptrCast(signal.handle) });
}

fn controllerSignal(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    const signal_val = this.getValue(context, v8.String.initUtf8(isolate, "_signal")) catch {
        info.getReturnValue().set(isolate.initUndefined().toValue());
        return;
    };
    info.getReturnValue().set(signal_val);
}

fn controllerAbort(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const context = isolate.getCurrentContext();
    const this = info.getThis();

    // Get optional reason argument
    var reason = isolate.initUndefined().toValue();
    if (info.length() >= 1) {
        reason = info.getArg(0);
    }

    // Get the signal
    const signal_val = this.getValue(context, v8.String.initUtf8(isolate, "_signal")) catch return;
    if (!signal_val.isObject()) return;
    const signal = v8.Object{ .handle = @ptrCast(signal_val.handle) };

    // Set aborted state
    _ = signal.setValue(context, v8.String.initUtf8(isolate, "_aborted"), v8.Value{ .handle = v8.Boolean.init(isolate, true).handle });
    _ = signal.setValue(context, v8.String.initUtf8(isolate, "_reason"), reason);

    // Note: Full implementation would dispatch 'abort' event to listeners
    // For basic usage, checking .aborted property is sufficient
}
