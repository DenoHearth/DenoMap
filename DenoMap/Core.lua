-- Deno Map 4K - the world map in four times the resolution.
--
-- Blizzard's map code sets every map tile, every discovered-area overlay, the zone
-- highlights and the flight maps by file id.
-- Maps\ holds a 4x upscale of each of those files under the same id; after Blizzard has
-- drawn a map, the textures that have an upscale are pointed at it. A texture without
-- one keeps Blizzard's own art, so a map this addon does not know can never go blank.
--
-- Nothing of Blizzard's is replaced: the map frames are only hooked.
--
--   /denomap           how many textures of the open map are in 4K, and what the minimap is doing
--   /denomap minimap   switch the 4K minimap on or off (Minimap.lua)
--   /denomap maps      switch the 4K maps on or off, to compare with the game's own art
--   /denomap selftest  write what was measured to the saved variables, take two screenshots

local ADDON, ns = ...

local BASE = "Interface\\AddOns\\" .. ADDON .. "\\Maps\\"
local HD = ns.files                  -- [fileDataID] = width of the game's own file, from Manifest.lua
local last = { tiles = 0, overlays = 0, seen = 0, missing = "", copy = 0 }

-- Three copies of every texture: 4x in Maps, 2x in Maps\h, 1x in Maps\q (tools/ladder.py).
-- The addon picks the copy that fits the size the map is drawn at and reads it with the LINEAR
-- filter. TRILINEAR, which the game uses for its own tiles, mixes two of the smaller copies:
-- measured in game, that came out soft at normal sizes. LINEAR on the 4x copy alone would
-- shimmer when the map is small, hence the three files.
local COPY = { "q\\", "h\\", "" }

local function hidden(value)
    return value == nil or (issecretvalue and issecretvalue(value))
end

