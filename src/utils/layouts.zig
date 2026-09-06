const std = @import("std");
const ash = @import("../root.zig");

const ui = @import("vkui.zig");

const Element = ui.Element;
const Container = ui.Container;
const ContainerInputData = ui.ContainerInputData;

pub const LayoutAxis = enum
{
    Horizontal,
    Vertical
};

pub const LinearLayoutDirection = struct
{
    spacing: f32,
    margin: f32
};

pub const LinearLayoutProperties = struct
{
    primary_direction: LinearLayoutDirection,
    secondary_direction: LinearLayoutDirection,
    primary_axis: LayoutAxis,
    alignment: ui.Alignment
};

pub const SplitLayoutProperties = struct
{
    primary_axis: LayoutAxis,
    primary_limit: usize = 0
};

fn linear_layout_update(e: *Element, data: ContainerInputData) !void
{
    if(e.lineage == null) return;

    var properties: LinearLayoutProperties = undefined;
    ash.utils.misc.memcpy_anonymous(&properties, e.layout_data.?.ptr, @sizeOf(LinearLayoutProperties));

    const container = data.container;
    const parent_bounds = (try container.get_element_bounds(e.lineage.?)).draw_bounds;

    var primary_offset: f32 = properties.primary_direction.margin;
    var secondary_offset: f32 = properties.secondary_direction.margin;

    const primary_spacing = properties.primary_direction.spacing;
    const secondary_spacing = properties.secondary_direction.spacing;

    const primary_axis = properties.primary_axis;

    var next_line_space: f32 = 0;

    var start_line: usize = 0;

    for(e.children.items, 0..) |ch, i|
    {
        const bounds = (try container.get_element_bounds(ch.lineage.?)).draw_bounds;

        const primary_limit = (if(primary_axis == .Horizontal) parent_bounds.scl_x else parent_bounds.scl_y) - properties.primary_direction.margin;

        var primary_add = if(primary_axis == .Horizontal) bounds.scl_x else bounds.scl_y;
        primary_add += primary_spacing;

        var secondary_add = if(primary_axis == .Horizontal) bounds.scl_y else bounds.scl_x;
        secondary_add += secondary_spacing;

        var next_primary_offset = primary_offset + primary_add;
        if(next_primary_offset > primary_limit and i > 0)
        {
            if(primary_axis == .Horizontal)
            {
                switch(properties.alignment.x)
                {
                    .Left => {},
                    .Center => {
                        for(start_line..i) |j|
                        {
                            e.children.items[j].placement.absolute_offset.pos_x += (parent_bounds.scl_x - primary_offset) / 2;
                        }
                    },
                    .Right => {
                        for(start_line..i) |j|
                        {
                            e.children.items[j].placement.absolute_offset.pos_x += (parent_bounds.scl_x - primary_offset);
                        }
                    }
                }
            }
            else
            {
                switch(properties.alignment.y)
                {
                    .Bottom => {},
                    .Center => {
                        for(start_line..i) |j|
                        {
                            e.children.items[j].placement.absolute_offset.pos_y += (parent_bounds.scl_y - primary_offset) / 2;
                        }
                    },
                    .Top => {
                        for(start_line..i) |j|
                        {
                            e.children.items[j].placement.absolute_offset.pos_y += (parent_bounds.scl_y - primary_offset);
                        }
                    }
                }
            }

            primary_offset = properties.primary_direction.margin;
            secondary_offset += next_line_space;

            next_primary_offset = primary_offset + primary_add;
            next_line_space = 0;

            start_line = i;
        }
        
        if(@abs(secondary_add) > @abs(next_line_space))
        {
            next_line_space = secondary_add;
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
                .pos_x = if(primary_axis == .Horizontal) primary_offset else secondary_offset,
                .pos_y = if(primary_axis == .Horizontal) secondary_offset else primary_offset,
                .scl_x = prev_placement.absolute_offset.scl_x,
                .scl_y = prev_placement.absolute_offset.scl_y
            },
            .alignment = .{
                .x = .Left,
                .y = .Bottom
            }
        };

        primary_offset += primary_add;
        
        if(i == e.children.items.len - 1)
        {
            if(primary_axis == .Horizontal)
            {
                switch(properties.alignment.x)
                {
                    .Left => {},
                    .Center => {
                        for(start_line..i + 1) |j|
                        {
                            e.children.items[j].placement.absolute_offset.pos_x += (parent_bounds.scl_x - primary_offset) / 2;
                        }
                    },
                    .Right => {
                        for(start_line..i + 1) |j|
                        {
                            e.children.items[j].placement.absolute_offset.pos_x += (parent_bounds.scl_x - primary_offset);
                        }
                    }
                }
            }
            else
            {
                switch(properties.alignment.y)
                {
                    .Bottom => {},
                    .Center => {
                        for(start_line..i + 1) |j|
                        {
                            e.children.items[j].placement.absolute_offset.pos_y += (parent_bounds.scl_y - primary_offset) / 2;
                        }
                    },
                    .Top => {
                        for(start_line..i + 1) |j|
                        {
                            e.children.items[j].placement.absolute_offset.pos_y += (parent_bounds.scl_y - primary_offset);
                        }
                    }
                }
            }

            secondary_offset += next_line_space;
        }
    }

    for(e.children.items) |ch|
    {
        if(primary_axis == .Horizontal)
        {
            switch(properties.alignment.y)
            {
                .Bottom => {},
                .Center => {
                    ch.placement.absolute_offset.pos_y += (parent_bounds.scl_y - secondary_offset) / 2;
                },
                .Top => {
                    ch.placement.absolute_offset.pos_y += (parent_bounds.scl_y - secondary_offset);
                }
            }
        }
        else
        {
            switch(properties.alignment.x)
            {
                .Left => {},
                .Center => {
                    ch.placement.absolute_offset.pos_x += (parent_bounds.scl_x - secondary_offset) / 2;
                },
                .Right => {
                    ch.placement.absolute_offset.pos_x += (parent_bounds.scl_x - secondary_offset);
                }
            }
        }
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
    ash.utils.misc.memcpy_anonymous(e.layout_data.?.ptr, &properties_alias, @sizeOf(LinearLayoutProperties));

    try e.add_callback(.AddChild, linear_layout_callback_add_or_remove_child);
    try e.add_callback(.RemoveChild, linear_layout_callback_add_or_remove_child);
    try e.add_callback(.WindowResize, linear_layout_callback_other);
}

