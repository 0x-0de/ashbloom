const std = @import("std");
const print = std.debug.print;

// Libraries.

const glfw = @import("glfw");
const vk = @import("vulkan");

const images = @import("utils/image_utils.zig");
const math = @import("utils/linalg.zig");

const vk_commands = @import("rendering/commands.zig");

// File imports (libraries that I don't use outside of the types below).

const imp_pipeline = @import("rendering/pipeline.zig");
const imp_vkcontext = @import("rendering/vkcontext.zig");
const imp_vkmemory = @import("utils/vkmemory.zig");

const imp_font = @import("utils/font.zig");

const vkui = @import("utils/vkui.zig");
const ui_basic = @import("utils/ui_themes/basic.zig");

// Types.

const CommandBuffer = vk_commands.CommandBuffer;
const VkContext = imp_vkcontext.VkContext;
const Window = @import("rendering/window.zig").Window;

const Swapchain = @import("rendering/swapchain.zig").Swapchain;

const Pipeline = imp_pipeline.Pipeline;
const PipelineVertexInput = imp_pipeline.PipelineVertexInput;
const PipelineDescriptorSet = imp_pipeline.PipelineDescriptorSet;

const RenderPass = @import("rendering/renderpass.zig").RenderPass;

const VulkanAllocator = imp_vkmemory.VulkanAllocator;

const Placement = vkui.Placement;
const ContainerInputData = vkui.ContainerInputData;

const Element = vkui.Element;
const Container = vkui.Container;

const Font = imp_font.Font;
const FontCharacter = imp_font.FontCharacter;

var debug_required_validation_layers: [1][*:0]const u8 = .{
    "VK_LAYER_KHRONOS_validation"
};

var debug_required_instance_extensions: [1][*:0]const u8 = .{
    vk.extensions.ext_debug_utils.name
};

var required_device_extensions: [1][*:0]const u8 = .{
    vk.extensions.khr_swapchain.name
};

var vertices: [28]f32 = .{
    -0.5, -0.5,    0, 0, 1,    0, 0,
    0.5, 0.5,      1, 1, 1,    1, 1,
    -0.5, 0.5,     0, 1, 1,    0, 1,
    0.5, -0.5,     0, 1, 0,    1, 0
};

var indices: [6]u16 = .{
    0, 1, 2, 0, 3, 1
};

var window: Window = undefined;

var vk_context: VkContext = undefined;
var vk_allocator: VulkanAllocator = undefined;

var vk_command_pool: vk.CommandPool = undefined;

const AppQueueNames = enum(u8)
{
    Graphics = 0,
    Presentation,
    app_queue_count
};

var vk_queues: [@intFromEnum(AppQueueNames.app_queue_count)]vk.Queue = undefined;

/// Deinitializes the Vulkan context. Should be the final step on the deinitialization process.
fn deinitialize_vulkan_context() void
{
    vk_allocator.deinit();

    vk_context.device.destroyCommandPool(vk_command_pool, null);
    vk_context.deinit();
}

/// Initializes the Vulkan context and associates it with the chosen window. Also initializes the Vulkan memory allocator, grabs the required Vulkan queues,
/// and creates a command pool for the allocator and other command buffers to use. TODO: Multiple windows with Vulkan.
fn initialize_vulkan_context(allocator: *const std.mem.Allocator) !void
{
    const vk_context_options: VkContext.InitOptions = .{
        .instance_extensions = @ptrCast(&debug_required_instance_extensions),
        .instance_layers = @ptrCast(&debug_required_validation_layers),
        .required_device_extensions = @ptrCast(&required_device_extensions),
        .required_device_features = .{
            .logic_op = .true
        }
    };

    vk_context = try VkContext.init(allocator, window.glfw_handle, vk_context_options);

    const queue_families = vk_context.physical_device_queue_families;

    vk_queues[@intFromEnum(AppQueueNames.Graphics)] = vk_context.get_queue(@truncate(queue_families.graphics_family_index.?), 0);
    vk_queues[@intFromEnum(AppQueueNames.Presentation)] = vk_context.get_queue(@truncate(queue_families.present_family_index.?), 0);

    vk_command_pool = try vk_commands.create_command_pool(&vk_context);

    vk_allocator = try VulkanAllocator.init(&vk_context, allocator, &vk_command_pool, &vk_queues[@intFromEnum(AppQueueNames.Graphics)], .{
        .page_size = 128 << 20, // 128 MB.
        .staging_size =  32 << 20 // 32 MB.
    });
}

