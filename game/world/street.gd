class_name Street
extends RefCounted
## The bits of a street the game builds from the map's lines rather than
## from the kit: kerbs, garden walls, fences, bridge decks and their piers,
## and railway sleepers, as boxes swept along a line in palette swatches,
## plus the same boxes as collision triangles.
##
## A line's points are the top of the thing (the Cartographer lifts them
## so); boxes reach `lo` to `hi` metres from each point, `hw` either side.


## A box along a→b on a SurfaceTool that is already begun (with flat
## normals), its sides in one swatch and its top in another. `extend`
## pushes each end out a little so a bending line shows no gaps.
static func bar(st: SurfaceTool, a: Vector3, b: Vector3, hw: float, lo: float, hi: float, side_swatch: String,
		top_swatch: String, extend := 0.0) -> void:
	var c := _corners(a, b, hw, lo, hi, extend)
	if c.is_empty():
		return
	var d: Vector3 = c[8]
	var s: Vector3 = c[9]
	# c: 0 a-left-lo, 1 a-right-lo, 2 b-right-lo, 3 b-left-lo, then the same high.
	face(st, [c[4], c[5], c[6], c[7]], Vector3.UP, top_swatch)
	face(st, [c[1], c[2], c[6], c[5]], s, side_swatch)
	face(st, [c[3], c[0], c[4], c[7]], -s, side_swatch)
	face(st, [c[0], c[1], c[5], c[4]], -d, side_swatch)
	face(st, [c[2], c[3], c[7], c[6]], d, side_swatch)


## The same box as collision triangles.
static func solid_bar(tris: PackedVector3Array, a: Vector3, b: Vector3, hw: float, lo: float, hi: float) -> void:
	var c := _corners(a, b, hw, lo, hi, 0.0)
	if c.is_empty():
		return
	for q in [[4, 5, 6, 7], [1, 2, 6, 5], [3, 0, 4, 7], [0, 1, 5, 4], [2, 3, 7, 6]]:
		tris.append_array(PackedVector3Array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]]))


## A railing along a line of its top: posts, a top rail, a middle rail and
## bars between, in one swatch.
static func fence(st: SurfaceTool, pts: PackedVector3Array, h: float, swatch := "steel_dark") -> void:
	var since := 99.0
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var length := Vector2(b.x - a.x, b.z - a.z).length()
		if length < 0.01:
			continue
		bar(st, a, b, 0.03, -0.06, 0.0, swatch, swatch, 0.03)
		bar(st, a + Vector3.UP * (-h * 0.55), b + Vector3.UP * (-h * 0.55), 0.025, -0.05, 0.0, swatch, swatch, 0.03)
		var n := int(length / 0.16)
		for i in n:
			var t := (i + 0.5) / n
			var p := a.lerp(b, t)
			_post(st, p, h - 0.06, 0.012, swatch)
		since += length
		if since > 2.4:
			since = 0.0
			_post(st, a, h + 0.05, 0.04, swatch)
	if pts.size() >= 2:
		_post(st, pts[pts.size() - 1], h + 0.05, 0.04, swatch)


## Railway sleepers under a track's middle line.
static func sleepers(st: SurfaceTool, pts: PackedVector3Array) -> void:
	var left := 0.0
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var length := a.distance_to(b)
		if length < 0.01:
			continue
		var d := (b - a) / length
		var side := Vector3(-d.z, 0, d.x).normalized()
		var t := left
		while t < length:
			var p := a + d * t
			bar(st, p - side * 1.25, p + side * 1.25, 0.11, -0.02, 0.14, "wood_dark", "wood_dark")
			t += 0.65
		left = t - length


## A bridge pier from the ground up to under a deck at `top`.
static func pier(st: SurfaceTool, top: Vector3, ground: float, half: float) -> void:
	var a := Vector3(top.x, top.y - 0.9, top.z - half)
	var b := Vector3(top.x, top.y - 0.9, top.z + half)
	bar(st, a, b, half, ground - top.y + 0.9 - 0.5, 0.0, "concrete", "concrete")


## A quad in a swatch, wound so it faces `normal` (Godot draws clockwise
## faces as fronts).
static func face(st: SurfaceTool, p: Array, normal: Vector3, swatch: String) -> void:
	st.set_uv(Palette.uv(swatch))
	st.set_normal(normal)
	var order := [0, 1, 2, 0, 2, 3]
	if ((p[1] - p[0]) as Vector3).cross(p[2] - p[0]).dot(normal) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for k in order:
		st.add_vertex(p[k])


static func _post(st: SurfaceTool, top: Vector3, h: float, hw: float, swatch: String) -> void:
	var lo := top - Vector3.UP * h
	for q in [[Vector3(-hw, 0, -hw), Vector3(hw, 0, -hw), Vector3.FORWARD], [Vector3(hw, 0, -hw), Vector3(hw, 0, hw),
			Vector3.RIGHT], [Vector3(hw, 0, hw), Vector3(-hw, 0, hw), Vector3.BACK],
			[Vector3(-hw, 0, hw), Vector3(-hw, 0, -hw), Vector3.LEFT]]:
		face(st, [lo + q[0], lo + q[1], top + q[1], top + q[0]], q[2], swatch)


## The eight corners of a box along a→b, then its direction and side.
static func _corners(a: Vector3, b: Vector3, hw: float, lo: float, hi: float, extend: float) -> Array:
	var flat := Vector3(b.x - a.x, 0, b.z - a.z)
	var length := flat.length()
	if length < 0.005:
		return []
	var d := flat / length
	var s := Vector3(-d.z, 0, d.x)
	var e := (b - a) / length * extend
	var a2 := a - e
	var b2 := b + e
	return [a2 - s * hw + Vector3.UP * lo, a2 + s * hw + Vector3.UP * lo, b2 + s * hw + Vector3.UP * lo,
			b2 - s * hw + Vector3.UP * lo, a2 - s * hw + Vector3.UP * hi, a2 + s * hw + Vector3.UP * hi,
			b2 + s * hw + Vector3.UP * hi, b2 - s * hw + Vector3.UP * hi, d, s]
