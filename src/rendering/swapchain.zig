const std = @import("std");

const vk = @import("vulkan");
const glfw = @import("glfw");

const vkcontext = @import("vkcontext.zig");
const rp = @import("renderpass.zig");
const CommandBuffer = @import("commands.zig").CommandBuffer;

const Window = @import("window.zig").Window;

const vk_memory = @import("../utils/vkmemory.zig");

pub const SwapchainResource = struct
{
    info_image: vk.ImageCreateInfo,
    info_image_view: vk.ImageViewCreateInfo,

    image_usage: vk_memory.VulkanAllocatorUsage,

    image: vk_memory.VulkanAllocator.VulkanImageAllocation = undefined,
    image_view: vk.ImageView = undefined
};

/// Describes a VkSwapchainKHR object, or Vulkan swap chain. A swap chain is a 'chain', list, or queue, of images that Vulkan can render to.
/// The reason we want multiple images rather than just a single image is to prevent screen tearing, which is caused by rendering to and displaying
/// an image at the same time. This structure also contains a command buffer and some synchronization objects for each image.
pub const Swapchain = struct
{
    /// GLFW window handle.
    window: *c_long,
    /// Vulkan context.
    context: *vkcontext.VkContext,
    /// Vulkan allocator.
    vk_allocator: *vk_memory.VulkanAllocator,
    /// Command pool used to create the swap chain command buffers.
    command_pool: vk.CommandPool,

    /// VkSwapchainKHR handle.
    handle: vk.SwapchainKHR = undefined,

    /// Number of images contained in the swap chain.
    image_count: u32 = undefined,

    /// VkSurfaceFormatKHR of the swap chain, stores the format and color space of each image in the swap chain.
    format: vk.SurfaceFormatKHR = undefined,
    /// VkExtent2D of the swap chain, stores the size/resolution of each image.
    extent: vk.Extent2D = undefined,

    /// List of image views corresponding to each image in the swap chain. Used for acquiring the swap chain's framebuffers.
    image_views: std.ArrayList(vk.ImageView) = undefined,

    /// Fence to signal for when the swapchain finishes acquiring an image.
    fence_image_acquired: vk.Fence = undefined,

    /// Number of render stages the swapchain should expect each image to undergo. A render stage is essentially a call to the render() function.
    render_stages: u16,
    /// Current render stage being performed by the current image. This field is updated automatically when a call to render() is performed, and
    /// shouldn't be modified externally.
    current_render_stage: u16 = undefined,
    /// List of semaphore lists for each render stage, each semaphore list having one semaphore for each image to signal when their renders have finished.
    semaphores_render_stage_finished: []std.ArrayList(vk.Semaphore) = undefined,

    /// List of fences to signal when the command buffer is no longer pending.
    fences_command_buffers_finished: []std.ArrayList(vk.Fence) = undefined,

    /// Index of the currently acquired image. Set whenever acquire_image is called.
    current_image_index: u32 = 0,

    /// List of command buffers to use for rendering each render stage to each image. Do not access this field directly, instead use get_current_command_buffer.
    command_buffers: []std.ArrayList(CommandBuffer) = undefined,

    /// List of resources that the swapchain keeps track of. Includes things like depth buffers. Add with `add_resource`.
    resources: std.ArrayList(SwapchainResource) = undefined,

    pub const AcquireImageResult = enum
    {
        /// Image acquired successfully with no further issues.
        NoIssue,
        /// Failed to acquire image.
        Failure,
        /// Swapchain was recreated, framebuffers need to be refreshed.
        NewSwapchain
    };

    pub const SwapchainError = error
    {
        /// Swapchain is attempting to perform a render stage which doesn't exist.
        InvalidRenderStage,
        /// Swapchain is attempting to present an image before all render stages have been used.
        UnusedRenderStage,
    };

    /// Helper function to choose a preferred swap chain format.
    /// We have no need of any pixel resolution higher than B8G8R8. We also use the sRGB color space.
    fn choose_swapchain_format(sc_support: vkcontext.DeviceSwapchainSupport) vk.SurfaceFormatKHR
    {
        for(sc_support.supported_formats.items) |format|
        {
            if(format.format == vk.Format.b8g8r8a8_srgb and format.color_space == vk.ColorSpaceKHR.srgb_nonlinear_khr)
                return format;
        }

        return sc_support.supported_formats.items[0];
    }

    /// Helper function to choose a preferred swap chain presentation mode out of a list of presentation modes.
    /// Mailbox is generally the most efficient (also somewhat power-intensive), but FIFO is garunteed to be supported if the device supports Vulkan.
    fn choose_swapchain_presentation_mode(sc_support: vkcontext.DeviceSwapchainSupport) vk.PresentModeKHR
    {
        for(sc_support.supported_presentation_modes.items) |present_mode|
        {
            if(present_mode == vk.PresentModeKHR.mailbox_khr)
                return present_mode;
        }

        return vk.PresentModeKHR.fifo_khr;
    }

    /// Helper function to choose the swap chain's extent. Should match with the GLFW window's dimensions.
    fn choose_swapchain_extent(self: Swapchain, sc_support: vkcontext.DeviceSwapchainSupport) vk.Extent2D
    {
        // If the current extent width and height are equal to the maximum u32 limit, then we need to set the dimensions ourselves.
        if(sc_support.capabilities.current_extent.width != std.math.maxInt(u32))
        {
            return sc_support.capabilities.current_extent;
        }
        else
        {
            var width: c_int = undefined;
            var height: c_int = undefined;

            glfw.getFramebufferSize(self.window, &width, &height);

            var extent: vk.Extent2D = .{
                .width = @bitCast(width),
                .height = @bitCast(height)
            };

            extent.width = std.math.clamp(extent.width, sc_support.capabilities.min_image_extent.width, sc_support.capabilities.max_image_extent.width);
            extent.height = std.math.clamp(extent.height, sc_support.capabilities.min_image_extent.height, sc_support.capabilities.max_image_extent.height);

            return extent;
        }
    }

    /// Returns a list of handles to each image in the swap chain.
    fn retrieve_images(self: *Swapchain) ![]vk.Image
    {
        var image_count: u32 = undefined;
        _ = try self.context.device.getSwapchainImagesKHR(self.handle, &image_count, null);
        
        const image_list = try self.context.allocator.alloc(vk.Image, image_count);
        _ = try self.context.device.getSwapchainImagesKHR(self.handle, &image_count, @ptrCast(image_list));

        return image_list;
    }

    /// Creates the swap chain and image views.
    fn create_swapchain(self: *Swapchain) !void
    {
        var sc_support = try vkcontext.query_device_swapchain_support(self.context.instance, self.context.allocator, self.context.physical_device, self.context.window_surface);
        defer sc_support.deinit(self.context.allocator);

        self.format = Swapchain.choose_swapchain_format(sc_support);
        const presentation_mode = Swapchain.choose_swapchain_presentation_mode(sc_support);
        self.extent = self.choose_swapchain_extent(sc_support);

        // It's a good idea to use one more than the minimum image count, so that we can have at least 2 images to render to.
        self.image_count = sc_support.capabilities.min_image_count + 1;

        if(sc_support.capabilities.max_image_count > 0 and self.image_count > sc_support.capabilities.max_image_count)
            self.image_count = sc_support.capabilities.max_image_count;

        const image_usage: vk.ImageUsageFlags = .{
            .color_attachment_bit = true
        };

        const info_create: vk.SwapchainCreateInfoKHR = .{
            .surface = self.context.window_surface,
            .min_image_count = self.image_count,
            .image_format = self.format.format,
            .image_color_space = self.format.color_space,
            .image_extent = self.extent,
            .image_array_layers = 1, // Number of views in a multiview/stereo surface. In non-stereoscopic applications, this value is 1.
            .image_usage = image_usage,
            .image_sharing_mode = vk.SharingMode.exclusive, // Can be exclusive or concurrent. Concurrent is used when multiple Vulkan queues will access the images at once.
            .pre_transform = sc_support.capabilities.current_transform, // You can transform the images after rendering to them, if you wish.
            .composite_alpha = .{.opaque_bit_khr = true}, // Alpha compositing mode. For swap chains, I can't see this being any value other than opaque.
            .present_mode = presentation_mode,
            .clipped = .true, // This allows Vulkan to discard rendering operations done on parts of the surface which aren't visible (i.e. if the window is partially off-screen).
            .old_swapchain = @enumFromInt(0), // May aid in resource reuse if we're recreating the swap chain after a window resize.
        };

        self.handle = try self.context.device.createSwapchainKHR(&info_create, null);

        const images= try self.retrieve_images();
        defer self.context.allocator.free(images);

        // Image views describe an image, which parts of the image are accessible, how to access them, etc.
        // They are required for most Vulkan operations on images.

        // We also create semaphores and fences for each image to signal when each render is finished, and command buffers
        // for each image as well.

        self.semaphores_render_stage_finished = try self.context.allocator.alloc(std.ArrayList(vk.Semaphore), self.render_stages);
        self.fences_command_buffers_finished = try self.context.allocator.alloc(std.ArrayList(vk.Fence), self.render_stages);
        self.command_buffers = try self.context.allocator.alloc(std.ArrayList(CommandBuffer), self.render_stages);

        self.image_views = try std.ArrayList(vk.ImageView).initCapacity(self.context.allocator.*, images.len);
        try self.image_views.resize(self.context.allocator.*, images.len);

        for(0..self.render_stages) |i|
        {
            self.semaphores_render_stage_finished[i] = try std.ArrayList(vk.Semaphore).initCapacity(self.context.allocator.*, images.len);
            try self.semaphores_render_stage_finished[i].resize(self.context.allocator.*, images.len);

            self.fences_command_buffers_finished[i] = try std.ArrayList(vk.Fence).initCapacity(self.context.allocator.*, images.len);
            try self.fences_command_buffers_finished[i].resize(self.context.allocator.*, images.len);

            self.command_buffers[i] = try std.ArrayList(CommandBuffer).initCapacity(self.context.allocator.*, images.len);
            try self.command_buffers[i].resize(self.context.allocator.*, images.len);
        }

        for(images, 0..) |_, i|
        {
            const info_image_view: vk.ImageViewCreateInfo = .{
                .image = images[i],
                .view_type = vk.ImageViewType.@"2d",
                .format = self.format.format,
                // In case you aren't aware, "swizzling" refers to mixing up components of different vectors, i.e. passing (B,G,G,A) to an (R,G,B,A) vector.
                // In this case we don't do any swizzling.
                .components = .{
                    .r = vk.ComponentSwizzle.identity,
                    .g = vk.ComponentSwizzle.identity,
                    .b = vk.ComponentSwizzle.identity,
                    .a = vk.ComponentSwizzle.identity
                },
                // An ImageSubresourceRange describes which parts of the image are accessible, and what the image's purpose is.
                .subresource_range = .{
                    // The aspect mask identifies which "aspects" of the image are included in this ImageView.
                    .aspect_mask = .{
                        .color_bit = true
                    },
                    // Mipmap levels accessible in the view. We only have one mipmap level (i.e. we don't do any mipmapping at all).
                    .base_mip_level = 0,
                    .level_count = 1,
                    // Image array layers (specified earlier with vk.SwapchainCreateInfoKHR.image_array_layers) accessible to the ImageView.
                    .base_array_layer = 0,
                    .layer_count = 1
                }
            };

            self.image_views.items[i] = try self.context.device.createImageView(&info_image_view, null);

            const info_semaphore: vk.SemaphoreCreateInfo = .{};
            const info_fence: vk.FenceCreateInfo = .{
                .flags = .{
                    .signaled_bit = true
                }
            };

            for(0..self.render_stages) |j|
            {
                self.semaphores_render_stage_finished[j].items[i] = try self.context.device.createSemaphore(&info_semaphore, null);
                self.fences_command_buffers_finished[j].items[i] = try self.context.device.createFence(&info_fence, null);
                self.command_buffers[j].items[i] = try CommandBuffer.init(self.context, self.command_pool);
            }
        }

        // Finally, we create a fence that will signal when the next image is acquired.

        const info_fence: vk.FenceCreateInfo = .{
            .flags = .{
                .signaled_bit = true
            }
        };

        self.fence_image_acquired = try self.context.device.createFence(&info_fence, null);
        
        self.current_render_stage = 0;
    }

    /// Acquires the next image from the swap chain, and possibly recreates the swap chain if the window has been resized or the swap chain
    /// has otherwise expired. Sets the value of current_image_index to the index of the acquired image.
    pub fn acquire_next_image(self: *Swapchain) !AcquireImageResult
    {
        try self.context.device.resetFences(&.{ self.fence_image_acquired });
        var result = try self.context.device.acquireNextImageKHR(self.handle, std.math.maxInt(u64), .null_handle, self.fence_image_acquired);

        var window_width: c_long = undefined;
        var window_height: c_long = undefined;

        glfw.getFramebufferSize(self.window, &window_width, &window_height);

        const resized = window_width != self.extent.width or window_height != self.extent.height;
        const swapchain_expired = resized or result.result == .error_out_of_date_khr or result.result == .suboptimal_khr;

        if(swapchain_expired)
        {
            while(window_width == 0 or window_height == 0)
            {
                // Window is minimized - don't bother doing anything.
                glfw.getFramebufferSize(self.window, &window_width, &window_height);
                glfw.waitEvents();
            }

            try self.context.device.deviceWaitIdle();
            
            self.deinit(false);
            try self.create_swapchain();

            try self.context.device.resetFences(&.{ self.fence_image_acquired });
            result = try self.context.device.acquireNextImageKHR(self.handle, std.math.maxInt(u64), .null_handle, self.fence_image_acquired);
        }
        else if(result.result != .success)
        {
            // We probably shouldn't ever reach this point.
            return AcquireImageResult.Failure;
        }

        self.current_image_index = result.image_index;
        return if(swapchain_expired) AcquireImageResult.NewSwapchain else AcquireImageResult.NoIssue;
    }

    /// Add a resource to the swapchain. Resources are seperate images that are included with the swapchain, but aren't any of the swapchain images directly.
    /// Examples include a depth buffer, or some kind of G-buffer.
    pub fn add_resource(self: *Swapchain, resource: SwapchainResource) !void
    {
        try self.resources.append(self.context.allocator.*, resource);
        var sr = &self.resources.items[self.resources.items.len - 1];

        sr.info_image.extent = .{
            .width = self.extent.width,
            .height = self.extent.height,
            .depth = 1
        };

        sr.image = try self.vk_allocator.alloc_image_empty(sr.info_image, sr.image_usage);

        sr.info_image_view.image = sr.image.image;
        sr.image_view = try self.context.device.createImageView(&sr.info_image_view, null);
    }

    /// Clears all swapchain resources. Used when the swapchain needs to be refreshed, or during swapchain deinitialization.
    pub fn clear_resources(self: *Swapchain) void
    {
        for(self.resources.items) |*sr|
        {
            self.context.device.destroyImageView(sr.image_view, null);
            self.vk_allocator.free_image(sr.image) catch unreachable;
        }
    }

    /// Creates framebuffers using the swap chain's images (or image views) and associates them with a render pass.
    /// Includes swapchain resources as additional attachments to the framebuffer.
    pub fn create_framebuffers(self: *Swapchain, render_pass: *rp.RenderPass) !std.ArrayList(vk.Framebuffer)
    {
        // A framebuffer attaches an ImageView to a render pass.
        // Both framebuffers and render passes are actually considered legacy features now with Vulkan 1.4, where the paradigm has shifted to
        // "dynamic rendering," which doesn't use either.

        // Framebuffers are required to use render passes, as they represent certain memory attachments that a render pass needs to use. You
        // need a framebuffer not just for every image, but every render pass as well.

        const num_images = self.image_views.items.len;

        var framebuffers = try std.ArrayList(vk.Framebuffer).initCapacity(self.context.allocator.*, num_images);
        try framebuffers.resize(self.context.allocator.*, num_images);

        for(0..num_images) |i|
        {
            var attachments = try self.context.allocator.alloc(vk.ImageView, self.resources.items.len + 1);
            defer self.context.allocator.free(attachments);

            attachments[0] = self.image_views.items[i];
            for(1..attachments.len) |j|
            {
                attachments[j] = self.resources.items[j - 1].image_view;
            }

            // As you can see, creating them is rather straightforward.
            const info_framebuffer: vk.FramebufferCreateInfo = .{
                .render_pass = render_pass.render_pass,
                .attachment_count = @truncate(attachments.len),
                .p_attachments = @ptrCast(attachments),
                .width = self.extent.width,
                .height = self.extent.height,
                .layers = 1
            };

            framebuffers.items[i] = try self.context.device.createFramebuffer(&info_framebuffer, null);
        }

        return framebuffers;
    }

    /// Deinitializes the swap chain. Set `include_resources` to true if this is the final call to deinit, and not just part of a swapchain refresh operation.
    pub fn deinit(self: *Swapchain, include_resources: bool) void
    {
        for(self.image_views.items, 0..) |_, i|
        {
            for(0..self.render_stages) |j|
            {
                self.context.device.destroySemaphore(self.semaphores_render_stage_finished[j].items[i], null);
                self.context.device.destroyFence(self.fences_command_buffers_finished[j].items[i], null);
            }

            self.context.device.destroyImageView(self.image_views.items[i], null);
        }

        for(0..self.render_stages) |i|
        {
            self.semaphores_render_stage_finished[i].deinit(self.context.allocator.*);
            self.fences_command_buffers_finished[i].deinit(self.context.allocator.*);
            self.command_buffers[i].deinit(self.context.allocator.*);
        }

        self.context.allocator.free(self.semaphores_render_stage_finished);
        self.context.allocator.free(self.fences_command_buffers_finished);
        self.context.allocator.free(self.command_buffers);
     
        if(include_resources)
        {
            self.clear_resources();
            self.resources.deinit(self.context.allocator.*);
        }

        self.image_views.deinit(self.context.allocator.*);

        self.context.device.destroySwapchainKHR(self.handle, null);
        self.context.device.destroyFence(self.fence_image_acquired, null);
    }

    /// Deinitializes a list of framebuffers.
    pub fn deinit_framebuffers(self: *Swapchain, framebuffers: std.ArrayList(vk.Framebuffer)) void
    {
        for(0..framebuffers.items.len) |i|
        {
            self.context.device.destroyFramebuffer(framebuffers.items[i], null);
        }
    }

    /// Waits for the command buffer associated with the current image and render stage to return to a pending state, then returns it.
    pub fn get_next_command_buffer(self: *Swapchain) !*CommandBuffer
    {
        const index = self.current_image_index;
        const stage = self.current_render_stage;
        _ = try self.context.device.waitForFences(&.{ self.fences_command_buffers_finished[stage].items[index] }, .true, std.math.maxInt(u64));
        try self.context.device.resetFences(&.{ self.fences_command_buffers_finished[stage].items[index] });
        return &self.command_buffers[stage].items[self.current_image_index];
    }

    /// Creates the swap chain, along with its image views.
    pub fn init(window: *Window, context: *vkcontext.VkContext, vk_allocator: *vk_memory.VulkanAllocator, command_pool: vk.CommandPool, render_stages: u16) !Swapchain
    {
        std.debug.assert(render_stages > 0);

        var sc: Swapchain = .{
            .window = window.glfw_handle,
            .context = context,
            .vk_allocator = vk_allocator,
            .command_pool = command_pool,
            .render_stages = render_stages
        };

        try sc.create_swapchain();

        sc.resources = try .initCapacity(context.allocator.*, 0);

        return sc;
    }

    /// Submits a command to present the current image to Vulkan. The operation will wait for the current image's render_finished semaphore to be completed before executing.
    /// Other operations on the CPU may occur before the image is presented (such as acquiring the next image). present_queue must be a queue that supports presentation
    /// operations.
    pub fn present(self: *Swapchain, present_queue: vk.Queue) !void
    {
        if(self.current_render_stage < self.render_stages)
        {
            return SwapchainError.UnusedRenderStage;
        }

        const final_stage = self.render_stages - 1;
        const index = self.current_image_index;

        const info_present: vk.PresentInfoKHR = .{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&self.semaphores_render_stage_finished[final_stage].items[index]),
            .swapchain_count = 1,
            .p_swapchains = @ptrCast(&self.handle),
            .p_image_indices = @ptrCast(&index)
        };

        _ = try self.context.device.queuePresentKHR(present_queue, &info_present);

        self.current_render_stage = 0;
    }

    /// Refreshes all resources (recreates them with up-to-date extents). Must be called whenever the swapchain needs to be refreshed.
    pub fn refresh_resources(self: *Swapchain) !void
    {
        self.clear_resources();

        for(self.resources.items) |*sr|
        {
            sr.info_image.extent = .{
                .width = self.extent.width,
                .height = self.extent.height,
                .depth = 1
            };

            sr.image = try self.vk_allocator.alloc_image_empty(sr.info_image, sr.image_usage);

            sr.info_image_view.image = sr.image.image;
            sr.image_view = try self.context.device.createImageView(&sr.info_image_view, null);
        }
    }

    /// Submits a rendering command buffer to Vulkan, using the synchronization objects (fences and semaphores) provided by the swap chain and it's currently selected image.
    /// You will need to make sure you're referencing the correct image in the command buffer itself. Waits for the swap chain to finish acquiring the image before submitting
    /// the command buffer. render_queue should be a queue that supports graphics operations.
    pub fn render(self: *Swapchain, render_queue: vk.Queue) !void
    {
        if(self.current_render_stage == self.render_stages)
        {
            return SwapchainError.InvalidRenderStage;
        }

        const index = self.current_image_index;
        const stage = self.current_render_stage;

        var info_submit: vk.SubmitInfo = .{
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&self.command_buffers[stage].items[index].handle),
            .signal_semaphore_count = 1,
            .p_signal_semaphores = @ptrCast(&self.semaphores_render_stage_finished[self.current_render_stage].items[index])
        };

        const wait_stage: vk.PipelineStageFlags = .{
            .bottom_of_pipe_bit = true
        };

        if(self.current_render_stage > 0)
        {
            info_submit.wait_semaphore_count = 1;
            info_submit.p_wait_semaphores = @ptrCast(&self.semaphores_render_stage_finished[self.current_render_stage - 1].items[index]);
            info_submit.p_wait_dst_stage_mask = @ptrCast(&wait_stage);
        }
        else
        {
            _ = try self.context.device.waitForFences(&.{ self.fence_image_acquired }, .true, std.math.maxInt(u64));
        }

        try self.context.device.queueSubmit(render_queue, &.{ info_submit }, self.fences_command_buffers_finished[stage].items[index]);

        self.current_render_stage += 1;
    }
};

const vk_test = @import("../utils/testing/test_utils.zig");

const commands = @import("commands.zig");

test "Swapchain init"
{
    try glfw.init();
    defer glfw.terminate();

    var dba = vk_test.init_testing_allocator();
    defer vk_test.deinit_testing_allocator(&dba);

    const allocator = dba.allocator();

    var window = try vk_test.create_testing_window();
    defer window.destroy();

    var vk_context = try vk_test.create_testing_vk_context(&allocator, &window);
    defer vk_context.deinit();

    const pool = try commands.create_command_pool(&vk_context);
    defer vk_context.device.destroyCommandPool(pool, null);

    var swapchain = try Swapchain.init(window.glfw_handle, &vk_context, pool, 2);

    try std.testing.expect(swapchain.image_count >= 1);
    try std.testing.expect(swapchain.current_image_index == 0);
    try std.testing.expect(swapchain.render_stages == 2);
    try std.testing.expect(swapchain.current_render_stage == 0);
    try std.testing.expect(swapchain.extent.width == window.width);
    try std.testing.expect(swapchain.extent.height == window.height);

    swapchain.deinit();
}
