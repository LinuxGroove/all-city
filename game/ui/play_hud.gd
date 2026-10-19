class_name PlayHud
extends CanvasLayer
## What a writer sees over the town: Flow along the top left with the line
## you're in, the balance on a grind, the moves just made, the quarter
## you're in (big when you cross into it, then small in the corner), a
## prompt at a wall you can paint and the paint's own line ("Clean",
## "Not here") along the bottom.
##
## The play scene feeds it each frame with [method show_skater], and with
## [method say] and [method prompt]; tests drive it the same way.

## Seconds a new quarter's name stays big, and the moves stay listed.
const QUARTER_SECONDS := 3.5
const MOVE_SECONDS := 2.5
const MOVES := 4
## The events worth a word, and the word.
const WORDS := {"grind_start": "", "wall_ride": "Wall ride", "wall_kick": "Kick", "climb_top": "Up top",
	"stumble": "Stumble", "bail": "Bail", "boost": "Boost", "trick": "Trick", "manual": "Manual",
	"line": ""}

var flow: ProgressBar
var line_label: Label
var state_label: Label
var balance: Control
var moves: Label
var quarter: Label
var quarter_small: Label
var paint_line: Label
var paint_prompt: Label
var guide: Control

var _moves: Array[Dictionary] = []
var _quarter_t := -1.0
var _quarter_id := -2
var _say_t := 0.0


func _init() -> void:
	name = "Hud"
	layer = 10
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# Flow, the line and the moves, top left.
	var col := VBoxContainer.new()
	col.position = Vector2(28, 22)
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	row.add_child(CityTheme.label("FLOW", 20, CityTheme.CYAN, CityTheme.heading()))
	flow = ProgressBar.new()
	flow.custom_minimum_size = Vector2(260, 18)
	flow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flow.max_value = 1.0
	flow.step = 0.001
	flow.show_percentage = false
	flow.add_theme_stylebox_override("background", CityTheme.flat(Color(CityTheme.INK, 0.75), CityTheme.INK, 2))
	flow.add_theme_stylebox_override("fill", CityTheme.flat(CityTheme.CYAN, CityTheme.INK, 2))
	row.add_child(flow)
	line_label = CityTheme.label("", 30, CityTheme.YELLOW, CityTheme.heading(), 8)
	col.add_child(line_label)
	state_label = CityTheme.label("", 18, CityTheme.DIM, CityTheme.text(600), 5)
	col.add_child(state_label)
	balance = _Balance.new()
	balance.custom_minimum_size = Vector2(260, 16)
	balance.visible = false
	col.add_child(balance)
	moves = CityTheme.label("", 22, CityTheme.TEXT, CityTheme.heading(), 6)
	col.add_child(moves)
	# The quarter, big in the upper middle and then small top right.
	quarter = CityTheme.label("", 46, CityTheme.TEXT, CityTheme.heading(), 10)
	quarter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quarter.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	quarter.offset_left = -500
	quarter.offset_right = 500
	quarter.offset_top = 70
	quarter.visible = false
	root.add_child(quarter)
	quarter_small = CityTheme.label("", 18, CityTheme.CREAM, CityTheme.text(640), 5)
	quarter_small.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quarter_small.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	quarter_small.offset_left = -520
	quarter_small.offset_right = -28
	quarter_small.offset_top = 24
	root.add_child(quarter_small)
	# Painting, along the bottom.
	paint_line = CityTheme.label("", 40, CityTheme.TEXT, CityTheme.marker(), 10)
	paint_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paint_line.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	paint_line.offset_left = -400
	paint_line.offset_right = 400
	paint_line.offset_top = -150
	paint_line.offset_bottom = -90
	root.add_child(paint_line)
	paint_prompt = CityTheme.label("", 22, CityTheme.YELLOW, CityTheme.text(700), 6)
	paint_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paint_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	paint_prompt.offset_left = -400
	paint_prompt.offset_right = 400
	paint_prompt.offset_top = -80
	paint_prompt.offset_bottom = -44
	root.add_child(paint_prompt)
	guide = _Guide.new()
	guide.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	guide.offset_left = -64
	guide.offset_right = 64
	guide.offset_top = -290
	guide.offset_bottom = -162
	guide.visible = false
	root.add_child(guide)


## Reads the skater for this frame: Flow, the line, the state and the
## balance, and words for the events (`events` from take_events()).
func show_skater(skater: Skater, events: Array[Dictionary]) -> void:
	flow.value = skater.flow
	line_label.text = "LINE x%d" % skater.line_count if skater.line_count >= 2 else ""
	state_label.text = "%s  %d km/h" % [skater.state_name().capitalize(), roundi(skater.horizontal_speed() * 3.6)]
	balance.visible = skater.state == Skater.State.GRIND
	if balance.visible:
		(balance as _Balance).value = skater.balance
		balance.queue_redraw()
	for e in events:
		var word := _word(e)
		if word != "":
			_moves.push_front({"text": word, "t": MOVE_SECONDS})
	_moves.resize(mini(_moves.size(), MOVES))


