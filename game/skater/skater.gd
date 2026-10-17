class_name Skater
extends CharacterBody3D
## A writer on inline skates: every move, tuned in one place, on the fixed
## physics tick, so it plays the same at any frame rate and tests can drive
## it headless through `input` and `step()`.
##
## Moves: push and carve, crouch to tuck and pump, jump; grind any line in
## `lines` (hold grind near it), balancing on the stick; wall ride a facade
## (hold grind in the air beside it) and kick off it; climb drainpipes and
## fire escapes and mantle onto the roof; drop from anywhere (a long fall
## costs Flow and a stumble, never a life). The clips are placeholders from
## the Universal Animation Library, and the body is turned and tipped in
## code where no clip fits.
##
## Flow is the paint: plain skating builds it slowly, grinds, wall rides,
## air and climbs fast, and a line of moves without touching flat ground
## multiplies it. The HUD reads `flow`, `line_count`, `state_name()`,
## `balance` and the events from `take_events()`.

enum State { SKATE, AIR, GRIND, WALL, CLIMB, PAINT, PICKED_UP }

const STATE_NAMES := ["skate", "air", "grind", "wall", "climb", "paint", "picked_up"]

# Skating.
## Pushing alone tops out here (m/s); slopes, pumps and boost go past it.
const PUSH_TOP := 9.0
## The push at a standstill; it tapers off towards PUSH_TOP.
const PUSH_ACCEL := 6.0
const MAX_SPEED := 17.0
## Coasting slows by this (m/s²), plus AIR_DRAG times the speed squared.
const ROLL_DRAG := 0.3
const AIR_DRAG := 0.004
## Pulling the stick against the way you roll stops you (a T-stop).
const BRAKE := 8.0
const BRAKE_ANGLE := 2.3
## How fast the skater carves when slow (radians a second); faster, the
## turn widens so it never pulls more than MAX_CARVE (m/s²) sideways.
const TURN_SLOW := 4.2
const MAX_CARVE := 16.0
## Speed lost per radian of carving.
const CARVE_DRAG := 0.04
## A tuck (crouch) halves the drag and turns less.
const TUCK_DRAG := 0.5
const TUCK_TURN := 0.7
## Letting go of a tuck pumps: this much speed, up to PUMP_TOP.
const PUMP := 1.0
const PUMP_TOP := 10.5
const PUMP_TUCK := 0.25
const PUMP_COOLDOWN := 0.45
const BOOST_TOP := 13.0
const BOOST_ACCEL := 7.0
## Flow a second of boost spends.
const BOOST_COST := 0.18
## Gravity along slopes and rails (the air uses GRAVITY, a livelier pull).
const SLOPE_GRAVITY := 9.8
## Kerbs this high are rolled up without a jump.
const STEP_HEIGHT := 0.25

# The air.
const GRAVITY := 20.0
const MAX_FALL := 32.0
const JUMP_SPEED := 7.6
## Steering in the air: turning the way you fly, and a little speed when slow.
const AIR_TURN := 1.5
const AIR_ACCEL := 2.5
const COYOTE := 0.12
const JUMP_BUFFER := 0.12
## Steering is weak for a moment after kicking off a wall, so the kick
## carries you away from it.
const KICK_STEER_LOCK := 0.35
## Falls longer than this stumble on landing and cost Flow.
const HARD_FALL := 4.5
const STUMBLE_TIME := 0.6
## How far a stumble tips the body forward.
const STUMBLE_PITCH := 0.45
const FALL_FLOW := 0.02

# Grinding.
## How near the feet must be to a line to snap on: in the air, and rolling
## alongside one (rails a metre up count).
const GRIND_REACH := 1.0
const GRIND_REACH_GROUND := 1.15
## How far below a line the feet can be and still snap up onto it.
const GRIND_BELOW := 0.6
const GRIND_MIN := 2.5
const GRIND_DRAG := 0.25
const GRIND_JUMP := 7.0
## Sideways speed from the stick when jumping off a line.
const GRIND_KICK := 2.5
## Joints sharper than this throw you off the line.
const GRIND_CORNER := deg_to_rad(100.0)
## The lean on a rail: how fast it tips over by itself, the drift that
## starts it, how hard the stick corrects it, and the damping. Forgiving:
## alone it takes a couple of seconds to fall, and a held stick saves it.
const BALANCE_TIP := 1.6
const BALANCE_DRIFT := 0.35
const BALANCE_CORRECT := 4.5
const BALANCE_DAMP := 1.4

# Wall rides.
const WALL_MIN_SPEED := 4.5
const WALL_TIME := 2.0
const WALL_GRAVITY := 2.4
const WALL_LIFT := 1.6
## From the body's middle to the wall, to start a ride.
const WALL_REACH := 0.85
const WALL_KICK_OUT := 5.0
const WALL_KICK_UP := 7.2
const WALL_DRAG := 0.5
## The body leans out from the wall, wheels on it.
const WALL_LEAN := deg_to_rad(50.0)

# Climbing.
const CLIMB_REACH := 0.9
const CLIMB_SPEED := 3.4
## The body's middle stands this far out from a climb line.
const CLIMB_OFF := 0.3
## Hands above the feet: at the top, the hands reach the parapet.
const GRIP := 1.75
const MANTLE_TIME := 0.7

# Flow (0 to 1), per second.
const FLOW_SPEED := 0.012
const FLOW_GRIND := 0.10
const FLOW_WALL := 0.12
const FLOW_AIR := 0.035
const FLOW_CLIMB := 0.07
const FLOW_DRAIN := 0.012
## A move's own lump of Flow as it starts.
const FLOW_MOVE := 0.02
## Seconds on flat ground before a line of moves ends.
const LINE_GRACE := 0.6
const LINE_MAX_MULT := 4.0

