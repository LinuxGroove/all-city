class_name StreetCamera
extends Camera3D
## The calm camera, after Block Party: Skyway's: behind and above the
## skater, looking a little down, blending slowly to new angles. It never
## rolls (the horizon stays level on grinds and wall rides too), shakes,
## punches its zoom or cuts.
##
## It swings round behind the way you're going at the camera/follow setting
## (0 never, 1 quickly). When the keys steer the skater (left and right
## turn them), it keeps right behind them, even standing still, so what's
## ahead of the skater is always ahead on the screen. The right stick and
## the mouse only nudge it: let go and it eases back behind you. With
## follow at 0 the stick turns it for good instead, since nothing else
## would. Something between the camera and the skater lifts it up and over
## the way, or pulls it in gently, never through the wall.

const LOOK_HEIGHT := 1.35
const DISTANCE := 5.6
const PITCH := deg_to_rad(17.0)
## Pitches for climbing (looking up the wall) and the pitch range.
const CLIMB_PITCH := deg_to_rad(4.0)
const PITCH_MIN := deg_to_rad(-12.0)
const PITCH_MAX := deg_to_rad(60.0)
## How far a held nudge can turn the camera, and how fast.
const NUDGE_YAW := deg_to_rad(80.0)
const NUDGE_PITCH := deg_to_rad(30.0)
const NUDGE_RATE := 2.0
const MOUSE_RATE := 0.0035
## Seconds after letting go before a nudge eases back.
const NUDGE_HOLD := 0.7
## The turn rate behind the skater at follow 1 (radians a second, scaled
## by how far there is to go).
const FOLLOW_RATE := 2.4
const FREE_TURN_RATE := 2.2
const BLEND_RATE := 2.4
## The focus rises only when the skater gets this far above their footing,
## so jumps don't bob the view.
const RISE_ALLOWANCE := 2.0
## Pulls in towards the skater gently when something's in the way, and
## eases back out more gently still.
const PULL_IN := 7.0
const PULL_OUT := 1.4
## The camera looks this far past where it sits, to start pulling in early.
const LOOKAHEAD := 0.8
const MIN_DISTANCE := 1.2
const CAST_RADIUS := 0.25
## The fastest it ever swings round, in radians a second.
const MAX_SWING := 1.6
## Following a skater the keys steer: how quickly it catches up (a second's
## fraction, from follow 0 to 1) and the fastest it swings, a little more
## than the skater turns, so a turn is never out of sight.
const CHASE_RATE_MIN := 2.5
const CHASE_RATE_MAX := 8.0
const CHASE_SWING := 4.2
## Easing of the picture itself onto the swung heading while chasing.
const CHASE_YAW_RATE := 10.0
## When something's in the way behind, it climbs this much further (at most)
## to look down over it before it pulls in.
const CLEAR_PITCH_STEP := deg_to_rad(9.0)
const CLEAR_PITCH_STEPS := 5
const CLEAR_IN := 5.0
const CLEAR_OUT := 1.3
## How much of the way back must be open to call it clear.
const CLEAR_ENOUGH := 0.85

var target: Skater
## Where the camera is (radians and metres from the focus), easing towards
## where it wants to be.
var yaw := 0.0
var pitch := PITCH
var distance := DISTANCE
## The heading the camera swings to.
var base_yaw := 0.0
var nudge := Vector2.ZERO
var focus := Vector3.ZERO
var follow := 0.6
var invert_y := false
## False in tests that step the skater by hand: then the camera follows
## its plain transform rather than the interpolated one.
var interpolated := true
## Set by tests and screenshots to drive the stick without input events.
var stick_override := Vector2.INF

var _pull := 0.0
var _clear := 0.0
var _focus_y := 0.0
var _lead := Vector3.ZERO
var _idle := 0.0
var _mouse := Vector2.ZERO
var _back := 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	near = 0.1
	far = 600.0
	_load_settings()
	LGSettings.changed.connect(_on_setting_changed)


func _on_setting_changed(section: String, _key: String, _value: Variant) -> void:
	if section == "camera":
		_load_settings()


func _load_settings() -> void:
	follow = clampf(float(LGSettings.get_value("camera", "follow", 0.6)), 0.0, 1.0)
	fov = float(LGSettings.get_value("camera", "fov", 70.0))
	invert_y = bool(LGSettings.get_value("camera", "invert_y", false))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse += (event as InputEventMouseMotion).relative


