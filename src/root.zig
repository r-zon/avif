const std = @import("std");
const c = @import("c");
const avif = @import("avif");
const r = @import("r");
const utils = @import("utils.zig");
const init = @import("root");

const copyAny = utils.copy;
const copyTruncate = utils.copyTruncate;
const copyFromLut = utils.copyFromLut;

const PixelType = enum {
    u8,
    u16,
};

const DecodingOptions = struct {
    jobs: ?c_int = null,
    normalize: bool = false,
};

pub fn readAvif(src: r.Sexp, proto: r.Sexp, args: r.Sexp) callconv(.c) r.Sexp {
    const log = std.log.scoped(.read);

    const src_type = src.type();
    log.debug("src_type={t}", .{src_type});
    switch (src_type) {
        .string, .raw => {},
        else => r.err("Source must be a file path or a raw vector"),
    }

    var out_type = proto.type();
    log.debug("out_type={t}", .{out_type});
    switch (out_type) {
        .raw, .real, .integer => {},
        else => r.err("Output must be a raw, real, or integer vector"),
    }

    var options: DecodingOptions = .{};
    parseEnvironment(@TypeOf(options), &options, args);
    log.debug("options={}", .{options});

    const jobs: c_int = blk: {
        if (options.jobs) |j| {
            if (j < 1 or j > init.max_cpu_count)
                r.err("Invalid argument jobs=%d, jobs must be in (0, %d]", j, init.max_cpu_count);
            break :blk j;
        }
        break :blk @intCast(init.max_cpu_count);
    };
    const normalize = options.normalize;
    if (normalize and out_type != .real) {
        out_type = .real;
        r.warn("Normalization turned on, output a real vector instead");
    }

    const decoder = avif.Decoder.init() catch |e|
        r.err("Init decoder failed: %s", @errorName(e).ptr);
    defer decoder.deinit();
    log.debug("codec={s}", .{avif.codecName(decoder.ptr.codecChoice, c.AVIF_CODEC_FLAG_CAN_DECODE)});

    decoder.ptr.maxThreads = jobs;

    const src_len = src.len();
    if (src_type == .string) {
        const filename = blk: {
            if (src_len == 1) {
                const name = src.stringElement(0).toUtf8();
                if (name[0] != 0)
                    break :blk name;
            }
            r.err("Filename should not be empty");
        };
        if (decoder.setIoFile(filename)) |result|
            r.err("Set file IO failed: %s", avif.resultToString(result));
    } else {
        if (src_len == 0)
            r.err("Input source should not be empty");
        const data = src.raw()[0..@intCast(src_len)];
        if (decoder.setIoMemory(data)) |result|
            r.err("Set memory IO failed: %s", avif.resultToString(result));
    }

    if (decoder.parse()) |result|
        r.err("Parse failed: %s", avif.resultToString(result));

    if (decoder.nextImage()) |result|
        r.err("Get next image failed: %s", avif.resultToString(result));

    const image: avif.Image = .{ .ptr = decoder.ptr.image };
    const width, const height, const depth = blk: {
        const img = image.ptr.*;
        break :blk .{ img.width, img.height, img.depth };
    };

    const pixel_type: PixelType = if (depth > 8) .u16 else .u8;
    log.debug("pixel_type={t}", .{pixel_type});

    if (pixel_type == .u16 and out_type == .raw) {
        out_type = if (normalize) .real else .integer;
        r.warn("%dbpc detected, output %s instead", depth, @tagName(out_type).ptr);
    }

    var rgb: avif.RgbImage = .{};
    rgb.setDefaults(image);
    if (image.isOpaque()) {
        rgb.inner.format = c.AVIF_RGB_FORMAT_RGB;
        log.debug("Image is opaque, set to RGB", .{});
    }

    if (rgb.allocatePixels()) |result|
        r.err("Allocate RGB pixels failed: %s", avif.resultToString(result));
    defer rgb.freePixels();

    if (image.toRgb(&rgb)) |result|
        r.err("Convert from YUV failed: %s", avif.resultToString(result));

    const channel_count = rgb.channelCount();
    log.debug("width={d} height={d} channel_count={d}", .{ width, height, channel_count });

    const plane_size = width * height;
    const out_size = plane_size * channel_count;
    const out = r.allocVector(out_type, out_size, .protected);
    defer r.unprotect(1);

    const pixels = rgb.inner.pixels;
    const pixels_u8 = pixels[0..out_size];
    const pixels_u16: []u16 = @ptrCast(@alignCast(pixels[0 .. out_size * 2]));
    blk: switch (out_type) {
        .raw => @memcpy(out.raw(), pixels_u8),
        .integer => {
            const buf = out.integer()[0..out_size];
            if (pixel_type == .u16)
                copyAny(buf, pixels_u16)
            else
                copyAny(buf, pixels_u8);
        },
        .real => {
            const buf = out.real()[0..out_size];

            if (!normalize) {
                if (pixel_type == .u8)
                    copyAny(buf, pixels_u8)
                else
                    copyAny(buf, pixels_u16);
                break :blk;
            }

            if (pixel_type == .u8)
                break :blk copyFromLut(u8)(buf, pixels_u8);

            const copy = switch (depth) {
                10 => copyFromLut(u10),
                12 => copyFromLut(u12),
                // 16 => copyFromLut(u16),
                else => break :blk {
                    const max_int: f64 = (@as(u6, 1) << @intCast(depth)) - 1;
                    const inv: f64 = 1.0 / max_int;
                    for (buf, pixels_u16) |*i, j|
                        i.* = j * inv;
                },
            };
            copy(buf, pixels_u16);
        },
        // Checked before
        else => unreachable,
    }

    const dim = r.allocVector(.integer, 3, .protected);
    defer r.unprotect(1);
    inline for (dim.integer(), .{ channel_count, width, height }) |*i, j|
        i.* = @intCast(j);
    _ = r.setAttribute(out, .dim, dim);

    const depth_sexp = r.allocScalar(.integer, @intCast(depth), .protected);
    defer r.unprotect(1);
    _ = r.setAttribute(out, .{ .custom = r.install("depth") }, depth_sexp);

    return out;
}

