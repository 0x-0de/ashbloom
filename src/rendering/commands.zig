//! Namespace for handling Vulkan commands and command buffers.

const std = @import("std");
const print = std.debug.print;

const glfw = @import("glfw");
const vk = @import("vulkan");

const vkcontext = @import("vkcontext.zig");

const VkInterface = vkcontext.VkInterface;
const RenderPass = @import("renderpass.zig").RenderPass;
const Pipeline = @import("pipeline.zig").Pipeline;

/// Creates a command pool to allocate graphics command buffers.
pub fn create_command_pool(vkc: *VkInterface, queue_family_index: u32) !vk.CommandPool
{
    const info_command_pool: vk.CommandPoolCreateInfo = .{
        .flags = .{
            .reset_command_buffer_bit = true
        },
        .queue_family_index = queue_family_index 
    };

    return try vkc.device.createCommandPool(&info_command_pool, null);
}

/// Uses an available command pool to create a single vk.CommandBuffer object to be executed once.
pub fn begin_single_time_command_buffer(context: *VkInterface, command_pool: vk.CommandPool) !vk.CommandBuffer
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
pub fn end_and_submit_single_time_command_buffer(context: *VkInterface, command_pool: vk.CommandPool, command_buffer: vk.CommandBuffer, queue: vk.Queue) !void
{
    try context.device.endCommandBuffer(command_buffer);

    const info_submit: vk.SubmitInfo = .{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&command_buffer)
    };

    try context.device.queueSubmit(queue, &.{ info_submit }, .null_handle);
    try context.device.queueWaitIdle(queue);

    context.device.freeCommandBuffers(command_pool, &.{ command_buffer });
}