## Every clip the body plays (placeholders from the Universal Animation
## Library).
const CLIPS := ["Idle", "Sprint", "Jump_Land", "Crouch_Idle", "NinjaJump_Land", "Jump_Start", "NinjaJump_Idle",
	"Swim_Fwd", "ClimbUp_1m", "Pistol_Aim_Neutral", "Hit_Knockback"]

## Below this the skater is put back where they last stood (holes in a
## town's ground; it isn't a death).
const KILL_Y := -40.0
## How fast the body catches up with a snap onto a line or a wall.
const SNAP_EASE := 14.0

## This tick's controls.
var input := SkaterInput.new()
## Every grind and climb line, set by whoever builds the world.
var lines: Lines
## True to read the controls each tick (the play scene); tests and pilots
## leave it off and fill `input`.
var reads_controls := false
## False to skip the body (for quick headless tests).
var visuals := true
## The writer's look, for Person.make.
var female := false
var look_seed := 0
var look := {}

var state := State.SKATE
## Speed along the ground, the line or the wall.
var speed := 0.0
## The way the skater rolls, flat and unit length.
var heading := Vector3.FORWARD
## The way the body faces, flat and unit length.
var facing := Vector3.FORWARD
var flow := 0.0
## Moves chained without touching flat ground.
var line_count := 0
## The lean on a line, -1 (left) to 1 (right); past either end you fall.
var balance := 0.0
## Scales how fast the lean tips over (a setting could make it easier).
var balance_scale := 1.0
var crouching := false
## Seconds left of a stumble after a long fall.
var stumble := 0.0
## The height of the last ground stood on, for the camera.
var last_ground_y := 0.0
var ground_normal := Vector3.UP
## The line being ground, or -1.
var grind_id := -1
var grind_kind := -1
## The wall being ridden: its outward normal.
var wall_normal := Vector3.ZERO
## The climb line held, or -1, and the way out from its wall.
var climb_id := -1
var climb_out := Vector3.ZERO
## Ticks of play.
var ticks := 0

var body: Node3D
var person: Person

var _events: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _buffer := 0.0
var _coyote := 0.0
var _jumped := false
var _air_time := 0.0
var _peak_y := 0.0
var _carve := 0.0
var _tuck_time := 0.0
var _pump_cool := 0.0
var _boosting := false
var _flat_time := 0.0
var _still_time := 0.0
var _last_safe := Vector3.ZERO
var _no_grind_id := -1
var _no_grind_time := 0.0
var _no_climb_id := -1
var _no_climb_time := 0.0
var _wall_cool := 0.0
## A wall ride ended without a kick: no more until the ground or a line.
var _wall_spent := false
var _steer_lock := 0.0
# The line being ground.
var _g_seg := 0
var _g_t := 0.0
var _g_dir := 1
var _g_len := 0.0
var _g_tangent := Vector3.FORWARD
var _lean_v := 0.0
var _drift := 0.0
var _drift_target := 0.0
var _drift_time := 0.0
# The wall.
var _w_dir := Vector3.FORWARD
var _w_time := 0.0
# The climb.
var _c_base := Vector3.ZERO
var _c_top := Vector3.ZERO
var _c_height := 0.0
var _c_v := 0.0
var _c_mantle := -1.0
var _c_from := Vector3.ZERO
var _c_to := Vector3.ZERO
# Painting and being picked up remember where they came from.
var _held_from := State.SKATE
# The body.
var _offset := Vector3.ZERO
var _yaw := PI
var _lean := 0.0
## Forward tip of the body (a stumble), in radians.
var _pitch := 0.0
var _land_time := 0.0
var _clip := ""
var _freeze_in := 0.0


func _init() -> void:
	collision_layer = Kit.LAYER_SKATER
	collision_mask = Kit.LAYER_WORLD
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.3
	floor_constant_speed = true
	floor_stop_on_slope = true
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.85
	add_child(shape)
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	_rng.seed = 24


func _ready() -> void:
	if visuals and person == null:
		person = Person.make("writer", female, look_seed, look)
		body.add_child(person)
		_play("Idle")


func _physics_process(delta: float) -> void:
	if reads_controls:
		var cam := get_viewport().get_camera_3d()
		input.from_actions(cam.global_basis if cam else Basis.IDENTITY)
	step(delta)


## Puts the skater down at `at`, facing `face`, at rest.
func place(at: Vector3, face := Vector3.FORWARD) -> void:
	global_position = at
	velocity = Vector3.ZERO
	speed = 0.0
	face = Vector3(face.x, 0, face.z)
	heading = face.normalized() if face.length() > 0.01 else Vector3.FORWARD
	facing = heading
	_yaw = atan2(facing.x, facing.z)
	state = State.AIR
	grind_id = -1
	climb_id = -1
	stumble = 0.0
	balance = 0.0
	_air_time = 0.0
	_peak_y = at.y
	_jumped = false
	_offset = Vector3.ZERO
	last_ground_y = at.y
	_last_safe = at
	reset_physics_interpolation()
	_update_body(0.0)


## Moves the skater with the world when the town moves back round its
## origin (TownView.shifted), mid-move or not.
func shift(by: Vector3) -> void:
	global_position += by
	_last_safe += by
	_c_base += by
	_c_top += by
	_c_from += by
	_c_to += by
	reset_physics_interpolation()


## The state as a word, for the HUD and play tests.
func state_name() -> String:
	return STATE_NAMES[state]


