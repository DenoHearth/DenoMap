-- Deno Map 4K - a sharper minimap.
--
-- The game draws the minimap terrain itself, from tiles an addon cannot replace. But it
-- can be told not to draw the terrain (C_Minimap.SetDrawGroundTextures), while it keeps
-- drawing the dots, arrows and tracking marks. Blizzard's own "hybrid minimap" works
-- this way. This file does the same: the terrain is switched off and a frame under the
-- minimap shows upscaled copies of the same tiles, moved to follow the player.
--
-- It stands down, and the game's own terrain comes back, whenever it cannot be sure it
-- is right: indoors, in an instance, with the rotating minimap on, on a tile the pack
-- does not have, while Blizzard's hybrid minimap is up, or when the position is hidden.
--
--   /denomap minimap   switch the sharper minimap on or off

local ADDON, ns = ...

local TILE_YARDS = 1600 / 3          -- one terrain tile; tile (32, 32) starts at the world origin
local BASE = "Interface\\AddOns\\" .. ADDON .. "\\Minimap\\"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local have = ns.minimapTiles         -- [world map id] = { ["column_row"] = true }

local frame, slots
local active = false
-- How the numbers of UnitPosition relate to east and south on this world map. Measured
-- from the game's own map conversion on every zone change, never assumed.
local worldID, eastA, eastB, southA, southB
local shownColumn, shownRow, shownWorld
local lastA, lastB, lastRadius, lastWidth
local sinceCheck = 0

local function hidden(value)
    return value == nil or (issecretvalue and issecretvalue(value))
end

local function worldPoint(map, x, y)
    local continent, vector = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x, y))
    if hidden(continent) or hidden(vector) then return end
    local a, b = vector:GetXY()
    if hidden(a) or hidden(b) then return end
    return continent, a, b
end

local function calibrate()
    worldID = nil
    local map = C_Map.GetBestMapForUnit("player")
    if hidden(map) then return end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if hidden(pos) then return end
    local px, py = pos:GetXY()
    if hidden(px) or hidden(py) then return end
    local continent, wx, wy = worldPoint(map, px, py)
    local a, b, _, unitWorld = UnitPosition("player")
    if hidden(a) or hidden(b) or hidden(unitWorld) or not continent or unitWorld ~= continent then return end
    if not have[continent] then return end
    -- the map conversion and UnitPosition must name the same spot, in the same order
    if math.abs(a - wx) > 1 or math.abs(b - wy) > 1 then return end
    local c0, ox, oy = worldPoint(map, 0, 0)
    local c1, ex, ey = worldPoint(map, 1, 0)
    local c2, sx, sy = worldPoint(map, 0, 1)
    if not c0 or not c1 or not c2 then return end
    ex, ey, sx, sy = ex - ox, ey - oy, sx - ox, sy - oy
    local el, sl = math.sqrt(ex * ex + ey * ey), math.sqrt(sx * sx + sy * sy)
    if el <= 0 or sl <= 0 then return end
    eastA, eastB, southA, southB = ex / el, ey / el, sx / sl, sy / sl
    worldID = continent
end

local function build()
    frame = CreateFrame("Frame", "DenoMapMinimap", Minimap)
    frame:SetAllPoints(Minimap)
    frame:SetFrameStrata("BACKGROUND")
    frame:SetFrameLevel(100)
    frame:SetClipsChildren(true)
    frame:EnableMouse(false)
    frame:Hide()

    local mask = frame:CreateMaskTexture()
    mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", 3, -3)
    mask:SetPoint("BOTTOMRIGHT", -3, 3)

    local back = frame:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0, 0, 0, 1)
    back:AddMaskTexture(mask)

    slots = {}
    for i = 1, 9 do
        local tile = frame:CreateTexture(nil, "ARTWORK")
        tile:SetSnapToPixelGrid(false)
        tile:SetTexelSnappingBias(0)
        tile:AddMaskTexture(mask)
        tile:Hide()
        slots[i] = tile
    end
end

