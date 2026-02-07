const std = @import("std");
const v8 = @import("v8");
const js = @import("js");

/// Register TransformStream, TextEncoderStream, and TextDecoderStream APIs
pub fn registerTransformStreamAPI(isolate: v8.Isolate, context: v8.Context) void {
    const global = context.getGlobal();

    // Register TransformStream constructor
    const stream_tmpl = v8.FunctionTemplate.initCallback(isolate, transformStreamConstructor);
    const stream_proto = stream_tmpl.getPrototypeTemplate();

    // Add readable and writable getters
    const readable_getter = v8.FunctionTemplate.initCallback(isolate, transformStreamReadableGetter);
    stream_proto.setAccessorGetter(
        js.string(isolate, "readable").toName(),
        readable_getter,
    );

    const writable_getter = v8.FunctionTemplate.initCallback(isolate, transformStreamWritableGetter);
    stream_proto.setAccessorGetter(
        js.string(isolate, "writable").toName(),
        writable_getter,
    );

    js.addGlobalClass(global, context, isolate, "TransformStream", stream_tmpl);

    // Register TextEncoderStream constructor
    const encoder_stream_tmpl = v8.FunctionTemplate.initCallback(isolate, textEncoderStreamConstructor);
    const encoder_stream_proto = encoder_stream_tmpl.getPrototypeTemplate();

    const encoder_readable_getter = v8.FunctionTemplate.initCallback(isolate, transformStreamReadableGetter);
    encoder_stream_proto.setAccessorGetter(
        js.string(isolate, "readable").toName(),
        encoder_readable_getter,
    );

    const encoder_writable_getter = v8.FunctionTemplate.initCallback(isolate, transformStreamWritableGetter);
    encoder_stream_proto.setAccessorGetter(
        js.string(isolate, "writable").toName(),
        encoder_writable_getter,
    );

    js.addGlobalClass(global, context, isolate, "TextEncoderStream", encoder_stream_tmpl);

    // Register TextDecoderStream constructor
    const decoder_stream_tmpl = v8.FunctionTemplate.initCallback(isolate, textDecoderStreamConstructor);
    const decoder_stream_proto = decoder_stream_tmpl.getPrototypeTemplate();

    const decoder_readable_getter = v8.FunctionTemplate.initCallback(isolate, transformStreamReadableGetter);
    decoder_stream_proto.setAccessorGetter(
        js.string(isolate, "readable").toName(),
        decoder_readable_getter,
    );

    const decoder_writable_getter = v8.FunctionTemplate.initCallback(isolate, transformStreamWritableGetter);
    decoder_stream_proto.setAccessorGetter(
        js.string(isolate, "writable").toName(),
        decoder_writable_getter,
    );

    js.addGlobalClass(global, context, isolate, "TextDecoderStream", decoder_stream_tmpl);
}

// ============================================================================
// TransformStream Implementation
// ============================================================================