## The events since the last call: {"kind": ...} with grind_start,
## grind_end, jump, land, stumble, bail, wall_ride, wall_end, wall_kick,
## climb_start, climb_top, climb_end, pump, boost, line, line_end.
func take_events() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out


## How much a move's Flow is multiplied by the line it's in.
func line_mult() -> float:
	return clampf(1.0 + 0.5 * (line_count - 1), 1.0, LINE_MAX_MULT)


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## The way along the line being ground (unit length), or zero.
func grind_direction() -> Vector3:
	return _g_tangent if state == State.GRIND else Vector3.ZERO


## Holds the skater still to paint (the paint system calls this), and lets
## go again to whatever they were doing (skating, or hanging on a climb).
func lock(on: bool) -> void:
	_hold(State.PAINT, on)


## Held by someone (Civic, a crewmate's help): no controls, no moves.
func pick_up(on: bool) -> void:
	_hold(State.PICKED_UP, on)


func is_held() -> bool:
	return state == State.PAINT or state == State.PICKED_UP


func _hold(as_state: State, on: bool) -> void:
	if on:
		if not is_held():
			_held_from = state
		if state == State.GRIND:
			_leave_grind("held")
		elif state == State.WALL:
			_leave_wall(false)
		state = as_state
		velocity = Vector3.ZERO
		speed = 0.0
	elif state == as_state:
		if _held_from == State.CLIMB and climb_id >= 0:
			state = State.CLIMB
			_c_v = 0.0
		else:
			state = State.AIR
			_air_time = 0.0
			_peak_y = global_position.y
			_jumped = true


## One tick of movement. Tests call this directly.
func step(dt: float) -> void:
	ticks += 1
	if input.jump:
		_buffer = JUMP_BUFFER
	else:
		_buffer = maxf(_buffer - dt, 0.0)
	_no_grind_time = maxf(_no_grind_time - dt, 0.0)
	_no_climb_time = maxf(_no_climb_time - dt, 0.0)
	_wall_cool = maxf(_wall_cool - dt, 0.0)
	_steer_lock = maxf(_steer_lock - dt, 0.0)
	_pump_cool = maxf(_pump_cool - dt, 0.0)
	_land_time = maxf(_land_time - dt, 0.0)
	match state:
		State.SKATE:
			_skate(dt)
		State.AIR:
			_air(dt)
		State.GRIND:
			_grind(dt)
		State.WALL:
			_wall(dt)
		State.CLIMB:
			_climb(dt)
		State.PAINT, State.PICKED_UP:
			velocity = Vector3.ZERO
	_flow(dt)
	if global_position.y < KILL_Y:
		place(_last_safe + Vector3.UP * 0.5, heading)
		_emit("rescue")
	_update_body(dt)


# --- Skating ------------------------------------------------------------------

func _skate(dt: float) -> void:
	_coyote = COYOTE
	_jumped = false
	if input.grind and stumble <= 0.0 and (_try_grind(true) or _try_climb(true)):
		return
	if stumble <= 0.0 and _wants_climb() and _try_climb(true):
		return
	var n := get_floor_normal() if is_on_floor() else Vector3.UP
	ground_normal = n
	stumble = maxf(stumble - dt, 0.0)
	var control := stumble <= 0.0
	var was_crouching := crouching
	crouching = control and input.crouch
	var m := input.move.length() if control else 0.0
	var pushing := false
	_carve = 0.0
	if m > 0.2:
		var want := input.move / m
		var angle := heading.signed_angle_to(want, Vector3.UP)
		if absf(angle) > BRAKE_ANGLE and speed > 0.3:
			speed = maxf(speed - BRAKE * m * dt, 0.0)
		else:
			var rate := minf(TURN_SLOW, MAX_CARVE / maxf(speed, 0.1)) * m
			if crouching:
				rate *= TUCK_TURN
			if speed < 1.0:
				# Slow enough to turn on the spot.
				rate = TURN_SLOW * 2.0
			var turn := clampf(angle, -rate * dt, rate * dt)
			heading = heading.rotated(Vector3.UP, turn).normalized()
			_carve = turn / dt
			speed -= absf(turn) * CARVE_DRAG * speed
			if not crouching and absf(angle) < 1.7 and speed < PUSH_TOP:
				pushing = true
				var push := PUSH_ACCEL * m * maxf(cos(angle), 0.3) * (1.0 - speed / PUSH_TOP)
				speed = minf(speed + push * dt, PUSH_TOP)
	# A tuck held long enough pumps when let go.
	if crouching:
		_tuck_time += dt
	else:
		if was_crouching and _tuck_time >= PUMP_TUCK and speed > 2.0 and _pump_cool <= 0.0:
			speed = minf(speed + PUMP, maxf(speed, PUMP_TOP))
			_pump_cool = PUMP_COOLDOWN
			_emit("pump")
		_tuck_time = 0.0
	var boosting := control and input.boost and flow > 0.01 and not crouching
	if boosting:
		if not _boosting:
			_emit("boost")
		if speed < BOOST_TOP:
			speed = minf(speed + BOOST_ACCEL * dt, BOOST_TOP)
		flow = maxf(flow - BOOST_COST * dt, 0.0)
	_boosting = boosting
	var along := _along_floor(heading, n)
	speed -= SLOPE_GRAVITY * along.y * (1.1 if crouching else 1.0) * dt
	if not pushing and not boosting or speed > PUSH_TOP:
		var drag := (ROLL_DRAG + AIR_DRAG * speed * speed) * (TUCK_DRAG if crouching else 1.0)
		speed = maxf(speed - drag * dt, 0.0) if speed > 0.0 else minf(speed + drag * dt, 0.0)
	if speed < 0.0:
		# Rolled back down a slope: now heading the other way.
		heading = -heading
		speed = -speed
		along = _along_floor(heading, n)
	speed = minf(speed, MAX_SPEED)
	velocity = along * speed - n * 0.5
	if _buffer > 0.0 and control:
		_buffer = 0.0
		_jump(along * speed)
		return
	var before := velocity
	move_and_slide()
	var stepped := is_on_floor() and is_on_wall() and _step_up(before, dt)
	if is_on_wall() and not stepped:
		# Rolled into something: keep only the speed that slid along it.
		var real := get_real_velocity()
		var flat := Vector3(real.x, 0, real.z)
		if flat.length() < speed * 0.97:
			speed = flat.length()
			if flat.length() > 0.3:
				heading = flat.normalized()
	if not is_on_floor():
		_start_air()
		return
	last_ground_y = global_position.y
	ground_normal = get_floor_normal()
	if ground_normal.y > 0.98:
		_last_safe = global_position
		_flat_time += dt
		if _flat_time > LINE_GRACE:
			_end_line()
	else:
		_flat_time = 0.0


