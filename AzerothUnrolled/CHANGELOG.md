# Changelog

## Azeroth Unrolled 1.2.0 (2026-10-06) - caves, the Gnomeregan tunnels, M follows you

- **Caves on the world map.** Zoom in past world zoom 30 and the caves of the old world show their tunnels right on
  the map - about 290: Blizzard's own cave maps where WoW Forever's cave is the one drawn (Fargodeep and Jasperlode
  Mine, the Venture Co. Mine, Skull Rock, the entrance caves of the Deadmines, Wailing Caverns and Uldaman, and more),
  cut to the cave's shape, and every other cave - wolf dens, mines, ogre mounds, hives, barrow dens, crypts, tunnels,
  Mazthoril, the Caverns of Time, WoW Forever's own caves - drawn from the game's own minimap of it, like Gnomeregan;
  each with its name where the game names it. Where the map can't zoom in that far (over some caves in Winterspring,
  Feralas, Tanaris, Stranglethorn Vale and Mulgore it stops between 25x and 30x), a cave shows at the deepest zoom over
  it. Caves with two levels show the lower one under the upper. The entrance caves carry their dungeon's icon at the
  portal; a click on their tunnels opens the dungeon's map. `/unroll cavezoom <N>` (10 to 60) sets the zoom,
  `/unroll cavezoom off` hides them.
- **The caves button**: left of the settings button, a mining pick - one click hides the caves, another shows them
  again (greyed while they are off).
- **With the city maps**, from world zoom 14 like Blackrock Mountain: the tunnels of Gnomeregan - drawn from the game's
  own minimap of Forever's tunnels (Blizzard's map of them shows a later layout), with both instance portals -, the
  caves around several dungeon entrances (Maraudon, the Scarlet Monastery) and the Timbermaw Hold tunnels between
  Felwood, Moonglade and Winterspring.
- **M follows you**: M opens the map on your character and follows you, as a click on your arrow does.
  `/unroll openfollow` switches that off and on.
- Fixed: following stopped tracking you after you zoomed out past your zone's map in combat.
- Fixed: zoomed in on Orgrimmar, blurry patches covered parts of the city - its name banner, the land west of the
  Valley of Wisdom and east of the Drag: land of the city's map that no zone's map covers showed the continent's
  low-detail picture. The city's own map shows there now, and in Stormwind's harbour too.
- In the settings menu (the round button on the map): "M follows me", and "Caves appear" under Zoom - 20x, 30x,
  40x or off. "Hide these buttons" hides both buttons; `/unroll button` brings them back.

## Azeroth Unrolled 1.1.1 (2026-10-05) - fix: Lua errors from the objective tracker

- **Fixed: Lua errors from the objective tracker** - "GetAuraDataByIndex(): Auras cannot be accessed when secret
  while tainted by 'AzerothUnrolled'", mostly in combat. When the add-on switched Blizzard's world map to another zone, the
  game's quest markers for that zone loaded their quests on the add-on's behalf, and the objective tracker later read
  those quests. Now the add-on only switches to a zone whose quests the game has already loaded itself - your own zone,
  any zone you clicked or opened the map on - and otherwise lines Blizzard's map up on the continent instead: the map
  looks the same and your arrow and other add-ons' icons stay; only the game's quest markers of that zone wait until
  you click the zone once. While a quest's details are open in the quest log, the add-on leaves the map where it is.
- `/unroll taint` checks that the objective tracker's quest data is clean (for bug reports).

## Azeroth Unrolled 1.1.0 (2026-10-05) - follow a character, open the map on yours

- **Click your arrow and the map follows you.** A click on your arrow on the world map - or on a party member's
  dot - makes the map follow them: it moves with them, keeps them in the middle and changes maps as they cross into
  another zone. "Following <name>" shows at the top of the map. The mouse wheel still zooms, about them. Dragging the
  map, clicking a zone, closing the map or clicking them again stops it. `/unroll follow` switches the click off and on.
- **M opens the map on your character** at world zoom 14 instead of showing your whole zone. `/unroll openzoom <1-25>`
  sets the zoom; `/unroll openzoom off` gives the game's own view back. Opening the map any other way (the quest log, a
  quest link) works as before.
