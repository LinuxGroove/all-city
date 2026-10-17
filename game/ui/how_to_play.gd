class_name HowToPanel
extends Control
## How to play: one page on skating, Flow, paint, the Buff and the respect
## list, beside the controls by action (as GameConfig.ACTIONS binds them,
## shown for the keyboard or the controller, whichever was used last).
## Opened from the title and the pause menu, over whatever is behind.

signal closed

## The page's sections: a heading and a few lines.
const SECTIONS := [
	["Skate", "Push to build speed, crouch to pump, lean into corners. Grind any rail, ledge, kerb or fence, wall ride a facade and kick off it, and climb fire escapes and drainpipes to the roofs. A long drop costs Flow, never more."],
	["Flow", "Moving builds Flow, and a line of moves that never touches flat ground builds it fastest. Stop and it drains. Flow is your paint: it fills your cans."],
	["Paint", "Hold Paint by a wall and follow the guide. A tag takes seconds; bigger work takes longer and goes over smaller. The harder a wall is to reach and the more people see it, the more it's worth."],
	["The Buff", "The city's cleaners come at dawn and take paint down, the walls most people see first."],
	["Respect", "Homes, schools, places of worship, hospitals, cemeteries and memorials are never painted. The town shows them with a quiet \"not here\"."],
]

## Each control: the action, what it does, and what to show on a keyboard
## when the action's own key doesn't say it all.
const CONTROLS := [
	["move_forward", "Skate and steer", "W A S D"],
	["look_right", "Camera (it eases back on its own)", "Mouse"],
	["jump", "Jump", ""],
	["crouch", "Crouch and pump; slide", ""],
	["grind", "Grind (hold by a rail), then balance", ""],
	["paint", "Paint (hold by a wall), then follow the guide", ""],
	["trick", "Trick (in the air)", ""],
	["look_back", "Look back", ""],
	["boost", "Boost (spends Flow)", ""],
	["map", "Map, spots and the crew", ""],
	["pause", "Pause", ""],
]

var _done: Button
var _scroll: ScrollContainer


func _init() -> void:
	name = "HowToPlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(CityTheme.INK, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "DarkPanel"
	center.add_child(panel)
	LGScreenFit.center(panel, Vector2(24, 24))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	col.add_child(LGUi.label("How to play", "HeaderMedium"))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(1160, 600)
	col.add_child(_scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	_scroll.add_child(row)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 6)
	words.custom_minimum_size.x = 640
	row.add_child(words)
	for s in SECTIONS:
		words.add_child(LGUi.label(str(s[0]).to_upper(), "CapsLabel"))
		var body := LGUi.label(s[1])
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size.x = 640
		body.add_theme_font_size_override("font_size", 19)
		words.add_child(body)
	var keys := VBoxContainer.new()
	keys.add_theme_constant_override("separation", 6)
	row.add_child(keys)
	keys.add_child(LGUi.label("CONTROLS", "CapsLabel"))
	for c in CONTROLS:
		keys.add_child(ControlRow.new(c[0], c[1], c[2]))
	_done = LGUi.button("Done", close, 300)
	_done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_done)


func open() -> void:
	visible = true
	_scroll.scroll_vertical = 0
	CityTheme.focus(_done)


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _input(event: InputEvent) -> void:
	# Done is the only button, so up and down scroll the page.
	if not visible:
		return
	var step := 0
	if event.is_action_pressed("ui_down", true):
		step = 1
	elif event.is_action_pressed("ui_up", true):
		step = -1
	if step != 0:
		_scroll.scroll_vertical += step * 60
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## Every action's text on the page, for tests.
func control_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for c in CONTROLS:
		out.append(c[1])
	return out


## One control: the button for the action on the device used last, and
## what it does.
class ControlRow:
	extends HBoxContainer

	var action := ""
	var keyboard := ""
	var _icon: TextureRect
	var _key: Label

	func _init(p_action: String, p_text: String, p_keyboard: String) -> void:
		action = p_action
		keyboard = p_keyboard
		add_theme_constant_override("separation", 10)
		custom_minimum_size.y = 38
		var slot := CenterContainer.new()
		slot.custom_minimum_size = Vector2(118, 38)
		add_child(slot)
		_icon = TextureRect.new()
		_icon.custom_minimum_size = Vector2(36, 36)
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.add_child(_icon)
		_key = LGUi.label("", "CapsLabel")
		_key.add_theme_color_override("font_color", CityTheme.YELLOW)
		slot.add_child(_key)
		var what := LGUi.label(p_text)
		what.add_theme_font_size_override("font_size", 19)
		what.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(what)

	func _ready() -> void:
		var router := get_node_or_null("/root/LGInput")
		if router:
			# A method, so the connection goes away with the row.
			router.device_changed.connect(_on_device_changed)
		_refresh()

	func _on_device_changed(_family: String) -> void:
		_refresh()

	func _refresh() -> void:
		var router := get_node_or_null("/root/LGInput")
		var pad: bool = router != null and router.is_gamepad()
		var tex: Texture2D = null
		if router and (pad or keyboard == ""):
			tex = router.glyph_for_action(action)
		_icon.texture = tex
		_icon.visible = tex != null
		_key.visible = tex == null
		if tex == null:
			_key.text = keyboard if keyboard != "" and not pad else (router.label_for_action(action) if router else action)
