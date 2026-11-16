-- Deno Map 4K with OpenMap (his ask, 2026-11-07: "make our 4k addon work with the seamless addon
-- ... if he make improvements to the addon, I want our addon to automatically be compatible").
--
-- OpenMap (CurseForge 1735937) stitches every zone into one map on the world map canvas. What it
-- draws there, found 2026-11-07 (OpenMap v0.7.5, Map/Stitch.lua):
--   * world and continent zoom: its own hand-cleaned art (Media/Textures/MapArt, file paths). Not
--     the game's files, so no 4K there.
--   * zone zoom: by default its "Baked" pictures (Media/Textures/MapZones, about 1x), which HIDE the
--     live zone layers until the view is past 1.2 screen px per baked px (Baked.FADE, ApplyDetail).
--   * the live zone layers: the game's own art by file id (zone tiles, explored areas, the reveal of
--     unexplored ones). These are what this file puts the 4K copies on.
--
-- 1. The swap. Every texture's SetTexture is post-hooked (the shared Texture metatable); when a file
--    this pack has in 4K lands on a texture under the world map canvas, the copy that fits its size
--    on screen goes on instead. Nothing of OpenMap's code is read or changed, so OpenMap may move,
--    rename or rebuild its frames in a new version and the swap still follows. The copy is picked
--    again on OpenMapAPI's "OpenMap_ViewChanged" (public, versioned API: major 1) and on the
--    canvas's own zoom.
-- 2. An earlier handover. OpenMap keeps its Baked pictures until the view is past 1.2 screen px
--    per baked px, r = scale / ns.MapZoneArt.px (Stitch.lua 1679, computed on every zoom step).
--    Turning Baked off altogether (1.8.0, colorMatch = -1) put every zone's live layers on screen
--    from far out, and the map lagged (his word, 2026-11-07). Now Baked stays on and, once OpenMap
--    has built its map (OpenMapAPI.ArtTopLevel() answers: S.Build runs Baked.Build at once, which is
--    the only other reader of px), px is divided by HANDOVER: its own pictures far out, where 4K
--    adds nothing, and the live (4K) layers from HANDOVER times less zoom than before. This is the
--    one use of OpenMap internals (_G.OpenMap = its namespace, Core.lua 11). Every access is
--    type-checked: if a future OpenMap renames it, nothing breaks, the 4K art just comes in at
--    OpenMap's own (deeper) handover again.
-- Blizzard's own map textures stay with Core.lua (it marks them denoMapCore).
local ADDON, ns = ...

local HD = ns.files
local tracked = setmetatable({}, { __mode = "k" })    -- texture -> the game's file id it was given
local pending = setmetatable({}, { __mode = "k" })    -- textures to (re)pick a copy for
local onCanvas = setmetatable({}, { __mode = "k" })   -- frame -> under the world map canvas or not
local busy = false                                    -- our own SetTexture is running
local hooked = false

-- What happened, for checking after a /reload (DenoMapDB.openmap): plain counts only.
local stats = { calls = 0, matched = 0, onCanvas = 0, applied = 0, copy1 = 0, copy2 = 0, copy3 = 0,
    errors = 0, shifted = false, bakedFound = false, passes = 0 }

local swapsThisFrame = 0                              -- for the slow-frame report below
local ourMs = 0                                       -- our own Lua time this frame, for the report
local scanList, scanAt, scanAll = {}, 1, false        -- a pass's pieces, checked a few hundred a frame
local SCAN_PER_FRAME = 250

local function Canvas()
    local map = _G.WorldMapFrame
    return map and map.ScrollContainer and map.ScrollContainer.Child
end

-- Whether a texture hangs (at any depth) under the world map canvas. Answers are kept per frame.
local function UnderCanvas(texture)
    local canvas = Canvas()
    if not canvas then return false end
    local frame = texture:GetParent()
    local walked = {}
    while frame do
        local known = onCanvas[frame]
        if known ~= nil then
            for _, f in ipairs(walked) do onCanvas[f] = known end
            return known
        end
        if frame == canvas then
            for _, f in ipairs(walked) do onCanvas[f] = true end
            return true
        end
        walked[#walked + 1] = frame
        frame = frame:GetParent()
    end
    for _, f in ipairs(walked) do onCanvas[f] = false end
    return false
end

local function hidden(value)
    return value == nil or (issecretvalue and issecretvalue(value))
end

-- 1, 2 or 3: the smallest copy with a texel for every screen pixel. OpenMap crops edge tiles with
-- texcoords, so the part of the file on screen is compared with the screen width, not the whole file.
-- OpenMap's own hand-cleaned world and continent art (Media/Textures/Forever/MapArt/<map>_<n>, the game's
-- art with the sea lettering taken out) has 4K copies in Maps/OpenMap, made by tools/openmap_art.py;
-- MapArtManifest.lua lists them. Found by the picture's name, so a picture OpenMap adds or renames
-- later simply stays its own. The name of a path OpenMap sets, or false: kept per path.
local artName = {}
local function ArtName(path)
    local known = artName[path]
    if known == nil then
        -- (OpenMap 0.8.x moved them into a folder per client: Media/Textures/Forever/MapArt)
        local name = path:match("[Oo]pen[Mm]ap[\\/][Mm]edia[\\/][Tt]extures[\\/][Mm]ap[Aa]rt[\\/](%d+_%d+)$")
            or path:match("[Oo]pen[Mm]ap[\\/][Mm]edia[\\/][Tt]extures[\\/][^\\/]+[\\/][Mm]ap[Aa]rt[\\/](%d+_%d+)$")
        known = (name and ns.openMapArt and ns.openMapArt[name]) and name or false
        artName[path] = known
    end
    return known
