const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // TODO: take in options as parameters
    const options = KmakeOptions{
        .platform = .guess,
    };
    // TODO: put examples in a list
    // List will need shaders too
    const exe = b.addExecutable(.{
        .name = "example",
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "examples/0_simple/main.zig" },
    });
    try link("Kinc", exe, options);
    try compileShader("Kinc", exe, "examples/0_simple/shader.frag.glsl", "examples/0_simple/shaderOut/shader.frag", options);
    try compileShader("Kinc", exe, "examples/0_simple/shader.vert.glsl", "examples/0_simple/shaderOut/shader.vert", options);
    b.installArtifact(exe);
    const runArtifact = b.addRunArtifact(exe);
    runArtifact.step.dependOn(&exe.step);
    const runStep = b.step("run", "Run example 0");
    runStep.dependOn(&runArtifact.step);
}

/// Only accepts GLSL shaders for now.
/// sourceFile and destinationFile are relative paths from your build.zig
/// The shader is compiled immediately upon calling this function, so you can expect it to be available for @embedFile or other build commands.
/// This function should be called after calling link, with the exact same options.
pub fn compileShader(comptime modulePath: []const u8, c: *std.Build.Step.Compile, sourceFile: []const u8, destinationFile: []const u8, options: KmakeOptions) !void {
    const allocator = c.root_module.owner.allocator;
    // make paths absolute
    const cwdPath = try std.fs.cwd().realpathAlloc(allocator, "./");
    const sourceFileAbsolute = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cwdPath, sourceFile });
    const destinationPath = destinationFile[0 .. std.mem.lastIndexOfAny(u8, destinationFile, "/\\") orelse 0];
    // create the destination folder if it doesn't already exist
    std.fs.cwd().makePath(destinationPath) catch |e| if (e != error.PathAlreadyExists) return e;
    const destinationFileAbsolute = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cwdPath, destinationFile });
    const modulePathAbsolute = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cwdPath, modulePath });
    // Figure out which krafix to use
    const krafixPath = switch (builtin.os.tag) {
        .linux => switch (builtin.cpu.arch) {
            .x86_64 => try std.fmt.allocPrint(allocator, "{s}/Tools/linux_x64/krafix", .{modulePathAbsolute}),
            .arm => try std.fmt.allocPrint(allocator, "{s}/Tools/linux_arm/krafix", .{modulePathAbsolute}),
            .aarch64 => try std.fmt.allocPrint(allocator, "{s}/Tools/linux_arm64/krafix", .{modulePathAbsolute}),
            else => @panic("unsupported host arch"),
        },
        .freebsd => switch (builtin.cpu.arch) {
            .x86_64 => try std.fmt.allocPrint(allocator, "{s}/Tools/freebsd_x64/krafix", .{modulePathAbsolute}),
            else => @panic("unsupported host arch"),
        },
        .macos => switch (builtin.cpu.arch) {
            // TODO: make sure this is actually x86 instead of being arm
            .x86_64 => try std.fmt.allocPrint(allocator, "{s}/Tools/macos/krafix", .{modulePathAbsolute}),
            // TODO: consider using rosetta on arm64 (or just running it of macos supports just running it)
            else => @panic("unsupported host arch"),
        },
        .windows => switch (builtin.cpu.arch) {
            .x86_64 => try std.fmt.allocPrint(allocator, "{s}/Tools/windows_x64/krafix", .{modulePathAbsolute}),
            else => @panic("unsupported host arch"),
        },
        else => @panic("unsupported host OS"),
    };

    // Figure out what shader type to compile to
    // TODO: actually do this instead of assuming Vulkan
    const shaderOutputType = "spirv";

    // the build directory for Kinc.
    const buildDir = try std.fmt.allocPrint(allocator, "{s}/Build", .{modulePathAbsolute});
    // build arguments for krafix
    std.debug.print("{s}\n", .{krafixPath});
    const args = [_][]const u8{
        krafixPath,
        shaderOutputType,
        sourceFileAbsolute,
        destinationFileAbsolute,
        buildDir,
        getKmakeTargetString(c.rootModuleTarget(), options.platform),
    };
    std.debug.print("Krafix arguments: {s}\n", .{args});
    var child = std.process.Child.init(&args, allocator);
    child.cwd = modulePathAbsolute;
    // TODO: verify it ran successfully
    _ = try child.spawnAndWait();
}

