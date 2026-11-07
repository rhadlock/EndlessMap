--[[
Endless Map - LoadStamp.lua (1.4.0; in every TOC, right after OneCopy.lua)

Which of the add-on's TOCs the game loaded, written silently into the saved settings. From 1.4.0 the one folder has two
TOCs (docs/retail-plan.md, section 7): AzerothUnrolled.toc for WoW Forever and Classic Era (interfaces 16001, 11508,
11509) and AzerothUnrolled_Standard.toc for retail (120105, the retail client's own engineSurveyPatch). Retail 12.1.5
takes a _Standard TOC before the plain one; Forever never loads it (it tries _Forever / _Camelot, then _Mainline, then
the plain TOC - so no TOC of ours is ever called _Mainline). Each TOC names itself in a field of its own,
## X-Endless-Toc ("plain", "Standard"), read back here with C_AddOns.GetAddOnMetadata (AddOnsDocumentation.lua:165 in
the retail 12.1.5.70529 and Forever 1.60.1.70532 clients alike, and Classic Era's; Blizzard's AddonList.lua reads its
IconTexture and Category fields the same way). After the user's in-game test the saved file is read on this machine
(logged): both clients loaded the TOC meant for them.

  AzerothUnrolledDB.loaded = { toc = "plain" | "Standard" (false: the field could not be read),
  ((1.4.0-beta4) on retail EndlessMapDB.loaded - the saved table's name by the game, OneCopy.lua ns.SAVED)
                               folder = the add-on's folder (AzerothUnrolled, or AzerothUnrolledBeta for a test copy;
                                        retail: EndlessMap, EndlessMapBeta),
                               version = the TOC's ## Version, game = "1.60.1" | "12.1.5", build = "70532",
                               interface = 16001 | 120105 (GetBuildInfo), at = time() of this login,
                               -- retail 1.4.0-beta0 only, from its RetailProbe.lua's Settings page (1.4.0-beta1:
                               -- that file is gone, nothing writes these two; RetailSpace.lua's own stamp is
                               -- AzerothUnrolledDB.retailChecks):
                               settings = true (the page is registered) or the error,
                               seen = { the last session the page was shown in: at = that login's time, page = times
                                        shown, iconSet / artSet / maskSet = what its three SetTexture calls answered,
                                        art / mask = whether its picture and the picture's mask had loaded } }

Written once per login, at the add-on's ADDON_LOADED, over the last login's (only its seen is carried over, until the
page shows again - 1.4.0-beta0 review: a /reload or relog after the in-game check lost it); no other saved value is
read or changed. Silent: no chat line, no popup, nothing shown. On Forever and Classic Era nothing else reads it:
Core.lua's defaults and Rev stamps fill other keys, /unroll reset writes only the defaults (Options.lua O:Reset), and
Core.lua's PLAYER_LOGIN keeps the global on the very table this file and Core.lua took at ADDON_LOADED (1.3.1,
OneCopy.lua) - so the stamp is in the table the game saves. On retail (1.4.0-beta1) the retail TOC loads the engine
after this file (Core.lua's defaults; RetailSpace.lua's stamp): the saved table still starts here.
]]
local ADDON, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)

-- (only plain values are kept: a value the game hands out may be secret in this era's clients, as in OneCopy.lua)
local function Plain(v, kind) return type(v) == kind and not (issecretvalue and issecretvalue(v)) end

-- One field of this add-on's TOC, or nil (no API, an error, a secret, an empty field).
local function Meta(field)
    local A = C_AddOns
    local get = type(A) == "table" and A.GetAddOnMetadata
    if type(get) ~= "function" then return nil end
    local ok, v = pcall(get, ADDON, field)
    if ok and Plain(v, "string") and v ~= "" then return v end
    return nil
end

local function Stamp()
    local db = _G[ns.SAVED] -- ((1.4.0-beta4) AzerothUnrolledDB; on retail EndlessMapDB - OneCopy.lua)
    if type(db) ~= "table" then -- (a first login, or retail, where no Core.lua makes the table)
        db = {}
        _G[ns.SAVED] = db
    end
    local s = { toc = Meta("X-Endless-Toc") or false, folder = ADDON, version = Meta("Version") }
    if GetBuildInfo then
        local ok, game, build, _, interface = pcall(GetBuildInfo)
        if ok then
            if Plain(game, "string") then s.game = game end
            if Plain(build, "string") then s.build = build end
            if Plain(interface, "number") then s.interface = interface end
        end
    end
    if time then
        local ok, t = pcall(time)
        if ok and Plain(t, "number") then s.at = t end
    end
    local old = db.loaded -- (1.4.0-beta0's RetailProbe.lua: its page's last showing, kept as it was)
    if type(old) == "table" and type(old.seen) == "table" then s.seen = old.seen end
    -- ((1.6.1, Share.lua's What's new) the version of the last login before this one)
    if type(old) == "table" and Plain(old.version, "string") then s.prev = old.version end
    db.loaded = s
    ns.loadStamp = s -- (1.4.0-beta0's RetailProbe.lua added what its page saw)
end

-- (the add-on's own ADDON_LOADED: its saved file is in by then; once, then the frame is done)
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    self:SetScript("OnEvent", nil)
    Stamp()
end)
