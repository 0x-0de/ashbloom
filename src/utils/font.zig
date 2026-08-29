//! Handles loading fonts and font characters.

const std = @import("std");

const images = @import("image_utils.zig");
const ui = @import("vkui.zig");

const freetype = ui.freetype;

const VkInterface = @import("../rendering/vkcontext.zig").VkInterface;
const VulkanAllocator = @import("vkmemory.zig").VulkanAllocator;

const Texture2D = images.Texture2D;
const TextureAtlas2D = images.TextureAtlas2D;

pub const FontError = error
{
    /// Ashbloom's UI is uninititalized (remember to call ash.ui.init()).
    UIisUninitialized,
    /// Failure to load a font file.
    FailedToLoadFont,
    /// Failure to load a character into a font.
    FailedToLoadGlyph,
    /// `atlas` is `null`.
    NoAtlas
};

/// Stores information relating to a single font character loaded with `request`.
pub const FontCharacter = struct
{
    /// Unicode value of the character.
    unicode: u32,
    /// Pixel size of the character.
    size: c_uint,
    /// Location of the character in the font's atlas.
    suballocation: TextureAtlas2D.TextureSuballocation,
    /// Indicates how many pixels the next character should "advance" to after this one (used in text rendering).
    advance: u16,
    /// Indicates the pixel x-offset of the character (used in text rendering).
    bearing_x: i16,
    /// Indicates the pixel y-offset of the character (used in text rendering).
    bearing_y: u16
};

/// Stores and performs font loading operations.
pub const Font = struct
{
    /// Vulkan interface.
    interface: *VkInterface,
    /// Vulkan allocator.
    vk_allocator: *VulkanAllocator,

    /// FreeType typeface object.
    typeface: freetype.FT_Face,
    /// Current pixel size of any new requested characters.
    typesize: c_uint,

    /// Texture atlas to load the font characters onto.
    atlas: ?*TextureAtlas2D,
    /// List of all characters added to this font instance.
    characters: std.ArrayList(FontCharacter),

    /// Adds a unicode character directly to the atlas.
    fn add_unicode_glyph(self: *Font, unicode: u32) !FontCharacter
    {
        if(self.atlas == null)
        {
            return FontError.NoAtlas;
        }

        if(freetype.FT_Load_Char(self.typeface, unicode, freetype.FT_LOAD_RENDER) != 0)
        {
            return FontError.FailedToLoadGlyph;
        }

        const bitmap = self.typeface.*.glyph.*.bitmap;
        
        const width = bitmap.width;
        const height = bitmap.rows;

        const buffer = try self.interface.allocator.alloc(u8, (width + 1) * (height + 1) * 4);
        for(0..height + 1) |y|
        {
            const row = (height + 1) - y - 1;
            for(0..width + 1) |x|
            {
                const i = x + row * width;
                const buf = x + y * (width + 1);

                buffer[buf * 4 + 0] = 255;
                buffer[buf * 4 + 1] = 255;
                buffer[buf * 4 + 2] = 255;
                buffer[buf * 4 + 3] = if(x < width and y > 0) bitmap.buffer[i] else 0;
            }
        }

        var texture = try Texture2D.init_buffer(self.interface, self.vk_allocator, u8, buffer, width + 1, height + 1,
        .a8b8g8r8_uint_pack32, .Subtexture);
        
        var suballocation = try self.atlas.?.add_texture(&texture);

        suballocation.pos_y += 1.0 / @as(f32, @floatFromInt(self.atlas.?.height));

        suballocation.scl_x -= 1.0 / @as(f32, @floatFromInt(self.atlas.?.width));
        suballocation.scl_y -= 1.0 / @as(f32, @floatFromInt(self.atlas.?.height));

        self.interface.allocator.free(buffer);
        texture.deinit();

        const character: FontCharacter = .{
            .unicode = unicode,
            .size = self.typesize,
            .suballocation = suballocation,
            .advance = @truncate(@as(u16, @intCast(self.typeface.*.glyph.*.advance.x)) >> 6),
            .bearing_x = @truncate(@as(i16, @intCast(self.typeface.*.glyph.*.bitmap_left))),
            .bearing_y = @truncate(@as(u16, @intCast(self.typeface.*.glyph.*.bitmap_top)))
        };

        return character;
    }

    /// Deinitializes the font class and releases all resources.
    pub fn deinit(self: *Font) void
    {
        self.characters.deinit(self.interface.allocator.*);
        _ = freetype.FT_Done_Face(self.typeface);
    }

    /// Initializes the font class. If `atlas` is null, it will need to be set before `request` is called.
    pub fn init(interface: *VkInterface, vk_allocator: *VulkanAllocator, path: []const u8, size: c_uint, atlas: ?*TextureAtlas2D) !Font
    {
        if(!ui.initialized) return FontError.UIisUninitialized;

        var font: Font = .{
            .interface = interface,
            .vk_allocator = vk_allocator,
            .typeface = undefined,
            .typesize = size,
            .atlas = atlas, 
            .characters = try std.ArrayList(FontCharacter).initCapacity(interface.allocator.*, 0)
        };

        const c_path_slc = try interface.allocator.alloc(u8, path.len + 1);
        defer interface.allocator.free(c_path_slc);

        for(0..path.len) |i|
        {
            c_path_slc[i] = path[i];
        }

        c_path_slc[path.len] = 0;

        if(freetype.FT_New_Face(ui.ft, @as([*:0]const u8, @ptrCast(c_path_slc.ptr)), 0, &font.typeface) != 0)
        {
            return FontError.FailedToLoadFont;
        }

        font.set_font_size(size);

        return font;
    }

    /// Requests a unicode character to be added to the font.
    /// If the character is already available, then the associated `FontCharacter` is returned. Otherwise, a new one is allocated from the `atlas` and added to `characters` before being returned.
    pub fn request(self: *Font, unicode: u32, size: f32) !FontCharacter
    {
        for(self.characters.items) |ch|
        {
            if(ch.unicode == unicode and ch.size == @as(c_uint, @intFromFloat(size)))
            {
                return ch;
            }
        }

        const ch = try self.add_unicode_glyph(unicode);
        try self.characters.append(self.interface.allocator.*, ch);

        return ch;
    }

    /// Updates the `typesize`. This change only applies to new requested characters, currently held ones will maintain their current sizes.
    /// You can request the same character(s) in multiple sizes.
    pub fn set_font_size(self: *Font, size: c_uint) void
    {
        self.typesize = size;
        _ = freetype.FT_Set_Pixel_Sizes(self.typeface, 0, size);
    }
};

comptime
{
    _ = Font;
}
