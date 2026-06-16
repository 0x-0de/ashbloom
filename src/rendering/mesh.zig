const std = @import("std");
const ash = @import("../root.zig");

/// Errors relating to vertex creation and addition to meshes.
pub const VertexError = error
{
    IncompatibleVertex,
    IncompleteVertex,
    IncompatibleAttribute,
    BufferOverflow
};

/// Utility struct for storing vertex data.
pub const Vertex = struct
{
    /// Pointer to the mesh which this vertex is a part of.
    mesh: *Mesh,
    /// Location of vertex memory in the mesh.
    memory_offset: [*]u8,

    /// Current lid (**do not set this**).
    lid: u16,
    /// Current attribute offset (**do not set this**).
    attribute_offset: u8,

    /// Initializes the Vertex object, populates this structure with the information provided in `layout`.
    pub fn init(mesh: *Mesh, memory_offset: [*]u8) !Vertex
    {
        return .{
            .mesh = mesh,
            .memory_offset = memory_offset,
            .lid = 0,
            .attribute_offset = 0
        };
    }

    /// Populates the next attribute of the vertex.
    pub fn add_attrib(self: *Vertex, value: anytype) VertexError!void
    {
        const num_attributes = self.mesh.attribute_sizes.len;
        if(self.attribute_offset == num_attributes) return VertexError.BufferOverflow;

        const bytes = std.mem.asBytes(&value);
        if(bytes.len != self.mesh.attribute_sizes[self.attribute_offset]) return VertexError.IncompatibleAttribute;
        if(self.lid + bytes.len > self.mesh.vertex_size) return VertexError.BufferOverflow;

        for(0..bytes.len) |i|
        {
            const offset = self.lid + i;
            self.memory_offset[offset] = bytes[i];
        }

        self.attribute_offset += 1;
        self.lid += bytes.len;
    }
};

