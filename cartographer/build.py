"""Builds a town from an OpenStreetMap extract: reads the map in the town's
box, shapes the land, lays the streets, steps, bridges and buildings, scores
the walls, names the quarters, and writes the tiles and manifest.
"""
import datetime
import math
import random
import time

import numpy as np
import shapely
from shapely.geometry import Polygon

from . import buildings, eyes, ground, lines, network, osm, props, quarters, respect, terrain, tiles, water
from .geo import Box, Projection, stable_seed

ATTRIBUTION = "Map data © OpenStreetMap contributors, available under the Open Database License (ODbL)"
LEFT_HAND = {"gb", "ie", "jp", "au", "nz", "in", "za", "hk", "mo", "sg", "my", "th", "id", "ke", "ug", "tz", "cy",
             "mt", "jm", "bb", "tt", "lk", "bd", "pk", "np", "bt", "mu", "bw", "na", "zm", "zw", "mw", "mz"}
# Standard time offsets (minutes) for countries in one zone; others go by longitude.
UTC_OFFSET = {"gb": 0, "ie": 0, "pt": 0, "is": 0, "fr": 60, "mc": 60, "de": 60, "it": 60, "es": 60, "nl": 60,
              "be": 60, "ch": 60, "at": 60, "dk": 60, "se": 60, "no": 60, "pl": 60, "cz": 60, "hu": 60, "hr": 60,
              "si": 60, "sk": 60, "lu": 60, "mt": 60, "fi": 120, "gr": 120, "ro": 120, "bg": 120, "ee": 120,
              "lv": 120, "lt": 120, "ua": 120, "cy": 120, "jp": 540, "kr": 540, "nz": 720, "in": 330, "sg": 480,
              "hk": 480, "cn": 480, "za": 120, "ie_": 0}


def log(*parts):
    print("  " + " ".join(str(p) for p in parts), flush=True)


