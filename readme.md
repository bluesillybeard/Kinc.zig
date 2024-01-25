# Kinc.zig

Kinc for Zig.

Right now there are no bindings; this simply provides an easier way to link Kinc with your project.

Also, cross compilation is not supported. You can try it, but don't expect it to work.

Supported platforms:
- Linux (compiled from Linux)
- Windows (compiled from Windows)
- Macos might work, but I don't have a mac to test it.

In the future, I plan on supporting every platform that Kinc supports.

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
1. call Kmake to create a static library of Kinc
    - This is why cross compilation doesn't work - Kmake doesn't do cross-compilation well.
2. link with that static lib
3. compile shaders with krafix

TODO:
- Lots of TODOS in `build.zig`
- actual bindings instead of just linking it
- return a module (or whatever that ends up being called in the future) instead of adding the files to a given compile step.
    - Better to do this after bindings are created

