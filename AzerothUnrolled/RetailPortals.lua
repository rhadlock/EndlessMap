--[[
Endless Map - RetailPortals.lua (1.4.0-beta14; retail only: AzerothUnrolled_Standard.toc, after RetailPins.lua)

The world's ways across: every portal, boat, zeppelin and tram, and where it goes - the player on 1.4.0-beta13: "show all the portals
and where they go if you hover over them, like an arking line, then if you click on a portal it does the same arc transition to the
ending lcoation we use to move to a player or party member, the world is big and confusing". The data is the game's own travel graph
(RETAIL_PLACES.portals: WaypointNode, WaypointEdge, WaypointSafeLocs - tools/retail/build_places.py; docs/retail-engine.md 23.4).

  * A HUB is the ways leaving one place (within HUB_YARDS): one marker, the character's faction's ways only. Its zoom is the zoom's alone
    (Labels.lua it.worldOn): a hub of HUB_BIG ways or more - a capital's portal room, the world's crossroads - with the continents' pictures
    (CONT_ON), so a wide view shows how the world connects; every other with the zones' maps (the band). A click needs no fight's end: a
    flight moves no Blizzard frame.
  * THE HOVER: over a marker its ways' arcs are drawn from it, dim, and its list opens beside it, a row a way and what a click does, staying
    while the cursor is on the marker, on the list or between them. The way under the cursor - the only one of a marker of one, or a row -
    brightens, sparks running along it to its end, its end's name where it leaves the view.
  * THE CLICK: on a way, a flight to its end - Core.lua FlyToView, the flight of a click on a party member (a zoom-arc flight). On a hub of
    several the list is the choice: a click on the marker itself does nothing more.
  * Nothing here takes the mouse: the map's own click (Core.lua OurClick) asks PT:OnCanvasClick; the hover reads the cursor's place.
Nothing here writes a Blizzard frame. /emap portals: the markers off.
]]
local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)
if ns.FLAVOR ~= "retail" then return end

local P = ns.RETAIL_PLACES
local Labels = ns.Labels
if type(P) ~= "table" or type(P.portals) ~= "table" or not (Labels and Labels.Add) then return end

local PT = {}
ns.RetailPortals = PT

local STYLE = Labels.STYLE
STYLE.portal = { size = 9, r = 0.80, g = 0.65, b = 1.00, prio = 30, icon = true, gate = "portals" }

local ICONS = { p = "portal", b = "boat", z = "zeppelin", t = "tram" }
local function IconFile(k)
    return "Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\" .. (ICONS[k] or "portal") .. ".tga"
end
local KIND_NAMES = { p = "Portal", b = "Boat", z = "Zeppelin", t = "Tram" }

local HUB_BIG = 3           -- a marker of so many ways is the world's crossroads: from the continents' zoom
local WORLD_BIG = 1.75      -- (RetailRender.lua CONT_ON)
local ICON, ICON_BIG = 18, 22
local HIT_PAD = 3
local ROW_H, ROW_W, ROW_PAD = 18, 190, 4
local SEGS = 40             -- an arc's straight pieces
local BULGE, BULGE_MAX = 0.22, 170 -- its height: this share of its length, at most this many px
local SPARKS, SPARK_SPEED = 3, 0.45
local THICK, THICK_HOT = 2, 3
local DIM = { 0.72, 0.58, 1.00, 0.55 }
local HOT = { 1.00, 0.92, 0.55, 1.00 }

local hubs = {}             -- the hubs' items (for the character's faction)
local built = false
local layer                 -- the frame the arcs and the list lie in
local hover                 -- the hub the hover is on
local rowOn                 -- the way under the cursor
local lines, sparks, rows = {}, {}, {}
local endText

local function Num(v) return type(v) == "number" and v == v and not (issecretvalue and issecretvalue(v)) end
local function Str(v) return type(v) == "string" and not (issecretvalue and issecretvalue(v)) end

