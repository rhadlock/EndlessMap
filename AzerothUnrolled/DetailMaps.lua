local _, ns = ...

-- Detail levels drawn INTO the world map (Render.lua, like a capital's own map over its home zone).
-- Blackrock Mountain: a mountain of five instances whose entrance level Blizzard drew at 4.1x Burning Steppes' texel
-- density (0.711 yd/px vs 2.923). Dalaran (1.0.0): WoW Forever's OPEN-WORLD city in Alterac Mountains (Eastern
-- Kingdoms, map 0 - in game inside it C_Map.GetBestMapForUnit = 1416, UnitPosition = 172, 299, instance 0), drawn from
-- the client's own Eastern Kingdoms MINIMAP tiles (0.96 px/yd: 2.68x Alterac's texel density; they show Forever's new
-- walled city), cut to its barrier ring and gate plaza. Nothing here is a uiMap of this client: an entry is a VIRTUAL
-- map (id < 0) that Render never passes to WorldMapFrame:SetMapID or C_Map; its art is drawn by fileDataID.
--   id       = virtual map id (negative: never a real uiMap; -229 = Map.db2 229 Blackrock Spire, -279 = AreaTable 279
--              "Dalaran" - NOT the City of Dalaran instance 2959, whose pages (ns.DUNGEON_MAPS[2959]) it never opens)
--   cave     = ns.DUNGEON_CAVES key of the level shown (art tiles t, world rect r)
--   art      = instead of cave: the level's own art grid { m = map, r = world rect {minX, minY, maxX, maxY}, lw x lh
--              layer px of tw x th tiles, t = fileDataIDs row by row, north row first, west tile first }
--   name     = (no entrance) the entry's name (Render bookkeeping only)
--   label    = a name label shown with the picture (Labels.lua; kind "city" unless kind): world (wx north, wy west),
--              ar = AreaTable ID localized by C_Map.GetAreaInfo, n = enUS fallback. No entrance: not a click target
--   home     = its zone's uiMap: its continent (the level shows over that continent), its banner cover's art; the level
--              is drawn only where that zone's cell mask fits this client. The city switch (Render.lua) turns it on - as
--              the capitals; with /unroll cityzoom off by this zone's own zoom; a cave (gate "cave") by the cave switch
--              (1.2.0: or the deepest zoom over it, where less)
--   entrance = ns.INSTANCES / ns.DUNGEON_ENTRANCES key: clicking the bare art opens that entrance map; its world icon
--              gives way while the level shows (Labels.lua)
--   mask     = shape mask (256x256 32-bit RLE TGA, white + alpha, stretched over the whole picture: tools/brm_masks/mask.py -
--              the dark rock of the drawn mountain; frame, title banner, corner art and printed labels left out;
--              tools/dal_mask/dalmask2.py - Dalaran's barrier ring, its causeway and gate plaza)
--   nz       = picture-px box {x0, y0, x1, y1} outside which the mask is zero
--   under    = a second level drawn UNDER it with its own mask (the halls of Blackrock Depths, lava lake left out), so
--              the Blackrock Depths / Molten Core icons sit on drawn art
--   cover    = the home zone's printed label to paint over while the level shows: dst {x0, y0, x1, y1} in the home
--              zone's layer px gets its explored art from src (top-left of a same-sized rect), feathered; only while
--              the explored piece that prints it shows (piece = {offsetX, offsetY, width, height} of that
--              C_MapExplorationInfo.GetExploredMapTextures entry: Burning Steppes' "Blackrock Mountain", overlay 5113);
--              or several rects (rects = { {dst, src, feather, pieces = {piece, ...}}, ... }), each only while one of
--              ITS pieces shows; explored = true: the source art is the home zone's explored pieces (what it shows),
--              not all of them (so a partly explored zone gets a patch in its own shade)
--   icons    = the instances behind it, at the portals drawn in the art (data/portals/portals_70009.json, cross-checked with Forever
--              Map.db2 Corpse / AreaTrigger.db2 / portal M2 197007): world (wx north, wy west), m = instance map, f = floor
--              a click opens, n = enUS name (lfg: LFGDungeons ID of a wing, localized by GetLFGDungeonInfo), kind
--   hit      = click grid of the mask: 100 x 67 cells over the picture, per row the column ranges inside the shape
--              (alpha >= 0.5); the under level has its own
ns.DETAIL_MAPS = {
  brm = {
    id = -229, cave = "brm_spire", home = 1428, inst = 0, entrance = "Blackrock Mountain",
    mask = "Interface\\AddOns\\AzerothUnrolled\\Masks\\brm_spire.tga", nz = { 293, 88, 920, 629 },
    under = { cave = "brm_depths", mask = "Interface\\AddOns\\AzerothUnrolled\\Masks\\brm_depths.tga", nz = { 238, 83, 615, 588 },
      hit = { cols = 100, rows = { "", "", "", "", "", "", "", "", "", "28-30,34-40", "28-40", "27-39", "26-39", "26-40", "25-41", "25-41,46", "25-41,46-47", "25-42,45-47", "25-47", "25-47", "25-47,50-51", "25-51", "26-51", "26-51", "25-51", "26-47", "26-47", "26-48", "26-50", "27-52,57", "28-53,57", "28-54,57-59", "29-55,58-59", "29-56,58-59", "29-59", "28-57", "28-57", "27-57", "27-57", "27-57", "27-57", "26-57", "26-57", "26-57", "27-56", "28-55", "28-55", "28-55", "30-53", "32-53", "32-52", "33-40,44-53", "34-39,44-54", "35-38,44-55", "43-55", "53-55", "55", "55", "", "", "", "", "", "", "", "", "" } } },
    cover = { piece = { 173, 101, 256, 288 }, dst = { 244, 206, 356, 272 }, src = { 556, 376 }, feather = 12 },
    icons = {
      { wx = -7482.9, wy = -1323.7, m = 229, f = 7, n = "Upper Blackrock Spire", lfg = 43, kind = "dungeon" }, -- spire art px 791,222
      { wx = -7531.2, wy = -1342.9, m = 229, f = 1, n = "Lower Blackrock Spire", lfg = 31, kind = "dungeon" }, -- spire art px 818,290
      { wx = -7664.2, wy = -1217.1, m = 469, f = 1, n = "Blackwing Lair", kind = "raid" },                    -- spire art px 641,477
      { wx = -7498.5, wy = -1035.6, m = 409, f = 1, n = "Molten Core", kind = "raid" },                       -- depths art px 538,543
      { wx = -7177.7, wy = -925.6, m = 230, f = 1, n = "Blackrock Depths", kind = "dungeon" },                -- depths art px 393,120
    },
    hit = { cols = 100, rows = { "", "", "", "", "", "", "", "", "", "", "42-51", "40-51", "39-52", "39-51", "39-51", "39-51", "39-52,61,68", "40-52,60-61,65-70", "40-61,66-71,76-82", "40-62,66-71,74-84", "40-62,66-86", "39-63,66-87", "39-89", "37-90", "37-90", "37-90", "37-90", "36-89", "35-88", "35-88", "34-87", "34-81,86-87", "33-77", "33-77", "33-77", "31-77", "31-77", "31-75", "30-71", "31-70", "31-71", "33-70", "33-69", "34-69", "34-69", "35-70", "35-70", "36-70", "36-70", "37-68", "38-60", "39-60", "40-59", "40-57", "41-56", "42-56", "42-55", "42-54", "43-53", "44-53", "45-53", "45-53", "", "", "", "", "" } },
  },
  -- Dalaran (open world): EK map-0 minimap tiles tx 30..32 x ty 30..32 (a 1536 x 1536 picture of 1600 x 1600 yd; the
  -- mask, as the engine stretches it, is 0 from x 1023 on, so the tx 32 column is never drawn; nz is that nonzero box,
  -- x 339..1022, y 447..1154, plus a pixel), cut to the barrier ring (the ring as fitted on these tiles:
  -- centre 244.57 N, 356.55 W, its centre line 302.6..327.3 yd out; the mask is opaque to 331+ yd, 0 by ~355 yd), plus
  -- the causeway and the round gate plaza south-east of the gate (plaza centre -66.4 N, 132.9 W), whose parchment drawing
  -- the real one covers. Alterac's explored piece 5039 (area 279 Dalaran, 426 x 461 at 0, 207) prints a DALARAN banner
  -- across the city's south, piece 5045 (area 278, 454 x 221 at 0, 447) its right half faintly: the ring covers the
  -- middle, the rects the scroll ends (the left end is printed only by 5039), and the name comes back as a label.
  dal = {
    id = -279, name = "Dalaran", home = 1416, inst = 0,
    art = { m = 0, r = { -533.3333, -533.3333, 1066.6667, 1066.6667 }, lw = 1536, lh = 1536, tw = 512, th = 512,
      t = { 204395, 204435, 204475, 204396, 204436, 204476, 204397, 204437, 204477 } },
    mask = "Interface\\AddOns\\AzerothUnrolled\\Masks\\dal_ring.tga", nz = { 338, 446, 1024, 1156 },
    cover = { explored = true, rects = {
      { dst = { 28, 482, 74, 530 }, src = { 40, 534 }, feather = 8, pieces = { { 0, 207, 426, 461 } } },
      { dst = { 234, 482, 308, 530 }, src = { 70, 559 }, feather = 8, pieces = { { 0, 207, 426, 461 }, { 0, 447, 454, 221 } } } } },
    label = { wx = 244.57, wy = 356.55, ar = 279, n = "Dalaran" },
  },
}
