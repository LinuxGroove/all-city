class_name TitleScreen
extends Node
## The title: a street at dusk behind the name, and Play (pick a town), How
## to play, Settings, About and Quit. Every page works with a controller,
## the keyboard or the mouse, and Back (or B) leaves it.

const SCENE := "res://game/ui/title_screen.tscn"
const OSM_URL := "https://www.openstreetmap.org/copyright"
const MENU_WIDTH := 420
const PAGE_WIDTH := 700

## The elevation credit, as the Cartographer writes it (cartographer/terrain.py's
## ATTRIBUTION; a test keeps the two the same).
const ELEVATION_CREDIT := "Elevation: Mapzen Terrarium tiles on AWS Open Data (SRTM, GMTED, NED, ETOPO1 and others; see https://github.com/tilezen/joerd/blob/master/docs/attribution.md)"

## Shown once on arrival, e.g. why a town didn't open.
var message := ""
## The towns to list instead of Towns.list(), for tests.
var towns_override: Variant = null
## Whether to build the street behind the menu (tests can leave it out).
var with_backdrop := true
var page := "main"

var backdrop: MenuBackdrop
var _ui: Control
var _main: Control
var _menu: VBoxContainer
var _status: Label
var _page: Control
var _head: Label
var _body: ScrollContainer
var _foot: VBoxContainer
var _page_status: Label
var _about: RichTextLabel
var _howto: HowToPanel
var _leaving := false


## Goes to the title with `text` on it (a setup for LGScenes.change_scene).
static func with_message(node: Node, text: String) -> void:
	if node is TitleScreen:
		(node as TitleScreen).message = text


func _ready() -> void:
	if with_backdrop:
		backdrop = MenuBackdrop.new()
		backdrop.name = "Backdrop"
		add_child(backdrop)
	var layer := CanvasLayer.new()
	layer.name = "Menus"
	layer.layer = 10
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_ui)
	_build_main()
	_build_page()
	show_main()


# --- Layout -------------------------------------------------------------------

func _build_main() -> void:
	_main = Control.new()
	_main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_main)
	var shade := Shade.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main.add_child(shade)
	var logo := CityTheme.logo(104)
	_main.add_child(logo)
	_pin(logo, Control.PRESET_TOP_LEFT, Vector2(56, 34))
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.custom_minimum_size.x = MENU_WIDTH
	_main.add_child(left)
	_pin(left, Control.PRESET_BOTTOM_LEFT, Vector2(56, -44))
	_status = LGUi.label("", "HintLabel")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = MENU_WIDTH
	_status.add_theme_color_override("font_color", CityTheme.YELLOW)
	left.add_child(_status)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 10)
	left.add_child(_menu)
	var corner := VBoxContainer.new()
	corner.alignment = BoxContainer.ALIGNMENT_END
	_main.add_child(corner)
	var credit := LGUi.label("Map data %s" % TownCard.OSM_CREDIT, "HintLabel")
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	corner.add_child(credit)
	var version := LGUi.label("v%s" % GameConfig.version(), "HintLabel")
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	corner.add_child(version)
	_pin(corner, Control.PRESET_BOTTOM_RIGHT, Vector2(-24, -18))


## Puts `c` at a corner of the screen, `offset` in from it, sized to fit.
func _pin(c: Control, preset: Control.LayoutPreset, offset: Vector2) -> void:
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if preset in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT] \
			else Control.GROW_DIRECTION_END
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT] \
			else Control.GROW_DIRECTION_END
	c.position += offset


## A page is a dark panel down the left of the screen, with the street still
## showing on the right: a heading, what the page holds (scrolling when it's
## long) and its buttons at the foot.
func _build_page() -> void:
	_page = Control.new()
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page.visible = false
	_ui.add_child(_page)
	var shade := Shade.new()
	shade.heavy = true
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page.add_child(shade)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "DarkPanel"
	panel.anchor_bottom = 1.0
	panel.offset_left = 40
	panel.offset_right = 40 + PAGE_WIDTH
	panel.offset_top = 28
	panel.offset_bottom = -28
	_page.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	_head = LGUi.label("", "HeaderMedium")
	col.add_child(_head)
	_body = ScrollContainer.new()
	_body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.follow_focus = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	_foot = VBoxContainer.new()
	_foot.add_theme_constant_override("separation", 10)
	col.add_child(_foot)


func _open_page(p_name: String, heading: String) -> void:
	page = p_name
	_close_howto()
	for box in [_body, _foot]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	_about = null
	_page_status = null
	_head.text = heading
	_body.scroll_vertical = 0
	_main.visible = false
	_page.visible = true


## Claims the screen for one action that leaves it; false if one is running.
func _claim() -> bool:
	if _leaving or LGScenes.is_busy():
		return false
	_leaving = true
	return true


