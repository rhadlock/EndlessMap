local _, ns = ...

--[[
Group markers on the dungeon view (Dungeon.lua). "Hook and draw": where the
game can draw the player and the group, the game draws them.

  * Open-world pages (an entrance cave, a hub level: instance map 0 or 1 -
    places that lie inside a zone of this client's world map): an addon-made
    UnitPositionFrame, the engine widget behind Blizzard's own world-map group
    pin (Blizzard_SharedMapDataProviders/GroupMembersDataProvider.lua,
    Blizzard_UIPanels_Game/Mainline/UnitPositionFrameTemplates.lua; API:
    Blizzard_APIDocumentationGenerated/FrameAPIUnitPositionFrameDocumentation.lua
    SetUiMapID / AddUnit / ClearUnits / FinalizeUnits), set to the zone around
    the page and laid out so that the zone's rectangle lines up with the page:
    the ENGINE draws the player arrow (turned by itself) and the class-coloured
    party / raid dots, exactly where it draws them on the world map. Sizes as
    GroupMembersDataProviderMixin:GetUnitPinSizesTable (27 / 11 / 8.25 px).
  * (wf12) Pages of an instance that is a copy of Eastern Kingdoms at unchanged
    world coordinates (DungeonMapsMM.lua cp: City of Dalaran, Half-Pint
    Tavern): the same widget on the parent's zone map. Addons get no position
    in instances; the engine does - whether it draws there is its own doing.
  * Inside dungeons (their maps have no uiMap: the engine can't place anyone)
    and wherever the widget is missing or /unroll markers turns it off: dots of
    our own (the same atlas, size and colours) from UnitPosition("partyN" /
    "raidN") - only while the game answers there (a plain number on the page's
    map; nothing, an error or a secret value = no dot). Floors that share one
    region can't tell who is on which (UnitPosition's Z is 0 there): a dot on
    such a floor is faded.
Hovering a dot names the member (our tooltip; the engine widget takes no
mouse, so the view keeps its drag and wheel). Nothing here is protected: it
works the same in combat.
]]

local M = {}
ns.Markers = M

local ARROW = "UI-WorldMapArrow"              -- GroupMembersPinMixin:OnLoad (player)
local BLIP = "WhiteCircle-RaidBlips"          -- UnitPositionFrameMixin:UpdateAppearanceData (party / raid)
local BLIP_PARTY_IN_RAID = "WhiteDotCircle-RaidBlips"
local PLAYER_SIZE, PARTY_SIZE, RAID_SIZE = 27, 11, 11 * 0.75
local SUBLEVEL = 7                            -- UNIT_POSITION_FRAME_DEFAULT_SUBLEVEL
local DOT_FALLBACK = "Interface\\Buttons\\WHITE8X8"
local FADED = 0.45                            -- a dot on a floor that shares its region
local ROSTER_EVERY = 1                        -- s between roster reads (positions: every poll)
local HIT = 7                                 -- px around a dot that name it
local MAX_RAID, MAX_PARTY = 40, 4

local E = {
    units = {}, sig = "",         -- group tokens (not the player), roster signature
    look = {},                    -- [unit] = { size, atlas, r, g, b } (ReadRoster)
    pos = {},                     -- [i] = { unit, u, v, alpha } for the members on this page
    npos = 0,
    dots = {}, rosterT = 0,
    zones = {},                   -- [cave key] = zone layout or false (ZoneFor)
    layouts = {},                 -- [uiMap] = zone layout (ZoneLayout: world rects are static - asked once)
}

---------------------------------------------------------------------------
-- Plain values only (a secret value, a nil or an error = nothing)
---------------------------------------------------------------------------
local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

local function Bool(fn, ...)
    if not fn then return false end
    local ok, v = pcall(fn, ...)
    if not ok or type(v) == "nil" or Secret(v) then return false end -- (type() / issecretvalue first: no compare on a secret)
    return v and true or false
end

local function Exists(u) return Bool(UnitExists, u) end
local function IsPlayer(u) return Bool(UnitIsUnit, u, "player") end

-- (the secret check first: nothing else may touch a secret value, not even v == v)
local function Num(v) return type(v) == "number" and not Secret(v) and v == v end

-- UnitDocumentation.lua UnitPosition: positionX (north), positionY (west), Z, mapID
local function Position(u)
    if not UnitPosition then return end
    local ok, x, y, _, inst = pcall(UnitPosition, u)
    if not ok or not (Num(x) and Num(y) and Num(inst)) then return end
    return x, y, inst
end

-- class colour: UnitClass (UnitDocumentation.lua, classFilename) ->
-- C_ClassColor.GetClassColor (ClassColorDocumentation.lua); white otherwise
local function ClassRGB(u)
    if not (UnitClass and C_ClassColor and C_ClassColor.GetClassColor) then return 1, 1, 1 end
    local ok, _, file = pcall(UnitClass, u)
    if not ok or type(file) ~= "string" or Secret(file) then return 1, 1, 1 end
    local ok2, c = pcall(C_ClassColor.GetClassColor, file)
    if not ok2 or type(c) ~= "table" or not c.GetRGB then return 1, 1, 1 end
    local r, g, b = c:GetRGB()
    if not (Num(r) and Num(g) and Num(b)) then return 1, 1, 1 end
    return r, g, b
end

local function UnitLabel(u)
    if not UnitName then return end
    local ok, name = pcall(UnitName, u)
    if ok and type(name) == "string" and not Secret(name) and name ~= "" then return name end
end

-- Pin size and art of a member, as UnitPositionFrameMixin:UpdateFull picks them.
local function Look(u)
    if E.raid then
        if Bool(UnitInSubgroup, u) then return PARTY_SIZE, E.partyInRaid end
        return RAID_SIZE, BLIP
    end
    return PARTY_SIZE, BLIP
end

-- The group (without the player): raid1..40 in a raid, else party1..4.
local function ReadRoster()
    local units = E.units
    for i = #units, 1, -1 do units[i] = nil end
    E.raid = Exists("raid1")
    local base, n = E.raid and "raid" or "party", E.raid and MAX_RAID or MAX_PARTY
    local sig = {}
    for i = 1, n do
        local u = base .. i
        if Exists(u) and not IsPlayer(u) then
            units[#units + 1] = u
            local r, g, b = ClassRGB(u)
            local size, tex = Look(u)
            local L = E.look[u] or {}
            E.look[u] = L
            L[1], L[2], L[3], L[4], L[5] = size, tex, r, g, b
            sig[#sig + 1] = ("%s:%.3f:%.3f:%.3f:%.2f:%s"):format(u, r, g, b, size, tex)
        end
    end
    local s = table.concat(sig, ",")
    local changed = s ~= E.sig
    E.sig = s
    return changed
end

---------------------------------------------------------------------------
-- Page geometry
---------------------------------------------------------------------------
-- Region r = { minX, minY, maxX, maxY } (world yards): the picture's u, v.
local function RegionUV(r, x, y)
    return (r[4] - y) / (r[4] - r[2]), (r[3] - x) / (r[3] - r[1])
end
local function InRegion(r, x, y, m)
    local u, v = RegionUV(r, x, y)
    return u >= -m and u <= 1 + m and v >= -m and v <= 1 + m, u, v
end

-- uiMap id's rectangle in world yards (MapDocumentation.lua
-- C_Map.GetWorldPosFromMapPos, MayReturnNothing): its top-left corner (0, 0)
-- = (maxX, maxY), bottom-right (1, 1) = (minX, minY), on instance map inst.
local function ZoneRect(id)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local ok, c0, p0 = pcall(C_Map.GetWorldPosFromMapPos, id, CreateVector2D(0, 0))
    local ok2, c1, p1 = pcall(C_Map.GetWorldPosFromMapPos, id, CreateVector2D(1, 1))
    if not (ok and ok2 and p0 and p1 and p0.GetXY and p1.GetXY and Num(c0) and Num(c1) and c0 == c1) then return end
    local X0, Y0 = p0:GetXY()
    local X1, Y1 = p1:GetXY()
    if not (Num(X0) and Num(Y0) and Num(X1) and Num(Y1)) or X0 <= X1 or Y0 <= Y1 then return end
    return c0, X0, Y0, X1, Y1
end

-- (wf12) The continent whose zone maps hold a page (nil: none): an open-world
-- page's own map (0 / 1), or the cosmetic parent of an instance that is a copy
-- of that continent at UNCHANGED world coordinates (DungeonMapsMM.lua cp: City
-- of Dalaran, Half-Pint Tavern - wf12/engine: every ADT tile matches map 0's
-- tile of the same index in heights and placed objects). Inside those
-- instances the game gives addons no position (UnitPosition: nil, nil, nil,
-- id), but the engine widget places units itself - IF the engine puts the
-- instance on its parent's maps (in-game test; if it doesn't, the widget
-- simply draws nothing: never a unit at a wrong spot).
local function LayoutMap(page)
    if not page then return end
    if page.kind == "cave" and (page.inst == 0 or page.inst == 1) then return page.inst end
    local dm = page.kind == "floor" and ns.DUNGEON_MAPS and ns.DUNGEON_MAPS[page.dun]
    if dm and (dm.cp == 0 or dm.cp == 1) and page.inst == page.dun then return dm.cp end
end

-- The instance map the player is on (GetInstanceInfo's 8th return, plain numbers only).
local function PlayerInstance()
    if not GetInstanceInfo then return end
    local ok, _, _, _, _, _, _, _, id = pcall(GetInstanceInfo)
    if ok and Num(id) then return id end
end

-- The map a group member is on: UnitPosition's 4th return, which the game
-- still gives inside instances where x / y are nil (The Hall of Thanes, in
-- game: nil nil nil 3065 - for the player; for party members: in-game test).
-- nil: unknown.
local function UnitMap(u)
    if not UnitPosition then return end
    local ok, _, _, _, inst = pcall(UnitPosition, u)
    if ok and Num(inst) then return inst end
end

-- A page of a cosmetic-parent instance (the widget shows the parent's zone).
local function CpPage(page)
    local li = LayoutMap(page)
    return li ~= nil and li ~= page.inst
end

-- (cp pages) who the widget may show: the player while in this instance,
-- members the game says are on this instance's map. A member outside - in the
-- open world at the same coordinates - is left out: the page is the instance.
local function OnCpMap(page, u)
    if u == "player" then
        -- (2.9.0 / verify_engine V1-V2: City of Dalaran's Underbelly page spans the same world rectangle as the city
        -- page - the player goes on the widget only where the sub-zone allows this floor, PollArrow's rule)
        if PlayerInstance() ~= page.inst then return false end
        return not (ns.Dungeon and ns.Dungeon.PlayerOnFloor) or ns.Dungeon:PlayerOnFloor(page)
    end
    return UnitMap(u) == page.inst
end

local function CpSig(page)
    local s = OnCpMap(page, "player") and "p" or "-"
    for _, u in ipairs(E.units) do s = s .. (OnCpMap(page, u) and "1" or "0") end
    return s
end

-- A zone map for the engine, if id is one of this world map's zones (or
-- cities) on instance map inst: { id, X0, Y0 (top-left), X1, Y1 (bottom-right) }.
-- (asked once per uiMap: ZoneFor runs every poll)
local function ZoneLayout(id, inst, cont)
    local e = Num(id) and ns.maps and ns.maps[id]
    if not (e and (e.mapType == ns.MAPTYPE_ZONE or (cont and e.mapType == ns.MAPTYPE_CONTINENT))) then return end
    local L = E.layouts[id]
    if not L then
        local c, X0, Y0, X1, Y1 = ZoneRect(id)
        if not c then return end
        L = { id = id, c = c, X0 = X0, Y0 = Y0, X1 = X1, Y1 = Y1 }
        E.layouts[id] = L
    end
    if L.c == inst then return L end
end

-- The zone of the page itself (cached per page): the one the game puts the
-- page's centre in (C_Map.GetMapPosFromWorldPos, no override), else the
-- smallest zone of the world map whose rectangle holds the whole page.
local function PageZone(page)
    local key = page.cave or page
    local z = E.zones[key]
    if z ~= nil then return z or nil end
    local r, inst = page.f.r, LayoutMap(page) or page.inst
    local X, Y = (r[1] + r[3]) / 2, (r[2] + r[4]) / 2
    if C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D then
        local ok, id = pcall(C_Map.GetMapPosFromWorldPos, inst, CreateVector2D(X, Y))
        if ok then z = ZoneLayout(id, inst) end
    end
    if not z then
        local cx, cy
        if ns.WorldPosToMap then cx, cy = ns.WorldPosToMap(inst, X, Y) end
        local bestA
        for _, e in ipairs(ns.drawList or {}) do
            if cx and e.mapType == ns.MAPTYPE_ZONE and ns.RectContains(e, cx, cy) then
                local L = ZoneLayout(e.id, inst)
                if L and L.X0 >= r[3] and L.Y0 >= r[4] and L.X1 <= r[1] and L.Y1 <= r[2] then
                    local area = (L.X0 - L.X1) * (L.Y0 - L.Y1)
                    if not bestA or area < bestA then z, bestA = L, area end
                end
            end
        end
    end
    E.zones[key] = z or false
    return z
end

-- The zone whose map the engine places the group on: the player's own map
-- (C_Map.GetBestMapForUnit, MapDocumentation.lua - where Blizzard's world map
-- draws the player) while the player is on this page, else the page's zone.
local function ZoneFor(page)
    local li = LayoutMap(page) or page.inst
    local here
    local x, y, inst = Position("player")
    if x then
        here = inst == page.inst and InRegion(page.f.r, x, y, 0.05)
    elseif li ~= page.inst then
        -- (wf12: in a cosmetic-parent instance the game gives no position - the
        -- player is somewhere in it; the zone the game itself puts the player on
        -- is still the one to use, when it is a zone of the parent continent)
        here = PlayerInstance() == page.inst
    end
    if here and C_Map and C_Map.GetBestMapForUnit then
        local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
        if ok then
            -- (2.9.0: on a cosmetic-parent page also the parent continent itself - verify_engine: Forever's zone rows
            -- filter by area, and these instances' areas are their own, so the game may place the player on the
            -- continent map only)
            local z = ZoneLayout(id, li, li ~= page.inst)
            if z then return z end
        end
    end
    return PageZone(page)
end

---------------------------------------------------------------------------
-- The engine widget
---------------------------------------------------------------------------
local function EngineUnits()
    local f = E.upf
    local page = E.page
    local cp = page and CpPage(page)
    E.cpSig = cp and CpSig(page) or nil
    f:ClearUnits()
    -- (the player's own arrow, turned by the engine: showFacing)
    E.withPlayer = not cp or OnCpMap(page, "player")
    if E.withPlayer then
        f:AddUnit("player", ARROW, PLAYER_SIZE, PLAYER_SIZE, 1, 1, 1, 1, SUBLEVEL, true)
    end
    for _, u in ipairs(E.units) do
        if not cp or OnCpMap(page, u) then
            local L = E.look[u]
            f:AddUnit(u, L[2], L[1], L[1], L[3], L[4], L[5], 1, SUBLEVEL, false)
        end
    end
    f:FinalizeUnits()
end

-- Any error from the widget: it is not used again this session (dots instead).
local function Engine(fn)
    local ok = pcall(fn)
    if not ok then
        E.broken = true
        if E.upf then E.upf:Hide() end
        E.mode = "dots"
    end
    return ok
end

local function Want()
    return E.upf and not E.broken and (ns.db == nil or ns.db.engineMarkers ~= false)
end

---------------------------------------------------------------------------
-- API for Dungeon.lua
---------------------------------------------------------------------------
-- dv = the view, level = frame level, barH = the bar's height (the area below
-- it clips the markers).
local function SetupImpl(self, dv, level, barH)
    if E.dv then return end
    E.dv = dv
    local clip = CreateFrame("Frame", nil, dv)
    ns.SetLevelFixed(clip, level)
    clip:SetPoint("TOPLEFT", dv, "TOPLEFT", 0, -barH)
    clip:SetPoint("BOTTOMRIGHT", dv, "BOTTOMRIGHT", 0, 0)
    clip:SetClipsChildren(true)
    clip:EnableMouse(false)
    E.clip = clip
    -- the engine widget (a frame type of this client: UI.xsd UnitPositionFrame)
    local ok, f = pcall(CreateFrame, "UnitPositionFrame", nil, clip)
    if ok and f and f.SetUiMapID and f.AddUnit and f.ClearUnits and f.FinalizeUnits then
        ns.SetLevelFixed(f, level)
        if f.EnableMouse then f:EnableMouse(false) end
        f:Hide()
        E.upf = f
    end
    local df = CreateFrame("Frame", nil, clip)
    ns.SetLevelFixed(df, level)
    df:SetAllPoints(dv)
    df:EnableMouse(false)
    E.dotFrame = df
    -- atlases (TextureUtilsDocumentation.lua C_Texture.GetAtlasInfo, MayReturnNothing)
    local function Has(a)
        if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
        local ok2, info = pcall(C_Texture.GetAtlasInfo, a)
        return ok2 and info ~= nil
    end
    E.blipAtlas = Has(BLIP)
    E.partyInRaid = Has(BLIP_PARTY_IN_RAID) and BLIP_PARTY_IN_RAID or BLIP
end

-- The page shown (nil: none). Picks the engine widget or our dots.
local function SetPageImpl(self, page)
    E.page, E.zone, E.mode = page, nil, nil
    E.npos, E.rosterT, E.placed, E.frameRect = 0, 0, false, nil
    if not E.dv then return end
    -- (wf12: on a cosmetic-parent instance's page only while the game gives
    -- addons no position there - where it does, our own arrow / dots as 2.8.0)
    if page and LayoutMap(page) and Want() and not (CpPage(page) and Position("player")) then
        local z = ZoneFor(page)
        if z then
            E.zone, E.mode = z, "engine"
            ReadRoster()
            local ok = Engine(function()
                E.upf:SetUiMapID(z.id)
                EngineUnits()
            end)
            if ok then E.upf:Show() end
        end
    end
    if page and not E.mode then E.mode = "dots" end
    if E.mode ~= "engine" and E.upf and E.upf:IsShown() then E.upf:Hide() end
    for _, t in ipairs(E.dots) do if t:IsShown() then t:Hide() end end
end

function M:Mode() return E.mode, E.zone and E.zone.id end
function M:HasPositions() return not E.dead and E.page ~= nil and E.npos > 0 end
function M:EngineDrawsPlayer() return not E.dead and E.mode == "engine" and E.withPlayer ~= false end

-- Every poll (Dungeon.lua POLL): the roster now and then, then the members'
-- positions on this page.
local function PollImpl(self, dt)
    local page = E.page
    if not page then return end
    E.rosterT = E.rosterT - (dt or 0)
    if E.rosterT <= 0 then
        E.rosterT = ROSTER_EVERY
        if ReadRoster() and E.mode == "engine" then Engine(EngineUnits) end
    end
    -- (cp pages, every poll: a member entering / leaving the instance, the player's sub-zone allowing this floor or not)
    if E.mode == "engine" and E.cpSig and CpSig(page) ~= E.cpSig then Engine(EngineUnits) end
    if E.mode == "engine" then
        local z = ZoneFor(page)
        if z and z.id ~= E.zone.id then
            E.zone, E.frameRect = z, nil
            Engine(function() E.upf:SetUiMapID(z.id) end)
        end
    end
    local n = 0
    local dm = page.kind == "floor" and ns.DUNGEON_MAPS[page.dun]
    for _, u in ipairs(E.units) do
        local x, y, inst = Position(u)
        if x and inst == page.inst then
            local on, uu, vv = InRegion(page.f.r, x, y, 0.01)
            if on then
                local a = 1
                if dm then
                    -- (another floor of this dungeon holds the point too: who knows which - unless the two show
                    -- the same ground: lv, DungeonMapsMM.lua)
                    for i, f in ipairs(dm.f) do
                        if i ~= page.floor and not (page.f.ov or f.ov or f.sz or (f.lv and f.lv == page.f.lv)) and InRegion(f.r, x, y, 0) then a = FADED break end
                    end
                end
                n = n + 1
                local p = E.pos[n] or {}
                E.pos[n] = p
                p.unit, p.u, p.v, p.a = u, uu, vv, a
            end
        end
    end
    E.npos = n
    E.placed = false
end

local function Dot(i)
    local t = E.dots[i]
    if not t then
        t = E.dotFrame:CreateTexture(nil, "OVERLAY", nil, 5)
        if E.blipAtlas and t.SetAtlas then t:SetAtlas(BLIP, false) else t:SetTexture(DOT_FALLBACK) end
        t:Hide()
        E.dots[i] = t
    end
    return t
end

-- Every frame: toView(u, v) -> view px, inArea(px, py). Only what changed
-- is re-anchored.
local function PlaceImpl(self, toView, inArea)
    local page = E.page
    if not page then return end
    if E.mode == "engine" then
        local z, r = E.zone, page.f.r
        local u0, v0 = RegionUV(r, z.X0, z.Y0)
        local u1, v1 = RegionUV(r, z.X1, z.Y1)
        local x0, y0 = toView(u0, v0)
        local x1, y1 = toView(u1, v1)
        local fr = E.frameRect
        if not fr or fr[1] ~= x0 or fr[2] ~= y0 or fr[3] ~= x1 or fr[4] ~= y1 then
            fr = fr or {}
            fr[1], fr[2], fr[3], fr[4] = x0, y0, x1, y1
            E.frameRect = fr
            local f = E.upf
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", E.dv, "TOPLEFT", x0, -y0)
            f:SetSize(math.max(x1 - x0, 1), math.max(y1 - y0, 1))
        end
        return
    end
    -- our dots
    local k = 0
    for i = 1, E.npos do
        local p = E.pos[i]
        local px, py = toView(p.u, p.v)
        if inArea(px, py) then
            k = k + 1
            local t = Dot(k)
            local L = E.look[p.unit]
            local size = L and L[1] or PARTY_SIZE
            if t.size ~= size then t:SetSize(size, size) t.size = size end
            local r, g, b = 1, 1, 1
            if L then r, g, b = L[3], L[4], L[5] end
            if t.r ~= r or t.g ~= g or t.b ~= b or t.a ~= p.a then
                t:SetVertexColor(r, g, b, p.a)
                t.r, t.g, t.b, t.a = r, g, b, p.a
            end
            if t.x ~= px or t.y ~= py then
                t:SetPoint("CENTER", E.dv, "TOPLEFT", px, -py)
                t.x, t.y = px, py
            end
            if not t:IsShown() then t:Show() end
            p.px, p.py = px, py
        else
            p.px = nil
        end
    end
    for i = k + 1, #E.dots do
        local t = E.dots[i]
        if t:IsShown() then t:Hide() end
    end
end

-- Names of the members under view point (mx, my), one per line (nil: none).
-- (From the positions the game gave: in engine mode too, where the widget
-- draws them from the same data.)
local function UnitsAtImpl(self, mx, my, toView)
    if not (E.page and mx and my) then return end
    local names
    for i = 1, E.npos do
        local p = E.pos[i]
        local px, py = p.px, p.py
        if E.mode == "engine" and toView then px, py = toView(p.u, p.v) end
        if px and math.abs(mx - px) <= HIT and math.abs(my - py) <= HIT then
            local name = UnitLabel(p.unit)
            if name then
                names = names or {}
                names[#names + 1] = name
            end
        end
    end
    return names
end

-- The API for Dungeon.lua. A failure in here must never break the dungeon
-- view: the markers switch off for the session (the error is reported once).
local function Guard(fn)
    return function(self, ...)
        if E.dead then return end
        local ok, a, b = pcall(fn, self, ...)
        if ok then return a, b end
        E.dead, E.page, E.npos = true, nil, 0
        pcall(function()
            if E.upf then E.upf:Hide() end
            for _, t in ipairs(E.dots) do t:Hide() end
        end)
        if geterrorhandler then geterrorhandler()(a) end
    end
end
M.Setup = Guard(SetupImpl)
M.SetPage = Guard(SetPageImpl)
M.Poll = Guard(PollImpl)
M.Place = Guard(PlaceImpl)
M.UnitsAt = Guard(UnitsAtImpl)

function M:DebugText()
    if E.dead then return "off (error)" end
    if not E.page then return "none" end
    if E.mode == "engine" then
        return ("engine widget on uiMap %s, %d group members, %d on the page"):format(tostring(E.zone and E.zone.id), #E.units, E.npos)
    end
    return ("addon dots, %d group members, %d on the page%s"):format(#E.units, E.npos, E.upf and "" or " (no engine widget)")
end
