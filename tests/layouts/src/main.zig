const std = @import("std");
const ash = @import("ashbloom");

const glfw = ash.glfw;
const vk = ash.vk;

const ui = ash.ui.core;

var debug_required_validation_layers: [1][*:0]const u8 = .{
    "VK_LAYER_KHRONOS_validation"
};

var debug_required_instance_extensions: [1][*:0]const u8 = .{
    vk.extensions.ext_debug_utils.name
};

var required_device_extensions: [1][*:0]const u8 = .{
    vk.extensions.khr_swapchain.name
};

const Window = ash.rendering.Window;

var allocator: std.mem.Allocator = undefined;

var window: Window = undefined;

var vk_context: ash.rendering.VkContext = undefined;
var vk_interface: ash.rendering.VkInterface = undefined;
var vk_allocator: ash.utils.VulkanAllocator = undefined;

var vk_command_pool: vk.CommandPool = undefined;

const AppQueues = enum(u8)
{
    Graphics = 0,
    Presentation,
};

var vk_queues: std.EnumArray(AppQueues, vk.Queue) = .initUndefined();

/// Initializes the Vulkan context.
fn init_vk_interfaces() !void
{
    const vk_context_options: ash.rendering.VkContext.InitOptions = .{
        .instance_extensions = @ptrCast(&debug_required_instance_extensions),
        .instance_layers = @ptrCast(&debug_required_validation_layers),
    };

    const vk_interface_options: ash.rendering.VkInterface.InitOptions = .{
        .device_layers = @ptrCast(&debug_required_validation_layers),
        .required_device_extensions = @ptrCast(&required_device_extensions),
        .required_device_features = .{
            .logic_op = .true
        }

    };

    vk_context = try .init(&allocator, vk_context_options);
    vk_interface = try .init_window(&vk_context, &window, vk_interface_options);

    const queue_families = vk_interface.physical_device_queue_families.?;

    vk_queues.set(.Graphics, vk_interface.get_queue(@truncate(queue_families.graphics_family_index.?), 0));
    vk_queues.set(.Presentation, vk_interface.get_queue(@truncate(queue_families.present_family_index.?), 0));

    vk_command_pool = try ash.rendering.commands.create_command_pool(&vk_interface, @truncate(queue_families.graphics_family_index.?));

    vk_allocator = try .init(&vk_interface, &allocator, .{
        .transfer_command_pool = &vk_command_pool,
        .transfer_queue = vk_queues.getPtr(.Graphics),
        .page_size = 128 << 20, // 128 MB.
        .staging_size =  32 << 20 // 32 MB.
    });
}

/// Deinitializes the Vulkan context.
fn deinit_vk_interfaces() void
{
    vk_allocator.deinit();

    vk_interface.device.destroyCommandPool(vk_command_pool, null);
    vk_interface.deinit();

    vk_context.deinit();
}

/// The application's main and only UI container.
var app_ui_container: ui.Container = undefined;
/// The application's chosen text font.
var app_font: ash.ui.Font = undefined;

fn init_ui_elements() !void
{
    const background = try ash.ui.theme_basic.create_quad(&allocator, .{
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
    }, .{0.01, 0.01, 0.05, 1});

    const linear_quad = try ash.ui.theme_basic.create_quad(&allocator, .{
        .relative_pos = .{
            .pos_x = 0,
            .pos_y = 0,
            .scl_x = 0.3,
            .scl_y = 0.5,
        },
        .absolute_offset = .{
            .pos_x = 30,
            .pos_y = 30,
            .scl_x = 0,
            .scl_y = 0
        },
        .alignment = .{
            .x = .Left,
            .y = .Bottom
        }
    }, .{0.2, 0.2, 0.2, 1});

    try ash.ui.layouts.set_layout_linear(linear_quad, .{
        .primary_direction = .{
            .margin = 5,
            .spacing = 5,
        },
        .secondary_direction = .{
            .margin = 5,
            .spacing = 5,
        },
        .primary_axis = .Horizontal,
        .alignment = .{
            .x = .Left,
            .y = .Center
        }
    });

    const split_quad = try ash.ui.theme_basic.create_quad(&allocator, .{
        .relative_pos = .{
            .pos_x = 0.35,
            .pos_y = 0,
            .scl_x = 0.3,
            .scl_y = 0.5
        },
        .absolute_offset = .{
            .pos_x = 30,
            .pos_y = 30,
            .scl_x = 0,
            .scl_y = 0
        },
        .alignment = .{
            .x = .Left,
            .y = .Bottom
        }
    }, .{0.2, 0.2, 0.2, 1});

    try ash.ui.layouts.set_layout_split(split_quad, .{
        .primary_axis = .Horizontal,
        .primary_limit = 5
    });

    var random = std.Random.DefaultPrng.init(34891343);

    for(0..8) |i|
    {
        const next_value_a = (random.next() % 150) + 50;
        const next_value_b = (random.next() % 150) + 50;

        const color: [4]f32 = switch(i % 4)
        {
            0 => .{0.2, 0.75, 0.2, 1},
            1 => .{0.2, 0.25, 0.8, 1},
            2 => .{0.8, 0.15, 0.25, 1},
            else => .{0.6, 0.8, 0.15, 1},
        };

        const linear_child = try ash.ui.theme_basic.create_quad(&allocator, .{
            .relative_pos = .{
                .pos_x = 0,
                .pos_y = 0,
                .scl_x = 0,
                .scl_y = 0
            },
            .absolute_offset = .{
                .pos_x = 0,
                .pos_y = 0,
                .scl_x = @floatFromInt(next_value_a),
                .scl_y = @floatFromInt(next_value_b)
            },
            .alignment = .{
                .x = .Left,
                .y = .Bottom
            }
        }, color);

        try linear_quad.add_and_dispose(linear_child);
    }

    for(0..14) |i|
    {
        const color: [4]f32 = switch(i % 4)
        {
            0 => .{0.2, 0.75, 0.2, 1},
            1 => .{0.2, 0.25, 0.8, 1},
            2 => .{0.8, 0.15, 0.25, 1},
            else => .{0.6, 0.8, 0.15, 1},
        };

        const split_child = try ash.ui.theme_basic.create_quad(&allocator, undefined, color);

        try split_quad.add_and_dispose(split_child);
    }

    try background.add_and_dispose(linear_quad);
    try background.add_and_dispose(split_quad);

    try app_ui_container.add_and_dispose(background);
}

