--[[
Endless Map - OneCopy.lua (1.3.1; the TOC's first file; 1.4.0: ns.FLAVOR)

(1.4.0) First of all it names the game this is, ns.FLAVOR (below), which every gate of the add-on reads.

One copy of the add-on runs, however many are enabled. The user, 2026-10-18, on a new character: "when i opened map it
would act very strange, zooming in and out was jittery and it seemed like the map addon and wow default map behavor was
fighting us. like both systems were running." They were: a new character starts with every add-on enabled, and that
one had both the CurseForge copy (folder AzerothUnrolled) and the test copy (folder AzerothUnrolledBeta). Each copy
hooked the map and drove Blizzard's canvas on its own (harness/hx/lua/twocopies_scen.lua: through a wheel zoom both
moved it in every frame, their two views drifted up to 1070 px apart, both pictures drawn); and both declare the same saved
table, AzerothUnrolledDB, so the copy loaded second replaced the table the first had taken.

The rule, decided here before any other file does anything:
  * While the beta copy (AzerothUnrolledBeta) is enabled for this character and loadable, every other copy stands down:
    the beta is the copy being tried out.
  * Otherwise the first copy to load runs. It leaves its folder name in ENDLESSMAP_ACTIVE_COPY; a copy that loads after
    it (any folder name: a manual download "AzerothUnrolled-main", ...) finds it and stands down. A copy from before
    1.3.1 sets no marker but has made its slash command by then (SLASH_AZEROTHUNROLLED1, Core.lua): that counts too -
    it cannot stand down, so the later one does.
A copy that stands down does nothing at all: every other file of the TOC returns at once on ns.inert (its first line
after `local _, ns = ...`), so it makes no frame, hook, event, timer, slash command, Settings entry or saved-table
write, and says nothing (no chat line, no popup). /unroll debug of the copy that runs names the others. One exception,
next to a copy from before 1.3.1 only: one frame for one event that puts the running copy's saved table back after
this copy's saved file replaced it (below), then it unregisters itself.
"Enabled for this character and loadable": C_AddOns.GetAddOnEnableState and C_AddOns.IsAddOnLoadable with the player's
GUID as the character, as Blizzard's AddonList.lua asks (AddOnsDocumentation.lua, Forever 1.60.1 and Classic Era
1.15.x alike). No answer (an API missing or raising, no GUID, a secret value) counts as "the beta does not load": then
this copy runs as the first, and the beta, loading after it, stands down by the marker - still one copy.

(1.4.0-beta4) The add-on's names, by the game (docs/retail-engine.md 18). On retail it is Endless Map everywhere a player
meets it: the folder EndlessMap (the test copy EndlessMapBeta - tools/release/flavors.py, beta_copy.py), the saved table
EndlessMapDB, the commands /emap and /endlessmap. WoW Forever and Classic Era keep what 1.3.1 kept for their players -
the folder AzerothUnrolled (it names their saved file), AzerothUnrolledDB, /unroll, /azerothunrolled, /endlessmap -
and gain /emap. Every file takes them from here: ns.SAVED (the saved table's global, the TOC's ## SavedVariables),
ns.SLASH (the SlashCmdList key), ns.COMMANDS (the slash words) and ns.COMMAND (the first: the one messages name).
On retail a copy of the old name (1.4.0-beta0 to beta3: AzerothUnrolledBeta, the user's) still runs where it is
installed: it loads first (the game loads add-ons by folder name), sets the marker, and this copy stands down - two
copies never run. The two declare different saved tables, so this copy's own table is no other copy's: it records why it
stood down there (AzerothUnrolledDB never touched), silently - its saved file then says so (EndlessMapDB.loaded.inert).
]]
local ADDON, ns = ...

local function Plain(v, kind) return type(v) == kind and not (issecretvalue and issecretvalue(v)) end

-- (1.4.0: ns.FLAVOR) Which game this is, decided once, here, before anything else: every file that switches something
-- on or off by the game reads it (docs/retail-plan.md section 7); none asks GetBuildInfo again to switch anything (only
-- stamps: Doors.lua's door sample, LoadStamp.lua's load stamp). By the interface number, GetBuildInfo's 4th value:
--   "era"      below 16000      Classic Era (11508, 11509)
--   "forever"  16000 - 19999    WoW Forever (16001)
--   "off"      20000 - 99999    another Classic game (TBC, Wrath, Cata or Mists Classic). The TOC does not list them:
--                               the client loads the add-on there only as "out of date", and it then runs as before
--                               1.4.0 - Forever's zone cells and imagery let through (Render.lua, MinimapLayer.lua),
--                               Forever's instances, doors, Gilneas and explored pieces not (Dungeon.lua, Doors.lua,
--                               DungeonMapsMM.lua, Gilneas.lua, OverlayData.lua)
--   "retail"   100000 and up    retail (12.1.5: 120105): nothing of Forever's (its pictures, masks and maps are not there)
-- No answer (GetBuildInfo missing or raising, not a number, a secret value) counts as 0, as each test did before 1.4.0
-- (`(select(4, GetBuildInfo())) or 0`): "era". A copy that stands down (below) has it too.
local okB, _, _, _, iface = pcall(GetBuildInfo)
if not okB or not Plain(iface, "number") or iface ~= iface then iface = 0 end
ns.FLAVOR = (iface < 16000 and "era") or (iface < 20000 and "forever") or (iface < 100000 and "off") or "retail"

