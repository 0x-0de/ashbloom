const std = @import("std");
const ash = @import("ashbloom");

const glfw = ash.glfw;
const vk = ash.vk;

const Window = ash.ABWindow;

const VkContext = ash.VkContext;
const VulkanAllocator = ash.VulkanAllocator;

const Swapchain = ash.Swapchain;

const TICKS_PER_SECOND = 60.0;
const TICK_RATE = 1.0 / TICKS_PER_SECOND;

var allocator: std.mem.Allocator = undefined;

var debug_required_validation_layers: [1][*:0]const u8 = .{
    "VK_LAYER_KHRONOS_validation"
};

var debug_required_instance_extensions: [1][*:0]const u8 = .{
    vk.extensions.ext_debug_utils.name
};

var required_device_extensions: [1][*:0]const u8 = .{
    vk.extensions.khr_swapchain.name
};

var window: Window = undefined;

var vk_context: VkContext = undefined;
var vk_allocator: VulkanAllocator = undefined;

const AppQueues = enum(u8)
{
    Graphics,
    Presentation,
};

var vk_queues: std.EnumArray(AppQueues, vk.Queue) = .initUndefined();

var vk_command_pool: vk.CommandPool = undefined;

fn init_vk_context() !void
{
    const vk_context_options: VkContext.InitOptions = .{
        .instance_extensions = @ptrCast(&debug_required_instance_extensions),
        .instance_layers = @ptrCast(&debug_required_validation_layers),
        .required_device_extensions = @ptrCast(&required_device_extensions),
        .required_device_features = .{
            .logic_op = .true
        }
    };

    vk_context = try .init(&allocator, &window, vk_context_options);

    const queue_families = vk_context.physical_device_queue_families;

    vk_queues.set(.Graphics, vk_context.get_queue(queue_families.graphics_family_index.?, 0));
    vk_queues.set(.Presentation, vk_context.get_queue(queue_families.present_family_index.?, 0));

    vk_command_pool = try ash.commands.create_command_pool(&vk_context, @truncate(queue_families.graphics_family_index.?));

    vk_allocator = try .init(&vk_context, &allocator, .{
        .transfer_command_pool = &vk_command_pool,
        .transfer_queue = vk_queues.getPtr(.Graphics),
        .page_size = 128 << 20, // 128 MB.
        .staging_size = 32 << 20 // 32 MB.
    });
}

fn deinit_vk_context() void
{
    vk_allocator.deinit();

    vk_context.device.destroyCommandPool(vk_command_pool, null);
    vk_context.deinit();
}

var swapchain: ash.Swapchain = undefined;

fn init_swapchain() !void
{
    swapchain = try .init(&window, &vk_context, &vk_allocator, vk_command_pool, 1);

    const info_depth_buffer: vk.ImageCreateInfo = .{
        .image_type = .@"2d",
        .extent = undefined,
        .mip_levels = 1,
        .array_layers = 1,
        .format = try ash.vk_utils.choose_best_depth_buffer_format(&vk_context),
        .tiling = .optimal,
        .initial_layout = .undefined,
        .usage = .{ .depth_stencil_attachment_bit = true },
        .sharing_mode = .exclusive,
        .samples = .{ .@"1_bit" = true }
    };

    const info_depth_image_view: vk.ImageViewCreateInfo = .{
        .image = undefined,
        .format = try ash.vk_utils.choose_best_depth_buffer_format(&vk_context),
        .components = .{
            .r = .identity,
            .g = .identity,
            .b = .identity,
            .a = .identity
        },
        .subresource_range = .{
            .aspect_mask = .{ .depth_bit = true },
            .base_array_layer = 0,
            .base_mip_level = 0,
            .layer_count = 1,
            .level_count = 1
        },
        .view_type = .@"2d"
    };

    try swapchain.add_attachment(.{
        .info_image = info_depth_buffer,
        .info_image_view = info_depth_image_view,
        .image_usage = .DepthAttachment
    });
}

fn deinit_swapchain() void
{
    swapchain.deinit(true);
}

const Attachments = enum(u8)
{
    SelectionBuffer
};

var attachments: std.EnumArray(Attachments, ash.AttachmentBundle) = .initUndefined();

