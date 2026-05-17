//! Handles random number and noise generation.

pub fn random_int(comptime T: type, comptime seed_count: u8, seeds: [seed_count]u256) T
{
    if(@typeInfo(T) != .int or @sizeOf(T) <= 32)
    {
        @compileError("random_int return type isn't a valid integer type.");
    }

    const initial_bitstr: u256 = 0xdeef1d50602d630a240530cf3e4484f042ba4bf187067fb17e813480fc335823;
    var value: T = @truncate(initial_bitstr);

    
}
