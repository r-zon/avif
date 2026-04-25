const c = @import("c");

inline fn resultFn(result: c.avifResult) ?c.avifResult {
    if (result == c.AVIF_RESULT_OK)
        return null;
    return result;
}

pub const Decoder = extern struct {
    ptr: *c.avifDecoder,

    pub fn init() !Decoder {
        return .{ .ptr = c.avifDecoderCreate() orelse return error.OutOfMemory };
    }

    pub fn deinit(self: Decoder) void {
        c.avifDecoderDestroy(self.ptr);
    }

    pub fn setIoFile(self: Decoder, file_path: [*c]const u8) ?c.avifResult {
        return resultFn(c.avifDecoderSetIOFile(self.ptr, file_path));
    }

    pub fn setIoMemory(self: Decoder, data: []const u8) ?c.avifResult {
        return resultFn(c.avifDecoderSetIOMemory(self.ptr, data.ptr, data.len));
    }

    pub fn parse(self: Decoder) ?c.avifResult {
        return resultFn(c.avifDecoderParse(self.ptr));
    }

    pub fn nextImage(self: Decoder) ?c.avifResult {
        return resultFn(c.avifDecoderNextImage(self.ptr));
    }
};

pub const Encoder = extern struct {
    ptr: *c.avifEncoder,

    pub fn init() !Encoder {
        return .{ .ptr = c.avifEncoderCreate() orelse return error.OutOfMemory };
    }

    pub fn deinit(self: *Encoder) void {
        c.avifEncoderDestroy(self.ptr);
    }

    pub fn addImage(self: *Encoder, image: Image) ?c.avifResult {
        return resultFn(c.avifEncoderAddImage(self.ptr, image.ptr, 1, c.AVIF_ADD_IMAGE_FLAG_SINGLE));
    }

    pub fn finish(self: *Encoder, data: *ReadWriteData) ?c.avifResult {
        return resultFn(c.avifEncoderFinish(self.ptr, &data.inner));
    }
};

pub const ReadWriteData = extern struct {
    inner: c.avifRWData = .{},

    pub fn deinit(self: *ReadWriteData) void {
        c.avifRWDataFree(&self.inner);
    }
};

pub const Image = extern struct {
    ptr: *c.avifImage,

    pub const PixelFormat = enum(u8) {
        none = 0,
        yuv444 = 1,
        yuv422 = 2,
        yuv420 = 3,
        yuv400 = 4,
    };

    const Options = struct {
        width: u32,
        height: u32,
        depth: u32,
        format: PixelFormat,
    };

    pub fn init() !Image {
        return .{ .ptr = c.avifImageCreateEmpty() orelse return error.OutOfMemory };
    }

    pub fn initWithOptions(options: Options) !Image {
        return .{ .ptr = c.avifImageCreate(
            options.width,
            options.height,
            options.depth,
            @intFromEnum(options.format),
        ) orelse return error.OutOfMemory };
    }

    pub fn deinit(self: *Image) void {
        c.avifImageDestroy(self.ptr);
    }

    pub fn isOpaque(self: *const Image) bool {
        return c.avifImageIsOpaque(self.ptr) == 1;
    }

    pub fn toRgb(self: *const Image, rgb: *RgbImage) ?c.avifResult {
        return resultFn(c.avifImageYUVToRGB(self.ptr, &rgb.inner));
    }

    pub fn toYuv(self: *Image, rgb: *const RgbImage) ?c.avifResult {
        return resultFn(c.avifImageRGBToYUV(self.ptr, &rgb.inner));
    }

    pub fn parse(self: *Image) ?c.avifResult {
        return resultFn(c.avifImageParse(self.ptr));
    }

    pub fn next(self: *Image) ?c.avifResult {
        return resultFn(c.avifImageNextImage(self.ptr));
    }
};

pub const RgbImage = extern struct {
    inner: c.avifRGBImage = .{},

    pub fn setDefaults(self: *RgbImage, image: Image) void {
        c.avifRGBImageSetDefaults(&self.inner, image.ptr);
    }

    pub fn allocatePixels(self: *RgbImage) ?c.avifResult {
        return resultFn(c.avifRGBImageAllocatePixels(&self.inner));
    }

    pub fn freePixels(self: *RgbImage) void {
        c.avifRGBImageFreePixels(&self.inner);
    }

    pub fn channelCount(self: *const RgbImage) u32 {
        return c.avifRGBFormatChannelCount(self.inner.format);
    }
};

pub const resultToString = c.avifResultToString;
pub const rgbFormatChannelCount = c.avifRGBFormatChannelCount;
pub const codecName = c.avifCodecName;
