# `vk_core`

The `vk_core` namespace/module contains the "core" Vulkan functions, related to initializing Vulkan, choosing a physical device (GPU) to run it on, and creating the logical device handle required for most Vulkan operations.

## VkContext (`struct`)

The `VkContext` structure holds the VkInstance object, as well as the VkDebugUtilsMessengerEXT object used for printing messages relating to any active validation layers. This structure has a number of functions made for checking what capabilities a physical device has. In 99.9% of all cases, you should only need one of these, since you should only need one VkInstance.

### Fields

`allocator: *const std.mem.Allocator` - CPU allocator.

`vkb: *vk.BaseWrapper` - This structure is for the `vulkan-zig` bindings specifically, used to initialize other wrappers.

`vki: *vk.InstanceWrapper` - `vulkan-zig` wrapper for Vulkan functions that require instances. Required to initialize a `vk.InstanceProxy`.

`instance: *vk.InstanceProxy` - This instance proxy functions both as a `vk.Instance` (`VkInstance`) and as a wrapper for any Vulkan function that requires a `VkInstance` as a first argument.

`debug_messenger: ?vk.DebugUtilsMessengerEXT = null` - Optional messenger utility which prints information that trips the instance and device validation layers, if any are provided.

### Structures

#### `InitOptions`

Initialization options, required to initialize a `VkContext`.

##### Fields

`instance_extensions: [][*:0]const u8 = &.{}` - List of extensions to add to the Vulkan instance. GLFW extensions are already added when VkContext.init() is called.

`instance_layers: [][*:0]const u8 = &.{}` - List of layers to add to the Vulkan instance.

### Public Functions

**`check_device_extension_support(self: VkContext, physical_device: vk.PhysicalDevice, required_extensions: [][*:0]const u8, preferred_extensions: [][*:0]const u8, num_preferred_extensions_supported: *usize) !bool`**

Checks if the `physical_device` can support the provided lists of extensions. Sets `num_preferred_extensions_supported.*` to the number of `preferred_extensions` supported. Returns false if any of the `required_extensions` are unsupported.

**`check_device_feature_support(self: VkContext, physical_device: vk.PhysicalDevice, required_features: vk.PhysicalDeviceFeatures, preferred_features: vk.PhysicalDeviceFeatures, num_preferred_features_supported: *usize, preferred_features_supported: ?*vk.PhysicalDeviceFeatures) !bool`**

Checks if the `physical_device` can support the provided lists of device features. Sets the fields of `preferred_features_supported.?.*` to true if they are set in `preferred_features`, are supported by the physical device, and if `preferred_features_supported` is not `null`. In the last case, the field is ignored entirely. Returns false if any of the `required_features` are unsupported.

**`check_device_swapchain_support(self: VkContext, physical_device: vk.PhysicalDevice, surface: vk.SurfaceKHR) !bool`**

Calls `vk_core.query_device_swapchain_support` using `self.instance` and `self.allocator`, returns true if no errors were produced by that call. The returned `DeviceSwapchainSupport` is deinitialized automatically.

**`create_glfw_window_surface(self: VkContext, window: *c_long) !vk.SurfaceKHR`**

Creates a SurfaceKHR object for the `window` (which must be a handle for the GLFW window, available through `Window.glfw_handle`). The SurfaceKHR is required to create a `Swapchain`.

**`deinit(self: VkContext) void`**

Deinitializes the `VkContext`. This should be the last Vulkan deinitialization call.

**`init(allocator: *const std.mem.Allocator, options: InitOptions) !VkContext`**

Initializes a `VkContext`. Creates the Vulkan instance, sets up any validation layers if necessary.

### Private Functions

**`check_required_extensions_support(self: VkContext, additional_extensions: [][*:0]const u8, required_extensions_list: *std.ArrayList([*:0]const u8)) !bool`**

Checks if the required Vulkan instance extensions are supported, and initializes and populates `required_extensions_list` if they are, otherwise returns false. This function adds the required GLFW extensions to the passed `additional_extensions` in order to get the final list of required extensions.

**`check_validation_layer_support(self: VkContext, layers: [][*:0]const u8) !bool`**

Checks if the required Vulkan layers are supported, and returns true if they are.

**`create_instance_handle(self: VkContext, options: InitOptions) !vk.Instance`**

Creates the Vulkan instance, effectively initializing Vulkan. Returns its handle. Currently, the Vulkan application info is uneditable. This will be fixed soon.

**`debug_setup_vulkan_messenger(self: VkContext) !vk.DebugUtilsMessengerEXT`**

