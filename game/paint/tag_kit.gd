class_name TagKit
extends RefCounted
## The letter kit: draws a writer's name as paint. A kit is the small
## Dictionary that goes to the server with the paint (see `kit_for`), and
## `art` turns it into two masks, the letters' fill and their ink outline,
## drawn once per name, style and seed and kept in memory. Colours, drips,
## fading and wobble are the paint shader's (game/paint/paint.gdshader), so
## one drawing serves every colour a writer sprays it in.
##
## The letters come straight from the fonts' glyphs as the text server
## rasterizes them, composited with Image operations on the CPU: no
## viewport, no frame to wait for and no read back from the GPU, so it runs
## headless (tests, the server checks) and gives the same masks on every
## machine for the same kit.
##
## Styles at M0: "handstyle" (tags: Permanent Marker, the first letter big,
## a climbing baseline, a slight slant and an ink outline) and "bubble"
## (throw-ups: Bungee swollen into bubble letters that overlap, each with a
## fat ink outline).

const FONTS := {
	"handstyle": preload("res://assets/fonts/PermanentMarker-Regular.ttf"),
	"bubble": preload("res://assets/fonts/Bungee-Regular.ttf"),
}
## The style each rank paints in at M0.
const RANK_STYLE := {"tag": "handstyle", "throwup": "bubble", "piece": "bubble", "burner": "bubble"}
## How tall each rank's paint stands on a wall, drips and all, in metres.
const HEIGHT := {"tag": 0.95, "throwup": 1.6, "piece": 2.2, "burner": 2.8}
## The name a writer who hasn't picked one paints.
const UNNAMED := "TOY"
## The crew's colours when the writer has none: fill, ink, second fill.
const COLOURS := ["3ff2ff", "14121c", "2846b8"]
const MIN_LETTERS := 2
const MAX_LETTERS := 6
## Letter size in pixels.
const GLYPH := 150
## The share of the drawing below the letters, for drips to run into.
const DRIP_ROOM := 0.3
## The most drips a piece of paint carries (the shader's array).
const MAX_DRIPS := 8

static var _cache := {}


## A name as the kit writes it: capitals and digits, up to six; "" when
## fewer than two are left.
static func clean_name(text: String) -> String:
	var out := ""
	for c in text.to_upper():
		if (c >= "A" and c <= "Z") or (c >= "0" and c <= "9"):
			out += c
	out = out.left(MAX_LETTERS)
	return out if out.length() >= MIN_LETTERS else ""


## The kit for a writer painting `rank`: the name, style, seed (the same
## for every tag a name makes, so a writer's tag is their own), the crew's
## colours as hex, how tall it stands and the style's own drips. `at` (the
## spot on the wall), more drips and the wobble are added by the painting.
static func kit_for(name: String, rank: String, colours: Array = []) -> Dictionary:
	var clean := clean_name(name)
	if clean == "":
		clean = UNNAMED
	var style: String = RANK_STYLE.get(rank, "handstyle")
	var hexes := []
	for i in COLOURS.size():
		var c = colours[i] if i < colours.size() else COLOURS[i]
		hexes.append(c.to_html(false) if c is Color else str(c).trim_prefix("#"))
	var kit := {
		"v": 1,
		"name": clean,
		"style": style,
		"seed": absi(hash(clean)) % 100000,
		"colours": hexes,
		"h": float(HEIGHT.get(rank, HEIGHT.tag)),
		"drips": [],
		"wobble": 0.0,
	}
	# A tag's own drips: a couple under its letters, from the seed.
	var a := art(kit)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(kit.seed) + 7
	var feet: Array = a.feet
	if style == "handstyle" and feet.size() > 0:
		for i in 2:
			var foot: Vector2 = feet[rng.randi() % feet.size()]
			kit.drips.append(_round([foot.x + rng.randf_range(-0.02, 0.02), foot.y - 0.02, rng.randf_range(0.06, 0.16)]))
	return kit


