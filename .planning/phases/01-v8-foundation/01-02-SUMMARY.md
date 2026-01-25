# Plan 01-02 Summary: Script Execution with Error Handling

## What Was Built
- `src/engine/error.zig` - ScriptError struct + extractError from V8 TryCatch
- `src/engine/script.zig` - runScript function with full V8 lifecycle

## Key Patterns

### Isolate Lifecycle (script.zig:29-55)
```zig
var params = v8.initCreateParams();
params.array_buffer_allocator = v8.createDefaultArrayBufferAllocator();
var isolate = v8.Isolate.init(&params);
isolate.enter();
var handle_scope: v8.HandleScope = undefined;
handle_scope.init(isolate);
var context = v8.Context.init(isolate, null, null);
context.enter();
```

### Error Extraction (error.zig:35-78)
```zig
const message = try_catch.getMessage();
const msg_str = message.getMessage();
const line = message.getLineNumber(context);
const column = message.getStartColumn();
```

### String Conversion
```zig
// Zig -> V8
v8.String.initUtf8(isolate, source)

// V8 -> Zig
const len = result_str.lenUtf8(isolate);
result_str.writeUtf8(isolate, buffer);
```

## ScriptResult Union
```zig
pub const ScriptResult = union(enum) {
    ok: []const u8,
    err: ScriptError,
    pub fn deinit(...) // cleanup
};
```

## Tests Included
- eval simple expression ("1 + 1" -> "2")
- eval string concatenation
- eval math function
- syntax error returns line number
- reference error handling

## Status
Complete - JavaScript execution working with proper error messages.