- Both are in the settings menu (the round button on the map): "Follow on click", and "M opens the map on me"
  under Zoom.
- In combat the map never changes to another map (a game rule): following keeps your character on the current map and
  catches up when combat ends.
- City of Dalaran: the two rooms the game renamed in client 70205 (The Linguist's Lounge, The Violet Hold) light up on
  its dungeon map again.

## Azeroth Unrolled 1.0.1 (2026-10-04) - the zones around you stay on the map

- **Zooming in on a zone no longer blanks out the zones around it.** From about 0.8x of a zone's own map, the zone
  you were over laid its whole map picture on top - and the game's zone maps are rectangles that show the land around
  the zone as blank parchment with the neighbours' names printed on it. Depending on where you looked, Duskwood or half
  of Elwynn Forest disappeared. Now every zone is drawn from its own sharp map art inside its own borders at every
  zoom, so the land around the zone you are looking at stays as it is.
- **Sharp coasts, soft edges.** A coastal zone now also draws the open sea along its coast from its own map art (the
  whole picture used to cover it), fading softly into the open sea and into its neighbours' seas - no boxy map edges.
- Unchanged: explored areas lie on top as the game draws them; the capitals, Blackrock Mountain and Dalaran work as
  before. On Classic Era, and with `/unroll mosaic` or `/unroll cells` off, a zone still shows its whole map picture.

## Azeroth Unrolled 1.0.0 (2026-10-04) - new name, settings button

Azeroth Unrolled is SmoothMapZoom 3.1.2 under its new name, plus a settings button on the map.

- The folder is `AzerothUnrolled`, the saved settings `AzerothUnrolledDB`; the commands are `/unroll` and
  `/azerothunrolled`.
- New: a settings button on the map (lower right corner) with a menu - toggles for the smooth zoom, place names,
  dungeon and raid icons, placeholders, dungeon maps, boss markers, moving map icons and the zoom readout; a Zoom
  submenu with presets for the wheel step, zoom depth, flight speed and the zoom at which city maps appear (10x,
  14.05x as the default, 20x, or per city zone); the command list; reset; hide the button (`/unroll button`). Built
  with the game's own menu system.
- New: the same settings on the game's Settings page (Esc > Options > AddOns > Azeroth Unrolled).
- New commands: `/unroll names` (place names), `/unroll icons` (dungeon and raid icons on the world map),
  `/unroll button`. `/unroll labels` still switches names and icons together.
- Saved settings: three new keys - placeNames, dungeonIcons and mapButton (all on by default); nothing else changes.
- Licence: GNU General Public License, version 3 or later (files `LICENSE` and `NOTICE.md`).

Below: the history of SmoothMapZoom. Its commands were `/smz ...`; they are `/unroll ...` now.

## 3.1.2 (2026-10-03) - no city map below the switch

- **Below the city switch nothing of a city's own map shows, anywhere.** Orgrimmar's cell in the map mosaic reaches
  past Durotar's map (its north half); there the city's own art stayed below the switch, at every zoom. Now the
  continent's art shows there, as in the strip beside it between Azshara's and Durotar's maps; from 14.05x the city's
  map covers it as before. (Every other capital lies inside its home zone's map.)
- **Quest areas stay on top of the city maps.** 3.1.1 put the city maps above the zone highlight everywhere - and so
  above the game's shaded quest and scenario areas as well, which only zone maps draw. Over a zone map the city maps
  now lie just above its explored areas (still over the printed city names; this game draws no zone highlight there),
  over a continent or the world map above the zone highlight.
- `/smz cityzoom` takes at most 25x: from about 25.7x the view can lie inside a city, and a higher switch let the
  city's own map show below it. The menu presets were never affected.
- After a very fast zoom-out from inside a city, its picture no longer comes back faintly for a few frames.

## 3.1.1 (2026-10-03) - city maps over the game's own map art

- **City maps are drawn over the game's own map art.** Above the city switch the six capitals, Blackrock Mountain
  and Dalaran lie over everything the game draws for the map itself: a zone's explored areas with their printed
  city names (Dun Morogh's IRONFORGE banner, Alterac's DALARAN) and a continent's zone highlight no longer cover
  them, wherever the view is. Only the map icons (the game's, the add-on's, other add-ons' pins) and the place names
  stay on top. (In the game a frame that clips its contents draws them as one block: the city maps now have a
  block of their own, right above the map art.)
- **No blurry blocks deep in a continent map.** Where the map under the add-on's is still the continent (Orgrimmar's
  north half lies outside Durotar's map), the continent's zone highlight was magnified into big blurry blocks; past
  2.5x of the continent's own view it is hidden now.
- **Fixed: a Lua error at login** ("Division by zero" in Render.lua) with the zoom readout on: the readout updates
  only while the map shows, and never divides by a map of size 0.

## 3.1.0 (2026-10-02) - one zoom level for all city maps

- **One switch for every city map.** From world zoom 14.05x (read it with `/smz zoom`) all six capitals, Blackrock
  Mountain and Dalaran show their own map; below it (they hide again just under the line, at 13.98x) the map is
  Blizzard's drawing of the zone with its printed city banner. Only the zoom decides - not where the view or the
  cursor is, and not which zone is under the centre. `/smz cityzoom <N>` sets another zoom, `/smz cityzoom default`
  is 14.05, `/smz cityzoom off` brings back the rule up to 3.0.1 (1.5x of each city's own zone). What 3.0.1 saved
  for this setting is replaced by the default once.
- **Below the switch the city spot is always the zone's own drawing.** The zone cells and explored pieces no longer
  paint the banner over, and a capital's cell shows its zone's art instead of the city's map (before, which of the
  two you saw depended on which zone was under the centre of the view).
- **Above the switch the city is always on top.** A neighbouring zone's picture can no longer lie across a city
  (Wetlands over Ironforge, Desolace over Thunder Bluff, Silverpine over Undercity, Azshara over Orgrimmar).
- **No pop at a city's edge.** A picture no longer drops under Blizzard's explored areas in one frame while it still
  shows; the city's own rectangle (with its frame) comes only once the whole view lies inside the city's map, and
  never rests half-faded with its edge on screen; fast wheel spins fade the city in a little more gently.
- **No pop-in while scrolling.** A city within one view of the screen is built and loaded ahead, so a drag or a
  fling brings it into view complete.
- **Fewer pin reloads.** Zooming out of a zone, a glide across a zone's corner, a fast drag across a city or a wheel
  spin into a city no longer switch Blizzard's map to a map that is left again a moment later.
- **Names.** A capital's name label gives way while the zone's printed banner shows the name (never twice), and comes
  back with the city's map. Labels that trade places with a city's name, or with Blackrock Mountain's and Dalaran's
  icons, crossfade instead of popping. All five Blackrock Mountain instance icons show as soon as the mountain does.

## 3.0.1 (2026-10-02) - zoom readout

- `/smz zoom`: a small readout on the map: one global zoom number (1.00x = the whole world map), the zone under
  the view's centre, and each city / detail map in view with whether its own map shows.
- `/smz cityzoom <N>`: the WORLD zoom from which every city map shows (they hide again 10% lower); `off` = the
  shipped rule (1.5x of each city's own zone). A tuning aid: the default behaviour is exactly 3.0.0's.

## 3.0.0 (2026-09-30) - the release

**Bosses and entrances on every dungeon map** (from the 2.11.0 prototype)
- Boss markers on 31 instance maps: 269 encounters from Forever's own encounter table, 252 with a
  position (165 high, 82 medium, 5 approximate). Numbers follow the game's encounter order per wing;
  optional bosses carry no number; approximate ones are drawn fainter with "Approximate location".
- Defeated bosses turn grey with a check (BOSS_KILL, ENCOUNTER_END, the instance lock the game reports on
  entering); remembered until the next loading screen.
- Entrance markers (44 on 31 maps): where you arrive; a click goes to the entrance map where there is one.
- The bar's skull button lists every boss of the dungeon and turns the markers on / off; `/smz bosses`.
- Click a boss marker to zoom in on it. The lit room's name moves clear of the markers.

**Doors on the world map**
- New door icon: Excavation Site: Wetlands (Wetlands 47.9, 56.5).
- City of Dalaran's dungeon door: an icon at the portal at the end of the sewer pipe (Alterac 9.2, 60.2),
  whose tooltip says it is not confirmed yet. It opens the City of Dalaran dungeon map; the open-world
  Dalaran city picture is untouched.
- Placeholders for the 8 instances not in the game files yet (The Drowned City, Krol'dok Stronghold,
  Alcaz Prison, Blackmaw Hold, Shaper's Terrace, Manor Mistmantle, Hyjal Summit, Barrow Deeps): hollow
  grey icons, no click, a tooltip with what is known. `/smz doors hints [on|off]`.
- Learned doors: the addon learns an instance's door when you walk in (and out), saved account-wide;
  it confirms placeholders and the unconfirmed Dalaran door, and adds icons for instances without one.
  `/smz doors`, `/smz doors forget [id]`.
- "You are inside": inside an instance its door on the world map carries your player icon, pulsing, at
  every zoom; its tooltip starts with "You are inside <name>"; a click opens the map of the instance you
  are in, also behind a shared door (Blackrock Mountain, Scarlet Monastery, Maraudon, Dire Maul).

**Fixes**
- Blackrock Mountain's picture, the capitals' city patches and the home zones' banner covers no longer
  vanish after an exploration update while the map is at rest (they stayed invisible until the next
  input).

**Other**
- README.md and this changelog in the addon folder.
- No live minimap panel (not asked for); nothing else changed.

## 2.11.0 (prototype, not released on its own)
- Boss and entrance markers on the dungeon maps (see 3.0.0).

## 2.10.0 (2026-09-30)
- The Hall of Thanes: a door icon in Ironforge (28.3, 47.7, confirmed in game) that opens its map.
- Dalaran is the open-world city of Alterac Mountains in Forever: it is drawn into the world map from the
  client's own minimap art (cut to its barrier ring and gate plaza), with its name as a label.

## 2.9.0 (2026-09-30)
- "Where am I" inside instances: the room the game names is lit and labelled on the floor shown, the
  floor is picked by sub-zone, and a chip on the bar names the room ("Room not named" otherwise).
- The engine's own unit frame on the City of Dalaran and Half-Pint Tavern pages.

## 2.8.0 (2026-09-29)
- Blackrock Mountain: stairs pins between its levels, a level button on the bar, clicks go through to
  the level under the cursor.
- The Deeprun Tram with 3 floors (Stormwind station, the whole line, the Ironforge station).
- Maps for Forever's own instances built from their minimap tiles (Ruins of Lordaeron, Excavation Site,
  Half-Pint Tavern, City of Dalaran, The Hall of Thanes); the Ruins of Lordaeron portal as a door icon.

## 2.7.0
- The Deeprun Tram map; Blackrock Mountain as a city-like detail level with clickable instance icons.
- The player and party on entrance maps drawn by the game's own widget; `/smz markers`.

## 2.6.0
- Dungeon maps open by clicking the dungeon icons; entrance maps with an icon per dungeon for shared
  doors (Blackrock Mountain, Scarlet Monastery, Maraudon).
- A heading player arrow on the dungeon maps.

## 2.5.0
- Dungeon maps: Blizzard's dungeon art that ships in the Forever client, drawn by file ID, with floors
  and a floor dropdown; they open by themselves inside dungeons.

## 2.4.0
- Capital cities show their own map as soon as it is the sharper art; deep zoom stays inside maps that
  have the detail for it; wheel zooms into a city end where the cursor points.

## 2.3.0
- Map icons move with the map (`/smz livepins`).
- Capital cities (Ironforge) layered correctly; zone land from the game's own zone-shape masks instead of
  magnified continent art (`/smz cells`).

## 2.2.1
- At rest the addon's art lives inside Blizzard's map canvas, below every pin (Questie and quest icons
  stay clickable); review fixes.

## 2.1.1
- Crash fix for WoW Forever 1.60.1: no frame buffers (the client asserted on them); fades without them.
