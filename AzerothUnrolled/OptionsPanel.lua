--[[
Endless Map - OptionsPanel.lua (1.0.0)

The same settings as the map menu, on the game's own Settings page: Esc > Options > AddOns > Endless Map. It is the
place players look for an addon's options, and the way back for those who hid the map button.

Built from the list in Options.lua with Blizzard's settings API (Blizzard_Settings_Shared/Blizzard_Settings.lua:
RegisterVerticalLayoutCategory :154, RegisterProxySetting :178, CreateCheckbox :388, CreateDropdown :410,
CreateControlTextContainer :261, RegisterAddOnCategory :134 - the calls of Blizzard_ImplementationReadme.lua). Proxy
settings: the page reads and writes through ns.Options, so a tick here does exactly what the menu and the slash
commands do. Registration goes through Blizzard's own secure delegate (Blizzard_SettingsInbound.lua); this file never
opens the Settings panel itself and touches no Blizzard frame. Any piece of the API missing: no page, nothing else
changes (the map button and the slash commands do not depend on this file).
]]
local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)

local P = {}
ns.OptionsPanel = P

local TITLE = ns.TITLE or "Endless Map" -- (Options.lua)
local TOGGLES = { "enabled", "placeNames", "dungeonIcons", "doorHints", "dungeons", "bosses", "livePins", "follow", "openFollow", "bubbles", "imagery", "zoomReadout", "mapButton", -- (1.3.0: + bubbles, imagery)
    "newsAfterUpdate" } -- (1.6.1: Share.lua's What's new)
local CHOICES = { "zoomStep", "maxZoom", "flySpeed", "cityZoom", "caveZoom", "questZoom", "openZoom" } -- (1.6.0: + questZoom)
local NONE = 0 -- (a dropdown value must be a number: stands for cityZoom = false)

local function PresetText(s, value, name, isDefault)
    local num = (type(value) == "number") and (("%g"):format(value) .. (s.unit or "")) or nil
    local text = num and ("%s (%s)"):format(name, num) or name
    return isDefault and (text .. " - default") or text
end

local function Register()
    local O, St = ns.Options, Settings
    if P.category or not (O and ns.db and St) then return end
    if not (St.RegisterVerticalLayoutCategory and St.RegisterProxySetting and St.RegisterAddOnCategory and St.CreateCheckbox
        and St.VarType and St.VarType.Boolean and St.VarType.Number) then return end

    local category, layout = St.RegisterVerticalLayoutCategory(TITLE)
    if not category then return end

    for _, key in ipairs(TOGGLES) do
        local s = O:Spec(key)
        if s and not (s.avail and not s.avail()) then -- (1.3.0: avail - the imagery, WoW Forever only)
            local setting = St.RegisterProxySetting(category, ns.SLASH .. "_" .. key:upper(), St.VarType.Boolean, s.label,
                O:Default(key) == true,
                function() return O:Get(key) == true end,
                function(value) O:Set(key, value and true or false, true) end)
            if setting then St.CreateCheckbox(category, setting, s.tip) end
        end
    end

    if St.CreateDropdown and St.CreateControlTextContainer then
        for _, key in ipairs(CHOICES) do
            local s = O:Spec(key)
            if s and s.presets and not (s.avail and not s.avail()) then -- (1.4.0: avail - retail)
                local def = O:Default(key)
                local function Options()
                    local container = St.CreateControlTextContainer()
                    local cur, found = O:Get(key), false
                    for _, p in ipairs(s.presets) do
                        if p[1] == cur then found = true end
                        container:Add(p[1] or NONE, PresetText(s, p[1], p[2], p[1] == def))
                    end
                    if not found and cur ~= nil then container:Add(cur or NONE, PresetText(s, cur, "Custom", false)) end
                    return container:GetData()
                end
                local setting = St.RegisterProxySetting(category, ns.SLASH .. "_" .. key:upper(), St.VarType.Number, s.label,
                    def or NONE,
                    function() return O:Get(key) or NONE end,
                    function(value)
                        if value == NONE and s.orFalse then value = false end
                        O:Set(key, value, true)
                    end)
                if setting then St.CreateDropdown(category, setting, Options, s.tip) end
            end
        end
    end

    -- (1.6.1, Share.lua) what's new - with the link to share - and a bug report to copy; nothing is sent from the game
    if ns.Share and type(layout) == "table" and layout.AddInitializer and CreateSettingsButtonInitializer then
        layout:AddInitializer(CreateSettingsButtonInitializer("What's new", "Show",
            function() ns.Share:ShowNews(false) end,
            "What changed in this version of Endless Map, with its download link to copy and share. Nothing is sent from the game.", true))
        layout:AddInitializer(CreateSettingsButtonInitializer("Report a bug", "Make a report",
            function() ns.Share:ShowReport() end,
            "A ready-made bug report - versions, settings, the add-on's errors - to copy and paste in Endless Map's bug form on GitHub. Nothing is sent from the game.", true))
    end

    St.RegisterAddOnCategory(category)
    P.category = category
end

-- (once, when the saved settings are there; a failure leaves the game's Settings page without ours and nothing else)
function P:Setup()
    if P.tried then return end
    P.tried = true
    local ok, err = pcall(Register)
    if not ok then P.error = err end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event)
    -- (1.4.0, retail: a login in combat registers the page when the combat ends, as 1.4.0-beta0's page did)
    if event == "PLAYER_LOGIN" and ns.FLAVOR == "retail" and InCombatLockdown and InCombatLockdown() then
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then self:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    P:Setup()
end)
