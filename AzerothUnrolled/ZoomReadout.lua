--[[
Endless Map - ZoomReadout.lua (1.0.0; the world-zoom switch is the default, 14.05x)

A tuning aid; nothing here draws map art.
  /unroll zoom        a small readout on the map: ONE global zoom number (1.00x = the whole world map fills the view),
                   the zone under the centre of the view, and every city / detail map in view with whether its map shows.
  /unroll cityzoom N  the WORLD zoom from which every city map (and Blackrock Mountain, Dalaran) shows, wherever the view
                   is; they hide again just below it (0.5%). /unroll cityzoom default = 14.05x; /unroll cityzoom off = the
                   rule before 1.0.0 (1.5x of the home zone of each city). Saved (AzerothUnrolledDB.cityZoom).
  /unroll cavezoom N  (1.2.0) the WORLD zoom from which the caves show (Caves.lua); default = 30x, off =
                   never. Over a cave the wheel stops short of it, the cave shows at the deepest zoom there. Saved
                   (AzerothUnrolledDB.caveZoom).
  /unroll questzoom N  (1.6.0, WoW Forever) the WORLD zoom from which every zone's quest icons show (Pins.lua) - a
                   zone's at its own map's zoom if that comes first; default = 10x, off = Blizzard's own (a zone's
                   on its own map only). Saved (AzerothUnrolledDB.questZoom).
]]
local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)

local Z = {}
ns.ZoomReadout = Z

local UPDATE_EVERY = 0.1
local LEVEL = 9500 -- above the pins of the map and the moving layers of the addon
local frame, bg, text
local acc = 0
local lines = {}

local function Lines()
    wipe(lines)
    local core, R = ns.Core, ns.Render
    if not (core and core.Cam and R and R.ZoomLines) then
        lines[1] = "zoom: the map is not set up yet (open it once)"
        return lines
    end
    local cam, v = core.Cam()
    if not (cam and v) then
        lines[1] = "zoom: no view yet (open the map once)"
        return lines
    end
    R:ZoomLines(cam, v, lines)
    return lines
end

local function Ensure()
    if frame then return true end
    local c = WorldMapFrame and WorldMapFrame.ScrollContainer
    if not c then return false end
    frame = CreateFrame("Frame", nil, c)
    if ns.SetLevelFixed then ns.SetLevelFixed(frame, LEVEL) else frame:SetFrameLevel(LEVEL) end
    -- (1.3.0: right of Blizzard's map-pin button and the party bubbles under it (PartyBubbles.lua), below the dungeon
    -- view's bar - at 8, -8 it lay over the pin button)
    frame:SetPoint("TOPLEFT", c, "TOPLEFT", 40, -36)
    frame:SetSize(200, 40)
    frame:EnableMouse(false)
    bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0, 0, 0, 0.65)
    text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -5)
    text:SetJustifyH("LEFT")
    frame:SetScript("OnUpdate", function(_, dt)
        acc = acc + (dt or 0)
        if acc < UPDATE_EVERY then return end
        acc = 0
        Z:Update()
    end)
    frame:Hide()
    return true
end

function Z:Update()
    if not (frame and frame:IsVisible()) then return end -- (1.0.0: only while the map shows)
    local s = table.concat(Lines(), "\n")
    if s == text.shownText then return end -- ((1.4.0-beta15) ten times a second: laid out only when it changed)
    text.shownText = s
    text:SetText(s)
    local w, h = text:GetStringWidth(), text:GetStringHeight()
    if type(w) ~= "number" or type(h) ~= "number" then w, h = 190, 30 end
    frame:SetSize(w + 12, h + 10)
end

-- The saved settings -> the renderer and the readout frame.
function Z:Apply()
    local db = ns.db
    if not db then return end
    if ns.Render and ns.Render.SetCityZoom then ns.Render:SetCityZoom(db.cityZoom) end
    if ns.Render and ns.Render.SetCaveZoom then ns.Render:SetCaveZoom(db.caveZoom) end -- (1.2.0)
    if ns.Pins and ns.Pins.SetQuestZoom then ns.Pins:SetQuestZoom(db.questZoom) end -- (1.6.0, WoW Forever)
    if db.zoomReadout then
        if Ensure() then
            frame:Show()
            self:Update()
        end
    elseif frame then
        frame:Hide()
    end
end

