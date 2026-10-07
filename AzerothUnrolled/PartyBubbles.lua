--[[
Azeroth Unrolled - PartyBubbles.lua (1.3.0)

Party bubbles on the world map (the user, 2026-10-06: "small icons, on the upper left hand side of the map. party
member bubbles. if you click one it goes to the person and tracks them, when you hover over the bubble it shows the
zone where they are to the right hand side of the bubble"; then: "in raid only your party. yea a bubble for your self.")

  * A column of round 28 px bubbles in the map's top left corner, directly under Blizzard's map-pin button
    (WorldMapTrackingPinButton: 32 px at TOPLEFT 3, 0 of the canvas container, Camelot/Blizzard_WorldMap.lua:7-10) and
    centred under it: you first, then your party - in a raid only your own group (GetRaidRosterInfo's subgroup, by
    raid index; the raid tokens, not the party ones) - at most five, no gaps. Each is the pin button's art at 7/8
    size, as MapMenu.lua's Dress copies it (Blizzard_WorldMapTemplates.xml:6-59): the minimap's round background, the
    portrait cut round (SetPortraitTexture, UnitDocumentation.lua:571), the gold ring and the blue hover glow; the
    bubble of the character the map follows carries the pin button's own "on" glow (its ActiveTexture). No portrait
    (out of sight, offline, a client without the call): the class icon (groupfinder-icon-class-<class>, in this
    client's atlas table), else a disc in the class colour. Offline or dead: greyed.
  * Hover: a box right of the bubble - the name in its class colour, the zone they are in (C_Map.GetBestMapForUnit;
    in a raid the roster's zone) and what a click does; an addon frame (GameTooltip stays untouched, as MapMenu.lua's
    hover text). Its zone is read again once a second while it shows.
  * Click: the map goes to them - at your zoom (in a flight's arc: the zoom it lands at), at least the zoom M opens
    the map at, no deeper than the wheel goes there - and follows them (Follow:Start at the click: the glow at once).
    (1.3.0: the user on 1.3.0-beta1: "the snap to the player is jaring ... click bubble, zoom out and in, while moving
    propotionally for a nice zoom arc") By a flight, Core's FlyToZoom - to the view JumpToZoom showed at once up to
    1.3.0-beta1 (QuestSafe, in combat on the current map) over StartFly's zoom-and-pan path; the wheel on the way sets
    the zoom it lands at, a drag takes over and stops following, another bubble flies on from where the view is. A
    click on the one followed stops following (a flight to them still lands on them). Nobody to go to (inside an
    instance, no position): nothing moves, the box says so. The glow follows Follow.lua however following starts or
    stops (Follow:Start / Stop call OnFollowChanged), on the one it follows by GUID - not by a party token that a
    roster change has just moved to someone else.
  * Parent WorldMapFrame, frame strata HIGH, as MapMenu.lua's buttons: above the map's pins, the addon's moving layers
    and its mouse catcher. The bubbles take no wheel (it zooms the map under them), and a press on one starts no pan
    (Core.lua pans presses on the bare map only). Hidden with /unroll bubbles off, while the smooth zoom is off (no
    following without it) and while the dungeon view has the map (following stops there; the column would cover the
    left of its picture).
  * Every frame is made once, when the map is set up. The roster and the portraits are read on the game's events
    (GROUP_ROSTER_UPDATE, UNIT_PORTRAIT_UPDATE, PORTRAITS_UPDATED, UNIT_CONNECTION, UNIT_NAME_UPDATE,
    PLAYER_ENTERING_WORLD; UNIT_HEALTH while the column shows, for a death or a resurrection) and whenever the column
    shows: nothing runs per frame at rest.
Nothing here is protected: plain buttons, no secure template, no unit menu; every unit API through pcall, plain values
only (a secret value is no value), and any of them may be missing (an older client, the offline harness).
]]
local _, ns = ...

local B = {}
ns.Bubbles = B

local MAX = 5                    -- you and four more: your party, or your own group of a raid
local SIZE, STEP = 28, 30        -- a bubble (7/8 of the pin button's 32 px), and one top to the next: 2 px apart
local X0, Y0 = 5, -36            -- the first one's top left in the canvas container: under the pin button (0 .. -32),
                                 -- centred on it (its centre x 3 + 16 = 5 + 14)
local LEVEL = 9600               -- fixed: above the Follow label and the zoom readout (9500), whatever the map's strata
local TIP_X = 6                  -- the box: 6 px right of the bubble
local TIP_PAD, TIP_GAP = 8, 3    -- (as Dungeon.lua's tooltip)
local TIP_SIZES = { 12, 11, 10 } -- the name, the zone, what a click does
local ZONE_EVERY = 1             -- seconds: the zone again while the box shows
local MAX_RAID, MAX_PARTY = 40, 4
local DIM = 0.6                  -- offline or dead: greyed, as the caves button while the caves are off

-- (the first four are MapMenu.lua's; the "on" glow is the pin button's ActiveTexture, Blizzard_WorldMapTemplates.xml:50-56)
local ART_BG = "Interface\\Minimap\\UI-Minimap-Background"
local ART_RING = "Interface\\Minimap\\MiniMap-TrackingBorder"
local ART_GLOW = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
local ART_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ART_ON = "Interface\\Minimap\\UI-Minimap-ZoomButton-Toggle"
local CLASS_ATLAS = "groupfinder-icon-class-%s" -- (all nine classes in this client: data/bosses/atlas_scan.json)

local holder, tip, ev
local bubbles, units, lines = {}, {}, {}
local hovered    -- the bubble under the mouse (the box shows)
local tipAcc = 0

---------------------------------------------------------------------------
-- Plain values only (a secret value, a nil or an error = nothing)
---------------------------------------------------------------------------
local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function Num(v) return type(v) == "number" and not Secret(v) and v == v end
local function Str(v) return type(v) == "string" and not Secret(v) and v ~= "" end

-- fn(...) as true / false; def when the API is missing, fails or gives nothing plain
local function Bool(fn, def, ...)
    if not fn then return def end
    local ok, v = pcall(fn, ...)
    if not ok or type(v) == "nil" or Secret(v) then return def end -- (type() / issecretvalue first: no compare on a secret)
    return v and true or false
end

local function Count(fn, hi)
    if not fn then return 0 end
    local ok, n = pcall(fn)
    if not ok or not Num(n) then return 0 end
    return math.max(0, math.min(math.floor(n), hi))
end

local function GUID(u)
    if not (UnitGUID and u) then return end
    local ok, g = pcall(UnitGUID, u)
    if ok and Str(g) then return g end
end

---------------------------------------------------------------------------
-- Who: you, then your party - in a raid your own group
---------------------------------------------------------------------------
local function Subgroup(i)
    if not GetRaidRosterInfo then return end
    local ok, _, _, sub = pcall(GetRaidRosterInfo, i)
    if ok and Num(sub) then return sub end
end

-- Your raid index: UnitInRaid's answer where that raid token is you, else the raid token that is you.
local function MyRaidIndex(n)
    if UnitInRaid then
        local ok, i = pcall(UnitInRaid, "player")
        if ok and Num(i) and i >= 1 and i <= n and Bool(UnitIsUnit, false, "raid" .. i, "player") then return i end
    end
    for i = 1, n do
        if Bool(UnitIsUnit, false, "raid" .. i, "player") then return i end
    end
end

local function Roster()
    wipe(units)
    units[1] = "player"
    if Bool(IsInRaid, false) then
        local n = Count(GetNumGroupMembers, MAX_RAID)
        local me = MyRaidIndex(n)
        local mine = me and Subgroup(me)
        if not mine then return units end
        for i = 1, n do
            if #units >= MAX then break end
            local u = "raid" .. i
            if i ~= me and Subgroup(i) == mine and Bool(UnitExists, false, u) then units[#units + 1] = u end
        end
        return units
    end
    for i = 1, Count(GetNumSubgroupMembers, MAX_PARTY) do
        local u = "party" .. i
        if #units < MAX and Bool(UnitExists, false, u) then units[#units + 1] = u end
    end
    return units
end

---------------------------------------------------------------------------
-- The look of a bubble
---------------------------------------------------------------------------
local function ClassFile(u)
    if not UnitClass then return end
    local ok, _, file = pcall(UnitClass, u)
    if ok and Str(file) then return file end
end

-- class colour: C_ClassColor (ClassColorDocumentation.lua), else RAID_CLASS_COLORS (read only); the map's gold otherwise
local function ClassRGB(file)
    if file and C_ClassColor and C_ClassColor.GetClassColor then
        local ok, c = pcall(C_ClassColor.GetClassColor, file)
        if ok and type(c) == "table" and c.GetRGB then
            local ok2, r, g, b = pcall(c.GetRGB, c)
            if ok2 and Num(r) and Num(g) and Num(b) then return r, g, b end
        end
    end
    local t = file and type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[file]
    if type(t) == "table" and Num(t.r) and Num(t.g) and Num(t.b) then return t.r, t.g, t.b end
    return 1, 0.82, 0
end

-- (an atlas this client may not have is checked first: design-rules.md, "Missing atlases")
local function ClassAtlas(file)
    if not (file and C_Texture and C_Texture.GetAtlasInfo) then return end
    local name = CLASS_ATLAS:format(file:lower())
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    if ok and type(info) == "table" then return name end
end

local function Dim(u) return not Bool(UnitIsConnected, true, u) or Bool(UnitIsDeadOrGhost, false, u) end

local function Paint(b)
    local u, face = b.unit, b.face
    if not u then return end
    local online = Bool(UnitIsConnected, true, u)
    local dim = not online or Bool(UnitIsDeadOrGhost, false, u)
    b.dim = dim -- (UNIT_HEALTH repaints only when this changes)
    if online and Bool(UnitIsVisible, true, u) and SetPortraitTexture and pcall(SetPortraitTexture, face, u) then
        face:SetTexCoord(0, 1, 0, 1) -- (whatever an atlas set before)
    else
        local file = ClassFile(u)
        local atlas = ClassAtlas(file)
        if atlas then face:SetAtlas(atlas) else face:SetColorTexture(ClassRGB(file)) end
    end
    face:SetDesaturated(dim)
    if dim then face:SetVertexColor(DIM, DIM, DIM) else face:SetVertexColor(1, 1, 1) end
end

-- Is unit u the one the map follows? By the GUID Follow.lua keeps: its token is the old one until its next step after
-- the group changed (someone ahead leaving moves party3 to party2, raid indices shift) - and the roster event repaints
-- the column before that. By UnitIsUnit only without GUIDs (never by the token's text).
local function Followed(u)
    local F = ns.Follow
    local f = u and F and F.Unit and F:Unit()
    if not f then return false end
    local fg, g = F.GUID and F:GUID(), GUID(u)
    if fg and g then return g == fg end
    return Bool(UnitIsUnit, false, u, f)
end

local function PaintGlow()
    for i = 1, MAX do
        local b = bubbles[i]
        local on = b:IsShown() and Followed(b.unit)
        if b.glow:IsShown() ~= on then b.glow:SetShown(on) end
    end
end

---------------------------------------------------------------------------
-- The box beside a bubble
---------------------------------------------------------------------------
local function NameOf(u)
    if UnitName then
        local ok, n = pcall(UnitName, u)
        if ok and Str(n) then return n end
    end
    return u == "player" and "You" or "Unknown"
end

local function RaidZone(u)
    local i = GetRaidRosterInfo and tonumber(u:match("^raid(%d+)$") or "")
    if not i then return end
    local ok, _, _, _, _, _, _, zone = pcall(GetRaidRosterInfo, i)
    if ok and Str(zone) then return zone end
end

-- Their uiMap's name (C_Map.GetBestMapForUnit: the player and the party - MapDocumentation.lua:49-63), in a raid the
-- roster's zone, else the map under their position; offline: "Offline".
local function ZoneOf(u)
    if not Bool(UnitIsConnected, true, u) then return "Offline" end
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo then
        local ok, id = pcall(C_Map.GetBestMapForUnit, u)
        if ok and Num(id) then
            local ok2, info = pcall(C_Map.GetMapInfo, id)
            if ok2 and type(info) == "table" and Str(info.name) then return info.name end
        end
    end
    local zone = RaidZone(u)
    if zone then return zone end
    local x, y
    if ns.Follow then x, y = ns.Follow:Position(u) end
    local m = x and ns.DeepestMapAt and ns.DeepestMapAt(x, y)
    if m and Str(m.name) then return m.name end
    if u == "player" and GetRealZoneText then
        local ok, z = pcall(GetRealZoneText)
        if ok and Str(z) then return z end
    end
    return "Zone unknown"
end

local function HintOf(u)
    if Followed(u) then return "Click to stop following" end
    if not (ns.Follow and ns.Follow:Position(u)) then return "Not on the map" end
    return "Click to follow"
end

local function FillTip(b)
    local u = b.unit
    if not (tip and u) then return end
    local texts = { NameOf(u), ZoneOf(u), HintOf(u) }
    local w = 0
    for i = 1, 3 do
        lines[i]:SetText(texts[i])
        local sw = lines[i]:GetStringWidth()
        if type(sw) == "number" and sw > w then w = sw end
    end
    lines[1]:SetTextColor(ClassRGB(ClassFile(u)))
    tip:SetSize(math.max(w, 60) + 2 * TIP_PAD, 2 * TIP_PAD + TIP_SIZES[1] + TIP_SIZES[2] + TIP_SIZES[3] + 2 * TIP_GAP)
    tip:ClearAllPoints()
    tip:SetPoint("LEFT", b, "RIGHT", TIP_X, 0)
end

local function HideTip()
    hovered = nil
    if tip and tip:IsShown() then tip:Hide() end
end

local function ShowTip(b)
    hovered, tipAcc = b, 0
    FillTip(b)
    tip:Show()
end

local function TipUpdate(_, dt)
    tipAcc = tipAcc + (dt or 0)
    if tipAcc < ZONE_EVERY then return end
    tipAcc = 0
    if hovered then FillTip(hovered) end
end

---------------------------------------------------------------------------
-- A click: go to them and follow them (on the one followed: stop)
---------------------------------------------------------------------------
-- The world zoom to show them at: the view's own (where the motion under way ends: Core's LandingVw), at least the one
-- M opens the map at (14 while that is off), and no deeper than the wheel may go there (Core.lua's depth limit:
-- maxZoom past the most detailed map at the point).
local function ZoomFor(x, y)
    local db, core = ns.db, ns.Core
    local z = (Num(db.openZoom) and db.openZoom) or 14
    local cam, v
    if core and core.Cam then cam, v = core.Cam() end
    local world = ns.maps and ns.maps[ns.WORLD_MAP_ID]
    if not (cam and v and Num(v.W) and v.W > 0 and world and ns.WorldZoom and ns.WidthForZoom) then return z end
    local vw = core.LandingVw and core.LandingVw() -- (1.3.0: in a flight's arc, the zoom it lands at)
    local now = ns.WorldZoom(v, (Num(vw) and vw > 0) and vw or cam.vw)
    if Num(now) and now > z then z = now end
    local deep = ns.DeepestMapAt and ns.DeepestMapAt(x, y)
    if deep and Num(db.maxZoom) then
        local lim = ns.WorldZoom(v, ns.WidthForZoom(v, deep, db.maxZoom))
        if Num(lim) and lim > 0 and z > lim then z = lim end
    end
    return z
end

local function Go(b)
    local u, F, core = b.unit, ns.Follow, ns.Core
    local go = core and (core.FlyToZoom or core.JumpToZoom) -- (1.3.0: a flight)
    if not (u and F and go and ns.db) then return end
    if Followed(u) then
        F:Stop()
    else
        local x, y = F:Position(u)
        if x and go(x, y, ZoomFor(x, y)) then F:Start(u, true) end
    end
    if hovered == b then FillTip(b) end
end

---------------------------------------------------------------------------
-- The frames (made once)
---------------------------------------------------------------------------
local function Press(b, down)
    local face = b.face
    face:ClearAllPoints()
    -- (as the map-pin button moves its icon while pressed: MapMenu.lua Press)
    if down then face:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -6) else face:SetPoint("TOPLEFT", b, "TOPLEFT", 6, -5) end
end

local function OnEnter(b) ShowTip(b) end
local function OnLeave(b) if hovered == b then HideTip() end end
local function OnClick(b, button) if button == nil or button == "LeftButton" then Go(b) end end
local function OnDown(b) Press(b, true) end
local function OnUp(b) Press(b, false) end

local function NewBubble(i)
    local b = CreateFrame("Button", nil, holder)
    b:SetSize(SIZE, SIZE)
    b:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -STEP * (i - 1))
    if b.SetFrameStrata then b:SetFrameStrata("HIGH") end
    if b.SetFixedFrameStrata then b:SetFixedFrameStrata(true) end

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(ART_BG)
    bg:SetSize(22, 22)
    bg:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)

    local face = b:CreateTexture(nil, "ARTWORK")
    face:SetSize(18, 18)
    b.face = face
    Press(b, false)
    if b.CreateMaskTexture then
        -- (round, as MapMenu.lua's icons: wrap mode CLAMP, the mask exactly on the portrait)
        local mask = b:CreateMaskTexture()
        mask:SetTexture(ART_MASK, "CLAMP", "CLAMP")
        mask:SetAllPoints(face)
        face:AddMaskTexture(mask)
    end

    local ring = b:CreateTexture(nil, "OVERLAY", nil, 1)
    ring:SetTexture(ART_RING)
    ring:SetSize(47, 47)
    ring:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)

    -- (following them: the pin button's toggled glow, 37 px at its ring's -2, 1 - here 7/8 of it)
    local glow = b:CreateTexture(nil, "OVERLAY", nil, 2)
    glow:SetTexture(ART_ON)
    glow:SetBlendMode("ADD")
    glow:SetSize(32, 32)
    glow:SetPoint("TOPLEFT", ring, "TOPLEFT", -2, 1)
    glow:Hide()
    b.glow = glow

    if b.SetHighlightTexture then b:SetHighlightTexture(ART_GLOW, "ADD") end
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp") end
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", OnLeave)
    b:SetScript("OnClick", OnClick)
    b:SetScript("OnMouseDown", OnDown)
    b:SetScript("OnMouseUp", OnUp)
    b:SetScript("OnHide", OnUp)
    b:Hide()
    return b
end

local function BuildTip()
    tip = CreateFrame("Frame", nil, holder)
    if tip.SetFrameStrata then tip:SetFrameStrata("HIGH") end
    if tip.SetFixedFrameStrata then tip:SetFixedFrameStrata(true) end
    ns.SetLevelFixed(tip, LEVEL + 20)
    tip:EnableMouse(false) -- (a drag over it still reaches the map)
    local edge = tip:CreateTexture(nil, "BACKGROUND", nil, -8)
    edge:SetAllPoints(tip)
    edge:SetColorTexture(0.62, 0.5, 0.26, 0.9)
    local bg = tip:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetPoint("TOPLEFT", tip, "TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", tip, "BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.04, 0.035, 0.03, 0.94)
    local font, y = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", TIP_PAD
    for i = 1, 3 do
        local fs = tip:CreateFontString(nil, "OVERLAY")
        fs:SetFont(font, TIP_SIZES[i], "")
        fs:SetPoint("TOPLEFT", tip, "TOPLEFT", TIP_PAD, -y)
        lines[i] = fs
        y = y + TIP_SIZES[i] + TIP_GAP
    end
    lines[2]:SetTextColor(0.8, 0.8, 0.8)
    lines[3]:SetTextColor(0.6, 0.6, 0.6)
    tip:SetScript("OnUpdate", TipUpdate) -- (only while it shows: the mouse is on a bubble)
    tip:Hide()
end

local function Build()
    local map = WorldMapFrame
    local c = map and map.ScrollContainer
    if holder or not (c and ns.db and ns.SetLevelFixed) then return end
    holder = CreateFrame("Frame", nil, map)
    holder:Hide() -- (shown by Apply; its OnShow reads the roster)
    if holder.SetFrameStrata then holder:SetFrameStrata("HIGH") end
    if holder.SetFixedFrameStrata then holder:SetFixedFrameStrata(true) end
    ns.SetLevelFixed(holder, LEVEL)
    holder:SetPoint("TOPLEFT", c, "TOPLEFT", X0, Y0)
    holder:SetSize(SIZE, SIZE + STEP * (MAX - 1))
    holder:EnableMouse(false)
    for i = 1, MAX do bubbles[i] = NewBubble(i) end
    BuildTip()
    -- (UNIT_HEALTH - a death, a resurrection - only while the column shows: in a group it fires all the time)
    holder:SetScript("OnShow", function()
        if ev then pcall(ev.RegisterEvent, ev, "UNIT_HEALTH") end
        B:Refresh()
    end)
    holder:SetScript("OnHide", function()
        if ev then pcall(ev.UnregisterEvent, ev, "UNIT_HEALTH") end
        HideTip()
    end)
    -- The dungeon view takes the map and gives it back (its Open, Exit; the map closed under it ends it too).
    local D = ns.Dungeon
    if D then
        for _, m in ipairs({ "Open", "Exit", "OnMapHidden" }) do
            if D[m] then hooksecurefunc(D, m, function() B:Apply() end) end
        end
    end
end

---------------------------------------------------------------------------
-- Showing
---------------------------------------------------------------------------
local function Wanted()
    local db = ns.db
    if not db or db.bubbles == false or db.enabled == false then return false end
    return not (ns.Dungeon and ns.Dungeon.IsActive and ns.Dungeon:IsActive())
end

-- The roster -> the bubbles (the column shows: the map opened, a setting, the dungeon view gone; the group changed).
function B:Refresh()
    if not holder then return end
    Roster()
    for i = 1, MAX do
        local b = bubbles[i]
        b.unit = units[i]
        if b.unit then
            Paint(b)
            if not b:IsShown() then b:Show() end
        elseif b:IsShown() then
            b:Hide()
        end
    end
    PaintGlow()
    if hovered then
        if hovered:IsShown() then FillTip(hovered) else HideTip() end
    end
end

-- The settings and the dungeon view -> the column (Options.lua: bubbles, enabled, a reset).
function B:Apply()
    Build()
    if not holder then return end
    local want = Wanted()
    if want and not holder:IsShown() then
        holder:Show()
    elseif not want and holder:IsShown() then
        holder:Hide()
    end
end

-- (Follow.lua Start / Stop) the glow on the bubble of the one followed, the box's line about a click.
function B:OnFollowChanged()
    if not (holder and holder:IsVisible()) then return end
    PaintGlow()
    if hovered then FillTip(hovered) end
end

-- One unit's portrait, connection or name changed (u: the event's unit; nil: all of them).
local function Repaint(u)
    if not Str(u) then
        B:Refresh()
        return
    end
    for i = 1, MAX do
        local b = bubbles[i]
        if b.unit and b:IsShown() and (b.unit == u or Bool(UnitIsUnit, false, b.unit, u)) then
            Paint(b)
            if hovered == b then FillTip(b) end
        end
    end
end

-- (UNIT_HEALTH) someone in the column died or came back to life: greyed or not again. Anyone else's health: a token
-- compare per bubble, no widget call.
local function Health(u)
    if not Str(u) then return end
    for i = 1, MAX do
        local b = bubbles[i]
        if b.unit == u and Dim(u) ~= b.dim then Paint(b) end
    end
end

-- (the harness and /unroll debug) the column, its bubbles, the box; the box's three lines while it shows
function B:Frames() return holder, bubbles, tip end
function B:TipLines()
    if not (tip and tip:IsShown()) then return nil end
    return lines[1]:GetText(), lines[2]:GetText(), lines[3]:GetText()
end

local UNIT_EVENTS = { UNIT_PORTRAIT_UPDATE = true, UNIT_CONNECTION = true, UNIT_NAME_UPDATE = true }

ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
-- (pcall: an event a client lacks is simply not registered)
for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "UNIT_PORTRAIT_UPDATE", "PORTRAITS_UPDATED", "UNIT_CONNECTION", "UNIT_NAME_UPDATE",
    "PLAYER_ENTERING_WORLD" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "UNIT_HEALTH" then -- (the frequent one first; registered only while the column shows)
        Health(arg1)
        return
    end
    -- (never before the login, as Core.lua's Setup)
    if event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and arg1 == "Blizzard_WorldMap" and IsLoggedIn and IsLoggedIn()) then
        B:Apply()
        return
    end
    if event == "ADDON_LOADED" or not (holder and holder:IsVisible()) then return end -- (the column reads it all as it shows)
    if UNIT_EVENTS[event] then Repaint(arg1) else B:Refresh() end
end)