-- (1.4.0-beta4) The names by the game (above) - in the namespace only for the copy that runs (below: one that stands
-- down keeps nothing but FLAVOR and inert). OLD: the folder prefix of a copy of the add-on under its old name.
local NAMES = (ns.FLAVOR == "retail")
    and { saved = "EndlessMapDB", slash = "ENDLESSMAP", commands = { "/emap", "/endlessmap" },
          beta = "EndlessMapBeta", copies = { "EndlessMap", "AzerothUnrolled" } }
    or { saved = "AzerothUnrolledDB", slash = "AZEROTHUNROLLED", commands = { "/unroll", "/azerothunrolled", "/endlessmap", "/emap" },
         beta = "AzerothUnrolledBeta", copies = { "AzerothUnrolled" } }
local BETA = NAMES.beta -- (the test copy's folder: tools/release/beta_copy.py)
local OLD = "AzerothUnrolled"

-- Will the beta copy load for this character?
local function BetaLoads()
    local A = C_AddOns
    if type(A) ~= "table" or not UnitGUID then return false end
    local ok, guid = pcall(UnitGUID, "player")
    if not ok or not Plain(guid, "string") or guid == "" then return false end
    local ok1, state = pcall(A.GetAddOnEnableState, BETA, guid)
    if not ok1 or not Plain(state, "number") or state <= 0 then return false end
    local ok2, loadable = pcall(A.IsAddOnLoadable, BETA, guid)
    return ok2 and Plain(loadable, "boolean") and loadable
end

local why, older
if ENDLESSMAP_ACTIVE_COPY ~= nil then
    why = "copy " .. tostring(ENDLESSMAP_ACTIVE_COPY) .. " runs"
elseif SLASH_AZEROTHUNROLLED1 ~= nil or (type(SlashCmdList) == "table" and SlashCmdList.AZEROTHUNROLLED ~= nil) then
    why, older = "a copy from before 1.3.1 runs", true
elseif ADDON ~= BETA and BetaLoads() then
    why = "the beta copy runs"
end
if why then
    ns.inert = why
    -- (1.3.1: the saved settings next to a copy from before 1.3.1) That copy took its saved file's table at its
    -- ADDON_LOADED and never looks at the global again; but every copy's TOC declares the one AzerothUnrolledDB, so this
    -- copy's saved file, which the game loads after these files, replaces the global - and at logout the game writes
    -- the global into every copy's file: the running copy's changes would be lost and its file (the CurseForge copy's,
    -- shared by all characters) would get this copy's settings. So this copy puts the running copy's table back once
    -- its own file has loaded: one frame, one event, gone after it - the one thing a copy that stands down does. (A
    -- running copy from 1.3.1 on points the global back itself at PLAYER_LOGIN: Core.lua.)
    -- ((1.4.0-beta4) only where both declare that table: never on retail, where this copy's is EndlessMapDB)
    local keep = older and NAMES.saved == "AzerothUnrolledDB" and AzerothUnrolledDB
    if type(keep) == "table" and CreateFrame then
        local f = CreateFrame("Frame")
        f:RegisterEvent("ADDON_LOADED")
        f:SetScript("OnEvent", function(self, _, name)
            if name ~= ADDON then return end
            self:UnregisterEvent("ADDON_LOADED")
            self:SetScript("OnEvent", nil)
            AzerothUnrolledDB = keep
        end)
    end
    -- ((1.4.0-beta4) next to a copy of the old name on retail - it declares AzerothUnrolledDB, this copy EndlessMapDB:
    -- the one other thing a copy that stands down does, once its own saved file has loaded - one frame, one event, gone
    -- after it - is to write why into its own table's load stamp (LoadStamp.lua's field; nothing else of it is touched))
    local run = ENDLESSMAP_ACTIVE_COPY
    if NAMES.saved ~= "AzerothUnrolledDB" and Plain(run, "string") and run:find(OLD, 1, true) == 1 and CreateFrame then
        local f = CreateFrame("Frame")
        f:RegisterEvent("ADDON_LOADED")
        f:SetScript("OnEvent", function(self, _, name)
            if name ~= ADDON then return end
            self:UnregisterEvent("ADDON_LOADED")
            self:SetScript("OnEvent", nil)
            local db = _G[NAMES.saved]
            if type(db) ~= "table" then
                db = {}
                _G[NAMES.saved] = db
            end
            local A = C_AddOns
            local okV, version = pcall(function() return A.GetAddOnMetadata(ADDON, "Version") end)
            local okT, at = pcall(time)
            db.loaded = { inert = why, folder = ADDON, version = okV and Plain(version, "string") and version or nil,
                          at = okT and Plain(at, "number") and at or nil }
        end)
    end
    return
end
ENDLESSMAP_ACTIVE_COPY = ADDON
ns.SAVED, ns.SLASH, ns.COMMANDS, ns.COMMAND = NAMES.saved, NAMES.slash, NAMES.commands, NAMES.commands[1] -- (1.4.0-beta4)

-- (/unroll debug, Core.lua) the other copies loaded in this session - each stood down for this one; nil: none. (A copy
-- from before 1.3.1 loaded after this one would run too - and would own /unroll, so this line is never printed then.)
-- A copy is a folder whose name starts with AzerothUnrolled (the add-on's folder keeps that name: the release, the beta,
-- a manual download "AzerothUnrolled-main"); a title is not asked (another add-on may say "Endless Map" in its own).
-- ((1.4.0-beta4) on retail with EndlessMap too - the folder there -, and the old name: 1.4.0-beta0 to beta3's copies)
function ns.OtherCopies()
    local A = C_AddOns
    if type(A) ~= "table" then return nil end
    local ok, n = pcall(A.GetNumAddOns)
    if not ok or not Plain(n, "number") then return nil end
    local out = {}
    local function Copy(name)
        for _, p in ipairs(NAMES.copies) do
            if name:find(p, 1, true) == 1 then return true end
        end
        return false
    end
    for i = 1, n do
        local ok1, name = pcall(A.GetAddOnInfo, i)
        if ok1 and Plain(name, "string") and name ~= ADDON and Copy(name) then
            local ok2, isLoaded = pcall(A.IsAddOnLoaded, i)
            if ok2 and Plain(isLoaded, "boolean") and isLoaded then out[#out + 1] = name end
        end
    end
    if #out == 0 then return nil end
    return ("this copy runs: %s; stood down: %s"):format(ADDON, table.concat(out, ", "))
end
