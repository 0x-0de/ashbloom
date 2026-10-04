const std = @import("std");
const ash = @import("ashbloom");

const miniaudio = ash.miniaudio;

const AudioFormat = struct
{
    sample_type: miniaudio.Format,
    sample_rate: u32,
    channels: u32,

    pub fn init_decoder(decoder: *miniaudio.Decoder) AudioFormat
    {
        var sample_type: miniaudio.Format = undefined;
        var sample_rate: u32 = undefined;
        var channels: u32 = undefined;

        decoder.getDataFormat(&sample_type, &channels, &sample_rate, null) catch |err|
        {
            std.debug.print("Miniaudio error: {any}\n", .{err});
            @panic("Failed to get AudioFormat from miniaudio Decoder.");
        };

        return .{
            .sample_type = sample_type,
            .sample_rate = sample_rate,
            .channels = channels
        };
    }

    pub fn init_device(device: *miniaudio.Device) AudioFormat
    {
        return .{
            .sample_type = device.getPlaybackFormat(),
            .sample_rate = device.getSampleRate(),
            .channels = device.getPlaybackChannels()
        };
    }

    pub fn print_info(self: AudioFormat) void
    {
        ash.print_stdout("Audio format:\n", .{});

        const format_str: []const u8 = switch(self.sample_type)
        {
            .unknown => "unknown",
            .unsigned8 => "u8",
            .signed16 => "i16",
            .signed24 => "i24",
            .signed32 => "i32",
            .float32 => "f32"
        };

        ash.print_stdout("\tFormat: {s}\n", .{format_str});
        ash.print_stdout("\tNumber of channels: {d}\n", .{self.channels});
        ash.print_stdout("\tSample rate: {d}\n", .{self.sample_rate});
    }
};

var allocator: std.mem.Allocator = undefined;
var audio_format: AudioFormat = undefined;

var wav_audio_format: AudioFormat = undefined;
var p_wav_decoder: *anyopaque = undefined;
var data_buffer: []f32 = undefined;

var reached_end = false;

fn data_callback(device: *miniaudio.Device, p_output: ?*anyopaque, _: ?*const anyopaque, frame_count: u32) callconv(.c) void
{
    _ = device;

    const channels = audio_format.channels;
    const wav_decoder: *miniaudio.Decoder = @ptrCast(p_wav_decoder);

    if(!reached_end)
    {
        _ = wav_decoder.readPCMFrames(data_buffer.ptr, frame_count) catch |err|
        {
            if(err == miniaudio.Error.AtEnd)
            {
                reached_end = true;
            }
            else
            {
                std.debug.print("Error: {any}\n", .{err});
                return;
            }
        };
    }

    //ash.print_stdout("Number of frames read: {d}\n", .{frames_read});

    ash.utils.misc.memcpy_anonymous(p_output.?, data_buffer.ptr, frame_count * @sizeOf(f32) * channels);
}

pub fn main() !void
{
    var dbg_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer
    {
        const status = dbg_allocator.deinit();
        if(status != .ok)
        {
            std.debug.print("Terminating with memory leaks!\n", .{});
        }
    }

    allocator = dbg_allocator.allocator();

    try ash.init_graphics(&allocator);
    defer ash.deinit_graphics();

    ash.print_stdout("Hello ashbloom!\n", .{});

    miniaudio.init(allocator);
    defer miniaudio.deinit();

    var audio_device_config: miniaudio.Device.Config = .init(.playback);

    audio_device_config.playback.format = .unknown;
    audio_device_config.playback.channels = 0;
    audio_device_config.sample_rate = 0;
    audio_device_config.data_callback = data_callback;

    const device = miniaudio.Device.create(null, audio_device_config) catch
    {
        @panic("Failed to open playback device.");
    };
    defer device.destroy();

    audio_format = .init_device(device);
    audio_format.print_info();

    data_buffer = try allocator.alloc(f32, 4096);
    defer allocator.free(data_buffer);

    var decoder_config = miniaudio.Decoder.Config.initDefault();

    // Decoders will automatically convert audio sources of different sample rates, types, and numbers of channels to the values set in the config.
    decoder_config.format = audio_format.sample_type;
    decoder_config.channels = audio_format.channels;
    decoder_config.sample_rate = audio_format.sample_rate;

    const wav_decoder = miniaudio.Decoder.createFromFile("../../res/test.wav", decoder_config) catch |err|
    {
        std.debug.print("Error: {any}\n", .{err});
        @panic("Failed to create wav decoder.");
    };
    defer wav_decoder.destroy();

    wav_audio_format = .init_decoder(wav_decoder);
    wav_audio_format.print_info();

    p_wav_decoder = @constCast(@ptrCast(wav_decoder));

    miniaudio.Device.start(device) catch
    {
        @panic("Failed to start playback device.");
    };

    while(true) {}
}
