# Credits

Made by Drew, Kaden, and Ken VanDine, the LinuxGroove team.

## Maps

- Every town is built from [OpenStreetMap](https://www.openstreetmap.org/)
  data by the game's Cartographer (`cartographer/`). Map data ©
  OpenStreetMap contributors, available under the Open Database License
  ([openstreetmap.org/copyright](https://www.openstreetmap.org/copyright)).
  A town's tiles are a produced work made from a dated extract of the map,
  and each town's `town.json` names the extract's date and its credits.
  The game shows "© OpenStreetMap contributors" when a town opens and
  always in About.
- The land's shape comes from the Mapzen Terrarium elevation tiles on AWS
  Open Data (SRTM, GMTED, NED, ETOPO1 and others; see
  [their attribution](https://github.com/tilezen/joerd/blob/master/docs/attribution.md)).
- Where an open lidar survey covers a town, the Cartographer measures its
  buildings' heights and roofs, its ground and its trees from it: the
  U.S. Geological Survey's 3D Elevation Program, or NOAA Office for Coastal
  Management's Digital Coast (Durham's is the 2015 NCFMP Lidar: Statewide
  North Carolina, Phase 3, from the North Carolina Floodplain Mapping
  Program), both public domain. Each town's card names its survey.
- Shops and businesses show as what they are with made-up signs, never by
  their real names, and no house numbers appear.

## Art

- The writers, the Buff's crew and everyone else in town are
  [Quaternius](https://quaternius.com)' Universal Base Characters with
  their hair, animated with the Universal Animation Library 1 and 2
  (CC0), in `assets/people/` with their licence files. The writers'
  hoodies and trousers (`assets/people/outfits/`) are made for All City by
  `tools/blender/wardrobe.py`, fitted over those bodies.
- The streets, buildings, stairs, vehicles, skateboards, backpacks and spray cans
  (`assets/models/`) and the palette they share (`assets/art/palette.png`)
  are made for All City by the Blender scripts in `tools/blender/`, CC0
  like the rest.
- The toon light and ink lines are the game's own shaders
  (`game/look/shaders/`).
- The icon is drawn by `tools/make_icon.py`.
- The shared add-on's buttons and panels are from
  [Kenney](https://kenney.nl)'s UI Pack - Adventure, and its controller
  and keyboard prompts from Kenney's Input Prompts, CC0
  (`addons/linuxgroove/ui/textures/`, `addons/linuxgroove/input/glyphs/`).

## Fonts

- [Bungee](https://github.com/djrrb/Bungee) by David Jonathan Ross and the
  Bungee Project Authors, SIL Open Font License 1.1
  (`assets/fonts/bungee-OFL.txt`).
- [Montserrat](https://github.com/JulietaUla/Montserrat) by Julieta
  Ulanovsky and the Montserrat Project Authors, SIL Open Font License 1.1
  (`assets/fonts/montserrat-OFL.txt`).
- Permanent Marker by Font Diner, Apache License 2.0
  (`assets/fonts/permanentmarker-LICENSE.txt`).
- Kenney Future, Kenney Future Narrow, Kenney Mini and Kenney Bold by
  [Kenney](https://kenney.nl), CC0, in the shared add-on's
  `addons/linuxgroove/ui/fonts/`.

## Audio

- The menu sounds in `addons/linuxgroove/ui/sounds/` are from
  [Kenney](https://kenney.nl)'s Interface Sounds, CC0.

## Code

- [Godot Engine](https://godotengine.org), MIT.
- [Nakama Godot client](https://github.com/heroiclabs/nakama-godot),
  Apache-2.0, vendored in `addons/com.heroiclabs.nakama` (see `VENDORED.md`).
- The shared LinuxGroove add-on in `addons/linuxgroove`, MIT.
- The Cartographer reads OpenStreetMap extracts with
  [pyosmium](https://osmcode.org/pyosmium/) (BSD-2-Clause) and works on
  them with [Shapely](https://shapely.readthedocs.io/) (BSD-3-Clause),
  [NumPy](https://numpy.org/) (BSD-3-Clause) and
  [Pillow](https://python-pillow.org/) (MIT-CMU). None of them ship with
  the game.
