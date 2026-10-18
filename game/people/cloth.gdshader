// All City's real clothes and the skin around them (Person's wardrobe, fitted
// by tools/blender/wardrobe.py): each piece one colour in the game's toon
// light, with a little wander in the cloth so it isn't flat paint. Ribbed
// knit (the hem and the cuffs) gets fine stripes. Works from the rest pose
// baked by Person.bake (CUSTOM0), so it needs no UVs and sticks to a moving
// body. Some pieces are single sheets, so both sides are drawn and the inside
// is darker.
shader_type spatial;
render_mode blend_mix, cull_disabled;
#include "res://game/look/shaders/toon.gdshaderinc"

uniform vec3 color : source_color = vec3(0.3, 0.4, 0.8);
// 0 plain cloth, 1 ribbed knit, 2 skin or anything else that stays flat.
uniform int kind = 0;
// How much the colour wanders over the cloth.
uniform float wander = 0.07;

varying vec3 rest;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	rest = CUSTOM0.xyz;
}

void fragment() {
	vec3 c = color;
	if (kind != 2) {
		float n = noise3(rest * 34.0) * 0.6 + noise3(rest * 91.0) * 0.4;
		c *= 1.0 + (n - 0.5) * wander;
	}
	if (kind == 1) {
		// Ribs round the hem, and round each wrist.
		bool cuff = abs(rest.x) > 0.42;
		float a = cuff ? atan(rest.y - 1.44, rest.z) : atan(rest.x, rest.z);
		float ribs = cuff ? 18.0 : 44.0;
		float s = smoothstep(0.3, 0.7, abs(fract(a / 6.2831853 * ribs) - 0.5) * 2.0);
		c *= 0.84 + 0.16 * s;
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
		c *= 0.72;
	}
	ALBEDO = c;
	ROUGHNESS = 0.9;
}
