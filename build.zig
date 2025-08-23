const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    // Options
    const build_all = b.option(bool, "all", "Build all components. You can still disable individual components") orelse false;
    const build_lib = b.option(bool, "lib", "Build the library") orelse build_all;
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.addModule("klib", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const lib_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    // Artifacts:
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "klib",
        .root_module = lib_mod,
    });

    if (build_lib) {
        b.installArtifact(lib);
    }

    const run_tests = b.addRunArtifact(lib_tests);

    const install_docs = b.addInstallDirectory(
        .{
            .source_dir = lib.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = "docs",
        },
    );

    const fmt = b.addFmt(.{
        .paths = &.{
            "src/",
            "build.zig",
            "build.zig.zon",
        },
        .check = true,
    });

    // Steps:
    const check = b.step("check", "Build without generating artifacts.");
    check.dependOn(&lib.step);

    const test_step = b.step("test", "Run the unit tests.");
    test_step.dependOn(&run_tests.step);
    // - fmt
    const fmt_step = b.step("fmt", "Check formatting");
    fmt_step.dependOn(&fmt.step);
    check.dependOn(fmt_step);
    b.getInstallStep().dependOn(fmt_step);
    // - docs
    const docs_step = b.step("docs", "Generate docs");
    docs_step.dependOn(&install_docs.step);
    docs_step.dependOn(&lib.step);

    // Dependencies:
    // 1st Party:
    // 3rd Party:
    const uuid = b.dependency("uuid", .{ .target = target, .optimize = optimize }).module("uuid");
    const metrics = b.dependency("metrics", .{ .target = target, .optimize = optimize }).module("metrics");

    // Imports:
    // Internal:
    // 1st Party:
    // 3rd Party:
    switch (builtin.os.tag) {
        .windows => {
            lib_mod.linkSystemLibrary("kernel32", .{ .preferred_link_mode = .dynamic });
            lib_mod.linkSystemLibrary("advapi32", .{ .preferred_link_mode = .dynamic });
        },
        .linux => {},
        else => |tag| {
            std.log.err("Compilation is not supported on: {}", .{tag});
            return error.Unsupported;
        },
    }

    lib_mod.addImport("metrics", metrics);
    lib_mod.addImport("uuid", uuid);
}
