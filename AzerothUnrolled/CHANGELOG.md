# Changelog

## Endless Map 1.6.1

- **What's new, in the game**: the first time you open the map after Endless Map updated, a window in the game's own style shows what changed, with Endless Map's link to share (Copy link, then Ctrl+C). Untick "Show what's new after an update" in it (or in the settings) and it stays away. The map menu's "What's new" and `/unroll news` open it any time.
- **Report a bug**: in the same window, a ready-made report - the add-on's and the game's versions, your settings, the add-on's own errors. Copy report and Copy form link (each then Ctrl+C), open the link - Endless Map's bug form on GitHub, your game and the add-on's version already filled in - and paste the report in it. Nothing is sent from the game. In the map menu, the settings, or `/unroll bug`.
- **The download link**: `/unroll link` shows it in your own chat window (only you see it); the What's new window has it to copy.

## Endless Map 1.6.0

- **WoW Forever: quest icons from higher up** (1.6.0-beta1). Your quests, the tracked quest's way and the quests on offer show for every zone in view from world zoom 10 (`/unroll questzoom`, or the settings' "Quest icons appear") - the game's map shows a zone's quests only on that zone's own map. They look as the game draws them; hover one for what is left to do, click it to track it (again: stop tracking). `/unroll questzoom off` gives the game's own back. A click tracks a quest in combat too, as the game's icon does; while a quest's details are open in the quest log only that quest shows, as on the game's map; quest hubs show with the quests on offer they stand for coming in as you zoom in.
- **City of Dalaran: the room names of WoW Forever's launch** (1.6.0-beta1): Dalaran Visitor Center, Runeweaver Lounge and The Wonder Works light up again where you stand.
- **Boss numbers in the game's order** (1.6.0-beta1): Ruins of Lordaeron (Viktor the Vile 4, Bjork 5, Rath'mael 6) and City of Dalaran (Shade of the Archmage 9).

## Endless Map 1.5.0

- **WoW Forever: every boat, zeppelin, skycutter, portal and the tram on the map** (1.5.0-beta1). A marker at each dock and portal from the zoom the continents fill the view, your faction's ways only; hover for an arc to where it goes, click a way to fly there. Zephras Isle has no place on the Azeroth map: its arc rises off the top and a click opens Blizzard's map of the isle. The Deeprun Tram keeps its door: hover for the arc, click for the tram's map. `/unroll portals` turns the markers off and on. Names are in English. Classic Era shows only the routes it has.

## Endless Map 1.4.0 - retail

- **`/emap`** (1.4.0-beta4): a short form of `/endlessmap` on WoW Forever and Classic Era too; nothing else changes
  there - the folder, the saved settings and `/unroll` stay.
- **Retail is its own download** (1.4.0-beta4): the folder `EndlessMap`, the commands `/emap` and `/endlessmap`, its
  own README and changelog. On retail the same zoom now looks the same wherever you drag - every map drawn as its land
  only, no frame, margin, title or sea of a map fading in or out -, the small inset maps, starting areas and cities
  come in cut to their own shapes, Vashj'ir is drawn in its own deep sea, the Eastern Kingdoms' north is
  Quel'Thalas's own map as soon as the continent's is drawn, and Vashj'ir's sea floor is in the terrain imagery.
- **Retail: WoW Forever's look** (1.4.0-beta3). Every zone of every continent and world is cut to its own land with soft
  edges - no rectangles or parchment margins over the neighbours, no blurry strip round Orgrimmar -, the zones turn to
  their detail together as you drag and zoom, a world fades softly into space at its edge and you can drag out into
  space. Oribos, both Dalarans, Stormshield, Warspear and the other open-world cities are on the map, each with its own
  map over its home as you close in.
- **Retail: feature complete** (1.4.0-beta3). The minimap imagery (the real terrain, with the fog of war and the sub-zone
  names; its button, `/emap imagery`), the caves and interiors (from world zoom 30; the caves button, `/emap
  cavezoom`), the names of cities, dungeons and raids (with their level range) and flight masters, a click on a door's
  name flies there and opens the dungeon's map, your icon on the door of the instance you are in, and the party bubbles:
  click from one member to another, also in the middle of a flight. After an update, `/reload` loads the new files.