# --- The main menu ------------------------------------------------------------

func show_main() -> void:
	page = "main"
	_close_howto()
	_page.visible = false
	_main.visible = true
	for c in _menu.get_children():
		_menu.remove_child(c)
		c.queue_free()
	var play := LGUi.button("Play", show_towns, MENU_WIDTH)
	play.theme_type_variation = "HeroButton"
	play.custom_minimum_size.y = 84
	_menu.add_child(play)
	_menu.add_child(LGUi.button("How to play", show_howto, MENU_WIDTH))
	_menu.add_child(LGUi.button("Settings", show_settings, MENU_WIDTH))
	_menu.add_child(LGUi.button("About", show_about, MENU_WIDTH))
	var quit := LGUi.button("Quit", _quit, MENU_WIDTH)
	quit.theme_type_variation = "DangerButton"
	_menu.add_child(quit)
	_status.text = message
	_status.visible = message != ""
	CityTheme.focus(play)


func _quit() -> void:
	LGScenes.quit()


# --- Play: the towns ----------------------------------------------------------

## The towns this copy can play, by name.
func towns() -> Array:
	return towns_override if towns_override is Array else Towns.list()


func show_towns() -> void:
	_open_page("towns", "Pick a town")
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(list)
	var all := towns()
	if all.is_empty():
		list.add_child(CityTheme.label("No towns yet", 40, CityTheme.TEXT))
		list.add_child(_text("Every town is built from OpenStreetMap by the Cartographer, a tool that comes with the game's source. A built town goes in your towns folder and shows up here."))
		var folder := LGUi.label(ProjectSettings.globalize_path(Towns.BUILT), "HintLabel")
		folder.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		folder.custom_minimum_size.x = PAGE_WIDTH - 80
		list.add_child(folder)
	for town in all:
		list.add_child(_town_button(town))
	_page_status = LGUi.label("", "HintLabel")
	_page_status.add_theme_color_override("font_color", CityTheme.YELLOW)
	_page_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_status.custom_minimum_size.x = PAGE_WIDTH - 80
	_page_status.visible = false
	_foot.add_child(_page_status)
	_foot.add_child(LGUi.label("Map data %s" % TownCard.OSM_CREDIT, "HintLabel"))
	var back := LGUi.button("Back", show_main, PAGE_WIDTH - 60)
	_foot.add_child(back)
	CityTheme.focus(list.get_child(0) if not all.is_empty() else back)


func _text(t: String) -> Label:
	var l := LGUi.label(t)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = PAGE_WIDTH - 80
	return l


## A town in the list: its name big, then the country and the map's date.
func _town_button(town: Dictionary) -> Button:
	var b := Button.new()
	b.theme_type_variation = "TileButton"
	b.custom_minimum_size = Vector2(PAGE_WIDTH - 80, 96)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.name = "Town_%s" % str(town.get("id", ""))
	b.pressed.connect(_open_town.bind(str(town.get("id", ""))))
	b.pressed.connect(LGUi.click)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 24
	col.offset_right = -24
	col.add_theme_constant_override("separation", 2)
	b.add_child(col)
	var title := CityTheme.label(str(town.get("name", town.get("id", ""))).to_upper(), 30, CityTheme.TEXT)
	col.add_child(title)
	col.add_child(LGUi.label(town_line(town), "HintLabel"))
	b.set_meta("town", str(town.get("id", "")))
	return b


## "Wales · map of 14 October 2026"
static func town_line(town: Dictionary) -> String:
	var parts := PackedStringArray()
	if str(town.get("country", "")) != "":
		parts.append(str(town.country))
	if str(town.get("data_date", "")) != "":
		parts.append("map of %s" % TownCard.date_text(str(town.data_date)))
	return "  ·  ".join(parts)


func _open_town(id: String) -> void:
	if not _claim():
		return
	var why := ""
	if not ResourceLoader.exists(Towns.PLAY_SCENE):
		why = "Towns can't open in this build yet."
	elif not Towns.play(id):
		why = "That town isn't here any more."
	if why != "":
		_leaving = false
		if _page_status:
			_page_status.text = why
			_page_status.visible = true


# --- Settings, how to play, about ---------------------------------------------

func show_settings() -> void:
	_open_page("settings", "Settings")
	var s := CitySettings.new()
	_body.add_child(s)
	_foot.add_child(LGUi.button("Back", show_main, PAGE_WIDTH - 60))
	LGUi.focus_first(s)


func show_howto() -> void:
	_close_howto()
	page = "howto"
	_main.visible = false
	_page.visible = false
	_howto = HowToPanel.new()
	_ui.add_child(_howto)
	_howto.closed.connect(_on_howto_closed)
	_howto.open()


func _on_howto_closed() -> void:
	show_main()


func _close_howto() -> void:
	if _howto and is_instance_valid(_howto):
		_howto.queue_free()
	_howto = null


