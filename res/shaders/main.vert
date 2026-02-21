#version 450

layout(location = 0) in vec2 v_pos;
layout(location = 1) in vec3 v_col;
layout(location = 2) in vec2 v_tex;

layout(location = 0) out vec3 f_col;
layout(location = 1) out vec2 f_tex;

layout(binding = 0) uniform Transformations
{
    mat4 transform;
    mat4 projection;
} ubo;

void main()
{
    f_col = v_col;
    f_tex = v_tex;
    gl_Position = ubo.projection * ubo.transform * vec4(v_pos, 0.0, 1.0);
}