extends RefCounted
## The skater in the test yard (tools/yard.gd), driven through SkaterInput
## one physics tick at a time: pushing, jumping, grinding the stair rail and
## a kerb, wall riding a facade, climbing to the roof and dropping off it,
## Flow, painting's lock, the camera's level horizon, and Lines.

const Yard := preload("res://tools/yard.gd")
const DT := 1.0 / 60.0
## Down the flight beside its middle rail.
const STAIR_LANE := Yard.STAIR_X - 1.2


# --- Lines --------------------------------------------------------------------

func test_lines(t) -> void:
	var lines := Lines.new()
	var kerb := lines.add(Lines.Kind.KERB, PackedVector3Array([Vector3(0, 0, 0), Vector3(20, 0, 0), Vector3(20, 0, 20)]),
			"0,0")
	var rail := lines.add(Lines.Kind.HANDRAIL, PackedVector3Array([Vector3(5, 1, 5), Vector3(5, 1, -5)]), "1,0")
	var pipe := lines.add(Lines.Kind.CLIMB, PackedVector3Array([Vector3(30, 0, 0), Vector3(30, 12, 0)]), "1,0")
	t.check(lines.count() == 3, "three lines")
	var hit := lines.nearest(Vector3(10, 0.3, 0.5), 1.0)
	t.check(not hit.is_empty() and hit.id == kerb and hit.seg == 0, "the kerb is nearest")
	t.check(not hit.is_empty() and hit.point.is_equal_approx(Vector3(10, 0, 0)), "at the closest point")
	t.check(not hit.is_empty() and absf(hit.distance - Vector2(0.3, 0.5).length()) < 0.001, "with its distance")
	t.check(lines.nearest(Vector3(10, 0.3, 0.5), 1.0, [Lines.Kind.HANDRAIL]).is_empty(), "kinds filter the search")
	hit = lines.nearest(Vector3(5.4, 1.5, 0), 1.0)
	t.check(not hit.is_empty() and hit.id == rail and hit.tangent.is_equal_approx(Vector3(0, 0, -1)), "the rail and its way")
	hit = lines.nearest(Vector3(30.5, 6, 0), 1.0, [Lines.Kind.CLIMB])
	t.check(not hit.is_empty() and hit.id == pipe and is_equal_approx(hit.point.y, 6.0), "a climb, at the right height")
	t.check(lines.nearest(Vector3(50, 0, 50), 3.0).is_empty(), "nothing far from every line")
	# Walking along: round the kerb's corner, and off its end.
	var moved := lines.advance(kerb, 0, 0.5, 15.0)
	t.check(moved.seg == 1 and moved.point.is_equal_approx(Vector3(20, 0, 5)), "advance goes round a corner")
	t.check(absf(moved.turn - PI * 0.5) < 0.01, "and says how sharp it was")
	moved = lines.advance(kerb, 1, 0.5, 14.0)
	t.check(moved.ended and is_equal_approx(moved.over, 4.0) and moved.point.is_equal_approx(Vector3(20, 0, 20)),
			"advance stops at the end")
	moved = lines.advance(kerb, 0, 0.5, -4.0)
	t.check(not moved.ended and moved.point.is_equal_approx(Vector3(6, 0, 0)), "and goes backwards")
	t.check(is_equal_approx(lines.room(kerb, 0, 0.5, 1), 30.0) and is_equal_approx(lines.room(kerb, 0, 0.5, -1), 10.0),
			"room to each end")
	# A block's kerb as a loop of many points, which never ends.
	var ring := PackedVector3Array()
	for i in 201:
		var a := TAU * i / 200.0
		ring.append(Vector3(100 + cos(a) * 30, 0.15, sin(a) * 30))
	ring[200] = ring[0]
	var loop := lines.add(Lines.Kind.KERB, ring, "2,0")
	for k in 8:
		var a := TAU * k / 8.0 + 0.1
		hit = lines.nearest(Vector3(100 + cos(a) * 30.4, 0.2, sin(a) * 30.4), 1.0)
		t.check(not hit.is_empty() and hit.id == loop and hit.distance < 0.45, "a long loop is found all round (%d)" % k)
	t.check(lines.room(loop, 3, 0.5, 1) == INF, "a loop has room for ever")
	moved = lines.advance(loop, 199, 0.5, 10.0)
	t.check(not moved.ended and moved.seg < 20, "and goes round past its start")
	# Tiles leave with their lines, and the origin moves.
	lines.drop("1,0")
	t.check(lines.count() == 2 and lines.line(rail).is_empty(), "dropping a tile drops its lines")
	t.check(lines.nearest(Vector3(5.4, 1.5, 0), 1.0).is_empty(), "and they aren't found")
	lines.shift(Vector3(100, 0, -50))
	hit = lines.nearest(Vector3(110, 0.3, -49.5), 1.0)
	t.check(not hit.is_empty() and hit.id == kerb and hit.point.is_equal_approx(Vector3(110, 0, -50)),
			"shifting moves every line")
	t.check(lines.nearest(Vector3(10, 0.3, 0.5), 1.0).is_empty(), "and nothing is left where they were")
	t.check(lines.line(kerb).pts[2].is_equal_approx(Vector3(120, 0, -30)), "every point moves")
	var start := Time.get_ticks_usec()
	for i in 1000:
		lines.nearest(Vector3(100 + cos(i) * 30, 0.2, sin(i) * 30 - 50), 1.2)
	var per := (Time.get_ticks_usec() - start) / 1000.0
	t.check(per < 200.0, "nearest is quick (%.1f µs)" % per)


