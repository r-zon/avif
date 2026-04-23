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

fn rInit(info: *r.DllInfo) callconv(.c) void {
    _ = r.registerRoutines(info, null, &call_entries, null, null);
    _ = r.useDynamicSymbols(info, 0);
    _ = r.forceSymbols(info, 1);
}
