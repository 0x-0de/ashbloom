const std = @import("std");
const print = std.debug.print;

const glfw = @import("glfw");
const vk = @import("vulkan");

const vkcontext = @import("vkcontext.zig");
const RenderPass = @import("renderpass.zig").RenderPass;
const Pipeline = @import("pipeline.zig").Pipeline;

/// Creates a command pool to allocate graphics command buffers.
pub fn create_command_pool(vkc: *vkcontext.VkContext) !vk.CommandPool
{
    const queue_family = try vkc.get_physical_device_queue_families(vkc.physical_device);

    const info_command_pool: vk.CommandPoolCreateInfo = .{
        .flags = .{
            .reset_command_buffer_bit = true
        },
        .queue_family_index = @truncate(queue_family.graphics_family_index.?)
    };

    return try vkc.device.createCommandPool(&info_command_pool, null);
}

/// Uses an available command pool to create a single vk.CommandBuffer object to be executed once.
pub fn begin_single_time_command_buffer(context: *vkcontext.VkContext, command_pool: vk.CommandPool) !vk.CommandBuffer
{
    const info_alloc: vk.CommandBufferAllocateInfo = .{
        .level = .primary,
        .command_pool = command_pool,
        .command_buffer_count = 1
    };

    var command_buffer: vk.CommandBuffer = undefined;
    try context.device.allocateCommandBuffers(&info_alloc, @ptrCast(&command_buffer));

    const info_begin: vk.CommandBufferBeginInfo = .{
        .flags = .{
            .one_time_submit_bit = true
        }
    };

    try context.device.beginCommandBuffer(command_buffer, &info_begin);

    return command_buffer;
}

/// Finishes recording and submits a single-time command buffer.
pub fn end_and_submit_single_time_command_buffer(context: *vkcontext.VkContext, command_pool: vk.CommandPool, command_buffer: vk.CommandBuffer, queue: vk.Queue) !void
{
    try context.device.endCommandBuffer(command_buffer);

    const info_submit: vk.SubmitInfo = .{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&command_buffer)
    };

    try context.device.queueSubmit(queue, 1, @ptrCast(&info_submit), .null_handle);
    try context.device.queueWaitIdle(queue);

    context.device.freeCommandBuffers(command_pool, 1, @ptrCast(&command_buffer));
}

