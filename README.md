# Ashbloom
**Ashbloom** is my own Zig game and application development framework, which aims to provide some bootstrapping functionality for Vulkan rendering, tying together zig-vulkan, zGLFW, and freetype. Eventually, this framework should include audio interfacing functionality as well. Intends to support Windows and Linux devices.

This library is currently in an unstable (pre-release) state and may not fully support Linux devices yet. Any existing feature in the `main` branch which breaks on Linux devices should be considered a breaking bug. Updates to this library that aren't marked as a major release could still introduce breaking changes.

## Current features include:

- Window management (with GLFW), *single window only for now*.
- Vulkan context creation.
- Swapchain management.
- Render passes (legacy Vulkan feature).
- Vulkan graphics pipeline, descriptor set, and push constant handling.
- Linear algebra library, with built-in projection and transformation matrices.
- Psuedo-random number and noise generation.
- Vulkan memory allocator.
- Vulkan texture loader (.bmps only).
- UI library and immediate-mode theme support.
- Preliminary support for Linux devices (this library is "native" to Windows).

## Upcoming:

- Support for dynamic rendering (no more render passes!).
- UI-mode rendering (as opposed to rumtime rendering).
- .jpeg and .png image decoder (will probably rely on third-party libraries for this).
- Multi-platform audio library (similar to Crest but for Linux too, at least).
- More example programs, and other minor features.

## Example demos:

### Todo application:

The todo application uses the provided UI tools and the immediate-mode theme to provide a basic program where you can add, check, and remove tasks to an indefinitely-sizable list. Meant to mimic simple front-end web dev projects.

### Voxel demo:

Provides a 3D demo in which you can edit and mess with a 64x64x64 grid of voxels. Essentially written as an example Vulkan renderer, provides a complete example on how to use the swapchain, render pass, and graphics pipeline bootstrapping tools.
