local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)

--[[
Endless Map - MapCoords.lua (1.8.2; WoW Forever): the map's coordinates in the zone you point at.

A player's report on 1.8.1 (through the author): "at 14x the coords break"; the author: "the individual zone
coordinates should be whats displayed when hovering over a zone, we dont really car about the global as we would just
tell someone what zone."

The coordinates are Blizzard's own panel at the map's bottom left (Blizzard_WorldMapTemplates.lua
WorldMapCoordsPanelMixin:OnUpdate, WoW Forever 70009 and retail 12.1.5 alike; the CVars worldMapShowCursorCoords,
worldMapShowPlayerCoords): "Cursor: x, y" from WorldMapFrame:GetNormalizedCursorPosition() and "Player: x, y" from
C_Map.GetPlayerMapPosition - both on the map Blizzard's frame shows. Endless Map switches that map as you zoom (the
continent, a zone, a city: Core.lua's handover), so the panel gave the continent's ("global") coordinates zoomed out, and
one zone's coordinates while you pointed at another.

After Blizzard's OnUpdate (a post-hook of the panel's script) each frame, while Endless Map drives the view:
  cursor  the coordinates of the zone or city under the cursor - the point from Endless Map's own view (Core.CursorWorld),
          the zone from the game's own hit areas (Core.ZoneAtPoint: C_Map.GetMapInfoAtPosition, as a click uses) - with
          its name after them where it is not the map Blizzard's frame shows; over no zone (the open sea) none.
  player  the player's own map's (C_Map.GetBestMapForUnit: the zone, or the city), with its name where it is not the map
          Blizzard's frame shows (the game's own wording: WORLD_MAP_PLAYER_COORDS_MAP_NAME); where the game gives no
          position (an instance), Blizzard's line as it is.
The game's own strings and its "by tenths" CVar (coordsByTenths) are kept. Endless Map off, the Gamepad UI on (Core.lua
standby), the dungeon view: Blizzard's panel as it is.
]]

local M = {}
ns.MapCoords = M

local panel
local last = {} -- the cursor line last set: its inputs (x, y, Blizzard's map, by tenths) and its text

local function Round(v) return math.floor(v + 0.5) end

-- (Blizzard's SetCoordText: a normalized position as percents, by tenths or whole)
local function Text(floatFmt, intFmt, tenths, x, y, name)
    if tenths then
        if name then return floatFmt:format(x * 100, y * 100, name) end
        return floatFmt:format(x * 100, y * 100)
    end
    if name then return intFmt:format(Round(x * 100), Round(y * 100), name) end
    return intFmt:format(Round(x * 100), Round(y * 100))
end

local function Active()
    local core = ns.Core
    if not (core and core.State and core.CursorWorld and core.ZoneAtPoint) then return false end
    if ns.Standby and ns.Standby() then return false end
    return core.State() ~= "off"
end

local function CursorText(tenths, shown)
    local x, y = ns.Core.CursorWorld()
    if not x then return nil end
    if last.x == x and last.y == y and last.map == shown and last.tenths == tenths then return last.text end
    local id = ns.Core.ZoneAtPoint(x, y)
    local e = id and ns.maps[id]
    local text = ""
    if e and e.x1 > e.x0 and e.y1 > e.y0 then
        text = Text(WORLD_MAP_CURSOR_COORDS, WORLD_MAP_CURSOR_COORDS_INTEGER, tenths, (x - e.x0) / (e.x1 - e.x0),
            (y - e.y0) / (e.y1 - e.y0))
        if id ~= shown then text = ("%s (%s)"):format(text, e.name or "") end
    end
    last.x, last.y, last.map, last.tenths, last.text = x, y, shown, tenths, text
    return text
end

local function PlayerText(tenths, shown)
    local id = C_Map.GetBestMapForUnit("player")
    local pos = id and C_Map.GetPlayerMapPosition(id, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if id == shown then return Text(WORLD_MAP_PLAYER_COORDS, WORLD_MAP_PLAYER_COORDS_INTEGER, tenths, x, y) end
    local info = C_Map.GetMapInfo(id)
    return Text(WORLD_MAP_PLAYER_COORDS_MAP_NAME, WORLD_MAP_PLAYER_COORDS_MAP_NAME_INTEGER, tenths, x, y,
        info and info.name or UNKNOWN)
end

local function After(self)
    if not Active() then return end
    local tenths, shown = self.coordsByTenths, WorldMapFrame:GetMapID()
    if self.CursorCoords:IsShown() then
        local t = CursorText(tenths, shown)
        if t then self.CursorCoords.Label:SetText(t) end
    end
    if self.PlayerCoords:IsShown() then
        local t = PlayerText(tenths, shown)
        if t then self.PlayerCoords.Label:SetText(t) end
    end
end

-- Blizzard's panel: the overlay frame of the world map with both lines (WorldMapMixin:AddOverlayFrames).
local function Setup()
    if panel or not (WorldMapFrame and WorldMapFrame.overlayFrames) then return end
    for _, f in ipairs(WorldMapFrame.overlayFrames) do
        if type(f) == "table" and f.HookScript and f.CursorCoords and f.CursorCoords.Label and f.PlayerCoords
            and f.PlayerCoords.Label then
            panel = f
            f:HookScript("OnUpdate", After)
            return
        end
    end
end

-- (tests) the panel hooked
M.T = { Panel = function() return panel end }

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" or name == "Blizzard_WorldMap" then Setup() end
end)
