"""Finding a town and its map data on a developer's machine.

`find(name)` asks Nominatim where a town is. `extract()` downloads the
smallest Geofabrik extract that covers it (dated regional files, which is
what the Cartographer builds from) and, when the `osmium` tool is installed,
cuts the town's box out of it so reading is quick. `overpass()` fetches just
the box from the Overpass API instead, for quick tries only: Overpass isn't
for production use, and a built town should name a dated extract.

All of it caches under `cache` and sends a User-Agent naming the game, as
the services' policies ask.
"""
import json
import os
import shutil
import subprocess
import urllib.parse
import urllib.request

from .terrain import USER_AGENT

NOMINATIM = "https://nominatim.openstreetmap.org/search"
GEOFABRIK_INDEX = "https://download.geofabrik.de/index-v1.json"
OVERPASS = "https://overpass-api.de/api/interpreter"


def _get(url, timeout=120):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def find(name):
    """The town called `name`: {"name", "lat", "lon", "country", "bbox": (s, w, n, e)}."""
    q = urllib.parse.urlencode({"q": name, "format": "jsonv2", "limit": 1, "addressdetails": 1})
    found = json.loads(_get(NOMINATIM + "?" + q))
    if not found:
        raise LookupError("No town called %r on the map" % name)
    f = found[0]
    s, n, w, e = (float(v) for v in f["boundingbox"])
    address = f.get("address", {})
    short = address.get("city") or address.get("town") or address.get("village") or f.get("name") or name
    return {"name": short, "lat": float(f["lat"]), "lon": float(f["lon"]),
            "country": address.get("country_code", "").lower(), "bbox": (s, w, n, e),
            "display": f.get("display_name", name)}


def _contains(geom, lat, lon):
    """Whether a GeoJSON (Multi)Polygon contains a point (ray casting)."""
    polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
    for poly in polys:
        inside = False
        ring = poly[0]
        for (x0, y0), (x1, y1) in zip(ring, ring[1:]):
            if (y0 > lat) != (y1 > lat) and lon < (x1 - x0) * (lat - y0) / (y1 - y0) + x0:
                inside = not inside
        if inside:
            return True
    return False


def _area(geom):
    polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
    total = 0.0
    for poly in polys:
        ring = poly[0]
        total += abs(sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(ring, ring[1:]))) * 0.5
    return total


def extract(lat, lon, cache):
    """The path of the smallest Geofabrik extract covering (lat, lon),
    downloaded into `cache` if it isn't there (they're updated daily; delete
    one to fetch a newer copy)."""
    os.makedirs(cache, exist_ok=True)
    index_path = os.path.join(cache, "geofabrik-index.json")
    if not os.path.exists(index_path):
        with open(index_path, "wb") as f:
            f.write(_get(GEOFABRIK_INDEX))
    with open(index_path, encoding="utf-8") as f:
        index = json.load(f)
    best = None
    for feat in index["features"]:
        props = feat["properties"]
        url = props.get("urls", {}).get("pbf")
        if not url or not feat.get("geometry") or not _contains(feat["geometry"], lat, lon):
            continue
        area = _area(feat["geometry"])
        if best is None or area < best[0]:
            best = (area, props["id"], url)
    if best is None:
        raise LookupError("No Geofabrik extract covers %.4f, %.4f" % (lat, lon))
    path = os.path.join(cache, best[1].replace("/", "_") + "-latest.osm.pbf")
    if not os.path.exists(path):
        print("  downloading %s" % best[2], flush=True)
        req = urllib.request.Request(best[2], headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=600) as r, open(path + ".part", "wb") as f:
            shutil.copyfileobj(r, f, 1 << 20)
        os.replace(path + ".part", path)
    return path


def clip(pbf, bounds, out_path):
    """Cuts (s, w, n, e) out of an extract with the osmium tool when it's
    installed (much quicker to read than a whole region); otherwise returns
    the extract itself."""
    tool = shutil.which("osmium")
    if tool is None:
        return pbf
    s, w, n, e = bounds
    subprocess.run([tool, "extract", "--overwrite", "-s", "smart", "-b", "%f,%f,%f,%f" % (w, s, e, n), pbf,
                    "-o", out_path], check=True)
    return out_path


def overpass(bounds, out_path):
    """Everything in (s, w, n, e) from the Overpass API, as an .osm file.
    For quick tries on a developer's machine only."""
    s, w, n, e = bounds
    query = "[out:xml][timeout:300];(nwr(%f,%f,%f,%f););(._;>;);out meta;" % (s, w, n, e)
    data = _get(OVERPASS + "?" + urllib.parse.urlencode({"data": query}), timeout=600)
    with open(out_path, "wb") as f:
        f.write(data)
    return out_path
