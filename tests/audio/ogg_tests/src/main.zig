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

    var current_play: usize = 0;
    var current_round: usize = 0;

    var decoders: [4]ash.audio.decoders.VorbisDecoder = .{
        try .init(&allocator, "../../res/128 mono.ogg"),
        try .init(&allocator, "../../res/128 stereo.ogg"),
        try .init(&allocator, "../../res/192 mono.ogg"),
        try .init(&allocator, "../../res/192 stereo.ogg")
    };

    var source: ash.audio.OutputSource = try .init(&allocator);
    defer source.deinit();

    try ash.add_audio_source(&allocator, &source);

    while(true)
    {
        if(source.producers.items.len == 0)
        {
            if(current_play == decoders.len)
            {
                current_play = 0;
                current_round += 1;
            }
            if(current_round == 3)
            {
                break;
            }
            ash.print_stdout("File {d}\n", .{current_play + 1});
            try source.add_producer(try decoders[current_play].new_producer());
            current_play += 1;
        }
    }
}
