#version 450
layout(location = 0) in vec3 pos;

layout(location = 0) out vec3 f_pos;

layout(binding = 0) uniform ModelView
{
	mat4 projection;
	mat4 view;
} model_view;

void main()
{
	f_pos = pos;
	gl_Position = model_view.projection * model_view.view * vec4(pos, 1);
}
