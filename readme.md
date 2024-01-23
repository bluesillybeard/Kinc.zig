# Kinc.zig

Kinc for Zig.

Right now there are no bindings; this simply provides an easier way to link Kinc with your project.

Supported platforms:
- Linux (compiled from Linux)

I am fruitlessly trying to get Windows builds to work, but Windows is just inherently a difficult platform to work with. On Linux, it "just works", but the windows build just refuses to work.

1. Add this as a submodule
    - `git submodule add https://github.com/bluesillybeard/Kinc.zig.git`
    - Technically the library could work if it's not a git submodule, but that is not a use case I will enthusiastically support. In other words, you're pretty much on your own if you refuse to use Git.
2. Make sure Kinc itself is loaded
    - `git submodule update --depth 1 --init Kinc`

- I reccomend putting the second step into some kind of script that people are supposed to run upon cloning your repository

3. In your build.zig:

```
// somewhere
kinc = @import("Kinc.zig/build.zig");

// after you've created your exe or whatever
kinc.link("Kinc.zig/Kinc", exe);
```
that will statically link kinc into your project, and it adds kinc's include paths as well.

Kinc creates its own Main method so it can initialize things before the user's program begins.
That means you can't use the regular Zig entrypoint, you need to do this instead:
```
// Tell zig to find main elsewhere
pub extern fn main(argc: c_int, argv: [*c][*c]const u8) callconv(.C) c_int;

// Export so the linker can find it (instead of it accidentally being linked in the compiler or something)
export fn kickstart(argc: c_int, argv: [*c][*c]const u8) callconv(.C) c_int {
    // code goes here
    return 0; //return non-zero on error
}
```

4. When you add shaders, in your build.zig:

```zig
// the shader source MUST end with 'vert.glsl' or 'frag.glsl' or else the compiler won't know if itt's a vertex or fragment shader!
kinc.compileShader("Kinc", exe, "path/to/shader.vert.glsl", "path/to/output/shader.vert");
kinc.compileShader("Kinc", exe, "path/to/shader.frag.glsl", "path/to/output/shader.frag");

// Shaders are guaranteed to be compiled before your application is, so it's safe to use @embedFile() to load the compiled shader file
```

Compile time depencies:
- Zig (version 0.12.0-dev.2127+fcc0c5ddc) or compatible
- any compile-time dependencies of Kinc (which depends heavily on your target platform)

How it works:
1. Call Kinc's make system to get JSON data of how to build it
2. use that information to add include directories, link system libraries, and add C sources to add Kinc.

TODO:
- Lots of TODOS in `build.zig`
- actual bindings instead of just linking it
- return a module (or whatever that ends up being called in the future) instead of adding the files to a given compile step.
    - Better to do this after bindings are created
- test building on Windows
    - test cross-compilation to Linux. It should work, since X11 libs are linked using libdl instead of as part of the ELF.
        - asound and udev might cause issues if they aren't part of Zig's cross-compile toolkit
        - Look into if libdl is really required, since it should be part of glibc now
- get cross-compilation from Linux to Windows working
    - dxguid is missing
    - winhttp is missing
    - strmiids is missing
    - wbemuuid is missing
    - It might be possible to fix these missing libraries by using .lib and .dll stubs