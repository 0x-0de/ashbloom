const std = @import("std");
const glfw = @import("glfw");

const ash = @import("../../root.zig");

const vk = @import("vulkan");

const imp_font = @import("../font.zig");

const vkui = @import("../vkui.zig");
const math = @import("../../math/linalg.zig");

const Font = imp_font.Font;
const FontCharacter = imp_font.FontCharacter;

const Container = vkui.Container;
const Element = vkui.Element;
const Placement = vkui.Placement;
const ContainerInputData = vkui.ContainerInputData;

const VkContext = @import("../../rendering/vkcontext.zig").VkContext;
const Swapchain = @import("../../rendering/swapchain.zig").Swapchain;
const RenderPass = @import("../../rendering/renderpass.zig").RenderPass;

const pipeline = @import("../../rendering/pipeline.zig");

const Pipeline = pipeline.Pipeline;
const PipelineDescriptorSet = pipeline.PipelineDescriptorSet;

const VulkanAllocator = @import("../vkmemory.zig").VulkanAllocator;

const memcpy_anonymous = @import("../misc.zig").memcpy_anonymous;

const BasicUIElementType = enum
{
    Quad,
    Icon,
    TextCharacter,
    Text,
    Button,
    Scrollbar,
    Checkbox,
    Slider,
    Textfield
};

/// Creates a colored quad.
pub fn create_quad(allocator: *const std.mem.Allocator, placement: Placement, color: [4]f32) !*Element
{
    const e = try allocator.create(Element);

    e.* = try Element.init(allocator, .Color, placement, color);
    return e;
}

/// Creates an icon, image, or sprite quad.
pub fn create_icon(allocator: *const std.mem.Allocator, placement: Placement, tex_coords: [4]f32) !*Element
{
    const e = try allocator.create(Element);

    e.* = try Element.init(allocator, .Texture, placement, tex_coords);
    return e;
}

/// Utility struct which stores a text character element (created with create_text_character(...)) and its associated FontCharacter.
pub const FontCharacterElement = struct
{
    element: *Element,
    character: FontCharacter
};

/// Creates an image quad which displays a letter, symbol, or glyph from a font.
pub fn create_text_character(allocator: *const std.mem.Allocator, placement: Placement, font: *Font, size: f32, unicode: u32) !FontCharacterElement
{
    const e = try allocator.create(Element);

    font.set_font_size(@as(c_uint, @intFromFloat(size)));

    const character = try font.request(unicode, size);
    const suballoc = character.suballocation;

    var scaled_placement = placement;
    scaled_placement.absolute_offset = .{
        .pos_x = 0,
        .pos_y = 0,
        .scl_x = suballoc.scl_x * @as(f32, @floatFromInt(font.atlas.?.width)),
        .scl_y = suballoc.scl_y * @as(f32, @floatFromInt(font.atlas.?.height))
    };

    e.* = try Element.init(allocator, .Character, scaled_placement, 
    .{suballoc.pos_x, suballoc.pos_y, suballoc.scl_x, suballoc.scl_y});

    return .{
        .element = e,
        .character = character
    };
}

/// Utility struct storing information about a line of UI text.
pub const TextLine = struct
{
    /// Offset of the text array where the line starts.
    start: usize,
    /// Number of characters the line contains.
    length: usize,
    /// Width of the line, in pixels.
    size: f32,
    /// Amount of pixels to 'push' the line forward so that it fits the horizontal alignment.
    alignment_push: f32
};

/// Data structure contained within the 'data' slice of a text element.
pub const TextData = struct
{
    /// Font used.
    font: *Font,
    /// Text size.
    size: f32,
    /// Alignment of individual lines of text in relation to the parent element.
    alignment: vkui.Alignment,
    /// Text, in unicode (u32) values.
    string: []u32,
    /// Horizontal border between the text and the edge of the parent element.
    margin: f32,

    pub fn init(font: *Font, size: f32, alignment: vkui.Alignment, string: []u32, margin: f32) TextData
    {
        return .{
            .font = font,
            .size = size,
            .alignment = alignment,
            .string = string,
            .margin = margin
        };
    }
};

/// Copying text data to a new text element.
fn text_copy_callback(element: *Element, data: ContainerInputData) !void
{
    _ = data;

    var text_data: TextData = undefined;
    memcpy_anonymous(&text_data, element.data.?.ptr, @sizeOf(TextData));

    const text = try element.allocator.alloc(u32, text_data.string.len);
    @memcpy(text, text_data.string);

    text_data.string = text;

    memcpy_anonymous(element.data.?.ptr, &text_data, @sizeOf(TextData));
}

/// Deleting element data.
fn text_deinit_callback(element: *Element, data: ContainerInputData) !void
{
    _ = data;

    var text_data: TextData = undefined;
    memcpy_anonymous(&text_data, element.data.?.ptr, @sizeOf(TextData));

    element.allocator.free(text_data.string);
}

fn loop_text_character(index: usize, text: []u32, character: FontCharacter, bound_width: f32, endpoint: *usize, offset: *f32, prev_offset: *f32, line_length: *f32, end_skip: *usize, word_mode: *bool, should_break: *bool) void
{
    const projected_length = offset.* + @as(f32, @floatFromInt(character.advance)) + @as(f32, @floatFromInt(character.bearing_x));
    if(projected_length > bound_width)
    {
        if(index > 0 and text[index - 1] == ' ')
        {
            // Prevents a bug where the first character of a word can go over the space.
            endpoint.* = index - 1;
            end_skip.* = 1;
        }
        should_break.* = true;
        return;
    }
    if(!word_mode.* and character.unicode != ' ')
    {
        word_mode.* = true;
        endpoint.* = index;
        line_length.* = prev_offset.*;
    }
    else if(character.unicode == ' ')
    {
        word_mode.* = false;
        endpoint.* = index + 1;
        line_length.* = offset.*;
    }

    if(index == text.len - 1)
    {
        endpoint.* = index;
        line_length.* = projected_length - @as(f32, @floatFromInt(character.bearing_x));
    }

    prev_offset.* = offset.*;
    offset.* += @as(f32, @floatFromInt(character.advance));
}

fn get_text_line_alignment_push(text_data: TextData, draw_bounds: vkui.Bounds, line_length: f32) f32
{
    return switch(text_data.alignment.x)
    {
        .Left => text_data.margin,
        .Center => (draw_bounds.scl_x - line_length) / 2,
        .Right => draw_bounds.scl_x - line_length - text_data.margin,
    };
}

fn get_text_line_vertical_offset(text_data: TextData, bounds: vkui.Bounds, line_index: f32, num_lines: usize) f32
{
    const size = text_data.size;

    return switch(text_data.alignment.y)
    {
        .Bottom => line_index * size + 5,
        .Center => -(line_index - 1) * size + (bounds.scl_y + size * @as(f32, @floatFromInt(num_lines))) / 2 - size,
        .Top => -(line_index - 1) * size + (bounds.scl_y - size - 5)
    };
}

fn get_text_line_data(element: *Element, data: ContainerInputData, text: TextData) ![]TextLine
{
    if(text.string.len == 0) return &.{};

    const parent_lineage = element.lineage.?[0..element.lineage.?.len - 1];
    const bounds = try data.container.get_element_bounds(parent_lineage);

    var line: usize = 0;

    var line_start: usize = 0;
    var line_end: usize = 0;

    var word_mode: bool = false;
    var should_loop: bool = true;

    const container_width = bounds.draw_bounds.scl_x - text.margin * 2;

    while(should_loop)
    {
        var offset: f32 = 0;
        var prev_offset: f32 = 0;
        var line_length: f32 = 0;
        var end_skip: usize = 0;

        var should_break = false;

        var check_end: usize = undefined;

        word_mode = text.string[line_start] != ' ';
        
        for(line_start..text.string.len) |i|
        {
            const unicode = text.string[i];
            const character = try text.font.request(unicode, text.size);

            loop_text_character(i, text.string, character, container_width, &line_end, &offset, &prev_offset,
            &line_length, &end_skip, &word_mode, &should_break);

            check_end = i;
            if(should_break) break;
        }

        line += 1;
        if(line_start == line_end and element.children.items.len - line_start > 1)
        {
            // No whitespaces in the current line.
            line_end = check_end;
        }
        line_start = line_end + end_skip;
        if(line_end == element.children.items.len - 1) should_loop = false;
    }

    var lines = try element.allocator.alloc(TextLine, line);

    line = 0;

    line_start = 0;
    line_end = 0;

    should_loop = true;

    while(should_loop)
    {
        var offset: f32 = 0;
        var prev_offset: f32 = 0;
        var line_length: f32 = 0;
        var end_skip: usize = 0;

        var should_break = false;

        lines[line].start = line_start;
        word_mode = text.string[line_start] != ' ';

        var check_end: usize = undefined;

        for(line_start..element.children.items.len) |i|
        {
            const unicode = text.string[i];
            const character = try text.font.request(unicode, text.size);

            loop_text_character(i, text.string, character, container_width, &line_end, &offset, &prev_offset,
            &line_length, &end_skip, &word_mode, &should_break);

            check_end = i;
            if(should_break) break;
        }

        if(line_start == line_end and element.children.items.len - line_start > 1)
        {
            // No whitespaces in the current line.
            line_end = check_end;
            line_length = offset;
        }

        lines[line].length = line_end - line_start;
        lines[line].size = offset;

        const line_alignment_push = get_text_line_alignment_push(text, bounds.draw_bounds, line_length);
        lines[line].alignment_push = line_alignment_push;
        
        line += 1;
        line_start = line_end + end_skip;
        if(line_end == element.children.items.len - 1) should_loop = false;
    }

    return lines;
}

fn text_parent_resize_callback(element: *Element, data: ContainerInputData) !void
{
    if(element.children.items.len == 0) return;
    
    const parent_lineage = element.lineage.?[0..element.lineage.?.len - 1];
    const bounds = try data.container.get_element_bounds(parent_lineage);

    var text_data: TextData = undefined;
    memcpy_anonymous(&text_data, element.data.?.ptr, @sizeOf(TextData));

    const lines = try get_text_line_data(element, data, text_data);

    for(lines, 0..) |line, i|
    {
        var offset: f32 = 0;

        for(line.start..line.start + line.length + 1) |j|
        {
            const e = element.children.items[j];

            const uc = text_data.string[j];
            const ch = try text_data.font.request(uc, text_data.size);

            e.placement.absolute_offset.pos_x = offset + @as(f32, @floatFromInt(ch.bearing_x)) + line.alignment_push;
            e.placement.absolute_offset.pos_y = -(e.placement.absolute_offset.scl_y - @as(f32, @floatFromInt(ch.bearing_y))) - @as(f32, @floatFromInt(i)) * text_data.size;
            offset += @floatFromInt(ch.advance);
        }
    }

    const total_lines = @as(f32, @floatFromInt(lines.len));
    element.allocator.free(lines);

    // Vertical alignment.

    switch(text_data.alignment.y)
    {
        .Bottom => {
            for(0..element.children.items.len) |i|
            {
                const e = element.children.items[i];

                e.placement.absolute_offset.pos_y += (total_lines - 1) * text_data.size + text_data.margin;
            }
        },
        .Center => {
            for(0..element.children.items.len) |i|
            {
                const e = element.children.items[i];

                e.placement.absolute_offset.pos_y += (bounds.draw_bounds.scl_y - text_data.size + (total_lines - 1) * text_data.size) / 2;
            }
        },
        .Top => {
            for(0..element.children.items.len) |i|
            {
                const e = element.children.items[i];

                e.placement.absolute_offset.pos_y += bounds.draw_bounds.scl_y - text_data.size - text_data.margin;
            }
        }
    }

    element.refresh(true);
}

