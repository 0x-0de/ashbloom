const std = @import("std");
const print = std.debug.print;

const ash = @import("ashbloom");

const vk = ash.vk;
const glfw = ash.glfw;

const vkui = ash.vk_ui;
const ui_basic = ash.ui_theme_basic;

const misc = ash.misc;

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

var app_font: Font = undefined;

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

const todo_height: f32 = 50;

const TodoItem = struct
{
    name: []u32,
    index: u32
};

fn set_todo_list_scroll() !void
{
    var todo_list_lineage: [2]usize = .{0, 2};
    const todo_list = try app_ui_container.get_element(todo_list_lineage[0..2]);

    const list_bounds = try app_ui_container.get_element_bounds(todo_list.lineage.?);

    const height = @as(f32, @floatFromInt(todo_list.children.items.len - 1)) * todo_height;
    
    todo_list.space.scl_x = list_bounds.cut_bounds.scl_x;
    todo_list.space.scl_y = height;

    const expected_height = if(height - todo_height < list_bounds.cut_bounds.scl_y) 0 else (height - list_bounds.cut_bounds.scl_y) - todo_height;
    const new_height = if(height < list_bounds.cut_bounds.scl_y) 0 else (height - list_bounds.cut_bounds.scl_y);

    todo_list.space.pos_y = if(todo_list.space.pos_y == expected_height or height < list_bounds.cut_bounds.scl_y) new_height else todo_list.space.pos_y + todo_height;
}

fn callback_delete_todo_item(e: *vkui.Element) !void
{
    const item = e.parent.?;

    var signal = true;
    misc.memcpy_anonymous(item.data.?.ptr + @sizeOf(u32), &signal, @sizeOf(bool));
    
    try set_todo_list_scroll();
    app_ui_container.signal_rebuild = true;
}

fn create_todo_item(item: TodoItem) !*vkui.Element
{
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
            .pos_y = -@as(f32, @floatFromInt(@as(i32, @bitCast(item.index)))) * todo_height,
            .scl_x = 1,
            .scl_y = todo_height
        },
        .alignment = .{
            .x = .Left,
            .y = .Top
        }
    }, .{1, 1, 1, 0.2});

    e.data = try allocator.alloc(u8, @sizeOf(u32) + @sizeOf(bool));

    var item_alias = item;
    misc.memcpy_anonymous(e.data.?.ptr, &item_alias.index, @sizeOf(u32));

    var false_alias = false;
    misc.memcpy_anonymous(e.data.?.ptr + @sizeOf(u32), &false_alias, @sizeOf(bool));

    var checkbox_properties: ui_basic.CheckboxProperties = .init_default(.{
        .relative_pos = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 0,
            .scl_y = 0
        },
        .absolute_offset = .{
            .pos_x = 10,
            .pos_y = 10,
            .scl_x = 30,
            .scl_y = 30
        },
        .alignment = .{
            .x = .Left,
            .y = .Bottom
        }
    });

    checkbox_properties.border_width = 4;

    const checkbox = try ui_basic.create_checkbox(&allocator, checkbox_properties);

    const text_area = try ui_basic.create_quad(&allocator, .{
        .relative_pos = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 0.8,
            .scl_y = 1
        },
        .absolute_offset = .{
            .pos_x = 60,
            .pos_y = 5,
            .scl_x = 0,
            .scl_y = 0
        },
        .alignment = .{
            .x = .Left,
            .y = .Bottom
        }
    }, .{1, 0, 0, 0});

    const text_properties: ui_basic.TextProperties = .init(&app_font, 30, .{
        .x = .Left,
        .y = .Center
    }, item.name);

    const text = try ui_basic.create_text(&allocator, text_properties);

    const button_delete = try ui_basic.create_button(&allocator, .{
        .placement = .{
            .relative_pos = .{
            .pos_x = 1,
            .pos_y = 0,
            .scl_x = 0,
            .scl_y = 0
            },
            .absolute_offset = .{
                .pos_x = -80,
                .pos_y = 5,
                .scl_x = 40,
                .scl_y = 40
            },
            .alignment = .{
                .x = .Left,
                .y = .Bottom
            }
        },
        .color_idle = .{0.75, 0.1, 0.1, 1},
        .color_hover = .{0.85, 0.15, 0.15, 1},
        .color_press = .{0.9, 0.25, 0.25, 1},
        .press_callback = callback_delete_todo_item
    });

    try e.add_and_dispose(checkbox);

    try text_area.add_and_dispose(text);
    try e.add_and_dispose(text_area);

    try e.add_and_dispose(button_delete);

    return e;
}

fn todo_list_rebuild_callback(e: *vkui.Element, data: vkui.ContainerInputData) !void
{
    if(e.children.items.len == 0) return;

    const item_index = e.children.items.len - 1;

    _ = data;

    var lineage: [5]usize = .{0, 2, item_index, 1, 0};
    const text_item = try app_ui_container.get_element(lineage[0..5]);

    try text_item.force_callback(.WindowResize);

    for(1..e.children.items.len) |i|
    {
        var delete_signal: bool = undefined;
        misc.memcpy_anonymous(&delete_signal, e.children.items[i].data.?.ptr + @sizeOf(u32), @sizeOf(bool));

        if(delete_signal)
        {
            try e.remove_by_index(i);
            break;
        }
    }

    for(1..e.children.items.len) |i|
    {
        const v = @as(f32, @floatFromInt(i - 1));

        const child = e.children.items[i];
        child.placement.absolute_offset.pos_y = -v * todo_height;
    }
}

fn new_todo(e: *vkui.Element) !void
{
    _ = e;

    var todo_list_lineage: [2]usize = .{0, 2};
    const todo_list = try app_ui_container.get_element(todo_list_lineage[0..2]);

    var textfield_lineage: [2]usize = .{0, 0};
    const textfield = try app_ui_container.get_element(textfield_lineage[0..2]);

    const todo_item_title = ui_basic.get_textfield_text(textfield);

    const todo_item = try create_todo_item(.{ .name = todo_item_title, .index = @truncate(todo_list.children.items.len) });
    try todo_list.add_and_dispose(todo_item);

    // const new_item_index = todo_list.children.items.len - 1;
    // try todo_list.children.items[new_item_index].force_callback(.WindowResize);

    try set_todo_list_scroll();

    app_ui_container.signal_rebuild = true;
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

    app_font = try Font.init(&vk_context, &vk_allocator, "res/bahnschrift.ttf", 36);
    app_ui_container.font = &app_font;

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
        .font = &app_font,
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

    var list_panel = try ui_basic.create_quad(&allocator, .{
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

    list_panel.space = .{
        .pos_x = 0,
        .pos_y = 0,
        .scl_x = 0,
        .scl_y = 0
    };

    const scrollbar = try ui_basic.create_scrollbar(&allocator);

    try list_panel.add_callback(.Rebuild, todo_list_rebuild_callback);

    try list_panel.add_callback(.Scroll, vkui.default_scroll_callback);

    try list_panel.add_and_dispose(scrollbar);

    try background.add_and_dispose(enter_textfield);
    try background.add_and_dispose(enter_button);
    try background.add_and_dispose(list_panel);

    try app_ui_container.add_and_dispose(background);

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

    try app_font.deinit();
    try app_ui_container.deinit();

    try deinit_pipeline();
}