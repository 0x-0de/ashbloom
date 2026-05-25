
#version 450

layout(location = 0) in vec3 f_pos;
layout(location = 1) flat in uint f_fac;

layout(location = 0) out uvec4 color;

void main()
{
	vec3 col;

	uint x = uint (floor(f_pos.x));
	uint y = uint (floor(f_pos.y));
	uint z = uint (floor(f_pos.z));

	uint loc = (f_fac << 24) | (x << 16) | (y << 8) | z;

	color = uvec4(loc, 0, 0, 1);
}

