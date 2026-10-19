extends Node
## Screenshots of the menus, to check how they look:
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x800x24" \
##       godot --path . --resolution 1280x800 tools/menu_shot.tscn -- --page=title --out=/tmp/title.png
## Pages: title, towns (two made-up towns), towns_empty, settings, about,
## about_end (scrolled down), howto, pause, card (the big town card),
## card_small (its corner line), or all (every page into the folder --out).

const PAGES := ["title", "towns", "towns_empty", "settings", "about", "about_end", "howto", "pause", "card", "card_small"]
const FAKE_TOWNS := [
	{"id": "porthaven", "name": "Porthaven", "country": "Wales", "data_date": "2026-10-14", "attribution": ["© OpenStreetMap contributors"]},
	{"id": "lindenau", "name": "Lindenau", "country": "Germany", "data_date": "2026-09-30", "attribution": ["© OpenStreetMap contributors"]},
]

var out := "/tmp/menu.png"
var page_name := "title"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--page="):
			page_name = a.trim_prefix("--page=")
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	LGInput.register_actions(GameConfig.ACTIONS, 0.25)
	LGInput.extend_ui_actions()
	LGTheme.apply(get_tree().root, 22)
	CityTheme.apply(get_tree().root, 22)
	if page_name == "all":
		DirAccess.make_dir_recursive_absolute(out)
		for p in PAGES:
			await _shoot(p, out.path_join(p + ".png"))
	else:
		await _shoot(page_name, out)
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shoot(p: String, path: String) -> void:
	for c in get_children():
		c.queue_free()
	await _frames(2)
	var title: TitleScreen = load(TitleScreen.SCENE).instantiate()
	title.towns_override = [] if p == "towns_empty" else FAKE_TOWNS
	add_child(title)
	await _frames(3)
	match p:
		"towns", "towns_empty":
			title.show_towns()
		"settings":
			title.show_settings()
		"about", "about_end":
			title.show_about()
			if p == "about_end":
				await _frames(3)
				title._body.scroll_vertical = 100000
		"howto":
			title.show_howto()
		"pause":
			title._main.visible = false
			Towns.current = FAKE_TOWNS[0]
			var menu := PauseMenu.attach(title)
			menu.open()
		"card", "card_small":
			title._main.visible = false
			var layer := CanvasLayer.new()
			title.add_child(layer)
			var card := TownCard.new()
			layer.add_child(card)
			card.show_town({"name": "Porthaven", "country": "Wales", "data_date": "2026-10-14",
				"attribution": ["© OpenStreetMap contributors", TitleScreen.ELEVATION_CREDIT]})
			card.step(1.0 if p == "card" else TownCard.BIG_SECONDS + TownCard.FADE + 1.5)
	await _frames(14)
	var img := get_viewport().get_texture().get_image()
	# The viewport keeps the menus' alpha; the screen doesn't show it.
	img.convert(Image.FORMAT_RGB8)
	img.save_png(path)
	print("menu_shot: ", path)
	get_tree().paused = false
	title.queue_free()
	await _frames(2)
