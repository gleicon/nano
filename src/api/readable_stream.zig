const std = @import("std");
const v8 = @import("v8");
const js = @import("js");

/// Global max buffer size (passed from app config)
var g_max_buffer_size: usize = 64 * 1024 * 1024; // Default 64MB

/// Register ReadableStream, ReadableStreamDefaultController, and ReadableStreamDefaultReader
pub fn registerReadableStreamAPI(isolate: v8.Isolate, context: v8.Context, max_buffer_size: usize) void {
    g_max_buffer_size = max_buffer_size;
    const global = context.getGlobal();

    // Create ReadableStream constructor
    const stream_tmpl = v8.FunctionTemplate.initCallback(isolate, readableStreamConstructor);
    const stream_proto = stream_tmpl.getPrototypeTemplate();

    js.addMethod(stream_proto, isolate, "getReader", readableStreamGetReader);
    js.addMethod(stream_proto, isolate, "cancel", readableStreamCancel);
    js.addMethod(stream_proto, isolate, "tee", readableStreamTee);

    // Add locked getter
    const locked_getter = v8.FunctionTemplate.initCallback(isolate, readableStreamLockedGetter);
    stream_proto.setAccessorGetter(
        js.string(isolate, "locked").toName(),
        locked_getter,
    );

    js.addGlobalClass(global, context, isolate, "ReadableStream", stream_tmpl);

    // Create ReadableStreamDefaultController constructor
    const controller_tmpl = v8.FunctionTemplate.initCallback(isolate, controllerConstructor);
    const controller_proto = controller_tmpl.getPrototypeTemplate();

    js.addMethod(controller_proto, isolate, "enqueue", controllerEnqueue);
    js.addMethod(controller_proto, isolate, "close", controllerClose);
    js.addMethod(controller_proto, isolate, "error", controllerError);

    // Add desiredSize getter
    const desired_size_getter = v8.FunctionTemplate.initCallback(isolate, controllerDesiredSizeGetter);
    controller_proto.setAccessorGetter(
        js.string(isolate, "desiredSize").toName(),
        desired_size_getter,
    );

    js.addGlobalClass(global, context, isolate, "ReadableStreamDefaultController", controller_tmpl);

    // Create ReadableStreamDefaultReader constructor
    const reader_tmpl = v8.FunctionTemplate.initCallback(isolate, readerConstructor);
    const reader_proto = reader_tmpl.getPrototypeTemplate();

    js.addMethod(reader_proto, isolate, "read", readerRead);
    js.addMethod(reader_proto, isolate, "cancel", readerCancel);
    js.addMethod(reader_proto, isolate, "releaseLock", readerReleaseLock);

    // Add closed getter (returns Promise)
    const closed_getter = v8.FunctionTemplate.initCallback(isolate, readerClosedGetter);
    reader_proto.setAccessorGetter(
        js.string(isolate, "closed").toName(),
        closed_getter,
    );

    js.addGlobalClass(global, context, isolate, "ReadableStreamDefaultReader", reader_tmpl);
}

// ============================================================================
// ReadableStream Implementation
// ============================================================================