/// Essentially wraps a vk.CommandBuffer object and provides some helper functions for common commands, such as beginning/ending
/// buffer recording, drawing commands, resetting buffers, binding a graphics pipeline, and so on.
pub const CommandBuffer = struct
{
    interface: *VkInterface,

    handle: vk.CommandBuffer,
    proxy: vk.CommandBufferProxy,

    /// Sets the command buffer to the recording state. Must be called before recording other commands to the buffer.
    pub fn begin_recording(self: *CommandBuffer) !void
    {
        const info_begin: vk.CommandBufferBeginInfo = .{
            .flags = .{}
        };

        try self.proxy.beginCommandBuffer(&info_begin);
    }

    /// Helper function to create a VkRenderPassBeginInfo and pass it into cmdBeginRenderPass.
    /// This command begins a render pass.
    pub fn begin_render_pass(self: *CommandBuffer, render_pass: *RenderPass, framebuffer: vk.Framebuffer, extent: vk.Extent2D, clear_values: []const vk.ClearValue) void
    {
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
            .clear_value_count = @truncate(clear_values.len),
            .p_clear_values = @ptrCast(clear_values),
        };

        self.proxy.beginRenderPass(&info_begin_rp, .@"inline");
    }

    /// Binds a pipeline descriptor set.
    pub fn bind_descriptor_set(self: *CommandBuffer, bind_point: vk.PipelineBindPoint, pipeline: *Pipeline, descriptor_set: *vk.DescriptorSet) void
    {
        self.proxy.bindDescriptorSets(bind_point, pipeline.pipeline_layout.?, 0, &.{ descriptor_set.* }, null);
    }

    /// Binds an index buffer. This will apply to the target of the next draw command. The buffer **MUST** be a list of 16-bit unsigned integers.
    /// (If you need a different format, just use proxy.bindIndexBuffer).
    pub fn bind_index_buffer(self: *CommandBuffer, buffer: vk.Buffer, offset: vk.DeviceSize) void
    {
        self.proxy.bindIndexBuffer(buffer, offset, .uint16);
    }

    /// Binds a Vulkan pipeline. All subsequent commands will be performed with this pipeline, until the buffer ends or another pipeline is bound. 
    pub fn bind_pipeline(self: *CommandBuffer, bind_point: vk.PipelineBindPoint, pipeline: *Pipeline) void
    {
        self.proxy.bindPipeline(bind_point, pipeline.pipeline);
    }

    /// Binds a vertex buffer to a specific binding defined by the graphics pipeline and its PipelineVertexInput. This will be the target of the next draw command.
    pub fn bind_vertex_buffer(self: *CommandBuffer, binding: u32, buffer: vk.Buffer, offset: vk.DeviceSize) void
    {
        self.proxy.bindVertexBuffers(binding, &.{ buffer }, &.{ offset });
    }

    /// Draws a certain number of vertices and instances. Does not apply indices.
    pub fn draw(self: *CommandBuffer, vertex_count: u32, instance_count: u32) void
    {
        self.proxy.draw(vertex_count, instance_count, 0, 0);
    }

    /// Draws a certain number of indices and instances.
    pub fn draw_indexed(self: *CommandBuffer, index_count: u32, instance_count: u32) void
    {
        self.proxy.drawIndexed(index_count, instance_count, 0, 0, 0);
    }

    /// Ends the render pass.
    pub fn cmd_end_render_pass(self: *CommandBuffer) void
    {
        self.proxy.endRenderPass();
    }

    /// Sets the command buffer to the executable state, effectively ending recording.
    pub fn end_recording(self: *CommandBuffer) !void
    {
        try self.proxy.endCommandBuffer();
    }

    /// Ends the current render pass.
    pub fn end_render_pass(self: *CommandBuffer) void
    {
        self.proxy.endRenderPass();
    }

    pub fn init(interface: *VkInterface, command_pool: vk.CommandPool) !CommandBuffer
    {
        const info_allocate_buffer: vk.CommandBufferAllocateInfo = .{
            .command_pool = command_pool,
            .level = vk.CommandBufferLevel.primary,
            .command_buffer_count = 1
        };

        var cmd_handle: vk.CommandBuffer = undefined;
        try interface.device.allocateCommandBuffers(&info_allocate_buffer, @ptrCast(&cmd_handle));

        const proxy = vk.CommandBufferProxy.init(cmd_handle, interface.vkd);

        return .{
            .interface = interface,
            .handle = cmd_handle,
            .proxy = proxy
        };
    }

    /// Pushes constants to a set push constant location in the shader.
    pub fn push_constants(self: *CommandBuffer, pipeline: *Pipeline, range: vk.PushConstantRange, data: *const anyopaque) void
    {
        self.proxy.pushConstants(pipeline.pipeline_layout.?, range.stage_flags, range.offset, range.size, data);
    }

    /// Resets the command buffer, setting it to the initial state like when it's initialized. Will produce an error if the buffer is pending (i.e. it's been submitted
    /// but not yet completed).
    pub fn reset(self: *CommandBuffer) !void
    {
        try self.proxy.resetCommandBuffer(.{});
    }
    
    /// Sets the scissor of the current draw operation. Used for graphics pipelines with dynamic viewports and scissors.
    pub fn set_scissor(self: *CommandBuffer, bounds: vk.Rect2D) void
    {
        const scissor: vk.Rect2D = .{
            .offset = bounds.offset,
            .extent = bounds.extent
        };

        self.proxy.setScissor(0, &.{ scissor });
    }
    
    /// Sets the viewport of the screen. Used for graphics pipelines with dynamic viewports and scissors.
    pub fn set_viewport(self: *CommandBuffer, bounds: vk.Rect2D, min_depth: f32, max_depth: f32) void
    {
        const viewport: vk.Viewport = .{
            .x = bounds.offset.x,
            .y = bounds.offset.y,
            .width = @floatFromInt(bounds.extent.width),
            .height = @floatFromInt(bounds.extent.height),
            .min_depth = min_depth,
            .max_depth = max_depth
        };

        self.proxy.setViewport(0, &.{ viewport });
    }

    /// Sets the viewport of the screen, assuming that the top-left corner of the viewport is (0, 0), and the min and max depth are -1 and
    /// 1 respectively. Used for graphics pipelines with dynamic viewports and scissors.
    pub fn set_viewport_full(self: *CommandBuffer, extent: vk.Extent2D) void
    {
        const viewport: vk.Viewport = .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(extent.width),
            .height = @floatFromInt(extent.height),
            .min_depth = 0,
            .max_depth = 1
        };

        self.proxy.setViewport(0, &.{ viewport });
    }

    /// Sets both the viewport and scissor to cover the entire area of extent. Used for graphics pipelines with dynamic viewports and scissors.
    pub fn set_viewport_scissor_full(self: *CommandBuffer, extent: vk.Extent2D) void
    {
        const viewport: vk.Viewport = .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(extent.width),
            .height = @floatFromInt(extent.height),
            .min_depth = 0,
            .max_depth = 1
        };

        self.proxy.setViewport(0, &.{ viewport });

        const scissor: vk.Rect2D = .{
            .offset = .{
                .x = 0,
                .y = 0
            },
            .extent = extent
        };

        self.proxy.setScissor(0, &.{ scissor });
    }
};

const vk_test = @import("../utils/testing/test_utils.zig");

test "Command pool from basic VkContext"
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

    const pool = try create_command_pool(&vk_context);
    vk_context.device.destroyCommandPool(pool, null);
}