/// Determines the properties of a text element.
pub const TextProperties = struct
{
    /// Font to draw glyph images from.
    font: *Font,
    /// Size to render the text glyphs.
    size: f32,
    /// Alignment of individual lines of text.
    alignment: vkui.Alignment,
    /// Unicode string.
    string: []u32,
    /// Space to leave between the horizontal edges of the parent element, and the text itself. 
    margin: f32,

    pub fn init(font: *Font, size: f32, alignment: vkui.Alignment, string: []u32) TextProperties
    {
        return .{
            .font = font,
            .size = size,
            .alignment = alignment,
            .string = string,
            .margin = 0
        };
    }
};

/// Creates a text element, which uses the element's parent to host the text. For example, adding this element as a child to a simple quad would
/// mean the text would attempt to fit within said quad.
pub fn create_text(allocator: *const std.mem.Allocator, properties: TextProperties) !*Element
{
    const placement: Placement = .get_default();

    const e = try allocator.create(Element);
    e.* = try Element.init(allocator, .None, placement, .{0, 0, 0, 0});

    for(properties.string) |ch|
    {
        const fce = try create_text_character(allocator, placement, properties.font, properties.size, ch);
        try e.add_and_dispose(fce.element);
    }

    const text = try allocator.alloc(u32, properties.string.len);
    @memcpy(text, properties.string);

    var data = TextData.init(properties.font, properties.size, properties.alignment, text, properties.margin);

    e.data = try allocator.alloc(u8, @sizeOf(TextData));
    memcpy_anonymous(e.data.?.ptr, &data, @sizeOf(TextData));

    try e.add_callback(.WindowResize, text_parent_resize_callback);
    try e.add_callback(.Copy, text_copy_callback);
    try e.add_callback(.Deinit, text_deinit_callback);

    return e;
}

/// Converts a slice string ([]const u8) to an ArrayList of u32 values, more usable with TextProperties.
pub fn get_unicode_from_string(allocator: *const std.mem.Allocator, string: []const u8) !std.ArrayList(u32)
{
    var unicode = try std.ArrayList(u32).initCapacity(allocator.*, string.len);
    for(string) |c|
    {
        try unicode.append(allocator.*, c);
    }
    return unicode;
}

fn button_callback_tick(e: *Element, data: ContainerInputData) !void
{
    _ = data;

    var state: u8 = 0;
    var clock: f32 = 0;

    var color_idle: math.Vec(f32, 4) = .init(.{0, 0, 0, 0});
    var color_hover: math.Vec(f32, 4) = .init(.{0, 0, 0, 0});
    var color_press: math.Vec(f32, 4) = .init(.{0, 0, 0, 0});

    var data_offset: usize = 0;

    memcpy_anonymous(&state, e.data.?.ptr + data_offset, @sizeOf(u8));
    data_offset += @sizeOf(u8);

    memcpy_anonymous(&clock, e.data.?.ptr + data_offset, @sizeOf(f32));
    data_offset += @sizeOf(f32);

    data_offset += @sizeOf(*const fn(*Element) void);

    for(0..4) |i|
    {
        memcpy_anonymous(&color_idle.data[i], e.data.?.ptr + data_offset, @sizeOf(f32));
        data_offset += @sizeOf(f32);
    }
    for(0..4) |i|
    {
        memcpy_anonymous(&color_hover.data[i], e.data.?.ptr + data_offset, @sizeOf(f32));
        data_offset += @sizeOf(f32);
    }
    for(0..4) |i|
    {
        memcpy_anonymous(&color_press.data[i], e.data.?.ptr + data_offset, @sizeOf(f32));
        data_offset += @sizeOf(f32);
    }

    const float_state = @as(f32, @floatFromInt(state));
    if(float_state != clock)
    {
        const diff: f32 = (float_state - clock) / 8;
        if(diff < 0.001 and diff > -0.001)
        {
            clock = float_state;
        }
        else
        {
            clock += diff;
        }

        const base: u8 = @intFromFloat(clock);

        switch(base)
        {
            0 =>
            {
                for(0..4) |i|
                {
                    e.coordinates[i] = color_idle.data[i] + (color_hover.data[i] - color_idle.data[i]) * clock;
                }
            },
            1 =>
            {
                for(0..4) |i|
                {
                    e.coordinates[i] = color_hover.data[i] + (color_press.data[i] - color_hover.data[i]) * (clock - 1);
                }
            },
            else =>
            {
                for(0..4) |i|
                {
                    e.coordinates[i] = color_press.data[i];
                }
            }
        }

        e.refresh(false);
        memcpy_anonymous(e.data.?.ptr + @sizeOf(u8), &clock, @sizeOf(f32));
    }
}

fn button_callback_mouse_enter(e: *Element, data: ContainerInputData) !void
{
    _ = data;

    if(e.data.?[0] == 0)
        e.data.?[0] = 1;
}

fn button_callback_mouse_leave(e: *Element, data: ContainerInputData) !void
{
    _ = data;
    e.data.?[0] = 0;
}

fn button_callback_mouse_press(e: *Element, data: ContainerInputData) !void
{
    if(data.mouse_buttons & 1 == 1)
    {
        e.data.?[0] = 2;
    }
}

fn button_callback_mouse_release(e: *Element, data: ContainerInputData) !void
{
    var callback_data: [@sizeOf(*const fn(*Element) void)]u8 = undefined;
    var callback: *const fn(*Element) anyerror!void = undefined;

    const data_offset: usize = @sizeOf(u8) + @sizeOf(f32);

    memcpy_anonymous(&callback_data, e.data.?.ptr + data_offset, @sizeOf(*const fn(*Element) void));
    @memcpy(@as([*]u8, @ptrCast(&callback)), callback_data[0..@sizeOf(*const fn(*Element) void)]);

    if(data.mouse_buttons & 1 == 0)
    {
        if(e.data.?[0] == 2)
        {
            try callback(e);
        }
        e.data.?[0] = 1;
    }
}

/// Example function used to test button press callbacks.
/// Prints a message every time a button is pressed, which includes the address of the button in memory.
pub fn test_callback_button_press(e: *Element) void
{
    std.debug.print("Button pressed.\nAddress of element: {*}\n", .{e});
}

fn empty_press_callback(e: *Element) !void
{
    _ = e;
}

/// Determines the properties of a created button element.
pub const ButtonProperties = struct
{
    /// Placement of the button.
    placement: Placement,

    /// Color to display when the button isn't being interacted with.
    color_idle: [4]f32,
    /// Color to display when the button is being hovered by the mouse cursor.
    color_hover: [4]f32,
    /// Color to display when the button is being pressed.
    color_press: [4]f32,

    /// Specific callback to be called whenever the button is finished being pressed.
    press_callback: *const fn(*Element) anyerror!void,

    /// Initializes the ButtonProperties struct with default colors and no press callback.
    pub fn init_default() ButtonProperties
    {
        return .{
            .placement = .get_default(),

            .color_idle = .{0.3, 0.4, 1, 1},
            .color_hover = .{0.5, 0.6, 1, 1},
            .color_press = .{0.75, 0.8, 1, 1},

            .press_callback = empty_press_callback
        };
    }
};

/// Creates a button element, which the user can click.
pub fn create_button(allocator: *const std.mem.Allocator, properties: ButtonProperties) !*Element
{
    const e = try allocator.create(Element);

    e.* = try Element.init(allocator, .Color, properties.placement, properties.color_idle);

    const data_size = @sizeOf(u8) + @sizeOf(@TypeOf(properties.press_callback)) + @sizeOf(f32) * 13;
    e.data = try allocator.alloc(u8, data_size);

    e.data.?[0] = 0;

    var data_offset: usize = @sizeOf(u8);
    var start_clock: f32 = 0;

    memcpy_anonymous(e.data.?.ptr + data_offset, &start_clock, @sizeOf(f32));
    data_offset += @sizeOf(f32);
    
    var press_callback_alias = properties.press_callback;
    memcpy_anonymous(e.data.?.ptr + data_offset, @ptrCast(&press_callback_alias), @sizeOf(*const fn(*Element) anyerror!void));
    data_offset += @sizeOf(@TypeOf(properties.press_callback));

    var color_idle = properties.color_idle;
    var color_hover = properties.color_hover;
    var color_press = properties.color_press;

    for(0..4) |i|
    {
        memcpy_anonymous(e.data.?.ptr + data_offset, @ptrCast(&color_idle[i]), @sizeOf(f32));
        data_offset += @sizeOf(f32);
    }
    for(0..4) |i|
    {
        memcpy_anonymous(e.data.?.ptr + data_offset, @ptrCast(&color_hover[i]), @sizeOf(f32));
        data_offset += @sizeOf(f32);
    }
    for(0..4) |i|
    {
        memcpy_anonymous(e.data.?.ptr + data_offset, @ptrCast(&color_press[i]), @sizeOf(f32));
        data_offset += @sizeOf(f32);
    }

    try e.add_callback(.Tick, button_callback_tick);
    try e.add_callback(.MouseEnter, button_callback_mouse_enter);
    try e.add_callback(.MouseLeave, button_callback_mouse_leave);
    try e.add_callback(.MousePress, button_callback_mouse_press);
    try e.add_callback(.MouseRelease, button_callback_mouse_release);

    return e;
}

fn scrollbar_callback_mouse_press(e: *Element, data: ContainerInputData) !void
{
    if((data.mouse_buttons & 1) != 0)
    {
        var picked: bool = true;
        memcpy_anonymous(e.data.?.ptr + @sizeOf(f32), &picked, @sizeOf(bool));
    }
}

fn scrollbar_horizontal_callback_tick(e: *Element, data: ContainerInputData) !void
{
    const parent = e.parent.?.parent.?;
    const bounds = try data.container.get_element_bounds(e.lineage.?[0..e.lineage.?.len - 2]);
    const child = e.children.items[0];

    var scroll_button_prev_pos: f32 = 0;
    memcpy_anonymous(&scroll_button_prev_pos, e.data.?.ptr, @sizeOf(f32));

    var should_refresh: bool = false;

    const bar_width = bounds.cut_bounds.scl_x - 20;

    const scroll_button_width_ratio = bounds.cut_bounds.scl_x / bounds.draw_bounds.scl_x;
    var scroll_button_width = scroll_button_width_ratio * bar_width;

    if(scroll_button_width_ratio >= 1)
    {
        scroll_button_width = 0;
    }

    // Mouse picking logic.

    var picked: bool = undefined;

    if((data.mouse_buttons & 1) == 0)
    {
        picked = false;
        memcpy_anonymous(e.data.?.ptr + @sizeOf(f32), &picked, @sizeOf(bool));
    }
    else
    {
        memcpy_anonymous(&picked, e.data.?.ptr + @sizeOf(f32), @sizeOf(bool));
    }

    if(picked)
    {
        const scroll_bar_ratio = bounds.draw_bounds.scl_x / bounds.cut_bounds.scl_x;
        var cursor_offset = @as(f32, @floatFromInt(data.cursor_pos.x)) - bounds.cut_bounds.pos_x - scroll_button_width / 2;

        if(cursor_offset < 0) cursor_offset = 0;
        if(cursor_offset > bar_width - scroll_button_width) cursor_offset = bar_width - scroll_button_width;

        const scroll = cursor_offset * scroll_bar_ratio;
        parent.space.pos_x = scroll;

        if(!should_refresh) should_refresh = scroll_button_prev_pos != scroll;
    }

    // Determining position of scroll marker.

    const scroll_button_pos_ratio = parent.space.pos_x / bounds.draw_bounds.scl_x;
    var scroll_button_pos = scroll_button_pos_ratio * bounds.cut_bounds.scl_x;

    child.placement.absolute_offset.scl_x = scroll_button_width;
    child.placement.absolute_offset.pos_x = scroll_button_pos;

    if(!should_refresh) should_refresh = scroll_button_prev_pos != scroll_button_pos;

    if(should_refresh)
    {
        memcpy_anonymous(e.data.?.ptr, &scroll_button_pos, @sizeOf(f32));
        parent.refresh(true);
    }
}

