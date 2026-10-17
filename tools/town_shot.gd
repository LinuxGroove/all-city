extends Node3D
## Pictures of a built town in the game's look, streamed as the game
## streams it, and the numbers M0 measures (tile build times, what the
## near tiles hold).
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 tools/town_shot.tscn -- \
##       --town=monaco --out=/tmp/town.png [--view=spawn|air|street] [--at=x,z] [--yaw=deg] [--time=dusk]
##
## --town is a town's id or its folder. "spawn" stands where a writer
## starts, "air" looks over the town from above it, and "street" stands at
## --at (town metres) facing --yaw. --views=a,b,c shoots several into the
## --out folder.

var _opts := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			_opts[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	var id := str(_opts.get("town", "monaco"))
	var town := Towns.read(id) if id.contains("/") else Towns.find(id)
	if town.is_empty():
		printerr("town_shot: no town ", id)
		get_tree().quit(1)
		return
	Look.dress(self, str(_opts.get("time", "dusk")))
	var view := TownView.new()
	add_child(view)
	view.open(town, int(_opts.get("detail", "1")))
	var views := str(_opts.get("views", _opts.get("view", "spawn"))).split(",")
	var out := str(_opts.get("out", "/tmp/town.png"))
	var cam := Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.fov = 70.0
	cam.far = 1400.0
	add_child(cam)
	cam.current = true
	for v in views:
		var where := _where(view, v)
		var t0 := Time.get_ticks_msec()
		view.load_around(where.p)
		var near_ms := Time.get_ticks_msec() - t0
		while not view.settled():
			view.follow(where.p)
			await get_tree().process_frame
		var all_ms := Time.get_ticks_msec() - t0
		cam.global_transform = where.xf
		for i in 30:
			await get_tree().physics_frame
		var path := out if views.size() == 1 else out.path_join(v + ".png")
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		get_viewport().get_texture().get_image().save_png(path)
		var near := 0
		for k in view.shown():
			near += 1 if view.shown()[k] else 0
		print("town_shot: %s  near tiles in %d ms, all %d tiles in %d ms; %d near; tile builds %s ms; %d lines, %d walls, %d lanes, %d cars" % [
			path, near_ms, view.tiles.size(), all_ms, near, _stats(view.timings()), view.lines.count(),
			view.walls.size(), view.traffic.lane_count(), view.traffic.car_count()])
	get_tree().quit()


## Where to stand: {"p" (the scene's point to stream round), "xf" (the camera)}.
func _where(view: TownView, v: String) -> Dictionary:
	var s := view.spawn()
	var p: Vector3 = s.p
	var yaw: float = s.yaw
	if _opts.has("at"):
		var xz := str(_opts.at).split(",")
		p = view.from_town(Vector3(float(xz[0]), 0.0, float(xz[1])))
		p.y = _ground(view, p)
	if _opts.has("yaw"):
		yaw = deg_to_rad(float(_opts.yaw))
	var basis := Basis(Vector3.UP, yaw)
	match v:
		"air":
			var eye := p + basis.z * 120.0 + Vector3.UP * 110.0
			return {"p": p, "xf": Transform3D(Basis.looking_at(p - eye), eye)}
		"street":
			var eye := p + Vector3.UP * 1.7
			return {"p": p, "xf": Transform3D(basis * Basis(Vector3.RIGHT, deg_to_rad(-4.0)), eye)}
		_:
			# Behind a writer at the foot of the steps, as the street camera sits.
			var eye := p + basis.z * 4.5 + Vector3.UP * 2.6
			var look := p - basis.z * 6.0 + Vector3.UP * 1.6
			return {"p": p, "xf": Transform3D(Basis.looking_at(look - eye), eye)}


func _ground(view: TownView, p: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 500.0, p - Vector3.UP * 500.0)
	view.load_around(p)
	var hit := space.intersect_ray(q)
	return hit.position.y if hit else 0.0


static func _stats(ms: Array[float]) -> String:
	if ms.is_empty():
		return "-"
	var sorted := ms.duplicate()
	sorted.sort()
	var total := 0.0
	for m in sorted:
		total += m
	return "mean %.0f, max %.0f" % [total / sorted.size(), sorted[sorted.size() - 1]]
