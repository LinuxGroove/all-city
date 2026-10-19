extends Node3D
## Pictures of the game's own art, for judging the look: every model of a
## set in a row with its name, or a street scene that puts them together.
##
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --resolution 1600x900 tools/art_preview.tscn -- \
##       --set=street --out=docs/art/street.png [--time=dusk|day|night] [--only=tree_oak,tree_pine] [--turn=90]
##
## Sets are the folders of assets/models/ (street, stairs, facade, vehicles,
## gear, landmark), plus "scene" (a street with buildings, a staircase, traffic and
## writers) and "all" (every set and the scene at every time of day, into
## the folder given by --out).

const SETS := ["street", "stairs", "facade", "vehicles", "gear", "landmark"]
## Colours the Wall role takes in lineups, so tinting shows.
const TINTS := ["ochre", "teal", "brick", "pink", "mint", "cobalt", "terracotta", "lilac", "sand", "signal_red"]

var _opts := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			_opts[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var set_name := str(_opts.get("set", "scene"))
	var out := str(_opts.get("out", "/tmp/art.png"))
	if set_name == "all":
		DirAccess.make_dir_recursive_absolute(out)
		for s in SETS:
			await _shoot(s, "day", out.path_join(s + ".png"))
		for view in ["street", "stairs"]:
			for t in ["day", "dusk", "night"]:
				_opts["view"] = view
				await _shoot("scene", t, out.path_join("scene_%s_%s.png" % [view, t]))
	else:
		await _shoot(set_name, str(_opts.get("time", "dusk" if set_name == "scene" else "day")), out)
	get_tree().quit()


func _shoot(set_name: String, time: String, path: String) -> void:
	for c in get_children():
		c.free()
	var stage := Node3D.new()
	add_child(stage)
	Look.dress(stage, time)
	var cam := Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	stage.add_child(cam)
	if set_name == "scene":
		_scene(stage, cam, str(_opts.get("view", "street")))
	else:
		_lineup(stage, cam, set_name)
	cam.current = true
	for i in 12:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("art_preview: ", path)


## Every model of a set in rows, each over its name.
func _lineup(stage: Node3D, cam: Camera3D, set_name: String) -> void:
	var models := Array(Kit.models(set_name))
	if _opts.has("only"):
		var only := str(_opts.only).split(",")
		models = models.filter(func(m: String) -> bool: return m.get_file() in only)
	models.sort_custom(_taller)
	var sizes: Array[AABB] = []
	var widest := 0.0
	var tallest := 0.0
	for m in models:
		var box := Kit.mesh(m).get_aabb()
		sizes.append(box)
		widest = maxf(widest, box.size.x)
		tallest = maxf(tallest, box.size.y)
	var gap := clampf(widest * 0.35, 0.15, 1.2)
	var row_width := maxf(widest * 4.5, 3.0)
	var rows: Array = [[]]
	var x := 0.0
	for i in models.size():
		var w := sizes[i].size.x + gap
		if x + w > row_width and not rows[-1].is_empty():
			rows.append([])
			x = 0.0
		rows[-1].append(i)
		x += w
	var depth := 0.0
	for i in models.size():
		depth = maxf(depth, sizes[i].size.z)
	var row_step := maxf(depth, tallest * 0.55) + gap * 3.0
	var label_size := clampf(widest * 0.06, 0.02, 0.16)
	var far_x := 0.0
	var bounds := AABB()
	var first := true
	for r in rows.size():
		var total := 0.0
		for i in rows[r]:
			total += sizes[i].size.x + gap
		x = -total * 0.5
		var z := -r * row_step
		for i in rows[r]:
			var box: AABB = sizes[i]
			var tint := Palette.color(TINTS[i % TINTS.size()])
			var node := Kit.instance(models[i], tint)
			node.rotation_degrees.y = float(_opts.get("turn", 0.0))
			node.position = Vector3(x + box.size.x * 0.5 - box.get_center().x, 0, z - box.get_center().z)
			stage.add_child(node)
			var placed := AABB(box.position + node.position, box.size)
			bounds = placed if first else bounds.merge(placed)
			first = false
			var label := _label(models[i].get_file().replace("_", " "), label_size)
			label.position = Vector3(x + box.size.x * 0.5, 0.01, z + box.end.z - box.get_center().z + label_size * 1.8)
			label.rotation_degrees.x = -90
			stage.add_child(label)
			x += box.size.x + gap
		far_x = maxf(far_x, total)
	var floor_size := Vector2(far_x + row_width, rows.size() * row_step + row_width) * 1.6
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = floor_size
	plane.material = Look.flat(Palette.color("paving"))
	ground.mesh = plane
	ground.position.z = -rows.size() * row_step * 0.5
	stage.add_child(ground)
	_frame(cam, bounds, Vector3(-0.25, 0.42, 1.0))


## Points the camera along `dir` (towards the camera) so `box` fills the view.
func _frame(cam: Camera3D, box: AABB, dir: Vector3) -> void:
	cam.fov = 30.0
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var half_v := deg_to_rad(cam.fov * 0.5)
	var half_h := atan(tan(half_v) * aspect)
	var radius := box.size.length() * 0.5
	var dist := radius / sin(minf(half_v, half_h)) * 0.66
	var centre := box.get_center()
	cam.position = centre + dir.normalized() * dist
	cam.look_at(centre, Vector3.UP)
	cam.near = maxf(dist * 0.01, 0.01)
	cam.far = dist * 8.0


func _taller(a: String, b: String) -> bool:
	return Kit.mesh(a).get_aabb().size.y < Kit.mesh(b).get_aabb().size.y


func _label(text: String, size: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = load("res://assets/fonts/Bungee-Regular.ttf")
	l.font_size = 64
	l.pixel_size = size / 64.0
	l.outline_size = 0
	l.modulate = Palette.color("ink")
	l.double_sided = false
	l.shaded = false
	return l


## The street: shops and flats along both sides of a road, a staircase
## between two buildings, cars, the Buff's van, Civic's drone and two
## writers at work.
func _scene(stage: Node3D, cam: Camera3D, view: String) -> void:
	var batch := Batch.new()
	var curb := 0.15
	_box(stage, Vector3(0, -0.5, 0), Vector3(120, 1.0, 8.0), Palette.color("asphalt"))
	for z in [-6.15, 6.15]:
		_box(stage, Vector3(0, curb * 0.5 - 0.5, z), Vector3(120, 1.0 + curb, 4.0), Palette.color("paving"))
	for z in [-4.13, 4.13]:
		_box(stage, Vector3(0, curb * 0.5 - 0.48, z), Vector3(120, 1.0 + curb, 0.26), Palette.color("kerb"))
	for i in 30:
		_box(stage, Vector3(-58 + i * 4.0, 0.005, 0), Vector3(2.0, 0.01, 0.14), Palette.color("white"))
	# The far side: four buildings, a staircase in the gap.
	var far := -8.15
	var buildings := [
		{"x0": -26.0, "x1": -10.0, "storeys": 4, "style": "plaster", "ground": "shop", "seed": 11},
		{"x0": -10.0, "x1": 1.8, "storeys": 5, "style": "brick", "ground": "shop", "seed": 3},
		{"x0": 8.2, "x1": 20.2, "storeys": 6, "style": "modern", "ground": "shop", "seed": 21},
		{"x0": 20.2, "x1": 34.0, "storeys": 3, "style": "plaster", "ground": "home", "seed": 7},
	]
	for b in buildings:
		var rec := Facade.recipe(b.style, b.ground, b.seed)
		if b.seed == 3:
			rec.escape = true
		var depth := 14.0
		var a := Vector3(b.x0, curb, far)
		var e := Vector3(b.x1, curb, far)
		Facade.lay(batch, a, e, b.storeys, rec, b.seed, Vector2i(1, 1))
		# Side faces where the staircase passes.
		var side_rec := rec.duplicate()
		side_rec.ground = "blank"
		side_rec.escape = false
		if b.x1 == 1.8:
			Facade.lay(batch, Vector3(1.8, curb, far), Vector3(1.8, curb, far - depth), b.storeys, side_rec, b.seed + 1,
					Vector2i(0, 0))
		if b.x0 == 8.2:
			Facade.lay(batch, Vector3(8.2, curb, far - depth), Vector3(8.2, curb, far), b.storeys, side_rec, b.seed + 1,
					Vector2i(0, 0))
		var h: float = b.storeys * Facade.STOREY
		_box(stage, Vector3((b.x0 + b.x1) * 0.5, curb, far - depth * 0.5 - 0.3), Vector3(b.x1 - b.x0 - 0.6, h, depth - 0.6),
				rec.wall)
		_box(stage, Vector3((b.x0 + b.x1) * 0.5, curb + h, far - depth * 0.5 - 0.3),
				Vector3(b.x1 - b.x0 - 0.6, 0.3, depth - 0.6), Palette.color("concrete_dark"))
		var roof_y: float = curb + h + 0.3
		var cx: float = (b.x0 + b.x1) * 0.5
		if b.seed == 3:
			batch.add("facade/roof_tank", Transform3D(Basis.IDENTITY, Vector3(cx - 2.0, roof_y, far - 6.0)))
		batch.add("facade/roof_vent", Transform3D(Basis.IDENTITY, Vector3(cx + 3.0, roof_y, far - 4.0)))
		batch.add("facade/roof_hut", Transform3D(Basis.IDENTITY, Vector3(cx + 1.0, roof_y, far - 9.0)))
	# The staircase up the hill between the brick block and the new one.
	var steps := 18
	var bottom := Vector3(5.0, curb, far + 0.2)
	var flight := Stairs.lay(batch, bottom, Vector3.FORWARD, steps, 4.0, Palette.color("cream"))
	var top: Vector3 = flight.top
	_box(stage, Vector3(5.0, curb, top.z - 6.0), Vector3(6.4, top.y - curb, 12.0), Palette.color("paving"))
	_mass(stage, bottom, top, 6.4, Palette.color("concrete_dark"))
	for rail in flight.rails:
		_tube(stage, rail, 0.03, "chrome")
	# Street furniture on the far pavement.
	var props := [
		["street/street_lamp", -20.0], ["street/bench", -15.5], ["street/litter_bin", -13.6], ["street/planter", -6.0],
		["street/street_lamp", -2.0], ["street/hydrant", -1.2], ["street/bollard", 3.0], ["street/bollard", 7.0],
		["street/sign_post", 9.4], ["street/street_lamp", 14.0], ["street/utility_box", 17.4], ["street/street_tree", 23.0],
		["street/bench", 26.0], ["street/street_lamp", 30.0],
	]
	for p in props:
		var y_turn := 0.0
		batch.add(p[0], Transform3D(Basis(Vector3.UP, y_turn), Vector3(p[1], curb, -4.75)))
	batch.add("street/traffic_light", Transform3D(Basis.IDENTITY, Vector3(-9.0, curb, -4.6)))
	batch.add("street/dumpster", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-27.6, curb, -11.0)))
	# The near pavement: the camera stands here.
	for p in [["street/bollard", -3.0], ["street/bollard", -1.4], ["street/litter_bin", 2.6], ["street/street_lamp", 11.0]]:
		batch.add(p[0], Transform3D(Basis(Vector3.UP, PI), Vector3(p[1], curb, 4.7)))
	batch.build(stage)
	# Traffic and the city's answer.
	_vehicle(stage, "vehicles/hatchback", Vector3(-16.0, 0, -2.6), PI * 0.5, Palette.color("cobalt"))
	_vehicle(stage, "vehicles/hatchback", Vector3(24.0, 0, -2.6), PI * 0.5, Palette.color("signal_yellow"))
	_vehicle(stage, "vehicles/hatchback", Vector3(-4.0, 0, 2.0), -PI * 0.5, Palette.color("mint"))
	_vehicle(stage, "vehicles/buff_van", Vector3(15.0, 0, -2.4), -PI * 0.5, Color.WHITE)
	_vehicle(stage, "vehicles/civic_car", Vector3(-24.0, 0, 2.0), -PI * 0.5, Color.WHITE)
	var drone := Kit.instance("vehicles/drone")
	drone.position = Vector3(-2.5, 8.5, -1.0)
	drone.rotation.y = 0.6
	stage.add_child(drone)
	# Its searchlight on the painter.
	var lamp := drone.position + Vector3(0, -0.05, 0)
	var target := Vector3(-6.7, 0.2, -6.8)
	var aim := Node3D.new()
	var down := (lamp - target).normalized()
	var side := down.cross(Vector3.FORWARD).normalized()
	aim.transform = Transform3D(Basis(side, down, side.cross(down)), lamp)
	stage.add_child(aim)
	aim.add_child(Look.beam(lamp.distance_to(target) + 1.0, 1.6))
	var beam := SpotLight3D.new()
	beam.light_color = Palette.color("lamp_white")
	beam.light_energy = 14.0
	beam.spot_range = 16.0
	beam.spot_angle = 11.0
	beam.shadow_enabled = true
	beam.rotation_degrees.x = -90
	aim.add_child(beam)
	# Night lights at the lamps.
	var night := Look.night
	if night > 0.3:
		for x in [-20.0, -2.0, 14.0, 30.0]:
			_lamp(stage, Vector3(x, curb + 5.7, -3.6), night)
		_lamp(stage, Vector3(11.0, curb + 5.7, 3.6), night)
	# Writers: one grinding the stair rail, one painting the shutter.
	var rail: PackedVector3Array = flight.rails[0]
	var grinder := Person.make("writer", true, 4, {"main": Palette.color("signal_yellow"), "legs": Palette.color("ink")})
	var on := rail[0].lerp(rail[1], 0.45)
	grinder.position = on + Vector3(0, -Person.SKATE_LIFT + 0.02, 0)
	grinder.rotation.y = PI * 0.5
	stage.add_child(grinder)
	grinder.pose("Crouch_Idle", 0.3)
	var painter := Person.make("writer", false, 9, {"main": Palette.color("purple"), "accent": Palette.color("hivis")})
	painter.position = Vector3(-6.7, curb, -6.5)
	painter.rotation.y = PI
	stage.add_child(painter)
	painter.pose("Pistol_Aim_Neutral", 0.5)
	painter.hold_can(Palette.color("neon_cyan"))
	var lookout := Person.make("writer", true, 2, {"main": Palette.color("signal_red")})
	lookout.position = Vector3(8.0, curb, -6.6)
	lookout.rotation.y = -0.5
	stage.add_child(lookout)
	lookout.pose("Idle_FoldArms", 0.3)
	var buff := Person.make("buff", false, 5)
	buff.position = Vector3(12.6, curb, -4.9)
	buff.rotation.y = PI * 0.6
	stage.add_child(buff)
	buff.pose("Idle_FoldArms", 0.3)
	# Paint on the walls: a tag on the shutter and a throw-up up the stairs.
	_tag(stage, "SALT", Vector3(-7.0, curb + 1.45, far + 0.05), 0.0, 1.3, Palette.color("neon_cyan"))
	_tag(stage, "NITE", Vector3(-20.6, curb + 1.3, far + 0.05), 0.0, 0.9, Palette.color("signal_yellow"))
	_tag(stage, "LOW TIDE", Vector3(1.85, curb + 5.2, far - 4.0), PI * 0.5, 1.2, Palette.color("neon_pink"))
	_tag(stage, "SALT", Vector3(7.0, curb + 1.45 + 0.6, far - 2.8), -PI * 0.5, 0.6, Palette.color("hivis"))
	var air := Person.make("writer", false, 12, {"main": Palette.color("cobalt"), "accent": Palette.color("orange")})
	air.position = Vector3(6.3, top.y + 0.9, top.z + 1.6)
	air.rotation.y = PI * 0.92
	stage.add_child(air)
	air.pose("NinjaJump_Idle", 0.5)
	if view == "stairs":
		cam.fov = 55.0
		cam.position = Vector3(1.2, 1.5, -1.6)
		cam.look_at(Vector3(5.6, 3.6, -12.5), Vector3.UP)
	else:
		cam.fov = 52.0
		cam.position = Vector3(-8.5, 3.0, 11.5)
		cam.look_at(Vector3(4.0, 5.5, -9.0), Vector3.UP)
	cam.far = 400.0


