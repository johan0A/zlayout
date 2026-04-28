const std = @import("std");
const zon = @import("build.zig.zon");

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
    root_module.linkLibrary(raylib_dep.artifact("raylib"));
    root_module.addImport("raylib", raylib_dep.module("raylib"));

    const zlayout_dep = b.dependency("zlayout", .{
        .target = target,
        .optimize = optimize,
    });
    root_module.addImport("zlayout", zlayout_dep.module("zlayout"));

    const exe = b.addExecutable(.{ .name = @tagName(zon.name), .root_module = root_module });
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    const run_step = b.step("run", "");
    run_step.dependOn(&run.step);
}
