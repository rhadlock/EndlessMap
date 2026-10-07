--[[
Azeroth Unrolled - OptionsPanel.lua (1.0.0)

The same settings as the map menu, on the game's own Settings page: Esc > Options > AddOns > Azeroth Unrolled. It is the
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

local P = {}
ns.OptionsPanel = P

local TITLE = ns.TITLE or "Azeroth Unrolled" -- (Options.lua)
local TOGGLES = { "enabled", "placeNames", "dungeonIcons", "doorHints", "dungeons", "bosses", "livePins", "follow", "openFollow", "bubbles", "imagery", "zoomReadout", "mapButton" } -- (1.3.0: + bubbles, imagery)
local CHOICES = { "zoomStep", "maxZoom", "flySpeed", "cityZoom", "caveZoom", "openZoom" }
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

    local category = St.RegisterVerticalLayoutCategory(TITLE)
    if not category then return end

    for _, key in ipairs(TOGGLES) do
        local s = O:Spec(key)
        if s and not (s.avail and not s.avail()) then -- (1.3.0: avail - the imagery, WoW Forever only)
            local setting = St.RegisterProxySetting(category, "AZEROTHUNROLLED_" .. key:upper(), St.VarType.Boolean, s.label,
                O:Default(key) == true,
                function() return O:Get(key) == true end,
                function(value) O:Set(key, value and true or false, true) end)
            if setting then St.CreateCheckbox(category, setting, s.tip) end
        end
    end

    if St.CreateDropdown and St.CreateControlTextContainer then
        for _, key in ipairs(CHOICES) do
            local s = O:Spec(key)
            if s and s.presets then
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
                local setting = St.RegisterProxySetting(category, "AZEROTHUNROLLED_" .. key:upper(), St.VarType.Number, s.label,
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
ev:SetScript("OnEvent", function() P:Setup() end)
