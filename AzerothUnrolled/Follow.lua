--[[
Azeroth Unrolled - Follow.lua (1.1.0)

Two ways to put a character in the middle of the map (the user, 2026-10-05):
  * Click your own arrow, or a party / raid member's dot, on the world map: the map follows them. It pans with them,
    keeps them centred and changes to the map that can show the view as they cross zones (Core.lua FollowStep). The
    wheel still zooms - about them; dragging the map, clicking a zone, closing the map or clicking them again stops
    it. "Following <name>" shows at the top of the map meanwhile. /unroll follow switches the click off and on.
    (1.3.0) Where they get two views away at once - a portal, a hearthstone, also in the middle of a wheel zoom - the
    map flies to them (Core.lua FollowFar) instead of jumping.
  * The M key (ToggleWorldMap): the map opens on your character at world zoom 14.00 (ns.WorldZoom: 1.00x = the whole
    world map) instead of the game's view of your zone. /unroll openzoom <1-25> sets the zoom, off = the game's view.
    (1.2.0, the user: "lets default following you when you open map") and follows you: /unroll openfollow.
Positions: UnitPosition (UnitDocumentation.lua; plain numbers only - a secret value or an error is no position) on
the continent's own map (C_Map.GetMapPosFromWorldPos with the continent as the override) -> the camera's world units.
Inside instances the game gives no position: nothing to follow there, and M opens as the game does.
Hit test: the arrow and the dots where Blizzard's group pin draws them (27 / 11 / 8.25 px: GroupMembersDataProvider),
with a little room around; the nearest wins. Nothing here is protected: it works the same in combat, where only the
map never changes (Core.lua: the view then stays on the current map).
]]
local _, ns = ...

local F = {}
ns.Follow = F

local PLAYER_HIT, MEMBER_HIT = 16, 10        -- hit radius (container px) of the arrow and of a dot
local CONT_UIMAP = { [0] = 1415, [1] = 1414 } -- UnitPosition's instance -> its continent's map
local LOST_AFTER = 3                          -- seconds without a position before following stops
local OPEN_ZOOM_MIN, OPEN_ZOOM_MAX = 1, 25    -- /unroll openzoom (25: from about 25.7x the view can lie inside a city)
local LABEL_LEVEL = 9500                      -- above the pins and the moving layers, as the zoom readout
local MAX_PARTY, MAX_RAID = 4, 40

local unit, guid, name -- the unit followed (nil: none), its GUID (party tokens move when the group changes), its name
local lostSince
local lastX, lastY     -- where it was at the last Target() (its motion since then goes to the camera as it is)
local hooked = false
local label, labelText

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function Num(v) return type(v) == "number" and not Secret(v) and v == v end
local function Str(v) return type(v) == "string" and not Secret(v) and v ~= "" end

local function Bool(fn, ...)
    if not fn then return false end
    local ok, v = pcall(fn, ...)
    if not ok or type(v) == "nil" or Secret(v) then return false end -- (type() / issecretvalue first: no compare on a secret)
    return v and true or false
end

local function GUID(u)
    if not UnitGUID then return end
    local ok, g = pcall(UnitGUID, u)
    if ok and Str(g) then return g end
end