# --- Skating ------------------------------------------------------------------

func test_push(t) -> void:
	var y: Array = await _yard(t)
	var s: Skater = y[1]
	s.place(Vector3(-60, 0.0, 1.5), Vector3.RIGHT)
	_drive(s, 10, _nothing)
	t.check(s.state == Skater.State.SKATE and s.is_on_floor(), "the skater stands on the road")
	var speeds := []
	var over := false
	for second in 10:
		_drive(s, 60, _push_east)
		speeds.append(s.speed)
		over = over or s.speed > Skater.PUSH_TOP + 0.001
	t.check(speeds[0] > 2.0 and speeds[0] < speeds[2] and speeds[2] < speeds[9], "pushing speeds you up (%s)" % [speeds])
	t.check(speeds[9] > Skater.PUSH_TOP * 0.95 and not over, "and stops at top speed (%.2f)" % speeds[9])
	t.check(absf(s.global_position.z - 1.5) < 0.05, "pushing straight goes straight")
	var top: float = speeds[9]
	_drive(s, 120, _nothing)
	t.check(s.speed < top and s.speed > top * 0.75, "letting go coasts (%.2f)" % s.speed)
	var ticks := _drive(s, 240, _brake_west, func() -> bool: return s.speed < 0.3)
	t.check(s.speed < 0.3 and ticks < 120, "pulling back stops you (%d ticks)" % ticks)
	# Carving: steering bends the way round, faster when slow.
	s.place(Vector3(-40, 0.0, 1.5), Vector3.RIGHT)
	_drive(s, 120, _push_east)
	var before := s.heading
	_drive(s, 30, _carve_left)
	var turned := rad_to_deg(before.angle_to(s.heading))
	t.check(turned > 20.0 and turned < 75.0, "half a second of carving turns %.0f°" % turned)
	_free(y)


func test_steer_by_keys(t) -> void:
	var y: Array = await _yard(t)
	var s: Skater = y[1]
	s.place(Vector3(-60, 0.0, 1.5), Vector3.RIGHT)
	_drive(s, 10, _nothing)
	# The first tick of a held key is a nudge, not a full stick.
	Input.action_press("move_right")
	s.input.from_actions(Basis.IDENTITY, s.heading, true, DT)
	Input.action_release("move_right")
	t.check(s.input.stick.x > 0.0 and s.input.stick.x < 0.3, "a key ramps in (%.2f)" % s.input.stick.x)
	_keys(s, 12, ["move_right"])
	_keys(s, 20, [])
	t.check(s.input.stick.length() < 0.05, "and ramps out when let go")
	s.place(Vector3(-60, 0.0, 1.5), Vector3.RIGHT)
	_drive(s, 5, _nothing)
	# Forward pushes along the way you face, whichever way the camera looks.
	var turned := Basis(Vector3.UP, 2.2)
	_keys(s, 180, ["move_forward"], Callable(), turned)
	t.check(s.speed > 3.0 and s.heading.dot(Vector3.RIGHT) > 0.99, "W pushes the way you face (%.2f)" % s.speed)
	t.check(absf(s.global_position.z - 1.5) < 0.05, "straight on, with the camera turned")
	# Right turns right, left turns left, at any camera angle.
	var before := s.heading
	_keys(s, 30, ["move_forward", "move_right"], Callable(), turned)
	t.check(s.heading.z > 0.2 and before.signed_angle_to(s.heading, Vector3.UP) < -0.3, "D turns you right (%.2f)" % s.heading.z)
	_keys(s, 60, ["move_forward", "move_left"], Callable(), turned)
	t.check(s.heading.z < before.z - 0.2, "and A turns you left")
	# Down brakes, and holding it from rest does not send you backwards.
	var stopped := _keys(s, 240, ["move_back"], func() -> bool: return s.speed < 0.3)
	t.check(s.speed < 0.3 and stopped < 120, "S brakes (%d ticks)" % stopped)
	var rest := s.global_position
	_keys(s, 60, ["move_back"])
	t.check(s.global_position.distance_to(rest) < 0.1, "and holding it at rest stays put")
	# From rest, left and right turn on the spot.
	var at := s.heading
	_keys(s, 30, ["move_right"])
	t.check(rad_to_deg(at.angle_to(s.heading)) > 40.0, "you can turn on the spot")
	# The camera setting keeps the old way: the stick points where you go.
	s.place(Vector3(-60, 0.0, 1.5), Vector3.RIGHT)
	_drive(s, 5, _nothing)
	_keys(s, 90, ["move_forward"], Callable(), Basis.IDENTITY, false)
	t.check(s.input.relative == false and s.heading.dot(Vector3.FORWARD) > 0.9, "with steering by the camera, up is away from it")
	_free(y)


