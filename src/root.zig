//! Root file for Ashbloom.
//! All modules (source files) are exposed here.

const std = @import("std");
const win32 = @import("win32");

/// Required field for win32 API.
pub const UNICODE = false;

// Namespaces.

pub const vk = @import("vulkan");
pub const glfw = @import("glfw");

pub const attachment = @import("rendering/attachment.zig");
pub const commands = @import("rendering/commands.zig");
pub const pipeline = @import("rendering/pipeline.zig");
pub const vk_context = @import("rendering/vkcontext.zig");
pub const window = @import("rendering/window.zig");
pub const mesh = @import("rendering/mesh.zig");

pub const linalg = @import("math/linalg.zig");
pub const interp = @import("math/interp.zig");
pub const random = @import("math/random.zig");

pub const font = @import("utils/font.zig");
pub const image_utils = @import("utils/image_utils.zig");
pub const misc = @import("utils/misc.zig");
pub const vk_memory = @import("utils/vkmemory.zig");
pub const ui = @import("utils/vkui.zig");
pub const vk_utils = @import("utils/vkutils.zig");

pub const ui_layouts = @import("utils/layouts.zig");
pub const ui_theme_basic = @import("utils/ui_themes/basic.zig");

// Types.

pub const Attachment = attachment.Attachment;
pub const AttachmentBundle = attachment.AttachmentBundle;

pub const CommandBuffer = commands.CommandBuffer;

pub const PipelineVertexInput = pipeline.PipelineVertexInput;
pub const PipelineDescriptorSet = pipeline.PipelineDescriptorSet;
pub const Pipeline = pipeline.Pipeline;

pub const RenderPass = @import("rendering/renderpass.zig").RenderPass;

pub const Swapchain = @import("rendering/swapchain.zig").Swapchain;

pub const VkContext = vk_context.VkContext;

pub const Mesh = mesh.Mesh;

/// Named "ABWindow" because vulkan-zig will try to interface with it if it's just named "Window".
pub const ABWindow = window.Window;

pub const FontCharacter = font.FontCharacter;
pub const Font = font.Font;

pub const Texture2D = image_utils.Texture2D;
pub const TextureAtlas2D = image_utils.TextureAtlas2D;

pub const Vec = linalg.Vec;
pub const Mat = linalg.Mat;

pub const FontEntry = misc.FontEntry;
pub const FontFamily = misc.FontFamily;

pub const VulkanAllocator = vk_memory.VulkanAllocator;

pub const Bounds = ui.Bounds;
pub const Alignment = ui.Alignment;
pub const ElementCallback = ui.ElementCallback;
pub const ContainerInputData = ui.ContainerInputData;
pub const Element = ui.Element;
pub const ContainerRendering = ui.ContainerRendering;
pub const Container = ui.Container;

var stdout_io: std.Io.Threaded = undefined;
var stdout_buffer: [2048]u8 = undefined;
var stdout_writer: std.Io.File.Writer = undefined;

var stdout: *std.Io.Writer = undefined;

/// Deinitializes the graphical side of the ashbloom framework, and all its dependencies (including GLFW).
pub fn deinit_graphics() void
{
    glfw.terminate();
}

/// Initializes the graphical side of the ashbloom framework, and all its dependencies (including GLFW).
pub fn init_graphics(allocator: *const std.mem.Allocator) !void
{
    stdout_io = .init(allocator.*, .{});
    stdout_writer = std.Io.File.stdout().writer(stdout_io.io(), &stdout_buffer);
    stdout = &stdout_writer.interface;

    try glfw.init();

    glfw.windowHint(glfw.ClientAPI, glfw.NoAPI);
}

/// Prints to the standard output. Useful since Zig's `std.debug.print` prints to stderr. Ashbloom inits its own instance of stdout().writer so this is just a shortcut.
/// Max buffer size is 2048 characters, exceeding this value will likely cause a panic.
pub fn print_stdout(comptime fmt: []const u8, args: anytype) void
{
    stdout.print(fmt, args) catch unreachable;
    stdout.flush() catch unreachable;
}

comptime
{
    _ = commands;
    _ = pipeline;
    _ = vk_context;
    _ = window;
    _ = mesh;

    _ = linalg;
    _ = interp;
    _ = random;

    _ = font;
    _ = image_utils;
    _ = misc;
    _ = vk_memory;
    _ = ui;
    _ = vk_utils;

    _ = ui_layouts;
    _ = ui_theme_basic;

    _ = RenderPass;
    _ = Swapchain;

    _ = UNICODE;
}
