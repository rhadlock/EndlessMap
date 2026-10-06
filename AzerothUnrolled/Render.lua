local _, ns = ...

--[[
Render: our own copy of the world map art, placed at true positions on the
Azeroth map. Nothing here touches Blizzard's canvas.

How WoW Forever's map art is built (verified from the game files):
  * Every map has one BASE picture (1002x668 in 256px tiles). A zone's base
    is parchment in the "unexplored" style, with a decorative frame and
    printed labels, filling the zone's whole rectangle - never transparent.
  * Zones also have OVERLAY pieces (one per subzone) with real transparency,
    shaped like the land. The game shows those you have explored.
  * Continents/Azeroth have no pieces, and no higher-resolution art exists:
    zoomed in, a continent picture gets ~10x blurrier than a zone's.

The "LOD mosaic" we draw (designed and checked with an offline renderer
using the real art), bottom to top:
  0  Azeroth base
  1  the continent you're over (frame cropped, edges feathered)
  2  every zone's CELL: its base picture cut to the zone's cell - one mask
     (ZoneMasks.lua, Masks\<uiMapID>.tga) per zone. The cells of a
     continent tile it (every place belongs to exactly one zone or city, a
     city's cell is cut out of its parent's), so the continent is covered by
     sharp zone art without gaps or overlaps. Only far sea and the odd strip
     of land no zone picture reaches keep the continent art.
     (3.1.0) A capital's cell shows its HOME ZONE's picture (BuildCityFill):
     below the city switch the mosaic is the zone as Blizzard draws it, title
     banner included, wherever the camera is. Above the switch the banner is
     painted over with the zone's own art (ZoneMaskPatches, faded in with the
     switch) and the city's own map lies on top of everything (its patch).
     Fallback (Classic Era, maps without a fitting mask, /unroll cells off):
     the zone's FOOTPRINT, its base picture cut to the union of ALL its
     overlay shapes (one mask per overlay tile).
  3  every zone's explored pieces, whole (not cut to the cell: explored land
     and its labels often reach past the Classic-era zone silhouettes the
     cells come from); with cells, the capital banners in them are painted
     over the same way (above the city switch)
  4  the zone you're looking at: its PICTURE - base (frame cropped,
     feathered), and on the level right above it its explored pieces (the
     picture's "top"). Zones still fading out keep their own two picture
     levels, newest on top.
     (3.2.0) The BASE only for a capital, and for a zone the mosaic cannot
     draw (no fitting cell: Classic Era, cells or mosaic off -
     WholePicture). A zone's map is a rectangle reaching over its
     neighbours (the median zone picture is 29 % other zones' land, drawn
     there as blank parchment with their printed names, and 14 % open sea),
     so with the base on top, zooming in on a zone blanked the land around
     it (user report 2026-10-04). Every other zone keeps its picture's slot,
     fades and top - its explored pieces above the neighbours', as Blizzard
     draws the real map's explored areas over everything at rest - but its
     base is never drawn and never hides what lies under it (FindCovers).
     Every zone's cell now also takes the open sea next to its own coast
     (the 3.2.0 masks), so coasts stay sharp without the base.
Frame alpha multiplies each texture on its own (no group fade: the engine's
frame buffers crash this client), so a picture fading at alpha b would let
its unexplored base tint its explored pieces. The top therefore fades in
faster than the base (TopAlpha), which keeps explored land close to how it
looks before and after the fade.
Zone art (2, 3) fades in while the continent goes from 2.5x to 4x zoom -
exactly when its art turns blurry - so the map stays sharp all the way down.
When the view sits inside a zone (as Blizzard shows it), the picture's
frame ring fades back in, so at rest it looks exactly like Blizzard's map
(3.2.0: only where a base still shows - capitals and the fallback).
At rest Blizzard draws the real map's explored areas over our whole band;
pictures we stack above that map's pieces (a city whose view pokes out of
the city, so its zone is the real map) move just above them (SetRestLift).

City detail (LOD): a capital's own map has 2x (Stormwind) to 6x (Ironforge)
the texels per world unit of its home zone's map. (3.1.0) ONE global switch:
from WORLD zoom 14.05x (ns.WorldZoom: 1.00x = the whole world map fills the
view; Render.CITY_G, /unroll cityzoom) every city's own map replaces the zone's
drawing of it, whatever has the focus and wherever the camera is; below it
(hidden again just under the line, Render.CITY_G_HIDE) the map is Blizzard's
zone drawing with the printed city banner. (/unroll cityzoom off: the rule up to
3.0.1 - from 1.5x of each city's own home zone, off below 1.35x.)
The city's PATCH - its map cut to its zone cell (no rectangle) - lies above
EVERY zone picture (a neighbour's picture never covers a city), right under
the city's own picture. (3.6.2) Where its map holds land no zone cell covers -
Orgrimmar's walls between Azshara's and Durotar's pictures, Stormwind's harbour
west of Elwynn's - the patch takes that too (ZoneMasks patch masks: frame and
emblems left out), so above the switch the city's map shows there, not the
continent's blurry art. It crossfades in time (a zoom-driven fade would
leave a half-blended city on screen wherever the zoom stops), keeping pace
with a zoom that goes well past the switch (a fast wheel spin). The zone's
printed city banner is painted over with the zone's own art in the same
fade (banner covers: in the cells and explored pieces, on the home zone's
picture, and in the patch for Blizzard's own exploration overlay at rest).
A patch near the view (within one view of the screen) is built and loaded
ahead, so a drag or a fling never shows it arriving. The city's own picture
(its whole rectangle, frame ring included) comes with the focus, which a
capital has only while the view lies inside its map (Core FocusZoneAt) - at
rest inside a city it is Blizzard's city map exactly; anywhere else only the
patch shows.

Detail levels (DetailMaps.lua): the same machinery for a place that has no
map of its own in this client - Blackrock Mountain's entrance level, drawn by
Blizzard at 4.1x Burning Steppes' texel density. It is a VIRTUAL map (a
negative id, never a uiMap: never passed to SetMapID or C_Map, never the focus,
not in ns.drawList, so the camera, the real-map hand-over and the depth limits
don't know it), home zone Burning Steppes: switched and crossfaded by
CityFades exactly like a capital (the same world zoom; prefetched from two
thirds of it). It shows only its PATCH: its picture cut to its shape mask (no
rectangle, no frame), with the halls of the level below (Blackrock Depths)
under it, and the home zone's printed name of the place painted over in the
same fade (while the explored piece that prints it shows). The patch goes on
top of every picture while moving - it lies across two zones (Burning Steppes,
Searing Gorge) - and in the rest lift band at rest, over Blizzard's canvas'
explored areas of either zone. Labels.lua puts the icons of its instances on
it (Render:DetailAlpha), Dungeon.lua takes clicks on its bare art
(Render:DetailAt).
Dalaran (2.10.0), WoW Forever's open-world city in Alterac Mountains, is the
second detail level: its art is the client's own Eastern Kingdoms minimap (a
3 x 3 grid of 512 px tiles, 2.68x Alterac's texel density) cut to the barrier
ring and the gate plaza; Alterac's printed DALARAN banner is covered in the
same fade (two rects, each while an explored piece that prints its part shows,
from the zone's explored art) and the name comes back as a label. Same switch,
same place in the stack (above every picture while moving, in the rest lift
band at rest), no entrance (its art takes no clicks), and no depth
confinement: that only comes with the deeper zoom a city's own uiMap allows
(DeepestAt), and Dalaran's 2.68x density is used up at Alterac's own limit
(maxZoom 4x: 1.49 screen px per minimap texel) - unlike Ironforge's 6.23x
(0.64 px per texel at Dun Morogh's limit), there is no deeper detail to zoom
into and keep the view on.
Caves (3.4.0, Caves.lua): more detail levels of this kind - Blizzard's cave maps
of the old world where WoW Forever's cave is the one drawn, each cut to its
footprint in the client's own indoor minimap - switched by their own world zoom
(gate "cave": Render.CAVE_G, Render:SetCaveZoom, /unroll cavezoom; hidden again
0.5% below it, never while the caves are off) instead of the city zoom;
and the tunnels of the Gnomeregan approach (the city zoom, like Blackrock
Mountain), drawn from the client's minimap blocks of their WMO, each turned as
the tunnels lie (Texture:SetRotation), desaturated and tinted over a rock rim
(EmitBlocks).
Every cave (3.5.0, Caves.lua): the open world's caves without a Blizzard map -
about 260: dens, mines, ogre mounds, hives, barrow dens, crypts, tunnels - drawn
as Gnomeregan from their own minimap blocks, by the cave switch. With that many:
a cave is built ahead only near the screen and from 0.9 of its switch (NearScreen,
CAVE_PREFETCH); CityFades considers only the detail levels that show or load; at
most DETAIL_BUILDS_PER_FRAME patches are built in a frame, those on screen
first; no stage visible in a frame is handed to another (BuildVisible); detail
levels stack in a fixed order (larger below); the zoom readout sums up the caves
in view.
A cave's own switch (3.6.0): the lower of the cave switch (Render.CAVE_G: world
zoom 30 since 3.6.2, 52 in 3.6.0) and the deepest zoom the wheel reaches over the
cave (CaveSwitch: Core's depth limit, maxZoom past the deepest map at the cave's
centre - at the default depth less than 30x for 34 caves in 5 zones, from
Winterspring's 25.28x to Mulgore's 29.17x), so every cave shows, at the deepest
zoom over it at most.
The caves around several instance portals (Maraudon, the Scarlet Monastery) and
the Timbermaw Hold tunnels go with the city maps, as Gnomeregan does (Caves.lua:
no gate).
]]

local Render = {}
ns.Render = Render

local LOD_C0, LOD_C1 = 2.5, 4.0     -- continent zoom over which zone art fades in
local LOD_PREFETCH = 2.0            -- start building/loading zone art here
local BASE_Z0, BASE_Z1 = 0.8, 0.97  -- the focused zone's whole picture
local CONT_FADE_W0, CONT_FADE_W1 = 1.05, 1.6
local CONT_CROP, CONT_FEATHER = 24, 40
local ZONE_CROP, ZONE_FEATHER = 24, 60
local EDGE_FEATHER = 32             -- soft zone-rect edge for footprints/pieces
local CORNER_STRIPS = 16            -- feathered corners: strips per corner cell
local PATCH_STRIPS = 4              -- (banner patches: small corners)
local MASK_PIECES = false           -- cut explored pieces to the zone's cell too (see BuildPieces)
local LOAD_FADE = 0.15
local LOAD_TIMEOUT = 2              -- treat art as loaded after this long anyway
local FOCUS_HOLD_MAX = 1            -- max seconds the old focus waits for the new one
local FOCUS_FADE = 0.25             -- crossfade when the focus zone/continent changes
local MAX_STAGES = 24
local FOOT_BUILDS_PER_FRAME = 3
local CELL_BUILDS_PER_FRAME = 8     -- a cell is one mask and a dozen tiles: cheap
local DETAIL_BUILDS_PER_FRAME = 6   -- (3.5.0) detail-level patches (a cave: a few blocks and a mask), on-screen ones first
local CELL_RECT_TOL = 2e-4          -- a mask fits while the zone rect is within this
local RING_PX = 48                  -- the zone frame fades out as the view leaves the zone
local RING_FADE = 0.15              -- ...but never faster than this (s), however fast you zoom
local PIC_FADE = 0.3                -- same for a zone picture's zoom fade (BASE_Z0..Z1)
local CORE_K0, CORE_K1 = 0.9, 1.0   -- continent alpha over which the exact LOD fade takes over
-- A capital's own map over its home zone (see the header): switched on once
-- the home zone is magnified 1.5x (off again below 1.35x: less than one
-- wheel notch, so a notch always crosses it; no flicker at rest), then
-- crossfaded in time (CITY_FADE) - a zoom-driven fade would leave a
-- half-blended city and banner on screen wherever the zoom stops.
-- A zoom that goes on more than one wheel notch past the switch (a fast
-- wheel spin: it gets there, or its destination is there) would magnify a
-- half-blended city and a ghost banner 1.5x -> 5x within those 0.3 s; its
-- crossfade then keeps pace with the zoom instead and is done CITY_BAND past
-- that notch (CityZoomStep), never quicker than CITY_FADE_MIN (no pop).
-- A single notch across the switch, a slow zoom or a rest: the timed fade.
local CITY_IN, CITY_OUT = 1.5, 1.35
local CITY_FADE = 0.3
local CITY_BAND, CITY_FADE_MIN = 1.15, 0.12 -- (3.1.0: 0.12, was 0.1 - at 60 fps no frame steps more than 0.14)
local CITY_PREFETCH = 1.0           -- build/load the city patch from here (or when a zoom in heads past CITY_IN)
-- (3.5.0) A cave's patch (~300 caves, many small and close together) is built ahead from CAVE_PREFETCH - 0.9 of its
-- switch: world zoom 27 at the default 30 - and only for the caves within CAVE_AHEAD of a screen around the view
-- (NearScreen), not every cave within a whole view from 2/3 of the switch as a city; or where a zoom in is heading.
local CAVE_PREFETCH, CAVE_AHEAD = CITY_IN * 0.9, 0.25
-- (3.1.0) ONE global switch: every city / detail map shows from WORLD zoom cityG (ns.WorldZoom: 1.00x = the whole world
-- map fills the view) and hides again below cityG * Render.CITY_G_HIDE, wherever the camera is. nil (/unroll cityzoom off):
-- CITY_IN / CITY_OUT of each city's own home zone (the rule up to 3.0.1).
local cityG = 14.05
local caveG = 30 -- (3.4.0) the WORLD zoom from which the caves show (Caves.lua, gate "cave"; 3.6.2: 30 - 3.6.0 52, 3.4.0 20); nil: never
local TILE = 256

