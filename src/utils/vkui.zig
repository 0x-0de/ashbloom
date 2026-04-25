const std = @import("std");

const glfw = @import("glfw");
const vk = @import("vulkan");

const vk_memory = @import("vkmemory.zig");
const images = @import("image_utils.zig");
const pipelines = @import("../rendering/pipeline.zig");

const VkContext = @import("../rendering/vkcontext.zig").VkContext;
const VulkanAllocator = vk_memory.VulkanAllocator;

const CommandBuffer = @import("../rendering/commands.zig").CommandBuffer;
const Swapchain = @import("../rendering/swapchain.zig").Swapchain;
const RenderPass = @import("../rendering/renderpass.zig").RenderPass;
const Pipeline = pipelines.Pipeline;
const PipelineDescriptorSet = pipelines.PipelineDescriptorSet;
const PipelineVertexInput = pipelines.PipelineVertexInput;

const Font = @import("font.zig").Font;

/// FreeType import.
pub const freetype = @import("freetype");

/// FreeType library instance. init() must be called before this is accessed.
pub var ft: freetype.FT_Library = undefined;

/// Used to represent the position and scale of a UI object.
pub const Bounds = struct
{
    pos_x: f32,
    pos_y: f32,

    scl_x: f32,
    scl_y: f32,

    pub fn get_default() Bounds
    {
        return .{
            .pos_x = 0,
            .pos_y = 0,

            .scl_x = 0,
            .scl_y = 0
        };
    }
};

pub const AlignX = enum
{
    Left,
    Center,
    Right
};

pub const AlignY = enum
{
    Bottom,
    Center,
    Top
};

pub const Alignment = struct
{
    x: AlignX,
    y: AlignY
};