// Link Kinc to a compile step & and kinc's include directory
pub fn link(comptime modulePath: []const u8, c: *std.Build.Step.Compile, options: KmakeOptions) !void {
    // Note: Kinc doesn't need the full C++ library in certain configurations, however it's easiest to always link it
    c.linkLibCpp();
    const allocator = c.root_module.owner.allocator;
    // Path to kinc (not Kinc.zig)
    const modulePathAbsolute = try std.fs.cwd().realpathAlloc(allocator, modulePath);
    // set up Kinc
    defer allocator.free(modulePathAbsolute);
    {
        var child = blk: {
            if (builtin.os.tag == .windows) {
                break :blk std.process.Child.init(&[_][]const u8{"get_dlc"}, allocator);
            } else {
                // TODO: see if the Windows code works on Posix as well. (skipping bash and going straight to running the file)
                break :blk std.process.Child.init(&[_][]const u8{ "bash", "get_dlc" }, allocator);
            }
        };

        child.cwd = modulePathAbsolute;
        const res = try child.spawnAndWait();
        if (res != .Exited or res.Exited != 0) {
            std.debug.print("get_dlc failed! {any}\n", .{res});
        }
    }
    // Call Kinc's build system to make the static library
    try runKmake(c, options, modulePathAbsolute, false);

    // Link with the static library
    // TODO: I believe it will be Kinc.lib on Windows
    c.addObjectFile(.{.path = try std.fmt.allocPrint(allocator, "{s}/Deployment/Kinc.a", .{modulePathAbsolute})});

    // Call it again to get json info - this is used for include directories
    try runKmake(c, options, modulePathAbsolute, true);

    // Read in the file it created
    // It has an option to print the json to stdout, but it mixes it with logs so it's basically useless
    const file = try std.fs.openFileAbsolute(try std.fmt.allocPrint(allocator, "{s}/build/Kinc.json", .{modulePathAbsolute}), .{});
    const jsonText = try file.readToEndAlloc(allocator, std.math.maxInt(usize));

    const buildInfoParsed = try std.json.parseFromSlice(BuildInfo, allocator, jsonText, .{
        .allocate = .alloc_always,
        .duplicate_field_behavior = .@"error",
        .ignore_unknown_fields = true,
        .max_value_len = null,
    });
    defer buildInfoParsed.deinit();
    const buildInfo = buildInfoParsed.value;

    for (buildInfo.includes) |include| {
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ modulePathAbsolute, include });
        c.addIncludePath(.{ .path = path });
    }

    // TODO: look into whether it would be worth adding the option to link libraries statically.
    for (buildInfo.libraries) |library| {
        c.linkSystemLibrary2(library, .{
            // pkg-config doesn't know what to do with some of the libs
            // For example, the 'udev' library wouldn't be linked correctly using pkg-config
            .use_pkg_config = .no,
        });
    }
    // TODO: frameworks on macos

}

// Kinc's build info will parse into this struct
pub const BuildInfo = struct {
    includes: []const []const u8,
    libraries: []const []const u8,
    defines: []const []const u8,
    files: []const []const u8,
};

