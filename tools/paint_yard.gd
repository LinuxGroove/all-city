extends Node3D
## A street to try painting on: a works building with a blank ground floor,
## a row of shops with a rival's tag already up, and a church on the
## respect list. Walk with the stick or WASD, hold paint (E, the left mouse
## button or X) at a wall and push the stick along the dots. The walls are
## kept offline in user://walls/paint-yard.json.
##
##   godot --path . tools/paint_yard.tscn [-- --rank=throwup --name=SALT --time=day]
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
##       godot --path . --resolution 1280x720 tools/paint_yard.tscn -- --shot=/tmp/claude-0/paint/tag.png
##
## With --shot it paints by itself, saving the wall mid-way as
## <name>_painting.png, the finished paint close up as <name>.png and the
## street as <name>_street.png, then quits.

const TOWN := "paint-yard"
const WALK := 3.2
const CAN := Color("3ff2ff")

var walls := Walls.new()
var layer: PaintLayer
var store: WallStore
var action: PaintAction
var writer: Person
var cam: Camera3D
var mist: CPUParticles3D
var line_label: Label
var _locked := false
var _opts := {}
var _shot := ""


func _ready() -> void:
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	LGInput.register_actions(GameConfig.ACTIONS)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			_opts[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	_shot = str(_opts.get("shot", ""))
	Look.dress(self, str(_opts.get("time", "dusk")))
	_street()
	layer = PaintLayer.new(walls)
	add_child(layer)
	store = WallStore.new(TOWN, 0, false)
	if _shot != "":
		store.forget()
	_rival()
	for id in [1, 2, 3]:
		layer.show_quarter(id, store.walls_in(id), store.now())
	writer = Person.make("writer", false, 9, {"main": Palette.color("purple"), "accent": Palette.color("hivis")})
	add_child(writer)
	writer.position = Vector3(-6.2, 0.15, -6.9)
	writer.rotation.y = PI
	writer.hold_can(CAN)
	writer.play("Idle")
	action = PaintAction.new(walls, writer, _lock, layer, store)
	action.rank = str(_opts.get("rank", "tag"))
	action.writer_name = str(_opts.get("name", "SALT"))
	action.colours = [CAN, Palette.color("ink"), Palette.color("cobalt")]
	action.line_changed.connect(_on_line)
	action.started.connect(_on_started)
	action.stopped.connect(_on_ended)
	action.finished.connect(_on_finished)
	_mist()
	_hud()
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 400.0
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)
	cam.current = true
	_follow(1.0)
	if _shot != "":
		_auto.call_deferred()


## The street: buildings along the far side of a road, their fronts the
## walls (outsides towards the camera, +z).
func _street() -> void:
	var batch := Batch.new()
	var curb := 0.15
	_box(Vector3(0, -0.5, 0), Vector3(90, 1.0, 8.0), Palette.color("asphalt"))
	_box(Vector3(0, curb * 0.5 - 0.5, -6.15), Vector3(90, 1.0 + curb, 4.0), Palette.color("paving"))
	_box(Vector3(0, curb * 0.5 - 0.48, -4.13), Vector3(90, 1.0 + curb, 0.26), Palette.color("kerb"))
	var far := -8.15
	var buildings := [
		{"id": "w0000000a1", "x0": -12.0, "x1": 0.0, "storeys": 3, "style": "works", "ground": "blank", "seed": 4,
			"paint": Walls.ALL, "eyes": 60, "quarter": 1},
		{"id": "w0000000b1", "x0": 0.0, "x1": 12.0, "storeys": 4, "style": "plaster", "ground": "shop", "seed": 11,
			"paint": Walls.GROUND, "eyes": 80, "quarter": 2},
		{"id": "w0000000c1", "x0": -26.0, "x1": -12.0, "storeys": 3, "style": "brick", "ground": "home", "seed": 3,
			"paint": Walls.NEVER, "eyes": 40, "quarter": 3},
	]
	for b in buildings:
		var rec := Facade.recipe(b.style, b.ground, b.seed)
		rec.pipe = false
		rec.escape = false
		var a := Vector3(b.x0, curb, far)
		var e := Vector3(b.x1, curb, far)
		var laid := Facade.lay(batch, a, e, b.storeys, rec, b.seed, Vector2i(1, 1))
		var h: float = b.storeys * Facade.STOREY
		_box(Vector3((b.x0 + b.x1) * 0.5, curb, far - 7.3), Vector3(b.x1 - b.x0 - 0.6, h, 13.4), rec.wall)
		_box(Vector3((b.x0 + b.x1) * 0.5, curb + h, far - 7.3), Vector3(b.x1 - b.x0 - 0.6, 0.3, 13.4),
				Palette.color("concrete_dark"))
		walls.add({"id": b.id, "a": a, "b": e, "base": curb, "top": float(laid.crest), "paint": b.paint,
			"eyes": b.eyes, "quarter": b.quarter})
	for p in [["street/street_lamp", -16.0], ["street/bench", 4.5], ["street/litter_bin", 7.0], ["street/bollard", -2.0]]:
		batch.add(p[0], Transform3D(Basis.IDENTITY, Vector3(p[1], curb, -4.75)))
	batch.build(self)


