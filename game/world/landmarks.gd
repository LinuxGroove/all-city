class_name Landmarks
extends RefCounted
## A tile's landmarks (the Cartographer's `landmarks`, docs/tiles.md) worked
## out into a `TilePlan`: kit models scaled to their measured size, a
## ballpark's diamond, outfield wall, foul poles, lights and scoreboard, and
## grandstands as rows of seats. Everything here is arithmetic, so it runs on
## the plan's worker thread; the drawing is in the plan's `landmark_mesh` and
## `landmark_models`, shown at any distance, and the collision and grind lines
## only with the detail.

const BASE_PATH := 27.43        # home to first base
const MOUND := 18.44            # home to the pitcher's mound
const INFIELD := 29.0           # the infield dirt's reach from the mound
const WALL_STEP := deg_to_rad(3.0)
const LIGHT_ANGLES := [-60.0, -32.0, 32.0, 60.0]


## Adds `lm` to `plan`: drawing to `st` (palette swatches) and `batch`,
## collision and grind lines too when `detail`.
static func add(plan: TilePlan, lm: Dictionary, st: SurfaceTool, batch: Batch, detail: bool) -> void:
	match str(lm.kind):
		"ballpark":
			_ballpark(plan, lm, st, batch, detail)
		"stand":
			_stand(plan, lm, st, detail)
		_:
			_model(plan, lm, batch, detail)


## A kit model (water tower, smokestack, statue, spire) at its size.
static func _model(plan: TilePlan, lm: Dictionary, batch: Batch, detail: bool) -> void:
	var s := float(lm.get("s", 1.0))
	var at: Vector3 = lm.p - plan.corner
	var xf := Transform3D(Basis(Vector3.UP, float(lm.yaw)).scaled(Vector3.ONE * s), at)
	batch.add(str(lm.m), xf, Palette.color("cream") if str(lm.kind) == "water_tower" else Color.WHITE)
	if not detail:
		return
	match str(lm.kind):
		"water_tower":
			# Four legs to weave between; the tank is out of reach.
			for c in [Vector2(-5.2, -5.2), Vector2(5.2, -5.2), Vector2(5.2, 5.2), Vector2(-5.2, 5.2)]:
				var leg := xf * Vector3(c.x, 0.0, c.y)
				plan.shapes.append(["post", Vector3(0.45 * s, 24.0 * s, 0.0),
						Transform3D(Basis.IDENTITY, leg + Vector3.UP * 12.0 * s)])
		"smokestack":
			plan.shapes.append(["post", Vector3(1.5 * s, 33.0 * s, 0.0),
					Transform3D(Basis.IDENTITY, at + Vector3.UP * 16.5 * s)])
		"statue":
			# The plinth, and its top edge to grind.
			plan.shapes.append(["box", Vector3(2.2, 3.2, 5.4) * s, Transform3D(xf.basis.orthonormalized(),
					xf * Vector3(0.0, 1.6, 0.4))])
			var lip := PackedVector3Array()
			for c in [Vector2(-1.1, -2.3), Vector2(1.1, -2.3), Vector2(1.1, 3.1), Vector2(-1.1, 3.1), Vector2(-1.1, -2.3)]:
				lip.append(xf * Vector3(c.x, 1.0, c.y) + plan.corner)
			plan.grind_lines.append([Lines.Kind.LEDGE, lip])


## A grandstand: the Cartographer's rows, each lip a ledge to grind.
static func _stand(plan: TilePlan, lm: Dictionary, st: SurfaceTool, detail: bool) -> void:
	var verts: PackedVector3Array = lm.verts
	var tris: PackedInt32Array = lm.tris
	var walls: PackedVector3Array = lm.walls
	st.set_uv(Palette.uv("concrete_light"))
	st.set_normal(Vector3.UP)
	for k in range(0, tris.size(), 3):
		for v in [tris[k], tris[k + 2], tris[k + 1]]:
			st.add_vertex(verts[v] - plan.corner)
	for k in range(0, walls.size(), 6):
		var a := walls[k] - plan.corner
		var b := walls[k + 1] - plan.corner
		var normal := Vector3(b.z - a.z, 0.0, a.x - b.x).normalized()
		Street.face(st, [a, b, walls[k + 2] - plan.corner, walls[k + 5] - plan.corner], normal, "civic_blue")
	if not detail:
		return
	for k in range(0, tris.size(), 3):
		plan.solid_faces.append_array(PackedVector3Array([verts[tris[k]] - plan.corner,
				verts[tris[k + 1]] - plan.corner, verts[tris[k + 2]] - plan.corner]))
	for k in walls.size():
		plan.solid_faces.append(walls[k] - plan.corner)
	for row in lm.get("rows", []):
		plan.grind_lines.append([Lines.Kind.LEDGE, row as PackedVector3Array])


