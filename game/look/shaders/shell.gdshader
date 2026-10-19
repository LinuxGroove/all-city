shader_type spatial;
// A building's shell: the plain walls behind its facade, which is all a
// far building shows. Windows are drawn on it a bay and a storey at a time
// (UV is metres along the wall and metres down from the roof; UV2 is the
// building's seed and its storeys), and some light up at night. The wall
// colour is the vertex colour.
#include "res://game/look/shaders/toon.gdshaderinc"

uniform vec3 glass : source_color = vec3(0.12, 0.2, 0.31);
uniform vec3 warm : source_color = vec3(1.0, 0.82, 0.54);
uniform float lit_share = 0.35;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 cell = floor(UV / vec2(2.0, 3.0));
	vec2 f = fract(UV / vec2(2.0, 3.0));
	float aa = fwidth(UV.x) * 0.5;
	float window = smoothstep(0.24 - aa, 0.24 + aa, f.x) * (1.0 - smoothstep(0.76 - aa, 0.76 + aa, f.x))
			* smoothstep(0.2, 0.22, f.y) * (1.0 - smoothstep(0.72, 0.74, f.y));
	// The ground floor (and the wall below it on a slope) gets none, nor the
	// band above the top storey.
	window *= step(cell.y + 1.5, UV2.y) * step(0.0, cell.y);
	ALBEDO = mix(COLOR.rgb, glass, window);
	ROUGHNESS = 0.9;
	float on = step(hash(cell + vec2(UV2.x, 0.0)), lit_share) * night * window;
	EMISSION = warm * on * 1.2;
}
