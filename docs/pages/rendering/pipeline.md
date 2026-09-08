# `pipeline`

Contains everything related to creating and building Vulkan graphics pipelines.

## PipelineVertexInput (`struct`)

Struct used for setting pipeline vertex input.

### Fields

`allocator: *const std.mem.Allocator` - CPU Allocator.

`attribute_descriptions: std.ArrayList(vk.VertexInputAttributeDescription)` - List of attribute descriptions. Do not access directly, if you need to add attribute descriptions, use **`add_attribute`**.

`binding_descriptions: std.ArrayList(vk.VertexInputBindingDescription)` - The binding description structure is the top-most structure used to describe a vertex input binding. A pipeline's vertex input is made up of multiple vertex input bindings, though in many cases you'll likely only need one. One binding description could be used to specify vertices, while another could be used to specify instances, for example.

### Public Functions

**`add_attribute(self: *PipelineVertexInput, binding: u32, location: u32, format: vk.Format, offset: u32) !void`**

Adds an attribute to the pipeline vertex input. An attribute is a scalar or vector value given to each vertex or instance drawn. On a per-vertex basis, an attribute could represent a vertex's position, color, texture coordinate, etc. On a per-instance basis, an attribute could represent a model position, scale, color, etc.

**`build(self: *PipelineVertexInput, binding_description_index: u32, input_rate: vk.VertexInputRate) !void`**

Compiles a binding description. Should be called after adding all attributes to the structure.

**`deinit(self: *PipelineVertexInput) void`**

Deinitializes the `PipelineVertexInput`.

**`init(allocator: *const std.mem.Allocator) !PipelineVertexInput`**

Initializes and returns a `PipelineVertexInput`.

## PipelineShaderModule (`struct`)

Structure that handles a Vulkan pipeline shader module.

### Fields

`shader_module: vk.ShaderModule = undefined` - Handle for the pipeline shader module.

`shader_stages: vk.ShaderStageFlags` - Shader stages that the module is compiled for.

### Public Functions

**`deinit(self: PipelineShaderModule, device: *vk.DeviceProxy) void`**

Destroy a pipeline shader module.

**`init(device: *vk.DeviceProxy, allocator: *const std.mem.Allocator, path: [*:0]const u8, shader_stages: vk.ShaderStageFlags) !PipelineShaderModule`**

Initialize a pipeline shader module. The `path` must point to a precompiled shader SPV file. The `shader_stages` refers to the stages that this module should be used for (vertex, fragment, tesselation, etc.)

### Private Functions

**`load_spv_file(allocator: *const std.mem.Allocator, path: [*:0]const u8) ![]u8`**

Load a shader .spv file and return it's data as a slice.

## PipelineDescriptorSet (`struct`)

Specifies a set of pipeline resource descriptors, which are how shaders access global (uniform) variables such as textures or projection matrices.

### Fields

`interface: *vkcontext.VkInterface` - `VkInterface` handle.

`vk_allocator: *VulkanAllocator` - Allocates the Vulkan memory the descriptor sets use.

`set_count: u16` - Number of descriptor sets included (typically matches the `image_count` in the swap chain).

`bindings: std.ArrayList(DescriptorBinding)` - List of `DescriptorBinding`s. See the `DescriptorBinding` structure below for details.

`layout: vk.DescriptorSetLayout = undefined` - Layout of the descriptor set.

`pool: vk.DescriptorPool = undefined` - Pool that the descriptor objects are allocated from.

`sets: []vk.DescriptorSet = undefined` - The descriptor sets.

### Enums

#### `DescriptorBindingType`

**buffer** - Buffer binding type.

**image** - Image binding type.

### Structures

#### `DescriptorBindingBufferInfo`

See the `DescriptorBindingInfo` union.

##### Fields

`buffer_size: vk.DeviceSize` - Size of the buffer.

`buffers: ?[]VulkanAllocator.VulkanBufferAllocation = null` - The allocated buffers. You do not need to set these, they are allocated when the descriptor set is built.

#### `DescriptorBindingImageInfo`

See the `DescriptorBindingInfo` union.

##### Fields

`image_sampler: vk.Sampler` - VkSampler object describing how the shader should sample the image.

`image_view: vk.ImageView` - VkImageView containing the image itself.

`image_layout: vk.ImageLayout` - Describes the layout of the image.

#### `DescriptorBinding`

Struct describing the information and requirements for a descriptor binding. Also contains the `VkDescriptorSetLayoutBinding` for the binding.

##### Fields

`binding_index: u32` - Index of the descriptor binding.

`type: vk.DescriptorType` - Descriptor type.

`shader_stage: vk.ShaderStageFlags` - Shader stages this descriptor is being bound to.

`info: DescriptorBindingInfo` - See the `DescriptorBindingInfo` union.

`binding: vk.DescriptorSetLayoutBinding = undefined` - Set when this binding is added to the `PipelineDescriptorSet`.

### Unions

#### `DescriptorBindingInfo` (Tag: `DescriptorBindingBufferInfo`)