fn init_attachments() !void
{
    const att_selection_buffer = attachments.getPtr(.SelectionBuffer);
    att_selection_buffer.* = try .init(&allocator, &vk_context, &vk_allocator);

    const selection_buffer_create_info: vk.ImageCreateInfo = .{
        .image_type = .@"2d",
        .format = .r32g32b32a32_uint,
        .extent = undefined,
        .mip_levels = 1,
        .array_layers = 1,
        .tiling = .optimal,
        .usage = .{ .transfer_src_bit = true, .color_attachment_bit = true },
        .sharing_mode = .exclusive,
        .samples = .{ .@"1_bit" = true },
        .initial_layout = .undefined
    };

    const selection_buffer_view_create_info: vk.ImageViewCreateInfo = .{
        .image = undefined,
        .view_type = .@"2d",
        .format = selection_buffer_create_info.format,
        .components = .{
            .r = .identity,
            .g = .identity,
            .b = .identity,
            .a = .identity
        },
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_array_layer = 0,
            .base_mip_level = 0,
            .layer_count = 1,
            .level_count = 1
        }
    };

    try att_selection_buffer.add_attachment(.{
        .info_image = selection_buffer_create_info,
        .info_image_view = selection_buffer_view_create_info,
        .image_usage = .GenericAttachment
    });

    const info_depth_buffer: vk.ImageCreateInfo = .{
        .image_type = .@"2d",
        .extent = undefined,
        .mip_levels = 1,
        .array_layers = 1,
        .format = try ash.vk_utils.choose_best_depth_buffer_format(&vk_context),
        .tiling = .optimal,
        .initial_layout = .undefined,
        .usage = .{ .depth_stencil_attachment_bit = true },
        .sharing_mode = .exclusive,
        .samples = .{ .@"1_bit" = true }
    };

    const info_depth_image_view: vk.ImageViewCreateInfo = .{
        .image = undefined,
        .format = try ash.vk_utils.choose_best_depth_buffer_format(&vk_context),
        .components = .{
            .r = .identity,
            .g = .identity,
            .b = .identity,
            .a = .identity
        },
        .subresource_range = .{
            .aspect_mask = .{ .depth_bit = true },
            .base_array_layer = 0,
            .base_mip_level = 0,
            .layer_count = 1,
            .level_count = 1
        },
        .view_type = .@"2d"
    };

    try att_selection_buffer.add_attachment(.{
        .info_image = info_depth_buffer,
        .info_image_view = info_depth_image_view,
        .image_usage = .DepthAttachment
    });

    try att_selection_buffer.build(.{
        .width = swapchain.extent.width,
        .height = swapchain.extent.height,
        .depth = 1
    });
}

fn deinit_attachments() void
{
    const att_selection_buffer = attachments.getPtr(.SelectionBuffer);

    att_selection_buffer.deinit();
}

const RenderPasses = enum(u8)
{
    DebugGeometry,
    Selection
};

var render_passes: std.EnumArray(RenderPasses, ash.RenderPass) = .initUndefined();

