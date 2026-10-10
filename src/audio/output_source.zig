const std = @import("std");
const ash = @import("../root.zig");

const ma = ash.ma;

/// Specifies a format for a piece of audio data.
/// All audio is assumed to be stored in 32-bit floats expect for when the streams are about to be played back or are just being recorded.
pub const AudioFormat = struct
{
    /// Number of audio frames (samples * channels) processed per second.
    sample_rate: u32,
    /// Format (data type) that the audio is stored in.
    format: ma.Format,
    /// Number of channels that the audio stores.
    channels: u32
};

/// Audio generator function type. This function is responsible for producing an audio frame and writing it to `output`. Input data can be specified with `data`.
pub const AudioGenerator = *const fn(output: *const []f32, flags: Producer.Flags, data: ?*anyopaque) void;

/// Stores information relating to a source of output audio.
pub const Producer = struct
{
    /// Audio generator function.
    generator: AudioGenerator,
    /// Sample rate of the produced audio.
    sample_rate: u32,
    /// Number of channels (data points) the generator should produce per-frame.
    channels: u32,
    /// Optional pointer to some additional data which can facilitate the production of audio data.
    data: ?*anyopaque = null,

    /// Flags send to the AudioGenerator to clue it in on some details.
    pub const Flags = packed struct(u1)
    {
        /// If 1, then the current requested frame is likely the last requested frame of the current request order.
        /// It's also likely that the returned frame is going to be used as a margin to interpolate between the sample rate of this producer and of the audio source.
        /// Therefore, when the next request comes, it should start with this frame, not the next one. Make sure your generator function takes that into account.
        sample_margin: u1
    };

    /// Produces `frame_count` amount of audio frames. Returns a slice of audio frames, which are themselves slices of audio samples which each index representing an audio channel.
    /// The number of channels is specified in `self.format`.
    pub fn generate(self: Producer, allocator: *const std.mem.Allocator, frame_count: u32) ![][]f32
    {
        var data = try allocator.alloc([]f32, frame_count);
        for(0..frame_count) |i|
        {
            const flags: Flags = .{
                .sample_margin = if(i == frame_count - 1) 1 else 0
            };

            data[i] = try allocator.alloc(f32, self.channels);
            self.generator(&data[i], flags, self.data);
        }
        return data;
    }
};

fn convert_channels(allocator: *const std.mem.Allocator, input: [][]f32, export_channels: u32) ![][]f32
{
    const current_channels = input[0].len;

    var new_frames = try allocator.alloc([]f32, input.len);
    for(0..input.len) |i|
    {
        new_frames[i] = try allocator.alloc(f32, export_channels);
        if(export_channels == current_channels)
        {
            for(0..current_channels) |j|
            {
                new_frames[i][j] = input[i][j];
            }
        }
        else if(export_channels == 1)
        {
            var sum: f32 = 0;
            for(0..current_channels) |j|
            {
                sum += input[i][j];
            }
            sum /= @as(f32, @floatFromInt(current_channels));
            new_frames[i][0] = sum;
        }
        else if(current_channels == 1)
        {
            for(0..export_channels) |j|
            {
                new_frames[i][j] = input[i][0];
            }
        }
        else
        {
            const channel_space: f32 = @floatFromInt(current_channels - 1);
            const sample_spacing = channel_space / @as(f32, @floatFromInt(export_channels));
            const sample_offset: f32 = channel_space / @as(f32, @floatFromInt(export_channels * 2));

            for(0..export_channels) |j|
            {
                const channel_offset: f32 = @floatFromInt(j);

                const sample_point: f32 = sample_spacing * channel_offset + sample_offset;

                const bottom_sample = input[i][@floor(sample_point)];
                const top_sample = input[i][@ceil(sample_point)];

                if(bottom_sample == top_sample)
                {
                    new_frames[i][j] = bottom_sample;
                }
                else
                {
                    const new_sample = ash.math.interp.linear(f32, bottom_sample, top_sample, sample_point - @floor(sample_point));
                    new_frames[i][j] = new_sample;
                }
            }
        }
    }

    return new_frames;
}

