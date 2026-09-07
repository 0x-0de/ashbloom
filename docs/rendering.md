# Rendering (Vulkan bootstrapping)

Ashbloom began as a Vulkan bootstrapping library, before becoming a general framework for game and application development. I made sure not to obscure any Vulkan functionality from this library, and if you ever want to access the `vulkan-zig` binding this library uses to build your own Vulkan engine or utilities, you can via `root.vk`. Ashbloom simply provides some of its own utilities which may prove useful.

This document is not a Vulkan programming guide, and attempting to create one here would betray my own limited understanding of the API. If you're a newcomer to graphics programming, or to Vulkan, I would recommend starting with Khronos' [official Vulkan tutorial](https://docs.vulkan.org/tutorial/latest/00_Introduction.html), which takes you through the process of building a simple engine in Vulkan with C++, though the tutorial could still be followed for other systems languages, like Zig.

