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

    vk_allocator = try .init(&vk_context, &allocator, &vk_command_pool, vk_queues.getPtr(.Graphics), .{
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

const RenderPasses = enum(u8)
{
    DebugGeometry
};

var swapchain: ash.Swapchain = undefined;
var render_passes: std.EnumArray(RenderPasses, ash.RenderPass) = .initUndefined();

fn init_render_passes() !void
{
    const p_debug_geometry = render_passes.getPtr(.DebugGeometry);

    p_debug_geometry.* = try .init(&vk_context);

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

    const depth_format = try ash.vk_utils.choose_best_depth_buffer_format(&vk_context);

    // Color attachment.
    try p_debug_geometry.add_attachment_description_no_stencil_multisample(swapchain.format.format, .clear, .store, .undefined, .present_src_khr);
    // Depth attachment.
    try p_debug_geometry.add_attachment_description_no_stencil_multisample(depth_format, .clear, .dont_care, .undefined, .depth_stencil_attachment_optimal);

    try p_debug_geometry.add_subpass(sp_color_depth);
    try p_debug_geometry.build();
}

fn deinit_render_passes() void
{
    render_passes.getPtr(.DebugGeometry).deinit();
}

const PipelineDescriptorSets = enum(u8)
{
    DebugGeometryModelView
};

const Pipelines = enum(u8)
{
    DebugGeometry
};

var pipeline_descriptor_sets: std.EnumArray(PipelineDescriptorSets, ash.PipelineDescriptorSet) = .initUndefined();
var pipeline_vertex_inputs: std.EnumArray(Pipelines, ash.PipelineVertexInput) = .initUndefined();
var pipelines: std.EnumArray(Pipelines, ash.Pipeline) = .initUndefined();

fn init_graphics_pipelines() !void
{
    var pvi_debug_geometry = pipeline_vertex_inputs.getPtr(.DebugGeometry); 

    pvi_debug_geometry.* = try .init(&allocator);

    try pvi_debug_geometry.add_attribute(0, 0, .r32g32b32_sfloat, 0);
    try pvi_debug_geometry.build(0, .vertex);

    const pds_debug_geometry = pipeline_descriptor_sets.getPtr(.DebugGeometryModelView);

    pds_debug_geometry.* = try .init(&vk_context, &vk_allocator, @truncate(swapchain.image_count));

    try pds_debug_geometry.add_binding(.{
        .binding_index = 0,
        .shader_stage = .{ .vertex_bit = true },
        .type = .uniform_buffer,
        .buffer_size = 32 * @sizeOf(f32)
    });

    try pds_debug_geometry.build();

    const p_debug_geometry = pipelines.getPtr(.DebugGeometry);

    p_debug_geometry.* = try .init(&vk_context);

    try p_debug_geometry.add_dynamic_state(.viewport);
    try p_debug_geometry.add_dynamic_state(.scissor);

    try p_debug_geometry.add_descriptor_set(pipeline_descriptor_sets.get(.DebugGeometryModelView));

    try p_debug_geometry.add_shader_module("../res/shaders/debug/geometry_vert.spv", .{.vertex_bit = true});
    try p_debug_geometry.add_shader_module("../res/shaders/debug/geometry_frag.spv", .{.fragment_bit = true});

    try p_debug_geometry.add_color_blend_attachment(ash.pipeline.pipeline_color_blend_attachment_alpha_blend());

    p_debug_geometry.set_vertex_input(pvi_debug_geometry);

    p_debug_geometry.info_depth_stencil_testing = ash.pipeline.pipeline_depth_stencil_state_default();

    try p_debug_geometry.build(render_passes.getPtr(.DebugGeometry));
}

fn deinit_graphics_pipelines() void
{
    pipelines.getPtr(.DebugGeometry).deinit();

    pipeline_vertex_inputs.getPtr(.DebugGeometry).deinit();

    pipeline_descriptor_sets.getPtr(.DebugGeometryModelView).deinit() catch unreachable;
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
    const fov = 70.0 * std.math.pi / 180.0;
    
    const width: u32 = swapchain.extent.width;
    const height: u32 = swapchain.extent.height;

    const aspect: f32 = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));

    var projection = try ash.math.mat_projection_perspective(&allocator, fov, aspect, 0.01, 1000.0);
    const projection_data = try ash.math.mat_slice_data(f32, projection);
    projection.deinit();

    const pds_debug_geometry = pipeline_descriptor_sets.getPtr(.DebugGeometryModelView);
    try pds_debug_geometry.place_data(@truncate(swapchain.current_image_index), 0, f32, projection_data, 0);

    allocator.free(projection_data);

    var view = try ash.math.mat_look_at(&allocator, camera.pos, camera.rot);
    const view_data = try ash.math.mat_slice_data(f32, view);
    view.deinit();

    try pds_debug_geometry.place_data(@truncate(swapchain.current_image_index), 0, f32, view_data, 16 * @sizeOf(f32));

    allocator.free(view_data);
}

