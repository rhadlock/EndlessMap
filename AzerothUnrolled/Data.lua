local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)

-- Capital cities (uiMapIDs). Their parent is the continent and their map type
-- is Zone, so they can't be detected from map data - hence the list.
-- Names come from C_Map so they are localized.
ns.CAPITALS = {
    1453, -- Stormwind City
    1455, -- Ironforge
    1457, -- Darnassus
    1454, -- Orgrimmar
    1456, -- Thunder Bluff
    1458, -- Undercity
}

-- Dungeon & raid entrances in WORLD coordinates (instance map, north, west).
-- (WoW Forever's own instances: their confirmed doors are rows of ns.FOREVER_DOORS, DungeonMapsMM.lua, added here at load.)
-- The game converts them onto whatever zone frames the client uses, so they
-- stay correct on WoW Forever (which re-framed Stormwind, EPL, Mulgore and
-- Redridge) as well as on Classic Era.
-- { instanceMapID, north, west, name, kind, minLevel, maxLevel }
ns.INSTANCES = {
    -- Eastern Kingdoms (instance map 0)
    { 0, -11073.0,  1529.2, "The Deadmines",        "dungeon", 17, 26 },
    { 0,  -8761.8,   848.6, "The Stockade",         "dungeon", 24, 32 },
    { 0,   -229.5,  1576.3, "Shadowfang Keep",      "dungeon", 22, 30 },
    { 0,  -5183.8,   605.3, "Gnomeregan",           "dungeon", 29, 38 },
    { 0,   2819.3,  -699.2, "Scarlet Monastery",    "dungeon", 30, 46 },
    { 0,  -6090.2, -3188.6, "Uldaman",              "dungeon", 41, 51 },
    { 0, -10440.5, -3826.2, "Sunken Temple",        "dungeon", 50, 60 },
    { 0,  -7778.9, -1127.8, "Blackrock Mountain",   "raid",    52, 60 },
    { 0,   1282.1, -2548.7, "Scholomance",          "dungeon", 58, 60 },
    { 0,   3392.5, -3396.8, "Stratholme",           "dungeon", 58, 60 },
    { 0,   3237.5, -4060.6, "Stratholme (Service)", "dungeon", 58, 60 },
    { 0,   3133.1, -3730.3, "Naxxramas",            "raid",    60, 60 },
    { 0, -11915.8, -1236.4, "Zul'Gurub",            "raid",    60, 60 },
    -- Deeprun Tram: its two portals (Forever AreaTrigger.db2 2173 / 2175, radius 10 yd). No level range. Ironforge's
    -- city map prints "The Deeprun Tram" right beside its portal, so there the icon goes without a name (iconOnly).
    { 0,  -8346.5,    514.0, "Deeprun Tram",         "dungeon" }, -- Stormwind City, Dwarven District (uiMap 1453 at 69.6, 30.3)
    { 0,  -4840.3,  -1330.5, "Deeprun Tram",         "dungeon", iconOnly = true, entrance = "Deeprun Tram (Ironforge)" }, -- Ironforge, Tinker Town (uiMap 1455 at 78.0, 51.4)

    -- Kalimdor (instance map 1)
    { 1,   1818.4, -4427.3, "Ragefire Chasm",       "dungeon", 13, 18 },
    { 1,   -846.8, -2038.4, "Wailing Caverns",      "dungeon", 17, 24 },
    { 1,   4127.1,   863.8, "Blackfathom Deeps",    "dungeon", 24, 32 },
    { 1,  -4456.7, -1656.0, "Razorfen Kraul",       "dungeon", 29, 38 },
    { 1,  -4666.5, -2536.8, "Razorfen Downs",       "dungeon", 37, 46 },
    { 1,  -6790.9, -2891.9, "Zul'Farrak",           "dungeon", 44, 54 },
    { 1,  -1382.0,  2918.7, "Maraudon",             "dungeon", 46, 55 },
    { 1,  -3700.7,  1091.6, "Dire Maul",            "dungeon", 54, 60 },
    { 1,  -4768.6, -3752.1, "Onyxia's Lair",        "raid",    60, 60 },
    -- (Ahn'Qiraj: one entrance per raid, see DungeonPortals.lua. The Temple at its portal, AreaTrigger.db2
    -- row 4010. The Ruins' portal (row 4008, -8424.94, 1508.65) lies 143.7 yd south of the Silithus map's
    -- edge, where no map shows it: its icon sits at the Ruins' entrance point in Map.db2[509] (Corpse),
    -- at the Gates of Ahn'Qiraj.)
    { 1,  -8114.46, 1526.37, "Ruins of Ahn'Qiraj",  "raid",    60, 60 },
    { 1,  -8230.4,  2005.33, "Ahn'Qiraj Temple",    "raid",    60, 60 },
}

-- Which continent map each instance map sits on.
ns.CONTINENT_FOR_INSTANCE = { [0] = 1415, [1] = 1414 }