fn readableStreamConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    // Initialize state
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_state", js.string(ctx.isolate, "readable"));
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_reader", js.null_(ctx.isolate).toValue());
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_queue", js.array(ctx.isolate, 0));
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_queueByteSize", js.number(ctx.isolate, 0));
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_closeRequested", v8.Value{ .handle = js.boolean(ctx.isolate, false).handle });
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_pulling", v8.Value{ .handle = js.boolean(ctx.isolate, false).handle });
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_pendingReads", js.array(ctx.isolate, 0));
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_maxBufferSize", js.number(ctx.isolate, @as(f64, @floatFromInt(g_max_buffer_size))));

    // Default highWaterMark
    var high_water_mark: f64 = 1.0;

    // Parse strategy argument (second argument)
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
    const controller_ctor_val = js.getProp(global, ctx.context, ctx.isolate, "ReadableStreamDefaultController") catch {
        js.throw(ctx.isolate, "ReadableStreamDefaultController not found");
        return;
    };
    const controller_ctor = js.asFunction(controller_ctor_val);
    var args: [0]v8.Value = .{};
    const controller = controller_ctor.initInstance(ctx.context, &args) orelse {
        js.throw(ctx.isolate, "Failed to create controller");
        return;
    };

    // Link controller to stream
    _ = js.setProp(controller, ctx.context, ctx.isolate, "_stream", ctx.this.toValue());
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_controller", controller.toValue());

    // Parse underlyingSource (first argument)
    if (ctx.argc() >= 1) {
        const source_arg = ctx.arg(0);
        if (source_arg.isObject()) {
            const source = js.asObject(source_arg);

            // Store callbacks
            const start_cb = js.getProp(source, ctx.context, ctx.isolate, "start") catch null;
            if (start_cb) |cb| {
                _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_startCallback", cb);
            }

            const pull_cb = js.getProp(source, ctx.context, ctx.isolate, "pull") catch null;
            if (pull_cb) |cb| {
                _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_pullCallback", cb);
            }

            const cancel_cb = js.getProp(source, ctx.context, ctx.isolate, "cancel") catch null;
            if (cancel_cb) |cb| {
                _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_cancelCallback", cb);
            }

            // Call start callback immediately if present
            if (start_cb) |cb| {
                if (cb.isFunction()) {
                    const start_fn = js.asFunction(cb);
                    var start_args: [1]v8.Value = .{controller.toValue()};
                    _ = start_fn.call(ctx.context, ctx.this.toValue(), &start_args);
                }
            }
        }
    }
}

fn readableStreamLockedGetter(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const reader_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_reader") catch {
        js.retBool(ctx, false);
        return;
    };

    js.retBool(ctx, !reader_val.isNull());
}

fn readableStreamGetReader(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    // Check if already locked
    const reader_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_reader") catch {
        js.throw(ctx.isolate, "Internal error: cannot read _reader");
        return;
    };

    if (!reader_val.isNull()) {
        js.throw(ctx.isolate, "ReadableStream is locked");
        return;
    }

    // Create reader
    const global = ctx.context.getGlobal();
    const reader_ctor_val = js.getProp(global, ctx.context, ctx.isolate, "ReadableStreamDefaultReader") catch {
        js.throw(ctx.isolate, "ReadableStreamDefaultReader not found");
        return;
    };
    const reader_ctor = js.asFunction(reader_ctor_val);
    var args: [1]v8.Value = .{ctx.this.toValue()};
    const reader = reader_ctor.initInstance(ctx.context, &args) orelse {
        js.throw(ctx.isolate, "Failed to create reader");
        return;
    };

    js.ret(ctx, reader.toValue());
}

fn readableStreamCancel(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const reason = if (ctx.argc() >= 1) ctx.arg(0) else js.undefined_(ctx.isolate).toValue();

    // Call cancel callback if present
    const cancel_cb = js.getProp(ctx.this, ctx.context, ctx.isolate, "_cancelCallback") catch null;
    if (cancel_cb) |cb| {
        if (cb.isFunction()) {
            const cancel_fn = js.asFunction(cb);
            var cancel_args: [1]v8.Value = .{reason};
            _ = cancel_fn.call(ctx.context, ctx.this.toValue(), &cancel_args);
        }
    }

    // Transition to closed state
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_state", js.string(ctx.isolate, "closed"));

    // Return resolved promise (for WHATWG compliance)
    const promise_resolver = v8.PromiseResolver.init(ctx.context);
    _ = promise_resolver.resolve(ctx.context, js.undefined_(ctx.isolate).toValue());
    js.ret(ctx, promise_resolver.getPromise());
}

fn readableStreamTee(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    // Placeholder - defer to Plan 03
    js.throw(ctx.isolate, "ReadableStream.tee() not yet implemented");
}

// ============================================================================
// ReadableStreamDefaultController Implementation
// ============================================================================

fn controllerConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    // Controller is created internally by ReadableStream
    // Store reference to stream (set by ReadableStream constructor)
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_stream", js.null_(ctx.isolate).toValue());
}

