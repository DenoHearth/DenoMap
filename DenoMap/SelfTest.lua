-- Deno Map 4K - self test.
--
-- /denomap selftest writes what the addon measured into its saved variables and takes two
-- screenshots (the minimap as it is, then the world map), so a problem can be looked at
-- afterwards. It runs once by itself when DenoMapDB.selftest is set.

local ADDON, ns = ...

local running = false

local function finish(openedMap)
    if openedMap and WorldMapFrame:IsShown() and not InCombatLockdown() then ToggleWorldMap() end
    DenoMapDB.selftest = false
    running = false
    print("|cffffcc66Deno Map 4K|r: self test done. Two screenshots are in the Screenshots folder.")
end

function ns.SelfTest()
    if running then return end
    running = true
    local report = { when = date("%Y-%m-%d %H:%M:%S"), zone = GetMinimapZoneText(), minimap = ns.MinimapReport() }
    DenoMapDB.report = report
    Screenshot()
    C_Timer.After(2, function()
        local opened = false
        if not WorldMapFrame:IsShown() and not InCombatLockdown() then
            ToggleWorldMap()
            opened = true
        end
        C_Timer.After(2, function()
            report.map = ns.MapReport()
            report.mapShown = WorldMapFrame:IsShown() and true or false
            local levels = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.zoomLevels
            report.zoomSteps = levels and #levels or 0
            report.minimapAfter = ns.MinimapStatus()
            Screenshot()
            C_Timer.After(2, function() finish(opened) end)
        end)
    end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function()
    if DenoMapDB and DenoMapDB.selftest then
        -- late enough for the minimap to have measured its place
        C_Timer.After(10, function()
            if DenoMapDB.selftest then ns.SelfTest() end
        end)
    end
end)
