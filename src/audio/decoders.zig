const std = @import("std");
const ash = @import("../root.zig");

const AudioFormat = ash.audio.AudioFormat;

pub const WavDecoderError = error
{
    InvalidFormat,
    MissingDataBlock
};

/// Creates producers that read and export PCM data from .wav files.
pub const WavDecoder = struct
{
    allocator: *const std.mem.Allocator,
    io_threaded: *std.Io.Threaded,

    path: []const u8,

    format: AudioFormat,
    data_offset: usize,
    data_size: usize,

    file_buffer: [128]u8 = undefined,

    const Chunk = union(enum)
    {
        Junk: void,
        RiffHeader: void,
        WaveHeader: void,
        Format: AudioFormat,
        Data: struct { offset: usize, size: usize },
        Unknown: void
    };

    pub const Producer = struct
    {
        allocator: *const std.mem.Allocator,
        io_threaded: *std.Io.Threaded,

        format: AudioFormat,
        data_offset: usize,
        data_size: usize,
        read_offset: usize,

        file: std.Io.File,
        file_reader: std.Io.File.Reader,
        file_buffer: [128]u8 = undefined,

        pub fn deinit(context: *anyopaque) void
        {
            const self: *Producer = @ptrCast(@alignCast(context));
            self.file.close(self.io_threaded.io());

            self.allocator.destroy(self);
        }

        pub fn generate(context: *anyopaque, output: *const []f32, flags: ash.audio.Producer.GeneratorFlags) ash.audio.Producer.Result
        {
            const self: *Producer = @ptrCast(@alignCast(context));

            self.file_reader.seekTo(self.data_offset + self.read_offset) catch
            {
                std.debug.print("Failed to seek .wav file.\n", .{});
                return .Fail;
            };

            const reader = &self.file_reader.interface;
            const frame_size = self.format.get_frame_size();

            if(self.read_offset >= self.data_size)
            {
                return .EndOfStream;
            }

            const frame_bytes = reader.take(frame_size) catch
            {
                std.debug.print("Error reading .wav file frame!\n", .{});
                return .Fail;
            };

            switch(self.format.format)
            {
                .Unknown => {},
                .Unsigned8 => {
                    for(0..self.format.channels) |i|
                    {
                        var sample: f32 = @floatFromInt(frame_bytes[i]);
                        sample /= 128;
                        sample -= 1;

                        output.*[i] = sample;
                    }
                },
                .Signed16 => {
                    for(0..self.format.channels) |i|
                    {
                        var sample_int: i16 = undefined;
                        ash.utils.misc.memcpy_anonymous(&sample_int, frame_bytes.ptr + i * 2, 2);

                        const sample: f32 = @as(f32, @floatFromInt(sample_int)) / 32768;
                        output.*[i] = sample;
                    }
                },
                .Signed24 => {
                    for(0..self.format.channels) |i|
                    {
                        var sample_int: i24 = undefined;
                        ash.utils.misc.memcpy_anonymous(&sample_int, frame_bytes.ptr + i * 3, 3);

                        const sample: f32 = @as(f32, @floatFromInt(sample_int)) / 8388608;
                        output.*[i] = sample;
                    }
                },
                .Signed32 => {
                    for(0..self.format.channels) |i|
                    {
                        var sample_int: i32 = undefined;
                        ash.utils.misc.memcpy_anonymous(&sample_int, frame_bytes.ptr + i * 4, 4);

                        const sample: f32 = @as(f32, @floatFromInt(sample_int)) / 2147483648;
                        output.*[i] = sample;
                    }
                },
                .Float32 => {
                    for(0..self.format.channels) |i|
                    {
                        var sample: f32 = undefined;
                        ash.utils.misc.memcpy_anonymous(&sample, frame_bytes.ptr + i * 4, 4);

                        output.*[i] = sample;
                    }
                }
            }

            if(flags.sample_margin != 1) self.read_offset += self.format.get_frame_size();
            return .Success;
        }

        pub fn init(parent: WavDecoder) !Producer
        {
            const cwd = std.Io.Dir.cwd();
            const io = parent.io_threaded.io();

            var file = try cwd.openFile(io, parent.path, .{ .mode = .read_only });
            errdefer file.close(io);

            var wav_producer: Producer = .{
                .allocator = parent.allocator,
                .io_threaded = parent.io_threaded,
                .format = parent.format,
                .data_offset = parent.data_offset,
                .data_size = parent.data_size,
                .read_offset = 0,
                .file = file,
                .file_reader = undefined,
            };

            wav_producer.file_reader = file.reader(io, &wav_producer.file_buffer);

            return wav_producer;
        }

        pub fn interface(self: *Producer) ash.audio.Producer
        {
            return .{
                .channels = self.format.channels,
                .context = self,
                .deinit_fn = Producer.deinit,
                .generate_fn = generate,
                .sample_rate = self.format.sample_rate
            };
        }
    };

    pub fn deinit(self: *WavDecoder) void
    {
        self.io_threaded.deinit();
        self.allocator.destroy(self.io_threaded);
    }

    pub fn init(allocator: *const std.mem.Allocator, path: []const u8) !WavDecoder
    {
        const io_threaded = try allocator.create(std.Io.Threaded);
        io_threaded.* = std.Io.Threaded.init(allocator.*, .{});

        const io = io_threaded.io();

        var wav_decoder: WavDecoder = .{
            .allocator = allocator,
            .io_threaded = io_threaded,
            .path = path,
            .format = undefined,
            .data_offset = undefined,
            .data_size = undefined
        };

        const cwd = std.Io.Dir.cwd();

        var file = try cwd.openFile(io, path, .{ .mode = .read_only });
        defer file.close(io);

        var file_reader = file.reader(io, &wav_decoder.file_buffer);

        var found_format = false;
        var found_data_block = false;

        while(try read_next_wav_block(&file_reader)) |b|
        {
            switch(b)
            {
                .Junk, .RiffHeader, .WaveHeader, .Unknown => {},
                .Format => |f|
                {
                    wav_decoder.format = f;

                    found_format = true;
                },
                .Data => |d|
                {
                    wav_decoder.data_offset = d.offset;
                    wav_decoder.data_size = d.size;

                    found_data_block = true;

                    break;
                }
            }
        }

        if(!found_format) return WavDecoderError.InvalidFormat;
        if(!found_data_block) return WavDecoderError.MissingDataBlock;

        return wav_decoder;
    }

    pub fn new_producer(self: WavDecoder) !ash.audio.Producer
    {
        const producer = try self.allocator.create(Producer);
        producer.* = try .init(self);

        return producer.interface();
    }

    fn read_next_wav_block(file_reader: *std.Io.File.Reader) !?Chunk
    {
        const reader = &file_reader.interface;
        const header = try reader.take(4);

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
            const size_bytes = try reader.take(4);

            var size: u32 = undefined;
            ash.utils.misc.memcpy_anonymous(&size, size_bytes.ptr, @sizeOf(u32));

            try reader.discardAll(size);
            return .{ .Junk = @as(void, undefined) };
        }
        else if(std.mem.eql(u8, header, "fmt "))
        {
            const size_bytes = try reader.take(4);

            var size: u32 = undefined;
            ash.utils.misc.memcpy_anonymous(&size, size_bytes.ptr, @sizeOf(u32));

            const format_bytes = try reader.take(2);

            var format: u16 = undefined;
            ash.utils.misc.memcpy_anonymous(&format, format_bytes.ptr, 2);

            const channels_bytes = try reader.take(2);

            var channels: u16 = undefined;
            ash.utils.misc.memcpy_anonymous(&channels, channels_bytes.ptr, 2);

            const sample_rate_bytes = try reader.take(4);

            var sample_rate: u32 = undefined;
            ash.utils.misc.memcpy_anonymous(&sample_rate, sample_rate_bytes.ptr, 4);

            // Number of bytes to read per second -> sample rate * bytes per frame. Don't care.
            try reader.discardAll(4);

            // Number of bytes per frame. Don't care, we're about to get bits per sample.
            try reader.discardAll(2);

            const bits_per_sample_bytes = try reader.take(2);

            var bits_per_sample: u16 = undefined;
            ash.utils.misc.memcpy_anonymous(&bits_per_sample, bits_per_sample_bytes.ptr, 2);

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
        else if(std.mem.eql(u8, header, "data"))
        {
            const data_size_bytes = try reader.take(4);

            var data_size: u32 = undefined;
            ash.utils.misc.memcpy_anonymous(&data_size, data_size_bytes.ptr, 4);

            return .{ .Data = .{ .offset = file_reader.pos, .size = data_size } };
        }

        return .{ .Unknown = @as(void, undefined) };
    }
};
