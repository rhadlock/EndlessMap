--[[
Endless Map - RetailParty.lua (1.4.0; retail only: AzerothUnrolled_Standard.toc lists it after PartyBubbles.lua)

The party bubbles and following on retail as on WoW Forever (the user, 2026-10-24: "we also need to get ... jumping
between aprty memers working on the retail version, need s to be feture compelte"; docs/retail-engine.md section 13).
Follow.lua and PartyBubbles.lua are shared; what retail needs beyond WoW Forever is here, as hooks they read (nil on WoW
Forever, so it keeps what it has):
  * ns.PartyWhy(u, x, y): the third line of a bubble's box in plain words where WoW Forever's "Not on the map" or
    "Click to follow" would not say what happens - no position for unit u because they are offline, inside an instance
    (the game gives no positions there), on a map the add-on does not draw (a class hall, Darkmoon Island: the placement
    tree has no box for that game map) or the game keeps it secret; with a position (x, y) in combat, when the map shown
    cannot reach them (Core.lua changes no map in combat: it goes to them when the fight ends) or the add-on stands
    aside (Blizzard's map of a dungeon). nil: PartyBubbles.lua's own words.
  * ((1.4.0-beta11) ns.PinPos - where Blizzard's own group pin drew a unit, Follow.lua's second spot to click - went:
    RetailGroup.lua draws the arrow and the dots where the add-on draws their maps, Blizzard's pin shows none)
  * ns.PartyFly(x, y, z): a bubble's flight. Where Blizzard's map shows a map the add-on stands aside on (a dungeon, a
    battleground: off the placement tree), first that map's nearest ancestor in the tree, whole - as Blizzard's own zoom
    out would show it -, then the flight from there (Core.lua FlyToZoom alone jumped to them in one frame: 22.7 view
    widths, retailparty Q9). In combat neither (no map switch): as before, nothing moves.
  * ns.ZoomLike(x, y, vw): "your zoom" (PartyBubbles.lua ZoomFor) at (x, y) - the world zoom of a view as wide in yards
    as the view vw wide now: one world zoom is another width in yards on another world (from Orgrimmar's 3,193 yd a
    bubble landed 1,356 yd wide in Blade's Edge Mountains, 2,248 in Bastion, 1,491 in Talador - retailparty Q3). By the
    yards across the most detailed drawn map with yards at either point (RetailTree.lua yw, as RetailSpace.lua
    OpenZoomFor); nil where either has none; 0 while the add-on stands aside (no view of ours to keep: M's zoom).
  * ns.VwLike(x, y, vw): the same for Core.lua's follow (FollowFar: the one followed two views away - a portal to
    another world, a hearthstone): the camera width at (x, y) as wide in yards as vw at the camera's point - the one
    edit in Core.lua (FollowFar, FollowFarFree), nil on WoW Forever.
What the retail client's own documentation says of the calls used (Blizzard_APIDocumentationGenerated of 12.1.5.70575,
read from the client, logged): UnitPosition, UnitIsConnected, UnitIsDeadOrGhost, UnitExists, UnitIsVisible,
SetPortraitTexture, C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, C_Map.GetMapPosFromWorldPos and IsInInstance
carry no secret marking, none is secret in combat; UnitGUID, UnitInRaid and UnitClass are secret only for a unit outside
your party or raid; UnitIsUnit answers a secret on an addon-restricted map - a dungeon or a raid
(SecretWhenUnitComparisonRestricted: PartyBubbles.lua then finds your raid index by GUID). Every call through pcall,
plain values only; any of them may be missing.
]]
local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)
if ns.FLAVOR ~= "retail" then return end

local DUNGEON = 4 -- (Enum.UIMapType.Dungeon: dungeons and raids)
-- (the box's third line; PartyBubbles.lua sizes the box to the widest)
local WHY = {
    offline = "Offline: not on the map",
    instance = "No positions inside an instance",
    youInside = "No positions while you are in an instance",
    offmap = "On a map Endless Map does not draw",
    secret = "The game keeps their position secret",
    none = "The game gives no position there",
    combat = "Click to follow - the map goes after combat",
    combatOff = "In combat the map stays here",
}

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function Num(v) return type(v) == "number" and not Secret(v) and v == v end
local function Str(v) return type(v) == "string" and not Secret(v) and v ~= "" end

-- fn(...) as true / false; def when the call is missing, fails or gives nothing plain
local function Bool(fn, def, ...)
    if not fn then return def end
    local ok, v = pcall(fn, ...)
    if not ok or type(v) == "nil" or Secret(v) then return def end
    return v and true or false
end

local function Combat() return Bool(InCombatLockdown, false) end

-- What UnitPosition answers for u: "plain" (and its game map, x, y), "secret", "none" or "error".
local function Raw(u)
    if not UnitPosition then return "error" end
    local ok, x, y, _, inst = pcall(UnitPosition, u)
    if not ok then return "error" end
    if Secret(x) or Secret(y) or Secret(inst) then return "secret" end
    if Num(x) and Num(y) and Num(inst) then return "plain", inst, x, y end
    return "none"
end

-- The map the game names for u (C_Map.GetBestMapForUnit: the player and party members), its info.
local function BestMap(u)
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return end
    local ok, id = pcall(C_Map.GetBestMapForUnit, u)
    if not (ok and Num(id)) then return end
    local ok2, info = pcall(C_Map.GetMapInfo, id)
    if ok2 and type(info) == "table" then return id, info end
end

local function YouInside()
    if not IsInInstance then return false end
    local ok, inside = pcall(IsInInstance)
    return ok and not Secret(inside) and inside == true
end

---------------------------------------------------------------------------
-- The box's last line
---------------------------------------------------------------------------
function ns.PartyWhy(u, x, y)
    if not Str(u) then return nil end
    if x then
        if not Combat() then return nil end
        local core = ns.Core
        if core and core.State and core.State() == "off" then return WHY.combatOff end
        local M = WorldMapFrame and ns.GetMap(WorldMapFrame:GetMapID())
        if M and ns.SpaceHolds and Num(y) and not ns.SpaceHolds(M, x, y) then return WHY.combat end
        return nil
    end
    if not Bool(UnitIsConnected, true, u) then return WHY.offline end
    local kind = Raw(u)
    if kind == "secret" then return WHY.secret end
    if kind == "plain" then return WHY.offmap end -- (a position the tree's game-map boxes place nowhere)
    local _, info = BestMap(u)
    if info and Num(info.mapType) and info.mapType == DUNGEON then return WHY.instance end
    if YouInside() then return u == "player" and WHY.instance or WHY.youInside end
    return WHY.none
end

---------------------------------------------------------------------------
-- A bubble's flight
---------------------------------------------------------------------------
-- The nearest ancestor of map id that the placement tree draws ((1.4.0-beta12) RetailSpace.lua ns.SpaceAncestor).
local function Ancestor(id) return ns.SpaceAncestor(id) end

-- The flight waiting for the ancestor's pictures (a flight from a picture the client has not loaded yet shows nothing of
-- ours: its first frames were bare - the harness's real-client mode, retailparty Q9 - while Blizzard's map stood still)
local pending -- { u, x, y, z, t }
local waiter

local function Waited(_, dt)
    local p, core = pending, ns.Core
    if not p then waiter:Hide() return end
    p.t = p.t + (dt or 0)
    -- (the map closed, or moved by someone - a drag, a click, the wheel: the flight is off)
    if not (WorldMapFrame and WorldMapFrame:IsShown() and core and core.State and core.State() == "rest") or Combat() then
        pending = nil
        waiter:Hide()
        return
    end
    -- ((1.4.0-beta4's fixes) as long as the first view's pictures take: 1.4.0-beta3's WAIT_MAX flew after 1 s, ready or
    -- not - a flight over nothing of ours. The longest wait goes to the stamp - retailChecks.partyWait - a measurement)
    local ready = ns.Render and ns.Render.IsReady and ns.Render:IsReady()
    if not ready then return end
    local st = ns.retailStamp
    if st and p.t > (st.partyWait or 0) then st.partyWait = math.floor(p.t * 1000 + 0.5) / 1000 end
    pending = nil
    waiter:Hide()
    local F = ns.Follow
    local ux, uy
    if F then ux, uy = F:Position(p.u) end -- (where they are by now)
    if core.FlyToZoom(ux or p.x, uy or p.y, p.z) and F then F:Start(p.u, true) end
end

-- (PartyBubbles.lua Go) x, y, z as Core.lua FlyToZoom; u the unit clicked. false while a flight waits for the ancestor's
-- pictures: then this file starts following them as the flight starts (Follow:Start - the glow with it).
function ns.PartyFly(x, y, z, u)
    local core = ns.Core
    if not (core and core.FlyToZoom) then return false end
    pending = nil
    -- (in combat a point the map shown does not reach: Core.lua's landing is kept inside that map - at the view's own
    -- width, not one picked for them over there, where the wheel's depth limit made it 5,846 yd after the fight instead
    -- of 3,193: retailparty Q10; after the fight the follow flies on as wide in yards - Core.lua FollowFar)
    if Combat() and WorldMapFrame and core.Cam then
        local M = ns.GetMap(WorldMapFrame:GetMapID())
        local cam, v = core.Cam()
        if M and cam and v and Num(v.W) and v.W > 0 and Num(x) and Num(y) and ns.SpaceHolds and not ns.SpaceHolds(M, x, y) then
            local vw = core.LandingVw and core.LandingVw()
            z = ns.WorldZoom(v, (Num(vw) and vw > 0) and vw or cam.vw)
        end
    end
    if core.State and core.State() == "off" and core.JumpToZoom and core.Cam and not Combat() and WorldMapFrame and Str(u) then
        local A = Ancestor(WorldMapFrame:GetMapID())
        local _, v = core.Cam()
        if A and v and Num(v.W) and v.W > 0 then
            local az = ns.WorldZoom(v, ns.WidthForZoom(v, A, 1)) -- (that map whole: its fit)
            if Num(az) and az > 0 and core.JumpToZoom(A.cx, A.cy, az) then
                pending = { u = u, x = x, y = y, z = z, t = 0 }
                if not waiter then
                    waiter = CreateFrame("Frame")
                    waiter:SetScript("OnUpdate", Waited)
                end
                waiter:Show()
                return false
            end
        end
    end
    return core.FlyToZoom(x, y, z)
end

---------------------------------------------------------------------------
-- Your zoom, in yards
---------------------------------------------------------------------------
-- Yards per root unit at (px, py): by the most detailed drawn map there that knows its yards (RetailSpace.lua
-- OpenZoomFor's rule); nil over open space.
local function YardsPerUnit(px, py)
    local best
    for _, e in ipairs(ns.drawList or {}) do
        if e.yw and ns.SpaceHolds(e, px, py) and (not best or e.area < best.area) then best = e end
    end
    if best and best.x1 > best.x0 then return best.yw / (best.x1 - best.x0) end
end

-- (Core.lua FollowFar: the one followed two views away - a portal, a hearthstone) the camera width at (x, y) as wide in
-- yards as width vw at the camera's point now (from Orgrimmar's 3,193 yd a portal to Shattrath landed at another width:
-- retailparty Q12); nil where either point has no yards.
function ns.VwLike(x, y, vw)
    local core = ns.Core
    if not (core and core.Cam and ns.SpaceHolds and Num(x) and Num(y) and Num(vw) and vw > 0) then return nil end
    local cam = core.Cam()
    if not cam then return nil end
    local a, b = YardsPerUnit(cam.x, cam.y), YardsPerUnit(x, y)
    if not (a and b) then return nil end
    return math.min(vw * a / b, 1)
end

function ns.ZoomLike(x, y, vw)
    local core = ns.Core
    if not (core and core.Cam and ns.SpaceHolds and Num(x) and Num(y) and Num(vw) and vw > 0) then return nil end
    local state = core.State and core.State()
    if state == "off" then return 0 end
    local cam, v = core.Cam()
    if not (cam and v and Num(v.W) and v.W > 0) then return nil end
    -- (the point the view vw belongs to: in a flight the one followed - a bubble's flight is aimed at them, LandingVw is
    -- the landing's width -, else the camera's)
    local fx, fy = cam.x, cam.y
    local F = ns.Follow
    if state == "fly" and F and F:Active() then
        local ux, uy = F:Position(F:Unit())
        if ux then fx, fy = ux, uy end
    end
    local a, b = YardsPerUnit(fx, fy), YardsPerUnit(x, y)
    if not (a and b) then return nil end
    return ns.WorldZoom(v, math.min(vw * a / b, 1))
end
