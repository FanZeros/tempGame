local Content = require("diggin.AbyssContent")
local Config = require("diggin.Config")
local V = {}
function V.Emit(app, id)
    app.effects[#app.effects + 1] = { kind = "world_item_visual", toolVisual = id,
        x = app.player.x, y = app.player.y, radius = 24, life = 0.7, maxLife = 0.7 }
end
function V.Draw(renderer, effect, x, y, alpha)
    local item = Content.WORLD_ITEM_BY_ID[effect.toolVisual]
    if not item then return false end
    local progress = math.max(0, math.min(1, 1 - (effect.life or 0) / (effect.maxLife or 0.48)))
    local size = math.max(20, math.min(96, (effect.radius or 24) * 2)) * (0.6 + progress * 0.6)
    if effect.kind == "explosion" then
        local hot = item.id == "magma_lance" or item.id == "starcore_bomb" or item.id == "echo_charge"
        local frame = math.min(4, math.floor(progress * 5)) + 1 + (hot and 0 or 5)
        renderer:DrawSheetCell(Config.Paths.generatedRoot .. "world_item_impact_atlas.png", 5, 2, frame,
            x - size * 0.65, y - size * 0.65, size * 1.3, size * 1.3, alpha)
        size = size * 0.55
    end
    nvgSave(renderer.vg)
    nvgTranslate(renderer.vg, x, y)
    nvgRotate(renderer.vg, (item.id == "crystal_saw" and 8 or 1.4) * progress)
    if item.atlasIndex then
        renderer:DrawSheetCell(Config.Paths.abyssWorldItemAtlas, 5, 2, item.atlasIndex,
            -size/2, -size/2, size, size, alpha)
    else
        renderer:DrawImage(item.icon, -size/2, -size/2, size, size, alpha)
    end
    nvgRestore(renderer.vg)
    return true
end
return V
