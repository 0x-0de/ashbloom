const std = @import("std");
const print = std.debug.print;

const ash = @import("ashbloom");

const vk = ash.vk;
const glfw = ash.glfw;

const vkui = ash.vk_ui;
const ui_basic = ash.ui_theme_basic;

const pipeline = ash.pipeline;

const VkContext = ash.vk_context.VkContext;
const VulkanAllocator = ash.vk_memory.VulkanAllocator;

const Swapchain = ash.Swapchain;
const RenderPass = ash.RenderPass;

const Font = ash.font.Font;

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

var window: ash.window.Window = undefined;

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

    vk_context = try VkContext.init(&allocator, window.glfw_handle, vk_context_options);

    const queue_families = vk_context.physical_device_queue_families;

    vk_queues[@intFromEnum(AppQueueNames.Graphics)] = vk_context.get_queue(@truncate(queue_families.graphics_family_index.?), 0);
    vk_queues[@intFromEnum(AppQueueNames.Presentation)] = vk_context.get_queue(@truncate(queue_families.present_family_index.?), 0);

    vk_command_pool = try ash.commands.create_command_pool(&vk_context);

    vk_allocator = try VulkanAllocator.init(&vk_context, &allocator, &vk_command_pool, &vk_queues[@intFromEnum(AppQueueNames.Graphics)], .{
        .page_size = 128 << 20, // 128 MB.
        .staging_size =  32 << 20 // 32 MB.
    });
}

fn deinit_vk_context() void
{
    vk_allocator.deinit();

    vk_context.device.destroyCommandPool(vk_command_pool, null);
    vk_context.deinit();
}

var render_pass: RenderPass = undefined;

fn init_render_pass(swapchain: Swapchain) !void
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

    render_pass = try RenderPass.init(&vk_context);

    try render_pass.add_attachment_description_no_stencil_multisample
    (swapchain.format.format, .clear, .store, .undefined, .present_src_khr);
    try render_pass.add_subpass(color_subpass);
    try render_pass.build();
}

fn deinit_render_pass() void
{
    render_pass.deinit();
}

var app_pipeline: pipeline.Pipeline = undefined;
var app_descriptor_set: pipeline.PipelineDescriptorSet = undefined;

var app_ui_container: vkui.Container = undefined;

fn deinit_pipeline() !void
{
    app_pipeline.deinit();
    try app_descriptor_set.deinit();
}

fn init_pipeline(swapchain: Swapchain) !void
{
    app_pipeline = try .init(&vk_context);

    var pvi = try pipeline.PipelineVertexInput.init(&allocator);
    defer pvi.deinit();

    try pvi.add_attribute(0, 0, vk.Format.r32_sfloat, 0);
    try pvi.add_attribute(0, 1, vk.Format.r32g32b32a32_sfloat, @sizeOf(u32));
    try pvi.add_attribute(0, 2, vk.Format.r32g32b32a32_sfloat, @sizeOf(u32) + 4 * @sizeOf(f32));
    try pvi.add_attribute(0, 3, vk.Format.r32g32b32a32_sfloat, @sizeOf(u32) + 8 * @sizeOf(f32));

    try pvi.build(0, vk.VertexInputRate.instance);

    app_descriptor_set = try pipeline.PipelineDescriptorSet.init(&vk_context, &vk_allocator, @truncate(swapchain.image_count));

    try app_descriptor_set.add_binding(.{
        .binding_index = 0,
        .type = .uniform_buffer,
        .shader_stage = .{
            .vertex_bit = true
        },
        .buffer_size = 16 * @sizeOf(f32)
    });

    try app_descriptor_set.add_binding(.{
        .binding_index = 1,
        .type = .combined_image_sampler,
        .shader_stage = .{
            .fragment_bit = true
        },
        .image_sampler = app_ui_container.texture_atlas.sampler,
        .image_layout = .shader_read_only_optimal,
        .image_view = app_ui_container.texture_atlas.image_view
    });

    try app_descriptor_set.add_binding(.{
        .binding_index = 2,
        .type = .combined_image_sampler,
        .shader_stage = .{
            .fragment_bit = true
        },
        .image_sampler = app_ui_container.font.?.atlas.sampler,
        .image_layout = .shader_read_only_optimal,
        .image_view = app_ui_container.font.?.atlas.image_view
    });

    try app_descriptor_set.build();

    try app_pipeline.add_shader_module("../../res/shaders/ui_vert.spv", .{.vertex_bit = true});
    try app_pipeline.add_shader_module("../../res/shaders/ui_frag.spv", .{.fragment_bit = true});

    try app_pipeline.add_dynamic_state(vk.DynamicState.viewport);
    try app_pipeline.add_dynamic_state(vk.DynamicState.scissor);

    try app_pipeline.add_descriptor_set(app_descriptor_set);

    try app_pipeline.add_color_blend_attachment(pipeline.pipeline_color_blend_attachment_alpha_blend());

    app_pipeline.set_vertex_input(&pvi);

    try app_pipeline.build(&render_pass);
}

pub fn update_ui_uniforms(set_index: u16) !void
{
    var window_width: u32 = undefined;
    var window_height: u32 = undefined;

    window.get_framebuffer_size(&window_width, &window_height);
    var projection = try ash.math.mat_projection_orthographic(&allocator, 0, @floatFromInt(window_width), 0, @floatFromInt(window_height), -1, 1);

    const projection_data = try ash.math.mat_slice_data(f32, projection);

    projection.deinit();

    try app_descriptor_set.place_data(set_index, 0, f32, projection_data, 0);

    allocator.free(projection_data);
}