- **Retail: cleaner still** (1.4.0-beta3). No continent frame or rectangle over space when you fling, drag or fly out of
  a continent; the small inset maps fade into their boxes; zooming out of a zone changes nothing all at once; Oribos
  comes in without the Shadowlands' giant tower round it; the big new cities at the same distance as the others; a door
  click you overtake by scrolling or dragging opens nothing. The terrain imagery never hangs dark boxes into space, fades
  softly at a world's edge and keeps the normal map if the game cannot load its pictures.
- **Retail: the map is no longer black between space and the zones** (1.4.0-beta2). The pictures now load the way the
  game loads its own map: each waits, invisible, until the game has loaded it, then fades in over the map under it -
  space's map under the worlds, a world's under its continents, a continent's under its zones - and nothing fades out
  before what replaces it is there. Blizzard's own map stays visible until the add-on's picture over it has loaded.
- **Retail: zones from far out** (1.4.0-beta2). On Kalimdor, the Eastern Kingdoms and Quel'Thalas every zone's own
  map shows, cut to its land, from about 5x (Quel'Thalas about 14.5x) - as on WoW Forever - instead of only the zone
  you are over, close in. The map also loads more around the view and where you are heading.
- **Retail: Blizzard's own map where it shows the view** (1.4.0-beta2). Wherever Blizzard's map already shows the view
  - at rest, and while it follows a drag or a zoom - the add-on no longer lays its own, coarser pictures over it: no
  blurry space map over Draenor, no fade-in over the right map when you open it. Worlds and continents load whole, so
  zooming out shows no edges popping in; the zones' cut-outs no longer leave gaps between them (Orgrimmar's valley
  included); and a zone's shape shows even if the game never says its mask has loaded.