fn controllerDesiredSizeGetter(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const stream_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_stream") catch {
        js.retNumber(ctx, 0);
        return;
    };

    if (stream_val.isNull()) {
        js.retNumber(ctx, 0);
        return;
    }

    const stream = js.asObject(stream_val);

    const hwm_val = js.getProp(stream, ctx.context, ctx.isolate, "_highWaterMark") catch {
        js.retNumber(ctx, 0);
        return;
    };
    const high_water_mark = if (hwm_val.isNumber()) hwm_val.toF64(ctx.context) catch 1.0 else 1.0;

    const queue_val = js.getProp(stream, ctx.context, ctx.isolate, "_queue") catch {
        js.retNumber(ctx, high_water_mark);
        return;
    };
    const queue = js.asArray(queue_val);
    const queue_length = queue.length();

    const desired = high_water_mark - @as(f64, @floatFromInt(queue_length));
    js.retNumber(ctx, desired);
}

fn controllerEnqueue(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) {
        js.throw(ctx.isolate, "enqueue() requires a chunk argument");
        return;
    }

    const chunk = ctx.arg(0);

    const stream_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_stream") catch {
        js.throw(ctx.isolate, "Internal error: no stream reference");
        return;
    };

    if (stream_val.isNull()) {
        js.throw(ctx.isolate, "Internal error: stream is null");
        return;
    }

    const stream = js.asObject(stream_val);

    // Check state
    const state_val = js.getProp(stream, ctx.context, ctx.isolate, "_state") catch {
        js.throw(ctx.isolate, "Internal error: cannot read state");
        return;
    };
    const state_str = state_val.toString(ctx.context) catch {
        js.throw(ctx.isolate, "Internal error: invalid state");
        return;
    };
    var state_buf: [32]u8 = undefined;
    const state_len = state_str.writeUtf8(ctx.isolate, &state_buf);
    const state = state_buf[0..state_len];

    if (std.mem.eql(u8, state, "closed") or std.mem.eql(u8, state, "errored")) {
        js.throw(ctx.isolate, "Cannot enqueue into a closed stream");
        return;
    }

    // Calculate chunk size
    const chunk_size = calculateChunkSize(ctx, chunk);

    // Check buffer size limit
    const current_size_val = js.getProp(stream, ctx.context, ctx.isolate, "_queueByteSize") catch {
        js.throw(ctx.isolate, "Internal error: cannot read queue size");
        return;
    };
    const current_size = if (current_size_val.isNumber()) current_size_val.toF64(ctx.context) catch 0.0 else 0.0;

    const max_size_val = js.getProp(stream, ctx.context, ctx.isolate, "_maxBufferSize") catch {
        js.throw(ctx.isolate, "Internal error: cannot read max buffer size");
        return;
    };
    const max_size = if (max_size_val.isNumber()) max_size_val.toF64(ctx.context) catch @as(f64, @floatFromInt(g_max_buffer_size)) else @as(f64, @floatFromInt(g_max_buffer_size));

    const new_size = current_size + @as(f64, @floatFromInt(chunk_size));

    if (new_size > max_size) {
        // Error the stream immediately (hard boundary)
        const max_mb = @as(i64, @intFromFloat(max_size / (1024.0 * 1024.0)));
        const error_msg_buf = std.fmt.allocPrint(
            std.heap.page_allocator,
            "Stream buffer size limit exceeded (max: {d}MB)",
            .{max_mb}
        ) catch "Stream buffer size limit exceeded";
        defer if (!std.mem.eql(u8, error_msg_buf, "Stream buffer size limit exceeded")) {
            std.heap.page_allocator.free(error_msg_buf);
        };

        const error_obj = js.object(ctx.isolate, ctx.context);
        _ = js.setProp(error_obj, ctx.context, ctx.isolate, "message", js.string(ctx.isolate, error_msg_buf));

        // Transition to errored state
        _ = js.setProp(stream, ctx.context, ctx.isolate, "_state", js.string(ctx.isolate, "errored"));
        _ = js.setProp(stream, ctx.context, ctx.isolate, "_error", error_obj.toValue());

        // TODO: Reject pending reads (requires proper async mechanism)
        // For MVP, just throw the error
        js.throw(ctx.isolate, error_msg_buf);
        return;
    }

    // Add to queue
    const queue_val = js.getProp(stream, ctx.context, ctx.isolate, "_queue") catch {
        js.throw(ctx.isolate, "Internal error: cannot read queue");
        return;
    };
    const queue = js.asArray(queue_val);
    const queue_len = queue.length();
    _ = js.setIndex(queue.castTo(v8.Object), ctx.context, queue_len, chunk);

    // Update queue byte size
    _ = js.setProp(stream, ctx.context, ctx.isolate, "_queueByteSize", js.number(ctx.isolate, new_size));

    // TODO: Process pending reads (requires proper async mechanism)
    // For MVP, data is just added to queue and read() will find it synchronously

    js.retUndefined(ctx);
}

