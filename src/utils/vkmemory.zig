const std = @import("std");
const print = std.debug.print;

const vk = @import("vulkan");

const vk_context = @import("../rendering/vkcontext.zig");

const VkInterface = vk_context.VkInterface;

const commands = @import("../rendering/commands.zig");
const image_utils = @import("image_utils.zig");

pub const VulkanMemoryError = error
{
    NoSuitableMemoryType,
    InvalidMemoryType,
    OutOfRange
};

/// Helper function to find the correct memory type in the selected physical device, if one exists.
pub fn find_physical_device_memory_type(interface: *VkInterface, type_filter: u32, requested_properties: vk.MemoryPropertyFlags) VulkanMemoryError!u32
{
    const prop_code: u32 = @bitCast(requested_properties);

    const device_memory_properties = interface.context.instance.getPhysicalDeviceMemoryProperties(interface.physical_device.?);
    
    for(0..device_memory_properties.memory_type_count) |i|
    {
        const device_prop_code: u32 = @bitCast(device_memory_properties.memory_types[i].property_flags);

        const type_filtered = (type_filter & (@as(u32, 1) << @truncate(i))) != 0;
        const properties_matched = (device_prop_code & prop_code) == prop_code;

        if(type_filtered and properties_matched)
            return @truncate(i);
    }

    return VulkanMemoryError.NoSuitableMemoryType;
}

/// Helper function to create a vk.Buffer with the buffer_size, share_mode, and usage flags.
pub fn create_buffer(interface: *VkInterface, buffer_size: vk.DeviceSize, share_mode: vk.SharingMode, usage: vk.BufferUsageFlags) !vk.Buffer
{
    const info_buffer: vk.BufferCreateInfo = .{
        .size = buffer_size,
        .usage = usage,
        .sharing_mode = share_mode
    };

    return try interface.device.createBuffer(&info_buffer, null);
}

/// Helper function to allocate memory directly from Vulkan, and then bind the memory to the buffer. Should never be used outside of the allocator.
pub fn allocate_vulkan_memory_from_buffer(interface: *VkInterface, buffer: vk.Buffer, requested_properties: vk.MemoryPropertyFlags) !vk.DeviceMemory
{
    const memory_requirements = interface.device.getBufferMemoryRequirements(buffer);
    const memory_type_index = try find_physical_device_memory_type(interface, memory_requirements.memory_type_bits, requested_properties);

    const info_memory_allocate: vk.MemoryAllocateInfo = .{
        .allocation_size = memory_requirements.size,
        .memory_type_index = memory_type_index
    };

    const memory = try interface.device.allocateMemory(&info_memory_allocate, null);
    try interface.device.bindBufferMemory(buffer, memory, 0);

    return memory;
}

/// Maps data directly to Vulkan memory. Will only work with data that can be accessed by the CPU. Assumes the offset of memory to map to is 0.
pub fn map_data_to_memory(comptime T: type, interface: *VkInterface, memory: vk.DeviceMemory, data: []T) !void
{
    const map: *anyopaque = (try interface.device.mapMemory(memory, 0, data.len * @sizeOf(T), .{})).?;
    const map_data: []u8 = @as([*]u8, @ptrCast(map))[0..data.len * @sizeOf(T)];
        @memcpy(map_data, @as([*]u8, @ptrCast(data)));
    interface.device.unmapMemory(memory);
}

/// Perform a copy operation to copy data from one buffer to another, with offset values (often used for copying CPU-visible data to GPU-only buffers).
/// Command pool and queue must both support transfer operations. NOTE: All Vulkan queues and command buffers that support graphics operations implicitly
/// support transfer operations as well.
pub fn copy_buffer_with_offsets(interface: *VkInterface, size: vk.DeviceSize, src_buffer: vk.Buffer, dst_buffer: vk.Buffer, command_pool: vk.CommandPool,
transfer_queue: vk.Queue, src_offset: vk.DeviceSize, dst_offset: vk.DeviceSize) !void
{
    const command_buffer = try commands.begin_single_time_command_buffer(interface, command_pool);

    const info_buffer_copy: vk.BufferCopy = .{
        .src_offset = src_offset,
        .dst_offset = dst_offset,
        .size = size
    };

    interface.device.cmdCopyBuffer(command_buffer, src_buffer, dst_buffer, &.{ info_buffer_copy });
    try commands.end_and_submit_single_time_command_buffer(interface, command_pool, command_buffer, transfer_queue);
}

