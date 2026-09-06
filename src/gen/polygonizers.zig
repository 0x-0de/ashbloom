const std = @import("std");
const ash = @import("../root.zig");

const Vec = ash.math.Vec;

/// Represents a cell in a signed-distance field. A cell is a cubic space where the points at the 8 corners of the cube have known distances from the isosurface.
/// Ashbloom's polygonizers mandate that *negative* distance values mean that the point is **outside** the isosurface, while *positive* values indicate that the
/// point is **inside** the isosurface.
pub const SDFCell = struct
{
    /// Position of the cell in **mesh**-space. This determines where the geometry is placed in the mesh.
    pos: [3]f32,
    /// Scale of the cell in **mesh**-space. This determines the size of the geometry in the mesh.
    scl: [3]f32,
    /// This array is ordered as [X,Y,Z] in ascending binary => [-,-,-], [+,-,-], [-,+,-], [+,+,-], [-,-,+], [+,-,+], [-,+,+], [+,+,+], where '-' represents the
    /// smaller x/y/z value and '+' represents the larger x/y/z value.
    values: [8]f32
};

fn midpoint_linear(a: f32, b: f32, t: f32) f32
{
    return (t - a) / (b - a);
}

pub const PolygonizeCallback: type = *const fn(SDFCell, *ash.mesh.Vertex, [3]f32) ash.rendering.mesh.VertexError!void;

/// The default polygonizer callback, called if **null** is passed to any of the polygonizer algorithms contained in Ashbloom. Adds the position vertex to the mesh,
/// and assumes the first and only attribute of the mesh is the vertex position.
pub fn default_vertex_addition(cell: SDFCell, vertex: *ash.mesh.Vertex, vertex_position: [3]f32) ash.mesh.VertexError!void
{
    _ = cell;
    try vertex.add_attrib(vertex_position);
}

