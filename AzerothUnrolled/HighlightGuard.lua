local _, ns = ...

--[[
HighlightGuard (1.0.0): Blizzard's zone hover highlight on a CONTINENT map
(MapHighlightPinMixin:Refresh, Blizzard_SharedMapDataProviders/MapHighlightDataProvider.lua) is drawn from a small, soft
texture made for the continent's own view. Where no zone map can show the view (Orgrimmar's north half lies outside
Durotar's map, a view across a zone border), the map under ours stays the continent, and when we zoom far past that
continent's own view the texture is magnified into big blurry blocks over the map. Past DEEP x of the continent's own
zoom - where our zone art has taken over (Render LOD_C0) - the highlight is hidden.
A post-hook (hooksecurefunc never changes what Blizzard's code does; it only hides the texture Blizzard just showed), on
the one highlight pin of the world map. Nothing else of Blizzard's map is touched. The hook goes in after login only -
then every addon has loaded.
]]

local DEEP = 2.5

local hooked, loggedIn = false, false

local function Deep()
    local db, core = ns.db, ns.Core
    if not (db and db.enabled ~= false and core and core.Cam and core.State) or core.State() == "off" then return false end
    local e = ns.maps and WorldMapFrame and ns.maps[WorldMapFrame:GetMapID()]
    if not (e and e.mapType and e.mapType <= (ns.MAPTYPE_CONTINENT or 2)) then return false end
    local cam, v = core.Cam()
    if not (cam and v and v.W and v.H and v.W > 0 and v.H > 0 and cam.vw and cam.vw > 0) then return false end
    return ns.ZoomOf(v, e, cam.vw) > DEEP
end

local function Hook()
    if hooked or not (WorldMapFrame and type(WorldMapFrame.dataProviders) == "table") then return end
    for dp in pairs(WorldMapFrame.dataProviders) do
        local pin = type(dp) == "table" and dp.pin
        if type(pin) == "table" and pin.HighlightTexture and pin.SetupHighlightPulse and type(pin.Refresh) == "function" then
            hooksecurefunc(pin, "Refresh", function(self)
                if Deep() and self.HighlightTexture:IsShown() then self.HighlightTexture:Hide() end
            end)
            hooked = true
            return
        end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then loggedIn = true end
    if loggedIn and (event == "PLAYER_LOGIN" or name == "Blizzard_WorldMap") then Hook() end
end)