## The way along the floor for a heading.
static func _along_floor(dir: Vector3, n: Vector3) -> Vector3:
	var v := dir - n * dir.dot(n)
	return v.normalized() if v.length() > 0.001 else dir


func _jump(from_velocity: Vector3) -> void:
	velocity = from_velocity
	velocity.y = maxf(velocity.y, 0.0) + JUMP_SPEED
	crouching = false
	_jumped = true
	_start_air()
	_emit("jump", {"from": "ground"})


func _start_air() -> void:
	state = State.AIR
	_air_time = 0.0
	_peak_y = global_position.y


## Rolls up a low kerb if there's room.
func _step_up(before: Vector3, dt: float) -> bool:
	var flat := Vector3(before.x, 0, before.z)
	if flat.length() < 0.5:
		return false
	var ahead := flat.normalized() * maxf(flat.length() * dt, 0.1)
	var up := Vector3.UP * STEP_HEIGHT
	if test_move(global_transform, up):
		return false
	var raised := global_transform.translated(up)
	if test_move(raised, ahead):
		return false
	global_position += up + ahead
	apply_floor_snap()
	return true


# --- The air ------------------------------------------------------------------

func _air(dt: float) -> void:
	_air_time += dt
	_coyote = maxf(_coyote - dt, 0.0)
	crouching = false
	if _buffer > 0.0 and _coyote > 0.0 and not _jumped:
		_buffer = 0.0
		_jump(velocity)
		return
	if input.grind and (_try_grind(false) or _try_climb(false) or _try_wall(false)):
		return
	if _wants_climb() and _try_climb(false):
		return
	var flat := Vector3(velocity.x, 0, velocity.z)
	var m := input.move.length()
	if m > 0.2:
		var want := input.move / m
		var grip := 0.2 if _steer_lock > 0.0 else 1.0
		if flat.length() > 0.5:
			var angle := flat.signed_angle_to(want, Vector3.UP)
			var turn := AIR_TURN * m * grip * dt
			if absf(angle) < BRAKE_ANGLE:
				flat = flat.rotated(Vector3.UP, clampf(angle, -turn, turn))
		if flat.dot(want) < 3.0:
			flat += want * AIR_ACCEL * m * grip * dt
	velocity.x = flat.x
	velocity.z = flat.z
	velocity.y = maxf(velocity.y - GRAVITY * dt, -MAX_FALL)
	if flat.length() > 0.5:
		heading = flat.normalized()
	var before := velocity
	_move_fast(dt)
	_peak_y = maxf(_peak_y, global_position.y)
	if is_on_floor() and before.y <= 0.01:
		_land()
	elif input.grind and is_on_wall():
		_try_wall(true)


## move_and_slide in short steps when falling fast, so the ground is met
## rather than sunk into for a tick.
func _move_fast(dt: float) -> void:
	var steps := clampi(ceili(absf(velocity.y) * dt / 0.12), 1, 4)
	if steps == 1:
		move_and_slide()
		return
	velocity /= steps
	for k in steps:
		move_and_slide()
		if is_on_floor() or is_on_wall():
			break
	velocity *= steps


func _land() -> void:
	var drop := _peak_y - global_position.y
	state = State.SKATE
	_wall_spent = false
	var flat := Vector3(velocity.x, 0, velocity.z)
	speed = flat.length()
	if speed > 0.3:
		heading = flat.normalized()
	last_ground_y = global_position.y
	_flat_time = 0.0
	_land_time = 0.3
	_emit("land", {"height": drop, "speed": speed})
	if drop > HARD_FALL:
		stumble = STUMBLE_TIME + minf(drop - HARD_FALL, 15.0) * 0.03
		speed *= 0.4
		var cost := clampf(0.05 + (drop - HARD_FALL) * FALL_FLOW, 0.05, 0.35)
		flow = maxf(flow - cost, 0.0)
		_end_line()
		_emit("stumble", {"height": drop, "flow": cost})


# --- Grinding -----------------------------------------------------------------

