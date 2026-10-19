// The ink line: a full-screen pass that draws dark lines where the depth
// jumps (silhouettes) and, on Forward+, where the normal turns (creases).
// Lines thin out with distance so the far town stays clean.

#ifdef INK_NORMALS
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
#endif
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 ink : source_color = vec3(0.078, 0.071, 0.11);
uniform float width = 1.25;
uniform float depth_edge = 0.08;
uniform float fade_from = 45.0;
uniform float fade_to = 140.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

float lin(float d, mat4 inv_proj, vec2 uv) {
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

void fragment() {
	vec2 px = width / VIEWPORT_SIZE * (VIEWPORT_SIZE.y / 720.0);
	vec2 uv = SCREEN_UV;
	// The depth buffer is linear across a flat surface on screen, so its
	// second difference is zero on any plane however steeply it's seen, and
	// large only where one thing stands in front of another.
	float c = texture(depth_tex, uv).r;
	float l = texture(depth_tex, uv - vec2(px.x, 0.0)).r;
	float r = texture(depth_tex, uv + vec2(px.x, 0.0)).r;
	float u = texture(depth_tex, uv - vec2(0.0, px.y)).r;
	float d = texture(depth_tex, uv + vec2(0.0, px.y)).r;
	float lap = max(abs(l + r - 2.0 * c), abs(u + d - 2.0 * c)) / max(max(c, max(max(l, r), max(u, d))), 1e-7);
	float edge = smoothstep(depth_edge, depth_edge * 2.0, lap);
	float nearest = lin(max(c, max(max(l, r), max(u, d))), INV_PROJECTION_MATRIX, uv);
#ifdef INK_NORMALS
	vec3 nc = normalize(texture(normal_tex, uv).xyz * 2.0 - 1.0);
	vec3 nl = normalize(texture(normal_tex, uv - vec2(px.x, 0.0)).xyz * 2.0 - 1.0);
	vec3 nu = normalize(texture(normal_tex, uv - vec2(0.0, px.y)).xyz * 2.0 - 1.0);
	float crease = max(1.0 - dot(nc, nl), 1.0 - dot(nc, nu));
	edge = max(edge, smoothstep(0.3, 0.55, crease) * 0.75);
#endif
	float fade = 1.0 - smoothstep(fade_from, fade_to, nearest);
	ALBEDO = ink;
	ALPHA = edge * fade;
}
