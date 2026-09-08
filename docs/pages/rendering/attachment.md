# 'attachment'

## Attachment (`struct`)

Structure storing information about an image attachment to be used as part of an `AttachmentBundle` or `Swapchain`.

### Fields

`info_image: vk.ImageCreateInfo` - Image creation info for the attachment. Certain fields (such as extent) are updated automatically when the attachment bundle is built.

`info_image_view: vk.ImageViewCreateInfo` - Image view creation info for the attachment.

`image_usage: vk_memory.VulkanAllocatorUsage` - Determines how the image attachment should be stored in memory.

`image: ?vk_memory.VulkanAllocator.VulkanImageAllocation = null` - The image. Do not set directly, unless you know what you're doing.

`image_view: ?vk.ImageView = null` - The image view. Do not set directly, unless you know what you're doing.

## AttachmentBundle (`struct`)

Stores a list of Vulkan image attachments. Can be used for refreshing (recreating) attachments for events such as window resizing.

### Fields

`allocator: *const std.mem.Allocator` - CPU allocator for the `ArrayList`.

`interface: *VkInterface` - `VkInterface` handle.

`vk_allocator: *vk_memory.VulkanAllocator` - Allocates Vulkan image resources.

`attachments: std.ArrayList(Attachment)` - `ArrayList` of all attachments.

### Public Functions

`add_attachment(self: *AttachmentBundle, attachment: Attachment) !void`

Adds an attachment to the bundle.

`build(self: *AttachmentBundle, resolution: vk.Extent3D) !void`

Creates or recreates the Vulkan attachment objects.

`deinit(self: *AttachmentBundle) void`

Frees all resources associated with the attachments.

`init(allocator: *const std.mem.Allocator, interface: *VkInterface, vk_allocator: *vk_memory.VulkanAllocator) !AttachmentBundle`

Initializes an empty attachment bundle.