## Jumps straight behind the skater with no easing (on arrival and
## respawns; never during play).
func snap() -> void:
	if target == null:
		return
	base_yaw = _behind()
	yaw = base_yaw
	pitch = PITCH
	distance = DISTANCE
	nudge = Vector2.ZERO
	_lead = Vector3.ZERO
	_pull = 0.0
	_clear = 0.0
	_back = 0.0
	var at := _target_origin()
	focus = at
	_focus_y = at.y
	_place(0.0)


## Moves the camera with the world when the town moves back round its
## origin, so nothing on screen jumps.
func shift(by: Vector3) -> void:
	position += by
	focus += by
	_focus_y += by.y


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	update(delta, _read_stick())


func _read_stick() -> Vector2:
	if stick_override != Vector2.INF:
		return stick_override
	var s := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if invert_y:
		s.y = -s.y
	return s


## One frame of camera work, with the right stick's position (x right,
## y down).
func update(delta: float, stick: Vector2) -> void:
	var mouse := _mouse * MOUSE_RATE
	_mouse = Vector2.ZERO
	if invert_y:
		mouse.y = -mouse.y
	var turning := stick.length() > 0.15 or mouse.length() > 0.0001
	if follow <= 0.001:
		# Nothing swings the camera round, so the stick turns it for good.
		base_yaw -= stick.x * FREE_TURN_RATE * delta + mouse.x
		nudge.y = clampf(nudge.y + stick.y * NUDGE_RATE * 0.6 * delta + mouse.y, -NUDGE_PITCH, NUDGE_PITCH)
	elif turning:
		nudge.x = clampf(nudge.x - stick.x * NUDGE_RATE * delta - mouse.x, -NUDGE_YAW, NUDGE_YAW)
		nudge.y = clampf(nudge.y + stick.y * NUDGE_RATE * 0.6 * delta + mouse.y, -NUDGE_PITCH, NUDGE_PITCH)
	if turning:
		_idle = 0.0
	else:
		_idle += delta
		if _idle > NUDGE_HOLD and follow > 0.001:
			nudge = nudge.lerp(Vector2.ZERO, 1.0 - exp(-(0.8 + 2.0 * follow) * delta))
	# Swing round behind the skater's way. When the keys steer the skater the
	# camera keeps right behind them, standing or rolling; otherwise it
	# follows lazily, and only when moving.
	var travel := _travel()
	var chasing := _chasing()
	if chasing:
		var diff := wrapf(_behind() - base_yaw, -PI, PI)
		base_yaw += _swing(diff, lerpf(CHASE_RATE_MIN, CHASE_RATE_MAX, follow), delta, CHASE_SWING)
	elif follow > 0.001 and travel.length() > 1.5:
		var diff := wrapf(_behind() - base_yaw, -PI, PI)
		var pace := clampf(travel.length() / Skater.PUSH_TOP, 0.3, 1.0)
		base_yaw += _swing(diff, FOLLOW_RATE * follow * pace, delta)
	elif target.state == Skater.State.CLIMB:
		base_yaw += _swing(wrapf(_behind() - base_yaw, -PI, PI), 1.5, delta)
	# Looking back swings round smoothly, never a cut.
	var want_back := 1.0 if target.input.look_back else 0.0
	_back = move_toward(_back, want_back, delta * 1.6)
	var k := 1.0 - exp(-BLEND_RATE * delta)
	var want_yaw := base_yaw + nudge.x + PI * smoothstep(0.0, 1.0, _back)
	var yaw_k := 1.0 - exp(-CHASE_YAW_RATE * delta) if chasing else minf(k * 1.6, 1.0)
	yaw = lerp_angle(yaw, want_yaw, yaw_k)
	var want_pitch := (CLIMB_PITCH if target.state == Skater.State.CLIMB else PITCH) + nudge.y
	pitch = lerpf(pitch, clampf(want_pitch, PITCH_MIN, PITCH_MAX), k)
	distance = lerpf(distance, DISTANCE, k)
	_follow_focus(delta)
	_place(delta)


## A step of an eased turn through `diff`, never faster than `limit`.
static func _swing(diff: float, rate: float, delta: float, limit := MAX_SWING) -> float:
	var step := diff * (1.0 - exp(-rate * delta))
	return clampf(step, -limit * delta, limit * delta)