func test_push_across(t) -> void:
	var s := Skater.new()
	s.visuals = false
	t.add_child(s)
	s.set_physics_process(false)
	var along := Vector3.FORWARD
	s.input.clear()
	s.input.relative = true
	s.input.stick = Vector2(1, 0.4)
	t.check(is_equal_approx(s._push_across(along), 1.0), "on a line, right is right with steering by the stick")
	s.input.stick = Vector2(-0.5, 0)
	t.check(is_equal_approx(s._push_across(along), -0.5), "and left is left")
	s.input.relative = false
	s.input.move = Vector3.RIGHT
	t.check(is_equal_approx(s._push_across(along), 1.0), "the camera way reads the world direction (right of a line going north)")
	s.queue_free()


func test_tricks(t) -> void:
	var y: Array = await _yard(t)
	var s: Skater = y[1]
	s.place(Vector3(-60, 0.0, 1.5), Vector3.RIGHT)
	_drive(s, 70, _push_east)
	s.take_events()
	_drive(s, 5, _trick_spin)
	t.check(_find(s.take_events(), "trick").is_empty(), "the trick button does nothing on the ground")
	# A spin on the way up counts when you land it.
	var seen := await _trick_jump(t, s, _trick_spin, 6)
	t.check(not seen.is_empty() and seen.name == "Spin", "a jump and Trick is a spin (%s)" % [seen])
	t.check(s.line_count >= 1, "and it joins the line")
	_drive(s, 90, _nothing, func() -> bool: return s.state == Skater.State.SKATE)
	_drive(s, 30, _nothing)
	t.check(s.body.transform.basis.y.is_equal_approx(Vector3.UP) and absf(s._trick_angle) < 0.01, "the body comes down upright")
	# The stick picks it.
	seen = await _trick_jump(t, s, _trick_up, 6)
	t.check(not seen.is_empty() and seen.name == "Flip" and s._trick_flip, "up flips forward")
	seen = await _trick_jump(t, s, _trick_down, 6)
	t.check(not seen.is_empty() and seen.name == "Backflip" and s._trick_dir < 0.0, "down flips back")
	seen = await _trick_jump(t, s, _trick_left, 6)
	t.check(not seen.is_empty() and seen.name == "Spin" and s._trick_dir < 0.0, "left spins left")
	# The body turns while it's done.
	_drive(s, 30, _nothing)
	_drive(s, 1, _jump_now)
	_drive(s, 6, _nothing)
	_drive(s, 1, _trick_up)
	_drive(s, 14, _nothing)
	t.check(s.state == Skater.State.AIR and not s.body.transform.basis.y.is_equal_approx(Vector3.UP), "the body is turned mid-trick")
	# Too late in the air: landing cuts it short and it doesn't count.
	_drive(s, 90, _nothing, func() -> bool: return s.state == Skater.State.SKATE)
	_drive(s, 30, _nothing)
	s.take_events()
	seen = await _trick_jump(t, s, _trick_spin, 28)
	t.check(seen.is_empty(), "a trick pressed too late to finish doesn't count")
	_drive(s, 20, _nothing)
	t.check(s.body.transform.basis.y.is_equal_approx(Vector3.UP), "and the body is upright again")
	_free(y)


## Jumps, waits `wait` ticks and presses Trick with `fill`, then flies on to
## the ground. Returns the trick event, or {}.
func _trick_jump(_t, s: Skater, fill: Callable, wait: int) -> Dictionary:
	_drive(s, 40, _nothing, func() -> bool: return s.state == Skater.State.SKATE and s.is_on_floor())
	s.take_events()
	_drive(s, 1, _jump_now)
	_drive(s, wait, _nothing)
	_drive(s, 1, fill)
	var events := []
	for i in 120:
		_drive(s, 1, _nothing)
		events.append_array(s.take_events())
		if s.state == Skater.State.SKATE and s.is_on_floor():
			break
	return _find(events, "trick")


