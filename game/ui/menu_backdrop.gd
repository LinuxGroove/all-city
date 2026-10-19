class_name MenuBackdrop
extends Node3D
## The street behind the title, built from the kit: shops and flats along a
## road at dusk, a staircase with its rail between two blocks, parked cars,
## and a crew at work (one on the rail, one painting, one keeping watch)
## under the drone's light. A small copy of tools/art_preview.gd's scene,
## which isn't shipped.
##
## The camera stands still apart from a slow sideways drift over a minute:
## no shake, no roll and no cuts. Low detail (handhelds) drops the shadows.

## How far the camera drifts each way, and how long one sweep takes.
const DRIFT := 0.9
const DRIFT_SECONDS := 70.0
const CURB := 0.15
const FAR := -8.15

## The time of day (see Look.TIMES).
var time := "dusk"
var camera: Camera3D
var _t := 0.0
var _cam_base := Vector3.ZERO
var _cam_target := Vector3.ZERO


func _ready() -> void:
	var low := int(LGSettings.get_value("video", "detail", 1)) == 0
	Look.dress(self, time)
	if low:
		var sun := get_node_or_null("Sun") as DirectionalLight3D
		if sun:
			sun.shadow_enabled = false
	_street(low)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.fov = 50.0
	camera.far = 300.0
	_cam_base = Vector3(-10.5, 2.3, 12.0)
	_cam_target = Vector3(-3.0, 5.6, -9.0)
	add_child(camera)
	_place_camera()
	camera.current = true


func _process(delta: float) -> void:
	_t += delta
	_place_camera()


func _place_camera() -> void:
	var s := sin(_t * TAU / DRIFT_SECONDS)
	camera.position = _cam_base + Vector3(s * DRIFT, 0, 0)
	camera.look_at(_cam_target + Vector3(s * DRIFT * 0.5, 0, 0), Vector3.UP)


func _street(low: bool) -> void:
	var batch := Batch.new()
	_box(Vector3(0, -0.5, 0), Vector3(120, 1.0, 8.0), "asphalt")
	for z in [-6.15, 6.15]:
		_box(Vector3(0, CURB * 0.5 - 0.5, z), Vector3(120, 1.0 + CURB, 4.0), "paving")
	for z in [-4.13, 4.13]:
		_box(Vector3(0, CURB * 0.5 - 0.48, z), Vector3(120, 1.0 + CURB, 0.26), "kerb")
	for i in 30:
		_box(Vector3(-58 + i * 4.0, 0.005, 0), Vector3(2.0, 0.01, 0.14), "white")
	var buildings := [
		{"x0": -34.0, "x1": -26.0, "storeys": 3, "style": "plaster", "ground": "home", "seed": 5},
		{"x0": -26.0, "x1": -10.0, "storeys": 4, "style": "plaster", "ground": "shop", "seed": 11},
		{"x0": -10.0, "x1": 1.8, "storeys": 5, "style": "brick", "ground": "shop", "seed": 3},
		{"x0": 8.2, "x1": 20.2, "storeys": 6, "style": "modern", "ground": "shop", "seed": 21},
		{"x0": 20.2, "x1": 34.0, "storeys": 3, "style": "plaster", "ground": "home", "seed": 7},
	]
	var depth := 14.0
	for b in buildings:
		var rec := Facade.recipe(b.style, b.ground, b.seed)
		rec.escape = b.seed == 3
		Facade.lay(batch, Vector3(b.x0, CURB, FAR), Vector3(b.x1, CURB, FAR), b.storeys, rec, b.seed, Vector2i(1, 1))
		var side := rec.duplicate()
		side.ground = "blank"
		side.escape = false
		if b.x1 == 1.8:
			Facade.lay(batch, Vector3(1.8, CURB, FAR), Vector3(1.8, CURB, FAR - depth), b.storeys, side, b.seed + 1, Vector2i(0, 0))
		if b.x0 == 8.2:
			Facade.lay(batch, Vector3(8.2, CURB, FAR - depth), Vector3(8.2, CURB, FAR), b.storeys, side, b.seed + 1, Vector2i(0, 0))
		var h: float = b.storeys * Facade.STOREY
		var cx: float = (b.x0 + b.x1) * 0.5
		_box_colour(Vector3(cx, CURB, FAR - depth * 0.5 - 0.3), Vector3(b.x1 - b.x0 - 0.6, h, depth - 0.6), rec.wall)
		_box(Vector3(cx, CURB + h, FAR - depth * 0.5 - 0.3), Vector3(b.x1 - b.x0 - 0.6, 0.3, depth - 0.6), "concrete_dark")
		var roof_y: float = CURB + h + 0.3
		if b.seed == 3:
			batch.add("facade/roof_tank", Transform3D(Basis.IDENTITY, Vector3(cx - 2.0, roof_y, FAR - 6.0)))
		batch.add("facade/roof_vent", Transform3D(Basis.IDENTITY, Vector3(cx + 3.0, roof_y, FAR - 4.0)))
	# The staircase up the hill between the brick block and the new one.
	var bottom := Vector3(5.0, CURB, FAR + 0.2)
	var flight := Stairs.lay(batch, bottom, Vector3.FORWARD, 18, 4.0, Palette.color("cream"))
	var top: Vector3 = flight.top
	_box(Vector3(5.0, CURB, top.z - 6.0), Vector3(6.4, top.y - CURB, 12.0), "paving")
	for rail in flight.rails:
		var m := MeshInstance3D.new()
		m.mesh = Tube.mesh(rail, 0.03, "chrome", 10)
		add_child(m)
	for p in [["street/street_lamp", -20.0], ["street/bench", -15.5], ["street/litter_bin", -13.6], ["street/planter", -6.0],
			["street/street_lamp", -2.0], ["street/hydrant", -1.2], ["street/bollard", 3.0], ["street/bollard", 7.0],
			["street/sign_post", 9.4], ["street/street_lamp", 14.0], ["street/street_tree", 23.0]]:
		batch.add(p[0], Transform3D(Basis.IDENTITY, Vector3(p[1], CURB, -4.75)))
	batch.add("street/traffic_light", Transform3D(Basis.IDENTITY, Vector3(-9.0, CURB, -4.6)))
	for p in [["street/bollard", -3.0], ["street/bollard", -1.4], ["street/street_lamp", -12.0]]:
		batch.add(p[0], Transform3D(Basis(Vector3.UP, PI), Vector3(p[1], CURB, 4.7)))
	batch.build(self, not low)
	_vehicle("vehicles/hatchback", Vector3(-17.0, 0, -2.6), PI * 0.5, "cobalt")
	_vehicle("vehicles/hatchback", Vector3(26.0, 0, -2.6), PI * 0.5, "signal_yellow")
	_vehicle("vehicles/buff_van", Vector3(16.0, 0, -2.4), -PI * 0.5, "")
	var drone := Kit.instance("vehicles/drone")
	drone.position = Vector3(-2.5, 8.5, -1.0)
	drone.rotation.y = 0.6
	add_child(drone)
	_beam(drone.position + Vector3(0, -0.05, 0), Vector3(-6.7, 0.2, -6.8), low)
	if Look.night > 0.3:
		for x in [-20.0, -2.0, 14.0]:
			_lamp(Vector3(x, CURB + 5.7, -3.6))
		_lamp(Vector3(-12.0, CURB + 5.7, 3.6))
	_crew(flight.rails[0], top)
	_tag("SALT", Vector3(-7.0, CURB + 1.45, FAR + 0.05), 0.0, 1.3, "neon_cyan")
	_tag("NITE", Vector3(-20.6, CURB + 1.3, FAR + 0.05), 0.0, 0.9, "signal_yellow")
	_tag("LOW TIDE", Vector3(1.85, CURB + 5.2, FAR - 4.0), PI * 0.5, 1.2, "neon_pink")


