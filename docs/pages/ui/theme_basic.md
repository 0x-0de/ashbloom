# `theme_basic`

Contains example (or immediate-mode) element templates, implementing common UI widgets and components like buttons, text, sliders, textfields, etc. Allows you to load XML files to populate an element or container with children.

Certain private functions (mostly element callback functions and `Data` structs which store element data found in their `data` slices) have been omitted from this module's documentation due to redundancy.

## BasicUIElementType (`enum`)

### Values

**Quad**: See **`create_quad`**.

**Icon**: See **`create_icon`**.

**TextCharacter**: See **`create_text_character`**.

**Text**: See **`create_text`**.

**Button**: See **`create_button`**.

**Scrollbar**: See **`create_scrollbar`**.

**Checkbox**: See **`create_checkbox`**.

**Slider**: See **`create_slider`**.

**Textfield**: See **`create_textfield`**.

## FontCharacterElement (`struct`)

Utility struct which stores a text character element (created with **`create_text_character`**) and its associated `FontCharacter`.

### Fields

`element: *Element` - Pointer to the text character element.

`character: FontCharacter` - Text character data.

## TextLine (`struct`)

Utility struct storing information about a line of UI text.

### Fields

`start: usize` - Offset of the text array where the line starts.

`length: usize` - Number of characters the line contains.

`size: f32` - Width of the line, in pixels.

`alignment_push: f32` - Amount of pixels to 'push' the line forward so that it fits the horizontal alignment.

## TextProperties (`struct`)

Specifies properties of a text element required in its creation.

### Fields

`font: *Font` - Text font.

`size: f32` - Text pixel size.

`alignment: vkui.Alignment` - Alignment of individual lines of text in relation to the parent element.

`string: []u32` - Text, in unicode (u32) values.

`margin: f32` - Horizontal border between the text and the edge of the parent element.

### Public Functions

**`init(font: *Font, size: f32, alignment: vkui.Alignment, string: []u32, margin: f32) TextData`**

Populates and returns a `TextData` struct.

## ButtonProperties

Determines the properties of a created button element.

### Fields

`placement: Placement` - Placement of the button.

`color_idle: [4]f32` - Color to display when the button isn't being interacted with.

`color_hover: [4]f32` - Color to display when the button is being hovered by the mouse cursor.

`color_press: [4]f32` - Color to display when the button is being pressed.

`press_callback: *const fn(*Element) anyerror!void` - Specific callback to be called whenever the button is finished being pressed.

### Public Functions

**`init_default() ButtonProperties`**

Pending removal. Initializes `ButtonProperties` with some default values.

## CheckboxProperties (`struct`)

Required properties to specify when creating a checkbox element.

### Fields

`placement: Placement` - Placement of the checkbox.

`start_ticked: bool` - Initial value of the checkbox.

`color_border: [4]f32` - Color to display on the checkbox's border.

`color_hover: [4]f32` - Color to display when the checkbox is being hovered.

`color_ticked: [4]f32` - Color to display when the checkbox is ticked.

`border_width: f32` - Width of the checkbox's border.

`callback: *const fn(*Element, bool) void` - Callback function to call when the checkbox is un/ticked.

### Public Functions

**`init_default() ButtonProperties`**

Pending removal. Initializes `CheckboxProperties` with some default values.

## SliderProperties (`struct`)

`placement: Placement` - Placement of the slider.

`discrete_values: u32` - Number of discrete values the slider can scroll to. Set to 0 if the slider is continuous.

`start_value: f32` - Initial value of the slider.

`color_bar: [4]f32` - Color of the bar behind the knob.

`color_knob_idle: [4]f32` - Color of the knob when not being hovered by the mouse.

`color_knob_hover: [4]f32` - Color of the knob when being hovered by the mouse.

`color_knob_press: [4]f32` - Color of the knob when being pressed.

`bar_width: f32` - Width of the bar, in pixels.

`knob_width: f32` - Width of the knob, in pixels.

`horizontal: bool` - If true, the slider knob slides left-to-right. If false, it slides top-to-bottom.

`callback: *const fn(*Element, f32) void` - Called when the slider's value is updated.

### Public Functions

**`init_default(placement: Placement) SliderProperties`**

Pending removal. Initializes `SliderProperties` with some default values.

## TextFieldProperties (`struct`)

Determines the properties of a textfield element.

### Fields

`font: *Font` - Font used for the text.

`text_size: f32 = 20` - Text size.