func test_jump(t) -> void:
	var y: Array = await _yard(t)
	var s: Skater = y[1]
	s.place(Vector3(-40, 0.0, 1.5), Vector3.RIGHT)
	_drive(s, 70, _push_east)
	s.take_events()
	var take_off := s.speed
	var start_y := s.global_position.y
	var top := 0.0
	var air := 0
	for i in 120:
		s.input.clear()
		s.input.move = Vector3.RIGHT
		s.input.jump = i == 0
		s.step(DT)
		top = maxf(top, s.global_position.y - start_y)
		if s.state == Skater.State.AIR:
			air += 1
		elif air > 0:
			break
	t.check(top > 1.2 and top < 1.7, "a jump goes about a metre and a half up (%.2f)" % top)
	t.check(air > 30 and air < 60 and s.state == Skater.State.SKATE, "and lands (%d ticks up)" % air)
	var kinds := _kinds(s.take_events())
	t.check(kinds.has("jump") and kinds.has("land") and not kinds.has("stumble"), "jump, land, no stumble (%s)" % [kinds])
	t.check(s.speed > take_off * 0.85, "landing keeps the speed (%.1f of %.1f)" % [s.speed, take_off])
	_free(y)


func test_kerb_step(t) -> void:
	# Rolling at the kerb gets you up onto the pavement.
	var y: Array = await _yard(t)
	var s: Skater = y[1]
	s.place(Vector3(-30, 0.0, 1.0), Vector3.FORWARD)
	_drive(s, 150, _push_north)
	t.check(s.global_position.z < -4.5 and absf(s.global_position.y - Yard.CURB) < 0.02,
			"rolls up the kerb (%s)" % s.global_position)
	_free(y)


func test_stairs(t) -> void:
	var y: Array = await _yard(t)
	var s: Skater = y[1]
	var w: Dictionary = y[2]
	# Down the flight from the terrace, rolling, not falling.
	s.place(Vector3(STAIR_LANE, w.terrace.y, w.terrace.z), Vector3.BACK)
	var air := 0
	for i in 300:
		s.input.clear()
		s.input.move = Vector3.BACK
		s.step(DT)
		if s.state == Skater.State.AIR:
			air += 1
		if s.global_position.z > -6.0:
			break
	t.check(s.global_position.z > -6.0 and s.state == Skater.State.SKATE, "rolls down the steps")
	t.check(air < 10, "without leaving the ramp (%d ticks in the air)" % air)
	# And up them with a run at it.
	s.place(Vector3(STAIR_LANE, 0.0, 2.0), Vector3.FORWARD)
	_drive(s, 420, _push_north, func() -> bool: return s.global_position.z < -16.0)
	t.check(s.global_position.z < -16.0 and absf(s.global_position.y - w.terrace.y) < 0.05,
			"rolls up the steps to the terrace (%s)" % s.global_position)
	_free(y)


# --- Grinding -----------------------------------------------------------------

func test_handrail(t) -> void:
	var y: Array = await _yard(t)
	var s: Skater = y[1]
	var w: Dictionary = y[2]
	var lines: Lines = w.lines
	s.place(w.terrace, Vector3.BACK)
	_drive(s, 10, _nothing)
	var events: Array[Dictionary] = []
	var lowest_lean := 0.0
	var grind_ticks := 0
	var rail_top: Vector3 = w.rail_top
	for i in 600:
		s.input.clear()
		if s.state == Skater.State.GRIND:
			grind_ticks += 1
			lowest_lean = maxf(lowest_lean, absf(s.balance))
			_steady(s)
		else:
			s.input.move = Vector3.BACK
			s.input.jump = s.state == Skater.State.SKATE and s.global_position.z > rail_top.z - 1.7 and grind_ticks == 0
		s.input.grind = grind_ticks == 0 or s.state == Skater.State.GRIND
		s.step(DT)
		events.append_array(s.take_events())
		if grind_ticks > 0 and s.state == Skater.State.SKATE:
			break
	var start := _find(events, "grind_start")
	var end := _find(events, "grind_end")
	t.check(not start.is_empty() and start.id == w.rail and start.line_kind == Lines.Kind.HANDRAIL,
			"jumping at the rail with grind held gets on it")
	t.check(not end.is_empty() and end.reason == "end", "rides it to its end (%s)" % [end])
	t.check(not end.is_empty() and end.length > lines.length(w.rail) * 0.85,
			"top to bottom (%.1f of %.1f m)" % [end.get("length", 0.0), lines.length(w.rail)])
	t.check(_find(events, "bail").is_empty() and _find(events, "stumble").is_empty(), "no bail, no stumble")
	t.check(s.state == Skater.State.SKATE and s.global_position.y < 0.3 and s.global_position.z > -8.0,
			"lands at the bottom (%s)" % s.global_position)
	t.check(s.speed > 6.0, "with speed from the slope (%.1f)" % s.speed)
	t.check(lowest_lean < 0.9, "balanced all the way (%.2f)" % lowest_lean)
	_free(y)