Creates the Vulkan debug messenger utility used to print messages relating to any passed validation layers. The behavior of the messenger is managed by Ashbloom.

**`debug_print_physical_device_name(self: VkContext, physical_device: vk.PhysicalDevice) !void`**

Debug function that prints the name of the `physical_device`.

## VulkanInitError (`error`)

**ExtensionNotSupported** - One or more required extensions for an instance isn't supported.
**LayerNotSupported** - One or more required layers for an instance isn't supported.
**NoPhysicalDeviceSupportsVulkan** - No physical devices which support Vulkan were able to be found.
**NoSuitableGPUs** - No physical device was able to meet the requirements set in `VkInterface.InitOptions`.
**FailedToCreateWindowSurface** - Failed to create a valid VkSurfaceKHR.
**IncompatiableWindow** - Returned if the VkSurfaceKHR object created by adding a secondary window to the `VkInterface` is incompatiable with the logical device that's already been created.

## VkInterface (`struct`)

Represents an output point for the Vulkan context. This structure contains a Vulkan logical device, handle for a selected physical device, and list of surfaces.

### Fields

`allocator: *const std.mem.Allocator` - CPU allocator.

`context: *const VkContext` - Pointer to the `VkContext` used to create this `VkInterface`.

`surfaces: std.ArrayList(vk.SurfaceKHR)` - List of `vk.SurfaceKHR` objects currently in use.

`vkd: *vk.DeviceWrapper = undefined` - `vulkan-zig` wrapper for Vulkan functions that require a device handle. Required to initialize a `vk.DeviceProxy`.

`device: *vk.DeviceProxy = undefined` - This device proxy functions both as a `vk.Device` (`VkDevice`) and as a wrapper for any Vulkan function that requires a `VkDevice` as a first argument.

`physical_device: ?vk.PhysicalDevice = null` - The selected physical device, if initialized.

`physical_device_features: ?vk.PhysicalDeviceFeatures = null` - Available device features, if initialized.

`physical_device_queue_families: ?PhysicalDeviceQueueFamilies = null` - Available device queue families, if initialized.

### Structures

#### `InitOptions`

Initialization options, required to initialize a `VkInterface`.

##### Fields

`device_layers: [][*:0]const u8 = &.{}` - List of layers to add to the Vulkan logical device.

