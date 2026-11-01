--[[
Endless Map - RetailWhy.lua (1.4.0-beta2; retail only: AzerothUnrolled_Standard.toc, its last file)

In-game diagnostics of the retail engine, so that one /reload in the player's game tells what the map shows and why.
(1.4.0-beta1 in game: between the Cosmic map and a zone the map was black but for the add-on's names - "the black is a
huge deadzone where nothing is loaded" - while every harness check passed: what the client does with the pictures is
what the harness cannot see.)
  * /emap why (also /endlessmap why): a short report in chat - asked for, so printed - of the view now: the engine's
    state, Blizzard's map and the one the settle would take (and whether QuestSafe lets it), the canvas, the art layer,
    how much of the view the client says is covered, and for the six largest stages planned there their host, picture
    parts, textures (with a file / visible / IsObjectLoaded true / masked) and mask, or why a stage is not shown
    (off screen, switched off, waiting for its textures, the budget, covered, faded). The same, fuller (each part's
    frame, a sample texture's file and rect as the client lays it out), goes silently into EndlessMapDB.retailWhy:
    the last 3, each with its time and zoom.
  * A silent automatic snapshot: when the camera rests with the map open (Core's rest or hold, the view unchanged a
    second, nothing drawing - (1.4.0-beta4's fixes) or STILL_BUSY seconds with the map still loading: nothing is given up,
    so a view that never loads stays busy, and that is the view to look at) and less than 90% of the view is covered by
    art the client confirms - Blizzard's canvas
    (shown, opaque, its map's picture there), or a texture of ours the client reports visible, loaded, at alpha 0.5 or
    more, inside its rect and its clipping frames, unmasked (the client tells nothing of a mask's shape), in a part frame
    of some size (WoW Forever's Render.lua, proven in game, sizes every part frame to its picture; 1.4.0-beta2's do too -
    RetailTiles.lua TL.SetSpec) - one snapshot goes to EndlessMapDB.retailWhy.auto: at most one every 10 s, the
    last 5, one per resting view. No chat line.
  * /emap test nomask | noclip | noload | nofade | canvas | off: switches for this session only (never saved,
    a /reload clears them), each toggled with one line in chat, to bisect in the player's game what hides the art: nomask
    no mask texture on any picture (RetailTiles.lua Lay); noclip no clipping frame - the insets' hosts, Core's art layer
    and city layer; noload a picture shows as soon as its textures are set, IsObjectLoaded not asked (RetailTiles.lua
    LoadState); nofade no load or transition fade, a drawn picture at alpha 1 at once (RetailRender.lua); canvas
    Blizzard's canvas never hidden (Core.lua UpdateCanvasAlpha); off all of them back. (1.4.0-beta2: the size switch
    went - every part frame has its picture's size now; 1.4.0-beta4: nofloor went with Blizzard's map as the floor.)
  * (1.4.0-beta4, the in-game probes - docs/retail-engine.md 16) /emap why's "loads" line: the load times by kind, every
    texture's from its first visible frame (tiles, the add-on's files, masks: count, median, 95th percentile, max and its
    file; the minimap imagery's and the caves' too since 1.4.0-beta4's fixes), the slow textures - visible a second or
    more before they loaded, how many loaded later, how many still wait (nothing is given up any more) -, the heavy frames
    (1,100 or more textures drawn) and the longest frame time after one, the parts shown again by how long they were
    hidden and how many of their textures the client had let go - the same in EndlessMapDB.retailChecks.load, .reshow
    (and .releaseUITextures, the client's setting, .partyWait, a bubble's longest wait for the first view); a stage's mask
    line says whether its MaskTexture reports IsObjectLoaded (true, false or nil).
Reads only, but for the switches; the snapshots look at the map while it is open (RetailRender.lua's Draw starts them).
]]
local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)
if ns.FLAVOR ~= "retail" then return end

local TEST = ns.retailTest -- (RetailTiles.lua: the switches RetailTiles.lua, RetailRender.lua and Core.lua read)
if type(TEST) ~= "table" then return end

local W = {}
ns.RetailWhy = W

local fmt = string.format
local floor, min, max = math.floor, math.min, math.max

local KEEP_WHY, KEEP_AUTO = 3, 5
local AUTO_GAP = 10          -- at most one silent snapshot in this many seconds
local AUTO_COVER = 0.9       -- a silent snapshot when less of the view than this is covered
local POLL, STILL = 0.5, 1   -- the open map looked at every POLL s; at rest: the view unchanged STILL s, nothing drawing
local STILL_BUSY = 2         -- ((1.4.0-beta4's fixes) ... or this long still loading - a diagnostic's wait, nothing drawn changes)
local GX, GY = 12, 8         -- the view's points the coverage is counted on
local CHAT_STAGES, SAVED_STAGES = 6, 12
local PARTS = { "base", "top" } -- (a picture's parts, RetailRender.lua: its art, its explored pieces)
local SWITCHES = { "nomask", "noclip", "noload", "nofade", "canvas", "nolod", "noviewport", "blizzart", "livemap", "nolive", "autowhy" }
local SAYS = {
    nomask = "no mask texture on any picture (land masks, globe circles)",
    noclip = "no clipping frame (the insets' hosts, the art layer, the city layer)",
    noload = "pictures show as soon as their textures are set, without waiting for IsObjectLoaded",
    nofade = "no load or transition fade: a drawn picture at alpha 1 at once",
    canvas = "Blizzard's map canvas never hidden",
    nolod = "no zone's small picture: its tiles at every zoom",
    noviewport = "every tile round the view shown, as 1.4.0-beta14, and every world's and continent's whole picture",
    blizzart = "Blizzard's map art and explored pieces kept under ours, as 1.4.0-beta14",
    livemap = "Blizzard's map switches in the middle of a motion, as 1.4.0-beta14",
    nolive = "Blizzard's canvas does not follow a motion: its pins hidden until the map stops",
    autowhy = "a silent snapshot of each view that rests not covered, kept in the saved file",
}

---------------------------------------------------------------------------
-- Asking the client
---------------------------------------------------------------------------
local function Plain(x)
    if issecretvalue and issecretvalue(x) then return nil end
    return x
end

-- o:m(...) when the client has that method: its first four answers (an error or a secret value is no answer)
local function Ask(o, m, ...)
    local fn = o and o[m]
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, o, ...)
    if not ok then return nil end
    return Plain(a), Plain(b), Plain(c), Plain(d)
end

local function F2(x) return type(x) == "number" and fmt("%.2f", x) or "?" end
local function F0(x) return type(x) == "number" and fmt("%d", floor(x + 0.5)) or "?" end
local function Pct(x) return F0((x or 0) * 100) .. "%" end

-- region r's rect on the screen (px: left, bottom, right, top) by the client's own layout; sf: the frame whose scale it
-- draws at (a texture's frame); nil when the client gives none
local function ScreenRect(r, sf)
    local l, b, w, h = Ask(r, "GetRect")
    if type(l) ~= "number" or type(b) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then return nil end
    local s = Ask(sf or r, "GetEffectiveScale") or 1
    return l * s, b * s, (l + w) * s, (b + h) * s
end

local function RectText(l, b, r, t)
    if not l then return "no rect" end
    return fmt("%s,%s %sx%s", F0(l), F0(b), F0(r - l), F0(t - b))
end

-- frame f in a few words: shown / visible, alpha (effective), level, size, clipping
local function FrameText(f)
    if not f then return "none" end
    local w, h = Ask(f, "GetSize")
    return fmt("%s%s a %s (eff %s) lvl %s %sx%s%s", f:IsShown() and "shown" or "hidden", Ask(f, "IsVisible") and " vis" or " NOT vis",
        F2(Ask(f, "GetAlpha")), F2(Ask(f, "GetEffectiveAlpha")), tostring(Ask(f, "GetFrameLevel")), F0(w), F0(h),
        Ask(f, "DoesClipChildren") and " clips" or "")
end

-- the textures of picture part p that have a file: how many, shown, visible, loaded (IsObjectLoaded), masked (the
-- client's count of their masks), and the first visible one
local function Survey(p)
    local o = { n = 0, shown = 0, vis = 0, loaded = 0, masked = 0 }
    if not p then return o end
    for _, list in pairs(p.items) do
        for i = 1, #list do
            local t = list[i]
            if t.file then
                o.n = o.n + 1
                if t:IsShown() then o.shown = o.shown + 1 end
                local vis = Ask(t, "IsVisible")
                if vis then o.vis = o.vis + 1 end
                if t.IsObjectLoaded == nil or Ask(t, "IsObjectLoaded") then o.loaded = o.loaded + 1 end
                local nm = Ask(t, "GetNumMaskTextures")
                if (nm or 0) > 0 or (nm == nil and t.maskRef) then o.masked = o.masked + 1 end
                if vis and not o.sample then o.sample = t end
            end
        end
    end
    return o
end

-- texture t of frame f as the client has it: its file, rect, alphas, layer, masks
local function TexText(t, f)
    if not t then return "no visible texture" end
    local _, _, _, va = Ask(t, "GetVertexColor")
    local layer, sub = Ask(t, "GetDrawLayer")
    return fmt("e.g. file %s (client %s) at %s a %s vertex %s %s/%s masks %s", tostring(t.file),
        tostring(Ask(t, "GetTextureFileID") or Ask(t, "GetTexture")), RectText(ScreenRect(t, f)), F2(Ask(t, "GetAlpha")), F2(va),
        tostring(layer), tostring(sub), tostring(Ask(t, "GetNumMaskTextures")))
end

-- the mask of stage st's picture (a continent's land, a globe's or portal's circle) as the client has it
local function MaskText(st)
    local m = st.base and st.base.maskTex
    if not m then return "no mask" end
    local w, h = Ask(m, "GetSize")
    local file = type(m.file) == "string" and (m.file:match("([^\\]+)$")) or tostring(m.file)
    return fmt("mask %s %sx%s shown %s loaded %s answer %s%s", tostring(file), F0(w), F0(h), tostring(m:IsShown()),
        tostring(Ask(m, "IsObjectLoaded")), tostring(m.answer), TEST.nomask and " (test nomask: not attached)" or "")
end

local function SwitchText()
    local on = {}
    for _, k in ipairs(SWITCHES) do if TEST[k] then on[#on + 1] = k end end
    return #on > 0 and table.concat(on, " ") or "none"
end

---------------------------------------------------------------------------
-- The view
---------------------------------------------------------------------------
-- the view's box in the camera's units (fractions of the Cosmic map), and the share of it entry e's picture takes
local function ViewBox(cam, v)
    local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)
    local hx, hy = v.W / 2 / ppx, v.H / 2 / ppy
    return cam.x - hx, cam.y - hy, cam.x + hx, cam.y + hy
end
local function AreaIn(e, x0, y0, x1, y1)
    local w = min(e.x1, x1) - max(e.x0, x0)
    local h = min(e.y1, y1) - max(e.y0, y0)
    if w <= 0 or h <= 0 then return 0 end
    return w * h / ((x1 - x0) * (y1 - y0))
end

local function In(list, x, y)
    for i = 1, #list do
        local q = list[i]
        if x >= q[1] and x <= q[3] and y >= q[2] and y <= q[4] then return true end
    end
    return false
end

-- The textures of the stages drawn last frame as the client lays them out, sorted: ok (visible, loaded, alpha 0.5 or
-- more, in their clipping frames, unmasked, in a part frame of some size), masked, unsized (as ok but in a frame of no
-- size) - screen rects
local function TexRects(order, tick)
    local ok, mk, un = {}, {}, {}
    for _, st in ipairs(order) do
        if st.drawn == tick then
            local clips = {}
            for _, c in ipairs({ st.host, st.host:GetParent() or false }) do
                if c and Ask(c, "DoesClipChildren") then
                    local l, b, r, t = ScreenRect(c)
                    clips[#clips + 1] = { l or 0, b or 0, r or 0, t or 0 }
                end
            end
            for _, pn in ipairs(PARTS) do
                local p = st[pn]
                local f = p and p.f
                if f and Ask(f, "IsVisible") then
                    local fa = Ask(f, "GetEffectiveAlpha") or 0
                    local fw, fh = Ask(f, "GetSize")
                    local sized = (fw or 0) > 0 and (fh or 0) > 0
                    for _, list in pairs(p.items) do
                        for i = 1, #list do
                            local t = list[i]
                            local a = fa * (Ask(t, "GetAlpha") or 1) * min(t.qa0 or 1, t.qa1 or t.qa0 or 1)
                            if t.file and a >= 0.5 and Ask(t, "IsVisible") and (t.IsObjectLoaded == nil or Ask(t, "IsObjectLoaded")) then
                                local l, b, r, top = ScreenRect(t, f)
                                if l then
                                    for _, c in ipairs(clips) do l, b, r, top = max(l, c[1]), max(b, c[2]), min(r, c[3]), min(top, c[4]) end
                                    if r > l and top > b then
                                        local nm = Ask(t, "GetNumMaskTextures")
                                        local into = ((nm or 0) > 0 and mk) or (sized and ok) or un
                                        into[#into + 1] = { l, b, r, top }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return ok, mk, un
end

-- How much of the view the client confirms covered (GX x GY points): under Blizzard's canvas (shown, opaque, its map's
-- picture there by the view it shows) or under one of our textures it confirms (TexRects ok). Of the rest: under a
-- masked texture only, under a texture of a part frame of no size only. { total, canvas, ours, masked, unsized } or nil.
local function Coverage(d, order, tick, v)
    local cl, cb, cr, ct = ScreenRect(d.container)
    if not cl or cr - cl < 1 or ct - cb < 1 then return nil end
    local cs = Ask(d.container, "GetEffectiveScale") or 1
    local child = d.container.Child
    local real = child and Ask(child, "IsVisible") and (Ask(child, "GetEffectiveAlpha") or 0) >= 0.99 and d.real or nil
    local rppx, rppy
    if real then rppx, rppy = ns.PixelsPerUnit(v, real.vw) end
    local ok, mk, un = TexRects(order, tick)
    local n, tot, can, ours, masked, unsized = GX * GY, 0, 0, 0, 0, 0
    for j = 1, GY do
        for i = 1, GX do
            local x, y = cl + (i - 0.5) / GX * (cr - cl), ct - (j - 0.5) / GY * (ct - cb)
            local c = false
            if real then
                local wx = real.x + ((x - cl) / cs - v.W / 2) / rppx
                local wy = real.y + ((ct - y) / cs - v.H / 2) / rppy
                local M = real.map
                c = wx >= M.x0 and wx <= M.x1 and wy >= M.y0 and wy <= M.y1
            end
            local o = In(ok, x, y)
            if c then can = can + 1 end
            if o then ours = ours + 1 end
            if c or o then tot = tot + 1
            elseif In(mk, x, y) then masked = masked + 1
            elseif In(un, x, y) then unsized = unsized + 1 end
        end
    end
    return { total = tot / n, canvas = can / n, ours = ours / n, masked = masked / n, unsized = unsized / n }
end

local function CoverText(cov)
    if not cov then return "coverage: the map has no rect" end
    return fmt("%s of the view covered (canvas %s, ours %s; not confirmed: masked %s, in frames of no size %s)", Pct(cov.total),
        Pct(cov.canvas), Pct(cov.ours), Pct(cov.masked), Pct(cov.unsized))
end

---------------------------------------------------------------------------
-- Stages
---------------------------------------------------------------------------
-- why stage st (planned last frame) is not drawn; b: its base part's survey. (1.4.0-beta2: a covered stage is drawn -
-- RetailRender.lua keeps the camera's chain under what covers it; a loading one is shown at alpha 0)
local function WhyNot(st, coverSt, b)
    if not st.onScreen then return "off screen" end
    if (st.planA or 0) <= 0.002 then
        if st.want then return fmt("loading ahead of its switch at alpha 0 (its own zoom %s; %d of %d loaded)", F2(st.zc), b.loaded, b.n) end
        return fmt("switched off (its own zoom %s)", F2(st.zc))
    end
    if not st.loadedAt then
        if st.base.pending then return fmt("the budget: its tiles wait for SetTexture (%d set)", b.n) end
        if b.n == 0 then return "no textures yet" end
        return fmt("waiting for its textures: %d of %d loaded (IsObjectLoaded)", b.loaded, b.n)
    end
    if (st.shownA or 0) <= 0.02 then return fmt("faded (planned %s, shown %s)", F2(st.planA), F2(st.shownA)) end
    return "not placed"
end

local function StageRec(st, tick, area, coverSt, d)
    local e = st.e
    local drawn = st.drawn == tick
    local r = { id = e.id, name = e.name, kind = e.kind, area = floor(area * 1000 + 0.5) / 1000, zoom = st.zc, planned = st.planA,
        shown = st.shownA, drawn = drawn, loaded = st.loadedAt ~= nil, hidden = st.covered or false,
        circle = st.d, open = st.open }
    local sv, brief = {}, {}
    r.parts = {}
    for _, pn in ipairs(PARTS) do
        local p = st[pn]
        if p then
            local s = Survey(p)
            sv[pn] = s
            local fw, fh = Ask(p.f, "GetSize")
            r.parts[pn] = fmt("%s scale %s at %s; %d textures: shown %d, visible %d, loaded %d, masked %d; %s", FrameText(p.f),
                F2(Ask(p.f, "GetScale")), RectText(ScreenRect(p.f)), s.n, s.shown, s.vis, s.loaded, s.masked, TexText(s.sample, p.f))
            if s.n > 0 or pn == "base" then
                brief[#brief + 1] = fmt("%s %s a %s: %d textures (shown %d, visible %d, loaded %d, masked %d) frame %sx%s", pn,
                    p.f:IsShown() and "shown" or "hidden", F2(Ask(p.f, "GetAlpha")), s.n, s.shown, s.vis, s.loaded, s.masked, F0(fw), F0(fh))
            end
        end
    end
    local head = fmt("%d %s (%s, %s of the view)", e.id, e.name, e.kind, Pct(area))
    if drawn then
        local hw, hh = Ask(st.host, "GetSize")
        -- ((1.4.0-beta4) placed at alpha 0 under the picture covering the view - rule 2)
        r.line = fmt("%s: drawn a %s%s%s | host %s%s a %s eff %s%s | %s | %s", head, F2(st.shownA),
            st.covered and fmt(" (covered by %s)", coverSt and (coverSt.e.id .. " " .. coverSt.e.name) or "?") or "",
            st.hid and " (at alpha 0 under its cover)" or "",
            st.host:IsShown() and "shown" or "hidden", Ask(st.host, "IsVisible") and " vis" or " NOT vis", F2(Ask(st.host, "GetAlpha")),
            F2(Ask(st.host, "GetEffectiveAlpha")), Ask(st.host, "DoesClipChildren") and fmt(" clips %sx%s", F0(hw), F0(hh)) or "",
            table.concat(brief, "; "), MaskText(st))
    else
        r.why = WhyNot(st, coverSt, sv.base)
        r.line = fmt("%s: not shown - %s", head, r.why)
    end
    local h = st.host
    r.host = fmt("%s in the %s at %s", FrameText(h), (h:GetParent() == d.cityLayer) and "city layer" or "art layer", RectText(ScreenRect(h)))
    r.mask = MaskText(st)
    return r
end

---------------------------------------------------------------------------
-- A snapshot of the view
---------------------------------------------------------------------------
-- how: "why" (asked: full - QuestSafe's answer too) or "auto". nil when there is no view.
local function Snapshot(how, full)
    local C, R = ns.Core, ns.Render
    if not (C and C.Diag and C.Cam and R and R.DebugStages) then return nil end
    local cam, v = C.Cam()
    if not (cam and v and v.W and v.W > 0 and v.H > 0) then return nil end
    local d = C.Diag(full)
    local order, _, F = R:DebugStages()
    local s = { how = how, t = GetTime(), state = C.State(), zoom = ns.WorldZoom(v, cam.vw), space = 1 / cam.vw,
        cam = fmt("%.5f %.5f %.7f", cam.x, cam.y, cam.vw), test = SwitchText() }
    if time then
        local ok, at = pcall(time)
        if ok then s.at = Plain(at) end
    end
    local id = WorldMapFrame:GetMapID()
    local M = ns.GetMap(id)
    s.map = fmt("%s %s%s", tostring(id), M and M.name or "(not in the tree)", d.holdsReal and "" or " - it cannot show this view")
    s.best = d.best and fmt("%d %s", d.best.id, d.best.name) or "none"
    if full then
        s.questSafe = d.best and tostring(d.questSafe) or "-"
        s.safe = d.safe and fmt("%d %s", d.safe.id, d.safe.name) or "none"
    end
    s.combat = (InCombatLockdown and InCombatLockdown()) and true or false
    s.mode = (d.live and "live: the canvas follows") or (d.detached and "detached: the canvas hidden once ours is ready")
        or "at rest in the canvas"
    s.holder = tostring(d.holder)
    s.canvas = FrameText(d.container.Child)
    s.container = fmt("%s at %s scale %s", FrameText(d.container), RectText(ScreenRect(d.container)), F2(Ask(d.container, "GetEffectiveScale")))
    local par = d.overlay:GetParent()
    s.overlay = fmt("%s %s at %s, strata %s", FrameText(d.overlay), (par == d.container.Child and "in the canvas") or (par == d.container and "beside the canvas")
        or "elsewhere", RectText(ScreenRect(d.overlay)), tostring(Ask(d.overlay, "GetFrameStrata")))
    s.city = FrameText(d.cityLayer)
    local cov = Coverage(d, order, F.tick, v)
    s.cover, s.coverN = CoverText(cov), cov and floor(cov.total * 1000 + 0.5) / 1000 or 0
    local S = R:Stats()
    s.stats = fmt("textures %d shown, %d live (peak %d), %d stages, %d loading, %d masks refused; ready %s", S.shown, S.live,
        S.peak or 0, S.stages, S.loading, S.maskFail, tostring(R:IsReady()))
    s.focus = fmt("zone %s, continent %s", tostring(R:GetFocus()), tostring(R:GetContinentFocus()))
    if R.LoadLine then s.loads = R:LoadLine() end -- ((1.4.0-beta4) the in-game probes P1, P2, P4)
    -- the stages planned last frame: the largest share of the view first, the higher drawn first among equals
    local x0, y0, x1, y1 = ViewBox(cam, v)
    local list, lastHidden = {}, 0
    for i, st in ipairs(order) do
        if st.covered then lastHidden = i end
        list[#list + 1] = { st = st, area = AreaIn(st.e, x0, y0, x1, y1), i = i }
    end
    local coverSt = order[lastHidden + 1]
    table.sort(list, function(a, b)
        if a.area ~= b.area then return a.area > b.area end
        return a.i > b.i
    end)
    s.planned = #order
    s.stages = {}
    for i = 1, min(#list, SAVED_STAGES) do s.stages[i] = StageRec(list[i].st, F.tick, list[i].area, coverSt, d) end
    return s
end

-- s kept in the saved table: the asked ones (the last KEEP_WHY), the silent ones in .auto (the last KEEP_AUTO)
local function Keep(s, auto)
    local db = _G[ns.SAVED] -- ((1.4.0-beta4) EndlessMapDB: OneCopy.lua)
    if type(db) ~= "table" then return 0 end
    local R = type(db.retailWhy) == "table" and db.retailWhy or {}
    db.retailWhy = R
    local list, keep = R, KEEP_WHY
    if auto then
        R.auto = type(R.auto) == "table" and R.auto or {}
        list, keep = R.auto, KEEP_AUTO
    end
    list[#list + 1] = s
    while #list > keep do table.remove(list, 1) end
    return #list
end

---------------------------------------------------------------------------
-- /emap why, /emap test
---------------------------------------------------------------------------
local function Why(Print)
    local C = ns.Core
    local st = C and C.State and C.State()
    if not st then
        Print("why: the map is not set up yet")
        return
    end
    if not WorldMapFrame:IsShown() then
        Print(fmt("why: the map is closed - open it where it looks wrong and type %s why there. Test switches: %s", ns.COMMAND, SwitchText()))
        return
    end
    if st == "off" then
        Print(fmt("why: the add-on stands aside here (map %s: no zoom path, or switched off) - Blizzard's map shows. Test switches: %s",
            tostring(WorldMapFrame:GetMapID()), SwitchText()))
        return
    end
    local ok, s = pcall(Snapshot, "why", true)
    if not ok or not s then
        Print("why: no view to describe" .. ((not ok) and (" (" .. tostring(s) .. ")") or ""))
        return
    end
    local kept = Keep(s, false)
    Print(fmt("why: %s, %s; Blizzard's map %s; the settle's pick %s (QuestSafe %s), it may switch to %s%s", s.state, s.mode, s.map,
        s.best, s.questSafe, s.safe, s.combat and "; in combat" or ""))
    Print(fmt("zoom %.2fx (space %.2fx); canvas %s; %s", s.zoom, s.space, s.canvas, s.cover))
    Print(fmt("art layer %s; city layer %s", s.overlay, s.city))
    Print(fmt("%s; focus %s; test switches: %s", s.stats, s.focus, s.test))
    if s.loads then Print(s.loads) end
    for i = 1, min(#s.stages, CHAT_STAGES) do Print(s.stages[i].line) end
    Print(fmt("kept in the saved settings: %s.retailWhy (%d of the last %d)", ns.SAVED, kept, KEEP_WHY))
end

-- a switch changed: the art layer's and city layer's clipping (noclip), the stages' (RetailRender.lua), a draw at rest
local function Apply()
    local C = ns.Core
    local d = C and C.Diag and C.Diag()
    if d then
        for _, f in ipairs({ d.overlay or false, d.cityLayer or false }) do
            if f then f:SetClipsChildren(not TEST.noclip) end
        end
    end
    if ns.Render and ns.Render.ApplyTest then ns.Render:ApplyTest() end
    if C and C.Redraw then C.Redraw() end
end

-- (Core.lua's slash handler) cmd "why" or "test", its argument, the chat printer
function W.Slash(cmd, arg, Print)
    if cmd == "why" then return Why(Print) end
    arg = (arg or ""):lower()
    if arg == "off" then
        for _, k in ipairs(SWITCHES) do TEST[k] = nil end
        Apply()
        Print("test switches all off: the map draws as it does normally")
    elseif SAYS[arg] then
        TEST[arg] = (not TEST[arg]) or nil
        Apply()
        Print(fmt("test %s %s: %s (this session only; %s test off clears them all)", arg, TEST[arg] and "on" or "off", SAYS[arg], ns.COMMAND))
    else
        Print(fmt("test switches on: %s - %s test %s | off", SwitchText(), ns.COMMAND, table.concat(SWITCHES, " | ")))
    end
end

---------------------------------------------------------------------------
-- The silent snapshots
---------------------------------------------------------------------------
local pollOn, seenKey, seenAt, doneKey, autoAt = false, nil, 0, nil, nil
local Poll

-- one look at the open map: at rest a second, nothing drawing, a view not looked at yet - and less than AUTO_COVER of it
-- covered: a snapshot (at most one every AUTO_GAP s)
local function Look(C, st)
    local cam, v = C.Cam()
    local key = fmt("%s %s %.6f %.6f %.8f", st, tostring(WorldMapFrame:GetMapID()), cam.x, cam.y, cam.vw)
    local now = GetTime()
    if key ~= seenKey then
        seenKey, seenAt = key, now
        return
    end
    if key == doneKey or now - seenAt < STILL or (autoAt and now - autoAt < AUTO_GAP) then return end
    local d = C.Diag()
    if d.busy and now - seenAt < STILL_BUSY then return end
    doneKey = key
    local order, _, F = ns.Render:DebugStages()
    local cov = Coverage(d, order, F.tick, v)
    if cov and cov.total < AUTO_COVER then
        local s = Snapshot("auto", false)
        if s then
            Keep(s, true)
            autoAt = now
        end
    end
end

Poll = function()
    local C = ns.Core
    local st = C and C.State and C.State()
    if not (st and st ~= "off" and WorldMapFrame:IsShown() and C.Diag) then
        pollOn, seenKey = false, nil
        return
    end
    C_Timer.After(POLL, Poll)
    if st ~= "rest" and st ~= "hold" then
        seenKey = nil
        return
    end
    pcall(Look, C, st)
end

-- (RetailRender.lua's Draw: the map is drawn) the looks run while the map is open
local cleaned = false
function W.Kick()
    -- ((1.4.0-beta16) the silent snapshots earlier versions left in the saved file: about 70 KB read at every login, for nothing)
    if not cleaned then
        cleaned = true
        local db = _G[ns.SAVED]
        if type(db) == "table" and type(db.retailWhy) == "table" and not TEST.autowhy then db.retailWhy.auto = nil end
    end
    -- ((1.4.0-beta15) only with /emap test autowhy: the silent snapshots found 1.4.0-beta2's black map. Every 10 s at rest they walked and wrote every stage of the view into the saved
    -- file - most views have under 90% "covered", the land masks never count -, each a frame's work and tables, for a question long answered. /emap why still answers at once)
    if pollOn or not TEST.autowhy then return end
    pollOn = true
    C_Timer.After(POLL, Poll)
end
