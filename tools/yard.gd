extends Node3D
## The test yard: a street to skate on its own, for feeling out the skater
## and for its tests. A road with kerbs, three buildings laid by Facade (one
## with a drainpipe and a fire escape up to a flat roof with a parapet), a
## wide flight of steps up to a terrace with its middle handrail and side
## copings, a ledge, a fence and lamps, at dusk. Every grindable edge and
## every way up is in a Lines.
##
##   godot --path . tools/yard.tscn [-- --time=day|dusk|night]
##
## Space jumps between spots (map), Escape lets go of the mouse (pause).
## For pictures of the look and the poses:
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 tools/yard.tscn -- \
##       --shot=/tmp/yard.png [--pose=street|stand|skate|ollie|kickflip|manual|grind|kerb|slide|wall|climb|roof|air|kick|paint|stumble] [--time=dusk] [--close=right|left|back]
##
## `build()` makes the world with no skater, camera or input, for tests.

## The pavement's height above the road.
const CURB := 0.15
## The north side's building line, and where the stairs start.
const FRONT := -8.2
const STAIR_STEPS := 18
const STAIR_WIDTH := 4.0
const STAIR_X := 6.0
const TERRACE_END := -24.0
## The buildings: a footprint (x0, z0 to x1, z1, the front on the street),
## storeys, style, ground floor, seed and the ways up.
const BUILDINGS := [
	{"name": "brick", "x0": -36.0, "x1": -20.0, "z0": FRONT, "z1": FRONT - 14.0, "storeys": 4, "style": "brick",
		"ground": "home", "seed": 3, "pipe_at": 2, "escape_bay": 5, "props": true},
	{"name": "modern", "x0": -16.0, "x1": 2.0, "z0": FRONT, "z1": FRONT - 14.0, "storeys": 3, "style": "modern",
		"ground": "blank", "seed": 21, "pipe_at": -1, "escape_bay": -1},
	{"name": "plaster", "x0": 10.0, "x1": 24.0, "z0": FRONT, "z1": FRONT - 14.0, "storeys": 5, "style": "plaster",
		"ground": "shop", "seed": 11, "pipe_at": -1, "escape_bay": -1},
	{"name": "corner", "x0": 30.0, "x1": 46.0, "z0": 8.0, "z1": 20.0, "storeys": 2, "style": "works",
		"ground": "shop", "seed": 7, "pipe_at": 3, "escape_bay": -1, "south": true},
]
const LEDGE := {"x0": -24.0, "x1": -10.0, "z0": 6.4, "z1": 6.85, "height": 0.5}
const FENCE := {"x0": -6.0, "x1": 26.0, "z": 8.0, "height": 1.1}
## The tube a handrail is drawn as; the wheels run along its top.
const RAIL_RADIUS := 0.03

var world := {}
var skater: Skater
var cam: StreetCamera
var _opts := {}
var _hud: Label
var _meter: ProgressBar
var _spot := 0
var _log: Array[String] = []


