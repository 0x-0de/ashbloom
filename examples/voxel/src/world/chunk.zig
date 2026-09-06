const std = @import("std");
const ash = @import("ashbloom");

const Mesh = ash.rendering.Mesh;

const CommandBuffer = ash.rendering.commands.CommandBuffer;

/// Size of each chunk, in voxels.
pub const CHUNK_SIZE: ash.math.Vec(usize, 3) = .init(.{64, 64, 64});

/// Pipeline layout used for all chunk meshes.
var chunk_pl: ?ash.rendering.PipelineVertexInput = null;

/// Pipeline layout used for all chunk selection meshes.
var chunk_pl_selection: ?ash.rendering.PipelineVertexInput = null;

/// Adds a left-facing quad to the chunk at x,y,z.
fn add_left_face(mesh: *Mesh, x: f32, y: f32, z: f32, mode: Chunk.MeshMode) !void
{
    _ = mode;
    var verts = try mesh.add_vertices(6);

    try verts[0].add_attrib(@as([3]f32, .{x, y, z}));
    try verts[1].add_attrib(@as([3]f32, .{x, y + 1, z}));
    try verts[2].add_attrib(@as([3]f32, .{x, y + 1, z + 1}));
    try verts[3].add_attrib(@as([3]f32, .{x, y, z}));
    try verts[4].add_attrib(@as([3]f32, .{x, y + 1, z + 1}));
    try verts[5].add_attrib(@as([3]f32, .{x, y, z + 1}));

    try verts[0].add_attrib(@as(u32, 0));
    try verts[1].add_attrib(@as(u32, 0));
    try verts[2].add_attrib(@as(u32, 0));
    try verts[3].add_attrib(@as(u32, 0));
    try verts[4].add_attrib(@as(u32, 0));
    try verts[5].add_attrib(@as(u32, 0));

    try mesh.finalize_vertices();
}

/// Adds a right-facing quad to the chunk at x,y,z.
fn add_right_face(mesh: *Mesh, x: f32, y: f32, z: f32, mode: Chunk.MeshMode) !void
{
    _ = mode;
    var verts = try mesh.add_vertices(6);

    try verts[0].add_attrib(@as([3]f32, .{x + 1, y, z}));
    try verts[1].add_attrib(@as([3]f32, .{x + 1, y + 1, z + 1}));
    try verts[2].add_attrib(@as([3]f32, .{x + 1, y + 1, z}));
    try verts[3].add_attrib(@as([3]f32, .{x + 1, y, z}));
    try verts[4].add_attrib(@as([3]f32, .{x + 1, y, z + 1}));
    try verts[5].add_attrib(@as([3]f32, .{x + 1, y + 1, z + 1}));

    try verts[0].add_attrib(@as(u32, 1));
    try verts[1].add_attrib(@as(u32, 1));
    try verts[2].add_attrib(@as(u32, 1));
    try verts[3].add_attrib(@as(u32, 1));
    try verts[4].add_attrib(@as(u32, 1));
    try verts[5].add_attrib(@as(u32, 1));
    
    try mesh.finalize_vertices();
}

/// Adds a bottom-facing quad to the chunk at x,y,z.
fn add_bottom_face(mesh: *Mesh, x: f32, y: f32, z: f32, mode: Chunk.MeshMode) !void
{
    _ = mode;
    var verts = try mesh.add_vertices(6);

    try verts[0].add_attrib(@as([3]f32, .{x, y, z}));
    try verts[1].add_attrib(@as([3]f32, .{x + 1, y, z + 1}));
    try verts[2].add_attrib(@as([3]f32, .{x + 1, y, z}));
    try verts[3].add_attrib(@as([3]f32, .{x, y, z}));
    try verts[4].add_attrib(@as([3]f32, .{x, y, z + 1}));
    try verts[5].add_attrib(@as([3]f32, .{x + 1, y, z + 1}));

    try verts[0].add_attrib(@as(u32, 2));
    try verts[1].add_attrib(@as(u32, 2));
    try verts[2].add_attrib(@as(u32, 2));
    try verts[3].add_attrib(@as(u32, 2));
    try verts[4].add_attrib(@as(u32, 2));
    try verts[5].add_attrib(@as(u32, 2));
    
    try mesh.finalize_vertices();
}

