shader_type spatial;
// The sea and lakes: flat water in the palette's blue with slow bands of
// light, so it reads as water from a roof without moving much.
#include "res://game/look/shaders/toon.gdshaderinc"

uniform vec3 deep : source_color = vec3(0.16, 0.36, 0.56);
uniform vec3 crest : source_color = vec3(0.55, 0.78, 0.92);

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world.xz;
	float w = sin(p.x * 0.11 + p.y * 0.07 + TIME * 0.35) + sin(p.x * -0.05 + p.y * 0.13 - TIME * 0.27);
	float band = smoothstep(1.45, 1.6, w) * (1.0 - smoothstep(0.02, 0.2, fwidth(p.x)));
	ALBEDO = mix(deep, crest, band * 0.6);
	ROUGHNESS = 0.25;
	SPECULAR = 0.4;
}
