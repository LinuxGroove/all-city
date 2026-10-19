shader_type spatial;
// The ink line on Forward+: silhouettes from the depth and creases from the
// normals.
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;
#define INK_NORMALS
#include "res://game/look/shaders/ink.gdshaderinc"
