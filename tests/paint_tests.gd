extends RefCounted
## Painting and the walls: finding the wall a writer faces, what's on the
## walls offline (going over, capping, the local Buff at dawn), the letter
## kit, the paint on the walls, and whole paintings run headless with a
## scripted stick.

const TOWN := "test-paint"
const STEP := 1.0 / 60.0

var _buffed := []
var _locks := []
var _lines := []
var _stored := []
var _done := []
var _stops := 0


## A building with its front on the street (z = 0, outside to +z, 10 m
## long) and the one across the street (z = 3, its outside to -z).
static func _street() -> Walls:
	var w := Walls.new()
	w.add({"id": "w0000a1", "a": Vector3(0, 0, 0), "b": Vector3(10, 0, 0), "base": 0.0, "top": 9.0, "paint": 2,
		"eyes": 40, "quarter": 12}, "tile_0_0")
	w.add({"id": "w0000b1", "a": Vector3(10, 0, 3), "b": Vector3(0, 0, 3), "base": 0.0, "top": 6.0, "paint": 1,
		"eyes": 20, "quarter": 12}, "tile_0_1")
	return w


func test_walls(t) -> void:
	var w := _street()
	t.check(w.size() == 2, "two faces")
	var hit := w.nearest(Vector3(5, 0, 1), 1.5)
	t.check(not hit.is_empty() and hit.face.id == "w0000a1", "the front is the nearest wall")
	t.check(is_equal_approx(hit.u, 5.0) and is_equal_approx(hit.distance, 1.0), "five metres along, a metre off")
	t.check(hit.normal.is_equal_approx(Vector3(0, 0, 1)), "its outside is +z")
	t.check(is_equal_approx(w.nearest(Vector3(5, 1.2, 1), 1.5).v, 1.2), "v is the height above the base")
	t.check(w.nearest(Vector3(5, 0, -1), 1.5).is_empty(), "nothing from inside a building")
	t.check(w.nearest(Vector3(5, 0, 1.4), 2.0).face.id == "w0000a1", "between the two, the nearer")
	t.check(w.nearest(Vector3(5, 0, 1.4), 2.0, Vector3(0, 0, 1)).face.id == "w0000b1", "or the one faced")
	t.check(w.nearest(Vector3(5, 0, 1.4), 2.0, Vector3(0, 0, -1)).face.id == "w0000a1", "either way")
	t.check(w.nearest(Vector3(5, 0, 1.4), 2.0, Vector3(1, 0, 0)).is_empty(), "nothing when looking along the street")
	t.check(w.nearest(Vector3(12, 0, 1), 1.5).is_empty(), "nothing past a face's end")
	t.check(is_equal_approx(Walls.paint_height(w.face("w0000a1")), 9.0), "a wall takes paint to its top")
	t.check(is_equal_approx(Walls.paint_height(w.face("w0000b1")), 3.0), "a shopfront under homes, the ground floor")
	# The respect list: found, so it can say so, but never painted.
	w.add({"id": "w0000c1", "a": Vector3(20, 0, 0), "b": Vector3(30, 0, 0), "base": 0.0, "top": 12.0, "paint": 0,
		"quarter": 12}, "tile_1_0")
	var church := w.nearest(Vector3(25, 0, 1), 1.5)
	t.check(not church.is_empty() and int(church.face.paint) == 0, "a respect wall is found")
	t.check(Walls.paint_height(church.face) == 0.0, "and takes no paint")
	# A face added again replaces itself.
	w.add({"id": "w0000c1", "a": Vector3(20, 0, 0), "b": Vector3(30, 0, 0), "base": 0.0, "top": 12.0, "paint": 0,
		"quarter": 12}, "tile_1_0")
	t.check(w.size() == 3, "the same face twice is one face")
	w.drop("tile_1_0")
	t.check(w.face("w0000c1").is_empty() and w.nearest(Vector3(25, 0, 1), 1.5).is_empty(), "dropping a tile drops its faces")
	t.check(w.size() == 2, "and only them")
	# A long face is found all along it.
	w.add({"id": "w0000d1", "a": Vector3(-40, 0, -20), "b": Vector3(20, 0, -50), "top": 6.0}, "tile_9")
	var along := Vector3(20, 0, -50) - Vector3(-40, 0, -20)
	var out := Vector3(-along.normalized().z, 0, along.normalized().x)
	var all_found := true
	for i in 13:
		var p := Vector3(-40, 0, -20) + along * (i / 12.0 * 0.98 + 0.01) + out * 0.8
		all_found = all_found and w.nearest(p, 1.0).get("face", {}).get("id", "") == "w0000d1"
	t.check(all_found, "a 67 m face is found from all along it")
	# Re-centring the origin moves every face.
	w.shift(Vector3(100, 2, -50))
	t.check(w.nearest(Vector3(5, 0, 1), 1.5).is_empty(), "after a shift the old spot is empty")
	var moved := w.nearest(Vector3(105, 2, -49), 1.5)
	t.check(not moved.is_empty() and moved.face.id == "w0000a1", "and the face is where it moved to")
	t.check(is_equal_approx(float(w.face("w0000a1").base), 2.0) and is_equal_approx(float(w.face("w0000a1").top), 11.0),
			"its base and top moved too")


