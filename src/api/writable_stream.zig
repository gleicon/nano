const std = @import("std");
const v8 = @import("v8");
const js = @import("js");

/// Max buffer size for WritableStream (passed from config)
var global_max_buffer_size: usize = 64 * 1024 * 1024; // 64MB default

/// Register WritableStream, WritableStreamDefaultController, and WritableStreamDefaultWriter APIs
pub fn registerWritableStreamAPI(isolate: v8.Isolate, context: v8.Context, max_buffer_size: usize) void {
    global_max_buffer_size = max_buffer_size;
    const global = context.getGlobal();

    // Register WritableStream constructor
    const stream_tmpl = v8.FunctionTemplate.initCallback(isolate, writableStreamConstructor);
    const stream_proto = stream_tmpl.getPrototypeTemplate();

    js.addMethod(stream_proto, isolate, "getWriter", writableStreamGetWriter);
    js.addMethod(stream_proto, isolate, "abort", writableStreamAbort);

    // Add locked property getter
    const locked_getter = v8.FunctionTemplate.initCallback(isolate, writableStreamLockedGetter);
    stream_proto.setAccessorGetter(
        js.string(isolate, "locked").toName(),
        locked_getter,
    );

    js.addGlobalClass(global, context, isolate, "WritableStream", stream_tmpl);

    // Register WritableStreamDefaultController constructor (internal use)
    const controller_tmpl = v8.FunctionTemplate.initCallback(isolate, controllerConstructor);
    const controller_proto = controller_tmpl.getPrototypeTemplate();

    js.addMethod(controller_proto, isolate, "error", controllerError);

    js.addGlobalClass(global, context, isolate, "WritableStreamDefaultController", controller_tmpl);

    // Register WritableStreamDefaultWriter constructor (internal use)
    const writer_tmpl = v8.FunctionTemplate.initCallback(isolate, writerConstructor);
    const writer_proto = writer_tmpl.getPrototypeTemplate();

    js.addMethod(writer_proto, isolate, "write", writerWrite);
    js.addMethod(writer_proto, isolate, "close", writerClose);
    js.addMethod(writer_proto, isolate, "abort", writerAbort);
    js.addMethod(writer_proto, isolate, "releaseLock", writerReleaseLock);

    // Add ready property getter
    const ready_getter = v8.FunctionTemplate.initCallback(isolate, writerReadyGetter);
    writer_proto.setAccessorGetter(
        js.string(isolate, "ready").toName(),
        ready_getter,
    );

    // Add closed property getter
    const closed_getter = v8.FunctionTemplate.initCallback(isolate, writerClosedGetter);
    writer_proto.setAccessorGetter(
        js.string(isolate, "closed").toName(),
        closed_getter,
    );

    // Add desiredSize property getter
    const desired_size_getter = v8.FunctionTemplate.initCallback(isolate, writerDesiredSizeGetter);
    writer_proto.setAccessorGetter(
        js.string(isolate, "desiredSize").toName(),
        desired_size_getter,
    );

    js.addGlobalClass(global, context, isolate, "WritableStreamDefaultWriter", writer_tmpl);
}

// ============================================================================
// WritableStream Implementation
// ============================================================================

