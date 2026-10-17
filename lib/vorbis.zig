const std = @import("std");
const vorbis = @import("stb_vorbis");

pub const MAX_CHANNELS = 16;

pub const STBVorbisResult = enum(i32)
{
    NoError,

    NeedMoreData = 1,

    InvalidAPIMixing,
    OutOfMemory,
    FeatureNotSupported,
    TooManyChannels,
    CantOpenFile,
    SeekWithoutLength,

    UnexpectedEOF = 10,
    SeekInvalid,

    InvalidSetup = 20,
    InvalidStream,

    MissingCapturePattern = 30,
    InvalidStreamStructureVersion,
    ContinuedPacketFlagInvalid,
    IncorrectStreamSerialNumber,
    InvalidFirstPage,
    BadPacketType,
    CantFindLastPage,
    SeekFailed,
    OggSkeletonNotSupported
};

pub const VorbisError = error
{
    NeedMoreData,
    InvalidAPIMixing,
    OutOfMemory,
    FeatureNotSupported,
    TooManyChannels,
    CantOpenFile,
    SeekWithoutLength,
    UnexpectedEOF,
    SeekInvalid,
    InvalidSetup,
    InvalidStream,
    MissingCapturePattern,
    InvalidStreamStructureVersion,
    ContinuedPacketFlagInvalid,
    IncorrectStreamSerialNumber,
    InvalidFirstPage,
    BadPacketType,
    CantFindLastPage,
    SeekFailed,
    OggSkeletonNotSupported,
};

pub fn result_to_error(result: STBVorbisResult) ?VorbisError
{
    return switch(result)
    {
        .NoError => null,
        .NeedMoreData => VorbisError.NeedMoreData,
        .InvalidAPIMixing => VorbisError.InvalidAPIMixing,
        .OutOfMemory => VorbisError.OutOfMemory,
        .FeatureNotSupported => VorbisError.FeatureNotSupported,
        .TooManyChannels => VorbisError.TooManyChannels,
        .CantOpenFile => VorbisError.CantOpenFile,
        .SeekWithoutLength => VorbisError.SeekWithoutLength,
        .UnexpectedEOF => VorbisError.UnexpectedEOF,
        .SeekInvalid => VorbisError.SeekInvalid,
        .InvalidSetup => VorbisError.InvalidSetup,
        .InvalidStream => VorbisError.InvalidStream,
        .MissingCapturePattern => VorbisError.MissingCapturePattern,
        .InvalidStreamStructureVersion => VorbisError.InvalidStreamStructureVersion,
        .ContinuedPacketFlagInvalid => VorbisError.ContinuedPacketFlagInvalid,
        .IncorrectStreamSerialNumber => VorbisError.IncorrectStreamSerialNumber,
        .InvalidFirstPage => VorbisError.InvalidFirstPage,
        .BadPacketType => VorbisError.BadPacketType,
        .CantFindLastPage => VorbisError.CantFindLastPage,
        .SeekFailed => VorbisError.SeekFailed,
        .OggSkeletonNotSupported => VorbisError.OggSkeletonNotSupported
    };
}

/// Represents an `stb_vorbis` handle.
pub const VorbisInstance = opaque
{
    pub const FrameData = struct
    {
        ptr: [*][*]f32,

        num_channels: u32,
        num_samples_per_channel: u32
    };

    pub const Info = extern struct
    {
        sample_rate: u32,
        channels: i32,

        setup_memory_required: i32,
        setup_temp_memory_required: i32,
        temp_memory_required: i32,

        max_frame_size: i32
    };

    extern fn stb_vorbis_close(vorbis: *VorbisInstance) void;

    pub fn close(self: *VorbisInstance) void
    {
        stb_vorbis_close(self);
    }

    extern fn stb_vorbis_get_frame_float(vorbis: *VorbisInstance, num_channels: *i32, output: *[*][*]f32) i32;

    pub fn get_frame_float(self: *VorbisInstance) VorbisError!FrameData
    {
        const info = self.get_info();
        var channels = info.channels;

        var output: [*][*]f32 = undefined;
        const num_samples = stb_vorbis_get_frame_float(self, &channels, &output);

        const channels_u32: u32 = @bitCast(channels);
        const num_samples_u32: u32 = @bitCast(num_samples);

        return .{
            .ptr = output,
            .num_channels = channels_u32,
            .num_samples_per_channel = num_samples_u32
        };
    }

    extern fn stb_vorbis_get_info(vorbis: *VorbisInstance) Info;

    pub fn get_info(self: *VorbisInstance) Info
    {
        return stb_vorbis_get_info(self);
    }

    extern fn stb_vorbis_open_filename(filepath: [*:0]const u8, err: *i32, alloc: ?*anyopaque) *VorbisInstance;

    pub fn open_filename(filepath: []const u8) VorbisError!*VorbisInstance
    {
        var err: i32 = 0;
        const hndl = stb_vorbis_open_filename(@ptrCast(filepath.ptr), &err, null);
        const return_value: STBVorbisResult = @enumFromInt(err);
        if(result_to_error(return_value)) |r| return r;
        return hndl;
    }
};
