"""Builds every All City model into assets/models/<set>/<name>.glb.

    /path/to/venv/bin/python tools/blender/build_art.py [set ...] [--only name,name]

The venv needs the `bpy` wheel from PyPI (Blender as a Python module).
Sets: street, stairs, facade, vehicles, gear. Prints each model's triangle
count, which the game's budget is judged by.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import ackit  # noqa: E402

SETS = {}


def _load_sets():
    import street_props
    SETS["street"] = street_props.ASSETS
    for mod, key in (("stair_set", "stairs"), ("facade_kit", "facade"), ("vehicles", "vehicles"), ("gear", "gear")):
        try:
            m = __import__(mod)
        except ImportError:
            continue
        SETS[key] = m.ASSETS


def main(argv):
    _load_sets()
    only = None
    names = []
    for a in argv:
        if a.startswith("--only="):
            only = set(a.split("=", 1)[1].split(","))
        else:
            names.append(a)
    total = 0
    for set_name, assets in SETS.items():
        if names and set_name not in names:
            continue
        for name, fn in assets.items():
            if only and name not in only:
                continue
            ackit.reset()
            ob = fn()
            path = os.path.join(ackit.ROOT, "assets", "models", set_name, name + ".glb")
            ackit.export(ob, path)
            tris = ackit.tri_count(ob)
            total += 1
            print("%-10s %-24s %6d tris" % (set_name, name, tris))
    print("built %d models" % total)


if __name__ == "__main__":
    main(sys.argv[1:])