fn init_render_passes() !void
{
    const depth_format = try ash.vk_utils.choose_best_depth_buffer_format(&vk_context);

    const sp_color_depth: ash.RenderPass.Subpass = .{
        .color_attachment_index = 0,
        .depth_stencil_attachment_index = 1,
        .color_attachment_layout = .color_attachment_optimal,
        .depth_stencil_attachment_layout = .depth_stencil_attachment_optimal,
        .subpass_bind_point = .graphics,
        .subpass_dependency = .{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = undefined,
            .src_access_mask = .{ .depth_stencil_attachment_write_bit = true },
            .dst_access_mask = .{ .color_attachment_write_bit = true, .depth_stencil_attachment_write_bit = true },
            .src_stage_mask = .{ .color_attachment_output_bit = true, .late_fragment_tests_bit = true },
            .dst_stage_mask = .{ .color_attachment_output_bit = true, .early_fragment_tests_bit = true }
        }
    };

    const sp_color_depth_selection: ash.RenderPass.Subpass = .{
        .color_attachment_index = 0,
        .depth_stencil_attachment_index = 1,
        .color_attachment_layout = .color_attachment_optimal,
        .depth_stencil_attachment_layout = .depth_stencil_attachment_optimal,
        .subpass_bind_point = .graphics,
        .subpass_dependency = .{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = undefined,
            .src_access_mask = .{ .depth_stencil_attachment_write_bit = true },
            .dst_access_mask = .{ .color_attachment_write_bit = true, .depth_stencil_attachment_write_bit = true },
            .src_stage_mask = .{ .color_attachment_output_bit = true, .late_fragment_tests_bit = true },
            .dst_stage_mask = .{ .color_attachment_output_bit = true, .early_fragment_tests_bit = true }
        }
    };

    const p_debug_geometry = render_passes.getPtr(.DebugGeometry);

    p_debug_geometry.* = try .init(&vk_context);

    // Color attachment.
    try p_debug_geometry.add_attachment_description_no_stencil_multisample(swapchain.format.format, .clear, .store, .undefined, .present_src_khr);
    // Depth attachment.
    try p_debug_geometry.add_attachment_description_no_stencil_multisample(depth_format, .clear, .dont_care, .undefined, .depth_stencil_attachment_optimal);

    try p_debug_geometry.add_subpass(sp_color_depth);
    try p_debug_geometry.build();

    const p_selection = render_passes.getPtr(.Selection);

    p_selection.* = try .init(&vk_context);

    try p_selection.add_attachment_description_no_stencil_multisample(.r32g32b32a32_uint, .clear, .store, .undefined, .transfer_src_optimal);
    try p_selection.add_attachment_description_no_stencil_multisample(depth_format, .clear, .dont_care, .undefined, .depth_stencil_attachment_optimal);

    try p_selection.add_subpass(sp_color_depth_selection);
    try p_selection.build();
}

fn deinit_render_passes() void
{
    render_passes.getPtr(.DebugGeometry).deinit();
    render_passes.getPtr(.Selection).deinit();
}

const PipelineDescriptorSets = enum(u8)
{
    DebugGeometryModelView,
    ModelView
};

const Pipelines = enum(u8)
{
    DebugGeometry,
    Main,
    SelectionDisplay,
    Selection
};

var pipeline_descriptor_sets: std.EnumArray(PipelineDescriptorSets, ash.PipelineDescriptorSet) = .initUndefined();
var pipeline_vertex_inputs: std.EnumArray(Pipelines, ash.PipelineVertexInput) = .initUndefined();
var pipelines: std.EnumArray(Pipelines, ash.Pipeline) = .initUndefined();

fn init_graphics_pipeline_vertex_inputs() !void
{
    // Debug geometry.
    var pvi_debug_geometry = pipeline_vertex_inputs.getPtr(.DebugGeometry); 

    pvi_debug_geometry.* = try .init(&allocator);

    try pvi_debug_geometry.add_attribute(0, 0, .r32g32b32_sfloat, 0);
    try pvi_debug_geometry.build(0, .vertex);

    // Main.
    var pvi_main = pipeline_vertex_inputs.getPtr(.Main);

    pvi_main.* = try .init(&allocator);

    try pvi_main.add_attribute(0, 0, .r32g32b32_sfloat, 0);
    try pvi_main.add_attribute(0, 1, .r32_uint, 3 * @sizeOf(f32));
    try pvi_main.build(0, .vertex);

    // Selection display.
    var pvi_selection_display = pipeline_vertex_inputs.getPtr(.SelectionDisplay);

    pvi_selection_display.* = try .init(&allocator);

    try pvi_selection_display.add_attribute(0, 0, .r32g32b32_sfloat, 0);
    try pvi_selection_display.add_attribute(0, 1, .r32_uint, 3 * @sizeOf(f32));
    try pvi_selection_display.build(0, .vertex);

    // Selection.
    var pvi_selection = pipeline_vertex_inputs.getPtr(.Selection);

    pvi_selection.* = try .init(&allocator);

    try pvi_selection.add_attribute(0, 0, .r32g32b32_sfloat, 0);
    try pvi_selection.add_attribute(0, 1, .r32_uint, 3 * @sizeOf(f32));
    try pvi_selection.build(0, .vertex);
}

