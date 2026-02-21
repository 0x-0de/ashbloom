const std = @import("std");
const print = std.debug.print;

const glfw = @import("glfw");
const vk = @import("vulkan");

/// Wrapper function. The vulkan-zig wrapper gets all function pointers dynamically, so there needs to be some user-defined function which
/// wraps vkGetInstanceProcAddr that vulkan-zig can use.
fn vk_get_instance_proc_address(instance: vk.Instance, proc_name: [*:0]const u8) vk.PfnVoidFunction
{
    const func = glfw.getInstanceProcAddress(@intFromEnum(instance), proc_name);
    return func;
}

/// Callback function. Vulkan validation layers require some kind of message callback to actually print statements to the console.
fn vk_debug_validation_layer_message_callback(message_severity: vk.DebugUtilsMessageSeverityFlagsEXT, message_types: vk.DebugUtilsMessageTypeFlagsEXT,
                                              p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, p_user_data: ?*anyopaque) callconv(.c) vk.Bool32
{
    _ = message_severity;
    _ = message_types;
    
    _ = p_user_data;

    print("[VK|VAL] {s}\n", .{p_callback_data.?.p_message.?});

    return vk.Bool32.false;
}

/// Helper function to return the vk.DebugUtilsMessengerCreateInfoEXT struct which defines when we when and where we want the validation
/// layer to callback to. Needs to be a seperate function from debug_setup_vulkan_messenger as create_instance_handle also uses it.
fn get_debug_messenger_create_info() vk.DebugUtilsMessengerCreateInfoEXT
{
    return .{
        .message_severity = .{
            .verbose_bit_ext = true,
            .warning_bit_ext = true,
            .error_bit_ext = true
        },
        .message_type = .{
            .general_bit_ext = true,
            .validation_bit_ext = true,
            .performance_bit_ext = true
        },
        .pfn_user_callback = vk_debug_validation_layer_message_callback
    };
}

/// Helper function that checks the equality of two null-terminated strings.
fn c_strequal(a: [*:0]const u8, b: [*:0]const u8) bool
{
    var index: usize = 0;
    while(a[index] == b[index])
    {
        if(a[index] == 0 or b[index] == 0) break;
        index += 1;
    }
    return a[index] == b[index];
}

/// Print out all items in a generic name list.
fn debug_print_name_list(names: std.ArrayList([*:0]const u8), label: []const u8) void
{
    print("[{s}], count {d}:\n", .{label, names.items.len});
    for(0..names.items.len) |i|
    {
        print("\t{s}\n", .{names.items[i]});
    }
    print("\t[End of list.]\n", .{});
}

/// Print out the names of all Vulkan extensions in a provided vk.ExtensionProperties list.
fn debug_print_extension_list(extensions: std.ArrayList(vk.ExtensionProperties), label: []const u8) void
{
    print("[{s}] extensions, count {d}:\n", .{label, extensions.items.len});
    for(0..extensions.items.len) |i|
    {
        print("\t{s}\n", .{extensions.items[i].extension_name});
    }
    print("\t[End of list.]\n", .{});
}

/// Print out the names of all Vulkan layers in a provided vk.LayerProperties list.
fn debug_print_layer_list(layers: std.ArrayList(vk.LayerProperties), label: []const u8) void
{
    print("[{s}] layers, count {d}:\n", .{label, layers.items.len});
    for(0..layers.items.len) |i|
    {
        print("\t{s}\n", .{layers.items[i].layer_name});
    }
    print("\t[End of list.]\n", .{});
}

/// Helper struct containing the swapchain formats, capabilities (such as max image width/height), and presentation modes.
pub const DeviceSwapchainSupport = struct
{
    capabilities: vk.SurfaceCapabilitiesKHR = undefined,
    supported_formats: std.ArrayList(vk.SurfaceFormatKHR) = undefined,
    supported_presentation_modes: std.ArrayList(vk.PresentModeKHR) = undefined,

    pub fn deinit(self: *DeviceSwapchainSupport, allocator: *const std.mem.Allocator) void
    {
        self.supported_formats.deinit(allocator.*);
        self.supported_presentation_modes.deinit(allocator.*);
    }
};

pub const SwapchainSupportError = error
{
    NoSupportedFormats,
    NoSupportedPresentationModes
};

