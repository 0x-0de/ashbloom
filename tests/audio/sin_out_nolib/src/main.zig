const std = @import("std");
const ash = @import("ashbloom");

const ma = ash.ma;

var data_buffer: [2048]f32 = undefined;

var sin_frame: f32 = 0;

fn dc_sin(_: *ma.Device, output: *anyopaque, _: *anyopaque, frame_count: u32) callconv(.c) void
{
    const pi = std.math.pi;

    for(0..frame_count) |i|
    {
        const value = std.math.sin(2.0 * pi * sin_frame * 400.0 / 48000.0) * 0.25;
        for(0..2) |j|
        {
            const index = i * 2 + j;
            data_buffer[index] = value;
        }
        sin_frame += 1;
    }

    ash.utils.misc.memcpy_anonymous(output, &data_buffer, frame_count * 2 * @sizeOf(f32));
}

pub fn main() !void
{
    var ma_context: *ma.Context = try .init();
    defer ma_context.uninit();

    const audio_device_list = try ma_context.get_devices();
    audio_device_list.print();

    var config: ma.Device.Config = .init(.Playback);

    config.playback.format = .Unknown;
    config.playback.channels = 0;
    config.sample_rate = 0;
    config.data_callback = dc_sin;
    config.user_data = null;

    var device: *ma.Device = try .init(null, &config);
    defer device.uninit();

    try device.start();

    while(sin_frame < 48000) {}

    device.stop();
}
