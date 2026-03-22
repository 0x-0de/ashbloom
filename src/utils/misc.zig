const std = @import("std");
const builtin = @import("builtin");

/// Implementation of C's memcpy(). Takes two anonymous pointers and a given byte size.
pub fn memcpy_anonymous(dst: *anyopaque, src: *anyopaque, size: usize) void
{
    const dest_data: [*]u8 = @as([*]u8, @ptrCast(dst));
    const copy_data: []u8 = @as([*]u8, @ptrCast(src))[0..size];
    @memcpy(dest_data, copy_data);
}

pub fn get_exe_path() []u8
{
    if(comptime builtin.os.tag == .windows)
    {
        const GetModuleFileName = @import("win32").system.library_loader.GetModuleFileNameA;

        var buffer: [4096]u8 = undefined;
        const len = GetModuleFileName(null, @as([*:0]u8, @ptrCast(&buffer)), 4096);

        return buffer[0..len];
    }
    else
    {
        @compileError("Your OS doesn't support the get_exe_path() function.");
    }
}