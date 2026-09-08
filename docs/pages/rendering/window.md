# `window`

Contains the Window structure and relevant handlers. Uses GLFW for window creation.

## Window (`struct`)

Contains the handle and relevant functions for a GLFW window.

### Fields

`width: u32` - Width of the window.

`height: u32` - Height of the window.

`glfw_handle: *c_long` - GLFW window handle.

### Public Functions

**`destroy(self: Window) void`**

Destroys and deinitializes the window.

**`get_all_mouse_buttons(self: Window) u8`**

Returns a u8 bitset with each bit corresponding to each mouse button. GLFW supports up to 8 mouse button inputs.

**`get_cursor_pos(self: Window, left_handed: bool) vk.Offset2D`**

Returns the cursor position relative to the window. If `left_handed` is true, the `y` value increases as the mouse cursor moves up, with a value of 0 corresponding to the bottom of the window. Otherwise, the `y` value increases as the mouse cursor moves down, with a value of 0 corresponding to the top of the screen.

**`get_framebuffer_size(self: Window) vk.Extent2D`**

Returns the size of the window's framebuffer (the "content" of the window).

**`get_key(self: Window, key: glfw.Key) glfw.KeyState`**

Returns the GLFW `KeyState` of the provided `key`.

**`get_mouse_button(self: Window, button: glfw.Mouse) glfw.KeyState`**

Returns the GLFW `KeyState` of the provided `button`.

**`get_ui_container_input(self: Window) ContainerInputData`**

Returns a `ContainerInputData` structure, used by a UI `Container` object to detect UI input events.

**`init(width: u32, height: u32, title: [*:0]const u8) !Window`**

Initializes the window.

**`should_close(self: Window) bool`**

Returns true if the window should close. Usually used as the condition for a game, application, or draw loop.

### Public Static Functions

**`reset_input_values() void`**

Resets all **global** input values. Must be called at least once before or after a UI update events call in a draw loop.

## Private Fields

```
var scroll_x: f64 = 0
var scroll_y: f64 = 0
```

GLFW's scroll input functions, for whatever reason, are not window-specific, and must be handled globally.

```
var window_text_buffer_cap: u16 = undefined
var window_text_buffer: [256]u32 = undefined
```

Records the global GLFW text input.

```
var window_key_buffer_cap: u16 = undefined
var window_key_buffer: [256]u32 = undefined
```

Records the global GLFW key input.

## Private Functions

**`window_scroll_callback(win: *c_long, x: f64, y: f64) callconv(.c) void`**

Global scroll event callback. Updates the `scroll_x` and `scroll_y` fields.

**`window_text_callback(win: *c_long, codepoint: c_uint) callconv(.c) void`**

Global text event callback. Updates the `window_text_buffer` and `window_text_buffer_cap` fields.

**`window_key_callback(win: *c_long, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void`**

Global key event callback. Updates the `window_key_buffer` and `window_key_buffer_cap` fields.