```text_alignment: vkui.Alignment = .{
	.x = .Left,
	.y = .Top
}``` - Alignment of the text within the textfield, including the direction which the text will "grow" in.

`initial_text: []u32 = &.{}` - Initial text for the field to start with.

`extension_protocol: TextFieldExtension = .ScrollVertically` - Determines how the textfield should handle text overflow.

## XMLUIFontEntry (`struct`)

Specifies a font asset used in the XML loader.

### Fields

`name: []const u8` - Identifier of the font entry.

`font: *Font` - Font.

## XMLUICallbackEntry (`struct`)

Specifies a callback asset used in the XML loader.

### Fields

`name: []const u8` - Identifier of the callback entry.

`callback: *const fn(*Element, ContainerInputData) anyerror!void` - Callback.

## XMLUIAssets (`struct`)

Specifies fonts and callbacks referenced in XML files.

### Fields

`fonts: []const XMLUIFontEntry` - List of font assets to use in the XML loader.

`callbacks: []const XMLUICallbackEntry` - List of callback assets to use in the XML loader.

## Errors

### XMLUIError

**UnknownElement** - Element type specified isn't recognized.

**UnknownAttribute** - Element attribute type specified isn't recognized.

**CannotParseData** - Data specified in an attribute can't be parsed.

**TooMuchData** - The amount of data provided exceeds what is necessary. For example, color attributes require 4 floats, passing 5 or more would trip this error.

**WrongClosingTag** - Element closing tags are wrong, or not in the correct order.

**MultipleContainers** - XML files can only have a single `<container>` tag.

## Public Functions

**`create_button(allocator: *const std.mem.Allocator, properties: ButtonProperties) !*Element`**

Creates a button element, which the user can click.

**`create_icon(allocator: *const std.mem.Allocator, placement: Placement, tex_coords: [4]f32) !*Element`**

Creates an icon, image, or sprite quad. Must be deallocated.

**`create_quad(allocator: *const std.mem.Allocator, placement: Placement, color: [4]f32) !*Element`**

Creates a colored quad. Must be deallocated.

**`create_scrollbar(allocator: *const std.mem.Allocator) !*Element`**

Creates scroll sliders where applicable. Meant to added to scrollable elements.

**`create_slider(allocator: *const std.mem.Allocator, properties: SliderProperties) !*Element`**

Creates a slider element, which the user can interact with.

**`create_text(allocator: *const std.mem.Allocator, properties: TextProperties) !*Element`**

Creates a text element, which uses the element's parent to host the text. For example, adding this element as a child to a simple quad would mean the text would attempt to fit within said quad.

**`create_text_character(allocator: *const std.mem.Allocator, placement: Placement, font: *Font, size: f32, unicode: u32) !FontCharacterElement`**

Creates an image quad which displays a letter, symbol, or glyph from a font.

**`create_textfield(allocator: *const std.mem.Allocator, placement: Placement, properties: TextFieldProperties) !*Element`**

Creates a textfield element, which the user can store text within.

**`init_basic_render_pass(interface: *VkInterface, swapchain: Swapchain) !*RenderPass`**

Provides a basic render pass to use with the `theme_basic` UI elements, if you don't want to create one for the `ContainerRendering` struct yourself.

**`init_render_instance(interface: *VkInterface, vulkan_allocator: *VulkanAllocator, swapchain: Swapchain, container: Container, render_pass: ?*RenderPass, render_queue: vk.Queue) !vkui.ContainerRendering`**

Initializes a new graphics pipeline and populates a `ContainerRendering` struct.

**`get_textfield_text(e: *Element) []u32`**

Returns the unicode string currently inside a textfield.

**`get_unicode_from_string(allocator: *const std.mem.Allocator, string: []const u8) !std.ArrayList(u32)`**

Converts a slice string (`[]const u8`) to an `ArrayList` of `u32` values, more usable with `TextProperties`.

**`load_xml_ui(allocator: *const std.mem.Allocator, path: []const u8, element: *Element, assets: XMLUIAssets) !void`**

Loads an XML file at `path` and populates the `element` with the elements specified within. `assets` should contain the fonts and callbacks specified in the XML file. See the `xml_to_ui` test (located in `ashbloom/tests/xml_to_ui`) for an example of how this is used.

**`test_callback_button_press(e: *Element) void`**

Example function used to test button press callbacks. Prints a message every time a button is pressed, which includes the address of the button element in memory.