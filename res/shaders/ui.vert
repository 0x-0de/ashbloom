#version 450

#define QUAD_POS 0
#define QUAD_SIZE 1

vec2 positions[6] = vec2[](
    vec2(QUAD_POS, QUAD_POS),
    vec2(QUAD_POS + QUAD_SIZE, QUAD_POS),
    vec2(QUAD_POS + QUAD_SIZE, QUAD_POS + QUAD_SIZE),
    vec2(QUAD_POS, QUAD_POS),
    vec2(QUAD_POS + QUAD_SIZE, QUAD_POS + QUAD_SIZE),
    vec2(QUAD_POS, QUAD_POS + QUAD_SIZE)
);

layout(location = 0) in float draw_mode;
layout(location = 1) in vec4 draw_bounds;
layout(location = 2) in vec4 cut_bounds;
layout(location = 3) in vec4 coords;

layout(location = 0) out int f_draw_mode;
layout(location = 1) out vec2 f_pos;
layout(location = 2) out vec2 f_draw_pos;
layout(location = 3) out vec4 f_cut_bounds;
layout(location = 4) out vec4 f_coords;

layout(binding = 0) uniform Transformations
{
    mat4 projection;
} ubo;

void main()
{
    f_draw_mode = int (round(draw_mode));

    f_pos = positions[gl_VertexIndex];
    f_coords = coords;

    vec2 transformed_pos = positions[gl_VertexIndex] * draw_bounds.zw + draw_bounds.xy;
    f_draw_pos = transformed_pos;

    f_cut_bounds = cut_bounds;

    gl_Position = ubo.projection * vec4(transformed_pos, 0, 1);
}