fn split_layout_update(e: *Element, data: ContainerInputData) !void
{
    _ = data;

    var properties: SplitLayoutProperties = undefined;
    ash.utils.misc.memcpy_anonymous(&properties, e.layout_data.?.ptr, @sizeOf(SplitLayoutProperties));

    const limit = properties.primary_limit;
    const primary_axis = properties.primary_axis;

    for(e.children.items, 0..) |ch, i|
    {
        if(limit == 0)
        {
            const total = e.children.items.len;
            const size: f32 = 1 / @as(f32, @floatFromInt(total));
            const position = @as(f32, @floatFromInt(i)) * size;

            ch.placement = .{
                .relative_pos = .{
                    .pos_x = if(primary_axis == .Horizontal) position else 0,
                    .pos_y = if(primary_axis == .Horizontal) 0 else position,
                    .scl_x = if(primary_axis == .Horizontal) size else 1,
                    .scl_y = if(primary_axis == .Horizontal) 1 else size
                },
                .absolute_offset = .get_default(),
                .alignment = .{
                    .x = .Left,
                    .y = .Bottom
                }
            };
        }
        else
        {
            const total_lines: usize = @ceil(@as(f32, @floatFromInt(e.children.items.len)) / @as(f32, @floatFromInt(limit)));
            const line_size: f32 = 1 / @as(f32, @floatFromInt(total_lines));
            const line_position = @as(f32, @floatFromInt(i / limit)) * line_size;

            const line_begin = (i / limit) * limit;

            const line_entries: usize = @min(limit, e.children.items.len - line_begin);
            const entry_size: f32 = 1 / @as(f32, @floatFromInt(line_entries));
            const entry_position = @as(f32, @floatFromInt(i % limit)) * entry_size;

            ch.placement = .{
                .relative_pos = .{
                    .pos_x = if(primary_axis == .Horizontal) entry_position else line_position,
                    .pos_y = if(primary_axis == .Horizontal) line_position else entry_position,
                    .scl_x = if(primary_axis == .Horizontal) entry_size else line_size,
                    .scl_y = if(primary_axis == .Horizontal) line_size else entry_size
                },
                .absolute_offset = .get_default(),
                .alignment = .{
                    .x = .Left,
                    .y = .Bottom
                }
            };
        }
    }

    e.refresh(true);
}

pub fn set_layout_split(e: *Element, properties: SplitLayoutProperties) !void
{
    if(e.layout_data != null)
    {
        e.allocator.free(e.layout_data.?);
    }

    var properties_alias = properties;

    e.layout_data = try e.allocator.alloc(u8, @sizeOf(SplitLayoutProperties));
    ash.utils.misc.memcpy_anonymous(e.layout_data.?.ptr, &properties_alias, @sizeOf(SplitLayoutProperties));

    try e.add_callback(.AddChild, split_layout_update);
    try e.add_callback(.RemoveChild, split_layout_update);
}