fn scrollbar_horizontal_callback_window_resize(e: *Element, data: ContainerInputData) !void
{
    const bounds = try data.container.get_element_bounds(e.lineage.?[0..e.lineage.?.len - 2]);
    const child = e.children.items[0];

    const bar_width = bounds.cut_bounds.scl_x - 20;

    const scroll_button_width_ratio = bounds.cut_bounds.scl_x / bounds.draw_bounds.scl_x;
    var scroll_button_width = scroll_button_width_ratio * bar_width;

    if(scroll_button_width_ratio >= 1)
    {
        scroll_button_width = 0;
    }

    const scroll_button_pos_ratio = e.parent.?.space.pos_x / bounds.draw_bounds.scl_x;
    var scroll_button_pos = scroll_button_pos_ratio * bar_width;

    child.placement.absolute_offset.pos_x = scroll_button_pos;
    memcpy_anonymous(e.data.?.ptr, &scroll_button_pos, @sizeOf(f32));

    child.placement.absolute_offset.scl_x = scroll_button_width;

    e.refresh(true);
}

fn scrollbar_vertical_callback_tick(e: *Element, data: ContainerInputData) !void
{
    const parent = e.parent.?.parent.?;
    const bounds = try data.container.get_element_bounds(e.lineage.?[0..e.lineage.?.len - 2]);
    const child = e.children.items[0];

    var scroll_button_prev_pos: f32 = 0;
    memcpy_anonymous(&scroll_button_prev_pos, e.data.?.ptr, @sizeOf(f32));

    var should_refresh: bool = false;

    // Mouse picking logic.

    var picked: bool = undefined;

    const scroll_button_height_ratio = bounds.cut_bounds.scl_y / bounds.draw_bounds.scl_y;
    var scroll_button_height = scroll_button_height_ratio * bounds.cut_bounds.scl_y;

    if(scroll_button_height_ratio >= 1)
    {
        scroll_button_height = 0;
    }

    if((data.mouse_buttons & 1) == 0)
    {
        picked = false;
        memcpy_anonymous(e.data.?.ptr + @sizeOf(f32), &picked, @sizeOf(bool));
    }
    else
    {
        memcpy_anonymous(&picked, e.data.?.ptr + @sizeOf(f32), @sizeOf(bool));
    }

    if(picked)
    {
        const scroll_bar_ratio = bounds.draw_bounds.scl_y / bounds.cut_bounds.scl_y;
        var cursor_offset = @as(f32, @floatFromInt(data.cursor_pos.y)) - bounds.cut_bounds.pos_y - scroll_button_height / 2;

        if(cursor_offset < 0) cursor_offset = 0;
        if(cursor_offset > bounds.cut_bounds.scl_y - scroll_button_height) cursor_offset = bounds.cut_bounds.scl_y - scroll_button_height;

        const scroll = cursor_offset * scroll_bar_ratio;
        parent.space.pos_y = scroll;

        if(!should_refresh) should_refresh = scroll_button_prev_pos != scroll;
    }

    // Determining position of scroll marker.

    const scroll_button_pos_ratio = parent.space.pos_y / bounds.draw_bounds.scl_y;
    var scroll_button_pos = scroll_button_pos_ratio * bounds.cut_bounds.scl_y;

    child.placement.absolute_offset.scl_y = scroll_button_height;
    child.placement.absolute_offset.pos_y = scroll_button_pos;

    if(!should_refresh) should_refresh = scroll_button_prev_pos != scroll_button_pos;

    if(should_refresh)
    {
        memcpy_anonymous(e.data.?.ptr, &scroll_button_pos, @sizeOf(f32));
        parent.refresh(true);
    }
}

fn scrollbar_vertical_callback_window_resize(e: *Element, data: ContainerInputData) !void
{    
    const bounds = try data.container.get_element_bounds(e.lineage.?[0..e.lineage.?.len - 2]);
    const child = e.children.items[0];

    const scroll_button_height_ratio = bounds.cut_bounds.scl_y / bounds.draw_bounds.scl_y;
    var scroll_button_height = scroll_button_height_ratio * bounds.cut_bounds.scl_y;

    if(scroll_button_height_ratio >= 1)
    {
        scroll_button_height = 0;
    }
    
    const scroll_button_pos_ratio = e.parent.?.space.pos_y / bounds.draw_bounds.scl_y;
    var scroll_button_pos = scroll_button_pos_ratio * bounds.cut_bounds.scl_y;

    child.placement.absolute_offset.pos_y = scroll_button_pos;
    memcpy_anonymous(e.data.?.ptr, &scroll_button_pos, @sizeOf(f32));

    child.placement.absolute_offset.scl_y = scroll_button_height;

    e.refresh(true);
}

/// Creates scroll sliders where applicable. Meant to be used with scrollable elements.
pub fn create_scrollbar(allocator: *const std.mem.Allocator) !*Element
{
    const e = try allocator.create(Element);

    const parent_placement: Placement = .{
        .relative_pos = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 1,
            .scl_y = 1
        },
        .absolute_offset = .get_default(),
        .alignment = .{
            .x = .Left,
            .y = .Bottom
        }
    };

    e.* = try Element.init(allocator, .None, parent_placement, .{0, 0, 0, 0});
    e.freeze = true;

    const vertical_scroll = try allocator.create(Element);

    const vertical_scroll_placement: Placement = .{
        .relative_pos = .{
            .pos_x = 1,
            .pos_y = 0,
            .scl_x = 0,
            .scl_y = 1
        },
        .absolute_offset = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 20,
            .scl_y = 0
        },
        .alignment = .{
            .x = .Right,
            .y = .Bottom
        }
    };

    vertical_scroll.* = try Element.init(allocator, .None, vertical_scroll_placement, .{1, 0, 0, 1});
    vertical_scroll.freeze = true;

    vertical_scroll.data = try allocator.alloc(u8, @sizeOf(f32) + @sizeOf(bool));

    var start: f32 = 0;
    memcpy_anonymous(vertical_scroll.data.?.ptr, &start, @sizeOf(f32));

    var picked: bool = false;
    memcpy_anonymous(vertical_scroll.data.?.ptr + @sizeOf(f32), &picked, @sizeOf(bool));

    try vertical_scroll.add_callback(.Tick, scrollbar_vertical_callback_tick);
    try vertical_scroll.add_callback(.MousePress, scrollbar_callback_mouse_press);
    try vertical_scroll.add_callback(.WindowResize, scrollbar_vertical_callback_window_resize);

    const scroll_placement: Placement = .{
        .relative_pos = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 1,
            .scl_y = 0
        },
        .absolute_offset = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 0,
            .scl_y = 0
        },
        .alignment = .{
            .x = .Left,
            .y = .Bottom
        }
    };

    const vertical_scroll_button = try allocator.create(Element);
    vertical_scroll_button.* = try Element.init(allocator, .Color, scroll_placement, .{1, 1, 1, 0.5});

    try vertical_scroll.add_and_dispose(vertical_scroll_button);
    try e.add_and_dispose(vertical_scroll);

    const horizontal_scroll = try allocator.create(Element);

    const horizontal_scroll_placement: Placement = .{
        .relative_pos = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 1,
            .scl_y = 0
        },
        .absolute_offset = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = -20,
            .scl_y = 20
        },
        .alignment = .{
            .x = .Left,
            .y = .Bottom
        }
    };

    horizontal_scroll.* = try Element.init(allocator, .None, horizontal_scroll_placement, .{1, 0, 0, 1});
    horizontal_scroll.freeze = true;

    horizontal_scroll.data = try allocator.alloc(u8, @sizeOf(f32) + @sizeOf(bool));

    memcpy_anonymous(horizontal_scroll.data.?.ptr, &start, @sizeOf(f32));
    memcpy_anonymous(horizontal_scroll.data.?.ptr + @sizeOf(f32), &picked, @sizeOf(bool));

    try horizontal_scroll.add_callback(.Tick, scrollbar_horizontal_callback_tick);
    try horizontal_scroll.add_callback(.MousePress, scrollbar_callback_mouse_press);
    try horizontal_scroll.add_callback(.WindowResize, scrollbar_horizontal_callback_window_resize);

    const horizontal_scroll_marker_placement: Placement = .{
        .relative_pos = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 0,
            .scl_y = 1
        },
        .absolute_offset = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 0,
            .scl_y = 0
        },
        .alignment = .{
            .x = .Left,
            .y = .Bottom
        }
    };

    const horizontal_scroll_button = try allocator.create(Element);
    horizontal_scroll_button.* = try Element.init(allocator, .Color, horizontal_scroll_marker_placement, .{1, 1, 1, 0.5});

    try horizontal_scroll.add_and_dispose(horizontal_scroll_button);
    try e.add_and_dispose(horizontal_scroll);

    return e;
}

pub fn empty_checkbox_callback(e: *Element, value: bool) void
{
    _ = e;
    _ = value;
}

pub const CheckboxData = struct
{
    ticked: bool,
    hovered: bool,

    color_hover: [4]f32,
    color_ticked: [4]f32,

    clock: f32,
    callback: *const fn(*Element, bool) void,

    pub fn init(ticked: bool, color_hover: [4]f32, color_ticked: [4]f32, callback: *const fn(*Element, bool) void) CheckboxData
    {
        return .{
            .ticked = ticked,
            .hovered = false,
            .color_hover = color_hover,
            .color_ticked = color_ticked,
            .clock = 0,
            .callback = callback
        };
    }
};

/// Properties of a checkbox element.
pub const CheckboxProperties = struct
{
    /// Placement of the checkbox.
    placement: Placement,
    /// Initial value of the checkbox.
    start_ticked: bool,

    /// Color to display on the checkbox's border.
    color_border: [4]f32,
    /// Color to display when the checkbox is being hovered.
    color_hover: [4]f32,
    /// Color to display when the checkbox is ticked.
    color_ticked: [4]f32,

    /// Width of the checkbox's border.
    border_width: f32,
    /// Callback function to call when the checkbox is un/ticked.
    callback: *const fn(*Element, bool) void,

    pub fn init_default(placement: Placement) CheckboxProperties
    {
        return .{
            .placement = placement,
            .start_ticked = false,
            .color_border = .{1, 1, 1, 1},
            .color_hover = .{1, 1, 1, 0.2},
            .color_ticked = .{0, 1, 1, 1},
            .border_width = 5,
            .callback = empty_checkbox_callback
        };
    }
};

fn checkbox_callback_mouse_enter(e: *Element, data: ContainerInputData) !void
{
    _ = data;

    var checkbox_data: CheckboxData = undefined;
    memcpy_anonymous(&checkbox_data, e.data.?.ptr, @sizeOf(CheckboxData));

    checkbox_data.hovered = true;

    memcpy_anonymous(e.data.?.ptr, &checkbox_data, @sizeOf(CheckboxData));
}

fn checkbox_callback_mouse_leave(e: *Element, data: ContainerInputData) !void
{
    _ = data;
    
    var checkbox_data: CheckboxData = undefined;
    memcpy_anonymous(&checkbox_data, e.data.?.ptr, @sizeOf(CheckboxData));

    checkbox_data.hovered = false;

    memcpy_anonymous(e.data.?.ptr, &checkbox_data, @sizeOf(CheckboxData));
}