const EncodingOptions = struct {
    jobs: ?c_int = null,
    speed: c_int = 6,
    quality: c_int = 60,
    alpha_quality: c_int = 60,
    format: c_uint = 444,
};

pub fn writeAvif(src: r.Sexp, target: r.Sexp, args: r.Sexp) callconv(.c) r.Sexp {
    const log = std.log.scoped(.write);

    const src_type = src.type();
    log.debug("src_type={t}", .{src_type});
    switch (src_type) {
        .raw, .integer => {},
        else => r.err("Source must be a raw or integer vector with dim (height, width, channel) set"),
    }

    const src_dim = r.getAttribute(src, .dim);
    if (src_dim.isNull() or src_dim.len() != 3)
        r.err("Source \"dim\" attribute (height, width, channel) required");

    var src_depth: u32 = if (r.getAttribute(src, .{ .custom = r.install("depth") }).asInteger()) |depth|
        switch (depth) {
            8, 10, 12 => @intCast(depth),
            else => |d| r.err("Invalid depth=%d, depth must be 8, 10 or 12", d),
        }
    else
        8;
    log.debug("src_depth={d}", .{src_depth});
    if (src_type == .raw and src_depth != 8) {
        r.warn("Ignore depth=%d, depth should always be 8 when source is a raw vector", src_depth);
        src_depth = 8;
    }

    const target_type = target.type();
    log.debug("target_type={t}", .{target_type});
    const target_filename = blk: switch (target_type) {
        .null => null,
        .string => {
            if (target.len() == 1) {
                const name = target.stringElement(0).toUtf8();
                if (name[0] != 0) {
                    log.debug("target_filename={s}", .{name});
                    break :blk name;
                }
            }
            r.err("Target file path must a string scalar");
        },
        else => r.err("Target must be a null or a string scalar"),
    };

    var options: EncodingOptions = .{};
    parseEnvironment(@TypeOf(options), &options, args);
    log.debug("options={}", .{options});

    const jobs: c_int = blk: {
        if (options.jobs) |j| {
            if (j < 1 or j > init.max_cpu_count)
                r.err("Invalid argument jobs=%d, jobs must be in (0, %d]", j, init.max_cpu_count);
            break :blk j;
        }
        break :blk @intCast(init.max_cpu_count);
    };
    const speed = options.speed;
    if (speed < 0 or speed > 10)
        r.err("Invalid argument speed=%d, speed must be in [0, 10] where 10 is the fastest", speed);
    const quality = options.quality;
    if (quality < 0 or quality > 100)
        r.err("Invalid argument quality=%d, quality must be in [0, 100] where 100 is lossless", quality);
    const alpha_quality = options.alpha_quality;
    if (alpha_quality < 0 or alpha_quality > 100)
        r.err("Invalid argument alpha_quality=%d, alpha_quality must be in [0, 100] where 100 is lossless", alpha_quality);
    const format: avif.Image.PixelFormat = switch (options.format) {
        444 => .yuv444,
        422 => .yuv422,
        420 => .yuv420,
        400 => .yuv400,
        else => |f| r.err("Invalid argument format=%d, format must be 444, 422, 420 or 400", f),
    };

    const channel_count: u32, const width: u32, const height: u32 = blk: {
        const int = src_dim.integer();
        break :blk .{ @intCast(int[0]), @intCast(int[1]), @intCast(int[2]) };
    };
    log.debug("width={d} height={d} channel_count={d}", .{ width, height, channel_count });

    var image = avif.Image.initWithOptions(.{
        .width = width,
        .height = height,
        .depth = src_depth,
        .format = format,
    }) catch |e|
        r.err("Image init failed: %s", @errorName(e).ptr);
    defer image.deinit();

    var rgb: avif.RgbImage = .{};
    rgb.setDefaults(image);
    rgb.inner.format = switch (channel_count) {
        3 => c.AVIF_RGB_FORMAT_RGB,
        4 => c.AVIF_RGB_FORMAT_RGBA,
        else => r.err("Unsupported channel count: %d", channel_count),
    };

    if (rgb.allocatePixels()) |result|
        r.err("Allocate RGB pixels failed: %s", avif.resultToString(result));
    defer rgb.freePixels();

    const pixel_type: PixelType = if (src_depth > 8) .u16 else .u8;
    log.debug("pixel_type={t}", .{pixel_type});
    if (src_type == .raw)
        @memcpy(rgb.inner.pixels, src.raw()[0..@intCast(src.len())])
    else {
        const src_uint: []c_uint = @ptrCast(src.integer()[0..@intCast(src.len())]);
        if (pixel_type == .u8) {
            copyTruncate(rgb.inner.pixels, src_uint);
        } else {
            const plane_size = width * height;
            const out_size = plane_size * channel_count;
            const pixels_u16: []u16 = @ptrCast(@alignCast(rgb.inner.pixels[0 .. out_size * 2]));
            copyTruncate(pixels_u16, src_uint);
        }
    }

    if (image.toYuv(&rgb)) |result|
        r.err("Convert to YUV failed: %s", avif.resultToString(result));

    var encoder = avif.Encoder.init() catch |e|
        r.err("Init encoder failed: %s", @errorName(e).ptr);
    defer encoder.deinit();
    log.debug("codec={s}", .{avif.codecName(encoder.ptr.codecChoice, c.AVIF_CODEC_FLAG_CAN_ENCODE)});

    encoder.ptr.maxThreads = jobs;
    encoder.ptr.speed = speed;
    encoder.ptr.quality = quality;
    encoder.ptr.qualityAlpha = alpha_quality;

    if (encoder.addImage(image)) |result| {
        const diagnostic_error = encoder.ptr.diag.@"error";
        if (diagnostic_error[0] == 0)
            r.err("Add image to encoder failed: %s", avif.resultToString(result))
        else
            r.err("Add image to encoder failed: %s\n%s", avif.resultToString(result), &diagnostic_error);
    }

    var avif_out: avif.ReadWriteData = .{};
    if (encoder.finish(&avif_out)) |result|
        r.err("Finish encode failed: %s", avif.resultToString(result));
    defer avif_out.deinit();

    const out_size = avif_out.inner.size;
    log.debug("out_size={d}", .{out_size});

    const out_data = avif_out.inner.data[0..out_size];
    if (target_filename) |sub_path| {
        var threaded: std.Io.Threaded = .init_single_threaded;
        const io = threaded.io();
        var file = std.Io.Dir.cwd().createFile(io, std.mem.sliceTo(sub_path, 0), .{}) catch |e|
            r.err("Create file failed: %s", @errorName(e).ptr);
        defer file.close(io);
        file.writeStreamingAll(io, out_data) catch |e|
            r.err("Write file failed: %s", @errorName(e).ptr);
        return .{ .ptr = c.R_NilValue };
    } else {
        const out = r.allocVector(.raw, out_size, .protected);
        defer r.unprotect(1);
        @memcpy(out.raw(), out_data);
        return out;
    }
}

fn parseEnvironment(comptime T: type, result: *T, env: r.Sexp) void {
    inline for (@typeInfo(T).@"struct".fields) |field| blk: {
        const name = r.installChar(r.makeChar(field.name, .utf8));
        const variable = r.getVariable(name, env.ptr, false, null);
        if (variable) |val| {
            const v: r.Sexp = .{ .ptr = val };
            @field(result, field.name) = switch (@FieldType(T, field.name)) {
                bool => v.asBool(),
                ?c_int => v.asInteger(),
                c_int => v.asInteger() orelse break :blk,
                c_uint, usize => |U| std.math.cast(U, v.asInteger() orelse break :blk) orelse break :blk,
                else => @compileError("Unsupported type"),
            };
        }
    }
}
