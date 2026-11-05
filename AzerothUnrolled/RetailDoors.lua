--[[
Endless Map - RetailDoors.lua (1.4.0-beta3; retail only: AzerothUnrolled_Standard.toc, after RetailParty.lua)

The places' names and doors on retail - WoW Forever's labels of cities, dungeon and raid doors and flight masters
(Labels.lua, Data.lua, Doors.lua, Dungeon.lua's door click) on the retail engine, from the places' data
(RetailPlaces.lua: docs/retail-places.md 2 - 3; docs/retail-engine.md 14.6):

  * CITY NAMES in the city style (Labels.lua STYLE.city) at the data's point on the city's home (lp) - a tree city's own
    zone-style name moved and restyled; with the city's own zoom band, as WoW Forever's capitals.
  * DOORS (RETAIL_PLACES.ent, 186): the dungeon's or raid's name and level range (its journal name -
    EJ_GetInstanceInfo -, the data's range) at its door on the place it lies in, under it WoW Forever's diamond (Labels.lua
    STYLE.dungeon / raid) on every one - ((1.4.0-beta10, the player on 1.4.0-beta9: "the instant diamonds are missing for
    most instances") 1.4.0-beta3 - beta9 drew a name only over the 185 Blizzard pins, and Blizzard's map pins the doors of
    the one map it shows: every other zone in view had names without icons; Blizzard's door pins are now hidden -
    RetailPins.lua - ours are the doors everywhere). A door a city map covers shows only while the city's map shows (c);
    a door on a place the game does not show now, not at all. The doors the data has no row for (Midnight's - 28 journal
    instances) come from GetDungeonEntrancesForMap as the maps come near - zones, the Maelstrom's places, cities -,
    matched by journalInstanceID.
  * HUBS ((1.4.0-beta10, WoW Forever's ns.DUNGEON_HUBS; the player: "at that zoom level it's telling me about an instance,
    not brm. that's wrong"): a cave or interior map (RetailCaveData.lua) that holds two doors or more - Blackrock Mountain,
    the Caverns of Time, Maraudon, the Scarlet Monastery's entrance, Uldaman - is ONE door outside,
    the cave's name with the doors' range, at the cave's name point; its doors come with the cave's own map (RetailCaves.lua:
    the city maps' or the caves' switch, Render:DetailAlpha) and the hub gives way meanwhile - WoW Forever's Blackrock
    Mountain (Labels.lua it.detail / it.hideFor). A click on the hub flies in to the cave's map.
  * FLIGHT MASTERS: RetailPins.lua (1.4.0-beta10: every map in view at once, with its picture).
  * THE DOOR CLICK (WoW Forever's: a click on a door opens its dungeon map; G4): a click on one of our door names - or
    our diamond - flies to the door (a zoom-arc flight, Core.lua FlyToView) and then opens the dungeon's map on
    Blizzard's map (WorldMapFrame:SetMapID: the data's dungeon map dm, else EJ_GetInstanceInfo's) - never in combat (the
    click waits for the fight's end), never a map whose quests Blizzard has not cached itself (Core.lua QuestSafe). A
    click on Blizzard's own pin is Blizzard's (the Encounter Journal). The hover: the door lit, its name and range, what
    a click does (an add-on frame - GameTooltip untouched).
  * YOU ARE INSIDE (Doors.lua's marker; G6): inside a dungeon or raid (IsInInstance, GetInstanceInfo's instance map) its
    door is marked with the player's round icon at every zoom, its tooltip says so.
Nothing here writes a Blizzard frame; every unit, map and journal call goes through pcall and takes plain values only.
]]
local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)
if ns.FLAVOR ~= "retail" then return end

local P = ns.RETAIL_PLACES
local Labels = ns.Labels
if type(P) ~= "table" or not (Labels and Labels.Add) then return end

local D = {}
ns.RetailDoors = D

local STYLE = Labels.STYLE

local CITY_YARDS = 3193            -- (a door in a city: shown while the city's map shows - RetailCells.lua's patches)
local HIT_ICON, HIT_PAD = 10, 2    -- (our diamond takes a click 10 px round it; a name its rect and 2 px)
local OPEN_WAIT = 8                -- (a door click's dungeon map waits for the flight this long at most)
local HUB_IN = 0.8                 -- ((1.4.0-beta10) a hub's click lands this much narrower than its cave's switch)
local doors = {}                   -- the door items
local hubs = {}                    -- ((1.4.0-beta10) the hubs' items: one door outside a cave of several)
local known = {}                   -- [journalInstanceID] = true: a door of the data's
local cities = {}                  -- [city entry] = its name's item
local entDone = {}                 -- [map id] = true: Blizzard's doors read
local built = false
local pending                      -- a door click waiting: { it, at, flown }
local hereInst                     -- the instance map the player is inside (nil: outside)

local function Plain(v, kind) return type(v) == kind and not (issecretvalue and issecretvalue(v)) end
local function Num(v) return Plain(v, "number") and v == v end

-- ((1.4.0-beta13) a door no journal instance has - the data's negative j, the Deeprun Tram's: the name of its map)
local function JournalName(j, fallback)
    if Num(j) and j < 0 then
        local J = P.ji and P.ji[j]
        if J and Num(J.nm) and C_Map and C_Map.GetMapInfo then
            local ok, info = pcall(C_Map.GetMapInfo, J.nm)
            if ok and type(info) == "table" and Plain(info.name, "string") and info.name ~= "" then return info.name end
        end
        return fallback
    end
    if EJ_GetInstanceInfo and Num(j) then
        local ok, name = pcall(EJ_GetInstanceInfo, j)
        if ok and Plain(name, "string") and name ~= "" then return name end
    end
    return fallback
end

local function WithRange(name, lv)
    if type(lv) == "table" and Num(lv[1]) and Num(lv[2]) and lv[1] < lv[2] then
        return ("%s |cffb0b0b0(%d-%d)|r"):format(name, lv[1], lv[2]), lv[1], lv[2]
    end
    return name
end

-- One door item at point (fx, fy) of entry z's picture.
local function AddDoor(z, fx, fy, j, jj, kind, bp, name, lv, city)
    local text, lo, hi = WithRange(name, lv)
    local x, y = z.x0 + fx * (z.x1 - z.x0), z.y0 + fy * (z.y1 - z.y0)
    local it = Labels:Add(x, y, text, kind, z)
    if not it then return nil end
    it.door, it.ji, it.jj, it.bp, it.city, it.name = true, j, jj, bp, city, name
    it.minLevel, it.maxLevel = lo, hi
    local J = P.ji and P.ji[j]
    it.dm = J and J.dm
    it.insts = {}
    if J and J.m then it.insts[J.m] = true end
    for _, o in ipairs(jj or {}) do
        local O = P.ji and P.ji[o]
        if O and O.m then it.insts[O.m] = true end
    end
    doors[#doors + 1] = it
    return it
end

---------------------------------------------------------------------------
-- Building the names (after Labels:Build - Core.lua's Setup)
---------------------------------------------------------------------------
local function Build()
    if built then return end
    built = true
    -- city names: the data's point on the home, the city style
    local ids = {}
    for id, c in pairs(P.city or {}) do if c.lab == 1 then ids[#ids + 1] = id end end
    table.sort(ids)
    local byOwner = {}
    for _, it in ipairs(Labels:Items()) do
        if it.owner and (it.kind == "zone" or it.kind == "city") then byOwner[it.owner] = byOwner[it.owner] or it end
    end
    for _, id in ipairs(ids) do
        local c, e = P.city[id], ns.maps[id]
        local h = ns.maps[c.h]
        if e and h and c.lp then
            local x, y = h.x0 + c.lp[1] * (h.x1 - h.x0), h.y0 + c.lp[2] * (h.y1 - h.y0)
            local it = byOwner[e]
            if it then
                it.x, it.y, it.kind = x, y, "city"
                Labels:Moved() -- ((1.4.0-beta16) its grid)
                Labels:SetStyle(it, "city")
            else
                it = Labels:Add(x, y, e.name ~= "" and e.name or nil, "city", e)
            end
            if it then
                it.capital = id
                cities[e] = it
            end
        end
    end
    -- the doors of the data
    for _, r in ipairs(P.ent or {}) do
        local z = ns.maps[r.z]
        known[r.j] = true
        for _, o in ipairs(r.jj or {}) do known[o] = true end
        if z then
            local J = P.ji and P.ji[r.j]
            local name = JournalName(r.j, r.n or (J and J.n) or "?")
            AddDoor(z, r.x, r.y, r.j, r.jj, r.k == "r" and "raid" or "dungeon", r.bp == 1, name, r.lv or (J and J.lv), r.c)
        end
    end
    if ns.RetailCaves then ns.RetailCaves:AddLabels() end
    D:BuildHubs()
    D:CheckInside()
end

-- ((1.4.0-beta10) WoW Forever's hubs - Labels.lua's detail levels, DungeonPortals.lua ns.DUNGEON_HUBS) The doors that lie
-- in one cave or interior map (RetailCaves.lua CV:Caves - any of its levels' rects) are its own: they show with its map
-- (it.detail: Render:DetailAlpha), and where they are two or more the cave is one door outside - its name, the doors'
-- range, the raid's look if one is a raid - at the cave's name point, giving way as its map comes in (it.hideFor). One
-- cave a door: the first that holds it.
local function Inside(c, x, y)
    for _, lv in ipairs(c.levels) do
        if lv.x0 <= x and x <= lv.x1 and lv.y0 <= y and y <= lv.y1 then return true end
    end
    return false
end
-- ((1.4.0-beta13) The doors a cave's rects hold but that do not lie in it: the Master's Cellar lies under Karazhan's tower,
-- its maps' rects and masks over the tower's front gate above it, where Karazhan's and Return to Karazhan's doors are -
-- WMO groups decide that in the game, no rect does. Blizzard pins both doors: they are doors, not a hub named after a cellar)
local NOT_HUB = { [43] = true, [44] = true }
function D:BuildHubs()
    local CV = ns.RetailCaves
    local list = CV and CV.Caves and CV:Caves()
    if not list or #hubs > 0 then return end
    local taken = {}
    -- (a cave drawn on its home's land - one level at least not off it, RetailCaves.lua Level: its doors come with its map)
    local function OnLand(c)
        for _, lv in ipairs(c.levels) do if not lv.ol then return true end end
        return false
    end
    for _, c in ipairs(list) do
        if c.kind == "map" and c.lab and c.name and OnLand(c) and not NOT_HUB[c.id] then
            local own = {}
            for _, it in ipairs(doors) do
                if not taken[it] and not it.city and Inside(c, it.x, it.y) then own[#own + 1] = it end
            end
            if #own >= 2 then
                local lo, hi, raid, insts, names = nil, nil, false, {}, {}
                for _, it in ipairs(own) do
                    taken[it] = true
                    -- ((1.4.0-beta13) it.portal: its icon kept whenever the cave's map shows - WoW Forever's Blackrock
                    -- Mountain, Labels.lua: every door a click target; names placed after them: only three of the
                    -- mountain's seven showed, the others' icons under their neighbours' names)
                    it.detail, it.hub, it.portal = c.key, c, true
                    if it.kind == "raid" then raid = true end
                    if it.minLevel and (not lo or it.minLevel < lo) then lo = it.minLevel end
                    if it.maxLevel and (not hi or it.maxLevel > hi) then hi = it.maxLevel end
                    for m in pairs(it.insts) do insts[m] = true end
                    names[#names + 1] = it.name
                end
                local h = c.h
                local x, y = h.x0 + c.lab[1] * (h.x1 - h.x0), h.y0 + c.lab[2] * (h.y1 - h.y0)
                local text = WithRange(c.name, (lo and hi) and { lo, hi } or nil)
                local it = Labels:Add(x, y, text, raid and "raid" or "dungeon", h)
                if it then
                    it.door, it.hubOf, it.hideFor, it.name, it.insts, it.members = true, c, c.key, c.name, insts, names
                    it.minLevel, it.maxLevel = lo, hi
                    hubs[#hubs + 1] = it
                    doors[#doors + 1] = it
                end
            end
        end
    end
end

-- (as zones come near) Blizzard's doors the data has no row for (Midnight's)
local function LoadEntrances(z)
    entDone[z.id] = true
    local EJ = C_EncounterJournal
    if not (EJ and EJ.GetDungeonEntrancesForMap) then return end
    local ok, list = pcall(EJ.GetDungeonEntrancesForMap, z.id)
    if not ok or type(list) ~= "table" then return end
    for _, en in ipairs(list) do
        local j = type(en) == "table" and en.journalInstanceID
        local pos = type(en) == "table" and en.position
        if Num(j) and not known[j] and pos then
            local px, py
            if pos.GetXY then
                local ok2, a, b = pcall(pos.GetXY, pos)
                if ok2 then px, py = a, b end
            else
                px, py = pos.x, pos.y
            end
            if Num(px) and Num(py) and px >= 0 and px <= 1 and py >= 0 and py <= 1 then
                known[j] = true
                local J = P.ji and P.ji[j]
                local name = Plain(en.name, "string") and en.name ~= "" and en.name or JournalName(j, J and J.n or "?")
                AddDoor(z, px, py, j, nil, (J and J.k == "r") and "raid" or "dungeon", true, name, J and J.lv, nil)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Every frame Labels draws (a post-hook: what it changes shows from the next frame)
---------------------------------------------------------------------------
local walkT = -1e9
local function AfterDraw(_, cam, v)
    if not built then Build() end
    if not (cam and v and v.W and v.W > 0) then return end
    -- (Blizzard's doors not in the data, of every map in the view zoomed in - ((1.4.0-beta10) not only the zone the view's
    -- centre lies in: every zone, the Maelstrom's places, the cities on the screen)
    local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)
    local hx, hy = v.W / 2 / ppx, v.H / 2 / ppy
    -- ((1.4.0-beta15) at most ten times a second, and always at the rest: a walk over every map of the tree)
    local now = GetTime()
    if now - walkT >= 0.1 or (ns.Core and ns.Core.Settled and ns.Core.Settled()) then
        walkT = now
        local read = 0
        for _, e in ipairs(ns.SpaceAll or ns.drawList or {}) do
            if not entDone[e.id] and (e.kind == "zone" or e.kind == "inset") and not e.spaceHidden
                and e.x0 <= cam.x + hx and cam.x - hx <= e.x1 and e.y0 <= cam.y + hy and cam.y - hy <= e.y1
                and ns.ZoomOf(v, e, cam.vw) >= 0.3 then
                -- ((1.4.0-beta16) three a go, the next draw the next: at rest it asks for one - each a read of the journal)
                if read >= 3 then
                    if ns.Core and ns.Core.Redraw then ns.Core.Redraw() end
                    break
                end
                LoadEntrances(e)
                read = read + 1
            end
        end
    end
    -- (a door a city map covers: while the city's map shows - the view as narrow as the city's switch)
    for _, it in ipairs(doors) do
        if it.city then
            local c = ns.maps[it.city]
            local show = false
            if c and c.yw and c.x1 > c.x0 then
                show = (v.W / ppx) / (c.x1 - c.x0) * c.yw <= CITY_YARDS
            end
            it.off = not show or nil
        end
    end
end

---------------------------------------------------------------------------
-- You are inside (Doors.lua's marker)
---------------------------------------------------------------------------
function D:CheckInside()
    local inst
    local ok, inside = pcall(IsInInstance)
    if ok and inside == true then
        local ok2, _, _, _, _, _, _, _, id = pcall(GetInstanceInfo)
        if ok2 and Num(id) then inst = id end
    end
    hereInst = inst
    for _, it in ipairs(doors) do
        local here = inst ~= nil and it.insts[inst] == true
        if (it.here == true) ~= here then it.here = here or nil end
    end
end
function D:Inside() return hereInst end

---------------------------------------------------------------------------
-- The door click (Core.lua OnCanvasClick, at rest) and the hover
---------------------------------------------------------------------------
-- The door item at container point (x, y): our diamond (bp 0) round its point, a name by its rect.
function D:HitTest(x, y)
    if not (x and y) then return nil end
    local best, bd
    for _, it in ipairs(doors) do
        if it.shown and it.sx and (it.alpha or 0) >= 0.5 then
            -- ((1.4.0-beta10) every door our diamond: the icon, or its name)
            local hit = (math.abs(x - it.sx) <= HIT_ICON and math.abs(y - it.sy) <= HIT_ICON)
                or (it.x0 and x >= it.x0 - HIT_PAD and x <= it.x1 + HIT_PAD and y >= it.y0 - HIT_PAD and y <= it.y1 + HIT_PAD)
            if hit then
                local d = (x - it.sx) ^ 2 + (y - it.sy) ^ 2
                if not best or d < bd then best, bd = it, d end
            end
        end
    end
    return best
end

-- (home: the view of the click - (1.4.0-beta13) back out of the door's map, the view comes back there: Core.lua SetDoorReturn)
local function Open(it, home)
    if it.hubOf then return false end -- ((1.4.0-beta10) a hub: its cave's map, the flight's landing - no dungeon map)
    local dm = it.dm
    if not Num(dm) and EJ_GetInstanceInfo then
        local ok, _, _, _, _, _, _, area = pcall(EJ_GetInstanceInfo, it.ji)
        if ok and Num(area) and area > 0 then dm = area end
    end
    if not Num(dm) or InCombatLockdown() then return false end
    local core = ns.Core
    if core and core.QuestSafe and not core.QuestSafe(dm) then return false end
    if core and core.SetDoorReturn then core.SetDoorReturn(home, dm) end
    pcall(WorldMapFrame.SetMapID, WorldMapFrame, dm)
    return true
end

local function Fly(it)
    local core = ns.Core
    if not (core and core.FlyToView and core.Cam) then return false end
    local _, v = core.Cam()
    local z = it.owner
    if not (v and z) then return false end
    -- (a view a quarter of its zone wide - as WoW Forever's door flight lands on the entrance)
    local vw = ns.WidthForZoom(v, z, 4)
    -- ((1.4.0-beta10) a hub: into its cave's map - the cave's top level in the middle of a view a little narrower than
    -- its switch (RetailCaves.lua CV:SwitchWidth), where its doors are)
    local c = it.hubOf
    if c and ns.RetailCaves and ns.RetailCaves.SwitchWidth then
        local w = ns.RetailCaves:SwitchWidth(c)
        if w then
            pending.vw = w * HUB_IN
            return core.FlyToView((c.x0 + c.x1) / 2, (c.y0 + c.y1) / 2, w * HUB_IN)
        end
    end
    pending.vw = vw
    return core.FlyToView(it.x, it.y, vw)
end

-- ((1.4.0-beta3, the reviews of 1.4.0-beta3) the camera now, to tell whether it moved since a click in combat)
local function CamNow()
    local core = ns.Core
    local c = core and core.Cam and core.Cam()
    return c and { x = c.x, y = c.y, vw = c.vw } or nil
end
local function Moved(a)
    local b = CamNow()
    if not (a and b and Num(b.vw) and b.vw > 0) then return true end
    return math.abs(a.vw / b.vw - 1) > 0.02 or math.abs(a.x - b.x) > 0.02 * b.vw or math.abs(a.y - b.y) > 0.02 * b.vw
end
-- (the door flight landed: the door in the middle of the view, at about the flight's width - not where a wheel or a drag
-- under way took the camera instead)
local function Landed(p)
    local b = CamNow()
    if not (b and Num(b.vw) and b.vw > 0 and p.vw) then return false end
    return math.abs(p.it.x - b.x) < 0.25 * b.vw and math.abs(p.it.y - b.y) < 0.25 * b.vw and b.vw < p.vw * 1.5 and b.vw > p.vw / 1.5
end

-- (Core.lua OnCanvasClick, at rest) true: the click was ours
function D:OnCanvasClick(button)
    if button ~= "LeftButton" or not ns.Core then return false end
    -- ((1.4.0-beta10) a click no door takes: the flight masters' and the points of interest's - Pins.lua, which Core.lua
    -- asks next (1.6.0: for both games))
    if ns.db and ns.db.dungeonIcons == false then return false end
    local x, y = ns.Core.CursorPos()
    local it = D:HitTest(x, y)
    if not it then return false end
    pending = { it = it, at = GetTime(), cam = CamNow() }
    if InCombatLockdown() then
        pending.combat = true -- (the flight and the map after the fight: PLAYER_REGEN_ENABLED - if the camera stays)
        return true
    end
    pending.flown = Fly(it)
    if not pending.flown then
        Open(it, pending.cam)
        pending = nil
    end
    return true
end

-- the hover: an add-on frame (GameTooltip untouched), the door lit
local tip, tipText, hot
local function ShowTip(it)
    if not tip then
        tip = CreateFrame("Frame", nil, UIParent)
        if tip.SetFrameStrata then tip:SetFrameStrata("TOOLTIP") end
        local bg = tip:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(tip)
        bg:SetColorTexture(0.04, 0.035, 0.03, 0.94)
        tipText = tip:CreateFontString(nil, "OVERLAY")
        tipText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "")
        tipText:SetTextColor(1, 0.82, 0)
        tipText:SetPoint("TOPLEFT", tip, "TOPLEFT", 8, -6)
        tipText:SetJustifyH("LEFT")
    end
    local lines = {}
    if it.here then lines[#lines + 1] = "You are inside " .. tostring(it.name) end
    lines[#lines + 1] = tostring(it.name) .. ((it.minLevel and it.maxLevel) and (" (" .. it.minLevel .. "-" .. it.maxLevel .. ")") or "")
    if it.hubOf then
        -- ((1.4.0-beta10) a hub: the doors inside, a click flies in)
        for _, n in ipairs(it.members or {}) do lines[#lines + 1] = "|cffd0d0d0  " .. tostring(n) .. "|r" end
        lines[#lines + 1] = "|cffffffffClick: fly in|r"
    else
        lines[#lines + 1] = "|cffffffffClick: fly there and open its map|r"
    end
    tipText:SetText(table.concat(lines, "\n"))
    local w, h = tipText:GetStringWidth(), tipText:GetStringHeight()
    if not Num(w) or w <= 0 then w = 180 end
    if not Num(h) or h <= 0 then h = 14 * #lines end
    tip:SetSize(w + 16, h + 12)
    tip:ClearAllPoints()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    tip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / s + 14, y / s + 14)
    tip:Show()
end
local function Hover()
    local core = ns.Core
    local it
    if core and core.Settled and core.Settled() and WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.ScrollContainer
        and WorldMapFrame.ScrollContainer:IsMouseOver() then
        it = D:HitTest(core.CursorPos())
    end
    if it ~= hot then
        hot = it
        Labels:SetHot(it)
        if it then ShowTip(it) elseif tip then tip:Hide() end
    elseif it then
        ShowTip(it)
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- (the hover and a door click's wait: a frame of its own, shown only while the map shows - nothing runs with it closed)
local watch = CreateFrame("Frame")
watch:Hide()
local acc = 0
watch:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc < 0.05 then return end
    acc = 0
    Hover()
    -- (a door click's flight landed: the dungeon's map)
    -- ((1.4.0-beta3, the reviews of 1.4.0-beta3) not after a wheel or a drag on the way, or a click in combat with
    -- the camera moved since: WoW Forever opens the dungeon's map at once - a click that was overtaken by the player's
    -- own motion opened it when the map next rested, or flew back to the door after the fight; four probes on Wailing
    -- Caverns ended on map 279 each)
    local p = pending
    local core = ns.Core
    local st = core and core.State and core.State()
    if p and not p.combat then
        if GetTime() - p.at > OPEN_WAIT or st == "free" or st == "off" then
            pending = nil
        elseif p.flown and (st == "rest" or st == "hold") and GetTime() - p.at > 0.2 then -- ((1.4.0-beta12) held too)
            pending = nil
            if Landed(p) then Open(p.it, p.cam) end
        end
    elseif p and p.combat and ((st ~= "rest" and st ~= "hold") or Moved(p.cam)) then
        pending = nil
    end
end)
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        hooksecurefunc(Labels, "Draw", AfterDraw)
        hooksecurefunc(Labels, "Build", Build)
        if WorldMapFrame then
            WorldMapFrame:HookScript("OnShow", function() watch:Show() end)
            WorldMapFrame:HookScript("OnHide", function()
                watch:Hide()
                pending = nil
                if tip then tip:Hide() end
                hot = nil
            end)
            if WorldMapFrame:IsShown() then watch:Show() end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        local p = pending
        if p and p.combat and WorldMapFrame and WorldMapFrame:IsShown() and GetTime() - p.at < 60 and not Moved(p.cam) then
            watch:Show()
            p.combat, p.at = nil, GetTime()
            p.flown = Fly(p.it)
            if not p.flown then
                pending = nil
                Open(p.it, p.cam)
            end
        else
            pending = nil
        end
    else
        D:CheckInside()
    end
end)

-- (tests) the doors, the cities' names
D.T = { doors = doors, cities = cities, known = known, hubs = hubs }
function D:Pending() return pending end
