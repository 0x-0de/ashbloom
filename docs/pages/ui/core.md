# `core`

## Bounds (`struct`)

Used to represent the position and scale of a UI object.

### Fields

`pos_x: f32 = 0` - X-offset.

`pos_y: f32 = 0` - Y-offset.

`scl_x: f32 = 0` - Width.

`scl_y: f32 = 0` - Height

## AlignX (`enum`)

Used for `Alignment`s.

### Values

**Left** - Leftward alignment.

**Center** - Horizontally centered alignment.

**Right** - Rightward alignment.

## AlignY (`enum`)

Used for `Alignment`s.

### Values

**Bottom** - Bottomward alignment.

**Center** - Vertically centered alignment.

**Top** - Topward alignment.

## Alignment (`struct`)

Determines which part of an `Element` is positioned with its placement.

### Fields

`x: AlignX` - Horizontal alignment.

`y: AlignY` - Vertical alignment.

## Placement (`struct`)

Represents the placement of a UI object. An object's "placement" is used to determine its final draw bounds at runtime.

### Fields

`relative_pos: Bounds` - Position of the object relative to the draw bounds of its parent. A value of 0.5 for example corresponds to either the center of the object or half of it's scale on an axis, depending on interface.

`absolute_offset: Bounds` - An additional pixel value can be added onto each value determined by `relative_pos` to determine a final value.

`alignment: Alignment` - Alignment value. This determines where the "origin point" of the element is, in other words, which part of the element should be placed at the location specified by the previous two fields.

### Public Functions

**`get_default() Placement`**

Returns a 'default' value for placement - zeroing every value of every `Bounds` in the structure.

## ElementDrawMode (`enum`)

Enumeral value representing the draw mode of an element.

### Values

**None** - Don't draw this element at all. This element will not be included in the final instance array, but its children may be.

**Color** - Fill the draw boundaries of the element with a single color.

**Texture** - Fill the draw boundaries of the element with a texture.

**Character** - Draws a monochrome texture, meant for rendering text characters.

**ColoredTexture** - Fill the draw boundaries of the element with a texture, multiplied by a single color.

## ElementCallbackType (`enum`)

Type of an element callback.

### Values

**Tick**

Function called every UI tick.

**MouseEnter**

Function called when the mouse cursor enters the element's boundaries.

**MouseLeave**

Function called when the mouse cursor leaves the element's boundaries.

**MouseHover**

Function called *while* the mouse cursor is within the element's boundaries.

**MousePress**

Function called when a mouse button is pressed and the cursor is within the element's boundaries.

**MouseRelease**

Function called when a mouse button is released and the cursor is within the element's boundaries.

**MouseHold**

Function called *while* a mouse button is being held down and the cursor is within the element's boundaries.

**WindowResize**

Function called when the window with the element container is resized.

**Scroll**

Function called when the mouse wheel scrolls while the cursor is within the element's boundaries.

**Deinit**

Function called when the element is deleted.

**Rebuild**

Function called when the container is rebuilt.

**Copy**

Function called when the element is copied (the callback is performed on the copy).

**AddChild**

Function called when a child is added to the element.

**RemoveChild**

Function called when a child is removed from the element.

## ElementCallback (`struct`)

Stored within an `Element`, activated when a certain event happens (depends on its `type`).

### Fields

`type: ElementCallbackType` - Type of the callback.

`callback: *const fn(*Element, ContainerInputData) anyerror!void` - Callback function.

## CallbackEvent (`struct`)

Structure used by `Container` to organize callback events.

### Fields

`element: *Element` - Element which the callback is being performed on.

`callback: *const fn(*Element, ContainerInputData) anyerror!void` - Callback function.

## ContainerInputData (`struct`)

Container input data, used in event callbacks.

### Fields

`container: *Container = undefined` - Container handle.

`cursor_pos: vk.Offset2D` - Absolute position of the cursor, compared to the window.

`scroll: vk.Offset2D` - Mouse wheel increment.

`mouse_buttons: u8` - 8-bit mask of currently pressed mouse buttons.

`text: ?[]u32` - Text buffer.

`keys: ?[]u32` - Key buffer.

`resized: bool = undefined` - True if the window was resized after the last tick.

## Element (`struct`)

The main unit of the UI system. An `Element` is a quad that is instanced onto the screen, and can represent a colored box, a textured quad, a font character, a button, etc. Elements contain a list of "children" whose final placement on the screen is derived from the placement of its parent element.

### Fields

`allocator: *const std.mem.Allocator` - Allocator handle.

`enabled: bool` - Controls whether the element and its children should draw and update, at all.

`draw_mode: ElementDrawMode` - This element's draw mode.

`placement: Placement` - The placement of the element. This, alongside the final calculated draw boundaries of this element's parent object, will determine the final draw boundaries of this element.