## Builds the yard under `parent` and returns what tests and the scene
## need: "lines", "spawn" and its "face", and named spots and line ids
## ("rail", "rail_top", "terrace", "kerb", "ledge", "fence", "copings",
## "pipe", "escape", "wall", "roofs", "buildings").
static func build(parent: Node3D, visuals := true, time := "dusk") -> Dictionary:
	var lines := Lines.new()
	var solid := StaticBody3D.new()
	solid.name = "Solid"
	solid.collision_layer = Kit.LAYER_WORLD
	solid.collision_mask = 0
	parent.add_child(solid)
	var looks := Node3D.new()
	looks.name = "Looks"
	parent.add_child(looks)
	var batch := Batch.new()
	if visuals:
		Look.dress(parent, time)
	var out := {"lines": lines, "spawn": Vector3(-8.0, CURB, -6.0), "face": Vector3.RIGHT, "roofs": [],
		"buildings": [], "copings": []}
	# The ground, the road and the pavements.
	_solid_box(solid, Vector3(0, -0.5, 0), Vector3(320, 1.0, 320))
	for z in [[FRONT - 0.0, -4.0], [4.0, 8.0]]:
		var z0: float = z[0]
		var z1: float = z[1]
		_solid_box(solid, Vector3(0, CURB * 0.5, (z0 + z1) * 0.5), Vector3(140, CURB, absf(z1 - z0)))
		if visuals:
			_look_box(looks, Vector3(0, CURB * 0.5, (z0 + z1) * 0.5), Vector3(140, CURB, absf(z1 - z0)), "paving")
	out.kerb = lines.add(Lines.Kind.KERB, PackedVector3Array([Vector3(-70, CURB, -4.0), Vector3(70, CURB, -4.0)]))
	out.kerb_south = lines.add(Lines.Kind.KERB, PackedVector3Array([Vector3(70, CURB, 4.0), Vector3(-70, CURB, 4.0)]))
	if visuals:
		_look_box(looks, Vector3(0, -0.05, 0), Vector3(320, 0.1, 320), "asphalt")
		_look_box(looks, Vector3(0, -0.04, 40), Vector3(320, 0.1, 64), "grass")
		for z in [-4.13, 4.13]:
			_look_box(looks, Vector3(0, CURB * 0.5 + 0.004, z), Vector3(140, CURB, 0.26), "kerb")
		for i in 34:
			_look_box(looks, Vector3(-66 + i * 4.0, 0.006, 0), Vector3(2.0, 0.012, 0.14), "white")
	# The buildings.
	for b in BUILDINGS:
		out.buildings.append(_building(b, solid, looks, batch, lines, visuals, out))
	# The steps up to the terrace, between the modern block and the shops.
	var bottom := Vector3(STAIR_X, CURB, FRONT)
	var up := Vector3.FORWARD
	var flight := Stairs.lay(batch, bottom, up, STAIR_STEPS, STAIR_WIDTH, Palette.color("cream"))
	var top: Vector3 = flight.top
	solid.add_child(Stairs.ramp(bottom, up, STAIR_STEPS, STAIR_WIDTH))
	var rail: PackedVector3Array = flight.rails[0]
	var wheels := PackedVector3Array([rail[0] + Vector3.UP * RAIL_RADIUS, rail[1] + Vector3.UP * RAIL_RADIUS])
	out.rail = lines.add(Lines.Kind.HANDRAIL, wheels)
	out.rail_top = wheels[1]
	out.rail_bottom = wheels[0]
	# The rail and its posts stop you rolling through them.
	_prism(solid, rail[0] - Vector3.UP * 0.04, rail[1] - Vector3.UP * 0.04, 0.08, 1.1)
	for coping in flight.copings:
		out.copings.append(lines.add(Lines.Kind.COPING, coping))
		_prism(solid, coping[0], coping[1], 0.42, 1.8)
	var terrace_len := top.z - TERRACE_END
	var terrace_mid := Vector3(STAIR_X, top.y * 0.5, (top.z + TERRACE_END) * 0.5)
	var terrace_size := Vector3(8.0, top.y, terrace_len)
	_solid_box(solid, terrace_mid, terrace_size)
	out.terrace = Vector3(STAIR_X, top.y, TERRACE_END + 1.5)
	out.stairs_top = top
	out.ledges = [lines.add(Lines.Kind.LEDGE, PackedVector3Array([Vector3(2.0, top.y, TERRACE_END),
		Vector3(10.0, top.y, TERRACE_END)]))]
	if visuals:
		_look_box(looks, terrace_mid, terrace_size, "paving", "concrete_dark")
		_mass(looks, bottom, top, STAIR_WIDTH + 0.9, Palette.color("concrete_dark"))
		looks.add_child(_tube_node(rail, RAIL_RADIUS, "chrome"))
	# A ledge along the south pavement, and a fence along its far side.
	var ledge_mid := Vector3((LEDGE.x0 + LEDGE.x1) * 0.5, CURB + LEDGE.height * 0.5, (LEDGE.z0 + LEDGE.z1) * 0.5)
	var ledge_size := Vector3(LEDGE.x1 - LEDGE.x0, LEDGE.height, LEDGE.z1 - LEDGE.z0)
	_solid_box(solid, ledge_mid, ledge_size)
	out.ledge = lines.add(Lines.Kind.LEDGE, PackedVector3Array([Vector3(LEDGE.x0, CURB + LEDGE.height, LEDGE.z0),
		Vector3(LEDGE.x1, CURB + LEDGE.height, LEDGE.z0)]))
	var fence_top := CURB + float(FENCE.height)
	_solid_box(solid, Vector3((FENCE.x0 + FENCE.x1) * 0.5, fence_top * 0.5, FENCE.z),
			Vector3(FENCE.x1 - FENCE.x0, fence_top, 0.1))
	out.fence = lines.add(Lines.Kind.FENCE, PackedVector3Array([Vector3(FENCE.x0, fence_top + RAIL_RADIUS, FENCE.z),
		Vector3(FENCE.x1, fence_top + RAIL_RADIUS, FENCE.z)]))
	if visuals:
		_look_box(looks, ledge_mid, ledge_size, "concrete_light", "concrete")
		looks.add_child(_railings(Vector3(FENCE.x0, CURB, FENCE.z), Vector3(FENCE.x1, CURB, FENCE.z), FENCE.height))
		_street_props(batch, looks, Look.night)
		batch.build(looks)
	out.wall = {"from": Vector3(-16.0, CURB, FRONT), "to": Vector3(2.0, CURB, FRONT), "out": Vector3.BACK}
	return out