/// This structure is essentially just a namespace that houses the marching cubes polygonization algorithm.
pub const MarchingCubes = struct
{
    /// Adds triangles to the mesh, created and calcuated using the marching cubes algorithm. This algorithm is intended to be used one cell at a time,
    /// so this function only adds triangles for a single cell. You will likely need to pass a function to handle adding actual vertex data to the mesh,
    /// which is the purpose of `callback`. If **null** is passed, the `polygonizers.default_vertex_addition` is used in place of `callback`, and this function
    /// provides an example of how `callback` should be used.
    pub fn add_cell_to_mesh(mesh: *ash.Mesh, cell: SDFCell, callback: ?PolygonizeCallback) !void
    {
        var code: u8 = 0;

        for(0..8) |i|
        {
            const bit: u8 = if(cell.values[i] > 0) 1 else 0;
            code |= (bit << @as(u3, @truncate(i)));
        }

        const x_p = cell.pos[0];
        const y_p = cell.pos[1];
        const z_p = cell.pos[2];

        const x_s = cell.scl[0];
        const y_s = cell.scl[1];
        const z_s = cell.scl[2];

        const x_00 = midpoint_linear(cell.values[0], cell.values[1], 0); // 0,0,0 -> 1,0,0
        const x_y0 = midpoint_linear(cell.values[2], cell.values[3], 0); // 0,1,0 -> 1,1,0
        const x_0z = midpoint_linear(cell.values[4], cell.values[5], 0); // 0,0,1 -> 1,0,1
        const x_yz = midpoint_linear(cell.values[6], cell.values[7], 0); // 0,1,1 -> 1,1,1

        const y_00 = midpoint_linear(cell.values[0], cell.values[2], 0); // 0,0,0 -> 0,1,0
        const y_x0 = midpoint_linear(cell.values[1], cell.values[3], 0); // 1,0,0 -> 1,1,0
        const y_0z = midpoint_linear(cell.values[4], cell.values[6], 0); // 0,0,1 -> 0,1,1
        const y_xz = midpoint_linear(cell.values[5], cell.values[7], 0); // 1,0,1 -> 1,1,1
        
        const z_00 = midpoint_linear(cell.values[0], cell.values[4], 0); // 0,0,0 -> 0,0,1
        const z_x0 = midpoint_linear(cell.values[1], cell.values[5], 0); // 1,0,0 -> 1,0,1
        const z_0y = midpoint_linear(cell.values[2], cell.values[6], 0); // 0,1,0 -> 0,1,1
        const z_xy = midpoint_linear(cell.values[3], cell.values[7], 0); // 1,1,0 -> 1,1,1

        const vertices: [12][3]f32 = .{
            .{x_p + x_00 * x_s, y_p, z_p},
            .{x_p + x_y0 * x_s, y_p + y_s, z_p},
            .{x_p + x_0z * x_s, y_p, z_p + z_s},
            .{x_p + x_yz * x_s, y_p + y_s, z_p + z_s},
            .{x_p, y_p + y_00 * y_s, z_p},
            .{x_p + x_s, y_p + y_x0 * y_s, z_p},
            .{x_p, y_p + y_0z * y_s, z_p + z_s},
            .{x_p + x_s, y_p + y_xz * y_s, z_p + z_s},
            .{x_p, y_p, z_p + z_00 * z_s},
            .{x_p + x_s, y_p, z_p + z_x0 * z_s},
            .{x_p, y_p + y_s, z_p + z_0y * z_s},
            .{x_p + x_s, y_p + y_s, z_p + z_xy * z_s}
        };

        const indices: []const usize = switch(code)
        {
            0, 255 => &.{},
            1 => &.{0, 8, 4},
            2 => &.{0, 5, 9},
            3 => &.{4, 5, 8, 5, 9, 8},
            4 => &.{4, 10, 1},
            5 => &.{0, 8, 10, 0, 10, 1},
            6 => &.{0, 5, 9, 4, 10, 1},
            7 => &.{8, 10, 9, 10, 1, 9, 9, 1, 5},
            8 => &.{1, 11, 5},
            9 => &.{0, 8, 4, 1, 11, 5},
            10 => &.{0, 11, 9, 0, 1, 11},
            11 => &.{9, 8, 11, 11, 8, 1, 8, 4, 1},
            12 => &.{4, 11, 5, 4, 10, 11},
            13 => &.{10, 11, 8, 8, 11, 0, 11, 5, 0},
            14 => &.{11, 9, 10, 9, 0, 10, 10, 0, 4},
            15 => &.{8, 10, 9, 9, 10, 11},
            16 => &.{2, 6, 8},
            17 => &.{4, 0, 2, 4, 2, 6},
            18 => &.{2, 6, 8, 0, 5, 9},
            19 => &.{4, 5, 6, 5, 9, 6, 6, 9, 2},
            20 => &.{2, 6, 8, 4, 10, 1},
            21 => &.{0, 2, 1, 1, 2, 10, 2, 6, 10},
            22 => &.{0, 5, 9, 4, 10, 1, 2, 6, 8},
            23 => &.{6, 10, 1, 1, 2, 6, 2, 1, 5, 5, 9, 2},
            24 => &.{2, 6, 8, 1, 11, 5},
            25 => &.{4, 0, 2, 4, 2, 6, 1, 11, 5},
            26 => &.{0, 11, 9, 0, 1, 11, 2, 6, 8},
            27 => &.{2, 4, 11, 11, 4, 1, 4, 2, 6, 2, 11, 9},
            28 => &.{4, 11, 5, 4, 10, 11, 2, 6, 8},
            29 => &.{5, 0, 11, 11, 0, 6, 6, 10, 11, 6, 0, 2},
            30 => &.{11, 9, 10, 9, 0, 10, 10, 0, 4, 2, 6, 8},
            31 => &.{11, 9, 10, 9, 2, 10, 10, 2, 6},
            32 => &.{2, 9, 7},
            33 => &.{0, 8, 4, 2, 9, 7},
            34 => &.{0, 5, 7, 0, 7, 2},
            35 => &.{5, 7, 4, 4, 7, 8, 7, 2, 8},
            36 => &.{2, 9, 7, 4, 10, 1},
            37 => &.{0, 8, 10, 0, 10, 1, 2, 9, 7},
            38 => &.{0, 5, 7, 0, 7, 2, 4, 10, 1},
            39 => &.{2, 10, 5, 10, 1, 5, 5, 7, 2, 2, 8, 10},
            40 => &.{2, 9, 7, 1, 11, 5},
            41 => &.{2, 9, 7, 1, 11, 5, 0, 8, 4},
            42 => &.{0, 1, 2, 1, 11, 2, 2, 11, 7},
            43 => &.{7, 1, 11, 1, 7, 2, 2, 4, 1, 4, 2, 8},
            44 => &.{4, 11, 5, 4, 10, 11, 2, 9, 7},
            45 => &.{10, 11, 8, 8, 11, 0, 11, 5, 0, 2, 9, 7},
            46 => &.{4, 10, 0, 10, 7, 0, 7, 10, 11, 7, 2, 0},
            47 => &.{10, 11, 8, 8, 11, 2, 11, 7, 2},
            48 => &.{8, 7, 6, 8, 9, 7},
            49 => &.{6, 4, 7, 7, 4, 9, 4, 0, 9},
            50 => &.{7, 6, 5, 6, 8, 5, 5, 8, 0},
            51 => &.{4, 5, 6, 5, 7, 6},
            52 => &.{8, 7, 6, 8, 9, 7, 4, 10, 1},
            53 => &.{0, 7, 10, 0, 10, 1, 10, 7, 6, 0, 9, 7},
            54 => &.{7, 6, 5, 6, 8, 5, 5, 8, 0, 4, 10, 1},
            55 => &.{7, 6, 5, 6, 10, 5, 5, 10, 1},
            56 => &.{8, 7, 6, 8, 9, 7, 1, 11, 5},
            57 => &.{6, 4, 7, 7, 4, 9, 4, 0, 9, 1, 11, 5},
            58 => &.{0, 11, 6, 0, 1, 11, 11, 7, 6, 0, 6, 8},
            59 => &.{6, 4, 7, 7, 4, 11, 4, 1, 11},
            60 => &.{4, 8, 5, 5, 8, 9, 10, 7, 6, 10, 11, 7},
            61 => &.{10, 7, 6, 10, 11, 7, 0, 9, 5},
            62 => &.{10, 7, 6, 10, 11, 7, 0, 4, 8},
            63 => &.{10, 7, 6, 10, 11, 7},
            64 => &.{3, 10, 6},
            65 => &.{3, 10, 6, 0, 8, 4},
            66 => &.{3, 10, 6, 0, 5, 9},
            67 => &.{4, 5, 8, 5, 9, 8, 3, 10, 6},
            68 => &.{4, 3, 1, 4, 6, 3},
            69 => &.{1, 0, 3, 0, 8, 3, 3, 8, 6},
            70 => &.{4, 3, 1, 4, 6, 3, 0, 5, 9},
            71 => &.{5, 9, 1, 9, 6, 1, 6, 9, 8, 6, 3, 1},
            72 => &.{3, 10, 6, 1, 11, 5},
            73 => &.{3, 10, 6, 1, 11, 5, 0, 8, 4},
            74 => &.{0, 11, 9, 0, 1, 11, 3, 10, 6},
            75 => &.{9, 8, 11, 11, 8, 1, 8, 4, 1, 3, 10, 6},
            76 => &.{4, 6, 5, 5, 6, 11, 6, 3, 11},
            77 => &.{5, 3, 11, 3, 5, 0, 0, 6, 3, 6, 0, 8},
            78 => &.{0, 6, 11, 11, 6, 3, 6, 0, 4, 0, 11, 9},
            79 => &.{9, 8, 11, 11, 8, 3, 8, 6, 3},
            80 => &.{8, 2, 3, 8, 3, 10},
            81 => &.{2, 3, 0, 3, 10, 0, 0, 10, 4},
            82 => &.{8, 2, 3, 8, 3, 10, 0, 5, 9},
            83 => &.{2, 10, 5, 2, 3, 10, 10, 4, 5, 2, 5, 9},
            84 => &.{3, 1, 2, 2, 1, 8, 1, 4, 8},
            85 => &.{0, 2, 1, 1, 2, 3},
            86 => &.{3, 1, 2, 2, 1, 8, 1, 4, 8, 0, 5, 9},
            87 => &.{3, 1, 2, 2, 1, 9, 1, 5, 9},
            88 => &.{8, 2, 3, 8, 3, 10, 1, 11, 5},
            89 => &.{2, 3, 0, 3, 10, 0, 0, 10, 4, 1, 11, 5},
            90 => &.{0, 10, 8, 0, 1, 10, 9, 2, 3, 9, 3, 11},
            91 => &.{9, 2, 3, 9, 3, 11, 4, 1, 10},
            92 => &.{2, 11, 4, 2, 3, 11, 11, 5, 4, 2, 4, 8},
            93 => &.{2, 3, 0, 3, 11, 0, 0, 11, 5},
            94 => &.{9, 2, 3, 9, 3, 11, 0, 4, 8},
            95 => &.{9, 2, 3, 9, 3, 11},
            96 => &.{3, 10, 6, 2, 9, 7},
            97 => &.{3, 10, 6, 2, 9, 7, 0, 8, 4},
            98 => &.{0, 5, 7, 0, 7, 2, 3, 10, 6},
            99 => &.{5, 7, 4, 4, 7, 8, 7, 2, 8, 3, 10, 6},
            100 => &.{4, 3, 1, 4, 6, 3, 2, 9, 7},
            101 => &.{1, 0, 3, 0, 8, 3, 3, 8, 6, 2, 9, 7},
            102 => &.{4, 2, 0, 4, 6, 2, 5, 3, 1, 5, 7, 3},
            103 => &.{5, 3, 1, 5, 7, 3, 2, 8, 6},
            104 => &.{3, 10, 6, 2, 9, 7, 1, 11, 5},
            105 => &.{0, 8, 4, 1, 11, 5, 2, 9, 7, 3, 10, 6},
            106 => &.{0, 1, 2, 1, 10, 2, 2, 10, 6, 3, 11, 7},
            107 => &.{3, 11, 7, 2, 8, 6, 4, 1, 10},
            108 => &.{4, 6, 5, 5, 6, 9, 6, 2, 9, 3, 11, 7},
            109 => &.{3, 11, 7, 2, 8, 6, 0, 9, 5},
            110 => &.{4, 2, 0, 4, 6, 2, 3, 11, 7},
            111 => &.{3, 11, 7, 2, 8, 6},
            112 => &.{8, 9, 10, 10, 9, 3, 9, 7, 3},
            113 => &.{4, 3, 10, 3, 4, 0, 0, 7, 3, 7, 0, 9},
            114 => &.{0, 7, 10, 10, 7, 3, 7, 0, 5, 0, 10, 8},
            115 => &.{5, 7, 4, 4, 7, 10, 7, 3, 10},
            116 => &.{4, 8, 1, 8, 7, 1, 7, 8, 9, 7, 3, 1},
            117 => &.{1, 0, 3, 0, 9, 3, 3, 9, 7},
            118 => &.{5, 3, 1, 5, 7, 3, 0, 4, 8},
            119 => &.{5, 3, 1, 5, 7, 3},
            120 => &.{8, 9, 10, 10, 9, 1, 9, 5, 1, 3, 11, 7},
            121 => &.{3, 11, 7, 4, 1, 10, 0, 9, 5},
            122 => &.{0, 10, 8, 0, 1, 10, 3, 11, 7},
            123 => &.{3, 11, 7, 4, 1, 10},
            124 => &.{4, 8, 5, 5, 8, 9, 3, 11, 7},
            125 => &.{3, 11, 7, 0, 9, 5},
            126 => &.{3, 11, 7, 0, 4, 8},
            127 => &.{3, 11, 7},
            128 => &.{3, 7, 11},
            129 => &.{3, 7, 11, 0, 8, 4},
            130 => &.{3, 7, 11, 0, 5, 9},
            131 => &.{4, 5, 8, 5, 9, 8, 3, 7, 11},
            132 => &.{3, 7, 11, 4, 10, 1},
            133 => &.{0, 8, 10, 0, 10, 1, 3, 7, 11},
            134 => &.{3, 7, 11, 4, 10, 1, 0, 5, 9},
            135 => &.{8, 10, 9, 10, 1, 9, 9, 1, 5, 3, 7, 11},
            136 => &.{5, 1, 3, 5, 3, 7},
            137 => &.{5, 1, 3, 5, 3, 7, 0, 8, 4},
            138 => &.{1, 3, 0, 0, 3, 9, 3, 7, 9},
            139 => &.{4, 1, 8, 8, 1, 7, 7, 9, 8, 7, 1, 3},
            140 => &.{5, 4, 7, 4, 10, 7, 7, 10, 3},
            141 => &.{0, 10, 7, 10, 3, 7, 7, 5, 0, 0, 8, 10},
            142 => &.{4, 10, 3, 3, 0, 4, 0, 3, 7, 7, 9, 0},
            143 => &.{8, 10, 9, 10, 3, 9, 9, 3, 7},
            144 => &.{3, 7, 11, 2, 6, 8},
            145 => &.{4, 0, 2, 4, 2, 6, 3, 7, 11},
            146 => &.{3, 7, 11, 2, 6, 8, 0, 5, 9},
            147 => &.{4, 5, 6, 5, 9, 6, 6, 9, 2, 3, 7, 11},
            148 => &.{3, 7, 11, 2, 6, 8, 4, 10, 1},
            149 => &.{0, 2, 1, 1, 2, 10, 2, 6, 10, 3, 7, 11},
            150 => &.{0, 4, 8, 1, 5, 11, 2, 7, 9, 3, 6, 10},
            151 => &.{3, 6, 10, 2, 7, 9, 1, 5, 11},
            152 => &.{5, 1, 3, 5, 3, 7, 2, 6, 8},
            153 => &.{4, 0, 2, 4, 2, 6, 5, 1, 3, 5, 3, 7},
            154 => &.{1, 3, 0, 0, 3, 8, 3, 6, 8, 2, 7, 9},
            155 => &.{4, 1, 3, 4, 3, 6, 2, 7, 9},
            156 => &.{5, 4, 7, 4, 8, 7, 7, 8, 2, 3, 6, 10},
            157 => &.{0, 7, 5, 0, 2, 7, 3, 6, 10},
            158 => &.{3, 6, 10, 2, 7, 9, 0, 4, 8},
            159 => &.{3, 6, 10, 2, 7, 9},
            160 => &.{9, 3, 2, 9, 11, 3},
            161 => &.{9, 3, 2, 9, 11, 3, 0, 8, 4},
            162 => &.{2, 0, 3, 3, 0, 11, 0, 5, 11},
            163 => &.{2, 4, 11, 2, 11, 3, 11, 4, 5, 2, 8, 4},
            164 => &.{9, 3, 2, 9, 11, 3, 4, 10, 1},
            165 => &.{0, 8, 10, 0, 10, 1, 9, 3, 2, 9, 11, 3},
            166 => &.{2, 0, 3, 3, 0, 10, 0, 4, 10, 1, 5, 11},
            167 => &.{8, 3, 2, 8, 10, 3, 1, 5, 11},
            168 => &.{3, 2, 1, 2, 9, 1, 1, 9, 5},
            169 => &.{3, 2, 1, 2, 8, 1, 1, 8, 4, 0, 9, 5},
            170 => &.{0, 1, 2, 1, 3, 2},
            171 => &.{3, 2, 1, 2, 8, 1, 1, 8, 4},
            172 => &.{2, 5, 10, 2, 10, 3, 10, 5, 4, 2, 9, 5},
            173 => &.{8, 3, 2, 8, 10, 3, 0, 9, 5},
            174 => &.{2, 0, 3, 3, 0, 10, 0, 4, 10},
            175 => &.{8, 3, 2, 8, 10, 3},
            176 => &.{9, 11, 8, 11, 3, 8, 8, 3, 6},
            177 => &.{0, 11, 6, 11, 3, 6, 6, 4, 0, 0, 9, 11},
            178 => &.{5, 11, 3, 3, 0, 5, 0, 3, 6, 6, 8, 0},
            179 => &.{4, 5, 6, 5, 11, 6, 6, 11, 3},
            180 => &.{9, 11, 8, 11, 1, 8, 8, 1, 4, 3, 6, 10},
            181 => &.{0, 9, 11, 0, 11, 1, 3, 6, 10},
            182 => &.{3, 6, 10, 1, 5, 11, 0, 4, 8},
            183 => &.{3, 6, 10, 1, 5, 11},
            184 => &.{5, 1, 9, 9, 1, 6, 6, 8, 9, 6, 1, 3},
            185 => &.{4, 1, 3, 4, 3, 6, 0, 9, 5},
            186 => &.{1, 3, 0, 0, 3, 8, 3, 6, 8},
            187 => &.{4, 1, 3, 4, 3, 6},
            188 => &.{4, 8, 5, 5, 8, 9, 3, 6, 10},
            189 => &.{3, 6, 10, 0, 9, 5},
            190 => &.{3, 6, 10, 0, 4, 8},
            191 => &.{3, 6, 10},
            192 => &.{10, 6, 7, 10, 7, 11},
            193 => &.{10, 6, 7, 10, 7, 11, 0, 8, 4},
            194 => &.{10, 6, 7, 10, 7, 11, 0, 5, 9},
            195 => &.{4, 5, 8, 5, 9, 8, 10, 6, 7, 10, 7, 11},
            196 => &.{6, 7, 4, 7, 11, 4, 4, 11, 1},
            197 => &.{0, 6, 11, 0, 11, 1, 11, 6, 7, 0, 8, 6},
            198 => &.{6, 7, 4, 7, 9, 4, 4, 9, 0, 1, 5, 11},
            199 => &.{8, 6, 7, 8, 7, 9, 1, 5, 11},
            200 => &.{7, 5, 6, 6, 5, 10, 5, 1, 10},
            201 => &.{7, 5, 6, 6, 5, 8, 5, 0, 8, 4, 1, 10},
            202 => &.{0, 10, 7, 0, 1, 10, 10, 6, 7, 0, 7, 9},
            203 => &.{8, 6, 7, 8, 7, 9, 4, 1, 10},
            204 => &.{4, 6, 5, 5, 6, 7},
            205 => &.{7, 5, 6, 6, 5, 8, 5, 0, 8},
            206 => &.{6, 7, 4, 7, 9, 4, 4, 9, 0},
            207 => &.{8, 6, 7, 8, 7, 9},
            208 => &.{10, 8, 11, 8, 2, 11, 11, 2, 7},
            209 => &.{4, 0, 10, 10, 0, 7, 7, 11, 10, 7, 0, 2},
            210 => &.{10, 8, 11, 8, 0, 11, 11, 0, 5, 2, 7, 9},
            211 => &.{4, 5, 11, 4, 11, 10, 2, 7, 9},
            212 => &.{7, 11, 1, 1, 2, 7, 2, 1, 4, 4, 8, 2},
            213 => &.{0, 2, 1, 1, 2, 11, 2, 7, 11},
            214 => &.{2, 7, 9, 1, 5, 11, 0, 4, 8},
            215 => &.{2, 7, 9, 1, 5, 11},
            216 => &.{2, 5, 10, 10, 5, 1, 5, 2, 7, 2, 10, 8},
            217 => &.{0, 7, 5, 0, 2, 7, 4, 1, 10},
            218 => &.{0, 10, 8, 0, 1, 10, 2, 7, 9},
            219 => &.{2, 7, 9, 4, 1, 10},
            220 => &.{5, 4, 7, 4, 8, 7, 7, 8, 2},
            221 => &.{0, 7, 5, 0, 2, 7},
            222 => &.{0, 4, 8, 2, 7, 9},
            223 => &.{2, 7, 9},
            224 => &.{11, 10, 9, 9, 10, 2, 10, 6, 2},
            225 => &.{11, 10, 9, 9, 10, 0, 10, 4, 0, 2, 8, 6},
            226 => &.{5, 11, 0, 11, 6, 0, 6, 11, 10, 6, 2, 0},
            227 => &.{4, 5, 11, 4, 11, 10, 2, 8, 6},
            228 => &.{2, 11, 4, 11, 1, 4, 4, 6, 2, 2, 9, 11},
            229 => &.{0, 9, 11, 0, 11, 1, 2, 8, 6},
            230 => &.{4, 2, 0, 4, 6, 2, 1, 5, 11},
            231 => &.{2, 8, 6, 1, 5, 11},
            232 => &.{6, 1, 10, 1, 6, 2, 2, 5, 1, 5, 2, 9},
            233 => &.{0, 9, 5, 4, 1, 10, 2, 8, 6},
            234 => &.{0, 1, 2, 1, 10, 2, 2, 10, 6},
            235 => &.{2, 8, 6, 4, 1, 10},
            236 => &.{4, 6, 5, 5, 6, 9, 6, 2, 9},
            237 => &.{2, 8, 6, 0, 9, 5},
            238 => &.{4, 2, 0, 4, 6, 2},
            239 => &.{2, 8, 6},
            240 => &.{8, 9, 10, 9, 11, 10},
            241 => &.{11, 10, 9, 9, 10, 0, 10, 4, 0},
            242 => &.{10, 8, 11, 8, 0, 11, 11, 0, 5},
            243 => &.{4, 5, 11, 4, 11, 10},
            244 => &.{9, 11, 8, 11, 1, 8, 8, 1, 4},
            245 => &.{0, 9, 11, 0, 11, 1},
            246 => &.{0, 4, 8, 1, 5, 11},
            247 => &.{1, 5, 11},
            248 => &.{8, 9, 10, 10, 9, 1, 9, 5, 1},
            249 => &.{0, 9, 5, 4, 1, 10},
            250 => &.{0, 10, 8, 0, 1, 10},
            251 => &.{4, 1, 10},
            252 => &.{4, 8, 5, 5, 8, 9},
            253 => &.{0, 9, 5},
            254 => &.{0, 4, 8},
        };

        if(indices.len > 0)
        {
            const mesh_vertices = try mesh.add_vertices(indices.len);

            for(0..indices.len) |i|
            {
                const vertex = vertices[indices[i]];
                if(callback == null)
                {
                    try default_vertex_addition(cell, mesh_vertices.ptr + i, vertex);
                }
                else
                {
                    try callback(cell, mesh_vertices.ptr + i, vertex);
                }
            }
        }

        try mesh.finalize_vertices();
    }
};