## Credits. Up and down scroll the page; the buttons are at its foot.
func show_about() -> void:
	_open_page("about", "About %s" % GameConfig.TITLE)
	_about = RichTextLabel.new()
	_about.bbcode_enabled = true
	_about.fit_content = true
	_about.scroll_active = false
	_about.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_about.custom_minimum_size.x = PAGE_WIDTH - 80
	_about.add_theme_font_size_override("normal_font_size", 19)
	_about.add_theme_font_size_override("bold_font_size", 20)
	_about.text = about_text()
	_about.meta_clicked.connect(_on_link)
	_body.add_child(_about)
	_foot.add_child(LGUi.button("OpenStreetMap's licence", _open_osm, PAGE_WIDTH - 60))
	var back := LGUi.button("Back", show_main, PAGE_WIDTH - 60)
	_foot.add_child(back)
	CityTheme.focus(back)


func _on_link(meta: Variant) -> void:
	var url := str(meta)
	if url.begins_with("https://"):
		OS.shell_open(url)


func _open_osm() -> void:
	OS.shell_open(OSM_URL)


## Everything About says, as BBCode.
static func about_text() -> String:
	return ABOUT_TEXT % [GameConfig.version(), OSM_URL, OSM_URL.trim_prefix("https://www."), ELEVATION_CREDIT]


const ABOUT_TEXT := """[font_size=34][color=#ff4fa3][b]ALL CITY[/b][/color][/font_size]  v%s
A LinuxGroove game

[b]Created by[/b]
Drew VanDine
Kaden VanDine
Ken VanDine

[b]Maps[/b]
Map data © OpenStreetMap contributors, available under the Open Database License: [url=%s]%s[/url]
%s
Every town is built from a dated copy of the map. Shops show as what they are, never by their real names, and no house numbers appear.

[b]Art[/b]
The writers are Quaternius' Universal Base Characters, moving with the Universal Animation Library (quaternius.com), CC0. Thank you, Quaternius!
The streets, buildings, stairs, vehicles, skates and cans were modelled in Blender for All City.
Button prompts, menu sounds and the shared add-on's fonts by Kenney (kenney.nl), CC0. Thank you, Kenney!

[b]Fonts[/b]
Bungee by David Jonathan Ross, SIL Open Font License 1.1
Montserrat by Julieta Ulanovsky and the Montserrat Project Authors, SIL Open Font License 1.1
Permanent Marker by Font Diner, Apache License 2.0

[b]Made with[/b]
Godot Engine (godotengine.org), MIT
Nakama Godot client by Heroic Labs, Apache-2.0

Copyright (c) 2026 The LinuxGroove team
All City is free software under the MIT license."""


func _input(event: InputEvent) -> void:
	# About's text has nothing to focus, so up and down scroll it.
	if page != "about" or not _page.visible:
		return
	var step := 0
	if event.is_action_pressed("ui_down", true):
		step = 1
	elif event.is_action_pressed("ui_up", true):
		step = -1
	if step != 0 and _body.get_v_scroll_bar().max_value > _body.size.y:
		var before := _body.scroll_vertical
		_body.scroll_vertical += step * 60
		# At the end of the text, let focus move between the buttons.
		if _body.scroll_vertical != before:
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and page in ["towns", "settings", "about"]:
		get_viewport().set_input_as_handled()
		show_main()


## The labels of the buttons on show, for tests.
func button_texts() -> PackedStringArray:
	var out := PackedStringArray()
	var root: Node = _menu if page == "main" else _page
	for b in root.find_children("", "Button", true, false):
		if (b as Button).is_visible_in_tree() or not is_inside_tree():
			out.append((b as Button).text if (b as Button).text != "" else str(b.get_meta("town", "")))
	return out


## The dark wash under the menu: heavy on the left, where the name and the
## buttons are, clearing towards the street on the right.
class Shade:
	extends Control

	## Darker, for pages.
	var heavy := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var ink := CityTheme.INK
		var a := 0.9 if heavy else 0.78
		var c1 := Color(ink, a)
		var c0 := Color(ink, 0.0)
		var x1 := 820.0 if heavy else 640.0
		draw_rect(Rect2(0, 0, x1 * 0.55, h), c1)
		draw_polygon(PackedVector2Array([Vector2(x1 * 0.55, 0), Vector2(x1, 0), Vector2(x1, h), Vector2(x1 * 0.55, h)]),
			PackedColorArray([c1, c0, c0, c1]))
		# A soft floor under the credits on the right.
		draw_polygon(PackedVector2Array([Vector2(w * 0.6, h - 90), Vector2(w, h - 90), Vector2(w, h), Vector2(w * 0.6, h)]),
			PackedColorArray([c0, Color(ink, 0.0), Color(ink, 0.6), c0]))
