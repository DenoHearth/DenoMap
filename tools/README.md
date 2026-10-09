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

## Minimap tiles

1. `python mjobs.py --fetch` - reads each open-world map's WDT for its minimap tile file ids
   (map id -> WDT file id is in `MAPS` at the top, from the game's Map table) and downloads them
2. `python mprocess.py` - upscales every tile to twice its size (4x model, halved), writes
   `../Minimap/<world map id>/<column>_<row>.blp`; empty ocean tiles are written small
3. The tile list `../MinimapManifest.lua` is written from `mjobs.json` (see the last lines of
   the addon's build notes in the repository history).

