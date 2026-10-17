extends RefCounted
## PaintRules against the game server's own test cases for its rules
## (modules/test/util.test.mjs in game-server, the all-city tests on lives,
## going over, dawns, the Buff and settling a quarter), case for case, so the
## game's copy and the server's can't drift apart.

const DAY := 86400


## Saturday 17 October 2026, 12:00 UTC.
static func _t() -> int:
	return _at("2026-10-17T12:00:00")


static func _at(when: String) -> int:
	return Time.get_unix_time_from_datetime_string(when)


static func _paint_on(rank: String, at: int, extra := {}) -> Dictionary:
	var w := {"writer": "a", "name": "Ana", "rank": rank, "kit": {}, "grade": 50, "eyes": 50, "heaven": false,
		"at": at, "capped": false}
	w.merge(extra, true)
	return w


static func _utc(times: Array) -> Array:
	var out := []
	for t in times:
		out.append(Time.get_datetime_string_from_unix_time(int(t)).substr(0, 16))
	return out


static func _list(a) -> Array:
	var out := []
	for x in a:
		out.append(x)
	return out


static func _walls_of(cleaned: Array) -> Array:
	var out := []
	for b in cleaned:
		out.append(b.wall)
	return out


func test_lives(t) -> void:
	var T := _t()
	t.check(PaintRules.LIFE == {"tag": 3 * DAY, "throwup": 10 * DAY, "piece": 30 * DAY, "burner": 60 * DAY},
			"paint lives as long as on the server")
	var tag := _paint_on("tag", T)
	t.check(not PaintRules.faded(tag, T + 3 * DAY), "a tag stands for exactly three days")
	t.check(PaintRules.faded(tag, T + 3 * DAY + 1), "and is gone a second after")
	t.check(not PaintRules.past_half(tag, T + 129600), "a tag isn't past half at a day and a half")
	t.check(PaintRules.past_half(tag, T + 129600 + 1), "and is a second after")
	t.check(not PaintRules.faded(_paint_on("burner", T), T + 60 * DAY), "a burner stands sixty days")
	t.check(PaintRules.faded(_paint_on("burner", T), T + 60 * DAY + 1), "and no longer")


func test_going_over(t) -> void:
	var T := _t()
	var ok := {"ok": true, "capped": false, "reason": ""}
	var no := {"ok": false, "capped": false, "reason": "rank"}
	var piece := _paint_on("piece", T)
	var now := T + 60
	t.check(PaintRules.can_paint({}, "b", "tag", false, now) == ok, "a bare wall takes anything")
	t.check(PaintRules.can_paint(piece, "b", "burner", false, now) == ok, "a burner goes over a piece")
	t.check(PaintRules.can_paint(piece, "b", "piece", false, now) == no, "a fresh piece holds against another piece")
	t.check(PaintRules.can_paint(piece, "b", "piece", false, T + 15 * DAY) == no, "until exactly half its life")
	t.check(PaintRules.can_paint(piece, "b", "piece", false, T + 15 * DAY + 1) == ok,
			"and doesn't once it's faded past half")
	t.check(PaintRules.can_paint(piece, "b", "throwup", false, now) == no, "a throw-up can't go over a piece")
	t.check(PaintRules.can_paint(piece, "b", "tag", true, now) == {"ok": true, "capped": true, "reason": ""},
			"a tag caps a piece")
	t.check(PaintRules.can_paint(piece, "b", "piece", true, now) == no, "capping is for lower ranks")
	t.check(PaintRules.can_paint(piece, "b", "burner", true, now) == ok, "going over with a higher rank isn't capping")
	t.check(PaintRules.can_paint(piece, "a", "tag", false, now) == ok, "writers go over their own work")
	t.check(PaintRules.can_paint(piece, "a", "tag", true, now) == ok, "without capping themselves")
	t.check(PaintRules.can_paint(piece, "b", "tag", false, T + 30 * DAY + 1) == ok, "faded paint leaves a bare wall")