---------------------------------------------------------------------------
-- The markers
---------------------------------------------------------------------------
local function Build()
    if built or not (ns.maps and ns.maps[ns.ROOT_MAP_ID]) or #Labels:Items() == 0 then return end
    built = true
    local faction
    local ok, f = pcall(UnitFactionGroup, "player")
    if ok and Str(f) then faction = (f == "Alliance") and 1 or (f == "Horde") and 2 or nil end
    for _, row in ipairs(P.portals) do
        local e = ns.maps[row.z]
        if e then
            local ways = {}
            for _, w in ipairs(row.l) do
                local d = ns.maps[w.tz]
                if d and (w.f == 0 or not faction or w.f == faction) then ways[#ways + 1] = w end
            end
            if #ways > 0 then
                table.sort(ways, function(a, b) return a.n < b.n end)
                local big = #ways >= HUB_BIG
                local size = big and ICON_BIG or ICON
                local kind = ways[1].k
                for _, w in ipairs(ways) do if w.k ~= kind then kind = "p" end end
                local x, y = e.x0 + row.x * (e.x1 - e.x0), e.y0 + row.y * (e.y1 - e.y0)
                local name = #ways > 1 and (#ways .. " ways from here") or ways[1].n
                local it = Labels:Add(x, y, name, "dungeon", e)
                if it then
                    it.style, it.pic = STYLE.portal, { file = IconFile(kind), w = size, h = size }
                    it.iconOnly, it.always, it.ways = true, true, ways
                    it.worldOn = big and WORLD_BIG or ns.RetailCells.BAND_WORLD
                    hubs[#hubs + 1] = it
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- The arcs and the list: their frame over the map, every texture of a pool
---------------------------------------------------------------------------
local function Layer()
    if layer then return layer end
    local parent = Labels:Layer()
    if not parent then return nil end
    layer = CreateFrame("Frame", nil, parent)
    layer:SetAllPoints(parent)
    layer:SetFrameLevel(parent:GetFrameLevel() + 20)
    if layer.SetClipsChildren then layer:SetClipsChildren(true) end
    layer:EnableMouse(false)
    layer:Hide()
    endText = layer:CreateFontString(nil, "OVERLAY")
    endText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    endText:SetTextColor(HOT[1], HOT[2], HOT[3])
    endText:Hide()
    return layer
end

local function LineAt(i)
    local ln = lines[i]
    if not ln then
        ln = layer:CreateLine(nil, "ARTWORK")
        lines[i] = ln
    end
    return ln
end

local function SparkAt(i)
    local s = sparks[i]
    if not s then
        s = layer:CreateTexture(nil, "OVERLAY")

        s:SetTexture("Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\spark.tga")
        s:SetSize(10, 10)
        sparks[i] = s
    end
    return s
end

local function RowAt(i)
    local r = rows[i]
    if not r then
        r = {}
        r.bg = layer:CreateTexture(nil, "BACKGROUND")
        r.icon = layer:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(ROW_H - 4, ROW_H - 4)
        r.fs = layer:CreateFontString(nil, "OVERLAY")
        r.fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "")
        r.fs:SetJustifyH("LEFT")
        if r.fs.SetWordWrap then r.fs:SetWordWrap(false) end
        rows[i] = r
    end
    return r
end

local function Hide()
    for _, ln in ipairs(lines) do ln:Hide() end
    for _, s in ipairs(sparks) do s:Hide() end
    for _, r in ipairs(rows) do
        r.bg:Hide()
        r.icon:Hide()
        r.fs:Hide()
    end
    if endText then endText:Hide() end
    if layer then layer:Hide() end
end

-- World point -> the view's px
local function ToScreen(x, y)
    local core = ns.Core
    local cam, v = core.Cam()
    if not (cam and v) then return nil end
    local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)
    return v.W / 2 + (x - cam.x) * ppx, v.H / 2 + (y - cam.y) * ppy, v.W, v.H
