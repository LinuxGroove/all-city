extends RefCounted
## The town streams: Monaco (which comes with the game) loads round its
## spawn with collision, grind lines and paintable walls, follows the
## player from tile to tile, moves back round them when they get far from
## the origin, and has traffic that stops for writers.

const TOWN := "monaco"


func _town(t) -> Dictionary:
	var town := Towns.find(TOWN)
	t.check(not town.is_empty(), "Monaco comes with the game")
	return town


func test_tile_plan(t) -> void:
	var town := _town(t)
	if town.is_empty():
		return
	var tile := TownTiles.load_tile(str(town.path), 0, -1)
	t.check(not tile.is_empty(), "a tile reads")
	var ctx := TownView.context(1)
	var far := TilePlan.make(tile, false, ctx)
	t.check(not far.ground.is_empty() and far.cover != null, "a far tile has its ground and cover")
	t.check(far.facades.is_empty() and far.grind_lines.is_empty(), "a far tile has no detail")
	var near := TilePlan.make(tile, true, ctx)
	var walls := 0
	for b in tile.buildings:
		walls += (b.faces as Array).size()
	t.check(near.faces.size() == walls, "every face of every building is a paintable wall")
	t.check(not near.facades.is_empty(), "facades are laid")
	t.check(not near.solid_faces.is_empty(), "buildings are solid")
	var kinds := {}
	for item in near.grind_lines:
		kinds[item[0]] = true
	t.check(kinds.has(Lines.Kind.PARAPET), "roof edges are grind lines")
	t.check(kinds.has(Lines.Kind.CLIMB), "there are ways up to the roofs")
	t.check(near.build_ms < 2000.0, "a near tile works out in under two seconds (%.0f ms)" % near.build_ms)


## Landmarks on a tile: a ballpark with its wall, poles, lights and
## scoreboard, a grandstand's rows and a water tower, drawn at any distance
## and solid with the detail.
func test_landmarks(t) -> void:
	var town := _town(t)
	if town.is_empty():
		return
	var tile := TownTiles.load_tile(str(town.path), 0, -1)
	var c := Vector3(float(tile.x0) + 128.0, 50.0, float(tile.z0) + 200.0)
	var field := PackedVector3Array([c])
	for k in 9:
		var a := -PI / 4.0 + PI / 2.0 * k / 8.0
		field.append(c + Vector3(sin(a), 0.0, -cos(a)) * 110.0)
	var stand_verts := PackedVector3Array([c + Vector3(-10, 1, 10), c + Vector3(10, 1, 10), c + Vector3(10, 1, 12),
			c + Vector3(-10, 1, 10), c + Vector3(10, 1, 12), c + Vector3(-10, 1, 12)])
	tile.landmarks = [
		{"kind": "ballpark", "name": "Test Park", "home": c, "yaw": PI, "field": field, "big": true, "wall": 2.4,
				"monster": {"side": "left", "height": 9.8, "colour": "civic_blue"}, "bull_sign": true},
		{"kind": "stand", "name": "", "p": c + Vector3(0, 0, 11), "height": 1.0, "verts": stand_verts,
				"tris": PackedInt32Array([0, 1, 2, 3, 4, 5]), "walls": PackedVector3Array(),
				"rows": [PackedVector3Array([c + Vector3(-10, 1, 10), c + Vector3(10, 1, 10)])]},
		{"kind": "water_tower", "m": "landmark/water_tower", "name": "", "p": c + Vector3(40, 0, 40), "yaw": 0.0,
				"s": 1.5},
	]
	var ctx := TownView.context(1)
	var far := TilePlan.make(tile, false, ctx)
	t.check(not far.landmark_mesh.is_empty(), "a far tile draws its landmarks")
	for m in ["landmark/foul_pole", "landmark/light_tower", "landmark/scoreboard", "landmark/bull_sign",
			"landmark/water_tower"]:
		t.check(far.landmark_models.has(m), "the ballpark and tower place %s" % m)
		t.check(Kit.mesh(m) != null, "%s is in the kit" % m)
	t.check(int(far.landmark_models["landmark/foul_pole"][1]) == 2, "two foul poles")
	var plain := TilePlan.make(TownTiles.load_tile(str(town.path), 0, -1), true, ctx)
	var near := TilePlan.make(tile, true, ctx)
	t.check(near.solid_faces.size() > plain.solid_faces.size(), "the wall and the stand are solid")
	t.check(near.shapes.size() >= plain.shapes.size() + 8, "light towers and the tower's legs are in the way")
	var walls := 0
	var ledges := 0
	for item in near.grind_lines:
		walls += 1 if item[0] == Lines.Kind.WALL else 0
		ledges += 1 if item[0] == Lines.Kind.LEDGE else 0
	t.check(walls >= 2, "the outfield wall and the Monster are grind lines")
	t.check(ledges >= 1, "the stand's rows are ledges")


