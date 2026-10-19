class_name TownMap
extends CanvasLayer
## The town map (the Map button, M on a keyboard): the whole town from
## above, streets light on a dark ground with parks, water and every roof,
## the quarters named and tinted, the paint standing on the walls and the
## writer as a yellow arrow. It holds the game while it's open; the stick
## (or the mouse dragged) looks round, the wheel, + and -, or the triggers
## zoom, and Jump comes back to the writer.
##
## The play scene adds one, calls [method load_town] once the town is up
## (the tiles are read on a worker thread, a little at low priority, so the
## night never stalls), and sets [member writer] and [member store].
## Tests load synchronously with `load_town(town, false)`.

signal opened
signal closed
## The picture's ready.
signal loaded

## Zoom is pixels a metre: the most, and where it opens.
const ZOOM_MAX := 3.0
const ZOOM_START := 0.8
## How fast the stick looks round, in screen pixels a second.
const PAN_SPEED := 560.0
## How much a wheel notch or a key press zooms by.
const NOTCH := 1.18
## Ground tiles made a frame, so the map comes up without a hitch.
const BATCH := 6
## Tiles overlap by this much, in metres, so no seams show between them.
const OVERLAP := 0.5
## Water's colour, and how strongly the quarters are tinted.
const WATER := Color("1f5a86")
const TINT := 0.2

## The town being shown (the manifest, as Towns gives it).
var town := {}
## The writer now: {p: Vector3 in town metres, dir: Vector3}.
var writer := Callable()
## Where the paint on the map is read from.
var store: WallStore
## Asked before the map opens; return false while it mustn't (menu up).
var can_open := Callable()
## Whether pressing Map opens and closes it.
var listen := true
## Whether opening the map stops the game (online play would keep going).
var hold_tree := true
## What the map was made from (TownMapData.read), or {} before it's ready.
var data := {}
## The town metre in the middle of the screen, and pixels a metre.
var centre := Vector2.ZERO
var zoom := ZOOM_START

var _root: Control
var _world: Node2D
var _overlay: Control
var _title: Label
var _hint: Label
var _credit: Label
var _wait: Label
var _tags: Array[Dictionary] = []
var _me := {"p": Vector2.ZERO, "dir": Vector2.UP}
var _thread: Thread
var _queue: Array[Callable] = []
var _built := false
var _cancel := {"stop": false}
var _mouse_mode := Input.MOUSE_MODE_VISIBLE


func _init() -> void:
	name = "TownMap"
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = CityTheme.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	_world = Node2D.new()
	_world.name = "World"
	_root.add_child(_world)
	_overlay = _Overlay.new()
	(_overlay as _Overlay).map = self
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_overlay)
	_title = CityTheme.label("", 40, CityTheme.TEXT, CityTheme.heading(), 10)
	_title.position = Vector2(28, 20)
	_root.add_child(_title)
	_hint = CityTheme.label("", 18, CityTheme.CREAM, CityTheme.text(640), 6)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_left = 28
	_hint.offset_right = -28
	_hint.offset_top = -92
	_hint.offset_bottom = -64
	_root.add_child(_hint)
	_credit = CityTheme.label("", 14, CityTheme.DIM, CityTheme.text(560), 5)
	_credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_credit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_credit.offset_left = 28
	_credit.offset_right = -28
	_credit.offset_top = -58
	_credit.offset_bottom = -12
	_root.add_child(_credit)
	_wait = CityTheme.label("Drawing the map...", 30, CityTheme.TEXT, CityTheme.heading(), 8)
	_wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wait.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_wait.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.add_child(_wait)


func _exit_tree() -> void:
	_cancel.stop = true
	if _thread:
		_thread.wait_to_finish()
		_thread = null


func is_open() -> bool:
	return visible


## Whether the picture is drawn and can be shown.
func is_loaded() -> bool:
	return _built


## Starts reading `p_town`'s tiles into a picture: on a worker thread (the
## map says `loaded` when it's ready), or right away.
func load_town(p_town: Dictionary, threaded := true) -> void:
	town = p_town
	_wait.text = "Drawing the map..."
	_title.text = str(town.get("name", "")).to_upper()
	_credit.text = "\n".join(PackedStringArray(town.get("attribution", [])))
	if threaded:
		_cancel = {"stop": false}
		_thread = Thread.new()
		_thread.start(TownMapData.read.bind(town, _cancel), Thread.PRIORITY_LOW)
	else:
		_show(TownMapData.read(town), true)


func _process(delta: float) -> void:
	if _thread and not _thread.is_alive():
		var read = _thread.wait_to_finish()
		_thread = null
		_show(read if read is Dictionary else {}, false)
	if not _queue.is_empty():
		_queue.pop_front().call()
	if not visible:
		return
	var pan := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if pan != Vector2.ZERO:
		set_view(centre + pan * PAN_SPEED * delta / zoom, zoom)
	if Input.is_action_pressed("boost"):
		zoom_by(pow(2.0, delta * 1.6))
	if Input.is_action_pressed("look_back"):
		zoom_by(pow(2.0, -delta * 1.6))
	_place()
	_overlay.queue_redraw()