/// Adds a top-facing quad to the chunk at x,y,z.
fn add_top_face(mesh: *Mesh, x: f32, y: f32, z: f32, mode: Chunk.MeshMode) !void
{
    _ = mode;
    var verts = try mesh.add_vertices(6);

    try verts[0].add_attrib(@as([3]f32, .{x, y + 1, z}));
    try verts[1].add_attrib(@as([3]f32, .{x + 1, y + 1, z}));
    try verts[2].add_attrib(@as([3]f32, .{x + 1, y + 1, z + 1}));
    try verts[3].add_attrib(@as([3]f32, .{x, y + 1, z}));
    try verts[4].add_attrib(@as([3]f32, .{x + 1, y + 1, z + 1}));
    try verts[5].add_attrib(@as([3]f32, .{x, y + 1, z + 1}));

    try verts[0].add_attrib(@as(u32, 3));
    try verts[1].add_attrib(@as(u32, 3));
    try verts[2].add_attrib(@as(u32, 3));
    try verts[3].add_attrib(@as(u32, 3));
    try verts[4].add_attrib(@as(u32, 3));
    try verts[5].add_attrib(@as(u32, 3));
    
    try mesh.finalize_vertices();
}

/// Adds a front-facing quad to the chunk at x,y,z.
fn add_front_face(mesh: *Mesh, x: f32, y: f32, z: f32, mode: Chunk.MeshMode) !void
{
    _ = mode;
    var verts = try mesh.add_vertices(6);
    
    try verts[0].add_attrib(@as([3]f32, .{x, y, z}));
    try verts[1].add_attrib(@as([3]f32, .{x + 1, y, z}));
    try verts[2].add_attrib(@as([3]f32, .{x + 1, y + 1, z}));
    try verts[3].add_attrib(@as([3]f32, .{x, y, z}));
    try verts[4].add_attrib(@as([3]f32, .{x + 1, y + 1, z}));
    try verts[5].add_attrib(@as([3]f32, .{x, y + 1, z}));

    try verts[0].add_attrib(@as(u32, 4));
    try verts[1].add_attrib(@as(u32, 4));
    try verts[2].add_attrib(@as(u32, 4));
    try verts[3].add_attrib(@as(u32, 4));
    try verts[4].add_attrib(@as(u32, 4));
    try verts[5].add_attrib(@as(u32, 4));
    
    try mesh.finalize_vertices();
}

/// Adds a back-facing quad to the chunk at x,y,z.
fn add_back_face(mesh: *Mesh, x: f32, y: f32, z: f32, mode: Chunk.MeshMode) !void
{
    _ = mode;
    var verts = try mesh.add_vertices(6);

    try verts[0].add_attrib(@as([3]f32, .{x, y, z + 1}));
    try verts[1].add_attrib(@as([3]f32, .{x + 1, y + 1, z + 1}));
    try verts[2].add_attrib(@as([3]f32, .{x + 1, y, z + 1}));
    try verts[3].add_attrib(@as([3]f32, .{x, y, z + 1}));
    try verts[4].add_attrib(@as([3]f32, .{x, y + 1, z + 1}));
    try verts[5].add_attrib(@as([3]f32, .{x + 1, y + 1, z + 1}));

    try verts[0].add_attrib(@as(u32, 5));
    try verts[1].add_attrib(@as(u32, 5));
    try verts[2].add_attrib(@as(u32, 5));
    try verts[3].add_attrib(@as(u32, 5));
    try verts[4].add_attrib(@as(u32, 5));
    try verts[5].add_attrib(@as(u32, 5));
    
    try mesh.finalize_vertices();
}

