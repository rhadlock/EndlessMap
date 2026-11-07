--[[
Endless Map - Share.lua (1.6.1; both games: AzerothUnrolled.toc and AzerothUnrolled_Standard.toc, after Options.lua and
each game's changes data - ChangesData.lua, RetailChangesData.lua)

The player, 2026-11-06, after asking whether a button could post the add-on's link in General chat - no: Blizzard's UI
Add-On Development Policy says "Add-ons may not be used to advertise any goods or services" (rule 4) and counts
"excessive use of the chat system" against other players (rule 3) -: "all 3 of those are good ideas. is there a way to
add bug reporting too?", "can we add a pop up in game that says the changes as well, so the first time they hit m since
an update the change log appear with the buttons ... they would be able to remove logs from that pop up. and thats what
the new button opens". On 1.6.1-beta1 in game: "the URL should be more obvious. report bug is broken, see image, we have
multiple windows. also that window does not meet the astetic of clasic we should match the game style, assets exist in
the client for this", "if theres soemthing we need them to copy and paste it shouldnt be in the same copy paste as the
instructions on what to do", "should be a button to auto copy really"; after 1.6.1-beta2, with Endless Map's public
repository on GitHub: "lets point the report a bug at where the issues would be on git". Nothing here sends anything to
another player or out of the game: no chat message, no whisper, no channel.

ONE WINDOW, the game's own: Blizzard's ButtonFrameTemplate (the frame of the game's mail, gossip and merchant windows,
with the add-on's icon as its portrait), the quest log's parchment (atlas QuestBG-Parchment; the file QuestBG where the
client has no such atlas) under the changes in the game's quest font, the game's buttons (UIPanelButtonTemplate), check
box (UICheckButtonTemplate), input boxes (InputBoxTemplate) and scroll frames (UIPanelScrollFrameTemplate). Two views,
switched by the two buttons in its bottom bar - never a second window:

  * WHAT'S NEW: this game's own changes (ns.CHANGES - tools/release/changes_lua.py makes it from the add-on's changelog:
    CHANGELOG.md on WoW Forever, CHANGELOG_Retail.md on retail), and "Spread the word": the download link (the CurseForge
    project page) in its own box with "Copy link". It opens by itself the first time the map opens after the add-on
    updated - never at login, never in combat - with the changes since the version the player had (db.seenVersion; for
    a player who never had one, LoadStamp.lua's prev: the version of the last login before; a brand-new player gets
    none); the map menu's "What's new", the Settings page's button and /unroll news open it any time. "Show what's new
    after an update" (the setting newsAfterUpdate) in its bottom bar. It closes with the map it opened with, its X, or
    Escape.
  * REPORT A BUG: the steps, as text to read; the report alone in its own box with "Copy report" - the add-on's version,
    folder and TOC, the game's version, build, interface and language, where the player and the map are, the settings
    changed from their defaults, the add-ons loaded, and this add-on's own Lua errors of the session (each message, how
    often, a few lines of its stack) - and where to paste it, in its own box with "Copy form link": (1.6.1-beta3) the
    bug form of Endless Map's GitHub issues (S.BUGS: the public repository's .github/ISSUE_TEMPLATE/bug_report.yml),
    its fields "game" and "version" filled in by the link (GitHub fills an issue form's text fields from the link's
    query, by their id). No character name, realm or account goes in. The map menu's "Report a bug", the Settings
    page's and /unroll bug open it.
  * COPY: no add-on may write the clipboard. CopyToClipboard is protected - Blizzard's own code only (warcraft.wiki.gg,
    API_CopyToClipboard: "#protected - This can only be called from secure code"; OsDocumentation.lua's entry for it,
    HasRestrictions, is word for word AssistUnit's, protected since 2.0): an add-on's call is blocked and the game shows
    its "only available to the Blizzard UI" dialog. So a Copy button does what an add-on can: its box's text, all
    selected, under the keyboard, and "Press Ctrl+C" (Cmd+C on a Mac) - the game's own copy. The box sees that Ctrl+C,
    says the text is copied and gives the keyboard back.
  * LINK: /unroll link prints the link in the player's own chat frame (DEFAULT_CHAT_FRAME:AddMessage: nobody else
    sees it).
  * THE ERRORS: from the login on, an error handler in front of the one there (geterrorhandler / seterrorhandler, as
    the error-catching add-ons chain theirs) notes the errors whose text names this add-on's folder; every error goes on
    to the handler before it, as it did.
]]
local ADDON, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)

