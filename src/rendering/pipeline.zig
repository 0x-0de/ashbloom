const std = @import("std");
const print = std.debug.print;

const ash = @import("../root.zig");

const vk = @import("vulkan");
const glfw = @import("glfw");

const vkcontext = @import("vkcontext.zig");
const RenderPass = @import("renderpass.zig").RenderPass;

const vk_utils = @import("../utils/vkutils.zig");
const images = @import("../utils/image_utils.zig");

const VulkanAllocator = @import("../utils/vkmemory.zig").VulkanAllocator;

const PipelineError = error
{
    CouldntLoadShaderFile,
    UnsupportedDescriptorBindingType,
    InvalidDescriptorBinding
};

fn dummy_stencil_op_state() vk.StencilOpState
{
    return .{
        .compare_mask = 0,
        .write_mask = 0,
        .reference = 0,
        .fail_op = .zero,
        .compare_op = .never,
        .depth_fail_op = .zero,
        .pass_op = .zero
    };
}

/// Struct used for setting pipeline vertex input.
pub const PipelineVertexInput = struct
{
    /// ALlocator.
    allocator: *const std.mem.Allocator,

    /// List of attribute descriptions. Do not access directly, if you need to add attribute descriptions, use add_attribute.
    attribute_descriptions: std.ArrayList(vk.VertexInputAttributeDescription),
    
    /// The binding description structure is the top-most structure used to describe a vertex input binding.
    /// A pipeline's vertex input is made up of multiple vertex input bindings, though in most cases you'll likely only need one.
    binding_description: vk.VertexInputBindingDescription = undefined,

    /// Adds an attribute to the pipeline vertex input. An attribute is a scalar or vector value given to each vertex or instance drawn.
    /// On a per-vertex basis, an attribute could represent a vertex's position, color, texture coordinate, etc.
    /// On a per-instance basis, an attribute could represent a model position, scale, color, etc.
    pub fn add_attribute(self: *PipelineVertexInput, binding: u32, location: u32, format: vk.Format, offset: u32) !void
    {
        const attribute: vk.VertexInputAttributeDescription = .{
            .binding = binding,
            .location = location,
            .format = format,
            .offset = offset
        };

        try self.attribute_descriptions.append(self.allocator.*, attribute);
    }

    /// Compiles the binding_description. Should be called after adding all attributes to the structure.
    pub fn build(self: *PipelineVertexInput, binding: u32, input_rate: vk.VertexInputRate) !void
    {
        var stride: u32 = 0;

        for(self.attribute_descriptions.items) |desc|
        {
            const format_size = try vk_utils.get_vulkan_format_size(desc.format);
            stride += format_size;
        }

        self.binding_description = .{
            .binding = binding,
            .stride = stride,
            .input_rate = input_rate
        };
    }

    /// Deinitializes a PipelineVertexInput.
    pub fn deinit(self: *PipelineVertexInput) void
    {
        self.attribute_descriptions.deinit(self.allocator.*);
    }

    /// Initializes and returns a PipelineVertexInput.
    pub fn init(allocator: *const std.mem.Allocator) !PipelineVertexInput
    {
        return .{
            .allocator = allocator,
            .attribute_descriptions = try std.ArrayList(vk.VertexInputAttributeDescription).initCapacity(allocator.*, 0),
        };
    }
};

/// Structure that handles a Vulkan pipeline shader module.
const PipelineShaderModule = struct
{
    shader_module: vk.ShaderModule = undefined,
    shader_stages: vk.ShaderStageFlags,

    /// Load a shader .spv file and return it's data as a slice.
    fn load_spv_file(allocator: *const std.mem.Allocator, path: [*:0]const u8) ![]u8
    {
        var io: std.Io.Threaded = .init(allocator.*, .{});
        defer io.deinit();

        const cwd = std.Io.Dir.cwd();
        const path_slice = std.mem.span(path);
        
        var dummy_buffer: [1]u8 = undefined;
        
        const file = try cwd.openFile(io.io(), path_slice, .{.mode = .read_only});
        var file_reader = file.reader(io.io(), @ptrCast(&dummy_buffer));

        const file_buffer = try file_reader.interface.allocRemaining(allocator.*, .unlimited);

        return file_buffer;
    }

    /// Destroy a pipeline shader module.
    pub fn deinit(self: PipelineShaderModule, device: *vk.DeviceProxy) void
    {
        device.destroyShaderModule(self.shader_module, null);
    }

    /// Initialize a pipeline shader module.
    pub fn init(device: *vk.DeviceProxy, allocator: *const std.mem.Allocator, path: [*:0]const u8, shader_stages: vk.ShaderStageFlags) !PipelineShaderModule
    {
        var psm: PipelineShaderModule = .{
            .shader_stages = shader_stages
        };

        const spv_data = try load_spv_file(allocator, path);
        defer allocator.free(spv_data);

        const info_sm: vk.ShaderModuleCreateInfo = .{
            .code_size = spv_data.len,
            .p_code = @ptrCast(@alignCast(spv_data))
        };
        
        psm.shader_module = try device.createShaderModule(&info_sm, null);

        return psm;
    }
};