fn init_graphics_pipeline_descriptor_sets() !void
{
    // Debug geometry model view.
    const pds_debug_geometry = pipeline_descriptor_sets.getPtr(.DebugGeometryModelView);

    pds_debug_geometry.* = try .init(&vk_context, &vk_allocator, @truncate(swapchain.image_count));

    try pds_debug_geometry.add_binding(.{
        .binding_index = 0,
        .shader_stage = .{ .vertex_bit = true },
        .type = .uniform_buffer,
        .buffer_size = 32 * @sizeOf(f32)
    });

    try pds_debug_geometry.build();

    // Model view.
    const pds_main = pipeline_descriptor_sets.getPtr(.ModelView);

    pds_main.* = try .init(&vk_context, &vk_allocator, @truncate(swapchain.image_count));

    try pds_main.add_binding(.{
        .binding_index = 0,
        .shader_stage = .{ .vertex_bit = true },
        .type = .uniform_buffer,
        .buffer_size = 32 * @sizeOf(f32)
    });

    try pds_main.build();
}

fn init_graphics_pipelines() !void
{
    try init_graphics_pipeline_vertex_inputs();
    try init_graphics_pipeline_descriptor_sets();
   
    // Debug geometry.
    const p_debug_geometry = pipelines.getPtr(.DebugGeometry);

    p_debug_geometry.* = try .init(&vk_context);

    try p_debug_geometry.add_dynamic_state(.viewport);
    try p_debug_geometry.add_dynamic_state(.scissor);

    try p_debug_geometry.add_descriptor_set(pipeline_descriptor_sets.get(.DebugGeometryModelView));

    try p_debug_geometry.add_shader_module("../res/shaders/debug/geometry_vert.spv", .{.vertex_bit = true});
    try p_debug_geometry.add_shader_module("../res/shaders/debug/geometry_frag.spv", .{.fragment_bit = true});

    try p_debug_geometry.add_color_blend_attachment(ash.pipeline.pipeline_color_blend_attachment_alpha_blend());

    p_debug_geometry.set_vertex_input(pipeline_vertex_inputs.getPtr(.DebugGeometry));

    p_debug_geometry.info_depth_stencil_testing = ash.pipeline.pipeline_depth_stencil_state_default();

    try p_debug_geometry.build(render_passes.getPtr(.DebugGeometry));

    // Main.
    const p_main = pipelines.getPtr(.Main);

    p_main.* = try .init(&vk_context);

    try p_main.add_dynamic_state(.viewport);
    try p_main.add_dynamic_state(.scissor);

    try p_main.add_descriptor_set(pipeline_descriptor_sets.get(.ModelView));

    try p_main.add_shader_module("../res/shaders/main_vert.spv", .{.vertex_bit = true});
    try p_main.add_shader_module("../res/shaders/main_frag.spv", .{.fragment_bit = true});

    try p_main.add_color_blend_attachment(ash.pipeline.pipeline_color_blend_attachment_alpha_blend());

    p_main.set_vertex_input(pipeline_vertex_inputs.getPtr(.Main));

    p_main.info_depth_stencil_testing = ash.pipeline.pipeline_depth_stencil_state_default();

    try p_main.build(render_passes.getPtr(.DebugGeometry));

    // Selection display.
    const p_selection_display = pipelines.getPtr(.SelectionDisplay);

    p_selection_display.* = try .init(&vk_context);

    try p_selection_display.add_dynamic_state(.viewport);
    try p_selection_display.add_dynamic_state(.scissor);

    try p_selection_display.add_descriptor_set(pipeline_descriptor_sets.get(.ModelView));

    try p_selection_display.add_shader_module("../res/shaders/debug/selection_vert.spv", .{.vertex_bit = true});
    try p_selection_display.add_shader_module("../res/shaders/debug/selection_frag.spv", .{.fragment_bit = true});

    try p_selection_display.add_color_blend_attachment(ash.pipeline.pipeline_color_blend_attachment_no_blend());

    p_selection_display.set_vertex_input(pipeline_vertex_inputs.getPtr(.SelectionDisplay));

    p_selection_display.info_depth_stencil_testing = ash.pipeline.pipeline_depth_stencil_state_default();

    try p_selection_display.build(render_passes.getPtr(.DebugGeometry));

    // Selection.
    const p_selection = pipelines.getPtr(.Selection);

    p_selection.* = try .init(&vk_context);

    try p_selection.add_dynamic_state(.viewport);
    try p_selection.add_dynamic_state(.scissor);

    try p_selection.add_descriptor_set(pipeline_descriptor_sets.get(.ModelView));

    try p_selection.add_shader_module("../res/shaders/selection_vert.spv", .{.vertex_bit = true});
    try p_selection.add_shader_module("../res/shaders/selection_frag.spv", .{.fragment_bit = true});

    try p_selection.add_color_blend_attachment(ash.pipeline.pipeline_color_blend_attachment_no_blend());

    p_selection.set_vertex_input(pipeline_vertex_inputs.getPtr(.Selection));

    p_selection.info_depth_stencil_testing = ash.pipeline.pipeline_depth_stencil_state_default();

    try p_selection.build(render_passes.getPtr(.Selection));
}

