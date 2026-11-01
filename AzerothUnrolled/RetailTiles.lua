--[[
Endless Map - RetailTiles.lua (1.4.0; retail only: AzerothUnrolled_Standard.toc, before RetailRender.lua)

The textures of retail's pictures: docs/retail-engine.md section 5, "Dynamic loading" - the plan's bounding rule made
exact - and (1.4.0-beta2) section 11.2, "load as the client loads". RetailRender.lua decides what draws; this file holds
the art of each part and keeps it bounded.

  * A part is one layer of one map's picture: its base art (layer 1's tiles, C_Map.GetMapArtLayerTextures - the
    client's own, phase-correct), or its explored pieces (its "top", C_MapExplorationInfo.GetExploredMapTextures, tiled
    as Blizzard's MapExplorationDataProvider.lua: the tile size from the layer, files from 16 px). A part is a frame of
    textures in the picture's own pixels (layer px), placed and scaled as a whole (RetailRender.lua). (1.4.0-beta2) The
    frame has its picture's size (TL.SetSpec), as WoW Forever's Render.lua sizes every part frame - in game the part
    frames of 1.4.0-beta1 had only a corner point.
  * Tile windows, (1.4.0-beta14) the viewport: a part keeps an emitted window of tiles - the view in layer px grown by
    0.125 of the view per side, snapped to tiles; while what the view needs stays inside it nothing changes, else it becomes
    the view grown by 0.25 per side. Tiles leaving it are HIDDEN with their files (HideList: part.held), not given back:
    back in the window they show again, no SetTexture, no second load unless the client let the file go, and then they
    fade in once loaded (ShowList, TL.StepLate) over the coarser picture that stays under them - never a hole. 1.4.0-beta2 -
    1.4.0-beta13 grew the view by 0.5 a side and gave each leaving tile back: 47,791 tile loads in the player's session for
    17,649 textures made, 3,988 shown for 1,800 drawn. Only over LIVE_MAX do the hidden ones go (TL.FreeHeld). A masked
    continent skips the tiles its land mask leaves out (RetailTree.lua tm). A tile whose file is wholly empty is left out
    (RetailEmptyTiles.lua).
  * (1.4.0-beta15) What is shown is what is in view (TL.ShowIn, each frame): a tile of the window outside the view is shown only
    until the client has loaded it (it loads only what is visible: 11.1, 3), then hidden with its file, so a drag finds it
    loaded and costs a Show. 1.4.0-beta14 kept the whole window and every world's and continent's whole picture shown: at 5.49x
    in the player's window 921 shown for 179 in view - all of them laid out again each frame of a motion.
  * Cut-outs: a zone's or an inset's picture is cropped and its edge feathered (crop / feather px, Render.lua Emit's
    quads and gradients: an edge tile is split where the feather starts, a corner in strips); (1.4.0-beta4) its printed
    frame is never drawn (1.4.0-beta3's frame ring, the uncropped edge brought back by the view's place, went with the
    look by the zoom alone). A masked part (a land mask, a globe's round mask) adds its one mask texture to every tile.
  * Budget: at most NEW_PER_FRAME (96) new SetTexture calls a frame - RetailRender.lua spends them on the drawn parts
    first, deepest first, then the ones loading, then the preloads; a part whose window is not complete yet waits
    (pending). TL.live counts the textures with a file (LIVE_MAX 16,000: above it the stages not drawn for 2 s go, least
    recently drawn first, down to 12,800 - RetailRender.lua), TL.peak its highest.
  * Loading (TL.LoadState): "ok" - every texture of the part in view and its mask report IsObjectLoaded (confirmed);
    "wait" - one does not yet. (1.4.0-beta4's fixes) Waited for as long as it takes, as Blizzard's map waits
    (Blizzard_MapCanvasDetailLayer.lua:91-105, TextureLoadingGroupMixin, MixinUtil.lua:326-335: no timeout): 1.4.0-beta2's
    third state "gave" (a texture not loaded LOAD_GIVEUP, 2 s, after its first visible frame counted as there) guarded a
    failure no client showed - the player's: "a saftie net isnt a fix it's a bandaid". A picture whose files never load
    stays out and its parent stays in (rules 1 and 3, RetailRender.lua); the stamp's load.slow says whether a texture ever
    takes long (TL.PollLoads). A part hidden for any reason starts again (part.visAt nil).
Textures are reused, never destroyed, and (1.4.0-beta2) never moved: each part keeps its own pool of textures made on
its own frame (as Render.lua's NextTex) - a texture given back keeps no file and waits for its part's next tile. Whole
parts are reused by RetailRender.lua (a released stage's frames go to the next stage: the frame moves, never a
texture). (1.4.0-beta1's one shared pool moved textures between frames by SetParent: in game they drew nothing.)
Alpha per texture and part only - no frame buffer (design rule 1).
]]
local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)
if ns.FLAVOR ~= "retail" then return end

local TL = {}
ns.RetailTiles = TL
-- (1.4.0-beta2) the session's test switches (RetailWhy.lua: /emap test - never saved, a /reload clears them): nomask,
-- noclip, noload, nofade, canvas; read here, by RetailRender.lua and by Core.lua (UpdateCanvasAlpha)
local TEST = {}
ns.retailTest = TEST

TL.NEW_PER_FRAME = 96
-- (1.4.0-beta2, docs/retail-engine.md 11.6: what is resident is what is shown - the client keeps a texture's file only
-- while it is visible; files set on parts not shown cost no texture memory)
-- ((1.4.0-beta13) 12,000 - 1.4.0-beta2's 6,000 the player's session reached (peak 5,968), a stage's 1,100 given back in a frame
-- and set again on the way back: a file set costs no memory while hidden - the client lets those go by itself, the stamp's
-- reshow: 24% after 1 - 10 s, 58% after more -, what it keeps is what is shown, SHOWN_MAX)
-- ((1.4.0-beta14) 16,000: the tiles outside the viewport hold their files too)
TL.LIVE_MAX, TL.LIVE_LOW = 16000, 12800
TL.SHOWN_MAX = 4000
TL.SHOW_PER_FRAME, TL.PRELOAD_SHOW = 160, 64
-- ((1.4.0-beta4's fixes, the in-game probe P2) a texture visible this long and not loaded is counted slow - the stamp's
-- load.slow; nothing waits less for it: a diagnostic, never a give-up)
local SLOW_S = 1
local CORNER_STRIPS = 4
local ITEM_MAX = 32          -- (the most textures one tile can take: its four corners in strips, the edges and the middle -
                            -- a picture of one tile; 1.4.0-beta1's 16 let a frame set 97 or 98)
local CLAMP, FILTER = "CLAMP", "TRILINEAR"
TL.SLOW_S = SLOW_S
-- ((1.4.0-beta15) the view grown by this much a side, of the view: a tile is shown from VIEW_SHOW, hidden past VIEW_HIDE - a second
-- draw in a frame moves the camera a little, and no tile flips at the edge. TOUCH_EVERY: a hidden tile of the window is shown again,
-- to see it is still loaded, at most this often, in seconds - the client let 6% of its hidden files go after 1 - 10 s, 59% after more)
local VIEW_SHOW, VIEW_HIDE = 0.03, 0.06
local TOUCH_EVERY = 4
TL.TOUCH_EVERY = TOUCH_EVERY
local HOLD_FRAMES, HOLD_NARROW = 8, 0.8 -- ((1.4.0-beta16) TL.ShowIn)

TL.live, TL.peak, TL.newThisFrame, TL.evicted, TL.made = 0, 0, 0, 0, 0
TL.newShown, TL.newParts = 0, 0 -- (textures and parts newly shown this game frame: RetailRender.lua resets them)
TL.reshown = 0 -- ((1.4.0-beta14) the tiles of the windows shown again this game frame: the same)
TL.now, TL.tick = 0, 0 -- (RetailRender.lua's frame: GetTime() and its frame count, for the load times)

local floor, min, max = math.floor, math.min, math.max
local function Plain(v, kind) return type(v) == kind and not (issecretvalue and issecretvalue(v)) end
local function Num(v) return Plain(v, "number") and v == v end
local function Clamp01(x) if x < 0 then return 0 elseif x > 1 then return 1 end return x end

---------------------------------------------------------------------------
-- The art: layer 1 of a map (cached for the session; a failed read is tried again later)
---------------------------------------------------------------------------
local layouts = {}
function TL.Layout(id)
    local L = layouts[id]
    if L then return L end
    local ok, layers = pcall(C_Map.GetMapArtLayers, id)
    local A = ok and type(layers) == "table" and layers[1]
    if type(A) ~= "table" or not (Num(A.layerWidth) and Num(A.layerHeight) and Num(A.tileWidth) and Num(A.tileHeight))
        or A.layerWidth <= 0 or A.tileWidth <= 0 or A.tileHeight <= 0 then
        return nil
    end
    local ok2, files = pcall(C_Map.GetMapArtLayerTextures, id, 1)
    if not ok2 or type(files) ~= "table" or #files == 0 then return nil end
    local plain = {}
    for i = 1, #files do plain[i] = Num(files[i]) and files[i] or 0 end
    L = { lw = A.layerWidth, lh = A.layerHeight, tw = A.tileWidth, th = A.tileHeight, files = plain }
    L.cols, L.rows = math.ceil(L.lw / L.tw), math.ceil(L.lh / L.th)
    layouts[id] = L
    return L
end

-- The explored pieces of map id as tiles: { { x0, y0, x1, y1, u1, v1, file, sub }, ... } in layer px (Blizzard's
-- MapExplorationPinMixin:RefreshOverlays tiling; isShownByMouseOver left out). Cached until TL.PiecesDirty().
local pieces = {}
-- ((1.4.0-beta14) the explored tiles with nothing in them: 12 - 15% of a fully explored 3,840-px zone's - the rects of Blizzard's
-- pieces hold corners of nothing; RetailEmptyTiles.lua, tools/retail/build_empty.py; its string read once)
local empty
local function Empty()
    if empty then return empty end
    empty = {}
    if type(ns.RETAIL_EMPTY) == "string" then
        for id in ns.RETAIL_EMPTY:gmatch("%d+") do empty[tonumber(id)] = true end
    end
    ns.RETAIL_EMPTY = nil
    return empty
end
function TL.Pieces(id, L)
    local P = pieces[id]
    if P then return P end
    P = {}
    pieces[id] = P
    if not (L and C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures) then return P end
    local ok, res = pcall(C_MapExplorationInfo.GetExploredMapTextures, id)
    if not ok or type(res) ~= "table" then return P end
    local TW, TH = L.tw, L.th
    local E = Empty()
    P.np = 0 -- ((1.4.0-beta14) how many pieces: RetailRender.lua's small picture, a zone explored whole)
    for _, info in ipairs(res) do
        if type(info) == "table" and type(info.fileDataIDs) == "table" and not info.isShownByMouseOver
            and Num(info.textureWidth) and Num(info.textureHeight) then
            P.np = P.np + 1
            local tw, th = info.textureWidth, info.textureHeight
            local wide, tall = math.ceil(tw / TW), math.ceil(th / TH)
            local ox, oy = Num(info.offsetX) and info.offsetX or 0, Num(info.offsetY) and info.offsetY or 0
            for j = 1, tall do
                local ph, fh = TH, TH
                if j == tall then
                    ph = th % TH
                    if ph == 0 then ph = TH end
                    fh = ns.TILE_FILE_MIN or 16
                    while fh < ph do fh = fh * 2 end
                end
                for k = 1, wide do
                    local pw, fw = TW, TW
                    if k == wide then
                        pw = tw % TW
                        if pw == 0 then pw = TW end
                        fw = ns.TILE_FILE_MIN or 16
                        while fw < pw do fw = fw * 2 end
                    end
                    local file = info.fileDataIDs[(j - 1) * wide + k]
                    if Num(file) and file > 0 and not E[file] then
                        local x0, y0 = ox + TW * (k - 1), oy + TH * (j - 1)
                        P[#P + 1] = { x0, y0, x0 + pw, y0 + ph, pw / fw, ph / fh, file, info.isDrawOnTopLayer and 1 or 0 }
                    end
                end
            end
        end
    end
    return P
end
TL.pieceGen = 0 -- ((1.4.0-beta15) RetailCells.lua's list of the cells drawn: read again when the pieces change)
function TL.PiecesDirty()
    wipe(pieces)
    TL.pieceGen = TL.pieceGen + 1
end

---------------------------------------------------------------------------
-- Parts
---------------------------------------------------------------------------
-- A part: frame f (a child of host), its textures by item key, its own pool of idle textures, the window, the cut-out
-- spec. (1.4.0-beta2) visAt: GetTime() since when its frame is shown (nil while hidden) - RetailRender.lua PlacePart.
function TL.NewPart(host)
    local f = CreateFrame("Frame", nil, host)
    f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    f:SetSize(1, 1) -- (its picture's size from TL.SetSpec)
    f:Hide()
    return { f = f, items = {}, n = 0, pool = {} }
end

local function SetFile(t, file)
    if t.file == file then return end
    if t.file == nil then TL.live = TL.live + 1 elseif file == nil then TL.live = TL.live - 1 end
    if file == nil then
        t:SetTexture(nil)
    else
        local ok = t:SetTexture(file, CLAMP, CLAMP, FILTER)
        t.refused = (ok == false) or nil
        TL.newThisFrame = TL.newThisFrame + 1
        t.setAt, t.setTick = TL.now, TL.tick
    end
    t.file = file
    if file ~= nil and t.ldPart then TL.Watch(t, t.ldPart) end -- ((1.4.0-beta4, probe P1) its load measured: TL.PollLoads)
    if TL.live > TL.peak then TL.peak = TL.live end
end

local function Detach(t)
    if t.maskRef then
        t:RemoveMaskTexture(t.maskRef)
        t.maskRef = nil
    end
end

-- Texture t back to its part's pool (no file, no mask, hidden; the part counts it no more). (held: its list hidden)
local function GiveBack(part, t, held)
    t:Hide()
    Detach(t)
    SetFile(t, nil)
    if t.fa then
        t.fa, t.faAt = nil, nil
        if part.fading then part.fading[t] = nil end
    end
    local pool = part.pool
    pool[#pool + 1] = t
    if held then part.held = part.held - 1 else part.n = part.n - 1 end
end

local function Free(part, list)
    local held = list.on == false
    for i = 1, #list do
        GiveBack(part, list[i], held)
        list[i] = nil
    end
end

-- ((1.4.0-beta14) the viewport) A tile out of its part's window: hidden with its file - part.n counts what is shown,
-- part.held what is kept hidden; no longer measured while hidden
local function HideList(part, list)
    if list.on == false then return end
    local n = #list
    for i = 1, n do
        local t = list[i]
        t:Hide()
        if t.fa then
            t.fa, t.faAt = nil, nil
            if part.fading then part.fading[t] = nil end
            t:SetAlpha(1)
        end
        TL.Unwatch(t)
    end
    list.on = false
    list.touchT = TL.now -- ((1.4.0-beta15) visible until now: FillTile's touch)
    part.n = part.n - n
    part.held = (part.held or 0) + n
end

-- ... back in the window: shown again. A file the client let go while hidden loads again: that tile, of a part shown whole
-- already, fades in once it has (TL.StepLate), as a tile new to it - the picture under it shows until then
local function ShowList(part, list)
    if list.on ~= false then return end
    local n = #list
    for i = 1, n do
        local t = list[i]
        t:Show()
        if not TEST.noload and t.IsObjectLoaded and not t:IsObjectLoaded() then
            if part.visAt then TL.newShown = TL.newShown + 1 end -- (only those the client must load again count as newly shown)
            if part.late and not TEST.nofade then
                t.fa, t.faAt = 0, nil
                local fl = part.fading or {}
                part.fading = fl
                fl[t] = true
                t:SetAlpha(0)
            end
            TL.Watch(t, part)
        end
    end
    list.on = true
    part.n = part.n + n
    part.held = part.held - n
end

-- ((1.4.0-beta14, RetailRender.lua's small picture) No tile of part shown: all kept hidden, its window empty
function TL.Off(part)
    local w = part.win
    if part.n == 0 and w and w[1] > w[3] then return end
    for _, list in pairs(part.items) do HideList(part, list) end
    w = w or {}
    w[1], w[2], w[3], w[4] = 1, 1, 0, 0
    part.win = w
    part.winGen = (part.winGen or 0) + 1
    part.pending = false
end

-- The tiles part keeps hidden go - until TL.live is at limit. Returns whether it is (RetailRender.lua's Evict)
function TL.FreeHeld(part, limit)
    if (part.held or 0) == 0 then return TL.live <= limit end
    -- ((1.4.0-beta15) those of its window too - the view keeps none hidden: the part's next fill makes again what the window holds)
    part.doneGen, part.doneP = nil, nil
    for key, list in pairs(part.items) do
        if list.on == false then
            Free(part, list)
            part.items[key] = nil
            if TL.live <= limit then return true end
        end
    end
    return TL.live <= limit
end

-- A texture for part: one of its own pool, else a new one on its frame (never one of another frame's).
local function Take(part)
    local t = table.remove(part.pool)
    if not t then
        t = part.f:CreateTexture(nil, "ARTWORK")
        TL.made = TL.made + 1
    end
    t.ldPart = part -- ((1.4.0-beta4) the part it lies in: its load measured while that is visible - TL.PollLoads)
    part.n = part.n + 1
    return t
end

local hasGradient
local function Gradient(t, orientation, a0, a1, k)
    if hasGradient == nil then hasGradient = (t.SetGradient ~= nil) and (CreateColor ~= nil) end
    if hasGradient then
        t:SetGradient(orientation, CreateColor(k, k, k, a0), CreateColor(k, k, k, a1))
    else
        t:SetVertexColor(k, k, k, (a0 + a1) / 2)
    end
end

-- (a quad's own alpha: its feather's - one texture a texel, so the edge is the interior at every alpha of the part;
-- (1.4.0-beta6) its colour the part's brightness, TL.SetDim)
local function Shade(part, t)
    local a0, a1, dir = t.qa0, t.qa1, t.qdir
    local k = part.dim or 1
    if dir == "H" then
        Gradient(t, "HORIZONTAL", a0, a1, k)
    elseif dir == "V" then
        Gradient(t, "VERTICAL", a1, a0, k) -- (VERTICAL: the first colour at the bottom)
    else
        t:SetVertexColor(k, k, k, a0)
    end
end

-- ((1.4.0-beta6, the player on 1.4.0-beta5: "can we fade the map image a bit when the real map is in?") part's brightness
-- k (1 as drawn): every quad of it shaded again when it changes (by 0.01 steps) - RetailRender.lua dims a picture whose
-- places' own maps are drawn over it, Argus's under the Antoran Wastes'
function TL.SetDim(part, k)
    k = math.floor(Clamp01(k) * 100 + 0.5) / 100
    if (part.dim or 1) == k then return end
    part.dim = k
    for _, list in pairs(part.items) do
        for i = 1, #list do Shade(part, list[i]) end
    end
end

-- One quad of an item on texture t: layer px x0..x1, y0..y1 of an item spanning ix0.. (its file's u 0..u1 over iw px -
-- (1.4.0-beta3) from u it[9], v it[10] when the item has them: a cover's piece of another place of the picture, RetailCells.lua);
-- alpha a0 (dir nil), or a0 -> a1 left to right ("H") / top to bottom ("V").
local function Lay(part, t, it, x0, y0, x1, y1, a0, a1, dir, sub)
    local du, dv = it[5] / (it[3] - it[1]), it[6] / (it[4] - it[2])
    local u0, v0 = it[9] or 0, it[10] or 0
    t:SetDrawLayer("ARTWORK", sub)
    t:ClearAllPoints()
    t:SetTexCoord(u0 + (x0 - it[1]) * du, u0 + (x1 - it[1]) * du, v0 + (y0 - it[2]) * dv, v0 + (y1 - it[2]) * dv)
    t:SetSize(x1 - x0, y1 - y0)
    t:SetPoint("TOPLEFT", part.f, "TOPLEFT", x0, -y0)
    t.qa0, t.qa1, t.qdir = a0, a1, dir -- (for the harness: the quad's own alpha)
    Shade(part, t)
    t.qx0, t.qy0, t.qx1, t.qy1 = x0, y0, x1, y1
    -- (1.4.0-beta2, the review of the seams, point 1) a tile new to a part already shown whole - its window moved on, the
    -- picture's load fade long done (part.late: RetailRender.lua) - fades in once it loads (TL.StepLate), as the part did
    if t.file ~= it[7] and part.late and not TEST.nofade then
        t.fa, t.faAt = 0, nil
        local fl = part.fading or {}
        part.fading = fl
        fl[t] = true
    end
    t:SetAlpha(t.fa or 1)
    local m = part.mask
    if TEST.nomask then m = nil end -- (1.4.0-beta2: /emap test nomask - RetailWhy.lua)
    if t.maskRef ~= m then
        Detach(t)
        if m then
            t:AddMaskTexture(m)
            t.maskRef = m
        end
    end
    SetFile(t, it[7])
    if not t:IsShown() then
        t:Show()
        if part.visAt then TL.newShown = TL.newShown + 1 end
    end
end

-- The quads of item it on part (spec: crop, fw feather) into list (its textures, reused in order).
local function EmitItem(part, it, list)
    local S, n = part.spec, 0
    local function Q(x0, y0, x1, y1, a0, a1, dir, sub)
        if x1 - x0 < 0.01 or y1 - y0 < 0.01 then return end
        n = n + 1
        local t = list[n]
        if not t then
            t = Take(part)
            list[n] = t
        end
        Lay(part, t, it, x0, y0, x1, y1, a0, a1, dir, sub)
    end
    local ix0, iy0, ix1, iy1, sub = it[1], it[2], it[3], it[4], it[8] or 0
    local crop, fw = S.crop or 0, S.fw or 0
    if crop <= 0 and fw <= 0 then
        Q(ix0, iy0, ix1, iy1, 1, 1, nil, sub)
    else
        local lw, lh = S.lw, S.lh
        local cx0, cy0, cx1, cy1 = crop, crop, lw - crop, lh - crop
        local ax0, ay0, ax1, ay1 = max(ix0, cx0), max(iy0, cy0), min(ix1, cx1), min(iy1, cy1)
        if ax1 - ax0 >= 0.01 and ay1 - ay0 >= 0.01 then
            local function AX(x) return fw > 0 and Clamp01((x - cx0) / fw) * Clamp01((cx1 - x) / fw) or 1 end
            local function AY(y) return fw > 0 and Clamp01((y - cy0) / fw) * Clamp01((cy1 - y) / fw) or 1 end
            local xs, ys = { ax0 }, { ay0 }
            for _, s in ipairs({ cx0 + fw, cx1 - fw }) do if s > ax0 + 0.01 and s < ax1 - 0.01 then xs[#xs + 1] = s end end
            for _, s in ipairs({ cy0 + fw, cy1 - fw }) do if s > ay0 + 0.01 and s < ay1 - 0.01 then ys[#ys + 1] = s end end
            table.sort(xs)
            table.sort(ys)
            xs[#xs + 1], ys[#ys + 1] = ax1, ay1
            for j = 1, #ys - 1 do
                local ya, yb = ys[j], ys[j + 1]
                for i = 1, #xs - 1 do
                    local xa, xb = xs[i], xs[i + 1]
                    local la, lb, ta, tb = AX(xa), AX(xb), AY(ya), AY(yb)
                    if not (la <= 0 and lb <= 0) and not (ta <= 0 and tb <= 0) then
                        if la == lb and ta == tb then
                            Q(xa, ya, xb, yb, la * ta, la * ta, nil, sub)
                        elseif ta == tb then
                            Q(xa, ya, xb, yb, la * ta, lb * ta, "H", sub)
                        elseif la == lb then
                            Q(xa, ya, xb, yb, la * ta, la * tb, "V", sub)
                        else
                            for s = 0, CORNER_STRIPS - 1 do
                                local s0 = ya + (yb - ya) * s / CORNER_STRIPS
                                local s1 = ya + (yb - ya) * (s + 1) / CORNER_STRIPS
                                local t = AY((s0 + s1) / 2)
                                if t > 0 then Q(xa, s0, xb, s1, la * t, lb * t, "H", sub) end
                            end
                        end
                    end
                end
            end
        end
    end
    for i = #list, n + 1, -1 do
        local t = list[i]
        list[i] = nil
        GiveBack(part, t)
    end
    -- (the item's rect, for TL.ShowIn: whether it lies in the view)
    local r = list.r or {}
    r[1], r[2], r[3], r[4] = ix0, iy0, ix1, iy1
    list.r, list.on = r, true
    return n
end

-- ((1.4.0-beta15) the viewport, tile by tile) Of part's tiles those in the view (layer px x0, y0, x1, y1) are shown, a hidden one
-- shown again at once whatever the client let go - it fades in once loaded (ShowList), over the picture under it; those outside are
-- hidden once the client has loaded them, their files kept (it loads only what is visible: a tile of the window new to it stays shown
-- until then, off the screen). Counts the textures reaching into the view - drawn while the part has an alpha (part.inView) - and
-- returns the count. force: a second draw in the frame, the camera moved. The Cosmic map keeps every tile: the floor everywhere.
-- /emap test noviewport: as 1.4.0-beta14 - the window shown whole (RetailBench.lua compares the two in the player's client).
-- (The reviews of 1.4.0-beta2: a tile hidden for good under a picture over it went: 1.4.0-beta1's masked tiles under a continent's
-- opaque middle, that picture going out faded over nothing loaded. Here what is in view stays shown, covered or not.)
local function ListLoaded(list)
    if TEST.noload then return true end
    for i = 1, #list do
        local t = list[i]
        if t.file and t.IsObjectLoaded and not t:IsObjectLoaded() then return false end
    end
    return true
end
function TL.ShowIn(part, view, force)
    if not force and part.inTick == TL.tick and part.inVpx == view and part.inGen == part.winGen and not part.pending then return part.inView end -- ((1.4.0-beta14) once a frame)
    part.inTick, part.inVpx, part.inGen = TL.tick, view, part.winGen
    local v0, v1, v2, v3 = view[1], view[2], view[3], view[4]
    -- (nothing shown, the view off its picture: nothing to do - most of the pictures near the view)
    local S0 = part.spec
    if part.n == 0 and S0 and (v2 <= 0 or v3 <= 0 or v0 >= S0.lw or v1 >= S0.lh) then
        part.inView = 0
        return 0
    end
    -- ((1.4.0-beta16) the view still inside what the last walk showed, nothing waiting to be hidden, not much narrower: nothing to do - a walk over every tile the part holds,
    -- each frame of a motion, 9% of the add-on's Lua. At most HOLD_FRAMES: what has left the view goes then)
    local sr = part.sr
    if sr and not force and part.srGen == part.winGen and not part.pending and not part.srWait and TL.tick - part.srTick < HOLD_FRAMES
        and v0 >= sr[1] and v1 >= sr[2] and v2 <= sr[3] and v3 <= sr[4] and v2 - v0 >= HOLD_NARROW * (sr[3] - sr[1]) then
        return part.inView
    end
    local gx, gy = (v2 - v0) * VIEW_SHOW, (v3 - v1) * VIEW_SHOW
    local s0, s1, s2, s3 = v0 - gx, v1 - gy, v2 + gx, v3 + gy
    gx, gy = (v2 - v0) * VIEW_HIDE, (v3 - v1) * VIEW_HIDE
    local h0, h1, h2, h3 = v0 - gx, v1 - gy, v2 + gx, v3 + gy
    local w = part.win
    local off = w ~= nil and w[1] > w[3] -- (no window: TL.Off's small picture, or the view reaches nothing of it)
    local keep = TEST.noviewport or (part.spec ~= nil and part.spec.key == "root")
    local n = 0
    local waiting = false
    for _, list in pairs(part.items) do
        local r = list.r
        if r ~= nil then
            local x0, y0, x1, y1 = r[1], r[2], r[3], r[4]
            if list.on == false then
                if not off and not keep and x1 > s0 and x0 < s2 and y1 > s1 and y0 < s3 then ShowList(part, list) end
            elseif not keep and (x1 <= h0 or x0 >= h2 or y1 <= h1 or y0 >= h3) then
                if ListLoaded(list) then HideList(part, list) else waiting = true end
            end
            if list.on ~= false and x1 > v0 and x0 < v2 and y1 > v1 and y0 < v3 then n = n + #list end
        end
    end
    part.inView = n
    sr = sr or {}
    sr[1], sr[2], sr[3], sr[4] = s0, s1, s2, s3
    part.sr, part.srGen, part.srTick, part.srWait = sr, part.winGen, TL.tick, waiting
    return n
end

-- (1.4.0-beta2, the review of the seams, point 1) The tiles of part fading in (Lay): each once IsObjectLoaded, up over
-- LATE_FADE ((1.4.0-beta4's fixes) once it loads, however long: 1.4.0-beta2 faded one in LOAD_GIVEUP after it was set
-- whether or not it had loaded - a net). Returns whether one still fades (RetailRender.lua: busy). TL.FadingIn: does one
-- lie in the view (layer px)?
local LATE_FADE = 0.2
function TL.StepLate(part, now)
    local fl = part.fading
    if not fl or next(fl) == nil then return false end
    local busy = false
    for t in pairs(fl) do
        if not t.faAt and (TEST.nofade or not t.IsObjectLoaded or t:IsObjectLoaded()) then
            t.faAt = now
        end
        local x = 0
        if t.faAt then
            x = Clamp01((now - t.faAt) / LATE_FADE)
            x = x * x * (3 - 2 * x)
        end
        local was = t.fa
        if x >= 1 or TEST.nofade then
            t.fa, t.faAt, fl[t] = nil, nil, nil
            x = 1
        else
            t.fa = x
            busy = true
        end
        if was ~= x then t:SetAlpha(x) end -- ((1.4.0-beta15) waiting for its load: at 0 already)
    end
    return busy
end
function TL.FadingIn(part, view)
    local fl = part.fading
    if not fl or next(fl) == nil then return false end
    for t in pairs(fl) do
        if not view or (t.qx0 < view[3] and t.qx1 > view[1] and t.qy0 < view[4] and t.qy1 > view[2]) then return true end
    end
    return false
end

-- Item (c, r) of a grid part, in a scratch table: { x0, y0, x1, y1, u1, v1, file, sub } (half a texel short at the last
-- column / row, so filtering cannot pull in the padding - Render.lua EmitBaseTiles). (1.4.0-beta3) full: the quad still
-- reaches the picture's edge, its texture coordinates half a texel short - the Cosmic map, the floor everywhere: its
-- half texel short left a strip bare at its edge, 21 px wide deep in a flight to Stormshield (retailwalk:draenor)
local cell = {}
local function GridItem(L, c, r, full)
    local file = L.files[(r - 1) * L.cols + c]
    if not file or file == 0 then return nil end
    local x0, y0 = (c - 1) * L.tw, (r - 1) * L.th
    local w, h = min(L.tw, L.lw - x0), min(L.th, L.lh - y0)
    local qw, qh = w, h
    if w < L.tw then w = w - 0.5 end
    if h < L.th then h = h - 0.5 end
    if not full then qw, qh = w, h end
    cell[1], cell[2], cell[3], cell[4], cell[5], cell[6], cell[7], cell[8] = x0, y0, x0 + qw, y0 + qh, w / L.tw, h / L.th, file, 0
    return cell
end

-- The part's spec: { lw, lh, crop, fw, tm (tile bitmap or nil), key; 1.4.0-beta3: full - GridItem }. A new key lays
-- every emitted item again.
-- (1.4.0-beta2) The part's frame takes its picture's size (Render.lua: every part frame spans its picture).
function TL.SetSpec(part, spec)
    part.spec = spec
    local f = part.f
    if f.sw ~= spec.lw or f.sh ~= spec.lh then
        f:SetSize(spec.lw, spec.lh)
        f.sw, f.sh = spec.lw, spec.lh
    end
end

-- The window for view (layer px x0, y0, x1, y1) on an art of lw x lh in tiles of tw x th: the emitted one while the
-- view grown by WIN_KEEP a side stays inside it, else the view grown by WIN_NEW a side. all: every tile (the Cosmic map).
local WIN_KEEP, WIN_NEW = 0.125, 0.25
local function Snap(view, m, L)
    local vw, vh = view[3] - view[1], view[4] - view[2]
    local x0, y0 = max(0, view[1] - m * vw), max(0, view[2] - m * vh)
    local x1, y1 = min(L.lw, view[3] + m * vw), min(L.lh, view[4] + m * vh)
    return floor(x0 / L.tw) + 1, floor(y0 / L.th) + 1, min(L.cols, floor((x1 - 0.01) / L.tw) + 1), min(L.rows, floor((y1 - 0.01) / L.th) + 1)
end
function TL.Window(part, L, view, all)
    local w = part.win
    if all then
        if w and w[1] == 1 and w[2] == 1 and w[3] == L.cols and w[4] == L.rows then return w end
        part.win = { 1, 1, L.cols, L.rows }
        part.winGen = (part.winGen or 0) + 1
        return part.win
    end
    local a0, b0, a1, b1 = Snap(view, WIN_KEEP, L)
    if a0 > a1 or b0 > b1 then
        -- ((1.4.0-beta14) the view grown does not reach this picture: no tile shown. 1.4.0-beta3 - 1.4.0-beta13 kept the window
        -- it had, whole for a picture seen whole: 427 of Azj-Kahet's shown off the screen from Kul Tiras, within NEAR)
        if w and w[1] == 1 and w[2] == 1 and w[3] == 0 and w[4] == 0 then return w end
        w = w or {}
        w[1], w[2], w[3], w[4] = 1, 1, 0, 0
        part.win = w
        part.winGen = (part.winGen or 0) + 1
        return w
    end
    if w and a0 >= w[1] and b0 >= w[2] and a1 <= w[3] and b1 <= w[4] then
        -- (1.4.0-beta2: every tile of the window is shown, hence resident - a window left far larger than the view needs
        -- by a zoom in, more than twice the tiles of a new one and 4 more, is drawn in again)
        local c0, d0, c1, d1 = Snap(view, WIN_NEW, L)
        if (w[3] - w[1] + 1) * (w[4] - w[2] + 1) <= 2 * (c1 - c0 + 1) * (d1 - d0 + 1) + 4 then return w end
    end
    w = w or {}
    w[1], w[2], w[3], w[4] = Snap(view, WIN_NEW, L)
    part.win = w
    part.winGen = (part.winGen or 0) + 1
    return w
end

local function InWin(w, x0, y0, x1, y1, L)
    if not w or w[1] > w[3] or w[2] > w[4] then return false end
    return x1 > (w[1] - 1) * L.tw and x0 < w[3] * L.tw and y1 > (w[2] - 1) * L.th and y0 < w[4] * L.th
end

-- One tile (c, r) of grid part's window made, if it is not yet and draws (budget: new SetTexture calls). Returns the
-- budget left, and true when the budget ran out before it.
local function FillTile(part, L, S, c, r, budget, margin)
    local key = (r - 1) * L.cols + c
    local tm = S.tm
    local have = part.items[key]
    if have then
        if have.on == false then
            -- ((1.4.0-beta15) the margin's: shown again only to see they are still loaded - TL.ShowIn hides them again - at most every TOUCH_EVERY,
            -- at TL.SHOW_PER_FRAME a frame; those in view at once - FillView's pass)
            if margin and not TEST.noviewport and TL.now - (have.touchT or -1e9) < TOUCH_EVERY then return budget end
            if margin and TL.reshown >= TL.SHOW_PER_FRAME then return budget, true end
            TL.reshown = TL.reshown + #have
            have.touchT = TL.now
            part.sr = nil -- (the next TL.ShowIn hides it again)
            ShowList(part, have)
        end
        return budget
    end
    if tm and tm:byte(key) == 48 then return budget end -- ("0": outside the land mask)
    local it = GridItem(L, c, r, S.full)
    if it and (S.crop or 0) > 0 then
        -- (an item wholly in the cropped edge draws nothing)
        if it[3] <= S.crop or it[1] >= S.lw - S.crop or it[4] <= S.crop or it[2] >= S.lh - S.crop then it = nil end
    end
    if not it then return budget end
    if budget < (((S.crop or 0) > 0 or (S.fw or 0) > 0) and ITEM_MAX or 1) then return budget, true end
    local before = TL.newThisFrame
    local list = {}
    part.items[key] = list
    EmitItem(part, it, list)
    return budget - (TL.newThisFrame - before)
end

-- ((1.4.0-beta4) The tiles of grid part's window in view (view: layer px) made first, before the rest of the window -
-- the client loads the oldest request first: what is seen comes before the window's margins, and a world's or a
-- continent's whole window (279 tiles of Azeroth's) never stands before what is seen of the pictures over it.)
-- Returns the budget left; nothing without a window, or with tiles laid out for another spec (FillGrid lays them again).
function TL.FillView(part, L, view, budget)
    local w, S = part.win, part.spec
    if not w or not view or budget <= 0 or w[1] > w[3] or w[2] > w[4] then return budget end
    -- ((1.4.0-beta14) its window whole and as it was: nothing to do - a frame of motion walked every tile of every picture)
    if part.doneGen == part.winGen and not part.pending and part.laidKey == S.key then return budget end
    if part.laidKey ~= S.key then
        if next(part.items) then return budget end
        part.laidKey = S.key
    end
    local a0, b0, a1, b1 = Snap(view, 0, L)
    for r = max(w[2], b0), min(w[4], b1) do
        for c = max(w[1], a0), min(w[3], a1) do
            local out
            budget, out = FillTile(part, L, S, c, r, budget)
            if out then
                part.pending = true
                return budget
            end
        end
    end
    return budget
end

-- Bring grid part's textures to its window (budget: new SetTexture calls it may make); returns the budget left.
-- part.pending: tiles of the window still waiting for budget. ((1.4.0-beta4) view: its tiles in view first - FillView)
function TL.FillGrid(part, L, budget, view)
    local w, S = part.win, part.spec
    local relay = part.laidKey ~= S.key
    if w and not relay and not part.pending and part.doneGen == part.winGen then return budget end
    for key, list in pairs(part.items) do
        local c, r = (key - 1) % L.cols + 1, floor((key - 1) / L.cols) + 1
        if relay and list.on == false then
            Free(part, list)
            part.items[key] = nil
        elseif not w or c < w[1] or c > w[3] or r < w[2] or r > w[4] then
            HideList(part, list)
        elseif relay then
            local it = GridItem(L, c, r, S.full)
            if it then EmitItem(part, it, list) end
        end
    end
    part.laidKey = S.key
    part.pending = false
    if not w then return budget end
    budget = TL.FillView(part, L, view, budget)
    if part.pending then return budget end
    for r = w[2], w[4] do
        for c = w[1], w[3] do
            local out
            budget, out = FillTile(part, L, S, c, r, budget, true)
            if out then
                part.pending = true
                return budget
            end
        end
    end
    part.doneGen = part.winGen
    return budget
end

-- The same for a part of listed items (the explored pieces): items P (TL.Pieces), the window of grid layout L.
function TL.FillList(part, L, P, budget, view)
    local w, S = part.win, part.spec
    local relay = part.laidKey ~= S.key
    if not relay and not part.pending and part.doneP == P and part.doneGen == part.winGen then return budget end
    local wait = false
    for key, list in pairs(part.items) do
        local it = P[key]
        if not it or (relay and list.on == false) then
            Free(part, list)
            part.items[key] = nil
        elseif not InWin(w, it[1], it[2], it[3], it[4], L) then
            HideList(part, list)
        else
            if list.on == false then
                -- ((1.4.0-beta14) as FillTile: those in view at once, the margin's at a frame's room)
                local inv = view and it[1] < view[3] and it[3] > view[1] and it[2] < view[4] and it[4] > view[2]
                if inv or TEST.noviewport or TL.now - (list.touchT or -1e9) >= TOUCH_EVERY then
                    if inv or TL.reshown < TL.SHOW_PER_FRAME then
                        TL.reshown = TL.reshown + #list
                        list.touchT = TL.now
                        part.sr = nil -- (the next TL.ShowIn hides it again)
                        ShowList(part, list)
                    else
                        wait = true
                    end
                end
            end
            if relay then EmitItem(part, it, list) end
        end
    end
    part.laidKey = S.key
    part.pending = wait
    if wait then return budget end
    for key, it in ipairs(P) do
        if not part.items[key] and InWin(w, it[1], it[2], it[3], it[4], L) then
            if budget < ITEM_MAX then
                part.pending = true
                return budget
            end
            local before = TL.newThisFrame
            local list = {}
            part.items[key] = list
            EmitItem(part, it, list)
            budget = budget - (TL.newThisFrame - before)
        end
    end
    part.doneP, part.doneGen = P, part.winGen
    return budget
end

---------------------------------------------------------------------------
-- Loading (1.4.0-beta2: docs/retail-engine.md 11.2 "Loaded means loaded")
---------------------------------------------------------------------------
-- (1.4.0-beta4, the in-game probes P1, P2 - docs/retail-engine.md 16) The load times, measured as the client loads: every
-- texture and mask given a file waits in `pend` until it has been visible and reports IsObjectLoaded - polled every frame
-- (TL.PollLoads, RetailRender.lua's Draw), as Blizzard's TextureLoadingGroup polls (MixinUtil.lua:302-335) - from its first
-- visible frame: the time and the frames by kind - "tile" (the client's own art, a fileDataID), "file" (the add-on's
-- files: the minimap imagery's pictures), "mask" (the add-on's masks) - every one of the session into a histogram (10 ms
-- and one frame a bucket), the largest with its file. 1.4.0-beta3's stamp kept the last 512 times at which the engine
-- first LOOKED at a texture (from LoadFade, ParentReady, Covers - not from its load): its 2.95 s was a look, not a load.
local KINDS = { "tile", "file", "mask" }
local LT = {}
for _, k in ipairs(KINDS) do LT[k] = { n = 0, hs = {}, hf = {}, maxS = 0, maxF = 0 } end
TL.loads = LT
local pend = {}
TL.pending = pend
-- (t: a texture or mask given a file; part: its part - or, (1.4.0-beta4's fixes) for the imagery's and the caves' textures,
-- frame: the frame it lies in, kind: "file" / "tile" / "mask" - its load measured from its first visible frame)
function TL.Watch(t, part, mask, frame, kind)
    t.ldPart, t.ldMask, t.ldV0, t.ldF0, t.ldFrame, t.ldKind = part, mask or nil, nil, nil, frame, kind
    pend[t] = true
end
-- (a texture or mask given back before it loaded: no longer measured)
function TL.Unwatch(t) pend[t] = nil end
local function KindOf(t)
    if t.ldMask then return "mask" end
    return type(t.file) == "string" and "file" or "tile"
end
-- (one load into the histograms: secs from its first visible frame, frames - draws - from it, its file)
function TL.RecordLoad(kind, secs, frames, file)
    local s = LT[kind]
    if not s then return end
    s.n = s.n + 1
    local bs, bf = math.min(1000, math.floor(secs * 100 + 0.5)), math.min(600, math.max(0, frames))
    s.hs[bs] = (s.hs[bs] or 0) + 1
    s.hf[bf] = (s.hf[bf] or 0) + 1
    if secs > s.maxS then s.maxS, s.maxFile = secs, file end
    if frames > s.maxF then s.maxF = frames end
end
-- ((1.4.0-beta4's fixes, probe P2) the textures visible SLOW_S or longer and not loaded: how many, the first file, how
-- many loaded later and how many still wait - a measurement only (nothing gives a texture up any more: TL.LoadState))
TL.slow = { textures = 0, later = 0, waiting = 0 }
local slowT = {}
-- (every frame: the textures waiting for their load that are visible now - their frame shown (f: the part's, or the
-- holder of the imagery's and the caves' - TL.Watch) and the texture itself)
function TL.PollLoads(now, tick)
    local waiting = 0
    for t in pairs(pend) do
        -- ((1.4.0-beta15) a part's: visible while the renderer has it placed - PlacePart's visAt; a tile hidden is no longer here, HideList.
        -- 1.4.0-beta14 asked the client twice a texture every frame, for this measurement alone)
        local fr = t.ldFrame
        local part = t.ldPart
        if not t.file and not t.ldMask then
            pend[t] = nil
        elseif (fr and fr:IsVisible()) or (not fr and part and part.visAt ~= nil) then
            if not t.ldV0 then t.ldV0, t.ldF0 = now, tick end
            if not t.IsObjectLoaded or t:IsObjectLoaded() then
                pend[t] = nil
                TL.RecordLoad(t.ldKind or KindOf(t), now - t.ldV0, tick - t.ldF0, t.ldMask and t.mfile or t.file)
                if slowT[t] then
                    slowT[t] = nil
                    TL.slow.later = TL.slow.later + 1
                end
            elseif now - t.ldV0 >= SLOW_S then
                if not slowT[t] then
                    slowT[t] = true
                    TL.slow.textures = TL.slow.textures + 1
                    TL.slow.first = TL.slow.first or (t.ldMask and t.mfile or t.file)
                end
                waiting = waiting + 1
            end
        else
            t.ldV0, t.ldF0 = nil, nil -- (hidden before it loaded: measured again from its next visible frame)
        end
    end
    TL.slow.waiting = waiting
end
-- (count, median, 95th percentile and max of one kind's histogram: seconds, frames)
local function Q(h, n, q)
    local want, acc = math.max(1, math.ceil(q * n)), 0
    local keys = {}
    for b in pairs(h) do keys[#keys + 1] = b end
    table.sort(keys)
    for _, b in ipairs(keys) do
        acc = acc + h[b]
        if acc >= want then return b end
    end
    return 0
end
function TL.LoadStats(kind)
    local s = LT[kind]
    if not s or s.n == 0 then return { count = 0 } end
    return { count = s.n, medianS = Q(s.hs, s.n, 0.5) / 100, p95S = Q(s.hs, s.n, 0.95) / 100, maxS = math.floor(s.maxS * 1000 + 0.5) / 1000,
        medianF = Q(s.hf, s.n, 0.5), p95F = Q(s.hf, s.n, 0.95), maxF = s.maxF, maxFile = s.maxFile }
end
function TL.LoadCount()
    local n = 0
    for _, k in ipairs(KINDS) do n = n + LT[k].n end
    return n
end

-- The part's state in view (layer px x0, y0, x1, y1; nil: all of it): "ok" - its textures there and its mask loaded
-- (confirmed), "wait" - loading. A part not shown waits: the client loads nothing that is not visible. (1.4.0-beta4) Its
-- mask is waited for as any texture - WoW Forever's LoadFade (Render.lua:1312-1315); 1.4.0-beta2's MASK_GIVEUP guarded
-- what the client never did: the player's saved file, maskSlow 0 all session. ((1.4.0-beta4's fixes) And no texture is
-- given up: 1.4.0-beta2's "gave" - not loaded LOAD_GIVEUP after its first visible frame, counted as there - went with the
-- other nets; the stamp's load.slow measures what it guarded.)
-- (/emap test noload - RetailWhy.lua: every texture set counts as loaded, IsObjectLoaded is not asked)
function TL.LoadState(part, now, view)
    if part.pending or not part.win then return "wait" end -- (its window not complete: not loaded)
    if TEST.noload then return "ok" end
    if part.n == 0 then return "ok" end -- (its window holds no tile - its mask leaves them out: nothing to wait for)
    if not part.visAt then return "wait" end
    local m = part.mask
    if m and m.IsObjectLoaded and not m:IsObjectLoaded() then return "wait" end
    for _, list in pairs(part.items) do
        for i = 1, (list.on ~= false) and #list or 0 do
            local t = list[i]
            if t.file and (not view or (t.qx0 < view[3] and t.qx1 > view[1] and t.qy0 < view[4] and t.qy1 > view[2])) then
                if t.IsObjectLoaded and not t:IsObjectLoaded() then return "wait" end
            end
        end
    end
    return "ok"
end

-- (the harness, RetailWhy.lua, Stats) loaded
function TL.Loaded(part, now, view) return TL.LoadState(part, now, view) == "ok" end

-- (1.4.0-beta4, G7 - the in-game probe P4) A part shown again after a hide: its textures with a file (in view, or all) and
-- how many of them the client reports not loaded now - those it let go while the part was hidden. RetailRender.lua then
-- waits for them at alpha 0 (its picture's load fade again) or shows on: by the client's answer, never by a timer.
function TL.Reshown(part, view)
    local n, missing = 0, 0
    if TEST.noload then return 0, 0 end
    for _, list in pairs(part.items) do
        for i = 1, (list.on ~= false) and #list or 0 do
            local t = list[i]
            if t.file and (not view or (t.qx0 < view[3] and t.qx1 > view[1] and t.qy0 < view[4] and t.qy1 > view[2])) then
                n = n + 1
                if t.IsObjectLoaded and not t:IsObjectLoaded() then missing = missing + 1 end
            end
        end
    end
    local m = part.mask
    if m and m.IsObjectLoaded and m.file then
        n = n + 1
        if not m:IsObjectLoaded() then missing = missing + 1 end
    end
    return n, missing
end

-- ((1.4.0-beta14) the textures of the part shown and not loaded: those a part shown now makes the client load)
function TL.NotLoaded(part)
    if TEST.noload then return 0 end
    local n = 0
    for _, list in pairs(part.items) do
        for i = 1, (list.on ~= false) and #list or 0 do
            local t = list[i]
            if t.file and t.IsObjectLoaded and not t:IsObjectLoaded() then n = n + 1 end
        end
    end
    return n
end

-- Every texture of the part back to its pool (no file); the window forgotten.
function TL.Release(part)
    for key, list in pairs(part.items) do
        Free(part, list)
        part.items[key] = nil
    end
    part.win, part.laidKey, part.pending, part.loadedAt, part.inView = nil, nil, nil, nil, 0
    part.doneGen, part.doneP = nil, nil
end

-- A mask texture of the part (made once): file, laid by RetailRender.lua; its SetTexture answer (true / false / nil).
-- (Laid with CLAMP: a land mask lies exactly over its picture; 1.4.0-beta2 - a globe's or portal's circle is the add-on's
-- own Masks/Retail/circle.tga, whose edge texels are transparent, so CLAMP spreads nothing beyond it: no clipping frame.)
function TL.Mask(part, file)
    local m = part.maskTex
    if not m then
        m = part.f:CreateMaskTexture()
        part.maskTex = m
    end
    if m.file ~= file then
        local ok = m:SetTexture(file, CLAMP, CLAMP, FILTER)
        m.file = file
        m.answer = nil
        m.setAt = TL.now
        TL.newThisFrame = TL.newThisFrame + 1 -- (1.4.0-beta2: a mask's file counts against the frame's SetTexture budget too)
        if type(ok) == "boolean" then m.answer = ok end
        m.mfile = file
        TL.Watch(m, part, true) -- ((1.4.0-beta4, probe P1) its load measured as a mask's)
    end
    return m
end

-- (the harness and RetailRender.lua's stats) the textures with a file in part
function TL.Count(part) return part.n end
-- (Stats) the texture objects made and not holding a file now: the parts' idle pools
function TL.Idle() return TL.made - TL.live end