## A ballpark: the diamond, the outfield wall where the map's pitch ends,
## foul lines and poles, lights and the scoreboard.
static func _ballpark(plan: TilePlan, lm: Dictionary, st: SurfaceTool, batch: Batch, detail: bool) -> void:
	var home: Vector3 = lm.home - plan.corner
	var yaw := float(lm.yaw)
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var y := home.y + 0.04
	var ring := PackedVector2Array()
	for p in (lm.field as PackedVector3Array):
		ring.append(Vector2(p.x - plan.corner.x, p.z - plan.corner.z))
	# Where the wall stands at each angle off centre field (+ towards first).
	var angles := PackedFloat32Array()
	var reach := PackedFloat32Array()
	var a := -PI / 4.0
	while a <= PI / 4.0 + 0.001:
		angles.append(a)
		reach.append(_reach(home, _dir(fwd, right, a), ring))
		a += WALL_STEP
	# The grass to the wall, then the infield dirt, its grass and the mound.
	var fan := PackedVector3Array()
	for k in angles.size():
		fan.append(home + _dir(fwd, right, angles[k]) * reach[k])
	_fan(st, Vector3(home.x, y, home.z), fan, "grass")
	# The infield dirt runs out to an arc round the mound, meeting the foul
	# lines where that arc crosses them.
	var mound := home + fwd * MOUND
	var cross := MOUND * cos(PI / 4.0) + sqrt(INFIELD * INFIELD - pow(MOUND * sin(PI / 4.0), 2.0))
	var dirt := PackedVector3Array()
	var steps := 20
	for k in steps + 1:
		var at := home + _dir(fwd, right, -PI / 4.0 + PI / 2.0 * k / steps) * cross
		dirt.append(mound + (at - mound).normalized() * INFIELD)
	_fan(st, home + Vector3.UP * 0.08, dirt, "terracotta")
	var second := home + fwd * BASE_PATH * sqrt(2.0)
	var first := home + _dir(fwd, right, PI / 4.0) * BASE_PATH
	var third := home + _dir(fwd, right, -PI / 4.0) * BASE_PATH
	var middle := (home + second) * 0.5
	var inner: Array = []
	for c in [home, first, second, third]:
		inner.append(middle + (c - middle) * 0.8 + Vector3.UP * 0.12)
	Street.face(st, inner, Vector3.UP, "grass")
	_disc(st, home + fwd * MOUND + Vector3.UP * 0.14, 2.7, "terracotta")
	_disc(st, home + Vector3.UP * 0.14, 3.0, "terracotta")
	for base in [first, second, third]:
		Street.bar(st, base + Vector3.UP * 0.2, base + Vector3.UP * 0.2 + fwd * 0.4, 0.2, -0.1, 0.0, "white", "white")
	Street.bar(st, home + Vector3.UP * 0.18 - fwd * 0.2, home + Vector3.UP * 0.18 + fwd * 0.2, 0.22, -0.05, 0.0,
			"white", "white")
	# Foul lines out to the poles.
	for k in [0, angles.size() - 1]:
		var d := _dir(fwd, right, angles[k])
		Street.bar(st, home + d * 1.0 + Vector3.UP * 0.1, home + d * reach[k] + Vector3.UP * 0.1, 0.05, -0.05, 0.0,
				"white", "white")
	# The outfield wall, and the Monster where a park has one.
	var wall_h := float(lm.get("wall", 2.4))
	var wall_colour := str(lm.get("wall_colour", "iron_green"))
	var monster: Dictionary = lm.get("monster", {})
	var monster_side := -1.0 if str(monster.get("side", "left")) == "left" else 1.0
	var top := PackedVector3Array()
	var tall := PackedVector3Array()
	for k in angles.size() - 1:
		var p0 := home + _dir(fwd, right, angles[k]) * (reach[k] + 0.3)
		var p1 := home + _dir(fwd, right, angles[k + 1]) * (reach[k + 1] + 0.3)
		var mid := (angles[k] + angles[k + 1]) * 0.5
		var h := wall_h
		var colour := wall_colour
		if not monster.is_empty() and mid * monster_side > deg_to_rad(10.0):
			h = float(monster.height)
			colour = str(monster.get("colour", wall_colour))
		var a0 := Vector3(p0.x, home.y + h, p0.z)
		var a1 := Vector3(p1.x, home.y + h, p1.z)
		Street.bar(st, a0, a1, 0.3, -h - 1.0, 0.0, colour, "concrete_dark", 0.15)
		if detail:
			Street.solid_bar(plan.solid_faces, a0, a1, 0.3, -h - 1.0, 0.0)
		if h > wall_h:
			if tall.is_empty():
				tall.append(a0 + plan.corner)
			tall.append(a1 + plan.corner)
		else:
			if top.is_empty():
				top.append(a0 + plan.corner)
			top.append(a1 + plan.corner)
	if detail:
		if top.size() > 1:
			plan.grind_lines.append([Lines.Kind.WALL, top])
		if tall.size() > 1:
			plan.grind_lines.append([Lines.Kind.WALL, tall])
	# Foul poles: the model's fin is fair seen from home with home at its +z,
	# so the left-field pole faces home and the right one faces away.
	var last := angles.size() - 1
	for k in [0, last]:
		var at := home + _dir(fwd, right, angles[k]) * (reach[k] + 0.6)
		var face := atan2(home.x - at.x, home.z - at.z) + (PI if k == last else 0.0)
		batch.add("landmark/foul_pole", Transform3D(Basis(Vector3.UP, face), Vector3(at.x, home.y, at.z)))
	# Lights round the park, facing the infield.
	if bool(lm.get("big", false)):
		for deg in LIGHT_ANGLES:
			var ang := deg_to_rad(deg)
			var r := reach[0] * 0.75 if absf(deg) > 50.0 else _at_angle(angles, reach, ang) + 12.0
			if absf(deg) > 50.0:
				ang = signf(ang) * deg_to_rad(80.0)
			var at := home + _dir(fwd, right, ang) * r
			var aim := atan2(middle.x - at.x, middle.z - at.z)
			batch.add("landmark/light_tower", Transform3D(Basis(Vector3.UP, aim), Vector3(at.x, home.y, at.z)))
			if detail:
				plan.shapes.append(["post", Vector3(0.6, 30.0, 0.0), Transform3D(Basis.IDENTITY, at + Vector3.UP * 15.0)])
	# The scoreboard behind the wall (under the Monster's top where there's
	# one), and the bull standing over it.
	var board_ang := deg_to_rad(22.0) * (monster_side if not monster.is_empty() else 1.0)
	var board_r := _at_angle(angles, reach, board_ang) + (1.4 if not monster.is_empty() else 6.0)
	var board := home + _dir(fwd, right, board_ang) * board_r
	var board_face := atan2(home.x - board.x, home.z - board.z)
	var board_y := home.y + (float(monster.height) - 13.0 + 2.0 if not monster.is_empty() else 0.0)
	batch.add("landmark/scoreboard", Transform3D(Basis(Vector3.UP, board_face), Vector3(board.x, board_y, board.z)))
	if bool(lm.get("bull_sign", false)):
		var bull_ang := deg_to_rad(34.0) * (monster_side if not monster.is_empty() else -1.0)
		var bull_r := _at_angle(angles, reach, bull_ang) + (0.6 if not monster.is_empty() else 5.0)
		var bull := home + _dir(fwd, right, bull_ang) * bull_r
		var bull_y := home.y + (float(monster.height) if not monster.is_empty() else wall_h)
		batch.add("landmark/bull_sign", Transform3D(Basis(Vector3.UP, atan2(home.x - bull.x, home.z - bull.z)),
				Vector3(bull.x, bull_y, bull.z)))


