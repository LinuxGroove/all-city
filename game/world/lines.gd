class_name Lines
extends RefCounted
## Every line a skater can grind or climb, in world space: the wheel line
## along the top of a handrail, the edge of a kerb or ledge, the coping of a
## stair wall, a parapet, a fence's top rail, a wire; and the ways up a
## building (drainpipes, fire escapes) as CLIMB lines from the ground to the
## top of the parapet.
##
## Lines are polylines (a kerb round a block can have hundreds of points; a
## line whose last point is its first is a loop). Every segment is indexed
## in square cells of CELL metres on the ground, so `nearest()` only looks at
## the few cells round the skater and stays cheap on every physics tick.
## Lines belong to an owner (a town tile's key), so a tile's lines leave
## with the tile.

enum Kind { HANDRAIL, LEDGE, KERB, RAIL, PARAPET, FENCE, WALL, WIRE, COPING, CLIMB }

const CELL := 8.0
## Every kind but CLIMB, for `nearest()`.
const GRINDS := [Kind.HANDRAIL, Kind.LEDGE, Kind.KERB, Kind.RAIL, Kind.PARAPET, Kind.FENCE, Kind.WALL, Kind.WIRE,
	Kind.COPING]

## id -> {"kind", "pts", "owner", "closed", "cells"}
var _lines := {}
## Vector2i cell -> PackedInt32Array of [line id, segment, line id, segment, ...]
## Cell -> segment refs, keyed by the cell less `_base`, so moving the whole
## world by whole cells only moves `_base`.
var _cells := {}
var _base := Vector2i.ZERO
## owner -> Array of line ids
var _owned := {}
var _next_id := 1


## Adds a line and returns its id. `owner` is the tile key it goes with.
func add(kind: int, pts: PackedVector3Array, owner := "") -> int:
	if pts.size() < 2:
		return -1
	var id := _next_id
	_next_id += 1
	var closed := pts.size() > 2 and pts[0].distance_to(pts[pts.size() - 1]) < 0.01
	_lines[id] = {"kind": kind, "pts": pts.duplicate(), "owner": owner, "closed": closed, "cells": []}
	if not _owned.has(owner):
		_owned[owner] = []
	_owned[owner].append(id)
	_index(id)
	return id


## Removes every line a tile added.
func drop(owner: String) -> void:
	for id in _owned.get(owner, []):
		_unindex(id)
		_lines.erase(id)
	_owned.erase(owner)


## Removes one line.
func remove(id: int) -> void:
	if not _lines.has(id):
		return
	var owner: String = _lines[id].owner
	_unindex(id)
	_lines.erase(id)
	if _owned.has(owner):
		_owned[owner].erase(id)
		if _owned[owner].is_empty():
			_owned.erase(owner)


## A line's kind, points and owner ({} if there's no such line).
func line(id: int) -> Dictionary:
	if not _lines.has(id):
		return {}
	var l: Dictionary = _lines[id]
	return {"kind": l.kind, "pts": l.pts, "owner": l.owner, "closed": l.closed}


func has(id: int) -> bool:
	return _lines.has(id)


func count() -> int:
	return _lines.size()


func ids() -> Array:
	return _lines.keys()


## The line nearest `pos` within `radius`, of one of `kinds` (any kind when
## empty): {} or {id, kind, seg, t, point, tangent, distance}, where `point`
## lies `t` (0 to 1) of the way along segment `seg` and `tangent` runs
## towards the line's next point.
func nearest(pos: Vector3, radius: float, kinds := []) -> Dictionary:
	var mask := 0
	for k in kinds:
		mask |= 1 << int(k)
	var x0 := floori((pos.x - radius) / CELL)
	var x1 := floori((pos.x + radius) / CELL)
	var z0 := floori((pos.z - radius) / CELL)
	var z1 := floori((pos.z + radius) / CELL)
	var best_d := radius
	var best_id := -1
	var best_seg := 0
	var best_point := Vector3.ZERO
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var refs: PackedInt32Array = _cells.get(Vector2i(cx, cz) - _base, PackedInt32Array())
			for i in range(0, refs.size(), 2):
				var l: Dictionary = _lines[refs[i]]
				if mask != 0 and (mask & (1 << int(l.kind))) == 0:
					continue
				var pts: PackedVector3Array = l.pts
				var seg := refs[i + 1]
				var p := Geometry3D.get_closest_point_to_segment(pos, pts[seg], pts[seg + 1])
				var d := p.distance_to(pos)
				if d <= best_d:
					best_d = d
					best_id = refs[i]
					best_seg = seg
					best_point = p
	if best_id < 0:
		return {}
	var l: Dictionary = _lines[best_id]
	var a: Vector3 = l.pts[best_seg]
	var b: Vector3 = l.pts[best_seg + 1]
	var length := a.distance_to(b)
	return {
		"id": best_id, "kind": l.kind, "seg": best_seg, "t": a.distance_to(best_point) / length if length > 0.0 else 0.0,
		"point": best_point, "tangent": (b - a) / length if length > 0.0 else Vector3.ZERO, "distance": best_d,
	}


## The point `t` of the way along segment `seg`.
func point_at(id: int, seg: int, t: float) -> Vector3:
	var pts: PackedVector3Array = _lines[id].pts
	return pts[seg].lerp(pts[seg + 1], t)


## Segment `seg`'s direction, towards the line's next point.
func tangent_at(id: int, seg: int) -> Vector3:
	var pts: PackedVector3Array = _lines[id].pts
	return (pts[seg + 1] - pts[seg]).normalized()


## A line's whole length.
func length(id: int) -> float:
	var pts: PackedVector3Array = _lines[id].pts
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	return total


