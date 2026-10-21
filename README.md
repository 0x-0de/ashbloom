# Ashbloom

**Ashbloom** is my own Zig game and application development framework, which aims to provide some bootstrapping functionality for Vulkan rendering, tying together zig-vulkan, zGLFW, and freetype. Eventually, this framework should include audio interfacing functionality as well. Intends to support Windows and Linux devices.

This library is currently in an unstable (pre-release) state and may not fully support Linux devices yet. Any existing feature in the `main` branch which breaks on Linux devices should be considered a breaking bug. Updates to this library that aren't marked as a major release could still introduce breaking changes.

## Current features include:

- Window management (with GLFW), *some input functions currently only function with 1 window*.
- Vulkan context creation.
- Swapchain management.
- Render passes (legacy Vulkan feature).
- Vulkan graphics pipeline, descriptor set, and push constant handling.
    - Support for modern Vulkan dynamic rendering.

- Linear algebra library, with built-in projection and transformation matrices.
- Psuedo-random number and noise generation.
- Built-in polygonization algorithms
- Vulkan memory allocator.
- Vulkan texture loader (.bmps only).
- Audio I/O support (w/ miniaudio as a backend).
- UI library and immediate-mode theme support, along with an XML parser for immediate-mode theme elements.
- Preliminary support for Linux devices (this library is "native" to Windows).
- Prepackaged documentation and programming references.

## Upcoming:

- .jpeg and .png image decoder (will probably rely on third-party libraries for this).
- More example programs, and other minor features.

## Example demos:

### Todo application:

The todo application uses the provided UI tools and the immediate-mode theme to provide a basic program where you can add, check, and remove tasks to an indefinitely-sizable list. Meant to mimic simple front-end web dev projects.

### Voxel demo:

Provides a 3D demo in which you can edit and mess with a 64x64x64 grid of voxels. Essentially written as an example Vulkan renderer, provides a complete example on how to use the swapchain, render pass, and graphics pipeline bootstrapping tools.

Other small tests are included in the `tests` folder.

## Attributions:

This library extends and is made possible by the following libraries and packages:

- [zGLFW](https://github.com/IridescenceTech/zglfw) | GLFW bindings for Zig. Bindings are MIT-licensed, while GLFW itself uses the zlib license.
- [vulkan-zig](https://github.com/Snektron/vulkan-zig) | Vulkan binding generator for Zig. MIT-licened.
- [miniaudio](https://miniaud.io/) | Single-file audio library, implements multiple OS-specific backends for Ashbloom's audio system. MIT-0 licensed.
- [zig-xml](https://github.com/ianprime0509/zig-xml) | ianprime0509's XML parser for Zig. 0BSD-licensed.
- [freetype](https://freetype.org/) | Font file parser and font glyph rasterizer library. This library chooses to use this software under the FreeType license. All files in the `include/freetype` directory are copyright (C) 2026 The FreeType project. All rights reserved.
- [minimp3](https://github.com/lieff/minimp3) | MP3 decoder. Licensed under CC0.
- [stb_vorbis](https://github.com/nothings/stb/blob/master/stb_vorbis.c) | Sean Barrett's vorbis decoder. This library chooses to use this software under the MIT license.
- [audiophile-flac](https://codeberg.org/audiophile/flac) | Zig-native FLAC decoder by `audiophile`.
