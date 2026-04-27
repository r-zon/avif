const std = @import("std");
const maxInt = std.math.maxInt;

fn makeDepthLut(comptime T: type) [maxInt(T) + 1]f64 {
    @setEvalBranchQuota(5000);
    const max_int: comptime_float = maxInt(T);
    var lut: [max_int + 1]f64 = @splat(1.0 / max_int);
    for (&lut, 0..) |*i, j|
        i.* *= j;
    return lut;
}

pub fn copyFromLut(comptime T: type) *const fn (dest: []f64, src: []if (@bitSizeOf(T) > 8) u16 else u8) void {
    return struct {
        const lut = makeDepthLut(T);
        fn copy(dest: []f64, src: []if (@bitSizeOf(T) > 8) u16 else u8) void {
            for (dest, src) |*i, j|
                i.* = lut[j];
        }
    }.copy;
}

pub inline fn copy(dest: anytype, src: anytype) void {
    for (dest, src) |*i, j|
        i.* = j;
}

pub inline fn copyTruncate(dest: anytype, src: anytype) void {
    for (dest, src) |*i, j|
        i.* = @truncate(j);
}
