--[[
Endless Map - one continuous camera over the whole world map.

Scroll from the Azeroth map straight down into a zone and past it (e.g. onto
the Deadmines entrance), drag across zone borders, no map-switch jumps.

How it stays friendly with Questie and other map addons:
  * We draw the map art ourselves (world, continents and zones blended by
    zoom) on an overlay that sits inside Blizzard's map canvas, just
    *underneath* the pin layers, so Questie's icons, Blizzard's POIs and the
    player arrow always draw on top of our art.
  * We keep Blizzard's own map pointed at exactly our view with its public
    methods (SetMapID + ScrollContainer:InstantPanAndZoom): at rest, and
    also every frame while you scroll, drag or fly - the way Blizzard's own
    zoom animation updates its canvas every frame - so the pins move with
    the map instead of vanishing until it stops. The map it shows is one
    that can display exactly our view (switching like Blizzard's map does
    when you navigate); only where no map can (or in combat, where we never
    switch maps) is Blizzard's canvas hidden until the view settles.
  * No Blizzard tables are replaced or written to; we only use
    hooksecurefunc / HookScript and Blizzard's own methods.
  * (1.1.1) Those methods run under our taint, though: a map switch we make
    refreshes Blizzard's quest pins, which fill the quest cache the objective
    tracker reads. We only switch to maps whose quests Blizzard has cached
    itself (QuestSafe) - the tracker stays clean.
]]

local ADDON, ns = ...
if ns.inert then return end -- (1.3.1: another copy of the add-on runs - OneCopy.lua)

local DEFAULTS = {
    enabled = true,
    maxZoom = 4,         -- how far past a zone's normal size you can zoom in
    zoomStep = 1.3,      -- zoom factor per mouse-wheel notch
    labels = true,       -- show important places
    labelsAtRest = true, -- keep them on the map when it isn't moving
    flightPaths = true,
    mosaic = true,       -- zone land shapes in their map style (see Render.lua)
    cells = true,        -- ...cut by zone-cell masks (off: by explored-area shapes)
    livePins = true,     -- map icons move with the map (off: hidden until it stops)
    flySpeed = 1,        -- speed multiplier for click flights
    dungeons = true,     -- dungeon maps (Dungeon.lua, WoW Forever)
    engineMarkers = true, -- group on entrance maps drawn by the game's own widget (DungeonMarkers.lua; off: addon dots)
    bosses = true,       -- (1.0.0) boss and entrance markers on dungeon maps (DungeonBosses.lua)
    doorHints = true,    -- (1.0.0) placeholder icons for the instances not in the game files yet (Doors.lua)
    zoomReadout = false, -- (1.0.0) /unroll zoom: the zoom numbers on the map (ZoomReadout.lua)
    cityZoom = ns.Render.CITY_G, -- (1.0.0) WORLD zoom from which every city / detail map shows (/unroll cityzoom; false: 1.5x of their zone)
    follow = true,       -- (1.1.0) a click on your arrow / a party member's dot follows them (Follow.lua; /unroll follow)
    openZoom = 14,       -- (1.1.0) M opens the map on your character at this WORLD zoom (false: as the game does)
    openFollow = true,   -- (1.2.0) ...and follows you (Follow.lua; /unroll openfollow)
    caveZoom = ns.Render.CAVE_G, -- (1.2.0) WORLD zoom from which the caves show (Caves.lua; /unroll cavezoom; false: never)
}

DEFAULTS.portals = true -- ((1.4.0-beta14) the ways across the world: Portals.lua)

local IDLE_DELAY = 0.2      -- seconds without input before handing over
local ZOOM_RATE = 14        -- how quickly the zoom catches up to the wheel
local MOMENTUM_DECAY = 5
-- free texture memory this long after closing ((1.4.0-beta14) retail's a minute: closed and opened again within it, the map reloads
-- nothing - the player's 1.4.0-beta13 session set 47,791 tiles for 17,649 textures; the client lets a hidden file go by itself)
local RELEASE_DELAY = (ns.FLAVOR == "retail") and 60 or 10
local LIVE_SWITCH_DELAY = 0.15 -- mid-motion, a better real map takes over once preferred this long
local FOLLOW_RATE = 6          -- (1.1.0) how quickly the camera catches up with the unit it follows (Follow.lua)
local FOLLOW_ZONE_CHECK = 0.5  -- (1.1.0) how often a followed view on a continent map looks for a zone map again

-- Absolute frame levels. Map pins live at 2000-9000 (Questie icons 2015+).
-- (only while Blizzard's canvas can't follow the view, see SyncMoving)
local OVERLAY_LEVEL_MOVING = 9100 -- above every pin while we drive the view
local LABELS_LEVEL_MOVING = 9400
local CATCHER_LEVEL = 9100         -- takes the mouse while the map moves
-- At rest our art lives in a band just below every map pin (pins start at
-- 2000) and above Blizzard's own map tiles. The only Blizzard art drawn over
-- it is the current map's explored areas, which match ours pixel for pixel -
-- except where we draw a more detailed picture over that map (a city inside
-- its zone): those pictures go just above the explored areas (liftLo..liftHi).
local REST_BAND = 40
local REST_LEVEL_FALLBACK = 2000 - REST_BAND - 1
local LABELS_LEVEL_REST_FALLBACK = 2014  -- above highlights, below Questie (2015+)

local WHEEL_NONE = MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_NONE or 3

local db
local container, overlay, labelLayer, cityLayer, driver, catcher
local ready = false
local fourArgPanZoom = false
local blizzWheelMode, wheelIsOurs
local restLevel = REST_LEVEL_FALLBACK
local restStageCap = REST_LEVEL_FALLBACK + REST_BAND
local labelsRestLevel = LABELS_LEVEL_REST_FALLBACK
local liftLo, liftHi -- levels just above Blizzard's exploration pin (Render:SetRestLift)
local cityLevel      -- (1.0.0) the city layer's level at rest: above Blizzard's map art pins (see Setup)
local cityLevelZone  -- (1.0.0) the same over a zone map: just above its explored areas (see SetOverlayMode)
local translucent = false
local dragThreshold = 4

local v = { W = 0, H = 0, lw0 = 1, lh0 = 1, fit0 = 1 } -- view metrics
local cam = { x = 0.5, y = 0.5, vw = 1 }                 -- world-normalized camera
local state = "off"      -- off | rest | free | fly | hold
local targetVw = 1
local anchor             -- wheel zoom anchor { wx, wy, sx, sy, ax, ay, asx, asy } (the aim: see CityZoom)
local restAim            -- the last wheel anchor when a rest cut it off: a slow, notch-by-notch zoom
                         -- into a city keeps aiming at the spot first pointed at (see OnMouseWheel)
local drag = { pending = false, active = false, swallow = false }
local vel = { x = 0, y = 0 }                             -- screen units / second
local lastInput = 0
local fly
local syncing = false
local justShown = false
local realDirty = false
local restBusy = false
local focusCheckT = 0
local hideGen = 0
-- Live motion: Blizzard's canvas (and its pins) follows the camera while
-- moving. live = it is in sync this frame; liveS/P/Q = the view we gave it;
-- liveT = GetTime() of the last sync; livePrefID/T = a better map waiting
-- to take over (hysteresis).
local live = false
local liveS, liveP, liveQ, liveT
local livePrefID, livePrefT = nil, 0
local lastWheel = 0 -- (1.0.0) GetTime() of the last wheel notch (LiveMap)

local Render, Labels

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function UpdateView()
    local world = ns.maps[ns.ROOT_MAP_ID] -- (1.4.0: the top of the camera's space - on retail the Cosmic map, Util.lua)
    local w, h = container:GetSize()
    if not world or not w or w <= 0 or not h or h <= 0 then return false end
    v.W, v.H = w, h
    v.lw0, v.lh0 = world.lw, world.lh
    v.fit0 = math.min(w / world.lw, h / world.lh)
    return true
end

-- Cursor in container units, origin top-left, y down.
local function CursorPos()
    local x, y = GetCursorPosition()
    local s = container:GetEffectiveScale()
    local left, top = container:GetLeft(), container:GetTop()
    if not left or not top or not s or s == 0 then return v.W / 2, v.H / 2 end
    return x / s - left, top - y / s
end

local function ScreenToWorldWith(c, sx, sy)
    local ppx, ppy = ns.PixelsPerUnit(v, c.vw)
    return c.x + (sx - v.W / 2) / ppx, c.y + (sy - v.H / 2) / ppy
end

-- The camera may only go where a real map can show exactly that view: the
-- Azeroth map, or a continent once zoomed in to at least its own fit (a
-- continent's map reaches past the Azeroth art). Returns the nearest such
-- centre for c, so the settle never has to move the camera.
-- The map that currently bounds the camera sticks until another one can show
-- the view without any correction (or it stops qualifying), so the allowed
-- area never flips back and forth under your hand.
-- Past a capital's own zone depth the view is also kept on the city (Confine,
-- defined with the capital helpers below).
local lastHolderID
local Confine
local function NearestHoldable(c)
    local ppx, ppy = ns.PixelsPerUnit(v, c.vw)
    local bx, by, bd, bid      -- nearest overall
    local zx, zy, zid          -- one that needs no correction
    local sx, sy, sd           -- the sticky one
    local function try(M)
        if not M or ns.ZoomOf(v, M, c.vw) < 1 - 1e-4 then return end
        -- (1.4.0, retail: RetailSpace.lua) a map that bounds the camera only up to a zoom - the Cosmic map, up to the
        -- largest world's fit: deeper, the view stays on a world (1.4.0-beta1: M.holdAt - that zoom for this view: the
        -- Cosmic map's by the world under it, an inset's only on its link's rect). (1.4.0-beta3, retail: M.boundsAll -
        -- the Cosmic map bounds the camera at every zoom, as WoW Forever's root, Azeroth, does: a drag goes on past a
        -- world's edge into space - the player on 1.4.0-beta2: "i cant drag out, feels bad"; its canvas still shows a
        -- view only up to holdMax, Holds. Nil on WoW Forever)
        if M.holdMax and not M.boundsAll and ns.ZoomOf(v, M, c.vw) > (M.holdAt and M.holdAt(M, c, v) or M.holdMax) then return end
        local s = (M.x1 - M.x0) * ppx / M.lw
        local xOff = math.min((v.W / 2) / (s * M.lw), 0.5)
        local yOff = math.min((v.H / 2) / (s * M.lh), 0.5)
        local wM, hM = M.x1 - M.x0, M.y1 - M.y0
        local x = ns.Clamp(c.x, M.x0 + xOff * wM, M.x1 - xOff * wM)
        local y = ns.Clamp(c.y, M.y0 + yOff * hM, M.y1 - yOff * hM)
        local d = math.sqrt(((x - c.x) * ppx) ^ 2 + ((y - c.y) * ppy) ^ 2)
        if M.id == lastHolderID then sx, sy, sd = x, y, d end
        if d < 0.5 and not zid then zx, zy, zid = x, y, M.id end
        if not bd or d < bd then bx, by, bd, bid = x, y, d, M.id end
    end
    if ns.holders then
        -- (1.4.0, retail: RetailSpace.lua) the maps that bound the camera: the Cosmic map, the worlds, continents,
        -- insets and portals, and the zones that reach past their parent's picture
        for _, M in ipairs(ns.holders) do try(M) end
    else
        try(ns.maps[ns.WORLD_MAP_ID])
        for _, e in ipairs(ns.drawList) do
            if e.mapType == ns.MAPTYPE_CONTINENT then try(e) end
        end
    end

    local x, y, id
    if sd and sd < 0.5 then x, y, id = sx, sy, lastHolderID
    elseif zid then x, y, id = zx, zy, zid
    elseif sd then x, y, id = sx, sy, lastHolderID
    else x, y, id = bx, by, bid end
    local changed = lastHolderID ~= nil and id ~= lastHolderID
    lastHolderID = id
    x, y = Confine(c, x or c.x, y or c.y)
    return x, y, changed
end

-- Clamp camera c. While zooming, or when the bounding map just changed, the
-- correction glides (capped per frame) from what was on screen, instead of
-- jumping; otherwise it's a hard edge (e.g. dragging against the map's end).
local MAX_GLIDE_PX = 16
local gliding = false
local function Limit(cur, prev, t)
    local o, po = cur - t, prev - t
    if o > 0 then return t + math.min(o, math.max(po, 0)) end
    if o < 0 then return t + math.max(o, math.min(po, 0)) end
    return cur
end
local function ClampCam(c, dt, zooming, prevX, prevY, panning, follow)
    if c.vw > 1 then c.vw = 1 end
    local x, y, changed = NearestHoldable(c)
    if changed then gliding = true end
    if ns.holders and lastHolderID == ns.ROOT_MAP_ID then
        -- (1.4.0-beta1, retail: the reviews of 1.4.0-beta1) the Cosmic map bounds the view: nothing is drawn beyond it, so
        -- a glide back would leave a blank strip at its edge (zoomed out from the Shadowlands' Bastion, up to 12% of the
        -- view for a second) - the view keeps to it at once, as at any edge outside a zoom
        c.x, c.y = x, y
        gliding = false
        return x, y
    end
    if follow and gliding then
        -- (1.3.0, following: no glide onto a view the bounding map shows as it is - the unit goes to the centre as soon
        -- as a map can show it there; a glide would trail it, and the zoom magnifies what trails)
        local ppx, ppy = ns.PixelsPerUnit(v, c.vw)
        if math.abs(x - c.x) * ppx + math.abs(y - c.y) * ppy < 0.5 then gliding = false end
    end
    if not (gliding or zooming) or not dt then
        c.x, c.y = x, y
        gliding = false
        return x, y
    end
    if panning and prevX then
        -- A drag or fling never pushes the camera further past the edge; an
        -- overshoot that's already there (from a zoom) still glides back.
        c.x, c.y = Limit(c.x, prevX, x), Limit(c.y, prevY, y)
    end
    local baseX, baseY = c.x, c.y
    if gliding and not zooming and prevX then baseX, baseY = prevX, prevY end
    local ppx, ppy = ns.PixelsPerUnit(v, c.vw)
    local dx, dy = (x - baseX) * ppx, (y - baseY) * ppy
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.02 then
        c.x, c.y = x, y
        gliding = false
    else
        local step = math.min(d, MAX_GLIDE_PX, math.max(d * (1 - math.exp(-dt * 10)), 0.3))
        c.x = baseX + (x - baseX) * step / d
        c.y = baseY + (y - baseY) * step / d
        -- Keep gliding (even once the zoom has finished) until we arrive.
        gliding = d - step >= 0.02
    end
    return x, y
end

