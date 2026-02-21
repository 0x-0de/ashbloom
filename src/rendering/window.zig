const std = @import("std");

const glfw = @import("glfw");

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

pub const Window = struct
{
    width: u32,
    height: u32,

    glfw_handle: *c_long,

    pub fn destroy(self: Window) void
    {
        glfw.destroyWindow(self.glfw_handle);
    }

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

    pub fn get_cursor_pos(self: Window, x: *f64, y: *f64) void
    {
        var w: u32 = undefined;
        var h: u32 = undefined;

        self.get_framebuffer_size(&w, &h);

        var cursor_x: f64 = undefined;
        var cursor_y: f64 = undefined;

        glfw.getCursorPos(self.glfw_handle, &cursor_x, &cursor_y);

        cursor_y *= -1;
        cursor_y += @as(f64, @floatFromInt(h));

        x.* = cursor_x;
        y.* = cursor_y;
    }

    pub fn get_framebuffer_size(self: Window, width: *u32, height: *u32) void
    {
        var w: c_int = undefined;
        var h: c_int = undefined;

        glfw.getFramebufferSize(self.glfw_handle, &w, &h);

        width.* = @intCast(w);
        height.* = @intCast(h);
    }

    pub fn get_mouse_button(self: Window, button: glfw.Mouse) glfw.KeyState
    {
        return glfw.getMouseButton(self.glfw_handle, button);
    }

    pub fn get_ui_container_input(self: Window) ContainerInputData
    {
        var cursor_x: f64 = undefined;
        var cursor_y: f64 = undefined;

        self.get_cursor_pos(&cursor_x, &cursor_y);

        const mouse_buttons = self.get_all_mouse_buttons();

        return .{
            .cursor_pos = .{
                .x = @intFromFloat(cursor_x),
                .y = @intFromFloat(cursor_y)
            },
            .scroll = .{
                .x = @intFromFloat(scroll_x),
                .y = @intFromFloat(scroll_y)
            },
            .mouse_buttons = mouse_buttons,
            .text = if(window_text_buffer_cap == 0) null else window_text_buffer[0..window_text_buffer_cap],
            .keys = if(window_key_buffer_cap == 0) null else window_key_buffer[0..window_key_buffer_cap]
        };
    }

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

    pub fn reset_input_values() void
    {
        scroll_x = 0;
        scroll_y = 0;

        window_text_buffer_cap = 0;
        window_key_buffer_cap = 0;
    }

    pub fn should_close(self: Window) bool
    {
        return glfw.windowShouldClose(self.glfw_handle);
    }
};
