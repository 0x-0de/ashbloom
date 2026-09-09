# `commands`

Namespace for handling Vulkan commands and command buffers.

## CommandBuffer (`struct`)

Essentially wraps a `VkCommandBuffer` object and provides some helper functions for common commands, such as beginning/ending buffer recording, drawing commands, resetting buffers, binding a graphics pipeline, and so on.

### Fields

`interface: *VkInterface` - `VkInterface` handle.

`handle: vk.CommandBuffer` - Command buffer handle.

`proxy: vk.CommandBufferProxy` - Proxies the command buffer. Wraps all command buffer functions and gets rid of redundant parameters. If you need to use a custom command, use this field to access and call it.

### Public Functions

**`begin_recording(self: *CommandBuffer) !void`**

Sets the command buffer to the recording state. Must be called before recording other commands to the buffer.

**`begin_render_pass(self: *CommandBuffer, render_pass: *RenderPass, framebuffer: vk.Framebuffer, extent: vk.Extent2D, clear_values: []const vk.ClearValue) void`**

Helper function to create a VkRenderPassBeginInfo and pass it into cmdBeginRenderPass. This command begins a render pass.

**`bind_descriptor_set(self: *CommandBuffer, bind_point: vk.PipelineBindPoint, pipeline: *Pipeline, descriptor_set: *vk.DescriptorSet) void`**

Binds a pipeline descriptor set.

**`bind_index_buffer(self: *CommandBuffer, buffer: vk.Buffer, offset: vk.DeviceSize) void`**

Binds an index buffer. This will apply to the target of the next draw command. The buffer **MUST** be a list of 16-bit unsigned integers (if you need a different format, just use proxy.bindIndexBuffer).

**`bind_pipeline(self: *CommandBuffer, bind_point: vk.PipelineBindPoint, pipeline: *Pipeline) void`**

Binds a Vulkan pipeline. All subsequent commands will be performed with this pipeline, until the buffer ends or another pipeline is bound. 

**`bind_vertex_buffer(self: *CommandBuffer, binding: u32, buffer: vk.Buffer, offset: vk.DeviceSize) void`**

Binds a vertex buffer to a specific binding defined by the graphics pipeline and its PipelineVertexInput. This will be the target of the next draw command.

**`draw(self: *CommandBuffer, vertex_count: u32, instance_count: u32) void`**

Draws a certain number of vertices and instances. Does not apply indices.

**`draw_indexed(self: *CommandBuffer, index_count: u32, instance_count: u32) void`**

Draws a certain number of indices and instances.

**`cmd_end_render_pass(self: *CommandBuffer) void`**

Ends the render pass.

**`end_recording(self: *CommandBuffer) !void`**

Sets the command buffer to the executable state, effectively ending recording.

**`end_render_pass(self: *CommandBuffer) void`**

Ends the current render pass.

**`init(interface: *VkInterface, command_pool: vk.CommandPool) !CommandBuffer`**

Initializes a new command buffer, allocated from `command_pool`.

**`push_constants(self: *CommandBuffer, pipeline: *Pipeline, range: vk.PushConstantRange, data: *const anyopaque) void`**

Pushes constants to a set push constant location in the shader.

**`reset(self: *CommandBuffer) !void`**

Resets the command buffer, setting it to the initial state like when it's initialized. Will produce an error if the buffer is pending (i.e. it's been submitted but not yet completed).

**`set_scissor(self: *CommandBuffer, bounds: vk.Rect2D) void`**

Sets the scissor of the current draw operation. Used for graphics pipelines with dynamic viewports and scissors.

**`set_viewport(self: *CommandBuffer, bounds: vk.Rect2D, min_depth: f32, max_depth: f32) void`**

Sets the viewport of the screen. Used for graphics pipelines with dynamic viewports and scissors.

**`set_viewport_full(self: *CommandBuffer, extent: vk.Extent2D) void`**

Sets the viewport of the screen, assuming that the top-left corner of the viewport is (0, 0), and the min and max depth are -1 and 1 respectively. Used for graphics pipelines with dynamic viewports and scissors.

**`set_viewport_scissor_full(self: *CommandBuffer, extent: vk.Extent2D) void`**

Sets both the viewport and scissor to cover the entire area of extent. Used for graphics pipelines with dynamic viewports and scissors.

## Public Functions

**`begin_single_time_command_buffer(context: *VkInterface, command_pool: vk.CommandPool) !vk.CommandBuffer`**

Uses an available command pool to create a single `VkCommandBuffer` object to be executed once.

**`create_command_pool(vkc: *VkInterface, queue_family_index: u32) !vk.CommandPool`**

Creates a command pool to allocate command buffers.

**`end_and_submit_single_time_command_buffer(context: *VkInterface, command_pool: vk.CommandPool, command_buffer: vk.CommandBuffer, queue: vk.Queue) !void`**

Finishes recording and submits a single-time command buffer.