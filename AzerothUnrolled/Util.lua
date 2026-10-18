local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)

---------------------------------------------------------------------------
-- Math
---------------------------------------------------------------------------
local exp, log, sqrt, abs = math.exp, math.log, math.sqrt, math.abs

function ns.Clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

function ns.Clamp01(v)
    if v < 0 then return 0 elseif v > 1 then return 1 end
    return v
end

function ns.Smooth(v)
    v = ns.Clamp01(v)
    return v * v * (3 - 2 * v)
end

function ns.EaseInOutCubic(t)
    t = ns.Clamp01(t)
    if t < 0.5 then return 4 * t * t * t end
    local f = -2 * t + 2
    return 1 - f * f * f / 2
end

-- Rises from 0 to 1 over [a0, a1], falls back to 0 over [b0, b1].
function ns.Band(z, a0, a1, b0, b1)
    local rise = (a1 > a0) and ns.Smooth((z - a0) / (a1 - a0)) or (z >= a0 and 1 or 0)
    if not b0 then return rise end
    return rise * (1 - ns.Smooth((z - b0) / (b1 - b0)))
end

-- Lua 5.1 in WoW has cosh/sinh/tanh, but don't depend on it.
function ns.Cosh(x) local e = exp(x) return (e + 1 / e) / 2 end
function ns.Sinh(x) local e = exp(x) return (e - 1 / e) / 2 end
function ns.Tanh(x)
    if x > 20 then return 1 elseif x < -20 then return -1 end
    local e2 = exp(2 * x)
    return (e2 - 1) / (e2 + 1)
end

-- Van Wijk & Nuij "smooth and efficient zooming and panning".
-- Views are (cx, cy, w) in a uniform space. Returns total path length S and
-- an interpolator f(s) -> cx, cy, w for s in [0, S].
function ns.ZoomPath(x0, y0, w0, x1, y1, w1, rho)
    rho = rho or 1.4
    local rho2, rho4 = rho * rho, rho * rho * rho * rho
    local dx, dy = x1 - x0, y1 - y0
    local u1 = sqrt(dx * dx + dy * dy)

    if u1 < 1e-6 * math.max(w0, w1) then
        if abs(w1 - w0) < 1e-12 then
            return 0, function() return x1, y1, w1 end
        end
        local k = (w1 > w0) and 1 or -1
        local S = abs(log(w1 / w0)) / rho
        return S, function(s)
            return x0 + dx * (S > 0 and s / S or 1), y0 + dy * (S > 0 and s / S or 1), w0 * exp(k * rho * s)
        end
    end

    local b0 = (w1 * w1 - w0 * w0 + rho4 * u1 * u1) / (2 * w0 * rho2 * u1)
    local b1 = (w1 * w1 - w0 * w0 - rho4 * u1 * u1) / (2 * w1 * rho2 * u1)
    local r0 = log(-b0 + sqrt(b0 * b0 + 1))
    local r1 = log(-b1 + sqrt(b1 * b1 + 1))
    local S = (r1 - r0) / rho
    if not (S == S) or S <= 0 or S == math.huge or not (r0 == r0) or math.abs(r0) > 700 then
        -- Numerically hopeless (huge zoom ratio with a tiny pan): plain
        -- log-zoom with a linear pan instead.
        S = math.max(abs(log(w1 / w0)) / rho, 1e-6)
        return S, function(s)
            local f = s / S
            return x0 + dx * f, y0 + dy * f, w0 * exp(log(w1 / w0) * f)
        end
    end
    local coshR0 = ns.Cosh(r0)
    local sinhR0 = ns.Sinh(r0)

    return S, function(s)
        local u = w0 / rho2 * coshR0 * ns.Tanh(rho * s + r0) - w0 / rho2 * sinhR0
        local w = w0 * coshR0 / ns.Cosh(rho * s + r0)
        local f = u / u1
        return x0 + dx * f, y0 + dy * f, w
    end
end

---------------------------------------------------------------------------
-- Map registry: every continent/zone we can place on the world map
---------------------------------------------------------------------------
ns.WORLD_MAP_ID = 947

