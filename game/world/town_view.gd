class_name TownView
extends Node3D
## Streams a town the Cartographer built: the tiles round the player in
## full detail (facades, steps, props, collision, grind lines, paintable
## walls and traffic), a wider ring as far scenery (ground, water, shells
## and roofs), loaded one tile at a time on a worker thread and dropped as
## the player moves on.
##
## Town coordinates are the Cartographer's: metres east (x) and south (z)
## of the town's middle. The scene works near its own origin instead, and
## when the player gets far from it the whole world is moved back
## (`recentre`), so a big town keeps its precision. `origin` is where the
## scene's origin is in the town; `shifted` tells the scene what moved.

signal shifted(offset: Vector3)
signal tile_shown(key: Vector2i, near: bool)

## Tiles this many tiles from the player's (in a square) get full detail;
## up to FAR show as scenery. Detail goes one tile later than it comes, so
## riding along a tile's edge doesn't build and drop it over and over.
const NEAR := 1
const FAR := 3
## How far the player may get from the scene's origin before the world is
## moved back round them.
const RECENTRE := 384.0
const SETS := ["facade", "street", "stairs", "vehicles", "landmark"]

var town := {}
var folder := ""
var origin := Vector3.ZERO
var lines := Lines.new()
var walls := Walls.new()
var traffic: Traffic
## Vector2i -> TileView
var tiles := {}
var detail := 1
## How long a frame may spend making tiles into nodes, in microseconds.
var make_budget := 4000

var _ctx := {}
var _have := {}
var _focus := Vector2i(1 << 20, 0)
var _queue: Array = []
var _task := -1
var _task_job := {}
var _task_result: TilePlan = null
## Tiles being made into nodes a piece at a time, before they replace any
## older view of the same tile.
var _making: Array[TileView] = []
var _timings: Array[float] = []


func _init() -> void:
	name = "Town"
	traffic = Traffic.new()
	add_child(traffic)


## Opens a town (a manifest as `Towns.list()` gives it). Nothing loads
## until `load_around()` or `follow()`.
func open(manifest: Dictionary, detail_level := -1) -> void:
	town = manifest
	folder = str(manifest.get("path", ""))
	detail = detail_level if detail_level >= 0 else int(LGSettings.get_value("video", "detail", 1))
	traffic.drive = str(manifest.get("drive", "right"))
	_ctx = context(detail)
	_have.clear()
	for t in manifest.get("tiles", []):
		_have[Vector2i(int(t[0]), int(t[1]))] = true


## The shared things every tile's build reads, made here on the main
## thread: the kit's meshes (loaded into Kit's cache), the materials and
## the props' sizes.
static func context(detail_level := 1) -> Dictionary:
	var boxes := {}
	for set_name in SETS:
		for m in Kit.models(set_name):
			var mesh := Kit.mesh(m)
			if mesh:
				boxes[m] = mesh.get_aabb()
	var ground := ShaderMaterial.new()
	ground.shader = preload("res://game/look/shaders/ground.gdshader")
	ground.set_shader_parameter("base", Palette.color("paving"))
	ground.set_shader_parameter("walk", Palette.color("concrete_light"))
	ground.set_shader_parameter("road", Palette.color("asphalt"))
	ground.set_shader_parameter("green", Palette.color("grass"))
	ground.set_shader_parameter("ballast", Palette.color("concrete_dark"))
	var water := ShaderMaterial.new()
	water.shader = preload("res://game/look/shaders/water.gdshader")
	water.set_shader_parameter("deep", Palette.color("sea"))
	var shell := ShaderMaterial.new()
	shell.shader = preload("res://game/look/shaders/shell.gdshader")
	shell.set_shader_parameter("glass", Palette.color("glass"))
	shell.set_shader_parameter("warm", Palette.color("window_warm"))
	var scale: float = [0.6, 1.0, 1.4][clampi(detail_level, 0, 2)]
	return {
		"mats": {"ground": ground, "water": water, "shell": shell, "roof": Look.flat(Color.WHITE),
				"palette": Look.material("Palette")},
		"prop_boxes": boxes,
		"facade_range": 230.0 * scale,
		"props_range": 160.0 * scale,
		"far": FAR if detail_level > 0 else FAR - 1,
	}


