--[[
Endless Map - RetailGroup.lua (1.4.0-beta11; retail only: AzerothUnrolled_Standard.toc, after RetailParty.lua)

Your arrow and your group's dots where the add-on draws their maps - the player on 1.4.0-beta9, at the Maelstrom: "cave
locations vs islands is wrong in the maelstrom, making me think the player location and other info wont display
properly". Until 1.4.0-beta10 they were Blizzard's: GroupMembersDataProvider's one pin (a UnitPositionFrame) draws them on
the ONE map Blizzard's canvas shows (Core.lua lines it up with the view), laid out as Blizzard has that map - over Azeroth
the Eastern Kingdoms and Northrend where Blizzard's world map puts them, not at their true shape where the add-on draws
them; at the Maelstrom the places where Blizzard has them, not pulled together (1.4.0-beta7's PORTAL_PACK); and your arrow
on no map that is not yours or above yours - with the view's centre a step past your zone's edge, Blizzard's map is the
neighbour's and your arrow was gone while your zone was still drawn. Here:
  * WHERE: Follow.lua F:Position - the unit's world position (UnitPosition) through the map the tree's world boxes give it
    (RetailSpace.lua NodeForWorldPos: Kezan's own map on Kezan) onto that map's rect in the add-on's layout - the place the
    add-on draws under them, at every zoom, from space down.
  * WHAT: Blizzard's look - your arrow (UI-WorldMapArrow, 27 px, turned to GetPlayerFacing), a member of your party's dot
    (11 px) and a raid member's (8.25 px): WhiteCircle-RaidBlips, your own group's WhiteDotCircle-RaidBlips in a raid, in
    their class colours (GroupMembersDataProvider's unitPinSizes, UnitPositionFrameTemplates.lua UpdateAppearanceData,
    GetUnitColor; 12.1.5, read from the client). A frame over the map (under the "Following" label and the bubbles): above
    every marker, as Blizzard's pin is above its others.
  * BLIZZARD'S PIN while the add-on draws: its units not shown (its own SetShouldShowUnits - no dot, so no name where none
    is drawn), its alpha 0 (its ping too), no mouse; given back as Blizzard has it (UpdateShownUnits, alpha 1, its own
    mouse) when the add-on stands aside - off, Blizzard's map of a dungeon.
  * THE HOVER names the members under the cursor (not you: UnitPositionFrame excludes "player"); THE CLICK is Follow.lua's
    (your arrow or a dot: the map follows them), on these; the ping as the map opens and on Follow.lua's ("you are here")
    is this arrow's.
Nothing protected: plain textures on a plain frame; every unit call through pcall, plain values only.
]]
local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)
if ns.FLAVOR ~= "retail" then return end

local G = {}
ns.RetailGroup = G

