const std = @import("std");
const ash = @import("ashbloom");

const vorbis = ash.stb_vorbis;

const glfw = ash.glfw;
const ma = ash.ma;

const READ_BUFFER_SIZE = 8192;

fn print_vorbis_info(info: vorbis.VorbisInstance.Info) void
{
    std.debug.print("Vorbis info:\n", .{});
    std.debug.print("\tChannels: {d}\n", .{info.channels});
    std.debug.print("\tSample rate: {d}\n", .{info.sample_rate});
    std.debug.print("\tMax frame size: {d}\n", .{info.max_frame_size});
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
    _ = allocator;

    var v: *vorbis.VorbisInstance = try .open_filename("../../res/128 stereo.ogg");
    defer v.close();

    const info = v.get_info();
    print_vorbis_info(info);

    while(true)
    {
        const frame = try v.get_frame_float();

        std.debug.print("New frame.\n\tChannels: {d}\n\tNum samples: {d}\n", .{frame.num_channels, frame.num_samples_per_channel});

        if(frame.num_samples_per_channel == 0)
        {
            break;
        }

        const channels = frame.ptr[0..frame.num_channels];
        for(0..channels.len) |i|
        {
            std.debug.print("\t\tChannel {d}\n", .{i + 1});
            const samples = channels[i][0..frame.num_samples_per_channel];
            std.debug.print("\t\tSize: {d} samples.\n", .{samples.len});
            if(samples.len >= 10)
            {
                std.debug.print("\t\t", .{});
                for(0..10) |j|
                {
                    std.debug.print("{d} ", .{samples[j]});
                }
                std.debug.print("\n", .{});
            }
        }
    }
}
