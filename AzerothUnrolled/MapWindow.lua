--[[
Endless Map - MapWindow.lua (1.7.0; WoW Forever and retail): the map window moved and sized by the player.

A player's request (2026-11-16, through the author): a way to resize the map window - "maintain the origional window but
resize and move it, with out causing other conflices when in battle or pvp". (1.7.0-beta2) The author, on beta1's scaling
grip: "can we resize independently in XY? like a normal window?" - its width and height now, each on its own.

The game's own window stays: Blizzard's WorldMapFrame, in the game's panel layout as before (Blizzard_WorldMap.lua
WorldMapMixin:OnLoad: RegisterUIPanel(self, { area = "left", ... })). The layout places it - UIParentPanelManager.lua's
FramePositionDelegate, a forbidden frame, sets its point - whenever a panel opens, closes or moves. The add-on writes
nothing of that layout (no SetUIPanelAttribute, no UIPanelWindows, no ShowUIPanel or UpdateUIPanelPositions of its own -
the taint that blocks other panels in combat): AFTER the game has placed and sized the windowed map, it moves and sizes
the frame with frame calls (ClearAllPoints, SetPoint, SetSize) - post-hooks on ShowUIPanel and UpdateUIPanelPositions
(taint-safe: hooksecurefunc; the game calls UpdateUIPanelPositions right after each size of its own - WorldMapMixin:Minimize,
QuestLogOwnerMixin:SetQuestLogPanelShown), the map's OnShow, its SynchronizeDisplayState (maximize / minimize). The map
window and its quest log hold no protected frame (WoW Forever 70938: Blizzard_WorldMap.xml, Blizzard_WorldMapTemplates.xml,
QuestMapFrame.xml and QuestMapFrame.lua - no secure template), so those calls are allowed in combat too: in a battleground
or an arena the map opens where it was put, at its size. (Should a later client make it protected, they wait for the
fight's end.)
A new size needs Blizzard's map fitted to it: nothing of the map does that by itself (no OnSizeChanged script - the game
calls WorldMapFrame:OnFrameSizeChanged after each size of its own). After a size of the add-on's that the game's own call
does not follow - the player's drag of the grip, a saved size at an opening - the add-on calls it: the canvas's zoom levels,
its size, its zoom reset (MapCanvasScrollControllerMixin:OnCanvasSizeChanged - Core.lua puts the zoom straight back, as after
the game's own sizes), the pins' and providers' OnCanvasSizeChanged. Blizzard's map code under the add-on's taint, as each of
Core.lua's InstantPanAndZoom: nothing protected in it - except with the Gamepad UI on (its soft cursor), where the add-on
never calls it - and noted for Core.lua's /reload line (Core.Touch: a switch to the Gamepad UI after it says to reload).
  move   drag the title bar: an invisible handle over Blizzard's title strip, between its help button and its maximize
         button; the window follows the cursor, kept on the screen
  size   drag the grip at the window's bottom right corner (outside it, clear of the map's buttons): its width and its height
         follow the cursor, each on its own, the top left corner staying - from 400 x 330 (the map without the quest log)
         to the screen's right and bottom edges; the text and the buttons keep their size, the map fills the window
         (Blizzard's canvas fits it)
  quest  (1.7.1; the player on 1.7.0, a screenshot of a tall window: "the quest pannel does not resize with the window
         changes") Blizzard's quest log beside the map is anchored at the window's top right and bottom right
         (WorldMapMixin:AttachQuestLog), and its quest list, events and map legend fill it - but the page of one quest
         does not: QuestMapFrame.xml sizes it for the game's window, DetailsFrame 308 x 502 and its text
         (QuestMapDetailsScrollFrame) 298 x 430, each anchored at its top only (WoW Forever 70938 and retail 70783 the
         same). The page and its text take the window's height over the game's, whoever sized the window - Gamepad UI
         too (two frames' heights, no map code); the full map hides the quest log: the game's heights then. Blizzard's
         rewards box at the page's foot works from the text's scroll range, so it fits itself.
         (1.8.1; a player on 1.8.0, screenshots of a tall window: "Is it possible stretch the quest panel background texture
         like the Place Story panel background texture is stretched?") Their backgrounds too: the game sizes them for its own
         window and stops short of a taller one - the page's parchment (DetailsFrame.Bg, a quest's SealMaterialBG) at most
         440 tall (QuestLogQuestDetailsMixin:AdjustBackgroundTexture), the list's (QuestScrollFrame.Background) at its
         picture's height (QuestLogScrollFrameMixin:ResizeBackground), a bare band under each. The page's: the game's sizing
         with its cap the window's height over the game's higher - cut where the picture is long enough, stretched where it
         runs out; the list's: stretched over the list where it is taller than its picture. After the game's own sizing
         (post-hooks of those two) and at each size of the window. Textures only (WoW Forever 71037 and retail 70783 the same).
  dock   (1.8.1; the author on a player's add-ons: "update what we can") what hangs outside the window's sides stays on the
         screen with it: the quest log's own tabs (QuestMapFrame.xml QuestsTab, EventsTab, MapLegendTab - TOPLEFT at the
         log's TOPRIGHT, 5 px out on WoW Forever: QuestMapFrameOverrides.GetQuestsTabAnchorOffset) and other add-ons'
         panels docked there - Spoken's Place Story panel (SpokenPlacesPanel, its Places part: 360 wide at the window's
         right, TOPLEFT and BOTTOMLEFT at the map border's right corners, never clamped to the screen) and the tab that
         reopens it. The children of the map, its border and its quest log whose middle lies outside the window and that
         reach no further in than DOCK_SLACK: their reach past each side narrows the window's place and size limits (the
         grip's drag, a move, a saved size and place - what is saved stays the player's: the window takes it back when they
         go). A child of those three shown or hidden asks again the frame after (DockSoon; as Spoken lays out its own tabs).
  full   the full map (maximized) stays the game's: its own place and size; back to the window, the player's again
  off    the setting mapWindow (default on; /unroll window): no handles, the game's last place and its own size
  reset  the map menu, /unroll window reset, /unroll reset: the game's last place and size
  Gamepad UI (Core.lua standby): no handles, and the add-on leaves the window alone - no frame call, no fitting: the
         game's own placing and sizing take it from their next run (a size the add-on gave it stays fitted till then)
Saved: db.mapWin = { x, y, w, h } - the window's top left in UIParent's units from its bottom left; the map's width (the
window's without the quest log beside it) and the window's height. (beta1 saved a scale s instead: read as that size.)
Side effect, the game's: its layout still opens other windows (character, spellbook) as if the map were in its usual
place, so they can overlap a moved map.
]]

local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)

local W = {}
ns.MapWindow = W

local MIN_W, MIN_H = 400, 330
local GRIP = 16
local HELP_CLEAR = 50 -- (the handle's left end from the title strip's: past the help button - TOPLEFT 43, 19 of the border)

local built = false
local handle, grip
local drag      -- { size = bool, cx, cy (the cursor at the press), x, y (the window's top left), w, h } - UIParent units
local ours      -- { x, y, w, h }: what the add-on set last
local game      -- { point, rel, relPoint, x, y }: where the game placed the window last (off and reset put it back)
local pending   -- a change waiting for the fight's end (a protected map frame only)

function W:Supported()
    local f = WorldMapFrame
    local b = f and f.BorderFrame
    return ns.FLAVOR ~= "era" and b ~= nil and b.TitleContainer ~= nil and b.MaximizeMinimizeFrame ~= nil
        and f.IsMaximized ~= nil and f.OnFrameSizeChanged ~= nil
end

local function Standby() return ns.Standby ~= nil and ns.Standby() end
local function Allowed()
    local db = ns.db
    return built and db ~= nil and db.mapWindow ~= false and not Standby()
end
local function Windowed()
    local f = WorldMapFrame
    return f:IsShown() and not f:IsMaximized()
end

-- (the quest log's width beside the map, while it is shown: QuestLogOwnerMixin:SetQuestLogPanelShown)
local function LogWidth()
    local f = WorldMapFrame
    local log = f.QuestLog
    return (log and log:IsShown() and f.questLogWidth) or 0
end
-- (the game's own size of the window: WorldMapMixin:Minimize, the quest log's width with it)
local function GameSize()
    local f = WorldMapFrame
    return (f.minimizedWidth or f:GetWidth()) + LogWidth(), f.minimizedHeight or f:GetHeight()
end

-- The cursor in UIParent's units.
local function Cursor()
    local x, y = GetCursorPosition()
    local es = UIParent:GetEffectiveScale()
    return x / es, y / es
end

-- (1.8.1) What hangs outside the window's sides (see the header, dock): how far past its left and its right edge, in
-- UIParent's units - read by Docked() at each placing of the add-on's and at a drag's start.
local DOCK_SLACK = 12 -- (how far inside the window a docked frame's edge may lie: a tab tucked under the border)
local dockL, dockR = 0, 0
local dockHooked = setmetatable({}, { __mode = "k" })
local DockSoon
local function Docked()
    local f = WorldMapFrame
    local ui = UIParent:GetEffectiveScale()
    local fl, fr = f:GetLeft(), f:GetRight()
    if not (fl and fr and ui and ui > 0) then return 0, 0 end
    local k = f:GetEffectiveScale() / ui
    fl, fr = fl * k, fr * k
    local l, r = 0, 0
    for _, parent in ipairs({ f, f.BorderFrame or false, f.QuestLog or false }) do
        if parent then
            for _, c in ipairs({ parent:GetChildren() }) do
                if not dockHooked[c] and c.HookScript then -- (each child once, as first seen: it may dock later)
                    dockHooked[c] = true
                    c:HookScript("OnShow", DockSoon)
                    c:HookScript("OnHide", DockSoon)
                end
                if c:IsVisible() then
                    local cl, cr = c:GetLeft(), c:GetRight()
                    if cl and cr then
                        local kc = c:GetEffectiveScale() / ui
                        cl, cr = cl * kc, cr * kc
                        local mid = (cl + cr) / 2
                        if mid > fr and cl >= fr - DOCK_SLACK then r = math.max(r, cr - fr) end
                        if mid < fl and cr <= fl + DOCK_SLACK then l = math.max(l, fl - cl) end
                    end
                end
            end
        end
    end
    return l, r
end

-- A size (the map's width, the window's height) kept between the smallest and the screen ((1.8.1) with what is docked).
local function ClampSize(w, h)
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    w = math.max(MIN_W, math.min(sw - LogWidth() - dockL - dockR, w))
    h = math.max(MIN_H, math.min(sh, h))
    return w, h
end
-- The window's top left (x, y) kept on the screen at size (fw, fh), (1.8.1) what is docked at its sides with it: all of it
-- where it fits, else its top left edge.
local function ClampPos(x, y, fw, fh)
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local lo, hi = dockL, sw - fw - dockR
    x = math.max(math.min(lo, hi), math.min(math.max(lo, hi), x))
    y = math.max(math.min(sh, fh), math.min(math.max(sh, fh), y))
    return x, y
end

-- (Blizzard's map fitted to a size the add-on gave the window - see the header; never with the Gamepad UI on: Apply and
-- Reset do nothing then)
local function Fit()
    local core = ns.Core
    if core and core.Touch then core.Touch() end
    WorldMapFrame:OnFrameSizeChanged()
end

-- (1.7.1) The quest page beside the map follows the window's height - see the header. Its heights for the game's window
-- are the ones it has before any change of the add-on's (only the add-on changes them).
local pageBase -- { page, text }: the quest page's and its text's heights for the game's window
-- (the window's height over the game's - the full map hides the quest log, QuestLogOwnerMixin:SetDisplayState: none then)
local function Extra()
    local f = WorldMapFrame
    if not f.minimizedHeight or f:IsMaximized() then return 0 end
    return f:GetHeight() - f.minimizedHeight
end

-- (1.8.1) The quest log's backgrounds over a taller window - see the header. The page's (DetailsFrame.Bg; a quest's
-- SealMaterialBG): QuestLogQuestDetailsMixin:AdjustBackgroundTexture's own sizing - the picture as wide as the page, at most
-- PAGE_BG_MAX tall, cut there - with that cap the window's height over the game's higher: cut where the picture is long
-- enough, stretched where it runs out. For the game's window the game's own result.
local PAGE_BG_MAX = 440 -- ("Capping off at 440 max height so it doesn't run out of bounds")
local function AtlasSize(texture)
    local atlas = texture and texture:GetAtlas()
    local info = atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    if info and type(info.width) == "number" and info.width > 0 and type(info.height) == "number" and info.height > 0 then
        return info.width, info.height
    end
end
local function FitPageBg(page, texture)
    local aw, ah = AtlasSize(texture)
    if not aw then return end
    local width = page:GetWidth()
    local needed = ah * width / aw
    local h = math.min(needed, PAGE_BG_MAX) + Extra()
    if h <= 0 then return end
    texture:SetWidth(width)
    texture:SetTexCoord(0, 1, 0, needed > h and h / needed or 1)
    texture:SetHeight(h)
end
-- The list's (QuestScrollFrame.Background): QuestLogScrollFrameMixin:ResizeBackground cuts the picture at the list's height
-- and keeps its own height where the list is taller; stretched over the list there. (The game reads the picture's height
-- back from the texture, a height it set itself: the atlas's here.)
local function FitListBg(list)
    local bg = list and list.Background
    local _, ah = AtlasSize(bg)
    if not ah then return end
    local h = list:GetHeight()
    if not h or h <= 0 then return end
    bg:SetHeight(h)
    bg:SetTexCoord(0, 1, 0, h < ah and h / ah or 1)
end

local function FitPage()
    local f = WorldMapFrame
    local log = f.QuestLog
    local page = log and log.DetailsFrame
    local text = page and page.ScrollFrame
    if not (text and f.minimizedHeight) then return end
    if not pageBase then pageBase = { page = page:GetHeight(), text = text:GetHeight() } end
    local extra = Extra()
    if math.abs(page:GetHeight() - (pageBase.page + extra)) > 0.01 then page:SetHeight(pageBase.page + extra) end
    if math.abs(text:GetHeight() - (pageBase.text + extra)) > 0.01 then text:SetHeight(pageBase.text + extra) end
    FitPageBg(page, page.Bg)
    FitPageBg(page, page.SealMaterialBG)
    FitListBg(log.QuestsFrame and log.QuestsFrame.ScrollFrame)
end

local function Place(x, y, w, h)
    local f = WorldMapFrame
    if math.abs(f:GetScale() - 1) > 1e-4 then f:SetScale(1) end -- (beta1's scale: gone)
    local fw, fh = w + LogWidth(), h
    local sized = math.abs(f:GetWidth() - fw) > 0.01 or math.abs(f:GetHeight() - fh) > 0.01
    if sized then f:SetSize(fw, fh) end
    x, y = ClampPos(x, y, fw, fh)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    ours = { x = x, y = y, w = w, h = h }
    if sized then Fit() end
    FitPage()
end

-- (the point the window has now: the game's, unless it is the one the add-on set)
local function Remember()
    local f = WorldMapFrame
    local point, rel, relPoint, x, y = f:GetPoint(1)
    if not point then return end
    if ours and point == "TOPLEFT" and rel == UIParent and relPoint == "BOTTOMLEFT"
        and math.abs(x - ours.x) < 0.01 and math.abs(y - ours.y) < 0.01 then return end
    game = { point, rel, relPoint, x, y }
end

-- The game's place and size again (off, reset, the full map, the Gamepad UI).
local function GiveBack()
    local f = WorldMapFrame
    if math.abs(f:GetScale() - 1) > 1e-4 then f:SetScale(1) end
    if ours and not f:IsMaximized() then
        local gw, gh = GameSize()
        if math.abs(f:GetWidth() - gw) > 0.01 or math.abs(f:GetHeight() - gh) > 0.01 then
            f:SetSize(gw, gh)
            Fit()
        end
        if game then
            f:ClearAllPoints()
            f:SetPoint(game[1], game[2], game[3], game[4], game[5])
        end
    end
    ours = nil
    FitPage()
end

-- (beta1 saved a scale: the size it showed, read as a size)
local function Saved()
    local s = ns.db and ns.db.mapWin
    if s and s.s and not s.w then
        local f = WorldMapFrame
        s.w, s.h, s.s = (f.minimizedWidth or 702) * s.s, (f.minimizedHeight or 534) * s.s, nil
    end
    return s
end

function W:Apply()
    if not built or drag then return end
    local f = WorldMapFrame
    if InCombatLockdown() and f:IsProtected() then -- (never in 70938: the map window holds no protected frame)
        pending = true
        return
    end
    pending = nil
    if Standby() then -- (the Gamepad UI: the game's window - nothing of the add-on's on it, no call into it)
        handle:Hide()
        grip:Hide()
        ours = nil
        -- ((1.7.1) but the quest page keeps the window's height - the player's until the game sizes the window, then
        -- the game's: two frames' heights, no map code)
        FitPage()
        return
    end
    local on = Allowed()
    local saved = Saved()
    if on and Windowed() and saved and (saved.x or saved.w) then
        dockL, dockR = Docked()
        local gw, gh = GameSize()
        local w, h = ClampSize(saved.w or (gw - LogWidth()), saved.h or gh)
        if saved.x then
            Place(saved.x, saved.y, w, h)
        else -- (a size and no place: where the game put it)
            local s = f:GetScale()
            Place(f:GetLeft() * s, f:GetTop() * s, w, h)
        end
    elseif not (on and Windowed()) then
        GiveBack()
    end
    local show = on and Windowed()
    handle:SetShown(show)
    grip:SetShown(show)
end

-- (after the game placed or sized the window: post-hooks, the map's OnShow - (1.8.1) and the frame after, what docked at
-- its sides in the same showing: another add-on's panel shown by its own hook of it)
local function After()
    if not built or drag or not WorldMapFrame:IsShown() then return end
    Remember()
    W:Apply()
    DockSoon()
end

-- (1.8.1) A child of the map, its border or its quest log shown or hidden (Docked hooks each): what hangs outside the
-- window read again the frame after - when every hook of that showing has run -, the window placed again if it changed.
local dockPending = false
local function DockCheck()
    dockPending = false
    if not built or drag or not ours or not Allowed() or not Windowed() then return end
    local l, r = Docked()
    if math.abs(l - dockL) > 0.5 or math.abs(r - dockR) > 0.5 then W:Apply() end
end
DockSoon = function()
    if dockPending then return end
    dockPending = true
    C_Timer.After(0, DockCheck)
end

-- A press on the handle (move) or the grip (size); the window follows the cursor until the release.
local function Track()
    local d = drag
    if not d then return end
    local cx, cy = Cursor()
    if d.size then -- (the top left stays: the window up to the screen's right and bottom edges from it - (1.8.1) what is
        -- docked at its right with it)
        local w, h = ClampSize(math.min(d.w + cx - d.cx, UIParent:GetWidth() - d.x - LogWidth() - dockR), math.min(d.h + d.cy - cy, d.y))
        Place(d.x, d.y, w, h)
    else
        Place(d.x + cx - d.cx, d.y + cy - d.cy, d.w, d.h)
    end
end
local function Begin(size)
    if not Allowed() or not Windowed() then return end
    local f = WorldMapFrame
    if InCombatLockdown() and f:IsProtected() then return end
    Remember()
    dockL, dockR = Docked()
    local cx, cy = Cursor()
    local s = f:GetScale()
    drag = { size = size, cx = cx, cy = cy, x = f:GetLeft() * s, y = f:GetTop() * s,
        w = f:GetWidth() * s - LogWidth(), h = f:GetHeight() * s }
    handle:SetScript("OnUpdate", Track)
end
local function Finish()
    if not drag then return end
    Track()
    drag = nil
    handle:SetScript("OnUpdate", nil)
    if ours and ns.db then ns.db.mapWin = { x = ours.x, y = ours.y, w = ours.w, h = ours.h } end
end

-- The game's place and size again (quiet: no chat line - a settings reset says its own).
function W:Reset(quiet)
    if ns.db then ns.db.mapWin = nil end
    if built and not drag and not Standby() then
        GiveBack()
        W:Apply()
    end
    if not quiet and ns.Print then ns.Print("the map window: the game's place and size again") end
end

local function Build()
    if built or not W:Supported() then return end
    local f = WorldMapFrame
    local b = f.BorderFrame
    local tc, mm = b.TitleContainer, b.MaximizeMinimizeFrame
    handle = CreateFrame("Frame", nil, b)
    handle:SetPoint("TOP", tc, "TOP")
    handle:SetPoint("BOTTOM", tc, "BOTTOM")
    handle:SetPoint("LEFT", tc, "LEFT", HELP_CLEAR, 0)
    handle:SetPoint("RIGHT", mm, "LEFT", -2, 0)
    handle:SetFrameLevel(tc:GetFrameLevel() + 1)
    handle:EnableMouse(true)
    handle:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then Begin(false) end end)
    handle:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then Finish() end end)
    handle:SetScript("OnHide", Finish)
    handle:Hide()

    grip = CreateFrame("Button", nil, b)
    grip:SetSize(GRIP, GRIP)
    grip:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 4, -4)
    grip:SetFrameLevel(tc:GetFrameLevel() + 1)
    grip:EnableMouse(true)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then Begin(true) end end)
    grip:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then Finish() end end)
    grip:SetScript("OnHide", Finish)
    grip:Hide()

    hooksecurefunc("ShowUIPanel", function(frame) if frame == WorldMapFrame then After() end end)
    hooksecurefunc("UpdateUIPanelPositions", After)
    f:HookScript("OnShow", After)
    if f.SynchronizeDisplayState then hooksecurefunc(f, "SynchronizeDisplayState", After) end
    -- ((1.8.1) the quest log's backgrounds after the game's own sizing of them: the page's at its showing and each quest's,
    -- the list's at each size of the list)
    local log = f.QuestLog
    local page = log and log.DetailsFrame
    if page and page.AdjustBackgroundTexture then
        hooksecurefunc(page, "AdjustBackgroundTexture", function(self, texture) FitPageBg(self, texture) end)
    end
    local list = log and log.QuestsFrame and log.QuestsFrame.ScrollFrame
    if list and list.ResizeBackground then hooksecurefunc(list, "ResizeBackground", FitListBg) end
    built = true
    if f:IsShown() then After() end
end

-- (tests) the handle, the grip, what the add-on set, the game's place, the smallest size
W.T = { Handle = function() return handle end, Grip = function() return grip end, Ours = function() return ours end,
    Game = function() return game end, Built = function() return built end, MIN_W = MIN_W, MIN_H = MIN_H }

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then W:Apply() end
    elseif event == "PLAYER_LOGIN" or (name == "Blizzard_WorldMap" and IsLoggedIn and IsLoggedIn()) then
        Build()
        if built then W:Apply() end
    end
end)
