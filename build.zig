const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // TODO: put examples in a list
    // List will need shaders too
    const exe = b.addExecutable(.{
        .name = "example",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = .{.path = "examples/0_simple/main.zig"},
    });
    try link("Kinc", exe);
    try compileShader("Kinc", exe, "examples/0_simple/shader.frag.glsl", "examples/0_simple/shaderOut/shader.frag");
    try compileShader("Kinc", exe, "examples/0_simple/shader.vert.glsl", "examples/0_simple/shaderOut/shader.vert");
    b.installArtifact(exe);
    const runArtifact = b.addRunArtifact(exe);
    runArtifact.step.dependOn(&exe.step);
    const runStep = b.step("run", "Run example 0");
    runStep.dependOn(&runArtifact.step);
}

/// Only accepts GLSL shaders for now.
/// sourceFile and destinationFile are relative paths from your build.zig
/// The shader is compiled immediately upon calling this function, so you can expect it to be available for @embedFile or other build commands.
/// This function should be called after calling link.
pub fn compileShader(comptime modulePath: []const u8, c: *std.Build.Step.Compile, sourceFile: []const u8, destinationFile: []const u8) !void {
    const allocator = c.root_module.owner.allocator;
    // make paths absolute
    const cwdPath = try std.fs.cwd().realpathAlloc(allocator, "./");
    const sourceFileAbsolute = try std.fmt.allocPrint(allocator, "{s}/{s}", .{cwdPath, sourceFile});
    const destinationPath = destinationFile[0 .. std.mem.lastIndexOfAny(u8, destinationFile, "/\\") orelse 0];
    // create the destination folder if it doesn't already exist
    std.fs.cwd().makePath(destinationPath) catch |e| if(e != error.PathAlreadyExists) return e;
    const destinationFileAbsolute = try std.fmt.allocPrint(allocator, "{s}/{s}", .{cwdPath, destinationFile});
    const modulePathAbsolute = try std.fmt.allocPrint(allocator, "{s}/{s}", .{cwdPath, modulePath});
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
        // TODO: figure target platform instead of assuing linux
        "linux",
    };
    std.debug.print("Krafix arguments: {s}\n", .{args});
    var child = std.process.Child.init(&args, allocator);
    child.cwd = modulePathAbsolute;
    // TODO: verify it ran successfully
    _ = try child.spawnAndWait();
}

// Link Kinc to a compile step & and kinc's include directory
pub fn link(comptime modulePath: []const u8, c: *std.Build.Step.Compile) !void {
    const allocator = c.root_module.owner.allocator;
    const modulePathAbsolute = try std.fs.cwd().realpathAlloc(allocator, modulePath);
    // set up Kinc
    // TODO: run the bat on Windows
    
    defer allocator.free(modulePathAbsolute);
    {
        var child = std.process.Child.init(&[_][]const u8{"bash", "get_dlc"}, allocator);
        child.cwd = modulePathAbsolute;
        _ = try child.spawnAndWait();
        // TODO: make sure it exited successfuly
    }
    // Call Kinc's build system to get information on how to build it.
    // TODO: forward target and optimize info
    // TODO: create a struct to place arguments for Kinc (such as specifying the graphics backend or which features to enable)
    // TODO: run the bat on Windows
    const buildInfoJson = blk: {
        var child = std.process.Child.init(&[_][]const u8{"bash", "make", "--json"}, allocator);
        child.cwd = modulePathAbsolute;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        var stdout = std.ArrayList(u8).init(allocator);
        defer stdout.deinit();
        var stderr = std.ArrayList(u8).init(allocator);
        defer stderr.deinit();
        try child.spawn();
        try child.collectOutput(&stdout, &stderr, std.math.maxInt(usize));
        _ = try child.wait();
        // TODO: make sure it exited successfuly
        
        if(stderr.items.len > 0){
            std.debug.print("{s}\n", .{stdout.items});
            std.debug.print("{s}\n", .{stderr.items});
        }
        // Read in the file it created
        // It has an option to print the json to stdout, but it mixes it with logs so it's basically useless
        const file = try std.fs.openFileAbsolute(try std.fmt.allocPrint(allocator, "{s}/build/Kinc.json", .{modulePathAbsolute}), .{});
        break :blk try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    };
    // print the JSON it returned
    try std.io.getStdOut().writer().print("{s}\n", .{buildInfoJson});
    // parse the json it returned
    const buildInfoParsed = try std.json.parseFromSlice(
        BuildInfo,allocator, buildInfoJson,
        .{
            .allocate = .alloc_always,
            .duplicate_field_behavior = .@"error",
            .ignore_unknown_fields = true,
            .max_value_len = null,
        }
    );
    defer buildInfoParsed.deinit();
    const buildInfo = buildInfoParsed.value;

    // Buid the flags for the compilation into c
    var flags = try std.ArrayList([]const u8).initCapacity(allocator, 
    buildInfo.includes.len * 2 + buildInfo.libraries.len * 2 + buildInfo.defines.len * 2);
    defer flags.deinit();

    for(buildInfo.defines) |define| {
        try flags.append("-D");
        try flags.append(define);
    }

    // TODO: look into whether it would be worth adding the option to link libraries statically.
    for(buildInfo.libraries) |library| {
        c.linkSystemLibrary2(library, .{
            .needed = true,
            // pkg-config doesn't know what to do with some of the libs 
            .use_pkg_config = .no,
        });
    }

    for(buildInfo.includes) |include| {
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{modulePathAbsolute, include});
        c.addIncludePath(.{.path = path});
    }
    var files = try std.ArrayList([]const u8).initCapacity(allocator, buildInfo.files.len);
    defer files.deinit();
    for(buildInfo.files) |file| {
        // filter out files we don't care about
        if(std.mem.endsWith(u8, file, ".c")
        or std.mem.endsWith(u8, file, ".cpp")) {
            // The files are relative to Kinc, not Kinc.zig so add that part of the path
            try files.append(try std.fmt.allocPrint(allocator, "Kinc/{s}", .{file}));
        }
    }
    c.addCSourceFiles(.{
        .files = files.items,
        .flags = flags.items,
    });
}

// Kinc's build info will parse into this struct
pub const BuildInfo = struct {
    includes: []const []const u8,
    libraries: []const []const u8,
    defines: []const []const u8,
    files: []const []const u8,
};