func _on_buffed(quarter: int, walls: PackedStringArray) -> void:
	_buffed.append([quarter, Array(walls)])


func test_wall_store_offline(t) -> void:
	var store := WallStore.new(TOWN, 60, false)
	store.forget()
	store.buffed.connect(_on_buffed)
	_buffed.clear()
	# Saturday 22:00 UTC, 23:00 in town.
	store.fixed_now = Time.get_unix_time_from_datetime_string("2026-10-17T22:00:00")
	var face := {"id": "w1a2b3c", "quarter": 12, "paint": 2, "eyes": 40, "heaven": false}
	var tag := TagKit.kit_for("ana", "tag")
	var res: Dictionary = await store.paint(face, "tag", tag, 70, 3.5)
	t.check(res.ok and res.local, "a tag goes on offline")
	t.check(res.wall.writer == WallStore.LOCAL and res.wall.name == "ANA" and int(res.wall.at) == store.now(),
			"as this writer's, painted now")
	t.check(store.wall(12, "w1a2b3c").rank == "tag", "and it's on the wall")
	t.check(store.pending() == 1, "waiting to be sent")
	t.check((await store.paint(face, "tag", tag, 70, 1.0)).reason == "too_quick", "a tag takes two seconds")
	var church := {"id": "w0000c1", "quarter": 12, "paint": 0}
	t.check((await store.paint(church, "tag", tag, 70, 3.0)).reason == "respect", "the respect list takes nothing")
	# A rival's work, as the server would have sent it.
	var walls := store.walls_in(12)
	walls["w0000e1"] = {"writer": "rival", "name": "SALT", "rank": "tag", "kit": {}, "grade": 50, "eyes": 30,
		"heaven": false, "at": store.now() - 60, "capped": false}
	walls["w0000e2"] = {"writer": "rival", "name": "SALT", "rank": "piece", "kit": {}, "grade": 50, "eyes": 30,
		"heaven": false, "at": store.now() - 60, "capped": false}
	var e1 := {"id": "w0000e1", "quarter": 12, "paint": 2, "eyes": 30}
	var e2 := {"id": "w0000e2", "quarter": 12, "paint": 2, "eyes": 30}
	t.check((await store.paint(e1, "tag", tag, 70, 3.0)).reason == "rank", "a fresh tag holds against a tag")
	var over: Dictionary = await store.paint(e1, "throwup", TagKit.kit_for("ana", "throwup"), 60, 20.0)
	t.check(over.ok and not over.capped, "a throw-up goes over it")
	t.check((await store.paint(e2, "tag", tag, 70, 3.0)).reason == "rank", "a tag can't go over a piece")
	var capped: Dictionary = await store.paint(e2, "tag", tag, 70, 3.0, true)
	t.check(capped.ok and capped.capped, "unless it caps it")
	t.check((await store.paint(face, "tag", tag, 80, 3.0)).ok, "writers go over their own work")
	# The rest of the night: a burner and a heaven spot.
	var burner := {"id": "w0000a1", "quarter": 12, "paint": 2, "eyes": 95}
	var heaven := {"id": "w0000a2", "quarter": 12, "paint": 2, "eyes": 100, "heaven": true}
	t.check((await store.paint(burner, "burner", TagKit.kit_for("ana", "burner"), 90, 300.0)).ok, "a burner")
	t.check((await store.paint(heaven, "tag", tag, 90, 3.0)).ok, "a tag up high")
	# It's all kept: a new store for the town reads it back.
	var again := WallStore.new(TOWN, 60, false)
	again.fixed_now = store.fixed_now
	t.check(again.walls_in(12).size() == 5 and again.pending() == store.pending(), "the walls and the paint to send are kept")
	# Overnight: dawn in town is 05:00 UTC. With 8 to spend the Buff takes the
	# three tags (the heaven spot is out of reach) and the throw-up, and can't
	# afford the burner.
	var evening := store.fixed_now
	store.fixed_now = Time.get_unix_time_from_datetime_string("2026-10-18T09:00:00")
	var morning: Dictionary = await store.read_quarter(12)
	t.check(morning.keys().has("w0000a1") and morning.keys().has("w0000a2") and morning.size() == 2,
			"the burner and the heaven spot are left")
	t.check(_buffed.size() == 1 and _buffed[0][0] == 12, "the Buff's round is told once")
	var took: Array = _buffed[0][1] if not _buffed.is_empty() else []
	took.sort()
	t.check(took == ["w0000e1", "w0000e2", "w1a2b3c"], "naming the walls it took")
	t.check(store.wall(12, "w1a2b3c").is_empty(), "a buffed wall is bare")
	await store.read_quarter(12)
	t.check(_buffed.size() == 1, "and it's told once")
	store.fixed_now += 86400
	await store.read_quarter(12)
	t.check(store.walls_in(12).keys() == ["w0000a2"], "the burner goes the next morning; the heaven spot stays")
	t.check(evening < store.fixed_now, "the clock moved on")
	t.check((await store.paint(face, "tag", tag, 70, 2.0)).ok, "and the bare wall takes a tag")
	store.forget()
	t.check(not FileAccess.file_exists(WallStore.path_for(TOWN)), "forgetting a town deletes its record")
	# Online, a copy that only painted in a quarter gets no Buff list from the
	# server (it never read it), so its own Buff tells it; a wall the server
	# still has wasn't taken.
	var before := PackedStringArray(["wa", "wb", "wc"])
	t.check(WallStore.taken_by_buff(before, PackedStringArray(["wa"]), PackedStringArray(), {}) == PackedStringArray(["wa"]),
			"the painter hears it from its own Buff")
	t.check(WallStore.taken_by_buff(before, PackedStringArray(["wa", "wb"]), PackedStringArray(["wb", "wz"]), {"wa": {}})
			== PackedStringArray(["wb"]), "the server's list counts, walls it still has and walls never seen don't")


