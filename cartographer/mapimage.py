"""A picture of a built town, read back from its tiles: the ground's cover,
buildings shaded by height (or by eyes, or by the respect list), the lines,
the steps and the quarters' names. For checking a build by eye and for the
game's own map later.
"""
import gzip
import io
import json
import os

from PIL import Image, ImageDraw, ImageFont

from .godot_variant import decode

COVER = {"road": (58, 56, 70), "walk": (150, 146, 140), "green": (92, 150, 84), "rail": (110, 92, 80)}
EARTH = (196, 178, 140)
SEA = (54, 120, 170)
LINE = {"kerb": (230, 230, 230), "fence": (40, 40, 40), "wall": (120, 70, 50), "rail": (20, 20, 20),
        "track": (90, 60, 40), "wire": (255, 210, 0), "parapet": (255, 120, 40)}


def read_tiles(folder):
    with open(os.path.join(folder, "town.json"), encoding="utf-8") as f:
        town = json.load(f)
    for i, j in town["tiles"]:
        with open(os.path.join(folder, "tiles", "%d_%d.tile" % (i, j)), "rb") as f:
            yield decode(gzip.decompress(f.read()))


def draw(folder, out_path, scale=0.5, shade="height"):
    """Writes a PNG of the town at `scale` pixels a metre; `shade` is
    "height", "eyes" or "respect"."""
    with open(os.path.join(folder, "town.json"), encoding="utf-8") as f:
        town = json.load(f)
    x0, z0, x1, z1 = town["box"]
    w, h = int((x1 - x0) * scale), int((z1 - z0) * scale)
    img = Image.new("RGB", (w, h), EARTH)
    d = ImageDraw.Draw(img)

    def px(x, z):
        return ((x - x0) * scale, (z - z0) * scale)

    tiles = list(read_tiles(folder))
    for t in tiles:
        cover = Image.open(io.BytesIO(t["ground"])).convert("RGBA")
        size = int(t["size"] * scale)
        # Each band on its own: resizing RGBA would multiply by the alpha band.
        bands = [b.resize((size, size), Image.BILINEAR) for b in cover.split()]
        base = Image.new("RGB", (size, size), EARTH)
        for band, colour in zip(bands, (COVER["road"], COVER["walk"], COVER["green"], COVER["rail"])):
            base.paste(Image.new("RGB", (size, size), colour), (0, 0), band)
        img.paste(base, (int((t["x0"] - x0) * scale), int((t["z0"] - z0) * scale)))
    for t in tiles:
        verts, tris = t["water"]["verts"], t["water"]["tris"]
        for k in range(0, len(tris), 3):
            d.polygon([px(verts[i][0], verts[i][2]) for i in tris[k:k + 3]], fill=SEA)
    for t in tiles:
        for b in t["buildings"]:
            if shade == "eyes":
                e = max([f["eyes"] for f in b["faces"]] or [0]) / 100.0
                colour = (int(60 + 195 * e), int(60 + 80 * (1 - e)), int(90 * (1 - e)))
            elif shade == "respect":
                colour = {0: (70, 110, 200), 1: (230, 180, 60), 2: (220, 70, 70)}[b["paint"]]
            else:
                k = min(1.0, b["storeys"] / 16.0)
                colour = (int(240 - 150 * k), int(236 - 160 * k), int(226 - 120 * k))
            ring = b["rings"][0]
            d.polygon([px(x, z) for x, z in ring], fill=colour, outline=(30, 30, 40))
        for line in t["lines"]:
            pts = [px(p[0], p[2]) for p in line["pts"]]
            if len(pts) >= 2:
                d.line(pts, fill=LINE.get(line["kind"], (255, 0, 255)), width=2 if line["kind"] == "wire" else 1)
        for f in t["flights"]:
            bx, by, bz = f["bottom"]
            ux, uz = f["up"]
            run = f["steps"] * f["going"]
            d.line([px(bx, bz), px(bx + ux * run, bz + uz * run)], fill=(255, 40, 160), width=max(2, int(f["width"] * scale)))
    try:
        font = ImageFont.truetype(os.path.join(os.path.dirname(__file__), "..", "assets", "fonts", "Montserrat.ttf"), 18)
    except OSError:
        font = ImageFont.load_default()
    for q in town.get("quarters", []):
        x, z = q["centre"]
        d.text(px(x, z), q["name"], fill=(20, 20, 30), font=font, anchor="mm", stroke_width=2, stroke_fill=(255, 255, 255))
    if "spawn" in town:
        sx, _, sz = town["spawn"]["p"]
        cx, cz = px(sx, sz)
        d.ellipse([cx - 6, cz - 6, cx + 6, cz + 6], outline=(255, 255, 255), fill=(0, 200, 255), width=2)
    img.save(out_path)
    return out_path