func test_kerb(t) -> void:
	var y: Array = await _yard(t)
	var s: Skater = y[1]
	var w: Dictionary = y[2]
	s.place(Vector3(-55, 0.0, -3.3), Vector3.RIGHT)
	_drive(s, 90, _push_east)
	var events: Array[Dictionary] = []
	var ridden := 0
	for i in 400:
		s.input.clear()
		s.input.grind = ridden < 240
		if s.state == Skater.State.GRIND:
			ridden += 1
			_steady(s)
			s.input.jump = ridden == 240
		else:
			s.input.move = Vector3.RIGHT
		s.step(DT)
		events.append_array(s.take_events())
		if ridden >= 240 and s.state == Skater.State.SKATE:
			break
	var start := _find(events, "grind_start")
	var end := _find(events, "grind_end")
	t.check(not start.is_empty() and start.id == w.kerb, "rolling alongside the kerb with grind held gets on it")
	t.check(ridden >= 240 and not end.is_empty() and end.reason == "jump", "four seconds on it, then a jump off")
	t.check(not end.is_empty() and end.length > 18.0, "a long grind (%.1f m)" % end.get("length", 0.0))
	t.check(s.state == Skater.State.SKATE, "and lands")
	# Left alone on a long line, the lean tips you off, slowly.
	s.place(Vector3(-55, 0.0, -3.3), Vector3.RIGHT)
	_drive(s, 90, _push_east)
	var alone := 0
	for i in 900:
		s.input.clear()
		s.input.grind = alone == 0
		if s.state == Skater.State.GRIND:
			alone += 1
		else:
			s.input.move = Vector3.RIGHT
		s.step(DT)
		if alone > 0 and s.state != Skater.State.GRIND:
			break
	t.check(alone > 90 and alone < 900, "an unbalanced grind lasts a while, then tips you off (%.1f s)" % (alone * DT))
	_free(y)


# --- Wall rides ---------------------------------------------------------------

func test_wall_ride(t) -> void:
	var y: Array = await _yard(t)
	var s: Skater = y[1]
	s.place(Vector3(-20.0, Yard.CURB, -7.3), Vector3.RIGHT)
	var events: Array[Dictionary] = []
	var on_wall := 0
	for i in 400:
		s.input.clear()
		s.input.move = Vector3(1, 0, -0.3).normalized() if i > 80 else Vector3.RIGHT
		s.input.jump = i == 100
		s.input.grind = i > 100
		s.step(DT)
		events.append_array(s.take_events())
		if s.state == Skater.State.WALL:
			on_wall += 1
		if on_wall > 0 and s.state == Skater.State.SKATE:
			break
	var ride := _find(events, "wall_ride")
	var end := _find(events, "wall_end")
	t.check(not ride.is_empty(), "jumping beside the facade with grind held rides it")
	t.check(on_wall >= 60 and not end.is_empty() and end.seconds >= 1.0,
			"for over a second (%.2f s)" % end.get("seconds", 0.0))
	t.check(on_wall <= int(Skater.WALL_TIME / DT) + 2, "and no more than two")
	t.check(s.state == Skater.State.SKATE and absf(s.global_position.y - Yard.CURB) < 0.05, "then lands")
	t.check(_find(events, "stumble").is_empty(), "on its feet")
	# A kick off the wall.
	s.place(Vector3(-20.0, Yard.CURB, -7.3), Vector3.RIGHT)
	events.clear()
	var kicked := false
	on_wall = 0
	for i in 300:
		s.input.clear()
		if s.state == Skater.State.WALL:
			on_wall += 1
		s.input.move = Vector3(1, 0, -0.3).normalized() if i > 80 else Vector3.RIGHT
		s.input.jump = i == 100 or on_wall == 30
		s.input.grind = i > 100 and not kicked
		s.step(DT)
		for e in s.take_events():
			kicked = kicked or e.kind == "wall_kick"
		if kicked and s.state == Skater.State.SKATE:
			break
	t.check(kicked and s.global_position.z > -6.0, "jumping kicks off the wall (%s)" % s.global_position)
	_free(y)


# --- Climbing -----------------------------------------------------------------

