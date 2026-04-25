#version 450

layout(location = 0) flat in int f_draw_mode;
layout(location = 1) in vec2 f_pos;
layout(location = 2) in vec2 f_draw_pos;
layout(location = 3) in vec4 f_cut_bounds;
layout(location = 4) in vec4 f_coords;

layout(location = 0) out vec4 color;

layout(binding = 1) uniform sampler2D tex_atlas;

void main()
{
    if(!(f_draw_pos.x >= f_cut_bounds.x && f_draw_pos.y >= f_cut_bounds.y
    && f_draw_pos.x < f_cut_bounds.x + f_cut_bounds.z && f_draw_pos.y < f_cut_bounds.y + f_cut_bounds.w))
        discard;
    
    vec2 tex_coords = vec2(f_pos.x * f_coords.z + f_coords.x, f_pos.y * f_coords.w + f_coords.y);

    switch(f_draw_mode)
    {
        case 0:
            color = vec4(1, 1, 1, 1);
            break;
        case 1:
            color = f_coords;
            break;
        case 2:
        {
            vec4 t = texture(tex_atlas, tex_coords);
            if(t.a == 0) discard;
            color = t;
        }
            break;
        case 3:
        {
            vec4 t = texture(tex_atlas, tex_coords);
            if(t.a == 0) discard;
            color = t;
        }
            break;
    }
}
