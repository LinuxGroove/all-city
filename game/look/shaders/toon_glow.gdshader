shader_type spatial;
// Lamps, neon and signals: their own colour by day, bright and blooming at
// night.
#include "res://game/look/shaders/toon.gdshaderinc"

instance uniform float power : instance_index(2) = 1.0;

void fragment() {
	vec3 c = texture(palette, UV).rgb * COLOR.rgb;
	ALBEDO = c * 0.6;
	EMISSION = c * power * mix(0.7, 2.8, night);
}
