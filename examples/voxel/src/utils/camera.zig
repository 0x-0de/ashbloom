const std = @import("std");
const ash = @import("ashbloom");

const glfw = ash.glfw;

const Vec = ash.linalg.Vec;

const CAMERA_SPEED = 0.05;

pub const Camera = struct
{
    pos: Vec(f32, 3),
    rot: Vec(f32, 3),

    prev_cursor_x: f64,
    prev_cursor_y: f64,

    cur_cursor_x: f64,
    cur_cursor_y: f64,

    pub fn init() Camera
    {
        return .{
            .pos = .init(.{0, 0, 0}),
            .rot = .init(.{0, 0, 1}),
            .prev_cursor_x = 0,
            .prev_cursor_y = 0,
            .cur_cursor_x = 0,
            .cur_cursor_y = 0
        };
    }

    pub fn tick(self: *Camera, window: ash.ABWindow) void
    {
        var forward = self.rot;
        
        var forward_compressed = forward;
        forward_compressed.data[1] = 0;
        forward_compressed = ash.linalg.normalize(f32, 3, forward_compressed);

        var side = ash.linalg.cross(f32, Vec(f32, 3).init(.{0, 1, 0}), forward_compressed);

        const speed: f32 = CAMERA_SPEED;

        var modifier: f32 = 1;
        if(glfw.getKey(window.glfw_handle, glfw.KeyLeftShift) == glfw.Press)
        {
            modifier = 10;
        }

        forward.mul(speed * modifier);
        side.mul(speed * modifier);

        if(glfw.getKey(window.glfw_handle, glfw.KeyW) == glfw.Press)
        {
            self.pos.add(forward);
        }
        if(glfw.getKey(window.glfw_handle, glfw.KeyS) == glfw.Press)
        {
            self.pos.sub(forward);
        }
        if(glfw.getKey(window.glfw_handle, glfw.KeyA) == glfw.Press)
        {
            self.pos.sub(side);
        }
        if(glfw.getKey(window.glfw_handle, glfw.KeyD) == glfw.Press)
        {
            self.pos.add(side);
        }
    }

    pub fn update_input(self: *Camera, window: ash.ABWindow, mouse_sensitivity: f64, input_mode: u8) void
    {
        var cursor_x: f64 = undefined;
        var cursor_y: f64 = undefined;

        window.get_cursor_pos(&cursor_x, &cursor_y);

        const delta_x = (cursor_x - self.prev_cursor_x) * mouse_sensitivity;
        const delta_y = (cursor_y - self.prev_cursor_y) * mouse_sensitivity;

        if(input_mode == 1)
        {
            self.cur_cursor_x -= delta_x;
            self.cur_cursor_y += delta_y;
        }

        const limit = std.math.pi / 2.0 - 0.001;

        if(self.cur_cursor_y > limit) self.cur_cursor_y = limit;
        if(self.cur_cursor_y < -limit) self.cur_cursor_y = -limit;

        self.rot.data[0] = @floatCast(std.math.cos(self.cur_cursor_x) * std.math.cos(self.cur_cursor_y));
        self.rot.data[1] = @floatCast(std.math.sin(self.cur_cursor_y));
        self.rot.data[2] = @floatCast(std.math.sin(self.cur_cursor_x) * std.math.cos(self.cur_cursor_y));

        self.prev_cursor_x = cursor_x;
        self.prev_cursor_y = cursor_y;
    }
};
