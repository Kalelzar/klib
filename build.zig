const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.addModule("klib", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const uuid = b.dependency("uuid", .{ .target = target, .optimize = optimize }).module("uuid");
    const metrics = b.dependency("metrics", .{ .target = target, .optimize = optimize }).module("metrics");
    lib_mod.addImport("metrics", metrics);
    lib_mod.addImport("uuid", uuid);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "klib",
        .root_module = lib_mod,
    });

    switch (builtin.os.tag) {
        .windows => {
            lib.linkSystemLibrary("kernel32");
            lib.linkSystemLibrary("advapi32");
        },
        .linux => {
            lib.linkLibC();
        },
        else => |tag| {
            std.log.err("Compilation is not supported on: {}", .{tag});
            return error.Unsupported;
        },
    }

    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("test/test.zig"),
    });

    lib_unit_tests.root_module.addImport("klib", lib_mod);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
