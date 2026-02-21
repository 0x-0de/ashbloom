const std = @import("std");

/// Adding the Vulkan and GLFW libraries to the compile object.
fn add_libraries(b: *std.Build, cmp: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void
{
    const glfw = b.addModule("glfw", .{
        .root_source_file = b.path("lib/glfw.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true
    });

    const vk = b.addModule("vulkan", .{
        .root_source_file = b.path("lib/vk.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true
    });

    cmp.root_module.addImport("glfw", glfw);
    cmp.root_module.addImport("vulkan", vk);

    cmp.root_module.addLibraryPath(.{ .cwd_relative = "bin" });
    
    const sys32_path: std.Build.LazyPath = .{
        .cwd_relative = "C:/Windows/System32"
    };
    
    cmp.root_module.addLibraryPath(sys32_path);

    cmp.root_module.linkSystemLibrary("glfw", .{});
    cmp.root_module.linkSystemLibrary("libfreetype", .{});
    cmp.root_module.linkSystemLibrary("vulkan-1", .{});
}

pub fn build(b: *std.Build) void
{
    const std_target = b.standardTargetOptions(.{});
	const std_optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "test",
        .root_module = b.createModule(.{
			.root_source_file = b.path("src/main.zig"),
			.target = std_target,
            .optimize = std_optimize,
            .link_libc = true
		})
    });

    add_libraries(b, exe, std_target, std_optimize);
    exe.addIncludePath(.{ .cwd_relative = "include/freetype" });

    const install_exe = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = "../bin" } }
    });
    
    b.getInstallStep().dependOn(&install_exe.step);
}