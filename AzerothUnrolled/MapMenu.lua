--[[
Endless Map - MapMenu.lua (1.0.0; 1.2.0: the caves button; 1.3.0: the imagery button)

The round settings button in the lower right corner of the world map, and its menu; (1.2.0) left of it the caves button,
which turns the caves on and off; (1.3.0) left of that the imagery button, which switches between the drawn map and
the minimap imagery (MinimapLayer.lua).

  * The buttons are built like Blizzard's own round map button (the map-pin button, WorldMapTrackingPinButtonTemplate,
    Blizzard_WorldMapTemplates.xml:6-63): a 32 px button, the minimap's round background, a 20 px icon, the gold ring
    and the blue hover glow - the same four textures, so they look like their neighbours (Questie's button uses them
    too). Parent WorldMapFrame, frame strata HIGH, as every map overlay button (Blizzard_WorldMap.lua:455
    AddOverlayFrame; the templates carry frameStrata="HIGH"): above the map's pins and above the dungeon view, below the
    menus. We do NOT call AddOverlayFrame (it writes into Blizzard's overlayFrames list); the buttons are our own frames
    and follow the map with post-hooks only.
  * Place: the map's lower right corner; beside Blizzard's quest-log arrow (WorldMapSidePanelToggle, 32 px at
    BOTTOMRIGHT -2, 1 - Blizzard_WorldMap.lua:349) while that shows (the windowed map), in the corner itself when the
    map is maximized (the arrow hides, QuestLogOwnerMixin.lua:145-151). The other corners are taken: top left the
    floor dropdown and the map-pin button, top right Questie, bottom left the coordinates. The caves button sits left
    of the settings button, as far from it as the settings button from the arrow.
  * The menu is Blizzard's menu system (Blizzard_Menu): the button is a DropdownButton (DropdownButton.xml, as the
    map's own filter button and this addon's floor picker in Dungeon.lua), its menu opens upwards from the button.
    Without it (an older client): a plain button that prints the command list.
  * The caves button: a click turns the caves off (Options.lua caveZoom: false) or on again at the zoom they had
    (caveZoomWas; the default when that is none the setting takes); its icon, a mining pick, greyed while they are off.
    It shows the setting however that changes - the menu, /unroll cavezoom, a reset: each ends in ZoomReadout:Apply,
    which it follows. Gnomeregan, Maraudon, the Scarlet Monastery and the Timbermaw Hold tunnels show with the city
    maps, not with the caves.
  * (1.3.0) The imagery button, as Google Maps' layer button: its picture is a live preview of the OTHER look under the
    view's centre - the minimap there while the drawn map shows, the drawn map while the imagery shows (MinimapLayer.lua
    sets it, at rest) - and it wears the map-pin button's own toggled glow (UI-Minimap-ZoomButton-Toggle) while the
    imagery is on. A click switches (Options.lua imagery). WoW Forever only: elsewhere it hides.
  * Every item goes through ns.Options (Options.lua), quietly: the tick (the icon) is the answer. Nothing here is
    protected, nothing touches a Blizzard frame, GameTooltip stays untouched (the hover text is an addon frame, as
    Dungeon.lua's).

/unroll button shows / hides the buttons (Options.lua: mapButton).
]]
local ADDON, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)

local M = {}
ns.MapMenu = M

