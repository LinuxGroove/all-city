class_name WallStore
extends RefCounted
## What's on every wall of one town: the local record in
## user://walls/<town>.json, so a town plays offline with its walls as last
## seen, merged with the game server's when online play is on (all-city.walls
## and all-city.paint, docs/game-api.md in game-server). Offline, the local
## Buff cleans the walls at dawn by the same rules the server uses
## (PaintRules), every time a quarter is read.
##
## Paint made offline goes on the local record at once and waits to be sent
## (at most MAX_PENDING of them). The server judges it again when it gets
## there, as if painted then: if a rival went over the wall in the
## meantime it's refused and dropped, and the next read shows the server's
## walls. A call that fails while signed in is tried TRIES times, since
## LGOnline.rpc_async can't tell a refusal from a lost connection.
##
## Records are the server's: {writer, name, rank, kit, grade, eyes, heaven,
## at, capped}, with `writer` the account id (LOCAL for paint made before
## this copy ever signed in).

## The walls the Buff cleaned since this copy last saw them standing.
signal buffed(quarter: int, walls: PackedStringArray)
## A quarter's walls changed (a read or a paint): redraw them.
signal changed(quarter: int)

const FORMAT := 1
const DIR := "user://walls"
const MAX_PENDING := 40
const TRIES := 2
## The writer id of paint made before this copy signed in.
const LOCAL := "me"

var town := ""
var utc_offset_min := 0
## Whether to use the game server at all (online play must be on too).
var use_server := true
## The clock, in unix seconds; tests fix it. -1 is the real time.
var fixed_now := -1
## This writer's account id, once known.
var writer_id := ""
## The server's last answer (for tools), or null.
var last_reply: Variant = null

## quarter (int) -> {utc_offset_min, buffed_until, walls, buffs, seen}
var _quarters := {}
## [{quarter, paint (the all-city.paint payload), tries}]
var _pending := []


func _init(p_town: String, p_utc_offset_min := 0, p_use_server := true) -> void:
	town = p_town
	utc_offset_min = clampi(p_utc_offset_min, -720, 840)
	use_server = p_use_server
	load_local()


static func path_for(town_id: String) -> String:
	return DIR.path_join(town_id + ".json")


func now() -> int:
	return fixed_now if fixed_now >= 0 else int(Time.get_unix_time_from_system())


## Whether the server is asked: allowed here, online play on, a network up.
func online() -> bool:
	return use_server and LGOnline.is_enabled() and LGNetwork.is_up()


## The paint standing in a quarter as this copy knows it, after the local
## Buff: {wall id: record}.
func walls_in(quarter: int) -> Dictionary:
	var q := _quarter(quarter)
	PaintRules.settle(q, now())
	return q.walls


## The paint on one wall ({} when bare).
func wall(quarter: int, id: String) -> Dictionary:
	return walls_in(quarter).get(id, {})


## How many paints wait to be sent.
func pending() -> int:
	return _pending.size()


## Reads a quarter: the local Buff first, then the server's walls when
## online (sending any paint waiting first). Emits `buffed` with what the
## Buff took since this copy last saw it, and `changed`. Returns the walls.
func read_quarter(quarter: int) -> Dictionary:
	var q := _quarter(quarter)
	var t := now()
	var before := PackedStringArray(q.walls.keys())
	var cleaned := PackedStringArray()
	for b in PaintRules.buff(q.walls, int(q.buffed_until), t, int(q.utc_offset_min)):
		cleaned.append(b.wall)
	PaintRules.settle(q, t)
	if online():
		await flush()
		var ask := {"town": town, "quarter": quarter}
		if int(q.get("seen", 0)) > 0:
			ask["since"] = int(q.seen)
		var res = await _call("walls", ask)
		if res is Dictionary and res.get("walls") is Dictionary:
			_merge(quarter, q, res, t)
			cleaned = taken_by_buff(before, cleaned, PackedStringArray(res.get("buffed", [])), q.walls)
	save_local()
	if not cleaned.is_empty():
		buffed.emit(quarter, cleaned)
	changed.emit(quarter)
	return q.walls


