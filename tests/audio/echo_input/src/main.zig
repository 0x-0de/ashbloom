const std = @import("std");
const ash = @import("ashbloom");

const glfw = ash.glfw;
const ma = ash.ma;

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

    const input_producer = ash.input_producer();

    var source: ash.audio.SoundNode = try .init(&allocator);
    defer source.deinit();
    
    var vt: ash.audio.transforms.VolumeTransform = .{
        .volume = 0.75
    };

    try source.add_producer(input_producer);

    try source.add_transform(vt.transform());

    try ash.audio.add_output_node(&allocator, &source);

    while(true)
    {

    }
}
