const std = @import("std");
const ash = @import("../root.zig");

const vk = ash.vk;

const vk_memory = ash.vk_memory;

/// Structure storing information about an image attachment to be used as part of an AttachmentBundle or Swapchain.
pub const Attachment = struct
{
    /// Image creation info for the attachment. Certain fields (such as extent) are updated automatically when the attachment bundle is built.
    info_image: vk.ImageCreateInfo,
    /// Image view creation info for the attachment.
    info_image_view: vk.ImageViewCreateInfo,

    /// Determines how the image attachment should be stored in memory.
    image_usage: vk_memory.VulkanAllocatorUsage,

    /// The image. Do not set directly, unless you know what you're doing.
    image: ?vk_memory.VulkanAllocator.VulkanImageAllocation = null,
    /// The image view. Do not set directly, unless you know what you're doing.
    image_view: ?vk.ImageView = null
};

/// Stores a list of Vulkan image attachments. Can be used for refreshing (recreating) attachments for events such as window resizing.
pub const AttachmentBundle = struct
{
    allocator: *const std.mem.Allocator,

    interface: *ash.VkInterface,
    vk_allocator: *vk_memory.VulkanAllocator,

    /// ArrayList of all attachments.
    attachments: std.ArrayList(Attachment),

    /// Frees all resources associated with the attachments.
    pub fn deinit(self: *AttachmentBundle) void
    {
        for(self.attachments.items) |*att|
        {
            if(att.image != null)
            {
                self.vk_allocator.free_image(att.image.?);
                self.interface.device.destroyImageView(att.image_view.?, null);
            }
        }

        self.attachments.deinit(self.allocator.*);
    }

    /// Initializes an empty attachment bundle.
    pub fn init(allocator: *const std.mem.Allocator, interface: *ash.VkInterface, vk_allocator: *vk_memory.VulkanAllocator) !AttachmentBundle
    {
        return .{
            .allocator = allocator,
            .interface = interface,
            .vk_allocator = vk_allocator,
            .attachments = try .initCapacity(allocator.*, 0)
        };
    }

    /// Adds an attachment to the bundle.
    pub fn add_attachment(self: *AttachmentBundle, attachment: Attachment) !void
    {
        try self.attachments.append(self.allocator.*, attachment);
    }

    /// Creates, or recreates the Vulkan attachment objects.
    pub fn build(self: *AttachmentBundle, resolution: vk.Extent3D) !void
    {
        for(self.attachments.items) |*att|
        {
            if(att.image != null)
            {
                self.vk_allocator.free_image(att.image.?);
                self.interface.device.destroyImageView(att.image_view.?, null);
            }
            
            att.info_image.extent = .{
                .width = resolution.width,
                .height = resolution.height,
                .depth = resolution.depth
            };

            att.image = try self.vk_allocator.alloc_image_empty(att.info_image, att.image_usage);

            att.info_image_view.image = att.image.?.image;
            att.image_view = try self.interface.device.createImageView(&att.info_image_view, null);
        }
    }
};
