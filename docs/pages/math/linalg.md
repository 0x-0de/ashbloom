# `linalg`

Implements linear algebra structures and functions: Vectors, Matrices, and calculations like matrix multiplication and the dot product of vectors.

## Vec (`type`)

**`Vec(comptime T: type, comptime len: u32) type`**

Returns a vector struct type, with a length `len` and type `T`.

### Fields

`const Self = @This()` - Type reference.

`data: [len]T` - Compile-time array of elements, of length `len`.

### Public Functions

**`add(self: *Self, other: Self) void`**

Adds the elements of another Vec of the same type & length to this vector.

**`div(self: *Self, factor: T) void`**

Divides the vector by a scalar value.

**`div_elements(self: *Self, other: Self) void`**

Divides the elements of another Vec of the same type & length from this vector.

**`init(data: [len]T) Self`**

Initialize all members of the vector.

**`init_undefined() Self`**

Initializes all members of this vector by setting them to `undefined`.

**`length(self: Self) f64`**

Calculates and returns the magnitude of the vector.

**`mul(self: *Self, factor: T) void`**

Multiplies the vector by a scalar value.

**`mul_elements(self: *Self, other: Self) void`**

Multiplies the elements of another Vec of the same type & length to this vector.

**`negate(self: *Self) void`**

Muliplies the vector by -1.

**`print(self: Self) void`**

Prints all members of the vector.

**`sub(self: *Self, other: Self) void`**

Subtracts the elements of another Vec of the same type & length from this vector.

## Mat (`type`)

Returns a matrix struct type of type `T`. The data and order of the matrix must be initialized and allocated with `init`.

### Fields

`allocator: *const std.mem.Allocator` - Allocator handle.

`data: [][]T` - Compile-time 2D array of values held by the matrix.

`const Self = @This()` - Type reference.

### Public Functions

**`add(self: *Self, other: Self) LinalgError!void`**

Adds a matrix to this one. The two matrices must have the same order.

**`deinit(self: *Self) void`**

Deinitializes the matrix and frees all associated memory.

**`emplace_values(self: *Self, other: Self, column_offset: usize, row_offset: usize) !void`**

Places values from one matrix directly onto another matrix.

**`get(self: Self, column: u32, row: u32) T`**

Gets the value of a matrix element.

**`init(allocator: *const std.mem.Allocator, columns: usize, rows: usize) !Self`**

Initializes a matrix object.

**`mul(self: *Self, value: T) void`**

Multiplies each element in the matrix by a scalar value.

**`print(self: Self) void`**

Prints the values of a matrix object.

**`set(self: *Self, column: u32, row: u32, value: T) void`**

Sets the value of a matrix element.

**`sub(self: *Self, other: Self) LinalgError!void`**

Subtracts a matrix from this one. The two matrices must have the same order.

### Private Functions

**`verify_matrices_same_order(self: Self, other: Self) LinalgError!void`**

Verifies that two matrices have the same order. Used to potentially flag an error.

## Errors

### LinalgError

#### Values

**MatrixOrderMismatch**: Attempt to perform a mathematical operation (such as multiplication) on matrices that don't have compatible orders.

**OutOfRange**: Attempt to set or change data that is out of the range of a vector or matrix.

## Public Functions

**`type_is_number(comptime T: type) bool`**

Checks if a type represents a discrete or continuous numeral value. Does not consider bools to be numbers. A type is considered usable with a `Vec` or `Mat` with this function.

**`types_can_add(comptime T_a: type, comptime T_b: type) bool`**

Checks if two types are capable of performing addition operations on one another.

**`dot(comptime vec_type: type, comptime vec_size: u32, a: Vec(vec_type, vec_size), b: Vec(vec_type, vec_size)) vec_type`**

Calculate and return the dot product of two vectors.

**`cross(comptime vec_type: type, a: Vec(vec_type, 3), b: Vec(vec_type, 3)) Vec(vec_type, 3)`**

Calculate and return the cross product of two **3-dimensional** vectors.

**`normalize(comptime vec_type: type, comptime vec_size: u32, vec: Vec(vec_type, vec_size)) Vec(vec_type, vec_size)`**

Returns a normalized version of `vec`.

**`multiply_matrices(comptime T: type, a: Mat(T), b: Mat(T)) !Mat(T)`**

Multiplies two matrices of compatible orders, returning a new matrix.

**`mat_3x3_identity(comptime T: type, allocator: *const std.mem.Allocator) !Mat(T)`**

Helper function that returns a simple 3x3 identity matrix, which can be passed as an argument to **`mat_transform`** to signal no rotation.

**`mat_4x4_identity(comptime T: type, allocator: *const std.mem.Allocator) !Mat(T)`**

Helper function that returns a simple 4x4 identity matrix.

**`mat_slice_data(comptime T: type, matrix: Mat(T)) ![]T`**

Returns the data of a matrix formatted into a one-dimensional column-major slice. Uses the allocator of the matrix to allocate the slice. **The slice must be deallocated.**

**`mat_transform_rotation(comptime T: type, allocator: *const std.mem.Allocator, axis_angles: Vec(T, 3)) !Mat(T)`**

Returns a 3x3 rotation matrix created using axis-angle rotation. `T` must be a floating-point type.

**`mat_transform(comptime T: type, allocator: *const std.mem.Allocator, rotation: Mat(T), scale: Vec(T, 3), translation: Vec(T, 3)) !Mat(T)`**

Creates and returns a transformation matrix.

**`mat_projection_orthographic(allocator: *const std.mem.Allocator, left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) !Mat(f32)`**

Creates an returns an orthographic (2D) projection matrix.

**`mat_projection_perspective(allocator: *const std.mem.Allocator, fov: f32, aspect: f32, near_plane: f32, far_plane: f32) !Mat(f32)`**

Creates and returns a 3D perspective projection matrix.

**`mat_look_at(allocator: *const std.mem.Allocator, pos: Vec(f32, 3), rot: Vec(f32, 3))!Mat(f32)`**

Creates and returns a 3D look-at (or "view") matrix.