/// Creates a pipeline descriptor set layout binding. This struct describes a single binding for global variables in the pipeline's shader.
pub fn create_pipeline_descriptor_set_layout_binding(binding: u32, descriptor_type: vk.DescriptorType, shader_stage: vk.ShaderStageFlags) vk.DescriptorSetLayoutBinding
{
    return .{
        .binding = binding,
        .descriptor_type = descriptor_type,
        .descriptor_count = 1,
        .stage_flags = shader_stage
    };
}

/// Specifies a set of pipeline resource descriptors, which are how shaders access global (uniform) variables such as textures or projection matrices.
pub const PipelineDescriptorSet = struct
{
    context: *vkcontext.VkContext,
    vk_allocator: *VulkanAllocator,

    set_count: u16,

    bindings: std.ArrayList(DescriptorBinding),

    layout: vk.DescriptorSetLayout = undefined,

    pool: vk.DescriptorPool = undefined,
    sets: []vk.DescriptorSet = undefined,

    // TODO: Make this a union.
    /// Struct describing the information and requirements for a descriptor binding. Also contains the DescriptorSetLayoutBinding for the binding.
    const DescriptorBinding = struct
    {
        binding_index: u32,
        type: vk.DescriptorType,
        shader_stage: vk.ShaderStageFlags,

        binding: vk.DescriptorSetLayoutBinding = undefined,

        buffers: ?[]VulkanAllocator.VulkanBufferAllocation = null,
        buffer_size: ?vk.DeviceSize = null,

        image_sampler: ?vk.Sampler = null,
        image_view: ?vk.ImageView = null,
        image_layout: ?vk.ImageLayout = null
    };

    fn create_descriptor_pool(self: *PipelineDescriptorSet) !void
    {
        var pool_sizes = try self.context.allocator.alloc(vk.DescriptorPoolSize, self.bindings.items.len);
        defer self.context.allocator.free(pool_sizes);

        for(0..pool_sizes.len) |i|
        {
            pool_sizes[i].type = self.bindings.items[i].type;
            pool_sizes[i].descriptor_count = self.set_count;
        }

        const info_pool: vk.DescriptorPoolCreateInfo = .{
            .pool_size_count = @truncate(pool_sizes.len),
            .p_pool_sizes = @ptrCast(pool_sizes),
            .max_sets = self.set_count
        };

        self.pool = try self.context.device.createDescriptorPool(&info_pool, null);
    }

    pub fn add_binding(self: *PipelineDescriptorSet, binding: DescriptorBinding) !void
    {
        const index = self.bindings.items.len;
        try self.bindings.append(self.context.allocator.*, binding);

        self.bindings.items[index].binding =
            create_pipeline_descriptor_set_layout_binding(binding.binding_index, binding.type, binding.shader_stage);
    }

    pub fn build(self: *PipelineDescriptorSet) !void
    {
        const descriptor_set_bindings = try self.context.allocator.alloc(vk.DescriptorSetLayoutBinding, self.bindings.items.len);
        for(0..descriptor_set_bindings.len) |i|
        {
            descriptor_set_bindings[i] = self.bindings.items[i].binding;
        }

        const info_create: vk.DescriptorSetLayoutCreateInfo = .{
            .binding_count = @truncate(descriptor_set_bindings.len),
            .p_bindings = @ptrCast(descriptor_set_bindings)
        };

        self.layout = try self.context.device.createDescriptorSetLayout(&info_create, null);
        self.context.allocator.free(descriptor_set_bindings);

        try self.create_descriptor_pool();

        const descriptor_layouts = try self.context.allocator.alloc(vk.DescriptorSetLayout, self.set_count);
        defer self.context.allocator.free(descriptor_layouts);

        for(0..descriptor_layouts.len) |i|
        {
            descriptor_layouts[i] = self.layout;
        }

        const info_alloc: vk.DescriptorSetAllocateInfo = .{
            .descriptor_pool = self.pool,
            .descriptor_set_count = self.set_count,
            .p_set_layouts = @ptrCast(descriptor_layouts)
        };

        self.sets = try self.context.allocator.alloc(vk.DescriptorSet, self.set_count);

        try self.context.device.allocateDescriptorSets(&info_alloc, @ptrCast(self.sets));

        // Allocating memory resources (like uniform buffers) for each binding.
        for(0..self.bindings.items.len) |i|
        {
            if(self.bindings.items[i].type == .uniform_buffer)
            {
                self.bindings.items[i].buffers = try self.context.allocator.alloc(VulkanAllocator.VulkanBufferAllocation, self.set_count);
                for(0..self.set_count) |j|
                {
                    self.bindings.items[i].buffers.?[j] = try self.vk_allocator.alloc_buffer_empty(
                        self.bindings.items[i].buffer_size.?, .exclusive, .UniformBuffer);
                }
            }
            else if(self.bindings.items[i].type == .combined_image_sampler)
            {
                // Nothing.
            }
            else
            {
                return PipelineError.UnsupportedDescriptorBindingType;
            }
        }

        const no_buffer: vk.DescriptorBufferInfo = .{
            .offset = 0,
            .range = 0
        };

        const no_image: vk.DescriptorImageInfo = .{
            .sampler = @enumFromInt(0),
            .image_view = @enumFromInt(0),
            .image_layout = @enumFromInt(0)
        };

        const no_buffer_view: vk.BufferView = @enumFromInt(0);

        // Updating descriptor sets.
        for(0..self.set_count) |i|
        {
            var info_buffers = try std.ArrayList(vk.DescriptorBufferInfo).initCapacity(self.context.allocator.*, 0);
            defer info_buffers.deinit(self.context.allocator.*);

            var info_images = try std.ArrayList(vk.DescriptorImageInfo).initCapacity(self.context.allocator.*, 0);
            defer info_images.deinit(self.context.allocator.*);

            var descriptor_writes = try self.context.allocator.alloc(vk.WriteDescriptorSet, self.bindings.items.len);
            defer self.context.allocator.free(descriptor_writes);

            for(0..descriptor_writes.len) |j|
            {
                const descriptor_type = self.bindings.items[j].type;

                descriptor_writes[j].s_type = .write_descriptor_set;
                descriptor_writes[j].dst_set = self.sets[i];
                descriptor_writes[j].dst_binding = @truncate(j);
                descriptor_writes[j].dst_array_element = 0;
                descriptor_writes[j].descriptor_type = descriptor_type;
                descriptor_writes[j].descriptor_count = 1;
                descriptor_writes[j].p_next = null;

                if(descriptor_type == vk.DescriptorType.uniform_buffer)
                {
                    const info_buffer: vk.DescriptorBufferInfo = .{
                        .buffer = self.bindings.items[j].buffers.?[i].buffer,
                        .offset = 0,
                        .range = self.bindings.items[j].buffer_size.?
                    };

                    const index = info_buffers.items.len;
                    try info_buffers.append(self.context.allocator.*, info_buffer);

                    descriptor_writes[j].p_buffer_info = @ptrCast(&info_buffers.items[index]);
                    descriptor_writes[j].p_image_info = @ptrCast(&no_image);
                    descriptor_writes[j].p_texel_buffer_view = @ptrCast(&no_buffer_view);
                }
                else if(descriptor_type == vk.DescriptorType.combined_image_sampler)
                {
                    const info_image: vk.DescriptorImageInfo = .{
                        .sampler = self.bindings.items[j].image_sampler.?,
                        .image_view = self.bindings.items[j].image_view.?,
                        .image_layout = self.bindings.items[j].image_layout.?
                    };

                    const index = info_images.items.len;
                    try info_images.append(self.context.allocator.*, info_image);

                    descriptor_writes[j].p_buffer_info = @ptrCast(&no_buffer);
                    descriptor_writes[j].p_image_info = @ptrCast(&info_images.items[index]);
                    descriptor_writes[j].p_texel_buffer_view = @ptrCast(&no_buffer_view);
                }
            }

            self.context.device.updateDescriptorSets(descriptor_writes, null);
        }
    }

    pub fn deinit(self: *PipelineDescriptorSet) !void
    {
        for(0..self.bindings.items.len) |i|
        {
            if(self.bindings.items[i].type == .uniform_buffer)
            {
                for(0..self.set_count) |j|
                {
                    try self.vk_allocator.free_buffer(self.bindings.items[i].buffers.?[j]);
                }
                self.context.allocator.free(self.bindings.items[i].buffers.?);
            }
        }

        self.context.allocator.free(self.sets);
        self.context.device.destroyDescriptorPool(self.pool, null);
        self.context.device.destroyDescriptorSetLayout(self.layout, null);
        self.bindings.deinit(self.context.allocator.*);
    }

    pub fn init(context: *vkcontext.VkContext, vk_allocator: *VulkanAllocator, set_count: u16) !PipelineDescriptorSet
    {
        return .{
            .context = context,
            .vk_allocator = vk_allocator,
            .set_count = set_count,
            .bindings = try std.ArrayList(DescriptorBinding).initCapacity(context.allocator.*, 0)
        };
    }

    pub fn place_data(self: *PipelineDescriptorSet, set_index: u16, binding_index: u16, comptime T: type, data: []T, offset: vk.DeviceSize) !void
    {
        if(binding_index >= self.bindings.items.len or self.bindings.items[binding_index].type != .uniform_buffer)
            return PipelineError.InvalidDescriptorBinding;

        try self.vk_allocator.map_data_to_buffer_subsection(T, data, self.bindings.items[binding_index].buffers.?[set_index], offset);
    }
};

