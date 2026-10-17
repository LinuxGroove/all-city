shader_type spatial;
// One flat colour in the game's light: ground, roofs and anything the
// palette texture doesn't reach.
#include "res://game/look/shaders/toon.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.6);

void fragment() {
	ALBEDO = albedo * COLOR.rgb;
	ROUGHNESS = 0.9;
}
