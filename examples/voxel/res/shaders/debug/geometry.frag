#version 450

layout(location = 0) in vec2 f_pos;

layout(location = 0) out vec4 color;

void main()
{
	color = vec4(f_pos, 0, 1);
}