end

-- What a tracked texture was given (a game file id, or OpenMap's own path): the width of that file,
-- and the path of one of our copies of it.
local function Width(base)
    if type(base) == "number" then return HD[base] end
    return ns.openMapArt[ArtName(base)]
end
local function CopyPath(base, copy)
    if type(base) == "number" then return ns.MapBase .. ns.MapCopy[copy] .. base end
    return ns.MapBase .. "OpenMap\\" .. ns.MapCopy[copy] .. ArtName(base)
end

local physical
local function CopyFor(texture, base)
    local width, scale = texture:GetWidth(), texture:GetEffectiveScale()
    if not physical then physical = select(2, GetPhysicalScreenSize()) end
    if hidden(width) or hidden(scale) or hidden(physical) or width <= 0 then return 3 end
    local left, _, _, _, right = texture:GetTexCoord()
    local part = (not hidden(left) and not hidden(right) and right > left) and (right - left) or 1
    local perPixel = width * scale * physical / 768 / (Width(base) * part)
    -- (a step up only past the line, a step down only well below it: no flipping back and forth,
    -- and no file reloads, while the zoom glides across a line)
    local now = texture.denoMapOM
    local up1, up2 = 1.02, 2.04
    -- (zooming out keeps the sharper copy until it is clearly too big: the files carry their own
    -- smaller mip levels, so it looks no worse, and the map does not reload pieces as it glides)
    if now == 2 then up1 = 0.5 elseif now == 3 then up1, up2 = 0.5, 1.0 end
    if perPixel <= up1 then return 1 elseif perPixel <= up2 then return 2 end
    return 3
end

-- Puts the fitting copy (or, with the maps switched off, the game's own file) on one texture.
local function ApplyNow(texture)
    local base = tracked[texture]
    if not base or texture.denoMapCore then return end
    if not ns.MapsOn() then
        if texture.denoMapOM or texture.denoMapCleared then
            texture:SetTexture(base, nil, nil, "TRILINEAR")
            texture.denoMapOM, texture.denoMapCleared = nil, nil
        end
        return
    end
    local copy = CopyFor(texture, base)
    if copy ~= texture.denoMapOM then
        texture:SetTexture(CopyPath(base, copy), nil, nil, "LINEAR")
        texture.denoMapOM, texture.denoMapCleared = copy, nil
        stats.applied = stats.applied + 1
        swapsThisFrame = swapsThisFrame + 1
        stats["copy" .. copy] = stats["copy" .. copy] + 1
    end
end

local function Apply(texture)
    busy = true
    local ok = pcall(ApplyNow, texture)
    busy = false
    if not ok then stats.errors = stats.errors + 1 end
end

-- Every file put on a map piece is read and sent to the graphics card while the next frames are
-- drawn: many in one frame made a slow frame (seen: 7 frames with about 40 each, 2026-11-07). So at
-- most BUDGET map pieces get a file per frame, ours and OpenMap's own together (BUDGET grows a
-- little with a long wait, to BUDGET_MOST at the most, so the queue never lags far behind):
--  * pending: pieces to (re)pick a copy for; they show what they have meanwhile.
--  * deferred: pieces OpenMap gave a file this frame beyond the budget. Their file is taken off
--    again at once, before the game reads it, and they get our copy in a coming frame, first in
--    line. OpenMap fades each such piece in from nothing over 0.3 s (its LOAD_FADE), so it was not
--    to be seen yet anyway: the same picture arrives, only spread over frames.
local BUDGET, BUDGET_MOST = 8, 12
local deferred = setmetatable({}, { __mode = "k" })
local waitingN = 0
local worker = CreateFrame("Frame")
worker:Hide()
local function Room()
    return math.min(BUDGET_MOST, BUDGET + math.floor(waitingN / 16)) - swapsThisFrame
end
local Queue
local function Work(self)
    -- a pass after a zoom: SCAN_PER_FRAME of its pieces looked at per frame (a single loop over
    -- thousands of pieces was a 320 ms frame, 2026-11-07)
    local scanEnd = math.min(#scanList, scanAt + SCAN_PER_FRAME - 1)
    for i = scanAt, scanEnd do
        local texture = scanList[i]
        scanList[i] = nil
        if tracked[texture] and (scanAll or texture:IsVisible()) then Queue(texture) end
    end
    scanAt = scanEnd + 1
    local scanning = scanAt <= #scanList
    if not scanning then scanList, scanAt = {}, 1 end
    for _, list in ipairs({ deferred, pending }) do
        for texture in pairs(list) do
            if Room() <= 0 then return end
            list[texture] = nil
            waitingN = math.max(0, waitingN - 1)
            Apply(texture)
        end
    end
    if not scanning then self:Hide() end
end
worker:SetScript("OnUpdate", function(self)
    local t0 = debugprofilestop()
    Work(self)
    ourMs = ourMs + debugprofilestop() - t0
end)
function Queue(texture)
    if not pending[texture] then waitingN = waitingN + 1 end
    pending[texture] = true
    worker:Show()
end
local function Defer(texture)
    busy = true
    texture:SetTexture(nil)
    busy = false
    texture.denoMapOM, texture.denoMapCleared = nil, true
    if not deferred[texture] then waitingN = waitingN + 1 end
    deferred[texture] = true
    stats.deferred = (stats.deferred or 0) + 1
    worker:Show()
end

local function OnSetTexture(texture, file)
    if busy then return end
    -- Every texture in the game passes here, and some get secret file ids (aura and spell icons in
    -- combat): a secret may not even be used as a table key, so it is left alone before anything.
    if issecretvalue and issecretvalue(file) then return end
    stats.calls = stats.calls + 1
    local ours = (type(file) == "number" and HD[file]) or (type(file) == "string" and ArtName(file))
    if ours and not texture.denoMapCore then
        local t0 = debugprofilestop()
        stats.matched = stats.matched + 1
        if UnderCanvas(texture) then
            stats.onCanvas = stats.onCanvas + 1
            tracked[texture] = file
            texture.denoMapOM = nil            -- it shows the game's file now
            -- A tile OpenMap fills as it scrolls into view (its lazy loader) already has its size:
            -- swap at once, before the frame is drawn, so only our copy is ever loaded, not the
            -- game's file first and ours a frame later (two loads per tile made dragging stutter).
            -- A new tile is sized by OpenMap right after this call: that one waits a frame.
            local width = texture:GetWidth()
            if hidden(width) or width <= 0 then
                Queue(texture)
            elseif Room() > 0 then
                Apply(texture)
                stats.direct = (stats.direct or 0) + 1
            else
                Defer(texture)
            end
            ourMs = ourMs + debugprofilestop() - t0
            return
        end
    end
    if tracked[texture] then
        tracked[texture], texture.denoMapOM = nil, nil   -- given other art
        if pending[texture] or deferred[texture] then waitingN = math.max(0, waitingN - 1) end
        pending[texture], deferred[texture] = nil, nil
    end
end

-- The tracked textures in view, to the queue (a zoom); all of them with the maps switched.
function ns.OpenMapPass(all)
    stats.passes = stats.passes + 1
    local list = {}
    for texture in pairs(tracked) do list[#list + 1] = texture end   -- (a quick list; looked at later)
    scanList, scanAt, scanAll = list, 1, all and true or false
    worker:Show()
end

-- A zoom is a glide of many small steps: the pieces are checked once, when it has settled
-- (SETTLE seconds without a change), not at every step. A drag (no zoom change) checks nothing:
-- pieces that scroll into view are handled as OpenMap loads them.
local SETTLE = 0.3
local lastZoom, changedAt, waiting = nil, 0, false
local function Settled()
    if GetTime() - changedAt < SETTLE then
        C_Timer.After(SETTLE, Settled)
        return
    end
    waiting = false
    ns.OpenMapPass()
end
local function ZoomChanged()
    changedAt = GetTime()
    if not waiting then
        waiting = true
        C_Timer.After(SETTLE, Settled)
    end
end
local function OnView(_, _, _, zoom)
    if type(zoom) == "number" and lastZoom and math.abs(zoom - lastZoom) < lastZoom * 0.03 then return end
    lastZoom = zoom
    ZoomChanged()
end

-- For the report: frames slower than 50 ms while the world map is open, and how many of our
-- swaps happened in those frames (none: the stutter is OpenMap's or the game's own).
local mapOpenAt
local meter = CreateFrame("Frame")
meter:SetScript("OnUpdate", function(_, elapsed)
    local lastOurMs = ourMs
    ourMs = 0
    local map = _G.WorldMapFrame
    if map and map:IsVisible() then
        stats.mapFrames = (stats.mapFrames or 0) + 1
        if not mapOpenAt then mapOpenAt = GetTime() end
        if elapsed > 0.05 then
            stats.slowFrames = (stats.slowFrames or 0) + 1
            -- the last 15 slow frames: ms, our swaps in it, our queue, seconds since the map opened
            -- and since the zoom last changed
            local log = stats.slowLog or {}
            stats.slowLog = log
            if #log >= 15 then table.remove(log, 1) end
            log[#log + 1] = string.format("%dms ours=%.1fms swaps=%d waiting=%d open=%.1fs zoom=%.1fs",
                math.floor(elapsed * 1000), lastOurMs, swapsThisFrame, waitingN, GetTime() - mapOpenAt,
                GetTime() - (changedAt or 0))
            if swapsThisFrame > 0 then
                stats.slowWithSwaps = (stats.slowWithSwaps or 0) + 1
                stats.swapsInSlow = (stats.swapsInSlow or 0) + swapsThisFrame
            end
            if elapsed > (stats.worstFrame or 0) then stats.worstFrame = math.floor(elapsed * 1000) / 1000 end
        end
    else
        mapOpenAt = nil
    end
    swapsThisFrame = 0
end)

-- The earlier handover (see the top of this file). Once per session, after OpenMap built its map.
local HANDOVER = 2
local function Handover()
    if stats.shifted then return end
    local om, api = _G.OpenMap, _G.OpenMapAPI
    local art = type(om) == "table" and rawget(om, "MapZoneArt")
    stats.bakedFound = type(art) == "table" and type(art.px) == "number"
    if not stats.bakedFound then return end
    if art.colorMatch == -1 then art.colorMatch = 1 end      -- (1.8.0 turned Baked off: back on)
    if type(api) == "table" and type(api.ArtTopLevel) == "function" and api.ArtTopLevel() then
        art.px = art.px / HANDOVER
        stats.shifted = true
    end
end

-- OpenMap's blur at its closest zoom (Close.lua soften: four shifted see-through copies of the zone
-- art laid over it, S.SetBlur) is there to hide the game's art stretched past its pixels. Over our
-- 4K copies nothing is stretched, and the blur smeared them. Since OpenMap 0.8.1 the blur rests
-- while the map moves and comes back a moment after it stops, so the map looked 4K while dragged
-- and went soft when let go (his report, 2026-11-08). With the 4K maps on, the blur's amount is
-- held at 0; OpenMap's paper grain (also "soften") is left as it is. One more use of OpenMap
-- internals (ns.MapStitch, Stitch.lua): skipped silently if it is renamed.
local function BlurOff()
    if stats.blurOff ~= nil then return end
    local om = _G.OpenMap
    local S = type(om) == "table" and rawget(om, "MapStitch")
    local original = type(S) == "table" and rawget(S, "SetBlur")
    stats.blurOff = type(original) == "function"
    if not stats.blurOff then return end
    S.SetBlur = function(amount, ...)
        if DenoMapDB and DenoMapDB.maps ~= false then amount = 0 end
        return original(amount, ...)
    end
end

local owner = {}
local function Hook()
    if hooked then return end
    hooked = true
    stats.hooked = true
    local sample = UIParent:CreateTexture()
    hooksecurefunc(getmetatable(sample).__index, "SetTexture", OnSetTexture)
    sample:Hide()
    Handover()
    BlurOff()
    local api = _G.OpenMapAPI
    if type(api) == "table" and api.major == 1 and type(api.RegisterCallback) == "function" then
        api.RegisterCallback(owner, "OpenMap_ViewChanged", function(...) Handover() OnView(...) end)
        api.RegisterCallback(owner, "OpenMap_StitchedChanged", Handover)
        stats.api = api.version
    end
    local map = _G.WorldMapFrame
    if map and map.OnCanvasScaleChanged then
        hooksecurefunc(map, "OnCanvasScaleChanged", function() Handover() ZoomChanged() end)
    end
end

-- Only with OpenMap in the game: without it Core.lua does all of the map. OpenMap loads before
-- this file (## OptionalDeps), so the hook is in before its map is first built.
if C_AddOns.IsAddOnLoaded("OpenMap") then Hook() end
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_LOGOUT")
loader:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if C_AddOns.IsAddOnLoaded("OpenMap") then Hook() end
    elseif DenoMapDB then
        stats.openmapVersion = C_AddOns.GetAddOnMetadata("OpenMap", "Version")
        local om = _G.OpenMap
        local ms = type(om) == "table" and rawget(om, "loadMs")
        if type(ms) == "table" then
            stats.openmapBuildMs = type(ms.build) == "number" and math.floor(ms.build) or nil
            stats.openmapBuiltShown = ms.builtShown
        end
        DenoMapDB.openmap = stats
    end
end)