func test_tag_kit(t) -> void:
	t.check(TagKit.clean_name("ana!") == "ANA", "names are capitals")
	t.check(TagKit.clean_name("x") == "", "two letters at least")
	t.check(TagKit.clean_name("salt water") == "SALTWA", "six at most")
	var kit := TagKit.kit_for("Salt", "tag", [Color("ff4fa3")])
	t.check(kit.name == "SALT" and kit.style == "handstyle" and kit.colours[0] == "ff4fa3", "a tag's kit")
	t.check(kit.drips.size() == 2, "a tag comes with a couple of drips")
	t.check(JSON.stringify(kit).to_utf8_buffer().size() < 2048, "a kit fits the server's 2 KB")
	t.check(TagKit.kit_for("", "tag").name == TagKit.UNNAMED, "a writer with no name paints as a toy")
	var art := TagKit.art(kit)
	t.check(art.fill is ImageTexture and art.ink is ImageTexture, "the kit draws textures")
	var fill: Image = art.fill_image
	var ink: Image = art.ink_image
	t.check(fill.get_width() > fill.get_height() and fill.get_height() > 100, "wider than tall")
	var painted := _coverage(fill)
	var outlined := _coverage(ink)
	t.check(painted > 0.08 and painted < 0.7, "the letters are painted (%.2f of it)" % painted)
	t.check(outlined > painted, "and outlined")
	t.check(is_same(TagKit.art(kit), art), "a drawing is made once")
	var guide: PackedVector2Array = art.guide
	var inside := guide.size() >= 8
	for p in guide:
		inside = inside and p.x > 0.0 and p.x < 1.0 and p.y > 0.0 and p.y < 1.0
	t.check(inside, "the guide runs through the letters")
	var throwup := TagKit.art(TagKit.kit_for("salt", "throwup"))
	t.check(_coverage(throwup.fill_image) > painted, "a throw-up's bubble letters fill more")


## The share of an L8 mask that's painted, on a coarse grid.
static func _coverage(img: Image) -> float:
	var hit := 0
	var all := 0
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			all += 1
			if img.get_pixel(x, y).r > 0.5:
				hit += 1
	return float(hit) / maxf(all, 1)


func _on_lock(on: bool) -> void:
	_locks.append(on)


func _on_line(text: String) -> void:
	_lines.append(text)


func _on_stored(result: Dictionary) -> void:
	_stored.append(result)


func _on_finished(result: Dictionary) -> void:
	_done.append(result)


func _on_stopped() -> void:
	_stops += 1


## A writer at the front of the street building, facing it.
static func _writer(t, x := 5.0, z := 0.8) -> Node3D:
	var writer := Node3D.new()
	t.add_child(writer)
	writer.global_position = Vector3(x, 0, z)
	writer.rotation.y = PI
	return writer


