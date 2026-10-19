shader_type spatial;
// A swatch tinted per building, per car or per can: the multimesh's
// instance colour (COLOR) or the node's `tint`.
#include "res://game/look/shaders/toon.gdshaderinc"

instance uniform vec4 tint : source_color, instance_index(0) = vec4(1.0);

void fragment() {
	ALBEDO = texture(palette, UV).rgb * COLOR.rgb * tint.rgb;
	ROUGHNESS = 0.9;
}
