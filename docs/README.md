# Ashbloom Documentation

Ashbloom is a suite of tools I've developed for GUI and game development. View the [README.md](../README.md) in the root directory for a more detailed synopsis of what this library is trying to do.

This folder, for the time being, houses the main documentation for Ashbloom. Ashbloom supports Zig documentation generation, and you are encouraged to run `zig build docs` to emit a quick programming reference to `zig-out/docs`. Run a web-server in that directory (I use `python -m http.server`) to access it.

This library's documentation is split along the namespaces provided in Ashbloom's `root.zig` file. These namespaces are as follows:

- [gen](./gen.md): Utilities related to procedural generation, such as noise and polygonization algorithms.
- [math](./math.md): Utilities related to advanced math, like linear algebra (vector and matrix math), as well as different methods of interpolation.
- [rendering](./rendering.md): Houses the various Vulkan bootstrapping utilities developed for this library.
- [utils](./utils.md): General utilities that don't belong to a specific category.
- [ui](./ui.md): Houses Ashbloom's UI system.

Each namespace contains modules, written in snake_lowercase, and exposed structures, written in UpperCamelCase. For example, here's what the `math` namespace looks like as of 0.2.0:
```
pub const math = struct
{
    pub const linalg = @import("math/linalg.zig");
    pub const interp = @import("math/interp.zig");

    pub const Vec = linalg.Vec;
    pub const Mat = linalg.Mat;
};
```
Here, the available modules are `linalg` and `interp`, and the exposed `Vec` and `Mat` structures are basically shortcuts provided to the developer. All exposed structures either belong to a module, or are the only relevant and accessible thing in a module, such as the case with `rendering.RenderPass`:

```
pub const rendering = struct
{
	[...]
	// This module just contains the RenderPass struct, so there's no point in exposing the module itself.
	pub const RenderPass = @import("rendering/renderpass.zig").RenderPass;
	[...]
};
```

Not all public structures belonging to the modules in Ashbloom are exposed, only the larger structures which have a greater chance of being necessary.

There's a more detailed guide written for each namespace, which you can access by clicking on the links provided in that bullet list.