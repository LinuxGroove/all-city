extends RefCounted
## The menus: the title with no towns and with one, a controller finding its
## way round them, About's credits, the pause menu, the town card's credit
## and where the developer shortcuts go.

const FAKE_ID := "menu_test_town"


func _frames(t, n := 3) -> void:
	for i in n:
		await t.get_tree().process_frame


## Waits long enough for the input router's repeat filter between presses.
func _gap(t) -> void:
	await t.get_tree().create_timer(0.15, true, false, true).timeout


func _pad(t, button: JoyButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.device = 0
		ev.button_index = button
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(t, 2)
	await _gap(t)


func _action(t, action: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(t, 2)


func _focused(t) -> Control:
	return t.get_viewport().gui_get_focus_owner()


func _title(t, towns: Variant, backdrop := false) -> TitleScreen:
	CityTheme.apply(t.get_tree().root)
	var title: TitleScreen = load(TitleScreen.SCENE).instantiate()
	title.towns_override = towns
	title.with_backdrop = backdrop
	t.add_child(title)
	await _frames(t, 3)
	return title


func _labels(root: Node) -> String:
	var out := PackedStringArray()
	for l in root.find_children("", "Label", true, false):
		if (l as Label).is_visible_in_tree():
			out.append((l as Label).text)
	return "\n".join(out)


func test_title_with_no_towns(t) -> void:
	var title := await _title(t, [], true)
	t.check(title.backdrop != null and title.backdrop.camera.current, "the title has its street behind it")
	t.check(Array(title.button_texts()) == ["Play", "How to play", "Settings", "About", "Quit"], "the title's buttons")
	var focus := _focused(t)
	t.check(focus is Button and (focus as Button).text == "Play", "Play has the focus")
	title.show_towns()
	await _frames(t)
	var text := _labels(title._page)
	t.check("No towns yet" in text, "with no towns the picker says so")
	t.check("OpenStreetMap" in text and "Cartographer" in text, "and says how towns get built")
	t.check("© OpenStreetMap contributors" in text, "the picker credits the map")
	focus = _focused(t)
	t.check(focus is Button and (focus as Button).text == "Back", "Back has the focus with no towns")
	title.free()


func test_title_with_a_town(t) -> void:
	var folder := Towns.BUILT.path_join(FAKE_ID)
	DirAccess.make_dir_recursive_absolute(folder)
	var manifest := {"format": 1, "id": FAKE_ID, "name": "Testbury", "country": "Nowhere", "data_date": "2026-10-01",
		"built": "2026-10-02", "attribution": ["© OpenStreetMap contributors"]}
	var f := FileAccess.open(folder.path_join("town.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest))
	f.close()
	t.check(not Towns.find(FAKE_ID).is_empty(), "the made-up town is found")
	var title := await _title(t, null)
	title.show_towns()
	await _frames(t)
	var found: Button = null
	for b in title._page.find_children("", "Button", true, false):
		if str(b.get_meta("town", "")) == FAKE_ID:
			found = b
	t.check(found != null, "the town has a button")
	if found:
		var text := _labels(found)
		t.check("TESTBURY" in text, "with its name")
		t.check("Nowhere" in text and "map of 1 October 2026" in text, "its country and the map's date")
	t.check(not title._page.find_children("", "Label", true, false).any(_says_no_towns), "no 'No towns yet' with a town")
	# Opening one needs the play scene; without it the picker says so.
	if found and not ResourceLoader.exists(Towns.PLAY_SCENE):
		found.pressed.emit()
		await _frames(t)
		t.check("can't open" in title._page_status.text, "a town can't open before the play scene exists")
	title.free()
	DirAccess.remove_absolute(folder.path_join("town.json"))
	DirAccess.remove_absolute(folder)
	t.check(Towns.find(FAKE_ID).is_empty(), "the made-up town is gone again")


func _says_no_towns(l: Label) -> bool:
	return l.text == "No towns yet"


func test_title_with_a_pad(t) -> void:
	var title := await _title(t, [])
	await _pad(t, JOY_BUTTON_DPAD_DOWN)
	var focus := _focused(t)
	t.check(focus is Button and (focus as Button).text == "How to play", "down moves to How to play")
	await _pad(t, JOY_BUTTON_A)
	t.check(title.page == "howto" and title._howto != null and title._howto.visible, "A opens How to play")
	await _pad(t, JOY_BUTTON_B)
	await _frames(t)
	t.check(title.page == "main", "B goes back to the title")
	focus = _focused(t)
	t.check(focus is Button and (focus as Button).text == "Play", "and Play has the focus again")
	await _pad(t, JOY_BUTTON_A)
	await _frames(t)
	t.check(title.page == "towns", "A on Play opens the towns")
	await _pad(t, JOY_BUTTON_B)
	t.check(title.page == "main", "B leaves them")
	for i in 2:
		await _pad(t, JOY_BUTTON_DPAD_DOWN)
	focus = _focused(t)
	t.check(focus is Button and (focus as Button).text == "Settings", "down twice reaches Settings")
	await _pad(t, JOY_BUTTON_A)
	await _frames(t)
	t.check(title.page == "settings", "A opens Settings")
	var texts := " ".join(title.button_texts())
	t.check("Field of view" in texts and "Reduce flashing" in texts and "Fullscreen" in texts, "with the game's rows and the shared ones")
	focus = _focused(t)
	t.check(focus is LGCycler, "a settings row has the focus")
	await _pad(t, JOY_BUTTON_B)
	t.check(title.page == "main", "B leaves Settings")
	title.free()
	LGInput.family = "keyboard"


func test_about(t) -> void:
	var text := TitleScreen.about_text()
	for want in ["© OpenStreetMap contributors", "Open Database License", "https://www.openstreetmap.org/copyright",
			"Created by", "Drew VanDine", "Kaden VanDine", "Ken VanDine", "The LinuxGroove team",
			"Universal Base Characters", "Universal Animation Library", "Bungee", "Montserrat", "Permanent Marker",
			"Apache License 2.0", "Godot"]:
		t.check(want in text, "About says %s" % want)
	t.check(TitleScreen.ELEVATION_CREDIT in text, "About credits the elevation")
	# The elevation credit is the Cartographer's own.
	var source := FileAccess.get_file_as_string("res://cartographer/terrain.py")
	if source != "":
		var start := source.find("ATTRIBUTION = (")
		var block := source.substr(start, source.find(")\n", start) - start)
		var re := RegEx.create_from_string("\"([^\"]*)\"")
		var joined := ""
		for m in re.search_all(block):
			joined += m.get_string(1)
		t.check(joined == TitleScreen.ELEVATION_CREDIT, "About's elevation credit matches cartographer/terrain.py")
	var title := await _title(t, [])
	title.show_about()
	await _frames(t)
	t.check(title._about != null and "OpenStreetMap contributors" in title._about.get_parsed_text(), "the About page shows the map credit")
	t.check("OpenStreetMap's licence" in title.button_texts(), "and a way to the licence")
	title.free()


func test_how_to_play(t) -> void:
	for c in HowToPanel.CONTROLS:
		t.check(GameConfig.ACTIONS.has(c[0]), "How to play's %s is a real action" % c[0])
	var listed := []
	for c in HowToPanel.CONTROLS:
		listed.append(c[0])
	for action in GameConfig.ACTIONS:
		if not (action.begins_with("move_") or action.begins_with("look_") and action != "look_back"):
			t.check(action in listed, "How to play lists %s" % action)
	var words := ""
	for s in HowToPanel.SECTIONS:
		words += " ".join(s) + " "
	for want in ["Grind", "Wall ride", "Climb", "Flow", "tag", "Buff", "dawn", "Homes", "schools", "worship"]:
		t.check(want.to_lower() in words.to_lower(), "How to play mentions %s" % want)


func test_pause_menu(t) -> void:
	CityTheme.apply(t.get_tree().root)
	var scene := Node.new()
	t.add_child(scene)
	var menu := PauseMenu.attach(scene)
	await _frames(t)
	t.check(not menu.is_open() and not t.get_tree().paused, "the menu starts closed")
	await _action(t, "pause")
	t.check(menu.is_open(), "Pause opens it")
	t.check(t.get_tree().paused and LGAudio.is_game_paused(), "the game and its sound are held")
	var texts := menu.button_texts()
	for want in ["Resume", "Settings", "How to play", "Back to the title", "Quit"]:
		t.check(want in texts, "the pause menu has %s" % want)
	var focus := _focused(t)
	t.check(focus is Button and (focus as Button).text == "Resume", "Resume has the focus")
	menu.show_settings()
	await _frames(t)
	await _action(t, "ui_cancel")
	t.check(menu.is_open() and "Resume" in menu.button_texts(), "Back leaves Settings, not the menu")
	await _action(t, "ui_cancel")
	t.check(not menu.is_open(), "Back again closes it")
	t.check(not t.get_tree().paused and not LGAudio.is_game_paused(), "and lets the game and its sound go")
	# Losing the window's focus opens it.
	var watcher: LGFocusPause = scene.get_node("FocusPause")
	t.check(watcher.pause_now() and menu.is_open() and t.get_tree().paused, "losing focus pauses")
	t.check(not watcher.pause_now(), "but not twice")
	menu.close()
	t.check(not t.get_tree().paused, "Resume lets go")
	menu.can_open = _never
	menu.open()
	t.check(not menu.is_open(), "it stays shut while the scene says so")
	scene.free()
	t.get_tree().paused = false
	LGAudio.pause_game(false)


func _never() -> bool:
	return false


func test_town_card(t) -> void:
	t.check(TownCard.date_text("2026-10-14") == "14 October 2026", "map dates read as words")
	t.check(TownCard.date_text("2026-13-01") == "2026-13-01" and TownCard.date_text("soon") == "soon", "odd dates stay as they are")
	var card := TownCard.new()
	t.add_child(card)
	card.show_town({"id": "porthaven", "name": "Porthaven", "country": "Wales", "data_date": "2026-10-14",
		"attribution": ["© OpenStreetMap contributors", "Elevation: somewhere"]})
	card.step(1.0)
	var text := card.shown_text()
	t.check(card.phase() == "big" and card.visible, "the card opens big")
	t.check("PORTHAVEN" in text and "WALES" in text and "Map of 14 October 2026" in text, "with the town and the map's date")
	t.check("© OpenStreetMap contributors" in text, "and the map's credit")
	t.check("Elevation: somewhere" in text, "and the town's other credits")
	card.step(TownCard.BIG_SECONDS + TownCard.FADE)
	text = card.shown_text()
	t.check(card.phase() == "small", "then it goes small")
	t.check("© OpenStreetMap contributors" in text and "Porthaven" in text and not "WALES" in text, "a corner line with the credit")
	card.step(TownCard.SMALL_SECONDS + TownCard.FADE + 1.0)
	t.check(card.phase() == "gone" and not card.visible, "then it's gone")
	card.free()


func test_start_plan(t) -> void:
	var main: GDScript = load("res://game/main.gd")
	t.check(main.plan(PackedStringArray()).scene == TitleScreen.SCENE, "the game starts at the title")
	t.check(main.plan(PackedStringArray(["--title"])).scene == TitleScreen.SCENE, "--title goes to the title")
	var nowhere: Dictionary = main.plan(PackedStringArray(["--town=no_such_town_here"]))
	t.check(nowhere.scene == TitleScreen.SCENE and "no town" in str(nowhere.get("message", "")), "an unknown town goes to the title and says so")
	var yard: Dictionary = main.plan(PackedStringArray(["--yard"]))
	if ResourceLoader.exists("res://tools/yard.tscn"):
		t.check(yard.scene == "res://tools/yard.tscn", "--yard goes to the yard")
	else:
		t.check(yard.scene == TitleScreen.SCENE and str(yard.get("message", "")) != "", "--yard with no yard goes to the title")


func test_theme(t) -> void:
	var theme := CityTheme.build()
	var body := theme.default_font as FontVariation
	t.check(body != null and not body.variation_opentype.is_empty(), "text is Montserrat at a set weight")
	t.check(theme.get_font("font", "Button").resource_path == CityTheme.HEADING_PATH, "buttons are in Bungee")
	var focus := theme.get_stylebox("focus", "Button") as StyleBoxFlat
	t.check(focus != null and focus.bg_color == CityTheme.YELLOW, "focus fills a button yellow")
	t.check(theme.get_font_size("font_size", "HintLabel") >= 18, "small text stays readable")
