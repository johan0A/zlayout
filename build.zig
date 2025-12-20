const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");
    root_module.linkLibrary(raylib_artifact);
    root_module.addImport("raylib", raylib);

    {
        const exe = b.addExecutable(.{ .name = "layout", .root_module = root_module });
        b.installArtifact(exe);
        const run = b.addRunArtifact(exe);
        const run_step = b.step("run", "");
        run_step.dependOn(&run.step);
    }

    {
        const tests = b.addTest(.{ .root_module = root_module });
        const run_tests = b.addRunArtifact(tests);
        const test_step = b.step("test", "");
        test_step.dependOn(&run_tests.step);
    }
}
