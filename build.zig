const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get v8 dependency
    const v8_dep = b.dependency("v8", .{
        .target = target,
        .optimize = optimize,
    });

    // Create the root module for nano
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add v8 import to root module
    root_module.addImport("v8", v8_dep.module("v8"));

    // Main executable
    const exe = b.addExecutable(.{
        .name = "nano",
        .root_module = root_module,
    });

    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run nano");
    run_step.dependOn(&run_cmd.step);

    // Create the test module
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add v8 import to test module
    test_module.addImport("v8", v8_dep.module("v8"));

    // Test step
    const unit_tests = b.addTest(.{
        .root_module = test_module,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
