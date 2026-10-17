shader_type spatial;
// The ink line on Mobile: silhouettes from the depth only.
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;
#include "res://game/look/shaders/ink.gdshaderinc"