/// Helper function to return a common vk.PipelineVertexInputStateCreateInfo use case:
/// No vertex input will be passed through the pipeline. Instead, vertex input must be specified in the shader itself.
pub fn pipeline_vertex_input_no_input() vk.PipelineVertexInputStateCreateInfo
{
    return .{
        .vertex_attribute_description_count = 0,
        .vertex_binding_description_count = 0
    };
}

/// Helper function to return a common vk.PipelineInputAssemblyStateCreateInfo use case:
/// Vertex input will be assembled into a list of rasterized triangles, with no element buffer (indices) or primitive restart (useless for lists anyways).
pub fn pipeline_input_assembly_triangle_list() vk.PipelineInputAssemblyStateCreateInfo
{
    return .{
        .topology = .triangle_list,
        .primitive_restart_enable = .false
    };
}

/// Helper function to return a common vk.PipelineViewportStateCreateInfo use case:
/// The viewport is included in the pipeline's dynamic state, and doesn't need to be specified at pipeline creation time.
pub fn pipeline_viewport_state_dynamic() vk.PipelineViewportStateCreateInfo
{
    return .{
        .viewport_count = 1,
        .scissor_count = 1
    };
}

/// Helper function to return a common vk.PipelineRasterizationStateCreateInfo use case:
/// The pipeline rasterizer will fill the front (clockwise) faces of triangles only, and not worry about depth culling.
pub fn pipeline_rasterizer_fill_triangle_cull_back_no_depth() vk.PipelineRasterizationStateCreateInfo
{
    return .{
        .depth_bias_enable = vk.Bool32.false,
        .depth_clamp_enable = vk.Bool32.false,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
        .rasterizer_discard_enable = vk.Bool32.false,
        .polygon_mode = vk.PolygonMode.fill,
        .line_width = 1,
        .cull_mode = .{
            .back_bit = true
        },
        .front_face = vk.FrontFace.counter_clockwise
    };
}

