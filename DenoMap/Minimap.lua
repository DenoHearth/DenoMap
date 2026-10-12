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

-- Three copies of every tile (tools/ladder.py): 512 px in q, 1024 px in h, 2048 px beside them.
-- The copy that fits the size a tile has on screen is shown, read with the LINEAR filter.
-- Measured in game 2026-10-10: the 2048 px copy alone with TRILINEAR had a quarter of the fine
-- detail of the game's own minimap at normal zoom, because that filter mixes in copies smaller
-- than the screen; with a fitting copy and LINEAR it has more than the game's.
local COPY = { "q\\", "h\\", "" }
local COPY_PIXELS = { 512, 1024 }
-- The game draws its minimap terrain darker than the tile files are, and darker at night than
-- by day. Measured in game on 2026-10-10 at 19 hours of the game clock (tools/tonecurve.py):
-- 0.77 of the file from 21:40 to 04:10, 0.88 from 05:20 to 20:35, a ramp in between.
-- The tiles are tinted the same, so the map keeps the game's own look at every hour.
local NIGHT, DAY = 0.772, 0.878
-- Water: the game paints terrain water onto its own minimap (the tile files have none, deep
-- water is nearly black in them), and that paint goes with the terrain. Since 1.5.0 the water
-- is painted into the 4K tiles themselves (tools/water.py), so nothing is drawn for it here.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local DAWN_FROM, DAWN_TO, DUSK_FROM, DUSK_TO = 4 * 60 + 10, 5 * 60 + 20, 20 * 60 + 35, 21 * 60 + 40
local shownTone

local frame, slots, mask, maskSquare
local active = false
local shownCopy

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

local function tone()
    local hours, minutes = GetGameTime()
    if hidden(hours) or hidden(minutes) then return DAY, 1 end
    local now = (ns.testHour or hours) * 60 + minutes       -- testHour: the watcher's "/denomap hour N" on the test server
    local light
    if now < 12 * 60 then
        light = (now - DAWN_FROM) / (DAWN_TO - DAWN_FROM)
    else
        light = 1 - (now - DUSK_FROM) / (DUSK_TO - DUSK_FROM)
    end
    light = math.min(1, math.max(0, light))
    return NIGHT + (DAY - NIGHT) * light, light
end

-- The tint has a colour, and it is the zone's: the game lights its minimap. Measured in game on
-- 2026-10-11 at twelve places at midday and four at night, per colour channel:
--   seen = file x (fixed part + share x direct light colour - share x ambient light colour)
-- of the zone at that hour, to within 0.024 on average (Elwynn by day 0.97 0.83 0.80, Winterspring
-- 0.76 0.92 0.96, Elwynn at night 0.80 0.78 1.0). The light colours come from the game's own light
-- tables (Lights.lua, tools/lights.py). Where a world has none, the grey of tone() above is used.
-- The numbers hold for these upscaled tiles, which are a little greener than the game's own.
--
-- That rule is a few percent off in most zones and far off in some (Dun Morogh came out 19 percent
-- too bright in red, Tanaris 16 percent too blue). Measured in game on 2026-10-12 at 64 places at
-- midday: inside one zone the error is the same everywhere, and nothing in the light tables
-- explains it. So a zone light can carry a measured correction (three more numbers in Lights.lua,
-- from tools/tintspots.json), blended the way the lights themselves are.
local TINT = { { 0.724, 0.254, 0.0 }, { 0.679, 0.255, 0.035 }, { 0.94, 0.219, 0.338 } }   -- red, green, blue: fixed, direct, ambient
-- Checked at night at nine places (2026-10-12): the rule with the corrections came out 2.5 percent
-- too bright in red and 2 in green; that much is taken off as the light goes.
local NIGHT_TRIM = { 0.975, 0.98, 1 }
-- In Stormwind and Orgrimmar the game does not draw terrain tiles at all: it shows its picture of
-- the city, and that one is not lit. Measured by day and at midnight, the same both times:
-- Stormwind 0.87 0.84 0.86 of the file, Orgrimmar 0.90 0.87 0.90, whatever the zone light does.
-- (Thunder Bluff and Darnassus are ordinary terrain and follow the zone.) By zone map id.
-- Stormwind's harbour is on the city map but is terrain like any other: west of 1130 yards
-- (the fourth number) the zone tint stays.
local CITY = { [1453] = { 0.867, 0.844, 0.862, 1130 }, [1454] = { 0.9, 0.87, 0.895 } }
local lights, suns = ns.minimapLights or {}, ns.minimapSun or {}
local atX, atY                      -- the player in world yards (north, west), set by update()

