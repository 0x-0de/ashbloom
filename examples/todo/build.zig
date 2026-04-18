const std = @import("std");
const builtin = @import("builtin");

/// Adding the Vulkan and GLFW libraries to the compile object.
fn add_libraries(b: *std.Build, cmp: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void
{
    const glfw = b.dependency("glfw", .{
        .target = target,
        .optimize = optimize,
    });

    const vulkan = b.dependency("vulkan", .{
        .registry = b.path("../../lib/vk.xml")
    });

    const ashbloom = b.addModule("ashbloom", .{
        .root_source_file = b.path("../../src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true
    });

    ashbloom.addImport("glfw", glfw.module("glfw"));
    ashbloom.addImport("vulkan", vulkan.module("vulkan-zig"));

    ashbloom.addIncludePath(.{ .cwd_relative = "../../include/freetype" });

    cmp.root_module.addImport("ashbloom", ashbloom);

    cmp.root_module.addLibraryPath(.{ .cwd_relative = "bin" });
    
    // Searching for the Vulkan drivers.
    // On Windows, they're located in System32.
    if(builtin.target.os.tag == .windows)
    {
        const sys32_path: std.Build.LazyPath = .{
            .cwd_relative = "C:/Windows/System32"
        };
        
        cmp.root_module.addLibraryPath(sys32_path);

        const win32 = b.addModule("win32", .{
            .root_source_file = b.path("../../lib/win32.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true
        });

        ashbloom.addImport("win32", win32);
    }
    else if(builtin.target.os.tag == .linux)
    {
        // TODO.
    }

    cmp.root_module.linkSystemLibrary("glfw", .{});
    cmp.root_module.linkSystemLibrary("libfreetype", .{});
    cmp.root_module.linkSystemLibrary("vulkan-1", .{});
}

pub fn build(b: *std.Build) void
{
    const std_target = b.standardTargetOptions(.{});
	const std_optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "todo",
        .root_module = b.createModule(.{
			.root_source_file = b.path("src/main.zig"),
			.target = std_target,
            .optimize = std_optimize,
            .link_libc = true
		})
    });

    const exe_test = b.addTest(.{
        .name = "todo-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = std_target,
            .optimize = std_optimize,
            .link_libc = true
        })
    });

    add_libraries(b, exe, std_target, std_optimize);
    // exe.addIncludePath(.{ .cwd_relative = "include/freetype" });

    add_libraries(b, exe_test, std_target, std_optimize);
    // exe_test.addIncludePath(.{ .cwd_relative = "include/freetype" });

    // Building test .exe.

    const install_exe = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = "../bin" } }
    });

    b.getInstallStep().dependOn(&install_exe.step);

    // Building unit tests.

    const install_exe_test = b.addInstallArtifact(exe_test, .{
        .dest_dir = .{ .override = .{ .custom = "../bin" } }
    });

    const test_step = b.step("app-test", "Build unit tests");
    test_step.dependOn(&install_exe_test.step);
}