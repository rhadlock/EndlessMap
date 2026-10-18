local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)

--[[
Doors (1.0.0, WoW Forever only): the world-map side of the instances.

  * Placeholders: one icon for every instance Forever lists that is not in this
    client's files yet (ns.FOREVER_DOOR_HINTS, DungeonMapsMM.lua), at the best
    candidate point - a hollow grey diamond with a grey name, drawn after every
    other label, never a click target. Its tooltip says what is known (level
    range, dungeon or raid, "Not in the game files yet", "Location approximate"
    below high confidence, known bosses). /unroll doors hints hides / shows them.
  * Unconfirmed doors: a ns.FOREVER_DOORS row with conf = "medium" (City of
    Dalaran's sewer-pipe portal) - a normal icon that opens the map; its tooltip
    says the door is not confirmed yet.
  * Learned doors: outdoors (Eastern Kingdoms / Kalimdor) the addon keeps the
    player's last position, 4 times a second; when a loading screen takes the
    player into a dungeon or raid, that spot is an ENTRY sample of its door, and
    the first spot outdoors after leaving one an EXIT sample. A door is
    confirmed by an entry with another sample within 25 yd, or by an entry
    within 150 yd of a hint point (or whose instance is named like a hint).
    Rejected: logins and /reload, summons (a summon prompt in the last 120 s or
    one pending), the dungeon finder's teleports (GetInstanceInfo lfgDungeonID),
    samples taken dead or as a ghost, battlegrounds / arenas / scenarios, and
    stale samples (the last outdoor position older than 2 s when the loading
    screen starts). A confirmed door turns a placeholder or an unconfirmed icon
    into a confirmed one at that spot, or adds an icon for an instance without
    a row (Half-Pint Tavern); a built-in door of high confidence (every classic
    entrance, The Hall of Thanes, Ruins of Lordaeron, Excavation Site) is never
    moved - its samples are only listed. Saved account-wide in
    AzerothUnrolledDB.doors (at most 6 samples per instance); /unroll doors lists
    them, /unroll doors forget [instance ID] clears them.
  * "You are inside": inside an instance, the door icon of that instance on the
    world map carries the round player icon, pulsing, shown at every zoom, and
    its tooltip starts with "You are inside <name>"; a click opens the map of
    the instance the player is in, on the floor the game names, as it opens by
    itself inside (switch HERE_OPENS_INSTANCE off: the door's fixed page, as
    every other entrance icon). It marks the DOOR - the game
    gives addons no position inside instances (UnitPosition answers nothing
    there), so nothing here claims to show where the player is.

APIs (all in this client's Blizzard_APIDocumentationGenerated, every call under pcall, secret values refused before any
compare): UnitPosition (UnitDocumentation.lua:2714), IsInInstance / GetInstanceInfo (InstanceDocumentation.lua:170 /
:103, 8th return instanceID, 10th lfgDungeonID), UnitIsDeadOrGhost (UnitDocumentation.lua:1931),
C_SummonInfo.GetSummonConfirmTimeLeft (SummonInfoDocumentation.lua:37), GetServerTime (SystemTimeDocumentation.lua:30),
C_Map.GetMapPosFromWorldPos (as Labels.lua), events LOADING_SCREEN_ENABLED (LoadingScreenDocumentation.lua:23),
CONFIRM_SUMMON (UnitDocumentation.lua:3572), PLAYER_ENTERING_WORLD (isInitialLogin, isReloadingUi:
SystemDocumentation.lua:136), ZONE_CHANGED_NEW_AREA (MapDocumentation.lua:665). No SetMapID, nothing in combat
matters (nothing here is protected), and the recorder sleeps inside instances.
]]

local Doors = {}
ns.Doors = Doors

local POLL = 0.25          -- s between outdoor position samples
local MAX_AGE = 2.0        -- s: the last outdoor sample must be this fresh when the loading screen starts
local EXIT_WAIT = 5        -- s after arriving outdoors in which the first sample is the exit spot
local SUMMON_WINDOW = 120  -- s after a summon prompt in which an entry is not trusted
local PAIR_YD = 25         -- an entry and another sample this close: a door
local HINT_YD = 150        -- an entry this close to a hint point: that hint's door
local MAX_SAMPLES = 6      -- per instance (the oldest go first)
local PULSE = 1.2          -- s per pulse of the "you are inside" icon
local LOG_N = 6            -- recent recorder decisions kept for /unroll doors
-- Switch: a click on the "you are inside" door opens the instance's own map (its floors, on the floor the game names) instead
-- of the door's fixed page. Off: the door opens what it always opens (for a door with one dungeon that is the dungeon's
-- map; Blackrock Mountain's opens its entrance map) - nothing is picked from the player's whereabouts.
-- (review: on - "clicking opens the dungeon map"; the instance ID is the game's, not a guess, and only
-- the marked door follows it: inside Blackrock Depths the Blackrock Mountain door opens Blackrock Depths, inside Dire
-- Maul's Warpwood Quarter the Dire Maul door opens that floor)
local HERE_OPENS_INSTANCE = true

-- All module state in one table. (Doors.S: read by the test harness only.)
local S = {
    supported = false, merged = false, attached = false,
    last = nil,        -- the last outdoor sample { c, x, y, t, dead }
    snap = nil,        -- the last outdoor sample when the loading screen started
    tLoad = nil, summonT = nil,
    prev = nil,        -- the instance the player was in at the last PLAYER_ENTERING_WORLD (nil: outdoors)
    exitArm = nil,     -- { inst, t }: the next outdoor sample is that instance's exit spot
    insideId = nil,    -- the instance the player is in now (the "you are inside" door)
    slots = {},        -- every door Doors knows: sk = "row" (ns.FOREVER_DOORS), "ghost" (placeholder), "learned"
    builtin = {},      -- instance IDs whose door is built in and never moves (Merge)
    here = {},         -- the items marked "you are inside"
    log = {},          -- recent recorder decisions (text)
    pollT = 0, pulseT = 0,
}
Doors.S = S
Doors.HERE_OPENS_INSTANCE = HERE_OPENS_INSTANCE -- (Dungeon.lua reads it)

local function Supported()
    local build = (select(4, GetBuildInfo())) or 0
    return build >= 16000 and build < 20000 and type(ns.FOREVER_DOORS) == "table" and type(ns.INSTANCES) == "table"
end

local function Plain(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end

local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffEndless Map|r: " .. msg) end
end

local function Now()
    if not GetServerTime then return 0 end
    local ok, t = pcall(GetServerTime)
    return (ok and type(t) == "number" and Plain(t)) and t or 0
end

local function Dist(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function Log(text)
    local L = S.log
    L[#L + 1] = text
    while #L > LOG_N do table.remove(L, 1) end
end

-- The saved samples: AzerothUnrolledDB.doors[instanceID] = { n = name, k = "dungeon" | "raid", s = { sample, ... } },
-- sample = { c, x, y, k = "in" | "out", t = server time, b = client build }.
local function DB(create)
    local db = ns.db
    if not db then return end
    -- (review) anything but a table there (a broken or foreign SavedVariables file) is no list of doors: ignored, and
    -- replaced by an empty one when a sample is recorded - it must never stop the addon's Setup (Merge runs in it)
    if type(db.doors) ~= "table" then
        if not create then return end
        db.doors = {}
    end
    return db.doors
end

-- (review) a saved sample the addon can compute with (anything else in a saved file is skipped, never an error)
local function Good(s) return type(s) == "table" and type(s.c) == "number" and type(s.x) == "number" and type(s.y) == "number" end

---------------------------------------------------------------------------
-- What the game says
---------------------------------------------------------------------------
-- The player's world position OUTDOORS: continent map 0 / 1, north, west (plain numbers only).
local function Pos()
    if not UnitPosition then return end
    local ok, x, y, _, m = pcall(UnitPosition, "player")
    if not ok or type(x) ~= "number" or type(y) ~= "number" or type(m) ~= "number" then return end
    if issecretvalue and (issecretvalue(x) or issecretvalue(y) or issecretvalue(m)) then return end
    if m ~= 0 and m ~= 1 then return end
    return m, x, y
end

local function Dead()
    if not UnitIsDeadOrGhost then return false end
    local ok, d = pcall(UnitIsDeadOrGhost, "player")
    return ok and Plain(d) and d == true
end

local function SummonPending()
    if not (C_SummonInfo and C_SummonInfo.GetSummonConfirmTimeLeft) then return false end
    local ok, t = pcall(C_SummonInfo.GetSummonConfirmTimeLeft)
    return ok and type(t) == "number" and Plain(t) and t > 0
end

-- The instance the player is in: { id, name, typ, kind = "dungeon" | "raid", lfg } - nil outdoors.
local function Inside()
    if not (IsInInstance and GetInstanceInfo) then return end
    local ok, isIn = pcall(IsInInstance)
    if not ok or not Plain(isIn) or not isIn then return end
    local ok2, name, typ, _, _, _, _, _, id, _, lfg = pcall(GetInstanceInfo)
    if not ok2 or type(id) ~= "number" or not Plain(id) or id <= 0 then return end
    if not (type(name) == "string" and Plain(name) and name ~= "") then name = nil end
    if not (type(typ) == "string" and Plain(typ)) then typ = nil end
    local finder = type(lfg) == "number" and Plain(lfg) and lfg > 0
    return { id = id, name = name, typ = typ, kind = (typ == "raid") and "raid" or "dungeon", lfg = finder }
end

---------------------------------------------------------------------------
-- Doors, hints, slots
---------------------------------------------------------------------------
-- Instances whose door is built in and must never move (S.builtin, from Merge: every ns.DUNGEON_ENTRANCES target but the
-- medium rows).
local function Builtin(id) return S.builtin[id] == true end

local function SlotOf(id)
    for _, slot in ipairs(S.slots) do
        if slot.id == id and slot.sk ~= "learned" then return slot end
    end
end

-- The hint an entry sample of instance id is near (HINT_YD): hints for exactly that instance first; unknown-instance
-- hints (m = nil) only for an instance nothing else claims. (review) Of those, the one named like the instance (the
-- game's name) first, then the one with the nearest point - never simply the first in the list: Hyjal Summit's and
-- Barrow Deeps' points lie 136 yd apart. Second return: the hint is the instance's own (by ID or by name).
local function HintNear(id, a, name)
    local hints = ns.FOREVER_DOOR_HINTS or {}
    local own = false
    for _, h in ipairs(hints) do if h.m == id then own = true end end
    local low = type(name) == "string" and name:lower() or nil
    local best, bestK
    for _, h in ipairs(hints) do
        if (h.m == id or (h.m == nil and not own and not Builtin(id))) and h.c == a.c then
            local mine = h.m == id or (low ~= nil and type(h.n) == "string" and h.n:lower() == low)
            for _, p in ipairs(h.p or {}) do
                local dx, dy = a.x - p[1], a.y - p[2]
                local d2 = dx * dx + dy * dy
                local k = mine and d2 or d2 + 1e9
                if d2 <= HINT_YD * HINT_YD and (not bestK or k < bestK) then best, bestK = h, k end
            end
        end
    end
    return best, best ~= nil and bestK < 1e9
end

-- A learned door: the newest entry with another sample within PAIR_YD, or within HINT_YD of a hint (point, how).
local function Evaluate(id, rec)
    local list = type(rec) == "table" and rec.s
    if type(list) ~= "table" then return end
    for i = #list, 1, -1 do
        local a = list[i]
        if Good(a) and a.k == "in" then
            for j = #list, 1, -1 do
                local b = list[j]
                if j ~= i and Good(b) and b.c == a.c and Dist(a, b) <= PAIR_YD then return a, "pair" end
            end
            local h = HintNear(id, a, rec.n)
            if h then return a, h end
        end
    end
end

-- A placeholder slot named like the instance (the game's name for it), for a door confirmed by a pair.
local function SlotNamed(name)
    if type(name) ~= "string" then return end
    local n = name:lower()
    for _, slot in ipairs(S.slots) do
        if slot.sk == "ghost" and not slot.id and slot.name:lower() == n then return slot end
    end
end

-- The floor of instance id whose picture holds world point (x, y), else 1 (never an overview or a sub-zone-only floor:
-- DungeonMapsMM.lua ov / sz).
local function FloorAt(id, x, y)
    local dm = ns.DUNGEON_MAPS and ns.DUNGEON_MAPS[id]
    for i, f in ipairs(dm and dm.f or {}) do
        local r = f.r
        if r and not f.ov and not f.sz and x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] then return i end
    end
    return 1
end

local function Mapped(id) return id and ns.DUNGEON_MAPS and ns.DUNGEON_MAPS[id] ~= nil end

local function NewSlot(sk, t)
    t.sk = sk
    S.slots[#S.slots + 1] = t
    return t
end

local function GhostStyle(slot) return slot.rkind == "raid" and "ghostRaid" or "ghostDungeon" end

-- The entrance key and click target of a slot: a learned door whose instance has a map opens it.
local function Target(slot)
    local id = slot.lid or slot.id
    if slot.sk == "row" then return true end
    if slot.learned and Mapped(id) then
        ns.DUNGEON_ENTRANCES[slot.key] = ns.DUNGEON_ENTRANCES[slot.key] or { d = { id }, floor = FloorAt(id, slot.learned.x, slot.learned.y), learned = true }
        return true
    end
    return false
end

-- The row Labels.lua builds a slot's item from.
local function RowOf(slot)
    local p = slot.learned or slot.home
    local row = { p.c, p.x, p.y, slot.name, slot.rkind, slot.lo, slot.hi, zone = (not slot.learned) and slot.home.zone or nil,
        entrance = slot.key, door = slot }
    if slot.sk == "ghost" and not slot.learned then row.style = GhostStyle(slot) end
    row.noClick = not Target(slot)
    return row
end

-- Learned states from the saved samples: which slot each confirmed door belongs to (new "learned" slots for instances
-- without one). Returns the slots whose icon changes, and those newly confirmed.
local function Resolve()
    for _, slot in ipairs(S.slots) do slot.was, slot.learned, slot.lid, slot.nsamp = slot.learned, nil, nil, nil end
    -- (review) the confirmed doors first, then their slots: instances a slot belongs to by ID or by name before the
    -- others, then by instance ID - one slot per instance whatever order the saved table comes in; the hint a door is
    -- near picks the placeholder however the door was confirmed (by a pair, or by that hint)
    local todo = {}
    for id, rec in pairs(DB() or {}) do
        if type(id) == "number" and not Builtin(id) then
            local pt, how = Evaluate(id, rec)
            if pt then
                local h, mine = HintNear(id, pt, rec.n)
                todo[#todo + 1] = { id = id, rec = rec, pt = pt, pair = how == "pair", h = h, first = mine or SlotOf(id) ~= nil or SlotNamed(rec.n) ~= nil }
            end
        end
    end
    table.sort(todo, function(a, b) if a.first ~= b.first then return a.first end return a.id < b.id end)
    for _, t in ipairs(todo) do
        local id, rec, pt, h = t.id, t.rec, t.pt, t.h
        -- (the slot: the instance's own row / placeholder by ID, else the placeholder named like it - wherever it lies:
        -- the name is the game's -, else the placeholder of the hint its door is near; each only if no other instance
        -- holds it)
        local slot = SlotOf(id)
        if not slot then
            local named = SlotNamed(rec.n)
            if named and not named.lid then slot = named end
        end
        if not slot and h then
            for _, x in ipairs(S.slots) do if x.hint == h and x.sk == "ghost" and not x.lid then slot = x end end
        end
        -- (confirmed only by a hint whose placeholder another instance holds: no door)
        if not slot and not (h and not t.pair) then
            for _, x in ipairs(S.slots) do if x.sk == "learned" and x.id == id then slot = x end end
            if not slot then
                local nm = (type(rec.n) == "string" and rec.n ~= "") and rec.n or (h and h.n) or ("Instance " .. id)
                local kind = (rec.k == "raid" or rec.k == "dungeon") and rec.k or (h and h.kind) or "dungeon"
                slot = NewSlot("learned", { id = id, key = "learned:" .. id, name = nm, rkind = kind, home = { c = pt.c, x = pt.x, y = pt.y } })
            end
        end
        if slot then
            slot.learned = { c = pt.c, x = pt.x, y = pt.y }
            slot.lid, slot.nsamp, slot.how = id, #rec.s, t.pair and "pair" or h
        end
    end
    local changed, newly = {}, {}
    for _, slot in ipairs(S.slots) do
        local a, b = slot.was, slot.learned
        if (a == nil) ~= (b == nil) or (a and b and (a.x ~= b.x or a.y ~= b.y)) then changed[#changed + 1] = slot end
        if b and not a then newly[#newly + 1] = slot end
        slot.was = nil
    end
    return changed, newly
end

---------------------------------------------------------------------------
-- Icons (Labels.lua items)
---------------------------------------------------------------------------
local function Redraw()
    local C = ns.Core
    if not (C and WorldMapFrame and WorldMapFrame:IsShown()) then return end
    if ns.Dungeon and ns.Dungeon.IsActive and ns.Dungeon:IsActive() then return end
    if C.State() == "rest" then C.ResyncFromReal() end
end

-- A slot's icon as its state says: where (learned or its own point), how it looks, whether a click opens anything.
local function ApplySlot(slot)
    local L = ns.Labels
    local it = slot.item
    if not L then return end
    if not it then
        if not slot.learned then return end
        it = L:AddRow(RowOf(slot)) -- (a door learned mid-session for an instance without an icon)
        slot.item, slot.placed = it, slot.learned
        return
    end
    local p = slot.learned or slot.home
    if slot.placed ~= p then
        slot.placed = p
        L:MoveItem(it, p.c, p.x, p.y, (not slot.learned) and slot.home.zone or nil)
    end
    if slot.sk == "ghost" then L:SetStyle(it, slot.learned and slot.rkind or GhostStyle(slot)) end
    it.noClick = not Target(slot)
    it.off = (slot.sk == "learned" and not slot.learned) or nil
end

-- Mark the door(s) of instance id ("you are inside"); nil: none.
local function MarkHere(id)
    local L = ns.Labels
    for _, it in ipairs(S.here) do it.here = nil end
    wipe(S.here)
    if S.pulse then S.pulse:Hide() end
    if not (id and L and L.Items) then return end
    for _, it in ipairs(L:Items()) do
        local hit = false
        local slot = it.door
        if it.off then
            hit = false -- (a learned door forgotten)
        elseif slot and slot.sk then
            hit = (slot.lid or slot.id) == id
        elseif it.portal then
            hit = it.portal.m == id
        elseif it.entrance then
            local e = ns.DUNGEON_ENTRANCES and ns.DUNGEON_ENTRANCES[it.entrance]
            for _, d in ipairs(e and e.d or {}) do if d == id then hit = true end end
        end
        if hit then
            it.here = true
            S.here[#S.here + 1] = it
        end
    end
    if S.pulse then S.pulse:SetShown(#S.here > 0) end
end

function Doors:UpdateHere()
    local inst = Inside()
    local id = inst and inst.id
    S.insideId, S.insideName = id, inst and inst.name
    if not S.attached then return end
    local before = #S.here
    MarkHere(id)
    if before > 0 or #S.here > 0 then Redraw() end
end

-- The instance the player is in NOW (asked live: Dungeon.lua's click on the marked door opens its map).
function Doors:InsideId()
    local inst = Inside()
    return inst and inst.id
end

-- Re-read the saved doors and bring every icon up to date (a door learned or forgotten).
function Doors:Refresh(quiet)
    if not S.merged then return end
    local changed, newly = Resolve()
    if not S.attached then return end
    for _, slot in ipairs(S.slots) do ApplySlot(slot) end
    MarkHere(S.insideId)
    for _, slot in ipairs(newly) do
        if not quiet then Print(("learned the door of %s - its icon is on the world map now"):format(slot.name)) end
    end
    if #changed > 0 then Redraw() end
end

-- Core's Setup, before Labels:Build: the slots of the ns.FOREVER_DOORS rows DungeonMapsMM.lua added (their ns.INSTANCES
-- rows carry the slot to their items), the placeholders (ns.FOREVER_DOOR_HINTS whose instance has no row) and the doors
-- learned before. (Placeholders and learned doors are no ns.INSTANCES rows - that list stays the entrances: Attach adds
-- their items.)
function Doors:Merge()
    if S.merged or not S.supported then return end
    S.merged = true
    for _, d in ipairs(ns.INSTANCES) do
        local row = d.door
        if type(row) == "table" and row.label and not row.sk then
            local slot = NewSlot("row", { id = row.d, key = row.label, name = row.label, conf = row.conf, rkind = d[5] or "dungeon",
                row = row, home = { c = row.c, x = row.x, y = row.y, zone = row.zone } })
            slot.placed, d.door = slot.home, slot
        end
    end
    local medium = {}
    for _, slot in ipairs(S.slots) do if slot.conf == "medium" then medium[slot.id] = true end end
    for _, e in pairs(ns.DUNGEON_ENTRANCES or {}) do
        for _, id in ipairs(e.d or {}) do if not medium[id] then S.builtin[id] = true end end
    end
    for _, h in ipairs(ns.FOREVER_DOOR_HINTS or {}) do
        local p = h.p and h.p[1]
        if p and not (h.m and (SlotOf(h.m) or Builtin(h.m))) then
            local slot = NewSlot("ghost", { id = h.m, key = "hint:" .. h.n, name = h.n, conf = h.conf, rkind = h.kind or "dungeon",
                lo = h.lo, hi = h.hi, hint = h, home = { c = h.c, x = p[1], y = p[2], zone = h.zone } })
            slot.placed = slot.home
        end
    end
    Resolve()
end

-- Core's Setup, after Labels:Build: every slot's item (the placeholders' and learned doors' made now), learned positions
-- applied, the "you are inside" door marked.
function Doors:Attach()
    if S.attached or not S.merged then return end
    local L = ns.Labels
    if not (L and L.Items and L.AddRow) then return end
    for _, it in ipairs(L:Items()) do
        local slot = it.door
        if slot and slot.sk and not slot.item then slot.item = it end
    end
    for _, slot in ipairs(S.slots) do
        if not slot.item and (slot.sk == "ghost" or slot.learned) then
            slot.placed = (slot.sk == "ghost") and slot.home or slot.learned
            slot.item = L:AddRow(RowOf(slot))
        end
    end
    S.attached = true
    S.pulse = CreateFrame("Frame")
    S.pulse:Hide()
    S.pulse:SetScript("OnUpdate", function(_, dt)
        if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
        S.pulseT = (S.pulseT + (dt or 0)) % PULSE
        local k = 0.6 + 0.4 * math.cos(S.pulseT / PULSE * 2 * math.pi)
        for _, it in ipairs(S.here) do
            local t = it.hereTex
            if t and it.shown and t:IsShown() then t:SetAlpha(k * (it.alpha or 1)) end
        end
    end)
    for _, slot in ipairs(S.slots) do ApplySlot(slot) end
    Doors:UpdateHere()
    -- (the marks are fresh whenever the map opens, whatever events came before; this hook runs before Core's own OnShow
    -- hook, which draws the labels)
    if WorldMapFrame and WorldMapFrame.HookScript then WorldMapFrame:HookScript("OnShow", function() Doors:UpdateHere() end) end
end

---------------------------------------------------------------------------
-- Tooltips (Dungeon.lua SetHot: the lines of every world-map entrance icon pass through here)
---------------------------------------------------------------------------
local GREY, ORANGE, BLUE = { 0.7, 0.7, 0.7 }, { 1, 0.6, 0.25 }, { 0.55, 0.8, 1 }
local function Line(text, c, size) return { text, c[1], c[2], c[3], size or 11 } end

local function KindText(slot)
    local k = slot.rkind == "raid" and "Raid" or "Dungeon"
    if slot.lo and slot.hi and slot.hi > slot.lo then return ("%s, level %d-%d"):format(k, slot.lo, slot.hi) end
    if slot.lo then return ("%s, level %d"):format(k, slot.lo) end
    return k
end

-- A slot with no map to open: its whole tooltip.
local function OwnLines(slot)
    local lines = { { slot.name, 1, 1, 1, 13 }, Line(KindText(slot), GREY) }
    if slot.learned then
        lines[#lines + 1] = Line("Door learned in game", BLUE)
        lines[#lines + 1] = Line("No map for this instance yet", GREY)
        return lines
    end
    lines[#lines + 1] = Line("Not in the game files yet", ORANGE)
    if slot.conf ~= "high" then lines[#lines + 1] = Line("Location approximate", GREY) end
    local b = slot.hint and slot.hint.b
    if type(b) == "table" and #b > 0 then lines[#lines + 1] = Line("Bosses: " .. table.concat(b, ", "), GREY) end
    return lines
end

function Doors:Tip(it, base)
    local slot = it.door
    if not (slot and slot.sk) then slot = nil end
    local own = slot and it.noClick
    local lines = own and OwnLines(slot) or base(it)
    if slot and not own then
        local extra
        if slot.learned then extra = Line("Door learned in game", BLUE)
        elseif slot.sk == "row" and slot.conf == "medium" then extra = Line("Door not confirmed yet (from the client files)", ORANGE) end
        if extra then table.insert(lines, math.max(#lines, 2), extra) end
        -- (a row's note describes ITS point: gone when the learned door is elsewhere)
        local note = slot.row and slot.row.note
        if note and slot.learned and Dist(slot.learned, slot.home) > 60 then
            for i = #lines, 2, -1 do if lines[i][1] == note then table.remove(lines, i) end end
        end
    end
    if it.here then
        local name = S.insideName or (slot and slot.name) or "this instance"
        table.insert(lines, 1, { "You are inside " .. name, 1, 0.82, 0, 13 })
    end
    return lines
end

---------------------------------------------------------------------------
-- The recorder
---------------------------------------------------------------------------
-- "Zone 12.3, 45.6" of a world point (in uiMap want when given: a door row's own zone, else the one the game names).
local function Where(c, x, y, want)
    local z = c == 0 and 1415 or 1414
    if C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D then
        local ok, zone, pos = pcall(C_Map.GetMapPosFromWorldPos, c, CreateVector2D(x, y), want)
        if ok and type(zone) == "number" and pos and ns.maps and ns.maps[zone] then
            local px, py = pos:GetXY()
            if px and py then return ("%s %.1f, %.1f"):format(ns.maps[zone].name or tostring(zone), px * 100, py * 100) end
        end
    end
    return ("%s %.0f, %.0f"):format(ns.maps and ns.maps[z] and ns.maps[z].name or tostring(c), x, y)
end

local function Record(inst, s, kind)
    local db = DB(true)
    if not db then return end
    local rec = db[inst.id]
    if type(rec) ~= "table" or type(rec.s) ~= "table" then
        rec = { s = {} }
        db[inst.id] = rec
    end
    rec.n = inst.name or rec.n
    rec.k = inst.kind or rec.k
    local build = select(2, GetBuildInfo())
    rec.s[#rec.s + 1] = { c = s.c, x = math.floor(s.x * 10 + 0.5) / 10, y = math.floor(s.y * 10 + 0.5) / 10, k = kind, t = Now(),
        b = tonumber(build) or build }
    while #rec.s > MAX_SAMPLES do table.remove(rec.s, 1) end
    Log(("%s %s: %s sample at %s"):format(tostring(inst.name or inst.id), kind == "in" and "entered" or "left", kind, Where(s.c, s.x, s.y)))
    Doors:Refresh()
end

local function Reject(inst, kind, why)
    Log(("%s %s: no %s sample - %s"):format(tostring(inst and (inst.name or inst.id) or "?"), kind == "in" and "entered" or "left", kind, why))
end

-- Why an entry may not count (nil: it counts).
local function EntryProblem(inst, snap, tLoad)
    if inst.typ ~= "party" and inst.typ ~= "raid" then return "not a dungeon or raid (" .. tostring(inst.typ) .. ")" end
    if inst.lfg then return "a dungeon finder teleport" end
    if not snap then return "no outdoor position right before the loading screen" end
    local age = (tLoad or GetTime()) - snap.t
    if age > MAX_AGE then return ("a stale position (%.1f s old)"):format(age) end
    if snap.dead then return "dead or a ghost" end
    if (S.summonT and GetTime() - S.summonT <= SUMMON_WINDOW) or SummonPending() then return "a summon" end
end

local function OnEnterWorld(login, reload)
    local inst = Inside()
    local prev = S.prev
    local snap, tLoad = S.snap, S.tLoad
    S.snap, S.tLoad, S.exitArm, S.last = nil, nil, nil, nil
    if login or reload then
        if inst then Reject(inst, "in", login and "a login" or "a /reload") end
    elseif inst and not (prev and prev.id == inst.id) then
        local why = EntryProblem(inst, snap, tLoad)
        if why then Reject(inst, "in", why) else Record(inst, snap, "in") end
    elseif not inst and prev then
        if prev.lfg then Reject(prev, "out", "a dungeon finder teleport")
        elseif prev.typ ~= "party" and prev.typ ~= "raid" then Reject(prev, "out", "not a dungeon or raid")
        else S.exitArm = { inst = prev, t = GetTime() } end
    end
    S.prev = inst
    S.pollT = 0
    if S.poll then S.poll:SetShown(inst == nil) end
    Doors:UpdateHere()
end

local function Poll(_, dt)
    S.pollT = S.pollT - (dt or 0)
    if S.pollT > 0 then return end
    S.pollT = POLL
    local c, x, y = Pos()
    if not c then return end
    local now = GetTime()
    local s = { c = c, x = x, y = y, t = now, dead = Dead() }
    S.last = s
    local arm = S.exitArm
    if arm then
        S.exitArm = nil
        if now - arm.t > EXIT_WAIT then Reject(arm.inst, "out", "no outdoor position in time")
        elseif s.dead then Reject(arm.inst, "out", "dead or a ghost")
        else Record(arm.inst, s, "out") end
    end
end

local function OnEvent(_, event, a1, a2)
    if event == "LOADING_SCREEN_ENABLED" then
        local l = S.last
        S.snap = l and { c = l.c, x = l.x, y = l.y, t = l.t, dead = l.dead } or nil
        S.tLoad = GetTime()
    elseif event == "CONFIRM_SUMMON" then
        S.summonT = GetTime()
    elseif event == "PLAYER_ENTERING_WORLD" then
        OnEnterWorld(a1 == true, a2 == true)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        Doors:UpdateHere()
    end
end

---------------------------------------------------------------------------
-- /unroll doors
---------------------------------------------------------------------------
local function Ago(t)
    local now = Now()
    if not (type(t) == "number" and t > 0 and now > 0) then return "?" end
    local d = now - t
    if d < 90 then return ("%d s ago"):format(d) end
    if d < 5400 then return ("%d min ago"):format(d / 60) end
    if d < 129600 then return ("%d h ago"):format(d / 3600) end
    return ("%d days ago"):format(d / 86400)
end

local function List()
    local rows, ghosts = {}, {}
    for _, slot in ipairs(S.slots) do
        local p = slot.learned or slot.home
        if slot.sk == "row" then
            rows[#rows + 1] = ("%s (%s, %s)"):format(slot.name, Where(p.c, p.x, p.y, not slot.learned and slot.home.zone or nil),
                slot.learned and "learned in game" or (slot.conf == "medium" and "not confirmed yet" or "confirmed"))
        elseif slot.sk == "ghost" then
            ghosts[#ghosts + 1] = ("%s (%s, %s)"):format(slot.name, Where(p.c, p.x, p.y, not slot.learned and slot.home.zone or nil),
                slot.learned and "learned in game" or (slot.conf or "?"))
        end
    end
    Print("doors on the world map: " .. table.concat(rows, "; "))
    Print(("placeholders (%s - /unroll doors hints): %s"):format(ns.db and ns.db.doorHints == false and "hidden" or "shown", table.concat(ghosts, "; ")))
    local n = 0
    for id, rec in pairs(DB() or {}) do
        if type(id) == "number" and type(rec) == "table" and type(rec.s) == "table" then
            n = n + 1
            local parts = {}
            for _, s in ipairs(rec.s) do if type(s) == "table" then parts[#parts + 1] = ("%s %s"):format(tostring(s.k), Ago(s.t)) end end
            local pt = Evaluate(id, rec)
            local state = pt and ("door at " .. Where(pt.c, pt.x, pt.y)) or "not confirmed yet"
            if pt and Builtin(id) then state = state .. " (a built-in door: kept)" end
            local near
            for _, slot in ipairs(S.slots) do
                if slot.sk == "row" and slot.id == id and pt then near = Dist(pt, slot.home) end
            end
            if near then state = state .. (", %.0f yd from the built-in door"):format(near) end
            Print(("learned %d %s: %d sample(s) (%s) - %s"):format(id, tostring(rec.n or "?"), #rec.s, table.concat(parts, ", "), state))
        end
    end
    if n == 0 then Print("no doors learned yet: walk into an instance and the addon notes the door") end
    for _, text in ipairs(S.log) do Print("recent: " .. text) end
end

function Doors:Slash(rest)
    if not S.supported then Print("doors: WoW Forever only") return end
    local cmd, arg = (rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" or cmd == "list" then
        List()
    elseif cmd == "hints" then
        local db = ns.db
        if not db then return end
        if arg == "on" then db.doorHints = true elseif arg == "off" then db.doorHints = false else db.doorHints = db.doorHints == false end
        Print("placeholders for the instances not in the game yet " .. (db.doorHints and "|cff40ff40on|r" or "|cffff4040off|r"))
        Redraw()
    elseif cmd == "forget" then
        local db = DB()
        local id = tonumber(arg)
        if not id and arg ~= "" and arg ~= "all" then -- (review: not an instance ID - nothing is forgotten, and it says so)
            Print("/unroll doors forget [id]: " .. arg .. " is no instance ID (/unroll doors lists them) - nothing forgotten")
            return
        end
        if db and id then db[id] = nil elseif db then wipe(db) end
        Print(id and ("forgot the samples of instance %d"):format(id) or "forgot every learned door")
        Doors:Refresh(true)
    else
        Print("/unroll doors            list the doors (built in, placeholders, learned)")
        Print("/unroll doors hints [on|off]   placeholders for the instances not in the game yet")
        Print("/unroll doors forget [id]      clear the learned doors (all, or one instance ID)")
    end
end

---------------------------------------------------------------------------
-- Start (Forever only: on Classic Era the module stays inert)
---------------------------------------------------------------------------
S.supported = Supported()
if S.supported then
    local f = CreateFrame("Frame")
    for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "LOADING_SCREEN_ENABLED", "CONFIRM_SUMMON" }) do
        pcall(f.RegisterEvent, f, ev) -- (an event a client lacks is simply not registered)
    end
    f:SetScript("OnEvent", OnEvent)
    S.events = f
    S.poll = CreateFrame("Frame")
    S.poll:Hide()
    S.poll:SetScript("OnUpdate", Poll)
end