fn runKmake(c: *std.Build.Step.Compile, options: KmakeOptions, modulePathAbsolute: []const u8, json: bool) !void {
    const allocator = c.root_module.owner.allocator;
    var args = try std.ArrayList([]const u8).initCapacity(c.root_module.owner.allocator, 20);
    if (builtin.os.tag == .windows) {
        try args.append("make");
    } else {
        // TODO: see if bash is nessisary on posix systems
        try args.append("bash");
        try args.append("make");
    }
    if(json){
       try args.append("--json") ;
    } else {
        try args.append("--compile");
        try args.append("--lib");
    }
    
    // forward target
    try args.append("--target");
    try args.append(getKmakeTargetString(c.rootModuleTarget(), options.platform));
    try args.append("--arch");
    try args.append(getKmakeArchitectureString(c.rootModuleTarget()));
    // forward debug
    if (c.root_module.optimize == null or c.root_module.optimize.? == .Debug) {
        try args.append("--debug");
    }
    // TODO: graphics and audio options
    // For now, only vulkan is allowed to be used
    try args.append("--graphics");
    try args.append("vulkan");

    std.debug.print("Kmake options: {s}\n", .{args.items});
    var child = std.process.Child.init(try args.toOwnedSlice(), allocator);
    child.cwd = modulePathAbsolute;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    var stdout = std.ArrayList(u8).init(allocator);
    defer stdout.deinit();
    var stderr = std.ArrayList(u8).init(allocator);
    defer stderr.deinit();
    try child.spawn();
    try child.collectOutput(&stdout, &stderr, std.math.maxInt(usize));
    const res = try child.wait();
    if (res != .Exited or res.Exited != 0) {
        std.debug.print("Kmake failed! {any}\n\n", .{res});
        std.debug.print("Stdout:\n{s}\n\n", .{stdout.items});
        std.debug.print("Stderr: {s}\n\n", .{stderr.items});
    }
}

fn guessKmakeTargetStringFromTarget(target: std.Target) []const u8 {
    // TODO: switch on compatible platforms too
    // For example, most BSDs are compatible with linux binaries
    return switch (target.os.tag) {
        .windows => "windows",
        .ios => "ios",
        .macos => "osx",
        .linux => "linux",
        .emscripten => "emscripten",
        .tvos => "tvos",
        .ps4 => "ps4",
        .ps5 => "ps5",
        .freebsd => "freebsd",
        // TODO: verify that Zig Wasi is compatible with Kmake WASM
        .wasi => "wasm",
        else => @panic("Unsupported target"),
    };
}

fn getKmakeTargetString(target: std.Target, platform: KmakePlatform) []const u8 {
    if (platform == .guess) return guessKmakeTargetStringFromTarget(target);
    // Note that whether the architecture is supported on that platform is not checked,
    // instead let Kmake do that.

    // The KmakePlatform enum's names are the same as the string values
    // So we can just get the enum name
    return @tagName(platform);
}
fn getKmakeArchitectureString(target: std.Target) []const u8 {
    return switch (target.cpu.arch) {
        .x86 => "x86",
        .x86_64 => "x86_64",
        .aarch64 => blk: {
            //TODO: differentiate between arm7 and arm8
            break :blk "arm7";
        },
        else => @panic("unsupported target architecture"),
    };
}

pub const KmakeOptions = struct {
    platform: KmakePlatform,
};

pub const KmakePlatform = enum {
    // TODO: go beyond Zig target and see if there are any CPU feature limitations or guarantees for each platform.
    // For example, the PS5's processor might support extensions that zig does not enable by default,
    // Or the XBox one might have a CPU that is too old to be supported by Zig's default code generation, so CPU features have to be explicitly disabled
    ///Try to guess using the Zig target. Note that this will generally assume Vulkan / DirectX support, and it will generally assume PC rather than mobile.
    guess,
    windows, //windows
    windowsapp, //windows
    ios, // ios
    osx, //macos
    android, //linux?
    linux, //linux
    emscripten, //emscripten
    tizen, //linux
    pi, //linux
    tvos, //tvos
    ps4, //ps4
    xboxone, //windows
    @"switch", //linux?
    xboxscarlett, //windows
    ps5, //ps5
    freebsd, //freebsd
    wasm, //wasi?
};
