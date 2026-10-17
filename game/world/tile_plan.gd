class_name TilePlan
extends RefCounted
## Everything one 256 m square of a town needs, worked out from the
## Cartographer's tile (see docs/tiles.md) as plain arrays: the ground, the
## water, every building's shell and roof, and, when the tile is near the
## player, the detail (facades, steps, kerbs, fences, walls, rails, wires,
## bridges, street props and collision). `TileView` turns a plan into nodes.
##
## A plan is only arithmetic: it makes no meshes, textures or shapes, so it
## runs on a worker thread without waiting on the renderer. Geometry is in
## the tile's own frame (its north-west corner at the origin); what the
## tile adds to the town's registries (grind and climb lines, paintable
## faces, traffic lanes) is in town coordinates.

const SIZE := 256.0
const CELLS := 64
const CELL := 4.0
## How far the plain shell sits inside the facade's face (the facade kit's
## walls are 0.3 m thick), and how far it goes into the ground.
const SHELL_INSET := 0.25
const BURY := 1.5
## Facades are batched by blocks of this size, so far blocks drop out.
const BLOCK := 128.0
const ROOFS := {"brick": "slate", "plaster": "stone", "modern": "concrete_light", "works": "steel_dark"}
const STAIR_WALLS := ["stone", "concrete_light", "cream", "concrete"]
const GARDEN_WALLS := ["brick", "stone", "concrete_light", "cream", "brick_dark"]
## Street props that block the way: a post of a radius, or the model's box;
## a ledge is a grind line along the front of the top.
const PROP_SOLIDS := {
	"street/street_lamp": {"post": 0.16}, "street/power_pole": {"post": 0.17}, "street/street_tree": {"post": 0.14},
	"street/traffic_light": {"post": 0.14}, "street/sign_post": {"post": 0.06}, "street/bollard": {"post": 0.13},
	"street/hydrant": {"post": 0.2}, "street/litter_bin": {"post": 0.3}, "street/bench": {"box": true},
	"street/dumpster": {"box": true, "ledge": true}, "street/planter": {"box": true, "ledge": true},
	"street/utility_box": {"box": true},
}

var key := Vector2i.ZERO
## The tile's north-west corner in town coordinates.
var corner := Vector3.ZERO
var near := false
## Heights every CELL metres, (CELLS + 1) squared, rows running south.
var heights := PackedFloat32Array()
## The ground's mesh arrays and its cover picture (an Image, mipmapped).
var ground := []
var cover: Image
## Mesh arrays, or [] when there's nothing: the water, the shells' walls
## and roofs, and the detail's street boxes and tubes.
var water := []
var shell_walls := []
var roofs := []
var street := []
var tubes := []
## MultiMesh buffers (`Batch.buffers()`): facades by block name, props, steps.
var facades := {}
var props := {}
var steps := {}
## Collision: the built things as triangles, and props and ramps as
## [kind ("post" or "box"), size (Vector3; x is a post's radius), Transform3D].
var solid_faces := PackedVector3Array()
var shapes: Array = []
## For the town's registries, in town coordinates: [Lines.Kind, points],
## the paintable faces as Walls takes them, and the lanes {"pts", "kind"}.
var grind_lines: Array = []
var faces: Array = []
var lanes: Array = []
var build_ms := 0.0


## Works out a tile. `ctx` comes from `TownView.context()`; it's only read.
static func make(tile: Dictionary, with_detail: bool, ctx: Dictionary) -> TilePlan:
	var t0 := Time.get_ticks_usec()
	var plan := TilePlan.new()
	plan.key = Vector2i(int(tile.i), int(tile.j))
	plan.corner = Vector3(float(tile.x0), 0.0, float(tile.z0))
	plan.near = with_detail
	plan.heights = tile.heights
	plan._ground(tile)
	plan._water(tile.water)
	plan._shells(tile.buildings)
	if with_detail:
		plan._detail(tile, ctx)
	plan.build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	return plan


