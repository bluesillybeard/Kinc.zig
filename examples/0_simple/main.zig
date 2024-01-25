// This is the same as the "Empty" test in the original Kinc sources.
// It has been transformed to do things "the zig way" as much as possible
// while being functionally identical to the original.

const std = @import("std");

// TODO: see if usingnamespace works or not
const c = @cImport({
    @cInclude("kinc/graphics4/graphics.h");
    @cInclude("kinc/graphics4/indexbuffer.h");
    @cInclude("kinc/graphics4/pipeline.h");
    @cInclude("kinc/graphics4/shader.h");
    @cInclude("kinc/graphics4/vertexbuffer.h");
    @cInclude("kinc/system.h");
});

// The original code worked something like this,
// However this is a terrible way to do it and very un-ziglike, so it's done a different way

// var vertex_shader: c.kinc_g4_shader_t = .{};
// var fragment_shader: c.kinc_g4_shader_t = .{};
// var pipeline: c.kinc_g4_pipeline_t = .{};
// var vertices: c.kinc_g4_vertex_buffer_t = .{};
// var indices: c.kinc_g4_index_buffer_t = .{};

// This is the data that persists throughout the application
const Data = struct {
    pipeline: c.kinc_g4_pipeline_t,
    vertices: c.kinc_g4_vertex_buffer_t,
    indices: c.kinc_g4_index_buffer_t,
};

fn update(_data: ?*anyopaque) callconv(.C) void {
    // cast the opaque pointer to Data.
    const data: *Data = @alignCast(@ptrCast(_data));

    c.kinc_g4_begin(0);
    c.kinc_g4_clear(c.KINC_G4_CLEAR_COLOR, 0, 0.0, 0);
    c.kinc_g4_set_pipeline(&data.pipeline);
    c.kinc_g4_set_vertex_buffer(&data.vertices);
    c.kinc_g4_set_index_buffer(&data.indices);
    c.kinc_g4_draw_indexed_vertices();
    c.kinc_g4_end(0);
    _ = c.kinc_g4_swap_buffers();
}

pub fn main() void {
    var vertex_shader: c.kinc_g4_shader_t = .{};
    var fragment_shader: c.kinc_g4_shader_t = .{};
    var data: Data = .{
        .indices = .{},
        .vertices = .{},
        .pipeline = .{},
    };
    _ = c.kinc_init("Shader", 1024, 768, null, null);
    c.kinc_set_update_callback(&update, &data);
    // In the original test, the shaders are loaded in a separate function
    // and the "allocator" is a buffer allocator to a chunk of memory.
    // Instead, the @embedFile builtin is used, which eliminates the need to allocate memory or load a file at runtime.
    const vertexShaderCode = @embedFile("shaderOut/shader.vert");
    c.kinc_g4_shader_init(&vertex_shader, vertexShaderCode.ptr, vertexShaderCode.len, c.KINC_G4_SHADER_TYPE_VERTEX);
    const fragmentShaderCode = @embedFile("shaderOut/shader.frag");
    c.kinc_g4_shader_init(&fragment_shader, fragmentShaderCode.ptr, fragmentShaderCode.len, c.KINC_G4_SHADER_TYPE_FRAGMENT);


    var structure: c.kinc_g4_vertex_structure_t = .{};
    c.kinc_g4_vertex_structure_init(&structure);
    c.kinc_g4_vertex_structure_add(&structure, "pos", c.KINC_G4_VERTEX_DATA_F32_3X);
    c.kinc_g4_pipeline_init(&data.pipeline);
    data.pipeline.vertex_shader = &vertex_shader;
    data.pipeline.fragment_shader = &fragment_shader;
    data.pipeline.input_layout[0] = &structure;
    data.pipeline.input_layout[1] = null;
    c.kinc_g4_pipeline_compile(&data.pipeline);
    c.kinc_g4_vertex_buffer_init(&data.vertices, 3, &structure, c.KINC_G4_USAGE_STATIC, 0);
    {
        const v: *[9]f32 = @ptrCast(c.kinc_g4_vertex_buffer_lock_all(&data.vertices));
        v.* = [9]f32 {
            -1, -1, 0.5,
            1, -1, 0.5,
            -1, 1, 0.5,
        };
        c.kinc_g4_vertex_buffer_unlock_all(&data.vertices);
    }
    c.kinc_g4_index_buffer_init(&data.indices, 3, c.KINC_G4_INDEX_BUFFER_FORMAT_16BIT, c.KINC_G4_USAGE_STATIC);
    {
        const i: *[3]u16 = @alignCast(@ptrCast(c.kinc_g4_index_buffer_lock_all(&data.indices)));
        i.* = [3]u16{0, 1, 2};
        c.kinc_g4_index_buffer_unlock_all(&data.indices);
    }

    c.kinc_start();
}