fn controllerClose(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const stream_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_stream") catch {
        js.throw(ctx.isolate, "Internal error: no stream reference");
        return;
    };

    if (stream_val.isNull()) {
        js.throw(ctx.isolate, "Internal error: stream is null");
        return;
    }

    const stream = js.asObject(stream_val);

    // Set close requested flag
    _ = js.setProp(stream, ctx.context, ctx.isolate, "_closeRequested", v8.Value{ .handle = js.boolean(ctx.isolate, true).handle });

    // If queue is empty, close immediately
    const queue_val = js.getProp(stream, ctx.context, ctx.isolate, "_queue") catch {
        js.retUndefined(ctx);
        return;
    };
    const queue = js.asArray(queue_val);

    if (queue.length() == 0) {
        _ = js.setProp(stream, ctx.context, ctx.isolate, "_state", js.string(ctx.isolate, "closed"));

        // TODO: Resolve pending reads with {done: true} (requires proper async mechanism)
    }

    js.retUndefined(ctx);
}

fn controllerError(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const error_val = if (ctx.argc() >= 1) ctx.arg(0) else js.undefined_(ctx.isolate).toValue();

    const stream_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_stream") catch {
        js.throw(ctx.isolate, "Internal error: no stream reference");
        return;
    };

    if (stream_val.isNull()) {
        js.throw(ctx.isolate, "Internal error: stream is null");
        return;
    }

    const stream = js.asObject(stream_val);

    // Transition to errored state
    _ = js.setProp(stream, ctx.context, ctx.isolate, "_state", js.string(ctx.isolate, "errored"));
    _ = js.setProp(stream, ctx.context, ctx.isolate, "_error", error_val);

    // Reject all pending reads
    const pending_reads_val = js.getProp(stream, ctx.context, ctx.isolate, "_pendingReads") catch {
        js.retUndefined(ctx);
        return;
    };
    // TODO: Reject pending reads (requires proper async mechanism)
    _ = pending_reads_val; // Suppress unused variable warning

    // Clear queue (buffered data is lost per WHATWG spec)
    _ = js.setProp(stream, ctx.context, ctx.isolate, "_queue", js.array(ctx.isolate, 0));
    _ = js.setProp(stream, ctx.context, ctx.isolate, "_queueByteSize", js.number(ctx.isolate, 0));

    js.retUndefined(ctx);
}

// ============================================================================
// ReadableStreamDefaultReader Implementation
// ============================================================================

fn readerConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    if (ctx.argc() < 1) {
        js.throw(ctx.isolate, "ReadableStreamDefaultReader requires a stream argument");
        return;
    }

    const stream_arg = ctx.arg(0);
    if (!stream_arg.isObject()) {
        js.throw(ctx.isolate, "Stream must be an object");
        return;
    }

    const stream = js.asObject(stream_arg);

    // Check if stream is already locked
    const existing_reader = js.getProp(stream, ctx.context, ctx.isolate, "_reader") catch {
        js.throw(ctx.isolate, "Invalid stream");
        return;
    };

    if (!existing_reader.isNull()) {
        js.throw(ctx.isolate, "ReadableStream is locked");
        return;
    }

    // Lock the stream
    _ = js.setProp(stream, ctx.context, ctx.isolate, "_reader", ctx.this.toValue());
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_stream", stream.toValue());

    // Create closed promise (will be resolved when stream closes)
    const closed_resolver = v8.PromiseResolver.init(ctx.context);
    const closed_promise = closed_resolver.getPromise();
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_closedPromise", v8.Value{ .handle = @ptrCast(closed_promise.handle) });
}

fn readerClosedGetter(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const closed_promise = js.getProp(ctx.this, ctx.context, ctx.isolate, "_closedPromise") catch {
        // Return resolved promise as fallback
        const resolver = v8.PromiseResolver.init(ctx.context);
        js.ret(ctx, resolver.getPromise());
        return;
    };

    js.ret(ctx, closed_promise);
}

