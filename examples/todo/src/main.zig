const std = @import("std");
const print = std.debug.print;

const ash = @import("ashbloom");
const glfw = ash.glfw;

pub fn main() !void
{
    try ash.init_graphics();
    defer ash.deinit_graphics();

    var dba: std.heap.DebugAllocator(.{}) = .{};
    defer {
        const dba_result = dba.deinit();
        if(dba_result == .leak)
        {
            print("Program terminating with {d} memory leaks.\n", .{@intFromEnum(dba_result)});
        }
    }

    const allocator = dba.allocator();
    _ = allocator;

    glfw.windowHint(glfw.ClientAPI, glfw.NoAPI);

    const window = try ash.window.Window.init(1280, 720, "UI Test Application");
    defer window.destroy();
}