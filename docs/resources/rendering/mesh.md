# `mesh`

Meshes are utilities that streamline the creation and formatting of multiple vertex buffers, intended to be used together to draw a single object, model, or entity. This namespace contains structures for both meshes and the vertices that they contain.

## Mesh (`struct`)

Utility struct for creating and storing Vulkan vertex buffers.

### Fields

`allocator: *const std.mem.Allocator` - CPU allocator.

`vk_allocator: *ash.utils.VulkanAllocator` - Vulkan allocator.

`vertex_binding: u32` - Vertex binding this mesh belongs to.

`attribute_sizes: []u8` - Size of each attribute (in bytes).

`vertex_size: u16` - Size of each vertex.

`num_vertices: u32` - Total number of vertices in the built mesh.

`vertices: std.ArrayList(Vertex)` - List of all vertices currently allocated to this mesh.

`vertex_data: std.ArrayList(u8)` - List of all vertex data **to be allocated** to GPU memory when this mesh is built.

`buffer: ?ash.utils.VulkanAllocator.VulkanBufferAllocation` - Vulkan buffer (allocated upon calling **`build`**).

### Public Functions

**`add_vertex(self: *Mesh) !*Vertex`**

Attempts to add a vertex to the `vertices` list, **initialize** it, and return it. All vertex data should be added and completed before **`build`** or **`finalize_vertices`** is called.

**`add_vertices(self: *Mesh, n: usize) ![]Vertex`**

Attempts to add multiple vertices to the `vertices` list, **initialize** them, and return them as a slice. All vertex data should be added and completed before **`build`** or **`finalize_vertices`** is called.

**`bind(self: *Mesh, command_buffer: *ash.rendering.CommandBuffer) MeshError!void`**

Use the `command_buffer` to bind the mesh's vertex buffer.

**`bind_and_draw_vertices(self: *Mesh, command_buffer: *ash.rendering.CommandBuffer) MeshError!void`**

Binds, then draws, the Mesh as vertices (records those commands onto the `command_buffer`).

**`build(self: *Mesh, clear: bool) !void`**

Allocates a buffer using the Vulkan allocator, stages the vertex data into it, and, if `clear` is true, deallocates the memory held by `self.data`.

**`deinit(self: *Mesh) void`**

Deinitializes the Mesh object.

**`draw_instances(self: *Mesh, command_buffer: *ash.rendering.CommandBuffer, vertex_count: u32) void`**

Uses the `command_buffer` to draw the Mesh as instances.

**`draw_vertices(self: *Mesh, command_buffer: *ash.rendering.CommandBuffer) void`**

Uses the `command_buffer` to draw the Mesh as vertices.

**`finalize_vertices(self: *Mesh) VertexError!void`**

After finishing and finalizing a set of vertices for the mesh, it's recommended to call this function to "release" the memory associated with those vertices and minimize unnessecary allocations. All of the vertices are fully cleared out when the mesh is built. Checks for incomplete vertices.

**`init(allocator: *const std.mem.Allocator, vk_allocator: *ash.utils.VulkanAllocator, layout: ash.rendering.PipelineVertexInput, vertex_binding: u32, verts_reserve: usize) !Mesh`**

Initializes the Mesh object. Uses a PipelineVertexInput to determine the sizes, formats, and total number of vertex attributes this mesh will use. The `input_binding` parameter specifies what binding in the `PipelineVertexInput` this mesh should use. The `verts_reserve` variable determines how many vertices should be pre-allocated in the `data` list.

## Vertex (`struct`)

### Fields

`mesh: *Mesh` - Pointer to the mesh which this vertex is a part of.

`memory_offset: [*]u8` - Location of vertex memory in the mesh.

`lid: u16` - Current lid (**do not set this**).

`attribute_offset: u8` - Current attribute offset (**do not set this**).

### Public Functions

**`add_attrib(self: *Vertex, value: anytype) VertexError!void`**

Populates the next attribute of the vertex.

**`init(mesh: *Mesh, memory_offset: [*]u8) !Vertex`**

Initializes the `Vertex` object.

## Errors

### `VertexError`

Errors related to vertex creation and addition to meshes.

#### Values

**IncompatibleVertex** - Currently unused.

**IncompleteVertex** - Attempted to finalize or build with a vertex without populating it properly.

**IncompatibleAttribute** -  - Vertex memory layout does not match the data that is being added to it.

**BufferOverflow** - Attempt to add too much data to a vertex.

### `MeshError`

Generic errors relating to meshes.

#### Values

**MeshIsEmpty** - Attempted to bind an empty mesh.