const std = @import("std");

pub const MathError = error
{
    MatrixOrderMismatch,
    OutOfRange
};

/// Checks if a type represents a discrete or continuous numeral value. Does not consider bools to be numbers.
/// A type is considered usable with a Vec or Mat with this function.
pub fn type_is_number(comptime T: type) bool
{
    const info = @typeInfo(T);
    return info == .int or info == .float or info == .comptime_int or info == .comptime_float;
}

/// Checks if two types are capable of performing addition operations on one another.
pub fn types_can_add(comptime T_a: type, comptime T_b: type) bool
{
    if(!type_is_number(T_a) or !type_is_number(T_b)) return false;

    return true;
}

/// Returns a Vec type, with a length len and type T.
pub fn Vec(comptime T: type, comptime len: u32) type
{
    if(!type_is_number(T))
    {
        @compileError("Attempt to define Vec using unsupported type T [" ++ @typeName(T) ++ "].\n");
    }
    if(len == 0)
    {
        @compileError("Length of Vec objects must be at least 1.");
    }

    return struct
    {
        /// Compile-time array of elements, of length 'len'.
        data: [len]T,
        const Self = @This();

        /// Adds the elements of another Vec of the same type & length to this vector.
        pub fn add(self: *Self, other: Self) void
        {
            for(self.data, 0..) |_, i|
            {
                self.data[i] += other.data[i];
            }
        }

        /// Subtracts the elements of another Vec of the same type & length from this vector.
        pub fn sub(self: *Self, other: Self) void
        {
            for(self.data, 0..) |_, i|
            {
                self.data[i] -= other.data[i];
            }
        }

        /// Multiplies the vector by a scalar value.
        pub fn mul(self: *Self, factor: T) void
        {
            for(self.data, 0..) |_, i|
            {
                self.data[i] *= factor;
            }
        }

        /// Multiplies the elements of another Vec of the same type & length to this vector.
        pub fn mul_elements(self: *Self, other: Self) void
        {
            for(self.data, 0..) |_, i|
            {
                self.data[i] *= other.data[i];
            }
        }

        /// Divides the vector by a scalar value.
        pub fn div(self: *Self, factor: T) void
        {
            for(self.data, 0..) |_, i|
            {
                self.data[i] /= factor;
            }
        }

        /// Divides the elements of another Vec of the same type & length from this vector.
        pub fn div_elements(self: *Self, other: Self) void
        {
            for(self.data, 0..) |_, i|
            {
                self.data[i] /= other.data[i];
            }
        }

        /// Muliplies the vector by -1.
        pub fn negate(self: *Self) void
        {
            const factor: T = -1;
            self.mul(factor);
        }

        /// Initialize all members of the vector.
        pub fn init(data: [len]T) Self
        {
            return Self{
                .data = data
            };
        }

        /// Initializes all members of this vector to undefined.
        pub fn init_undefined() Self
        {
            return Self{
                .data = undefined
            };
        }

        /// Prints all members of the vector.
        pub fn print(self: Self) void
        {
            std.debug.print("(", .{});
            for(self.data, 0..) |_, i|
            {
                std.debug.print("{d}", .{self.data[i]});
                if(i < self.data.len - 1) std.debug.print(", ", .{});
            }
            std.debug.print(")\n", .{});
        }
    };
}

pub fn dot(comptime vec_size: u32, comptime vec_type: type, a: Vec(vec_type, vec_size), b: Vec(vec_type, vec_size)) vec_type
{
    var dot_product: vec_type = 0;
    for(0..vec_size) |i|
    {
        dot_product += a.data[i] * b.data[i];
    }
    return dot_product;
}

pub fn cross(comptime vec_type: type, a: Vec(vec_type, 3), b: Vec(vec_type, 3)) Vec(vec_type, 3)
{
    var vec: Vec(vec_type, 3) = .init_undefined();

    vec.data[0] = a.data[1] * b.data[2] - a.data[2] * b.data[1];
    vec.data[1] = a.data[2] * b.data[0] - a.data[0] * b.data[2];
    vec.data[2] = a.data[0] * b.data[1] - a.data[1] * b.data[0];

    return vec;
}

