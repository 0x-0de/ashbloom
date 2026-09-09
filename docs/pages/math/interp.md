# `interp`

Implements various interpolation methods.

## Public Functions

linear(comptime T: type, a: T, b: T, t: T) T

Returns the linearly interpolated value between `a` and `b`, at offset `t`.

linear_2d(comptime T: type, aa: T, ba: T, ab: T, bb: T, tx: T, ty: T) T

Does linear interpolation across two axes.

linear_3d(comptime T: type, aaa: T, baa: T, aba: T, bba: T, aab: T, bab: T, abb: T, bbb: T, tx: T, ty: T, tz: T) T

Does linear interpolation across three axes.

cosine(comptime T: type, a: T, b: T, t: T) T

Performs cosine interpolation between `a` and `b`, with offset value `t`.

cosine_2d(comptime T: type, aa: T, ba: T, ab: T, bb: T, tx: T, ty: T) T

Does cosine interpolation across two axes.

cosine_3d(comptime T: type, aaa: T, baa: T, aba: T, bba: T, aab: T, bab: T, abb: T, bbb: T, tx: T, ty: T, tz: T) T

Does cosine interpolation across three axes.

cubic(comptime T: type, a: T, b: T, c: T, d: T, t: T) T

Performs cubic interpolation between `b` and `c`, with slopes determined by `a` and `d`, with offset value `t`.