local UIMAPTYPE = (Enum and Enum.UIMapType) or {}
ns.MAPTYPE_WORLD = UIMAPTYPE.World or 1
ns.MAPTYPE_CONTINENT = UIMAPTYPE.Continent or 2
ns.MAPTYPE_ZONE = UIMAPTYPE.Zone or 3

local maps = {}        -- [mapID] = entry
local drawList = {}    -- continents + zones, sorted for drawing
ns.maps = maps
ns.drawList = drawList

-- Normalized rect (x0, x1, y0, y1) of mapID drawn on topMapID, or nil.
function ns.RectOn(mapID, topMapID)
    if mapID == topMapID then return 0, 1, 0, 1 end
    local ok, x0, x1, y0, y1 = pcall(C_Map.GetMapRectOnMap, mapID, topMapID)
    if not ok or type(x0) ~= "number" or type(x1) ~= "number" or type(y0) ~= "number" or type(y1) ~= "number" then
        return nil
    end
    if x1 < x0 then x0, x1 = x1, x0 end
    if y1 < y0 then y0, y1 = y1, y0 end
    if (x1 - x0) <= 1e-5 or (y1 - y0) <= 1e-5 then return nil end
    return x0, x1, y0, y1
end

-- Rect of mapID on the world map, composed up the parent chain
-- (zone -> continent -> world), which is what Blizzard/HereBeDragons rely on.
local worldRectCache = {}
function ns.WorldRect(mapID, depth)
    if mapID == ns.WORLD_MAP_ID then return 0, 1, 0, 1 end
    local c = worldRectCache[mapID]
    if c then
        if c == false then return nil end
        return c[1], c[2], c[3], c[4]
    end
    depth = depth or 0
    local info = C_Map.GetMapInfo(mapID)
    local parent = info and info.parentMapID
    local x0, x1, y0, y1
    if parent and parent ~= 0 and depth < 8 then
        local a0, a1, b0, b1 = ns.RectOn(mapID, parent)
        local p0, p1, q0, q1 = ns.WorldRect(parent, depth + 1)
        if a0 and p0 then
            x0, x1 = p0 + a0 * (p1 - p0), p0 + a1 * (p1 - p0)
            y0, y1 = q0 + b0 * (q1 - q0), q0 + b1 * (q1 - q0)
        end
    end
    if not x0 then
        x0, x1, y0, y1 = ns.RectOn(mapID, ns.WORLD_MAP_ID)
    end
    worldRectCache[mapID] = x0 and { x0, x1, y0, y1 } or false
    return x0, x1, y0, y1
end

local function ArtSize(mapID)
    local layers = C_Map.GetMapArtLayers(mapID)
    local L = layers and layers[1]
    if L and L.layerWidth and L.layerWidth > 0 and L.layerHeight and L.layerHeight > 0 then
        return L.layerWidth, L.layerHeight
    end
end

local function AddMap(mapID, info)
    if maps[mapID] then return maps[mapID] end
    local x0, x1, y0, y1 = ns.WorldRect(mapID)
    local lw, lh = ArtSize(mapID)
    if not x0 or not lw then return nil end
    local e = {
        id = mapID,
        name = info and info.name or "",
        mapType = info and info.mapType,
        parent = info and info.parentMapID,
        x0 = x0, x1 = x1, y0 = y0, y1 = y1,
        cx = (x0 + x1) / 2, cy = (y0 + y1) / 2,
        lw = lw, lh = lh,
        area = (x1 - x0) * (y1 - y0),
        nest = 0,
    }
    maps[mapID] = e
    return e
end

