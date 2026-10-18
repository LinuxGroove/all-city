extends RefCounted
## The town map: what it reads from Monaco's tiles (ground, roofs, water,
## quarters and where every wall is), and the map itself: opening on the
## Map button and holding the game, looking round and zooming inside the
## town, the writer and the paint on it.


func _frames(t, n := 3) -> void:
	for i in n:
		await t.get_tree().process_frame


func _action(t, action: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(t, 2)


func _town(t) -> Dictionary:
	var town := Towns.find("monaco")
	t.check(not town.is_empty(), "Monaco comes with the game")
	return town


func test_map_data(t) -> void:
	var town := _town(t)
	if town.is_empty():
		return
	var start := Time.get_ticks_msec()
	var data := TownMapData.read(town)
	var took := Time.get_ticks_msec() - start
	t.check(not data.is_empty(), "Monaco's tiles are read (%d ms)" % took)
	t.check(data.ground.size() == town.tiles.size(), "a ground picture for every tile")
	var px := int(data.pixels)
	t.check(px == TownMapData.PIXELS_MID or px == TownMapData.PIXELS_SMALL, "at a size by the town's (%d)" % px)
	t.check((data.ground[0].image as Image).get_width() == px, "each shrunk to it")
	t.check(data.roofs.indices.size() > 3000 and data.roofs.verts.size() == data.roofs.colors.size(), "roofs, with a colour a corner (%d)" % data.roofs.verts.size())
	t.check(data.roofs.indices.size() % 3 == 0 and int(data.roofs.indices.size() > 0 and data.roofs.indices[-1]) < data.roofs.verts.size(), "whose triangles stay inside them")
	t.check(data.water.indices.size() > 0, "and the sea")
	t.check(data.faces.size() > 1000, "and where each wall is (%d)" % data.faces.size())
	var box: Rect2 = data.box
	var inside := true
	for id in data.faces:
		inside = inside and box.grow(64.0).has_point(data.faces[id])
	t.check(inside, "all within a building's length of the town's box")
	var known := 0
	for q in town.quarters:
		for cell in data.cells.ids:
			if cell == int(q.id):
				known += 1
				break
	t.check(known == town.quarters.size(), "a cell or more in every quarter")
	t.check(TownMapData.quarter_colour(1) != TownMapData.quarter_colour(2), "each quarter its own tint")
	var stopped := TownMapData.read(town, {"stop": true})
	t.check(stopped.is_empty(), "and it stops when asked")


func test_town_map(t) -> void:
	var town := _town(t)
	if town.is_empty():
		return
	CityTheme.apply(t.get_tree().root)
	var scene := Node.new()
	t.add_child(scene)
	var map := TownMap.new()
	scene.add_child(map)
	map.load_town(town, false)
	t.check(map.is_loaded() and map.data.ground.size() > 0, "the map is drawn")
	t.check(map._world.get_child_count() > map.data.ground.size(), "ground, quarters, water and roofs on it")
	var here := Vector3(map.data.box.get_center().x + 120.0, 5.0, map.data.box.get_center().y - 80.0)
	map.writer = func() -> Dictionary: return {"p": here, "dir": Vector3.RIGHT}
	t.check(not map.is_open(), "it starts shut")
	await _action(t, "map")
	t.check(map.is_open() and t.get_tree().paused and LGAudio.is_game_paused(), "Map opens it and holds the game")
	t.check(map.centre.is_equal_approx(Vector2(here.x, here.z)), "on the writer")
	t.check(map.to_screen(map.centre).is_equal_approx(map._size() * 0.5), "in the middle of the screen")
	t.check("M" in map.hint() or LGInput.is_gamepad(), "the bottom line names the key (%s)" % map.hint())
	# Looking round and zooming stay on the town.
	map.set_view(Vector2(-99999, 99999), 1.0)
	var box: Rect2 = map.data.box
	t.check(box.has_point(map.centre) or map.centre.x == box.position.x and map.centre.y == box.end.y, "looking is kept to the town")
	map.set_view(map.centre, 99.0)
	t.check(map.zoom == TownMap.ZOOM_MAX, "zoom has a most")
	map.set_view(map.centre, 0.0001)
	t.check(is_equal_approx(map.zoom, map.min_zoom()) and map.min_zoom() > 0.0, "and the whole town in the window is the least (%.3f)" % map.zoom)
	map.set_view(Vector2(here.x, here.z), 1.0)
	var spot := Vector2(300, 200)
	var under := map.to_map(spot)
	map.zoom_by(1.5, spot)
	t.check(map.zoom > 1.4 and map.to_map(spot).distance_to(under) < 0.01, "zooming keeps the spot under the mouse")
	await _action(t, "jump")
	t.check(map.centre.is_equal_approx(Vector2(here.x, here.z)), "Jump comes back to you")
	await _action(t, "map")
	t.check(not map.is_open() and not t.get_tree().paused and not LGAudio.is_game_paused(), "Map shuts it and lets go")
	map.can_open = func() -> bool: return false
	map.open()
	t.check(not map.is_open(), "it stays shut while the scene says so")
	map.can_open = Callable()
	map.open()
	await _action(t, "pause")
	t.check(not map.is_open() and not t.get_tree().paused, "Pause closes it")
	# The paint on the walls.
	var store := WallStore.new("map-test", 0, false)
	map.store = store
	var id: String = map.data.faces.keys()[5]
	var quarter := int(town.quarters[0].id)
	var kit := {"colours": ["3ff2ff", "ff4fa3"]}
	store.walls_in(quarter)[id] = {"writer": store.me(), "rank": "tag", "kit": kit, "grade": 90, "at": store.now()}
	store.walls_in(quarter)["no-such-wall"] = {"writer": "someone", "rank": "tag", "kit": kit, "grade": 90, "at": store.now()}
	var tags := map.tags()
	t.check(tags.size() == 1 and tags[0].mine and tags[0].p == map.data.faces[id], "your tag is on the map where its wall is")
	t.check(tags.size() == 1 and tags[0].colour.is_equal_approx(Color("3ff2ff")), "in its colour")
	store.walls_in(quarter)[id].writer = "someone-else"
	t.check(not map.tags()[0].mine, "and other writers' paint isn't yours")
	scene.free()
	t.get_tree().paused = false
	LGAudio.pause_game(false)


func test_map_threaded(t) -> void:
	var town := _town(t)
	if town.is_empty():
		return
	var scene := Node.new()
	t.add_child(scene)
	var map := TownMap.new()
	scene.add_child(map)
	map.load_town(town)
	t.check(not map.is_loaded(), "a map read on a worker isn't there at once")
	var deadline := Time.get_ticks_msec() + 60000
	while not map.is_loaded() and Time.get_ticks_msec() < deadline:
		await t.get_tree().process_frame
		OS.delay_msec(5)
	t.check(map.is_loaded(), "but comes up by itself")
	scene.free()
