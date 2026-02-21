const std = @import("std");

const vk = @import("vulkan");

const VkContext = @import("../rendering//vkcontext.zig").VkContext;

const vk_memory = @import("vkmemory.zig");
const VulkanAllocator = vk_memory.VulkanAllocator;

const commands = @import("../rendering/commands.zig");

const ImageLoadError = error
{
    InvalidFileType,
    MissingFormat,
    InvalidData
};

const ImageTransitionError = error
{
    UnsupportedOldLayout,
    UnsupportedNewLayout
};

/// Load a .bmp image, and return its data as a slice.
pub fn load_bmp_image(allocator: *const std.mem.Allocator, path: [*:0]const u8, image_width: *u32, image_height: *u32) ![]u8
{
    const cwd = std.fs.cwd();
    const path_slice = std.mem.span(path);
    
    var dummy_buffer: [1]u8 = undefined;
    
    const file = try cwd.openFile(path_slice, .{.mode = .read_only});
    var file_reader = file.reader(@ptrCast(&dummy_buffer));

    std.debug.print("File size: {d}.\n", .{try file_reader.getSize()});

    const bitmap_header = try file_reader.interface.readAlloc(allocator.*, 18);

    if(bitmap_header[0] != 'B' or bitmap_header[1] != 'M')
    {
        return ImageLoadError.InvalidFileType;
    }

    var data_offset: u32 = undefined;
    @memcpy(@as(*[4]u8, @ptrCast(&data_offset)), bitmap_header.ptr + 10);

    var header_size: u32 = undefined;
    @memcpy(@as(*[4]u8, @ptrCast(&header_size)), bitmap_header.ptr + 14);

    std.debug.print("Header size: {d}.\n", .{header_size});

    if(header_size != 124)
    {
        return ImageLoadError.InvalidFileType;
    }

    allocator.free(bitmap_header);
    const header = try file_reader.interface.readAlloc(allocator.*, 36);

    @memcpy(@as(*[4]u8, @ptrCast(image_width)), header.ptr);
    @memcpy(@as(*[4]u8, @ptrCast(image_height)), header.ptr + 4);

    var color_planes: u16 = undefined;
    @memcpy(@as(*[2]u8, @ptrCast(&color_planes)), header.ptr + 8);

    if(color_planes != 1) return ImageLoadError.InvalidData;

    var bit_depth: u16 = undefined;
    @memcpy(@as(*[2]u8, @ptrCast(&bit_depth)), header.ptr + 10);

    var compression: u32 = undefined;
    @memcpy(@as(*[4]u8, @ptrCast(&compression)), header.ptr + 12);

    allocator.free(header);

    try file_reader.seekTo(data_offset);

    return try file_reader.interface.allocRemaining(allocator.*, .unlimited);
}

/// Creates an image view using a 2D image.
pub fn create_image_view_2d(context: *VkContext, image: vk.Image, format: vk.Format) !vk.ImageView
{
    const info_image_view: vk.ImageViewCreateInfo = .{
        .image = image,
        .view_type = .@"2d",
        .format = format,
        .components = .{
            .r = .identity,
            .g = .identity,
            .b = .identity,
            .a = .identity
        },
        .subresource_range = .{
            .aspect_mask = .{
                .color_bit = true
            },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1
        }
    };

    const image_view = try context.device.createImageView(&info_image_view, null);

    return image_view;
}

pub fn create_sampler_2d_linear_repeat_no_mipmap(context: *VkContext) !vk.Sampler
{
    const info_sampler: vk.SamplerCreateInfo = .{
        .mag_filter = .linear,
        .min_filter = .linear,
        .address_mode_u = .repeat,
        .address_mode_v = .repeat,
        .address_mode_w = .repeat,
        .anisotropy_enable = .false,
        .max_anisotropy = 1,
        .border_color = .int_opaque_black,
        .unnormalized_coordinates = .false,
        .compare_enable = .false,
        .compare_op = .always,
        .mipmap_mode = .linear,
        .mip_lod_bias = 0,
        .min_lod = 0,
        .max_lod = 0,
    };

    const sampler = try context.device.createSampler(&info_sampler, null);
    return sampler;
}

