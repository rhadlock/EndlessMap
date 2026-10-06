# Azeroth Unrolled

Version 1.2.0 - for **WoW Forever** (client 1.60.1, interface 16001). It also loads on **Classic Era**
(1.15.8 / 1.15.9, interfaces 11508 / 11509); everything marked *Forever* below is switched off there.

One continuous zoom over the whole world map: scroll from Azeroth straight down to a
dungeon entrance, drag across zone borders, and see the important places along the way. Questie-friendly.

## What it does

**World map**
- One smooth zoom from the world view down to about 4x past a zone's own map. Dragging pans across zone
  and continent borders; a flick glides on. Clicking a zone flies there.
- Zone art fills in seamlessly while you move (zone cells and land shapes, explored areas as the game
  draws them). Below one zoom level the map is Blizzard's own drawing of every zone, city banners
  included; above it (world zoom 14.05x, `/unroll cityzoom`) every capital shows its own map, on top of
  everything, wherever you look. Deep zoom stays inside maps that have the detail for it.
- Map icons (quests, Questie, flight masters...) move with the map. At rest everything the addon draws
  sits *inside* Blizzard's map canvas, below every pin, so every icon stays clickable.
- Click your arrow (or a party member's dot) and the map follows them; M opens the map on your character at
  world zoom 14, and follows you.
- Every cave and mine of the old world (about 290) shows its tunnels from world zoom 30 - or as deep as the map goes
  over it, where that is less; Gnomeregan's tunnels, Maraudon, the Scarlet Monastery and the Timbermaw Hold tunnels
  with the city maps.
- Place names: continents, zones, cities, dungeons (level range), raids, flight masters - each in its
  own zoom range, never overlapping.
- *Forever:* Blackrock Mountain is drawn as a detail level of Burning Steppes, with an icon for each
  instance inside. Dalaran - the open-world city in Alterac Mountains - is drawn from the client's own
  minimap art.

**Dungeon and raid maps** (*Forever*)
- Click a dungeon or raid icon on the world map to open its map (Blizzard's map art that ships in the
  client, drawn by file ID - Forever has no dungeon maps of its own). Several dungeons behind one door
  (Blackrock Mountain, Scarlet Monastery, Maraudon) open their entrance map, with a portal icon per
  dungeon. Inside an instance the map opens on that instance by itself.
- A bar with World Map / back / level buttons, the name and a floor dropdown. The wheel zooms (1x-3x),
  dragging pans, right-click goes back one step.
- **Bosses**: every boss with a known position has a marker on its floor - Blizzard's raid-target skull
  in a gold ring, numbered in the game's own encounter order (per wing), optional bosses unnumbered,
  approximate ones faded with "Approximate location" in the tooltip. A boss killed while you are inside
  (the game's BOSS_KILL / ENCOUNTER_END events), or listed as killed by the instance lock the game reports
  when you enter an instance with progress, turns grey with a green check. Kills are remembered until
  the next loading screen: after a wipe and a run back the skulls show alive again (the addon cannot
  tell a reset instance from the same one). The skull button on the bar lists
  every boss of the dungeon (including the ones without a position) and turns the markers on / off.
  Click a marker to zoom in on it.
- **Entrance**: the swirl marker shows where you arrive (Blizzard's minimap dungeon / raid swirl).
  Clicking it goes to the entrance map where there is one.
- The Deeprun Tram (3 stations), the Forever instances (Ruins of Lordaeron, Excavation Site: Wetlands,
  City of Dalaran, Half-Pint Tavern, The Hall of Thanes) with maps built from their minimap art.
- Inside an instance: the room the game names (its sub-zone text) is lit and labelled, and the bar
  names it.

**Doors on the world map** (*Forever*, new in 3.0.0)
- Door icons for Forever's own instances: The Hall of Thanes (Ironforge), Ruins of Lordaeron (Tirisfal),
  Excavation Site: Wetlands (Wetlands). City of Dalaran's dungeon door (the portal at the end of the
  sewer pipe) has an icon too; its tooltip says the door is not confirmed yet.
- **Placeholders** for the instances Forever lists that are not in the game files yet: The Drowned City,
  Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold, Shaper's Terrace, Manor Mistmantle, and the raids
  Hyjal Summit and Barrow Deeps. They are hollow grey icons with grey names, never a click target, and
  never push another label off the map. The tooltip gives the level range, dungeon or raid, "Not in
  the game files yet" and "Location approximate".
- **Learned doors**: when you walk into a dungeon or raid, the addon notes where you were just before
  the loading screen (and where you come out). A door is confirmed by two samples within 25 yd, or by
  one within 150 yd of a known candidate spot. A learned door turns a placeholder or an unconfirmed
  icon into a normal one, or adds an icon for an instance that has none (e.g. Half-Pint Tavern). It
  never moves a door that is already certain. Summons, logins / reloads, dying or being a ghost, the
  dungeon finder's teleports and stale positions are ignored. Learned doors are saved for your whole
  account.
- **"You are inside"**: while you are in an instance, the world map marks that instance's *door* with
  your round player icon, pulsing, at every zoom; its tooltip starts with "You are inside <name>", and
  clicking it opens the map of the instance you are in (also behind a shared door such as Blackrock
  Mountain), on the floor the game names.

## Settings

A small round button in the map's lower right corner (the treasure-map icon) opens the settings: tick what you want
to see, pick the zoom behaviour under "Zoom". Left of it, the caves button (a mining pick) hides and shows the caves
with one click. The same settings are on the game's own page Esc > Options > AddOns > Azeroth Unrolled (plus "Buttons
on the map", to bring hidden buttons back), and every one of them has a slash command.

| Menu item | What it does |
|---|---|
| Smooth zoom | the continuous zoom on / off (off: Blizzard's map as usual) |
| Place names | names of continents, zones, cities, flight masters |
| Dungeon and raid icons | the door icons on the world map (click one for its map) |
| Unreleased-dungeon placeholders | *Forever:* grey icons where the instances not in the game yet are expected (on by default) |
| Dungeon maps | *Forever:* dungeon and raid maps (they open by themselves inside) |
| Boss and entrance markers | *Forever:* on the dungeon maps |
| Map icons move with the map | quest and other icons follow the map while it moves |
| Follow on click | a click on your arrow or a party member's dot: the map follows them |
| M follows me | M opens the map on your character and follows you |
| Zoom readout | the zoom numbers in the map's top left corner |
| Zoom > Wheel step | zoom per wheel notch: 1.15x, 1.3x (default), 1.5x, 2x |
| Zoom > Zoom depth | how far past a zone's own map: 2x, 4x (default), 6x, 10x |
| Zoom > Flight speed | 0.5x, 1x (default), 2x, 4x |
| Zoom > City maps appear | from world zoom 10x, 14.05x (default) or 20x, or by each city's own zone |
| Zoom > Caves appear | from world zoom 20x, 30x (default) or 40x - where the map stops short of that, at its deepest zoom over the cave -, or never |
| Zoom > M opens the map on me | at world zoom 10x, 14x (default) or 20x on your character, or off (the game's view) |
| Slash commands | prints every command to the chat |
| Reset to defaults | every setting back to its default (learned doors are kept) |
| Hide these buttons | both buttons; `/unroll button` or the Settings page brings them back |

Any other allowed value can still be typed as a command (`/unroll step 1.4`, `/unroll cityzoom 16`); the menu then
shows it as "Custom".

## Slash commands

`/unroll` (or `/azerothunrolled`) shows the settings and this list.

| Command | What it does |
|---|---|
| `/unroll on`, `/unroll off` | the smooth zoom on / off (Blizzard's map as usual when off) |
| `/unroll depth <1-10>` | how far past a zone's own map you can zoom (default 4) |
| `/unroll step <1.05-2>` | zoom per wheel notch (default 1.3) |
| `/unroll speed <0.25-4>` | speed of click flights (default 1) |
| `/unroll labels` / `rest` / `flight` | place names on / off; names while the map is still; flight masters |
| `/unroll names` | place names on / off |
| `/unroll icons` | dungeon and raid icons on the world map on / off |
| `/unroll button` | the buttons on the map (settings, caves) on / off |
| `/unroll mosaic` | unexplored zone land in map style (mosaic) on / off |
| `/unroll cells` | seamless zone cells (off: land shapes only) |
| `/unroll livepins` | map icons move with the map (off: hidden while it moves) |
| `/unroll dungeons` | dungeon maps on / off (click a dungeon icon; they open inside dungeons) |
| `/unroll markers` | the group on entrance maps: the game's own widget / the addon's dots |
| `/unroll bosses` | boss and entrance markers on dungeon maps on / off |
| `/unroll doors` | list the doors: built in, placeholders, learned (with their samples) and the recorder's last decisions |
| `/unroll doors hints [on\|off]` | the placeholders on / off (default on) |
| `/unroll doors forget [id]` | clear the learned doors (all, or one instance ID) |
| `/unroll zoom` | a zoom readout on the map: the world zoom (1.00x = the whole world map) and each city in view |
| `/unroll cityzoom <N>`, `default`, `off` | the world zoom from which every city map (and Blackrock Mountain, Dalaran) shows, wherever the view is: default 14.05; off = the rule up to 3.0.1 (1.5x of each city's own zone) |
| `/unroll follow` | a click on your arrow / a party member's dot makes the map follow them: on / off (default on) |
| `/unroll openzoom <N>`, `default`, `off` | the world zoom M opens the map at, on your character: default 14; off = the game's own view |
| `/unroll openfollow` | M also follows you: on / off (default on) |
| `/unroll cavezoom <N>`, `default`, `off` | the world zoom from which caves show their tunnels: 10 to 60, default 30 (where the map stops short of it, at its deepest zoom over the cave); off = never |
| `/unroll taint` | checks that the objective tracker's quest data is clean (for bug reports) |
| `/unroll debug` | how the map layers are stacked (for bug reports) |
| `/unroll reset` | settings back to their defaults (learned doors are kept) |

## Inside instances: what is possible and what is not

**Your position inside an instance cannot be shown.** Since patch 7.1 Blizzard blocks every position
API for addons inside instances, and WoW Forever does the same - confirmed in game (The Hall of Thanes):
`UnitPosition("player")` returns nothing but the instance ID, `C_Map.GetBestMapForUnit` and
`C_Minimap.GetUiMapID` return nothing, `GetPlayerFacing` returns nothing. Blizzard's own map can only
draw you where the game data has a dungeon map with a map assignment, and Forever ships none (its UiMap
table has no dungeon maps). No addon can work around this, and estimating the position from other
signals is exactly what the block is there to prevent - so this addon does not try.

What the addon shows instead, and what each thing means:
- **The instance's map** with its bosses and entrance - where things are, not where you are.
- **The lit room**: the room the game names in its sub-zone text. Some instances name no rooms (The
  Hall of Thanes names only a few), then nothing is lit.
- **"You are inside"** on the world map marks the instance's *door*, not your position.
- **Defeated bosses** come from the game's own boss-kill events while you are inside, and from the
  instance lock the game reports when you enter an instance with progress.

## Data and where it comes from

Everything the addon draws comes from data files inside the addon (no network access, ever):
- `Data.lua` - world entrances of the classic dungeons and raids (instance map, world position, levels).
- `DungeonMaps.lua` - Blizzard's dungeon map art in this client (file IDs, floor rectangles, floor
  names), `DungeonMapsMM.lua` - the Forever instance pages built from their minimap art, the Forever
  door rows (`ns.FOREVER_DOORS`) and the placeholder / hint rows (`ns.FOREVER_DOOR_HINTS`).
- `DungeonBossData.lua` - boss and entrance markers (generated; do not edit by hand).
- `DungeonPortals.lua`, `DungeonLinks.lua`, `DetailMaps.lua`, `SubZoneRegions.lua`, `OverlayData.lua`,
  `ZoneMasks.lua` + `Masks\` - portals of the entrance maps, level links, detail levels, room shapes,
  explored-area data, zone masks.

Sources, with thanks:
- **The WoW Forever client itself** (read-only): its DB2 tables (Map, UiMap, UiMapAssignment,
  UiMapArtTile, DungeonEncounter, AreaTable, AreaTrigger, JournalInstance...), the placed models and
  WMO groups of its world, its minimap tiles and its UI art. Boss names, encounter IDs and the kill
  order come from Forever's own DungeonEncounter table.
- **Boss positions**: vanilla spawn data from the MaNGOS Zero, CMaNGOS classic-db, VMaNGOS and
  AzerothCore projects, cross-checked with Blizzard's Encounter Journal tables of later clients (via
  wago.tools) and the skulls printed in the map art; Questie's NPC data; Wowhead.
- **Forever instances**: the ForeverChanges and Icy Veins guides (bosses and rooms), wowhandbook.com
  and foreverchanges.pro (door positions, used only to cross-check the client data), mobalytics'
  Forever dungeon list (level ranges), warcraft.wiki.gg (API behaviour).
- **ForeverChanges** (foreverchanges.pro): ten positions on the Forever dungeon maps - nine bosses and one
  entrance in The Hall of Thanes and Ruins of Lordaeron - follow the pins on its hand-drawn guide maps
  (cross-checked with the Icy Veins guide maps). Only the positions were taken; credit and thanks to
  ForeverChanges. Details in `NOTICE.md`.
- Blizzard's own map code (the Mainline world map of the Forever client) for how the canvas, pins and
  map changes work.

## After a client patch: checking and refreshing the data

The data is tied to client build 1.60.1.70124. After a patch:
1. **Check that it loads**: open the map, `/unroll debug`. A Lua error names the file.
2. **New instances** (a placeholder whose map is now in the game): their `Map.db2` rows were encrypted
   in 70124. When a patch unlocks them, the instance can get a map page (built from its minimap art
   like the other Forever instances in `DungeonMapsMM.lua`), boss rows (`DungeonBossData.lua`) and a
   door row in `ns.FOREVER_DOORS`; its placeholder then disappears by itself (a hint whose instance has
   a door row is no placeholder). Until then, walking in once near the placeholder is enough for the
   addon to learn the door.
3. **A door moved**: the door rows are data only - one row, one icon (`c` continent, `x`/`y` world
   position as `UnitPosition` gives it, `zone` uiMap, `d` instance ID, `floor`, `note`, `conf`). Stand at
   the door and read the position with
   `/run print(UnitPosition("player"))`. `/unroll doors` also lists how far each learned door is from its
   built-in row.
4. **Bosses**: `DungeonBossData.lua` is generated from the client's DungeonEncounter table (encounter
   IDs and order) and the position research. Rebuild it when bosses are added or renamed (the table's
   header describes every field); a boss without a reliable position simply has no `f`/`u`/`v` and
   appears only in the boss list.
5. **Dungeon art**: the map art is drawn by file ID; if Blizzard replaces a file, the page shows
   nothing for that tile (no error) - re-read the UiMapArtTile rows for the new IDs.

The generator tools used for 3.0.0 (DB2 readers, the boss / door table builders, the test harness that
runs the real addon files against Blizzard's map code) were kept outside the addon folder.

## Tests before this release

This release was built and checked in the offline harness of the earlier versions, which runs the addon's real
files against Blizzard's own map canvas code (Lua 5.1 limits enforced; the 93 test suites of 3.6.2, plus suites
for the settings and caves buttons, the menu and the Settings page; image dumps).
Things only the game can confirm
(please report): the boss-marker art and the kill events in Forever, the placeholder spots, the City of
Dalaran door (stand at the portal at the end of the sewer pipe: `/run print(UnitPosition("player"))`
should print about 377, 525), and that the door recorder learns a door when you walk in and out.

## License / author

Copyright (C) 2026 Hadlock.
Azeroth Unrolled is free software under the GNU General Public License, version 3 or (at your option) any later version
(SPDX: `GPL-3.0-or-later`); it comes WITHOUT ANY WARRANTY. The full text is in `LICENSE`; data sources and
third-party notices are in `NOTICE.md`.

By Hadlock. Blizzard's art and data belong to Blizzard Entertainment; the addon only points the game
at files already in your client.
