class_name CityTheme
extends RefCounted
## All City's look for menus: Bungee for headings and buttons, Montserrat for
## text, Permanent Marker for anything written by hand, on ink panels with
## sticker-like buttons in the palette's bold colours. Built on the shared
## theme (so the shared settings rows, cyclers and keyboard follow it) and
## applied once at startup by main.gd, after LGTheme.
##
## Sized for a 7-inch handheld at 1280x800 first: buttons are tall, text is
## never under 18 px, and focus is a solid yellow fill with ink text that
## reads from across the room.

## The palette's colours (assets/art/palette.png, see Palette).
const INK := Color("14121c")
const SHADOW := Color("221f2b")
const ASPHALT := Color("2b2a33")
const ASPHALT_LIGHT := Color("403e4a")
const TEXT := Color("f4efe6")
const CREAM := Color("efe2c6")
const DIM := Color("b9b3ae")
const YELLOW := Color("f2c641")
const PINK := Color("ff4fa3")
const CYAN := Color("3ff2ff")
const RED := Color("e8463a")
const HIVIS := Color("c6f03c")
const PANEL := Color(0.078, 0.071, 0.11, 0.92)

const HEADING_PATH := "res://assets/fonts/Bungee-Regular.ttf"
const TEXT_PATH := "res://assets/fonts/Montserrat.ttf"
const MARKER_PATH := "res://assets/fonts/PermanentMarker-Regular.ttf"

static var _fonts := {}


## Builds the theme on top of the shared one and makes it the default
## everywhere, as LGTheme.apply does.
static func apply(root: Window, base_size := 22) -> Theme:
	var t := build(base_size)
	root.theme = t
	ThemeDB.get_default_theme().merge_with(t)
	ThemeDB.get_default_theme().default_font = t.default_font
	ThemeDB.get_default_theme().default_font_size = t.default_font_size
	return t