/// Handles transitioning image layouts, used during image transitions in memory.
pub fn transition_vulkan_image_layout(context: *VkContext, image: vk.Image, image_format: vk.Format, old_layout: vk.ImageLayout, new_layout: vk.ImageLayout,
command_pool: vk.CommandPool, transfer_queue: vk.Queue) !void
{
    // Tutorial specified this should be a part of the function... but we're not currently using it.
    _ = image_format;

    const command_buffer = try commands.begin_single_time_command_buffer(context, command_pool);

    var pipeline_barrier: vk.ImageMemoryBarrier = .{
        .old_layout = old_layout,
        .new_layout = new_layout,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresource_range = .{
            .aspect_mask = .{
                .color_bit = true
            },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1
        },

        // These two are handled below.
        .src_access_mask = .{}, 
        .dst_access_mask = .{}
    };

    var src_stage: vk.PipelineStageFlags = undefined;
    var dst_stage: vk.PipelineStageFlags = undefined;

    if(old_layout == .undefined)
    {
        // General case - we don't care about the old layout at all.

        if(new_layout == .transfer_dst_optimal)
        {
            pipeline_barrier.src_access_mask = .{};
            pipeline_barrier.dst_access_mask = .{
                .transfer_write_bit = true
            };

            src_stage = .{
                .top_of_pipe_bit = true
            };
            dst_stage = .{
                .transfer_bit = true
            };
        }
        else if(new_layout == .transfer_src_optimal)
        {
            pipeline_barrier.src_access_mask = .{};
            pipeline_barrier.dst_access_mask = .{
                .transfer_read_bit = true
            };

            src_stage = .{
                .top_of_pipe_bit = true
            };
            dst_stage = .{
                .transfer_bit = true
            };
        }
    }
    else if(old_layout == .transfer_dst_optimal)
    {
        // More specific case - we've just transfered the data to this image, and now we need to figure out what said data will be used for.

        if(new_layout == .shader_read_only_optimal)
        {
            pipeline_barrier.src_access_mask = .{
                .transfer_write_bit = true
            };
            pipeline_barrier.dst_access_mask = .{
                .shader_read_bit = true
            };

            src_stage = .{
                .transfer_bit = true
            };
            dst_stage = .{
                .fragment_shader_bit = true
            };
        }
    }

    context.device.cmdPipelineBarrier(command_buffer, src_stage, dst_stage, .{},
    0, null, 0, null, 1, @ptrCast(&pipeline_barrier));

    try commands.end_and_submit_single_time_command_buffer(context, command_pool, command_buffer, transfer_queue);
}

/// This struct holds a VulkanImageAllocation, ImageView, and Sampler, to be used for rendering textures.
pub const Texture2D = struct
{
    context: *VkContext,
    vk_allocator: *VulkanAllocator,

    image: VulkanAllocator.VulkanImageAllocation = undefined,
    image_view: ?vk.ImageView,

    sampler: ?vk.Sampler,

    width: u32,
    height: u32,

    pub fn deinit(self: *Texture2D) !void
    {
        if(self.sampler != null) self.context.device.destroySampler(self.sampler.?, null);
        if(self.image_view != null) self.context.device.destroyImageView(self.image_view.?, null);
        try self.vk_allocator.free_image(self.image);
    }

    pub fn init_buffer(context: *VkContext, vk_allocator: *VulkanAllocator, comptime T: type, buffer: []T, width: u32, height: u32, format: vk.Format,
    usage: vk_memory.VulkanAllocatorUsage) !Texture2D
    {
        var image_data: []u8 = undefined;

        if(T != u8)
        {
            image_data = @as([*]u8, @ptrCast(buffer))[0..buffer.len * @sizeOf(T)];
        }
        else
        {
            image_data = buffer;
        }

        const image = try vk_allocator.alloc_image_2d(image_data, width, height, format, usage);

        var image_view: ?vk.ImageView = null;
        var sampler: ?vk.Sampler = null;

        if(usage == .Texture)
        {
            image_view = try create_image_view_2d(context, image.image, format);
            sampler = try create_sampler_2d_linear_repeat_no_mipmap(context);
        }

        return .{
            .context = context,
            .vk_allocator = vk_allocator,
            .width = width,
            .height = height,
            .image = image,
            .image_view = image_view,
            .sampler = sampler
        };
    }

    pub fn init(context: *VkContext, vk_allocator: *VulkanAllocator, path: [*:0]const u8, usage: vk_memory.VulkanAllocatorUsage) !Texture2D
    {
        var image_width: u32 = undefined;
        var image_height: u32 = undefined;

        const image_data = try load_bmp_image(context.allocator, path, &image_width, &image_height);
        const texture = try Texture2D.init_buffer(context, vk_allocator, u8, image_data, image_width, image_height,
        .a8b8g8r8_srgb_pack32, usage);

        context.allocator.free(image_data);

        return texture;
    }
};

pub const TextureAtlasError = error
{
    OutOfSpace
};

