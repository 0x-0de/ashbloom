const std = @import("std");
const ash = @import("ashbloom");

const glfw = ash.glfw;
const vk = ash.vk;

const Window = ash.Window;

const VkContext = ash.VkContext;
const VulkanAllocator = ash.VulkanAllocator;

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

    vk_command_pool = try ash.commands.create_command_pool(&vk_context);

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

pub fn main() !void
{
    try ash.init_graphics();
    defer ash.deinit_graphics();

    var dba: std.heap.DebugAllocator(.{}) = .{};
    defer {
        const dba_result = dba.deinit();
        if(dba_result == .leak)
        {
            std.debug.print("Program terminating with {d} memory leaks.\n", .{@intFromEnum(dba_result)});
        }
    }

    allocator = dba.allocator();

    glfw.windowHint(glfw.ClientAPI, glfw.NoAPI);

    window = try .init(1280, 720, "Voxel demo");
    defer window.destroy();
    
    try init_vk_context();
    defer deinit_vk_context();

    while(!window.should_close())
    {
        glfw.pollEvents();
    }
}