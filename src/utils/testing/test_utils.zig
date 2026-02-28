//! This file contains several functions used in the unit tests for this library.
const std = @import("std");
const print = std.debug.print;

const glfw = @import("glfw");
const vk = @import("vulkan");

const Window = @import("../../rendering/window.zig").Window;

const VkContext = @import("../../rendering/vkcontext.zig").VkContext;
const RenderPass = @import("../../rendering/renderpass.zig").RenderPass;
const Swapchain = @import("../../rendering/swapchain.zig").Swapchain;

/// Creates a default debug allocator, the chosen allocator for this library's unit tests.
pub fn init_testing_allocator() std.heap.DebugAllocator(.{})
{
    return .{};
}

/// Deinitializes the testing allocator.
pub fn deinit_testing_allocator(dba: *std.heap.DebugAllocator(.{})) void
{
    const dba_result = dba.deinit();
    if(dba_result == .leak)
    {
        print("Program terminating with {d} memory leaks.\n", .{@intFromEnum(dba_result)});
    }
}

/// Creates a simple window used for testing.
pub fn create_testing_window() !Window
{
    glfw.windowHint(glfw.ClientAPI, glfw.NoAPI);

    const window = try Window.init(1280, 720, "TEST");
    return window;
}

// Standard Vulkan validation layers.
var testing_basic_validation_layers: [1][*:0]const u8 = .{
    "VK_LAYER_KHRONOS_validation"
};

// Standard validation layer extension.
var testing_basic_instance_extensions: [1][*:0]const u8 = .{
    vk.extensions.ext_debug_utils.name
};

// Swapchain extension. Not technically required but greatly helpful and recommended (used in the swapchain.zig module).
var testing_basic_device_extensions: [1][*:0]const u8 = .{
    vk.extensions.khr_swapchain.name
};

/// Creates a VkContext object with some basic extensions, validation layers, and even device features, used for testing.
pub fn create_testing_vk_context(allocator: *const std.mem.Allocator, window: *Window) !VkContext
{
    const vk_context_options: VkContext.InitOptions = .{
        .instance_extensions = @ptrCast(&testing_basic_instance_extensions),
        .instance_layers = @ptrCast(&testing_basic_validation_layers),
        .required_device_extensions = @ptrCast(&testing_basic_device_extensions),
        .required_device_features = .{
            .logic_op = .true // I use logic op for color blending.
        }
    };

    const vk_context = try VkContext.init(allocator, window.glfw_handle, vk_context_options);
    return vk_context;
}

/// Creates a simple color render pass for testing.
pub fn create_testing_color_render_pass(vk_context: *VkContext, swapchain: Swapchain) !RenderPass
{
    const color_subpass: RenderPass.Subpass = .{
        .attachment_index = 0,
        .attachment_layout = .color_attachment_optimal,
        .subpass_bind_point = .graphics,
        .subpass_dependency = .{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = undefined,
            .src_access_mask = .{},
            .src_stage_mask = .{
                .color_attachment_output_bit = true
            },
            .dst_access_mask = .{
                .color_attachment_write_bit = true
            },
            .dst_stage_mask = .{
                .color_attachment_output_bit = true
            }
        }
    };

    var rp = try RenderPass.init(vk_context);
    try rp.add_attachment_description_no_stencil_multisample(swapchain.format.format, .clear, .store, .undefined, .color_attachment_optimal);
    try rp.add_subpass(color_subpass);
    try rp.build();

    return rp;
}
