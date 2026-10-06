local _, ns = ...

--[[
"Where am I" inside instances (2.9.0 candidate, wf12/synth prototype).

Inside an instance the game gives addons no position: UnitPosition("player") returns nil, nil, nil, <instance id>
(in game, The Hall of Thanes, 1.60.1.70058). So the dungeon view cannot draw the player's arrow there. What the game
still tells an addon:
  * the SUB-ZONE: GetSubZoneText() (else GetMinimapZoneText()) - the name of the room / area the player is in, where the
    game names it. SubZoneRegions.lua holds, per instance / floor / enUS name, the region of the picture that name covers
    (generated from the client's own WMOAreaTable, AreaTable and map geometry);
  * the FACING: GetPlayerFacing() - if the game answers inside instances (in-game test; nil = no needle).

What this module shows, only on a floor page of the instance the player is in, and only while the game gives no
position (where it does - the open world, the Deeprun Tram - Dungeon.lua's own arrow is drawn, as 2.8.0):
  * the named room on the picture: a warm gold fill with an outline, drawn on the picture layer itself (it zooms, pans
    and cross-fades with the page), and the text "You are in <name>" on it (unscaled, on the icon frame);
  * a chip on the bar: a needle turned to the facing (the pages are north-up) and the room / level; its tooltip says why
    there is no arrow; when the room is on another level, a click shows that level.
Never a spot the game did not give: no dot and no arrow on the picture.

Grid: ns.SUBZONE_GRID = { 111, 74 } square cells of the 1002 x 668 picture; region strings as SubZoneRegions.lua says.
Outline: through the midpoints of the region's cell edges (wf13/review1): straight runs as thin textures, every corner
cut at 45 degrees and 1-cell staircases as straight diagonals, both as Line objects (Frame:CreateLine); pieces lengthened
by tan(22.5 deg) / 2 x their thickness, so the 135-degree joints close. Without CreateLine (or CHAMFER = false): the cell
boundary's axis-aligned runs, horizontal ones lengthened and vertical ones shortened by half the thickness (no overlap).
(A file of its own, like DungeonQuads.lua: Dungeon.lua's chunk stays far from Lua 5.1's 200-local limit.)
]]

local W = {}
ns.Where = W

local ART_W, ART_H = 1002, 668
local FILL = { 1, 0.84, 0.43, 0.22 }   -- the room
local LINE = { 1, 0.93, 0.63, 0.95 }   -- its outline
local GLOW = { 1, 0.75, 0.25, 0.25 }   -- a soft band under the outline
local LINE_PX, GLOW_PX = 2, 7          -- on screen (view units), whatever the zoom
local CHIP_W = 170                     -- the chip's width at least; it grows to fit a long name (ChipWidth)
local CHIP_MAX = 320                   -- ... up to this
local TITLE_ROOM = 300                 -- ... and never leaves the bar less than this left of it (button + title)
local NEEDLE = 18
local ARROW_ATLAS = "UI-WorldMapArrow"
local ARROW_FILE = "Interface\\WorldMap\\WorldMapArrow"
local FACING_EPS = 0.005
local LABEL_PAD = 6
local CHAMFER = true                   -- (wf13/review1) outline corners cut at 45 degrees (Lines); false = cell steps
local CUT = 0.2071                     -- tan(22.5 deg) / 2: a piece's extension per unit of thickness at a 135-degree joint

local P = {
    api = nil,
    cache = {},      -- [region string] = decoded { lc, lr, rects (flat), segs (flat), pcs (flat) }
    en = nil,        -- [localized AreaTable name] = enUS key (non-enUS clients)
    state = "off",
}

---------------------------------------------------------------------------
-- Region strings (SubZoneRegions.lua)
---------------------------------------------------------------------------
local function Grid()
    local g = ns.SUBZONE_GRID
    return (g and g[1]) or 111, (g and g[2]) or 74
end

local function D91(b) return b - 35 - ((b > 92) and 1 or 0) end

-- The outline through the midpoints of the cell edges: the cell set's boundary loops (directed edges between lattice
-- points, the region on their right; at a pinch - two cells touching at a corner - the rightmost turn, so each 4-connected
-- part keeps its own loop), then the loop's edge midpoints where the path turns. Pieces { kind, x0, y0, x1, y1, ... } in
-- cell units: kind 1 horizontal, 2 vertical, 3 diagonal (45 degrees: the cells are square).
local function Chamfer(At, GW, GH)
    local W1 = GW + 1
    local nxt = {}
    local function Add(x0, y0, x1, y1)
        local k = y0 * W1 + x0
        local t = nxt[k]
        if not t then
            t = {}
            nxt[k] = t
        end
        t[#t + 1] = y1 * W1 + x1
    end
    for r = 0, GH do
        for c = 0, GW - 1 do
            local a, b = At(c, r - 1), At(c, r)
            if b and not a then Add(c, r, c + 1, r) elseif a and not b then Add(c + 1, r, c, r) end
        end
    end
    for c = 0, GW do
        for r = 0, GH - 1 do
            local a, b = At(c - 1, r), At(c, r)
            if a and not b then Add(c, r, c, r + 1) elseif b and not a then Add(c, r + 1, c, r) end
        end
    end
    local pcs = {}
    local ex, ey = {}, {}
    for k0 = 0, (GH + 1) * W1 - 1 do
        while nxt[k0] do
            -- one loop: its points' edges as unit vectors ex / ey (the edge that leaves point i)
            local px, py = {}, {}
            local k, dx, dy = k0, nil, nil
            local m = 0
            repeat
                local list = nxt[k]
                local pick = 1
                if #list > 1 and dx then
                    local best
                    for i = 1, #list do
                        local n = list[i]
                        local ndx, ndy = n % W1 - k % W1, math.floor(n / W1) - math.floor(k / W1)
                        local turn = (ndx == -dy and ndy == dx) and 0 or ((ndx == dx and ndy == dy) and 1 or 2)
                        if not best or turn < best then best, pick = turn, i end
                    end
                end
                local n = table.remove(list, pick)
                if #list == 0 then nxt[k] = nil end
                m = m + 1
                px[m], py[m] = k % W1, math.floor(k / W1)
                dx, dy = n % W1 - px[m], math.floor(n / W1) - py[m]
                ex[m], ey[m] = dx, dy
                k = n
            until k == k0 or not nxt[k]
            -- the midpoints where the path turns: midpoint i (of edge i) is a vertex unless edges i-1, i, i+1 run on
            -- one line through it ((e[i-1] + e[i]) parallel to (e[i] + e[i+1]))
            local vx, vy, nv = {}, {}, 0
            for i = 1, m do
                local h, j = (i == 1) and m or i - 1, (i == m) and 1 or i + 1
                local ax, ay = ex[h] + ex[i], ey[h] + ey[i]
                local bx, by = ex[i] + ex[j], ey[i] + ey[j]
                if ax * by - ay * bx ~= 0 or ax * bx + ay * by <= 0 then
                    nv = nv + 1
                    vx[nv], vy[nv] = px[i] + ex[i] / 2, py[i] + ey[i] / 2
                end
            end
            for i = 1, nv do
                local j = (i == nv) and 1 or i + 1
                local x0, y0, x1, y1 = vx[i], vy[i], vx[j], vy[j]
                local kind = (y0 == y1) and 1 or ((x0 == x1) and 2 or 3)
                local q = #pcs
                pcs[q + 1], pcs[q + 2], pcs[q + 3], pcs[q + 4], pcs[q + 5] = kind, x0, y0, x1, y1
            end
        end
    end
    return pcs
end

-- region string -> label cell, rectangles { c0, r0, c1, r1, ... } (inclusive), outline runs
-- { kind (1 = horizontal, 2 = vertical), a0, fixed, a1, ... } in cell units
local function Decode(s)
    local d = P.cache[s]
    if d then return d end
    local GW, GH = Grid()
    local function Cell(i)
        local a, b = s:byte(i, i + 1)
        local v = D91(a) * 91 + D91(b)
        return v % GW, math.floor(v / GW)
    end
    local lc, lr = Cell(1)
    local rects = {}
    for i = 3, #s - 1, 4 do
        local c0, r0 = Cell(i)
        local c1, r1 = Cell(i + 2)
        rects[#rects + 1], rects[#rects + 2], rects[#rects + 3], rects[#rects + 4] = c0, r0, c1, r1
    end
    -- the cells, then their boundary as maximal runs
    local on = {}
    for i = 1, #rects, 4 do
        for r = rects[i + 1], rects[i + 3] do
            for c = rects[i], rects[i + 2] do on[r * GW + c] = true end
        end
    end
    local function At(c, r) return c >= 0 and c < GW and r >= 0 and r < GH and on[r * GW + c] == true end
    local segs = {}
    if #rects > 0 then
        for r = 0, GH do            -- horizontal edges at y = r (between rows r - 1 and r)
            local c = 0
            while c < GW do
                local inside = At(c, r)
                if At(c, r - 1) ~= inside then
                    local c0 = c
                    while c < GW and At(c, r - 1) ~= At(c, r) and At(c, r) == inside do c = c + 1 end
                    segs[#segs + 1], segs[#segs + 2], segs[#segs + 3], segs[#segs + 4] = 1, c0, r, c
                else
                    c = c + 1
                end
            end
        end
        for c = 0, GW do            -- vertical edges at x = c
            local r = 0
            while r < GH do
                local inside = At(c, r)
                if At(c - 1, r) ~= inside then
                    local r0 = r
                    while r < GH and At(c - 1, r) ~= At(c, r) and At(c, r) == inside do r = r + 1 end
                    segs[#segs + 1], segs[#segs + 2], segs[#segs + 3], segs[#segs + 4] = 2, r0, c, r
                else
                    r = r + 1
                end
            end
        end
    end
    d = { lc = lc, lr = lr, rects = rects, segs = segs, pcs = CHAMFER and #rects > 0 and Chamfer(At, GW, GH) or nil }
    P.cache[s] = d
    return d
end

---------------------------------------------------------------------------
-- The game's sub-zone -> region key
---------------------------------------------------------------------------
local function Trim(s)
    if type(s) ~= "string" or (issecretvalue and issecretvalue(s)) then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Text(fn)
    if not fn then return "" end
    local ok, s = pcall(fn)
    if not ok then return "" end
    return Trim(s)
end

-- The room name the game reports (localized), or nil when it names only the zone / the instance.
local function SubZone(id)
    local sub = Text(GetSubZoneText)
    if sub == "" then sub = Text(GetMinimapZoneText) end
    if sub == "" then return nil end
    if sub == Text(GetZoneText) or sub == Text(GetRealZoneText) then return nil end
    local api = P.api
    if api.dungeonName and sub == api.dungeonName(id) then return nil end
    -- (the instance's own map name: e.g. every Stockade group reports "Stormwind Stockade", while its zone is "The Stockade")
    if GetInstanceInfo then
        local ok, name = pcall(GetInstanceInfo)
        if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) and sub == Trim(name) then return nil end
    end
    return sub
end

-- The data's key for a game string: enUS as is; elsewhere the AreaTable names through C_Map.GetAreaInfo (WMOAreaTable
-- names exist in enUS only - there the chip names the room, without a lit area).
local function Key(sub)
    if not (GetLocale and GetLocale() ~= "enUS") then return sub end
    if not P.en then
        P.en = {}
        if C_Map and C_Map.GetAreaInfo then
            for enName, a in pairs(ns.SUBZONE_AREA or {}) do
                local ok, loc = pcall(C_Map.GetAreaInfo, a)
                if ok and type(loc) == "string" and loc ~= "" then P.en[loc] = enName end
            end
        end
    end
    return P.en[sub] or sub
end

---------------------------------------------------------------------------
-- The lit room, on a picture layer (Dungeon.lua NewLayer: 1002 x 668, scaled by the view)
---------------------------------------------------------------------------
-- The frame of layer L that holds the page's art: the angled blocks' holder (DungeonQuads.lua), else the layer itself.
local function Holder(L, page)
    if page and page.f and page.f.rq and L.hold then return L.hold end
    return L
end

local function Pool(h, name, i, sub, color)
    local list = h[name]
    if not list then
        list = {}
        h[name] = list
    end
    local t = list[i]
    if not t then
        t = h:CreateTexture(nil, "OVERLAY", nil, sub)
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
        if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
        t:SetColorTexture(color[1], color[2], color[3], color[4])
        list[i] = t
    end
    return t
end

local function HideFrom(list, from)
    if not list then return end
    for i = from, #list do
        if list[i]:IsShown() then list[i]:Hide() end
    end
end

-- (a pooled Line on holder h: a thick segment between two points of h; nil where the client has no CreateLine)
local function PoolLine(h, name, i, sub, color)
    if not h.CreateLine then return nil end
    local list = h[name]
    if not list then
        list = {}
        h[name] = list
    end
    local ln = list[i]
    if not ln then
        ln = h:CreateLine(nil, "OVERLAY", nil, sub)
        ln:SetColorTexture(color[1], color[2], color[3], color[4])
        list[i] = ln
    end
    return ln
end

local function ClearHolder(h)
    if not h then return end
    HideFrom(h.hlFill, 1)
    HideFrom(h.hlLine, 1)
    HideFrom(h.hlGlow, 1)
    HideFrom(h.hlLineD, 1)
    HideFrom(h.hlGlowD, 1)
end

local function ClearLayer(L)
    if not L then return end
    -- (wf13/review2: only the holder that shows something - Light and Thicken show pieces on L.hlHolder alone, and
    -- Off() runs at every poll outside instances: no walk over the pools when nothing is lit)
    if L.hlHolder then ClearHolder(L.hlHolder) end
    L.hlPage, L.hlStr, L.hlS, L.hlHolder, L.hlData = nil, nil, nil, nil, nil
end

-- the outline runs at thickness px on screen (layer scale L.s)
local function Thicken(L)
    local h, d = L.hlHolder, L.hlData
    if not (h and d) then return end
    local s = L.s or 1
    if s <= 0 then s = 1 end
    local GW, GH = Grid()
    local cw, ch = ART_W / GW, ART_H / GH
    if d.pcs and h.CreateLine then
        -- the chamfered outline: straight pieces as textures, 45-degree pieces as Lines, each lengthened by CUT x t
        local pcs = d.pcs
        for k = 1, 2 do
            local tname, lname = (k == 1) and "hlGlow" or "hlLine", (k == 1) and "hlGlowD" or "hlLineD"
            local color = (k == 1) and GLOW or LINE
            local sub = (k == 1) and 1 or 2
            local t = ((k == 1) and GLOW_PX or LINE_PX) / s
            local ht, e = t / 2, CUT * t
            local nt, nl = 0, 0
            for i = 1, #pcs, 5 do
                local kind = pcs[i]
                local x0, y0, x1, y1 = pcs[i + 1] * cw, pcs[i + 2] * ch, pcs[i + 3] * cw, pcs[i + 4] * ch
                if kind == 3 then
                    nl = nl + 1
                    local ln = PoolLine(h, lname, nl, sub, color)
                    local len = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0))
                    local ux, uy = (x1 - x0) / len * e, (y1 - y0) / len * e
                    ln:SetStartPoint("TOPLEFT", h, x0 - ux, -(y0 - uy))
                    ln:SetEndPoint("TOPLEFT", h, x1 + ux, -(y1 + uy))
                    ln:SetThickness(t)
                    if not ln:IsShown() then ln:Show() end
                else
                    nt = nt + 1
                    local tex = Pool(h, tname, nt, sub, color)
                    local xa, xb = math.min(x0, x1), math.max(x0, x1)
                    local ya, yb = math.min(y0, y1), math.max(y0, y1)
                    tex:ClearAllPoints()
                    if kind == 1 then
                        tex:SetPoint("TOPLEFT", h, "TOPLEFT", xa - e, -(ya - ht))
                        tex:SetSize(xb - xa + 2 * e, t)
                    else
                        tex:SetPoint("TOPLEFT", h, "TOPLEFT", xa - ht, -(ya - e))
                        tex:SetSize(t, yb - ya + 2 * e)
                    end
                    if not tex:IsShown() then tex:Show() end
                end
            end
            HideFrom(h[tname], nt + 1)
            HideFrom(h[lname], nl + 1)
        end
        L.hlS = s
        return
    end
    local segs = d.segs
    local n = 0
    for k = 1, 2 do
        local name = (k == 1) and "hlGlow" or "hlLine"
        local color = (k == 1) and GLOW or LINE
        local t = ((k == 1) and GLOW_PX or LINE_PX) / s
        local ht = t / 2
        n = 0
        for i = 1, #segs, 4 do
            local kind, a0, fixed, a1 = segs[i], segs[i + 1], segs[i + 2], segs[i + 3]
            local x, y, w, hh
            if kind == 1 then
                x, y, w, hh = a0 * cw - ht, fixed * ch - ht, (a1 - a0) * cw + t, t
            else
                x, y, w, hh = fixed * cw - ht, a0 * ch + ht, t, (a1 - a0) * ch - t
            end
            if w > 0 and hh > 0 then
                n = n + 1
                local tex = Pool(h, name, n, (k == 1) and 1 or 2, color)
                tex:ClearAllPoints()
                tex:SetPoint("TOPLEFT", h, "TOPLEFT", x, -y)
                tex:SetSize(w, hh)
                if not tex:IsShown() then tex:Show() end
            end
        end
        HideFrom(h[name], n + 1)
    end
    -- (wf13/review2: and the 45-degree Lines of a chamfered room lit before on this holder - a label-only name has no
    -- chamfer pieces and comes here)
    HideFrom(h.hlLineD, 1)
    HideFrom(h.hlGlowD, 1)
    L.hlS = s
end

-- Light region string s of page on layer L (nothing to do when it already shows it).
local function Light(L, page, s)
    if L.hlPage == page and L.hlStr == s then return end
    local h = Holder(L, page)
    if L.hlHolder and L.hlHolder ~= h then ClearHolder(L.hlHolder) end
    local d = Decode(s)
    local GW, GH = Grid()
    local cw, ch = ART_W / GW, ART_H / GH
    local rects = d.rects
    local n = 0
    for i = 1, #rects, 4 do
        n = n + 1
        local t = Pool(h, "hlFill", n, 0, FILL)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", h, "TOPLEFT", rects[i] * cw, -rects[i + 1] * ch)
        t:SetSize((rects[i + 2] - rects[i] + 1) * cw, (rects[i + 3] - rects[i + 1] + 1) * ch)
        if not t:IsShown() then t:Show() end
    end
    HideFrom(h.hlFill, n + 1)
    L.hlPage, L.hlStr, L.hlHolder, L.hlData = page, s, h, d
    L.hlS = nil
    Thicken(L)
end

---------------------------------------------------------------------------
-- The label on the picture and the chip on the bar
---------------------------------------------------------------------------
local function BuildLabel(parent)
    -- (wf13 judge) on the icon frame itself, OVERLAY sub-level 7 (SimpleRegionAPIDocumentation.lua SetDrawLayer): a child
    -- frame of its own got the default level, the icon frame's + 1 = the level of the group markers' frames
    -- (DungeonMarkers.lua: the engine arrow and the party dots on City of Dalaran / Half-Pint Tavern) - an undefined draw
    -- order with them. Within one frame the order is fixed: above the level-link pins (OVERLAY 3 / 4), below every marker.
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if fs.SetDrawLayer then fs:SetDrawLayer("OVERLAY", 7) end
    local path, size = fs:GetFont()
    if type(path) == "string" and type(size) == "number" then fs:SetFont(path, size + 1, "OUTLINE") end
    if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)
    fs:Hide()
    P.label = fs
end

local function ChipTip()
    local api, c = P.api, P.chip
    local lines = { { c.title or "", 1, 0.82, 0, 12 } }
    local grey = function(s) lines[#lines + 1] = { s, 0.8, 0.8, 0.8, 11 } end
    grey("Inside instances the game gives addons no position.")
    if P.state == "room" then
        grey("The lit area is the room the game names:")
        grey("you are somewhere in it, not at its label.")
    elseif P.state == "none" then
        grey("The game names only some rooms here; this one has")
        grey("no name, so the map cannot light it.")
    elseif P.state == "nodata" then
        grey("This map has no outline for that name.")
    end
    if c.needle:IsShown() then grey("The needle is the way you face (north is up).") end
    if c.target then lines[#lines + 1] = { "Click: show that level", 0.5, 1, 0.5, 11 } end
    api.tip(lines)
end

local function BuildChip(bar)
    local c = CreateFrame("Button", nil, bar)
    c:SetSize(CHIP_W, 22)
    c:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
    local needle = c:CreateTexture(nil, "OVERLAY")
    needle:SetSize(NEEDLE, NEEDLE)
    needle:SetPoint("LEFT", c, "LEFT", 2, 0)
    local info
    if C_Texture and C_Texture.GetAtlasInfo then
        local ok, i = pcall(C_Texture.GetAtlasInfo, ARROW_ATLAS)
        info = ok and i or nil
    end
    if info and needle.SetAtlas then needle:SetAtlas(ARROW_ATLAS, false) else needle:SetTexture(ARROW_FILE) end
    needle:Hide()
    local label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", c, "LEFT", 4 + NEEDLE, 0)
    label:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    c.needle, c.label = needle, label
    c:SetScript("OnEnter", function() if P.api.D.active then ChipTip() end end)
    c:SetScript("OnLeave", function() P.api.untip() end)
    c:SetScript("OnClick", function(self)
        if self.target and self.dun then P.api.show(self.dun, self.target) end
    end)
    c:Hide()
    P.chip = c
end

-- The chip's width for its text: the text's full width (GetUnboundedStringWidth, SimpleFontStringAPIDocumentation.lua;
-- GetStringWidth where a client lacks it) + the needle, between CHIP_W and what the bar can spare right of TITLE_ROOM.
local function ChipWidth(c, right)
    local fs = c.label
    local fn = fs.GetUnboundedStringWidth or fs.GetStringWidth
    local ok, tw = pcall(fn, fs)
    if not ok or type(tw) ~= "number" or (issecretvalue and issecretvalue(tw)) or tw ~= tw then tw = 0 end
    local bw = P.api.D.bar and P.api.D.bar:GetWidth() or 0
    -- (3.0.0 review) the bar's boss button (Dungeon.lua, 46 px + 6) sits left of the title: where the bar is short of room
    -- (the map's normal size) the chip's spare minimum width gives it up, so the dungeon's name keeps room (none changes
    -- where the bar has room, nor without the button)
    local bb = P.api.D.bossBtn
    local give = (bb and bb:IsShown()) and 52 or 0
    local spare = bw - right - TITLE_ROOM - give
    local least = math.max(CHIP_W - give, math.min(CHIP_W, spare - give))
    local most = math.max(least, math.min(CHIP_MAX, spare))
    return math.min(math.max(tw + 4 + NEEDLE + 8, least), most)
end

-- Chip: shown or not, its text, its click target; the bar's title makes room (Dungeon.lua RefreshUp).
local function SetChip(show, text, title, dun, target, grey)
    local c, D = P.chip, P.api.D
    c.dun, c.target, c.title = dun, target, title
    if show then
        if c.text ~= text then
            c.label:SetText(text)
            c.text = text
        end
        if grey then c.label:SetTextColor(0.7, 0.7, 0.7) else c.label:SetTextColor(1, 1, 1) end
    end
    -- (the level picker: Blizzard's dropdown, 200 px at -8; else 2.8.0's prev / next fallback, 24 + 150 + 24 px and two
    -- 6 px gaps at -8, its left edge 218 px from the bar's end - wf13/review2)
    local pick = (D.dd and D.dd:IsShown() and 214) or (D.next and D.next:IsShown() and 224) or nil
    local dd = pick ~= nil
    local right = show and (pick or 8) or nil
    if c.right ~= right then
        c.right = right
        if right then
            c:ClearAllPoints()
            c:SetPoint("RIGHT", D.bar, "RIGHT", -right, 0)
        end
    end
    local cw = show and ChipWidth(c, right) or nil
    if cw and c.w ~= cw then
        c.w = cw
        c:SetWidth(cw)
    end
    -- (the title's right edge: 14 px left of the chip; without a level picker 2.8.0's 222 px as long as the chip fits)
    local tr = cw and (dd and (right + cw + 14) or ((right + cw + 14 > 222) and (right + cw + 14)) or nil) or nil
    if c:IsShown() ~= show then c:SetShown(show) end
    if D.titleRight ~= tr then
        D.titleRight = tr
        P.api.refreshTitle()
    end
end

---------------------------------------------------------------------------
-- API for Dungeon.lua
---------------------------------------------------------------------------
-- api: D (Dungeon.lua's state), page(), inside(), pos(), facing(), detect(id), floorName(f), dungeonName(id),
-- show(dun, floor), tip(lines), untip(), refreshTitle(), viewXY(u, v), inArea(px, py)
function W:Setup(api)
    if P.api then return end
    P.api = api
    BuildLabel(api.D.iconFrame)
    BuildChip(api.D.bar)
end

-- A picture layer got a page (Dungeon.lua LoadLayer): whatever it lit for another page goes.
function W:OnLoad(L, page)
    if L and L.hlPage and L.hlPage ~= page then ClearLayer(L) end
end

local function Off()
    local D = P.api.D
    for _, L in ipairs(D.layers or {}) do ClearLayer(L) end
    if P.label:IsShown() then P.label:Hide() end
    P.lit, P.state = nil, "off"
    SetChip(false)
end

-- Every poll (Dungeon.lua POLL): what the game says now -> the lit room, the label, the chip.
function W:Poll()
    local api = P.api
    if not api then return end
    local D = api.D
    -- (wf13/review2: the view fades out - Dungeon:Exit - the light, label and chip fade with the art as they are)
    if not D.active and D.fade then return end
    local page = api.page()
    local id = page and page.kind == "floor" and D.active and api.inside()
    if not (id and id == page.dun) or D.arrowOn or api.pos() then return Off() end
    local dm = ns.DUNGEON_MAPS[id]
    local regs = ns.SUBZONE_REGIONS and ns.SUBZONE_REGIONS[id]
    local sub = SubZone(id)
    local key = sub and Key(sub)
    local s, rf
    if key and regs then
        if regs[page.floor] and regs[page.floor][key] then
            s, rf = regs[page.floor][key], page.floor
        else
            local f = api.detect(id)
            if f and regs[f] and regs[f][key] then
                rf = f
            else
                for i = 1, #regs do
                    if regs[i] and regs[i][key] then rf = i break end
                end
            end
        end
    end
    if not rf and sub then
        -- (no outline for the name: the level the game's name points to, if any)
        local f = api.detect(id)
        if f and f ~= page.floor then rf = f end
    end
    -- (other layers: whatever they lit is from an older page - it fades out with them)
    if s then
        Light(D.front, page, s)
        P.state = "room"
        local d = Decode(s)
        -- (wf13/review2: placed again only when the room, its page or its text changed - not at every poll)
        if P.lit ~= d or d.page ~= page or P.labelText ~= sub then P.lblDirty = true end
        P.lit = d
        d.page = page
        SetChip(true, sub, "You are in " .. sub)
        if P.labelText ~= sub then
            P.label:SetText("You are in " .. sub)
            P.labelText = sub
        end
    else
        ClearLayer(D.front)
        P.lit = nil
        if P.label:IsShown() then P.label:Hide() end
        if rf and rf ~= page.floor and dm and dm.f[rf] then
            P.state = "level"
            local fname = api.floorName(dm.f[rf])
            SetChip(true, "You: " .. fname, "You are in " .. sub .. " (" .. fname .. ")", id, rf)
        elseif sub then
            P.state = "nodata"
            SetChip(true, sub, "You are in " .. sub)
        else
            P.state = "none"
            SetChip(true, "Room not named", "Room not named here", nil, nil, true)
        end
    end
end

-- Every frame: the label follows the view (only when it moved), the outline keeps its thickness on screen, the needle
-- turns to the facing.
function W:Place(moved)
    local api = P.api
    if not api then return end
    local D = api.D
    local lit = P.lit
    if lit and lit.page ~= api.page() then
        if P.label:IsShown() then P.label:Hide() end
    elseif lit then
        local L = D.front
        -- (outline thickness follows the zoom: at rest exactly, while zooming in 15 % steps - at most 2 x 404 textures each time)
        if L.hlHolder and L.hlS ~= L.s and L.s and (D.view.z == D.targetZ or math.abs(L.s / (L.hlS or L.s) - 1) > 0.15) then Thicken(L) end
        if moved or P.lblDirty then
            P.lblDirty = false
            local GW, GH = Grid()
            local px, py = api.viewXY((lit.lc + 0.5) / GW, (lit.lr + 0.5) / GH)
            local fs = P.label
            if api.inArea(px, py) then
                local half = (fs:GetStringWidth() or 0) / 2 + LABEL_PAD
                local W_, H_ = D.W or 0, D.H or 0
                if W_ > 2 * half then px = math.min(math.max(px, half), W_ - half) end
                -- (and pushed down from the bar / up from the bottom edge: a cell on the picture's top row put half the text
                -- under the bar)
                local hh = (fs:GetStringHeight() or 12) / 2 + 2
                -- (2.11.0) not over a boss / entrance marker (DungeonBosses.lua): just under the marker it would cover
                if ns.Bosses and ns.Bosses.Clear then py = ns.Bosses:Clear(px, py, half, hh) end
                local top = (D.bar and D.bar:GetHeight() or 30) + hh
                if H_ > top + hh then py = math.min(math.max(py, top), H_ - hh) end
                fs:ClearAllPoints()
                fs:SetPoint("CENTER", D.dv, "TOPLEFT", px, -py)
                if not fs:IsShown() then fs:Show() end
            elseif fs:IsShown() then
                fs:Hide()
            end
        end
    end
    local c = P.chip
    if c and c:IsShown() then
        local f = c.needle.SetRotation and api.facing()
        if f then
            if not c.facing or math.abs(f - c.facing) > FACING_EPS then
                c.needle:SetRotation(f)
                c.facing = f
            end
            if not c.needle:IsShown() then c.needle:Show() end
        elseif c.needle:IsShown() then
            c.needle:Hide()
            c.facing = nil
        end
    end
end

function W:State() return P.state, P.lit ~= nil end

-- (2.11.0) DungeonBosses.lua: markers came, went or grew - place the label again (next W:Place).
function W:Relabel() P.lblDirty = true end

function W:DebugText()
    if not P.api then return "-" end
    local c = P.chip
    return ("%s%s"):format(P.state, (c and c:IsShown() and c.text) and (" '" .. c.text .. "'") or "")
end