fn deinit_graphics_pipelines() void
{
    pipelines.getPtr(.DebugGeometry).deinit();
    pipelines.getPtr(.Main).deinit();
    pipelines.getPtr(.SelectionDisplay).deinit();
    pipelines.getPtr(.Selection).deinit();

    pipeline_vertex_inputs.getPtr(.DebugGeometry).deinit();
    pipeline_vertex_inputs.getPtr(.Main).deinit();
    pipeline_vertex_inputs.getPtr(.SelectionDisplay).deinit();
    pipeline_vertex_inputs.getPtr(.Selection).deinit();

    pipeline_descriptor_sets.getPtr(.DebugGeometryModelView).deinit();
    pipeline_descriptor_sets.getPtr(.ModelView).deinit();
}

fn get_tick_count(time_start_frame: *f64, tick_timer: *f64) usize
{
    const time_of_last_frame = ash.glfw.getTime() - time_start_frame.*;
    time_start_frame.* = ash.glfw.getTime();

    tick_timer.* += time_of_last_frame;
    var ticks: usize = 0;

    while(tick_timer.* >= TICK_RATE)
    {
        tick_timer.* -= TICK_RATE;
        ticks += 1;
    }

    return ticks;
}

const Camera = @import("utils/camera.zig").Camera;

var camera: Camera = undefined;

fn update_shader_uniforms() !void
{
    const pds_debug_geometry = pipeline_descriptor_sets.getPtr(.DebugGeometryModelView);
    const pds_main = pipeline_descriptor_sets.getPtr(.ModelView);

    const fov = 70.0 * std.math.pi / 180.0;
    
    const width: u32 = swapchain.extent.width;
    const height: u32 = swapchain.extent.height;

    const aspect: f32 = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));

    var projection = try ash.linalg.mat_projection_perspective(&allocator, fov, aspect, 0.01, 1000.0);
    const projection_data = try ash.linalg.mat_slice_data(f32, projection);
    projection.deinit();

    try pds_debug_geometry.place_data(@truncate(swapchain.current_image_index), 0, f32, projection_data, 0);
    try pds_main.place_data(@truncate(swapchain.current_image_index), 0, f32, projection_data, 0);

    allocator.free(projection_data);

    var view = try ash.linalg.mat_look_at(&allocator, camera.pos, camera.rot);
    const view_data = try ash.linalg.mat_slice_data(f32, view);
    view.deinit();

    try pds_debug_geometry.place_data(@truncate(swapchain.current_image_index), 0, f32, view_data, 16 * @sizeOf(f32));
    try pds_main.place_data(@truncate(swapchain.current_image_index), 0, f32, view_data, 16 * @sizeOf(f32));
    
    allocator.free(view_data);
}

const imp_chunk = @import("world/chunk.zig");
const Chunk = imp_chunk.Chunk;

var input_mode: u8 = 0;