/// Gets the swapchain capabilities for a physical device.
pub fn query_device_swapchain_support(instance: *vk.InstanceProxy, allocator: *const std.mem.Allocator, physical_device: vk.PhysicalDevice, surface: vk.SurfaceKHR) !DeviceSwapchainSupport
{
    var sc_support: DeviceSwapchainSupport = .{};

    sc_support.capabilities = try instance.getPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface);

    var format_count: u32 = undefined;
    _ = try instance.getPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, null);

    if(format_count == 0) return SwapchainSupportError.NoSupportedFormats;
    
    sc_support.supported_formats = try std.ArrayList(vk.SurfaceFormatKHR).initCapacity(allocator.*, format_count);
    try sc_support.supported_formats.resize(allocator.*, format_count);
    
    _ = try instance.getPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count,
                                                        @ptrCast(sc_support.supported_formats.items));

    var presentation_mode_count: u32 = undefined;
    _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &presentation_mode_count, null);

    if(presentation_mode_count == 0) return SwapchainSupportError.NoSupportedPresentationModes;

    sc_support.supported_presentation_modes = try std.ArrayList(vk.PresentModeKHR).initCapacity(allocator.*, format_count);
    try sc_support.supported_presentation_modes.resize(allocator.*, presentation_mode_count);

    _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &presentation_mode_count,
                                                             @ptrCast(sc_support.supported_presentation_modes.items));

    return sc_support;
}