/// Perform a copy operation to copy data from one buffer to another (often used for copying CPU-visible data to GPU-only buffers). Command pool and queue
/// must both support transfer operations. NOTE: All Vulkan queues and command buffers that support graphics operations implicitly support transfer
/// operations as well.
pub fn copy_buffer(interface: *VkInterface, size: vk.DeviceSize, src_buffer: vk.Buffer, dst_buffer: vk.Buffer, command_pool: vk.CommandPool,
transfer_queue: vk.Queue) !void
{
    const command_buffer = try commands.begin_single_time_command_buffer(interface, command_pool);

    const info_buffer_copy: vk.BufferCopy = .{
        .src_offset = 0,
        .dst_offset = 0,
        .size = size
    };

    interface.device.cmdCopyBuffer(command_buffer, src_buffer, dst_buffer, &.{ info_buffer_copy });
    try commands.end_and_submit_single_time_command_buffer(interface, command_pool, command_buffer, transfer_queue);
}

pub fn copy_image(interface: *VkInterface, src_image: vk.Image, dst_image: vk.Image, src_layout: vk.ImageLayout, dst_layout: vk.ImageLayout,
command_pool: vk.CommandPool, transfer_queue: vk.Queue, src_offset: vk.Offset3D, dst_offset: vk.Offset3D, copy_extent: vk.Extent3D,
src_subresource: vk.ImageSubresourceLayers, dst_subresource: vk.ImageSubresourceLayers) !void
{
    const command_buffer = try commands.begin_single_time_command_buffer(interface, command_pool);

    const image_copy: vk.ImageCopy = .{
        .src_offset = src_offset,
        .dst_offset = dst_offset,
        .extent = copy_extent,
        .src_subresource = src_subresource,
        .dst_subresource = dst_subresource
    };

    interface.device.cmdCopyImage(command_buffer, src_image, src_layout, dst_image, dst_layout, &.{ image_copy });
    try commands.end_and_submit_single_time_command_buffer(interface, command_pool, command_buffer, transfer_queue);
}

/// Perform a copy operation to copy data from a buffer to an image. Command pool and queue must both support transfer operations. NOTE: All Vulkan queues
/// and command buffers that support graphics operations implicitly support transfer operations as well.
pub fn copy_buffer_to_image(interface: *VkInterface, src_buffer: vk.Buffer, dst_image: vk.Image, image_extent: vk.Extent3D, command_pool: vk.CommandPool,
transfer_queue: vk.Queue) !void
{
    const command_buffer = try commands.begin_single_time_command_buffer(interface, command_pool);

    const info_buffer_image_copy: vk.BufferImageCopy = .{
        .buffer_offset = 0,
        .buffer_row_length = 0,
        .buffer_image_height = 0,
        .image_subresource = .{
            .aspect_mask = .{
                .color_bit = true
            },
            .mip_level = 0,
            .base_array_layer = 0,
            .layer_count = 1
        },
        .image_offset = .{
            .x = 0, .y = 0, .z = 0
        },
        .image_extent = image_extent
    };

    interface.device.cmdCopyBufferToImage(command_buffer, src_buffer, dst_image, .transfer_dst_optimal, &.{ info_buffer_image_copy });
    try commands.end_and_submit_single_time_command_buffer(interface, command_pool, command_buffer, transfer_queue);
}

/// Perform a copy operation to copy data from an image to a buffer. Command pool and queue must both support transfer operations. NOTE: All Vulkan queues
/// and command buffers that support graphics operations implicitly support transfer operations as well.
pub fn copy_image_to_buffer(interface: *VkInterface, src_image: vk.Image, dst_buffer: vk.Buffer, image_offset: vk.Offset3D, image_extent: vk.Extent3D, command_pool: vk.CommandPool,
transfer_queue: vk.Queue) !void
{
    const command_buffer = try commands.begin_single_time_command_buffer(interface, command_pool);

    const info_image_buffer_copy: vk.BufferImageCopy = .{
        .buffer_offset = 0,
        .buffer_row_length = 0,
        .buffer_image_height = 0,
        .image_subresource = .{
            .aspect_mask = .{
                .color_bit = true
            },
            .mip_level = 0,
            .base_array_layer = 0,
            .layer_count = 1
        },
        .image_offset = image_offset,
        .image_extent = image_extent
    };

    interface.device.cmdCopyImageToBuffer(command_buffer, src_image, .transfer_src_optimal, dst_buffer, &.{ info_image_buffer_copy });
    try commands.end_and_submit_single_time_command_buffer(interface, command_pool, command_buffer, transfer_queue);
}

