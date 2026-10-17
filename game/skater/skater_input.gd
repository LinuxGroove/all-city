class_name SkaterInput
extends RefCounted
## One tick of the skater's controls. The play scene fills it from the pad,
## keyboard and mouse with `from_actions()`; tests and pilots fill it
## themselves.

## The left stick as a direction on the ground in the world (y is 0), length
## 0 to 1, turned by the camera so pushing up always heads away from it.
var move := Vector3.ZERO
## The left stick itself: x right, y up. Climbing reads it as up and down.
var stick := Vector2.ZERO
## Pressed this tick.
var jump := false
var jump_held := false
var crouch := false
var grind := false
## Pressed this tick.
var grind_pressed := false
var paint := false
var trick := false
var boost := false
var look_back := false


func clear() -> void:
	move = Vector3.ZERO
	stick = Vector2.ZERO
	jump = false
	jump_held = false
	crouch = false
	grind = false
	grind_pressed = false
	paint = false
	trick = false
	boost = false
	look_back = false


## Reads the controls for this physics tick. `camera_basis` is the camera's
## (only its heading counts).
func from_actions(camera_basis: Basis) -> void:
	stick = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var forward := Vector3(-camera_basis.z.x, 0.0, -camera_basis.z.z)
	if forward.length() < 0.01:
		# Looking straight down: the camera's up is the way ahead.
		forward = Vector3(camera_basis.y.x, 0.0, camera_basis.y.z)
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var right := forward.cross(Vector3.UP)
	move = right * stick.x + forward * stick.y
	if move.length() > 1.0:
		move = move.normalized()
	jump = Input.is_action_just_pressed("jump")
	jump_held = Input.is_action_pressed("jump")
	crouch = Input.is_action_pressed("crouch")
	grind = Input.is_action_pressed("grind")
	grind_pressed = Input.is_action_just_pressed("grind")
	paint = Input.is_action_pressed("paint")
	trick = Input.is_action_pressed("trick")
	boost = Input.is_action_pressed("boost")
	look_back = Input.is_action_pressed("look_back")