- **Retail World of Warcraft: the map** (1.4.0-beta1). Open the map in space, on Blizzard's map of the worlds, and
  scroll: into any of the four worlds, any continent, through the small inset maps, down to the centre of any zone -
  and back out, in one smooth zoom. Drag across borders, click a world or a zone (or use the quest log and the floor
  list) and the map flies there; M opens it on your character, a click on your arrow follows you, the party bubbles
  fly to your party. Pictures load as you go. Each picture fades in over about a third of a second, and wherever you
  stop none is left half-faded: a continent shows with its own sea and frame (no longer Azeroth's drawing beside it),
  a zone's own picture covers the view once you are inside it, the zone drawn is the one Blizzard's map shows, and
  zooming back out to space ends without an empty strip. Names are added only where the map's own art does not print
  them (Kalimdor and the Eastern Kingdoms).
  Settings are on the map's round button and in Esc > Options > AddOns > Endless Map; WoW Forever's own options (city
  maps, caves, minimap imagery, dungeon icons, flight masters) are left out on retail. After an update, `/reload`
  loads the new files.
- 1.4.0-beta0 was only a preview for retail: it checked that Endless Map loads there (a page in the AddOns settings
  with the add-on's icon and a round picture), without changing the map.
- **WoW Forever and Classic Era**: the same as 1.3.1. The add-on now notes quietly in its saved settings which of its
  files the game loaded; nothing changes for you.

## Endless Map 1.3.1 (2026-10-18) - the new name

- **Azeroth Unrolled is now called Endless Map.** It is the same add-on: the map, the settings, the buttons and every
  command work as in 1.3.0.
- **Gilneas is on the map** (WoW Forever). The land south of Silverpine Forest and the Greymane Wall is in the game,
  but the game has no map of it, so the map showed only the blurry continent picture there. Now it is drawn like the
  maps beside it - coast, mountains, roads, Gilneas City and its houses, all from the game's own terrain - and named:
  "Gilneas" from the continent view in, "Gilneas City" as you zoom in. It shows wherever zone maps show (not under the
  minimap imagery, which has the terrain anyway; the names stay), and you can zoom in on it as on any zone - before,
  the zoom stopped far out over it. A party member there shows as in Gilneas.
- **Gilneas follows the fog of war like every zone**: parchment until you have been there. Each part of it - the
  countryside (most of the land, all at once), Gilneas City, the Greymane Wall, the islands off the coast - turns to
  colour once you have walked into it, right away even with the map open, and stays so for that character (another
  character sees its own). Gilneas City's name shows once you have been there. With the minimap imagery on,
  Gilneas's land is greyed until explored, as everywhere; with "unexplored land drawn in map style" off
  (`/unroll mosaic`), unexplored Gilneas is left out like every zone's unexplored land.
- Your settings are kept: the add-on's folder is still `AzerothUnrolled`, and the game keeps the saved settings by
  that folder, so an update over 1.3.0 (or any earlier version) starts with everything as you left it.
- The name shows in the AddOns list, on the Settings page (Esc > Options > AddOns > Endless Map), on the map menu and
  in the chat.
- New command: `/endlessmap` - the full one, it always works. `/unroll` stays the short form and `/azerothunrolled`
  still works.
- Fixed: two copies of the add-on enabled at once - for example the CurseForge copy and a test copy - no longer fight
  over the map: only one runs. (A new character starts with every add-on enabled; with two copies on, zooming was
  jittery.) While the test copy, Endless Map (beta), is enabled, it is the one that runs; the other copy does
  nothing and says nothing. A copy older than 1.3.1 cannot step aside, so next to one the newer copy does - and
  leaves the older copy's settings as they are.
- Minimap imagery: the lakes and rivers match the game's again. The game's latest patch drew the minimap's water
  darker; the imagery's pictures are now made from the new minimap, so lakes, rivers and coasts no longer change
  colour as you zoom in, and land Blizzard reshaped shows as it is now. The open sea stays one calm blue.

## Azeroth Unrolled 1.3.0 (2026-10-07) - minimap imagery, party bubbles, smooth flights

- Fixed: zooming with the mouse wheel while the map follows you (or a party member) lost track of them - the map
  zoomed about the middle of the view and slid away from them until it stopped; zoomed in from a whole continent, it
  could throw you right off the map. Now the zoom goes about the one you follow, who stays in the middle of the map
  all the way in and out (on the world and continent views as close to the middle as the map's edge allows, gliding
  back onto it as you zoom in), a fast spin in from the whole world goes as deep as you spin (it stopped at about 5x),
  and a capital city no longer pulls the view onto itself while you follow someone past it.
- **Party bubbles**: you and your party (in a raid: your own group) as small round portraits in the map's top left
  corner, under the map-pin button. Hover one to see the zone they are in; click it and the map flies to them - it
  zooms out, glides across and zooms back in, one smooth arc - and follows them; click again to stop. A turn of the
  wheel on the way changes how close it lands; another bubble on the way turns the flight to that one, at your zoom.
  The bubble of the one followed glows; offline or dead members are greyed. `/unroll bubbles`, the map menu or the
  Settings page switch them off and on. The zoom readout (`/unroll zoom`) moved to the right of the bubbles.
- The map no longer jumps when the one you follow is suddenly far away - through a portal, a hearthstone, the end of a
  long trip, even in the middle of a zoom: it flies after them the same way.
- **Minimap imagery**: the whole world map drawn from the game's own minimap pictures - the real terrain, from the
  whole world down to the deepest zoom - instead of the drawn map. Switch between the two with the new round button
  left of the caves button (its picture shows the other look; it glows while the imagery is on), the map menu, the
  Settings page or `/unroll imagery` (off by default). Land you have not explored is greyed as you zoom in on a
  continent (the sea and the capitals stay in colour), and turns to colour the moment you explore it. Zone and city
  names stay on the map, explored sub-zones get their names; Ironforge's and Undercity's city maps still show (they are underground), the caves,
  Blackrock Mountain, Dalaran, dungeon entrances and every map icon too.
- In combat the game allows no map change, so following keeps the view inside the map shown, as before; a turn of the
  wheel now brings the one you follow back to the middle even past that map's edge, and Blizzard's own map and its
  pins come back there when combat ends.

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

The first release on CurseForge - the add-on was called SmoothMapZoom while it was being made - with a settings
button on the map.

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