fn checkbox_callback_mouse_press(e: *Element, data: ContainerInputData) !void
{
    _ = data;

    var checkbox_data: CheckboxData = undefined;
    memcpy_anonymous(&checkbox_data, e.data.?.ptr, @sizeOf(CheckboxData));

    checkbox_data.ticked = !checkbox_data.ticked;

    const tickbox = e.children.items[5];
    tickbox.coordinates = if(checkbox_data.ticked) checkbox_data.color_ticked else .{0, 0, 0, 0};

    checkbox_data.callback(tickbox.parent.?, checkbox_data.ticked);
    tickbox.refresh(false);

    memcpy_anonymous(e.data.?.ptr, &checkbox_data, @sizeOf(CheckboxData));
}

fn checkbox_callback_tick(e: *Element, data: ContainerInputData) !void
{
    _ = data;

    const hover = e.children.items[0];

    var checkbox_data: CheckboxData = undefined;
    memcpy_anonymous(&checkbox_data, e.data.?.ptr, @sizeOf(CheckboxData));

    if(checkbox_data.hovered and checkbox_data.clock != 1)
    {
        const diff = (1 - checkbox_data.clock) / 3;
        if(diff < 0.001)
        {
            checkbox_data.clock = 1;
            hover.coordinates = checkbox_data.color_hover;
        }
        else
        {
            checkbox_data.clock += diff;
            for(0..4) |i|
            {
                hover.coordinates[i] = checkbox_data.color_hover[i] * checkbox_data.clock;
            }
        }

        hover.refresh(false);
    }
    else if(!checkbox_data.hovered and checkbox_data.clock != 0)
    {
        const diff = -checkbox_data.clock / 3;
        if(diff > -0.001)
        {
            checkbox_data.clock = 0;
            hover.coordinates = .{0, 0, 0, 0};
        }
        else
        {
            checkbox_data.clock += diff;
            for(0..4) |i|
            {
                hover.coordinates[i] = checkbox_data.color_hover[i] * checkbox_data.clock;
            }
        }

        hover.refresh(false);
    }

    memcpy_anonymous(e.data.?.ptr, &checkbox_data, @sizeOf(CheckboxData));
}

/// Creates a checkbox element, which the user can un/tick.
pub fn create_checkbox(allocator: *const std.mem.Allocator, properties: CheckboxProperties) !*Element
{
    const e = try allocator.create(Element);

    e.* = try Element.init(allocator, .None, properties.placement, .{0, 0, 0, 0});

    e.data = try allocator.alloc(u8, @sizeOf(CheckboxData));

    var data: CheckboxData = .init(properties.start_ticked, properties.color_hover, properties.color_ticked, properties.callback);
    memcpy_anonymous(e.data.?.ptr, &data, @sizeOf(CheckboxData));

    const hover = try create_quad(allocator, .{
        .relative_pos = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 1,
            .scl_y = 1
        },
        .absolute_offset = .get_default(),
        .alignment = .{
            .x = .Left,
            .y = .Bottom
        }
    }, .{0, 0, 0, 0});

    try e.add_and_dispose(hover);

    const border_top = try create_quad(allocator, .{
        .relative_pos = .{
            .pos_x = 0,
            .pos_y = 1,
            .scl_x = 1,
            .scl_y = 0
        },
        .absolute_offset = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 0,
            .scl_y = properties.border_width
        },
        .alignment = .{
            .x = .Left,
            .y = .Top
        }
    }, .{1, 1, 1, 1});

    try e.add_and_dispose(border_top);

    const border_bottom = try create_quad(allocator, .{
        .relative_pos = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 1,
            .scl_y = 0
        },
        .absolute_offset = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 0,
            .scl_y = properties.border_width
        },
        .alignment = .{
            .x = .Left,
            .y = .Bottom
        }
    }, .{1, 1, 1, 1});

    try e.add_and_dispose(border_bottom);

    const border_left = try create_quad(allocator, .{
        .relative_pos = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 0,
            .scl_y = 1
        },
        .absolute_offset = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = properties.border_width,
            .scl_y = 0
        },
        .alignment = .{
            .x = .Left,
            .y = .Bottom
        }
    }, .{1, 1, 1, 1});

    try e.add_and_dispose(border_left);

    const border_right = try create_quad(allocator, .{
        .relative_pos = .{
            .pos_x = 1,
            .pos_y = 0,
            .scl_x = 0,
            .scl_y = 1
        },
        .absolute_offset = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = properties.border_width,
            .scl_y = 0
        },
        .alignment = .{
            .x = .Right,
            .y = .Bottom
        }
    }, .{1, 1, 1, 1});

    try e.add_and_dispose(border_right);

    const tickbox = try create_quad(allocator, .{
        .relative_pos = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 1,
            .scl_y = 1
        },
        .absolute_offset = .{
            .pos_x = properties.border_width * 2,
            .pos_y = properties.border_width * 2,
            .scl_x = -properties.border_width * 4,
            .scl_y = -properties.border_width * 4
        },
        .alignment = .{
            .x = .Left,
            .y = .Bottom
        }
    }, if(properties.start_ticked) properties.color_ticked else .{0, 0, 0, 0});

    try e.add_and_dispose(tickbox);

    try e.add_callback(.MouseEnter, checkbox_callback_mouse_enter);
    try e.add_callback(.MouseLeave, checkbox_callback_mouse_leave);
    try e.add_callback(.MousePress, checkbox_callback_mouse_press);
    try e.add_callback(.Tick, checkbox_callback_tick);

    return e;
}

fn empty_slider_callback(e: *Element, value: f32) void
{
    _ = e;
    _ = value;
}

pub const SliderData = struct
{
    input_value: f32,
    discrete_values: u32,

    color_knob_idle: [4]f32,
    color_knob_hover: [4]f32,
    color_knob_press: [4]f32,

    horizontal: bool,

    clock: f32,
    hovered: bool,
    pressed: bool,
    press_toggle: bool,

    callback: *const fn(*Element, f32) void
};

/// Determines the properties of a slider element.
pub const SliderProperties = struct
{
    placement: Placement,

    discrete_values: u32,
    start_value: f32,

    color_bar: [4]f32,
    color_knob_idle: [4]f32,
    color_knob_hover: [4]f32,
    color_knob_press: [4]f32,

    bar_width: f32,
    knob_width: f32,
    horizontal: bool,

    callback: *const fn(*Element, f32) void,

    pub fn init_default(placement: Placement) SliderProperties
    {
        return .{
            .placement = placement,
            .discrete_values = 0,
            .start_value = 0.5,
            .color_bar = .{0.1, 0.1, 0.1, 1},
            .color_knob_idle = .{0.35, 0.35, 0.35, 1},
            .color_knob_hover = .{0.55, 0.55, 0.55, 1},
            .color_knob_press = .{0.6, 0.6, 0.6, 1},
            .bar_width = 5,
            .knob_width = 30,
            .horizontal = true,
            .callback = empty_slider_callback
        };
    }
};

fn slider_callback_mouse_enter(e: *Element, data: ContainerInputData) !void
{
    _ = data;
    
    var slider_data: SliderData = undefined;
    memcpy_anonymous(&slider_data, e.data.?.ptr, @sizeOf(SliderData));

    slider_data.hovered = true;

    memcpy_anonymous(e.data.?.ptr, &slider_data, @sizeOf(SliderData));
}

fn slider_callback_mouse_leave(e: *Element, data: ContainerInputData) !void
{
    _ = data;

    var slider_data: SliderData = undefined;
    memcpy_anonymous(&slider_data, e.data.?.ptr, @sizeOf(SliderData));

    slider_data.hovered = false;

    memcpy_anonymous(e.data.?.ptr, &slider_data, @sizeOf(SliderData));
}

fn slider_callback_mouse_press(e: *Element, data: ContainerInputData) !void
{
    _ = data;
    
    var slider_data: SliderData = undefined;
    memcpy_anonymous(&slider_data, e.data.?.ptr, @sizeOf(SliderData));

    slider_data.pressed = true;

    memcpy_anonymous(e.data.?.ptr, &slider_data, @sizeOf(SliderData));
}

fn slider_callback_tick(e: *Element, data: ContainerInputData) !void
{
    const knob = e.children.items[1];

    var slider_data: SliderData = undefined;
    memcpy_anonymous(&slider_data, e.data.?.ptr, @sizeOf(SliderData));

    if(slider_data.pressed)
    {
        if(!slider_data.press_toggle)
        {
            knob.coordinates = slider_data.color_knob_press;
            knob.refresh(false);
        }

        slider_data.press_toggle = true;
    }
    else
    {
        if(slider_data.press_toggle)
        {
            knob.coordinates = if(slider_data.hovered) slider_data.color_knob_hover else slider_data.color_knob_idle;
            knob.refresh(false);

            slider_data.press_toggle = false;
        }

        if(slider_data.hovered and slider_data.clock != 1)
        {
            const diff = (1 - slider_data.clock) / 3;
            if(diff < 0.001)
            {
                slider_data.clock = 1;
                knob.coordinates = slider_data.color_knob_hover;
            }
            else
            {
                slider_data.clock += diff;
                for(0..4) |i|
                {
                    knob.coordinates[i] = (slider_data.color_knob_hover[i] * slider_data.clock) + (slider_data.color_knob_idle[i] * (1 - slider_data.clock));
                }
            }

            knob.refresh(false);
        }
        else if(!slider_data.hovered and slider_data.clock != 0)
        {
            const diff = -slider_data.clock / 3;
            if(diff > -0.001)
            {
                slider_data.clock = 0;
                knob.coordinates = slider_data.color_knob_idle;
            }
            else
            {
                slider_data.clock += diff;
                for(0..4) |i|
                {
                    knob.coordinates[i] = slider_data.color_knob_hover[i] * slider_data.clock + (slider_data.color_knob_idle[i] * (1 - slider_data.clock));
                }
            }

            knob.refresh(false);
        }
    }

    if(data.mouse_buttons & 1 == 0)
    {
        slider_data.pressed = false;
    }
    else if(slider_data.pressed)
    {
        const bounds = (try data.container.get_element_bounds(e.lineage.?)).draw_bounds;
        const mouse_offset = if(slider_data.horizontal) @as(f32, @floatFromInt(data.cursor_pos.x)) - bounds.pos_x
                                                        else @as(f32, @floatFromInt(data.cursor_pos.y)) - bounds.pos_y;

        var offset = mouse_offset / (if(slider_data.horizontal) bounds.scl_x else bounds.scl_y);
        offset = std.math.clamp(offset, 0, 1);

        if(slider_data.discrete_values != 0)
        {
            const limit = @as(f32, @floatFromInt(slider_data.discrete_values + 1));

            var discrete_offset = offset * limit;

            if(discrete_offset >= limit)
            {
                discrete_offset = limit - 0.0001;
            }

            offset = std.math.floor(discrete_offset) / @as(f32, @floatFromInt(slider_data.discrete_values));
        }
        
        if(offset != slider_data.input_value)
        {
            slider_data.input_value = offset;
            if(slider_data.horizontal)
            {
                knob.placement.relative_pos.pos_x = offset;
            }
            else
            {
                knob.placement.relative_pos.pos_y = offset;
            }

            slider_data.callback(e, if(slider_data.discrete_values != 0) offset * @as(f32, @floatFromInt(slider_data.discrete_values)) else offset);

            knob.refresh(false);
        }
    }

    memcpy_anonymous(e.data.?.ptr, &slider_data, @sizeOf(SliderData));
}

