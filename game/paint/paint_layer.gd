class_name PaintLayer
extends Node3D
## The paint on the town's walls: one quad per painted wall face, carrying
## its kit's drawing (TagKit) in game/paint/paint.gdshader, a couple of
## centimetres off the wall along its outward normal. Never Decal nodes:
## hundreds per quarter would cost too much. Paint shows only on faces
## `walls` has loaded; the rest waits for its tile.
##
## The paint a layer shows is what WallStore says is on the walls (records
## as the server keeps them: rank, kit, at, ...). A writer's tag in
## progress is a preview quad that PaintAction drives.

const SHADER := preload("res://game/paint/paint.gdshader")
## How far paint stands off its wall.
const LIFT := 0.02
## How long paint stays wet, in seconds: it shines.
const WET := 20.0
## How long its drips take to run, in seconds.
const DRIP_RUN := 4.0
## Drip widths per style, in quad heights.
const DRIP_WIDTH := {"handstyle": 0.022, "bubble": 0.016}

var walls: Walls

## wall id -> {node, record, quarter}
var _shown := {}
var _preview: MeshInstance3D
var _quad := QuadMesh.new()


func _init(p_walls: Walls = null) -> void:
	name = "Paint"
	walls = p_walls
	_quad.size = Vector2.ONE


func _ready() -> void:
	apply_comfort()
	LGSettings.changed.connect(_on_setting)


func _exit_tree() -> void:
	if LGSettings.changed.is_connected(_on_setting):
		LGSettings.changed.disconnect(_on_setting)


## Shows a wall's paint (its record), replacing what was there. Returns the
## quad, or null when the wall isn't loaded or the paint has faded.
func show_paint(id: String, record: Dictionary, now: int) -> MeshInstance3D:
	remove_paint(id)
	var face := walls.face(id) if walls else {}
	if face.is_empty() or not PaintRules.LIFE.has(str(record.get("rank", ""))) or PaintRules.faded(record, now):
		return null
	var kit: Dictionary = record.get("kit", {})
	var art := TagKit.art(kit)
	var node := MeshInstance3D.new()
	node.name = id
	node.mesh = _quad
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.transform = place(face, kit, art.aspect)
	var mat := material(kit, art)
	node.material_override = mat
	add_child(node)
	_shown[id] = {"node": node, "record": record, "quarter": int(face.quarter)}
	_age(id, now)
	return node


func remove_paint(id: String) -> void:
	if _shown.has(id):
		_free(_shown[id].node)
		_shown.erase(id)


## Shows exactly `records` ({wall id: record}) on a quarter's walls: paint
## shown there before and missing from them goes.
func show_quarter(quarter: int, records: Dictionary, now: int) -> void:
	for id in _shown.keys():
		if int(_shown[id].quarter) == quarter and not records.has(id):
			remove_paint(id)
	for id in records:
		var was: Dictionary = _shown.get(id, {})
		if was.is_empty() or was.record != records[id]:
			show_paint(id, records[id], now)


## Takes away paint on walls `walls` no longer has (their tile went).
func prune() -> void:
	for id in _shown.keys():
		if walls == null or walls.face(id).is_empty():
			remove_paint(id)


## The wall ids showing paint.
func shown() -> PackedStringArray:
	return PackedStringArray(_shown.keys())


## Brings every quad's age up to `now`, and takes away faded paint.
func refresh(now: int) -> void:
	for id in _shown.keys():
		if PaintRules.faded(_shown[id].record, now):
			remove_paint(id)
		else:
			_age(id, now)


func _process(_delta: float) -> void:
	# Only wet paint changes from second to second.
	var now := int(Time.get_unix_time_from_system())
	for id in _shown:
		var rec: Dictionary = _shown[id].record
		if now - int(rec.at) <= WET + 1:
			_age(id, now)


func _age(id: String, now: int) -> void:
	var rec: Dictionary = _shown[id].record
	var mat: ShaderMaterial = _shown[id].node.material_override
	var age := float(maxi(now - int(rec.at), 0))
	mat.set_shader_parameter("fade", clampf(age / float(PaintRules.LIFE[rec.rank]), 0.0, 1.0))
	mat.set_shader_parameter("wet", 1.0 - clampf(age / WET, 0.0, 1.0))
	mat.set_shader_parameter("drip_run", clampf(age / DRIP_RUN, 0.0, 1.0))


## Where a kit's quad goes on a face: centred on the kit's "at" (metres
## along a→b, height above the base), facing out, LIFT off the wall.
static func place(face: Dictionary, kit: Dictionary, aspect: float) -> Transform3D:
	var a: Vector3 = face.a
	var b: Vector3 = face.b
	var along := Vector3(b.x - a.x, 0, b.z - a.z)
	var d := along.normalized()
	var out := Vector3(-d.z, 0, d.x)
	var at: Array = kit.get("at", [along.length() * 0.5, 1.5])
	var h := float(kit.get("h", TagKit.HEIGHT.tag))
	var centre := Vector3(a.x, float(face.base), a.z) + d * float(at[0]) + Vector3.UP * float(at[1]) + out * LIFT
	return Transform3D(Basis(d * h * aspect, Vector3.UP * h, out), centre)


