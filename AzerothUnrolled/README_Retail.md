# Endless Map

Version 1.6.1 - for **retail World of Warcraft** (12.1.5, interface 120105).

One smooth zoom over the whole world map. Open the map and you are in space, on Blizzard's map of the worlds; scroll
into any world, any continent, through the small inset maps (Argus, the Maelstrom, Nazjatar, ...) down to the centre
of any zone - and back out, in one zoom. What you see depends on the zoom alone: the same zoom looks the same wherever
you drag. Each zone is cut to its own land with soft edges, so no map's frame, margin or parchment sea is drawn over
its neighbours.

Install: the folder is `EndlessMap` (in `World of Warcraft\_retail_\Interface\AddOns\`). After an update, `/reload`
loads the new files.

## What it does

- One smooth zoom from space down to about 4x past a zone's own map. Dragging pans across zone, continent and world
  borders - out into space too; a flick glides on. Clicking a world or a zone flies there, and so do Blizzard's own
  clicks (the quest log, the floor list).
- Every zone of every continent and world is drawn cut to its land; the zones turn to their detail together as you
  zoom, by the zoom alone. Open-world cities (Oribos, both Dalarans, Stormshield, Warspear, ...) and the capitals show
  their own maps over their home as you close in.
- Pictures load ahead of you and fade in once loaded; nothing fades out before what replaces it is there.
- Every map in view shows its own markers at once: flight masters, points of interest, events, delves and quests. Hover
  for what they are; a click tracks the quest or sets the waypoint. Other add-ons' icons on Blizzard's map move with
  the map and stay clickable at rest; on a zoom out they can hide until the map stops.
- Every portal, boat, zeppelin and tram: hover one for an arc to where it goes, click it to fly there. A room of portals
  opens a list. Their destinations use the names in the game's travel data, which are in English.
- Click your arrow (or a party member's dot) and the map follows them; M opens the map on your character and follows
  you.
- Party bubbles: you and your party (in a raid: your group) as small round portraits in the map's top left corner.
  Hover one for the zone they are in; click it and the map flies to them and follows them.
- Minimap imagery: the map drawn from the game's own minimap pictures - the real terrain, with the fog of war - instead
  of the drawn map (the round button with the terrain picture, or `/emap imagery`; off by default).
- Caves and interiors show their tunnels from world zoom 30 (the caves button, or `/emap cavezoom`).
- Place names: cities, dungeons and raids (with their level range), flight masters. A click on a door's name flies
  there and opens the dungeon's map; while you are inside an instance its door shows your icon.

## Settings

A small round button in the map's lower right corner opens the settings; left of it the caves button and the imagery
button. The same settings are on the game's own page Esc > Options > AddOns > Endless Map, and every one of them has a
slash command.

## Slash commands

`/emap` shows the settings and this list. Every command works as `/emap <command>` or `/endlessmap <command>`.

| Command | What it does |
|---|---|
| `/emap on`, `/emap off` | the smooth zoom on / off (Blizzard's map as usual when off) |
| `/emap depth <1-10>` | how far past a zone's own map you can zoom (default 4) |
| `/emap step <1.05-2>` | zoom per wheel notch (default 1.3) |
| `/emap speed <0.25-4>` | speed of the map's flights - a click on a zone, a party bubble, following someone (default 1) |
| `/emap labels` / `rest` | place names and door icons together on / off; the names and icons while the map is still |
| `/emap names` | place names on / off |
| `/emap icons` | dungeon and raid doors on the map on / off |
| `/emap flight` | the flight masters' names on / off |
| `/emap button` | the round buttons on the map on / off |
| `/emap portals` | the portal, boat, zeppelin and tram markers on / off |
| `/emap bench` | what the map costs on this machine: it flies itself for about a minute and a half, a line in the chat at the end |
| `/emap livepins` | map icons move with the map (off: hidden while it moves) |
| `/emap cells` | the zones cut to their land (off: each zone's whole picture as you near it) |
| `/emap zoom` | a zoom readout on the map: the world zoom (1.00x = the Azeroth map) and what is drawn |
| `/emap follow` | a click on your arrow / a party member's dot makes the map follow them: on / off (default on) |
| `/emap openzoom <N>`, `default`, `off` | the world zoom M opens the map at, on your character: default 14; off = the game's own view |
| `/emap openfollow` | M also follows you: on / off (default on) |
| `/emap bubbles` | the party bubbles in the map's top left corner: on / off (default on) |
| `/emap imagery` | the minimap imagery - the map drawn from the game's minimap pictures: on / off (default off) |
| `/emap imagerytiles` | the minimap imagery's closest zoom from the game's own minimap tiles: on / off (default on) |
| `/emap cavezoom <N>`, `default`, `off` | the world zoom from which caves show their tunnels: default 30; off = never |
| `/emap link` | the download link in your own chat window (only you see it) |
| `/emap news` | what's new in this version - the window that opens by itself the first time the map opens after an update - with the download link to copy and share |
| `/emap bug` | a bug report to copy - versions, settings, the add-on's errors - and paste in Endless Map's bug form on GitHub |
| `/emap taint` | checks that the objective tracker's quest data is clean (for bug reports) |
| `/emap debug` | how the map layers are stacked (for bug reports) |
| `/emap why` | what the map shows here and why - kept in the saved settings too (for bug reports) |
| `/emap test <switch>` | test switches for this session only (`/emap test` lists them; `off` clears them all) |
| `/emap reset` | settings back to their defaults |

## License / author

Copyright (C) 2026 Hadlock.
Endless Map is free software under the GNU General Public License, version 3 or (at your option) any later version
(SPDX: `GPL-3.0-or-later`); it comes WITHOUT ANY WARRANTY. The full text is in `LICENSE`; data sources and
third-party notices are in `NOTICE.md`.

By Hadlock. Blizzard's art and data belong to Blizzard Entertainment; the add-on draws the files already in your
client, and carries only pictures derived from them: the minimap imagery's overview pictures (`Media\Retail\`), the zones'
small pictures and the covers of printed names (`Masks\Retail\Lod\`, `Masks\Retail\Covers\`) and the masks in
`Masks\Retail\` (see `NOTICE.md`).