/// Creates a slider element, which the user can interact with.
pub fn create_slider(allocator: *const std.mem.Allocator, properties: SliderProperties) !*Element
{
    const e = try allocator.create(Element);

    e.* = try .init(allocator, .None, properties.placement, properties.color_bar);

    var slider_data: SliderData = .{
        .input_value = properties.start_value,
        .discrete_values = properties.discrete_values,
        .color_knob_idle = properties.color_knob_idle,
        .color_knob_hover = properties.color_knob_hover,
        .color_knob_press = properties.color_knob_press,
        .clock = 0,
        .horizontal = properties.horizontal,
        .hovered = false,
        .pressed = false,
        .press_toggle = false,
        .callback = properties.callback
    };

    e.data = try allocator.alloc(u8, @sizeOf(SliderData));
    memcpy_anonymous(e.data.?.ptr, &slider_data, @sizeOf(SliderData));

    const bar = try create_quad(allocator, .{
        .relative_pos = .{
            .pos_x = if(properties.horizontal) 0 else 0.5,
            .pos_y = if(properties.horizontal) 0.5 else 0,
            .scl_x = if(properties.horizontal) 1 else 0,
            .scl_y = if(properties.horizontal) 0 else 1
        },
        .absolute_offset = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = if(properties.horizontal) 0 else properties.bar_width,
            .scl_y = if(properties.horizontal) properties.bar_width else 0
        },
        .alignment = .{
            .x = if(properties.horizontal) .Left else .Center,
            .y = if(properties.horizontal) .Center else .Bottom
        }
    }, properties.color_bar);

    try e.add_and_dispose(bar);

    const knob = try create_quad(allocator, .{
        .relative_pos = .{
            .pos_x = if(properties.horizontal) properties.start_value else 0.5,
            .pos_y = if(properties.horizontal) 0.5 else properties.start_value,
            .scl_x = if(properties.horizontal) 0 else 1,
            .scl_y = if(properties.horizontal) 1 else 0
        },
        .absolute_offset = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = if(properties.horizontal) properties.knob_width else 0,
            .scl_y = if(properties.horizontal) 0 else properties.knob_width
        },
        .alignment = .{
            .x = .Center,
            .y = .Center
        }
    }, properties.color_knob_idle);

    try e.add_and_dispose(knob);

    try e.add_callback(.MouseEnter, slider_callback_mouse_enter);
    try e.add_callback(.MouseLeave, slider_callback_mouse_leave);
    try e.add_callback(.MousePress, slider_callback_mouse_press);
    try e.add_callback(.Tick, slider_callback_tick);

    return e;
}

pub const TextFieldData = struct
{
    update: bool,

    editing: bool,
    hovering: bool,

    font: *Font,

    text: []u32,
    text_size: f32,
    text_alignment: vkui.Alignment,

    current_cursor_pos: usize,
    prev_cursor_pos: usize,
    cursor_timer: f32,
    editing_toggle: bool,

    extension_protocol: TextFieldExtension,

    pub fn init(allocator: *const std.mem.Allocator, properties: TextFieldProperties) !TextFieldData
    {
        const new_allocation = try allocator.alloc(u32, properties.initial_text.len);
        @memcpy(new_allocation, properties.initial_text);

        return .{
            .update = false,
            .editing = false,
            .hovering = false,
            .text_size = properties.text_size,
            .font = properties.font,
            .text = new_allocation,
            .text_alignment = properties.text_alignment,
            .current_cursor_pos = new_allocation.len,
            .prev_cursor_pos = new_allocation.len,
            .cursor_timer = 0,
            .editing_toggle = false,
            .extension_protocol = properties.extension_protocol
        };
    }
};

const TextFieldExtension = enum
{
    ScrollVertically
};

/// Determines the properties of a textfield element.
pub const TextFieldProperties = struct
{
    /// Font used for the text.
    font: *Font,
    /// Text size.
    text_size: f32 = 20,
    /// Alignment of the text within the textfield, including the direction which the text will "grow" in.
    text_alignment: vkui.Alignment = .{
        .x = .Left,
        .y = .Top
    },

    /// Initial text for the field to start with.
    initial_text: []u32 = &.{},
    /// Determines how the textfield should handle text overflow.
    extension_protocol: TextFieldExtension = .ScrollVertically
};

fn insert_characters_into_text(allocator: *const std.mem.Allocator, index: usize, characters: []u32, text: []u32) ![]u32
{
    const string = try allocator.alloc(u32, text.len + characters.len);

    for(0..index) |i|
    {
        string[i] = text[i];
    }

    for(0..characters.len) |i|
    {
        string[i + index] = characters[i];
    }

    for(index..text.len) |i|
    {
        string[i + characters.len] = text[i];
    }

    allocator.free(text);
    return string;
}

fn remove_characters_from_text(allocator: *const std.mem.Allocator, start_index: usize, length: usize, text: []u32) ![]u32
{
    if(start_index + length >= text.len)
    {
        if(start_index == 0)
        {
            allocator.free(text);
            return try allocator.alloc(u32, 0);
        }

        const string = try allocator.alloc(u32, text.len - length);
        for(0..start_index) |i|
        {
            string[i] = text[i];
        }

        allocator.free(text);
        return string;
    }

    const string = try allocator.alloc(u32, text.len - length);

    for(0..start_index) |i|
    {
        string[i] = text[i];
    }

    for(start_index + length..text.len) |i|
    {
        string[i - length] = text[i];
    }

    allocator.free(text);
    return string;
}

/// Locates the position of a text character in a textfield, used for determining the placement of the textfield cursor.
fn get_offset_of_textfield_character(index: usize, element: *Element, container_data: ContainerInputData, textfield: TextFieldData) !vkui.Bounds
{
    const text_space = element.children.items[0];
    const text_element = text_space.children.items[1];

    const textfield_bounds = (try container_data.container.get_element_bounds(text_space.lineage.?)).draw_bounds;

    var text_data: TextData = undefined;
    memcpy_anonymous(&text_data, text_element.data.?.ptr, @sizeOf(TextData));

    const lines = try get_text_line_data(text_element, container_data, text_data);
    defer element.allocator.free(lines);

    if(lines.len == 0)
    {
        // No text.
        const line_alignment_push = get_text_line_alignment_push(text_data, textfield_bounds, 0);

        // For Center Y, they both need to be 1.
        const vertical_offset = switch(text_data.alignment.y)
        {
            .Bottom => get_text_line_vertical_offset(text_data, textfield_bounds, 0, 0),
            .Center, .Top => get_text_line_vertical_offset(text_data, textfield_bounds, 1, 1)
        };

        return .{
            .pos_x = line_alignment_push,
            .pos_y = vertical_offset,
            .scl_x = 0,
            .scl_y = 0
        };
    }

    var index_line: f32 = 0;
    if(index == 0)
    {
        index_line = 1;
    }
    else
    {
        for(lines) |line|
        {
            if(line.start < index)
            {
                index_line += 1;
            }
            else
            {
                break;
            }
        }
    }

    const line_index = @as(usize, @intFromFloat(index_line - 1));
    if(textfield.text_alignment.y == .Bottom) index_line = @as(f32, @floatFromInt(lines.len)) - index_line;

    // std.debug.print("Index line: {d}.\n", .{index_line});

    const cursor_y = get_text_line_vertical_offset(text_data, textfield_bounds, index_line, lines.len);

    const line_start = lines[line_index].start;
    const line_end = line_start + lines[line_index].length;

    var cursor_x: f32 = 0;

    for(line_start..line_end + 1) |i|
    {
        const uc = textfield.text[i];
        const character = try textfield.font.request(uc, textfield.text_size);

        if(i < index)
        {
            cursor_x += @floatFromInt(character.advance);
        }
        else
        {
            cursor_x += @floatFromInt(character.bearing_x);
            break;
        }
    }

    cursor_x += lines[line_index].alignment_push;

    return .{
        .pos_x = cursor_x,
        .pos_y = cursor_y,
        .scl_x = 0,
        .scl_y = 0
    };
}

fn get_text_space(element: *Element, container_data: ContainerInputData) !vkui.Bounds
{
    const inner = element.children.items[0];
    const cursor = element.children.items[0].children.items[0];
    const text = element.children.items[0].children.items[1];

    var text_data: TextData = undefined;
    memcpy_anonymous(&text_data, text.data.?.ptr, @sizeOf(TextData));

    const container = container_data.container;

    const border_bounds = (try container.get_element_bounds(element.lineage.?)).draw_bounds;
    const inner_bounds = (try container.get_element_bounds(inner.lineage.?)).draw_bounds;
    const cursor_bounds = (try container.get_element_bounds(cursor.lineage.?)).draw_bounds;

    var min_x: f32 = 9999;
    var min_y: f32 = 9999;

    var max_x: f32 = 0;
    var max_y: f32 = 0;

    for(text.children.items) |ch|
    {
        const bounds = (try container.get_element_bounds(ch.lineage.?)).draw_bounds;

        const cur_min_x = bounds.pos_x - inner_bounds.pos_x;
        const cur_min_y = bounds.pos_y - inner_bounds.pos_y;

        const cur_max_x = bounds.pos_x - inner_bounds.pos_x + bounds.scl_x;
        const cur_max_y = bounds.pos_y - inner_bounds.pos_y + bounds.scl_y;
        
        if(cur_min_x < min_x)
        {
            min_x = cur_min_x;
        }
        if(cur_min_y < min_y)
        {
            min_y = cur_min_y;
        }

        if(cur_max_x > max_x)
        {
            max_x = cur_max_x;
        }
        if(cur_max_y > max_y)
        {
            max_y = cur_max_y;
        }
    }

    var scl_y = max_y - min_y + text_data.size;
    if(scl_y < border_bounds.scl_y - 2)
    {
        // Ensures the text space is always at least as tall as the textfield space.
        scl_y = border_bounds.scl_y - 2;
    }

    var pos_y: f32 = cursor_bounds.pos_y - inner_bounds.pos_y;
    
    if(text_data.alignment.y == .Bottom)
    {
        pos_y += -border_bounds.scl_y + cursor_bounds.scl_y;
    }
    else if(text_data.alignment.y == .Top)
    {
        const cursor_boundary = border_bounds.scl_y - 2 - text_data.size;
        const scroll_boundary = border_bounds.scl_y - 2 + text_data.size;

        if(pos_y < cursor_boundary and scl_y > scroll_boundary)
        {
            pos_y = min_y;
        }
        else if(scl_y <= scroll_boundary)
        {
            pos_y = 0;
        }
        else if(pos_y >= cursor_boundary)
        {
            pos_y += -border_bounds.scl_y + cursor_bounds.scl_y;
        }
    }

    if(pos_y < 0)
    {
        pos_y = 0; // <- Bottom alignment.
    }

    return .{
        .pos_x = 0,
        .pos_y = pos_y,
        .scl_x = inner_bounds.scl_x,
        .scl_y = scl_y
    };
}

fn textfield_callback_copy(e: *Element, data: ContainerInputData) !void
{
    _ = data;

    var textfield_data: TextFieldData = undefined;
    memcpy_anonymous(&textfield_data, e.data.?.ptr, @sizeOf(TextFieldData));

    var new_textfield_data: TextFieldData = textfield_data;

    new_textfield_data.text = try e.allocator.alloc(u32, textfield_data.text.len);
    @memcpy(new_textfield_data.text, textfield_data.text);

    memcpy_anonymous(e.data.?.ptr, &new_textfield_data, @sizeOf(TextFieldData));
}

fn textfield_callback_deinit(e: *Element, data: ContainerInputData) !void
{
    _ = data;

    var textfield_data: TextFieldData = undefined;
    memcpy_anonymous(&textfield_data, e.data.?.ptr, @sizeOf(TextFieldData));

    e.allocator.free(textfield_data.text);
}

fn textfield_callback_mouse_enter(e: *Element, data: ContainerInputData) !void
{
    _ = data;

    var textfield_data: TextFieldData = undefined;
    memcpy_anonymous(&textfield_data, e.data.?.ptr, @sizeOf(TextFieldData));

    textfield_data.hovering = true;
    textfield_data.update = true;

    memcpy_anonymous(e.data.?.ptr, &textfield_data, @sizeOf(TextFieldData));
}