/// Returns a Matrix type, of type T, and with data of order columns x rows.
pub fn Mat(comptime T: type) type
{
    if(!type_is_number(T))
    {
        @compileError("Attempt to define Mat using unsupported type T [" ++ @typeName(T) ++ "].\n");
    }

    return struct
    {
        /// Allocator handle.
        allocator: *const std.mem.Allocator,
        /// Compile-time 2D array of values held by the matrix.
        data: [][]T,

        /// Type of this Mat.
        const Self = @This();

        /// Verifies that two matrices have the same order.
        fn verify_matrices_same_order(self: Self, other: Self) MathError!void
        {
            if(self.data.len != other.data.len or self.data[0].len != other.data[0].len)
            {
                return MathError.MatrixOrderMismatch;
            }
        }

        /// Adds a matrix to this one. The two matrices must have the same order.
        pub fn add(self: *Self, other: Self) MathError!void
        {
            try self.verify_matrices_same_order(other);

            for(0..self.data.len) |i|
            {
                for(0..self.data[0].len) |j|
                {
                    self.data[i][j] += other.data[i][j];
                }
            }
        }

        /// Deinitializes the matrix and frees all associated memory.
        pub fn deinit(self: *Self) void
        {
            for(0..self.data.len) |i|
            {
                self.allocator.free(self.data[i]);
            }

            self.allocator.free(self.data);
        }

        /// Places values from one matrix directly onto another matrix.
        pub fn emplace_values(self: *Self, other: Self, column_offset: usize, row_offset: usize) !void
        {
            if(other.data.len + column_offset >= self.data.len or other.data[0].len + row_offset >= self.data[0].len)
            {
                return MathError.OutOfRange;
            }

            for(0..other.data.len) |i|
            {
                for(0..other.data[0].len) |j|
                {
                    self.set(@truncate(i + column_offset), @truncate(j + row_offset), other.data[i][j]);
                }
            }
        }

        /// Gets the value of a matrix element.
        pub fn get(self: Self, column: u32, row: u32) T
        {
            std.debug.assert(column < self.data.len);
            std.debug.assert(row < self.data[0].len);

            return self.data.items[column].data[row];
        }

        /// Initializes a matrix object.
        pub fn init(allocator: *const std.mem.Allocator, columns: usize, rows: usize) !Self
        {
            var matrix: Self = .{
                .allocator = allocator,
                .data = try allocator.alloc([]T, columns)
            };

            for(0..columns) |i|
            {
                matrix.data[i] = try allocator.alloc(T, rows);
                for(0..rows) |j|
                {
                    const val: T = if(i == j) 1 else 0;
                    matrix.data[i][j] = val;
                }
            }

            return matrix;
        }

        /// Prints the values of a matrix object.
        pub fn print(self: Self) void
        {
            std.debug.print("[\n", .{});
            for(0..self.data[0].len) |i|
            {
                std.debug.print("\t(", .{});
                for(0..self.data.len) |j|
                {
                    std.debug.print("{d}", .{self.data[j][i]});
                    if(j < self.data.len - 1) std.debug.print(", ", .{});
                }
                std.debug.print(")\n", .{});
            }
            std.debug.print("]\n", .{});
        }

        /// Multiplies each element in the matrix by a scalar value.
        pub fn mul(self: *Self, value: T) void
        {
            for(self.data.items, 0..) |_, i|
            {
                for(self.data.items[0].data, 0..) |_, j|
                {
                    self.data.items[i].data[j] *= value;
                }
            }
        }

        /// Sets the value of a matrix element.
        pub fn set(self: *Self, column: u32, row: u32, value: T) void
        {
            std.debug.assert(column < self.data.len);
            std.debug.assert(row < self.data[0].len);

            self.data[column][row] = value;
        }

        /// Subtracts a matrix from this one. The two matrices must have the same order.
        pub fn sub(self: *Self, other: Self) MathError!void
        {
            try self.verify_matrices_same_type_order(other);

            for(self.data.items, 0..) |_, i|
            {
                for(self.data.items[0].data, 0..) |_, j|
                {
                    self.data.items[i].data[j] -= other.data.items[i].data[j];
                }
            }
        }
    };
}