local function deactivate()
    if not active then return end
    active = false
    C_Minimap.SetDrawGroundTextures(true)
    frame:Hide()
    shownColumn, shownRow, shownWorld = nil, nil, nil
    lastA = nil
end

local function activate()
    if active then return end
    active = true
    C_Minimap.SetDrawGroundTextures(false)
    frame:Show()
end

-- Everything that has to hold before the game's terrain may be switched off.
local function allowed()
    if not DenoMapDB.minimap then return false end
    if not Minimap:IsVisible() then return false end
    if IsIndoors() then return false end
    if C_CVar.GetCVarBool("rotateMinimap") then return false end
    if HybridMinimap and HybridMinimap:IsShown() then return false end
    if not worldID then calibrate() end
    return worldID ~= nil
end

local function update()
    local a, b, _, world = UnitPosition("player")
    if hidden(a) or hidden(b) or hidden(world) then return deactivate() end
    if world ~= worldID then
        worldID = nil
        return deactivate()
    end
    local radius = C_Minimap.GetViewRadius()
    local width = Minimap:GetWidth()
    if hidden(radius) or radius <= 0 or width <= 0 then return deactivate() end
    if a == lastA and b == lastB and radius == lastRadius and width == lastWidth and active then return end
    lastA, lastB, lastRadius, lastWidth = a, b, radius, width

    local column = 32 + (a * eastA + b * eastB) / TILE_YARDS
    local row = 32 + (a * southA + b * southB) / TILE_YARDS
    local c, r = math.floor(column), math.floor(row)
    local set = have[world]
    if not set[c .. "_" .. r] then return deactivate() end

    if c ~= shownColumn or r ~= shownRow or world ~= shownWorld then
        shownColumn, shownRow, shownWorld = c, r, world
        local i = 0
        for dr = -1, 1 do
            for dc = -1, 1 do
                i = i + 1
                local key = (c + dc) .. "_" .. (r + dr)
                if set[key] then
                    slots[i]:SetTexture(BASE .. world .. "\\" .. key, nil, nil, "TRILINEAR")
                    slots[i]:Show()
                else
                    slots[i]:Hide()
                end
            end
        end
    end

    local size = TILE_YARDS * (width / 2) / radius
    local u, v = column - c, row - r
    local i = 0
    for dr = -1, 1 do
        for dc = -1, 1 do
            i = i + 1
            local tile = slots[i]
            tile:SetSize(size, size)
            tile:SetPoint("CENTER", frame, "CENTER", (dc + 0.5 - u) * size, -(dr + 0.5 - v) * size)
        end
    end
    activate()
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_LEAVING_WORLD")
driver:RegisterEvent("ZONE_CHANGED_NEW_AREA")
driver:RegisterEvent("ZONE_CHANGED_INDOORS")
driver:RegisterEvent("ZONE_CHANGED")
driver:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON then return end
        DenoMapDB = DenoMapDB or {}
        if DenoMapDB.minimap == nil then DenoMapDB.minimap = true end
    elseif event == "PLAYER_LEAVING_WORLD" then
        if frame then deactivate() end
        self:SetScript("OnUpdate", nil)
    else
        if not frame then build() end
        worldID = nil                     -- measure again in the new place
        sinceCheck = 1
        self:SetScript("OnUpdate", self.OnUpdate)
    end
end)

-- The conditions are looked at four times a second; the tiles follow the player every frame.
local ok = false
function driver:OnUpdate(elapsed)
    sinceCheck = sinceCheck + elapsed
    if sinceCheck >= 0.25 then
        sinceCheck = 0
        ok = allowed()
        if not ok then deactivate() end
    end
    if ok then update() end
end

function ns.ToggleMinimap()
    DenoMapDB.minimap = not DenoMapDB.minimap
    sinceCheck = 1
    print("|cffffcc66Deno Map 4K|r: sharper minimap " .. (DenoMapDB.minimap and "on" or "off") .. ".")
end

function ns.MinimapStatus()
    if not DenoMapDB.minimap then return "off" end
    if active then return "on, drawing" end
    return "on, standing by (the game's own terrain is showing here)"
end