fn readerRead(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const stream_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_stream") catch {
        js.throw(ctx.isolate, "Internal error: no stream reference");
        return;
    };

    if (stream_val.isNull()) {
        js.throw(ctx.isolate, "Reader is not locked to a stream");
        return;
    }

    const stream = js.asObject(stream_val);

    // Check state
    const state_val = js.getProp(stream, ctx.context, ctx.isolate, "_state") catch {
        js.throw(ctx.isolate, "Internal error: cannot read state");
        return;
    };
    const state_str = state_val.toString(ctx.context) catch {
        js.throw(ctx.isolate, "Internal error: invalid state");
        return;
    };
    var state_buf: [32]u8 = undefined;
    const state_len = state_str.writeUtf8(ctx.isolate, &state_buf);
    const state = state_buf[0..state_len];

    // If errored, reject immediately
    if (std.mem.eql(u8, state, "errored")) {
        const error_val = js.getProp(stream, ctx.context, ctx.isolate, "_error") catch js.undefined_(ctx.isolate).toValue();
        const resolver = v8.PromiseResolver.init(ctx.context);
        _ = resolver.reject(ctx.context, error_val);
        js.ret(ctx, resolver.getPromise());
        return;
    }

    // Check if queue has data
    const queue_val = js.getProp(stream, ctx.context, ctx.isolate, "_queue") catch {
        js.throw(ctx.isolate, "Internal error: cannot read queue");
        return;
    };
    const queue = js.asArray(queue_val);
    const queue_len = queue.length();

    if (queue_len > 0) {
        // Dequeue chunk
        const chunk = js.getIndex(queue.castTo(v8.Object), ctx.context, 0) catch {
            js.throw(ctx.isolate, "Internal error: cannot dequeue");
            return;
        };

        // Calculate dequeued chunk size
        const chunk_size = calculateChunkSize(ctx, chunk);

        // Update queue byte size
        const current_size_val = js.getProp(stream, ctx.context, ctx.isolate, "_queueByteSize") catch {
            js.throw(ctx.isolate, "Internal error: cannot read queue size");
            return;
        };
        const current_size = if (current_size_val.isNumber()) current_size_val.toF64(ctx.context) catch 0.0 else 0.0;
        const new_size = current_size - @as(f64, @floatFromInt(chunk_size));
        _ = js.setProp(stream, ctx.context, ctx.isolate, "_queueByteSize", js.number(ctx.isolate, new_size));

        // Shift queue
        const new_queue = js.array(ctx.isolate, queue_len - 1);
        var i: u32 = 1;
        while (i < queue_len) : (i += 1) {
            const elem = js.getIndex(queue.castTo(v8.Object), ctx.context, i) catch continue;
            _ = js.setIndex(new_queue.castTo(v8.Object), ctx.context, i - 1, elem);
        }
        _ = js.setProp(stream, ctx.context, ctx.isolate, "_queue", new_queue);

        // Check if we should close after this read
        const close_requested_val = js.getProp(stream, ctx.context, ctx.isolate, "_closeRequested") catch {
            // Return chunk even if we can't check close status
            const result = js.object(ctx.isolate, ctx.context);
            _ = js.setProp(result, ctx.context, ctx.isolate, "value", chunk);
            _ = js.setProp(result, ctx.context, ctx.isolate, "done", v8.Value{ .handle = js.boolean(ctx.isolate, false).handle });
            const resolver = v8.PromiseResolver.init(ctx.context);
            js.ret(ctx, resolver.getPromise());
            return;
        };

        const close_requested = if (close_requested_val.isBoolean()) close_requested_val.toBool(ctx.isolate) else false;

        if (close_requested and new_queue.length() == 0) {
            // Close the stream now
            _ = js.setProp(stream, ctx.context, ctx.isolate, "_state", js.string(ctx.isolate, "closed"));
            // Note: closed promise resolution deferred to full WHATWG implementation
        }

        // Return {value: chunk, done: false}
        const result = js.object(ctx.isolate, ctx.context);
        _ = js.setProp(result, ctx.context, ctx.isolate, "value", chunk);
        _ = js.setProp(result, ctx.context, ctx.isolate, "done", v8.Value{ .handle = js.boolean(ctx.isolate, false).handle });

        const resolver = v8.PromiseResolver.init(ctx.context);
        js.ret(ctx, resolver.getPromise());
        return;
    }

    // If closed, return {done: true}
    if (std.mem.eql(u8, state, "closed")) {
        const result = js.object(ctx.isolate, ctx.context);
        _ = js.setProp(result, ctx.context, ctx.isolate, "value", js.undefined_(ctx.isolate).toValue());
        _ = js.setProp(result, ctx.context, ctx.isolate, "done", v8.Value{ .handle = js.boolean(ctx.isolate, true).handle });

        const resolver = v8.PromiseResolver.init(ctx.context);
        js.ret(ctx, resolver.getPromise());
        return;
    }

    // Queue is empty and stream not closed - call pull callback and wait
    const pull_cb = js.getProp(stream, ctx.context, ctx.isolate, "_pullCallback") catch null;
    if (pull_cb) |cb| {
        if (cb.isFunction()) {
            const controller_val = js.getProp(stream, ctx.context, ctx.isolate, "_controller") catch {
                js.throw(ctx.isolate, "Internal error: no controller");
                return;
            };

            const pull_fn = js.asFunction(cb);
            var pull_args: [1]v8.Value = .{controller_val};
            _ = pull_fn.call(ctx.context, stream.toValue(), &pull_args);
        }
    }

    // For MVP: return rejected promise when no data available
    // TODO: Implement proper async pending reads mechanism
    const resolver = v8.PromiseResolver.init(ctx.context);
    const error_msg = js.string(ctx.isolate, "No data available - pull callback should enqueue data");
    _ = resolver.reject(ctx.context, error_msg.toValue());
    js.ret(ctx, resolver.getPromise());
}

