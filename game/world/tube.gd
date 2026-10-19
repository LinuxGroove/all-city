class_name Tube
extends RefCounted
## Round tubes swept along a line, in one palette swatch: handrails, the
## rails along fences and parapets, power lines and railway rails.


## A tube through `points` with mitred joints and flat caps.
static func mesh(points: PackedVector3Array, radius: float, swatch := "steel", sides := 8,
		role := "Palette") -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_uv(Palette.uv(swatch))
	add_to(st, points, radius, sides)
	st.generate_normals()
	st.set_material(Look.material(role))
	return st.commit()


## Adds a tube's triangles to a SurfaceTool that is already begun.
static func add_to(st: SurfaceTool, points: PackedVector3Array, radius: float, sides := 8) -> void:
	var n := points.size()
	if n < 2:
		return
	var rings: Array[PackedVector3Array] = []
	for i in n:
		var p := points[i]
		var d: Vector3
		if i == 0:
			d = (points[1] - p).normalized()
		elif i == n - 1:
			d = (p - points[i - 1]).normalized()
		else:
			d = ((p - points[i - 1]).normalized() + (points[i + 1] - p).normalized()).normalized()
		var up := Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT
		var a := d.cross(up).normalized()
		var b := d.cross(a).normalized()
		var scale := 1.0
		if i > 0 and i < n - 1:
			scale = 1.0 / maxf((p - points[i - 1]).normalized().dot(d), 0.3)
		var ring := PackedVector3Array()
		for k in sides:
			var t := TAU * k / sides
			ring.append(p + (a * cos(t) + b * sin(t)) * radius * scale)
		rings.append(ring)
	for i in n - 1:
		for k in sides:
			var k2 := (k + 1) % sides
			_quad(st, rings[i][k], rings[i + 1][k], rings[i + 1][k2], rings[i][k2])
	for k in range(1, sides - 1):
		st.add_vertex(rings[0][0])
		st.add_vertex(rings[0][k])
		st.add_vertex(rings[0][k + 1])
		st.add_vertex(rings[n - 1][0])
		st.add_vertex(rings[n - 1][k + 1])
		st.add_vertex(rings[n - 1][k])


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)