# --- The picture ---------------------------------------------------------------

## Makes the nodes from what the worker read: a few a frame, or all of them
## now.
func _show(read: Dictionary, now: bool) -> void:
	for c in _world.get_children():
		c.queue_free()
	_queue.clear()
	_built = false
	data = read
	if data.is_empty():
		_wait.text = "No map for this town."
		_wait.visible = visible
		return
	var ground := ShaderMaterial.new()
	ground.shader = load("res://game/look/shaders/map_ground.gdshader")
	var tiles: Array = data.ground
	for k in range(0, tiles.size(), BATCH):
		_queue.append(_add_ground.bind(tiles.slice(k, k + BATCH), ground))
	_queue.append(_add_tint)
	_queue.append(_add_water)
	_queue.append(_add_roofs)
	_queue.append(_finish)
	while now and not _queue.is_empty():
		_queue.pop_front().call()


func _add_ground(tiles: Array, material: ShaderMaterial) -> void:
	var px := int(data.pixels)
	for g in tiles:
		var s := Sprite2D.new()
		s.centered = false
		s.texture = ImageTexture.create_from_image(g.image)
		s.material = material
		var key: Vector2i = g.key
		s.position = Vector2(key.x, key.y) * TownTiles.SIZE - Vector2.ONE * OVERLAP * 0.5
		s.scale = Vector2.ONE * (TownTiles.SIZE + OVERLAP) / float(px)
		_world.add_child(s)


func _add_tint() -> void:
	_world.add_child(_tint(data.cells))


func _add_water() -> void:
	var w: Dictionary = data.water
	if w.indices.is_empty():
		return
	var water := MeshInstance2D.new()
	water.mesh = _mesh(w.verts, w.indices)
	water.modulate = WATER
	_world.add_child(water)


func _add_roofs() -> void:
	var r: Dictionary = data.roofs
	if r.indices.is_empty():
		return
	var roofs := MeshInstance2D.new()
	roofs.mesh = _mesh(r.verts, r.indices, r.colors)
	_world.add_child(roofs)


func _finish() -> void:
	_built = true
	_wait.visible = false
	zoom = clampf(ZOOM_START, min_zoom(), ZOOM_MAX)
	var box: Rect2 = data.box
	centre = box.get_center()
	if visible:
		_look_for_writer()
	_place()
	loaded.emit()


## The quarters as one tinted pixel a cell, drawn over the ground.
func _tint(cells: Dictionary) -> Sprite2D:
	var cols := int(cells.cols)
	var rows := int(cells.rows)
	var img := Image.create(cols, rows, false, Image.FORMAT_RGBA8)
	var ids: PackedInt32Array = cells.ids
	for k in ids.size():
		if ids[k] >= 0:
			img.set_pixel(k % cols, k / cols, Color(TownMapData.quarter_colour(ids[k]), TINT))
	var s := Sprite2D.new()
	s.centered = false
	s.texture = ImageTexture.create_from_image(img)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var origin: Vector2i = cells.origin
	s.position = Vector2(origin.x, origin.y) * TownTiles.SIZE
	s.scale = Vector2.ONE * TownTiles.SIZE / float(TownMapData.CELLS)
	return s


static func _mesh(verts: PackedVector2Array, indices: PackedInt32Array, colors := PackedColorArray()) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- Opening and closing -------------------------------------------------------

## Opens the map (the Map button) on the writer, and holds the game.
func open() -> void:
	if visible or not is_inside_tree():
		return
	if can_open.is_valid() and not bool(can_open.call()):
		return
	visible = true
	_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hold_tree:
		get_tree().paused = true
	LGAudio.pause_game(true)
	_wait.visible = not _built
	_tags = tags()
	_look_for_writer()
	_hint.text = hint()
	LGPlaytest.event("map_open", {})
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	if is_inside_tree():
		if hold_tree:
			get_tree().paused = false
		LGAudio.pause_game(false)
	Input.mouse_mode = _mouse_mode
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not listen:
		return
	if event.is_action_pressed("map"):
		get_viewport().set_input_as_handled()
		if visible:
			close()
		else:
			open()
		return
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif event.is_action_pressed("jump"):
		get_viewport().set_input_as_handled()
		_look_for_writer()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(NOTCH, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / NOTCH, event.position)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		set_view(centre - event.relative / zoom, zoom)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]:
			zoom_by(NOTCH * 1.1)
		elif event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			zoom_by(1.0 / (NOTCH * 1.1))


## What the bottom line says to press, for the device used last.
func hint() -> String:
	var map_key := LGInput.label_for_action("map")
	var back := LGInput.label_for_action("jump")
	if LGInput.is_gamepad():
		return "Stick: look round    Triggers: zoom    %s: back to you    %s: close" % [back, map_key]
	return "Move or drag: look round    Wheel, + and -: zoom    %s: back to you    %s: close" % [back, map_key]


