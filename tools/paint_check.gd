extends Node
## Paints a tag on a wall through a real game server, and reads it back
## from another copy of the game, as two machines would. Run each copy with
## its own data folder, so each has its own device id and account:
##   XDG_DATA_HOME=/tmp/a godot --headless --path . tools/paint_check.tscn -- paint <town> <quarter> <wall> <utc_offset_min>
##   XDG_DATA_HOME=/tmp/b godot --headless --path . tools/paint_check.tscn -- read <town> <quarter> <wall> [expect=gone]
## "server=host:port" picks the server (127.0.0.1:7350 by default, over
## plain http with the default key, as the game-server Compose setup runs)
## and "name=SALT" the writer's name.
##
## paint runs a whole tag with PaintAction (a scripted stick following the
## guide) on a face with that wall id and sends it with WallStore; read
## reads the quarter with WallStore and says whether the tag is there, and
## which walls the Buff took since this copy last read it. Each prints
## "PAINT OK" or "READ OK" and exits 0 when its side worked (for read, when
## the tag is there, or gone with expect=gone).

const TIMEOUT := 30.0

var _buffed := PackedStringArray()
var _stored := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var role := args[0] if args.size() > 0 else ""
	var town := args[1] if args.size() > 1 else "test-town"
	var quarter := int(args[2]) if args.size() > 2 else 0
	var wall := args[3] if args.size() > 3 else "w0000000a1"
	var offset := int(args[4]) if args.size() > 4 and role == "paint" else 0
	var server := "127.0.0.1:7350"
	var name := "SALT"
	var expect := "there"
	for a in args:
		if a.begins_with("server="):
			server = a.trim_prefix("server=")
		elif a.begins_with("name="):
			name = a.trim_prefix("name=")
		elif a.begins_with("expect="):
			expect = a.trim_prefix("expect=")
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	var at := server.split(":")
	LGSettings.set_value("online", "enabled", true, false)
	LGSettings.set_value("online", "host", at[0], false)
	LGSettings.set_value("online", "port", int(at[1]) if at.size() > 1 else 7350, false)
	LGSettings.set_value("online", "scheme", "http", false)
	LGSettings.set_value("online", "server_key", "defaultkey", false)
	LGSettings.set_value("player", "tag", name, false)
	print("device %s, user dir %s" % [Nakama.get_device_id(), ProjectSettings.globalize_path("user://")])
	var ok := false
	match role:
		"paint":
			ok = await _paint(town, quarter, wall, offset, name)
		"read":
			ok = await _read(town, quarter, wall, expect)
		_:
			printerr("paint_check: say paint or read")
	print("%s %s" % [role.to_upper(), "OK" if ok else "FAILED"])
	LGOnline.disconnect_online()
	get_tree().quit(0 if ok else 1)


func _paint(town: String, quarter: int, wall: String, offset: int, name: String) -> bool:
	var walls := Walls.new()
	walls.add({"id": wall, "a": Vector3(0, 0, 0), "b": Vector3(8, 0, 0), "base": 0.0, "top": 6.0, "paint": Walls.ALL,
		"eyes": 40, "quarter": quarter})
	var writer := Node3D.new()
	add_child(writer)
	writer.position = Vector3(4, 0, 0.8)
	writer.rotation.y = PI
	var store := WallStore.new(town, offset)
	var action := PaintAction.new(walls, writer, Callable(), null, store)
	action.writer_name = name
	action.stored.connect(_on_stored)
	var t := 0.0
	var step := 1.0 / 60.0
	while action.state != PaintAction.State.DONE and t < TIMEOUT:
		var input := PaintInput.make(true, action.guide_direction() * 0.8 if action.is_painting() else Vector2.ZERO)
		action.step(input, step)
		t += step
	if action.state != PaintAction.State.DONE:
		print("the tag never finished: ", action.line)
		return false
	print("painted %s on %s in %.2f s: %s (%d)" % [action.kit.name, wall, action.seconds, PaintAction.label_for(action.grade),
		action.grade])
	while _stored.is_empty() and t < TIMEOUT * 2:
		await get_tree().process_frame
		t += get_process_delta_time()
	if _stored.is_empty():
		print("the walls never answered")
		return false
	print("server said: ", JSON.stringify(store.last_reply))
	if not _stored.get("ok", false) or _stored.get("local", true):
		print("the tag didn't reach the server: %s" % _stored.get("reason", "offline"))
		return false
	var rec: Dictionary = _stored.wall
	print("on the wall: %s's %s, painted at %s UTC, writer %s" % [rec.name, rec.rank,
		Time.get_datetime_string_from_unix_time(int(rec.at)), rec.writer])
	var dawn := PaintRules.last_dawn(int(rec.at), offset) + PaintRules.DAY
	print("the Buff comes next at %s UTC (06:00 in town, UTC%+d min)" % [Time.get_datetime_string_from_unix_time(dawn),
		offset])
	return true


func _read(town: String, quarter: int, wall: String, expect: String) -> bool:
	var store := WallStore.new(town)
	store.buffed.connect(_on_buffed)
	var walls: Dictionary = await store.read_quarter(quarter)
	print("server said: ", JSON.stringify(store.last_reply))
	if not store.last_reply is Dictionary:
		print("the server never answered: ", LGOnline.last_error)
		return false
	print("walls with paint in %s quarter %d: %s" % [town, quarter, ", ".join(PackedStringArray(walls.keys()))])
	if not _buffed.is_empty():
		print("the Buff took overnight: ", ", ".join(_buffed))
	if walls.has(wall):
		var rec: Dictionary = walls[wall]
		print("TAG THERE: %s's %s on %s, painted %s UTC" % [rec.name, rec.rank, wall,
			Time.get_datetime_string_from_unix_time(int(rec.at))])
		return expect == "there"
	print("TAG GONE: nothing on %s%s" % [wall, " (the Buff took it)" if wall in _buffed else ""])
	return expect == "gone" and wall in _buffed


func _on_stored(result: Dictionary) -> void:
	_stored = result


func _on_buffed(_quarter: int, walls: PackedStringArray) -> void:
	_buffed.append_array(walls)
