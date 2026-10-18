local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)

--[[
Boss and entrance markers on the dungeon view's FLOOR pages (1.0.0; data: DungeonBossData.lua, made by tools/bosses/make_data.py).
Blizzard blocks every position API inside instances, so the map shows WHERE the bosses and the entrance are instead:

  * a boss: Blizzard's raid-target skull (Interface\TargetingFrame\UI-RaidTargetingIcon_8, file 137008) on a dark disc
    (WhiteCircle-RaidBlips, the level links' disc) in a thin gold ring (GarrMission_EncounterBar-PortraitRing: the
    encounter-journal look Blizzard drew on these very maps in Cataclysm), and its number - the game's encounter order
    (DungeonEncounter OrderIndex, counted per wing) - in gold on a small dark badge at its lower right. Optional / rare /
    summoned encounters: silver ring, grey skull, no number. Approximate spots (q = 1): no ring, 70% alpha.
  * the entrance: Blizzard's dungeon / raid entrance swirl (Interface\Minimap\Dungeon, file 1502543; ...\Raid, 1502548) on
    a faint dark disc - drawn ON the entrance swirl printed in the art where the art has one within 40 yd (a).
  * a boss the game has told us is defeated (BOSS_KILL / ENCOUNTER_END success this session, or the instance lock):
    skull greyed, number grey, a green check (groupfinder-icon-greencheckmark).
Hover: 1.2x, our tooltip (Dungeon.lua ShowTip), the interact cursor. Click: a boss - zoom in about it; the entrance - the
entrance cave / the entrance map the dungeon was opened from (Dungeon.lua decides). The bar's skull button: the whole
list on hover (bosses without a position too), click = /unroll bosses.

Art (verified in the LOCAL client 1.60.1.70124: UiTextureAtlasMember 897532 / UiTextureAtlas 897470 decoded, files present
locally - the boss research's atlas_scan_all.json, path_check.json): WhiteCircle-RaidBlips (member 6220, atlas 867, file
1523129), GarrMission_EncounterBar-PortraitRing (2474, atlas 152, file 952657), groupfinder-icon-greencheckmark (3373,
atlas 236, file 985877); files 137008, 1502543, 1502548 present. NOT usable (file 1121272 Interface\Minimap\ObjectIconsAtlas
is not installed): DungeonSkull, Dungeon, Raid, Map-MarkedDefeated, poi-door-*; nor the encounter journal's own
UI-EncounterJournalTextures (522972, not installed). Missing atlases degrade: no disc / ring / check; skull, number and
swirl are plain files.
(A file of its own, like DungeonLinks.lua: Dungeon.lua's chunk stays far from Lua 5.1's 200-local limit.)
]]

local B = {}
ns.Bosses = B

local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local SWIRL = { dungeon = "Interface\\Minimap\\Dungeon", raid = "Interface\\Minimap\\Raid" }
local DISC, RING, CHECK = "WhiteCircle-RaidBlips", "GarrMission_EncounterBar-PortraitRing", "groupfinder-icon-greencheckmark"
local S_DISC, S_RING, S_SKULL = 20, 26, 13     -- px at fit (x the icon scale: zoom ^ 0.25, as the portal icons)
local S_NUM, NUM_DX, NUM_DY = 11, 8, 7         -- the number (font px) and its offset from the centre
local S_SWIRL = 26
local HIT = 22                                 -- px square that takes hover / click (at fit)
local GROW = 1.2                               -- hovered
local APPROX_A = 0.7
local RAID = { [249] = true, [309] = true, [409] = true, [469] = true, [509] = true, [531] = true, [533] = true }

local P = { items = {}, n = 0, pool = {}, epool = {}, hot = nil, dirty = true, art = nil, killed = {}, shown = true }

