shader_type spatial;
// Flat palette swatches: most of every model.
#include "res://game/look/shaders/toon.gdshaderinc"

void fragment() {
	ALBEDO = texture(palette, UV).rgb * COLOR.rgb;
	ROUGHNESS = 0.9;
}
