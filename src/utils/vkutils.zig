const ash = @import("../root.zig");
const vk = ash.vk;

pub const VulkanFormatError = error
{
    FormatNotSupported,
    FormatHasNoSize,
    NoValidFormatsFound
};

/// Returns the size, in bytes, of a complete pixel value in the given format.
pub fn get_vulkan_format_size(format: vk.Format) VulkanFormatError!u32
{
    const code: i32 = @intFromEnum(format);
    return switch(code)
    {
        // Undefined.
        0 => VulkanFormatError.FormatHasNoSize,
        // R4G4_UNORM_PACK8
        1 => 1,
        // 16-bit packed formats.
        2...8 => 2,
        // Regular 8-bit monochrome formats.
        9...15 => 1,
        // Regular 16-bit RG formats.
        16...22 => 2,
        // Regular 24-bit RGB/BGR formats.
        23...36 => 3,
        // Regular 32-bit RGBA/BGRA formats.
        37...50 => 4,
        // 32-bit packed formats.
        51...69 => 4,
        // Regular 16-bit monochrome formats.
        70...76 => 2,
        // Regular 32-bit RG formats.
        77...83 => 4,
        // Regular 48-bit RGB formats.
        84...90 => 6,
        // Regular 64-bit RGBA formats.
        91...97 => 8,
        // Regular 32-bit monochrome, RG, RGB, and RGBA formats.
        98...100 => 4,
        101...103 => 8,
        104...106 => 12,
        107...109 => 16,
        // Regular 64-bit monochrome, RG, RGB, and RGBA formats.
        110...112 => 8,
        113...115 => 16,
        116...118 => 24,
        119...121 => 32,
        // B10G11R11_UFLOAT_PACK32, E5B9G9R9_UFLOAT_PACK32.
        122, 123 => 4,
        // 16-bit depth buffer.
        124 => 2,
        // X8_D24_UNORM_PACK32, 32-bit depth buffer.
        125, 126 => 4,
        // 8-bit stencil buffer.
        127 => 1,
        // Depth and stencil buffers: 16-bit + 8-bit, 24-bit + 8-bit, 32-bit + 8-bit.
        128 => 3,
        129 => 4,
        130 => 5,
        else => VulkanFormatError.FormatNotSupported
    };
}

/// Picks the most well-suited from a list of image formats based on preferred image tiling and features.
pub fn choose_image_format(vk_interface: *ash.VkInterface, preferred_tiling: vk.ImageTiling, preferred_features: vk.FormatFeatureFlags, formats: []const vk.Format) VulkanFormatError!vk.Format
{
    for(formats) |f|
    {
        const pf: vk.Flags = @bitCast(preferred_features);
        const properties = vk_interface.context.instance.getPhysicalDeviceFormatProperties(vk_interface.physical_device.?, f);
     
        const ltf: vk.Flags = @bitCast(properties.linear_tiling_features);
        const otf: vk.Flags = @bitCast(properties.optimal_tiling_features);

        if(preferred_tiling == .linear and (ltf & pf) == pf) return f;
        if(preferred_tiling == .optimal and (otf & pf) == pf) return f;
    }

    return VulkanFormatError.NoValidFormatsFound;
}

/// Calls choose_image_format for a list of depth buffer attachments with optimal tiling and the depth-stencil feature.
pub fn choose_best_depth_buffer_format(vk_interface: *ash.VkInterface) VulkanFormatError!vk.Format
{
    return choose_image_format(vk_interface, .optimal, .{ .depth_stencil_attachment_bit = true }, &.{ .d32_sfloat, .d32_sfloat_s8_uint, .d24_unorm_s8_uint });
}