end

-- The end of way w, world point
local function WayEnd(w)
    local d = ns.maps[w.tz]
    if not d then return nil end
    return d.x0 + w.tx * (d.x1 - d.x0), d.y0 + w.ty * (d.y1 - d.y0), d
end

-- (the point at t on the arc: a parabola over the chord, its height BULGE of its length up to BULGE_MAX, always on the upper side)
local function Curve(x0, y0, x1, y1)
    local dx, dy = x1 - x0, y1 - y0
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return nil end
    local h = math.min(len * BULGE, BULGE_MAX)
    local nx, ny = dy / len, -dx / len
    if ny > 0 then nx, ny = -nx, -ny end -- (the bulge upward on the screen)
    local cx, cy = (x0 + x1) / 2 + nx * h * 2, (y0 + y1) / 2 + ny * h * 2
    return function(t)
        local a, b, c = (1 - t) * (1 - t), 2 * t * (1 - t), t * t
        return a * x0 + b * cx + c * x1, a * y0 + b * cy + c * y1
    end
end

local nLine, nSpark
local function DrawArc(x0, y0, x1, y1, W, H, hot, now)
    local f = Curve(x0, y0, x1, y1)
    if not f then return end
    local col = hot and HOT or DIM
    local px, py = f(0)
    local inside = function(x, y) return x >= -40 and x <= W + 40 and y >= -40 and y <= H + 40 end
    for i = 1, SEGS do
        local qx, qy = f(i / SEGS)
        if inside(px, py) or inside(qx, qy) then
            nLine = nLine + 1
            local ln = LineAt(nLine)
            ln:SetColorTexture(col[1], col[2], col[3], col[4])
            ln:SetThickness(hot and THICK_HOT or THICK)
            ln:SetStartPoint("TOPLEFT", layer, px, -py)
            ln:SetEndPoint("TOPLEFT", layer, qx, -qy)
            ln:Show()
        end
        px, py = qx, qy
    end
    if hot then
        for i = 1, SPARKS do
            local t = (now * SPARK_SPEED + (i - 1) / SPARKS) % 1
            local sx, sy = f(t)
            if sx >= 0 and sx <= W and sy >= 0 and sy <= H then
                nSpark = nSpark + 1
                local s = SparkAt(nSpark)
                s:ClearAllPoints()
                s:SetPoint("CENTER", layer, "TOPLEFT", sx, -sy)
                s:Show()
            end
        end
    end
end