## Three writers: one on the stair rail, one painting the shutter in the
## drone's light, one keeping watch at the top of the steps.
func _crew(rail: PackedVector3Array, top: Vector3) -> void:
	var grinder := Person.make("writer", true, 4, {"main": Palette.color("signal_yellow"), "legs": Palette.color("ink")})
	grinder.position = rail[0].lerp(rail[1], 0.45) + Vector3(0, 0.03 - Skater.GRIND_DROP, 0)
	add_child(grinder)
	grinder.pose("Crouch_Idle", 0.3)
	grinder.grind_still(rail[0] - rail[1])
	var painter := Person.make("writer", false, 9, {"main": Palette.color("purple"), "accent": Palette.color("hivis")})
	painter.position = Vector3(-6.7, CURB, -6.5)
	painter.rotation.y = PI
	add_child(painter)
	painter.pose("Pistol_Aim_Neutral", 0.5)
	painter.hold_can(Palette.color("neon_cyan"))
	painter.hold_board_still()
	var lookout := Person.make("writer", true, 2, {"main": Palette.color("signal_red")})
	lookout.position = Vector3(6.3, top.y + 0.02, top.z + 1.2)
	lookout.rotation.y = PI * 0.85
	add_child(lookout)
	lookout.pose("Idle_FoldArms", 0.3)
	lookout.board_on_pack_still()


func _box(base: Vector3, size: Vector3, swatch: String) -> void:
	_box_colour(base, size, Palette.color(swatch))


func _box_colour(base: Vector3, size: Vector3, colour: Color) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = Look.flat(colour)
	m.mesh = b
	m.position = base + Vector3.UP * (size.y * 0.5)
	add_child(m)


func _vehicle(model: String, at: Vector3, yaw: float, swatch: String) -> void:
	var v := Kit.instance(model, Palette.color(swatch) if swatch != "" else Color.WHITE)
	v.position = at
	v.rotation.y = yaw
	add_child(v)


## The drone's searchlight from `lamp` down onto `target`: a steady beam,
## never a flicker.
func _beam(lamp: Vector3, target: Vector3, low: bool) -> void:
	var aim := Node3D.new()
	var down := (lamp - target).normalized()
	var side := down.cross(Vector3.FORWARD).normalized()
	aim.transform = Transform3D(Basis(side, down, side.cross(down)), lamp)
	add_child(aim)
	aim.add_child(Look.beam(lamp.distance_to(target) + 1.0, 1.6))
	var spot := SpotLight3D.new()
	spot.light_color = Palette.color("lamp_white")
	spot.light_energy = 14.0
	spot.spot_range = 16.0
	spot.spot_angle = 11.0
	spot.shadow_enabled = not low
	spot.rotation_degrees.x = -90
	aim.add_child(spot)


func _lamp(at: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Palette.color("sodium")
	l.light_energy = 3.0 * Look.night
	l.omni_range = 13.0
	l.omni_attenuation = 0.8
	l.position = at
	add_child(l)


## Paint as the art preview draws it for now: marker letters with an ink
## outline, flat on the wall.
func _tag(text: String, at: Vector3, yaw: float, height: float, swatch: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = CityTheme.marker()
	l.font_size = 128
	l.pixel_size = height / 128.0
	l.outline_size = 18
	l.outline_modulate = Palette.color("ink")
	l.modulate = Palette.color(swatch)
	l.shaded = false
	l.double_sided = false
	l.position = at
	l.rotation = Vector3(0, yaw, -0.06)
	add_child(l)