const AppDescriptorSetNames = enum(u8)
{
    MainModel,
    UIProjection,
    app_descriptor_set_count
};

const AppPipelineNames = enum(u8)
{
    Main = 0,
    UI,
    app_pipeline_count
};

var pipelines: [@intFromEnum(AppPipelineNames.app_pipeline_count)]Pipeline = undefined;
var render_passes: [@intFromEnum(AppPipelineNames.app_pipeline_count)]RenderPass = undefined;
var pipeline_descriptor_sets: [@intFromEnum(AppDescriptorSetNames.app_descriptor_set_count)]PipelineDescriptorSet = undefined;

var app_texture: images.Texture2D = undefined;

var atlas_test_texture: [3]images.Texture2D = undefined;

var app_ui_container: Container = undefined;

fn deinitialize_render_passes() void
{
    for(&render_passes) |*rp|
    {
        rp.deinit();
    }
}

fn initialize_render_passes(swapchain: Swapchain) !void
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

    render_passes[@intFromEnum(AppPipelineNames.Main)] = try RenderPass.init(&vk_context);
    render_passes[@intFromEnum(AppPipelineNames.UI)] = try RenderPass.init(&vk_context);

    try render_passes[@intFromEnum(AppPipelineNames.Main)].add_attachment_description_no_stencil_multisample
    (swapchain.format.format, .clear, .store, .undefined, .color_attachment_optimal);
    try render_passes[@intFromEnum(AppPipelineNames.UI)].add_attachment_description_no_stencil_multisample
    (swapchain.format.format, .load, .store, .color_attachment_optimal, .present_src_khr);

    try render_passes[@intFromEnum(AppPipelineNames.Main)].add_subpass(color_subpass);
    try render_passes[@intFromEnum(AppPipelineNames.UI)].add_subpass(color_subpass);

    try render_passes[@intFromEnum(AppPipelineNames.Main)].build();
    try render_passes[@intFromEnum(AppPipelineNames.UI)].build();
}

/// Deinitializes all required pipelines.
fn deinitialize_pipelines() !void
{
    for(&pipeline_descriptor_sets) |*descriptor_set|
    {
        try descriptor_set.deinit();
    }

    for(&pipelines) |*pipeline|
    {
        pipeline.deinit();
    }
}