fn writableStreamConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    // Initialize state
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_state", js.string(ctx.isolate, "writable"));
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_writer", js.null_(ctx.isolate));
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_queue", js.array(ctx.isolate, 0));
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_queueByteSize", js.number(ctx.isolate, 0));
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_closeRequested", js.boolean(ctx.isolate, false));
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_writing", js.boolean(ctx.isolate, false));
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_maxBufferSize", js.number(ctx.isolate, global_max_buffer_size));

    // Default strategy
    var high_water_mark: f64 = 1.0;

    // First argument: underlyingSink (optional)
    var sink_obj: ?v8.Object = null;
    if (ctx.argc() >= 1) {
        const sink_arg = ctx.arg(0);
        if (sink_arg.isObject()) {
            sink_obj = js.asObject(sink_arg);
            _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_underlyingSink", sink_arg);
        }
    }

    // Second argument: strategy (optional)
    if (ctx.argc() >= 2) {
        const strategy_arg = ctx.arg(1);
        if (strategy_arg.isObject()) {
            const strategy = js.asObject(strategy_arg);
            const hwm_val = js.getProp(strategy, ctx.context, ctx.isolate, "highWaterMark") catch null;
            if (hwm_val) |hwm| {
                if (hwm.isNumber()) {
                    high_water_mark = hwm.toF64(ctx.context) catch 1.0;
                }
            }
        }
    }

    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_highWaterMark", js.number(ctx.isolate, high_water_mark));

    // Create controller
    const global = ctx.context.getGlobal();
    const controller_ctor_val = js.getProp(global, ctx.context, ctx.isolate, "WritableStreamDefaultController") catch {
        js.throw(ctx.isolate, "WritableStreamDefaultController not found");
        return;
    };
    const controller_ctor = js.asFunction(controller_ctor_val);

    var args: [1]v8.Value = .{js.objToValue(ctx.this)};
    const controller = controller_ctor.initInstance(ctx.context, &args) orelse {
        js.throw(ctx.isolate, "Failed to create controller");
        return;
    };

    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_controller", controller);

    // Call start callback if provided
    if (sink_obj) |sink| {
        const start_val = js.getProp(sink, ctx.context, ctx.isolate, "start") catch null;
        if (start_val) |sv| {
            if (sv.isFunction()) {
                const start_fn = js.asFunction(sv);
                var start_args: [1]v8.Value = .{js.objToValue(controller)};
                _ = start_fn.call(ctx.context, js.objToValue(sink), &start_args);
            }
        }
    }
}

fn writableStreamLockedGetter(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const writer_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_writer") catch {
        js.retBool(ctx, false);
        return;
    };

    js.retBool(ctx, !writer_val.isNull() and !writer_val.isUndefined());
}

fn writableStreamGetWriter(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    // Check if already locked
    const writer_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_writer") catch {
        js.throw(ctx.isolate, "Failed to get writer state");
        return;
    };

    if (!writer_val.isNull() and !writer_val.isUndefined()) {
        js.throw(ctx.isolate, "TypeError: WritableStream is locked");
        return;
    }

    // Create writer
    const global = ctx.context.getGlobal();
    const writer_ctor_val = js.getProp(global, ctx.context, ctx.isolate, "WritableStreamDefaultWriter") catch {
        js.throw(ctx.isolate, "WritableStreamDefaultWriter not found");
        return;
    };
    const writer_ctor = js.asFunction(writer_ctor_val);

    var args: [1]v8.Value = .{js.objToValue(ctx.this)};
    const writer = writer_ctor.initInstance(ctx.context, &args) orelse {
        js.throw(ctx.isolate, "Failed to create writer");
        return;
    };

    js.ret(ctx, writer);
}

fn writableStreamAbort(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const reason = if (ctx.argc() >= 1) ctx.arg(0) else js.undefined_(ctx.isolate).toValue();

    // Transition to errored state
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_state", js.string(ctx.isolate, "errored"));

    // Call abort callback if provided
    const sink_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_underlyingSink") catch null;
    if (sink_val) |sv| {
        if (sv.isObject()) {
            const sink = js.asObject(sv);
            const abort_val = js.getProp(sink, ctx.context, ctx.isolate, "abort") catch null;
            if (abort_val) |av| {
                if (av.isFunction()) {
                    const abort_fn = js.asFunction(av);
                    var abort_args: [1]v8.Value = .{reason};
                    _ = abort_fn.call(ctx.context, sv, &abort_args);
                }
            }
        }
    }

    // Return resolved promise
    const resolver = v8.PromiseResolver.init(ctx.context);
    _ = resolver.resolve(ctx.context, js.undefined_(ctx.isolate).toValue());
    js.ret(ctx, resolver.getPromise());
}

// ============================================================================
// WritableStreamDefaultController Implementation
// ============================================================================

fn controllerConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    // Store reference to stream
    if (ctx.argc() >= 1) {
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_stream", ctx.arg(0));
    }
}