/// Essentially wraps a vk.CommandBuffer object and provides some helper functions for common commands, such as beginning/ending
/// buffer recording, drawing, resetting, binding a graphics pipeline, and so on.
pub const CommandBuffer = struct
{
    /// Vulkan context.
    vkc: *vkcontext.VkContext,

    /// vk.CommandBuffer handle.
    handle: vk.CommandBuffer = undefined,

    /// Sets the command buffer to the recording state. Must be called before recording other commands to the buffer.
    pub fn begin_recording(self: *CommandBuffer) !void
    {
        const info_begin: vk.CommandBufferBeginInfo = .{
            .flags = .{}
        };

        try self.vkc.device.beginCommandBuffer(self.handle, &info_begin);
    }

    /// Activates a render pass and binds it to a framebuffer. You can also provide a render area for the render pass, as 'extent'.
    pub fn cmd_begin_render_pass(self: *CommandBuffer, render_pass: *RenderPass, framebuffer: vk.Framebuffer, extent: vk.Extent2D, clear_color: [4]f32) void
    {
        const clear_value: vk.ClearValue = .{
            .color = .{
                .float_32 = clear_color
            }
        };

        const info_begin_rp: vk.RenderPassBeginInfo = .{
            .render_pass = render_pass.render_pass,
            .framebuffer = framebuffer,
            .render_area = .{
                .extent = extent,
                .offset = .{
                    .x = 0,
                    .y = 0
                }
            },
            .clear_value_count = 1,
            .p_clear_values = @ptrCast(&clear_value),
        };

        self.vkc.device.cmdBeginRenderPass(self.handle, &info_begin_rp, vk.SubpassContents.@"inline");
    }

    /// Binds a Vulkan pipeline. All subsequent commands will be 
    pub fn cmd_bind_pipeline(self: *CommandBuffer, pipeline: *Pipeline) void
    {
        self.vkc.device.cmdBindPipeline(self.handle, vk.PipelineBindPoint.graphics, pipeline.pipeline);
    }

    /// Binds a descriptor set.
    pub fn cmd_bind_descriptor_set(self: *CommandBuffer, pipeline: *Pipeline, descriptor_set: *vk.DescriptorSet) void
    {
        self.vkc.device.cmdBindDescriptorSets(self.handle, .graphics, pipeline.pipeline_layout.?, 0, 1, @ptrCast(descriptor_set), 0, null);
    }

    /// Binds an index buffer. This will apply to the target of the next draw command. The buffer MUST be a list of 16-bit unsigned integers.
    pub fn cmd_bind_index_buffer(self: *CommandBuffer, buffer: *vk.Buffer, offset: vk.DeviceSize) void
    {
        self.vkc.device.cmdBindIndexBuffer(self.handle, buffer.*, offset, .uint16);
    }

    /// Binds a vertex buffer. This will be the target of the next draw command.
    pub fn cmd_bind_vertex_buffer(self: *CommandBuffer, buffer: *vk.Buffer, offset: *vk.DeviceSize) void
    {
        self.vkc.device.cmdBindVertexBuffers(self.handle, 0, 1, @ptrCast(buffer), @ptrCast(offset));
    }

    /// Sets the scissor of the current draw operation. Used for graphics pipelines with dynamic viewports and scissors.
    pub fn cmd_set_scissor(self: *CommandBuffer, bounds: vk.Rect2D) void
    {
        const scissor: vk.Rect2D = .{
            .offset = bounds.offset,
            .extent = bounds.extent
        };

        self.vkc.device.cmdSetScissor(self.handle, 0, 1, @ptrCast(&scissor));
    }

    /// Sets the viewport of the screen. Used for graphics pipelines with dynamic viewports and scissors.
    pub fn cmd_set_viewport(self: *CommandBuffer, bounds: vk.Rect2D, min_depth: f32, max_depth: f32) void
    {
        const viewport: vk.Viewport = .{
            .x = bounds.offset.x,
            .y = bounds.offset.y,
            .width = @floatFromInt(bounds.extent.width),
            .height = @floatFromInt(bounds.extent.height),
            .min_depth = min_depth,
            .max_depth = max_depth
        };

        self.vkc.device.cmdSetViewport(self.handle, 0, 1, @ptrCast(&viewport));
    }

    /// Sets the viewport of the screen, assuming that the top-left corner of the viewport is (0, 0), and the min and max depth are -1 and
    /// 1 respectively. Used for graphics pipelines with dynamic viewports and scissors.
    pub fn cmd_set_viewport_full(self: *CommandBuffer, extent: vk.Extent2D) void
    {
        const viewport: vk.Viewport = .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(extent.width),
            .height = @floatFromInt(extent.height),
            .min_depth = 0,
            .max_depth = 1
        };

        self.vkc.device.cmdSetViewport(self.handle, 0, 1, @ptrCast(&viewport));
    }

    /// Sets both the viewport and scissor to cover the entire area of extent. Used for graphics pipelines with dynamic viewports and scissors.
    pub fn cmd_set_viewport_scissor_full(self: *CommandBuffer, extent: vk.Extent2D) void
    {
        const viewport: vk.Viewport = .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(extent.width),
            .height = @floatFromInt(extent.height),
            .min_depth = 0,
            .max_depth = 1
        };

        self.vkc.device.cmdSetViewport(self.handle, 0, 1, @ptrCast(&viewport));

        const scissor: vk.Rect2D = .{
            .offset = .{
                .x = 0,
                .y = 0
            },
            .extent = extent
        };

        self.vkc.device.cmdSetScissor(self.handle, 0, 1, @ptrCast(&scissor));
    }

    /// Draws a certain number of vertices and instances. Does not apply indices.
    pub fn cmd_draw(self: *CommandBuffer, vertex_count: u32, instance_count: u32) void
    {
        self.vkc.device.cmdDraw(self.handle, vertex_count, instance_count, 0, 0);
    }

    /// Draws a certain number of indices and instances.
    pub fn cmd_draw_indexed(self: *CommandBuffer, index_count: u32, instance_count: u32) void
    {
        self.vkc.device.cmdDrawIndexed(self.handle, index_count, instance_count, 0, 0, 0);
    }

    /// Ends the render pass.
    pub fn cmd_end_render_pass(self: *CommandBuffer) void
    {
        self.vkc.device.cmdEndRenderPass(self.handle);
    }

    /// Sets the command buffer to the executable state, effectively ending recording.
    pub fn end_recording(self: *CommandBuffer) !void
    {
        try self.vkc.device.endCommandBuffer(self.handle);
    }

    /// Initializes a CommandBuffer object.
    pub fn init(vkc: *vkcontext.VkContext, command_pool: vk.CommandPool) !CommandBuffer
    {
        var command_buffer: CommandBuffer = .{
            .vkc = vkc
        };

        const info_allocate_buffer: vk.CommandBufferAllocateInfo = .{
            .command_pool = command_pool,
            .level = vk.CommandBufferLevel.primary,
            .command_buffer_count = 1
        };

        try vkc.device.allocateCommandBuffers(&info_allocate_buffer, @ptrCast(&command_buffer.handle));

        return command_buffer;
    }

    /// Resets the command buffer, setting it to the initial state like when it's initialized. Will produce an error if the buffer is pending (i.e. it's been submitted
    /// but not yet completed).
    pub fn reset(self: *CommandBuffer) !void
    {
        try self.vkc.device.resetCommandBuffer(self.handle, .{});
    }
};