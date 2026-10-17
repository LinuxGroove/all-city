# Town folders and tiles

The Cartographer (`python3 -m cartographer build <town>`, see `cartographer/cli.py`) turns an OpenStreetMap extract into a **town folder**, once per town. The game reads it and never touches the map itself. Towns that come with the game are in `res://towns/<id>/`; towns built or downloaded since are in `user://towns/<id>/` (`Towns.list()` finds both).

```
<id>/
  town.json          the manifest
  tiles/<i>_<j>.tile one 256 m square each
```

This is format **1** (`cartographer/__init__.py` `FORMAT`, `TownTiles.FORMAT`). Bump it whenever an older game couldn't read what's written; the game skips towns whose format is newer than its own.

## Coordinates

Metres from the town's middle (`origin` in the manifest): **x runs east, z runs south, y is height above sea level**, as in Godot. The town is a square box round the middle (`box`: x0, z0, x1, z1), cut into 256 m tiles: tile `(i, j)` covers x from `i * 256` to `(i + 1) * 256` and z from `j * 256` to `(j + 1) * 256`.

The game works near its own origin rather than the town's: `TownView` keeps where the scene's origin is in the town (`origin`) and moves the world back when the player gets far from it.

## town.json

| Key | What |
|---|---|
| `format`, `cartographer` | The tile format and the Cartographer's version |
| `id`, `name`, `country` | The town's id (its folder), its name and its two-letter country code |
| `drive` | `"left"` or `"right"`: the side traffic keeps to |
| `utc_offset_min` | The town's standard time offset, for dawn (the Buff) |
| `origin` | `{lat, lon}` of the middle |
| `box` | `[x0, z0, x1, z1]` in metres |
| `tile_size`, `tiles` | 256, and every tile written as `[i, j]` |
| `quarters` | `[{id, name, centre: [x, z]}]`: the parts of town walls belong to (ids 0 to 9999, the server's rooms for walls) |
| `spawn` | `{p: [x, y, z], yaw}`: where a writer starts, at the foot of the town's best staircase near the middle, looking up it (`Basis(Vector3.UP, yaw)` faces up it) |
| `data_date`, `built` | The map data's date (the newest edit read) and the day the town was built |
| `attribution` | Lines the game must show with the town (OpenStreetMap's credit and the elevation's) |
| `stats` | Counts, the bytes of tiles and how long each stage of the build took |

## A tile

Each `.tile` is a gzipped Godot binary Variant (`var_to_bytes`): one Dictionary, read with `bytes_to_var` after a gzip decompress (`TownTiles.load_tile`), so loading does no parsing. `cartographer/godot_variant.py` writes it. Arrays of numbers are packed arrays; points are `Vector3` (x, y, z) or `Vector2` (x, z) in town metres.

| Key | Type | What |
|---|---|---|
| `format`, `i`, `j`, `x0`, `z0`, `size` | int, float | The format, the tile's grid key, its north-west corner and side (256) |
| `heights` | PackedFloat32Array | 65 x 65 heights every 4 m from the corner, rows running south (`heights[row * 65 + col]`). Edges are shared with the next tile |
| `ground` | PackedByteArray | A 512 x 512 RGBA PNG of what covers the ground (row 0 is the north edge): R roads, G footways and paved areas, B parks and grass, A railway ballast |
| `quarters` | PackedInt32Array | 8 x 8 quarter ids, one per 32 m cell, rows running south |
| `buildings` | Array | See below |
| `lines` | Array | `{kind, pts}` plus `height` for fences and walls: `kerb` (the top of a kerb, 0.14 m up), `fence` and `wall` (their top), `rail` (a railway rail's top, two per track), `track` (a track's middle on the ground), `wire` (a power line, sagging between poles), `parapet` (the top of a bridge's edge). `pts` is a PackedVector3Array |
| `flights` | Array | Flights of steps: `{bottom, up, steps, rise, going, width, walls}`. `bottom` is the middle of the lowest nosing (Vector3), `up` the level direction up the flight (Vector2), `rise` and `going` one step's height and depth, `walls` whether it has side walls (with copings to grind) |
| `bridges` | Array | `{pts, width, rail, motor}`: a deck's middle line on top (PackedVector3Array) |
| `props` | Array | `{m, p, yaw}`: a kit model (`street/street_lamp`) at a point; `Basis(Vector3.UP, yaw)` turns it, and its +z faces the street |
| `lanes` | Array | Traffic lanes, one per direction on the town's side of the road: `{pts, kind, bridge}` in the direction of travel, 2 cm above the ground |
| `water` | Dictionary | `{verts, tris}`: the sea and lakes cut to the tile, triangles wound anticlockwise seen from above |

Lines, lanes and water are cut where they cross into the next tile (the pieces share the point where they meet); a building, flight, bridge or prop goes in the tile its middle is in.

### Buildings

| Key | What |
|---|---|
| `id` | `b` and hex digits, from the building's place and size |
| `rings` | Its outline: the outer ring first, then courtyards, each a PackedVector2Array without the closing point |
| `tris` | The roof: indices into the rings' points taken in order, three a triangle, wound anticlockwise seen from above |
| `y0`, `top`, `storeys` | The lowest ground along the outline, the roof's height (where the top storey ends) and the storeys from `y0` |
| `style` | The facade kit's style: `brick`, `plaster`, `modern` or `works` |
| `seed`, `kind`, `paint` | Its seed (colours), its map kind (`yes`, `apartments`, `school`, ...) and the respect list's verdict (0 never, 1 the ground floor only, 2 all of it) |
| `props` | Things on its roof: `{m, p, yaw}` |
| `faces` | Its walls that show, see below |

A building's **faces** are the parts of its outline that face out, cut at most 12 m long, each a paintable wall:

| Key | What |
|---|---|
| `id` | The wall's id, `w` and 12 hex digits from its ends' places: the server's key for the paint on it |
| `p0`, `p1` | Its ends on the ground at its base (Vector3), with its outside on the right walking from `p0` to `p1` seen from above |
| `storeys` | Storeys from the base to the roof; the base is `top - storeys * 3` |
| `ground` | Its ground floor: `shop`, `home`, `blank`, or `upper` (it starts above a lower neighbour, so windows all the way down) |
| `pipe`, `escape` | The bay with a drainpipe, and the bay with a fire escape, or -1: the ways up to the roof (every roof has one) |
| `ends` | `[start, end]`: 1 where the face ends at an outside corner (a pier there) |
| `paint`, `paint_top` | The respect list's verdict and the highest paintable point |
| `eyes` | 0 to 100: how much of the street sees it, which is what a tag there is worth |
| `quarter`, `seed` | The quarter it's in and its own seed |

The game lays the facade kit along each face (`Facade.lay`) and builds a plain shell set inside the outline for everything else and for far away. The roof is level with the cornice's top where the style has a parapet on it (`TilePlan.deck`), so a parapet is a hop high.

## Streaming

`TownView` keeps the tiles within one tile of the player's in full detail (facades, steps, props, collision, grind lines, walls and traffic) and up to three tiles out as scenery (ground, water, shells and roofs). A worker thread reads each tile and works it out as plain arrays (`TilePlan`); the main thread then makes nodes from the plan a few milliseconds a frame (`TileView`), so nothing stalls. Detail is dropped a tile later than it comes, so riding along a tile's edge doesn't build it over and over.