fn controllerError(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const reason = if (ctx.argc() >= 1) ctx.arg(0) else js.undefined_(ctx.isolate).toValue();

    // Get stream
    const stream_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_stream") catch {
        return;
    };

    if (!stream_val.isObject()) {
        return;
    }

    const stream = js.asObject(stream_val);

    // Transition stream to errored state
    _ = js.setProp(stream, ctx.context, ctx.isolate, "_state", js.string(ctx.isolate, "errored"));

    // Reject all pending writes
    const queue_val = js.getProp(stream, ctx.context, ctx.isolate, "_queue") catch {
        return;
    };

    if (queue_val.isArray()) {
        const queue = js.asArray(queue_val);
        const len = queue.length();

        var i: u32 = 0;
        while (i < len) : (i += 1) {
            const item_val = js.getIndex(queue.castTo(v8.Object), ctx.context, i) catch continue;
            if (item_val.isObject()) {
                const item = js.asObject(item_val);
                const resolver_val = js.getProp(item, ctx.context, ctx.isolate, "resolver") catch continue;
                if (resolver_val.isObject()) {
                    const resolver = v8.PromiseResolver{ .handle = @ptrCast(resolver_val.handle) };
                    _ = resolver.reject(ctx.context, reason);
                }
            }
        }

        // Clear queue
        _ = js.setProp(stream, ctx.context, ctx.isolate, "_queue", js.array(ctx.isolate, 0));
        _ = js.setProp(stream, ctx.context, ctx.isolate, "_queueByteSize", js.number(ctx.isolate, 0));
    }
}

// ============================================================================
// WritableStreamDefaultWriter Implementation
// ============================================================================

fn writerConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) {
        js.throw(ctx.isolate, "WritableStreamDefaultWriter requires a WritableStream");
        return;
    }

    const stream_arg = ctx.arg(0);
    if (!stream_arg.isObject()) {
        js.throw(ctx.isolate, "WritableStreamDefaultWriter requires a WritableStream");
        return;
    }

    const stream = js.asObject(stream_arg);

    // Check if stream is already locked
    const writer_val = js.getProp(stream, ctx.context, ctx.isolate, "_writer") catch {
        js.throw(ctx.isolate, "Failed to get writer state");
        return;
    };

    if (!writer_val.isNull() and !writer_val.isUndefined()) {
        js.throw(ctx.isolate, "TypeError: WritableStream is locked");
        return;
    }

    // Lock the stream
    _ = js.setProp(stream, ctx.context, ctx.isolate, "_writer", ctx.this);
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_stream", stream_arg);

    // Create closed promise (pending initially)
    const closed_resolver = v8.PromiseResolver.init(ctx.context);
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_closedPromise", closed_resolver.getPromise());
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_closedResolver", js.objToValue(v8.Object{ .handle = @ptrCast(closed_resolver.handle) }));

    // Create ready promise (resolved initially)
    const ready_resolver = v8.PromiseResolver.init(ctx.context);
    _ = ready_resolver.resolve(ctx.context, js.undefined_(ctx.isolate).toValue());
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_readyPromise", ready_resolver.getPromise());
}

fn writerReadyGetter(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const ready_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_readyPromise") catch {
        const resolver = v8.PromiseResolver.init(ctx.context);
        _ = resolver.resolve(ctx.context, js.undefined_(ctx.isolate).toValue());
        js.ret(ctx, resolver.getPromise());
        return;
    };

    js.ret(ctx, ready_val);
}

fn writerClosedGetter(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const closed_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_closedPromise") catch {
        const resolver = v8.PromiseResolver.init(ctx.context);
        js.ret(ctx, resolver.getPromise());
        return;
    };

    js.ret(ctx, closed_val);
}

fn writerDesiredSizeGetter(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const stream_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_stream") catch {
        js.retNumber(ctx, 1);
        return;
    };

    if (!stream_val.isObject()) {
        js.retNumber(ctx, 1);
        return;
    }

    const stream = js.asObject(stream_val);

    const hwm_val = js.getProp(stream, ctx.context, ctx.isolate, "_highWaterMark") catch {
        js.retNumber(ctx, 1);
        return;
    };

    const queue_val = js.getProp(stream, ctx.context, ctx.isolate, "_queue") catch {
        js.retNumber(ctx, 1);
        return;
    };

    const hwm = if (hwm_val.isNumber()) hwm_val.toF64(ctx.context) catch 1.0 else 1.0;
    const queue_len = if (queue_val.isArray()) @as(f64, @floatFromInt(js.asArray(queue_val).length())) else 0.0;

    js.retNumber(ctx, hwm - queue_len);
}