func _word(e: Dictionary) -> String:
	var kind := str(e.get("kind", ""))
	if not WORDS.has(kind):
		return ""
	if kind == "grind_start":
		# The line and the grind on it: "Handrail 50-50", "Kerb boardslide".
		var k := int(e.get("line_kind", -1))
		var on := str(Lines.Kind.keys()[k]).capitalize() if k >= 0 and k < Lines.Kind.size() else ""
		var how := str(e.get("trick", ""))
		how = how.to_lower() if how != "" and on != "" and how[0] != "5" else how
		if how == "":
			how = "grind" if on != "" else "Grind"
		return (on + " " + how).strip_edges()
	if kind == "line":
		return ""
	if kind == "trick":
		return str(e.get("name", "Trick"))
	return WORDS[kind]


## The quarter the writer is in: its name shows big when it changes.
func show_quarter(id: int, quarter_name: String) -> void:
	if id == _quarter_id:
		return
	_quarter_id = id
	quarter_small.text = quarter_name
	if quarter_name != "":
		quarter.text = quarter_name.to_upper()
		_quarter_t = QUARTER_SECONDS


## The paint's line along the bottom ("" clears it); it clears itself after
## a few seconds.
func say(text: String) -> void:
	paint_line.text = text
	_say_t = 3.0 if text != "" else 0.0


## The prompt at a wall ("" for none).
func prompt(text: String) -> void:
	paint_prompt.text = text


## While painting: an arrow for the way to push the stick (`dir`, x right and
## y down as the guide runs on the wall) and a dot for where the stick is.
func show_guide(dir: Vector2, stick: Vector2, on: bool) -> void:
	guide.visible = on and dir != Vector2.ZERO
	if guide.visible:
		(guide as _Guide).set_push(dir, stick)


func _process(delta: float) -> void:
	step(delta)


## Moves the timers on (the frame does this; tests call it).
func step(delta: float) -> void:
	for m in _moves:
		m.t -= delta
	_moves = _moves.filter(_fresh)
	var lines := PackedStringArray()
	for m in _moves:
		lines.append(str(m.text))
	moves.text = "\n".join(lines)
	if _quarter_t >= 0.0:
		_quarter_t -= delta
		quarter.visible = _quarter_t > 0.0
		quarter.modulate.a = clampf(_quarter_t / 0.6, 0.0, 1.0)
	if _say_t > 0.0:
		_say_t -= delta
		if _say_t <= 0.0:
			paint_line.text = ""


func _fresh(m: Dictionary) -> bool:
	return float(m.t) > 0.0


## The painting's push: a ring with an arrow for the guide's way and a dot
## for the stick, which turns green when the two agree.
class _Guide:
	extends Control
	var dir := Vector2.ZERO
	var stick := Vector2.ZERO

	func set_push(p_dir: Vector2, p_stick: Vector2) -> void:
		if p_dir != dir or p_stick != stick:
			dir = p_dir
			stick = p_stick
			queue_redraw()

	func _draw() -> void:
		var mid := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 4.0
		var agree := stick.dot(dir) > 0.5
		draw_circle(mid, r, Color(CityTheme.INK, 0.75))
		draw_arc(mid, r, 0.0, TAU, 40, CityTheme.YELLOW, 3.0, true)
		var colour := CityTheme.HIVIS if agree else CityTheme.YELLOW
		var tip := mid + dir * r * 0.78
		var tail := mid - dir * r * 0.5
		draw_line(tail, tip, colour, 8.0, true)
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([tip + dir * 12.0, tip - dir * 6.0 + side * 16.0, tip - dir * 6.0 - side * 16.0]), colour)
		if stick.length() > 0.1:
			draw_circle(mid + stick.limit_length(1.0) * r * 0.6, 8.0, CityTheme.CYAN)


## The grind's balance: a bar with a dot that drifts off the middle.
class _Balance:
	extends Control
	var value := 0.0

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(CityTheme.INK, 0.75))
		var mid := size.x * 0.5
		var safe := size.x * 0.18
		draw_rect(Rect2(mid - safe, 2, safe * 2.0, size.y - 4), Color(CityTheme.HIVIS, 0.35))
		var at := mid + clampf(value, -1.0, 1.0) * (size.x * 0.5 - 6.0)
		var colour := CityTheme.HIVIS if absf(value) < 0.36 else (CityTheme.YELLOW if absf(value) < 0.7 else CityTheme.RED)
		draw_circle(Vector2(at, size.y * 0.5), size.y * 0.5, colour)
