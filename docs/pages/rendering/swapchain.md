# `swapchain`

## Swapchain (`struct`)

### Fields

`window: *c_long` - GLFW window handle.

`surface: vk.SurfaceKHR` - Handle to the window surface.

`interface: *vkcontext.VkInterface` - VkInterface used to create this swapchain.

`vk_allocator: *vk_memory.VulkanAllocator` - Vulkan allocator used to allocate data for attachments.

`command_pool: vk.CommandPool` - Command pool used to create the swap chain command buffers.

`handle: vk.SwapchainKHR = undefined` - `VkSwapchainKHR` handle created during initialization.

`image_count: u32 = undefined` - Number of images contained in the swap chain, set during initialization.

`format: vk.SurfaceFormatKHR = undefined` - VkSurfaceFormatKHR of the swap chain, stores the format and color space of each image in the swap chain.

`extent: vk.Extent2D = undefined` - VkExtent2D of the swap chain, stores the size/resolution of each image.

`image_views: std.ArrayList(vk.ImageView) = undefined` - List of image views corresponding to each image in the swap chain. Used for acquiring the swap chain's framebuffers.

`fence_image_acquired: vk.Fence = undefined` - Fence to signal for when the swapchain finishes acquiring an image.

`render_stages: u16` - Number of render stages the swapchain should expect each image to undergo. A render stage is essentially a call to the render() function.

`current_render_stage: u16 = undefined` - Current render stage being performed by the current image. This field is updated automatically when a call to render() is performed, and shouldn't be modified externally.

`last_render_stage: ?u16 = null` - The last render stage which was actually rendered. Incremented when a call to render(...) is performed.

`semaphores_render_stage_finished: []std.ArrayList(vk.Semaphore) = undefined` - List of semaphore lists for each render stage, each semaphore list having one semaphore for each image to signal when their renders have finished.

`fences_command_buffers_finished: []std.ArrayList(vk.Fence) = undefined` - List of fences to signal when the command buffer is no longer pending.

`current_image_index: u32 = 0` - Index of the currently acquired image. Set whenever acquire_image is called.

`command_buffers: []std.ArrayList(CommandBuffer) = undefined` - List of command buffers to use for rendering each render stage to each image. Do not access this field directly, instead use get_current_command_buffer.

`attachments: std.ArrayList(att.Attachment) = undefined` - List of attachments that the swapchain keeps track of. Includes things like depth buffers. Add with `add_resource`.

### Enums

#### `AcquireImageResult`

**NoIssue** - Image acquired successfully with no further issues.

**Failure** - Failed to acquire image.

**NewSwapchain** - Swapchain was recreated, framebuffers need to be refreshed.

### Errors

#### `SwapchainError`

**InvalidRenderStage** - Swapchain is attempting to perform a render stage which doesn't exist.

**UnusedRenderStage** - Swapchain is attempting to present an image before all render stages have been used.

### Public Functions

**`acquire_next_image(self: *Swapchain) !AcquireImageResult`**

Acquires the next image from the swap chain, and possibly recreates the swap chain if the window has been resized or the swap chain has otherwise expired. Sets the value of `current_image_index` to the index of the acquired image.

**`add_attachment(self: *Swapchain, attachment: att.Attachment) !void`**

Add a resource to the swapchain. Attachments are seperate images that are included with the swapchain, but aren't any of the swapchain images directly. Examples include a depth buffer, or some kind of G-buffer.

**`clear_attachments(self: *Swapchain) void`**

Clears all swapchain attachments. Used when the swapchain needs to be refreshed, or during swapchain deinitialization.

**`create_framebuffers(self: *Swapchain, render_pass: *rp.RenderPass, attachment_indices: []const u8) !std.ArrayList(vk.Framebuffer)`**

Creates framebuffers using the swap chain's images (or image views) and associates them with a render pass. Includes swapchain attachments as additional attachments to the framebuffer.

**`deinit(self: *Swapchain, include_attachments: bool) void`**

Deinitializes the swap chain. Set `include_attachments` to true if this is the final call to deinit, and not just part of a swapchain refresh operation.

**`deinit_framebuffers(self: *Swapchain, framebuffers: std.ArrayList(vk.Framebuffer)) void`**

Deinitializes a list of framebuffers.

**`get_attachment(self: Swapchain, attachment_index: usize) *att.Attachment`**

Returns a pointer to the attachment at the `attachment_index`.

**`get_current_image_view(self: Swapchain) *vk.ImageView`**

Returns a pointer to the currently active image view.

**`get_next_command_buffer(self: *Swapchain) !*CommandBuffer`**

Waits for the command buffer associated with the current image and render stage to return to a pending state, then returns it.

**`init(window: *Window, interface: *vkcontext.VkInterface, vk_allocator: *vk_memory.VulkanAllocator, surface: vk.SurfaceKHR, command_pool: vk.CommandPool, render_stages: u16) !Swapchain`**

Initializes the swap chain.

**`present(self: *Swapchain, present_queue: vk.Queue) !void`**

Submits a command to present the current image to Vulkan. The operation will wait for the current image's render_finished semaphore to be completed before executing. Other operations on the CPU may occur before the image is presented (such as acquiring the next image). present_queue must be a queue that supports presentation operations.

**`refresh_attachments(self: *Swapchain) !void`**

Refreshes all attachments (recreates them with up-to-date extents). Must be called whenever the swapchain needs to be refreshed.

**`render(self: *Swapchain, render_queue: vk.Queue) !void`**

Submits a rendering command buffer to Vulkan, using the synchronization objects (fences and semaphores) provided by the swap chain and it's currently selected image. You will need to make sure you're referencing the correct image in the command buffer itself. Waits for the swap chain to finish acquiring the image before submitting the command buffer. render_queue should be a queue that supports graphics operations.

**`skip_render_stage(self: *Swapchain, render_queue: vk.Queue) !void`**

Skips the current render stage this frame.

### Private Functions

**`choose_swapchain_format(sc_support: vkcontext.DeviceSwapchainSupport) vk.SurfaceFormatKHR`**

Helper function to choose a preferred swap chain format. Most monitors have no need of any pixel resolution higher than B8G8R8. Ashbloom also prefers the sRGB color space.

**`choose_swapchain_presentation_mode(sc_support: vkcontext.DeviceSwapchainSupport) vk.PresentModeKHR`**

Helper function to choose a preferred swap chain presentation mode out of a list of presentation modes. Mailbox is generally the most efficient (also somewhat power-intensive), but FIFO is garunteed to be supported if the device supports Vulkan.

**`choose_swapchain_extent(self: Swapchain, sc_support: vkcontext.DeviceSwapchainSupport) vk.Extent2D`**

Helper function to choose the swap chain's extent. Should match with the GLFW window's dimensions.

**`create_swapchain(self: *Swapchain) !void`**

Creates the swap chain, along with its image views.

**`retrieve_images(self: *Swapchain) ![]vk.Image`**

Returns a list of handles to each image in the swap chain.