/// Represents a field of voxels. The size is determined by the CHUNK_SIZE constant.
pub const Chunk = struct
{
    /// Chunk position. Multiplied by CHUNK_SIZE to get the world position of each chunk and voxel.
    position: ash.math.Vec(isize, 3),
    /// Scale of the chunk. If 0, each block corresponds to each voxel. If >0, this chunk is a non-interactable LOD chunk.
    scale: u32,

    /// Allocator.
    allocator: *const std.mem.Allocator,
    /// Vulkan allocator.
    vk_allocator: *ash.utils.VulkanAllocator,

    /// Chunk mesh (main drawing).
    mesh: *ash.rendering.Mesh,
    /// Chunk mesh (selection buffer).
    mesh_selection: *ash.rendering.Mesh,
    /// Voxels.
    voxels: [][][]u32,

    pub const MeshMode = enum
    {
        Main,
        Selection
    };

    /// Loads and compiles the chunk mesh.
    fn build_mesh(self: *Chunk, fill_borders: bool, mesh: *ash.rendering.Mesh, mode: MeshMode) !void
    {
        // I only want to add the visible, outer-facing faces to the mesh, since those are presumably all that the player would see (even though this demo uses a freeroam camera).
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
                    try add_left_face(mesh, fi, fj, fk, mode);
                }
                if(i == CHUNK_SIZE.data[0] - 1 or self.voxels[i + 1][j][k] == 0)
                {
                    try add_right_face(mesh, fi, fj, fk, mode);
                }
                if(j == 0 or self.voxels[i][j - 1][k] == 0)
                {
                    try add_bottom_face(mesh, fi, fj, fk, mode);
                }
                if(j == CHUNK_SIZE.data[1] - 1 or self.voxels[i][j + 1][k] == 0)
                {
                    try add_top_face(mesh, fi, fj, fk, mode);
                }
                if(k == 0 or self.voxels[i][j][k - 1] == 0)
                {
                    try add_front_face(mesh, fi, fj, fk, mode);
                }
                if(k == CHUNK_SIZE.data[2] - 1 or self.voxels[i][j][k + 1] == 0)
                {
                    try add_back_face(mesh, fi, fj, fk, mode);
                }
            }
        }}}
    }

    /// Builds all chunk meshes (the visible mesh and the selection mesh).
    pub fn build(self: *Chunk, fill_borders: bool) !void
    {
        try self.build_mesh(fill_borders, self.mesh, .Main);
        try self.build_mesh(fill_borders, self.mesh_selection, .Selection);
        
        try self.mesh.build(true);
        try self.mesh_selection.build(true);
    }

    /// Deinitializes the chunk.
    pub fn deinit(self: *Chunk) void
    {
        self.mesh.deinit();
        self.mesh_selection.deinit();

        self.allocator.destroy(self.mesh);
        self.allocator.destroy(self.mesh_selection);

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

    /// Draws a chunk mesh, the specific mesh is determined by the mode.
    pub fn draw(self: *Chunk, mode: MeshMode, command_buffer: *CommandBuffer) !void
    {
        switch(mode)
        {
            .Main => {
                try self.mesh.bind_and_draw_vertices(command_buffer);
            },
            .Selection => {
                try self.mesh_selection.bind_and_draw_vertices(command_buffer);
            }
        }
    }

    /// Initializes a new Chunk.
    pub fn init(allocator: *const std.mem.Allocator, vk_allocator: *ash.utils.VulkanAllocator, position: ash.math.Vec(isize, 3), scale: u32) !Chunk
    {
        // Must call Chunk.init_context before creating a chunk.
        std.debug.assert(chunk_pl != null);

        var chunk: Chunk = .{
            .position = position,
            .scale = scale,
            .allocator = allocator,
            .vk_allocator = vk_allocator,
            .mesh = try allocator.create(ash.rendering.Mesh),
            .mesh_selection = try allocator.create(ash.rendering.Mesh),
            .voxels = undefined,
        };

        chunk.mesh.* = try .init(allocator, vk_allocator, chunk_pl.?, 0, 0);
        chunk.mesh_selection.* = try .init(allocator, vk_allocator, chunk_pl_selection.?, 0, 0);

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
    pub fn init_context(pipeline_layout_main: ash.rendering.PipelineVertexInput, pipeline_layout_selection: ash.rendering.PipelineVertexInput) void
    {
        chunk_pl = pipeline_layout_main;
        chunk_pl_selection = pipeline_layout_selection;
    }

    /// Sets all of the voxels in the chunk.
    pub fn generate(self: *Chunk) void
    {
        for(0..CHUNK_SIZE.data[0]) |i| {
        for(0..CHUNK_SIZE.data[2]) |k|
        {
            const x: f64 = @floatFromInt(i);
            const z: f64 = @floatFromInt(k);

            const r = (ash.gen.random.value_noise_2d(128124, x / 24, z / 24, .{
                .octaves = 5,
                .focus = 1.6,
                .persistance = 0.45
            }) + 1) * 32;

            const ri: u32 = @intFromFloat(r);

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

    /// Set a voxel to a value, and then build the mesh if `rebuild` is true.
    pub fn set(self: *Chunk, x: u32, y: u32, z: u32, value: u32) void
    {
        self.voxels[x][y][z] = value;
    }
};
