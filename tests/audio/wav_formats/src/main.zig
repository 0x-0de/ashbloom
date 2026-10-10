const std = @import("std");
const ash = @import("ashbloom");

const ma = ash.ma;

const SAMPLE_RATE = 44100.0;

var data_buffer: [2048]f32 = undefined;

var sin_frame: f32 = 0;

fn produce_sin(output: *const []f32, flags: ash.audio.Producer.Flags, _: ?*anyopaque) void
{
    const pi = std.math.pi;
    const value = std.math.sin(2.0 * pi * sin_frame * 400.0 / SAMPLE_RATE) * 0.25;

    for(output.*) |*o|
    {
        o.* = value;
    }

    if(flags.sample_margin != 1) sin_frame += 1;
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

    // For the stdout console.
    try ash.init_graphics(&allocator);
    defer ash.deinit_graphics();

    const producer: ash.audio.Producer = .{
        .generator = produce_sin,
        .sample_rate = SAMPLE_RATE,
        .channels = 1
    };

    var source: ash.audio.OutputSource = try .init(&allocator);
    defer source.deinit();

    try source.add_producer(producer);

    try ash.add_audio_source(&allocator, &source);

    while(sin_frame < SAMPLE_RATE) {}

    ash.remove_audio_source(0);
}
