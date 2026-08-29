const std = @import("std");
const print = std.debug.print;

const vk = @import("vulkan");
const glfw = @import("glfw");

const vkcontext = @import("vkcontext.zig");
const sc = @import("swapchain.zig");

/// A render pass is a (now deprecated) structure describing what framebuffers will be used in a render operation with a graphics pipeline,
/// and how to handle framebuffer contents before, during, and after rendering operations (for example, if a framebuffer's contents be cleared
/// before a specific rendering operation or not).
pub const RenderPass = struct
{
    /// Vulkan interface.
    interface: *vkcontext.VkInterface,
    /// Render pass handle.
    render_pass: vk.RenderPass = undefined,

    /// List of attachment descriptions. This field should not be accessed externally, use add_attachment_description(...) or any of its variants and build() to
    /// interact with it.
    attachment_descriptions: std.ArrayList(vk.AttachmentDescription),
    /// List of subpasses. This field should not be accessed externally, use add_subpass(...) or any of its variants and build() to interact with it.
    subpasses: std.ArrayList(Subpass),

    /// Structure that describes a render pass subpass, including its attachment reference and its dependencies.
    pub const Subpass = struct
    {
        /// Index of the vkAttachmentDescription that this subpass is using for the color attachment.
        color_attachment_index: u32,
        /// Index of the vkAttachmentDescription that this subpass is using for the depth-stencil attachment (if there is one).
        depth_stencil_attachment_index: ?u32 = null,
        /// Layout that the color attachment should have during the subpass.
        color_attachment_layout: vk.ImageLayout,
        /// Layout that the depth-stencil attachment should have during the subpass.
        depth_stencil_attachment_layout: ?vk.ImageLayout = null,

        /// Specifies which part of the pipeline this subpass aims to perform with.
        subpass_bind_point: vk.PipelineBindPoint,

        /// Subpasses and render passes automatically take care of image transitions for the framebuffer images. This subpass dependency specifies how exactly
        /// these image transitions should be handled (what part of the pipeline should image transitions take place? which other subpasses should this subpass's
        /// image transitions wait for, if any? etc.) The "dst_subpass" field is updated automatically when building, and may be given an undefined value.
        subpass_dependency: vk.SubpassDependency
    };

    /// Adds an attachment description to the render pass. Use before building. An attachment description describes the framebuffer attachment this render pass will
    /// be used for, which parts of it specifically will need to be used (i.e. depth buffers, color buffers, or stencil buffers), and what to do before and after rendering
    /// operations have started/completed.
    pub fn add_attachment_description(self: *RenderPass, attachment_description: vk.AttachmentDescription) !void
    {
        try self.attachment_descriptions.append(self.interface.allocator.*, attachment_description);
    }

    /// Adds an attachment description to the render pass, assumes the number of samples is 1 (no multisampling) and that stencils aren't being used. Use before building.
    /// See the description for add_attachment_description(...) if you want to know more about render pass attachment descriptions.
    pub fn add_attachment_description_no_stencil_multisample(self: *RenderPass, format: vk.Format, load_op: vk.AttachmentLoadOp, store_op: vk.AttachmentStoreOp,
    initial_layout: vk.ImageLayout, final_layout: vk.ImageLayout) !void
    {
        const att_desc: vk.AttachmentDescription = .{
            .format = format,
            .samples = .{
                .@"1_bit" = true
            },
            .load_op = load_op,
            .store_op = store_op,
            .stencil_load_op = vk.AttachmentLoadOp.dont_care,
            .stencil_store_op = vk.AttachmentStoreOp.dont_care,
            .initial_layout = initial_layout,
            .final_layout = final_layout
        };

        try self.add_attachment_description(att_desc);
    }

    /// Adds a subpass to the render pass. Use before building. A subpass describes a "logical phase" of a render pass, such as a geometry pass in which G-buffer
    /// information (such as depth, albedo, and normal data) is recorded to the framebuffer, or a lighting pass where said information is used to perform the
    /// final shading step. These steps can be split into multiple render passes, but subpasses allow Vulkan to reorder and thus potentially optimize rendering
    /// operations as a result.
    pub fn add_subpass(self: *RenderPass, subpass: Subpass) !void
    {
        try self.subpasses.append(self.interface.allocator.*, subpass);
    }

    /// Builds the render pass. Should only be used if at least one attachment description and subpass have been added to this render pass. This function also
    /// clears the attachment_descriptions and subpasses lists.
    pub fn build(self: *RenderPass) !void
    {
        defer
        {
            self.attachment_descriptions.deinit(self.interface.allocator.*);
            self.subpasses.deinit(self.interface.allocator.*);
        }

        var attachment_references = try std.ArrayList(vk.AttachmentReference).initCapacity(self.interface.allocator.*, 0);
        defer attachment_references.deinit(self.interface.allocator.*);

        var subpass_descriptions = try std.ArrayList(vk.SubpassDescription).initCapacity(self.interface.allocator.*, 0);
        defer subpass_descriptions.deinit(self.interface.allocator.*);

        var subpass_dependencies = try std.ArrayList(vk.SubpassDependency).initCapacity(self.interface.allocator.*, 0);
        defer subpass_dependencies.deinit(self.interface.allocator.*);

        for(self.subpasses.items) |subpass|
        {
            const att_ref_color: vk.AttachmentReference = .{
                .attachment = subpass.color_attachment_index,
                .layout = subpass.color_attachment_layout
            };

            var att_ref_depth: ?vk.AttachmentReference = null;

            const ref_index = attachment_references.items.len;
            try attachment_references.append(self.interface.allocator.*, att_ref_color);

            if(subpass.depth_stencil_attachment_index != null)
            {
                att_ref_depth = .{
                    .attachment = subpass.depth_stencil_attachment_index.?,
                    .layout = subpass.depth_stencil_attachment_layout.?
                };

                try attachment_references.append(self.interface.allocator.*, att_ref_depth.?);
            }

            const sp_desc: vk.SubpassDescription = .{
                .pipeline_bind_point = subpass.subpass_bind_point,
                .color_attachment_count = 1,
                .p_color_attachments = @ptrCast(&attachment_references.items[ref_index]),
                .p_depth_stencil_attachment = if(att_ref_depth != null) @ptrCast(&attachment_references.items[ref_index + 1]) else null
            };

            try subpass_descriptions.append(self.interface.allocator.*, sp_desc);

            var dependency = subpass.subpass_dependency;
            dependency.dst_subpass = @truncate(ref_index);

            try subpass_dependencies.append(self.interface.allocator.*, dependency);
        }

        const info_render_pass: vk.RenderPassCreateInfo = .{
            .attachment_count = @truncate(self.attachment_descriptions.items.len),
            .p_attachments = @ptrCast(self.attachment_descriptions.items),
            .subpass_count = @truncate(subpass_descriptions.items.len),
            .p_subpasses = @ptrCast(subpass_descriptions.items),
            .dependency_count = @truncate(subpass_dependencies.items.len),
            .p_dependencies = @ptrCast(subpass_dependencies.items)
        };

        self.render_pass = try self.interface.device.createRenderPass(&info_render_pass, null);
    }

    /// Deinitialize the render pass and free its associated memory.
    pub fn deinit(self: *RenderPass) void
    {
        self.interface.device.destroyRenderPass(self.render_pass, null);
    }

    /// Creates a new render pass object. This object will need to have attachment descriptions and subpasses added to it before it can be built.
    pub fn init(interface: *vkcontext.VkInterface) !RenderPass
    {
        const rp: RenderPass = .{
            .interface = interface,
            .attachment_descriptions = try std.ArrayList(vk.AttachmentDescription).initCapacity(interface.allocator.*, 0),
            .subpasses = try std.ArrayList(Subpass).initCapacity(interface.allocator.*, 0)
        };

        return rp;
    }
};