## The ground's height at a point of the tile (in its own frame).
func height_at(x: float, z: float) -> float:
	var n := CELLS + 1
	var fx := clampf(x / CELL, 0.0, CELLS - 0.0001)
	var fz := clampf(z / CELL, 0.0, CELLS - 0.0001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var top := lerpf(heights[j * n + i], heights[j * n + i + 1], tx)
	var bottom := lerpf(heights[(j + 1) * n + i], heights[(j + 1) * n + i + 1], tx)
	return lerpf(top, bottom, tz)


# The ground and the water -------------------------------------------------

func _ground(tile: Dictionary) -> void:
	var h := heights
	var n := CELLS + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(n * n)
	normals.resize(n * n)
	uvs.resize(n * n)
	for j in n:
		for i in n:
			var k := j * n + i
			verts[k] = Vector3(i * CELL, h[k], j * CELL)
			uvs[k] = Vector2(float(i) / CELLS, float(j) / CELLS)
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, CELLS)
			var j0 := maxi(j - 1, 0)
			var j1 := mini(j + 1, CELLS)
			var dx := (h[j * n + i1] - h[j * n + i0]) / (CELL * (i1 - i0))
			var dz := (h[j1 * n + i] - h[j0 * n + i]) / (CELL * (j1 - j0))
			normals[k] = Vector3(-dx, 1.0, -dz).normalized()
	var idx := PackedInt32Array()
	idx.resize(CELLS * CELLS * 6)
	var w := 0
	for j in CELLS:
		for i in CELLS:
			var a := j * n + i
			# Clockwise seen from above, as Godot draws front faces.
			idx[w] = a
			idx[w + 1] = a + 1
			idx[w + 2] = a + n
			idx[w + 3] = a + 1
			idx[w + 4] = a + n + 1
			idx[w + 5] = a + n
			w += 6
	ground = _arrays(verts, normals, idx)
	ground[Mesh.ARRAY_TEX_UV] = uvs
	cover = Image.new()
	if cover.load_png_from_buffer(tile.ground) == OK:
		cover.generate_mipmaps()
	else:
		cover = null


func _water(w: Dictionary) -> void:
	var src: PackedVector3Array = w.verts
	var tris: PackedInt32Array = w.tris
	if tris.is_empty():
		return
	var verts := PackedVector3Array()
	verts.resize(src.size())
	for k in src.size():
		verts[k] = src[k] - corner
	var idx := PackedInt32Array()
	idx.resize(tris.size())
	# The Cartographer winds them anticlockwise seen from above.
	for k in range(0, tris.size(), 3):
		idx[k] = tris[k]
		idx[k + 1] = tris[k + 2]
		idx[k + 2] = tris[k + 1]
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	water = _arrays(verts, normals, idx)


static func _arrays(verts: PackedVector3Array, normals: PackedVector3Array, idx: PackedInt32Array) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays


# Buildings ----------------------------------------------------------------

## A building's wall colour: the one its facade takes.
static func wall_colour(b: Dictionary) -> Color:
	return Facade.recipe(str(b.style), "home", int(b.seed)).wall


## How high a building's facade reaches: its roof plus the style's cornice
## and parapet.
static func crest(b: Dictionary) -> float:
	var style: Dictionary = Facade.STYLES.get(str(b.style), Facade.STYLES.plaster)
	var y := float(b.top)
	for piece in style.top:
		y += 0.6 if piece == "cornice" else 0.95
	return y


## Every building's shell (walls set back behind the facade, with windows
## drawn on for when the facade is out of range) and roof.
func _shells(buildings: Array) -> void:
	if buildings.is_empty():
		return
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tops := SurfaceTool.new()
	tops.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roof_count := 0
	for b in buildings:
		var colour := wall_colour(b)
		var y0 := float(b.y0) - BURY
		var top := float(b.top)
		var seed_uv := float(int(b.seed) % 997)
		var outer := true
		for ring in b.rings:
			var pts := _oriented(ring, outer)
			outer = false
			var inset := _inset(pts, SHELL_INSET)
			var along := 0.0
			for k in inset.size():
				var a := inset[k]
				var c := inset[(k + 1) % inset.size()]
				var length := a.distance_to(c)
				var lo_a := Vector3(a.x - corner.x, y0, a.y - corner.z)
				var lo_b := Vector3(c.x - corner.x, y0, c.y - corner.z)
				var d := (c - a) / maxf(length, 0.001)
				var normal := Vector3(-d.y, 0.0, d.x)
				walls.set_color(colour)
				walls.set_normal(normal)
				walls.set_uv2(Vector2(seed_uv, float(b.storeys)))
				_quad_uv(walls, [Vector3(lo_a.x, top, lo_a.z), Vector3(lo_b.x, top, lo_b.z), lo_b, lo_a],
						[Vector2(along, 0.0), Vector2(along + length, 0.0), Vector2(along + length, top - y0),
						Vector2(along, top - y0)], normal)
				along += length
		# The roof, from the Cartographer's triangles over the outline.
		var flat := _flat_rings(b.rings, top)
		var tris: PackedInt32Array = b.tris
		tops.set_color(Palette.color(ROOFS.get(str(b.style), "concrete_light")))
		tops.set_normal(Vector3.UP)
		for k in range(0, tris.size(), 3):
			tops.add_vertex(flat[tris[k]])
			tops.add_vertex(flat[tris[k + 2]])
			tops.add_vertex(flat[tris[k + 1]])
			roof_count += 1
	shell_walls = walls.commit_to_arrays()
	if roof_count > 0:
		roofs = tops.commit_to_arrays()