/// Initializes all required pipelines, and pipeline descriptor sets.
fn initialize_pipelines(allocator: *const std.mem.Allocator, swapchain: Swapchain, ui_container: *Container) !void
{
    pipelines[@intFromEnum(AppPipelineNames.Main)] = try Pipeline.init(&vk_context);
    pipelines[@intFromEnum(AppPipelineNames.UI)] = try Pipeline.init(&vk_context);

    var pvi_main = try PipelineVertexInput.init(allocator);
    defer pvi_main.deinit();

    try pvi_main.add_attribute(0, 0, vk.Format.r32g32_sfloat, 0);
    try pvi_main.add_attribute(0, 1, vk.Format.r32g32b32_sfloat, 2 * @sizeOf(f32));
    try pvi_main.add_attribute(0, 2, .r32g32_sfloat, 5 * @sizeOf(f32));

    try pvi_main.build(0, vk.VertexInputRate.vertex);

    var pvi_ui = try PipelineVertexInput.init(allocator);
    defer pvi_ui.deinit();

    try pvi_ui.add_attribute(0, 0, vk.Format.r32_sfloat, 0);
    try pvi_ui.add_attribute(0, 1, vk.Format.r32g32b32a32_sfloat, @sizeOf(u32));
    try pvi_ui.add_attribute(0, 2, vk.Format.r32g32b32a32_sfloat, @sizeOf(u32) + 4 * @sizeOf(f32));
    try pvi_ui.add_attribute(0, 3, vk.Format.r32g32b32a32_sfloat, @sizeOf(u32) + 8 * @sizeOf(f32));

    try pvi_ui.build(0, vk.VertexInputRate.instance);

    pipeline_descriptor_sets[@intFromEnum(AppDescriptorSetNames.MainModel)] =
        try PipelineDescriptorSet.init(&vk_context, &vk_allocator, @truncate(swapchain.image_count));
    
    pipeline_descriptor_sets[@intFromEnum(AppDescriptorSetNames.UIProjection)] =
        try PipelineDescriptorSet.init(&vk_context, &vk_allocator, @truncate(swapchain.image_count));

    try pipeline_descriptor_sets[@intFromEnum(AppDescriptorSetNames.MainModel)].add_binding(.{
        .binding_index = 0,
        .type = .uniform_buffer,
        .shader_stage = .{
            .vertex_bit = true
        },
        .buffer_size = 32 * @sizeOf(f32)
    });

    try pipeline_descriptor_sets[@intFromEnum(AppDescriptorSetNames.UIProjection)].add_binding(.{
        .binding_index = 0,
        .type = .uniform_buffer,
        .shader_stage = .{
            .vertex_bit = true
        },
        .buffer_size = 16 * @sizeOf(f32)
    });

    try pipeline_descriptor_sets[@intFromEnum(AppDescriptorSetNames.MainModel)].add_binding(.{
        .binding_index = 1,
        .type = .combined_image_sampler,
        .shader_stage = .{
            .fragment_bit = true
        },
        .image_sampler = app_texture.sampler.?,
        .image_layout = .shader_read_only_optimal,
        .image_view = app_texture.image_view.?
    });

    try pipeline_descriptor_sets[@intFromEnum(AppDescriptorSetNames.UIProjection)].add_binding(.{
        .binding_index = 1,
        .type = .combined_image_sampler,
        .shader_stage = .{
            .fragment_bit = true
        },
        .image_sampler = ui_container.texture_atlas.sampler,
        .image_layout = .shader_read_only_optimal,
        .image_view = ui_container.texture_atlas.image_view
    });

    try pipeline_descriptor_sets[@intFromEnum(AppDescriptorSetNames.UIProjection)].add_binding(.{
        .binding_index = 2,
        .type = .combined_image_sampler,
        .shader_stage = .{
            .fragment_bit = true
        },
        .image_sampler = ui_container.font.?.atlas.sampler,
        .image_layout = .shader_read_only_optimal,
        .image_view = ui_container.font.?.atlas.image_view
    });

    try pipeline_descriptor_sets[@intFromEnum(AppDescriptorSetNames.MainModel)].build();
    try pipeline_descriptor_sets[@intFromEnum(AppDescriptorSetNames.UIProjection)].build();

    try pipelines[@intFromEnum(AppPipelineNames.Main)].add_shader_module("./res/shaders/main_vert.spv", .{.vertex_bit = true});
    try pipelines[@intFromEnum(AppPipelineNames.Main)].add_shader_module("./res/shaders/main_frag.spv", .{.fragment_bit = true});

    try pipelines[@intFromEnum(AppPipelineNames.Main)].add_dynamic_state(vk.DynamicState.viewport);
    try pipelines[@intFromEnum(AppPipelineNames.Main)].add_dynamic_state(vk.DynamicState.scissor);

    try pipelines[@intFromEnum(AppPipelineNames.Main)].add_descriptor_set(pipeline_descriptor_sets[@intFromEnum(AppDescriptorSetNames.MainModel)]);

    try pipelines[@intFromEnum(AppPipelineNames.Main)].add_color_blend_attachment(imp_pipeline.pipeline_color_blend_attachment_no_blend());

    pipelines[@intFromEnum(AppPipelineNames.Main)].set_vertex_input(&pvi_main);

    try pipelines[@intFromEnum(AppPipelineNames.Main)].build(&render_passes[@intFromEnum(AppPipelineNames.Main)]);

    try pipelines[@intFromEnum(AppPipelineNames.UI)].add_shader_module("./res/shaders/ui_vert.spv", .{.vertex_bit = true});
    try pipelines[@intFromEnum(AppPipelineNames.UI)].add_shader_module("./res/shaders/ui_frag.spv", .{.fragment_bit = true});

    try pipelines[@intFromEnum(AppPipelineNames.UI)].add_dynamic_state(vk.DynamicState.viewport);
    try pipelines[@intFromEnum(AppPipelineNames.UI)].add_dynamic_state(vk.DynamicState.scissor);

    try pipelines[@intFromEnum(AppPipelineNames.UI)].add_descriptor_set(pipeline_descriptor_sets[@intFromEnum(AppDescriptorSetNames.UIProjection)]);

    try pipelines[@intFromEnum(AppPipelineNames.UI)].add_color_blend_attachment(imp_pipeline.pipeline_color_blend_attachment_alpha_blend());

    pipelines[@intFromEnum(AppPipelineNames.UI)].set_vertex_input(&pvi_ui);

    try pipelines[@intFromEnum(AppPipelineNames.UI)].build(&render_passes[@intFromEnum(AppPipelineNames.UI)]);
}

