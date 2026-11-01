--[[
Endless Map - Options.lua (1.0.0)

Every setting of the addon in ONE place: what it is called, which values it takes and what has to happen after a change.
Whatever changes a setting goes through here - the slash commands (Core.lua hands them over: Options:Slash), the map
menu (MapMenu.lua) and the game's Settings page (OptionsPanel.lua) - so a setting behaves the same wherever it is changed.

    ns.Options:Get(key)                 the value (for placeNames / dungeonIcons: what is on screen, see below)
    ns.Options:Set(key, value, quiet)   false when the value is not allowed; quiet: no chat line
    ns.Options:Toggle(key, quiet)
    ns.Options:Reset(quiet)             every setting back to its default (learned doors are kept)
    ns.Options:Default(key)
    ns.Options:Spec(key), :List()       label, kind ("bool" / "num"), presets - what the menus are built from

Core.lua keeps the saved table, its defaults (ns.DEFAULTS - this file adds its own rows), the chat printer
(ns.Print), the redraw (ns.Refresh), the command handler (ns.RunCommand) and its first slash word (ns.COMMAND).
Three commands keep their own handlers and messages: zoom and cityzoom (ZoomReadout.lua), doors hints (Doors.lua);
the menus set those values here and call the same Apply / redraw those handlers call.

Place names and dungeon icons: "labels" stays the switch of the whole label layer (/unroll labels: names AND icons, as
before 1.0.0). placeNames and dungeonIcons are its two halves; choosing one of them turns the layer on and
leaves the other half as it was on screen.
]]
local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)

local O = {}
ns.Options = O
ns.TITLE = "Endless Map" -- (the name on the menu, the hover text and the Settings page; 1.3.1: the new name)

local SPEC, LIST, BYCMD = {}, {}, {}

local function OnOff(b) return b and "|cff40ff40on|r" or "|cffff4040off|r" end
local function Say(msg) if ns.Print then ns.Print(msg) end end
local function Redraw() if ns.Refresh then ns.Refresh() end end
local function Cmd() return ns.COMMAND end -- (the first slash word: /unroll, on retail /emap - OneCopy.lua, 1.4.0-beta4)
O.Cmd = Cmd