## The drawing for a kit, cached: {fill, ink (ImageTextures, white where
## there's paint), fill_image, ink_image, aspect (width over height), guide
## (the path the spray follows, in UV, y down), feet (the bottom middle of
## each letter, in UV), letters (each letter's box in UV)}.
static func art(kit: Dictionary) -> Dictionary:
	var style := str(kit.get("style", "handstyle"))
	if not FONTS.has(style):
		style = "handstyle"
	var name := clean_name(str(kit.get("name", "")))
	if name == "":
		name = UNNAMED
	var seed := int(kit.get("seed", 0))
	var key := "%s/%s/%d" % [style, name, seed]
	if not _cache.has(key):
		_cache[key] = _draw(name, style, seed)
	return _cache[key]


## Forgets every drawing (they're made again when asked for).
static func clear_cache() -> void:
	_cache.clear()


static func _draw(name: String, style: String, seed: int) -> Dictionary:
	var bubble := style == "bubble"
	var font: FontFile = FONTS[style]
	var rid: RID = font.get_rids()[0]
	var ts := TextServerManager.get_primary_interface()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# Outlines grow a glyph by a quarter of their size on every side.
	var ink_grow := int(GLYPH * (0.6 if bubble else 0.36))
	var body_grow := int(GLYPH * 0.26) if bubble else 0
	var tracking := 0.9 if bubble else 0.84
	var slant := 0.0 if bubble else rng.randf_range(0.13, 0.2)
	var letters := []
	var pen := 0.0
	for i in name.length():
		var px := GLYPH
		if bubble:
			px = int(GLYPH * rng.randf_range(0.94, 1.04))
		elif i == 0:
			px = int(GLYPH * 1.25)
		else:
			px = int(GLYPH * rng.randf_range(0.9, 1.03))
		var g := ts.font_get_glyph_index(rid, px, name.unicode_at(i), 0)
		if g == 0:
			continue
		var lift := rng.randf_range(-1.0, 1.0) * px * 0.04
		if not bubble:
			lift -= i * px * 0.04
		var origin := Vector2(pen, lift)
		var ink := _glyph(ts, rid, Vector2i(px, ink_grow), g)
		var fill := _glyph(ts, rid, Vector2i(px, body_grow), g)
		if ink.is_empty() or fill.is_empty():
			continue
		letters.append({"origin": origin, "ink": ink, "fill": fill})
		pen += ts.font_get_glyph_advance(rid, px, g).x * tracking
	if letters.is_empty():
		return _blank()
	# Lay the letters out: their ink boxes, then the drawing round them.
	var box := Rect2()
	for i in letters.size():
		var l: Dictionary = letters[i]
		var r := Rect2(l.origin + l.ink.offset, Vector2(l.ink.white.get_size()))
		box = r if i == 0 else box.merge(r)
	var pad := 10.0
	var letters_h := box.size.y + pad * 2.0
	var h := int(ceil(letters_h / (1.0 - DRIP_ROOM)))
	var w := int(ceil(box.size.x + pad * 2.0 + slant * h))
	var shift := Vector2(pad, pad) - box.position
	var fill_img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var ink_img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	fill_img.fill(Color.BLACK)
	ink_img.fill(Color.BLACK)
	# Each letter goes over the ones before it: its outline cuts them.
	var rects: Array[Rect2] = []
	for l in letters:
		var ink_at := Vector2i((l.origin + l.ink.offset + shift).round())
		var fill_at := Vector2i((l.origin + l.fill.offset + shift).round())
		var ink_img_l: Image = l.ink.white
		var fill_img_l: Image = l.fill.white
		ink_img.blend_rect(ink_img_l, Rect2i(Vector2i.ZERO, ink_img_l.get_size()), ink_at)
		fill_img.blend_rect(l.ink.black, Rect2i(Vector2i.ZERO, ink_img_l.get_size()), ink_at)
		fill_img.blend_rect(fill_img_l, Rect2i(Vector2i.ZERO, fill_img_l.get_size()), fill_at)
		rects.append(Rect2(Vector2(fill_at), Vector2(fill_img_l.get_size())))
	if slant > 0.0:
		fill_img = _shear(fill_img, slant)
		ink_img = _shear(ink_img, slant)
	fill_img.convert(Image.FORMAT_L8)
	ink_img.convert(Image.FORMAT_L8)
	fill_img.generate_mipmaps()
	ink_img.generate_mipmaps()
	# The guide: down and up through each letter for a tag, round each
	# letter for a throw-up; feet for drips; boxes, all in UV.
	var size := Vector2(w, h)
	var guide := PackedVector2Array()
	var feet: Array[Vector2] = []
	var boxes: Array[Rect2] = []
	for r in rects:
		var pts: Array[Vector2] = []
		if bubble:
			pts = [r.position + r.size * Vector2(0.25, 0.2), r.position + r.size * Vector2(0.18, 0.78),
				r.position + r.size * Vector2(0.6, 0.85), r.position + r.size * Vector2(0.78, 0.3)]
		else:
			pts = [r.position + r.size * Vector2(0.2, 0.18), r.position + r.size * Vector2(0.45, 0.85),
				r.position + r.size * Vector2(0.78, 0.2)]
		for p in pts:
			guide.append(_sheared(p, slant, h) / size)
		feet.append(_sheared(r.position + r.size * Vector2(0.5, 0.92), slant, h) / size)
		boxes.append(Rect2(_sheared(r.position + Vector2(0, r.size.y), slant, h) / size, r.size / size))
	return {
		"fill": ImageTexture.create_from_image(fill_img),
		"ink": ImageTexture.create_from_image(ink_img),
		"fill_image": fill_img,
		"ink_image": ink_img,
		"aspect": float(w) / float(h),
		"guide": guide,
		"feet": feet,
		"letters": boxes,
	}


