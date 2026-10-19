class_name PaintRules
extends RefCounted
## The rules of the walls: how long paint stands, what goes over what, when
## dawn comes and what the Buff cleans. An exact copy of the game server's
## rules (AllCity in modules/src/games/all-city.ts in game-server), so a town
## played offline changes the way the server would change it; the comment
## above them there is the description, and tests/paint_rules_tests.gd runs
## the server's own test cases against this copy so the two can't drift.
##
## A wall's paint is a Dictionary as the server sends it: {writer, name,
## rank, kit, grade, eyes, heaven, at, capped}. Times are unix seconds.

const DAY := 86400

## Ranks, lowest first: each goes over the ones before it.
const RANKS := ["tag", "throwup", "piece", "burner"]
## How long each rank stands before it fades away, in seconds.
const LIFE := {"tag": 3 * DAY, "throwup": 10 * DAY, "piece": 30 * DAY, "burner": 60 * DAY}
## The least time each rank takes to paint, in seconds.
const MIN_SECONDS := {"tag": 2, "throwup": 15, "piece": 90, "burner": 240}
## What cleaning each rank costs the Buff, out of BUFF_BUDGET a dawn.
const BUFF_COST := {"tag": 1, "throwup": 2, "piece": 4, "burner": 8}
const BUFF_BUDGET := 8
## The most dawns the Buff catches up on.
const BUFF_DAWNS := 7
## Dawn, in hours after the town's midnight.
const DAWN_HOUR := 6
## Recent buffs kept on a quarter.
const BUFF_LOG := 200
## The most painted walls one quarter holds.
const MAX_WALLS := 1000


## Whether paint has faded away by `now`.
static func faded(wall: Dictionary, now: int) -> bool:
	return now - int(wall.at) > int(LIFE[wall.rank])


## Whether paint has faded past half, so an equal rank can go over it.
static func past_half(wall: Dictionary, now: int) -> bool:
	return now - int(wall.at) > int(LIFE[wall.rank]) * 0.5


## Whether `writer` may put `rank` on a wall that has `current` on it ({}
## when bare): {ok, capped, reason}.
static func can_paint(current: Dictionary, writer: String, rank: String, cap: bool, now: int) -> Dictionary:
	if current.is_empty() or faded(current, now) or str(current.writer) == writer:
		return {"ok": true, "capped": false, "reason": ""}
	var was := RANKS.find(current.rank)
	var next := RANKS.find(rank)
	if next > was or (next == was and past_half(current, now)):
		return {"ok": true, "capped": false, "reason": ""}
	if next < was and cap:
		return {"ok": true, "capped": true, "reason": ""}
	return {"ok": false, "capped": false, "reason": "rank"}


## Every dawn after `from` up to and including `to`, the last BUFF_DAWNS of
## them, oldest first.
static func dawns(from: int, to: int, utc_offset_min: int) -> Array[int]:
	var shift := DAWN_HOUR * 3600 - utc_offset_min * 60
	var last := _floor_div(to - shift, DAY)
	var first := maxi(_floor_div(from - shift, DAY) + 1, last - BUFF_DAWNS + 1)
	var out: Array[int] = []
	for d in range(first, last + 1):
		out.append(d * DAY + shift)
	return out


## The latest dawn at or before `now`.
static func last_dawn(now: int, utc_offset_min: int) -> int:
	var shift := DAWN_HOUR * 3600 - utc_offset_min * 60
	return _floor_div(now - shift, DAY) * DAY + shift


## The walls the Buff cleans at the dawns after `from` up to `to`, in order,
## as [{wall, at}]. Changes nothing.
static func buff(walls: Dictionary, from: int, to: int, utc_offset_min: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var gone := {}
	for dawn in dawns(from, to, utc_offset_min):
		# [cost, -eyes, at, id] sorts in the Buff's order.
		var standing := []
		for id in walls:
			var w: Dictionary = walls[id]
			if not gone.has(id) and not bool(w.heaven) and int(w.at) < dawn and not faded(w, dawn):
				standing.append([int(BUFF_COST[w.rank]), -int(w.eyes), int(w.at), str(id)])
		standing.sort_custom(_buff_before)
		var left := BUFF_BUDGET
		for s in standing:
			if s[0] > left:
				break
			left -= s[0]
			gone[s[3]] = true
			out.append({"wall": s[3], "at": dawn})
	return out


## Brings a quarter ({utc_offset_min, buffed_until, walls, buffs}) up to
## `now`: the Buff's dawns since buffed_until (logged in buffs, the last
## BUFF_LOG kept), then faded paint dropped. Returns whether a dawn passed.
static func settle(q: Dictionary, now: int) -> bool:
	var offset := int(q.utc_offset_min)
	var until := int(q.buffed_until)
	var passed := not dawns(until, now, offset).is_empty()
	var walls: Dictionary = q.walls
	var buffs: Array = q.buffs
	for b in buff(walls, until, now, offset):
		walls.erase(b.wall)
		buffs.append(b)
	if buffs.size() > BUFF_LOG:
		q.buffs = buffs.slice(buffs.size() - BUFF_LOG)
	for id in walls.keys():
		if faded(walls[id], now):
			walls.erase(id)
	q.buffed_until = maxi(until, now)
	return passed


## The walls the Buff cleaned after `since`, each once.
static func buffed_since(q: Dictionary, since: int) -> PackedStringArray:
	var out := PackedStringArray()
	for b in q.buffs:
		if int(b.at) > since and not out.has(str(b.wall)):
			out.append(str(b.wall))
	return out


## Whether one wall comes before another on the Buff's round: cheapest
## first, then most eyes, then oldest, then by id.
static func _buff_before(x: Array, y: Array) -> bool:
	for i in 4:
		if x[i] != y[i]:
			return x[i] < y[i]
	return false


## Division rounding down, as Math.floor does, for times before 1970 too.
@warning_ignore("integer_division")
static func _floor_div(a: int, b: int) -> int:
	return (a - posmod(a, b)) / b