fn writerWrite(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const stream_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_stream") catch {
        js.throw(ctx.isolate, "Writer not attached to stream");
        return;
    };

    if (!stream_val.isObject()) {
        js.throw(ctx.isolate, "Writer not attached to stream");
        return;
    }

    const stream = js.asObject(stream_val);

    // Check stream state
    const state_val = js.getProp(stream, ctx.context, ctx.isolate, "_state") catch {
        js.throw(ctx.isolate, "Failed to get stream state");
        return;
    };

    var state_buf: [32]u8 = undefined;
    const state_str = js.readValue(ctx, state_val, &state_buf) orelse "writable";

    if (std.mem.eql(u8, state_str, "closed")) {
        js.throw(ctx.isolate, "TypeError: Cannot write to a closed stream");
        return;
    }

    if (std.mem.eql(u8, state_str, "errored")) {
        js.throw(ctx.isolate, "TypeError: Cannot write to an errored stream");
        return;
    }

    // Get chunk
    const chunk = if (ctx.argc() >= 1) ctx.arg(0) else js.undefined_(ctx.isolate).toValue();

    // Calculate chunk size
    const chunk_size = calculateChunkSize(ctx, chunk);

    // Check buffer size limit
    const current_size_val = js.getProp(stream, ctx.context, ctx.isolate, "_queueByteSize") catch {
        js.throw(ctx.isolate, "Failed to get queue byte size");
        return;
    };
    const current_size = if (current_size_val.isNumber()) @as(usize, @intFromFloat(current_size_val.toF64(ctx.context) catch 1.0)) else 0;

    const max_buffer_val = js.getProp(stream, ctx.context, ctx.isolate, "_maxBufferSize") catch {
        js.throw(ctx.isolate, "Failed to get max buffer size");
        return;
    };
    const max_buffer = if (max_buffer_val.isNumber()) @as(usize, @intFromFloat(max_buffer_val.toF64(ctx.context) catch 1.0)) else global_max_buffer_size;

    if (current_size + chunk_size > max_buffer) {
        const max_mb = @as(f64, @floatFromInt(max_buffer)) / (1024.0 * 1024.0);
        var err_msg_buf: [256]u8 = undefined;
        const err_msg = std.fmt.bufPrint(&err_msg_buf, "Stream buffer size limit exceeded (max: {d:.1}MB)", .{max_mb}) catch "Stream buffer size limit exceeded";

        // Create rejected promise
        const resolver = v8.PromiseResolver.init(ctx.context);
        _ = resolver.reject(ctx.context, js.string(ctx.isolate, err_msg).toValue());
        js.ret(ctx, resolver.getPromise());
        return;
    }

    // Create promise for this write
    const resolver = v8.PromiseResolver.init(ctx.context);
    const promise = resolver.getPromise();

    // Add to queue
    const queue_val = js.getProp(stream, ctx.context, ctx.isolate, "_queue") catch {
        js.throw(ctx.isolate, "Failed to get queue");
        return;
    };

    const queue = if (queue_val.isArray()) js.asArray(queue_val) else js.array(ctx.isolate, 0);

    const queue_item = js.object(ctx.isolate, ctx.context);
    _ = js.setProp(queue_item, ctx.context, ctx.isolate, "chunk", chunk);
    _ = js.setProp(queue_item, ctx.context, ctx.isolate, "resolver", js.objToValue(v8.Object{ .handle = @ptrCast(resolver.handle) }));
    _ = js.setProp(queue_item, ctx.context, ctx.isolate, "size", js.number(ctx.isolate, chunk_size));

    const new_len = queue.length();
    _ = js.setIndex(queue.castTo(v8.Object), ctx.context, new_len, js.objToValue(queue_item));

    // Update queue byte size
    _ = js.setProp(stream, ctx.context, ctx.isolate, "_queueByteSize", js.number(ctx.isolate, current_size + chunk_size));

    // Update ready promise if backpressure
    const hwm_val = js.getProp(stream, ctx.context, ctx.isolate, "_highWaterMark") catch {
        js.throw(ctx.isolate, "Failed to get high water mark");
        return;
    };
    const hwm = if (hwm_val.isNumber()) hwm_val.toF64(ctx.context) catch 1.0 else 1.0;
    const queue_len = @as(f64, @floatFromInt(queue.length()));

    if (queue_len > hwm) {
        // Create pending ready promise
        const new_ready_resolver = v8.PromiseResolver.init(ctx.context);
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_readyPromise", new_ready_resolver.getPromise());
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_readyResolver", js.objToValue(v8.Object{ .handle = @ptrCast(new_ready_resolver.handle) }));
    }

    // Process queue if not already writing
    const writing_val = js.getProp(stream, ctx.context, ctx.isolate, "_writing") catch {
        js.throw(ctx.isolate, "Failed to get writing state");
        return;
    };

    const writing = if (writing_val.isBoolean()) writing_val.isTrue() else false;

    if (!writing) {
        processWriteQueue(ctx.isolate, ctx.context, stream);
    }

    js.ret(ctx, promise);
}

