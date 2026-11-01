local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)

--[[
Gilneas (1.3.1): the land south of Silverpine Forest and the Greymane Wall. WoW Forever has its terrain and its names
(AreaTable: Gilneas, Ruins of Gilneas, Gilneas City ...) but Blizzard ships no map of it - no UiMap, no map art - so the
drawn map showed only the Eastern Kingdoms' continent picture there, blurry wherever zone pictures show. The user: "we
also still don't show the zone under silver pine forest on the illustrated map even though it is in the game now."

The add-on draws its own page there: one picture of 3 x 3 pictures of 256 px (Media\Gilneas, DXT1 BLP2 with mips - the
one picture format proven in this client) drawn by tools/gilneas/build_gilneas.py from the client's terrain in the manner
of the zone maps beside it, cut by one mask (Masks\gilneas.tga: whole on Gilneas's land, fading out over the sea round
it and just north of the wall, where Silverpine's own picture takes over). GilneasData.lua (generated) places it.

  * (1.3.1: the fog of war) Two looks, as a zone map has (the user, after 1.3.1-beta2 on a new character: "we just need
    the illustrated fog of war back in"): the UNEXPLORED look (upages: Blizzard's unexplored base - parchment, inked
    coast, ranges, water; no wash, road, town or house) is drawn whole through the mask (Masks\gilneas.tga: the
    page's opacity, but over Silverpine's land north of the wall only at the wall itself - (1.3.1 review) there
    Silverpine's own art shows, with its own fog of war); the EXPLORED look (pages: the page above) only over the
    areas you have explored, one piece per area of Gilneas that covers land (D.areas: Gilneas, Gilneas City,
    Shark-Infested Waters' islets, The Greymane Wall south of the wall - and (1.3.1 review) the page's fade over
    Silverpine's land north of it, so an explored wall shows the page there as 1.3.1-beta2 did -, Ruins of Gilneas,
    the Northern Headlands - each its own soft-edged mask, Masks\gilneas_<areaID>.tga, over its rect of the page):
    the explored page's pictures that the rect crosses, each cut to it (CLAMP) and through that mask, stacked over
    the unexplored look - a union, as Blizzard's explored pieces (one mask a texture: masks on one texture would
    intersect). Each area turns to colour on its own; every area explored, the page is 1.3.1-beta2's. (1.3.1 review)
    Only the explored pieces follow the page while the map moves (Place): a hidden one is placed when it turns on.
    What is explored, for this character (Recompute, after MarkArtDirty, a new character or a discovery):
      - the game's own record where a Blizzard map has a piece of the same area (A.game: Silverpine Forest's "The
        Greymane Wall" - C_MapExplorationInfo.GetExploredMapTextures, as Render's ExploredList reads it),
      - what C_MapExplorationInfo.GetExploredAreaIDsAtPosition answers at a point of each area's land on the Eastern
        Kingdoms' map (1415) and the world map (947) - not verified in game for Gilneas (it may well answer nothing:
        neither map has explored areas of its own there),
      - the add-on's own record (AzerothUnrolledDB.gilneasExplored[the character's GUID][areaID] = true): on
        PLAYER_ENTERING_WORLD, ZONE_CHANGED, ZONE_CHANGED_INDOORS and ZONE_CHANGED_NEW_AREA (no timer, nothing per
        frame: one look at where you are), the area of the terrain chunk you stand in (UnitPosition, map 0: the data's
        chunk grid), and the names the game gives where you are (GetSubZoneText, GetMinimapZoneText, and with no
        sub-zone GetRealZoneText: an area's own name, in the client's language - C_Map.GetAreaInfo - or enUS) while
        that position is inside the page, or with no position outdoors. A new area is saved and shown at once: Core's ExplorationChanged - the
        MAP_EXPLORATION_UPDATED path (Render:MarkArtDirty, a redraw at rest); its pictures are loaded with the page's,
        so it shows without a blink. Another character has its own record: parchment until they have been there.
    With the mosaic off (/unroll mosaic) the unexplored look hides, as every zone's unexplored land does (Render's
    footA); the explored pieces stay (Render's pieceA). The minimap imagery's fog (MinimapLayer.lua MaskTiles) greys
    Gilneas's land as anywhere else and lights the explored areas' pieces (G:FogTiles: one mask tile per explored
    piece). The names: the zone's always, a sub-zone's (Gilneas City) only while its area is explored (Labels.lua, as
    MINIMAP_SUBZONES' names).
  * When: as the zone pictures do - it fades in while the Eastern Kingdoms' continent zoom goes from Render's LOD_C0 to
    LOD_C1 (2.5 to 4: where the zone cells come in) and stays at every deeper zoom; built and loaded ahead from
    LOD_PREFETCH within a screen of the view, or (1.3.1 review) where a zoom in is heading (Render's prefetch rect, as
    its cells), then faded in once loaded (both looks and every piece). Not while the minimap imagery shows (its own
    pictures have the terrain), not over Kalimdor, not outside WoW Forever (Classic Era has no Gilneas).
  * Where in the stack: on the city layer's own level (Core's clipping frame above Blizzard's map art pins - over a zone
    map just above its explored areas): the page lies over every zone cell, explored piece and picture of the overlay
    - Silverpine's old drawing of the land south of the wall, its explored "Greymane Wall" piece, which Blizzard's
    canvas draws itself at rest over our band - and under every picture the city layer lifts (its frames' levels are
    above their parent's own regions), every pin and every name; the explored pieces one sublevel over the unexplored
    look.
    (1.3.1 review) While the map moves detached (the canvas hidden: livepins off, or no map can show the view) the
    city layer holds no frame - Render lifts its city and detail maps into it at rest and in the live canvas only - so
    a city or detail map over the page would show above it at rest and fall under it moving: a cave in Gilneas's north
    (-50111, Caves.lua) does, from its switch. Detached, the page is therefore a second copy of it on a frame of its own
    in the overlay, at the level Render keeps for it (Render.pageLevel, PicTops: just under the first city or detail
    map's, where the lift starts at rest) - above every zone part, under every city and detail map, as at rest; the
    copy on the city layer is hidden meanwhile. Both copies share the files (one load).
  * Names (Labels.lua): "Gilneas" as a zone's name and its sub-zones (Gilneas City) at zone zoom, in the bands the
    minimap imagery's names use (the page prints no names), shown over the drawn map and the imagery alike.
  * The zone as a map (G:Zone): an entry with a zone map's rect (3:2 round its land) that is no uiMap: never passed to
    SetMapID or C_Map. ns.DeepestMapAt counts it (Util.lua), so the wheel goes as deep over Gilneas as over any zone
    (maxZoom past its fit) - before, only the continent's depth: Gilneas was a quarter of the view at the deepest. A
    click on it does nothing of its own: Blizzard's canvas has no map there, so its click handler switches nowhere.
  * (1.3.1 review) Where the page shows (G:Covers: the data's coarse cover grid, its mask whole to half) the layer
    button's preview of the drawn map is the page's own picture - the unexplored look, as the zones' previews show
    their base (G:PreviewAt, MinimapLayer.lua PreviewOf) - and a party bubble's box names Gilneas where the game knows
    only the continent (G:ZoneAt, PartyBubbles.lua ZoneOf).
At rest nothing here runs: Render draws only while the map moves or art fades in, and a frame with the same view, alpha
and explored areas calls no widget method; the zone events do one quick look at where you are.
]]

local G = {}
ns.Gilneas = G

local D = ns.GILNEAS
local EK = 1415                                -- the Eastern Kingdoms (uiMap)
local LOAD_FADE, LOAD_TIMEOUT = 0.15, 2        -- the page fades in over this once loaded (after the timeout anyway)
local API_MAPS = { EK, 947 }                   -- (1.3.1: the fog of war) GetExploredAreaIDsAtPosition asked on these
local host, anchor                             -- the city layer (the page's textures are its own regions), the overlay
-- (1.3.1 review) the page's two copies: [1] the city layer's own regions (at rest, in the live canvas), [2] a frame of
-- its own in the overlay (detached); each { host, u = { 9 textures: the unexplored look }, mask = the page's mask,
-- pieces = { [k] = { mask, tex = { textures: the explored look over area k } } }, all = every texture and mask (load),
-- place = what was set, a = alpha shown (nil: hidden), uOn = the unexplored look shown, on = { [k] = piece k shown } }
local sets = { { u = {}, pieces = {}, all = {}, place = {}, on = {} }, { u = {}, pieces = {}, all = {}, place = {}, on = {} } }
local mframe                                   -- [2]'s frame (its level: Render.pageLevel)
local filesSet, loadedAt, setAt = false, nil, nil
local page, zoneE                              -- the page's rect on the world map; the zone as a map entry
local wants = false                            -- (Render's PicTops) on screen and in its zooms in the last draw
local stats = { draws = 0, placed = 0, recomputed = 0, discovered = 0, events = 0 }
-- (1.3.1: the fog of war) what is explored: explored[k] (piece k), exploredAr[areaID]; worked out again when dirty
local explored, exploredAr, dirty = {}, {}, true
local cuts                                     -- [k] = the explored page's pictures over piece k: { i, x0, y0, x1, y1 }
local session = {}                             -- [areaID] = true: discovered with no character to save it under

-- (1.4.0: ns.FLAVOR, OneCopy.lua - before 1.4.0 the interface number here, 16000 - 19999) WoW Forever only
function G:Supported()
    return ns.FLAVOR == "forever" and D ~= nil and D.r ~= nil
end

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
local function Num(v) return type(v) == "number" and not Secret(v) end
local function Str(v) return type(v) == "string" and not Secret(v) and v ~= "" end

-- The client's name of an area (C_Map.GetAreaInfo), else nil.
local function AreaName(ar)
    if not (C_Map and C_Map.GetAreaInfo) then return nil end
    local ok, loc = pcall(C_Map.GetAreaInfo, ar)
    if ok and Str(loc) then return loc end
end

-- The page's and the zone's rects on the world map (ns.WorldPosToMap of their corners: the map is affine on a continent).
local function Rect(r)
    local x0, y0 = ns.WorldPosToMap(D.m, r[3], r[4])
    local x1, y1 = ns.WorldPosToMap(D.m, r[1], r[2])
    if not (x0 and x1 and x1 > x0 and y1 > y0) then return nil end
    return { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
end

local function Setup()
    if page then return true end
    if page == false or not G:Supported() or not (ns.maps and ns.maps[EK] and ns.WorldPosToMap) then return false end
    page = Rect(D.r) or false
    local z = Rect(D.zone)
    if not (page and z) then
        page = false
        return false
    end
    -- (a zone map's entry, no uiMap: the id is negative - as a detail level's - and the art size a zone map's)
    z.id, z.name, z.virtual, z.mapType, z.parent = -D.name.ar, AreaName(D.name.ar) or D.name.n, true, ns.MAPTYPE_ZONE, EK
    z.cx, z.cy, z.lw, z.lh, z.nest, z.ky = (z.x0 + z.x1) / 2, (z.y0 + z.y1) / 2, 1002, 668, 0, 1
    z.area = (z.x1 - z.x0) * (z.y1 - z.y0)
    zoneE = z
    ns.extraZones = ns.extraZones or {}
    ns.extraZones[#ns.extraZones + 1] = z
    return true
end

-- The zone as a map entry (labels' owner, the depth limit), nil where there is no Gilneas.
function G:Zone()
    if Setup() then return zoneE end
end

---------------------------------------------------------------------------
-- (1.3.1: the fog of war) What is explored, for this character
---------------------------------------------------------------------------
-- The character's GUID (the record's key), nil when the game gives none.
local function Me()
    if not UnitGUID then return nil end
    local ok, g = pcall(UnitGUID, "player")
    if ok and Str(g) then return g end
end

-- This character's record { [areaID] = true } in the saved settings; create: made when missing (else nil then).
local function Record(create)
    local db, me = ns.db, Me()
    if not (db and me) then return nil end
    local all = db.gilneasExplored
    if type(all) ~= "table" then
        if not create then return nil end
        all = {}
        db.gilneasExplored = all
    end
    local r = all[me]
    if type(r) ~= "table" then
        if not create then return nil end
        r = {}
        all[me] = r
    end
    return r
end

-- Is the explored piece g = { uiMapID, offsetX, offsetY, width, height } of a Blizzard map explored (the game's record)?
-- lists: the maps' explored pieces read in this pass.
local function GamePiece(g, lists)
    local list = lists[g[1]]
    if list == nil then
        list = false
        local f = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures
        if f then
            local ok, res = pcall(f, g[1])
            if ok and type(res) == "table" and not Secret(res) then list = res end
        end
        lists[g[1]] = list
    end
    if not list then return false end
    for _, info in ipairs(list) do
        if type(info) == "table" and not Secret(info) and not Secret(info.isShownByMouseOver)
            and info.isShownByMouseOver ~= true and Num(info.offsetX) and Num(info.offsetY) and Num(info.textureWidth)
            and Num(info.textureHeight) and info.offsetX == g[2] and info.offsetY == g[3] and info.textureWidth == g[4]
            and info.textureHeight == g[5] then
            return true
        end
    end
    return false
end

-- The areas GetExploredAreaIDsAtPosition says are explored at a point of each area's land (on the Eastern Kingdoms' map
-- and the world map): { [areaID] = true }.
local function ApiAreas()
    local out = {}
    local f = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredAreaIDsAtPosition
    local cont = ns.maps and ns.maps[EK]
    if not (f and CreateVector2D and ns.WorldPosToMap) then return out end
    for _, A in ipairs(D.areas) do
        local x, y = ns.WorldPosToMap(D.m, A.at[1], A.at[2])
        for _, m in ipairs(x and API_MAPS or {}) do
            local u, v = x, y
            if m == EK then
                u = cont and (x - cont.x0) / (cont.x1 - cont.x0)
                v = cont and (y - cont.y0) / (cont.y1 - cont.y0)
            end
            local ok, ids = false, nil
            if u then ok, ids = pcall(f, m, CreateVector2D(u, v)) end
            if ok and type(ids) == "table" and not Secret(ids) then
                for _, id in ipairs(ids) do
                    if Num(id) then out[id] = true end
                end
            end
        end
    end
    return out
end

local function Recompute()
    dirty = false
    stats.recomputed = stats.recomputed + 1
    wipe(exploredAr)
    if not (D and D.areas) then return end
    local rec = Record(false) or (Me() == nil and session) or nil
    local api, lists = ApiAreas(), {}
    for k, A in ipairs(D.areas) do
        local on = (rec ~= nil and rec[A.ar] == true) or api[A.ar] == true or (A.game ~= nil and GamePiece(A.game, lists))
        explored[k] = on and true or false
        if on then exploredAr[A.ar] = true end
    end
end

-- Is area ar (an AreaTable ID of D.areas) explored for this character? (Labels.lua: a sub-zone's name)
function G:Explored(ar)
    if dirty then Recompute() end
    return exploredAr[ar] == true
end

-- The piece (index into D.areas) whose area holds the terrain chunk at world (X north, Y west), else nil.
local gridRows = {}
local function AreaAt(X, Y)
    local g = D.grid
    local r, c = math.floor((g.x - X) / g.s), math.floor((g.y - Y) / g.s)
    if r < 0 or c < 0 or c >= g.n or r >= #g.rows then return nil end
    local row = gridRows[r + 1]
    if not row then
        row = {}
        for cnt, ch in g.rows[r + 1]:gmatch("(%d+)(%a)") do
            local v = ch:byte() - 97
            for _ = 1, tonumber(cnt) do row[#row + 1] = v end
        end
        gridRows[r + 1] = row
    end
    local v = row[c + 1]
    if v and v > 0 then return v end
end

-- The areas by their names: enUS and the client's (C_Map.GetAreaInfo).
local byName
local function NameIndex()
    if byName then return byName end
    byName = {}
    for k, A in ipairs(D.areas) do
        byName[A.n] = byName[A.n] or k
        local loc = AreaName(A.ar)
        if loc then byName[loc] = byName[loc] or k end
    end
    return byName
end

local function InInstance()
    if not IsInInstance then return false end
    local ok, inside = pcall(IsInInstance)
    return ok and not Secret(inside) and inside == true
end

-- One of the game's zone texts, trimmed (nil when none).
local function Text(fn)
    local f = _G[fn]
    local ok, s = false, nil
    if f then ok, s = pcall(f) end
    s = ok and Str(s) and (s:gsub("^%s+", ""):gsub("%s+$", "")) or nil
    if s ~= "" then return s end
end

-- The game's names of the area you are in: the sub-zone's and the minimap's, and only with no sub-zone the zone's (you
-- are in the zone-level area's own land) - as the chunk's area: in Gilneas City the zone is Ruins of Gilneas, but you
-- are in Gilneas City, not on the ruins' own land.
local function Texts()
    local sub = Text("GetSubZoneText")
    return { sub, Text("GetMinimapZoneText"), not sub and Text("GetRealZoneText") or nil }
end

-- Exploration changed: shown at once (Core.lua: the MAP_EXPLORATION_UPDATED path - a redraw at rest).
local function Changed()
    local C = ns.Core
    if C and C.ExplorationChanged then
        C.ExplorationChanged()
    elseif ns.Render then
        ns.Render:MarkArtDirty()
    end
end

-- A zone event: where you are now - the chunk's area and the names the game gives - marked explored for this character.
local function Discover()
    stats.events = stats.events + 1
    if not (D and D.areas and D.grid) then return end
    local hit, inside, havePos = nil, false, false
    if UnitPosition then
        local ok, x, y, _, inst = pcall(UnitPosition, "player")
        if ok and Num(x) and Num(y) and Num(inst) then
            havePos = true
            if inst == D.m and x >= D.r[1] and x <= D.r[3] and y >= D.r[2] and y <= D.r[4] then
                inside = true
                local k = AreaAt(x, y)
                if k then hit = { [k] = true } end
            end
        end
    end
    -- (the names only inside the page, or with no position outdoors: another place may share a name)
    if inside or (not havePos and not InInstance()) then
        local idx, t = NameIndex(), Texts()
        for i = 1, 3 do
            local k = t[i] and idx[t[i]]
            if k then
                hit = hit or {}
                hit[k] = true
            end
        end
    end
    if not hit then return end
    local rec = Record(true) or (Me() == nil and session) or nil
    local new = false
    for k in pairs(hit) do
        local ar = D.areas[k].ar
        if rec and rec[ar] ~= true then
            rec[ar], new = true, true
        end
    end
    if new then
        stats.discovered = stats.discovered + 1
        dirty = true
        Changed()
    end
end

---------------------------------------------------------------------------
-- Where the page shows
---------------------------------------------------------------------------
-- (1.3.1 review) Does the page show at world-map point (x, y)? The data's cover grid (D.cover: n x n cells over the
-- page, row by row from the north-west, each row hex digits of 4 cells, west first): its mask whole to half there.
local cover
function G:Covers(x, y)
    if not (Setup() and D.cover) then return false end
    local n = D.cover.n
    if not cover then
        cover = {}
        for r, s in ipairs(D.cover) do
            for c = 0, n - 1 do
                local k = math.floor(c / 4)
                local digit = tonumber(s:sub(k + 1, k + 1), 16) or 0
                cover[(r - 1) * n + c] = math.floor(digit / 2 ^ (3 - c % 4)) % 2 == 1
            end
        end
    end
    local u, w = (x - page.x0) / (page.x1 - page.x0), (y - page.y0) / (page.y1 - page.y0)
    if u < 0 or u >= 1 or w < 0 or w >= 1 then return false end
    return cover[math.floor(w * n) * n + math.floor(u * n)] == true
end

-- (1.3.1 review) The zone entry where the page shows, else nil (PartyBubbles.lua: where the game knows only the
-- continent).
function G:ZoneAt(x, y)
    if G:Covers(x, y) then return zoneE end
end

-- (1.3.1 review) The layer button's preview of the drawn map (MinimapLayer.lua PreviewOf) where the page shows: its
-- picture there and a quarter of it round the point (as the art tiles') - file, left, right, top, bottom; else nil.
-- (1.3.1: the fog of war) the unexplored look's picture, as a zone's preview is its base picture.
function G:PreviewAt(x, y)
    if not G:Covers(x, y) then return nil end
    local list = D.upages or D.pages
    local n = math.floor(math.sqrt(#list) + 0.5)
    local px = (x - page.x0) / (page.x1 - page.x0) * D.size
    local py = (y - page.y0) / (page.y1 - page.y0) * D.size
    local tw = D.tile
    local tc, tr = math.min(n - 1, math.floor(px / tw)), math.min(n - 1, math.floor(py / tw))
    local s = tw / 2
    local l = ns.Clamp(px - tc * tw - s / 2, 0, tw - s)
    local t = ns.Clamp(py - tr * tw - s / 2, 0, tw - s)
    return D.path .. list[tr * n + tc + 1] .. ".blp", l / tw, (l + s) / tw, t / tw, (t + s) / tw
end

-- (1.3.1: the fog of war) The minimap imagery's fog of war (MinimapLayer.lua MaskTiles): a mask tile in its terms for
-- every explored area's piece - its mask placed over the piece's rect in the world map's art px (w0 x h0) - appended to
-- out where it meets world-map px rect (x0, y0, x1, y1), so Gilneas's explored areas are lit and the rest greys, as
-- everywhere; nothing off the Eastern Kingdoms.
local fogTiles
function G:FogTiles(cont, w0, h0, x0, y0, x1, y1, out)
    if cont ~= EK or not (Setup() and D.areas) then return end
    if dirty then Recompute() end
    if not (fogTiles and fogTiles.w0 == w0 and fogTiles.h0 == h0) then
        fogTiles = { w0 = w0, h0 = h0 }
        local pw, ph = (page.x1 - page.x0) * w0 / D.size, (page.y1 - page.y0) * h0 / D.size
        for k, A in ipairs(D.areas) do
            local p = A.px
            local mx, my = page.x0 * w0 + p[1] * pw, page.y0 * h0 + p[2] * ph
            local mw, mh = (p[3] - p[1]) * pw, (p[4] - p[2]) * ph
            fogTiles[k] = { key = "gilneas:" .. A.ar, file = D.mpath .. A.mask .. ".tga", mx = mx, my = my, mw = mw,
                mh = mh, ux0 = mx, uy0 = my, ux1 = mx + mw, uy1 = my + mh }
        end
    end
    for k, T in ipairs(fogTiles) do
        if explored[k] and T.ux0 < x1 and T.ux1 > x0 and T.uy0 < y1 and T.uy1 > y0 then out[#out + 1] = T end
    end
end

---------------------------------------------------------------------------
-- The page's textures: the city layer's own regions, and (1.3.1 review) a copy for the map moving detached
---------------------------------------------------------------------------
-- (1.3.1: the fog of war) the explored page's pictures over each piece's rect: { i = the picture, x0, y0, x1, y1 } (page
-- px), the part of picture i inside the rect
local function Cuts()
    if cuts then return cuts end
    cuts = {}
    local tw = D.tile
    local n = math.floor(math.sqrt(#D.pages) + 0.5)
    for k, A in ipairs(D.areas or {}) do
        local p, list = A.px, {}
        for r = 0, n - 1 do
            for c = 0, n - 1 do
                local x0, y0 = math.max(p[1], c * tw), math.max(p[2], r * tw)
                local x1, y1 = math.min(p[3], (c + 1) * tw), math.min(p[4], (r + 1) * tw)
                if x1 > x0 and y1 > y0 then list[#list + 1] = { i = r * n + c + 1, x0 = x0, y0 = y0, x1 = x1, y1 = y1 } end
            end
        end
        cuts[k] = list
    end
    return cuts
end

-- (1.3.1 review) the two copies' widgets, made once: [1] on the city layer, [2] on a frame of its own in the overlay
local function Make()
    if sets[1].mask or not (host and anchor) then return end
    mframe = CreateFrame("Frame", nil, anchor)
    mframe:SetAllPoints(anchor)
    mframe:EnableMouse(false)
    sets[1].host, sets[2].host = host, mframe
    for _, s in ipairs(sets) do
        s.mask = s.host:CreateMaskTexture()
        s.mask:Hide()
        s.all[#s.all + 1] = s.mask
        for i = 1, #(D.upages or D.pages) do
            local t = s.host:CreateTexture(nil, "BACKGROUND", nil, 0)
            t:Hide()
            s.u[i] = t
            s.all[#s.all + 1] = t
        end
        -- (1.3.1: the fog of war) the explored pieces, a sublevel over the unexplored look
        for k, list in ipairs(Cuts()) do
            local P = { mask = s.host:CreateMaskTexture(), tex = {} }
            P.mask:Hide()
            s.all[#s.all + 1] = P.mask
            for j = 1, #list do
                local t = s.host:CreateTexture(nil, "BACKGROUND", nil, 1)
                t:Hide()
                P.tex[j] = t
                s.all[#s.all + 1] = t
            end
            s.pieces[k] = P
            s.on[k] = false
        end
        s.uOn = false
    end
end

local function SetFiles()
    if filesSet then return end
    Make()
    local tw = D.tile
    local n = math.floor(math.sqrt(#D.pages) + 0.5)
    for _, s in ipairs(sets) do
        -- (Blizzard's order, MapCanvasMixin:SetMaskTexture: the mask's file first, then the textures take it)
        s.mask:SetTexture(D.mask, "CLAMP", "CLAMP", "TRILINEAR")
        for i, t in ipairs(s.u) do
            t:SetTexture(D.path .. (D.upages or D.pages)[i] .. ".blp", "CLAMP", "CLAMP", "TRILINEAR")
            t:SetTexCoord(0, 1, 0, 1)
            t:AddMaskTexture(s.mask)
        end
        for k, P in ipairs(s.pieces) do
            P.mask:SetTexture(D.mpath .. D.areas[k].mask .. ".tga", "CLAMP", "CLAMP", "TRILINEAR")
            for j, t in ipairs(P.tex) do
                local q = cuts[k][j]
                local r, c = math.floor((q.i - 1) / n), (q.i - 1) % n
                t:SetTexture(D.path .. D.pages[q.i] .. ".blp", "CLAMP", "CLAMP", "TRILINEAR")
                t:SetTexCoord((q.x0 - c * tw) / tw, (q.x1 - c * tw) / tw, (q.y0 - r * tw) / tw, (q.y1 - r * tw) / tw)
                t:AddMaskTexture(P.mask)
            end
        end
    end
    filesSet, loadedAt, setAt = true, nil, GetTime()
end

-- One copy hidden: no widget call when it is hidden already.
local function HideSet(s)
    if s.a == nil then return end
    s.a = nil
    wipe(s.place)
    if s.uOn then
        s.mask:Hide()
        for _, t in ipairs(s.u) do t:Hide() end
    end
    s.uOn = false
    for k, P in ipairs(s.pieces) do
        if s.on[k] then
            P.mask:Hide()
            for _, t in ipairs(P.tex) do t:Hide() end
        end
        s.on[k] = false
    end
end

-- Everything hidden (the map closed, the imagery on, out of view ...).
function G:Hide()
    for _, s in ipairs(sets) do HideSet(s) end
end

-- The files let go (the map closed for a while: Render:ReleaseAll).
function G:Release()
    G:Hide()
    if not filesSet then return end
    for _, s in ipairs(sets) do
        for _, t in ipairs(s.u) do
            t:RemoveMaskTexture(s.mask)
            t:SetTexture(nil)
        end
        s.mask:SetTexture(nil)
        for _, P in ipairs(s.pieces) do
            for _, t in ipairs(P.tex) do
                t:RemoveMaskTexture(P.mask)
                t:SetTexture(nil)
            end
            P.mask:SetTexture(nil)
        end
    end
    filesSet, loadedAt, setAt = false, nil, nil
end

-- (every picture and mask of both looks loaded - a piece explored later shows at once - or the timeout)
local function LoadFade(now, s)
    if not loadedAt then
        local ok = now - (setAt or now) >= LOAD_TIMEOUT
        if not ok then
            ok = true
            for _, t in ipairs(s.all) do
                if ok and t.IsObjectLoaded and not t:IsObjectLoaded() then ok = false end
            end
        end
        if not ok then return 0 end
        loadedAt = now
    end
    return ns.Smooth((now - loadedAt) / LOAD_FADE)
end

-- (1.3.1: the fog of war) piece k of copy s placed where s is (s.place): its mask over its rect, its pictures over
-- their parts of it (page px -> screen); P.ver = the placement it has (s.ver)
local function PlacePiece(s, k, P)
    local place = s.place
    local sx0, sy0, kx, ky = place.sx0, place.sy0, place.w / D.size, place.h / D.size
    local p = D.areas[k].px
    P.mask:ClearAllPoints()
    P.mask:SetPoint("TOPLEFT", anchor, "TOPLEFT", sx0 + p[1] * kx, -(sy0 + p[2] * ky))
    P.mask:SetSize((p[3] - p[1]) * kx, (p[4] - p[2]) * ky)
    for j, t in ipairs(P.tex) do
        local q = cuts[k][j]
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", anchor, "TOPLEFT", sx0 + q.x0 * kx, -(sy0 + q.y0 * ky))
        t:SetSize((q.x1 - q.x0) * kx, (q.y1 - q.y0) * ky)
    end
    P.ver = s.ver
end

-- Copy s placed: the page's top-left (sx0, sy0) and size (w, h) in the overlay's px.
local function Place(s, sx0, sy0, w, h)
    local place = s.place
    if not (place.sx0 == sx0 and place.sy0 == sy0 and place.w == w and place.h == h) then
        place.sx0, place.sy0, place.w, place.h = sx0, sy0, w, h
        s.ver = (s.ver or 0) + 1
        stats.placed = stats.placed + 1
        local n = math.floor(math.sqrt(#s.u) + 0.5)
        local tw, th = w / n, h / n
        s.mask:ClearAllPoints()
        s.mask:SetPoint("TOPLEFT", anchor, "TOPLEFT", sx0, -sy0)
        s.mask:SetSize(w, h)
        for i, t in ipairs(s.u) do
            local r, c = math.floor((i - 1) / n), (i - 1) % n
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", anchor, "TOPLEFT", sx0 + c * tw, -(sy0 + r * th))
            t:SetSize(tw, th)
        end
    end
    -- (1.3.1: the fog of war; review) only the explored pieces - the ones ShowSet shows next - follow the page: a hidden
    -- piece costs nothing while the map moves, and is placed when it turns on (its placement older than the page's)
    for k, P in ipairs(s.pieces) do
        if explored[k] and P.ver ~= s.ver then PlacePiece(s, k, P) end
    end
end

-- Copy s shown at alpha a: the unexplored look while uOn (the mosaic), each explored area's piece. Only what changed.
local function ShowSet(s, a, uOn)
    local same = s.a == a
    if s.uOn ~= uOn then
        s.uOn = uOn
        if uOn then s.mask:Show() else s.mask:Hide() end
        for _, t in ipairs(s.u) do
            if uOn then
                t:SetAlpha(a)
                t:Show()
            else
                t:Hide()
            end
        end
    elseif uOn and not same then
        for _, t in ipairs(s.u) do t:SetAlpha(a) end
    end
    for k, P in ipairs(s.pieces) do
        local on = explored[k] == true
        if s.on[k] ~= on then
            s.on[k] = on
            if on then P.mask:Show() else P.mask:Hide() end
            for _, t in ipairs(P.tex) do
                if on then
                    t:SetAlpha(a)
                    t:Show()
                else
                    t:Hide()
                end
            end
        elseif on and not same then
            for _, t in ipairs(P.tex) do t:SetAlpha(a) end
        end
    end
    s.a = a
end

-- (1.3.1 review, Render's PicTops) Is the page on screen and in its zooms (last draw)? Detached it gets a level then.
function G:Wants() return wants end
-- Is a copy of the page shown?
function G:Shown() return sets[1].a ~= nil or sets[2].a ~= nil end

---------------------------------------------------------------------------
-- Per frame (Render:Draw, after its levels are planned): returns true while the page is still fading in
---------------------------------------------------------------------------
-- (pfvw, pfx0 .. pfy1: Render's prefetch - the view a zoom in is heading to, its rect on the world map - or nil)
function G:Draw(cam, v, ppx, ppy, mm, pfvw, pfx0, pfy0, pfx1, pfy1)
    stats.draws = stats.draws + 1
    wants = false
    if not (host and anchor and Setup()) then return false end
    local R, cont = ns.Render, ns.maps[EK]
    local cf = R:GetContinentFocus()
    if mm or not cont or (cf ~= nil and cf ~= EK) then
        G:Hide()
        return false
    end
    if dirty then Recompute() end -- (1.3.1: the fog of war)
    local W, H = v.W, v.H
    local sx0, sy0 = W / 2 + (page.x0 - cam.x) * ppx, H / 2 + (page.y0 - cam.y) * ppy
    local sx1, sy1 = W / 2 + (page.x1 - cam.x) * ppx, H / 2 + (page.y1 - cam.y) * ppy
    local zc = ns.ZoomOf(v, cont, cam.vw)
    local target = ns.Smooth((zc - R.LOD_C0) / (R.LOD_C1 - R.LOD_C0))
    local onScreen = sx1 > 0 and sx0 < W and sy1 > 0 and sy0 < H
    local near = sx1 > -W and sx0 < 2 * W and sy1 > -H and sy0 < 2 * H
    -- (1.3.1 review) loaded ahead within a screen of the view from LOD_PREFETCH, and where a zoom in is heading (the
    -- prefetch rect over the page, at LOD_PREFETCH there: Render's Consider loads its cells the same way)
    local heading = pfvw ~= nil and pfx0 ~= nil and page.x0 < pfx1 and pfx0 < page.x1 and page.y0 < pfy1
        and pfy0 < page.y1 and ns.ZoomOf(v, cont, pfvw) >= R.LOD_PREFETCH
    if heading or (near and (target > 0.002 or zc >= R.LOD_PREFETCH)) then SetFiles() end
    wants = onScreen and target > 0.002
    -- (1.3.1 review) which copy: detached, the overlay's at the level Render planned for it (none yet - the first
    -- frame it would show in: hidden and drawn again, the next one has it), else the city layer's
    local s, lvl = sets[1], nil
    if R.pageDetached then
        s, lvl = sets[2], R.pageLevel
        if not lvl then
            G:Hide()
            return wants and filesSet
        end
    end
    local a, fade = 0, 1
    if wants and filesSet then
        fade = LoadFade(GetTime(), s)
        a = target * fade
    end
    if a <= 0.002 then
        G:Hide()
        return wants and filesSet -- (loading, or the first frame of its fade: draw again)
    end
    HideSet(s == sets[1] and sets[2] or sets[1])
    if lvl and mframe.level ~= lvl then
        ns.SetLevelFixed(mframe, lvl)
        mframe.level = lvl
    end
    Place(s, sx0, sy0, sx1 - sx0, sy1 - sy0)
    -- (1.3.1: the fog of war) the unexplored look with the mosaic (as the zones' unexplored land), the explored pieces
    ShowSet(s, a, ns.db == nil or ns.db.mosaic ~= false)
    return fade < 1 -- (still fading in: draw again)
end

---------------------------------------------------------------------------
-- Names (Labels.lua Build): the zone's and its sub-zones', owned by the zone entry
---------------------------------------------------------------------------
function G:AddLabels(add)
    if not Setup() then return end
    local function One(lb, kind)
        local x, y = ns.WorldPosToMap(D.m, lb.wx, lb.wy)
        local it = x and add(x, y, AreaName(lb.ar) or lb.n, kind, zoneE)
        if it then it.homemade = true end -- (Labels: the imagery's bands - the page prints no names)
        return it
    end
    One(D.name, "zone")
    for _, lb in ipairs(D.subzones or {}) do
        local it = One(lb, "subzone")
        if it then it.areaID = lb.ar end -- (1.3.1: the fog of war - Labels.lua: only while its area is explored)
    end
end

-- (tests, /unroll debug) what is set up and shown
function G:Stats()
    if dirty then Recompute() end
    local s = sets[1].a and sets[1] or sets[2]
    local nOn = 0
    for _, on in pairs(s.on) do if on then nOn = nOn + 1 end end
    local ex = {}
    for ar in pairs(exploredAr) do ex[#ex + 1] = ar end
    table.sort(ex)
    return { supported = G:Supported(), page = page or nil, zone = zoneE, filesSet = filesSet, loaded = loadedAt ~= nil,
        alpha = s.a or 0, shown = s.a ~= nil, moving = sets[2].a ~= nil, draws = stats.draws, placed = stats.placed,
        unexplored = s.uOn == true, pieces = nOn, explored = ex, recomputed = stats.recomputed,
        discovered = stats.discovered, events = stats.events }
end
-- (tests) the city layer's copy as T.tex (the unexplored look: the page always drawn) / T.place / T.mask / T.pieces
-- (the explored look's pieces), the detached one as T.moving (its frame: T.frame)
G.T = { tex = sets[1].u, place = sets[1].place, mask = function() return sets[1].mask end, pieces = sets[1].pieces,
    host = function() return host end, page = function() return page or nil end, moving = sets[2],
    frame = function() return mframe end, cuts = function() return Cuts() end, session = session }

---------------------------------------------------------------------------
-- Following Render; (1.3.1: the fog of war) the zone events
---------------------------------------------------------------------------
hooksecurefunc(ns.Render, "Init", function(_, parent) anchor = parent end)
hooksecurefunc(ns.Render, "SetCityLayer", function(_, f) host = f end)
hooksecurefunc(ns.Render, "HideAll", function() G:Hide() end)
hooksecurefunc(ns.Render, "ReleaseAll", function()
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then G:Release() end
end)
hooksecurefunc(ns.Render, "MarkArtDirty", function() dirty = true end) -- (MAP_EXPLORATION_UPDATED, a discovery here)

if G:Supported() and D.areas and D.grid then
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do
        pcall(ev.RegisterEvent, ev, e) -- (an event a client lacks is simply not registered)
    end
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then dirty = true end -- (another character, the game's record: read again)
        Discover()
    end)
end