-- (where the arc to (x1, y1) off the view leaves it: for its end's name)
local function Leaves(x0, y0, x1, y1, W, H)
    local f = Curve(x0, y0, x1, y1)
    if not f then return nil end
    local lx, ly
    for i = 0, SEGS do
        local x, y = f(i / SEGS)
        if x >= 8 and x <= W - 8 and y >= 8 and y <= H - 8 then lx, ly = x, y elseif lx then break end
    end
    return lx, ly
end

-- The list of hub it: its rect in the view's px, its rows beside the marker, turned to stay in the view
local function ListRect(it, W, H)
    local n = #it.ways + 1 -- (and what a click does)
    local w, h = ROW_W, n * ROW_H + 2 * ROW_PAD
    local half = it.pic.w / 2 + 6
    local x = it.sx + half
    if x + w > W then x = it.sx - half - w end
    local y = it.sy - h / 2
    if y < 2 then y = 2 elseif y + h > H - 2 then y = math.max(2, H - 2 - h) end
    return x, y, w, h
end

-- (the way of the row at (cx, cy); on: on the list, or between it and its marker - the cursor on its way there)
local function RowHit(it, cx, cy, W, H)
    local x, y, w, h = ListRect(it, W, H)
    if cx >= x and cx <= x + w and cy >= y and cy <= y + h then
        return it.ways[math.floor((cy - y - ROW_PAD) / ROW_H) + 1], true
    end
    local half = it.pic.w / 2 + HIT_PAD
    local x0, x1 = math.min(x, it.sx - half), math.max(x + w, it.sx + half)
    local y0, y1 = math.min(y, it.sy - half), math.max(y + h, it.sy + half)
    return nil, cx >= x0 and cx <= x1 and cy >= y0 and cy <= y1
end

local function DrawList(it, W, H, on)
    local x, y, w = ListRect(it, W, H)
    for i, way in ipairs(it.ways) do
        local r = RowAt(i)
        local ry = y + ROW_PAD + (i - 1) * ROW_H
        r.bg:ClearAllPoints()
        r.bg:SetPoint("TOPLEFT", layer, "TOPLEFT", x, -ry)
        r.bg:SetSize(w, ROW_H)
        if way == on then r.bg:SetColorTexture(0.30, 0.22, 0.05, 0.96) else r.bg:SetColorTexture(0.04, 0.035, 0.03, 0.92) end
        r.bg:Show()
        r.icon:SetTexture(IconFile(way.k))
        r.icon:ClearAllPoints()
        r.icon:SetPoint("LEFT", r.bg, "LEFT", 3, 0)
        r.icon:Show()
        r.fs:SetText(way.n)
        r.fs:ClearAllPoints()
        r.fs:SetPoint("LEFT", r.bg, "LEFT", ROW_H + 2, 0)
        r.fs:SetWidth(w - ROW_H - 6)
        if way == on then r.fs:SetTextColor(1, 1, 1) else r.fs:SetTextColor(1, 0.82, 0) end
        r.fs:Show()
    end
    -- (what a click does)
    local n = #it.ways + 1
    local r = RowAt(n)
    r.bg:ClearAllPoints()
    r.bg:SetPoint("TOPLEFT", layer, "TOPLEFT", x, -(y + ROW_PAD + (n - 1) * ROW_H))
    r.bg:SetSize(w, ROW_H)
    r.bg:SetColorTexture(0.04, 0.035, 0.03, 0.92)
    r.bg:Show()
    r.icon:Hide()
    r.fs:SetText("Click a way: fly there")
    r.fs:SetTextColor(0.75, 0.75, 0.75)
    r.fs:ClearAllPoints()
    r.fs:SetPoint("LEFT", r.bg, "LEFT", 6, 0)
    r.fs:SetWidth(w - 10)
    r.fs:Show()
end

-- This tick's hover drawn: hub it, way on under the cursor
local function Draw(it, on)
    if not Layer() then return end
    for _, ln in ipairs(lines) do ln:Hide() end
    for _, s in ipairs(sparks) do s:Hide() end
    for i = #it.ways + 2, #rows do
        rows[i].bg:Hide()
        rows[i].icon:Hide()
        rows[i].fs:Hide()
    end
    layer:Show()
    nLine, nSpark = 0, 0
    local now = GetTime()
    local x0, y0, W, H = ToScreen(it.x, it.y)
    if not x0 then return end
    local one = #it.ways == 1 and it.ways[1] or on
    for _, way in ipairs(it.ways) do
        local ex, ey = WayEnd(way)
        if ex and way ~= one then
            local x1, y1 = ToScreen(ex, ey)
            DrawArc(x0, y0, x1, y1, W, H, false, now)
        end
    end
    endText:Hide()
    if one then
        local ex, ey = WayEnd(one)
        if ex then
            local x1, y1 = ToScreen(ex, ey)
            DrawArc(x0, y0, x1, y1, W, H, true, now)
            -- (its end's name where the arc leaves the view; at its end in the view)
            local tx, ty = x1, y1
            if x1 < 0 or x1 > W or y1 < 0 or y1 > H then tx, ty = Leaves(x0, y0, x1, y1, W, H) end
            if tx then
                local d = ns.maps[one.tz]
                endText:SetText(tostring(d and d.name or one.n))
                endText:ClearAllPoints()
                endText:SetPoint(tx > W / 2 and "BOTTOMRIGHT" or "BOTTOMLEFT", layer, "TOPLEFT", tx, -ty + 6)
                endText:Show()
            end
        end
    end
    DrawList(it, W, H, on or one)
end

---------------------------------------------------------------------------
-- The hover, the click
---------------------------------------------------------------------------
local function MarkerAt(x, y)
    if not (x and y) then return nil end
    local best, bd
    for _, it in ipairs(hubs) do
        if it.shown and it.sx and (it.alpha or 0) >= 0.5 then
            local half = it.pic.w / 2 + HIT_PAD
            if math.abs(x - it.sx) <= half and math.abs(y - it.sy) <= half then
                local d = (x - it.sx) ^ 2 + (y - it.sy) ^ 2
                if not best or d < bd then best, bd = it, d end
            end
        end
    end
    return best
end

-- The hub and the way at container point (x, y): the list of the hub the hover is on first - it lies over the map
function PT:HitTest(x, y)
    if not (x and y) then return nil end
    local _, v = ns.Core.Cam()
    if hover and v then
        local way, inList = RowHit(hover, x, y, v.W, v.H)
        if way then return hover, way end
        if inList then
            -- (on the marker itself, or between it and its list: a marker of one way is that way)
            if #hover.ways == 1 and MarkerAt(x, y) == hover then return hover, hover.ways[1] end
            return hover, nil
        end
    end
    local it = MarkerAt(x, y)
    if it and #it.ways == 1 then return it, it.ways[1] end
    return it, nil
end

-- The flight: as a click on a party member's bubble (Core.lua FlyToView); the view a little wider than its end's map
local function FlyTo(way)
    local core = ns.Core
    if not (core and core.FlyToView and core.Cam) then return false end
    local _, v = core.Cam()
    local ex, ey, d = WayEnd(way)
    if not (v and ex and d) then return false end
    return core.FlyToView(ex, ey, ns.WidthForZoom(v, d, 1.6))
end
PT.FlyTo = FlyTo

function PT:OnCanvasClick(button)
    if button ~= "LeftButton" or not ns.Core then return false end
    if ns.db and ns.db.portals == false then return false end
    if not (ns.Core.Settled and ns.Core.Settled()) then return false end
    local x, y = ns.Core.CursorPos()
    local it, way = PT:HitTest(x, y)
    if not it then return false end
    if way then
        FlyTo(way)
        hover, rowOn = nil, nil
        Hide()
    end
    return true -- (a hub's marker, or its list: the map's own click does nothing here)
end

local function Hover()
    local core = ns.Core
    local it, way
    if core and core.Settled and core.Settled() and ns.db and ns.db.portals ~= false and WorldMapFrame and WorldMapFrame:IsShown()
        and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer:IsMouseOver() then
        it, way = PT:HitTest(core.CursorPos())
    end
    if it ~= hover then
        if hover then Labels:SetHot(nil) end
        hover = it
        if it then Labels:SetHot(it) end
    end
    rowOn = way
    if it then Draw(it, way) elseif layer and layer:IsShown() then Hide() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local watch = CreateFrame("Frame")
watch:Hide()
local acc = 0
watch:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc < 0.05 then return end
    acc = 0
    Hover()
end)
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    hooksecurefunc(Labels, "Draw", function() if not built then Build() end end)
    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", function() watch:Show() end)
        WorldMapFrame:HookScript("OnHide", function()
            watch:Hide()
            hover, rowOn = nil, nil
            Hide()
        end)
        if WorldMapFrame:IsShown() then watch:Show() end
    end
end)

-- (tests) the hubs, the frames of the hover
PT.T = { hubs = hubs, lines = lines, sparks = sparks, rows = rows, ListRect = ListRect }
function PT:Hovered() return hover, rowOn end
function PT:EndText() return endText end