`space: Bounds` - Determines, in pixel units, the total amount of "space" this element uses. If it extends beyond the space allocated by its placement, then the element becomes scrollable. pos_x and pos_y determine the offset of the scissor. If scl_y is -1, then the draw boundaries are assumed to be the same as the cut (or scroll) boundaries, meaning the element doesn't scroll at all.

`freeze: bool` - If enabled, this element's position will be relative to the cut_bounds, instead of the draw_bounds. In other words, this element is "frozen" relative to its parent while other elements with this flag disabled will scroll normally. Doesn't affect elements whose parents don't scroll.

`coordinates: [4]f32` - 'Coordinates' of the element - color values, texture coordinates, etc.

`parent: ?*Element` - This element's parent.

`children: std.ArrayList(*Element)` - Dynamic array of this element's children.

`lineage: ?[]usize` - List of offsets that can lead the container to this element's offset in memory and its children array.

`callbacks: std.ArrayList(ElementCallback)` - Dynamic array of this element's callbacks.

`callback_queue: std.ArrayList(CallbackEvent)` - Queue of currently activated callbacks.

`force_callbacks: std.ArrayList(ElementCallbackType)` - Dynamic array of callback types to force in the next tick.

`layout_data: ?[]u8` - Data used for this element's layout.

`data: ?[]u8` - Other data that may be used for this element's extra logic or callbacks.

`instance_data_offset: ?vk.DeviceSize` - Offset of the element's data in the instance array.

`should_refresh: bool` - Flag to be enabled if the refresh() function is called. Used by the element's origin Container object.

`mouse_enter_toggle: bool` - Set automatically. Used for the callback manager.

`mouse_button_toggles: u8` - Set automatically. Used for the callback manager.

### Structures

#### `RuntimeBounds`

##### Values

`draw_bounds: Bounds` - The actual boundaries of the element. These are the final draw boundaries, derived from `placement` and whatever the `parent`s of this element are.

`cut_bounds: Bounds` - If `space` is set (where `scl_y` is not -1) then `draw_bounds` is used to determine the entire boundaries of the element, while this determines which sub-rectangle (or "window") of the element is actually being drawn.

### Public Functions

**`add(self: *Element, element: *Element) !void`**

Adds a copy of `element` to this element's children array, making the copy one of its children.

**`add_and_dispose(self: *Element, element: *Element) !void`**

After trying **`add`**, deinitializes `element` and destroys it.

**`add_callback(self: *Element, callback_type: ElementCallbackType, callback_func: *const fn(*Element, ContainerInputData) anyerror!void) !void`**

Adds a callback to this element.

**`build_lineage(self: *Element, list: *std.ArrayList(usize)) !void`**

Recursively builds the `lineage` values of this element and its children. Used by `Container`.

**`deinit(self: *Element) anyerror!void`**

Deinitializes, destroys, and frees all memory from an element and its children.

**`force_callback(self: *Element, callback_type: ElementCallbackType) !void`**

Adds a callback type to the force callback queue.

**`get_element_draw_count(self: *Element) usize`**

Returns the total number of children that need to be drawn from this element, including the element's children's children and so on.

**`get_element_instance_data(self: *Element, origin: *Element, origin_bounds: Bounds) ?[13]f32`**

Returns formatted vertex data for this element. Used by `Container` during building.

**`init(allocator: *const std.mem.Allocator, draw_mode: ElementDrawMode, placement: Placement, coordinates: [4]f32) !Element`**

Initializes an element.

**`place_instance_data(self: *Element, data_list: *std.ArrayList(f32), parent_bounds: RuntimeBounds) !void`**

Gets the instance data for this element, alongside it's children, and fills an `ArrayList` with it.

**`refresh(self: *Element, include_children: bool) void`**

Sets the 'should_refresh' flag to true for this element, and all of it's children if "include_children" is enabled. Element refreshing is handled automatically by the Container object.

**`remove_by_index(self: *Element, index: usize) !void`**

Removes one of the elements from the children array and frees it, including all of *its* children.

**`update(self: *Element, erb: RuntimeBounds, input_data: ContainerInputData) !void`**

Updates this element's callbacks, as well as the callbacks for all of its children.

### Private Functions

**`get_runtime_bounds_from_parent(self: *Element, parent_bounds: RuntimeBounds) RuntimeBounds`**

Using this element's placement and this element's parent's draw boundaries, determines this element's draw boundaries.

**`queue_callback(self: *Element, callback: ElementCallback) !void`**

Adds a new `CallbackEvent` to this element's `callback_queue`.

## ContainerRendering (`struct`)

Stores resources that a UI container needs to render UI.

### Fields

`pipeline: *Pipeline` - Graphics pipeline used to render the UI.

`descriptor_set: *PipelineDescriptorSet` - Descriptor set used by the shaders in the `pipeline`.

`render_pass: *RenderPass` - Render pass used to render the UI.

`render_queue: vk.Queue` - Queue used to submit render commands.

`uniform_callback: *const fn(Container, u16) anyerror!void` - Points to a callback function which updates the descriptors (and other data) every frame.

