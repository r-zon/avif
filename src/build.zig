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
    translate_c.linkSystemLibrary("avif", .{});
    const c_mod = translate_c.createModule();

    const r_mod = b.createModule(.{
        .root_source_file = b.path("r.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = c_mod },
        },
    });

    const avif_mod = b.createModule(.{
        .root_source_file = b.path("avif.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = c_mod },
        },
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("root.zig"),
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
            .root_source_file = b.path("init.zig"),
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
        .dest_dir = .{ .override = .prefix },
    });

    // Makevars
    const pkg_config = b.graph.environ_map.get("PKG_CONFIG") orelse "pkg-config";
    var code: u8 = undefined;
    const libs = b.runAllowFail(&.{ pkg_config, "--libs", "libavif" }, &code, .ignore) catch "-lavif";
    const makevars = b.addConfigHeader(
        .{ .style = .{ .autoconf_at = b.path("Makevars.in") } },
        .{ .libs = std.mem.trimEnd(u8, libs, "\n") },
    );
    makevars.step.dependOn(&install_artifact.step);
    // Fix auto-generated comments
    const run_sed = b.addSystemCommand(&.{ "sed", "1s/^./#/" });
    run_sed.addFileArg(makevars.getOutputFile());

    const install_makevars = b.addInstallFile(
        run_sed.captureStdOut(.{}),
        if (target.result.os.tag == .windows) "Makevars.win" else "Makevars",
    );
    b.getInstallStep().dependOn(&install_makevars.step);
}