/// VkContext handles initialization of Vulkan, selecting a physical device, and creating the logical Vulkan device handle.
/// It also serves as the container for the Vulkan instance and device.
pub const VkContext = struct
{
    const VulkanContextInitError = error
    {
        ExtensionNotSupported,
        LayerNotSupported,
        NoPhysicalDeviceSupportsVulkan,
        NoSuitableGPUs,
        FailedToCreateWindowSurface
    };

    allocator: *const std.mem.Allocator,

    vkb: *vk.BaseWrapper = undefined,
    vki: *vk.InstanceWrapper = undefined,
    vkd: *vk.DeviceWrapper = undefined,

    instance: *vk.InstanceProxy = undefined,
    device: *vk.DeviceProxy = undefined,

    debug_messenger: vk.DebugUtilsMessengerEXT = undefined,

    physical_device: vk.PhysicalDevice = undefined,
    physical_device_queue_families: PhysicalDeviceQueueFamilies = undefined,

    window_surface: vk.SurfaceKHR = undefined,

    /// Contains the indices of each queue family for a physical device. Created via get_physical_device_queue_families.
    const PhysicalDeviceQueueFamilies = struct
    {
        graphics_family_index: ?usize = null,
        present_family_index: ?usize = null
    };

    pub const InitOptions = struct {
        /// List of extensions to add to the Vulkan instance. GLFW extensions are already added when VkContext.init() is called.
        instance_extensions: [][*:0]const u8,
        /// List of layers to add to the Vulkan instance.
        instance_layers: [][*:0]const u8,

        /// List of required extensions to add to the Vulkan device interface.
        required_device_extensions: [][*:0]const u8,
        /// List of required device features to enable.
        required_device_features: vk.PhysicalDeviceFeatures
    };

    /// Checks if the required Vulkan extensions for the build are supported, and initializes and populates required_extensions_list if they are supported.
    fn check_required_extensions_support(self: VkContext, additional_extensions: [][*:0]const u8, required_extensions_list: *std.ArrayList([*:0]const u8)) !bool
    {
        // Get all available Vulkan extensions that this device can support.
        // We won't use all of them, but a few are required for GLFW, and we want to make sure those are available.

        var available_extension_count: u32 = undefined;
        _ = try self.vkb.enumerateInstanceExtensionProperties(null, &available_extension_count, null);

        var available_extensions = try std.ArrayList(vk.ExtensionProperties).initCapacity(self.allocator.*, available_extension_count);
        try available_extensions.resize(self.allocator.*, available_extension_count);
        defer available_extensions.deinit(self.allocator.*);

        _ = try self.vkb.enumerateInstanceExtensionProperties(null, &available_extension_count, @ptrCast(available_extensions.items));

        // The reason this function builds a list of extensions and returns it rather than simply relying on the existing required extension list
        // is that GLFW has its own extensions that it requires, which is polled here.

        var glfw_extension_count: u32 = undefined;
        const glfw_extensions = glfw.getRequiredInstanceExtensions(&glfw_extension_count);

        const required_extensions_count = glfw_extension_count + additional_extensions.len;
        required_extensions_list.* = try std.ArrayList([*:0]const u8).initCapacity(self.allocator.*, required_extensions_count);

        // We can now check if said GLFW extensions are supported.

        if(glfw_extension_count > 0)
        {
            if(glfw_extensions == null) unreachable; // Not sure if this can ever be true...
            for(0..glfw_extension_count) |i|
            {
                var supported: bool = false;
                for(0..available_extension_count) |j|
                {
                    if(c_strequal(@ptrCast(&available_extensions.items[j].extension_name), glfw_extensions.?[i]))
                    {
                        supported = true;
                        break;
                    }
                }
                if(!supported) return false;
                try required_extensions_list.*.append(self.allocator.*, glfw_extensions.?[i]);
            }
        }

        // And now the additional instance extensions, if applicable.

        for(0..additional_extensions.len) |i|
        {
            var supported: bool = false;
            for(0..available_extension_count) |j|
            {
                if(c_strequal(@ptrCast(&available_extensions.items[j].extension_name), additional_extensions[i]))
                {
                    supported = true;
                    break;
                }
            }
            if(!supported) return false;
            try required_extensions_list.*.append(self.allocator.*, additional_extensions[i]);
        }

        return true;
    }

    fn check_validation_layer_support(self: VkContext, layers: [][*:0]const u8) !bool
    {
        // Much like getting the available extensions, we also need to get all the available Vulkan layers in order to
        // make sure the ones we're using are supported.

        var available_layer_count: u32 = undefined;
        _ = try self.vkb.enumerateInstanceLayerProperties(&available_layer_count, null);

        if(available_layer_count == 0) return false;

        var available_layers = try std.ArrayList(vk.LayerProperties).initCapacity(self.allocator.*, available_layer_count);
        try available_layers.resize(self.allocator.*, available_layer_count);
        defer available_layers.deinit(self.allocator.*);

        _ = try self.vkb.enumerateInstanceLayerProperties(&available_layer_count, @ptrCast(available_layers.items));

        for(0..layers.len) |i|
        {
            var supported: bool = false;
            for(available_layers.items) |layer|
            {
                if(c_strequal(layers[i], @ptrCast(&layer.layer_name)))
                {
                    supported = true;
                    break;
                }
            }
            if(!supported) return false;
        }

        return true;
    }

    /// Check if the required physical device features are supported. TODO: Actually implement this.
    fn check_device_feature_support(self: VkContext, features: vk.PhysicalDeviceFeatures) !bool
    {
        const available_features = self.vki.getPhysicalDeviceFeatures(self.physical_device);
        return features == available_features;
    }

    /// Creates the vk.Instance handle, used for initializing Vulkan.
    fn create_instance_handle(self: VkContext, options: InitOptions) !vk.Instance
    {
        // Application info, not required but may be useful for GPU.
        // Most important thing here is to define the version of Vulkan we're using.

        const info_app: vk.ApplicationInfo = .{
            .p_application_name = "Zig Vulkan Test",
            .application_version = 1,
            .p_engine_name = "No Engine",
            .engine_version = 1,
            .api_version = @bitCast(vk.API_VERSION_1_0)
        };

        // We check to make sure all required instance extensions and layers are supported.

        var required_extensions: std.ArrayList([*:0]const u8) = undefined;
        if(!(try self.check_required_extensions_support(options.instance_extensions, &required_extensions)))
        {
            return VulkanContextInitError.ExtensionNotSupported;
        }
        defer required_extensions.deinit(self.allocator.*);

        debug_print_name_list(required_extensions, @ptrCast("Required extensions"));

        // We do the same for the layers.

        if(!(try self.check_validation_layer_support(options.instance_layers)))
        {
            return VulkanContextInitError.LayerNotSupported;
        }

        // Now we can get the information together for the creation of the Vulkan instance.

        const validate_instance = get_debug_messenger_create_info();

        const info_instance: vk.InstanceCreateInfo = .{
            .p_application_info = &info_app,
            .enabled_extension_count = @truncate(required_extensions.capacity),
            .pp_enabled_extension_names = @ptrCast(required_extensions.items),
            .enabled_layer_count = @truncate(options.instance_layers.len),
            .pp_enabled_layer_names = @ptrCast(options.instance_layers),
            .p_next = &validate_instance
        };

        return try self.vkb.createInstance(&info_instance, null);
    }

    /// For debug builds, sets up the callback for the validation layer.
    fn debug_setup_vulkan_messenger(self: VkContext) !vk.DebugUtilsMessengerEXT
    {
        const info_msg: vk.DebugUtilsMessengerCreateInfoEXT = get_debug_messenger_create_info();

        // Normally, in C/++, we'd have to create a proxy function for this, since it's an extension function.
        // Fortunately, vulkan-zig already creates proxy functions for everything.
        return try self.instance.createDebugUtilsMessengerEXT(&info_msg, null);
    }

    /// Prints the name (identifier) for a physical device.
    fn debug_print_physical_device_name(self: VkContext, physical_device: vk.PhysicalDevice) void
    {
        const device_properties = self.instance.getPhysicalDeviceProperties(physical_device);
        print("{s}\n", .{device_properties.device_name});
    }

    /// Gets a PhysicalDeviceQueueFamilies struct containing the indices of all queue families housed with the physical_device.
    /// Prefers queue families that support graphics and presentation commands at the same time.
    pub fn get_physical_device_queue_families(self: VkContext, physical_device: vk.PhysicalDevice) !PhysicalDeviceQueueFamilies
    {
        var queue_family_count: u32 = undefined;
        self.instance.getPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, null);

        if(queue_family_count == 0) return .{};

        var qf: PhysicalDeviceQueueFamilies = .{};

        var queue_families = try std.ArrayList(vk.QueueFamilyProperties).initCapacity(self.allocator.*, queue_family_count);
        try queue_families.resize(self.allocator.*, queue_family_count);
        defer queue_families.deinit(self.allocator.*);

        self.instance.getPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, @ptrCast(queue_families.items));

        for(queue_families.items, 0..) |family, i|
        {
            if(family.queue_flags.graphics_bit) qf.graphics_family_index = i;

            if(try self.vki.getPhysicalDeviceSurfaceSupportKHR(physical_device, @truncate(i), self.window_surface) == .true)
            {
                qf.present_family_index = i;
                if(family.queue_flags.graphics_bit) qf.graphics_family_index = i;
            }
        }

        return qf;
    }

    /// Checking if a physical device can support the provided list of extensions.
    fn check_device_extension_support(self: VkContext, physical_device: vk.PhysicalDevice, extensions: [][*:0]const u8) !bool
    {
        var available_extension_count: u32 = undefined;
        _ = try self.vki.enumerateDeviceExtensionProperties(physical_device, null, &available_extension_count, null);

        var available_extensions = try std.ArrayList(vk.ExtensionProperties).initCapacity(self.allocator.*, available_extension_count);
        try available_extensions.resize(self.allocator.*, available_extension_count);
        defer available_extensions.deinit(self.allocator.*);

        _ = try self.vki.enumerateDeviceExtensionProperties(physical_device, null, &available_extension_count,
        @ptrCast(available_extensions.items));

        for(extensions) |ext|
        {
            var supported: bool = false;
            for(available_extensions.items) |a_ext|
            {
                if(c_strequal(ext, @ptrCast(&a_ext.extension_name)))
                {
                    supported = true;
                    break;
                }
            }
            if(!supported) return false;
        }

        return true;
    }

    fn check_device_swapchain_support(self: VkContext, physical_device: vk.PhysicalDevice) !bool
    {
        var sc_support = try query_device_swapchain_support(self.instance, self.allocator, physical_device, self.window_surface);
        sc_support.deinit(self.allocator);
        return true;
    }

    /// Gives a vk.PhysicalDevice a score depending on how usable it is for the current program. Used by select_physical_device.
    /// A score of -1 indicates that the device isn't usable.
    fn rate_physical_device(self: VkContext, physical_device: vk.PhysicalDevice, required_extensions: [][*:0]const u8) !i32
    {
        var score: i32 = -1;

        const device_properties = self.instance.getPhysicalDeviceProperties(physical_device);

        // Should prefer discrete GPUs to integrated ones.

        if(device_properties.device_type == .integrated_gpu) score = 1;
        if(device_properties.device_type == .discrete_gpu) score = 10;

        const queue_families = try self.get_physical_device_queue_families(physical_device);

        // If the GPU doesn't have a valid graphics queue family, it's unusable in this case.
        if(queue_families.graphics_family_index == null) score = -1;

        // Checking if the GPU supports the required extensions.
        if(!(try self.check_device_extension_support(physical_device, required_extensions))) score = -1;
        if(!(try self.check_device_swapchain_support(physical_device))) score = -1;

        return score;
    }

    /// Selects a physical device for Vulkan to send commands to.
    fn select_physical_device(self: VkContext, options: InitOptions) !vk.PhysicalDevice
    {
        // Much like getting the available extensions and layers, we need to poll the available physical devices (GPUs and other hardware that Vulkan can run on)
        // and find the best fit for our program.

        var physical_device_count: u32 = undefined;
        _ = try self.instance.enumeratePhysicalDevices(&physical_device_count, null);

        if(physical_device_count == 0) return VulkanContextInitError.NoPhysicalDeviceSupportsVulkan;

        var available_physical_devices = try std.ArrayList(vk.PhysicalDevice).initCapacity(self.allocator.*, physical_device_count);
        try available_physical_devices.resize(self.allocator.*, physical_device_count);
        defer available_physical_devices.deinit(self.allocator.*);

        _ = try self.instance.enumeratePhysicalDevices(&physical_device_count, @ptrCast(available_physical_devices.items));

        // My preferred method of selecting a GPU is to give each device a score, and then pick the highest scoring one.

        var current_selected_index: usize = 0;
        var current_highest_score: i32 = -1;

        for(0..available_physical_devices.capacity) |i|
        {
            const score = try self.rate_physical_device(available_physical_devices.items[i], options.required_device_extensions);
            if(score > current_highest_score)
            {
                current_selected_index = i;
                current_highest_score = score;
            }
        }

        if(current_highest_score == -1) return VulkanContextInitError.NoSuitableGPUs;

        const selected_device = available_physical_devices.items[current_selected_index];
        self.debug_print_physical_device_name(selected_device);
        return selected_device;
    }

    /// Creates a Vulkan logical device handle, used for creating Vulkan objects such as pipelines, swap chains (with an extension), buffers, etc.
    /// as well as sending Vulkan commands to the physical device. Also loads the Vulkan queues we'll need.
    fn create_vulkan_logical_device(self: VkContext, physical_device: vk.PhysicalDevice, options: InitOptions) !vk.Device
    {
        // We want to get queues for all queue types specified in the PhysicalDeviceQueueFamilies structure.
        const queue_families = self.physical_device_queue_families;
        const queue_priority: f32 = 1.0;

        var unique_families = try std.ArrayList(usize).initCapacity(self.allocator.*, 1);
        try unique_families.append(self.allocator.*, queue_families.graphics_family_index.?);
        try unique_families.append(self.allocator.*, queue_families.present_family_index.?);

        for(unique_families.items, 0..) |_, i|
        {
            const cur = unique_families.items[i];
            for(unique_families.items, (i+1)..) |_, j|
            {
                if(j >= unique_families.items.len) break;
                if(cur == unique_families.items[j])
                {
                    _ = unique_families.orderedRemove(j);
                }
            }
        }

        var info_queue_creates = try std.ArrayList(vk.DeviceQueueCreateInfo).initCapacity(self.allocator.*, unique_families.items.len);
        defer info_queue_creates.deinit(self.allocator.*);

        for(0..unique_families.items.len) |i|
        {
            const info_queue_create: vk.DeviceQueueCreateInfo = .{
                .queue_family_index = @truncate(unique_families.items[i]),
                .queue_count = 1,
                .p_queue_priorities = @ptrCast(&queue_priority)
            };

            try info_queue_creates.append(self.allocator.*, info_queue_create);
        }

        unique_families.deinit(self.allocator.*);

        const enabled_features: vk.PhysicalDeviceFeatures = options.required_device_features;

        const info_device_create: vk.DeviceCreateInfo = .{
            .p_queue_create_infos = @ptrCast(info_queue_creates.items),
            .queue_create_info_count = @truncate(info_queue_creates.items.len),
            .p_enabled_features = &enabled_features,
            .enabled_extension_count = @truncate(options.required_device_extensions.len),
            .pp_enabled_extension_names = @ptrCast(options.required_device_extensions),
            .enabled_layer_count = @truncate(options.instance_layers.len),
            .pp_enabled_layer_names = @ptrCast(options.instance_layers)
        };

        return try self.instance.createDevice(physical_device, &info_device_create, null);
    }

    /// Creates a SurfaceKHR object for the GLFW window. Required to display images onto the window.
    fn create_window_surface(self: *VkContext, window: *c_long) !void
    {
        var surface_id: u64 = undefined;
        const result = glfw.createWindowSurface(@intFromEnum(self.instance.handle), window, null, &surface_id);
        self.window_surface = @enumFromInt(surface_id);
        if(result != .success) return VulkanContextInitError.FailedToCreateWindowSurface;
    }

    /// Deinitializes the Vulkan context and frees all its associated resources.
    pub fn deinit(self: VkContext) void
    {
        self.device.destroyDevice(null);
        self.allocator.destroy(self.device);
        self.allocator.destroy(self.vkd);
        self.instance.destroySurfaceKHR(self.window_surface, null);
        self.instance.destroyDebugUtilsMessengerEXT(self.debug_messenger, null);
        self.instance.destroyInstance(null);
        self.allocator.destroy(self.instance);
        self.allocator.destroy(self.vki);
        self.allocator.destroy(self.vkb);
    }

    /// Creates a new Vulkan context.
    pub fn init(allocator: *const std.mem.Allocator, window: *c_long, options: InitOptions) !VkContext
    {
        print("{s}\n", .{"Loading Zig Vulkan wrappers and creating instance..."});
        var vk_context: VkContext = .{
            .allocator = allocator
        };

        // The base Vulkan wrapper handles all functions that don't require a Vulkan instance or logical device handle.

        vk_context.vkb = try allocator.create(vk.BaseWrapper);
        vk_context.vkb.* = vk.BaseWrapper.load(vk_get_instance_proc_address);

        const hndl_instance = try vk_context.create_instance_handle(options);
        
        // The instance wrapper handles all functions that require an instance handle only.

        vk_context.vki = try allocator.create(vk.InstanceWrapper);
        vk_context.vki.* = vk.InstanceWrapper.load(hndl_instance, vk_context.vkb.dispatch.vkGetInstanceProcAddr.?);

        // The instance proxy can be thought of as a wrapper around a wrapper.
        // Rather than calling vki.destroyInstance(hndl_instance, null), we can call it from the InstanceProxy directly.

        vk_context.instance = try allocator.create(vk.InstanceProxy);
        vk_context.instance.* = vk.InstanceProxy.init(hndl_instance, vk_context.vki);

        // Initializing the debug messenger for validation layers.

        vk_context.debug_messenger = try vk_context.debug_setup_vulkan_messenger();

        // Creating the window surface handle for GLFW.

        try vk_context.create_window_surface(window);

        // Selecting a GPU to use for the application, and then creating the Vulkan logical device handle.

        vk_context.physical_device = try vk_context.select_physical_device(options);
        vk_context.physical_device_queue_families = try vk_context.get_physical_device_queue_families(vk_context.physical_device);

        const hndl_device = try vk_context.create_vulkan_logical_device(vk_context.physical_device, options);

        // Seems like the best way to get the correct vkGetDeviceProcAddr function is to get it straight from the dispatch table.

        vk_context.vkd = try allocator.create(vk.DeviceWrapper);
        vk_context.vkd.* = vk.DeviceWrapper.load(hndl_device, vk_context.vki.dispatch.vkGetDeviceProcAddr.?);
        
        vk_context.device = try allocator.create(vk.DeviceProxy);
        vk_context.device.* = vk.DeviceProxy.init(hndl_device, vk_context.vkd);

        // Testing getting a queue.

        const queue_family = try vk_context.get_physical_device_queue_families(vk_context.physical_device);

        const graphics_queue = vk_context.device.getDeviceQueue(@truncate(queue_family.graphics_family_index.?), 0);
        _ = graphics_queue;

        print("{s}\n", .{"\tDone."});

        return vk_context;
    }

    /// Returns the queue at the queue index with the queue family.
    pub fn get_queue(self: *VkContext, queue_family_index: u32, queue_index: u32) vk.Queue
    {
        return self.device.getDeviceQueue(queue_family_index, queue_index);
    }
};

const testing = std.testing;

test "Equality of null-terminated strings."
{
    var str_a: [4]u8 = .{'a', 'b', 'c', 'd'};
    var str_b: [6]u8 = .{'a', 'b', 'c', 'd', 'e', 'f'};

    str_a[3] = 0;
    str_b[3] = 0;

    try testing.expect(!std.mem.eql(u8, &str_a, &str_b));
    try testing.expect(c_strequal(@ptrCast(&str_a), @ptrCast(&str_b)));
}