`required_device_extensions: [][*:0]const u8 = &default_device_extensions` - List of required extensions to add to the Vulkan device interface. Includes VkSwapchainKHR by default (required by Ashbloom's swapchain).

`required_device_features: vk.PhysicalDeviceFeatures = .{}` - List of required device features to enable.

`preferred_device_extensions: [][*:0]const u8 = &.{}` - List of non-required extensions to attempt to add to the Vulkan device interface.

`preferred_device_features: vk.PhysicalDeviceFeatures = .{}` - List of non-required device features to attempt to enable on the Vulkan device.

#### `PhysicalDeviceQueueFamilies`

Contains the indices of each queue family for a physical device. Created via `get_physical_device_queue_families`.

##### Fields

`graphics_family_index: ?usize = null` - Index of an available queue family for graphics operations in the physical device.

`present_family_index: ?usize = null` - Index of an available queue family for presentation operations in the physical device.

##### Public Functions

**`equals(self: PhysicalDeviceQueueFamilies, queue_family: PhysicalDeviceQueueFamilies) bool`**

Checks if the fields in `self` are equal to the fields in `queue_family`.

### Public Functions

**`add_window(self: *VkInterface, window: *Window) !void`**

Adds a new window surface object to the VkInterface, which is created using `window`.

**`deinit(self: *VkInterface) void`**

Deinitializes the VkInterface.

**`init(context: *VkContext, window: *Window, options: InitOptions) !VkInterface`**

Initializes a VkInterface using a provided window object (required for creating the vk.SurfaceKHR), selecting a physical device and creating a logical device handle. Any window surface added later will need to either match or exceed the capabilities of the current window surface.

**`get_queue(self: *VkInterface, queue_family_index: usize, queue_index: usize) vk.Queue`**

Returns the queue at the `queue_index` from the queue family at `queue_family_index`.

**`remove_window(self: *VkInterface, index: usize) void`**

Destroys and removes the window surface from the instance.

### Private Functions

**`check_surface_physical_device_compatibility(self: VkInterface, surface: vk.SurfaceKHR) bool`**

Checks if the provided surface meets the capabilities of the physical device. Used when adding a new window (surface) to this `VkInterface`.

**`create_vulkan_logical_device(self: VkInterface, options: InitOptions) !vk.Device`**

Creates the logical device handle. Used during initialization.

**`get_physical_device_queue_families(self: VkInterface, physical_device: vk.PhysicalDevice, surface: vk.SurfaceKHR) !PhysicalDeviceQueueFamilies`**

Gets a `PhysicalDeviceQueueFamilies` struct containing the indices of relevant queue families housed with the physical_device. Prefers queue families that support graphics and presentation commands at the same time.

**`rate_physical_device(self: VkInterface, physical_device: vk.PhysicalDevice, required_extensions: [][*:0]const u8, preferred_extensions: [][*:0]const u8, required_features: vk.PhysicalDeviceFeatures, preferred_features: vk.PhysicalDeviceFeatures, preferred_features_supported: *vk.PhysicalDeviceFeatures, surface: vk.SurfaceKHR) !i32`**

Gives the `physical_device` a score depending on how usable it is for the current program. Used by `select_physical_device`. A score of -1 indicates that the device isn't usable.

**`select_physical_device(self: *VkInterface, options: InitOptions, surface: vk.SurfaceKHR) !vk.PhysicalDevice`**

Selects a physical device for Vulkan to send commands to. Used during initialization.

## DeviceSwapchainSupport (`struct`)

This struct exists to be returned by `query_device_swapchain_support`. It contains the swapchain capabilities, as well as a list of supported image formats and presentation modes.

### Fields

`capabilities: vk.SurfaceCapabilitiesKHR = undefined` - Swapchain capabilities.

`supported_formats: std.ArrayList(vk.SurfaceFormatKHR) = undefined` - List of swapchain formats.

`supported_presentation_modes: std.ArrayList(vk.PresentModeKHR) = undefined` - List of swapchain presentation modes.

### Public Functions

**`deinit(self: *DeviceSwapchainSupport, allocator: *const std.mem.Allocator) void`**

Frees all allocated resources used by this object.

## SwapchainSupportError (`error`)

**NoSupportedFormats** - The physical device and/or surface does not support any available swapchain formats.
**NoSupportedPresentationModes** - The physical device and/or surface does not support any available swapchain presentation modes.

## Private Fields

```
var default_device_extensions: [1][*:0]const u8 = .{
    vk.extensions.khr_swapchain.name
};
```

Default device extensions. Ashbloom's Swapchain structure uses a `VkSwapchainKHR`, so it's assumed that the relevant device extension will be required for this application.

## Public Functions

**`query_device_swapchain_support(instance: *vk.InstanceProxy, allocator: *const std.mem.Allocator, physical_device: vk.PhysicalDevice, surface: vk.SurfaceKHR) !DeviceSwapchainSupport`**

Using the `physical_device` and `surface`, queries the various swapchain capabilities, image formats, and presentation modes, and returns them as a `DeviceSwapchainSupport`.

## Private Functions

**`vk_get_instance_proc_address(instance: vk.Instance, proc_name: [*:0]const u8) vk.PfnVoidFunction`**

Wrapper function. The `vulkan-zig` wrapper gets all function pointers dynamically, so there needs to be some user-defined function which wraps `vkGetInstanceProcAddr` that `vulkan-zig` can use.

**`vk_debug_validation_layer_message_callback(message_severity: vk.DebugUtilsMessageSeverityFlagsEXT, message_types: vk.DebugUtilsMessageTypeFlagsEXT, p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, p_user_data: ?*anyopaque) callconv(.c) vk.Bool32`**

Message callback for Vulkan's validation layers.

**`get_debug_messenger_create_info() vk.DebugUtilsMessengerCreateInfoEXT`**

Returns the current built-in `vk.DebugUtilsMessengerCreateInfoEXT` used for any passed in validation layers.

**`debug_print_extension_list(extensions: std.ArrayList(vk.ExtensionProperties), label: []const u8) !void`**

Debug helper function to print all of the names of the vulkan extensions provided in `extensions`.

**`debug_print_layer_list(extensions: std.ArrayList(vk.ExtensionProperties), label: []const u8) !void`**

Debug helper function to print all of the names of the vulkan layers provided in `layers`.

**`debug_print_physical_device_properties(properties: vk.PhysicalDeviceProperties) void`**

Prints the various fields of `properties`.

**`compare_device_features_lists(allocator: *const std.mem.Allocator, desired_features: vk.PhysicalDeviceFeatures, available_features: vk.PhysicalDeviceFeatures, total_features: *usize, features_supported: ?*vk.PhysicalDeviceFeatures) !usize`**

Compares desired device features (`desired_features`) with all available device features (`available_features`). Returns a "score" value indicating how many desired features are available, and sets `total_features.*` to the total number of desired features. If `features_supported` is not null, it will be populated with the desired features that are available.