There are two types of data to pass into descriptors: buffers, for generic/numerical data, and images, typically for textures. This union allows you to select either/or.

##### Values

**buffer: `DescriptorBindingBufferInfo`** - Buffer binding for sending numerical data (such as matrices) to the shader.

**image: `DescriptorBindingImageInfo`** - Image binding for sending image/texture data to the shader.

### Public Functions

**`add_binding(self: *PipelineDescriptorSet, binding: DescriptorBinding) !void`**

Adds a descriptor binding to the container. See the `DescriptorBinding` struct.

**`build(self: *PipelineDescriptorSet) !void`**

Creates the descriptor set resources in Vulkan.

**`deinit(self: *PipelineDescriptorSet) void`**

Deinitializes the descriptor sets.

**`init(allocator: *const std.mem.Allocator) !PipelineVertexInput`**

Initializes an empty descriptor set container.

**`place_data(self: *PipelineDescriptorSet, set_index: u16, binding_index: u16, comptime T: type, data: []T, offset: vk.DeviceSize) !void`**

Places data into a descriptor set (index determined by `set_index`, and binding determined by the `binding_index`), at offset `offset`.

### Private Functions

**`create_descriptor_pool(self: *PipelineDescriptorSet) !void`**

Creates the descriptor pool used to allocate the descriptor sets.

## Pipeline (`struct`)

Wraps a `VkPipeline` object, and describes a Vulkan graphics pipeline. The graphics pipeline is a combination of pre-compiled shader modules, configurable fixed functions, and a pipeline layout which describes the shader's uniforms (push constants and descriptor sets).

### Fields

`interface: *vkcontext.VkInterface` - Vulkan interface.

`shader_modules: std.ArrayList(PipelineShaderModule)` - List of shader modules used in the pipeline, appended with **`add_shader_module`**. These modules should be null after the pipeline has been built.

`dynamic_states: std.ArrayList(vk.DynamicState)` - List of dynamic states used by the pipeline.

`descriptor_sets: std.ArrayList(PipelineDescriptorSet)` - List of descriptor sets used in the pipeline, appended with **`add_descriptor_set`**. These descriptor sets should be null after the pipeline is built.

`color_blend_attachments: std.ArrayList(vk.PipelineColorBlendAttachmentState)` - List of color blend attachments (one for every type of framebuffer used in the graphics pipeline) which describe a color blend operation.

`push_constant_ranges: std.ArrayList(vk.PushConstantRange)` - List of push constant ranges. These are small packets of data that can be sent to the GPU, analogous to uniform variables in OpenGL shaders.

`pipeline_layout: ?vk.PipelineLayout` - `VkPipelineLayout` object specifying the layout of the pipeline (used to describe push constants and descriptor sets).

`pipeline: vk.Pipeline = undefined` - `VkPipeline` handle, set/created with the build function.

`pipeline_vertex_input: *PipelineVertexInput = undefined` - Pointer to a `PipelineVertexInput` structure, set/created via **`set_vertex_input`**.

`info_vertex_input: vk.PipelineVertexInputStateCreateInfo` - Struct containing information about the pipeline's expected vertex input. Includes information such as the number of expected attributes and bindings, each of their sizes (strides, number of values per vertex), etc.

`info_input_assembly: vk.PipelineInputAssemblyStateCreateInfo` - Struct containing information about how the pipeline should assemble vertices into drawable geometry (triangles, lines, or points).

`info_viewport: vk.PipelineViewportStateCreateInfo` - Struct containing pointers to the viewport and scissor objects if they are static, or simply viewport and scissor counts if they are a part of the pipeline's dynamic state.

`info_rasterizer: vk.PipelineRasterizationStateCreateInfo` - Struct containing information about the pipeline's rasterization process. Includes information such as which faces to cull, how to draw polygons (filling vs. drawing lines) and if depth culling should be enabled.

`info_multisampling: vk.PipelineMultisampleStateCreateInfo` - Struct containing information about the pipeline's multisampling operations. Multisampling combines the fragment shader results of multiple polygons into a single pixel, rather than simply overwriting them.

`info_depth_stencil_testing: ?vk.PipelineDepthStencilStateCreateInfo = null` - One of the only optional "CreateInfo" structures, this struct contains information about the pipeline's depth buffering operations, if they are using one.

### Enums

#### `BuildMode`

**FixedRenderPass** - Render pass build mode.

**Dynamic** - Used for dynamic rendering. **NOTE:** There is currently no way to support dynamic rendering with the current VkInstance. This feature is planned for an upcoming release.

### Unions

#### `BuildInfo` (Tag: `BuildMode`)

Used for building the pipeline.

##### Values

**FixedRenderPass: `\*RenderPass`** - Used for building a pipeline to use with a render pass.

**Dynamic: `vk.PipelineRenderingCreateInfo`** - Used for building a dynamically rendered pipeline.

### Public Functions

**`add_color_blend_attachment(self: *Pipeline, state: vk.PipelineColorBlendAttachmentState) !void`**