func test_dawns(t) -> void:
	var T := _t()
	var from := _at("2026-10-15T12:00:00")
	t.check(_utc(PaintRules.dawns(from, T, 0)) == ["2026-10-16T06:00", "2026-10-17T06:00"], "dawn at 06:00 in a UTC town")
	t.check(_utc(PaintRules.dawns(from, T, 60)) == ["2026-10-16T05:00", "2026-10-17T05:00"], "UTC+1")
	t.check(_utc(PaintRules.dawns(from, T, 330)) == ["2026-10-16T00:30", "2026-10-17T00:30"], "UTC+5:30")
	t.check(_utc(PaintRules.dawns(from, T, -300)) == ["2026-10-16T11:00", "2026-10-17T11:00"], "UTC-5")
	t.check(_utc(PaintRules.dawns(from, T, 840)) == ["2026-10-15T16:00", "2026-10-16T16:00"],
			"UTC+14 sees dawn the day before UTC")
	t.check(_utc(PaintRules.dawns(from, T, -720)) == ["2026-10-15T18:00", "2026-10-16T18:00"], "UTC-12")
	var dawn := _at("2026-10-17T06:00:00")
	t.check(_list(PaintRules.dawns(dawn - 1, dawn, 0)) == [dawn], "a dawn right now counts")
	t.check(PaintRules.dawns(dawn, dawn + DAY - 1, 0).is_empty(), "and isn't counted again")
	t.check(PaintRules.dawns(T, from, 0).is_empty(), "no dawns going backwards")
	var month := PaintRules.dawns(T - 30 * DAY, T, 0)
	t.check(month.size() == 7, "the Buff catches up on a week at most")
	t.check(_utc([month[0], month[6]]) == ["2026-10-11T06:00", "2026-10-17T06:00"], "the last week of them")
	t.check(PaintRules.dawns(0, T, 0).size() == 7, "even from 1970")
	t.check(PaintRules.last_dawn(dawn, 0) == dawn, "the last dawn at dawn is that dawn")
	t.check(PaintRules.last_dawn(dawn - 1, 0) == dawn - DAY, "and a second before, the day before's")
	t.check(_utc([PaintRules.last_dawn(T, -300), PaintRules.last_dawn(T, 840)]) == ["2026-10-17T11:00", "2026-10-16T16:00"],
			"last dawns either side of UTC")


