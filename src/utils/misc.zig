/// Implementation of C's memcpy(). Takes two anonymous pointers and a given byte size.
pub fn memcpy_anonymous(dst: *anyopaque, src: *anyopaque, size: usize) void
{
    const dest_data: [*]u8 = @as([*]u8, @ptrCast(dst));
    const copy_data: []u8 = @as([*]u8, @ptrCast(src))[0..size];
    @memcpy(dest_data, copy_data);
}