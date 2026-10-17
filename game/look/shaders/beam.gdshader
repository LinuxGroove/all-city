shader_type spatial;
// A searchlight's beam through the haze: a cone drawn additive, brightest
// at the lamp and along its middle, fading out where it meets the ground.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform float steady;

uniform vec3 colour : source_color = vec3(1.0, 0.96, 0.86);
uniform float strength = 0.35;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

void fragment() {
	float edge = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	// A cylinder's UV.y runs 0 at the top (the lamp) to 1 at the end.
	float along = 1.0 - UV.y;
	// Fade where the beam meets what it lights, so there's no hard line.
	float scene = texture(depth_tex, SCREEN_UV).r;
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene, 1.0);
	float soft = clamp((VERTEX.z - sv.z / sv.w) / 1.5, 0.0, 1.0);
	ALBEDO = colour * strength * edge * (0.25 + along * 0.75) * soft;
}