local function HasAtlas(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end

local function Art()
    if P.art == nil then P.art = { disc = HasAtlas(DISC), ring = HasAtlas(RING), check = HasAtlas(CHECK) } end
    return P.art
end

-- api (Dungeon.lua): parent = the icon frame (fades with the floor cross-fades); isRaid(id)
function B:Setup(parent, api)
    P.parent, P.api = parent, api or {}
end

local function Tex(layer, sub)
    local t = P.parent:CreateTexture(nil, layer or "OVERLAY", nil, sub)
    t:Hide()
    return t
end

local function NewBoss()
    local art = Art()
    local m = { kind = "boss" }
    m.disc = Tex("OVERLAY", 1)
    if art.disc then m.disc:SetAtlas(DISC, false) else m.disc = nil end
    m.ring = Tex("OVERLAY", 2)
    if art.ring then m.ring:SetAtlas(RING, false) else m.ring = nil end
    m.skull = Tex("OVERLAY", 3)
    m.skull:SetTexture(SKULL)
    m.badge = Tex("OVERLAY", 4)
    if art.disc then m.badge:SetAtlas(DISC, false) else m.badge = nil end
    m.num = P.parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if m.num.SetDrawLayer then m.num:SetDrawLayer("OVERLAY", 5) end
    m.num:Hide()
    m.check = Tex("OVERLAY", 6)
    if art.check then m.check:SetAtlas(CHECK, false) else m.check = nil end
    return m
end

local function NewEntrance()
    local m = { kind = "entrance" }
    m.disc = Tex("OVERLAY", 1)
    if Art().disc then m.disc:SetAtlas(DISC, false) else m.disc = nil end
    m.swirl = Tex("OVERLAY", 3)
    return m
end

local PARTS = { "disc", "ring", "skull", "badge", "num", "check", "swirl" }

local function ShowAll(m, on)
    for _, key in ipairs(PARTS) do
        local r = m[key]
        if r then r:SetShown(on) end
    end
end

local function Killed(dun, b) return P.killed[b.e] == true end

local Visible

-- Colours / art of a marker for its state (normal, hot, optional, approximate, defeated).
local function Paint(m)
    local it = m.item
    if m.kind == "entrance" then
        m.swirl:SetTexture(RAID[it.dun] and SWIRL.raid or SWIRL.dungeon)
        if m.disc then m.disc:SetVertexColor(0.02, 0.02, 0.03, 0.55) end
        m.swirl:SetVertexColor(1, 1, 1, 1)
    else
        local b = it.b
        local a = (b.q == 1) and APPROX_A or 1
        local dead = Killed(it.dun, b)
        local grey = b.opt or dead
        if m.disc then m.disc:SetVertexColor(0.06, 0.05, 0.04, 0.82 * a) end
        if m.ring then
            if m.ring.SetDesaturated then m.ring:SetDesaturated(b.opt and true or false) end
            local c = b.opt and 0.75 or 1
            m.ring:SetVertexColor(c, c, c, a)
        end
        if m.skull.SetDesaturated then m.skull:SetDesaturated(grey and true or false) end
        local c = grey and 0.82 or 1
        m.skull:SetVertexColor(c, c, c, a * (dead and 0.55 or 1))
        if b.o then
            m.num:SetText(tostring(b.o))
            if dead then m.num:SetTextColor(0.7, 0.7, 0.7) else m.num:SetTextColor(1, 0.82, 0) end
            m.num:SetAlpha(a)
            if m.badge then m.badge:SetVertexColor(0.06, 0.05, 0.04, 0.85 * a) end
        end
    end
    m.size = nil
    P.dirty = true
    if m.on then Visible(m, true) end -- (a kill shows the check; the rest keeps its state)
end

-- The markers of a page (a floor of a dungeon: its bosses on that floor and its entrances there), or none.
function B:SetPage(page)
    P.hot = nil
    local n = 0
    local dun = page and page.kind == "floor" and page.dun
    local fl = page and page.floor
    if P.parent and dun and P.shown then
        for _, e in ipairs(ns.DUNGEON_ENTRANCE_PINS and ns.DUNGEON_ENTRANCE_PINS[dun] or {}) do
            if e.f == fl and type(e.u) == "number" then
                n = n + 1
                local u, v = e.u, e.v
                if e.a then u, v = e.a[1], e.a[2] end
                P.items[n] = { kind = "entrance", dun = dun, e = e, u = u, v = v }
            end
        end
        for _, b in ipairs(ns.DUNGEON_BOSSES and ns.DUNGEON_BOSSES[dun] or {}) do
            if b.f == fl and type(b.u) == "number" then
                n = n + 1
                P.items[n] = { kind = "boss", dun = dun, b = b, u = b.u, v = b.v }
            end
        end
    end
    for i = n + 1, P.n do P.items[i] = nil end
    P.n = n
    -- (markers from two pools: entrances first, then bosses - a boss draws over an entrance it touches)
    local nb, ne = 0, 0
    for i = 1, n do
        local it = P.items[i]
        local m
        if it.kind == "entrance" then
            ne = ne + 1
            m = P.epool[ne] or NewEntrance()
            P.epool[ne] = m
        else
            nb = nb + 1
            m = P.pool[nb] or NewBoss()
            P.pool[nb] = m
        end
        it.m, m.item, m.x, m.px, m.on = m, it, nil, nil, false
        ShowAll(m, false)
        Paint(m)
    end
    if ns.Where and ns.Where.Relabel then ns.Where:Relabel() end -- (the room's label keeps clear of the new markers)
    for i = nb + 1, #P.pool do P.pool[i].item = nil ShowAll(P.pool[i], false) P.pool[i].on = false end
    for i = ne + 1, #P.epool do P.epool[i].item = nil ShowAll(P.epool[i], false) P.epool[i].on = false end
    P.dirty = true
end

function B:Count() return P.n end

-- (Whereabouts.lua) The lit room's label centred at view (px, py), half width / height (hw, hh): the nearest height at
-- which it covers no marker - just above or just under the markers in its way (the room's name stays near its cell, the
-- markers stay readable and hoverable). Radius: the unhovered hit square (no jump on hover).
local function Covers(px, y, hw, hh)
    for i = 1, P.n do
        local m = P.items[i].m
        if m.on and m.px then
            local r = HIT / 2 * (m.size or 1) / (m == P.hot and GROW or 1)
            if math.abs(m.px - px) < hw + r and math.abs(m.py - y) < hh + r then return true end
        end
    end
    return false
end

function B:Clear(px, py, hw, hh)
    if not Covers(px, py, hw, hh) then return py end
    local best
    for i = 1, P.n do
        local m = P.items[i].m
        if m.on and m.px and math.abs(m.px - px) < hw + HIT then
            local r = HIT / 2 * (m.size or 1) / (m == P.hot and GROW or 1)
            for _, y in ipairs({ m.py - r - hh - 1, m.py + r + hh + 1 }) do
                if (not best or math.abs(y - py) < math.abs(best - py)) and not Covers(px, y, hw, hh) then best = y end
            end
        end
    end
    return best or py
end

local function Size(m, k)
    local s = k * (m == P.hot and GROW or 1)
    if m.size == s then return end
    m.size = s
    if m.kind == "entrance" then
        m.swirl:SetSize(S_SWIRL * s, S_SWIRL * s)
        if m.disc then m.disc:SetSize(S_SWIRL * 0.8 * s, S_SWIRL * 0.8 * s) end
        return
    end
    if m.disc then m.disc:SetSize(S_DISC * s, S_DISC * s) end
    if m.ring then m.ring:SetSize(S_RING * s, S_RING * s * 61 / 64) end
    m.skull:SetSize(S_SKULL * s, S_SKULL * s)
    local b = m.item.b
    if b.o then
        local path = m.num:GetFont()
        m.num:SetFont(path or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", math.floor(S_NUM * s + 0.5), "OUTLINE")
        if m.badge then m.badge:SetSize((S_NUM + 2 + (b.o >= 10 and 5 or 0)) * s, (S_NUM + 2) * s) end
    end
    if m.check then m.check:SetSize(11 * s, 13 * s) end
end

local function Anchor(m, px, py, s)
    local p = P.parent
    if m.kind == "entrance" then
        m.swirl:SetPoint("CENTER", p, "TOPLEFT", px, -py)
        if m.disc then m.disc:SetPoint("CENTER", p, "TOPLEFT", px, -py) end
        return
    end
    m.skull:SetPoint("CENTER", p, "TOPLEFT", px, -py)
    if m.disc then m.disc:SetPoint("CENTER", p, "TOPLEFT", px, -py) end
    if m.ring then m.ring:SetPoint("CENTER", p, "TOPLEFT", px, -py) end
    if m.item.b.o then
        m.num:SetPoint("CENTER", p, "TOPLEFT", px + NUM_DX * s, -(py + NUM_DY * s))
        if m.badge then m.badge:SetPoint("CENTER", p, "TOPLEFT", px + NUM_DX * s, -(py + NUM_DY * s)) end
    end
    if m.check then m.check:SetPoint("CENTER", p, "TOPLEFT", px - 7 * s, -(py + 7 * s)) end
end

Visible = function(m, on)
    if m.kind == "entrance" then
        m.swirl:SetShown(on)
        if m.disc then m.disc:SetShown(on) end
        return
    end
    local b = m.item.b
    if m.disc then m.disc:SetShown(on) end
    if m.ring then m.ring:SetShown(on and b.q ~= 1) end
    m.skull:SetShown(on)
    m.num:SetShown(on and b.o ~= nil)
    if m.badge then m.badge:SetShown(on and b.o ~= nil) end
    if m.check then m.check:SetShown(on and Killed(m.item.dun, b)) end
end

-- Every frame over the view (cheap: only when the view moved or a marker changed).
-- viewXY(u, v) -> view px, inArea(px, py), k = the icon scale (zoom ^ 0.25).
function B:Place(viewXY, inArea, k, moved)
    if not (moved or P.dirty) then return end
    P.dirty = false
    local relabel = P.n > 0 and ns.Where and ns.Where.Relabel
    for i = 1, P.n do
        local it = P.items[i]
        local m = it.m
        local px, py = viewXY(it.u, it.v)
        m.px, m.py = px, py
        local on = inArea(px, py)
        if on then
            Size(m, k)
            if m.x ~= px or m.y ~= py or m.k ~= m.size then
                Anchor(m, px, py, m.size)
                m.x, m.y, m.k = px, py, m.size
            end
        end
        if on ~= m.on then
            m.on = on
            Visible(m, on)
        end
    end
    if relabel and not moved then ns.Where:Relabel() end -- (a marker grew / appeared without the view moving)
end

-- The item under view point (mx, my): a HIT x HIT square (x k), the nearest; never under the bar.
function B:At(mx, my, k, barH)
    if P.n == 0 or not (mx and my) or my < (barH or 0) then return nil end
    local half = HIT / 2 * (k or 1)
    local best, bestD
    for i = 1, P.n do
        local m = P.items[i].m
        if m.on and m.px then
            local dx, dy = math.abs(mx - m.px), math.abs(my - m.py)
            if dx <= half and dy <= half and (not best or dx * dx + dy * dy < bestD) then
                best, bestD = P.items[i], dx * dx + dy * dy
            end
        end
    end
    return best
end

function B:SetHot(it)
    local want = it and it.m or nil
    if want == P.hot then return end
    local old = P.hot
    P.hot = want
    if old and old.item then Paint(old) end
    if want then Paint(want) end
end

-- Tooltip lines (Dungeon.lua ShowTip format). canGo: the entrance click leads somewhere (Dungeon.lua knows).
function B:Tip(it, canGo)
    local HINT = { 0.25, 1, 0.25 }
    if it.kind == "entrance" then
        local e = it.e
        local lines = { { e.n or "Entrance", 1, 1, 1, 13 }, { "Where you arrive - the portal out", 0.7, 0.7, 0.7, 11 } }
        if e.q == 1 then lines[#lines + 1] = { "Approximate location", 1, 0.6, 0.3, 11 } end
        if canGo then lines[#lines + 1] = { canGo, HINT[1], HINT[2], HINT[3], 11 } end
        return lines
    end
    local b = it.b
    local lines = { { (b.o and (b.o .. "  ") or "") .. b.n, 1, 1, 1, 13 } }
    if b.o then
        local total = 0
        for _, x in ipairs(ns.DUNGEON_BOSSES[it.dun]) do
            if x.o and x.o > total and B:SameWing(it.dun, x, b) then total = x.o end
        end
        lines[#lines + 1] = { ("Boss %d of %d"):format(b.o, total), 0.7, 0.7, 0.7, 11 }
    elseif b.opt then
        lines[#lines + 1] = { "Optional (rare or summoned)", 0.7, 0.7, 0.7, 11 }
    end
    if b.aka then lines[#lines + 1] = { "Guides call it " .. b.aka, 0.7, 0.7, 0.7, 11 } end
    if b.q == 1 then lines[#lines + 1] = { "Approximate location", 1, 0.6, 0.3, 11 } end
    if b.oa then lines[#lines + 1] = { "Beyond the part of the cave this map draws", 1, 0.6, 0.3, 11 } end
    if Killed(it.dun, b) then
        lines[#lines + 1] = { (DUNGEON_ENCOUNTER_DEFEATED ~= nil and tostring(DUNGEON_ENCOUNTER_DEFEATED)) or "Defeated", 1, 0.125, 0.125, 11 }
    end
    lines[#lines + 1] = { "Click to zoom in here", HINT[1], HINT[2], HINT[3], 11 }
    return lines
end

-- (wings: Dungeon.lua's WingsOf, passed in by Setup as api.wingOf(dun, floor) -> wing index or 0)
function B:SameWing(dun, a, b)
    local w = P.api.wingOf
    if not w then return true end
    return w(dun, a.f) == w(dun, b.f)
end

-- The bar button's tooltip: every boss of the dungeon (placed or not), in order.
function B:ListTip(dun, title)
    local list = ns.DUNGEON_BOSSES and ns.DUNGEON_BOSSES[dun]
    if not list then return nil end
    local lines = { { (title or "") .. " - bosses", 1, 1, 1, 13 } }
    for _, b in ipairs(list) do
        local tag = b.o and (b.o .. "  ") or "-   "
        local note = ""
        if type(b.u) ~= "number" then note = b.opt and "  (rare, no position)" or "  (no position)"
        elseif b.opt then note = "  (optional)"
        elseif b.q == 1 then note = "  (approximate)" end
        local dead = Killed(dun, b)
        local c = (type(b.u) ~= "number" or dead) and 0.6 or 0.95
        lines[#lines + 1] = { tag .. b.n .. note, c, dead and 0.6 or 0.85, dead and 0.6 or 0.55, 11 }
    end
    lines[#lines + 1] = { "Numbers: the game's encounter order", 0.7, 0.7, 0.7, 11 }
    lines[#lines + 1] = { P.shown and "Click to hide the boss markers" or "Click to show the boss markers", 0.25, 1, 0.25, 11 }
    return lines
end

function B:HasList(dun) return ns.DUNGEON_BOSSES ~= nil and ns.DUNGEON_BOSSES[dun] ~= nil end

function B:NumberedCount(dun)
    local n = 0
    for _, b in ipairs(ns.DUNGEON_BOSSES and ns.DUNGEON_BOSSES[dun] or {}) do if b.o then n = n + 1 end end
    return n
end

-- /unroll bosses (ns.db.bosses): markers on / off; the page shown picks its markers again (Dungeon.lua calls SetPage).
function B:SetShown(on) P.shown = on and true or false end
function B:Shown() return P.shown end

-- Defeated: BOSS_KILL (encounterID) / ENCOUNTER_END (success == 1) this session, and the instance lock while inside
-- (GetInstanceLockTimeRemainingEncounter(i): name, texture, isKilled - InstanceDocumentation.lua; matched by the
-- enUS name, so on other locales only the events count).
function B:OnEncounter(encounterID)
    if type(encounterID) == "number" and not (issecretvalue and issecretvalue(encounterID)) then
        P.killed[encounterID] = true
        for i = 1, P.n do if P.items[i].m then Paint(P.items[i].m) end end
        P.dirty = true
    end
end

function B:ReadLock(dun)
    if not (GetInstanceLockTimeRemaining and GetInstanceLockTimeRemainingEncounter and ns.DUNGEON_BOSSES[dun]) then return end
    local ok, _, _, total = pcall(GetInstanceLockTimeRemaining)
    if not ok or type(total) ~= "number" or (issecretvalue and issecretvalue(total)) then return end
    local byName = {}
    for _, b in ipairs(ns.DUNGEON_BOSSES[dun]) do byName[b.n] = b.e end
    for i = 1, math.min(total, 40) do
        local ok2, name, _, isKilled = pcall(GetInstanceLockTimeRemainingEncounter, i)
        if ok2 and type(name) == "string" and not (issecretvalue and (issecretvalue(name) or issecretvalue(isKilled)))
            and isKilled == true and byName[name] then P.killed[byName[name]] = true end
    end
end

-- Entering the world (a new instance, a reset): forget the session's kills, read the lock of the instance the player is in.
function B:ResetKills(dun)
    P.killed = {}
    if dun then B:ReadLock(dun) end
    for i = 1, P.n do if P.items[i].m then Paint(P.items[i].m) end end
end

-- (review) INSTANCE_LOCK_START / INSTANCE_LOCK_WARNING (EncounterInfoDocumentation.lua:68 / :80): the game has the lock's
-- encounters now (Blizzard's lock dialog reads them then - GameDialogDefs.lua INSTANCE_LOCK) - read them again; this only
-- ever adds kills.
function B:OnLock(dun)
    if not dun then return end
    B:ReadLock(dun)
    for i = 1, P.n do if P.items[i].m then Paint(P.items[i].m) end end
end

function B:DebugText()
    if P.n == 0 then return "none" end
    local nb, ne = 0, 0
    for i = 1, P.n do if P.items[i].kind == "boss" then nb = nb + 1 else ne = ne + 1 end end
    return ("%d bosses, %d entrances%s"):format(nb, ne, P.hot and " (one hovered)" or "")
end
