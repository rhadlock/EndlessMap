--[[
Endless Map - RetailRender.lua (1.4.0; retail only: AzerothUnrolled_Standard.toc, after RetailTiles.lua, before Core.lua)

ns.Render on retail (docs/retail-engine.md sections 1, 4 and 5; plan D15: Render.lua - WoW Forever's mosaic of zone cells,
city patches and caves - is not loaded there): the pictures of the placement tree (RetailSpace.lua) from space to the
zones, in Blizzard's own art, behind the interface Core.lua, Labels.lua and the menus use.

What draws - (1.4.0-beta4, docs/retail-engine.md 16; the player on 1.4.0-beta3: "photos 4 and 5 are the same zoom but
different xy, we shouldnt see this ... this is only zoom based", "what ever tile adds the borders... just dont use them")
by the ZOOM ALONE, and only land: each node by its own zoom zc (1 = it fits the view; zL = the zoom where its art reaches
0.25 screen px per art px - no art below it, the root and the globes excepted); the view's position decides only what is
loaded ahead (NEAR, the prefetch), never what is seen. Every picture comes and goes by a SWITCH (1.4.0-beta1): on at a
zoom, off a little below it, a 0.3 s crossfade that keeps pace with a fast wheel - wherever the zoom stops, nothing rests
half-faded over its parent.
  * the Cosmic map (always, at alpha 1 under everything; its 12 tiles never leave while the map is open);
  * the worlds (globe): on at 0.61 inside the add-on's round mask (Masks/Retail/circle.tga, transparent at its edge), which
    opens from the globe's size to past the picture's diagonal over 0.74 -> 0.97; the picture cropped and feathered at its
    printed frame (GLOBE_CROP, GLOBE_FW) - at its edge it fades softly into space, its frame never drawn; (1.4.0-beta4) a
    world's own sea colour lies round it over the Cosmic map from a notch past its fit (SpaceFill: the Cosmic map no
    longer magnified past a world's edge - the player's photo 1, the reviews' R1.11);
  * the continents (cont), each through its land mask (Masks/Retail/c<id>.tga: its land, soft coasts, and its own sea only
    where it sticks out of its world): on at the middle of a -> b, a = min(max(0.50, zL + 0.05), 0.80), b = min(a + 0.20,
    0.95), at most 0.84; the Eastern Kingdoms, Northrend and Khaz Algar (true shape over Azeroth's squeezed drawing) at
    max(0.62, a). (1.4.0-beta4) Never a continent's whole picture: the sea between lands is its world's, as photo 4;
  * the zone cells of every continent, world and inset (RetailCells.lua): each zone's picture cut by a mask of its own
    land, one switch a band by the continent's zoom - WoW Forever's mosaic; a city's or capital's patch with its city;
  * the insets and portals (Blizzard's framed corner pictures that open another map; the Maelstrom): a switch at on =
    max(0.55, min(zL + 0.05, 0.80)); an inset in a soft box over its printed place (RetailTree.lua lr: BoxMask), opening
    to the whole picture by its own zoom - OPEN_END; (1.4.0-beta5) a portal draws no picture of its own, its switch only
    (its places' parent): the Maelstrom's picture is its places drawn on a stylized sea, and its circle opened that sea
    over the Broken Isles' west (the player on 1.4.0-beta4: "broken isles is covered by the malstrum");
  * (1.4.0-beta4's fixes) never a zone's whole picture - its rectangle, its margins, banners and frame: a zone draws as
    its cell (WoW Forever's WholePicture, design rule 10), a city, a capital or a nested zone as its patch - the city plan,
    or the zone's own shape, cut to it (RetailCells.lua; WoW Forever draws a city's rectangle only with the focus, and the
    focus draws nothing here: by the zoom alone, only the patch); a zone with neither is its parent's picture there until
    its cut-out exists - data, not a fallback. /emap cells off: each zone's whole picture (the player's choice). Zones and
    insets carry their explored pieces.
The fade model - WoW Forever's (Render.lua, proven in game), four rules (1.4.0-beta2, docs/retail-engine.md 11.4):
  1. a child comes in over a parent that is there, once it is there itself: shown at alpha 0 while its tiles in view
     load (the client loads only what is visible - as Render.lua's Place and Blizzard's detail layer do), its switch's
     fade starts when they are confirmed (RetailTiles.lua TL.LoadState);
  2. a parent never fades by zoom: under a confirmed opaque picture covering the view it is placed at alpha 0, still shown
     - so loaded (WoW Forever's FindCovers; 1.4.0-beta4: every covered picture, not only the magnified ones);
  3. a child goes out over a parent that is there: its fade starts once the parent's tiles in view are confirmed -
     (1.4.0-beta4's fixes) however long that takes: PARENT_WAIT (2 s) and LOAD_GIVEUP went, the nets the player ruled out
     ("a saftie net isnt a fix it's a bandaid"); the stamp's load.slow measures a texture that takes long;
  4. Blizzard's canvas is hidden (Core.lua UpdateCanvasAlpha: detached and IsReady) only over art the client confirmed:
     the Cosmic map loaded in view, or a confirmed picture covering the view - never on a timeout.
(1.4.0-beta4) Blizzard's map is never the floor: our pictures lie inside its canvas over its art (design rule 3) at rest as
moving, the same pictures - 1.4.0-beta2's floor (our pictures of the map Blizzard's canvas showed, and of every map above
it, at alpha 0 under it) made the look depend on where the view rested and brought its margins and frame back at every
rest. Its guard - masks the client would not draw - is refuted in game (the saved file: every continent's mask set, none
slow; the player's photos show the masked pictures). The map's opening is WoW Forever's (Render.lua LoadFade): the
whole chain of the view loads at once - a picture switched on plans its children while its own picture loads (PlanNode),
the files asked for parents first and in view first (PlanTiles) - and each picture fades in by its own load, its alpha
times its parent's: never the chain fading in level by level, one load after another, over Blizzard's map.
Drawn order: parents first, then the continents (the larger below), the cells, the zones (the larger below, a city above
its home), the link children; a node's own children right above it. Every wanted part is shown - drawn, loading at alpha
0, covered, or preloaded (the window around the view, the next level, where the motion goes: Prefetch) - so the client has
loaded it when it is needed. A part shown again after a hide is loaded or not as the client answers then (IsObjectLoaded:
the stamp's reshow counts), never by a timer. One plan a game frame: a second Draw in the same frame (Core draws from the
wheel's event and from its driver) places the plan at the camera of the moment (Replace).
Levels: each planned stage its own levels in Core's overlay (one clipping block, design rule 9 - the levels inside it
only order its parts). (1.4.0-beta13) One layer, at rest as moving: Blizzard's exploration pin is hidden while the add-on
draws (RetailPins.lua), each map's explored pieces are its own picture's top part, and nothing is lifted over it (SetRestLift).
Debug: Render:Stats(), Render:DebugParts(out), Render:Chain(out) (the harness's retail suites); the readout's texture
line (ZoomLines).
]]
local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)
if ns.FLAVOR ~= "retail" then return end

local Render = {}
ns.Render = Render

-- (Core.lua's defaults and Options.lua read these at load: WoW Forever's city / cave switches - not on retail, but the
-- saved table keeps their rows; Render.lua's numbers)
Render.CITY_G, Render.CITY_G_HIDE, Render.CITY_G_MAX = 14.05, 0.995, 25
Render.CAVE_G, Render.CAVE_G_MIN, Render.CAVE_G_MAX = 30, 10, 60
Render.FADE_Z0, Render.FADE_Z1 = 0.8, 0.97
Render.PREFETCH_FLIGHTS = true -- (Core.lua DrawFrame: a flight's landing view is loaded ahead too - the review, point 10)
Render.PREFETCH_PAN = true     -- (1.4.0-beta2, Core.lua DrawFrame: a drag's or glide's heading too - 11.6)
Render.PREFETCH_OUT = true     -- (1.4.0-beta2, the review of the seams, point 1 - Core.lua DrawFrame: a wheel's zoom OUT too)
-- (1.4.0-beta2) a globe's or portal's circle: the add-on's own mask (tools/retail/build_masks.py), its disc CIRCLE_DISC
-- of the square's side, the edge transparent (the harness reads both)
Render.CIRCLE_FILE = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\circle.tga"
Render.CIRCLE_DISC = 244 / 256

local TL = ns.RetailTiles
local T = ns.RETAIL_TREE
local IMG -- (1.4.0-beta3) the minimap imagery, RetailImagery.lua (loaded after this file: set by the first Draw)
local CAVES -- (1.4.0-beta3) the caves, RetailCaves.lua (the same)
-- (1.4.0-beta2) the session's test switches (RetailWhy.lua, /emap test): noclip, nofade are read here
local TEST = ns.retailTest or {}

local GLOBE_LOAD = 0.35
-- ((1.4.0-beta14) One zoom of the world for each level of picture, whatever its size - on the readout one number, the player on
-- 1.4.0-beta13: "not sure why you differed open items, just fucking fix them": a world's picture at WORLD_ON, a continent's and
-- the Maelstrom's at CONT_ON, an inset's with the zones, RetailCells.lua's BAND_WORLD. 1.4.0-beta1 - 1.4.0-beta13 switched each by
-- its own zoom, its own size: the continents from 1.7x (Kalimdor) to 4.9x (Kul Tiras), the worlds 0.6x - 1.0x, the insets from
-- 5.8x (Argus) to 39x (the Emerald Dream). The cities and caves stay a view's width in yards: their real size)
local WORLD_ON, CONT_ON = 0.84, 1.75
local LOD_DIR = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\Lod\\" -- (a zone's small picture: LodMode)
local SWITCH_OFF = 0.95      -- (off this much below its on)
local ZONE_ON = 0.84         -- (1.4.0-beta1: a zone's switch - done by 1.15 x 0.84 = 0.97, as the old 0.80 -> 0.97 fade)
local OPEN_END = 0.97        -- every box / circle is open by here (a map that can hold the view is whole)
local DIAGONAL = 1.202       -- a 3:2 picture's diagonal in widths: a circle past it covers the picture
local SWITCH_FADE, SWITCH_FADE_MIN = 0.3, 0.12
local SWITCH_BAND = math.log(1.15) -- (a switch going out: done by 1.15 x below its off once zoomed out well past it)
local LOAD_FADE = 0.2         -- (Render.lua's 0.15 stepped a part 0.17 in one frame at 60 fps)
-- (a picture's alpha moves at most this much from one drawn frame to the next: two fades at once - a switch's and a
-- load fade - never step it more; the frame's one plan, Replace, steps nothing)
local STEP_MAX = 0.14
local CIRCLE_FADE = 0.3       -- (1.4.0-beta1) a circle's whole opening takes at least this long
local PLACES_DIM = 0.3        -- ((1.4.0-beta6) a picture under its places' own maps dims by this much - PlaceStage)
local MAG0, MAG1 = 2, 3       -- ((1.4.0-beta6) Azeroth's picture off past MAG1 screen px an art px, on again below MAG0 - PlanNode)
-- ((1.4.0-beta12, WoW Forever parity) a picture's textures go by the live budget alone - Evict, least recently drawn first,
-- as Render.lua's stages go by MAX_STAGES; 1.4.0-beta2 - 1.4.0-beta11 gave back every picture unseen 60 s, under any
-- budget: a zoom out after a minute in a zone set the continents' and the worlds' 780 textures again, every time - the
-- player's 1.4.0-beta11 stamp, 28,683 tile loads in a session, "needlessly swapping tiles reloading over and opver")
local IDLE_EVICT = 2
-- (1.4.0-beta3, WoW Forever parity) the pictures this many views around the view are planned, shown and loaded at
-- their alpha (clipped by the overlay): a drag brings each in loaded (Render.lua builds a city's patch within one view,
-- NearScreen(e, 1); its cells keep their loaded state across hides)
local NEAR = 0.5
-- (1.4.0-beta3, the player's 66.webp: a world's printed frame hard over space) a world's picture cropped and feathered
-- at its frame - px of a 1002-px picture (Render.lua's zone: 24 / 60); (1.4.0-beta4) its frame never back: a ring by the
-- view's position made the look depend on where the view lay
local GLOBE_CROP, GLOBE_FW = 24, 72
local CIRCLE = Render.CIRCLE_FILE
-- (1.4.0-beta3, the reviews of 1.4.0-beta3) an inset's soft opening box: the add-on's soft rect (tools/retail/
-- build_masks.py --soft: transparent at its edge, opaque from SOFT_IN of its width and height in), laid over the box
local SOFT = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\soft.tga"
local SOFT_INX, SOFT_INY = 96 / 1002, 96 / 668
local CORRECTED = { [13] = true, [113] = true, [2274] = true }       -- (true shape over Azeroth's squeezed drawing)
-- (1.4.0-beta4, the player's photo 1: the Cosmic map magnified past Azeroth's edge, its golden globe ring an orange blur
-- in the view's corner; the reviews' R1.11) a world's own sea colour round its picture, over the Cosmic map and under the
-- worlds, through soft.tga over the world's rect grown FILL_GROW of its size a side - by the world's own zoom alone: none
-- at its fit, whole a notch past it (FILL_Z0 -> FILL_Z1). The colours: the median of each world's open sea in its own art
-- (tools/retail/build_masks.py --fills)
local FILL_GROW = 0.5
local FILL_Z0, FILL_Z1 = 1.0, 1.35
-- ((1.4.0-beta4's fixes, the reviews: the fill came in at once, its mask not loaded, never loaded ahead - rule 1) a fill
-- is shown at alpha 0 from FILL_LOAD of its world's zoom while its rect lies within NEAR views of the view, so its mask
-- has loaded when its zoom calls for it; it comes in once the client reports its mask loaded, over LOAD_FADE, its alpha
-- times its zoom's. With the minimap imagery standing for its world, its colour is the imagery's sea (RetailImagery.lua
-- SpaceSea): the drawn map's sand stood beside the imagery's dark sea past a world's edge)
local FILL_LOAD = 0.85
Render.SPACE_FILLS = {
    [101] = { 0.510, 0.443, 0.290 },  -- Outland
    [572] = { 0.498, 0.431, 0.294 },  -- Draenor
    [947] = { 0.518, 0.447, 0.294 },  -- Azeroth
    [1550] = { 0.529, 0.486, 0.353 }, -- The Shadowlands
}

local overlay, cityLayer
local focusID, contFocusID
local prefetch
local stages = {}       -- [entry] = stage
local zoneStages = 0    -- ((1.4.0-beta16) those of a zone's whole picture: Plan)
-- (1.4.0-beta2) the frames of released stages - a host and its parts - for the next stage; (the review of the seams,
-- point 3) by the kind and size of their pictures (ShellKey): a shell keeps its parts' pools, and taken by any stage a
-- small picture's shell grew to the largest pools - 26,074 texture objects after two tours of every place
local shells = {}       -- [key] = { shell, ... }
local order = {}        -- the stages planned this frame, bottom to top
local pref = {}         -- (1.4.0-beta2) the stages the prefetch filled this frame, not planned
local F = {}            -- this frame: view, camera, steps, busy
local lastDrawT
local dready = false
local maskRefused = 0   -- (masks the client's SetTexture answered false: the stamp's masks say which - no fallback)
local frameNew, frameShown, frameParts = 0, 0, 0
local peaks = { drawn = 0, shown = 0 }
local preloaded = {}    -- (1.4.0-beta2) maps C_Map.RequestPreloadMap was asked for, this session
local fills = {}        -- (1.4.0-beta4) [world entry] = its space fill: { f, t, m, at, col } (SpaceFill)

local function Clamp01(x) if x < 0 then return 0 elseif x > 1 then return 1 end return x end
local function Smooth(x) x = Clamp01(x) return x * x * (3 - 2 * x) end

---------------------------------------------------------------------------
-- The interface Core.lua calls
---------------------------------------------------------------------------
function Render:Init(parent) overlay = parent end
function Render:SetCityLayer(f) cityLayer = f end
function Render:SetLevelCap() end -- (levels inside the overlay's clipping block only order its parts: design rule 9)
-- ((1.4.0-beta13) nothing lifted: 1.4.0-beta2 - 1.4.0-beta12 lifted the pictures after Blizzard's map's own over Blizzard's
-- exploration pin at rest, so which layer a picture lay in followed the map Blizzard's canvas rested on - the view's centre;
-- that pin is hidden now - RetailPins.lua - the look at rest is the look moving)
function Render:SetRestLift() end
-- (the focus Core works out - the zone and continent under the view's centre: the labels, the readout, Blizzard's map;
-- (1.4.0-beta4) nothing the renderer draws depends on it)
function Render:SetFocus(id) focusID = id end
function Render:GetFocus() return focusID end
function Render:SetContinentFocus(id) contFocusID = id end
function Render:GetContinentFocus() return contFocusID end
function Render:SetFadeTime() end
function Render:SetPrefetch(x, y, vw)
    if x then
        prefetch = prefetch or {}
        prefetch.x, prefetch.y, prefetch.vw = x, y, vw
    else
        prefetch = nil
    end
end
function Render:IsReady() return dready end
-- (1.4.0-beta3, the minimap imagery - RetailImagery.lua) the overlay its holders lie in; an inset's switch and opening
-- (its imagery comes and goes with its drawn picture); is entry e's own picture there - drawn whole last frame, loaded
-- (the imagery goes out over it: ParentReady)
function Render:Overlay() return overlay end
function Render:StageSwitch(e)
    local st = stages[e]
    if not st then return 0, 0 end
    return st.sa or 0, st.open or 0
end
function Render:MarkArtDirty()
    TL.PiecesDirty()
    for _, st in pairs(stages) do
        if st.top then TL.Release(st.top) end
    end
end

---------------------------------------------------------------------------
-- Stages: one per entry (a map at one place), made when first needed; (1.4.0-beta2) a released stage's frames - its
-- host and parts, each part with its own textures - go to the next stage made (Render.lua's GetStage): the frames move,
-- never a texture
---------------------------------------------------------------------------
local function ShellKey(e, L) return e.kind .. ((L.lw > 2000) and "+" or "") end
local function Shell(key)
    local list = shells[key]
    local sh = list and table.remove(list)
    if sh then
        if sh.host:GetParent() ~= overlay then
            sh.host:SetParent(overlay)
            sh.host.level = nil -- (reparenting re-levels the frame)
        end
        return sh
    end
    local host = CreateFrame("Frame", nil, overlay)
    host:SetAllPoints(overlay)
    host:Hide()
    return { host = host, base = TL.NewPart(host) }
end

local function PartOf(sh, key)
    local p = sh[key]
    if not p then
        p = TL.NewPart(sh.host)
        sh[key] = p
    end
    p.mask = nil
    return p
end

-- (1.4.0-beta4) A mask the client's SetTexture refused: the stamp says so (masks[id] = "false", the readout's "masks
-- refused") - nothing else. 1.4.0-beta2's fallbacks (a continent's rectangle while focused, a globe without its circle, an
-- inset in a clipping host) guarded a failure the client never showed: every continent's mask answered true in the
-- player's saved file, and tools/release/check_images.py fails a build with a mask the client could refuse.
local function MaskRefused(e, m)
    if m.answer ~= false or m.counted then return end
    m.counted = true
    maskRefused = maskRefused + 1
    if ns.retailStamp then ns.retailStamp.masks[(e.cellOf or e).id] = "false" end
end

local function Stage(e)
    local st = stages[e]
    if st then return st end
    local L = TL.Layout(e.cellOf and e.cellOf.id or e.id)
    if not L then return nil end
    -- (a stage with a mask sets its file now: not over the frame's SetTexture budget - it is made next frame)
    -- ((1.4.0-beta3) an inset's soft opening box: a mask, its top's too; (1.4.0-beta4's fixes) none for an inset with its
    -- land mask - RetailTree.lua m, tools/retail/build_masks.py mask_for_inset: its land by its switch, as a continent's)
    local boxed = e.kind == "inset" and not e.node.m
    -- ((1.4.0-beta4's fixes) an inset two - its base's and its top's -, boxed or through its land mask: the masked insets
    -- set one more than they counted - gate.newTex, 97 new SetTexture, f73 of retailwalk:brokenisles)
    if (e.cell or e.node.m or (e.kind == "globe" and e.node.c) or boxed) and TL.newThisFrame + ((e.cell or e.kind == "inset" or e.kind == "cont") and 2 or 1) > TL.NEW_PER_FRAME then
        return nil
    end
    local key = ShellKey(e, L)
    local sh = Shell(key)
    local host = sh.host
    host:ClearAllPoints()
    host:SetAllPoints(overlay)
    host:SetClipsChildren(false)
    st = { e = e, L = L, host = host, sh = sh, shellKey = key, base = PartOf(sh, "base"), a = 0, sa = 0, w = 0 }
    st.hostVis = host:IsShown()
    if e.kind == "zone" then zoneStages = zoneStages + 1 end
    local k = e.kind
    -- ((1.4.0-beta3, the reviews of 1.4.0-beta3) an inset's opening box is a soft mask, no clipping host - BoxMask:
    -- its hard clip stood as a straight-edged rectangle over its parent for 0.3 s at every zoom out of it - voidstorm_out
    -- f31 - 38, Krokuun through Argus)
    st.box = boxed or nil
    local s = L.lw / 1002
    -- ((1.4.0-beta4) no frame ring: a picture's printed frame never drawn - the ring brought it back while the view lay
    -- inside the picture, so the look followed the view's position: photos 3 - 5)
    if k == "zone" then
        st.spec = { lw = L.lw, lh = L.lh, crop = 24 * s, fw = 60 * s, key = "zone" }
    elseif k == "inset" then
        st.spec = { lw = L.lw, lh = L.lh, crop = 12 * s, fw = 40 * s, key = "inset", tm = e.node.m and e.node.tm or nil }
    elseif k == "cell" then
        -- (1.4.0-beta2) a zone's cell: its whole picture through the mask of its land (RetailCells.lua)
        st.spec = { lw = L.lw, lh = L.lh, crop = 0, fw = 0, key = (e.cell.cover or e.cell.citycover) and "cover" or "cell", tm = e.cell.tm }
    elseif k == "globe" then
        -- (1.4.0-beta3) a world's picture: cropped and feathered at its printed frame - past its edge it fades softly into
        -- space once its circle has opened past the picture
        st.spec = { lw = L.lw, lh = L.lh, crop = GLOBE_CROP * s, fw = GLOBE_FW * s, key = "globe" }
    elseif k == "portal" then
        -- ((1.4.0-beta5) no tile of its own - RetailTree.lua tm, tools/retail/build_tree.py: its places draw their land)
        st.spec = { lw = L.lw, lh = L.lh, crop = 0, fw = 0, key = "plain", tm = e.node.tm }
    elseif k == "root" then
        -- (1.4.0-beta3: its last column and row reach its edge - the floor everywhere: RetailTiles.lua GridItem's full)
        st.spec = { lw = L.lw, lh = L.lh, crop = 0, fw = 0, key = "root", full = true }
    else
        st.spec = { lw = L.lw, lh = L.lh, crop = 0, fw = 0, key = "plain", tm = (k == "cont") and e.node.tm or nil }
    end
    TL.SetSpec(st.base, st.spec)
    local mfile = (k == "cell" and e.cell.m) or ((k == "cont" or k == "inset") and e.node.m) or nil
    if mfile then
        local m = TL.Mask(st.base, mfile)
        m:ClearAllPoints()
        local cv = k == "cell" and e.cell.cover
        if cv then
            -- ((1.4.0-beta3) a home's cover: soft.tga over the cover's rect - RetailCells.lua HOME_COVERS)
            m:SetPoint("TOPLEFT", st.base.f, "TOPLEFT", cv.d[1], -cv.d[2])
            m:SetSize(cv.d[3] - cv.d[1], cv.d[4] - cv.d[2])
        else
            m:SetPoint("TOPLEFT", st.base.f, "TOPLEFT", 0, 0)
            m:SetSize(L.lw, L.lh)
        end
        st.base.mask = m
        if (k == "cont" or k == "inset") and ns.retailStamp then ns.retailStamp.masks[e.id] = tostring(m.answer) end
        MaskRefused(e, m)
    elseif k == "globe" and e.node.c then
        -- (1.4.0-beta2) the add-on's round mask, its edge transparent: CLAMP spreads nothing beyond its square, so the
        -- picture needs no clipping frame (1.4.0-beta1 masked Blizzard's 130924 - opaque at its edge - inside a clipping
        -- host: in game such a picture drew nothing)
        local m = TL.Mask(st.base, CIRCLE)
        st.base.mask = m
        st.circle = m
        MaskRefused(e, m)
    elseif st.box then
        -- ((1.4.0-beta3) the soft opening box - BoxMask)
        local m = TL.Mask(st.base, SOFT)
        st.base.mask = m
        MaskRefused(e, m)
    end
    -- ((1.4.0-beta13) a continent's too, where it has any - the Broken Isles' two; Blizzard's pin drew them over ours only
    -- with Blizzard's map on that continent: RetailPins.lua hides it)
    if (e.mapType == 3 and (k == "zone" or k == "inset" or k == "cell") and not (e.cell and (e.cell.cover or e.cell.citycover)))
        or (k == "cont" and #TL.Pieces(e.id, L) > 0) then
        st.top = PartOf(sh, "top")
        TL.SetSpec(st.top, { lw = L.lw, lh = L.lh, crop = st.spec.crop, fw = st.spec.fw, key = "top" })
        if k == "cell" and st.base.mask then
            -- (its explored pieces through the same cell: a mask of the top's own frame, laid as the base's)
            local mt = TL.Mask(st.top, e.cell.m)
            mt:ClearAllPoints()
            mt:SetPoint("TOPLEFT", st.top.f, "TOPLEFT", 0, 0)
            mt:SetSize(L.lw, L.lh)
            st.top.mask = mt
        elseif st.box then
            st.top.mask = TL.Mask(st.top, SOFT) -- ((1.4.0-beta3) its explored pieces through the same box: BoxMask)
        elseif (k == "inset" or k == "cont") and st.base.mask then
            -- ((1.4.0-beta4's fixes) an inset's explored pieces through its land mask, as a cell's through its cell)
            local mt = TL.Mask(st.top, e.node.m)
            mt:ClearAllPoints()
            mt:SetPoint("TOPLEFT", st.top.f, "TOPLEFT", 0, 0)
            mt:SetSize(L.lw, L.lh)
            st.top.mask = mt
        end
    end
    -- ((1.4.0-beta14) a land zone's small picture: RetailLodData.lua, tools/retail/build_lod.py - PlanAlphas's LodMode)
    local lod = (k == "cell" or k == "inset") and ns.RETAIL_LOD and ns.RETAIL_LOD[(e.cellOf or e).id]
    if lod and st.top and st.base.mask and L.files[1] == lod.f1 and not (e.cell and (e.cell.pt or e.cell.si or e.cell.ph or e.cell.cover or e.cell.citycover)) then
        st.lod = PartOf(sh, "lod")
        TL.SetSpec(st.lod, { lw = L.lw, lh = L.lh, crop = 0, fw = 0, key = "lod" })
        -- (through what its picture goes through: a cell's mask, an inset's land or its soft opening box - BoxMask; its file set when it is
        -- first drawn, within the frame's budget - FillStage: a band of 30 zones came in with a mask more each, 97 set in a frame)
        st.lodMask = (k == "cell" and e.cell.m) or e.node.m or SOFT
        -- (its tiles over the picture's layer px, 256 art px each, the last ones part of their file)
        local items, kx, ky = {}, L.lw / lod.w, L.lh / lod.h
        local n = 0
        for j = 0, math.ceil(lod.h / 256) - 1 do
            for i = 0, math.ceil(lod.w / 256) - 1 do
                n = n + 1
                local w, h = math.min(256, lod.w - i * 256), math.min(256, lod.h - j * 256)
                items[n] = { i * 256 * kx, j * 256 * ky, (i * 256 + w) * kx, (j * 256 + h) * ky, w / 256, h / 256,
                    LOD_DIR .. (e.cellOf or e).id .. "_" .. n .. ".blp", 0 }
            end
        end
        st.lodItems, st.lodData = items, lod
    end
    stages[e] = st
    return st
end

-- Every texture of the stage back to its parts' pools; the stage forgotten, its frames to the next one (not while it is
-- planned or filled this frame: RetailRender only releases those not in use).
local PART_NAMES = { "base", "top", "lod" }
local function ReleaseStage(st)
    for i = 1, 3 do
        local p = st.sh[PART_NAMES[i]]
        if p then
            TL.Release(p)
            p.f:Hide()
            p.f.pVis = false
            p.visAt, p.visTick, p.hidT, p.hidClosed = nil, nil, nil, nil
        end
    end
    st.host:Hide()
    st.hostVis = false
    stages[st.e] = nil
    if st.e.kind == "zone" then zoneStages = zoneStages - 1 end
    local list = shells[st.shellKey] or {}
    shells[st.shellKey] = list
    list[#list + 1] = st.sh
    TL.evicted = TL.evicted + 1
end

---------------------------------------------------------------------------
-- Planning a frame: which nodes draw and how much (PlanNode, Plan)
---------------------------------------------------------------------------
-- (1.4.0-beta2, rule 3) Is the picture under entry e there - its stage drawn last frame at alpha 1 with its tiles in view
-- loaded? Walks up past maps not drawn whole; the Cosmic map is always there. own: e's own picture.
-- (A picture placed at alpha 0 under a confirmed cover - rule 2 - is drawn: shown, its own alpha 1, loaded.)
local function ParentReady(e, own)
    local p = own and e or ((e.cellOf and e.cellOf.pe) or (e.home and ns.maps[e.home]) or e.pe)
    local guard = 0
    while p and guard < 12 do
        local ps = stages[p]
        if ps and ps.drawn == F.tick - 1 and (ps.shownA or 0) >= 0.999 then
            return ps.vpx ~= nil and TL.LoadState(ps.base, F.now, ps.vpx) ~= "wait"
        end
        p, guard = p.pe, guard + 1
    end
    return true
end
function Render:PictureThere(e) return ParentReady(e, true) end
-- (1.4.0-beta3, RetailImagery.lua: a world's imagery goes out once its drawn picture is loaded again - fading back in over it)
function Render:PictureLoaded(e)
    local st = stages[e]
    return st ~= nil and st.loadedAt ~= nil
end

-- (a switch - o: a stage, or a band of cells -: on at on, off below off; a crossfade of SWITCH_FADE.
-- 1.4.0-beta1: every picture's fade - no zoom-driven fade rests half-way - and each takes its whole SWITCH_FADE coming
-- in, as Render.lua's PicFade never ran faster. Going out it catches up only once zoomed out well past its off.
-- 1.4.0-beta2: it comes in only once its picture is there (ready: its tiles in view loaded, or off screen - rule 1) and
-- goes out only over its parent's (e, own: ParentReady - rule 3); (1.4.0-beta4's fixes) no PARENT_WAIT: as long as the
-- parent takes)
local function Switch(o, zc, on, off, ready, e, own)
    -- ((1.4.0-beta16) not run last frame - its map far from the view, or switched off: from where its zoom is, as a band's. A fade it left half way, or an alpha the zoom has since passed, would show
    -- as it comes into the view)
    if o.swT and o.swT < F.tick - 1 then
        if zc >= on then o.sa, o.sw = 1, true elseif zc < off then o.sa, o.sw = 0, false end
    end
    local was = o.sw
    o.swT = F.tick
    if zc >= on then o.sw = true elseif zc < off then o.sw = false end
    if o.sw == false and was ~= false then o.offAt = F.now end
    local a = o.sa or 0
    local s = F.swStep
    if o.sw then
        if ready or TEST.nofade then a = math.min(1, a + s) end
    elseif a > 0 then
        if e and not TEST.nofade and not ParentReady(e, own) then
            s = 0
        else
            local want = 1 - Clamp01(math.log(off / math.max(zc, 1e-9)) / SWITCH_BAND)
            if a - want > s and zc < off * 0.7 then s = math.min(a - want, F.capStep) end
        end
        a = math.max(0, a - s)
    end
    if (o.sw and a < 1) or (not o.sw and a > 0) then F.busy = true end
    o.sa = a
    return a
end

local function OnScreen(e)
    return e.x1 > F.vx0 and e.x0 < F.vx1 and e.y1 > F.vy0 and e.y0 < F.vy1
end

-- (1.4.0-beta3) Is entry e within NEAR views of the view, or in the view the motion heads for (F.pv: a pan's heading, a
-- wheel's destination - Core.lua's prefetch)? Planned there, it is shown and loaded at its alpha (clipped), so a drag
-- brings it into the view at once - WoW Forever keeps a part's loaded state across hides, and builds a city's patch
-- within one view (Render.lua NearScreen).
local function Near(e)
    if e.x1 > F.nx0 and e.x0 < F.nx1 and e.y1 > F.ny0 and e.y0 < F.ny1 then return true end -- (the view grown by NEAR: Draw)
    local p = F.pv
    return p ~= nil and e.x1 > p[1] and e.x0 < p[3] and e.y1 > p[2] and e.y0 < p[4]
end

-- ((1.4.0-beta14) entry e's own zoom at zoom z of the world, this view: the levels' switches above)
-- ((1.4.0-beta15) kept per view size: a ratio of two maps' sizes, whatever the camera)
local function OwnAt(e, z)
    local c = e.ownC
    if not c or c.W ~= F.W or c.H ~= F.H then
        c = { W = F.W, H = F.H }
        e.ownC = c
    end
    local o = c[z]
    if not o then
        o = ns.ZoomOf(F.v, e, ns.WidthForZoom(F.v, ns.maps[ns.WORLD_MAP_ID], z))
        c[z] = o
    end
    return o
end

-- (1.4.0-beta4) Does zone entry e draw its whole picture? Only with /emap cells off (each zone's whole picture: the
-- player's choice). With the cells a zone is its cell (C.Celled: WoW Forever's WholePicture, design rule 10), a city, a
-- capital or a nested zone its patch (RetailCells.lua: the city plan or the zone's own shape - WoW Forever draws a city's
-- rectangle only with the focus, and the focus draws nothing here), a zone with neither its parent's picture there until
-- its cut-out exists (data: tools/retail/build_cells.py) - never a rectangle with its margins. 1.4.0-beta3 drew the
-- focused zone's whole picture - the view's centre decided which (Vashj'ir's in photo 6, Blizzard's own in photo 7, at
-- one zoom); (1.4.0-beta4's reviews) 1.4.0-beta4 drew every zone with a patch whole by its own zoom (C.Patched: a patch
-- taken for a city plan) - the Cape of Stranglethorn's banner and frame corner, the Echo Isles' banner, Dornogal's
-- rectangle ending in a straight edge across its road.
local function Whole(e)
    return ns.db ~= nil and ns.db.cells == false
end

-- (a band's switch, once a frame)
local function StepBand(b, zp, con, coff, e)
    if b.t == F.tick then return end
    -- (a band not run last frame - its continent not planned - starts from where its zoom is: its cells were not
    -- drawn meanwhile)
    if b.t ~= F.tick - 1 then b.sa, b.sw, b.inAt = (zp >= con) and 1 or 0, nil, nil end
    b.t = F.tick
    b.a = Switch(b, zp, con, coff, true, e)
    -- ((1.4.0-beta9) out: in again together, once all are there - BandFade)
    if b.a <= 0 then b.inAt = nil end
end
-- ((1.4.0-beta16) the bands of a map far from the view, its cells not walked: they run on, each by the zoom alone)
local function StepFarBands(e)
    local list = ns.RetailCells and ns.RetailCells.BandList(F.v, e)
    if not list then return end
    for i = 1, #list do
        local B = list[i]
        local b = F.bands[B.key]
        if not b then
            b = { sa = 0 }
            F.bands[B.key] = b
        end
        StepBand(b, ns.ZoomOf(F.v, B.bp, F.vw), B.on, B.off, B.cell)
    end
end

-- (1.4.0-beta2: is stage st's picture there - loaded; or nothing of it on screen to wait for)
-- ((1.4.0-beta3) ih: the minimap imagery stands for it - nothing of it to wait for: RetailImagery.lua)
local function Ready(st, on, ih) return ih or st.loadedAt ~= nil or not on end

local Plan -- (recursive, below)

-- One node this frame: its stage's planned alpha (a, before loading), whether its art loads, and the geometry it draws
-- with; its children after it. dn: does its parent draw.
local function PlanNode(e)
    local v = F.v
    local k = e.kind
    local on = OnScreen(e)
    -- (1.4.0-beta3, WoW Forever parity: F1 - F3) a picture's switch runs by its zoom alone, on screen or not; it is loaded
    -- - shown at its alpha, clipped - while within NEAR of the view: a drag brings it in loaded, at the alpha of the
    -- rest. (1.4.0-beta2 fed a switch the zoom only while on screen and loaded only there: each picture a drag brought in
    -- waited for its load, then faded from 0 while those in view stood at 1 - the player's "choppy look")
    -- ((1.4.0-beta4) the worlds and continents too - 1.4.0-beta3 loaded those only on the screen: a drag brought each
    -- into the view still loading, its load fade a step of its look - a continent sliding in faded up from nothing over
    -- its world's drawing of it; the budget trims the off-screen ones first - BudgetAhead, Budget, Evict)
    local near = on or (k ~= "root" and Near(e))
    -- (1.4.0-beta1) the maps placed under it on screen though its own picture is not (RetailSpace.lua e.ext: the Eastern Kingdoms' east
    -- beyond Azeroth's picture)
    local nearx = near or (e.ext ~= nil and Near(e.ext))
    local st = stages[e]
    -- ((1.4.0-beta16) No stage and far from the view: nothing below would do anything. The player's stamp on 1.4.0-beta15: Draw 3.16 ms a frame though it asks the client a
    -- fifth of what it did - the time is the Lua, every map and every cell of every continent walked each frame, on the other side of the world too. A cell goes on to its
    -- band's switch: one of them runs it each frame)
    if not st and not nearx and k ~= "root" and k ~= "cell" then return end
    local zc = (k ~= "cell" or st) and ns.ZoomOf(v, e, F.vw)
    local a, load = 0, false
    -- (1.4.0-beta3, the minimap imagery - RetailImagery.lua) under its world's imagery switching on, this picture fades
    -- out over it (ik: its alpha's factor, the imagery's holders lying under our pictures); where the imagery stands for
    -- it whole, it is planned at alpha 0 (its switch runs on, ready - nothing of it to wait for), its children as it would
    -- draw them (the capitals underground, the floors, their patches keep their maps over the imagery)
    local ik = k ~= "cell" and (F.imgOn and IMG:Fade(e) or 1)
    local ih = ik and ik <= 0
    if k == "root" then
        a, load = 1, true
        st = st or Stage(e)
    elseif k == "globe" then
        load = near and zc >= GLOBE_LOAD
        if load or (nearx and zc >= GLOBE_LOAD) or (st and st.sa > 0) then
            st = st or Stage(e)
            local gon = OwnAt(e, WORLD_ON)
            if st then a = Switch(st, zc, gon, gon * SWITCH_OFF, Ready(st, on, ih), e) * math.min(1, F.parentA or 1) end
        end
    elseif k == "cont" then
        -- ((1.4.0-beta4's fixes, the player's photo 1: "bunch of missing zones in east king") a continent placed on a
        -- continent - Quel'Thalas on the Eastern Kingdoms - is that continent's land: it switches and loads by that one's
        -- zoom, with it. 1.4.0-beta4 switched it by its own (0.84 of its fit, the Eastern Kingdoms' 2.27): below that the
        -- north was the Eastern Kingdoms' own drawing of it, blobs)
        local be = (e.pe and e.pe.kind == "cont") and e.pe or e
        local bzc = zc
        if be ~= e then bzc = ns.ZoomOf(v, be, F.vw) end
        local x1 = OwnAt(be, CONT_ON)
        local x0 = x1 * SWITCH_OFF
        local lz = x1 * 0.8
        load = near and bzc >= lz
        if load or (nearx and bzc >= lz) or (st and st.sa > 0) then
            st = st or Stage(e)
            -- ((1.4.0-beta4) its land mask's picture only, by its zoom: never its whole picture, never off for a focused
            -- one over it - 1.4.0-beta1's continent on the focus chain drew its sea, margins, compass and title from 0.90 of
            -- its fit while the view's centre lay on it: Northrend's in photo 5, not in photo 4, at one zoom)
            if st then a = Switch(st, bzc, x1, x0, Ready(st, on, ih), e) * math.min(1, F.parentA or 1) end
        end
    elseif k == "inset" or k == "portal" then
        -- ((1.4.0-beta7, the player on 1.4.0-beta6: "they expose at different zoom levels in the maelstrom. all 3 areas
        -- should expose at the same zoom level") a place on a portal - the Lost Isles, Kezan, Deepholm, the swirl - is the
        -- portal's land, as a continent's is its own (the portal draws no picture: 1.4.0-beta5): it switches and loads by
        -- the portal's zoom, with it - all four at once, as a continent of the portal's size comes in (Northrend's,
        -- Pandaria's). 1.4.0-beta6 switched each by its own zoom: Kezan from about 6x the world, Deepholm from 14x)
        local be = (k == "inset" and e.pe and e.pe.kind == "portal") and e.pe or e
        local bzc = zc
        if be ~= e then bzc = ns.ZoomOf(v, be, F.vw) end
        local sw = OwnAt(be, be.kind == "portal" and CONT_ON or ns.RetailCells.BAND_WORLD)
        local lz = sw * 0.8
        load = near and bzc >= lz
        if load or (nearx and bzc >= lz) or (st and st.sa > 0) then
            st = st or Stage(e)
            if st then
                -- (1.4.0-beta2) one lying on a zone is drawn on that zone's picture: with it - its alpha times the zone's.
                -- A zone's children are planned only while it draws, and as the focus left The Coiled Isle the Vaults of
                -- Atal'Utek, at 0.72 and at 1, went out in one frame with it. ((1.4.0-beta4) every picture so: times its
                -- parent's - PlanNode's end)
                a = Switch(st, bzc, sw, sw * SWITCH_OFF, Ready(st, on, ih), e) * math.min(1, F.parentA or 1)
                -- ((1.4.0-beta4) its box or circle opens to the whole picture by its own zoom alone - 1.4.0-beta1 opened it
                -- only while the view's centre lay on it)
                st.open = Smooth((bzc - sw) / (OPEN_END - sw))
            end
        end
    elseif k == "zone" then
        -- ((1.4.0-beta4) a city's own map by its own zoom alone, wherever the view: Whole)
        if Whole(e) then
            local zL = 0.25 / ns.FitOf(v, e)
            local lz = math.max(0.60, math.min(zL, 0.78))
            load = near and zc >= lz
            if load or (nearx and zc >= lz) or (st and st.sa > 0) then
                st = st or Stage(e)
                if st then a = Switch(st, zc, ZONE_ON, ZONE_ON - 0.04, Ready(st, on, ih), e) * math.min(1, F.parentA or 1) end
            end
        elseif st and st.sa > 0 then
            a = Switch(st, 0, ZONE_ON, ZONE_ON - 0.04, Ready(st, on, ih), e) * math.min(1, F.parentA or 1) -- (its cell drawn now: out)
        end
    elseif k == "cell" then
        -- (1.4.0-beta2) a zone's cell (RetailCells.lua): by its continent's zoom, on at CELL_ON (or later where the zone's
        -- art is still too coarse there; 1.4.0-beta3: no later than its zone's whole picture came), loaded from CELL_LOAD.
        -- (1.4.0-beta3, WoW Forever parity: F1) the cells of one band of a continent share one switch, whatever the
        -- screen (WoW Forever's lod): a cell a drag brings into the view takes the band's alpha at once - times its own
        -- load fade, only if it comes in not loaded - and with the continent's own (a cell lies on its picture)
        local C = ns.RetailCells
        local con, coff, cload, bkey = C.Band(F.v, e, F.vw)
        -- ((1.4.0-beta3) a home's cover: by its home's zoom; (1.4.0-beta16) asked once for the cells of one map, planned together)
        local bp = e.bandOf or e.cellOf.pe
        local zp = F.zpV
        if F.zpE ~= bp then
            zp = ns.ZoomOf(v, bp, F.vw)
            F.zpE, F.zpV = bp, zp
        end
        local key = bkey or C.BandKey(e, con)
        local b = F.bands[key]
        if not b then
            b = { sa = 0 }
            F.bands[key] = b
        end
        local child = e.cell.picture and e.cell.cover.child and ns.maps[e.cell.cover.child]
        if child then
            -- ((1.4.0-beta4's fixes) a picture cover in step with a child's switch - the Cosmic map's ribbon of a world, with
            -- that world (its stage's switch last frame: the root's covers are planned before its worlds), as WoW Forever's
            -- banner covers come with their city; it loads while the child does)
            local cs = stages[child]
            b = F.coverB -- (read here alone: no table a frame)
            b.sa, b.sw = cs and cs.sa or 0, cs and cs.sw
            b.a = b.sa
            cload = (cs and (cs.load or b.sa > 0)) and -1 or math.huge
        else
            StepBand(b, zp, con, coff, e)
        end
        load = near and zp >= cload
        if load or (st and st.sa > 0) or (near and b.a > 0.002) then
            st = st or Stage(e)
            if st and not st.dead then
                st.sa, st.sw = b.a, b.sw
                st.band = (not child) and b or nil
                a = b.a * math.min(1, F.parentA or 1)
                -- ((1.4.0-beta14) a band going out draws only the cells it already draws: on a fast zoom out the view grew over
                -- every zone of the world while they faded, 3,413 drawn at 1.0x in the player's session - the heaviest frames)
                if not child and b.sw == false and not (st.placed == F.tick - 1 and (st.placedA or 0) > 0) then a = 0 end
            elseif st then
                st.sa = 0
            end
        end
        -- ((1.4.0-beta16) its band's switch run: no stage, nothing more to do)
        if not st then return end
        zc = ns.ZoomOf(v, e, F.vw)
        ik = F.imgOn and IMG:Fade(e) or 1
        ih = ik <= 0
    end
    -- ((1.4.0-beta3) the imagery stands for it: at alpha 0, nothing loads - but a world's own picture near the zoom its
    -- imagery goes at (it comes back over the imagery as you zoom out, RetailImagery.lua CutZoom: loaded already); its
    -- children as it would draw them - aDraw)
    local aDraw = a
    if ih then
        a = 0
        if not (k == "globe" and zc and zc < 1.25) then load = false end
    elseif ik < 1 then
        a = a * ik
    end
    -- ((1.4.0-beta6, the player on 1.4.0-beta5: "background map fog") Azeroth's picture switches off - the engine's 0.3 s
    -- crossfade, as every switch - once magnified past MAG1 screen px an art px, back on below MAG0, over its plain sea: its
    -- space fill, right under it (SpaceFill: whole from just past the world's fit); its children as it draws them (aDraw).
    -- Where no continent's or zone's picture lies, the view deep in showed its 3840-px picture blown up 13 times and more:
    -- a mottled fog between Argus's islands, KUL TIRAS's letters a screen high below them (88.webp). Azeroth only: its land
    -- is its continents' pictures; Outland's, Draenor's and the Shadowlands' own pictures are the only land of some of
    -- their places (Tazavesh, the Veiled Market - no picture of its own: retailwalk_shadowlands's rest on it drew nothing
    -- but the plain sea). (Switch by art px a screen px, 1 / the magnification: on at or above 1 / MAG0)
    if k == "globe" and e.id == ns.WORLD_MAP_ID and e.node.a and st then
        local m = (e.x1 - e.x0) * F.ppx / e.node.a[1]
        st.mag = st.mag or { sa = 1, sw = true }
        a = a * Switch(st.mag, 1 / math.max(m, 1e-9), 1 / MAG0, 1 / MAG1, true)
    end
    -- ((1.4.0-beta16) a stage far from the view and not shown takes no part in this frame's walks: 79 stages each frame after a tour of the world, a dozen in the view)
    if st and (nearx or st.hostVis) then
        st.zc, st.planA, st.load, st.onScreen, st.near = zc, a, load, on, near
        st.planT = F.tick
        st.imgHid = ih or nil
        order[#order + 1] = st
        -- ((1.4.0-beta6) an inset on an inset - the Antoran Wastes on Argus: its parent's picture dims as it comes in -
        -- PlaceStage, PLACES_DIM; its parent was planned before it this frame. (1.4.0-beta13) On an overview map alone
        -- (UiMap type under a zone's: Argus's printed islands stand for its places): Voidstorm is land, and its whole
        -- picture darkened at 32x as Val and Naigtal came in, on the screen or not - the player on 1.4.0-beta12, "changes
        -- tine between areas depnding on zoom and it isnt relitive to area")
        local ps = k == "inset" and e.pe and e.pe.kind == "inset" and (e.pe.mapType or 3) < 3 and stages[e.pe]
        if ps then
            if ps.kidT ~= F.tick then ps.kidT, ps.kidA = F.tick, 0 end
            if a > ps.kidA then ps.kidA = a end
        end
    end
    -- the children of a node that draws (the root always); F.parentA: its planned alpha - theirs is times it.
    -- ((1.4.0-beta4) and of one switched on, its picture still loading (rule 1: it comes in once there): its children
    -- load meanwhile, at alpha 0 - times its 0 -, so the chain loads at once and comes in with it. 1.4.0-beta1 -
    -- 1.4.0-beta3 planned a node's children only once it drew: each level's load began after its parent's - opening the
    -- map at a zone loaded the world, then the continent, then the cells, one after another; the harness's load=30 had
    -- Kalimdor still loading a second after the settle at the Northern Barrens - retailplaces's doorclick)
    local coming = st ~= nil and st.swT == F.tick and st.sw == true
    -- ((1.4.0-beta16) and only near the view - e.ext holds every map under it: at the zones' zoom every continent's switch is on, and all their cells were walked each frame,
    -- 300 and more. Their bands run on without them: StepFarBands)
    if k == "root" or (k ~= "cell" and (aDraw > 0.002 or coming)) then
        if k == "root" or nearx then
            local pa = F.parentA
            F.parentA = aDraw
            Plan(e)
            F.parentA = pa
        else
            StepFarBands(e)
        end
    end
end

local function ByArea(a, b)
    if a.area ~= b.area then return a.area > b.area end
    return a.id < b.id
end

-- The children of e in drawn order: (1.4.0-beta2) the zone cells of a continent that has them, continents and worlds
-- (the larger below), the zones that draw (the larger below), the link children (insets, portals: above every geometric
-- sibling - the review, point 2).
-- ((1.4.0-beta16) e's children by what Plan asks of them, made once - until the maps the game shows change: three walks over all of them for each map planned, each frame)
local function KidsOf(e)
    local kids = ns.SpaceKids(e)
    if not kids then return nil end
    local c = e.kidC
    if c and c.kids == kids and c.gen == ns.SpaceGen then return c end
    c = { kids = kids, gen = ns.SpaceGen, big = {}, zones = {}, links = {} }
    for _, m in ipairs(kids) do
        if m.kind == "globe" or m.kind == "cont" then c.big[#c.big + 1] = m end
        if m.kind == "zone" then c.zones[#c.zones + 1] = m end
        if m.link then c.links[#c.links + 1] = m end
    end
    e.kidC = c
    return c
end
Plan = function(e)
    local K = KidsOf(e)
    if not K then return end
    -- (1.4.0-beta2: a continent's cells first - under the continents placed on it: Quel'Thalas over the Eastern Kingdoms'
    -- Plaguelands)
    local cells = ns.RetailCells and ns.RetailCells.For(e)
    if cells then
        for i = 1, #cells do PlanNode(cells[i]) end
        -- (1.4.0-beta3) the insets lying on a zone drawn as its cell (WholePicture: its whole picture never draws, and a
        -- zone's children were planned only while it drew - at rest on the Vaults of Atal'Utek, The Coiled Isle's cell lay
        -- over Blizzard's map of it, ours of it never planned): on the cell, at its alpha, above every cell of the map
        for i = 1, #cells do
            local c = cells[i]
            local st = stages[c]
            local zk = not c.cell.pt and not c.cell.cover and st and st.planT == F.tick and (st.planA > 0.002 or st.imgHid) and KidsOf(c.cellOf)
            if zk then
                local pa = F.parentA
                F.parentA = st.planA
                local links = zk.links
                for j = 1, #links do PlanNode(links[j]) end
                F.parentA = pa
            end
        end
    end
    local big = K.big
    for i = 1, #big do PlanNode(big[i]) end
    -- (1.4.0-beta4) the zones that draw their whole picture (Whole) - by their own zoom, the focus nowhere - and one going
    -- out: the larger below, by area then id (never the order pairs() gives; a city above its home)
    -- ((1.4.0-beta16) with the cells on no zone has a stage of its own: zoneStages, Stage)
    if zoneStages > 0 or Whole() then
        local list, n = {}, 0
        for _, m in ipairs(K.zones) do
            if Whole(m) or (stages[m] and stages[m].sa > 0) then
                n = n + 1
                list[n] = m
            end
        end
        table.sort(list, ByArea)
        for i = 1, n do PlanNode(list[i]) end
    end
    local links = K.links
    for i = 1, #links do PlanNode(links[i]) end
end

---------------------------------------------------------------------------
-- Alphas, covers, tiles (PlanAlphas, PlanCovers)
---------------------------------------------------------------------------
-- The view centred on (x, y), vw wide, in stage st's layer px (into out); ViewPx: the camera's, kept as st.vpx.
local function ViewRect(st, x, y, vw, out)
    local e, L = st.e, st.L
    local ppx, ppy = ns.PixelsPerUnit(F.v, vw)
    local hx, hy = F.W / 2 / ppx, F.H / 2 / ppy
    local sx, sy = L.lw / (e.x1 - e.x0), L.lh / (e.y1 - e.y0)
    out[1], out[2], out[3], out[4] = (x - hx - e.x0) * sx, (y - hy - e.y0) * sy, (x + hx - e.x0) * sx, (y + hy - e.y0) * sy
    return out
end
-- ((1.4.0-beta16) up to four times a stage each frame, the same view: once)
local function ViewPx(st, x, y, vw)
    if st.vpx and st.vpxX == x and st.vpxY == y and st.vpxW == vw and st.vpxV == F.W and st.vpxH == F.H and st.vpxG == ns.SpaceGen then return st.vpx end
    local out = ViewRect(st, x, y, vw, st.vpx or {})
    st.vpx = out
    st.vpxX, st.vpxY, st.vpxW, st.vpxV, st.vpxH, st.vpxG = x, y, vw, F.W, F.H, ns.SpaceGen
    return out
end

-- The part's load fade: 0 until its tiles in view are loaded (TL.LoadState - shown meanwhile at alpha 0:
-- PlacePart), then up over LOAD_FADE (once - later tiles just appear, the chain under them meanwhile). (1.4.0-beta2: the
-- give-up counts from the textures' first visible frame, never from SetTexture.) (1.4.0-beta4) WoW Forever's own rule
-- (Render.lua LoadFade) - no group: a group of every part on the screen (Blizzard's TextureLoadingGroup), tried here,
-- held what had loaded at 0 behind the rest - with the client loading a few files a frame and letting hidden ones go,
-- the map opened again at Westfall waited past a second, a bubble's flight started from nothing (retailparty:rate=4).
-- 1.4.0-beta2's WANT_GIVEUP (a wanted part never shown counted loaded after 3 s) went - a part waits on what is shown only.
local function LoadFade(st, part, key)
    if not st[key] then
        -- ((1.4.0-beta14) off the screen, out of the viewport's reach: nothing of it shown, nothing to wait for - and not there yet)
        if not st.onScreen and part.win and part.win[1] > part.win[3] then return 0 end
        -- (1.4.0-beta3: a picture planned off the screen, near it, waits for every texture of its window - it comes into
        -- the view loaded; on screen for those in view)
        local ls = TL.LoadState(part, F.now, st.onScreen and st.vpx or nil)
        if ls == "wait" then
            F.busy = true
            return 0
        end
        st[key] = F.now
    end
    if TEST.nofade then return 1 end -- (1.4.0-beta2: /emap test nofade - RetailWhy.lua)
    local x = Smooth((F.now - st[key]) / LOAD_FADE)
    if x < 1 then F.busy = true end
    return x
end

-- ((1.4.0-beta9, the player on 1.4.0-beta8: "all zones need to become visable at the same time" - 97.webp, at 5.69x of
-- the world: Dun Morogh's and the Wetlands' maps in, Loch Modan's, the Badlands', Searing Gorge's and the Burning
-- Steppes' still the Eastern Kingdoms' drawing) The load fade of band b's cells: 0 while any of them on the screen still
-- loads (PlanAlphas: b.waitT), then up over LOAD_FADE from the frame the last one is there - all at once, WoW Forever's
-- lod: a continent's cells one picture. 1.4.0-beta2 - 1.4.0-beta8 let each cell in by its own load fade: the band
-- switched on, the zones came one by one as the client loaded them. Once the band is in (b.inAt, until it is out -
-- PlanNode), a cell a drag brings in comes by its own load fade, the rest stand.
local function BandFade(b)
    if not b.inAt then
        if b.waitT == F.tick then return 0 end
        b.inAt = F.now
    end
    if TEST.nofade then return 1 end
    local x = Smooth((F.now - b.inAt) / LOAD_FADE)
    if x < 1 then F.busy = true end
    return x
end

-- Does stage st, drawn at alpha 1 now, cover the whole view with opaque art, its tiles in view confirmed loaded? A picture through a land mask - a continent, a cell - never covers; a world's, a portal's, a
-- zone's or an inset's opaque middle does: inside its crop and feather, its circle past its corners, its box open.
local function Covers(st)
    local e, k = st.e, st.e.kind
    local part, spec = st.base, st.spec
    if k == "cell" or k == "cont" or (k == "inset" and e.node.m) or st.shownA < 0.999 then return false end
    local x0, y0, x1, y1 = e.x0, e.y0, e.x1, e.y1
    if k == "globe" and st.circle and (st.d or 0) < DIAGONAL then return false end
    if k == "zone" or k == "inset" or k == "globe" or k == "portal" then
        if k == "inset" and (st.open or 0) < 0.999 then return false end
        local cx = (spec.crop + spec.fw) / st.L.lw * (x1 - x0)
        local cy = (spec.crop + spec.fw) / st.L.lh * (y1 - y0)
        x0, x1, y0, y1 = x0 + cx, x1 - cx, y0 + cy, y1 - cy
    end
    local tx, ty = 0.5 / F.ppx, 0.5 / F.ppy
    if not (x0 <= F.vx0 + tx and x1 >= F.vx1 - tx and y0 <= F.vy0 + ty and y1 >= F.vy1 - ty) then return false end
    -- (1.4.0-beta2, the review of the seams: and no tile of it in view still fading in - TL.StepLate)
    return (part.inView or 0) > 0 and TL.LoadState(part, F.now, st.vpx) == "ok" and not TL.FadingIn(part, st.vpx)
end

-- (1.4.0-beta3) Before the frame's fills: the pictures planned off the screen, near it, stop being wanted - the most
-- detailed first - while what the wanted ones hold already passes SHOWN_MAX less a frame's new textures (Budget trims
-- what is placed; this keeps the fills from growing live textures for pictures it would only hide: a walk over
-- Zandalar's 3840-px zones reached 7,320 live)
-- ((1.4.0-beta14) Does stage st draw its small picture: a land zone small on the screen - its picture no wider than LOD_ON of its small one's px, back
-- past LOD_OFF - with every explored piece on (Blizzard's call says how many: fog of war stays the game's). At the zones' band a 3,840-px zone is 150 - 350 px
-- wide and its 400 - 500 tiles under 20 px each: the Dragon Isles 1,700 drawn at 5.49x, the player's frames over 2,000 drawn 43 - 62 ms. Over LOD_OFF its tiles
-- come in over it as they load - FillStage: never a hole, either way)
local LOD_ON, LOD_OFF = 1.1, 1.3
local function LodMode(st)
    if not st.lod then return end
    local P = TL.Pieces((st.e.cellOf or st.e).id, st.L)
    if TEST.nolod or (P.np or 0) < st.lodData.np then -- (more: a piece behind a condition, no part of the small picture)
        st.lodOn = false
        return
    end
    local px = (st.e.x1 - st.e.x0) * F.ppx
    if st.lodOn then
        if px > st.lodData.w * LOD_OFF then st.lodOn = false end
    elseif px <= st.lodData.w * LOD_ON then
        st.lodOn = true
    end
end

local function BudgetAhead()
    local n = 0
    for oi = 1, #order do
        local st = order[oi]
        if st.want then n = n + st.base.n + (st.top and st.top.n or 0) + (st.lod and st.lod.n or 0) end
    end
    local room = TL.SHOWN_MAX - TL.NEW_PER_FRAME
    for i = #order, 2, -1 do
        if n <= room then return end
        local st = order[i]
        if st.want and not st.onScreen then
            -- (and not placed: at its alpha the fills would set again what Evict gives back - a churn at rest, the fill
            -- never done: the Northrend walk's driver ran on 3 s after a settle)
            st.want, st.shownA = false, 0
            n = n - (st.base.n + (st.top and st.top.n or 0) + (st.lod and st.lod.n or 0))
        end
    end
end

local function PlanAlphas()
    -- (1.4.0-beta2) wanted: drawn, or loading ahead of its switch (shown at alpha 0 - the client loads only what is
    -- visible); its load state from its first shown frame
    -- (1.4.0-beta3: or near the view - shown at its alpha, clipped, so the client has loaded it when a drag brings it in)
    -- ((1.4.0-beta9) every picture's first: a band's cells come in once all of them on the screen are there - BandFade)
    for oi = 1, #order do
        local st = order[oi]
        if st.onScreen then st.liveOut = nil end -- (1.4.0-beta3: out of the near preload for the live budget - Evict)
        st.want = st.near and (st.load or st.planA > 0.002) and not st.liveOut
        st.loadF = 0
    end
    -- ((1.4.0-beta13) first what the budget leaves out: 1.4.0-beta3 - 1.4.0-beta12 trimmed after the wait below - a picture it
    -- left out, never shown, never loaded, was waited for frame after frame, and the map, standing still, drew on at full rate
    -- wherever the view holds SHOWN_MAX: the heavy maps, explored pieces on - retailzoom's gate.busyRest, the player's "cpu
    -- spiked to 35%" with their stamp's most shown, 3,891, at this limit)
    BudgetAhead()
    for oi = 1, #order do
        local st = order[oi]
        if st.want then
            local vpx = ViewPx(st, F.cx, F.cy, F.vw)
            LodMode(st)
            -- ((1.4.0-beta15) what is in view shown first: the load fade waits for those - RetailTiles.lua's viewport)
            TL.ShowIn(st.base, vpx)
            if st.top then TL.ShowIn(st.top, vpx) end
            if st.lod then TL.ShowIn(st.lod, vpx) end
            st.loadF = LoadFade(st, st.lodOn and st.lod or st.base, "loadedAt")
            if st.band and st.onScreen and not st.loadedAt then st.band.waitT = F.tick end
        end
    end
    for oi = 1, #order do
        local st = order[oi]
        -- (the alpha it was placed with last frame - drawn, or shown at alpha 0 while it loads: two fades at once - a
        -- switch's and a load fade - never step a picture more than STEP_MAX a frame. One plan a game frame (Replace): no
        -- second step in a frame. The map closed: HideAll forgets it)
        local was = (st.placed == F.tick - 1) and st.placedA or nil
        -- ((1.4.0-beta16) as long in time on a slow frame as on a quick one, not in frames: a fast zoom out's heaviest frames took seven frames to fade, 60 ms each)
        local stepMax = math.max(STEP_MAX, (F.ddt or 0) / SWITCH_FADE_MIN)
        st.shownA = 0
        if st.want and st.planA > 0.002 then
            local lf = st.loadF
            if st.band then lf = math.min(lf, BandFade(st.band)) end
            st.shownA = st.planA * lf
        end
        -- (1.4.0-beta1: a picture switching off goes at 0.02 - its last few steps show nothing, and a zoom out fast left
        -- whole pictures at alpha 0.01 counting their textures: 1,113 shown leaving Voidstorm. (1.4.0-beta4) Its aim, before
        -- the step cap: applied after it - at PlaceParts - a picture capped down to 0.02 went on to 0 in the same frame,
        -- STEP_MAX and 0.02 at once: the walks' 0.16 -> 0 at Voidstorm's and K'aresh's cells, each alpha times its
        -- parent's going out with it)
        if st.sw == false and st.shownA <= 0.02 then st.shownA = 0 end
        if was and not TEST.nofade and math.abs(st.shownA - was) > stepMax then
            st.shownA = was + ((st.shownA > was) and stepMax or -stepMax)
            F.busy = true
        end
        st.baseA = st.shownA
        local c = st.e.node.c
        if st.circle and c then
            -- (a globe's or a portal's circle by its own zoom - (1.4.0-beta4) a portal's too: 1.4.0-beta1 opened it only
            -- while the view's centre lay on it)
            local d = c[3] + (c[4] - c[3]) * Smooth((st.zc - c[5]) / (c[6] - c[5]))
            -- (1.4.0-beta1, the picture harness: by the zoom alone a notch's quick start opened a globe's circle past
            -- its picture's corners within two frames - Outland's and Draenor's framed corners popped in at 0.93x; the
            -- circle now moves at most its whole range in CIRCLE_FADE, as a fade's alpha does, and the root under it
            -- stays)
            local cw = st.d
            if cw and F.ddt and st.drawn == F.tick - 1 and not TEST.nofade then
                local s = (c[4] - c[3]) * F.ddt / CIRCLE_FADE
                if d > cw + s then d, F.busy = cw + s, true elseif d < cw - s then d, F.busy = cw - s, true end
            end
            st.d = d
        end
    end
end

-- ((1.4.0-beta10, the player on 1.4.0-beta9: "the instant diamonds are missing for most instances", "when we shows quests
-- and FP's is also not consist across all the zones. this should be unified") How much of each map's own picture is
-- drawn this frame - a zone's by its land cells (or its whole picture: a city, an inset), a continent's, a world's by its
-- own - and how much of the maps that stand for it there: a continent's zones (their cells), a world's continents.
-- Render:MapAlpha - a map's markers (RetailPins.lua: flight masters, points of interest) come and go with its picture,
-- as Blizzard's map shows a map's own pins on that map: every map drawn at once, each its own.
F.mapOwn, F.mapKid = {}, {}
local function PlanMapAlphas()
    local own, kid = F.mapOwn, F.mapKid
    wipe(own)
    wipe(kid)
    for oi = 1, #order do
        local st = order[oi]
        local e, a = st.e, st.shownA or 0
        if a > 0.002 then
            if e.kind == "cell" then
                local z = not (e.cell.cover or e.cell.picture) and e.cellOf or nil
                if z then
                    if a > (own[z] or 0) then own[z] = a end
                    local p = z.pe
                    if p and a > (kid[p] or 0) then kid[p] = a end
                end
            else
                if a > (own[e] or 0) then own[e] = a end
                local p = e.pe
                if e.kind == "cont" and p and p.kind == "globe" and a > (kid[p] or 0) then kid[p] = a end
            end
        end
    end
    F.mapT = F.tick
end

-- (1.4.0-beta2) The pictures under the topmost one that covers the view are marked covered; (1.4.0-beta4, WoW Forever's
-- FindCovers - Render.lua:1996-2012) they are placed at alpha 0, still shown, so loaded (Hidden): nothing of them is seen,
-- the frame the cover stops covering they draw again. Ready (Core.lua hides Blizzard's canvas while detached and ready):
-- the Cosmic map confirmed in view - it lies under everything at alpha 1 - or a confirmed picture covering the view.
local function PlanCovers()
    local cover
    for i = #order, 1, -1 do
        local st = order[i]
        st.covered = nil
        if cover then
            st.covered = true
        elseif st.shownA > 0.002 and Covers(st) then
            cover = i
        end
    end
    F.cover = cover
    local root = order[1]
    dready = cover ~= nil or (root ~= nil and root.e.kind == "root" and root.shownA >= 0.999 and root.vpx ~= nil
        and TL.LoadState(root.base, F.now, root.vpx) == "ok")
        or (F.imgOn and IMG:CoversView()) -- (1.4.0-beta3: the minimap imagery's backdrop over the view - RetailImagery.lua)
end

---------------------------------------------------------------------------
-- Tiles: drawn stages first (deepest first), then the ones that load, then the prefetch
---------------------------------------------------------------------------
-- (1.4.0-beta2, the review of the seams, point 1) Worlds and continents keep their whole picture shown - every tile, so
-- loaded - while they are wanted, and so do pictures of ALL_TILES tiles or fewer (a 1002-px zone's 12): a zoom out grew
-- the view past a window of 0.25 - 0.5 of it a side in about a notch, and with half-second loads up to 89 of Kalimdor's
-- tiles in view were still loading, the picture under them showing round its frame, then popping in. WoW Forever loads
-- each picture whole (Render.lua EmitBaseTiles). The rest - 3840-px zones and insets - keep a window, on a zoom out
-- grown to the view the wheel heads for too (dest: Core.lua's prefetch of a zoom out, Render.PREFETCH_OUT).
-- ((1.4.0-beta15) Only the Cosmic map and a picture of ALL_TILES whole now: a world's and a continent's window lies round the view as a zone's,
-- on a zoom out or a flight grown to where it heads - each new tile loaded before the view reaches it, a coarser picture under it until then;
-- 1.4.0-beta2 - 1.4.0-beta14 asked the client for all 279 of Azeroth's and 150 of each continent near the view)
local ALL_TILES = 16
local winU = {}
-- ((1.4.0-beta15) every so often the margin looked at again - a part's whole window walked, RetailTiles.lua FillTile's touch: the first frame
-- of a motion after a rest finds what the client let go meanwhile, so it is back before the view gets there)
function Render:LookAgainAll() -- (RetailBench.lua, /emap test: a switch of the viewport's)
    for _, st in pairs(stages) do
        for i = 1, 3 do
            local p = st[PART_NAMES[i]]
            if p then p.doneGen, p.doneP = nil, nil end
        end
    end
end
local function LookAgain(p)
    if F.now - (p.lookT or -1e9) >= TL.TOUCH_EVERY then
        p.lookT = F.now
        p.doneGen, p.doneP = nil, nil
    end
end
-- ((1.4.0-beta4) viewOnly: only its window's tiles in view - PlanTiles's first pass, TL.FillView)
local function FillStage(st, budget, x, y, vw, dest, viewOnly)
    local vpx = ViewPx(st, x, y, vw)
    local k = st.e.kind
    local all = k == "root" or st.L.cols * st.L.rows <= ALL_TILES or (TEST.noviewport and (k == "globe" or k == "cont"))
    local win = vpx
    if dest and not all then
        local d = ViewRect(st, dest.x, dest.y, dest.vw, winU)
        d[1], d[2], d[3], d[4] = math.min(d[1], vpx[1]), math.min(d[2], vpx[2]), math.max(d[3], vpx[3]), math.max(d[4], vpx[4])
        win = d
    end
    -- ((1.4.0-beta14) the small picture: its tiles, and once it is there no other of the stage's shown - LodMode)
    if st.lodOn then
        if not st.lod.mask then
            if budget <= 0 then return budget end
            local ml = TL.Mask(st.lod, st.lodMask)
            if not st.box then
                ml:ClearAllPoints()
                ml:SetPoint("TOPLEFT", st.lod.f, "TOPLEFT", 0, 0)
                ml:SetSize(st.L.lw, st.L.lh)
            end
            st.lod.mask = ml
            budget = budget - 1
        end
        st.lod.late = st.loadedAt ~= nil
        TL.Window(st.lod, st.L, vpx, true)
        budget = TL.FillList(st.lod, st.L, st.lodItems, budget, vpx)
        st.lodHold = false
        -- ((1.4.0-beta15) and none of them still fading in - a tile the client let go comes back through its fade: until then the tiles stay, never the coarser picture between)
        if not viewOnly and TL.LoadState(st.lod, F.now) == "ok" and not TL.FadingIn(st.lod) then
            TL.Off(st.base)
            if st.top then TL.Off(st.top) end
        end
        return budget
    end
    -- (tiles that come into the window of a picture shown whole already fade in as they load: TL.StepLate)
    st.base.late = st.loadedAt ~= nil
    local cover = k == "cell" and (st.e.cell.cover or st.e.cell.citycover) and ns.RetailCells.CoverItems(st.e)
    if viewOnly then
        if cover then return budget end
        TL.Window(st.base, st.L, win, all)
        return TL.FillView(st.base, st.L, vpx, budget)
    end
    LookAgain(st.base)
    if cover then
        -- ((1.4.0-beta3) a home's cover: its few items - the home's plain piece stretched over the icon, RetailCells.lua)
        TL.Window(st.base, st.L, vpx, true)
        budget = TL.FillList(st.base, st.L, cover, budget)
    else
        TL.Window(st.base, st.L, win, all)
        budget = TL.FillGrid(st.base, st.L, budget, vpx) -- ((1.4.0-beta4) its tiles in view first: TL.FillView)
    end
    if st.top and budget > 0 then
        local P = TL.Pieces(st.e.cellOf and st.e.cellOf.id or st.e.id, st.L)
        if #P > 0 then
            st.top.late = st.loadedAt ~= nil
            LookAgain(st.top)
            -- ((1.4.0-beta14) a small zone's base whole, its 12 tiles, but its explored pieces by the viewport: 54 of Desolace's)
            if all then
                st.top.win = TL.Window(st.top, st.L, win)
            else
                st.top.win, st.top.winGen = st.base.win, st.base.winGen
            end
            budget = TL.FillList(st.top, st.L, P, budget, vpx)
        end
    end
    if st.base.pending or (st.top and st.top.pending) then F.busy = true end
    -- ((1.4.0-beta14) from the small picture to the tiles: it stays under them until those in view are there)
    if st.lod and st.lod.n > 0 and st.lod.f.pVis then
        local ready = not st.base.pending and TL.LoadState(st.base, F.now, vpx) == "ok" and not TL.FadingIn(st.base, vpx)
            and not (st.top and (st.top.pending or TL.LoadState(st.top, F.now, vpx) ~= "ok" or TL.FadingIn(st.top, vpx)))
        st.lodHold = not ready
    else
        st.lodHold = false
    end
    return budget
end

-- (prefetch: the chain of the most detailed map at where the motion is heading, each that loads there - zones by
-- their load point - in the view it lands on; only stages not filled now: a drawn one keeps its window on the view.
-- 1.4.0-beta2: shown at alpha 0 at their true place (PlaceParts), so the client loads them; at most TL.PRELOAD_SHOW new
-- textures a frame; a flight's landing map and its continent asked of C_Map.RequestPreloadMap once a session, as
-- Blizzard does for the player's map - MapTexturePreloader.lua. (1.4.0-beta4) In every frame: 1.4.0-beta2 skipped it after
-- a frame slower than 33 ms - exactly the frames loading makes slow, so the view the motion headed for loaded late)
local function Prefetch(budget)
    local p = prefetch
    if not p or budget <= 0 then return budget end
    local v = F.v
    local e = ns.DeepestMapAt(p.x, p.y)
    local core = ns.Core
    if core and core.State and core.State() == "fly" and C_Map and C_Map.RequestPreloadMap then
        local q, guard = e, 0
        while q and guard < 3 and q.kind ~= "root" do
            if not preloaded[q.id] and (q.kind == "zone" or q.kind == "cont" or q.kind == "inset") then
                preloaded[q.id] = true
                pcall(C_Map.RequestPreloadMap, q.id)
            end
            q, guard = q.pe, guard + 1
        end
    end
    local left = math.min(budget, TL.PRELOAD_SHOW)
    local guard = 0
    local C = ns.RetailCells
    while e and guard < 12 and left > 0 do
        -- (1.4.0-beta3) a zone drawn as its cell: its cell loads ahead, never its whole picture (WholePicture);
        -- ((1.4.0-beta4's fixes) a city, a capital or a nested zone: its patch)
        local se = e
        if C and e.kind == "zone" and not Whole(e) then
            se = (C.Celled(e) and C.CellEntry(e)) or C.PatchEntry(e) or e
        end
        local st = stages[se]
        if not (st and st.fillT == F.tick) and (se.kind ~= "zone" or Whole(se)) then
            local zc = ns.ZoomOf(v, e, p.vw)
            local zL = 0.25 / ns.FitOf(v, e)
            local need = (e.kind == "root") or (e.kind == "globe" and zc >= GLOBE_LOAD)
                or (e.kind ~= "globe" and zc >= math.max(0.40, math.min(zL, 0.78)))
            if need then
                st = st or Stage(se)
                -- (a stage made here set its mask's file: the frame's budget)
                left = math.min(left, TL.NEW_PER_FRAME - TL.newThisFrame)
                budget = math.min(budget, TL.NEW_PER_FRAME - TL.newThisFrame)
                if st and left > 0 then
                    local before = left
                    left = FillStage(st, left, p.x, p.y, p.vw)
                    budget = budget - (before - left)
                    if st.planT ~= F.tick then pref[#pref + 1] = st end
                    st.prefT = F.tick
                end
            end
        end
        e = e.home and ns.maps[e.home] or e.pe
        guard = guard + 1
    end
    return budget
end

-- The budget of live textures: stages neither planned this frame nor preloaded in the last and not drawn for IDLE_EVICT
-- go, least recently drawn first, down to LIVE_LOW once over LIVE_MAX. (1.4.0-beta2, the review of the seams, point 3:
-- LIVE_MAX a real cap - before this frame's new textures, those not planned nor preloaded go however recently drawn, so
-- the frame's NEW_PER_FRAME fit under it: a tour of every place reached 6,080 live)
-- (1.4.0-beta3, a switch by the zoom alone: a picture off the view keeps its switch - planned, not wanted - and its
-- stage; its textures go back like an unplanned stage's, the stage stays: it is in this frame's plan)
local function Unload(st)
    for i = 1, 3 do
        local p = st.sh[PART_NAMES[i]]
        if p and (p.n > 0 or p.win) then TL.Release(p) end
    end
    st.loadedAt = nil
end
local function Evict()
    local room = TL.LIVE_MAX - TL.NEW_PER_FRAME
    if TL.live <= room then return end
    local list = {}
    for _, st in pairs(stages) do
        if st.e.kind ~= "root" and (st.planT ~= F.tick or not st.want) and (st.prefT or 0) < F.tick - 1 then list[#list + 1] = st end
    end
    table.sort(list, function(a, b) return (a.lastDrawn or 0) < (b.lastDrawn or 0) end)
    for _, st in ipairs(list) do
        if TL.live <= TL.LIVE_LOW then break end
        -- (least recently drawn first: once one was drawn within IDLE_EVICT, so were the rest - only down to the room)
        if (st.lastDrawn or 0) >= F.now - IDLE_EVICT and TL.live <= room then break end
        if st.planT == F.tick then Unload(st) else ReleaseStage(st) end
    end
    -- ((1.4.0-beta14) then the tiles the pictures keep hidden outside their windows - RetailTiles.lua's viewport)
    for _, st in pairs(stages) do
        if TL.FreeHeld(st.base, TL.LIVE_LOW) or (st.top and TL.FreeHeld(st.top, TL.LIVE_LOW)) then return end
    end
    -- (1.4.0-beta3: still over the room - every picture left is wanted -: those planned near the view but off it go, the
    -- most detailed first, and stay out until they come on screen (st.liveOut: not wanted, not filled - they load there
    -- as 1.4.0-beta2's did). Khaz Algar at its zoom 3, its 3840-px cells loaded a view around: 6,011 live)
    for i = #order, 2, -1 do
        if TL.live <= room then return end
        local st = order[i]
        if st.want and not st.onScreen and st.prefT ~= F.tick then
            st.want, st.liveOut, st.shownA = false, true, 0
            Unload(st)
        end
    end
end

local function PlanTiles()
    Evict()
    local budget = TL.NEW_PER_FRAME - TL.newThisFrame
    -- (1.4.0-beta2, the review of the seams, point 1: a zoom out - the prefetch's view wider than this one - grows the
    -- drawn pictures' windows to it too)
    local dest = prefetch and prefetch.vw > F.vw * 1.0001 and prefetch or nil
    -- ((1.4.0-beta4) first what is in view of every picture drawn or wanted, bottom up (TL.FillView), then the windows -
    -- the client loads the oldest request first: a world's or a continent's whole window - 279 tiles of Azeroth's - asked
    -- for before the tiles in view of the pictures over it held those back; retailparty:rate=4's map opened at Orgrimmar
    -- with its city map and Durotar's cells still loading after a second)
    for i = 1, #order do
        if budget <= 0 then break end
        local st = order[i]
        if st.shownA > 0.002 then
            budget = FillStage(st, budget, F.cx, F.cy, F.vw, dest, true)
        elseif st.want then
            -- ((1.4.0-beta16) where the motion heads too, as the pass below: without it a window shrank here and grew there, each frame)
            budget = FillStage(st, budget, F.cx, F.cy, F.vw, dest, true)
        end
    end
    for i = #order, 1, -1 do
        local st = order[i]
        if st.shownA > 0.002 then
            st.fillT = F.tick
            budget = FillStage(st, budget, F.cx, F.cy, F.vw, dest)
        end
    end
    -- ((1.4.0-beta4) the pictures wanted, not drawn yet: a parent before its children - the order they come in (rule 1,
    -- a child's alpha times its parent's: PlanNode), and the order a client loading a few files a frame, the oldest
    -- request first, serves them. The chain planned at once (PlanNode's end) filled from the top down asked for the
    -- cells first: the Cosmic map's tiles waited behind them - retailparty:rate=4's flights started with nothing drawn)
    for i = 1, #order do
        local st = order[i]
        if st.shownA <= 0.002 and st.want then
            st.fillT = F.tick
            budget = FillStage(st, budget, F.cx, F.cy, F.vw, dest)
        end
    end
    budget = Prefetch(budget)
    -- (the live budget: Evict, before the fills - no picture goes by time, IDLE_EVICT)
    if ns.retailStamp and TL.peak > (ns.retailStamp.peak or 0) then ns.retailStamp.peak = TL.peak end
end

---------------------------------------------------------------------------
-- Levels and placing (PlaceParts)
---------------------------------------------------------------------------
-- (1.4.0-beta4, G7 - the in-game probe P4) A part shown again after a hide - its frame or its stage's host: its textures
-- the client reports not loaded now (TL.Reshown) - let go while it was hidden - make its stage wait for them at alpha 0
-- and fade in again; loaded, it shows on. 1.4.0-beta3 decided by a timer (HIDE_GRACE, 0.25 s: hidden longer, it waited
-- whatever the client said). The stamp's reshow counts the parts by how long they were hidden (the map closed apart): how
-- many of their textures the client had let go.
-- ((1.4.0-beta4's fixes, the review of the real client, point 5) and of those, the DIPS: a part drawn (alpha over 0) when it
-- was hidden and drawn again now, its textures let go - a picture on the screen that loads again and fades back in; the
-- first few by map and kind. In the harness's walks (retailvisible, retailparity: 277 parts shown again within 0.25 s, the
-- client letting hidden files go at once) none: the parts hidden that briefly were planned out - switched off below their
-- load zoom, or off the near window - and came back at alpha 0, loading, or lay off the screen with an empty window)
local RESHOW = { { 0.25, "under 0.25 s" }, { 1, "0.25 - 1 s" }, { 10, "1 - 10 s" }, { math.huge, "over 10 s" } }
local function Reshow(part, st)
    local hid, closed, hidA = part.hidT, part.hidClosed, part.hidA
    part.hidT, part.hidClosed, part.hidA = nil, nil, nil
    if not hid or part.n == 0 then return end
    local n, missing = TL.Reshown(part, st.vpx)
    local s = ns.retailStamp
    if s and n > 0 then
        local key = "map closed"
        if not closed then
            for _, b in ipairs(RESHOW) do
                if F.now - hid < b[1] then key = b[2] break end
            end
        end
        s.reshow = s.reshow or {}
        local r = s.reshow[key] or { parts = 0, textures = 0, notLoaded = 0, dips = 0 }
        s.reshow[key] = r
        r.parts, r.textures, r.notLoaded = r.parts + 1, r.textures + n, r.notLoaded + missing
        if missing > 0 and not closed and (hidA or 0) > 0.002 and (st.planA or 0) > 0.002 then
            r.dips = (r.dips or 0) + 1
            r.ex = r.ex or {}
            if #r.ex < 5 then r.ex[#r.ex + 1] = ("%d %s"):format((st.e.cellOf or st.e).id, st.e.kind) end
        end
    end
    if missing > 0 and part == st.base and not (st.lod and st.lod.f.pVis) then
        -- (at 0 this frame - the alpha the next frame steps from, PlanAlphas: its load fade brings it in again)
        st.loadedAt, st.shownA, st.baseA = nil, 0, 0
        F.busy = true
        return true
    end
end
local function Hid(part)
    if part.f.pVis and not part.hidT then part.hidT, part.hidA = F.now, part.f.pAlpha end
end
-- (a stage's host hidden: its parts hidden with it, each loaded as the client says when it is shown again - Reshow)
local function HostOff(st)
    st.host:Hide()
    st.hostVis = false
    local p = st.base
    Hid(p)
    p.visAt, p.visTick = nil, nil
    p = st.top
    if p then
        Hid(p)
        p.visAt, p.visTick = nil, nil
    end
    p = st.lod
    if p then
        Hid(p)
        p.visAt, p.visTick = nil, nil
    end
end

-- (1.4.0-beta2) A part wanted is shown at its alpha - 0 while it loads -, its frame the size of its picture
-- (RetailTiles.lua TL.SetSpec); one nothing wants is hidden. Returns whether it shows.
-- ((1.4.0-beta15) Only what changed asked of the client: a part's frame is moved and scaled alone, and what it was last asked is kept here (f.pVis,
-- pScale, pX, pY, pAlpha) - 1.4.0-beta14 made five calls a part a frame, the same scale and alpha again on every frame of a drag. One anchor: SetPoint replaces it.)
local function PlacePart(part, st, scale, alpha, level, layer, want, defer)
    local f = part.f
    if part.n == 0 or not want then
        if f.pVis then
            -- ((1.4.0-beta14) no tile of it in its window - RetailTiles.lua's viewport: nothing was seen to go, nothing to answer for when it
            -- is back - its tiles fade in as they load)
            if not part.hidT and part.n > 0 then part.hidT, part.hidA = F.now, f.pAlpha end
            f:Hide()
            f.pVis = false
        end
        part.visAt, part.visTick = nil, nil
        return false
    end
    -- (1.4.0-beta2, 11.6: at most TL.SHOW_PER_FRAME textures newly shown a game frame - a part not loaded yet, which
    -- would show nothing this frame anyway, waits for the next one; a part alone may be larger)
    -- ((1.4.0-beta14) those the client must load: what it holds costs a Show - RetailTiles.lua's viewport - and waits for nothing)
    local nl = f.pVis and 0 or TL.NotLoaded(part)
    if nl > 0 and TL.newShown > 0 and TL.newShown + nl > TL.SHOW_PER_FRAME then
        part.deferT = F.tick -- (the harness: a wait on a part deferred, not on a hidden one)
        return false
    end
    -- ((1.4.0-beta13) at alpha 0 - loading ahead, under a cover - nothing of it is seen, its textures load wherever it lies:
    -- laid once, not again every frame of a motion with every texture on it; the frame it shows it is laid first)
    if alpha > 0 or not f.laid then
        if f.pScale ~= scale then
            f:SetScale(scale)
            f.pScale = scale
        end
        local px, py = st.sx0 / scale, -st.sy0 / scale
        if f.pX ~= px or f.pY ~= py or not f.laid then
            f:SetPoint("TOPLEFT", layer, "TOPLEFT", px, py)
            f.pX, f.pY = px, py
        end
        f.laid = true
    end
    if f.level ~= level then
        ns.SetLevelFixed(f, level)
        f.level = level
    end
    if not f.pVis then
        f:Show()
        f.pVis = true
        TL.newShown, TL.newParts = TL.newShown + nl, TL.newParts + 1
        -- ((1.4.0-beta4) shown again: loaded as the client says now - Reshow)
        if Reshow(part, st) then alpha = 0 end
    end
    alpha = Clamp01(alpha)
    if f.pAlpha ~= alpha then
        f:SetAlpha(alpha)
        f.pAlpha = alpha
    end
    if not part.visAt then part.visAt, part.visTick = F.now, F.tick end
    return true
end

-- ((1.4.0-beta3, the reviews of 1.4.0-beta3) An inset's soft opening box: soft.tga over its link's rect - its
-- picture fading into the box printed on its parent -, opening to its whole picture (st.open), where it is grown by its
-- ramp, so its opaque middle is the whole picture: the picture's own crop and feather then, as a zone's. Laid on the
-- base's and the top's masks, in their layer px; st.boxRect: the box on the screen, for the harness.)
local function BoxMask(st)
    local e, t, L = st.e, st.open or 0, st.L
    local h = e.hit or e
    local w, hh = e.x1 - e.x0, e.y1 - e.y0
    local gx, gy = SOFT_INX / (1 - 2 * SOFT_INX), SOFT_INY / (1 - 2 * SOFT_INY)
    local bx0, by0 = (h.x0 - e.x0) / w * L.lw, (h.y0 - e.y0) / hh * L.lh
    local bx1, by1 = (h.x1 - e.x0) / w * L.lw, (h.y1 - e.y0) / hh * L.lh
    local x0, y0 = bx0 + (-gx * L.lw - bx0) * t, by0 + (-gy * L.lh - by0) * t
    local x1, y1 = bx1 + (L.lw * (1 + gx) - bx1) * t, by1 + (L.lh * (1 + gy) - by1) * t
    for i = 1, 3 do
        local p = st[PART_NAMES[i]]
        local m = p and p.mask
        if m and (m.bx0 ~= x0 or m.by0 ~= y0 or m.bx1 ~= x1 or m.by1 ~= y1 or m.bf ~= p.f) then
            m:ClearAllPoints()
            m:SetPoint("TOPLEFT", p.f, "TOPLEFT", x0, -y0)
            m:SetSize(math.max(x1 - x0, 0.01), math.max(y1 - y0, 0.01))
            m.bx0, m.by0, m.bx1, m.by1, m.bf = x0, y0, x1, y1, p.f
        end
    end
    local r = st.boxRect or {}
    st.boxRect = r
    local sx, sy = (e.x1 - e.x0) * F.ppx / L.lw, (e.y1 - e.y0) * F.ppy / L.lh
    r[1], r[2] = F.W / 2 + (e.x0 - F.cx) * F.ppx + x0 * sx, F.H / 2 + (e.y0 - F.cy) * F.ppy + y0 * sy
    r[3], r[4] = F.W / 2 + (e.x0 - F.cx) * F.ppx + x1 * sx, F.H / 2 + (e.y0 - F.cy) * F.ppy + y1 * sy
end

-- One stage on its layer at levels L .. L+1 (its alpha this frame - 0 for one that only loads, or under a confirmed cover:
-- st.hid, rule 2).
local function PlaceStage(st, L, layer)
    local e = st.e
    st.sx0 = F.W / 2 + (e.x0 - F.cx) * F.ppx
    st.sy0 = F.H / 2 + (e.y0 - F.cy) * F.ppy
    st.placeL, st.placeLayer = L, layer -- ((1.4.0-beta4) a second Draw in the frame places it again here - Replace)
    local scale = (e.x1 - e.x0) * F.ppx / st.L.lw
    local host = st.host
    if st.hostLayer ~= layer then
        if host:GetParent() ~= layer then
            host:SetParent(layer)
            host.level = nil
            host:ClearAllPoints()
            host:SetAllPoints(layer)
        end
        st.hostLayer = layer
    end
    if host.level ~= L then
        ns.SetLevelFixed(host, L)
        host.level = L
    end
    if st.box then BoxMask(st) end
    local vpx = st.vpx or ViewPx(st, F.cx, F.cy, F.vw)
    if not st.hostVis then
        host:Show()
        st.hostVis = true
        -- ((1.4.0-beta4) its parts shown again with it: loaded as the client says now - Reshow; at 0 this frame if not)
        if Reshow(st.base, st) then st.shownA, st.baseA = 0, 0 end
        if st.top then Reshow(st.top, st) end
    end
    TL.ShowIn(st.base, vpx, F.replacing)
    if st.top then TL.ShowIn(st.top, vpx, F.replacing) end
    if st.lod then TL.ShowIn(st.lod, vpx, F.replacing) end
    -- ((1.4.0-beta6, the player on 1.4.0-beta5: "can we fade the map image a bit when the real map is in?") a picture whose
    -- places are insets of their own - Argus's printed islands round the Antoran Wastes' real map - dims by PLACES_DIM
    -- times the most of them come in (PlanNode: st.kidA this frame), so their maps stand out over it
    local kid = (st.kidT == F.tick) and st.kidA or 0
    if st.dimK ~= kid then
        st.dimK = kid
        TL.SetDim(st.base, 1 - PLACES_DIM * kid)
        if st.top then TL.SetDim(st.top, 1 - PLACES_DIM * kid) end
    end
    local want = st.want or st.prefT == F.tick
    if scale > 0 and scale < 1e6 then
        -- (a part hidden with textures starts its loading again; one with none has nothing to wait for - TL.LoadState)
        -- (1.4.0-beta3: one planned off the screen, near it, waits for a frame's room too - newly shown, not drawn)
        -- ((1.4.0-beta3) and one not placed last frame, loaded or not: it waits for a frame's room as well - a city map's
        -- 3840-px patch shown in the frame a loaded picture came back made 191 newly shown, Boralus on the Kul Tiras walk)
        local pre = (st.prefT == F.tick and st.planT ~= F.tick) or not st.onScreen or st.placed ~= F.tick - 1
        local k = st.hid and 0 or 1
        -- ((1.4.0-beta14) the small picture under its tiles, at the stage's own level)
        if st.lod and PlacePart(st.lod, st, scale, st.shownA * k, L, overlay, want and (st.lodOn or st.lodHold), pre or not st.loadedAt) and TL.StepLate(st.lod, F.now) then
            F.busy = true
        end
        if not PlacePart(st.base, st, scale, (st.baseA or st.shownA) * k, L + 1, overlay, want, pre or not st.loadedAt) and st.base.n > 0 then
            -- ((1.4.0-beta4) not shown this frame - deferred for room, or not wanted: shown again, loaded as the client
            -- says then - Reshow)
        elseif TL.StepLate(st.base, F.now) then
            F.busy = true
        end
        if st.top and PlacePart(st.top, st, scale, st.shownA * k, L + 2, overlay, want, pre or not st.loadedAt) and TL.StepLate(st.top, F.now) then
            F.busy = true
        end
    else
        PlacePart(st.base, st, 1, 0, L + 1, overlay, false)
        if st.top then PlacePart(st.top, st, 1, 0, L + 1, overlay, false) end
        if st.lod then PlacePart(st.lod, st, 1, 0, L + 1, overlay, false) end
    end
    if st.circle then
        local c, d = e.node.c, st.d or 1.25
        local size = math.max(d, 0.01) * st.L.lw / Render.CIRCLE_DISC
        st.circle:ClearAllPoints()
        st.circle:SetPoint("CENTER", st.base.f, "TOPLEFT", c[1] * st.L.lw, -c[2] * st.L.lh)
        st.circle:SetSize(size, size)
    end
end

-- (1.4.0-beta2, 11.6: what is shown is what the client keeps - at most TL.SHOWN_MAX textures. Over it the preloads go
-- first, then the pictures planned near the view but off it - the most detailed first.) (1.4.0-beta4, G5) Never a picture
-- on the screen: the camera's chain stays shown, so loaded - 1.4.0-beta3 hid covered pictures here and dropped those off
-- the focus chain, and a parent so let go had to load again before the child over it could go out (PARENT_WAIT); the
-- player's session peaked at 1,589 shown of 4,000. (1.4.0-beta4's fixes) Nothing drawn is cut for the count drawn:
-- 1.4.0-beta4's DRAWN_MAX (1,100 - beta1's estimate, no measured limit of the client) hid the pictures going out under 0.1
-- once more were drawn, and 1.4.0-beta3's last resort hid every one going out up to 0.5 and hurried the switches - the
-- look depended on the load. The count drawn and the frame time after it go to the stamp (load.heavy): what the client
-- holds, measured in game.
local function Budget()
    local n, d = 0, 0
    for oi = 1, #order do
        local st = order[oi]
        st.overBudget, st.dN, st.rN = nil, 0, 0
        if st.want or st.shownA > 0.002 then
            st.rN = st.base.n + (st.top and st.top.n or 0) + (st.lod and st.lod.n or 0)
            n = n + st.rN
            local vpx = st.vpx
            if vpx and st.shownA > 0.002 and not st.covered then
                st.dN = TL.ShowIn(st.base, vpx) + (st.top and TL.ShowIn(st.top, vpx) or 0)
                    + ((st.lod and (st.lodOn or st.lodHold)) and TL.ShowIn(st.lod, vpx) or 0)
                d = d + st.dN
            end
        end
    end
    for _, st in ipairs(pref) do n = n + st.base.n end
    if n > TL.SHOWN_MAX then
        for i = #pref, 1, -1 do
            n = n - pref[i].base.n
            pref[i] = nil
            if n <= TL.SHOWN_MAX then break end
        end
    end
    -- (1.4.0-beta3: then the pictures planned near the view but off it, the most detailed first - loaded ahead for a drag,
    -- they are what can wait: not wanted, they load again when on screen)
    for i = #order, 2, -1 do
        if n <= TL.SHOWN_MAX then break end
        local st = order[i]
        if not st.onScreen and st.want and not st.overBudget then
            st.overBudget, st.want = true, false
            n = n - st.rN
        end
    end
    F.drawnN = d
end

-- This frame's st.hid - (1.4.0-beta4, rule 2) a picture under the confirmed cover, placed at alpha 0 (PlaceStage) - and
-- st.hidFlipT, when it changed (the harness's alpha-step check lets that frame pass: the picture over it is opaque).
-- 1.4.0-beta2 - 1.4.0-beta3 put our pictures of the map Blizzard's canvas showed, and of every map above it, under
-- Blizzard's map as the floor: gone (the header).
local function Hidden()
    for oi = 1, #order do
        local st = order[oi]
        local hid = st.covered or nil
        if st.hid ~= hid then st.hidFlipT = F.now end
        st.hid = hid
    end
end

-- (1.4.0-beta4) The worlds' space fills (FILL_GROW, FILL_Z0 -> FILL_Z1): one colour texture each through soft.tga over the
-- world's rect grown, right over the Cosmic map; alpha by the world's own zoom alone, times its load fade ((1.4.0-beta4's
-- fixes) a part as any: loaded ahead near the view, in once its mask is - FILL_LOAD). Returns the next level free.
local function SpaceFill(W, L)
    local base = Render.SPACE_FILLS[W.id]
    local x = fills[W]
    local zc = ns.ZoomOf(F.v, W, F.vw)
    local za = base and Smooth((zc - FILL_Z0) / (FILL_Z1 - FILL_Z0)) or 0
    local gw, gh = (W.x1 - W.x0) * FILL_GROW, (W.y1 - W.y0) * FILL_GROW
    local x0, y0, x1, y1 = W.x0 - gw, W.y0 - gh, W.x1 + gw, W.y1 + gh
    local mx, my = (F.vx1 - F.vx0) * NEAR, (F.vy1 - F.vy0) * NEAR
    local want = base ~= nil and zc >= FILL_LOAD and x1 > F.vx0 - mx and x0 < F.vx1 + mx and y1 > F.vy0 - my and y0 < F.vy1 + my
    if not want then
        if x and x.f:IsShown() then x.f:Hide() end
        return L + 1 -- (a level each world's, shown or not: a second Draw in the frame places them again - Replace)
    end
    if not x then
        -- ((1.4.0-beta4's fixes) its mask's file against the frame's SetTexture budget, as every mask's: made next frame
        -- when it is spent)
        if TL.newThisFrame + 1 > TL.NEW_PER_FRAME then return L + 1 end
        local f = CreateFrame("Frame", nil, overlay)
        f:SetAlpha(0)
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints(f)
        local m = f:CreateMaskTexture()
        m:SetTexture(SOFT, "CLAMP", "CLAMP", "TRILINEAR")
        TL.newThisFrame = TL.newThisFrame + 1
        m:SetAllPoints(f)
        m.file, m.mfile = SOFT, SOFT
        TL.Watch(m, nil, true, f, "mask") -- (its load measured as every mask's - probe P1)
        t:AddMaskTexture(m)
        x = { f = f, t = t, m = m }
        fills[W] = x
    end
    -- (its colour: the drawn map's sea, or the imagery's while that stands for its world - in step with its switch)
    local cr, cg, cb = base[1], base[2], base[3]
    local ic, ia = nil, 0
    if F.imgOn and IMG and IMG.SpaceSea then ic, ia = IMG:SpaceSea(W) end
    if ic and ia > 0 then
        cr, cg, cb = cr + (ic[1] - cr) * ia, cg + (ic[2] - cg) * ia, cb + (ic[3] - cb) * ia
    end
    if x.cr ~= cr or x.cg ~= cg or x.cb ~= cb then
        x.t:SetColorTexture(cr, cg, cb, 1)
        x.cr, x.cg, x.cb = cr, cg, cb
    end
    if not x.f:IsShown() then
        x.f:Show()
        -- (shown again: loaded as the client says now - Reshow's rule)
        if x.at and x.m.IsObjectLoaded and not x.m:IsObjectLoaded() then x.at = nil end
    end
    if not x.at and (TEST.noload or not x.m.IsObjectLoaded or x.m:IsObjectLoaded()) then x.at = F.now end
    local lf = x.at and (TEST.nofade and 1 or Smooth((F.now - x.at) / LOAD_FADE)) or 0
    local a = za * lf
    if za > 0 and lf < 1 then F.busy = true end
    local sx0, sy0 = F.W / 2 + (x0 - F.cx) * F.ppx, F.H / 2 + (y0 - F.cy) * F.ppy
    local w, h = (x1 - x0) * F.ppx, (y1 - y0) * F.ppy
    -- (laid at its picture's own scale - as a stage's part: a rect of millions of px deep in a zone is no frame's size)
    local scale = math.max(w / 1002, 1e-6)
    if a > 0 or x.a == nil or x.a > 0 then
        -- ((1.4.0-beta15) at alpha 0 nothing of it is seen: not laid again every frame)
        x.f:SetScale(scale)
        x.f:SetPoint("TOPLEFT", overlay, "TOPLEFT", sx0 / scale, -sy0 / scale)
        x.f:SetSize(1002, h / scale)
    end
    if x.a ~= a then x.f:SetAlpha(a) end
    if x.f.level ~= L then
        ns.SetLevelFixed(x.f, L)
        x.f.level = L
    end
    x.a = a
    local rc = x.rect or {}
    rc[1], rc[2], rc[3], rc[4] = sx0, sy0, sx0 + w, sy0 + h
    x.rect = rc
    return L + 1
end
local function PlaceFills(L)
    local root = ns.maps[ns.ROOT_MAP_ID]
    for _, W in ipairs(root and ns.SpaceKids(root) or {}) do
        if W.kind == "globe" then L = SpaceFill(W, L) end
    end
    return L
end

-- ((1.4.0-beta15) The levels inside the clipping layers are their own - they only order what is drawn there, a clipping frame drawing its children as one block (design rule 9):
-- constant, whatever the level the layer itself has at rest or moving, under every pin's and over Blizzard's map art either way. 1.4.0-beta14 counted up from the layer's
-- level, each stage the next three: every stage's frames levelled again (three calls each, up to 200 frames) whenever the layer went between rest and moving, and all those
-- after one that came or went - up to 36 levels set a frame in a flight. A stage keeps its level while the order allows - LevelFor -, a new one leaves room before it.)
local STAGE_BASE, CAVE_BASE = 100, 1500
local LEVEL_KEEP = 300
local function LevelFor(st, nOver)
    local kept = st.placeL
    if kept and kept >= nOver and kept - nOver < LEVEL_KEEP then return kept end
    if kept then return nOver end -- (planned before: only as far as the order asks)
    return nOver + 3
end
local function PlaceParts()
    local base = STAGE_BASE
    local nOver, nCity = base, CAVE_BASE
    Budget()
    Hidden()
    -- ((1.4.0-beta3) the minimap imagery's holders right over the Cosmic map, under every other picture of ours: those it
    -- stands for fade out over it - RetailImagery.lua; (1.4.0-beta4) the worlds' space fills under them)
    local imgPlaced = false
    for i, st in ipairs(order) do
        local e = st.e
        -- (1.4.0-beta1: a picture switching off goes at 0.02 - (1.4.0-beta4) PlanAlphas, before the step cap)
        -- (1.4.0-beta3: a picture near the view is placed at its alpha too - clipped: one a drag brings in
        -- shows at once)
        local drawn = st.shownA > 0.002 and st.near and not st.overBudget
        -- ((1.4.0-beta3) its base part's alpha with it - placed at baseA, a cell switching off went on drawn at
        -- 0.003 - 0.02: a fast zoom out to Krokuun had 40 of them, 1,160 drawn)
        if not drawn and st.shownA > 0 then st.shownA, st.baseA = 0, 0 end
        if drawn or (st.want and not st.overBudget) then
            if drawn then
                st.lastDrawn = F.now
                st.drawn = F.tick
            end
            local L = LevelFor(st, nOver)
            nOver = L + 3
            PlaceStage(st, L, overlay)
            st.placed = F.tick
            st.placedA = st.shownA
        elseif st.hostVis then
            HostOff(st)
        end
        -- ((1.4.0-beta4's fixes) over the Cosmic map and its picture covers - RetailCells.lua PICTURE_COVERS: under the fill
        -- as the Cosmic map is - and under every other picture)
        local nxt = order[i + 1]
        if not imgPlaced and (st.e.kind == "root" or st.e.cellOf and st.e.cellOf.kind == "root")
            and not (nxt and nxt.e.cellOf and nxt.e.cellOf.kind == "root") then
            F.fillL = nOver
            nOver = PlaceFills(nOver)
            F.imgL = nOver
            if F.imgOn then nOver = IMG:Place(nOver) end
            imgPlaced = true
        end
    end
    if not imgPlaced then
        F.fillL = nOver
        nOver = PlaceFills(nOver)
        F.imgL = nOver
        if F.imgOn then nOver = IMG:Place(nOver) end
    end
    -- ((1.4.0-beta3) the caves over it all - RetailCaves.lua, (1.4.0-beta12) in the city layer)
    F.caveL = nCity
    if CAVES then nCity = CAVES:Place(nCity) end
    -- (1.4.0-beta2) the prefetch's stages: shown at alpha 0 at their true place, under everything (they load)
    for _, st in ipairs(pref) do
        if st.planT ~= F.tick and stages[st.e] == st then
            -- (every alpha PlaceStage reads at 0: a stage drawn before kept its base's alpha - a preload drew Terokkar
            -- Forest at 1 under everything)
            st.want, st.shownA, st.baseA = false, 0, 0
            PlaceStage(st, base, overlay)
            st.placed = F.tick
            st.placedA = 0 -- (planned again, it fades in from 0: PlanAlphas)
        end
    end
    for _, st in pairs(stages) do
        if st.placed ~= F.tick and st.hostVis then HostOff(st) end
    end
end

-- ((1.4.0-beta4, C3) A second Draw in the same game frame - Core.lua draws from the wheel's event and from its driver:
-- the frame's one plan placed again at the camera of the moment - no switch, fade or load steps twice in a frame, and
-- nothing is planned anew but what the camera's place decides: what covers the view, so what lies at 0 under it (the
-- input's draw comes before the driver moves the camera: a cover of the first view hid the pictures under it at the
-- second view's corners - the walks' frame checks). 1.4.0-beta2 - 1.4.0-beta3 planned twice and guarded the second plan
-- (PLACED_RECENT, no step in the second draw). The imagery and the caves keep their own second-draw rules (dt 0).)
local function Replace(cam, v)
    F.v, F.vw, F.cx, F.cy, F.W, F.H = v, cam.vw, cam.x, cam.y, v.W, v.H
    F.ppx, F.ppy = ns.PixelsPerUnit(v, cam.vw)
    F.vx0, F.vx1 = cam.x - v.W / 2 / F.ppx, cam.x + v.W / 2 / F.ppx
    F.vy0, F.vy1 = cam.y - v.H / 2 / F.ppy, cam.y + v.H / 2 / F.ppy
    if IMG and IMG:Frame(cam, v, prefetch, overlay) then F.busy = true end
    if CAVES and CAVES:Frame(cam, v, cityLayer or overlay) then F.busy = true end
    for oi = 1, #order do
        local st = order[oi]
        ViewPx(st, F.cx, F.cy, F.vw)
        if st.placed == F.tick then TL.ShowIn(st.base, st.vpx, true) end
    end
    PlanCovers()
    Hidden()
    F.replacing = true
    for _, st in pairs(stages) do
        if st.placed == F.tick and st.placeL and st.hostVis then
            ViewPx(st, F.cx, F.cy, F.vw)
            PlaceStage(st, st.placeL, st.placeLayer)
        end
    end
    F.replacing = nil
    if F.fillL then PlaceFills(F.fillL) end
    if F.imgOn and IMG and F.imgL then IMG:Place(F.imgL) end
    if CAVES and F.caveL then CAVES:Place(F.caveL) end
    if ns.RetailWhy then ns.RetailWhy.Kick() end
    return F.busy
end

---------------------------------------------------------------------------
-- The stamp's load times and peaks
---------------------------------------------------------------------------
-- (1.4.0-beta2) the textures in shown parts (resident: the client keeps what is visible) and of them those drawn - in
-- view in a part with an alpha
local function Counts()
    local shown, drawn = 0, 0
    for _, st in pairs(stages) do
        if st.placed == F.tick then
            for i = 1, 3 do
                local p = st[PART_NAMES[i]]
                if p and p.f.pVis then
                    shown = shown + p.n
                    if p.f.pAlpha > 0.002 then drawn = drawn + (p.inView or 0) end
                end
            end
        end
    end
    if drawn > peaks.drawn then peaks.drawn = drawn end
    if shown > peaks.shown then peaks.shown = shown end
    return shown, drawn
end

-- (1.4.0-beta2) the stamp's load times (EndlessMapDB.retailChecks.load) and the peaks, written from every Draw at most
-- every STAMP_EVERY s and when the map closes (HideAll). (1.4.0-beta4, the in-game probes - docs/retail-engine.md 16) The
-- load times every texture's (RetailTiles.lua TL.PollLoads: from its first visible frame to its first IsObjectLoaded, the
-- session's every one - P1) by kind: tile, file, mask - count, median, 95th percentile and max in seconds and frames, the
-- max's file; slow: the textures visible a second or more before they loaded (P2: TL.slow - nothing is given up); heavy:
-- the frames drawing HEAVY or more textures and the longest frame time after one; the reshow counts are written as they
-- come (Reshow - P4).
local STAMP_EVERY = 10
local stampT
-- ((1.4.0-beta4's fixes) the frames drawing HEAVY or more textures - in view with an alpha - and the longest frame time
-- after one (the next draw's interval), against the longest of any frame with the map open: whether so many drawn cost
-- the player's client anything - measured, never cut (Budget))
local HEAVY = 1100
local heavy = { frames = 0, maxDrawn = 0, worstMs = 0, worstAllMs = 0 }
-- ((1.4.0-beta13) the frame times by the textures the frame before drew, each 500 - the stamp's load.byDrawn: what so many
-- drawn cost the player's client, not only the worst of them)
local byDrawn = {}
-- ((1.4.0-beta13) the frames drawn with the map standing still and more to do - load.rest: it should stop within a moment of every
-- move; longest: the longest such stretch, in seconds)
local restBusy = { frames = 0, longest = 0 }
-- ((1.4.0-beta14) load.hitch: the frames this long, in ms, and the textures set and shown in the frames before them - what the
-- player feels, where load.byDrawn is the mean; load.draw: the renderer's own time a frame in ms)
local hitch = { ["50+"] = 0, ["100+"] = 0, ["250+"] = 0, ["500+"] = 0, newBefore = 0, shownBefore = 0 }
local drawTime = { n = 0, ms = 0, max = 0 }
local lastDrawnN
-- ((1.4.0-beta12) the heaviest frame's pictures, the most drawn first, their explored pieces apart - the stamp: what the
-- player's 2,145 drawn of 1.4.0-beta11 were, where the suites' walks draw at most 1,289)
local function HeavyParts()
    local list = {}
    for oi = 1, #order do
        local st = order[oi]
        if (st.dN or 0) > 0 then list[#list + 1] = st end
    end
    table.sort(list, function(a, b) return a.dN > b.dN end)
    local out = {}
    for i = 1, math.min(8, #list) do
        local st = list[i]
        local top = st.top and st.top.inView or 0
        out[#out + 1] = ("%d %s %d%s a %.2f"):format(st.e.id, st.e.kind, st.dN, top > 0 and (" (explored " .. top .. ")") or "", st.shownA or 0)
    end
    return ("%d pictures at %.1fx: %s"):format(#list, ns.WorldZoom(F.v, F.vw), table.concat(out, ", "))
end
local function StampLoads(every)
    local s = ns.retailStamp
    local now = F.now or GetTime()
    if not s or (every and stampT and now - stampT < every) then return end
    stampT = now
    if F.tick and every == STAMP_EVERY then Counts() end -- (the peaks, without the readout)
    local bd = {}
    for k, b in pairs(byDrawn) do
        bd[("%d+"):format(k * 500)] = ("%d frames, mean %.1f ms, longest %d ms"):format(b.n, b.ms / b.n, b.max)
    end
    s.load = { tile = TL.LoadStats("tile"), file = TL.LoadStats("file"), mask = TL.LoadStats("mask"), byDrawn = bd,
        slow = { textures = TL.slow.textures, later = TL.slow.later, waiting = TL.slow.waiting, first = TL.slow.first },
        rest = { frames = restBusy.frames, longest = math.floor(restBusy.longest * 10 + 0.5) / 10 },
        hitch = hitch, draw = { frames = drawTime.n, meanMs = drawTime.n > 0 and math.floor(drawTime.ms / drawTime.n * 100 + 0.5) / 100 or 0, maxMs = math.floor(drawTime.max * 10 + 0.5) / 10 },
        heavy = { frames = heavy.frames, maxDrawn = heavy.maxDrawn, worstMs = heavy.worstMs, worstAllMs = heavy.worstAllMs, top = heavy.top },
        peakDrawn = peaks.drawn, peakShown = peaks.shown, peakLive = TL.peak, made = TL.made }
    if ns.Perf then
        local pr = ns.Perf.Report()
        s.load.frames, s.load.parts, s.load.hitches = pr.frames, pr.parts, pr.hitches
    end
end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------
F.bands = {} -- (1.4.0-beta3: the cells' bands' switches)
F.coverB = {}

-- ((1.4.0-beta15, RetailBench.lua: a frame of motion's time, the client's own elapsed. 1.4.0-beta13 - 1.4.0-beta14 took the time between two draws: the map draws
-- nothing at rest, so the pause between two moves counted as a long frame - 18 "frames" of over 500 ms in the player's stamp)
function Render:FrameTime(ms)
    if not lastDrawnN then return end
    ms = math.floor(ms + 0.5)
    if ms > heavy.worstAllMs then heavy.worstAllMs = ms end
    if lastDrawnN >= HEAVY and ms > heavy.worstMs then heavy.worstMs = ms end
    local k = math.floor(lastDrawnN / 500)
    local b = byDrawn[k] or { n = 0, ms = 0, max = 0 }
    byDrawn[k] = b
    b.n, b.ms = b.n + 1, b.ms + ms
    if ms > b.max then b.max = ms end
    if ms >= 50 then
        hitch["50+"] = hitch["50+"] + 1
        if ms >= 100 then hitch["100+"] = hitch["100+"] + 1 end
        if ms >= 250 then hitch["250+"] = hitch["250+"] + 1 end
        if ms >= 500 then hitch["500+"] = hitch["500+"] + 1 end
        hitch.newBefore, hitch.shownBefore = hitch.newBefore + frameNew, hitch.shownBefore + frameShown
    end
end
-- (RetailBench.lua) the last draw's textures set, newly shown, drawn; shown and drawn
function Render:FrameCounts() return frameNew, frameShown, lastDrawnN or 0 end
function Render:StampNow() StampLoads() end
function Render:Counts2() return Counts() end

function Render:Draw(cam, v)
    local now = GetTime()
    -- ((1.4.0-beta4) one plan a game frame: a second Draw in it places that plan again - Replace)
    if F.now == now and F.tick and lastDrawT == now then return Replace(cam, v) end
    local p0 = debugprofilestop()
    F.tick = (F.tick or 0) + 1
    local ddt = lastDrawT and math.min(now - lastDrawT, 0.05)
    lastDrawT = now
    F.now, F.ddt, F.busy, F.v, F.vw, F.cx, F.cy = now, ddt, false, v, cam.vw, cam.x, cam.y
    F.zpE = nil
    TL.now, TL.tick = now, F.tick
    F.swStep = ddt and math.min(1, ddt / SWITCH_FADE) or 1
    F.capStep = ddt and math.min(1, ddt / SWITCH_FADE_MIN) or 1
    -- (1.4.0-beta2, /emap test nofade - RetailWhy.lua: every switch at once)
    if TEST.nofade then F.swStep, F.capStep = 1, 1 end
    F.W, F.H = v.W, v.H
    F.ppx, F.ppy = ns.PixelsPerUnit(v, cam.vw)
    F.vx0, F.vx1 = cam.x - v.W / 2 / F.ppx, cam.x + v.W / 2 / F.ppx
    F.vy0, F.vy1 = cam.y - v.H / 2 / F.ppy, cam.y + v.H / 2 / F.ppy
    local nmx, nmy = (F.vx1 - F.vx0) * NEAR, (F.vy1 - F.vy0) * NEAR
    F.nx0, F.nx1, F.ny0, F.ny1 = F.vx0 - nmx, F.vx1 + nmx, F.vy0 - nmy, F.vy1 + nmy
    -- (1.4.0-beta1, the review of the code, point 9: the budget is the game frame's)
    TL.newThisFrame, TL.newShown, TL.newParts, TL.reshown = 0, 0, 0, 0
    -- (1.4.0-beta3) the minimap imagery first (RetailImagery.lua; the frame's SetTexture budget is shared): its worlds'
    -- switches and holders - where it stands for our pictures PlanNode fades them out over it (IMG:Fade), and its
    -- backdrop over the view makes the frame ready (IMG:CoversView)
    IMG = ns.RetailImagery
    F.imgOn = false
    if IMG then
        if IMG:Frame(cam, v, prefetch, overlay) then F.busy = true end
        F.imgOn = IMG:Shown()
    end
    -- (1.4.0-beta3) the view the motion heads for - a pan's heading, a wheel's destination (Core.lua's prefetch): what
    -- lies there is near too (Near)
    local p = prefetch
    if p and p.vw and p.vw > 0 then
        local qx, qy = v.W / 2 / F.ppx * p.vw / cam.vw, v.H / 2 / F.ppy * p.vw / cam.vw
        local pv = F.pvBuf or {}
        F.pvBuf = pv
        pv[1], pv[2], pv[3], pv[4] = p.x - qx, p.y - qy, p.x + qx, p.y + qy
        F.pv = pv
    else
        F.pv = nil
    end
    wipe(order)
    wipe(pref)
    local root = ns.maps[ns.ROOT_MAP_ID]
    if root then PlanNode(root) end
    PlanAlphas()
    PlanMapAlphas()
    PlanCovers()
    PlanTiles()
    -- ((1.4.0-beta3) the caves and interiors - RetailCaves.lua: over everything placed here, PlaceParts. (1.4.0-beta4)
    -- after the map's tiles - what lies over a picture asks for its files after it, as PlanTiles's pictures bottom up: the
    -- caves near Orgrimmar loaded ahead at alpha 0 had their 100-odd files asked for before the map's tiles in view -
    -- retailparty:rate=4's map opened there, Orgrimmar's own map in view still loading a second on)
    CAVES = ns.RetailCaves
    if CAVES and CAVES:Frame(cam, v, cityLayer or overlay) then F.busy = true end
    PlaceParts()
    lastDrawnN = F.drawnN
    if lastDrawnN and lastDrawnN >= HEAVY then
        heavy.frames = heavy.frames + 1
        if lastDrawnN > heavy.maxDrawn then
            heavy.maxDrawn = lastDrawnN
            heavy.top = HeavyParts()
        end
    end
    TL.PollLoads(now, F.tick) -- ((1.4.0-beta4, probe P1) the load times of the textures visible now)
    frameNew, frameShown, frameParts = TL.newThisFrame, TL.newShown, TL.newParts
    if F.busy and ns.Core and ns.Core.Settled and ns.Core.Settled() then
        restBusy.frames = restBusy.frames + 1
        restBusy.since = restBusy.since or now
        if now - restBusy.since > restBusy.longest then restBusy.longest = now - restBusy.since end
    else
        restBusy.since = nil
    end
    StampLoads(STAMP_EVERY) -- (the review of the real client, point 8: not only from the readout)
    if ns.RetailWhy then ns.RetailWhy.Kick() end -- (1.4.0-beta2: its silent snapshots look at the open map, RetailWhy.lua)
    local dms = debugprofilestop() - p0
    drawTime.n, drawTime.ms = drawTime.n + 1, drawTime.ms + dms
    if dms > drawTime.max then drawTime.max = dms end
    if ns.Perf then ns.Perf.Add("draw", dms) end
    return F.busy
end

function Render:HideAll()
    for _, st in pairs(stages) do
        st.host:Hide()
        st.hostVis = false
        st.a, st.sa, st.sw = 0, 0, nil
        st.loadedAt, st.hid = nil, nil
        st.placedA, st.baseA = nil, nil -- (1.4.0-beta2: no alpha step is measured across the map closed - PlanAlphas)
        for i = 1, 3 do
            local p = st[PART_NAMES[i]]
            if p then
                if p.f.pVis then p.hidT, p.hidClosed = p.hidT or GetTime(), true end
                p.visAt, p.visTick = nil, nil
            end
        end
    end
    for _, x in pairs(fills) do x.f:Hide() end
    lastDrawT, lastDrawnN = nil, nil
    F.now = nil
    dready = false
    StampLoads()
end

-- (Core.lua: the map closed RELEASE_DELAY seconds) the pictures' textures go, but the Cosmic map's, the worlds' and the
-- continents' ((1.4.0-beta12) WoW Forever's Render:ReleaseAll keeps its world and continent stages: the map opened again
-- finds them loaded - 1.4.0-beta2 - 1.4.0-beta11 kept the Cosmic map's alone, and every opening set Azeroth's 279 tiles
-- and each continent's again)
function Render:ReleaseAll()
    local list = {}
    for e, st in pairs(stages) do
        if e.kind ~= "root" and e.kind ~= "globe" and e.kind ~= "cont" then list[#list + 1] = st end
    end
    for _, st in ipairs(list) do ReleaseStage(st) end
end

---------------------------------------------------------------------------
-- Readout, highlight, debug
---------------------------------------------------------------------------
-- (HighlightGuard.lua) Hide the world map's zone highlight while a continent drawn at its true shape shows over it.
-- ((1.4.0-beta13) and on any map whose zones' own maps are in: its soft, small highlight lay over them as a tint under the
-- cursor while Blizzard's map rested on the continent - by the view's centre, from the band to 2.5x of the continent)
function Render:HighlightOff(id)
    local m = ns.maps[id]
    if m and F.mapT == F.tick and (F.mapKid[m] or 0) > 0.002 then return true end
    if id ~= ns.WORLD_MAP_ID then return false end
    for e, st in pairs(stages) do
        if CORRECTED[e.id] and st.drawn == F.tick and (st.shownA or 0) > 0.002 then return true end
    end
    return false
end

-- ((1.4.0-beta10) RetailPins.lua, RetailDoors.lua) How much map e's own markers show this frame: its own picture drawn,
-- as far as the maps standing for it there are not (a continent's under its zones' maps: theirs instead). 0 for a map
-- not drawn - or before the first frame.
function Render:MapAlpha(e)
    if not (e and F.mapT and F.mapT == F.tick) then return 0 end
    local a = F.mapOwn[e] or 0
    if a <= 0 then return 0 end
    if e.kind ~= "zone" then a = a * (1 - (F.mapKid[e] or 0)) end
    return a
end

function Render:Stats()
    local loading, n = 0, 0
    for _, st in pairs(stages) do
        n = n + 1
        -- (a stage that loads now: wanted, its picture not there yet - its window not complete, or a texture of it in
        -- view not loaded)
        -- ((1.4.0-beta14) nothing shown out of the viewport's reach: LoadFade)
        local reach = st.onScreen or not (st.base.win and st.base.win[1] > st.base.win[3])
        if st.planT == F.tick and st.want and reach and (st.base.pending or not st.loadedAt) then loading = loading + 1 end
    end
    local shown, drawn = Counts()
    local S = { shown = shown, drawn = drawn, live = TL.live, stages = n, loading = loading, newTex = frameNew, newShown = frameShown, newParts = frameParts,
        evicted = TL.evicted, maskFail = maskRefused, budget = TL.LIVE_MAX, peak = TL.peak, spare = TL.Idle(), made = TL.made,
        peakDrawn = peaks.drawn, peakShown = peaks.shown, mb = shown * 44 / 1024 }
    StampLoads(2)
    return S
end

-- ((1.4.0-beta4, the in-game probes P1, P2, P4 - /emap why) one line: the load times by kind, the give-ups, the parts
-- shown again)
function Render:LoadLine()
    local out = {}
    for _, k in ipairs({ "tile", "file", "mask" }) do
        local s = TL.LoadStats(k)
        if s.count > 0 then
            out[#out + 1] = ("%ss %d: median %.2f s (%d frames), 95%% %.2f s (%d), max %.2f s (%d, %s)"):format(k, s.count, s.medianS, s.medianF,
                s.p95S, s.p95F, s.maxS, s.maxF, tostring(s.maxFile))
        end
    end
    local g = TL.slow
    out[#out + 1] = ("slow (visible %d s, not loaded): %d textures (first %s), %d loaded later, %d waiting"):format(TL.SLOW_S, g.textures,
        tostring(g.first), g.later, g.waiting)
    out[#out + 1] = ("heavy frames (%d+ drawn): %d, most drawn %d, longest frame after one %d ms (any frame %d ms)"):format(HEAVY,
        heavy.frames, heavy.maxDrawn, heavy.worstMs, heavy.worstAllMs)
    if heavy.top then out[#out + 1] = "the heaviest frame: " .. heavy.top end
    local rs = ns.retailStamp and ns.retailStamp.reshow
    if rs then
        local keys = {}
        for k in pairs(rs) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local r = rs[k]
            out[#out + 1] = ("shown again %s: %d parts, %d of %d textures not loaded, %d drawn ones faded in again%s"):format(k, r.parts,
                r.notLoaded, r.textures, r.dips or 0, r.ex and (" (" .. table.concat(r.ex, ", ") .. ")") or "")
        end
    end
    return "loads: " .. table.concat(out, "; ")
end

-- out[frame] = { map, part = "base" | "top", alpha, level, loaded, door, kind, covered, cell } for every part shown in
-- the overlay or the city layer (the harness's retail suites) - (1.4.0-beta2) those loading at alpha 0 and the preloads
-- too; hid: placed at 0 under its cover (rule 2), hidFlip: that changed this frame; (1.4.0-beta3) area: a home's cover's
-- rect on the screen (its d - the part spans its home's whole picture, its items only d: RetailCells.lua HOME_COVERS)
local function CoverArea(e, L, d)
    local sx, sy = (e.x1 - e.x0) * F.ppx / L.lw, (e.y1 - e.y0) * F.ppy / L.lh
    local ox, oy = F.W / 2 + (e.x0 - F.cx) * F.ppx, F.H / 2 + (e.y0 - F.cy) * F.ppy
    return { ox + d[1] * sx, oy + d[2] * sy, ox + d[3] * sx, oy + d[4] * sy }
end
function Render:DebugParts(out)
    for e, st in pairs(stages) do
        if st.placed == F.tick then
            for _, pn in ipairs({ "base", "top", "lod" }) do
                local p = st[pn]
                if p and p.f:IsShown() then
                    local ent = e.cellOf or e
                    out[p.f] = { map = ent.id, part = (e.kind == "cell") and ("cell" .. (pn == "top" and "top" or "")) or pn,
                        alpha = p.f:GetAlpha(), level = p.f.level, loaded = st.loadedAt ~= nil, door = ent.door, kind = e.kind,
                        box = st.box and st.boxRect,
                        area = (e.kind == "cell" and e.cell.cover and st.L) and CoverArea(e, st.L, e.cell.cover.d) or nil,
                        entry = ent, cellEntry = (e.kind == "cell") and e or nil, host = st.host, n = p.n, shown = p.inView, circle = st.circle and st.d,
                        partObj = p, stage = st,
                        covered = st.covered or false, preload = st.planT ~= F.tick, pending = p.pending or nil,
                        hid = (st.planT == F.tick and st.hid) or false, floor = false,
                        hidFlip = st.hidFlipT ~= nil and st.hidFlipT >= F.now, hidFlipT = st.hidFlipT }
                end
            end
        end
    end
    return out
end
-- ((1.4.0-beta4) the worlds' space fills shown now: out[frame] = { map, alpha, level, rect (screen px), loaded } - the
-- harness)
function Render:DebugFills(out)
    for W, x in pairs(fills) do
        if x.f:IsShown() then out[x.f] = { map = W.id, alpha = x.a, level = x.f.level, rect = x.rect, mask = x.m, tex = x.t, loaded = x.at ~= nil } end
    end
    return out
end

-- (1.4.0-beta2, RetailWhy.lua's /emap why and snapshots) the stages planned in the last frame drawn, bottom to top, every
-- stage, the frame's numbers (F: tick, view, now) - read only
function Render:DebugStages() return order, stages, F end

-- (1.4.0-beta2, /emap test - RetailWhy.lua) a switch changed: every part lays its items again on its next fill (nomask:
-- the masks off or on; no texture is set again)
function Render:ApplyTest()
    for _, st in pairs(stages) do
        for _, p in ipairs({ st.base, st.top or false, st.lod or false }) do
            if p then p.laidKey = nil end
        end
    end
end

-- The drawn nodes, bottom to top.
function Render:Chain(out)
    for oi = 1, #order do
        local st = order[oi]
        if st.drawn == F.tick and st.onScreen and st.e.kind ~= "cell" then out[#out + 1] = st.e.id end
    end
    return out
end

function Render:ZoomLines(cam, v, out)
    if not (v and v.W and v.H and v.W > 0 and v.H > 0 and cam.vw and cam.vw > 0) then
        out[#out + 1] = "zoom: open the map to see the numbers"
        return
    end
    out[#out + 1] = ("Zoom %.2fx   (1.00x = the Azeroth map; space %.2fx)"):format(ns.WorldZoom(v, cam.vw), 1 / cam.vw)
    local c, z
    if ns.SpaceFocus then c, z = ns.SpaceFocus(cam.x, cam.y, nil, cam, v) end
    local ce, ze = c and ns.GetMap(c), z and ns.GetMap(z)
    local s = "centre:"
    if ze then s = ("%s %s (%.2fx of its own map)"):format(s, ze.name, ns.ZoomOf(v, ze, cam.vw)) end
    if ce then s = ("%s%s %s (%.2fx)"):format(s, ze and "," or "", ce.name, ns.ZoomOf(v, ce, cam.vw)) end
    out[#out + 1] = s
    local st = Render:Stats()
    -- (1.4.0-beta2: drawn - in view with an alpha -, shown - resident in the client, about 44 KB a tile -, live - with a
    -- file -, and the stages still loading)
    out[#out + 1] = ("textures %d drawn, %d shown (about %d MB), %d live of %d (peak %d), %d loading%s"):format(st.drawn, st.shown,
        math.floor(st.mb + 0.5), st.live, TL.LIVE_MAX, st.peak, st.loading,
        st.maskFail > 0 and (", " .. st.maskFail .. " masks refused") or "")
    if IMG then IMG:ZoomLines(out) end -- (1.4.0-beta3: the minimap imagery - RetailImagery.lua)
end
