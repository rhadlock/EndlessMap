--[[
Endless Map - RetailImagery.lua (1.4.0-beta3; retail only: AzerothUnrolled_Standard.toc, after RetailRender.lua)

The minimap imagery on retail - WoW Forever's MinimapLayer.lua (1.3.0: the map drawn from the game's own minimap
pictures, the real terrain, instead of the drawn map; the fog of war; the sub-zone names; the client's own tiles at the
deepest zooms) on every world the placement tree draws (docs/retail-engine.md 14.2: the data - RetailMinimap<Pack>.lua,
one pack a continent or world; 14.4: this file). It is ns.MinimapLayer on retail: Options.lua ("imagery",
"imageryTiles"), MapMenu.lua (the imagery button and its live preview) and Labels.lua (the bands while it shows, the
sub-zone names - ns.MINIMAP_SUBZONES) ask it as they ask WoW Forever's.

  * HOSTS (the data's hosts: a world, a continent, an inset, a phase copy - a tree node whose own picture the imagery
    lies on) draw in a HOLDER each: a frame of the overlay (never another's - no nested clipping host, design rule 9;
    never moved to another parent) the size of the host's picture in its own px, placed and scaled as RetailRender.lua
    places a stage's part. In it, bottom to top: the host's sea colour over its whole picture (not a copy's), then each
    placement's pages - level 1 (16 px a tile, the backdrop: all of it, loaded before the host shows), 2 and 3 (32, 64
    px: a window round the view), 4 the client's own tiles by fileDataID (from CLIENT_IN texels a physical px while at
    most CLIENT_MAX are in view and "imageryTiles" is on) - clipped to the placement's box, a land-masked placement (lm)
    through its land masks (its 64-px pages only, at every level). Every texture of a host through the host's SOFT
    edge: a continent's own land mask (Masks/Retail/c<id>.tga: Kul Tiras never under the Eastern Kingdoms' sea - as its
    drawn picture), anything else Masks/Retail/soft.tga laid over its picture - an inset's over its printed box opening
    to its whole picture as RetailRender.lua's clip does (st.open). Azeroth (947, no host: its continents are) is its
    sea colour only, through soft.tga.
  * A WORLD's imagery comes by a switch (IMG_ON of its own zoom - it fits the view, its globe's circle open; off below
    IMG_OFF): the hosts of a world load from IMG_LOAD (shown at alpha 0 - the client loads only what is visible), its
    switch fades in once their backdrops in view are loaded and faded in whole (at alpha 0). The holders lie right over
    the Cosmic map, under every other picture of ours (RetailRender.lua PlaceParts): in the switch's first half they come
    in whole under the drawn pictures of that world, in its second half those fade out over them (I:Fade -
    RetailRender.lua PlanNode; a holder partly faded showed its pages as darker squares over its sea, each texture
    taking the holder's alpha on its own), and whole they are planned at alpha 0 - but the root's,
    the capitals underground (KEEP_CITY: Ironforge, the Undercity) and the floors. Going out it waits for the drawn world
    picture to be loaded again, which fades back in over it ((1.4.0-beta4's fixes) as long as that takes - PARENT_WAIT, 2 s
    at most, went with the other nets; a world off the view, nothing of it to see, goes at once). An inset's imagery comes
    and goes with its drawn picture's switch; a copy's while its group shows it.
  * FOG OF WAR (technique A, WoW Forever's): from a host's zoom FOG_C0 (the zone cells' 2.5) to FOG_C1 every picture is
    desaturated (FOG_DESAT) and dimmed (FOG_DIM); full-colour copies of the pictures lie over it through each explored
    piece of the zones near the view (TL.Pieces - C_MapExplorationInfo, Blizzard's tiling: a mask a piece tile, a union
    as stacked copies), the zones lit whole ("a": the capitals, cities) through their cut-out, and the open sea through
    each 64-px page's sea mask. MAP_EXPLORATION_UPDATED (Render:MarkArtDirty) rebuilds the copies: those that stay keep
    their texture.
  * The real client's rules (docs/retail-engine.md 11): every texture shown at alpha 0 while it loads (never hidden),
    pooled per holder and keyed by what it shows (a window rebuilt keeps what stays in it), its masks waited for as it is
    (1.4.0-beta4: no MASK_GIVEUP - the client never needed one); caps MAX_TEX / MAX_MASKS; the textures go 10 s after the
    map closes (Render:ReleaseAll) or when the imagery is switched off.
  * While it shows: its backdrop over the view counts as ready (Core hides Blizzard's canvas while moving detached), Blizzard's
    exploration pin at alpha 0 (a post-hook on that one pin, as MinimapLayer.lua's), the zone names stay on deeper and the
    sub-zone names come with their pieces (Labels.lua).
  * (1.4.0-beta3, the reviews of 1.4.0-beta3) Never more than the drawn map's footprint: a continent's sea fill through
    its land mask (its own sea past its world as far as its drawn picture's), none where every placement is land-masked
    (Khaz Algar) - through soft.tga over a continent's whole picture it hung that rectangle out into space. A picture
    fades in once it is loaded, however long that takes ((1.4.0-beta4's fixes) 1.4.0-beta3's LOAD_TIMEOUT faded one in
    after 2 s loaded or not - t.gave - and 1.4.0-beta4 dropped only its failure for the session: the add-on's pictures
    drew in the player's client, photo 75); its world's switch waits for its backdrop; its load time, from its holder's
    first visible frame, goes to the stamp (RetailTiles.lua TL.Watch - the stamp's load.slow counts one that takes long).
    The caps count what holds a file (a long session's pools reached MAX_TEX made and every
    host was refused, the map drawing every frame); a window short at a cap waits for room (capGen); a holder given back
    goes with its pools to the next host (Shelve). A holder shown again counts its textures against the frame's room -
    one off the screen waits for a frame with room. In a soft edge one picture at a time (h.smask, EDGE_IN): the sea
    colour through the soft rect, level 1 through it shrunk, levels 2 - 4 through it shrunk more - stacked through one
    edge they stepped at every window's edge; a continent's pages through its world's soft rect so shrunk, grown with
    its drawn picture's switch (LayEdges) - at the world's fit its pages stood whole to their own edge in the world's.
  * (1.4.0-beta4) A world's imagery switches by its own zoom alone, wherever the view's centre lies (1.4.0-beta3 switched it
    only for the world under the centre: the Vaults of Atal'Utek, past Azeroth's picture, never showed theirs); a holder
    shown again keeps each picture the client still has (IsObjectLoaded) and loads again those it let go - never a timer
    (HIDE_GRACE); every picture's load time goes to the stamp (RetailTiles.lua TL.RecordLoad).
]]
local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)
if ns.FLAVOR ~= "retail" then return end

local D = ns.RETAIL_MINIMAP
local R, TL = ns.Render, ns.RetailTiles
if type(D) ~= "table" or type(D.hosts) ~= "table" or type(D.packs) ~= "table" or not (R and TL) then return end

local I = {}
ns.RetailImagery = I
ns.MinimapLayer = I        -- (the interface Options.lua, MapMenu.lua and Labels.lua ask - WoW Forever's MinimapLayer.lua)
ns.MINIMAP_SUBZONES = D.subzones -- (Labels:AddSubzones - the rows are WoW Forever's format)

local TEST = ns.retailTest or {}
local T = 1600 / 3                        -- yards a minimap tile
local COMP_TEXELS, LEVEL_HYS = 1, 1.25    -- a composite serves while it has this many texels a physical px; hysteresis
local CLIENT_IN, CLIENT_OUT, CLIENT_MAX = 2, 2.5, 200
local WIN_MARGIN, WIN_KEEP, WIN_SHRINK = 0.5, 0.15, 1.6
local FOG_MARGIN, FOG_KEEP = 0.25, 0.05
local LOAD_FADE = 0.15
local LEVEL_FADE, HOST_FADE = 0.2, 0.15
local FOG_C0, FOG_C1, FOG_PRE = 2.5, 4, 2
local FOG_DESAT, FOG_DIM = 0.9, 0.6
local MAX_TEX, MAX_MASKS = 3000, 1200
local IMG_ON, IMG_OFF, IMG_LOAD = 0.97, 0.93, 0.8
local SWITCH_FADE = 0.3
local COPY_BUDGET = 300
local LAYERS = { "BACKGROUND", "BORDER", "ARTWORK", "OVERLAY" }
local SEA_SUB = 7
local SOFT = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\soft.tga"
-- ((1.4.0-beta3, the renders of the reviews' fixes) the levels' soft edges: soft.tga over a host's soft rect shrunk by
-- these px of a 1002 x 668 picture - level 1's, levels 2 - 4's (h.smask; DrawHost lays them, AddEdge gives them)
local EDGE_IN = { 40, 110 }
local CLAMP, FILTER = "CLAMP", "TRILINEAR"
-- (the capitals underground and the floors keep their drawn maps over the imagery, as WoW Forever's KEEP_CITY: the
-- surface imagery shows Stormwind, Orgrimmar, Thunder Bluff, Darnassus; the Undercity's copy 998 too)
I.KEEP_CITY = { [87] = true, [90] = true, [998] = true }
I.CLIENT_IN, I.CLIENT_OUT, I.CLIENT_MAX, I.MAX_TEX, I.MAX_MASKS = CLIENT_IN, CLIENT_OUT, CLIENT_MAX, MAX_TEX, MAX_MASKS
I.FOG_DESAT, I.FOG_DIM, I.FOG_C0, I.FOG_C1, I.IMG_ON, I.IMG_OFF = FOG_DESAT, FOG_DIM, FOG_C0, FOG_C1, IMG_ON, IMG_OFF

local hosts = {}        -- [entry] = its host (made when first near the view)
local shownH = {}       -- the hosts placed this frame, bottom to top
local worlds = {}       -- [world entry] = { sw, sa, offAt, ready } its imagery switch
local mapData = {}      -- [pack .. ":" .. m] = the game map's pages, tiles, sea / land sets
local pending, fading = {}, {}
local tilesOf, setOf = {}, {}             -- [zone id] = its explored pieces as mask tiles (this fogGen) / their keys
local fogGen = 0
-- (nTex: texture objects made - pooled, never freed; nLive (1.4.0-beta3, the reviews of 1.4.0-beta3): those holding
-- a file or a colour now - the cap's count; capHit: a texture refused at the cap this frame)
local nTex, nMask, nSkipped, nLive, nMaskLive = 0, 0, 0, 0, 0
local capHit = false
local shells = {}       -- ((1.4.0-beta3) the holders of hosts given back, with their pools, for the next host made)
local cap = { tex = MAX_TEX, masks = MAX_MASKS }
local now, dt, lastT = 0, 0, nil
local V = {}            -- this frame: view (x0..y1 in the root's units), ppx, ppy, vw, phys, pf (the prefetch's view)
local active = false    -- a world's imagery shows (Labels.lua's bands; the button's glow and picture)
local overlay
local copyBudget, copiesShort = COPY_BUDGET, false
local pin, pinHooked, pinHidden = nil, false, false
local preview = {}
local lastCam

local function Clamp01(x) if x < 0 then return 0 elseif x > 1 then return 1 end return x end
local function Smooth(x) x = Clamp01(x) return x * x * (3 - 2 * x) end
local function Plain(v, kind) return type(v) == kind and not (issecretvalue and issecretvalue(v)) end

---------------------------------------------------------------------------
-- The interface (WoW Forever's MinimapLayer.lua's)
---------------------------------------------------------------------------
function I:Supported() return next(D.packs) ~= nil end
function I:On() return ns.db ~= nil and ns.db.imagery == true end
function I:TilesOn() return ns.db ~= nil and ns.db.imageryTiles == true end
function I:Active() return active end

---------------------------------------------------------------------------
-- The data: a game map's pages, tiles and masks (parsed once)
---------------------------------------------------------------------------
local function Pairs(s, out)
    for a, b in (s or ""):gmatch("(%d+),(%d+)") do out[tonumber(b) * 1024 + tonumber(a)] = true end
    return out
end

local function MapData(pack, m)
    local key = pack .. ":" .. m
    local md = mapData[key]
    if md ~= nil then return md or nil end
    local P = D.packs[pack]
    local src = P and P.maps and P.maps[m]
    if not src then
        mapData[key] = false
        return nil
    end
    md = { m = m, px = src.px or 512, path = P.path, maskPath = P.maskPath, pages = {}, tiles = {}, sea = Pairs(src.sea, {}),
        land = Pairs(src.land, {}) }
    for _, L in ipairs(D.lods or { 16, 32, 64 }) do md.pages[L] = Pairs(src.pages and src.pages[L], {}) end
    for c, r, f in (src.tiles or ""):gmatch("(%d+),(%d+),(%d+)") do md.tiles[tonumber(r) * 1024 + tonumber(c)] = tonumber(f) end
    mapData[key] = md
    return md
end

-- The levels of a host: 1 - 3 the composites of 16, 32, 64 px a tile, 4 the client's own tiles.
local function NewLevels()
    local lev = {}
    for i, px in ipairs({ 16, 32, 64, 0 }) do
        lev[i] = { i = i, px = px, n = (px > 0) and (256 / px) or 1, layer = LAYERS[i], tex = {}, copies = {}, a = 0, gen = 0 }
    end
    return lev
end

-- The world of entry e: its ancestor right under the Cosmic map (itself for a world).
local worldOf = {}
local function WorldOf(e)
    local w = worldOf[e]
    if w ~= nil then return w or nil end
    -- ((1.4.0-beta3) a cell by its zone - a home's cover is an entry of its home itself: RetailCells.lua)
    local p, guard = (e.kind == "cell" and e.cellOf) or e, 0
    while p and p.pe and p.pe.pe and guard < 16 do p, guard = p.pe, guard + 1 end
    w = (p and p.pe) and p or false
    worldOf[e] = w
    return w or nil
end

-- Host e (an entry of ns.SpaceAll whose map the data hosts; 947: its sea alone).
local function Host(e)
    local h = hosts[e]
    if h then return h end
    local d = D.hosts[e.id]
    local kind = d and d.kind
    if not d then
        if e.id ~= ns.WORLD_MAP_ID then return nil end
        -- (Azeroth: its continents are hosts; its own picture is the sea between them - Kalimdor's colour)
        local k = D.hosts[12]
        d = { kind = "globe", sea = k and k.sea or { 0, 0.1137, 0.1569 } }
        kind = "sea"
    end
    h = { e = e, d = d, kind = kind, rows = {}, lev = NewLevels(), masks = {}, freeTex = {}, freeMask = {}, zones = {},
        a = 0, ra = 0, w = WorldOf(e) }
    -- ((1.4.0-beta4's fixes) a continent - and an inset with its land mask (RetailTree.lua m): its pictures through it, as its
    -- drawn picture is, never an opening box)
    h.landMask = kind == "cont" or (kind == "inset" and e.node ~= nil and e.node.m ~= nil)
    for i, r in ipairs(d) do
        local md = MapData(d.pack, r[1])
        if md then
            local row = { ri = i, m = r[1], md = md, wx0 = r[2], wx1 = r[3], wy0 = r[4], wy1 = r[5], u0 = r[6], v0 = r[7], u1 = r[8],
                v1 = r[9], lm = r[10] == 1 }
            local ku, kv = (row.u1 - row.u0) / (row.wy1 - row.wy0), (row.v1 - row.v0) / (row.wx1 - row.wx0)
            -- (tile column c spans u = uc0 + c * ucs .. + ucs of the host's picture; row r likewise in v)
            row.uc0, row.ucs = row.u0 + (row.wy1 - 32 * T) * ku, T * ku
            row.vr0, row.vrs = row.v0 + (row.wx1 - 32 * T) * kv, T * kv
            h.rows[#h.rows + 1] = row
        end
    end
    -- (a tile's width in the host's picture: the full-picture row's)
    h.ucs = h.rows[1] and h.rows[1].ucs or nil
    for id, z in pairs(D.zones) do
        for k = 2, #z - 4, 5 do
            if z[k] == e.id then h.zones[#h.zones + 1] = { id = id, fog = z[1], u0 = z[k + 1], v0 = z[k + 2], u1 = z[k + 3], v1 = z[k + 4] } end
        end
    end
    -- (does a larger host of its world - drawn below it - overlap its picture? Then its sea keeps its land mask: Pandaria's
    -- over Kalimdor's south-east)
    if kind == "cont" then
        for _, o in ipairs(ns.SpaceAll or {}) do
            local od = o ~= e and D.hosts[o.id]
            if od and od.kind ~= "copy" and o.area > e.area and WorldOf(o) == h.w and o.x0 < e.x1 and e.x0 < o.x1 and o.y0 < e.y1 and e.y0 < o.y1 then
                h.overlaps = true
            end
        end
        -- ((1.4.0-beta3) and its sea a colour of its own against its world's - the client's deep sea is one colour a game
        -- map: Northrend's, Pandaria's, Khaz Algar's surface's are not Kalimdor's: through soft.tga their fills lay
        -- rectangles of another blue on Azeroth's sea; through the land mask a tint along their coasts)
        local wd = h.w and (D.hosts[h.w.id] or (h.w.id == ns.WORLD_MAP_ID and D.hosts[12]))
        local ws, cs = wd and wd.sea, d.sea
        if ws and cs and (math.abs(ws[1] - cs[1]) > 0.01 or math.abs(ws[2] - cs[2]) > 0.01 or math.abs(ws[3] - cs[3]) > 0.01) then
            h.overlaps = true
            -- (every placement of it land-masked - Khaz Algar: its fill is all the sea it shows, its land mask a rectangle
            -- round the Isle of Dorn and the underground: its world's colour, one sea from Kalimdor to Dorn)
            local allLm = #h.rows > 0
            for _, row in ipairs(h.rows) do if not row.lm then allLm = false end end
            if allLm then h.fillSea, h.noFill = ws, true end
        end
    end
    hosts[e] = h
    return h
end

---------------------------------------------------------------------------
-- Holders, pooled textures and masks (each holder its own: a texture never moves to another frame)
---------------------------------------------------------------------------
-- (the frame's budget, shared with RetailRender.lua's stages - RetailTiles.lua: at most NEW_PER_FRAME new SetTexture and
-- SHOW_PER_FRAME textures newly shown a game frame; a window or the copies not done go on in the next frame)
-- (a picture and its masks: at most 4 SetTexture)
local function Room() return TL.newThisFrame + 4 <= TL.NEW_PER_FRAME and TL.newShown < TL.SHOW_PER_FRAME end
local function Spent(set, shown)
    TL.newThisFrame = TL.newThisFrame + set
    TL.newShown = TL.newShown + shown
end

-- ((1.4.0-beta3, the reviews of 1.4.0-beta3) a texture or mask object of holder f: one of its pools, else a new one
-- - never another frame's; the cap counts those holding a file or a colour (nLive, nMaskLive), not those ever made: the
-- pools are per holder, and a long session's tour reached MAX_TEX made by its 136th place, every host refused from there
-- and the map drawing every frame, its windows rebuilt to no end. A holder given back goes with its pools to the next
-- host made - a frame may move whole: Shelve, Holder)
local capGen, capped = 0, false
local function TakeTex(h, layer, sub)
    if nLive >= cap.tex then
        nSkipped, capHit, capped = nSkipped + 1, true, true
        return nil
    end
    local t = table.remove(h.freeTex)
    if not t then
        nTex = nTex + 1
        t = h.holder:CreateTexture(nil, layer)
    end
    t:SetDrawLayer(layer, sub)
    nLive = nLive + 1
    h.nt = (h.nt or 0) + 1
    return t
end
local function TakeMask(h)
    if nMaskLive >= cap.masks then
        nSkipped, capHit, capped = nSkipped + 1, true, true
        return nil
    end
    local m = table.remove(h.freeMask)
    if not m then
        nMask = nMask + 1
        m = h.holder:CreateMaskTexture()
    end
    nMaskLive = nMaskLive + 1
    return m
end
local function GiveTex(h, t)
    t:Hide()
    t:ClearAllPoints()
    t:SetTexture(nil)
    h.freeTex[#h.freeTex + 1] = t
    nLive = nLive - 1
    h.nt = (h.nt or 1) - 1
    -- (room again under the cap: the windows and copies short at it are built again - EnsureWindow, BuildCopies)
    if capped and nLive < cap.tex - 32 and nMaskLive < cap.masks - 8 then capped, capGen = false, capGen + 1 end
end
local function GiveMask(h, m)
    TL.Unwatch(m)
    m:Hide()
    m:ClearAllPoints()
    m:SetTexture(nil)
    m.key, m.file, m.host, m.lx, m.ly, m.lw, m.lh = nil, nil, nil, nil, nil, nil, nil
    h.freeMask[#h.freeMask + 1] = m
    nMaskLive = nMaskLive - 1
end

local function Holder(h)
    if h.holder then return h.holder end
    if not Room() then return nil end
    local e = h.e
    -- ((1.4.0-beta3) a holder given back, with its pools - Shelve)
    local sh = table.remove(shells)
    local f
    if sh then
        f = sh.f
        h.freeTex, h.freeMask = sh.freeTex, sh.freeMask
        f:ClearAllPoints()
        f:SetScale(1)
    else
        f = CreateFrame("Frame", nil, overlay)
        f:EnableMouse(false)
    end
    f:SetSize(e.lw, e.lh)
    f:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0)
    f:SetAlpha(0)
    f:Hide()
    f.level = nil
    h.holder, h.HW, h.HH = f, e.lw, e.lh
    h.scale, h.sx0, h.sy0, h.hmx, h.hmy, h.hmw, h.hmh = nil, nil, nil, nil, nil, nil, nil
    -- (its soft edge: a continent's land mask, else soft.tga - laid each frame, an inset's over its opening box)
    if h.kind ~= "copy" then
        local m = TakeMask(h)
        if not m then
            h.holder = nil
            sh = sh or { f = f, freeTex = h.freeTex, freeMask = h.freeMask }
            shells[#shells + 1] = sh
            return nil
        end
        -- ((1.4.0-beta4's fixes) a continent's imagery land mask where it differs from its drawn picture's - RetailTree.lua mi:
        -- the Eastern Kingdoms' with Vashj'ir's sea floor, which its drawn picture leaves to Vashj'ir's own cut-out)
        local file = (h.landMask and (e.node.mi or e.node.m)) or SOFT
        m:SetTexture(file, CLAMP, CLAMP, FILTER)
        m:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        m:SetSize(e.lw, e.lh)
        m:Show()
        m.t0, m.file, m.host, m.mfile = now, file, true, file
        TL.Watch(m, nil, true, f, "mask") -- ((1.4.0-beta4's fixes, probe P1) its load measured as every mask's)
        -- ((1.4.0-beta3, the renders of the reviews' fixes) and its levels' soft edges (h.smask, laid by DrawHost): a
        -- host through soft.tga, or a continent of a world, has its pages through soft.tga over its soft rect shrunk by
        -- EDGE_IN - level 1's inside its sea fill's edge, levels 2 - 4's inside level 1's -, so that in a soft edge one
        -- picture shows at a time: through the one soft edge, each over the one below, they covered 1 - (1 - a)^n where
        -- n of them lay - the edge's fade stepping at every window's and page's edge (Outland's fit, b3_imgoutfit:
        -- black steps of 20 px down its void's edge); a continent's pages through its world's (b3_imgazfit: past
        -- Azeroth's opaque middle the Eastern Kingdoms', Northrend's and Pandaria's pages stood whole to their page's
        -- edge, hard lines through their land)
        local sm
        if #h.rows > 0 and (h.kind ~= "cont" or (h.w and h.w ~= e)) then
            sm = {}
            for j = 1, 2 do
                local x = TakeMask(h)
                if not x then
                    for _, y in ipairs(sm) do GiveMask(h, y) end
                    GiveMask(h, m)
                    h.holder = nil
                    sh = sh or { f = f, freeTex = h.freeTex, freeMask = h.freeMask }
                    shells[#shells + 1] = sh
                    return nil
                end
                x:SetTexture(SOFT, CLAMP, CLAMP, FILTER)
                x:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
                x:SetSize(e.lw, e.lh)
                x:Show()
                x.t0, x.file, x.host, x.mfile = now, SOFT, true, SOFT
                TL.Watch(x, nil, true, f, "mask")
                sm[j] = x
            end
            Spent(2, 0)
        end
        h.hmask, h.smask = m, sm
        Spent(1, 0)
        -- ((1.4.0-beta3, the reviews of 1.4.0-beta3) the sea fill through the same soft edge - a continent's through
        -- its land mask, so its sea reaches past its world only as far as its drawn picture's (the mask's own vignette): a
        -- continent's fill through soft.tga over its whole picture hung its rectangle out into space - Kalimdor's west of
        -- Azeroth's globe, at rest at Azeroth's fit (b3_imgazfit, b3_imgdurotar out); none where every placement is
        -- land-masked (Khaz Algar: its world's sea is under it - its land mask's boxes round the Isle of Dorn and the
        -- underground stood as notches past Azeroth's edge)
        local s = (not h.noFill) and TakeTex(h, "BACKGROUND", -8)
        if s then
            local c = h.d.sea or { 0, 0, 0 }
            s:SetColorTexture(c[1], c[2], c[3], 1)
            s:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
            s:SetSize(e.lw, e.lh)
            s:SetAlpha(0)
            s:AddMaskTexture(m)
            s.mk = { m }
            s.a, s.t0, s.at = 0, now, now -- (a colour: nothing to load - its soft edge's mask is waited for by the pictures)
            s:Show()
            h.fill = s
            Spent(1, 1)
        end
    end
    return f
end

-- ((1.4.0-beta3) Host h's holder and pools to the shells - its fill and soft edge given back first; the host keeps its
-- data and takes a holder again when it comes back near the view)
local function Shelve(h)
    local f = h.holder
    if not f then return end
    if h.fill then
        h.fill:RemoveMaskTexture(h.hmask)
        h.fill.mk = nil
        GiveTex(h, h.fill)
        h.fill = nil
    end
    if h.smask then
        for _, x in ipairs(h.smask) do GiveMask(h, x) end
        h.smask = nil
    end
    if h.hmask then
        GiveMask(h, h.hmask)
        h.hmask = nil
    end
    f:Hide()
    f:SetAlpha(0)
    shells[#shells + 1] = { f = f, freeTex = h.freeTex, freeMask = h.freeMask }
    h.holder, h.freeTex, h.freeMask = nil, {}, {}
end

local function NewTex(h, layer, sub)
    if not Room() then return nil end
    local t = TakeTex(h, layer, sub)
    if not t then return nil end
    t:ClearAllPoints()
    t:SetAlpha(0)
    t.a, t.at, t.fl, t.t0 = 0, nil, nil, now
    t.f0 = TL.tick
    t.mk = t.mk or {}
    pending[t] = true
    t:Show()
    return t
end

local function UnrefMask(h, m)
    m.refs = m.refs - 1
    if m.refs > 0 then return end
    h.masks[m.key] = nil
    GiveMask(h, m)
end

local function FreeTex(h, t)
    for k = #t.mk, 1, -1 do
        local m = t.mk[k]
        t:RemoveMaskTexture(m)
        if not m.host then UnrefMask(h, m) end -- (the host's own - h.hmask, h.smask - stay)
        t.mk[k] = nil
    end
    if t.desat then
        if t.SetDesaturation then t:SetDesaturation(0) elseif t.SetDesaturated then t:SetDesaturated(false) end
        t:SetVertexColor(1, 1, 1, 1)
        t.desat = nil
    end
    t.key, t.base, t.at, t.a, t.fl, t.file, t.row, t.lmk = nil, nil, nil, nil, nil, nil, nil, nil
    pending[t], fading[t] = nil, nil
    TL.Unwatch(t)
    GiveTex(h, t)
end

-- A mask M (key, file, mx, my, mw, mh: the whole file in host px) of host h - shared, counted.
local function MaskFor(h, M)
    local m = h.masks[M.key]
    if m then
        m.refs = m.refs + 1
        return m
    end
    if not Room() then return nil end
    m = TakeMask(h)
    if not m then return nil end
    m:SetTexture(M.file, CLAMP, CLAMP, FILTER)
    Spent(1, 0)
    m:ClearAllPoints()
    m:SetSize(M.mw, M.mh)
    m:SetPoint("TOPLEFT", h.holder, "TOPLEFT", M.mx, -M.my)
    m:Show()
    m.key, m.file, m.refs, m.t0, m.mfile = M.key, M.file, 1, now, M.file
    -- ((1.4.0-beta4's fixes, probe P1) the imagery's masks measured too - 1.4.0-beta4 left them out)
    if type(M.file) == "string" then TL.Watch(m, nil, true, h.holder, "mask") end
    h.masks[M.key] = m
    return m
end

-- Texture t shows host px rect (x0, y0, x1, y1) of the picture `file` spanning (fx0, fy0, fx1, fy1).
local function Put(h, t, file, x0, y0, x1, y1, fx0, fy0, fx1, fy1)
    t:SetTexture(file, CLAMP, CLAMP, FILTER)
    Spent(1, 1)
    local w, hh = fx1 - fx0, fy1 - fy0
    t:SetTexCoord((x0 - fx0) / w, (x1 - fx0) / w, (y0 - fy0) / hh, (y1 - fy0) / hh)
    t:SetSize(x1 - x0, y1 - y0)
    t:SetPoint("TOPLEFT", h.holder, "TOPLEFT", x0, -y0)
    t.x0, t.y0, t.x1, t.y1, t.file = x0, y0, x1, y1, file
    t.fx0, t.fy0, t.fx1, t.fy1 = fx0, fy0, fx1, fy1
end

local function AddMask(t, m)
    t:AddMaskTexture(m)
    t.mk[#t.mk + 1] = m
end

---------------------------------------------------------------------------
-- Windows: the pages (or client tiles) of a level over a rect of the host's picture
---------------------------------------------------------------------------
-- The land mask of game map row.m's 64-px page (p, q) (nil: land all over).
local function LandMask(h, row, p, q)
    local md = row.md
    if not md.land[q * 1024 + p] then return nil end
    local n = 4
    return MaskFor(h, { key = ("land:%d:%d:%d"):format(row.ri, p, q), file = ("%sland_%d_%d_%d.tga"):format(md.maskPath, row.m, p, q),
        mx = (row.uc0 + p * n * row.ucs) * h.HW, my = (row.vr0 + q * n * row.vrs) * h.HH, mw = n * row.ucs * h.HW, mh = n * row.vrs * h.HH })
end

-- ((1.4.0-beta3, the renders of the reviews' fixes) Picture t of level i of host h through its soft edges: a
-- continent's land mask first, then its level's soft edge (h.smask: a continent's world's - DrawHost); a host through
-- soft.tga takes its level's soft edge in its place (its sea fill keeps h.hmask). The pictures of a continent past its
-- world picture's opaque middle came with its drawn picture's switch, each whole or not (1.4.0-beta3's Outside): at the
-- world's fit a page there stood whole to its own edge, a hard line through the land)
local function AddEdge(h, t, i)
    local s = h.smask and h.smask[i == 1 and 1 or 2]
    if h.hmask and (h.landMask or not s) then AddMask(t, h.hmask) end
    if s then AddMask(t, s) end
end

-- ((1.4.0-beta4) a placement's pictures above the placements before it - the data's order, bottom to top (14.4): its
-- level's draw layer at sublevel 2 x (row - 1), its fog copies one above. At one sublevel for every row the order was
-- the order the textures were made in - a pairs walk: Vashj'ir's sea floor, a placement over the Eastern Kingdoms'
-- own tiles, came out as a patchwork of its pages and the flat sea's - b4d_imgek; the sea copies stay on OVERLAY's top,
-- SEA_SUB: at most 3 placements a host - sublevels 0 - 5 -, which build_retail_layer.py's write_lua holds the packs to)
local function RowSub(row) return 2 * (row.ri - 1) end

-- Level lev of host h shows its cells over host-fraction rect (a0, b0, a1, b1).
local function BuildWindow(h, lev, a0, b0, a1, b1)
    local want = {}
    lev.win = { a0, b0, a1, b1 }
    lev.short = nil
    capHit = false
    for _, row in ipairs(h.rows) do
        local md = row.md
        local L = lev.px
        local n
        local set
        if lev.i == 4 then
            n, set = 1, md.tiles
        elseif row.lm then
            n, set, L = 4, md.pages[64], 64 -- (a land-masked placement: its 64-px pages only - a land mask a 64-px page)
        else
            n, set = lev.n, md.pages[L]
        end
        local x0, x1 = math.max(a0, row.u0), math.min(a1, row.u1)
        local y0, y1 = math.max(b0, row.v0), math.min(b1, row.v1)
        if x1 > x0 and y1 > y0 and set then
            local c0, c1 = math.floor((x0 - row.uc0) / row.ucs / n), math.floor((x1 - row.uc0) / row.ucs / n)
            local r0, r1 = math.floor((y0 - row.vr0) / row.vrs / n), math.floor((y1 - row.vr0) / row.vrs / n)
            for q = math.max(0, r0), math.min(1023, r1) do
                for p = math.max(0, c0), math.min(1023, c1) do
                    if set[q * 1024 + p] then want[row.ri * 1048576 + q * 1024 + p] = L end
                end
            end
        end
    end
    for k, t in pairs(lev.tex) do
        if not want[k] then
            FreeTex(h, t)
            lev.tex[k] = nil
        end
    end
    for k, L in pairs(want) do
        if not lev.tex[k] then
            local ri = math.floor(k / 1048576)
            local key = k % 1048576
            local p, q = key % 1024, math.floor(key / 1024)
            local row = h.rows[ri]
            local md = row.md
            local n = (lev.i == 4) and 1 or (256 / L)
            -- (the cell's rect in the host's picture, and the part of it inside the placement's box)
            local fx0, fy0 = (row.uc0 + p * n * row.ucs) * h.HW, (row.vr0 + q * n * row.vrs) * h.HH
            local fx1, fy1 = fx0 + n * row.ucs * h.HW, fy0 + n * row.vrs * h.HH
            local x0, y0 = math.max(fx0, row.u0 * h.HW), math.max(fy0, row.v0 * h.HH)
            local x1, y1 = math.min(fx1, row.u1 * h.HW), math.min(fy1, row.v1 * h.HH)
            if x1 - x0 > 1e-3 and y1 - y0 > 1e-3 then
                -- (a land-masked placement's picture never without its land mask: its own sea would show)
                local lmk, ok = nil, true
                if row.lm then
                    local lq, lp = (lev.i == 4) and math.floor(q / 4) or q, (lev.i == 4) and math.floor(p / 4) or p
                    if md.land[lq * 1024 + lp] then
                        lmk = LandMask(h, row, lp, lq)
                        ok = lmk ~= nil
                    end
                end
                local t = ok and NewTex(h, lev.layer, RowSub(row))
                if t then
                    local file = (lev.i == 4) and md.tiles[key] or ("%s%d_%d_%d_%d.blp"):format(md.path, row.m, L, p, q)
                    Put(h, t, file, x0, y0, x1, y1, fx0, fy0, fx1, fy1)
                    -- ((1.4.0-beta4's fixes, probe P1) its load time from its holder's first visible frame, as every
                    -- texture's - 1.4.0-beta4 timed it from its making; a fog copy - the same file - is not counted again)
                    TL.Watch(t, nil, nil, h.holder, (lev.i == 4) and "tile" or "file")
                    AddEdge(h, t, lev.i)
                    if lmk then
                        AddMask(t, lmk)
                        t.lmk = lmk
                    end
                    t.key, t.row = k, row
                    lev.tex[k] = t
                else
                    if lmk then UnrefMask(h, lmk) end
                    lev.short = true
                end
            end
        end
    end
    -- ((1.4.0-beta3) short at the cap: built again once there is room (capGen) or the window moves, not every frame -
    -- a frame's budget spent: the next frame)
    if lev.short and capHit then lev.short, lev.capGen = "cap", capGen end
    lev.live = true
    lev.gen = lev.gen + 1
end

-- (host-fraction rect a0..b1 grown by k of its size)
local function Grow(a0, b0, a1, b1, k)
    local w, hh = a1 - a0, b1 - b0
    return a0 - w * k, b0 - hh * k, a1 + w * k, b1 + hh * k
end

local function Fits(w, a, b, c, d, A, B, C, Dd)
    return w ~= nil and a >= w[1] and b >= w[2] and c <= w[3] and d <= w[4]
        and w[3] - w[1] <= (C - A) * WIN_SHRINK and w[4] - w[2] <= (Dd - B) * WIN_SHRINK
end

local function Retry(lev) return lev.short == true or (lev.short == "cap" and lev.capGen ~= capGen) end
local function EnsureWindow(h, lev, a0, b0, a1, b1)
    if lev.i == 1 then
        if not lev.win or Retry(lev) then BuildWindow(h, lev, 0, 0, 1, 1) end -- (the backdrop: all of it)
        return
    end
    local k = (lev.i == 4) and math.max(h.ucs or 0, 0) or 0
    local a, b, c, d = Grow(a0, b0, a1, b1, WIN_KEEP)
    local A, B, C, Dd = Grow(a0, b0, a1, b1, WIN_MARGIN)
    if lev.i == 4 then
        -- (the client tiles: a tile round the view)
        a, b, c, d = a0 - k * 0.25, b0 - k * 0.25, a1 + k * 0.25, b1 + k * 0.25
        A, B, C, Dd = a0 - k, b0 - k, a1 + k, b1 + k
    end
    if Retry(lev) or not Fits(lev.win, a, b, c, d, A, B, C, Dd) then BuildWindow(h, lev, A, B, C, Dd) end
end

local function ReleaseLevel(h, lev)
    for ck, c in pairs(lev.copies) do
        FreeTex(h, c)
        lev.copies[ck] = nil
    end
    for k, t in pairs(lev.tex) do
        FreeTex(h, t)
        lev.tex[k] = nil
    end
    lev.live, lev.win, lev.a, lev.copyStamp, lev.short = nil, nil, 0, nil, nil
    lev.gen = lev.gen + 1
end

---------------------------------------------------------------------------
-- The fog of war: the explored pieces as mask tiles, the copies through them
---------------------------------------------------------------------------
-- (Labels.lua) Is explored-area piece (ox, oy, w, h) of zone id explored?
local function ExploredList(id)
    if not (C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures) or not Plain(id, "number") then return nil end
    local ok, res = pcall(C_MapExplorationInfo.GetExploredMapTextures, id)
    if not ok or type(res) ~= "table" then return nil end
    return res
end
function I:PieceExplored(id, ox, oy, w, h)
    local s = setOf[id]
    if not s then
        s = {}
        for _, info in ipairs(ExploredList(id) or {}) do
            if type(info) == "table" and Plain(info.textureWidth, "number") and Plain(info.textureHeight, "number") then
                local x, y = Plain(info.offsetX, "number") and info.offsetX or 0, Plain(info.offsetY, "number") and info.offsetY or 0
                s[("%d:%d:%d:%d"):format(x, y, info.textureWidth, info.textureHeight)] = true
            end
        end
        setOf[id] = s
    end
    return s[("%d:%d:%d:%d"):format(ox, oy, w, h)] == true
end

-- The cut-out of a zone lit whole ("a"): its city map's (RetailPlaces.lua), its cell's (RetailCellData.lua), else soft.
local function WholeMask(id)
    local P = ns.RETAIL_PLACES
    local c = P and P.city and P.city[id]
    if c and c.m then return c.m end
    for _, list in pairs(ns.RETAIL_CELLS or {}) do
        for _, cell in ipairs(list) do
            if cell.id == id and cell.m then return cell.m end
        end
    end
    return SOFT
end

-- The mask tiles of host h over host-fraction rect w: every explored piece of its zones there, its zones lit whole, its
-- sea pages (r.row: only over that placement's pictures).
local function MaskTiles(h, w)
    local out = {}
    local HW, HH = h.HW, h.HH
    for _, z in ipairs(h.zones) do
        if z.u0 < w[3] and z.u1 > w[1] and z.v0 < w[4] and z.v1 > w[2] then
            if z.fog == "a" then
                local x0, y0, x1, y1 = z.u0 * HW, z.v0 * HH, z.u1 * HW, z.v1 * HH
                out[#out + 1] = { key = "a:" .. z.id, file = WholeMask(z.id), mx = x0, my = y0, mw = x1 - x0, mh = y1 - y0,
                    ux0 = x0, uy0 = y0, ux1 = x1, uy1 = y1 }
            elseif z.fog == "o" then
                local key = h.e.id .. ":" .. z.id
                local Tt = tilesOf[key]
                if not Tt then
                    Tt = {}
                    local L = TL.Layout(z.id)
                    if L then
                        local kx, ky = (z.u1 - z.u0) * HW / L.lw, (z.v1 - z.v0) * HH / L.lh
                        local ox, oy = z.u0 * HW, z.v0 * HH
                        for _, it in ipairs(TL.Pieces(z.id, L)) do
                            -- (it: x0, y0, x1, y1 the used part in the zone's layer px, u1 / v1 its share of the file)
                            local fw, fh = (it[3] - it[1]) / it[5], (it[4] - it[2]) / it[6]
                            Tt[#Tt + 1] = { key = ("%d:%s:%d:%d"):format(z.id, tostring(it[7]), it[1], it[2]), file = it[7],
                                mx = ox + it[1] * kx, my = oy + it[2] * ky, mw = fw * kx, mh = fh * ky,
                                ux0 = ox + it[1] * kx, uy0 = oy + it[2] * ky, ux1 = ox + it[3] * kx, uy1 = oy + it[4] * ky }
                        end
                    end
                    tilesOf[key] = Tt
                end
                local wx0, wy0, wx1, wy1 = w[1] * HW, w[2] * HH, w[3] * HW, w[4] * HH
                for _, t in ipairs(Tt) do
                    if t.ux0 < wx1 and t.ux1 > wx0 and t.uy0 < wy1 and t.uy1 > wy0 then out[#out + 1] = t end
                end
            end
        end
    end
    -- (the open sea in colour: each 64-px page's sea mask, over its own placement's pictures; not a copy's - it has none)
    for _, row in ipairs(h.rows) do
        if not row.lm then
            local md, n = row.md, 4
            local seaRow = next(md.sea) ~= nil -- (a sea's map, not a void's: its deep sea in colour)
            local x0, x1 = math.max(w[1], row.u0), math.min(w[3], row.u1)
            local y0, y1 = math.max(w[2], row.v0), math.min(w[4], row.v1)
            if x1 > x0 and y1 > y0 then
                local c0, c1 = math.floor((x0 - row.uc0) / row.ucs / n), math.floor((x1 - row.uc0) / row.ucs / n)
                local r0, r1 = math.floor((y0 - row.vr0) / row.vrs / n), math.floor((y1 - row.vr0) / row.vrs / n)
                for q = math.max(0, r0), r1 do
                    for p = math.max(0, c0), c1 do
                        if md.sea[q * 1024 + p] then
                            local mx, my = (row.uc0 + p * n * row.ucs) * HW, (row.vr0 + q * n * row.vrs) * HH
                            local mw, mh = n * row.ucs * HW, n * row.vrs * HH
                            out[#out + 1] = { key = ("sea:%d:%d:%d"):format(row.ri, p, q), file = ("%ssea_%d_%d_%d.tga"):format(md.maskPath, row.m, p, q),
                                mx = mx, my = my, mw = mw, mh = mh, ux0 = mx, uy0 = my, ux1 = mx + mw, uy1 = my + mh, row = row.ri }
                        elseif seaRow and not md.pages[64][q * 1024 + p] then
                            -- ((1.4.0-beta3) a 64-px cell with no page at all is deep sea whole - no kept tile: a coarser
                            -- level's picture there, fogged with no sea mask over it, showed as a dark box in the sea:
                            -- its copy in full colour, no mask of its own)
                            local mx, my = (row.uc0 + p * n * row.ucs) * HW, (row.vr0 + q * n * row.vrs) * HH
                            local mw, mh = n * row.ucs * HW, n * row.vrs * HH
                            out[#out + 1] = { key = ("deep:%d:%d:%d"):format(row.ri, p, q), deep = true,
                                ux0 = mx, uy0 = my, ux1 = mx + mw, uy1 = my + mh, row = row.ri }
                        end
                    end
                end
            end
        end
    end
    return out
end

-- The full-colour copies of level lev's pictures through the mask tiles near the view.
local function BuildCopies(h, lev)
    local stamp = ("%d:%d:%d:%s:%d"):format(lev.gen, fogGen, h.fogWinGen or 0, tostring(h.fogPre), capGen)
    if lev.copyStamp == stamp then return end
    lev.copyStamp = stamp
    capHit = false
    local want = {}
    if h.fogPre and h.fogWin then
        for _, M in ipairs(MaskTiles(h, h.fogWin)) do
            for k, base in pairs(lev.tex) do
                if base.x0 < M.ux1 and base.x1 > M.ux0 and base.y0 < M.uy1 and base.y1 > M.uy0 and (not M.row or M.row == base.row.ri) then
                    want[k .. "|" .. M.key] = M
                end
            end
        end
    end
    for ck, c in pairs(lev.copies) do
        if not want[ck] or lev.tex[c.baseKey] ~= c.base then
            FreeTex(h, c)
            lev.copies[ck] = nil
        end
    end
    local short = false
    for ck, M in pairs(want) do
        if not lev.copies[ck] then
            if copyBudget <= 0 then
                short = true
                break
            end
            copyBudget = copyBudget - 1
            local k = tonumber(ck:match("^(%d+)|"))
            local base = lev.tex[k]
            local x0, y0 = math.max(base.x0, M.ux0), math.max(base.y0, M.uy0)
            local x1, y1 = math.min(base.x1, M.ux1), math.min(base.y1, M.uy1)
            if x1 - x0 > 1e-3 and y1 - y0 > 1e-3 then
                local c = NewTex(h, M.row and "OVERLAY" or lev.layer, M.row and SEA_SUB or (RowSub(base.row) + 1))
                local mk = c and (M.deep or MaskFor(h, M))
                if mk then
                    Put(h, c, base.file, x0, y0, x1, y1, base.fx0, base.fy0, base.fx1, base.fy1)
                    AddEdge(h, c, lev.i)
                    if base.lmk then
                        base.lmk.refs = base.lmk.refs + 1
                        AddMask(c, base.lmk)
                    end
                    if mk ~= true then AddMask(c, mk) end
                    c.base, c.baseKey, c.key, c.row = base, k, ck, base.row
                    lev.copies[ck] = c
                else
                    if c then FreeTex(h, c) end
                    short = true
                end
            end
        end
    end
    -- ((1.4.0-beta3) short at the cap: not again until there is room - capGen in the stamp)
    if short and capHit then short = false end
    if short then
        lev.copyStamp = nil
        copiesShort = true
    end
    h.copiesShort = short or nil
end

---------------------------------------------------------------------------
-- Alphas: each picture's load fade, its level's alpha, the fog
---------------------------------------------------------------------------
-- A picture's load fade: 0 until it and its masks are loaded, however long that takes, then up over LOAD_FADE.
-- ((1.4.0-beta4's fixes) 1.4.0-beta3's LOAD_TIMEOUT faded one in after 2 s, loaded or not - a net for a failure the
-- player's client never showed: its pictures drew, photo 75. Its load time: TL.PollLoads, from its first visible frame)
local function LoadA(t)
    if not t.at then
        local ok = TEST.noload
        if not ok then
            ok = not t.IsObjectLoaded or t:IsObjectLoaded()
            for k = 1, (ok and #t.mk or 0) do
                local m = t.mk[k]
                if m.IsObjectLoaded and not m:IsObjectLoaded() then
                    ok = false
                    break
                end
            end
        end
        if not ok then return 0 end
        t.at = now
        pending[t] = nil
        fading[t] = true
    end
    if TEST.nofade then
        fading[t] = nil
        return 1
    end
    local x = (now - t.at) / LOAD_FADE
    if x >= 1 then
        fading[t] = nil
        return 1
    end
    return Smooth(x)
end

local function SetA(t, a)
    a = math.floor(Clamp01(a) * 255 + 0.5) / 255
    if t.a ~= a then
        t:SetAlpha(a)
        t.a = a
    end
end

local function Fog(t, f)
    f = math.floor(f * 64 + 0.5) / 64
    if t.fl == f then return end
    t.fl = f
    if t.SetDesaturation then t:SetDesaturation(f * FOG_DESAT) elseif t.SetDesaturated then t:SetDesaturated(f >= 0.5) end
    local k = 1 - f * (1 - FOG_DIM)
    t:SetVertexColor(k, k, k, 1)
    t.desat = f > 0 or nil
end

-- Host h's alphas this frame; returns: its target covers the view (loaded, the level in), its backdrop loaded (every
-- level-1 picture), whole (faded in).
local function Alphas(h)
    local covered, backdrop, whole = true, true, true
    local loading = false
    local f, tgt = h.fog or 0, h.target
    local va, vb, vc, vd = h.view[1] * h.HW, h.view[2] * h.HH, h.view[3] * h.HW, h.view[4] * h.HH
    -- ((1.4.0-beta3, the reviews of 1.4.0-beta3) a continent's sea past its world's picture comes with its drawn picture's
    -- switch k, as the drawn continent's own sea past its world does; its pictures there come with its world's soft edge
    -- grown by k - DrawHost)
    local k = 1
    if h.kind == "cont" and R.StageSwitch then k = R:StageSwitch(h.e) end
    for i = 1, 4 do
        local lev = h.lev[i]
        if lev.live then
            for _, t in pairs(lev.tex) do
                local ta = LoadA(t)
                SetA(t, ta * lev.a)
                Fog(t, f)
                local inView = t.x0 < vc and t.x1 > va and t.y0 < vd and t.y1 > vb
                if ta < 1 then loading = true end
                if i == 1 and ta <= 0 then backdrop = false end
                if i == 1 and ta < 1 then whole = false end
                if i == tgt and ta < 1 and inView then covered = false end
            end
            for _, c in pairs(lev.copies) do
                local ca = LoadA(c)
                SetA(c, ca * lev.a * f)
                if ca < 1 and f > 0 then loading = true end
            end
        end
    end
    if h.fill then
        local fa = LoadA(h.fill)
        -- ((1.4.0-beta3) its sea fill likewise - inside its world the world's own sea lies under it: only past it, its own
        -- picture's vignette, does it show)
        SetA(h.fill, fa * k)
        if fa < 1 then whole = false end
    end
    h.loading = loading
    return covered and tgt ~= nil and h.lev[tgt].a >= 1, backdrop, whole
end

---------------------------------------------------------------------------
-- Choosing the level
---------------------------------------------------------------------------
local function ClientCount(h, a0, b0, a1, b1)
    local n = 0
    for _, row in ipairs(h.rows) do
        local x0, x1 = math.max(a0 - row.ucs, row.u0), math.min(a1 + row.ucs, row.u1)
        local y0, y1 = math.max(b0 - row.vrs, row.v0), math.min(b1 + row.vrs, row.v1)
        if x1 > x0 and y1 > y0 then
            for q = math.floor((y0 - row.vr0) / row.vrs), math.floor((y1 - row.vr0) / row.vrs) do
                for p = math.floor((x0 - row.uc0) / row.ucs), math.floor((x1 - row.uc0) / row.ucs) do
                    if row.md.tiles[q * 1024 + p] then n = n + 1 end
                end
            end
            if n > CLIENT_MAX then return n end
        end
    end
    return n
end

-- The level for adt physical px a tile over host-fraction rect a0..b1; cur: the level now (hysteresis).
local function Pick(h, adt, cur, a0, b0, a1, b1)
    local row = h.rows[1]
    local client = row and row.md.px or 512
    local d = client / adt
    if I:TilesOn() and (d <= CLIENT_IN or (cur == 4 and d <= CLIENT_OUT)) and ClientCount(h, a0, b0, a1, b1) <= CLIENT_MAX then return 4 end
    local want = adt * COMP_TEXELS
    local lev = h.lev
    if cur and cur <= 3 and lev[cur].px * LEVEL_HYS >= want and (cur == 1 or lev[cur - 1].px < want * LEVEL_HYS) then return cur end
    for i = 1, 3 do
        if lev[i].px >= want then return i end
    end
    return 3
end

-- Physical screen px per overlay unit (the user's 4K screen at UI scale 0.64: 1.8).
local function PhysPerUnit()
    local ph = 768
    if GetPhysicalScreenSize then
        local ok, _, hh = pcall(GetPhysicalScreenSize)
        if ok and Plain(hh, "number") and hh > 0 then ph = hh end
    end
    local s = overlay and overlay.GetEffectiveScale and overlay:GetEffectiveScale() or 1
    return s * ph / 768
end

---------------------------------------------------------------------------
-- Blizzard's exploration pin: the real map's explored parchment, drawn above our band at rest - at alpha 0 while the
-- imagery shows (its alpha only, after Blizzard's own RefreshAlpha / RefreshOverlays: a post-hook, as MinimapLayer.lua)
---------------------------------------------------------------------------
local function PinApply(self)
    if pinHidden and self.SetAlpha then self:SetAlpha(0) end
end
local function PinHook()
    if pinHooked or not (WorldMapFrame and type(WorldMapFrame.dataProviders) == "table") then return end
    for dp in pairs(WorldMapFrame.dataProviders) do
        local p = type(dp) == "table" and dp.pin
        if type(p) == "table" and p.overlayTexturePool and type(p.RefreshOverlays) == "function" and type(p.RefreshAlpha) == "function" then
            hooksecurefunc(p, "RefreshOverlays", PinApply)
            hooksecurefunc(p, "RefreshAlpha", PinApply)
            pin, pinHooked = p, true
            return
        end
    end
end
local function PinSync(hide)
    if hide == pinHidden then return end
    pinHidden = hide
    if not pin then return end
    if hide then
        pin:SetAlpha(0)
    elseif not pin.isWaitingForLoad then
        local a = 1
        if WorldMapFrame.GetGlobalAlpha then
            local ok, g = pcall(WorldMapFrame.GetGlobalAlpha, WorldMapFrame)
            if ok and Plain(g, "number") then a = g end
        end
        pin:SetAlpha(a)
    end
end
function I:PinHidden() return pinHidden, pin end

---------------------------------------------------------------------------
-- The layer button's picture (MapMenu.lua): a live preview of the OTHER look under the view's centre - the minimap tile
-- there (from its 64-px composite) while the drawn map shows, the drawn map's art there while the imagery shows. At rest.
---------------------------------------------------------------------------
local function HostAt(x, y)
    local best, bh
    for _, e in ipairs(ns.SpaceAll or {}) do
        local h = D.hosts[e.id] and e.visibleNow and e.x0 <= x and x <= e.x1 and e.y0 <= y and y <= e.y1 and Host(e)
        if h and #h.rows > 0 and (not best or e.depth > best.depth or (e.depth == best.depth and e.area < best.area)) then best, bh = e, h end
    end
    return bh
end

local function PreviewOf(x, y, imagery)
    if imagery then
        local e = ns.DeepestMapAt and ns.DeepestMapAt(x, y)
        local L = e and TL.Layout(e.id)
        if not L then return nil end
        local px, py = (x - e.x0) / (e.x1 - e.x0) * L.lw, (y - e.y0) / (e.y1 - e.y0) * L.lh
        local tc, tr = math.floor(px / L.tw), math.floor(py / L.th)
        local file = L.files[tr * L.cols + tc + 1]
        if not file or file == 0 then return nil end
        local uw, uh = math.min(L.tw, L.lw - tc * L.tw), math.min(L.th, L.lh - tr * L.th)
        local s = math.min(L.tw / 2, uw, uh)
        local l = math.max(0, math.min(px - tc * L.tw - s / 2, uw - s))
        local t = math.max(0, math.min(py - tr * L.th - s / 2, uh - s))
        return file, l / L.tw, (l + s) / L.tw, t / L.th, (t + s) / L.th
    end
    local h = HostAt(x, y)
    if not h then return nil end
    local e = h.e
    local u, v = (x - e.x0) / (e.x1 - e.x0), (y - e.y0) / (e.y1 - e.y0)
    for k = #h.rows, 1, -1 do
        local row = h.rows[k]
        if u >= row.u0 and u <= row.u1 and v >= row.v0 and v <= row.v1 then
            local c, r = math.floor((u - row.uc0) / row.ucs), math.floor((v - row.vr0) / row.vrs)
            if row.md.tiles[r * 1024 + c] then
                local p, q = math.floor(c / 4), math.floor(r / 4)
                local i, j = c - p * 4, r - q * 4
                return ("%s%d_64_%d_%d.blp"):format(row.md.path, row.m, p, q), i / 4, (i + 1) / 4, j / 4, (j + 1) / 4
            end
        end
    end
    return "sea", h.fillSea or h.d.sea
end

function I:RefreshPreview(force)
    local MM = ns.MapMenu
    if not (MM and MM.SetLayerPicture) then return end
    local x, y = 0.5, 0.5
    if lastCam then x, y = lastCam.x, lastCam.y end
    local file, l, r, t, b = PreviewOf(x, y, active)
    if not file and active then file, l, r, t, b = PreviewOf(x, y, false) end
    local key = ("%s:%s:%s:%s:%s"):format(tostring(file), tostring(l), tostring(r), tostring(t), tostring(b))
    if key == preview.key and not force then return end
    preview.key = key
    if file == "sea" or not file then
        MM:SetLayerPicture(nil, (file == "sea" and l) or (D.hosts[12] and D.hosts[12].sea) or { 0, 0.11, 0.16 })
    else
        MM:SetLayerPicture(file, nil, l, r, t, b)
    end
end
function I:PreviewKey() return preview.key end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------
-- Everything a host holds released (textures and masks keep no file).
local function ReleaseHost(h)
    for i = 1, 4 do ReleaseLevel(h, h.lev[i]) end
    h.target, h.fogWin, h.a, h.ra, h.ready = nil, nil, 0, 0, nil
    if h.holder then
        h.holder:SetAlpha(0)
        h.holder:Hide()
    end
end

function I:Release()
    for _, h in pairs(hosts) do
        ReleaseHost(h)
        Shelve(h)
    end
    wipe(shownH)
    for _, w in pairs(worlds) do w.sw, w.sa, w.ea = nil, 0, 0 end
    active = false
end

function I:Hide()
    for _, h in pairs(hosts) do
        if h.holder and h.holder:IsShown() then
            h.holder:Hide()
            h.hidAt = now
        end
    end
    wipe(shownH)
    PinSync(false)
end

-- (a world's switch: on at IMG_ON once its hosts' backdrops in view are there, off below IMG_OFF - going out once the
-- drawn world picture is there, or at once with the world off the view: nothing of it to see; (1.4.0-beta4's fixes) no
-- PARENT_WAIT - 1.4.0-beta3's 2 s bound let the imagery go over a drawn world not loaded)
-- (a world's globe: the zoom below which its circle no longer covers its picture - RetailRender.lua's circle, its
-- diameter c[3] -> c[4] widths over its zoom c[5] -> c[6]; past the picture's diagonal 1.202 its corners are in. The
-- holders are rectangles: zooming out fast, a switch going off by its time left Azeroth's sea and Northrend's in
-- rectangles round the closing globe - the imagery is gone by this zoom, whatever its time: WorldSwitch's ea)
local DIAGONAL = 1.202
local cutOf = {}
local function CutZoom(W)
    local z = cutOf[W]
    if z then return z end
    local c = W.node and W.node.c
    z = IMG_OFF - 0.08
    if c and c[4] > c[3] and c[6] > c[5] then
        if c[3] >= DIAGONAL then
            z = c[5]
        elseif c[4] <= DIAGONAL then
            z = c[6]
        else
            local want, lo, hi = (DIAGONAL - c[3]) / (c[4] - c[3]), 0, 1
            for _ = 1, 30 do
                local m = (lo + hi) / 2
                if Smooth(m) < want then lo = m else hi = m end
            end
            z = c[5] + (c[6] - c[5]) * (lo + hi) / 2
        end
    end
    z = math.min(z, IMG_ON - 0.02)
    cutOf[W] = z
    return z
end

-- ((1.4.0-beta4's fixes) does world W lie within half a view of the view - where RetailRender.lua loads its drawn picture
-- (NEAR): its imagery going out waits for that picture there, never off it)
local function WorldNear(W)
    local mx, my = (V.x1 - V.x0) * 0.5, (V.y1 - V.y0) * 0.5
    return W.x1 > V.x0 - mx and W.x0 < V.x1 + mx and W.y1 > V.y0 - my and W.y0 < V.y1 + my
end

-- ((1.4.0-beta4) by its own zoom alone - 1.4.0-beta3 switched it only for the world under the view's centre: the look
-- depended on where the view lay, and the Vaults of Atal'Utek, past Azeroth's picture, never showed theirs; its circle
-- open past its corners at IMG_ON, a world's imagery at the view's corner lies in its world's soft rect as its drawn
-- picture does. The view's position decides only what loads: I:Frame's near)
local function WorldSwitch(W, zc, ready)
    local s = worlds[W]
    if not s then
        s = { sa = 0, ea = 0 }
        worlds[W] = s
    end
    local was = s.sw
    if zc >= IMG_ON then s.sw = true elseif zc < IMG_OFF then s.sw = false end
    if s.sw == false and was ~= false then s.offAt = now end
    -- (a second draw in the same frame - a wheel notch draws at once - has dt 0: no step, never a whole one)
    local step = TEST.nofade and 1 or math.min(1, dt / SWITCH_FADE)
    if s.sw then
        if ready then s.sa = math.min(1, s.sa + step) end
    elseif s.sa > 0 then
        local back = (R.PictureLoaded and R:PictureLoaded(W)) or not WorldNear(W)
        if back then s.sa = math.max(0, s.sa - step) end
    end
    -- (ea: the switch as drawn - by its time, and by the zoom below IMG_ON down to the globe's cut, CutZoom)
    local cut = CutZoom(W)
    s.ea = math.min(s.sa, Smooth((zc - cut) / (IMG_ON - cut)))
    return s
end

-- The hosts near the view this frame, bottom to top (the larger below; a copy over its continent).
local function ByDraw(a, b)
    if a.e.depth ~= b.e.depth then return a.e.depth < b.e.depth end
    if a.e.area ~= b.e.area then return a.e.area > b.e.area end
    return a.e.id < b.e.id
end

local function Near(e, m)
    local mx, my = (V.x1 - V.x0) * m, (V.y1 - V.y0) * m
    return e.x1 > V.x0 - mx and e.x0 < V.x1 + mx and e.y1 > V.y0 - my and e.y0 < V.y1 + my
end

-- (an inset's drawn picture: RetailRender.lua's switch and opening - its imagery comes and goes with it)
local function InsetState(e)
    if R.StageSwitch then return R:StageSwitch(e) end
    return 0, 1
end
-- ((1.4.0-beta6, the player on 1.4.0-beta5: "the terrain map offers no guidance to where it might be while everything else
-- is perfectly visible at every level") an inset on a portal - the Maelstrom's places, a portal drawing no picture of its
-- own: its imagery comes with its world's, as a continent's does, not with its drawn picture's switch - under the world's
-- imagery Azeroth's drawn Maelstrom went out, and the Lost Isles, Kezan, Deepholm and the Maelstrom's own swirl came only
-- from their own fits, the middle of Azeroth an empty sea till then (the player's 91.png, 92.webp)
local function OnPortal(e) return e.kind == "inset" and e.pe ~= nil and e.pe.kind == "portal" end

-- ((1.4.0-beta3, the renders of the reviews' fixes) Host h's levels' soft edges (h.smask) laid in holder f: soft.tga
-- over its soft rect shrunk by EDGE_IN - an inset's opening box (h.hmask's), a continent's world's picture grown by its
-- drawn picture's switch k by up to that picture's size (at the world's fit its pages end in the world's soft edge;
-- its parts past it come in with the drawn continent - a soft edge sweeping out, never a page's edge), else its picture
local function LayEdges(h, f)
    local e = h.e
    local x0, y0, x1, y1 = 0, 0, h.HW, h.HH
    if h.kind == "cont" then
        local W = h.w
        local w, hh = e.x1 - e.x0, e.y1 - e.y0
        x0, y0 = (W.x0 - e.x0) / w * h.HW, (W.y0 - e.y0) / hh * h.HH
        x1, y1 = (W.x1 - e.x0) / w * h.HW, (W.y1 - e.y0) / hh * h.HH
        local g = (R.StageSwitch and R:StageSwitch(e) or 1) * math.max(x1 - x0, y1 - y0)
        x0, y0, x1, y1 = x0 - g, y0 - g, x1 + g, y1 + g
    elseif h.hmx and e.kind == "inset" then
        x0, y0, x1, y1 = h.hmx, h.hmy, h.hmx + h.hmw, h.hmy + h.hmh
    end
    for j = 1, 2 do
        local m = h.smask[j]
        local dx, dy = (x1 - x0) * EDGE_IN[j] / 1002, (y1 - y0) * EDGE_IN[j] / 668
        local a, b, c, d = x0 + dx, y0 + dy, math.max(x1 - dx, x0 + dx + 1e-3), math.max(y1 - dy, y0 + dy + 1e-3)
        if m.lx ~= a or m.ly ~= b or m.lw ~= c - a or m.lh ~= d - b then
            m:ClearAllPoints()
            m:SetPoint("TOPLEFT", f, "TOPLEFT", a, -b)
            m:SetSize(c - a, d - b)
            m.lx, m.ly, m.lw, m.lh = a, b, c - a, d - b
        end
    end
end

-- One host this frame: placed, its level, windows, copies and alphas. Returns busy.
local function DrawHost(h, wa)
    local e = h.e
    local f = Holder(h)
    if not f then return true end -- (the frame's budget spent: next frame)
    local HW, HH = h.HW, h.HH
    -- (placed as RetailRender.lua places a stage's part: scale = screen px per host px)
    local scale = (e.x1 - e.x0) * V.ppx / HW
    local sx0, sy0 = V.W / 2 + (e.x0 - V.cx) * V.ppx, V.H / 2 + (e.y0 - V.cy) * V.ppy
    if not (scale > 0 and scale < 1e6) then return false end
    if h.scale ~= scale or h.sx0 ~= sx0 or h.sy0 ~= sy0 then
        f:SetScale(scale)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", overlay, "TOPLEFT", sx0 / scale, -sy0 / scale)
        h.scale, h.sx0, h.sy0 = scale, sx0, sy0
    end
    if not f:IsShown() then
        -- ((1.4.0-beta3, the reviews of 1.4.0-beta3) a holder shown again shows its textures at once: they count
        -- against the frame's room for newly shown textures (RetailTiles.lua SHOW_PER_FRAME) - the map opened again
        -- showed 195 of the imagery's in a frame, counted 0; one off the screen, preloaded near it, waits for a frame
        -- with room, as RetailRender.lua's parts do; one on the screen shows now - the drawn pictures over it are
        -- planned at alpha 0, never a frame without it)
        local n = h.nt or 0
        if not Near(e, 0) and TL.newShown > 0 and TL.newShown + n > TL.SHOW_PER_FRAME then
            h.deferred = V.tick
            return true
        end
        f:Show()
        TL.newShown = TL.newShown + n
        -- ((1.4.0-beta4, G7) A picture the client let go while the holder was hidden - it reports itself not loaded now -
        -- loads again at alpha 0, the holder coming in again once its backdrop is whole; one it kept shows on. 1.4.0-beta3
        -- decided by a timer - hidden HIDE_GRACE or longer, every picture loaded again)
        local back, lost = h.hidAt ~= nil, false
        for i = 1, 4 do
            local lev = h.lev[i]
            for _, t in pairs(lev.tex) do
                if back and t.at and t.IsObjectLoaded and not t:IsObjectLoaded() then
                    t.at = nil
                    if i == 1 then lost = true end
                end
                if not t.at then
                    t.t0, t.f0 = now, TL.tick
                    pending[t], fading[t] = true, nil
                    SetA(t, 0)
                end
            end
            for _, c in pairs(lev.copies) do
                if back and c.at and c.IsObjectLoaded and not c:IsObjectLoaded() then c.at = nil end
                if not c.at then
                    c.t0, c.f0 = now, TL.tick
                    pending[c], fading[c] = true, nil
                    SetA(c, 0)
                end
            end
        end
        for _, m in pairs(h.masks) do m.t0 = now end
        if h.hmask then h.hmask.t0 = now end
        for _, x in ipairs(h.smask or {}) do x.t0 = now end
        if lost then h.ra = 0 end
        h.hidAt = nil
    end
    h.deferred = nil
    -- (the view in host fractions)
    local w = e.x1 - e.x0
    local hh = e.y1 - e.y0
    h.view = h.view or {}
    local vw = h.view
    vw[1], vw[2], vw[3], vw[4] = (V.x0 - e.x0) / w, (V.y0 - e.y0) / hh, (V.x1 - e.x0) / w, (V.y1 - e.y0) / hh
    -- (an inset's soft edge over its opening box: its printed place, opening to its whole picture with the focus)
    local ia, open = 1, 1
    if e.kind == "inset" and not OnPortal(e) then ia, open = InsetState(e) end
    if h.hmask and e.hit and e.kind == "inset" and not h.landMask then
        local x0, x1 = e.hit.x0 + (e.x0 - e.hit.x0) * open, e.hit.x1 + (e.x1 - e.hit.x1) * open
        local y0, y1 = e.hit.y0 + (e.y0 - e.hit.y0) * open, e.hit.y1 + (e.y1 - e.hit.y1) * open
        local mx, my, mw, mh = (x0 - e.x0) / w * HW, (y0 - e.y0) / hh * HH, (x1 - x0) / w * HW, (y1 - y0) / hh * HH
        if h.hmx ~= mx or h.hmy ~= my or h.hmw ~= mw or h.hmh ~= mh then
            h.hmask:ClearAllPoints()
            h.hmask:SetPoint("TOPLEFT", f, "TOPLEFT", mx, -my)
            h.hmask:SetSize(math.max(mw, 1e-3), math.max(mh, 1e-3))
            h.hmx, h.hmy, h.hmw, h.hmh = mx, my, mw, mh
        end
    end
    if h.smask then LayEdges(h, f) end
    local busy = false
    if #h.rows > 0 then
        -- (the level: by physical px a tile; a zoom heading in loads its level ahead)
        local adt = (h.ucs or 1) * (e.x1 - e.x0) * V.ppx * V.phys
        h.target = Pick(h, adt, h.target, vw[1], vw[2], vw[3], vw[4])
        h.dest = nil
        local pf = V.pf
        if pf and pf.vw < V.vw then
            local k = V.vw / pf.vw
            local d = Pick(h, adt * k, h.target, (pf.x0 - e.x0) / w, (pf.y0 - e.y0) / hh, (pf.x1 - e.x0) / w, (pf.y1 - e.y0) / hh)
            if d ~= h.target then h.dest = d end
        end
        -- (the fog: by the host's own zoom - or, a copy, its continent's)
        local fz = e
        if h.kind == "copy" then
            local p = e.pe
            while p and not (D.hosts[p.id] and D.hosts[p.id].kind ~= "copy") and p.pe do p = p.pe end
            fz = p or e
        end
        local zc = ns.ZoomOf(V.v, fz, V.vw)
        local fl = Smooth((zc - FOG_C0) / (FOG_C1 - FOG_C0))
        local pre = zc >= FOG_PRE
        if V.flying and fl <= 0 then pre = false end
        h.fog = (wa > 0) and fl or 0
        local A, B, C, Dd = Grow(vw[1], vw[2], vw[3], vw[4], FOG_MARGIN)
        if pre and not Fits(h.fogWin, vw[1] - (vw[3] - vw[1]) * FOG_KEEP, vw[2] - (vw[4] - vw[2]) * FOG_KEEP,
            vw[3] + (vw[3] - vw[1]) * FOG_KEEP, vw[4] + (vw[4] - vw[2]) * FOG_KEEP, A, B, C, Dd) then
            h.fogWin = { A, B, C, Dd }
            h.fogWinGen = (h.fogWinGen or 0) + 1
        end
        if h.fogPre ~= pre then
            h.fogPre = pre
            h.fogWinGen = (h.fogWinGen or 0) + 1
        end
        local lev = h.lev
        EnsureWindow(h, lev[1], vw[1], vw[2], vw[3], vw[4])
        EnsureWindow(h, lev[h.target], vw[1], vw[2], vw[3], vw[4])
        if h.dest then
            EnsureWindow(h, lev[h.dest], (pf.x0 - e.x0) / w, (pf.y0 - e.y0) / hh, (pf.x1 - e.x0) / w, (pf.y1 - e.y0) / hh)
        end
        if h.target > 1 then BuildCopies(h, lev[h.target]) end
        for i = 1, 4 do
            if lev[i].live and i ~= h.target and (i == h.dest or lev[i].a > 0 or i == 1) then BuildCopies(h, lev[i]) end
        end
        local tl = lev[h.target]
        lev[1].a = 1
        tl.a = math.min(1, tl.a + ((h.ra > 0 and not TEST.nofade) and dt / LEVEL_FADE or 1))
        local covered, backdrop, whole = Alphas(h)
        if h.loading or tl.a < 1 or lev[1].short == true or tl.short == true or h.copiesShort then busy = true end
        for i = 2, 4 do
            local l = lev[i]
            if l.live and i ~= h.target and i ~= h.dest then
                if i > h.target and covered then
                    l.a = math.max(0, l.a - dt / LEVEL_FADE)
                    if l.a <= 0 then ReleaseLevel(h, l) end
                    busy = true
                elseif i < h.target and covered then
                    ReleaseLevel(h, l)
                    busy = true
                else
                    busy = true
                end
            end
        end
        h.backdrop, h.whole = backdrop, whole
    else
        local _, backdrop, whole = Alphas(h)
        h.backdrop, h.whole = backdrop, whole
    end
    -- (the holder at alpha 0 until its backdrop has faded in whole; then by the world's switch and an inset's own -
    -- (1.4.0-beta3) never on a timeout)
    if h.whole then
        h.ra = math.min(1, h.ra + (TEST.nofade and 1 or dt / HOST_FADE))
    else
        busy = true
    end
    -- ((under our pictures, which fade out over it: whole from half its world's switch - partly faded, a holder's pages
    -- over its sea showed as darker squares, every texture taking the holder's alpha on its own; the drawn pictures over
    -- it fade out only in the switch's second half, over the holder whole - I:Fade)
    h.a = math.min(1, 2 * wa) * ia * (e.visibleNow and 1 or 0) * h.ra
    local ha = math.floor(Clamp01(h.a) * 255 + 0.5) / 255
    if f:GetAlpha() ~= ha then f:SetAlpha(ha) end
    if h.ra < 1 then busy = true end
    return busy
end

-- (RetailRender.lua Render:Draw, before it plans) This frame's imagery: the worlds' switches, the hosts near the view
-- drawn. Returns busy.
function I:Frame(cam, v, pf, ov)
    now = GetTime()
    dt = lastT and math.min(now - lastT, 0.05) or 0
    lastT = now
    lastCam = cam
    overlay = overlay or ov
    wipe(shownH)
    if not (I:On() and overlay and v and v.W and v.W > 0 and ns.SpaceAll) then
        if active or next(worlds) ~= nil then I:Release() end
        I:Hide()
        active = false
        wipe(worlds)
        if ns.Core and ns.Core.State and ns.Core.State() == "rest" then I:RefreshPreview() end
        return false
    end
    if not pinHooked then PinHook() end
    V.v, V.W, V.H, V.cx, V.cy, V.vw = v, v.W, v.H, cam.x, cam.y, cam.vw
    V.ppx, V.ppy = ns.PixelsPerUnit(v, cam.vw)
    V.x0, V.x1 = cam.x - v.W / 2 / V.ppx, cam.x + v.W / 2 / V.ppx
    V.y0, V.y1 = cam.y - v.H / 2 / V.ppy, cam.y + v.H / 2 / V.ppy
    V.phys = PhysPerUnit()
    V.flying = ns.Core and ns.Core.State and ns.Core.State() == "fly"
    V.pf = nil
    if pf and pf.vw and pf.vw > 0 then
        local px, py = ns.PixelsPerUnit(v, pf.vw)
        V.pf = V.pfBuf or {}
        V.pfBuf = V.pf
        V.pf.vw = pf.vw
        V.pf.x0, V.pf.x1 = pf.x - v.W / 2 / px, pf.x + v.W / 2 / px
        V.pf.y0, V.pf.y1 = pf.y - v.H / 2 / py, pf.y + v.H / 2 / py
    end
    copyBudget, copiesShort = COPY_BUDGET, false
    local busy = false
    -- the worlds: their switches (by last frame's backdrops)
    local root = ns.maps[ns.ROOT_MAP_ID]
    local any = false
    for _, W in ipairs(ns.SpaceKids(root) or {}) do
        local zc = ns.ZoomOf(v, W, cam.vw)
        local hx, hy = (V.x1 - V.x0) / 2, (V.y1 - V.y0) / 2
        local near = W.x0 - hx <= cam.x and cam.x <= W.x1 + hx and W.y0 - hy <= cam.y and cam.y <= W.y1 + hy
        local s = WorldSwitch(W, zc, worlds[W] and worlds[W].ready)
        s.load = (zc >= IMG_LOAD and near) or s.sa > 0
        s.ready = true
        if (s.sw and s.sa < 1) or (not s.sw and s.sa > 0) then busy = true end
        if s.ea > 0.5 and Near(W, 0) then any = true end
    end
    -- the hosts near the view whose world loads
    for _, e in ipairs(ns.SpaceAll) do
        local W = WorldOf(e) or (e.pe == root and e) or nil
        local s = W and worlds[W]
        if s and s.load and e.visibleNow and (D.hosts[e.id] or e.id == ns.WORLD_MAP_ID) and Near(e, 0.1) then
            local go = true
            if e.kind == "inset" and not OnPortal(e) then
                local ia = InsetState(e)
                go = ia > 0 or ns.ZoomOf(v, e, cam.vw) >= 0.45
            end
            local h = go and Host(e)
            if h then shownH[#shownH + 1] = h end
        end
    end
    table.sort(shownH, ByDraw)
    V.tick = (V.tick or 0) + 1
    local deferred = false
    for _, h in ipairs(shownH) do
        h.since = h.since or now
        h.tick = V.tick
        local s = worlds[h.w or h.e]
        if DrawHost(h, s and s.ea or 0) then busy = true end
        if h.deferred == V.tick then
            h.tick, deferred = nil, true -- (shown in a frame with room: its drawn pictures stay meanwhile - I:Fade)
        end
        -- (a world's switch comes once every host of it in the view has its backdrop, faded in whole at alpha 0 - h.ra:
        -- the holder whole by half the switch; one still fading in with the switch under way showed its pages as
        -- darker squares over its sea, Outland's black void through the drawn map fading out)
        if s and (not h.backdrop or h.ra < 1) and Near(h.e, 0) and (h.kind ~= "inset" or h.a > 0) then s.ready = false end
    end
    if deferred then
        local k = 0
        for i = 1, #shownH do
            local h = shownH[i]
            if h.deferred ~= V.tick then
                k = k + 1
                shownH[k] = h
            end
        end
        for i = #shownH, k + 1, -1 do shownH[i] = nil end
    end
    for _, h in pairs(hosts) do
        if h.tick ~= V.tick and h.deferred ~= V.tick then
            if h.holder and h.holder:IsShown() then
                h.holder:Hide()
                h.hidAt = now
            end
            h.since, h.ra = nil, 0
            -- (a host left behind keeps its backdrop a while - a drag back finds it; its finer levels go)
            for i = 2, 4 do if h.lev[i].live then ReleaseLevel(h, h.lev[i]) end end
            h.target = nil
            h.offT = h.offT or now
            if now - h.offT > 30 and h.holder then
                ReleaseHost(h)
                Shelve(h) -- ((1.4.0-beta3) its holder and pools to the next host made)
            end
        elseif h.tick == V.tick then
            h.offT = nil
        end
    end
    if copiesShort then busy = true end
    active = any
    PinSync(active)
    if ns.Core and ns.Core.State and ns.Core.State() == "rest" then I:RefreshPreview() end
    if active and ns.Labels and ns.Labels.AddSubzones then ns.Labels:AddSubzones() end
    return busy
end

-- (RetailRender.lua PlanNode) The factor of entry e's drawn picture's alpha this frame: its world's imagery lies under our
-- pictures (RetailRender.lua places the holders right over the Cosmic map), so a drawn picture fades out over it in the
-- second half of the world's switch; 0 where the imagery stands for it whole (the switch at 1 and every host in the
-- view loaded: it is planned at alpha 0). The Cosmic map, the capitals underground, the floors (their patches and whole
-- pictures) keep 1: their drawn maps over the imagery.
-- (the host whose holder entry e's drawn picture lies over: e itself, its continent, its world - the nearest with a host;
-- ((1.4.0-beta4's fixes) never past a link - an inset or a portal is another place: its own host or none. Argus and the
-- Maelstrom's portal have no imagery, and their drawn pictures went out over the Broken Isles' and Azeroth's - empty dark
-- sea at their own fits: the imagery stands for a drawn picture only where it has that place's tiles)
local coverOf = {}
local function CoverHost(e)
    local c = coverOf[e]
    if c == nil then
        -- ((1.4.0-beta4) a cell by the map its band is (a stand-in's: the map it stands in on - its own map is hidden,
        -- its holder never drawn - RetailCells.lua; a home's cover: its home), else by its zone)
        local p, guard = (e.kind == "cell" and (e.bandOf or e.cellOf)) or e, 0
        c = false
        while p and guard < 16 do
            if D.hosts[p.id] or p.id == ns.WORLD_MAP_ID then
                c = p
                break
            end
            if p.kind == "inset" or p.kind == "portal" then break end
            p, guard = p.pe, guard + 1
        end
        coverOf[e] = c
    end
    return c and hosts[c] or nil
end
local function Keep(z)
    return z ~= nil and (I.KEEP_CITY[z.id] == true or (z.node and z.node.g ~= nil and z.node.fl ~= nil))
end
local function Kept(e)
    if e.kind == "cell" then return e.cell ~= nil and e.cell.pt ~= nil and Keep(e.cellOf) end
    return e.kind == "zone" and Keep(e)
end
function I:Fade(e)
    if e.kind == "root" then return 1 end
    local s = worlds[WorldOf(e) or e]
    if not s or s.ea <= 0 or Kept(e) then return 1 end
    if s.ea >= 1 then
        if not s.sw then return 1 end -- (going out: the drawn world loads again at 1 - WorldSwitch waits for it)
        -- (the switch whole: each drawn picture by the holder it lies over - one come into the view since, still fading in
        -- with its own HOST_FADE, keeps the drawn picture over it as much; not the whole world's pictures back at once, as
        -- the first build did when any host of the view was not ready)
        local h = CoverHost(e)
        if not h then return coverOf[e] == false and 1 or 0 end
        if h.tick ~= V.tick then return 1 end
        return 1 - ((h.backdrop and h.ra) or 0)
    end
    -- (the switch's first half brings the holders in whole under the drawn pictures - DrawHost: 2 x its alpha -, its
    -- second half fades the drawn pictures out over them; going out the other way round)
    return 1 - math.max(0, 2 * s.ea - 1)
end
function I:Hides(e) return I:Fade(e) <= 0 end

-- ((1.4.0-beta4's fixes) RetailRender.lua's space fill round world W: the imagery's sea colour there (its world's host's, or
-- Azeroth's - its continents' sea, Kalimdor's) and its world's switch as drawn - the fill takes that colour in step)
function I:SpaceSea(W)
    local s = worlds[W]
    if not (s and s.ea > 0) then return nil, 0 end
    local d = D.hosts[W.id] or (W.id == ns.WORLD_MAP_ID and D.hosts[12]) or nil
    return d and d.sea or nil, s.ea
end

-- (RetailRender.lua) The imagery covers the view: the world under the view's centre whole, its hosts loaded - the frame is
-- ready (Core hides Blizzard's canvas while detached).
function I:CoversView()
    if not active then return false end
    local W
    for w, s in pairs(worlds) do
        if s.ea >= 1 and V.cx and w.x0 <= V.cx and V.cx <= w.x1 and w.y0 <= V.cy and V.cy <= w.y1 then W = w end
    end
    if not W then return false end
    for _, h in ipairs(shownH) do
        -- ((1.4.0-beta3) and its holder whole - shown again, it fades in over the drawn map first)
        if (h.w or h.e) == W and Near(h.e, 0) and h.kind ~= "inset" and not (h.backdrop and h.ra >= 1) then return false end
    end
    return true
end

-- (RetailRender.lua PlaceParts) The holders at the levels from L up, bottom to top; returns the next level free.
function I:Place(L)
    for _, h in ipairs(shownH) do
        local f = h.holder
        if f then
            if f.level ~= L then
                ns.SetLevelFixed(f, L)
                f.level = L
            end
            L = L + 1
        end
    end
    return L
end
function I:Shown() return #shownH > 0 end

---------------------------------------------------------------------------
-- Following Render
---------------------------------------------------------------------------
hooksecurefunc(R, "MarkArtDirty", function()
    fogGen = fogGen + 1
    wipe(tilesOf)
    wipe(setOf)
end)
hooksecurefunc(R, "HideAll", function() I:Hide() end)
hooksecurefunc(R, "ReleaseAll", function()
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then I:Release() end
end)

-- (/emap zoom) the readout's line
function I:ZoomLines(out)
    if not I:On() then return end
    local best
    for _, h in ipairs(shownH) do
        if h.target and h.a > 0 and (not best or h.e.depth > best.e.depth) then best = h end
    end
    if not best then
        out[#out + 1] = "Minimap imagery: on (it shows from a world's own zoom 0.97 - the drawn map out in space)"
        return
    end
    local lev = best.lev[best.target]
    local adt = (best.ucs or 1) * (best.e.x1 - best.e.x0) * V.ppx * V.phys
    local what = (lev.i == 4) and "the game's own minimap tiles" or ("composite %d px per tile"):format(lev.px)
    out[#out + 1] = ("Minimap imagery (%s): %s, %.2f texels per screen pixel; fog %.2f (%s)"):format(best.e.name or "?", what,
        ((lev.i == 4) and (best.rows[1] and best.rows[1].md.px or 512) or lev.px) / math.max(adt, 1e-6), best.fog or 0,
        I:TilesOn() and ("client tiles from %.1f"):format(CLIENT_IN) or ("client tiles off: %s imagerytiles"):format(ns.COMMAND))
end

-- (tests, /emap debug) counts
function I:Stats()
    -- ((1.4.0-beta3) held / maskHeld: every texture and mask holding a file or a colour, shown or not - the cap's count)
    local s = { made = nTex, masks = nMask, skipped = nSkipped, active = active, hosts = #shownH, live = 0, copies = 0, worlds = {},
        held = nLive, maskHeld = nMaskLive, shells = #shells }
    for _, h in ipairs(shownH) do
        for i = 1, 4 do
            for _ in pairs(h.lev[i].tex) do s.live = s.live + 1 end
            for _ in pairs(h.lev[i].copies) do s.copies = s.copies + 1 end
        end
    end
    for w, x in pairs(worlds) do s.worlds[w.id] = x.sa end
    return s
end
I.T = { hosts = hosts, shown = shownH, worlds = worlds, cap = cap, V = V, shells = shells } -- (tests: read only, but the caps)
function I:HostOf(id)
    for e, h in pairs(hosts) do if e.id == id then return h end end
end