## Paints a wall: `face` from Walls, the kit from TagKit (with "at" set),
## the grade 0 to 100 and the seconds it took. Returns {ok, reason, wall,
## capped, local}: `local` when it went only on this copy's record for now.
## Reasons are the server's ("rank", "rate", "full", "busy", "too_quick")
## and "respect" for the respect list.
func paint(face: Dictionary, rank: String, kit: Dictionary, grade: int, seconds: float, cap := false) -> Dictionary:
	var quarter := int(face.get("quarter", 0))
	var id := str(face.get("id", ""))
	if int(face.get("paint", Walls.ALL)) == Walls.NEVER:
		return {"ok": false, "reason": "respect"}
	if not PaintRules.MIN_SECONDS.has(rank):
		return {"ok": false, "reason": "rank"}
	if seconds < float(PaintRules.MIN_SECONDS[rank]):
		return {"ok": false, "reason": "too_quick"}
	var payload := {
		"town": town,
		"quarter": quarter,
		"wall": id,
		"rank": rank,
		"kit": kit,
		"grade": clampi(grade, 0, 100),
		"eyes": clampi(int(face.get("eyes", 0)), 0, 100),
		"heaven": bool(face.get("heaven", false)),
		"seconds": snappedf(seconds, 0.01),
		"utc_offset_min": utc_offset_min,
		"cap": cap,
	}
	var q := _quarter(quarter)
	if online():
		# The server judges; this copy's view of the wall may be old.
		await flush()
		var res = await _call("paint", payload)
		if res is Dictionary:
			if not bool(res.get("ok", false)) or not res.get("wall") is Dictionary:
				return {"ok": false, "reason": str(res.get("reason", "busy"))}
			q.walls[id] = res.wall
			if int(q.get("seen", 0)) <= 0:
				# The next read asks what the Buff took since this paint.
				q.seen = int(res.wall.get("at", now()))
			save_local()
			changed.emit(quarter)
			return {"ok": true, "reason": "", "wall": res.wall, "capped": bool(res.wall.get("capped", false)), "local": false}
	var t := now()
	PaintRules.settle(q, t)
	var verdict := PaintRules.can_paint(q.walls.get(id, {}), me(), rank, cap, t)
	if not verdict.ok:
		return {"ok": false, "reason": verdict.reason}
	var rec := {
		"writer": me(), "name": str(kit.get("name", "")), "rank": rank, "kit": kit, "grade": payload.grade,
		"eyes": payload.eyes, "heaven": payload.heaven, "at": t, "capped": verdict.capped,
	}
	q.walls[id] = rec
	_pending.append({"quarter": quarter, "paint": payload, "tries": 0})
	if _pending.size() > MAX_PENDING:
		_pending = _pending.slice(_pending.size() - MAX_PENDING)
	save_local()
	changed.emit(quarter)
	return {"ok": true, "reason": "", "wall": rec, "capped": verdict.capped, "local": true}


## Sends paint made offline, oldest first. Returns how many the server took.
func flush() -> int:
	if _pending.is_empty() or not online() or not await _sign_in():
		return 0
	var took := 0
	for p in _pending.duplicate():
		var res = await LGOnline.rpc_async("%s.paint" % GameConfig.GAME_ID, p.paint)
		if res is Dictionary:
			_pending.erase(p)
			if bool(res.get("ok", false)) and res.get("wall") is Dictionary:
				_quarter(int(p.quarter)).walls[str(p.paint.wall)] = res.wall
				took += 1
		elif LGOnline.is_connected_online():
			p.tries += 1
			if p.tries >= TRIES:
				_pending.erase(p)
		else:
			break
	save_local()
	return took


func load_local() -> void:
	_quarters.clear()
	_pending.clear()
	var text := FileAccess.get_file_as_string(path_for(town))
	var data = JSON.parse_string(text) if text != "" else null
	if not data is Dictionary or int(data.get("format", 0)) != FORMAT:
		return
	writer_id = str(data.get("writer", ""))
	var quarters: Dictionary = data.get("quarters", {})
	for key in quarters:
		var q = quarters[key]
		if q is Dictionary and q.get("walls") is Dictionary:
			_quarters[int(key)] = {
				"utc_offset_min": int(q.get("utc_offset_min", utc_offset_min)),
				"buffed_until": int(q.get("buffed_until", now())),
				"walls": _valid(q.walls),
				"buffs": q.get("buffs", []) if q.get("buffs") is Array else [],
				"seen": int(q.get("seen", 0)),
			}
	for p in data.get("pending", []):
		if p is Dictionary and p.get("paint") is Dictionary:
			_pending.append({"quarter": int(p.get("quarter", 0)), "paint": p.paint, "tries": int(p.get("tries", 0))})


