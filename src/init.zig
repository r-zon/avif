const std = @import("std");
const r = @import("r");
const lib = @import("lib");

comptime {
    const pkgname = @tagName(@import("build_zon").name);
    @export(&rInit, .{ .name = "R_init_" ++ pkgname });
}

fn fnArgsNum(comptime func: anytype) usize {
    return @typeInfo(@TypeOf(func)).@"fn".params.len;
}

const call_entries = [_]r.CallMethodDef{
    .{ .name = "read_avif", .fun = @ptrCast(&lib.readAvif), .numArgs = fnArgsNum(lib.readAvif) },
    .{ .name = "write_avif", .fun = @ptrCast(&lib.writeAvif), .numArgs = fnArgsNum(lib.writeAvif) },
    .{ .name = null, .fun = null, .numArgs = 0 },
};

fn maxCpuCount() usize {
    const cpu_count = std.Thread.getCpuCount() catch |e| {
        r.warn("Failed to get logical core count: %s. Forced to use single-threading.", @errorName(e).ptr);
        return 1;
    };
    // core count should be <= 2 if `_R_CHECK_LIMIT_CORES_` is `TRUE`,
    // see https://cran.r-project.org/doc/manuals/R-ints.html
    if (std.c.getenv("_R_CHECK_LIMIT_CORES_")) |env| {
        if (std.mem.eql(u8, std.mem.sliceTo(env, 0), "TRUE"))
            return @min(2, cpu_count);
    }
    return cpu_count;
}

pub var max_cpu_count: usize = undefined;
fn rInit(info: *r.DllInfo) callconv(.c) void {
    const log = std.log.scoped(.init);
    max_cpu_count = maxCpuCount();
    log.debug("max_cpu_count={d}", .{max_cpu_count});
    _ = r.registerRoutines(info, null, &call_entries, null, null);
    _ = r.useDynamicSymbols(info, 0);
    _ = r.forceSymbols(info, 1);
}