local function sunAt(set, time)
    local keys = suns[set]
    if not keys then return end
    local count = #keys / 7
    local last = count
    for i = 1, count do
        if keys[i * 7 - 6] <= time then last = i end
    end
    local nextKey = last % count + 1
    local from, to = keys[last * 7 - 6], keys[nextKey * 7 - 6]
    if to <= from then to = to + 2880 end
    local at = time >= from and time or time + 2880
    local part = to > from and (at - from) / (to - from) or 0
    local a, b = last * 7 - 6, nextKey * 7 - 6
    local out = {}
    for n = 1, 6 do out[n] = keys[a + n] + (keys[b + n] - keys[a + n]) * part end
    return out
end

local function tint()
    local city = CITY[cal.map]
    if city and not (city[4] and atY and atY > city[4]) then return city[1], city[2], city[3] end
    local grey, daylight = tone()
    local world = lights[cal.world]
    local hours, minutes = GetGameTime()
    if not world or not atX or hidden(hours) or hidden(minutes) then return grey, grey, grey end
    local time = ((ns.testHour or hours) * 60 + minutes) * 2
    local sum, weight = { 0, 0, 0, 0, 0, 0 }, 0
    local fix = { 0, 0, 0 }
    for i = 1, #world do
        local spot = world[i]
        local dx, dy = atX - spot[1], atY - spot[2]
        local far = math.sqrt(dx * dx + dy * dy)
        if far < spot[4] then
            local share = far <= spot[3] and 1 or (spot[4] - far) / (spot[4] - spot[3])
            local light = sunAt(spot[5], time)
            if light then
                for n = 1, 6 do sum[n] = sum[n] + light[n] * share end
                for n = 1, 3 do fix[n] = fix[n] + (spot[5 + n] or 1) * share end
                weight = weight + share
            end
        end
    end
    if weight >= 1 then
        for n = 1, 6 do sum[n] = sum[n] / weight end
        for n = 1, 3 do fix[n] = fix[n] / weight end
    else
        -- what the local lights leave room for is filled by the zone light the player stands
        -- in (an outline on the map), else by the light of the whole world
        local base, baseFix = world.base, world.baseFix
        local zones = world.zones
        if zones then
            for i = 1, #zones do
                local zone = zones[i]
                local inside, count = false, (#zone - 4) / 2
                for k = 1, count do
                    local x1, y1 = zone[3 + 2 * k], zone[4 + 2 * k]
                    local nextK = k % count + 1
                    local x2, y2 = zone[3 + 2 * nextK], zone[4 + 2 * nextK]
                    if (y1 > atY) ~= (y2 > atY) and atX < (x2 - x1) * (atY - y1) / (y2 - y1) + x1 then inside = not inside end
                end
                if inside then
                    base, baseFix = zone[1], { zone[2], zone[3], zone[4] }
                    break
                end
            end
        end
        local light = sunAt(base, time)
        if light then
            for n = 1, 6 do sum[n] = sum[n] + light[n] * (1 - weight) end
            for n = 1, 3 do fix[n] = fix[n] + (baseFix and baseFix[n] or 1) * (1 - weight) end
        elseif weight == 0 then
            return grey, grey, grey
        else
            for n = 1, 6 do sum[n] = sum[n] / weight end
            for n = 1, 3 do fix[n] = fix[n] / weight end
        end
    end
    local out = {}
    for n = 1, 3 do
        local rule = TINT[n]
        out[n] = math.min(1, math.min(1, rule[1] + rule[2] * sum[n] / 255 - rule[3] * sum[n + 3] / 255) * fix[n])
        out[n] = out[n] * (1 - (1 - daylight) * (1 - NIGHT_TRIM[n]))
    end
    return out[1], out[2], out[3]
end

local function build()
    frame = CreateFrame("Frame", "DenoMapTiles", Minimap)
    frame:SetAllPoints(Minimap)
    frame:SetFrameStrata("BACKGROUND")
    frame:SetFrameLevel(100)
    frame:SetClipsChildren(true)
    frame:EnableMouse(false)
    frame:Hide()

    mask = frame:CreateMaskTexture()

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
    shownColumn, shownRow, shownWorld, shownCopy = nil, nil, nil, nil
    lastA = nil
end

local function activate()
    if active then return end
    active = true
    C_Minimap.SetDrawGroundTextures(false)
    frame:Show()
end

-- The tiles are cut to the minimap's own outline: round as the game has it, or square where an
-- addon made the minimap square and says so the way addons do (GetMinimapShape).
local function outline()
    local shape = _G.GetMinimapShape
    local square = shape ~= nil and shape() == "SQUARE"
    if square == maskSquare then return end
    maskSquare = square
    mask:ClearAllPoints()
    if square then
        mask:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints()
    else
        mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetPoint("TOPLEFT", 3, -3)
        mask:SetPoint("BOTTOMRIGHT", -3, 3)
    end
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
    atX, atY = (32 - row) * TILE_YARDS, (32 - column) * TILE_YARDS
    local c, r = math.floor(column), math.floor(row)
    local set = have[world]
    if not set[c .. "_" .. r] then return deactivate() end

    -- how many screen pixels one tile covers decides which copy is shown
    local size = TILE_YARDS * (width / 2) / radius
    local _, physical = GetPhysicalScreenSize()
    local scale = frame:GetEffectiveScale()
    local copy = 3
    if not hidden(physical) and not hidden(scale) then
        local pixels = size * scale * physical / 768
        if pixels <= COPY_PIXELS[1] then copy = 1 elseif pixels <= COPY_PIXELS[2] then copy = 2 end
    end

    if c ~= shownColumn or r ~= shownRow or world ~= shownWorld or copy ~= shownCopy then
        shownColumn, shownRow, shownWorld, shownCopy = c, r, world, copy
        local i = 0
        for dr = -1, 1 do
            for dc = -1, 1 do
                i = i + 1
                local key = (c + dc) .. "_" .. (r + dr)
                if set[key] then
                    slots[i]:SetTexture(BASE .. world .. "\\" .. COPY[copy] .. key, nil, nil, "LINEAR")
                    slots[i]:Show()
                else
                    slots[i]:Hide()
                end
            end
        end
    end

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
        outline()
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
        local red, green, blue = tint()
        local now = math.floor(red * 255 + 0.5) * 65536 + math.floor(green * 255 + 0.5) * 256 + math.floor(blue * 255 + 0.5)
        if ok and now ~= shownTone then
            shownTone = now
            for _, tile in ipairs(slots) do tile:SetVertexColor(red, green, blue) end
        end
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

-- What each of the nine tile slots really holds (for the watcher on the local test server).
function ns.MinimapSlotReport()
    local out = {}
    if not slots then return out end
    for i, tile in ipairs(slots) do
        local r, g, b, a = tile:GetVertexColor()
        local w, h = tile:GetSize()
        local _, physical = GetPhysicalScreenSize()
        out[i] = string.format("slot %d shown=%s id=%s copy=%s size=%.0f units = %.0f px, tone=%.2f",
            i, tostring(tile:IsShown()), tostring(tile:GetTextureFileID()), tostring(shownCopy), w,
            w * frame:GetEffectiveScale() * physical / 768, r)
    end
    return out
end

function ns.MinimapStatus()
    if not DenoMapDB.minimap then return "off" end
    if active then return "on, drawing" end
    return "on, standing by (the game's own terrain is showing here)"
end
