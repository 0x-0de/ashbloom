# Ashbloom Documentation

Ashbloom is a suite of tools I've developed for GUI and game development. View the [README.md](../README.md) in the root directory for a more detailed synopsis of what this library is trying to do.

This folder, for the time being, houses the main documentation for Ashbloom. Ashbloom supports Zig documentation generation, and you are encouraged to run `zig build docs` to emit a quick programming reference to `zig-out/docs`. Run a web-server in that directory (I use `python -m http.server`) to access it.

This library's documentation is split along the namespaces provided in Ashbloom's `root.zig` file. These namespaces are as follows:

- [gen](./gen.md): Utilities related to procedural generation, such as noise and polygonization algorithms.
- [math](./math.md): Utilities related to advanced math, like linear algebra (vector and matrix math), as well as different methods of interpolation.
- [rendering](./rendering.md): Houses the various Vulkan bootstrapping utilities developed for this library.
- [utils](./utils.md): General utilities that don't belong to a specific category.
- [ui](./ui.md): Houses Ashbloom's UI system.

