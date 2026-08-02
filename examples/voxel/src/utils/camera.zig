const std = @import("std");
const ash = @import("ashbloom");

const glfw = ash.glfw;
const vk = ash.vk;

const Vec = ash.linalg.Vec;

const CAMERA_SPEED = 0.05;

const Offset2Df64 = struct
{
    x: f64,
    y: f64
};

/// Simple struct representing a camera in 3D space.
pub const Camera = struct
{
    pos: Vec(f32, 3),
    rot: Vec(f32, 3),

    prev_cursor_pos: Offset2Df64,
    cur_cursor_pos: Offset2Df64,

    /// Initializes the camera.
    pub fn init() Camera
    {
        return .{
            .pos = .init(.{0, 0, 0}),
            .rot = .init(.{0, 0, 1}),
            .prev_cursor_pos = .{
                .x = 0,
                .y = 0
            },
            .cur_cursor_pos = .{
                .x = 0,
                .y = 0
            }
        };
    }

    /// Handles tick-based update events (such as camera movement).
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

    /// Handles non-tick-based update events (such as camera rotation via mouse).
    pub fn update_input(self: *Camera, window: ash.ABWindow, mouse_sensitivity: f64, input_mode: u8) void
    {
        const cursor_pos = window.get_cursor_pos(true);

        const delta_x = (cursor_pos.x - self.prev_cursor_pos.x) * mouse_sensitivity;
        const delta_y = (cursor_pos.y - self.prev_cursor_pos.y) * mouse_sensitivity;

        if(input_mode == 1)
        {
            self.cur_cursor_pos.x -= delta_x;
            self.cur_cursor_pos.y += delta_y;
        }

        const limit = std.math.pi / 2.0 - 0.001;

        if(self.cur_cursor_pos.y > limit) self.cur_cursor_pos.y = limit;
        if(self.cur_cursor_pos.y < -limit) self.cur_cursor_pos.y = -limit;

        self.rot.data[0] = @floatCast(std.math.cos(self.cur_cursor_pos.x) * std.math.cos(self.cur_cursor_pos.y));
        self.rot.data[1] = @floatCast(std.math.sin(self.cur_cursor_pos.y));
        self.rot.data[2] = @floatCast(std.math.sin(self.cur_cursor_pos.x) * std.math.cos(self.cur_cursor_pos.y));

        self.prev_cursor_pos.x = cursor_pos.x;
        self.prev_cursor_pos.y = cursor_pos.y;
    }
};
