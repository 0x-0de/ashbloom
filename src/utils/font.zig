const std = @import("std");

const images = @import("image_utils.zig");
const vkui = @import("vkui.zig");

const freetype = vkui.freetype;

const VkContext = @import("../rendering/vkcontext.zig").VkContext;
const VulkanAllocator = @import("vkmemory.zig").VulkanAllocator;

const Texture2D = images.Texture2D;
const TextureAtlas2D = images.TextureAtlas2D;

pub const FontError = error
{
    FailedToLoadFont,
    FailedToLoadGlyph
};

pub const FontCharacter = struct
{
    unicode: u32,
    size: c_uint,
    suballocation: TextureAtlas2D.TextureSuballocation,
    advance: u16,
    bearing_x: i16,
    bearing_y: u16
};

pub const Font = struct
{
    context: *VkContext,
    vk_allocator: *VulkanAllocator,

    typeface: freetype.FT_Face,
    typesize: c_uint,

    atlas: TextureAtlas2D,
    characters: std.ArrayList(FontCharacter),

    fn add_unicode_glyph(self: *Font, unicode: u32) !FontCharacter
    {
        if(freetype.FT_Load_Char(self.typeface, unicode, freetype.FT_LOAD_RENDER) != 0)
        {
            return FontError.FailedToLoadGlyph;
        }

        const bitmap = self.typeface.*.glyph.*.bitmap;
        
        const width = bitmap.width;
        const height = bitmap.rows;

        const buffer = try self.context.allocator.alloc(u8, (width + 1) * (height + 1) * 4);
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

        var texture = try Texture2D.init_buffer(self.context, self.vk_allocator, u8, buffer, width + 1, height + 1,
        .a8b8g8r8_uint_pack32, .Subtexture);
        
        var suballocation = try self.atlas.add_texture(&texture);

        suballocation.pos_y += 1.0 / @as(f32, @floatFromInt(self.atlas.height));

        suballocation.scl_x -= 1.0 / @as(f32, @floatFromInt(self.atlas.width));
        suballocation.scl_y -= 1.0 / @as(f32, @floatFromInt(self.atlas.height));

        self.context.allocator.free(buffer);
        try texture.deinit();

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

    pub fn deinit(self: *Font) !void
    {
        self.characters.deinit(self.context.allocator.*);
        try self.atlas.deinit();
        _ = freetype.FT_Done_Face(self.typeface);
    }

    pub fn init(context: *VkContext, vk_allocator: *VulkanAllocator, path: [*:0]const u8, size: c_uint) !Font
    {
        var font: Font = .{
            .context = context,
            .vk_allocator = vk_allocator,
            .typeface = undefined,
            .typesize = size,
            .atlas = try TextureAtlas2D.init(context, vk_allocator, 1024, 1024),
            .characters = try std.ArrayList(FontCharacter).initCapacity(context.allocator.*, 0)
        };

        if(freetype.FT_New_Face(vkui.ft, path, 0, &font.typeface) != 0)
        {
            return FontError.FailedToLoadFont;
        }

        font.set_font_size(size);

        return font;
    }

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
        try self.characters.append(self.context.allocator.*, ch);

        return ch;
    }

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