## One building: its four faces, a body to bump into, a roof to stand on
## behind a parapet you can grind, and its ways up as climb lines.
static func _building(b: Dictionary, solid: StaticBody3D, looks: Node3D, batch: Batch, lines: Lines, visuals: bool,
		out: Dictionary) -> Dictionary:
	var x0: float = b.x0
	var x1: float = b.x1
	var z0: float = b.z0
	var z1: float = b.z1
	var south := bool(b.get("south", false))
	# Corners walked with the outside on the right: the street face first.
	var corners: Array[Vector3]
	if south:
		corners = [Vector3(x1, CURB, z0), Vector3(x0, CURB, z0), Vector3(x0, CURB, z1), Vector3(x1, CURB, z1)]
	else:
		corners = [Vector3(x0, CURB, z0), Vector3(x1, CURB, z0), Vector3(x1, CURB, z1), Vector3(x0, CURB, z1)]
	var rec := Facade.recipe(b.style, b.ground, b.seed)
	var crest := 0.0
	for i in 4:
		var face_rec := rec.duplicate()
		if i == 0:
			face_rec.pipe_at = b.pipe_at
			face_rec.escape_bay = b.escape_bay
		else:
			face_rec.ground = "blank"
			face_rec.pipe_at = -1
			face_rec.escape_bay = -1
		var laid := Facade.lay(batch, corners[i], corners[(i + 1) % 4], b.storeys, face_rec, int(b.seed) + i)
		crest = laid.crest
		for climb in laid.climbs:
			var id := lines.add(Lines.Kind.CLIMB, climb)
			if i == 0 and int(b.pipe_at) >= 0 and not out.has("pipe") and b.name == "brick":
				out.pipe = id
			elif i == 0 and b.name == "brick":
				out.escape = id
	var deck := crest - 0.95
	var w := x1 - x0
	var d := absf(z1 - z0)
	var mid := Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)
	# The body reaches the facade modules' faces, a hand's width out.
	_solid_box(solid, Vector3(mid.x, (CURB + deck) * 0.5, mid.z), Vector3(w + 0.2, deck - CURB, d + 0.2))
	# The parapet: a band round the roof's edge, ground along its top.
	var band := 0.42
	var inset := 0.15
	for side in [[Vector3(mid.x, 0, minf(z0, z1) + inset), Vector3(w, 0, band)],
			[Vector3(mid.x, 0, maxf(z0, z1) - inset), Vector3(w, 0, band)],
			[Vector3(x0 + inset, 0, mid.z), Vector3(band, 0, d)], [Vector3(x1 - inset, 0, mid.z), Vector3(band, 0, d)]]:
		var at: Vector3 = side[0]
		var size: Vector3 = side[1]
		_solid_box(solid, Vector3(at.x, (deck + crest) * 0.5, at.z), Vector3(size.x, crest - deck, size.z))
	var loop := PackedVector3Array()
	for c in corners:
		loop.append(Vector3(c.x + (inset if c.x < mid.x else -inset), crest, c.z + (inset if c.z < mid.z else -inset)))
	loop.append(loop[0])
	lines.add(Lines.Kind.PARAPET, loop)
	out.roofs.append({"name": b.name, "y": deck, "rect": Rect2(x0, minf(z0, z1), w, d), "crest": crest})
	if bool(b.get("props", false)):
		var props := [["facade/roof_hut", Vector3(mid.x + 3.5, deck, mid.z - 2.0)],
			["facade/roof_vent", Vector3(mid.x - 3.0, deck, mid.z + 1.0)],
			["facade/roof_tank", Vector3(mid.x + 5.0, deck, mid.z + 3.0)]]
		for p in props:
			var box := Kit.mesh(p[0]).get_aabb()
			_solid_box(solid, p[1] + box.get_center(), box.size)
			batch.add(p[0], Transform3D(Basis.IDENTITY, p[1]))
	if visuals:
		var top_y: float = CURB + int(b.storeys) * Facade.STOREY
		_look_box(looks, Vector3(mid.x, (CURB + top_y) * 0.5, mid.z), Vector3(w - 0.6, top_y - CURB, d - 0.6), "", "",
				rec.wall)
		_look_box(looks, Vector3(mid.x, (top_y + deck) * 0.5, mid.z), Vector3(w - 0.6, deck - top_y + 0.02, d - 0.6),
				"concrete_dark")
	return {"name": b.name, "rect": Rect2(x0, minf(z0, z1), w, d), "deck": deck, "crest": crest}