## The tile key under a point of the scene.
func key_at(local: Vector3) -> Vector2i:
	var p := local + origin
	return Vector2i(floori(p.x / TilePlan.SIZE), floori(p.z / TilePlan.SIZE))


func to_town(local: Vector3) -> Vector3:
	return local + origin


func from_town(town_pos: Vector3) -> Vector3:
	return town_pos - origin


## The quarter a place is in (its id in the manifest), or -1 where no
## tile is shown.
func quarter_at(local: Vector3) -> int:
	var key := key_at(local)
	var tv: TileView = tiles.get(key)
	if tv == null or tv.quarters.size() < TilePlan.QUARTER_CELLS * TilePlan.QUARTER_CELLS:
		return -1
	var p := local + origin - tv.corner
	var col := clampi(floori(p.x / TilePlan.QUARTER_CELL), 0, TilePlan.QUARTER_CELLS - 1)
	var row := clampi(floori(p.z / TilePlan.QUARTER_CELL), 0, TilePlan.QUARTER_CELLS - 1)
	return tv.quarters[row * TilePlan.QUARTER_CELLS + col]


## A quarter's name from the manifest, or "".
func quarter_name(id: int) -> String:
	for q in town.get("quarters", []):
		if int(q.id) == id:
			return str(q.get("name", ""))
	return ""


## The quarters a shown tile's walls are in.
func quarters_of(key: Vector2i) -> PackedInt32Array:
	var out := PackedInt32Array()
	var tv: TileView = tiles.get(key)
	if tv:
		for q in tv.quarters:
			if not out.has(q):
				out.append(q)
	return out


## Where the town says a writer starts, in the scene: {"p", "yaw"}.
func spawn() -> Dictionary:
	var s: Dictionary = town.get("spawn", {"p": [0, 0, 0], "yaw": 0.0})
	var p: Array = s.p
	return {"p": from_town(Vector3(p[0], p[1], p[2])), "yaw": float(s.get("yaw", 0.0))}


## Builds the near tiles round a point at once (behind a loading screen,
## and for tests); the far ring then streams in.
func load_around(local: Vector3) -> void:
	_focus = key_at(local)
	for key in _wanted(_focus):
		if _chebyshev(key, _focus) <= NEAR and _has_tile(key):
			var plan := _make_plan(key, true)
			if plan:
				var tv := TileView.from_plan(plan, _ctx)
				tv.step(1 << 30)
				_attach(tv)
	_plan()


## Call every physics tick with the player's place in the scene. Streams
## tiles in and out, and moves the world back when the player is far from
## the origin; returns how far everything moved (Vector3.ZERO mostly), as
## `shifted` also says.
func follow(local: Vector3) -> Vector3:
	_poll()
	_make_some()
	var key := key_at(local)
	if key != _focus:
		_focus = key
		_plan()
	if absf(local.x) > RECENTRE or absf(local.z) > RECENTRE:
		var by := Vector3(snappedf(local.x, TilePlan.SIZE), 0.0, snappedf(local.z, TilePlan.SIZE))
		recentre(by)
		return -by
	return Vector3.ZERO


## Moves the scene's origin `by` metres through the town: everything the
## town holds moves back by as much, and `shifted` says so.
func recentre(by: Vector3) -> void:
	by.y = 0.0
	origin += by
	for tv in tiles.values() + _making:
		tv.position = tv.corner - origin
		tv.reset_physics_interpolation()
	lines.shift(-by)
	walls.shift(-by)
	traffic.shift(-by)
	shifted.emit(-by)


## Tiles shown, as {key: near}.
func shown() -> Dictionary:
	var out := {}
	for key in tiles:
		out[key] = (tiles[key] as TileView).near
	return out


## Whether every tile wanted round the player is in (near and far).
func settled() -> bool:
	return _queue.is_empty() and _task < 0 and _making.is_empty()


## How long tiles took to build, in milliseconds, as built so far.
func timings() -> Array[float]:
	return _timings


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_task_result = null
	for tv in _making:
		tv.free()
	_making.clear()


func _wanted(around: Vector2i) -> Array:
	var far := int(_ctx.get("far", FAR))
	var out := []
	for dj in range(-far, far + 1):
		for di in range(-far, far + 1):
			out.append(around + Vector2i(di, dj))
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _chebyshev(a, around) < _chebyshev(b, around))
	return out