/// Represents the placement of a UI object. An object's "placement" is used to determine its final draw bounds at runtime.
pub const Placement = struct
{
    /// Position of the object relative to the draw bounds of its parent. A value of 0.5 for example corresponds to either the center of the object
    /// or half of it's scale on an axis, depending on context.
    relative_pos: Bounds,
    /// An additional pixel value can be added onto each element of relative_pos to determine a final value.
    absolute_offset: Bounds,
    /// Alignment value. This determines where the "origin point" of the element is, in other words, which part of the element should be placed
    /// at the location specified by the previous two fields.
    alignment: Alignment,

    /// Returns a 'default' value for placement - zeroing every value of every Bounds in the structure.
    pub fn get_default() Placement
    {
        return .{
            .relative_pos = .{
                .pos_x = 0,
                .pos_y = 0,
                .scl_x = 0,
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
    }
};

/// Enumeral value representing the draw mode of an element.
pub const ElementDrawMode = enum
{
    /// Don't draw this element at all. This element will not be included in the final instance array, but its children may be.
    None,
    /// Fill the draw boundaries of the element with a single color.
    Color,
    /// Fill the draw boundaries of the element with a texture.
    Texture,
    /// Draws a monochrome texture, meant for rendering text characters.
    Character,
    /// Fill the draw bounaries of the element with a texture, multiplied by a single color.
    ColoredTexture
};

pub const ElementCallbackType = enum
{
    Tick,
    MouseEnter,
    MouseLeave,
    MouseHover,
    MousePress,
    MouseRelease,
    MouseHold,
    WindowResize,
    Scroll,
    Deinit,
    Rebuild,
    Copy
};

/// Element callback. When the callback is called is determined by the callback type.
pub const ElementCallback = struct
{
    /// Type of the callback.
    type: ElementCallbackType,
    /// Callback function.
    callback: *const fn(*Element, ContainerInputData) anyerror!void
};

/// Container input data, used in event callbacks.
pub const ContainerInputData = struct
{
    container: *Container = undefined,
    cursor_pos: vk.Offset2D,
    scroll: vk.Offset2D,
    mouse_buttons: u8,
    text: ?[]u32,
    keys: ?[]u32,
    resized: bool = undefined
};

pub const VulkanUIError = error
{
    CantInitializeFreeType,
    NonRefreshableElement,
    MissingLineage,
};

/// The main unit of the UI system. An Element is a quad that is instanced onto the screen, and can represent a colored box, a textured quad, a
/// font character, a button, etc. Elements contain a list of "children" whose final placement on the screen is derived from the placement of its
/// parent element.
pub const Element = struct
{
    /// Allocator handle.
    allocator: *const std.mem.Allocator,
    /// This element's draw mode.
    draw_mode: ElementDrawMode,
    /// The placement of the element. This, alongside the final calculated draw boundaries of this element's parent object, will determine the final
    /// draw boundaries of this element.
    placement: Placement,
    /// Determines, in pixel units, the total amount of "space" this element uses. If it extends beyond the space allocated by its placement, then
    /// the element becomes scrollable. pos_x and pos_y determine the offset of the scissor. If scl_y is -1, then the draw boundaries are assumed to
    /// be the same as the cut (or scroll) boundaries, meaning the element doesn't scroll at all.
    space: Bounds,
    /// If enabled, this element's position will be relative to the cut_bounds, instead of the draw_bounds. In other words, this element is "frozen"
    /// relative to its parent while other elements with this flag disabled will scroll normally. Doesn't affect elements whose parents don't scroll.
    freeze: bool,
    /// 'Coordinates' of the element - color values, texture coordinates, etc.
    coordinates: [4]f32,

    /// This element's parent.
    parent: ?*Element,
    /// Dynamic array of this element's children.
    children: std.ArrayList(*Element),
    /// List of offsets that can lead the container to this element's offset in memory and its children array.
    lineage: ?[]usize,
    /// Dynamic array of this element's callbacks.
    callbacks: std.ArrayList(ElementCallback),
    /// Dynamic array of callback types to force in the next tick.
    force_callbacks: std.ArrayList(ElementCallbackType),
    /// Other data that may be used for this element's extra logic or callbacks.
    data: ?[]u8,
    /// Offset of the element's data in the instance array.
    instance_data_offset: ?vk.DeviceSize,
    /// Flag to be enabled if the refresh() function is called. Used by the element's origin Container object.
    should_refresh: bool,

    /// Set automatically. Used for the callback manager.
    mouse_enter_toggle: bool,
    /// Set automatically. Used for the callback manager.
    mouse_button_toggles: u8,

    pub const RuntimeBounds = struct
    {
        draw_bounds: Bounds,
        cut_bounds: Bounds
    };

    /// Using this element's placement and this element's parent's draw boundaries, determines this element's draw boundaries.
    fn get_runtime_bounds_from_parent(self: *Element, parent_bounds: RuntimeBounds) RuntimeBounds
    {
        const parent_draw_bounds = if(self.freeze) parent_bounds.cut_bounds else parent_bounds.draw_bounds;
        const parent_cut_bounds = parent_bounds.cut_bounds;

        const uses_space = self.space.scl_y != -1;

        const cut_scl_x = self.placement.relative_pos.scl_x * parent_draw_bounds.scl_x + self.placement.absolute_offset.scl_x;
        const cut_scl_y = self.placement.relative_pos.scl_y * parent_draw_bounds.scl_y + self.placement.absolute_offset.scl_y;

        var draw_scl_x = if(uses_space) self.space.scl_x else cut_scl_x;
        var draw_scl_y = if(uses_space) self.space.scl_y else cut_scl_y;

        if(draw_scl_x < cut_scl_x) draw_scl_x = cut_scl_x;
        if(draw_scl_y < cut_scl_y) draw_scl_y = cut_scl_y;

        var cut_pos_x = self.placement.relative_pos.pos_x * parent_draw_bounds.scl_x + parent_draw_bounds.pos_x + self.placement.absolute_offset.pos_x;
        var cut_pos_y = self.placement.relative_pos.pos_y * parent_draw_bounds.scl_y + parent_draw_bounds.pos_y + self.placement.absolute_offset.pos_y;

        switch(self.placement.alignment.x)
        {
            .Left => {},
            .Center => cut_pos_x -= cut_scl_x / 2,
            .Right => cut_pos_x -= cut_scl_x
        }

        switch(self.placement.alignment.y)
        {
            .Bottom => {},
            .Center => cut_pos_y -= cut_scl_y / 2,
            .Top => cut_pos_y -= cut_scl_y
        }

        var draw_pos_x = cut_pos_x;
        var draw_pos_y = cut_pos_y;

        if(uses_space)
        {
            draw_pos_x -= self.space.pos_x;
            draw_pos_y -= self.space.pos_y;
        }

        const draw_bounds: Bounds = .{
            .pos_x = draw_pos_x,
            .pos_y = draw_pos_y,
            .scl_x = draw_scl_x,
            .scl_y = draw_scl_y
        };

        var cut_bounds: Bounds = undefined;

        if(self.space.scl_y == -1)
        {
            cut_bounds = parent_cut_bounds;
        }
        else
        {
            cut_bounds = .{
                .pos_x = cut_pos_x,
                .pos_y = cut_pos_y,
                .scl_x = cut_scl_x,
                .scl_y = cut_scl_y
            };
        }

        return .{
            .draw_bounds = draw_bounds,
            .cut_bounds = cut_bounds
        };
    }

    /// Adds a copy of 'element' to this element's children array, making the copy one of its children.
    pub fn add(self: *Element, element: *Element) !void
    {
        var e = try self.allocator.create(Element);
        e.* = try .init(self.allocator, element.draw_mode, element.placement, element.coordinates);

        e.parent = self;
        e.space = element.space;
        e.freeze = element.freeze;

        if(self.lineage != null)
        {
            e.lineage = try e.allocator.alloc(usize, self.lineage.?.len + 1);

            for(0..self.lineage.?.len) |i|
            {
                e.lineage.?[i] = self.lineage.?[i];
            }
            
            e.lineage.?[self.lineage.?.len] = self.children.items.len;
        }
        else
        {
            e.lineage = try e.allocator.alloc(usize, 1);
            e.lineage.?[0] = self.children.items.len;
        }

        for(element.callbacks.items) |cb|
        {
            try e.callbacks.append(e.allocator.*, cb);
        }

        if(element.data != null)
        {
            e.data = try e.allocator.alloc(u8, element.data.?.len);
            @memcpy(e.data.?, element.data.?);
        }
        else
        {
            e.data = null;
        }

        try self.children.append(self.allocator.*, e);

        var child_num: u32 = 0;

        for(element.callbacks.items) |cb|
        {
            if(cb.type == .Copy)
            {
                try cb.callback(e, undefined);
            }
        }

        for(element.children.items) |child|
        {
            try e.add(child);
            child_num += 1;
        }
    }

    /// After trying self.add(element), deinitializes the element and destroys it.
    pub fn add_and_dispose(self: *Element, element: *Element) !void
    {
        try self.add(element);
        try element.deinit();
        self.allocator.destroy(element);
    }

    /// Adds a callback to this element.
    pub fn add_callback(self: *Element, callback_type: ElementCallbackType, callback_func: *const fn(*Element, ContainerInputData) anyerror!void) !void
    {
        try self.callbacks.append(self.allocator.*, .{
            .type = callback_type,
            .callback = callback_func
        });
    }

    pub fn build_lineage(self: *Element, list: *std.ArrayList(usize)) !void
    {
        if(self.lineage != null)
        {
            self.allocator.free(self.lineage.?);
        }

        if(list.items.len != 0)
        {
            self.lineage = try self.allocator.alloc(usize, list.items.len);
            @memcpy(self.lineage.?, list.items);
        }

        for(0..self.children.items.len) |i|
        {
            try list.append(self.allocator.*, i);
            try self.children.items[i].build_lineage(list);
            _ = list.orderedRemove(list.items.len - 1);
        }
    }

    /// Deinitializes, destroys, and frees all memory from an element and its children.
    pub fn deinit(self: *Element) anyerror!void
    {
        while(self.children.items.len > 0)
        {
            try self.remove_by_index(0);
        }

        for(self.callbacks.items) |cb|
        {
            if(cb.type == .Deinit)
            {
                try cb.callback(self, undefined);
            }
        }

        self.children.deinit(self.allocator.*);
        self.callbacks.deinit(self.allocator.*);
        self.force_callbacks.deinit(self.allocator.*);
        if(self.lineage != null) self.allocator.free(self.lineage.?);
        if(self.data != null) self.allocator.free(self.data.?);
    }

    /// Adds a callback type to the force callback queue.
    pub fn force_callback(self: *Element, callback_type: ElementCallbackType) !void
    {
        try self.force_callbacks.append(self.allocator.*, callback_type);
    }

    /// Returns the total number of children that need to be drawn from this element, including the element's children's children and so on.
    pub fn get_element_draw_count(self: *Element) usize
    {
        var count = self.children.items.len;
        for(self.children.items) |child|
        {
            // Elements with no draw mode can be skipped in the instance array.
            if(child.draw_mode == .None) count -= 1;
            count += child.get_element_draw_count();
        }
        return count;
    }

    pub fn get_element_instance_data(self: *Element, origin: *Element, origin_bounds: Bounds) ?[13]f32
    {
        if(self.draw_mode == .None or self.lineage == null)
        {
            return null;
        }

        var element = origin;

        var erb: RuntimeBounds = .{
            .draw_bounds = origin_bounds,
            .cut_bounds = origin_bounds
        };

        for(self.lineage.?) |i|
        {
            element = element.children.items[i];
            erb = element.get_runtime_bounds_from_parent(erb);
        }

        std.debug.assert(element == self);

        const data: [13]f32 = .{
            @floatFromInt(@intFromEnum(self.draw_mode)),
            erb.draw_bounds.pos_x, erb.draw_bounds.pos_y, erb.draw_bounds.scl_x, erb.draw_bounds.scl_y,
            erb.cut_bounds.pos_x, erb.cut_bounds.pos_y, erb.cut_bounds.scl_x, erb.cut_bounds.scl_y,
            self.coordinates[0], self.coordinates[1], self.coordinates[2], self.coordinates[3]
        };

        return data;
    }

    /// Initializes an element.
    pub fn init(allocator: *const std.mem.Allocator, draw_mode: ElementDrawMode, placement: Placement, coordinates: [4]f32) !Element
    {
        return .{
            .allocator = allocator,
            .placement = placement,
            .space = .{
                .pos_x = 0,
                .pos_y = 0,
                .scl_x = 0,
                .scl_y = -1
            },
            .freeze = false,
            .draw_mode = draw_mode,
            .coordinates = coordinates,
            .parent = null,
            .children = try std.ArrayList(*Element).initCapacity(allocator.*, 0),
            .lineage = null,
            .callbacks = try std.ArrayList(ElementCallback).initCapacity(allocator.*, 0),
            .force_callbacks = try std.ArrayList(ElementCallbackType).initCapacity(allocator.*, 0),
            .data = null,
            .instance_data_offset = null,
            .should_refresh = false,
            .mouse_enter_toggle = false,
            .mouse_button_toggles = 0
        };
    }

    /// Gets the instance data for this element, alongside it's children, and fills a std.ArrayList with it.
    pub fn place_instance_data(self: *Element, data_list: *std.ArrayList(f32), parent_bounds: RuntimeBounds) !void
    {
        const erb = self.get_runtime_bounds_from_parent(parent_bounds);

        if(self.draw_mode != .None)
        {
            const data: [13]f32 = .{
                @floatFromInt(@intFromEnum(self.draw_mode)),
                erb.draw_bounds.pos_x, erb.draw_bounds.pos_y, erb.draw_bounds.scl_x, erb.draw_bounds.scl_y,
                erb.cut_bounds.pos_x, erb.cut_bounds.pos_y, erb.cut_bounds.scl_x, erb.cut_bounds.scl_y,
                self.coordinates[0], self.coordinates[1], self.coordinates[2], self.coordinates[3]
            };

            self.instance_data_offset = data_list.items.len;
            try data_list.appendSlice(self.allocator.*, data[0..13]);
        }
        else
        {
            self.instance_data_offset = null;
        }

        for(self.children.items) |child|
        {
            try child.place_instance_data(data_list, erb);
        }
    }

    /// Sets the 'should_refresh' flag to true for this element, and all of it's children if "include_children" is enabled.
    /// Element refreshing is handled automatically by the Container object.
    pub fn refresh(self: *Element, include_children: bool) void
    {
        self.should_refresh = true;
        if(include_children)
        {
            for(self.children.items) |child|
            {
                child.refresh(true);
            }
        }
    }

    /// Removes one of the elements from the children array and frees it, including all of *its* children.
    pub fn remove_by_index(self: *Element, index: usize) !void
    {
        const e = self.children.orderedRemove(index);
        try e.deinit();
        self.allocator.destroy(e);
    }

    /// Updates this element's callbacks, as well as the callbacks for all of its children.
    pub fn update(self: *Element, erb: RuntimeBounds, input_data: ContainerInputData) !void
    {
        const cursor_x: f32 = @floatFromInt(input_data.cursor_pos.x);
        const cursor_y: f32 = @floatFromInt(input_data.cursor_pos.y);

        const cursor_over_element: bool = cursor_x >= erb.draw_bounds.pos_x and cursor_x < erb.draw_bounds.pos_x + erb.draw_bounds.scl_x
                                      and cursor_y >= erb.draw_bounds.pos_y and cursor_y < erb.draw_bounds.pos_y + erb.draw_bounds.scl_y
                                      and cursor_x >= erb.cut_bounds.pos_x and cursor_x < erb.cut_bounds.pos_x + erb.cut_bounds.scl_x
                                      and cursor_y >= erb.cut_bounds.pos_y and cursor_y < erb.cut_bounds.pos_y + erb.cut_bounds.scl_y;


        for(self.callbacks.items) |callback|
        {
            var force: bool = false;
            for(self.force_callbacks.items) |t|
            {
                if(callback.type == t)
                {
                    force = true;
                    break;
                }
            }

            if(force)
            {
                try callback.callback(self, input_data);
            }
            else
            {
                switch(callback.type)
                {
                    .Tick => {
                        try callback.callback(self, input_data);
                    },
                    .MouseEnter => {
                        if(!self.mouse_enter_toggle and cursor_over_element)
                        {
                            self.mouse_enter_toggle = true;
                            try callback.callback(self, input_data);
                        }
                    },
                    .MouseLeave => {
                        if(self.mouse_enter_toggle and !cursor_over_element)
                        {
                            self.mouse_enter_toggle = false;
                            try callback.callback(self, input_data);
                        }
                    },
                    .MouseHover => {
                        if(cursor_over_element)
                        {
                            try callback.callback(self, input_data);
                        }
                    },
                    .MousePress => {
                        if(cursor_over_element)
                        {
                            for(0..8) |i|
                            {
                                const button: u8 = @as(u8, 1) << @truncate(i);
                                if(input_data.mouse_buttons & button != 0 and self.mouse_button_toggles & button == 0)
                                {
                                    try callback.callback(self, input_data);
                                }
                            }
                        }
                    },
                    .MouseRelease => {
                        if(cursor_over_element)
                        {
                            for(0..8) |i|
                            {
                                const button: u8 = @as(u8, 1) << @truncate(i);
                                if(input_data.mouse_buttons & button == 0 and self.mouse_button_toggles & button != 0)
                                {
                                    try callback.callback(self, input_data);
                                }
                            }
                        }
                    },
                    .MouseHold => {
                        if(cursor_over_element)
                        {
                            if(input_data.mouse_buttons != 0)
                            {
                                try callback.callback(self, input_data);
                            }
                        }
                    },
                    .WindowResize => {
                        if(input_data.resized)
                        {
                            try callback.callback(self, input_data);
                        }
                    },
                    .Scroll => {
                        // It is often advantagous to perform scroll callbacks when the parent is resized.
                        if(input_data.resized or (cursor_over_element and (input_data.scroll.x != 0 or input_data.scroll.y != 0)))
                        {
                            try callback.callback(self, input_data);
                        }
                    },
                    .Deinit, .Rebuild, .Copy => {},
                }
            }
        }

        // Mouse button toggles need to be flipped after the main loop is complete, to ensure that all mouse button callbacks get called first.
        for(0..8) |i|
        {
            const button: u8 = @as(u8, 1) << @truncate(i);

            // Mouse button is being pressed. Occurs whether or not the cursor is over the element.
            if(input_data.mouse_buttons & button != 0 and self.mouse_button_toggles & button == 0)
            {
                self.mouse_button_toggles |= button;
            }

            // Mouse button isn't being pressed. Same deal as above.
            if(input_data.mouse_buttons & button == 0 and self.mouse_button_toggles & button != 0)
            {
                self.mouse_button_toggles &= ~button;
            }
        }

        self.force_callbacks.clearRetainingCapacity();

        for(self.children.items) |child|
        {
            const child_bounds = child.get_runtime_bounds_from_parent(erb);
            try child.update(child_bounds, input_data);
        }
    }
};

pub const ContainerRendering = struct
{
    pipeline: *Pipeline,
    descriptor_set: *PipelineDescriptorSet,
    render_pass: *RenderPass,
    render_queue: vk.Queue,
    uniform_callback: *const fn(Container, u16) anyerror!void,

    pub fn deinit(self: *ContainerRendering, vk_context: VkContext) !void
    {
        self.pipeline.deinit();
        vk_context.allocator.destroy(self.pipeline);

        try self.descriptor_set.deinit();
        vk_context.allocator.destroy(self.descriptor_set);

        self.render_pass.deinit();
        vk_context.allocator.destroy(self.render_pass);
    }
};

/// The Container acts as an origin point for the UI system, containing an automatically updated "master" element which all other elements can
/// be added to.
pub const Container = struct
{
    /// Vulkan context.
    context: *VkContext,
    /// Vulkan allocator.
    vk_allocator: *VulkanAllocator,

    /// The master/origin element of this container. This is used as the container's "entry point" to draw all subelements that the developer
    /// will add.
    origin: Element,
    /// Boundaries of the origin element, and by extension this container.
    bounds: Bounds,

    /// The final instance buffer, built with the build() function.
    instance_buffer: ?VulkanAllocator.VulkanBufferAllocation = null,
    /// Number of elements that need to be drawn with this container.
    element_draw_count: usize = undefined,
    /// Struct containing the Vulkan resources used to render the UI system.
    ui_rendering: ContainerRendering,

    /// Texture atlas to be used by all drawn icons or texture elements other than those that render text.
    texture_atlas: images.TextureAtlas2D,

    /// Number of ticks to occur per second.
    tick_rate: u16,
    /// Keeps track of how many ticks need to occur in the next frame.
    tick_timer: f64,
    /// Timestamp of last frame.
    prev_time: f64,

    /// Flag enabled when set_bounds() is called. Used to call WindowResize events.
    resized: bool = false,
    /// Flag signalled when the manual window input values need to be reset.
    signal_reset_manual_input: bool = false,
    /// Flag signalled when a rebuild is requested.
    signal_rebuild: bool = false,
    /// Flag signalled to ignore callbacks for the next tick (useful for rebuilding).
    signal_ignore_callbacks: bool = false,

    /// Returns a list of all of the element data from the origin element and its children.
    fn get_all_element_data(self: *Container) !std.ArrayList(f32)
    {
        const total_elements = self.origin.get_element_draw_count() + 1;
        self.element_draw_count = total_elements;

        var data_list = try std.ArrayList(f32).initCapacity(self.context.allocator.*, total_elements * 13);

        const erb: Element.RuntimeBounds = .{
            .draw_bounds = self.bounds,
            .cut_bounds = self.bounds
        };

        try self.origin.place_instance_data(&data_list, erb);

        return data_list;
    }

    /// Returns a list of all of the elements contained within this element which need to be refreshed.
    fn get_elements_refresh_list(self: *Container, element: *Element, list: *std.ArrayList(*Element)) !void
    {
        if(element.should_refresh)
        {
            if(element.draw_mode != .None)
            {
                try list.append(self.context.allocator.*, element);
            }
            element.should_refresh = false;
        }

        for(element.children.items) |child|
        {
            try self.get_elements_refresh_list(child, list);
        }
    }
    
    fn perform_rebuild_callbacks(self: *Container, e: *Element) !void
    {
        for(e.callbacks.items) |cb|
        {
            if(cb.type == .Rebuild)
            {
                const data: ContainerInputData = .{
                    .container = self,
                    .cursor_pos = undefined,
                    .mouse_buttons = undefined,
                    .resized = undefined,
                    .scroll = undefined,
                    .text = null,
                    .keys = null
                };

                try cb.callback(e, data);
            }
        }

        for(e.children.items) |child|
        {
            try self.perform_rebuild_callbacks(child);
        }
    }

    /// Adds an element to the origin element of this container.
    pub fn add(self: *Container, element: *Element) !void
    {
        try self.origin.add(element);
    }

    /// Adds an element to the origin element of this container, then deletes the original element.
    pub fn add_and_dispose(self: *Container, element: *Element) !void
    {
        try self.add(element);
        try element.deinit();
        self.context.allocator.destroy(element);
    }

    /// Adds a texture to the texture atlas.
    pub fn add_texture(self: *Container, texture: *images.Texture2D) !images.TextureAtlas2D.TextureSuballocation
    {
        return self.texture_atlas.add_texture(texture);
    }

    /// Builds (or rebuilds) the instance buffer used for drawing. Recommend using only when elements have been added or removed from
    /// the origin element or any of its children. Otherwise, use refresh_all().
    pub fn build(self: *Container) !void
    {
        if(self.instance_buffer != null)
        {
            try self.context.device.queueWaitIdle(self.ui_rendering.render_queue);

            try self.perform_rebuild_callbacks(&self.origin);
            try self.vk_allocator.free_buffer(self.instance_buffer.?);
        }

        var lineage_list: std.ArrayList(usize) = try .initCapacity(self.context.allocator.*, 0);
        try self.origin.build_lineage(&lineage_list);
        lineage_list.deinit(self.context.allocator.*);

        var data_list = try self.get_all_element_data();
        defer data_list.deinit(self.context.allocator.*);

        self.instance_buffer = try self.vk_allocator.alloc_buffer(f32, data_list.items, .exclusive, .VertexBuffer);
    }

    /// Deinitializes the container, destroying all elements it holds and freeing all memory it uses.
    pub fn deinit(self: *Container) !void
    {
        try self.origin.deinit();
        try self.texture_atlas.deinit();
        if(self.instance_buffer != null) try self.vk_allocator.free_buffer(self.instance_buffer.?);
    }

    /// Draws the instance arrays using the command buffer onto the framebuffer.
    pub fn draw(self: *Container, command_buffer: *CommandBuffer, swapchain: *Swapchain, framebuffer: vk.Framebuffer) !void
    {
        try self.ui_rendering.uniform_callback(self.*, @truncate(swapchain.current_image_index));

        try command_buffer.reset();

        try command_buffer.begin_recording();
        command_buffer.cmd_begin_render_pass(self.ui_rendering.render_pass, framebuffer, swapchain.extent, .{0, 0, 0, 1});
        command_buffer.cmd_bind_pipeline(self.ui_rendering.pipeline);
        command_buffer.cmd_bind_descriptor_set(self.ui_rendering.pipeline, 
        &self.ui_rendering.descriptor_set.sets[swapchain.current_image_index]);
        command_buffer.cmd_set_viewport_full(swapchain.extent);
        command_buffer.cmd_set_scissor(.{
            .offset = .{
                .x = @intFromFloat(self.bounds.pos_x),
                .y = @intFromFloat(self.bounds.pos_y)
            },
            .extent = .{
                .width = @intFromFloat(self.bounds.scl_x),
                .height = @intFromFloat(self.bounds.scl_y)
            }
        });
        command_buffer.cmd_bind_vertex_buffer(self.instance_buffer.?.buffer, @as(vk.DeviceSize, 0));
        command_buffer.cmd_draw(6, @truncate(self.element_draw_count));
        command_buffer.cmd_end_render_pass();
        try command_buffer.end_recording();

        try swapchain.render(self.ui_rendering.render_queue);
    }

    pub fn get_element(self: *Container, lineage: []usize) VulkanUIError!*Element
    {
        var cur_element = &self.origin;
        if(lineage.len == 0) return cur_element;

        var cur_index: usize = 0;
        
        while(cur_index < lineage.len) : (cur_index += 1)
        {
            const cur_lineage = lineage[cur_index];
            if(cur_lineage < cur_element.children.items.len)
            {
                cur_element = cur_element.children.items[cur_lineage];
            }
            else
            {
                return VulkanUIError.MissingLineage;
            }
        }

        return cur_element;
    }

    pub fn get_element_bounds(self: *Container, lineage: []usize) VulkanUIError!Element.RuntimeBounds
    {
        var cur_bounds: Element.RuntimeBounds = .{
            .draw_bounds = self.bounds,
            .cut_bounds = self.bounds
        };

        if(lineage.len == 0) return cur_bounds;

        var cur_index: usize = 0;
        var cur_element = &self.origin;
        
        while(cur_index < lineage.len) : (cur_index += 1)
        {
            const cur_lineage = lineage[cur_index];
            if(cur_lineage < cur_element.children.items.len)
            {
                cur_element = cur_element.children.items[cur_lineage];
                cur_bounds = cur_element.get_runtime_bounds_from_parent(cur_bounds);
            }
            else
            {
                return VulkanUIError.MissingLineage;
            }
        }

        return cur_bounds;
    }

    /// Creates a new Container object.
    pub fn init(context: *VkContext, vulkan_allocator: *VulkanAllocator) !Container
    {
        const container: Container = .{
            .context = context,
            .vk_allocator = vulkan_allocator,

            .origin = try Element.init(context.allocator, .None, .{
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
            }, .{0, 0, 0, 0}),

            .bounds = .get_default(),
            .ui_rendering = undefined,
            .texture_atlas = try images.TextureAtlas2D.init(context, vulkan_allocator, 1024, 1024),
            .tick_rate = 60,
            .tick_timer = 0,
            .prev_time = glfw.getTime()
        };

        return container;
    }

    /// Refreshes the entire element list. Called automatically when set_bounds is performed.
    pub fn refresh_all(self: *Container) !void
    {
        var data_list = try self.get_all_element_data();
        defer data_list.deinit(self.context.allocator.*);

        try self.vk_allocator.overwrite_buffer(self.instance_buffer.?, f32, data_list.items, 0);
    }

    /// Sets the 'bounds' object, but also refreshes the instance array after doing so (if the instance array has been built first, otherwise it doesn't).
    pub fn set_bounds(self: *Container, pos_x: f32, pos_y: f32, scl_x: f32, scl_y: f32) !void
    {
        self.bounds.pos_x = pos_x;
        self.bounds.pos_y = pos_y;

        self.bounds.scl_x = scl_x;
        self.bounds.scl_y = scl_y;

        if(self.instance_buffer != null) try self.refresh_all();
        self.resized = true;
    }

    pub fn set_render_instance(self: *Container, resources: ContainerRendering) void
    {
        self.ui_rendering = resources;
    }

    /// Updates all callbacks for the origin element and all of its children. Also handles refreshing any elements if necessary.
    pub fn update(self: *Container, input_data: ContainerInputData) !void
    {
        const tick_interval: f64 = 1.0 / @as(f64, @floatFromInt(self.tick_rate));

        const cur_time = glfw.getTime();
        const elapsed = cur_time - self.prev_time;

        self.tick_timer += elapsed;
        
        var ticks: usize = 0;
        while(self.tick_timer >= tick_interval)
        {
            ticks += 1;
            self.tick_timer -= tick_interval;
        }

        const erb: Element.RuntimeBounds = .{
            .draw_bounds = self.bounds,
            .cut_bounds = self.bounds
        };

        var first_tick: bool = true;

        for(0..ticks) |_|
        {
            self.prev_time = cur_time;

            var final_input_data = input_data;
            final_input_data.container = self;
            final_input_data.resized = self.resized;

            if(final_input_data.scroll.x != 0 or final_input_data.scroll.y != 0 or final_input_data.text != null or final_input_data.keys != null)
            {
                if(!first_tick)
                {
                    final_input_data.scroll.x = 0;
                    final_input_data.scroll.y = 0;

                    final_input_data.text = null;
                }
                else
                {
                    self.signal_reset_manual_input = true;
                }
            }

            if(self.signal_rebuild)
            {
                try self.build();
                self.signal_rebuild = false;
            }

            try self.origin.update(erb, final_input_data);

            if(!self.signal_ignore_callbacks)
            {
                // Get a list of every element which needs to be refreshed.

                var element_refresh_list = try std.ArrayList(*Element).initCapacity(self.context.allocator.*, 0);
                defer element_refresh_list.deinit(self.context.allocator.*);

                try self.get_elements_refresh_list(&self.origin, &element_refresh_list);

                // Now get the ranges of all these elements in the instance data array.

                var condensed_list = try std.ArrayList(u64).initCapacity(self.context.allocator.*, 0);
                defer condensed_list.deinit(self.context.allocator.*);

                var previous_offset: u64 = 0;
                var current_length: u64 = 0;

                for(element_refresh_list.items, 0..) |e, i|
                {
                    const offset = e.instance_data_offset.?;

                    if(condensed_list.items.len == 0 or offset > previous_offset + 13)
                    {
                        if(condensed_list.items.len != 0)
                        {
                            try condensed_list.append(self.context.allocator.*, current_length);
                        }

                        try condensed_list.append(self.context.allocator.*, @truncate(i));
                        current_length = 0;
                    }

                    current_length += 13;
                    previous_offset = offset;
                }

                try condensed_list.append(self.context.allocator.*, current_length);

                // Now run through the list, and refresh each batch of elements.

                for(0..condensed_list.items.len / 2) |i|
                {
                    const element_index = condensed_list.items[i * 2];
                    const start_element = element_refresh_list.items[element_index];

                    std.debug.assert(start_element.draw_mode != .None);

                    var data = try self.context.allocator.alloc(f32, condensed_list.items[i * 2 + 1]);
                    defer self.context.allocator.free(data);

                    const num_elements = condensed_list.items[i * 2 + 1] / 13;

                    for(0..num_elements) |j|
                    {
                        const e = element_refresh_list.items[element_index + j];
                        const element_data = e.get_element_instance_data(&self.origin, self.bounds).?;

                        const data_offset = j * 13;

                        for(0..13) |k|
                        {
                            data[data_offset + k] = element_data[k];
                        }
                    }

                    try self.vk_allocator.overwrite_buffer(self.instance_buffer.?, f32, data, start_element.instance_data_offset.?);
                }
            }

            self.resized = false;
            first_tick = false;

            self.signal_ignore_callbacks = false;
        }
    }
};

pub fn default_scroll_callback(e: *Element, input_data: ContainerInputData) !void
{
    if(e.space.scl_y != -1)
    {
        const bounds = try input_data.container.get_element_bounds(e.lineage.?);

        const scroll_max_x = bounds.draw_bounds.scl_x - bounds.cut_bounds.scl_x;
        const scroll_max_y = bounds.draw_bounds.scl_y - bounds.cut_bounds.scl_y;

        e.space.pos_x += @floatFromInt(input_data.scroll.x * 30);
        e.space.pos_y += @floatFromInt(input_data.scroll.y * 30);

        if(e.space.pos_x < 0) e.space.pos_x = 0;
        if(e.space.pos_y < 0) e.space.pos_y = 0;

        if(e.space.pos_x > scroll_max_x) e.space.pos_x = scroll_max_x;
        if(e.space.pos_y > scroll_max_y) e.space.pos_y = scroll_max_y;

        e.refresh(true);
    }
}

pub fn deinit() void
{
    _ = freetype.FT_Done_FreeType(ft);
}

pub fn init() VulkanUIError!void
{
    const err = freetype.FT_Init_FreeType(&ft);
    if(err != 0)
    {
        std.debug.print("Error initializing FreeType library.\nError code: {d}.\n", .{err});
        return VulkanUIError.CantInitializeFreeType;
    }
}