local S = {}
ns.Share = S
S.URL = "https://www.curseforge.com/wow/addons/endless-map" -- (CurseForge project 1725335)
S.BUGS = "https://github.com/rhadlock/EndlessMap/issues/new?template=bug_report.yml" -- (1.6.1-beta3: the bug form)
local ERR_KEEP = 5      -- (the errors a report lists: the last ones, each once with its count)
local STACK_LINES = 6   -- (and a few lines of where each happened)
local ADDONS_MAX = 40   -- (the add-ons it names; the rest counted)
local NEWS_RECENT = 3   -- (the window opened by hand: the newest versions' changes)
local W, H = 560, 560   -- (the window)

local function Plain(v, kind) return type(v) == kind and not (issecretvalue and issecretvalue(v)) end
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end
local function Say(msg) if ns.Print then ns.Print(msg) end end
-- "1.6.1-beta1" -> 1006001 (a version's order; nil: not a version)
local function Ver(s)
    local a, b, c = tostring(s or ""):match("^(%d+)%.(%d+)%.(%d+)")
    if not a then return nil end
    return tonumber(a) * 1000000 + tonumber(b) * 1000 + tonumber(c)
end
local function Version()
    local ld = (ns.db and ns.db.loaded) or ns.loadStamp or {}
    return Plain(ld.version, "string") and ld.version or nil
end

---------------------------------------------------------------------------
-- This add-on's errors of the session
---------------------------------------------------------------------------
local errs = {}
local function Note(msg)
    if not (Plain(msg, "string") and msg:find(ADDON, 1, true)) then return end
    for _, e in ipairs(errs) do
        if e.msg == msg then
            e.n = e.n + 1
            return
        end
    end
    if #errs >= ERR_KEEP then table.remove(errs, 1) end
    local lines = {}
    local stack = debugstack and Call(debugstack, 2, 12, 0)
    for l in (Plain(stack, "string") and stack or ""):gmatch("[^\n]+") do
        -- (where the error happened: the handler's own lines left out)
        if not (l:find("Share.lua", 1, true) or l:find("in function `pcall'", 1, true) or l:find("in function 'pcall'", 1, true)) then
            if #lines < STACK_LINES then lines[#lines + 1] = l end
        end
    end
    errs[#errs + 1] = { msg = msg, n = 1, stack = lines }
end
local chained = false
local function Chain()
    if chained or not (geterrorhandler and seterrorhandler) then return end
    local prev = geterrorhandler()
    if type(prev) ~= "function" then return end
    chained = true
    seterrorhandler(function(msg, ...)
        pcall(Note, msg)
        return prev(msg, ...)
    end)
end

---------------------------------------------------------------------------
-- The report: what to paste, nothing else
---------------------------------------------------------------------------
local GAMES = { forever = "WoW Forever", retail = "World of Warcraft", era = "Classic Era" }

local function AddOnsLoaded()
    local A = C_AddOns
    local n = type(A) == "table" and Call(A.GetNumAddOns)
    if not Plain(n, "number") then return nil end
    local out, more = {}, 0
    for i = 1, n do
        local name = Call(A.GetAddOnInfo, i)
        local loaded = Call(A.IsAddOnLoaded, i)
        if Plain(name, "string") and loaded == true and name ~= ADDON then
            if #out < ADDONS_MAX then
                local v = Call(A.GetAddOnMetadata, name, "Version")
                out[#out + 1] = (Plain(v, "string") and v ~= "") and (name .. " " .. v) or name
            else
                more = more + 1
            end
        end
    end
    if #out == 0 then return "none" end
    return table.concat(out, ", ") .. (more > 0 and (" and %d more"):format(more) or "")
end

local function Changed()
    local O = ns.Options
    if not (O and O.List) then return "?" end
    local out = {}
    for _, s in ipairs(O:List()) do
        local cur, def = O:Get(s.key), O:Default(s.key)
        if def ~= nil and cur ~= def then out[#out + 1] = s.key .. " = " .. tostring(cur) end
    end
    return #out > 0 and table.concat(out, ", ") or "none"
end

local function MapName(id)
    local info = C_Map and Call(C_Map.GetMapInfo, id)
    return (type(info) == "table" and Plain(info.name, "string")) and info.name or "?"
end

local function Where()
    local parts = {}
    local here = C_Map and Call(C_Map.GetBestMapForUnit, "player")
    if Plain(here, "number") then parts[#parts + 1] = ("you are in %s (map %d)"):format(MapName(here), here) end
    local inside, kind = Call(IsInInstance)
    if inside then parts[#parts + 1] = "inside an instance (" .. tostring(kind) .. ")" end
    local M = WorldMapFrame
    if M and M:IsShown() then
        local id = M:GetMapID()
        local line = ("the map shows %s (map %s)"):format(Plain(id, "number") and MapName(id) or "?", tostring(id))
        local core = ns.Core
        local cam, v
        if core and core.Cam then cam, v = core.Cam() end
        if cam and v and v.W and v.W > 0 and ns.WorldZoom then line = line .. (", world zoom %.2fx"):format(ns.WorldZoom(v, cam.vw)) end
        if core and core.State then line = line .. ", " .. tostring(core.State()) end
        parts[#parts + 1] = line
        -- (WoW Forever's dungeon view open: its own line - Dungeon.lua's /unroll debug line)
        local D = ns.Dungeon
        if D and D.IsActive and Call(D.IsActive, D) and D.DebugLine then
            local dl = Call(D.DebugLine, D)
            if Plain(dl, "string") then parts[#parts + 1] = dl end
        end
    else
        parts[#parts + 1] = "the map is closed"
    end
    return table.concat(parts, "; ")
end

function S:ReportText()
    local ld = (ns.db and ns.db.loaded) or ns.loadStamp or {}
    local game, build, _, interface = Call(GetBuildInfo)
    local L = {}
    L[#L + 1] = ("Endless Map %s (folder %s, TOC %s)"):format(tostring(ld.version or "?"), ADDON, tostring(ld.toc or "?"))
    L[#L + 1] = ("Game: %s %s build %s, interface %s, %s"):format(GAMES[ns.FLAVOR] or tostring(ns.FLAVOR), tostring(game),
        tostring(build), tostring(interface), tostring(Call(GetLocale) or "?"))
    L[#L + 1] = "Where: " .. Where()
    L[#L + 1] = "Settings changed from the defaults: " .. Changed()
    L[#L + 1] = "Add-ons loaded: " .. (AddOnsLoaded() or "not available")
    if #errs == 0 then
        L[#L + 1] = "Errors of Endless Map this session: none" .. (chained and "" or " noted (the error handler was not chained)")
    else
        L[#L + 1] = "Errors of Endless Map this session:"
        for i, e in ipairs(errs) do
            L[#L + 1] = ("%d) %s%s"):format(i, e.n > 1 and ("x%d "):format(e.n) or "", e.msg)
            for _, l in ipairs(e.stack) do L[#L + 1] = "    " .. l end
        end
    end
    return table.concat(L, "\n")
end

-- a value in a link: letters, digits and - . _ ~ as they are, every other byte %XX (RFC 3986)
local function Enc(s)
    return (tostring(s):gsub("[^%w%-%._~]", function(c) return ("%%%02X"):format(c:byte()) end))
end

-- (1.6.1-beta3) the bug form's link, with the form's fields "game" (this game, its version and build) and "version"
-- (the add-on's) filled in
function S:BugLink()
    local ld = (ns.db and ns.db.loaded) or ns.loadStamp or {}
    local game, build = Call(GetBuildInfo)
    local g = ("%s %s.%s"):format(GAMES[ns.FLAVOR] or tostring(ns.FLAVOR), tostring(game or "?"), tostring(build or "?"))
    return S.BUGS .. "&game=" .. Enc(g) .. "&version=" .. Enc(ld.version or "?")
end

function S:PrintLink()
    Say("download and updates: " .. S.URL .. " (only you see this line)")
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
-- the key the game copies with
local function CopyKeys() return (IsMacClient and IsMacClient()) and "Cmd+C" or "Ctrl+C" end
local function CopyDown() return (IsControlKeyDown and IsControlKeyDown()) or (IsMetaKeyDown and IsMetaKeyDown()) end
-- a text the player may copy and not change: typing puts it back, every keystroke; a click selects it all; the player's
-- Ctrl+C - the game's own copy - is seen: said in eb.status (eb.done), and the keyboard given back
local function KeepText(eb)
    eb:SetScript("OnTextChanged", function(self, user)
        if user and self.keep and self:GetText() ~= self.keep then
            self:SetText(self.keep)
            self:HighlightText()
        end
    end)
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnKeyDown", function(self, key)
        if key == "C" and CopyDown() then self.copying = true end
    end)
    eb:SetScript("OnKeyUp", function(self, key)
        if key == "C" and self.copying then
            self.copying = nil
            if self.status then self.status:SetText("|cff40ff40" .. (self.done or "Copied.") .. "|r") end
            self:ClearFocus()
        end
    end)
end
-- a Copy button: box eb's text, all selected, under the keyboard, for the player's Ctrl+C (no add-on may write the
-- clipboard: CopyToClipboard is protected - above)
local function Copy(eb)
    eb:SetFocus()
    eb:HighlightText()
    if eb.status then eb.status:SetText(("|cffffd100Press %s to copy it.|r"):format(CopyKeys())) end
end
local function Button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end
local function LinkBox(parent, w)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(w, 24)
    eb:SetAutoFocus(false)
    eb:SetFontObject(GameFontHighlight)
    KeepText(eb)
    return eb
end
local function Label(parent, font, text)
    local t = parent:CreateFontString(nil, "OVERLAY", font)
    t:SetJustifyH("LEFT")
    if text then t:SetText(text) end
    return t
end

local win
local function ShowView(view)
    local f = win
    f.view = view
    f.news:SetShown(view == "news")
    f.report:SetShown(view == "report")
    f.bNews:SetEnabled(view ~= "news")
    f.bReport:SetEnabled(view ~= "report")
    f:SetTitle(("Endless Map %s - %s"):format(tostring(Version() or ""), view == "news" and "what's new" or "report a bug"))
end

local function NewsView(f)
    local v = CreateFrame("Frame", nil, f.Inset)
    v:SetAllPoints(f.Inset)
    -- (the changes on the quest log's parchment, in the game's quest font)
    local bg = v:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", v, "TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", -3, 100)
    if C_Texture and C_Texture.GetAtlasInfo and Call(C_Texture.GetAtlasInfo, "QuestBG-Parchment") then
        bg:SetAtlas("QuestBG-Parchment")
    else
        bg:SetTexture("Interface\\QuestFrame\\QuestBG")
    end
    local scroll = CreateFrame("ScrollFrame", nil, v, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", v, "TOPLEFT", 12, -10)
    scroll:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", -30, 106)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(W - 70, 10)
    scroll:SetScrollChild(child)
    v.body = Label(child, "QuestFont")
    v.body:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -4)
    v.body:SetWidth(W - 78)
    v.child, v.scroll = child, scroll
    -- (spread the word: the link, in its own box, and its button)
    local head = Label(v, "GameFontNormalLarge", "Spread the word")
    head:SetPoint("BOTTOMLEFT", v, "BOTTOMLEFT", 12, 72)
    v.link = LinkBox(v, W - 180)
    v.link:SetPoint("BOTTOMLEFT", v, "BOTTOMLEFT", 18, 40)
    v.status = Label(v, "GameFontHighlightSmall", "Endless Map's page: copy the link and share it wherever you like.")
    v.status:SetPoint("BOTTOMLEFT", v, "BOTTOMLEFT", 14, 14)
    v.link.status, v.link.done = v.status, "Copied - paste it wherever you like."
    v.copy = Button(v, "Copy link", 116, function() Copy(v.link) end)
    v.copy:SetPoint("LEFT", v.link, "RIGHT", 10, 0)
    return v
end

local function ReportView(f)
    local v = CreateFrame("Frame", nil, f.Inset)
    v:SetAllPoints(f.Inset)
    -- (the steps: to read, not to copy)
    local steps = Label(v, "GameFontHighlight")
    steps:SetPoint("TOPLEFT", v, "TOPLEFT", 12, -12)
    steps:SetWidth(W - 40)
    steps:SetText("Found a bug? Two steps:\n1. Copy report - the report below: the add-on's and the game's versions, your settings, Endless Map's errors.\n2. Copy form link and open it in your browser: Endless Map's bug form on GitHub. Say what happened, paste the report.")
    -- (the report: its own box, nothing in it but what to paste)
    local box = CreateFrame("Frame", nil, v)
    box:SetPoint("TOPLEFT", v, "TOPLEFT", 10, -92)
    box:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", -10, 108)
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(box)
    bg:SetColorTexture(0, 0, 0, 0.5)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -26, 6)
    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetWidth(W - 70)
    KeepText(eb)
    scroll:SetScrollChild(eb)
    v.text = eb
    v.status = Label(v, "GameFontHighlightSmall")
    eb.status, eb.done = v.status, "Report copied - now copy the form link below."
    v.copy = Button(v, "Copy report", 116, function() Copy(eb) end)
    v.copy:SetPoint("BOTTOMLEFT", v, "BOTTOMLEFT", 10, 76)
    v.status:SetPoint("LEFT", v.copy, "RIGHT", 10, 0)
    -- (the bug form: its own box and button)
    local head = Label(v, "GameFontNormal", "Endless Map's bug form on GitHub")
    head:SetPoint("BOTTOMLEFT", v, "BOTTOMLEFT", 12, 52)
    v.link = LinkBox(v, W - 180)
    v.link:SetPoint("BOTTOMLEFT", v, "BOTTOMLEFT", 18, 20)
    v.pageStatus = Label(v, "GameFontHighlightSmall")
    v.pageStatus:SetPoint("BOTTOMLEFT", v, "BOTTOMLEFT", 14, 4)
    v.link.status, v.link.done = v.pageStatus, "Link copied - open it in your browser and paste the report in the form."
    v.copyPage = Button(v, "Copy form link", 116, function() Copy(v.link) end)
    v.copyPage:SetPoint("LEFT", v.link, "RIGHT", 10, 0)
    return v
end

local function Win()
    if win then return win end
    local f = CreateFrame("Frame", ADDON .. "Window", UIParent, "ButtonFrameTemplate")
    f:SetSize(W, H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    f:SetPortraitToAsset("Interface\\AddOns\\" .. ADDON .. "\\Media\\icon")
    -- (Escape closes it, as it closes the game's own windows)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, f:GetName()) end
    win = f
    f.news = NewsView(f)
    f.report = ReportView(f)
    -- (its bottom bar: the switch, the two views)
    local check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 0)
    check.Text:SetText("Show what's new after an update")
    check:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        if ns.Options then ns.Options:Set("newsAfterUpdate", on, true) elseif ns.db then ns.db.newsAfterUpdate = on end
    end)
    f.check = check
    f.bReport = Button(f, "Report a bug", 120, function() S:ShowReport() end)
    f.bReport:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 4)
    f.bNews = Button(f, "What's new", 110, function() S:ShowNews(false) end)
    f.bNews:SetPoint("RIGHT", f.bReport, "LEFT", -4, 0)
    f:HookScript("OnHide", function() -- (hooked: the template's own scripts stay)
        f.news.link:ClearFocus()
        f.report.link:ClearFocus()
        f.report.text:ClearFocus()
    end)
    f:Hide()
    return f
end

-- this game's changes after version `since` (a number of Ver; nil: the newest NEWS_RECENT), up to this version
local function NewsLines(since)
    local cur = Ver(Version())
    local out, n = {}, 0
    for _, sec in ipairs(ns.CHANGES or {}) do
        local v = Ver(sec.v)
        if v and (not cur or v <= cur) and ((since and v > since) or (not since and n < NEWS_RECENT)) then
            n = n + 1
            out[#out + 1] = "|cff4a2c0f" .. sec.v .. "|r"
            for _, l in ipairs(sec.lines) do out[#out + 1] = l end
            out[#out + 1] = ""
        end
    end
    return out, n
end

-- (the window shown: the switch as saved; opened with the map: closed with it)
local function Open(f)
    f.check:SetChecked(not (ns.db and ns.db.newsAfterUpdate == false))
    if not f:IsShown() then
        f.withMap = WorldMapFrame and WorldMapFrame:IsShown() or false
        f:Show()
    end
end

-- auto: opened by itself with the map (the changes since db.seenVersion), else by hand (the newest)
function S:ShowNews(auto)
    local f = Win()
    local v = f.news
    local since = auto and Ver(ns.db and ns.db.seenVersion) or nil
    local lines, n = NewsLines(since)
    if n == 0 then lines = { "No changes are listed for this version." } end
    v.body:SetText(table.concat(lines, "\n"))
    v.child:SetHeight((v.body:GetStringHeight() or 0) + 12)
    v.scroll:SetVerticalScroll(0)
    v.link.keep = S.URL
    v.link:SetText(S.URL)
    v.link:SetCursorPosition(0)
    v.status:SetText("Endless Map's page: copy the link and share it wherever you like.")
    ShowView("news")
    Open(f)
    if ns.db and Version() then ns.db.seenVersion = Version() end
end

function S:ShowReport()
    local f = Win()
    local v = f.report
    local text = self:ReportText()
    v.text.keep = text
    v.text:SetText(text)
    v.text:SetCursorPosition(0)
    local link = self:BugLink()
    v.link.keep = link
    v.link:SetText(link)
    v.link:SetCursorPosition(0)
    v.status:SetText("")
    v.pageStatus:SetText("")
    ShowView("report")
    Open(f)
end

-- (the first map opening after an update; never in combat - the next opening then)
local function Due()
    local db = ns.db
    if not db or db.newsAfterUpdate == false or (InCombatLockdown and InCombatLockdown()) then return false end
    local cur, seen = Ver(Version()), Ver(db.seenVersion)
    if not (cur and seen) or seen >= cur then return false end
    local _, n = NewsLines(seen)
    return n > 0
end

-- (login: where this player comes from - the version whose changes they have seen)
local function Settle()
    local db = ns.db
    if not db or db.seenVersion ~= nil then return end
    local prev = ns.loadStamp and ns.loadStamp.prev
    -- (a player who had the add-on before: from that version; a brand-new one: nothing to tell, from now on)
    db.seenVersion = (Plain(prev, "string") and Ver(prev)) and prev or Version()
end

-- (Core.lua's slash handler: link, news, bug)
function S:Slash(cmd)
    if cmd == "link" then
        self:PrintLink()
    elseif cmd == "news" then
        self:ShowNews(false)
    else
        self:ShowReport()
    end
end

-- (tests) the window, the errors noted
S.T = { Win = function() return win end, errs = errs, Chained = function() return chained end, Due = Due, Ver = Ver }

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    Chain()
    Settle()
    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", function()
            if Due() then S:ShowNews(true) end
        end)
        WorldMapFrame:HookScript("OnHide", function()
            if win and win:IsShown() and win.withMap then win:Hide() end
        end)
    end
end)
