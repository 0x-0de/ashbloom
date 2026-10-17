const std = @import("std");

pub const MAX_SAMPLES_PER_FRAME = 1152 * 2;

pub const MP3FrameInfo = extern struct
{
    frame_bytes: i32,
    frame_offset: i32,
    channels: i32,
    hz: i32,
    layer: i32,
    bitrate_kbps: i32
};

pub const MP3Decoder = extern struct
{
    mdct_overlap: [2][9*32]f32,
    qmf_state: [15*2*32]f32,
    reserve: i32,
    free_format_bytes: i32,
    header: [4]u8,
    reserve_buf: [511]u8,

    extern fn mp3dec_decode_frame(decoder: *MP3Decoder, mp3: [*]u8, mp3_bytes: i32, pcm: [*]f32, info: *MP3FrameInfo) i32;

    pub fn decode_frame(self: *MP3Decoder, mp3: []u8, pcm: []f32, info: *MP3FrameInfo) usize
    {
        const length: i32 = @bitCast(@as(u32, @truncate(mp3.len)));
        return @intCast(mp3dec_decode_frame(self, mp3.ptr, length, pcm.ptr, info));
    }

    extern fn mp3dec_init(decoder: *MP3Decoder) void;

    pub fn init() MP3Decoder
    {
        var dec: MP3Decoder = undefined;
        mp3dec_init(&dec);
        return dec;
    }
};