## Lamps, benches, bins and the like along both pavements (looks only).
static func _street_props(batch: Batch, looks: Node3D, night: float) -> void:
	for x in [-40.0, -24.0, -8.0, 14.0, 28.0]:
		batch.add("street/street_lamp", Transform3D(Basis.IDENTITY, Vector3(x, CURB, -4.75)))
		if night > 0.3:
			_lamp(looks, Vector3(x, CURB + 5.7, -3.6), night)
	for x in [-32.0, -16.0, 0.0, 18.0, 34.0]:
		batch.add("street/street_lamp", Transform3D(Basis(Vector3.UP, PI), Vector3(x, CURB, 4.75)))
		if night > 0.3:
			_lamp(looks, Vector3(x, CURB + 5.7, 3.6), night)
	var props := [["street/bench", Vector3(-28.0, CURB, -6.9), 0.0], ["street/litter_bin", Vector3(-26.4, CURB, -7.2), 0.0],
		["street/planter", Vector3(-18.0, CURB, -7.0), 0.0], ["street/hydrant", Vector3(-1.0, CURB, -4.9), 0.0],
		["street/bollard", Vector3(3.2, CURB, -4.8), 0.0], ["street/bollard", Vector3(8.8, CURB, -4.8), 0.0],
		["street/sign_post", Vector3(26.0, CURB, -4.9), 0.0], ["street/utility_box", Vector3(-30.0, CURB, 7.3), PI],
		["street/bench", Vector3(-4.0, CURB, 7.2), PI], ["street/street_tree", Vector3(8.0, CURB, 6.4), 0.0],
		["street/street_tree", Vector3(24.0, CURB, 6.4), 0.8], ["street/dumpster", Vector3(-18.0, CURB, -20.0), PI * 0.5],
		["street/traffic_light", Vector3(28.6, CURB, 4.6), PI]]
	for p in props:
		batch.add(p[0], Transform3D(Basis(Vector3.UP, p[2]), p[1]))


