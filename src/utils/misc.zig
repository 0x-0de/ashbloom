const std = @import("std");
const builtin = @import("builtin");

/// Implementation of C's memcpy(). Takes two anonymous pointers and a given byte size.
pub fn memcpy_anonymous(dst: *anyopaque, src: *anyopaque, size: usize) void
{
    const dest_data: [*]u8 = @as([*]u8, @ptrCast(dst));
    const copy_data: []u8 = @as([*]u8, @ptrCast(src))[0..size];
    @memcpy(dest_data, copy_data);
}

/// Performs a wrapping left-shift.
pub fn wrapping_leftshift(comptime T: type, value: T, shift: usize) T
{
    const type_size = @sizeOf(T) << 8;
    const trunc_shift = shift % type_size;

    const overflow = value >> @truncate(type_size - trunc_shift);
    const product = value << @truncate(trunc_shift);

    return overflow | product;
}

/// Performs a wrapping right-shift.
pub fn wrapping_rightshift(comptime T: type, value: T, shift: usize) T
{
    const type_size = @sizeOf(T) << 8;
    return wrapping_leftshift(T, value, (type_size - shift));
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

        return buffer[0..@intCast(len)];
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

fn walk_font_directory(allocator: *const std.mem.Allocator, io: *std.Io.Threaded, dir: *std.Io.Dir, font_list: *std.ArrayList(FontEntry), prefix_str: []const u8) !void
{
    var walker = try dir.walk(allocator.*);
    defer walker.deinit();

    while(try walker.next(io.io())) |entry|
    {
        const is_font = std.mem.endsWith(u8, entry.path, ".ttf") or std.mem.endsWith(u8, entry.path, ".otf");
        if(entry.kind == .file and is_font)
        {
            var name_offset: usize = 0;
            for(0..entry.path.len) |i|
            {
                if(entry.path[i] == '/' or entry.path[i] == '\\')
                {
                    name_offset = i + 1;
                }
            }

            const name = try allocator.alloc(u8, entry.path.len - name_offset - 4);
            for(0..name.len) |i|
            {
                name[i] = entry.path[i + name_offset];
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
}

/// Enumarates the available system fonts. Returns a dynamically-allocated array that must be freed if no errors are thrown.
pub fn enumerate_system_fonts(allocator: *const std.mem.Allocator) ![]FontEntry
{
    if(comptime builtin.os.tag == .windows)
    {
        var io: std.Io.Threaded = .init(allocator.*, .{});
        defer io.deinit();

        var font_list = try std.ArrayList(FontEntry).initCapacity(allocator.*, 0);
        defer font_list.deinit(allocator.*);
        
        const prefix_str: *const [17:0]u8 = "C:\\Windows\\Fonts\\";
        var dir = try std.Io.Dir.openDirAbsolute(io.io(), prefix_str, .{
            .iterate = true
        });

        defer dir.close(io.io());

        try walk_font_directory(allocator, &io, &dir, &font_list, prefix_str);

        const data = try allocator.alloc(FontEntry, font_list.items.len);

        for(font_list.items, 0..) |item, i|
        {
            data[i] = item;
        }

        return data;
    }
    else if(comptime builtin.os.tag == .linux)
    {
        var io: std.Io.Threaded = .init(allocator.*, .{});
        defer io.deinit();

        var font_list = try std.ArrayList(FontEntry).initCapacity(allocator.*, 0);
        defer font_list.deinit(allocator.*);
        
        const prefix_str_otf: *const [26:0]u8 = "/usr/share/fonts/opentype/";
        var dir_otf = try std.Io.Dir.openDirAbsolute(io.io(), prefix_str_otf, .{
            .iterate = true
        });

        defer dir_otf.close(io.io());

        try walk_font_directory(allocator, &io, &dir_otf, &font_list, prefix_str_otf);

        const prefix_str_ttf: *const [26:0]u8 = "/usr/share/fonts/truetype/";
        var dir_ttf = try std.Io.Dir.openDirAbsolute(io.io(), prefix_str_ttf, .{
            .iterate = true
        });

        defer dir_ttf.close(io.io());

        try walk_font_directory(allocator, &io, &dir_ttf, &font_list, prefix_str_ttf);

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
