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
--   /denomap selftest  write what was measured to the saved variables, take two screenshots

local ADDON, ns = ...

local BASE = "Interface\\AddOns\\" .. ADDON .. "\\Maps\\"
local HD = ns.files                  -- [fileDataID] = true, from Manifest.lua
local last = { tiles = 0, overlays = 0, seen = 0 }

-- Returns 1 when the texture was pointed at its upscale.
local function swap(texture)
    local id = texture:GetTextureFileID()
    if id and HD[id] then
        texture:SetTexture(BASE .. id, nil, nil, "TRILINEAR")
        return 1
    end
    return 0
end

local function sweepTiles(canvas)
    local done, seen = 0, 0
    for layer in canvas.detailLayerPool:EnumerateActive() do
        for tile in layer.detailTilePool:EnumerateActive() do
            seen = seen + 1
            done = done + swap(tile)
        end
    end
    if seen > 0 then last.tiles, last.seen = done, seen end
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
    if taxi.InsetBg then swap(taxi.InsetBg) end
end

-- A map frame built on Blizzard's map canvas: the world map, the zone map, the flight map.
local attached = {}
local function attach(canvas)
    if not canvas or attached[canvas] or not canvas.detailLayerPool then return end
    attached[canvas] = true
    hooksecurefunc(canvas, "RefreshDetailLayers", sweepTiles)
    for pin in canvas:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
        hooksecurefunc(pin, "RefreshOverlays", sweepOverlays)
        sweepOverlays(pin)
    end
    for pin in canvas:EnumeratePinsByTemplate("MapHighlightPinTemplate") do
        hooksecurefunc(pin, "Refresh", sweepHighlight)
    end
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
    return { tiles = last.tiles, seen = last.seen, overlays = last.overlays }
end

SLASH_DENOMAP1 = "/denomap"
SlashCmdList.DENOMAP = function(msg)
    local word = strtrim(msg or ""):lower()
    if word == "minimap" then return ns.ToggleMinimap() end
    if word == "selftest" then return ns.SelfTest() end
    local count = 0
    for _ in pairs(HD) do count = count + 1 end
    print(string.format("|cffffcc66Deno Map 4K|r: %d textures in the pack. Last map drawn: %d of %d tiles and %d discovered areas in 4K.",
        count, last.tiles, last.seen, last.overlays))
    print("|cffffcc66Deno Map 4K|r: 4K minimap " .. ns.MinimapStatus() .. ". /denomap minimap switches it.")
end
