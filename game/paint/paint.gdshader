shader_type spatial;
// Paint on a wall: one quad per painted wall face, a couple of centimetres
// off it, drawing the letter kit's masks (fill and ink outline) in the
// crew's colours, in the town's toon light. Drips run down while the paint
// is wet; paint wears and pales as it ages towards its rank's life. While a
// writer is painting, only what the spray has reached shows, with the rest
// of the letters as a faint guide and dots for the way ahead.
//
// With Reduce flashing (the `steady` global) wet paint has no shine; the
// shine never flickers anyway, it only follows the view.
render_mode blend_mix, depth_draw_never, cull_back;

#include "res://game/look/shaders/toon.gdshaderinc"

uniform sampler2D fill_mask : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform sampler2D ink_mask : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec3 fill_colour : source_color = vec3(0.25, 0.95, 1.0);
uniform vec3 fill_colour2 : source_color = vec3(0.25, 0.95, 1.0);
uniform vec3 ink_colour : source_color = vec3(0.08, 0.07, 0.11);
// The quad's width over its height.
uniform float aspect = 2.0;
// Age over the rank's life: 0 fresh, 1 gone.
uniform float fade = 0.0;
// 1 just painted, 0 dry.
uniform float wet = 0.0;
// How far the outline strays (rushing).
uniform float wobble = 0.0;
// A shine along the letters' top edges (throw-ups).
uniform float bevel = 0.0;
uniform float seed = 0.0;
// Each drip: x, y (UV, where it starts), its length (in quad heights) and
// 1 when it already ran while painting (0 runs as the paint dries).
uniform vec4 drips[8];
uniform int drip_count = 0;
uniform float drip_width = 0.022;
// How far the drips that run as the paint dries have run, 0 to 1.
uniform float drip_run = 1.0;
// Painting in progress: painted up to this UV x, and around the nozzle.
uniform float reveal = 1.0;
uniform vec2 nozzle = vec2(-1.0);
// How strongly the unpainted letters and the way ahead show.
uniform float ghost = 0.0;
// The next points of the guide, in UV (x, y; vec4 because arrays of vec2
// don't reach the shader whole).
uniform vec4 ahead[6];
uniform int ahead_count = 0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	// Quad space: x and y in quad heights.
	vec2 p = vec2(uv.x * aspect, uv.y);
	if (wobble > 0.0) {
		uv += wobble * 0.01 * vec2(sin(p.y * 41.0 + seed) / aspect, sin(p.x * 33.0 + seed * 1.7));
	}
	float fill = texture(fill_mask, uv).r;
	float ink = texture(ink_mask, uv).r;
	float drip = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i < drip_count) {
			vec4 d = drips[i];
			vec2 top = vec2(d.x * aspect, d.y);
			float len = d.z * max(d.w, drip_run);
			float y = p.y - top.y;
			float taper = drip_width * (1.0 - 0.4 * clamp(y / max(d.z, 0.001), 0.0, 1.0));
			float stem = step(0.0, y) * step(y, len) * (1.0 - smoothstep(taper * 0.6, taper, abs(p.x - top.x)));
			float bulb = 1.0 - smoothstep(drip_width * 0.75, drip_width * 1.1, distance(p, top + vec2(0.0, len)));
			drip = max(drip, max(stem, bulb) * step(0.002, len));
		}
	}
	float painted = 1.0 - smoothstep(reveal - 0.01, reveal + 0.01, UV.x);
	if (nozzle.x >= 0.0) {
		painted = max(painted, 1.0 - smoothstep(0.06, 0.09, distance(p, vec2(nozzle.x * aspect, nozzle.y))));
	}
	vec3 paint = mix(fill_colour, fill_colour2, smoothstep(0.15, 0.75, UV.y));
	float f = max(fill, drip) * painted;
	float k = ink * painted;
	vec3 col = mix(ink_colour, paint, f);
	if (bevel > 0.0) {
		float above = texture(fill_mask, uv + vec2(-0.01 / aspect, -0.025)).r;
		col = mix(col, vec3(1.0), clamp(fill - above, 0.0, 1.0) * bevel * f);
	}
	float a = max(f, k);
	// Wear: patches go first, then it all pales.
	float weather = noise(p * 9.0 + seed) * 0.6 + noise(p * 31.0 + seed) * 0.4;
	float worn = smoothstep(weather - 0.08, weather + 0.08, fade * 0.75 - 0.15);
	a *= (1.0 - worn) * mix(1.0, 0.6, fade);
	col = mix(col, col * 0.75 + vec3(0.18), fade * 0.5);
	// The guide: the letters still to paint, faintly, and dots ahead.
	if (ghost > 0.0) {
		float rest = max(fill, ink) * (1.0 - painted) * ghost * 0.3;
		float dots = 0.0;
		for (int i = 0; i < 6; i++) {
			if (i < ahead_count) {
				float r = 0.022 - float(i) * 0.002;
				dots = max(dots, 1.0 - smoothstep(r, r + 0.008, distance(p, vec2(ahead[i].x * aspect, ahead[i].y))));
			}
		}
		float g = max(rest, dots * ghost * 0.85);
		col = mix(vec3(0.95, 0.94, 0.9), col, a / max(a + g * (1.0 - a), 0.001));
		a = a + g * (1.0 - a);
	}
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
	// Wet paint shines a little towards glancing views; never with Reduce flashing.
	float shine = wet * (1.0 - steady) * pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 2.0) * 0.3;
	EMISSION = paint * shine * f;
	ROUGHNESS = 0.9;
}