## Snaps onto the nearest grind line if the feet are near it and moving
## along it.
func _try_grind(on_ground: bool) -> bool:
	if lines == null:
		return false
	var feet := global_position
	var hit := lines.nearest(feet, GRIND_REACH_GROUND if on_ground else GRIND_REACH, Lines.GRINDS)
	if hit.is_empty() or (hit.id == _no_grind_id and _no_grind_time > 0.0):
		return false
	var point: Vector3 = hit.point
	var v := _along_floor(heading, ground_normal) * speed if on_ground else velocity
	var flat := Vector3(v.x, 0, v.z)
	# Not down through the floor, and not far up unless rising to it.
	if point.y < feet.y - (0.35 if on_ground else GRIND_REACH):
		return false
	if not on_ground and point.y > feet.y + GRIND_BELOW and v.y < 0.5:
		return false
	var tangent: Vector3 = hit.tangent
	var along := v.dot(tangent)
	var flat_t := Vector3(tangent.x, 0, tangent.z)
	if flat.length() > 0.5 and flat_t.length() > 0.1:
		if absf(flat.normalized().dot(flat_t.normalized())) < (0.4 if on_ground else 0.25):
			return false
	var dir := 1 if along >= 0.0 else -1
	if absf(along) < 0.25 * v.length():
		dir = 1 if facing.dot(tangent) >= 0.0 else -1
	var on_speed := maxf(absf(along), flat.length() * 0.75)
	if on_speed < GRIND_MIN:
		return false
	if lines.room(hit.id, hit.seg, hit.t, dir) < 0.6:
		return false
	_start_grind(hit, dir, on_speed)
	return true


## Starts a grind on a line found by `Lines.nearest()`, going `dir` along it.
func start_grind(hit: Dictionary, dir: int, at_speed: float) -> void:
	_start_grind(hit, dir, at_speed)


func _start_grind(hit: Dictionary, dir: int, at_speed: float) -> void:
	grind_id = hit.id
	grind_kind = hit.kind
	_g_seg = hit.seg
	_g_t = hit.t
	_g_dir = dir
	_g_len = 0.0
	_g_tangent = (hit.tangent as Vector3) * dir
	speed = clampf(at_speed, GRIND_MIN, MAX_SPEED)
	_offset += global_position - hit.point
	global_position = hit.point
	velocity = _g_tangent * speed
	state = State.GRIND
	crouching = false
	_wall_spent = false
	balance = 0.0
	_lean_v = _rng.randf_range(-0.12, 0.12)
	_drift = 0.0
	_drift_time = 0.0
	# Grind stance: side on to the line, turned from where you came.
	var side := _flat(_g_tangent).cross(Vector3.UP)
	facing = side if side.dot(facing) >= 0.0 else -side
	_bump_line()
	_emit("grind_start", {"line_kind": grind_kind, "id": grind_id})


func _grind(dt: float) -> void:
	var t_dir := _g_tangent
	speed += -SLOPE_GRAVITY * t_dir.y * dt
	speed -= (GRIND_DRAG + AIR_DRAG * speed * speed) * dt
	speed = minf(speed, MAX_SPEED)
	if speed < 0.8:
		velocity = t_dir * speed + Vector3.UP * 1.0
		_leave_grind("stall")
		return
	_balance(dt, t_dir)
	if absf(balance) >= 1.0:
		_bail(t_dir)
		return
	if _buffer > 0.0:
		_buffer = 0.0
		var side := _flat(t_dir).cross(Vector3.UP)
		velocity = t_dir * speed + Vector3.UP * GRIND_JUMP + side * input.move.dot(side) * GRIND_KICK
		velocity.y = maxf(velocity.y, GRIND_JUMP * 0.8)
		_leave_grind("jump")
		_jumped = true
		_emit("jump", {"from": "grind"})
		return
	var moved := lines.advance(grind_id, _g_seg, _g_t, speed * dt * _g_dir)
	var turn: float = moved.turn
	_g_seg = moved.seg
	_g_t = moved.t
	_g_len += speed * dt
	global_position = moved.point
	_g_tangent = (moved.tangent as Vector3) * _g_dir
	if turn > GRIND_CORNER:
		velocity = t_dir * speed + Vector3.UP * 1.5
		_leave_grind("corner")
		return
	if turn > 0.0:
		speed *= lerpf(1.0, 0.75, turn / GRIND_CORNER)
		var side := _flat(_g_tangent).cross(Vector3.UP)
		facing = side if side.dot(facing) >= 0.0 else -side
	velocity = _g_tangent * speed
	if moved.ended:
		global_position += _g_tangent * float(moved.over)
		velocity = _g_tangent * speed + Vector3.UP * 0.8
		_leave_grind("end")


## The lean on a line: it drifts and tips over by itself, and the stick
## (pushed against the lean) brings it back.
func _balance(dt: float, t_dir: Vector3) -> void:
	_drift_time -= dt
	if _drift_time <= 0.0:
		_drift_target = _rng.randf_range(-1.0, 1.0) * BALANCE_DRIFT
		_drift_time = _rng.randf_range(0.6, 1.4)
	_drift = move_toward(_drift, _drift_target, dt * 0.8)
	var side := _flat(t_dir).cross(Vector3.UP)
	var push := input.move.dot(side)
	_lean_v += ((balance * BALANCE_TIP + _drift) * balance_scale + push * BALANCE_CORRECT) * dt
	_lean_v *= exp(-BALANCE_DAMP * dt)
	balance += _lean_v * dt


func _bail(t_dir: Vector3) -> void:
	var side := _flat(t_dir).cross(Vector3.UP) * signf(balance)
	velocity = t_dir * speed * 0.6 + side * 2.5 + Vector3.UP * 2.0
	_leave_grind("bail")
	flow = maxf(flow - 0.04, 0.0)
	_end_line()
	_emit("bail")


func _leave_grind(reason: String) -> void:
	_emit("grind_end", {"line_kind": grind_kind, "id": grind_id, "length": _g_len, "reason": reason})
	_no_grind_id = grind_id
	_no_grind_time = 0.3
	grind_id = -1
	balance = 0.0
	if reason != "held":
		_start_air()
		_coyote = 0.0 if reason == "jump" else 0.1
		_jumped = reason == "jump"
		var flat := _flat(velocity)
		if flat.length() > 0.3:
			heading = flat.normalized()


