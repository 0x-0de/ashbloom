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

const Texture2D = ash.image_utils.Texture2D;
const TextureAtlas2D = ash.image_utils.TextureAtlas2D;

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

const AppQueues = enum(u8)
{
    Graphics = 0,
    Presentation,
};

var vk_queues: std.EnumArray(AppQueues, vk.Queue) = .initUndefined();

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

    vk_context = try VkContext.init(&allocator, &window, vk_context_options);

    const queue_families = vk_context.physical_device_queue_families;

    vk_queues.set(.Graphics, vk_context.get_queue(@truncate(queue_families.graphics_family_index.?), 0));
    vk_queues.set(.Presentation, vk_context.get_queue(@truncate(queue_families.present_family_index.?), 0));

    vk_command_pool = try ash.commands.create_command_pool(&vk_context);

    vk_allocator = try VulkanAllocator.init(&vk_context, &allocator, &vk_command_pool, vk_queues.getPtr(.Graphics), .{
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

var app_ui_container: vkui.Container = undefined;
var app_font: Font = undefined;

var icon_trash: TextureAtlas2D.TextureSuballocation = undefined;

const todo_height: f32 = 50;

const TodoItem = struct
{
    name: []u32,
    index: u32
};

fn set_todo_list_scroll(adding: bool) !void
{
    var todo_list_lineage: [2]usize = .{0, 2};
    const todo_list = try app_ui_container.get_element(todo_list_lineage[0..2]);

    const list_bounds = try app_ui_container.get_element_bounds(todo_list.lineage.?);

    const min_height = list_bounds.cut_bounds.scl_y;
    const prev_height = list_bounds.draw_bounds.scl_y;

    var height = @as(f32, @floatFromInt(todo_list.children.items.len - 1)) * todo_height;
    if(!adding) height -= todo_height;

    if(height < min_height) height = min_height;
    
    todo_list.space.scl_x = list_bounds.cut_bounds.scl_x;
    todo_list.space.scl_y = height;

    const diff = height - prev_height;

    if(height == min_height)
    {
        todo_list.space.pos_y = 0;
    }
    else if(adding)
    {
        todo_list.space.pos_y += diff;
    }
    else
    {
        todo_list.space.pos_y += diff;
        if(todo_list.space.pos_y < 0) todo_list.space.pos_y = 0;
    }
}

fn callback_delete_todo_item(e: *vkui.Element) !void
{
    const item = e.parent.?;

    var signal = true;
    misc.memcpy_anonymous(item.data.?.ptr + @sizeOf(u32), &signal, @sizeOf(bool));
    
    try set_todo_list_scroll(false);
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

    const icon_delete = try ui_basic.create_icon(&allocator, .{
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
    }, .{icon_trash.pos_x, icon_trash.pos_y, icon_trash.scl_x, icon_trash.scl_y});

    try e.add_and_dispose(checkbox);

    try text_area.add_and_dispose(text);
    try e.add_and_dispose(text_area);

    try button_delete.add_and_dispose(icon_delete);
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

    try set_todo_list_scroll(true);

    app_ui_container.signal_ignore_callbacks = true;
    app_ui_container.signal_rebuild = true;
}

fn init_ui_main_elements() !void
{
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
            .pos_x = 50,
            .pos_y = -30,
            .scl_x = -250,
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
                .scl_x = 150,
                .scl_y = 40
            },
            .alignment = .{
                .x = .Left,
                .y = .Top
            }
        },
        .press_callback = new_todo
    });

    var enter_unicode = try ui_basic.get_unicode_from_string(&allocator, "Add item");

    const enter_button_text = try ui_basic.create_text(&allocator, .{
        .alignment = .{
            .x = .Center,
            .y = .Center
        },
        .font = &app_font,
        .margin = 0,
        .size = 30,
        .string = enter_unicode.items
    });

    try enter_button.add_and_dispose(enter_button_text);
    enter_unicode.deinit(allocator);

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
            .scl_y = -150
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
}

pub fn main() !void
{
    try ash.init_graphics();
    defer ash.deinit_graphics();

    const exe_path = ash.misc.get_exe_path();
    std.debug.print("{s}\n", .{exe_path});

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

    const system_fonts = try ash.misc.enumerate_system_fonts(&allocator);

    const names = [_][]const u8{"bahnschrift", "arial"};
    const names_slc: []const []const u8 = &names;

    const font_entry = try ash.misc.search_font_entries(system_fonts, names_slc);

    try init_vk_context();
    defer deinit_vk_context();

    var swapchain = try Swapchain.init(&window, &vk_context, vk_command_pool, 1);
    defer swapchain.deinit();

    try vkui.init();
    defer vkui.deinit();

    app_ui_container = try vkui.Container.init(&vk_context, &vk_allocator);
    app_font = try Font.init(&vk_context, &vk_allocator, font_entry.path, 36, &app_ui_container.texture_atlas);

    var trash_texture: Texture2D = try .init(&vk_context, &vk_allocator, "../res/trash.bmp", .Subtexture);
    icon_trash = try app_ui_container.texture_atlas.add_texture(&trash_texture);
    try trash_texture.deinit();

    for(system_fonts, 0..) |_, i|
    {
        system_fonts[i].deinit(&allocator);
    }
    allocator.free(system_fonts);

    var container_resources = try ui_basic.init_render_instance(&vk_context, &vk_allocator, swapchain, app_ui_container, vk_queues.get(.Graphics));
    app_ui_container.set_render_instance(container_resources);

    var framebuffers_ui = try swapchain.create_framebuffers(container_resources.render_pass);
    defer framebuffers_ui.deinit(allocator);
    defer swapchain.deinit_framebuffers(framebuffers_ui);

    try init_ui_main_elements();

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
            framebuffers_ui = try swapchain.create_framebuffers(container_resources.render_pass);
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

        const command_buffer = try swapchain.get_next_command_buffer();

        try app_ui_container.draw(command_buffer, &swapchain, framebuffers_ui.items[swapchain.current_image_index]);

        try swapchain.present(vk_queues.get(.Presentation));

        frames += 1;
    }

    try vk_context.device.deviceWaitIdle();

    try app_font.deinit();
    try app_ui_container.deinit();

    try container_resources.deinit(vk_context);
}