Adds a color blend attachment state to the pipeline. At least one is needed before building.

**`add_descriptor_set(self: *Pipeline, descriptor_set: PipelineDescriptorSet) !void`**

Adds a created descriptor set to the pipeline.

**`add_dynamic_state(self: *Pipeline, state: vk.DynamicState) !void`**

Tells Vulkan that one aspect of the pipeline will be dynamic (such as it's viewport, which may change if the window gets resized).

**`add_push_constant_range(self: *Pipeline, offset: u32, size: u32, shader_stage: vk.ShaderStageFlags) !void`**

Adds a push constant range to the pipeline.

**`add_shader_module(self: *Pipeline, path: [*:0]const u8, shader_stage: vk.ShaderStageFlags) !void`**

Creates and adds a shader module to the pipeline. `path` must be a valid path to a pre-compiled shader .spv bytecode file.

**`build(self: *Pipeline, build_info: BuildInfo) !void`**

Builds the pipeline. Assembles all shader modules and structs and attempts to create a pipeline using their information. Can either build using a fixed render pass or build into a dynamic rendering pipeline.

**`deinit(self: *Pipeline) void`**

Deinitializes the pipeline.

**`get_pipeline_shader_modules(self: *Pipeline) !std.ArrayList(vk.ShaderModule)`**

Returns a list of shader modules. These will likely be Vulkan null handles if the pipeline has already been built.

**`init(interface: *vkcontext.VkInterface) !Pipeline`**

Initializes a `Pipeline` object.

**`set_vertex_input(self: *Pipeline, vertex_input: *PipelineVertexInput) void`**

Sets the pipeline's vertex input state using a `PipelineVertexInput` structure. The `PipelineVertexInput` should be built prior to calling this function.

## Errors

### `PipelineError`

**CouldntLoadShaderFile**: There was an issue loading the shader SPV file (most likely the file couldn't be found).

**UnsupportedDescriptorBindingType**: As of 0.2.0, the supported descriptor types are `uniform_buffer` for buffers and `combined_image_sampler` for images. Anything else will trigger an error.

**InvalidDescriptorBinding**: Returned by **`PipelineDescriptorSet.place_data`** if the `set` exceeds `set_count`, or the binding is an image type instead of a buffer type.

## Public Functions

**`create_pipeline_descriptor_set_layout_binding(binding: u32, descriptor_type: vk.DescriptorType, shader_stage: vk.ShaderStageFlags) vk.DescriptorSetLayoutBinding`**

Creates a pipeline descriptor set layout binding, populating it with the arguments provided. This struct describes a single binding for global variables in the pipeline's shader.

**`pipeline_vertex_input_no_input() vk.PipelineVertexInputStateCreateInfo`**

Helper function to return a common vk.PipelineVertexInputStateCreateInfo use case:

No vertex input will be passed through the pipeline. Instead, vertex input must be specified in the shader itself.

**`pipeline_input_assembly_triangle_list() vk.PipelineInputAssemblyStateCreateInfo`**

Helper function to return a common vk.PipelineInputAssemblyStateCreateInfo use case:

Vertex input will be assembled into a list of rasterized triangles, with no element buffer (indices) or primitive restart (useless for lists anyways).

**`pipeline_viewport_state_dynamic() vk.PipelineViewportStateCreateInfo`**

Helper function to return a common vk.PipelineViewportStateCreateInfo use case:

The viewport is included in the pipeline's dynamic state, and doesn't need to be specified at pipeline creation time.

**`pipeline_rasterizer_fill_triangle_cull_back_no_depth() vk.PipelineRasterizationStateCreateInfo`**

Helper function to return a common vk.PipelineRasterizationStateCreateInfo use case:

The pipeline rasterizer will fill the front (clockwise) faces of triangles only, and not worry about depth culling.

**`pipeline_multisample_no_multisampling() vk.PipelineMultisampleStateCreateInfo`**

Helper function to return a common vk.PipelineMultisampleStateCreateInfo use case:

The pipeline will not perform multisampling operations.

**`pipeline_color_blend_attachment_no_blend() vk.PipelineColorBlendAttachmentState`**

Helper function to return a common vk.PipelineColorBlendAttachmentState use case:

The pipeline will not perform color blend operations, and will simply overwrite any colors instead.

**`pipeline_color_blend_attachment_alpha_blend() vk.PipelineColorBlendAttachmentState`**

Helper function to return a common vk.PipelineColorBlendAttachmentState use case:

The pipeline will perform standard alpha channel blending.

**`pipeline_depth_stencil_state_default() vk.PipelineDepthStencilStateCreateInfo`**

Helper function to return a common vk.PipelineDepthStencilStateCreateInfo use case:

This pipeline will perform depth testing, preferring fragments with smaller Z values.

## Private Functions

**`dummy_stencil_op_state() vk.StencilOpState`**

Returns the "null" case, signifying to the `vk.PipelineDepthStencilStateCreateInfo` that no stencils will be used.