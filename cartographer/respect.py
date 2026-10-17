"""The respect list: walls the game never lets anyone paint, whatever the
map says. Homes, schools, places of worship, hospitals, cemeteries, police
stations, shelters and memorials, as the idea file lists them. A home with
shops on its ground floor keeps the shops' shutters paintable, since that's
where real writers go too.

`paint` for a building is one of:
  NONE    nothing on it
  GROUND  the ground floor only (shopfronts and shutters under homes)
  ALL     the whole wall
"""
from shapely.prepared import prep

NONE = 0
GROUND = 1
ALL = 2

HOME_KINDS = {"house", "detached", "semidetached_house", "terrace", "residential", "apartments", "bungalow",
              "dormitory", "farm", "cabin", "houseboat", "static_caravan", "hut"}
RESPECT_KINDS = {"school", "kindergarten", "university", "college", "church", "chapel", "cathedral", "mosque",
                 "synagogue", "temple", "shrine", "religious", "monastery", "hospital", "clinic", "fire_station",
                 "police", "prison", "government", "civic", "toilets", "grandstand"}
RESPECT_AMENITIES = {"school", "kindergarten", "university", "college", "place_of_worship", "hospital", "clinic",
                     "doctors", "police", "prison", "social_facility", "shelter", "grave_yard", "funeral_hall",
                     "crematorium", "childcare", "nursing_home", "courthouse", "townhall", "fire_station",
                     "monastery"}
RESPECT_HISTORIC = {"memorial", "monument", "wayside_shrine", "church", "castle", "tomb", "cathedral"}
# Land a building can stand in that puts it on the list.
RESPECT_LAND = {("landuse", "cemetery"), ("amenity", "grave_yard"), ("amenity", "school"),
                ("amenity", "kindergarten"), ("amenity", "university"), ("amenity", "college"),
                ("amenity", "hospital"), ("amenity", "place_of_worship"), ("landuse", "religious"),
                ("landuse", "military"), ("military", None), ("amenity", "prison"), ("amenity", "police"),
                ("historic", "memorial")}
SHOP_AMENITIES = {"restaurant", "cafe", "bar", "pub", "fast_food", "bank", "ice_cream", "nightclub",
                  "bureau_de_change", "car_rental", "cinema", "theatre", "marketplace", "casino"}


class Places:
    """The map's points and land, ready for asking about one building."""

    def __init__(self, map_data):
        from shapely.geometry import Polygon
        self.respect_land = []
        for a in map_data.areas:
            tags = a["tags"]
            hit = any((k, v) in RESPECT_LAND or ((k, None) in RESPECT_LAND and k in tags) for k, v in tags.items())
            if not hit:
                continue
            for outer, inners in a["polys"]:
                try:
                    p = Polygon(outer, inners).buffer(0)
                except ValueError:
                    continue
                if not p.is_empty:
                    self.respect_land.append(prep(p))
        self.points = map_data.points

    def points_in(self, poly):
        """The tagged points inside a footprint."""
        minx, minz, maxx, maxz = poly.bounds
        from shapely.geometry import Point
        out = []
        for p in self.points:
            if minx <= p["x"] <= maxx and minz <= p["z"] <= maxz and poly.contains(Point(p["x"], p["z"])):
                out.append(p)
        return out

    def in_respect_land(self, poly):
        c = poly.representative_point()
        return any(r.contains(c) for r in self.respect_land)


def judge(tags, inside, in_land, zone=""):
    """How much of a building can be painted, from its own tags, the points
    inside it, the land it stands in and its zone (an untagged building in a
    residential zone counts as a home). Also returns whether it has shops."""
    kind = tags.get("building", "yes")
    shops = any("shop" in p["tags"] or p["tags"].get("amenity") in SHOP_AMENITIES or "craft" in p["tags"]
                or "office" in p["tags"] for p in inside)
    shops = shops or "shop" in tags or tags.get("amenity") in SHOP_AMENITIES or kind in ("retail", "commercial",
                                                                                       "kiosk", "supermarket")
    if in_land or kind in RESPECT_KINDS or tags.get("amenity") in RESPECT_AMENITIES or \
            tags.get("historic") in RESPECT_HISTORIC or "religion" in tags:
        return NONE, shops
    for p in inside:
        t = p["tags"]
        if t.get("amenity") in RESPECT_AMENITIES or t.get("historic") in RESPECT_HISTORIC or \
                t.get("healthcare") in ("hospital", "clinic", "doctor", "centre") or "social_facility" in t or \
                "religion" in t:
            return NONE, shops
    if kind in HOME_KINDS or (kind == "yes" and zone == "residential"):
        return (GROUND if shops else NONE), shops
    return ALL, shops
