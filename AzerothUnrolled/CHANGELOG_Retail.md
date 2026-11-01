# Changelog

## Endless Map 1.5.0 (in work) - retail

- A marker's list of ways and its arcs lie over everything on the map, and a click on the list is always the list's, also over your arrow or a door. A destination's name at the map's top edge is no longer cut off.

## Endless Map 1.4.0 - retail

The first release on retail World of Warcraft (12.1.5).

- One smooth zoom from space to every zone of every world, the same map wherever you look, every zone cut to its land.
- Every map's own markers at once: flight masters, points of interest, events, delves and quests.
- Every portal, boat, zeppelin and tram: hover for an arc to where it goes, click to fly there.
- Every dungeon and raid door, cities' own maps, caves, following, party bubbles and the minimap imagery.
- Light on the game: only what is on the screen is shown, and a map standing still stops redrawing. `/emap bench` measures it on your machine.

### The test builds

- **The release candidate: less work again, no more bursts** (1.4.0-beta16). The map checks only what is near the view each frame, caves and names too. On a fast zoom out
  quests, flight masters and names load a few at a time, those on the screen first. Pictures fade out in the same time on a slow frame as on a quick one.
- **The same map for far less work** (1.4.0-beta15). Only what is on the screen is shown, with what lies just outside it loaded ahead and waiting hidden. Blizzard's own map art no longer 
  loads and moves behind this one, and its map switches where a move ends, not in the middle of a zoom. `/emap bench` shows what the map costs on your machine.
- **Portals and where they go, a tighter viewport, one zoom a level, printed names gone** (1.4.0-beta14). Every portal, boat, zeppelin and tram is on the map:
  hover for an arc to where it goes, click to fly there. A room of portals opens a list. The map keeps only what is near the view on screen, no longer reloads what it
  has seen, and draws a zone explored whole from one small picture while it is small on the screen: far lighter on the largest maps, never showing a hole. Worlds, continents and zones each come in at one zoom everywhere. Azeroth's giant letters,
  zone names cut at the coast and city names half under a city's map are gone.
- **One zoom for every continent, the same map wherever you look, all of Blackrock Mountain** (1.4.0-beta13). Every zone's
  detail map on Azeroth comes in at one zoom. Blizzard's explored pieces no longer lie over the map, so it no longer changes
  with where the view or the mouse is. Every level of Blackrock Mountain shows by zoom alone, with all its entrances. Backing
  out of a dungeon's map returns to the view you opened it from. New entrances: the Deeprun Tram and Torghast. City maps are
  redone from one source: Silvermoon City shows its real plan, and missing districts are back. A map standing still stops
  redrawing itself on the largest maps.
- **The map answers the mouse everywhere, every zone of a map at one zoom, less lag** (1.4.0-beta12). Entrances and
  city icons open their maps, quests hover and track, a click on a zone flies into it and a right click goes out, at
  rest or not; zooming out of a dungeon's map carries on into the world. Caves and Blackrock Mountain show by zoom
  alone. Every zone of a continent comes in at the same zoom, with its flight masters and quests. The map keeps the
  pictures it loaded instead of loading them again on every zoom out and every time it opens, and does far less work
  each frame. Entrance names stay on the map at its edges.
- **Quests and your arrow with their maps** (1.4.0-beta11). Every zone in view shows its own quests as its map comes
  in - the quest log's (in Blizzard's look: in progress, ready to turn in, the tracked one), world quests, bonus
  objectives, quests on offer and quest hubs; hover for the quest, click to track it. Your arrow and your group's dots
  sit where the map draws your place - over the Maelstrom and the whole of Azeroth too - at every zoom.
