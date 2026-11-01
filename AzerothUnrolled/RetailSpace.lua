--[[
Endless Map - RetailSpace.lua (1.4.0; retail only: AzerothUnrolled_Standard.toc lists it after Util.lua, before Core.lua)

The camera's space on retail (docs/retail-engine.md sections 1-3, 6): Util.lua's registry rebuilt over the placement tree
(RetailTree.lua, ns.RETAIL_TREE - tools/retail/build_tree.py), so Core.lua's one camera - wheel, drag, flights, settle,
live pins, combat hold - runs from space (the Cosmic map 946) down to every zone.

  * Units: fractions of the Cosmic map's picture (946, 1002 x 668), as Util.lua's are fractions of Azeroth's on WoW
    Forever. Each node's rect is composed down the tree from its rect on its PARENT's picture; its height is derived
    from its width, so every picture lies at its art's true shape (ky = 1): Core's RealParams / Holds and Blizzard's
    pins agree with the drawing to the pixel.
  * ns.maps[id]: every node of the tree (group members too: a floor or copy Blizzard's map shows is found); ns.drawList:
    the ones that draw - one member per group (the one Blizzard's map showed last, else the default), conditional links
    only while the game lists them (C_Map.GetMapLinksForMap) -, parents first. Nazjatar's second door (on Zandalar) is
    an entry of its own with the same id; ns.GetMap gives the one nearest the camera (the review of the design, point 5:
    no flight between them).
  * ns.holders: the maps that bound the camera (Core NearestHoldable) - the Cosmic map (over open space up to the
    largest world's fit, maxZoom - the review, point 1; 1.4.0-beta1: over a world up to that world's fit, or up to the fit
    of a child reaching past it while the view reaches over that part - RootHoldAt), the worlds, the continents, insets
    and portals (1.4.0-beta1: these only on their link's rect - HoldAt), and the zones that reach past their parent's
    picture (hold).
  * Hooks Core.lua reads (nil on WoW Forever): ns.SpaceFocus (focus down the tree), ns.SpaceSwap (a floor or copy of
    the map shown: in place), ns.QuestSafeExtra (task quests too), ns.NodeForWorldPos / ns.OpenZoomFor (Follow.lua,
    PartyBubbles.lua), e.hscore (the hand-over score by depth: an inset above the zones beside it - the review, point 2),
    e.maxZoom (the depth limit's own map), e.holdMax and (1.4.0-beta1) e.holdAt (that zoom for a view), e.holder; and
    for the renderer e.ext (the extent of a map and every map placed under it).
  * A silent stamp, EndlessMapDB.retailChecks, once per login (docs/retail-engine.md section 6): what the client
    answers where the tree is a model (GetMapRectOnMap of five pairs, a continent's children, the conditional links,
    the art sizes), and - filled in by RetailRender.lua through the session - the masks' SetTexture answers and the
    texture high-water mark. No chat line, nothing shown.
Every C_Map call goes through pcall and takes plain values only (the Midnight map restrictions: a secret value or an
error is no answer); a failed read keeps the tree's own value.
]]
local _, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)
if ns.FLAVOR ~= "retail" then return end

local T = ns.RETAIL_TREE
if type(T) ~= "table" or type(T.n) ~= "table" then return end -- (RetailTree.lua not loaded: the engine stands aside)
local N = T.n

ns.ROOT_MAP_ID = T.root
ns.WORLD_MAP_ID = T.world
-- (WoW Forever's data, which retail has not: Data.lua is not loaded - Blizzard pins retail's entrances and capitals)
ns.CAPITALS, ns.INSTANCES, ns.CONTINENT_FOR_INSTANCE = {}, {}, {}
ns.TILE_FILE_MIN = 16 -- (retail's explored pieces start at 16 px, as Blizzard's MapExplorationDataProvider.lua)

local maps, drawList = ns.maps, ns.drawList
local holders = {}
ns.holders = holders

local alts = {}       -- [id] = { second entries of map id (Nazjatar's door on Zandalar) }
local all = {}        -- every entry, main and door, parents first
local groupOf = {}    -- [member id] = group key (the default member's id)
local shown = {}      -- [group key] = the member that draws now
local listed = {}     -- [child id] = true while the game shows it (conditional links: ReadLinks, OnRealMapChanged)
local kids = {}       -- [entry] = { shown entries placed on it }
local reach = {}      -- [world entry] = { its shown children whose pictures reach past its own }
local built = false
local hooked = false
local stamp           -- EndlessMapDB.retailChecks of this login

local LINK = { inset = true, portal = true }
-- (Forever's view at world zoom 14 is 3,193 yd wide: M opens the map that wide - docs/retail-engine.md section 3)
local OPEN_YARDS_AT_14 = 3193
-- (SpaceFocus: a capital takes the focus from its home zone only as its own picture is about to show)
local HOME_IN, HOME_OUT = 0.60, 0.55

local function Plain(v, kind) return type(v) == kind and not (issecretvalue and issecretvalue(v)) end
local function Num(v) return Plain(v, "number") and v == v end

local function Info(id)
    if not (C_Map and C_Map.GetMapInfo) then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, id)
    if ok and type(info) == "table" then return info end
end

-- The client's layer-1 art size of map id (what Blizzard's canvas is sized by), else the tree's.
local function ArtSize(id, n)
    local ok, layers = pcall(C_Map.GetMapArtLayers, id)
    local L = ok and type(layers) == "table" and layers[1]
    if type(L) == "table" and Num(L.layerWidth) and Num(L.layerHeight) and L.layerWidth > 0 and L.layerHeight > 0 then
        return L.layerWidth, L.layerHeight, true
    end
    return n.a[1], n.a[2], false
end

---------------------------------------------------------------------------
-- The entries
---------------------------------------------------------------------------
local function NewEntry(id, n, pe, door)
    local info = Info(id)
    local lw, lh, fromClient = ArtSize(id, n)
    local e = {
        id = id, node = n, kind = n.k, mapType = n.t, pe = pe, door = door or nil,
        name = (info and Plain(info.name, "string")) and info.name or "",
        parent = (info and Num(info.parentMapID)) and info.parentMapID or n.p,
        depth = pe and (pe.depth + 1) or 0,
        lw = lw, lh = lh, artFromClient = fromClient, ky = 1, nest = 0, yw = n.yw,
        lab = n.lab or false, link = LINK[n.k] or nil, home = n.home, cond = n.cond,
    }
    if not pe then
        e.x0, e.x1, e.y0, e.y1 = 0, 1, 0, 1
    else
        local r = n.r
        local pw, ph = pe.x1 - pe.x0, pe.y1 - pe.y0
        local root = maps[T.root]
        e.x0, e.x1, e.y0 = pe.x0 + r[1] * pw, pe.x0 + r[3] * pw, pe.y0 + r[2] * ph
        -- (true shape: the height from the width by the art's aspect, in the root's units)
        e.y1 = e.y0 + (e.x1 - e.x0) * (root.lw / root.lh) * (lh / lw)
        if n.lr then
            -- (the link's rect on the parent: the inset's printed place - its hit area, and where its picture is
            -- clipped to as it switches on)
            local lr = n.lr
            e.hit = { x0 = pe.x0 + lr[1] * pw, x1 = pe.x0 + lr[3] * pw, y0 = pe.y0 + lr[2] * ph, y1 = pe.y0 + lr[4] * ph }
        end
    end
    e.cx, e.cy = (e.x0 + e.x1) / 2, (e.y0 + e.y1) / 2
    e.area = (e.x1 - e.x0) * (e.y1 - e.y0)
    return e
end

local function DepthOf(id)
    local d, n = 0, N[id]
    while n and n.p and d < 20 do
        d = d + 1
        n = N[n.p]
    end
    return d
end

local function BuildEntries()
    wipe(maps)
    wipe(alts)
    wipe(all)
    local ids = {}
    for id in pairs(N) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        local da, db = DepthOf(a), DepthOf(b)
        if da ~= db then return da < db end
        return a < b
    end)
    for _, id in ipairs(ids) do
        local n = N[id]
        local pe = n.p and maps[n.p]
        if n.p == nil or pe then
            local e = NewEntry(id, n, pe)
            maps[id] = e
            all[#all + 1] = e
        end
    end
    -- second doors: an inset of the real node's art at another link (Nazjatar on Zandalar)
    for _, d in ipairs(T.doors or {}) do
        local main, pe = maps[d.id], maps[d.p]
        if main and pe then
            local n = { p = d.p, k = "inset", t = main.node.t, a = main.node.a, r = d.r, lr = d.lr, lnk = d.lnk, hold = 1,
                yw = main.node.yw, lab = main.node.lab }
            local e = NewEntry(d.id, n, pe, true)
            alts[d.id] = alts[d.id] or {}
            table.insert(alts[d.id], e)
            all[#all + 1] = e
        end
    end
    for key, members in pairs(T.g or {}) do
        for _, id in ipairs(members) do groupOf[id] = key end
        if not shown[key] then shown[key] = key end
    end
end

local hiddenVis = {} -- (1.4.0-beta3, G9) [id] = true: a map this character does not see (Phases)

-- Is entry e drawn at all now: its group's shown member, its conditional link listed, its parents too?
local function Visible(e)
    local g = groupOf[e.id]
    if g and shown[g] ~= e.id then return false end
    if hiddenVis[e.id] then return false end
    -- ((1.4.0-beta8) a nested zone with its home: Sunstrider Isle, no condition of its own, in the old Eversong Woods - hidden
    -- from a character the game hides that from)
    if e.home and hiddenVis[e.home] then return false end
    if e.cond and not listed[e.id] then return false end
    if e.pe and not e.pe.visibleNow then return false end
    return true
end

local function ByDraw(a, b)
    if a.depth ~= b.depth then return a.depth < b.depth end
    if a.area ~= b.area then return a.area > b.area end
    if a.id ~= b.id then return a.id < b.id end
    return (a.door and 1 or 0) < (b.door and 1 or 0)
end

---------------------------------------------------------------------------
-- What may hold or bound the camera (Core.lua NearestHoldable, Holds: e.holdAt - 1.4.0-beta1, the reviews of 1.4.0-beta1)
---------------------------------------------------------------------------
-- (Core: e.holdAt(e, c, v) -> the zoom of e up to which it may show / bound view c) an inset or a portal: only while the
-- camera's point is on its link's rect, as the focus has it (SpaceFocus) - else the hand-over gave Blizzard's map to
-- Argus while the Broken Isles' zone beside it was drawn (the settle now draws Blizzard's map: Core.lua BeginSettle)
local function HoldAt(M, c)
    local h = M.hit
    if h and not (c.x >= h.x0 and c.x <= h.x1 and c.y >= h.y0 and c.y <= h.y1) then return 0 end
    return M.holdMax
end
-- ((1.4.0-beta10) a map Blizzard's canvas never shows: Holds' zoom limit 0 - below every zoom it is asked at)
local function NeverHold() return 0 end

-- (a world's child reaching past it by more than this share of the world's size: RootHoldAt)
local REACH_MIN = 0.02

-- The Cosmic map (the review of the pictures, point 8: with holdMax 14.45 everywhere its "AZEROTH" ribbon showed at 6x
-- under Pandaria):
--   * over a world (the view's centre on its picture or on a child reaching past it) up to that world's fit - from there
--     the world bounds the camera -, or, while the view reaches over the part of such a child beyond the world's edge
--     (Kalimdor west of Azeroth by 6%, the Eastern Kingdoms east by 10% - not Khaz Algar's 1% south), up to that child's
--     fit: zoomed in at the Draenei isles the view is not pushed off them, and that child's own picture (its sea) shows
--     beyond the world's edge;
--   * over open space up to the largest world's fit (maxZoom): no diving into empty space.
local function RootHoldAt(M, c, v)
    if not (v and v.W and v.W > 0) then return M.holdMax end
    local zr = ns.ZoomOf(v, M, c.vw)
    local ppx, ppy = ns.PixelsPerUnit(v, c.vw)
    local x0, x1 = c.x - v.W / 2 / ppx, c.x + v.W / 2 / ppx
    local y0, y1 = c.y - v.H / 2 / ppy, c.y + v.H / 2 / ppy
    for _, w in ipairs(kids[M] or {}) do
        local over = c.x >= w.x0 and c.x <= w.x1 and c.y >= w.y0 and c.y <= w.y1
        for _, k in ipairs(reach[w] or {}) do
            if not over and c.x >= k.x0 and c.x <= k.x1 and c.y >= k.y0 and c.y <= k.y1 then over = true end
        end
        if over then
            local far = zr / ns.ZoomOf(v, w, c.vw)
            for _, k in ipairs(reach[w] or {}) do
                -- (the view on k, and that part of it beyond w)
                local a0, a1, b0, b1 = math.max(x0, k.x0), math.min(x1, k.x1), math.max(y0, k.y0), math.min(y1, k.y1)
                if a0 < a1 and b0 < b1 and (a0 < w.x0 or a1 > w.x1 or b0 < w.y0 or b1 > w.y1) then
                    far = math.max(far, zr / ns.ZoomOf(v, k, c.vw))
                end
            end
            return far * (1 + 1e-6)
        end
    end
    return M.maxZoom
end

-- drawList, holders and the placement children from the shown members; in place, between frames.
local function Rebuild()
    wipe(drawList)
    wipe(holders)
    wipe(kids)
    local root = maps[T.root]
    for _, e in ipairs(all) do
        e.visibleNow = Visible(e)
        e.spaceHidden = not e.visibleNow or nil
        e.holder = nil
        if e.visibleNow and e ~= root then drawList[#drawList + 1] = e end
    end
    table.sort(drawList, ByDraw)
    for i, e in ipairs(drawList) do
        e.order = i
        if e.pe then
            kids[e.pe] = kids[e.pe] or {}
            table.insert(kids[e.pe], e)
        end
    end
    -- (1.4.0-beta1) each entry's extent: its picture and every shown map placed under it, deepest first - a map draws
    -- its children while that extent is on screen (RetailRender.lua), not only its own picture: past Azeroth's east
    -- edge, on the Eastern Kingdoms' picture, the Coiled Isle and its Vaults of Atal'Utek drew nothing
    local ext = function(e)
        local x = e.ext or {}
        x.x0, x.x1, x.y0, x.y1 = e.x0, e.x1, e.y0, e.y1
        for _, k in ipairs(kids[e] or {}) do
            local q = k.ext
            if q.x0 < x.x0 then x.x0 = q.x0 end
            if q.x1 > x.x1 then x.x1 = q.x1 end
            if q.y0 < x.y0 then x.y0 = q.y0 end
            if q.y1 > x.y1 then x.y1 = q.y1 end
        end
        e.ext = x
    end
    for i = #drawList, 1, -1 do ext(drawList[i]) end
    ext(root)
    -- the hand-over score: by the depth in the tree; a link child (an inset, a portal) over the zones beside it; a zone
    -- lying wholly inside another of its parent (a capital in its zone) over it
    for _, e in ipairs(drawList) do
        local nest = 0
        if e.kind == "zone" then
            for _, o in ipairs(kids[e.pe] or {}) do
                if o ~= e and o.kind == "zone" and o.area > e.area and e.x0 >= o.x0 and e.x1 <= o.x1 and e.y0 >= o.y0 and e.y1 <= o.y1 then
                    nest = nest + 1
                end
            end
        end
        e.hscore = e.depth * 100000 + (e.link and 20000 or 0) + nest * 1000
    end
    -- the maps that bound the camera. The Cosmic map: the wheel stops over open space at the largest world's fit (its
    -- maxZoom: no diving into empty space); it bounds the camera further, up to the fit of the deepest map that reaches
    -- past its world's picture (Khaz Algar, Kalimdor, the Eastern Kingdoms): until that map can take the view, a zoom
    -- aimed at its edge would be pushed off its aim by the world's edge (the 1.4.0-beta1 walk: aimed at Durotar from
    -- space, the view ended east of it)
    -- (1.4.0-beta1: holdMax only while the view reaches over such a map's picture beyond its world, by more than
    -- REACH_MIN of the world's size - RootHoldAt)
    local fit, far = 1, 1
    wipe(reach)
    for _, w in ipairs(kids[root] or {}) do
        fit = math.max(fit, 1 / (w.x1 - w.x0))
        local mx, my = REACH_MIN * (w.x1 - w.x0), REACH_MIN * (w.y1 - w.y0)
        for _, c in ipairs(kids[w] or {}) do
            if c.x0 < w.x0 - mx or c.x1 > w.x1 + mx or c.y0 < w.y0 - my or c.y1 > w.y1 + my then
                far = math.max(far, 1 / (c.x1 - c.x0))
                reach[w] = reach[w] or {}
                table.insert(reach[w], c)
            end
        end
    end
    root.maxZoom = fit * (1 + 1e-6)
    root.holdMax = math.max(fit, far) * (1 + 1e-6)
    root.holdAt = RootHoldAt
    root.holder = true
    -- (1.4.0-beta3, WoW Forever parity: its root, Azeroth, bounds the camera at every zoom - Core.lua NearestHoldable) the
    -- Cosmic map bounds it at every zoom too: a drag or a zoom goes on past a world's edge into space, the world's picture
    -- fading softly into it (RetailRender.lua's globe edge). Its canvas and the wheel keep holdMax / maxZoom: Blizzard's
    -- map shows space only up to there (Holds), and no wheel dives into empty space
    root.boundsAll = true
    holders[1] = root
    for _, e in ipairs(drawList) do
        if e.mapType <= 2 or e.node.hold then
            e.holder = true
            holders[#holders + 1] = e
        end
        -- (an inset or a portal: holds the view only while the camera's point is on its link's rect - HoldAt)
        if e.hit then e.holdMax, e.holdAt = math.huge, HoldAt else e.holdMax, e.holdAt = nil, nil end
        -- ((1.4.0-beta10, the player on 1.4.0-beta9 at the Maelstrom: "the highlighted area and zone don't make sense, for
        -- where the zone is") a portal never: its places lie where the add-on pulls them together (RetailTree.lua,
        -- tools/retail/corrections.py PORTAL_PACK - 1.4.0-beta7), Blizzard's map of it has them where Blizzard does - its
        -- zone highlight, its hover name, its pins stood in the sea beside the Lost Isles and Kezan. The map under it
        -- (Azeroth) or the place itself (the Lost Isles, Kezan: their own maps, laid out as drawn) takes the view.
        if e.kind == "portal" then e.holdAt = NeverHold end
    end
    -- ((1.4.0-beta12) the shown maps changed: what is read from them once - RetailCaves.lua's deepest map at a cave - again)
    ns.SpaceGen = (ns.SpaceGen or 0) + 1
end

-- Does the game name conditional link child o at the middle of its link's rect on its parent? (1.4.0-beta1, the review
-- of the code, point 4: GetMapLinksForMap lists the AreaPOI map links - docs/retail-engine.md section 10 -, maybe never
-- Siren Isle's inset; GetMapInfoAtPosition goes by the map's own links, the player's condition included.)
local function NamedAtLink(o)
    local lr = o.node.lr
    if not (lr and o.pe and C_Map and C_Map.GetMapInfoAtPosition) then return false end
    local ok, info = pcall(C_Map.GetMapInfoAtPosition, o.pe.id, (lr[1] + lr[3]) / 2, (lr[2] + lr[4]) / 2)
    local id = ok and type(info) == "table" and info.mapID
    local guard = 0
    while Num(id) and id ~= 0 and id ~= o.pe.id and guard < 8 do
        if id == o.id then return true end
        local pi = Info(id)
        id = pi and pi.parentMapID
        guard = guard + 1
    end
    return false
end

local prevReal, swapFrom

-- The conditional links the game shows now (Siren Isle: drawn only while C_Map.GetMapLinksForMap(its parent) lists it,
-- or - 1.4.0-beta1 - GetMapInfoAtPosition names it in its link's rect, or Blizzard's map shows it: OnRealMapChanged).
-- (Only links with a player condition are gated: GetMapLinksForMap lists AreaPOI map links - MapLinkDataProvider.lua -,
-- not every UiMapLink inset; the stamp records what it lists for every link parent.)
local function ReadLinks()
    local changed, seen = false, {}
    for _, e in ipairs(all) do
        local p = e.node.lnk and e.pe
        if p and not seen[p] then
            seen[p] = true
            local got, list = {}, {}
            local ok, links = false, nil
            if C_Map and C_Map.GetMapLinksForMap then ok, links = pcall(C_Map.GetMapLinksForMap, p.id) end
            if ok and type(links) == "table" then
                for _, l in ipairs(links) do
                    local c = type(l) == "table" and l.linkedUiMapID
                    if Num(c) then
                        got[c] = true
                        list[#list + 1] = c
                    end
                end
            end
            for _, o in ipairs(all) do
                if o.cond and o.pe == p then
                    local on = got[o.id] == true or prevReal == o.id or NamedAtLink(o)
                    if listed[o.id] ~= on then changed = true end
                    listed[o.id] = on
                end
            end
            if stamp then stamp.links[p.id] = table.concat(list, " ") end
        end
    end
    return changed
end

---------------------------------------------------------------------------
-- Util.lua's registry, retail's
---------------------------------------------------------------------------
-- (installed before Core.lua's own hook, so it runs first) the map Blizzard shows now: a group member it shows becomes
-- the one that draws (the floor list, a phase); the one shown before is kept for ns.SpaceSwap. (1.4.0-beta1, the review
-- of the code, point 4) a conditional link it shows is one the game has for this character: it draws from now on (a
-- click on Siren Isle was undone by the next notch - the add-on drew Khaz Algar over it and flew to the Isle of Dorn).
local function OnRealMapChanged()
    local id = WorldMapFrame:GetMapID()
    swapFrom, prevReal = prevReal, id
    local g = groupOf[id]
    local changed = false
    if g and shown[g] ~= id and maps[id] then
        shown[g] = id
        changed = true
    end
    local e = maps[id]
    if e and e.cond and not listed[id] then
        listed[id] = true
        changed = true
    end
    if changed then Rebuild() end
end

---------------------------------------------------------------------------
-- (1.4.0-beta3, G9) Phases per character (RetailPlaces.lua vis, alt - docs/retail-places.md 4)
---------------------------------------------------------------------------
-- The maps the game shows this character under map p (every descendant: C_Map.GetMapChildrenInfo leaves out a map whose
-- player condition fails); nil: no answer (nothing is hidden on no answer).
local function ChildrenOf(p)
    if not (C_Map and C_Map.GetMapChildrenInfo) then return nil end
    local ok, list = pcall(C_Map.GetMapChildrenInfo, p, nil, true)
    if not ok or type(list) ~= "table" or #list == 0 then return nil end
    local out = {}
    for _, c in ipairs(list) do
        local id = type(c) == "table" and c.mapID
        if Num(id) then out[id] = true end
    end
    return out
end
local function BestMap()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
    if ok and Num(id) then return id end
end
-- vis: a map only some characters see - hidden while the game's children list leaves it out; alt: of a place's maps the
-- one this character sees - "c" the one the children list names, "u" the one the player is on - drawn in its group (the
-- tree's g: in place, as a floor), unless Blizzard's map shows another member now (its choice wins). Members off the tree
-- (RetailPlaces.lua nodes: the old Quel'Thalas, the orphan copies) are not drawn (docs/retail-engine.md 14.8).
local function Phases()
    local PL = ns.RETAIL_PLACES
    if type(PL) ~= "table" then return false end
    local changed = false
    local cache = {}
    local function Kids(p)
        if cache[p] == nil then cache[p] = ChildrenOf(p) or false end
        return cache[p] or nil
    end
    for id, parent in pairs(PL.vis or {}) do
        local kids = Kids(parent)
        local hide = kids ~= nil and not kids[id]
        if (hiddenVis[id] == true) ~= hide then
            hiddenVis[id] = hide or nil
            changed = true
        end
    end
    local best
    for _, s in ipairs(PL.alt or {}) do
        local m = s.m or {}
        local pick
        if s.how == "u" then
            best = best or BestMap() or false
            for _, x in ipairs(m) do if x == best then pick = x end end
        else
            local e = maps[m[1]]
            local kids = e and e.pe and Kids(e.pe.id)
            for _, x in ipairs(kids and m or {}) do
                if kids[x] then
                    pick = x
                    break
                end
            end
        end
        local g = pick and groupOf[pick]
        if g and maps[pick] and shown[g] ~= pick and not (prevReal and groupOf[prevReal] == g) then
            shown[g] = pick
            changed = true
        end
    end
    return changed
end
function ns.SpacePhases()
    if built and Phases() then Rebuild() end
end
ns.SpaceHiddenVis = hiddenVis -- (tests: read only)

function ns.BuildRegistry()
    if not built then
        BuildEntries()
        built = true
        ReadLinks()
        Phases()
        Rebuild()
    end
    -- (1.4.0-beta1: the stamp builds the registry at PLAYER_LOGIN, maybe before Blizzard's map is there - its hooks then
    -- come with Core's Setup)
    if not hooked and WorldMapFrame and WorldMapFrame.OnMapChanged then
        hooked = true
        hooksecurefunc(WorldMapFrame, "OnMapChanged", OnRealMapChanged)
        WorldMapFrame:HookScript("OnShow", function()
            local a = ReadLinks()
            if Phases() or a then Rebuild() end -- ((1.4.0-beta3) G9: the phases this character sees)
        end)
    end
    return maps[T.root] ~= nil
end

-- Map id's entry - for a map with a second door, the one nearest the camera; nil for a map off the tree (Core goes
-- off there: Blizzard's map).
function ns.GetMap(id)
    local e = id and maps[id]
    local more = e and alts[id]
    if not more then return e end
    local core = ns.Core
    local c = core and core.Cam and core.Cam()
    if not c then return e end
    local function D(m)
        local dx = math.max(m.x0 - c.x, 0, c.x - m.x1)
        local dy = math.max(m.y0 - c.y, 0, c.y - m.y1)
        return dx * dx + dy * dy
    end
    local best, bd = e, D(e)
    for _, m in ipairs(more) do
        local d = D(m)
        if d < bd then best, bd = m, d end
    end
    return best
end

local function Holds(e, x, y)
    local h = e.hit or e
    return x >= h.x0 and x <= h.x1 and y >= h.y0 and y <= h.y1
end
ns.SpaceHolds = Holds
-- (RetailRender.lua) the shown entries placed on entry e, and every entry (main and door, parents first)
function ns.SpaceKids(e) return kids[e] end
ns.SpaceAll = all

-- The most detailed map at (x, y): the deepest in the tree whose picture - for an inset its link's rect, switched on
-- or not (the review, point 3) - holds the point; at one depth a link child before the zones beside it, then the
-- smaller. The Cosmic map over open space (its maxZoom: no diving into empty space).
function ns.DeepestMapAt(x, y)
    local best
    for _, e in ipairs(drawList) do
        if Holds(e, x, y) then
            if not best or e.depth > best.depth or (e.depth == best.depth and ((e.link and not best.link)
                or ((e.link ~= nil) == (best.link ~= nil) and e.area < best.area))) then
                best = e
            end
        end
    end
    return best or maps[T.root]
end

-- (1.4.0-beta12 - RetailParty.lua's Ancestor, now for Core.lua's LeaveOff too) The nearest map above game map id that the
-- placement tree draws (id itself if it does; its UiMap parents up, at most 8 steps); nil: none
function ns.SpaceAncestor(id)
    local guard = 0
    while Num(id) and id ~= 0 and guard < 8 do
        local e = ns.GetMap(id)
        if e and e.visibleNow then return e end
        local ok, info = pcall(C_Map.GetMapInfo, id)
        id = ok and type(info) == "table" and info.parentMapID
        guard = guard + 1
    end
end

---------------------------------------------------------------------------
-- (1.4.0-beta12) A click on the map (Core.lua OurClick - at rest and held): Blizzard's own navigation in the add-on's
-- layout. Blizzard's map opens the child under the cursor and goes to its parent on a right click, as Blizzard lays its
-- one map out (over Azeroth not where the add-on draws the continents at their true shape) - and while the map holds,
-- Blizzard's map is another map: the player's 1.4.0-beta11 session, "no zones or objectives are interactable".
---------------------------------------------------------------------------
local NAV_IN, NAV_OUT = 0.9, 1.1 -- (a map whose whole view is this much narrower than the view: one to go into; wider: out)
local NAV_KINDS = { globe = true, cont = true, inset = true, portal = true, zone = true }
-- (the maps whose children lie where Blizzard lays them out: a zone's place on its continent, a city's on its zone - not a
-- world's continents at their true shape, a portal's places pulled together)
local NAV_ASK = { cont = true, inset = true, zone = true }
local function Navigable(e)
    return NAV_KINDS[e.kind] and not e.door and e.visibleNow ~= false and not e.spaceHidden
end
-- A left click: the next map down under the cursor - on the map the view shows (the narrowest holding the point whose
-- whole view is at least the view's), the child Blizzard's own navigation names there (C_Map.GetMapInfoAtPosition, as
-- MapCanvasMixin:NavigateToCursor: the zone's own shape, where zones' rects overlap), else of the maps holding the point
-- whose whole view is narrower, the widest; a right click: the next map out - of the maps holding the view's middle whose
-- whole view is wider, the narrowest. A flight to that map whole. True: the click is the map's (nothing to go to as well).
function ns.SpaceNavigate(button)
    local core = ns.Core
    if button ~= "LeftButton" and button ~= "RightButton" then return false end
    if not (core and core.Cam and core.CursorPos and core.FlyToView) then return false end
    local cam, v = core.Cam()
    if not (cam and v and Num(v.W) and v.W > 0) then return false end
    local px, py = cam.x, cam.y
    if button == "LeftButton" then
        local sx, sy = core.CursorPos()
        local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)
        px, py = cam.x + (sx - v.W / 2) / ppx, cam.y + (sy - v.H / 2) / ppy
    end
    local best, bw, on, onW
    for _, e in ipairs(drawList) do
        if Navigable(e) and Holds(e, px, py) then
            local w = ns.WidthForZoom(v, e, 1)
            if button == "LeftButton" then
                if w < cam.vw * NAV_IN and (not bw or w > bw) then best, bw = e, w end
                if w >= cam.vw * NAV_IN and (not onW or w < onW) then on, onW = e, w end
            elseif w > cam.vw * NAV_OUT and (not bw or w < bw) then
                best, bw = e, w
            end
        end
    end
    if button == "LeftButton" and on and NAV_ASK[on.kind] and on.id > 0 and C_Map and C_Map.GetMapInfoAtPosition then
        local ok, info = pcall(C_Map.GetMapInfoAtPosition, on.id, (px - on.x0) / (on.x1 - on.x0), (py - on.y0) / (on.y1 - on.y0))
        local c = ok and type(info) == "table" and Num(info.mapID) and info.mapID ~= on.id and maps[info.mapID]
        if c and Navigable(c) and Holds(c, px, py) then
            local w = ns.WidthForZoom(v, c, 1)
            if w < cam.vw * NAV_IN then best, bw = c, w end
        end
    end
    if best then core.FlyToView(best.cx, best.cy, math.min(bw, 1)) end
    return true
end

---------------------------------------------------------------------------
-- Focus (Core.lua UpdateFocus, FocusRealMap, a flight's landing)
---------------------------------------------------------------------------
-- The child of map e that GetMapInfoAtPosition names at (x, y), walked up its UiMap parents to one placed on e.
local function NamedChild(e, x, y, want)
    if not (C_Map and C_Map.GetMapInfoAtPosition) then return nil end
    local ok, info = pcall(C_Map.GetMapInfoAtPosition, e.id, (x - e.x0) / (e.x1 - e.x0), (y - e.y0) / (e.y1 - e.y0))
    local id = ok and type(info) == "table" and info.mapID
    local guard = 0
    while Num(id) and id ~= 0 and id ~= e.id and guard < 8 do
        local m = maps[id]
        if m and m.pe == e and m.visibleNow and want(m) and Holds(m, x, y) then return m end
        local pi = Info(id)
        id = pi and pi.parentMapID
        guard = guard + 1
    end
end

local function NotZone(m) return m.kind ~= "zone" end
local function IsZone(m) return m.kind == "zone" end

local lastCont -- the last continent-level focus (over sea it stays while it holds the point)

-- The child of e holding (x, y) that is not a zone: a link child first (its link rect; the smallest), else the one
-- GetMapInfoAtPosition names, else - over sea - the current one while it holds the point, else the smallest holding it.
local function ChildAt(e, x, y)
    local best
    for _, m in ipairs(kids[e] or {}) do
        if m.link and Holds(m, x, y) and (not best or (m.hit or m).x1 - (m.hit or m).x0 < (best.hit or best).x1 - (best.hit or best).x0) then
            best = m
        end
    end
    if best then return best end
    best = NamedChild(e, x, y, NotZone)
    if best then return best end
    for _, m in ipairs(kids[e] or {}) do
        if m == lastCont and not m.link and NotZone(m) and Holds(m, x, y) then return m end
    end
    for _, m in ipairs(kids[e] or {}) do
        if not m.link and NotZone(m) and Holds(m, x, y) and (not best or m.area < best.area) then best = m end
    end
    return best
end

-- The zone of e at (x, y): GetMapInfoAtPosition's, else the smallest zone rect holding the point; a capital only as its
-- own picture is about to show (else its home zone).
local function HomeIn(m, z)
    local h, guard = m.home, 0
    while h and guard < 4 do
        if h == z.id then return true end
        local hm = maps[h]
        h, guard = hm and hm.home, guard + 1
    end
    return false
end

-- (can map m's canvas show camera view c whole: past its fit, the view inside its picture - half a pixel's slack)
local function ViewIn(m, c, v)
    if ns.ZoomOf(v, m, c.vw) < 1 - 1e-4 then return false end
    local ppx, ppy = ns.PixelsPerUnit(v, c.vw)
    local hx, hy = v.W / 2 / ppx, v.H / 2 / ppy
    local tx, ty = 0.5 / ppx, 0.5 / ppy
    return c.x - hx >= m.x0 - tx and c.x + hx <= m.x1 + tx and c.y - hy >= m.y0 - ty and c.y + hy <= m.y1 + ty
end

local function ZoneAt(e, x, y, c, v, focus)
    local z = NamedChild(e, x, y, IsZone)
    -- a zone lying in another (a capital, a starting area: its home) whose rect and home hold the point - the smallest;
    -- the game may name its home there (whose UiMap child it is) or a neighbour whose rect reaches over it (Drustvar's
    -- over Boralus): it goes first, and the home rule below decides
    local inner
    for _, m in ipairs(kids[e] or {}) do
        if m.kind == "zone" and m ~= z and m.home and Holds(m, x, y) and (not inner or m.area < inner.area) then
            local h = maps[m.home]
            if h and Holds(h, x, y) then inner = m end
        end
    end
    if not z and not inner then
        for _, m in ipairs(kids[e] or {}) do
            if m.kind == "zone" and Holds(m, x, y) and (not z or m.area < z.area) then z = m end
        end
    end
    z = inner or z
    -- (1.4.0-beta1, the reviews' point 3 / 2) the zone Blizzard's map will show: when z cannot show this view whole but
    -- another zone holding the point can (past its fit, the view inside its picture - Core.lua Holds), that one, so the
    -- picture drawn while moving is the one the settle shows (the harness's GetMapInfoAtPosition named Val'sharah at
    -- Highmountain's centre: Highmountain's picture faded in only at rest). Not for a capital or a zone with a home.
    if z and not z.home and c and v and v.W and v.W > 0 and not ViewIn(z, c, v) then
        local best
        for _, m in ipairs(kids[e] or {}) do
            if m.kind == "zone" and m ~= z and not m.home and Holds(m, x, y) and ViewIn(m, c, v) and (not best or m.area < best.area) then best = m end
        end
        if best then z = best end
    end
    local guard = 0
    while z and z.home and c and v and v.W and v.W > 0 and guard < 4 do
        local need = (focus == z.id) and HOME_OUT or HOME_IN
        if ns.ZoomOf(v, z, c.vw) >= need then break end
        local h = maps[z.home]
        if not (h and h.visibleNow) then break end
        z, guard = h, guard + 1
    end
    return z
end

-- contID, zoneID at camera point (x, y): from the Cosmic map down, at each map the child holding the point - a link
-- child first, then the one the game names, then by the rects; the last that is no zone is contID; zoneID its zone
-- there. real: the map Blizzard shows (after a change someone else made): it and the chain above it win - a zone is
-- the zone, any other map the continent-level focus. c, v: Core's camera and view (the capitals' zoom).
function ns.SpaceFocus(x, y, real, c, v)
    local R = Plain(real, "number") and ns.GetMap(real)
    local focus = ns.Render and ns.Render.GetFocus and ns.Render:GetFocus()
    if R and R.kind == "zone" then
        local p = R.pe
        while p and p.kind == "zone" do p = p.pe end
        lastCont = p
        -- (1.4.0-beta1: the settle now focuses Blizzard's map) a capital drawn over its home zone stays while that home
        -- is Blizzard's map and the capital's picture shows by ZoneAt's home rule (Orgrimmar over Durotar)
        local F = focus and maps[focus]
        if F and F ~= R and F.kind == "zone" and HomeIn(F, R) and Holds(F, x, y) and c and v and v.W and v.W > 0
            and ns.ZoomOf(v, F, c.vw) >= HOME_OUT then
            return p and p.id, F.id
        end
        return p and p.id, R.id
    end
    local e = R or maps[T.root]
    local guard = 0
    while guard < 12 do
        local m = ChildAt(e, x, y)
        if not m then break end
        e, guard = m, guard + 1
    end
    lastCont = e
    local z = ZoneAt(e, x, y, c, v, focus)
    -- (1.4.0-beta1) an inset lying on a zone (Siren Isle on the Isle of Dorn, the Vaults of Atal'Utek): with its link's
    -- rect holding the point it is the map on top - its picture opens - and that zone stays drawn under it; Blizzard's
    -- map on such an inset keeps its zone too (the settle on Siren Isle left no zone: the Isle of Dorn faded and took the
    -- inset, its child, with it - at rest nothing but Khaz Algar's picture over Siren Isle's map)
    if z then
        local m, g2 = ChildAt(z, x, y), 0
        while m and m.link and g2 < 4 do
            e, lastCont = m, m
            m, g2 = ChildAt(m, x, y), g2 + 1
        end
    else
        local p, g2 = e, 0
        while p and p.link and p.pe and g2 < 4 do
            p, g2 = p.pe, g2 + 1
            if p.kind == "zone" then z = p break end
        end
    end
    return e.id, z and z.id
end

-- (Core.lua OnMapChanged) Blizzard changed its map to another member of the group it showed before (a floor from its
-- list, a phase copy): true - the picture swaps in place and the camera stays.
function ns.SpaceSwap(id)
    local g = groupOf[id]
    return g ~= nil and swapFrom ~= nil and swapFrom ~= id and groupOf[swapFrom] == g
end

---------------------------------------------------------------------------
-- Positions (Follow.lua, PartyBubbles.lua)
---------------------------------------------------------------------------
-- The map game map inst's region holding world position (x, y) belongs to (UnitPosition's first two values): the first
-- of RetailTree.lua's inst boxes that holds it (smallest first); nil when none does.
function ns.NodeForWorldPos(inst, x, y)
    local rows = Num(inst) and T.inst and T.inst[inst]
    if not rows or not (Num(x) and Num(y)) then return nil end
    for _, r in ipairs(rows) do
        if x >= r[2] and x <= r[3] and y >= r[4] and y <= r[5] and maps[r[1]] then return r[1] end
    end
end

-- The world zoom (ns.WorldZoom) of a view as wide in yards as WoW Forever's at world zoom z, at camera point (x, y): by
-- the yards across the most detailed map there that knows them (RetailTree.lua yw). Without a view or yards: z.
function ns.OpenZoomFor(x, y, z)
    local core = ns.Core
    local _, v
    if core and core.Cam then _, v = core.Cam() end
    if not (Num(z) and z > 0 and Num(x) and Num(y) and v and Num(v.W) and v.W > 0 and v.fit0) then return z end
    local best
    for _, e in ipairs(drawList) do
        if e.yw and Holds(e, x, y) and (not best or e.area < best.area) then best = e end
    end
    if not best then return z end
    local units = (OPEN_YARDS_AT_14 * 14 / z) * (best.x1 - best.x0) / best.yw -- (the view's width in the root's units)
    local vw = units * v.lw0 * v.fit0 / v.W
    return ns.WorldZoom(v, math.min(vw, 1))
end

---------------------------------------------------------------------------
-- QuestSafe's task quests (Core.lua QuestSafe)
---------------------------------------------------------------------------
-- (retail: a world quest's or a bonus objective's pin styles itself from the quest cache - POIButtonMixin:
-- GetQuestClassification -> QuestCache:Get, Blizzard_POIButton/POIButton.lua - as a quest's does; so a map whose task
-- quests Blizzard has not cached itself is not one we may switch to, as for its quests)
-- (1.4.0-beta3, G1 - the player's beta2 session: 113 worlds and 68 continents refused, their views showing another map's
-- pins) Only a task quest a pin of THIS map would style counts, as Blizzard's providers decide (retail 12.1.5's
-- WorldQuestDataProvider:RefreshAllData, BonusObjectiveDataProvider:RefreshAllData -> MapUtil.ShouldShowTask, read from the
-- client): a world quest or a map-indicator quest while the questPOIWQ CVar is on, any task of the very map (its mapID),
-- a calling on a zone. On a world or continent map (UiMap type 0 - 2) a bonus objective of a zone under it has no pin -
-- it no longer refuses the map; on a zone every task counts as before (its bonus objectives pin there), and a task the
-- client says too little of (no mapID, no answer to IsWorldQuest) counts. The stamp splits the refusals by why.
local function WorldQuest(q, t)
    if t.isMapIndicatorQuest == true then return true end
    local QL = C_QuestLog
    if not (QL and QL.IsWorldQuest) then return nil end
    local ok, wq = pcall(QL.IsWorldQuest, q)
    if ok and Plain(wq, "boolean") then return wq end
    return nil
end
-- ((1.4.0-beta12) the player's 1.4.0-beta11 session: 110 continents and 159 worlds refused for "wq" - every view of them
-- held, the map dead to the mouse. The world map's provider is WorldMap_WorldQuestDataProvider (Blizzard_WorldMap.lua):
-- its ShouldShowQuest wants the quest's own map (mapID == info.mapID) and ShouldMapShowQuest adds a child map's on a zone and
-- the tracked one on a continent - a zone's world quest on a continent's or a world's list has no pin there, so no style
-- from the cache. Those two only.)
local function TaskPinned(id, t, q, mapType)
    if not (Num(mapType) and mapType <= 2) then return true end
    local wq = WorldQuest(q, t)
    if wq == nil then return true end
    if wq then
        if GetCVarBool then
            local ok, on = pcall(GetCVarBool, "questPOIWQ")
            if ok and on == false then return false end
        end
        if not Num(t.mapID) or t.mapID == id then return true end
        if mapType == 2 and C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
            local ok, st = pcall(C_SuperTrack.GetSuperTrackedQuestID)
            if ok and Num(st) and st == q then return true end
        end
        return false
    end
    -- (a bonus objective: pinned only on its own map)
    if not Num(t.mapID) then return true end
    return t.mapID == id
end
-- ((1.4.0-beta3, the reviews of 1.4.0-beta3) the map-indicator quests: Blizzard adds them to the map's task quests
-- (SharedMapPoiTemplates.lua AddIndicatorQuestsToTasks, from C_QuestLog.GetQuestsOnMap) and its world-quest provider pins
-- them on any map - worlds and continents too - while questPOIWQ is on, styling the pin from the quest cache; Core.lua's
-- QuestSafe skips them, C_TaskQuest does not list them. One the client has data for but Blizzard has not cached refuses
-- the map, as a world quest's does.)
local function IndicatorSafe(id, Cached)
    local QL = C_QuestLog
    if not (QL and QL.GetQuestsOnMap) then return true end
    if GetCVarBool then
        local ok, on = pcall(GetCVarBool, "questPOIWQ")
        if ok and on == false then return true end
    end
    local ok, quests = pcall(QL.GetQuestsOnMap, id)
    if not ok or type(quests) ~= "table" then return true end
    for _, q in ipairs(quests) do
        local qid = type(q) == "table" and q.questID
        local ind = type(q) == "table" and q.isMapIndicatorQuest
        if Plain(ind, "boolean") and ind and Num(qid) and (not HaveQuestData or HaveQuestData(qid)) and not Cached(qid) then
            if stamp then
                local e = maps[id]
                local k = e and e.kind or "off"
                stamp.questRefused[k] = (stamp.questRefused[k] or 0) + 1
                stamp.questWhy = stamp.questWhy or {}
                stamp.questWhy[k .. ".ind"] = (stamp.questWhy[k .. ".ind"] or 0) + 1
            end
            return false
        end
    end
    return true
end

function ns.QuestSafeExtra(id, Cached)
    if not IndicatorSafe(id, Cached) then return false end
    local TQ = C_TaskQuest
    if not (TQ and TQ.GetQuestsOnMap) then return true end
    local ok, tasks = pcall(TQ.GetQuestsOnMap, id)
    if not ok or type(tasks) ~= "table" then return true end
    local info = Info(id)
    local mapType = info and info.mapType
    for _, t in ipairs(tasks) do
        local q = type(t) == "table" and (t.questID or t.questId)
        if Num(q) and (not HaveQuestData or HaveQuestData(q)) and not Cached(q) then
            if TaskPinned(id, t, q, mapType) then
                if stamp then
                    local e = maps[id]
                    local k = e and e.kind or "off"
                    stamp.questRefused[k] = (stamp.questRefused[k] or 0) + 1
                    local why = WorldQuest(q, t) and "wq" or "task"
                    stamp.questWhy = stamp.questWhy or {}
                    stamp.questWhy[k .. "." .. why] = (stamp.questWhy[k .. "." .. why] or 0) + 1
                end
                return false
            elseif stamp then
                stamp.questPassed = (stamp.questPassed or 0) + 1
            end
        end
    end
    return true
end

---------------------------------------------------------------------------
-- The silent stamp (EndlessMapDB.retailChecks, once per login)
---------------------------------------------------------------------------
local function RectText(a, b)
    local ok, x0, x1, y0, y1 = pcall(C_Map.GetMapRectOnMap, a, b)
    if not ok then return "error" end
    if not (Num(x0) and Num(x1) and Num(y0) and Num(y1)) then return "none" end
    return ("%.4f %.4f %.4f %.4f"):format(x0, x1, y0, y1)
end

local function Stamp()
    local db = _G[ns.SAVED] -- ((1.4.0-beta4) EndlessMapDB: OneCopy.lua)
    if type(db) ~= "table" then return end
    -- (1.4.0-beta1, the review of the code, point 6: this runs before Core's Setup builds the registry - the art sizes
    -- below were always empty; building is idempotent)
    ns.BuildRegistry()
    local s = { build = T.build, schema = T.v, links = {}, questRefused = {}, art = {}, masks = {}, peak = 0 }
    if time then
        local ok, t = pcall(time)
        if ok and Num(t) then s.at = t end
    end
    s.rects = {}
    for _, p in ipairs({ { 947, 946 }, { 13, 947 }, { 2274, 947 }, { 101, 947 }, { 1, 12 } }) do
        s.rects[p[1] .. " on " .. p[2]] = RectText(p[1], p[2])
    end
    local ok, ch = pcall(C_Map.GetMapChildrenInfo, 12)
    s.children12 = (ok and type(ch) == "table") and #ch or false
    -- ((1.4.0-beta4's fixes, the in-game probe P4) the client's own word on hidden textures: "Release Hidden UI Textures" -
    -- with it on, a texture hidden lets its file go (what RetailRender.lua's Reshow asks the client about each part shown
    -- again); a diagnostic, read once a session)
    if GetCVar then
        local okc, cv = pcall(GetCVar, "releaseUITextures")
        s.releaseUITextures = (okc and Plain(cv, "string")) and cv or false
    end
    -- (the art sizes the client gives where they differ from the tree's)
    local n = 0
    for _, e in ipairs(all) do
        if not e.artFromClient then
            s.art[#s.art + 1] = e.id .. " not read"
        elseif e.lw ~= e.node.a[1] or e.lh ~= e.node.a[2] then
            s.art[#s.art + 1] = ("%d %dx%d (tree %dx%d)"):format(e.id, e.lw, e.lh, e.node.a[1], e.node.a[2])
        end
        n = n + 1
    end
    s.nodes = n
    db.retailChecks = s
    stamp = s
    ns.retailStamp = s -- (RetailRender.lua adds the masks' answers and the texture high-water mark)
    ReadLinks()
end

-- (1.4.0-beta3, G9) a zone changed: the phases this character sees may have
local pev = CreateFrame("Frame")
pev:RegisterEvent("PLAYER_ENTERING_WORLD")
pev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
pev:SetScript("OnEvent", function() ns.SpacePhases() end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    self:SetScript("OnEvent", nil)
    local ok = pcall(Stamp)
    if not ok then stamp = nil end
end)