fn transformStreamConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    // Build JavaScript code to create the transform stream
    // This approach lets us reuse existing ReadableStream/WritableStream constructors
    // without having to replicate all the complex state machine logic in Zig

    // Store transformer, writableStrategy, readableStrategy for later use
    if (ctx.argc() >= 1) {
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_transformer", ctx.arg(0));
    } else {
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_transformer", js.object(ctx.isolate, ctx.context).toValue());
    }

    if (ctx.argc() >= 2) {
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_writableStrategy", ctx.arg(1));
    } else {
        const default_strategy = js.object(ctx.isolate, ctx.context);
        _ = js.setProp(default_strategy, ctx.context, ctx.isolate, "highWaterMark", js.number(ctx.isolate, 1.0));
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_writableStrategy", default_strategy.toValue());
    }

    if (ctx.argc() >= 3) {
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_readableStrategy", ctx.arg(2));
    } else {
        const default_strategy = js.object(ctx.isolate, ctx.context);
        _ = js.setProp(default_strategy, ctx.context, ctx.isolate, "highWaterMark", js.number(ctx.isolate, 0.0));
        _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "_readableStrategy", default_strategy.toValue());
    }

    // Execute JavaScript to create the readable/writable pair
    const setup_code =
        \\(function(transformStream, transformer, writableStrategy, readableStrategy) {
        \\  // Create controller interface
        \\  const controller = {
        \\    enqueue(chunk) {
        \\      if (transformStream._readableController) {
        \\        transformStream._readableController.enqueue(chunk);
        \\      }
        \\    },
        \\    error(e) {
        \\      if (transformStream._readableController) {
        \\        transformStream._readableController.error(e);
        \\      }
        \\    },
        \\    terminate() {
        \\      if (transformStream._readableController) {
        \\        transformStream._readableController.close();
        \\      }
        \\    }
        \\  };
        \\
        \\  // Create readable stream
        \\  transformStream._readable = new ReadableStream({
        \\    start(readableController) {
        \\      transformStream._readableController = readableController;
        \\      if (transformer.start) {
        \\        transformer.start(controller);
        \\      }
        \\    }
        \\  }, readableStrategy);
        \\
        \\  // Create writable stream
        \\  transformStream._writable = new WritableStream({
        \\    async write(chunk) {
        \\      if (transformer.transform) {
        \\        await transformer.transform(chunk, controller);
        \\      } else {
        \\        controller.enqueue(chunk);
        \\      }
        \\    },
        \\    async close() {
        \\      if (transformer.flush) {
        \\        await transformer.flush(controller);
        \\      }
        \\      transformStream._readableController.close();
        \\    },
        \\    abort(reason) {
        \\      transformStream._readableController.error(reason || new Error('Stream aborted'));
        \\    }
        \\  }, writableStrategy);
        \\})
    ;

    const setup_str = v8.String.initUtf8(ctx.isolate, setup_code);
    const setup_script = v8.Script.compile(ctx.context, setup_str, null) catch {
        js.throw(ctx.isolate, "TransformStream: failed to compile setup");
        return;
    };

    const setup_fn_val = setup_script.run(ctx.context) catch {
        js.throw(ctx.isolate, "TransformStream: failed to run setup");
        return;
    };

    if (!setup_fn_val.isFunction()) {
        js.throw(ctx.isolate, "TransformStream: setup is not a function");
        return;
    }

    const setup_fn = v8.Function{ .handle = @ptrCast(setup_fn_val.handle) };

    const transformer = js.getProp(ctx.this, ctx.context, ctx.isolate, "_transformer") catch js.object(ctx.isolate, ctx.context).toValue();
    const writable_strategy = js.getProp(ctx.this, ctx.context, ctx.isolate, "_writableStrategy") catch js.object(ctx.isolate, ctx.context).toValue();
    const readable_strategy = js.getProp(ctx.this, ctx.context, ctx.isolate, "_readableStrategy") catch js.object(ctx.isolate, ctx.context).toValue();

    var args = [_]v8.Value{ ctx.this.toValue(), transformer, writable_strategy, readable_strategy };
    _ = setup_fn.call(ctx.context, ctx.this.toValue(), &args);
}

fn transformStreamReadableGetter(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);
    const readable = js.getProp(ctx.this, ctx.context, ctx.isolate, "_readable") catch {
        js.retUndefined(ctx);
        return;
    };
    js.ret(ctx, readable);
}

fn transformStreamWritableGetter(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);
    const writable = js.getProp(ctx.this, ctx.context, ctx.isolate, "_writable") catch {
        js.retUndefined(ctx);
        return;
    };
    js.ret(ctx, writable);
}

// ============================================================================
// TextEncoderStream Implementation
// ============================================================================

