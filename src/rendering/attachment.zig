const std = @import("std");
const ash = @import("../root.zig");

const vk = ash.vk;

const vk_memory = ash.vk_memory;

/// Structure storing information about an attachment to be used as part of an AttachmentBundle or Swapchain.
pub const Attachment = struct
{
    info_image: vk.ImageCreateInfo,
    info_image_view: vk.ImageViewCreateInfo,

    image_usage: vk_memory.VulkanAllocatorUsage,

    image: ?vk_memory.VulkanAllocator.VulkanImageAllocation = null,
    image_view: ?vk.ImageView = null
};

/// Stores a list of attachments. Can be used for refreshing (recreating) attachments for events such as window resizing.
pub const AttachmentBundle = struct
{
    allocator: *const std.mem.Allocator,

    vk_context: *ash.VkContext,
    vk_allocator: *vk_memory.VulkanAllocator,

    attachments: std.ArrayList(Attachment),

    pub fn deinit(self: *AttachmentBundle) void
    {
        for(self.attachments.items) |*att|
        {
            if(att.image != null)
            {
                self.vk_allocator.free_image(att.image.?) catch unreachable;
                self.vk_context.device.destroyImageView(att.image_view.?, null);
            }
        }

        self.attachments.deinit(self.allocator.*);
    }

    pub fn init(allocator: *const std.mem.Allocator, vk_context: *ash.VkContext, vk_allocator: *vk_memory.VulkanAllocator) !AttachmentBundle
    {
        return .{
            .allocator = allocator,
            .vk_context = vk_context,
            .vk_allocator = vk_allocator,
            .attachments = try .initCapacity(allocator.*, 0)
        };
    }

    pub fn add_attachment(self: *AttachmentBundle, attachment: Attachment) !void
    {
        try self.attachments.append(self.allocator.*, attachment);
    }

    pub fn build(self: *AttachmentBundle, resolution: vk.Extent3D) !void
    {
        for(self.attachments.items) |*att|
        {
            if(att.image != null)
            {
                self.vk_allocator.free_image(att.image.?) catch unreachable;
                self.vk_context.device.destroyImageView(att.image_view.?, null);
            }
            
            att.info_image.extent = .{
                .width = resolution.width,
                .height = resolution.height,
                .depth = resolution.depth
            };

            att.image = try self.vk_allocator.alloc_image_empty(att.info_image, att.image_usage);

            att.info_image_view.image = att.image.?.image;
            att.image_view = try self.vk_context.device.createImageView(&att.info_image_view, null);
        }
    }
};
