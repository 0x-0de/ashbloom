const std = @import("std");

const glfw = @import("glfw");
const vk = @import("vulkan");

var scroll_x: f64 = 0;
var scroll_y: f64 = 0;

const vkui = @import("../utils/vkui.zig");

const Container = vkui.Container;
const ContainerInputData = vkui.ContainerInputData;

fn window_scroll_callback(win: *c_long, x: f64, y: f64) callconv(.c) void
{
    _ = win;

    scroll_x += x;
    scroll_y += y;
}

var window_text_buffer_cap: u16 = undefined;
var window_text_buffer: [256]u32 = undefined;

var window_key_buffer_cap: u16 = undefined;
var window_key_buffer: [256]u32 = undefined;

fn window_text_callback(win: *c_long, codepoint: c_uint) callconv(.c) void
{
    _ = win;

    if(window_text_buffer_cap < 256)
    {
        window_text_buffer[window_text_buffer_cap] = @intCast(codepoint);
        window_text_buffer_cap += 1;
    }
}

fn window_key_callback(win: *c_long, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void
{
    _ = win;

    _ = scancode;
    _ = mods;

    if(window_key_buffer_cap < 256)
    {
        if(action == glfw.Press or action == glfw.Repeat)
        {
            window_key_buffer[window_key_buffer_cap] = @intCast(key);
            window_key_buffer_cap += 1;
        }
    }

    if(window_text_buffer_cap < 256)
    {
        if(key == glfw.KeyBackspace and (action == glfw.Press or action == glfw.Repeat))
        {
            window_text_buffer[window_text_buffer_cap] = 8; // Backspace ASCII code.
            window_text_buffer_cap += 1;
        }
    }
}

/// Contains information about a window. Currently, ashbloom primarily only supports 1 window, so certain input features will not work across multiple windows.
pub const Window = struct
{
    /// Width of the window.
    width: u32,
    /// Height of the window.
    height: u32,

    /// GLFW handle, used for calling GLFW functions like setInputMode.
    glfw_handle: *c_long,

    /// Destroys the window. Used in place of deinit-ing.
    pub fn destroy(self: Window) void
    {
        glfw.destroyWindow(self.glfw_handle);
    }

    /// Returns an 8-bitset with each bit corresponding to each mouse button. GLFW supports up to 8 mouse button inputs.
    pub fn get_all_mouse_buttons(self: Window) u8
    {
        var mouse_buttons: u8 = 0;

        for(0..8) |i|
        {
            mouse_buttons |= if(self.get_mouse_button(glfw.MouseButton1 + @as(c_int, @truncate(@as(isize, @bitCast(i))))) == glfw.Press)
                (@as(u8, 1) << @truncate(i)) else 0;
        }

        return mouse_buttons;
    }

    /// Returns the cursor position relative to the window. If "left_handed" is true, the bottom of the window is 0, otherwise it's the top.
    pub fn get_cursor_pos(self: Window, left_handed: bool) vk.Offset2D
    {
        const window_size = self.get_framebuffer_size();

        var cursor_x: f64 = undefined;
        var cursor_y: f64 = undefined;

        glfw.getCursorPos(self.glfw_handle, &cursor_x, &cursor_y);

        if(left_handed)
        {
            cursor_y *= -1;
            cursor_y += @as(f64, @floatFromInt(window_size.height));
        }

        return .{
            .x = @intFromFloat(cursor_x),
            .y = @intFromFloat(cursor_y)
        };
    }

    /// Returns the framebuffer size as a vk.Extent2D.
    pub fn get_framebuffer_size(self: Window) vk.Extent2D
    {
        var w: c_int = undefined;
        var h: c_int = undefined;

        glfw.getFramebufferSize(self.glfw_handle, &w, &h);

        return .{
            .width = @intCast(w),
            .height = @intCast(h)
        };
    }

    /// Returns the GLFW KeyState of the `key`.
    pub fn get_key(self: Window, key: glfw.Key) glfw.KeyState
    {
        return glfw.getKey(self.glfw_handle, key);
    }

    /// Returns the GLFW KeyState of the `button`.
    pub fn get_mouse_button(self: Window, button: glfw.Mouse) glfw.KeyState
    {
        return glfw.getMouseButton(self.glfw_handle, button);
    }

    /// Returns a ContainerInputData structure, used by a UI Container object to detect UI input events.
    pub fn get_ui_container_input(self: Window) ContainerInputData
    {
        const cursor_pos = self.get_cursor_pos();
        const mouse_buttons = self.get_all_mouse_buttons();

        return .{
            .cursor_pos = cursor_pos,
            .scroll = .{
                .x = @intFromFloat(scroll_x),
                .y = @intFromFloat(scroll_y)
            },
            .mouse_buttons = mouse_buttons,
            .text = if(window_text_buffer_cap == 0) null else window_text_buffer[0..window_text_buffer_cap],
            .keys = if(window_key_buffer_cap == 0) null else window_key_buffer[0..window_key_buffer_cap]
        };
    }

    /// Initializes the window.
    pub fn init(width: u32, height: u32, title: [*:0]const u8) !Window
    {
        window_text_buffer_cap = 0;
        for(0..256) |i|
        {
            window_text_buffer[i] = 0;
        }

        window_key_buffer_cap = 0;
        for(0..256) |i|
        {
            window_key_buffer[i] = 0;
        }

        const w: c_int = @intCast(width);
        const h: c_int = @intCast(height);

        const window_handle = try glfw.createWindow(w, h, title, null, null);

        _ = glfw.setKeyCallback(window_handle, window_key_callback);
        _ = glfw.setScrollCallback(window_handle, window_scroll_callback);
        _ = glfw.setCharCallback(window_handle, window_text_callback);

        return .{
            .width = width,
            .height = height,
            .glfw_handle = window_handle
        };
    }

    /// Resets all input values. Must be called at least once before or after a UI update events call in a draw loop.
    pub fn reset_input_values() void
    {
        scroll_x = 0;
        scroll_y = 0;

        window_text_buffer_cap = 0;
        window_key_buffer_cap = 0;
    }

    /// Returns true if the window should close. Usually used as the condition for a game, application, or draw loop.
    pub fn should_close(self: Window) bool
    {
        return glfw.windowShouldClose(self.glfw_handle);
    }
};