-- Deepest map at a point: its size decides how far the wheel may zoom there (Util.lua; 1.2.0: also the caves' switch).
local DeepestAt = ns.DeepestMapAt

local function Usable()
    return ready and db.enabled and state ~= "off" and WorldMapFrame:IsShown() and v.W > 0
end

local function MouseFocus()
    if GetMouseFoci then
        local foci = GetMouseFoci()
        return foci and foci[1]
    elseif GetMouseFocus then
        return GetMouseFocus()
    end
end

local function SetBlizzardWheel(ours)
    if not WorldMapFrame.SetMouseWheelZoomMode or wheelIsOurs == ours then return end
    wheelIsOurs = ours
    WorldMapFrame:SetMouseWheelZoomMode(ours and WHEEL_NONE or blizzWheelMode)
end

-- While moving with a canvas that can't follow the view (see SyncMoving),
-- Blizzard's (stale) canvas and pins are hidden, so gaps show the map's
-- normal background just like at rest - once our own picture is complete
-- (after a cold start its art may still be loading; until then the canvas
-- stays). At rest, and while it follows the view, the canvas is aligned
-- and shows through gaps.
local overlayMoving = false
local function UpdateCanvasAlpha()
    local child = container.Child
    if not child then return end
    local want = (overlayMoving and overlay:IsShown() and Render:IsReady()) and 0 or 1
    -- (1.4.0-beta2, retail: /unroll test canvas - RetailWhy.lua - never hides the canvas, this session; nil on WoW Forever)
    if ns.retailTest and ns.retailTest.canvas then want = 1 end
    if child:GetAlpha() ~= want then child:SetAlpha(want) end
end

-- Inside the canvas our layers would inherit its zoom: undo it, so they keep
-- the container's scale (they are anchored to the container either way).
local function FitLayers()
    local p = overlay:GetParent()
    local s = (p and p ~= container) and p:GetScale() or 1
    if not s or s <= 0 then s = 1 end
    local want = 1 / s
    if overlay.fit ~= want then
        overlay:SetScale(want)
        labelLayer:SetScale(want)
        if cityLayer then cityLayer:SetScale(want) end
        overlay.fit = want
    end
end

-- Which frame hosts our layers. At rest, and while moving with Blizzard's
-- canvas in sync: the canvas itself (the frame that holds the map tiles and
-- every pin), so the pins - the player arrow, Blizzard's icons, Questie's -
-- always draw on top of our art, whatever order the engine renders sibling
-- frames in. Detached (moving, canvas out of sync): the container, next to
-- the canvas, whose (stale) pins are then hidden with it.
local function HostLayers(detached)
    local host = (not detached and container.Child) or container
    for _, f in ipairs({ overlay, labelLayer, cityLayer }) do
        if f:GetParent() ~= host then
            f:SetParent(host)
            f.level = nil -- (reparenting re-levels the frame: set it again)
            if ns.Perf then ns.Perf.Flip() end
        end
    end
    FitLayers()
end

-- Where the overlay sits: just above Blizzard's map art, under the pins, at
-- rest and while the canvas follows the view (live); above all pins only
-- while moving detached. While moving, an invisible frame above the pins
-- takes the mouse, so a press grabs the map (or stops a glide) instead of
-- clicking a pin sliding under the cursor.
local function SetOverlayMode(moving)
    local detached = moving and not live
    HostLayers(detached)
    local level = detached and OVERLAY_LEVEL_MOVING or restLevel
    if overlay.level ~= level then
        ns.SetLevelFixed(overlay, level)
        overlay.level = level
    end
    -- (1.0.0) the city layer: right above Blizzard's map art pins in the canvas, above the moving overlay detached.
    -- (1.0.0) Over a zone map just above its explored areas - under the quest / scenario blobs, which only zone maps
    -- draw (MapUtil.ShouldMapTypeShowQuests); this client draws no zone highlight there (no city has a zone as its
    -- parent map) - and over a continent or the world map above the zone highlight too.
    local cl
    if detached then
        cl = OVERLAY_LEVEL_MOVING + 150
    else
        local e = ns.maps[WorldMapFrame:GetMapID()]
        local wide = e and e.mapType and e.mapType <= (ns.MAPTYPE_CONTINENT or 2)
        cl = (wide and cityLevel) or cityLevelZone or cityLevel or level
    end
    if cityLayer.level ~= cl then
        ns.SetLevelFixed(cityLayer, cl)
        cityLayer.level = cl
    end
    Render:SetLevelCap(detached and (OVERLAY_LEVEL_MOVING + 280) or restStageCap)
    -- Inside the canvas (at rest, and while it follows the view) the real
    -- map's explored areas draw above our band; pictures stacked above that
    -- map's pieces go just above them (see Render). Detached: the canvas is
    -- hidden, no lift.
    Render:SetRestLift(liftLo, liftHi, (not detached) and WorldMapFrame:GetMapID() or nil)
    local labelLevel = detached and LABELS_LEVEL_MOVING or labelsRestLevel
    if labelLayer.level ~= labelLevel then
        ns.SetLevelFixed(labelLayer, labelLevel)
        labelLayer.level = labelLevel
    end
    -- (1.4.0-beta2, retail - the review of the real client, point 9: a hold that is live - Blizzard's map on the view, its
    -- pins in place, nothing sliding under the cursor - leaves the pins the mouse as at rest; on WoW Forever a hold is
    -- never live)
    local catch = moving and not (live and state == "hold")
    if catcher:IsShown() ~= catch then catcher:SetShown(catch) end

    overlayMoving = detached
    UpdateCanvasAlpha()
    -- Classic Era's map opacity slider makes the canvas translucent; then we
    -- show Blizzard's map alone at rest instead of stacking ours on it.
    translucent = container:GetAlpha() < 0.999
end

---------------------------------------------------------------------------
-- Real (Blizzard) map <-> camera
---------------------------------------------------------------------------

-- Blizzard canvas scale + normalized view centre that show camera c on map M.
-- (Scale comes from the map's width; vertical position from its own rect
-- height, which is how Blizzard places pins.)
local function RealParams(M, c)
    local ppx = ns.PixelsPerUnit(v, c.vw)
    local s = (M.x1 - M.x0) * ppx / M.lw
    local P = (c.x - M.x0) / (M.x1 - M.x0)
    local Q = (c.y - M.y0) / (M.y1 - M.y0)
    return s, P, Q
end

-- Can Blizzard's canvas for map M show camera c exactly? (zoom at least the
-- map's fit, and the view inside the map the way Blizzard clamps scrolling)
-- (1.4.0-beta2, retail) canvas: whether its canvas CAN show it - M.holdAt left out, M.holdMax kept (docs/retail-engine.md
-- 11.3, CanvasShows: InstantPanAndZoom takes any scale, the cap is ours); on WoW Forever no map has holdAt: the same
local function Holds(M, c, canvas)
    if ns.ZoomOf(v, M, c.vw) < 1 - 1e-4 then return false end
    -- (1.4.0, retail: RetailSpace.lua) the Cosmic map shows a view only up to its holdMax (the fit of the deepest map that
    -- reaches past its world's picture) - deeper, its canvas (and its pins) would grow without end over open space; a
    -- world or a map under it takes the view there (1.4.0-beta1: M.holdAt - that zoom for this view)
    if M.holdMax and ns.ZoomOf(v, M, c.vw) > ((M.holdAt and not canvas) and M.holdAt(M, c, v) or M.holdMax) then return false end
    local s, P, Q = RealParams(M, c)
    local xOff, yOff = (v.W / 2) / (s * M.lw), (v.H / 2) / (s * M.lh)
    local tx, ty = 0.5 / (s * M.lw), 0.5 / (s * M.lh) -- half a pixel
    if xOff >= 0.5 then
        if math.abs(P - 0.5) > tx then return false end
    elseif P < xOff - tx or P > 1 - xOff + tx then
        return false
    end
    if yOff >= 0.5 then
        if math.abs(Q - 0.5) > ty then return false end
    elseif Q < yOff - ty or Q > 1 - yOff + ty then
        return false
    end
    return true
end

-- Constrain camera c to what map M's canvas can show (zoom >= fit, view
-- inside the map), mirroring Blizzard's CalculateScrollExtentsAtScale.
local function ClampToMap(M, c)
    if ns.ZoomOf(v, M, c.vw) < 1 then c.vw = ns.WidthForZoom(v, M, 1) end
    if M.holdMax and ns.ZoomOf(v, M, c.vw) > M.holdMax then c.vw = ns.WidthForZoom(v, M, M.holdMax) end -- (1.4.0, retail)
    local s, P, Q = RealParams(M, c)
    local xOff = math.min((v.W / 2) / (s * M.lw), 0.5)
    local yOff = math.min((v.H / 2) / (s * M.lh), 0.5)
    P = ns.Clamp(P, xOff, 1 - xOff)
    Q = ns.Clamp(Q, yOff, 1 - yOff)
    c.x = M.x0 + P * (M.x1 - M.x0)
    c.y = M.y0 + Q * (M.y1 - M.y0)
end

local function ReadRealView()
    local M = ns.GetMap(WorldMapFrame:GetMapID())
    if not M then return nil end
    local s = container:GetCanvasScale()
    if not s or s <= 0 then return nil end
    local P = container:GetCurrentScrollX() or 0.5
    local Q = container:GetCurrentScrollY() or 0.5
    local vw = v.lw0 * v.fit0 * (M.x1 - M.x0) / (M.lw * s)
    return { x = M.x0 + P * (M.x1 - M.x0), y = M.y0 + Q * (M.y1 - M.y0), vw = vw, map = M }
end

local function SetRealView(s, P, Q)
    if fourArgPanZoom then
        -- ignoreScaleRatio = true: (P, Q) is the exact new view centre.
        container:InstantPanAndZoom(s, P, Q, true)
    else
        -- Classic Era: the pan is blended with the current one by
        -- currentScale/newScale. Step to 2x first so that factor is exactly 2,
        -- then ask for the pan that lands on P, Q.
        container:InstantPanAndZoom(s * 2, 0.5, 0.5)
        local cx = container:GetCurrentScrollX() or 0.5
        local cy = container:GetCurrentScrollY() or 0.5
        container:InstantPanAndZoom(s, 2 * cx - P, 2 * cy - Q)
    end
end

local function DiffersFromCam(r)
    local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)
    return math.abs(r.x - cam.x) * ppx > 0.5 or math.abs(r.y - cam.y) * ppy > 0.5
        or math.abs(r.vw / cam.vw - 1) > 0.001
end

-- ((1.4.0-beta15, retail: RetailBench.lua) a map switch's time, in the player's client)
local function SwitchMap(id)
    local perf = ns.Perf
    if not perf then return WorldMapFrame:SetMapID(id) end
    local p0 = debugprofilestop()
    WorldMapFrame:SetMapID(id)
    perf.Add("setMap", debugprofilestop() - p0)
    perf.Map()
end

local function SyncReal(M)
    syncing = true
    local ok, err = pcall(function()
        if WorldMapFrame:GetMapID() ~= M.id then
            SwitchMap(M.id)
        end
        SetRealView(RealParams(M, cam))
    end)
    syncing = false
    if not ok then
        geterrorhandler()(err)
        return
    end
    -- If Blizzard clamped anything, follow what it actually shows.
    local real = ReadRealView()
    if real and DiffersFromCam(real) then
        cam.x, cam.y, cam.vw = real.x, real.y, real.vw
    end
end

-- (1.1.1) May we switch Blizzard's map to map id without tainting the objective tracker? A switch we make runs the
-- map's refresh under our taint (MapCanvasMixin:OnMapChanged): QuestDataProvider puts a pin on each quest of the map
-- and styles it from the shared QuestCache (POIButtonUtil.GetStyle -> QuestCache:Get), which creates the quest's object
-- on its first Get - or fills in its quest-log fields (QuestMixin:CheckRefresh) - under whoever asked; the tracker reads
-- those objects (BuildQuestWatchInfos), and one made under our taint taints every tracker update after it (in combat
-- the scenario module's aura read is refused: "GetAuraDataByIndex(): Auras cannot be accessed when secret while
-- tainted"). So: only a map whose pins' quests are all cached already, complete and by Blizzard's own code (one it
-- showed - the map it opened, a zone clicked - or a tracked quest); one we tainted earlier adds nothing. And not while a
-- quest's details are open on another map: the quest log would close them (QuestMapFrame_CloseQuestDetails) under our
-- taint, and the tracker reads the focused quest. The current map may always stay. Without the quest APIs: true.
-- (The quest part is kept for a second per map: the live map asks every moving frame.)
local questSafeAt, questSafeOK = {}, {}
local function QuestSafe(id)
    if id == WorldMapFrame:GetMapID() then return true end
    local d = QuestMapFrame and QuestMapFrame.DetailsFrame
    if d and d.questMapID and d.questMapID ~= id then return false end
    local now = GetTime()
    if questSafeAt[id] and now - questSafeAt[id] < 1 then return questSafeOK[id] end
    questSafeAt[id], questSafeOK[id] = now, false
    local cache = QuestCache and QuestCache.objects
    local QL = C_QuestLog
    if type(cache) ~= "table" or not (QL and QL.GetQuestsOnMap and C_Map and C_Map.GetMapInfo) then
        questSafeOK[id] = true
        return true
    end
    local function Cached(q)
        local o = cache[q]
        if type(o) ~= "table" then return false end
        if issecurevariable and not issecurevariable(o, "questID") then return true end -- (tainted already)
        return o.hasQuestLogInfo == true or not (QL.GetLogIndexForQuestID and QL.GetLogIndexForQuestID(q))
    end
    local info = C_Map.GetMapInfo(id)
    if info and MapUtil and MapUtil.ShouldMapTypeShowQuests and MapUtil.ShouldMapTypeShowQuests(info.mapType) then
        local ok, quests = pcall(QL.GetQuestsOnMap, id)
        for _, q in ipairs(ok and type(quests) == "table" and quests or {}) do
            local qid = q.questID
            if qid and not q.isMapIndicatorQuest and (not HaveQuestData or HaveQuestData(qid)) and not Cached(qid) then
                return false
            end
        end
    end
    -- (the waypoint pin: the super-tracked quest's next waypoint on this map, continents too)
    local sq = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
    if sq and sq ~= 0 and QL.GetNextWaypointForMap and QL.GetNextWaypointForMap(sq, id) and not Cached(sq) then
        return false
    end
    -- (1.4.0, retail: RetailSpace.lua) the map's task quests too - world quests and bonus objectives style their pins
    -- from the same cache (POIButtonMixin:GetQuestClassification -> QuestCache:Get)
    if ns.QuestSafeExtra and not ns.QuestSafeExtra(id, Cached) then return false end
    questSafeOK[id] = true
    return true
end

-- Which real map to line up with the camera: the most detailed one that can
-- show exactly this view (so nothing moves), preferring the zone you're over.
-- (1.1.1) ok(mapID): only the maps it returns true for (QuestSafe).
local function ChooseHandover(c, ok)
    local focus, contFocus = Render:GetFocus(), Render:GetContinentFocus()
    local realID = WorldMapFrame:GetMapID()
    local best, bestScore
    for _, e in ipairs(ns.drawList) do
        if Holds(e, c) and (not ok or ok(e.id)) then
            -- (1.4.0, retail: e.hscore, RetailSpace.lua - by the depth in the placement tree, an inset over the zones
            -- beside it; the integer terms come first, so on WoW Forever the sum is the same to the bit)
            local score = (e.hscore or ((e.mapType == ns.MAPTYPE_ZONE) and 100000 or 0))
                + ((e.id == focus or e.id == contFocus) and 10000 or 0)
                + e.nest * 1000
                + ((e.id == realID) and 100 or 0)
                + e.order * 0.001
            if not bestScore or score > bestScore then best, bestScore = e, score end
        end
    end
    if best then return best end
    local world = ns.maps[ns.ROOT_MAP_ID] -- (1.4.0: the top map - on retail the Cosmic map)
    if world and Holds(world, c) and (not ok or ok(world.id)) then return world end
end

---------------------------------------------------------------------------
-- Live motion: Blizzard's canvas follows the camera while the map moves
---------------------------------------------------------------------------

-- Which real map follows the camera: the current one while it can show
-- exactly this view - a better one (the map the settle would pick) takes
-- over once it has been preferred for LIVE_SWITCH_DELAY, so a border never
-- flips maps back and forth - else the best one at once. Never another map
-- in combat (see BeginSettle), and during a flight to a map someone asked
-- for (a click, Questie, the quest log) only that map.
-- (1.0.0) The view the motion is heading to. A glide: where it comes to rest (it slows down by MOMENTUM_DECAY, so it
-- still travels vel / MOMENTUM_DECAY). A drag: where it would be DRAG_AHEAD seconds on at its present speed (a still
-- or slow drag: the view itself). A wheel zoom: its target zoom about its anchor, kept on the city the way the zoom
-- will be (Confine). nil: no such view (a flight, at rest).
local DRAG_AHEAD = 0.5
local liveProbe = {}
local function PanAhead()
    if state ~= "free" or (vel.x == 0 and vel.y == 0) then return nil end
    local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)
    local t = drag.active and DRAG_AHEAD or 1 / MOMENTUM_DECAY
    liveProbe.x, liveProbe.y, liveProbe.vw = cam.x - vel.x * t / ppx, cam.y - vel.y * t / ppy, cam.vw
    return liveProbe
end
-- Is M a capital that draws its own patch (WoW Forever, cells on)? Only there do the rules below differ from the old per-zone rule.
local function CityMap(M)
    return M ~= nil and Render.HasCityPatch ~= nil and Render:HasCityPatch(M.id) == true
end
-- The city whose own map can show view c (the view lies inside it), if any.
local function CityHolding(c)
    for _, id in ipairs(ns.CAPITALS) do
        local M = ns.maps[id]
        if M and CityMap(M) and Holds(M, c) then return M end
    end
end
local function LiveProbe()
    if state == "free" and anchor and not drag.active and math.abs(targetVw / cam.vw - 1) > 1e-4 then
        local ppx, ppy = ns.PixelsPerUnit(v, targetVw)
        liveProbe.vw = targetVw
        liveProbe.x, liveProbe.y = Confine(liveProbe, anchor.wx - (anchor.sx - v.W / 2) / ppx, anchor.wy - (anchor.sy - v.H / 2) / ppy)
        return liveProbe
    end
    return PanAhead()
end