fn textEncoderStreamConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    // Create a TransformStream with text encoding transformer
    const setup_code =
        \\(function(stream) {
        \\  const transformer = {
        \\    transform(chunk, controller) {
        \\      const encoder = new TextEncoder();
        \\      const encoded = encoder.encode(String(chunk));
        \\      controller.enqueue(encoded);
        \\    }
        \\  };
        \\
        \\  const writableStrategy = { highWaterMark: 1 };
        \\  const readableStrategy = { highWaterMark: 0 };
        \\
        \\  // Create readable stream
        \\  stream._readable = new ReadableStream({
        \\    start(readableController) {
        \\      stream._readableController = readableController;
        \\    }
        \\  }, readableStrategy);
        \\
        \\  // Create writable stream
        \\  stream._writable = new WritableStream({
        \\    write(chunk) {
        \\      const encoder = new TextEncoder();
        \\      const encoded = encoder.encode(String(chunk));
        \\      stream._readableController.enqueue(encoded);
        \\    },
        \\    close() {
        \\      stream._readableController.close();
        \\    },
        \\    abort(reason) {
        \\      stream._readableController.error(reason || new Error('Stream aborted'));
        \\    }
        \\  }, writableStrategy);
        \\})
    ;

    const setup_str = v8.String.initUtf8(ctx.isolate, setup_code);
    const setup_script = v8.Script.compile(ctx.context, setup_str, null) catch {
        js.throw(ctx.isolate, "TextEncoderStream: failed to compile");
        return;
    };

    const setup_fn_val = setup_script.run(ctx.context) catch {
        js.throw(ctx.isolate, "TextEncoderStream: failed to run");
        return;
    };

    if (!setup_fn_val.isFunction()) {
        js.throw(ctx.isolate, "TextEncoderStream: setup is not a function");
        return;
    }

    const setup_fn = v8.Function{ .handle = @ptrCast(setup_fn_val.handle) };
    var args = [_]v8.Value{ctx.this.toValue()};
    _ = setup_fn.call(ctx.context, ctx.this.toValue(), &args);

    // Set encoding property
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "encoding", js.string(ctx.isolate, "utf-8").toValue());
}

// ============================================================================
// TextDecoderStream Implementation
// ============================================================================

fn textDecoderStreamConstructor(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.c) void {
    const ctx = js.CallbackContext.init(raw_info);

    // Parse encoding argument (first argument, default utf-8)
    var encoding: []const u8 = "utf-8";
    if (ctx.argc() >= 1) {
        const encoding_arg = ctx.arg(0);
        if (encoding_arg.isString()) {
            if (encoding_arg.toString(ctx.context)) |str| {
                var buf: [32]u8 = undefined;
                const enc_str = js.readString(ctx.isolate, str, &buf);
                if (std.mem.eql(u8, enc_str, "utf-8") or std.mem.eql(u8, enc_str, "utf8")) {
                    encoding = "utf-8";
                } else {
                    js.throw(ctx.isolate, "TextDecoderStream: only utf-8 supported");
                    return;
                }
            } else |_| {
                encoding = "utf-8";
            }
        }
    }

    // Create a TransformStream with text decoding transformer
    const setup_code =
        \\(function(stream) {
        \\  const writableStrategy = { highWaterMark: 1 };
        \\  const readableStrategy = { highWaterMark: 0 };
        \\
        \\  // Create readable stream
        \\  stream._readable = new ReadableStream({
        \\    start(readableController) {
        \\      stream._readableController = readableController;
        \\    }
        \\  }, readableStrategy);
        \\
        \\  // Create writable stream with decoder
        \\  stream._writable = new WritableStream({
        \\    write(chunk) {
        \\      const decoder = new TextDecoder();
        \\      const decoded = decoder.decode(chunk, { stream: true });
        \\      if (decoded.length > 0) {
        \\        stream._readableController.enqueue(decoded);
        \\      }
        \\    },
        \\    close() {
        \\      // Flush any remaining bytes
        \\      const decoder = new TextDecoder();
        \\      const decoded = decoder.decode(new Uint8Array(0));
        \\      if (decoded.length > 0) {
        \\        stream._readableController.enqueue(decoded);
        \\      }
        \\      stream._readableController.close();
        \\    },
        \\    abort(reason) {
        \\      stream._readableController.error(reason || new Error('Stream aborted'));
        \\    }
        \\  }, writableStrategy);
        \\})
    ;

    const setup_str = v8.String.initUtf8(ctx.isolate, setup_code);
    const setup_script = v8.Script.compile(ctx.context, setup_str, null) catch {
        js.throw(ctx.isolate, "TextDecoderStream: failed to compile");
        return;
    };

    const setup_fn_val = setup_script.run(ctx.context) catch {
        js.throw(ctx.isolate, "TextDecoderStream: failed to run");
        return;
    };

    if (!setup_fn_val.isFunction()) {
        js.throw(ctx.isolate, "TextDecoderStream: setup is not a function");
        return;
    }

    const setup_fn = v8.Function{ .handle = @ptrCast(setup_fn_val.handle) };
    var args = [_]v8.Value{ctx.this.toValue()};
    _ = setup_fn.call(ctx.context, ctx.this.toValue(), &args);

    // Set encoding property
    _ = js.setProp(ctx.this, ctx.context, ctx.isolate, "encoding", js.string(ctx.isolate, encoding).toValue());
}
