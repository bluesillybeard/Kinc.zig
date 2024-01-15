// This is the same as the "Empty" test in the original Kinc sources.
// It has been transformed to do things "the zig way" as much as possible
// while being functionally identical to the original.

const std = @import("std");

const c = @cImport({
    @cInclude("kinc/graphics4/graphics.h");
    @cInclude("kinc/graphics4/indexbuffer.h");
    @cInclude("kinc/graphics4/pipeline.h");
    @cInclude("kinc/graphics4/shader.h");
    @cInclude("kinc/graphics4/vertexbuffer.h");
    @cInclude("kinc/io/filereader.h");
    @cInclude("kinc/system.h");
});

var vertex_shader: c.kinc_g4_shader_t = undefined;
var fragment_shader: c.kinc_g4_shader_t = undefined;
var pipeline: c.kinc_g4_pipeline_t = undefined;
var vertices: c.kinc_g4_vertex_buffer_t = undefined;
var indices: c.kinc_g4_index_buffer_t = undefined;

fn update(data: ?*anyopaque) callconv(.C) void {
    _ = data;

    c.kinc_g4_begin(0);
    c.kinc_g4_clear(c.KINC_G4_CLEAR_COLOR, 0, 0.0, 0);
    c.kinc_g4_set_pipeline(&pipeline);
    c.kinc_g4_set_vertex_buffer(&vertices);
    c.kinc_g4_set_index_buffer(&indices);
    c.kinc_g4_draw_indexed_vertices();
    c.kinc_g4_end(0);
    _ = c.kinc_g4_swap_buffers();
}

// Tell zig to find main elsewhere
pub extern fn main(argc: c_int, argv: [*c][*c]const u8) callconv(.C) c_int;

// Export so the LLVM linker can find it (instead of it accidentally being linked before LLVM can find it)
export fn kickstart(argc: c_int, argv: [*c][*c]const u8) callconv(.C) c_int {
    _ = argc;
    _ = argv;

    _ = c.kinc_init("Shader", 1-24, 768, null, null);
    c.kinc_set_update_callback(&update, null);
    // In the original test, the shaders are loaded in a separate function
    // and the "allocator" is a buffer allocator to a chunk of memory.
    // Instead, the @embedFile builtin is used, which eliminates the need to allocate memory or load a file at runtime.
    const vertexShaderCode = @embedFile("shader.frag.glsl");
    c.kinc_g4_shader_init(&vertex_shader, vertexShaderCode.ptr, vertexShaderCode.len, c.KINC_G4_SHADER_TYPE_VERTEX);
    const fragmentShaderCode = @embedFile("shader.frag.glsl");
    c.kinc_g4_shader_init(&fragment_shader, fragmentShaderCode.ptr, fragmentShaderCode.len, c.KINC_G4_SHADER_TYPE_FRAGMENT);


    var structure: c.kinc_g4_vertex_structure_t = undefined;
    c.kinc_g4_vertex_structure_init(&structure);
    c.kinc_g4_vertex_structure_add(&structure, "pos", c.KINC_G4_VERTEX_DATA_F32_3X);
    c.kinc_g4_pipeline_init(&pipeline);
    pipeline.vertex_shader = &vertex_shader;
    pipeline.fragment_shader = &fragment_shader;
    pipeline.input_layout[0] = &structure;
    pipeline.input_layout[1] = null;
    c.kinc_g4_pipeline_compile(&pipeline);
    c.kinc_g4_vertex_buffer_init(&vertices, 3, &structure, c.KINC_G4_USAGE_STATIC, 0);
    {
        const v: *[9]f32 = @ptrCast(c.kinc_g4_vertex_buffer_lock_all(&vertices));
        v.* = [9]f32 {
            -1, -1, 0.5,
            1, -1, 0.5,
            -1, 1, 0.5,
        };
        c.kinc_g4_vertex_buffer_unlock_all(&vertices);
    }
    c.kinc_g4_index_buffer_init(&indices, 3, c.KINC_G4_INDEX_BUFFER_FORMAT_16BIT, c.KINC_G4_USAGE_STATIC);
    {
        const i: *[3]u16 = @alignCast(@ptrCast(c.kinc_g4_index_buffer_lock_all(&indices)));
        i.* = [3]u16{0, 1, 2};
        c.kinc_g4_index_buffer_unlock_all(&indices);
    }

    c.kinc_start();
    return 0;
}