## Whether the camera keeps right behind the skater: the keys steer them
## (they turn on the spot and roll the way they face), they're on their feet
## or in the air, and follow isn't off.
func _chasing() -> bool:
	return follow > 0.001 and target.input.relative \
			and (target.state == Skater.State.SKATE or target.state == Skater.State.AIR)


## The skater's way of travel on the ground.
func _travel() -> Vector3:
	var v := target.velocity
	return Vector3(v.x, 0, v.z)


## The heading that puts the camera behind the skater.
func _behind() -> float:
	if target.state == Skater.State.CLIMB:
		return atan2(target.climb_out.x, target.climb_out.z)
	var dir := _travel()
	if dir.length() < 1.0:
		dir = target.facing if target.state != Skater.State.GRIND else target.heading
	return atan2(-dir.x, -dir.z)


func _target_origin() -> Vector3:
	return target.get_global_transform_interpolated().origin if interpolated else target.global_position


## Follows the skater across quickly, and up and down only to where they
## stand (or ride, or climb), so jumps don't bob the view.
func _follow_focus(delta: float) -> void:
	var at := _target_origin()
	var target_y := at.y
	if target.state == Skater.State.AIR:
		target_y = clampf(target.last_ground_y, at.y - RISE_ALLOWANCE, at.y + 0.3)
	var ky := 1.0 - exp(-(7.0 if target_y < _focus_y else 4.0) * delta)
	_focus_y = lerpf(_focus_y, target_y, ky)
	var lead_target := _travel() * 0.12
	if lead_target.length() > 1.2:
		lead_target = lead_target.normalized() * 1.2
	_lead = _lead.lerp(lead_target, 1.0 - exp(-1.5 * delta))
	var kx := 1.0 - exp(-12.0 * delta)
	focus.x = lerpf(focus.x, at.x + _lead.x, kx)
	focus.z = lerpf(focus.z, at.z + _lead.z, kx)
	focus.y = _focus_y


func _place(delta: float) -> void:
	var look := focus + Vector3.UP * LOOK_HEIGHT
	# Something behind the skater: climb to look down over it first.
	var want_clear := _clear_pitch(look)
	if delta > 0.0:
		var rate_c := CLEAR_IN if want_clear > _clear else CLEAR_OUT
		_clear = lerpf(_clear, want_clear, 1.0 - exp(-rate_c * delta))
	else:
		_clear = want_clear
	var dir := _direction(minf(pitch + _clear, PITCH_MAX))
	var free := _free_distance(look, dir, distance + LOOKAHEAD)
	var want_pull := distance - clampf(free - LOOKAHEAD, MIN_DISTANCE, distance)
	# In smoothly, and back out more smoothly still; but never past a wall.
	if delta > 0.0:
		var rate := PULL_IN if want_pull > _pull else PULL_OUT
		_pull = lerpf(_pull, want_pull, 1.0 - exp(-rate * delta))
	else:
		_pull = want_pull
	var d := clampf(distance - _pull, MIN_DISTANCE, maxf(minf(free, distance), MIN_DISTANCE))
	global_position = look + dir * d
	if not global_position.is_equal_approx(look):
		look_at(look, Vector3.UP)


## From the focus towards the camera, for a pitch above the horizon.
func _direction(p: float) -> Vector3:
	return Vector3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p))


## The least extra pitch (in steps) at which the way back to the camera is
## clear, or the clearest there is.
func _clear_pitch(look: Vector3) -> float:
	var reach := distance + LOOKAHEAD
	var best := 0.0
	var best_free := -1.0
	for i in CLEAR_PITCH_STEPS + 1:
		var extra := CLEAR_PITCH_STEP * i
		if pitch + extra > PITCH_MAX:
			break
		var free := _free_distance(look, _direction(pitch + extra), reach)
		if free >= reach * CLEAR_ENOUGH:
			return extra
		if free > best_free + 0.05:
			best_free = free
			best = extra
	return best


## How far a small sphere can go from `from` along `dir`, up to `dist`,
## before something solid.
func _free_distance(from: Vector3, dir: Vector3, dist: float) -> float:
	if not is_inside_tree():
		return dist
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = CAST_RADIUS
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = dir * dist
	q.collision_mask = Kit.LAYER_WORLD
	var r := get_world_3d().direct_space_state.cast_motion(q)
	if r.is_empty():
		return dist
	return dist * r[0]
