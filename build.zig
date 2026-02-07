const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get v8 dependency
    const v8_dep = b.dependency("v8", .{
        .target = target,
        .optimize = optimize,
    });

    const v8_module = v8_dep.module("v8");

    // Get libxev dependency
    const xev_dep = b.dependency("libxev", .{
        .target = target,
        .optimize = optimize,
    });
    const xev_module = xev_dep.module("xev");

    // Create js helper module
    const js_module = b.createModule(.{
        .root_source_file = b.path("src/js.zig"),
        .target = target,
        .optimize = optimize,
    });
    js_module.addImport("v8", v8_module);

    // Create api/console module
    const console_module = b.createModule(.{
        .root_source_file = b.path("src/api/console.zig"),
        .target = target,
        .optimize = optimize,
    });
    console_module.addImport("v8", v8_module);
    console_module.addImport("js", js_module);

    // Create api/encoding module
    const encoding_module = b.createModule(.{
        .root_source_file = b.path("src/api/encoding.zig"),
        .target = target,
        .optimize = optimize,
    });
    encoding_module.addImport("v8", v8_module);
    encoding_module.addImport("js", js_module);

    // Create api/url module
    const url_module = b.createModule(.{
        .root_source_file = b.path("src/api/url.zig"),
        .target = target,
        .optimize = optimize,
    });
    url_module.addImport("v8", v8_module);
    url_module.addImport("js", js_module);

    // Create api/crypto module
    const crypto_module = b.createModule(.{
        .root_source_file = b.path("src/api/crypto.zig"),
        .target = target,
        .optimize = optimize,
    });
    crypto_module.addImport("v8", v8_module);
    crypto_module.addImport("js", js_module);

    // Create api/fetch module
    const fetch_module = b.createModule(.{
        .root_source_file = b.path("src/api/fetch.zig"),
        .target = target,
        .optimize = optimize,
    });
    fetch_module.addImport("v8", v8_module);
    fetch_module.addImport("js", js_module);

    // Create api/headers module
    const headers_module = b.createModule(.{
        .root_source_file = b.path("src/api/headers.zig"),
        .target = target,
        .optimize = optimize,
    });
    headers_module.addImport("v8", v8_module);
    headers_module.addImport("js", js_module);

    // Create api/request module
    const request_module = b.createModule(.{
        .root_source_file = b.path("src/api/request.zig"),
        .target = target,
        .optimize = optimize,
    });
    request_module.addImport("v8", v8_module);
    request_module.addImport("js", js_module);

    // Create api/abort module
    const abort_module = b.createModule(.{
        .root_source_file = b.path("src/api/abort.zig"),
        .target = target,
        .optimize = optimize,
    });
    abort_module.addImport("v8", v8_module);
    abort_module.addImport("js", js_module);

    // Create api/blob module
    const blob_module = b.createModule(.{
        .root_source_file = b.path("src/api/blob.zig"),
        .target = target,
        .optimize = optimize,
    });
    blob_module.addImport("v8", v8_module);
    blob_module.addImport("js", js_module);

    // Create api/formdata module
    const formdata_module = b.createModule(.{
        .root_source_file = b.path("src/api/formdata.zig"),
        .target = target,
        .optimize = optimize,
    });
    formdata_module.addImport("v8", v8_module);
    formdata_module.addImport("js", js_module);

    // Create api/readable_stream module
    const readable_stream_module = b.createModule(.{
        .root_source_file = b.path("src/api/readable_stream.zig"),
        .target = target,
        .optimize = optimize,
    });
    readable_stream_module.addImport("v8", v8_module);
    readable_stream_module.addImport("js", js_module);

    // Create api/writable_stream module
    const writable_stream_module = b.createModule(.{
        .root_source_file = b.path("src/api/writable_stream.zig"),
        .target = target,
        .optimize = optimize,
    });
    writable_stream_module.addImport("v8", v8_module);
    writable_stream_module.addImport("js", js_module);

    // Create api/transform_stream module
    const transform_stream_module = b.createModule(.{
        .root_source_file = b.path("src/api/transform_stream.zig"),
        .target = target,
        .optimize = optimize,
    });
    transform_stream_module.addImport("v8", v8_module);
    transform_stream_module.addImport("js", js_module);

    // Create log module
    const log_module = b.createModule(.{
        .root_source_file = b.path("src/log.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create config module
    const config_module = b.createModule(.{
        .root_source_file = b.path("src/config.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create runtime/event_loop module
    const event_loop_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/event_loop.zig"),
        .target = target,
        .optimize = optimize,
    });
    event_loop_module.addImport("xev", xev_module);

    // Create runtime/timers module
    const timers_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/timers.zig"),
        .target = target,
        .optimize = optimize,
    });
    timers_module.addImport("v8", v8_module);
    timers_module.addImport("event_loop", event_loop_module);

    // Create runtime/watchdog module
    const watchdog_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/watchdog.zig"),
        .target = target,
        .optimize = optimize,
    });
    watchdog_module.addImport("v8", v8_module);

    // Create engine/error module
    const error_module = b.createModule(.{
        .root_source_file = b.path("src/engine/error.zig"),
        .target = target,
        .optimize = optimize,
    });
    error_module.addImport("v8", v8_module);

    // Create engine/script module
    const script_module = b.createModule(.{
        .root_source_file = b.path("src/engine/script.zig"),
        .target = target,
        .optimize = optimize,
    });
    script_module.addImport("v8", v8_module);
    script_module.addImport("error.zig", error_module);
    script_module.addImport("console", console_module);
    script_module.addImport("encoding", encoding_module);
    script_module.addImport("url", url_module);
    script_module.addImport("crypto", crypto_module);
    script_module.addImport("fetch", fetch_module);
    script_module.addImport("headers", headers_module);
    script_module.addImport("request", request_module);
    script_module.addImport("timers", timers_module);
    script_module.addImport("abort", abort_module);
    script_module.addImport("blob", blob_module);
    script_module.addImport("formdata", formdata_module);
    script_module.addImport("readable_stream", readable_stream_module);
    script_module.addImport("writable_stream", writable_stream_module);
    script_module.addImport("transform_stream", transform_stream_module);

    // Create repl module
    const repl_module = b.createModule(.{
        .root_source_file = b.path("src/repl.zig"),
        .target = target,
        .optimize = optimize,
    });
    repl_module.addImport("v8", v8_module);
    repl_module.addImport("console", console_module);
    repl_module.addImport("encoding", encoding_module);
    repl_module.addImport("url", url_module);
    repl_module.addImport("crypto", crypto_module);
    repl_module.addImport("fetch", fetch_module);
    repl_module.addImport("headers", headers_module);
    repl_module.addImport("request", request_module);
    repl_module.addImport("timers", timers_module);
    repl_module.addImport("event_loop", event_loop_module);
    repl_module.addImport("abort", abort_module);
    repl_module.addImport("blob", blob_module);
    repl_module.addImport("formdata", formdata_module);
    repl_module.addImport("readable_stream", readable_stream_module);
    repl_module.addImport("writable_stream", writable_stream_module);
    repl_module.addImport("transform_stream", transform_stream_module);

    // Create server/app module (with V8 dependency)
    const app_module = b.createModule(.{
        .root_source_file = b.path("src/server/app.zig"),
        .target = target,
        .optimize = optimize,
    });
    app_module.addImport("v8", v8_module);
    app_module.addImport("console", console_module);
    app_module.addImport("encoding", encoding_module);
    app_module.addImport("url", url_module);
    app_module.addImport("crypto", crypto_module);
    app_module.addImport("fetch", fetch_module);
    app_module.addImport("headers", headers_module);
    app_module.addImport("request", request_module);
    app_module.addImport("timers", timers_module);
    app_module.addImport("event_loop", event_loop_module);
    app_module.addImport("watchdog", watchdog_module);
    app_module.addImport("abort", abort_module);
    app_module.addImport("blob", blob_module);
    app_module.addImport("formdata", formdata_module);
    app_module.addImport("readable_stream", readable_stream_module);
    app_module.addImport("writable_stream", writable_stream_module);
    app_module.addImport("transform_stream", transform_stream_module);

    // Create server/metrics module
    const metrics_module = b.createModule(.{
        .root_source_file = b.path("src/server/metrics.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create server/http module
    const server_module = b.createModule(.{
        .root_source_file = b.path("src/server/http.zig"),
        .target = target,
        .optimize = optimize,
    });
    server_module.addImport("v8", v8_module);
    server_module.addImport("app", app_module);
    server_module.addImport("log", log_module);
    server_module.addImport("metrics", metrics_module);
    server_module.addImport("event_loop", event_loop_module);
    server_module.addImport("timers", timers_module);
    server_module.addImport("config", config_module);

    // Create the root module for nano
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    root_module.addImport("v8", v8_module);
    root_module.addImport("script", script_module);
    root_module.addImport("repl", repl_module);
    root_module.addImport("server", server_module);
    root_module.addImport("log", log_module);
    root_module.addImport("config", config_module);

    // Main executable
    const exe = b.addExecutable(.{
        .name = "nano",
        .root_module = root_module,
    });

    // Add C++ inspector stubs
    exe.addCSourceFile(.{
        .file = b.path("src/engine/inspector_stubs.cpp"),
        .flags = &.{"-std=c++17"},
    });
    exe.linkLibCpp();

    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run nano");
    run_step.dependOn(&run_cmd.step);

    // Test module for script tests
    const script_test_module = b.createModule(.{
        .root_source_file = b.path("src/engine/script.zig"),
        .target = target,
        .optimize = optimize,
    });
    script_test_module.addImport("v8", v8_module);
    script_test_module.addImport("error.zig", error_module);
    script_test_module.addImport("console", console_module);
    script_test_module.addImport("encoding", encoding_module);
    script_test_module.addImport("url", url_module);
    script_test_module.addImport("crypto", crypto_module);
    script_test_module.addImport("fetch", fetch_module);
    script_test_module.addImport("headers", headers_module);
    script_test_module.addImport("request", request_module);
    script_test_module.addImport("abort", abort_module);
    script_test_module.addImport("blob", blob_module);
    script_test_module.addImport("formdata", formdata_module);
    script_test_module.addImport("readable_stream", readable_stream_module);
    script_test_module.addImport("writable_stream", writable_stream_module);

    // Test step for script module
    const script_tests = b.addTest(.{
        .root_module = script_test_module,
    });

    // Add C++ inspector stubs for tests (same as main exe)
    script_tests.addCSourceFile(.{
        .file = b.path("src/engine/inspector_stubs.cpp"),
        .flags = &.{"-std=c++17"},
    });
    script_tests.linkLibCpp();

    const run_script_tests = b.addRunArtifact(script_tests);

    // Config module tests (no V8 dependency)
    const config_test_module = b.createModule(.{
        .root_source_file = b.path("src/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    const config_tests = b.addTest(.{
        .root_module = config_test_module,
    });
    const run_config_tests = b.addRunArtifact(config_tests);

    // Fetch module tests (SSRF protection - no V8 dependency)
    const fetch_test_module = b.createModule(.{
        .root_source_file = b.path("src/api/fetch.zig"),
        .target = target,
        .optimize = optimize,
    });
    fetch_test_module.addImport("v8", v8_module);
    const fetch_tests = b.addTest(.{
        .root_module = fetch_test_module,
    });
    const run_fetch_tests = b.addRunArtifact(fetch_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_script_tests.step);
    test_step.dependOn(&run_config_tests.step);
    test_step.dependOn(&run_fetch_tests.step);
}