fn textfield_callback_mouse_leave(e: *Element, data: ContainerInputData) !void
{
    _ = data;

    var textfield_data: TextFieldData = undefined;
    memcpy_anonymous(&textfield_data, e.data.?.ptr, @sizeOf(TextFieldData));

    textfield_data.hovering = false;
    textfield_data.update = true;

    memcpy_anonymous(e.data.?.ptr, &textfield_data, @sizeOf(TextFieldData));
}

fn textfield_callback_mouse_press(e: *Element, data: ContainerInputData) !void
{
    _ = data;

    var textfield_data: TextFieldData = undefined;
    memcpy_anonymous(&textfield_data, e.data.?.ptr, @sizeOf(TextFieldData));

    textfield_data.editing = true;
    textfield_data.update = true;

    memcpy_anonymous(e.data.?.ptr, &textfield_data, @sizeOf(TextFieldData));
}

fn textfield_callback_rebuild(e: *Element, data: ContainerInputData) !void
{
    var textfield_data: TextFieldData = undefined;
    memcpy_anonymous(&textfield_data, e.data.?.ptr, @sizeOf(TextFieldData));

    const text_space = e.children.items[0];
    const text = text_space.children.items[1];

    const previous_text_size = text.children.items.len;

    try text_space.remove_by_index(1);

    var text_properties: TextProperties = .init(textfield_data.font, textfield_data.text_size, textfield_data.text_alignment, textfield_data.text);

    text_properties.margin = 5;

    const new_text = try create_text(e.allocator, text_properties);
    try text_space.add_and_dispose(new_text);

    const diff: isize = @as(isize, @intCast(textfield_data.text.len)) - @as(isize, @intCast(previous_text_size));
    textfield_data.current_cursor_pos +%= @bitCast(diff);

    if(textfield_data.current_cursor_pos > textfield_data.text.len)
        textfield_data.current_cursor_pos = textfield_data.text.len;

    memcpy_anonymous(e.data.?.ptr, &textfield_data, @sizeOf(TextFieldData));

    const text_index = text_space.children.items.len - 1;
    // try text_space.children.items[text_index].force_callback(.WindowResize);
    try text_parent_resize_callback(text_space.children.items[text_index], data);
}

fn textfield_callback_window_resize(e: *Element, data: ContainerInputData) !void
{
    const parent_lineage = e.lineage.?[0..e.lineage.?.len - 1];
    const bounds = (try data.container.get_element_bounds(parent_lineage)).draw_bounds;

    e.space.scl_x = bounds.scl_x;
    e.refresh(true);
}

/// Updates the cursor's specific placement if necessary by querying what it's placement should be based on the cursor's
/// position (index in the string where it would insert characters).
fn textfield_update_cursor_placement(e: *Element, container_data: ContainerInputData, textfield_data: TextFieldData) !void
{
    const text_space = e.children.items[0];
    const cursor = text_space.children.items[0];

    const character_bounds = try get_offset_of_textfield_character(textfield_data.current_cursor_pos, e, 
    container_data, textfield_data);

    const cursor_x = character_bounds.pos_x + character_bounds.scl_x;
    const cursor_y = character_bounds.pos_y;
    
    if(cursor.placement.absolute_offset.pos_x != cursor_x or cursor.placement.absolute_offset.pos_y != cursor_y)
    {
        cursor.placement.absolute_offset.pos_x = cursor_x;
        cursor.placement.absolute_offset.pos_y = cursor_y;

        cursor.refresh(true);
    }
}

/// Any textfield mouse input events that can't be handled by other mouse picking callbacks are handled here.
fn textfield_update_mouse_input(container_data: ContainerInputData, textfield_data: *TextFieldData) void
{
    if(container_data.mouse_buttons & 1 == 1 and !textfield_data.hovering and textfield_data.editing)
    {
        textfield_data.editing = false;
        textfield_data.update = true;
    }
}

/// Update the textfield's visuals during editing (cursor blinking).
fn textfield_update_editing_visual(e: *Element, textfield_data: *TextFieldData) void
{
    const text_space = e.children.items[0];
    const cursor = text_space.children.items[0];
    
    if(!textfield_data.editing_toggle)
    {
        textfield_data.cursor_timer = 1;
    }

    const cursor_visible = textfield_data.cursor_timer < 0.5;
    textfield_data.cursor_timer += 0.0125;
    
    if(textfield_data.cursor_timer >= 1)
    {
        textfield_data.cursor_timer -= 1;
    }

    if(textfield_data.cursor_timer < 0.5)
    {
        if(!cursor_visible)
        {
            cursor.coordinates = .{1, 1, 1, 1};
            cursor.refresh(false);
        }
    }
    else if(cursor_visible)
    {
        cursor.coordinates = .{1, 1, 1, 0};
        cursor.refresh(false);
    }

    textfield_data.editing_toggle = true;
}

/// Handles textfield key events, such as using the arrow keys to move the cursor's index position.
fn textfield_update_key_input(keys: []u32, textfield_data: *TextFieldData) void
{
    for(keys) |k|
    {
        if(k == glfw.KeyLeft)
        {
            if(textfield_data.current_cursor_pos > 0)
                textfield_data.current_cursor_pos -= 1;

            textfield_data.cursor_timer = 1;
        }
        else if(k == glfw.KeyRight)
        {
            if(textfield_data.current_cursor_pos < textfield_data.text.len)
                textfield_data.current_cursor_pos += 1;

            textfield_data.cursor_timer = 1;
        }
    }
}

/// Handles inputting text into the textfield. Returns true if the text elements actually need to be updated.
fn textfield_update_text_input(e: *Element, text: []u32, textfield_data: *TextFieldData) !bool
{
    var update_text: bool = false;

    var characters: u32 = 0;
    var backspaces: u32 = 0;

    for(text) |c|
    {
        if(c == 8)
        {
            backspaces += 1;
        }
        else
        {
            characters += 1;
        }
    }

    if(backspaces > textfield_data.current_cursor_pos)
    {
        backspaces = @truncate(textfield_data.current_cursor_pos);
    }

    if(characters != 0)
    {
        const new_slice = try insert_characters_into_text(e.allocator, textfield_data.current_cursor_pos, 
        text, textfield_data.text);

        textfield_data.text = new_slice;
        update_text = true;
    }

    if(backspaces != 0 and textfield_data.current_cursor_pos > 0)
    {
        const new_slice = try remove_characters_from_text(e.allocator, textfield_data.current_cursor_pos - backspaces,
        backspaces, textfield_data.text);

        textfield_data.text = new_slice;
        update_text = true;
    }

    textfield_data.update = true;
    textfield_data.cursor_timer = 1;

    return update_text;
}

/// Handles textfield container refreshing.
fn textfield_update_refreshing(e: *Element, container_data: ContainerInputData, textfield_data: *TextFieldData, update_text: bool) !void
{
    const text_space = e.children.items[0];

    if(textfield_data.editing)
    {
        e.coordinates = .{1, 1, 1, 1};
        text_space.coordinates = .{0.05, 0.05, 0.05, 1};
    }
    else if(textfield_data.hovering)
    {
        e.coordinates = .{1, 1, 1, 1};
        text_space.coordinates = .{0.175, 0.175, 0.175, 1};
    }
    else
    {
        e.coordinates = .{0.8, 0.8, 0.8, 1};
        text_space.coordinates = .{0.125, 0.125, 0.125, 1};
    }

    if(update_text)
    {
        container_data.container.signal_rebuild = true;
    }
    else
    {
        e.refresh(true);
    }

    textfield_data.update = false;
}

fn textfield_callback_tick(e: *Element, data: ContainerInputData) !void
{
    var textfield_data: TextFieldData = undefined;
    memcpy_anonymous(&textfield_data, e.data.?.ptr, @sizeOf(TextFieldData));

    try textfield_update_cursor_placement(e, data, textfield_data);
    textfield_update_mouse_input(data, &textfield_data);

    const text_space = e.children.items[0];
    const cursor = text_space.children.items[0];

    var update_text: bool = false;
    if(textfield_data.editing)
    {
        // Show the cursor.
        textfield_update_editing_visual(e, &textfield_data);

        if(data.keys != null)
        {
            // Possibly move the cursor with the arrow keys.
            textfield_update_key_input(data.keys.?, &textfield_data);
        }

        if(data.text != null)
        {
            // Possibly add text to the textfield.
            update_text = try textfield_update_text_input(e, data.text.?, &textfield_data);
        }
    }
    else
    {
        // Hide the cursor. 
        if(cursor.coordinates[3] != 0)
        {
            cursor.coordinates[3] = 0;
            cursor.refresh(false);
        }

        textfield_data.editing_toggle = false;
    }

    if(textfield_data.update)
    {
        // Handling refreshing and extensions.
        try textfield_update_refreshing(e, data, &textfield_data, update_text);
    }

    // Updating the textfield space.
    
    const prev_space = text_space.space;
    const space = try get_text_space(e, data);

    if(prev_space.pos_x != space.pos_x or prev_space.pos_y != space.pos_y or prev_space.scl_x != space.scl_x or prev_space.scl_y != space.scl_y)
    {
        text_space.space = space;
        try text_parent_resize_callback(text_space.children.items[1], data);
        text_space.refresh(true);
    }

    textfield_data.prev_cursor_pos = textfield_data.current_cursor_pos;
    memcpy_anonymous(e.data.?.ptr, &textfield_data, @sizeOf(TextFieldData));
}

/// Creates a textfield element, which the user can store text within.
pub fn create_textfield(allocator: *const std.mem.Allocator, placement: Placement, properties: TextFieldProperties) !*Element
{
    if(properties.text_alignment.y == .Center)
    {
        @panic("[ASH|ERR] Ashbloom's basic UI theme doesn't support center-Y text alignment for textfields.");
    }

    const e = try allocator.create(Element);

    e.* = try Element.init(allocator, .Color, placement, .{0.8, 0.8, 0.8, 1});

    const inner = try allocator.create(Element);

    const inner_placement: Placement = .{
        .relative_pos = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 1,
            .scl_y = 1
        },
        .absolute_offset = .{
            .pos_x = 1,
            .pos_y = 1,
            .scl_x = -2,
            .scl_y = -2
        },
        .alignment = .{
            .x = .Left,
            .y = .Bottom
        }
    };

    inner.* = try Element.init(allocator, .Color, inner_placement, .{0.125, 0.125, 0.125, 1});

    const cursor = try allocator.create(Element);

    const cursor_placement: Placement = .{
        .relative_pos = .get_default(),
        .absolute_offset = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 3,
            .scl_y = properties.text_size
        },
        .alignment = .{
            .x = .Left,
            .y = .Bottom
        }
    };

    cursor.* = try Element.init(allocator, .Color, cursor_placement, .{1, 1, 1, 1});

    var text_properties: TextProperties = .init(properties.font, properties.text_size, properties.text_alignment, properties.initial_text);

    text_properties.margin = 5;

    const text = try create_text(allocator, text_properties);
    var data: TextFieldData = try .init(allocator, properties);

    e.data = try allocator.alloc(u8, @sizeOf(TextFieldData));
    memcpy_anonymous(e.data.?.ptr, &data, @sizeOf(TextFieldData));

    try inner.add_callback(.WindowResize, textfield_callback_window_resize);

    try inner.add_and_dispose(cursor);
    try inner.add_and_dispose(text);
    try e.add_and_dispose(inner);

    try e.add_callback(.MouseEnter, textfield_callback_mouse_enter);
    try e.add_callback(.MouseLeave, textfield_callback_mouse_leave);
    try e.add_callback(.MousePress, textfield_callback_mouse_press);
    try e.add_callback(.Copy, textfield_callback_copy);
    try e.add_callback(.Deinit, textfield_callback_deinit);
    try e.add_callback(.Rebuild, textfield_callback_rebuild);
    try e.add_callback(.Tick, textfield_callback_tick);

    return e;
}

