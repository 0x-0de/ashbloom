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
    /// Vulkan context.
    context: *vkcontext.VkContext,
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
        /// Index of the vkAttachmentDescription that this subpass is using.
        attachment_index: u32,
        /// Layout that the framebuffer should have during the subpass.
        attachment_layout: vk.ImageLayout,

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
        try self.attachment_descriptions.append(self.context.allocator.*, attachment_description);
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
        try self.subpasses.append(self.context.allocator.*, subpass);
    }

    /// Builds the render pass. Should only be used if at least one attachment description and subpass have been added to this render pass. This function also
    /// clears the attachment_descriptions and subpasses lists.
    pub fn build(self: *RenderPass) !void
    {
        defer
        {
            self.attachment_descriptions.deinit(self.context.allocator.*);
            self.subpasses.deinit(self.context.allocator.*);
        }

        var attachment_references = try std.ArrayList(vk.AttachmentReference).initCapacity(self.context.allocator.*, 0);
        defer attachment_references.deinit(self.context.allocator.*);

        var subpass_descriptions = try std.ArrayList(vk.SubpassDescription).initCapacity(self.context.allocator.*, 0);
        defer subpass_descriptions.deinit(self.context.allocator.*);

        var subpass_dependencies = try std.ArrayList(vk.SubpassDependency).initCapacity(self.context.allocator.*, 0);
        defer subpass_dependencies.deinit(self.context.allocator.*);

        for(self.subpasses.items) |subpass|
        {
            const att_ref: vk.AttachmentReference = .{
                .attachment = subpass.attachment_index,
                .layout = subpass.attachment_layout
            };

            const ref_index = attachment_references.items.len;
            try attachment_references.append(self.context.allocator.*, att_ref);

            const sp_desc: vk.SubpassDescription = .{
                .pipeline_bind_point = subpass.subpass_bind_point,
                .color_attachment_count = 1,
                .p_color_attachments = @ptrCast(&attachment_references.items[ref_index])
            };

            try subpass_descriptions.append(self.context.allocator.*, sp_desc);

            var dependency = subpass.subpass_dependency;
            dependency.dst_subpass = @truncate(ref_index);

            try subpass_dependencies.append(self.context.allocator.*, dependency);
        }

        const info_render_pass: vk.RenderPassCreateInfo = .{
            .attachment_count = @truncate(self.attachment_descriptions.items.len),
            .p_attachments = @ptrCast(self.attachment_descriptions.items),
            .subpass_count = @truncate(subpass_descriptions.items.len),
            .p_subpasses = @ptrCast(subpass_descriptions.items),
            .dependency_count = @truncate(subpass_dependencies.items.len),
            .p_dependencies = @ptrCast(subpass_dependencies.items)
        };

        self.render_pass = try self.context.device.createRenderPass(&info_render_pass, null);
    }

    /// Deinitialize the render pass and free its associated memory.
    pub fn deinit(self: *RenderPass) void
    {
        self.context.device.destroyRenderPass(self.render_pass, null);
    }

    /// Creates a new render pass object. This object will need to have attachment descriptions and subpasses added to it before it can be built.
    pub fn init(context: *vkcontext.VkContext) !RenderPass
    {
        const rp: RenderPass = .{
            .context = context,
            .attachment_descriptions = try std.ArrayList(vk.AttachmentDescription).initCapacity(context.allocator.*, 0),
            .subpasses = try std.ArrayList(Subpass).initCapacity(context.allocator.*, 0)
        };

        return rp;
    }
};

const vk_test = @import("../utils/testing/test_utils.zig");
const Swapchain = @import("swapchain.zig").Swapchain;
const commands = @import("commands.zig");

test "Render pass init and build"
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

    var swapchain = try Swapchain.init(window.glfw_handle, &vk_context, pool, 1);
    defer swapchain.deinit();

    var rp = try vk_test.create_testing_color_render_pass(&vk_context, swapchain);
    rp.deinit();
}