/// Multiplies two matrices of compatible orders, returning a new matrix.
pub fn multiply_matrices(comptime T: type, a: Mat(T), b: Mat(T)) !Mat(T)
{
    if(a.data.len != b.data[0].len)
    {
        return MathError.MatrixOrderMismatch;
    }

    const nm_sum_elements = a.data.len;

    const nm_columns = b.data.len;
    const nm_rows = a.data[0].len;

    var matrix = try Mat(T).init(a.allocator, nm_columns, nm_rows);

    for(0..nm_columns) |i|
    {
        for(0..nm_rows) |j|
        {
            var sum: T = 0;
            for(0..nm_sum_elements) |k|
            {
                sum += a.data[k][j] * b.data[i][k];
            }
            matrix.set(@truncate(i), @truncate(j), sum);
        }
    }

    return matrix;
}

/// Helper function that returns a simple 3x3 identity matrix, which can be passed as an argument to mat_transform to signal no rotation.
pub fn mat_3x3_identity(comptime T: type, allocator: *const std.mem.Allocator) !Mat(T)
{
    return try Mat(T).init(allocator, 3, 3);
}

/// Helper function that returns a simple 4x4 identity matrix, which can be used to represent no transformation.
pub fn mat_4x4_identity(comptime T: type, allocator: *const std.mem.Allocator) !Mat(T)
{
    return try Mat(T).init(allocator, 4, 4);
}

/// Returns the data of a matrix formatted into a one-dimensional column-major slice. Uses the allocator of the matrix to allocate the slice.
/// The slice must be deallocated.
pub fn mat_slice_data(comptime T: type, matrix: Mat(T)) ![]T
{
    const size = matrix.data.len * matrix.data[0].len;
    var data = try matrix.allocator.alloc(T, size);

    for(0..matrix.data.len) |i|
    {
        for(0..matrix.data[i].len) |j|
        {
            const index = i * matrix.data[i].len + j;
            data[index] = matrix.data[i][j];
        }
    }

    return data;
}

/// Returns a 3x3 rotation matrix created using axis-angle rotation. T must be a floating-point type.
pub fn mat_transform_rotation(comptime T: type, allocator: *const std.mem.Allocator, axis_angles: Vec(T, 3)) !Mat(T)
{
    const type_info = @typeInfo(T);
    if(type_info != .float and type_info != .comptime_float)
    {
        @compileError("Rotation matrices must have a floating-point data type. (attempted type: " ++ @typeName(T) ++ ").");
    }

    const sin_x = std.math.sin(axis_angles.data[0]);
    const cos_x = std.math.cos(axis_angles.data[0]);

    const sin_y = std.math.sin(axis_angles.data[1]);
    const cos_y = std.math.cos(axis_angles.data[1]);

    const sin_z = std.math.sin(axis_angles.data[2]);
    const cos_z = std.math.cos(axis_angles.data[2]);

    var rot_x = try Mat(T).init(allocator, 3, 3);
    defer rot_x.deinit();

    var rot_y = try Mat(T).init(allocator, 3, 3);
    defer rot_y.deinit();

    var rot_z = try Mat(T).init(allocator, 3, 3);
    defer rot_z.deinit();

    rot_z.set(0, 0, cos_z);
    rot_z.set(1, 0, -sin_z);
    rot_z.set(0, 1, sin_z);
    rot_z.set(1, 1, cos_z);

    rot_y.set(0, 0, cos_y);
    rot_y.set(2, 0, sin_y);
    rot_y.set(0, 2, -sin_y);
    rot_y.set(2, 2, cos_y);

    rot_x.set(1, 1, cos_x);
    rot_x.set(2, 1, -sin_x);
    rot_x.set(1, 2, sin_x);
    rot_x.set(2, 2, cos_x);

    var rot_yz = try multiply_matrices(T, rot_y, rot_z);
    defer rot_yz.deinit();

    const rot = try multiply_matrices(T, rot_x, rot_yz);
    return rot;
}