fn convert_sample_rate(allocator: *const std.mem.Allocator, input: [][]f32, current_sample_rate: u32, export_sample_rate: u32) ![][]f32
{
    const inverted_sample_ratio: f32 = @as(f32, @floatFromInt(export_sample_rate)) / @as(f32, @floatFromInt(current_sample_rate));
    const sample_jump: f32 = @as(f32, @floatFromInt(current_sample_rate)) / @as(f32, @floatFromInt(export_sample_rate));

    const number_of_converted_samples: usize = @round(@as(f32, @floatFromInt(input.len - 1)) * inverted_sample_ratio);
    var sample_offset: f32 = 0;

    const channels = input[0].len;

    var new_frames = try allocator.alloc([]f32, number_of_converted_samples);
    for(0..number_of_converted_samples) |i|
    {
        new_frames[i] = try allocator.alloc(f32, channels);
        //ash.print_stdout("Converted sample {d} of {d}\nRaw sample offset: {d}\n", .{(i + 1), number_of_converted_samples, sample_offset});
        for(0..channels) |j|
        {
            const bottom_sample = input[@floor(sample_offset)][j];
            const top_sample = input[@ceil(sample_offset)][j];

            if(bottom_sample == top_sample)
            {
                new_frames[i][j] = bottom_sample;
            }
            else
            {
                const new_sample = ash.math.interp.linear(f32, bottom_sample, top_sample, sample_offset - @floor(sample_offset));
                new_frames[i][j] = new_sample;
            }
        }
        sample_offset += sample_jump;
    }

    return new_frames;
}

/// Handles a list of audio producers, automatically removing them when the end signal is given, and transforms them into the output audio format.
pub const OutputSource = struct
{
    /// Allocator handle.
    allocator: *const std.mem.Allocator,
    /// List of producers.
    producers: std.ArrayList(Producer),
    /// Playback sample rate.
    export_sample_rate: u32,
    /// Playback number of channels.
    export_channels: u32,

    /// Adds a producer to the output source. This will begin generating audio immediately.
    pub fn add_producer(self: *OutputSource, producer: Producer) !void
    {
        try self.producers.append(self.allocator.*, producer);
    }

    /// Deinitializes the OutputSource.
    pub fn deinit(self: *OutputSource) void
    {
        self.producers.deinit(self.allocator.*);
    }

    /// Initializes a new OutputSource.
    pub fn init(allocator: *const std.mem.Allocator) !OutputSource
    {
        return .{
            .allocator = allocator,
            .producers = try .initCapacity(allocator.*, 0),
            .export_sample_rate = undefined,
            .export_channels = undefined
        };
    }

    /// Pull a required amount of audio data. Performs sample rate and channel conversions.
    pub fn pull_audio(self: OutputSource, frame_count: u32) ![][]f32
    {
        var data = try self.allocator.alloc([]f32, frame_count);
        for(0..frame_count) |i|
        {
            data[i] = try self.allocator.alloc(f32, self.export_channels);
            for(0..self.export_channels) |j|
            {
                data[i][j] = 0;
            }
        }

        for(self.producers.items) |p|
        {
            const current_sample_rate: f32 = @floatFromInt(p.sample_rate);
            const export_rate: f32 = @floatFromInt(self.export_sample_rate);

            const sample_ratio = current_sample_rate / export_rate;
            const raw_frames_float = @as(f32, @floatFromInt(frame_count)) * sample_ratio;
            const number_of_raw_frames: u32 = @as(u32, @round(raw_frames_float)) + 1; // Need one additional sample for interpolation.

            const producer_raw_data = try p.generate(self.allocator, number_of_raw_frames);
            const converted_sample_rate_data = try convert_sample_rate(self.allocator, producer_raw_data, p.sample_rate, self.export_sample_rate);

            std.debug.assert(converted_sample_rate_data.len == frame_count);

            for(0..number_of_raw_frames) |i|
            {
                self.allocator.free(producer_raw_data[i]);
            }
            self.allocator.free(producer_raw_data);

            const converted_channel_data = try convert_channels(self.allocator, converted_sample_rate_data, self.export_channels);

            for(0..frame_count) |i|
            {
                self.allocator.free(converted_sample_rate_data[i]);
            }
            self.allocator.free(converted_sample_rate_data);

            for(0..frame_count) |i|
            {
                for(0..self.export_channels) |j|
                {
                    data[i][j] += converted_channel_data[i][j];
                }
            }

            for(0..frame_count) |i|
            {
                self.allocator.free(converted_channel_data[i]);
            }
            self.allocator.free(converted_channel_data);
        }

        return data;
    }
};
