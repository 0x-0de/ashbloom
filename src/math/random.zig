//! Handles random number and noise generation.
const std = @import("std");
const misc = @import("../utils/misc.zig");

const interp = @import("interp.zig");

const permutations: [256]u8 = .{
    144, 219, 232, 110, 171, 202, 50,  242, 55,  148, 87,  6,   12,  152, 143, 21,
    27,  195, 180, 249, 79,  139, 134, 98,  103, 37,  41,  125, 213, 48,  159, 160,
    10,  46,  128, 157, 236, 181, 124, 168, 251, 184, 19,  149, 54,  189, 61,  127,
    138, 105, 16,  145, 76,  210, 113, 169, 94,  252, 255, 158, 246, 156, 175, 65,
    203, 64,  225, 18,  17,  142, 30,  226, 71,  137, 118, 13,  216, 59,  126, 116,
    194, 186, 174, 45,  234, 97,  220, 217, 206, 235, 182, 170, 153, 106, 4,   114,
    166, 237, 108, 7,   36,  26,  177, 223, 243, 163, 164, 141, 66,  212, 28,  197,
    86,  240, 63,  132, 211, 227, 57,  104, 0,   72,  39,  58,  123, 221, 2,   228,
    62,  214, 229, 218, 99,  101, 112, 11,  207, 75,  32,  47,  196, 68,  42,  34,
    92,  85,  190, 43,  135, 154, 247, 173, 215, 80,  15,  90,  131, 84,  31,  51,
    187, 230, 172, 24,  40,  198, 115, 222, 8,   14,  60,  29,  23,  53,  204, 73,
    25,  9,   136, 117, 130, 241, 83,  74,  248, 5,   70,  208, 201, 82,  38,  147,
    56,  81,  183, 52,  121, 185, 1,   253, 91,  49,  96,  67,  111, 233, 188, 179,
    151, 119, 109, 95,  254, 167, 77,  176, 122, 44,  93,  238, 35,  245, 165, 205,
    200, 146, 239, 161, 100, 88,  209, 244, 120, 3,   231, 102, 193, 78,  155, 162,
    140, 20,  191, 199, 150, 224, 133, 178, 250, 89,  33,  129, 22,  69,  107, 192
};

/// Returns a random integer value generated using the seed values. Type T must be an int of no greater than 256 bits.
pub fn random_int(comptime T: type, comptime seed_count: u8, seeds: [seed_count]u256) T
{
    if(@typeInfo(T) != .int or @sizeOf(T) > 32)
    {
        @compileError("random_int return type isn't a valid integer type.");
    }

    const initial_bitstr: u256 = 0xdeef1d50602d630a240530cf3e4484f042ba4bf187067fb17e813480fc335823;
    var value: T = @truncate(misc.wrapping_leftshift(u256, initial_bitstr, permutations[@truncate(seeds[0] & 255)]));

    for(0..3) |_|
    {
        for(seeds) |s|
        {
            var ts: T = @truncate(s);
            ts = misc.wrapping_leftshift(T, ts, (value ^ ts));
            value +%= ts;
            const p_index: u8 = @truncate(ts & 255);
            value = misc.wrapping_rightshift(T, value, permutations[p_index]);
            value ^= ts;
        }
    }

    return value;
}

/// Returns a random float between two boundary values. Type T must be a float of no greater than 256 bits.
pub fn random_float(comptime T_float: type, comptime T_int: type, comptime seed_count: u8, seeds: [seed_count]u256, min: T_float, max: T_float) T_float
{
    if(@typeInfo(T_float) != .float or @sizeOf(T_float) > 32)
    {
        @compileError("random_float return type isn't a value floating-point type.");
    }

    const r = random_int(T_int, seed_count, seeds);
    var fr: T_float = @floatFromInt(r);
    fr /= std.math.maxInt(T_int);

    const bounds = max - min;

    const value = fr * bounds + min;
    std.debug.assert(value >= min and value <= max);
    return value;
}