func _box(stage: Node3D, base: Vector3, size: Vector3, colour: Color) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = Look.flat(colour)
	m.mesh = b
	m.position = base + Vector3.UP * (size.y * 0.5)
	stage.add_child(m)


## The solid under a flight, so it reads as built into the hill.
func _mass(stage: Node3D, bottom: Vector3, top: Vector3, width: float, colour: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width * 0.5
	for s in [-1.0, 1.0]:
		var x: float = bottom.x + s * hw
		var a := Vector3(x, bottom.y - 0.4, bottom.z)
		var b := Vector3(x, top.y - 0.3, top.z)
		var c := Vector3(x, bottom.y - 0.4, top.z)
		if s > 0:
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
		else:
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(b)
	st.generate_normals()
	st.set_material(Look.flat(colour))
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	stage.add_child(m)


func _tube(stage: Node3D, points: PackedVector3Array, radius: float, swatch: String) -> void:
	var m := MeshInstance3D.new()
	m.mesh = Tube.mesh(points, radius, swatch, 10)
	stage.add_child(m)


func _vehicle(stage: Node3D, model: String, at: Vector3, yaw: float, tint: Color) -> void:
	var v := Kit.instance(model, tint)
	v.position = at
	v.rotation.y = yaw
	stage.add_child(v)


func _lamp(stage: Node3D, at: Vector3, night: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = Palette.color("sodium")
	l.light_energy = 3.0 * night
	l.omni_range = 13.0
	l.omni_attenuation = 0.8
	l.position = at
	stage.add_child(l)


## Paint in the kit's style for now: letters in a marker face with an ink
## outline, flat on the wall. The game's paint renders to the wall's own
## texture instead.
func _tag(stage: Node3D, text: String, at: Vector3, yaw: float, height: float, colour: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = load("res://assets/fonts/PermanentMarker-Regular.ttf")
	l.font_size = 128
	l.pixel_size = height / 128.0
	l.outline_size = 18
	l.outline_modulate = Palette.color("ink")
	l.modulate = colour
	l.shaded = false
	l.double_sided = false
	l.position = at
	l.rotation = Vector3(0, yaw, -0.06)
	stage.add_child(l)
