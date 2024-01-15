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
export fn kickstart(c_int argc, [*c][*c]const u8 argv) c_int {}
```


TODO:
- actual bindings instead of just linking it
    - This is extra important because Kinc has an aggrivatingly traditional C api that makes me want to puke
- return a module (or whatever that ends up being called in the future) instead of adding the files to a given compile step.
