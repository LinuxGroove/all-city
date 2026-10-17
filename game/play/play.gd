extends Node3D
## A night in a town: the town streams round a writer on skates at the
## foot of its best staircase, with traffic on its streets and the paint
## that's on its walls. Skate, grind, wall ride and climb; hold Paint at a
## wall to tag it. The walls are kept by WallStore (the game server's when
## online play is on, this copy's own record otherwise), so a tag stays,
## shows on everyone's copy of the town and goes when the Buff comes by
## at dawn.
##
## The town is Towns.current (Towns.play() sets it), or the first town
## there is. After `--`: --time=day|dusk|night.

## The town is up and the writer can play.
signal ready_to_play

## The tags a writer gets before choosing their own (Settings): one word,
## sometimes with a number, as tags are.
const TAG_WORDS := ["SALT", "NITE", "KRUSH", "VIBE", "DUSK", "RUSH", "ZEPH", "OKRA", "MOTH", "FLUX", "KITE",
	"JUNO", "RIFT", "BOLT", "HAZE", "ECHO", "SOAP", "TANK", "WISP", "FROG"]
## The can, and the crew's other colours.
const CAN := Color("3ff2ff")
## Seconds before a quarter's walls are read again on going back into it.
const REREAD := 120.0

var town := {}
var view: TownView
var skater: Skater
var cam: StreetCamera
var hud: PlayHud
var layer: PaintLayer
var store: WallStore
var action: PaintAction
var menu: PauseMenu
var card: TownCard
var mist: CPUParticles3D
## Set by tools and tests to paint without the controls.
var paint_override: PaintInput = null

var _opts := {}
## quarter id -> when its walls were last read (ticks in msec)
var _read := {}
var _can: Node3D
var _loading: CanvasLayer
var _ready_to_play := false


func is_playing() -> bool:
	return _ready_to_play


func _exit_tree() -> void:
	# The mouse goes back to the menus, however the night ended.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			_opts[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	town = Towns.current
	if town.is_empty():
		var all := Towns.list()
		town = all[0] if not all.is_empty() else {}
	if town.is_empty():
		LGScenes.change_scene(TitleScreen.SCENE, TitleScreen.with_message.bind("There are no towns here yet."))
		return
	Towns.current = town
	_show_loading()
	# Let the loading card draw before the town's first tiles are made.
	await get_tree().process_frame
	await get_tree().process_frame
	_build()


## Everything in the scene, round the town's spawn.
func _build() -> void:
	Look.dress(self, str(_opts.get("time", "dusk")))
	view = TownView.new()
	add_child(view)
	view.open(town)
	view.shifted.connect(_on_shifted)
	view.tile_shown.connect(_on_tile_shown)
	layer = PaintLayer.new(view.walls)
	add_child(layer)
	store = WallStore.new(str(town.id), int(town.get("utc_offset_min", 0)), true)
	store.changed.connect(_on_walls_changed)
	store.buffed.connect(_on_buffed)
	var spawn := view.spawn()
	view.load_around(spawn.p)
	skater = Skater.new()
	skater.name = "Skater"
	skater.lines = view.lines
	skater.female = int(LGSettings.get_value("player", "body", 0)) == 1
	skater.look = {"main": Palette.color("signal_yellow"), "accent": Palette.color("neon_pink")}
	skater.look_seed = 4
	# Cars are solid; they stop for a writer in the road, and nudge them out of it.
	skater.collision_mask |= Kit.LAYER_TRAFFIC
	add_child(skater)
	skater.place(spawn.p + Vector3.UP * 0.2, Basis(Vector3.UP, float(spawn.yaw)) * Vector3.FORWARD)
	view.traffic.watch = [skater]
	cam = StreetCamera.new()
	cam.target = skater
	add_child(cam)
	cam.current = true
	cam.snap()
	action = PaintAction.new(view.walls, skater, skater.lock, layer, store)
	action.facing = _facing
	action.rank = "tag"
	action.writer_name = _tag()
	action.colours = [CAN, Palette.color("ink"), Palette.color("cobalt")]
	action.line_changed.connect(_on_paint_line)
	action.started.connect(_on_paint_started)
	action.stopped.connect(_on_paint_ended)
	action.finished.connect(_on_paint_finished)
	action.stored.connect(_on_paint_stored)
	_make_mist()
	hud = PlayHud.new()
	add_child(hud)
	menu = PauseMenu.attach(self)
	menu.opened.connect(_on_menu_opened)
	var cards := CanvasLayer.new()
	cards.layer = 20
	add_child(cards)
	card = TownCard.new()
	cards.add_child(card)
	for key in view.shown():
		_on_tile_shown(key, view.shown()[key])
	_loading.queue_free()
	_loading = null
	card.show_town(town)
	skater.reads_controls = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	LGPlaytest.event("town", {"id": town.id})
	_ready_to_play = true
	ready_to_play.emit()