/// A TextureAltas is a "dynamic" texture sheet, which can store and discard smaller textures.
pub const TextureAtlas2D = struct
{
    context: *VkContext,
    vk_allocator: *VulkanAllocator,

    image: VulkanAllocator.VulkanImageAllocation,
    image_view: vk.ImageView,

    sampler: vk.Sampler,

    width: vk.DeviceSize,
    height: vk.DeviceSize,

    map_texels_used: [][]bool,

    pub const TextureSuballocation = struct
    {
        pos_x: f32,
        pos_y: f32,
        scl_x: f32,
        scl_y: f32
    };

    pub fn add_texture(self: *TextureAtlas2D, texture: *Texture2D) !TextureSuballocation
    {
        const image_subresource: vk.ImageSubresourceLayers = .{
            .aspect_mask = .{
                .color_bit = true
            },
            .mip_level = 0,
            .base_array_layer = 0,
            .layer_count = 1
        };

        var found_space: bool = false;

        var tex_offset_x: u32 = 0;
        var tex_offset_y: u32 = 0;

        for(0..self.map_texels_used.len) |i|
        {
            if(found_space) break;

            for(0..self.map_texels_used[i].len) |j|
            {
                if(i + texture.width >= self.width or j + texture.height >= self.height) continue;
                
                found_space = true;

                if(!self.map_texels_used[i][j])
                {
                    for(0..texture.width) |x|
                    {
                        if(!found_space) break;

                        for(0..texture.height) |y|
                        {
                            if(self.map_texels_used[i + x][j + y])
                            {
                                found_space = false;
                                break;
                            }
                        }
                    }

                    if(found_space)
                    {
                        tex_offset_x = @truncate(i);
                        tex_offset_y = @truncate(j);
                        break;
                    }
                }
                else
                {
                    found_space = false;
                }
            }
        }

        if(!found_space)
        {
            return TextureAtlasError.OutOfSpace;
        }

        for(0..texture.width) |i|
        {
            for(0..texture.height) |j|
            {
                self.map_texels_used[tex_offset_x + i][tex_offset_y + j] = true;
            }
        }

        try transition_vulkan_image_layout(self.context, self.image.image, .a8b8g8r8_uint_pack32, .undefined, 
        .transfer_dst_optimal, self.vk_allocator.staging_command_pool.*, self.vk_allocator.staging_queue.*);

        try vk_memory.copy_image(self.context, texture.image.image, self.image.image, .transfer_src_optimal, 
        .transfer_dst_optimal, self.vk_allocator.staging_command_pool.*, self.vk_allocator.staging_queue.*, 
        .{.x = 0, .y = 0, .z = 0}, .{.x = @bitCast(tex_offset_x), .y = @bitCast(tex_offset_y), .z = 0},
        .{.width = texture.width, .height = texture.height, .depth = 1}, image_subresource, image_subresource);

        try transition_vulkan_image_layout(self.context, self.image.image, .a8b8g8r8_uint_pack32, .transfer_dst_optimal, 
        .shader_read_only_optimal, self.vk_allocator.staging_command_pool.*, self.vk_allocator.staging_queue.*);

        const f_width = @as(f32, @floatFromInt(self.width));
        const f_height = @as(f32, @floatFromInt(self.height));

        return .{
            .pos_x = @as(f32, @floatFromInt(tex_offset_x)) / f_width,
            .pos_y = @as(f32, @floatFromInt(tex_offset_y)) / f_height,
            .scl_x = @as(f32, @floatFromInt(texture.width)) / f_width,
            .scl_y = @as(f32, @floatFromInt(texture.height)) / f_height
        };
    }
    
    pub fn deinit(self: *TextureAtlas2D) !void
    {
        self.context.device.destroySampler(self.sampler, null);
        self.context.device.destroyImageView(self.image_view, null);
        try self.vk_allocator.free_image(self.image);

        for(0..self.map_texels_used.len) |i|
        {
            self.context.allocator.free(self.map_texels_used[i]);
        }
        self.context.allocator.free(self.map_texels_used);
    }

    pub fn init(context: *VkContext, vk_allocator: *VulkanAllocator, width: u32, height: u32) !TextureAtlas2D
    {
        const image = try vk_allocator.alloc_image_2d_empty(width, height, .a8b8g8r8_srgb_pack32, .Texture);

        const image_view = try create_image_view_2d(context, image.image, .a8b8g8r8_srgb_pack32);
        const sampler = try create_sampler_2d_linear_repeat_no_mipmap(context);

        const texels_used = try context.allocator.alloc([]bool, width);
        for(0..texels_used.len) |i|
        {
            texels_used[i] = try context.allocator.alloc(bool, height);
        }

        for(0..texels_used.len) |i|
        {
            for(0..texels_used[i].len) |j|
            {
                texels_used[i][j] = false;
            }
        }

        return .{
            .context = context,
            .vk_allocator = vk_allocator,
            .width = width,
            .height = height,
            .image = image,
            .image_view = image_view,
            .sampler = sampler,
            .map_texels_used = texels_used
        };
    }
};