func _flat_rings(rings: Array, y: float) -> PackedVector3Array:
	var flat := PackedVector3Array()
	for ring in rings:
		for p in ring:
			flat.append(Vector3(p.x - corner.x, y, p.y - corner.z))
	return flat


## A ring turned so its outside is on the right of each edge (as the
## Cartographer's faces are): clockwise in maths terms for an outer ring,
## anticlockwise for a courtyard.
static func _oriented(ring: PackedVector2Array, outer: bool) -> PackedVector2Array:
	var area := 0.0
	for k in ring.size():
		var a := ring[k]
		var b := ring[(k + 1) % ring.size()]
		area += a.x * b.y - b.x * a.y
	if (area < 0.0) == outer:
		return ring
	var out := ring.duplicate()
	out.reverse()
	return out


## A ring moved `by` metres inwards (to the left of each edge).
static func _inset(ring: PackedVector2Array, by: float) -> PackedVector2Array:
	var n := ring.size()
	var out := PackedVector2Array()
	out.resize(n)
	for k in n:
		var d0 := (ring[k] - ring[(k - 1 + n) % n]).normalized()
		var d1 := (ring[(k + 1) % n] - ring[k]).normalized()
		var n0 := Vector2(-d0.y, d0.x)
		var m := n0 + Vector2(-d1.y, d1.x)
		m = n0 if m.length() < 0.001 else m.normalized()
		out[k] = ring[k] - m * (by / maxf(m.dot(n0), 0.35))
	return out


# The detail ---------------------------------------------------------------

func _detail(tile: Dictionary, ctx: Dictionary) -> void:
	var blocks := {}
	var prop_batch := Batch.new()
	var step_batch := Batch.new()
	var bars := SurfaceTool.new()
	bars.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tube_tool := SurfaceTool.new()
	tube_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var counts := {"bars": 0, "tubes": 0}
	for b in tile.buildings:
		_building(b, blocks, prop_batch)
	for f in tile.flights:
		_flight(f, step_batch)
	for line in tile.lines:
		_line(line, bars, tube_tool, counts)
	for br in tile.bridges:
		_bridge(br, bars)
		counts.bars += 1
	for p in tile.props:
		_prop(p, prop_batch, ctx)
	for lane in tile.lanes:
		if not bool(lane.get("bridge", false)):
			lanes.append({"pts": lane.pts, "kind": str(lane.kind)})
	for cell in blocks:
		facades["Facades_%d_%d" % [cell.x, cell.y]] = (blocks[cell] as Batch).buffers()
	props = prop_batch.buffers()
	steps = step_batch.buffers()
	if counts.bars > 0:
		street = bars.commit_to_arrays()
	if counts.tubes > 0:
		tube_tool.generate_normals()
		tubes = tube_tool.commit_to_arrays()


