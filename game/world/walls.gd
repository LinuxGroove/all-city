class_name Walls
extends RefCounted
## Every paintable wall face of the loaded town, indexed in CELL metre cells
## so finding the wall a writer stands at is quick. The town streamer fills
## it from the tiles it loads (`add` with the tile as the owner) and empties
## it as they go (`drop`); walls are known only by the Cartographer's ids.
##
## A face is a Dictionary:
##   id       the Cartographer's wall id ("w" and hex digits)
##   a, b     its ends on the ground at its base, with its outside on the
##            right of a→b seen from above (as Facade.lay takes them)
##   base     the height of its foot
##   top      the highest paintable height (the first storey only for
##            shopfronts under homes, the parapet's top otherwise)
##   paint    0 never (the respect list), 1 ground floor only, 2 all
##   eyes     0 to 100, how much street sees it
##   quarter  the quarter it's in (0 to 9999)
##   heaven   a heaven spot, out of the Buff's reach

const CELL := 8.0
## Paint levels.
const NEVER := 0
const GROUND := 1
const ALL := 2
## How high the ground floor goes, for faces that only take paint there.
const GROUND_FLOOR := 3.0

## id -> face
var _faces := {}
## id -> owner
var _owner_of := {}
## owner -> {id: true}
var _owned := {}
## Vector2i cell -> {id: true}
## Cell -> {wall id: true}, keyed by the cell less `_base`, so moving the
## whole world by whole cells only moves `_base`.
var _cells := {}
var _base := Vector2i.ZERO


## Adds a face (a copy of it), replacing any face with the same id.
func add(face: Dictionary, owner := "") -> void:
	var id := str(face.id)
	if _faces.has(id):
		_remove(id)
	var f := face.duplicate()
	f.a = Vector3(face.a)
	f.b = Vector3(face.b)
	f.base = float(face.get("base", f.a.y))
	f.top = float(face.get("top", f.base + GROUND_FLOOR))
	f.paint = int(face.get("paint", ALL))
	f.eyes = clampi(int(face.get("eyes", 0)), 0, 100)
	f.quarter = int(face.get("quarter", 0))
	f.heaven = bool(face.get("heaven", false))
	_faces[id] = f
	_owner_of[id] = owner
	if not _owned.has(owner):
		_owned[owner] = {}
	_owned[owner][id] = true
	_index(id)


## Drops every face `owner` added (a tile streamed out).
func drop(owner: String) -> void:
	if not _owned.has(owner):
		return
	for id in _owned[owner].keys():
		_remove(id)
	_owned.erase(owner)


## The face with this id, or {} when it isn't loaded.
func face(id: String) -> Dictionary:
	return _faces.get(id, {})


func size() -> int:
	return _faces.size()


## The face nearest `pos` within `radius` metres that `pos` is outside of,
## as {face, u (metres along a→b), v (height above its base), distance,
## normal (outward)}, or {} when there's none. With `facing` (the way the
## writer looks, flat), faces turned away are skipped and, of two at much
## the same distance (a corner), the one faced more squarely wins.
func nearest(pos: Vector3, radius: float, facing := Vector3.ZERO) -> Dictionary:
	var look := Vector3(facing.x, 0, facing.z)
	if look.length_squared() > 0.0001:
		look = look.normalized()
	var best := {}
	var best_score := INF
	for id in _near_ids(pos, radius):
		var f: Dictionary = _faces[id]
		var along := Vector3(f.b.x - f.a.x, 0, f.b.z - f.a.z)
		var length := along.length()
		if length < 0.01:
			continue
		var d := along / length
		var normal := Vector3(-d.z, 0, d.x)
		var rel := Vector3(pos.x - f.a.x, 0, pos.z - f.a.z)
		var out := rel.dot(normal)
		var u := rel.dot(d)
		if out < -0.05 or u < 0.0 or u > length or out > radius:
			continue
		var score := out
		if look != Vector3.ZERO:
			var square := -look.dot(normal)
			if square < 0.25:
				continue
			score += (1.0 - square) * 1.5
		if score < best_score:
			best_score = score
			best = {"face": f, "u": u, "v": pos.y - float(f.base), "distance": maxf(out, 0.0), "normal": normal}
	return best


## How high paint can go on a face, above its base: nothing on the respect
## list, the ground floor where only that takes paint, else up to its top.
static func paint_height(face: Dictionary) -> float:
	match int(face.get("paint", ALL)):
		NEVER:
			return 0.0
		GROUND:
			return minf(float(face.top) - float(face.base), GROUND_FLOOR)
	return float(face.top) - float(face.base)


## Moves every face by `offset`, when the world's origin is re-centred.
func shift(offset: Vector3) -> void:
	for id in _faces:
		var f: Dictionary = _faces[id]
		f.a += offset
		f.b += offset
		f.base += offset.y
		f.top += offset.y
	var by := Vector2(offset.x, offset.z) / CELL
	if by.is_equal_approx(by.round()):
		_base += Vector2i(by.round())
		return
	# Not whole cells: index it all again.
	_cells.clear()
	_base = Vector2i.ZERO
	for id in _faces:
		_index(id)


func _remove(id: String) -> void:
	var f: Dictionary = _faces[id]
	for c in _cells_of(f):
		var key := c - _base
		if _cells.has(key):
			_cells[key].erase(id)
			if _cells[key].is_empty():
				_cells.erase(key)
	var owner: String = _owner_of[id]
	if _owned.has(owner):
		_owned[owner].erase(id)
	_owner_of.erase(id)
	_faces.erase(id)


func _index(id: String) -> void:
	for c in _cells_of(_faces[id]):
		var key := c - _base
		if not _cells.has(key):
			_cells[key] = {}
		_cells[key][id] = true


## The cells a face passes through: those in its bounding box whose
## centres are within half a cell's diagonal of the face.
func _cells_of(f: Dictionary) -> Array[Vector2i]:
	var a := Vector2(f.a.x, f.a.z)
	var b := Vector2(f.b.x, f.b.z)
	var lo := Vector2i(floori(minf(a.x, b.x) / CELL), floori(minf(a.y, b.y) / CELL))
	var hi := Vector2i(floori(maxf(a.x, b.x) / CELL), floori(maxf(a.y, b.y) / CELL))
	var reach := CELL * 0.7072
	var out: Array[Vector2i] = []
	for i in range(lo.x, hi.x + 1):
		for j in range(lo.y, hi.y + 1):
			var centre := Vector2((i + 0.5) * CELL, (j + 0.5) * CELL)
			if Geometry2D.get_closest_point_to_segment(centre, a, b).distance_to(centre) <= reach:
				out.append(Vector2i(i, j))
	return out


func _near_ids(pos: Vector3, radius: float) -> Array:
	var lo := Vector2i(floori((pos.x - radius) / CELL), floori((pos.z - radius) / CELL))
	var hi := Vector2i(floori((pos.x + radius) / CELL), floori((pos.z + radius) / CELL))
	var found := {}
	for i in range(lo.x, hi.x + 1):
		for j in range(lo.y, hi.y + 1):
			var key := Vector2i(i, j) - _base
			if _cells.has(key):
				found.merge(_cells[key])
	return found.keys()
