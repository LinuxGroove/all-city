"""The Cartographer's command line:

  python3 -m cartographer build "Hebden Bridge"          find it, fetch its extract, build it
  python3 -m cartographer build Monaco --pbf monaco.osm.pbf --lat 43.7384 --lon 7.4246 --country mc
  python3 -m cartographer build "Totnes" --overpass       quick try from the Overpass API
  python3 -m cartographer map ~/.local/share/all-city/towns/monaco [--shade=eyes] [--out map.png]
  python3 -m cartographer info ~/.local/share/all-city/towns/monaco

A built town goes to the game's own towns folder (where the game finds it
under Play) unless --out says elsewhere.
"""
import argparse
import json
import os
import re
import sys
import time


def default_towns():
    data = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")
    return os.path.join(data, "all-city", "towns")


def slug(name):
    s = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return (s or "town")[:48]


def main(argv=None):
    ap = argparse.ArgumentParser(prog="cartographer", description="Builds All City towns from OpenStreetMap.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build", help="build a town")
    b.add_argument("town", help="the town's name, as you'd search for it on a map")
    b.add_argument("--pbf", help="an OpenStreetMap extract (.osm.pbf or .osm) to build from")
    b.add_argument("--overpass", action="store_true", help="fetch the box from the Overpass API (quick tries only)")
    b.add_argument("--lat", type=float)
    b.add_argument("--lon", type=float)
    b.add_argument("--country", default=None, help="two-letter country code (picks the style kit and the time zone)")
    b.add_argument("--radius", type=float, default=1280.0, help="metres from the middle to each edge (default 1280)")
    b.add_argument("--out", help="the town's folder (default: the game's towns folder)")
    b.add_argument("--id", help="the town's id (default: from its name)")
    b.add_argument("--flat", action="store_true", help="don't fetch elevation: the land is flat")
    b.add_argument("--no-lidar", action="store_true",
                   help="don't look for an open lidar survey (heights, ground and trees by rule)")
    b.add_argument("--cache", default=os.path.join(os.path.expanduser("~"), ".cache", "all-city"))
    m = sub.add_parser("map", help="draw a built town")
    m.add_argument("folder")
    m.add_argument("--out")
    m.add_argument("--shade", default="height", choices=["height", "eyes", "respect"])
    m.add_argument("--scale", type=float, default=0.5, help="pixels a metre")
    i = sub.add_parser("info", help="a built town's numbers")
    i.add_argument("folder")
    args = ap.parse_args(argv)

    if args.cmd == "map":
        from . import mapimage
        out = args.out or os.path.join(args.folder, "map_%s.png" % args.shade)
        print(mapimage.draw(args.folder, out, args.scale, args.shade))
        return 0
    if args.cmd == "info":
        with open(os.path.join(args.folder, "town.json"), encoding="utf-8") as f:
            town = json.load(f)
        print("%s (%s), map data of %s, built %s" % (town["name"], town["id"], town["data_date"], town["built"]))
        print(json.dumps(town.get("stats", {}), indent=1))
        return 0

    from . import build, fetch
    t0 = time.time()
    name, lat, lon, country = args.town, args.lat, args.lon, args.country
    if lat is None or lon is None:
        print("Finding %s..." % args.town, flush=True)
        found = fetch.find(args.town)
        print("  %s" % found["display"])
        name, lat, lon = found["name"], found["lat"], found["lon"]
        country = country or found["country"]
    country = (country or "").lower()
    town_id = args.id or slug(name)
    out = args.out or os.path.join(default_towns(), town_id)
    os.makedirs(args.cache, exist_ok=True)
    from .geo import Box, Projection, latlon_box
    proj = Projection(lat, lon)
    bounds = latlon_box(proj, Box(-args.radius, -args.radius, args.radius, args.radius).grow(200.0))
    if args.pbf:
        pbf = args.pbf
    elif args.overpass:
        print("Fetching the map from Overpass...", flush=True)
        pbf = fetch.overpass(bounds, os.path.join(args.cache, town_id + ".osm"))
    else:
        print("Fetching the map extract...", flush=True)
        region = fetch.extract(lat, lon, os.path.join(args.cache, "extracts"))
        pbf = fetch.clip(region, bounds, os.path.join(args.cache, town_id + ".osm.pbf"))
    print("Building %s into %s" % (name, out), flush=True)
    stats = build.build_town(pbf, out, town_id, name, lat, lon, radius=args.radius, country=country,
                             terrain_source="flat" if args.flat else "terrarium",
                             cache=os.path.join(args.cache, "terrain"), lidar_mode="off" if args.no_lidar else "auto",
                             lidar_cache=args.cache)
    print("Built %s in %.0f s: %d buildings, %d walls, %d flights of steps, %.1f MB of tiles" % (
        name, time.time() - t0, stats["buildings"], stats["walls"], stats["flights"], stats["tile_bytes"] / 1e6))
    return 0


if __name__ == "__main__":
    sys.exit(main())