func _building(b: Dictionary, blocks: Dictionary, prop_batch: Batch) -> void:
	var rec := Facade.recipe(str(b.style), "home", int(b.seed))
	var top_crest := crest(b)
	var chain := PackedVector3Array()
	for f in b.faces:
		var a: Vector3 = f.p0 - corner
		var c: Vector3 = f.p1 - corner
		var mid := (a + c) * 0.5
		var cell := Vector2i(clampi(int(mid.x / BLOCK), 0, 1), clampi(int(mid.z / BLOCK), 0, 1))
		if not blocks.has(cell):
			blocks[cell] = Batch.new()
		var face_rec := rec.duplicate()
		face_rec["ground"] = str(f.ground)
		face_rec["pipe_at"] = int(f.pipe)
		face_rec["escape_bay"] = int(f.escape)
		var ends: Array = f.ends
		var laid := Facade.lay(blocks[cell], a, c, int(f.storeys), face_rec, int(f.seed),
				Vector2i(int(ends[0]), int(ends[1])))
		for climb in laid.climbs:
			grind_lines.append([Lines.Kind.CLIMB, _to_town(climb)])
		faces.append({
			"id": str(f.id), "a": f.p0, "b": f.p1, "base": float(f.p0.y), "top": float(f.paint_top),
			"paint": int(f.paint), "eyes": int(f.eyes), "quarter": int(f.quarter), "heaven": false,
		})
		# The roof's edge, a little inside the facade's face, to grind along:
		# faces that meet end to end make one line.
		var d := c - a
		d.y = 0.0
		var length := d.length()
		if length < Facade.MIN_LENGTH:
			_end_chain(chain)
			chain = PackedVector3Array()
			continue
		d /= length
		var inward := Vector3(d.z, 0.0, -d.x) * 0.1
		var p0 := Vector3(f.p0.x, top_crest, f.p0.z) + inward
		var p1 := Vector3(f.p1.x, top_crest, f.p1.z) + inward
		if not chain.is_empty() and chain[chain.size() - 1].distance_to(p0) > 0.3:
			_end_chain(chain)
			chain = PackedVector3Array()
		if chain.is_empty():
			chain.append(p0)
		else:
			chain[chain.size() - 1] = (chain[chain.size() - 1] + p0) * 0.5
		chain.append(p1)
	_end_chain(chain)
	for p in b.props:
		prop_batch.add(str(p.m), Transform3D(Basis(Vector3.UP, float(p.yaw)), p.p - corner))
	# Collision: the walls on the outline up to the facade's top, and the roof.
	var y0 := float(b.y0) - BURY
	for ring in b.rings:
		for k in ring.size():
			var a2: Vector2 = ring[k]
			var c2: Vector2 = ring[(k + 1) % ring.size()]
			var a := Vector3(a2.x - corner.x, y0, a2.y - corner.z)
			var c := Vector3(c2.x - corner.x, y0, c2.y - corner.z)
			var a_hi := Vector3(a.x, top_crest, a.z)
			var c_hi := Vector3(c.x, top_crest, c.z)
			solid_faces.append_array(PackedVector3Array([a, c, c_hi, a, c_hi, a_hi]))
	var flat := _flat_rings(b.rings, float(b.top))
	var roof: PackedInt32Array = b.tris
	for k in range(0, roof.size(), 3):
		solid_faces.append(flat[roof[k]])
		solid_faces.append(flat[roof[k + 2]])
		solid_faces.append(flat[roof[k + 1]])


func _end_chain(chain: PackedVector3Array) -> void:
	if chain.size() >= 2:
		grind_lines.append([Lines.Kind.PARAPET, chain])


func _flight(f: Dictionary, step_batch: Batch) -> void:
	var bottom: Vector3 = f.bottom - corner
	var up := Vector3(f.up.x, 0.0, f.up.y)
	var tint := Palette.color(STAIR_WALLS[absi(hash([f.bottom.x, f.bottom.z])) % STAIR_WALLS.size()])
	var laid := Stairs.lay(step_batch, bottom, up, int(f.steps), float(f.width), tint, bool(f.walls), float(f.rise),
			float(f.going))
	for rail in laid.rails:
		grind_lines.append([Lines.Kind.HANDRAIL, _to_town(rail)])
	for coping in laid.copings:
		grind_lines.append([Lines.Kind.COPING, _to_town(coping)])
	var ramp := Stairs.ramp_box(bottom, up, int(f.steps), float(f.width), float(f.rise), float(f.going))
	shapes.append(["box", ramp[1], ramp[0]])