## Metres from `seg`, `t` to the line's end going one way (`dir` +1 towards
## the last point, -1 towards the first). Loops never end (INF).
func room(id: int, seg: int, t: float, dir: int) -> float:
	var l: Dictionary = _lines[id]
	if l.closed:
		return INF
	var pts: PackedVector3Array = l.pts
	var seg_len := pts[seg].distance_to(pts[seg + 1])
	var total := 0.0
	if dir > 0:
		total = (1.0 - t) * seg_len
		for i in range(seg + 1, pts.size() - 1):
			total += pts[i].distance_to(pts[i + 1])
	else:
		total = t * seg_len
		for i in seg:
			total += pts[i].distance_to(pts[i + 1])
	return total


## Moves `dist` metres along a line from segment `seg`, `t` (negative goes
## towards the first point), crossing joints and going round loops. Returns
## {seg, t, point, tangent (towards the next point), ended, over (metres
## past the end), turn (the sharpest joint crossed, in radians)}.
func advance(id: int, seg: int, t: float, dist: float) -> Dictionary:
	var l: Dictionary = _lines[id]
	var pts: PackedVector3Array = l.pts
	var last := pts.size() - 2
	var ended := false
	var over := 0.0
	var turn := 0.0
	var left := absf(dist)
	var forward := dist >= 0.0
	# Each pass either finishes inside a segment or moves to the next one.
	for guard in pts.size() * 2 + 4:
		var a := pts[seg]
		var b := pts[seg + 1]
		var seg_len := a.distance_to(b)
		var ahead := (1.0 - t) * seg_len if forward else t * seg_len
		if left <= ahead:
			if seg_len > 0.0:
				t += (left / seg_len) * (1.0 if forward else -1.0)
			left = 0.0
			break
		left -= ahead
		var next := seg + (1 if forward else -1)
		if next < 0 or next > last:
			if l.closed:
				next = 0 if forward else last
			else:
				t = 1.0 if forward else 0.0
				ended = true
				over = left
				break
		var before := (b - a).normalized()
		var after := (pts[next + 1] - pts[next]).normalized()
		if before.length() > 0.0 and after.length() > 0.0:
			turn = maxf(turn, before.angle_to(after))
		seg = next
		t = 0.0 if forward else 1.0
	t = clampf(t, 0.0, 1.0)
	return {
		"seg": seg, "t": t, "point": pts[seg].lerp(pts[seg + 1], t), "tangent": (pts[seg + 1] - pts[seg]).normalized(),
		"ended": ended, "over": over, "turn": turn,
	}


## Moves every line by `offset` (when the town re-centres the origin) and
## indexes them again.
func shift(offset: Vector3) -> void:
	var moved := Transform3D(Basis.IDENTITY, offset)
	for id in _lines:
		var l: Dictionary = _lines[id]
		l.pts = moved * (l.pts as PackedVector3Array)
	var by := Vector2(offset.x, offset.z) / CELL
	if by.is_equal_approx(by.round()):
		_base += Vector2i(by.round())
		return
	# Not whole cells: index it all again.
	_cells.clear()
	_base = Vector2i.ZERO
	for id in _lines:
		_index(id)


func clear() -> void:
	_base = Vector2i.ZERO
	_lines.clear()
	_cells.clear()
	_owned.clear()


func _index(id: int) -> void:
	var l: Dictionary = _lines[id]
	var pts: PackedVector3Array = l.pts
	var touched := {}
	for seg in pts.size() - 1:
		for cell in _cells_of(pts[seg], pts[seg + 1]):
			var key := cell - _base
			var refs: PackedInt32Array = _cells.get(key, PackedInt32Array())
			refs.append(id)
			refs.append(seg)
			_cells[key] = refs
			touched[key] = true
	l.cells = touched.keys()


func _unindex(id: int) -> void:
	for cell in _lines[id].cells:
		var refs: PackedInt32Array = _cells.get(cell, PackedInt32Array())
		var kept := PackedInt32Array()
		for i in range(0, refs.size(), 2):
			if refs[i] != id:
				kept.append(refs[i])
				kept.append(refs[i + 1])
		if kept.is_empty():
			_cells.erase(cell)
		else:
			_cells[cell] = kept


## The cells a segment passes through on the ground: every cell of its
## bounding box that the segment crosses (clipped to the cell, so a long
## diagonal kerb doesn't fill a square).
static func _cells_of(a: Vector3, b: Vector3) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x0 := floori(minf(a.x, b.x) / CELL)
	var x1 := floori(maxf(a.x, b.x) / CELL)
	var z0 := floori(minf(a.z, b.z) / CELL)
	var z1 := floori(maxf(a.z, b.z) / CELL)
	var flat_a := Vector2(a.x, a.z)
	var flat_b := Vector2(b.x, b.z)
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			if (x1 == x0 and z1 == z0) or _crosses(flat_a, flat_b, Rect2(cx * CELL, cz * CELL, CELL, CELL).grow(0.01)):
				out.append(Vector2i(cx, cz))
	return out


## Whether a segment on the ground passes through a rectangle (Liang-Barsky).
static func _crosses(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	var p := [-d.x, d.x, -d.y, d.y]
	var q := [a.x - r.position.x, r.end.x - a.x, a.y - r.position.y, r.end.y - a.y]
	for i in 4:
		if is_zero_approx(p[i]):
			if q[i] < 0.0:
				return false
			continue
		var u: float = q[i] / p[i]
		if p[i] < 0.0:
			t0 = maxf(t0, u)
		else:
			t1 = minf(t1, u)
		if t0 > t1:
			return false
	return true