# --- Wall rides ---------------------------------------------------------------

## Starts a wall ride on a near-vertical wall beside the skater, if moving
## fast enough along it. `touching` is true when the last move bumped it.
func _try_wall(touching: bool) -> bool:
	if _wall_cool > 0.0 or _wall_spent or _air_time < 0.05:
		return false
	var flat := _flat(velocity)
	if flat.length() < WALL_MIN_SPEED:
		return false
	var hit := {}
	if touching:
		var n := get_wall_normal()
		if absf(n.y) < 0.3:
			hit = _wall_at(-_flat(n).normalized())
	if hit.is_empty():
		var fwd := flat.normalized()
		var right := fwd.cross(Vector3.UP)
		for dir in [right, -right, (right + fwd).normalized(), (-right + fwd).normalized()]:
			var h := _wall_at(dir)
			if not h.is_empty() and (hit.is_empty() or h.distance < hit.distance):
				hit = h
	if hit.is_empty():
		return false
	var n: Vector3 = hit.normal
	var along := flat - n * flat.dot(n)
	if along.length() < WALL_MIN_SPEED * 0.8:
		return false
	wall_normal = n
	_w_dir = along.normalized()
	_w_time = 0.0
	speed = along.length()
	velocity.y = clampf(velocity.y * 0.5, 0.0, 2.0) + WALL_LIFT
	var to := global_position
	var at: Vector3 = hit.position
	to.x = at.x + n.x * 0.32
	to.z = at.z + n.z * 0.32
	_offset += global_position - to
	global_position = to
	state = State.WALL
	heading = _w_dir
	facing = _w_dir
	_bump_line()
	_emit("wall_ride")
	return true


## A wall the body is beside, along `dir` from its middle: {} or {position,
## normal (flat), distance}. Both a knee-high and a head-high ray must hit,
## so low walls and rails don't count.
func _wall_at(dir: Vector3, reach := WALL_REACH) -> Dictionary:
	if not is_inside_tree():
		return {}
	var space := get_world_3d().direct_space_state
	var found := {}
	for h: float in [0.6, 1.4]:
		var from := global_position + Vector3.UP * h
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach, Kit.LAYER_WORLD, [get_rid()])
		var r := space.intersect_ray(q)
		if r.is_empty():
			return {}
		var n: Vector3 = r.normal
		if absf(n.y) > 0.3:
			return {}
		if found.is_empty():
			found = {"position": r.position, "normal": _flat(n).normalized(), "distance": from.distance_to(r.position)}
	return found


func _wall(dt: float) -> void:
	_w_time += dt
	if _buffer > 0.0:
		_buffer = 0.0
		_leave_wall(true)
		return
	if not input.grind or _w_time > WALL_TIME or speed < 3.0:
		_leave_wall(false)
		return
	speed = maxf(speed - WALL_DRAG * dt, 0.0)
	var vy := velocity.y - WALL_GRAVITY * dt
	velocity = _w_dir * speed + Vector3.UP * vy - wall_normal * 0.5
	move_and_slide()
	velocity = _w_dir * speed + Vector3.UP * vy
	if is_on_floor() and vy <= 0.0:
		_emit("wall_end", {"seconds": _w_time})
		_land()
		return
	# Follow the wall's face, or drop when it ends.
	var hit := _wall_at(-wall_normal, 0.32 + 0.45)
	if hit.is_empty():
		_leave_wall(false)
		return
	wall_normal = hit.normal
	_w_dir = (_w_dir - wall_normal * _w_dir.dot(wall_normal)).normalized()
	var at: Vector3 = hit.position
	global_position.x = at.x + wall_normal.x * 0.32
	global_position.z = at.z + wall_normal.z * 0.32
	heading = _w_dir
	facing = _w_dir


func _leave_wall(kick: bool) -> void:
	_emit("wall_end", {"seconds": _w_time})
	_wall_cool = 0.3
	_start_air()
	if kick:
		velocity = _w_dir * speed * 0.9 + wall_normal * WALL_KICK_OUT + Vector3.UP * WALL_KICK_UP
		_jumped = true
		_steer_lock = KICK_STEER_LOCK
		_bump_line()
		_emit("wall_kick")
	else:
		_wall_spent = true
		velocity = _w_dir * speed + wall_normal * 1.2 + Vector3.UP * minf(velocity.y, 0.0)
		_jumped = false
		_coyote = 0.1
	var flat := _flat(velocity)
	if flat.length() > 0.3:
		heading = flat.normalized()
		facing = heading


# --- Climbing -----------------------------------------------------------------

## Pushing at a climb line while slow grabs it, as well as pressing grind.
func _wants_climb() -> bool:
	return input.move.length() > 0.5 and _flat(velocity).length() < 5.0


