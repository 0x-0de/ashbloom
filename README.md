# v0lcano

**v0lcano** is my own Vulkan framework, which aims to provide some bootstrapping functionality, tying together zig-vulkan, zGLFW, and freetype.

## Current features include:

- Window management (GLFW) **[needs testing]**
- Vulkan context creation **[needs testing]**
- Swapchain management **[needs testing]**
- Render passes (legacy Vulkan feature) **[needs testing]**
- Vulkan graphics pipeline, descriptor set, and push constant handling **[needs testing]**
- Linear algebra library **[done]**
- Vulkan memory allocator **[done]**
- Vulkan texture loader (.bmps only) **[done]**

## Upcoming before the next release:

- UI context & immediate-mode theme **[wip]**
- Support for building on Linux devices **[wip]**
- Example UI applications **[pending]**

## Further things that need to be added or addressed:

- Support for dynamic rendering (no more render passes!)
- .jpeg and .png image decoder (will probably rely on third-party libraries for this).
- Multi-platform audio library (similar to Crest but for Linux too, at least).
- More example programs.