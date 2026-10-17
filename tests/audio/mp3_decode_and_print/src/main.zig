const std = @import("std");
const ash = @import("ashbloom");

const minimp3 = ash.minimp3;

const glfw = ash.glfw;
const ma = ash.ma;

const READ_BUFFER_SIZE = 8192;

fn print_frame_info(frame: minimp3.MP3FrameInfo) void
{
    std.debug.print("Frame info:\n", .{});
    std.debug.print("\tSize (in bytes): {d}\n", .{frame.frame_bytes});
    std.debug.print("\tOffset (in bytes): {d}\n", .{frame.frame_offset});
    std.debug.print("\tChannels: {d}\n", .{frame.channels});
    std.debug.print("\tSample rate: {d}\n", .{frame.hz});
    std.debug.print("\tMPEG Layer: {d}\n", .{frame.layer});
    std.debug.print("\tBitrate (kbps): {d}\n", .{frame.bitrate_kbps});
}

pub fn main() !void
{
    var dbg_alloc: std.heap.DebugAllocator(.{}) = .init;
    defer
    {
        const status = dbg_alloc.deinit();
        if(status == .leak)
        {
            @panic("Program terminating with memory leaks!");
        }
    }

    const allocator = dbg_alloc.allocator();

    var input_buffer: [READ_BUFFER_SIZE]u8 = undefined;

    var io_threaded: std.Io.Threaded = .init(allocator, .{});
    defer io_threaded.deinit();

    const io = io_threaded.io();

    const cwd = std.Io.Dir.cwd();
    var mp3_file = try cwd.openFile(io, "../../res/128 stereo.mp3", .{ .mode = .read_only });
    defer mp3_file.close(io);

    var mp3_reader = mp3_file.reader(io, &input_buffer);
    const file_size = try mp3_reader.getSize();

    const reader = &mp3_reader.interface;

    var mp3_decoder: minimp3.MP3Decoder = .init();
    var mp3_frame: minimp3.MP3FrameInfo = undefined;

    var pcm_output: [minimp3.MAX_SAMPLES_PER_FRAME]f32 = undefined;

    var has_more_frames = true;
    var current_frame: usize = 1;

    var read: []u8 = undefined;
    while(has_more_frames)
    {
        const file_read_amnt = @min(file_size - mp3_reader.pos, READ_BUFFER_SIZE);
        if(file_read_amnt > 0)
            read = try reader.peek(file_read_amnt);

        const samples = mp3_decoder.decode_frame(read, &pcm_output, &mp3_frame);

        std.debug.print("Frame {d}\n", .{current_frame});
        std.debug.print("Seek: {d} bytes.\n", .{reader.seek});
        std.debug.print("Number of samples: {d}.\n", .{samples});
        print_frame_info(mp3_frame);

        std.debug.print("Samples: ", .{});
        for(0..10) |i|
        {
            std.debug.print("{d} ", .{pcm_output[i]});
        }
        std.debug.print("[end]\n", .{});

        const frame_size: usize = @intCast(mp3_frame.frame_bytes);

        reader.toss(frame_size);
        read = read[frame_size..];

        has_more_frames = mp3_frame.frame_bytes != 0;
        current_frame += 1;
    }
}
