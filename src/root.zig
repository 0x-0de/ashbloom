//! Root source file.
//! All modules (source files) are exposed here.

pub const commands = @import("rendering\\commands.zig");
pub const pipeline = @import("rendering\\pipeline.zig");
pub const vk_context = @import("rendering\\vkcontext.zig");
pub const window = @import("rendering\\window.zig");

pub const font = @import("utils\\font.zig");
pub const image_utils = @import("utils\\image_utils.zig");
pub const linalg = @import("utils\\linalg.zig");
pub const vk_memory = @import("utils\\vkmemory.zig");
pub const vk_ui = @import("utils\\vkui.zig");
pub const vk_utils = @import("utils\\vkutils.zig");

pub const ui_theme_basic = @import("utils\\ui_themes\\basic.zig");

pub const RenderPass = @import("rendering\\renderpass.zig").RenderPass;
pub const Swapchain = @import("rendering\\swapchain.zig").Swapchain;

comptime
{
    _ = commands;
    _ = pipeline;
    _ = vk_context;
    _ = window;

    _ = font;
    _ = image_utils;
    _ = linalg;
    _ = vk_memory;
    _ = vk_ui;
    _ = vk_utils;

    _ = ui_theme_basic;

    _ = RenderPass;
    _ = Swapchain;
}