const TodoItem = struct
{
    name: []u32
};

fn create_todo_item(item: TodoItem) !*vkui.Element
{
    _ = item;

    const e = try allocator.create(vkui.Element);

    e.* = try vkui.Element.init(&allocator, .Color, .{
        .relative_pos = .{
            .pos_x = 0,
            .pos_y = 1,
            .scl_x = 1,
            .scl_y = 0
        },
        .absolute_offset = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 1,
            .scl_y = 50
        },
        .alignment = .{
            .x = .Left,
            .y = .Top
        }
    }, .{1, 1, 1, 0.2});

    return e;
}

fn new_todo(e: *vkui.Element) !void
{
    _ = e;

    var todo_list_lineage: [2]usize = .{0, 2};
    const todo_list = try app_ui_container.get_element(todo_list_lineage[0..2]);

    const todo_item = try create_todo_item(.{ .name = &.{} });
    _ = try todo_list.add_and_dispose(todo_item);

    app_ui_container.signal_rebuild = true;

    print("Pressed!\n", .{});
}

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

    allocator = dba.allocator();

    glfw.windowHint(glfw.ClientAPI, glfw.NoAPI);

    window = try ash.window.Window.init(1280, 720, "Todo");
    defer window.destroy();

    try init_vk_context();
    defer deinit_vk_context();

    var swapchain = try Swapchain.init(window.glfw_handle, &vk_context, vk_command_pool, 1);
    defer swapchain.deinit();

    try init_render_pass(swapchain);
    defer deinit_render_pass();

    try vkui.init();
    defer vkui.deinit();

    app_ui_container = try vkui.Container.init(&vk_context, &vk_allocator, .{
        .pipeline = &app_pipeline,
        .descriptor_set = &app_descriptor_set,
        .render_pass = &render_pass,
        .render_queue = vk_queues[@intFromEnum(AppQueueNames.Graphics)]
    });

    var font = try Font.init(&vk_context, &vk_allocator, "res/bahnschrift.ttf", 36);
    app_ui_container.font = &font;

    try init_pipeline(swapchain);

    var framebuffers_ui = try swapchain.create_framebuffers(&render_pass);
    defer framebuffers_ui.deinit(allocator);
    defer swapchain.deinit_framebuffers(framebuffers_ui);

    const background = try ui_basic.create_quad(&allocator, .{
        .relative_pos = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 1,
            .scl_y = 1
        },
        .absolute_offset = .get_default(),
        .alignment = .{
            .x = .Left,
            .y = .Bottom
        }
    }, .{0.01, 0.01, 0.01, 1});

    const enter_textfield = try ui_basic.create_textfield(&allocator, .{
        .relative_pos = .{
            .pos_x = 0,
            .pos_y = 1,
            .scl_x = 1,
            .scl_y = 0
        },
        .absolute_offset = .{
            .pos_x = 30,
            .pos_y = -30,
            .scl_x = -230,
            .scl_y = 40
        },
        .alignment = .{
            .x = .Left,
            .y = .Top
        }
    }, .{
        .font = &font,
        .text_alignment = .{
            .x = .Left,
            .y = .Bottom
        },
        .text_size = 30
    });

    const enter_button = try ui_basic.create_button(&allocator, .{
        .color_idle = .{0.15, 0.15, 0.15, 1},
        .color_hover = .{0.25, 0.25, 0.25, 1},
        .color_press = .{0.4, 0.4, 0.4, 1},
        .placement = .{
            .relative_pos = .{
                .pos_x = 1,
                .pos_y = 1,
                .scl_x = 0,
                .scl_y = 0
            },
            .absolute_offset = .{
                .pos_x = -200,
                .pos_y = -30,
                .scl_x = 170,
                .scl_y = 40
            },
            .alignment = .{
                .x = .Left,
                .y = .Top
            }
        },
        .press_callback = new_todo
    });

    const list_panel = try ui_basic.create_quad(&allocator, .{
        .relative_pos = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 1,
            .scl_y = 1
        },
        .absolute_offset = .{
            .pos_x = 50,
            .pos_y = 50,
            .scl_x = -100,
            .scl_y = -250
        },
        .alignment = .{
            .x = .Left,
            .y = .Bottom
        }
    }, .{0.005, 0.005, 0.005, 1});

    _ = try background.add_and_dispose(enter_textfield);
    _ = try background.add_and_dispose(enter_button);
    _ = try background.add_and_dispose(list_panel);

    _ = try app_ui_container.add_and_dispose(background);

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
            swapchain.deinit_framebuffers(framebuffers_ui);
            framebuffers_ui.deinit(allocator);
            framebuffers_ui = try swapchain.create_framebuffers(&render_pass);
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
            ash.window.Window.reset_input_values();
            app_ui_container.signal_reset_manual_input = false;
        }

        try update_ui_uniforms(@truncate(swapchain.current_image_index));

        const command_buffer = try swapchain.get_next_command_buffer();

        try app_ui_container.draw(command_buffer, &swapchain, framebuffers_ui.items[swapchain.current_image_index]);

        try swapchain.present(vk_queues[@intFromEnum(AppQueueNames.Presentation)]);

        frames += 1;
    }

    try vk_context.device.deviceWaitIdle();

    try font.deinit();
    try app_ui_container.deinit();

    try deinit_pipeline();
}