/// Properties used for generating value noise.
pub const NoiseProperties = struct
{
    /// Number of layers of detail to generate.
    octaves: u8,

    /// Controls how much each additional layer of noise scales down.
    focus: f64,
    /// Controls how much each additional layer should add to the noise.
    persistance: f64
};

/// Returns a value noise value, between -1 and 1 (inclusive). Generated along one axis.
pub fn value_noise_1d(seed: u256, x: f64, properties: NoiseProperties) f64
{
    var value: f64 = 0;

    var scale: f64 = 1;
    var division_factor: f64 = 0;
    var mult_factor: f64 = 1;
    
    for(0..properties.octaves) |_|
    {
        const xs = x * scale;

        const ax: f64 = @floor(xs);
        const bx: f64 = @ceil(xs);

        const axi: u256 = @intFromFloat(ax);
        const bxi: u256 = @intFromFloat(bx);

        const ar = @as(f64, random_float(f128, u64, 2, .{seed, axi}, -1, 1));
        if(ax == bx)
        {
            value += ar * mult_factor;
        }
        else
        {
            const br = @as(f64, random_float(f128, u64, 2, .{seed, bxi}, -1, 1));
            const dx = xs - ax;

            value += interp.linear(f64, ar, br, dx) * mult_factor;
        }

        division_factor += mult_factor;
        mult_factor *= properties.persistance;
        scale *= properties.focus;
    }

    return value / division_factor;
}

/// Returns a value noise value, between -1 and 1 (inclusive). Generated along two axes.
pub fn value_noise_2d(seed: u256, x: f64, y: f64, properties: NoiseProperties) f64
{
    var value: f64 = 0;

    var scale: f64 = 1;
    var division_factor: f64 = 0;
    var mult_factor: f64 = 1;
    
    for(0..properties.octaves) |_|
    {
        const xs = x * scale;
        const ys = y * scale;

        const ax: f64 = @floor(xs);
        const bx: f64 = @ceil(xs);

        const ay: f64 = @floor(ys);
        const by: f64 = @ceil(ys);

        const axi: u256 = @intFromFloat(ax);
        const bxi: u256 = @intFromFloat(bx);

        const ayi: u256 = @intFromFloat(ay);
        const byi: u256 = @intFromFloat(by);
        
        const aa = @as(f64, @floatCast(random_float(f128, u64, 3, .{seed, axi, ayi}, -1, 1)));
        std.debug.assert(aa <= 1 and aa >= -1);

        if(ax == bx and ay == by)
        {
            value += aa * mult_factor;
        }
        else
        {
            if(ay == by)
            {
                const ba = @as(f64, @floatCast(random_float(f128, u64, 3, .{seed, bxi, ayi}, -1, 1)));
                const dx = xs - ax;

                std.debug.assert(ba <= 1 and ba >= -1);
                value += interp.linear(f64, aa, ba, dx) * mult_factor;
            }
            else if(ax == bx)
            {
                const ab = @as(f64, @floatCast(random_float(f128, u64, 3, .{seed, axi, byi}, -1, 1)));
                const dy = ys - ay;

                std.debug.assert(ab <= 1 and ab >= -1);
                value += interp.linear(f64, aa, ab, dy) * mult_factor;
            }
            else
            {
                const ba = @as(f64, @floatCast(random_float(f128, u64, 3, .{seed, bxi, ayi}, -1, 1)));
                const ab = @as(f64, @floatCast(random_float(f128, u64, 3, .{seed, axi, byi}, -1, 1)));
                const bb = @as(f64, @floatCast(random_float(f128, u64, 3, .{seed, bxi, byi}, -1, 1)));

                std.debug.assert(ba <= 1 and ba >= -1);
                std.debug.assert(ab <= 1 and ab >= -1);
                std.debug.assert(bb <= 1 and bb >= -1);

                const dx = xs - ax;
                const dy = ys - ay;

                value += interp.linear_2d(f64, aa, ba, ab, bb, dx, dy) * mult_factor;
            }
        }

        division_factor += mult_factor;
        mult_factor *= properties.persistance;
        scale *= properties.focus;
    }

    std.debug.assert(@abs(value) <= division_factor);
    return value / division_factor;
}
