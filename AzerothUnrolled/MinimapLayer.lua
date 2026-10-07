local _, ns = ...

--[[
MinimapLayer (1.3.0): the world map drawn from the game's own minimap pictures - the real terrain - instead of
the drawn parchment; switched by the round button left of the caves button (MapMenu.lua), the map menu, the Settings
page and /unroll imagery (Options.lua "imagery", default off: the drawn map stays the default look).

Everything is drawn in ONE frame, the holder: a child of Render's overlay on the overlay's own level - the level of the
parchment's world picture, which Render leaves out while the imagery shows (Render.lua Consider, dMM) - its textures
ordered by draw layer, bottom to top:
  * the open sea, one flat colour over the whole view (the minimap has no pictures of the open sea)
  * level 1-3, the composites (MinimapData.lua, tools/minimap/build_layer.py): 256 px pages of 16 / 32 / 64 px per ADT
    tile (533 yd), DXT1 BLP2 with a full mip chain - the one add-on image format proven in this client (the layer test
    of 1.3.0-beta1: a palettized BLP crashed it). Level 1 (14 pages for both continents) is the backdrop: all of it,
    always, loaded before the imagery takes over.
  * level 4, the client's own 512 px minimap tiles (by fileDataID: no mips, so a shrunk tile shimmers): once each shows
    at most CLIENT_IN texels per PHYSICAL screen pixel and no more than CLIENT_MAX of them are in view - and only with
    while "imageryTiles" is on (Options.lua, default on; /unroll imagerytiles): client minimap tiles by fileDataID are
    what Dalaran's detail map and the caves have drawn since 1.0 (design rule 12). Without them the 64 px level serves at
    every depth.
  * the open sea's colour again, through each coastal tile's sea mask (Masks\sea_*.tga): the open sea of the client's
    tiles - its dark background, its blue water - and of the fogged composites in the one sea colour; and over every
    tile without land inside the backdrop's pages (merged into rectangles, no mask), which the fog would grey with its
    page. Whole while the fog or the client tiles show (the composites' own open sea is that colour already).
  The level the zoom wants is the target; finer levels draw above coarser ones. A level shows only near the view (its
  window: the view grown by half its size, a tile for the client tiles; rebuilt once the view nears its edge), every
  picture fading in once it has loaded, over the level below - nothing blinks: the backdrop is always under it. A
  level the zoom left stays until the target covers the view, then the finer one fades out, the coarser one goes.
  Where a zoom in is heading (Render's prefetch) its level is loaded ahead, hidden. Textures and masks are pooled, at
  most MAX_TEX / MAX_MASKS, keyed by what they show (a window rebuilt keeps what stays in it: no reload, no blink),
  and released 10 s after the map closes (Render:ReleaseAll) or when the imagery is switched off. The target's copies
  and the sea are made before the levels it replaces get any more; whatever the caps held back is made again once a
  level has been released (the frame after, with the sea's alpha).
  Readiness (Render:IsReady, Core hides Blizzard's stale canvas while moving detached): the backdrop loaded.

Fog of war (technique A): as the drawn map's explored pieces fade in - continent zoom 2.5 to 4 (Render's LOD_C0 /
LOD_C1; built from 2.0) - every picture is desaturated (FOG_DESAT) and darkened (FOG_DIM), and full-colour copies of the
pictures are drawn through the explored-area tiles of every zone near the view (C_MapExplorationInfo, Blizzard's own
tiling of them: one mask per tile, as Render's footprints; a union of masks is drawn as stacked copies - masks on one
texture would intersect), each copy cut to the tile's used part (CLAMP), one mask per texture. The six capitals' cells
(ZoneMasks) are always explored, the sea always in colour (the sea masks lie above the fog). Below continent zoom 2.5
the imagery is all in colour, as Blizzard's continent maps have no fog. MAP_EXPLORATION_UPDATED (Render:MarkArtDirty)
rebuilds the copies: those that stay keep their texture - nothing blinks.

What else changes while the imagery shows (Render.lua, Labels.lua): no parchment base, cell, piece or core; the city
maps only of the capitals underground (KEEP_CITY: Ironforge, Undercity - the surface imagery shows Stormwind,
Orgrimmar, Darnassus and Thunder Bluff), without their home zones' banner covers; the detail levels (Blackrock
Mountain, Dalaran, the caves) without their parchment covers; zone and city names stay on deeper (no printed banner),
sub-zone names come with their explored pieces (MINIMAP_SUBZONES); Blizzard's own exploration pin (the real map's
explored parchment, drawn above our band at rest) is hidden - a post-hook on that one pin, as HighlightGuard.lua does,
setting only its alpha; switched back, it gets its alpha back.

WoW Forever only (the data is its minimap): elsewhere the setting does nothing and the button hides.
]]

local L = {}
ns.MinimapLayer = L

local ADT = 1600 / 3
local CLIENT = 512                        -- the client's own tiles: texels per ADT tile
local COMP_TEXELS = 1                     -- a composite serves while it has this many texels per physical screen px
local LEVEL_HYS = 1.25                    -- ... switching between the composites this far past that either way
local CLIENT_IN, CLIENT_OUT = 2, 2.5      -- the client's tiles from at most 2 texels per physical px, until 2.5
local CLIENT_MAX = 200                    -- ... and while at most this many of them (with a tile round the view) are in view
local WIN_MARGIN, WIN_KEEP = 0.5, 0.15    -- a composite's window: the view grown by half its size; rebuilt at 15 %
local FOG_MARGIN, FOG_KEEP = 0.25, 0.05   -- the fog's window (copies, sea quads): the view grown by a quarter; at 5 %
local WIN_SHRINK = 1.6                    -- any window rebuilt once wider or taller than this many times what it needs
local CLIENT_WIN, CLIENT_KEEP = 1, 0.25   -- the client tiles' window: a tile round the view; rebuilt at a quarter tile
local LOAD_FADE, LOAD_TIMEOUT = 0.15, 2   -- a picture fades in over this once loaded (after the timeout anyway)
local LEVEL_FADE = 0.2                    -- a level fades in / out over this
local FOG_C0, FOG_C1, FOG_PRE = 2.5, 4, 2 -- continent zoom: the fog fades in (Render LOD_C0 / LOD_C1), built from FOG_PRE
local FOG_DESAT, FOG_DIM = 0.9, 0.6       -- unexplored land: desaturated this much, darkened to this
local MAX_TEX, MAX_MASKS = 3000, 1200     -- hard caps: the textures and masks this file ever makes (all explored: 4K, out of
                                          -- the client tiles, about 2300 textures at the peak; the fog's first zoom 700 masks)
local LAYERS = { "BACKGROUND", "BORDER", "ARTWORK", "OVERLAY" } -- level 1..4; base sublevel 0, copies 1
local SEA_SUB = 7                         -- the sea masks' colour quads: OVERLAY 7, above every level
L.KEEP_CITY = { [1455] = true, [1458] = true } -- Ironforge, Undercity: underground, their city maps stay
L.CLIENT_IN, L.CLIENT_OUT, L.CLIENT_MAX, L.MAX_TEX, L.MAX_MASKS = CLIENT_IN, CLIENT_OUT, CLIENT_MAX, MAX_TEX, MAX_MASKS
L.FOG_DESAT, L.FOG_DIM, L.FOG_C0, L.FOG_C1 = FOG_DESAT, FOG_DIM, FOG_C0, FOG_C1

local D = ns.MINIMAP
local grids                               -- [m] = { ax, bx, ay, by: world-map px of grid point (col, row); pages, tiles, sea }
local W0, H0 = 1002, 668                  -- the world map's art px (its entry: Setup)
local holder, seaTex
local levels = {}
local masks = {}                          -- [mask key] = mask (shared by the copies of every level)
local seaQ = {}                           -- [m * 4096 + row * 64 + col] = the sea colour through that tile's sea mask
local seaR = {}                           -- [m * 4096 + i] = the sea colour over grids[m].seaRects[i] (tiles without land)
local freeTex, freeMask = {}, {}
local nTex, nMask, nSkipped = 0, 0, 0
local pending, fading = {}, {}            -- [texture] = true
local tilesOf, setOf = {}, {}             -- [zone id] = explored mask tiles / explored pieces ("ox:oy:w:h"), this fogGen
local fogGen = 0
local fl, fogPre, seaA = {}, {}, {}       -- [m] = fog alpha (0..1), fog built, sea quads' alpha
local active, onSince = false, nil
local target, dest                        -- level indices this frame
local now, dt, lastT = 0, 0, nil
local view = {}                           -- x0, y0, x1, y1 (world-map px), s (screen px per px), adtPhys
local place = {}                          -- the holder's placement last set
local seaStamp, pinHidden = nil, false
local fogWin, fogWinGen = nil, 0          -- the fog's window (world-map px) and its builds
local preview = {}                        -- key of the button's picture last set
local cap = { tex = MAX_TEX, masks = MAX_MASKS } -- (the caps in force: the imagery suite lowers them for a while)
for i, px in ipairs({ 16, 32, 64, CLIENT }) do
    levels[i] = { i = i, px = px, n = (px == CLIENT) and 1 or 256 / px, layer = LAYERS[i], tex = {}, copies = {}, a = 0, gen = 0 }
end

---------------------------------------------------------------------------
-- Setup: the grids on the world map (ns.WorldPosToMap of two tiles' centres: each grid is affine on it)
---------------------------------------------------------------------------
local isForever
function L:Supported()
    if isForever == nil then isForever = ((select(4, GetBuildInfo())) or 0) >= 16000 end
    return isForever and D ~= nil and D[0] ~= nil
end
function L:On() return ns.db ~= nil and ns.db.imagery == true and L:Supported() end
function L:TilesOn() return ns.db ~= nil and ns.db.imageryTiles == true end -- (the client's own tiles: /unroll imagerytiles)
function L:Active() return active end

local function Set(s)
    local t = {}
    for a, b in (s or ""):gmatch("(%d+),(%d+)") do t[tonumber(b) * 64 + tonumber(a)] = true end
    return t
end

-- The tiles without land inside the backdrop's pages (open sea the fog would grey with its page), merged: runs along each
-- row, a run continued down while the next row has the same one. { col0, row0, col1, row1 } each, inclusive.
local function SeaRects(g)
    local out, open = {}, {}
    local function Sea(c, r) return g.pages[1][math.floor(r / 16) * 64 + math.floor(c / 16)] and not g.tiles[r * 64 + c] end
    for r = 0, 63 do
        local now = {}
        local c = 0
        while c <= 63 do
            if Sea(c, r) then
                local c0 = c
                while c < 63 and Sea(c + 1, r) do c = c + 1 end
                local k = c0 * 64 + c
                local R = open[k]
                if R then R[4] = r else R = { c0, r, c, r } out[#out + 1] = R end
                now[k] = R
            end
            c = c + 1
        end
        open = now
    end
    return out
end

local function Grids()
    if grids ~= nil then return grids end
    local world = ns.maps and ns.maps[ns.WORLD_MAP_ID]
    if not (world and ns.WorldPosToMap and L:Supported()) then return nil end
    W0, H0 = world.lw, world.lh
    local out = {}
    for m = 0, 1 do
        local d = D[m]
        local p = d and d.probe
        if p then
            local x0, y0 = ns.WorldPosToMap(m, (32 - p[2] - 0.5) * ADT, (32 - p[1] - 0.5) * ADT)
            local x1, y1 = ns.WorldPosToMap(m, (32 - p[4] - 0.5) * ADT, (32 - p[3] - 0.5) * ADT)
            if x0 and x1 and y0 and y1 and p[3] ~= p[1] and p[4] ~= p[2] then
                local g = { m = m, cont = d.cont, pages = {}, tiles = {}, sea = Set(d.sea) }
                g.bx = (x1 - x0) * W0 / (p[3] - p[1])
                g.ax = x0 * W0 - g.bx * (p[1] + 0.5)
                g.by = (y1 - y0) * H0 / (p[4] - p[2])
                g.ay = y0 * H0 - g.by * (p[2] + 0.5)
                for i = 1, 3 do g.pages[i] = Set(d.pages[levels[i].px]) end
                local t = d.tiles or {}
                for k = 1, #t - 2, 3 do g.tiles[t[k + 1] * 64 + t[k]] = t[k + 2] end
                g.pages[4] = g.tiles
                g.seaRects = SeaRects(g)
                if g.bx > 0 and g.by > 0 then out[m] = g end
            end
        end
    end
    grids = next(out) and out or false
    return grids or nil
end

-- Grid cell (col, row) of level lev on grid g: its rect in world-map px.
local function CellRect(g, lev, c, r)
    local n = lev.n
    local x0, y0 = g.ax + g.bx * c * n, g.ay + g.by * r * n
    return x0, y0, x0 + g.bx * n, y0 + g.by * n
end

-- The cells of level lev on grid g over world-map px rect (x0, y0, x1, y1): c0, r0, c1, r1 (nil: none).
local function CellsOver(g, lev, x0, y0, x1, y1)
    local n, cells = lev.n, 64 / lev.n
    local c0 = math.max(0, math.floor((x0 - g.ax) / g.bx / n))
    local c1 = math.min(cells - 1, math.floor((x1 - g.ax) / g.bx / n))
    local r0 = math.max(0, math.floor((y0 - g.ay) / g.by / n))
    local r1 = math.min(cells - 1, math.floor((y1 - g.ay) / g.by / n))
    if c1 < c0 or r1 < r0 then return nil end
    return c0, r0, c1, r1
end

local function FileOf(lev, m, key)
    if lev.i == 4 then return grids[m].tiles[key] end
    return D.path .. ("%d_%d_%d_%d.blp"):format(m, lev.px, key % 64, math.floor(key / 64))
end

---------------------------------------------------------------------------
-- Pooled textures and masks
---------------------------------------------------------------------------
local function NewTex(layer, sub)
    local t = table.remove(freeTex)
    if not t then
        if nTex >= cap.tex then
            nSkipped = nSkipped + 1
            return nil
        end
        nTex = nTex + 1
        t = holder:CreateTexture(nil, layer)
    end
    t:SetDrawLayer(layer, sub)
    t:ClearAllPoints()
    t:SetAlpha(0)
    t.a, t.at, t.fl = 0, nil, nil
    t.t0 = now
    pending[t] = true
    t:Show()
    return t
end

local function UnrefMask(m)
    m.refs = m.refs - 1
    if m.refs > 0 then return end
    masks[m.key] = nil
    m:Hide()
    m:ClearAllPoints()
    m:SetTexture(nil)
    m.key, m.file = nil, nil
    freeMask[#freeMask + 1] = m
end

local function FreeTex(t)
    if t.mask then
        t:RemoveMaskTexture(t.mask) -- (Blizzard's order: the texture lets go first, MapCanvasMixin:SetMaskTexture)
        UnrefMask(t.mask)
        t.mask = nil
    end
    if t.desat then
        if t.SetDesaturation then t:SetDesaturation(0) elseif t.SetDesaturated then t:SetDesaturated(false) end
        t:SetVertexColor(1, 1, 1, 1)
        t.desat = nil
    end
    t:Hide()
    t:ClearAllPoints()
    t:SetTexture(nil)
    t.key, t.m, t.base, t.at, t.a, t.fl, t.file = nil, nil, nil, nil, nil, nil, nil
    pending[t], fading[t] = nil, nil
    freeTex[#freeTex + 1] = t
end

-- A mask tile T (key, file, mx, my, mw, mh: the whole file placed in world-map px) - shared, counted.
local function MaskFor(T)
    local m = masks[T.key]
    if m then
        m.refs = m.refs + 1
        return m
    end
    m = table.remove(freeMask)
    if not m then
        if nMask >= cap.masks then
            nSkipped = nSkipped + 1
            return nil
        end
        nMask = nMask + 1
        m = holder:CreateMaskTexture()
    end
    m:SetTexture(T.file, "CLAMP", "CLAMP", "TRILINEAR")
    m:SetSize(T.mw, T.mh)
    m:SetPoint("TOPLEFT", holder, "TOPLEFT", T.mx, -T.my)
    m:Show()
    m.key, m.file, m.refs = T.key, T.file, 1
    masks[T.key] = m
    return m
end

-- Texture t shows world-map px rect (x0, y0, x1, y1) of the picture `file` that spans (fx0, fy0, fx1, fy1).
local function Put(t, file, x0, y0, x1, y1, fx0, fy0, fx1, fy1)
    t:SetTexture(file, "CLAMP", "CLAMP", "TRILINEAR")
    local w, h = fx1 - fx0, fy1 - fy0
    t:SetTexCoord((x0 - fx0) / w, (x1 - fx0) / w, (y0 - fy0) / h, (y1 - fy0) / h)
    t:SetSize(x1 - x0, y1 - y0)
    t:SetPoint("TOPLEFT", holder, "TOPLEFT", x0, -y0)
    t.x0, t.y0, t.x1, t.y1, t.file = x0, y0, x1, y1, file
end

---------------------------------------------------------------------------
-- Exploration: the mask tiles of a zone (its explored pieces in Blizzard's tiling) and of the capitals
---------------------------------------------------------------------------
local function ExploredList(id)
    if not (C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures) then return nil end
    local ok, res = pcall(C_MapExplorationInfo.GetExploredMapTextures, id)
    if not ok or type(res) ~= "table" then return nil end
    local out = {}
    for _, info in ipairs(res) do
        if type(info) == "table" and info.fileDataIDs and not info.isShownByMouseOver and info.textureWidth and info.textureHeight then
            out[#out + 1] = info
        end
    end
    return out
end

-- (as Render's ForEachPieceTile: Blizzard's MapExplorationPinMixin tiling, the smallest file ns.TILE_FILE_MIN)
local function PieceTiles(e, list, out)
    local kx, ky = (e.x1 - e.x0) * W0 / e.lw, (e.y1 - e.y0) * H0 / e.lh
    local ox, oy = e.x0 * W0, e.y0 * H0
    for _, info in ipairs(list) do
        local tw, th = info.textureWidth, info.textureHeight
        local wide, tall = math.ceil(tw / 256), math.ceil(th / 256)
        for j = 1, tall do
            local ph, fh = 256, 256
            if j == tall then
                ph = th % 256
                if ph == 0 then ph = 256 end
                fh = ns.TILE_FILE_MIN or 16
                while fh < ph do fh = fh * 2 end
            end
            for k = 1, wide do
                local pw, fw = 256, 256
                if k == wide then
                    pw = tw % 256
                    if pw == 0 then pw = 256 end
                    fw = ns.TILE_FILE_MIN or 16
                    while fw < pw do fw = fw * 2 end
                end
                local file = info.fileDataIDs[(j - 1) * wide + k]
                local x0, y0 = (info.offsetX or 0) + 256 * (k - 1), (info.offsetY or 0) + 256 * (j - 1)
                if file then
                    out[#out + 1] = { key = ("%d:%s:%d:%d"):format(e.id, tostring(file), x0, y0), file = file,
                        mx = ox + x0 * kx, my = oy + y0 * ky, mw = fw * kx, mh = fh * ky,
                        ux0 = ox + x0 * kx, uy0 = oy + y0 * ky,
                        ux1 = ox + math.min(x0 + pw, e.lw) * kx, uy1 = oy + math.min(y0 + ph, e.lh) * ky }
                end
            end
        end
    end
end

local cellOk
local function CapitalTiles(out, m)
    for _, id in ipairs(ns.CAPITALS or {}) do
        local e, c = ns.maps[id], ns.ZoneMasks and ns.ZoneMasks[id]
        if e and c and c.kind == "city" and e.parent == grids[m].cont then
            if cellOk == nil then cellOk = {} end
            if cellOk[id] == nil then cellOk[id] = (C_Map.GetMapArtID and C_Map.GetMapArtID(id) == c.art) == true end
            if cellOk[id] and e.lw and e.lh then
                local kx, ky = (e.x1 - e.x0) * W0 / e.lw, (e.y1 - e.y0) * H0 / e.lh
                local nz = c.nz
                out[#out + 1] = { key = "city:" .. id, file = c.file, mx = e.x0 * W0, my = e.y0 * H0,
                    mw = (e.x1 - e.x0) * W0, mh = (e.y1 - e.y0) * H0,
                    ux0 = (e.x0 * W0) + nz[1] * kx, uy0 = (e.y0 * H0) + nz[2] * ky,
                    ux1 = (e.x0 * W0) + nz[3] * kx, uy1 = (e.y0 * H0) + nz[4] * ky }
            end
        end
    end
end

-- The mask tiles over world-map px rect R of grid m's continent: every explored-area tile of its zones there, the
-- capitals' cells.
local function MaskTiles(m, x0, y0, x1, y1)
    local out = {}
    local g = grids[m]
    for _, e in ipairs(ns.drawList or {}) do
        if e.mapType == ns.MAPTYPE_ZONE and e.parent == g.cont and not L.KEEP_CITY[e.id] and e.lw and e.lh
            and e.x0 * W0 < x1 and e.x1 * W0 > x0 and e.y0 * H0 < y1 and e.y1 * H0 > y0 then
            local T = tilesOf[e.id]
            if not T then
                T = {}
                local list = ExploredList(e.id)
                if list then PieceTiles(e, list, T) end
                tilesOf[e.id] = T
            end
            for _, t in ipairs(T) do
                if t.ux0 < x1 and t.ux1 > x0 and t.uy0 < y1 and t.uy1 > y0 then out[#out + 1] = t end
            end
        end
    end
    CapitalTiles(out, m)
    return out
end

-- (Labels.lua) Is the explored-area piece (ox, oy, w, h) of zone id explored?
function L:PieceExplored(id, ox, oy, w, h)
    local s = setOf[id]
    if not s then
        s = {}
        for _, info in ipairs(ExploredList(id) or {}) do
            s[("%d:%d:%d:%d"):format(info.offsetX or 0, info.offsetY or 0, info.textureWidth, info.textureHeight)] = true
        end
        setOf[id] = s
    end
    return s[("%d:%d:%d:%d"):format(ox, oy, w, h)] == true
end

---------------------------------------------------------------------------
-- Levels: windows, copies, the sea quads
---------------------------------------------------------------------------
local function ReleaseLevel(lev)
    for ck, c in pairs(lev.copies) do
        FreeTex(c)
        lev.copies[ck] = nil
    end
    for key, t in pairs(lev.tex) do
        FreeTex(t)
        lev.tex[key] = nil
    end
    lev.live, lev.win, lev.a, lev.copyStamp, lev.short = nil, nil, 0, nil, nil
    lev.gen = lev.gen + 1
end

-- Level lev shows the cells over world-map px rect (x0, y0, x1, y1): textures kept for the cells that stay, made for
-- the new ones, released for the others.
local function BuildWindow(lev, x0, y0, x1, y1)
    local want = {}
    lev.win = { x0, y0, x1, y1 }
    lev.short = nil -- (a picture the cap held back: built again next time)
    for m, g in pairs(grids) do
        local c0, r0, c1, r1 = CellsOver(g, lev, x0, y0, x1, y1)
        if c0 then
            local have = g.pages[lev.i]
            for r = r0, r1 do
                for c = c0, c1 do
                    local key = r * 64 + c
                    if have[key] then want[m * 4096 + key] = true end
                end
            end
        end
    end
    for k, t in pairs(lev.tex) do
        if not want[k] then
            FreeTex(t)
            lev.tex[k] = nil
        end
    end
    for k in pairs(want) do
        if not lev.tex[k] then
            local m, key = math.floor(k / 4096), k % 4096
            local t = NewTex(lev.layer, 0)
            if t then
                local cx0, cy0, cx1, cy1 = CellRect(grids[m], lev, key % 64, math.floor(key / 64))
                Put(t, FileOf(lev, m, key), cx0, cy0, cx1, cy1, cx0, cy0, cx1, cy1)
                t.key, t.m = k, m
                lev.tex[k] = t
            else
                lev.short = true
            end
        end
    end
    lev.live = true
    lev.gen = lev.gen + 1
end

-- The full-colour copies of level lev's pictures through the mask tiles near it (fog of war).
local COPY_BUDGET = 300 -- (1.3.0: at most this many copies made per frame; the rest the frames after)
local copyBudget, copiesShort = COPY_BUDGET, false
local function BuildCopies(lev)
    local stamp = ("%d:%d:%d:%s:%s"):format(lev.gen, fogGen, fogWinGen, tostring(fogPre[0]), tostring(fogPre[1]))
    if lev.copyStamp == stamp then return end
    lev.copyStamp = stamp
    local want = {}
    local w = fogWin
    for m, g in pairs(grids) do
        if fogPre[m] and w then
            for _, T in ipairs(MaskTiles(m, w[1], w[2], w[3], w[4])) do
                local c0, r0, c1, r1 = CellsOver(g, lev, T.ux0, T.uy0, T.ux1, T.uy1)
                if c0 then
                    for r = r0, r1 do
                        for c = c0, c1 do
                            local k = m * 4096 + r * 64 + c
                            local base = lev.tex[k]
                            if base then want[k .. "|" .. T.key] = T end
                        end
                    end
                end
            end
        end
    end
    for ck, c in pairs(lev.copies) do
        if not want[ck] or lev.tex[c.baseKey] ~= c.base then
            FreeTex(c)
            lev.copies[ck] = nil
        end
    end
    local short = false
    for ck, T in pairs(want) do
        if not lev.copies[ck] and copyBudget <= 0 then short = true break end -- (1.3.0)
        if not lev.copies[ck] then
            copyBudget = copyBudget - 1
            local k = tonumber(ck:match("^(%d+)|"))
            local base = lev.tex[k]
            local x0, y0 = math.max(base.x0, T.ux0), math.max(base.y0, T.uy0)
            local x1, y1 = math.min(base.x1, T.ux1), math.min(base.y1, T.uy1)
            if x1 - x0 > 1e-3 and y1 - y0 > 1e-3 then
                local c = NewTex(lev.layer, 1)
                local mk = c and MaskFor(T)
                if mk then
                    Put(c, base.file, x0, y0, x1, y1, base.x0, base.y0, base.x1, base.y1)
                    c:AddMaskTexture(mk)
                    c.mask, c.base, c.baseKey, c.m, c.key = mk, base, k, base.m, ck
                    lev.copies[ck] = c
                else
                    if c then FreeTex(c) end
                    short = true
                end
            end
        end
    end
    if short then lev.copyStamp = nil copiesShort = true end -- (the caps held some back: built again next time)
end

-- The sea colour over the fog's window, where the fog or the client tiles show: through each coastal tile's sea mask,
-- and over the tiles without land (the rectangles: the fog greys them with their page, the client tiles have none there).
local function BuildSea()
    local w = fogWin
    local stamp = ("%d:%s:%s"):format(fogWinGen, tostring(seaA[0] > 0), tostring(seaA[1] > 0))
    if seaStamp == stamp then return end
    seaStamp = stamp
    local want, wantR = {}, {}
    for m, g in pairs(grids) do
        if w and seaA[m] > 0 then
            local c0, r0, c1, r1 = CellsOver(g, levels[4], w[1], w[2], w[3], w[4])
            if c0 then
                for r = r0, r1 do
                    for c = c0, c1 do
                        if g.sea[r * 64 + c] then want[m * 4096 + r * 64 + c] = true end
                    end
                end
                for i, R in ipairs(g.seaRects) do
                    if R[1] <= c1 and R[3] >= c0 and R[2] <= r1 and R[4] >= r0 then wantR[m * 4096 + i] = R end
                end
            end
        end
    end
    for k, q in pairs(seaQ) do
        if not want[k] then
            FreeTex(q)
            seaQ[k] = nil
        end
    end
    for k, q in pairs(seaR) do
        if not wantR[k] then
            FreeTex(q)
            seaR[k] = nil
        end
    end
    local sea = D.sea
    local short = false
    for k, R in pairs(wantR) do
        if not seaR[k] then
            local m = math.floor(k / 4096)
            local q = NewTex("OVERLAY", SEA_SUB)
            if q then
                local x0, y0 = CellRect(grids[m], levels[4], R[1], R[2])
                local _, _, x1, y1 = CellRect(grids[m], levels[4], R[3], R[4])
                q:SetColorTexture(sea[1], sea[2], sea[3], 1)
                q:SetSize(x1 - x0, y1 - y0)
                q:SetPoint("TOPLEFT", holder, "TOPLEFT", x0, -y0)
                q.x0, q.y0, q.x1, q.y1 = x0, y0, x1, y1
                q.m, q.key = m, k
                seaR[k] = q
            else
                short = true
            end
        end
    end
    for k in pairs(want) do
        if not seaQ[k] then
            local m, key = math.floor(k / 4096), k % 4096
            local c, r = key % 64, math.floor(key / 64)
            local q = NewTex("OVERLAY", SEA_SUB)
            if q then
                local x0, y0, x1, y1 = CellRect(grids[m], levels[4], c, r)
                local mk = MaskFor({ key = ("sea:%d:%d:%d"):format(m, c, r), file = ("%ssea_%d_%d_%d.tga"):format(D.maskPath, m, c, r),
                    mx = x0, my = y0, mw = x1 - x0, mh = y1 - y0 })
                if mk then
                    q:SetColorTexture(sea[1], sea[2], sea[3], 1)
                    q:SetSize(x1 - x0, y1 - y0)
                    q:SetPoint("TOPLEFT", holder, "TOPLEFT", x0, -y0)
                    q.x0, q.y0, q.x1, q.y1 = x0, y0, x1, y1
                    q:AddMaskTexture(mk)
                    q.mask, q.m, q.key = mk, m, k
                    seaQ[k] = q
                else
                    FreeTex(q)
                    short = true
                end
            else
                short = true
            end
        end
    end
    if short then seaStamp = nil end -- (the caps held some back: built again next time)
end

---------------------------------------------------------------------------
-- Choosing the level
---------------------------------------------------------------------------
-- Client tiles with a tile round world-map px rect R: how many (the cap)?
local function ClientCount(x0, y0, x1, y1)
    local n = 0
    for _, g in pairs(grids) do
        local c0, r0, c1, r1 = CellsOver(g, levels[4], x0 - g.bx * CLIENT_WIN, y0 - g.by * CLIENT_WIN, x1 + g.bx * CLIENT_WIN, y1 + g.by * CLIENT_WIN)
        if c0 then
            for r = r0, r1 do
                for c = c0, c1 do
                    if g.tiles[r * 64 + c] then n = n + 1 end
                end
            end
        end
    end
    return n
end

-- The level for physical px per ADT tile `adt` over rect R; cur: the level now (hysteresis).
local function Pick(adt, cur, x0, y0, x1, y1)
    local d = CLIENT / adt
    if L:TilesOn() and (d <= CLIENT_IN or (cur == 4 and d <= CLIENT_OUT)) and ClientCount(x0, y0, x1, y1) <= CLIENT_MAX then return 4 end
    local want = adt * COMP_TEXELS
    if cur and cur <= 3 and levels[cur].px * LEVEL_HYS >= want and (cur == 1 or levels[cur - 1].px < want * LEVEL_HYS) then
        return cur
    end
    for i = 1, 3 do
        if levels[i].px >= want then return i end
    end
    return 3
end

-- Physical screen px per container unit (the user's 4K screen at UI scale 0.64: 1.8).
local function PhysPerUnit(host)
    local ph = 768
    if GetPhysicalScreenSize then
        local ok, _, h = pcall(GetPhysicalScreenSize)
        if ok and type(h) == "number" and h > 0 then ph = h end
    end
    local s = host and host.GetEffectiveScale and host:GetEffectiveScale() or 1
    return s * ph / 768
end

-- The window rect of level lev around world-map px rect R, and its keep test.
local function Grown(lev, x0, y0, x1, y1, keep)
    if lev.i == 4 then
        local g = grids[0] or grids[1]
        local k = keep and CLIENT_KEEP or CLIENT_WIN
        return x0 - g.bx * k, y0 - g.by * k, x1 + g.bx * k, y1 + g.by * k
    end
    local k = keep and WIN_KEEP or WIN_MARGIN
    local w, h = x1 - x0, y1 - y0
    return x0 - w * k, y0 - h * k, x1 + w * k, y1 + h * k
end

-- Does window w = {x0, y0, x1, y1} still fit: holding rect (a, b, c, d), not too big for the wanted (A, B, C, D)?
local function Fits(w, a, b, c, d, A, B, C, D)
    return w ~= nil and a >= w[1] and b >= w[2] and c <= w[3] and d <= w[4]
        and w[3] - w[1] <= (C - A) * WIN_SHRINK and w[4] - w[2] <= (D - B) * WIN_SHRINK
end

local function EnsureWindow(lev, x0, y0, x1, y1)
    local a, b, c, d = Grown(lev, x0, y0, x1, y1, true)
    local A, B, C, D = Grown(lev, x0, y0, x1, y1, false)
    if lev.i == 1 then
        if not lev.win or lev.short then BuildWindow(lev, -1e9, -1e9, 1e9, 1e9) end
    elseif lev.short or not Fits(lev.win, a, b, c, d, A, B, C, D) then
        BuildWindow(lev, A, B, C, D)
    end
end

-- The fog's window: the view grown by FOG_MARGIN (a zoom heading in: its destination is inside the view).
local function EnsureFogWindow(x0, y0, x1, y1)
    local w, h = x1 - x0, y1 - y0
    local A, B, C, D = x0 - w * FOG_MARGIN, y0 - h * FOG_MARGIN, x1 + w * FOG_MARGIN, y1 + h * FOG_MARGIN
    if not Fits(fogWin, x0 - w * FOG_KEEP, y0 - h * FOG_KEEP, x1 + w * FOG_KEEP, y1 + h * FOG_KEEP, A, B, C, D) then
        fogWin = { A, B, C, D }
        fogWinGen = fogWinGen + 1
    end
end

---------------------------------------------------------------------------
-- Alphas: each picture's load fade, its level's alpha, the fog
---------------------------------------------------------------------------
local function LoadA(t)
    if not t.at then
        local ok = now - (t.t0 or now) >= LOAD_TIMEOUT
        if not ok then
            ok = (not t.IsObjectLoaded or t:IsObjectLoaded()) and (not t.mask or not t.mask.IsObjectLoaded or t.mask:IsObjectLoaded())
        end
        if not ok then return 0 end
        t.at = now
        pending[t] = nil
        fading[t] = true
    end
    local x = (now - t.at) / LOAD_FADE
    if x >= 1 then
        fading[t] = nil
        return 1
    end
    return ns.Smooth(x)
end

local function SetA(t, a)
    a = math.floor(ns.Clamp01(a) * 255 + 0.5) / 255
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

-- Returns: the target covers the view (every picture of it there loaded, the level in), the backdrop is loaded.
local function Alphas()
    local covered, backdrop, whole = true, true, true
    local v = view
    for i = 1, 4 do
        local lev = levels[i]
        if lev.live then
            for _, t in pairs(lev.tex) do
                local ta = LoadA(t)
                SetA(t, ta * lev.a)
                Fog(t, fl[t.m] or 0)
                if i == 1 and ta <= 0 then backdrop = false end
                if i == 1 and ta < 1 then whole = false end -- (1.3.0: the backdrop faded in whole, under the holder at alpha 0)
                if i == target and ta < 1 and t.x0 < v.x1 and t.x1 > v.x0 and t.y0 < v.y1 and t.y1 > v.y0 then covered = false end
            end
            for _, c in pairs(lev.copies) do
                local ca = LoadA(c)
                SetA(c, ca * lev.a * (fl[c.m] or 0))
                if i == target and ca < 1 and (fl[c.m] or 0) > 0 and c.x0 < v.x1 and c.x1 > v.x0 and c.y0 < v.y1 and c.y1 > v.y0 then covered = false end
            end
        end
    end
    -- (the sea whole wherever it is built: under it the composites' own open sea is that colour - no shade while the fog
    -- fades in or out)
    for _, q in pairs(seaQ) do SetA(q, (seaA[q.m] or 0) > 0 and LoadA(q) or 0) end
    for _, q in pairs(seaR) do SetA(q, (seaA[q.m] or 0) > 0 and LoadA(q) or 0) end
    return covered and levels[target].a >= 1, backdrop, whole
end

---------------------------------------------------------------------------
-- Blizzard's exploration pin: the real map's explored parchment, drawn above our band at rest - hidden while the
-- imagery shows (its alpha only, after Blizzard's own RefreshAlpha / RefreshOverlays: a post-hook, as HighlightGuard)
---------------------------------------------------------------------------
local pin, pinHooked
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
        -- (the alpha Blizzard's RefreshAlpha gives it; while its overlays load, its own OnUpdate does that)
        local a = 1
        if WorldMapFrame.GetGlobalAlpha then
            local ok, g = pcall(WorldMapFrame.GetGlobalAlpha, WorldMapFrame)
            if ok and type(g) == "number" then a = g end
        end
        pin:SetAlpha(a)
    end
end
function L:PinHidden() return pinHidden, pin end

---------------------------------------------------------------------------
-- The layer button's picture (MapMenu.lua): a live preview of the OTHER look under the view's centre - the minimap
-- tile there (from its 64 px composite, which has mips) while the drawn map shows, the drawn map's art tile there while
-- the imagery shows. Set at rest only (and when asked: the setting changed).
---------------------------------------------------------------------------
local lastCam
local function PreviewOf(x, y, imagery)
    if imagery then
        local e = ns.DeepestMapAt and ns.DeepestMapAt(x, y)
        local layers = e and C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(e.id)
        local Ly = layers and layers[1]
        local files = e and Ly and C_Map.GetMapArtLayerTextures and C_Map.GetMapArtLayerTextures(e.id, 1)
        if not (files and Ly.tileWidth and Ly.tileWidth > 0 and Ly.layerWidth) then return nil end
        local px = (x - e.x0) / (e.x1 - e.x0) * Ly.layerWidth
        local py = (y - e.y0) / (e.y1 - e.y0) * Ly.layerHeight
        local tw, th = Ly.tileWidth, Ly.tileHeight
        local cols = math.ceil(Ly.layerWidth / tw)
        local tc, tr = math.floor(px / tw), math.floor(py / th)
        local file = files[tr * cols + tc + 1]
        if not file then return nil end
        -- (a quarter of the tile round the point, inside its used part)
        local uw, uh = math.min(tw, Ly.layerWidth - tc * tw), math.min(th, Ly.layerHeight - tr * th)
        local s = math.min(tw / 2, uw, uh)
        local l = ns.Clamp(px - tc * tw - s / 2, 0, uw - s)
        local t = ns.Clamp(py - tr * th - s / 2, 0, uh - s)
        return file, l / tw, (l + s) / tw, t / th, (t + s) / th
    end
    for m, g in pairs(grids) do
        local c, r = math.floor((x * W0 - g.ax) / g.bx), math.floor((y * H0 - g.ay) / g.by)
        if c >= 0 and c < 64 and r >= 0 and r < 64 and g.tiles[r * 64 + c] then
            local px, py = math.floor(c / 4), math.floor(r / 4)
            local i, j = c - px * 4, r - py * 4
            return ("%s%d_64_%d_%d.blp"):format(D.path, m, px, py), i / 4, (i + 1) / 4, j / 4, (j + 1) / 4
        end
    end
    return "sea"
end

function L:RefreshPreview(force)
    local MM = ns.MapMenu
    if not (MM and MM.SetLayerPicture and Grids()) then return end
    local x, y = 0.5, 0.5
    if lastCam then x, y = lastCam.x, lastCam.y end
    local file, l, r, t, b = PreviewOf(x, y, active)
    if not file and active then file, l, r, t, b = PreviewOf(x, y, false) end -- (no art there: the tile)
    local key = ("%s:%s:%s:%s:%s"):format(tostring(file), tostring(l), tostring(r), tostring(t), tostring(b))
    if key == preview.key and not force then return end
    preview.key = key
    if file == "sea" or not file then
        MM:SetLayerPicture(nil, D.sea)
    else
        MM:SetLayerPicture(file, nil, l, r, t, b)
    end
end
function L:PreviewKey() return preview.key end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local function Setup(host)
    if not Grids() then return false end
    if not holder then
        holder = CreateFrame("Frame", nil, host)
        holder:SetSize(W0, H0)
        holder:EnableMouse(false)
        holder:SetAlpha(0)
        holder:Hide()
        seaTex = holder:CreateTexture(nil, "BACKGROUND", nil, -8)
        local s = D.sea
        seaTex:SetColorTexture(s[1], s[2], s[3], 1)
    end
    if holder:GetParent() ~= host then
        holder:SetParent(host)
        holder.level = nil
    end
    return true
end

-- Everything released (the map closed 10 s ago, the imagery switched off): textures and masks keep no file.
function L:Release()
    for i = 1, 4 do ReleaseLevel(levels[i]) end
    for k, q in pairs(seaQ) do
        FreeTex(q)
        seaQ[k] = nil
    end
    for k, q in pairs(seaR) do
        FreeTex(q)
        seaR[k] = nil
    end
    seaStamp, fogWin = nil, nil
    target, dest = nil, nil
    wipe(place)
end

function L:Hide()
    if holder and holder:IsShown() then holder:Hide() end
    wipe(place)
    PinSync(false)
end

local function Off()
    local was = active
    active, onSince = false, nil
    L:Release()
    L:Hide()
    if holder then holder:SetAlpha(0) end
    if was and ns.Render then ns.Render:MarkArtDirty() end
end

-- The holder on the overlay: scale = screen px per world-map px, its top-left the world map's.
local function Place(cam, v, ppx, ppy, host)
    local s = v.fit0 / cam.vw
    local ox, oy = v.W / 2 - cam.x * ppx, v.H / 2 - cam.y * ppy
    local level = host:GetFrameLevel()
    -- (a redraw at rest re-reads the view from Blizzard's canvas: float noise far below a screen pixel moves nothing)
    if not (place.s and math.abs(s - place.s) <= s * 1e-9 and math.abs(ox - place.ox) <= 1e-6 and math.abs(oy - place.oy) <= 1e-6) then
        holder:SetScale(s)
        holder:ClearAllPoints()
        holder:SetPoint("TOPLEFT", host, "TOPLEFT", ox / s, -oy / s)
        place.s, place.ox, place.oy = s, ox, oy
        -- the sea colour: the view, a little more
        local x0, y0 = -ox / s, -oy / s
        local w, h = v.W / s, v.H / s
        seaTex:ClearAllPoints()
        seaTex:SetSize(w * 1.2, h * 1.2)
        seaTex:SetPoint("TOPLEFT", holder, "TOPLEFT", x0 - w * 0.1, -(y0 - h * 0.1))
    end
    if holder.level ~= level then
        ns.SetLevelFixed(holder, level)
        holder.level = level
    end
    if not holder:IsShown() then holder:Show() end
    view.s = s
    view.x0, view.y0 = (cam.x - v.W / 2 / ppx) * W0, (cam.y - v.H / 2 / ppy) * H0
    view.x1, view.y1 = (cam.x + v.W / 2 / ppx) * W0, (cam.y + v.H / 2 / ppy) * H0
end

-- Fog per continent: its alpha now, whether it is built (from FOG_PRE, or where a zoom in is heading there).
local function FogState(cam, v, pfvw, pfx0, pfy0, pfx1, pfy1)
    local flying = ns.Core and ns.Core.State and ns.Core.State() == "fly" -- (1.3.0)
    for m, g in pairs(grids) do
        local cont = ns.maps[g.cont]
        local f, pre = 0, false
        if cont then
            local zc = ns.ZoomOf(v, cont, cam.vw)
            f = ns.Smooth((zc - FOG_C0) / (FOG_C1 - FOG_C0))
            pre = zc >= FOG_PRE
            if not pre and pfvw and cont.x0 < pfx1 and pfx0 < cont.x1 and cont.y0 < pfy1 and pfy0 < cont.y1 then
                pre = ns.ZoomOf(v, cont, pfvw) >= FOG_PRE
            end
        end
        if flying and f <= 0 then pre = false end -- (1.3.0: a flight builds no fog it does not show yet)
        fl[m], fogPre[m] = f, pre
    end
end

-- (Render:Draw, before anything of its own) Returns: the imagery is the map's art this frame, its readiness, busy.
function L:Draw(cam, v, ppx, ppy, host, pfvw, pfx0, pfy0, pfx1, pfy1)
    now = GetTime()
    dt = lastT and math.min(now - lastT, 0.05) or 0
    lastT = now
    lastCam = cam
    if not L:On() then
        if active or (holder and holder:IsShown()) then Off() end
        PinSync(false)
        if ns.Core and ns.Core.State and ns.Core.State() == "rest" then L:RefreshPreview() end
        return false, false, false
    end
    if not Setup(host) then return false, false, false end
    if not pinHooked then PinHook() end
    onSince = onSince or now
    Place(cam, v, ppx, ppy, host)
    -- the level: by physical screen px per ADT tile (both grids nearly the same: the first)
    local g = grids[0] or grids[1]
    local phys = PhysPerUnit(host)
    view.adtPhys = g.bx * view.s * phys
    target = Pick(view.adtPhys, target, view.x0, view.y0, view.x1, view.y1)
    dest = nil
    if pfvw then
        local d = Pick(g.bx * (v.fit0 / pfvw) * phys, target, pfx0 * W0, pfy0 * H0, pfx1 * W0, pfy1 * H0)
        if d ~= target then dest = d end
    end
    FogState(cam, v, pfvw, pfx0, pfy0, pfx1, pfy1)
    local clientA = levels[4].live and levels[4].a or 0
    for m in pairs(grids) do seaA[m] = math.max(fl[m] or 0, clientA) end
    EnsureWindow(levels[1], view.x0, view.y0, view.x1, view.y1)
    EnsureFogWindow(view.x0, view.y0, view.x1, view.y1)
    EnsureWindow(levels[target], view.x0, view.y0, view.x1, view.y1)
    if dest then EnsureWindow(levels[dest], pfx0 * W0, pfy0 * H0, pfx1 * W0, pfy1 * H0) end
    -- (the target's copies and the sea first: what the caps hold back goes to the levels it replaces)
    copyBudget, copiesShort = COPY_BUDGET, false
    if target > 1 then BuildCopies(levels[target]) end
    BuildSea()
    for i = 2, 4 do
        local lev = levels[i]
        if lev.live and i ~= target and (i == dest or lev.a > 0) then BuildCopies(lev) end
    end
    -- levels: the target fades in; a finer one the zoom left fades out once the target covers the view, a coarser one
    -- goes then; the one a zoom heads for waits hidden
    local tl = levels[target]
    levels[1].a = 1 -- (the backdrop)
    tl.a = math.min(1, tl.a + (active and dt / LEVEL_FADE or 1))
    local covered, backdrop, whole = Alphas()
    local busy = next(pending) ~= nil or next(fading) ~= nil or tl.a < 1 or copiesShort -- (1.3.0: copies still to make)
    for i = 2, 4 do
        local lev = levels[i]
        if lev.live and i ~= target then
            if i > target and covered and i ~= dest then
                lev.a = math.max(0, lev.a - dt / LEVEL_FADE)
                if lev.a <= 0 then ReleaseLevel(lev) end
                busy = true -- (fading; or released: one more frame for the sea's alpha without it and what the caps held back)
            elseif i < target and covered and i ~= dest then
                ReleaseLevel(lev)
                busy = true
            elseif i ~= dest then
                busy = true
            end
        end
    end
    if not active and (whole or now - onSince >= LOAD_TIMEOUT) then
        active = true
        holder:SetAlpha(1)
        if ns.Render then ns.Render:MarkArtDirty() end
        if ns.Labels and ns.Labels.AddSubzones then ns.Labels:AddSubzones() end
        L:RefreshPreview(true)
    elseif not active then
        busy = true
    end
    PinSync(active)
    if active and ns.Core and ns.Core.State and ns.Core.State() == "rest" then L:RefreshPreview() end
    return active, active and backdrop, busy
end

---------------------------------------------------------------------------
-- Following Render
---------------------------------------------------------------------------
-- (exploration changed: the copies are rebuilt - those that stay keep their textures)
hooksecurefunc(ns.Render, "MarkArtDirty", function()
    fogGen = fogGen + 1
    wipe(tilesOf)
    wipe(setOf)
end)
hooksecurefunc(ns.Render, "HideAll", function() L:Hide() end)
hooksecurefunc(ns.Render, "ReleaseAll", function()
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then
        L:Release()
        active, onSince = false, nil
        if holder then holder:SetAlpha(0) end
    end
end)

-- (/unroll zoom) the readout's line
function L:ZoomLines(out)
    if not L:On() then return end
    local t = target and levels[target]
    if not (t and view.adtPhys) then return end
    local what = t.i == 4 and "the game's own minimap tiles" or ("composite %d px per tile"):format(t.px)
    out[#out + 1] = ("Minimap imagery: %s, %.2f texels per screen pixel; fog %.2f / %.2f (%s)"):format(what,
        t.px / view.adtPhys, fl[0] or 0, fl[1] or 0,
        L:TilesOn() and ("client tiles from %.1f"):format(CLIENT_IN) or "client tiles off: /unroll imagerytiles")
end

-- (tests, /unroll debug) counts
function L:Stats()
    local s = { made = nTex, masks = nMask, skipped = nSkipped, target = target, dest = dest, active = active,
        adtPhys = view.adtPhys, fog = { fl[0], fl[1] }, sea = 0, levels = {}, live = 0, masksLive = 0 }
    for _ in pairs(seaQ) do s.sea = s.sea + 1 end
    s.seaRects = 0
    for _ in pairs(seaR) do s.seaRects = s.seaRects + 1 end
    for _ in pairs(masks) do s.masksLive = s.masksLive + 1 end
    for i = 1, 4 do
        local lev, nb, nc = levels[i], 0, 0
        for _ in pairs(lev.tex) do nb = nb + 1 end
        for _ in pairs(lev.copies) do nc = nc + 1 end
        s.levels[i] = { live = lev.live == true, a = lev.a, base = nb, copies = nc }
        s.live = s.live + nb + nc
    end
    s.live = s.live + s.sea + s.seaRects
    return s
end
L.T = { levels = levels, masks = masks, seaQ = seaQ, seaR = seaR, view = view, cap = cap } -- (tests: read only, but the caps)
function L:Holder() return holder, seaTex end
function L:Grid(m) return Grids() and grids[m] end