-- Frame level offsets (above the overlay's own level), bottom to top;
-- footprints, pieces and zone pictures follow from LV_FOOT up.
local LV_WORLD, LV_CONT, LV_FOOT = 0, 1, 2

Render.FADE_Z0, Render.FADE_Z1 = BASE_Z0, BASE_Z1 -- (kept for other modules)
-- (3.1.0) The default world zoom of the city switch (measured in game by the user with /unroll zoom) and how far below it
-- the maps hide again: just enough that a view resting on the line cannot blink (a settle moves the zoom by 4e-8). Every
-- zone's own default view (Elwynn 12.88x, Hillsbrad 13.97x) lies below the band, so what shows there never depends on
-- where the zoom came from.
Render.CITY_G, Render.CITY_G_HIDE = cityG, 0.995
-- (3.1.2) The highest switch the cityzoom command takes: just below the lowest world zoom at which the view can lie inside a
-- capital (Stormwind 25.72x; a window taller than the map's 3:2 only raises it). Above that a capital could get the
-- focus and be the real map - its own map at rest - while its switch is still off.
Render.CITY_G_MAX = 25
-- (3.4.0) The caves' switch (Caves.lua, gate "cave"): its default, and the lowest (3.5.0: below 10x a view holds
-- a hundred caves and more) and the highest world zoom the cavezoom command takes.
Render.CAVE_G, Render.CAVE_G_MIN, Render.CAVE_G_MAX = caveG, 10, 60
-- The switch's "off" value in the units ns.CityZoomOf returns.
function Render.CityOut()
    if cityG then return CITY_IN * Render.CITY_G_HIDE end
    return CITY_OUT
end

local overlay
local stages = {}     -- [mapID] = stage
local freeStages = {}
local stageCount = 0
local tick = 0
local focusID, contFocusID, prevFocusID
local focusChangedAt = 0
local weight = {}     -- [mapID] = eased 0..1 "is focused" weight
local ringE = {}      -- [mapID] = eased alpha of a zone picture's frame ring
local picZ = {}       -- [mapID] = eased zoom fade of a zone picture
local ringSeen = {}
local picVis = {}      -- [mapID] = tick of the last Draw that showed its picture
local picOrder = {}   -- [mapID] = stacking order of visible zone pictures
local picSeq = 0
local picLow = 0      -- (3.1.0) order numbers below every picture showing (PlanLevels: the real map's own picture)
local picSeen, pics = {}, {}
local prefetch        -- {x, y, vw}: where a zoom in is heading
local fadeTime = FOCUS_FADE
local lastDrawT
local visible = {}
local used = {}
local levelCap = 10000
local hasGradient = nil
local emitStrips = CORNER_STRIPS
local contT, needCore, cores = {}, {}, {}
local liftLo, liftHi, liftMap, liftID -- see Render:SetRestLift
local cityLayer                       -- (3.1.1) where lifted parts live (Render:SetCityLayer, Core's Setup)
-- (CityFades; a city: a capital or a detail level - Dalaran, Blackrock Mountain, Gnomeregan, a cave)
local cityL, cityLVis, cityPre = {}, {}, {} -- [cityID] = eased fade of a city's patch; tick last shown; build / load it
local cityOn = {}                            -- [cityID] = patch switched on (by its switch's zoom, with hysteresis)
local cityZ = {}                             -- [cityID] = that zoom at the last Draw
local dCityOn = false                        -- this frame draws city patches (cells in use)
local homeOfCity, cityOfHome                 -- [city id] = its home zone's entry / [home zone id] = its capital (CityLinks)
local virt = {}                              -- [id] = virtual map entry of a detail level (DetailEntry, CityLinks)
local xfK, xfKy, xfX, xfY                    -- Emit: layer-px transform (another map's art on a part)
local edgeC                                  -- Emit: extra clip {x0, y0, x1, y1, feather} (a picture's edge)

function Render:Init(parent)
    overlay = parent
end

-- Stage frame levels never go above cap (at rest: under Questie's icons).
function Render:SetLevelCap(cap)
    levelCap = cap
end

-- (3.1.1) The frame lifted parts go to: a clipping frame of its own above Blizzard's map art pins (Core's Setup).
function Render:SetCityLayer(f)
    cityLayer = f
end

-- Explored pieces the game shows for a map (defined below).
local ExploredList

-- At rest Blizzard's canvas draws the REAL map's explored areas itself
-- (MapExplorationPinMixin:RefreshOverlays, Blizzard_SharedMapDataProviders/
-- MapExplorationDataProvider.lua) on a pin level above our whole rest band.
-- They match our own copy of that map's pieces, so where our mosaic stacks
-- another picture above those pieces - a city inside its zone (the view pokes
-- out of the city, so the zone is the real map), or a neighbour's picture -
-- Blizzard's overlays would cover it (Dun Morogh's IRONFORGE banner over the
-- city). Such pictures go to levels lo..hi, just above that pin level and
-- below the map highlight and every icon. mapID nil (our layers detached
-- from the canvas while moving) = no lift. (Called every frame while the
-- canvas follows the view: only a change - or force - re-reads the pieces.)
function Render:SetRestLift(lo, hi, mapID, force)
    if not force and lo == liftLo and hi == liftHi and mapID == liftID then return end
    liftLo, liftHi, liftID = lo, hi, mapID
    liftMap = nil
    local e = mapID and lo and hi and hi >= lo + 1 and ns.maps[mapID]
    if e and e.mapType == ns.MAPTYPE_ZONE then
        local list = ExploredList(mapID)
        if list and #list > 0 then liftMap = mapID end
    end
end

-- Exploration changed: rebuild explored pieces next time they're used.
function Render:MarkArtDirty()
    for _, st in pairs(stages) do
        st.piecesDirty, st.topDirty = true, true
        -- (3.5.0) a detail level's patch shows explored art only through its cover (Dalaran): a cave's never changes
        local e = st.e
        if not (e and e.virtual and not e.detail.cover) then st.lodDirty = true end
    end
    Render.bannerOn = nil
    if liftID then Render:SetRestLift(liftLo, liftHi, liftID, true) end
end

-- Alpha of a zone picture's own explored pieces (its "top" part, the level
-- above its base) while the base is at alpha b and the zone's regular pieces
-- show under the picture with weight w (their alpha, less what older
-- pictures cover). Separate textures don't fade as one image: with the top
-- at b, the base tints explored land by b*(1-b) (up to 25%). Where the same
-- pieces already show below, a faster top cancels that: at 1-(1-b)^2 the
-- tint is b*(1-b)^2 (at most 4/27 = 15%). Where they don't (w < 1, or a
-- neighbour's art on top of them) a faster top shows them too early, so the
-- boost scales with w. Continuous in b and w, 0 at b = 0 (where the picture
-- and its top leave their levels) and 1 at b = 1.
local function TopAlpha(b, w)
    b, w = ns.Clamp01(b), ns.Clamp01(w)
    return b + w * b * (1 - b)
end

---------------------------------------------------------------------------
-- Parts: a frame holding textures (and mask textures) of one layer of a map
---------------------------------------------------------------------------
local function NewPart()
    local f = CreateFrame("Frame", nil, overlay)
    f.pool, f.masks, f.n, f.nm, f.outer = {}, {}, 0, 0, {}
    f:Hide()
    return f
end

local function BeginPart(f, keepLoaded)
    f.n, f.nm = 0, 0
    wipe(f.outer)
    f.outerA = nil
    if f.patch then -- (3.1.0: the mosaic's banner covers, see Render.PatchQuads)
        wipe(f.patch)
        wipe(f.patchOut)
        f.patchA = nil
    end
    f.builtAt = GetTime()
    if not keepLoaded then f.loaded, f.loadedAt = false, nil
    elseif not f.loadedAt then f.loaded = false end
end

-- Unused textures drop their mask first (as MapCanvasMixin:SetMaskTexture
-- does); unused masks are only hidden and unanchored here (like Blizzard's
-- mask pool), and lose their file in FreeMasks once nothing references them.
local function EndPart(f, keepMasks)
    for i = f.n + 1, #f.pool do
        local tex = f.pool[i]
        if tex.maskRef and not keepMasks then
            tex:RemoveMaskTexture(tex.maskRef)
            tex.maskRef = nil
        end
        if tex:IsShown() or tex:GetTexture() then
            tex:Hide()
            tex:SetTexture(nil)
        end
    end
    for i = f.nm + 1, #f.masks do
        local m = f.masks[i]
        if m:IsShown() then
            m:Hide()
            m:ClearAllPoints()
        end
    end
end

-- (after EndPart with f.n == 0: no texture references a mask any more)
local function FreeMasks(f)
    for i = f.nm + 1, #f.masks do
        local m = f.masks[i]
        if m:GetTexture() then m:SetTexture(nil) end
        m.file = nil
    end
end

-- Before a part is rebuilt, every texture lets go of its mask, so no mask
-- gets a new file while a texture still uses it (Blizzard's order in
-- MapCanvasMixin:SetMaskTexture: RemoveMaskTexture, then re-point).
local function DetachMasks(f)
    for _, tex in ipairs(f.pool) do
        if tex.maskRef then
            tex:RemoveMaskTexture(tex.maskRef)
            tex.maskRef = nil
        end
    end
end

-- (a mask that already shows this file keeps it: no reload)
local function SetMaskFile(m, file)
    if m.file ~= file then
        m:SetTexture(file, "CLAMP", "CLAMP", "TRILINEAR")
        m.file = file
    end
end

local function NextTex(f, sub)
    f.n = f.n + 1
    local tex = f.pool[f.n]
    if not tex then
        tex = f:CreateTexture(nil, "ARTWORK")
        f.pool[f.n] = tex
    end
    tex:SetDrawLayer("ARTWORK", sub or 0)
    tex:ClearAllPoints()
    tex:SetVertexColor(1, 1, 1, 1)
    tex:SetAlpha(1)
    if tex.maskRef then
        tex:RemoveMaskTexture(tex.maskRef)
        tex.maskRef = nil
    end
    if tex.turned then -- (3.4.0, EmitBlocks: a minimap block - its turn and its grey go with it)
        if tex.SetRotation then tex:SetRotation(0) end
        if tex.SetDesaturated then tex:SetDesaturated(false) end
        tex.turned = nil
    end
    tex:Show()
    return tex
end

local function NextMask(f)
    f.nm = f.nm + 1
    local m = f.masks[f.nm]
    if not m then
        m = f:CreateMaskTexture()
        f.masks[f.nm] = m
    end
    m:ClearAllPoints()
    m:Show()
    return m
end

local function Gradient(tex, orientation, a0, a1)
    if hasGradient == nil then
        hasGradient = (tex.SetGradient ~= nil) and (CreateColor ~= nil)
    end
    if hasGradient then
        tex:SetGradient(orientation, CreateColor(1, 1, 1, a0), CreateColor(1, 1, 1, a1))
    else
        tex:SetVertexColor(1, 1, 1, (a0 + a1) / 2)
    end
end

-- Emit a textured rect (layer px [x0,x1]x[y0,y1], texcoords u0..u1/v0..v1),
-- clipped to C = {cx0, cy0, cx1, cy1} and faded to transparent over the last
-- `fw` px inside C's edges. Split into cells so each cell needs at most a
-- one-directional gradient; corner cells use a few strips.
local function AddSplit(list, v, lo, hi)
    if v > lo + 0.01 and v < hi - 0.01 then list[#list + 1] = v end
end
local function Dedup(list)
    local j = 1
    for i = 2, #list do
        if list[i] - list[j] > 0.01 then
            j = j + 1
            list[j] = list[i]
        end
    end
    for i = #list, j + 1, -1 do list[i] = nil end
end

local function Emit(f, file, x0, y0, x1, y1, u0, u1, v0, v1, C, fw, ky, sub, mask, split)
    local cx0, cy0, cx1, cy1 = C[1], C[2], C[3], C[4]
    if xfK then
        -- (another map's art on this part: its layer px -> this part's)
        x0, x1, cx0, cx1 = (x0 - xfX) * xfK, (x1 - xfX) * xfK, (cx0 - xfX) * xfK, (cx1 - xfX) * xfK
        y0, y1, cy0, cy1 = (y0 - xfY) * xfKy, (y1 - xfY) * xfKy, (cy0 - xfY) * xfKy, (cy1 - xfY) * xfKy
        fw = fw * xfK
    end
    -- (edgeC: a second clip rect with its own feather - a picture's cropped,
    -- feathered edge - multiplied in)
    local E = edgeC
    local ax0, ay0 = math.max(x0, cx0, E and E[1] or cx0), math.max(y0, cy0, E and E[2] or cy0)
    local ax1, ay1 = math.min(x1, cx1, E and E[3] or cx1), math.min(y1, cy1, E and E[4] or cy1)
    if ax1 - ax0 < 0.01 or ay1 - ay0 < 0.01 then return end
    local du, dv = (u1 - u0) / (x1 - x0), (v1 - v0) / (y1 - y0)

    local function AX(x)
        local a = 1
        if fw > 0 then a = ns.Clamp01((x - cx0) / fw) * ns.Clamp01((cx1 - x) / fw) end
        if E then a = a * ns.Clamp01((x - E[1]) / E[5]) * ns.Clamp01((E[3] - x) / E[5]) end
        return a
    end
    local function AY(y)
        local a = 1
        if fw > 0 then a = ns.Clamp01((y - cy0) / fw) * ns.Clamp01((cy1 - y) / fw) end
        if E then a = a * ns.Clamp01((y - E[2]) / E[5]) * ns.Clamp01((E[4] - y) / E[5]) end
        return a
    end

    local function Quad(qx0, qy0, qx1, qy1)
        local tex = NextTex(f, sub)
        tex:SetTexture(file, "CLAMP", "CLAMP", "TRILINEAR")
        tex:SetTexCoord(u0 + (qx0 - x0) * du, u0 + (qx1 - x0) * du, v0 + (qy0 - y0) * dv, v0 + (qy1 - y0) * dv)
        tex:SetSize(qx1 - qx0, (qy1 - qy0) * ky)
        tex:SetPoint("TOPLEFT", f, "TOPLEFT", qx0, -qy0 * ky)
        if mask then
            tex:AddMaskTexture(mask)
            tex.maskRef = mask
        end
        if split then
            local mx, my = (qx0 + qx1) / 2, (qy0 + qy1) / 2
            if mx < split[1] or mx > split[3] or my < split[2] or my > split[4] then
                f.outer[#f.outer + 1] = tex
            end
        end
        return tex
    end

    -- split points
    local xs, ys = { ax0 }, { ay0 }
    if fw > 0 then
        AddSplit(xs, cx0 + fw, ax0, ax1); AddSplit(xs, cx1 - fw, ax0, ax1)
        AddSplit(ys, cy0 + fw, ay0, ay1); AddSplit(ys, cy1 - fw, ay0, ay1)
    end
    if E then
        AddSplit(xs, E[1] + E[5], ax0, ax1); AddSplit(xs, E[3] - E[5], ax0, ax1)
        AddSplit(ys, E[2] + E[5], ay0, ay1); AddSplit(ys, E[4] - E[5], ay0, ay1)
    end
    if split then
        AddSplit(xs, split[1], ax0, ax1); AddSplit(xs, split[3], ax0, ax1)
        AddSplit(ys, split[2], ay0, ay1); AddSplit(ys, split[4], ay0, ay1)
    end
    table.sort(xs); Dedup(xs)
    table.sort(ys); Dedup(ys)
    xs[#xs + 1], ys[#ys + 1] = ax1, ay1

    for j = 1, #ys - 1 do
        local ya, yb = ys[j], ys[j + 1]
        for i = 1, #xs - 1 do
            local xa, xb = xs[i], xs[i + 1]
            local la, lb = AX(xa), AX(xb)
            local ta, tb = AY(ya), AY(yb)
            if not (la <= 0 and lb <= 0) and not (ta <= 0 and tb <= 0) then
                if la == lb and ta == tb then
                    local tex = Quad(xa, ya, xb, yb)
                    if la * ta < 1 then tex:SetVertexColor(1, 1, 1, la * ta) end
                elseif ta == tb then
                    Gradient(Quad(xa, ya, xb, yb), "HORIZONTAL", la * ta, lb * ta)
                elseif la == lb then
                    -- VERTICAL: min colour at the bottom (yb), max at the top (ya)
                    Gradient(Quad(xa, ya, xb, yb), "VERTICAL", la * tb, la * ta)
                else
                    local n = emitStrips
                    for s = 0, n - 1 do
                        local sy0 = ya + (yb - ya) * s / n
                        local sy1 = ya + (yb - ya) * (s + 1) / n
                        local t = AY((sy0 + sy1) / 2)
                        if t > 0 then Gradient(Quad(xa, sy0, xb, sy1), "HORIZONTAL", la * t, lb * t) end
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Building a map's layers
---------------------------------------------------------------------------
local function BaseLayout(mapID)
    local ve = virt[mapID]
    if ve then return ve.lw, ve.lh, ve.tw, ve.th, ve.tiles end -- (a detail level: never asked of C_Map)
    local layers = C_Map.GetMapArtLayers(mapID)
    local L = layers and layers[1]
    if not L or not L.layerWidth or L.layerWidth <= 0 or not L.tileWidth or L.tileWidth <= 0
        or not L.tileHeight or L.tileHeight <= 0 then
        return nil
    end
    local files = C_Map.GetMapArtLayerTextures(mapID, 1)
    if type(files) ~= "table" or #files == 0 then return nil end
    return L.layerWidth, L.layerHeight, L.tileWidth, L.tileHeight, files
end

-- Calls fn(file, x0, y0, pixW, pixH, fileW, fileH, drawOnTop) for every 256px
-- tile of a list of overlay pieces, like Blizzard's MapExplorationPinMixin
-- (but with the real smallest file size: WoW Forever's are 32px, not 16).
local function ForEachPieceTile(list, fn)
    for _, info in ipairs(list) do
        local tw, th = info.textureWidth, info.textureHeight
        local wide, tall = math.ceil(tw / TILE), math.ceil(th / TILE)
        for j = 1, tall do
            local pixH, fileH = TILE, TILE
            if j == tall then
                pixH = th % TILE
                if pixH == 0 then pixH = TILE end
                fileH = ns.TILE_FILE_MIN or 16
                while fileH < pixH do fileH = fileH * 2 end
            end
            for k = 1, wide do
                local pixW, fileW = TILE, TILE
                if k == wide then
                    pixW = tw % TILE
                    if pixW == 0 then pixW = TILE end
                    fileW = ns.TILE_FILE_MIN or 16
                    while fileW < pixW do fileW = fileW * 2 end
                end
                local file = info.fileDataIDs[(j - 1) * wide + k]
                if file then
                    fn(file, (info.offsetX or 0) + TILE * (k - 1), (info.offsetY or 0) + TILE * (j - 1),
                        pixW, pixH, fileW, fileH, info.isDrawOnTopLayer)
                end
            end
        end
    end
end

-- Explored pieces the game shows for a map.
function ExploredList(mapID)
    if not (C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures) then return nil end
    local ok, res = pcall(C_MapExplorationInfo.GetExploredMapTextures, mapID)
    if not ok or type(res) ~= "table" then return nil end
    local shown = {}
    for _, info in ipairs(res) do
        if info.fileDataIDs and not info.isShownByMouseOver and info.textureWidth and info.textureHeight then
            shown[#shown + 1] = info
        end
    end
    return shown
end

local function EmitPieces(f, list, lw, lh, ky, sub, split, mask)
    local C = { 0, 0, lw, lh }
    ForEachPieceTile(list, function(file, x0, y0, pw, ph, fw, fh, top)
        Emit(f, file, x0, y0, x0 + pw, y0 + ph, 0, pw / fw, 0, ph / fh, C, EDGE_FEATHER, ky, top and sub + 1 or sub, mask, split)
    end)
end

-- Emits the base tiles overlapping clip rect C (half a texel short of the
-- padding in the last row/column, so filtering can't pull it in), drawn
-- shifted by (dx, dy) layer px (a patch; 0 otherwise).
local function EmitBaseTiles(f, lw, lh, tw, th, files, C, fw, ky, sub, mask, split, dx, dy)
    dx, dy = dx or 0, dy or 0
    local cols, rows = math.ceil(lw / tw), math.ceil(lh / th)
    for r = math.max(1, math.floor((C[2] - dy) / th) + 1), math.min(rows, math.floor((C[4] - dy - 0.01) / th) + 1) do
        for c = math.max(1, math.floor((C[1] - dx) / tw) + 1), math.min(cols, math.floor((C[3] - dx - 0.01) / tw) + 1) do
            local file = files[(r - 1) * cols + c]
            if file then
                local x0, y0 = (c - 1) * tw, (r - 1) * th
                local w, h = math.min(tw, lw - x0), math.min(th, lh - y0)
                if w < tw then w = w - 0.5 end
                if h < th then h = h - 0.5 end
                Emit(f, file, x0 + dx, y0 + dy, x0 + w + dx, y0 + h + dy, 0, w / tw, 0, h / th, C, fw, ky, sub, mask, split)
            end
        end
    end
end

-- A map's picture: its base, cropped `crop` px on every side and feathered
-- `fw` px. A zone's picture also gets, under the feathered border, a RING of
-- the uncropped base (frame included) whose alpha is set per frame (see
-- SetRing); its explored pieces are a separate part (st.top, BuildPieces).
local function BuildBase(st, crop, fw, isZone)
    local e, f = st.e, st.base
    BeginPart(f)
    f.ring = f.ring or {}
    wipe(f.ring)
    f.ringA = nil
    local lw, lh, tw, th, files = BaseLayout(e.id)
    if not lw then
        EndPart(f)
        return false
    end
    local ky = e.ky or 1
    if isZone and crop > 0 then
        local k = crop + fw -- the cropped base is fully opaque inside this
        for _, B in ipairs({ { 0, 0, lw, k }, { 0, lh - k, lw, lh }, { 0, k, k, lh - k }, { lw - k, k, lw, lh - k } }) do
            local n0 = f.n
            EmitBaseTiles(f, lw, lh, tw, th, files, B, 0, ky, -1)
            for i = n0 + 1, f.n do f.ring[#f.ring + 1] = f.pool[i] end
        end
    end
    EmitBaseTiles(f, lw, lh, tw, th, files, { crop, crop, lw - crop, lh - crop }, fw, ky, 0)
    EndPart(f)
    st.lw, st.lh = lw, lh
    return true
end

local function SetRing(f, r)
    r = math.floor(r * 100 + 0.5) / 100
    if f.ringA == r or not f.ring then return end
    f.ringA = r
    for _, tex in ipairs(f.ring) do tex:SetAlpha(r) end
end

-- A zone's explored pieces: st.pieces (the mosaic's piece layer, zones seen
-- from afar) or st.top (the same pieces on top of the zone's picture).
-- Texture alpha of a part's textures outside its continent's opaque core
-- (not covered by the continent's core copy, so they fade per texture).
-- (3.1.0) pa: alpha of the part's city-banner covers (Render.PatchQuads) - the city switch's fade; those of them outside
-- the core take both.
local function SetOuter(f, r, pa)
    r = math.floor(r * 255 + 0.5) / 255
    if f.outerA ~= r then
        f.outerA = r
        for _, tex in ipairs(f.outer) do tex:SetAlpha(r) end
    end
    local P = f.patch
    if P and #P > 0 then
        pa = math.floor((pa or 0) * 255 + 0.5) / 255
        if f.patchA ~= pa or f.patchK ~= r then
            f.patchA, f.patchK = pa, r
            local O = f.patchOut
            for _, tex in ipairs(P) do tex:SetAlpha(O[tex] and pa * r or pa) end
        end
    end
end

-- (3.1.0) The textures f.pool[n0 + 1 .. f.n] are a city banner's cover in the mosaic (BuildCell, BuildPieces). They show
-- only while the city's own map does (SetOuter's pa: the city switch's fade): below the switch the mosaic is the zone as
-- Blizzard draws it, banner included, wherever the camera is. o0 = #f.outer before they were emitted (those outside
-- the continent's core leave f.outer: SetOuter gives them both alphas).
function Render.PatchQuads(f, n0, o0)
    local P, O = f.patch, f.patchOut
    if not P then
        P, O = {}, {}
        f.patch, f.patchOut = P, O
    end
    for j = #f.outer, o0 + 1, -1 do
        O[f.outer[j]] = true
        f.outer[j] = nil
    end
    for i = n0 + 1, f.n do P[#P + 1] = f.pool[i] end
    f.patchA = nil
end

-- cell: the zone's ZoneMasks entry when the mosaic draws cells (the piece
-- layer then also paints over city banners; with MASK_PIECES the pieces are
-- cut to the cell too), nil otherwise.
local function BuildPieces(st, f, split, cell)
    local e = st.e
    local want = cell and cell.file or false
    DetachMasks(f)
    -- (keeps its loaded state on a plain rebuild; a new mask loads and fades in)
    BeginPart(f, f.cellFile == nil or f.cellFile == want)
    f.cellFile = want
    local list = ExploredList(e.id)
    local m
    if MASK_PIECES and cell and st.lw and f.CreateMaskTexture then
        m = NextMask(f)
        SetMaskFile(m, cell.file)
        m:SetSize(st.lw, st.lh * (e.ky or 1))
        m:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    end
    if list and st.lw then
        local ky = e.ky or 1
        EmitPieces(f, list, st.lw, st.lh, ky, 0, split, m)
        -- city banners in the explored art: covered with the pieces' own art
        -- from src (see BuildCell), on top of the pieces - or with the base
        -- picture's (pbase: a banner drawn out over the sea, where no
        -- explored art lies below it). (3.1.0) Shown only above the city switch (Render.PatchQuads).
        emitStrips = PATCH_STRIPS
        local n0, o0 = f.n, #f.outer
        for _, p in ipairs(cell and ns.ZoneMaskPatches and ns.ZoneMaskPatches[e.id] or {}) do
            local d, dx, dy = p.dst, p.dst[1] - p.src[1], p.dst[2] - p.src[2]
            if p.pbase then
                local lw, lh, tw, th, files = BaseLayout(e.id)
                if lw then EmitBaseTiles(f, lw, lh, tw, th, files, d, p.feather or 0, ky, 2, m, split, dx, dy) end
            else
                ForEachPieceTile(list, function(file, x0, y0, pw, ph, fw, fh)
                    if x0 + dx < d[3] and x0 + pw + dx > d[1] and y0 + dy < d[4] and y0 + ph + dy > d[2] then
                        Emit(f, file, x0 + dx, y0 + dy, x0 + pw + dx, y0 + ph + dy, 0, pw / fw, 0, ph / fh, d,
                            p.feather or 0, ky, 2, m, split)
                    end
                end)
            end
        end
        emitStrips = CORNER_STRIPS
        if cell then Render.PatchQuads(f, n0, o0) end
    end
    EndPart(f)
end

-- The continent's fully opaque core (inside its crop + feather), again, to
-- be drawn above the mosaic during the LOD fade.
local function BuildCore(st)
    local e, f = st.e, st.core
    BeginPart(f)
    st.hasCore = false
    local lw, lh, tw, th, files = BaseLayout(e.id)
    if lw then
        local k = CONT_CROP + CONT_FEATHER
        local ky = e.ky or 1
        f:SetSize(lw, lh * ky)
        EmitBaseTiles(f, lw, lh, tw, th, files, { k, k, lw - k, lh - k }, 0, ky, 0)
        st.hasCore = f.n > 0
    end
    EndPart(f)
end

-- Every overlay of a zone (explored or not), from the shipped table.
local function AllOverlays(mapID)
    local data = ns.OVERLAYS
    local artID = data and C_Map.GetMapArtID and C_Map.GetMapArtID(mapID)
    local rows = artID and data[artID]
    if not rows then return nil end
    local list = {}
    for i, r in ipairs(rows) do
        local files = {}
        for k = 5, #r do files[#files + 1] = r[k] end
        list[i] = { offsetX = r[1], offsetY = r[2], textureWidth = r[3], textureHeight = r[4], fileDataIDs = files }
    end
    return list
end

-- Footprint: the zone's base picture, but only inside its overlay shapes.
-- One mask per overlay tile (masks intersect, so each base copy gets one).
local function BuildFoot(st, split)
    local e, f = st.e, st.foot
    DetachMasks(f)
    BeginPart(f)
    f.cellFile = false
    local list = AllOverlays(e.id)
    local lw, lh, tw, th, files = BaseLayout(e.id)
    if list and lw and f.CreateMaskTexture then
        local ky = e.ky or 1
        local C = { 0, 0, lw, lh }
        local cols = math.ceil(lw / tw)
        ForEachPieceTile(list, function(pfile, px0, py0, pw, ph, pfw, pfh)
            local m = NextMask(f)
            -- (edge clamp: the quads below stay inside this tile's used part,
            -- and clamp-to-black would fade every tile edge to a seam)
            SetMaskFile(m, pfile)
            m:SetSize(pfw, pfh * ky) -- whole power-of-two file; its used part lands on the tile
            m:SetPoint("TOPLEFT", f, "TOPLEFT", px0, -py0 * ky)
            local px1, py1 = math.min(px0 + pw, lw), math.min(py0 + ph, lh)
            -- base tiles under this overlay tile
            for r = math.floor(py0 / th) + 1, math.floor((py1 - 0.01) / th) + 1 do
                for c = math.floor(px0 / tw) + 1, math.floor((px1 - 0.01) / tw) + 1 do
                    local file = files[(r - 1) * cols + c]
                    if file then
                        local bx0, by0 = (c - 1) * tw, (r - 1) * th
                        local ix0, iy0 = math.max(px0, bx0), math.max(py0, by0)
                        local ix1 = math.min(px1, bx0 + tw, lw)
                        local iy1 = math.min(py1, by0 + th, lh)
                        if ix1 > ix0 and iy1 > iy0 then
                            Emit(f, file, ix0, iy0, ix1, iy1, (ix0 - bx0) / tw, (ix1 - bx0) / tw,
                                (iy0 - by0) / th, (iy1 - by0) / th, C, EDGE_FEATHER, ky, 0, m, split)
                        end
                    end
                end
            end
        end)
    end
    EndPart(f)
end

-- The zone's cell mask (a ZoneMasks entry), if this client's map is the one
-- the mask was made for: WoW Forever, same art, same rect on the continent.
-- Anything else (Classic Era, a changed or unknown map) draws a footprint.
local cellOf = {}
local isForever
local function CellOf(e)
    local c = cellOf[e.id]
    if c == nil then
        c = false
        local m = ns.ZoneMasks and ns.ZoneMasks[e.id]
        if isForever == nil then isForever = ((select(4, GetBuildInfo())) or 0) >= 16000 end
        if m and isForever and e.lw == 1002 and e.lh == 668 and C_Map.GetMapArtID
            and C_Map.GetMapArtID(e.id) == m.art then
            local x0, x1, y0, y1 = ns.RectOn(e.id, m.cont)
            local r = m.rc
            if x0 and math.abs(x0 - r[1]) < CELL_RECT_TOL and math.abs(x1 - r[2]) < CELL_RECT_TOL
                and math.abs(y0 - r[3]) < CELL_RECT_TOL and math.abs(y1 - r[4]) < CELL_RECT_TOL then
                c = m
            end
        end
        cellOf[e.id] = c
    end
    return c or nil
end

-- (3.2.0) Does zone e still draw its picture's BASE (layer 4)? Only a capital - its own map at rest inside it - and a
-- zone the mosaic cannot draw: no fitting cell (Classic Era, maps whose art changed) or cells / mosaic switched off,
-- where the footprints leave its unexplored land to the continent's blurry art. Every other zone's land is its cell,
-- the open sea by its coast too (the 3.2.0 masks): its base would only cover the neighbours with blank parchment.
local function WholePicture(e)
    local c = (ns.db == nil or (ns.db.cells ~= false and ns.db.mosaic ~= false)) and CellOf(e)
    return not (c and c.kind == "zone")
end

-- Cell: the zone's base picture inside its cell - ONE mask for the whole
-- picture (all tiles share it). City banners printed on the picture outside
-- the city's own cell are painted over with the zone's own art (patches) -
-- (3.1.0) above the city switch only (Render.PatchQuads).
local function BuildCell(st, cell, split)
    local e, f = st.e, st.foot
    DetachMasks(f)
    BeginPart(f)
    f.cellFile = cell.file
    local lw, lh, tw, th, files = BaseLayout(e.id)
    if lw and f.CreateMaskTexture then
        local ky = e.ky or 1
        local m = NextMask(f)
        -- (the mask spans the whole layer, which it keeps at 0 near its edges)
        SetMaskFile(m, cell.file)
        m:SetSize(lw, lh * ky)
        m:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        local nz = cell.nz
        EmitBaseTiles(f, lw, lh, tw, th, files, { math.max(0, nz[1]), math.max(0, nz[2]), math.min(lw, nz[3]), math.min(lh, nz[4]) },
            0, ky, 0, m, split)
        emitStrips = PATCH_STRIPS
        local n0, o0 = f.n, #f.outer
        for _, p in ipairs(ns.ZoneMaskPatches and ns.ZoneMaskPatches[e.id] or {}) do
            local d = p.dst
            EmitBaseTiles(f, lw, lh, tw, th, files, { d[1], d[2], d[3], d[4] }, p.feather or 0, ky, 1, m, split,
                d[1] - p.src[1], d[2] - p.src[2])
        end
        emitStrips = CORNER_STRIPS
        Render.PatchQuads(f, n0, o0)
    end
    EndPart(f)
end

-- (3.1.0) A capital's cell in the mosaic: its HOME ZONE's base picture through the city's cell mask (the hole the
-- city's cell leaves in its parent's), so below the city switch the mosaic is the zone as Blizzard draws it, banner
-- included, wherever the camera is - the city's own map is only its patch (BuildCityLod), switched by the zoom alone.
-- (3.1.2) Where the home zone's picture does not reach (the north half of Orgrimmar's cell lies outside Durotar's map)
-- the cell stays empty: the continent's art shows there, as in the strip beside it, under a soft edge of the zone's -
-- never the city's own map below the switch (up to 3.1.1 the city's art stayed there).
local function BuildCityFill(st, h, cell, split)
    local e, f = st.e, st.foot
    DetachMasks(f)
    BeginPart(f)
    f.cellFile = cell.file
    local lw, lh = BaseLayout(e.id)
    local hw, hh, htw, hth, hfiles = BaseLayout(h.id)
    if lw and hw and f.CreateMaskTexture then
        local ky, hky = e.ky or 1, h.ky or 1
        -- the city's rect in the home zone's layer px (as BuildCityLod)
        local X0 = (e.x0 - h.x0) / (h.x1 - h.x0) * hw
        local X1 = (e.x1 - h.x0) / (h.x1 - h.x0) * hw
        local Y0 = (e.y0 - h.y0) / (h.y1 - h.y0) * hh
        local Y1 = (e.y1 - h.y0) / (h.y1 - h.y0) * hh
        local kx = lw / (X1 - X0)
        local kyr = kx * hky / ky
        local m = NextMask(f)
        SetMaskFile(m, cell.file)
        m:SetSize(lw, lh * ky)
        m:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        local c, fw = 8, 16 -- (the home picture's dark frame line; the soft edge inside it, in its layer px)
        local nz = cell.nz
        -- the cell's box in the home zone's layer px: does the cell reach past the zone's picture (inside its frame)?
        local C0, C1, C2, C3 = X0 + nz[1] / kx, Y0 + nz[2] / kyr, X0 + nz[3] / kx, Y0 + nz[4] / kyr
        local E
        if C0 < c or C1 < c or C2 > hw - c or C3 > hh - c then
            -- (the zone's art: clipped inside its frame on the sides the cell reaches past, in this part's px)
            E = { C0 < c and (c - X0) * kx or -1e6, C1 < c and (c - Y0) * kyr or -1e6,
                C2 > hw - c and (hw - c - X0) * kx or 1e6, C3 > hh - c and (hh - c - Y0) * kyr or 1e6, fw * kx }
        end
        xfK, xfKy, xfX, xfY = kx, kyr, X0, Y0
        edgeC = E
        EmitBaseTiles(f, hw, hh, htw, hth, hfiles, { math.max(0, X0), math.max(0, Y0), math.min(hw, X1), math.min(hh, Y1) },
            0, ky, 1, m, split)
        edgeC, xfK = nil, nil
    end
    EndPart(f)
end

---------------------------------------------------------------------------
-- City detail (see the header): a capital's patch and its home zone's
-- banner cover, each one part (st.lod) on its map's picture level
---------------------------------------------------------------------------

-- A detail level's virtual map entry (see the header): its world rect on the
-- world map from its cave's rect in yards - (maxX, maxY) is the picture's
-- top-left - like any entrance point (ns.WorldPosToMap). Only where its home
-- zone's cell mask fits this client (WoW Forever, the art the data was made
-- for); nil otherwise. Its art: a ns.DUNGEON_CAVES picture (4 x 3 tiles of
-- 256 on 1002 x 668), or its own grid (def.art: lw x lh layer px of tw x th
-- tiles, row by row - Dalaran's minimap tiles), or (3.4.0) the client's minimap
-- blocks (def.art.blocks: Gnomeregan's tunnels and the minimap caves, EmitBlocks);
-- the level under it: a ns.DUNGEON_CAVES picture or (under.art: the caves of
-- Caves.lua) 12 tiles of its own on that 1002 x 668 picture.
local function DetailEntry(def)
    local c = def.art or (ns.DUNGEON_CAVES and ns.DUNGEON_CAVES[def.cave])
    local h = ns.maps[def.home]
    local lw, lh = c and c.lw or 1002, c and c.lh or 668
    local tw, th = c and c.tw or TILE, c and c.th or TILE
    if not (c and (c.blocks or (c.t and #c.t == math.ceil(lw / tw) * math.ceil(lh / th))) and h and CellOf(h) and ns.WorldPosToMap
        and def.id < 0) then return end
    local r = c.r
    local x0, y0 = ns.WorldPosToMap(c.m, r[3], r[4])
    local x1, y1 = ns.WorldPosToMap(c.m, r[1], r[2])
    if not (x0 and x1 and x1 > x0 and y1 > y0) then return end
    local e = {
        id = def.id, virtual = true, detail = def, name = def.entrance or def.name,
        mapType = ns.MAPTYPE_ZONE, parent = def.home, home = h,
        x0 = x0, x1 = x1, y0 = y0, y1 = y1, cx = (x0 + x1) / 2, cy = (y0 + y1) / 2,
        lw = lw, lh = lh, tw = tw, th = th, area = (x1 - x0) * (y1 - y0), nest = 99, order = 100000,
        tiles = c.t, blocks = c.blocks, tint = c.tint, rimC = c.rim, gate = def.gate, -- (3.4.0: Caves.lua)
    }
    ns.SetStretch(e)
    -- (3.6.0) a cave: the map the wheel's depth limit over it counts from (CaveSwitch)
    if def.gate == "cave" then e.deepMap = ns.DeepestMapAt(e.cx, e.cy) end
    -- the level drawn under it: its rect the same way
    local u = def.under
    local uc = u and (u.art or (ns.DUNGEON_CAVES and ns.DUNGEON_CAVES[u.cave])) -- (3.4.0: or its own grid)
    if uc and uc.t and #uc.t == 12 then
        local ux0, uy0 = ns.WorldPosToMap(uc.m, uc.r[3], uc.r[4])
        local ux1, uy1 = ns.WorldPosToMap(uc.m, uc.r[1], uc.r[2])
        if ux0 and ux1 and ux1 > ux0 and uy1 > uy0 then
            e.under = { x0 = ux0, x1 = ux1, y0 = uy0, y1 = uy1, lw = 1002, lh = 668, tiles = uc.t, def = u }
            ns.SetStretch(e.under)
        end
    end
    -- What the patch draws reaches past its own rect (the halls of the level
    -- under it lie up to ~175 yd north of it, over Searing Gorge; the label
    -- cover a little south): Consider keeps it while any of that is on screen
    -- (e.drawBox = {x0, y0, x1, y1} on the world map), so it never pops out there.
    local b = { x0, y0, x1, y1 }
    local function Grow(R, box, w, h)
        local sx, sy = (R.x1 - R.x0) / w, (R.y1 - R.y0) / h
        b[1], b[2] = math.min(b[1], R.x0 + box[1] * sx), math.min(b[2], R.y0 + box[2] * sy)
        b[3], b[4] = math.max(b[3], R.x0 + box[3] * sx), math.max(b[4], R.y0 + box[4] * sy)
    end
    if e.under and u.nz then Grow(e.under, u.nz, 1002, 668) end
    for _, p in ipairs(def.cover and (def.cover.rects or { def.cover }) or {}) do
        if p.dst and h.lw and h.lh then Grow(h, p.dst, h.lw, h.lh) end
    end
    e.drawBox = b
    return e
end

-- Capital <-> home zone (ZoneMasks: a city cell's parent), for the pairs
-- whose cell masks both fit this client (CellOf). Detail levels join as
-- cities of their home zone (the home zone gets no banner-cover role: their
-- cover is part of their own patch).
local function CityLinks()
    if homeOfCity then return end
    homeOfCity, cityOfHome = {}, {}
    for id, m in pairs(ns.ZoneMasks or {}) do
        local c, h = ns.maps[id], m.parent and ns.maps[m.parent]
        if m.kind == "city" and c and h and CellOf(c) and CellOf(h) then
            homeOfCity[id], cityOfHome[h.id] = h, c
        end
    end
    for _, def in pairs(ns.DETAIL_MAPS or {}) do
        local e = DetailEntry(def)
        if e then
            virt[e.id] = e
            homeOfCity[e.id] = e.home
        end
    end
end

-- A banner patch p of a zone's picture: its base picture and explored pieces
-- (the picture's top) from src, drawn at dst with feathered edges, so the
-- picture looks as it does just beside the banner.
local function EmitCover(f, p, lw, lh, tw, th, files, list, ky, sub, mask, clip)
    local d, dx, dy = clip or p.dst, p.dst[1] - p.src[1], p.dst[2] - p.src[2]
    local fw = p.feather or 0
    if files then EmitBaseTiles(f, lw, lh, tw, th, files, d, fw, ky, sub, mask, nil, dx, dy) end
    ForEachPieceTile(list or {}, function(file, x0, y0, pw, ph, fW, fH)
        if x0 + dx < d[3] and x0 + pw + dx > d[1] and y0 + dy < d[4] and y0 + ph + dy > d[2] then
            Emit(f, file, x0 + dx, y0 + dy, x0 + pw + dx, y0 + ph + dy, 0, pw / fW, 0, ph / fH, d, fw, ky, sub + 1, mask)
        end
    end)
end

-- Home zone: its city banners covered as far as its picture shows them (the
-- part sits on the zone's picture levels, just above the picture). The base
-- picture's art: inside the picture's cropped rect with the picture's own
-- edge feather and, in the feathered border, a second copy whose alpha
-- follows the picture's frame ring (f.ring, like BuildBase's); the frame
-- itself (the crop) is left as is. The explored pieces' art on top, whole,
-- as the picture's top (and Blizzard's exploration pin) draws them.
local function BuildHomeCover(st)
    local e, f = st.e, st.lod
    BeginPart(f, true) -- (3.0.0: a rebuild - an exploration update - keeps the loaded fade, as BuildDetailLod does)
    f.ring = f.ring or {}
    wipe(f.ring)
    f.ringA = nil
    local lw, lh, tw, th, files = BaseLayout(e.id)
    local patches = ns.ZoneMaskPatches and ns.ZoneMaskPatches[e.id]
    if lw and patches then
        local list, ky = ExploredList(e.id), e.ky or 1
        local c, k = ZONE_CROP, ZONE_CROP + ZONE_FEATHER
        emitStrips = PATCH_STRIPS
        for _, p in ipairs(patches) do
            local d, pf = p.dst, p.feather or 0
            -- the border copy (under the other one): four bands inside the crop
            for _, B in ipairs({ { c, c, lw - c, k + pf }, { c, lh - k - pf, lw - c, lh - c }, { c, k, k + pf, lh - k }, { lw - k - pf, k, lw - c, lh - k } }) do
                local clip = { math.max(d[1], B[1]), math.max(d[2], B[2]), math.min(d[3], B[3]), math.min(d[4], B[4]) }
                if clip[3] > clip[1] and clip[4] > clip[2] then
                    local n0 = f.n
                    EmitCover(f, p, lw, lh, tw, th, files, nil, ky, -2, nil, clip)
                    for i = n0 + 1, f.n do f.ring[#f.ring + 1] = f.pool[i] end
                end
            end
            edgeC = { c, c, lw - c, lh - c, ZONE_FEATHER }
            EmitCover(f, p, lw, lh, tw, th, files, nil, ky, 0)
            edgeC = nil
            EmitCover(f, p, lw, lh, tw, th, nil, list, ky, 0) -- (pieces: sub 1)
        end
        emitStrips = CORNER_STRIPS
    end
    EndPart(f)
end

-- Capital: its own map inside its cell, over its home zone's banner covers
-- cut to the home zone's cell (those also stand in for the zone's picture
-- when that isn't up, e.g. over the banner Blizzard's exploration pin draws
-- at rest). Everything in the city's layer px: the zone's art is mapped
-- onto them (Emit transform), the zone's mask stretched the same way.
local function BuildCityLod(st, h)
    local e, f = st.e, st.lod
    DetachMasks(f)
    BeginPart(f, true) -- (3.0.0: a rebuild keeps the loaded fade - before, the patch vanished at rest until the next input)
    f.ring = f.ring or {} -- (3.1.0: the banner covers, shown by SetRing only while they are needed - see LodAlphas)
    wipe(f.ring)
    f.ringA = nil
    local lw, lh, tw, th, files = BaseLayout(e.id)
    local hw, hh, htw, hth, hfiles = BaseLayout(h.id)
    local cell, hcell = CellOf(e), CellOf(h)
    if lw and hw and cell and hcell and f.CreateMaskTexture then
        local ky, hky = e.ky or 1, h.ky or 1
        -- the city's rect in the home zone's layer px
        local X0 = (e.x0 - h.x0) / (h.x1 - h.x0) * hw
        local X1 = (e.x1 - h.x0) / (h.x1 - h.x0) * hw
        local Y0 = (e.y0 - h.y0) / (h.y1 - h.y0) * hh
        local kx = lw / (X1 - X0)
        local kyr = kx * hky / ky -- (so the zone's rows land where its own picture draws them)
        local patches = ns.ZoneMaskPatches and ns.ZoneMaskPatches[h.id]
        if patches then
            local m = NextMask(f)
            SetMaskFile(m, hcell.file)
            m:SetSize(hw * kx, hh * kyr * ky)
            m:SetPoint("TOPLEFT", f, "TOPLEFT", -X0 * kx, Y0 * kyr * ky)
            local list = ExploredList(h.id)
            xfK, xfKy, xfX, xfY = kx, kyr, X0, Y0
            emitStrips = PATCH_STRIPS
            local n0 = f.n
            for _, p in ipairs(patches) do EmitCover(f, p, hw, hh, htw, hth, hfiles, list, ky, 0, m) end
            for i = n0 + 1, f.n do f.ring[#f.ring + 1] = f.pool[i] end
            emitStrips = CORNER_STRIPS
            xfK = nil
        end
        -- (3.6.2) A city whose map holds land no zone cell covers (Orgrimmar, Stormwind) takes that too: its patch mask.
        -- The emblems its map prints there: copies of its own plain art under the patch (through the whole patch, pcover),
        -- whose own mask has them carved out - where the patch is translucent the two crossfade, never double up.
        local covers = cell.pcover and ns.CityPatchCovers and ns.CityPatchCovers[e.id]
        if covers then
            local mc = NextMask(f)
            SetMaskFile(mc, cell.pcover)
            mc:SetSize(lw, lh * ky)
            mc:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
            emitStrips = PATCH_STRIPS
            for _, p in ipairs(covers) do
                local d = p.dst
                EmitBaseTiles(f, lw, lh, tw, th, files, { d[1], d[2], d[3], d[4] }, p.feather, ky, 2, mc, nil, d[1] - p.src[1], d[2] - p.src[2])
            end
            emitStrips = CORNER_STRIPS
        end
        local m = NextMask(f)
        SetMaskFile(m, cell.patch or cell.file)
        m:SetSize(lw, lh * ky)
        m:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        local nz = cell.pnz or cell.nz
        EmitBaseTiles(f, lw, lh, tw, th, files, { math.max(0, nz[1]), math.max(0, nz[2]), math.min(lw, nz[3]), math.min(lh, nz[4]) },
            0, ky, 3, m)
    end
    EndPart(f)
end

-- Is piece p = {offsetX, offsetY, width, height} of mapID explored (shown)?
local function PieceShown(mapID, p)
    for _, info in ipairs(ExploredList(mapID) or {}) do
        if info.offsetX == p[1] and info.offsetY == p[2] and info.textureWidth == p[3] and info.textureHeight == p[4] then
            return true
        end
    end
    return false
end

-- Emit-transform onto a detail level's layer px of a picture spanning rect R
-- (another map entry or the level under it: x0..y1 on the world map, lw, lh,
-- ky) - as BuildCityLod maps the home zone onto the city.
local function DetailXf(e, R)
    local X0 = (e.x0 - R.x0) / (R.x1 - R.x0) * R.lw
    local X1 = (e.x1 - R.x0) / (R.x1 - R.x0) * R.lw
    local Y0 = (e.y0 - R.y0) / (R.y1 - R.y0) * R.lh
    local kx = e.lw / (X1 - X0)
    xfK, xfKy, xfX, xfY = kx, kx * (R.ky or 1) / (e.ky or 1), X0, Y0
    return kx, xfKy, X0, Y0
end

-- (3.4.0, Caves.lua: Gnomeregan's tunnels; 3.5.0: the minimap caves) A level drawn from the client's own minimap
-- blocks: the rock colour over the level's nonzero box (its mask leaves a rim of it around the floor), then each block
-- whole, centred on its point and turned as its WMO lies (Texture:SetRotation about its centre - this client's own UI
-- turns textures so: AddonList.lua, BuffFrame.lua), desaturated and tinted; the lower level first (sublevel 0), the
-- upper over it (1). NextTex undoes the turn and the grey when the texture is used again.
local function EmitBlocks(f, e, nz, ky, m)
    local c, t = e.rimC, e.tint
    if c and nz then
        local tex = NextTex(f, -1)
        tex:SetColorTexture(c[1], c[2], c[3], 1)
        tex:SetSize(nz[3] - nz[1], (nz[4] - nz[2]) * ky)
        tex:SetPoint("TOPLEFT", f, "TOPLEFT", nz[1], -nz[2] * ky)
        tex:AddMaskTexture(m)
        tex.maskRef = m
    end
    for _, b in ipairs(e.blocks) do
        local tex = NextTex(f, b[7] or 0)
        tex:SetTexture(b[1], "CLAMP", "CLAMP", "TRILINEAR")
        tex:SetTexCoord(0, 1, 0, 1) -- (a pooled texture keeps the texcoords of its last use)
        tex:SetSize(b[4], b[5] * ky)
        tex:SetPoint("CENTER", f, "TOPLEFT", b[2], -b[3] * ky)
        tex.turned = true
        if tex.SetRotation then tex:SetRotation(b[6]) end
        if tex.SetDesaturated then tex:SetDesaturated(true) end
        if t then tex:SetVertexColor(t[1], t[2], t[3], 1) end
        tex:AddMaskTexture(m)
        tex.maskRef = m
    end
end

-- A detail level's patch (see the header), in its own layer px, bottom to
-- top: the home zone's printed name covered with the zone's own art (only
-- while the piece printing it shows - per rect, its own pieces; the source:
-- all of the zone's pieces, or with cover.explored the explored ones; not cut
-- to a cell - the pieces aren't either), the level below cut to its mask, the
-- level cut to its mask.
local function BuildDetailLod(st)
    local e, f = st.e, st.lod
    local def = e.detail
    DetachMasks(f)
    -- (A rebuild - an exploration update under Dalaran's cover - keeps a loaded part's fade, as BuildPieces does:
    -- restarting it would blink the level out while moving, and at rest leave it unseen - nothing redraws a part at
    -- alpha 0. The capitals' patches and home-zone covers do the same.)
    BeginPart(f, true)
    local ky = e.ky or 1
    if f.CreateMaskTexture then
        local h, cv = e.home, def.cover
        local rects = {}
        for _, p in ipairs(cv and h and (cv.rects or { cv }) or {}) do
            for _, q in ipairs(p.pieces or { cv.piece }) do
                if PieceShown(h.id, q) then rects[#rects + 1] = p break end
            end
        end
        if #rects > 0 then
            local hw, hh, htw, hth, hfiles = BaseLayout(h.id)
            local list
            if cv.explored then list = ExploredList(h.id) else list = AllOverlays(h.id) end
            if hw and list then
                DetailXf(e, { x0 = h.x0, x1 = h.x1, y0 = h.y0, y1 = h.y1, lw = hw, lh = hh, ky = h.ky })
                emitStrips = PATCH_STRIPS
                for _, p in ipairs(rects) do EmitCover(f, p, hw, hh, htw, hth, hfiles, list, ky, -6) end
                emitStrips = CORNER_STRIPS
                xfK = nil
            end
        end
        local U = e.under
        if U then
            local kx, kyr, X0, Y0 = DetailXf(e, U)
            local m = NextMask(f)
            SetMaskFile(m, U.def.mask)
            m:SetSize(U.lw * kx, U.lh * kyr * ky)
            m:SetPoint("TOPLEFT", f, "TOPLEFT", -X0 * kx, Y0 * kyr * ky)
            EmitBaseTiles(f, U.lw, U.lh, TILE, TILE, U.tiles, U.def.nz, 0, ky, -3, m)
            xfK = nil
        end
        local m = NextMask(f)
        SetMaskFile(m, def.mask)
        m:SetSize(e.lw, e.lh * ky)
        m:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        if e.blocks then EmitBlocks(f, e, def.nz, ky, m) else EmitBaseTiles(f, e.lw, e.lh, e.tw, e.th, e.tiles, def.nz, 0, ky, 0, m) end
    end
    EndPart(f)
end

-- Textures load asynchronously; a part stays invisible until all of its
-- textures are in, then fades in. Returns the fade factor (0 while loading).
local function LoadFade(f, now)
    if not f.loaded and now - (f.builtAt or now) < LOAD_TIMEOUT then
        for i = 1, f.n do
            local tex = f.pool[i]
            if tex.IsObjectLoaded and not tex:IsObjectLoaded() then return 0 end
        end
        for i = 1, f.nm do
            local m = f.masks[i]
            if m.IsObjectLoaded and not m:IsObjectLoaded() then return 0 end
        end
    end
    if not f.loaded then
        f.loaded = true
        if not f.loadedAt then f.loadedAt = now end
    end
    return ns.Smooth((now - f.loadedAt) / LOAD_FADE)
end

-- reuse: the stage is recycled at once (GetStage), so its textures keep
-- their masks (and the masks their files) until the parts are rebuilt.
local function ClearStage(st, reuse)
    for _, f in ipairs({ st.base, st.foot, st.pieces, st.top, st.core }) do -- (core: continents only, may be nil)
        BeginPart(f)
        EndPart(f, reuse)
        if not reuse then FreeMasks(f) end
        f:Hide()
        f.level, f.cellFile = nil, nil
    end
    if st.lod then -- (city patch / banner cover; may be missing)
        BeginPart(st.lod)
        EndPart(st.lod, reuse)
        if not reuse then FreeMasks(st.lod) end
        st.lod:Hide()
        st.lod.level = nil
    end
    st.hasBase, st.hasFoot, st.hasPieces, st.hasTop, st.hasCore, st.hasLod = nil, nil, nil, nil, nil, nil
    st.piecesDirty, st.topDirty, st.lodDirty = nil, nil, nil
    st.lw, st.lh = nil, nil
    st.covT, st.covA, st.covB = nil, nil, nil
end

local function ReleaseStage(st, reuse)
    ClearStage(st, reuse)
    stages[st.mapID] = nil
    st.mapID, st.e = nil, nil
    stageCount = stageCount - 1
    freeStages[#freeStages + 1] = st
end

local function GetStage(e)
    local st = stages[e.id]
    if st then
        st.lastUsed = tick
        return st
    end
    if stageCount >= MAX_STAGES then
        local oldest
        for _, s in pairs(stages) do
            if s.lastUsed < tick and (not oldest or s.lastUsed < oldest.lastUsed) then oldest = s end
        end
        if oldest then ReleaseStage(oldest, true) end -- (popped again just below)
    end
    st = table.remove(freeStages)
    if not st then
        st = { base = NewPart(), foot = NewPart(), pieces = NewPart(), top = NewPart() }
    end
    st.mapID, st.e, st.lastUsed = e.id, e, tick
    stages[e.id] = st
    stageCount = stageCount + 1
    return st
end

-- Free texture memory once the map has been closed for a while (the small
-- world and continent pictures stay, so the next zoom starts with them).
function Render:ReleaseAll()
    for _, st in pairs(stages) do
        local e = st.e
        if not (e and (e.isWorld or e.mapType == ns.MAPTYPE_CONTINENT)) then
            ReleaseStage(st)
        else
            -- (a kept stage recycled from a zone may still hold that zone's masks)
            if not st.hasFoot then BeginPart(st.foot); EndPart(st.foot); FreeMasks(st.foot) end
            if not st.hasPieces then BeginPart(st.pieces); EndPart(st.pieces); FreeMasks(st.pieces) end
            if st.lod and not st.hasLod then BeginPart(st.lod); EndPart(st.lod); FreeMasks(st.lod) end
        end
    end
end

---------------------------------------------------------------------------
-- Geometry helpers shared with Core/Labels
---------------------------------------------------------------------------
function ns.PixelsPerUnit(v, vw)
    return v.lw0 * v.fit0 / vw, v.lh0 * v.fit0 / vw
end

function ns.FitOf(v, e)
    return math.min(v.W / e.lw, v.H / e.lh)
end

-- Zoom of map e relative to its own fit (1 = fills the view like Blizzard's
-- default view of that map).
function ns.ZoomOf(v, e, vw)
    local ppx = v.lw0 * v.fit0 / vw
    return (e.x1 - e.x0) * ppx / (e.lw * ns.FitOf(v, e))
end

-- (3.0.1) Zoom of the whole world map (1 = Azeroth fills the view): the one global zoom number.
function ns.WorldZoom(v, vw)
    local w = ns.maps and ns.maps[ns.WORLD_MAP_ID]
    if w then return ns.ZoomOf(v, w, vw) end
    return 1 / vw
end

-- (3.0.1) The zoom the city switch compares with CITY_IN / CITY_OUT / CITY_PREFETCH: the home zone's own zoom, or -
-- with a world-zoom switch set (Render:SetCityZoom) - the world zoom scaled so that it reads CITY_IN exactly at it.
function ns.CityZoomOf(v, h, vw)
    if cityG then return CITY_IN * ns.WorldZoom(v, vw) / cityG end
    return ns.ZoomOf(v, h, vw)
end

function ns.WidthForZoom(v, e, z)
    return (e.x1 - e.x0) * v.lw0 * v.fit0 / (z * e.lw * ns.FitOf(v, e))
end

local function ContAlpha(v, e, vw)
    local z, b = ns.ZoomOf(v, e, vw), ns.ZoomOf(v, e, 1)
    local z0 = math.min(b * CONT_FADE_W0, 0.95)
    local z1 = math.max(math.min(b * CONT_FADE_W1, 1), z0 + 0.02)
    return ns.Smooth((z - z0) / (z1 - z0))
end

function ns.StageAlpha(v, e, vw)
    if e.isWorld then return 1 end
    if e.mapType == ns.MAPTYPE_CONTINENT then return ContAlpha(v, e, vw) end
    return ns.Smooth((ns.ZoomOf(v, e, vw) - BASE_Z0) / (BASE_Z1 - BASE_Z0))
end

local contOf = {}
local function ContinentOf(e)
    local c = contOf[e.id]
    if c == nil then
        c = false
        local id, guard = e.parent, 0
        while id and id ~= 0 and guard < 8 do
            local m = ns.maps[id]
            if m and m.mapType == ns.MAPTYPE_CONTINENT then c = m break end
            local info = C_Map.GetMapInfo(id)
            id = info and info.parentMapID
            guard = guard + 1
        end
        contOf[e.id] = c
    end
    return c or nil
end

-- The opaque core of a zone's continent picture (where the continent's core
-- copy covers it), in the zone's layer px; nil when it covers the whole zone.
local splitOf = {}
local function CoreSplit(e)
    local s = splitOf[e.id]
    if s == nil then
        s = false
        local c = ContinentOf(e)
        if c and c.lw and c.lh and e.lw and e.lh then
            local k = CONT_CROP + CONT_FEATHER
            local ux, uy = (e.x1 - e.x0) / e.lw, (e.y1 - e.y0) / e.lh
            local wx0 = c.x0 + (c.x1 - c.x0) * k / c.lw
            local wx1 = c.x1 - (c.x1 - c.x0) * k / c.lw
            local wy0 = c.y0 + (c.y1 - c.y0) * k / c.lh
            local wy1 = c.y1 - (c.y1 - c.y0) * k / c.lh
            local r = { (wx0 - e.x0) / ux, (wy0 - e.y0) / uy, (wx1 - e.x0) / ux, (wy1 - e.y0) / uy }
            if r[1] > 0 or r[2] > 0 or r[3] < e.lw or r[4] < e.lh then s = r end
        end
        splitOf[e.id] = s
    end
    return s or nil
end

local function RankOf(e, focus, contFocus)
    if e.isWorld then return -1 end
    if e.mapType == ns.MAPTYPE_CONTINENT then
        return e.order + ((e.id == contFocus) and 1000 or 0)
    end
    return 100000 + e.nest * 10000 + ((e.id == focus) and 5000 or 0) + e.order
end
function ns.RankOf(e) return RankOf(e, focusID, contFocusID) end

---------------------------------------------------------------------------
-- Per-frame draw
---------------------------------------------------------------------------
function Render:SetFocus(id)
    if id ~= focusID then
        prevFocusID, focusID = focusID, id
        focusChangedAt = GetTime()
    end
end
-- Crossfade duration for focus changes (a click flight times it to land).
function Render:SetFadeTime(t) fadeTime = t or FOCUS_FADE end
function Render:GetFocus() return focusID end
function Render:SetContinentFocus(id) if id then contFocusID = id end end
function Render:GetContinentFocus() return contFocusID end
-- Where a zoom in is heading (nil when not zooming in): zone art there is
-- built ahead of time.
function Render:SetPrefetch(x, y, vw)
    if x then
        prefetch = prefetch or {}
        prefetch.x, prefetch.y, prefetch.vw = x, y, vw
    else
        prefetch = nil
    end
end
-- True once the last frame drawn was complete (its bottom layer loaded).
local dready = false
function Render:IsReady() return dready end

local dW, dH, dppx, dppy, dcam, dv, dn, dstep, dbusy, dbuilds, dfocusReady, dpicStep
local pfx0, pfy0, pfx1, pfy1, pfvw

local function Weight(id, target)
    local w = weight[id]
    if w == nil then
        w = target
    elseif w < target then
        w = math.min(target, w + dstep)
    elseif w > target then
        w = math.max(target, w - dstep)
    end
    weight[id] = w
    if w ~= target then dbusy = true end
    return w
end

-- A zone picture's zoom fade follows the zoom, but never faster than
-- PIC_FADE for the whole range, so a fast wheel can't pop the picture (and its
-- frame) out or in within a couple of frames. While the picture can't show
-- (not focused), it takes the target at once.
local function PicFade(id, target, gate)
    local a = picZ[id]
    if a == nil or gate <= 0.002 or (a > target and picVis[id] ~= tick - 1) then
        a = target -- (nothing showing: never fade out from a stale value)
    elseif a < target then
        a = math.min(target, a + dpicStep)
    elseif a > target then
        a = math.max(target, a - dpicStep)
    end
    picZ[id] = a
    if a ~= target then dbusy = true end
    return a
end

local function PartFade(f, wanted, now)
    f.fading = false
    if not wanted then return 0 end
    local x = LoadFade(f, now)
    f.fading = x < 1
    return x
end

local function Overlap(a, b)
    return a.sx0 < b.sx1 and b.sx0 < a.sx1 and a.sy0 < b.sy1 and b.sy0 < a.sy1
end

local function ByRank(a, b) return a.rank < b.rank end
-- (focus-independent: footprint/piece levels must not swap when focus moves)
local function ByStatic(a, b) return a.srank < b.srank end
local zlist = {}

-- Is map entry e - all it draws: a detail level's e.drawBox (DetailEntry), else its rect - within m screens of the view?
-- (m = 0: on screen)
local function NearScreen(e, m)
    local b = e.drawBox
    local x0, y0, x1, y1 = e.x0, e.y0, e.x1, e.y1
    if b then x0, y0, x1, y1 = b[1], b[2], b[3], b[4] end
    return dW / 2 + (x1 - dcam.x) * dppx > -m * dW and dW / 2 + (x0 - dcam.x) * dppx < (1 + m) * dW
        and dH / 2 + (y1 - dcam.y) * dppy > -m * dH and dH / 2 + (y0 - dcam.y) * dppy < (1 + m) * dH
end

local function Consider(e)
    local sx0 = dW / 2 + (e.x0 - dcam.x) * dppx
    local sx1 = dW / 2 + (e.x1 - dcam.x) * dppx
    local sy0 = dH / 2 + (e.y0 - dcam.y) * dppy
    local sy1 = dH / 2 + (e.y1 - dcam.y) * dppy
    local onScreen = NearScreen(e, 0)

    local kind, baseA, footA, pieceA = nil, 0, 0, 0
    local loadBase, loadFoot, loadPieces, loadCore, lod = false, false, false, false, 0
    local lodRole, lodL, loadLod = nil, 0, false
    if e.isWorld then
        kind, baseA, loadBase = "world", 1, true
    elseif e.mapType == ns.MAPTYPE_CONTINENT then
        -- Only the continent you're over (a continent picture's ocean filler
        -- would otherwise cover the other one); crossfades on change.
        local w = Weight(e.id, (contFocusID == nil or e.id == contFocusID) and 1 or 0)
        kind = "continent"
        baseA = ContAlpha(dv, e, dcam.vw) * w
        loadBase = baseA > 0.002
        local zc = ns.ZoomOf(dv, e, dcam.vw)
        lod = ns.Smooth((zc - LOD_C0) / (LOD_C1 - LOD_C0)) * w
        loadCore = loadBase and (zc >= LOD_PREFETCH or (pfvw ~= nil and ns.ZoomOf(dv, e, pfvw) >= LOD_PREFETCH))
    else
        kind = "zone"
        local focused = e.id == focusID
        -- the old focus stays up until the new focus's picture is ready
        local hold = (e.id == prevFocusID) and not dfocusReady
        if hold then dbusy = true end -- keep drawing until the hold resolves
        local fw = Weight(e.id, (focused or hold) and 1 or 0)
        local cont = ContinentOf(e)
        local cw = cont and (weight[cont.id] or 0) or 1
        local zc = cont and ns.ZoomOf(dv, cont, dcam.vw) or 99
        local lod = ns.Smooth((zc - LOD_C0) / (LOD_C1 - LOD_C0)) * cw
        local z = ns.ZoomOf(dv, e, dcam.vw)
        baseA = PicFade(e.id, ns.Smooth((z - BASE_Z0) / (BASE_Z1 - BASE_Z0)), fw * cw) * fw * cw
        pieceA = lod
        footA = (ns.db == nil or ns.db.mosaic ~= false) and lod or 0
        local near = cw > 0 and zc >= LOD_PREFETCH
        if not near and cw > 0 and pfvw and cont and e.x0 < pfx1 and pfx0 < e.x1 and e.y0 < pfy1 and pfy0 < e.y1 then
            near = ns.ZoomOf(dv, cont, pfvw) >= LOD_PREFETCH -- a zoom in is heading here
        end
        loadBase = baseA > 0.002 or (focused and z >= 0.6)
        loadPieces = near
        loadFoot = near and (ns.db == nil or ns.db.mosaic ~= false)
        if e.virtual then pieceA, footA, loadPieces, loadFoot = 0, 0, false, false end -- (its patch only)
        if dCityOn then
            -- a capital's patch / its home zone's banner cover (CityFades)
            local c = homeOfCity[e.id] and e or cityOfHome[e.id]
            if c then
                lodRole, lodL = (c == e) and "city" or "home", (cityL[c.id] or 0) * cw
                loadLod = cityPre[c.id] and cw > 0
            end
        end
    end
    if not onScreen then
        -- (3.1.0) A city / detail map within one view of the screen: its patch - and a capital's cell in the mosaic -
        -- are built and loaded ahead, hidden, so they are there when a drag or a fling brings the city into view (no
        -- pop-in at the screen's edge). Nothing else of it, and nothing of it is placed on a level.
        if not (lodRole == "city" and (loadLod or loadFoot)) or not NearScreen(e, 1) then return end
        baseA, footA, pieceA, lodL = 0, 0, 0, 0
        loadBase, loadPieces, loadCore = false, false, false
    elseif not (loadBase or loadFoot or loadPieces or loadLod) then
        return
    end

    dn = dn + 1
    local it = visible[dn]
    if not it then it = {}; visible[dn] = it end
    it.lodRole, it.lodL, it.loadLod = lodRole, lodL, loadLod
    it.e, it.kind = e, kind
    it.baseA, it.footA, it.pieceA = baseA, footA, pieceA
    it.loadBase, it.loadFoot, it.loadPieces = loadBase, loadFoot, loadPieces
    it.loadCore, it.lod = loadCore, lod
    it.sx0, it.sy0, it.sx1, it.sy1 = sx0, sy0, sx1, sy1
    it.focused = (e.id == focusID)
    it.whole = kind ~= "zone" or WholePicture(e) -- (3.2.0: does its base draw?)
    -- The zone's frame shows while the view stays inside the zone (as on
    -- Blizzard's map) and fades out as the view extends past its edges
    -- (target here; eased in time in Render:Draw).
    local over = math.max(0, sx0, dW - sx1, sy0, dH - sy1)
    it.ringT = (kind == "zone") and (1 - ns.Smooth((over - 1) / RING_PX)) or 0
    it.ringA = it.ringT
    it.rank = RankOf(e, focusID, contFocusID)
    it.srank = RankOf(e)
end

-- (Never use Frame:SetIsFrameBuffer here: on WoW Forever 1.60.1 it trips an
-- engine assert in CSimpleRender.cpp and crashes the client.)
local function Place(f, it, scale, alpha, level, cap)
    if f.fading then dbusy = true end
    -- (3.1.1) a lifted part (cap given: LiftPictures) lives in the city layer - only a clipping frame of its own draws
    -- above the canvas' pins in the client - everything else in the overlay; levels in the city layer count from it
    local host = (cap and cityLayer) or overlay
    if f:GetParent() ~= host then
        f:SetParent(host)
        f.level = nil -- (reparenting re-levels the frame)
    end
    if host == cityLayer then
        level, cap = (cityLayer.level or 0) + 1 + level - (liftLo or level), 1e9
        if level <= (cityLayer.level or 0) then level = (cityLayer.level or 0) + 1 end -- (3.1.2: never under its layer)
    end
    f:SetScale(scale)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", overlay, "TOPLEFT", it.sx0 / scale, -it.sy0 / scale)
    f:SetAlpha(ns.Clamp01(alpha))
    level = math.min(level, cap or levelCap)
    if f.level ~= level then
        ns.SetLevelFixed(f, level)
        f.level = level
    end
    if not f:IsShown() then f:Show() end
end

-- Screen rect of the fully opaque inner part of a cropped+feathered base.
local function Covers(it, inset)
    local s = (it.sx1 - it.sx0) / it.e.lw
    local k = s * (it.e.ky or 1)
    return it.sx0 + inset * s <= 0.5 and it.sx1 - inset * s >= dW - 0.5
        and it.sy0 + inset * k <= 0.5 and it.sy1 - inset * k >= dH - 0.5
end

-- Share of a's on-screen rect under o's base picture (o's rect inset to the
-- middle of its feathered border). Continuous as the view moves.
local function CoverShare(a, o)
    local x0, x1 = math.max(a.sx0, 0), math.min(a.sx1, dW)
    local y0, y1 = math.max(a.sy0, 0), math.min(a.sy1, dH)
    local area = (x1 - x0) * (y1 - y0)
    if area <= 0 then return 0 end
    local s = (o.sx1 - o.sx0) / o.e.lw
    local ix, iy = (ZONE_CROP + ZONE_FEATHER / 2) * s, (ZONE_CROP + ZONE_FEATHER / 2) * s * (o.e.ky or 1)
    local w = math.min(x1, o.sx1 - ix) - math.max(x0, o.sx0 + ix)
    local h = math.min(y1, o.sy1 - iy) - math.max(y0, o.sy0 + iy)
    if w <= 0 or h <= 0 then return 0 end
    return w * h / area
end

-- Render:Draw runs in phases: WoW's Lua 5.1 compiler rejects a function with
-- more than 60 upvalues (the whole file then fails to load).

local function UseCells()
    return ns.db == nil or (ns.db.cells ~= false and ns.db.mosaic ~= false)
end

-- (3.6.0) The caves' switch where the deepest map is m (a cave's: e.deepMap): the cave zoom, or the deepest world zoom
-- the wheel reaches there where that is less (Core's depth limit: maxZoom past the deepest map at a point); nil while
-- the caves are off. The limits by map, for the frame (deepZ: CityFades wipes it).
local deepZ = {}
local function CaveSwitch(m, v)
    if not caveG then return nil end
    local z = deepZ[m]
    if not z then
        z = ns.WorldZoom(v, ns.WidthForZoom(v, m, ns.db and ns.db.maxZoom or 4))
        deepZ[m] = z
    end
    return math.min(caveG, z)
end

-- City detail: each city's patch - a capital's, a detail level's (Dalaran,
-- Blackrock Mountain, Gnomeregan, a cave) - on or off by its switch's zoom
-- (ns.CityZoomOf; a cave: the world zoom scaled by its own switch,
-- CaveSwitch), CITY_IN at the switch, with
-- hysteresis; crossfaded over CITY_FADE (a patch that wasn't showing takes 0
-- at once); and whether to build / load its art: from CITY_PREFETCH (a cave:
-- CAVE_PREFETCH, near the screen), or when a zoom in is heading past CITY_IN
-- over it.
-- The fade's share of this frame from the zoom's own travel (the switch's zoom
-- z0 -> z, a the fade so far, zDest where a zoom in is heading): once the
-- zoom goes more than one wheel notch past the switch - it is there, or a
-- zoom in is heading there - the rest of the fade is spread over the zoom's
-- remaining way to CITY_BAND past that notch, so both arrive together; if
-- the zoom stops first, the timed fade finishes it. 0 while the zoom stays
-- within a notch of the switch (a single notch never gets past it: its fade
-- is the timed one), moves back toward the switch, pans or rests.
local function CityZoomStep(on, a, z0, z, zDest, zOut)
    local notch = math.max(ns.db and tonumber(ns.db.zoomStep) or 1.3, 1.05)
    if on then
        local gate = CITY_IN * notch
        if z <= z0 or not (z >= gate or (zDest and zDest >= gate)) then return 0 end
        local lo, hi = math.max(z0, CITY_IN), gate * CITY_BAND
        if z >= hi then return 1 end
        if z <= lo then return 0 end
        return (1 - a) * math.log(z / lo) / math.log(hi / lo)
    end
    local gate = zOut / notch
    if z >= z0 or z > gate then return 0 end
    local hi, lo = math.min(z0, zOut), gate / CITY_BAND
    if z <= lo then return 1 end
    if z >= hi then return 0 end
    return a * math.log(hi / z) / math.log(hi / lo)
end

-- The fade advances by this frame's time (ddt / CITY_FADE) or by the zoom's
-- travel (CityZoomStep), whichever is more, but never by more than
-- ddt / CITY_FADE_MIN.
local function CityFades(ddt)
    dCityOn = UseCells()
    if not dCityOn then return end
    CityLinks()
    local step = ddt and math.min(1, ddt / CITY_FADE) or 1
    local cap = ddt and math.min(1, ddt / CITY_FADE_MIN) or 1
    local zOut = Render.CityOut()
    wipe(deepZ)
    local wz, wzPf = ns.WorldZoom(dv, dcam.vw), pfvw and ns.WorldZoom(dv, pfvw)
    for cid, h in pairs(homeOfCity) do
        -- (3.4.0) a cave (Caves.lua) by its own switch, hidden just below it whatever the city rule
        local e = virt[cid]
        local cave = e ~= nil and e.gate == "cave"
        local z, zPf -- (zPf: where a zoom in is heading)
        if cave then
            local g = CaveSwitch(e.deepMap, dv)
            z = g and CITY_IN * wz / g or 0
            zPf = pfvw and (g and CITY_IN * wzPf / g or 0)
        else
            z, zPf = ns.CityZoomOf(dv, h, dcam.vw), pfvw and ns.CityZoomOf(dv, h, pfvw)
        end
        local zo = cave and CITY_IN * Render.CITY_G_HIDE or zOut
        local on = cityOn[cid]
        -- (3.5.0 - 1e-9: a view opened at exactly the switch's zoom - M at a cave's switch, or the wheel at the depth
        -- limit that is one - is past it, whatever the rounding of its width)
        if on then on = z > zo else on = z >= CITY_IN - 1e-9 end
        cityOn[cid] = on
        local target = on and 1 or 0
        local a, s, z0 = cityL[cid], step, cityZ[cid]
        cityZ[cid] = z
        if a and a ~= target and z0 then
            local zs = CityZoomStep(on, a, z0, z, zPf, zo)
            if zs > s then s = math.min(zs, cap) end
        end
        if a == nil or (a > target and cityLVis[cid] ~= tick - 1) then
            a = target
        elseif a < target then
            a = math.min(target, a + s)
        elseif a > target then
            a = math.max(target, a - s)
        end
        cityL[cid] = a
        if a ~= target then dbusy = true end
        local pre = a > 0 or z >= (cave and CAVE_PREFETCH or CITY_PREFETCH)
        if pre and cave and not NearScreen(e, CAVE_AHEAD) then pre = false end -- (3.5.0: every cave is on past its switch)
        if not pre and pfvw then
            local c = ns.maps[cid] or e
            if c and c.x0 < pfx1 and pfx0 < c.x1 and c.y0 < pfy1 and pfy0 < c.y1 then
                pre = zPf >= CITY_IN -- a zoom in is heading here
            end
        end
        cityPre[cid] = pre
    end
    -- (the detail levels aren't in ns.drawList: considered here, with the cities - 3.5.0: those that show or load,
    -- cityPre; for the others, most caves most of the time, Consider adds nothing: a detail level is never the focus
    -- and its own picture never shows)
    for id, e in pairs(virt) do
        if cityPre[id] then Consider(e) end
    end
end

-- Build the city patches and banner covers that are needed (after
-- BuildVisible: every visible map has its stage and layout); (3.5.0) at most
-- DETAIL_BUILDS_PER_FRAME detail levels a frame, those showing first, the rest
-- in the next frames (a patch draws nothing until it is built).
local function BuildLods(n)
    local builds = 0
    for pass = 1, 2 do
        for i = 1, n do
            local it = visible[i]
            local st = it.st
            if (pass == 1) == ((it.lodL or 0) > 0) and it.lodRole and it.loadLod and st.lw and (st.hasLod == nil or st.lodDirty)
                and (it.lodRole == "city" or (it.loadBase and st.hasBase)) then
                if it.e.virtual and builds >= DETAIL_BUILDS_PER_FRAME then
                    dbusy = true
                else
                    if not st.lod then st.lod = NewPart() end
                    st.lod:SetSize(st.lw, st.lh * (it.e.ky or 1))
                    if it.e.virtual then
                        BuildDetailLod(st)
                        builds = builds + 1
                    elseif it.lodRole == "city" then BuildCityLod(st, homeOfCity[it.e.id]) else BuildHomeCover(st) end
                    st.hasLod, st.lodDirty = true, false
                end
            end
        end
    end
end

-- Alpha of each visible map's patch / cover part (it.lodA, before the
-- picture levels are planned), and a capital's own picture fading out with
-- its frame ring once its patch can stand in for it: as the view leaves the
-- city only the patch is left (no rectangle, frame or edge feather over the
-- zone), while inside the city (ring 1) the picture is unchanged.
local function LodAlphas(n, now)
    for i = 1, n do
        local it = visible[i]
        local st = it.st
        it.baseU, it.lodA, it.lodCity, it.patchA = it.baseA, 0, nil, 0
        if it.lodRole then
            local f = st.lod and PartFade(st.lod, it.loadLod and st.hasLod, now) or 0
            if it.lodRole == "city" then
                it.lodCity = it.e.id
                -- (3.1.0) A capital's own banner covers show only where the banner is not covered already: while
                -- Blizzard's canvas draws the home zone's explored pieces over our band (it is the real map: the patch
                -- is lifted above them) as far as the home zone's own cover (on its picture, lifted first) is not
                -- there; and on the home zone's picture while that cover is still loading. Everywhere else the banner
                -- is covered where it is drawn - in the mosaic (Render.PatchQuads) and on the home zone's picture
                -- (BuildHomeCover) - so a banner is never covered twice (two half-faded covers made it fade twice as
                -- fast), and no rectangle of home-zone art lies over a neighbour's picture.
                local h = not it.e.virtual and st.lod and homeOfCity[it.e.id]
                if h then
                    local hs = stages[h.id]
                    local seen = hs and hs.covT and hs.covT >= tick - 1 -- (this frame or, drawn after us, the last one)
                    SetRing(st.lod, math.max((liftMap == h.id) and (1 - (seen and hs.covA or 0)) or 0, seen and hs.covB or 0))
                end
                -- (3.1.0: the lesser of the switch's fade and the loading fade, not their product - while both run, in
                -- a fast spin, the product stepped up to 0.23 a frame)
                it.lodA = math.min(math.max(it.lodL, it.baseA), f)
                -- (3.1.0: likewise the lesser of the focus fade and the ring's, not their product)
                -- (3.1.2) The patch's art counts once it has loaded, wanted or not: below the switch the patch is no
                -- longer wanted (f = 0), and the picture of a city the view had left came back for a few frames after a
                -- fast zoom-out from inside it (up to 0.1: the rest of its own fade).
                local fc = f
                if not it.loadLod and st.lod and st.hasLod and st.lod.loaded then fc = 1 end
                local g = 1 - fc * (1 - it.ringA)
                it.baseA, it.topB = math.min(it.baseA, g), math.min(it.topB, g)
            else
                it.lodCity = cityOfHome[it.e.id].id
                it.lodA = math.min(it.lodL, f) -- (3.1.0: the lesser, as above; and of the picture's alpha, see Render:Draw)
                it.patchA = cityL[it.lodCity] or 0 -- (the mosaic's banner covers of this zone, see SetOuter)
                -- (how far this zone's cover is there, and how much of its picture's banner it leaves: see above)
                st.covT, st.covA, st.covB = tick, f * it.baseA, it.baseA * (1 - f)
            end
        end
    end
end

    -- Build what's needed (footprints are heavy: a couple per frame).
local function BuildVisible(n)
    dbuilds = 0
    -- (3.5.0) Every stage shown in this frame is in use before any is handed out: GetStage gives a new map the stage
    -- unused the longest, and a detail level later in the list - they all rank last - would lose its stage to one before
    -- it (a cave blinking out and in, and taking the next one's stage in turn).
    for i = 1, n do
        local st = stages[visible[i].e.id]
        if st then st.lastUsed = tick end
    end
    local cells, useCells = 0, UseCells()
    for i = 1, n do
        local it = visible[i]
        local st = GetStage(it.e)
        it.st = st
        if not st.lw then
            local lw, lh = BaseLayout(it.e.id)
            st.lw, st.lh = lw, lh
            if lw then
                -- Every layer frame spans the map's rect (textures anchor to it).
                local h = lh * (it.e.ky or 1)
                st.base:SetSize(lw, h)
                st.foot:SetSize(lw, h)
                st.pieces:SetSize(lw, h)
                st.top:SetSize(lw, h)
            else
                st.hasBase = false
            end
        end
        if it.loadBase and st.hasBase == nil then
            local crop, fw = 0, 0
            if it.kind == "continent" then crop, fw = CONT_CROP, CONT_FEATHER
            elseif it.kind == "zone" then crop, fw = ZONE_CROP, ZONE_FEATHER end
            st.hasBase = BuildBase(st, crop, fw, it.kind == "zone")
        end
        if st.lw and it.kind == "zone" then
            -- (cells switched on/off: rebuild what was cut the other way)
            local cell = useCells and CellOf(it.e) or nil
            local want = cell and cell.file or false
            if st.hasFoot ~= nil and st.foot.cellFile ~= want then st.hasFoot = nil end
            if st.hasPieces ~= nil and st.pieces.cellFile ~= want then st.piecesDirty = true end
            if it.loadPieces and (st.hasPieces == nil or st.piecesDirty) then
                BuildPieces(st, st.pieces, CoreSplit(it.e), cell)
                st.hasPieces, st.piecesDirty = true, false
            end
            if it.loadBase and st.hasBase and (st.hasTop == nil or st.topDirty) then
                BuildPieces(st, st.top)
                st.hasTop, st.topDirty = true, false
            end
            if it.loadFoot and st.hasFoot == nil then
                if cell and cells < CELL_BUILDS_PER_FRAME then
                    cells = cells + 1
                    local hz = homeOfCity and not it.e.virtual and homeOfCity[it.e.id]
                    if hz then BuildCityFill(st, hz, cell, CoreSplit(it.e)) else BuildCell(st, cell, CoreSplit(it.e)) end
                    st.hasFoot = true
                elseif not cell and dbuilds < FOOT_BUILDS_PER_FRAME then
                    dbuilds = dbuilds + 1
                    BuildFoot(st, CoreSplit(it.e))
                    st.hasFoot = true
                else
                    dbusy = true
                end
            end
        elseif st.lw and it.loadCore and st.hasCore == nil then
            st.core = st.core or NewPart()
            BuildCore(st)
        end
    end
end

local function EaseRings(n, ddt)
    local ringStep = ddt and math.min(1, ddt / RING_FADE) or 1
    -- Zone frames (rings) move toward their target at a bounded rate, so a
    -- fast zoom or fling can't make a frame pop in or out within a frame or
    -- two. A picture that isn't showing takes its target at once.
    for i = 1, n do
        local it = visible[i]
        if it.kind == "zone" then
            local id, t = it.e.id, it.ringT
            local r = ringE[id]
            if r == nil or it.baseA <= 0.002 then
                r = t
            elseif r < t then
                r = math.min(t, r + ringStep)
            elseif r > t then
                r = math.max(t, r - ringStep)
            end
            if r ~= t then dbusy = true end
            ringE[id], ringSeen[id] = r, tick
            it.ringA = r
        end
    end
    for id, seen in pairs(ringSeen) do
        if seen ~= tick then ringSeen[id], ringE[id] = nil, nil end
    end
end

local function FindCovers(n, world)
    -- Hide whatever an opaque picture completely covers.
    local coverAll, coverWorld, worldIn = false, false, world == nil
    for i = 1, n do
        local it = visible[i]
        if it.focused and it.kind == "zone" and it.whole and it.baseA >= 0.999
            and (Covers(it, ZONE_CROP + ZONE_FEATHER) or (it.ringA >= 0.999 and Covers(it, 0))) then
            coverAll = true
        elseif it.kind == "continent" and it.baseA >= 0.999 and Covers(it, CONT_CROP + CONT_FEATHER) then
            coverWorld = true
        elseif it.kind == "world" and it.baseA >= 0.999 then
            worldIn = true
        end
    end
    dready = worldIn or coverWorld or coverAll
    return coverAll, coverWorld
end

-- (3.1.0) Is any city banner of visible home zone `it` (ns.ZoneMaskPatches, with its feather) on screen?
function Render.BannerOnScreen(it)
    local e = it.e
    local s = (it.sx1 - it.sx0) / e.lw
    local k = s * (e.ky or 1)
    for _, p in ipairs(ns.ZoneMaskPatches and ns.ZoneMaskPatches[e.id] or {}) do
        local d = p.dst
        if it.sx0 + d[3] * s > 0 and it.sx0 + d[1] * s < dW and it.sy0 + d[4] * k > 0 and it.sy0 + d[2] * k < dH then return true end
    end
    return false
end

local function PlanLevels(n, coverAll)
    -- Level plan, bottom to top: world, continent, footprints, explored
    -- pieces, then the zone pictures that show, each on its own two levels
    -- (base, then its top) in the order they appeared (a picture never jumps
    -- over another while visible, so crossfades stay continuous).
    -- Footprints/pieces of zones whose rects overlap get distinct levels in
    -- rank order (bigger zones below smaller ones) so nothing depends on the
    -- engine's order for equal levels; invisible (loading) parts don't use
    -- up levels.
    local footMax, pieceMax = -1, -1
    wipe(picSeen)
    wipe(pics)
    wipe(zlist)
    for i = 1, n do
        local it = visible[i]
        local st = it.st
        it.footOff, it.pieceOff, it.picLevel, it.lifted = nil, nil, nil, nil
        it.lodLevel, it.lodLifted, it.lodShow = nil, nil, nil
        if it.kind == "zone" then
            local showPic = st.hasBase and it.loadBase and it.baseA > 0.002
            -- (a capital's patch alone also makes it a picture; a home zone's
            -- banner cover only shows with the zone's picture)
            local showLod = it.lodA > 0.002 and st.hasLod and st.lod.n > 0
            -- (3.1.0: a home zone's banner cover takes a level only while its banner is on screen - with one switch
            -- for all cities every home zone's cover is on above the line, and the lift band has six levels)
            if showLod and it.lodRole == "home" and not Render.BannerOnScreen(it) then showLod = false end
            if showPic or (showLod and it.lodRole == "city") then
                picSeen[it.e.id] = true
                pics[#pics + 1] = it
                it.lodShow, it.picShow = showLod, showPic
            end
            zlist[#zlist + 1] = it
        end
    end
    -- Pictures new this frame go on top, in rank order - except a home
    -- zone's picture that appears while its city shows: right under the city
    -- (the city's patch is part of that zone's look; a newly shown picture
    -- moves nothing that is already visible).
    for _, it in ipairs(pics) do
        local id = it.e.id
        if not picOrder[id] then
            local c = it.lodRole == "home" and it.lodCity
            if id == liftMap and next(picOrder) then
                -- (3.1.0) the real map's own picture appears at rest / in the canvas: UNDER every picture showing. On
                -- top, the older pictures - lifted above Blizzard's exploration overlay until now - would all drop
                -- under that overlay in this one frame, while they still show (LiftPictures lifts what lies after it).
                picLow = picLow - 1
                picOrder[id] = picLow
            elseif c and picSeen[c] and picOrder[c] then
                picOrder[id] = picOrder[c] - 0.5
            else
                picSeq = picSeq + 1
                picOrder[id] = picSeq
            end
        end
    end
    -- Offsets follow a fixed order (never the focus), so two overlapping
    -- footprints or piece layers keep their relative order whatever happens.
    table.sort(zlist, ByStatic)
    if not coverAll then
        for i, it in ipairs(zlist) do
            local st = it.st
            if st.hasFoot and it.loadFoot and st.foot.n > 0 and it.footA > 0.002 then
                local off = 0
                for j = 1, i - 1 do
                    local o = zlist[j]
                    if o.footOff and o.footOff >= off and Overlap(o, it) then off = o.footOff + 1 end
                end
                it.footOff = off
                if off > footMax then footMax = off end
            end
            if st.hasPieces and it.loadPieces and st.pieces.n > 0 and it.pieceA > 0.002 then
                local off = 0
                for j = 1, i - 1 do
                    local o = zlist[j]
                    if o.pieceOff and o.pieceOff >= off and Overlap(o, it) then off = o.pieceOff + 1 end
                end
                it.pieceOff = off
                if off > pieceMax then pieceMax = off end
            end
        end
    end
    for id in pairs(picOrder) do
        if not picSeen[id] then picOrder[id] = nil end
    end
    -- (a detail level lies across zones: above every picture, whatever came first)
    -- (3.1.0) and so does every capital's slot (its patch and its own picture): a zone picture that comes up later -
    -- the focus moved to a neighbour whose map rectangle reaches over the city - never covers a city
    table.sort(pics, function(a, b)
        local ca, cb = a.lodRole == "city", b.lodRole == "city"
        if ca ~= cb then return cb end
        if a.e.virtual ~= b.e.virtual then return b.e.virtual == true end
        -- (3.5.0) detail levels in a fixed order - the larger below, then by id - not by when they came up: two caves
        -- over the same ground keep their order whatever the panning
        if a.e.virtual then
            if a.e.area ~= b.e.area then return a.e.area > b.e.area end
            return a.e.id < b.e.id
        end
        return picOrder[a.e.id] < picOrder[b.e.id]
    end)
    return footMax, pieceMax
end

local function PlanCores(n, lvCore)
    -- Exact LOD fade (see D1): the continent's core copy above all
    -- footprints/pieces at t = (1-lod)*m; zone parts at frame alpha Q/(1-t).
    wipe(contT)
    wipe(needCore)
    wipe(cores)
    for i = 1, n do
        local it = visible[i]
        if it.footOff or it.pieceOff then
            local c = ContinentOf(it.e)
            if c then needCore[c.id] = true end
        end
    end
    for i = 1, n do
        local it = visible[i]
        it.coreT, it.coreLevel = 0, nil
        if it.kind == "continent" and needCore[it.e.id] and it.st.hasCore and it.coreF > 0 then
            local m = ns.Smooth((it.baseA - CORE_K0) / (CORE_K1 - CORE_K0)) * it.coreF
            local t = (1 - it.lod) * m
            if t > 0.002 then
                it.coreT = t
                contT[it.e.id] = t
                cores[#cores + 1] = it
            end
        end
    end
    table.sort(cores, function(a, b) return a.e.order < b.e.order end)
    for k, it in ipairs(cores) do it.coreLevel = lvCore + k - 1 end
    return lvCore + #cores
end

-- A picture's levels from lv: base and top, plus its patch part when that
-- shows - a capital's patch UNDER its own picture (inside the city the
-- picture covers it: Blizzard's city map exactly; as the view leaves the
-- city the picture fades and the patch is left), a home zone's banner cover
-- over its picture. Returns the next free level.
local function SlotLevels(it, lv)
    if not it.lodShow then
        it.picLevel = lv
        return lv + 2
    elseif it.lodRole == "city" then
        it.lodLevel = lv
        if not it.picShow then return lv + 1 end -- (3.1.0) the patch alone: one level (the lift band has six)
        it.picLevel = lv + 1
    else
        it.picLevel, it.lodLevel = lv, lv + 2
    end
    return lv + 3
end

local function PicTops(lvPics)
    local lv = lvPics
    for k, it in ipairs(pics) do
        lv = SlotLevels(it, lv)
        -- (how much of the zone's own regular pieces shows under its
        -- picture: not what older pictures cover)
        local w = it.pieceA
        for m = 1, k - 1 do
            w = w * (1 - pics[m].baseA * CoverShare(it, pics[m]))
        end
        it.topA = TopAlpha(it.topB, w)
    end
end

-- At rest (see Render:SetRestLift): the pictures stacked above the real
-- map's explored pieces - every picture after the real map's own one, or all
-- of them when it has none - move just above Blizzard's exploration pin, in
-- the same order. (A picture's base and top keep their two levels.) The real
-- map's own banner cover goes first: Blizzard's copy of that map's explored
-- pieces carries the banner too.
local function LiftPictures()
    if not (liftID and liftLo and cityLayer) then return end
    local k0 = 0
    if liftMap then
        for k, it in ipairs(pics) do
            if it.e.id == liftMap then k0 = k end
        end
    else
        -- (3.1.1) no explored pieces of the real map under us (a continent, a city, an unexplored zone): the cities and
        -- detail maps alone - last in pics - still go over Blizzard's own map art (a continent's zone hover highlight)
        k0 = #pics
        for k, it in ipairs(pics) do
            if it.lodRole == "city" then
                k0 = k - 1
                break
            end
        end
    end
    local lv = liftLo
    local r = liftMap and pics[k0]
    if r and r.lodLevel and r.lodRole == "home" then r.lodLevel, r.lodLifted, lv = lv, true, lv + 1 end
    for k = k0 + 1, #pics do
        local it = pics[k]
        lv = SlotLevels(it, lv)
        it.lifted, it.lodLifted = true, it.lodLevel ~= nil
    end
end

-- Returns true while something is still animating on its own (art loading,
-- fading in, crossfades, deferred builds) so another frame is needed.
function Render:Draw(cam, v)
    tick = tick + 1
    local now = GetTime()
    -- (after a pause, advance crossfades by one normal frame, not the gap)
    local ddt = lastDrawT and math.min(now - lastDrawT, 0.05)
    dstep = ddt and math.min(1, ddt / fadeTime) or 1
    dpicStep = ddt and math.min(1, ddt / PIC_FADE) or 1
    lastDrawT = now
    dW, dH, dcam, dv, dn, dbusy = v.W, v.H, cam, v, 0, false
    local fst = focusID and stages[focusID]
    dfocusReady = (focusID == nil) or (fst and fst.base.loaded) or (now - focusChangedAt > FOCUS_HOLD_MAX)
    dppx, dppy = ns.PixelsPerUnit(v, cam.vw)
    pfvw = nil
    if prefetch and prefetch.vw < cam.vw then
        local px, py = ns.PixelsPerUnit(v, prefetch.vw)
        pfvw = prefetch.vw
        pfx0, pfx1 = prefetch.x - dW / 2 / px, prefetch.x + dW / 2 / px
        pfy0, pfy1 = prefetch.y - dH / 2 / py, prefetch.y + dH / 2 / py
    end
    CityFades(ddt)

    local world = ns.maps[ns.WORLD_MAP_ID]
    if world then Consider(world) end
    for _, e in ipairs(ns.drawList) do Consider(e) end -- continents come first
    local n = dn
    for i = n + 1, #visible do visible[i] = nil end
    table.sort(visible, ByRank)

    BuildVisible(n)
    if dCityOn then BuildLods(n) end

    -- Loading fades. A picture's top follows its base (it never shows before
    -- the base has loaded, and fades in on its own if it loads later).
    for i = 1, n do
        local it = visible[i]
        local st = it.st
        local b, fb = it.baseA, PartFade(st.base, it.loadBase and st.hasBase, now)
        it.baseA = b * fb
        it.footA = it.footA * PartFade(st.foot, it.loadFoot and st.hasFoot, now)
        it.pieceA = it.pieceA * PartFade(st.pieces, it.loadPieces and st.hasPieces, now)
        it.topA, it.topB = 0, 0
        if it.kind == "zone" then
            local ft = PartFade(st.top, it.loadBase and st.hasBase and st.hasTop, now)
            it.topB = b * math.min(fb, ft)
        end
        it.coreF = st.core and PartFade(st.core, it.loadCore and st.hasCore, now) or 0
    end

    EaseRings(n, ddt)
    LodAlphas(n, now)

    local coverAll, coverWorld = FindCovers(n, world)

    local footMax, pieceMax = PlanLevels(n, coverAll)
    local baseLevel = overlay:GetFrameLevel() -- the overlay itself draws nothing
    local lvFoot = baseLevel + LV_FOOT
    local lvPieces = lvFoot + footMax + 1
    local lvPics = PlanCores(n, lvPieces + pieceMax + 1)
    PicTops(lvPics)
    LiftPictures()

    wipe(used)
    for i = 1, n do
        local it = visible[i]
        local st, kind = it.st, it.kind
        local scale = (it.sx1 - it.sx0) / it.e.lw
        if scale > 0 and scale < 1e5 then
            if st.hasBase and it.loadBase then
                local hidden = (kind == "world" and (coverWorld or coverAll)) or (kind == "continent" and coverAll)
                    or not it.whole -- (3.2.0: a zone the mosaic draws lays no blank map over its neighbours)
                if not hidden then
                    local lv
                    if kind == "world" then lv = baseLevel + LV_WORLD
                    elseif kind == "continent" then lv = baseLevel + LV_CONT
                    else lv = it.picLevel or lvFoot end -- (no level: invisible, still loading)
                    if kind == "zone" then SetRing(st.base, it.ringA) end
                    used[st.base] = true
                    Place(st.base, it, scale, it.baseA, lv, it.lifted and liftHi)
                    if kind == "zone" and it.baseU > 0.002 then picVis[it.e.id] = tick end
                end
            end
            if kind == "zone" and it.picLevel and st.hasTop and st.top.n > 0 then
                used[st.top] = true
                Place(st.top, it, scale, it.topA, it.picLevel + 1, it.lifted and liftHi)
                if not it.whole and it.topA > 0.002 then picVis[it.e.id] = tick end -- (3.2.0: its top is its picture)
            end
            if it.lodLevel then
                -- (a home zone's banner cover fades with the zone's picture)
                local a = it.lodA
                if it.lodRole == "home" then
                    -- (3.1.0: the lesser of its own fade and the picture's - its top only where the top shows: a zone
                    -- with no explored pieces has none, and its cover then stepped with the top's faster fade)
                    a = math.min(a, math.max(it.baseA, (st.hasTop and st.top.n > 0) and it.topA or 0))
                    SetRing(st.lod, it.ringA)
                end
                used[st.lod] = true
                Place(st.lod, it, scale, a, it.lodLevel, it.lodLifted and liftHi)
                st.lod.drawA, st.lod.sx0, st.lod.sy0, st.lod.sx1, st.lod.sy1 = a, it.sx0, it.sy0, it.sx1, it.sy1
                if a > 0.002 then cityLVis[it.lodCity] = tick end
            end
            if kind == "continent" and it.coreLevel then
                used[st.core] = true
                Place(st.core, it, scale, it.coreT, it.coreLevel)
            end
            if kind == "zone" and not coverAll then
                local c = ContinentOf(it.e)
                local keep = 1 - (c and contT[c.id] or 0) -- what the core copy lets through
                if st.hasFoot and it.loadFoot and st.foot.n > 0 then
                    used[st.foot] = true
                    SetOuter(st.foot, keep, it.patchA)
                    Place(st.foot, it, scale, it.footOff and it.footA / keep or it.footA, lvFoot + (it.footOff or 0))
                end
                if st.hasPieces and it.loadPieces and st.pieces.n > 0 then
                    used[st.pieces] = true
                    SetOuter(st.pieces, keep, it.patchA)
                    Place(st.pieces, it, scale, it.pieceOff and it.pieceA / keep or it.pieceA,
                        it.pieceOff and (lvPieces + it.pieceOff) or lvFoot)
                end
            end
        end
    end
    for _, st in pairs(stages) do
        if not used[st.base] and st.base:IsShown() then st.base:Hide() end
        if not used[st.foot] and st.foot:IsShown() then st.foot:Hide() end
        if not used[st.pieces] and st.pieces:IsShown() then st.pieces:Hide() end
        if not used[st.top] and st.top:IsShown() then st.top:Hide() end
        if st.core and not used[st.core] and st.core:IsShown() then st.core:Hide() end
        if st.lod and not used[st.lod] and st.lod:IsShown() then st.lod:Hide() end
    end
    dcam, dv = nil, nil
    return dbusy
end

---------------------------------------------------------------------------
-- Detail levels for Labels / Dungeon
---------------------------------------------------------------------------
-- Alpha the detail level id shows with now (0: not shown).
function Render:DetailAlpha(id)
    local st = id and virt[id] and stages[id]
    local L = st and st.lod
    if L and L:IsShown() and overlay and overlay:IsShown() then return L.drawA or 0 end
    return 0
end

-- Is picture point (u, v) (0..1) inside hit grid g (DetailMaps.lua)?
local function InGrid(g, u, v)
    if not (g and u >= 0 and u < 1 and v >= 0 and v < 1) then return false end
    local rows = g.rows
    local row = rows[math.floor(v * #rows) + 1]
    if not row or row == "" then return false end
    local c = math.floor(u * g.cols)
    for a, b in row:gmatch("(%d+)-?(%d*)") do
        local lo = tonumber(a)
        local hi = tonumber(b) or lo
        if c >= lo and c <= hi then return true end
    end
    return false
end

-- The detail level (its DETAIL_MAPS entry) whose drawn art is at container
-- point (x, y) - shown at alpha 0.5 or more - else nil; second value: the
-- ns.DUNGEON_CAVES key of the level drawn there (the level itself where its
-- shape is - it is drawn on top - else the level under it).
function Render:DetailAt(x, y)
    if not (x and y) then return end
    for id, e in pairs(virt) do
        local st = stages[id]
        local L = st and st.lod
        if L and L:IsShown() and (L.drawA or 0) >= 0.5 and L.sx1 and L.sx1 > L.sx0 and L.sy1 > L.sy0 then
            -- (world-map point -> the level's picture, and the one under it)
            local wx = e.x0 + (x - L.sx0) / (L.sx1 - L.sx0) * (e.x1 - e.x0)
            local wy = e.y0 + (y - L.sy0) / (L.sy1 - L.sy0) * (e.y1 - e.y0)
            if InGrid(e.detail.hit, (wx - e.x0) / (e.x1 - e.x0), (wy - e.y0) / (e.y1 - e.y0)) then return e.detail, e.detail.cave end
            local U = e.under
            if U and InGrid(U.def.hit, (wx - U.x0) / (U.x1 - U.x0), (wy - U.y0) / (U.y1 - U.y0)) then return e.detail, U.def.cave end
        end
    end
end

-- (3.1.0, Core FocusZoneAt) Does capital id draw a patch (its cell masks fit this client and cells are on)?
function Render:HasCityPatch(id)
    return dCityOn and homeOfCity ~= nil and homeOfCity[id] ~= nil and not virt[id]
end

-- (3.1.0) Does home zone h's picture print its city's name banner now? Dun Morogh's, Elwynn's and Teldrassil's base
-- pictures print it; Durotar's, Mulgore's and Tirisfal's only with the explored piece that lies over the banner.
Render.BANNER_IN_BASE = { [1426] = true, [1429] = true, [1438] = true }
function Render.BannerShown(h)
    local t = Render.bannerOn
    if not t then
        t = {}
        Render.bannerOn = t
    end
    local on = t[h.id]
    if on == nil then
        on = Render.BANNER_IN_BASE[h.id] or false
        local p = not on and ns.ZoneMaskPatches and ns.ZoneMaskPatches[h.id]
        local d = p and p[1] and p[1].dst
        if d then
            for _, info in ipairs(ExploredList(h.id) or {}) do
                local x0, y0 = info.offsetX or 0, info.offsetY or 0
                local w = math.min(d[3], x0 + info.textureWidth) - math.max(d[1], x0)
                local hh = math.min(d[4], y0 + info.textureHeight) - math.max(d[2], y0)
                if w > 0 and hh > 0 and w * hh >= 0.5 * (d[3] - d[1]) * (d[4] - d[2]) then
                    on = true
                    break
                end
            end
        end
        t[h.id] = on
    end
    return on
end

-- (3.1.0, Labels.lua) How much of capital id's name label shows: all of it while the city's own map does (the patch);
-- none while its home zone's drawing prints the name itself - the banner, readable once the zone's own name label has
-- given way (zone zoom 0.45 - 0.7) - so the name is never on the map twice. By the zoom alone, like the switch.
-- (3.1.0 review) Second value: true while that is the switch's timed fade (the patch half-faded), false when the zoom
-- band decides - a label part-faded by the zoom keeps its place like every other label (Labels.lua placedSoft).
function Render:CityNameFade(id, v, vw)
    local h = dCityOn and homeOfCity and not virt[id] and homeOfCity[id]
    if not h or not Render.BannerShown(h) then return 1, false end
    local L, z = cityL[id] or 0, 1 - ns.Smooth((ns.ZoomOf(v, h, vw) - 0.45) / 0.25)
    if L >= z then return L, L > 0.03 and L < 0.97 end
    return z, false
end

-- (3.0.1) The WORLD zoom (ns.WorldZoom) from which every city's own map shows; (3.1.0) the default (Render.CITY_G), and
-- they hide again just below it (Render.CITY_G_HIDE). nil / false / 0: the rule up to 3.0.1 - 1.5x of each city's own
-- home zone.
function Render:SetCityZoom(g)
    g = tonumber(g)
    local was = cityG
    if g and g > 0 then
        if g < 1 then g = 1 elseif g > Render.CITY_G_MAX then g = Render.CITY_G_MAX end -- (3.1.2: was 400)
        cityG = g
    else
        cityG = nil
    end
    -- (3.1.0 review) A new switch while the map is drawn (/unroll cityzoom N, default, off, /unroll reset): the slash command
    -- draws at once and the driver again in the same frame - the first of them measured its fade step from the last
    -- draw, seconds ago (0.05 s, the cap), so a city on screen stepped 0.22 in one shown frame. Its fade starts here.
    if cityG ~= was and lastDrawT then lastDrawT = GetTime() end
end
function Render:CityZoom() return cityG, CITY_IN, Render.CityOut() end

-- (3.4.0) The WORLD zoom from which the caves show (Caves.lua, gate "cave"; the default Render.CAVE_G, from
-- Render.CAVE_G_MIN to Render.CAVE_G_MAX); nil / false / 0: the caves never show. They hide again just below it
-- (Render.CITY_G_HIDE).
function Render:SetCaveZoom(g)
    g = tonumber(g)
    local was = caveG
    if g and g > 0 then
        if g < Render.CAVE_G_MIN then g = Render.CAVE_G_MIN elseif g > Render.CAVE_G_MAX then g = Render.CAVE_G_MAX end
        caveG = g
    else
        caveG = nil
    end
    if caveG ~= was and lastDrawT then lastDrawT = GetTime() end -- (as SetCityZoom: the fade starts here)
end
function Render:CaveZoom() return caveG end

-- (3.0.1, /unroll zoom) The zoom numbers as text lines: the world zoom, the zone under the view's centre and its
-- continent, every city / detail map in view and whether its map shows, and the switch rule.
function Render:ZoomLines(cam, v, out)
    -- (3.1.1) not before the map has a size (this client's Lua raises "Division by zero")
    if not (v and v.W and v.H and v.W > 0 and v.H > 0 and cam.vw and cam.vw > 0) then
        out[#out + 1] = "zoom: open the map to see the numbers"
        return
    end
    local x, y = cam.x, cam.y
    out[#out + 1] = ("Zoom %.2fx   (1.00x = the whole world map)"):format(ns.WorldZoom(v, cam.vw))
    local zone, cont
    for _, e in ipairs(ns.drawList) do
        if ns.RectContains(e, x, y) then
            if e.mapType == ns.MAPTYPE_CONTINENT then
                if not cont or e.area < cont.area then cont = e end
            elseif e.mapType == ns.MAPTYPE_ZONE and not (homeOfCity and homeOfCity[e.id]) then
                if not zone or e.area < zone.area then zone = e end
            end
        end
    end
    if zone or cont then
        local s = "centre:"
        if zone then s = ("%s %s (%.2fx of its own map)"):format(s, zone.name, ns.ZoomOf(v, zone, cam.vw)) end
        if cont then s = ("%s%s %s (%.2fx)"):format(s, zone and "," or "", cont.name, ns.ZoomOf(v, cont, cam.vw)) end
        out[#out + 1] = s
    end
    if homeOfCity then
        local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)
        local x0, x1 = x - v.W / 2 / ppx, x + v.W / 2 / ppx
        local y0, y1 = y - v.H / 2 / ppy, y + v.H / 2 / ppy
        local first = #out + 1
        local caves, shown = {}, 0 -- (3.5.0) more than 4 caves in view: one line for them all
        for cid, h in pairs(homeOfCity) do
            local c = ns.maps[cid] or virt[cid]
            if c and c.x0 < x1 and x0 < c.x1 and c.y0 < y1 and y0 < c.y1 then
                local name = (c.name and c.name ~= "") and c.name or tostring(cid)
                local state = cityOn[cid] and "SHOWN" or "hidden"
                if c.gate == "cave" then
                    local g = CaveSwitch(c.deepMap, v) -- (3.6.0: its own switch where the wheel stops short of the cave zoom)
                    caves[#caves + 1] = g and g < caveG and ("%s: cave %s  (from %.2fx)"):format(name, state, g)
                        or ("%s: cave %s"):format(name, state)
                    if cityOn[cid] then shown = shown + 1 end
                elseif cityG then
                    out[#out + 1] = ("%s: city map %s"):format(name, state)
                else
                    out[#out + 1] = ("%s: city map %s  (its zone %s at %.2fx)"):format(name, state, h.name or "?", ns.ZoomOf(v, h, cam.vw))
                end
            end
        end
        if #caves > 4 then
            out[#out + 1] = ("Caves in view: %d, %d shown"):format(#caves, shown)
        else
            for _, l in ipairs(caves) do out[#out + 1] = l end
        end
        if #out > first then
            local t = {}
            for i = first, #out do t[#t + 1] = out[i] end
            table.sort(t)
            for i = 1, #t do out[first + i - 1] = t[i] end
        end
    end
    -- (3.4.0) the caves' switch (before the city rule, which stays the last line); (3.6.0) where the wheel stops short of
    -- it at the view's centre, the deepest zoom there
    if caveG then
        local here = CaveSwitch(ns.DeepestMapAt(cam.x, cam.y), v)
        out[#out + 1] = ("Caves show above zoom %.2fx (hide below %.2fx)%s  -  /unroll cavezoom <N> | default | off"):format(
            caveG, caveG * Render.CITY_G_HIDE, here < caveG and ("; here from %.2fx, the deepest zoom"):format(here) or "")
    else
        out[#out + 1] = "Caves: off  -  /unroll cavezoom default"
    end
    if cityG then
        out[#out + 1] = ("City maps show above zoom %.2fx, everywhere (hide below %.2fx)%s  -  /unroll cityzoom <N> | default | off"):format(
            cityG, cityG * Render.CITY_G_HIDE, cityG == Render.CITY_G and "" or (" - default %.2fx"):format(Render.CITY_G))
    else
        out[#out + 1] = ("City maps show at %.2fx of their own zone (the rule up to 3.0.1)  -  /unroll cityzoom default | <world zoom>"):format(CITY_IN)
    end
end

function Render:HideAll()
    wipe(ringE)
    wipe(ringSeen)
    wipe(picZ)
    wipe(picVis)
    wipe(cityL)
    wipe(cityLVis)
    wipe(cityOn)
    wipe(cityZ)
    for _, st in pairs(stages) do
        st.base:Hide()
        st.foot:Hide()
        st.pieces:Hide()
        st.top:Hide()
        if st.core then st.core:Hide() end
        if st.lod then st.lod:Hide() end
    end
end
