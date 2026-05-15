#version 450

layout(location = 0) in vec3 f_pos;

layout(location = 0) out vec4 color;

void main()
{
	color = vec4(f_pos, 1);
}
