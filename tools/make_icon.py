#!/usr/bin/env python3
"""Draws the game's icon: a yellow spray can on inline skate wheels, leaning
into a line, with a puff of cyan paint off the nozzle, against a dusk sky
with a street lamp's glow. Writes icon.svg, the snap's copy and icon.png:

    python3 tools/make_icon.py [--out=file.svg]

Colours are the game's palette (assets/art/palette.png). Shapes are thick
and outlined in ink so it still reads at 32 px. icon.png is drawn from the
SVG by Godot itself (tools/svg_to_png.gd), so it matches what the game
shows; there are no SVG filters or text, which Godot's importer would draw
differently from a browser.
"""

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUTS = [ROOT / "icon.svg", ROOT / "snap/gui/all-city.svg"]

INK = "#14121c"
YELLOW = "#f2c641"
PINK = "#ff4fa3"
CYAN = "#3ff2ff"
HIVIS = "#c6f03c"
CHROME = "#c3ccd6"
PLASTER = "#e9dccb"
WHITE = "#f4efe6"


def build() -> str:
    svg = []
    add = svg.append
    add('<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">')
    add("  <defs>")
    add('    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">')
    add('      <stop offset="0" stop-color="#2b2a6b"/>')
    add('      <stop offset="0.62" stop-color="#6a3fb5"/>')
    add('      <stop offset="1" stop-color="#e07a8b"/>')
    add("    </linearGradient>")
    add('    <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5">')
    add('      <stop offset="0" stop-color="#ffb347" stop-opacity="0.85"/>')
    add('      <stop offset="0.55" stop-color="#ff8a5c" stop-opacity="0.35"/>')
    add('      <stop offset="1" stop-color="#ff8a5c" stop-opacity="0"/>')
    add("    </radialGradient>")
    add('    <clipPath id="tile"><rect x="0" y="0" width="512" height="512" rx="104"/></clipPath>')
    add("  </defs>")
    add('  <g clip-path="url(#tile)">')
    add('    <rect x="0" y="0" width="512" height="512" fill="url(#sky)"/>')
    add('    <circle cx="232" cy="226" r="230" fill="url(#glow)"/>')
    # The kerb the skate rides along.
    add('    <rect x="-10" y="430" width="532" height="100" fill="%s"/>' % INK)
    add('    <rect x="-10" y="418" width="532" height="20" fill="#403e4a"/>')
    # A swipe of pink paint already up on the wall behind, with drips.
    add('    <path d="M 36 168 C 70 150 112 146 150 154" fill="none" stroke="%s" stroke-width="30" stroke-linecap="round"/>' % PINK)
    for x, y0, y1 in [(66, 170, 226), (118, 162, 200)]:
        add('    <line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="12" stroke-linecap="round"/>' % (x, y0, x, y1, PINK))
    # The can on its skate, leaning into the line.
    add('    <g transform="translate(246 276) rotate(14)">')
    # Frame and wheels.
    add('      <rect x="-128" y="118" width="256" height="30" rx="12" fill="%s" stroke="%s" stroke-width="12"/>' % (CHROME, INK))
    for x in (-92, -31, 31, 92):
        add('      <circle cx="%d" cy="166" r="31" fill="%s" stroke="%s" stroke-width="12"/>' % (x, HIVIS, INK))
        add('      <circle cx="%d" cy="166" r="9" fill="%s"/>' % (x, INK))
    # Body, label band, shine.
    add('      <rect x="-96" y="-150" width="192" height="276" rx="38" fill="%s"/>' % YELLOW)
    add('      <rect x="-96" y="-42" width="192" height="72" fill="%s"/>' % PINK)
    add('      <rect x="-66" y="-128" width="24" height="232" rx="12" fill="%s" opacity="0.6"/>' % WHITE)
    add('      <rect x="-96" y="-150" width="192" height="276" rx="38" fill="none" stroke="%s" stroke-width="16"/>' % INK)
    # Shoulder and nozzle.
    add('      <rect x="-70" y="-200" width="140" height="64" rx="22" fill="%s" stroke="%s" stroke-width="16"/>' % (PLASTER, INK))
    add('      <rect x="-26" y="-242" width="52" height="50" rx="10" fill="%s" stroke="%s" stroke-width="14"/>' % (PINK, INK))
    add("    </g>")
    # The puff of paint off the nozzle, up and to the right.
    for cx, cy, r, op in [(350, 84, 30, 1.0), (402, 66, 24, 0.95), (400, 122, 22, 0.9), (444, 96, 18, 0.85),
                          (452, 50, 14, 0.75), (474, 140, 12, 0.7), (432, 160, 10, 0.6), (482, 86, 9, 0.6)]:
        add('    <circle cx="%d" cy="%d" r="%d" fill="%s" stroke="%s" stroke-width="8" opacity="%.2f"/>' % (cx, cy, r, CYAN, INK, op))
    # Speed lines behind the skate.
    for y, x0, x1 in [(300, 14, 96), (346, 28, 112), (392, 10, 74)]:
        add('    <line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="14" stroke-linecap="round"/>' % (x0, y, x1, y, WHITE))
    add("  </g>")
    add('  <rect x="4" y="4" width="504" height="504" rx="100" fill="none" stroke="%s" stroke-width="8"/>' % INK)
    add("</svg>")
    return "\n".join(svg) + "\n"


def main() -> None:
    svg = build()
    outs = [Path(a[6:]).resolve() for a in sys.argv if a.startswith("--out=")] or OUTPUTS
    for path in outs:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(svg)
        print("wrote", path)
    if not any(a.startswith("--out=") for a in sys.argv):
        subprocess.run(["godot", "--headless", "--path", str(ROOT), "-s", "tools/svg_to_png.gd", "--", "icon.svg", "icon.png", "512"],
                       check=False)


if __name__ == "__main__":
    main()