func test_climb(t) -> void:
	var y: Array = await _yard(t)
	var s: Skater = y[1]
	var w: Dictionary = y[2]
	var roof: Dictionary = w.roofs[0]
	s.place(Vector3(-32.0, Yard.CURB, -6.5), Vector3.FORWARD)
	var events: Array[Dictionary] = []
	var grabbed := false
	for i in 900:
		s.input.clear()
		s.input.move = Vector3.FORWARD * 0.6
		s.input.stick = Vector2(0, 1)
		s.step(DT)
		events.append_array(s.take_events())
		grabbed = grabbed or (s.state == Skater.State.CLIMB and s.climb_id == w.pipe)
		if not _find(events, "climb_top").is_empty():
			break
	t.check(grabbed, "pushing at the drainpipe grabs it")
	t.check(not _find(events, "climb_top").is_empty(), "climbing it reaches the top")
	_drive(s, 60, _nothing)
	t.check(s.state == Skater.State.SKATE and s.is_on_floor(), "standing")
	t.check(absf(s.global_position.y - roof.y) < 0.05 and roof.rect.has_point(Vector2(s.global_position.x, s.global_position.z)),
			"on the roof (%s)" % s.global_position)
	# Roll about up there: the parapet keeps you on.
	_drive(s, 120, _push_south)
	t.check(absf(s.global_position.y - roof.y) < 0.05, "the parapet stops you rolling off")
	# The fire escape, up a little and back down.
	s.place(Vector3(-25.0, Yard.CURB, -6.2), Vector3.FORWARD)
	events.clear()
	_drive(s, 120, _climb_up, func() -> bool: return s.state == Skater.State.CLIMB and s.global_position.y > 3.0)
	t.check(s.state == Skater.State.CLIMB and s.climb_id == w.escape, "the fire escape climbs too")
	_drive(s, 200, _climb_down, func() -> bool: return s.state == Skater.State.SKATE)
	t.check(s.state == Skater.State.SKATE and absf(s.global_position.y - Yard.CURB) < 0.05, "and back down to the street")
	# Jumping lets go and kicks back off the wall.
	s.place(Vector3(-32.0, Yard.CURB, -6.5), Vector3.FORWARD)
	_drive(s, 120, _climb_up, func() -> bool: return s.state == Skater.State.CLIMB and s.global_position.y > 2.5)
	_drive(s, 1, _jump_now)
	_drive(s, 10, _nothing)
	t.check(s.state == Skater.State.AIR and s.global_position.z > -7.4, "jump lets go of the pipe")
	_free(y)


func test_roof_drop(t) -> void:
	var y: Array = await _yard(t)
	var s: Skater = y[1]
	var w: Dictionary = y[2]
	var roof: Dictionary = w.roofs[0]
	s.place(Vector3(-30.0, roof.y, -16.0), Vector3.BACK)
	_drive(s, 10, _nothing)
	s.flow = 0.5
	var events: Array[Dictionary] = []
	for i in 400:
		s.input.clear()
		s.input.move = Vector3.BACK
		s.input.jump = s.state == Skater.State.SKATE and s.global_position.z > -10.4
		s.step(DT)
		events.append_array(s.take_events())
		if s.global_position.y < 1.0 and s.state == Skater.State.SKATE:
			break
	var stumble := _find(events, "stumble")
	t.check(s.state == Skater.State.SKATE and absf(s.global_position.y - Yard.CURB) < 0.3,
			"over the parapet and down to the street (%s)" % s.global_position)
	t.check(not stumble.is_empty() and stumble.height > 10.0, "a long drop stumbles (%s)" % [stumble])
	t.check(s.flow < 0.5 and s.flow > 0.0, "and costs some Flow (%.2f)" % s.flow)
	_drive(s, 90, _push_south)
	t.check(s.stumble <= 0.0 and s.speed > 1.0, "then skates on")
	_free(y)


# --- Flow, lines and the lock -------------------------------------------------

func test_flow(t) -> void:
	var y: Array = await _yard(t)
	var s: Skater = y[1]
	s.place(Vector3(-55, 0.0, -3.3), Vector3.RIGHT)
	_drive(s, 10, _nothing)
	s.flow = 0.5
	_drive(s, 180, _nothing)
	t.check(s.flow < 0.5 and s.flow > 0.45, "standing still drains Flow slowly (%.3f)" % s.flow)
	s.flow = 0.0
	_drive(s, 180, _push_east)
	var skated := s.flow
	t.check(skated > 0.0 and skated < 0.05, "skating builds it slowly (%.3f)" % skated)
	# Grinding the kerb, hopping off and back on: a line of two.
	var events: Array[Dictionary] = []
	var grinds := 0
	var hop := 0
	for i in 400:
		s.input.clear()
		s.input.move = Vector3.RIGHT
		s.input.grind = grinds < 2 or s.state == Skater.State.GRIND
		if s.state == Skater.State.GRIND:
			_steady(s)
			hop += 1
			s.input.jump = grinds == 1 and hop == 45
		s.step(DT)
		for e in s.take_events():
			events.append(e)
			if e.kind == "grind_start":
				grinds += 1
				hop = 0
		if grinds >= 2 and hop > 45:
			break
	var gained := s.flow - skated
	t.check(grinds >= 2 and s.line_count >= 2, "two grinds make a line (%d)" % s.line_count)
	t.check(not _find(events, "line").is_empty(), "the line is told")
	t.check(gained > skated * 3.0, "grinding builds Flow fast (%.3f against %.3f)" % [gained, skated])
	# Off the line and onto flat ground for a moment ends it.
	_drive(s, 1, _jump_now)
	_drive(s, 60, _nothing)
	events.clear()
	_drive(s, 120, _push_east)
	events.append_array(s.take_events())
	t.check(s.line_count == 0 and not _find(events, "line_end").is_empty(), "flat ground ends the line")
	_free(y)


