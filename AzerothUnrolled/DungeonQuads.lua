local _, ns = ...

-- Minimap pages (DungeonMapsMM.lua): pictures put together from the client's
-- own minimap textures instead of Blizzard's 12 map tiles, on a picture layer
-- of the dungeon view (Dungeon.lua NewLayer: 1002 x 668, scaled by the view).
--   q  = { fileDataID, u0, v0, u1, v1, ULx, ULy, LLx, LLy, URx, URy, LRx, LRy, sublevel }: one texture filling the box
--        u0..v1 of the picture (0..1, clipped to it) through its 8 texcoords (all inside 0..1), ARTWORK sublevel
--   rq = { fileDataID, cx, cy, w, h, radians, sublevel }: a block at an angle - the whole texture as a w x h quad
--        centred on picture px (cx, cy), turned by Texture:SetRotation(radians) about its centre. Turned blocks reach
--        past the picture's edge, so they live in a frame that clips to the picture (Frame:SetClipsChildren); the
--        page's backdrop is drawn there too, so the whole page is on that one frame (the layer itself shows nothing
--        then) and its draw order never depends on how two frames of one level are sorted.
--   bg = { fileDataID, tile px }: tiled backdrop; bgc = { r, g, b }: plain backdrop
--   st = { d = desaturate, c = { r, g, b, a } } for every block
-- APIs (this client's Blizzard_APIDocumentationGenerated, forever 1.60.1): SimpleTextureBaseAPIDocumentation.lua
-- SetRotation l.527 (radians, normalizedRotationPoint Nilable: the centre), SetSnapToPixelGrid l.555,
-- SetTexelSnappingBias l.594, SetDesaturated l.417, SetTexCoord l.580 (documented with 4 values; the 8-value corner form
-- used here is Blizzard's own in this client: Blizzard_SharedXML/MixinUtil.lua l.68, Blizzard_SharedXMLBase/AnchorUtil.lua
-- l.375), SetColorTexture l.403; SimpleFrameAPIDocumentation.lua
-- SetClipsChildren l.1217, SetFixedFrameLevel l.1248 (Util.lua); SimpleRegionAPIDocumentation.lua IsObjectLoaded l.110,
-- SetVertexColor l.191, SetDrawLayer l.147. Every one that 2.7.0 did not use is checked before it is called.
-- (A file of its own, like DungeonLinks.lua: Dungeon.lua's chunk and functions stay far from Lua 5.1's limits.)
local Q = {}
ns.Quads = Q

local ART_W, ART_H = 1002, 668

local function NoSnap(t)
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
    if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
end

local function Style(t, st)
    local c = st and st.c
    if t.SetDesaturated then t:SetDesaturated(st and st.d and true or false) end
    t:SetVertexColor(c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 1)
end

local function Backdrop(bg, f)
    if f.bg then
        bg:SetTexture(f.bg[1], "REPEAT", "REPEAT")
        bg:SetTexCoord(0, ART_W / f.bg[2], 0, ART_H / f.bg[2])
        bg:Show()
    elseif f.bgc then
        bg:SetColorTexture(f.bgc[1], f.bgc[2], f.bgc[3], 1)
        bg:Show()
    else
        bg:SetTexture(nil)
        bg:Hide()
    end
end

local function Empty(list, from)
    for i = from, #list do
        list[i]:Hide()
        list[i]:SetTexture(nil)
    end
end

-- The layer's plain quads and their backdrop (on the layer itself).
local function Pool(L)
    if not L.q then
        L.q = {}
        local bg = L:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(L)
        bg:Hide()
        L.bgTex = bg
    end
    return L.q
end

-- The layer's angled blocks: L.clip (clips to the picture) > L.hold (the
-- blocks and their backdrop), both at the layer's frame level. nil when the
-- client cannot clip or turn textures (the page then shows its backdrop only).
local function Holder(L)
    if L.hold then return L.hold end
    if L.noHold then return nil end
    local clip = CreateFrame("Frame", nil, L)
    if not (clip.SetClipsChildren and clip.CreateTexture) then
        clip:Hide()
        L.noHold = true
        return nil
    end
    clip:SetAllPoints(L)
    clip:SetClipsChildren(true)
    local hold = CreateFrame("Frame", nil, clip)
    hold:SetAllPoints(clip)
    local bg = hold:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(hold)
    bg:Hide()
    L.clip, L.hold, L.rbg, L.rq = clip, hold, bg, {}
    clip:Hide()
    return hold
