local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)

--[[
Dungeon maps (WoW Forever only).

Forever has no dungeon maps of its own (its UiMap table holds no dungeon or
micro maps), but the client ships Blizzard's dungeon map art for the classic
instances (DungeonMaps.lua). This module shows it:

  * Inside a supported dungeon or raid the map opens on that dungeon's map, on
    the floor the player is on (sub-zone name, else the last floor viewed
    there, else the first). Walking into another sub-zone while the map is
    open cross-fades to that floor.
  * On the world map every dungeon / raid entrance has an ICON (the diamond
    under its name, Labels.lua). At rest, hovering it lights it and shows a
    tooltip; clicking it opens the map - the name itself is not a click
    target. An entrance with one dungeon opens that dungeon's map (with its
    entrance cave, where there is one, as a page of the dropdown). An
    entrance with several (Blackrock Mountain, Maraudon, Scarlet Monastery:
    ns.DUNGEON_HUBS) opens its ENTRANCE map at a fixed level; there each
    dungeon's portal carries the same icon (ns.DUNGEON_PORTALS), and clicking
    it opens that dungeon's map. Nothing is picked from the player's position.
  * A small bar: World Map, the entrance map the dungeon was opened from (as a
    second button), the name, a floor / level dropdown. The wheel zooms about
    the cursor (1x-3x, the world zoom's easing), dragging pans and stays on the
    picture, right-click goes back one step (dungeon -> entrance map -> world).
  * The player, where the game tells us the position (UnitPosition): in the
    open-world entrance maps, and inside instances only if the client answers
    there. Blizzard's world-map player arrow turned to GetPlayerFacing(); the
    round player icon when the game gives no facing. The group
    (DungeonMarkers.lua): on open-world pages the ENGINE draws the player and
    the party / raid (a UnitPositionFrame lined up with the page); inside
    dungeons, dots of our own where the game gives the members' positions.

How it stays out of Blizzard's way: the view is one addon frame beside
Blizzard's canvas in the canvas container - like the addon's own detached
mode - above every pin and taking the mouse, while the canvas and its pins
are hidden (alpha 0) and restored exactly on exit. Blizzard's map is never
switched (no SetMapID: the uiMap numbers behind this art don't exist in
Forever), so it is combat-safe, and any map change someone else makes (quest
log, Questie, the nav bar) simply returns to the world map.
]]

local Dungeon = {}
ns.Dungeon = Dungeon

local ART_W, ART_H, TILE = 1002, 668, 256 -- picture = top-left 1002x668 of a 4x3 grid of 256px tiles
local FADE = 0.2           -- world <-> dungeon view and floor cross-fades (seconds)
local LOAD_WAIT = 0.35     -- wait at most this long for a picture's tiles before fading it in
local ZOOM_RATE = 14       -- the world zoom's easing (Core.lua)
local MAX_ZOOM = 3
local MOMENTUM_DECAY = 5   -- (Core.lua)
local DRAG_THRESHOLD = 4
local CLICK_DIST_SQ = 20   -- Blizzard's MAX_DIST_FOR_CLICK_SQ (MapCanvas_ScrollContainerMixin.lua)
local POLL = 0.05          -- player position poll (20 Hz)
local RELEASE_DELAY = 10   -- free the tile textures this long after the map closes (as Core.lua)
local VIEW_LEVEL = 9150    -- above every map pin (2000-9000), like the detached overlay (9100)
-- (view levels: pictures +1 / +2, portal icons +3, group markers +4 (DungeonMarkers.lua), player +5, bar +6)
local BAR_H = 30

-- The player: Blizzard's world-map player arrow (GroupMembersDataProvider.lua
-- SetPinTexture("player", "UI-WorldMapArrow"), 27 px: unitPinSizes.player),
-- pointing up (north) unturned and turned by GetPlayerFacing() (radians,
-- counter-clockwise from north, as SetRotation turns: VehicleDataProvider.lua
-- does the same on north-up maps). Without a facing: the round player icon.
local ARROW_SIZE = 27
local ARROW_ATLAS = "UI-WorldMapArrow"
local ARROW_FILE = "Interface\\WorldMap\\WorldMapArrow"   -- (same art, if the atlas is missing)
local DOT_SIZE = 22
local DOT_FILE = "Interface\\WorldMap\\WorldMapPlayerIcon"
local FACING_EPS = 0.005   -- turn the arrow only when the facing changed this much (radians)

-- Portal icons on entrance maps: the world map's entrance diamonds (Labels.lua)
local DIAMOND = "Interface\\Buttons\\WHITE8X8"
local ICON_SIZE = { dungeon = 12, raid = 14 } -- px at fit; they grow gently with the zoom (IconScale)
local ICON_HIT = 24        -- px square that takes the click (at fit)
local ICON_GROW = 1.25     -- hovered
local LINK_GRACE = 0.5     -- s after a level link was followed in which a press on a pin is no link click
-- Forever Map.db2 InstanceType 2 (raid): orange icons like the world map's raid labels
local RAID = { [249] = true, [309] = true, [409] = true, [469] = true, [509] = true, [531] = true, [533] = true }
local TIP_PAD, TIP_GAP = 8, 3

-- English names (fallback when C_Map.GetAreaInfo has nothing).
local EN = {
    [33] = "Shadowfang Keep", [34] = "The Stockade", [36] = "The Deadmines", [43] = "Wailing Caverns",
    [47] = "Razorfen Kraul", [48] = "Blackfathom Deeps", [70] = "Uldaman", [90] = "Gnomeregan",
    [109] = "Sunken Temple", [129] = "Razorfen Downs", [189] = "Scarlet Monastery", [209] = "Zul'Farrak",
    [229] = "Blackrock Spire", [230] = "Blackrock Depths", [249] = "Onyxia's Lair", [289] = "Scholomance",
    [309] = "Zul'Gurub", [329] = "Stratholme", [349] = "Maraudon", [389] = "Ragefire Chasm",
    [409] = "Molten Core", [429] = "Dire Maul", [469] = "Blackwing Lair", [369] = "Deeprun Tram", [509] = "Ruins of Ahn'Qiraj",
    [531] = "Ahn'Qiraj Temple", [533] = "Naxxramas",
}

-- All module state in one table (keeps every function far from Lua 5.1's
-- upvalue limit).
local D = {
    supported = false, built = false,
    active = false,             -- the view owns the map (Core off, canvas hidden)
    book = nil, pageIndex = nil,
    view = { z = 1, cx = ART_W / 2, cy = ART_H / 2 },
    targetZ = 1,
    lastFloor = {},             -- [dungeon] = floor last shown (this session)
    detected = {},              -- [dungeon] = floor last detected from the player's whereabouts
    W = 0, H = 0,
    vel = { x = 0, y = 0 },
    pollT = 0,
    icons = {}, nIcons = 0,     -- portal icons of the page shown
}

---------------------------------------------------------------------------
-- Names, data
---------------------------------------------------------------------------
local function GlobalString(key)
    local s = key and _G[key]
    if type(s) == "string" and s ~= "" then return s end
end

-- An AreaTable name (localized), when the game has it.
local function AreaName(a)
    if not (a and C_Map and C_Map.GetAreaInfo) then return end
    local ok, name = pcall(C_Map.GetAreaInfo, a)
    if ok and type(name) == "string" and name ~= "" then return name end
end

local function DungeonName(id)
    local dm = ns.DUNGEON_MAPS[id]
    return (dm and AreaName(dm.a)) or EN[id] or (dm and dm.en) or tostring(id)
end