/// Creates and returns a transformation matrix.
pub fn mat_transform(comptime T: type, allocator: *const std.mem.Allocator, rotation: Mat(T), scale: Vec(T, 3), translation: Vec(T, 3)) !Mat(T)
{
    const type_info = @typeInfo(T);
    if(type_info != .float and type_info != .comptime_float)
    {
        @compileError("Transformation matrices must have a floating-point data type. (attempted type: " ++ @typeName(T) ++ ").");
    }

    var scale_mat = try Mat(T).init(allocator, 4, 4);
    defer scale_mat.deinit();

    var translation_mat = try Mat(T).init(allocator, 4, 4);
    defer translation_mat.deinit();

    for(0..3) |i|
    {
        scale_mat.set(@truncate(i), @truncate(i), scale.data[i]);
        translation_mat.set(3, @truncate(i), translation.data[i]);
    }

    var full_rotation = try Mat(T).init(allocator, 4, 4);
    defer full_rotation.deinit();

    try full_rotation.emplace_values(rotation, 0, 0);

    var scaled_rotation = try multiply_matrices(T, translation_mat, scale_mat);
    defer scaled_rotation.deinit();

    const transform = try multiply_matrices(T, scaled_rotation, full_rotation);
    return transform;
}

/// Creates an returns an orthographic (2D) projection matrix.
pub fn mat_projection_orthographic(allocator: *const std.mem.Allocator, left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) !Mat(f32)
{
    var matrix = try Mat(f32).init(allocator, 4, 4);

    matrix.set(0, 0, 2 / (right - left));
    matrix.set(1, 1, -2 / (top - bottom));
    matrix.set(2, 2, 2 / (far - near));
    matrix.set(3, 0, -(right + left) / (right - left));
    matrix.set(3, 1, (top + bottom) / (top - bottom));
    matrix.set(3, 2, -(far + near) / (far - near));

    return matrix;
}

/// Creates and returns a 3D perspective projection matrix.
pub fn mat_projection_perspective(allocator: *const std.mem.Allocator, fov: f32, aspect: f32, near_plane: f32, far_plane: f32) !Mat(f32)
{
    var matrix = try Mat(f32).init(allocator, 4, 4);

    const ang = fov / 2;
    const f = std.math.cos(ang) / std.math.sin(ang);

    matrix.set(0, 0, f / aspect);
    matrix.set(1, 1, -f);
    matrix.set(2, 2, (far_plane + near_plane) / (near_plane - far_plane));
    matrix.set(3, 2, (2 * far_plane * near_plane) / (near_plane - far_plane));
    matrix.set(2, 3, -1);
    matrix.set(3, 3, 0);

    return matrix;
}

/// Creates and returns a 3D look-at matrix.
pub fn mat_look_at(allocator: *const std.mem.Allocator, pos: Vec(f32, 3), rot: Vec(f32, 3))!Mat(f32)
{
    var matrix = try Mat(f32).init(allocator, 4, 4);

    var forward = rot;
    forward.negate();
    const side = cross(f32, Vec(f32, 3).init(.{0, -1, 0}), forward);
    const above = cross(f32, side, forward);

    for(0..3) |i|
    {
        matrix.set(@truncate(i), 0, side.data[i]);
        matrix.set(@truncate(i), 1, above.data[i]);
        matrix.set(@truncate(i), 2, forward.data[i]);
    }

    matrix.set(3, 0, -dot(3, f32, pos, side));
    matrix.set(3, 1, -dot(3, f32, pos, above));
    matrix.set(3, 2, -dot(3, f32, pos, forward));

    return matrix;
}