func _try_climb(on_ground: bool) -> bool:
	if lines == null:
		return false
	var mid := global_position + Vector3.UP * 1.0
	var hit := lines.nearest(mid, CLIMB_REACH, [Lines.Kind.CLIMB])
	if hit.is_empty() or (hit.id == _no_climb_id and _no_climb_time > 0.0):
		return false
	var pts: PackedVector3Array = lines.line(hit.id).pts
	var base := pts[0] if pts[0].y <= pts[pts.size() - 1].y else pts[pts.size() - 1]
	var top := pts[pts.size() - 1] if pts[0].y <= pts[pts.size() - 1].y else pts[0]
	if top.y - global_position.y < GRIP + 0.3:
		return false
	var point: Vector3 = hit.point
	var toward := _flat(point - global_position)
	toward = toward.normalized() if toward.length() > 0.05 else facing
	# Grind grabs it when pressed, or held while slow (so a wall ride past a
	# drainpipe doesn't stop on it); pushing at it slowly grabs it too.
	var slow := _flat(velocity).length() < 5.0
	var grab := input.grind_pressed or (input.grind and slow)
	if not grab and not (slow and input.move.normalized().dot(toward) > 0.6):
		return false
	# The wall behind the line gives the way out; failing that, back the way
	# the skater came.
	var out := -toward
	if is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(mid, Vector3(point.x, mid.y, point.z) + toward * 1.0,
				Kit.LAYER_WORLD, [get_rid()])
		var r := get_world_3d().direct_space_state.intersect_ray(q)
		if not r.is_empty() and absf((r.normal as Vector3).y) < 0.3:
			out = _flat(r.normal).normalized()
	climb_id = hit.id
	climb_out = out
	_c_base = base
	_c_top = top
	_c_height = clampf(global_position.y - base.y, 0.0, top.y - base.y - GRIP)
	# A run-up carries you a little way up.
	_c_v = clampf(_flat(velocity).length() * 0.35, 0.0, CLIMB_SPEED) if not on_ground or speed > 3.0 else 0.0
	_c_mantle = -1.0
	var to := _climb_point()
	_offset += global_position - to
	global_position = to
	velocity = Vector3.ZERO
	speed = 0.0
	state = State.CLIMB
	facing = -out
	heading = facing
	_bump_line()
	_emit("climb_start", {"id": climb_id})
	return true


func _climb_point() -> Vector3:
	var along := (_c_top - _c_base)
	var k := clampf(_c_height / maxf(along.y, 0.01), 0.0, 1.0)
	return _c_base + along * k + climb_out * CLIMB_OFF


func _climb(dt: float) -> void:
	if _c_mantle >= 0.0:
		_mantle(dt)
		return
	if _buffer > 0.0:
		# Let go and kick back off the wall.
		_buffer = 0.0
		velocity = climb_out * 4.0 + Vector3.UP * 4.5
		_no_climb_id = climb_id
		_no_climb_time = 0.6
		climb_id = -1
		_start_air()
		_jumped = true
		facing = climb_out
		heading = climb_out
		_emit("jump", {"from": "climb"})
		return
	var want := clampf(input.stick.y, -1.0, 1.0) * CLIMB_SPEED
	_c_v = move_toward(_c_v, want, 14.0 * dt)
	_c_height += _c_v * dt
	var reach := _c_top.y - _c_base.y - GRIP
	if _c_height >= reach and _c_v > 0.0:
		_c_height = reach
		if _start_mantle():
			return
		_c_v = 0.0
	if _c_height <= 0.0 and _c_v < 0.0:
		# Back on the ground.
		_c_height = 0.0
		global_position = _climb_point()
		_no_climb_id = climb_id
		_no_climb_time = 0.6
		climb_id = -1
		state = State.SKATE
		speed = 0.0
		_emit("climb_end")
		return
	_c_height = clampf(_c_height, 0.0, reach)
	global_position = _climb_point()
	velocity = Vector3.UP * _c_v
	facing = -climb_out


## Finds the roof behind the parapet and starts climbing over onto it.
func _start_mantle() -> bool:
	if not is_inside_tree():
		return false
	var space := get_world_3d().direct_space_state
	for d: float in [1.4, 1.8, 2.3]:
		var spot := _c_top - climb_out * d
		var q := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 1.0, spot - Vector3.UP * 4.0, Kit.LAYER_WORLD,
				[get_rid()])
		var r := space.intersect_ray(q)
		if r.is_empty() or (r.normal as Vector3).y < 0.7 or (r.position as Vector3).y > _c_top.y - 0.3:
			continue
		_c_mantle = 0.0
		_c_from = global_position
		_c_to = r.position
		_emit("mantle")
		return true
	return false


func _mantle(dt: float) -> void:
	_c_mantle += dt / MANTLE_TIME
	var k := clampf(_c_mantle, 0.0, 1.0)
	# Up until the feet clear the parapet, then over and down onto the roof.
	var over := Vector3(_c_from.x, _c_top.y + 0.1, _c_from.z)
	if k < 0.55:
		global_position = _c_from.lerp(over, ease(k / 0.55, 0.6))
	else:
		var j := (k - 0.55) / 0.45
		var p := over.lerp(_c_to, j)
		p.y = lerpf(over.y, _c_to.y, j * j) + sin(j * PI) * 0.15
		global_position = p
	velocity = Vector3.ZERO
	if k >= 1.0:
		global_position = _c_to + Vector3.UP * 0.02
		var height := _c_to.y
		_no_climb_id = climb_id
		_no_climb_time = 0.8
		climb_id = -1
		_c_mantle = -1.0
		state = State.SKATE
		speed = 0.0
		heading = -climb_out
		facing = heading
		last_ground_y = _c_to.y
		_peak_y = _c_to.y
		flow = minf(flow + 0.05 * line_mult(), 1.0)
		_emit("climb_top", {"height": height})


# --- Flow and lines -----------------------------------------------------------

func _flow(dt: float) -> void:
	var mult := line_mult()
	match state:
		State.SKATE:
			if speed > 0.5:
				_still_time = 0.0
				flow += FLOW_SPEED * minf(speed / PUSH_TOP, 1.5) * dt
			else:
				_still_time += dt
				if _still_time > 1.0:
					flow -= FLOW_DRAIN * dt
		State.AIR:
			if _air_time > 0.25:
				flow += FLOW_AIR * mult * dt
		State.GRIND:
			flow += FLOW_GRIND * mult * dt
		State.WALL:
			flow += FLOW_WALL * mult * dt
		State.CLIMB:
			if absf(_c_v) > 0.3 or _c_mantle >= 0.0:
				flow += FLOW_CLIMB * mult * dt
	flow = clampf(flow, 0.0, 1.0)


