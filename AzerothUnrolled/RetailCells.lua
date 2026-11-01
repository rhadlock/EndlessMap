--[[
Endless Map - RetailCells.lua (1.4.0-beta2; retail only: AzerothUnrolled_Standard.toc, after RetailCellData.lua and
RetailSpace.lua, before RetailRender.lua)

The zone cells of retail (docs/retail-engine.md 11.5, "Zones much earlier"): WoW Forever's mosaic on Kalimdor, the
Eastern Kingdoms and Quel'Thalas. Every zone in view is drawn from far out as its CELL - its picture cut by a mask of
its own land (Masks/Retail/z<uiMapID>.tga, RetailCellData.lua: tools/retail/build_cells.py partitions each continent by
Blizzard's own zone shapes, the highlight images, as tools/zonemasks/partition.js does for WoW Forever) - so a zone's
picture never lays its blank parchment over its neighbours. The cells switch on with the engine's 0.3 s crossfade at ONE
zoom of the world (1.4.0-beta13: BAND_WORLD, 5.4x - WoW Forever's LOD_C0 on Kalimdor and the Eastern Kingdoms -, every map:
C.Band, BandOn), 4% lower off, loaded from 0.8 of it (Forever's LOD_PREFETCH), and in together once all in view are loaded
(RetailRender.lua PlanAlphas). (1.4.0-beta4) No
zone's whole picture comes over its cell or its patch - a city, a capital or a nested zone is its patch (RetailRender.lua
Whole). A nested zone (a capital, a starting area) stays in its home's cell below its own
switch, as on WoW Forever.
Each cell carries the zone's explored pieces through the same mask (Forever's layer 3). (1.4.0-beta3) Every continent and
world has its cells, with WoW Forever's soft edges and sea (tools/retail/build_cells.py); a nested zone's or open-world
city's PATCH (RetailCellData.lua pt = 1: the land no other picture draws but by its frame, a capital's footprint, a city's
own zone shape) is listed after the cells - drawn over them - and switches on only with its city (`on`: its map's zoom at a
view 3,193 yards wide, WoW Forever's city switch, design rule 6).
This file gives RetailRender.lua the cells of a continent as entries of their own (kind "cell", cellOf = the zone; the
zone's rect, id and art by the zone's entry) and their band; RetailRender.lua plans, loads and draws them as any
picture. A cell draws only while its zone is the map's shown member and the client gives the zone the art the mask was
made for (its first tile: RetailCellData.lua f1; (1.4.0-beta6) or another phase's art of its size, f1s - Silithus
after the sword: the cell is the zone's cut of the map's land, whatever its picture shows there).
(1.4.0-beta3, WoW Forever parity - docs/retail-engine.md 13) A zone that has its cell drawn never lays its whole picture
over the mosaic (C.Celled: Render.lua's WholePicture, design rule 10) - so its cell comes in no later than its whole
picture did (ZONE_ON of its own fit: Zuldazar at Zandalar's 1.36, Gorgrond at Draenor's 2.34); and the cells of one
band of a continent share ONE switch (C.BandKey: RetailRender.lua's bands) - WoW Forever's cell is its continent's lod,
whatever the screen: a drag brings a cell into the view at the alpha of the rest.
(1.4.0-beta4, the data) A STAND-IN (RetailCellData.lua si): a map placed on this one that only some characters see -
Quel'Thalas 2537 on the Eastern Kingdoms (tools/retail/corrections.py ART_STANDIN) -: its own picture through its land
mask and its zones' cells and patches, listed again in this map's list and drawn there only while the game hides that
map from the character: the Eastern Kingdoms' picture
draws Midnight's Quel'Thalas for everyone, and a character on the old Quel'Thalas saw its north as the continent's blobs
at every zoom (68.webp). It is banded by this map's zoom (bandOf) and never its zone's own cell (Celled): the map, its
labels, focus and Blizzard's map stay hidden (RetailSpace.lua Phases) - the phase decides which maps are places, never
which land gets art.
]]
local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)
if ns.FLAVOR ~= "retail" then return end

local DATA = ns.RETAIL_CELLS
if type(DATA) ~= "table" then return end

local C = {}
ns.RetailCells = C

local CELL_ON, CELL_OFF, CELL_LOAD = 2.5, 2.4, 2.0
-- (a patch's art density rule - C.Band: a 1002-px picture's 12 tiles at 0.15 screen px per art px, a 3840-px picture's 150
-- at 0.25 - docs/retail-engine.md section 5 rule 2)
local DENSE_SMALL, DENSE_BIG = 0.15, 0.25
-- ((1.4.0-beta13) The zoom of the world every map's zones come in at - on the readout one number on every continent;
-- (1.4.0-beta14) every map: the worlds' too, every inset's - RetailRender.lua's picture levels)
local BAND_WORLD = 5.4
C.BAND_WORLD = BAND_WORLD
-- (1.4.0-beta3) a zone's map is in by this of its own fit: where a zone is that large at BAND_WORLD - the worlds' zones on
-- a world as small as a continent, Outland's, Draenor's, the Shadowlands' - its map comes before it fills the view
local ZONE_ON = 0.84
C.ON, C.OFF, C.LOAD = CELL_ON, CELL_OFF, CELL_LOAD

local lists = {}   -- [continent entry] = { its cell entries }
local meta = {}    -- [zone entry] = the metatable of its cell entry
local cellOf = {}  -- (1.4.0-beta3) [zone entry] = its cell entry (not a patch)
local patchOf = {} -- ((1.4.0-beta4's fixes) [zone entry] = its patch entry - a city's, a nested zone's: the prefetch)

-- (1.4.0-beta3, the city maps - docs/retail-places.md 2) ((1.4.0-beta13) Every city of RetailPlaces.lua that the tree
-- places on map cont: 1.4.0-beta3 - 1.4.0-beta12 only those RetailCellData.lua has no row for - the Dalarans, Oribos, Boralus,
-- Dazar'alor, Valdrakken, Dornogal, the floors -; the others drew that row's patch - "the land no other picture draws" -, and
-- where the home's cell had all of it, nothing: Silvermoon City's held 0.0% of its map, the City of Threads' 5.5%, the home's
-- drawing of the city stayed at every zoom - the player on 1.4.0-beta12, "silvermoon vity map is still wrong"; one source
-- for every city now): their cut-out (Masks\Retail\Cities\: the city plus the land of its picture no cell covers, inside
-- WoW Forever's soft patch frame, its banners left out) as a patch of its own, switching on with its city - at a view
-- CITY_YARDS wide (its continent's yards over them: the continent's zoom there).
local CITY_YARDS = 3193
-- ((1.4.0-beta3, the reviews of 1.4.0-beta3) A city whose home prints a large icon of it round its place - the
-- Shadowlands' Oribos tower and its ORIBOS title, some 2 x 4 times the city: zooming in, that tower filled the screen
-- magnified 10 - 20 times, the city a small disc in it under a huge "O" (d3_oribos, b3_oribosout). From the city's switch
-- the icon is covered by the home's own plain mist: d - the cover, in the home's layer px - shows the home's picture's
-- plain piece s repeated at k times its size, mirrored every other time (no seam), through m - the icon's own shape, grown
-- and feathered -, under the city's patch and switching with it (its band). Made by tools/retail/build_covers.py from the
-- home's art (docs/retail-places.md "The home's cover"); WoW Forever painted its capitals' banners over with copies of
-- plain art the same way (tools/history/v3.6.2/patchmasks.py COVERS).
local HOME_COVERS = {
    [1670] = { home = 1550, d = { 1602, 918, 2327, 1573 }, s = { 1950, 1050, 2230, 1200 }, k = 1.6, -- Oribos on the Shadowlands
        m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Cities\\1670h.tga" },
    -- ((1.4.0-beta14) A home's printed name of its city, half under the city's map - TH and UFF beside Thunder Bluff, AKKEN beside
    -- Valdrakken -, WoW Forever's BuildHomeCover: its own art made anew over rect d, through its name's own shape, under the city's patch and
    -- switching with it, while the explored piece that prints it shows (pieces: their offsets on the home's picture). The data:
    -- tools/retail/corrections.py NAME_COVERS, tools/retail/build_name_covers.py)
    [87] = { home = 27, d = { 456, 110, 790, 178 }, t = { { 456, 110, 712, 178, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\27_n87_1.blp" }, { 712, 110, 790, 178, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\27_n87_2.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\27_n87.tga", pieces = { { 398, 0 } } },
    [88] = { home = 7, d = { 238, 154, 575, 224 }, t = { { 238, 154, 494, 224, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\7_n88_1.blp" }, { 494, 154, 575, 224, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\7_n88_2.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\7_n88.tga", pieces = { { 448, 101 }, { 208, 62 } } },
    [90] = { home = 18, d = { 454, 496, 792, 564 }, t = { { 454, 496, 710, 564, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\18_n90_1.blp" }, { 710, 496, 792, 564, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\18_n90_2.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\18_n90.tga", pieces = { { 423, 359 } } },
    [111] = { home = 108, d = { 111, 216, 411, 264 }, t = { { 111, 216, 367, 264, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\108_n111_1.blp" }, { 367, 216, 411, 264, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\108_n111_2.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\108_n111.tga", pieces = { { 143, 171 }, { 104, 4 } } },
    [622] = { home = 588, d = { 417, 549, 523, 572 }, t = { { 417, 549, 523, 572, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\588_n622_1.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\588_n622.tga" },
    [624] = { home = 588, d = { 481, 103, 561, 126 }, t = { { 481, 103, 561, 126, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\588_n624_1.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\588_n624.tga" },
    [1161] = { home = 895, d = { 2256, 938, 2584, 1017 }, t = { { 2256, 938, 2512, 1017, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\895_n1161_1.blp" }, { 2512, 938, 2584, 1017, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\895_n1161_2.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\895_n1161.tga", pieces = { { 2117, 332 } } },
    [1165] = { home = 862, d = { 1991, 1108, 2424, 1187 }, t = { { 1991, 1108, 2247, 1187, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\862_n1165_1.blp" }, { 2247, 1108, 2424, 1187, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\862_n1165_2.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\862_n1165.tga", pieces = { { 1815, 260 }, { 1312, 82 } } },
    [2112] = { home = 2025, d = { 1020, 1355, 1470, 1439 }, t = { { 1020, 1355, 1276, 1439, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\2025_n2112_1.blp" }, { 1276, 1355, 1470, 1439, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\2025_n2112_2.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\2025_n2112.tga", pieces = { { 835, 952 } } },
    [2339] = { home = 2248, d = { 1582, 1309, 1953, 1384 }, t = { { 1582, 1309, 1838, 1384, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\2248_n2339_1.blp" }, { 1838, 1309, 1953, 1384, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\2248_n2339_2.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\2248_n2339.tga", pieces = { { 967, 558 } } },
}
C.HOME_COVERS = HOME_COVERS
-- ((1.4.0-beta4's fixes, the reviews of 1.4.0-beta4: "printed titles, compass roses, margins and banners still show") A
-- picture's own printed marks the view would show on their own - the Cosmic map's world ribbons beside each world's own
-- picture (at a world's fit the Cosmic map round it showed its ribbon magnified: OUTLAND over "...TLAND", a giant
-- DRAENOR), the Eastern Kingdoms' compass rose and squid and Kalimdor's sea serpent in their own sea past Azeroth's edge,
-- Draenor's compass rose - painted over with that picture's own texture made anew without them (tools/retail/
-- build_covers.py --pictures: the picture round the mark quilted into its place, 256-px DXT1 tiles t over the rect d in
-- the picture's layer px), through a mask over d (m: the mark's shape or a soft rect, times the picture's own alpha
-- there); WoW Forever paints its capitals' banners over the same way (tools/history/v3.6.2/patchmasks.py COVERS). Drawn
-- right over their picture, under its cells, with it - or (child) in step with that map's switch, as WoW Forever's
-- banner covers come with their city. A continent's covers are cut out of its land mask (tools/retail/build_masks.py), so
-- over its fading sea past its world the cover replaces it exactly. ((1.4.0-beta9) Or (cells) with its cells, over its land
-- mask as it is - the Eastern Kingdoms' printed name, its letters' own shape: from their switch the zones' maps are the
-- land, and its KI between Dun Morogh's and Elwynn Forest's pictures, its A and MS out on the sea stood alone - 98.webp.)
-- The data: tools/retail/corrections.py PICTURE_COVERS
local PICTURE_COVERS = {
    [946] = { -- the Cosmic map: the worlds' ribbons, each with its world
        { d = { 0, 190, 380, 307 }, t = { { 0, 190, 256, 307, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\946_shadowlands_1.blp" }, { 256, 190, 380, 307, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\946_shadowlands_2.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\946_shadowlands.tga", child = 1550 }, -- shadowlands
        { d = { 0, 520, 400, 650 }, t = { { 0, 520, 256, 650, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\946_outland_1.blp" }, { 256, 520, 400, 650, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\946_outland_2.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\946_outland.tga", child = 101 }, -- outland
        { d = { 315, 385, 715, 503 }, t = { { 315, 385, 571, 503, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\946_azeroth_1.blp" }, { 571, 385, 715, 503, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\946_azeroth_2.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\946_azeroth.tga", child = 947 }, -- azeroth
        { d = { 645, 265, 1002, 375 }, t = { { 645, 265, 901, 375, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\946_draenor_1.blp" }, { 901, 265, 1002, 375, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\946_draenor_2.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\946_draenor.tga", child = 572 }, -- draenor
    },
    [13] = { -- the Eastern Kingdoms
        { d = { 3190, 310, 3545, 665 }, t = { { 3190, 310, 3446, 566, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_rose_1.blp" }, { 3446, 310, 3545, 566, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_rose_2.blp" }, { 3190, 566, 3446, 665, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_rose_3.blp" }, { 3446, 566, 3545, 665, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_rose_4.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_rose.tga" }, -- rose
        { d = { 2530, 1950, 2925, 2235 }, t = { { 2530, 1950, 2786, 2206, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_squid_1.blp" }, { 2786, 1950, 2925, 2206, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_squid_2.blp" }, { 2530, 2206, 2786, 2235, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_squid_3.blp" }, { 2786, 2206, 2925, 2235, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_squid_4.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_squid.tga" }, -- squid
        { d = { 1340, 1560, 2400, 1880 }, t = { { 1340, 1560, 1596, 1816, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_title_1.blp" }, { 1596, 1560, 1852, 1816, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_title_2.blp" }, { 1852, 1560, 2108, 1816, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_title_3.blp" }, { 2108, 1560, 2364, 1816, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_title_4.blp" }, { 2364, 1560, 2400, 1816, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_title_5.blp" }, { 1340, 1816, 1596, 1880, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_title_6.blp" }, { 1596, 1816, 1852, 1880, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_title_7.blp" }, { 1852, 1816, 2108, 1880, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_title_8.blp" }, { 2108, 1816, 2364, 1880, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_title_9.blp" }, { 2364, 1816, 2400, 1880, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_title_10.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\13_title.tga" }, -- title
    },
    [12] = { -- Kalimdor
        { d = { 215, 1310, 860, 1555 }, t = { { 215, 1310, 471, 1555, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\12_serpent_1.blp" }, { 471, 1310, 727, 1555, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\12_serpent_2.blp" }, { 727, 1310, 860, 1555, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\12_serpent_3.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\12_serpent.tga" }, -- serpent
    },
    [572] = { -- Draenor
        { d = { 812, 60, 938, 192 }, t = { { 812, 60, 938, 192, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\572_rose_1.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\572_rose.tga" }, -- rose
    },
    [1978] = { -- ((1.4.0-beta14) a continent's printed zone names its coast cuts, with the zones' maps: THE WAKI, THE EMER)
        { d = { 1530, 470, 2360, 670 }, t = { { 1530, 470, 1786, 670, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\1978_l_waking_1.blp" }, { 1786, 470, 2042, 670, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\1978_l_waking_2.blp" }, { 2042, 470, 2298, 670, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\1978_l_waking_3.blp" }, { 2298, 470, 2360, 670, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\1978_l_waking_4.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\1978_l_waking.tga", cells = true }, -- l_waking
        { d = { 975, 1145, 1410, 1350 }, t = { { 975, 1145, 1231, 1350, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\1978_l_emerald_1.blp" }, { 1231, 1145, 1410, 1350, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\1978_l_emerald_2.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\1978_l_emerald.tga", cells = true }, -- l_emerald
        { d = { 315, 1690, 955, 1800 }, t = { { 315, 1690, 571, 1800, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\1978_l_amirdrassil_1.blp" }, { 571, 1690, 827, 1800, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\1978_l_amirdrassil_2.blp" }, { 827, 1690, 955, 1800, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\1978_l_amirdrassil_3.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\1978_l_amirdrassil.tga", cells = true }, -- l_amirdrassil
        { d = { 2360, 1355, 3065, 1495 }, t = { { 2360, 1355, 2616, 1495, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\1978_l_thaldraszus_1.blp" }, { 2616, 1355, 2872, 1495, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\1978_l_thaldraszus_2.blp" }, { 2872, 1355, 3065, 1495, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\1978_l_thaldraszus_3.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\1978_l_thaldraszus.tga", cells = true }, -- l_thaldraszus
    },
    [876] = {
        { d = { 310, 585, 900, 715 }, t = { { 310, 585, 566, 715, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\876_l_mechagon_1.blp" }, { 566, 585, 822, 715, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\876_l_mechagon_2.blp" }, { 822, 585, 900, 715, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\876_l_mechagon_3.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\876_l_mechagon.tga", cells = true }, -- l_mechagon
    },
    [2537] = {
        { d = { 2790, 1180, 3410, 1380 }, t = { { 2790, 1180, 3046, 1380, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\2537_l_coiled_1.blp" }, { 3046, 1180, 3302, 1380, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\2537_l_coiled_2.blp" }, { 3302, 1180, 3410, 1380, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\2537_l_coiled_3.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\2537_l_coiled.tga", cells = true }, -- l_coiled
        { d = { 340, 1280, 960, 1480 }, t = { { 340, 1280, 596, 1480, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\2537_l_eversong_1.blp" }, { 596, 1280, 852, 1480, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\2537_l_eversong_2.blp" }, { 852, 1280, 960, 1480, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\2537_l_eversong_3.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\2537_l_eversong.tga", cells = true }, -- l_eversong
    },
    [2274] = {
        { d = { 2430, 1140, 2910, 1355 }, t = { { 2430, 1140, 2686, 1355, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\2274_l_ringing_1.blp" }, { 2686, 1140, 2910, 1355, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\2274_l_ringing_2.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\2274_l_ringing.tga", cells = true }, -- l_ringing
    },
    [619] = {
        { d = { 595, 380, 780, 440 }, t = { { 595, 380, 780, 440, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\619_l_shore_1.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\619_l_shore.tga", cells = true }, -- l_shore
        { d = { 545, 175, 715, 210 }, t = { { 545, 175, 715, 210, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\619_l_stormheim_1.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\619_l_stormheim.tga", cells = true }, -- l_stormheim
    },
    [947] = { -- ((1.4.0-beta7) Azeroth: its drawing of the Maelstrom - the swirl - with the portal's switch, its places over its sea)
        { d = { 1400, 850, 2140, 1560 }, t = { { 1400, 850, 1656, 1106, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_maelstrom_1.blp" }, { 1656, 850, 1912, 1106, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_maelstrom_2.blp" }, { 1912, 850, 2140, 1106, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_maelstrom_3.blp" }, { 1400, 1106, 1656, 1362, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_maelstrom_4.blp" }, { 1656, 1106, 1912, 1362, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_maelstrom_5.blp" }, { 1912, 1106, 2140, 1362, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_maelstrom_6.blp" }, { 1400, 1362, 1656, 1560, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_maelstrom_7.blp" }, { 1656, 1362, 1912, 1560, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_maelstrom_8.blp" }, { 1912, 1362, 2140, 1560, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_maelstrom_9.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_maelstrom.tga", child = 948 }, -- maelstrom
        { d = { 380, 1270, 1060, 1390 }, t = { { 380, 1270, 636, 1390, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_kalimdor_1.blp" }, { 636, 1270, 892, 1390, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_kalimdor_2.blp" }, { 892, 1270, 1060, 1390, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_kalimdor_3.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_kalimdor.tga", child = 12 }, -- n_kalimdor
        { d = { 2990, 1536, 3740, 1770 }, t = { { 2990, 1536, 3246, 1770, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_kingdoms_1.blp" }, { 3246, 1536, 3502, 1770, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_kingdoms_2.blp" }, { 3502, 1536, 3740, 1770, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_kingdoms_3.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_kingdoms.tga", child = 13 }, -- n_kingdoms
        { d = { 1520, 300, 2280, 420 }, t = { { 1520, 300, 1776, 420, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_northrend_1.blp" }, { 1776, 300, 2032, 420, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_northrend_2.blp" }, { 2032, 300, 2280, 420, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_northrend_3.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_northrend.tga", child = 113 }, -- n_northrend
        { d = { 2940, 320, 3480, 560 }, t = { { 2940, 320, 3196, 560, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_dragon_1.blp" }, { 3196, 320, 3452, 560, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_dragon_2.blp" }, { 3452, 320, 3480, 560, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_dragon_3.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_dragon.tga", child = 1978 }, -- n_dragon
        { d = { 1880, 770, 2390, 1000 }, t = { { 1880, 770, 2136, 1000, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_broken_1.blp" }, { 2136, 770, 2390, 1000, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_broken_2.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_broken.tga", child = 619 }, -- n_broken
        { d = { 2546, 980, 2980, 1210 }, t = { { 2546, 980, 2802, 1210, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_kultiras_1.blp" }, { 2802, 980, 2980, 1210, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_kultiras_2.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_kultiras.tga", child = 876 }, -- n_kultiras
        { d = { 1820, 1570, 2500, 1690 }, t = { { 1820, 1570, 2076, 1690, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_zandalar_1.blp" }, { 2076, 1570, 2332, 1690, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_zandalar_2.blp" }, { 2332, 1570, 2500, 1690, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_zandalar_3.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_zandalar.tga", child = 875 }, -- n_zandalar
        { d = { 1530, 2016, 2180, 2136 }, t = { { 1530, 2016, 1786, 2136, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_pandaria_1.blp" }, { 1786, 2016, 2042, 2136, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_pandaria_2.blp" }, { 2042, 2016, 2180, 2136, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_pandaria_3.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_pandaria.tga", child = 424 }, -- n_pandaria
        { d = { 750, 2180, 1310, 2410 }, t = { { 750, 2180, 1006, 2410, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_khazalgar_1.blp" }, { 1006, 2180, 1262, 2410, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_khazalgar_2.blp" }, { 1262, 2180, 1310, 2410, "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_khazalgar_3.blp" } }, m = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Covers\\947_n_khazalgar.tga", child = 2274 }, -- n_khazalgar
    },
}
C.PICTURE_COVERS = PICTURE_COVERS
local function CityPatches(cont, list)
    local P = ns.RETAIL_PLACES
    if not (P and P.city) then return end
    local have, ids = {}, {}
    for _, c in ipairs(DATA[cont.id] or {}) do
        if not c.pt then have[c.id] = true end
    end
    for id in pairs(P.city) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local c, z = P.city[id], ns.maps[id]
        if c.m and not have[id] and z and z.pe == cont and z.kind == "zone" and z.yw and z.x1 > z.x0 then
            local yards = z.yw * (cont.x1 - cont.x0) / (z.x1 - z.x0)
            local cv = HOME_COVERS[id]
            local hm = cv and ns.maps[cv.home]
            if hm and (hm == cont or hm.pe == cont) then
                -- (the home's cover, under the patch: an entry of the home itself - (1.4.0-beta14) a zone of this map too -, its band the
                -- city's in this map's zoom)
                local row = { id = hm.id, city = id, m = cv.m, pt = 1, on = yards / CITY_YARDS, cover = cv, places = true }
                meta[hm] = meta[hm] or { __index = hm }
                list[#list + 1] = setmetatable({ kind = "cell", cellOf = hm, bandOf = cont, cell = row, link = false, home = false }, meta[hm])
            end
            meta[z] = meta[z] or { __index = z }
            if type(c.cv) == "table" and c.cv.m and c.cv.fy and c.cv.nz then
                -- ((1.4.0-beta3, the reviews of 1.4.0-beta3) the city's own cover (docs/retail-places.md "Covers": Oribos's
                -- ORIBOS banner bites its outer ring) - its art mirrored about cv.fy where the mirror meets the bite cv.nz,
                -- through cv.m, just under its patch; not drawn before, the ring's notch showed the home under it)
                local cr = { id = id, m = c.cv.m, art = c.art, f1 = c.f1, pt = 1, on = yards / CITY_YARDS, citycover = c.cv, places = true }
                list[#list + 1] = setmetatable({ kind = "cell", cellOf = z, cell = cr, link = false, home = false }, meta[z])
            end
            local row = { id = id, m = c.m, nz = c.nz, art = c.art, f1 = c.f1, pt = 1, on = yards / CITY_YARDS, places = true }
            local pe = setmetatable({ kind = "cell", cellOf = z, cell = row, link = false, home = false }, meta[z])
            list[#list + 1] = pe
            patchOf[z] = pe
        end
    end
end

-- ((1.4.0-beta3) RetailRender.lua: a cover's items - the home's tiles under its piece s, each laid over its share of d,
-- in the home's layer px: { x0, y0, x1, y1, u1, v1, file, sub, u0, v0 } - RetailTiles.lua's list items; a city's own
-- cover: its tiles whose mirror about fy meets the bite nz, mirrored - v from 1 down to 0)
function C.CoverItems(e)
    local cv = e.cell.cover or e.cell.citycover
    if cv.items then return cv.items end
    if cv.t then
        -- ((1.4.0-beta4's fixes) a picture cover: its own tiles over d, each 256 px from its top left)
        local items = {}
        for _, t in ipairs(cv.t) do
            items[#items + 1] = { t[1], t[2], t[3], t[4], (t[3] - t[1]) / 256, (t[4] - t[2]) / 256, t[5], 0 }
        end
        cv.items = items
        return items
    end
    local TL = ns.RetailTiles
    local L = TL and TL.Layout(e.cellOf.id)
    if not L then return nil end
    if e.cell.citycover then
        local items, fy, nz = {}, cv.fy * L.lh / 668, cv.nz
        local kx, ky = L.lw / 1002, L.lh / 668
        for r = 1, L.rows do
            for c = 1, L.cols do
                local x0, y0 = (c - 1) * L.tw, (r - 1) * L.th
                local w, h = math.min(L.tw, L.lw - x0), math.min(L.th, L.lh - y0)
                local my0, my1 = 2 * fy - (y0 + h), 2 * fy - y0
                local file = L.files[(r - 1) * L.cols + c]
                if file and file ~= 0 and x0 < nz[3] * kx and x0 + w > nz[1] * kx and my0 < nz[4] * ky and my1 > nz[2] * ky then
                    items[#items + 1] = { x0, my0, x0 + w, my1, w / L.tw, -h / L.th, file, 0, 0, h / L.th }
                end
            end
        end
        cv.items = items
        return items
    end
    local d, s, items = cv.d, cv.s, {}
    local z = cv.k or 1 -- (each copy this many times its piece's size: fewer, larger copies - less of a pattern)
    local sw, sh = (s[3] - s[1]) * z, (s[4] - s[2]) * z
    -- (one axis of a copy: the piece a0..a1 of s - its tile from t0, tw wide - laid at copy k from d0, z times its size,
    -- mirrored when k is odd, clipped to d1: the laid span and its texcoords at either end)
    local function Span(a0, a1, t0, tw, s0, s1, k, d0, d1)
        local c0 = d0 + k * (s1 - s0) * z
        local x0, x1, u0, u1
        if k % 2 == 0 then
            x0, x1 = c0 + (a0 - s0) * z, c0 + (a1 - s0) * z
            u0, u1 = (a0 - t0) / tw, (a1 - t0) / tw
        else
            x0, x1 = c0 + (s1 - a1) * z, c0 + (s1 - a0) * z
            u0, u1 = (a1 - t0) / tw, (a0 - t0) / tw
        end
        local cx0, cx1 = math.max(x0, d0), math.min(x1, d1)
        if cx1 <= cx0 then return nil end
        local k0, k1 = (cx0 - x0) / (x1 - x0), (cx1 - x0) / (x1 - x0)
        return cx0, cx1, u0 + (u1 - u0) * k0, u0 + (u1 - u0) * k1
    end
    for r = 1, L.rows do
        for c = 1, L.cols do
            local tx0, ty0 = (c - 1) * L.tw, (r - 1) * L.th
            local a0, b0 = math.max(tx0, s[1]), math.max(ty0, s[2])
            local a1, b1 = math.min(tx0 + L.tw, s[3]), math.min(ty0 + L.th, s[4])
            local file = L.files[(r - 1) * L.cols + c]
            if a1 > a0 and b1 > b0 and file and file ~= 0 then
                for j = 0, math.ceil((d[4] - d[2]) / sh) - 1 do
                    local y0, y1, v0, v1 = Span(b0, b1, ty0, L.th, s[2], s[4], j, d[2], d[4])
                    for i = 0, y0 and (math.ceil((d[3] - d[1]) / sw) - 1) or -1 do
                        local x0, x1, u0, u1 = Span(a0, a1, tx0, L.tw, s[1], s[3], i, d[1], d[3])
                        if x0 then items[#items + 1] = { x0, y0, x1, y1, u1 - u0, v1 - v0, file, 0, u0, v0 } end
                    end
                end
            end
        end
    end
    cv.items = items
    return items
end

local function Entries(cont)
    local list = lists[cont]
    if list then return list end
    list = {}
    -- ((1.4.0-beta4's fixes) its picture covers first: right over its picture, under its cells)
    for _, cv in ipairs(PICTURE_COVERS[cont.id] or {}) do
        meta[cont] = meta[cont] or { __index = cont }
        local row = { id = cont.id, m = cv.m, cover = cv, picture = true }
        list[#list + 1] = setmetatable({ kind = "cell", cellOf = cont, bandOf = cont, cell = row, link = false, home = false }, meta[cont])
    end
    local PL = ns.RETAIL_PLACES
    for _, c in ipairs(DATA[cont.id] or {}) do
        local z = ns.maps[c.id]
        -- ((1.4.0-beta4) a stand-in: map si placed on this one - its own picture, a zone of it - banded by this map, never
        -- its zone's cell)
        local s = c.si and ns.maps[c.si]
        local sp = s and z == s and s.pe == cont
        -- ((1.4.0-beta13) a city's patch is its places' cut-out: CityPatches)
        local city = c.pt and not s and PL and PL.city and PL.city[c.id] and PL.city[c.id].m
        if not city and z and (sp or (z.kind == "zone" and (z.pe == cont or (s and s.pe == cont and z.pe == s)))) then
            meta[z] = meta[z] or { __index = z }
            local ce = setmetatable({ kind = "cell", cellOf = z, cell = c, link = false, home = false, bandOf = s and cont or nil }, meta[z])
            list[#list + 1] = ce
            if not c.pt and not s then cellOf[z] = ce end
            if c.pt and not s then patchOf[z] = ce end
        end
    end
    CityPatches(cont, list)
    lists[cont] = list
    return list
end

-- (is cell entry ce drawn now: its zone the shown member, with the art its mask was made for - (1.4.0-beta6) or another
-- phase's art of its size, RetailCellData.lua f1s: the cell is the zone's cut of its map's land, whatever its picture
-- shows there. 1.4.0-beta5 waited for the one art: the player's Silithus after the sword drew nothing at any zoom)
local function Draws(ce)
    local z = ce.cellOf
    if ce.cell.si then
        -- ((1.4.0-beta4) a stand-in: only while the game hides its map - its zones then hidden with it)
        local s = ns.maps[ce.cell.si]
        if not (s and s.visibleNow == false) then return false end
    elseif z.visibleNow == false then
        return false
    end
    if ce.cell.cover then
        -- ((1.4.0-beta3) a home's cover: with its home - any floor of the city; (1.4.0-beta14) a printed name: while what prints it shows)
        local ps = ce.cell.cover.pieces
        if not ps then return true end
        local TL = ns.RetailTiles
        local L = TL and TL.Layout(z.id)
        local P = L and TL.Pieces(z.id, L)
        if ce.cell.cover.of ~= P then
            ce.cell.cover.of, ce.cell.cover.printed = P, false
            for _, it in ipairs(P or {}) do
                for _, o in ipairs(ps) do
                    if it[1] == o[1] and it[2] == o[2] then ce.cell.cover.printed = true end
                end
            end
        end
        return ce.cell.cover.printed
    end
    local TL = ns.RetailTiles
    local L = TL and TL.Layout(z.id)
    if L == nil then return false end
    local f = L.files[1]
    if f == ce.cell.f1 then return true end
    local fs = ce.cell.f1s
    if fs then
        for i = 1, #fs do
            if fs[i] == f then return true end
        end
    end
    return false
end

-- (1.4.0-beta3, WoW Forever's WholePicture - Render.lua, design rule 10) Does zone entry z have its cell drawn now - a
-- cell of its own land, not a patch (a capital's or a city's own map comes over its patch whole, at rest Blizzard's
-- map)? Then its whole picture never draws: it would lay its parchment margins over the neighbours' land.
function C.Celled(z)
    if ns.db and ns.db.cells == false then return false end -- ((1.4.0-beta3) /emap cells off: each zone's whole picture)
    local cont = z and z.kind == "zone" and z.pe
    if not (cont and DATA[cont.id]) then return false end
    Entries(cont)
    local ce = cellOf[z]
    return ce ~= nil and Draws(ce)
end
-- (its cell entry - RetailRender.lua's prefetch loads it ahead)
function C.CellEntry(z) return cellOf[z] end

-- ((1.4.0-beta4's fixes) its patch entry - a city's, a capital's, a nested zone's (RetailCellData.lua pt, the places'
-- city patches; the last listed: the places' over the data's) - RetailRender.lua's prefetch loads it ahead. 1.4.0-beta4
-- had C.Patched here - "a zone with a patch is a city plan: its whole picture comes over it" - and drew the Cape of
-- Stranglethorn's and the Echo Isles' banners and frames and the cities' rectangles: no zone's whole picture comes over
-- its patch now (RetailRender.lua Whole).
function C.PatchEntry(z)
    local cont = z and z.kind == "zone" and z.pe
    if not (cont and DATA[cont.id]) then return nil end
    Entries(cont)
    local pe = patchOf[z]
    return (pe and Draws(pe)) and pe or nil
end

-- The cells of entry e that draw now (nil: e has none): its zones shown (a group's member Blizzard's map shows has
-- other art), with the art their masks were made for.
-- ((1.4.0-beta15) kept until what decides it changes: the maps the game shows - RetailSpace.lua's ns.SpaceGen -, the explored pieces, /emap cells; a zone whose art is not read yet
-- is asked again next time. Each map planned asked every cell's art every frame)
local now, nowGen = {}, {}
function C.For(e)
    -- ((1.4.0-beta4's fixes) a picture's covers with it, the cells on or not - /emap cells off draws no cell)
    local cellsOn = not (ns.db and ns.db.cells == false)
    if not ((DATA[e.id] and cellsOn) or PICTURE_COVERS[e.id]) then return nil end
    local TL = ns.RetailTiles
    local gen = (ns.SpaceGen or 0) * 1000000 + (TL and TL.pieceGen or 0) * 2 + (cellsOn and 1 or 0)
    local out = now[e]
    if out and nowGen[e] == gen then return out end
    local list = Entries(e)
    out = out or {}
    now[e] = out
    local n = 0
    local again = false
    for _, ce in ipairs(list) do
        if (cellsOn or ce.cell.picture) then
            if Draws(ce) then
                n = n + 1
                out[n] = ce
            elseif TL and not ce.cell.cover and not TL.Layout(ce.cellOf.id) then
                again = true
            end
        end
    end
    for i = #out, n + 1, -1 do out[i] = nil end
    nowGen[e] = (not again) and gen or nil
    return out
end

-- ((1.4.0-beta9, the player on 1.4.0-beta8: "all zones need to become visable at the same time" - 99.webp, 100.webp:
-- Highmountain's map in at 10.4x of the world, Stormheim's, Val'sharah's and Suramar's still the Broken Isles' drawing
-- there) A zone's cell - its own land - is no band of its own: every zone of a map comes in at ONE zoom, WoW Forever's
-- lod (its LOD_C0, one for a continent). The map whose band it is: the zone's continent - or, for a continent placed on
-- a continent (Quel'Thalas on the Eastern Kingdoms: its zones from 8.0x of the world, the Eastern Kingdoms' from 5.4x),
-- that one: its land, with it (RetailRender.lua PlanNode's continent on a continent)
local function Owner(cont)
    if cont.kind == "cont" and cont.pe and cont.pe.kind == "cont" then return cont.pe end
    return cont
end

-- (map a's zoom over map b's - ns.ZoomOf of each at one view)
local function Ratio(v, a, b)
    return ((a.x1 - a.x0) / (a.lw * ns.FitOf(v, a))) / ((b.x1 - b.x0) / (b.lw * ns.FitOf(v, b)))
end

-- (is cell entry ce a zone's own land - its band its map's one: not a patch, a cover, a stand-in's own picture or a
-- PHASE_LAND zone - each with a switch of its own, C.Band)
local function Land(ce)
    local c = ce.cell
    return not (c.pt or c.cover or c.ph or (c.si and ce.cellOf.id == c.si))
end

-- ((1.4.0-beta9 - 1.4.0-beta11 held a zone back from its map's band while its art there was drawn at under half its dense
-- screen px per art px - JOIN: a 3,840-px map came once about 480 px of the screen wide, so by the window's size: in the
-- player's 697-px window Eversong Woods and Zul'Aman came at 8.3x, the Eastern Plaguelands at 6.4x - the player on
-- 1.4.0-beta11, "how are these inconsistant, it should use the same calls and rutines". (1.4.0-beta12) Every zone of a
-- map's land comes with its band: one rule, the window's size aside; a 3,840-px map is 150 textures there, as Blizzard's
-- own map draws it whole.)

-- ((1.4.0-beta13) Map O's band, in its zoom, to 0.01: BAND_WORLD of the world, whatever the map - one number on the readout.
-- 1.4.0-beta3 - 1.4.0-beta12 worked it out from each map's own zoom: CELL_ON (2.5) of the map or that ZONE_ON, the earlier -
-- Kalimdor at 5.3x of the world, the Eastern Kingdoms at 5.4x, Zandalar at 7.8x, Khaz Algar at 8.1x, Northrend at 8.9x, the
-- Broken Isles at 9.8x: the player on 1.4.0-beta12, "detail maps show up at 5.49 for east kiing and kalamdor, but nothing
-- else. so you are still using mixed code". (1.4.0-beta14) and no exception: 1.4.0-beta13 still came earlier where a zone
-- would fill the view first - Outland 2.7x, Draenor 2.5x, the Shadowlands 3.5x. Their pictures hold the view till then:
-- 3,840 px Outland's and the Shadowlands', about 1:1 there)
local bandOn = {}
local function BandOn(v, O)
    local c = bandOn[O]
    if c and c.W == v.W and c.H == v.H then return c.on end
    local on = ns.ZoomOf(v, O, ns.WidthForZoom(v, ns.maps[ns.WORLD_MAP_ID], BAND_WORLD))
    on = math.floor(on * 100 + 0.5) / 100
    bandOn[O] = { W = v.W, H = v.H, on = on }
    return on
end

-- (RetailRender.lua PlanNode) the band of cell entry e in its continent's zoom (view v, camera width vw): on, off, the
-- zoom it loads from; (1.4.0-beta3) a patch not before its city's switch (RetailCellData.lua on); (1.4.0-beta9) a zone's
-- cell at its map's band - BandOn (1.4.0-beta12: every land zone of the map with it) - and the band's key
local function BandOf(v, e)
    -- ((1.4.0-beta4's fixes) a picture cover: with its picture - or its child's switch, RetailRender.lua; (1.4.0-beta9) or with
    -- its cells - PICTURE_COVERS cells: their band)
    if e.cell.picture and not e.cell.cover.cells then return 0, -1, 0 end
    if e.cell.cover and not e.cell.picture then
        -- ((1.4.0-beta3) a home's cover: its city's switch, in the home's zoom - the city's patch's band)
        local on = math.floor(math.max(CELL_ON, e.cell.on) * 100 + 0.5) / 100
        return on, on - (CELL_ON - CELL_OFF) * math.min(1, on / CELL_ON), on * CELL_LOAD / CELL_ON
    end
    local z, cont = e.cellOf, e.bandOf or e.cellOf.pe -- ((1.4.0-beta4) a stand-in: by the map it stands in on)
    if e.cell.si and z.id == e.cell.si then
        -- ((1.4.0-beta4's fixes) a stand-in's own picture - Quel'Thalas's through its land mask on the Eastern Kingdoms for
        -- a character on the old Quel'Thalas: that continent's land, with it from its switch, as the map itself is for a
        -- Midnight character - RetailRender.lua PlanNode's continent on a continent)
        return 0, -1, 0
    end
    if e.cell.ph and not e.cell.pt then
        -- ((1.4.0-beta8) a zone of tools/retail/corrections.py PHASE_LAND - the old Quel'Thalas's Eversong Woods, Ghostlands
        -- and Isle of Quel'Danas for a character the game shows them to: that character's land there, with the continent
        -- from its switch, over the stand-in's - as the stand-in's own picture; its cities' patches at their city switch)
        return 0, -1, 0
    end
    if not e.cell.pt then
        -- ((1.4.0-beta9) a zone's cell - or a picture cover with the cells: its map's band, in its continent's zoom, its off
        -- and load in the band's map's)
        local O = Owner(cont)
        local on = BandOn(v, O)
        local r = (O == cont) and 1 or Ratio(v, cont, O)
        -- (its key: the band's map and its switch zoom there - RetailRender.lua keeps one switch a band)
        return on * r, (on - (CELL_ON - CELL_OFF) * math.min(1, on / CELL_ON)) * r, on * CELL_LOAD / CELL_ON * r, O.id .. "@" .. on
    end
    -- ((1.4.0-beta3, the reviews of 1.4.0-beta3) a patch at its city's switch alone - design rule 6, one switch for every
    -- city: the art-density rule held a 3,840-px city map's patch to a view 1,937 - 2,781 yd wide - Valdrakken, Dornogal,
    -- Boralus at 0.755 of their own maps, nothing of them at 0.5 or 0.7); else from where its art reaches dense screen px
    -- per art px (Due's rule, no later bound)
    local dense = (z.lw and z.lw > 1100) and DENSE_BIG or DENSE_SMALL
    local on = math.max(CELL_ON, dense / ns.FitOf(v, z) * (cont.x1 - cont.x0) / (z.x1 - z.x0))
    if tonumber(e.cell.on) then on = math.max(CELL_ON, tonumber(e.cell.on)) end
    -- (a band's switch zoom to 0.01: the patches of one city switch share one switch - C.BandKey)
    on = math.floor(on * 100 + 0.5) / 100
    return on, on - (CELL_ON - CELL_OFF) * math.min(1, on / CELL_ON), on * CELL_LOAD / CELL_ON
end

-- ((1.4.0-beta15) kept per view size: nothing of it moves with the camera, and every cell of every map planned asked each frame)
function C.Band(v, e, vw)
    local c = e.bandC
    if c and c.W == v.W and c.H == v.H then return c[1], c[2], c[3], c[4] end
    local on, off, load, key = BandOf(v, e)
    e.bandC = { on, off, load, key, W = v.W, H = v.H }
    return on, off, load, key
end

-- ((1.4.0-beta16) the different bands of e's cells: RetailRender.lua runs them for a map far from the view without walking its cells - a band stands for the zoom alone, and one
-- reset while far would have come back off within its switch's window, the same zoom looking otherwise where the view had been)
local bandLists = {}
function C.BandList(v, e)
    local cells = C.For(e)
    if not cells then return nil end
    local c = bandLists[e]
    if c and c.cells == cells and c.n == #cells and c.gen == nowGen[e] and c.W == v.W and c.H == v.H then return c end
    c = { cells = cells, n = #cells, gen = nowGen[e], W = v.W, H = v.H }
    local seen = {}
    for _, ce in ipairs(cells) do
        if not (ce.cell.picture and ce.cell.cover.child and ns.maps[ce.cell.cover.child]) then
            local con, coff, _, bkey = C.Band(v, ce)
            local key = bkey or C.BandKey(ce, con)
            if not seen[key] then
                seen[key] = true
                c[#c + 1] = { key = key, on = con, off = coff, cell = ce, bp = ce.bandOf or ce.cellOf.pe }
            end
        end
    end
    bandLists[e] = c
    return c
end

-- (1.4.0-beta3) the key of cell entry e's band - its continent and its switch zoom: RetailRender.lua keeps one switch a
-- band, so a cell a drag brings into the view takes the alpha of the band's cells already there (WoW Forever's lod);
-- ((1.4.0-beta9) a zone's cell's, or a cover's with the cells: C.Band's fourth value - its map's band)
local keys = {}
function C.BandKey(e, on)
    local cont = e.bandOf or e.cellOf.pe
    local t = keys[cont]
    if not t then
        t = {}
        keys[cont] = t
    end
    local key = t[on]
    if not key then
        key = cont.id .. "@" .. on
        t[on] = key
    end
    return key
end
