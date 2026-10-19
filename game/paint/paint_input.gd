class_name PaintInput
extends RefCounted
## One step of a writer's controls for painting: tests and bots fill it
## themselves, play fills it from the input actions.

## The paint button is held.
var paint := false
## The left stick: x right, y down (as Input.get_vector gives it).
var stick := Vector2.ZERO


## The controls as they are now.
static func from_actions() -> PaintInput:
	var i := PaintInput.new()
	i.paint = Input.is_action_pressed("paint")
	i.stick = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return i


static func make(p_paint: bool, p_stick := Vector2.ZERO) -> PaintInput:
	var i := PaintInput.new()
	i.paint = p_paint
	i.stick = p_stick
	return i
