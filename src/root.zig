//! Root file for Ashbloom.
//! All modules (source files) are exposed here.

const std = @import("std");

/// Required field for win32 API.
pub const UNICODE = false;

// Namespaces.

/// vulkan-zig
pub const vk = @import("vulkan");
/// zGLFW
pub const glfw = @import("glfw");
/// ianprime0509's XML loader
pub const xml = @import("xml");
/// miniaudio (custom bindings based on zaudio)
pub const ma = @import("miniaudio");
/// minimp3 (custom bindings)
pub const minimp3 = @import("minimp3");
/// stb_vorbis (custom bindings)
pub const stb_vorbis = @import("stb_vorbis");

/// Contains everything related to audio input and output. Allows you to record and play audio from a selected input and output.
pub const audio = struct
{
    pub const decoders = @import("audio/decoders.zig");
    pub const nodes = @import("audio/nodes.zig");
    pub const transforms = @import("audio/transforms.zig");

    pub const AudioFormat = nodes.AudioFormat;
    pub const SoundNode = nodes.SoundNode;
    pub const Producer = nodes.Producer;

    /// When called, Ashbloom will emit any sound processed through `node` in addition to other nodes added through this function.
    pub fn add_output_node(allocator: *const std.mem.Allocator, node: *SoundNode) !void
    {
        node.export_channels = audio_device_output_format.channels;
        node.export_sample_rate = audio_device_output_format.sample_rate;

        try audio_sources.append(allocator.*, node);
    }

    /// Disables and deinitializes the audio faculties of the ashbloom framework.
    pub fn deinit(allocator: *const std.mem.Allocator) void
    {
        audio_device.stop();

        audio_sources.deinit(allocator.*);

        audio_device.deinit();
        audio_context.deinit();
    }

    fn input_producer_generate(_: *anyopaque, output: *const []f32, _: audio.Producer.GeneratorFlags) Producer.Result
    {
        for(0..output.len) |i|
        {
            const index = input_cap * output.len + i;
            output.*[i] = audio_input_buffer[index];
        }

        input_cap += 1;
        return .Success;
    }

    /// Returns a `Producer` which records data from the chosen audio input device.
    pub fn input_producer() Producer
    {
        return .{
            .channels = audio_device_input_format.channels,
            .context = undefined,
            .generate_fn = input_producer_generate,
            .sample_rate = audio_device_input_format.sample_rate
        };
    }

    /// Initializes the audio faculties of the Ashbloom framework. Creates a default miniaudio context and polls all available audio I/O devices (speakers, microphones, etc.).
    pub fn init(allocator: *const std.mem.Allocator) !void
    {
        audio_allocator = allocator;
        audio_context = try .init();

        const audio_devices = try audio_context.get_devices();
        audio_devices.print();

        var playback_device_info: ma.Device.Info = undefined;
        var capture_device_info: ma.Device.Info = undefined;

        for(audio_devices.playback_devices) |d|
        {
            if(d.is_default == .True)
            {
                playback_device_info = d;
            }
        }

        for(audio_devices.capture_devices) |d|
        {
            if(d.is_default == .True)
            {
                capture_device_info = d;
            }
        }

        std.debug.print("Selected playback device: ", .{});
        for(playback_device_info.name, 0..) |c, i|
        {
            if(c == 0)
            {
                std.debug.print("{s}\n", .{playback_device_info.name[0..i]});
                break;
            }
        }

        std.debug.print("Selected capture device: ", .{});
        for(capture_device_info.name, 0..) |c, i|
        {
            if(c == 0)
            {
                std.debug.print("{s}\n", .{capture_device_info.name[0..i]});
                break;
            }
        }

        const playback_device_info_ext = try audio_context.get_device_info(.Playback, &playback_device_info.id);
        const capture_device_info_ext = try audio_context.get_device_info(.Capture, &capture_device_info.id);

        audio_device_output_format.channels = playback_device_info_ext.native_data_formats[0].channels;
        audio_device_output_format.format = playback_device_info_ext.native_data_formats[0].format;
        audio_device_output_format.sample_rate = playback_device_info_ext.native_data_formats[0].sample_rate;

        std.debug.print("Playback device format:\n", .{});
        std.debug.print("\tChannels: {d}\n", .{audio_device_output_format.channels});
        std.debug.print("\tFormat: {d}\n", .{@intFromEnum(audio_device_output_format.format)});
        std.debug.print("\tSample rate: {d}\n", .{audio_device_output_format.sample_rate});

        audio_device_input_format.channels = capture_device_info_ext.native_data_formats[0].channels;
        audio_device_input_format.format = capture_device_info_ext.native_data_formats[0].format;
        audio_device_input_format.sample_rate = capture_device_info_ext.native_data_formats[0].sample_rate;

        std.debug.print("Capture device format:\n", .{});
        std.debug.print("\tChannels: {d}\n", .{audio_device_input_format.channels});
        std.debug.print("\tFormat: {d}\n", .{@intFromEnum(audio_device_input_format.format)});
        std.debug.print("\tSample rate: {d}\n", .{audio_device_input_format.sample_rate});

        var config: ma.Device.Config = .init(.Duplex);

        config.playback.device_id = &playback_device_info.id;
        config.playback.format = audio_device_output_format.format;
        config.playback.channels = audio_device_output_format.channels;
        config.capture.device_id = &capture_device_info.id;
        config.capture.format = audio_device_input_format.format;
        config.capture.channels = audio_device_input_format.channels;
        config.sample_rate = audio_device_output_format.sample_rate;
        config.data_callback = ashbloom_audio_callback;
        config.user_data = null;

        audio_device = try .init(audio_context, &config);

        for(0..AUDIO_BUFFER_SIZE) |i|
        {
            audio_output_buffer[i] = 0;
        }

        audio_sources = try .initCapacity(allocator.*, 0);

        try audio_device.start();
    }

    /// Removes an output node from Ashbloom's listening queue by its index. Will effectively stop audio output from this node immediately.
    pub fn remove_output_node(index: usize) void
    {
        _ = audio_sources.orderedRemove(index);
    }
};