local TITLE = ns.TITLE or "Endless Map" -- (Options.lua)
local SIZE = 32
local BESIDE_X, CORNER_X, BOTTOM_Y = -36, -3, 1 -- BOTTOMRIGHT offsets: left of the quest-log arrow / in the corner
local CAVES_X = -2 -- (1.2.0) the caves button's right edge from the settings button's left: the gap left of the arrow
-- (all six files are in this client: fileDataIDs 136467, 136430, 136477, 134269, 136248, 130924; the icons are the
-- classic map item icon and the mining profession's pick; the first three are the textures of Blizzard's own map-pin
-- button)
local ART_BG = "Interface\\Minimap\\UI-Minimap-Background"
local ART_RING = "Interface\\Minimap\\MiniMap-TrackingBorder"
local ART_GLOW = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
local ART_ICON = "Interface\\Icons\\INV_Misc_Map_01"
local ART_CAVES = "Interface\\Icons\\Trade_Mining"
local ART_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ART_TOGGLE = "Interface\\Minimap\\UI-Minimap-ZoomButton-Toggle" -- (1.3.0: the map-pin button's ActiveTexture, Blizzard_WorldMapTemplates.xml:49-55)

-- The menu, top to bottom.
local TOGGLES = { "enabled", "placeNames", "dungeonIcons", "doorHints", "dungeons", "bosses", "livePins", "follow", "openFollow", "bubbles", "imagery", "zoomReadout" } -- (1.3.0: + bubbles, imagery)
local ZOOM = { "zoomStep", "maxZoom", "flySpeed", "cityZoom", "caveZoom", "questZoom", "openZoom" } -- (1.6.0: + questZoom)

local S = {} -- button, icon, caves, cavesIcon, layer, layerIcon, layerGlow, tip, tipText, dropdown (true: Blizzard's menu)

local function Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not get then return "" end
    local ok, v = pcall(get, ADDON, "Version")
    return (ok and type(v) == "string") and v or ""
end

function M:Title()
    local v = Version()
    return v ~= "" and (TITLE .. " " .. v) or TITLE
end

---------------------------------------------------------------------------
-- The menu
---------------------------------------------------------------------------
local function IsOn(key) return ns.Options:Get(key) == true end
local function Flip(key) ns.Options:Toggle(key, true) end
local function StayOpen(e)
    if e and e.SetResponse and MenuResponse and MenuResponse.Refresh then e:SetResponse(MenuResponse.Refresh) end
end

local function AddToggle(root, key)
    local s = ns.Options:Spec(key)
    if not (s and root.CreateCheckbox) or (s.avail and not s.avail()) then return end -- (1.3.0: avail - imagery)
    local e = root:CreateCheckbox(s.label, IsOn, Flip, key)
    if e and s.needs and e.SetEnabled then
        e:SetEnabled(function() return ns.Options:Usable(key) end)
    end
end

-- "Normal (1.3x, default)" / "By each city's zone (default)" / "Custom (1.41x)"
local function ValueText(s, value, name, isDefault)
    local num = (type(value) == "number") and (("%g"):format(value) .. (s.unit or "")) or nil
    if num and isDefault then return ("%s (%s, default)"):format(name, num) end
    if num then return ("%s (%s)"):format(name, num) end
    return isDefault and (name .. " (default)") or name
end

local function IsValue(pick) return ns.Options:Get(pick.key) == pick.value end
local function SetValue(pick) ns.Options:Set(pick.key, pick.value, true) end

local function AddChoices(parent, key)
    local O = ns.Options
    local s = O:Spec(key)
    if not (s and s.presets and parent.CreateButton) or (s.avail and not s.avail()) then return end -- (1.4.0: avail - retail)
    local sub = parent:CreateButton(s.label)
    if not (sub and sub.CreateRadio) then return end
    local cur, def, found = O:Get(key), O:Default(key), false
    for _, p in ipairs(s.presets) do
        if p[1] == cur then found = true end
        StayOpen(sub:CreateRadio(ValueText(s, p[1], p[2], p[1] == def), IsValue, SetValue, { key = key, value = p[1] }))
    end
    -- (a value typed as a slash command that is none of the presets: shown, so the menu never lies about it)
    if not found and cur ~= nil then
        StayOpen(sub:CreateRadio(ValueText(s, cur, "Custom", false), IsValue, SetValue, { key = key, value = cur }))
    end
end

-- (Core.lua's command handler with no command: the settings in one line and every command)
local function PrintCommands()
    if ns.RunCommand then ns.RunCommand("") end
end

function M.Generator(_, root)
    local O = ns.Options
    if not (O and root and ns.db) then return end
    if root.SetTag then root:SetTag(ns.FLAVOR == "retail" and "MENU_ENDLESS_MAP" or "MENU_AZEROTH_UNROLLED") end -- ((1.4.0-beta4) the name by the game)
    if root.CreateTitle then root:CreateTitle(M:Title()) end
    for _, key in ipairs(TOGGLES) do AddToggle(root, key) end
    if root.CreateDivider then root:CreateDivider() end
    local zoom = root.CreateButton and root:CreateButton("Zoom")
    if zoom and zoom.CreateButton then
        for _, key in ipairs(ZOOM) do AddChoices(zoom, key) end
    end
    if root.CreateDivider then root:CreateDivider() end
    if root.CreateButton then
        root:CreateButton("Slash commands", PrintCommands)
        root:CreateButton("Reset to defaults", function() O:Reset() end)
        root:CreateButton("Hide these buttons", function() O:Set("mapButton", false) end)
    end
end

---------------------------------------------------------------------------
-- The caves button (1.2.0)
---------------------------------------------------------------------------
local function CavesOn() return ns.Options:Get("caveZoom") ~= false end

local function ToggleCaves()
    local O, db = ns.Options, ns.db
    if not (O and db) then return end
    local z = O:Get("caveZoom")
    if z then
        db.caveZoomWas = z
        O:Set("caveZoom", false, true)
    elseif not O:Set("caveZoom", db.caveZoomWas, true) then
        O:Set("caveZoom", O:Default("caveZoom"), true)
    end
end

-- Its icon: the pick in colour while the caves show, greyed while they are off.
local function UpdateCaves()
    local icon = S.cavesIcon
    if not (icon and ns.Options and ns.db) then return end
    local on = CavesOn()
    icon:SetDesaturated(not on)
    if on then icon:SetVertexColor(1, 1, 1) else icon:SetVertexColor(0.6, 0.6, 0.6) end
end

local function CavesTip()
    return CavesOn() and "Caves on the map - click to hide them" or "Caves hidden - click to show them"
end

---------------------------------------------------------------------------
-- The imagery button (1.3.0)
---------------------------------------------------------------------------
local function ImageryOn() return ns.Options:Get("imagery") == true end

local function LayerTip()
    return ImageryOn() and "Minimap imagery - click for the drawn map" or "Drawn map - click for the minimap imagery"
end

-- Its picture (MinimapLayer.lua): file and texcoords (a part of a map tile or of a composite), or colour {r, g, b}
-- (the sea).
function M:SetLayerPicture(file, rgb, l, r, t, b)
    local icon = S.layerIcon
    if not icon then return end
    if file then
        icon:SetTexture(file)
        icon:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
    elseif rgb then
        icon:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    end
end

-- The glow while the imagery is on, and the picture again (the other look changed).
function M:UpdateLayer()
    local g = S.layerGlow
    if not (g and ns.Options and ns.db) then return end
    local on = ImageryOn()
    if g:IsShown() ~= on then g:SetShown(on) end
    if ns.MinimapLayer then ns.MinimapLayer:RefreshPreview(true) end
end

---------------------------------------------------------------------------
-- The hover text (an addon frame: GameTooltip stays untouched, as Dungeon.lua's tooltip)
---------------------------------------------------------------------------
local function ShowTip(owner, text)
    if owner.IsMenuOpen and owner:IsMenuOpen() then return end
    local f = S.tip
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        if f.SetFrameStrata then f:SetFrameStrata("TOOLTIP") end
        if f.SetClampedToScreen then f:SetClampedToScreen(true) end
        local edge = f:CreateTexture(nil, "BACKGROUND", nil, -8)
        edge:SetAllPoints(f)
        edge:SetColorTexture(0.62, 0.5, 0.26, 0.9)
        local bg = f:CreateTexture(nil, "BACKGROUND", nil, -7)
        bg:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        bg:SetColorTexture(0.04, 0.035, 0.03, 0.94)
        local fs = f:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "")
        fs:SetTextColor(1, 0.82, 0)
        fs:SetPoint("CENTER", f, "CENTER", 0, 0)
        S.tip, S.tipText = f, fs
    end
    S.tipText:SetText(text)
    local w = S.tipText:GetStringWidth()
    if type(w) ~= "number" or w <= 0 then w = 150 end
    f:SetSize(w + 16, 12 + 14)
    f:ClearAllPoints()
    f:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", 0, 2)
    f:Show()
end

local function HideTip()
    if S.tip then S.tip:Hide() end
end

---------------------------------------------------------------------------
-- The buttons
---------------------------------------------------------------------------
local function Press(b, icon, down)
    icon:ClearAllPoints()
    -- (as the map-pin button moves its icon while pressed: Blizzard_WorldMapTemplates.lua:413-423)
    if down then icon:SetPoint("TOPLEFT", b, "TOPLEFT", 8, -8) else icon:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -6) end
end

local function Place()
    local b, map = S.button, WorldMapFrame
    if not (b and map and map.ScrollContainer) then return end
    local arrow = map.SidePanelToggle
    local beside = arrow and arrow.IsShown and arrow:IsShown()
    b:ClearAllPoints()
    b:SetPoint("BOTTOMRIGHT", map.ScrollContainer, "BOTTOMRIGHT", beside and BESIDE_X or CORNER_X, BOTTOM_Y)
end

-- Button b as Blizzard's round map button (see the header) with icon art, and its hover text tip(); the icon texture.
local function Dress(b, art, tip)
    b:SetSize(SIZE, SIZE)
    if b.SetFrameStrata then b:SetFrameStrata("HIGH") end
    -- (it stays HIGH when the map frame's own strata is set: Blizzard_WorldMap.lua:388-391; SimpleFrameAPIDocumentation.lua:1259)
    if b.SetFixedFrameStrata then b:SetFixedFrameStrata(true) end

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(ART_BG)
    bg:SetSize(25, 25)
    bg:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -4)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(art)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- (without the item icon's own border)
    icon:SetSize(20, 20)
    Press(b, icon, false)
    if b.CreateMaskTexture then
        -- (round, so the square item icon never shows a corner past the ring, also while pressed; Blizzard cuts round
        -- icons with this file, Blizzard_AccountStoreCategoryList.xml:27. Wrap mode CLAMP as Render.lua's masks, the mode
        -- tested in this client: the mask covers exactly the icon, so nothing outside it is ever sampled)
        local mask = b:CreateMaskTexture()
        mask:SetTexture(ART_MASK, "CLAMP", "CLAMP")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
    end

    local ring = b:CreateTexture(nil, "OVERLAY", nil, 1)
    ring:SetTexture(ART_RING)
    ring:SetSize(54, 54)
    ring:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)

    if b.SetHighlightTexture then b:SetHighlightTexture(ART_GLOW, "ADD") end

    b:SetScript("OnEnter", function() ShowTip(b, tip()) end)
    b:SetScript("OnLeave", HideTip)
    b:SetScript("OnMouseDown", function() Press(b, icon, true) HideTip() end)
    b:SetScript("OnMouseUp", function() Press(b, icon, false) end)
    b:SetScript("OnHide", function() Press(b, icon, false) HideTip() end)
    return icon
end

local function Build()
    local map = WorldMapFrame
    if S.button or not (map and map.ScrollContainer and ns.db) then return end

    -- Blizzard's dropdown button (its click opens and closes the menu), else a plain button.
    local ok, b = pcall(CreateFrame, "DropdownButton", nil, map)
    if ok and b and b.SetupMenu and b.GenerateMenu then
        S.dropdown = true
    else
        if ok and b and b.Hide then b:Hide() end
        b = CreateFrame("Button", nil, map)
    end
    S.button = b
    S.icon = Dress(b, ART_ICON, function() return TITLE .. " - settings" end)

    if S.dropdown then
        if b.SetMenuAnchor and AnchorUtil and AnchorUtil.CreateAnchor then
            b:SetMenuAnchor(AnchorUtil.CreateAnchor("BOTTOMRIGHT", b, "TOPRIGHT", 0, 0)) -- (upwards: the button is at the map's bottom)
        end
        b:SetupMenu(M.Generator)
    else
        b:SetScript("OnClick", function(self)
            if MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(self, M.Generator)
            else
                PrintCommands()
            end
        end)
    end

    -- (1.2.0) the caves button, left of it (and placed with it)
    local c = CreateFrame("Button", nil, map)
    S.caves = c
    S.cavesIcon = Dress(c, ART_CAVES, CavesTip)
    c:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT", CAVES_X, 0)
    c:SetScript("OnClick", function()
        ToggleCaves()
        ShowTip(c, CavesTip())
    end)
    if ns.ZoomReadout then hooksecurefunc(ns.ZoomReadout, "Apply", UpdateCaves) end
    UpdateCaves()

    -- (1.3.0) the imagery button, left of the caves button; its toggled glow over the ring (as the map-pin button's)
    local l = CreateFrame("Button", nil, map)
    S.layer = l
    S.layerIcon = Dress(l, ART_ICON, LayerTip)
    l:SetPoint("BOTTOMRIGHT", c, "BOTTOMLEFT", CAVES_X, 0)
    local g = l:CreateTexture(nil, "OVERLAY", nil, 2)
    g:SetTexture(ART_TOGGLE)
    if g.SetBlendMode then g:SetBlendMode("ADD") end
    g:SetSize(37, 37)
    g:SetPoint("TOPLEFT", l, "TOPLEFT", -2, 1)
    g:Hide()
    S.layerGlow = g
    l:SetScript("OnClick", function()
        ns.Options:Toggle("imagery", true)
        ShowTip(l, LayerTip())
    end)

    -- The quest-log arrow comes and goes with the map's display state (QuestLogOwnerMixin:SetDisplayState).
    if map.SetDisplayState then hooksecurefunc(map, "SetDisplayState", Place) end
    map:HookScript("OnShow", Place)
    Place()
end

-- The setting -> the buttons (Options.lua calls this after /unroll button and after a reset).
function M:Apply()
    Build()
    local b, c, l = S.button, S.caves, S.layer
    if not b then return end
    if ns.db.mapButton ~= false then
        Place()
        b:Show()
        c:SetShown(ns.FLAVOR ~= "retail" or ns.RetailCaves ~= nil) -- (1.4.0: no caves on retail; 1.4.0-beta3: RetailCaves.lua's)
        l:SetShown(ns.MinimapLayer ~= nil and ns.MinimapLayer:Supported()) -- (1.3.0: WoW Forever only)
    else
        -- (an open menu closes by itself: Blizzard's menu follows its owner, Menu.lua:2504-2510)
        b:Hide()
        c:Hide()
        l:Hide()
    end
    M:UpdateLayer()
end

function M:Button() return S.button end
function M:CavesButton() return S.caves end
function M:LayerButton() return S.layer, S.layerIcon, S.layerGlow end -- (1.3.0)
function M:UsesBlizzardMenu() return S.dropdown == true end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, name)
    -- (never before the login, as Core.lua's Setup)
    if event == "PLAYER_LOGIN" or (name == "Blizzard_WorldMap" and IsLoggedIn and IsLoggedIn()) then M:Apply() end
end)