/// Helper function to return a common vk.PipelineMultisampleStateCreateInfo use case:
/// The pipeline will not perform multisampling operations.
pub fn pipeline_multisample_no_multisampling() vk.PipelineMultisampleStateCreateInfo
{
    return .{
        .sample_shading_enable = vk.Bool32.false,
        .rasterization_samples = .{
            .@"1_bit" = true
        },
        .min_sample_shading = 1,
        .alpha_to_coverage_enable = vk.Bool32.false,
        .alpha_to_one_enable = vk.Bool32.false
    };
}

/// Helper function to return a common vk.PipelineColorBlendAttachmentState use case:
/// The pipeline will not perform color blend operations, and will simply overwrite any colors instead.
pub fn pipeline_color_blend_attachment_no_blend() vk.PipelineColorBlendAttachmentState
{
    return .{
        .color_write_mask = .{
            .r_bit = true,
            .g_bit = true,
            .b_bit = true,
            .a_bit = true
        },
        .blend_enable = vk.Bool32.false,
        .src_alpha_blend_factor = vk.BlendFactor.one,
        .dst_alpha_blend_factor = vk.BlendFactor.zero,
        .alpha_blend_op = vk.BlendOp.add,
        .src_color_blend_factor = vk.BlendFactor.one,
        .dst_color_blend_factor = vk.BlendFactor.zero,
        .color_blend_op = vk.BlendOp.add
    };
}