/// Utilities related to procedural generation, whether it's noise algorithms like Perlin noise or polygonization algorithms like marching cubes.
pub const gen = struct
{
    pub const polygonizers = @import("gen/polygonizers.zig");
    pub const random = @import("math/random.zig");

    pub const MarchingCubes = polygonizers.MarchingCubes;
    pub const MarchingTetrahedra = polygonizers.MarchingTetrahedra;
    pub const SurfaceNets = polygonizers.SurfaceNets;
};

/// Utilities related to advanced math, like vector and matrix math, as well as different methods of interpolation.
pub const math = struct
{
    pub const linalg = @import("math/linalg.zig");
    pub const interp = @import("math/interp.zig");

    pub const Vec = linalg.Vec;
    pub const Mat = linalg.Mat;
};

/// Utilities related to graphical operations with Vulkan.
pub const rendering = struct
{
    pub const attachment = @import("rendering/attachment.zig");
    pub const commands = @import("rendering/commands.zig");
    pub const mesh = @import("rendering/mesh.zig");
    pub const pipeline = @import("rendering/pipeline.zig");
    pub const vk_core = @import("rendering/vkcontext.zig");
    pub const window = @import("rendering/window.zig");

    pub const Attachment = attachment.Attachment;
    pub const AttachmentBundle = attachment.AttachmentBundle;

    pub const CommandBuffer = commands.CommandBuffer;

    pub const Mesh = mesh.Mesh;

    pub const PipelineVertexInput = pipeline.PipelineVertexInput;
    pub const PipelineDescriptorSet = pipeline.PipelineDescriptorSet;
    pub const Pipeline = pipeline.Pipeline;

    pub const RenderPass = @import("rendering/renderpass.zig").RenderPass;

    pub const Swapchain = @import("rendering/swapchain.zig").Swapchain;

    pub const VkContext = vk_core.VkContext;
    pub const VkInterface = vk_core.VkInterface;

    pub const Window = window.Window;
};

/// General utilities that don't belong to any specific category.
pub const utils = struct
{
    pub const image_utils = @import("utils/image_utils.zig");
    pub const misc = @import("utils/misc.zig");
    pub const vk_memory = @import("utils/vkmemory.zig");
    pub const vk_utils = @import("utils/vkutils.zig");

    pub const FontEntry = misc.FontEntry;
    pub const FontFamily = misc.FontFamily;

    pub const Texture2D = image_utils.Texture2D;
    pub const TextureAtlas2D = image_utils.TextureAtlas2D;

    pub const VulkanAllocator = vk_memory.VulkanAllocator;
};

