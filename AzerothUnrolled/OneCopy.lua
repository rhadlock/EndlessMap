--[[
Endless Map - OneCopy.lua (1.3.1; the TOC's first file)

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
]]
local ADDON, ns = ...

local BETA = "AzerothUnrolledBeta" -- (the test copy's folder: tools/release/beta_copy.py)

local function Plain(v, kind) return type(v) == kind and not (issecretvalue and issecretvalue(v)) end

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
    local keep = older and AzerothUnrolledDB
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
    return
end
ENDLESSMAP_ACTIVE_COPY = ADDON

-- (/unroll debug, Core.lua) the other copies loaded in this session - each stood down for this one; nil: none. (A copy
-- from before 1.3.1 loaded after this one would run too - and would own /unroll, so this line is never printed then.)
-- A copy is a folder whose name starts with AzerothUnrolled (the add-on's folder keeps that name: the release, the beta,
-- a manual download "AzerothUnrolled-main"); a title is not asked (another add-on may say "Endless Map" in its own).
function ns.OtherCopies()
    local A = C_AddOns
    if type(A) ~= "table" then return nil end
    local ok, n = pcall(A.GetNumAddOns)
    if not ok or not Plain(n, "number") then return nil end
    local out = {}
    for i = 1, n do
        local ok1, name = pcall(A.GetAddOnInfo, i)
        if ok1 and Plain(name, "string") and name ~= ADDON and name:find("AzerothUnrolled", 1, true) == 1 then
            local ok2, isLoaded = pcall(A.IsAddOnLoaded, i)
            if ok2 and Plain(isLoaded, "boolean") and isLoaded then out[#out + 1] = name end
        end
    end
    if #out == 0 then return nil end
    return ("this copy runs: %s; stood down: %s"):format(ADDON, table.concat(out, ", "))
end
