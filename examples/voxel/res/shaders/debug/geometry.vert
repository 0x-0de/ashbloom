#version 450
layout(location = 0) in vec2 pos;

layout(location = 0) out vec2 f_pos;

layout(binding = 0) uniform DebugGeometryModelView
{
	mat4 projection;
	mat4 view;
} model_view;

void main()
{
	f_pos = pos;
	gl_Position = model_view.projection * model_view.view * vec4(pos, 0, 1);
}
