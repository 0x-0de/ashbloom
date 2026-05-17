const std = @import("std");
const ash = @import("ashbloom");

/// Size of each chunk, in voxels.
pub const CHUNK_SIZE: ash.Vec(usize, 3) = .init(64, 64, 64);

/// Pipeline layout used for all chunk meshes.
var chunk_pl: ?ash.PipelineVertexInput = null;

const Chunk = struct
{
    /// Chunk position. Multiplied by CHUNK_SIZE to get the world position of each chunk and voxel.
    position: ash.Vec(isize, 3),
    /// Scale of the chunk. If 0, each block corresponds to each voxel. If >0, this chunk is a non-interactable LOD chunk.
    scale: u8,

    /// Allocator.
    allocator: *const std.mem.Allocator,
    /// Vulkan allocator.
    vk_allocator: *ash.VulkanAllocator,

    /// Chunk mesh.
    mesh: *ash.Mesh,

    pub fn deinit(self: *Chunk) !void
    {
        try self.mesh.deinit();
        self.allocator.destroy(self.mesh);
    }

    pub fn init(allocator: *const std.mem.Allocator, vk_allocator: *ash.VulkanAllocator, position: ash.Vec(isize, 3), scale: u8) !Chunk
    {
        // Must call Chunk.init_context before creating a chunk.
        std.debug.assert(chunk_pl != null);

        var chunk: Chunk = .{
            .position = position,
            .scale = scale,
            .allocator = allocator,
            .vk_allocator = vk_allocator,
            .mesh = try allocator.create(ash.Mesh)
        };

        chunk.mesh.* = .init(allocator, vk_allocator, chunk_pl.?, 0);

        return chunk;
    }

    /// Initializes all necessary rendering resources to allow chunks to be initialized and built.
    pub fn init_context(pipeline_layout: ash.PipelineVertexInput) void
    {
        chunk_pl = pipeline_layout;
    }
};
