const std = @import("std");
const ash = @import("../root.zig");

const ui = @import("vkui.zig");

const Element = ui.Element;
const ContainerInputData = ui.ContainerInputData;

pub const Direction = enum
{
    LeftToRight,
    RightToLeft,
    BottomToTop,
    TopToBottom,

    pub fn is_negative(self: Direction) bool
    {
        return self == RightToLeft or self == TopToBottom;
    }

    pub fn is_vertical(self: Direction) bool
    {
        return self == BottomToTop or self == TopToBottom;
    }
};

pub const LinearLayoutDirection = struct
{
    towards: Direction,
    spacing: f32,
    margin: f32
};

pub const LinearLayoutProperties = struct
{
    primary_direction: LinearLayoutDirection,
    secondary_direction: LinearLayoutDirection,
};

fn linear_layout_update(e: *Element, data: ContainerInputData) !void
{
    var properties: LinearLayoutProperties = undefined;
    ash.misc.memcpy_anonymous(&properties, e.layout_data.?.ptr, @sizeOf(ContainerInputData));

    const parent_bounds = data.container.get_element_bounds(e.lineage.?);

    var primary_offset: f32 = properties.primary_direction.margin;
    var secondary_offset: f32 = properties.secondary_direction.margin;

    const primary_towards = properties.primary_direction.towards;
    const primary_spacing = properties.primary_direction.spacing;

    const secondary_towards = properties.secondary_direction.towards;
    const secondary_spacing = properties.secondary_direction.spacing;

    var next_line_space: f32 = 0;

    for(e.children.items) |*ch|
    {
        const bounds = data.container.get_element_bounds(ch.lineage.?);

        const primary_limit = parent_bounds.scl_x - properties.primary_direction.margin;

        var primary_add = switch(properties.primary_direction.towards)
        {
            .LeftToRight => bounds.scl_x,
            .RightToLeft => -bounds.scl_x,
            .BottomToTop => bounds.scl_y,
            .TopToBottom => -bounds.scl_y,
        };

        primary_add += primary_spacing * (if(primary_towards.is_negative()) -1 else 1);

        var secondary_add = switch(properties.secondary_direction.towards)
        {
            .LeftToRight => bounds.scl_x,
            .RightToLeft => -bounds.scl_x,
            .BottomToTop => bounds.scl_y,
            .TopToBottom => -bounds.scl_y,
        }

        secondary_add += secondary_spacing * (if(secondary_towards.is_negative()) -1 else 1);

        if(@abs(secondary_spacing) > @abs(next_line_space))
        {
            next_line_space = secondary_spacing;
        }

        const next_primary_offset = primary_offset + primary_add;
        if(next_primary_offset > primary_limit)
        {
            primary_offset = properties.primary_direction.margin;
            secondary_offset += next_line_space;
        }
        else
        {
            primary_offset += primary_add;
        }

        const prev_placement = ch.placement;

        ch.placement = .{
            .relative_pos = .{
                .pos_x = 0,
                .pos_y = 0,
                .scl_x = prev_placement.relative_pos.scl_x,
                .scl_y = prev_placement.relative_pos.scl_y
            },
            .absolute_offset = .{
                .pos_x = primary_offset,
                .pos_y = secondary_offset,
                .scl_x = prev_placement.absolute_offset.scl_x,
                .scl_y = prev_placement.absolute_offset.scl_y
            },
            .alignment = .{
                .x = .Left,
                .y = .Bottom
            }
        };
    }
}

fn linear_layout_callback_add_or_remove_child(e: *Element, data: ContainerInputData) !void
{
    try linear_layout_update(e, data);
}

fn linear_layout_callback_other(e: *Element, data: ContainerInputData) !void
{
    try linear_layout_update(e, data);
    e.refresh(true);
}

pub fn set_layout_linear(e: *Element, properties: LinearLayoutProperties) !void
{
    if(e.layout_data != null)
    {
        e.allocator.free(e.layout_data.?);
    }

    var properties_alias = properties;

    e.layout_data = try e.allocator.alloc(u8, @sizeOf(LinearLayoutProperties));
    ash.misc.memcpy_anonymous(e.layout_data.?.ptr, &properties_alias, @sizeOf(LinearLayoutProperties));

    try e.add_callback(.AddChild, linear_layout_callback_add_or_remove_child);
    try e.add_callback(.RemoveChild, linear_layout_callback_add_or_remove_child);
    try e.add_callback(.WindowResize, linear_layout_callback_other);
}