const Chunk = @import("world/chunk.zig").Chunk;

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

    swapchain = try .init(&window, &vk_context, vk_command_pool, 1);
    defer swapchain.deinit();

    try init_render_passes();
    defer deinit_render_passes();

    try init_graphics_pipelines();
    defer deinit_graphics_pipelines();

    const info_depth_buffer: vk.ImageCreateInfo = .{
        .image_type = .@"2d",
        .extent = .{
            .width = swapchain.extent.width,
            .height = swapchain.extent.height,
            .depth = 1
        },
        .mip_levels = 1,
        .array_layers = 1,
        .format = try ash.vk_utils.choose_best_depth_buffer_format(&vk_context),
        .tiling = .optimal,
        .initial_layout = .undefined,
        .usage = .{ .depth_stencil_attachment_bit = true },
        .sharing_mode = .exclusive,
        .samples = .{ .@"1_bit" = true }
    };

    const depth_image = try vk_allocator.alloc_image_empty(info_depth_buffer, .DepthAttachment);

    const info_depth_image_view: vk.ImageViewCreateInfo = .{
        .image = depth_image.image,
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

    const depth_image_view = try vk_context.device.createImageView(&info_depth_image_view, null);
    defer vk_context.device.destroyImageView(depth_image_view, null);

    var framebuffers = try swapchain.create_framebuffers(render_passes.getPtr(.DebugGeometry), &.{depth_image_view});
    defer
    {
        swapchain.deinit_framebuffers(framebuffers);
        framebuffers.deinit(allocator);
    }

    var test_mesh: ash.Mesh = try .init(&allocator, &vk_allocator, pipeline_vertex_inputs.get(.DebugGeometry), 0);

    var v = try test_mesh.add_vertex();
    try v.add_attrib(@as([3]f32, .{0, 0, 0}));
    v = try test_mesh.add_vertex();
    try v.add_attrib(@as([3]f32, .{1, 0, 0}));
    v = try test_mesh.add_vertex();
    try v.add_attrib(@as([3]f32, .{1, 1, 0}));
    v = try test_mesh.add_vertex();
    try v.add_attrib(@as([3]f32, .{0, 0, 0}));
    v = try test_mesh.add_vertex();
    try v.add_attrib(@as([3]f32, .{1, 1, 0}));
    v = try test_mesh.add_vertex();
    try v.add_attrib(@as([3]f32, .{0, 1, 0}));

    try test_mesh.build(true);
    
    var test_mesh_2: ash.Mesh = try .init(&allocator, &vk_allocator, pipeline_vertex_inputs.get(.DebugGeometry), 0);

    v = try test_mesh_2.add_vertex();
    try v.add_attrib(@as([3]f32, .{0, 0, 2}));
    v = try test_mesh_2.add_vertex();
    try v.add_attrib(@as([3]f32, .{1, 0, 2}));
    v = try test_mesh_2.add_vertex();
    try v.add_attrib(@as([3]f32, .{1, 1, 2}));
    v = try test_mesh_2.add_vertex();
    try v.add_attrib(@as([3]f32, .{0, 0, 2}));
    v = try test_mesh_2.add_vertex();
    try v.add_attrib(@as([3]f32, .{1, 1, 2}));
    v = try test_mesh_2.add_vertex();
    try v.add_attrib(@as([3]f32, .{0, 1, 2}));

    try test_mesh_2.build(true);

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

    const cv_depth: vk.ClearValue = .{
        .depth_stencil = .{
            .depth = 1,
            .stencil = 0
        }
    };

    Chunk.init_context(pipeline_vertex_inputs.get(.DebugGeometry));
    var chunk: Chunk = try .init(&allocator, &vk_allocator, .init(.{0, 0, 1}), 0);

    while(!window.should_close())
    {
        glfw.pollEvents();

        const ticks = get_tick_count(&time_start_frame, &tick_timer);

        if(ash.glfw.getTime() - fps_timer > 1)
        {
            ash.print_stdout("FPS: {d}\n", .{frames}) catch unreachable;
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

                framebuffers = try swapchain.create_framebuffers(render_passes.getPtr(.DebugGeometry), &.{});
            }
        }

        if(window.get_mouse_button(glfw.MouseButton1) == glfw.Press)
        {
            glfw.setInputMode(window.glfw_handle, glfw.Cursor, glfw.CursorDisabled);
        }

        if(glfw.getKey(window.glfw_handle, glfw.KeyEscape) == glfw.Press)
        {
            glfw.setInputMode(window.glfw_handle, glfw.Cursor, glfw.CursorNormal);
        }

        for(0..ticks) |_|
        {
            camera.tick(window);
        }

        camera.update_input(window, 0.002);

        try update_shader_uniforms();
        const command_buffer = try swapchain.get_next_command_buffer();

        try command_buffer.reset();
        try command_buffer.begin_recording();
        command_buffer.cmd_begin_render_pass(render_passes.getPtr(.DebugGeometry), framebuffers.items[swapchain.current_image_index], swapchain.extent, &.{cv_color, cv_depth});
        command_buffer.cmd_set_viewport_scissor_full(swapchain.extent);
        command_buffer.cmd_bind_pipeline(pipelines.getPtr(.DebugGeometry));
        command_buffer.cmd_bind_descriptor_set(pipelines.getPtr(.DebugGeometry), &pipeline_descriptor_sets.getPtr(.DebugGeometryModelView).sets[swapchain.current_image_index]);
        test_mesh.bind_and_draw(command_buffer);
        test_mesh_2.bind_and_draw(command_buffer);
        command_buffer.cmd_end_render_pass();
        try command_buffer.end_recording();

        try swapchain.render(vk_queues.get(.Graphics));

        try swapchain.present(vk_queues.get(.Presentation));

        frames += 1;
    }

    try vk_context.device.deviceWaitIdle();

    try chunk.deinit();

    try test_mesh_2.deinit();
    try test_mesh.deinit();

    try vk_allocator.free_image(depth_image);
}