-- The units that have a dot: raid1..40 in a raid, else party1..4 (without the player).
local function Members()
    local out = {}
    local raid = Bool(UnitExists, "raid1")
    local base, n = raid and "raid" or "party", raid and MAX_RAID or MAX_PARTY
    for i = 1, n do
        local u = base .. i
        if Bool(UnitExists, u) and not Bool(UnitIsUnit, u, "player") then out[#out + 1] = u end
    end
    return out
end

-- Where unit u is, in the camera's world units (nil: unknown - inside an instance, no answer, a secret value).
function F:Position(u)
    if not (UnitPosition and C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D and ns.GetMap) then return end
    local ok, x, y, _, inst = pcall(UnitPosition, u)
    if not ok or not (Num(x) and Num(y) and Num(inst)) then return end
    local cont = CONT_UIMAP[inst]
    local M = cont and ns.GetMap(cont)
    if not M then return end
    local ok2, _, pos = pcall(C_Map.GetMapPosFromWorldPos, inst, CreateVector2D(x, y), cont)
    if not ok2 or type(pos) ~= "table" or not (Num(pos.x) and Num(pos.y)) then return end
    return M.x0 + pos.x * (M.x1 - M.x0), M.y0 + pos.y * (M.y1 - M.y0)
end

-- The unit under container point (sx, sy): your arrow or the nearest dot within its radius (nil: none).
function F:UnitAt(sx, sy)
    local core = ns.Core
    if not (core and core.Cam) then return end
    local cam, v = core.Cam()
    if not (cam and v and v.W and v.W > 0) then return end
    local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)
    local best, bestD
    local function Try(u, r)
        local x, y = self:Position(u)
        if not x then return end
        local dx = v.W / 2 + (x - cam.x) * ppx - sx
        local dy = v.H / 2 + (y - cam.y) * ppy - sy
        local d = dx * dx + dy * dy
        if d <= r * r and (not bestD or d < bestD) then best, bestD = u, d end
    end
    Try("player", PLAYER_HIT)
    for _, u in ipairs(Members()) do Try(u, MEMBER_HIT) end
    return best
end

---------------------------------------------------------------------------
-- The "Following <name>" label
---------------------------------------------------------------------------
local function ShowLabel(show)
    if not show then
        if label then label:Hide() end
        return
    end
    local c = WorldMapFrame and WorldMapFrame.ScrollContainer
    if not c then return end
    if not label then
        label = CreateFrame("Frame", nil, c)
        if ns.SetLevelFixed then ns.SetLevelFixed(label, LABEL_LEVEL) else label:SetFrameLevel(LABEL_LEVEL) end
        label:SetPoint("TOP", c, "TOP", 0, -8)
        label:SetSize(160, 22)
        label:EnableMouse(false)
        local bg = label:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(label)
        bg:SetColorTexture(0, 0, 0, 0.65)
        labelText = label:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        labelText:SetPoint("CENTER", label, "CENTER", 0, 0)
    end
    labelText:SetText("Following " .. (name or "?"))
    local w = labelText:GetStringWidth()
    if type(w) ~= "number" then w = 140 end
    label:SetSize(w + 16, 22)
    label:Show()
end

-- The game's own "you are here" ping on your arrow (GroupMembersPinMixin: StartPlayerPing), as when the map opens.
local function Ping()
    if not (WorldMapFrame and WorldMapFrame.EnumeratePinsByTemplate) then return end
    pcall(function()
        for pin in WorldMapFrame:EnumeratePinsByTemplate("GroupMembersPinTemplate") do
            if pin.StartPlayerPing then pin:StartPlayerPing(1, 0.25) end
        end
    end)
end

---------------------------------------------------------------------------
-- Following
---------------------------------------------------------------------------
function F:Active() return unit ~= nil end
function F:Unit() return unit end
function F:GUID() return guid end -- (1.3.0, PartyBubbles.lua: who is followed, whatever token they have this frame)
function F:LabelText() return label and label:IsShown() and labelText:GetText() or nil end

function F:Start(u, quiet)
    unit, guid, lostSince, lastX, lastY = u, GUID(u), nil, nil, nil
    local ok, n = pcall(UnitName, u)
    name = (u == "player" and "you") or ((ok and Str(n)) and n) or u
    ShowLabel(true)
    if u == "player" and not quiet then Ping() end -- (1.2.0 quiet: M - the game pings your arrow as the map opens)
    if ns.Core and ns.Core.Wake then ns.Core.Wake() end
    if ns.Bubbles then ns.Bubbles:OnFollowChanged() end -- (1.3.0, PartyBubbles.lua: the glow on their bubble)
end

function F:Stop()
    if not unit then return end
    unit, guid, name, lostSince, lastX, lastY = nil, nil, nil, nil, nil, nil
    ShowLabel(false)
    if ns.Bubbles then ns.Bubbles:OnFollowChanged() end -- (1.3.0)
end

-- The token of the unit followed now (a party token moves when someone leaves the group; nil: gone).
local function Token()
    if unit == "player" then return "player" end
    if guid and GUID(unit) == guid then return unit end
    if not guid then return Bool(UnitExists, unit) and unit or nil end
    for _, u in ipairs(Members()) do
        if GUID(u) == guid then return u end
    end