## One glyph at a size and outline, as a white image with its coverage in
## alpha and a black one for cutting, and where it sits from the pen.
static func _glyph(ts: TextServer, rid: RID, size: Vector2i, g: int) -> Dictionary:
	ts.font_render_glyph(rid, size, g)
	var uv := Rect2i(ts.font_get_glyph_uv_rect(rid, size, g))
	if uv.size.x <= 0 or uv.size.y <= 0:
		return {}
	var page := ts.font_get_texture_image(rid, size, ts.font_get_glyph_texture_idx(rid, size, g))
	if page == null:
		return {}
	var white := page.get_region(uv)
	white.convert(Image.FORMAT_RGBA8)
	var black := white.duplicate() as Image
	black.adjust_bcs(0.0, 1.0, 1.0)
	return {"white": white, "black": black, "offset": ts.font_get_glyph_offset(rid, size, g)}


## Leans the image right by `slant` (the top row moves furthest).
static func _shear(img: Image, slant: float) -> Image:
	var h := img.get_height()
	var out := Image.create(img.get_width(), h, false, img.get_format())
	out.fill(Color.BLACK)
	for y in h:
		out.blit_rect(img, Rect2i(0, y, img.get_width(), 1), Vector2i(roundi(slant * (h - 1 - y)), y))
	return out


static func _sheared(p: Vector2, slant: float, h: int) -> Vector2:
	return Vector2(p.x + slant * (h - 1 - p.y), p.y)


static func _blank() -> Dictionary:
	var img := Image.create(4, 4, false, Image.FORMAT_L8)
	return {"fill": ImageTexture.create_from_image(img), "ink": ImageTexture.create_from_image(img), "fill_image": img,
		"ink_image": img, "aspect": 1.0, "guide": PackedVector2Array([Vector2(0.2, 0.5), Vector2(0.8, 0.5)]),
		"feet": [], "letters": []}


static func _round(values: Array) -> Array:
	var out := []
	for v in values:
		out.append(snappedf(float(v), 0.001))
	return out
