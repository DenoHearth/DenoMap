# Changelog

## v1.7.0 — 2026-10-12

Every open point of 1.6.0, each one measured in the game against the game's own minimap.

- **Minimap water has the game's depth, colour by colour.** 1.5 and 1.6 used one water colour and one depth for red, green and blue, so shallow seas and ponds came out too blue (Westfall, Wetlands, the Gadgetzan pond). The game's water takes red first, then green, blue last: shallow water is green, only deep water is blue, and lakes are about twice as clear as the sea. That rule is now painted into the tiles (fitted over 44,000 water pixels at seven places, to within 1.5 of 255). Menethil Harbor: game 22 35 31, Deno Map 22 34 30. Stormwind harbour: 29 42 49 against 32 41 49
- **The minimap tint is measured per zone.** The 1.6 rule was right to a few percent in most zones and far off in some: Dun Morogh 19 percent too bright in red, Tanaris 16 percent too blue, and the zones it was never fitted on worse still (17 percent in blue on average). Nothing in the game's light tables explains those differences, so the game's tint was measured at 183 places at midday, one for nearly every zone light, and each light now carries its own correction. At 16 places that were not used for it: within about 2 percent in red and green
- **Zone outlines.** Fifteen zones (Burning Steppes, Mulgore, Elwynn, Ashenvale, Blasted Lands and more) are lit by an outline on the map instead of a round light. Those are followed now too
- **Stormwind and Orgrimmar.** There the game shows its picture of the city, which is not lit by the zone: the same by day and at midnight. Deno Map now draws those two cities with that tint instead of the zone's (it was 8 percent off in red and 12 in blue)
- **Night:** 2.5 percent less red and 2 percent less green, as measured at nine places at midnight
- **Truer colours in every repainted tile.** The picture library used to read a tile decoded it darker than the game does (red up to 5 of 255), and the texture compressor rounded dark sea down by another 3 to 7. Tiles are now read exactly and compressed with the loss put back
- **Alterac Valley's pond** is painted (Warsong Gulch has no water inside)
- **Deeper zoom checked for taint:** real mouse wheel and drag on the world map with encounter, combat and map restrictions forced: no error, no blocked action
- **Game build 1.60.1.70338:** all 3,592 source textures compared, none changed
- 1,324 of the 1,888 minimap tiles were repainted in all three sizes

Known and left as it is: rain darkens the game's own minimap (heavy rain by about a fifth). An addon cannot read the weather, so Deno Map shows clear weather. The game's water also shifts a little with the hour; the tiles match midday.

## v1.6.0 — 2026-10-11

- The 4K minimap now has the game's colour, not only its brightness. The game lights its minimap with the zone's light: warm in Elwynn, cold in Winterspring, blue at night. Deno Map tinted plain grey. It now follows the zone's light through the day (direct and ambient light colour from the game's own light tables, rule fitted to the game's minimap at twelve places by day and four at night). Against the game, per colour channel: within about 5 percent by day, within about 6 at night; before, red was up to 10 percent too dark and blue up to 12 percent off
- `tools/lights.py` writes the light table (`Lights.lua`, 50 KB)

## v1.5.0 — 2026-10-11

- Minimap water is now the game's own, in 4K. 1.4 laid one flat colour over the tiles from a separate low-resolution layer; it looked plain next to the game. Now the water is painted into the 4K tiles themselves, by the rule the game uses, measured against the game's minimap at 13 places: the water colour covers the sea bed more the deeper it is (17 percent at 1.5 yards, half at 5.5, nearly all past 20), so shallows, sand and the shapes of the shore stay as the art has them; piers, quays, bridges and ships keep the art. Stranglethorn has its own water colour, as in the game
- The game paints water only in the map square you stand in, and not at all far out at sea or off some coasts (black in the stock game). Deno Map applies the same rule to all clear water, so there is no black; the straight edge between two squares is gone (Booty Bay)
- Swamps, lava and the battlegrounds of Warsong Gulch and Alterac Valley are left as they are
- The separate water layer of 1.4 (760 files, 256 MB) is gone again; 1,335 of the 1,888 minimap tiles were repainted in all three sizes
- `tools/water.py bake` does it, from the untouched upscaled tiles; `tools/seams.py` checks the borders between tiles

## v1.4.1 — 2026-10-11

- Minimap water: no more straight edge in the water where two map squares meet (Booty Bay and other shores). Green and teal seabed now counts as water at any brightness, so shallows are painted alike on both sides; piers, docks and ships still keep their own look. `tools/seams.py` finds such edges: 17 before, 12 after, the rest are edges in the game's own art.

## v1.4.0 — 2026-10-11

- Minimap: sea, lakes and rivers are blue again instead of nearly black (the game paints water only in the map square you stand in; Deno Map now paints all of it). The 4K minimap follows a square minimap (Deno Square Minimap or any addon that reports its shape).

## v1.3.0 — 2026-10-10

First version measured in the game against the game's own picture, pixel for pixel. Before this the minimap looked softer and brighter than the original at normal zoom.

- Texture is back: the upscaler had wiped out the fine grain of the game art (a tile kept 21 to 27 percent of the original's fine detail). Every one of the 3,592 textures was redone with the game's own grain laid back over the sharper upscale
- Sharp at every size: each texture now comes in three sizes (4x, 2x, 1x) and the addon shows the one that fits how large the map is drawn. Zoomed in, the minimap carries about 150 percent of the game's fine detail and the maximized world map about 250 percent; at normal sizes it is never below the original
- Same brightness as the game: the game draws its minimap darker than the tile files, and darker at night than by day. The 4K minimap now follows that through the day (measured at 19 hours of the game clock)
- `/denomap maps` switches the 4K maps off and on, to compare with the game's own art (as `/denomap minimap` does for the minimap)
- The "tiles in 4K" count shown by `/denomap` was wrong after the first redraw of a map; fixed
- The minimap frame has a new name, so minimap button collectors no longer mistake it for a button
- `tools/ladder.py` cuts the 2x and 1x files out of the 4x ones; `tools/tonecurve.py`, `tools/sweepshot.py`, `tools/compare.py` are the measuring tools

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
