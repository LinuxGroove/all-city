shader_type canvas_item;
// The town map's ground: the Cartographer's cover picture (R roads, G
// footways and paved areas, B parks, A rail ballast) as flat colours with
// crisp edges at any zoom, light streets on a dark town.

uniform vec4 base : source_color = vec4(0.125, 0.115, 0.17, 1.0);
uniform vec4 walk : source_color = vec4(0.2, 0.185, 0.27, 1.0);
uniform vec4 road : source_color = vec4(0.86, 0.81, 0.7, 1.0);
uniform vec4 green : source_color = vec4(0.17, 0.36, 0.23, 1.0);
uniform vec4 ballast : source_color = vec4(0.33, 0.3, 0.42, 1.0);

float edge(float v) {
	float w = fwidth(v) * 0.75 + 0.06;
	return smoothstep(0.5 - w, 0.5 + w, v);
}

void fragment() {
	vec4 m = texture(TEXTURE, UV);
	vec3 c = base.rgb;
	c = mix(c, green.rgb, edge(m.b));
	c = mix(c, ballast.rgb, edge(m.a));
	c = mix(c, walk.rgb, edge(m.g));
	c = mix(c, road.rgb, edge(m.r));
	COLOR = vec4(c, 1.0);
}