local function LiveMap(now)
    local real = ns.GetMap(WorldMapFrame:GetMapID())
    local cur = real
    if cur and not Holds(cur, cam) then cur = nil end
    -- (1.4.0-beta2, retail: docs/retail-engine.md 11.3 (4)) out of combat, where no map we may switch to can show the view,
    -- the current map stays live while its canvas can show it (Holds' canvas: the Cosmic map past a world's fit, under
    -- our pictures) - in game at 1.11x over Draenor QuestSafe kept Blizzard's map on the Cosmic map and its canvas was
    -- hidden under pictures that did not draw. On WoW Forever Holds(real, cam, true) is Holds(real, cam): nil, as before.
    local keep = (real and not cur and not InCombatLockdown() and Holds(real, cam, true)) and real or nil
    -- (1.3.0: nor on the add-on's own flights to a view it picked, StartAimed - their landing switches once, BeginSettle.
    -- Live, a bubble's flight from Elwynn Forest to Durotar went over the world's and Kalimdor's maps: three SetMapID,
    -- each reloading every pin in mid-flight, where the jump before it made one.)
    if (fly and (fly.external or fly.aimed)) or InCombatLockdown() then
        livePrefID = nil
        return cur or keep
    end
    -- ((1.4.0-beta15, retail) Blizzard's map switches where the motion ends, once - BeginSettle -, never on the way, every motion as a flight: a switch runs every one
    -- of its 40-odd data providers over the map and acquires all its pins, in one frame, in the middle of a zoom - on a wheel from space to a zone four of them. Its
    -- canvas follows while the map it is on can show the view; past that our layers go on alone, its pins back at the rest. /emap test livemap: as 1.4.0-beta14)
    if ns.SpaceFocus and not (ns.retailTest and ns.retailTest.livemap) then
        livePrefID = nil
        if drag.active then
            -- (once its canvas has let go in a stroke it stays off to the release: never hidden and shown again - F8, below)
            if drag.liveOff then return nil end
            if cur or keep then return cur or keep end
            drag.liveOff = true
            return nil
        end
        return cur or keep
    end
    if ns.SpaceFocus and drag.active then
        -- (1.4.0-beta3, retail - WoW Forever parity, F8: Blizzard's map changes at most once in a stroke, never back) A
        -- drag keeps Blizzard's map while it can show the view; where it cannot, it goes once - to the nearest map above it
        -- that can (a zone's continent holds the view across its zones), else the best -, and after that, where the map
        -- it went to cannot show the view either, the stroke goes on detached: our pictures alone, Blizzard's canvas and
        -- pins back at the release (the settle). 1.4.0-beta2 at Azeroth's edge, dragging and zooming: 947 -> 946 -> 947
        -- -> 946 -> 947 in 0.6 s, the canvas hidden and shown, each SetMapID reloading the pins and the detail layer.
        livePrefID = nil
        if drag.liveOff then return nil end
        if cur then return cur end
        if (drag.liveN or 0) < 1 then
            local p, guard = real and ((real.home and ns.maps[real.home]) or real.pe), 0
            while p and guard < 8 do
                if Holds(p, cam) and QuestSafe(p.id) then break end
                p, guard = (p.home and ns.maps[p.home]) or p.pe, guard + 1
            end
            p = p or ChooseHandover(cam, QuestSafe) or keep
            if p then
                if p ~= real then drag.liveN = (drag.liveN or 0) + 1 end
                return p
            end
        end
        drag.liveOff = true
        return nil
    end
    local best = ChooseHandover(cam, QuestSafe) -- (1.1.1: a map we may switch to)
    -- (1.0.0) A map the motion only passes through does not take over: every SetMapID reloads the pins.
    local probe = best and LiveProbe()
    local dest = probe and ChooseHandover(probe, QuestSafe)
    -- (the view ends inside a city: then the city has the focus there, and its map is the one - see FocusZoneAt)
    if dest and not CityMap(dest) then dest = CityHolding(probe) or dest end
    if dest and dest ~= best then
        local pan = probe.vw == cam.vw
        if not cur then
            -- The current map was left. A zoom out or a glide (where it ends is known): the map of the view the
            -- motion ends on, if it can show this one too - not one that is left again a frame or two later (Searing
            -- Gorge -> Burning Steppes -> Eastern Kingdoms in consecutive frames). A drag that leaves through a
            -- city's own map: likewise. (Not for a zoom in, nor for a drag between zones - a drag may stop anywhere:
            -- tested, both made the map change more often.)
            if (probe.vw > cam.vw * 1.0001 or CityMap(best) or (pan and not drag.active)) and Holds(dest, cam) then best = dest end
        elseif best ~= cur and (pan or CityMap(dest) or CityMap(best)) then
            -- A better map than the current one, but not the one the motion ends on: a map a glide or a fast drag
            -- only crosses (a zone's corner, a city), or the zone on the way into a city (continent -> zone ->
            -- city). The current map stays until the one the motion ends on can take over.
            best = cur
        end
    end
    if not cur or not best or best == cur then
        livePrefID = nil
        return cur or best or keep
    end
    if livePrefID ~= best.id then livePrefID, livePrefT = best.id, now end
    -- (1.0.0: and, zooming at a city, not while the wheel is still being spun - the zoom's target moves with every
    -- notch, and each map on the way would reload the pins)
    local since = livePrefT
    if lastWheel > since and anchor and CityMap(DeepestAt(anchor.wx, anchor.wy)) then since = lastWheel end
    if now - since < LIVE_SWITCH_DELAY then return cur end
    livePrefID = nil
    return best
end

local liveMap
local function LiveSyncCall()
    if WorldMapFrame:GetMapID() ~= liveMap.id then SwitchMap(liveMap.id) end
    SetRealView(RealParams(liveMap, cam))
end

-- Point Blizzard's canvas at the camera on map M (only what changed).
-- Returns true when it now shows exactly our view. Unlike the settle, a
-- clamp is never adopted: the camera is the user's while it moves.
local function LiveSync(M)
    if not M then return false end
    local s, P, Q = RealParams(M, cam)
    if WorldMapFrame:GetMapID() ~= M.id or s ~= container:GetCanvasScale()
        or P ~= container:GetCurrentScrollX() or Q ~= container:GetCurrentScrollY() then
        liveMap = M
        syncing = true
        local p0 = ns.Perf and debugprofilestop()
        local ok, err = pcall(LiveSyncCall)
        if p0 then ns.Perf.Add("sync", debugprofilestop() - p0) end
        syncing = false
        liveMap = nil
        if not ok then
            geterrorhandler()(err)
            return false
        end
    end
    liveS, liveP, liveQ = container:GetCanvasScale(), container:GetCurrentScrollX(), container:GetCurrentScrollY()
    local real = ReadRealView()
    return real ~= nil and real.map == M and not DiffersFromCam(real)
end

-- Every drawn frame while moving (and whenever motion starts): keep
-- Blizzard's canvas on the camera, exactly like its own zoom animation
-- updates it every frame, so its pins move with the map (live: our layers
-- stay inside the canvas, under the pins). Where no map can show the view
-- (or on Classic Era, whose pan needs two steps), detach instead: the canvas
-- is hidden and our layers go above it until the view settles.
local function SyncMoving()
    local now = GetTime()
    -- (1.4.0-beta2, retail: a hold out of combat is live on the current map while its canvas can show the view - LiveMap)
    live = (db.livePins ~= false and not (ns.retailTest and ns.retailTest.nolive) and fourArgPanZoom and not translucent
        and (state ~= "hold" or (ns.SpaceFocus ~= nil and not InCombatLockdown()))
        and LiveSync(LiveMap(now))) or false
    liveT = now
    if live and fly then fly.liveUsed = true end
    SetOverlayMode(true)
end

---------------------------------------------------------------------------
-- Focus: which continent / zone is drawn on top where their maps overlap
---------------------------------------------------------------------------
local function WalkUpTo(id, wantType)
    local guard = 0
    while id and id ~= 0 and guard < 8 do
        local m = ns.maps[id]
        if m and m.mapType == wantType then return id end
        local mi = C_Map.GetMapInfo(id)
        id = mi and mi.parentMapID
        guard = guard + 1
    end
end

local function ContinentAt(x, y)
    local ok, info = pcall(C_Map.GetMapInfoAtPosition, ns.WORLD_MAP_ID, x, y)
    if ok and info then
        local id = WalkUpTo(info.mapID, ns.MAPTYPE_CONTINENT)
        if id then return id end
    end
    -- Ocean: keep the current one if we're still over it.
    local cur = ns.maps[Render:GetContinentFocus()]
    if cur and ns.RectContains(cur, x, y) then return cur.id end
    local best, bestD
    for _, e in ipairs(ns.drawList) do
        if e.mapType == ns.MAPTYPE_CONTINENT and ns.RectContains(e, x, y) then
            local d = (e.cx - x) ^ 2 + (e.cy - y) ^ 2
            if not bestD or d < bestD then best, bestD = e, d end
        end
    end
    return best and best.id
end

local function ZoneAt(x, y, contID)
    local cont = ns.maps[contID]
    if cont and ns.RectContains(cont, x, y) then
        local ok, info = pcall(C_Map.GetMapInfoAtPosition, cont.id,
            (x - cont.x0) / (cont.x1 - cont.x0), (y - cont.y0) / (cont.y1 - cont.y0))
        if ok and info and info.mapID ~= cont.id then
            local id = WalkUpTo(info.mapID, ns.MAPTYPE_ZONE)
            if id then return id end
        end
    end
    local best
    for _, e in ipairs(ns.drawList) do
        if e.mapType == ns.MAPTYPE_ZONE and ns.RectContains(e, x, y) and (not best or e.area < best.area) then
            best = e
        end
    end
    return best and best.id
end

-- Focus only changes when the view centre actually crosses into another
-- continent/zone, so overlapping zone art never swaps without a reason.
local lastZoneAt, lastContAt
-- A capital city only becomes the focus once it's zoomed in enough for its
-- own map to show; before that, the zone around it is (so its map art
-- doesn't vanish when you pan over the city).
local capitalSet
local function IsCapital(id)
    if not capitalSet then
        capitalSet = {}
        for _, c in ipairs(ns.CAPITALS) do capitalSet[c] = true end
    end
    return capitalSet[id] == true
end
-- A capital's own zone: the one holding most of the city's map rect
-- (Ironforge -> Dun Morogh, Thunder Bluff -> Mulgore, Undercity -> Tirisfal).
-- The smallest zone rect around a point is often a neighbour's: the Wetlands'
-- rect reaches over Ironforge, Desolace's over Thunder Bluff, Silverpine's
-- over Undercity - their whole map would be drawn over the city's zone.
local capitalHome = {}
local function HomeZone(m)
    local h = capitalHome[m.id]
    if h == nil then
        local best, bestShare
        for _, e in ipairs(ns.drawList) do
            if e.mapType == ns.MAPTYPE_ZONE and not IsCapital(e.id) then
                local w = math.min(m.x1, e.x1) - math.max(m.x0, e.x0)
                local hh = math.min(m.y1, e.y1) - math.max(m.y0, e.y0)
                local share = (w > 0 and hh > 0) and w * hh / m.area or 0
                if share > 0 and (not best or share > bestShare + 1e-6
                    or (share > bestShare - 1e-6 and e.area < best.area)) then
                    best, bestShare = e, share
                end
            end
        end
        h = best or false
        capitalHome[m.id] = h
    end
    return h or nil
end
-- (1.0.0) Does the view of camera c lie inside map m (it may poke tol px out)?
local function ViewInside(m, c, tol)
    local ppx, ppy = ns.PixelsPerUnit(v, c.vw)
    return (c.x - m.x0) * ppx >= v.W / 2 - tol and (m.x1 - c.x) * ppx >= v.W / 2 - tol
        and (c.y - m.y0) * ppy >= v.H / 2 - tol and (m.y1 - c.y) * ppy >= v.H / 2 - tol
end
local function FocusZoneAt(x, y, contID)
    local id = ZoneAt(x, y, contID)
    local m = id and ns.maps[id]
    -- (switch in once the city's own map shows, out a bit lower: no flicker)
    local need = (Render:GetFocus() == id) and 0.9 or 0.97
    local cap = m and IsCapital(id)
    local out = cap and ns.ZoomOf(v, m, cam.vw) < need
    local patch = cap and Render.HasCityPatch and Render:HasCityPatch(id)
    if patch then
        -- (1.0.0) Where the city draws a patch (WoW Forever, cells on) it needs no focus to show: the city has the focus
        -- only while the VIEW lies inside its map (kept until it pokes 6 px out) - then its own picture is Blizzard's
        -- city map exactly. Anywhere else its home zone has it, so no half-faded city rectangle shows at a city's edge
        -- and the home zone's picture does not come and go there.
        -- A fling or a fast drag that only crosses the city (the view it would come to rest on is not inside it) leaves
        -- the focus alone.
        out = not ViewInside(m, cam, (Render:GetFocus() == id) and 6 or 0.5)
        if not out and Render:GetFocus() ~= id then
            local p = PanAhead()
            if p and not ViewInside(m, p, 0.5) then out = true end
        end
    end
    if out then
        local home = HomeZone(m)
        if home and (patch or ns.RectContains(home, x, y)) then return home.id end
        local best
        for _, e in ipairs(ns.drawList) do
            if e.mapType == ns.MAPTYPE_ZONE and not IsCapital(e.id) and ns.RectContains(e, x, y)
                and (not best or e.area < best.area) then
                best = e
            end
        end
        if best then return best.id end
    end
    return id
end

-- Depth confinement. A capital's map is far more detailed than its zone's
-- (Ironforge ~6x Dun Morogh, Stormwind 2x Elwynn), so the wheel goes deeper
-- over the city (DeepestAt) - but past the zone's own depth limit (maxZoom
-- past the zone's fit) the land around the city only exists as the zone's
-- picture blown up 10-25x. Once you zoom past that limit over a city (or rest
-- on the city's own map that deep), the view is kept on the city, the way
-- Blizzard keeps a map's view inside the map (CalculateScrollExtentsAtScale):
-- over the next DEPTH_RAMP of zoom the share of the view allowed past the
-- city's edge shrinks from a whole view (the view need only touch the city)
-- to none, so zooming in draws the city into the view as part of the zoom
-- (CityZoom), dragging or a fling stops at its edge, and resting on the city
-- needs no correction. Zooming out only ever widens the allowed area, and
-- back at the zone's limit the city lets go.
local DEPTH_RAMP = 1.69 -- (two wheel notches at the default step)
local depthCity         -- the capital the view is kept on, or nil

-- View width at the depth limit of a capital's own zone (nil: none known).
local function CityLimit(C)
    local home = HomeZone(C)
    return home and ns.WidthForZoom(v, home, db.maxZoom)
end

-- The zone's limit and the width from which the view is wholly on the city:
-- DEPTH_RAMP deeper - or the city's fit, when that comes first (then it
-- can't be dragged, like Blizzard's own city map at fit).
local function CityRamp(C)
    local lim = CityLimit(C)
    if not lim then return nil end
    local done = lim / DEPTH_RAMP
    local fit = ns.WidthForZoom(v, C, 1)
    if fit < lim and fit > done then done = fit end
    return lim, done
end

-- Share of the view that may lie past the city's edge at width vw: nil (no
-- limit) until the zone's limit, then from 1 down to 0 over the ramp.
local function CityMargin(C, vw)
    local lim, done = CityRamp(C)
    if not lim or vw >= lim then return nil end
    return 1 - ns.Smooth(math.log(lim / vw) / math.log(lim / done))
end

-- Allowed view centre on one axis in the city's normalized coordinates, for
-- a half view h and margin m: centred when it doesn't fit (as Blizzard's).
local function Span(p, h, m)
    local lo, hi = h - m, 1 - h + m
    if lo > hi then return 0.5 end
    return ns.Clamp(p, lo, hi)
end

-- Centre (x, y) moved to where camera c's view keeps to the city.
Confine = function(c, x, y)
    local C = depthCity
    local g = C and CityMargin(C, c.vw)
    if not g then return x, y end
    local s = (C.x1 - C.x0) * ns.PixelsPerUnit(v, c.vw) / C.lw -- (as RealParams)
    local xOff, yOff = (v.W / 2) / (s * C.lw), (v.H / 2) / (s * C.lh)
    local P = Span((x - C.x0) / (C.x1 - C.x0), xOff, 2 * xOff * g)
    local Q = Span((y - C.y0) / (C.y1 - C.y0), yOff, 2 * yOff * g)
    return C.x0 + P * (C.x1 - C.x0), C.y0 + Q * (C.y1 - C.y0)
end

-- While the view is kept on a city, the wheel zoom heads for the view it may
-- end on: the one it would reach anchored at the cursor, moved onto the city
-- (as Blizzard clamps its own wheel zoom's pan target to the scroll extents
-- at the next scale, MapCanvas_ScrollContainerMixin.lua:198) - first the one
-- at the end of the ramp, where the view has to be wholly on the city, so the
-- pull is spread over all the zoom up to there. The view zooms about the one
-- point that lands it there - and at every step it is kept on the city at
-- that step's own zoom - so the city is drawn in by the zoom itself, never
-- behind it. Where that would slide the point under the cursor more than
-- MAX_GLIDE_PX in a frame (the cap of every clamp's glide), the zoom step is
-- shortened instead: the zoom waits for the pull.
-- The view it heads for puts the spot the wheel was first pointed at (the
-- aim, anchor.ax/ay: kept while the cursor stays still and the zoom goes in)
-- under the cursor - as close as the city allows - not the spot the pull has
-- slid there: so the zoom ends where you pointed. (anchor.wx/wy, the point
-- under the cursor now, is what each frame's slide is measured from.) A step
-- stops at the ramp's end, where the view is wholly on the city (for most
-- capitals the city's fit), and heads on from there: no lurch in the zoom's
-- speed between the pull and what follows.
-- (x0, y0, w0): last frame's camera, cam.vw: this frame's zoom step (may be
-- shortened). Returns the new centre, or nil when the plain anchor is fine
-- (or the view isn't on the city yet: then the usual glide brings it).
local cityProbe = {}
-- Centre at width w on the way (kept on the city at w), and how far that
-- slides the point under the cursor (px) beyond the cap (<= 0: fine).
local function CityPath(x0, y0, w0, fx, fy, w)
    local f = w / w0
    cityProbe.vw = w
    local x, y = Confine(cityProbe, fx + (x0 - fx) * f, fy + (y0 - fy) * f)
    local px, py = ns.PixelsPerUnit(v, w)
    local ax = anchor.wx - (anchor.sx - v.W / 2) / px
    local ay = anchor.wy - (anchor.sy - v.H / 2) / py
    local slide = math.sqrt(((x - ax) * px) ^ 2 + ((y - ay) * py) ^ 2)
    return x, y, slide - MAX_GLIDE_PX, slide
end
local function CityZoom(x0, y0, w0)
    local ww = targetVw
    local _, done = CityRamp(depthCity)
    if done and w0 > done * 1.0001 and targetVw < done then
        ww = done
        if cam.vw < done then cam.vw = done end
    end
    local k = ww / w0
    if math.abs(1 - k) < 1e-6 then return nil end
    cityProbe.vw = ww
    local pxT, pyT = ns.PixelsPerUnit(v, ww)
    local tx, ty = Confine(cityProbe, anchor.ax - (anchor.sx - v.W / 2) / pxT, anchor.ay - (anchor.sy - v.H / 2) / pyT)
    local fx, fy = (tx - k * x0) / (1 - k), (ty - k * y0) / (1 - k)
    if select(4, CityPath(x0, y0, w0, fx, fy, w0)) > 0.5 then return nil end
    local w1 = cam.vw
    local x, y, over, s = CityPath(x0, y0, w0, fx, fy, w1)
    if s < 0.05 then return nil end
    if over > 0 then
        -- the longest step (in log width) whose slide stays within the cap
        local l0, l1, lo, hi = math.log(w0), math.log(w1), 0, 1
        for _ = 1, 12 do
            local m = (lo + hi) / 2
            if select(3, CityPath(x0, y0, w0, fx, fy, math.exp(l0 + (l1 - l0) * m))) > 0 then hi = m else lo = m end
        end
        w1 = math.exp(l0 + (l1 - l0) * lo)
        x, y = CityPath(x0, y0, w0, fx, fy, w1)
    end
    cam.vw = w1
    return x, y
end

-- A wheel notch in that heads past a capital's zone limit with the cursor or
-- the view centre on the city (the points the depth limit comes from).
local function EngageCity(points, newT)
    for i = 1, #points, 2 do
        local M = DeepestAt(points[i], points[i + 1])
        if M and IsCapital(M.id) then
            local lim = CityLimit(M)
            if lim and newT < lim then depthCity = M end
        end
    end
end

-- Back at (or out past) the zone's limit, with no zoom heading deeper.
local function ReleaseCity()
    if not depthCity then return end
    local lim = CityLimit(depthCity)
    if not lim or (cam.vw >= lim and targetVw >= lim) then depthCity = nil end
end

-- At rest: on a capital's own map deeper than its zone's limit, the view is
-- kept on the city (Blizzard's canvas already keeps it inside); after a
-- settle anywhere else the city keeps the view only while still that deep.
local function RestCity()
    local R = ns.GetMap(WorldMapFrame:GetMapID())
    if R and IsCapital(R.id) and CityMargin(R, cam.vw) then
        depthCity = R
    elseif depthCity and not CityMargin(depthCity, cam.vw) then
        depthCity = nil
    end
end

-- The point that decides the focus (and where zone art is built ahead of
-- time): the view centre - or, while the wheel is still zooming IN, the
-- centre that zoom will end on. The point under the cursor stays put, so this
-- is a blend of the view centre and the cursor, weighted by how much zoom is
-- still pending: a wheel burst toward a zone at the edge of the view hands
-- the map to that zone sooner (and skips zones the centre would only cross
-- on the way), while a finished zoom, a drag, a glide or a mouse that merely
-- moves leave the focus to the centre - which is what the settle hands over
-- to Blizzard's map, so the focus at rest still matches the real map.
local function ZoomDestination()
    if state == "free" and anchor and targetVw < cam.vw then
        local ppx, ppy = ns.PixelsPerUnit(v, targetVw)
        return anchor.wx - (anchor.sx - v.W / 2) / ppx, anchor.wy - (anchor.sy - v.H / 2) / ppy
    end
    return cam.x, cam.y
end

local function UpdateFocus(now, force)
    if not force and now - focusCheckT < 0.08 then return end
    focusCheckT = now
    local fx, fy = ZoomDestination()
    local contID, zoneID
    if ns.SpaceFocus then
        -- (1.4.0, retail: RetailSpace.lua) down the placement tree from the Cosmic map
        contID, zoneID = ns.SpaceFocus(fx, fy, nil, cam, v)
    else
        contID = ContinentAt(fx, fy)
        zoneID = FocusZoneAt(fx, fy, contID or Render:GetContinentFocus())
    end
    if contID ~= lastContAt then
        lastContAt = contID
        Render:SetContinentFocus(contID)
    end
    if zoneID ~= lastZoneAt then
        lastZoneAt = zoneID
        Render:SetFocus(zoneID)
    end
end

-- After a map change we didn't make, the real map (and its continent) goes
-- on top, like Blizzard's own view of it.
local function FocusRealMap()
    local M = ns.GetMap(WorldMapFrame:GetMapID())
    if ns.SpaceFocus then
        -- (1.4.0, retail: RetailSpace.lua) the real map and the chain above it go on top
        local c, z = ns.SpaceFocus(cam.x, cam.y, M and M.id, cam, v)
        lastContAt, lastZoneAt = c, z
        Render:SetContinentFocus(c)
        Render:SetFocus(z)
        return
    end
    local contID = ContinentAt(cam.x, cam.y)
    lastContAt = contID
    lastZoneAt = FocusZoneAt(cam.x, cam.y, contID or Render:GetContinentFocus())
    if M and M.mapType == ns.MAPTYPE_ZONE then
        Render:SetFocus(M.id)
        Render:SetContinentFocus(WalkUpTo(M.parent, ns.MAPTYPE_CONTINENT) or contID)
    elseif M and M.mapType == ns.MAPTYPE_CONTINENT then
        Render:SetContinentFocus(M.id)
        Render:SetFocus(lastZoneAt)
    else
        Render:SetContinentFocus(contID)
        Render:SetFocus(lastZoneAt)
    end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function Moving()
    return state == "free" or state == "fly" or state == "hold"
end

-- Returns true while art is still loading / fading in.
-- ((1.4.0-beta16) or something drawn asked for another draw - Redraw from inside this one, Labels.lua's markers beyond a frame's few: the caller's restBusy = DrawFrame() and its
-- driver:Hide() threw the request away, and those markers stayed missing until the next move)
local drawing, redrawAsked = false, false
local function DrawFrame()
    local busy = false
    drawing = true
    if Moving() then SyncMoving() end
    -- Zooming in: build the zone art where the zoom is heading ahead of time. (1.4.0-beta2, retail: RetailRender.lua's
    -- PREFETCH_OUT - zooming out too, the drawn pictures' windows grown to the view it heads for; nil on WoW Forever)
    if state == "free" and (targetVw < cam.vw or (Render.PREFETCH_OUT and targetVw > cam.vw * 1.0001)) then
        local tx, ty = ZoomDestination()
        Render:SetPrefetch(tx, ty, targetVw)
    elseif state == "fly" and fly and Render.PREFETCH_FLIGHTS then
        -- (1.4.0, retail: RetailRender.lua) a flight loads ahead the pictures of the view it lands on
        Render:SetPrefetch(fly.target.x, fly.target.y, fly.target.vw)
    elseif state == "free" and Render.PREFETCH_PAN and PanAhead() then
        -- (1.4.0-beta2, retail: RetailRender.lua) a drag or a glide loads ahead the view it heads for
        local p = PanAhead()
        Render:SetPrefetch(p.x, p.y, p.vw)
    else
        Render:SetPrefetch(nil)
    end
    if overlay:IsShown() then busy = Render:Draw(cam, v) end
    UpdateCanvasAlpha()
    if db.labels and state ~= "off" and (Moving() or db.labelsAtRest) then
        labelLayer:Show()
        local p0 = ns.Perf and debugprofilestop()
        Labels:Draw(cam, v)
        if p0 then ns.Perf.Add("labels", debugprofilestop() - p0) end
    else
        Labels:HideAll()
    end
    drawing = false
    if redrawAsked then
        redrawAsked = false
        busy = true
    end
    return busy
end

local function GoOff()
    state = "off"
    fly, anchor, restAim = nil, nil, nil
    drag.pending, drag.active = false, false
    vel.x, vel.y = 0, 0
    realDirty, restBusy = false, false
    live, livePrefID = false, nil
    depthCity = nil
    if ns.Follow then ns.Follow:Stop() end -- (1.1.0: the map closed)
    if overlay then
        if container.Child and container.Child:GetAlpha() < 1 then container.Child:SetAlpha(1) end
        HostLayers(true)
        catcher:Hide()
        overlay:Hide()
        cityLayer:Hide() -- (1.0.0: the overlay's OnHide does not fire while the map is closed)
        Render:HideAll()
        Labels:HideAll()
        driver:Hide()
        SetBlizzardWheel(false)
    end
end

-- keepFocus: after our own settle, keep the art layering exactly as it was
-- while moving (the camera didn't move, so nothing should change).
local function EnterRest(keepFocus)
    Render:SetFadeTime(nil)
    state = "rest"
    restAim = anchor
    fly, anchor = nil, nil
    live, livePrefID = false, nil
    targetVw = cam.vw
    RestCity()
    SetBlizzardWheel(true)
    SetOverlayMode(false)
    if not keepFocus then FocusRealMap() end
    -- With a translucent (opacity-slider) canvas, show Blizzard's map alone.
    overlay:SetShown(not translucent)
    -- (hidden: nothing draws at rest, so drop half-done picture/ring fades;
    -- the next motion then starts from the settled look, like Blizzard's map)
    if translucent then Render:HideAll() end
    restBusy = DrawFrame()
    local following = ns.Follow and ns.Follow:Active() -- (1.3.0: FollowStep runs on every frame at rest)
    if restBusy then driver:Show() elseif not drag.pending and not realDirty and not following then driver:Hide() end
end

-- Adopt whatever Blizzard's map currently shows, then rest.
local function ResyncFromReal()
    if not ready or not WorldMapFrame:IsShown() then return end
    if not db.enabled or not UpdateView() then
        GoOff()
        return
    end
    local real = ReadRealView()
    if real then
        cam.x, cam.y, cam.vw = real.x, real.y, real.vw
        EnterRest()
    else
        GoOff()
    end
end

-- (1.1.0, Follow.lua: the M key) Show world point (x, y) at world zoom z at once: on the most detailed map that can show
-- that view - in combat on the map the game opened, the view kept inside it. (1.3.0: at once only where nothing was
-- shown yet - M opens the map; a view already shown flies there, FlyToZoom.)
local function JumpToZoom(x, y, z)
    if not ready or not db.enabled or not WorldMapFrame:IsShown() or not UpdateView() then return false end
    local world = ns.maps[ns.WORLD_MAP_ID]
    if not world then return false end
    cam.x, cam.y, cam.vw = x, y, ns.WidthForZoom(v, world, z)
    local M = (not InCombatLockdown() and ChooseHandover(cam, QuestSafe)) or ns.GetMap(WorldMapFrame:GetMapID())
    if not M then return false end
    if not Holds(M, cam) then ClampToMap(M, cam) end
    fly, anchor, restAim = nil, nil, nil
    vel.x, vel.y = 0, 0
    SyncReal(M)
    EnterRest()
    return true
end

---------------------------------------------------------------------------
-- Modes
---------------------------------------------------------------------------
local function EnterFree()
    if state == "rest" or state == "off" then
        local real = ReadRealView()
        if real then cam.x, cam.y, cam.vw = real.x, real.y, real.vw end
        -- Blizzard moved its map past the city's edge at rest (a gamepad,
        -- another addon - more than a press before a drag starts): that view
        -- stays, and the city lets go instead of pulling it back.
        if depthCity then
            local x, y = Confine(cam, cam.x, cam.y)
            local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)
            if math.abs(x - cam.x) * ppx + math.abs(y - cam.y) * ppy > dragThreshold + 2 then depthCity = nil end
        end
    end
    if state ~= "free" then
        targetVw = cam.vw
        lastHolderID, gliding = nil, false
    end
    fly = nil
    Render:SetFadeTime(nil)
    state = "free"
    SyncMoving()
    overlay:Show()
    UpdateFocus(GetTime(), true) -- only re-ranks if the centre crossed a border
    DrawFrame()
    driver:Show()
end

-- A zoom out whose start view lies inside the target view: a zoom about the
-- one point that keeps its place on screen, so every view on the way is
-- nested between the two. (The general path lets the pan lag the zoom, so
-- its views can stick out of the target map; nested ones never do, and the
-- map that was asked for - and its pins - can follow the whole flight.)
-- Views in uniform units (x * lw0, y * lh0, width); nil if not nested.
local function NestedPath(x0, y0, w0, x1, y1, w1, S)
    local a = v.H / v.W -- view height / width
    local eps = w1 * 1e-6
    if not (w1 > w0 * 1.000001) or math.abs(x1 - x0) + w0 / 2 > w1 / 2 + eps
        or math.abs(y1 - y0) + w0 * a / 2 > w1 * a / 2 + eps then
        return nil
    end
    local fx = (x0 * w1 - x1 * w0) / (w1 - w0)
    local fy = (y0 * w1 - y1 * w0) / (w1 - w0)
    local L = math.log(w1 / w0)
    return function(s)
        local k = math.exp(L * ns.Clamp01(S > 0 and s / S or 1))
        return fx + (x0 - fx) * k, fy + (y0 - fy) * k, w0 * k
    end
end

-- external: a flight to a map someone else switched to (see OnMapChanged). aimed (1.3.0): to a view the add-on picked
-- itself (StartAimed). Neither switches Blizzard's map on the way (LiveMap) - from the first sync on, below.
local function StartFly(target, onDone, external, aimed)
    local k = v.W / v.fit0 -- camera width in uniform units = vw * k
    local x0, y0, w0 = cam.x * v.lw0, cam.y * v.lh0, cam.vw * k
    local x1, y1, w1 = target.x * v.lw0, target.y * v.lh0, target.vw * k
    local S, path = ns.ZoomPath(x0, y0, w0, x1, y1, w1, 1.4)
    if not (S == S) or S == math.huge or S < 0 then S = 0 end -- NaN / inf guard
    if external and fourArgPanZoom and target.map and Holds(target.map, cam) then
        -- (same duration as the general path)
        path = NestedPath(x0, y0, w0, x1, y1, w1, S) or path
    end
    local dur = ns.Clamp(0.3 + S * 0.22, 0.3, 1.5)
    -- (1.4.0, retail: RetailSpace.lua) from space to a zone the zoom spans up to 1,700x: no faster than 1.25x a frame at the
    -- ease's steepest (0.35 s per unit of path, up to 2 s)
    if ns.SpaceFocus then dur = math.max(dur, math.min(S * 0.35, 2)) end
    dur = dur / ((db.flySpeed and db.flySpeed > 0) and db.flySpeed or 1)
    fly = { S = S, path = path, t = 0, dur = dur, target = target, onDone = onDone,
        external = external, lockFocus = external, aimed = aimed }
    state = "fly"
    SyncMoving()
    overlay:Show()
    DrawFrame()
    driver:Show()
end

local BeginSettle

local function EnterHold()
    state = "hold"
    SyncMoving()
    DrawFrame()
    driver:Show()
end

BeginSettle = function()
    local M = ChooseHandover(cam)
    if not M then
        -- Safety net: ClampCam keeps the camera holdable, so this only
        -- corrects float drift. Glide to the nearest view a map can show.
        local x, y = NearestHoldable(cam)
        local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)
        if math.abs(x - cam.x) * ppx + math.abs(y - cam.y) * ppy < 0.01 then
            -- (1.4.0-beta3, retail: the Cosmic map bounds the camera at every zoom - RetailSpace.lua boundsAll -, so a view
            -- dragged past a world's edge into space, deeper than any canvas can show, is where it may rest: held, our
            -- pictures over Blizzard's hidden canvas - never a snap onto Azeroth's map, which cannot show it. On WoW
            -- Forever the root is the world: as before)
            local root = ns.maps[ns.ROOT_MAP_ID]
            if root and root.boundsAll and ns.ROOT_MAP_ID ~= ns.WORLD_MAP_ID then
                EnterHold()
                return
            end
            M = ns.maps[ns.WORLD_MAP_ID] -- numerically on the edge; take the world
        else
            StartFly({ x = x, y = y, vw = cam.vw }, BeginSettle)
            return
        end
    end
    if M.id ~= WorldMapFrame:GetMapID() and not InCombatLockdown() and not QuestSafe(M.id) then
        -- (1.1.1) A switch that would cache that map's quests under our taint (QuestSafe): the best map we may switch
        -- to - the continent, the world map - else the current one, else our overlay until the next input.
        local S = ChooseHandover(cam, QuestSafe)
        local R = ns.GetMap(WorldMapFrame:GetMapID())
        if S then
            M = S
        elseif R and Holds(R, cam) then
            M = R
        else
            EnterHold()
            return
        end
    end
    if M.id ~= WorldMapFrame:GetMapID() and InCombatLockdown() then
        -- Switching maps in combat can trip Blizzard's protected pin code
        -- under our taint. Stay on the current map if it can show the view,
        -- otherwise keep our overlay up until combat ends.
        local R = ns.GetMap(WorldMapFrame:GetMapID())
        if R and Holds(R, cam) then
            M = R
        else
            EnterHold()
            return
        end
    end
    SyncReal(M)
    -- (1.4.0-beta1, retail: the reviews of 1.4.0-beta1) the focus follows the map the settle shows: moving, the focus
    -- goes by the point under the camera (RetailSpace.lua SpaceFocus) and the hand-over by the maps that can show the
    -- whole view, so at rest a zone's picture could be drawn over Blizzard's map of its neighbour (Durotar's over the
    -- Southern Barrens)
    EnterRest(not ns.SpaceFocus)
end

---------------------------------------------------------------------------
-- Per-frame driver
---------------------------------------------------------------------------
local function EndDrag()
    drag.active = false
    lastInput = GetTime()
    if vel.x * vel.x + vel.y * vel.y < 2500 then vel.x, vel.y = 0, 0 end
end

-- (1.3.0, Follow.lua) Where the unit followed is now (world units) - the point a wheel zoom is about while following -
-- and how far it moved since the camera last went with it. nil: not following, or no position this frame (the zoom
-- then goes on about where it was).
local function FollowPoint(now)
    if not (ns.Follow and ns.Follow:Active()) then return nil end
    return ns.Follow:Target(now)
end

-- (1.3.0) Flights to a view the add-on picks itself - a party bubble clicked, the unit followed two views away (the
-- user on 1.3.0-beta1's bubbles: "the snap to the player is jaring, it should be a smooth transition where we lerp zoom
-- and xy to the target, so click bubble, zoom out and in, while moving propotionally for a nice zoom arc. this should be
-- how all movment works excep for tracking a players movment"): StartFly's zoom-and-pan path from the view shown, as
-- long as StartFly makes it (db.flySpeed), landing like every motion (BeginSettle) - Blizzard's map switches only there,
-- never on the way (LiveMap: aimed, as an external flight). While following, such a flight is on its way to the one
-- followed (aimed): a wheel notch on the way sets the zoom it lands at - eased at the wheel's rate, what is left of it at
-- the landing goes on about them as a wheel zoom does - and their position is read on every frame, so after the landing
-- FollowStep eases onto where they are by then instead of adding their motion of the whole flight in one frame. A drag
-- takes over as it does from any flight (and stops following).
local function FlightFollow(f, dt, now)
    FollowPoint(now)
    local lk, lt = math.log(f.zoomK), math.log(f.zoomF)
    if math.abs(lt - lk) < 1e-4 then
        f.zoomK = f.zoomF
    else
        f.zoomK = math.exp(lk + (lt - lk) * (1 - math.exp(-dt * ZOOM_RATE)))
    end
    cam.vw = cam.vw * f.zoomK
end

local function LandFlight(f)
    cam.vw = f.target.vw * f.zoomK
    if math.abs(f.zoomF / f.zoomK - 1) < 1e-4 then
        BeginSettle()
        return
    end
    -- (a notch late in the flight: the rest of its zoom, about the one followed - else the centre - as OnMouseWheel's)
    local now = GetTime()
    EnterFree()
    local fx, fy = FollowPoint(now)
    local wx, wy = fx or cam.x, fy or cam.y
    local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)
    local sx, sy = v.W / 2 + (wx - cam.x) * ppx, v.H / 2 + (wy - cam.y) * ppy
    anchor = { wx = wx, wy = wy, sx = sx, sy = sy, ax = wx, ay = wy, asx = sx, asy = sy }
    targetVw = math.min(f.target.vw * f.zoomF, 1)
    lastInput = now
end

-- The view a flight to world point (x, y) at width vw lands on: the one JumpToZoom shows - on the most detailed map we
-- may switch to that can show it (QuestSafe), else on the current map, the view kept inside it; in combat always on the
-- current map (no map switch, BeginSettle's rule). nil: no map.
local function FlightTarget(x, y, vw)
    local t = { x = x, y = y, vw = vw }
    local combat = InCombatLockdown()
    local M = (not combat and ChooseHandover(t, QuestSafe)) or (combat and ns.GetMap(WorldMapFrame:GetMapID())) or nil
    if not M and not combat then
        -- ((1.4.0-beta12, retail: the Cosmic map bounds the camera - RetailSpace.lua boundsAll - and a held view answers the
        -- mouse) no map we may switch to can show the view: the view itself, held at the landing - never pressed into
        -- Blizzard's map of the moment. The player's 1.4.0-beta11 session, every map refused: Blizzard's map the Cosmic
        -- map, a click on your bubble "only zooms out and centers, never zooms back in" (the landing pressed into the
        -- Cosmic map's own depth); a click's flight to Redridge landed on Elwynn Forest's edge. Not into the Cosmic map
        -- either - its canvas shows no view that deep (holdMax). On WoW Forever, as before: on the current map, the view
        -- kept inside it.)
        local root = ns.maps[ns.ROOT_MAP_ID]
        if root and root.boundsAll and ns.ROOT_MAP_ID ~= ns.WORLD_MAP_ID then return t end
        M = ns.GetMap(WorldMapFrame:GetMapID())
    end
    if not M then return nil end
    if not Holds(M, t) then ClampToMap(M, t) end
    return t
end

local function StartAimed(t)
    vel.x, vel.y, anchor, restAim = 0, 0, nil, nil
    depthCity = nil -- (the landing decides again, see RestCity)
    drag.fromRest = false -- (a press held from rest: a drag grabs what is under it when it starts, see OnUpdate)
    Render:SetFadeTime(nil) -- (an external flight's crossfade cut off)
    StartFly(t, LandFlight, nil, true)
    fly.zoomF, fly.zoomK = 1, 1
end

-- (PartyBubbles.lua) Go to world point (x, y) at world zoom z: a flight from the view shown. With nothing shown yet (the
-- map just opened) or the camera off: at once (JumpToZoom). false: nothing to show it on.
local function FlyToZoom(x, y, z)
    if not ready or not db.enabled or not WorldMapFrame:IsShown() or not UpdateView() then return false end
    if state == "off" or justShown then return JumpToZoom(x, y, z) end
    local world = ns.maps[ns.WORLD_MAP_ID]
    local t = world and FlightTarget(x, y, ns.WidthForZoom(v, world, z))
    if not t then return false end
    if state == "rest" then
        local real = ReadRealView()
        if real then cam.x, cam.y, cam.vw = real.x, real.y, real.vw end
    end
    local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)
    if math.abs(t.x - cam.x) * ppx + math.abs(t.y - cam.y) * ppy < 0.5 and math.abs(t.vw / cam.vw - 1) < 1e-3 then
        return JumpToZoom(x, y, z) -- (there already: nothing to fly)
    end
    StartAimed(t)
    return true
end

-- (1.3.0) The unit followed is two views away - a portal, a hearthstone, the end of a long flight: a flight to the view
-- the jump there ended on up to 1.3.0-beta1 (on the unit; at rest kept inside the map FollowStep shows it on: the
-- current one, else - out of combat - one we may switch to, else the current one, the view clamped into it), when that
-- lies more than a tenth of the view's diagonal away. (Held off the unit by a map's edge - in combat - the view slides
-- along the edge with the unit's motion as before: a pixel or two a frame.) held: no map keeps the view inside it -
-- FollowHeld's (over our overlay), a wheel zoom's (UpdateFree: ClampCam's bounds only). true: a flight started.
local function FollowFar(tx, ty, held)
    -- (1.4.0, retail: RetailParty.lua VwLike - nil on WoW Forever) as wide in yards as the view now: through a portal to
    -- another world one width of the camera is another width in yards
    local yv = ns.VwLike and ns.VwLike(tx, ty, cam.vw)
    local t = { x = tx, y = ty, vw = yv or cam.vw }
    local cur = ns.GetMap(WorldMapFrame:GetMapID())
    if yv and not held and not ((cur and Holds(cur, t)) or (not InCombatLockdown() and ChooseHandover(t, QuestSafe))) then
        t.vw = cam.vw -- (1.4.0: no map we may show can show that width there: the view's own, as before)
    end
    if not held and not ((cur and Holds(cur, t)) or (not InCombatLockdown() and ChooseHandover(t, QuestSafe))) then
        if not cur then return false end
        t.vw = cam.vw -- (1.4.0: kept inside the map shown - in combat - the view keeps its width, as before)
        ClampToMap(cur, t)
    end
    local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)
    if ((t.x - cam.x) * ppx) ^ 2 + ((t.y - cam.y) * ppy) ^ 2 <= (v.W * v.W + v.H * v.H) / 100 then return false end
    StartAimed(t)
    return true
end

-- (1.3.0) Following through a wheel zoom, the unit two views away at once (a portal, a hearthstone in mid-zoom): a flight
-- there too (FollowFar) - the zoom about it moved the view with it in one frame, 0.8 of a view's width - landing at the
-- zoom the wheel was heading for, no deeper than the wheel may go there (OnMouseWheel's depth limit). true: it flies.
local function FollowFarFree(fx, fy)
    local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)
    local ex, ey = (fx - cam.x) * ppx, (fy - cam.y) * ppy
    if ex * ex + ey * ey <= 4 * (v.W * v.W + v.H * v.H) then return false end
    local w = math.min(targetVw, 1)
    if w < cam.vw then
        local D = DeepestAt(fx, fy)
        w = math.max(w, math.min(ns.WidthForZoom(v, D, D.maxZoom or db.maxZoom), cam.vw)) -- (1.4.0: D.maxZoom, retail)
    end
    local vw0 = cam.vw
    if not FollowFar(fx, fy, true) then return false end
    if ns.VwLike then
        -- (1.4.0, retail: RetailParty.lua) the wheel's zoom on a landing as wide in yards as the view (FollowFar), no
        -- deeper than the wheel may go there
        local L = math.min(fly.target.vw * w / vw0, 1)
        if L < fly.target.vw then
            local D = DeepestAt(fx, fy)
            L = math.max(L, math.min(ns.WidthForZoom(v, D, D.maxZoom or db.maxZoom), fly.target.vw))
        end
        fly.zoomF = L / fly.target.vw
        return true
    end
    fly.zoomF = w / fly.target.vw
    return true
end

local function UpdateFree(dt, now)
    local prevX, prevY, prevVw = cam.x, cam.y, cam.vw -- what was on screen last frame
    -- (1.3.0) Following through a wheel zoom (the user on 1.2.0: "zooming breaks tracking"): the zoom is about the unit
    -- where it is THIS frame, its screen point easing onto the centre as the rest's follow does (it starts there unless
    -- the view was still catching up, or held off it); no city pulls the view off it.
    local fx, fy
    if anchor and not drag.active then fx, fy = FollowPoint(now) end
    if fx and FollowFarFree(fx, fy) then return end -- (two views away: a flight)
    if fx then
        depthCity = nil
        local hw, hh = v.W / 2, v.H / 2
        local k = 1 - math.exp(-dt * FOLLOW_RATE)
        local ax, ay = anchor.sx + (hw - anchor.sx) * k, anchor.sy + (hh - anchor.sy) * k
        if (ax - hw) ^ 2 + (ay - hh) ^ 2 < 0.01 then ax, ay = hw, hh end
        anchor.wx, anchor.wy, anchor.sx, anchor.sy = fx, fy, ax, ay
        anchor.ax, anchor.ay, anchor.asx, anchor.asy = fx, fy, ax, ay
    end
    if targetVw > 1 then targetVw = 1 end
    local lv, lt = math.log(cam.vw), math.log(targetVw)
    if math.abs(lt - lv) < 1e-4 then
        cam.vw = targetVw
    else
        cam.vw = math.exp(lv + (lt - lv) * (1 - math.exp(-dt * ZOOM_RATE)))
    end
    -- (kept on a city: the wheel zoom heads onto it, see CityZoom)
    local cx, cy
    if depthCity and anchor and not drag.active and cam.vw ~= prevVw then cx, cy = CityZoom(prevX, prevY, prevVw) end
    local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)

    if drag.active then
        if not IsMouseButtonDown("LeftButton") then
            EndDrag()
        else
            local sx, sy = CursorPos()
            cam.x = drag.wx - (sx - v.W / 2) / ppx
            cam.y = drag.wy - (sy - v.H / 2) / ppy
            if dt > 0 then
                vel.x = vel.x * 0.6 + (sx - drag.lastSx) / dt * 0.4
                vel.y = vel.y * 0.6 + (sy - drag.lastSy) / dt * 0.4
            end
            drag.lastSx, drag.lastSy = sx, sy
            lastInput = now
        end
    elseif cx then
        cam.x, cam.y = cx, cy
    elseif anchor then
        cam.x = anchor.wx - (anchor.sx - v.W / 2) / ppx
        cam.y = anchor.wy - (anchor.sy - v.H / 2) / ppy
    end

    local moved = false
    if not drag.active and (vel.x ~= 0 or vel.y ~= 0) then
        moved = true
        anchor = nil
        cam.x = cam.x - vel.x * dt / ppx
        cam.y = cam.y - vel.y * dt / ppy
        local decay = math.exp(-dt * MOMENTUM_DECAY)
        vel.x, vel.y = vel.x * decay, vel.y * decay
        if vel.x * vel.x + vel.y * vel.y < 400 then vel.x, vel.y = 0, 0 end
        lastInput = now
    end

    local zooming = cam.vw ~= targetVw
    local panning = drag.active or vel.x ~= 0 or vel.y ~= 0 or moved
    ReleaseCity()
    -- (1.3.0: following, the view keeps as close to the unit as a map can show it, every frame - a clamp that glides
    -- would trail it; for a change of the map that bounds the view see below)
    local holder = lastHolderID
    local hx, hy = ClampCam(cam, dt, zooming and not fx, prevX, prevY, panning, fx ~= nil)
    if fx and anchor and holder and lastHolderID ~= holder then
        -- (1.3.0) Following, another map bounds the view now: where that map shows the unit at the screen point it had,
        -- it stays there and eases onto the centre (above). Centred at once, the view jumped: zoomed in from a
        -- continent's whole view, the world's map takes over where it can show the unit centred - 60 - 70 px from where
        -- the continent's edge held it by Stormwind. (Else as ClampCam has it: centred where the new map shows that,
        -- else a glide.)
        local new = lastHolderID
        local pp, pq = ns.PixelsPerUnit(v, prevVw)
        local sx, sy = v.W / 2 + (fx - prevX) * pp, v.H / 2 + (fy - prevY) * pq
        local q = { x = fx - (sx - v.W / 2) / ppx, y = fy - (sy - v.H / 2) / ppy, vw = cam.vw }
        local qx, qy = NearestHoldable(q)
        if lastHolderID == new and math.abs(qx - q.x) * ppx + math.abs(qy - q.y) * ppy < 0.5 then
            cam.x, cam.y, hx, hy = q.x, q.y, q.x, q.y
            gliding = false
            anchor.sx, anchor.sy = sx, sy
        end
        lastHolderID = new
    end
    if anchor then
        if anchor.held and not fx and not drag.active then
            -- (1.4.0-beta1, retail: OnMouseWheel's held) zooming in, the zoom keeps heading for the point aimed at: a
            -- clamp at a world's edge moves it on screen instead of handing the zoom to whatever slid under the cursor
            local hpx, hpy = ns.PixelsPerUnit(v, cam.vw)
            anchor.sx, anchor.sy = v.W / 2 + (anchor.wx - cam.x) * hpx, v.H / 2 + (anchor.wy - cam.y) * hpy
        else
            -- Keep the zoom anchored to the cursor from wherever the clamp put us.
            anchor.wx, anchor.wy = ScreenToWorldWith(cam, anchor.sx, anchor.sy)
        end
        -- (kept on a city and zooming in: the aim stays, see CityZoom)
        if not (depthCity and targetVw <= cam.vw) then -- (the aim also outlives a finished notch)
            anchor.ax, anchor.ay, anchor.asx, anchor.asy = anchor.wx, anchor.wy, anchor.sx, anchor.sy
        end
    end
    if drag.active then
        -- Same for the drag: at a map edge, re-grab what's under the cursor
        -- so pulling back responds at once and nothing builds up.
        drag.wx, drag.wy = ScreenToWorldWith(cam, drag.lastSx, drag.lastSy)
    end
    local settled = not gliding and math.abs(hx - cam.x) * ppx + math.abs(hy - cam.y) * ppy < 0.05
    UpdateFocus(now)

    if settled and not drag.active and vel.x == 0 and vel.y == 0 and not zooming
        and now - lastInput > IDLE_DELAY then
        BeginSettle()
    end
end

local function UpdateFly(dt, now)
    local f = fly
    f.t = f.t + dt
    local p = ns.EaseInOutCubic(f.t / f.dur)
    local X, Y, Wv = f.path(p * f.S)
    local k = v.W / v.fit0
    cam.x, cam.y, cam.vw = X / v.lw0, Y / v.lh0, Wv / k
    if f.aimed then FlightFollow(f, dt, now) end -- (1.3.0)
    if not (cam.x == cam.x and cam.y == cam.y and cam.vw == cam.vw and cam.vw > 0) then
        f.t = f.dur -- numerical trouble: jump to the end
    end
    if f.lockFocus and p >= 0.5 then
        -- Second half of a click flight: the destination goes on top (the
        -- swap happens while the camera is moving, never before or after).
        if not f.focusSet then
            f.focusSet = true
            -- finish the crossfade just before the flight lands
            Render:SetFadeTime(math.max(0.06, (f.dur - f.t) * 0.85))
            local M = f.target.map
            if M and ns.SpaceFocus then
                -- (1.4.0, retail: RetailSpace.lua) the map flown to and the chain above it - a world, an inset or a
                -- zone of Outland as well as a continent's zone
                local c, z = ns.SpaceFocus(f.target.x, f.target.y, M.id, f.target, v)
                Render:SetFocus(z)
                Render:SetContinentFocus(c)
            elseif M and M.mapType == ns.MAPTYPE_ZONE then
                Render:SetFocus(M.id)
                Render:SetContinentFocus(WalkUpTo(M.parent, ns.MAPTYPE_CONTINENT))
            elseif M and M.mapType == ns.MAPTYPE_CONTINENT then
                Render:SetContinentFocus(M.id)
            end
        end
    else
        UpdateFocus(now)
    end
    if f.t >= f.dur then
        cam.x, cam.y, cam.vw = f.target.x, f.target.y, f.target.vw
        fly = nil
        f.onDone(f)
    end
end

-- (1.1.0, Follow.lua) Following a unit at rest: the camera moves with it (its motion as it is: no lag at any speed) and
-- glides onto it (where it starts away from the centre), and Blizzard's map pans along - on the same map while that
-- can show the view, else on the one that can (ChooseHandover). In combat the map never changes: the view stays inside
-- the current map (the unit may leave the centre until combat ends). On a continent map a zone map takes over again as
-- soon as it can show the view (its pins).
local followZoneT = 0
-- The camera's move with the unit this frame; true when it is already on it (nil: no position, or a flight took over).
local function FollowCamera(dt, now, held)
    local tx, ty, mx, my = ns.Follow:Target(now)
    if not tx then return end
    local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)
    local ex, ey = (tx - cam.x) * ppx, (ty - cam.y) * ppy
    local still = ex * ex + ey * ey < 0.01 -- (under a tenth of a pixel)
    if not still then
        local k = 1 - math.exp(-dt * FOLLOW_RATE)
        if ex * ex + ey * ey > 4 * (v.W * v.W + v.H * v.H) then -- (two views away - a portal, a long flight: go)
            if FollowFar(tx, ty, held) then return nil end -- (1.3.0: by a flight)
            k = 1
        end
        local cx, cy = cam.x + (mx or 0), cam.y + (my or 0)
        cam.x, cam.y = cx + (tx - cx) * k, cy + (ty - cy) * k
    end
    return still
end

local function FollowStep(dt, now)
    local still = FollowCamera(dt, now)
    if still == nil then return end
    local cur = ns.GetMap(WorldMapFrame:GetMapID())
    local M = (cur and Holds(cur, cam)) and cur or nil
    local combat = InCombatLockdown()
    if not M then
        M = (not combat) and ChooseHandover(cam, QuestSafe) or nil
        if not M then
            if not cur then return end
            M = cur
            ClampToMap(M, cam)
        end
    elseif not combat and M.mapType ~= ns.MAPTYPE_ZONE and now - followZoneT > FOLLOW_ZONE_CHECK then
        followZoneT = now
        local B = ChooseHandover(cam, QuestSafe)
        if B and B.mapType == ns.MAPTYPE_ZONE then M = B end
    end
    if still and M == cur then return end -- (nothing moved, the map stays: nothing to do)
    local switched = M.id ~= WorldMapFrame:GetMapID()
    SyncReal(M)
    if switched then FocusRealMap() end
    restBusy = true
end

-- (1.2.0) Following while the view is held (BeginSettle: in combat, or no map we may switch to can show it - the
-- user: "zooming in and out while following, breaks the follow"): the camera goes on with the unit over our overlay,
-- Blizzard's map stays; out of combat the settle is tried again now and then, in combat when it ends.
local function FollowHeld(dt, now)
    if FollowCamera(dt, now, true) == nil then return end
    if not InCombatLockdown() and now - followZoneT > FOLLOW_ZONE_CHECK then
        followZoneT = now
        BeginSettle()
    end
end

local function OnUpdate(_, dt)
    if not ready or not WorldMapFrame:IsShown() then
        driver:Hide()
        return
    end
    if dt > 0.1 then dt = 0.1 end
    local now = GetTime()

    if drag.pending then
        if not IsMouseButtonDown("LeftButton") then
            drag.pending = false
        else
            local sx, sy = CursorPos()
            local dx, dy = sx - drag.sx, sy - drag.sy
            if dx * dx + dy * dy > dragThreshold * dragThreshold and Usable() then
                drag.pending = false
                if not drag.fromRest then
                    -- Our camera kept moving (glide, zoom, flight) while the
                    -- button was held: grab what is under the press point now.
                    drag.gx, drag.gy = ScreenToWorldWith(cam, drag.sx, drag.sy)
                end
                EnterFree()
                drag.active = true
                drag.liveN, drag.liveOff = 0, false -- (1.4.0-beta3, retail: a new stroke - LiveMap)
                drag.swallow = true
                if ns.Follow then ns.Follow:Stop() end -- (1.1.0: a drag takes the map back)
                drag.wx, drag.wy = drag.gx, drag.gy
                drag.lastSx, drag.lastSy = sx, sy
                vel.x, vel.y = 0, 0
                anchor, restAim = nil, nil
            end
        end
    end

    if state == "free" then
        UpdateFree(dt, now)
        if state == "free" then DrawFrame() end
    elseif state == "fly" then
        UpdateFly(dt, now)
        if state == "fly" then DrawFrame() end
    elseif state == "hold" then
        local following = ns.Follow and ns.Follow:Active() -- (1.2.0)
        if following then FollowHeld(dt, now) end
        if state == "hold" and not DrawFrame() and not drag.pending and not following then driver:Hide() end
    elseif state == "rest" then
        if realDirty then
            -- Blizzard moved its canvas by itself (tiny press-pan, gamepad,
            -- another addon): follow it so our art stays under the pins.
            realDirty = false
            local r = ReadRealView()
            if r and r.map.id == WorldMapFrame:GetMapID() and DiffersFromCam(r) then
                cam.x, cam.y, cam.vw = r.x, r.y, r.vw
                targetVw = cam.vw
                restBusy = true
                restAim = nil -- (the view moved under a still cursor: aim afresh)
            end
        end
        local following = ns.Follow and ns.Follow:Active() -- (1.1.0)
        if following then FollowStep(dt, now) end
        if restBusy then restBusy = DrawFrame() end
        if not restBusy and not drag.pending and not realDirty and not following then driver:Hide() end
    elseif not drag.pending then
        driver:Hide()
    end
end

---------------------------------------------------------------------------
-- Input & Blizzard hooks
---------------------------------------------------------------------------
-- (1.3.0) A notch on a flight to the one followed (StartAimed): the zoom it lands at, a notch deeper or wider -
-- no deeper than the wheel may go there - and the flight goes on (FlightFollow eases the zoom).
local function WheelInFlight(f, delta)
    local w0 = f.target.vw * f.zoomF
    local w = w0 / (db.zoomStep ^ delta)
    if delta > 0 then
        local D = DeepestAt(f.target.x, f.target.y)
        w = math.max(w, math.min(ns.WidthForZoom(v, D, D.maxZoom or db.maxZoom), w0)) -- (1.4.0: D.maxZoom, retail)
    end
    f.zoomF = math.min(w, 1) / f.target.vw
    lastInput = GetTime()
    lastWheel = lastInput
end

-- ((1.4.0-beta13, retail: RetailDoors.lua) A door's click: the view it was clicked at, for the way back; chain: the maps above
-- the door's. Back out of the door's map - Blizzard's right click to a map of the chain, the wheel out past its least zoom -
-- that view shows again, at once, as WoW Forever's dungeon view lies over a world map that never moved: the player on
-- 1.4.0-beta12, "right clicking to go back to world does not put your back to the same view you had before entering the
-- dungion". true: done.
local doorReturn
local function SetDoorReturn(home, dm)
    local chain, id, guard = {}, dm, 0
    while id and id ~= 0 and guard < 8 do
        local ok, info = pcall(C_Map.GetMapInfo, id)
        id = ok and type(info) == "table" and info.parentMapID
        if id then chain[id] = true end
        guard = guard + 1
    end
    doorReturn = { home = home, chain = chain }
end
local function BackFromDoor(mapID)
    local r = doorReturn
    doorReturn = nil
    if not (r and r.home and (not mapID or r.chain[mapID])) then return false end
    return JumpToZoom(r.home.x, r.home.y, ns.WorldZoom(v, r.home.vw))
end

-- ((1.4.0-beta12, retail: ns.SpaceAncestor) The add-on standing aside on Blizzard's map of a map it does not draw (a
-- dungeon - M inside an instance), that map zoomed out as far as Blizzard's goes: the zoom out goes on in the add-on's map,
-- from the nearest map above it the add-on draws, whole (the player on 1.4.0-beta11: "if i hit m while in an instance,
-- zooming out will not go back to world"); where no map we may switch to shows that view, held there. true: done.
local function LeaveOff()
    if not (ns.SpaceAncestor and ready and db.enabled and WorldMapFrame:IsShown() and UpdateView()) then return false end
    if doorReturn and BackFromDoor() then return true end
    local A = ns.SpaceAncestor(WorldMapFrame:GetMapID())
    local world = ns.maps[ns.WORLD_MAP_ID]
    if not (A and world) then return false end
    local w = ns.WidthForZoom(v, A, 1)
    if JumpToZoom(A.cx, A.cy, ns.WorldZoom(v, w)) then return true end
    cam.x, cam.y, cam.vw = A.cx, A.cy, w
    fly, anchor, restAim = nil, nil, nil
    vel.x, vel.y = 0, 0
    overlay:Show()
    SetBlizzardWheel(true)
    EnterHold()
    return true
end

local function OnMouseWheel(_, delta)
    if state == "off" and delta < 0 and ns.SpaceAncestor and container.IsAtMinZoom and container:IsAtMinZoom() then
        LeaveOff()
        return
    end
    if not Usable() or delta == 0 then return end
    if state == "fly" and fly and fly.aimed and ns.Follow and ns.Follow:Active() then
        WheelInFlight(fly, delta)
        return
    end
    local prev = (state == "free" and anchor) or (state == "rest" and restAim)
    restAim = nil
    -- (1.3.0) Following: the zoom is about the unit - where it is now, not the view's centre, which may trail it or be
    -- held off it by a map's edge - as deep as the map under it allows, and no city pulls the view off it (UpdateFree).
    local fx, fy, fdx, fdy = FollowPoint(GetTime())
    if fx then depthCity = nil end
    EnterFree()
    local sx, sy = CursorPos()
    if ns.Follow and ns.Follow:Active() then sx, sy = v.W / 2, v.H / 2 end -- (1.1.0: following - zoom about them)
    if fx then
        -- The unit's screen point: the centre - or, while the view was still catching up with it (the glide onto it,
        -- or held off it by the current map in combat), where the camera last put it; it eases onto the centre
        -- (UpdateFree). Only the part of that offset the free view's own bounds don't force (the world's or a
        -- continent's edge, see NearestHoldable) counts: zoomed in from there, the view comes back onto the unit as
        -- soon as a map can show it.
        if not lastHolderID then
            -- (from rest the bound is the map the view rests on, when that is the world's or a continent's own view:
            -- from Eastern Kingdoms' whole view the world's nearest view of you lies elsewhere - zoomed about that, the
            -- view first went away from you)
            local R = ns.GetMap(WorldMapFrame:GetMapID())
            -- (1.4.0, retail: R.holder - every map that bounds the camera, RetailSpace.lua)
            if R and (R.id == ns.WORLD_MAP_ID or R.mapType == ns.MAPTYPE_CONTINENT or R.holder) then lastHolderID = R.id end
        end
        local q = { x = fx - (fdx or 0), y = fy - (fdy or 0), vw = cam.vw } -- (where it was when the camera last moved)
        local keep = lastHolderID
        local hx, hy = NearestHoldable(q)
        lastHolderID = keep
        local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)
        sx, sy = v.W / 2 + (hx - cam.x) * ppx, v.H / 2 + (hy - cam.y) * ppy
    end
    local points = { fx or cam.x, fy or cam.y }
    if drag.active then
        anchor = nil
    else
        local wx, wy = ScreenToWorldWith(cam, sx, sy)
        if fx then wx, wy = fx, fy end
        -- (1.4.0-beta1, retail) a notch in with the cursor where the last one was taken: the zoom goes on toward that
        -- notch's point, wherever a clamp at a world's edge has moved it on screen (UpdateFree) - zoomed in at a place
        -- near Azeroth's edge from space, the place no longer slides away from the zoom
        local held = ns.holders and delta > 0 and not fx and not depthCity
        local hx, hy, cx0, cy0 = sx, sy, sx, sy
        if held and prev and prev.held and prev.cx and (sx - prev.cx) ^ 2 + (sy - prev.cy) ^ 2 <= dragThreshold * dragThreshold then
            local hpx, hpy = ns.PixelsPerUnit(v, cam.vw)
            wx, wy, cx0, cy0 = prev.wx, prev.wy, prev.cx, prev.cy
            hx, hy = v.W / 2 + (wx - cam.x) * hpx, v.H / 2 + (wy - cam.y) * hpy
        end
        points[3], points[4] = wx, wy
        anchor = { wx = wx, wy = wy, sx = hx, sy = hy, ax = wx, ay = wy, asx = hx, asy = hy }
        if held then anchor.held, anchor.cx, anchor.cy = true, cx0, cy0 end
        if delta > 0 and depthCity and prev and prev.asx
            and (sx - prev.asx) ^ 2 + (sy - prev.asy) ^ 2 <= dragThreshold * dragThreshold then
            -- Another notch in while kept on a city, the cursor still (less
            -- than a drag's threshold from where the aim was taken): keep
            -- aiming at the spot the burst started on, which the city's pull
            -- may have slid away from the cursor (see CityZoom).
            anchor.ax, anchor.ay, anchor.asx, anchor.asy = prev.ax, prev.ay, prev.asx, prev.asy
        end
    end
    vel.x, vel.y = 0, 0

    local newT = targetVw / (db.zoomStep ^ delta)
    if delta > 0 then
        -- Depth limit: maxZoom past the deepest map under the cursor (or the
        -- centre). Only ever stops further zooming in, never pushes you out.
        local floor = math.huge
        for i = 1, #points, 2 do
            -- (1.4.0, retail: a map's own limit - the Cosmic map's over open space, RetailSpace.lua)
            local D = DeepestAt(points[i], points[i + 1])
            floor = math.min(floor, ns.WidthForZoom(v, D, D.maxZoom or db.maxZoom))
        end
        newT = math.max(newT, math.min(floor, targetVw))
        -- (deeper than a capital's zone goes: the view is kept on the city - not while following, 1.3.0)
        if not fx then EngageCity(points, newT) end
    end
    targetVw = math.min(newT, 1)
    lastInput = GetTime()
    lastWheel = lastInput
    -- the focus follows where the zoom now heads, at once (not up to 0.08 s later)
    UpdateFocus(lastInput, true)
end

-- (1.4.0-beta12) A press on our catcher while the map holds (Blizzard's map cannot show the view; its canvas, on another
-- map, lies hidden under the catcher): its release, when no drag came of it, is a click on the map - ours (OurClick).
-- (The player's 1.4.0-beta11 session held at every view - no door, city, quest or zone answered a click: a hold is no
-- motion, only Blizzard's map cannot follow.)
local holdPress
local OurClick

local function OnGlobalMouseDown(button)
    holdPress = nil
    -- (retail: ns.SpaceNavigate; WoW Forever holds only in combat, its clicks eaten there as before)
    if state == "hold" and ns.SpaceNavigate and Usable() and MouseFocus() == catcher then
        local x, y = CursorPos()
        holdPress = { button = button, x = x, y = y }
    end
    if button ~= "LeftButton" then return end
    drag.swallow = false
    if not Usable() then return end
    -- Only presses on the bare map (or our mouse catcher while it moves) pan;
    -- presses on Questie icons or other pins behave as usual.
    local f = MouseFocus()
    if f ~= container and f ~= container.Child and f ~= overlay and f ~= catcher then return end
    drag.pending = true
    drag.fromRest = (state == "rest")
    if state == "free" then
        -- Tap to stop a glide.
        vel.x, vel.y = 0, 0
        lastInput = GetTime()
    end
    drag.sx, drag.sy = CursorPos()
    -- Grab point from the view *before* Blizzard starts panning its canvas.
    local base = cam
    if state == "rest" then base = ReadRealView() or cam end
    drag.gx, drag.gy = ScreenToWorldWith(base, drag.sx, drag.sy)
    driver:Show()
end

local function OnGlobalMouseUp(button)
    local hp = holdPress
    holdPress = nil
    if button == "LeftButton" then
        drag.pending = false
        if drag.active then EndDrag() end
    end
    -- (1.4.0-beta12: a click while the map holds - still held, so no drag came of the press, the cursor where it was)
    if hp and hp.button == button and state == "hold" then
        local x, y = CursorPos()
        if math.abs(x - hp.x) + math.abs(y - hp.y) <= dragThreshold then OurClick(button) end
    end
end

-- The add-on's own click on the map, at rest and (1.4.0-beta12) while it holds; true: the click was ours.
OurClick = function(button)
    -- (1.1.0, Follow.lua) a click on your arrow or a party member's dot follows them (on the one followed: stops)
    if ns.Follow and ns.Follow:OnCanvasClick(button) then return true end
    -- ((1.4.0-beta14, Portals.lua) a way across the world: a flight to its end - 1.5.0: before Dungeon.lua, whose bare detail art takes any click on it)
    if ns.Portals and ns.Portals:OnCanvasClick(button) then return true end
    -- (Dungeon.lua) a click on a dungeon / raid entrance label opens its maps
    if ns.Dungeon and ns.Dungeon:OnCanvasClick(button) then return true end
    -- (1.4.0-beta3, retail: RetailDoors.lua - nil on WoW Forever) a click on a door's name flies there, then opens its map
    if ns.RetailDoors and ns.RetailDoors:OnCanvasClick(button) then return true end
    -- (1.4.0-beta10, Pins.lua) a flight master's, a point of interest's, a quest's - (1.6.0) on WoW Forever its quests'
    if ns.Pins and ns.Pins:OnCanvasClick(button) then return true end
    -- ((1.4.0-beta12, retail: RetailSpace.lua - nil on WoW Forever) the map under the cursor: Blizzard's own navigation in
    -- the add-on's layout - Blizzard's map knows its children where Blizzard lays them out, and while the map holds it is
    -- another map)
    if ns.SpaceNavigate and ns.SpaceNavigate(button) then return true end
    return false
end

-- Runs before Blizzard turns a canvas click into a map switch. A click that
-- was really the end of our drag (or lands while we drive the view) is eaten.
local function OnCanvasClick(_, button)
    if not ready or not db.enabled then return false end
    if drag.swallow and button == "LeftButton" then return true end
    if state == "free" or state == "fly" or state == "hold" then return true end
    if state == "rest" and OurClick(button) then return true end
    return false
end

-- Any map change we didn't make (clicking a zone, right-click out, Questie,
-- the quest log...) becomes a smooth flight to the new map.
local function OnMapChanged()
    if syncing or not ready or not WorldMapFrame:IsShown() then return end
    if not db.enabled then return end
    if not UpdateView() then return end
    local target = ReadRealView()
    if not target then
        GoOff()
        return
    end
    if state == "off" or justShown then
        if state == "off" and not justShown and doorReturn and BackFromDoor(target.map.id) then return end
        cam.x, cam.y, cam.vw = target.x, target.y, target.vw
        EnterRest()
        return
    end
    -- (1.4.0, retail: RetailSpace.lua) another floor or copy of the map shown - Blizzard's floor list, a phase - lies on
    -- the same rect: its picture takes over in place (RetailRender.lua crossfades it), the camera stays where it is
    if (state == "rest" or state == "hold") and ns.SpaceSwap and ns.SpaceSwap(target.map.id) and Holds(target.map, cam) then
        fly, anchor, restAim = nil, nil, nil
        SyncReal(target.map)
        EnterRest(true)
        return
    end
    if ns.Follow then ns.Follow:Stop() end -- (1.1.0: a map change we did not make - a zone clicked, the quest log)
    drag.active = false
    vel.x, vel.y, anchor, restAim = 0, 0, nil, nil
    depthCity = nil -- (the landing decides again, see RestCity)
    StartFly(target, function(f)
        if f.liveUsed then
            -- Blizzard's canvas followed the flight (on the map that was
            -- asked for): line it up with the landing view.
            local M = ns.GetMap(WorldMapFrame:GetMapID())
            if M then SyncReal(M) end
        else
            -- Blizzard may have moved on while we were flying.
            local real = ReadRealView()
            if real then cam.x, cam.y, cam.vw = real.x, real.y, real.vw end
        end
        EnterRest()
    end, true)
end

-- Maximize/minimize, the quest log panel and UI scale changes resize the map
-- and make Blizzard reset its zoom. Put the zoom straight back (same frame,
-- so the reset never shows).
local function OnFrameSizeChanged()
    restAim = nil -- (the layout changes: the point under the cursor with it)
    if not ready or state == "off" or not WorldMapFrame:IsShown() or v.W <= 0 then return end
    if state == "rest" then
        local M = ns.GetMap(WorldMapFrame:GetMapID())
        if not M then return end
        local z = ns.ZoomOf(v, M, cam.vw) -- measured with the old size
        local x, y = cam.x, cam.y
        if not UpdateView() then return end
        cam.x, cam.y = x, y
        cam.vw = ns.WidthForZoom(v, M, math.max(z, 1))
        ClampToMap(M, cam)
        targetVw = cam.vw
        syncing = true
        local ok, err = pcall(SetRealView, RealParams(M, cam))
        syncing = false
        if not ok then geterrorhandler()(err) end
        restBusy = DrawFrame()
        if restBusy then driver:Show() end
    else
        -- Moving: DrawFrame puts Blizzard's canvas back on the camera (live),
        -- or our overlay hides the reset until the handover re-syncs.
        UpdateView()
        anchor = nil
        if drag.active then
            -- Keep the grabbed point under the cursor in the new layout.
            local ppx, ppy = ns.PixelsPerUnit(v, cam.vw)
            local sx, sy = CursorPos()
            cam.x = drag.wx - (sx - v.W / 2) / ppx
            cam.y = drag.wy - (sy - v.H / 2) / ppy
            drag.lastSx, drag.lastSy = sx, sy
        end
        if state == "free" then ClampCam(cam) end
        DrawFrame()
    end
end

local function OnCanvasScaleChanged()
    if ready and overlay then FitLayers() end
end

local function MarkRealDirty()
    if syncing or not ready or state ~= "rest" then return end
    realDirty = true
    driver:Show()
end

-- Runs right after the canvas's own OnUpdate. While live, that OnUpdate can
-- move the canvas after our sync in the same frame (Blizzard's drag-pan
-- while the button that started a drag at rest is held, its release glide):
-- put it back under the camera before the frame is drawn. (When our driver
-- hasn't run yet this frame it syncs anyway, so nothing is done twice.)
local function AfterCanvasUpdate()
    if not live or liveT ~= GetTime() or not Moving() or not ready then return end
    if container:GetCanvasScale() ~= liveS or container:GetCurrentScrollX() ~= liveP
        or container:GetCurrentScrollY() ~= liveQ then
        SyncMoving()
    end
end

-- (Dungeon.lua) the dungeon view hands the map back and forth with these.
local function ExportCore()
    ns.Core = {
        GoOff = GoOff,
        ResyncFromReal = ResyncFromReal,
        State = function() return state end,
        -- ((1.4.0-beta12) the view still: at rest, or held where Blizzard's map cannot follow - the markers' hover then)
        Settled = function() return state == "rest" or state == "hold" end,
        Cam = function() return cam, v end, -- (1.0.0, ZoomReadout.lua)
        -- (1.1.0, Follow.lua)
        CursorPos = CursorPos,
        JumpToZoom = JumpToZoom,
        FlyToZoom = FlyToZoom, -- (1.3.0, PartyBubbles.lua)
        QuestSafe = QuestSafe, -- (1.4.0-beta3, retail: RetailDoors.lua - a dungeon's map opened by a door click)
        SetDoorReturn = SetDoorReturn, -- (1.4.0-beta13, retail: RetailDoors.lua)
        -- (1.3.0, PartyBubbles.lua) the width of the view the motion under way ends on - a flight's landing (a notch on
        -- the way included), a wheel zoom's target - else the view's: "your zoom" in the middle of a flight's arc
        LandingVw = function()
            if state == "fly" and fly then return fly.target.vw * (fly.zoomF or 1) end
            if state == "free" then return targetVw end
            return cam.vw
        end,
        JustShown = function() return justShown end,
        Wake = function() if ready then driver:Show() end end,
        -- (1.4.0, retail) a flight to view (x, y, vw) in the camera's own units, as a party bubble's (StartAimed): from
        -- the view shown, landing on the most detailed map that can show it; false when the map is closed or off
        FlyToView = function(x, y, vw)
            if not ready or not db.enabled or not WorldMapFrame:IsShown() or not UpdateView() or state == "off" then return false end
            local t = FlightTarget(x, y, math.min(vw, 1))
            if not t then return false end
            if state == "rest" then
                local real = ReadRealView()
                if real then cam.x, cam.y, cam.vw = real.x, real.y, real.vw end
            end
            -- ((1.4.0-beta16) a click on a zone, a door or a way takes the map, as a drag does: M opens the map following you, and each of these landed and then flew back to your character)
            if ns.Follow then ns.Follow:Stop() end
            StartAimed(t)
            return true
        end,
        -- (1.3.1: the fog of war, Gilneas.lua) an area discovered: as MAP_EXPLORATION_UPDATED - the explored art rebuilt
        -- where it is used, and drawn at once at rest
        ExplorationChanged = function()
            if not ready then return end
            Render:MarkArtDirty()
            if state == "rest" or state == "hold" then
                restBusy = true
                driver:Show()
            end
        end,
        -- (1.4.0-beta2, retail: RetailWhy.lua's /unroll why and its silent snapshots - read only) the frames the view
        -- stands on, live or detached, the map the settle would pick (best) and, asked (full), the one it may switch to
        -- (QuestSafe: its one-second memo is filled as Core's own asking does); busy: the driver still runs
        Diag = function(full)
            local d = { container = container, overlay = overlay, cityLayer = cityLayer, labelLayer = labelLayer, live = live,
                detached = overlayMoving, busy = driver:IsShown(), real = ReadRealView(), best = ChooseHandover(cam),
                holder = lastHolderID }
            local R = ns.GetMap(WorldMapFrame:GetMapID())
            d.holdsReal = R ~= nil and Holds(R, cam)
            if full then
                d.safe = ChooseHandover(cam, QuestSafe)
                if d.best then d.questSafe = QuestSafe(d.best.id) end
            end
            return d
        end,
        -- (1.4.0-beta2, retail: /unroll test) draw again at rest, as after a change of the art
        Redraw = function()
            if ready and (state == "rest" or state == "hold") then
                restBusy = true
                driver:Show()
                if drawing then redrawAsked = true end
            end
        end,
    }
end

local function Setup()
    if ready or not WorldMapFrame or not WorldMapFrame.ScrollContainer then return end
    if not ns.BuildRegistry() then
        print("|cff33ccffEndless Map|r: couldn't read the world map layout; addon disabled.")
        return
    end

    Render, Labels = ns.Render, ns.Labels
    container = WorldMapFrame.ScrollContainer
    -- (1.4.0: ns.FLAVOR, OneCopy.lua - the same answer as the interface number >= 16000 before: every game but Classic
    -- Era takes the 4th argument - WoW Forever, the other Classic games, retail)
    fourArgPanZoom = (container.HasZoomLevels ~= nil) or ns.FLAVOR ~= "era"
    dragThreshold = fourArgPanZoom and 4 or 3 -- just under Blizzard's click distance
    blizzWheelMode = container.mouseWheelZoomMode or MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_FULL or 2

    -- Rest band: below every pin (incl. Blizzard's zone highlight and all of
    -- Questie's icons) and above the map tiles of Blizzard's canvas.
    local function PinLevel(kind)
        if not WorldMapFrame.GetPinFrameLevelsManager then return end
        local ok, level = pcall(function()
            return WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel(kind)
        end)
        if ok and type(level) == "number" and level > 0 and level < 8000 then return level end
    end
    local lowestPin = PinLevel("PIN_FRAME_LEVEL_DEFAULT") or 2000
    local exploration = PinLevel("PIN_FRAME_LEVEL_MAP_EXPLORATION")
    if exploration and exploration < lowestPin then lowestPin = exploration end
    restStageCap = lowestPin - 1
    restLevel = restStageCap - REST_BAND
    local childLevel = container.Child and container.Child:GetFrameLevel() or 0
    if restLevel <= childLevel then restLevel = childLevel + 1 end
    if restStageCap < restLevel then restStageCap = restLevel end
    labelsRestLevel = (exploration or 2002) + 12
    -- Pictures that must draw over the real map's explored areas at rest:
    -- above the exploration pin, below the zone hover highlight and the
    -- labels. (The levels in between belong to the Plunderstorm, event
    -- overlay, garrison, fog-of-war and quest/scenario blob pins -
    -- Blizzard_WorldMap.lua AddStandardDataProviders; lifted pictures take
    -- the lowest ones first.)
    local highlight = PinLevel("PIN_FRAME_LEVEL_MAP_HIGHLIGHT")
    if exploration and highlight and highlight - 1 >= exploration + 2 and highlight <= labelsRestLevel then
        liftLo, liftHi = exploration + 1, highlight - 1
    end
    -- (1.0.0) The pictures that must draw over Blizzard's own map art - the city / detail maps, a home zone's banner
    -- cover, a picture stacked above the real map's explored pieces - live in their own clipping frame, the city layer.
    -- In the client a frame that clips its children draws them as ONE block at its own place among its siblings: lifted
    -- inside the overlay they never got above the canvas' pins, and the real map's explored areas (Dun Morogh's
    -- IRONFORGE banner, Alterac's DALARAN) or a continent map's zone hover highlight covered the cities. The layer sits
    -- right above the highlight (the levels of Blizzard's debug pins), under every icon pin and our labels.
    if liftLo then
        cityLevel = (highlight or liftHi) + 1
        if cityLevel >= labelsRestLevel then cityLevel = labelsRestLevel - 1 end
        cityLevelZone = liftLo -- (1.0.0: over a zone map, see SetOverlayMode)
    end

    overlay = CreateFrame("Frame", nil, container)
    ns.SetLevelFixed(overlay, restLevel)
    overlay.level = restLevel
    overlay:SetAllPoints(container)
    overlay:SetClipsChildren(true)
    overlay:EnableMouse(false)
    overlay.mouse = false
    overlay:Hide()

    labelLayer = CreateFrame("Frame", nil, container)
    ns.SetLevelFixed(labelLayer, labelsRestLevel)
    labelLayer.level = labelsRestLevel
    labelLayer:SetAllPoints(container)
    labelLayer:SetClipsChildren(true)
    labelLayer:EnableMouse(false)

    -- (1.0.0) the city layer (see above); shown and hidden with the overlay
    cityLayer = CreateFrame("Frame", nil, container)
    ns.SetLevelFixed(cityLayer, cityLevel or restLevel)
    cityLayer.level = cityLevel or restLevel
    cityLayer:SetAllPoints(container)
    cityLayer:SetClipsChildren(true)
    cityLayer:EnableMouse(false)
    cityLayer:SetShown(overlay:IsShown())
    overlay:HookScript("OnShow", function() cityLayer:Show() end)
    overlay:HookScript("OnHide", function() cityLayer:Hide() end)

    -- Invisible, above every pin: takes the mouse while the map moves.
    catcher = CreateFrame("Frame", nil, container)
    ns.SetLevelFixed(catcher, CATCHER_LEVEL)
    catcher:SetAllPoints(container)
    catcher:EnableMouse(true)
    catcher:Hide()

    driver = CreateFrame("Frame")
    driver:Hide()
    driver:SetScript("OnUpdate", OnUpdate)
    if ns.Perf then ns.Perf.Start() end -- (1.4.0-beta15, retail: RetailBench.lua)

    Render:Init(overlay)
    if Render.SetCityLayer then Render:SetCityLayer(cityLayer) end
    Labels:Init(labelLayer)
    if ns.Doors then ns.Doors:Merge() end -- (1.0.0: the doors of Doors.lua - Forever rows, placeholders, learned doors)
    Labels:Build()
    if ns.Doors then ns.Doors:Attach() end -- (their icons: placeholders, learned doors, the "you are inside" door)
    SetOverlayMode(false)

    hooksecurefunc(WorldMapFrame, "OnMapChanged", OnMapChanged)
    if WorldMapFrame.OnFrameSizeChanged then
        hooksecurefunc(WorldMapFrame, "OnFrameSizeChanged", OnFrameSizeChanged)
    end
    if WorldMapFrame.OnCanvasScaleChanged then
        hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", OnCanvasScaleChanged)
        hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", MarkRealDirty)
    end
    if WorldMapFrame.OnCanvasPanChanged then
        hooksecurefunc(WorldMapFrame, "OnCanvasPanChanged", MarkRealDirty)
    end
    if WorldMapFrame.AddCanvasClickHandler then
        WorldMapFrame:AddCanvasClickHandler(OnCanvasClick, 100)
    end
    container:HookScript("OnMouseWheel", OnMouseWheel)
    -- (as Blizzard_GamepadSmartNavigation/Debug.lua:67 hooks an OnUpdate)
    container:HookScript("OnUpdate", AfterCanvasUpdate)
    WorldMapFrame:HookScript("OnShow", function()
        hideGen = hideGen + 1
        justShown = true
        ResyncFromReal()
        C_Timer.After(0, function() justShown = false end)
    end)
    WorldMapFrame:HookScript("OnHide", function()
        GoOff()
        doorReturn = nil
        hideGen = hideGen + 1
        local gen = hideGen
        C_Timer.After(RELEASE_DELAY, function()
            if gen == hideGen and not WorldMapFrame:IsShown() then Render:ReleaseAll() end
        end)
    end)

    ready = true
    ExportCore()
    if WorldMapFrame:IsShown() then ResyncFromReal() end
    if ns.Dungeon then ns.Dungeon:Setup() end
    if ns.Follow then ns.Follow:Setup() end -- (1.1.0: the M key)
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffEndless Map|r: " .. msg)
end

local function OnOff(b) return b and "|cff40ff40on|r" or "|cffff4040off|r" end

local function Refresh()
    if not ready or not WorldMapFrame:IsShown() then return end
    if ns.Dungeon and ns.Dungeon:Refresh() then return end -- (the dungeon view owns the map)
    if not db.enabled then
        GoOff()
    elseif state == "off" or state == "rest" then
        ResyncFromReal()
    else
        DrawFrame()
    end
end

-- The slash words (1.3.1: /endlessmap, the add-on's name; /unroll stays the short form the messages name). (1.4.0-beta4) By
-- the game (OneCopy.lua ns.COMMANDS, ns.SLASH): WoW Forever and Classic Era SLASH_AZEROTHUNROLLED1..4 = /unroll,
-- /azerothunrolled, /endlessmap, /emap; retail SLASH_ENDLESSMAP1..2 = /emap, /endlessmap (no /unroll there).
for i, word in ipairs(ns.COMMANDS) do _G["SLASH_" .. ns.SLASH .. i] = word end
SlashCmdList[ns.SLASH] = function(input)
    local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    local num = tonumber(arg)
    if ns.Options and ns.Options:Slash(cmd, arg, num) then
        -- (Azeroth Unrolled 1.0.0, Options.lua: on / off / toggle, depth, step, speed, labels, names, icons, rest, flight,
        -- mosaic, cells, livepins, dungeons, markers, bosses, button, reset - the one path the commands, the map menu
        -- and the Settings page share)
    elseif cmd == "doors" then
        if ns.Doors then ns.Doors:Slash(arg) else Print("doors: not available") end
    elseif cmd == "zoom" or cmd == "cityzoom" or cmd == "cavezoom" or cmd == "questzoom" then -- (1.6.0: questzoom)
        if ns.ZoomReadout then
            ns.ZoomReadout:Slash(cmd, num, Print, arg)
            if ready then Refresh() end
        else
            Print("zoom: not available")
        end
    elseif cmd == "follow" or cmd == "openzoom" or cmd == "openfollow" then
        if ns.Follow then ns.Follow:Slash(cmd, num, Print, arg) else Print(cmd .. ": not available") end
    elseif cmd == "taint" then
        -- (1.1.1) Did a map switch of ours put quest objects into Blizzard's quest cache (QuestSafe)?
        local cache, n, mine, list = QuestCache and QuestCache.objects, 0, 0, {}
        if type(cache) == "table" and issecurevariable then
            for q, o in pairs(cache) do
                n = n + 1
                local secure, by = issecurevariable(o, "questID")
                if not secure then
                    mine = mine + 1
                    if #list < 10 then list[#list + 1] = ("%s (%s)"):format(tostring(q), tostring(by)) end
                end
            end
            Print(("quest cache: %d quests, %d tainted%s"):format(n, mine, mine > 0 and (": " .. table.concat(list, ", ")) or ""))
        else
            Print("quest cache: not in this client")
        end
        local d = QuestMapFrame and QuestMapFrame.DetailsFrame
        if d and issecurevariable then
            local secure, by = issecurevariable(d, "questID")
            Print("quest log details: " .. (secure and "clean" or ("tainted by " .. tostring(by))))
        end
    elseif cmd == "bench" and ns.RetailBench then
        -- (1.4.0-beta15, retail: RetailBench.lua) what the map costs in this client
        ns.RetailBench.Slash(arg, Print)
    elseif (cmd == "why" or cmd == "test") and ns.RetailWhy then
        -- (1.4.0-beta2, retail: RetailWhy.lua) what the view shows and why; the session's test switches (WoW Forever: the
        -- help, as before)
        ns.RetailWhy.Slash(cmd, arg, Print)
    elseif cmd == "debug" then
        if not ready then Print("not set up yet") return end
        local child = container.Child
        local function Where(f)
            local p = f:GetParent()
            return (p == child and "in canvas") or (p == container and "beside canvas") or "elsewhere"
        end
        local function Info(f)
            if not f then return "none" end
            return ("%s level %d %s alpha %.2f scale %.3f"):format(f:GetFrameStrata(), f:GetFrameLevel(),
                f:IsShown() and "shown" or "hidden", f:GetAlpha(), f:GetEffectiveScale())
        end
        Print(("state %s%s, map %s, canvas scale %.3f"):format(state, (Moving() and (live and " (live)" or " (detached)")) or "",
            tostring(WorldMapFrame:GetMapID()), container:GetCanvasScale() or 0))
        Print("map frame: " .. Info(WorldMapFrame))
        Print("canvas: " .. Info(child))
        Print("art: " .. Info(overlay) .. ", " .. Where(overlay))
        Print("labels: " .. Info(labelLayer) .. ", " .. Where(labelLayer))
        local n, lo, hi, strata = 0
        pcall(function()
            for _, pool in pairs(WorldMapFrame.pinPools or {}) do
                for pin in pool:EnumerateActive() do
                    if pin:IsShown() then
                        n = n + 1
                        local l = pin:GetFrameLevel()
                        lo, hi = math.min(lo or l, l), math.max(hi or l, l)
                        strata = strata or pin:GetFrameStrata()
                    end
                end
            end
        end)
        Print(("pins shown: %d, levels %s-%s, strata %s"):format(n, tostring(lo), tostring(hi), tostring(strata)))
        if ns.Dungeon then Print(ns.Dungeon:DebugLine()) end
        if ns.OtherCopies then -- (1.3.1, OneCopy.lua) the copies of the add-on that stood down for this one
            local others = ns.OtherCopies()
            if others then Print(others) end
        end
    else
        if ns.FLAVOR == "retail" then
            -- (1.4.0) retail: the settings it has there (no flight master labels, no dungeon maps)
            Print(("zoom %s | depth %gx | step %gx | speed %gx | labels %s (still: %s)"):format(
                OnOff(db.enabled), db.maxZoom, db.zoomStep, db.flySpeed, OnOff(db.labels), OnOff(db.labelsAtRest)))
        else
            Print(("zoom %s | depth %gx | step %gx | speed %gx | labels %s (still: %s, flight: %s) | dungeons %s"):format(
                OnOff(db.enabled), db.maxZoom, db.zoomStep, db.flySpeed,
                OnOff(db.labels), OnOff(db.labelsAtRest), OnOff(db.flightPaths), OnOff(db.dungeons)))
        end
        -- ((1.4.0-beta4) C: the short command by the game - /unroll on WoW Forever and Classic Era, /emap on retail)
        local C = ns.COMMAND
        Print(("/endlessmap <command> always works; %s <command> is the short form:"):format(C))
        Print(C .. " on | off")
        Print(C .. " depth <1-10>   how far past a zone you can zoom")
        Print(C .. " step <1.05-2>  zoom per wheel notch")
        Print(C .. " speed <0.25-4> click flight speed")
        -- (1.4.0) on retail only the lines of what it has there: no mosaic, cells, dungeon maps, markers, bosses, doors,
        -- city or cave switch (WoW Forever's; RetailRender.lua draws Blizzard's own pictures)
        local forever = ns.FLAVOR ~= "retail"
        Print(C .. (forever and " labels | rest | flight   toggle place labels" or " labels | rest   toggle place labels"))
        if forever then
            Print(C .. " mosaic        toggle unexplored zone land (map-style mosaic)")
            Print(C .. " cells         toggle seamless zone cells (off: land shapes only)")
        end
        Print(C .. " livepins      toggle map icons moving with the map (off: hidden while moving)")
        if forever then
            Print(C .. " dungeons      toggle dungeon maps (click a dungeon label; opens inside dungeons)")
            Print(C .. " markers       group on entrance maps: the game's own widget / addon dots")
            Print(C .. " bosses        toggle boss and entrance markers on dungeon maps")
            Print(C .. " doors         list the doors (hints [on|off]: placeholders; forget [id]: learned doors)")
        end
        Print(C .. " zoom          toggle a zoom readout on the map (world zoom: 1.00x = the whole world map)")
        if forever then
            Print((C .. " cityzoom <N>  world zoom from which the city maps show (default %.2f; off: 1.5x of each city's own zone)"):format(ns.Render.CITY_G))
            Print((C .. " cavezoom <N>  world zoom from which the caves show (%d to %d, default %d; off: never)"):format(
                ns.Render.CAVE_G_MIN, ns.Render.CAVE_G_MAX, ns.Render.CAVE_G))
            if ns.Pins and ns.Pins.QUEST_G then -- (1.6.0)
                Print((C .. " questzoom <N> world zoom from which every zone's quest icons show (%d to %d, default %d; off: Blizzard's own)"):format(
                    ns.Pins.QUEST_G_MIN, ns.Pins.QUEST_G_MAX, ns.Pins.QUEST_G))
            end
        end
        Print(C .. " follow        toggle following a character when you click their arrow / dot on the map")
        Print(C .. " openzoom <N>  the world zoom M opens the map at, on your character (default 14; off: as the game does)")
        Print(C .. " openfollow    toggle M also following you (default on)")
        Print(C .. " taint         check that the map left the objective tracker's quest data clean")
        Print(C .. " debug         show how the map layers are stacked")
        if ns.RetailBench then Print(C .. " bench         what the map costs on this machine (it flies itself for about a minute and a half)") end
        if ns.RetailWhy then -- (1.4.0-beta2, retail: RetailWhy.lua)
            Print(C .. " why           what the map shows here and why (kept in the saved settings too)")
            Print(C .. " test <switch> nomask | noclip | noload | nofade | canvas | off - for this session only")
        end
        Print(C .. " reset")
        if ns.Options then ns.Options:Help() end -- (Options.lua: names, icons, button; 1.3.0: bubbles, imagery)
    end
end

-- (Azeroth Unrolled 1.0.0) what Options.lua and MapMenu.lua need of this file: the defaults (Options.lua adds its own rows:
-- placeNames, dungeonIcons, mapButton; 1.3.0: bubbles), the chat printer, the redraw, the command handler and its first slash word.
ns.DEFAULTS, ns.Print, ns.Refresh = DEFAULTS, Print, Refresh
ns.RunCommand = SlashCmdList[ns.SLASH] -- ((1.4.0-beta4) ns.COMMAND, its first slash word: OneCopy.lua)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("MAP_EXPLORATION_UPDATED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("GLOBAL_MOUSE_DOWN")
events:RegisterEvent("GLOBAL_MOUSE_UP")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "GLOBAL_MOUSE_DOWN" then
        if ready then OnGlobalMouseDown(arg1) end
    elseif event == "GLOBAL_MOUSE_UP" then
        if ready then OnGlobalMouseUp(arg1) end
    elseif event == "ADDON_LOADED" then
        if arg1 == ADDON then
            -- ((1.4.0-beta4) the saved table by the game: AzerothUnrolledDB, on retail EndlessMapDB - OneCopy.lua ns.SAVED)
            _G[ns.SAVED] = _G[ns.SAVED] or {}
            db = _G[ns.SAVED]
            -- (1.0.0) The city switch is ONE world zoom by default. What a test build before it saved (false: its default, never a choice;
            -- or a trial number of its tuning aid) gives way to the default once; later /unroll cityzoom choices are kept.
            if db.cityZoomRev ~= 310 then db.cityZoom, db.cityZoomRev = nil, 310 end
            -- (1.2.0) The same for the caves: every default is written into the saved settings below, so a changed default
            -- reaches nobody who ran the old one (the 1.2.0 betas left 20, then 52 - or a zoom picked while
            -- testing them). Each new cave default (1.2.0: 30) bumps this stamp: what was saved gives way to it once (with the
            -- zoom the add-on's caves button remembered); later /unroll cavezoom choices are kept.
            if db.caveZoomRev ~= 362 then db.caveZoom, db.caveZoomWas, db.caveZoomRev = nil, nil, 362 end
            for k, val in pairs(DEFAULTS) do
                if db[k] == nil then db[k] = val end
            end
            if db.cityZoom ~= false and type(db.cityZoom) ~= "number" then db.cityZoom = DEFAULTS.cityZoom end
            if db.caveZoom ~= false and type(db.caveZoom) ~= "number" then db.caveZoom = DEFAULTS.caveZoom end -- (1.2.0)
            -- (1.6.0, Pins.lua) the quest switch: a world zoom it takes, or off - anything else its default
            local PN = ns.Pins
            if PN and db.questZoom ~= false and not (type(db.questZoom) == "number" and db.questZoom >= PN.QUEST_G_MIN
                and db.questZoom <= PN.QUEST_G_MAX) then db.questZoom = DEFAULTS.questZoom end
            ns.db = db -- (ZoomReadout:Apply gives the renderer the saved switches at login)
        elseif arg1 == "Blizzard_WorldMap" and IsLoggedIn() then
            Setup()
        end
    elseif event == "PLAYER_LOGIN" then
        -- (1.3.1) Every copy of the add-on declares this one saved table. A copy that loaded after this one (and stood
        -- down: OneCopy.lua) had its saved file replace the global after our ADDON_LOADED; the game writes the global into
        -- every copy's file at logout, so it must be the table this copy uses (or what changes now would be lost).
        if db and _G[ns.SAVED] ~= db then _G[ns.SAVED] = db end
        Setup()
    elseif event == "MAP_EXPLORATION_UPDATED" then
        if ready then
            Render:MarkArtDirty()
            if state == "rest" or state == "hold" then
                restBusy = true
                driver:Show()
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ready and state == "hold" and WorldMapFrame:IsShown() then
            BeginSettle()
        end
    end
end)
