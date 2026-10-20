const std = @import("std");
const ash = @import("ashbloom");

const glfw = ash.glfw;
const vk = ash.vk;

const VkContext = ash.rendering.VkContext;
const VkInterface = ash.rendering.VkInterface;

var allocator: std.mem.Allocator = undefined;

var window: ash.rendering.Window = undefined;

var debug_required_instance_extensions: [1][*:0]const u8 = .{
    vk.instance_extensions.ext_debug_utils.name
};

var debug_required_validation_layers: [1][*:0]const u8 = .{
    "VK_LAYER_KHRONOS_validation"
};

var required_device_extensions: [4][*:0]const u8 = .{
    vk.device_extensions.khr_swapchain.name,
    vk.device_extensions.khr_create_renderpass_2.name,
    vk.device_extensions.khr_depth_stencil_resolve.name,
    vk.device_extensions.khr_dynamic_rendering.name
};

var vk_context: VkContext = undefined;
var vk_interface: VkInterface = undefined;

var cmd_pool_graphics: vk.CommandPool = undefined;

var vk_allocator: ash.utils.VulkanAllocator = undefined;

const AppQueues = enum
{
    Graphics,
    Presentation
};

var vk_queues: std.EnumArray(AppQueues, vk.Queue) = .initUndefined();

fn deinit_vk_interface() void
{
    vk_allocator.deinit();

    vk_interface.device.destroyCommandPool(cmd_pool_graphics, null);

    vk_interface.deinit();
    vk_context.deinit();
}

fn init_vk_interface() !void
{
    const vk_context_opts: VkContext.InitOptions = .{
        .instance_extensions = &debug_required_instance_extensions,
        .instance_layers = &debug_required_validation_layers
    };

    vk_context = try .init(&allocator, vk_context_opts);

    var dynamic_rendering: vk.PhysicalDeviceDynamicRenderingFeaturesKHR = .{
        .dynamic_rendering = .true
    };

    const vk_interface_opts: VkInterface.InitOptions = .{
        .device_layers = &debug_required_validation_layers,
        .required_device_extensions = &required_device_extensions,
        .required_device_features = .{},
        .extensions = @ptrCast(&dynamic_rendering)
    };

    vk_interface = try .init(&vk_context, &window, vk_interface_opts);

    const queue_families = vk_interface.physical_device_queue_families.?;

    cmd_pool_graphics = try ash.rendering.commands.create_command_pool(&vk_interface, @truncate(queue_families.graphics_family_index.?));

    vk_queues.set(.Graphics, vk_interface.device.getDeviceQueue(@truncate(queue_families.graphics_family_index.?), 0));
    vk_queues.set(.Presentation, vk_interface.device.getDeviceQueue(@truncate(queue_families.present_family_index.?), 0));

    vk_allocator = try .init(&vk_interface, &allocator, .{
        .transfer_command_pool = &cmd_pool_graphics,
        .transfer_queue = vk_queues.getPtr(.Graphics),
        .page_size = 128 << 20,
        .staging_size = 32 << 20
    });
}

var swapchain: ash.rendering.Swapchain = undefined;

fn deinit_swapchain() void
{
    swapchain.deinit(true);
}

fn init_swapchain() !void
{
    swapchain = try .init(&window, &vk_interface, &vk_allocator, vk_interface.surfaces.items[0], cmd_pool_graphics, 1);
}

var pipeline: ash.rendering.Pipeline = undefined;

fn deinit_pipeline() void
{
    pipeline.deinit();
}

fn init_pipeline() !void
{
    pipeline = try .init(&vk_interface);

    try pipeline.add_shader_module("../../res/shaders/main_vert.spv", .{ .vertex = true });
    try pipeline.add_shader_module("../../res/shaders/main_frag.spv", .{ .fragment = true });

    try pipeline.add_color_blend_attachment(ash.rendering.pipeline.pipeline_color_blend_attachment_no_blend());

    try pipeline.add_dynamic_state(.viewport);
    try pipeline.add_dynamic_state(.scissor);

    const attachment_format: vk.Format = swapchain.format.format;

    const info_pipeline_rendering: vk.PipelineRenderingCreateInfoKHR = .{
        .color_attachment_count = 1,
        .p_color_attachment_formats = @ptrCast(&attachment_format),
        .depth_attachment_format = .undefined,
        .stencil_attachment_format = .undefined,
        .view_mask = 0
    };

    try pipeline.build(.{ .Dynamic = info_pipeline_rendering });
}