/// Ashbloom's UI system.
pub const ui = struct
{
    pub const core = @import("utils/vkui.zig");
    pub const font = @import("utils/font.zig");
    pub const layouts = @import("utils/layouts.zig");
    pub const theme_basic = @import("utils/ui_themes/basic.zig");

    pub const Alignment = core.Alignment;
    pub const Bounds = core.Bounds;
    pub const Container = core.Container;
    pub const ContainerInputData = core.ContainerInputData;
    pub const ContainerRendering = core.ContainerRendering;
    pub const Element = core.Element;
    pub const ElementCallback = core.ElementCallback;
    pub const Font = font.Font;
    pub const FontCharacter = font.FontCharacter;
};

const AUDIO_BUFFER_SIZE = 2048;

var audio_allocator: *const std.mem.Allocator = undefined;

var audio_context: *ma.Context = undefined;
var audio_device: *ma.Device = undefined;

var audio_input_buffer: [AUDIO_BUFFER_SIZE]f32 = undefined;
var audio_output_buffer: [AUDIO_BUFFER_SIZE]f32 = undefined;
var audio_output_data_buffer: [AUDIO_BUFFER_SIZE * @sizeOf(f32)]u8 = undefined;

var audio_device_input_format: audio.AudioFormat = undefined;
var audio_device_output_format: audio.AudioFormat = undefined;

var audio_sources: std.ArrayList(*audio.SoundNode) = undefined;
var input_cap: usize = 0;

fn ashbloom_audio_callback(_: *ma.Device, output: *anyopaque, input: *anyopaque, frame_count: u32) callconv(.c) void
{
    var frames_remaining = frame_count;
    while(frames_remaining > 0)
    {
        const next_amount_of_frames = @min(frame_count, AUDIO_BUFFER_SIZE);

        var converted_offset: usize = 0;
        input_cap = 0;
        for(0..next_amount_of_frames * audio_device_input_format.channels) |i|
        {
            const input_format_size = audio_device_input_format.format.get_size();
            const input_buffer: [*]u8 = @ptrCast(input);

            switch(audio_device_input_format.format)
            {
                .Unknown => {},
                .Unsigned8 => {
                    var dp: u8 = undefined;
                    utils.misc.memcpy_anonymous(&dp, input_buffer + i * input_format_size, input_format_size);
                    audio_input_buffer[i] = @as(f32, @floatFromInt(dp)) / 128;
                },
                .Signed16 => {
                    var dp: u16 = undefined;
                    utils.misc.memcpy_anonymous(&dp, input_buffer + i * input_format_size, input_format_size);
                    audio_input_buffer[i] = @as(f32, @floatFromInt(dp)) / 32768;
                },
                .Signed24 => {
                    var dp: u24 = undefined;
                    utils.misc.memcpy_anonymous(&dp, input_buffer + i * input_format_size, input_format_size);
                    audio_input_buffer[i] = @as(f32, @floatFromInt(dp)) / 8388608;
                },
                .Signed32 => {
                    var dp: u32 = undefined;
                    utils.misc.memcpy_anonymous(&dp, input_buffer + i * input_format_size, input_format_size);
                    audio_input_buffer[i] = @as(f32, @floatFromInt(dp)) / 2147483648;
                },
                .Float32 => {
                    utils.misc.memcpy_anonymous(&audio_input_buffer[i], input_buffer + i * input_format_size, input_format_size);
                }
            }
        }

        for(audio_sources.items) |os|
        {
            const data = os.pull_audio(next_amount_of_frames) catch
            {
                @panic("Error generating audio from provider.");
            };
            defer audio_allocator.free(data);

            for(0..next_amount_of_frames) |i|
            {
                for(0..2) |j|
                {
                    const index = i * 2 + j;
                    audio_output_buffer[index] = data[i][j];
                }
                audio_allocator.free(data[i]);
            }
        }

        const output_format_size = audio_device_output_format.format.get_size();

        converted_offset = 0;
        for(0..next_amount_of_frames * audio_device_output_format.channels) |i|
        {
            switch(audio_device_output_format.format)
            {
                .Unknown => {},
                .Unsigned8 => {
                    var dp: u8 = @truncate(@as(usize, @intFromFloat(audio_output_buffer[i] * 128 + 128)));
                    utils.misc.memcpy_anonymous(&audio_output_data_buffer[converted_offset], &dp, output_format_size);
                },
                .Signed16 => {
                    var dp: i16 = @truncate(@as(isize, @intFromFloat(audio_output_buffer[i] * 32768)));
                    utils.misc.memcpy_anonymous(&audio_output_data_buffer[converted_offset], &dp, output_format_size);
                },
                .Signed24 => {
                    var dp: i24 = @truncate(@as(isize, @intFromFloat(audio_output_buffer[i] * 8388608)));
                    utils.misc.memcpy_anonymous(&audio_output_data_buffer[converted_offset], &dp, output_format_size);
                },
                .Signed32 => {
                    var dp: i32 = @truncate(@as(isize, @intFromFloat(audio_output_buffer[i] * 2147483648)));
                    utils.misc.memcpy_anonymous(&audio_output_data_buffer[converted_offset], &dp, output_format_size);
                },
                .Float32 => {
                    utils.misc.memcpy_anonymous(&audio_output_data_buffer[converted_offset], &audio_output_buffer[i], output_format_size);
                }
            }

            converted_offset += output_format_size;
        }

        utils.misc.memcpy_anonymous(output, &audio_output_data_buffer, next_amount_of_frames * audio_device_output_format.channels * output_format_size);
        frames_remaining -= next_amount_of_frames;
    }
}

