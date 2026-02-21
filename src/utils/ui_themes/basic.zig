const std = @import("std");
const glfw = @import("glfw");

const imp_font = @import("../font.zig");

const vkui = @import("../vkui.zig");
const math = @import("../linalg.zig");

const Font = imp_font.Font;
const FontCharacter = imp_font.FontCharacter;

const Container = vkui.Container;
const Element = vkui.Element;
const Placement = vkui.Placement;
const ContainerInputData = vkui.ContainerInputData;

fn memcpy_anonymous(dst: *anyopaque, src: *anyopaque, size: usize) void
{
    const dest_data: [*]u8 = @as([*]u8, @ptrCast(dst));
    const copy_data: []u8 = @as([*]u8, @ptrCast(src))[0..size];
    @memcpy(dest_data, copy_data);
}

pub fn create_quad(allocator: *const std.mem.Allocator, placement: Placement, color: [4]f32) !*Element
{
    const e = try allocator.create(Element);

    e.* = try Element.init(allocator, .Color, placement, color);
    return e;
}

pub fn create_icon(allocator: *const std.mem.Allocator, placement: Placement, tex_coords: [4]f32) !*Element
{
    const e = try allocator.create(Element);

    e.* = try Element.init(allocator, .Texture, placement, tex_coords);
    return e;
}

pub const FontCharacterElement = struct
{
    element: *Element,
    character: FontCharacter
};

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
        .scl_x = suballoc.scl_x * @as(f32, @floatFromInt(font.atlas.width)),
        .scl_y = suballoc.scl_y * @as(f32, @floatFromInt(font.atlas.height))
    };

    e.* = try Element.init(allocator, .Character, scaled_placement, 
    .{suballoc.pos_x, suballoc.pos_y, suballoc.scl_x, suballoc.scl_y});

    return .{
        .element = e,
        .character = character
    };
}

const TextLine = struct
{
    // Offset of the text array where the line starts.
    start: usize,
    // Number of characters the line contains.
    length: usize,
    // Width of the line, in pixels.
    size: f32,
    // Amount of pixels to 'push' the line forward so that it fits the horizontal alignment.
    alignment_push: f32
};

