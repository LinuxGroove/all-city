extends Node3D
## Pictures of the writers in the game's own light, close up: each body in a
## few poses seen from the front, three quarters, the side and the back, to
## judge their clothes. One picture per body, a row per pose and a column per
## view, each the size of the window.
##
##   xvfb-run -a -s "-screen 0 480x640x24" godot --path . --resolution 480x640 tools/people_shot.tscn -- \
##       --out=/tmp/people [--time=day|dusk|night] [--body=male|female|both] \
##       [--poses=Idle,Sprint,Crouch_Idle,NinjaJump_Idle] [--views=front,three,side,back,close] [--board=true]

const VIEWS := {
	"front": {"yaw": 0.0, "focus": 0.95, "dist": 4.6},
	"three": {"yaw": 38.0, "focus": 0.95, "dist": 4.6},
	"side": {"yaw": 90.0, "focus": 0.95, "dist": 4.6},
	"back": {"yaw": 180.0, "focus": 0.95, "dist": 4.6},
	"close": {"yaw": 28.0, "focus": 1.3, "dist": 2.1},
	"legs": {"yaw": 32.0, "focus": 0.35, "dist": 2.4},
	"hood": {"yaw": 205.0, "focus": 1.3, "dist": 2.1},
	"pouch": {"yaw": 22.0, "focus": 1.0, "dist": 1.3},
}

var _opts := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			_opts[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var out := str(_opts.get("out", "/tmp/people"))
	var bodies: Array = ["male", "female"] if str(_opts.get("body", "both")) == "both" else [str(_opts.body)]
	DirAccess.make_dir_recursive_absolute(out)
	for body in bodies:
		await _shoot(body == "female", out.path_join(body + ".png"))
	get_tree().quit()


func _shoot(female: bool, path: String) -> void:
	for c in get_children():
		c.free()
	var stage := Node3D.new()
	add_child(stage)
	Look.dress(stage, str(_opts.get("time", "day")))
	var ground := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(30, 0.2, 30)
	slab.material = Look.flat(Color("8d8b94"))
	ground.mesh = slab
	ground.position.y = -0.1
	stage.add_child(ground)
	var cam := Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.fov = 30.0
	stage.add_child(cam)
	cam.current = true
	# With --board=true the writer stands on the skateboard, side on to it.
	var board := str(_opts.get("board", "false")) == "true"
	var look := {"board": board}
	for k in ["main", "accent", "legs"]:
		if _opts.has(k):
			look[k] = Color(str(_opts[k]))
	var writer := Person.make("writer", female, int(_opts.get("seed", 3)), look)
	stage.add_child(writer)
	if board:
		writer.lift(Person.DECK_TOP)
	var poses: PackedStringArray = str(_opts.get("poses", "Idle,Sprint,Crouch_Idle")).split(",")
	var views: PackedStringArray = str(_opts.get("views", "front,three,side,back,close")).split(",")
	var img: Image
	for r in poses.size():
		writer.pose(poses[r], float(_opts.get("at", 0.3)))
		for c in views.size():
			var v: Dictionary = VIEWS[views[c]]
			var dir := Vector3(sin(deg_to_rad(v.yaw)), 0.1, cos(deg_to_rad(v.yaw))).normalized()
			cam.position = Vector3(0, v.focus, 0) + dir * v.dist
			cam.look_at(Vector3(0, v.focus, 0), Vector3.UP)
			for i in 6:
				await get_tree().process_frame
			var shot := get_viewport().get_texture().get_image()
			shot.convert(Image.FORMAT_RGB8)
			if img == null:
				img = Image.create(shot.get_width() * views.size(), shot.get_height() * poses.size(), false, Image.FORMAT_RGB8)
			img.blit_rect(shot, Rect2i(Vector2i.ZERO, shot.get_size()), Vector2i(c * shot.get_width(), r * shot.get_height()))
	img.save_png(path)
	print("people_shot: ", path)
