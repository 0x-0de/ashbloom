const std = @import("std");
const builtin = @import("builtin");

/// Adding other dependencies for ashbloom.
fn add_library_dependencies(b: *std.Build, install_step: *std.Build.Step, ashbloom: *std.Build.Dependency) void
{
    const install_glfw = b.addInstallFile(ashbloom.path("deps/glfw.dll"), "bin/glfw.dll");
    const install_freetype = b.addInstallFile(ashbloom.path("deps/libfreetype.dll"), "bin/libfreetype.dll");

    const install_shader_ui_basic_vert = b.addInstallFile(ashbloom.path("src/utils/ui_themes/ui_basic_vert.spv"), "bin/shaders/ui_basic_vert.spv");
    const install_shader_ui_basic_frag = b.addInstallFile(ashbloom.path("src/utils/ui_themes/ui_basic_frag.spv"), "bin/shaders/ui_basic_frag.spv");

    install_step.dependOn(&install_glfw.step);
    install_step.dependOn(&install_freetype.step);

    install_step.dependOn(&install_shader_ui_basic_vert.step);
    install_step.dependOn(&install_shader_ui_basic_frag.step);
}

/// Adding the Ashbloom library to the compile object.
fn add_libraries(b: *std.Build, cmp: *std.Build.Step.Compile, ashbloom: *std.Build.Dependency, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void
{
    cmp.root_module.addLibraryPath(.{ .cwd_relative = "zig-out/bin" });
    
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

        ashbloom.module("ashbloom").addImport("win32", win32);
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
        .name = "textfields",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = std_target,
            .optimize = std_optimize,
            .link_libc = true
	})
    });
    
    const ashbloom = b.dependency("ashbloom", .{
        .target = std_target,
        .optimize = std_optimize,
    });

    exe.root_module.addImport("ashbloom", ashbloom.module("ashbloom"));
    
    // Building test .exe.

    const install_exe = b.addInstallArtifact(exe, .{});
    
    add_library_dependencies(b, &install_exe.step, ashbloom);
    
    add_libraries(b, exe, ashbloom, std_target, std_optimize);

    b.getInstallStep().dependOn(&install_exe.step);

    // Run step.
    
    const run_step = b.step("run", "Run the application.");
    const run_exe = b.addRunArtifact(exe);
    run_exe.setCwd(b.path("./zig-out/bin"));

    run_exe.step.dependOn(&install_exe.step);
    run_step.dependOn(&run_exe.step);
}
