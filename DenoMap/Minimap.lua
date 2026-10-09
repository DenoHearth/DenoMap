-- Deno Map 4K - the minimap in four times the resolution.
--
-- The game draws the minimap terrain itself, from tiles an addon cannot replace. But it
-- can be told not to draw the terrain (C_Minimap.SetDrawGroundTextures), while it keeps
-- drawing the dots, arrows and tracking marks. Blizzard's own "hybrid minimap" works
-- this way. This file does the same: the terrain is switched off and a frame under the
-- minimap shows 4x upscaled copies of the same tiles, moved (and, with the rotating
-- minimap, turned) to follow the player.
--
-- It stands down, and the game's own terrain comes back, whenever it cannot be sure it
-- is right: indoors (the game shows floor plans there that an addon cannot place), where
-- the game gives no position (dungeons), on a tile the pack does not have, and while
-- Blizzard's hybrid minimap is up.
--
--   /denomap minimap   switch the 4K minimap on or off

local ADDON, ns = ...

local TILE_YARDS = 1600 / 3          -- one terrain tile; tile (32, 32) starts at the world origin
local BASE = "Interface\\AddOns\\" .. ADDON .. "\\Minimap\\"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local have = ns.minimapTiles or {}   -- [world map id] = { ["column_row"] = true }, from Minimap\<id>\Tiles.lua

local frame, slots
local active = false

-- The measured link between a zone map and the world, redone on every zone change and
-- never assumed: where the map's corner is, and which way east and south run, in the
-- numbers UnitPosition and the map conversion use.
local cal = {}                       -- map, world, originA/B, eastA/B, southA/B (per map unit), unitEastA/B, unitSouthA/B
local shownColumn, shownRow, shownWorld
local lastA, lastB, lastRadius, lastWidth, lastFacing
local turned = false
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

local function mapPosition(map)
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if hidden(pos) then return end
    local x, y = pos:GetXY()
    if hidden(x) or hidden(y) then return end
    return x, y
end

local function calibrate()
    cal.world = nil
    local map = C_Map.GetBestMapForUnit("player")
    if hidden(map) then return end
    cal.map = map
    local c0, oa, ob = worldPoint(map, 0, 0)
    local c1, ea, eb = worldPoint(map, 1, 0)
    local c2, sa, sb = worldPoint(map, 0, 1)
    if not c0 or c1 ~= c0 or c2 ~= c0 or not have[c0] then return end
    ea, eb, sa, sb = ea - oa, eb - ob, sa - oa, sb - ob
    local el, sl = math.sqrt(ea * ea + eb * eb), math.sqrt(sa * sa + sb * sb)
    if el <= 0 or sl <= 0 then return end
    -- east and south have to be at right angles, or this is not a plain zone map
    if math.abs(ea * sa + eb * sb) / (el * sl) > 0.001 then return end
    -- where UnitPosition answers, it has to name the same spot as the map does
    local a, b, _, unitWorld = UnitPosition("player")
    if not hidden(a) and not hidden(b) and not hidden(unitWorld) then
        local px, py = mapPosition(map)
        if unitWorld ~= c0 or not px then return end
        if math.abs(oa + px * ea + py * sa - a) > 2 or math.abs(ob + px * eb + py * sb - b) > 2 then return end
    end
    cal.originA, cal.originB = oa, ob
    cal.eastA, cal.eastB, cal.southA, cal.southB = ea, eb, sa, sb
    cal.unitEastA, cal.unitEastB, cal.unitSouthA, cal.unitSouthB = ea / el, eb / el, sa / sl, sb / sl
    cal.world = c0
end

-- The player's spot in world numbers: straight from the game in the open world, through
-- the zone map where the game hides it (battlegrounds).
local function position()
    local a, b, _, world = UnitPosition("player")
    if not hidden(a) and not hidden(b) and not hidden(world) then
        if world ~= cal.world then return end
        return a, b
    end
    local px, py = mapPosition(cal.map)
    if not px then return end
    return cal.originA + px * cal.eastA + py * cal.southA, cal.originB + px * cal.eastB + py * cal.southB
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
    if HybridMinimap and HybridMinimap:IsShown() then return false end
    local map = C_Map.GetBestMapForUnit("player")
    if not cal.world or map ~= cal.map then calibrate() end
    return cal.world ~= nil
end

-- With the rotating minimap the way the player faces points up; otherwise north does.
local function heading()
    if not C_CVar.GetCVarBool("rotateMinimap") then return 0 end
    if C_Minimap.IsRotateMinimapIgnored and C_Minimap.IsRotateMinimapIgnored() then return 0 end
    return GetPlayerFacing()
end

local function update()
    local a, b = position()
    if not a then return deactivate() end
    local radius = C_Minimap.GetViewRadius()
    local width = Minimap:GetWidth()
    local facing = heading()
    if hidden(radius) or hidden(facing) or radius <= 0 or width <= 0 then return deactivate() end
    if a == lastA and b == lastB and radius == lastRadius and width == lastWidth and facing == lastFacing and active then return end
    lastA, lastB, lastRadius, lastWidth, lastFacing = a, b, radius, width, facing

    local world = cal.world
    local column = 32 + (a * cal.unitEastA + b * cal.unitEastB) / TILE_YARDS
    local row = 32 + (a * cal.unitSouthA + b * cal.unitSouthB) / TILE_YARDS
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
    local sin, cos = math.sin(facing), math.cos(facing)
    local i = 0
    for dr = -1, 1 do
        for dc = -1, 1 do
            i = i + 1
            local tile = slots[i]
            -- the tile's middle, east and north of the player, in screen units
            local east, north = (dc + 0.5 - u) * size, -(dr + 0.5 - v) * size
            tile:SetSize(size, size)
            tile:SetPoint("CENTER", frame, "CENTER", east * cos + north * sin, north * cos - east * sin)
            if facing ~= 0 or turned then tile:SetRotation(-facing) end
        end
    end
    turned = facing ~= 0
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
        cal.world = nil                   -- measure again in the new place
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
    print("|cffffcc66Deno Map 4K|r: 4K minimap " .. (DenoMapDB.minimap and "on" or "off") .. ".")
end

-- What was measured, for the self test: plain numbers only.
function ns.MinimapReport()
    local a, b
    if cal.world then a, b = position() end
    return {
        status = ns.MinimapStatus(), map = cal.map, world = cal.world,
        eastA = cal.unitEastA, eastB = cal.unitEastB, southA = cal.unitSouthA, southB = cal.unitSouthB,
        a = a, b = b, column = shownColumn, row = shownRow,
        radius = lastRadius, width = lastWidth, facing = lastFacing,
        indoors = IsIndoors() and true or false,
        rotate = C_CVar.GetCVarBool("rotateMinimap") and true or false,
        groundDrawnByGame = C_Minimap.GetDrawGroundTextures() and true or false,
    }
end

function ns.MinimapStatus()
    if not DenoMapDB.minimap then return "off" end
    if active then return "on, drawing" end
    return "on, standing by (the game's own terrain is showing here)"
end