/// This structure is essentially just a namespace that houses the marching tetrahedra polygonization algorithm.
pub const MarchingTetrahedra = struct
{
    fn add_tetra(mesh: *ash.Mesh, cell: SDFCell, callback: ?PolygonizeCallback, positions: [4][3]f32, values: [4]f32) !void
    {
        var code: u4 = 0;

        for(0..4) |i|
        {
            const bit: u4 = if(values[i] > 0) 1 else 0;
            code |= (bit << @as(u2, @truncate(i)));
        }

        const v_ab = midpoint_linear(values[0], values[1], 0);
        const v_ac = midpoint_linear(values[0], values[2], 0);
        const v_ad = midpoint_linear(values[0], values[3], 0);

        const v_bc = midpoint_linear(values[1], values[2], 0);
        const v_bd = midpoint_linear(values[1], values[3], 0);
        const v_cd = midpoint_linear(values[2], values[3], 0);

        const a_x = positions[0][0];
        const a_y = positions[0][1];
        const a_z = positions[0][2];

        const b_x = positions[1][0];
        const b_y = positions[1][1];
        const b_z = positions[1][2];

        const c_x = positions[2][0];
        const c_y = positions[2][1];
        const c_z = positions[2][2];

        const d_x = positions[3][0];
        const d_y = positions[3][1];
        const d_z = positions[3][2];

        const vertices: [6][3]f32 = .{
            .{a_x + (b_x - a_x) * v_ab, a_y + (b_y - a_y) * v_ab, a_z + (b_z - a_z) * v_ab}, // AB
            .{a_x + (c_x - a_x) * v_ac, a_y + (c_y - a_y) * v_ac, a_z + (c_z - a_z) * v_ac}, // AC
            .{a_x + (d_x - a_x) * v_ad, a_y + (d_y - a_y) * v_ad, a_z + (d_z - a_z) * v_ad}, // AD
            .{b_x + (c_x - b_x) * v_bc, b_y + (c_y - b_y) * v_bc, b_z + (c_z - b_z) * v_bc}, // BC
            .{b_x + (d_x - b_x) * v_bd, b_y + (d_y - b_y) * v_bd, b_z + (d_z - b_z) * v_bd}, // BD
            .{c_x + (d_x - c_x) * v_cd, c_y + (d_y - c_y) * v_cd, c_z + (d_z - c_z) * v_cd}  // CD
        };

        const indices: []const u4 = switch(code)
        {
            0, 15 => &.{},
            1 => &.{0, 2, 1},
            2 => &.{0, 3, 4},
            3 => &.{1, 3, 4, 1, 4, 2},
            4 => &.{1, 5, 3},
            5 => &.{0, 2, 3, 2, 5, 3},
            6 => &.{0, 1, 4, 1, 5, 4},
            7 => &.{2, 5, 4},
            8 => &.{2, 4, 5},
            9 => &.{0, 4, 1, 1, 4, 5},
            10 => &.{0, 3, 2, 2, 3, 5},
            11 => &.{1, 3, 5},
            12 => &.{1, 4, 3, 1, 2, 4},
            13 => &.{0, 4, 3},
            14 => &.{0, 1, 2},
        };

        if(indices.len > 0)
        {
            const mesh_vertices = try mesh.add_vertices(indices.len);

            for(0..indices.len) |i|
            {
                const vertex = vertices[indices[i]];
                if(callback == null)
                {
                    try default_vertex_addition(cell, mesh_vertices.ptr + i, vertex);
                }
                else
                {
                    try callback(cell, mesh_vertices.ptr + i, vertex);
                }
            }
        }

        try mesh.finalize_vertices();
    }

    pub fn add_cell_to_mesh(mesh: *ash.Mesh, cell: SDFCell, callback: ?PolygonizeCallback) !void
    {
        const vertices: [8][3]f32 = .{
            .{cell.pos[0], cell.pos[1], cell.pos[2]},
            .{cell.pos[0] + cell.scl[0], cell.pos[1], cell.pos[2]},
            .{cell.pos[0], cell.pos[1] + cell.scl[1], cell.pos[2]},
            .{cell.pos[0] + cell.scl[0], cell.pos[1] + cell.scl[1], cell.pos[2]},
            .{cell.pos[0], cell.pos[1], cell.pos[2] + cell.scl[2]},
            .{cell.pos[0] + cell.scl[0], cell.pos[1], cell.pos[2] + cell.scl[2]},
            .{cell.pos[0], cell.pos[1] + cell.scl[1], cell.pos[2] + cell.scl[2]},
            .{cell.pos[0] + cell.scl[0], cell.pos[1] + cell.scl[1], cell.pos[2] + cell.scl[2]},
        };

        try add_tetra(mesh, cell, callback, .{vertices[0], vertices[1], vertices[3], vertices[4]}, .{cell.values[0], cell.values[1], cell.values[3], cell.values[4]});
        try add_tetra(mesh, cell, callback, .{vertices[1], vertices[3], vertices[4], vertices[5]}, .{cell.values[1], cell.values[3], cell.values[4], cell.values[5]});
        try add_tetra(mesh, cell, callback, .{vertices[3], vertices[4], vertices[5], vertices[7]}, .{cell.values[3], cell.values[4], cell.values[5], cell.values[7]});

        try add_tetra(mesh, cell, callback, .{vertices[2], vertices[3], vertices[4], vertices[0]}, .{cell.values[2], cell.values[3], cell.values[4], cell.values[0]});
        try add_tetra(mesh, cell, callback, .{vertices[3], vertices[4], vertices[6], vertices[2]}, .{cell.values[3], cell.values[4], cell.values[6], cell.values[2]});
        try add_tetra(mesh, cell, callback, .{vertices[4], vertices[6], vertices[7], vertices[3]}, .{cell.values[4], cell.values[6], cell.values[7], cell.values[3]});
    }
};

