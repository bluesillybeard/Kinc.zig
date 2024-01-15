# Kinc.zig

Kinc for Zig.

Right now there are no bindings; this simply provides an easier way to link Kinc with your project.

Add this as a submodule (don't forget to clone recursively).

In your build.zig:

```
// somewhere
kinc = @import("Kinc.zig/build.zig");

// after you've created your exe or whatever
kinc.link("Kinc.zig", exe);
```
that will statically link kinc into your project, and it adds kinc's include paths as well.

Note: Kinc creates its own Main method so it can initialize things before the user's program begins.
That means you can't use the regular Zig entrypoint system, you need to define this for your entry point:
```
// Tell zig to find main elsewhere
pub extern fn main(argc: c_int, argv: [*c][*c]const u8) callconv(.C) c_int;

// Export so the LLVM linker can find it (instead of it accidentally being linked before LLVM can find it)
export fn kickstart(argc: c_int, argv: [*c][*c]const u8) callconv(.C) c_int {
    // code goes here
    return 0; //return non-zero on error
}
```

Currently tested with zig 0.12.0-dev.2127+fcc0c5ddc

How it works:
1. Call Kinc's make system to get JSON data of how to build it
2. use that information to add include directories, link system libraries, and add C sources to add Kinc.

TODO:
- actual bindings instead of just linking it
- return a module (or whatever that ends up being called in the future) instead of adding the files to a given compile step.