pub const VulkanAllocatorUsage = enum
{
    VertexBuffer,
    IndexBuffer,
    UniformBuffer,
    Texture,
    Subtexture,
    GenericAttachment,
    DepthAttachment,
    CPUTransferDst,
};

pub const VulkanAllocatorError = error
{
    InvalidAllocatorUsage
};

pub fn get_allocator_buffer_usage_flags(allocator_usage: VulkanAllocatorUsage) VulkanAllocatorError!vk.BufferUsageFlags
{
    return switch(allocator_usage)
    {
        .VertexBuffer => .{
            .vertex_buffer_bit = true,
            .transfer_dst_bit = true
        },
        .IndexBuffer => .{
            .index_buffer_bit = true,
            .transfer_dst_bit = true
        },
        .UniformBuffer => .{
            .uniform_buffer_bit = true
        },
        .CPUTransferDst => .{
            .transfer_dst_bit = true
        },
        else => VulkanAllocatorError.InvalidAllocatorUsage
    };
}

pub fn get_allocator_image_usage_flags(allocator_usage: VulkanAllocatorUsage) VulkanAllocatorError!vk.ImageUsageFlags
{
    return switch(allocator_usage)
    {
        .Texture => .{
            .transfer_dst_bit = true,
            .sampled_bit = true
        },
        .Subtexture => .{
            .transfer_src_bit = true,
            .transfer_dst_bit = true
        },
        .DepthAttachment => .{
            .depth_stencil_attachment_bit = true
        },
        else => VulkanAllocatorError.InvalidAllocatorUsage
    };
}

pub fn get_allocator_usage_memory_properties(allocator_usage: VulkanAllocatorUsage) vk.MemoryPropertyFlags
{
    return switch(allocator_usage)
    {
        .VertexBuffer, .IndexBuffer => .{
            .device_local_bit = true,
        },
        .UniformBuffer, .CPUTransferDst => .{
            .host_visible_bit = true,
            .host_coherent_bit = true
        },
        .Texture, .Subtexture, .GenericAttachment, .DepthAttachment => .{
            .device_local_bit = true
        }
    };
}