pub const SurfaceNets = struct
{
    const NetCell = packed struct(u6)
    {
        x: bool,
        y: bool,
        z: bool,
        dir_x: bool,
        dir_y: bool,
        dir_z: bool
    };

    fn cell_collides_with_isosurface(cell: SDFCell) bool
    {
        const initial_value = cell.values[0] >= 0;

        for(1..8) |i|
        {
            if(initial_value != (cell.values[i] >= 0)) return true;
        }

        return false;
    }

    fn get_cell_surface_point(cell: SDFCell) [3]f32
    {
        const aaa = cell.values[0] >= 0;
        const baa = cell.values[1] >= 0;
        const aba = cell.values[2] >= 0;
        const bba = cell.values[3] >= 0;
        const aab = cell.values[4] >= 0;
        const bab = cell.values[5] >= 0;
        const abb = cell.values[6] >= 0;
        const bbb = cell.values[7] >= 0;

        var edge_points: [12][3]f32 = undefined;
        var num_points: u4 = 0;

        // X-edges.
        if(aaa != baa)
        {
            const midpoint = midpoint_linear(cell.values[0], cell.values[1], 0);
            edge_points[num_points] = .{cell.pos[0] + cell.scl[0] * midpoint, cell.pos[1], cell.pos[2]};

            num_points += 1;
        }
        if(aba != bba)
        {
            const midpoint = midpoint_linear(cell.values[2], cell.values[3], 0);
            edge_points[num_points] = .{cell.pos[0] + cell.scl[0] * midpoint, cell.pos[1] + cell.scl[1], cell.pos[2]};

            num_points += 1;
        }
        if(aab != bab)
        {
            const midpoint = midpoint_linear(cell.values[4], cell.values[5], 0);
            edge_points[num_points] = .{cell.pos[0] + cell.scl[0] * midpoint, cell.pos[1], cell.pos[2] + cell.scl[2]};

            num_points += 1;
        }
        if(abb != bbb)
        {
            const midpoint = midpoint_linear(cell.values[6], cell.values[7], 0);
            edge_points[num_points] = .{cell.pos[0] + cell.scl[0] * midpoint, cell.pos[1] + cell.scl[1], cell.pos[2] + cell.scl[2]};

            num_points += 1;
        }

        // Y-edges.
        if(aaa != aba)
        {
            const midpoint = midpoint_linear(cell.values[0], cell.values[2], 0);
            edge_points[num_points] = .{cell.pos[0], cell.pos[1] + cell.scl[1] * midpoint, cell.pos[2]};

            num_points += 1;
        }
        if(baa != bba)
        {
            const midpoint = midpoint_linear(cell.values[1], cell.values[3], 0);
            edge_points[num_points] = .{cell.pos[0] + cell.scl[0], cell.pos[1] + cell.scl[1] * midpoint, cell.pos[2]};

            num_points += 1;
        }
        if(aab != abb)
        {
            const midpoint = midpoint_linear(cell.values[4], cell.values[6], 0);
            edge_points[num_points] = .{cell.pos[0], cell.pos[1] + cell.scl[1] * midpoint, cell.pos[2] + cell.scl[2]};

            num_points += 1;
        }
        if(bab != bbb)
        {
            const midpoint = midpoint_linear(cell.values[5], cell.values[7], 0);
            edge_points[num_points] = .{cell.pos[0] + cell.scl[0], cell.pos[1] + cell.scl[1] * midpoint, cell.pos[2] + cell.scl[2]};

            num_points += 1;
        }

        // Z-edges.
        if(aaa != aab)
        {
            const midpoint = midpoint_linear(cell.values[0], cell.values[4], 0);
            edge_points[num_points] = .{cell.pos[0], cell.pos[1], cell.pos[2] + cell.scl[2] * midpoint};

            num_points += 1;
        }
        if(baa != bab)
        {
            const midpoint = midpoint_linear(cell.values[1], cell.values[5], 0);
            edge_points[num_points] = .{cell.pos[0] + cell.scl[0], cell.pos[1], cell.pos[2] + cell.scl[2] * midpoint};

            num_points += 1;
        }
        if(aba != abb)
        {
            const midpoint = midpoint_linear(cell.values[2], cell.values[6], 0);
            edge_points[num_points] = .{cell.pos[0], cell.pos[1] + cell.scl[1], cell.pos[2] + cell.scl[2] * midpoint};

            num_points += 1;
        }
        if(bba != bbb)
        {
            const midpoint = midpoint_linear(cell.values[3], cell.values[7], 0);
            edge_points[num_points] = .{cell.pos[0] + cell.scl[0], cell.pos[1] + cell.scl[1], cell.pos[2] + cell.scl[2] * midpoint};

            num_points += 1;
        }

        var sum_points: [3]f32 = .{0, 0, 0};

        for(0..num_points) |i|
        {
            sum_points[0] += edge_points[i][0];
            sum_points[1] += edge_points[i][1];
            sum_points[2] += edge_points[i][2];
        }

        for(0..3) |i|
        {
            sum_points[i] /= num_points;
        }

        return sum_points;
    }

    pub fn build(mesh: *ash.Mesh, cells: [][][]SDFCell, callback: ?PolygonizeCallback) !void
    {
        const net_cells = try mesh.allocator.alloc([][]NetCell, cells.len - 1);
        for(0..net_cells.len) |i|
        {
            net_cells[i] = try mesh.allocator.alloc([]NetCell, cells[0].len - 1);
            for(0..net_cells[0].len) |j|
            {
                net_cells[i][j] = try mesh.allocator.alloc(NetCell, cells[0][0].len - 1);
            }
        }

        defer
        {
            for(0..net_cells.len) |i|
            {
                for(0..net_cells[0].len) |j|
                {
                    mesh.allocator.free(net_cells[i][j]);
                }
                mesh.allocator.free(net_cells[i]);
            }
            mesh.allocator.free(net_cells);
        }

        for(0..net_cells.len)       |i| {
        for(0..net_cells[0].len)    |j| {
        for(0..net_cells[0][0].len) |k|
        {
            net_cells[i][j][k].x = false;
            net_cells[i][j][k].y = false;
            net_cells[i][j][k].z = false;
            net_cells[i][j][k].dir_x = false;
            net_cells[i][j][k].dir_y = false;
            net_cells[i][j][k].dir_z = false;

            if(cell_collides_with_isosurface(cells[i][j][k]))
            {
                const right = cell_collides_with_isosurface(cells[i + 1][j][k]);
                const up = cell_collides_with_isosurface(cells[i][j + 1][k]);
                const forward = cell_collides_with_isosurface(cells[i][j][k + 1]);

                // Checking the X-direction.
                if(forward and up and cell_collides_with_isosurface(cells[i][j + 1][k + 1]))
                {
                    net_cells[i][j][k].x = true;

                    var sum_1: u4 = 0;
                    var sum_2: u4 = 0;

                    sum_1 += if(cells[i][j][k].values[0] >= 0) 1 else 0;
                    sum_1 += if(cells[i][j][k].values[2] >= 0) 1 else 0;
                    sum_1 += if(cells[i][j][k].values[4] >= 0) 1 else 0;
                    sum_1 += if(cells[i][j][k].values[6] >= 0) 1 else 0;
                    sum_1 += if(cells[i][j + 1][k].values[2] >= 0) 1 else 0;
                    sum_1 += if(cells[i][j + 1][k].values[6] >= 0) 1 else 0;
                    sum_1 += if(cells[i][j][k + 1].values[4] >= 0) 1 else 0;
                    sum_1 += if(cells[i][j][k + 1].values[6] >= 0) 1 else 0;
                    sum_1 += if(cells[i][j + 1][k + 1].values[6] >= 0) 1 else 0;

                    sum_2 += if(cells[i][j][k].values[1] >= 0) 1 else 0;
                    sum_2 += if(cells[i][j][k].values[3] >= 0) 1 else 0;
                    sum_2 += if(cells[i][j][k].values[5] >= 0) 1 else 0;
                    sum_2 += if(cells[i][j][k].values[7] >= 0) 1 else 0;
                    sum_2 += if(cells[i][j + 1][k].values[3] >= 0) 1 else 0;
                    sum_2 += if(cells[i][j + 1][k].values[7] >= 0) 1 else 0;
                    sum_2 += if(cells[i][j][k + 1].values[5] >= 0) 1 else 0;
                    sum_2 += if(cells[i][j][k + 1].values[7] >= 0) 1 else 0;
                    sum_2 += if(cells[i][j + 1][k + 1].values[7] >= 0) 1 else 0;

                    if(sum_1 > sum_2)
                    {
                        net_cells[i][j][k].dir_x = true;
                    }
                }
                // Checking the Y-direction.
                if(right and forward and cell_collides_with_isosurface(cells[i + 1][j][k + 1]))
                {
                    net_cells[i][j][k].y = true;

                    var sum_1: u4 = 0;
                    var sum_2: u4 = 0;

                    sum_1 += if(cells[i][j][k].values[0] >= 0) 1 else 0;
                    sum_1 += if(cells[i][j][k].values[1] >= 0) 1 else 0;
                    sum_1 += if(cells[i][j][k].values[4] >= 0) 1 else 0;
                    sum_1 += if(cells[i][j][k].values[5] >= 0) 1 else 0;
                    sum_1 += if(cells[i + 1][j][k].values[1] >= 0) 1 else 0;
                    sum_1 += if(cells[i + 1][j][k].values[5] >= 0) 1 else 0;
                    sum_1 += if(cells[i][j][k + 1].values[4] >= 0) 1 else 0;
                    sum_1 += if(cells[i][j][k + 1].values[5] >= 0) 1 else 0;
                    sum_1 += if(cells[i + 1][j][k + 1].values[5] >= 0) 1 else 0;

                    sum_2 += if(cells[i][j][k].values[2] >= 0) 1 else 0;
                    sum_2 += if(cells[i][j][k].values[3] >= 0) 1 else 0;
                    sum_2 += if(cells[i][j][k].values[6] >= 0) 1 else 0;
                    sum_2 += if(cells[i][j][k].values[7] >= 0) 1 else 0;
                    sum_2 += if(cells[i + 1][j][k].values[3] >= 0) 1 else 0;
                    sum_2 += if(cells[i + 1][j][k].values[7] >= 0) 1 else 0;
                    sum_2 += if(cells[i][j][k + 1].values[6] >= 0) 1 else 0;
                    sum_2 += if(cells[i][j][k + 1].values[7] >= 0) 1 else 0;
                    sum_2 += if(cells[i + 1][j][k + 1].values[7] >= 0) 1 else 0;

                    if(sum_1 > sum_2)
                    {
                        net_cells[i][j][k].dir_y = true;
                    }
                }
                // Checking the Z-direction.
                if(right and up and cell_collides_with_isosurface(cells[i + 1][j + 1][k]))
                {
                    net_cells[i][j][k].z = true;

                    var sum_1: u4 = 0;
                    var sum_2: u4 = 0;

                    sum_1 += if(cells[i][j][k].values[0] >= 0) 1 else 0;
                    sum_1 += if(cells[i][j][k].values[1] >= 0) 1 else 0;
                    sum_1 += if(cells[i][j][k].values[2] >= 0) 1 else 0;
                    sum_1 += if(cells[i][j][k].values[3] >= 0) 1 else 0;
                    sum_1 += if(cells[i + 1][j][k].values[1] >= 0) 1 else 0;
                    sum_1 += if(cells[i + 1][j][k].values[3] >= 0) 1 else 0;
                    sum_1 += if(cells[i][j + 1][k].values[2] >= 0) 1 else 0;
                    sum_1 += if(cells[i][j + 1][k].values[3] >= 0) 1 else 0;
                    sum_1 += if(cells[i + 1][j + 1][k].values[3] >= 0) 1 else 0;

                    sum_2 += if(cells[i][j][k].values[4] >= 0) 1 else 0;
                    sum_2 += if(cells[i][j][k].values[5] >= 0) 1 else 0;
                    sum_2 += if(cells[i][j][k].values[6] >= 0) 1 else 0;
                    sum_2 += if(cells[i][j][k].values[7] >= 0) 1 else 0;
                    sum_2 += if(cells[i + 1][j][k].values[5] >= 0) 1 else 0;
                    sum_2 += if(cells[i + 1][j][k].values[7] >= 0) 1 else 0;
                    sum_2 += if(cells[i][j + 1][k].values[6] >= 0) 1 else 0;
                    sum_2 += if(cells[i][j + 1][k].values[7] >= 0) 1 else 0;
                    sum_2 += if(cells[i + 1][j + 1][k].values[7] >= 0) 1 else 0;

                    if(sum_1 > sum_2)
                    {
                        net_cells[i][j][k].dir_z = true;
                    }
                }
            }
        }}}

        const cb = callback orelse default_vertex_addition;
        
        for(0..net_cells.len)       |i| {
        for(0..net_cells[0].len)    |j| {
        for(0..net_cells[0][0].len) |k|
        {
            const cell = net_cells[i][j][k];

            const v1: [3]f32 = get_cell_surface_point(cells[i][j][k]);
            const v2: [3]f32 = get_cell_surface_point(cells[i + 1][j][k]);
            const v3: [3]f32 = get_cell_surface_point(cells[i][j + 1][k]);
            const v5: [3]f32 = get_cell_surface_point(cells[i][j][k + 1]);

            if(cell.x)
            {
                const v7: [3]f32 = get_cell_surface_point(cells[i][j + 1][k + 1]);
                const vertices = try mesh.add_vertices(6);

                if(cell.dir_x)
                {
                    try cb(cell, vertices.ptr, v1);
                    try cb(cell, vertices.ptr + 1, v7);
                    try cb(cell, vertices.ptr + 2, v3);
                    try cb(cell, vertices.ptr + 3, v1);
                    try cb(cell, vertices.ptr + 4, v5);
                    try cb(cell, vertices.ptr + 5, v7);
                }
                else
                {
                    try cb(cell, vertices.ptr, v1);
                    try cb(cell, vertices.ptr + 1, v3);
                    try cb(cell, vertices.ptr + 2, v7);
                    try cb(cell, vertices.ptr + 3, v1);
                    try cb(cell, vertices.ptr + 4, v7);
                    try cb(cell, vertices.ptr + 5, v5);
                }

                try mesh.finalize_vertices();
            }
            if(cell.y)
            {
                const v6: [3]f32 = get_cell_surface_point(cells[i + 1][j][k + 1]);
                const vertices = try mesh.add_vertices(6);

                if(cell.dir_y)
                {
                    try cb(cell, vertices.ptr, v1);
                    try cb(cell, vertices.ptr + 1, v2);
                    try cb(cell, vertices.ptr + 2, v6);
                    try cb(cell, vertices.ptr + 3, v1);
                    try cb(cell, vertices.ptr + 4, v6);
                    try cb(cell, vertices.ptr + 5, v5);
                }
                else
                {
                    try cb(cell, vertices.ptr, v1);
                    try cb(cell, vertices.ptr + 1, v6);
                    try cb(cell, vertices.ptr + 2, v2);
                    try cb(cell, vertices.ptr + 3, v1);
                    try cb(cell, vertices.ptr + 4, v5);
                    try cb(cell, vertices.ptr + 5, v6);
                }

                try mesh.finalize_vertices();
            }
            if(cell.z)
            {
                const v4: [3]f32 = get_cell_surface_point(cells[i + 1][j + 1][k]);
                const vertices = try mesh.add_vertices(6);

                if(cell.dir_z)
                {
                    try cb(cell, vertices.ptr, v1);
                    try cb(cell, vertices.ptr + 1, v3);
                    try cb(cell, vertices.ptr + 2, v4);
                    try cb(cell, vertices.ptr + 3, v1);
                    try cb(cell, vertices.ptr + 4, v4);
                    try cb(cell, vertices.ptr + 5, v2);
                }
                else
                {
                    try cb(cell, vertices.ptr, v1);
                    try cb(cell, vertices.ptr + 1, v4);
                    try cb(cell, vertices.ptr + 2, v3);
                    try cb(cell, vertices.ptr + 3, v1);
                    try cb(cell, vertices.ptr + 4, v2);
                    try cb(cell, vertices.ptr + 5, v4);
                }

                try mesh.finalize_vertices();
            }
        }}}
    }
};
