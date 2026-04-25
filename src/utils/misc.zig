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
        const unistd = @cImport({
            @cInclude("unistd.h");
        });

        var buffer: [4096]u8 = undefined;
        const len = unistd.readlink("/proc/self/exe", @as([*:0]u8, @ptrCast(&buffer)), 4096 - 1);

        return buffer[0..len];
    }
    else
    {
        @compileError("Your OS doesn't support the get_exe_path() function.");
    }
}

/// Contains data about an individual font file.
pub const FontEntry = struct
{
    name: []u8,
    path: []u8,

    pub fn deinit(self: *FontEntry, allocator: *const std.mem.Allocator) void
    {
        allocator.free(self.name);
        allocator.free(self.path);
    }
};

/// Contains data about a family of font files.
pub const FontFamily = struct
{
    name: []u8,
    fonts: []FontEntry,

    pub fn deinit(self: *FontFamily, allocator: *const std.mem.Allocator) void
    {
        for(self.fonts) |font|
        {
            font.deinit(allocator);
        }

        allocator.free(self.name);
        allocator.free(self.fonts);
    }
};

/// Enumarates the available system fonts. Returns a dynamically-allocated array that must be freed if no errors are thrown.
pub fn enumerate_system_fonts(allocator: *const std.mem.Allocator) ![]FontEntry
{
    if(comptime builtin.os.tag == .windows)
    {
        const prefix_str: *const [17:0]u8 = "C:\\Windows\\Fonts\\";
        var dir = try std.fs.openDirAbsolute(prefix_str, .{
            .iterate = true
        });

        defer dir.close();

        var walker = try dir.walk(allocator.*);
        defer walker.deinit();

        var font_list = try std.ArrayList(FontEntry).initCapacity(allocator.*, 0);
        defer font_list.deinit(allocator.*);

        while(try walker.next()) |entry|
        {
            const is_font = std.mem.endsWith(u8, entry.path, ".ttf") or std.mem.endsWith(u8, entry.path, ".otf");
            if(entry.kind == .file and is_font)
            {
                const name = try allocator.alloc(u8, entry.path.len - 4);
                for(0..name.len) |i|
                {
                    name[i] = entry.path[i];
                }

                const path = try allocator.alloc(u8, entry.path.len + prefix_str.len);
                
                for(0..prefix_str.len) |i|
                {
                    path[i] = prefix_str[i];
                }

                for(0..entry.path.len) |i|
                {
                    path[i + prefix_str.len] = entry.path[i];
                }

                const font_entry: FontEntry = .{
                    .name = name,
                    .path = path
                };

                try font_list.append(allocator.*, font_entry);
            }
        }

        const data = try allocator.alloc(FontEntry, font_list.items.len);

        for(font_list.items, 0..) |item, i|
        {
            data[i] = item;
        }

        return data;
    }
    else
    {
        @compileError("Your OS doesn't support the enumerate_system_fonts() function.");
    }
}

pub const FontSearchError = error
{
    MissingFont
};

pub fn search_font_entries(available_fonts: []FontEntry, names: []const []const u8) FontSearchError!FontEntry
{
    for(names) |term|
    {
        for(available_fonts) |font|
        {
            if(std.mem.eql(u8, term, font.name))
            {
                return font;
            }
        }
    }

    return FontSearchError.MissingFont;
}