pub fn main() !void
{
    var dbg_alloc: std.heap.DebugAllocator(.{}) = .init;
    defer
    {
        const status = dbg_alloc.deinit();
        if(status != .ok)
        {
            @panic("Program terminating with memory leaks!");
        }
    }

    allocator = dbg_alloc.allocator();

    try ash.init_graphics(&allocator);
    defer ash.deinit_graphics();

    window = try .init(1280, 720, "Dynamic rendering test");

    try init_vk_interface();
    defer deinit_vk_interface();

    try init_swapchain();
    defer deinit_swapchain();

    try init_pipeline();
    defer deinit_pipeline();

    while(!window.should_close())
    {
        glfw.pollEvents();

        const swapchain_result = try swapchain.acquire_next_image();

        switch(swapchain_result)
        {
            .NoIssue => {},
            .Failure => { @panic("Failed to acquire swapchain image."); },
            .NewSwapchain => {}
        }

        // Raw rendering image barrier.

        const render_image_barrier: vk.ImageMemoryBarrier = .{
            .image = swapchain.images[swapchain.current_image_index],
            .old_layout = .undefined,
            .new_layout = .color_attachment_optimal,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .subresource_range = .{
                .aspect_mask = .{
                    .color = true
                },
                .base_array_layer = 0,
                .base_mip_level = 0,
                .layer_count = 1,
                .level_count = 1
            },
            .src_access_mask = .{
                .color_attachment_read = true
            },
            .dst_access_mask = .{
                .color_attachment_write = true
            }
        };

        const render_src_stage_mask: vk.PipelineStageFlags = .{
            .fragment_shader = true
        };

        const render_dst_stage_mask: vk.PipelineStageFlags = .{
            .color_attachment_output = true
        };

        _ = render_image_barrier;

        _ = render_src_stage_mask;
        _ = render_dst_stage_mask;

        const render_barrier: ash.rendering.commands.PipelineBarrier = .{
            .barrier = .{ .Image = .{
                .image = swapchain.images[swapchain.current_image_index],
                .old_layout = .undefined,
                .new_layout = .color_attachment_optimal,
                .subresource_range = .{
                    .aspect_mask = .{
                        .color = true
                    },
                    .base_array_layer = 0,
                    .base_mip_level = 0,
                    .layer_count = 1,
                    .level_count = 1
                },
                .accesses = .{
                    .src_access_mask = .{
                        .color_attachment_read = true
                    },
                    .dst_access_mask = .{
                        .color_attachment_write = true
                    }
                }
            }},
            .src_stage_mask = .{
                .fragment_shader = true
            },
            .dst_stage_mask = .{
                .color_attachment_output = true
            }
        };

        // Raw presentation image barrier.

        const present_image_barrier: vk.ImageMemoryBarrier = .{
            .image = swapchain.images[swapchain.current_image_index],
            .old_layout = .color_attachment_optimal,
            .new_layout = .present_src_khr,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .subresource_range = .{
                .aspect_mask = .{
                    .color = true
                },
                .base_array_layer = 0,
                .base_mip_level = 0,
                .layer_count = 1,
                .level_count = 1
            },
            .src_access_mask = .{
                .color_attachment_read = true
            },
            .dst_access_mask = .{
                .color_attachment_write = true
            }
        };

        const present_src_stage_mask: vk.PipelineStageFlags = .{
            .color_attachment_output = true
        };

        const present_dst_stage_mask: vk.PipelineStageFlags = .{
            .color_attachment_output = true
        };

        _ = present_image_barrier;

        _ = present_src_stage_mask;
        _ = present_dst_stage_mask;
        
        const present_barrier: ash.rendering.commands.PipelineBarrier = .{
            .barrier = .{ .Image = .{
                .image = swapchain.images[swapchain.current_image_index],
                .old_layout = .color_attachment_optimal,
                .new_layout = .present_src_khr,
                .subresource_range = .{
                    .aspect_mask = .{
                        .color = true
                    },
                    .base_array_layer = 0,
                    .base_mip_level = 0,
                    .layer_count = 1,
                    .level_count = 1
                },
                .accesses = .{
                    .src_access_mask = .{
                        .color_attachment_read = true
                    },
                    .dst_access_mask = .{
                        .color_attachment_write = true
                    }
                }
            }},
            .src_stage_mask = .{
                .color_attachment_output = true
            },
            .dst_stage_mask = .{
                .color_attachment_output = true
            }
        };

        const render_attachment: vk.RenderingAttachmentInfoKHR = .{
            .image_view = swapchain.image_views.items[swapchain.current_image_index],
            .clear_value = .{
                .color = .{
                    .float_32 = .{0.02, 0.03, 0.1, 1}
                }
            },
            .image_layout = .color_attachment_optimal,
            .load_op = .clear,
            .store_op = .store,
            .resolve_mode = .{},
            .resolve_image_layout = .undefined
        };

        const render_info: vk.RenderingInfoKHR = .{
            .color_attachment_count = 1,
            .layer_count = 1,
            .p_color_attachments = @ptrCast(&render_attachment),
            .view_mask = 0,
            .render_area = .{
                .offset = .{
                    .x = 0,
                    .y = 0
                },
                .extent = swapchain.extent
            }
        };

        const command_buffer = try swapchain.get_next_command_buffer();

        try command_buffer.reset();
        try command_buffer.begin_recording();
        // command_buffer.proxy.pipelineBarrier(render_src_stage_mask, render_dst_stage_mask, .{}, null, null, &.{ render_image_barrier });
        command_buffer.pipeline_barrier(render_barrier, .{});
        // command_buffer.proxy.pipelineBarrier(present_src_stage_mask, present_dst_stage_mask, .{}, null, null, &.{ present_image_barrier });
        command_buffer.pipeline_barrier(present_barrier, .{});
        command_buffer.proxy.beginRenderingKHR(&render_info);
        command_buffer.bind_pipeline(.graphics, &pipeline);
        command_buffer.set_viewport_scissor_full(swapchain.extent);
        command_buffer.draw(3, 1);
        command_buffer.proxy.endRenderingKHR();
        try command_buffer.end_recording();

        try swapchain.render(vk_queues.get(.Graphics));

        try swapchain.present(vk_queues.get(.Presentation));
    }
    
    try vk_interface.device.deviceWaitIdle();
}
