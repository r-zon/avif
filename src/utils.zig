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

pub fn copyFromLut(comptime T: type) *const fn (dest: []f64, src: []if (@bitSizeOf(T) > 8) u16 else u8, extent: Extent) void {
    return struct {
        const lut = makeDepthLut(T);
        fn copy(dest: []f64, src: []if (@bitSizeOf(T) > 8) u16 else u8, extent: Extent) void {
            const W, const H, const C = .{ extent.width, extent.height, extent.channel };
            for (0..H) |h| {
                for (0..W) |w| {
                    for (0..C) |c| {
                        const i = h + H * w + H * W * c;
                        const j = c + C * w + C * W * h;
                        dest[i] = lut[src[j]];
                    }
                }
            }
        }
    }.copy;
}

pub const Extent = struct {
    width: usize,
    height: usize,
    channel: usize,
};

pub const CopyType = enum {
    to_r,
    from_r,
};

pub const CopyFn = enum {
    none,
    truncate,
};

pub inline fn copy(comptime @"type": CopyType, dest: anytype, src: anytype, extent: Extent, comptime func: CopyFn) void {
    const W, const H, const C = .{ extent.width, extent.height, extent.channel };
    for (0..H) |h| {
        for (0..W) |w| {
            for (0..C) |c| {
                const i = h + H * w + H * W * c;
                const j = c + C * w + C * W * h;
                switch (func) {
                    .none => switch (@"type") {
                        .to_r => dest[i] = src[j],
                        .from_r => dest[j] = src[i],
                    },
                    .truncate => switch (@"type") {
                        .to_r => dest[i] = @truncate(src[j]),
                        .from_r => dest[j] = @truncate(src[i]),
                    },
                }
            }
        }
    }
}

pub inline fn copyInv(dest: anytype, src: anytype, extent: Extent, inv: f64) void {
    const W, const H, const C = .{ extent.width, extent.height, extent.channel };
    for (0..H) |h| {
        for (0..W) |w| {
            for (0..C) |c| {
                const i = h + H * w + H * W * c;
                const j = c + C * w + C * W * h;
                dest[i] = src[j] * inv;
            }
        }
    }
}
