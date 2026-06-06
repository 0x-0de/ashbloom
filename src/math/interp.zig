//! Handles various interpolation methods.
const std = @import("std");

/// Returns the linearly interpolated value between a and b, at offset t.
pub fn linear(comptime T: type, a: T, b: T, t: T) T
{
    return (b - a) * t + a;
}

/// Does linear interpolation across two axes.
pub fn linear_2d(comptime T: type, aa: T, ba: T, ab: T, bb: T, tx: T, ty: T) T
{
    const a = linear(T, aa, ba, tx);
    const b = linear(T, ab, bb, tx);

    return linear(T, a, b, ty);
}

/// Does linear interpolation across three axes.
pub fn linear_3d(comptime T: type, aaa: T, baa: T, aba: T, bba: T, aab: T, bab: T, abb: T, bbb: T, tx: T, ty: T, tz: T) T
{
    const a = linear_2d(T, aaa, baa, aba, bba, tx, ty);
    const b = linear_2d(T, aab, bab, abb, bbb, tx, ty);

    return linear(T, a, b, tz);
}

/// Performs cosine interpolation between a and b, with offset value t.
pub fn cosine(comptime T: type, a: T, b: T, t: T) T
{
    const m = (1 - std.math.cos(t * std.math.pi)) / 2;
    return linear(T, a, b, m);
}

/// Does cosine interpolation across two axes.
pub fn cosine_2d(comptime T: type, aa: T, ba: T, ab: T, bb: T, tx: T, ty: T) T
{
    const a = cosine(T, aa, ba, tx);
    const b = cosine(T, ab, bb, tx);

    return cosine(T, a, b, ty);
}

/// Does cosine interpolation across three axes.
pub fn cosine_3d(comptime T: type, aaa: T, baa: T, aba: T, bba: T, aab: T, bab: T, abb: T, bbb: T, tx: T, ty: T, tz: T) T
{
    const a = cosine_2d(T, aaa, baa, aba, bba, tx, ty);
    const b = cosine_2d(T, aab, bab, abb, bbb, tx, ty);

    return cosine(T, a, b, tz);
}

/// Performs cubic interpolation between b and c, with slopes determined by a and d, with offset value t.
pub fn cubic(comptime T: type, a: T, b: T, c: T, d: T, t: T) T
{
    const m = t * t;

    const v0 = d - c - a + b;
    const v1 = a - b - v0;
    const v2 = c - a;
    const v3 = b;

    return v0 * t * m + v1 * m + v2 * t + v3;
}


