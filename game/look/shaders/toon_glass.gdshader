shader_type spatial;
// Dark glass with a sky sheen. On facades, some windows light up at night:
// `lit_share` of them, picked by the window's place so it never flickers.
#include "res://game/look/shaders/toon.gdshaderinc"

instance uniform float lit_share : instance_index(1) = 0.0;
uniform vec3 sheen : source_color = vec3(0.55, 0.62, 0.85);
uniform vec3 warm : source_color = vec3(1.0, 0.82, 0.54);
uniform vec3 cool : source_color = vec3(0.66, 0.85, 1.0);

varying flat vec3 origin;
varying flat float which;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	// Each window is its own instance (or its own model), so its origin
	// picks whether it's lit.
	origin = MODEL_MATRIX[3].xyz;
	which = float(INSTANCE_ID);
}

void fragment() {
	vec3 base = texture(palette, UV).rgb;
	float facing = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = base;
	ROUGHNESS = 0.32;
	SPECULAR = 0.3;
	vec3 sky = sheen * smoothstep(0.3, 1.0, facing) * 0.35;
	vec2 cell = floor(vec2(origin.x * 0.7 + origin.z * 1.3 + which * 1.618, origin.y * 0.5 + origin.z * 0.31 + which));
	float h = hash(cell);
	float on = step(h, lit_share) * night;
	vec3 lamp = mix(warm, cool, step(0.82, hash(cell + 7.0)));
	EMISSION = sky + lamp * on * 1.6;
}
