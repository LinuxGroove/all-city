class_name TownCard
extends Control
## The card that opens a town: its name, the date of the map it was built
## from and "© OpenStreetMap contributors", big across the screen for a few
## seconds, then as a small line in the bottom left corner that fades out a
## few seconds later. The play scene adds one and calls [method show_town]
## when the town is up; the credit is also always in About.
##
## It draws nothing over the town once it's gone, and takes no input.

signal finished

const OSM_CREDIT := "© OpenStreetMap contributors"
const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August", "September",
	"October", "November", "December"]
## How long the big card stays, the small line after it, and each fade.
const BIG_SECONDS := 4.0
const SMALL_SECONDS := 6.0
const FADE := 0.6

var _big: Control
var _name: Label
var _place: Label
var _date: Label
var _credit: Label
var _extra: Label
var _small: Label
var _t := -1.0


func _init() -> void:
	name = "TownCard"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	# The big card: a band across the lower middle, so the town shows above.
	_big = Control.new()
	_big.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_big)
	var band := PanelContainer.new()
	band.theme_type_variation = "DarkPanel"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.anchor_left = 0.0
	band.anchor_right = 1.0
	band.anchor_top = 0.56
	band.anchor_bottom = 0.56
	band.grow_vertical = Control.GROW_DIRECTION_BOTH
	_big.add_child(band)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(col)
	_place = _line("", "CapsLabel")
	col.add_child(_place)
	_name = CityTheme.label("", 72, CityTheme.TEXT, CityTheme.heading(), 10)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_name)
	_date = _line("", "")
	col.add_child(_date)
	_credit = _line(OSM_CREDIT, "")
	_credit.add_theme_color_override("font_color", CityTheme.YELLOW)
	col.add_child(_credit)
	_extra = _line("", "HintLabel")
	_extra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_extra)
	# The small line afterwards.
	_small = LGUi.label("", "HintLabel")
	_small.add_theme_color_override("font_color", CityTheme.TEXT)
	_small.add_theme_constant_override("outline_size", 6)
	_small.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_small)
	_small.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 24)


func _line(text: String, variation: String) -> Label:
	var l := LGUi.label(text, variation)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Shows a town's card: `manifest` is a town.json as Towns.list() gives it
## (name, country, data_date and attribution).
func show_town(manifest: Dictionary) -> void:
	var town_name := str(manifest.get("name", manifest.get("id", "")))
	_name.text = town_name.to_upper()
	_place.text = str(manifest.get("country", "")).to_upper()
	_place.visible = _place.text != ""
	var when := str(manifest.get("data_date", ""))
	_date.text = "Map of %s" % date_text(when) if when != "" else ""
	_date.visible = when != ""
	var extra := PackedStringArray()
	for line in manifest.get("attribution", []):
		if not "OpenStreetMap" in str(line):
			extra.append(str(line))
	_extra.text = "\n".join(extra)
	_extra.visible = not extra.is_empty()
	_small.text = "%s  ·  %s" % [town_name, OSM_CREDIT] if town_name != "" else OSM_CREDIT
	_small.reset_size()
	_small.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 24)
	_t = 0.0
	visible = true
	_apply()


func _process(delta: float) -> void:
	if _t >= 0.0:
		step(delta)


## Moves the card on by `delta` seconds (the frame does this; tests call it).
func step(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	_apply()
	if phase() == "gone":
		_t = -1.0
		visible = false
		finished.emit()


## "big", "small" or "gone".
func phase() -> String:
	if _t < 0.0:
		return "gone"
	if _t < BIG_SECONDS + FADE:
		return "big"
	if _t < BIG_SECONDS + FADE + SMALL_SECONDS + FADE:
		return "small"
	return "gone"


func _apply() -> void:
	var big_a := clampf(_t / 0.4, 0.0, 1.0) * (1.0 - clampf((_t - BIG_SECONDS) / FADE, 0.0, 1.0))
	var small_start := BIG_SECONDS + FADE * 0.5
	var small_end := BIG_SECONDS + FADE + SMALL_SECONDS
	var small_a := clampf((_t - small_start) / FADE, 0.0, 1.0) * (1.0 - clampf((_t - small_end) / FADE, 0.0, 1.0))
	_big.modulate.a = big_a
	_big.visible = big_a > 0.0
	_small.modulate.a = small_a
	_small.visible = small_a > 0.0


## Every line the card shows now, for tests.
func shown_text() -> String:
	var out := PackedStringArray()
	if _big.visible:
		for l in [_place, _name, _date, _credit, _extra]:
			if (l as Label).visible:
				out.append((l as Label).text)
	if _small.visible:
		out.append(_small.text)
	return "\n".join(out)


## "14 October 2026" from "2026-10-14" (the map extract's date); anything
## else comes back as it was.
static func date_text(iso: String) -> String:
	var parts := iso.strip_edges().split("-")
	if parts.size() < 3 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return iso
	var month := int(parts[1])
	var day := int(parts[2].substr(0, 2)) if parts[2].substr(0, 2).is_valid_int() else 0
	if month < 1 or month > 12 or day < 1:
		return iso
	return "%d %s %s" % [day, MONTHS[month - 1], parts[0]]