/// Returns the unicode string currently inside a textfield.
pub fn get_textfield_text(e: *Element) []u32
{
    var textfield_data: TextFieldData = undefined;
    memcpy_anonymous(&textfield_data, e.data.?.ptr, @sizeOf(TextFieldData));

    return textfield_data.text;
}

pub fn init_basic_render_pass(context: *VkContext, swapchain: Swapchain) !*RenderPass
{
    const color_subpass: RenderPass.Subpass = .{
        .color_attachment_index = 0,
        .color_attachment_layout = .color_attachment_optimal,
        .subpass_bind_point = .graphics,
        .subpass_dependency = .{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = undefined,
            .src_access_mask = .{},
            .src_stage_mask = .{
                .color_attachment_output_bit = true
            },
            .dst_access_mask = .{
                .color_attachment_write_bit = true
            },
            .dst_stage_mask = .{
                .color_attachment_output_bit = true
            }
        }
    };

    var ui_render_pass = try context.allocator.create(RenderPass);
    ui_render_pass.* = try .init(context);

    try ui_render_pass.add_attachment_description_no_stencil_multisample
    (swapchain.format.format, .clear, .store, .undefined, .present_src_khr);
    try ui_render_pass.add_subpass(color_subpass);
    try ui_render_pass.build();

    return ui_render_pass;
}

fn init_basic_pipeline_descriptor_set(context: *VkContext, vk_allocator: *VulkanAllocator, swapchain: Swapchain, container: Container) !*PipelineDescriptorSet
{
    var ui_descriptor_set = try context.allocator.create(PipelineDescriptorSet);
    ui_descriptor_set.* = try .init(context, vk_allocator, @truncate(swapchain.image_count));

    try ui_descriptor_set.add_binding(.{
        .binding_index = 0,
        .type = .uniform_buffer,
        .shader_stage = .{
            .vertex_bit = true
        },
        .info = .{ .buffer = .{
            .buffer_size = 16 * @sizeOf(f32)
        }}
    });

    try ui_descriptor_set.add_binding(.{
        .binding_index = 1,
        .type = .combined_image_sampler,
        .shader_stage = .{
            .fragment_bit = true
        },
        .info = .{ .image = .{
            .image_sampler = container.texture_atlas.sampler,
            .image_layout = .shader_read_only_optimal,
            .image_view = container.texture_atlas.image_view
        }}
    });

    try ui_descriptor_set.build();

    return ui_descriptor_set;
}

fn init_basic_pipeline(context: *VkContext, descriptor_set: PipelineDescriptorSet, render_pass: *RenderPass) !*Pipeline
{
    var ui_pipeline = try context.allocator.create(Pipeline);
    ui_pipeline.* = try .init(context);

    var pvi = try pipeline.PipelineVertexInput.init(context.allocator);
    defer pvi.deinit();

    try pvi.add_attribute(0, 0, vk.Format.r32_sfloat, 0);
    try pvi.add_attribute(0, 1, vk.Format.r32g32b32a32_sfloat, @sizeOf(u32));
    try pvi.add_attribute(0, 2, vk.Format.r32g32b32a32_sfloat, @sizeOf(u32) + 4 * @sizeOf(f32));
    try pvi.add_attribute(0, 3, vk.Format.r32g32b32a32_sfloat, @sizeOf(u32) + 8 * @sizeOf(f32));

    try pvi.build(0, vk.VertexInputRate.instance);

    try ui_pipeline.add_shader_module("shaders/ui_basic_vert.spv", .{.vertex_bit = true});
    try ui_pipeline.add_shader_module("shaders/ui_basic_frag.spv", .{.fragment_bit = true});

    try ui_pipeline.add_dynamic_state(vk.DynamicState.viewport);
    try ui_pipeline.add_dynamic_state(vk.DynamicState.scissor);

    try ui_pipeline.add_descriptor_set(descriptor_set);

    try ui_pipeline.add_color_blend_attachment(pipeline.pipeline_color_blend_attachment_alpha_blend());

    ui_pipeline.set_vertex_input(&pvi);

    try ui_pipeline.build(render_pass);

    return ui_pipeline;
}

fn update_ui_basic_uniforms(container: Container, set_index: u16) !void
{
    const width = container.bounds.scl_x;
    const height = container.bounds.scl_y;

    var projection = try math.mat_projection_orthographic(container.context.allocator, 0, width, 0, height, -1, 1);

    const projection_data = try math.mat_slice_data(f32, projection);

    projection.deinit();

    try container.ui_rendering.descriptor_set.place_data(set_index, 0, f32, projection_data, 0);

    container.context.allocator.free(projection_data);
}

/// Creates a ContainerRendering struct compatible with the basic UI element factories provided in this module.
pub fn init_render_instance(context: *VkContext, vulkan_allocator: *VulkanAllocator, swapchain: Swapchain, container: Container, render_pass: ?*RenderPass, render_queue: vk.Queue) !vkui.ContainerRendering
{
    const rp = render_pass orelse try init_basic_render_pass(context, swapchain);

    const ui_descriptor_set = try init_basic_pipeline_descriptor_set(context, vulkan_allocator, swapchain, container);
    const ui_pipeline = try init_basic_pipeline(context, ui_descriptor_set.*, rp);

    return .{
        .render_pass = rp,
        .descriptor_set = ui_descriptor_set,
        .pipeline = ui_pipeline,
        .render_queue = render_queue,
        .uniform_callback = update_ui_basic_uniforms,
        .render_pass_is_reference = render_pass != null
    };
}

const xml = ash.xml;

const XMLUIError = error
{
    UnknownElement,
    UnknownAttribute,
    CannotParseData,
    TooMuchData,
    WrongClosingTag
};

const XMLAttribute = struct
{
    name: []const u8,
    value: []const u8
};

fn character_is_whitespace(c: u32) bool
{
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

fn character_is_number(c: u32) bool
{
    return (c >= 48 and c <= 57) or c == 46 or c == 45;
}

fn character_is_letter(c: u32) bool
{
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95;
}

fn trim_string(comptime T: type, str: []const T) []const T
{
    var start_index: usize = 0;
    var end_index: usize = str.len - 1;

    for(0..str.len) |i|
    {
        if(character_is_whitespace(str[i]))
        {
            start_index += 1;
        }
        else
        {
            break;
        }
    }

    if(start_index == str.len) return &.{};

    var read_mode = false;

    for(start_index..str.len) |i|
    {
        if(character_is_whitespace(str[i]) and !read_mode)
        {
            read_mode = true;
            end_index = i;
        }
        else if(!character_is_whitespace(str[i]))
        {
            read_mode = false;
        }

        if(i == str.len - 1 and !read_mode)
        {
            end_index = str.len;
        }
    }

    return str[start_index..end_index];
}

fn parse_4_floats(s: []const u8) ![4]f32
{
    var reading_number = false;
    var number_start: usize = 0;

    var current_float: usize = 0;
    var floats: [4]f32 = undefined;

    for(s, 0..) |_, i|
    {
        if(character_is_whitespace(s[i]))
        {
            if(reading_number)
            {
                reading_number = false;

                if(current_float >= 4)
                {
                    return XMLUIError.TooMuchData;
                }

                const number_str = s[number_start..i];
                floats[current_float] = try std.fmt.parseFloat(f32, number_str);
            }

            continue;
        }

        if(character_is_number(s[i]))
        {
            if(!reading_number)
            {
                reading_number = true;
                number_start = i;
            }
        }
        else
        {
            if(reading_number)
            {
                reading_number = false;

                if(current_float >= 4)
                {
                    return XMLUIError.TooMuchData;
                }

                const number_str = s[number_start..i];
                floats[current_float] = try std.fmt.parseFloat(f32, number_str);
            }
        }

        if(s[i] == ',')
        {
            current_float += 1;
        }

        if(i == s.len - 1)
        {
            if(reading_number)
            {
                reading_number = false;

                if(current_float >= 4)
                {
                    return XMLUIError.TooMuchData;
                }

                const number_str = s[number_start..s.len];
                floats[current_float] = try std.fmt.parseFloat(f32, number_str);
            }
        }
    }

    return floats;
}

fn parse_alignment(s: []const u8) !vkui.Alignment
{
    var reading_word = false;
    var word_start: usize = 0;

    var current_word: usize = 0;
    var words: [2][]const u8 = undefined;

    for(s, 0..) |_, i|
    {
        if(character_is_whitespace(s[i]))
        {
            if(reading_word)
            {
                words[current_word] = s[word_start..i];
                reading_word = false;
            }

            continue;
        }

        if(character_is_letter(s[i]))
        {
            if(!reading_word)
            {
                if(current_word >= 2) return XMLUIError.CannotParseData;

                word_start = i;
                reading_word = true;
            }
        }
        else if(s[i] == ',')
        {
            if(reading_word)
            {
                words[current_word] = s[word_start..i];
                reading_word = false;
            }

            current_word += 1;
        }
        else
        {
            return XMLUIError.CannotParseData;
        }

        if(i == s.len - 1)
        {
            words[current_word] = s[word_start..s.len];
        }
    }

    var horizontal = false;
    var vertical = false;

    var alignment: vkui.Alignment = undefined;

    for(0..2) |i|
    {
        if(std.mem.eql(u8, words[i], "left"))
        {
            horizontal = true;
            alignment.x = .Left;
        }
        else if(std.mem.eql(u8, words[i], "right"))
        {
            horizontal = true;
            alignment.x = .Right;
        }
        else if(std.mem.eql(u8, words[i], "bottom"))
        {
            vertical = true;
            alignment.y = .Bottom;
        }
        else if(std.mem.eql(u8, words[i], "top"))
        {
            vertical = true;
            alignment.y = .Top;
        }
        else if(std.mem.eql(u8, words[i], "center"))
        {
            if(horizontal and !vertical)
            {
                vertical = true;
                alignment.y = .Center;
            }
            else
            {
                horizontal = true;
                alignment.x = .Center;
            }
        }
    }

    if(!horizontal or !vertical) return XMLUIError.CannotParseData;
    return alignment;
}

fn load_xml_quad(allocator: *const std.mem.Allocator, attributes: []XMLAttribute) !*Element
{
    var color: [4]f32 = undefined;
    for(attributes) |att|
    {
        if(std.mem.eql(u8, att.name, "color"))
        {
            color = try parse_4_floats(att.value);
        }
        else
        {
            return XMLUIError.UnknownAttribute;
        }
    }

    const default_placement: Placement = .{
        .relative_pos = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 1,
            .scl_y = 1
        },
        .absolute_offset = .get_default(),
        .alignment = .{
            .x = .Left,
            .y = .Bottom
        }
    };

    return create_quad(allocator, default_placement, color);
}

fn load_xml_text(allocator: *const std.mem.Allocator, attributes: []XMLAttribute, assets: XMLUIAssets) !*Element
{
    var font = assets.fonts[0].font;

    var alignment: vkui.Alignment = .{ .x = .Center, .y = .Center };

    var margin: f32 = 3;
    var size: f32 = 30;

    for(attributes) |att|
    {
        if(std.mem.eql(u8, att.name, "alignment"))
        {
            alignment = try parse_alignment(att.value);
        }
        else if(std.mem.eql(u8, att.name, "margin"))
        {
            margin = try std.fmt.parseFloat(f32, att.value);
        }
        else if(std.mem.eql(u8, att.name, "size"))
        {
            size = try std.fmt.parseFloat(f32, att.value);
        }
        else if(std.mem.eql(u8, att.name, "font"))
        {
            for(assets.fonts) |f|
            {
                if(std.mem.eql(u8, att.value, f.name))
                {
                    font = f.font;
                }
            }
        }
        else
        {
            return XMLUIError.UnknownAttribute;
        }
    }

    const text_properties: TextProperties = .{
        .alignment = alignment,
        .font = font,
        .margin = margin,
        .size = size,
        .string = &.{}
    };

    return try create_text(allocator, text_properties);
}