var stdout_io: std.Io.Threaded = undefined;
var stdout_buffer: [2048]u8 = undefined;
var stdout_writer: std.Io.File.Writer = undefined;

var stdout: *std.Io.Writer = undefined;

/// Deinitializes the base and graphical faculties of the ashbloom framework, and all its dependencies (including GLFW).
pub fn deinit() void
{
    glfw.terminate();
}

/// Initializes the base and graphical faculties of the ashbloom framework, and all its dependencies (including GLFW).
pub fn init(allocator: *const std.mem.Allocator) !void
{
    stdout_io = .init(allocator.*, .{});
    stdout_writer = std.Io.File.stdout().writer(stdout_io.io(), &stdout_buffer);
    stdout = &stdout_writer.interface;

    try glfw.init();

    glfw.windowHint(glfw.ClientAPI, glfw.NoAPI);
}

/// Prints to the standard output. Useful since Zig's `std.debug.print` prints to stderr. Ashbloom inits its own instance of stdout().writer so this is just a shortcut.
/// Max buffer size is 2048 characters, exceeding this value will likely cause a panic.
pub fn print_stdout(comptime fmt: []const u8, args: anytype) void
{
    stdout.print(fmt, args) catch unreachable;
    stdout.flush() catch unreachable;
}

comptime
{
    _ = audio;
    _ = gen;
    _ = math;
    _ = rendering;
    _ = utils;
    _ = ui;

    _ = audio.decoders;
    _ = audio.nodes;
    _ = audio.transforms;

    _ = audio.AudioFormat;
    _ = audio.Producer;
    _ = audio.SoundNode;

    _ = gen.polygonizers;
    _ = gen.random;

    _ = gen.MarchingCubes;
    _ = gen.MarchingTetrahedra;
    _ = gen.SurfaceNets;

    _ = math.interp;
    _ = math.linalg;

    _ = math.Mat;
    _ = math.Vec;

    _ = rendering.attachment;
    _ = rendering.commands;
    _ = rendering.mesh;
    _ = rendering.pipeline;
    _ = rendering.vk_core;
    _ = rendering.window;

    _ = rendering.Attachment;
    _ = rendering.AttachmentBundle;
    _ = rendering.CommandBuffer;
    _ = rendering.Mesh;
    _ = rendering.Pipeline;
    _ = rendering.PipelineDescriptorSet;
    _ = rendering.PipelineVertexInput;
    _ = rendering.RenderPass;
    _ = rendering.Swapchain;
    _ = rendering.VkContext;
    _ = rendering.VkInterface;
    _ = rendering.Window;

    _ = utils.image_utils;
    _ = utils.misc;
    _ = utils.vk_memory;
    _ = utils.vk_utils;

    _ = utils.FontEntry;
    _ = utils.FontFamily;
    _ = utils.Texture2D;
    _ = utils.TextureAtlas2D;
    _ = utils.VulkanAllocator;

    _ = ui.core;
    _ = ui.font;
    _ = ui.layouts;
    _ = ui.theme_basic;

    _ = ui.Alignment;
    _ = ui.Bounds;
    _ = ui.Container;
    _ = ui.ContainerInputData;
    _ = ui.ContainerRendering;
    _ = ui.Element;
    _ = ui.ElementCallback;
    _ = ui.Font;
    _ = ui.FontCharacter;

    _ = deinit_graphics;
    _ = init_graphics;

    _ = print_stdout;

    _ = UNICODE;
}
