const std = @import("std");
const builtin = @import("builtin");

/// Implementation of C's memcpy(). Takes two anonymous pointers and a given byte size.
pub fn memcpy_anonymous(dst: *anyopaque, src: *anyopaque, size: usize) void
{
    const dest_data: [*]u8 = @as([*]u8, @ptrCast(dst));
    const copy_data: []u8 = @as([*]u8, @ptrCast(src))[0..size];
    @memcpy(dest_data, copy_data);
}

/// Returns the path of the emitted .exe file (implementation is OS-specific, only works on Windows & Linux for now).
pub fn get_exe_path() []u8
{
    if(comptime builtin.os.tag == .windows)
    {
        const win32 = @import("win32");
        const GetModuleFileName = win32.system.library_loader.GetModuleFileNameA;

        var buffer: [4096]u8 = undefined;
        const len = GetModuleFileName(null, @as([*:0]u8, @ptrCast(&buffer)), 4096);

        return buffer[0..len];
    }
    else if(comptime builtin.os.tag == .linux)
    {
        const unistd = @cImport("unistd.h");

        var buffer: [4096]u8 = undefined;
        const len = unistd.readlink("/proc/self/exe", @as([*:0]u8, @ptrCast(&buffer)), 4096 - 1);

        return buffer[0..len];
    }
    else
    {
        @compileError("Your OS doesn't support the get_exe_path() function.");
    }
}