`render_pass_is_reference: bool` - If true, the `render_pass` will **not** be deinitalized/freed when **`deinit`** is called.

### Public Functions

**`deinit(self: *ContainerRendering, vk_context: VkInterface) void`**

Deinitializes the `pipeline`, `descriptor_set`, and the `render_pass` if `render_pass_is_reference` is false.

## Container (`struct`)

The Container acts as an origin point for the UI system, containing an automatically updated "master" element which all other elements can be added to. The container is also responsible for drawing the UI.

### Fields

`interface: *VkInterface` - Vulkan interface.

`vk_allocator: *VulkanAllocator` - Vulkan allocator.

`origin: Element` - The master/origin element of this container. This is used as the container's "entry point" to draw all subelements that the developer will add.

`bounds: Bounds` - Boundaries of the origin element, and by extension this container.

`instance_buffer: ?VulkanAllocator.VulkanBufferAllocation = null` - The final instance buffer, built with the **`build`** function.

`element_draw_count: usize = undefined` - Number of elements that need to be drawn with this container.

`ui_rendering: ContainerRendering` - Struct containing the Vulkan resources used to render the UI system.

`texture_atlas: images.TextureAtlas2D` - Texture atlas to be used by all drawn icons or texture elements other than those that render text.

`tick_rate: u16` - Number of ticks to occur per second.

`tick_timer: f64` - Keeps track of how many ticks need to occur in the next frame.

`prev_time: f64` - Timestamp of last frame.

`resized: bool = false` - Flag enabled when **`set_bounds`** is called. Used to call `WindowResize` events.

`signal_reset_manual_input: bool = false` - Flag signalled when the manual window input values need to be reset.

`signal_rebuild: bool = false` - Flag signalled when a rebuild is requested.

`signal_ignore_callbacks: bool = false` - Flag signalled to ignore callbacks for the next tick (useful for rebuilding).

`callback_queue: std.ArrayList(CallbackEvent)` - Queue of all callbacks for the container.

### Public Functions

add(self: *Container, element: *Element) !void

Adds an element to the origin element of this container.

add_callbacks(self: *Container, callbacks: []CallbackEvent) !void

Used by the `Element`s' updates functions.

add_and_dispose(self: *Container, element: *Element) !void

Adds an element to the origin element of this container, then deletes the original element.

add_texture(self: *Container, texture: *images.Texture2D) !images.TextureAtlas2D.TextureSuballocation

Adds a texture to the texture atlas.

build(self: *Container) !void

Builds (or rebuilds) the instance buffer used for drawing. Recommend using only when elements have been added or removed from the origin element or any of its children. Otherwise, use **`refresh_all`**.

deinit(self: *Container) !void

Deinitializes the container, destroying all elements it holds and freeing all memory it uses.

draw(self: *Container, command_buffer: *CommandBuffer, swapchain: *Swapchain, framebuffer: vk.Framebuffer) !void

Draws the instance arrays using the command buffer onto the framebuffer.

get_element(self: *Container, lineage: []usize) AshbloomUIError!*Element

Returns a pointer to the element with `lineage`.

get_element_bounds(self: *Container, lineage: []usize) AshbloomUIError!Element.RuntimeBounds

Returns the `RuntimeBounds` of the element with `lineage`.

init(interface: *VkInterface, vulkan_allocator: *VulkanAllocator) !Container

Creates a new Container object.

refresh_all(self: *Container) !void

Refreshes the entire element list. Called automatically when set_bounds is performed.

set_bounds(self: *Container, pos_x: f32, pos_y: f32, scl_x: f32, scl_y: f32) !void

Sets the `bounds` object, but also refreshes the instance array after doing so (if the instance array has been built first, otherwise it doesn't).

set_render_instance(self: *Container, resources: ContainerRendering) void

Sets the `ui_rendering` field to `resources`.

update(self: *Container, input_data: ContainerInputData) !void

Updates all callbacks for the origin element and all of its children. Also handles refreshing any elements if necessary.

### Private Functions

**`get_elements_refresh_list(self: *Container, element: *Element, list: *std.ArrayList(*Element)) !void`**

Returns a list of all of the elements contained within this element which need to be refreshed.

**`perform_rebuild_callbacks(self: *Container, e: *Element) !void`**

Responsible for calling all `Rebuild` callback events for all elements within the container.

## Public Fields

`const freetype = @import("freetype")` - FreeType import.

`var ft: freetype.FT_Library = undefined` - FreeType library instance. **`init`** must be called before this is accessed.

`var initialized: bool = false` - True if Ashbloom's UI system has been initialized.

## Public Functions

**`default_scroll_callback(e: *Element, input_data: ContainerInputData) !void`**

The "default," or standard, scroll callback. Moves the scroll position of an element with the mouse scrollwheel.

**`deinit() void`**

Deinitializes Ashbloom's UI system.

**`init() AshbloomUIError!void`**

Initializes Ashbloom's UI system.