def build_town(pbf, out_dir, town_id, name, lat, lon, radius=1600.0, country="", terrain_source="terrarium",
               cache=None, data_date=None):
    """Builds `name` around (lat, lon), `radius` metres each way, from the
    extract at `pbf` into `out_dir`. Returns the manifest's stats."""
    t_start = time.time()
    times = {}
    proj = Projection(lat, lon)
    box = Box(-radius, -radius, radius, radius)

    def lap(what):
        times[what] = round(time.time() - lap.t, 2)
        lap.t = time.time()
    lap.t = time.time()

    m = osm.read(pbf, proj, box)
    lap("read")
    log("read", len(m.buildings), "buildings,", len(m.lines), "lines,", len(m.areas), "areas")

    if terrain_source == "flat":
        field = terrain.flat(box, 10.0)
    else:
        try:
            field = terrain.clean(terrain.sample(proj, box, cache=cache))
        except OSError as e:
            log("no elevation tiles (%s): the land is flat" % e)
            field = terrain.flat(box, 10.0)
    sea = water.sea(m, box)
    xs = field.x0 + np.arange(field.nx) * field.cell
    zs = field.z0 + np.arange(field.nz) * field.cell
    gx, gz = np.meshgrid(xs, zs)
    if sea is not None:
        terrain.apply_sea(field, shapely.contains_xy(sea, gx, gz))
    lakes = water.areas(m)
    lap("terrain")

    ws = network.ways(m)
    flight_list = [f for f in network.flights(m, field, ws) if f["rise"] > 0.0]
    for f in flight_list:
        steps = f["steps"]
        f["rise"] = min(0.21, max(0.1, f["rise"]))
        rng = random.Random(stable_seed("flight", f["way"], round(f["bottom"][0]), round(f["bottom"][2])))
        f["walls"] = rng.random() < 0.55
        f["steps"] = steps
    network.carve(field, flight_list)
    bridge_list = network.bridges(field, ws)
    road = network.surface(ws, "motor")
    walk = network.surface(ws, "walk")
    rail = network.surface(ws, "rail")
    lap("network")
    log(len(ws), "ways,", len(flight_list), "flights,", len(bridge_list), "bridges")

    places = respect.Places(m)
    built = buildings.build(m, field, ws, proj, country=country, places=places)
    lap("buildings")
    log(len(built), "buildings,", sum(len(b["faces"]) for b in built), "walls")

    eyes.score(built, ws, field, box)
    lap("eyes")
    qs = quarters.build(m, ws, box, name)
    for b in built:
        for f in b["faces"]:
            f["quarter"] = qs.at((f["p0"][0] + f["p1"][0]) * 0.5, (f["p0"][2] + f["p1"][2]) * 0.5)["id"]
    lap("quarters")

    cover = ground.Cover(m, road, walk, rail)
    green_areas = []
    for a in m.areas:
        tags = a["tags"]
        kind = "wood" if tags.get("landuse") == "forest" or tags.get("natural") == "wood" else \
            "park" if tags.get("leisure") in ("park", "garden") else None
        if kind is None:
            continue
        for outer, inners in a["polys"]:
            try:
                p = Polygon(outer, inners).buffer(0)
            except (ValueError, TypeError):
                continue
            if not p.is_empty and p.area > 50:
                green_areas.append((kind, p))
    prop_list = props.place(m, ws, field, road, built, green_areas)
    wire_lines, poles = lines.wires(m, field)
    prop_list += poles
    lap("props")

    town = tiles.Town(box)
    for b in built:
        town.add_building(b)
    line_list = []
    line_list += lines.kerbs(network.kerbs(ws, ground._polys(m, ground.PAVED)), field)
    line_list += lines.barriers(m, field)
    line_list += lines.rails(ws, field)
    line_list += wire_lines
    line_list += lines.parapets(bridge_list)
    for l in line_list:
        if len(l["pts"]) >= 2:
            town.add_line(l)
    for f in flight_list:
        town.add_flight(f)
    for b in bridge_list:
        town.add_bridge(b)
    for p in prop_list:
        town.add_prop(p)
    for lane in network.lanes(ws, "left" if country in LEFT_HAND else "right"):
        pts = lane["pts"]
        hs = np.atleast_1d(field.at(np.array([p[0] for p in pts]), np.array([p[1] for p in pts])))
        lane["pts"] = [(x, float(h) + 0.02, z) for (x, z), h in zip(pts, hs)]
        if not lane["bridge"]:
            town.add_lane(lane)
    if sea is not None:
        town.add_water(sea, 0.0)
    for lake in lakes:
        level = float(np.min(field.at(*np.asarray(lake.exterior.coords).T))) - 0.3
        town.add_water(lake, level)
    lap("tiles")

    spawn = _spawn(flight_list, field)
    manifest = {
        "id": town_id, "name": name, "country": country, "drive": "left" if country in LEFT_HAND else "right",
        "utc_offset_min": UTC_OFFSET.get(country, int(round(lon / 15.0)) * 60),
        "origin": {"lat": lat, "lon": lon}, "box": box.as_list(),
        "data_date": data_date or m.newest, "built": datetime.date.today().isoformat(),
        "attribution": [ATTRIBUTION, terrain.ATTRIBUTION], "spawn": spawn,
        "stats": {"buildings": len(built), "walls": sum(len(b["faces"]) for b in built), "flights": len(flight_list),
                  "bridges": len(bridge_list), "lines": len(line_list), "props": len(prop_list),
                  "quarters": len(qs.list)},
    }
    total = town.write(out_dir, field, cover, qs, manifest)
    lap("write")
    manifest["stats"]["seconds"] = round(time.time() - t_start, 1)
    manifest["stats"]["times"] = times
    manifest["stats"]["tile_bytes"] = total
    # Write the manifest again with the build's own time in it.
    import json
    import os
    with open(os.path.join(out_dir, "town.json"), "r", encoding="utf-8") as f:
        written = json.load(f)
    written["stats"] = manifest["stats"]
    with open(os.path.join(out_dir, "town.json"), "w", encoding="utf-8") as f:
        json.dump(written, f, indent=1, ensure_ascii=False)
        f.write("\n")
    return manifest["stats"]


def _spawn(flight_list, field):
    """Where a writer starts: at the foot of the town's best staircase near
    the middle, looking up it."""
    best, best_score = None, -1.0
    for f in flight_list:
        bx, _, bz = f["bottom"]
        score = f["steps"] * (1.5 if f["width"] >= 3.0 else 1.0) / (1.0 + math.hypot(bx, bz) / 700.0)
        if score > best_score:
            best, best_score = f, score
    if best is None:
        return {"p": [0.0, float(field.at(0.0, 0.0)) + 0.5, 0.0], "yaw": 0.0}
    bx, by, bz = best["bottom"]
    ux, uz = best["up"]
    x, z = bx - ux * 7.0, bz - uz * 7.0
    return {"p": [round(x, 2), round(float(field.at(x, z)) + 0.5, 2), round(z, 2)],
            "yaw": round(math.atan2(-ux, -uz), 4)}
