const std = @import("std");
const ash = @import("../root.zig");

const AudioFormat = ash.audio.AudioFormat;
const Producer = ash.audio.Producer;

fn produce_wav(output: *const []f32, flags: ash.audio.Producer.Flags, data: ?*anyopaque) void
{
    _ = output;

    std.debug.assert(data != null);
    var wav_data: WavData = undefined;
    ash.utils.misc.memcpy_anonymous(&wav_data, data.?, @sizeOf(WavData));

    if(flags.sample_margin != 1) wav_data.read_offset += wav_data.format.get_frame_size();

    ash.utils.misc.memcpy_anonymous(data.?, &wav_data, @sizeOf(WavData));
}

const WavChunk = union(enum)
{
    Junk: void,
    RiffHeader: void,
    WaveHeader: void,
    Format: AudioFormat,
    Data: struct { offset: usize, size: usize }
};

const WavData = struct
{
    format: AudioFormat,
    data_offset: usize,
    data_size: usize,
    read_offset: usize
};

fn read_next_wav_block(allocator: *const std.mem.Allocator, reader: *std.Io.File.Reader) ?WavChunk
{
    const header = try reader.readAlloc(allocator.*, 4);
    defer allocator.free(header);

    if(std.mem.eql(u8, header, "RIFF"))
    {
        // Advance the next 4 bytes.
        try reader.discardAll(4);
        return .{ .RiffHeader = @as(void, undefined) };
    }
    else if(std.mem.eql(u8, header, "WAVE"))
    {
        return .{ .WaveHeader = @as(void, undefined) };
    }
    else if(std.mem.eql(u8, header, "JUNK"))
    {
        const size_bytes = try reader.readAlloc(allocator.*, 4);
        defer allocator.free(size_bytes);

        var size: u32 = undefined;
        ash.utils.misc.memcpy_anonymous(&size, size_bytes.ptr, @sizeOf(u32));

        try reader.discardAll(size);

        return .{ .Junk = @as(void, undefined) };
    }
    else if(std.mem.eql(u8, header, "fmt "))
    {
        const size_bytes = try reader.readAlloc(allocator.*, 4);

        var size: u32 = undefined;
        ash.utils.misc.memcpy_anonymous(&size, size_bytes.ptr, @sizeOf(u32));

        allocator.free(size_bytes);
        const format_bytes = try reader.readAlloc(allocator.*, 2);

        var format: u16 = undefined;
        ash.utils.misc.memcpy_anonymous(&format, format_bytes.ptr, 2);

        allocator.free(format_bytes);
        const channels_bytes = try reader.readAlloc(allocator.*, 2);

        var channels: u16 = undefined;
        ash.utils.misc.memcpy_anonymous(&channels, channels_bytes.ptr, 2);

        allocator.free(channels_bytes);
        const sample_rate_bytes = try reader.readAlloc(allocator.*, 4);

        var sample_rate: u32 = undefined;
        ash.utils.misc.memcpy_anonymous(&sample_rate, sample_rate_bytes.ptr, 4);

        allocator.free(sample_rate_bytes);

        // Number of bytes to read per second -> sample rate * bytes per frame. Don't care.
        try reader.discardAll(4);

        // Number of bytes per frame. Don't care, we're about to get bits per sample.
        try reader.discardAll(2);

        const bits_per_sample_bytes = try reader.readAlloc(allocator.*, 2);

        var bits_per_sample: u16 = undefined;
        ash.utils.misc.memcpy_anonymous(&bits_per_sample, bits_per_sample_bytes.ptr, 2);

        allocator.free(bits_per_sample_bytes);

        const miniaudio_format: ash.ma.Format = switch(bits_per_sample)
        {
            8 => .Unsigned8,
            16 => .Signed16,
            24 => .Signed24,
            32 => if(format == 1) .Signed32 else .Float32,
            else => .Unknown
        };

        return .{ .Format = .{
            .sample_rate = sample_rate,
            .format = miniaudio_format,
            .channels = channels
        }};
    }
}

pub fn wav(allocator: *const std.mem.Allocator, path: []const u8) !Producer
{
    var io_threaded = std.Io.Threaded.init(allocator.*, .{});
    defer io_threaded.deinit();

    const io = io_threaded.io();

    const cwd = std.Io.Dir.cwd();

    const file = try cwd.openFile(io, path, .{ .mode = .read_only });
    defer file.close(io);

    const reader_buffer: [1024]u8 = undefined;
    var reader = file.reader(io, reader_buffer);

    var wav_data: WavData = try allocator.create(WavData);

    while(read_next_wav_block(allocator, &reader)) |b|
    {
        switch(b)
        {
            .Junk, .RiffHeader, .WaveHeader => {},
            .Format => |f|
            {
                wav_data.format = f;
            },
            .Data => |d|
            {
                wav_data.data_offset = d.offset;
                wav_data.data_size = d.size;
            }
        }
    }

    ash.print_stdout("WAV Data:\n\tChannels: {d}\n\tSample rate: {d}\n\tFormat: {any}\n\tData offset: {d}\n\tData size: {d}\n",
        .{wav_data.format.channels, wav_data.format.sample_rate, wav_data.format.format, wav_data.data_offset, wav_data.data_size});

    return .{
        .channels = wav_data.format.channels,
        .sample_rate = wav_data.format.sample_rate,
        .data = wav_data,
        .generator = produce_wav
    };
}
