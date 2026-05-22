const std = @import("std");
const ash = @import("ashbloom");

const CommandBuffer = ash.commands.CommandBuffer;

/// Size of each chunk, in voxels.
pub const CHUNK_SIZE: ash.Vec(usize, 3) = .init(.{64, 64, 64});

/// Pipeline layout used for all chunk meshes.
var chunk_pl: ?ash.PipelineVertexInput = null;

pub const Chunk = struct
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
    /// Voxels.
    voxels: [][][]u32,

    pub fn build(self: *Chunk, fill_borders: bool) !void
    {
        for(0..CHUNK_SIZE.data[0]) |i| {
        for(0..CHUNK_SIZE.data[1]) |j| {
        for(0..CHUNK_SIZE.data[2]) |k|
        {
            const fi = @as(f32, @floatFromInt(i));
            const fj = @as(f32, @floatFromInt(j));
            const fk = @as(f32, @floatFromInt(k));

            if(self.voxels[i][j][k] == 0) continue;

            if(fill_borders)
            {
                if(i == 0 or self.voxels[i - 1][j][k] == 0)
                {
                    var v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi, fj, fk}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi, fj + 1, fk}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi, fj + 1, fk + 1}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi, fj, fk}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi, fj + 1, fk + 1}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi, fj, fk + 1}));
                }
                if(i == CHUNK_SIZE.data[0] - 1 or self.voxels[i + 1][j][k] == 0)
                {
                    var v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi + 1, fj, fk}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi + 1, fj + 1, fk + 1}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi + 1, fj + 1, fk}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi + 1, fj, fk}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi + 1, fj, fk + 1}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi + 1, fj + 1, fk + 1}));
                }
                if(j == 0 or self.voxels[i][j - 1][k] == 0)
                {
                    var v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi, fj, fk}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi + 1, fj, fk + 1}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi + 1, fj, fk}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi, fj, fk}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi, fj, fk + 1}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi + 1, fj, fk + 1}));
                }
                if(j == CHUNK_SIZE.data[1] - 1 or self.voxels[i][j + 1][k] == 0)
                {
                    var v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi, fj + 1, fk}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi + 1, fj + 1, fk}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi + 1, fj + 1, fk + 1}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi, fj + 1, fk}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi + 1, fj + 1, fk + 1}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi, fj + 1, fk + 1}));
                }
                if(k == 0 or self.voxels[i][j][k - 1] == 0)
                {
                    var v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi, fj, fk}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi + 1, fj, fk}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi + 1, fj + 1, fk}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi, fj, fk}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi + 1, fj + 1, fk}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi, fj + 1, fk}));
                }
                if(k == CHUNK_SIZE.data[2] - 1 or self.voxels[i][j][k + 1] == 0)
                {
                    var v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi, fj, fk + 1}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi + 1, fj + 1, fk + 1}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi + 1, fj, fk + 1}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi, fj, fk + 1}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi, fj + 1, fk + 1}));
                    v = try self.mesh.add_vertex();
                    try v.add_attrib(@as([3]f32, .{fi + 1, fj + 1, fk + 1}));
                }
            }
        }}}

        try self.mesh.build(true);
    }

    pub fn deinit(self: *Chunk) !void
    {
        try self.mesh.deinit();
        self.allocator.destroy(self.mesh);

        for(self.voxels) |*v|
        {
            for(v.*) |*vv|
            {
                self.allocator.free(vv.*);
            }
            self.allocator.free(v.*);
        }
        self.allocator.free(self.voxels);
    }

    pub fn draw(self: *Chunk, command_buffer: *CommandBuffer) void
    {
        self.mesh.bind_and_draw(command_buffer);
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
            .mesh = try allocator.create(ash.Mesh),
            .voxels = undefined,
        };

        chunk.mesh.* = try .init(allocator, vk_allocator, chunk_pl.?, 0);

        chunk.voxels = try allocator.alloc([][]u32, CHUNK_SIZE.data[0]);
        for(chunk.voxels) |*v|
        {
            v.* = try allocator.alloc([]u32, CHUNK_SIZE.data[1]);
            for(v.*) |*vv|
            {
                vv.* = try allocator.alloc(u32, CHUNK_SIZE.data[2]);
            }
        }

        return chunk;
    }

    /// Initializes all necessary rendering resources to allow chunks to be initialized and built.
    pub fn init_context(pipeline_layout: ash.PipelineVertexInput) void
    {
        chunk_pl = pipeline_layout;
    }

    /// Sets all of the voxels in the chunk.
    pub fn generate(self: *Chunk) void
    {
        for(0..CHUNK_SIZE.data[0]) |i| {
        for(0..CHUNK_SIZE.data[2]) |k|
        {
            const x: f64 = @floatFromInt(i);
            const z: f64 = @floatFromInt(k);

            const r = (ash.random.value_noise_2d(128124, x / 24, z / 24, .{
                .octaves = 4,
                .focus = 2,
                .persistance = 0.333
            }) + 1) * 32;

            const ri: u8 = @intFromFloat(r);

            for(0..CHUNK_SIZE.data[1]) |j|
            {
                if(j < ri)
                {
                    self.voxels[i][j][k] = 1;
                }
                else
                {
                    self.voxels[i][j][k] = 0;
                }
            }
        }}
    }
};
