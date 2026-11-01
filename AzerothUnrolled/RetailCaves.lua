--[[
Endless Map - RetailCaves.lua (1.4.0-beta3; retail only: AzerothUnrolled_Standard.toc, after RetailImagery.lua)

The caves and interiors on retail - WoW Forever's caves (Caves.lua, 1.2.0: the tunnels drawn into the world map from the
cave zoom, Blackrock Mountain's levels and the caves round the instance portals with the city maps; the caves button,
/emap cavezoom) on the retail engine (docs/retail-engine.md 14.5; the data: RetailCaveData.lua, docs/retail-places.md 4).

  * Blizzard's MICRO MAPS (RETAIL_CAVES.map: 179 caves and interiors, 217 levels) - each level its art
    (C_Map.GetMapArtLayerTextures: the client's own, drawn only while its first tile is the data's f1 - another phase's art
    keeps out) at its rect on the zone or inset it lies in, through its footprint (Masks\Retail\Caves\<uiMap>.tga: the
    cave's shape in the client's own indoor minimap, its title banner and corner ornaments left out). (1.4.0-beta13) Every
    level at once, the lower under the upper, by the zoom alone - WoW Forever's Blackrock Mountain, its spire with the depths
    `under` (DetailMaps.lua); 1.4.0-beta3 - 1.4.0-beta12 drew one, the one the player stood on, else the top one: the player
    on 1.4.0-beta12, "show all of BRM". Only a level off its home's land (ol) still needs the player in it.
  * (1.4.0-beta13) A name its home prints under the levels, painted over while they show - WoW Forever's cover: COVERS.
  * The old world's MINIMAP CAVES (RETAIL_CAVES.mm: 226) as WoW Forever's MM draws them: the rock colour (rim) through the
    cave's mask, the client's indoor minimap blocks over it as quads turned by SetRotation, desaturated in the tint.
  * The switch (WoW Forever's): a cave shows from a view yardsFor wide - the caves' (sw "cave": /emap cavezoom's world
    zoom as yards, 30x = RETAIL_PLACES.yd.cave 1,490 yd; off: none) or the city maps' ("city": 3,181 yd - Blackrock
    Mountain, New Tinkertown, Maraudon, the Scarlet Monastery's entrance, the Timbermaw tunnels) -, or from the deepest
    view the wheel reaches over it where that is wider (Core's depth limit: maxZoom past the deepest map there); off 5%
    wider; a 0.3 s crossfade. Within NEAR views of the screen a cave about to show is loaded at alpha 0 (the client loads
    only what is visible), so a drag brings it in loaded; it fades in once its art and mask are loaded, however long that
    takes ((1.4.0-beta4's fixes) no LOAD_GIVEUP, as no MASK_GIVEUP since 1.4.0-beta4; shown again, it asks the client
    again - a level it let go loads and fades in again; every load measured - RetailTiles.lua TL.Watch).
  * Each cave is a HOLDER of Core's city layer (never another's: no nested clipping host; textures never move between
    frames), placed and scaled as RetailRender.lua places a stage's part, at the levels RetailRender.lua's PlaceParts gives
    it - over the zone pictures, the city maps and the minimap imagery (WoW Forever: the caves over the imagery). Its name
    (Labels.lua's "cave" style; the level's map name, else the data's) shows with its picture (Render:DetailAlpha).
  * Budget: at most the frame's NEW_PER_FRAME new SetTexture (shared, RetailTiles.lua); a cave out of the near window for
    RELEASE_AFTER gives its textures back; all of them 10 s after the map closes (Render:ReleaseAll).
]]
local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)
if ns.FLAVOR ~= "retail" then return end

local CD = ns.RETAIL_CAVES
local R, TL = ns.Render, ns.RetailTiles
if type(CD) ~= "table" or not (R and TL) then return end

local CV = {}
ns.RetailCaves = CV

local TEST = ns.retailTest or {}
local P = ns.RETAIL_PLACES
local CITY_YARDS = (P and P.yd and P.yd.city) or 3181
local OPEN_YARDS_AT_14 = 3193     -- (RetailSpace.lua: WoW Forever's view at world zoom 14 is 3,193 yd wide)
local HIDE_K = 1.05               -- off this much wider than on
local PRE_K = 1.4                 -- loaded from this much wider than on
local NEAR = 1                    -- ... within this many views of the screen
local SWITCH_FADE, LOAD_FADE = 0.3, 0.2
local RELEASE_AFTER = 10
local CLAMP, FILTER = "CLAMP", "TRILINEAR"
local TINT, RIM = CD.tint or { 0.98, 0.86, 0.62 }, CD.rim or { 0.30, 0.21, 0.12 }
local SOFT = "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\soft.tga"
-- ((1.4.0-beta13) A name the home prints under a cave, its levels hiding only a part of it - the BLAC of Burning Steppes'
-- BLACKROCK MOUNTAIN beside the ring (the player's Blackrock Mountain on 1.4.0-beta12, tools/retail/ measured on the art):
-- WoW Forever's cover (DetailMaps.lua, Render.lua EmitCover). Under the levels, with their switch and fade, while the
-- explored piece that prints it shows (piece: its offset on the home's picture): rect d of the home's layer px (lw x lh)
-- shows the home's explored art from s (d's top left there), through the soft mask.
local COVERS = {
    [33] = { lw = 1002, lh = 668, piece = { 79, 0 }, d = { 124, 170, 284, 202 }, s = { 188, 92 } },
}

local caves                       -- every cave: built once the registry is
local shownC = {}                 -- the caves placed this frame
local alphaOf = {}                -- [key] = the cave's alpha this frame (its name's: Render:DetailAlpha)
local V = {}
local now, dt, lastT = 0, 0, nil
local overlay

local function Clamp01(x) if x < 0 then return 0 elseif x > 1 then return 1 end return x end
local function Smooth(x) x = Clamp01(x) return x * x * (3 - 2 * x) end
local function Plain(v, kind) return type(v) == kind and not (issecretvalue and issecretvalue(v)) end

---------------------------------------------------------------------------
-- The caves (built once: the data's rects on the tree's entries)
---------------------------------------------------------------------------
local function Rect(h, r)
    local w, hh = h.x1 - h.x0, h.y1 - h.y0
    return h.x0 + r[1] * w, h.y0 + r[2] * hh, h.x0 + r[3] * w, h.y0 + r[4] * hh
end

local function MapName(id, fallback)
    if C_Map and C_Map.GetMapInfo and Plain(id, "number") then
        local ok, info = pcall(C_Map.GetMapInfo, id)
        if ok and type(info) == "table" and Plain(info.name, "string") and info.name ~= "" then return info.name end
    end
    return fallback
end

local function Build()
    if caves then return caves end
    if not (ns.maps and ns.maps[ns.ROOT_MAP_ID]) then return nil end
    caves = {}
    local keys = {}
    for k in pairs(CD.map or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local c = CD.map[k]
        local h = ns.maps[c.h]
        if h and c.lv and #c.lv > 0 then
            local cave = { key = "m" .. k, id = k, kind = "map", sw = c.sw, h = h, lab = c.lab, levels = {} }
            for i, lv in ipairs(c.lv) do
                local x0, y0, x1, y1 = Rect(h, lv.r)
                cave.levels[i] = { id = lv[1], x0 = x0, y0 = y0, x1 = x1, y1 = y1, yw = lv.yw, lw = lv.a[1], lh = lv.a[2], f1 = lv.f1, m = lv.m,
                    tex = {}, pool = {}, a = 0, ol = lv.ol == 1 or nil }
            end
            local t = cave.levels[1]
            cave.x0, cave.y0, cave.x1, cave.y1 = t.x0, t.y0, t.x1, t.y1
            -- ((1.4.0-beta13) what it draws: every level - near the view by these)
            cave.bx0, cave.by0, cave.bx1, cave.by1 = t.x0, t.y0, t.x1, t.y1
            for _, l in ipairs(cave.levels) do
                cave.bx0, cave.by0 = math.min(cave.bx0, l.x0), math.min(cave.by0, l.y0)
                cave.bx1, cave.by1 = math.max(cave.bx1, l.x1), math.max(cave.by1, l.y1)
            end
            -- ((1.4.0-beta13) what is drawn: its levels, then its cover - RetailDoors.lua and the switch read the levels alone)
            cave.all = cave.levels
            local cv = COVERS[k]
            if cv then
                cave.all = {}
                for i, l in ipairs(cave.levels) do cave.all[i] = l end
                cave.all[#cave.all + 1] = { id = c.h, cover = cv, x0 = h.x0, y0 = h.y0, x1 = h.x1, y1 = h.y1, lw = cv.lw, lh = cv.lh, m = SOFT,
                    tex = {}, pool = {}, a = 0 }
            end
            cave.name = MapName(k, nil)
            caves[#caves + 1] = cave
        end
    end
    for _, c in ipairs(CD.mm or {}) do
        local h = ns.maps[c.h]
        if h then
            local x0, y0, x1, y1 = Rect(h, c.r)
            local lv = { id = c.uid, x0 = x0, y0 = y0, x1 = x1, y1 = y1, lw = c.lw, lh = c.lh, m = c.m, q = c.q, tex = {}, pool = {}, a = 0 }
            -- (its yards: 2 px a yard - docs/retail-places.md 4)
            lv.yw = c.lw / 2
            caves[#caves + 1] = { key = "mm" .. c.uid, id = c.uid, kind = "mm", sw = c.sw, h = h, lab = c.lab, name = c.n, levels = { lv },
                x0 = x0, y0 = y0, x1 = x1, y1 = y1, bx0 = x0, by0 = y0, bx1 = x1, by1 = y1 }
            caves[#caves].all = caves[#caves].levels
        end
    end
    return caves
end

-- (Labels.lua) The caves' names: with their pictures (it.detail - Render:DetailAlpha), Labels' "cave" style.
local labelled = false
function CV:AddLabels()
    if labelled or not (ns.Labels and ns.Labels.Add) or not Build() or #ns.Labels:Items() == 0 then return end
    labelled = true
    for _, c in ipairs(caves) do
        if c.lab and c.name then
            local h = c.h
            local it = ns.Labels:Add(h.x0 + c.lab[1] * (h.x1 - h.x0), h.y0 + c.lab[2] * (h.y1 - h.y0), c.name, "cave", h)
            if it then it.detail = c.key end
        end
    end
end

---------------------------------------------------------------------------
-- The switch in yards (WoW Forever's cave zoom, as a view's width)
---------------------------------------------------------------------------
-- The caves' switch: the view this many yards wide (nil: off) - /emap cavezoom's world zoom z: WoW Forever's view at
-- world zoom z is OPEN_YARDS_AT_14 x 14 / z yards wide
function CV:CaveYards()
    local db = ns.db
    local z = db and db.caveZoom
    if z == false then return nil end
    if not Plain(z, "number") or z <= 0 then z = R.CAVE_G or 30 end
    return OPEN_YARDS_AT_14 * 14 / z
end

-- Cave c's switch now: the yards across the view it shows from (nil: never) - the deepest view over it where wider.
-- ((1.4.0-beta12) The deepest map at its middle read once, again when the shown maps change (RetailSpace.lua's Rebuild,
-- ns.SpaceGen): read every frame for every cave near the view - ns.DeepestMapAt goes through every map shown - it was the
-- add-on's largest work a frame, about 190 a frame on a zoom into Elwynn Forest and out - the player on 1.4.0-beta11,
-- "laggy, cpu spiked to 35%")
local function SwitchYards(c)
    local y = CITY_YARDS
    if c.sw ~= "city" then
        y = V.yards -- ((1.4.0-beta15) once a frame: CV:Frame)
        if y == nil then
            y = CV:CaveYards() or false
            V.yards = y
        end
        y = y or nil
    end
    if not y then return nil end
    local gen = ns.SpaceGen or 0
    if c.deepGen ~= gen then
        c.deep = ns.DeepestMapAt and ns.DeepestMapAt((c.x0 + c.x1) / 2, (c.y0 + c.y1) / 2)
        c.deepGen = gen
    end
    local d = c.deep
    local depth = ns.db and Plain(ns.db.maxZoom, "number") and ns.db.maxZoom or 4
    if d and d.yw and depth > 0 then
        -- (the narrowest view the wheel reaches over it: the deepest map at its depth limit, by width)
        y = math.max(y, d.yw / depth * 1.02)
    end
    return y
end

-- The yards across the view at cave level lv
local function ViewYards(lv)
    return (V.x1 - V.x0) / (lv.x1 - lv.x0) * lv.yw
end

-- ((1.4.0-beta10, RetailDoors.lua's hubs) every cave (nil before the tree is built), and the width in the camera's units
-- of the view cave c comes in at - its switch's yards on its top level (nil: never)
function CV:Caves() return Build() end
function CV:SwitchWidth(c)
    local y = SwitchYards(c)
    local lv = c and c.levels and c.levels[1]
    if not (y and lv and lv.yw and lv.yw > 0) then return nil end
    return y / lv.yw * (lv.x1 - lv.x0)
end

---------------------------------------------------------------------------
-- Holders and their textures
---------------------------------------------------------------------------
local function Room() return TL.newThisFrame + 4 <= TL.NEW_PER_FRAME and TL.newShown < TL.SHOW_PER_FRAME end
local function Spent(set, shown)
    TL.newThisFrame = TL.newThisFrame + set
    TL.newShown = TL.newShown + shown
end

local function Holder(lv)
    if lv.holder then return lv.holder end
    if not Room() then return nil end
    local f = CreateFrame("Frame", nil, overlay)
    f:SetSize(lv.lw, lv.lh)
    f:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0)
    f:EnableMouse(false)
    f:SetAlpha(0)
    f:Hide()
    lv.fa, lv.fOn = 0, false -- ((1.4.0-beta15) what it was last asked: no question a frame for each cave's each level)
    local m = f:CreateMaskTexture()
    m:SetTexture(lv.m, CLAMP, CLAMP, FILTER)
    local d = lv.cover and lv.cover.d
    m:SetPoint("TOPLEFT", f, "TOPLEFT", d and d[1] or 0, d and -d[2] or 0)
    m:SetSize(d and d[3] - d[1] or lv.lw, d and d[4] - d[2] or lv.lh)
    m.t0, m.file, m.mfile = now, lv.m, lv.m
    TL.Watch(m, nil, true, f, "mask") -- ((1.4.0-beta4's fixes, probe P1) the caves' loads measured too
    Spent(1, 0)
    lv.holder, lv.mask = f, m
    return f
end

-- A tile of level lv: over x0, y0 of its holder, w x h, its file's u1, v1
local function Tile(lv, f, key, file, x0, y0, w, h, u1, v1)
    local t = table.remove(lv.pool) or f:CreateTexture(nil, "ARTWORK")
    t:SetTexture(file, CLAMP, CLAMP, FILTER)
    t.file = file
    TL.Watch(t, nil, nil, f, "tile")
    t:SetTexCoord(0, u1, 0, v1)
    t:SetSize(w, h)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -y0)
    if not t.masked then -- (a texture from the holder's pool keeps its mask)
        t:AddMaskTexture(lv.mask)
        t.masked = true
    end
    t.t0 = now
    Spent(1, 1)
    lv.tex[key] = t
end

-- Level lv's textures (a micro map: its art's tiles; a minimap cave: its rim and blocks; (1.4.0-beta13) a cover: its home's
-- explored tiles under s, moved over d - the list's order, as they draw on the home), made once; false: not now
-- (the frame's budget, or the art the client gives is not the data's - another phase's).
local function Fill(lv, kind)
    if lv.filled then return true end
    local f = Holder(lv)
    if not f then return false end
    if lv.cover then
        local L = TL.Layout(lv.id)
        if not L then
            lv.noArt = true
            return false
        end
        lv.noArt = nil
        local d, s = lv.cover.d, lv.cover.s
        local dx, dy = d[1] - s[1], d[2] - s[2]
        local kx, ky = lv.lw / L.lw, lv.lh / L.lh
        for i, it in ipairs(TL.Pieces(lv.id, L)) do
            if not lv.tex[i] and it[1] + dx < d[3] and it[3] + dx > d[1] and it[2] + dy < d[4] and it[4] + dy > d[2] then
                if not Room() then return false end
                Tile(lv, f, i, it[7], (it[1] + dx) * kx, (it[2] + dy) * ky, (it[3] - it[1]) * kx, (it[4] - it[2]) * ky, it[5], it[6])
            end
        end
    elseif kind == "map" then
        local L = TL.Layout(lv.id)
        if not L then
            lv.noArt = true -- (the client gives no art for it: nothing to draw, nothing to wait for)
            return false
        end
        lv.noArt = nil
        if lv.f1 and L.files[1] ~= lv.f1 then
            lv.wrongArt = true
            return false
        end
        lv.wrongArt = nil
        -- (the art's px over the level's picture: the layout is the client's, the data's size the same)
        local kx, ky = lv.lw / L.lw, lv.lh / L.lh
        for r = 1, L.rows do
            for c = 1, L.cols do
                local file = L.files[(r - 1) * L.cols + c]
                if file and file ~= 0 and not lv.tex[(r - 1) * L.cols + c] then
                    if not Room() then return false end
                    local x0, y0 = (c - 1) * L.tw, (r - 1) * L.th
                    local w, h = math.min(L.tw, L.lw - x0), math.min(L.th, L.lh - y0)
                    Tile(lv, f, (r - 1) * L.cols + c, file, x0 * kx, y0 * ky, w * kx, h * ky,
                        (w - ((w < L.tw) and 0.5 or 0)) / L.tw, (h - ((h < L.th) and 0.5 or 0)) / L.th)
                end
            end
        end
    else
        if not lv.rim then
            if not Room() then return false end
            local s = f:CreateTexture(nil, "BACKGROUND")
            s:SetColorTexture(RIM[1], RIM[2], RIM[3], 1)
            s:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
            s:SetSize(lv.lw, lv.lh)
            s:AddMaskTexture(lv.mask)
            s.t0, s.at = now, now
            Spent(1, 1)
            lv.rim = s
        end
        for i, q in ipairs(lv.q or {}) do
            if not lv.tex[i] then
                if not Room() then return false end
                local t = table.remove(lv.pool) or f:CreateTexture(nil, "ARTWORK", nil, q[7] == 1 and 1 or 0)
                t:SetDrawLayer("ARTWORK", q[7] == 1 and 1 or 0)
                t:SetTexture(q[1], CLAMP, CLAMP, FILTER)
                t.file = q[1]
                TL.Watch(t, nil, nil, f, "tile")
                t:SetSize(q[4], q[5])
                t:SetPoint("CENTER", f, "TOPLEFT", q[2], -q[3])
                if t.SetRotation then t:SetRotation(q[6]) end
                if t.SetDesaturated then t:SetDesaturated(true) end
                t:SetVertexColor(TINT[1], TINT[2], TINT[3], 1)
                if not t.masked then
                    t:AddMaskTexture(lv.mask)
                    t.masked = true
                end
                t.t0 = now
                Spent(1, 1)
                lv.tex[i] = t
            end
        end
    end
    lv.filled = true
    return true
end

-- Every texture of level lv let go: to its holder's pool, no file (the next fill gives them files again; a texture
-- never moves to another frame).
local function Release(lv)
    for k, t in pairs(lv.tex) do
        TL.Unwatch(t)
        t.file = nil
        t:SetTexture(nil)
        t:ClearAllPoints()
        lv.pool[#lv.pool + 1] = t
        lv.tex[k] = nil
    end
    lv.filled, lv.loadedAt = nil, nil
    if lv.holder then
        lv.holder:SetAlpha(0)
        lv.holder:Hide()
        lv.fa, lv.fOn = 0, false
    end
    lv.a = 0
end

-- Is level lv loaded - every texture and its mask? ((1.4.0-beta4) its mask waited for as a texture is - RetailTiles.lua's
-- rule: no MASK_GIVEUP; (1.4.0-beta4's fixes) nor a texture given up after LOAD_GIVEUP from its first visible frame)
local function Loaded(lv)
    if TEST.noload then return true end
    local m = lv.mask
    if m and m.IsObjectLoaded and not m:IsObjectLoaded() then return false end
    for _, t in pairs(lv.tex) do
        if t.IsObjectLoaded and not t:IsObjectLoaded() then return false end
    end
    return true
end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------
local function Near(c, k)
    local mx, my = (V.x1 - V.x0) * k, (V.y1 - V.y0) * k
    return c.bx1 > V.x0 - mx and c.bx0 < V.x1 + mx and c.by1 > V.y0 - my and c.by0 < V.y1 + my
end
-- ((1.4.0-beta15) the near ones' test, its margins once a frame - CV:Frame; a cave nothing of which is on or made skips the rest: c.act)
local function NearNow(c)
    return c.bx1 > V.nx0 and c.bx0 < V.nx1 and c.by1 > V.ny0 and c.by0 < V.ny1
end
-- ((1.4.0-beta16) Over 300 caves walked every frame was 10% of the add-on's Lua. Those near the view by a grid, those something of which is on or made in active: the frame's
-- candidates, in their own order - the order they lie in, CV:Place)
local GRID_N = 32
local grid, gridX0, gridY0, gridKX, gridKY
local active = {}
local cands = {}
local function BuildGrid()
    grid = {}
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for i, c in ipairs(caves) do
        c.idx = i
        x0, y0, x1, y1 = math.min(x0, c.bx0), math.min(y0, c.by0), math.max(x1, c.bx1), math.max(y1, c.by1)
    end
    gridX0, gridY0 = x0, y0
    gridKX, gridKY = GRID_N / math.max(x1 - x0, 1e-9), GRID_N / math.max(y1 - y0, 1e-9)
    for _, c in ipairs(caves) do
        local c0, c1 = math.floor((c.bx0 - x0) * gridKX), math.min(GRID_N - 1, math.floor((c.bx1 - x0) * gridKX))
        local r0, r1 = math.floor((c.by0 - y0) * gridKY), math.min(GRID_N - 1, math.floor((c.by1 - y0) * gridKY))
        for r = r0, r1 do
            for k = c0, c1 do
                local key = r * GRID_N + k
                local b = grid[key]
                if not b then
                    b = {}
                    grid[key] = b
                end
                b[#b + 1] = c
            end
        end
    end
end
local function ByIdx(a, b) return a.idx < b.idx end

-- (the map the player is on: a level off its home's land shows only then)
local playerMap, playerAt
local function PlayerMap()
    if playerAt == now then return playerMap end
    playerAt = now
    playerMap = nil
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and Plain(id, "number") then playerMap = id end
    end
    return playerMap
end

-- ((1.4.0-beta10, the player on 1.4.0-beta9 at Kezan: "cave locations vs islands is wrong in the maelstrom") Does level l
-- show: every level that lies on its home's land (RetailCaveData.lua ol: a level off it - Kezan's three Kaja'mine maps, in the
-- sea by the game's own coordinates - only while the player is in it; on the home it stood in the sea like an island).
-- ((1.4.0-beta13) a cover: while the explored piece that prints its name shows - read again when the explored pieces change)
local function Shows(l)
    if not l.cover then return not l.ol or l.id == PlayerMap() end
    local L = TL.Layout(l.id)
    local P = L and TL.Pieces(l.id, L)
    if l.of ~= P then
        l.of, l.printed = P, false
        for _, it in ipairs(P or {}) do
            if it[1] == l.cover.piece[1] and it[2] == l.cover.piece[2] then
                l.printed = true
                break
            end
        end
    end
    return l.printed
end

-- ((1.4.0-beta15) The view's width past which cave c can neither show nor load ahead (PRE_K of its switch, any level's), read when what decides it changes - most caves at
-- most views: over 300 caves a frame, each its levels and its switch's yards)
local function FarWidth(c)
    local db = ns.db
    local gen, dz, dm = ns.SpaceGen or 0, db and db.caveZoom, db and db.maxZoom
    if c.farGen == gen and c.farZ == dz and c.farM == dm then return c.farW end
    c.farGen, c.farZ, c.farM = gen, dz, dm
    local y = SwitchYards(c)
    local w = 0
    if y then
        for _, l in ipairs(c.levels) do
            if l.yw and l.yw > 0 then
                local lw = y * PRE_K * (l.x1 - l.x0) / l.yw
                if lw > w then w = lw end
            end
        end
    end
    c.farW = w
    return w
end

local KnowsFar
local farLeft = 0
local function CountedFar(c)
    if not KnowsFar(c) then farLeft = farLeft - 1 end
    return FarWidth(c)
end
-- (the widest FarWidth of all: the view wider than this, no cave can show - most of the zooms. Worked out FAR_PER_FRAME caves a frame: each asks the deepest map at its middle, a walk
-- over every map, and when the shown maps change all of them would ask in one frame. Until it is done every cave near the view is looked at, those not worked out yet wait for a frame with room)
local FAR_PER_FRAME = 16
local maxFar, maxFarGen, maxFarZ, maxFarM, maxFarI
KnowsFar = function(c)
    local db = ns.db
    return c.farGen == (ns.SpaceGen or 0) and c.farZ == (db and db.caveZoom) and c.farM == (db and db.maxZoom)
end
local function MaxFar()
    local db = ns.db
    local gen, dz, dm = ns.SpaceGen or 0, db and db.caveZoom, db and db.maxZoom
    if maxFarGen ~= gen or maxFarZ ~= dz or maxFarM ~= dm then
        maxFarGen, maxFarZ, maxFarM, maxFarI, maxFar = gen, dz, dm, 1, 0
    end
    while maxFarI <= #caves and farLeft > 0 do
        local c = caves[maxFarI]
        if not KnowsFar(c) then farLeft = farLeft - 1 end
        local w = FarWidth(c)
        if w > maxFar then maxFar = w end
        maxFarI = maxFarI + 1
    end
    return maxFarI > #caves and maxFar or math.huge
end

-- Cave c this frame: its switch, its levels' load and fade, placed. Returns busy.
local function DrawCave(c)
    -- (the top one that shows: the switch's yards, the name's alpha)
    local lv
    for _, l in ipairs(c.levels) do
        if Shows(l) then
            lv = l
            break
        end
    end
    c.want = lv
    local y = lv and SwitchYards(c)
    local vy = lv and ViewYards(lv)
    local was = c.on
    if y and vy <= y then c.on = true elseif not y or vy > y * HIDE_K then c.on = false end
    if c.on == false and was then c.offAt = now end
    -- ((1.4.0-beta15) off, not loading ahead, nothing of it shown: the loop below would do nothing)
    if not c.on and not c.act and not (y and vy <= y * PRE_K) then
        alphaOf[c.key] = 0
        return false
    end
    c.act = true
    active[c] = true
    local busy = false
    local step = TEST.nofade and 1 or math.min(1, dt / SWITCH_FADE) -- (dt 0 - a second draw in a frame: no step)
    -- (the lowest first: its cover, the top level placed last, over the others - CV:Place)
    for i = #c.all, 1, -1 do
        local l = c.all[i]
        local shows = lv ~= nil and Shows(l)
        local on = c.on and shows
        local pre = shows and y ~= nil and vy <= y * PRE_K
        if on or pre or l.a > 0 then
            if Fill(l, c.kind) then
                local f = l.holder
                local scale = (l.x1 - l.x0) * V.ppx / l.lw
                if scale > 0 and scale < 1e6 then
                    local sx0, sy0 = V.W / 2 + (l.x0 - V.cx) * V.ppx, V.H / 2 + (l.y0 - V.cy) * V.ppy
                    if l.scale ~= scale or l.sx0 ~= sx0 or l.sy0 ~= sy0 then
                        f:SetScale(scale)
                        f:SetPoint("TOPLEFT", overlay, "TOPLEFT", sx0 / scale, -sy0 / scale)
                        l.scale, l.sx0, l.sy0 = scale, sx0, sy0
                    end
                    -- ((1.4.0-beta3, the reviews of 1.4.0-beta3) a level shown again shows its textures at once:
                    -- they count against the frame's room for newly shown textures - one off the screen, loaded ahead,
                    -- waits for a frame with room, as RetailRender.lua's parts do)
                    local defer = false
                    if not l.fOn then
                        local n = (l.rim and 1 or 0)
                        for _ in pairs(l.tex) do n = n + 1 end
                        if not Near(c, 0) and TL.newShown > 0 and TL.newShown + n > TL.SHOW_PER_FRAME then
                            defer = true
                        else
                            f:Show()
                            l.fOn = true
                            l.visAt = now
                            TL.newShown = TL.newShown + n
                            -- ((1.4.0-beta4's fixes, G7 - RetailRender.lua's Reshow) shown again: loaded as the client
                            -- says now - a level it let go while hidden loads and fades in again, never by a timer)
                            if l.loadedAt and not Loaded(l) then l.loadedAt = nil end
                        end
                    end
                    local ready = l.loadedAt ~= nil
                    if not ready and Loaded(l) then
                        l.loadedAt = now
                        ready = true
                    end
                    local lf = ready and (TEST.nofade and 1 or Smooth((now - l.loadedAt) / LOAD_FADE)) or 0
                    if on then l.a = math.min(1, l.a + step) else l.a = math.max(0, l.a - step) end
                    local a = l.a * lf
                    if (on and (l.a < 1 or lf < 1)) or (not on and l.a > 0) or not ready or defer then busy = true end
                    a = math.floor(Clamp01(a) * 255 + 0.5) / 255
                    if l.fa ~= a then
                        f:SetAlpha(a)
                        l.fa = a
                    end
                    if not defer then shownC[#shownC + 1] = l end
                    l.seenAt = now
                end
            else
                busy = busy or not (l.wrongArt or l.noArt) -- (the frame's budget spent: next frame)
            end
        end
    end
    alphaOf[c.key] = (c.want and c.want.a or 0) * ((c.want and c.want.loadedAt) and 1 or 0)
    return busy
end

-- (RetailRender.lua Render:Draw, after it planned) This frame's caves. Returns busy.
function CV:Frame(cam, v, ov)
    now = GetTime()
    dt = lastT and math.min(now - lastT, 0.05) or 0
    lastT = now
    overlay = overlay or ov
    wipe(shownC)
    if not (overlay and v and v.W and v.W > 0 and Build()) then return false end
    CV:AddLabels() -- (once Labels has its items: Core.lua's Setup)
    V.W, V.H, V.cx, V.cy = v.W, v.H, cam.x, cam.y
    V.ppx, V.ppy = ns.PixelsPerUnit(v, cam.vw)
    V.x0, V.x1 = cam.x - v.W / 2 / V.ppx, cam.x + v.W / 2 / V.ppx
    V.y0, V.y1 = cam.y - v.H / 2 / V.ppy, cam.y + v.H / 2 / V.ppy
    local mx, my = (V.x1 - V.x0) * NEAR, (V.y1 - V.y0) * NEAR
    V.nx0, V.nx1, V.ny0, V.ny1 = V.x0 - mx, V.x1 + mx, V.y0 - my, V.y1 + my
    V.yards = nil
    local busy = false
    CV.busyKey = nil
    local viewW = V.x1 - V.x0
    if not grid then BuildGrid() end
    farLeft = FAR_PER_FRAME
    -- ((1.4.0-beta16) this frame's caves: those near, by the grid - none with the view wider than any can show from - and the active ones, in their own order)
    local n = 0
    local mark = (CV.markN or 0) + 1
    CV.markN = mark
    for c in pairs(active) do
        n = n + 1
        cands[n] = c
        c.mark = mark
    end
    if viewW <= MaxFar() then
        local c0, c1 = math.max(0, math.floor((V.nx0 - gridX0) * gridKX)), math.min(GRID_N - 1, math.floor((V.nx1 - gridX0) * gridKX))
        local r0, r1 = math.max(0, math.floor((V.ny0 - gridY0) * gridKY)), math.min(GRID_N - 1, math.floor((V.ny1 - gridY0) * gridKY))
        for r = r0, r1 do
            for k = c0, c1 do
                local b = grid[r * GRID_N + k]
                if b then
                    for i = 1, #b do
                        local c = b[i]
                        if c.mark ~= mark then
                            c.mark = mark
                            n = n + 1
                            cands[n] = c
                        end
                    end
                end
            end
        end
    end
    for i = #cands, n + 1, -1 do cands[i] = nil end
    if n > 1 then table.sort(cands, ByIdx) end
    for i = 1, n do
        local c = cands[i]
        if c.h.visibleNow and NearNow(c) then
            if not c.act and not c.on and not KnowsFar(c) and farLeft <= 0 then
                alphaOf[c.key] = 0
                busy = true -- (the next frame has room)
            elseif not c.act and not c.on and viewW > CountedFar(c) then
                alphaOf[c.key] = 0
            elseif DrawCave(c) then
                busy = true
                CV.busyKey = CV.busyKey or c.key -- (/emap why, the harness: the first cave still busy)
            end
        else
            alphaOf[c.key] = 0
            if c.act then
                for _, l in ipairs(c.all) do
                    if l.holder and l.fOn then
                        l.holder:Hide()
                        l.fOn = false
                        l.visAt = nil
                    end
                    l.a = 0
                    if l.filled and now - (l.seenAt or 0) > RELEASE_AFTER then Release(l) end
                end
            end
        end
    end
    -- (the levels drawn last frame and not now: hidden; RELEASE_AFTER later their textures go - near the view or not)
    -- ((1.4.0-beta15) only the caves something of which is on or made: 300-odd, each frame)
    for c in pairs(active) do
        local any = false
        for _, l in ipairs(c.all) do
            if l.holder and l.fOn and l.seenAt ~= now then
                l.holder:Hide()
                l.fOn = false
                l.visAt = nil
            end
            if l.filled and l.seenAt ~= now and now - (l.seenAt or 0) > RELEASE_AFTER then Release(l) end
            if l.fOn or l.filled or l.a > 0 then any = true end
        end
        if not any then
            c.act = nil
            active[c] = nil
            alphaOf[c.key] = 0
        end
    end
    return busy
end

-- (RetailRender.lua PlaceParts, last) The caves' holders at the levels from L up; returns the next level free.
function CV:Place(L)
    for _, l in ipairs(shownC) do
        local f = l.holder
        if f.level ~= L then
            ns.SetLevelFixed(f, L)
            f.level = L
        end
        L = L + 1
    end
    return L
end

function CV:Hide()
    for _, c in ipairs(caves or {}) do
        for _, l in ipairs(c.all) do
            if l.holder then
                l.holder:Hide()
                l.fOn = false
                l.visAt = nil
            end
            l.a = 0
        end
        alphaOf[c.key] = 0
    end
    wipe(shownC)
end

function CV:Release()
    for _, c in ipairs(caves or {}) do
        for _, l in ipairs(c.all) do Release(l) end
    end
end

-- (Labels.lua) a cave's name with its picture
function R:DetailAlpha(key) return alphaOf[key] or 0 end
-- (ZoomReadout.lua, Options.lua: /emap cavezoom - the world zoom WoW Forever's caves show from; retail: as yards)
function R:CaveZoom()
    local z = ns.db and ns.db.caveZoom
    if z == false then return nil end
    return Plain(z, "number") and z or R.CAVE_G
end
function R:SetCaveZoom() end -- (read each frame: CV:CaveYards)

hooksecurefunc(R, "HideAll", function() CV:Hide() end)
hooksecurefunc(R, "ReleaseAll", function()
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then CV:Release() end
end)

-- ((1.4.0-beta10) the player walked into another map - a cave's level, an interior off its home's land (Level): the map at
-- rest draws again (Core.lua Redraw), so the level the player is on comes in while the map is open - not at its next move)
local zoneEv = CreateFrame("Frame")
zoneEv:RegisterEvent("ZONE_CHANGED")
zoneEv:RegisterEvent("ZONE_CHANGED_INDOORS")
zoneEv:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoneEv:SetScript("OnEvent", function()
    if WorldMapFrame and WorldMapFrame:IsShown() and ns.Core and ns.Core.Redraw then ns.Core.Redraw() end
end)

-- (tests) the caves, those placed this frame, their alphas
CV.T = { shown = shownC, alpha = alphaOf }
function CV:All() return Build() end
function CV:Stats()
    local n, filled, live = 0, 0, 0
    for _, c in ipairs(caves or {}) do
        for _, l in ipairs(c.all) do
            n = n + 1
            if l.filled then
                filled = filled + 1
                for _ in pairs(l.tex) do live = live + 1 end
            end
        end
    end
    return { caves = caves and #caves or 0, levels = n, filled = filled, live = live, shown = #shownC }
end
