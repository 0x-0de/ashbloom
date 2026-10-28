const nodes = @import("nodes.zig");

pub const VolumeTransform = struct
{
    volume: f32,

    pub fn process_frame(context: *anyopaque, frame: *[]f32) void
    {
        const self: *VolumeTransform = @ptrCast(@alignCast(context));
        for(0..frame.len) |i|
        {
            frame.*[i] *= self.volume;
        }
    }

    pub fn transform(self: *VolumeTransform) nodes.SoundTransform
    {
        return .{
            .context = self,
            .transform_fn = process_frame
        };
    }
};

pub const BalanceTransform = struct
{
    left: f32,
    right: f32,

    pub fn process_frame(context: *anyopaque, frame: *[]f32) void
    {
        const self: *BalanceTransform = @ptrCast(@alignCast(context));
        if(frame.len == 1)
        {
            const volume = (self.left + self.right) / 2;
            frame.*[0] *= volume;
        }
        else
        {
            var current = self.left;
            const add = (self.right - self.left) / @as(f32, @floatFromInt(frame.len - 1));
            for(0..frame.len) |i|
            {
                frame.*[i] *= current;
                current += add;
            }
        }
    }

    pub fn transform(self: *BalanceTransform) nodes.SoundTransform
    {
        return .{
            .context = self,
            .transform_fn = process_frame
        };
    }
};
