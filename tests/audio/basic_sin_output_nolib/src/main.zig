const std = @import("std");
const ash = @import("ashbloom");

const miniaudio = ash.miniaudio;

const AudioFormat = struct
{
    sample_type: miniaudio.Format,
    sample_rate: u32,
    channels: u32,

    pub fn init(device: *miniaudio.Device) AudioFormat
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
        ash.print_stdout("\tFormat: {d}\n", .{@intFromEnum(self.sample_type)});
        ash.print_stdout("\tNumber of channels: {d}\n", .{self.channels});
        ash.print_stdout("\tSample rate: {d}\n", .{self.sample_rate});
    }
};

var allocator: std.mem.Allocator = undefined;
var audio_format: AudioFormat = undefined;

const SIN_FREQUENCY: f32 = 400;

var sin_offset: f32 = 0;
var data_buffer: []f32 = undefined;

fn data_callback(device: *miniaudio.Device, p_output: ?*anyopaque, _: ?*const anyopaque, frame_count: u32) callconv(.c) void
{
    _ = device;

    const channels = audio_format.channels;
    const sample_rate: f32 = @floatFromInt(audio_format.sample_rate);

    for(0..frame_count) |i|
    {
        const value = std.math.sin(2 * std.math.pi * SIN_FREQUENCY * sin_offset / sample_rate);
        for(0..channels) |j|
        {
            const index = i * channels + j;
            data_buffer[index] = value;
        }
        sin_offset += 1;
    }

    ash.utils.misc.memcpy_anonymous(p_output.?, data_buffer.ptr, frame_count * @sizeOf(f32) * channels);

    // ash.print_stdout("Number of frames: {d}\n", .{frame_count});
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

    audio_format = .init(device);
    audio_format.print_info();

    data_buffer = try allocator.alloc(f32, 4096);
    defer allocator.free(data_buffer);

    miniaudio.Device.start(device) catch
    {
        @panic("Failed to start playback device.");
    };

    while(true) {}
}
