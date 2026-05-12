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
    /// Number of attributes for this vertex.
    num_attributes: u8,
    /// Total size of the vertex (in bytes).
    vertex_size: u16,
    /// Size of each attribute (in bytes).
    attribute_sizes: []u8,
    /// Vertex data.
    data: []u8,

    /// Current lid (**do not set this**).
    lid: u16,
    /// Current attribute offset (**do not set this**).
    attribute_offset: u8,

    /// Deinitializes the Vertex object.
    pub fn deinit(self: *Vertex, allocator: *const std.mem.Allocator) void
    {
        allocator.free(self.data);
        allocator.free(self.attribute_sizes);
    }

    /// Initializes the Vertex object, populates this structure with the information provided in `layout`.
    pub fn init(allocator: *const std.mem.Allocator, layout: ash.PipelineVertexInput) !Vertex
    {
        const num_att = layout.attribute_descriptions.items.len;
        std.debug.assert(num_att < 256);

        var vertex_size: usize = 0;
        var att_sizes = try allocator.alloc(u8, num_att);

        for(layout.attribute_descriptions.items, 0..) |att, i|
        {
            const format_size = try ash.vk_utils.get_vulkan_format_size(att.format);
            std.debug.assert(format_size < std.math.maxInt(u8) + 1);
            att_sizes[i] = @truncate(format_size);
            vertex_size += att_sizes[i];
        }

        return .{
            .num_attributes = @truncate(num_att),
            .vertex_size = @truncate(vertex_size),
            .attribute_sizes = att_sizes,
            .data = try allocator.alloc(u8, vertex_size),
            .lid = 0,
            .attribute_offset = 0
        };
    }

    /// Populates the next attribute of the vertex.
    pub fn add_attrib(self: *Vertex, value: anytype) VertexError!void
    {
        if(self.attribute_offset == self.num_attributes) return VertexError.BufferOverflow;

        const bytes = std.mem.asBytes(&value);
        if(bytes.len != self.attribute_sizes[self.attribute_offset]) return VertexError.IncompatibleAttribute;
        if(self.lid + bytes.len > self.data.len) return VertexError.BufferOverflow;

        for(0..bytes.len) |i|
        {
            const offset = self.lid + i;
            self.data[offset] = bytes[i];
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

    /// Layout of each vertex in the mesh.
    layout: ash.PipelineVertexInput,
    /// Size of each vertex.
    vertex_size: u16,
    /// Total number of vertices in the built mesh.
    num_vertices: u32,

    /// List of all vertex data **to be allocated** to GPU memory when this mesh is built.
    vertices: std.ArrayList(Vertex),
    /// Vulkan buffer (allocated upon calling `self.build(...)`).
    buffer: ?ash.VulkanAllocator.VulkanBufferAllocation,

    /// Deinitializes the Mesh object.
    pub fn deinit(self: *Mesh) !void
    {
        if(self.buffer != null)
        {
            try self.vk_allocator.free_buffer(self.buffer.?);
        }

        for(self.vertices.items) |*v|
        {
            v.deinit(self.allocator);
        }

        self.vertices.deinit(self.allocator.*);
    }

    /// Initializes the Mesh object. Uses a PipelineVertexInput to determine the sizes, formats, and total number of vertex attributes this mesh will use.
    /// The `verts_reserve` variable determines how many vertices should be pre-allocated in the `data` list.
    pub fn init(allocator: *const std.mem.Allocator, vk_allocator: *ash.VulkanAllocator, layout: ash.PipelineVertexInput, verts_reserve: usize) !Mesh
    {
        const num_att = layout.attribute_descriptions.items.len;
        std.debug.assert(num_att > 0 and num_att < 256);
        
        var mesh: Mesh = .{
            .allocator = allocator,
            .vk_allocator = vk_allocator,
            .layout = layout,
            .vertex_size = 0,
            .num_vertices = 0,
            .vertices = undefined,
            .buffer = null
        };

        for(layout.attribute_descriptions.items) |att|
        {
            const format_size = try ash.vk_utils.get_vulkan_format_size(att.format);
            mesh.vertex_size += @truncate(format_size);
        }

        mesh.vertices = try .initCapacity(allocator.*, verts_reserve);

        return mesh;
    }

    /// Attempts to add a vertex data to the `vertices` list, **initialize** it, and return it. All vertex data should be added and completed before `self.build(...)` is called.
    pub fn add_vertex(self: *Mesh) !*Vertex
    {
        const vertex = try self.vertices.addOne(self.allocator.*);
        vertex.* = try .init(self.allocator, self.layout);
        return vertex;
    }

    /// Use the `command_buffer` to bind the Mesh's vertex buffer.
    pub fn bind(self: *Mesh, command_buffer: *ash.CommandBuffer) void
    {
        command_buffer.cmd_bind_vertex_buffer(self.buffer.?.buffer, 0);
    }

    /// Binds, then draws, the Mesh (records those commands onto the `command_buffer`).
    pub fn bind_and_draw(self: *Mesh, command_buffer: *ash.CommandBuffer) void
    {
        self.bind(command_buffer);
        self.draw(command_buffer);
    }

    /// Allocates a buffer using the Vulkan allocator, stages the vertex data into it, and, if `clear` is true, deallocates the memory held by `self.data`.
    pub fn build(self: *Mesh, clear: bool) !void
    {
        if(self.buffer != null)
        {
            try self.vk_allocator.free_buffer(self.buffer.?);
        }

        self.num_vertices = @truncate(self.vertices.items.len);
        const vertex_data = try self.allocator.alloc(u8, self.vertex_size * self.num_vertices);
        defer self.allocator.free(vertex_data);

        for(0..self.num_vertices) |i|
        {
            for(0..self.vertices.items[i].data.len) |j|
            {
                vertex_data[i * self.vertex_size + j] = self.vertices.items[i].data[j];
            }
        }

        self.buffer = try self.vk_allocator.alloc_buffer(u8, vertex_data, .exclusive, .VertexBuffer);

        if(clear)
        {
            for(self.vertices.items) |*v|
            {
                v.deinit(self.allocator);
            }

            self.vertices.clearRetainingCapacity();
        }
    }

    /// Uses the `command_buffer` to draw the Mesh.
    pub fn draw(self: *Mesh, command_buffer: *ash.CommandBuffer) void
    {
        command_buffer.cmd_draw(self.num_vertices, 1);
    }
};
