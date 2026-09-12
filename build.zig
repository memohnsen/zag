const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // create module
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // add vaxis dependency to module
    const vaxis = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("vaxis", vaxis.module("vaxis"));

    const tree_sitter = b.dependency("tree_sitter", .{
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("tree_sitter", tree_sitter.module("tree_sitter"));

    const tree_sitter_zig = b.addLibrary(.{
        .name = "tree-sitter-zig",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    tree_sitter_zig.root_module.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-zig/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    tree_sitter_zig.root_module.addIncludePath(b.path("vendor/tree-sitter-zig/src"));
    exe_mod.linkLibrary(tree_sitter_zig);

    const exe = b.addExecutable(.{
        .name = "zag",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    // Let ZLS type-check the project on save without emitting a binary.
    const exe_check = b.addExecutable(.{
        .name = "zag-check",
        .root_module = exe_mod,
    });
    const check_step = b.step("check", "Check if zag compiles");
    check_step.dependOn(&exe_check.step);

    const run_step = b.step("run", "Run the Zag editor");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
}
