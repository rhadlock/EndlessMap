--[[
Endless Map - Pins.lua (1.4.0-beta10 as RetailPins.lua, retail only; 1.6.0: both games - AzerothUnrolled_Standard.toc
after RetailDoors.lua, AzerothUnrolled.toc after ForeverWays.lua; WoW Forever's part at the end of this header)

The markers of every map in view, each with its own map's picture - the player on 1.4.0-beta9: "the instant diamonds are
missing for most instances", "even the dark portal is missing from the map", "when we shows quests and FP's is also not
consist across all the zones. this should be unified", and at the Maelstrom "no fp's or other poi are visible at any zoom
level". Until 1.4.0-beta9 these were Blizzard's pins: Blizzard's map pins the markers of the ONE map it shows (Core.lua
lines it up with the view: the zone under the view's centre, else the continent), laid out as Blizzard has that map -
every other zone in view had none, and where our layout differs (the Maelstrom's places pulled together, the continents
at their true shape over Azeroth) they stood beside their places. Here every map the add-on draws brings its own:

  * FLIGHT MASTERS on the maps Blizzard pins them on (RETAIL_PLACES.taxi): C_TaxiMap.GetTaxiNodesForMap - the game's
    icon of each (its atlas: a discovered one, one not discovered yet - as Blizzard's map shows both), its name; the other
    faction's left out (Blizzard's FlightPointDataProvider:ShouldShowTaxiNode). WoW Forever's flight masters (Labels.lua
    LoadTaxi) were names with a dot.
  * POINTS OF INTEREST: C_AreaPoiInfo.GetAreaPOIForMap (the portals of a city, the places a map marks - as the game
    lists them: none at the Dark Portal for the player of 1.4.0-beta11), GetEventsForMap (an event on now),
    GetDelvesForMap (the delves; Blizzard's map filter "showDelveEntrancesOnMap" kept) -
    each C_AreaPoiInfo.GetAreaPOIInfo's icon (its atlas, its texture kit's, else the minimap's POI icons) and name.
  * THEIR ZOOM: a map's markers come and go with that map's own picture (Render:MapAlpha): a zone's with its zone map (its
    land cells - every zone of a continent at once, 1.4.0-beta9), a continent's own list while its picture shows and its
    zones' maps do not - as Blizzard's map shows a continent's markers on the continent and a zone's on the zone, here every
    map drawn at once. Labels.lua places them (it.mapBand, it.pic): a name gives way where another lies, the icon stays.
  * BLIZZARD'S OWN PINS of these kinds (FlightPointPinTemplate, AreaPOIPinTemplate, AreaPOIEventPinTemplate,
    DelveEntrancePinTemplate, the doors' DungeonEntrancePinTemplate - RetailDoors.lua draws every door -, (1.4.0-beta13)
    the explored pieces' MapExplorationPinTemplate - each map's pieces are its own picture's: RetailRender.lua) are hidden -
    a post-hook on WorldMapFrame:AcquirePin, as HighlightGuard.lua's: Blizzard's code runs as it does, its pin of one map
    goes; while the add-on stands aside (off, Blizzard's map of a dungeon) they are Blizzard's again.
  * THE HOVER and THE CLICK: an add-on frame names the marker (its name, its description - a flight master not found yet,
    a delve's, an event's time left); a click sets the game's waypoint to it and a second takes it off
    (C_SuperTrack.SetSuperTrackedMapPin - Blizzard's pin's own left click), at rest. (1.6.2) Every click is the click of
    the Blizzard pin ours stands for, step by step: "The hover and the click" below.
  * (1.4.0-beta11) QUESTS the same way - the player on 1.4.0-beta9: "when we shows quests and FP's is also not consist
    across all the zones. this should be unified": every map in view its own, as Blizzard's providers pick them for that
    map (12.1.5's QuestDataProvider, WorldMap_WorldQuestDataProvider, BonusObjectiveDataProvider, QuestOfferDataProvider,
    read from the client): the quest log's quests on the map (C_QuestLog.GetQuestsOnMap) and the tracked quest's next
    waypoint, the world quests and bonus objectives (C_TaskQuest.GetQuestsOnMap), the quests on offer (C_QuestLine, the
    tasks that start one) and the quest hubs (C_AreaPoiInfo.GetQuestHubsForMap) - the offers a hub stands for come in at
    its map's own zoom 2 (Blizzard's map at its deepest: QuestOfferDataProviderMixin:IsSuppressionDisabled). Their look is
    Blizzard's: POIButton.lua's round button of the quest's classification under its icon (in progress, ready to turn in,
    the waypoint's arrow, a world quest's type), the offers' icons (questOfferPinData). No names printed (it.iconOnly):
    Blizzard's map prints none; the hover names them, the click is POIButtonMixin:OnClick's - (1.6.2) the quest onto the
    quest tracker and selected (C_QuestLog.AddQuestWatch, C_SuperTrack.SetSuperTrackedQuestID) - or sets the waypoint to
    an offer. Blizzard's quest pins hidden as the others. Never through
    QuestCache, GetQuestsOnMapCached or GetTasksOnMapCached (Blizzard's Lua caches - an entry made by the add-on would taint
    the quest tracker that reads them: Core.lua QuestSafe): the C_ calls only.
  * (1.6.0) WOW FOREVER: its map is retail's (Blizzard_WorldMap's providers, POIButton.lua - the same files), and it pins a
    zone's quests only on that zone's own map (MapUtil.ShouldMapTypeShowQuests), which Core.lua lines up with the view
    only from the zone's own fit - Elwynn Forest from world zoom 12.88x. The player on 1.5.0: "can we make quest icons
    visable from higher up? like around 10x zoom level". Here the QUESTS of every continent and zone near the view (the
    log's, the tracked one's waypoint, world quests, bonus objectives, offers), read and drawn as on retail: a zone's
    from the world zoom of the quest switch (questG - /unroll questzoom, default QUEST_G 10x; Labels.lua it.worldOn) or
    from its own fit if that comes first (it.orOwn), a continent's - the tracked quest, which Blizzard pins on a
    continent - from that continent's own fit (it.ownFrom) up to the switch (it.worldOff), where its zones' take over. Its flight masters (Labels.lua LoadTaxi) and points of interest
    (Blizzard's, laid out as ours) stay as they were: of Blizzard's pins only the quests' are hidden, and only while ours
    stand in - the label layer on, at rest too, the switch not off (/unroll questzoom off: Blizzard's own, as before).
Nothing here writes a Blizzard frame but the alpha of its pins of these kinds (and, on a Shift-click while a chat box is
open, the quest's link that Blizzard's own ChatFrameUtil puts there - as its pin's click does); every call through pcall,
plain values only.
]]
local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)
-- ((1.6.0) WoW Forever too, for its quests - the header; Classic Era's map is its own, without the quests of the log)
local RETAIL = ns.FLAVOR == "retail"
if not (RETAIL or ns.FLAVOR == "forever") then return end

local P = ns.RETAIL_PLACES
local Labels = ns.Labels
if (RETAIL and type(P) ~= "table") or not (Labels and Labels.Add) then return end

local PN = {}
ns.Pins = PN

local STYLE = Labels.STYLE
-- (the names: WoW Forever's flight master yellow; a point of interest Blizzard's gold; their icons the game's own - it.pic)
STYLE.flightPin = { size = 9, r = 1.00, g = 1.00, b = 0.60, prio = 20, icon = true, gate = "flightPaths" }
STYLE.poiPin = { size = 10, r = 1.00, g = 0.86, b = 0.45, prio = 35, icon = true, gate = "labels" }
-- ((1.4.0-beta11) a quest's and an offer's icons placed before every name but a continent's - the names give way to them -,
-- and drawn whatever lies there (it.always): Blizzard's quest pins lie over its map's names and over one another)
STYLE.questPin = { size = 10, r = 1.00, g = 0.82, b = 0.00, prio = 52, icon = true, gate = "quests" }
STYLE.offerPin = { size = 10, r = 1.00, g = 0.82, b = 0.00, prio = 51, icon = true, gate = "quests" }

local FP_SIZE = 18                 -- (px: Blizzard's flight point pin, BaseMapPoiPinMixin at its scale 1)
local POI_SIZE = 20                -- (px: an area POI's icon, the long side)
local QUEST_BASE, QUEST_ICON = 28, 18 -- (px: POIButton's 32-px button and its icon, at the map's pin scale)
local OFFER_SIZE = 20              -- (px: QuestOfferPinTemplate's 20-px icon)
local OFFER_SPLIT = 2.0            -- (a quest hub's offers: from its map's own zoom 2 - see the header)
local READ_EVERY = 1.0             -- (s: maps marked changed are read again at most this often - QUEST_LOG_UPDATE comes
                                   -- in bursts; Blizzard's world quests refresh every 0.5 s while its map shows)
local REQUEST_EVERY = 0.25         -- (s: C_QuestLine.RequestQuestLinesForMap, one map at a time - see ReadOffers)
local lastRequest = -1e9
local NEAR = 0.5                   -- (a map is read while its rect lies within this many views of the view)
local LOAD_ZOOM = 0.25             -- (... and its zoom is at least this: a zone 1/4 of the view wide)
local HIT_PAD = 3
local TEMPLATES = { FlightPointPinTemplate = true, AreaPOIPinTemplate = true, AreaPOIEventPinTemplate = true,
    DelveEntrancePinTemplate = true, DungeonEntrancePinTemplate = true,
    -- ((1.4.0-beta13) Blizzard's explored pieces of the ONE map its canvas rests on, drawn over every picture of ours:
    -- which pieces showed followed the view's centre - and its mouse-over ones the cursor: on Azeroth the blurred drawing of
    -- Khaz Algar, 1084 x 744 px, over our Khaz Algar's map whenever the cursor lay on it, so the same zoom looked two ways -
    -- the player on 1.4.0-beta12, "khaz algar maps are still depdant on xy position". Each map's pieces are its own picture's
    -- top part, at rest as moving: RetailRender.lua)
    MapExplorationPinTemplate = true,
    -- ((1.4.0-beta11) the quests' - Blizzard_WorldMap.lua's providers' templates)
    QuestPinTemplate = true, QuestOfferPinTemplate = true, QuestHubPinTemplate = true, WorldMap_WorldQuestPinTemplate = true,
    WorldQuestPinTemplate = true, BonusObjectivePinTemplate = true, ThreatObjectivePinTemplate = true }
if not RETAIL then
    -- ((1.6.0) WoW Forever: the quests' alone, their hubs among them - QuestOfferDataProvider draws a zone's hubs and
    -- keeps back the offers one stands for; ours do the same (Read, ReadOffers))
    TEMPLATES = { QuestPinTemplate = true, QuestOfferPinTemplate = true, QuestHubPinTemplate = true,
        WorldMap_WorldQuestPinTemplate = true, WorldQuestPinTemplate = true, BonusObjectivePinTemplate = true,
        ThreatObjectivePinTemplate = true }
end
-- ((1.6.0, WoW Forever) the quest switch: the world zoom from which a zone's quests show - the player asked for about 10x
-- (/unroll questzoom, ZoomReadout.lua) -, a continent's up to it; false: off, Blizzard's own quest pins as before 1.6.0
local QUEST_G, QUEST_G_MIN, QUEST_G_MAX = 10, 3, 25
local questG = QUEST_G
PN.QUEST_G, PN.QUEST_G_MIN, PN.QUEST_G_MAX = QUEST_G, QUEST_G_MIN, QUEST_G_MAX
-- (Enum.SuperTrackingMapPinType when the enum is missing: AreaPOI 0, QuestOffer 1, TaxiNode 2)
local MAPPIN_POI, MAPPIN_OFFER, MAPPIN_TAXI = 0, 1, 2

local maps = {}                    -- [entry] = { items = { [key] = item }, dirty }
local pins = {}                    -- every marker item (hit test)
local hidden = setmetatable({}, { __mode = "k" }) -- Blizzard's pins hidden here
local hooked = setmetatable({}, { __mode = "k" }) -- (their SetAlpha post-hooked once)
local hiding = false

local function Plain(v, kind) return type(v) == kind and not (issecretvalue and issecretvalue(v)) end
local function Num(v) return Plain(v, "number") and v == v end
local function Str(v) return Plain(v, "string") and v ~= "" end

local function XY(pos)
    if type(pos) ~= "table" then return nil end
    local x, y
    if pos.GetXY then
        local ok, a, b = pcall(pos.GetXY, pos)
        if ok then x, y = a, b end
    else
        x, y = pos.x, pos.y
    end
    if Num(x) and Num(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, r = pcall(fn, ...)
    if ok then return r end
end

local function CVarOn(name)
    if not GetCVarBool then return true end
    local ok, v = pcall(GetCVarBool, name)
    return not ok or v ~= false
end

-- The icon of an atlas, at most `side` px on its long side (its own shape); nil when the client has no such atlas
local function AtlasPic(atlas, side)
    if not Str(atlas) then return nil end
    local w, h = side, side
    if C_Texture and C_Texture.GetAtlasInfo then
        local info = Call(C_Texture.GetAtlasInfo, atlas)
        if type(info) ~= "table" then return nil end
        if Num(info.width) and Num(info.height) and info.width > 0 and info.height > 0 then
            local k = side / math.max(info.width, info.height)
            w, h = info.width * k, info.height * k
        end
    end
    return { atlas = atlas, w = w, h = h }
end

-- An area POI's icon as Blizzard's pin draws it (BaseMapPoiPinMixin:SetTexture): its atlas - with its texture kit's prefix
-- (ATLAS_WITH_TEXTURE_KIT_PREFIX) -, else the minimap's POI icons at its index
local function PoiPic(info)
    local atlas = info.atlasName
    if Str(atlas) and Str(info.uiTextureKit) then
        local kit = (ATLAS_WITH_TEXTURE_KIT_PREFIX or "%s-%s"):format(info.uiTextureKit, atlas)
        local p = AtlasPic(kit, POI_SIZE)
        if p then return p end
    end
    local p = AtlasPic(atlas, POI_SIZE)
    if p then return p end
    if Num(info.textureIndex) and C_Minimap and C_Minimap.GetPOITextureCoords then
        local ok, x1, x2, y1, y2 = pcall(C_Minimap.GetPOITextureCoords, info.textureIndex)
        if ok and Num(x1) and Num(x2) and Num(y1) and Num(y2) then
            return { file = "Interface/Minimap/POIIcons", tc = { x1, x2, y1, y2 }, w = POI_SIZE, h = POI_SIZE }
        end
    end
end

local function SamePic(a, b)
    if a == b then return true end
    if not (a and b) then return false end
    return a.atlas == b.atlas and a.file == b.file and a.w == b.w and a.h == b.h and a.base == b.base
        and (a.tint and a.tint[1]) == (b.tint and b.tint[1])
end

---------------------------------------------------------------------------
-- A map's markers (read as it comes near; again when the game says they changed)
---------------------------------------------------------------------------
-- ((1.6.0, WoW Forever) when a quest's marker shows (Labels.lua): a zone's from the switch's world zoom - or from the zone's
-- own fit, where Blizzard's map of it showed it, should that come first (a large zone: the Barrens) -, a continent's from
-- its own fit up to the switch (MapUtil.ShouldMapTypeShowQuests: a continent pins the tracked quest alone). On retail with
-- its map's picture (it.mapBand).
local function Band(it)
    if RETAIL then return end
    local zoneLike = (it.owner.mapType or 3) > 2
    it.worldOn, it.orOwn = zoneLike and questG or nil, zoneLike and 1 or nil
    it.worldOff, it.ownFrom = (not zoneLike) and questG or nil, (not zoneLike) and 1 or nil
end

-- (the item, or nil; quest: (1.4.0-beta11) its icon alone - no name printed -, drawn whatever lies there)
local function Upsert(e, M, seen, key, px, py, text, kind, style, pic, info, quest)
    if not (text and pic) then return end
    local x, y = e.x0 + px * (e.x1 - e.x0), e.y0 + py * (e.y1 - e.y0)
    local it = M.items[key]
    if it then
        if it.text ~= text or not SamePic(it.pic, pic) or it.style ~= style then
            Labels:Reset(it)
            it.text, it.pic, it.style = text, pic, style
        end
        if it.x ~= x or it.y ~= y then Labels:Moved() end -- ((1.4.0-beta16) its grid)
        it.x, it.y, it.off, it.info = x, y, nil, info
    else
        it = Labels:Add(x, y, text, kind, e)
        if not it then return end
        it.style, it.pic, it.mapBand, it.info, it.pin = style, pic, RETAIL or nil, info, true
        M.items[key] = it
        pins[#pins + 1] = it
    end
    it.iconOnly, it.always, it.zmin = quest or nil, quest or nil, nil
    Band(it)
    seen[key] = true
    return it
end

local function ReadTaxi(e, M, seen)
    if not (P.taxi and P.taxi[e.id] and C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return end
    local nodes = Call(C_TaxiMap.GetTaxiNodesForMap, e.id)
    if type(nodes) ~= "table" then return end
    local faction
    local okf, f = pcall(UnitFactionGroup, "player")
    if okf and Str(f) then faction = f end
    for _, node in ipairs(nodes) do
        if type(node) == "table" and Num(node.nodeID) then
            local fac = Num(node.faction) and node.faction or 0
            -- (Blizzard's ShouldShowTaxiNode: Enum.FlightPathFaction 1 Horde, 2 Alliance - that faction's only)
            local mine = (fac == 0) or (fac == 1 and faction == "Horde") or (fac == 2 and faction == "Alliance")
            local px, py = XY(node.position)
            if mine and px and Str(node.name) then
                local atlas = node.atlasName
                if Str(atlas) and Str(node.textureKit) then
                    local kit = (ATLAS_WITH_TEXTURE_KIT_PREFIX or "%s-%s"):format(node.textureKit, atlas)
                    if AtlasPic(kit, FP_SIZE) then atlas = kit end
                end
                local pic = AtlasPic(Str(atlas) and atlas or "TaxiNode_Neutral", FP_SIZE)
                local info = { kind = "taxi", id = node.nodeID, name = node.name, undiscovered = node.isUndiscovered == true, faction = fac }
                Upsert(e, M, seen, "t" .. node.nodeID, px, py, node.name:match("^[^,]+") or node.name, "flight", STYLE.flightPin, pic, info)
            end
        end
    end
end

local function ReadPois(e, M, seen, list, kind, hubs)
    if type(list) ~= "table" then return end
    for _, id in ipairs(list) do
        if Num(id) and not seen["p" .. id] then
            local info = Call(C_AreaPoiInfo.GetAreaPOIInfo, e.id, id)
            if type(info) == "table" then
                local px, py = XY(info.position)
                if px and Str(info.name) then
                    local inf = { kind = kind, id = id, name = info.name, desc = Str(info.description) and info.description or nil }
                    Upsert(e, M, seen, "p" .. id, px, py, info.name, "poi", STYLE.poiPin, PoiPic(info), inf)
                    if hubs then hubs[#hubs + 1] = { id = id, link = Num(info.linkedUiMapID) and info.linkedUiMapID or nil } end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- (1.4.0-beta11) Quests (the header's QUESTS)
---------------------------------------------------------------------------
local QC = (Enum and Enum.QuestClassification) or { Important = 0, Legendary = 1, Campaign = 2, Calling = 3, Meta = 4,
    Recurring = 5, Questline = 6, Normal = 7, BonusObjective = 8, Threat = 9, WorldQuest = 10 }
local QT = (Enum and Enum.QuestTagType) or { Profession = 1, Normal = 2, PvP = 3, PetBattle = 4, Dungeon = 6, Invasion = 7,
    Raid = 8, FactionAssault = 12, Islands = 13, Threat = 14, DragonRiderRacing = 16, Capstone = 17, WorldBoss = 18, Prey = 19 }
local EPIC = Enum and Enum.WorldQuestQuality and Enum.WorldQuestQuality.Epic or 2
local ZONE = 3 -- (Enum.UIMapType.Zone)

-- POIButton.lua: a quest's round button by its classification (in progress and ready to turn in alike; a calling's the
-- campaign's), and the icon on it once it is ready to turn in
local BUTTON = { [QC.Legendary] = "UI-QuestPoiLegendary-QuestNumber", [QC.Campaign] = "UI-QuestPoiCampaign-QuestNumber",
    [QC.Calling] = "UI-QuestPoiCampaign-QuestNumber", [QC.Recurring] = "UI-QuestPoiRecurring-QuestNumber",
    [QC.Important] = "UI-QuestPoiImportant-QuestNumber", [QC.Meta] = "UI-QuestPoiWrapper-QuestNumber",
    [QC.Threat] = "UI-QuestPoiCampaign-QuestNumber" }
local TURN_IN = { [QC.Legendary] = "UI-QuestPoiLegendary-QuestBangTurnIn", [QC.Campaign] = "UI-QuestPoiCampaign-QuestBangTurnIn",
    [QC.Calling] = "UI-DailyQuestPoiCampaign-QuestBangTurnIn", [QC.Recurring] = "UI-QuestPoiRecurring-QuestBangTurnIn",
    [QC.Important] = "UI-QuestPoiImportant-QuestBangTurnIn", [QC.Meta] = "UI-QuestPoiWrapper-QuestBangTurnIn" }
-- QuestOfferDataProvider.lua questOfferPinData: an offer's icon by its classification (none: no pin)
local OFFER = { [QC.Normal] = "QuestNormal", [QC.Questline] = "QuestNormal", [QC.Recurring] = "UI-QuestPoiRecurring-QuestBang",
    [QC.Meta] = "quest-wrapper-available", [QC.Calling] = "Quest-DailyCampaign-Available",
    [QC.Campaign] = "Quest-Campaign-Available", [QC.Legendary] = "UI-QuestPoiLegendary-QuestBang",
    [QC.Important] = "importantavailablequesticon" }
-- QuestUtils.lua GetWorldQuestAtlasInfo: a world quest's icon by its type
local WQ_ICON = { [QT.Capstone] = "worldquest-Capstone", [QT.PvP] = "worldquest-icon-pvp-ffa",
    [QT.PetBattle] = "worldquest-icon-petbattle", [QT.Dungeon] = "worldquest-icon-dungeon", [QT.Raid] = "worldquest-icon-raid",
    [QT.Invasion] = "worldquest-icon-burninglegion", [QT.Islands] = "poi-islands-table",
    [QT.DragonRiderRacing] = "worldquest-icon-race", [QT.Prey] = "worldquest-prey-crystal",
    [QT.WorldBoss] = "worldquest-icon-boss" }
local DIM = { 0.6, 0.6, 0.6 } -- (an offer Blizzard draws at half alpha - a trivial quest's: greyed)

local function Yes(fn, ...) return type(fn) == "function" and Call(fn, ...) == true end
local function Tracked()
    local q = C_SuperTrack and Call(C_SuperTrack.GetSuperTrackedQuestID)
    if Num(q) and q > 0 then return q end
end
local function Classification(q)
    local c = C_QuestInfoSystem and Call(C_QuestInfoSystem.GetQuestClassification, q)
    return Num(c) and c or QC.Normal
end
-- (fractions of a map: plain numbers in 0 - 1)
local function Frac(x, y)
    if Num(x) and Num(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
end
-- POIButton's look: icon atlas over button atlas (the super-tracked one's own button); nil without the icon
local function QuestPic(button, icon, selected, side)
    local p = AtlasPic(icon, side or QUEST_ICON)
    if not p then return nil end
    local b = selected and button .. "-SuperTracked" or button
    if not AtlasPic(b, QUEST_BASE) then b = button end
    if AtlasPic(b, QUEST_BASE) then p.base, p.bw, p.bh = b, QUEST_BASE, QUEST_BASE end
    return p
end
local function Real(e) return (e.node and e.node.ut) or e.mapType end -- (an open-world city's own UiMap type: RetailTree ut)

-- QuestDataProvider: the quest log's quests on map e and the tracked quest's next waypoint
local function ReadQuests(e, M, seen)
    local QL = C_QuestLog
    if not (QL and QL.GetQuestsOnMap) or not CVarOn("questPOI") then return end
    local st = Tracked()
    -- ((1.6.0) QuestDataProviderMixin:ShouldShowQuest: while a quest's details are open in the quest log only that quest,
    -- and the waypoint is the focused quest's, else the tracked one's - QuestMapFrame_GetFocusedQuestID, read only)
    local focused = Call(QuestMapFrame_GetFocusedQuestID)
    if not (Num(focused) and focused > 0) then focused = nil end
    local wq0 = focused or st
    local zoneLike = (e.mapType or ZONE) > 2 -- (MapUtil.ShouldMapTypeShowQuests: not the Cosmic map, a world, a continent)
    local tasksToo = C_TaskQuest and Yes(C_TaskQuest.DoesMapShowTaskQuestObjectives, e.id)
    local function Add(q, px, py, waypoint)
        if not (Num(q) and px) then return end
        if focused and q ~= focused then return end
        -- (QuestDataProviderMixin:ShouldShowQuest)
        local wq = Yes(QL.IsWorldQuest, q)
        if (wq and not tasksToo) or (not wq and Yes(QL.IsQuestTask, q)) then return end
        if HaveQuestData and not Yes(HaveQuestData, q) then return end
        if not zoneLike and not (e.mapType == 2 and q == st) then return end
        local title = Call(QL.GetTitleForQuestID, q)
        if not Str(title) then return end
        local c, selected = Classification(q), q == st
        local button = BUTTON[c] or "UI-QuestPoi-QuestNumber"
        local icon, done = nil, Yes(QL.IsComplete, q)
        if waypoint then
            icon = "poi-traveldirections-arrow"
        elseif done then
            icon = TURN_IN[c] or "UI-QuestIcon-TurnIn-Normal"
        elseif Yes(QL.IsQuestDisabledForSession, q) then
            icon = "QuestSharing-QuestLog-Padlock"
        else
            icon = selected and "Quest-In-Progress-Icon-Brown" or "Quest-In-Progress-Icon-yellow"
        end
        local info = { kind = waypoint and "waypoint" or "quest", id = q, name = title, done = done }
        Upsert(e, M, seen, (waypoint and "w" or "q") .. q, px, py, title, "quest", STYLE.questPin, QuestPic(button, icon, selected), info, true)
    end
    local list = Call(QL.GetQuestsOnMap, e.id)
    for _, r in ipairs(type(list) == "table" and list or {}) do
        if type(r) == "table" and not r.isMapIndicatorQuest then Add(r.questID, Frac(r.x, r.y)) end
    end
    if wq0 and QL.GetNextWaypointForMap then
        local ok, x, y = pcall(QL.GetNextWaypointForMap, wq0, e.id)
        local px, py
        if ok then px, py = Frac(x, y) end
        if px then Add(wq0, px, py, true) end
    end
end

-- WorldMap_WorldQuestDataProvider and BonusObjectiveDataProvider: map e's world quests, bonus objectives and threats
local function ReadTasks(e, M, seen, tasks)
    local QL = C_QuestLog
    if not QL then return end
    local st = Tracked()
    local real = Real(e)
    local wqOn = CVarOn("questPOIWQ")
    for _, t in ipairs(tasks) do
        local q = type(t) == "table" and t.questID
        local px, py = Frac(t.x, t.y)
        if Num(q) and px and (not HaveQuestData or Yes(HaveQuestData, q)) then
            local wq = Yes(QL.IsWorldQuest, q) or t.isMapIndicatorQuest == true
            local own = t.mapID == e.id
            if wq then
                -- (WorldQuestDataProviderMixin:ShouldMapShowQuest, WorldMap_'s ShouldShowQuest: a child map's on a zone, the
                -- tracked one on a continent, else the map's own)
                if wqOn and ((t.childDepth and real == ZONE) or (q == st and real == 2) or own) then
                    local tag = Call(QL.GetQuestTagInfo, q)
                    local icon = "Worldquest-icon"
                    if type(tag) == "table" then
                        local wt = tag.worldQuestType
                        if wt == QT.FactionAssault then
                            local _, f = pcall(UnitFactionGroup, "player")
                            icon = f == "Alliance" and "worldquest-icon-alliance" or "worldquest-icon-horde"
                        elseif wt == QT.Profession or wt == QT.Threat or not WQ_ICON[wt] then
                            local theme = Call(QL.GetQuestDetailsTheme, q)
                            if type(theme) == "table" and Str(theme.poiIcon) then icon = theme.poiIcon end
                            if wt == QT.Normal and tag.isElite and tag.quality == EPIC then icon = "worldquest-icon-boss" end
                        else
                            icon = WQ_ICON[wt]
                        end
                    end
                    local title = C_TaskQuest and Call(C_TaskQuest.GetQuestInfoByQuestID, q) or Call(QL.GetTitleForQuestID, q)
                    if Str(title) then
                        local pic = QuestPic("UI-QuestPoi-QuestNumber", icon, q == st) or QuestPic("UI-QuestPoi-QuestNumber", "Worldquest-icon", q == st)
                        Upsert(e, M, seen, "q" .. q, px, py, title, "quest", STYLE.questPin, pic, { kind = "world", id = q, name = title }, true)
                    end
                end
            elseif not (t.isQuestStart and t.inProgress) and (own or (Yes(QL.IsQuestCalling, q) and real == ZONE)) then
                -- (MapUtil.ShouldShowTask; the pin by classification: a bonus objective's, a threat's - else none)
                local c = Classification(q)
                local title = C_TaskQuest and Call(C_TaskQuest.GetQuestInfoByQuestID, q)
                if Str(title) and (c == QC.BonusObjective or c == QC.Threat) then
                    local pic
                    if c == QC.BonusObjective then
                        pic = AtlasPic("Bonus-Objective-Star", QUEST_ICON - 2)
                        local b = q == st and "worldquest-questmarker-epic-supertracked" or "worldquest-questmarker-epic"
                        if pic and AtlasPic(b, QUEST_BASE) then pic.base, pic.bw, pic.bh = b, QUEST_BASE, QUEST_BASE end
                    else
                        local theme = Call(QL.GetQuestDetailsTheme, q)
                        pic = QuestPic(BUTTON[QC.Threat], type(theme) == "table" and Str(theme.poiIcon) and theme.poiIcon or "Bonus-Objective-Star", q == st)
                    end
                    Upsert(e, M, seen, "q" .. q, px, py, title, "quest", STYLE.questPin, pic, { kind = "bonus", id = q, name = title }, true)
                end
            end
        end
    end
end

-- Is map `child` map `id` or under it (MapUtil.IsChildMapCached)?
local function Under(child, id)
    local guard = 0
    while Num(child) and child ~= 0 and guard < 10 do
        if child == id then return true end
        local info = C_Map and Call(C_Map.GetMapInfo, child)
        child = type(info) == "table" and info.parentMapID
        guard = guard + 1
    end
    return false
end

-- QuestOfferDataProvider: map e's quests on offer; those a quest hub of hubs stands for wait for OFFER_SPLIT (a hub of a
-- city's map keeps them: they are that city map's)
local function ReadOffers(e, M, seen, tasks, hubs)
    local QL, QLn = C_QuestLog, C_QuestLine
    if (e.mapType or ZONE) <= 2 or not (QL and QLn) then return end
    if not M.requested and QLn.RequestQuestLinesForMap then
        -- (Blizzard's map asks for the one map it shows; here a band's every zone comes at once: at most one map every
        -- REQUEST_EVERY, the others read again later - QUESTLINE_UPDATE marks them when the answer comes)
        local now = GetTime()
        if now - lastRequest >= REQUEST_EVERY then
            lastRequest = now
            M.requested = true
            Call(QLn.RequestQuestLinesForMap, e.id)
        else
            M.dirty = true
        end
    end
    local offers, order = {}, {}
    local function Take(o)
        if type(o) == "table" and Num(o.questID) and not offers[o.questID] then
            offers[o.questID] = o
            order[#order + 1] = o
        end
    end
    local lines = QLn.GetAvailableQuestLines and Call(QLn.GetAvailableQuestLines, e.id)
    for _, o in ipairs(type(lines) == "table" and lines or {}) do Take(o) end
    local forced = QLn.GetForceVisibleQuests and Call(QLn.GetForceVisibleQuests, e.id)
    for _, q in ipairs(type(forced) == "table" and forced or {}) do
        if Num(q) and QLn.GetQuestLineInfo then Take(Call(QLn.GetQuestLineInfo, q, e.id)) end
    end
    for _, t in ipairs(tasks) do
        if type(t) == "table" and t.isQuestStart and Num(t.questID) and not offers[t.questID] then
            local name = C_TaskQuest and Call(C_TaskQuest.GetQuestInfoByQuestID, t.questID)
            Take({ questID = t.questID, x = t.x, y = t.y, questName = name, inProgress = t.inProgress,
                isHidden = Yes(QL.IsQuestTrivial, t.questID), isAccountCompleted = Yes(QL.IsQuestFlaggedCompletedOnAccount, t.questID) })
        end
    end
    local M_ = C_Minimap
    local hidden, account = M_ and Yes(M_.IsTrackingHiddenQuests), M_ and Yes(M_.IsTrackingAccountCompletedQuests)
    local local_ = CVarOn("questPOILocalStory")
    local city = C_Map and Yes(C_Map.IsCityMap, e.id)
    for _, o in ipairs(order) do
        local q = o.questID
        local px, py = Frac(o.x, o.y)
        -- (QuestOfferDataProviderMixin:ShouldAddQuestOffer)
        local ok = px and not o.inProgress and Str(o.questName)
            and not (Num(o.startMapID) and o.startMapID ~= e.id and not Under(o.startMapID, e.id))
            and not (o.isHidden and not hidden) and not (o.isLocalStory and not local_)
        if ok and o.isAccountCompleted and not account
            and not (Num(o.questLineID) and Yes(QLn.QuestLineIgnoresAccountCompletedFiltering, e.id, o.questLineID))
            and not Yes(QL.QuestIgnoresAccountCompletedFiltering, q) then
            ok = false
        end
        local icon = ok and OFFER[Classification(q)]
        local pic = icon and AtlasPic(icon, OFFER_SIZE)
        if pic then
            if o.isHidden then pic.tint = DIM end
            local hub
            if not city and C_QuestHub and C_QuestHub.IsQuestCurrentlyRelatedToHub then
                for _, h in ipairs(hubs) do
                    if Yes(C_QuestHub.IsQuestCurrentlyRelatedToHub, q, h.id) then hub = h break end
                end
            end
            if not (hub and hub.link and C_Map and Yes(C_Map.IsCityMap, hub.link)) then
                local info = { kind = "offer", id = q, name = o.questName, line = Str(o.questLineName) and o.questLineName or nil }
                local it = Upsert(e, M, seen, "o" .. q, px, py, o.questName, "quest", STYLE.offerPin, pic, info, true)
                if it and hub then it.zmin = OFFER_SPLIT end
            end
        end
    end
end

local function Read(e)
    local M = maps[e]
    if not M then
        M = { items = {} }
        maps[e] = M
    end
    M.dirty = false
    local seen = {}
    -- ((1.6.0) WoW Forever: its quests alone - the header; none while its switch is off)
    if RETAIL and ns.db and ns.db.flightPaths ~= false then ReadTaxi(e, M, seen) end
    local A = C_AreaPoiInfo
    local hubs = {}
    if A and A.GetAreaPOIInfo then
        if RETAIL then
            if A.GetEventsForMap then ReadPois(e, M, seen, Call(A.GetEventsForMap, e.id), "event") end
            if A.GetDelvesForMap and CVarOn("showDelveEntrancesOnMap") then ReadPois(e, M, seen, Call(A.GetDelvesForMap, e.id), "delve") end
            if A.GetAreaPOIForMap then ReadPois(e, M, seen, Call(A.GetAreaPOIForMap, e.id), "poi") end
        end
        -- ((1.4.0-beta11) quest hubs: points of interest that stand for their quests on offer - (1.6.0) on WoW Forever too:
        -- its QuestOfferDataProvider draws them)
        if A.GetQuestHubsForMap and (e.mapType or ZONE) > 2 then ReadPois(e, M, seen, Call(A.GetQuestHubsForMap, e.id), "hub", hubs) end
    end
    -- ((1.4.0-beta11) quests; the map's tasks read once for its world quests, bonus objectives and offers)
    local tasks = C_TaskQuest and Call(C_TaskQuest.GetQuestsOnMap, e.id)
    tasks = type(tasks) == "table" and tasks or {}
    ReadQuests(e, M, seen)
    ReadTasks(e, M, seen, tasks)
    ReadOffers(e, M, seen, tasks, hubs)
    for key, it in pairs(M.items) do
        if not seen[key] then it.off = true end
    end
end

local restDirty -- ((1.4.0-beta16) set below: ReadAtRest's restClean)
local function Dirty()
    for _, M in pairs(maps) do M.dirty = true end
    if restDirty then restDirty() end
end

---------------------------------------------------------------------------
-- Every frame Labels draws (a post-hook): the maps near the view read, once and when changed
---------------------------------------------------------------------------
local KINDS = { zone = true, inset = true, cont = true, globe = true }
-- ((1.6.0) WoW Forever: its continents and zones, the cities among them - the maps Blizzard pins quests on)
local function Readable(e)
    if RETAIL then return KINDS[e.kind] and not e.spaceHidden and e.visibleNow ~= false end
    return e.mapType == ns.MAPTYPE_CONTINENT or e.mapType == ns.MAPTYPE_ZONE
end
-- (map e's markers show now: on retail its picture is drawn; (1.6.0) on WoW Forever its quests' band has begun - Band)
local function Drawn(e, cam, v)
    if RETAIL then return ns.Render:MapAlpha(e) > 0 end
    local w, z = ns.WorldZoom(v, cam.vw), ns.ZoomOf(v, e, cam.vw)
    if (e.mapType or ZONE) > 2 then return w >= questG * 0.92 or z >= 0.92 end
    return w < questG and z >= 0.92
end
local lastCam, lastV -- (the view Labels last drew: the map at rest reads its changed maps against it)
-- ((1.4.0-beta16) at most READ_MAX maps a go, those drawn now first, the rest at the next: a read asks the client up to a dozen lists and a zoom out brought in dozens of maps in one
-- frame, a quest update every map near the view - the stamp's frames of 20 - 39 ms in the labels. Returns how many were read, and whether more wait)
local READ_MAX = 3
local function ReadNear(cam, v)
    if not RETAIL and not questG then return 0, false end -- ((1.6.0) WoW Forever's quest switch off: nothing of ours)
    local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)
    local hx, hy = v.W / 2 / ppx * (1 + 2 * NEAR), v.H / 2 / ppy * (1 + 2 * NEAR)
    local now, n = GetTime(), 0
    local later = false
    for pass = 1, 2 do
        for _, e in ipairs(ns.SpaceAll or ns.drawList or {}) do
            if Readable(e) and e.x0 <= cam.x + hx and cam.x - hx <= e.x1 and e.y0 <= cam.y + hy and cam.y - hy <= e.y1 then
                local M = maps[e]
                -- ((1.4.0-beta11) a map read before, marked changed: again once READ_EVERY has passed since its last read;
                -- and read whenever its picture is drawn - a small zone's band comes in below LOAD_ZOOM: Duskwood and Redridge
                -- at 0.20 of their own with the Eastern Kingdoms' zones, whose markers stayed as first read - or a stale list)
                if not M or M.dirty then
                    local drawn = Drawn(e, cam, v)
                    if (pass == 1 and drawn) or (pass == 2 and not drawn and ns.ZoomOf(v, e, cam.vw) >= LOAD_ZOOM) then
                        if n >= READ_MAX or (M and now - (M.at or 0) < READ_EVERY) then
                            later = true
                        else
                            Read(e)
                            maps[e].at = now
                            n = n + 1
                        end
                    end
                end
            end
        end
    end
    return n, later
end
-- ((1.4.0-beta11) the map at rest draws only when something changes (Core.lua Redraw: the next frame): what a read found
-- is drawn then - a map read as the view settled, a quest done, a world quest's data come)
-- ((1.4.0-beta15) a motion's draws walk the maps at most every READ_NEAR_EVERY - every map of the tree, for a map new near the view; the watch below at rest takes the last of it)
local READ_NEAR_EVERY = 0.1
-- ((restClean: the last walk found nothing near to read: none again until something changes - a far map stays marked changed for good, and with it every map of the tree was walked 20 times a second, at rest)
local readNearT, readLate = -1e9, false
local restClean = false
restDirty = function() restClean = false end
local function AfterDraw(_, cam, v)
    if not (cam and v and v.W and v.W > 0) then return end
    lastCam, lastV = cam, v
    restClean = false
    local now = GetTime()
    if now - readNearT < READ_NEAR_EVERY then
        readLate = true
        return
    end
    local n, later = ReadNear(cam, v)
    readNearT, readLate = now, later
    if n > 0 and ns.Core and ns.Core.Redraw then ns.Core.Redraw() end
end
local function ReadAtRest()
    if not (lastCam and lastV) or (restClean and not readLate) then return end
    local core = ns.Core
    if not (core and core.Settled and core.Settled()) then return end -- (moving: AfterDraw, ten times a second)
    local n, later = ReadNear(lastCam, lastV)
    readLate = later
    readNearT = GetTime()
    restClean = n == 0 and not later
    if n > 0 and core.Redraw then core.Redraw() end
end

---------------------------------------------------------------------------
-- Blizzard's own pins of these kinds: hidden while the add-on draws the map (a post-hook - its code runs as it does)
---------------------------------------------------------------------------
local function Ours()
    local core, db = ns.Core, ns.db
    if not (db ~= nil and db.enabled ~= false and core ~= nil and core.State ~= nil and core.State() ~= "off") then return false end
    -- ((1.6.0) WoW Forever: only while ours stand in - its switch on, the label layer drawn, at rest too -, Blizzard's own
    -- else: there they lie where ours would. On retail they stay hidden: they do not lie where the add-on draws their maps)
    return RETAIL or (questG ~= false and db.labels ~= false and db.labelsAtRest ~= false)
end
-- (a pin Blizzard sets the alpha of again - MapCanvasPinMixin:ApplyCurrentAlpha at every canvas scale, a POI's alpha limits
-- (isAlwaysOnFlightmap): moving, Blizzard's map rescales each frame - goes back to 0 in the same call, never drawn between)
local function KeepHidden(pin, a)
    if hidden[pin] and a ~= 0 then pin:SetAlpha(0) end
end
-- ((1.4.0-beta15) Blizzard's explored pieces not only at alpha 0: hidden - a frame at alpha 0 still has its textures loaded and laid out, up to 500 of them
-- on a 3,840-px map at every map switch and every frame its canvas moves, for a picture ours draws. Its one permanent pin, MapExplorationDataProvider.lua:
-- its code runs as it does; on a hidden frame nothing it sets loads)
local GONE = { MapExplorationPinTemplate = true }
local gone = setmetatable({}, { __mode = "k" })
local function KeepGone(pin)
    if gone[pin] then pin:Hide() end
end
local function Unhide(pin)
    hidden[pin] = nil
    pin:SetAlpha(1)
    if gone[pin] then
        gone[pin] = nil
        pin:Show()
    end
    if pin.SetMouseClickEnabled then pcall(pin.SetMouseClickEnabled, pin, true) end
    if pin.SetMouseMotionEnabled then pcall(pin.SetMouseMotionEnabled, pin, true) end
end
local function HideTemplate(map, template)
    for pin in map:EnumeratePinsByTemplate(template) do
        if not hidden[pin] and pin:IsShown() then
            hidden[pin] = true
            if not hooked[pin] then
                hooked[pin] = true
                hooksecurefunc(pin, "SetAlpha", KeepHidden)
                if GONE[template] then hooksecurefunc(pin, "Show", KeepGone) end
            end
            pin:SetAlpha(0)
            if pin.SetMouseClickEnabled then pcall(pin.SetMouseClickEnabled, pin, false) end
            if pin.SetMouseMotionEnabled then pcall(pin.SetMouseMotionEnabled, pin, false) end
            if GONE[template] and not ns.retailTest.blizzart then
                gone[pin] = true
                pin:Hide()
            end
        end
    end
end
local function ShowHidden()
    for pin in pairs(hidden) do Unhide(pin) end
end
local function OnAcquire(map, template)
    if TEMPLATES[template] and hiding then HideTemplate(map, template) end
end
-- (each frame the map is open: the add-on's state decides - off, Blizzard's pins are back)
-- ((1.4.0-beta15) Blizzard's map art - its detail layers, a whole map's tiles: 12 on a small zone, 150 on a 3,840-px one, 279 on Azeroth - lies under our Cosmic map, which
-- covers every view: never seen, once ours is there, yet each map switch asked the client for all of them and each frame of a motion laid them out, and it drew them at
-- rest. Hidden once our floor is confirmed (Render:IsReady - rule 4: Blizzard's canvas until then, each time the map opens) until the add-on stands aside. On a hidden
-- layer Blizzard's code runs as it does, and nothing it sets loads. /emap test blizzart: as before (RetailBench.lua compares the two)
local artOff = false
local function ArtShown(on)
    local pool = WorldMapFrame.detailLayerPool
    if not (pool and pool.EnumerateActive) then return end
    for layer in pool:EnumerateActive() do
        if type(layer) == "table" and layer.SetShown and layer:IsShown() ~= on then layer:SetShown(on) end
    end
end
local function SyncArt()
    local TEST = ns.retailTest
    local off = artOff
    if not hiding or TEST.blizzart then
        off = false
    elseif not off and ns.Render and ns.Render:IsReady() then
        off = true
    end
    if off ~= artOff then
        artOff = off
        ArtShown(not off)
    end
    -- (the test's switch for the explored pieces' pin: with the art)
    local bl = TEST.blizzart == true
    if bl ~= (PN.blizzart == true) then
        PN.blizzart = bl
        for pin in WorldMapFrame:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
            if bl and gone[pin] then
                gone[pin] = nil
                pin:Show()
            elseif not bl and hidden[pin] then
                gone[pin] = true
                pin:Hide()
            end
        end
    end
end
local function SyncHiding()
    local want = Ours()
    if want == hiding then return end
    hiding = want
    if want then
        for t in pairs(TEMPLATES) do HideTemplate(WorldMapFrame, t) end
    else
        ShowHidden()
    end
end
-- (a pool's pin released goes back to the pool as Blizzard left it - its alpha, its mouse -, so whatever acquires it next
-- finds it so: hidden again here while the add-on draws, Blizzard's own with it off)
local function Released(map, template)
    if not TEMPLATES[template] then return end
    for pin in pairs(hidden) do
        if not pin:IsShown() and not gone[pin] then Unhide(pin) end
    end
end

---------------------------------------------------------------------------
-- The hover and the click (at rest)
---------------------------------------------------------------------------
function PN:HitTest(x, y)
    if not (x and y) then return nil end
    local best, bd
    for _, it in ipairs(pins) do
        if it.shown and it.sx and (it.alpha or 0) >= 0.5 and not it.off then
            local half = (it.pic and math.max(it.pic.h, it.pic.bh or 0) / 2 or 8) + HIT_PAD
            local hit = (math.abs(x - it.sx) <= half and math.abs(y - it.sy) <= half)
                or (it.x0 and x >= it.x0 and x <= it.x1 and y >= it.y0 and y <= it.y1)
            if hit then
                local d = (x - it.sx) ^ 2 + (y - it.sy) ^ 2
                if not best or d < bd then best, bd = it, d end
            end
        end
    end
    return best
end

-- ((1.4.0-beta11) a quest of the log, a world quest, a bonus objective, the waypoint: tracked by its quest)
local QUEST_KINDS = { quest = true, waypoint = true, world = true, bonus = true }
local function PinType(it)
    local E = Enum and Enum.SuperTrackingMapPinType
    if it.info.kind == "taxi" then return (E and E.TaxiNode) or MAPPIN_TAXI end
    if it.info.kind == "offer" then return (E and E.QuestOffer) or MAPPIN_OFFER end
    return (E and E.AreaPOI) or MAPPIN_POI
end
local function IsTracked(it)
    local S = C_SuperTrack
    if QUEST_KINDS[it.info.kind] then return Tracked() == it.info.id end
    if not (S and S.GetSuperTrackedMapPin) then return false end
    local ok, t, id = pcall(S.GetSuperTrackedMapPin)
    return ok and Num(t) and Num(id) and t == PinType(it) and id == it.info.id
end

-- ((1.6.2) The click is the click of the Blizzard pin ours stands for, step by step - the same code on WoW Forever 1.60.1
-- (70862) and retail 12.1.5 (Gethe's wow-ui-source, branches forever and live): a quest of the log, a bonus objective and
-- the selected quest's waypoint (QuestPinMixin's, BonusObjectivePinMixin's OnMouseClickAction: POIButtonMixin:OnClick -
-- QuestDataProvider pins the waypoint as a quest pin), a world quest (WorldQuestPinMixin:OnMouseClickAction), an offer, a
-- flight master, a point of interest (SuperTrackablePinMixin:OnMouseClickAction). Until 1.6.1 a quest's click only
-- selected it (C_SuperTrack) and never put it on the quest tracker - the player on 1.6.1: "i cant click on a question
-- mark to mark it for tracking". Of Blizzard's steps, those that run its own Lua and write it are left out and the C
-- calls they make taken instead - run by an add-on they would taint the quest tracker (Core.lua QuestSafe): a world
-- quest's QuestUtil.TrackWorldQuest / UntrackWorldQuest (they keep its lastTrackedQuestID and run
-- ObjectiveTrackerManager:UpdateAll) -> C_QuestLog.AddWorldQuestWatch / RemoveWorldQuestWatch. The world quest provider's
-- HandleClick (a spell aimed at a world quest's place) has no counterpart here.)
local WATCH_AUTO, WATCH_MANUAL = 0, 1   -- (Enum.QuestWatchType when the enum is missing)
local function Sound(name)
    local id = SOUNDKIT and SOUNDKIT[name]
    if Num(id) then Call(PlaySound, id) end
end
-- (QuestUtils_IsQuestWatched: a watch of any type - nil, not on the quest tracker)
local function WatchType(id)
    local w = C_QuestLog and Call(C_QuestLog.GetQuestWatchType, id)
    if Num(w) then return w end
end
local function Shift() return Call(IsShiftKeyDown) == true end
-- (Blizzard's first step: a modified click - Shift - while a chat box is open puts the quest's link there, its own utility)
local function ChatLink(id)
    return ChatFrameUtil ~= nil and Call(ChatFrameUtil.TryInsertQuestLinkForQuestID, id) == true
end
-- (POIButtonMixin:OnClick)
local function ClickQuest(it)
    local S, L, id = C_SuperTrack, C_QuestLog or {}, it.info.id
    if IsTracked(it) then -- (self:IsSelected())
        Sound("IG_MAINMENU_OPTION_CHECKBOX_OFF")
        Call(S.ClearAllSuperTracked)
        return
    end
    Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    if ChatLink(id) then return end
    if WatchType(id) ~= nil then
        if Shift() then
            -- (QuestUtil.CanRemoveQuestWatch: not in the New Player Experience)
            local U = QuestUtil
            if not (U and U.CanRemoveQuestWatch) or Call(U.CanRemoveQuestWatch) == true then Call(L.RemoveQuestWatch, id) end
            return
        end
    else
        Call(L.AddQuestWatch, id)
    end
    Call(S.SetSuperTrackedQuestID, id)
end
-- (WorldQuestPinMixin:OnMouseClickAction)
local function ClickWorld(it)
    local S, L, id = C_SuperTrack, C_QuestLog or {}, it.info.id
    if ChatLink(id) then return end
    local E = Enum and Enum.QuestWatchType
    local AUTO, MANUAL = (E and E.Automatic) or WATCH_AUTO, (E and E.Manual) or WATCH_MANUAL
    local w, selected = WatchType(id), IsTracked(it)
    if Shift() then
        if w == MANUAL or (w == AUTO and selected) then
            Sound("IG_MAINMENU_OPTION_CHECKBOX_OFF")
            Call(L.RemoveWorldQuestWatch, id)
        else
            Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
            Call(L.AddWorldQuestWatch, id, MANUAL)
        end
    elseif selected then
        Sound("IG_MAINMENU_OPTION_CHECKBOX_OFF")
        Call(S.SetSuperTrackedQuestID, 0)
    else
        Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        if w ~= MANUAL then Call(L.AddWorldQuestWatch, id, AUTO) end
        Call(S.SetSuperTrackedQuestID, id)
    end
end
-- (SuperTrackablePinMixin:OnMouseClickAction: the waypoint set, or taken off)
local function ClickPin(it)
    local S = C_SuperTrack
    if IsTracked(it) then
        Call(S.ClearAllSuperTracked)
        Sound("IG_MAINMENU_OPTION_CHECKBOX_OFF")
    else
        Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        Call(S.SetSuperTrackedMapPin, PinType(it), it.info.id)
    end
end

-- (RetailDoors.lua OnCanvasClick, a click no door took) true: the click was ours
function PN:OnCanvasClick(button)
    if button ~= "LeftButton" or not ns.Core then return false end
    local it = PN:HitTest(ns.Core.CursorPos())
    if not it then return false end
    -- ((1.6.0) a quest is tracked in combat too, as Blizzard's quest pin does it (POIButtonMixin:OnClick: C_SuperTrack and
    -- (1.6.2) C_QuestLog's watches, no protected call) - its own pin, hidden, takes no click; another marker's waypoint
    -- waits for the fight's end)
    if InCombatLockdown() and not QUEST_KINDS[it.info.kind] then return false end
    if not C_SuperTrack then return true end
    local kind = it.info.kind
    if kind == "world" then
        ClickWorld(it)
    elseif QUEST_KINDS[kind] then
        ClickQuest(it)
    else
        ClickPin(it)
    end
    Dirty() -- (the tracked quest's button and its waypoint change: SUPER_TRACKING_CHANGED says so too)
    return true
end

local tip, tipText, hot
local function ShowTip(it)
    if not tip then
        tip = CreateFrame("Frame", nil, UIParent)
        if tip.SetFrameStrata then tip:SetFrameStrata("TOOLTIP") end
        local bg = tip:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(tip)
        bg:SetColorTexture(0.04, 0.035, 0.03, 0.94)
        tipText = tip:CreateFontString(nil, "OVERLAY")
        tipText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "")
        tipText:SetTextColor(1, 0.82, 0)
        tipText:SetPoint("TOPLEFT", tip, "TOPLEFT", 8, -6)
        tipText:SetJustifyH("LEFT")
    end
    local inf = it.info or {}
    local lines = { tostring(inf.name or it.text) }
    local quest = QUEST_KINDS[inf.kind]
    if inf.kind == "taxi" then
        lines[#lines + 1] = inf.undiscovered and "|cffd0d0d0Flight master - not found yet|r" or "|cffd0d0d0Flight master|r"
    elseif quest then
        -- ((1.4.0-beta11) what it is, what is left of it - C_QuestLog.GetQuestObjectives, as QuestPinMixin:OnMouseEnter's)
        local what = (inf.kind == "world" and "World quest") or (inf.kind == "bonus" and "Bonus objective")
            or (inf.kind == "waypoint" and "Tracked quest - the way there") or (inf.done and "Ready to turn in") or "Quest"
        lines[#lines + 1] = "|cffd0d0d0" .. what .. "|r"
        if not inf.done and C_QuestLog and C_QuestLog.GetQuestObjectives then
            local obj = Call(C_QuestLog.GetQuestObjectives, inf.id)
            local k = 0
            for _, o in ipairs(type(obj) == "table" and obj or {}) do
                if type(o) == "table" and Str(o.text) and not o.finished and k < 4 then
                    lines[#lines + 1] = "|cffffffff- " .. o.text .. "|r"
                    k = k + 1
                end
            end
        end
        local s = inf.kind == "world" and C_TaskQuest and Call(C_TaskQuest.GetQuestTimeLeftSeconds, inf.id)
        if Num(s) and s > 0 then
            lines[#lines + 1] = ("|cffd0d0d0%d:%02d left|r"):format(math.floor(s / 3600), math.floor(s / 60) % 60)
        end
    elseif inf.kind == "offer" then
        lines[#lines + 1] = "|cffd0d0d0Quest on offer|r"
        if inf.line then lines[#lines + 1] = "|cffd0d0d0" .. inf.line .. "|r" end
    elseif inf.desc then
        lines[#lines + 1] = "|cffd0d0d0" .. inf.desc .. "|r"
    end
    if not quest and inf.kind ~= "taxi" and inf.kind ~= "offer" and C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOISecondsLeft then
        local s = Call(C_AreaPoiInfo.GetAreaPOISecondsLeft, inf.id)
        if Num(s) and s > 0 then
            lines[#lines + 1] = ("|cffd0d0d0%d:%02d left|r"):format(math.floor(s / 3600), math.floor(s / 60) % 60)
        end
    end
    if quest then
        -- ((1.6.2) what the click does - ClickQuest, ClickWorld: onto the quest tracker and selected; selected, a click lets
        -- it go - it stays on the tracker -; Shift-click takes it off the tracker)
        local w, selected = WatchType(inf.id), IsTracked(it)
        lines[#lines + 1] = (selected and "|cffffffffClick: deselect it|r")
            or (w ~= nil and "|cffffffffClick: select it|r") or "|cffffffffClick: track this quest|r"
        local off
        if inf.kind == "world" then
            local E = Enum and Enum.QuestWatchType
            off = w == ((E and E.Manual) or WATCH_MANUAL) or (selected and w == ((E and E.Automatic) or WATCH_AUTO))
        else
            off = w ~= nil and not selected
        end
        if off then lines[#lines + 1] = "|cffffffffShift-click: stop tracking it|r" end
    else
        lines[#lines + 1] = IsTracked(it) and "|cffffffffClick: take the waypoint off|r" or "|cffffffffClick: set the waypoint here|r"
    end
    tipText:SetText(table.concat(lines, "\n"))
    local w, h = tipText:GetStringWidth(), tipText:GetStringHeight()
    if not Num(w) or w <= 0 then w = 180 end
    if not Num(h) or h <= 0 then h = 14 * #lines end
    tip:SetSize(w + 16, h + 12)
    tip:ClearAllPoints()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    tip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / s + 14, y / s + 14)
    tip:Show()
end

-- (a door under the cursor has the hover: retail's RetailDoors.lua, (1.6.0) WoW Forever's dungeon icons - Dungeon.lua)
local function OnDoor(x, y)
    if RETAIL then return ns.RetailDoors ~= nil and ns.RetailDoors.HitTest ~= nil and ns.RetailDoors:HitTest(x, y) ~= nil end
    return Labels:HitTest(x, y) ~= nil
end
local function Hover()
    local core = ns.Core
    local it
    if core and core.Settled and core.Settled() and WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.ScrollContainer
        and WorldMapFrame.ScrollContainer:IsMouseOver() and not OnDoor(core.CursorPos()) then
        it = PN:HitTest(core.CursorPos())
    end
    if it ~= hot then
        if hot then Labels:SetHot(nil) end
        hot = it
        if it then
            Labels:SetHot(it)
            ShowTip(it)
        elseif tip then
            tip:Hide()
        end
    elseif it then
        Labels:SetHot(it) -- (lit again if the doors' hover - RetailDoors.lua - let go of a door under it this frame)
        ShowTip(it)
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local watch = CreateFrame("Frame")
watch:Hide()
local acc = 0
watch:SetScript("OnUpdate", function(_, elapsed)
    SyncHiding()
    if RETAIL then SyncArt() end -- ((1.6.0) Blizzard's art and exploration pin: retail's alone - WoW Forever lays them out as ours)
    acc = acc + (elapsed or 0)
    if acc < 0.05 then return end
    acc = 0
    Hover()
    ReadAtRest()
end)
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("AREA_POIS_UPDATED")
ev:RegisterEvent("TAXI_NODE_STATUS_CHANGED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("CVAR_UPDATE")
-- ((1.4.0-beta11) the quests' - Blizzard's providers' events; QUESTLINE_UPDATE with requestRequired: the quest lines asked
-- for again)
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_POI_UPDATE", "SUPER_TRACKING_CHANGED",
    "QUESTLINE_UPDATE", "MINIMAP_UPDATE_TRACKING", "QUEST_DATA_LOAD_RESULT", "QUEST_TURNED_IN", "QUEST_ACCEPTED",
    "QUEST_REMOVED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1)
    if event == "QUESTLINE_UPDATE" and a1 then
        for _, M in pairs(maps) do M.requested = nil end
    end
    if event == "PLAYER_LOGIN" then
        hooksecurefunc(Labels, "Draw", AfterDraw)
        if WorldMapFrame then
            if WorldMapFrame.AcquirePin then hooksecurefunc(WorldMapFrame, "AcquirePin", OnAcquire) end
            if WorldMapFrame.RemoveAllPinsByTemplate then hooksecurefunc(WorldMapFrame, "RemoveAllPinsByTemplate", Released) end
            -- ((1.6.0) a quest's details opened or closed in the quest log: the quests read again - ReadQuests' focus)
            for _, fn in ipairs({ "QuestMapFrame_ShowQuestDetails", "QuestMapFrame_CloseQuestDetails" }) do
                if type(_G[fn]) == "function" then hooksecurefunc(fn, Dirty) end
            end
            -- ((1.4.0-beta15) a map switch's new layers: never shown - SetMapID makes them in one go)
            if WorldMapFrame.RefreshDetailLayers then
                hooksecurefunc(WorldMapFrame, "RefreshDetailLayers", function()
                    if artOff then ArtShown(false) end
                end)
            end
            WorldMapFrame:HookScript("OnShow", function()
                Dirty() -- (Blizzard's providers read their maps again as the map opens: so do we)
                -- ((1.4.0-beta15) its art under ours until ours is confirmed: SyncArt)
                if artOff then
                    artOff = false
                    ArtShown(true)
                end
                watch:Show()
            end)
            WorldMapFrame:HookScript("OnHide", function()
                watch:Hide()
                if tip then tip:Hide() end
                if hot then Labels:SetHot(nil) end
                hot = nil
            end)
            if WorldMapFrame:IsShown() then watch:Show() end
        end
    else
        Dirty()
    end
end)

-- ((1.6.0, WoW Forever: ZoomReadout.lua Apply) the quest switch - a world zoom, false: off. Every quest marker takes the new
-- band (Band); off, they go and Blizzard's own come back (Ours); on again, every map is read anew.
function PN:SetQuestZoom(g)
    if RETAIL then return end
    if g ~= false then g = (type(g) == "number" and g >= QUEST_G_MIN and g <= QUEST_G_MAX) and g or QUEST_G end
    if g == questG then return end
    questG = g
    for _, it in ipairs(pins) do
        if g then Band(it) else it.off = true end
    end
    Dirty()
    if ns.Core and ns.Core.Redraw then ns.Core.Redraw() end
end
function PN:QuestZoom() return questG end

-- (tests) the markers, the maps read, Blizzard's pins hidden
PN.T = { pins = pins, maps = maps, hidden = hidden, Hiding = function() return hiding end, Hot = function() return hot end }