- **Every map's markers with its map** (1.4.0-beta10). Every dungeon and raid entrance has its diamond again, in every
  zone at once; Blackrock Mountain is one entrance outside and its dungeons and raids come with the mountain's own map
  (so do the Caverns of Time, Maraudon, the Scarlet Monastery, Uldaman and the Master's Cellar). The flight masters and
  the places a map marks - a city's portals, the events, the delves - show in every zone in view as its
  map comes in, a click sets the waypoint. At the Maelstrom the highlight and the name under the cursor match the
  islands, and the mines the game keeps off Kezan's coast show only while you are in them.
- **Every zone of a continent at once** (1.4.0-beta9). Zooming in, all the zone maps of a continent replace its drawing
  at one zoom and fade in together once all in view are loaded - no zone coming before its neighbours or popping in
  late; Quel'Thalas comes with the Eastern Kingdoms. A few small islands with very detailed maps come a little deeper.
  The continent's printed EASTERN KINGDOMS goes once its zones are in.
- **Quel'Thalas for every character** (1.4.0-beta8). A character on the old Quel'Thalas gets its zones - Eversong Woods,
  the Ghostlands, Silvermoon City, the Isle of Quel'Danas, Sunstrider Isle - like every other zone: their maps with the
  character's explored areas, their names, clicks, the full zoom and Silvermoon City's map; a Midnight character sees
  Midnight's zones. The map picks them by itself.
- **The Maelstrom's places together** (1.4.0-beta7). The Lost Isles, Kezan, Deepholm and the swirl lie close together
  where the Maelstrom is and come in at one zoom, as a continent of that size does; the world map's drawing of the
  Maelstrom shows until then.
- **Zones in another phase, Mechagon, Argus, no fog deep in** (1.4.0-beta6). A zone whose map changes with the story
  (Silithus after the sword, burnt Darkshore, the Arathi warfront, Tirisfal after the Undercity and others) draws for a
  character who sees that version - it was missing. Mechagon's printed name is whole. Deep in, where no zone's map lies,
  the world's plain sea instead of its map blown up into a blurry fog. Argus's islands lie on Argus's own sky, and its
  map dims a little once a zone's real map is in. With the terrain on, the Maelstrom's places show at every zoom.
- **The Maelstrom** (1.4.0-beta5). Its map is drawn as its places' land only - the Lost Isles, Kezan and Deepholm, each
  near its own zoom - never its whole picture, whose sea and swirl opened over the Broken Isles' west; with the terrain
  imagery on, the Lost Isles, Kezan and Deepholm show their terrain.
- **The look by the zoom alone** (1.4.0-beta4). The same zoom now looks the same wherever you drag: a continent never
  shows its whole picture - its own sea, title, compass or frame - because the view's centre is over it, and no
  map's border fades in or out as you pan or as the map comes to rest. Every map is drawn as its land only, with soft
  coasts over the sea round it, and the maps' printed titles, banners, frames and compass roses are left out - the
  continents', the ones in the zones' seas (Durotar's compass rose) and the worlds' second titles on the map of space.
  The small inset maps (Argus, Nazjatar, Zaralek Cavern, K'aresh, Undermine, Voidstorm, Harandar) come in near their
  own zoom as their own land, softly in their places - no boxes, frames or banners. Past a world's edge its own sea
  colour continues softly.
- **Every small zone and city its own shape** (1.4.0-beta4). The starting areas and small zones (Northshire, Coldridge
  Valley, Deathknell, Valley of Trials, Camp Narache, Shadowglen, Ammen Vale, the Echo Isles, Northern Stranglethorn and
  the Cape, the Veiled Stair) have their own maps cut to their shape as you close in, without their title banners; a
  city's map (Dornogal, the capitals) is cut to the city's shape - no straight edge.
- **Vashj'ir and the north of the Eastern Kingdoms** (1.4.0-beta4). Vashj'ir is drawn in its own deep sea, cut to its
  shape, and its three areas come in over it as you close in; with the minimap imagery on, Vashj'ir's sea floor is
  there in the game's own colours. The Eastern Kingdoms' north is Quel'Thalas's own map (Eversong Woods, Silvermoon,
  Zul'Aman, the Isle of Quel'Danas) as soon as the continent's own map is drawn - also for a character who has not
  started Midnight. The imagery's
  colours are a little brighter, as the game draws them; with it on, Argus and the Maelstrom keep their drawn map.
- **Nothing shown before it has loaded** (1.4.0-beta4). Every picture waits, invisible, until the game has loaded it -
  however long that takes - and the map under it stays until then; nothing is shown half-loaded after a timeout.
- **The add-on's own name on retail** (1.4.0-beta4). Retail uses Endless Map everywhere: the folder `EndlessMap`, the
  commands `/emap` and `/endlessmap`, its own saved settings; the old name is in none of its files.
- **WoW Forever's look** (1.4.0-beta3). Every zone of every continent and world is cut to its own land with soft
  edges, the zones turn to their detail together as you drag and zoom, a world fades softly into space at its edge and
  you can drag out into space. Oribos, both Dalarans, Stormshield, Warspear and the other open-world cities are on the
  map, each with its own map over its home as you close in.
- **Feature complete** (1.4.0-beta3). The minimap imagery (the real terrain, with the fog of war and the sub-zone
  names; its button, `/emap imagery`), the caves and interiors (from world zoom 30; the caves button, `/emap
  cavezoom`), the names of cities, dungeons and raids (with their level range) and flight masters, a click on a door's
  name flies there and opens the dungeon's map, your icon on the door of the instance you are in, and the party bubbles:
  click from one member to another, also in the middle of a flight.
- **The map is no longer black between space and the zones** (1.4.0-beta2). The pictures load the way the game loads
  its own map: each waits, invisible, until the game has loaded it, then fades in over the map under it, and nothing
  fades out before what replaces it is there.
- **The map** (1.4.0-beta1). Open the map in space, on Blizzard's map of the worlds, and scroll: into any world, any
  continent, through the small inset maps, down to the centre of any zone - and back out, in one smooth zoom. Drag
  across borders, click a world or a zone (or use the quest log and the floor list) and the map flies there; M opens
  it on your character, a click on your arrow follows you, the party bubbles fly to your party. Settings are on the
  map's round button and in Esc > Options > AddOns > Endless Map. After an update, `/reload` loads the new files.
- 1.4.0-beta0 was only a preview: it checked that Endless Map loads on retail, without changing the map.