end

-- The clip frame follows the layer's frame level (Dungeon.lua swaps the two
-- layers' levels for its cross-fades).
function Q:Relevel(L)
    if not L.clip then return end
    local lv = L:GetFrameLevel()
    ns.SetLevelFixed(L.clip, lv)
    ns.SetLevelFixed(L.hold, lv)
end

local function LoadPlain(L, f)
    local pool = Pool(L)
    for i, q in ipairs(f.q) do
        local t = pool[i]
        if t then
            t:SetDrawLayer("ARTWORK", q[14])
        else
            t = L:CreateTexture(nil, "ARTWORK", nil, q[14])
            NoSnap(t)
            pool[i] = t
        end
        t:SetTexture(q[1], "CLAMP", "CLAMP", "TRILINEAR")
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", L, "TOPLEFT", q[2] * ART_W, -q[3] * ART_H)
        t:SetSize((q[4] - q[2]) * ART_W, (q[5] - q[3]) * ART_H)
        t:SetTexCoord(q[6], q[7], q[8], q[9], q[10], q[11], q[12], q[13])
        Style(t, f.st)
        t:Show()
    end
    Empty(pool, #f.q + 1)
    Backdrop(L.bgTex, f)
end

local function LoadAngled(L, f)
    local hold = Holder(L)
    if not hold then return end
    local list = L.rq
    local turn = true
    for i, b in ipairs(f.rq) do
        local t = list[i]
        if t then
            t:SetDrawLayer("ARTWORK", b[7])
        else
            t = hold:CreateTexture(nil, "ARTWORK", nil, b[7])
            NoSnap(t)
            list[i] = t
        end
        if not t.SetRotation then turn = false break end
        t:SetTexture(b[1], "CLAMP", "CLAMP", "TRILINEAR")
        t:ClearAllPoints()
        t:SetPoint("CENTER", hold, "TOPLEFT", b[2], -b[3])
        t:SetSize(b[4], b[5])
        t:SetTexCoord(0, 1, 0, 1)
        t:SetRotation(b[6])
        Style(t, f.st)
        t:Show()
    end
    Empty(list, turn and #f.rq + 1 or 1)
    Backdrop(L.rbg, f)
    Q:Relevel(L)
    L.clip:Show()
end

local function ClearAngled(L)
    if not L.hold then return end
    Empty(L.rq, 1)
    L.rbg:SetTexture(nil)
    L.rbg:Hide()
    L.clip:Hide()
end

local function ClearPlain(L)
    if not L.q then return end
    Empty(L.q, 1)
    L.bgTex:SetTexture(nil)
    L.bgTex:Hide()
end

-- Show floor f (f.q or f.rq) on picture layer L.
function Q:Load(L, f)
    if f.rq then
        ClearPlain(L)
        LoadAngled(L, f)
    else
        ClearAngled(L)
        LoadPlain(L, f)
    end
end

-- Nothing of a minimap floor on layer L (a tile floor shows there, or release).
function Q:Clear(L)
    ClearPlain(L)
    ClearAngled(L)
end

local function AllLoaded(list, bg)
    for _, t in ipairs(list or {}) do
        if t:IsShown() and t.IsObjectLoaded and not t:IsObjectLoaded() then return false end
    end
    if bg and bg:IsShown() and bg.IsObjectLoaded and not bg:IsObjectLoaded() then return false end
    return true
end

-- Every shown block (and the backdrop) has its texture.
function Q:Loaded(L)
    return AllLoaded(L.q, L.bgTex) and AllLoaded(L.rq, L.rbg)
end

function Q:Count(L)
    local n = 0
    for _, t in ipairs(L.q or {}) do if t:IsShown() then n = n + 1 end end
    for _, t in ipairs(L.rq or {}) do if t:IsShown() then n = n + 1 end end
    return n
end