function ns.BuildRegistry()
    wipe(maps)
    wipe(drawList)
    wipe(worldRectCache)

    local worldInfo = C_Map.GetMapInfo(ns.WORLD_MAP_ID)
    local world = AddMap(ns.WORLD_MAP_ID, worldInfo)
    if not world then return false end
    world.isWorld = true

    local all = C_Map.GetMapChildrenInfo(ns.WORLD_MAP_ID, nil, true) or {}
    for _, info in ipairs(all) do
        local t = info.mapType
        if t == ns.MAPTYPE_CONTINENT or t == ns.MAPTYPE_ZONE then
            local e = AddMap(info.mapID, info)
            if e then drawList[#drawList + 1] = e end
        end
    end

    -- Maps whose rect sits fully inside another zone's rect (cities inside a
    -- zone) are always drawn above it.
    for _, a in ipairs(drawList) do
        if a.mapType == ns.MAPTYPE_ZONE then
            for _, b in ipairs(drawList) do
                if b ~= a and b.mapType == ns.MAPTYPE_ZONE
                    and a.x0 >= b.x0 and a.x1 <= b.x1 and a.y0 >= b.y0 and a.y1 <= b.y1
                    and a.area < b.area then
                    a.nest = a.nest + 1
                end
            end
        end
    end

    table.sort(drawList, function(a, b)
        if a.mapType ~= b.mapType then return a.mapType < b.mapType end -- continents first
        if a.nest ~= b.nest then return a.nest < b.nest end
        if a.area ~= b.area then return a.area > b.area end
        return a.id < b.id
    end)
    for i, e in ipairs(drawList) do e.order = i end
    for _, e in pairs(maps) do ns.SetStretch(e) end

    -- Area the camera may roam: the world map plus anything poking out of it.
    local b = { x0 = 0, x1 = 1, y0 = 0, y1 = 1 }
    for _, e in ipairs(drawList) do
        b.x0, b.x1 = math.min(b.x0, e.x0), math.max(b.x1, e.x1)
        b.y0, b.y1 = math.min(b.y0, e.y0), math.max(b.y1, e.y1)
    end
    ns.bounds = b
    return true
end

-- Map rects aren't exactly the art's aspect (float rounding in the game
-- data, up to ~0.1%). Stretch our art vertically by this factor so it spans
-- exactly the rect, which is how Blizzard positions everything vertically.
function ns.SetStretch(e)
    local world = maps[ns.WORLD_MAP_ID]
    if not world or e.isWorld then
        e.ky = 1
        return
    end
    e.ky = ((e.y1 - e.y0) / (e.x1 - e.x0)) * (e.lw / e.lh) * (world.lh / world.lw)
end

function ns.GetMap(mapID)
    local e = maps[mapID]
    if e then return e end
    if not mapID or not maps[ns.WORLD_MAP_ID] then return nil end
    -- A map that wasn't a continent/zone descendant (e.g. opened directly).
    local info = C_Map.GetMapInfo(mapID)
    if info and (info.mapType == ns.MAPTYPE_CONTINENT or info.mapType == ns.MAPTYPE_ZONE) then
        e = AddMap(mapID, info)
        if e then ns.SetStretch(e) end
        return e
    end
end

-- Absolute frame level that sticks even when WorldMapFrame gets raised
-- (toplevel), the same way Questie pins its icons' levels.
function ns.SetLevelFixed(f, level)
    if f.SetFixedFrameLevel then
        f:SetFixedFrameLevel(false)
        f:SetFrameLevel(level)
        f:SetFixedFrameLevel(true)
    else
        f:SetFrameLevel(level)
    end
end

function ns.RectContains(e, x, y)
    return x >= e.x0 and x <= e.x1 and y >= e.y0 and y <= e.y1
end

-- The most detailed map at world-map point (x, y): the smallest rect of ns.drawList holding it, else the world map.
-- The wheel's depth limit counts from it (Core.lua), and so does a cave's switch where that limit is shallower (Render.lua).
-- (1.3.1) ns.extraZones: zones the add-on draws itself where Blizzard ships no map (Gilneas.lua) - entries with a zone
-- map's rect and art size, virtual (a negative id: never a uiMap); realOnly leaves them out (a caller that asks C_Map).
function ns.DeepestMapAt(x, y, realOnly)
    local best
    for _, e in ipairs(drawList) do
        if ns.RectContains(e, x, y) and (not best or e.area < best.area) then best = e end
    end
    if not realOnly and ns.extraZones then
        for _, e in ipairs(ns.extraZones) do
            if ns.RectContains(e, x, y) and (not best or e.area < best.area) then best = e end
        end
    end
    return best or ns.maps[ns.WORLD_MAP_ID]
end