## Works out what to load, upgrade, drop and free for the current focus.
func _plan() -> void:
	var far := int(_ctx.get("far", FAR))
	_queue.clear()
	for key in _wanted(_focus):
		if not _has_tile(key):
			continue
		var d := _chebyshev(key, _focus)
		var want_near := d <= NEAR
		if not tiles.has(key):
			_queue.append({"key": key, "near": want_near})
		elif want_near and not (tiles[key] as TileView).near:
			_queue.append({"key": key, "near": true})
	for key in tiles.keys():
		var tv: TileView = tiles[key]
		var d := _chebyshev(key, _focus)
		if d > far + 1:
			_drop_registries(key)
			tv.queue_free()
			tiles.erase(key)
		elif tv.near and d > NEAR + 1:
			_drop_registries(key)
			tv.drop_detail()
			tile_shown.emit(key, false)
	for tv in _making.duplicate():
		var d := _chebyshev(tv.key, _focus)
		if d > far + 1 or (tv.near and d > NEAR + 1):
			_making.erase(tv)
			tv.queue_free()
	_start_next()


func _start_next() -> void:
	if _task >= 0 or _queue.is_empty():
		return
	_task_job = _queue.pop_front()
	_task_result = null
	_task = WorkerThreadPool.add_task(_run_job.bind(_task_job.key, _task_job.near), false, "town tile")


func _run_job(key: Vector2i, with_detail: bool) -> void:
	_task_result = _make_plan(key, with_detail)


func _poll() -> void:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var plan := _task_result
	_task_result = null
	if plan and _chebyshev(plan.key, _focus) <= int(_ctx.get("far", FAR)) + 1:
		var stale := tiles.has(plan.key) and (tiles[plan.key] as TileView).near and not plan.near
		if not stale:
			var tv := TileView.from_plan(plan, _ctx)
			tv.position = tv.corner - origin
			tv.visible = false
			add_child(tv)
			_making.append(tv)
	_start_next()


## Makes the tiles waiting to be nodes, a few milliseconds a frame.
func _make_some() -> void:
	var t0 := Time.get_ticks_usec()
	while not _making.is_empty() and Time.get_ticks_usec() - t0 < make_budget:
		var tv := _making[0]
		if tv.step(make_budget - (Time.get_ticks_usec() - t0)):
			_making.pop_front()
			tv.visible = true
			_attach(tv)


func _make_plan(key: Vector2i, with_detail: bool) -> TilePlan:
	var tile := TownTiles.load_tile(folder, key.x, key.y)
	if tile.is_empty():
		return null
	return TilePlan.make(tile, with_detail, _ctx)


## Puts a whole tile in the scene (in place of an older view of it) and
## adds what it brings to the registries.
func _attach(tv: TileView) -> void:
	if tiles.has(tv.key):
		_drop_registries(tv.key)
		(tiles[tv.key] as TileView).queue_free()
	tiles[tv.key] = tv
	tv.position = tv.corner - origin
	if tv.get_parent() != self:
		add_child(tv)
	tv.reset_physics_interpolation()
	var plan := tv.plan
	_timings.append(plan.build_ms)
	if tv.near:
		var owner_key := _owner(tv.key)
		for item in plan.grind_lines:
			lines.add(int(item[0]), _shift_pts(item[1], -origin), owner_key)
		for f in plan.faces:
			var face: Dictionary = f.duplicate()
			face.a = f.a - origin
			face.b = f.b - origin
			walls.add(face, owner_key)
		var list := []
		for lane in plan.lanes:
			list.append({"pts": _shift_pts(lane.pts, -origin), "kind": lane.kind})
		traffic.add_lanes(owner_key, list)
	# The arrays are in the nodes now.
	tv.plan = null
	tile_shown.emit(tv.key, tv.near)


func _drop_registries(key: Vector2i) -> void:
	var owner_key := _owner(key)
	lines.drop(owner_key)
	walls.drop(owner_key)
	traffic.drop_lanes(owner_key)


func _has_tile(key: Vector2i) -> bool:
	return _have.has(key)


static func _owner(key: Vector2i) -> String:
	return "%d_%d" % [key.x, key.y]


static func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func _shift_pts(pts: PackedVector3Array, by: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(pts.size())
	for k in pts.size():
		out[k] = pts[k] + by
	return out