static func _lamp(looks: Node3D, at: Vector3, night: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = Palette.color("sodium")
	l.light_energy = 3.0 * night
	l.omni_range = 13.0
	l.omni_attenuation = 0.8
	l.position = at
	looks.add_child(l)


static func _solid_box(solid: StaticBody3D, centre: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = centre
	solid.add_child(cs)


## A solid whose top edge runs from `a` to `b`, `width` across and
## `depth` straight down: stair walls follow their copings with one.
static func _prism(solid: StaticBody3D, a: Vector3, b: Vector3, width: float, depth: float) -> void:
	var along := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	var side := along.cross(Vector3.UP) * (width * 0.5)
	var pts := PackedVector3Array()
	for p in [a, b]:
		for s in [-1.0, 1.0]:
			pts.append(p + side * s)
			pts.append(p + side * s - Vector3.UP * depth)
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = shape
	solid.add_child(cs)


## A box to look at: `top` colours its top and `sides` the rest (both
## palette swatches), or `tint` all of it.
static func _look_box(looks: Node3D, centre: Vector3, size: Vector3, top: String, sides := "", tint := Color.WHITE) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	var colour := tint if top == "" else Palette.color(top)
	b.material = Look.flat(colour)
	m.mesh = b
	m.position = centre
	looks.add_child(m)
	if sides != "" and size.y > 0.2:
		# The top's colour as a thin slab over a body in the sides' colour.
		b.material = Look.flat(Palette.color(sides))
		var cap := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(size.x + 0.01, 0.06, size.z + 0.01)
		cb.material = Look.flat(colour)
		cap.mesh = cb
		cap.position = centre + Vector3.UP * (size.y * 0.5 - 0.025)
		looks.add_child(cap)


## The solid under a flight, so it reads as built into the hill.
static func _mass(looks: Node3D, bottom: Vector3, top: Vector3, width: float, colour: Color) -> void:
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
	looks.add_child(m)


static func _tube_node(points: PackedVector3Array, radius: float, swatch: String) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = Tube.mesh(points, radius, swatch, 10)
	return m


## Iron railings from `a` to `b` on the ground: a top rail, a bottom rail
## and bars.
static func _railings(a: Vector3, b: Vector3, height: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_uv(Palette.uv("iron_green"))
	for y in [height, 0.14]:
		Tube.add_to(st, PackedVector3Array([a + Vector3.UP * y, b + Vector3.UP * y]), RAIL_RADIUS, 8)
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var bars := int(length / 0.16)
	for i in bars + 1:
		var at := a + dir * (length * i / bars)
		var r := 0.035 if i % 12 == 0 else 0.012
		Tube.add_to(st, PackedVector3Array([at, at + Vector3.UP * (height + (0.08 if i % 12 == 0 else 0.0))]), r, 6)
	st.generate_normals()
	st.set_material(Look.material("Palette"))
	var m := MeshInstance3D.new()
	m.name = "Railings"
	m.mesh = st.commit()
	return m


# --- Playing in the yard ------------------------------------------------------

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			_opts[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	LGInput.register_actions(GameConfig.ACTIONS)
	world = build(self, true, str(_opts.get("time", "dusk")))
	skater = Skater.new()
	skater.lines = world.lines
	skater.look = {"main": Palette.color("signal_yellow"), "accent": Palette.color("neon_pink")}
	skater.look_seed = 4
	add_child(skater)
	skater.place(world.spawn, world.face)
	cam = StreetCamera.new()
	cam.target = skater
	add_child(cam)
	cam.current = true
	cam.snap()
	_make_hud()
	if _opts.has("shot"):
		await _shoot(str(_opts.shot), str(_opts.get("pose", "street")))
		get_tree().quit()
		return
	skater.reads_controls = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
				else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("map"):
		_spot = (_spot + 1) % 4
		var spots := [[world.spawn, world.face], [world.terrace, Vector3.BACK],
			[Vector3(-32.0, CURB, -6.0), Vector3.FORWARD], [Vector3(-20.0, 0.0, -2.5), Vector3.RIGHT]]
		skater.place(spots[_spot][0], spots[_spot][1])
		cam.snap()


func _make_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var box := VBoxContainer.new()
	box.position = Vector2(24, 20)
	layer.add_child(box)
	_meter = ProgressBar.new()
	_meter.custom_minimum_size = Vector2(240, 14)
	_meter.max_value = 1.0
	_meter.show_percentage = false
	box.add_child(_meter)
	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 5)
	box.add_child(_hud)


func _process(_delta: float) -> void:
	if skater == null or _hud == null:
		return
	for e in skater.take_events():
		if e.kind in ["grind_start", "wall_ride", "climb_top", "stumble", "bail", "line", "wall_kick"]:
			var text := str(e.kind).replace("_", " ")
			if e.kind == "line":
				text = "line x%d" % e.count
			elif e.kind == "grind_start":
				text = "grind: %s" % str(Lines.Kind.keys()[e.line_kind]).to_lower()
			_log.push_front(text)
			_log.resize(mini(_log.size(), 4))
	_meter.value = skater.flow
	var lines_text := "%s  %d km/h" % [skater.state_name(), roundi(skater.speed * 3.6)]
	if skater.state == Skater.State.GRIND:
		var bar := "-----|-----"
		var at := clampi(roundi((skater.balance + 1.0) * 5.0), 0, 10)
		lines_text += "\n" + bar.substr(0, at) + "o" + bar.substr(at + 1)
	if skater.line_count >= 2:
		lines_text += "\nline x%d" % skater.line_count
	_hud.text = lines_text + "\n" + "\n".join(_log)


# --- Pictures -----------------------------------------------------------------

## Drives the skater into a pose with scripted controls, then saves a
## picture from the calm camera.
func _shoot(path: String, pose: String) -> void:
	skater.set_physics_process(false)
	cam.interpolated = false
	cam.set_process(false)
	for i in 3:
		await get_tree().physics_frame
	var roof: Dictionary = world.roofs[0]
	var starts := {
		"skate": [Vector3(-30.0, 0.0, -1.5), Vector3.RIGHT], "grind": [world.terrace, Vector3.BACK],
		"kerb": [Vector3(-40.0, 0.0, -3.4), Vector3.RIGHT], "wall": [Vector3(-20.0, CURB, -7.3), Vector3.RIGHT],
		"climb": [Vector3(-32.0, CURB, -6.5), Vector3.FORWARD], "mantle": [Vector3(-32.0, CURB, -6.5), Vector3.FORWARD],
		"roof": [Vector3(-26.5, roof.y, -14.0), Vector3.BACK], "air": [Vector3(-30.0, 0.0, -1.5), Vector3.RIGHT],
		"stumble": [Vector3(-20.0, 9.0, -1.5), Vector3.RIGHT], "stand": [Vector3(-30.0, 0.0, -1.5), Vector3.RIGHT],
		"ollie": [Vector3(-30.0, 0.0, -1.5), Vector3.RIGHT], "kickflip": [Vector3(-30.0, 0.0, -1.5), Vector3.RIGHT],
		"manual": [Vector3(-30.0, 0.0, -1.5), Vector3.RIGHT], "slide": [Vector3(-40.0, 0.0, -0.8), Vector3.RIGHT],
		"paint": [Vector3(-30.0, 0.0, -1.5), Vector3.RIGHT], "kick": [Vector3(-30.0, 0.0, -1.5), Vector3.RIGHT],
	}
	var start: Array = starts.get(pose, [world.spawn, world.face])
	skater.place(start[0], start[1])
	for i in 600:
		skater.input.clear()
		_shot_input(pose, skater.input, i)
		skater.step(1.0 / 60.0)
		if _shot_ready(pose, i):
			break
	# A stumble reads best from the side, so that picture nudges the camera.
	var nudge := Vector2(0.9, 0.0) if pose in ["stumble", "kickflip", "ollie", "manual"] else Vector2.ZERO
	for i in 90:
		cam.update(1.0 / 60.0, nudge)
	if _opts.has("close"):
		# A close look at the writer from the front right, left or back, for the poses.
		var side := 1.0
		match str(_opts.close):
			"left":
				side = -1.0
			"back":
				side = 0.0
		var at := skater.global_position + Vector3.UP * 0.9
		var f := skater.facing
		var r := f.cross(Vector3.UP)
		var near := Camera3D.new()
		near.fov = 40.0
		add_child(near)
		var from := at + f * 2.6 + r * 1.6 * side if side != 0.0 else at - f * 3.0
		near.look_at_from_position(from + Vector3.UP * 0.4, at)
		near.make_current()
	for i in 24:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("yard: %s (%s, %s)" % [path, pose, skater.state_name()])


## The scripted controls for each picture.
func _shot_input(pose: String, inp: SkaterInput, i: int) -> void:
	match pose:
		"skate":
			inp.move = Vector3(1, 0, 0.12).normalized()
		"grind":
			inp.move = Vector3.BACK
			inp.grind = true
			inp.jump = skater.state == Skater.State.SKATE and skater.global_position.z > float(world.rail_top.z) - 1.7
		"kerb":
			inp.move = Vector3.RIGHT
			inp.grind = i > 90
		"wall":
			inp.move = Vector3(1, 0, -0.25).normalized() if i > 100 else Vector3.RIGHT
			inp.jump = i == 130
			inp.grind = i > 130
		"climb", "mantle":
			inp.move = Vector3.FORWARD * 0.6
			inp.stick = Vector2(0, 1)
		"roof":
			inp.move = Vector3.BACK * 0.5
		"air", "ollie":
			inp.move = Vector3.RIGHT
			inp.jump = i == 120
		"kickflip":
			inp.move = Vector3.RIGHT
			inp.jump = i == 120
			inp.trick_pressed = i == 126
		"manual":
			inp.move = Vector3.RIGHT
			inp.trick = i > 110
		"slide":
			inp.move = Vector3.RIGHT if i < 60 else Vector3(1, 0, -1).normalized()
			inp.jump = i == 68
			inp.grind = i > 60
		"paint", "kick":
			inp.move = Vector3.RIGHT if i < 60 else Vector3.ZERO
			if i == 100:
				skater.lock(true)


## Whether the skater has reached the pose for the picture.
func _shot_ready(pose: String, i: int) -> bool:
	match pose:
		"skate":
			return i >= 150
		"grind":
			return skater.state == Skater.State.GRIND and skater.global_position.y < 2.4
		"kerb":
			return skater.state == Skater.State.GRIND and skater.global_position.x > -22.0
		"wall":
			return skater.state == Skater.State.WALL and skater.global_position.x > -6.0
		"climb":
			return skater.state == Skater.State.CLIMB and skater.global_position.y > 6.0
		"mantle":
			return skater._c_mantle > 0.4
		"roof":
			return i >= 40
		"air":
			return i > 125 and skater.state == Skater.State.AIR and skater.velocity.y < 0.5
		"stand":
			return i >= 60
		"ollie":
			return i >= 128
		"kickflip":
			return i >= 135
		"manual":
			return i >= 150
		"slide":
			return skater.state == Skater.State.GRIND and skater.grind_trick != "" and skater._g_len > 1.0
		"paint":
			return i >= 160
		"kick":
			return i >= 112
		"stumble":
			return skater.stumble > 0.0 and skater.stumble < skater.STUMBLE_TIME
	return i >= 30
