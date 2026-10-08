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