fn calculateChunkSize(ctx: js.CallbackContext, chunk: v8.Value) usize {
    // For strings: byte length in UTF-8
    if (chunk.isString()) {
        const str = chunk.toString(ctx.context) catch return 1024;
        return str.lenUtf8(ctx.isolate);
    }

    // For Uint8Array/ArrayBuffer: byteLength
    if (chunk.isArrayBufferView()) {
        const view = js.asArrayBufferView(chunk);
        return view.getByteLength();
    }

    if (chunk.isArrayBuffer()) {
        const buf = js.asArrayBuffer(chunk);
        return buf.getByteLength();
    }

    // For other objects: estimate as 1KB
    return 1024;
}

fn processWriteQueue(isolate: v8.Isolate, context: v8.Context, stream: v8.Object) void {
    const queue_val = js.getProp(stream, context, isolate, "_queue") catch return;
    if (!queue_val.isArray()) return;

    const queue = js.asArray(queue_val);
    if (queue.length() == 0) return;

    // Mark as writing
    _ = js.setProp(stream, context, isolate, "_writing", js.boolean(isolate, true));

    // Get first item
    const item_val = js.getIndex(queue.castTo(v8.Object), context, 0) catch {
        _ = js.setProp(stream, context, isolate, "_writing", js.boolean(isolate, false));
        return;
    };

    if (!item_val.isObject()) {
        _ = js.setProp(stream, context, isolate, "_writing", js.boolean(isolate, false));
        return;
    }

    const item = js.asObject(item_val);
    const chunk = js.getProp(item, context, isolate, "chunk") catch {
        _ = js.setProp(stream, context, isolate, "_writing", js.boolean(isolate, false));
        return;
    };

    const resolver_val = js.getProp(item, context, isolate, "resolver") catch {
        _ = js.setProp(stream, context, isolate, "_writing", js.boolean(isolate, false));
        return;
    };

    const chunk_size_val = js.getProp(item, context, isolate, "size") catch {
        _ = js.setProp(stream, context, isolate, "_writing", js.boolean(isolate, false));
        return;
    };
    const chunk_size = if (chunk_size_val.isNumber()) @as(usize, @intFromFloat(chunk_size_val.toF64(context) catch 1.0)) else 0;

    // Get sink and call write callback
    const sink_val = js.getProp(stream, context, isolate, "_underlyingSink") catch null;
    if (sink_val) |sv| {
        if (sv.isObject()) {
            const sink = js.asObject(sv);
            const write_val = js.getProp(sink, context, isolate, "write") catch null;
            if (write_val) |wv| {
                if (wv.isFunction()) {
                    const write_fn = js.asFunction(wv);
                    const controller_val = js.getProp(stream, context, isolate, "_controller") catch {
                        _ = js.setProp(stream, context, isolate, "_writing", js.boolean(isolate, false));
                        return;
                    };

                    var write_args: [2]v8.Value = .{ chunk, controller_val };

                    // Set up try-catch for sink errors
                    var try_catch: v8.TryCatch = undefined;
                    try_catch.init(isolate);
                    defer try_catch.deinit();

                    _ = write_fn.call(context, sv, &write_args);

                    if (try_catch.hasCaught()) {
                        // Sink threw an error - transition to errored state
                        _ = js.setProp(stream, context, isolate, "_state", js.string(isolate, "errored"));

                        const exception = try_catch.getException() orelse js.string(isolate, "Write error").toValue();
                        const resolver = v8.PromiseResolver{ .handle = @ptrCast(resolver_val.handle) };
                        _ = resolver.reject(context, exception);

                        _ = js.setProp(stream, context, isolate, "_writing", js.boolean(isolate, false));
                        return;
                    }
                }
            }
        }
    }

    // Resolve this write's promise
    const resolver = v8.PromiseResolver{ .handle = @ptrCast(resolver_val.handle) };
    _ = resolver.resolve(context, js.undefined_(isolate).toValue());

    // Remove from queue
    const new_queue = js.array(isolate, 0);
    var i: u32 = 1;
    while (i < queue.length()) : (i += 1) {
        const elem = js.getIndex(queue.castTo(v8.Object), context, i) catch continue;
        _ = js.setIndex(new_queue.castTo(v8.Object), context, i - 1, elem);
    }
    _ = js.setProp(stream, context, isolate, "_queue", new_queue);

    // Update queue byte size
    const current_size_val = js.getProp(stream, context, isolate, "_queueByteSize") catch {
        _ = js.setProp(stream, context, isolate, "_writing", js.boolean(isolate, false));
        return;
    };
    const current_size = if (current_size_val.isNumber()) @as(usize, @intFromFloat(current_size_val.toF64(context) catch 1.0)) else 0;
    const new_size = if (current_size >= chunk_size) current_size - chunk_size else 0;
    _ = js.setProp(stream, context, isolate, "_queueByteSize", js.number(isolate, new_size));

    // Check if ready promise should resolve
    const hwm_val = js.getProp(stream, context, isolate, "_highWaterMark") catch {
        _ = js.setProp(stream, context, isolate, "_writing", js.boolean(isolate, false));
        return;
    };
    const hwm = if (hwm_val.isNumber()) hwm_val.toF64(context) catch 1.0 else 1.0;
    const new_queue_len = @as(f64, @floatFromInt(new_queue.length()));

    if (new_queue_len <= hwm) {
        // Resolve ready promise if pending
        const ready_resolver_val = js.getProp(stream, context, isolate, "_readyResolver") catch null;
        if (ready_resolver_val) |rrv| {
            if (rrv.isObject()) {
                const ready_resolver = v8.PromiseResolver{ .handle = @ptrCast(rrv.handle) };
                _ = ready_resolver.resolve(context, js.undefined_(isolate).toValue());
            }
        }
    }

    // Mark as not writing
    _ = js.setProp(stream, context, isolate, "_writing", js.boolean(isolate, false));

    // Process next item if queue not empty
    if (new_queue.length() > 0) {
        processWriteQueue(isolate, context, stream);
    } else {
        // Queue is empty - check if close was requested while writes were pending
        const close_requested_val = js.getProp(stream, context, isolate, "_closeRequested") catch null;
        if (close_requested_val) |crv| {
            if (crv.isBoolean() and crv.isTrue()) {
                const close_resolver_val = js.getProp(stream, context, isolate, "_closeResolver") catch null;
                if (close_resolver_val) |csv| {
                    if (csv.isObject()) {
                        const close_resolver = v8.PromiseResolver{ .handle = @ptrCast(csv.handle) };
                        finishClose(isolate, context, stream, close_resolver);
                    }
                }
            }
        }
    }
}