end

-- Where the camera should be (world units), and how far the unit moved since the last call (0, 0 on the first); nil
-- while there is no position. Stops following when the unit is gone, the dungeon view has the map, or no position came
-- for LOST_AFTER seconds.
function F:Target(now)
    if not unit then return end
    if ns.Dungeon and ns.Dungeon.IsActive and ns.Dungeon:IsActive() then
        self:Stop()
        return
    end
    local u = Token()
    if not u then
        self:Stop()
        return
    end
    if u ~= unit then
        unit = u
        if ns.Bubbles then ns.Bubbles:OnFollowChanged() end -- (1.3.0: the same one under a new token - the glow checks)
    end
    local x, y = self:Position(u)
    if x then
        lostSince = nil
        local dx, dy = 0, 0
        if lastX then dx, dy = x - lastX, y - lastY end
        lastX, lastY = x, y
        return x, y, dx, dy
    end
    lostSince = lostSince or now or 0
    if now and now - lostSince > LOST_AFTER then self:Stop() end
end

-- (Core.lua: the canvas click handler at rest) a left click on your arrow or a dot follows them - on the one followed
-- it stops; true = the click is handled (no zone switch under it).
function F:OnCanvasClick(button)
    local db = ns.db
    if button ~= "LeftButton" or not db or db.follow == false then return false end
    local core = ns.Core
    if not (core and core.CursorPos) then return false end
    local sx, sy = core.CursorPos()
    local u = self:UnitAt(sx, sy)
    if not u then return false end
    if unit and (u == unit or Bool(UnitIsUnit, u, unit)) then self:Stop() else self:Start(u) end
    return true
end

---------------------------------------------------------------------------
-- The M key: open on your character
---------------------------------------------------------------------------
local function AfterToggle()
    local db = ns.db
    if not (db and db.enabled and db.openZoom and WorldMapFrame and WorldMapFrame:IsShown()) then return end
    local core = ns.Core
    if not (core and core.JustShown and core.JustShown() and core.JumpToZoom) then return end -- (only when it opened)
    if ns.Dungeon and ns.Dungeon.IsActive and ns.Dungeon:IsActive() then return end
    local x, y = F:Position("player")
    if x and core.JumpToZoom(x, y, db.openZoom) and db.openFollow ~= false then
        F:Start("player", true) -- (1.2.0: and follows you)
    end
end

function F:Setup()
    if not hooked and ToggleWorldMap then
        hooksecurefunc("ToggleWorldMap", AfterToggle)
        hooked = true
    end
end

-- cmd = "follow" | "openzoom" | "openfollow", num = the number typed (or nil), Print = Core's chat printer, arg = the
-- text typed.
function F:Slash(cmd, num, Print, arg)
    local db = ns.db
    if not db then return end
    if cmd == "openfollow" then
        db.openFollow = (db.openFollow == false)
        Print("M opens the map following you: " .. (db.openFollow and "on" or "off")
            .. (db.openFollow and not db.openZoom and " (while M opens the map on you: /unroll openzoom is off)" or ""))
        return
    end
    if cmd == "follow" then
        db.follow = (db.follow == false)
        if not db.follow then self:Stop() end
        Print("click your arrow or a party member on the map to follow them: " .. (db.follow and "on" or "off"))
        return
    end
    if num and num >= OPEN_ZOOM_MIN and num <= OPEN_ZOOM_MAX then
        db.openZoom = num
    elseif arg == "off" or num == 0 then
        db.openZoom = false
    elseif arg == "default" or arg == "reset" or arg == "on" then
        db.openZoom = 14
    elseif arg and arg ~= "" then
        Print(("openzoom: a world zoom between %d and %d (read it with /unroll zoom), default (14) or off"):format(OPEN_ZOOM_MIN, OPEN_ZOOM_MAX))
    end
    if db.openZoom then
        Print(("M opens the map on your character at world zoom %.2fx"):format(db.openZoom))
    else
        Print("M opens the map as the game does (your zone)")
    end
end
