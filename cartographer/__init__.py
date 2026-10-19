"""The Cartographer: turns OpenStreetMap data into All City's town tiles.

A town is built once from a dated extract and written as a folder the game
streams: town.json (the manifest), tiles/<i>_<j>.tile (one 256 m square
each) and map pictures. See docs/tiles.md for the format.
"""

## Bumped whenever the tile format changes in a way old games can't read.
FORMAT = 1
VERSION = "0.1.0"
