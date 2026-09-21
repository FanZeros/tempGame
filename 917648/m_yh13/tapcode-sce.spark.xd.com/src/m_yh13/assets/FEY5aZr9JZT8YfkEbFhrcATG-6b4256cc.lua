local Config = require("diggin.Config")
local AbyssLoot = require("diggin.AbyssLoot")
local AbyssRunTools = require("diggin.AbyssRunTools")

local AbyssMetaRenderer = {}

local ROUTE_COLORS = {
    universal = Config.Palette.creamDim,
    safe = Config.Palette.green,
    treasure = Config.Palette.gold,
    risk = Config.Palette.red,
}

local function drawEquipmentIcon(renderer, item, x, y, size, alpha)
    return renderer:DrawSheetCell(Config.Paths.abyssEquipmentAtlas, 5, 4,
        item and item.iconIndex or 1, x, y, size, size, alpha or 1)
end

function AbyssMetaRenderer.DrawBlacksmith(renderer, app)
    renderer.worldTreeButtons = {}
    renderer:FillRect(0, 0, Config.DESIGN_WIDTH, Config.DESIGN_HEIGHT, { 7, 5, 11, 225 })
    local x, y, w, h = 10, 18, 460, 242
    renderer:DrawPanel(x, y, w, h, "铁匠铺 · 装备仓库")
    local storage = app.state.abyssEquipmentStorage or {}
    local capacity = Config.Abyss.equipmentStorageCapacity or 60
    renderer:Text(string.format("晶尘 %d · 仓库 %d/%d · 图鉴 %d/20",
        app.state.abyssDust or 0, #storage, capacity, AbyssLoot.GetDiscoveredCount(app.state)), x + 10, y + 27, 7,
        Config.Palette.creamDim)
    local bulkCount = app.state:GetAbyssBulkSalvagePreview("B")
    renderer:DrawButton("blacksmith_salvage_all", bulkCount > 0 and ("一键分解 " .. bulkCount .. "件") or "无低级弱装",
        x + 343, y + 20, 107, 20, bulkCount > 0, false, renderer.worldTreeButtons)

    local selectedSlot = app.selectedAbyssLootSlot or "drill_core"
    app.selectedAbyssLootSlot = selectedSlot
    for index, entry in ipairs(AbyssLoot.GetLoadout(app.state)) do
        local bx, by, bw, bh = x + 10 + (index - 1) * 72, y + 39, 66, 34
        local selected = not app.selectedAbyssStorageUid and entry.slot.id == selectedSlot
        local color = entry.grade and AbyssLoot.GetGradeColor(entry.grade.id, renderer.time)
            or Config.Palette.inkSoft
        renderer:FillRect(bx, by, bw, bh, { 20, 16, 27, 245 })
        renderer:StrokeRect(bx, by, bw, bh, selected and Config.Palette.cream or color, selected and 2 or 1)
        if entry.item then drawEquipmentIcon(renderer, AbyssLoot.GetArchetype(entry.item.archetypeId), bx + 3, by + 4, 23, 1) end
        renderer:Text(entry.slot.name, bx + 30, by + 7, 7, Config.Palette.cream)
        renderer:Text(entry.grade and (entry.grade.id .. "  +" .. tostring(entry.item.forgeLevel or 0)) or "未装备",
            bx + 30, by + 21, 7, color)
        renderer.worldTreeButtons["blacksmith_slot:" .. entry.slot.id] = {
            x = bx, y = by, w = bw, h = bh, enabled = true,
        }
    end

    local perPage = 8
    local pageCount = math.max(1, math.ceil(#storage / perPage))
    app.blacksmithPage = math.max(1, math.min(pageCount, math.floor(tonumber(app.blacksmithPage) or 1)))
    renderer:Text(string.format("仓库第 %d/%d 页 · 一键仅清理F～B级弱装，保留强化、A级以上和更优装备", app.blacksmithPage, pageCount),
        x + 10, y + 82, 6, Config.Palette.cyan)
    local startIndex = (app.blacksmithPage - 1) * perPage + 1
    for localIndex = 1, perPage do
        local item = storage[startIndex + localIndex - 1]
        local column, row = (localIndex - 1) % 4, math.floor((localIndex - 1) / 4)
        local ix, iy, iw, ih = x + 10 + column * 54, y + 94 + row * 45, 49, 40
        renderer:FillRect(ix, iy, iw, ih, { 13, 10, 18, 242 })
        if item then
            local grade = AbyssLoot.GetGrade(item.grade)
            local color = AbyssLoot.GetGradeColor(item.grade, renderer.time)
            local selected = tonumber(app.selectedAbyssStorageUid) == tonumber(item.uid)
            renderer:StrokeRect(ix, iy, iw, ih, selected and Config.Palette.cream or color, selected and 2 or 1)
            drawEquipmentIcon(renderer, AbyssLoot.GetArchetype(item.archetypeId), ix + 3, iy + 3, 25, 1)
            renderer:Text(item.grade, ix + 44, iy + 8, 7, color, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            renderer:Text("+" .. tostring(item.forgeLevel or 0), ix + 44, iy + 20, 6,
                Config.Palette.creamDim, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            renderer:Text((AbyssLoot.GetSlot(item.slot) or {}).name or "装备", ix + 4, iy + 34, 6,
                ROUTE_COLORS[item.routeId] or Config.Palette.creamDim)
            renderer.worldTreeButtons["blacksmith_storage:" .. tostring(item.uid)] = {
                x = ix, y = iy, w = iw, h = ih, enabled = true,
            }
        else
            renderer:StrokeRect(ix, iy, iw, ih, Config.Palette.inkSoft, 1)
        end
    end

    local storedItem = app.selectedAbyssStorageUid and app.state:GetAbyssStoredItem(app.selectedAbyssStorageUid) or nil
    local detail = storedItem and AbyssLoot.GetStandaloneDetails(app.state, storedItem)
        or AbyssLoot.GetItemDetails(app.state, selectedSlot)
    if detail then
        renderer:Text(detail.title, x + 235, y + 87, 8,
            detail.grade and AbyssLoot.GetGradeColor(detail.grade.id, renderer.time) or Config.Palette.creamDim)
        renderer:TextBox(detail.affixText, x + 235, y + 102, 211, 7, Config.Palette.cream)
        if storedItem then
            local equipped = AbyssLoot.GetEquippedItem(app.state, storedItem.slot)
            local difference = detail.score - AbyssLoot.GetEquipmentScore(equipped)
            renderer:Text(string.format("对比当前%s：战力 %s%d · 分解 +%d晶尘",
                (AbyssLoot.GetSlot(storedItem.slot) or {}).name or "槽位",
                difference >= 0 and "+" or "", difference, detail.salvage),
                x + 235, y + 163, 6, difference >= 0 and Config.Palette.green or Config.Palette.red)
        else
            renderer:TextBox(detail.resonance, x + 235, y + 153, 211, 7, Config.Palette.cyan)
        end
    end

    renderer:DrawButton("blacksmith_prev", "上一页", x + 10, y + h - 29, 58, 20,
        app.blacksmithPage > 1, false, renderer.worldTreeButtons)
    renderer:DrawButton("blacksmith_next", "下一页", x + 72, y + h - 29, 58, 20,
        app.blacksmithPage < pageCount, false, renderer.worldTreeButtons)
    if storedItem then
        renderer:DrawButton("blacksmith_equip", "装备/交换", x + 150, y + h - 29, 82, 20,
            true, false, renderer.worldTreeButtons)
        renderer:DrawButton("blacksmith_salvage", "分解", x + 237, y + h - 29, 62, 20,
            true, false, renderer.worldTreeButtons)
    else
        local forgeCost = detail and detail.forgeCost or 0
        local promoteCost = detail and detail.promoteCost or 0
        local hasItem = detail and detail.grade ~= nil
        renderer:DrawButton("blacksmith_forge", forgeCost > 0 and ("强化 " .. forgeCost) or "强化已满",
            x + 136, y + h - 29, 62, 20, hasItem and forgeCost > 0, false, renderer.worldTreeButtons)
        renderer:DrawButton("blacksmith_promote", promoteCost > 0 and ("升阶 " .. promoteCost) or "升阶需+5",
            x + 202, y + h - 29, 70, 20, hasItem and promoteCost > 0, false, renderer.worldTreeButtons)
        renderer:DrawButton("world_tree_loot_reforge", hasItem and ("重铸 " .. detail.reforgeCost) or "重铸",
            x + 276, y + h - 29, 68, 20, hasItem, false, renderer.worldTreeButtons)
    end
    renderer:DrawButton("blacksmith_close", "关闭", x + w - 80, y + h - 29, 70, 20,
        true, false, renderer.worldTreeButtons)
end

function AbyssMetaRenderer.DrawWeaponCodex(renderer, app)
    renderer.worldTreeButtons = {}
    renderer:FillRect(0, 0, Config.DESIGN_WIDTH, Config.DESIGN_HEIGHT, { 7, 5, 11, 225 })
    local x, y, w, h = 42, 26, 396, 220
    renderer:DrawPanel(x, y, w, h, "终极专武配方图鉴")
    renderer:Text("每次选择道具或被动都会积累锻造进度；专武不占新的道具槽。",
        x + 11, y + 29, 7, Config.Palette.creamDim)
    local recipes, perPage = AbyssRunTools.GetRecipeCodex(), 4
    local pageCount = math.max(1, math.ceil(#recipes / perPage))
    app.weaponCodexPage = math.max(1, math.min(pageCount, math.floor(tonumber(app.weaponCodexPage) or 1)))
    renderer:Text(string.format("第 %d/%d 页 · 共 %d 种终极专武", app.weaponCodexPage, pageCount, #recipes),
        x + w - 12, y + 29, 7, Config.Palette.gold, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    local first = (app.weaponCodexPage - 1) * perPage + 1
    for localIndex = 1, perPage do
        local index = first + localIndex - 1
        local recipe = recipes[index]
        if recipe then
        local rowY = y + 48 + (localIndex - 1) * 34
        renderer:FillRect(x + 10, rowY, w - 20, 29, { 22, 17, 31, 238 })
        local borderColors = { Config.Palette.red, Config.Palette.cyan, Config.Palette.gold, Config.Palette.purple }
        renderer:StrokeRect(x + 10, rowY, w - 20, 29,
            borderColors[((index - 1) % #borderColors) + 1], 1)
        renderer:DrawImage(Config.Paths.generatedRoot .. "skill_icons/" .. recipe.iconNode .. ".png",
            x + 14, rowY + 3, 23, 23, 1)
        renderer:Text(recipe.name .. "：" .. recipe.recipe, x + 44, rowY + 5, 8, Config.Palette.cream)
        renderer:Text(recipe.effect, x + 44, rowY + 17, 6, Config.Palette.creamDim)
        end
    end
    renderer:DrawButton("weapon_codex_prev", "上一页", x + 12, y + h - 27, 62, 19,
        app.weaponCodexPage > 1, false, renderer.worldTreeButtons)
    renderer:DrawButton("weapon_codex_next", "下一页", x + 80, y + h - 27, 62, 19,
        app.weaponCodexPage < pageCount, false, renderer.worldTreeButtons)
    renderer:DrawButton("weapon_codex_close", "关闭", x + w - 82, y + h - 27, 70, 19,
        true, false, renderer.worldTreeButtons)
end

return AbyssMetaRenderer
