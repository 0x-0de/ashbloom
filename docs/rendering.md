# Rendering (Vulkan bootstrapping)

Ashbloom began as a Vulkan bootstrapping library, before becoming a general framework for game and application development. I made sure not to obscure any Vulkan functionality from this library, and if you ever want to access the `vulkan-zig` binding this library uses to build your own Vulkan engine or utilities, you can via `root.vk`. Ashbloom simply provides some of its own utilities which may prove useful.

This document is not a Vulkan programming guide, and attempting to create one here would betray my own limited understanding of the API. If you're a newcomer to graphics programming, or to Vulkan, I would recommend starting with Khronos' [official Vulkan tutorial](https://docs.vulkan.org/tutorial/latest/00_Introduction.html), which takes you through the process of building a simple engine in Vulkan with C++, though the tutorial could still be followed for other systems languages, like Zig.

If you're familiar with Vulkan, you should be able to proceed with little issue. Here's a diagram showing how the common Vulkan structures are organized in Ashbloom's rendering modules:

![Dependency graph showing Vulkan objects contained within Ashbloom structures](./resources/rendering/dependency_chart.png)

This dependency graph shows how Vulkan objects are contained within the structs found in this namespace. Connections indicate dependencies, and it can be largely assumed that if a structure contains something which depends on an object a different structure contains, then the structure overall depends on that other structure. The arrow points towards the object which depends on the structure the arrow is pointing from.

Blue objects are Vulkan objects, with gray ones being optional. Dependencies within structures are not graphed here but do exist (such as `VkDevice` depending on a chosen  `VkPhysicalDevice`). Purple objects are Ashbloom structures, and pink objects are structures found within other libraries/dependencies. Since `VulkanAllocator` is considered a utility (found within `utils`), it's not elaborated on much here. 

This diagram is simplified, and lacks a lot of details within each module, such as all of the shader modules and info structures in the `Pipeline` structure (like `VkPipelineRasterizationStateCreateInfo` for example), or the `CommandBuffer` list and synchronization objects contained in the `Swapchain` structure, or the various info structures needed for a `PipelineDescriptorSet`, etc.

Hopefully, this gives you a good idea on how this namespace is structured overall.

# `vk_core`

## VkContext

The `VkContext` structure holds the VkInstance object, as well as the VkDebugUtilsMessengerEXT object used for printing messages relating to any active validation layers. This structure has a number of functions made for checking what capabilities a physical device has. In 99.9% of all cases, you should only need one of these, since you should only need one VkInstance.

### Fields

`allocator: *const std.mem.Allocator` - CPU allocator.

`vkb: *vk.BaseWrapper` - This structure is for the `vulkan-zig` bindings specifically, used to initialize other wrappers.

`vki: *vk.InstanceWrapper` - `vulkan-zig` wrapper for Vulkan functions that require instances. Required to initialize a `vk.InstanceProxy`.

`instance: *vk.InstanceProxy` - This instance proxy functions both as a `vk.Instance` (`VkInstance`) and as a wrapper for any Vulkan function that requires a `VkInstance` as a first argument.

`debug_messenger: ?vk.DebugUtilsMessengerEXT = null` - Optional messenger utility which prints information that trips the instance and device validation layers, if any are provided.

### Structures

`InitOptions` - Initialization options, required to initialize a `VkContext`.

#### Fields

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