# --- The view -------------------------------------------------------------------

## The smallest zoom: the whole town in the window.
func min_zoom() -> float:
	if data.is_empty():
		return 0.1
	var box: Rect2 = data.box
	var size := _size()
	return minf(size.x / box.size.x, size.y / box.size.y)


## Looks at `at` (town metres) at `z` pixels a metre, kept on the town.
func set_view(at: Vector2, z: float) -> void:
	zoom = clampf(z, min_zoom(), ZOOM_MAX)
	if data.is_empty():
		centre = at
	else:
		var box: Rect2 = data.box
		centre = Vector2(clampf(at.x, box.position.x, box.end.x), clampf(at.y, box.position.y, box.end.y))
	_place()


## Zooms by `factor`, keeping the spot at screen position `about` (the middle
## when it isn't given) where it is.
func zoom_by(factor: float, about := Vector2(-1, -1)) -> void:
	var size := _size()
	var from := about if about.x >= 0.0 else size * 0.5
	var fixed := to_map(from)
	var before := zoom
	zoom = clampf(zoom * factor, min_zoom(), ZOOM_MAX)
	if about.x >= 0.0 and zoom != before:
		centre = fixed - (from - size * 0.5) / zoom
	set_view(centre, zoom)


## Where the writer is, in the middle.
func _look_for_writer() -> void:
	if writer.is_valid():
		var w = writer.call()
		if w is Dictionary and w.has("p"):
			var p: Vector3 = w.p
			var d: Vector3 = w.get("dir", Vector3.FORWARD)
			_me = {"p": Vector2(p.x, p.z), "dir": Vector2(d.x, d.z).normalized() if Vector2(d.x, d.z).length() > 0.01 else Vector2.UP}
	set_view(_me.p, maxf(zoom, ZOOM_START))


func _size() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 800)


func _place() -> void:
	_world.scale = Vector2.ONE * zoom
	_world.position = _size() * 0.5 - centre * zoom


## A town metre's place on the screen.
func to_screen(p: Vector2) -> Vector2:
	return (p - centre) * zoom + _size() * 0.5


## A screen place's town metre.
func to_map(screen: Vector2) -> Vector2:
	return (screen - _size() * 0.5) / zoom + centre


# --- Paint and quarters ---------------------------------------------------------

## The paint standing on the town as this copy knows it: [{p: Vector2 (the
## wall's middle, in town metres), colour, mine, rank}].
func tags() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if store == null or data.is_empty():
		return out
	var faces: Dictionary = data.faces
	var me := store.me()
	for q in town.get("quarters", []):
		var walls := store.walls_in(int(q.id))
		for id in walls:
			if not faces.has(id):
				continue
			var w: Dictionary = walls[id]
			var cols: Array = w.get("kit", {}).get("colours", [])
			var colour := CityTheme.PINK
			if not cols.is_empty() and Color.html_is_valid(str(cols[0])):
				colour = Color(str(cols[0]))
			out.append({"p": faces[id], "colour": colour, "mine": str(w.get("writer", "")) == me,
				"rank": str(w.get("rank", "tag"))})
	return out


## Draws the screen-sized things over the picture on `c`: the quarters'
## names, the paint and the writer.
func draw_overlay(c: Control) -> void:
	var size := _size()
	var font := CityTheme.heading()
	for q in town.get("quarters", []):
		var at := to_screen(Vector2(q.centre[0], q.centre[1]))
		var text := str(q.get("name", ""))
		if text == "" or at.x < -200.0 or at.y < -40.0 or at.x > size.x + 200.0 or at.y > size.y + 40.0:
			continue
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		var pos := at + Vector2(-w * 0.5, 7.0)
		c.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 8, Color(CityTheme.INK, 0.95))
		c.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, CityTheme.CREAM)
	for t in _tags:
		var at := to_screen(t.p)
		if at.x < -10.0 or at.y < -10.0 or at.x > size.x + 10.0 or at.y > size.y + 10.0:
			continue
		var r := 6.0 if t.mine else 4.0
		c.draw_circle(at, r + 2.0, CityTheme.INK)
		c.draw_circle(at, r, t.colour)
	# The writer: an arrow pointing the way they face.
	var here := to_screen(_me.p)
	var dir: Vector2 = _me.dir
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([here + dir * 17.0, here - dir * 11.0 + side * 11.0, here - dir * 5.0,
			here - dir * 11.0 - side * 11.0])
	var outline := PackedVector2Array([here + dir * 22.0, here - dir * 15.0 + side * 15.0, here - dir * 6.0,
			here - dir * 15.0 - side * 15.0])
	c.draw_colored_polygon(outline, CityTheme.INK)
	c.draw_colored_polygon(pts, CityTheme.YELLOW)


## The map's overlay: it draws through [method TownMap.draw_overlay].
class _Overlay:
	extends Control
	var map: TownMap

	func _draw() -> void:
		if map:
			map.draw_overlay(self)