/// Deinitialize all texture resources.
fn deinitialize_textures() !void
{
    try app_texture.deinit();

    // try atlas_test_texture[0].deinit();
    // try atlas_test_texture[1].deinit();
    // try atlas_test_texture[2].deinit();
}

/// Initialize all texture resources.
fn initialize_textures() !void
{
    app_texture = try images.Texture2D.init(&vk_context, &vk_allocator, "res/textures/smile.bmp", .Texture);

    // atlas_test_texture[0] = try images.Texture2D.init(&vk_context, &vk_allocator, "res/textures/atlas_test_1.bmp", .Subtexture);
    // atlas_test_texture[1] = try images.Texture2D.init(&vk_context, &vk_allocator, "res/textures/atlas_test_2.bmp", .Subtexture);
    // atlas_test_texture[2] = try images.Texture2D.init(&vk_context, &vk_allocator, "res/textures/atlas_test_3.bmp", .Subtexture);
}

/// Updates the uniform matrices in the descriptor sets for the main shader.
pub fn update_main_uniforms(allocator: *const std.mem.Allocator, set_index: u16) !void
{
    var rotation = try math.mat_transform_rotation(f32, allocator, math.Vec(f32, 3).init(.{0, 0, 0}));
    var transform = try math.mat_transform(f32, allocator, rotation, math.Vec(f32, 3).init(.{100, 100, 1}), math.Vec(f32, 3).init(.{100, 100, 0}));

    rotation.deinit();

    const transform_data = try math.mat_slice_data(f32, transform);

    transform.deinit();

    try pipeline_descriptor_sets[@intFromEnum(AppDescriptorSetNames.MainModel)].place_data(set_index, 0, f32, transform_data, 0);

    allocator.free(transform_data);

    var window_width: u32 = undefined;
    var window_height: u32 = undefined;

    window.get_framebuffer_size(&window_width, &window_height);
    var projection = try math.mat_projection_orthographic(allocator, 0, @floatFromInt(window_width), 0, @floatFromInt(window_height), -1, 1);

    const projection_data = try math.mat_slice_data(f32, projection);

    projection.deinit();

    try pipeline_descriptor_sets[@intFromEnum(AppDescriptorSetNames.MainModel)].place_data(set_index, 0, f32, projection_data, 16 * @sizeOf(f32));

    allocator.free(projection_data);
}

/// Updates the uniform matrices in the descriptor sets for the UI shader.
pub fn update_ui_uniforms(allocator: *const std.mem.Allocator, set_index: u16) !void
{
    var window_width: u32 = undefined;
    var window_height: u32 = undefined;

    window.get_framebuffer_size(&window_width, &window_height);
    var projection = try math.mat_projection_orthographic(allocator, 0, @floatFromInt(window_width), 0, @floatFromInt(window_height), -1, 1);

    const projection_data = try math.mat_slice_data(f32, projection);

    projection.deinit();

    try pipeline_descriptor_sets[@intFromEnum(AppDescriptorSetNames.UIProjection)].place_data(set_index, 0, f32, projection_data, 0);

    allocator.free(projection_data);
}

