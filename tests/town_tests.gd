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
	var id: int = view.lines.ids()[0]
	var before: Vector3 = view.lines.line(id).pts[0]
	var tile: TileView = view.tiles.values()[0]
	var tile_at := tile.position
	var moved := view.follow(Vector3(TownView.RECENTRE + 40.0, at.y, 0))
	t.check(moved == Vector3(-512.0, 0, 0), "the world moves back by whole tiles (%s)" % str(moved))
	t.check(view.origin == Vector3(512.0, 0, 0), "and the origin moves on as far")
	t.check(view.lines.line(id).pts[0].is_equal_approx(before + moved), "grind lines move with it")
	t.check(tile.position.is_equal_approx(tile_at + moved), "tiles move with it")
	var p: Array = town.spawn.p
	t.check(view.to_town(view.spawn().p).is_equal_approx(Vector3(p[0], p[1], p[2])),
			"the town's own places stay where they are")
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