pub fn main() !void
{
    var dba: std.heap.DebugAllocator(.{}) = .{};
    defer {
        const dba_result = dba.deinit();
        if(dba_result == .leak)
        {
            std.debug.print("Program terminates with {d} memory leaks.\n", .{@intFromEnum(dba_result)});
        }
    }

    allocator = dba.allocator();

    try ash.init_graphics(&allocator);
    defer ash.deinit_graphics();

    glfw.windowHint(glfw.ClientAPI, glfw.NoAPI);

    window = try .init(1280, 720, "UI layouts test");
    defer window.destroy();

    const system_fonts = try ash.utils.misc.enumerate_system_fonts(&allocator);

    const names = [_][]const u8{"bahnschrift", "arial", "LiberationSans-Regular"};
    const names_slc: []const []const u8 = &names;

    const font_entry = try ash.utils.misc.search_font_entries(system_fonts, names_slc);

    try init_vk_interfaces();
    defer deinit_vk_interfaces();

    var swapchain = try ash.rendering.Swapchain.init(&window, &vk_interface, &vk_allocator, vk_command_pool, 1);
    defer swapchain.deinit(true);

    try ui.init();
    defer ui.deinit();

    app_ui_container = try ui.Container.init(&vk_interface, &vk_allocator);

    app_font = try ash.ui.Font.init(&vk_interface, &vk_allocator, font_entry.path, 36, &app_ui_container.texture_atlas);
    defer app_font.deinit();

    for(system_fonts, 0..) |_, i|
    {
        system_fonts[i].deinit(&allocator);
    }
    allocator.free(system_fonts);

    var container_resources = try ash.ui.theme_basic.init_render_instance(&vk_interface, &vk_allocator, swapchain, app_ui_container, null, vk_queues.get(.Graphics));
    defer container_resources.deinit(vk_interface);
    app_ui_container.set_render_instance(container_resources);

    var framebuffers_ui = try swapchain.create_framebuffers(container_resources.render_pass, &.{});
    defer framebuffers_ui.deinit(allocator);
    defer swapchain.deinit_framebuffers(framebuffers_ui);
    
    try init_ui_elements();

    var cur_size = window.get_framebuffer_size();

    try app_ui_container.set_bounds(0, 0, @floatFromInt(cur_size.width), @floatFromInt(cur_size.height));
    try app_ui_container.build();

    while(!window.should_close())
    {
        const prev_window_size: vk.Extent2D = .{
            .width = cur_size.width,
            .height = cur_size.height
        };

        glfw.pollEvents();

        const acquire_result = try swapchain.acquire_next_image();
        if(acquire_result == .NewSwapchain)
        {
            swapchain.deinit_framebuffers(framebuffers_ui);
            framebuffers_ui.deinit(allocator);
            framebuffers_ui = try swapchain.create_framebuffers(container_resources.render_pass, &.{});
        }

        cur_size = window.get_framebuffer_size();

        if(cur_size.width != prev_window_size.width or cur_size.height != prev_window_size.height)
        {
            try app_ui_container.set_bounds(0, 0, @floatFromInt(cur_size.width), @floatFromInt(cur_size.height));
        }

        const container_input = window.get_ui_container_input();

        try app_ui_container.update(container_input);

        if(app_ui_container.signal_reset_manual_input)
        {
            ash.rendering.Window.reset_input_values();
            app_ui_container.signal_reset_manual_input = false;
        }

        const command_buffer = try swapchain.get_next_command_buffer();
        try app_ui_container.draw(command_buffer, &swapchain, framebuffers_ui.items[swapchain.current_image_index]);

        try swapchain.present(vk_queues.get(.Presentation));
    }

    try vk_interface.device.deviceWaitIdle();
    try app_ui_container.deinit();
}