const TextData = struct
{
    font: *Font,
    size: f32,
    alignment: vkui.Alignment,
    string: []u32,
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

        word_mode = text.string[line_start] != ' ';
        
        for(line_start..text.string.len) |i|
        {
            const unicode = text.string[i];
            const character = try data.container.font.?.request(unicode, text.size);

            loop_text_character(i, text.string, character, container_width, &line_end, &offset, &prev_offset,
            &line_length, &end_skip, &word_mode, &should_break);

            if(should_break) break;
        }

        line += 1;
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

        for(line_start..element.children.items.len) |i|
        {
            const unicode = text.string[i];
            const character = try data.container.font.?.request(unicode, text.size);

            loop_text_character(i, text.string, character, container_width, &line_end, &offset, &prev_offset,
            &line_length, &end_skip, &word_mode, &should_break);

            if(should_break) break;
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
            const ch = try data.container.font.?.request(uc, text_data.size);

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

pub const TextProperties = struct
{
    font: *Font,
    size: f32,
    alignment: vkui.Alignment,
    string: []u32,
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

pub fn create_text(allocator: *const std.mem.Allocator, properties: TextProperties) !*Element
{
    const placement: Placement = .get_default();

    const e = try allocator.create(Element);
    e.* = try Element.init(allocator, .None, placement, .{0, 0, 0, 0});

    for(properties.string) |ch|
    {
        const fce = try create_text_character(allocator, placement, properties.font, properties.size, ch);
        _ = try e.add_and_dispose(fce.element);
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
    var callback: *const fn(*Element) void = undefined;

    const data_offset: usize = @sizeOf(u8) + @sizeOf(f32);

    memcpy_anonymous(&callback_data, e.data.?.ptr + data_offset, @sizeOf(*const fn(*Element) void));
    @memcpy(@as([*]u8, @ptrCast(&callback)), callback_data[0..@sizeOf(*const fn(*Element) void)]);

    if(data.mouse_buttons & 1 == 0)
    {
        if(e.data.?[0] == 2)
        {
            callback(e);
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

fn empty_press_callback(e: *Element) void
{
    _ = e;
}

pub const ButtonProperties = struct
{
    placement: Placement,

    color_idle: [4]f32,
    color_hover: [4]f32,
    color_press: [4]f32,

    press_callback: *const fn(*Element) void,

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
    memcpy_anonymous(e.data.?.ptr + data_offset, @ptrCast(&press_callback_alias), @sizeOf(*const fn(*Element) void));
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

fn scrollbar_callback_mouse_release(e: *Element, data: ContainerInputData) !void
{
    _ = e;
    _ = data;
}

fn scrollbar_horizontal_callback_tick(e: *Element, data: ContainerInputData) !void
{
    const parent = e.parent.?.parent.?;
    const bounds = try data.container.get_element_bounds(e.lineage.?[0..e.lineage.?.len - 2]);
    const child = e.children.items[0];

    var scroll_button_prev_pos: f32 = 0;
    memcpy_anonymous(&scroll_button_prev_pos, e.data.?.ptr, @sizeOf(f32));

    var should_refresh: bool = false;

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
        const bar_width = bounds.cut_bounds.scl_x - 20;

        const scroll_button_width_ratio = bounds.cut_bounds.scl_x / bounds.draw_bounds.scl_x;
        const scroll_button_width = scroll_button_width_ratio * bar_width;

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
    const scroll_button_width = scroll_button_width_ratio * bar_width;

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
        const scroll_button_height_ratio = bounds.cut_bounds.scl_y / bounds.draw_bounds.scl_y;
        const scroll_button_height = scroll_button_height_ratio * bounds.cut_bounds.scl_y;

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
    const scroll_button_height = scroll_button_height_ratio * bounds.cut_bounds.scl_y;
    
    const scroll_button_pos_ratio = e.parent.?.space.pos_y / bounds.draw_bounds.scl_y;
    var scroll_button_pos = scroll_button_pos_ratio * bounds.cut_bounds.scl_y;

    child.placement.absolute_offset.pos_y = scroll_button_pos;
    memcpy_anonymous(e.data.?.ptr, &scroll_button_pos, @sizeOf(f32));

    child.placement.absolute_offset.scl_y = scroll_button_height;

    e.refresh(true);
}

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
    try vertical_scroll.add_callback(.MouseRelease, scrollbar_callback_mouse_release);
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

    _ = try vertical_scroll.add_and_dispose(vertical_scroll_button);
    _ = try e.add_and_dispose(vertical_scroll);

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
    try horizontal_scroll.add_callback(.MouseRelease, scrollbar_callback_mouse_release);
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

    _ = try horizontal_scroll.add_and_dispose(horizontal_scroll_button);
    _ = try e.add_and_dispose(horizontal_scroll);

    return e;
}

const TextFieldData = struct
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
    ScrollHorizontally,
    ScrollVertically
};

const TextFieldProperties = struct
{
    font: *Font,
    text_size: f32 = 20,
    text_alignment: vkui.Alignment = .{
        .x = .Left,
        .y = .Top
    },

    initial_text: []u32 = &.{},
    extension_protocol: TextFieldExtension = .ScrollHorizontally
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

    var scl_y = max_y - min_y;
    if(scl_y < border_bounds.scl_y - 2)
    {
        scl_y = border_bounds.scl_y - 2;
    }

    var pos_y: f32 = (cursor_bounds.pos_y - inner_bounds.pos_y) - border_bounds.scl_y + cursor_bounds.scl_y;
    if(pos_y < 0)
    {
        pos_y = 0;
    }

    return .{
        .pos_x = 0,
        .pos_y = pos_y,
        .scl_x = inner_bounds.scl_x,
        .scl_y = scl_y + text_data.size
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

fn textfield_callback_mouse_release(e: *Element, data: ContainerInputData) !void
{
    _ = e;
    _ = data;
}

fn textfield_callback_rebuild(e: *Element, data: ContainerInputData) !void
{
    _ = data;

    var textfield_data: TextFieldData = undefined;
    memcpy_anonymous(&textfield_data, e.data.?.ptr, @sizeOf(TextFieldData));

    const text_space = e.children.items[0];
    const text = text_space.children.items[1];

    const previous_text_size = text.children.items.len;

    try text_space.remove_by_index(1);

    var text_properties: TextProperties = .init(textfield_data.font, textfield_data.text_size, textfield_data.text_alignment, textfield_data.text);

    text_properties.margin = 5;

    const new_text = try create_text(e.allocator, text_properties);
    var text_ptr = try text_space.add_and_dispose(new_text);

    const diff: isize = @as(isize, @intCast(textfield_data.text.len)) - @as(isize, @intCast(previous_text_size));
    textfield_data.current_cursor_pos +%= @bitCast(diff);

    memcpy_anonymous(e.data.?.ptr, &textfield_data, @sizeOf(TextFieldData));

    try text_ptr.force_callback(.WindowResize);
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
        text_space.refresh(true);
    }

    textfield_data.prev_cursor_pos = textfield_data.current_cursor_pos;
    memcpy_anonymous(e.data.?.ptr, &textfield_data, @sizeOf(TextFieldData));
}

pub fn create_textfield(allocator: *const std.mem.Allocator, placement: Placement, properties: TextFieldProperties) !*Element
{
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

    _ = try inner.add_and_dispose(cursor);
    _ = try inner.add_and_dispose(text);
    _ = try e.add_and_dispose(inner);

    try e.add_callback(.MouseEnter, textfield_callback_mouse_enter);
    try e.add_callback(.MouseLeave, textfield_callback_mouse_leave);
    try e.add_callback(.MousePress, textfield_callback_mouse_press);
    try e.add_callback(.MouseRelease, textfield_callback_mouse_release);
    try e.add_callback(.Copy, textfield_callback_copy);
    try e.add_callback(.Deinit, textfield_callback_deinit);
    try e.add_callback(.Rebuild, textfield_callback_rebuild);
    try e.add_callback(.Tick, textfield_callback_tick);

    return e;
}