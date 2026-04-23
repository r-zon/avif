const std = @import("std");

pub fn build(b: *std.Build) void {
    const strip = b.option(bool, "strip", "Remove debug information");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wf = b.addWriteFiles();
    const translate_c = b.addTranslateC(.{
        .root_source_file = wf.add("c.h",
            \\#include <Rinternals.h>
            \\#include <avif/avif.h>
        ),
        .target = target,
        .optimize = optimize,
    });
    translate_c.defineCMacro("R_NO_REMAP", "");
    if (b.graph.environ_map.get("R_INCLUDE_DIR")) |r_include_dir|
        translate_c.addIncludePath(.{ .cwd_relative = r_include_dir });
    const c_mod = translate_c.createModule();

    const r_mod = b.createModule(.{
        .root_source_file = b.path("src/r.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = c_mod },
        },
    });

    const avif_mod = b.createModule(.{
        .root_source_file = b.path("src/avif.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = c_mod },
        },
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = c_mod },
            .{ .name = "r", .module = r_mod },
            .{ .name = "avif", .module = avif_mod },
        },
    });

    const obj = b.addObject(.{
        .name = "avif",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lib", .module = mod },
                .{ .name = "r", .module = r_mod },
            },
            .strip = strip,
            .omit_frame_pointer = strip,
            .unwind_tables = if (strip orelse false) .none else null,
        }),
    });

    obj.root_module.addAnonymousImport("build_zon", .{
        .root_source_file = b.path("build.zig.zon"),
    });

    const install_artifact = b.addInstallArtifact(obj, .{
        .dest_dir = .{ .override = .{ .custom = "obj" } },
    });
    b.getInstallStep().dependOn(&install_artifact.step);
}