-- (1.2.0) /unroll cityzoom and /unroll cavezoom: a world zoom - kept within lo..hi of the switch (said so when it is not) -
-- default (or on), off (or 0; offWords: more words for off); returns the new setting (false: off), nil: nothing to do.
local function SwitchSetting(cmd, num, arg, lo, hi, default, Print, offWords)
    if num and num ~= 0 then
        local v = math.min(math.max(num, lo), hi)
        if v ~= num then Print(("%s: from %gx to %gx - set to %gx"):format(cmd, lo, hi, v)) end
        return v
    end
    if num == 0 or arg == "off" or (offWords and offWords[arg]) then return false end
    if arg == "default" or arg == "reset" or arg == "on" then return default end
    if arg and arg ~= "" then
        Print(("%s: a world zoom from %g to %g (read it with %s zoom), default, or off"):format(cmd, lo, hi, ns.COMMAND))
    end
end

-- cmd = "zoom" | "cityzoom" | "cavezoom" | (1.6.0) "questzoom", num = the number typed (or nil), Print = the chat printer
-- of Core, arg = the text typed.
function Z:Slash(cmd, num, Print, arg)
    local db, R = ns.db, ns.Render
    if not (db and R and R.ZoomLines) then
        Print("zoom: not available")
        return
    end
    if (cmd == "cavezoom" and not R.CaveZoom) or (cmd == "cityzoom" and not R.CityZoom) or (cmd == "questzoom" and ns.FLAVOR ~= "forever") then
        Print(cmd .. ": WoW Forever only") -- (1.4.0: retail has no city switch - RetailRender.lua; 1.4.0-beta3: its caves, RetailCaves.lua)
        return
    end
    if cmd == "questzoom" then
        -- (1.6.0) the world zoom from which a zone's quests show (Pins.lua) - the player: "like around 10x zoom level"
        local PN = ns.Pins
        if not PN then
            Print(cmd .. ": not available")
            return
        end
        local v = SwitchSetting(cmd, num, arg, PN.QUEST_G_MIN, PN.QUEST_G_MAX, PN.QUEST_G, Print)
        if v ~= nil then
            db.questZoom = v
            self:Apply()
        end
        local g = PN:QuestZoom()
        if g then
            Print(("quest icons show above world zoom %.2fx - a zone's at its own map's zoom if that comes first. %s questzoom default = %.2fx, off = Blizzard's own (a zone's on its own map only)"):format(g, ns.COMMAND, PN.QUEST_G))
        else
            Print(("quest icons are Blizzard's own (a zone's on its own map only). %s questzoom default = world zoom %.2fx"):format(ns.COMMAND, PN.QUEST_G))
        end
        return
    end
    if cmd == "cavezoom" then
        -- (1.2.0) the world zoom from which the caves show (Caves.lua)
        local v = SwitchSetting(cmd, num, arg, R.CAVE_G_MIN, R.CAVE_G_MAX, R.CAVE_G, Print)
        if v ~= nil then
            db.caveZoom = v
            self:Apply()
        end
        local g = R:CaveZoom()
        if g then
            Print(("caves show above world zoom %.2fx - or as deep as the zoom goes over a cave, where it stops short of that. %s cavezoom default = %.2fx, off = never"):format(g, ns.COMMAND, R.CAVE_G))
        else
            Print(("caves never show. %s cavezoom default = world zoom %.2fx"):format(ns.COMMAND, R.CAVE_G))
        end
        return
    end
    if cmd == "cityzoom" then
        -- (1.0.0) at most Render.CITY_G_MAX: from about 25.7x the view can lie inside a capital, whose own map then shows
        local v = SwitchSetting(cmd, num, arg, 1, R.CITY_G_MAX, R.CITY_G, Print, { zone = true })
        if v ~= nil then
            db.cityZoom = v
            self:Apply()
        end
        local g, zin, zout = R:CityZoom()
        if g then
            Print(("city maps show above world zoom %.2fx, wherever the view is (hide below %.2fx). %s cityzoom default = %.2fx, off = 1.5x of each city's own zone"):format(
                g, g * zout / zin, ns.COMMAND, R.CITY_G))
        else
            Print(("city maps show at %.2fx of their own zone (the per-zone rule). %s cityzoom default = world zoom %.2fx"):format(zin, ns.COMMAND, R.CITY_G))
        end
        return
    end
    db.zoomReadout = not db.zoomReadout
    self:Apply()
    Print("zoom readout on the map " .. (db.zoomReadout and "on" or "off"))
    for _, l in ipairs(Lines()) do Print(l) end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" or name == "Blizzard_WorldMap" then Z:Apply() end
end)
