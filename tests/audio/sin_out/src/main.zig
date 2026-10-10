const std = @import("std");
const ash = @import("ashbloom");

const ma = ash.ma;

var data_buffer: [2048]f32 = undefined;

var sin_frame: f32 = 0;

fn produce_sin(output: *const []f32, _: ?*anyopaque) void
{
    const pi = std.math.pi;
    const value = std.math.sin(2.0 * pi * sin_frame * 400.0 / 48000.0) * 0.25;

    for(output.*) |*o|
    {
        o.* = value;
    }

    sin_frame += 1;
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

    try ash.init_audio(&allocator);
    defer ash.deinit_audio(&allocator);

    const producer: ash.audio.Producer = .{
        .generator = produce_sin
    };

    try ash.add_audio_producer(&allocator, producer);

    while(sin_frame < 48000) {}

    ash.remove_audio_producer(0);
}
