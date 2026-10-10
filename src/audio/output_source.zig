const std = @import("std");
const ash = @import("ashbloom");

pub const AudioGenerator = *const fn(output: *const []f32, data: ?*anyopaque) void;

pub const Producer = struct
{
    generator: AudioGenerator
};