## Runs a painting to its end: the stick pushed at `tilt` along the guide,
## and let go for `pauses` (progress at which to wait, and for how long).
static func _paint(action: PaintAction, tilt: float, pauses := {}) -> void:
	var waited := {}
	for i in 60 * 60:
		var input := PaintInput.make(true)
		if action.is_painting():
			input.stick = action.guide_direction() * tilt
			for at in pauses:
				if action.progress() >= at and float(waited.get(at, 0.0)) < float(pauses[at]):
					input.stick = Vector2.ZERO
					waited[at] = float(waited.get(at, 0.0)) + STEP
		action.step(input, STEP)
		if action.state == PaintAction.State.DONE:
			return


func test_paint_action(t) -> void:
	var walls := _street()
	var writer := _writer(t)
	_locks.clear()
	var action := PaintAction.new(walls, writer, _on_lock)
	action.writer_name = "SALT"
	action.colours = [Color("3ff2ff")]
	_done.clear()
	var done := _done
	action.finished.connect(_on_finished)
	_paint(action, 0.8)
	t.check(done.size() == 1, "a tag is painted")
	var result: Dictionary = done[0] if not done.is_empty() else {}
	t.check(_locks == [true, false], "the writer is held still while painting, then let go")
	t.check(result.get("face", {}).get("id", "") == "w0000a1", "on the wall faced")
	t.check(float(result.get("seconds", 0)) >= PaintRules.MIN_SECONDS.tag, "taking at least a tag's two seconds")
	t.check(float(result.get("seconds", 0)) < 4.0, "and not much more at the guide's pace")
	t.check(int(result.get("grade", 0)) >= PaintAction.CLEAN and result.get("label") == "Clean",
			"following the guide at its pace is Clean (%d)" % result.get("grade", 0))
	var kit: Dictionary = result.get("kit", {})
	t.check(kit.get("at", []).size() == 2 and is_equal_approx(float(kit.at[1]), PaintAction.ARM), "at arm's height")
	t.check(kit.get("colours", [""])[0] == "3ff2ff", "in the writer's colour")
	t.check(TagKit.kit_for("salt", "tag").drips.size() == kit.drips.size(), "no drips but the tag's own")
	# Full tilt round the corners: the outline wobbles.
	action.step(PaintInput.make(false), STEP)
	done.clear()
	_paint(action, 1.0)
	t.check(done.size() == 1 and int(done[0].grade) < int(result.grade) and float(done[0].kit.wobble) > 0.0,
			"rushing wobbles (%d)" % (done[0].grade if not done.is_empty() else -1))
	# Hesitating: the paint runs.
	action.step(PaintInput.make(false), STEP)
	done.clear()
	_paint(action, 0.8, {0.2: 1.5, 0.45: 1.5, 0.7: 1.5, 0.9: 1.5})
	t.check(done.size() == 1 and done[0].label == "Drippy", "stopping and starting is Drippy")
	t.check(done.size() == 1 and done[0].kit.drips.size() == 6, "with a drip for each wait")
	# Letting go drops it.
	action.step(PaintInput.make(false), STEP)
	_locks.clear()
	_stops = 0
	action.stopped.connect(_on_stopped)
	for i in 30:
		action.step(PaintInput.make(true, action.guide_direction() * 0.8), STEP)
	for i in 30:
		action.step(PaintInput.make(false), STEP)
	t.check(_stops == 1 and action.state == PaintAction.State.IDLE and _locks == [true, false],
			"letting go stops the painting and frees the writer")
	writer.queue_free()


func test_not_here(t) -> void:
	var walls := Walls.new()
	walls.add({"id": "w0000c1", "a": Vector3(0, 0, 0), "b": Vector3(10, 0, 0), "base": 0.0, "top": 12.0, "paint": 0,
		"quarter": 12})
	var writer := _writer(t)
	_locks.clear()
	_lines.clear()
	var action := PaintAction.new(walls, writer, _on_lock)
	action.line_changed.connect(_on_line)
	for i in 10:
		action.step(PaintInput.make(true, Vector2.RIGHT), STEP)
	t.check(action.line == "Not here" and _lines == ["Not here"], "a respect wall says Not here, once")
	t.check(action.state == PaintAction.State.IDLE and _locks.is_empty(), "and nothing starts")
	action.step(PaintInput.make(false), STEP)
	t.check(action.line == "", "letting go clears it")
	writer.global_position = Vector3(5, 0, 6)
	action.step(PaintInput.make(true), STEP)
	t.check(action.line == "" and action.state == PaintAction.State.IDLE, "away from walls, paint does nothing")
	# Too high up a ground-floor-only face.
	walls.add({"id": "w0000c2", "a": Vector3(0, 0, 20), "b": Vector3(10, 0, 20), "base": 0.0, "top": 9.0, "paint": 1,
		"quarter": 12})
	writer.global_position = Vector3(5, 4.5, 20.8)
	action.step(PaintInput.make(false), STEP)
	action.step(PaintInput.make(true), STEP)
	t.check(action.line == "Out of reach" and action.state == PaintAction.State.IDLE, "a shopfront from a balcony is out of reach")
	writer.queue_free()