func save_local() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var quarters := {}
	for k in _quarters:
		quarters[str(k)] = _quarters[k]
	var f := FileAccess.open(path_for(town), FileAccess.WRITE)
	if f == null:
		push_warning("WallStore: can't write %s" % path_for(town))
		return
	f.store_string(JSON.stringify({"format": FORMAT, "town": town, "writer": writer_id, "quarters": quarters,
		"pending": _pending}))
	f.close()


## Deletes this town's local record.
func forget() -> void:
	_quarters.clear()
	_pending.clear()
	if FileAccess.file_exists(path_for(town)):
		DirAccess.remove_absolute(path_for(town))


func _quarter(quarter: int) -> Dictionary:
	if not _quarters.has(quarter):
		_quarters[quarter] = {"utc_offset_min": utc_offset_min, "buffed_until": now(), "walls": {}, "buffs": [],
			"seen": 0}
	return _quarters[quarter]


## Takes the server's answer for a quarter: its walls, with paint still
## waiting to be sent laid over them.
func _merge(quarter: int, q: Dictionary, res: Dictionary, t: int) -> void:
	q.walls = _valid(res.walls)
	for p in _pending:
		if int(p.quarter) == quarter:
			var pay: Dictionary = p.paint
			q.walls[str(pay.wall)] = {"writer": me(), "name": str(pay.kit.get("name", "")), "rank": pay.rank,
				"kit": pay.kit, "grade": pay.grade, "eyes": pay.eyes, "heaven": pay.heaven, "at": t, "capped": pay.cap}
	var dawn := int(res.get("last_dawn", 0))
	for id in res.get("buffed", []):
		q.buffs.append({"wall": str(id), "at": dawn})
	if q.buffs.size() > PaintRules.BUFF_LOG:
		q.buffs = q.buffs.slice(q.buffs.size() - PaintRules.BUFF_LOG)
	q.buffed_until = t
	q.seen = t


## What a read tells the writer the Buff took: of the walls this copy had
## (`before`), the ones the server says it cleaned since this copy last
## read the quarter, and the ones the local Buff cleaned that the server
## doesn't have either (the server only lists what went since a read, so a
## copy that only painted there hears it from its own Buff).
static func taken_by_buff(before: PackedStringArray, local: PackedStringArray, server: PackedStringArray,
		standing: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for id in server:
		if id in before and not id in out:
			out.append(id)
	for id in local:
		if id in before and not standing.has(id) and not id in out:
			out.append(id)
	return out


## Only records the rules can read.
static func _valid(walls: Dictionary) -> Dictionary:
	var out := {}
	for id in walls:
		var w = walls[id]
		if w is Dictionary and PaintRules.LIFE.has(str(w.get("rank", ""))) and w.has("at"):
			w["writer"] = str(w.get("writer", ""))
			w["eyes"] = int(w.get("eyes", 0))
			w["heaven"] = bool(w.get("heaven", false))
			out[str(id)] = w
	return out


## This writer's id on the walls: the account's, or LOCAL before the first sign-in.
func me() -> String:
	return writer_id if writer_id != "" else LOCAL


func _sign_in() -> bool:
	if not online():
		return false
	var tag := str(LGSettings.get_value("player", "tag", ""))
	if not await LGOnline.connect_async(tag, GameConfig.GAME_ID):
		return false
	var uid := str(LGOnline.session.user_id) if LGOnline.session else ""
	if uid != "" and uid != writer_id:
		# Paint made before this copy first signed in is this account's.
		for k in _quarters:
			for id in _quarters[k].walls:
				var w: Dictionary = _quarters[k].walls[id]
				if w.writer == LOCAL:
					w.writer = uid
		writer_id = uid
	return true


func _call(rpc_name: String, payload: Dictionary) -> Variant:
	if not await _sign_in():
		return null
	last_reply = await LGOnline.rpc_async("%s.%s" % [GameConfig.GAME_ID, rpc_name], payload)
	return last_reply