## A quad's material for a kit (fresh and dry; `_age` sets the rest).
static func material(kit: Dictionary, art: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var cols: Array = kit.get("colours", TagKit.COLOURS)
	var fill := _colour(cols, 0)
	m.set_shader_parameter("fill_mask", art.fill)
	m.set_shader_parameter("ink_mask", art.ink)
	m.set_shader_parameter("fill_colour", fill)
	m.set_shader_parameter("ink_colour", _colour(cols, 1))
	var style := str(kit.get("style", "handstyle"))
	m.set_shader_parameter("fill_colour2", _colour(cols, 2) if style == "bubble" else fill)
	m.set_shader_parameter("bevel", 0.55 if style == "bubble" else 0.0)
	m.set_shader_parameter("aspect", float(art.aspect))
	m.set_shader_parameter("wobble", clampf(float(kit.get("wobble", 0.0)), 0.0, 1.0))
	m.set_shader_parameter("seed", float(int(kit.get("seed", 0)) % 1000) * 0.37)
	set_drips(m, kit.get("drips", []), style)
	return m


## Puts a kit's drips on a material: [x, y, length] each, with a fourth 1
## for a drip that already ran while it was painted.
static func set_drips(m: ShaderMaterial, drips: Array, style: String) -> void:
	var list := PackedVector4Array()
	for d in drips:
		if d is Array and d.size() >= 3 and list.size() < TagKit.MAX_DRIPS:
			list.append(Vector4(float(d[0]), float(d[1]), float(d[2]), float(d[3]) if d.size() > 3 else 0.0))
	var count := list.size()
	while list.size() < TagKit.MAX_DRIPS:
		list.append(Vector4.ZERO)
	m.set_shader_parameter("drips", list)
	m.set_shader_parameter("drip_count", count)
	m.set_shader_parameter("drip_width", float(DRIP_WIDTH.get(style, 0.02)))


static func _colour(cols: Array, i: int) -> Color:
	var hex := str(cols[i]) if i < cols.size() else str(TagKit.COLOURS[i])
	return Color.html(hex) if Color.html_is_valid(hex) else Color.html(TagKit.COLOURS[i])


# --- A tag in progress --------------------------------------------------------

## Starts showing a writer's paint going on: the letters as a faint guide,
## nothing painted yet.
func begin_preview(face: Dictionary, kit: Dictionary) -> MeshInstance3D:
	end_preview()
	var art := TagKit.art(kit)
	_preview = MeshInstance3D.new()
	_preview.name = "Painting"
	_preview.mesh = _quad
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview.transform = place(face, kit, art.aspect)
	# A hair further out, over any paint it's going over.
	_preview.position += _preview.transform.basis.z.normalized() * 0.005
	var m := material(kit, art)
	m.set_shader_parameter("reveal", 0.0)
	m.set_shader_parameter("ghost", 1.0)
	m.set_shader_parameter("wet", 1.0)
	# Only drips made while painting show; the rest run once it's done.
	m.set_shader_parameter("drip_run", 0.0)
	_preview.material_override = m
	add_child(_preview)
	return _preview


## Moves the preview on: painted up to `reveal` (UV x), the spray at
## `nozzle` (UV), the next guide points, the drips and wobble so far.
func update_preview(reveal: float, nozzle: Vector2, ahead: PackedVector2Array, kit: Dictionary) -> void:
	if _preview == null:
		return
	var m: ShaderMaterial = _preview.material_override
	m.set_shader_parameter("reveal", reveal)
	m.set_shader_parameter("nozzle", nozzle)
	var list := PackedVector4Array()
	for p in ahead.slice(0, 6):
		list.append(Vector4(p.x, p.y, 0, 0))
	var count := list.size()
	while list.size() < 6:
		list.append(Vector4(-9, -9, 0, 0))
	m.set_shader_parameter("ahead", list)
	m.set_shader_parameter("ahead_count", count)
	m.set_shader_parameter("wobble", clampf(float(kit.get("wobble", 0.0)), 0.0, 1.0))
	set_drips(m, kit.get("drips", []), str(kit.get("style", "handstyle")))


func end_preview() -> void:
	if _preview:
		_free(_preview)
		_preview = null


func preview() -> MeshInstance3D:
	return _preview


## Takes a quad off now (so a new one can have its name) and frees it.
func _free(node: Node) -> void:
	if node.get_parent() == self:
		remove_child(node)
	node.queue_free()


## Moves every quad by `offset`, when the world's origin is re-centred (the
## walls move with Walls.shift).
func shift(offset: Vector3) -> void:
	for c in get_children():
		if c is Node3D:
			c.position += offset


## Sets the paint's shine from the Reduce flashing setting (the `steady`
## shader global, which the drone's light reads too).
static func apply_comfort() -> void:
	var steady := bool(LGSettings.get_value("comfort", "reduce_flashing", false))
	RenderingServer.global_shader_parameter_set("steady", 1.0 if steady else 0.0)


func _on_setting(section: String, key: String, _value: Variant) -> void:
	if section == "comfort" and key == "reduce_flashing":
		apply_comfort()