func test_town_streams(t) -> void:
	var town := _town(t)
	if town.is_empty():
		return
	var view := TownView.new()
	t.add_child(view)
	view.open(town, 1)
	var spawn := view.spawn()
	var at: Vector3 = spawn.p
	view.load_around(at)
	var near := 0
	for key in view.shown():
		near += 1 if view.shown()[key] else 0
	t.check(near >= 4, "the tiles round the spawn are in, in detail (%d)" % near)
	t.check(view.walls.size() > 100, "their walls are paintable (%d)" % view.walls.size())
	var kinds := {}
	for id in view.lines.ids():
		kinds[view.lines.line(id).kind] = true
	for k in [Lines.Kind.HANDRAIL, Lines.Kind.KERB, Lines.Kind.CLIMB, Lines.Kind.PARAPET]:
		t.check(kinds.has(k), "the town has %s lines" % Lines.Kind.keys()[k])
	t.check(view.traffic.lane_count() > 0, "the streets have lanes")
	await t.get_tree().physics_frame
	await t.get_tree().physics_frame
	var space := view.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 30.0, at - Vector3.UP * 30.0,
			Kit.LAYER_WORLD))
	t.check(not hit.is_empty() and absf(hit.position.y - (at.y - 0.5)) < 1.5,
			"the spawn stands on solid ground (%s)" % str(hit.get("position", "nothing")))
	# Going on to the next tile streams it in.
	var east := at + Vector3(TilePlan.SIZE * 1.0, 0, 0)
	var key := view.key_at(east)
	for i in 4000:
		view.follow(east)
		if view.settled():
			break
		await t.get_tree().process_frame
	t.check(view.settled(), "the town settles round a new place")
	t.check(view.shown().get(key, false), "the tile ahead comes in, in detail")
	t.check(view.tiles.size() > 9, "the far ring is shown too (%d tiles)" % view.tiles.size())
	# Getting far from the origin moves the world back round the player.
	var id: int = view.lines.nearest(at, 300.0).id
	var before: Vector3 = view.lines.line(id).pts[0]
	var tile: TileView = view.tiles[view.key_at(at)]
	var tile_at := tile.position
	# Out past the limit but still in the spawn's tile, so nothing is dropped.
	var go := Vector3(-(TownView.RECENTRE + 8.0), at.y, at.z)
	t.check(view.key_at(go) == view.key_at(at), "the test's far point is in the spawn's tile")
	var moved := view.follow(go)
	t.check(moved == Vector3(512.0, 0, 0), "the world moves back by whole tiles (%s)" % str(moved))
	t.check(view.origin == Vector3(-512.0, 0, 0), "and the origin moves on as far")
	t.check(view.lines.line(id).pts[0].is_equal_approx(before + moved), "grind lines move with it")
	t.check(tile.position.is_equal_approx(tile_at + moved), "tiles move with it")
	var found := view.lines.nearest(view.lines.line(id).pts[0], 0.3)
	t.check(not found.is_empty(), "lines are found where they've moved to")
	t.check(view.lines.nearest(before, 0.3, [view.lines.line(id).kind]).get("id", -1) != id or before == view.lines.line(id).pts[0],
			"and no longer where they were")
	var moved_wall: Dictionary = view.walls.face(view.walls._faces.keys()[0])
	var wall_mid: Vector3 = (moved_wall.a + moved_wall.b) * 0.5
	var wall_hit := view.walls.nearest(wall_mid + (moved_wall.b - moved_wall.a).cross(Vector3.UP).normalized() * 0.5, 2.0)
	t.check(not wall_hit.is_empty(), "walls are found where they've moved to")
	var p: Array = town.spawn.p
	t.check(view.to_town(view.spawn().p).is_equal_approx(Vector3(p[0], p[1], p[2])),
			"the town's own places stay where they are")
	view.queue_free()


