shader_type spatial;
// The ground of a town tile: the Cartographer's cover picture (R roads,
// G footways, B parks, A rail ballast) as flat palette colours with crisp
// edges, over the town's paving. UV runs 0 to 1 across the tile.
#include "res://game/look/shaders/toon.gdshaderinc"

uniform sampler2D cover : filter_linear, repeat_disable;
uniform vec3 base : source_color = vec3(0.65, 0.6, 0.56);
uniform vec3 walk : source_color = vec3(0.73, 0.7, 0.68);
uniform vec3 road : source_color = vec3(0.17, 0.16, 0.2);
uniform vec3 green : source_color = vec3(0.31, 0.56, 0.29);
uniform vec3 ballast : source_color = vec3(0.42, 0.4, 0.44);
uniform float tile_size = 256.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// A mask band's edge, sharp at any distance.
float edge(float v) {
	float w = fwidth(v) * 0.75 + 0.03;
	return smoothstep(0.5 - w, 0.5 + w, v);
}

void fragment() {
	vec4 m = texture(cover, UV);
	vec2 p = UV * tile_size;
	// Paving slabs: faint joints that fade out with distance.
	vec2 slab = abs(fract(p / vec2(1.2, 0.9)) - 0.5);
	float fade = 1.0 - smoothstep(0.02, 0.08, fwidth(p.x));
	float joint = smoothstep(0.455, 0.49, max(slab.x, slab.y)) * fade;
	vec3 c = base * (1.0 - joint * 0.12);
	vec3 path = walk * (1.0 - joint * 0.16);
	c = mix(c, green * (0.94 + 0.08 * hash(floor(p * 0.5))), edge(m.b));
	c = mix(c, ballast * (0.85 + 0.25 * hash(floor(p * 4.0))), edge(m.a));
	c = mix(c, path, edge(m.g));
	c = mix(c, road * (0.92 + 0.12 * hash(floor(p * 3.0))), edge(m.r));
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