func test_buff(t) -> void:
	var dawn := _at("2026-10-17T06:00:00")
	var before := dawn - DAY
	var quarter := {
		"w000001": _paint_on("tag", before, {"eyes": 10}),
		"w000002": _paint_on("tag", before, {"eyes": 90}),
		"w000003": _paint_on("burner", before, {"eyes": 100}),
		"w000004": _paint_on("piece", before, {"eyes": 80}),
		"w000005": _paint_on("throwup", before, {"eyes": 20}),
		"w000006": _paint_on("tag", before, {"eyes": 100, "heaven": true}),
	}
	# 1 + 1 + 2 + 4 spends the budget of 8, so the burner waits.
	t.check(_walls_of(PaintRules.buff(quarter, dawn - 1, dawn, 0)) == ["w000002", "w000001", "w000005", "w000004"],
			"the Buff cleans the cheapest walls first, then the most seen, never heaven spots")
	t.check(quarter.size() == 6, "working it out changes nothing")
	var throwups := {"w00000a": _paint_on("throwup", before), "w00000b": _paint_on("throwup", before),
		"w00000c": _paint_on("throwup", before), "w00000d": _paint_on("piece", before)}
	t.check(_walls_of(PaintRules.buff(throwups, dawn - 1, dawn, 0)) == ["w00000a", "w00000b", "w00000c"],
			"it stops at the first wall that costs more than what's left")
	var big := {"w0000b1": _paint_on("burner", before, {"eyes": 100}), "w0000b2": _paint_on("tag", before, {"eyes": 0})}
	t.check(_walls_of(PaintRules.buff(big, dawn - 1, dawn, 0)) == ["w0000b2"], "a burner doesn't fit after a tag")
	t.check(_list(PaintRules.buff(big, dawn - 1, dawn + DAY, 0)) == [{"wall": "w0000b2", "at": dawn},
			{"wall": "w0000b1", "at": dawn + DAY}], "and goes the next morning")
	var ties := {"w0000c2": _paint_on("tag", before - 60), "w0000c1": _paint_on("tag", before),
		"w0000c3": _paint_on("tag", before - 60)}
	t.check(_walls_of(PaintRules.buff(ties, dawn - 1, dawn, 0)) == ["w0000c2", "w0000c3", "w0000c1"],
			"equal cost and eyes: oldest first, then by id")
	var late := {"w0000d1": _paint_on("tag", dawn), "w0000d2": _paint_on("tag", dawn - 3 * DAY - 1),
		"w0000d3": _paint_on("tag", dawn - 3 * DAY)}
	t.check(_walls_of(PaintRules.buff(late, dawn - 1, dawn, 0)) == ["w0000d3"],
			"paint from the dawn on, and paint already faded by it, isn't on its round")
	var ten := {}
	for i in 10:
		ten["w00010%d" % i] = _paint_on("tag", before - i)
	var times := []
	for b in PaintRules.buff(ten, dawn - 1, dawn + DAY, 0):
		times.append(b.at)
	var expected := []
	for i in 8:
		expected.append(dawn)
	expected.append_array([dawn + DAY, dawn + DAY])
	t.check(times == expected, "ten tags take two mornings")
	var early := {"w0000e1": _paint_on("tag", dawn - 1800)}
	t.check(_walls_of(PaintRules.buff(early, dawn - 7200, dawn, 0)) == ["w0000e1"],
			"a tag at 05:30 UTC came before dawn in a UTC town")
	t.check(PaintRules.buff(early, dawn - 7200, dawn, 60).is_empty(), "but after it in a UTC+1 one")


func test_settle(t) -> void:
	var dawn := _at("2026-10-17T06:00:00")
	var buffs := []
	for i in 199:
		buffs.append({"wall": "w%07d" % i, "at": dawn - 2 * DAY})
	var q := {
		"utc_offset_min": 0,
		"buffed_until": dawn - 1,
		"walls": {"w0000f1": _paint_on("tag", dawn - 60), "w0000f2": _paint_on("piece", dawn - 31 * DAY),
			"w0000f3": _paint_on("burner", dawn - 60, {"heaven": true})},
		"buffs": buffs,
	}
	t.check(PaintRules.settle(q, dawn + 60), "a dawn passed")
	t.check(q.walls.keys() == ["w0000f3"], "the tag was buffed and the piece had faded")
	t.check(q.buffs.size() == 200, "the buff log holds 200")
	t.check(q.buffs[199] == {"wall": "w0000f1", "at": dawn}, "the newest buff is last")
	t.check(q.buffed_until == dawn + 60, "the Buff is up to now")
	t.check(not PaintRules.settle(q, dawn + 120), "no dawn since")
	q.walls["w0000f4"] = _paint_on("tag", dawn + 100)
	q.walls["w0000f5"] = _paint_on("tag", dawn + 100)
	t.check(PaintRules.settle(q, dawn + DAY), "the next morning")
	t.check(q.buffs.size() == 200, "the log stays at 200")
	t.check(q.buffs[0].wall == "w0000002", "the oldest buffs go first")
	t.check(_list(PaintRules.buffed_since(q, dawn)) == ["w0000f4", "w0000f5"], "buffed since this morning")
	t.check(_list(PaintRules.buffed_since(q, dawn - 1)) == ["w0000f1", "w0000f4", "w0000f5"], "and since before it")
	q.buffs.append({"wall": "w0000f4", "at": dawn + 2 * DAY})
	t.check(_list(PaintRules.buffed_since(q, dawn)) == ["w0000f4", "w0000f5"], "each wall once")