-- 1, 2 or 3: the smallest copy that still has a texel for every screen pixel.
-- Map art on a canvas is laid out at one unit per pixel of the game's own file, so the screen
-- pixels per unit say it all. A picture that is stretched to a frame (the flight master's map)
-- is judged by its width on screen against the width of the game's file.
local function copyFor(texture, base, stretched)
    local scale = texture:GetEffectiveScale()
    local _, physical = GetPhysicalScreenSize()
    if hidden(scale) or hidden(physical) then return 3 end
    local perPixel = scale * physical / 768
    if stretched then
        local width = texture:GetWidth()
        if hidden(width) or width <= 0 then return 3 end
        perPixel = perPixel * width / HD[base]
    end
    if perPixel <= 1.02 then return 1 elseif perPixel <= 2.04 then return 2 end
    return 3
end

local function mapsOn()
    return not DenoMapDB or DenoMapDB.maps ~= false
end

-- Returns 1 when the texture shows a copy from the pack after this call. Otherwise 0 and the
-- file id it shows. A texture that was pointed at the pack no longer reports Blizzard's file
-- id, so what it was is kept on the texture itself.
local function swap(texture, stretched)
    local id = texture:GetTextureFileID()
    local base
    if id and HD[id] then
        base = id                                   -- Blizzard has just put its own art here
    elseif texture.denoMapShows and (id or 0) == texture.denoMapShows then
        base = texture.denoMapBase                  -- still ours from an earlier pass
    else
        texture.denoMapShows, texture.denoMapBase, texture.denoMapCopy = nil, nil, nil
        return 0, id
    end
    if not mapsOn() then
        if base ~= id then texture:SetTexture(base, nil, nil, "TRILINEAR") end
        texture.denoMapShows, texture.denoMapBase, texture.denoMapCopy = nil, nil, nil
        return 0, base
    end
    local copy = copyFor(texture, base, stretched)
    if base == id or copy ~= texture.denoMapCopy then
        texture:SetTexture(BASE .. COPY[copy] .. base, nil, nil, "LINEAR")
        texture.denoMapBase, texture.denoMapCopy = base, copy
        texture.denoMapShows = texture:GetTextureFileID() or 0
    end
    return 1, nil, copy
end

local function sweepTiles(canvas)
    local done, seen, missing, copyShown = 0, 0, {}, 0
    for layer in canvas.detailLayerPool:EnumerateActive() do
        for tile in layer.detailTilePool:EnumerateActive() do
            seen = seen + 1
            local shown, unknown, copy = swap(tile)
            done = done + shown
            if copy then copyShown = copy end
            if shown == 0 and #missing < 6 then missing[#missing + 1] = tostring(unknown) end
        end
    end
    if seen > 0 then
        local changed = done ~= last.tiles or seen ~= last.seen or copyShown ~= last.copy
        last.tiles, last.seen, last.missing, last.copy = done, seen, table.concat(missing, " "), copyShown
        -- local test server only: the probe's live line to the watcher
        local eyes = _G.ForeverProbeEyes
        if eyes and changed then
            eyes("map", string.format("%d of %d tiles from the pack, copy %s%s", done, seen,
                ({ [0] = "none", "1x", "2x", "4x" })[copyShown],
                #missing > 0 and (", no upscale for file " .. last.missing) or ""))
        end
    end
end

local function sweepOverlays(pin)
    if not pin.overlayTexturePool then return end
    local done = 0
    for texture in pin.overlayTexturePool:EnumerateActive() do
        done = done + swap(texture)
    end
    last.overlays = done
end

-- The glow over a zone when the mouse is on it, on a continent map.
local function sweepHighlight(pin)
    if pin.HighlightTexture then swap(pin.HighlightTexture) end
    if pin.PulseTexture then swap(pin.PulseTexture) end
end

-- The flight master's map (the classic window: the game puts one picture on InsetBg).
local function sweepTaxi(taxi)
    if taxi.InsetBg then swap(taxi.InsetBg, true) end
end

-- A map frame built on Blizzard's map canvas: the world map, the zone map, the flight map.
local attached = {}

function ns.SweepCanvas(canvas)
    local pins = attached[canvas]
    if not pins then return end
    sweepTiles(canvas)
    for _, pin in ipairs(pins) do sweepOverlays(pin) end
end

-- /denomap maps: the game's own map art back, or the pack again. For looking at the difference.
function ns.ToggleMaps()
    DenoMapDB.maps = not mapsOn()
    for canvas in pairs(attached) do
        if canvas:IsShown() then ns.SweepCanvas(canvas) end
    end
    print("|cffffcc66Deno Map 4K|r: 4K maps " .. (DenoMapDB.maps and "on" or "off") .. ".")
end
local function attach(canvas)
    if not canvas or attached[canvas] or not canvas.detailLayerPool then return end
    local pins = {}
    attached[canvas] = pins
    hooksecurefunc(canvas, "RefreshDetailLayers", sweepTiles)
    for pin in canvas:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
        hooksecurefunc(pin, "RefreshOverlays", sweepOverlays)
        pins[#pins + 1] = pin
        sweepOverlays(pin)
    end
    for pin in canvas:EnumeratePinsByTemplate("MapHighlightPinTemplate") do
        hooksecurefunc(pin, "Refresh", sweepHighlight)
    end
    -- zooming and resizing change how large the art is drawn: pick the fitting copy again
    hooksecurefunc(canvas, "OnCanvasScaleChanged", ns.SweepCanvas)
    sweepTiles(canvas)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then
        ns.AttachZoom(WorldMapFrame)
        attach(WorldMapFrame)
        attach(BattlefieldMapFrame)
        attach(FlightMapFrame)
        if TaxiFrame then TaxiFrame:HookScript("OnShow", sweepTaxi) end
    elseif name == "Blizzard_BattlefieldMap" or name == "Blizzard_WorldMap" or name == "Blizzard_FlightMap" then
        attach(WorldMapFrame)
        attach(BattlefieldMapFrame)
        attach(FlightMapFrame)
    end
end)

function ns.MapReport()
    return { tiles = last.tiles, seen = last.seen, overlays = last.overlays, missing = last.missing }
end

SLASH_DENOMAP1 = "/denomap"
SlashCmdList.DENOMAP = function(msg)
    local eyes = _G.ForeverProbeEyes
    local word = strtrim(msg or ""):lower()
    if eyes and word == "" and ns.MinimapSlotReport then
        for _, line in ipairs(ns.MinimapSlotReport()) do eyes("minimap", line) end
    end
    if eyes then
        -- for the watcher on the local test server only: set the minimap zoom, say the state
        local zoom = tonumber(word:match("^zoom (%d+)$"))
        if zoom then Minimap:SetZoom(math.min(zoom, Minimap:GetZoomLevels() - 1)) end
        if word == "minimap" then ns.ToggleMinimap() end
        if word == "maps" then ns.ToggleMaps() end
        C_Timer.After(0.6, function()
            eyes("state", string.format("minimap %s, zoom %d of %d, maps %s", ns.MinimapStatus(), Minimap:GetZoom(),
                Minimap:GetZoomLevels() - 1, (not DenoMapDB or DenoMapDB.maps ~= false) and "on" or "off"))
        end)
        if word == "sweep" then
            -- every minimap zoom level, with our tiles and with the game's own: the addon steps
            -- through them by itself and tells the watcher when each picture is ready
            local steps, at, was = {}, 0, DenoMapDB.minimap
            for level = 0, Minimap:GetZoomLevels() - 1 do
                steps[#steps + 1] = { level, true }
                steps[#steps + 1] = { level, false }
            end
            local function nextStep()
                at = at + 1
                local step = steps[at]
                if not step then
                    DenoMapDB.minimap = was
                    return eyes("shot", "done")
                end
                Minimap:SetZoom(step[1])
                DenoMapDB.minimap = step[2]
                C_Timer.After(1.8, function()
                    eyes("shot", string.format("zoom%d %s (%s)", step[1], step[2] and "ours" or "game", ns.MinimapStatus()))
                    C_Timer.After(3.4, nextStep)   -- the message can wait in the strip queue: hold the state
                end)
            end
            nextStep()
            return
        end
        if word == "mapsweep" or word == "mapsweep max" then
            -- every zoom level of the world map, with the pack and with the game's own art
            if not WorldMapFrame:IsShown() then ToggleWorldMap() end
            if word == "mapsweep max" then WorldMapFrame:Maximize() else WorldMapFrame:Minimize() end
            local container = WorldMapFrame.ScrollContainer
            local steps, at, was = {}, 0, DenoMapDB.maps
            for index, level in ipairs(container.zoomLevels) do
                steps[#steps + 1] = { index, level.scale, true }
                steps[#steps + 1] = { index, level.scale, false }
            end
            local function box()
                local left, bottom, width, height = container:GetRect()
                local _, physical = GetPhysicalScreenSize()
                local k = container:GetEffectiveScale() * physical / 768
                return string.format("%d,%d,%d,%d", left * k, physical - (bottom + height) * k,
                    (left + width) * k, physical - bottom * k)
            end
            local function nextStep()
                at = at + 1
                local step = steps[at]
                if not step then
                    DenoMapDB.maps = was
                    ns.SweepCanvas(WorldMapFrame)
                    return eyes("shot", "done")
                end
                DenoMapDB.maps = step[3]
                container:InstantPanAndZoom(step[2], 0.5, 0.5)
                ns.SweepCanvas(WorldMapFrame)
                C_Timer.After(1.8, function()
                    local _, physical = GetPhysicalScreenSize()
                    eyes("shot", string.format("zoom%d %s (copy %s, %.2f px per unit, %d of %d tiles) box %s", step[1] - 1,
                        step[3] and "ours" or "game", tostring(last.copy),
                        container:GetCanvasScale() * container:GetEffectiveScale() * physical / 768, last.tiles, last.seen, box()))
                    C_Timer.After(3.4, nextStep)
                end)
            end
            nextStep()
            return
        end
        if zoom or word == "minimap" or word == "maps" then return end
    end
    if word == "minimap" then return ns.ToggleMinimap() end
    if word == "maps" then return ns.ToggleMaps() end
    if word == "selftest" then return ns.SelfTest() end
    local count = 0
    for _ in pairs(HD) do count = count + 1 end
    print(string.format("|cffffcc66Deno Map 4K|r: %d textures in the pack. Last map drawn: %d of %d tiles and %d discovered areas from the pack%s.",
        count, last.tiles, last.seen, last.overlays,
        mapsOn() and (", copy " .. (({ [0] = "none", "1x", "2x", "4x" })[last.copy])) or " (4K maps are switched off)"))
    print("|cffffcc66Deno Map 4K|r: /denomap maps switches the 4K maps, to compare with the game's own.")
    print("|cffffcc66Deno Map 4K|r: 4K minimap " .. ns.MinimapStatus() .. ". /denomap minimap switches it.")
end