## A rival's tag, already up on the shops.
func _rival() -> void:
	var kit := TagKit.kit_for("NITE", "tag", [Palette.color("signal_yellow"), Palette.color("ink")])
	kit.at = [7.6, 1.5]
	var walls_q := store.walls_in(2)
	if not walls_q.has("w0000000b1"):
		walls_q["w0000000b1"] = {"writer": "rival", "name": "NITE", "rank": "tag", "kit": kit, "grade": 70,
			"eyes": 80, "heaven": false, "at": store.now() - 3600 * 30, "capped": false}


func _physics_process(delta: float) -> void:
	var input := PaintInput.from_actions() if _shot == "" else _auto_input()
	action.step(input, delta)
	if not _locked and _shot == "":
		var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if move.length() > 0.1:
			var dir := Vector3(move.x, 0, move.y)
			writer.position += dir * WALK * delta
			writer.position.z = clampf(writer.position.z, -7.6, 3.5)
			writer.rotation.y = lerp_angle(writer.rotation.y, atan2(dir.x, dir.z), minf(1.0, delta * 10.0))
			writer.play("Jog_Fwd")
		else:
			writer.play("Idle")
	_spray()
	_follow(delta)


## The camera: behind the writer, over their left shoulder, easing after
## them; never shakes.
func _follow(delta: float) -> void:
	if _framed:
		return
	var target := writer.position + Vector3(-1.6, 2.1, 4.6)
	cam.position = cam.position.lerp(target, minf(1.0, delta * 3.0)) if delta < 1.0 else target
	cam.look_at(writer.position + Vector3(0.7, 1.4, -1.4), Vector3.UP)


func _spray() -> void:
	var preview := layer.preview()
	mist.emitting = action.is_painting() and preview != null
	if mist.emitting:
		var n := action.nozzle()
		mist.global_position = preview.global_transform * Vector3(n.x - 0.5, 0.5 - n.y, 0.08)


func _mist() -> void:
	mist = CPUParticles3D.new()
	mist.name = "Mist"
	mist.amount = 40
	mist.lifetime = 0.35
	mist.emitting = false
	mist.local_coords = false
	mist.direction = Vector3(0, 0, 1)
	mist.spread = 40.0
	mist.gravity = Vector3.ZERO
	mist.initial_velocity_min = 0.1
	mist.initial_velocity_max = 0.35
	mist.scale_amount_min = 0.6
	mist.scale_amount_max = 1.4
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(CAN, 0.35)
	m.vertex_color_use_as_albedo = true
	quad.material = m
	mist.mesh = quad
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.8))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	mist.color_ramp = fade
	add_child(mist)


func _hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	var hint := Label.new()
	hint.text = "Hold paint at a wall, then push the stick along the dots."
	hint.position = Vector2(24, 18)
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_outline_color", Palette.color("ink"))
	hint.add_theme_constant_override("outline_size", 6)
	hud.add_child(hint)
	line_label = Label.new()
	line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	line_label.offset_top = -90
	line_label.offset_bottom = -40
	line_label.offset_left = -300
	line_label.offset_right = 300
	line_label.add_theme_font_override("font", load("res://assets/fonts/Bungee-Regular.ttf"))
	line_label.add_theme_font_size_override("font_size", 34)
	line_label.add_theme_color_override("font_outline_color", Palette.color("ink"))
	line_label.add_theme_constant_override("outline_size", 10)
	hud.add_child(line_label)
	if _shot != "":
		hint.visible = false


func _lock(on: bool) -> void:
	_locked = on


func _on_line(text: String) -> void:
	line_label.text = text


func _on_started(_face: Dictionary, _kit: Dictionary) -> void:
	writer.play("Pistol_Aim_Neutral")


func _on_ended() -> void:
	writer.play("Idle")


func _on_finished(_result: Dictionary) -> void:
	writer.play("Idle")


# --- The screenshot -------------------------------------------------------------

var _auto_on := false
var _framed := false


func _auto_input() -> PaintInput:
	if not _auto_on or action.state == PaintAction.State.DONE:
		return PaintInput.make(false)
	return PaintInput.make(true, action.guide_direction() * 0.8)


func _auto() -> void:
	for i in 20:
		await get_tree().physics_frame
	_auto_on = true
	var saved_mid := false
	while action.state != PaintAction.State.DONE:
		await get_tree().physics_frame
		if not saved_mid and action.progress() > 0.55:
			saved_mid = true
			await _save(_shot.get_basename() + "_painting.png")
	_auto_on = false
	# Step back and look at the wall while the drips run.
	writer.position = Vector3(-2.6, 0.15, -5.4)
	writer.rotation.y = -0.5
	_framed = true
	var kit_at := PaintLayer.place(action.face, action.kit, TagKit.art(action.kit).aspect).origin
	cam.position = kit_at + Vector3(0.9, 0.2, 3.4)
	cam.look_at(kit_at + Vector3(0.2, -0.1, 0), Vector3.UP)
	for i in 60 * 5:
		await get_tree().physics_frame
	await _save(_shot)
	cam.position = Vector3(-1.0, 2.0, 2.6)
	cam.look_at(Vector3(-1.0, 1.7, -8.15), Vector3.UP)
	for i in 10:
		await get_tree().physics_frame
	await _save(_shot.get_basename() + "_street.png")
	get_tree().quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("paint_yard: ", path)


func _box(base: Vector3, size: Vector3, colour: Color) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = Look.flat(colour)
	m.mesh = b
	m.position = base + Vector3.UP * (size.y * 0.5)
	add_child(m)
