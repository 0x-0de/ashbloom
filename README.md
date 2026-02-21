# This repo is a work in progress!

I'm still working on the initial release for v0lcano! Check out the ```dev``` branch for the latest version!

# What is this?

v0lcano is my own little framework which provides some bootstrapping for Vulkan in Zig. It will eventually grow to encompass several aspects of game and graphical application development, but for now here's the checklist for the initial release:

- Window management (GLFW) **[done, needs testing]**
- Vulkan context creation **[done, needs testing]**
- Swapchain management **[done, needs testing]**
- Render passes (legacy Vulkan feature) **[done, needs testing]**
- Vulkan graphics pipeline, descriptor set, and push constant handling **[done, needs testing]**
- Linear algebra library **[done]**
- Vulkan memory allocator **[done]**
- Vulkan texture loader (.bmps only) **[done]**
- UI context & immediate-mode theme **[wip]**
- Example UI applications **[pending]**

Here are some further things that need to be added:

- Support for dynamic rendering (no more render passes!)
- .jpeg and .png image decoder (will probably rely on third-party libraries for this).
- Multi-platform audio library (similar to Crest but for Linux too, at least).
- More example programs.