static func build(base_size := 22) -> Theme:
	var t := LGTheme.build(base_size)
	var head := heading()
	var body := text()
	t.default_font = body
	t.default_font_size = base_size

	# Labels.
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(INK, 0.9))
	t.set_constant("outline_size", "Label", 4)
	t.set_font("font", "HeaderLarge", head)
	t.set_font_size("font_size", "HeaderLarge", int(base_size * 2.2))
	t.set_color("font_color", "HeaderLarge", TEXT)
	t.set_constant("outline_size", "HeaderLarge", 8)
	t.set_font("font", "HeaderMedium", head)
	t.set_font_size("font_size", "HeaderMedium", int(base_size * 1.4))
	t.set_color("font_color", "HeaderMedium", YELLOW)
	t.set_constant("outline_size", "HeaderMedium", 6)
	t.set_color("font_color", "HintLabel", DIM)
	t.set_font_size("font_size", "HintLabel", maxi(18, int(base_size * 0.82)))
	t.set_type_variation("CapsLabel", "Label")
	t.set_font("font", "CapsLabel", head)
	t.set_font_size("font_size", "CapsLabel", maxi(18, int(base_size * 0.82)))
	t.set_color("font_color", "CapsLabel", CYAN)
	t.set_type_variation("MarkerLabel", "Label")
	t.set_font("font", "MarkerLabel", marker())
	t.set_font_size("font_size", "MarkerLabel", int(base_size * 1.3))
	t.set_color("font_color", "MarkerLabel", PINK)
	t.set_constant("outline_size", "MarkerLabel", 6)
	t.set_type_variation("DimLabel", "Label")
	t.set_color("font_color", "DimLabel", DIM)
	for ink in ["InkLabel", "InkHeader", "InkTitle"]:
		t.set_color("font_color", ink, TEXT)
		t.set_constant("outline_size", ink, 4)

	# Buttons: dark stickers with a cream edge and a hard ink shadow; focus
	# fills them yellow.
	var normal := sticker(ASPHALT, CREAM)
	var hover := sticker(ASPHALT_LIGHT, YELLOW)
	var pressed := sticker(PINK, INK, Vector2(2, 2))
	var focus := sticker(YELLOW, INK)
	var disabled := sticker(Color(SHADOW, 0.85), Color(DIM, 0.35), Vector2.ZERO)
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus)
		t.set_font("font", type, head)
		t.set_font_size("font_size", type, base_size)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, INK)
		t.set_color("font_pressed_color", type, INK)
		t.set_color("font_hover_pressed_color", type, INK)
		t.set_color("font_disabled_color", type, Color(DIM, 0.55))
		t.set_constant("outline_size", type, 0)
	# A focused button is filled, so its text stays ink even when hovered.
	t.set_type_variation("DangerButton", "Button")
	t.set_stylebox("normal", "DangerButton", sticker(Color("3a1418"), RED))
	t.set_stylebox("focus", "DangerButton", sticker(RED, INK))
	for c in ["font_color", "font_hover_color"]:
		t.set_color(c, "DangerButton", Color("ffd9d4"))
	t.set_color("font_focus_color", "DangerButton", Color.WHITE)
	# The big one: Play.
	t.set_type_variation("HeroButton", "Button")
	var hero := sticker(PINK, INK, Vector2(6, 6))
	hero.border_color = TEXT
	hero.set_content_margin_all(16)
	t.set_stylebox("normal", "HeroButton", hero)
	var hero_hover := hero.duplicate() as StyleBoxFlat
	hero_hover.bg_color = PINK.lightened(0.12)
	t.set_stylebox("hover", "HeroButton", hero_hover)
	var hero_focus := sticker(YELLOW, INK, Vector2(6, 6))
	hero_focus.set_content_margin_all(16)
	t.set_stylebox("focus", "HeroButton", hero_focus)
	t.set_font_size("font_size", "HeroButton", int(base_size * 1.5))
	t.set_color("font_color", "HeroButton", Color.WHITE)
	t.set_color("font_hover_color", "HeroButton", Color.WHITE)
	# Tiles in lists (towns): flatter, with room for two lines of their own.
	t.set_type_variation("TileButton", "Button")
	var tile := sticker(Color(ASPHALT, 0.95), Color(CREAM, 0.5), Vector2(4, 4))
	tile.set_border_width_all(2)
	t.set_stylebox("normal", "TileButton", tile)
	var tile_hover := sticker(ASPHALT_LIGHT, YELLOW, Vector2(4, 4))
	t.set_stylebox("hover", "TileButton", tile_hover)
	var tile_focus := sticker(Color("3a3320"), YELLOW, Vector2(4, 4))
	tile_focus.set_border_width_all(5)
	t.set_stylebox("focus", "TileButton", tile_focus)
	for c in ["font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "TileButton", Color.WHITE)

	# Panels.
	var panel := flat(PANEL, Color(CREAM, 0.22), 2)
	panel.set_content_margin_all(22)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var dark := flat(Color(INK, 0.95), PINK, 0)
	dark.border_width_top = 5
	dark.set_content_margin_all(26)
	t.set_stylebox("panel", "DarkPanel", dark)
	t.set_stylebox("panel", "ParchmentPanel", dark)
	var glass := flat(Color(INK, 0.72), Color(CREAM, 0.14), 1)
	glass.set_content_margin_all(16)
	t.set_stylebox("panel", "GlassPanel", glass)

	# Text entry.
	var edit := flat(Color(INK, 0.95), Color(CREAM, 0.6), 2)
	edit.set_content_margin_all(12)
	t.set_stylebox("normal", "LineEdit", edit)
	var edit_focus := flat(Color(INK, 0.95), YELLOW, 4)
	edit_focus.set_content_margin_all(12)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", YELLOW)
	t.set_color("font_placeholder_color", "LineEdit", Color(DIM, 0.8))
	t.set_font("font", "LineEdit", body)

	# Bars.
	t.set_stylebox("background", "ProgressBar", flat(Color(INK, 0.6), Color(CREAM, 0.3), 2))
	t.set_stylebox("fill", "ProgressBar", flat(HIVIS, Color(0, 0, 0, 0), 0))
	t.set_stylebox("fill", "BlueProgressBar", flat(CYAN, Color(0, 0, 0, 0), 0))
	t.set_stylebox("fill", "RedProgressBar", flat(RED, Color(0, 0, 0, 0), 0))

	# Scroll bars, lists, check boxes and rich text.
	var grab := flat(Color(YELLOW, 0.85), Color(0, 0, 0, 0), 0)
	for s in ["grabber", "grabber_highlight", "grabber_pressed"]:
		t.set_stylebox(s, "VScrollBar", grab)
	t.set_stylebox("scroll", "VScrollBar", flat(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 0))
	var sel := flat(Color(YELLOW, 0.35), Color(0, 0, 0, 0), 0)
	t.set_stylebox("selected", "ItemList", sel)
	t.set_stylebox("selected_focus", "ItemList", sel)
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("font_outline_color", "RichTextLabel", Color(INK, 0.9))
	t.set_constant("outline_size", "RichTextLabel", 3)
	t.set_font("normal_font", "RichTextLabel", body)
	t.set_font("bold_font", "RichTextLabel", text(800))
	return t


## A button's sticker: a flat slab with a thick border and a hard shadow
## dropped down and right.
static func sticker(bg: Color, edge: Color, drop := Vector2(4, 4)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(3)
	s.set_corner_radius_all(6)
	s.shadow_color = Color(INK, 0.95)
	s.shadow_size = 1 if drop != Vector2.ZERO else 0
	s.shadow_offset = drop
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.anti_aliasing = true
	return s


## A plain box with a border.
static func flat(bg: Color, edge: Color, border := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(border)
	s.set_corner_radius_all(4)
	s.anti_aliasing = true
	return s


## Bungee: the name, headings and buttons.
static func heading() -> Font:
	if not _fonts.has("heading"):
		_fonts["heading"] = load(HEADING_PATH)
	return _fonts.heading


## Montserrat at a weight (its file is variable and starts at its thinnest).
static func text(weight := 560) -> Font:
	var key := "text/%d" % weight
	if not _fonts.has(key):
		var f := FontVariation.new()
		f.base_font = load(TEXT_PATH)
		var ts := TextServerManager.get_primary_interface()
		f.variation_opentype = {ts.name_to_tag("wght"): weight}
		_fonts[key] = f
	return _fonts[key]


## Permanent Marker: tags and anything written by hand.
static func marker() -> Font:
	if not _fonts.has("marker"):
		_fonts["marker"] = load(MARKER_PATH)
	return _fonts.marker


## Gives `c` the focus at the end of the frame, if it's still on screen by
## then (a page can be swapped again before it).
static func focus(c: Control) -> void:
	_grab.call_deferred(c)


static func _grab(c: Control) -> void:
	if is_instance_valid(c) and c.is_inside_tree() and c.is_visible_in_tree():
		c.grab_focus()


## A label in a font and colour of its own, with an ink outline.
static func label(p_text: String, size := 22, color := TEXT, font: Font = null, outline := 6) -> Label:
	var l := Label.new()
	l.text = p_text
	l.add_theme_font_override("font", font if font else heading())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(INK, 0.95))
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The game's name: ALL CITY in Bungee, white over a pink drop, with the
## line from the pitch in marker under it.
static func logo(size := 104) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(size * 0.02))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var front := label(GameConfig.TITLE.to_upper(), size, TEXT, heading(), int(size * 0.14))
	box.add_child(front)
	# The pink drop sits behind the name, down and to the right.
	var drop := label(GameConfig.TITLE.to_upper(), size, PINK, heading(), int(size * 0.14))
	drop.show_behind_parent = true
	drop.position = Vector2(size * 0.07, size * 0.07)
	front.add_child(drop)
	var line := label("Your town. Your walls. Your name, everywhere.", int(size * 0.27), YELLOW, marker(), int(size * 0.06))
	line.rotation_degrees = -2.0
	box.add_child(line)
	return box
