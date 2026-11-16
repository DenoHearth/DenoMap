-- Deno Map 4K: Zygor's map extras off (2026-11-07, his asks: "can we make it survive updates",
-- "make it to our 4k addon so it looks for zygor and disables it, even if we update it").
-- Until now these were LOCAL PATCHES inside Zygor's own files, and his Zygor update of 2026-11-06
-- wiped them. This file is part of Deno Map, which a Zygor update never touches. It does nothing
-- without Zygor; with it (loaded first: ## OptionalDeps) it switches these off from outside:
--   1. Path lines and ants on the world map and the minimap ("pathing"). Zygor's option
--      maplines_enabled is set off in his profile (saved, so it holds), and the two Pointer
--      functions that draw them do nothing, so turning the option back on cannot bring them back.
--   2. Shift+left click on the map setting a waypoint. Zygor reads that click in
--      Pointer.OverlayProvider.OnUpdate only while OverlayProvider.onCanvasClickHandler is unset
--      (its new-style handler is commented out, "disabled in 11.0 due to blizz taint issues").
--      Giving that field a function that does nothing skips the click code.
--   3. Foglight, the unexplored-areas layer on the world map (it drew Dun Morogh's art over
--      Ironforge): option off, the layer removed, its show functions do nothing.
-- Only Zygor's own Lua tables are changed (no Blizzard code), so no taint. If a future Zygor
-- renames something, that one tweak just stops; nothing errors (every access is checked).
if not C_AddOns.IsAddOnLoaded("ZygorGuidesViewerForever") then return end

local ZGV

local function Off()
    ZGV = ZGV or _G.ZygorGuidesViewer
    if type(ZGV) ~= "table" then return end
    local profile = ZGV.db and ZGV.db.profile

    -- 1. path lines and ants
    local P = ZGV.Pointer
    if type(P) == "table" then
        if profile then profile.maplines_enabled = false end
        if type(P.AnimateAnts) == "function" and not P.denoOff then
            P.AnimateAnts = function() end
            P.UpdateMapLines = function() end
            P.denoOff = true
        end
        if type(P.ClearAntsAndLines) == "function" then pcall(P.ClearAntsAndLines, P) end

        -- 2. shift+click waypoint on the map
        local provider = P.OverlayProvider
        if type(provider) == "table" and not provider.onCanvasClickHandler then
            provider.onCanvasClickHandler = function() end
        end
    end

    -- 3. Foglight
    local F = ZGV.Foglight
    if type(F) == "table" then
        if profile then profile.foglight = false end
        if type(F.HideOverlay) == "function" then pcall(F.HideOverlay, F) end
        if not F.denoOff then
            F.Startup = function() end
            F.ShowOverlay = function() end
            F.ToggleOverlay = function(self) if self.HideOverlay then pcall(self.HideOverlay, self) end end
            F.denoOff = true
        end
    end
end

-- Now (Zygor's files are loaded: the functions are swapped before Zygor starts them), and again
-- once Zygor has its saved settings.
Off()
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function()
    Off()
    C_Timer.After(2, Off)
end)
