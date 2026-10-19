class_name PauseMenu
extends CanvasLayer
## The pause menu over a town: Resume, Settings, How to play, Note this
## moment (while a play test records), Back to the title and Quit. Opening
## it pauses the game and holds its sound (LGAudio.pause_game); closing it
## lets both go and gives the mouse back to the camera if it had it.
##
## The play scene adds one with [method attach], which also opens it when
## the window loses focus (LGFocusPause). The menu answers the pause action
## itself while [member listen] is on, so the scene needn't.

signal opened
signal closed

## Whether pressing Pause opens and closes the menu.
var listen := true
## Whether opening the menu stops the game. Online play would keep going
## for everyone else and only hold this device's sound.
var hold_tree := true
## Asked before the menu opens; return false while it mustn't (results up).
var can_open := Callable()

var _root: Control
var _col: VBoxContainer
var _page := ""
var _howto: HowToPanel
var _mouse_mode := Input.MOUSE_MODE_VISIBLE
var _leaving := false


## Adds a pause menu to `scene` and has it open when the window loses focus.
static func attach(scene: Node) -> PauseMenu:
	var menu := PauseMenu.new()
	scene.add_child(menu)
	LGFocusPause.watch(scene, menu.open)
	return menu


func _init() -> void:
	name = "PauseMenu"
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(CityTheme.INK, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "DarkPanel"
	center.add_child(panel)
	LGScreenFit.center(panel, Vector2(24, 24))
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 12)
	_col.custom_minimum_size.x = 560
	panel.add_child(_col)


func is_open() -> bool:
	return visible


## Opens the menu (the pause button, or the window losing focus).
func open() -> void:
	if visible or _leaving or not is_inside_tree():
		return
	if can_open.is_valid() and not bool(can_open.call()):
		return
	visible = true
	_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hold_tree:
		get_tree().paused = true
	LGAudio.pause_game(true)
	show_main()
	LGPlaytest.event("paused", {"town": str(Towns.current.get("id", ""))})
	opened.emit()


## Closes the menu and lets the game go on.
func close() -> void:
	if not visible:
		return
	visible = false
	_close_howto()
	_clear()
	_page = ""
	if is_inside_tree():
		if hold_tree:
			get_tree().paused = false
		LGAudio.pause_game(false)
		var f := _root.get_viewport().gui_get_focus_owner()
		if f:
			f.release_focus()
	Input.mouse_mode = _mouse_mode
	closed.emit()


func _clear() -> void:
	for c in _col.get_children():
		_col.remove_child(c)
		c.queue_free()


func show_main() -> void:
	_clear()
	_page = "main"
	_col.add_child(LGUi.label("Paused", "HeaderLarge"))
	var where := str(Towns.current.get("name", ""))
	if where != "":
		_col.add_child(LGUi.label(where.to_upper(), "CapsLabel"))
	var resume := LGUi.button("Resume", close, 560)
	resume.theme_type_variation = "HeroButton"
	_col.add_child(resume)
	_col.add_child(LGUi.button("Settings", show_settings, 560))
	_col.add_child(LGUi.button("How to play", show_howto, 560))
	_col.add_child(LGPlaytestButton.make(560))
	_col.add_child(LGUi.button("Back to the title", _to_title, 560))
	var quit := LGUi.button("Quit", _quit, 560)
	quit.theme_type_variation = "DangerButton"
	_col.add_child(quit)
	CityTheme.focus(resume)


func show_settings() -> void:
	_clear()
	_page = "settings"
	_col.add_child(LGUi.label("Settings", "HeaderMedium"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(600, 480)
	scroll.follow_focus = true
	_col.add_child(scroll)
	scroll.add_child(CitySettings.new())
	_col.add_child(LGUi.button("Back", show_main, 560))
	LGUi.focus_first(scroll)


func show_howto() -> void:
	_page = "howto"
	_root.visible = false
	_howto = HowToPanel.new()
	add_child(_howto)
	_howto.closed.connect(_on_howto_closed)
	_howto.open()


func _on_howto_closed() -> void:
	_close_howto()
	_root.visible = true
	show_main()


func _close_howto() -> void:
	if _howto and is_instance_valid(_howto):
		_howto.queue_free()
	_howto = null
	_root.visible = true


func _to_title() -> void:
	if _leaving or LGScenes.is_busy():
		return
	_leaving = true
	visible = false
	if hold_tree:
		get_tree().paused = false
	LGAudio.pause_game(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	LGScenes.change_scene(TitleScreen.SCENE)


func _quit() -> void:
	LGScenes.quit()


## The labels of the buttons on show, for tests.
func button_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for b in _col.find_children("", "Button", true, false):
		if (b as Button).visible:
			out.append((b as Button).text)
	return out


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		if listen and event.is_action_pressed("pause") and not _leaving:
			get_viewport().set_input_as_handled()
			open()
		return
	if _page == "howto":
		return
	# Back (and Escape) leave a page first; Pause on a controller closes.
	if event.is_action_pressed("ui_cancel") and _page != "main":
		get_viewport().set_input_as_handled()
		show_main()
	elif event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
