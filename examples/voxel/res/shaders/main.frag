#version 450

layout(location = 0) in vec3 f_pos;

layout(location = 0) out vec4 color;

const int permutations[256] = int[] (
    144, 219, 232, 110, 171, 202, 50,  242, 55,  148, 87,  6,   12,  152, 143, 21,
    27,  195, 180, 249, 79,  139, 134, 98,  103, 37,  41,  125, 213, 48,  159, 160,
    10,  46,  128, 157, 236, 181, 124, 168, 251, 184, 19,  149, 54,  189, 61,  127,
    138, 105, 16,  145, 76,  210, 113, 169, 94,  252, 255, 158, 246, 156, 175, 65,
    203, 64,  225, 18,  17,  142, 30,  226, 71,  137, 118, 13,  216, 59,  126, 116,
    194, 186, 174, 45,  234, 97,  220, 217, 206, 235, 182, 170, 153, 106, 4,   114,
    166, 237, 108, 7,   36,  26,  177, 223, 243, 163, 164, 141, 66,  212, 28,  197,
    86,  240, 63,  132, 211, 227, 57,  104, 0,   72,  39,  58,  123, 221, 2,   228,
    62,  214, 229, 218, 99,  101, 112, 11,  207, 75,  32,  47,  196, 68,  42,  34,
    92,  85,  190, 43,  135, 154, 247, 173, 215, 80,  15,  90,  131, 84,  31,  51,
    187, 230, 172, 24,  40,  198, 115, 222, 8,   14,  60,  29,  23,  53,  204, 73,
    25,  9,   136, 117, 130, 241, 83,  74,  248, 5,   70,  208, 201, 82,  38,  147,
    56,  81,  183, 52,  121, 185, 1,   253, 91,  49,  96,  67,  111, 233, 188, 179,
    151, 119, 109, 95,  254, 167, 77,  176, 122, 44,  93,  238, 35,  245, 165, 205,
    200, 146, 239, 161, 100, 88,  209, 244, 120, 3,   231, 102, 193, 78,  155, 162,
    140, 20,  191, 199, 150, 224, 133, 178, 250, 89,  33,  129, 22,  69,  107, 192
);

float pixel_res = 3;
float epsilon = 0.0001;

int wrapping_ls(int value, int shift)
{
	int trunc_shift = shift & 31;

	int overflow = value >> (32 - trunc_shift);
	int product = value << trunc_shift;

	return overflow | product;
}

int wrapping_rs(int value, int shift)
{
	return wrapping_ls(value, 31 - shift);
}

vec3 random_color(int seed, int x, int y, int z)
{
	int value = seed;
	for(int i = 0; i < 2; i++)
	{
		value = wrapping_ls(value, permutations[(value * x + value) & 255]);
		value += x * 7101 + 180121;
		value ^= permutations[value & 255];
		value = wrapping_ls(value, permutations[(value * y + value) & 255]);
		value += y * 2011 + 735013;
		value ^= permutations[value & 255];
		value = wrapping_ls(value, permutations[(value * z + value) & 255]);
		value += z * 2317 + 678477;
		value ^= permutations[value & 255];
	}

	int ri = permutations[wrapping_rs(value, y + z) & 255];
	int gi = permutations[wrapping_rs(value, x + z) & 255];
	int bi = permutations[wrapping_rs(value, x + y) & 255];

	return vec3(float (ri) / 255, float (gi) / 255, float (bi) / 255);
}

void main()
{
	vec3 step_pos = f_pos * pixel_res;

	int sr = int (floor(step_pos.x - epsilon));
	int sg = int (floor(step_pos.y - epsilon));
	int sb = int (floor(step_pos.z - epsilon));

	vec3 base = vec3(0.15, 0.75, 0.1);
	vec3 rand = random_color(909, sr, sg, sb);

	vec3 weighted_rand = vec3(rand.x * 0.1, rand.y * 0.2, rand.z * 0.1);

	vec3 col = base + weighted_rand;

	color = vec4(col, 1);
}
