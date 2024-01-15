const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // TODO: put examples in a list
    const exe = b.addExecutable(.{
        .name = "example",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = .{.path = "examples/0_simple/main.zig"},
    });
    try link("Kinc", exe);
    b.installArtifact(exe);
    const runStep = b.addRunArtifact(exe);
    runStep.step.dependOn(&exe.step);
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
        //try flags.append("-I");
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{modulePathAbsolute, include});
        //try flags.append(path);
        // Because the application needs to have the includes as well, those are sent to c as well
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