/// Helper function to return a common vk.PipelineColorBlendAttachmentState use case:
/// The pipeline will perform standard alpha channel blending.
pub fn pipeline_color_blend_attachment_alpha_blend() vk.PipelineColorBlendAttachmentState
{
    return .{
        .color_write_mask = .{
            .r_bit = true,
            .g_bit = true,
            .b_bit = true,
            .a_bit = true
        },
        .blend_enable = vk.Bool32.true,
        .src_alpha_blend_factor = vk.BlendFactor.one,
        .dst_alpha_blend_factor = vk.BlendFactor.zero,
        .alpha_blend_op = vk.BlendOp.add,
        .src_color_blend_factor = vk.BlendFactor.src_alpha,
        .dst_color_blend_factor = vk.BlendFactor.one_minus_src_alpha,
        .color_blend_op = vk.BlendOp.add
    };
}

/// Helper function to return a common vk.PipelineDepthStencilStateCreateInfo use case:
/// This pipeline will perform depth testing, preferring fragments with smaller Z values.
pub fn pipeline_depth_stencil_state_default() vk.PipelineDepthStencilStateCreateInfo
{
    return .{
        .depth_test_enable = .true,
        .depth_write_enable = .true,
        .depth_compare_op = .less,
        .depth_bounds_test_enable = .false,
        .min_depth_bounds = 0,
        .max_depth_bounds = 1,
        .stencil_test_enable = .false,
        .front = dummy_stencil_op_state(),
        .back = dummy_stencil_op_state()
    };
}

