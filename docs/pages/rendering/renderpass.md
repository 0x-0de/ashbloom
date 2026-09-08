# `renderpass`

Contains the `RenderPass` structure.

## RenderPass (`struct`)

A render pass is a (now deprecated) structure describing what framebuffers will be used in a render operation with a graphics pipeline, and how to handle framebuffer contents before, during, and after rendering operations (for example, if a framebuffer's contents be cleared before a specific rendering operation or not).

### Fields

`interface: *vkcontext.VkInterface` - Vulkan interface.

`render_pass: vk.RenderPass = undefined` - Render pass handle.

`attachment_descriptions: std.ArrayList(vk.AttachmentDescription)` - List of attachment descriptions. This field should not be accessed externally, use **`add_attachment_description`** or any of its variants and **`build`** to interact with it.

`subpasses: std.ArrayList(Subpass)` - List of subpasses. This field should not be accessed externally, use **`add_subpass`** or any of its variants and **`build`** to interact with it.

### Structures

#### `Subpass`

Structure that describes a render pass subpass, including its attachment reference and its dependencies. A subpass describes a "logical phase" of a render pass, such as a geometry pass in which G-buffer information (such as depth, albedo, and normal data) is recorded to the framebuffer, or a lighting pass where said information is used to perform the final shading step. These steps can be split into multiple render passes, but subpasses allow Vulkan to reorder and thus potentially optimize rendering operations as a result.

##### Fields

`color_attachment_index: u32` - Index of the `VkAttachmentDescription` that this subpass is using for the color attachment.

`depth_stencil_attachment_index: ?u32 = null` - Index of the `VkAttachmentDescription` that this subpass is using for the depth-stencil attachment (if there is one).

`color_attachment_layout: vk.ImageLayout` - Layout that the color attachment should have during the subpass.

`depth_stencil_attachment_layout: ?vk.ImageLayout = null` - Layout that the depth-stencil attachment should have during the subpass (if there is one).

`subpass_bind_point: vk.PipelineBindPoint` - Specifies which part of the pipeline this subpass aims to perform with.

`subpass_dependency: vk.SubpassDependency` - Subpasses and render passes automatically take care of image transitions for the framebuffer images. This subpass dependency specifies how exactly these image transitions should be handled (what part of the pipeline should image transitions take place? which other subpasses should this subpass's image transitions wait for, if any? etc.) The `dst_subpass` field is updated automatically when building, and may be given an undefined value.

### Public Functions

**`add_subpass(self: *RenderPass, subpass: Subpass) !void`**

Adds the `subpass` to the render pass. Use before building.

**`build(self: *RenderPass) !void`**

Builds the render pass. Should only be used if at least one attachment description and subpass have been added to this render pass. This function also clears the `attachment_descriptions` and `subpasses` lists.

**`deinit(self: *RenderPass) void`**

Deinitialize the render pass and free its associated memory.

**`init(interface: *vkcontext.VkInterface) !RenderPass`**

Creates a new render pass object. This object will need to have attachment descriptions and subpasses added to it before it can be built.