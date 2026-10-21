const std = @import("std");
const builtin = @import("builtin");

/// Adding other dependencies for ashbloom.
fn add_library_dependencies(b: *std.Build, install_step: *std.Build.Step) void
{
    const install_glfw = b.addInstallFile(b.path("deps/glfw.dll"), "bin/glfw.dll");
    const install_freetype = b.addInstallFile(b.path("deps/libfreetype.dll"), "bin/libfreetype.dll");

    install_step.dependOn(&install_glfw.step);
    install_step.dependOn(&install_freetype.step);
}

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

    const xml = b.dependency("xml", .{
        .target = target,
        .optimize = optimize
    });

    const flac = b.dependency("flac", .{
        .target = target,
        .optimize = optimize
    });

    cmp.root_module.addImport("glfw", glfw.module("glfw"));
    cmp.root_module.addImport("vulkan", vulkan.module("vulkan-zig"));
    cmp.root_module.addImport("xml", xml.module("xml"));
    cmp.root_module.addImport("flac", flac.module("flac"));

    cmp.root_module.addLibraryPath(b.path("deps"));

    const miniaudio = load_miniaudio_module(b, target, optimize);
    cmp.root_module.addImport("miniaudio", miniaudio);

    const minimp3 = load_minimp3_module(b, target, optimize);
    cmp.root_module.addImport("minimp3", minimp3);

    const vorbis = load_stb_vorbis_module(b, target, optimize);
    cmp.root_module.addImport("stb_vorbis", vorbis);

    // Searching for the Vulkan drivers.
    // On Windows, they're located in System32.
    if(builtin.target.os.tag == .windows)
    {
        const sys32_path: std.Build.LazyPath = .{
            .cwd_relative = "C:/Windows/System32"
        };

        cmp.root_module.addLibraryPath(sys32_path);

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

fn load_miniaudio_module(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module
{
    const miniaudio = b.createModule(.{
        .target = target,
        .optimize = optimize
    });

    miniaudio.addIncludePath(b.path("include/miniaudio"));
    miniaudio.linkSystemLibrary("c", .{});

    miniaudio.addCSourceFile(.{
        .file = b.path("include/miniaudio/miniaudio.c"),
        .flags = &.{
            "-DMA_NO_WEBAUDIO",
            "-DMA_NO_NULL",
            "-DMA_NO_JACK",
            "-DMA_NO_DSOUND",
            "-DMA_NO_WINMM",
            "-std=c99",
            "-fno-sanitize=undefined",
            if(target.result.os.tag == .macos) "-DMA_NO_RUNTIME_LINKING" else ""
        },
    });

    miniaudio.addCSourceFile(.{
        .file = b.path("include/miniaudio/ma_bind.c"),
        .flags = &.{
            "-std=c99",
            "-fno-sanitize=undefined"
        },
    });

    switch(target.result.os.tag)
    {
        .macos => {
            if(b.lazyDependency("system_sdk", .{})) |system_sdk|
            {
                miniaudio.addFrameworkPath(system_sdk.path("macos12/System/Library/Frameworks"));
                miniaudio.addSystemIncludePath(system_sdk.path("macos12/usr/include"));
                miniaudio.addLibraryPath(system_sdk.path("macos12/usr/lib"));
            }

            miniaudio.linkFramework("CoreAudio", .{});
            miniaudio.linkFramework("CoreFoundation", .{});
            miniaudio.linkFramework("AudioUnit", .{});
            miniaudio.linkFramework("AudioToolbox", .{});
        },
        .linux => {
            miniaudio.linkSystemLibrary("pthread", .{});
            miniaudio.linkSystemLibrary("m", .{});
            miniaudio.linkSystemLibrary("dl", .{});
        },
        else => {}
    }

    const miniaudio_lib = b.addLibrary(.{
        .name = "miniaudio_lib",
        .root_module = miniaudio,
        .linkage = .static
    });

    b.installArtifact(miniaudio_lib);

    const miniaudio_bind = b.addModule("miniaudio", .{
        .root_source_file = b.path("lib/miniaudio.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true
    });

    miniaudio_bind.linkLibrary(miniaudio_lib);

    return miniaudio_bind;
}

fn load_minimp3_module(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module
{
    const minimp3 = b.createModule(.{
        .target = target,
        .optimize = optimize
    });

    minimp3.addIncludePath(b.path("include/minimp3"));
    minimp3.linkSystemLibrary("c", .{});

    minimp3.addCSourceFile(.{
        .file = b.path("include/minimp3/minimp3.c")
    });

    const minimp3_lib = b.addLibrary(.{
        .name = "minimp3_lib",
        .root_module = minimp3,
        .linkage = .static
    });

    b.installArtifact(minimp3_lib);

    const minimp3_bind = b.addModule("minimp3", .{
        .root_source_file = b.path("lib/minimp3.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true
    });

    minimp3_bind.linkLibrary(minimp3_lib);

    return minimp3_bind;
}

fn load_stb_vorbis_module(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module
{
    const stb_vorbis = b.createModule(.{
        .target = target,
        .optimize = optimize
    });

    stb_vorbis.addIncludePath(b.path("include/stb_vorbis"));
    stb_vorbis.linkSystemLibrary("c", .{});

    stb_vorbis.addCSourceFile(.{
        .file = b.path("include/stb_vorbis/stb_vorbis.c")
    });

    const vorbis_lib = b.addLibrary(.{
        .name = "stb_vorbis_lib",
        .root_module = stb_vorbis,
        .linkage = .static
    });

    b.installArtifact(vorbis_lib);

    const vorbis_bind = b.addModule("stb_vorbis", .{
        .root_source_file = b.path("lib/vorbis.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true
    });

    vorbis_bind.linkLibrary(vorbis_lib);

    return vorbis_bind;
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

    const ashbloom_lib = b.addLibrary(.{
        .name = "ashbloom",
        .root_module = ashbloom_mod,
        .linkage = .static
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

    add_library_dependencies(b, &exe_test.step);
    add_library_dependencies(b, &ashbloom_lib.step);

    // add_libraries(b, exe_test, std_target, std_optimize);
    add_libraries(b, ashbloom_lib, std_target, std_optimize);

    // Building library documentation.

    const install_docs = b.addInstallDirectory(.{
        .install_dir = .prefix,
        .install_subdir = "docs",
        .source_dir = ashbloom_lib.getEmittedDocs()
    });

    const docs_step = b.step("docs", "Build documentation");

    add_library_dependencies(b, &install_docs.step);
    docs_step.dependOn(&install_docs.step);

    // Building unit tests.

    const install_exe_test = b.addInstallArtifact(exe_test, .{});

    const test_step = b.step("lib-test", "Build unit tests");
    test_step.dependOn(&install_exe_test.step);
}