/// Utility struct for creating and storing Vulkan vertex buffers.
pub const Mesh = struct
{
    /// Allocator.
    allocator: *const std.mem.Allocator,
    /// Vulkan allocator.
    vk_allocator: *ash.VulkanAllocator,

    /// Vertex binding this mesh belongs to.
    vertex_binding: u32,
    /// Size of each attribute (in bytes).
    attribute_sizes: []u8,
    /// Size of each vertex.
    vertex_size: u16,
    /// Total number of vertices in the built mesh.
    num_vertices: u32,

    /// List of all vertices currently allocated to this mesh.
    vertices: std.ArrayList(Vertex),
    /// List of all vertex data **to be allocated** to GPU memory when this mesh is built.
    vertex_data: std.ArrayList(u8),
    /// Vulkan buffer (allocated upon calling `self.build(...)`).
    buffer: ?ash.VulkanAllocator.VulkanBufferAllocation,

    /// Deinitializes the Mesh object.
    pub fn deinit(self: *Mesh) void
    {
        if(self.buffer != null)
        {
            self.vk_allocator.free_buffer(self.buffer.?);
        }

        self.vertices.deinit(self.allocator.*);
        self.vertex_data.deinit(self.allocator.*);

        self.allocator.free(self.attribute_sizes);
    }

    /// Initializes the Mesh object. Uses a PipelineVertexInput to determine the sizes, formats, and total number of vertex attributes this mesh will use.
    /// The `input_binding` parameter specifies what binding in the PipelineVertexInput this mesh should use.
    /// The `verts_reserve` variable determines how many vertices should be pre-allocated in the `data` list.
    pub fn init(allocator: *const std.mem.Allocator, vk_allocator: *ash.VulkanAllocator, layout: ash.PipelineVertexInput, vertex_binding: u32, verts_reserve: usize) !Mesh
    {
        var num_att: usize = 0;
        for(layout.attribute_descriptions.items) |att|
        {
            if(att.binding == vertex_binding)
            {
                num_att += 1;
            }
        }

        std.debug.assert(num_att > 0 and num_att < 256);
        
        var mesh: Mesh = .{
            .allocator = allocator,
            .vk_allocator = vk_allocator,
            .vertex_binding = vertex_binding,
            .attribute_sizes = try allocator.alloc(u8, num_att),
            .vertex_size = 0,
            .num_vertices = 0,
            .vertices = undefined,
            .vertex_data = try .initCapacity(allocator.*, 0),
            .buffer = null
        };

        var cur_att: usize = 0;

        for(layout.attribute_descriptions.items) |att|
        {
            if(att.binding == vertex_binding)
            {
                const format_size = try ash.vk_utils.get_vulkan_format_size(att.format);
                mesh.attribute_sizes[cur_att] = @truncate(format_size);
                mesh.vertex_size += @truncate(format_size);

                cur_att += 1;
            }
        }

        mesh.vertices = try .initCapacity(allocator.*, verts_reserve);

        return mesh;
    }

    /// Attempts to add a vertex data to the `vertices` list, **initialize** it, and return it. All vertex data should be added and completed before `self.build(...)` is called.
    pub fn add_vertex(self: *Mesh) !*Vertex
    {
        const vertex = try self.vertices.addOne(self.allocator.*);
        const data = try self.vertex_data.addManyAsSlice(self.allocator.*, self.vertex_size);
        vertex.* = try .init(self, data.ptr);
        return vertex;
    }

    pub fn add_vertices(self: *Mesh, n: usize) ![]Vertex
    {
        const vertices = try self.vertices.addManyAsSlice(self.allocator.*, n);
        const data = try self.vertex_data.addManyAsSlice(self.allocator.*, self.vertex_size * n);
        for(0..n) |i|
        {
            vertices[i] = try .init(self, data.ptr + i * self.vertex_size);
        }
        return vertices;
    }

    /// Use the `command_buffer` to bind the Mesh's vertex buffer.
    pub fn bind(self: *Mesh, command_buffer: *ash.CommandBuffer) void
    {
        command_buffer.cmd_bind_vertex_buffer(self.vertex_binding, self.buffer.?.buffer, 0);
    }

    /// Binds, then draws, the Mesh as vertices (records those commands onto the `command_buffer`).
    pub fn bind_and_draw_vertices(self: *Mesh, command_buffer: *ash.CommandBuffer) void
    {
        self.bind(command_buffer);
        self.draw_vertices(command_buffer);
    }

    /// Allocates a buffer using the Vulkan allocator, stages the vertex data into it, and, if `clear` is true, deallocates the memory held by `self.data`.
    pub fn build(self: *Mesh, clear: bool) !void
    {
        if(self.buffer != null)
        {
            self.vk_allocator.free_buffer(self.buffer.?);
        }

        self.num_vertices = @truncate(self.vertex_data.items.len / self.vertex_size);
        self.buffer = try self.vk_allocator.alloc_buffer(u8, self.vertex_data.items, .exclusive, .VertexBuffer);

        if(clear)
        {
            self.vertex_data.clearAndFree(self.allocator.*);
            self.vertices.clearAndFree(self.allocator.*);
        }
    }

    /// Uses the `command_buffer` to draw the Mesh as vertices.
    pub fn draw_vertices(self: *Mesh, command_buffer: *ash.CommandBuffer) void
    {
        command_buffer.cmd_draw(self.num_vertices, 1);
    }

    /// After finishing and finalizing a set of vertices for the mesh, it's recommended to call this function to "release" the memory associated with those vertices
    /// and minimize unnessecary allocations. All of the vertices are fully cleared out when the mesh is built. Checks for incomplete vertices.
    pub fn finalize_vertices(self: *Mesh) VertexError!void
    {
        for(self.vertices.items) |v|
        {
            if(v.lid < self.vertex_size)
            {
                return VertexError.IncompleteVertex;
            }
        }

        self.vertices.clearRetainingCapacity();
    }
};