func _line(line: Dictionary, st: SurfaceTool, tube_tool: SurfaceTool, counts: Dictionary) -> void:
	var pts: PackedVector3Array = line.pts
	var local := PackedVector3Array()
	local.resize(pts.size())
	for k in pts.size():
		local[k] = pts[k] - corner
	match str(line.kind):
		"kerb":
			grind_lines.append([Lines.Kind.KERB, pts])
			for k in local.size() - 1:
				Street.bar(st, local[k], local[k + 1], 0.12, -0.32, 0.0, "kerb", "kerb", 0.06)
		"fence":
			var h := float(line.get("height", 1.2))
			grind_lines.append([Lines.Kind.FENCE, pts])
			Street.fence(st, local, h)
			for k in local.size() - 1:
				Street.solid_bar(solid_faces, local[k], local[k + 1], 0.06, -h, 0.0)
		"wall":
			var h := float(line.get("height", 1.2))
			var swatch: String = GARDEN_WALLS[absi(hash([pts[0].x, pts[0].z])) % GARDEN_WALLS.size()]
			var top := PackedVector3Array()
			for p in pts:
				top.append(p + Vector3.UP * 0.07)
			grind_lines.append([Lines.Kind.WALL, top])
			for k in local.size() - 1:
				Street.bar(st, local[k], local[k + 1], 0.15, -h - 0.3, 0.0, swatch, swatch, 0.0)
				Street.bar(st, local[k], local[k + 1], 0.2, 0.0, 0.07, "stone", "stone", 0.1)
				Street.solid_bar(solid_faces, local[k], local[k + 1], 0.2, -h - 0.3, 0.07)
		"rail":
			grind_lines.append([Lines.Kind.RAIL, pts])
			tube_tool.set_uv(Palette.uv("chrome"))
			Tube.add_to(tube_tool, local, 0.04, 6)
			counts.tubes += 1
			return
		"track":
			Street.sleepers(st, local)
		"wire":
			grind_lines.append([Lines.Kind.WIRE, pts])
			tube_tool.set_uv(Palette.uv("ink"))
			Tube.add_to(tube_tool, local, 0.025, 4)
			counts.tubes += 1
			return
		"parapet":
			grind_lines.append([Lines.Kind.PARAPET, pts])
			for k in local.size() - 1:
				Street.bar(st, local[k], local[k + 1], 0.15, -1.0, 0.0, "concrete_light", "stone", 0.1)
				Street.solid_bar(solid_faces, local[k], local[k + 1], 0.15, -1.0, 0.0)
		_:
			return
	counts.bars += 1


func _bridge(br: Dictionary, st: SurfaceTool) -> void:
	var pts: PackedVector3Array = br.pts
	var hw := float(br.width) * 0.5
	var top := "asphalt" if bool(br.motor) else "paving"
	var since := 0.0
	for k in pts.size() - 1:
		var a := pts[k] - corner
		var c := pts[k + 1] - corner
		Street.bar(st, a, c, hw, -0.9, 0.0, "concrete", top, 0.0)
		Street.solid_bar(solid_faces, a, c, hw, -0.9, 0.0)
		since += a.distance_to(c)
		# Piers down to the ground every so often.
		if since > 16.0 and k < pts.size() - 2:
			since = 0.0
			var ground_y := height_at(c.x, c.z)
			if c.y - ground_y > 2.0:
				Street.pier(st, c, ground_y, 0.6)
				Street.solid_bar(solid_faces, c + Vector3(0, -0.9, -0.6), c + Vector3(0, -0.9, 0.6), 0.6,
						ground_y - c.y + 0.9, 0.0)


func _prop(p: Dictionary, prop_batch: Batch, ctx: Dictionary) -> void:
	var model := str(p.m)
	var xf := Transform3D(Basis(Vector3.UP, float(p.yaw)), p.p - corner)
	prop_batch.add(model, xf)
	if not PROP_SOLIDS.has(model):
		return
	var spec: Dictionary = PROP_SOLIDS[model]
	var box: AABB = ctx.prop_boxes.get(model, AABB(Vector3(-0.2, 0, -0.2), Vector3(0.4, 1.0, 0.4)))
	if spec.has("post"):
		shapes.append(["post", Vector3(float(spec.post), box.size.y, 0.0),
				Transform3D(Basis.IDENTITY, xf.origin + Vector3.UP * (box.position.y + box.size.y * 0.5))])
	else:
		shapes.append(["box", box.size, Transform3D(xf.basis, xf * box.get_center())])
	if spec.has("ledge"):
		var front := box.end.z - 0.04
		var ledge := PackedVector3Array([xf * Vector3(box.position.x + 0.05, box.end.y, front),
				xf * Vector3(box.end.x - 0.05, box.end.y, front)])
		grind_lines.append([Lines.Kind.LEDGE, _to_town(ledge)])


func _to_town(pts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(pts.size())
	for k in pts.size():
		out[k] = pts[k] + corner
	return out


## Adds a quad with its own UVs, wound so it faces `normal`.
static func _quad_uv(st: SurfaceTool, p: Array, uv: Array, normal: Vector3) -> void:
	var order := [0, 1, 2, 0, 2, 3]
	if ((p[1] - p[0]) as Vector3).cross(p[2] - p[0]).dot(normal) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for k in order:
		st.set_uv(uv[k])
		st.add_vertex(p[k])
