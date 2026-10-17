extends RefCounted
## The HUD, and a night in Monaco: the play scene comes up with the town
## round the skater, the skater stands on solid ground in a named quarter,
## skates, and a tag painted at a wall is on the wall's record and shown.
## (tools/play_check.tscn plays the rest of it: the rail, the roof, the
## walk across the town.)

const DT := 1.0 / 60.0


func test_hud(t) -> void:
	var hud := PlayHud.new()
	t.add_child(hud)
	var skater := Skater.new()
	skater.visuals = false
	t.add_child(skater)
	skater.flow = 0.6
	skater.line_count = 3
	var events: Array[Dictionary] = [{"kind": "wall_ride"}, {"kind": "grind_start", "line_kind": Lines.Kind.HANDRAIL},
		{"kind": "jump"}]
	hud.show_skater(skater, events)
	hud.step(0.1)
	t.check(is_equal_approx(hud.flow.value, 0.6), "the HUD shows Flow")
	t.check(hud.line_label.text == "LINE x3", "and the line")
	t.check("Wall ride" in hud.moves.text and "Handrail grind" in hud.moves.text, "and the moves just made")
	t.check(not "Jump" in hud.moves.text, "but not every event")
	hud.step(PlayHud.MOVE_SECONDS + 0.1)
	t.check(hud.moves.text == "", "the moves clear after a moment")
	hud.show_quarter(7, "Condamine")
	hud.step(0.1)
	t.check(hud.quarter.visible and hud.quarter.text == "CONDAMINE", "a new quarter's name shows big")
	t.check(hud.quarter_small.text == "Condamine", "and stays as a small line")
	hud.step(PlayHud.QUARTER_SECONDS + 0.5)
	t.check(not hud.quarter.visible, "the big name goes")
	hud.say("Clean")
	t.check(hud.paint_line.text == "Clean", "the paint's line shows")
	hud.step(4.0)
	t.check(hud.paint_line.text == "", "and goes by itself")
	hud.queue_free()
	skater.queue_free()


func test_play_scene(t) -> void:
	var town := Towns.find("monaco")
	t.check(not town.is_empty(), "Monaco comes with the game")
	if town.is_empty():
		return
	# The walls stay on this copy for a test.
	LGSettings.set_value("online", "enabled", false, false)
	LGSettings.set_value("player", "tag", "TEST", false)
	# Under its own id, so a player's walls in Monaco are never touched.
	town = town.duplicate()
	town.id = "play-test"
	Towns.current = town
	var play: Node3D = (load(Towns.PLAY_SCENE) as PackedScene).instantiate()
	t.add_child(play)
	await play.ready_to_play
	var sk: Skater = play.skater
	t.check(play.is_playing() and sk != null, "the play scene comes up")
	t.check(play.view.walls.size() > 100 and play.view.lines.count() > 100, "with the town's lines and walls round it")
	sk.reads_controls = false
	for i in 30:
		await t.get_tree().physics_frame
	t.check(sk.state == Skater.State.SKATE, "the skater stands on the ground (%s)" % sk.state_name())
	var quarter: int = play.view.quarter_at(sk.position)
	t.check(quarter >= 0 and play.view.quarter_name(quarter) != "", "in a named quarter (%d, %s)" % [quarter,
			play.view.quarter_name(quarter)])
	var from := sk.global_position
	for i in 180:
		sk.input.clear()
		sk.input.move = sk.facing
		await t.get_tree().physics_frame
	t.check(Vector2(sk.global_position.x - from.x, sk.global_position.z - from.z).length() > 2.0, "and skates")
	# A tag at the nearest wall that takes paint.
	var walls: Walls = play.view.walls
	var best := {}
	var best_d := INF
	for id in walls._near_ids(sk.global_position, 60.0):
		var f: Dictionary = walls.face(id)
		var d := sk.global_position.distance_to((f.a + f.b) * 0.5)
		if int(f.paint) == Walls.ALL and Vector2(f.b.x - f.a.x, f.b.z - f.a.z).length() >= 4.0 and d < best_d:
			best_d = d
			best = f
	t.check(not best.is_empty(), "there's a wall to paint close by")
	if not best.is_empty():
		var along: Vector3 = best.b - best.a
		var out := along.cross(Vector3.UP).normalized()
		var mid: Vector3 = (best.a + best.b) * 0.5
		sk.place(Vector3(mid.x, float(best.base) + 0.3, mid.z) + out * 0.8, -out)
		for i in 40:
			await t.get_tree().physics_frame
		var action: PaintAction = play.action
		for i in 900:
			play.paint_override = PaintInput.make(true, action.guide_direction() * 0.8)
			await t.get_tree().physics_frame
			if action.state == PaintAction.State.DONE:
				break
		play.paint_override = null
		t.check(action.state == PaintAction.State.DONE, "a tag gets painted")
		for i in 5:
			await t.get_tree().physics_frame
		t.check(not play.store.wall(int(best.quarter), str(best.id)).is_empty(), "and goes on the wall's record")
		t.check(play.layer.shown().has(str(best.id)), "and shows on the wall")
	play.store.forget()
	play.queue_free()
	await t.get_tree().process_frame