## A move joins the line (and the line's multiplier grows).
func _bump_line() -> void:
	line_count += 1
	_flat_time = 0.0
	flow = minf(flow + FLOW_MOVE * line_mult(), 1.0)
	if line_count >= 2:
		_emit("line", {"count": line_count})


func _end_line() -> void:
	if line_count >= 2:
		_emit("line_end", {"count": line_count})
	line_count = 0


func _emit(kind: String, extra := {}) -> void:
	var e := {"kind": kind}
	e.merge(extra)
	_events.append(e)
	# Nobody reading (a test, a paused HUD): keep the newest.
	if _events.size() > 64:
		_events.remove_at(0)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


# --- The body -----------------------------------------------------------------

## Turns, tips and poses the body, and picks the clip. Runs on the physics
## tick, so physics interpolation smooths it.
func _update_body(dt: float) -> void:
	var k := 1.0 - exp(-SNAP_EASE * dt) if dt > 0.0 else 1.0
	_offset = _offset.lerp(Vector3.ZERO, k)
	if _offset.length() < 0.002:
		_offset = Vector3.ZERO
	var want_yaw := atan2(facing.x, facing.z)
	var turn_rate := 16.0 if state in [State.GRIND, State.WALL, State.CLIMB] else 10.0
	_yaw = lerp_angle(_yaw, want_yaw, 1.0 - exp(-turn_rate * dt) if dt > 0.0 else 1.0)
	var yaw_basis := Basis(Vector3.UP, _yaw)
	var lean_axis := Vector3(sin(_yaw), 0, cos(_yaw))
	var want_lean := 0.0
	var shift := Vector3.ZERO
	match state:
		State.SKATE:
			# Lean into a carve.
			want_lean = clampf(-_carve * speed * 0.06, -0.45, 0.45)
		State.GRIND:
			lean_axis = _flat(_g_tangent).normalized()
			want_lean = balance * 0.45
		State.WALL:
			lean_axis = _w_dir
			var right := _w_dir.cross(Vector3.UP)
			want_lean = WALL_LEAN * signf(right.dot(wall_normal))
			shift = -wall_normal * 0.28
	_lean = lerpf(_lean, want_lean, 1.0 - exp(-10.0 * dt) if dt > 0.0 else 1.0)
	# A stumble pitches forward over the knees and comes back up.
	var want_pitch := STUMBLE_PITCH * clampf(stumble / STUMBLE_TIME, 0.0, 1.0) if state == State.SKATE else 0.0
	_pitch = lerpf(_pitch, want_pitch, 1.0 - exp(-14.0 * dt) if dt > 0.0 else 1.0)
	var b := Basis(lean_axis.normalized(), _lean) * yaw_basis if lean_axis.length() > 0.01 else yaw_basis
	if _pitch > 0.01:
		b = Basis(yaw_basis.x, _pitch) * b
	if state == State.CLIMB and _c_mantle < 0.0:
		# The swimming clip, stood up against the wall, climbs.
		b = yaw_basis * Basis(Vector3.RIGHT, -PI * 0.5)
		shift = Vector3.UP * 0.95 - climb_out * 0.25
	body.transform = Transform3D(b, _offset + shift)
	if person:
		_pose()


func _pose() -> void:
	match state:
		State.SKATE:
			if stumble > 0.0:
				_play("Jump_Land", 0.08, 0.8)
			elif crouching:
				_play("Crouch_Idle", 0.2)
			elif _land_time > 0.0:
				_play("NinjaJump_Land", 0.05, 1.4)
			elif _boosting or (input.move.length() > 0.2 and speed < PUSH_TOP * 0.97):
				_play("Sprint", 0.25, clampf(0.35 + speed / PUSH_TOP * 0.3, 0.35, 0.7))
			elif speed > 0.5:
				_hold_pose("Jump_Land", 0.62)
			else:
				_play("Idle", 0.3)
		State.AIR:
			if _air_time < 0.18 and _jumped:
				_play("Jump_Start", 0.08, 1.4)
			else:
				_play("NinjaJump_Idle", 0.2)
		State.GRIND, State.WALL:
			_play("Crouch_Idle", 0.1)
		State.CLIMB:
			if _c_mantle >= 0.0:
				_play("ClimbUp_1m", 0.05, 0.67 / MANTLE_TIME)
			else:
				_play("Swim_Fwd", 0.15, absf(_c_v) / CLIMB_SPEED * 1.2)
		State.PAINT:
			_play("Pistol_Aim_Neutral", 0.2)
		State.PICKED_UP:
			_play("Hit_Knockback", 0.1)


func _play(clip: String, blend := 0.2, rate := 1.0) -> void:
	if _clip != clip:
		_clip = clip
		person.play(clip, blend, rate)
	else:
		person.anim.speed_scale = rate


## Holds a clip at one moment, as a stance: it blends in while playing up
## to that moment, then stops there.
func _hold_pose(clip: String, at: float, blend := 0.25) -> void:
	var key := "%s@%s" % [clip, at]
	if _clip != key:
		_clip = key
		_freeze_in = blend
		person.play(clip, blend, 1.0, true)
		person.anim.seek(maxf(person.clip_length(clip) * at - blend, 0.0), false)
	elif _freeze_in > 0.0:
		_freeze_in -= get_physics_process_delta_time()
		if _freeze_in <= 0.0:
			person.anim.speed_scale = 0.0
