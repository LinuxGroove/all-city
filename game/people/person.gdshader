// All City's people: writers in hoodies and cargo trousers, the Buff's
// crews in hi-vis, Civic's officers and the town's passers-by, drawn on
// Quaternius' Universal Base Characters in the game's toon light. Works
// from the rest pose baked by Person.bake (CUSTOM0 the position, CUSTOM1
// how much of each vertex is head, hand and foot), so it needs no UVs and
// sticks to a moving body. The rest pose is a T-pose facing +z, feet at 0.
shader_type spatial;
render_mode blend_mix, cull_back;
#include "res://game/look/shaders/toon.gdshaderinc"

// 0 writer, 1 the Buff, 2 Civic, 3 passer-by.
uniform int outfit = 0;
uniform vec3 main_color : source_color = vec3(0.2, 0.22, 0.3);
uniform vec3 accent : source_color = vec3(1.0, 0.31, 0.64);
uniform vec3 legs : source_color = vec3(0.24, 0.24, 0.22);
uniform vec3 skin : source_color = vec3(0.78, 0.56, 0.44);
uniform vec3 shoe : source_color = vec3(0.92, 0.9, 0.86);
// Where the hands start along the arms (the female body's are shorter).
uniform float wrist = 0.66;

varying vec3 rest;
varying vec3 region;

float band(float v, float at, float half_width) {
	return smoothstep(half_width + 0.008, half_width, abs(v - at));
}

void vertex() {
	rest = CUSTOM0.xyz;
	region = CUSTOM1.xyz;
	vec3 p = rest;
	float ax = abs(p.x);
	float arm = smoothstep(0.24, 0.3, ax) * step(1.2, p.y);
	float bulk = 0.0;
	if (outfit == 0) {
		// A hoodie: loose body and sleeves, the hood bunched behind the neck,
		// ribbed cuffs and hem; cargo pockets on the thighs.
		float top = step(0.92, p.y) * (1.0 - region.x) * step(ax, wrist - 0.06);
		bulk += top * 0.012;
		bulk += smoothstep(0.1, 0.0, length(vec2(p.x, (p.y - 1.46) * 1.4))) * step(p.z, 0.0) * 0.05;
		bulk += band(p.y, 0.62, 0.07) * smoothstep(0.08, 0.12, ax) * step(ax, 0.2) * 0.014;
	} else if (outfit == 1 || outfit == 2) {
		bulk += step(0.92, p.y) * (1.0 - region.x) * step(ax, wrist - 0.06) * 0.008;
	}
	VERTEX += NORMAL * bulk;
}

void fragment() {
	vec3 p = rest;
	float head = region.x;
	float hand = region.y;
	float foot = region.z;
	float ax = abs(p.x);
	float arm = smoothstep(0.24, 0.3, ax) * step(1.2, p.y);
	float upper = step(0.95, p.y);
	vec3 c = mix(legs, main_color, upper);
	if (outfit == 0) {
		// Hoodie with a pouch, drawstrings and a stripe down the sleeves.
		float pouch = step(ax, 0.13) * step(1.0, p.y) * step(p.y, 1.16) * step(0.02, p.z);
		c = mix(c, main_color * 0.82, pouch);
		float strings = band(ax, 0.045, 0.006) * step(1.3, p.y) * step(p.y, 1.47) * step(0.0, p.z);
		c = mix(c, accent, strings);
		float stripe = band(p.z, 0.04, 0.02) * arm * step(ax, wrist - 0.08);
		c = mix(c, accent, stripe);
		float cuff = band(ax, wrist - 0.075, 0.02) * arm;
		float hem = band(p.y, 0.97, 0.022) * step(ax, 0.26);
		c = mix(c, main_color * 0.7, max(cuff, hem));
		float pocket = band(p.y, 0.62, 0.07) * smoothstep(0.08, 0.12, ax) * step(ax, 0.2);
		c = mix(c, legs * 0.78, pocket);
	} else if (outfit == 1) {
		// The Buff: a hi-vis jacket with two silver bands, dark trousers
		// with bands at the shins.
		c = mix(legs, main_color, upper);
		float bands = (band(p.y, 1.08, 0.022) + band(p.y, 1.2, 0.022)) * upper * step(ax, 0.26);
		bands += band(ax, 0.45, 0.022) * arm;
		bands += band(p.y, 0.3, 0.02) * (1.0 - upper);
		c = mix(c, vec3(0.82, 0.84, 0.88), clamp(bands, 0.0, 1.0));
	} else if (outfit == 2) {
		// Civic: a navy uniform under a vest in civic blue and yellow check.
		c = mix(legs, main_color, upper);
		float vest = upper * step(ax, 0.24) * step(p.y, 1.42);
		float check = step(0.5, fract(p.x * 12.0 + 0.25)) * band(p.y, 1.02, 0.03);
		c = mix(c, accent, vest);
		c = mix(c, vec3(0.95, 0.78, 0.25), check * vest);
	} else {
		// A passer-by: a T-shirt and jeans.
		c = mix(legs, main_color, upper);
		c = mix(c, skin, smoothstep(0.42, 0.44, ax) * arm);
	}
	c = mix(c, skin, head);
	c = mix(c, skin, hand);
	c = mix(c, shoe, foot);
	ALBEDO = c;
	ROUGHNESS = 0.9;
}
