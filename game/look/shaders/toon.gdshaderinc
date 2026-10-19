// All City's light: three flat bands (shadow, half and lit) with a rim on
// the edges facing the light, so shapes read as bold colour, not gradients.
// Included by every role's shader.

global uniform float night;
global uniform float steady;

uniform sampler2D palette : source_color, filter_nearest;

float toon_bands(float ndl) {
	return smoothstep(-0.02, 0.04, ndl) * 0.5 + smoothstep(0.42, 0.5, ndl) * 0.5;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = toon_bands(ndl);
	if (LIGHT_IS_DIRECTIONAL) {
		lit *= smoothstep(0.35, 0.55, ATTENUATION);
	} else {
		// Lamps light in two flat rings: a bright pool and a soft edge.
		lit *= smoothstep(0.03, 0.06, ATTENUATION) * 0.45 + smoothstep(0.22, 0.27, ATTENUATION) * 0.55;
	}
	float rim = smoothstep(0.62, 0.7, 1.0 - max(dot(NORMAL, VIEW), 0.0)) * smoothstep(-0.1, 0.25, ndl);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * (lit + rim * 0.35 * lit);
}

// Instance uniforms share one slot list per node across all its materials,
// so each has a fixed index: 0 tint (Wall), 1 lit_share (Glass), 2 power
// (Glow).