pub fn main() !void
{
    try glfw.init();
    defer glfw.terminate();

    var dba: std.heap.DebugAllocator(.{}) = .{};
    defer {
        const dba_result = dba.deinit();
        if(dba_result == .leak)
        {
            print("Program terminating with {d} memory leaks.\n", .{@intFromEnum(dba_result)});
        }
    }

    const allocator = dba.allocator();

    glfw.windowHint(glfw.ClientAPI, glfw.NoAPI);

    window = try Window.init(1280, 720, "UI Test Application");
    defer window.destroy();

    try initialize_vulkan_context(&allocator);
    defer deinitialize_vulkan_context();

    var swapchain = try Swapchain.init(window.glfw_handle, &vk_context, vk_command_pool, 2);
    defer swapchain.deinit();

    try initialize_render_passes(swapchain);
    defer deinitialize_render_passes();

    try vkui.init();
    defer vkui.deinit();

    app_ui_container = try Container.init(&vk_context, &vk_allocator, .{
        .pipeline = &pipelines[@intFromEnum(AppPipelineNames.UI)],
        .descriptor_set = &pipeline_descriptor_sets[@intFromEnum(AppDescriptorSetNames.UIProjection)],
        .render_pass = &render_passes[@intFromEnum(AppPipelineNames.UI)],
        .render_queue = vk_queues[@intFromEnum(AppQueueNames.Graphics)]
    });

    var font = try Font.init(&vk_context, &vk_allocator, "res/fonts/bahnschrift.ttf", 36);
    app_ui_container.font = &font;

    try initialize_textures();
    try initialize_pipelines(&allocator, swapchain, &app_ui_container);

    var framebuffers_main = try swapchain.create_framebuffers(&render_passes[@intFromEnum(AppPipelineNames.Main)]);
    defer framebuffers_main.deinit(allocator);
    defer swapchain.deinit_framebuffers(framebuffers_main);

    var framebuffers_ui = try swapchain.create_framebuffers(&render_passes[@intFromEnum(AppPipelineNames.UI)]);
    defer framebuffers_ui.deinit(allocator);
    defer swapchain.deinit_framebuffers(framebuffers_ui);

    var vertex_buffer = try vk_allocator.alloc_buffer(f32, &vertices, .exclusive, .VertexBuffer);
    var index_buffer = try vk_allocator.alloc_buffer(u16, &indices, .exclusive, .IndexBuffer);

    const quad = try ui_basic.create_quad(&allocator, .{
        .relative_pos = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 0.5,
            .scl_y = 1
        },
        .absolute_offset = .{
            .pos_x = 20,
            .pos_y = 20,
            .scl_x = -20,
            .scl_y = -40
        },
        .alignment = .{
            .x = .Left,
            .y = .Bottom
        }
    }, .{0.2, 0.2, 0.2, 1});

    var start_text = try ui_basic.get_unicode_from_string(&allocator, "");

    const singleline_tf = try ui_basic.create_textfield(&allocator, .{
        .relative_pos = .{
            .pos_x = 0,
            .pos_y = 0.8,
            .scl_x = 0.4,
            .scl_y = 0.2
        },
        .absolute_offset = .{
            .pos_x = 20,
            .pos_y = 0,
            .scl_x = -40,
            .scl_y = -20
        },
        .alignment = .{
            .x = .Left,
            .y = .Bottom
        }
    },
    .{
        .font = &font,
        .text_size = 24,
        .initial_text = start_text.items,
        .text_alignment = .{
            .x = .Left,
            .y = .Bottom
        },
        .extension_protocol = .ScrollVertically
    });

    start_text.deinit(allocator);

    _ = try quad.add_and_dispose(singleline_tf);
    _ = try app_ui_container.add_and_dispose(quad);

    var window_width: u32 = undefined;
    var window_height: u32 = undefined;

    window.get_framebuffer_size(&window_width, &window_height);

    try app_ui_container.set_bounds(0, 0, @floatFromInt(window_width), @floatFromInt(window_height));
    try app_ui_container.build();

    var timer: f64 = glfw.getTime();
    var frames: u32 = 0;

    while(!window.should_close())
    {
        if(glfw.getTime() - timer > 1.0)
        {
            print("FPS: {d}\n", .{frames});
            frames = 0;
            timer = glfw.getTime();
        }

        const prev_window_size: vk.Extent2D = .{
            .width = @intCast(window_width),
            .height = @intCast(window_height)
        };

        glfw.pollEvents();

        const acquire_result = try swapchain.acquire_next_image();
        if(acquire_result == .NewSwapchain)
        {
            swapchain.deinit_framebuffers(framebuffers_main);
            framebuffers_main.deinit(allocator);

            swapchain.deinit_framebuffers(framebuffers_ui);
            framebuffers_ui.deinit(allocator);

            framebuffers_main = try swapchain.create_framebuffers(&render_passes[@intFromEnum(AppPipelineNames.Main)]);
            framebuffers_ui = try swapchain.create_framebuffers(&render_passes[@intFromEnum(AppPipelineNames.UI)]);
        }

        window.get_framebuffer_size(&window_width, &window_height);

        if(window_width != prev_window_size.width or window_height != prev_window_size.height)
        {
            try app_ui_container.set_bounds(0, 0, @floatFromInt(window_width), @floatFromInt(window_height));
        }

        const container_input = window.get_ui_container_input();

        try app_ui_container.update(container_input);

        if(app_ui_container.signal_reset_manual_input)
        {
            Window.reset_input_values();
            app_ui_container.signal_reset_manual_input = false;
        }

        try update_main_uniforms(&allocator, @truncate(swapchain.current_image_index));
        try update_ui_uniforms(&allocator, @truncate(swapchain.current_image_index));

        var command_buffer = try swapchain.get_next_command_buffer();
        var offset: vk.DeviceSize = 0;

        try command_buffer.reset();

        try command_buffer.begin_recording();
        command_buffer.cmd_begin_render_pass(&render_passes[@intFromEnum(AppPipelineNames.Main)], 
        framebuffers_main.items[swapchain.current_image_index], swapchain.extent, .{0, 0, 0, 1});
        command_buffer.cmd_bind_pipeline(&pipelines[@intFromEnum(AppPipelineNames.Main)]);
        command_buffer.cmd_set_viewport_scissor_full(swapchain.extent);
        command_buffer.cmd_bind_vertex_buffer(&vertex_buffer.buffer, &offset);
        command_buffer.cmd_bind_index_buffer(&index_buffer.buffer, offset);
        command_buffer.cmd_bind_descriptor_set(&pipelines[@intFromEnum(AppPipelineNames.Main)], 
        &pipeline_descriptor_sets[@intFromEnum(AppPipelineNames.Main)].sets[swapchain.current_image_index]);
        command_buffer.cmd_draw_indexed(6, 1);
        command_buffer.cmd_end_render_pass();
        try command_buffer.end_recording();

        try swapchain.render(vk_queues[@intFromEnum(AppQueueNames.Graphics)]);
        command_buffer = try swapchain.get_next_command_buffer();

        try app_ui_container.draw(command_buffer, &swapchain, framebuffers_ui.items[swapchain.current_image_index]);

        try swapchain.present(vk_queues[@intFromEnum(AppQueueNames.Presentation)]);

        frames += 1;
    }

    try vk_context.device.deviceWaitIdle();

    try font.deinit();
    try app_ui_container.deinit();

    try vk_allocator.free_buffer(index_buffer);
    try vk_allocator.free_buffer(vertex_buffer);

    try deinitialize_pipelines();
    try deinitialize_textures();

    vk_allocator.debug_print_free_space();
}

test "All unit tests."
{
    _ = @import("rendering/vkcontext.zig");
    _ = @import("rendering/commands.zig");
    _ = @import("rendering/swapchain.zig");
    _ = @import("rendering/renderpass.zig");
}
