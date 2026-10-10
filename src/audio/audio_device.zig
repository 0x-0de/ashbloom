const std = @import("std");
const ash = @import("ashbloom");

const ma = ash.miniaudio;

/// Stores information relating to a stream of audio data, whether it be an input/output device, or an audio file.
pub const Format = struct
{
    sample_type: ma.Format,
    sample_rate: u32,
    channels: u32,

    pub fn init_decoder(decoder: *ma.Decoder) Format
    {
        var sample_type: ma.Format = undefined;
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

    pub fn init_device(device: *ma.Device) Format
    {
        return .{
            .sample_type = device.getPlaybackFormat(),
            .sample_rate = device.getSampleRate(),
            .channels = device.getPlaybackChannels()
        };
    }

    pub fn print_info(self: Format) void
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

pub const Device = struct
{
    
};