-- A floor or cave: its localized name (Forever GlobalStrings, or the area
-- the floor shows: the Deeprun Tram's stations), else enUS.
local function FloorName(f)
    return (f.g and GlobalString("DUNGEON_FLOOR_" .. f.g)) or (f.ar and AreaName(f.ar)) or f.n
end

local function WingName(w)
    if w[2] and w[2] > 0 and GetLFGDungeonInfo then
        local ok, name = pcall(GetLFGDungeonInfo, w[2])
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return w[1]
end

local wingsOf
local function WingsOf(id)
    if not wingsOf then
        wingsOf = {}
        for _, e in pairs(ns.DUNGEON_ENTRANCES or {}) do
            if e.w then
                local top = 0
                for _, w in ipairs(e.w) do
                    for _, f in ipairs(w[3]) do if f > top then top = f end end
                end
                for _, id2 in ipairs(e.d) do
                    local dm = ns.DUNGEON_MAPS[id2]
                    if dm and #dm.f >= top then wingsOf[id2] = e.w break end
                end
            end
        end
    end
    return wingsOf[id]
end

-- (1.0.0) The wing (index into WingsOf) a floor belongs to, 0 = none (DungeonBosses.lua counts per wing).
local function WingOfFloor(id, f)
    for i, w in ipairs(WingsOf(id) or {}) do
        for _, x in ipairs(w[3]) do if x == f then return i end end
    end
    return 0
end

-- A portal icon's dungeon / wing (localized where the game has the name).
local function PortalName(p)
    if p.lfg and p.lfg > 0 then return WingName({ p.n, p.lfg }) end
    return DungeonName(p.m)
end

local function Trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Player position (X north, Y west, Z, instance map) - only when the game
-- gives plain numbers (retail returns nothing inside instances).
local function PlayerPos()
    if not UnitPosition then return end
    local ok, x, y, z, inst = pcall(UnitPosition, "player")
    if not ok or type(x) ~= "number" or type(y) ~= "number" then return end
    if issecretvalue and (issecretvalue(x) or issecretvalue(y) or issecretvalue(inst)) then return end
    return x, y, z, inst
end

-- The player's facing (radians, 0 = north, counter-clockwise), when the game
-- gives a plain number (PlayerScriptDocumentation.lua: GetPlayerFacing,
-- result Nilable).
local function PlayerFacing()
    if not GetPlayerFacing then return end
    local ok, f = pcall(GetPlayerFacing)
    if not ok or type(f) ~= "number" then return end
    if issecretvalue and issecretvalue(f) then return end -- (review: before any compare - not even f ~= f on a secret)
    if f ~= f then return end
    return f
end

-- Region r = { minX, minY, maxX, maxY } (world yards): the picture's u, v.
local function RegionUV(r, x, y)
    return (r[4] - y) / (r[4] - r[2]), (r[3] - x) / (r[3] - r[1])
end
local function InRegion(r, x, y, m)
    local u, v = RegionUV(r, x, y)
    m = m or 0
    return u >= -m and u <= 1 + m and v >= -m and v <= 1 + m
end

-- The mapped map the player is on (GetInstanceInfo's 8th return, a plain number).
local function PlayerMap()
    if not GetInstanceInfo then return end
    local ok, _, _, _, _, _, _, _, id = pcall(GetInstanceInfo)
    if not ok or type(id) ~= "number" or (issecretvalue and issecretvalue(id)) then return end
    return id, ns.DUNGEON_MAPS[id]
end

-- (ni maps: only where one of the map's pictures shows the player - the Deeprun
-- Tram's one picture is its Stormwind end; at the Ironforge end or on the ride
-- it would show a place the player isn't.)
local function OnSomeFloor(dm, id)
    local x, y, _, inst = PlayerPos()
    if not (x and inst == id) then return false end
    for _, f in ipairs(dm.f) do
        if InRegion(f.r, x, y, 0.01) then return true end
    end
    return false
end

-- The supported instance the player is in. (Deeprun Tram: Map.db2 InstanceType
-- 0 - IsInInstance() is false there; its entry says ni = true, and it counts
-- only while the player is on its picture.)
local function CurrentInstance()
    if not (IsInInstance and GetInstanceInfo) then return end
    local ok, inside = pcall(IsInInstance)
    if not ok then return end
    local isIn = false
    if not (issecretvalue and issecretvalue(inside)) then isIn = inside and true or false end
    local id, dm = PlayerMap()
    if dm and (isIn or (dm.ni and OnSomeFloor(dm, id))) then return id end
end

-- The ni map the player is on, wherever on it (nil: none).
local function NiMap()
    local id, dm = PlayerMap()
    if dm and dm.ni then return id, dm end
end

-- Which floor of dungeon id the player is on, from what the game tells us
-- (nil = no evidence). 1) the sub-zone's enUS name (DungeonMaps.lua s),
-- 2) a floor's own localized name, 3) the player's position (when the game
-- gives it there), 4) among the sub-zone's floors, the last one viewed.
-- (Only inside the instance: auto-open and the player marker. Maps opened
-- from the world map never guess from the player's whereabouts.)
-- 1.0.0: sz floors (DungeonMapsMM.lua) are never picked from the position alone;
-- maps with an ov floor (the whole map at a smaller scale: the Deeprun Tram's
-- line, Half-Pint Tavern's Arathi copy) pick from the position only - another
-- floor holding the player wins (2% inside its picture to enter, 1% past its
-- edge to leave), else the ov floor.
local PICK_ENTER, PICK_STAY = -0.02, 0.01
local ovMaps = {}
local function HasOv(dm)
    local o = ovMaps[dm]
    if o == nil then
        o = false
        for _, f in ipairs(dm.f) do if f.ov then o = true end end
        ovMaps[dm] = o
    end
    return o
end

local function PickOv(dm, x, y, cur)
    local ov
    for i, f in ipairs(dm.f) do
        if f.ov then
            ov = ov or i
        elseif not f.sz and InRegion(f.r, x, y, i == cur and PICK_STAY or PICK_ENTER) then
            return i
        end
    end
    if ov and InRegion(dm.f[ov].r, x, y) then return ov end
end

local function DetectFloor(id)
    local dm = ns.DUNGEON_MAPS[id]
    if not dm then return end
    if HasOv(dm) then
        local x, y, _, inst = PlayerPos()
        if x then
            if inst ~= id then return end
            return PickOv(dm, x, y, D.detected[id])
        end
        -- (1.0.0: no position at all - inside Half-Pint Tavern the game gives none: the sub-zone name, below)
    end
    local sub = Trim(GetSubZoneText and GetSubZoneText())
    local cands
    if sub ~= "" then
        local s = dm.s and dm.s[sub]
        if type(s) == "number" then return s end
        if type(s) == "table" then cands = s end
        if not cands and sub ~= Trim(GetZoneText and GetZoneText()) and sub ~= DungeonName(id) then
            for i, f in ipairs(dm.f) do
                if f.g and GlobalString("DUNGEON_FLOOR_" .. f.g) == sub then return i end
            end
        end
    end
    local last = D.lastFloor[id]
    local x, y, _, inst = PlayerPos()
    if x and inst == id then
        local first
        for i = 1, (cands and #cands or #dm.f) do
            local fi = cands and cands[i] or i
            local f = dm.f[fi]
            if f and not f.sz and InRegion(f.r, x, y) then
                if fi == last then return fi end
                first = first or fi
            end
        end
        if first then return first end
    end
    if cands then
        for _, fi in ipairs(cands) do if fi == last then return fi end end
        return cands[1]
    end
end

---------------------------------------------------------------------------
-- Books: what the view can show, as pages (floors, caves) in groups
---------------------------------------------------------------------------
local function AddGroup(book, title)
    local g = { title = title, first = #book.pages + 1, last = #book.pages }
    book.groups[#book.groups + 1] = g
    return g
end

local function AddPage(book, g, p)
    book.pages[#book.pages + 1] = p
    p.index, p.group = #book.pages, g
    g.last = #book.pages
end

local function AddFloors(book, id, g, place)
    local dm = ns.DUNGEON_MAPS[id]
    local function add(i, grp, pl)
        local f = dm.f[i]
        if f then
            AddPage(book, grp, { kind = "floor", inst = id, dun = id, floor = i, f = f, name = FloorName(f), place = pl })
        end
    end
    local name = DungeonName(id)
    local wings = WingsOf(id)
    if g then
        for i = 1, #dm.f do add(i, g, place or name) end
    elseif wings then
        for _, w in ipairs(wings) do
            local wn = WingName(w)
            local grp = AddGroup(book, wn)
            -- (a wing with its own LFG name - DM North/West/East, LBRS/UBRS - names the view)
            for _, i in ipairs(w[3]) do add(i, grp, (w[2] and w[2] > 0) and wn or name) end
        end
    else
        local grp = AddGroup(book, name)
        for i = 1, #dm.f do add(i, grp, name) end
    end
end

local function AddCave(book, g, key)
    local c = ns.DUNGEON_CAVES[key]
    if c then AddPage(book, g, { kind = "cave", inst = c.m, cave = key, f = c, name = FloorName(c), place = g.title }) end
end

local function PageOfFloor(book, id, floor)
    for i, p in ipairs(book.pages) do
        if p.kind == "floor" and p.dun == id and p.floor == floor then return i end
    end
end

-- The dungeons of a world entrance that have maps.
local function MappedIds(e)
    local ids = {}
    for _, id in ipairs(e and e.d or {}) do if ns.DUNGEON_MAPS[id] then ids[#ids + 1] = id end end
    return ids
end

-- A world entrance with several dungeons behind it (ns.DUNGEON_HUBS): its
-- entrance map's levels, opening on the hub's fixed default level. Dungeons
-- no portal icon leads to yet (Scarlet Monastery's wings) are added as floors,
-- so the dropdown still reaches them.
local function HubBook(key)
    local hub = ns.DUNGEON_HUBS and ns.DUNGEON_HUBS[key]
    if not (hub and hub.levels and ns.DUNGEON_CAVES) then return end
    local book = { pages = {}, groups = {}, entrance = key, hub = key, title = key }
    local g = AddGroup(book, key)
    local reached = {}
    for _, ck in ipairs(hub.levels) do
        AddCave(book, g, ck)
        for _, p in ipairs(ns.DUNGEON_PORTALS and ns.DUNGEON_PORTALS[ck] or {}) do reached[p.m] = true end
    end
    if #book.pages == 0 then return end
    local e = ns.DUNGEON_ENTRANCES and ns.DUNGEON_ENTRANCES[key]
    for _, id in ipairs(MappedIds(e)) do
        if not reached[id] then AddFloors(book, id) end
    end
    book.start = 1
    for i, p in ipairs(book.pages) do
        if p.kind == "cave" and p.cave == hub.default then book.start = i break end
    end
    return book
end

-- A world entrance with one dungeon: its entrance cave(s) in the open world
-- (with the portal icon) and its floors, opening on the floor the entrance
-- leads to (Stratholme's two gates) - else the first.
local function DungeonBook(key)
    local e = ns.DUNGEON_ENTRANCES and ns.DUNGEON_ENTRANCES[key]
    if not e or not e.d then return end
    local ids = MappedIds(e)
    if #ids == 0 then return end
    local book = { pages = {}, groups = {}, entrance = key }
    local single = #ids == 1 and not WingsOf(ids[1])
    book.title = single and DungeonName(ids[1]) or key
    local g
    if e.c and #e.c > 0 and ns.DUNGEON_CAVES then
        g = AddGroup(book, book.title)
        for _, ck in ipairs(e.c) do AddCave(book, g, ck) end
    end
    for _, id in ipairs(ids) do
        if single then
            AddFloors(book, id, g or AddGroup(book, book.title), book.title)
        else
            AddFloors(book, id)
        end
    end
    book.start = PageOfFloor(book, ids[1], e.floor or 1)
    if not book.start then
        for i, p in ipairs(book.pages) do if p.kind == "floor" then book.start = i break end end
    end
    book.start = book.start or 1
    return book
end

-- A dungeon opened from a portal icon of an entrance map (whose bar and
-- right-click lead back there), or the dungeon the player is in (auto).
local function FloorsBook(id)
    local book = { pages = {}, groups = {}, title = DungeonName(id) }
    AddFloors(book, id)
    return book
end

local function InstanceBook(id)
    local book = FloorsBook(id)
    book.inst, book.auto = id, true
    return book
end

local function CurrentPage()
    return D.book and D.book.pages[D.pageIndex]
end

---------------------------------------------------------------------------
-- Picture layers, view math
---------------------------------------------------------------------------
local function NewLayer(parent, level)
    local L = CreateFrame("Frame", nil, parent)
    ns.SetLevelFixed(L, level)
    L:SetSize(ART_W, ART_H)
    L.tex = {}
    for i = 1, 12 do
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        local w, h = math.min(TILE, ART_W - col * TILE), math.min(TILE, ART_H - row * TILE)
        local t = L:CreateTexture(nil, "ARTWORK")
        t:SetSize(w, h)
        t:SetPoint("TOPLEFT", L, "TOPLEFT", col * TILE, -row * TILE)
        t:SetTexCoord(0, w / TILE, 0, h / TILE)
        L.tex[i] = t
    end
    L:Hide()
    return L
end

local function LoadLayer(L, page)
    if L.page == page then return end
    local f = page.f
    if f.q or f.rq then
        for i = 1, 12 do
            L.tex[i]:SetTexture(nil)
            L.tex[i]:Hide()
        end
        ns.Quads:Load(L, f)
    else
        for i = 1, 12 do
            local t = L.tex[i]
            t:SetTexture(f.t[i], "CLAMP", "CLAMP", "TRILINEAR")
            t:Show()
        end
        ns.Quads:Clear(L)
    end
    L.page = page
    if ns.Where then ns.Where:OnLoad(L, page) end -- (1.0.0: a lit room of another page goes)
end

local function LayerLoaded(L)
    for i = 1, 12 do
        local t = L.tex[i]
        if t:IsShown() and t.IsObjectLoaded and not t:IsObjectLoaded() then return false end
    end
    return ns.Quads:Loaded(L)
end

-- Free the tiles (map closed a while; like Render:ReleaseAll). They load
-- again when a page is shown.
local function ReleaseLayers()
    for _, L in ipairs(D.layers) do
        if L.page then
            for i = 1, 12 do L.tex[i]:SetTexture(nil) end
            ns.Quads:Clear(L)
            L.page = nil
        end
    end
end

-- The map area: the view below the bar (the picture never hides under the
-- bar at fit, so the art's own title banner stays readable).
local function AreaH() return math.max(D.H - BAR_H, 1) end
local function MidY() return BAR_H + AreaH() / 2 end
local function Fit()
    return math.min(D.W / ART_W, AreaH() / ART_H)
end

-- Keep the view on the picture (centred where it is smaller than the area).
local function ClampView(v)
    local s = Fit() * v.z
    if s <= 0 then return end
    local hw, hh = D.W / 2 / s, AreaH() / 2 / s
    if hw * 2 >= ART_W then v.cx = ART_W / 2 else v.cx = ns.Clamp(v.cx, hw, ART_W - hw) end
    if hh * 2 >= ART_H then v.cy = ART_H / 2 else v.cy = ns.Clamp(v.cy, hh, ART_H - hh) end
end

local function Place(L, v)
    local s = Fit() * v.z
    if not (s > 0) then return end
    local ox, oy = D.W / 2 - v.cx * s, MidY() - v.cy * s
    if L.s ~= s then
        L:SetScale(s)
        L.s, L.ox = s, nil
    end
    if L.ox ~= ox or L.oy ~= oy then
        L:SetPoint("TOPLEFT", D.dv, "TOPLEFT", ox / s, -oy / s)
        L.ox, L.oy = ox, oy
    end
end

-- Cursor in the view's units, origin top-left, y down.
local function Cursor()
    local x, y = GetCursorPosition()
    local dv = D.dv
    local s = dv:GetEffectiveScale()
    local l, t = dv:GetLeft(), dv:GetTop()
    if not (l and t and s and s > 0) then return D.W / 2, MidY() end
    return x / s - l, t - y / s
end

local function ArtAt(mx, my)
    local v = D.view
    local s = Fit() * v.z
    return v.cx + (mx - D.W / 2) / s, v.cy + (my - MidY()) / s
end

-- Where the picture point (u, v in 0..1) is in the view (px).
local function ViewXY(u, w)
    local v = D.view
    local s = Fit() * v.z
    return D.W / 2 + (u * ART_W - v.cx) * s, MidY() + (w * ART_H - v.cy) * s
end
local function InArea(px, py)
    return px >= 0 and px <= D.W and py >= BAR_H and py <= D.H
end

-- The view on page b that shows what view v shows on page a: the same world
-- spot at the same zoom when both lie on one map (floors of a dungeon, the
-- levels of Blackrock Mountain), else the whole picture.
local function CarryView(a, b, v)
    local nv = { z = 1, cx = ART_W / 2, cy = ART_H / 2 }
    if a and b and a.inst == b.inst then
        local r0, r1 = a.f.r, b.f.r
        local X = r0[3] - v.cy / ART_H * (r0[3] - r0[1])
        local Y = r0[4] - v.cx / ART_W * (r0[4] - r0[2])
        local u, w = RegionUV(r1, X, Y)
        if u >= 0 and u <= 1 and w >= 0 and w <= 1 then
            nv.z, nv.cx, nv.cy = v.z, u * ART_W, w * ART_H
        end
    end
    return nv
end

---------------------------------------------------------------------------
-- Canvas hand-over (Core off + Blizzard's canvas hidden) and back
---------------------------------------------------------------------------
local function CanvasChild()
    local c = WorldMapFrame and WorldMapFrame.ScrollContainer
    return c and c.Child
end

local function Available()
    local db = ns.db
    return D.supported and D.built and db ~= nil and db.enabled ~= false and db.dungeons ~= false
end

local function TakeCanvas()
    if D.canvasTaken then return end
    D.canvasTaken = true
    if ns.Core then ns.Core.GoOff() end
    local child = CanvasChild()
    if child then
        D.canvasAlpha = child:GetAlpha()
        child:SetAlpha(0)
    end
end

local function GiveCanvas()
    if not D.canvasTaken then return end
    D.canvasTaken = false
    local child = CanvasChild()
    if child and D.canvasAlpha and child:GetAlpha() ~= D.canvasAlpha then child:SetAlpha(D.canvasAlpha) end
    D.canvasAlpha = nil
end

-- The bar's buttons take the mouse only while the view owns the map (not
-- while it fades out over a world map that may already move). (By key: the
-- dropdown and the prev / next fallback never both exist, and ipairs would
-- stop at the first missing one.)
local BAR_BUTTONS = { "back", "up", "lvl", "dd", "prev", "next" }
local function BarMouse(on)
    for _, k in ipairs(BAR_BUTTONS) do
        local b = D[k]
        if b and b.EnableMouse then b:EnableMouse(on) end
    end
end

local function CloseMenu()
    local dd = D.dd
    if dd and dd.CloseMenu and dd.IsMenuOpen and dd:IsMenuOpen() then pcall(dd.CloseMenu, dd) end
end

---------------------------------------------------------------------------
-- Tooltip (an addon frame on UIParent: GameTooltip stays untouched)
---------------------------------------------------------------------------
local function BuildTip()
    local f = CreateFrame("Frame", nil, UIParent)
    if f.SetFrameStrata then f:SetFrameStrata("TOOLTIP") end
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    local edge = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    edge:SetAllPoints(f)
    edge:SetColorTexture(0.62, 0.5, 0.26, 0.9)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.04, 0.035, 0.03, 0.94)
    f.lines = {}
    f:Hide()
    return f
end

-- Beside the cursor (right of the cursor art, like ANCHOR_CURSOR_RIGHT).
local function MoveTip()
    local f = D.tip
    if not (f and D.tipShown) then return end
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    if not (x and y and s and s > 0) then return end
    if x == D.tipX and y == D.tipY then return end
    D.tipX, D.tipY = x, y
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s + 20, y / s - 6)
end

-- lines = { { text, r, g, b, size }, ... }
local function ShowTip(lines)
    local f = D.tip
    if not f then return end
    local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local w, y = 0, TIP_PAD
    for i, L in ipairs(lines) do
        local fs = f.lines[i]
        if not fs then
            fs = f:CreateFontString(nil, "OVERLAY")
            f.lines[i] = fs
        end
        fs:SetFont(font, L[5] or 11, "")
        fs:SetTextColor(L[2], L[3], L[4])
        fs:SetText(L[1])
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", TIP_PAD, -y)
        fs:Show()
        local sw = fs:GetStringWidth()
        if type(sw) == "number" and sw > w then w = sw end
        y = y + (L[5] or 11) + TIP_GAP
    end
    for i = #lines + 1, #f.lines do f.lines[i]:Hide() end
    f:SetSize(math.max(w, 60) + 2 * TIP_PAD, y - TIP_GAP + TIP_PAD)
    D.tipShown, D.tipX = true, nil
    MoveTip()
    f:Show()
end

local function HideTip()
    if D.tip and D.tipShown then D.tip:Hide() end
    D.tipShown = false
end

local HINT = { 0.25, 1, 0.25, 11 }
local function Hint(text) return { text, HINT[1], HINT[2], HINT[3], HINT[4] } end

-- A hub level's dungeons (their portal icons' names, once each), as tooltip
-- lines appended to lines.
local function LevelLines(lines, cave)
    local seen = {}
    for _, p in ipairs(ns.DUNGEON_PORTALS and ns.DUNGEON_PORTALS[cave] or {}) do
        local n = PortalName(p)
        if not seen[n] then
            seen[n] = true
            lines[#lines + 1] = { n, 0.95, 0.85, 0.55, 11 }
        end
    end
    return lines
end

-- World map entrance icon: its name, level range, the dungeons behind it
-- when there are several, and what a click does.
local PortalTip
local function EntranceTip(it)
    if it.portal then return PortalTip(it.portal) end
    local key = it.entrance
    local e = ns.DUNGEON_ENTRANCES and ns.DUNGEON_ENTRANCES[key]
    local hub = ns.DUNGEON_HUBS and ns.DUNGEON_HUBS[key]
    local ids = MappedIds(e)
    local title = key
    if not hub and #ids == 1 then
        title = DungeonName(ids[1])
        local f = e.floor and (e.floor > 1 or e.named) and ns.DUNGEON_MAPS[ids[1]].f[e.floor]
        if f then title = title .. " - " .. FloorName(f) end -- (Stratholme's service gate)
    end
    local lines = { { title, 1, 1, 1, 13 } }
    local lo, hi = it.minLevel, it.maxLevel
    if type(lo) == "number" then
        local lv = GlobalString("LEVEL") or "Level"
        lines[#lines + 1] = { (type(hi) == "number" and hi > lo) and ("%s %d-%d"):format(lv, lo, hi) or ("%s %d"):format(lv, lo), 0.7, 0.7, 0.7, 11 }
    end
    if e and e.note then lines[#lines + 1] = { e.note, 0.7, 0.7, 0.7, 11 } end -- (the Deeprun Tram: which end)
    -- (a detail level's bare art, Render:DetailAt: the level under the cursor and its dungeons)
    local c = it.level and ns.DUNGEON_CAVES and ns.DUNGEON_CAVES[it.level]
    if c then
        local lk = ns.DUNGEON_LEVEL_LINKS and ns.DUNGEON_LEVEL_LINKS[it.level]
        local where = lk and lk[1] and (lk[1].dir == "down" and "upper level" or "lower level")
        lines[#lines + 1] = { FloorName(c) .. (where and (" (" .. where .. ")") or ""), 1, 0.82, 0, 12 }
        LevelLines(lines, it.level)
        lines[#lines + 1] = Hint("Click to open this level of the entrance map")
        return lines
    end
    -- (a hub whose levels are linked - Blackrock Mountain: its dungeons by level)
    local LL = hub and ns.DUNGEON_LEVEL_LINKS
    if LL and hub.levels and LL[hub.levels[1]] then
        for _, ck in ipairs(hub.levels) do
            local lc, lk = ns.DUNGEON_CAVES[ck], LL[ck] and LL[ck][1]
            if lc then
                local where = lk and (lk.dir == "down" and "upper level" or "lower level")
                lines[#lines + 1] = { FloorName(lc) .. (where and (" (" .. where .. ")") or ""), 0.7, 0.7, 0.7, 11 }
                LevelLines(lines, ck)
            end
        end
        lines[#lines + 1] = Hint("Click to open the entrance map")
        return lines
    end
    local names = {}
    for _, id in ipairs(ids) do
        local wings = WingsOf(id)
        if wings then
            for _, w in ipairs(wings) do names[#names + 1] = WingName(w) end
        else
            names[#names + 1] = DungeonName(id)
        end
    end
    if #names > 1 then
        for _, n in ipairs(names) do lines[#lines + 1] = { n, 0.95, 0.85, 0.55, 11 } end
    end
    lines[#lines + 1] = Hint(hub and "Click to open the entrance map" or "Click to open the map")
    return lines
end

PortalTip = function(p)
    return { { PortalName(p), 1, 1, 1, 13 }, Hint("Click to open the map") }
end

-- A level link (pin or bar button, DungeonLinks.lua): the level it leads to,
-- which one, the way, the dungeons there, what a click does.
local function LinkTip(lk)
    local c = ns.DUNGEON_CAVES and ns.DUNGEON_CAVES[lk.to]
    local down = lk.dir == "down"
    local lines = { { c and FloorName(c) or tostring(lk.to), 1, 1, 1, 13 }, { down and "Lower level" or "Upper level", 0.7, 0.7, 0.7, 11 } }
    if lk.via then lines[#lines + 1] = { lk.via, 0.7, 0.7, 0.7, 11 } end
    LevelLines(lines, lk.to)
    lines[#lines + 1] = Hint(down and "Click to go down to this level" or "Click to go up to this level")
    return lines
end

---------------------------------------------------------------------------
-- Portal icons on entrance maps (hover, click: that dungeon's map)
---------------------------------------------------------------------------
local function IconScale() return D.view.z ^ 0.25 end

local function NewIcon()
    local f = D.iconFrame
    local rim = f:CreateTexture(nil, "OVERLAY", nil, 1)
    rim:SetTexture(DIAMOND)
    rim:SetVertexColor(0.05, 0.04, 0.03, 0.9)
    local fill = f:CreateTexture(nil, "OVERLAY", nil, 2)
    fill:SetTexture(DIAMOND)
    if fill.SetRotation then
        rim:SetRotation(math.rad(45))
        fill:SetRotation(math.rad(45))
    end
    rim:Hide()
    fill:Hide()
    return { rim = rim, fill = fill, on = false }
end

local function PaintIcon(ic)
    local st = ns.Labels and ns.Labels.STYLE and ns.Labels.STYLE[ic.kind]
    if ic == D.hotIcon then
        ic.fill:SetVertexColor(1, 1, 1)
    elseif st then
        ic.fill:SetVertexColor(st.r, st.g, st.b)
    else
        ic.fill:SetVertexColor(0.4, 1, 0.4)
    end
    ic.size = nil -- (sized again by PlaceIcons)
    D.iconsDirty = true
end

local function PlaceIcons()
    D.iconsDirty = false
    if not (Fit() * D.view.z > 0) then return end
    local k = IconScale()
    for i = 1, D.nIcons do
        local ic = D.icons[i]
        local px, py = ViewXY(ic.p.x, ic.p.y)
        ic.px, ic.py = px, py
        local on = InArea(px, py)
        if on then
            local size = ICON_SIZE[ic.kind] * k * (ic == D.hotIcon and ICON_GROW or 1)
            if ic.size ~= size then
                ic.fill:SetSize(size, size)
                ic.rim:SetSize(size + 4, size + 4)
                ic.size = size
            end
            if ic.x ~= px or ic.y ~= py then
                ic.fill:SetPoint("CENTER", D.iconFrame, "TOPLEFT", px, -py)
                ic.rim:SetPoint("CENTER", D.iconFrame, "TOPLEFT", px, -py)
                ic.x, ic.y = px, py
            end
        end
        if on ~= ic.on then
            ic.on = on
            ic.rim:SetShown(on)
            ic.fill:SetShown(on)
        end
    end
end

-- The icon under view point (mx, my): a 24 x 24 px square around it (the
-- nearest if two squares touch); never under the bar.
local function IconAt(mx, my)
    if D.nIcons == 0 or not (mx and my) or my < BAR_H then return nil end
    local half = ICON_HIT / 2 * IconScale()
    local best, bestD
    for i = 1, D.nIcons do
        local ic = D.icons[i]
        if ic.on and ic.px then
            local dx, dy = math.abs(mx - ic.px), math.abs(my - ic.py)
            if dx <= half and dy <= half and (not best or dx * dx + dy * dy < bestD) then
                best, bestD = ic, dx * dx + dy * dy
            end
        end
    end
    return best
end

local function SetHotIcon(ic)
    if D.hotIcon == ic then return end
    local old = D.hotIcon
    D.hotIcon = ic
    if old then PaintIcon(old) end
    if ic then
        PaintIcon(ic)
        ShowTip(PortalTip(ic.p))
        D.unitsTip = nil
        D.cursorOurs = true
    else
        HideTip()
        if D.cursorOurs then
            D.cursorOurs = false
            if ResetCursor then ResetCursor() end
        end
    end
end

-- The level-link pin under the cursor (DungeonLinks.lua): lit, its tooltip,
-- the interact cursor - as SetHotIcon.
local function SetHotLink(lk)
    if D.hotLink == lk then return end
    D.hotLink = lk
    if ns.Links then ns.Links:SetHot(lk) end
    if lk then
        ShowTip(LinkTip(lk))
        D.unitsTip = nil
        D.cursorOurs = true
    elseif not D.hotIcon then
        HideTip()
        if D.cursorOurs then
            D.cursorOurs = false
            if ResetCursor then ResetCursor() end
        end
    end
end

-- (1.0.0) Where a click on an entrance marker (DungeonBosses.lua) leads: this book's entrance cave whose portal leads
-- to the dungeon, else the entrance map the dungeon was opened from. dry: only the tooltip hint (nil = no click).
local function EntranceGo(it, dry)
    local book = D.book
    if not (book and it) then return nil end
    for i, p in ipairs(book.pages) do
        if p.kind == "cave" then
            for _, pt in ipairs(ns.DUNGEON_PORTALS and ns.DUNGEON_PORTALS[p.cave] or {}) do
                if pt.m == it.dun then
                    if dry then return "Click to show the entrance map" end
                    Dungeon:ShowPage(i, "fade", true)
                    return true
                end
            end
        end
    end
    if book.parent then
        if dry then return "Click to go back to " .. tostring(book.parent.book.title or "the entrance map") end
        return Dungeon:Back()
    end
end

-- (1.0.0) The boss / entrance marker under the cursor (DungeonBosses.lua): lit, its tooltip, the interact cursor -
-- as SetHotLink.
local function SetHotBoss(it)
    if D.hotBoss == it then return end
    D.hotBoss = it
    if ns.Bosses then ns.Bosses:SetHot(it) end
    if it then
        ShowTip(ns.Bosses:Tip(it, it.kind == "entrance" and EntranceGo(it, true) or nil))
        D.unitsTip = nil
        D.cursorOurs = true
    elseif not (D.hotIcon or D.hotLink) then
        HideTip()
        if D.cursorOurs then
            D.cursorOurs = false
            if ResetCursor then ResetCursor() end
        end
    end
end

-- The icons of page (its portals: ns.DUNGEON_PORTALS[cave]) and its level
-- links (DungeonLinks.lua); none for floors. (1.0.0: a floor's boss and entrance markers, DungeonBosses.lua)
local function SetIcons(page)
    SetHotIcon(nil)
    SetHotLink(nil)
    SetHotBoss(nil)
    if ns.Links then ns.Links:SetPage(page) end
    if ns.Bosses then
        ns.Bosses:SetShown(not (ns.db and ns.db.bosses == false))
        ns.Bosses:SetPage(page)
    end
    local list = page and page.kind == "cave" and ns.DUNGEON_PORTALS and ns.DUNGEON_PORTALS[page.cave]
    local n = 0
    for _, p in ipairs(list or {}) do
        local dm = ns.DUNGEON_MAPS[p.m]
        if dm and dm.f[p.f] and type(p.x) == "number" and type(p.y) == "number" then
            n = n + 1
            local ic = D.icons[n] or NewIcon()
            D.icons[n] = ic
            ic.p, ic.kind = p, RAID[p.m] and "raid" or "dungeon"
            ic.x, ic.px = nil, nil
            PaintIcon(ic)
        end
    end
    for i = n + 1, #D.icons do
        local ic = D.icons[i]
        ic.p, ic.px = nil, nil
        if ic.on then
            ic.on = false
            ic.rim:Hide()
            ic.fill:Hide()
        end
    end
    D.nIcons = n
    D.iconsDirty = true
end

-- The view glides (momentum after a drag): icons slide under the cursor.
local function Gliding() return D.vel.x ~= 0 or D.vel.y ~= 0 end

-- A group member's dot (DungeonMarkers.lua) under the cursor: their names.
local function SetHotUnits(names)
    local key = names and table.concat(names, "|") or nil
    if key == D.unitsTip then
        if key then MoveTip() end
        return
    end
    D.unitsTip = key
    if names then
        local lines = {}
        for i, n in ipairs(names) do lines[i] = { n, 1, 1, 1, 12 } end
        ShowTip(lines)
    else
        HideTip()
    end
end

-- Per frame over the view: light the icon under the cursor (tooltip,
-- interact cursor - Blizzard's canvas doesn't set one while the view has
-- the mouse), else name the group members under it. Not while dragging or
-- gliding: like pins on the world map while it moves, icons sliding by
-- don't light up.
local function UpdateHover()
    local ic, lk, bk, names
    local mk = ns.Markers and ns.Markers:HasPositions()
    local nl = ns.Links and ns.Links:Count() or 0
    local nb = ns.Bosses and ns.Bosses:Count() or 0
    if D.active and not D.fade and (D.nIcons > 0 or nl > 0 or nb > 0 or mk) and not (D.press and D.press.dragging) and not Gliding()
        and D.dv.IsMouseMotionFocus and D.dv:IsMouseMotionFocus() then
        local mx, my = Cursor()
        -- (priority: portal icon, level-link pin, boss / entrance marker, group member names)
        if D.nIcons > 0 then ic = IconAt(mx, my) end
        if not ic and nl > 0 then lk = ns.Links:At(mx, my, IconScale(), BAR_H) end
        if not (ic or lk) and nb > 0 then bk = ns.Bosses:At(mx, my, IconScale(), BAR_H) end
        if not (ic or lk or bk) and mk then names = ns.Markers:UnitsAt(mx, my, ViewXY) end
    end
    SetHotIcon(ic)
    SetHotLink(lk)
    SetHotBoss(bk)
    if ic or lk or bk then
        MoveTip()
        if SetCursor then SetCursor("INTERACT_CURSOR") end
    elseif names or D.unitsTip then
        SetHotUnits(names)
    end
end

local function HideView()
    CloseMenu()
    D.fade, D.xfade = nil, nil
    D.press, D.rpress, D.anchor = nil, nil, nil
    D.vel.x, D.vel.y = 0, 0
    SetIcons(nil)
    if ns.Markers then ns.Markers:SetPage(nil) end
    if D.unitsTip then
        D.unitsTip = nil
        HideTip()
    end
    if D.dv then
        D.dv:Hide()
        D.dv:SetAlpha(1)
        for _, L in ipairs(D.layers) do L:SetAlpha(1) end
        D.iconFrame:SetAlpha(1)
        D.arrow:Hide()
        D.dot:Hide()
        D.markerShown = false
        D.arrowOn = false
    end
end

---------------------------------------------------------------------------
-- Bar (World Map, the entrance map, name, floor dropdown)
---------------------------------------------------------------------------
local function IsSelected(i) return D.pageIndex == i end
local function SetSelected(i) Dungeon:ShowPage(i, "fade", true) end

-- One heading per dungeon / wing when there are several; a group that is
-- one floor named like the group (Molten Core, UBRS) gets a divider instead.
local function MenuGenerator(_, root)
    local book = D.book
    if not book then return end
    local titles = #book.groups > 1
    local prevPlain = true
    for gi, g in ipairs(book.groups) do
        if g.last >= g.first then
            local plain = not titles or (g.first == g.last and book.pages[g.first].name == g.title)
            if titles and not plain and root.CreateTitle then
                root:CreateTitle(g.title)
            elseif titles and plain and gi > 1 and not prevPlain and root.CreateDivider then
                root:CreateDivider()
            end
            for i = g.first, g.last do
                root:CreateRadio(book.pages[i].name, IsSelected, SetSelected, i)
            end
            prevPlain = plain
        end
    end
end

-- A bar button as wide as its text.
local function FitButton(b, text)
    b:SetText(text)
    local fs = b.GetFontString and b:GetFontString()
    local w = fs and fs.GetStringWidth and fs:GetStringWidth()
    if type(w) == "number" and w > 0 then b:SetWidth(math.max(90, w + 30)) end
end

-- The level link of the page shown when it is a hub level (DungeonLinks.lua), else nil.
local function LevelLink()
    local book = D.book
    local t = book and book.hub and not book.parent and ns.Links and ns.Links:ForPage(CurrentPage())
    return t and t[1]
end

-- The second button: the entrance map this dungeon was opened from - or, on
-- a hub level with a level link, the other level (arrow + its name; the two
-- never show together: a hub has no parent).
local function RefreshUp()
    local par = D.book and D.book.parent
    if par and D.upText ~= par.book.title then
        FitButton(D.up, par.book.title or "")
        D.upText = par.book.title
    end
    D.up:SetShown(par ~= nil)
    local lk = not par and LevelLink()
    if lk then
        local c = ns.DUNGEON_CAVES[lk.to]
        local text = ns.Links:ButtonText(lk, c and FloorName(c) or lk.to)
        if D.lvlText ~= text then
            FitButton(D.lvl, text)
            D.lvlText = text
        end
    end
    D.lvl.link = lk or nil
    D.lvl:SetShown(D.lvl.link ~= nil)
    local left = (par and D.up) or (lk and D.lvl) or D.back
    -- (1.0.0) the dungeon's boss list: a skull button with the count of numbered bosses, after the buttons
    local bb, page = D.bossBtn, CurrentPage()
    local dun = page and page.kind == "floor" and page.dun
    local showB = bb and dun and ns.Bosses and ns.Bosses:HasList(dun) and true or false
    if bb then
        if showB then
            if bb.dun ~= dun then
                bb.dun = dun
                bb:SetText(("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:14:14|t %d"):format(ns.Bosses:NumberedCount(dun)))
            end
            if bb.left ~= left then
                bb:ClearAllPoints()
                bb:SetPoint("LEFT", left, "RIGHT", 6, 0)
                bb.left = left
            end
            left = bb
        end
        bb:SetShown(showB)
    end
    if D.titleLeft ~= left then
        D.title:ClearAllPoints()
        D.title:SetPoint("LEFT", left, "RIGHT", 12, 0)
        D.title:SetPoint("RIGHT", D.bar, "RIGHT", -(D.titleRight or 222), 0) -- (1.0.0: Whereabouts.lua's chip)
        D.titleLeft = left
    end
end

local function RefreshBar()
    local page = CurrentPage()
    if not page or not D.bar then return end
    RefreshUp()
    D.title:SetText(page.place or D.book.title or "")
    local many = #D.book.pages > 1
    if D.dd then
        D.dd:SetShown(many)
        if many then D.dd:GenerateMenu() end
    elseif D.prev then
        D.prev:SetShown(many)
        D.next:SetShown(many)
        D.floorText:SetShown(many)
        D.floorText:SetText(page.name or "")
    end
end

local function BackText()
    if GetLocale and GetLocale() ~= "enUS" and GlobalString("WORLD") then return GlobalString("WORLD") end
    return "World Map"
end

local function SmallButton(parent, text, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(24, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function BuildBar(dv)
    local bar = CreateFrame("Frame", nil, dv)
    ns.SetLevelFixed(bar, VIEW_LEVEL + 6)
    bar:SetPoint("TOPLEFT", dv, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", dv, "TOPRIGHT", 0, 0)
    bar:SetHeight(BAR_H)
    local shade = bar:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints(bar)
    shade:SetColorTexture(0.075, 0.065, 0.05, 0.96)
    local rule = bar:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    rule:SetHeight(1)
    rule:SetColorTexture(0.62, 0.5, 0.26, 0.7)
    D.bar, D.shade, D.rule = bar, shade, rule

    -- (x 40: right of Blizzard's 32 px tracking-pin button at the canvas' top left)
    local back = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    back:SetSize(110, 22)
    back:SetPoint("TOPLEFT", bar, "TOPLEFT", 40, -4)
    FitButton(back, BackText())
    back:SetScript("OnClick", function() Dungeon:Exit() end)
    D.back = back

    local up = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    up:SetSize(110, 22)
    up:SetPoint("LEFT", back, "RIGHT", 6, 0)
    up:SetScript("OnClick", function() Dungeon:Back() end)
    up:Hide()
    D.up = up

    -- (same slot as up: a hub's other level)
    local lvl = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    lvl:SetSize(110, 22)
    lvl:SetPoint("LEFT", back, "RIGHT", 6, 0)
    lvl:SetScript("OnClick", function(self)
        if not (self.link and Dungeon:FollowLink(self.link)) then return end
        -- (the page changed under the hovered button - RefreshBar ran in ShowPage: its tooltip describes the new link)
        if self.link and self.IsMouseOver and self:IsMouseOver() then ShowTip(LinkTip(self.link)) else HideTip() end
    end)
    lvl:SetScript("OnEnter", function(self)
        if not (self.link and D.active) then return end
        SetHotIcon(nil)
        SetHotLink(nil)
        ShowTip(LinkTip(self.link))
    end)
    lvl:SetScript("OnLeave", function() if not (D.hotIcon or D.hotLink) then HideTip() end end)
    lvl:Hide()
    D.lvl = lvl

    -- (1.0.0) the boss list (DungeonBosses.lua): hover = every boss of the dungeon, click = markers on / off
    local bb = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    bb:SetSize(46, 22)
    bb:SetScript("OnEnter", function(self)
        if not (self.dun and D.active and ns.Bosses) then return end
        SetHotIcon(nil)
        SetHotLink(nil)
        SetHotBoss(nil)
        local t = ns.Bosses:ListTip(self.dun, DungeonName(self.dun))
        if t then ShowTip(t) end
    end)
    bb:SetScript("OnLeave", function() if not (D.hotIcon or D.hotLink or D.hotBoss) then HideTip() end end)
    bb:SetScript("OnClick", function(self)
        Dungeon:ToggleBosses()
        if self.dun and ns.Bosses and self.IsMouseOver and self:IsMouseOver() then ShowTip(ns.Bosses:ListTip(self.dun, DungeonName(self.dun))) end
    end)
    bb:Hide()
    D.bossBtn = bb

    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    D.title = title
    RefreshUp()

    -- Floor picker: Blizzard's own dropdown (as its floor dropdown,
    -- Blizzard_WorldMapTemplates.lua), else plain prev / next buttons.
    local ok, dd = pcall(CreateFrame, "DropdownButton", nil, bar, "WowStyle1DropdownTemplate")
    if ok and dd and dd.SetupMenu and dd.GenerateMenu then
        dd:SetWidth(200)
        dd:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -8, -3)
        dd:SetupMenu(MenuGenerator)
        dd:Hide()
        D.dd = dd
    else
        if ok and dd and dd.Hide then dd:Hide() end
        D.next = SmallButton(bar, ">", function() Dungeon:Step(1) end)
        D.next:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -8, -4)
        D.floorText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        D.floorText:SetPoint("RIGHT", D.next, "LEFT", -6, 0)
        D.floorText:SetWidth(150)
        D.floorText:SetWordWrap(false)
        D.prev = SmallButton(bar, "<", function() Dungeon:Step(-1) end)
        D.prev:SetPoint("RIGHT", D.floorText, "LEFT", -6, 0)
    end
end

---------------------------------------------------------------------------
-- Player marker
---------------------------------------------------------------------------
local function PollArrow()
    local page = CurrentPage()
    D.arrowOn = false
    if not page then return end
    if ns.Markers and ns.Markers:EngineDrawsPlayer() then return end -- (the engine's own arrow there)
    local x, y, _, inst = PlayerPos()
    if x and inst == page.inst and InRegion(page.f.r, x, y, 0.01) then
        -- (floors often share one region - BRS, SFK, BWL...: not on a floor
        -- other than the one the player's whereabouts point to)
        local f = page.kind == "floor" and not page.f.ov and DetectFloor(page.dun)
        if f and f ~= page.floor then
            -- (unless it is the ov floor - the whole map at a smaller scale never vetoes the arrow, as it never
            -- fades a dot (review) - or both show the same ground: lv, DungeonMapsMM.lua - City of Dalaran's
            -- city / Hillsbrad pages)
            local of = ns.DUNGEON_MAPS[page.dun].f[f]
            if not (of and (of.ov or (of.lv and of.lv == page.f.lv))) then return end
        end
        D.arrowU, D.arrowV = RegionUV(page.f.r, x, y)
        D.arrowOn = true
    end
end

-- (review) An auto-opened map with an ov floor, other than the tram (its own
-- watcher, NiWatch): Half-Pint Tavern's ground carries one area everywhere, so
-- no zone event fires between the camp and the land around it - the floor
-- follows the position at the poll rate (FollowFloor: a floor picked by hand
-- stays while the position points to the same floor).
local function PollFollow()
    local book = D.book
    local dm = book and book.auto and book.inst and ns.DUNGEON_MAPS[book.inst]
    if dm and not dm.ni and HasOv(dm) then Dungeon:FollowFloor(book.inst) end
end

-- Every frame while the player is on the page: the arrow turned to the
-- facing (SetRotation only when it changed), else the round icon.
local function PlaceArrow()
    local show = false
    local mk = D.marker
    if D.arrowOn then
        -- (an arrow that can't be turned would point north whatever the
        -- facing: the round icon then)
        local f = D.arrow.SetRotation and PlayerFacing()
        local want = f and D.arrow or D.dot
        if want ~= mk then
            if mk and D.markerShown then mk:Hide() end
            mk, D.marker, D.markerShown, D.markerX = want, want, false, nil
        end
        if f and D.arrow.SetRotation and (not D.facing or math.abs(f - D.facing) > FACING_EPS) then
            D.arrow:SetRotation(f)
            D.facing = f
        end
        local px, py = ViewXY(D.arrowU, D.arrowV)
        if InArea(px, py) then
            show = true
            if px ~= D.markerX or py ~= D.markerY then
                mk:SetPoint("CENTER", D.dv, "TOPLEFT", px, -py)
                D.markerX, D.markerY = px, py
            end
        end
    end
    if mk and show ~= D.markerShown then
        D.markerShown = show
        mk:SetShown(show)
    end
end

---------------------------------------------------------------------------
-- Per-frame: fades, zoom, drag, fling
---------------------------------------------------------------------------
local function StepZoom(dt)
    local v = D.view
    if v.z == D.targetZ then return false end
    local lz, lt = math.log(v.z), math.log(D.targetZ)
    if math.abs(lt - lz) < 1e-4 then
        v.z = D.targetZ
    else
        v.z = math.exp(lz + (lt - lz) * (1 - math.exp(-dt * ZOOM_RATE)))
    end
    local a = D.anchor
    if a and not (D.press and D.press.dragging) then
        local s = Fit() * v.z
        v.cx = a.ax - (a.mx - D.W / 2) / s
        v.cy = a.ay - (a.my - MidY()) / s
    end
    return true
end

local function StepDrag(dt)
    local p = D.press
    if not p then return false end
    if not IsMouseButtonDown("LeftButton") then
        D.press = nil
        return false
    end
    local mx, my = Cursor()
    if not p.dragging then
        if (mx - p.mx) ^ 2 + (my - p.my) ^ 2 <= DRAG_THRESHOLD * DRAG_THRESHOLD then return false end
        p.dragging = true
        D.anchor = nil
        p.lx, p.ly = mx, my
    end
    local v = D.view
    local s = Fit() * v.z
    v.cx = p.ax - (mx - D.W / 2) / s
    v.cy = p.ay - (my - MidY()) / s
    if dt > 0 then
        D.vel.x = D.vel.x * 0.6 + (mx - p.lx) / dt * 0.4
        D.vel.y = D.vel.y * 0.6 + (my - p.ly) / dt * 0.4
    end
    p.lx, p.ly = mx, my
    return true
end

local function StepFling(dt)
    local vel = D.vel
    if D.press or (vel.x == 0 and vel.y == 0) then return false end
    local v = D.view
    local s = Fit() * v.z
    v.cx = v.cx - vel.x * dt / s
    v.cy = v.cy - vel.y * dt / s
    local k = math.exp(-dt * MOMENTUM_DECAY)
    vel.x, vel.y = vel.x * k, vel.y * k
    if vel.x * vel.x + vel.y * vel.y < 400 then vel.x, vel.y = 0, 0 end
    return true
end

-- After the clamp: the drag grab follows what is under the cursor now
-- (nothing builds up at an edge), and a fling stops there. (The wheel's aim
-- stays: where the picture is narrower than the view it is centred, so the
-- spot pointed at slides aside while zooming in and comes back under the
-- cursor once the picture fills the view.)
local function AfterClamp(bx, by)
    local v = D.view
    local p = D.press
    if p and p.dragging then p.ax, p.ay = ArtAt(p.lx, p.ly) end
    if not p then
        if math.abs(v.cx - bx) > 1e-6 then D.vel.x = 0 end
        if math.abs(v.cy - by) > 1e-6 then D.vel.y = 0 end
    end
end

local function StepFades(dt)
    local f = D.fade
    if f then
        if f.dir > 0 and not LayerLoaded(D.front) and f.wait < LOAD_WAIT then
            f.wait = f.wait + dt
        else
            f.t = f.t + dt
            local a = ns.Smooth(f.t / FADE)
            if f.dir > 0 then
                D.dv:SetAlpha(f.a0 + (1 - f.a0) * a)
                if f.t >= FADE then
                    D.fade = nil
                    TakeCanvas()
                end
            else
                D.dv:SetAlpha(f.a0 * (1 - a))
                if f.t >= FADE then HideView() end
            end
        end
    end
    local x = D.xfade
    if x then
        if not LayerLoaded(x.new) and x.wait < LOAD_WAIT then
            x.wait = x.wait + dt
        else
            x.t = x.t + dt
            local a = ns.Smooth(x.t / FADE)
            x.new:SetAlpha(a)
            x.old:SetAlpha(1 - a)
            D.iconFrame:SetAlpha(a)
            if x.t >= FADE then Dungeon:FinishCrossfade() end
        end
    end
end

local function OnUpdate(_, dt)
    if dt > 0.1 then dt = 0.1 end
    local W, H = D.dv:GetSize()
    local moved = false
    if W and H and (W ~= D.W or H ~= D.H) and W > 0 and H > 0 then
        D.W, D.H = W, H
        moved = true
    end
    if D.active then
        if StepZoom(dt) then moved = true end
        if StepDrag(dt) then moved = true end
        if StepFling(dt) then moved = true end
    end
    if moved then
        local bx, by = D.view.cx, D.view.cy
        ClampView(D.view)
        AfterClamp(bx, by)
        Place(D.front, D.view)
    end
    if moved or D.iconsDirty then PlaceIcons() end
    if ns.Links then ns.Links:Place(ViewXY, InArea, IconScale(), moved) end
    if ns.Bosses then ns.Bosses:Place(ViewXY, InArea, IconScale(), moved) end
    StepFades(dt)
    if not D.dv:IsShown() then return end
    UpdateHover()
    D.pollT = D.pollT - dt
    if D.pollT <= 0 then
        D.pollT = POLL
        PollFollow()
        PollArrow()
        if ns.Markers then ns.Markers:Poll(POLL) end
        if ns.Where then ns.Where:Poll() end -- (1.0.0: the named room, the chip)
    end
    PlaceArrow()
    if ns.Where then ns.Where:Place(moved) end
    if ns.Markers then ns.Markers:Place(ViewXY, InArea) end
end

---------------------------------------------------------------------------
-- Input on the view
---------------------------------------------------------------------------
local function OnMouseDown(_, button)
    if not D.active then return end
    local mx, my = Cursor()
    if button == "LeftButton" then
        -- (a press while the view glides only stops it - as on the world map,
        -- where a press while it moves never reaches a pin sliding under the
        -- cursor - it doesn't open the icon that happens to be there)
        local icon = not Gliding() and IconAt(mx, my) or nil
        -- (not within LINK_GRACE s of a level change: the partner pin lands under the cursor, and the second click
        -- of a double click would go straight back)
        local link = not (icon or Gliding() or (D.linkT and GetTime() - D.linkT < LINK_GRACE)) and ns.Links
            and ns.Links:At(mx, my, IconScale(), BAR_H) or nil
        local boss = not (icon or link or Gliding()) and ns.Bosses and ns.Bosses:At(mx, my, IconScale(), BAR_H) or nil
        D.vel.x, D.vel.y = 0, 0
        local ax, ay = ArtAt(mx, my)
        D.press = { mx = mx, my = my, ax = ax, ay = ay, lx = mx, ly = my, icon = icon, link = link, boss = boss }
    elseif button == "RightButton" then
        D.rpress = { mx = mx, my = my }
    end
end

local function OnMouseUp(_, button)
    if button == "LeftButton" then
        local p = D.press
        D.press = nil
        if p and p.dragging and D.vel.x * D.vel.x + D.vel.y * D.vel.y < 2500 then D.vel.x, D.vel.y = 0, 0 end
        if p and not p.dragging then
            D.vel.x, D.vel.y = 0, 0
            -- (a click - pressed and released on the same portal icon, no drag)
            local ic = p.icon
            if ic and ic.p and D.active and not D.fade and IconAt(Cursor()) == ic then Dungeon:OpenPortal(ic.p) end
            -- (or on the same level-link pin: the other level, that pin's partner under the cursor)
            if p.link and D.active and not D.fade then
                local mx, my = Cursor()
                if ns.Links:At(mx, my, IconScale(), BAR_H) == p.link then Dungeon:FollowLink(p.link, mx, my) end
            end
            -- (1.0.0: or on the same boss / entrance marker)
            if p.boss and D.active and not D.fade then
                local mx, my = Cursor()
                if ns.Bosses:At(mx, my, IconScale(), BAR_H) == p.boss then Dungeon:BossClick(p.boss) end
            end
        end
    elseif button == "RightButton" then
        local p = D.rpress
        D.rpress = nil
        if p and D.active then
            local mx, my = Cursor()
            if (mx - p.mx) ^ 2 + (my - p.my) ^ 2 <= CLICK_DIST_SQ and not Dungeon:Back() then Dungeon:Exit() end
        end
    end
end

local function OnMouseWheel(_, delta)
    if not D.active or delta == 0 then return end
    local mx, my = Cursor()
    if not (D.press and D.press.dragging) then
        local ax, ay = ArtAt(mx, my)
        D.anchor = { mx = mx, my = my, ax = ax, ay = ay }
    end
    D.vel.x, D.vel.y = 0, 0
    local step = (ns.db and ns.db.zoomStep) or 1.3
    D.targetZ = ns.Clamp(D.targetZ * step ^ delta, 1, MAX_ZOOM)
end

---------------------------------------------------------------------------
-- Opening, paging, closing
---------------------------------------------------------------------------

-- Show book at page index. how: "fade" (from the world view at rest),
-- "instant" (the map just opened) - or, when the view is already up, the
-- new book replaces the old one with a floor cross-fade.
function Dungeon:Open(book, index, how)
    if not Available() or not book or not book.pages[1] then return false end
    if not WorldMapFrame:IsShown() then return false end
    -- (a cross-fade only over the world map at rest; while it moves, the
    -- camera stops at once and the view takes over)
    if how ~= "instant" and ns.Core and ns.Core.State() ~= "rest" and not D.active then how = "instant" end
    local page = book.pages[index] or book.pages[1]
    if D.active and D.dv:IsShown() and not D.fade then
        local old = CurrentPage()
        D.book, D.pageIndex = book, nil
        self:ShowPage(page.index, "fade", false, old)
        return true
    end
    D.book, D.pageIndex = book, page.index
    D.xfade = nil
    local L = D.front
    for _, other in ipairs(D.layers) do
        if other ~= L then other:Hide() other:SetAlpha(1) end
    end
    LoadLayer(L, page)
    L:SetAlpha(1)
    L:Show()
    D.view.z, D.view.cx, D.view.cy = 1, ART_W / 2, ART_H / 2
    D.targetZ, D.anchor, D.press, D.rpress = 1, nil, nil, nil
    D.vel.x, D.vel.y = 0, 0
    -- (the view spans the canvas container, which is laid out while the map shows)
    D.W, D.H = WorldMapFrame.ScrollContainer:GetSize()
    D.W, D.H = D.W or 0, D.H or 0
    ClampView(D.view)
    L.s = nil
    Place(L, D.view)
    D.active = true
    if page.kind == "floor" then D.lastFloor[page.dun] = page.floor end
    SetIcons(page)
    if ns.Markers then ns.Markers:SetPage(page) end
    D.iconFrame:SetAlpha(1)
    RefreshBar()
    D.dv:EnableMouse(true)
    D.dv:EnableMouseWheel(true)
    BarMouse(true)
    D.pollT = 0
    D.arrowOn = false
    -- (re-opened while still fading out: fade in from where it is)
    local a0 = (D.dv:IsShown() and D.fade and D.dv:GetAlpha()) or 0
    D.dv:Show()
    if how == "instant" then
        D.fade = nil
        D.dv:SetAlpha(1)
        TakeCanvas()
    else
        D.dv:SetAlpha(a0)
        D.fade = { dir = 1, t = 0, wait = 0, a0 = a0 }
    end
    return true
end

function Dungeon:FinishCrossfade()
    local x = D.xfade
    if not x then return end
    D.xfade = nil
    x.old:Hide()
    x.old:SetAlpha(1)
    x.new:SetAlpha(1)
    D.iconFrame:SetAlpha(1)
end

-- Go to page i of the current book (how: "fade" or "instant"; manual: the
-- user picked it; old: the page shown before, when the book was replaced;
-- view: the view to show it with - else the one carried over from old).
function Dungeon:ShowPage(i, how, manual, old, view)
    local book = D.book
    local page = book and book.pages[i]
    if not page or not D.active then return end
    old = old or CurrentPage()
    if old == page and D.pageIndex == i then return end
    self:FinishCrossfade()
    local v = view or CarryView(old, page, D.view)
    local front = D.front
    if how == "fade" and D.dv:IsVisible() and not D.fade and old then
        local L = (front == D.layers[1]) and D.layers[2] or D.layers[1]
        ns.SetLevelFixed(L, VIEW_LEVEL + 2)
        ns.SetLevelFixed(front, VIEW_LEVEL + 1)
        ns.Quads:Relevel(L)
        ns.Quads:Relevel(front)
        LoadLayer(L, page)
        L:SetAlpha(0)
        L.s = nil
        L:Show()
        D.xfade = { old = front, new = L, t = 0, wait = 0 }
        D.front = L
        D.iconFrame:SetAlpha(0)
    else
        LoadLayer(front, page)
        front:SetAlpha(1)
        front:Show()
        D.iconFrame:SetAlpha(1)
    end
    D.pageIndex = i
    D.view.z, D.view.cx, D.view.cy = v.z, v.cx, v.cy
    D.targetZ, D.anchor = v.z, nil
    D.vel.x, D.vel.y = 0, 0
    D.press = nil -- (a drag held across a floor change would grab the old floor)
    ClampView(D.view)
    Place(D.front, D.view)
    if page.kind == "floor" then D.lastFloor[page.dun] = page.floor end
    -- (picked by hand where the player is: follow again only once the
    -- player's whereabouts point elsewhere)
    if manual and page.kind == "floor" and CurrentInstance() == page.dun then D.detected[page.dun] = DetectFloor(page.dun) end
    SetIcons(page)
    if ns.Markers then ns.Markers:SetPage(page) end
    RefreshBar()
    D.pollT = 0
end

function Dungeon:Step(d)
    if not D.book then return end
    local n = #D.book.pages
    self:ShowPage(((D.pageIndex or 1) - 1 + d) % n + 1, "fade", true)
end

-- A portal icon was clicked: its dungeon's map, on the floor it leads to -
-- in this book if the book has it (a dungeon's own entrance cave), else as a
-- new book whose bar and right-click lead back to this entrance map.
function Dungeon:OpenPortal(p)
    local book = D.book
    if not (book and D.active and p and ns.DUNGEON_MAPS[p.m]) then return false end
    SetHotIcon(nil)
    local i = PageOfFloor(book, p.m, p.f)
    if i then
        self:ShowPage(i, "fade", true)
        return true
    end
    local nb = FloorsBook(p.m)
    local v = D.view
    nb.parent = { book = book, index = D.pageIndex, view = { z = v.z, cx = v.cx, cy = v.cy } }
    return self:Open(nb, PageOfFloor(nb, p.m, p.f) or 1)
end

-- A level link (pin or bar button, DungeonLinks.lua): the hub's other level,
-- cross-faded, at the same zoom, with the linked spot (lk.tx, lk.ty) under the
-- cursor (mx, my: a pin click) or in the middle (the bar button).
function Dungeon:FollowLink(lk, mx, my)
    local book = D.book
    if not (book and D.active and not D.fade and lk) then return false end
    for i, p in ipairs(book.pages) do
        if p.kind == "cave" and p.cave == lk.to then
            SetHotLink(nil)
            local z = D.view.z
            local s = Fit() * z
            local v = { z = z, cx = (lk.tx or 0.5) * ART_W, cy = (lk.ty or 0.5) * ART_H }
            if mx and s > 0 then
                v.cx, v.cy = v.cx - (mx - D.W / 2) / s, v.cy - (my - MidY()) / s
            end
            self:ShowPage(i, "fade", true, nil, v)
            D.linkT = GetTime()
            return true
        end
    end
    return false
end

-- (1.0.0) A boss marker clicked: zoom in about it (as two wheel notches over it, at least 2x); an entrance marker:
-- the entrance map (EntranceGo).
function Dungeon:BossClick(it)
    if not (it and D.active) then return end
    if it.kind == "entrance" then
        if EntranceGo(it, true) then
            SetHotBoss(nil)
            EntranceGo(it)
        end
        return
    end
    local px, py = ViewXY(it.u, it.v)
    D.anchor = { mx = px, my = py, ax = it.u * ART_W, ay = it.v * ART_H }
    D.vel.x, D.vel.y = 0, 0
    local step = (ns.db and ns.db.zoomStep) or 1.3
    D.targetZ = ns.Clamp(math.max(D.targetZ * step * step, 2), 1, MAX_ZOOM)
end

-- (1.0.0) /unroll bosses and the bar's skull button: the markers on / off; the page shown picks them again.
function Dungeon:ToggleBosses(on)
    if on == nil then on = (ns.db and ns.db.bosses == false) and true or false end
    if ns.db then ns.db.bosses = on end
    if ns.Bosses then ns.Bosses:SetShown(on) end
    if D.active then SetIcons(CurrentPage()) end
    return on
end

-- (1.0.0) BOSS_KILL (encounterID, name) / ENCOUNTER_END (encounterID, name, difficulty, size, success): defeated
-- this session (DungeonBosses.lua greys the marker).
function Dungeon:OnBossEvent(event, id, _, _, _, success)
    if not ns.Bosses then return end
    -- (review: a secret success decides nothing - BOSS_KILL still counts)
    local won = event == "ENCOUNTER_END" and type(success) == "number" and not (issecretvalue and issecretvalue(success)) and success == 1
    if event == "BOSS_KILL" or won then
        ns.Bosses:OnEncounter(id)
        -- (the marker under the cursor: its tooltip says so at once)
        local h = D.hotBoss
        if h then ShowTip(ns.Bosses:Tip(h, h.kind == "entrance" and EntranceGo(h, true) or nil)) end
    end
end

-- Back to the entrance map a dungeon was opened from (its level and view as
-- they were). false: there is none.
function Dungeon:Back()
    local par = D.book and D.book.parent
    if not (par and D.active and par.book.pages[par.index]) then return false end
    local old = CurrentPage()
    D.book, D.pageIndex = par.book, nil
    self:ShowPage(par.index, "fade", false, old, par.view)
    return true
end

-- Back to the world map (whatever Blizzard's map shows - it never changed).
function Dungeon:Exit(how)
    if not D.active then return end
    D.active = false
    D.press, D.rpress, D.anchor = nil, nil, nil
    D.vel.x, D.vel.y = 0, 0
    CloseMenu()
    self:FinishCrossfade()
    SetHotIcon(nil)
    SetHotLink(nil)
    if D.unitsTip then
        D.unitsTip = nil
        HideTip()
    end
    D.dv:EnableMouse(false)
    D.dv:EnableMouseWheel(false)
    BarMouse(false)
    GiveCanvas()
    -- (the camera was switched off once the view had faded in; while still
    -- fading in, or after a map change someone made, it's already running)
    if ns.Core and WorldMapFrame:IsShown() and ns.Core.State() == "off" then ns.Core.ResyncFromReal() end
    local a0 = D.dv:GetAlpha()
    if how == "instant" or not D.dv:IsVisible() or a0 <= 0.01 then
        HideView()
    else
        D.fade = { dir = -1, t = 0, wait = 0, a0 = a0 }
    end
end

-- A world-map entrance icon: its entrance map (several dungeons) or its
-- dungeon's map - always the same page, whatever the player's whereabouts.
-- level: the hub level to open on (a ns.DUNGEON_CAVES key: the part of a
-- detail level's art clicked) instead of the hub's default.
function Dungeon:OpenEntrance(key, how, level)
    local book = HubBook(key) or DungeonBook(key)
    if not book then return false end
    local start = book.start
    if level then
        for i, p in ipairs(book.pages) do
            if p.kind == "cave" and p.cave == level then start = i break end
        end
    end
    return self:Open(book, start, how or "fade")
end

-- A dungeon icon on a detail level of the world map (Blackrock Mountain): that
-- dungeon's map, on the floor its portal leads to.
function Dungeon:OpenPortalWorld(p)
    if not (p and ns.DUNGEON_MAPS[p.m]) then return false end
    local book = FloorsBook(p.m)
    return self:Open(book, PageOfFloor(book, p.m, p.f) or 1, "fade")
end

function Dungeon:OpenInstance(id, how)
    local book = InstanceBook(id)
    local f = DetectFloor(id)
    D.detected[id] = f
    return self:Open(book, PageOfFloor(book, id, f or D.lastFloor[id] or 1), how or "instant")
end

-- (1.0.0) Whether what the game says of the player's whereabouts allows floor page of the instance the player is in
-- (DungeonMarkers.lua: the engine arrow on City of Dalaran's pages). PollArrow's rule: a floor the sub-zone names
-- elsewhere vetoes, unless it is the ov floor or shows the same ground (lv); a sz floor needs the sub-zone to name it.
function Dungeon:PlayerOnFloor(page)
    if not (page and page.kind == "floor" and ns.DUNGEON_MAPS[page.dun]) then return true end
    local f = DetectFloor(page.dun)
    if page.f.sz then return f == page.floor end
    if not f or f == page.floor or page.f.ov then return true end
    local of = ns.DUNGEON_MAPS[page.dun].f[f]
    return (of and (of.ov or (of.lv and of.lv == page.f.lv))) and true or false
end

-- The player moved (sub-zone / WMO group): follow to the floor they're on
-- when that changed - a floor picked by hand stays while nothing changes.
function Dungeon:FollowFloor(id)
    if not D.active or not D.book then return end
    -- (ni maps - the Deeprun Tram: a map opened by hand from a city icon stays on its page during the ride)
    local dm = ns.DUNGEON_MAPS[id]
    if dm and dm.ni and not D.book.auto then return end
    local f = DetectFloor(id)
    if not f or f == D.detected[id] then return end
    D.detected[id] = f
    local i = PageOfFloor(D.book, id, f)
    if i and i ~= D.pageIndex then self:ShowPage(i, "fade") end
end

---------------------------------------------------------------------------
-- World map: clickable entrance icons (+ hover, tooltip), map show / hide /
-- change
---------------------------------------------------------------------------
local function ContainerCursor()
    local c = WorldMapFrame.ScrollContainer
    local x, y = GetCursorPosition()
    local s = c:GetEffectiveScale()
    local l, t = c:GetLeft(), c:GetTop()
    if not (l and t and s and s > 0) then return -1, -1 end
    return x / s - l, t - y / s
end

-- A detail level's bare art (Render:DetailAt) stands for its entrance: an
-- item like the entrance icon's (same tooltip, same click), made once.
-- (one per level of it: level = the ns.DUNGEON_CAVES key of the part under
-- the cursor, Render:DetailAt - its tooltip names that level, a click opens it)
local artItems = {}
local function ArtItem(def, level)
    local k = def.id .. ":" .. tostring(level)
    local it = artItems[k]
    if not it then
        it = { entrance = def.entrance, art = true, level = level }
        for _, d in ipairs(ns.INSTANCES or {}) do
            if d[4] == def.entrance then it.minLevel, it.maxLevel = d[6], d[7] end
        end
        artItems[k] = it
    end
    return it
end

local function IconUnderCursor()
    if not Available() or D.active or not ns.Labels or not ns.Core or ns.Core.State() ~= "rest" then return end
    if IsControlKeyDown and IsControlKeyDown() then return end -- (Ctrl-click: Blizzard's waypoint pin)
    local x, y = ContainerCursor()
    local it = ns.Labels:HitTest(x, y)
    if it and it.portal then
        if ns.DUNGEON_MAPS[it.portal.m] then return it end
    elseif it and it.noClick then
        return it -- (1.0.0 Doors.lua: a placeholder / a door without a map - a tooltip, no click)
    elseif it and it.entrance and ns.DUNGEON_ENTRANCES and ns.DUNGEON_ENTRANCES[it.entrance] then
        return it
    end
    local def, level = nil, nil
    if ns.Render and ns.Render.DetailAt then def, level = ns.Render:DetailAt(x, y) end
    if def and def.entrance and ns.DUNGEON_ENTRANCES and ns.DUNGEON_ENTRANCES[def.entrance] then return ArtItem(def, level) end
end

local function SetHot(it)
    if D.hot == it then return end
    D.hot = it
    if ns.Labels then ns.Labels:SetHot(it) end
    if D.hover then D.hover:SetShown(it ~= nil) end
    -- (1.0.0) Doors.lua adds its lines (placeholders, unconfirmed / learned doors, "You are inside ...")
    if it then ShowTip(ns.Doors and ns.Doors:Tip(it, EntranceTip) or EntranceTip(it)) else HideTip() end
end

-- Blizzard asks cursor handlers while the canvas (or a pin) has the mouse
-- (Blizzard_MapCanvas.lua ProcessCursorHandlers), like the waypoint's. Only
-- the bare canvas counts: a pin over an icon takes the click itself.
local function CursorHandler()
    local c = WorldMapFrame.ScrollContainer
    local it = c.IsMouseMotionFocus and c:IsMouseMotionFocus() and IconUnderCursor() or nil
    SetHot(it)
    if it and not it.noClick then return "INTERACT_CURSOR" end
end

-- While an icon is lit: the tooltip follows the cursor; unlight it once the
-- cursor leaves it (the cursor handler isn't asked then).
local function HoverUpdate()
    local it = D.hot
    local c = WorldMapFrame.ScrollContainer
    if it and WorldMapFrame:IsShown() and c.IsMouseMotionFocus and c:IsMouseMotionFocus() and IconUnderCursor() == it then
        MoveTip()
        return
    end
    SetHot(nil)
end

-- Core's canvas click handler at rest (Core.lua OnCanvasClick): a left click
-- on an entrance icon opens its maps. Pins never get here (Blizzard only
-- asks canvas handlers for clicks on the bare canvas).
function Dungeon:OnCanvasClick(button)
    if button ~= "LeftButton" then return false end
    local it = IconUnderCursor()
    if not it or it.noClick then return false end -- (1.0.0: a placeholder / a door without a map opens nothing)
    SetHot(nil)
    -- (1.0.0) the door of the instance the player is in (Doors.lua "you are inside"), switch HERE_OPENS_INSTANCE on (the
    -- default): that instance's own map, as inside (off: the door opens its fixed page, as every entrance icon)
    local inside = it.here and ns.Doors and ns.Doors.HERE_OPENS_INSTANCE and ns.Doors:InsideId()
    if inside and ns.DUNGEON_MAPS[inside] then return self:OpenInstance(inside, "fade") end
    if it.portal then return self:OpenPortalWorld(it.portal) end
    return self:OpenEntrance(it.entrance, "fade", it.level)
end

-- (ni maps - the Deeprun Tram) No zone event fires when the tram leaves the
-- station, so while the world map is open on such a map a light watcher (4 Hz)
-- follows the player: leaving the picture closes the map it opened by itself
-- (never one opened by hand from a city icon), arriving on it opens the map -
-- once per arrival: closed by hand, it stays closed while the player stays.
local NI_POLL = 0.25
local function NiWatch(_, dt)
    D.niT = (D.niT or 0) - (dt or 0)
    if D.niT > 0 then return end
    D.niT = NI_POLL
    local id, dm = NiMap()
    if not (id and Available() and WorldMapFrame:IsShown()) then
        D.niWatch:Hide()
        D.niOn = nil
        return
    end
    local on = OnSomeFloor(dm, id)
    if on == D.niOn then
        -- (no zone event while riding: the map that opened by itself follows the stations / the line)
        if on and D.active and D.book and D.book.auto and D.book.inst == id then Dungeon:FollowFloor(id) end
        return
    end
    D.niOn = on
    if on then
        if not D.active then Dungeon:OpenInstance(id, "fade") end
    elseif D.active and D.book and D.book.auto and D.book.inst == id then
        Dungeon:Exit()
    end
end

local function StartNiWatch()
    local w = D.niWatch
    if not w then return end
    local id, dm = NiMap()
    if id and Available() and WorldMapFrame:IsShown() then
        D.niOn, D.niT = OnSomeFloor(dm, id), NI_POLL
        w:Show()
    elseif w:IsShown() then
        w:Hide()
        D.niOn = nil
    end
end

function Dungeon:OnMapShown()
    if not Available() then return end
    local id = CurrentInstance()
    if id then self:OpenInstance(id, "instant") end
    StartNiWatch()
end

function Dungeon:OnMapHidden()
    SetHot(nil)
    SetHotIcon(nil)
    SetHotLink(nil)
    if D.niWatch and D.niWatch:IsShown() then D.niWatch:Hide() end
    if not D.dv then return end
    D.active = false
    GiveCanvas()
    HideView()
    D.hideGen = (D.hideGen or 0) + 1
    local gen = D.hideGen
    C_Timer.After(RELEASE_DELAY, function()
        if gen == D.hideGen and not WorldMapFrame:IsShown() then ReleaseLayers() end
    end)
end

-- (D8) Inside an instance whose map says keep (DungeonMapsMM.lua: City of
-- Dalaran, Half-Pint Tavern - their cosmetic parent is Eastern Kingdoms), a
-- change of Blizzard's map to exactly the map Blizzard's own automatic changes
-- set is the game's own doing: the view stays. That map is
-- MapUtil.GetDisplayableMapForPlayer() (WorldMapMixin:OnShow,
-- ContentTrackingUtil.OpenMapToTrackable; Blizzard_FrameXMLUtil/Mainline/
-- MapUtil.lua l.75: C_Map.GetBestMapForUnit, up its parents to the first map
-- with art, else C_Map.GetFallbackWorldMapID). Any other map - the parents the
-- nav bar offers too - is the user's: back to the world, as before (review).
local function OwnMapChange()
    local id = CurrentInstance()
    local dm = id and ns.DUNGEON_MAPS[id]
    if not (dm and dm.keep and MapUtil and MapUtil.GetDisplayableMapForPlayer) then return false end
    local ok, m = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
    if not ok or type(m) ~= "number" then return false end
    local own
    ok, own = pcall(MapUtil.GetDisplayableMapForPlayer)
    return ok and type(own) == "number" and not (issecretvalue and issecretvalue(own)) and own == m
end

-- Any other map change we didn't make (we never make one): back to the world.
function Dungeon:OnMapChanged()
    if not D.active then return end
    if not OwnMapChange() then
        self:Exit()
    elseif D.canvasTaken then
        -- (Core has just adopted Blizzard's new map - its own OnMapChanged runs
        -- first: the view keeps the map, as TakeCanvas left it)
        if ns.Core then ns.Core.GoOff() end
        local child = CanvasChild()
        if child and child:GetAlpha() ~= 0 then child:SetAlpha(0) end
    end
end

function Dungeon:OnZoneEvent(event)
    if not Available() or not WorldMapFrame:IsShown() then return end
    local id = CurrentInstance()
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        if id then
            if not (D.active and D.book and D.book.inst == id) then
                self:OpenInstance(id, "instant")
            end
        elseif D.active and D.book and D.book.auto then
            self:Exit()
        end
        StartNiWatch()
        return
    end
    if id and D.active then
        self:FollowFloor(id)
        D.pollT = 0 -- (1.0.0: the lit room follows the sub-zone at once; review: inside only - elsewhere the older timing)
    end
end

-- Core's Refresh (slash commands): true when the view owns the map (Core is
-- off under it). Closed here, or still fading in over the world view: false,
-- so Core applies the setting (/unroll off) to the world view it shows.
function Dungeon:Refresh()
    if not D.active then return false end
    if not Available() then
        self:Exit()
        return false
    end
    return D.canvasTaken == true
end

-- /unroll dungeons turned on: open the map of the dungeon we're in.
function Dungeon:AutoOpen()
    if Available() and not D.active and WorldMapFrame:IsShown() then
        local id = CurrentInstance()
        if id then self:OpenInstance(id, "fade") end
    end
    StartNiWatch()
end

function Dungeon:IsActive() return D.active end

-- /unroll markers: the page shown picks its group markers again.
function Dungeon:RefreshMarkers()
    if D.active and ns.Markers then ns.Markers:SetPage(CurrentPage()) end
end
function Dungeon:Supported() return D.supported end

local function MarkerText()
    if ns.Markers and ns.Markers:EngineDrawsPlayer() then return "the engine's (group widget)" end
    if not D.markerShown then return "hidden" end
    if D.marker == D.arrow then return ("arrow (facing %.2f rad)"):format(D.facing or 0) end
    return "round icon (no facing)"
end

function Dungeon:DebugLine()
    if not D.supported then return "dungeon maps: not available (WoW Forever only)" end
    local page = CurrentPage()
    local x, y, _, inst = PlayerPos()
    local f = PlayerFacing()
    local dv = D.dv
    local where = page and ("%s / %s (%d of %d)"):format(tostring(page.place), tostring(page.name), D.pageIndex, #D.book.pages) or "-"
    if D.book and D.book.parent then where = where .. ", from " .. tostring(D.book.parent.book.title) end
    return ("dungeon maps %s: view %s%s, %s, zoom %.2f, portal icons %d, level links %s, bosses %s, player marker %s, group %s, room %s, position %s, facing %s, in instance %s, view %s level %d alpha %.2f, canvas alpha %.2f"):format(
        Available() and "on" or "off", D.active and "shown" or "hidden", D.fade and (D.fade.dir > 0 and " (fading in)" or " (fading out)") or "",
        where, D.view.z, D.nIcons, ns.Links and ns.Links:DebugText() or "-", ns.Bosses and ns.Bosses:DebugText() or "-", MarkerText(), ns.Markers and ns.Markers:DebugText() or "-",
        ns.Where and ns.Where:DebugText() or "-",
        x and ("%.1f, %.1f on map %s"):format(x, y, tostring(inst)) or "unknown", f and ("%.2f"):format(f) or "unknown",
        tostring(CurrentInstance() or "no"),
        dv and dv:GetFrameStrata() or "?", dv and dv:GetFrameLevel() or 0, dv and dv:GetAlpha() or 0,
        CanvasChild() and CanvasChild():GetAlpha() or -1)
end

---------------------------------------------------------------------------
-- Setup (from Core's Setup, once Blizzard's map exists)
---------------------------------------------------------------------------
local events

-- The player marker: Blizzard's arrow atlas (TextureUtilsDocumentation.lua
-- C_Texture.GetAtlasInfo, MayReturnNothing) else its file, and the round icon.
local function BuildMarker(dv)
    local af = CreateFrame("Frame", nil, dv)
    ns.SetLevelFixed(af, VIEW_LEVEL + 5)
    af:SetAllPoints(dv)
    local arrow = af:CreateTexture(nil, "OVERLAY", nil, 7)
    arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
    local info
    if C_Texture and C_Texture.GetAtlasInfo then
        local ok, i = pcall(C_Texture.GetAtlasInfo, ARROW_ATLAS)
        info = ok and i or nil
    end
    if info and arrow.SetAtlas then arrow:SetAtlas(ARROW_ATLAS, false) else arrow:SetTexture(ARROW_FILE) end
    arrow:Hide()
    local dot = af:CreateTexture(nil, "OVERLAY", nil, 6)
    dot:SetSize(DOT_SIZE, DOT_SIZE)
    dot:SetTexture(DOT_FILE)
    dot:Hide()
    D.arrowFrame, D.arrow, D.dot = af, arrow, dot
end

function Dungeon:Setup()
    if D.built or not WorldMapFrame or not WorldMapFrame.ScrollContainer then return end
    -- (1.4.0: ns.FLAVOR, OneCopy.lua - before 1.4.0 the interface number here, 16000 - 19999) WoW Forever only
    D.supported = ns.FLAVOR == "forever" and type(ns.DUNGEON_MAPS) == "table"
        and type(ns.DUNGEON_ENTRANCES) == "table" and type(ns.DUNGEON_CAVES) == "table"
    if not D.supported then return end

    local container = WorldMapFrame.ScrollContainer
    local dv = CreateFrame("Frame", nil, container)
    ns.SetLevelFixed(dv, VIEW_LEVEL)
    dv:SetAllPoints(container)
    dv:SetClipsChildren(true)
    dv:EnableMouse(true)
    dv:EnableMouseWheel(true)
    dv:Hide()
    D.dv = dv

    local bg = dv:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints(dv)
    bg:SetColorTexture(0.06, 0.05, 0.04, 1)
    D.bg = bg

    D.layers = { NewLayer(dv, VIEW_LEVEL + 1), NewLayer(dv, VIEW_LEVEL + 2) }
    D.front = D.layers[1]

    local icf = CreateFrame("Frame", nil, dv)
    ns.SetLevelFixed(icf, VIEW_LEVEL + 3)
    icf:SetAllPoints(dv)
    D.iconFrame = icf
    if ns.Links then ns.Links:Setup(icf) end -- (level-link pins: on the icon frame, fading with it)
    if ns.Bosses then ns.Bosses:Setup(icf, { wingOf = WingOfFloor }) end -- (1.0.0: boss / entrance markers, same frame)

    BuildMarker(dv)
    if ns.Markers then ns.Markers:Setup(dv, VIEW_LEVEL + 4, BAR_H) end
    BuildBar(dv)
    D.tip = BuildTip()
    if ns.Where then
        -- (1.0.0) the named room + the chip (Whereabouts.lua): what it may use of this file
        ns.Where:Setup({
            D = D, page = CurrentPage, inside = CurrentInstance, pos = PlayerPos, facing = PlayerFacing,
            detect = DetectFloor, floorName = FloorName, dungeonName = DungeonName, viewXY = ViewXY, inArea = InArea,
            tip = ShowTip, untip = function() if not (D.hotIcon or D.hotLink) then HideTip() end end,
            refreshTitle = function() D.titleLeft = nil RefreshUp() end,
            show = function(dun, floor)
                local i = D.book and PageOfFloor(D.book, dun, floor)
                if i then Dungeon:ShowPage(i, "fade", true) end
            end,
        })
    end

    dv:SetScript("OnMouseDown", OnMouseDown)
    dv:SetScript("OnMouseUp", OnMouseUp)
    dv:SetScript("OnMouseWheel", OnMouseWheel)
    dv:SetScript("OnUpdate", OnUpdate)

    D.hover = CreateFrame("Frame")
    D.hover:Hide()
    D.hover:SetScript("OnUpdate", HoverUpdate)

    D.niWatch = CreateFrame("Frame")
    D.niWatch:Hide()
    D.niWatch:SetScript("OnUpdate", NiWatch)

    hooksecurefunc(WorldMapFrame, "OnMapChanged", function() Dungeon:OnMapChanged() end)
    WorldMapFrame:HookScript("OnShow", function() Dungeon:OnMapShown() end)
    WorldMapFrame:HookScript("OnHide", function() Dungeon:OnMapHidden() end)
    if WorldMapFrame.AddCursorHandler then WorldMapFrame:AddCursorHandler(CursorHandler, 100) end

    events = CreateFrame("Frame")
    for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "NEW_WMO_CHUNK" }) do
        events:RegisterEvent(ev)
    end
    -- (1.0.0) defeated bosses (DungeonBosses.lua); pcall: an event a client lacks is simply not registered
    -- (review) and the instance lock again when the game starts its lock dialog (the data of that dialog)
    for _, ev in ipairs({ "BOSS_KILL", "ENCOUNTER_END", "INSTANCE_LOCK_START", "INSTANCE_LOCK_WARNING" }) do pcall(events.RegisterEvent, events, ev) end
    events:SetScript("OnEvent", function(_, event, ...)
        if event == "BOSS_KILL" or event == "ENCOUNTER_END" then Dungeon:OnBossEvent(event, ...) return end
        if event == "INSTANCE_LOCK_START" or event == "INSTANCE_LOCK_WARNING" then
            if ns.Bosses and ns.Bosses.OnLock then ns.Bosses:OnLock(CurrentInstance()) end
            return
        end
        if event == "PLAYER_ENTERING_WORLD" and ns.Bosses then ns.Bosses:ResetKills(CurrentInstance()) end
        Dungeon:OnZoneEvent(event)
    end)

    D.built = true
    if WorldMapFrame:IsShown() then self:OnMapShown() end
end