/// Wraps a vk.Pipeline object, and describes a Vulkan graphics pipeline. The graphics pipeline is a combination of pre-compiled shader modules,
/// configurable fixed functions, and a pipeline layout which describes the shader's uniforms (push constants and descriptor sets).
pub const Pipeline = struct
{
    /// Vulkan context.
    vkc: *vkcontext.VkContext,

    /// List of shader modules used in the pipeline, appended with add_shader_module. These modules should be null after the pipeline has been built.
    shader_modules: std.ArrayList(PipelineShaderModule),
    /// List of dynamic states used by the pipeline.
    dynamic_states: std.ArrayList(vk.DynamicState),
    /// List of descriptor sets used in the pipeline, appended with add_descriptor_set. These descriptor sets should be null after the pipeline is built.
    descriptor_sets: std.ArrayList(PipelineDescriptorSet),
    /// List of color blend attachments (one for every type of framebuffer used in the graphics pipeline) which describe a color blend operation.
    color_blend_attachments: std.ArrayList(vk.PipelineColorBlendAttachmentState),

    /// VkPipelineLayout object specifying the layout of the pipeline (used to describe push constants and descriptor sets).
    pipeline_layout: ?vk.PipelineLayout,
    /// VkPipeline handle, created with the build function.
    pipeline: vk.Pipeline = undefined,

    /// Pointer to a PipelineVertexInput structure, set via set_vertex_input.
    pipeline_vertex_input: *PipelineVertexInput = undefined,

    /// Struct containing information about the pipeline's expected vertex input.
    /// Includes information such as the number of expected attributes and bindings, each of their sizes (strides, number of values per vertex), etc.
    info_vertex_input: vk.PipelineVertexInputStateCreateInfo,

    /// Struct containing information about how the pipeline should assemble vertices into drawable geometry (triangles, lines, or points).
    info_input_assembly: vk.PipelineInputAssemblyStateCreateInfo,

    /// Struct containing pointers to the viewport and scissor objects if they are static, or simply viewport and scissor counts if they are a part of the
    /// pipeline's dynamic state.
    info_viewport: vk.PipelineViewportStateCreateInfo,

    /// Struct containing information about the pipeline's rasterization process. Includes information such as which faces to cull, how to draw polygons (filling
    /// vs. drawing lines) and if depth culling should be enabled.
    info_rasterizer: vk.PipelineRasterizationStateCreateInfo,

    /// Struct containing information about the pipeline's multisampling operations. Multisampling combines the fragment shader results of multiple polygons into
    /// a single pixel, rather than simply overwriting them.
    info_multisampling: vk.PipelineMultisampleStateCreateInfo,

    /// One of the only optional structures, this struct contains information about the pipeline's depth buffering operations, if they are using one.
    info_depth_stencil_testing: ?vk.PipelineDepthStencilStateCreateInfo = null,

    /// Adds a color blend attachment state to the pipeline. At least one is needed before building.
    pub fn add_color_blend_attachment(self: *Pipeline, state: vk.PipelineColorBlendAttachmentState) !void
    {
        const p_ds = try self.color_blend_attachments.addOne(self.vkc.allocator.*);
        p_ds.* = state;
    }

    /// Adds a created descriptor set to the pipeline.
    pub fn add_descriptor_set(self: *Pipeline, descriptor_set: PipelineDescriptorSet) !void
    {
        try self.descriptor_sets.append(self.vkc.allocator.*, descriptor_set);
    }

    /// Tells Vulkan that one aspect of the pipeline will be dynamic (such as it's viewport, which may change if the window gets resized).
    pub fn add_dynamic_state(self: *Pipeline, state: vk.DynamicState) !void
    {
        const p_ds = try self.dynamic_states.addOne(self.vkc.allocator.*);
        p_ds.* = state;
    }

    /// Creates and adds a shader module to the pipeline. 'path' must be a valid path to a pre-compiled shader .spv bytecode file.
    pub fn add_shader_module(self: *Pipeline, path: [*:0]const u8, shader_stage: vk.ShaderStageFlags) !void
    {
        const p_psm = try self.shader_modules.addOne(self.vkc.allocator.*);
        p_psm.* = try PipelineShaderModule.init(self.vkc.device, self.vkc.allocator, path, shader_stage);
    }

    /// Builds the pipeline. Assembles all shader modules and structs and attempts to create a pipeline using their information.
    pub fn build(self: *Pipeline, render_pass: *RenderPass) !void
    {
        const num_shaders = self.shader_modules.items.len;
        var shader_stage_list = try std.ArrayList(vk.PipelineShaderStageCreateInfo).initCapacity(self.vkc.allocator.*, num_shaders);

        const shader_entrypoint = "main";

        for(0..num_shaders) |i|
        {
            const info_shader_stage: vk.PipelineShaderStageCreateInfo = .{
                .stage = self.shader_modules.items[i].shader_stages,
                .module = self.shader_modules.items[i].shader_module,
                .p_name = shader_entrypoint
            };

            try shader_stage_list.append(self.vkc.allocator.*, info_shader_stage);
        }

        const info_dynamic_state: vk.PipelineDynamicStateCreateInfo = .{
            .dynamic_state_count = @truncate(self.dynamic_states.items.len),
            .p_dynamic_states = @ptrCast(self.dynamic_states.items)
        };

        const info_color_blend: vk.PipelineColorBlendStateCreateInfo = .{
            .logic_op_enable = vk.Bool32.false,
            .logic_op = vk.LogicOp.copy,
            .attachment_count = @truncate(self.color_blend_attachments.items.len),
            .p_attachments = @ptrCast(self.color_blend_attachments.items),
            .blend_constants = .{0, 0, 0, 0}
        };

        // TODO: Push constants.

        var set_layouts = try std.ArrayList(vk.DescriptorSetLayout).initCapacity(self.vkc.allocator.*, self.descriptor_sets.items.len);
        defer set_layouts.deinit(self.vkc.allocator.*);

        try set_layouts.resize(self.vkc.allocator.*, self.descriptor_sets.items.len);
        for(0..self.descriptor_sets.items.len) |i|
        {
            set_layouts.items[i] = self.descriptor_sets.items[i].layout;
        }

        const info_pipeline_layout: vk.PipelineLayoutCreateInfo = .{
            .set_layout_count = @truncate(set_layouts.items.len),
            .p_set_layouts = @ptrCast(set_layouts.items),
            .push_constant_range_count = 0
        };

        self.pipeline_layout = try self.vkc.device.createPipelineLayout(&info_pipeline_layout, null);

        const info_pipeline: vk.GraphicsPipelineCreateInfo = .{
            .stage_count = 2,
            .p_stages = @ptrCast(shader_stage_list.items),
            .p_vertex_input_state = &self.info_vertex_input,
            .p_input_assembly_state = &self.info_input_assembly,
            .p_viewport_state = &self.info_viewport,
            .p_rasterization_state = &self.info_rasterizer,
            .p_multisample_state = &self.info_multisampling,
            .p_color_blend_state = &info_color_blend,
            .p_depth_stencil_state = if(self.info_depth_stencil_testing != null) &self.info_depth_stencil_testing.? else null,
            .p_dynamic_state = &info_dynamic_state,
            .layout = self.pipeline_layout.?,
            .render_pass = render_pass.render_pass,
            .subpass = 0,
            .base_pipeline_index = -1
        };

        _ = try self.vkc.device.createGraphicsPipelines(.null_handle, &.{ info_pipeline }, null, @ptrCast(&self.pipeline));

        shader_stage_list.deinit(self.vkc.allocator.*);

        for(self.shader_modules.items, 0..) |_, i|
        {
            self.shader_modules.items[i].deinit(self.vkc.device);
        }
    }

    /// Deinitializes the pipeline.
    pub fn deinit(self: *Pipeline) void
    {
        self.vkc.device.destroyPipeline(self.pipeline, null);
        if(self.pipeline_layout != null)
        {
            self.vkc.device.destroyPipelineLayout(self.pipeline_layout.?, null);
        }
        self.dynamic_states.deinit(self.vkc.allocator.*);
        self.shader_modules.deinit(self.vkc.allocator.*);
        self.descriptor_sets.deinit(self.vkc.allocator.*);
        self.color_blend_attachments.deinit(self.vkc.allocator.*);
    }

    /// Returns a list of shader modules. These may be Vulkan null handles if the pipeline has already been built.
    pub fn get_pipeline_shader_modules(self: *Pipeline) !std.ArrayList(vk.ShaderModule)
    {
        var list = try std.ArrayList(vk.ShaderModule).initCapacity(self.vkc.allocator, self.shader_modules.items.len);
        for(self.shader_modules.items.len) |module|
        {
            try list.append(module);
        }

        return list;
    }

    /// Initializes a Pipeline object.
    pub fn init(vkc: *vkcontext.VkContext) !Pipeline
    {
        const p: Pipeline = .{
            .vkc = vkc,
            .shader_modules = try std.ArrayList(PipelineShaderModule).initCapacity(vkc.allocator.*, 0),
            .dynamic_states = try std.ArrayList(vk.DynamicState).initCapacity(vkc.allocator.*, 0),
            .descriptor_sets = try std.ArrayList(PipelineDescriptorSet).initCapacity(vkc.allocator.*, 0),
            .color_blend_attachments = try std.ArrayList(vk.PipelineColorBlendAttachmentState).initCapacity(vkc.allocator.*, 0),
            .pipeline_layout = null,

            .info_vertex_input = pipeline_vertex_input_no_input(),
            .info_input_assembly = pipeline_input_assembly_triangle_list(),
            .info_viewport = pipeline_viewport_state_dynamic(),
            .info_rasterizer = pipeline_rasterizer_fill_triangle_cull_back_no_depth(),
            .info_multisampling = pipeline_multisample_no_multisampling()
        };

        return p;
    }

    /// Sets the pipeline's vertex input state using a PipelineVertexInput structure. The PipelineVertexInput should be built prior to calling
    /// this function.
    pub fn set_vertex_input(self: *Pipeline, vertex_input: *PipelineVertexInput) void
    {
        self.pipeline_vertex_input = vertex_input;

        self.info_vertex_input = .{
            .vertex_attribute_description_count = @truncate(vertex_input.attribute_descriptions.items.len),
            .p_vertex_attribute_descriptions = @ptrCast(vertex_input.attribute_descriptions.items),
            .vertex_binding_description_count = 1,
            .p_vertex_binding_descriptions = @ptrCast(&vertex_input.binding_description)
        };
    }
};