## The writer's tag: the player/tag setting, or one picked (and kept) the
## first time.
static func _tag() -> String:
	var tag := str(LGSettings.get_value("player", "tag", "")).strip_edges()
	if tag == "":
		tag = LGNameMaker.make([], null, 7, [""], TAG_WORDS)
		LGSettings.set_value("player", "tag", tag)
	return tag


func _physics_process(delta: float) -> void:
	if not _ready_to_play:
		return
	# Before the skater's own tick (children go after their parent), so a
	# move back round the origin lands before they move.
	view.follow(skater.position)
	view.traffic.focus = skater.position
	# Paint from your feet or from a climb, never mid-grind or mid-air.
	var can_paint := skater.state in [Skater.State.SKATE, Skater.State.CLIMB, Skater.State.PAINT]
	var paint := paint_override if paint_override else PaintInput.from_actions()
	action.step(paint if can_paint else PaintInput.make(false), delta)


func _process(delta: float) -> void:
	if not _ready_to_play:
		return
	hud.show_skater(skater, skater.take_events())
	var q := view.quarter_at(skater.position)
	hud.show_quarter(q, view.quarter_name(q))
	if q >= 0 and (not _read.has(q) or Time.get_ticks_msec() - int(_read[q]) > REREAD * 1000.0):
		_read_quarter(q)
	_prompt()
	_spray()


## "Hold Paint" at a wall that takes paint, while not painting.
func _prompt() -> void:
	if action.is_painting() or skater.state != Skater.State.SKATE:
		hud.prompt("")
		return
	var hit := action.target()
	if hit.is_empty() or int(hit.face.paint) == Walls.NEVER:
		hud.prompt("")
	else:
		hud.prompt("Hold Paint to tag this wall")


func _facing() -> Vector3:
	return skater.facing


func _on_shifted(by: Vector3) -> void:
	skater.shift(by)
	cam.shift(by)
	layer.shift(by)
	if mist:
		mist.global_position += by


func _on_tile_shown(key: Vector2i, near: bool) -> void:
	if not near:
		return
	layer.prune()
	for q in view.quarters_of(key):
		# What this copy knows at once, then the server's when it answers.
		layer.show_quarter(q, store.walls_in(q), store.now())
		if not _read.has(q):
			_read_quarter(q)


func _read_quarter(q: int) -> void:
	_read[q] = Time.get_ticks_msec()
	store.read_quarter(q)


func _on_walls_changed(q: int) -> void:
	if is_instance_valid(layer):
		layer.show_quarter(q, store.walls_in(q), store.now())


func _on_buffed(_q: int, gone: PackedStringArray) -> void:
	if is_instance_valid(hud) and not gone.is_empty():
		hud.say("The Buff came by: %d gone" % gone.size())


# --- Painting -----------------------------------------------------------------

func _on_paint_line(text: String) -> void:
	hud.say(text)


func _on_paint_started(face: Dictionary, _kit: Dictionary) -> void:
	# Face the wall: its outside is on the right going from a to b.
	var out: Vector3 = (face.b - face.a).cross(Vector3.UP)
	out.y = 0.0
	if out.length() > 0.01:
		skater.facing = -out.normalized()
	if skater.person and _can == null:
		_can = skater.person.hold_can(CAN)
	LGPlaytest.event("paint_start", {"wall": str(face.id)})


func _on_paint_ended() -> void:
	_drop_can()


func _on_paint_finished(result: Dictionary) -> void:
	_drop_can()
	hud.say(str(result.get("label", "")))
	LGPlaytest.moment("tag", {"grade": int(result.get("grade", 0))})


func _on_paint_stored(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		hud.say(PaintAction.REFUSED.get(str(result.get("reason", "")), "Didn't stick, try again"))


func _drop_can() -> void:
	if _can:
		# The can hangs off a BoneAttachment3D the person added for it.
		_can.get_parent().queue_free()
		_can = null


func _spray() -> void:
	var preview := layer.preview()
	mist.emitting = action.is_painting() and preview != null
	if mist.emitting:
		var n := action.nozzle()
		mist.global_position = preview.global_transform * Vector3(n.x - 0.5, 0.5 - n.y, 0.08)


func _make_mist() -> void:
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


# --- Loading and the menu ---------------------------------------------------------

func _show_loading() -> void:
	_loading = CanvasLayer.new()
	_loading.layer = 50
	add_child(_loading)
	var bg := ColorRect.new()
	bg.color = CityTheme.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	var l := CityTheme.label(str(town.get("name", town.id)).to_upper(), 64, CityTheme.TEXT, CityTheme.heading(), 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(l)


func _on_menu_opened() -> void:
	# Painting stops when the menu opens; the wall waits.
	if action.is_painting():
		action.step(PaintInput.make(false), PaintAction.LET_GO + 0.01)