## Every town that comes with the game (res://towns/): its manifest and
## tiles are all there, it carries OpenStreetMap's credit, it starts a writer
## on solid ground with a way up and walls to paint, and it has quarters.
func test_bundled_towns(t) -> void:
	var ids := DirAccess.get_directories_at(Towns.BUNDLED)
	t.check(ids.has(TOWN), "Monaco is among the bundled towns")
	for id in ids:
		var town := Towns.read(Towns.BUNDLED.path_join(id))
		t.check(not town.is_empty() and str(town.id) == id, "%s: the manifest reads and has the folder's id" % id)
		if town.is_empty():
			continue
		var tiles: Array = town.tiles
		var missing := 0
		for k in tiles:
			missing += 0 if FileAccess.file_exists(str(town.path).path_join("tiles/%d_%d.tile" % [k[0], k[1]])) else 1
		t.check(not tiles.is_empty() and missing == 0, "%s: all %d tiles are there" % [id, tiles.size()])
		var credit := false
		for line in town.get("attribution", []):
			credit = credit or "OpenStreetMap" in str(line)
		t.check(credit, "%s: the town card carries OpenStreetMap's credit" % id)
		t.check((town.get("quarters", []) as Array).size() > 0, "%s: it has quarters" % id)
		var p: Array = town.spawn.p
		t.check(Rect2(town.box[0], town.box[1], town.box[2] - town.box[0], town.box[3] - town.box[1]).has_point(Vector2(p[0], p[2])),
				"%s: the spawn is inside the town" % id)
		var view := TownView.new()
		t.add_child(view)
		view.open(town, 1)
		var at: Vector3 = view.spawn().p
		view.load_around(at)
		t.check(view.walls.size() > 100 and view.lines.count() > 100, "%s: round the spawn there are walls (%d) and lines (%d)" % [id,
				view.walls.size(), view.lines.count()])
		t.check(not view.lines.nearest(at, 150.0, [Lines.Kind.CLIMB]).is_empty(), "%s: a way up to a roof is near the spawn" % id)
		await t.get_tree().physics_frame
		await t.get_tree().physics_frame
		var hit := view.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 30.0,
				at - Vector3.UP * 30.0, Kit.LAYER_WORLD))
		t.check(not hit.is_empty() and absf(hit.position.y - (at.y - 0.5)) < 1.5, "%s: the spawn stands on solid ground" % id)
		view.queue_free()


func test_traffic(t) -> void:
	var traffic := Traffic.new()
	t.add_child(traffic)
	var a := PackedVector3Array([Vector3(0, 0, 0), Vector3(100, 0, 0)])
	var b := PackedVector3Array([Vector3(100, 0, 0), Vector3(220, 0, 0)])
	traffic.add_lanes("t", [{"pts": a, "kind": "residential"}, {"pts": b, "kind": "residential"}])
	t.check(traffic.lane_count() == 2, "lanes go in")
	traffic.focus = Vector3(110, 0, 70)
	for i in 120:
		traffic._physics_process(1.0 / 60.0)
	t.check(traffic.car_count() > 3, "cars come out on the lanes (%d)" % traffic.car_count())
	# A writer in the road: the car behind them stops short.
	var car: Node3D = traffic.cars()[0]
	var writer := Node3D.new()
	t.add_child(writer)
	writer.position = car.position + car.global_basis.z * 9.0
	traffic.watch = [writer]
	traffic.focus = Vector3(110, 0, 70)
	for i in 240:
		traffic._physics_process(1.0 / 60.0)
	if is_instance_valid(car):
		var gap := (writer.position - car.position).dot(car.global_basis.z)
		t.check(gap > 2.0, "a car stops for a writer in front of it (%.1f m short)" % gap)
	traffic.drop_lanes("t")
	t.check(traffic.lane_count() == 0 and traffic.car_count() == 0, "dropping a tile's lanes takes its cars")
	writer.queue_free()
	traffic.queue_free()
