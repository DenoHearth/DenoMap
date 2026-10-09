-- Deno Map 4K - zoom further into the world map.
--
-- The game's map already zooms with the mouse wheel and moves when dragged while zoomed
-- in, but it stops at about twice the size. With four times the resolution there is
-- more to see, so the list of zoom steps gets four more: up to five times the size.
--
--   wheel up / down   zoom in / out, towards the mouse
--   hold left, drag   move the map while zoomed in
--
-- Nothing of Blizzard's is replaced: steps are added to the list the game has just built.

local ADDON, ns = ...

local EXTRA = { 2.6, 3.2, 4.0, 5.0 }     -- times the size of the whole map in the window

local function extend(container)
    local levels = container.zoomLevels
    local base = container.baseScale
    if not levels or not base or #levels == 0 then return end
    local last = levels[#levels]
    for _, factor in ipairs(EXTRA) do
        local scale = factor * base
        if scale > last.scale + 0.01 then
            last = { scale = scale, layerIndex = last.layerIndex }
            table.insert(levels, last)
        end
    end
end

local hooked = {}
function ns.AttachZoom(map)
    local container = map and map.ScrollContainer
    if not container or hooked[container] or not container.CreateZoomLevels then return end
    hooked[container] = true
    hooksecurefunc(container, "CreateZoomLevels", extend)
end
