//! Root file for Ashbloom.
//! All modules (source files) are exposed here.

const win32 = @import("win32");
pub const UNICODE = false;

// Namespaces.

pub const vk = @import("vulkan");
pub const glfw = @import("glfw");

pub const commands = @import("rendering\\commands.zig");
pub const pipeline = @import("rendering\\pipeline.zig");
pub const vk_context = @import("rendering\\vkcontext.zig");
pub const window = @import("rendering\\window.zig");

pub const font = @import("utils\\font.zig");
pub const image_utils = @import("utils\\image_utils.zig");
pub const math = @import("utils\\linalg.zig");
pub const misc = @import("utils\\misc.zig");
pub const vk_memory = @import("utils\\vkmemory.zig");
pub const vk_ui = @import("utils\\vkui.zig");
pub const vk_utils = @import("utils\\vkutils.zig");

pub const ui_theme_basic = @import("utils\\ui_themes\\basic.zig");

// Types.

pub const CommandBuffer = commands.CommandBuffer;

pub const PipelineVertexInput = pipeline.PipelineVertexInput;
pub const PipelineDescriptorSet = pipeline.PipelineDescriptorSet;
pub const Pipeline = pipeline.Pipeline;

pub const RenderPass = @import("rendering\\renderpass.zig").RenderPass;

pub const Swapchain = @import("rendering\\swapchain.zig").Swapchain;

pub const VkContext = vk_context.VkContext;

pub const Window = window.Window;

pub const FontCharacter = font.FontCharacter;
pub const Font = font.Font;

pub const Texture2D = image_utils.Texture2D;
pub const TextureAtlas2D = image_utils.TextureAtlas2D;

pub const Vec = math.Vec;
pub const Mat = math.Mat;

pub const FontEntry = misc.FontEntry;
pub const FontFamily = misc.FontFamily;

pub const VulkanAllocator = vk_memory.VulkanAllocator;

pub const Bounds = vk_ui.Bounds;
pub const Alignment = vk_ui.Alignment;
pub const ElementCallback = vk_ui.ElementCallback;
pub const ContainerInputData = vk_ui.ContainerInputData;
pub const Element = vk_ui.Element;
pub const ContainerRendering = vk_ui.ContainerRendering;
pub const Container = vk_ui.Container;

/// Deinitializes the graphical side of the ashbloom framework, and all its dependencies (including GLFW).
pub fn deinit_graphics() void
{
    glfw.terminate();
}

/// Initializes the graphical side of the ashbloom framework, and all its dependencies (including GLFW).
pub fn init_graphics() !void
{
    try glfw.init();
}

comptime
{
    _ = commands;
    _ = pipeline;
    _ = vk_context;
    _ = window;

    _ = font;
    _ = image_utils;
    _ = math;
    _ = misc;
    _ = vk_memory;
    _ = vk_ui;
    _ = vk_utils;

    _ = ui_theme_basic;

    _ = RenderPass;
    _ = Swapchain;

    _ = UNICODE;
}