fn writerClose(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const stream_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_stream") catch {
        js.throw(ctx.isolate, "Writer not attached to stream");
        return;
    };

    if (!stream_val.isObject()) {
        js.throw(ctx.isolate, "Writer not attached to stream");
        return;
    }

    const stream = js.asObject(stream_val);

    // Mark close requested
    _ = js.setProp(stream, ctx.context, ctx.isolate, "_closeRequested", js.boolean(ctx.isolate, true));

    // Create close promise
    const resolver = v8.PromiseResolver.init(ctx.context);
    const promise = resolver.getPromise();

    // Wait for queue to empty, then close
    const queue_val = js.getProp(stream, ctx.context, ctx.isolate, "_queue") catch {
        js.throw(ctx.isolate, "Failed to get queue");
        return;
    };

    const queue_len = if (queue_val.isArray()) js.asArray(queue_val).length() else 0;

    if (queue_len == 0) {
        // Queue is empty, close immediately
        finishClose(ctx.isolate, ctx.context, stream, resolver);
    } else {
        // Store resolver to call after queue drains
        _ = js.setProp(stream, ctx.context, ctx.isolate, "_closeResolver", js.objToValue(v8.Object{ .handle = @ptrCast(resolver.handle) }));

        // Process queue (it will call finishClose when empty)
        const writing_val = js.getProp(stream, ctx.context, ctx.isolate, "_writing") catch {
            js.throw(ctx.isolate, "Failed to get writing state");
            return;
        };

        const writing = if (writing_val.isBoolean()) writing_val.isTrue() else false;

        if (!writing) {
            processWriteQueue(ctx.isolate, ctx.context, stream);
        }
    }

    js.ret(ctx, promise);
}

