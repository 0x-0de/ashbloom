//! Root file for Ashbloom.
//! All modules (source files) are exposed here.

const std = @import("std");
const win32 = @import("win32");

/// Required field for win32 API.
pub const UNICODE = false;

// Namespaces.

pub const vk = @import("vulkan");
pub const glfw = @import("glfw");
pub const xml = @import("xml");

/// Utilities related to procedural generation, whether it's noise algorithms like Perlin noise or polygonization algorithms like marching cubes.
pub const gen = struct
{
    pub const polygonizers = @import("gen/polygonizers.zig");
    pub const random = @import("math/random.zig");

    pub const MarchingCubes = polygonizers.MarchingCubes;
    pub const MarchingTetrahedra = polygonizers.MarchingTetrahedra;
    pub const SurfaceNets = polygonizers.SurfaceNets;
};

/// Utilities related to advanced math, like vector and matrix math, as well as different methods of interpolation.
pub const math = struct
{
    pub const linalg = @import("math/linalg.zig");
    pub const interp = @import("math/interp.zig");

    pub const Vec = linalg.Vec;
    pub const Mat = linalg.Mat;
};

pub const rendering = struct
{
    pub const attachment = @import("rendering/attachment.zig");
    pub const commands = @import("rendering/commands.zig");
    pub const mesh = @import("rendering/mesh.zig");
    pub const pipeline = @import("rendering/pipeline.zig");
    pub const vk_core = @import("rendering/vkcontext.zig");
    pub const window = @import("rendering/window.zig");

    pub const Attachment = attachment.Attachment;
    pub const AttachmentBundle = attachment.AttachmentBundle;

    pub const CommandBuffer = commands.CommandBuffer;

    pub const Mesh = mesh.Mesh;

    pub const PipelineVertexInput = pipeline.PipelineVertexInput;
    pub const PipelineDescriptorSet = pipeline.PipelineDescriptorSet;
    pub const Pipeline = pipeline.Pipeline;

    pub const RenderPass = @import("rendering/renderpass.zig").RenderPass;

    pub const Swapchain = @import("rendering/swapchain.zig").Swapchain;

    pub const VkContext = vk_core.VkContext;
    pub const VkInterface = vk_core.VkInterface;

    pub const Window = window.Window;
};

pub const utils = struct
{
    pub const image_utils = @import("utils/image_utils.zig");
    pub const misc = @import("utils/misc.zig");
    pub const vk_memory = @import("utils/vkmemory.zig");
    pub const vk_utils = @import("utils/vkutils.zig");

    pub const FontEntry = misc.FontEntry;
    pub const FontFamily = misc.FontFamily;

    pub const Texture2D = image_utils.Texture2D;
    pub const TextureAtlas2D = image_utils.TextureAtlas2D;

    pub const VulkanAllocator = vk_memory.VulkanAllocator;
};

pub const ui = struct
{
    pub const core = @import("utils/vkui.zig");
    pub const font = @import("utils/font.zig");
    pub const layouts = @import("utils/layouts.zig");
    pub const theme_basic = @import("utils/ui_themes/basic.zig");

    pub const Alignment = core.Alignment;
    pub const Bounds = core.Bounds;
    pub const Container = core.Container;
    pub const ContainerInputData = core.ContainerInputData;
    pub const ContainerRendering = core.ContainerRendering;
    pub const Element = core.Element;
    pub const ElementCallback = core.ElementCallback;
    pub const Font = font.Font;
    pub const FontCharacter = font.FontCharacter;
};

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
    _ = gen;
    _ = math;
    _ = rendering;
    _ = utils;
    _ = ui;

    _ = gen.polygonizers;
    _ = gen.random;

    _ = gen.MarchingCubes;
    _ = gen.MarchingTetrahedra;
    _ = gen.SurfaceNets;

    _ = math.interp;
    _ = math.linalg;

    _ = math.Mat;
    _ = math.Vec;

    _ = rendering.attachment;
    _ = rendering.commands;
    _ = rendering.mesh;
    _ = rendering.pipeline;
    _ = rendering.vk_core;
    _ = rendering.window;

    _ = rendering.Attachment;
    _ = rendering.AttachmentBundle;
    _ = rendering.CommandBuffer;
    _ = rendering.Mesh;
    _ = rendering.Pipeline;
    _ = rendering.PipelineDescriptorSet;
    _ = rendering.PipelineVertexInput;
    _ = rendering.RenderPass;
    _ = rendering.Swapchain;
    _ = rendering.VkContext;
    _ = rendering.VkInterface;
    _ = rendering.Window;

    _ = utils.image_utils;
    _ = utils.misc;
    _ = utils.vk_memory;
    _ = utils.vk_utils;

    _ = utils.FontEntry;
    _ = utils.FontFamily;
    _ = utils.Texture2D;
    _ = utils.TextureAtlas2D;
    _ = utils.VulkanAllocator;

    _ = ui.core;
    _ = ui.font;
    _ = ui.layouts;
    _ = ui.theme_basic;

    _ = ui.Alignment;
    _ = ui.Bounds;
    _ = ui.Container;
    _ = ui.ContainerInputData;
    _ = ui.ContainerRendering;
    _ = ui.Element;
    _ = ui.ElementCallback;
    _ = ui.Font;
    _ = ui.FontCharacter;

    _ = deinit_graphics;
    _ = init_graphics;

    _ = print_stdout;

    _ = UNICODE;
}
