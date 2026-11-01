--[[
Endless Map - RetailBench.lua (1.4.0-beta15; retail only: AzerothUnrolled_Standard.toc, before RetailTiles.lua)

What the map costs in the player's client - docs/retail-engine.md 24. The harness counts calls; only the client knows what they cost.

ns.Perf, always on with the map open (and 10 s after it closes - the game without the map): every frame's time from the client's own
elapsed - never the time between two draws, 1.4.0-beta14's load.hitch counted the pauses between two moves as long frames - by what the
frame did: closed, at rest, moving; the add-on's own parts of it (Perf.Add: draw, labels, sync, setMap) and the longest frames, each with what
it did. In the saved stamp: EndlessMapDB.retailChecks.load.frames, .parts, .hitches.

/emap bench: the map flies itself over a fixed path, about a minute and a half; the same path with what 1.4.0-beta15 changed put back one at a
time, so the difference is the client's own answer on the player's machine (retailChecks.bench; a line in the chat). And how much one texture
costs each way, under the Cosmic map where nothing of it is seen. Nothing else in the add-on depends on this file.
]]
local ADDON, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)
if ns.FLAVOR ~= "retail" then return end

local fmt = string.format
local floor = math.floor

---------------------------------------------------------------------------
-- A frame-time histogram (1 ms a bucket)
---------------------------------------------------------------------------
local HIST_MAX = 400
local function NewHist() return { n = 0, ms = 0, max = 0, h = {} } end
local function HistAdd(H, ms)
    H.n, H.ms = H.n + 1, H.ms + ms
    if ms > H.max then H.max = ms end
    local b = floor(ms)
    if b > HIST_MAX then b = HIST_MAX end
    H.h[b] = (H.h[b] or 0) + 1
end
local function HistQ(H, q)
    local want, acc = math.max(1, math.ceil(q * H.n)), 0
    for b = 0, HIST_MAX do
        acc = acc + (H.h[b] or 0)
        if acc >= want then return b end
    end
    return HIST_MAX
end
local function HistRow(H)
    if H.n == 0 then return { n = 0 } end
    return { n = H.n, mean = floor(H.ms / H.n * 10 + 0.5) / 10, p50 = HistQ(H, 0.5), p95 = HistQ(H, 0.95), p99 = HistQ(H, 0.99), max = floor(H.max + 0.5) }
end

---------------------------------------------------------------------------
-- ns.Perf
---------------------------------------------------------------------------
local P = {}
ns.Perf = P
local KEYS = { "draw", "labels", "sync", "setMap" }
local parts = {}                       -- [key] = the session's { n, ms, max }
local cur = { flips = 0, maps = 0, moved = false } -- this frame's
for _, k in ipairs(KEYS) do
    parts[k] = { n = 0, ms = 0, max = 0 }
    cur[k] = 0
end
local frames = { closed = NewHist(), rest = NewHist(), moving = NewHist() }
local HITCH_MS, HITCH_KEEP = 40, 12
local hitches = {}                     -- the longest frames: { ms, text }
P.lastMs = 0

-- (ms of this frame spent in key - draw, labels, sync, setMap)
function P.Add(key, ms)
    cur[key] = cur[key] + ms
    if key == "draw" then cur.moved = true end
    local t = parts[key]
    t.n, t.ms = t.n + 1, t.ms + ms
    if ms > t.max then t.max = ms end
end
function P.Flip() cur.flips = cur.flips + 1 end -- (the layers moved between Blizzard's canvas and its container: Core.lua HostLayers)
function P.Map() cur.maps = cur.maps + 1 end    -- (a SetMapID the add-on made)

local B -- (the bench, below: it takes the frames while it runs)
local tickF = CreateFrame("Frame")
tickF:Hide()
local function Hitch(ms, state)
    local keep = #hitches >= HITCH_KEEP and hitches[#hitches][1] or 0
    if ms < HITCH_MS or ms <= keep then return end
    local R = ns.Render
    local nw, ns2, drawn = 0, 0, 0
    if R and R.FrameCounts then nw, ns2, drawn = R:FrameCounts() end
    local map = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    hitches[#hitches + 1] = { ms, fmt("%d ms %s: draw %.1f, labels %.1f, canvas %.1f, map switches %d (%.1f ms), layers moved %d, new %d, newly shown %d, drawn %d, map %s",
        floor(ms + 0.5), state, cur.draw, cur.labels, cur.sync, cur.maps, cur.setMap, cur.flips, nw, ns2, drawn, tostring(map)) }
    table.sort(hitches, function(a, b) return a[1] > b[1] end)
    hitches[HITCH_KEEP + 1] = nil