fn update_main_input(draw_pipeline: *Pipelines) void
{
    if(input_mode != 0)
    {
        if(glfw.getKey(window.glfw_handle, glfw.KeyLeftAlt) == glfw.Press)
        {
            input_mode = 2;
        }
        else if(glfw.getKey(window.glfw_handle, glfw.KeyLeftAlt) == glfw.Release)
        {
            input_mode = 1;
        }
    }
    
    if(window.get_mouse_button(glfw.MouseButton1) == glfw.Press and input_mode != 2)
    {
        input_mode = 1;
    }
    if(glfw.getKey(window.glfw_handle, glfw.KeyEscape) == glfw.Press)
    {
        input_mode = 0;
    }

    switch(input_mode)
    {
        0, 2 => {
            glfw.setInputMode(window.glfw_handle, glfw.Cursor, glfw.CursorNormal);
        },
        1 => {
            glfw.setInputMode(window.glfw_handle, glfw.Cursor, glfw.CursorDisabled);
        },
        else => {}
    }

    if(glfw.getKey(window.glfw_handle, glfw.KeyF1) == glfw.Press)
    {
        draw_pipeline.* = .Main;
    }
    else if(glfw.getKey(window.glfw_handle, glfw.KeyF2) == glfw.Press)
    {
        draw_pipeline.* = .DebugGeometry;
    }
    else if(glfw.getKey(window.glfw_handle, glfw.KeyF3) == glfw.Press)
    {
        draw_pipeline.* = .SelectionDisplay;
    }
}