fn finishClose(isolate: v8.Isolate, context: v8.Context, stream: v8.Object, resolver: v8.PromiseResolver) void {
    // Transition to closed state
    _ = js.setProp(stream, context, isolate, "_state", js.string(isolate, "closed"));

    // Call close callback if provided
    const sink_val = js.getProp(stream, context, isolate, "_underlyingSink") catch null;
    if (sink_val) |sv| {
        if (sv.isObject()) {
            const sink = js.asObject(sv);
            const close_val = js.getProp(sink, context, isolate, "close") catch null;
            if (close_val) |cv| {
                if (cv.isFunction()) {
                    const close_fn = js.asFunction(cv);
                    var close_args: [0]v8.Value = .{};
                    _ = close_fn.call(context, sv, &close_args);
                }
            }
        }
    }

    // Resolve close promise
    _ = resolver.resolve(context, js.undefined_(isolate).toValue());

    // Resolve closed promise
    const writer_val = js.getProp(stream, context, isolate, "_writer") catch null;
    if (writer_val) |wv| {
        if (wv.isObject()) {
            const writer = js.asObject(wv);
            const closed_resolver_val = js.getProp(writer, context, isolate, "_closedResolver") catch null;
            if (closed_resolver_val) |crv| {
                if (crv.isObject()) {
                    const closed_resolver = v8.PromiseResolver{ .handle = @ptrCast(crv.handle) };
                    _ = closed_resolver.resolve(context, js.undefined_(isolate).toValue());
                }
            }
        }
    }
}

fn writerAbort(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const stream_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_stream") catch {
        js.throw(ctx.isolate, "Writer not attached to stream");
        return;
    };

    if (!stream_val.isObject()) {
        js.throw(ctx.isolate, "Writer not attached to stream");
        return;
    }

    const stream = js.asObject(stream_val);

    const reason = if (ctx.argc() >= 1) ctx.arg(0) else js.undefined_(ctx.isolate).toValue();

    // Call stream's abort method
    const abort_val = js.getProp(stream, ctx.context, ctx.isolate, "abort") catch {
        js.throw(ctx.isolate, "Failed to get abort method");
        return;
    };

    if (abort_val.isFunction()) {
        const abort_fn = js.asFunction(abort_val);
        var abort_args: [1]v8.Value = .{reason};
        const result = abort_fn.call(ctx.context, js.objToValue(stream), &abort_args) orelse {
            js.throw(ctx.isolate, "Abort failed");
            return;
        };
        js.ret(ctx, result);
    } else {
        const resolver = v8.PromiseResolver.init(ctx.context);
        _ = resolver.resolve(ctx.context, js.undefined_(ctx.isolate).toValue());
        js.ret(ctx, resolver.getPromise());
    }

    // Release lock on both sides
    _ = js.setProp(stream, ctx.context, ctx.isolate, "_writer", js.null_(ctx.isolate));
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_stream", js.null_(ctx.isolate).toValue());
}

fn writerReleaseLock(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const stream_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_stream") catch {
        return;
    };

    if (!stream_val.isObject()) {
        return;
    }

    const stream = js.asObject(stream_val);

    // Release lock on both sides
    _ = js.setProp(stream, ctx.context, ctx.isolate, "_writer", js.null_(ctx.isolate));
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_stream", js.null_(ctx.isolate).toValue());
}
