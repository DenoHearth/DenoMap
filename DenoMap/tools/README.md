# Building the textures

Needs Python 3.12, an NVIDIA GPU and: `pip install torch spandrel pillow numpy etcpak`
(torch from the CUDA index). Put `RealESRGAN_x4plus.pth` in `models/`.

Run in this folder, in this order:

1. `python jobs.py --fetch` - reads the game's map tables for the build named at the top of
   the file and downloads the source textures into `raw/`
2. `python process.py` - upscales every map and discovered area 4x, writes `../Maps/<file id>.blp`
3. `python verify.py` - checks every written file is complete
4. `python manifest.py` - writes `../Manifest.lua`

After a game patch: change `BUILD` in `jobs.py`, delete `db2/` and `jobs.json`, run again.
`process.py` skips what is already there; delete `../Maps` to redo everything.

## Flight maps and zone highlights

After the steps above: `python extras.py` (the three flight maps and the zone highlights of the
continent maps, 48 files, into `../Maps`), then `python manifest.py` again.

## Minimap tiles

1. `python mjobs.py --fetch` - reads each world map's WDT for its minimap tile file ids
   (map id -> WDT file id is in `MAPS` at the top, from the game's Map table) and downloads them
2. `python mprocess.py` - upscales every tile 4x (512 -> 2048), writes
   `../Minimap/<world map id>/<column>_<row>.blp`; empty ocean tiles are written small
3. `python mtiles.py` - writes each world's `Tiles.lua` beside its tiles. A new world also needs
   its `Minimap\<id>\Tiles.lua` line in `DenoMap.toc`.

## Minimap tint (measured)

The game lights its minimap per zone, and nothing in its light tables predicts by how much.
`tintspots.json` holds what was measured in game: 183 places, each with the tint the game uses
there at midday. `tinttable.py` turns them into one correction per zone light (run it to see how
many lights are covered); `lights.py` writes them into `../Lights.lua` with the light tables.

Measuring a place: on a test server stand there in clear weather (rain darkens the game's own
minimap), capture the minimap with the addon's terrain on and off (`sweepshot.py "sweep 0"`),
take the slope ours against game over the land pixels per colour channel, and divide the tint
the addon used there by it. Add the place to `tintspots.json`, run `lights.py`.

After changing the tint, run `water.py bake` again: the water colour is divided by the tint a
tile gets, so it comes out as measured.

## Reading and writing tiles

`up.py`: `read_blp` reads a DXT1 tile exactly as the graphics card does (Pillow reads these files
up to 7 of 255 too dark), and `write_blp` compresses with the loss put back
(`compress_bc1_true`). Use these for anything that reads a tile, changes it and writes it again.