/// Allocator used for creating Vulkan buffer and image objects.
pub const VulkanAllocator = struct
{
    /// Helper struct which stores information about a free space in a memory page - just its offset and length.
    const MemorySpace = struct
    {
        offset: vk.DeviceSize,
        length: vk.DeviceSize
    };

    /// Structure containing all the information for a page of Vulkan memory, including the memory handle itself.
    const VulkanMemoryPage = struct
    {
        /// Handle to the page's device memory.
        memory: vk.DeviceMemory = undefined,

        /// List of all available free spaces in the memory page.
        freelist: std.ArrayList(MemorySpace),

        /// Memory usage properties for the memory page.
        properties: vk.MemoryPropertyFlags,

        /// Index for the memory type in the physical device that this page uses.
        memory_type_index: u32,
    };

    /// Structure containing options used when intializing the VulkanAllocator.
    pub const VulkanAllocatorOptions = struct
    {
        /// Command pool used to allocate buffers for memory transfer commands.
        transfer_command_pool: *const vk.CommandPool,
        /// Queue that memory transfer commands will be placed into.
        transfer_queue: *const vk.Queue,
        /// Size of each allocated memory page.
        page_size: vk.DeviceSize,
        /// Size of the staging buffer.
        staging_size: vk.DeviceSize
    };

    /// Vulkan interface handle.
    interface: *VkInterface,

    /// std.mem.Allocator object used for allocating an ArrayList on the CPU.
    cpu_allocator: *const std.mem.Allocator,

    /// Command pool used for allocating command buffers used for staging (or memory transfer) operations.
    staging_command_pool: *const vk.CommandPool,

    /// Queue used for executing staging (or memory transfer) commands.
    staging_queue: *const vk.Queue,

    /// List of memory pages that the allocator has allocated.
    memory_pages: std.ArrayList(VulkanMemoryPage),

    /// Options for the allocator. Set when initialized.
    options: VulkanAllocatorOptions,

    /// Staging buffer for the allocator.
    staging_buffer: vk.Buffer = undefined,

    /// Staging buffer memory.
    staging_buffer_memory: vk.DeviceMemory = undefined,

    /// Simple data type that points to a location in the allocator's memory. May contain the index of a freelist MemorySpace.
    const MemoryLocation = struct
    {
        page: usize,
        offset: vk.DeviceSize,
        memory_space_index: ?usize = null
    };

    /// Creates a new memory page with the memory type and properties given.
    fn alloc_new_page(self: *VulkanAllocator, memory_type_index: u32, properties: vk.MemoryPropertyFlags) !void
    {
        var page: VulkanMemoryPage = .{
            .freelist = try std.ArrayList(MemorySpace).initCapacity(self.cpu_allocator.*, 1),
            .properties = properties,
            .memory_type_index = memory_type_index
        };

        try page.freelist.resize(self.cpu_allocator.*, 1);

        page.freelist.items[0] = .{
            .offset = 0,
            .length = self.options.page_size
        };

        const info_memory_allocate: vk.MemoryAllocateInfo = .{
            .allocation_size = self.options.page_size,
            .memory_type_index = memory_type_index
        };

        page.memory = try self.interface.device.allocateMemory(&info_memory_allocate, null);

        try self.memory_pages.append(self.cpu_allocator.*, page);
    }

    /// Browses the existing memory pages for one which matches the memory type and properties, and has a space at least as great as size.
    /// Returns null if no space in the existing memory pages was able to be found.
    fn find_memory_space(self: VulkanAllocator, size: vk.DeviceSize, alignment: vk.DeviceSize, memory_type_index: u32, properties: vk.MemoryPropertyFlags) ?MemoryLocation
    {
        for(self.memory_pages.items, 0..) |page, i|
        {
            if(page.properties == properties and page.memory_type_index == memory_type_index)
            {
                for(page.freelist.items, 0..) |space, j|
                {
                    if(space.length >= size)
                    {
                        const align_index = space.offset % alignment;
                        if(align_index == 0)
                        {
                            return .{
                                .page = i,
                                .offset = space.offset,
                                .memory_space_index = j
                            };
                        }
                        else
                        {
                            const align_push = alignment - align_index;

                            const aligned_offset = space.offset + align_push;
                            const aligned_size = space.length - align_push;

                            if(aligned_size >= size)
                            {
                                return .{
                                    .page = i,
                                    .offset = aligned_offset,
                                    .memory_space_index = j
                                };
                            }
                        }
                    }
                }
            }
        }

        return null;
    }

    /// Updates a page's freelist after a deallocation (free).
    fn page_freelist_clear(self: *VulkanAllocator, page_index: usize, offset: vk.DeviceSize, size: vk.DeviceSize) void
    {
        const page: *VulkanMemoryPage = &self.memory_pages.items[page_index];

        var insert_location: usize = 0;
        for(page.freelist.items) |space|
        {
            if(space.offset >= offset) break;
            insert_location += 1;
        }

        const prev_space: ?*MemorySpace = if(insert_location == 0) null else &page.freelist.items[insert_location - 1];
        const next_space: ?*MemorySpace = if(insert_location == page.freelist.items.len) null else &page.freelist.items[insert_location];

        // May not be used.
        const new_space: MemorySpace = .{
            .offset = offset,
            .length = size
        };

        if(prev_space != null)
        {
            // We have a previous space available.

            const ps = prev_space.?;
            std.debug.assert(ps.offset + ps.length <= offset);

            if(ps.offset + ps.length == offset)
            {
                // The allocation occurs at the end of the previous space, meaning that we can just increase the size of the previous space.

                if(next_space != null)
                {
                    // We also have a next space available.

                    const ns = next_space.?;
                    std.debug.assert(ns.offset >= offset + size);

                    if(ns.offset == offset + size)
                    {
                        // In this case, the allocation is fit perfectly between two free spaces.
                        // We can get rid of the next space in the list entirely, and increase the size of the previous space to cover the entire
                        // allocation, as well as the entire next space.

                        ps.length += size + ns.length;
                        _ = page.freelist.orderedRemove(insert_location);
                    }
                    else
                    {
                        ps.length += size;
                    }
                }
                else
                {
                    ps.length += size;
                }
            }
            else
            {
                if(next_space != null)
                {
                    // We have a next space available.

                    const ns = next_space.?;
                    std.debug.assert(ns.offset >= offset + size);

                    if(offset + size == ns.offset)
                    {
                        // The allocation meets with the start of the next space.
                        // We can increase the size and decrease the offset of the next space.

                        ns.length += size;
                        ns.offset -= size;
                    }
                    else
                    {
                        // New space.
                        page.freelist.insert(self.cpu_allocator.*, insert_location, new_space) catch unreachable;
                    }
                }
            }
        }
        else if(next_space != null)
        {
            // We have a next space available.

            const ns = next_space.?;
            std.debug.assert(ns.offset >= offset + size);

            if(offset + size == ns.offset)
            {
                // The allocation meets with the start of the next space.
                // We can increase the size and decrease the offset of the next space.

                ns.length += size;
                ns.offset -= size;
            }
            else
            {
                // New space.
                page.freelist.insert(self.cpu_allocator.*, insert_location, new_space) catch unreachable;
            }
        }
        else
        {
            // New space.
            page.freelist.insert(self.cpu_allocator.*, insert_location, new_space) catch unreachable;
        }
    }

    /// Updates a page's freelist after an allocation.
    fn page_freelist_fill(self: *VulkanAllocator, fill_location: MemoryLocation, fill_amount: usize) !void
    {
        std.debug.assert(fill_location.memory_space_index != null);

        const page: *VulkanMemoryPage = &self.memory_pages.items[fill_location.page];
        const space = fill_location.memory_space_index.?;

        std.debug.assert(page.freelist.items[space].length >= fill_amount);

        if(fill_location.offset == page.freelist.items[space].offset)
        {
            page.freelist.items[space].length -= fill_amount;

            if(page.freelist.items[space].length == 0)
            {
                _ = page.freelist.orderedRemove(space);
            }
            else
            {
                page.freelist.items[space].offset += fill_amount;
            }
        }
        else
        {
            const after_length = page.freelist.items[space].length - ((fill_location.offset - page.freelist.items[space].offset) + fill_amount);
            page.freelist.items[space].length = fill_location.offset - page.freelist.items[space].offset;

            if(after_length != 0)
            {
                const new_space: MemorySpace = .{
                    .offset = fill_location.offset + fill_amount,
                    .length = after_length
                };

                try page.freelist.insert(self.cpu_allocator.*, fill_location.memory_space_index.? + 1, new_space);
            }
        }
    }

    /// Maps memory to the staging buffer, then transfers said memory to it's proper place in Vulkan memory.
    fn stage_buffer(self: *VulkanAllocator, buffer: vk.Buffer, comptime T: type, data: []T) !void
    {
        try map_data_to_memory(T, self.interface, self.staging_buffer_memory, data);
        try copy_buffer(self.interface, data.len * @sizeOf(T), self.staging_buffer, buffer, self.staging_command_pool.*,
        self.staging_queue.*);
    }

    /// Maps memory to the staging buffer, transfers said memory to the image, and then transitions the image's layout to be read by the shader.
    fn setup_image_texture(self: *VulkanAllocator, image: vk.Image, extent: vk.Extent3D, format: vk.Format) !void
    {
        try image_utils.transition_vulkan_image_layout(self.interface, image, format, .undefined, .transfer_dst_optimal,
        self.staging_command_pool.*, self.staging_queue.*);
        try copy_buffer_to_image(self.interface, self.staging_buffer, image, extent, self.staging_command_pool.*,
        self.staging_queue.*);
        try image_utils.transition_vulkan_image_layout(self.interface, image, format, .transfer_dst_optimal, 
        .shader_read_only_optimal, self.staging_command_pool.*, self.staging_queue.*);
    }

    /// Maps memory to the staging buffer, transfers said memory to the image, and then transitions the image's layout to be used as a source in a copy operation.
    fn setup_image_subtexture(self: *VulkanAllocator, image: vk.Image, extent: vk.Extent3D, format: vk.Format) !void
    {
        try image_utils.transition_vulkan_image_layout(self.interface, image, format, .undefined, .transfer_dst_optimal,
        self.staging_command_pool.*, self.staging_queue.*);
        try copy_buffer_to_image(self.interface, self.staging_buffer, image, extent, self.staging_command_pool.*,
        self.staging_queue.*);
        try image_utils.transition_vulkan_image_layout(self.interface, image, format, .undefined, .transfer_src_optimal,
        self.staging_command_pool.*, self.staging_queue.*);
    }

    /// Object representing a finished buffer allocation. Members of this struct can be accessed, but should NOT be modified outside
    /// of this allocator.
    pub const VulkanBufferAllocation = struct
    {
        buffer: vk.Buffer,

        page: usize,
        offset: vk.DeviceSize,
        size: vk.DeviceSize
    };

    /// Object representing a finished image allocation. Members of this struct can be accessed, but should NOT be modified outside
    /// of this allocator.
    pub const VulkanImageAllocation = struct
    {
        image: vk.Image,

        page: usize,
        offset: vk.DeviceSize,
        size: vk.DeviceSize
    };

    /// Allocates a vk.Buffer object of a size, share mode, and allocator usage. Returns an allocation object used to keep track of
    /// where the buffer is in GPU memory. DO NOT edit the contents of the allocation object.
    pub fn alloc_buffer(self: *VulkanAllocator, comptime T: type, data: []T, share_mode: vk.SharingMode, usage: VulkanAllocatorUsage) !?VulkanBufferAllocation
    {
        const size: vk.DeviceSize = data.len * @sizeOf(T);
        const allocation = try self.alloc_buffer_empty(size, share_mode, usage);

        if(allocation != null) try self.stage_buffer(allocation.?.buffer, T, data);

        return allocation;
    }

    /// Allocates a vk.Buffer with uninitialized memory. Returns an allocation object used to keep track of where the buffer is in GPU
    /// memory. DO NOT edit the contents of the allocation object.
    pub fn alloc_buffer_empty(self: *VulkanAllocator, size: vk.DeviceSize, share_mode: vk.SharingMode, usage: VulkanAllocatorUsage) !?VulkanBufferAllocation
    {
        if(size == 0)
        {
            return null;
        }

        const memory_properties = get_allocator_usage_memory_properties(usage);

        const info_buffer: vk.BufferCreateInfo = .{
            .size = size,
            .usage = try get_allocator_buffer_usage_flags(usage),
            .sharing_mode = share_mode
        };

        const buffer = try self.interface.device.createBuffer(&info_buffer, null);

        const memory_requirements = self.interface.device.getBufferMemoryRequirements(buffer);
        const memory_type_index = try find_physical_device_memory_type(self.interface, memory_requirements.memory_type_bits, 
        memory_properties);

        var free_location = self.find_memory_space(memory_requirements.size, memory_requirements.alignment, 
        memory_type_index, memory_properties);

        if(free_location == null)
        {
            try self.alloc_new_page(memory_type_index, memory_properties);
            free_location = .{
                .page = self.memory_pages.items.len - 1,
                .offset = 0,
                .memory_space_index = 0
            };
        }

        const page_memory = self.memory_pages.items[free_location.?.page].memory;
        try self.interface.device.bindBufferMemory(buffer, page_memory, free_location.?.offset);

        try self.page_freelist_fill(free_location.?, memory_requirements.size);

        return .{
            .buffer = buffer,
            .page = free_location.?.page,
            .offset = free_location.?.offset,
            .size = memory_requirements.size
        };
    }

    fn alloc_image_resource(self: *VulkanAllocator, image_info: vk.ImageCreateInfo) !VulkanImageAllocation
    {
        const image = try self.interface.device.createImage(&image_info, null);

        const memory_properties: vk.MemoryPropertyFlags = .{
            .device_local_bit = true
        };

        const memory_requirements = self.interface.device.getImageMemoryRequirements(image);
        const memory_type_index = try find_physical_device_memory_type(self.interface, memory_requirements.memory_type_bits, memory_properties);

        var free_location = self.find_memory_space(memory_requirements.size, memory_requirements.alignment, 
        memory_type_index, memory_properties);

        if(free_location == null)
        {
            try self.alloc_new_page(memory_type_index, memory_properties);
            free_location = .{
                .page = self.memory_pages.items.len - 1,
                .offset = 0,
                .memory_space_index = 0
            };
        }
        
        const page_memory = self.memory_pages.items[free_location.?.page].memory;
        try self.interface.device.bindImageMemory(image, page_memory, free_location.?.offset);

        try self.page_freelist_fill(free_location.?, memory_requirements.size);

        return .{
            .image = image,
            .page = free_location.?.page,
            .offset = free_location.?.offset,
            .size = memory_requirements.size
        };
    }

    pub fn alloc_image_empty(self: *VulkanAllocator, image_info: vk.ImageCreateInfo, usage: VulkanAllocatorUsage) !VulkanImageAllocation
    {
        const allocation = try self.alloc_image_resource(image_info);

        switch(usage)
        {
            .Texture => try self.setup_image_texture(allocation.image, image_info.extent, image_info.format),
            .Subtexture => try self.setup_image_subtexture(allocation.image, image_info.extent, image_info.format),
            else => {}
        }

        return allocation;
    }

    pub fn alloc_image(self: *VulkanAllocator, image_info: vk.ImageCreateInfo, image_data: []u8, usage: VulkanAllocatorUsage) !VulkanImageAllocation
    {
        const allocation = try self.alloc_image_resource(image_info);

        try map_data_to_memory(u8, self.interface, self.staging_buffer_memory, image_data);

        switch(usage)
        {
            .Texture => try self.setup_image_texture(allocation.image, image_info.extent, image_info.format),
            .Subtexture => try self.setup_image_subtexture(allocation.image, image_info.extent, image_info.format),
            else => {}
        }

        return allocation;
    }

    pub fn alloc_image_2d_empty(self: *VulkanAllocator, width: u32, height: u32, format: vk.Format, usage: VulkanAllocatorUsage) !VulkanImageAllocation
    {
        const image_flags = try get_allocator_image_usage_flags(usage);

        const info_image: vk.ImageCreateInfo = .{
            .image_type = .@"2d",
            .extent = .{
                .width = width,
                .height = height,
                .depth = 1
            },
            .mip_levels = 1,
            .array_layers = 1,
            .format = format,
            .tiling = .optimal,
            .initial_layout = .undefined,
            .usage = image_flags,
            .sharing_mode = .exclusive,
            .samples = .{ .@"1_bit" = true }
        };

        return self.alloc_image_empty(info_image, usage);
    }

    pub fn alloc_image_2d(self: *VulkanAllocator, image_data: []u8, width: u32, height: u32, format: vk.Format, usage: VulkanAllocatorUsage) !VulkanImageAllocation
    {
        const image_flags = try get_allocator_image_usage_flags(usage);

        const info_image: vk.ImageCreateInfo = .{
            .image_type = .@"2d",
            .extent = .{
                .width = width,
                .height = height,
                .depth = 1
            },
            .mip_levels = 1,
            .array_layers = 1,
            .format = format,
            .tiling = .optimal,
            .initial_layout = .undefined,
            .usage = image_flags,
            .sharing_mode = .exclusive,
            .samples = .{ .@"1_bit" = true }
        };

        return self.alloc_image(info_image, image_data, usage);
    }

    /// Deinitializes the allocator and frees all its allocated memory.
    pub fn deinit(self: *VulkanAllocator) void
    {
        for(self.memory_pages.items, 0..) |page, i|
        {
            self.interface.device.freeMemory(page.memory, null);
            self.memory_pages.items[i].freelist.deinit(self.cpu_allocator.*);
        }

        self.memory_pages.deinit(self.cpu_allocator.*);

        self.interface.device.destroyBuffer(self.staging_buffer, null);
        self.interface.device.freeMemory(self.staging_buffer_memory, null);
    }

    /// Frees a VulkanBufferAllocation from memory.
    pub fn free_buffer(self: *VulkanAllocator, allocation: VulkanBufferAllocation) void
    {
        self.page_freelist_clear(allocation.page, allocation.offset, allocation.size);
        self.interface.device.destroyBuffer(allocation.buffer, null);
    }

    /// Frees a VulkanImageAllocation from memory.
    pub fn free_image(self: *VulkanAllocator, allocation: VulkanImageAllocation) void
    {
        self.page_freelist_clear(allocation.page, allocation.offset, allocation.size);
        self.interface.device.destroyImage(allocation.image, null);
    }

    /// For buffers that are host-visible and host-coherent (such as UniformBuffers), maps data directly to their memory.
    /// Using a non CPU-interactable memory type will result in a VulkanMemoryError.InvalidMemoryType being returned.
    pub fn map_data_to_buffer_subsection(self: *VulkanAllocator, comptime T: type, data: []T, allocation: VulkanBufferAllocation, buffer_offset: vk.DeviceSize) !void
    {
        std.debug.assert(allocation.page < self.memory_pages.items.len);

        const page = self.memory_pages.items[allocation.page];

        if(!page.properties.host_visible_bit or !page.properties.host_coherent_bit)
        {
            return VulkanMemoryError.InvalidMemoryType;
        }

        const offset = allocation.offset;
        const size = allocation.size;

        const data_size = data.len * @sizeOf(T);

        if(buffer_offset + data_size > offset + size)
        {
            return VulkanMemoryError.OutOfRange;
        }

        std.debug.assert(data_size <= size);

        const map: *anyopaque = (try self.interface.device.mapMemory(page.memory, offset + buffer_offset, size, .{})).?;
        const map_coherent: []u8 = @as([*]u8, @ptrCast(map))[0..data.len * @sizeOf(T)];
            @memcpy(map_coherent, @as([*]u8, @ptrCast(data)));
        self.interface.device.unmapMemory(page.memory);
    }

    pub fn map_data_to_buffer(self: *VulkanAllocator, comptime T: type, data: []T, allocation: VulkanBufferAllocation) !void
    {
        try self.map_data_to_buffer_subsection(T, data, allocation, 0);
    }

    pub fn overwrite_buffer(self: *VulkanAllocator, allocation: VulkanBufferAllocation, comptime T: type, data: []T, offset: vk.DeviceSize) !void
    {
        try map_data_to_memory(T, self.interface, self.staging_buffer_memory, data);
        try copy_buffer_with_offsets(self.interface, data.len * @sizeOf(T), self.staging_buffer, allocation.buffer, 
        self.staging_command_pool.*, self.staging_queue.*, 0, offset * @sizeOf(T));
    }

    /// Takes a CPU-visible and coherent buffer and copies the data to a slice of a given type T.
    pub fn pull_buffer_data(self: *VulkanAllocator, comptime T: type, buffer: VulkanAllocator.VulkanBufferAllocation) ![]T
    {
        const page = self.memory_pages.items[buffer.page];

        const data_size = buffer.size / @sizeOf(T);
        const data = try self.interface.allocator.alloc(T, data_size);

        const map: *anyopaque = (try self.interface.device.mapMemory(page.memory, buffer.offset, buffer.size, .{})).?;
        const map_data: []u8 = @as([*]u8, @ptrCast(map))[0..buffer.size];
            @memcpy(@as([*]u8, @ptrCast(data)), map_data);
        self.interface.device.unmapMemory(page.memory);

        return data;
    }
    
    /// Prints out all available space in the allocator.
    pub fn debug_print_free_space(self: VulkanAllocator) void
    {
        print("{s}\n", .{"BEGIN FREELIST\n----------------------------"});
        for(self.memory_pages.items, 0..) |page, i|
        {
            print("[Page {d}]\n", .{i});
            for(page.freelist.items) |space|
            {
                print("\t[{d}, {d}]\n", .{space.offset, space.length});
            }
        }
        print("{s}\n", .{"END FREELIST."});
    }

    /// Create an instance of VulkanAllocator.
    pub fn init(interface: *VkInterface, allocator: *const std.mem.Allocator, options: VulkanAllocatorOptions) !VulkanAllocator
    {
        var alloc: VulkanAllocator = .{
            .interface = interface,
            .cpu_allocator = allocator,
            .memory_pages = try std.ArrayList(VulkanMemoryPage).initCapacity(allocator.*, 0),
            .staging_command_pool = options.transfer_command_pool,
            .staging_queue = options.transfer_queue,
            .options = options
        };

        alloc.staging_buffer = try create_buffer(interface, options.staging_size, .exclusive, .{
            .transfer_src_bit = true,
        });

        alloc.staging_buffer_memory = try allocate_vulkan_memory_from_buffer(interface, alloc.staging_buffer, .{
            .host_visible_bit = true,
            .host_coherent_bit = true
        });

        return alloc;
    }
};