local ARROW_ATLAS, ARROW_FILE = "UI-WorldMapArrow", "Interface\\WorldMap\\WorldMapArrow"
local CIRCLE, DOT_CIRCLE = "WhiteCircle-RaidBlips", "WhiteDotCircle-RaidBlips"
local PLAYER_SIZE, PARTY_SIZE, RAID_SIZE = 27, 11, 11 * 0.75
local LEVEL = 9400                 -- (fixed: under the Follow label 9500 and the bubbles 9600, over the map's pins)
local MEMBERS_EVERY = 0.1          -- (s: the members' positions read again; drawn every frame where they were)
local HOVER_PAD = 3                -- (px round a dot that names it)
local PING_FILE = "Interface\\minimap\\UI-Minimap-Ping-Expand"
local PING_SIZE, PING_TIME, PING_LOOPS = 70, 0.5, 2 -- (GroupMembersPinMixin: StartPlayerPing(2, .25), its 70-px ring)
local MAX_RAID, MAX_PARTY = 40, 4

local frame, arrow, ring
local dots = {}                    -- [i] = texture
local members = {}                 -- [i] = { u, x, y, size, atlas, r, g, b } (root units)
local membersAt = -1e9
local shown = {}                   -- [i] = { u, sx, sy, r } the dots drawn this frame (the hover)
local pingT                        -- (s into the ping; nil: none)
local at = {}                      -- (tests: where the arrow was drawn - G.at)
local tip, tipText

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function Num(v) return type(v) == "number" and not Secret(v) and v == v end
local function Str(v) return type(v) == "string" and not Secret(v) and v ~= "" end
local function Bool(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, ...)
    return ok and not Secret(v) and v == true
end

local function Ours()
    local core, db = ns.Core, ns.db
    return db ~= nil and db.enabled ~= false and core ~= nil and core.State ~= nil and core.State() ~= "off"
end

---------------------------------------------------------------------------
-- Blizzard's group pin
---------------------------------------------------------------------------
local hidingPin, hookedPin = false, nil
local pinMouse = {}                -- (the hidden pin's own click / motion state, given back with it)
local UNIT_TYPES = { "player", "party", "raid" }
local function BlizzardPin()
    if not (WorldMapFrame and WorldMapFrame.EnumeratePinsByTemplate) then return end
    local found
    pcall(function()
        for pin in WorldMapFrame:EnumeratePinsByTemplate("GroupMembersPinTemplate") do
            found = pin
            break
        end
    end)
    return found
end
local function KeepHidden(pin, a)
    if hidingPin and a ~= 0 then pin:SetAlpha(0) end
end
local function SyncBlizzard(want)
    if want == hidingPin then return end
    local pin = BlizzardPin()
    if not pin then return end
    hidingPin = want
    if hookedPin ~= pin then
        hookedPin = pin
        hooksecurefunc(pin, "SetAlpha", KeepHidden)
    end
    if want then
        pin:SetAlpha(0)
        if pin.SetShouldShowUnits then
            for _, t in ipairs(UNIT_TYPES) do pcall(pin.SetShouldShowUnits, pin, t, false) end
        end
        -- (and no mouse: a press on the map where it lies is the map's - a click on a dot of this file's, Follow.lua's)
        pinMouse.click = pin.IsMouseClickEnabled and pin:IsMouseClickEnabled()
        pinMouse.motion = pin.IsMouseMotionEnabled and pin:IsMouseMotionEnabled()
        if pin.SetMouseClickEnabled then pcall(pin.SetMouseClickEnabled, pin, false) end
        if pin.SetMouseMotionEnabled then pcall(pin.SetMouseMotionEnabled, pin, false) end
    else
        pin:SetAlpha(1)
        if pin.UpdateShownUnits then pcall(pin.UpdateShownUnits, pin) end
        if pin.SetMouseClickEnabled and pinMouse.click ~= nil then pcall(pin.SetMouseClickEnabled, pin, pinMouse.click) end
        if pin.SetMouseMotionEnabled and pinMouse.motion ~= nil then pcall(pin.SetMouseMotionEnabled, pin, pinMouse.motion) end
    end
end

---------------------------------------------------------------------------
-- The members (read MEMBERS_EVERY)
---------------------------------------------------------------------------
local function ClassRGB(u)
    local ok, _, class = pcall(UnitClass, u)
    if ok and Str(class) then
        if C_ClassColor and C_ClassColor.GetClassColor then
            local ok2, c = pcall(C_ClassColor.GetClassColor, class)
            if ok2 and type(c) == "table" and Num(c.r) and Num(c.g) and Num(c.b) then return c.r, c.g, c.b end
        end
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if type(c) == "table" and Num(c.r) then return c.r, c.g, c.b end
    end
    return 1, 1, 1
end

local function ReadMembers()
    local F = ns.Follow
    local n = 0
    if F then
        local raid = Bool(IsInRaid)
        local base, count = raid and "raid" or "party", raid and MAX_RAID or MAX_PARTY
        for i = 1, count do
            local u = base .. i
            if Bool(UnitExists, u) and not Bool(UnitIsUnit, u, "player") then
                local x, y = F:Position(u)
                if x then
                    -- (UpdateFull: your own group's look in a raid - UnitInSubgroup -, else the raid's)
                    local own = not raid or Bool(UnitInSubgroup, u)
                    n = n + 1
                    local m = members[n] or {}
                    members[n] = m
                    m.u, m.x, m.y = u, x, y
                    m.size = own and PARTY_SIZE or RAID_SIZE
                    m.atlas = (raid and own) and DOT_CIRCLE or CIRCLE
                    m.r, m.g, m.b = ClassRGB(u)
                end
            end
        end
    end
    for i = n + 1, #members do members[i] = nil end
end

---------------------------------------------------------------------------
-- Drawing (every frame the map shows)
---------------------------------------------------------------------------
local function Make()
    if frame or not (WorldMapFrame and WorldMapFrame.ScrollContainer) then return frame end
    local c = WorldMapFrame.ScrollContainer
    frame = CreateFrame("Frame", nil, c)
    frame:SetAllPoints(c)
    frame:EnableMouse(false)
    if ns.SetLevelFixed then ns.SetLevelFixed(frame, LEVEL) else frame:SetFrameLevel(LEVEL) end
    arrow = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    local info
    if C_Texture and C_Texture.GetAtlasInfo then
        local ok, i = pcall(C_Texture.GetAtlasInfo, ARROW_ATLAS)
        if ok then info = i end
    end
    if info and arrow.SetAtlas then arrow:SetAtlas(ARROW_ATLAS, false) else arrow:SetTexture(ARROW_FILE) end
    arrow:SetSize(PLAYER_SIZE, PLAYER_SIZE)
    arrow:Hide()
    ring = frame:CreateTexture(nil, "OVERLAY", nil, 6)
    ring:SetTexture(PING_FILE)
    ring:SetBlendMode("ADD")
    ring:Hide()
    return frame
end

local function Dot(i)
    local t = dots[i]
    if not t then
        t = frame:CreateTexture(nil, "OVERLAY", nil, 5)
        t:Hide()
        dots[i] = t
    end
    return t
end

local function HideAll()
    if not frame then return end
    arrow:Hide()
    ring:Hide()
    for _, t in ipairs(dots) do t:Hide() end
    for i = #shown, 1, -1 do shown[i] = nil end
end

local function Facing()
    if not GetPlayerFacing then return nil end
    local ok, f = pcall(GetPlayerFacing)
    if ok and Num(f) then return f end
end

-- (container px of root point x, y; nil off the map by more than pad)
local function Screen(cam, v, ppx, ppy, x, y, pad)
    local sx, sy = v.W / 2 + (x - cam.x) * ppx, v.H / 2 + (y - cam.y) * ppy
    if sx < -pad or sx > v.W + pad or sy < -pad or sy > v.H + pad then return nil end
    return sx, sy
end

local function Draw(elapsed)
    local core = ns.Core
    local on = Ours()
    SyncBlizzard(on)
    if not on or not (core and core.Cam) or not Make() then
        HideAll()
        return
    end
    local cam, v = core.Cam()
    if not (cam and v and Num(v.W) and v.W > 0) then
        HideAll()
        return
    end
    local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)
    local now = GetTime()
    if now - membersAt >= MEMBERS_EVERY then
        membersAt = now
        ReadMembers()
    end
    local k = 0
    for _, m in ipairs(members) do
        local sx, sy = Screen(cam, v, ppx, ppy, m.x, m.y, m.size)
        if sx then
            k = k + 1
            local t = Dot(k)
            if t.atlas ~= m.atlas then
                t:SetAtlas(m.atlas, false)
                t.atlas = m.atlas
            end
            t:SetSize(m.size, m.size)
            t:SetVertexColor(m.r, m.g, m.b)
            t:ClearAllPoints()
            t:SetPoint("CENTER", frame, "TOPLEFT", sx, -sy)
            t:Show()
            local d = shown[k] or {}
            shown[k] = d
            d.u, d.sx, d.sy, d.r = m.u, sx, sy, m.size / 2
        end
    end
    for i = #shown, k + 1, -1 do shown[i] = nil end
    for i = k + 1, #dots do dots[i]:Hide() end
    local F = ns.Follow
    local x, y
    if F then x, y = F:Position("player") end
    local sx, sy
    if x then sx, sy = Screen(cam, v, ppx, ppy, x, y, PING_SIZE) end
    if sx then
        local f = Facing()
        if arrow.SetRotation then arrow:SetRotation(f or 0) end
        arrow:ClearAllPoints()
        arrow:SetPoint("CENTER", frame, "TOPLEFT", sx, -sy)
        arrow:Show()
        at.sx, at.sy, at.facing = sx, sy, f
        G.at = at -- (tests)
    else
        arrow:Hide()
        G.at = nil
    end
    -- (the ping: a ring growing out of the arrow, PING_LOOPS times)
    if pingT and sx then
        pingT = pingT + (elapsed or 0)
        local loop = pingT / PING_TIME
        if loop >= PING_LOOPS then
            pingT = nil
            ring:Hide()
        else
            local p = loop - math.floor(loop)
            local s = PING_SIZE * (0.3 + 0.7 * p)
            ring:SetSize(s, s)
            ring:SetAlpha(1 - p)
            ring:ClearAllPoints()
            ring:SetPoint("CENTER", frame, "TOPLEFT", sx, -sy)
            ring:Show()
        end
    else
        ring:Hide()
    end
end

-- (Follow.lua: "you are here" - ns.PingPlayer)
function G:Ping()
    pingT = 0
end
ns.PingPlayer = function() G:Ping() end

---------------------------------------------------------------------------
-- The hover: the members under the cursor
---------------------------------------------------------------------------
local function ShowTip(names)
    if not tip then
        tip = CreateFrame("Frame", nil, UIParent)
        if tip.SetFrameStrata then tip:SetFrameStrata("TOOLTIP") end
        local bg = tip:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(tip)
        bg:SetColorTexture(0.04, 0.035, 0.03, 0.94)
        tipText = tip:CreateFontString(nil, "OVERLAY")
        tipText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "")
        tipText:SetTextColor(1, 1, 1)
        tipText:SetPoint("TOPLEFT", tip, "TOPLEFT", 8, -6)
        tipText:SetJustifyH("LEFT")
    end
    tipText:SetText(table.concat(names, "\n"))
    local w, h = tipText:GetStringWidth(), tipText:GetStringHeight()
    if not Num(w) or w <= 0 then w = 120 end
    if not Num(h) or h <= 0 then h = 14 * #names end
    tip:SetSize(w + 16, h + 12)
    tip:ClearAllPoints()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    tip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / s + 14, y / s + 14)
    tip:Show()
end

local function Hover()
    local core = ns.Core
    local names = {}
    if #shown > 0 and core and core.CursorPos and WorldMapFrame.ScrollContainer:IsMouseOver() then
        local cx, cy = core.CursorPos()
        for _, d in ipairs(shown) do
            local r = d.r + HOVER_PAD
            if (cx - d.sx) ^ 2 + (cy - d.sy) ^ 2 <= r * r then
                local ok, n = pcall(UnitName, d.u)
                if ok and Str(n) then names[#names + 1] = n end
            end
        end
    end
    if #names > 0 then ShowTip(names) elseif tip then tip:Hide() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local watch = CreateFrame("Frame")
watch:Hide()
local acc = 0
watch:SetScript("OnUpdate", function(_, elapsed)
    Draw(elapsed)
    acc = acc + (elapsed or 0)
    if acc < 0.05 then return end
    acc = 0
    Hover()
end)
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function(_, event)
    if event == "GROUP_ROSTER_UPDATE" then
        membersAt = -1e9 -- (read again the next frame)
        return
    end
    if not WorldMapFrame then return end
    WorldMapFrame:HookScript("OnShow", function()
        membersAt = -1e9
        watch:Show()
        pingT = 0 -- (Blizzard's pin pings you as its map opens: so does this arrow)
    end)
    WorldMapFrame:HookScript("OnHide", function()
        watch:Hide()
        HideAll()
        pingT = nil
        if tip then tip:Hide() end
    end)
    if WorldMapFrame:IsShown() then watch:Show() end
end)

-- (tests) the members read, the dots drawn, Blizzard's pin hidden
G.T = { members = members, shown = shown, dots = dots, Hiding = function() return hidingPin end,
    Arrow = function() return arrow end, Draw = Draw }
