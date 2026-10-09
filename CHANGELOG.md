# Changelog

## v1.2.1 — 2026-10-09

- Remade for game build 1.60.1.70291: the patch redrew part of the minimap; 485 minimap tiles and 4 world map textures are new
- `tools/rebuild_check.py` and `tools/keep_same.py`: after a game patch, find the textures whose source changed and redo only those

## v1.2.0 — 2026-10-09

- The minimap in full 4K: tiles are now four times the game's resolution (2048 pixels a tile), not two
- Minimap also in Alterac Valley, Warsong Gulch, Arathi Basin and on Darkspear Islands; it now turns with the rotating minimap instead of standing by
- Zone highlights (the glow over a zone on a continent map) and the flight master's maps in 4K
- `/denomap selftest`: writes what the addon measured to its saved variables and takes two screenshots
- The whole addon, textures included, is now in the repository as one bundle; the addon sits in its own `DenoMap` folder

## v1.1.0 — 2026-10-09

- Zoom further into the world map: four more steps, up to five times its size; the mouse wheel zooms towards the pointer and holding the left button drags the map while zoomed in
- Sharper minimap outdoors in Eastern Kingdoms, Kalimdor and Zephras Isle: the terrain is drawn from tiles upscaled to twice the resolution (1,796 tiles); `/denomap minimap` switches it off

## v1.0.0 — 2026-10-09

- First release: all 57 world maps of WoW: Forever in four times the resolution, with their discovered areas. Upscaled from Forever's own map art.
