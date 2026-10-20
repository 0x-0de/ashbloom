#version 450
layout(location = 0) out vec4 color;

layout(location = 0) in vec3 f_color;

void main()
{
	color = vec4(f_color, 1);
}