## The direction `a` radians off centre field, towards first base when
## positive.
static func _dir(fwd: Vector3, right: Vector3, a: float) -> Vector3:
	return fwd * cos(a) + right * sin(a)


## How far from `home` along `d` the field's outline is (100 m if the ray
## misses it).
static func _reach(home: Vector3, d: Vector3, ring: PackedVector2Array) -> float:
	var o := Vector2(home.x, home.z)
	var far := o + Vector2(d.x, d.z) * 400.0
	var best := INF
	for k in ring.size():
		var hit = Geometry2D.segment_intersects_segment(o, far, ring[k], ring[(k + 1) % ring.size()])
		if hit != null:
			var t := o.distance_to(hit as Vector2)
			if t > 20.0:
				best = minf(best, t)
	return clampf(best if best < INF else 100.0, 60.0, 160.0)


## The wall's reach at an angle, from the samples either side.
static func _at_angle(angles: PackedFloat32Array, reach: PackedFloat32Array, a: float) -> float:
	for k in angles.size() - 1:
		if a <= angles[k + 1]:
			return lerpf(reach[k], reach[k + 1], clampf((a - angles[k]) / (angles[k + 1] - angles[k]), 0.0, 1.0))
	return reach[reach.size() - 1]


## A fan of triangles from `centre` through `rim`, facing up.
static func _fan(st: SurfaceTool, centre: Vector3, rim: PackedVector3Array, swatch: String) -> void:
	st.set_uv(Palette.uv(swatch))
	st.set_normal(Vector3.UP)
	for k in rim.size() - 1:
		var p0 := Vector3(rim[k].x, centre.y, rim[k].z)
		var p1 := Vector3(rim[k + 1].x, centre.y, rim[k + 1].z)
		# Clockwise from above is the front.
		if (p0 - centre).cross(p1 - centre).y < 0.0:
			st.add_vertex(centre)
			st.add_vertex(p0)
			st.add_vertex(p1)
		else:
			st.add_vertex(centre)
			st.add_vertex(p1)
			st.add_vertex(p0)


static func _disc(st: SurfaceTool, centre: Vector3, r: float, swatch: String) -> void:
	var rim := PackedVector3Array()
	for k in 17:
		var t := TAU * k / 16.0
		rim.append(centre + Vector3(cos(t), 0.0, sin(t)) * r)
	_fan(st, centre, rim, swatch)
