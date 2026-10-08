-- Deno Map 4K - the world map in four times the resolution.
--
-- Blizzard's map code sets every map tile and every discovered-area overlay by file id.
-- Maps\ holds a 4x upscale of each of those files under the same id; after Blizzard has
-- drawn a map, the textures that have an upscale are pointed at it. A texture without
-- one keeps Blizzard's own art, so a map this addon does not know can never go blank.
--
-- Nothing of Blizzard's is replaced: the map frames are only hooked.
--
--   /denomap   how many textures of the open map are in 4K

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

-- A map frame built on Blizzard's map canvas: the world map, the zone map.
local attached = {}
local function attach(canvas)
    if not canvas or attached[canvas] or not canvas.detailLayerPool then return end
    attached[canvas] = true
    hooksecurefunc(canvas, "RefreshDetailLayers", sweepTiles)
    for pin in canvas:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
        hooksecurefunc(pin, "RefreshOverlays", sweepOverlays)
        sweepOverlays(pin)
    end
    sweepTiles(canvas)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then
        attach(WorldMapFrame)
        attach(BattlefieldMapFrame)
    elseif name == "Blizzard_BattlefieldMap" or name == "Blizzard_WorldMap" then
        attach(WorldMapFrame)
        attach(BattlefieldMapFrame)
    end
end)

SLASH_DENOMAP1 = "/denomap"
SlashCmdList.DENOMAP = function()
    local count = 0
    for _ in pairs(HD) do count = count + 1 end
    print(string.format("|cffffcc66Deno Map 4K|r: %d textures in the pack. Last map drawn: %d of %d tiles and %d discovered areas in 4K.",
        count, last.tiles, last.seen, last.overlays))
end
