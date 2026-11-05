local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)

--[[
Labels: "important places along the way". Every label lives in world-map
coordinates and has a zoom band (relative to the map it belongs to) in which
it is visible, so continents give way to zones, zones to cities, dungeons,
raids and flight masters as you zoom in. Overlapping labels are dropped by
priority. The layer never takes mouse input, so Questie icons underneath
stay clickable. (Dungeon.lua makes the dungeon / raid entrance ICONS - the
diamond under the name - clickable through Blizzard's canvas click handler
instead, with HitTest below; the name itself is not a click target.)
A detail level drawn into the world map (Render.lua: Blackrock Mountain's
entrance level, ns.DETAIL_MAPS) brings the icons of the dungeons it leads to;
they fade with the level's picture and stand in for the entrance's own icon,
which fades out meanwhile. (1.0.0: Dalaran's brings its name instead.)
1.0.0 (Doors.lua): placeholders for the instances not in the game files yet
(hollow grey diamonds, drawn after every other label, never a click target,
hidden by /unroll doors hints), doors learned in game (moved / restyled here),
and the "you are inside" marker - the round player icon on the door icon of
the instance the player is in, shown at every zoom (it marks the door, not a
position: the game gives none inside instances).
]]

local Labels = {}
ns.Labels = Labels

local layer
local items = {}
local taxiLoaded = {}
local placed = {}
local placedGhost = {} -- (1.0.0 review) placed[i..i+3] is a placeholder's name + icon rect (placedGhost[i])
-- (1.0.0) placed[i..i+3] belongs to a label the city switch is fading right now (it.soft: a capital's name giving way
-- to its banner or coming back with the city's map, a detail level's name and icons, the entrance icon that gives way
-- to them): placedSoft[i] = its alpha. While it is part-faded by the switch it does not push another label off the map -
-- that one shows through it, as much as the first is gone (softA) - so two labels that trade places crossfade; before,
-- the second one popped in (or out) at full alpha when the first one's fade ended (or began). A label fading for any
-- other reason (its zoom band) blocks as it always did.
local placedSoft = {}
-- (1.0.0 review) placedLevel[i]: the detail level (it.detail) of a part-faded label at placed[i..i+3], else false. Labels
-- of ONE level fade together (the same alpha): between them the overlap stays hard, as at full alpha - else, while the
-- level fades in or out, a name it hides showed through it (two names drawn on top of each other for the whole fade).
local placedLevel = {}
local softA = 0
local sortBuf = {}
local entrances = {} -- dungeon / raid entrance items (Dungeon.lua)
local hot            -- the entrance icon under the cursor (Dungeon.lua)
local ICON_HIT = 10  -- entrance icons take clicks in a 20 x 20 px square around the diamond
local HOT_GROW = 1.25
local DIAMOND = "Interface\\Buttons\\WHITE8X8"
local HERE_FILE = "Interface\\WorldMap\\WorldMapPlayerIcon" -- (1.0.0) the round player icon (Dungeon.lua DOT_FILE)
local HERE_SIZE = 22
-- (the "you are inside" door beyond its own zoom band: its icon alone, placed after every name - so it pushes none off the
-- map, it draws over one as the player arrow does - and before the placeholders; in its band it is placed as always)
local HERE_PRIO = 16

local STYLE = {
    continent = { size = 18, r = 1.00, g = 0.86, b = 0.45, prio = 60 },
    zone      = { size = 12, r = 0.96, g = 0.91, b = 0.76, prio = 30 },
    city      = { size = 12, r = 0.45, g = 0.80, b = 1.00, prio = 45, dot = 8 },
    raid      = { size = 11, r = 1.00, g = 0.50, b = 0.20, prio = 50, dot = 12, icon = true },
    dungeon   = { size = 10, r = 0.40, g = 1.00, b = 0.40, prio = 40, dot = 10, icon = true },
    flight    = { size = 9,  r = 1.00, g = 1.00, b = 0.60, prio = 20, dot = 5 },
    cave      = { size = 10, r = 0.92, g = 0.84, b = 0.64, prio = 25 }, -- (1.2.0) a cave's name (Caves.lua), with its picture
    subzone   = { size = 10, r = 0.93, g = 0.89, b = 0.78, prio = 22 }, -- (1.3.0) a sub-zone's name over the minimap imagery
    -- (1.0.0) placeholders (Doors.lua): hollow grey diamonds with grey names, placed after every other label (so they
    -- never push one off the map); their kind stays "dungeon" / "raid" (the same zoom bands)
    ghostDungeon = { size = 10, r = 0.66, g = 0.66, b = 0.66, prio = 15, dot = 10, icon = true, hollow = true },
    ghostRaid    = { size = 11, r = 0.66, g = 0.66, b = 0.66, prio = 15, dot = 12, icon = true, hollow = true },
}
Labels.STYLE = STYLE -- (Dungeon.lua: the portal icons on entrance maps look the same)

-- Half the height a dot takes: entrance icons are 45-degree diamonds (their
-- tips reach dot * sqrt(1/2)) with a 2 px dark rim.
local function DotHalf(s)
    if s.icon then return s.dot * 0.7072 + 1.5 end
    return s.dot / 2
end
-- ((1.4.0-beta10, retail: RetailPins.lua) an item with a picture of its own - it.pic { atlas or file + tc, w, h }: the
-- game's icon of a flight master or a point of interest - takes half its height; else its style's dot. nil on WoW Forever)
-- ((1.4.0-beta11) a picture over a base - it.pic.base, bw, bh: a quest's round button under its icon - the taller of the two)
local function ItemHalf(it)
    if it.pic then return math.max(it.pic.h, it.pic.bh or 0) / 2 end
    return it.style.dot and DotHalf(it.style)
end
-- ((1.4.0-beta11, retail: RetailPins.lua - it.zmin) a map's marker that waits for a deeper view of its map than the map's
-- picture itself: the quest offers a quest hub stands for until its map is ZMIN_RAMP short of zmin, fully in at zmin)
local ZMIN_RAMP = 0.8

-- Visibility bands, in zoom of the owning map (1 = that map fills the view).
-- Zone/city names give way as their own art fades in (Render.FADE_Z0/Z1).
-- (1.3.0) mm: the minimap imagery shows (MinimapLayer.lua) - it prints no names: zone and city names stay on until the
-- view is well inside them, sub-zone names (of explored pieces, see Labels:Draw) come in as a zone's own would give way.
local function AlphaFor(kind, z, owner, v, mm)
    if mm then
        if kind == "zone" then return ns.Band(z, 0.10, 0.18, 1.6, 2.4)
        elseif kind == "city" then return ns.Band(z, 0.035, 0.07, 1.6, 2.4)
        elseif kind == "subzone" then return ns.Band(z, 0.5, 0.75) end
    elseif kind == "subzone" then
        return 0
    end
    if kind == "continent" then
        -- (1.4.0, retail: owner.pe, the map it is placed on - RetailSpace.lua) a continent's name belongs to the view of
        -- the map it lies on: by how far that map is zoomed (Quel'Thalas on the Eastern Kingdoms, Argus on the Broken
        -- Isles); world and continent names on space and on Azeroth are in Blizzard's own pictures
        if owner.pe then
            return ns.Band(z / ns.ZoomOf(v, owner, ns.WidthForZoom(v, owner.pe, 1)), 0.5, 0.7, 1.6, 2.4)
        end
        -- Continent names belong to the Azeroth view: judge them by how far
        -- the world map is zoomed, not by the continent's own zoom.
        return ns.Band(z / ns.ZoomOf(v, owner, 1), 0, 0, 1.6, 2.4)
    elseif kind == "zone" then return ns.Band(z, 0.10, 0.18, 0.45, 0.7)
    elseif kind == "city" then return ns.Band(z, 0.035, 0.07, 0.45, 0.7)
    elseif kind == "raid" then return ns.Band(z, 0.08, 0.16)
    elseif kind == "dungeon" then return ns.Band(z, 0.20, 0.35)
    elseif kind == "flight" then return ns.Band(z, 0.50, 0.70)
    end
    return 0
end

function Labels:Init(parent)
    layer = parent
end

local function Add(x, y, text, kind, owner)
    if not (x and y and text and text ~= "" and owner) then return end
    local it = { x = x, y = y, text = text, kind = kind, owner = owner, style = STYLE[kind] }
    items[#items + 1] = it
    it.seq = #items -- (1.0.0: ByPriority's last word)
    return it
end

-- One ns.INSTANCES row -> its entrance item. (1.0.0) Rows from Doors.lua may also carry door = its record (Doors.lua),
-- style = a STYLE key other than the kind's (placeholders), noClick = nothing opens on a click (no map behind it).
local function AddRow(d)
    local x, y, owner = ns.WorldPosToMap(d[1], d[2], d[3])
    if x and d.zone and ns.maps[d.zone] then owner = ns.maps[d.zone] end -- (ns.FOREVER_DOORS rows: the door's own zone)
    if not x then return end
    local text = d[4]
    if d[6] and d[7] and d[6] < d[7] then
        text = ("%s |cffb0b0b0(%d-%d)|r"):format(text, d[6], d[7])
    end
    local it = Add(x, y, text, d[5], owner)
    if it then
        it.entrance = d.entrance or d[4] -- (ns.DUNGEON_ENTRANCES key)
        it.minLevel, it.maxLevel = d[6], d[7]
        -- (a city map printing the place's name beside it: the icon alone)
        it.iconOnly = d.iconOnly
        it.door, it.noClick = d.door, d.noClick
        if d.style and STYLE[d.style] then it.style, it.ghost = STYLE[d.style], STYLE[d.style].hollow end
        entrances[#entrances + 1] = it
    end
    return it
end

-- Built once: map layout and instance data don't change during a session.
function Labels:Build()
    if #items > 0 then return end

    local capital = {}
    for _, id in ipairs(ns.CAPITALS) do capital[id] = true end

    -- (1.4.0-beta1, retail: every place, shown or not - RetailSpace.lua ns.SpaceAll; a floor or copy swapped in later
    -- had no name: owner.spaceHidden decides what shows)
    for _, e in ipairs(ns.SpaceAll or ns.drawList) do
        if e.lab ~= nil then
            -- (1.4.0, retail: RetailTree.lua's lab - "c" a continent's name, "z" a zone's, false none: the worlds and
            -- what lies on space or on Azeroth, whose names Blizzard's pictures print)
            if e.lab == "c" then Add(e.cx, e.cy, e.name, "continent", e)
            elseif e.lab == "z" then Add(e.cx, e.cy, e.name, "zone", e) end
        elseif e.mapType == ns.MAPTYPE_CONTINENT then
            Add(e.cx, e.cy, e.name, "continent", e)
        elseif capital[e.id] then
            local it = Add(e.cx, e.cy, e.name, "city", e)
            if it then it.capital = e.id end -- (1.0.0: gives way to the zone's printed banner, see Labels:Draw)
        else
            Add(e.cx, e.cy, e.name, "zone", e)
        end
    end

    for _, d in ipairs(ns.INSTANCES) do AddRow(d) end
    Labels:BuildDetailIcons()
    if ns.Gilneas then ns.Gilneas:AddLabels(Add) end -- (1.3.1: Gilneas's names - Gilneas.lua: no uiMap there)
end

-- (1.3.0, MinimapLayer.lua) The sub-zone names (MinimapData.lua MINIMAP_SUBZONES: at their explored-area pieces), added
-- once, when the minimap imagery first shows - they draw only over it, each while one of its pieces is explored.
local subzonesAdded = false
function Labels:AddSubzones()
    if subzonesAdded or not ns.MINIMAP_SUBZONES then return end
    subzonesAdded = true
    for id, rows in pairs(ns.MINIMAP_SUBZONES) do
        local e = ns.maps[id]
        if e and e.mapType == ns.MAPTYPE_ZONE then
            for _, r in ipairs(rows) do
                local name = r[2]
                if C_Map and C_Map.GetAreaInfo then
                    local ok, loc = pcall(C_Map.GetAreaInfo, r[1])
                    if ok and type(loc) == "string" and not (issecretvalue and issecretvalue(loc)) and loc ~= "" then name = loc end
                end
                local it = Add(e.x0 + r[3] * (e.x1 - e.x0), e.y0 + r[4] * (e.y1 - e.y0), name, "subzone", e)
                if it then
                    it.pieces = {}
                    for k = 5, #r do it.pieces[#it.pieces + 1] = r[k] end
                end
            end
        end
    end
end

-- Is one of a sub-zone label's explored-area pieces explored?
local function SubzoneExplored(it)
    if it.areaID then return ns.Gilneas ~= nil and ns.Gilneas:Explored(it.areaID) end -- (1.3.1: the fog of war, Gilneas.lua)
    local MM, P = ns.MinimapLayer, it.pieces
    if not (MM and P) then return false end
    for k = 1, #P - 3, 4 do
        if MM:PieceExplored(it.owner.id, P[k], P[k + 1], P[k + 2], P[k + 3]) then return true end
    end
    return false
end

-- (1.0.0, Doors.lua) a door learned mid-session: its row's item; every item (read only); an item moved to another world
-- point (zone: the uiMap it belongs to, else the one the game names); an item's look changed (STYLE key) - its widgets are
-- made again on the next draw.
function Labels:AddRow(d) return AddRow(d) end
-- (1.4.0-beta3, retail: RetailDoors.lua, RetailCaves.lua - the names of cities, doors, flight masters and caves from their
-- data) an item at point (x, y) of the camera's space
function Labels:Add(x, y, text, kind, owner) return Add(x, y, text, kind, owner) end
function Labels:Items() return items end

-- The dungeon icons of each detail level (ns.DETAIL_MAPS, Render.lua): at the
-- portals drawn in its art; they show while its picture does (it.detail), and
-- its entrance's own world icon gives way meanwhile (it.hideFor). A level with
-- a name label (def.label: Dalaran, whose home zone's printed banner its
-- picture covers) gets it the same way: a name shown while its picture is,
-- never a click target (not an entrance).
local function DetailName(lb)
    local name = lb.n
    if lb.ar and C_Map and C_Map.GetAreaInfo then
        local ok, loc = pcall(C_Map.GetAreaInfo, lb.ar)
        if ok and type(loc) == "string" and not (issecretvalue and issecretvalue(loc)) and loc ~= "" then name = loc end
    end
    return name
end

function Labels:BuildDetailIcons()
    for _, def in pairs(ns.DETAIL_MAPS or {}) do
        local lb = def.label
        if lb then
            local x, y, owner = ns.WorldPosToMap(def.inst or 0, lb.wx, lb.wy)
            local it = x and Add(x, y, DetailName(lb), lb.kind or "city", owner)
            if it then it.detail = def.id end
        end
        for _, p in ipairs(def.icons or {}) do
            local x, y, owner = ns.WorldPosToMap(def.inst or 0, p.wx, p.wy)
            local it = x and Add(x, y, p.n, p.kind, owner)
            if it then
                it.portal, it.detail = p, def.id
                entrances[#entrances + 1] = it
            end
        end
        -- (the entrance's world icon gives way to the level's portal icons; a level without any - the Scarlet
        -- Monastery's cave - keeps it)
        for _, it in ipairs(def.entrance and def.icons and #def.icons > 0 and entrances or {}) do
            if it.entrance == def.entrance and not it.detail then it.hideFor = def.id end
        end
    end
end

-- A label's alpha from its detail level's picture (Render:DetailAlpha).
local function DetailFade(it, a)
    local R = ns.Render
    if not (R and R.DetailAlpha) then return it.detail and 0 or a end
    if it.detail then return R:DetailAlpha(it.detail) end
    return a * (1 - R:DetailAlpha(it.hideFor))
end

-- (1.0.0) The door of the instance the player is in (it.here, Doors.lua) shows at every zoom - but a detail level's own
-- icon only with its picture, and the entrance icon that gives way to it only while the picture does not show.
local function HereAlpha(it, a)
    if it.detail then return a end
    if it.hideFor then return DetailFade(it, 1) end
    return 1
end

-- World coordinates -> world-map (947) normalized position plus the zone the
-- point belongs to (whose zoom decides when the label shows).
function ns.WorldPosToMap(instanceID, north, west)
    local contID = ns.CONTINENT_FOR_INSTANCE[instanceID]
    local cont = contID and ns.maps[contID]
    if not cont or not (C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end

    local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, instanceID, CreateVector2D(north, west), contID)
    if not ok or not pos then return nil end
    local px, py = pos:GetXY()
    if not px or not py then return nil end
    local x = cont.x0 + px * (cont.x1 - cont.x0)
    local y = cont.y0 + py * (cont.y1 - cont.y0)

    local owner
    local ok2, zoneID = pcall(C_Map.GetMapPosFromWorldPos, instanceID, CreateVector2D(north, west))
    if ok2 and zoneID and ns.maps[zoneID] and ns.maps[zoneID].mapType == ns.MAPTYPE_ZONE then
        owner = ns.maps[zoneID]
    end
    if not owner then
        for _, e in ipairs(ns.drawList) do
            if e.mapType == ns.MAPTYPE_ZONE and ns.RectContains(e, x, y)
                and (not owner or e.area < owner.area) then
                owner = e
            end
        end
    end
    return x, y, owner or cont
end

-- Flight masters are loaded per zone the first time you zoom near it.
local function LoadTaxi(zone)
    taxiLoaded[zone.id] = true
    if not ns.db.flightPaths or not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return end
    local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, zone.id)
    if not ok or type(nodes) ~= "table" then return end
    local faction = UnitFactionGroup("player")
    for _, node in ipairs(nodes) do
        local f = node.faction
        local hostile = (f == 1 and faction == "Alliance") or (f == 2 and faction == "Horde")
        local pos = node.position
        local px, py
        if pos then
            if pos.GetXY then px, py = pos:GetXY() else px, py = pos.x, pos.y end
        end
        if not hostile and px and py and px >= 0 and px <= 1 and py >= 0 and py <= 1 and node.name then
            Add(zone.x0 + (zone.x1 - zone.x0) * px, zone.y0 + (zone.y1 - zone.y0) * py,
                node.name:match("^[^,]+") or node.name, "flight", zone)
        end
    end
end

local function EnsureWidgets(it)
    if it.fs then return end
    local s = it.style
    it.fs = layer:CreateFontString(nil, "OVERLAY")
    it.fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", s.size, "OUTLINE")
    it.fs:SetTextColor(s.r, s.g, s.b)
    it.fs:SetText(it.text)
    if it.pic then
        -- ((1.4.0-beta10, retail: RetailPins.lua) the game's own icon of the place - its atlas, or a file and its coords)
        local p = it.pic
        it.dot = layer:CreateTexture(nil, "OVERLAY", nil, 2)
        if p.atlas then it.dot:SetAtlas(p.atlas) else it.dot:SetTexture(p.file) end
        if p.tc then it.dot:SetTexCoord(p.tc[1], p.tc[2], p.tc[3], p.tc[4]) end
        if p.tint then it.dot:SetVertexColor(p.tint[1], p.tint[2], p.tint[3]) end
        it.dot:SetSize(p.w, p.h)
        it.dot:Hide()
        if p.base then
            -- ((1.4.0-beta11) its base under it - a quest's round button, POIButton's NormalTexture - in the rim's place)
            it.rim = layer:CreateTexture(nil, "OVERLAY", nil, 1)
            it.rim:SetAtlas(p.base)
            it.rim:SetSize(p.bw or p.w, p.bh or p.h)
            it.rim:Hide()
        end
    elseif s.dot and not s.nodot then -- ((1.4.0-beta3) nodot: the dot's room kept, nothing drawn - a name over Blizzard's pin)
        if s.icon then
            -- (a dark rim: the icon reads on any map art)
            it.rim = layer:CreateTexture(nil, "OVERLAY", nil, 1)
            it.rim:SetTexture(DIAMOND)
            it.rim:SetSize(s.dot + 4, s.dot + 4)
            it.rim:SetVertexColor(0.05, 0.04, 0.03, 0.9)
            if it.rim.SetRotation then it.rim:SetRotation(math.rad(45)) end
            it.rim:Hide()
        end
        it.dot = layer:CreateTexture(nil, "OVERLAY", nil, s.icon and 2 or 0)
        it.dot:SetTexture(DIAMOND)
        it.dot:SetSize(s.dot, s.dot)
        it.dot:SetVertexColor(s.r, s.g, s.b)
        if it.dot.SetRotation then it.dot:SetRotation(math.rad(45)) end
        it.dot:Hide()
        if s.hollow then
            -- (1.0.0 placeholder: the diamond's dark middle - a grey outline is left)
            it.hole = layer:CreateTexture(nil, "OVERLAY", nil, 3)
            it.hole:SetTexture(DIAMOND)
            it.hole:SetSize(s.dot - 4, s.dot - 4)
            it.hole:SetVertexColor(0.05, 0.04, 0.03, 0.9)
            if it.hole.SetRotation then it.hole:SetRotation(math.rad(45)) end
            it.hole:Hide()
        end
    end
    it.fs:Hide()
    it.shown = false
    it.fsOn, it.dotOn, it.drawnA, it.fsX, it.fsY, it.dotX, it.dotY = false, false, nil, nil, nil, nil, nil -- ((1.4.0-beta15) new widgets: ShowItem)
end

-- (1.0.0) the "you are inside" marker: the round player icon over the door icon (Doors.lua pulses its alpha)
local function HereTex(it)
    if not it.hereTex then
        it.hereTex = layer:CreateTexture(nil, "OVERLAY", nil, 5)
        it.hereTex:SetTexture(HERE_FILE)
        it.hereTex:SetSize(HERE_SIZE, HERE_SIZE)
        it.hereTex:Hide()
    end
    return it.hereTex
end

local function HideItem(it)
    if not it.shown then return end
    it.shown = false
    it.drawnA, it.fsOn, it.dotOn = nil, false, false
    if it.fs then it.fs:Hide() end
    if it.dot then it.dot:Hide() end
    if it.rim then it.rim:Hide() end
    if it.hole then it.hole:Hide() end
    if it.hereTex then it.hereTex:Hide() end
end

-- Place a label's widgets: the name centred at (cx, ty) unless text is
-- false, its dot / icon at (cx, cy).
-- ((1.4.0-beta15) only what changed asked of the client, as RetailRender.lua's parts: 12 calls a marker a frame before, four a widget. One anchor each: SetPoint replaces it)
local function ShowItem(it, cx, cy, ty, text, tx)
    local a = it.alpha
    local newA = it.drawnA ~= a
    it.drawnA = a
    local fs = it.fs
    if text then
        local fx = tx or cx
        if it.fsX ~= fx or it.fsY ~= ty then
            fs:SetPoint("CENTER", layer, "TOPLEFT", fx, -ty)
            it.fsX, it.fsY = fx, ty
        end
        if newA or not it.fsOn then fs:SetAlpha(a) end
        if not it.fsOn then
            fs:Show()
            it.fsOn = true
        end
    elseif it.fsOn ~= false then
        fs:Hide()
        it.fsOn = false
    end
    local moved = it.dotX ~= cx or it.dotY ~= cy
    if moved then it.dotX, it.dotY = cx, cy end
    if it.dot then
        local d = it.dot
        if moved then d:SetPoint("CENTER", layer, "TOPLEFT", cx, -cy) end
        if newA then d:SetAlpha(a) end
        local first = not it.dotOn
        if first then
            d:Show()
            it.dotOn = true
        end
        if it.rim then
            if moved then it.rim:SetPoint("CENTER", layer, "TOPLEFT", cx, -cy) end
            if newA then it.rim:SetAlpha(a) end
            if first then it.rim:Show() end
        end
        if it.hole then
            if moved then it.hole:SetPoint("CENTER", layer, "TOPLEFT", cx, -cy) end
            if newA then it.hole:SetAlpha(a) end
            if first then it.hole:Show() end
        end
    end
    if it.here then
        local t = HereTex(it)
        t:ClearAllPoints()
        t:SetPoint("CENTER", layer, "TOPLEFT", cx, -cy)
        t:SetAlpha(it.alpha)
        t:Show()
    elseif it.hereTex then
        it.hereTex:Hide()
    end
end

-- (noGhost: placeholders' name + icon rects don't count, their icons' own rects do - two close placeholders both keep
-- their icons, never one on the other)
local function Overlaps(x0, y0, x1, y1, count, noGhost, level)
    softA = 0
    for i = 1, count, 4 do
        if not (noGhost and placedGhost[i]) and x0 < placed[i + 2] and x1 > placed[i] and y0 < placed[i + 3] and y1 > placed[i + 1] then
            local s = placedSoft[i]
            if not s or s >= 0.97 or (level and placedLevel[i] == level) then return true end
            if s > softA then softA = s end
        end
    end
    return false
end

-- (1.0.0) Two labels of the same priority and alpha keep one order (the order they were made in): before, the sort left
-- it open, and which of two overlapping names showed could change whenever another label entered or left the view.
local function ByPriority(a, b)
    if a.prio ~= b.prio then return a.prio > b.prio end
    if a.alpha ~= b.alpha then return a.alpha > b.alpha end
    return a.seq < b.seq
end

-- ((1.4.0-beta16, retail - WoW Forever walks them all, as before) Over a thousand markers tested each frame was a tenth of the add-on's Lua: those in the view by a grid over the
-- items - when the view covers little of it -, those shown last frame apart (prevShown). An item moved says so: Labels:Moved. And at most NEW_WIDGETS markers a frame get their
-- widgets, the most important first: a zoom out bringing in many maps made them all in one frame - up to 39 ms in the player's stamp.
local RETAIL = ns.FLAVOR == "retail"
local GRID_N = 48
local NEW_WIDGETS = 12
local gridOf, gridN, gridDirty, gridX0, gridY0, gridKX, gridKY
local cand, prevShown = {}, {}
local prevN, drawTick = 0, 0
function Labels:Moved() gridDirty = true end
local function BuildGrid()
    gridOf, gridN, gridDirty = {}, #items, false
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for i = 1, gridN do
        local it = items[i]
        if it.x < x0 then x0 = it.x end
        if it.x > x1 then x1 = it.x end
        if it.y < y0 then y0 = it.y end
        if it.y > y1 then y1 = it.y end
    end
    gridX0, gridY0 = x0, y0
    gridKX, gridKY = GRID_N / math.max(x1 - x0, 1e-9), GRID_N / math.max(y1 - y0, 1e-9)
    for i = 1, gridN do
        local it = items[i]
        local k = math.min(GRID_N - 1, math.floor((it.y - y0) * gridKY)) * GRID_N + math.min(GRID_N - 1, math.floor((it.x - x0) * gridKX))
        local b = gridOf[k]
        if not b then
            b = {}
            gridOf[k] = b
        end
        b[#b + 1] = it
    end
end
-- (the items in the cells over x0 .. y1, their count; nil: the view covers much of the grid - all of them)
local function Candidates(x0, y0, x1, y1)
    if not gridOf or gridDirty or gridN ~= #items then BuildGrid() end
    local c0, c1 = math.max(0, math.floor((x0 - gridX0) * gridKX)), math.min(GRID_N - 1, math.floor((x1 - gridX0) * gridKX))
    local r0, r1 = math.max(0, math.floor((y0 - gridY0) * gridKY)), math.min(GRID_N - 1, math.floor((y1 - gridY0) * gridKY))
    if (c1 - c0 + 1) * (r1 - r0 + 1) > GRID_N * GRID_N / 4 then return nil end
    local n = 0
    for r = r0, r1 do
        for c = c0, c1 do
            local b = gridOf[r * GRID_N + c]
            if b then
                for i = 1, #b do
                    n = n + 1
                    cand[n] = b[i]
                end
            end
        end
    end
    return cand, n
end

function Labels:Draw(cam, v)
    local W, H = v.W, v.H
    local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)

    -- Lazily pull flight masters for zones we are zoomed into. (1.4.0: not on retail - Blizzard pins them there)
    if ns.db.flightPaths and ns.FLAVOR ~= "retail" then
        for _, e in ipairs(ns.drawList) do
            if e.mapType == ns.MAPTYPE_ZONE and not taxiLoaded[e.id] and ns.RectContains(e, cam.x, cam.y)
                and ns.ZoomOf(v, e, cam.vw) >= 0.6 then
                LoadTaxi(e)
            end
        end
    end

    local n = 0
    local mm = ns.MinimapLayer ~= nil and ns.MinimapLayer:Active() -- (1.3.0: the minimap imagery shows)
    -- ((1.4.0-beta15) a marker off the view - the most of over a thousand, each frame: one test, in the camera's units, the screen's margins below)
    local wx0, wx1 = cam.x + (-60 - W / 2) / ppx, cam.x + (W + 60 - W / 2) / ppx
    local wy0, wy1 = cam.y + (-20 - H / 2) / ppy, cam.y + (H + 20 - H / 2) / ppy
    local walk, walkN = items, #items
    if RETAIL then
        local c, cn = Candidates(wx0, wy0, wx1, wy1)
        if c then walk, walkN = c, cn end
        drawTick = drawTick + 1
    end
    for ii = 1, walkN do
      local it = walk[ii]
      it.cTick = drawTick
      local ix, iy = it.x, it.y
      if ix <= wx0 or ix >= wx1 or iy <= wy0 or iy >= wy1 then
        if it.shown then HideItem(it) end
      else
        local sx = W / 2 + (ix - cam.x) * ppx
        local sy = H / 2 + (iy - cam.y) * ppy
        local a, own = 0, 0
        if sx > -60 and sx < W + 60 and sy > -20 and sy < H + 20
            and (it.kind ~= "flight" or ns.db.flightPaths)
            and ns.db[it.style.gate or (it.style.icon and "dungeonIcons" or "placeNames")] ~= false -- (Azeroth Unrolled 1.0.0: the two halves of the layer; 1.4.0-beta3: a style's own gate)
            and not it.off and not (it.ghost and ns.db.doorHints == false) -- (1.0.0: retired / placeholders off)
            and not it.owner.spaceHidden then -- (1.4.0, retail: a map the game does not show now - RetailSpace.lua)
            -- (1.3.1: Gilneas's names - it.homemade - in the imagery's bands everywhere: its page prints no names either)
            -- ((1.4.0-beta10, retail: RetailPins.lua - it.mapBand) a map's own marker comes and goes with that map's picture
            -- (Render:MapAlpha): every map drawn shows its own, each at once - not a band of its own zoom)
            if it.worldOn or it.worldOff then
                -- ((1.4.0-beta14: Portals.lua) from a zoom of the world, whatever map it lies on: a band of 8%)
                -- ((1.6.0, WoW Forever: Pins.lua's quests) it.worldOff: up to that zoom instead - a continent's tracked
                -- quest; it.orOwn: or from that zoom of its own map, should it come first - a zone's quests from the zone's
                -- fit, where Blizzard's map of it showed them; it.ownFrom: and not before that zoom of its own map - a
                -- continent's from its fit, where Blizzard's map is that continent)
                local g = it.worldOn or it.worldOff
                local t = (ns.WorldZoom(v, cam.vw) - g * 0.92) / (g * 0.08)
                a = t <= 0 and 0 or t >= 1 and 1 or t * t * (3 - 2 * t)
                if it.worldOff then a = 1 - a end
                local k = it.orOwn or it.ownFrom
                if k then
                    local u = (ns.ZoomOf(v, it.owner, cam.vw) - k * 0.92) / (k * 0.08)
                    u = u <= 0 and 0 or u >= 1 and 1 or u * u * (3 - 2 * u)
                    if it.orOwn then a = math.max(a, u) else a = a * u end
                end
            elseif it.mapBand then
                a = ns.Render:MapAlpha(it.owner)
            else
                a = AlphaFor(it.kind, ns.ZoomOf(v, it.owner, cam.vw), it.owner, v, mm or it.homemade == true)
            end
            if it.zmin and a > 0 then
                -- ((1.4.0-beta11) it.zmin: not before its map is this deep - see ZMIN_RAMP; (1.6.0) whatever its band:
                -- WoW Forever's quest hubs' offers too)
                local z = ns.ZoomOf(v, it.owner, cam.vw)
                local t = (z - it.zmin * ZMIN_RAMP) / (it.zmin * (1 - ZMIN_RAMP))
                a = a * (t <= 0 and 0 or t >= 1 and 1 or t * t * (3 - 2 * t))
            end
            -- (1.3.0: a sub-zone's name; 1.3.1: the fog of war - Gilneas's, it.areaID)
            if (it.pieces or it.areaID) and a > 0 and not SubzoneExplored(it) then a = 0 end
            it.soft = nil
            if it.detail or it.hideFor then
                a = DetailFade(it, a)
                -- (1.0.0: part-faded by the switch right now? see placedSoft)
                local d = ns.Render.DetailAlpha and ns.Render:DetailAlpha(it.detail or it.hideFor) or 0
                if d > 0.03 and d < 0.97 then it.soft = true end
            end
            -- (1.0.0) a capital's name gives way while its zone's drawing prints it (the banner, below the city switch)
            if it.capital and a > 0 and ns.Render.CityNameFade then
                local k, timed = ns.Render:CityNameFade(it.capital, v, cam.vw)
                a = a * k
                -- (1.0.0 review: soft only while the switch's timed fade moves it - part-faded by the zoom band at rest it
                -- lay half-drawn over another name, e.g. Undercity over the Ruins of Lordaeron door)
                if k < 0.97 and timed then it.soft = true end
            end
            own = a
            if it.here then a = HereAlpha(it, a) end
        end
        if a > 0.03 then
            n = n + 1
            it.hereOnly = (it.here and own <= 0.03) or nil -- (1.0.0: the "you are inside" door beyond its band - its icon)
            it.alpha, it.sx, it.sy, it.prio = a, sx, sy, it.hereOnly and HERE_PRIO or it.style.prio
            sortBuf[n] = it
        else
            HideItem(it)
        end
      end
    end
    for i = n + 1, #sortBuf do sortBuf[i] = nil end
    table.sort(sortBuf, ByPriority)
    if RETAIL then
        -- ((1.4.0-beta16) shown last frame and out of the walk: gone; those with no widgets yet beyond the frame's few wait for the next draw - asked for at rest too)
        for i = 1, prevN do
            local it = prevShown[i]
            if it.cTick ~= drawTick and it.shown then HideItem(it) end
        end
        local m, made = 0, 0
        for i = 1, n do
            local it = sortBuf[i]
            if it.fs or made < NEW_WIDGETS then
                if not it.fs then made = made + 1 end
                m = m + 1
                sortBuf[m] = it
            end
        end
        if m < n then
            for i = n, m + 1, -1 do sortBuf[i] = nil end
            n = m
            if ns.Core and ns.Core.Redraw then ns.Core.Redraw() end
        end
    end

    local count = 0
    -- (1.0.0) The instance icons of a detail level (it.portal) keep their ICON whenever the level shows - each is a click
    -- target, and at the world zoom the level now appears from, two of Blackrock Mountain's are 16 px apart: their icon
    -- rects are taken first, names are placed after them (a name never covers such an icon).
    for i = 1, n do
        local it = sortBuf[i]
        it.iconKept = nil
        if it.portal and it.style.icon then
            local half = DotHalf(it.style)
            if it.sx + half >= 0 and it.sx - half <= W and it.sy + half >= 0 and it.sy - half <= H then
                placed[count + 1], placed[count + 2], placed[count + 3], placed[count + 4] = it.sx - half, it.sy - half, it.sx + half, it.sy + half
                placedGhost[count + 1] = false
                placedSoft[count + 1] = it.soft and it.alpha or false
                placedLevel[count + 1] = it.detail or false
                count = count + 4
                it.iconKept = true
            end
        end
    end
    for i = 1, n do
        local it = sortBuf[i]
        EnsureWidgets(it)
        if not it.tw or it.tw <= 0 then it.tw = it.fs:GetStringWidth() end
        local tw = (it.tw and it.tw > 0) and it.tw or 40
        local th = it.style.size + 2
        local cx, cy = it.sx, it.sy
        local half = ItemHalf(it) -- ((1.4.0-beta3) a nodot style's too: its name over the point; (1.4.0-beta10) it.pic's)
        local ty = half and (cy - half - 2 - th / 2) or cy
        local x0, x1 = cx - tw / 2 - 2, cx + tw / 2 + 2
        local y0, y1 = ty - th / 2, ty + th / 2
        if half and not it.iconKept then y1 = cy + half end -- (iconKept: the name's own rect - its icon has one already)
        local text = not it.iconOnly and not it.hereOnly
        if not text then x0, y0, x1, y1 = cx - half, cy - half, cx + half, cy + half end
        -- (1.0.0 review) a placeholder whose name the map's edge would cut (The Drowned City, at Stranglethorn's west edge)
        -- has the name moved inside the map while its icon is on it (the icon stays at its point); an icon leaving the map
        -- takes the name along beside it, so the name never jumps while the map moves
        local tx, soft = cx, 0 -- (soft: how much a part-faded label of the city switch covers this one, see placedSoft)
        -- ((1.4.0-beta12, retail) every icon's name kept on the map so, not a placeholder's alone, and one the map's top edge
        -- would cut above its icon goes under it - the player's 1.4.0-beta11 photo 4: a raid's door at the top edge, its
        -- name above it off the map, the door nameless)
        local keepIn = half and (it.ghost or ns.FLAVOR == "retail")
        local below = false
        if text and keepIn and tw + 8 < W then
            tx = math.max(cx, math.min(tw / 2 + 4, cx + tw / 2 + 4))
            tx = math.min(tx, math.max(W - tw / 2 - 4, cx - tw / 2 - 4))
            x0, x1 = math.min(tx - tw / 2 - 2, cx - half), math.max(tx + tw / 2 + 2, cx + half)
        end
        if text and keepIn and ns.FLAVOR == "retail" and ty - th / 2 < 0 and cy >= 0 then
            below = true
            ty = cy + half + 2 + th / 2
            y0, y1 = it.iconKept and (ty - th / 2) or (cy - half), ty + th / 2
        end
        if text and (x1 < 0 or x0 > W or y1 < 0 or y0 > H or Overlaps(x0, y0, x1, y1, count, nil, it.detail)) then
            -- (a dungeon / raid whose name has no room keeps its icon when the
            -- icon itself has: every entrance stays clickable, the tooltip names it)
            text = false
            if it.style.icon then x0, y0, x1, y1 = cx - half, cy - half, cx + half, cy + half end
        elseif text then
            soft = softA
        end
        -- (1.0.0) the "you are inside" door keeps its icon wherever another label lies; a placeholder's icon gives way to
        -- no other placeholder (Barrow Deeps beside Hyjal Summit's name: both icons show)
        if it.iconKept then
            if text then
                placed[count + 1], placed[count + 2], placed[count + 3], placed[count + 4] = x0, y0, x1, y1
                placedGhost[count + 1] = false
                placedSoft[count + 1] = it.soft and it.alpha or false
                placedLevel[count + 1] = it.detail or false
                count = count + 4
                if below then
                    x0, y0, x1 = math.min(x0, cx - half), cy - half, math.max(x1, cx + half)
                else
                    x0, x1, y1 = math.min(x0, cx - half), math.max(x1, cx + half), cy + half
                end
            end
            it.shown = true
            it.x0, it.y0, it.x1, it.y1 = x0, y0, x1, y1
            ShowItem(it, cx, cy, ty, text, tx)
        elseif not text and (not it.style.icon or x1 < 0 or x0 > W or y1 < 0 or y0 > H
            or (not it.here and not it.always and Overlaps(x0, y0, x1, y1, count, it.ghost, it.detail))) then
            HideItem(it)
        elseif it.alpha * (1 - ((text or it.here or it.always) and soft or softA)) <= 0.03 then
            HideItem(it) -- (1.0.0: all of it under a part-faded label of the city switch)
        else
            -- (1.0.0: as much of it as a part-faded label of the city switch lets through; not text: its icon's own
            -- rect was tested just above)
            -- ((1.4.0-beta11) it.always: no rect tested - softA is another item's: not this one's)
            it.alpha = it.alpha * (1 - ((text or it.here or it.always) and soft or softA))
            placed[count + 1], placed[count + 2], placed[count + 3], placed[count + 4] = x0, y0, x1, y1
            placedGhost[count + 1] = (it.ghost and text) and true or false
            placedSoft[count + 1] = it.soft and it.alpha or false
            placedLevel[count + 1] = it.detail or false
            count = count + 4
            if it.ghost and text then
                -- (its icon's own rect as well: another placeholder's icon may sit beside this name, never on this icon)
                placed[count + 1], placed[count + 2], placed[count + 3], placed[count + 4] = cx - half, cy - half, cx + half, cy + half
                placedGhost[count + 1] = false
                placedSoft[count + 1] = false
                placedLevel[count + 1] = false
                count = count + 4
            end
            it.shown = true
            it.x0, it.y0, it.x1, it.y1 = x0, y0, x1, y1 -- (placed rect, container units)
            ShowItem(it, cx, cy, ty, text, tx)
        end
    end
    if RETAIL then
        local m = 0
        for i = 1, n do
            local it = sortBuf[i]
            if it.shown then
                m = m + 1
                prevShown[m] = it
            end
        end
        prevN = m
    end
end

function Labels:HideAll()
    for _, it in ipairs(items) do HideItem(it) end
end

-- (Dungeon.lua) the shown entrance whose ICON is at container point (x, y):
-- a 20 x 20 px square around the diamond (the name above it doesn't
-- count); the nearest one if two squares touch.
function Labels:HitTest(x, y)
    if not (x and y) then return nil end
    local best, bestD
    for _, it in ipairs(entrances) do
        if it.shown and it.x0 and it.sx and (it.alpha or 0) >= 0.5 then
            local dx, dy = math.abs(x - it.sx), math.abs(y - it.sy)
            if dx <= ICON_HIT and dy <= ICON_HIT and (not best or dx * dx + dy * dy < bestD) then
                best, bestD = it, dx * dx + dy * dy
            end
        end
    end
    return best
end

-- Hovered or plain look of an entrance: white name, white diamond 1.25x.
local function Paint(it, lit)
    local s = it.style
    if it.fs then
        if lit then it.fs:SetTextColor(1, 1, 1) else it.fs:SetTextColor(s.r, s.g, s.b) end
    end
    if it.dot and it.pic then
        -- ((1.4.0-beta10, retail: RetailPins.lua) the game's icon: grown, its own colours)
        local k = lit and HOT_GROW or 1
        local p = it.pic
        it.dot:SetSize(p.w * k, p.h * k)
        if it.rim then it.rim:SetSize((p.bw or p.w) * k, (p.bh or p.h) * k) end
    elseif it.dot then
        local k = lit and HOT_GROW or 1
        it.dot:SetSize(s.dot * k, s.dot * k)
        if lit then it.dot:SetVertexColor(1, 1, 1) else it.dot:SetVertexColor(s.r, s.g, s.b) end
        if it.rim then it.rim:SetSize((s.dot + 4) * k, (s.dot + 4) * k) end
        if it.hole then it.hole:SetSize((s.dot - 4) * k, (s.dot - 4) * k) end
    end
end

-- (Dungeon.lua) light up the entrance icon under the cursor (nil: none).
function Labels:SetHot(it)
    if hot == it then return end
    if hot then Paint(hot, false) end
    hot = it
    if it then Paint(it, true) end
end

-- (1.0.0, Doors.lua) a door learned in game: its item moves to world point (c: 0 / 1, x north, y west; zone: the uiMap it
-- belongs to, else the one the game names) - false if the game cannot place it.
function Labels:MoveItem(it, c, x, y, zone)
    local mx, my, owner = ns.WorldPosToMap(c, x, y)
    if not mx then return false end
    if zone and ns.maps[zone] then owner = ns.maps[zone] end
    HideItem(it)
    it.x, it.y, it.owner = mx, my, owner
    gridDirty = true
    return true
end

-- ((1.4.0-beta10, retail: RetailPins.lua) an item whose name or picture changed (the game updated a marker): its widgets
-- made again on the next draw)
function Labels:Reset(it)
    if hot == it then Labels:SetHot(nil) end
    HideItem(it)
    for _, k in ipairs({ "fs", "dot", "rim", "hole" }) do
        if it[k] then it[k]:Hide() it[k] = nil end
    end
    it.tw = nil
end

-- (1.0.0, Doors.lua) an item's look (a STYLE key: a placeholder that became a learned door): the old widgets are hidden
-- and made again, in the new look, when the item is next drawn.
function Labels:SetStyle(it, key)
    local st = STYLE[key]
    if not st or it.style == st then return end
    if hot == it then Labels:SetHot(nil) end
    HideItem(it)
    for _, k in ipairs({ "fs", "dot", "rim", "hole" }) do
        if it[k] then it[k]:Hide() it[k] = nil end
    end
    it.style, it.ghost, it.tw = st, st.hollow, nil
end
