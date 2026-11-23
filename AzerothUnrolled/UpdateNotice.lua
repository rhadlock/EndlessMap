--[[
Endless Map - UpdateNotice.lua (1.8.2; both games: AzerothUnrolled.toc and AzerothUnrolled_Standard.toc, after Share.lua)

The author, 2026-11-22: "and can we do soemthing that would notify the user a new version is avalable? when they log in
or refresh?" No add-on can ask the internet - the game gives add-ons no web access. What it gives them is the hidden
add-on channel (C_ChatInfo.SendAddonMessage under a prefix of their own: no chat line, no player reads it), to the guild
and to the group - the way boss mods learn of their own updates. So Endless Map's copies tell each other which version
they are, and a copy that hears of a newer release says so:

  * SENT: "v1 <version>" (this copy's ## Version) under the prefix "EndlessMap": to the guild SEND_DELAY after the
    loading screen of a login or a reload (not in the login's own burst), and to the group (party, raid, or an instance
    group) on joining one or when it grows - at most once a channel in ANNOUNCE_EVERY. A copy that hears an OLDER
    version answers it on the same channel after ANSWER_MIN - ANSWER_MAX s at random, unless another copy has answered
    meanwhile with this version or a newer one - at most once a channel in ANSWER_EVERY. A beta (1.8.2-beta3: the
    author's own test copies, never published) never answers.
  * HEARD: a release newer than this copy (a beta of a version is older than that version's release; another copy's
    beta is never news) - kept in the saved settings (newestSeen) and said in chat at once, once a session.
  * SAID at every login and every reload while this copy is older than the newest heard: one chat line, SAY_DELAY after
    the loading screen. Once this copy is that version or newer, newestSeen goes.
  * The setting updateNotice ("Tell me when a newer version is out" - the Settings page, /unroll updates): off, nothing
    is sent, heard or said. /unroll version: this copy, the newest heard, the copies heard this session.

What it cannot do: tell a player whom no other Endless Map player meets - none in their guild, none in their group. And
the first version with this file hears only of the ones after it: 1.8.1 and older send nothing. Nothing else leaves the
game: no whisper, no chat channel, no chat message - only the add-on channel to the guild and the group; the names of
the copies heard are counted for /unroll version and never kept.
]]
local ADDON, ns = ...
if ns.inert then return end -- (another copy of the add-on runs - OneCopy.lua)

local PREFIX = "EndlessMap"
local SEND_DELAY = 8          -- (s after the loading screen: the login's own messages first)
local SAY_DELAY = 6           -- (s after the loading screen: after the game's own login lines)
local GROUP_DELAY = 2         -- (s after the group grew)
local ANNOUNCE_EVERY = 60     -- (s: at most one announcement a channel)
local ANSWER_EVERY = 30       -- (s: at most one answer a channel)
local ANSWER_MIN, ANSWER_MAX = 2, 6

local U = {}
ns.UpdateNotice = U

local function Plain(v, kind) return type(v) == kind and not (issecretvalue and issecretvalue(v)) end
local function Say(msg) if ns.Print then ns.Print(msg) end end
local function Now() return GetTime and GetTime() or 0 end

-- "1.8.2" -> 1008002, true (a release); "1.8.2-beta3" -> 1008002, false; nil: no version
local function Parse(s)
    if not Plain(s, "string") then return nil end
    local a, b, c, rest = s:match("^(%d+)%.(%d+)%.(%d+)(.*)$")
    if not a then return nil end
    return tonumber(a) * 1000000 + tonumber(b) * 1000 + tonumber(c), rest == ""
end
-- version a older than b (a beta older than its own version's release)
local function Older(a, ar, b, br)
    return a < b or (a == b and not ar and br)
end

local function Enabled() return ns.db ~= nil and ns.db.updateNotice ~= false end
-- this copy's version (LoadStamp.lua: the TOC's ## Version)
local function Own()
    local ld = (ns.db and ns.db.loaded) or ns.loadStamp or {}
    return Plain(ld.version, "string") and ld.version or nil
end

local announced, answered = {}, {} -- channel -> when this copy last announced / answered there
local due = {}                     -- channel -> the token of an answer waiting
local said = {}                    -- version -> said this session
local heard, heardN = {}, {}       -- sender -> true (this session); channel -> how many
local groupN = 0

local function Send(channel)
    local own = Own()
    local C = C_ChatInfo
    if not (Enabled() and Parse(own) and C and C.SendAddonMessage) then return false end
    local ok = pcall(C.SendAddonMessage, PREFIX, "v1 " .. own, channel)
    return ok
end

local function Announce(channel)
    if not channel then return end
    local t = Now()
    if announced[channel] and t - announced[channel] < ANNOUNCE_EVERY then return end
    if Send(channel) then announced[channel] = t end
end

local function GroupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

local function Line(v, own)
    return ("|cffffd100version %s is out|r - you have %s. Update it in the CurseForge app (or %s news for the download link)."):format(
        v, own, ns.COMMAND or "/endlessmap")
end

-- A release v newer than this copy: kept, and said once a session.
local function Learn(v, nv)
    local db = ns.db
    if not db then return end
    local kv = Parse(db.newestSeen)
    if not kv or nv > kv then db.newestSeen = v end
    if not said[v] then
        said[v] = true
        Say(Line(v, Own() or "?"))
    end
end

-- At a login or reload: the newest heard, while this copy is older; gone once it is not.
local function SayKnown()
    local db = ns.db
    if not (db and Enabled()) then return end
    local v = db.newestSeen
    local nv = Parse(v)
    local ov, orel = Parse(Own())
    if not (nv and ov) then
        if v ~= nil and not nv then db.newestSeen = nil end
        return
    end
    if Older(ov, orel, nv, true) then
        if not said[v] then
            said[v] = true
            Say(Line(v, Own()))
        end
    else
        db.newestSeen = nil
    end
end

local function Answer(channel)
    local t = Now()
    if answered[channel] and t - answered[channel] < ANSWER_EVERY then return end
    local token = {}
    due[channel] = token
    local wait = ANSWER_MIN + (math.random and math.random() or 0.5) * (ANSWER_MAX - ANSWER_MIN)
    C_Timer.After(wait, function()
        if due[channel] ~= token then return end
        due[channel] = nil
        if Send(channel) then answered[channel] = Now() end
    end)
end

local function Me(sender)
    local me = UnitName and UnitName("player")
    if not (Plain(me, "string") and Plain(sender, "string")) then return false end
    if sender == me then return true end
    local short = Ambiguate and Ambiguate(sender, "none")
    return short == me
end

local function Heard(text, channel, sender)
    if not Enabled() or Me(sender) then return end
    local v = Plain(text, "string") and text:match("^v1 (%S+)$")
    local hv, hr = Parse(v)
    if not hv then return end
    if Plain(sender, "string") and not heard[sender] then
        heard[sender] = true
        heardN[channel] = (heardN[channel] or 0) + 1
    end
    local ov, orel = Parse(Own())
    if not ov then return end
    if hr and Older(ov, orel, hv, true) then Learn(v, hv) end
    -- an answer as new as this copy's (or newer) came first: this copy's is not needed
    if due[channel] and not Older(hv, hr, ov, orel) then due[channel] = nil end
    -- an older copy: a release answers it
    if orel and Older(hv, hr, ov, true) and channel ~= "WHISPER" and not due[channel] then Answer(channel) end
end

-- /unroll version
function U:Status()
    local own = Own() or "?"
    local db = ns.db
    local v = db and db.newestSeen
    local parts = {}
    for ch, n in pairs(heardN) do
        local name = ch:lower():gsub("_", " ")
        parts[#parts + 1] = ("%s %d"):format(name, n)
    end
    table.sort(parts)
    Say(("this copy %s; the newest heard: %s; copies heard this session: %s%s"):format(own,
        Parse(v) and ("|cffffd100" .. v .. "|r") or "none newer",
        #parts > 0 and table.concat(parts, ", ") or "none",
        Enabled() and "" or (" - off (%s updates turns it on)"):format(ns.COMMAND or "/endlessmap")))
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("CHAT_MSG_ADDON")
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if event == "CHAT_MSG_ADDON" then
        if a1 == PREFIX then Heard(a2, a3, a4) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- (a1 isInitialLogin, a2 isReloadingUi: a login or a reload, not a loading screen between zones)
        if a1 or a2 then
            C_Timer.After(SAY_DELAY, SayKnown)
            C_Timer.After(SEND_DELAY, function()
                if IsInGuild and IsInGuild() then Announce("GUILD") end
                Announce(GroupChannel())
            end)
        end
        groupN = GetNumGroupMembers and GetNumGroupMembers() or 0
    elseif event == "GROUP_ROSTER_UPDATE" then
        local n = GetNumGroupMembers and GetNumGroupMembers() or 0
        if n > groupN and n > 1 then C_Timer.After(GROUP_DELAY, function() Announce(GroupChannel()) end) end
        groupN = n
    end
end)

-- (harness) the inner parts
U.T = { Parse = Parse, Older = Older, Heard = Heard, SayKnown = SayKnown, Own = Own, PREFIX = PREFIX,
    Reset = function() wipe(announced) wipe(answered) wipe(due) wipe(said) wipe(heard) wipe(heardN) groupN = 0 end }
