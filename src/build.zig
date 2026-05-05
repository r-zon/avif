const std = @import("std");

pub fn build(b: *std.Build) void {
    const strip = b.option(bool, "strip", "Remove debug information") orelse false;

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
    if (b.graph.environ_map.get("R_HOME")) |r_home|
        c_mod.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ r_home, "lib" }) });
    c_mod.linkSystemLibrary("R", .{});

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

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
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
            .unwind_tables = if (strip) .none else null,
        }),
    });

    if (optimize != .Debug and !strip)
        lib.compress_debug_sections = .zstd;

    lib.root_module.addAnonymousImport("build_zon", .{
        .root_source_file = b.path("build.zig.zon"),
    });

    const shlib_ext = b.graph.environ_map.get("SHLIB_EXT") orelse if (target.result.os.tag == .windows) ".dll" else ".so";
    const install_lib = b.addInstallFile(lib.getEmittedBin(), b.fmt("{s}{s}", .{ lib.name, shlib_ext }));
    b.getInstallStep().dependOn(&install_lib.step);

    const makefile = b.addConfigHeader(
        .{ .style = .{ .autoconf_at = b.path("Makefile.in") } },
        .{
            .zig_jobs = b.graph.environ_map.get("ZIG_JOBS") orelse "1",
            .zig_cpu = b.graph.environ_map.get("ZIG_CPU") orelse "baseline",
            .zig_optimize = b.graph.environ_map.get("ZIG_OPTIMIZE") orelse "ReleaseFast",
            .zig_strip = b.graph.environ_map.get("ZIG_STRIP") orelse "false",
        },
    );
    // Fix auto-generated comments
    const run_sed = b.addSystemCommand(&.{ "sed", "1s/^./#/" });
    run_sed.addFileArg(makefile.getOutputFile());
    const install_makefile = b.addInstallFile(
        run_sed.captureStdOut(.{}),
        if (target.result.os.tag == .windows) "Makefile.win" else "Makefile",
    );

    const configure_step = b.step("configure", "Configure the package");
    configure_step.dependOn(&install_makefile.step);
}