pub fn main() !void
{   
    var dba: std.heap.DebugAllocator(.{}) = .{};
    defer {
        const dba_result = dba.deinit();
        if(dba_result == .leak)
        {
            std.debug.print("Program terminating with {d} memory leaks.\n", .{@intFromEnum(dba_result)});
        }
    }

    allocator = dba.allocator();

    try ash.init_graphics(&allocator);
    defer ash.deinit_graphics();

    window = try .init(1280, 720, "Voxel demo");
    defer window.destroy();

    try init_vk_context();
    defer deinit_vk_context();

    try init_swapchain();
    defer deinit_swapchain();

    try init_attachments();
    defer deinit_attachments();

    try init_render_passes();
    defer deinit_render_passes();

    try init_graphics_pipelines();
    defer deinit_graphics_pipelines();

    var framebuffers = try swapchain.create_framebuffers(render_passes.getPtr(.DebugGeometry));
    defer
    {
        swapchain.deinit_framebuffers(framebuffers);
        framebuffers.deinit(allocator);
    }

    const selection_buffer = attachments.getPtr(.SelectionBuffer);
    var selection_buffer_attachments: []const vk.ImageView = &.{selection_buffer.attachments.items[0].image_view.?, selection_buffer.attachments.items[1].image_view.?};

    var selection_framebuffer_info: vk.FramebufferCreateInfo = .{
        .render_pass = render_passes.get(.Selection).render_pass,
        .attachment_count = 2,
        .p_attachments = @ptrCast(selection_buffer_attachments),
        .width = swapchain.extent.width,
        .height = swapchain.extent.height,
        .layers = 1
    };

    var selection_framebuffer = try vk_context.device.createFramebuffer(&selection_framebuffer_info, null);
    defer vk_context.device.destroyFramebuffer(selection_framebuffer, null);

    camera = .init();
    camera.pos = .init(.{0, 0, -3});

    var frames: usize = 0;
    
    var fps_timer: f64 = ash.glfw.getTime();
    var tick_timer: f64 = 0;

    var time_start_frame = ash.glfw.getTime();

    const cv_color: vk.ClearValue = .{
        .color = .{
            .float_32 = .{0, 0, 0, 1}
        }
    };

    const cv_selection_color: vk.ClearValue = .{
        .color = .{
            .float_32 = .{0, 0, 0, 0}
        }
    };

    const cv_depth: vk.ClearValue = .{
        .depth_stencil = .{
            .depth = 1,
            .stencil = 0
        }
    };

    Chunk.init_context(pipeline_vertex_inputs.get(.Main), pipeline_vertex_inputs.get(.SelectionDisplay));
    var chunk: Chunk = try .init(&allocator, &vk_allocator, .init(.{0, 0, 1}), 0);
    defer chunk.deinit();

    chunk.generate();
    try chunk.build(true);

    var draw_pipeline: Pipelines = .Main;

    var selection_command_buffer: ash.CommandBuffer = try .init(&vk_context, vk_command_pool);

    const selection_fence_info: vk.FenceCreateInfo = .{
        .flags = .{
            .signaled_bit = true
        }
    };

    const selection_fence = try vk_context.device.createFence(&selection_fence_info, null);
    defer vk_context.device.destroyFence(selection_fence, null);

    const selection_data = try vk_allocator.alloc_buffer_empty(4 * @sizeOf(f32), .exclusive, .CPUTransferDst);
    defer vk_allocator.free_buffer(selection_data);

    var first_frame = true;

    while(!window.should_close())
    {
        glfw.pollEvents();

        const ticks = get_tick_count(&time_start_frame, &tick_timer);

        if(ash.glfw.getTime() - fps_timer > 1)
        {
            ash.print_stdout("FPS: {d}\n", .{frames});
            frames = 0;
            fps_timer += 1;
        }

        const sc_next_image_result = try swapchain.acquire_next_image();
        
        switch(sc_next_image_result)
        {
            .NoIssue => {},
            .Failure => { @panic("Failed to acquire next swapchain image."); },
            .NewSwapchain => {
                try vk_context.device.deviceWaitIdle();

                swapchain.deinit_framebuffers(framebuffers);
                framebuffers.deinit(allocator);

                vk_context.device.destroyFramebuffer(selection_framebuffer, null);

                try swapchain.refresh_attachments();

                framebuffers = try swapchain.create_framebuffers(render_passes.getPtr(.DebugGeometry));

                try selection_buffer.build(.{
                    .width = swapchain.extent.width,
                    .height = swapchain.extent.height,
                    .depth = 1
                });

                selection_buffer_attachments = &.{selection_buffer.attachments.items[0].image_view.?, selection_buffer.attachments.items[1].image_view.?};
                selection_framebuffer_info.p_attachments = @ptrCast(selection_buffer_attachments);

                selection_framebuffer_info.width = swapchain.extent.width;
                selection_framebuffer_info.height = swapchain.extent.height;

                selection_framebuffer = try vk_context.device.createFramebuffer(&selection_framebuffer_info, null);

                first_frame = true;
            }
        }

        update_main_input(&draw_pipeline);

        for(0..ticks) |_|
        {
            camera.tick(window);
        }

        camera.update_input(window, 0.002, input_mode);

        try update_shader_uniforms();
        const command_buffer = try swapchain.get_next_command_buffer();

        const descriptor_set: PipelineDescriptorSets = switch(draw_pipeline)
        {
            .DebugGeometry => .DebugGeometryModelView,
            .Main, .SelectionDisplay, .Selection => .ModelView
        };

        const chunk_mesh_mode: Chunk.MeshMode = switch(draw_pipeline)
        {
            .DebugGeometry, .Main => .Main,
            .SelectionDisplay, .Selection => .Selection
        };

        var cursor_pos = window.get_cursor_pos(false);

        if(input_mode == 1)
        {
            cursor_pos.x = @intCast(swapchain.extent.width / 2);
            cursor_pos.y = @intCast(swapchain.extent.height / 2);
        }

        if(cursor_pos.x >= 0 and cursor_pos.y >= 0 and cursor_pos.x < swapchain.extent.width and cursor_pos.y < swapchain.extent.height)
        {
            _ = try vk_context.device.waitForFences(&.{selection_fence}, .true, std.math.maxInt(u64));
            _ = try vk_context.device.resetFences(&.{selection_fence});

            if(!first_frame)
            {
                try ash.vk_memory.copy_image_to_buffer(&vk_context, selection_buffer.attachments.items[0].image.?.image, selection_data.buffer, .{ .x = cursor_pos.x, .y = cursor_pos.y, .z = 0 },
                    .{ .width = 1, .height = 1, .depth = 1 }, vk_command_pool, vk_queues.get(.Graphics));

                const selection_data_slc = try vk_allocator.pull_buffer_data(u32, selection_data);
                defer allocator.free(selection_data_slc);

                if(selection_data_slc[3] == 1)
                {
                    var x = (selection_data_slc[0] >> 16) & 255;
                    var y = (selection_data_slc[0] >> 8) & 255;
                    var z = selection_data_slc[0] & 255;

                    const fac = selection_data_slc[0] >> 24;

                    if(window.get_mouse_button(glfw.MouseButton1) == glfw.Press)
                    {
                        switch(fac)
                        {
                            1 => { x -= 1; },
                            3 => { y -= 1; },
                            5 => { z -= 1; },
                            else => {}
                        }

                        chunk.set(x, y, z, 0);
                        try chunk.build(true);
                    }

                    if(window.get_mouse_button(glfw.MouseButton2) == glfw.Press)
                    {
                        var can_place: bool = true;

                        switch(fac)
                        {
                            0 => {
                                if(x == 0)
                                {
                                    can_place = false;
                                }
                                else
                                {
                                    x -= 1;
                                }
                            },
                            1 => {
                                if(x == imp_chunk.CHUNK_SIZE.data[0])
                                {
                                    can_place = false;
                                }
                            },
                            2 => {
                                if(y == 0)
                                {
                                    can_place = false;
                                }
                                else
                                {
                                    y -= 1;
                                }
                            },
                            3 => {
                                if(y == imp_chunk.CHUNK_SIZE.data[1])
                                {
                                    can_place = false;
                                }
                            },
                            4 => {
                                if(z == 0)
                                {
                                    can_place = false;
                                }
                                else
                                {
                                    z -= 1;
                                }
                            },
                            5 => {
                                if(z == imp_chunk.CHUNK_SIZE.data[2])
                                {
                                    can_place = false;
                                }
                            },
                            else => {}
                        }

                        if(can_place)
                        {
                            chunk.set(x, y, z, 1);
                            try chunk.build(true);
                        }
                    }
                }
            }

            try selection_command_buffer.reset();
            try selection_command_buffer.begin_recording();
            selection_command_buffer.cmd_begin_render_pass(render_passes.getPtr(.Selection), selection_framebuffer, swapchain.extent, &.{cv_selection_color, cv_depth});
            selection_command_buffer.cmd_set_viewport_full(swapchain.extent);
            selection_command_buffer.cmd_set_scissor(.{ .offset = .{ .x = cursor_pos.x, .y = cursor_pos.y }, .extent = .{ .width = 1, .height = 1 } });
            selection_command_buffer.cmd_bind_pipeline(pipelines.getPtr(.Selection));
            selection_command_buffer.cmd_bind_descriptor_set(pipelines.getPtr(.Selection), &pipeline_descriptor_sets.getPtr(.ModelView).sets[swapchain.current_image_index]);
            chunk.draw(.Selection, &selection_command_buffer);
            selection_command_buffer.cmd_end_render_pass();
            try selection_command_buffer.end_recording();

            const info_selection_cmd_submit: vk.SubmitInfo = .{
                .command_buffer_count = 1,
                .p_command_buffers = @ptrCast(&selection_command_buffer.handle)
            };

            try vk_context.device.queueSubmit(vk_queues.get(.Graphics), &.{info_selection_cmd_submit}, selection_fence);

            first_frame = false;
        }

        try command_buffer.reset();
        try command_buffer.begin_recording();
        command_buffer.cmd_begin_render_pass(render_passes.getPtr(.DebugGeometry), framebuffers.items[swapchain.current_image_index], swapchain.extent, &.{cv_color, cv_depth});
        command_buffer.cmd_set_viewport_scissor_full(swapchain.extent);
        command_buffer.cmd_bind_pipeline(pipelines.getPtr(draw_pipeline));
        command_buffer.cmd_bind_descriptor_set(pipelines.getPtr(draw_pipeline), &pipeline_descriptor_sets.getPtr(descriptor_set).sets[swapchain.current_image_index]);
        chunk.draw(chunk_mesh_mode, command_buffer);
        command_buffer.cmd_end_render_pass();
        try command_buffer.end_recording();

        try swapchain.render(vk_queues.get(.Graphics));

        try swapchain.present(vk_queues.get(.Presentation));

        frames += 1;
    }

    try vk_context.device.deviceWaitIdle();
}
