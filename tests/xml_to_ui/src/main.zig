const std = @import("std");
const ash = @import("ashbloom");

const glfw = ash.glfw;
const vk = ash.vk;

const ui = ash.ui;

var debug_required_validation_layers: [1][*:0]const u8 = .{
    "VK_LAYER_KHRONOS_validation"
};

var debug_required_instance_extensions: [1][*:0]const u8 = .{
    vk.extensions.ext_debug_utils.name
};

var required_device_extensions: [1][*:0]const u8 = .{
    vk.extensions.khr_swapchain.name
};

const Window = ash.ABWindow;

var allocator: std.mem.Allocator = undefined;

var window: Window = undefined;

var vk_context: ash.VkContext = undefined;
var vk_allocator: ash.VulkanAllocator = undefined;

var vk_command_pool: vk.CommandPool = undefined;

const AppQueues = enum(u8)
{
    Graphics = 0,
    Presentation,
};

var vk_queues: std.EnumArray(AppQueues, vk.Queue) = .initUndefined();

/// Initializes the Vulkan context.
fn init_vk_context() !void
{
    const vk_context_options: ash.VkContext.InitOptions = .{
        .instance_extensions = @ptrCast(&debug_required_instance_extensions),
        .instance_layers = @ptrCast(&debug_required_validation_layers),
        .required_device_extensions = @ptrCast(&required_device_extensions),
        .required_device_features = .{
            .logic_op = .true
        }
    };

    vk_context = try ash.VkContext.init(&allocator, &window, vk_context_options);

    const queue_families = vk_context.physical_device_queue_families.?;

    vk_queues.set(.Graphics, vk_context.get_queue(@truncate(queue_families.graphics_family_index.?), 0));
    vk_queues.set(.Presentation, vk_context.get_queue(@truncate(queue_families.present_family_index.?), 0));

    vk_command_pool = try ash.commands.create_command_pool(&vk_context, @truncate(queue_families.graphics_family_index.?));

    vk_allocator = try ash.VulkanAllocator.init(&vk_context, &allocator, .{
        .transfer_command_pool = &vk_command_pool,
        .transfer_queue = vk_queues.getPtr(.Graphics),
        .page_size = 128 << 20, // 128 MB.
        .staging_size =  32 << 20 // 32 MB.
    });
}

/// Deinitializes the Vulkan context.
fn deinit_vk_context() void
{
    vk_allocator.deinit();

    vk_context.device.destroyCommandPool(vk_command_pool, null);
    vk_context.deinit();
}

/// The application's main and only UI container.
var app_ui_container: ui.Container = undefined;
/// The application's chosen text font.
var app_font: ash.Font = undefined;

fn init_ui_elements(font: *ash.Font) !void
{
    const background = try ash.ui_theme_basic.create_quad(&allocator, .{
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

    const ui_assets: ash.ui_theme_basic.XMLUIAssets = .{
        .fonts = &.{
            .{
                .name = "main",
                .font = font
            }
        },
        .callbacks = &.{}
    };

    try ash.ui_theme_basic.load_xml_ui(&allocator, "../../res/test_xml.xml", background, ui_assets);

    try app_ui_container.add_and_dispose(background);
}

pub fn main() !void
{
    var dba: std.heap.DebugAllocator(.{}) = .{};
    defer {
        const dba_result = dba.deinit();
        if(dba_result == .leak)
        {
            std.debug.print("Program terminated with {d} memory leaks.\n", .{@intFromEnum(dba_result)});
        }
    }

    allocator = dba.allocator();

    try ash.init_graphics(&allocator);
    defer ash.deinit_graphics();

    glfw.windowHint(glfw.ClientAPI, glfw.NoAPI);

    window = try .init(1280, 720, "Textfield test");
    defer window.destroy();

    const system_fonts = try ash.misc.enumerate_system_fonts(&allocator);

    const names = [_][]const u8{"bahnschrift", "arial", "LiberationSans-Regular"};
    const names_slc: []const []const u8 = &names;

    const font_entry = try ash.misc.search_font_entries(system_fonts, names_slc);

    try init_vk_context();
    defer deinit_vk_context();

    var swapchain = try ash.Swapchain.init(&window, &vk_context, &vk_allocator, vk_command_pool, 1);
    defer swapchain.deinit(true);

    try ui.init();
    defer ui.deinit();

    app_ui_container = try ui.Container.init(&vk_context, &vk_allocator);

    app_font = try ash.Font.init(&vk_context, &vk_allocator, font_entry.path, 36, &app_ui_container.texture_atlas);
    defer app_font.deinit();

    for(system_fonts, 0..) |_, i|
    {
        system_fonts[i].deinit(&allocator);
    }
    allocator.free(system_fonts);

    var container_resources = try ash.ui_theme_basic.init_render_instance(&vk_context, &vk_allocator, swapchain, app_ui_container, null, vk_queues.get(.Graphics));
    defer container_resources.deinit(vk_context);
    app_ui_container.set_render_instance(container_resources);

    var framebuffers_ui = try swapchain.create_framebuffers(container_resources.render_pass, &.{});
    defer framebuffers_ui.deinit(allocator);
    defer swapchain.deinit_framebuffers(framebuffers_ui);
    
    try init_ui_elements(&app_font);

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
            ash.window.Window.reset_input_values();
            app_ui_container.signal_reset_manual_input = false;
        }

        const command_buffer = try swapchain.get_next_command_buffer();
        try app_ui_container.draw(command_buffer, &swapchain, framebuffers_ui.items[swapchain.current_image_index]);

        try swapchain.present(vk_queues.get(.Presentation));
    }

    try vk_context.device.deviceWaitIdle();
    try app_ui_container.deinit();
}
