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

    try ash.audio.init(&allocator);
    defer ash.audio.deinit(&allocator);

    // For the stdout console.
    try ash.init(&allocator);
    defer ash.deinit();

    var current_play: usize = 0;
    var current_round: usize = 0;

    var decoders: [6]ash.audio.decoders.WAVDecoder = .{
        try ash.audio.decoders.WAVDecoder.init(&allocator, "../../res/i16 mono.wav"),
        try ash.audio.decoders.WAVDecoder.init(&allocator, "../../res/i16 stereo.wav"),
        try ash.audio.decoders.WAVDecoder.init(&allocator, "../../res/i24 mono.wav"),
        try ash.audio.decoders.WAVDecoder.init(&allocator, "../../res/i24 stereo.wav"),
        try ash.audio.decoders.WAVDecoder.init(&allocator, "../../res/f32 mono.wav"),
        try ash.audio.decoders.WAVDecoder.init(&allocator, "../../res/f32 stereo.wav")
    };

    var source: ash.audio.SoundNode = try .init(&allocator);
    defer source.deinit();

    try ash.audio.add_output_node(&allocator, &source);

    while(true)
    {
        if(source.producers.items.len == 0)
        {
            if(current_play == 6)
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

    for(&decoders) |*d|
    {
        d.deinit();
    }
}