fn readerCancel(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const stream_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_stream") catch {
        js.throw(ctx.isolate, "Internal error: no stream reference");
        return;
    };

    if (stream_val.isNull()) {
        js.throw(ctx.isolate, "Reader is not locked to a stream");
        return;
    }

    const stream = js.asObject(stream_val);

    const reason = if (ctx.argc() >= 1) ctx.arg(0) else js.undefined_(ctx.isolate).toValue();

    // Call stream.cancel()
    const cancel_method = js.getProp(stream, ctx.context, ctx.isolate, "cancel") catch {
        js.retUndefined(ctx);
        return;
    };

    if (cancel_method.isFunction()) {
        const cancel_fn = js.asFunction(cancel_method);
        var cancel_args: [1]v8.Value = .{reason};
        const result = cancel_fn.call(ctx.context, stream.toValue(), &cancel_args) orelse {
            js.retUndefined(ctx);
            return;
        };

        // Release lock
        _ = js.setProp(stream, ctx.context, ctx.isolate, "_reader", js.null_(ctx.isolate).toValue());
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_stream", js.null_(ctx.isolate).toValue());

        js.ret(ctx, result);
    } else {
        js.retUndefined(ctx);
    }
}

fn readerReleaseLock(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    const stream_val = js.getProp(ctx.this, ctx.context, ctx.isolate, "_stream") catch {
        js.retUndefined(ctx);
        return;
    };

    if (!stream_val.isNull()) {
        const stream = js.asObject(stream_val);
        _ = js.setProp(stream, ctx.context, ctx.isolate, "_reader", js.null_(ctx.isolate).toValue());
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_stream", js.null_(ctx.isolate).toValue());
    }

    js.retUndefined(ctx);
}

// ============================================================================
// Helper Functions
// ============================================================================

fn calculateChunkSize(ctx: js.CallbackContext, chunk: v8.Value) usize {
    if (chunk.isString()) {
        // UTF-8 byte length
        const str = chunk.toString(ctx.context) catch return 0;
        return str.lenUtf8(ctx.isolate);
    } else if (chunk.isArrayBuffer() or chunk.isTypedArray()) {
        // For typed arrays, get byteLength
        const obj = js.asObject(chunk);
        const byte_length_val = js.getProp(obj, ctx.context, ctx.isolate, "byteLength") catch return 0;
        if (byte_length_val.isNumber()) {
            const byte_length = byte_length_val.toF64(ctx.context) catch 0.0;
            return @intFromFloat(byte_length);
        }
        return 0;
    } else {
        // Conservative estimate for other objects
        return 1024;
    }
}
