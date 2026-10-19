class_name Look
extends RefCounted
## The game's look: the toon materials every model's roles turn into, the
## ink line, and the light and sky for each time of day.
##
## Models come out of Blender with four material roles (see
## tools/blender/ackit.py): Palette, Wall, Glass and Glow. `material()` gives
## the shader for each, and `Kit` swaps them in when it loads a model.

const PALETTE := preload("res://assets/art/palette.png")
const SHADERS := {
	"Palette": preload("res://game/look/shaders/toon_palette.gdshader"),
	"Wall": preload("res://game/look/shaders/toon_wall.gdshader"),
	"Glass": preload("res://game/look/shaders/toon_glass.gdshader"),
	"Glow": preload("res://game/look/shaders/toon_glow.gdshader"),
}
const FLAT := preload("res://game/look/shaders/toon_flat.gdshader")
const BEAM := preload("res://game/look/shaders/beam.gdshader")
const INK := preload("res://game/look/shaders/ink.gdshader")
const INK_CREASES := preload("res://game/look/shaders/ink_creases.gdshader")

## Each time of day: the sun's angle and colour, the sky, the ambient light,
## the haze, and how far the night has come (lamps, lit windows).
const TIMES := {
	"day": {
		"sun_pitch": -52.0, "sun_yaw": -35.0, "sun": Color("fff1d6"), "sun_energy": 1.25,
		"top": Color("4f8fd8"), "horizon": Color("bfe0f2"), "ground": Color("5d5866"),
		"ambient": Color("a9b8d8"), "ambient_energy": 0.55, "fog": Color("c4d6e6"), "fog_density": 0.0016,
		"night": 0.0,
	},
	"dusk": {
		"sun_pitch": -16.0, "sun_yaw": -60.0, "sun": Color("ffa25c"), "sun_energy": 1.35,
		"top": Color("2b2a6b"), "horizon": Color("ff8a5c"), "ground": Color("2d2438"),
		"ambient": Color("8a76c8"), "ambient_energy": 0.62, "fog": Color("b37a98"), "fog_density": 0.0028,
		"night": 0.55,
	},
	"night": {
		"sun_pitch": -40.0, "sun_yaw": 120.0, "sun": Color("8fa8ff"), "sun_energy": 0.32,
		"top": Color("0c0f2a"), "horizon": Color("2d3170"), "ground": Color("141226"),
		"ambient": Color("6a62b8"), "ambient_energy": 0.7, "fog": Color("1f2350"), "fog_density": 0.003,
		"night": 1.0,
	},
}

## How far the night has come, as last set (0 day, 1 night).
static var night := 0.0
static var _materials := {}
static var _flats := {}


## The shader material for a role, shared by every model.
static func material(role: String) -> ShaderMaterial:
	if not SHADERS.has(role):
		role = "Palette"
	if not _materials.has(role):
		var m := ShaderMaterial.new()
		m.shader = SHADERS[role]
		m.set_shader_parameter("palette", PALETTE)
		_materials[role] = m
	return _materials[role]


## A flat colour in the game's light, shared per colour.
static func flat(colour: Color) -> ShaderMaterial:
	var key := colour.to_html()
	if not _flats.has(key):
		var m := ShaderMaterial.new()
		m.shader = FLAT
		m.set_shader_parameter("albedo", colour)
		_flats[key] = m
	return _flats[key]


## A searchlight's beam: a cone from the lamp (the node's origin) down its
## -y for `length` metres, spreading to `radius`.
static func beam(length: float, radius: float, colour := Color(1.0, 0.96, 0.86)) -> MeshInstance3D:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.08
	cone.bottom_radius = radius
	cone.height = length
	cone.cap_top = false
	cone.cap_bottom = false
	cone.radial_segments = 24
	cone.rings = 1
	var m := ShaderMaterial.new()
	m.shader = BEAM
	m.set_shader_parameter("colour", colour)
	cone.material = m
	var node := MeshInstance3D.new()
	node.name = "Beam"
	node.mesh = cone
	node.position.y = -length * 0.5
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Whether this renderer can draw creases as well as silhouettes.
static func has_creases() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


## A node that draws the ink line over everything a camera sees. Add it
## anywhere in the scene; it follows no transform.
static func ink() -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var m := ShaderMaterial.new()
	m.shader = INK_CREASES if has_creases() else INK
	m.render_priority = 10
	quad.material = m
	var node := MeshInstance3D.new()
	node.name = "Ink"
	node.mesh = quad
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 16384.0
	node.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	return node


## The environment for a time of day: a gradient sky, flat ambient light,
## haze for depth and bloom on the lamps.
static func environment(time := "dusk") -> Environment:
	var t: Dictionary = TIMES.get(time, TIMES.dusk)
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = t.top
	sky_mat.sky_horizon_color = t.horizon
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = t.ground
	sky_mat.ground_horizon_color = t.horizon.darkened(0.25)
	sky_mat.ground_curve = 0.05
	sky_mat.sun_angle_max = 8.0
	sky_mat.sun_curve = 0.08
	sky_mat.energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = t.ambient
	env.ambient_light_energy = t.ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = t.fog
	env.fog_density = t.fog_density
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.35
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	return env


## The sun (or the moon) for a time of day.
static func sun(time := "dusk") -> DirectionalLight3D:
	var t: Dictionary = TIMES.get(time, TIMES.dusk)
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = Vector3(t.sun_pitch, t.sun_yaw, 0)
	light.light_color = t.sun
	light.light_energy = t.sun_energy
	light.shadow_enabled = true
	light.shadow_bias = 0.04
	light.shadow_normal_bias = 1.2
	light.shadow_blur = 0.6
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_max_distance = 160.0
	return light


## Sets the time of day for every material at once (lamps and windows).
static func set_night(amount: float) -> void:
	night = amount
	RenderingServer.global_shader_parameter_set("night", amount)


## A scene's sky, sun and ink for a time of day, under `parent`.
static func dress(parent: Node, time := "dusk") -> void:
	var we := WorldEnvironment.new()
	we.name = "Sky"
	we.environment = environment(time)
	parent.add_child(we)
	parent.add_child(sun(time))
	parent.add_child(ink())
	set_night(float(TIMES.get(time, TIMES.dusk).night))