func test_lock(t) -> void:
	var y: Array = await _yard(t)
	var s: Skater = y[1]
	s.place(Vector3(-40, 0.0, 1.5), Vector3.RIGHT)
	_drive(s, 60, _push_east)
	s.lock(true)
	var at := s.global_position
	_drive(s, 60, _push_east)
	t.check(s.state == Skater.State.PAINT and s.global_position.distance_to(at) < 0.001, "locked to paint, nothing moves")
	s.lock(false)
	_drive(s, 60, _push_east)
	t.check(s.state == Skater.State.SKATE and s.global_position.x > at.x + 1.0, "let go, skating again")
	# Painting from a drainpipe goes back to hanging on it.
	s.place(Vector3(-32.0, Yard.CURB, -6.5), Vector3.FORWARD)
	_drive(s, 120, _climb_up, func() -> bool: return s.state == Skater.State.CLIMB and s.global_position.y > 3.0)
	at = s.global_position
	s.lock(true)
	_drive(s, 30, _climb_up)
	s.lock(false)
	t.check(s.state == Skater.State.CLIMB and s.global_position.distance_to(at) < 0.001, "painting from a climb")
	s.pick_up(true)
	_drive(s, 30, _push_east)
	t.check(s.state == Skater.State.PICKED_UP, "picked up holds too")
	s.pick_up(false)
	_free(y)


# --- The camera ---------------------------------------------------------------

func test_camera_level(t) -> void:
	var y: Array = await _yard(t)
	var s: Skater = y[1]
	var w: Dictionary = y[2]
	var cam := StreetCamera.new()
	cam.target = s
	cam.interpolated = false
	(y[0] as Node3D).add_child(cam)
	cam.set_process(false)
	var worst := [0.0, 0, 0]
	# The handrail, with a nudge of the stick partway down.
	s.place(w.terrace, Vector3.BACK)
	cam.snap()
	var rail_top: Vector3 = w.rail_top
	var grinding := 0
	for i in 400:
		s.input.clear()
		if s.state == Skater.State.GRIND:
			grinding += 1
			_steady(s)
		else:
			s.input.move = Vector3.BACK
			s.input.jump = s.state == Skater.State.SKATE and s.global_position.z > rail_top.z - 1.7 and grinding == 0
		s.input.grind = grinding == 0 or s.state == Skater.State.GRIND
		s.step(DT)
		cam.update(DT, Vector2(0.8, -0.5) if grinding > 10 and grinding < 30 else Vector2.ZERO)
		_level(cam, s, w, worst)
		if grinding > 0 and s.state == Skater.State.SKATE and s.speed < 9.0:
			break
	t.check(grinding > 20, "the camera watched a grind")
	# Along the facade.
	s.place(Vector3(-20.0, Yard.CURB, -7.3), Vector3.RIGHT)
	cam.snap()
	var riding := 0
	for i in 300:
		s.input.clear()
		s.input.move = Vector3(1, 0, -0.3).normalized() if i > 80 else Vector3.RIGHT
		s.input.jump = i == 100
		s.input.grind = i > 100
		s.step(DT)
		cam.update(DT, Vector2.ZERO)
		_level(cam, s, w, worst)
		if s.state == Skater.State.WALL:
			riding += 1
	t.check(riding > 30, "the camera watched a wall ride")
	t.check(worst[0] < 0.0001, "the horizon stays level (worst tilt %.6f)" % worst[0])
	t.check(worst[1] == 0, "the camera never goes inside a building (%d frames)" % worst[1])
	t.check(worst[2] == 0, "and always sees the skater (%d frames blocked)" % worst[2])
	_free(y)