func test_paint_layer(t) -> void:
	var walls := _street()
	var layer := PaintLayer.new(walls)
	t.add_child(layer)
	var now := Time.get_unix_time_from_datetime_string("2026-10-17T22:00:00")
	var kit := TagKit.kit_for("salt", "tag")
	kit.at = [4.0, 1.5]
	var rec := {"writer": "a", "name": "SALT", "rank": "tag", "kit": kit, "grade": 80, "eyes": 40, "heaven": false,
		"at": now - 60, "capped": false}
	var quad := layer.show_paint("w0000a1", rec, now)
	t.check(quad != null and quad.material_override is ShaderMaterial, "paint shows as a quad with the paint shader")
	var at := quad.global_position if quad else Vector3.ZERO
	t.check(at.is_equal_approx(Vector3(4.0, 1.5, PaintLayer.LIFT)), "centred where it was painted, just off the wall")
	t.check(quad != null and quad.global_basis.z.normalized().is_equal_approx(Vector3(0, 0, 1)), "facing out")
	var h := float(kit.h)
	t.check(quad != null and is_equal_approx(quad.global_basis.y.length(), h), "as tall as the kit says")
	t.check(layer.show_paint("w0000zz", rec, now) == null, "nothing on a wall that isn't loaded")
	t.check(layer.show_paint("w0000b1", rec, now + 4 * 86400) == null, "nor faded paint")
	var mat: ShaderMaterial = quad.material_override if quad else ShaderMaterial.new()
	t.check(float(mat.get_shader_parameter("fade")) > 0.0 and float(mat.get_shader_parameter("fade")) < 0.01,
			"a minute-old tag has hardly faded")
	layer.refresh(now + 2 * 86400)
	t.check(is_equal_approx(float(mat.get_shader_parameter("fade")), (2 * 86400 + 60) / float(PaintRules.LIFE.tag)),
			"two days on it's faded by its age")
	layer.refresh(now + 4 * 86400)
	t.check(layer.shown().is_empty(), "and gone when its life is over")
	layer.show_quarter(12, {"w0000a1": rec, "w0000b1": rec}, now)
	t.check(layer.shown().size() == 2, "a quarter's walls show")
	layer.show_quarter(12, {"w0000b1": rec}, now)
	t.check(Array(layer.shown()) == ["w0000b1"], "and paint gone from them goes")
	layer.shift(Vector3(10, 0, 0))
	walls.shift(Vector3(10, 0, 0))
	var moved: MeshInstance3D = layer.get_node("w0000b1")
	t.check(moved != null and is_equal_approx(moved.position.x, 10.0 - 4.0 + 10.0), "re-centring moves the paint")
	layer.queue_free()


func test_painting_to_the_store(t) -> void:
	var walls := _street()
	var writer := _writer(t)
	var layer := PaintLayer.new(walls)
	t.add_child(layer)
	var store := WallStore.new(TOWN, 0, false)
	store.forget()
	var action := PaintAction.new(walls, writer, Callable(), layer, store)
	action.writer_name = "NITE"
	_stored.clear()
	action.stored.connect(_on_stored)
	action.step(PaintInput.make(true, Vector2.ZERO), STEP)
	t.check(layer.preview() != null, "the guide shows on the wall while painting")
	_paint(action, 0.8)
	t.check(_stored.size() == 1 and _stored[0].ok, "the finished tag goes to the walls")
	t.check(store.wall(12, "w0000a1").get("name", "") == "NITE", "and is on the record")
	t.check(Array(layer.shown()) == ["w0000a1"] and layer.preview() == null, "and on the wall")
	# Another writer can't go over it with a tag while it's fresh.
	store.walls_in(12)["w0000a1"].writer = "someone"
	_lines.clear()
	action.line_changed.connect(_on_line)
	action.step(PaintInput.make(false), STEP)
	action.step(PaintInput.make(true), STEP)
	t.check(action.line == "Too fresh to go over" and not action.is_painting(), "fresh paint holds against a tag")
	store.forget()
	layer.queue_free()
	writer.queue_free()
