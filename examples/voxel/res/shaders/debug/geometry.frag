#version 450

layout(location = 0) in vec3 f_pos;

layout(location = 0) out vec4 color;

float epsilon = 0.0001;

void main()
{
	float r = (f_pos.x - epsilon) - floor(f_pos.x - epsilon);
	float g = (f_pos.y - epsilon) - floor(f_pos.y - epsilon);
	float b = (f_pos.z - epsilon) - floor(f_pos.z - epsilon);

	color = vec4(r, g, b, 1);
}
