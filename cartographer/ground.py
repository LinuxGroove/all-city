"""The ground's paint: what covers each half metre of a tile, as an RGBA
picture the terrain shader reads. Red is carriageway, green paving
(pavements, squares, car parks), blue grass and planting, and alpha the
ballast under railway tracks. Bare earth (and sand) is none of them.
"""
import io

from PIL import Image, ImageDraw, ImageFilter
from shapely.geometry import Polygon, box as shapely_box
from shapely.ops import unary_union

PIXELS = 512

GREEN = {("leisure", "park"), ("leisure", "garden"), ("leisure", "pitch"), ("leisure", "playground"),
         ("leisure", "golf_course"), ("leisure", "common"), ("leisure", "dog_park"), ("leisure", "recreation_ground"),
         ("landuse", "grass"), ("landuse", "meadow"), ("landuse", "forest"), ("landuse", "village_green"),
         ("landuse", "recreation_ground"), ("landuse", "cemetery"), ("landuse", "allotments"), ("landuse", "orchard"),
         ("landuse", "farmland"), ("landuse", "vineyard"), ("natural", "wood"), ("natural", "scrub"),
         ("natural", "grassland"), ("natural", "heath"), ("amenity", "grave_yard")}
PAVED = {("amenity", "parking"), ("highway", "pedestrian"), ("area:highway", "pedestrian"),
         ("area:highway", "footway"), ("place", "square"), ("amenity", "marketplace"), ("leisure", "marina"),
         ("man_made", "pier"), ("man_made", "quay"), ("railway", "platform"), ("amenity", "fuel"),
         ("landuse", "railway")}


def _polys(map_data, kinds):
    out = []
    for a in map_data.areas:
        if not any((k, v) in kinds for k, v in a["tags"].items()):
            continue
        for outer, inners in a["polys"]:
            try:
                p = Polygon(outer, inners).buffer(0)
            except (ValueError, TypeError):
                continue
            if not p.is_empty:
                out.append(p)
    return unary_union(out) if out else None


class Cover:
    """The town's cover, ready to paint tile by tile."""

    def __init__(self, map_data, road, walk, rail):
        self.road = road
        green = _polys(map_data, GREEN)
        paved = _polys(map_data, PAVED)
        walk_all = unary_union([g for g in (walk, paved) if g is not None]) if (walk or paved) else None
        if walk_all is not None and road is not None:
            walk_all = walk_all.difference(road)
        if green is not None and walk_all is not None:
            green = green.difference(walk_all)
        if green is not None and road is not None:
            green = green.difference(road)
        self.walk = walk_all
        self.green = green
        self.rail = rail

    def picture(self, x0, z0, size):
        """The tile's cover as PNG bytes."""
        frame = shapely_box(x0, z0, x0 + size, z0 + size).buffer(2.0)
        scale = PIXELS / size
        bands = []
        for geom in (self.road, self.walk, self.green, self.rail):
            img = Image.new("L", (PIXELS, PIXELS), 0)
            if geom is not None:
                part = geom.intersection(frame)
                _draw(ImageDraw.Draw(img), part, x0, z0, scale)
                img = img.filter(ImageFilter.BoxBlur(0.6))
            bands.append(img)
        out = io.BytesIO()
        Image.merge("RGBA", bands).save(out, format="PNG", compress_level=6)
        return out.getvalue()


def _draw(draw, geom, x0, z0, scale):
    if geom.is_empty:
        return
    if geom.geom_type == "Polygon":
        draw.polygon([((x - x0) * scale, (z - z0) * scale) for x, z in geom.exterior.coords], fill=255)
        for hole in geom.interiors:
            draw.polygon([((x - x0) * scale, (z - z0) * scale) for x, z in hole.coords], fill=0)
    elif hasattr(geom, "geoms"):
        for g in geom.geoms:
            _draw(draw, g, x0, z0, scale)
