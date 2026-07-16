const std = @import("std");
const print = std.debug.print;

const ash = @import("ashbloom");

const vk = ash.vk;
const glfw = ash.glfw;

const ui = ash.ui;
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

var window: ash.ABWindow = undefined;

var vk_context: VkContext = undefined;
var vk_allocator: VulkanAllocator = undefined;

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

    vk_command_pool = try ash.commands.create_command_pool(&vk_context, @truncate(queue_families.graphics_family_index.?));

    vk_allocator = try VulkanAllocator.init(&vk_context, &allocator, .{
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
var app_font: Font = undefined;

/// Location of the trash icon being added to the UI container's texture atlas.
var icon_trash: TextureAtlas2D.TextureSuballocation = undefined;

/// Height of the todo item element.
const todo_height: f32 = 50;

/// Data required to create a new todo item.
const TodoItem = struct
{
    name: []u32,
    index: u32
};

/// Updates the space values of the list panel, called when items are added to or removed from the panel.
/// If we're adding an element, `adding` should be true, otherwise false.
fn set_todo_list_scroll(adding: bool) !void
{
    var todo_list_lineage: [2]usize = .{0, 2};
    const todo_list = try app_ui_container.get_element(todo_list_lineage[0..2]);

    // Getting the boundary values of the todo list.
    const list_bounds = try app_ui_container.get_element_bounds(todo_list.lineage.?);

    // The "cut_bounds" are the boundaries of the list as they appear on screen, while the "draw_bounds" are the actual, scrollable boundaries of the list.
    // So "min_height" would be the minimum height necessary for the panel to be scrollable.
    const min_height = list_bounds.cut_bounds.scl_y;
    // While "prev_height" would just be the last actual height, either the same as cut_bounds.scl_y or space.scl_y if it's larger than cut_bounds.scl_y.
    const prev_height = list_bounds.draw_bounds.scl_y;

    // Gets the total height of all the todo item elements.
    var height = @as(f32, @floatFromInt(todo_list.children.items.len - 1)) * todo_height;
    // This function is called before any elements can get removed, so I have to manually subtract the removed element's height if it's getting removed.
    if(!adding) height -= todo_height;

    // If the projected height of the todo list items is less than the minimum height (defined by cut_bounds), we set the space to cut bounds so that the list panel
    // still remains the same height, but isn't scrollable anymore.
    if(height < min_height) height = min_height;
    
    todo_list.space.scl_x = list_bounds.cut_bounds.scl_x; // Probably not necessary.
    todo_list.space.scl_y = height;

    // Now all that remains is to update the scroll *position*.
    const diff = height - prev_height;

    if(height == min_height)
    {
        // If the list panel is no longer scrollable, I set the scroll position to 0.
        todo_list.space.pos_y = 0;
    }
    else if(adding)
    {
        // If the list panel is being added to, we add the difference to the scroll position (moves the scrollbar down).
        todo_list.space.pos_y += diff;
    }
    else
    {
        // If the list panel is being removed from, by default the scroll position would appear to move up (since the scale goes down) but I prevent that here.
        todo_list.space.pos_y += diff;
        if(todo_list.space.pos_y < 0) todo_list.space.pos_y = 0;
    }
}

/// Callback for pressing any todo item delete button.
fn callback_delete_todo_item(e: *ui.Element) !void
{
    // The todo item that ought to be deleted is the parent of the delete button that was pressed.
    const item = e.parent.?;

    // I set the delete signal stored in the todo item element to true.
    var signal = true;
    misc.memcpy_anonymous(item.data.?.ptr + @sizeOf(u32), &signal, @sizeOf(bool));
    
    // 
    try set_todo_list_scroll(false);
    app_ui_container.signal_rebuild = true;
}

/// Creates a todo item element.
fn create_todo_item(item: TodoItem) !*ui.Element
{
    // Similarly to the provided factory functions in ui_basic, I allocate a new Element struct.
    const e = try allocator.create(ui.Element);

    // Initializing this element as a regular colored quad.
    e.* = try ui.Element.init(&allocator, .Color, .{
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

    // Now, I allocate some memory to its data pointer to store some information specific to the todo item.
    // I store the index of the item, as well as a flag which is set if the item should be deleted.
    e.data = try allocator.alloc(u8, @sizeOf(u32) + @sizeOf(bool));

    // Setting the values of the data.
    var item_alias = item;
    misc.memcpy_anonymous(e.data.?.ptr, &item_alias.index, @sizeOf(u32));

    var false_alias = false;
    misc.memcpy_anonymous(e.data.?.ptr + @sizeOf(u32), &false_alias, @sizeOf(bool));

    // Now, I add the actual user elements. First, a checkbox to signal whether the task has been completed.
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

    // Then, the text label for the todo item.
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

    // And finally, a button to delete the item.
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
        .press_callback = callback_delete_todo_item // When pressed, callback_delete_todo_item is called.
    });

    // This button has an icon, which I added to the texture atlas of the UI container when first initializing it.
    // This icon is added to the button.
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

/// Callback function for when the todo list panel gets rebuilt.
/// Handles positioning and possible deletion all of the list items in the panel.
fn todo_list_rebuild_callback(e: *ui.Element, data: ui.ContainerInputData) !void
{
    _ = data;

    // If there are no elements in the panel, there's nothing to do.
    if(e.children.items.len == 0) return;

    const item_index = e.children.items.len - 1;

    // We need to manually activate the window resize callback function to make sure the text is laid out properly.
    var lineage: [5]usize = .{0, 2, item_index, 1, 0};
    const text_item = try app_ui_container.get_element(lineage[0..5]);

    try text_item.force_callback(.WindowResize);

    // We start with element 1 because element 0 is the list panel's scrollbar.
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

    // Updating remaining todo element positions.
    for(1..e.children.items.len) |i|
    {
        const v = @as(f32, @floatFromInt(i - 1));

        const child = e.children.items[i];
        child.placement.absolute_offset.pos_y = -v * todo_height;
    }
}

/// Creates a new todo element and adds it to the list panel.
fn new_todo(e: *ui.Element) !void
{
    _ = e;

    // Getting a pointer to the todo list.
    var todo_list_lineage: [2]usize = .{0, 2};
    const todo_list = try app_ui_container.get_element(todo_list_lineage[0..2]);

    // Getting a pointer to the textfield element.
    var textfield_lineage: [2]usize = .{0, 0};
    const textfield = try app_ui_container.get_element(textfield_lineage[0..2]);

    // Getting the text in the textfield.
    const todo_item_title = ui_basic.get_textfield_text(textfield);

    // Creating the actual todo item element, and adding it to the panel.
    const todo_item = try create_todo_item(.{ .name = todo_item_title, .index = @truncate(todo_list.children.items.len) });
    try todo_list.add_and_dispose(todo_item);

    // Updates the todo list scroll values.
    try set_todo_list_scroll(true);

    // Signal to the UI container to ignore any oncoming callbacks for the next tick (prevents crashes), and then rebuild.
    // This will inevitably lead to todo_list_rebuild_callback being called.
    app_ui_container.signal_ignore_callbacks = true;
    app_ui_container.signal_rebuild = true;
}

/// Creates and adds the main UI elements (usually serving as containers for other elements).
fn init_ui_main_elements() !void
{
    // Initial background element. Serves no purpose other than to give the application a background color and serve as a container for
    // every other UI element in the application.
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

    // Textfield element where the user can define new tasks.
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

    // Enter or "Add todo" button, which is used to push the new task defined in the textfield to the list.
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
        .press_callback = new_todo // This button calls new_todo when pressed.
    });

    // "Add todo" text used to label the enter button.
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

    // Each "create_XXX" function in the ui_basic theme allocates a structure which must be freed.
    // The "Element.add" function adds a copy of that allocated element (another allocation) to the container.
    // I use "add_and_dispose" which adds that copy, but then deinitializes/frees the original. It's useful when you only need 1 copy of something.
    try enter_button.add_and_dispose(enter_button_text);
    enter_unicode.deinit(allocator);

    // List panel, serves as a container for all added tasks.
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

    // The "space" field is used to define an absolute space which the stored UI elements can fit into.
    // Used for defining a scrolling space.
    list_panel.space = .{
        .pos_x = 0,
        .pos_y = 0,
        .scl_x = 0,
        .scl_y = 0
    };

    // Scrollbar for the list panel.
    const scrollbar = try ui_basic.create_scrollbar(&allocator);

    // Adding callbacks to the list panel.
    // When the list panel needs to be rebuilt, todo_list_rebuild_callback is called.
    try list_panel.add_callback(.Rebuild, todo_list_rebuild_callback);
    // When the list panel is scrolled, Ashbloom UI has a "default callback" which updates the positions of the child elements.
    try list_panel.add_callback(.Scroll, ui.default_scroll_callback);

    // Adding the scrollbar to the list panel.
    try list_panel.add_and_dispose(scrollbar);

    // Adding the outgoing elements to the background element.
    try background.add_and_dispose(enter_textfield);
    try background.add_and_dispose(enter_button);
    try background.add_and_dispose(list_panel);

    // Adding the background element to the UI container.
    try app_ui_container.add_and_dispose(background);
}

pub fn main() !void
{
    // Setting up the CPU allocator.
    var dba: std.heap.DebugAllocator(.{}) = .{};
    defer {
        const dba_result = dba.deinit();
        if(dba_result == .leak)
        {
            print("Program terminating with {d} memory leaks.\n", .{@intFromEnum(dba_result)});
        }
    }

    allocator = dba.allocator();

    // Initializing ashbloom (which also initializes GLFW).
    try ash.init_graphics(&allocator);
    defer ash.deinit_graphics();

    // This is mandatory for Vulkan projects, since GLFW is primed to use OpenGL.
    glfw.windowHint(glfw.ClientAPI, glfw.NoAPI);

    // Creating the window.
    window = try .init(1280, 720, "Todo");
    defer window.destroy();

    // Querying the host machine for available system fonts. This function is supported on both Windows and Linux (Ubuntu) devices.
    // For a more platform-agnostic solution, it's suggested to include a .ttf or .otf file in the project directory to load directly.
    const system_fonts = try ash.misc.enumerate_system_fonts(&allocator);

    // Searching for some preferred fonts. Arial should be installed on all modern Windows devices, and Liberation Sans should be on all Ubuntu devices.
    const names = [_][]const u8{"bahnschrift", "arial", "LiberationSans-Regular"};
    const names_slc: []const []const u8 = &names;

    // Returns the path of the first available font in the list (or an error if no font is available).
    const font_entry = try ash.misc.search_font_entries(system_fonts, names_slc);

    // Initialize the Vulkan context and allocator objects.
    try init_vk_context();
    defer deinit_vk_context();

    // Initialize the swapchain.
    var swapchain = try Swapchain.init(&window, &vk_context, &vk_allocator, vk_command_pool, 1);
    defer swapchain.deinit(true);

    // Initialize Ashbloom's Vulkan UI system.
    try ui.init();
    defer ui.deinit();

    // Create a UI container object. This object is the top-most container for a UI system.
    app_ui_container = try ui.Container.init(&vk_context, &vk_allocator);
    
    // Create a font object, using the font path I queried above, with a pixel size of 36. I attach the font to the UI container's existing texture atlas,
    // so any character glyph textures that get loaded are sent to the UI container's texture atlas.
    app_font = try Font.init(&vk_context, &vk_allocator, font_entry.path, 36, &app_ui_container.texture_atlas);
    defer app_font.deinit();

    // Loading the trash icon texture for the delete button, and adding it to the UI container's texture atlas.
    // Any textures that should be used as part of the UI must be loaded into the UI container's texture atlas.
    var trash_texture: Texture2D = try .init(&vk_context, &vk_allocator, "../../res/trash.bmp", .Subtexture);
    icon_trash = try app_ui_container.texture_atlas.add_texture(&trash_texture);
    trash_texture.deinit();

    // With the UI resources sufficiently initialized, I can clear some resources used to query them.
    for(system_fonts, 0..) |_, i|
    {
        system_fonts[i].deinit(&allocator);
    }
    allocator.free(system_fonts);

    // With all of the basic UI resources having been created, it's time to tether them to a specific "theme."
    // A "theme" in Ashbloom UI terms is a collection of element factories and rendering resources used to create and draw the UI elements.
    // Ashbloom provides its own theme ("ui_basic"), which essentially serves as an "immediate mode" for the system's UI.
    //
    // Every UI theme initializes a "render instance," which is a collection of Vulkan rendering resources required to draw the UI instance tree,
    // including a graphics pipeline which itself includes a set of pre-compiled shaders and descriptors, alongside a render pass.
    var container_resources = try ui_basic.init_render_instance(&vk_context, &vk_allocator, swapchain, app_ui_container, null, vk_queues.get(.Graphics));
    defer container_resources.deinit(vk_context);
    app_ui_container.set_render_instance(container_resources);

    // Creating the framebuffers necessary for the UI's render pass.
    var framebuffers_ui = try swapchain.create_framebuffers(container_resources.render_pass, &.{});
    defer framebuffers_ui.deinit(allocator);
    defer swapchain.deinit_framebuffers(framebuffers_ui);

    // Create all of the main UI elements for the program.
    try init_ui_main_elements();

    // One last bit of configuration required is to set the width and height of the container, which in most cases should be the size of the window.
    var fb_size = window.get_framebuffer_size();

    try app_ui_container.set_bounds(0, 0, @floatFromInt(fb_size.width), @floatFromInt(fb_size.height));
    try app_ui_container.build();

    var timer: f64 = glfw.getTime();
    var frames: u32 = 0;

    while(!window.should_close())
    {
        // Simple FPS timer.
        if(glfw.getTime() - timer > 1.0)
        {
            ash.print_stdout("FPS: {d}\n", .{frames});
            frames = 0;
            timer = glfw.getTime();
        }

        const prev_window_size: vk.Extent2D = .{
            .width = fb_size.width,
            .height = fb_size.height
        };

        glfw.pollEvents();

        // Load the next swapchain image.
        const acquire_result = try swapchain.acquire_next_image();
        if(acquire_result == .NewSwapchain)
        {
            swapchain.deinit_framebuffers(framebuffers_ui);
            framebuffers_ui.deinit(allocator);
            framebuffers_ui = try swapchain.create_framebuffers(container_resources.render_pass, &.{});
        }

        fb_size = window.get_framebuffer_size();

        // If the window size has been changed, update the boundaries of the UI container.
        if(fb_size.width != prev_window_size.width or fb_size.height != prev_window_size.height)
        {
            try app_ui_container.set_bounds(0, 0, @floatFromInt(fb_size.width), @floatFromInt(fb_size.height));
        }

        // Gets all user input information (mouse buttons/scrolling, key inputs, text) and puts it into a single structure.
        const container_input = window.get_ui_container_input();

        // "Updates" all UI elements in the container (handles all callbacks other than the ones which aren't reliant on user input (such as the child add/remove callbacks)).
        try app_ui_container.update(container_input);

        // Resets all input values if the need arises. Must happen because of the way GLFW handles certain input events like mouse scrolling.
        if(app_ui_container.signal_reset_manual_input)
        {
            ash.window.Window.reset_input_values();
            app_ui_container.signal_reset_manual_input = false;
        }

        // Drawing the UI.
        const command_buffer = try swapchain.get_next_command_buffer();
        try app_ui_container.draw(command_buffer, &swapchain, framebuffers_ui.items[swapchain.current_image_index]);

        // Presenting the UI.
        try swapchain.present(vk_queues.get(.Presentation));

        frames += 1;
    }

    // Waits for all latent Vulkan operations to finish before deinitializing anything.
    try vk_context.device.deviceWaitIdle();

    try app_ui_container.deinit();
}
