local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)

--[[
Level links on entrance (hub) maps (ns.DUNGEON_LEVEL_LINKS, DungeonPortals.lua):
a round "stairs" pin where the path drawn on a level leads to the hub's other
level (Blackrock Mountain: the chain at the central platform). Dungeon.lua owns
the view, the tooltip, the clicks and the bar's level button; this module only
keeps the pins of the page shown, draws them and hit-tests them (like
DungeonMarkers.lua for the group).

Art (all verified in the LOCAL Forever 1.60.1.70009 client, UiTextureAtlasMember
fdid 897532 / UiTextureAtlas 897470, file installed locally; siblings of the
housing-floor-arrow-* atlases that Blizzard_HouseEditor uses): housing-stair-arrow-{down,up}-default-2x
(members 34736 / 34738, 64x64, atlas 3552 = file 7361255) and -highlight-2x
(34737 / 34739) when hovered, on a dark disc WhiteCircle-RaidBlips (member
6220, atlas 867 = file 1523129). (Retail's map-link art - CaveUnderground-Up /
-Down, poi-door-* - is in file 1121272, which this client does NOT have
installed.) Without the atlases the pins stay hidden; the bar button remains.
]]

local Links = {}
ns.Links = Links

local SIZE = 28      -- px at fit (grows with the zoom like the portal icons: Dungeon.lua IconScale)
local DISC = 1.1     -- the dark disc behind the arrow, x SIZE
local HIT = 30       -- px square that takes the click / hover (at fit)
local GROW = 1.2     -- hovered
local ART = {
    down = { "housing-stair-arrow-down-default-2x", "housing-stair-arrow-down-highlight-2x" },
    up = { "housing-stair-arrow-up-default-2x", "housing-stair-arrow-up-highlight-2x" },
}
local DISC_ATLAS = "WhiteCircle-RaidBlips"
-- (the bar button: the 1x arrow inline in its text, CreateAtlasMarkup's format)
local MARKUP = { down = "|A:housing-stair-arrow-down-default:16:16|a ", up = "|A:housing-stair-arrow-up-default:16:16|a " }

local L = { pins = {}, n = 0, hot = nil, dirty = true, ok = nil }

local function HasAtlas(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end

-- Pins drawn? (the atlases exist in this client)
local function ArtOK()
    if L.ok == nil then
        L.ok = HasAtlas(DISC_ATLAS)
        for _, a in pairs(ART) do L.ok = L.ok and HasAtlas(a[1]) and HasAtlas(a[2]) end
    end
    return L.ok
end

-- parent: Dungeon.lua's icon frame (its alpha follows the floor cross-fades)
function Links:Setup(parent)
    L.parent = parent
end

local function NewPin()
    local p = L.parent
    local disc = p:CreateTexture(nil, "OVERLAY", nil, 3)
    disc:SetAtlas(DISC_ATLAS, false)
    disc:SetVertexColor(0.03, 0.025, 0.02, 0.72)
    disc:Hide()
    local arrow = p:CreateTexture(nil, "OVERLAY", nil, 4)
    arrow:Hide()
    return { disc = disc, arrow = arrow, on = false }
end

local function Paint(pin)
    local art = ART[pin.link.dir] or ART.down
    pin.arrow:SetAtlas(art[pin == L.hot and 2 or 1], false)
    pin.size = nil
    L.dirty = true
end

-- The links of a page (a hub's level), or nil.
function Links:ForPage(page)
    local t = page and page.kind == "cave" and ns.DUNGEON_LEVEL_LINKS and ns.DUNGEON_LEVEL_LINKS[page.cave]
    if t and t[1] then return t end
end

function Links:SetPage(page)
    L.hot = nil
    local n = 0
    if L.parent and ArtOK() then
        for _, lk in ipairs(self:ForPage(page) or {}) do
            if type(lk.x) == "number" and type(lk.y) == "number" and ns.DUNGEON_CAVES and ns.DUNGEON_CAVES[lk.to] then
                n = n + 1
                local pin = L.pins[n] or NewPin()
                L.pins[n] = pin
                pin.link, pin.x = lk, nil
                Paint(pin)
            end
        end
    end
    for i = n + 1, #L.pins do
        local pin = L.pins[i]
        pin.link = nil
        if pin.on then
            pin.on = false
            pin.disc:Hide()
            pin.arrow:Hide()
        end
    end
    L.n = n
    L.dirty = true
end

function Links:Count() return L.n end

-- Every frame over the view (cheap: only when the view moved or a pin changed).
-- viewXY(u, v) -> view px, inArea(px, py), k = the icon scale (zoom ^ 0.25).
function Links:Place(viewXY, inArea, k, moved)
    if not (moved or L.dirty) then return end
    L.dirty = false
    for i = 1, L.n do
        local pin = L.pins[i]
        local px, py = viewXY(pin.link.x, pin.link.y)
        pin.px, pin.py = px, py
        local on = inArea(px, py)
        if on then
            local size = SIZE * k * (pin == L.hot and GROW or 1)
            if pin.size ~= size then
                pin.arrow:SetSize(size, size)
                pin.disc:SetSize(size * DISC, size * DISC)
                pin.size = size
            end
            if pin.x ~= px or pin.y ~= py then
                pin.arrow:SetPoint("CENTER", L.parent, "TOPLEFT", px, -py)
                pin.disc:SetPoint("CENTER", L.parent, "TOPLEFT", px, -py)
                pin.x, pin.y = px, py
            end
        end
        if on ~= pin.on then
            pin.on = on
            pin.disc:SetShown(on)
            pin.arrow:SetShown(on)
        end
    end
end

-- The link whose pin is under view point (mx, my): a HIT x HIT px square
-- (x the icon scale), never under the bar (barH); nil if none.
function Links:At(mx, my, k, barH)
    if L.n == 0 or not (mx and my) or my < (barH or 0) then return nil end
    local half = HIT / 2 * (k or 1)
    local best, bestD
    for i = 1, L.n do
        local pin = L.pins[i]
        if pin.on and pin.px then
            local dx, dy = math.abs(mx - pin.px), math.abs(my - pin.py)
            if dx <= half and dy <= half and (not best or dx * dx + dy * dy < bestD) then
                best, bestD = pin, dx * dx + dy * dy
            end
        end
    end
    return best and best.link
end

-- Light the pin of link lk (nil: none).
function Links:SetHot(lk)
    local want
    for i = 1, L.n do if L.pins[i].link == lk then want = L.pins[i] end end
    if want == L.hot then return end
    local old = L.hot
    L.hot = want
    if old and old.link then Paint(old) end
    if want then Paint(want) end
end

-- The bar button's text: the arrow (when its 1x atlas exists), then the other level's name.
function Links:ButtonText(lk, name)
    local m = MARKUP[lk.dir]
    if m and L.markup == nil then
        L.markup = HasAtlas("housing-stair-arrow-down-default") and HasAtlas("housing-stair-arrow-up-default")
    end
    return ((L.markup and m) or "") .. (name or "")
end

function Links:DebugText()
    if L.n == 0 then return "none" end
    local t = {}
    for i = 1, L.n do
        local pin = L.pins[i]
        t[#t + 1] = ("%s->%s%s"):format(pin.link.dir, pin.link.to, pin.on and "" or " (off view)")
    end
    return table.concat(t, ", ")
end
