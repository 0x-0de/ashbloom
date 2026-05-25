#version 450

layout(location = 0) in vec3 f_pos;
layout(location = 1) flat in uint f_fac;

layout(location = 0) out vec4 color;

void main()
{
	vec3 col;

	switch(f_fac)
	{
		case 0:
			col = vec3(1, 0.25, 0.25);
			break;
		case 1:
			col = vec3(0.25, 1, 0.25);
			break;
		case 2:
			col = vec3(0.25, 0.25, 1);
			break;
		case 3:
			col = vec3(1, 1, 0.25);
			break;
		case 4:
			col = vec3(1, 0.25, 1);
			break;
		case 5:
			col = vec3(0.25, 1, 1);
			break;
	}

	color = vec4(col, 1);
}
