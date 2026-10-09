# Deno Map 4K

The world map of every Forever zone in four times the resolution, discovered areas included. Upscaled from Forever's own map art.

[![Latest release](https://img.shields.io/github/v/release/DenoHearth/DenoMap?label=download&style=for-the-badge)](https://github.com/DenoHearth/DenoMap/releases/latest)

A World of Warcraft: Forever addon (interface 16001).

## What it does

The world map of World of Warcraft: Forever in four times the resolution: 4008 x 2672
instead of 1002 x 668. Every zone, city, continent and battleground map the game has,
57 maps in all, with the discovered areas that are drawn over them. Plus deeper zoom and a sharper minimap.

- **Forever's own maps.** Forever redrew every zone map and added new zones (Mount Hyjal,
  Zephras Isle, Riverglades, Shen'dralas, Darkspear Islands). The textures here are upscaled
  from that art, so nothing shows an older version of a zone.
- **Discovered areas too.** The coloured pieces that appear as you explore are upscaled
  with the same model and line up with the map underneath.
- **Nothing replaced.** The game's map frames are only hooked. A map or texture the pack
  does not know keeps Blizzard's art, so a map can never go blank.
- **Zoom further.** The mouse wheel zooms the map up to five times its size (the game
  stops at about two), and holding the left button drags it around while zoomed in.
- **Sharper minimap.** Outdoors in Eastern Kingdoms, Kalimdor and Zephras Isle the minimap
  terrain is drawn from tiles upscaled to twice the resolution, which shows when the minimap
  is zoomed in. Dots, arrows and tracking are still the game's own. Indoors, in instances
  and with the rotating minimap switched on, the game's own minimap is shown unchanged.
- **Standalone.** No libraries, no dependencies.

## Install

- **By hand:** download the zip from the
  [latest release](https://github.com/DenoHearth/DenoMap/releases/latest) and extract
  the `DenoMap` folder into `World of Warcraft\<Forever folder>\Interface\AddOns\`.
  Restart the game. The download is large: it holds about 3,450 textures.
- This repository holds the code and the build scripts only. The textures are in the
  release zip, not in git.

## Commands

- `/denomap` - how many textures of the map you last opened are shown in 4K, and what the
  minimap is doing
- `/denomap minimap` - switch the sharper minimap on or off

## How it works

The game sets every map tile and every discovered-area piece by file id. `Maps\` holds a
4x upscale of each of those files under the same id. After the game has drawn a map,
`Core.lua` points each texture that has an upscale at it.

## How the textures are made

`tools/` holds the scripts. `jobs.py` reads the game's map tables for the build and
downloads the source textures; `process.py` stitches each map and each discovered area
into one picture, upscales it 4x on the GPU with the RealESRGAN x4plus model, cuts it back
into tiles and writes them as DXT-compressed BLP files; `manifest.py` writes the list
of file ids. After a game patch that changes a map, run the three again.

## Files

- `Core.lua` - the hooks and the texture swap
- `Manifest.lua` - generated: the file ids that have an upscale
- `Maps\` - the textures (release zip only)
- `Zoom.lua` - the extra zoom steps
- `Minimap.lua` - the sharper minimap; `MinimapManifest.lua` - generated: its tiles
- `Minimap\` - the minimap tiles (release zip only)

## Limits and credits

- An upscale sharpens lines and lettering; it does not add detail the artists did not paint.
- The map art belongs to Blizzard Entertainment. The MIT licence covers the code in this
  repository, not the art.


## Compatibility

- World of Warcraft: Forever, interface version **16001**.
- Forever only. It uses that client's API and will not load on retail or the Classic clients.

## Changelog

What changed in each version: [CHANGELOG.md](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE).  Current version: 1.0.0.
