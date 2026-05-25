#version 450

layout(location = 0) in vec3 pos;
layout(location = 1) in uint fac;

layout(location = 0) out vec3 f_pos;
layout(location = 1) out uint f_fac;

layout(binding = 0) uniform ModelView
{
	mat4 projection;
	mat4 view;
} model_view;

void main()
{
	f_pos = pos;
	f_fac = fac;

	gl_Position = model_view.projection * model_view.view * vec4(pos, 1);
}