## Records the camera's roll, whether it's inside a building, and whether
## a wall hides the skater.
func _level(cam: StreetCamera, s: Skater, w: Dictionary, worst: Array) -> void:
	worst[0] = maxf(worst[0], absf(cam.global_basis.x.y))
	var p := cam.global_position
	for b in w.buildings:
		var r: Rect2 = (b.rect as Rect2).grow(0.1)
		if r.has_point(Vector2(p.x, p.z)) and p.y < b.deck:
			worst[1] += 1
	var space := cam.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p, s.global_position + Vector3.UP * 1.2, Kit.LAYER_WORLD)
	if not space.intersect_ray(q).is_empty():
		worst[2] += 1


# --- The body -----------------------------------------------------------------

func test_body(t) -> void:
	var y: Array = await _yard(t, true)
	var s: Skater = y[1]
	t.check(s.person != null and s.person.skates, "a writer on skates")
	for clip in Skater.CLIPS:
		t.check(s.person.clip_path(clip) != "", "the %s clip is there" % clip)
	s.place(Vector3(-40, 0.0, 1.5), Vector3.RIGHT)
	_drive(s, 60, _push_east)
	t.check(absf(s.body.global_basis.z.normalized().dot(Vector3.RIGHT) - 1.0) < 0.05, "the body faces the way it rolls")
	t.check(absf(s.body.global_basis.x.y) < 0.01, "and stands up straight going straight")
	_free(y)


# --- Helpers ------------------------------------------------------------------

## A yard with a skater stepped by hand: [stage, skater, world].
func _yard(t, visuals := false) -> Array:
	var stage := Node3D.new()
	stage.name = "Yard"
	t.add_child(stage)
	var w := Yard.build(stage, visuals)
	var s := Skater.new()
	s.visuals = visuals
	s.lines = w.lines
	stage.add_child(s)
	s.set_physics_process(false)
	await t.get_tree().physics_frame
	await t.get_tree().physics_frame
	return [stage, s, w]


func _free(y: Array) -> void:
	(y[0] as Node).queue_free()


## Steps `n` ticks with `fill(input)` setting the controls, stopping early
## once `until` holds. Returns the ticks run.
func _drive(s: Skater, n: int, fill: Callable, until := Callable()) -> int:
	for i in n:
		s.input.clear()
		fill.call(s.input)
		s.step(DT)
		if until.is_valid() and until.call():
			return i + 1
	return n


## Steps `n` ticks with the keyboard actions in `held` pressed, read the way
## play reads them: steered by the stick (`relative`) or by `camera`. Stops
## early once `until` holds. Returns the ticks run.
func _keys(s: Skater, n: int, held: Array, until := Callable(), camera := Basis.IDENTITY, relative := true) -> int:
	var ran := n
	for a in held:
		Input.action_press(a)
	for i in n:
		s.input.from_actions(camera, s.heading, relative, DT)
		s.step(DT)
		if until.is_valid() and until.call():
			ran = i + 1
			break
	for a in held:
		Input.action_release(a)
	return ran


## Pushes the stick against the lean, as a player would.
func _steady(s: Skater) -> void:
	var dir := s.grind_direction()
	var side := Vector3(dir.x, 0, dir.z).normalized().cross(Vector3.UP)
	s.input.move = side * clampf(-s.balance * 3.0, -1.0, 1.0)


func _find(events: Array, kind: String) -> Dictionary:
	for e in events:
		if e.kind == kind:
			return e
	return {}


func _kinds(events: Array) -> Array:
	var out := []
	for e in events:
		out.append(e.kind)
	return out


func _nothing(_inp: SkaterInput) -> void:
	pass


func _push_east(inp: SkaterInput) -> void:
	inp.move = Vector3.RIGHT


func _push_north(inp: SkaterInput) -> void:
	inp.move = Vector3.FORWARD


func _push_south(inp: SkaterInput) -> void:
	inp.move = Vector3.BACK


func _brake_west(inp: SkaterInput) -> void:
	inp.move = Vector3.LEFT


func _carve_left(inp: SkaterInput) -> void:
	inp.move = Vector3.FORWARD


func _climb_up(inp: SkaterInput) -> void:
	inp.move = Vector3.FORWARD * 0.6
	inp.stick = Vector2(0, 1)


func _climb_down(inp: SkaterInput) -> void:
	inp.stick = Vector2(0, -1)


func _trick_spin(inp: SkaterInput) -> void:
	inp.trick_pressed = true


func _trick_up(inp: SkaterInput) -> void:
	inp.trick_pressed = true
	inp.stick = Vector2(0, 1)


func _trick_down(inp: SkaterInput) -> void:
	inp.trick_pressed = true
	inp.stick = Vector2(0, -1)


func _trick_left(inp: SkaterInput) -> void:
	inp.trick_pressed = true
	inp.stick = Vector2(-1, 0)


func _jump_now(inp: SkaterInput) -> void:
	inp.jump = true

