extends Node
## Plays a town's play scene by itself to check M0's claims in the real
## town: the skater skates up the staircase at the spawn, grinds its
## handrail down, climbs the nearest way up to a roof, paints a tag and then
## travels three tiles out, so the town streams round them and moves back
## round the origin. Prints what it found and how long things took, and
## with --shots saves a picture of each.
##
##   godot --headless --path . tools/play_check.tscn -- --town=monaco
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x800x24" \
##       godot --path . --resolution 1280x800 tools/play_check.tscn -- --town=monaco --shots=/tmp/play
##
## Exits 0 when every step did what it should, 1 otherwise.

const PLAY := "res://game/play/play.tscn"
const TICK := 1.0 / 60.0

var play: Node3D
var _opts := {}
var _shots := ""
var _fails: Array[String] = []
var _step := "start"
var _drive := Callable()
var _worst_frame := 0.0
var _frames := 0
var _frame_total := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			_opts[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	_shots = str(_opts.get("shots", ""))
	var only := PackedStringArray()
	if _opts.has("only"):
		only = str(_opts.only).split(",")
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	LGInput.register_actions(GameConfig.ACTIONS)
	# The walls stay on this copy for a check: nothing goes to the server.
	LGSettings.set_value("online", "enabled", false, false)
	if LGSettings.get_value("player", "tag", "") == "":
		LGSettings.set_value("player", "tag", "MOTH", false)
	Towns.current = Towns.find(str(_opts.get("town", "monaco"))).duplicate()
	if Towns.current.is_empty():
		_fail("no town called %s" % _opts.get("town", "monaco"))
		_finish()
		return
	# Under its own id, so a player's walls in the town are never touched.
	Towns.current.id = "play-check"
	var t0 := Time.get_ticks_msec()
	play = (load(PLAY) as PackedScene).instantiate()
	add_child(play)
	await play.ready_to_play
	print("play_check: %s up in %d ms (%d tiles, %d near)" % [Towns.current.name, Time.get_ticks_msec() - t0,
		play.view.tiles.size(), _near_count()])
	play.skater.reads_controls = false
	await _settle(30)
	_worst_frame = 0.0
	await _shot("spawn")
	for step in ["skate", "grind", "coping", "climb", "paint", "travel"]:
		if only.is_empty() or step in only:
			await call("_" + step if step != "coping" else "_grind_coping")
	_finish()


func _physics_process(_delta: float) -> void:
	if play and play.is_playing() and _drive.is_valid():
		play.skater.input.clear()
		_drive.call(play.skater.input)


func _process(delta: float) -> void:
	if play and play.is_playing():
		_frames += 1
		_frame_total += delta
		_worst_frame = maxf(_worst_frame, delta)
		if delta > 0.05 and _opts.has("spikes"):
			print("play_check:   %.0f ms frame during %s (origin %s, %d tiles)" % [delta * 1000.0, _step, play.view.origin,
				play.view.tiles.size()])


func _near_count() -> int:
	var n := 0
	for k in play.view.shown():
		n += 1 if play.view.shown()[k] else 0
	return n


# --- The steps ------------------------------------------------------------------

## Up the staircase the town starts at.
func _skate() -> void:
	_step = "skate"
	var sk: Skater = play.skater
	var from := sk.global_position
	var up := sk.facing
	_drive = func(inp: SkaterInput) -> void: inp.move = up
	await _ticks(240)
	_drive = Callable()
	var rise := sk.global_position.y - from.y
	print("play_check: skated %.1f m and rose %.1f m (%s)" % [_flat(sk.global_position - from).length(), rise,
		sk.state_name()])
	_check(_flat(sk.global_position - from).length() > 5.0, "the skater skates from the spawn")
	await _shot("skate")


## Down the nearest handrail.
func _grind() -> void:
	_step = "grind"
	var sk: Skater = play.skater
	var lines: Lines = play.view.lines
	var spawn_at: Vector3 = play.view.spawn().p
	var best := -1
	var best_len := 0.0
	for id in lines.ids():
		var l: Dictionary = lines.line(id)
		if l.kind != Lines.Kind.HANDRAIL or (l.pts[0] as Vector3).distance_to(spawn_at) > 150.0:
			continue
		if lines.length(id) > best_len:
			best = id
			best_len = lines.length(id)
	if not _check(best >= 0, "there's a handrail within 150 m of the spawn"):
		return
	var hit := {"id": best}
	var pts: PackedVector3Array = lines.line(best).pts
	var top := pts[0] if pts[0].y > pts[pts.size() - 1].y else pts[pts.size() - 1]
	var at := lines.nearest(top, 0.5, [Lines.Kind.HANDRAIL])
	var down := 1 if (at.tangent as Vector3).y < 0.0 else -1
	sk.place(at.point + Vector3.UP * 0.05, _flat(at.tangent * down))
	sk.start_grind(at, down, 6.5)
	play.cam.snap()
	var ground := 0
	_drive = func(inp: SkaterInput) -> void: inp.grind = true
	for i in 300:
		await get_tree().physics_frame
		ground += 1 if sk.state == Skater.State.GRIND else 0
		if ground == 25:
			await _shot("grind")
		if sk.state != Skater.State.GRIND and ground > 0:
			break
	_drive = Callable()
	var length := lines.length(hit.id)
	print("play_check: ground %.2f s of a %.1f m handrail" % [ground * TICK, length])
	_check(ground * TICK > 0.3, "the skater grinds the real handrail")
	await _ticks(60)


## Down the coping of the staircase the town starts at: the longest grind
## in the picture.
func _grind_coping() -> void:
	_step = "coping"
	var sk: Skater = play.skater
	var lines: Lines = play.view.lines
	var near := lines.nearest(play.view.spawn().p, 30.0, [Lines.Kind.COPING])
	if not _check(not near.is_empty(), "the staircase at the spawn has copings to grind"):
		return
	var pts: PackedVector3Array = lines.line(near.id).pts
	var top := pts[0] if pts[0].y > pts[pts.size() - 1].y else pts[pts.size() - 1]
	var at := lines.nearest(top, 0.5, [Lines.Kind.COPING])
	var down := 1 if (at.tangent as Vector3).y < 0.0 else -1
	sk.place(at.point + Vector3.UP * 0.05, _flat(at.tangent * down))
	sk.start_grind(at, down, 7.0)
	play.cam.snap()
	var ground := 0
	_drive = func(inp: SkaterInput) -> void: inp.grind = true
	for i in 900:
		await get_tree().physics_frame
		ground += 1 if sk.state == Skater.State.GRIND else 0
		if ground == 60:
			await _shot("coping")
		if sk.state != Skater.State.GRIND and ground > 0:
			break
	_drive = Callable()
	print("play_check: ground %.1f s down a %.0f m coping (left it by %s)" % [ground * TICK, lines.length(near.id),
		sk.state_name()])
	_check(ground * TICK > 1.0, "the skater grinds the staircase's coping")
	await _ticks(60)


## Up the nearest drainpipe or fire escape, onto the roof.
func _climb() -> void:
	_step = "climb"
	var sk: Skater = play.skater
	var lines: Lines = play.view.lines
	var hit := lines.nearest(play.view.spawn().p, 120.0, [Lines.Kind.CLIMB])
	if not _check(not hit.is_empty(), "there's a way up near the spawn"):
		return
	var pts: PackedVector3Array = lines.line(hit.id).pts
	var base := pts[0] if pts[0].y <= pts[pts.size() - 1].y else pts[pts.size() - 1]
	var top := pts[pts.size() - 1] if pts[0].y <= pts[pts.size() - 1].y else pts[0]
	# Stand a step out from the wall it's on and push at it.
	var out := _wall_out(base)
	var stand := base + out * 0.9
	stand.y = _ground_at(Vector3(stand.x, base.y + 6.0, stand.z), 0.0) + 0.1
	sk.place(stand, -out)
	play.cam.snap()
	await _ticks(10)
	var climbed := false
	var topped := false
	_drive = func(inp: SkaterInput) -> void:
		inp.move = -out * 0.6
		inp.stick = Vector2(0, 1)
	var last := ""
	for i in 1200:
		await get_tree().physics_frame
		if sk.state_name() != last:
			last = sk.state_name()
			print("play_check:   tick %d %s at %s" % [i, last, sk.global_position])
		if sk.state == Skater.State.CLIMB:
			if not climbed and sk.global_position.y > base.y + 3.0:
				await _shot("climb")
			climbed = true
		elif climbed and sk.state == Skater.State.SKATE and sk.global_position.y > top.y - 2.5:
			topped = true
			break
	_drive = Callable()
	print("play_check: climbed %.1f m up (%s at %.1f, roof edge %.1f)" % [top.y - base.y, sk.state_name(),
		sk.global_position.y, top.y])
	_check(climbed, "the skater climbs a real building")
	_check(topped, "and gets onto its roof")
	await _ticks(40)
	if topped:
		await _shot("roof")


## A tag on the nearest wall that takes paint.
func _paint() -> void:
	_step = "paint"
	var sk: Skater = play.skater
	var walls: Walls = play.view.walls
	var near := play.view.spawn().p as Vector3
	var best := {}
	var best_d := INF
	for id in walls._near_ids(near, 60.0):
		var f: Dictionary = walls.face(id)
		if int(f.paint) != Walls.ALL or Vector2(f.b.x - f.a.x, f.b.z - f.a.z).length() < 4.0:
			continue
		var d := near.distance_to((f.a + f.b) * 0.5)
		if d < best_d:
			best_d = d
			best = f
	if not _check(not best.is_empty(), "there's a wall to paint near the spawn"):
		return
	var along: Vector3 = (best.b - best.a)
	var out := along.cross(Vector3.UP).normalized()
	var mid: Vector3 = (best.a + best.b) * 0.5
	sk.place(Vector3(mid.x, float(best.base) + 0.3, mid.z) + out * 0.8 - along.normalized() * 0.3, -out)
	play.cam.snap()
	await _ticks(40)
	var action: PaintAction = play.action
	var t0 := Time.get_ticks_msec()
	var mid_shot := false
	for i in 1200:
		play.paint_override = PaintInput.make(true, action.guide_direction() * 0.8)
		await get_tree().physics_frame
		if action.is_painting() and not mid_shot and action.progress() > 0.5:
			mid_shot = true
			await _shot("painting")
		if action.state == PaintAction.State.DONE:
			break
	play.paint_override = PaintInput.make(false)
	await _ticks(30)
	play.paint_override = null
	var stored: Dictionary = play.store.wall(int(best.quarter), str(best.id))
	print("play_check: painted %s on %s (%s, %.1f s), shown: %s" % [action.writer_name, best.id, action.grade,
		(Time.get_ticks_msec() - t0) / 1000.0, play.layer.shown().has(str(best.id))])
	_check(not stored.is_empty(), "the tag is on the wall's record")
	_check(play.layer.shown().has(str(best.id)), "and on the wall")
	# Step back to look at it.
	sk.place(Vector3(mid.x, float(best.base) + 0.3, mid.z) + out * 3.5, -out)
	play.cam.snap()
	await _ticks(90)
	await _shot("tag")


## Three tiles east (or as far as the town goes): the town streams round
## the writer and moves back round the origin.
func _travel() -> void:
	_step = "travel"
	var sk: Skater = play.skater
	var view: TownView = play.view
	var start := view.to_town(sk.global_position)
	var target := start
	var town_box: Array = view.town.get("box", [0, 0, 0, 0])
	for dx in [768.0, -768.0, 512.0, -512.0]:
		var p := start + Vector3(dx, 0, 0)
		if p.x > float(town_box[0]) + 64.0 and p.x < float(town_box[2]) - 64.0:
			target = p
			break
	var origin_before := view.origin
	var worst_before := _worst_frame
	_worst_frame = 0.0
	# Hop a tile at a time, as fast as a writer can't, letting it stream.
	var steps := int(absf(target.x - start.x) / 64.0)
	var t0 := Time.get_ticks_msec()
	for i in steps:
		var at := view.from_town(start.lerp(target, float(i + 1) / steps))
		at.y = _ground_at(at) + 0.3
		sk.place(at, Vector3.RIGHT)
		play.cam.snap()
		await _ticks(20)
	for i in 1200:
		if view.settled():
			break
		await get_tree().process_frame
	print("play_check: travelled %.0f m in %.1f s; origin %s -> %s; %d tiles, %d near, %d lines, %d walls, %d cars" % [
		absf(target.x - start.x), (Time.get_ticks_msec() - t0) / 1000.0, origin_before, view.origin, view.tiles.size(),
		_near_count(), view.lines.count(), view.walls.size(), view.traffic.car_count()])
	print("play_check: slowest frame %.0f ms on the way (%.0f ms before), mean %.1f ms over %d frames" % [
		_worst_frame * 1000.0, worst_before * 1000.0, _frame_total / maxf(_frames, 1) * 1000.0, _frames])
	_check(view.origin != origin_before, "the world moves back round the writer")
	_check(view.settled() and view.shown().get(view.key_at(sk.global_position), false), "the town streams in round them")
	_check(absf(sk.global_position.x) <= TownView.RECENTRE + 64.0, "the writer stays near the scene's origin")
	await _ticks(30)
	await _shot("far")


# --- Helpers --------------------------------------------------------------------

## The way out from the wall a way up is on (flat): the outside of the
## nearest paintable face, as the town's walls say.
func _wall_out(p: Vector3) -> Vector3:
	var hit: Dictionary = play.view.walls.nearest(p + Vector3.UP * 1.0, 2.5)
	if hit.is_empty():
		return Vector3.BACK
	return _flat(hit.normal).normalized()


## The ground's height under `p`, looking down from `above` metres over it.
func _ground_at(p: Vector3, above := 400.0) -> float:
	var space: PhysicsDirectSpaceState3D = play.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * above, p - Vector3.UP * 400.0,
			Kit.LAYER_WORLD))
	return hit.position.y if not hit.is_empty() else p.y


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _settle(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	if _shots == "" or DisplayServer.get_name() == "headless":
		return
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_shots)
	var path := _shots.path_join(shot_name + ".png")
	img.save_png(path)
	print("play_check: ", path)


func _check(ok: bool, what: String) -> bool:
	print("play_check: %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fail(what)
	return ok


func _fail(what: String) -> void:
	_fails.append(what)


func _finish() -> void:
	if play and play.store:
		play.store.forget()
	print("play_check: %s" % ("all good" if _fails.is_empty() else "%d failed: %s" % [_fails.size(), ", ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)
