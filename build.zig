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
        .registry = b.path("./lib/vk.xml")
    });

    cmp.root_module.addImport("glfw", glfw.module("glfw"));
    cmp.root_module.addImport("vulkan", vulkan.module("vulkan-zig"));

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
            .root_source_file = b.path("lib/win32.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true
        });

        cmp.root_module.addImport("win32", win32);

        cmp.root_module.linkSystemLibrary("glfw", .{});
        cmp.root_module.linkSystemLibrary("vulkan-1", .{});
    }
    else if(builtin.target.os.tag == .linux)
    {
        cmp.root_module.linkSystemLibrary("glfw3", .{});
        cmp.root_module.linkSystemLibrary("vulkan", .{});
    }

    cmp.root_module.linkSystemLibrary("libfreetype", .{});
}

pub fn build(b: *std.Build) void
{
    const std_target = b.standardTargetOptions(.{});
    const std_optimize = b.standardOptimizeOption(.{});

    const c_freetype = b.addTranslateC(.{
        .root_source_file = b.path("src/utils/inc_freetype.h"),
        .target = std_target,
        .optimize = std_optimize
    });

    c_freetype.addIncludePath(b.path("include/freetype"));

    // May need to link libfreetype with c_freetype.

    const ashbloom_mod = b.addModule("ashbloom", .{
        .root_source_file = b.path("src/root.zig"),
        .target = std_target,
        .optimize = std_optimize,
        .link_libc = true,
        .imports = &.{
            .{
                .name = "freetype",
                .module = c_freetype.createModule()
            }
        }
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "ashbloom",
        .root_module = ashbloom_mod
    });

    const exe_test = b.addTest(.{
        .name = "ashbloom-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = std_target,
            .optimize = std_optimize,
            .link_libc = true,
            .imports = &.{
                .{
                    .name = "freetype",
                    .module = c_freetype.createModule()
                }
            }
        })
    });

    add_libraries(b, exe_test, std_target, std_optimize);
    add_libraries(b, lib, std_target, std_optimize);

    // Building library documentation.

    const install_docs = b.addInstallDirectory(.{
        .install_dir = .{ .custom = ".." },
        .install_subdir = "docs",
        .source_dir = lib.getEmittedDocs()
    });

    const docs_step = b.step("docs", "Build documentation");
    docs_step.dependOn(&install_docs.step);

    // Building unit tests.

    const install_exe_test = b.addInstallArtifact(exe_test, .{
        .dest_dir = .{ .override = .{ .custom = "../bin" } }
    });

    const test_step = b.step("lib-test", "Build unit tests");
    test_step.dependOn(&install_exe_test.step);
}