fn load_xml_button(allocator: *const std.mem.Allocator, attributes: []XMLAttribute) !*Element
{
    var color_idle: [4]f32 = .{1, 1, 1, 0.3};
    var color_hover: [4]f32 = .{1, 1, 1, 0.6};
    var color_press: [4]f32 = .{1, 1, 1, 0.75};

    for(attributes) |att|
    {
        if(std.mem.eql(u8, att.name, "color_idle"))
        {
            color_idle = try parse_4_floats(att.value);
        }
        else if(std.mem.eql(u8, att.name, "color_hover"))
        {
            color_hover = try parse_4_floats(att.value);
        }
        else if(std.mem.eql(u8, att.name, "color_press"))
        {
            color_press = try parse_4_floats(att.value);
        }
        else
        {
            return XMLUIError.UnknownAttribute;
        }
    }

    const button_properties: ButtonProperties = .{
        .color_idle = color_idle,
        .color_hover = color_hover,
        .color_press = color_press,
        
        .placement = .{
            .relative_pos = .{
                .pos_x = 0,
                .pos_y = 0,
                .scl_x = 1,
                .scl_y = 1
            },
            .absolute_offset = .get_default(),
            .alignment = .{
                .x = .Left,
                .y = .Bottom
            }
        },

        .press_callback = empty_press_callback
    };

    return create_button(allocator, button_properties);
}

fn load_xml_scrollbar(allocator: *const std.mem.Allocator) !*Element
{
    return create_scrollbar(allocator);
}

fn load_xml_checkbox(allocator: *const std.mem.Allocator, attributes: []XMLAttribute) !*Element
{
    var color_border: [4]f32 = .{1, 1, 1, 1};
    var color_hover: [4]f32 = .{1, 1, 1, 0.4};
    var color_ticked: [4]f32 = .{1, 1, 1, 1};

    var border_width: f32 = 4;
    var start_ticked: u1 = 0;

    for(attributes) |att|
    {
        if(std.mem.eql(u8, att.name, "color_border"))
        {
            color_border = try parse_4_floats(att.value);
        }
        else if(std.mem.eql(u8, att.name, "color_hover"))
        {
            color_hover = try parse_4_floats(att.value);
        }
        else if(std.mem.eql(u8, att.name, "color_ticked"))
        {
            color_ticked = try parse_4_floats(att.value);
        }
        else if(std.mem.eql(u8, att.name, "border_width"))
        {
            border_width = try std.fmt.parseFloat(f32, att.value);
        }
        else if(std.mem.eql(u8, att.name, "start_ticked"))
        {
            start_ticked = try std.fmt.parseInt(u1, att.value, 10);
        }
        else
        {
            return XMLUIError.UnknownAttribute;
        }
    }

    const checkbox_properties: CheckboxProperties = .{
        .color_border = color_border,
        .color_hover = color_hover,
        .color_ticked = color_ticked,

        .border_width = border_width,
        .start_ticked = start_ticked == 1,
        
        .placement = .{
            .relative_pos = .{
                .pos_x = 0,
                .pos_y = 0,
                .scl_x = 1,
                .scl_y = 1
            },
            .absolute_offset = .get_default(),
            .alignment = .{
                .x = .Left,
                .y = .Bottom
            }
        },

        .callback = empty_checkbox_callback
    };

    return create_checkbox(allocator, checkbox_properties);
}

fn load_xml_placement(attributes: []XMLAttribute) !Placement
{
    var relative: [4]f32 = undefined;
    var absolute: [4]f32 = undefined;

    var alignment: vkui.Alignment = undefined;

    for(attributes) |att|
    {
        if(std.mem.eql(u8, att.name, "relative"))
        {
            relative = try parse_4_floats(att.value);
        }
        else if(std.mem.eql(u8, att.name, "absolute"))
        {
            absolute = try parse_4_floats(att.value);
        }
        else if(std.mem.eql(u8, att.name, "alignment"))
        {
            alignment = try parse_alignment(att.value);
        }
        else
        {
            return XMLUIError.UnknownAttribute;
        }
    }

    return .{
        .relative_pos = .{
            .pos_x = relative[0],
            .pos_y = relative[1],
            .scl_x = relative[2],
            .scl_y = relative[3]
        },
        .absolute_offset = .{
            .pos_x = absolute[0],
            .pos_y = absolute[1],
            .scl_x = absolute[2],
            .scl_y = absolute[3]
        },
        .alignment = alignment
    };
}

pub const XMLUIFontEntry = struct
{
    name: []const u8,
    font: *Font
};

pub const XMLUICallbackEntry = struct
{
    name: []const u8,
    callback: *const fn(*Element, ContainerInputData) anyerror!void
};

pub const XMLUIAssets = struct
{
    fonts: []const XMLUIFontEntry,
    callbacks: []const XMLUICallbackEntry
};

fn xml_finish_element(element_type: BasicUIElementType, root: *Element, element_stack: *std.ArrayList(*Element), element_type_stack: *std.ArrayList(BasicUIElementType)) !void
{
    const current_type = element_type_stack.items[element_type_stack.items.len - 1];

    if(current_type != element_type)
    {
        return XMLUIError.WrongClosingTag;
    }
    else
    {
        if(element_stack.items.len == 1)
        {
            try root.add_and_dispose(element_stack.items[0]);
        }
        else
        {
            const end = element_stack.items.len - 1;
            try element_stack.items[end - 1].add_and_dispose(element_stack.items[end]);
        }

        _ = element_stack.pop();
        _ = element_type_stack.pop();
    }
}

fn load_xml_ui_elements(allocator: *const std.mem.Allocator, reader: *xml.Reader, root: *Element, assets: XMLUIAssets) !void
{
    var element_stack: std.ArrayList(*Element) = try .initCapacity(allocator.*, 0);
    defer element_stack.deinit(allocator.*);

    var element_type_stack: std.ArrayList(BasicUIElementType) = try .initCapacity(allocator.*, 0);
    defer element_type_stack.deinit(allocator.*);

    while(true)
    {
        const node = reader.read() catch |err| switch(err)
        {
            error.MalformedXml => {
                const loc = reader.errorLocation();

                std.debug.print("[ASH|XML|ERR] Bad XML at {}:{} - {}\n", .{loc.line, loc.column, reader.errorCode()});
                return error.MalformedXml;
            },
            else => {
                std.debug.print("[ASH|XML|ERR] Unknown XML error.\n", .{});
                return err;
            }
        };

        switch(node)
        {
            .eof => break,
            .element_start =>
            {
                const element_name = reader.elementNameNs().local;
                ash.print_stdout("New tag: {s}\n", .{element_name});

                var attributes = try allocator.alloc(XMLAttribute, reader.attributeCount());
                defer allocator.free(attributes);

                for(0..reader.attributeCount()) |i|
                {
                    const attribute_name = reader.attributeNameNs(i);
                    const attribute_value = try reader.attributeValue(i);

                    ash.print_stdout("\tAttribute: {s} = {s}\n", .{attribute_name.local, attribute_value});

                    attributes[i] = .{
                        .name = attribute_name.local,
                        .value = attribute_value
                    };
                }

                if(std.mem.eql(u8, element_name, "quad"))
                {
                    try element_type_stack.append(allocator.*, .Quad);

                    const new_element = try load_xml_quad(allocator, attributes);
                    try element_stack.append(allocator.*, new_element);
                }
                else if(std.mem.eql(u8, element_name, "text"))
                {
                    try element_type_stack.append(allocator.*, .Text);

                    const new_element = try load_xml_text(allocator, attributes, assets);
                    try element_stack.append(allocator.*, new_element);
                }
                else if(std.mem.eql(u8, element_name, "button"))
                {
                    try element_type_stack.append(allocator.*, .Button);

                    const new_element = try load_xml_button(allocator, attributes);
                    try element_stack.append(allocator.*, new_element);
                }
                else if(std.mem.eql(u8, element_name, "scrollbar"))
                {
                    try element_type_stack.append(allocator.*, .Scrollbar);

                    const new_element = try load_xml_scrollbar(allocator);
                    try element_stack.append(allocator.*, new_element);
                }
                else if(std.mem.eql(u8, element_name, "checkbox"))
                {
                    try element_type_stack.append(allocator.*, .Checkbox);

                    const new_element = try load_xml_checkbox(allocator, attributes);
                    try element_stack.append(allocator.*, new_element);
                }
                else if(std.mem.eql(u8, element_name, "placement"))
                {
                    const placement = try load_xml_placement(attributes);
                    element_stack.items[element_stack.items.len - 1].placement = placement;
                }
                else
                {
                    return XMLUIError.UnknownElement;
                }
            },
            .element_end => {
                const element_name = reader.elementNameNs().local;
                ash.print_stdout("End tag: {s}\n", .{element_name});
                ash.print_stdout("\tCurrent stack length: {d}\n", .{element_stack.items.len});

                if(std.mem.eql(u8, element_name, "quad"))
                {
                    try xml_finish_element(.Quad, root, &element_stack, &element_type_stack);
                }
                else if(std.mem.eql(u8, element_name, "text"))
                {
                    try xml_finish_element(.Text, root, &element_stack, &element_type_stack);
                }
                else if(std.mem.eql(u8, element_name, "button"))
                {
                    try xml_finish_element(.Button, root, &element_stack, &element_type_stack);
                }
                else if(std.mem.eql(u8, element_name, "scrollbar"))
                {
                    try xml_finish_element(.Scrollbar, root, &element_stack, &element_type_stack);
                }
                else if(std.mem.eql(u8, element_name, "checkbox"))
                {
                    try xml_finish_element(.Checkbox, root, &element_stack, &element_type_stack);
                }
            },
            .text => {
                const current_type = element_type_stack.items[element_type_stack.items.len - 1];
                
                if(current_type == .Text)
                {
                    const text = try reader.text();
                    const index = element_stack.items.len - 1;

                    ash.print_stdout("Text tag: {s}\n", .{text});

                    const flattened_text = trim_string(u8, text);
                    ash.print_stdout("\t(trim string): {s}\n", .{flattened_text});

                    var text_data: TextData = undefined;
                    memcpy_anonymous(&text_data, element_stack.items[index].data.?.ptr, @sizeOf(TextData));

                    try element_stack.items[index].deinit();
                    allocator.destroy(element_stack.items[index]);

                    const str = try allocator.alloc(u32, flattened_text.len);
                    defer allocator.free(str);

                    const text_properties: TextProperties = .{
                        .alignment = text_data.alignment,
                        .font = text_data.font,
                        .margin = text_data.margin,
                        .size = text_data.size,
                        .string = str
                    };

                    for(0..flattened_text.len) |i|
                    {
                        text_properties.string[i] = flattened_text[i];
                    }

                    element_stack.items[index] = try create_text(allocator, text_properties);
                }
            },
            else => {}
        }
    }
}

pub fn load_xml_ui(allocator: *const std.mem.Allocator, path: []const u8, element: *Element, assets: XMLUIAssets) !void
{
    var io_threaded = std.Io.Threaded.init(allocator.*, .{});
    defer io_threaded.deinit();

    const io = io_threaded.io();

    const cwd = std.Io.Dir.cwd();

    const file = try cwd.openFile(io, path, .{});
    defer file.close(io);

    var read_buffer: [1024]u8 = undefined;
    var reader = file.reader(io, &read_buffer);

    var xml_streaming_reader: xml.Reader.Streaming = .init(allocator.*, &reader.interface, .{});
    defer xml_streaming_reader.deinit();

    const xml_reader = &xml_streaming_reader.interface;

    try load_xml_ui_elements(allocator, xml_reader, element, assets);
}