-- (1.4.0) The settings of what only WoW Forever (and Classic Era) has - its dungeon maps, doors, markers, city and cave
-- switches, zone mosaic and flight master labels: on retail (RetailRender.lua draws Blizzard's own pictures) they are
-- left out of the menus (avail) and their slash commands say "WoW Forever only" (forever).
local FOREVER_ONLY = { doorHints = true, dungeons = true, bosses = true, cityZoom = true, mosaic = true, engineMarkers = true }
local function NotRetail() return ns.FLAVOR ~= "retail" end
-- (1.4.0-beta3, feature complete on retail - docs/retail-engine.md 14) the settings retail has once its file is there: the
-- door icons and names (RetailDoors.lua), the flight masters' names (the same), the caves (RetailCaves.lua), the zone
-- cut-outs (RetailCells.lua), the game's own minimap tiles (RetailImagery.lua); WoW Forever's as before
local RETAIL_HAS = {
    dungeonIcons = function() return ns.RetailDoors ~= nil end,
    flightPaths = function() return ns.RetailDoors ~= nil end,
    portals = function() return ns.Portals ~= nil end,
    caveZoom = function() return ns.RetailCaves ~= nil end,
    cells = function() return ns.RetailCells ~= nil end,
    imageryTiles = function() return ns.RetailImagery ~= nil end,
}

-- s.said: the chat line after a change - a text that ends in "on" / "off", or a function of the new value.
local function Add(s)
    if FOREVER_ONLY[s.key] then s.avail, s.forever = NotRetail, true end
    local has = RETAIL_HAS[s.key]
    if has then s.avail, s.forever = function() return NotRetail() or has() end, true end
    SPEC[s.key] = s
    LIST[#LIST + 1] = s
    if s.cmd then BYCMD[s.cmd] = s end
    return s
end

-- (the two halves of the label layer)
local function PartGet(db, key) return db.labels ~= false and db[key] ~= false end
local function PartSet(db, key, on)
    if not db.labels then db.labels, db.placeNames, db.dungeonIcons = true, false, false end
    db[key] = on
end

Add({ key = "enabled", kind = "bool", label = "Smooth zoom", said = "smooth zoom ",
    tip = "One continuous zoom over the whole world map. Off: Blizzard's map as usual.",
    apply = function(on, was)
        Redraw()
        -- (back on inside a dungeon: its map again, as /unroll dungeons does)
        if on and not was and ns.Dungeon then ns.Dungeon:AutoOpen() end
        if ns.Bubbles then ns.Bubbles:Apply() end -- (1.3.0: the party bubbles go with it - no following without it)
    end })
Add({ key = "placeNames", kind = "bool", cmd = "names", label = "Place names", said = "place names ",
    tip = "The names of continents, zones, cities and flight masters on the map.",
    get = PartGet, set = PartSet, apply = Redraw })
Add({ key = "dungeonIcons", kind = "bool", cmd = "icons", label = "Dungeon and raid icons", said = "dungeon and raid icons ",
    tip = "The door icons of dungeons and raids on the world map (click one for its map).",
    get = PartGet, set = PartSet, apply = Redraw })
Add({ key = "doorHints", kind = "bool", label = "Unreleased-dungeon placeholders", needs = "dungeonIcons",
    said = "placeholders for the instances not in the game yet ",
    tip = "Grey icons where the instances that are not in the game yet are expected.",
    apply = Redraw })
Add({ key = "dungeons", kind = "bool", cmd = "dungeons", label = "Dungeon maps",
    tip = "Dungeon and raid maps: click a door icon; they open by themselves inside a dungeon.",
    said = function(on)
        return "dungeon maps " .. OnOff(on) .. ((ns.Dungeon and ns.Core and not ns.Dungeon:Supported()) and " (WoW Forever only)" or "")
    end,
    apply = function(on)
        Redraw()
        if on and ns.Dungeon then ns.Dungeon:AutoOpen() end
    end })
Add({ key = "bosses", kind = "bool", cmd = "bosses", label = "Boss and entrance markers",
    said = "boss and entrance markers on dungeon maps ",
    tip = "Boss skulls and entrance markers on the dungeon maps.",
    apply = function(on) if ns.Dungeon and ns.Dungeon.ToggleBosses then ns.Dungeon:ToggleBosses(on) end end })
Add({ key = "livePins", kind = "bool", cmd = "livepins", label = "Map icons move with the map",
    said = "map icons move with the map ",
    tip = "Quest and other map icons follow the map while it moves. Off: they hide until it stops.",
    apply = Redraw })
Add({ key = "zoomReadout", kind = "bool", label = "Zoom readout", said = "zoom readout on the map ",
    tip = "A small readout of the zoom numbers in the map's top left corner.",
    apply = function()
        if ns.ZoomReadout then ns.ZoomReadout:Apply() end
        if ns.Core then Redraw() end
    end })

-- Numbers: presets = { value, text } rows for the menus (any allowed value can still be typed as a slash command).
Add({ key = "zoomStep", kind = "num", cmd = "step", lo = 1.05, hi = 2, label = "Wheel step", unit = "x",
    tip = "How much one notch of the mouse wheel zooms.",
    said = function(v) return ("zoom per wheel notch: %gx"):format(v) end,
    presets = { { 1.15, "Fine" }, { 1.3, "Normal" }, { 1.5, "Fast" }, { 2, "Fastest" } } })
Add({ key = "maxZoom", kind = "num", cmd = "depth", lo = 1, hi = 10, label = "Zoom depth", unit = "x",
    tip = "How far past a zone's own map you can zoom in.",
    said = function(v) return ("you can now zoom %gx past a zone's normal size"):format(v) end,
    presets = { { 2, "Shallow" }, { 4, "Normal" }, { 6, "Deep" }, { 10, "Deepest" } } })
Add({ key = "flySpeed", kind = "num", cmd = "speed", lo = 0.25, hi = 4, label = "Flight speed", unit = "x",
    tip = "The speed of the flight to another map (a click on a zone, the quest log).",
    said = function(v) return ("flight speed: %gx"):format(v) end,
    presets = { { 0.5, "Slow" }, { 1, "Normal" }, { 2, "Fast" }, { 4, "Fastest" } } })
-- (the WORLD zoom from which the city maps show; false: 1.5x of each city's own zone, the rule before 1.0.0)
Add({ key = "cityZoom", kind = "num", lo = 1, hi = ns.Render.CITY_G_MAX, orFalse = true, label = "City maps appear", unit = "x",
    tip = "The zoom (1x = the whole world map) from which the city maps replace their zone's drawing of the city.",
    said = function(v)
        return v and ("city maps show from world zoom %gx"):format(v) or "city maps show at 1.5x of their own zone"
    end,
    presets = { { 10, "Sooner" }, { 14.05, "Normal" }, { 20, "Later" }, { false, "By each city's zone" } },
    apply = function()
        if ns.ZoomReadout then ns.ZoomReadout:Apply() end
        if ns.Core then Redraw() end
    end })

-- (1.1.0, Follow.lua) following a character, and where M opens the map
Add({ key = "follow", kind = "bool", cmd = "follow", label = "Follow on click", said = "follow on click ",
    tip = "Click your arrow or a party member on the map: the map follows them. Click them again, drag the map or click a zone to stop.",
    apply = function(on) if not on and ns.Follow then ns.Follow:Stop() end end })
Add({ key = "openZoom", kind = "num", cmd = "openzoom", lo = 1, hi = 25, orFalse = true, label = "M opens the map on me", unit = "x",
    tip = "The M key opens the map on your character at this zoom (1x = the whole world map). Off: the game's view of your zone.",
    said = function(v)
        return v and ("M opens the map on your character at world zoom %gx"):format(v) or "M opens the map as the game does (your zone)"
    end,
    presets = { { 10, "Wide" }, { 14, "Normal" }, { 20, "Close" }, { false, "Off (the game's view)" } } })

-- (1.2.0) M also follows you; the caves' switch (no command of its own: ZoomReadout.lua handles /unroll cavezoom, as
-- cityzoom)
Add({ key = "openFollow", kind = "bool", cmd = "openfollow", label = "M follows me", said = "M opens the map following you: ",
    tip = "When M opens the map on your character, the map also follows you, as a click on your arrow does." })
Add({ key = "caveZoom", kind = "num", lo = ns.Render.CAVE_G_MIN, hi = ns.Render.CAVE_G_MAX, orFalse = true, label = "Caves appear", unit = "x",
    tip = "The zoom (1x = the whole world map) from which caves and mines show their tunnels on the map - where the map stops short of it, at its deepest zoom there. The caves button beside the settings button turns them on and off.",
    said = function(v)
        return v and ("caves show from world zoom %gx (or as deep as the zoom goes over a cave, where it stops short of that)"):format(v)
            or "caves never show"
    end,
    presets = { { 20, "Sooner" }, { 30, "Normal" }, { 40, "Later" }, { false, "Off" } },
    apply = function()
        if ns.ZoomReadout then ns.ZoomReadout:Apply() end
        if ns.Core then Redraw() end
    end })

-- (1.3.0, PartyBubbles.lua) you and your party in round bubbles under the map's top left button
Add({ key = "bubbles", kind = "bool", cmd = "bubbles", label = "Party bubbles", said = "party bubbles on the map ",
    tip = "You and your party (in a raid: your group) as round portraits under the map's top left button. Hover one for the zone they are in; click it to go to them and follow them.",
    apply = function() if ns.Bubbles then ns.Bubbles:Apply() end end })

-- (1.3.0, MinimapLayer.lua) the map drawn from the game's own minimap pictures; WoW Forever only (avail: the menus leave it
-- out elsewhere, MapMenu.lua / OptionsPanel.lua)
local function Imagery() return ns.MinimapLayer ~= nil and ns.MinimapLayer:Supported() end
Add({ key = "imagery", kind = "bool", cmd = "imagery", label = "Minimap imagery", avail = Imagery,
    tip = "The map drawn from the game's own minimap pictures - the real terrain - instead of the drawn map; land you have not explored is greyed. The round button left of the caves button switches between the two.",
    said = function(on) return "minimap imagery " .. OnOff(on) .. (Imagery() and "" or " (WoW Forever only)") end,
    apply = function()
        Redraw()
        if ns.MapMenu and ns.MapMenu.UpdateLayer then ns.MapMenu:UpdateLayer() end
    end })

-- Slash only (not in the menus).
Add({ key = "labels", kind = "bool", cmd = "labels", said = "place labels ",
    apply = function(on)
        -- (the layer back on with both halves off would show nothing)
        local db = ns.db
        if on and db.placeNames == false and db.dungeonIcons == false then db.placeNames, db.dungeonIcons = true, true end
        Redraw()
    end })
Add({ key = "labelsAtRest", kind = "bool", cmd = "rest", said = "labels while the map is still ", apply = Redraw })
Add({ key = "flightPaths", kind = "bool", cmd = "flight", said = "flight master labels ", apply = Redraw })
Add({ key = "portals", kind = "bool", cmd = "portals", said = "portal markers ", apply = Redraw }) -- (1.5.0: on WoW Forever too)
Add({ key = "mosaic", kind = "bool", cmd = "mosaic", said = "zone map mosaic ", apply = Redraw })
Add({ key = "cells", kind = "bool", cmd = "cells", said = "seamless zone cells ", apply = Redraw })
Add({ key = "engineMarkers", kind = "bool", cmd = "markers",
    said = function(on) return "group on entrance maps drawn by " .. (on and "the game (its group widget)" or "the addon (dots)") end,
    apply = function() if ns.Dungeon and ns.Dungeon.RefreshMarkers then ns.Dungeon:RefreshMarkers() end end })
-- (1.3.0, MinimapLayer.lua) the game's own minimap tiles at the imagery's deepest zooms - drawn by fileDataID as Dalaran's
-- detail map and the caves have been since 1.0; a way out should they ever misbehave (not in the help or the menus)
Add({ key = "imageryTiles", kind = "bool", cmd = "imagerytiles",
    said = function(on) return "the game's own minimap tiles in the minimap imagery " .. OnOff(on) .. (Imagery() and "" or " (WoW Forever only)") end,
    apply = Redraw })
Add({ key = "mapButton", kind = "bool", cmd = "button", label = "Buttons on the map",
    tip = "The round settings, caves and imagery buttons in the map's lower right corner.", -- (1.3.0: + imagery)
    said = function(on)
        return "buttons on the map " .. OnOff(on) .. (on and "" or (" (" .. Cmd() .. " button shows them again)"))
    end,
    apply = function() if ns.MapMenu then ns.MapMenu:Apply() end end })

-- The defaults of the settings this file adds (Core.lua fills the saved table from ns.DEFAULTS on ADDON_LOADED and on
-- /unroll reset; its own rows are in Core.lua).
local OWN_DEFAULTS = { placeNames = true, dungeonIcons = true, mapButton = true, bubbles = true, imagery = false, imageryTiles = true } -- (1.3.0: + bubbles, imagery, imageryTiles)
if ns.DEFAULTS then
    for k, v in pairs(OWN_DEFAULTS) do
        if ns.DEFAULTS[k] == nil then ns.DEFAULTS[k] = v end
    end
end

function O:Spec(key) return SPEC[key] end
function O:List() return LIST end

function O:Default(key)
    local d = ns.DEFAULTS
    if d and d[key] ~= nil then return d[key] end
    return OWN_DEFAULTS[key]
end

function O:Get(key)
    local s, db = SPEC[key], ns.db
    if not (s and db) then return nil end
    if s.get then return s.get(db, key) end
    return db[key]
end

-- (a setting that only matters while another one is on: the menus grey it out)
function O:Usable(key)
    local s = SPEC[key]
    if not (s and ns.db) then return false end
    return not s.needs or self:Get(s.needs) == true
end

function O:Set(key, value, quiet)
    local s, db = SPEC[key], ns.db
    if not (s and db) then return false end
    if s.kind == "bool" then
        value = value and true or false
    elseif not (value == false and s.orFalse) then
        if type(value) ~= "number" or not (value >= s.lo and value <= s.hi) then return false end
    end
    local was = self:Get(key)
    if s.set then s.set(db, key, value) else db[key] = value end
    if s.apply then s.apply(value, was) end
    if not quiet and s.said then
        Say(type(s.said) == "function" and s.said(value) or (s.said .. OnOff(value)))
    end
    return true
end

function O:Toggle(key, quiet)
    local s = SPEC[key]
    if not (s and s.kind == "bool" and ns.db) then return false end
    return self:Set(key, not self:Get(key), quiet)
end

function O:Reset(quiet)
    local db, defaults = ns.db, ns.DEFAULTS
    if not (db and defaults) then return false end
    for k, val in pairs(defaults) do db[k] = val end
    if ns.Dungeon and ns.Dungeon.ToggleBosses then ns.Dungeon:ToggleBosses(db.bosses) end -- (review: markers follow)
    if ns.ZoomReadout then ns.ZoomReadout:Apply() end
    Redraw()
    if ns.MapMenu then ns.MapMenu:Apply() end
    if ns.Bubbles then ns.Bubbles:Apply() end -- (1.3.0)
    if not quiet then Say("settings reset") end
    return true
end

-- Core.lua's slash handler asks first: true when the command was a setting (and is done). A number out of range is no
-- command: Core.lua prints its list, as it always did.
function O:Slash(cmd, arg, num)
    if not ns.db then return false end
    if cmd == "on" or cmd == "off" then return self:Set("enabled", cmd == "on") end
    if cmd == "toggle" then return self:Toggle("enabled") end
    if cmd == "reset" then return self:Reset() end
    local s = BYCMD[cmd]
    if not s then return false end
    if s.forever and not s.avail() then -- (1.4.0: on retail)
        Say(cmd .. ": WoW Forever only")
        return true
    end
    if s.kind == "num" then return num ~= nil and self:Set(s.key, num) end
    return self:Toggle(s.key)
end

-- The lines Core.lua's command list ends with (the commands this file and MapMenu.lua add).
function O:Help()
    local c = Cmd()
    if not NotRetail() then
        -- (1.4.0) retail: the commands it has there (1.4.0-beta3: the doors, the flight masters, the caves, the imagery)
        Say(c .. " names | icons   toggle place names / dungeon and raid doors on the map (click a door's name: fly there)")
        Say(c .. " flight          toggle the flight masters' names")
        Say(c .. " portals         toggle the markers of the boats, zeppelins, portals and trams (hover: where it goes; click a way: fly there)")
        Say(c .. " button          show or hide the buttons on the map (settings, caves, imagery)")
        Say(c .. " bubbles         toggle the party bubbles in the map's top left corner (click one: go to them and follow)")
        Say(c .. " cavezoom N      the world zoom the caves show from (default 30, off: never)")
        Say(c .. " imagery         toggle the minimap imagery: the map drawn from the game's minimap pictures (default off)")
        Say(c .. " cells           toggle the zones cut to their land (off: each zone's whole picture as you near it)")
        return
    end
    Say(c .. " names | icons   toggle place names / dungeon and raid icons on the map")
    Say(c .. " portals         toggle the markers of the boats, zeppelins, portals and trams (hover: where it goes; click a way: fly there)")
    Say(c .. " button          show or hide the buttons on the map (settings, caves, imagery)")
    Say(c .. " bubbles         toggle the party bubbles in the map's top left corner (click one: go to them and follow)")
    Say(c .. " imagery         toggle the minimap imagery: the map drawn from the game's minimap pictures (default off)")
end