end
tickF:SetScript("OnUpdate", function(_, elapsed)
    local ms = (elapsed or 0) * 1000
    P.lastMs = ms
    local shown = WorldMapFrame and WorldMapFrame:IsShown()
    local state = not shown and "closed" or (cur.moved and "moving") or "rest"
    if not (B and B.running) or B.record then
        if state == "moving" and ns.Render and ns.Render.FrameTime then ns.Render:FrameTime(ms) end
        if not (B and B.running) then
            HistAdd(frames[state], ms)
            Hitch(ms, state)
        end
    end
    if B and B.running then B.Frame(ms, state, cur) end
    for i = 1, #KEYS do cur[KEYS[i]] = 0 end
    cur.flips, cur.maps, cur.moved = 0, 0, false
    if not shown and not (B and B.running) and GetTime() >= (P.stopAt or 0) then
        tickF:Hide()
        -- ((1.4.0-beta16) the stamp was written as the map closed, before these frames: the saved file never held them)
        if ns.Render and ns.Render.StampNow then ns.Render:StampNow() end
    end
end)
function P.Start()
    if WorldMapFrame and not P.hooked then
        P.hooked = true
        WorldMapFrame:HookScript("OnShow", function() tickF:Show() end)
        WorldMapFrame:HookScript("OnHide", function()
            -- (10 s of the game without the map: what the map's own frames compare with)
            P.stopAt = GetTime() + 10
            tickF:Show()
        end)
        if WorldMapFrame:IsShown() then tickF:Show() end
    end
end

-- (RetailRender.lua's stamp)
function P.Report()
    local out = { frames = {}, parts = {}, hitches = {} }
    for k, H in pairs(frames) do out.frames[k] = HistRow(H) end
    for k, t in pairs(parts) do
        if t.n > 0 then out.parts[k] = { n = t.n, mean = floor(t.ms / t.n * 100 + 0.5) / 100, max = floor(t.max * 10 + 0.5) / 10, total = floor(t.ms) } end
    end
    for i, h in ipairs(hitches) do out.hitches[i] = h[2] end
    return out
end

---------------------------------------------------------------------------
-- /emap bench
---------------------------------------------------------------------------
B = {}
ns.RetailBench = B

-- (the canvas Blizzard keeps behind ours: what is shown there - frames, textures, its pins by template)
local function Canvas()
    local child = WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
    if not (child and child.GetChildren) then return nil end
    local nf, nt = 0, 0
    local ours = {}
    local core = ns.Core and ns.Core.Diag and ns.Core.Diag()
    if core then ours[core.overlay or 0], ours[core.cityLayer or 0], ours[core.labelLayer or 0] = true, true, true end
    local function Walk(f)
        if ours[f] or not f:IsShown() then return 0 end
        nf = nf + 1
        local n = 0
        for _, r in ipairs({ f:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") and r:IsShown() then n = n + 1 end
        end
        for _, c in ipairs({ f:GetChildren() }) do n = n + Walk(c) end
        return n
    end
    local byT, list = {}, {}
    for _, c in ipairs({ child:GetChildren() }) do
        local n = Walk(c)
        nt = nt + n
        local k = c.pinTemplate or (c.SetMapAndLayer and "detail layer") or "other"
        local a = c:GetAlpha() == 0 and " (alpha 0)" or ""
        byT[k .. a] = (byT[k .. a] or 0) + n
    end
    for k, n in pairs(byT) do list[#list + 1] = { k, n } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    local rows = {}
    for i = 1, math.min(8, #list) do rows[i] = list[i][1] .. " " .. list[i][2] end
    return fmt("%d frames, %d textures: %s", nf, nt, table.concat(rows, ", "))
end

---------------------------------------------------------------------------
-- What a texture costs (under the Cosmic map: nothing of it is seen)
---------------------------------------------------------------------------
local TEX_N = 600
local tf, tmask, ttex, tlabels
local function TexFiles(n)
    local out, seen = {}, {}
    for _, id in ipairs({ 947, 12, 13, 113, 424, 1978, 619, 875, 876, 2274 }) do
        local L = ns.RetailTiles.Layout(id)
        for _, f in ipairs(L and L.files or {}) do
            if f and f ~= 0 and not seen[f] then
                seen[f] = true
                out[#out + 1] = f
                if #out >= n then return out end
            end
        end
    end
    return out
end
local function TexSetup()
    if tf then return end
    local ov = ns.Render:Overlay()
    tf = CreateFrame("Frame", nil, ov)
    tf:SetSize(64, 64)
    tf:SetPoint("TOPLEFT", ov, "TOPLEFT", 8, -8)
    ns.SetLevelFixed(tf, 50) -- (under every stage, RetailRender.lua STAGE_BASE: the Cosmic map over it)
    tmask = tf:CreateMaskTexture()
    tmask:SetTexture("Interface\\AddOns\\AzerothUnrolled\\Masks\\Retail\\soft.tga", "CLAMP", "CLAMP", "TRILINEAR")
    tmask:SetAllPoints(tf)
    ttex = {}
    for i, file in ipairs(TexFiles(TEX_N)) do
        local t = tf:CreateTexture(nil, "ARTWORK")
        t:SetTexture(file, "CLAMP", "CLAMP", "TRILINEAR")
        t:SetSize(4, 4)
        t:SetPoint("TOPLEFT", tf, "TOPLEFT", ((i - 1) % 16) * 4, -floor((i - 1) / 16) * 1)
        ttex[i] = t
    end
    tlabels = {}
    for i = 1, 60 do
        local s = tf:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        s:SetText("Endless Map")
        s:SetPoint("CENTER", tf, "TOPLEFT", (i % 8) * 8, -(i % 8) * 8)
        tlabels[i] = s
    end
end
local TEX_STEPS = {
    { key = "none", show = false, labels = false },
    { key = "drawn", show = true },
    { key = "drawn, masked", show = true, mask = true },
    { key = "off the view", show = true, off = true },
    { key = "moved each frame", show = true, move = true },
    { key = "moved each frame, masked", show = true, mask = true, move = true },
    { key = "moved each frame, off the view", show = true, off = true, move = true },
    { key = "hidden, moved each frame", show = false, move = true },
    { key = "none again", show = false },
    { key = "names, moved each frame", show = false, labels = true, move = true },
}
local function TexApply(s)
    tf:Show()
    local masked = s.mask == true
    for _, t in ipairs(ttex) do
        t:SetShown(s.show == true)
        if (t.benchMask or false) ~= masked then
            if masked then t:AddMaskTexture(tmask) else t:RemoveMaskTexture(tmask) end
            t.benchMask = masked
        end
    end
    for _, l in ipairs(tlabels) do l:SetShown(s.labels == true) end
    tf.benchX = s.off and -4000 or 8
    tf:SetPoint("TOPLEFT", ns.Render:Overlay(), "TOPLEFT", tf.benchX, -8)
end

---------------------------------------------------------------------------
-- The path and the variants
---------------------------------------------------------------------------
local function ViewOf(id, z)
    local e = ns.maps and ns.maps[id]
    local world = ns.maps and ns.maps[ns.WORLD_MAP_ID]
    local _, v = ns.Core.Cam()
    if not (e and world and v) then return nil end
    return { e.cx, e.cy, ns.WidthForZoom(v, world, z) }
end
local PATH = { { 947, 1.2 }, { 1978, 5.49 }, { 2022, 14 }, { 2023, 14 }, { 2022, 40 }, { 13, 5.49 }, { 37, 14 }, { 947, 1.2 } }
local VARIANTS = {
    { key = "warm", warm = true },
    { key = "now" },
    { key = "as 1.4.0-beta14's tiles", test = "noviewport" },
    { key = "Blizzard's art under ours", test = "blizzart" },
    { key = "Blizzard's pins not following", test = "nolive" },
    { key = "now again" },
}

local function SetVariant(V)
    local TEST = ns.retailTest
    TEST.noviewport, TEST.blizzart, TEST.nolive = nil, nil, nil
    if V and V.test then TEST[V.test] = true end
    if ns.Render.LookAgainAll then ns.Render:LookAgainAll() end
end

local function Say(s) print("|cff33ccffEndless Map|r: " .. s) end

local function Finish(why)
    B.running = false
    B.record = false
    SetVariant(nil)
    if tf then tf:Hide() end
    if B.results and ns.retailStamp then
        B.results.at = time and time() or nil
        B.results.why = why
        ns.retailStamp.bench = B.results
    end
    if why then
        Say("bench stopped: " .. why)
    else
        local R = B.results
        local function M(k) return tostring(R.flights[k] and R.flights[k].mean or "?") end
        Say(fmt("bench done, ms a frame: the game alone %s, map at rest %s, map moving %s (with 1.4.0-beta14's tiles %s, Blizzard's art under ours %s, its pins not following %s). /reload saves the numbers.",
            tostring(R.closed and R.closed.mean or "?"), tostring(R.rest and R.rest.mean or "?"), M("now"), M("as 1.4.0-beta14's tiles"), M("Blizzard's art under ours"), M("Blizzard's pins not following")))
    end
    if B.startCam and WorldMapFrame:IsShown() and ns.Core.FlyToView then
        ns.Core.FlyToView(B.startCam[1], B.startCam[2], B.startCam[3])
    end
    if not WorldMapFrame:IsShown() then P.stopAt = GetTime() + 1 end
end

-- ((one step at a time, each with its frames) a small machine on the frame tick: wait, record, flight)
local step
local function Rec() return { H = NewHist(), draw = 0, labels = 0, sync = 0, setMap = 0, maps = 0, flips = 0, g0 = collectgarbage("count"), gar = 0, shown = 0, drawn = 0, samples = 0 } end
local function RecAdd(r, ms, c)
    HistAdd(r.H, ms)
    r.draw, r.labels, r.sync, r.setMap = r.draw + c.draw, r.labels + c.labels, r.sync + c.sync, r.setMap + c.setMap
    r.maps, r.flips = r.maps + c.maps, r.flips + c.flips
    local g = collectgarbage("count")
    if g > r.g0 then r.gar = r.gar + (g - r.g0) end
    r.g0 = g
end
local function RecRow(r)
    local row = HistRow(r.H)
    local n = math.max(1, r.H.n)
    row.drawMs, row.labelsMs, row.canvasMs = floor(r.draw / n * 100 + 0.5) / 100, floor(r.labels / n * 100 + 0.5) / 100, floor(r.sync / n * 100 + 0.5) / 100
    row.maps, row.mapMs = r.maps, r.maps > 0 and floor(r.setMap / r.maps * 10 + 0.5) / 10 or 0
    row.flips = r.flips
    row.garbageKB = floor(r.gar / n * 10 + 0.5) / 10
    if r.samples > 0 then row.shown, row.drawn = floor(r.shown / r.samples + 0.5), floor(r.drawn / r.samples + 0.5) end
    local AP = C_AddOnProfiler
    if AP and AP.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric then
        local ok, m = pcall(AP.GetAddOnMetric, ADDON, Enum.AddOnProfilerMetric.RecentAverageTime)
        if ok and type(m) == "number" then row.profilerMs = floor(m * 100 + 0.5) / 100 end
    end
    return row
end

local function Steps()
    local list = {}
    local function Add(s) list[#list + 1] = s end
    -- the game alone
    if not WorldMapFrame:IsShown() then
        Add({ t = 4, rec = function(R, r) R.closed = HistRow(r.H) end, say = "bench: measuring the game without the map, 4 seconds - keep it closed" })
        Add({ open = true, say = "bench: open the map now (M)" })
        Add({ t = 2 })
    end
    Add({ fn = function()
        local cam = ns.Core.Cam()
        B.startCam = { cam.x, cam.y, cam.vw }
        B.results.canvas0 = Canvas()
    end })
    -- the map at rest
    Add({ fly = { 1978, 5.49 }, say = "bench: the map flies by itself for about a minute - leave it open" })
    Add({ t = 1.5 })
    Add({ fn = function() B.results.canvas = Canvas() end })
    Add({ t = 3, rec = function(R, r) R.rest = HistRow(r.H) end })
    -- what a texture costs
    Add({ fn = TexSetup })
    Add({ fn = function() TexApply(TEX_STEPS[2]) end })
    -- (their files loaded: at most 5 s)
    Add({ t = 5, done = function()
        for _, t in ipairs(ttex) do
            if t.IsObjectLoaded and not t:IsObjectLoaded() then return false end
        end
        return true
    end })
    for _, s in ipairs(TEX_STEPS) do
        Add({ fn = function()
            TexApply(s)
            B.moveTex = s.move
        end })
        Add({ t = 0.3 })
        Add({ t = 1.2, raw = true, rec = function(R, r)
            table.sort(r.raw)
            R.tex[s.key] = floor((r.raw[math.ceil(#r.raw / 2)] or 0) * 100 + 0.5) / 100
        end })
    end
    Add({ fn = function()
        tf:Hide()
        B.moveTex = nil
        -- (a texture's cost in microseconds a frame, over the frames with none; a name's over the same)
        local R = B.results
        local none = ((R.tex["none"] or 0) + (R.tex["none again"] or 0)) / 2
        R.texUs = {}
        for _, s in ipairs(TEX_STEPS) do
            if s.show or s.labels or s.move then
                local n = s.labels and #tlabels or math.max(#ttex, 1)
                R.texUs[s.key] = floor(((R.tex[s.key] or 0) - none) / n * 1000 * 10 + 0.5) / 10
            end
        end
    end })
    -- the path, each variant
    for _, V in ipairs(VARIANTS) do
        Add({ fn = function() SetVariant(V) end })
        Add({ t = 0.5 })
        local r
        Add({ fn = function()
            r = Rec()
            B.flightRec = r
        end })
        for _, p in ipairs(PATH) do
            Add({ fly = p })
            Add({ t = 0.4 })
        end
        Add({ fn = function()
            B.flightRec = nil
            if not V.warm then B.results.flights[V.key] = RecRow(r) end
        end })
    end
    return list
end

function B.Frame(ms, state, c)
    if B.flightRec then
        RecAdd(B.flightRec, ms, c)
        if ns.Render.Counts2 then
            local shown, drawn = ns.Render:Counts2()
            B.flightRec.shown, B.flightRec.drawn, B.flightRec.samples = B.flightRec.shown + shown, B.flightRec.drawn + drawn, B.flightRec.samples + 1
        end
    end
    if B.moveTex and tf then
        B.moveFlip = not B.moveFlip
        tf:SetPoint("TOPLEFT", ns.Render:Overlay(), "TOPLEFT", tf.benchX + (B.moveFlip and 1 or 0), -8)
    end
    if not WorldMapFrame:IsShown() and not B.preOpen then return Finish("the map was closed") end
    if InCombatLockdown() then return Finish("combat started") end
    local now = GetTime()
    while true do
        if not step then
            B.i = B.i + 1
            step = B.list[B.i]
            if not step then return Finish(nil) end
            if step.say then Say(step.say) end
            step.t0 = now
            if step.rec then
                step.r = NewHist()
                step.raw = step.raw and {} or nil
            end
            if step.fly then
                -- (a map this character cannot see: the next step)
                local view = ViewOf(step.fly[1], step.fly[2])
                if view and ns.Core.FlyToView(view[1], view[2], view[3]) then
                    step.flyT = now
                else
                    step = { fn = function() end }
                end
            end
        end
        if step.fn then
            step.fn()
            step = nil
        elseif step.open then
            if WorldMapFrame:IsShown() then
                step = nil
                B.preOpen = false
            elseif now - step.t0 > 30 then
                return Finish("the map was not opened")
            else
                return
            end
        elseif step.fly then
            local st = ns.Core.State()
            if (st == "rest" or st == "hold" or st == "off") and now - step.flyT > 0.1 or now - step.flyT > 8 then
                step = nil
            else
                return
            end
        else
            if step.r then
                HistAdd(step.r, ms)
                if step.raw then step.raw[#step.raw + 1] = ms end
            end
            if now - step.t0 >= step.t or (step.done and step.done()) then
                if step.rec then step.rec(B.results, { H = step.r, raw = step.raw }) end
                step = nil
            else
                return
            end
        end
    end
end

function B.Slash(_, Print)
    if B.running then
        Finish("asked to stop")
        return
    end
    if InCombatLockdown() then
        Print("bench: not in combat")
        return
    end
    if not (ns.Core and ns.Core.FlyToView and ns.db and ns.Render) then
        Print("bench: open the map once first")
        return
    end
    P.Start()
    B.results = { tex = {}, flights = {} }
    B.i, step = 0, nil
    B.preOpen = not WorldMapFrame:IsShown()
    B.list = Steps()
    B.running = true
    tickF:Show()
end

-- (tests)
B.T = { VARIANTS = VARIANTS, TEX_STEPS = TEX_STEPS, Steps = Steps, frames = frames, parts = parts, hitches = hitches, Canvas = Canvas, TEX_N = TEX_N }
