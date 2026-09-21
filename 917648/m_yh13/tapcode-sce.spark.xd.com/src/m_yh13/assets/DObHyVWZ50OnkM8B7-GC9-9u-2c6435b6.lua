local Config = require("diggin.Config")
local Util = require("diggin.Util")
local WorldTree = require("diggin.WorldTree")
local AbyssLoot = require("diggin.AbyssLoot")
local AbyssMetaRenderer = require("diggin.AbyssMetaRenderer")

local WorldTreeRenderer = {}

local function nodePosition(node, view)
    return view.x + node.position[1] * view.zoom, view.y + node.position[2] * view.zoom
end

local function drawConnection(renderer, x1, y1, x2, y2, color, active)
    nvgBeginPath(renderer.vg)
    nvgMoveTo(renderer.vg, x1, y1)
    nvgLineTo(renderer.vg, x2, y2)
    nvgStrokeColor(renderer.vg, Util.Color(active and color or { 68, 61, 78, 145 }))
    nvgStrokeWidth(renderer.vg, active and 2 or 1)
    nvgStroke(renderer.vg)
end

local function drawNodeIcon(renderer, node, x, y, w, h, alpha)
    if node.earlyIconIndex then
        return renderer:DrawSheetCell(node.icon, 3, 3, node.earlyIconIndex, x, y, w, h, alpha)
    end
    if node.iconAtlasIndex then
        return renderer:DrawSheetCell(Config.Paths.abyssWorldItemAtlas, 5, 2,
            node.iconAtlasIndex, x, y, w, h, alpha)
    end
    local path = tostring(node.icon or "")
    if path:find("/", 1, true) then return renderer:DrawImage(path, x, y, w, h, alpha) end
    return renderer:DrawImage(Config.Paths.generatedRoot .. "skill_icons/" .. path .. ".png",
        x, y, w, h, alpha)
end

local function drawTooltip(renderer, app, node)
    local x, y, w, h = 299, 43, 172, 186
    local level = WorldTree.GetLevel(app.state, node.id)
    local cost = WorldTree.GetCost(app.state, node.id)
    local available = WorldTree.IsAvailable(app.state, node)
    local maxed = level >= node.maxLevel
    renderer:DrawPanel(x, y, w, h, node.name)
    drawNodeIcon(renderer, node, x + 9, y + 27, 30, 30, available and 1 or 0.25)
    renderer:Text(node.branchName .. " · 第 " .. node.tier .. " 层", x + 47, y + 31, 8, node.color)
    renderer:Text(string.format("等级 %d/%d", level, node.maxLevel), x + 47, y + 46, 8,
        maxed and Config.Palette.green or Config.Palette.cyan)
    renderer:FillRect(x + 8, y + 63, w - 16, 1, { 86, 77, 95, 210 })
    renderer:TextBox(node.effect, x + 9, y + 72, w - 18, 8, Config.Palette.cream)

    local rule = "需连通前置节点，并让本方向主根达到该层门槛。"
    if node.mechanicId then
        local catalog = require("diggin.DrillMechanicsCatalog")
        rule = catalog.Describe(node.mechanicId, catalog.Ranks(WorldTree, app.state)[node.mechanicId] or 0)
    elseif node.early then
        rule = "主根1级即可学习。共3级，每级花费1/2/3点；不改变旧节点。"
    elseif node.kind == "item" then
        rule = "解锁后加入深渊三选一道具池；普通模式不会触发。"
    elseif node.kind == "item_upgrade" then
        rule = "该道具的永久精通节点；只强化对应世界树道具。"
    elseif #node.parents == 0 then
        rule = "主根共8级；2/4/6/8级依次开放四层分支。"
    end
    renderer:TextBox(rule, x + 9, y + 111, w - 18, 7, Config.Palette.creamDim)
    renderer:Text("世界树点数 " .. tostring(app.state.worldTreePoints or 0), x + 9, y + h - 45,
        7, Config.Palette.cyan)
    local canBuy = WorldTree.CanBuy(app.state, node.id)
    local label = canBuy and ("生长 · " .. cost .. " 点") or "点数不足"
    if maxed then label = "已生长完成"
    elseif not available then label = "前置或主根等级不足" end
    renderer:DrawButton("world_tree_buy_selected", label, x + 9, y + h - 27, w - 18, 19,
        canBuy, app.worldTreeHover == "world_tree_buy_selected", renderer.worldTreeButtons)
end

local function drawLootTooltip(renderer, app, slotId)
    local detail = AbyssLoot.GetItemDetails(app.state, slotId)
    if not detail then return end
    local x, y, w, h = 299, 43, 172, 186
    local color = detail.grade and AbyssLoot.GetGradeColor(detail.grade.id, renderer.time)
        or Config.Palette.creamDim
    renderer:DrawPanel(x, y, w, h, detail.title)
    renderer:DrawSheetCell(Config.Paths.abyssEquipmentAtlas, 5, 4,
        detail.iconIndex or 1, x + 9, y + 27, 34, 34, detail.grade and 1 or 0.2)
    renderer:Text(detail.slot.name .. " · 深渊装备槽", x + 50, y + 31, 8, color)
    renderer:Text(string.format("品级 %d/9 · 装备威能 %d", detail.gradeIndex, detail.power),
        x + 50, y + 47, 7, Config.Palette.creamDim)
    renderer:FillRect(x + 8, y + 67, w - 16, 1, { 86, 77, 95, 210 })
    renderer:TextBox(detail.affixText, x + 9, y + 75, w - 18, 7, color)
    renderer:TextBox(detail.resonance, x + 9, y + 108, w - 18, 7, Config.Palette.cyan)
    if detail.grade then
        renderer:Text("重复/低级装备分解：晶尘 +" .. tostring(detail.salvage),
            x + 9, y + 139, 7, Config.Palette.gold)
        renderer:Text("重铸消耗 " .. detail.reforgeCost .. " 晶尘", x + 9, y + 152, 7, Config.Palette.creamDim)
    else
        renderer:Text("来源：深渊矿石、首层奖励与宝箱", x + 9, y + 153, 7, Config.Palette.gold)
    end
    renderer:DrawButton("world_tree_loot_reforge", "晶尘重铸", x + 9, y + h - 25, 72, 18,
        detail.grade ~= nil, app.worldTreeHover == "world_tree_loot_reforge", renderer.worldTreeButtons)
    renderer:DrawButton("world_tree_loot_close", "关闭", x + 88, y + h - 25, 75, 18,
        true, app.worldTreeHover == "world_tree_loot_close", renderer.worldTreeButtons)
end

function WorldTreeRenderer.Draw(renderer, app)
    renderer.worldTreeButtons = {}
    renderer.worldTreeNodeRects = {}
    renderer:DrawStarfield()

    local view = app.worldTreeView
    local coreSize = 76 * view.zoom
    renderer:DrawImage(Config.Paths.worldTree, view.x - coreSize * 0.37, view.y - coreSize * 0.55,
        coreSize * 0.74, coreSize, app.state.worldTreeAwakened and 0.38 or 0.12)

    for _, branch in ipairs(WorldTree.BRANCHES) do
        local root = WorldTree.NODE_BY_ID[branch.rootId]
        if root and WorldTree.IsVisible(app.state, root) then
            local x2, y2 = nodePosition(root, view)
            drawConnection(renderer, view.x, view.y, x2, y2, branch.color,
                WorldTree.GetLevel(app.state, root.id) > 0)
        end
    end

    for _, node in ipairs(WorldTree.NODES) do
        if WorldTree.IsVisible(app.state, node) then
            local x1, y1 = nodePosition(node, view)
            for _, childId in ipairs(node.unlocks) do
                local child = WorldTree.NODE_BY_ID[childId]
                if child and WorldTree.IsVisible(app.state, child) then
                    local x2, y2 = nodePosition(child, view)
                    drawConnection(renderer, x1, y1, x2, y2, node.color,
                        WorldTree.GetLevel(app.state, node.id) > 0)
                end
            end
        end
    end

    for _, node in ipairs(WorldTree.NODES) do
        if WorldTree.IsVisible(app.state, node) then
            local x, y = nodePosition(node, view)
            local size = math.max(10, 20 * view.zoom)
            if x > -size and x < Config.DESIGN_WIDTH + size and y > 27 - size and y < 240 + size then
                local level = WorldTree.GetLevel(app.state, node.id)
                local available = WorldTree.IsAvailable(app.state, node)
                local maxed = level >= node.maxLevel
                local selected = app.selectedWorldTreeNode == node.id
                local fill = level > 0 and node.color or Config.Palette.inkSoft
                renderer:FillRect(x - size * 0.5 + 2, y - size * 0.5 + 2, size, size, Config.Palette.shadow)
                renderer:FillRect(x - size * 0.5, y - size * 0.5, size, size, fill)
                local border = selected and Config.Palette.cream
                    or (maxed and Config.Palette.green or { node.color[1], node.color[2], node.color[3], available and 255 or 80 })
                renderer:StrokeRect(x - size * 0.5, y - size * 0.5, size, size, border,
                    selected and 2 or 1)
                drawNodeIcon(renderer, node, x - size * 0.38, y - size * 0.38,
                    size * 0.76, size * 0.76, available and 1 or 0.24)
                if node.kind == "item" then
                    renderer:Text("◆", x + size * 0.48, y - size * 0.48, math.max(6, 7 * view.zoom),
                        Config.Palette.gold, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                elseif node.maxLevel > 1 and level > 0 then
                    renderer:Text(level .. "/" .. node.maxLevel, x, y + size * 0.52,
                        math.max(6, 7 * view.zoom), Config.Palette.cream,
                        NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                end
                renderer.worldTreeNodeRects[node.id] = {
                    x = x - size * 0.68, y = y - size * 0.68,
                    w = size * 1.36, h = size * 1.36, enabled = true,
                }
            end
        end
    end

    renderer:FillRect(0, 0, Config.DESIGN_WIDTH, 28, { 26, 21, 35, 248 })
    renderer:DrawButton("world_tree_back", "主菜单", 6, 4, 54, 20, true,
        app.worldTreeHover == "world_tree_back", renderer.worldTreeButtons)
    renderer:Text("世界树 · " .. #WorldTree.NODES .. " 节点", 69, 7, 11, Config.Palette.cream)
    local fullyMaxed = WorldTree.GetFullyMaxedNodeCount(app.state)
    renderer:Text(string.format("已满级 %d/100", fullyMaxed), 211, 14, 7, Config.Palette.green,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    renderer:DrawImage(Config.Paths.worldTreePoint, 286, 7, 12, 12, 1)
    renderer:Text(tostring(app.state.worldTreePoints or 0), 302, 14, 8, Config.Palette.cyan,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    for index, entry in ipairs(AbyssLoot.GetLoadout(app.state)) do
        local itemX = 320 + (index - 1) * 15
        local color = entry.grade and AbyssLoot.GetGradeColor(entry.grade.id, renderer.time)
            or { 65, 58, 75, 255 }
        local selected = app.selectedAbyssLootSlot == entry.slot.id
        renderer:FillRect(itemX, 5, 13, 17, { 12, 10, 18, 235 })
        renderer:StrokeRect(itemX, 5, 13, 17, selected and Config.Palette.cream or color,
            selected and 2 or 1)
        renderer:DrawSheetCell(Config.Paths.abyssEquipmentAtlas, 5, 4, entry.iconIndex, itemX + 1, 6, 11, 11,
            entry.grade and 1 or 0.18)
        renderer:Text(entry.gradeId or "-", itemX + 6.5, 19, entry.gradeId == "SSS" and 4 or 5,
            color, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        renderer.worldTreeButtons["world_tree_loot:" .. entry.slot.id] = {
            x = itemX - 1, y = 3, w = 15, h = 21, enabled = true,
        }
    end
    local capstoneCount = WorldTree.GetCapstoneCount(app.state)
    local starCount = app.state:GetDensityStarCount()
    local canEnter = WorldTree.CanEnterAbyss(app.state)
    local enterLabel = "无尽下潜"
    if capstoneCount < #WorldTree.CAPSTONES then
        enterLabel = string.format("终极 %d/4", capstoneCount)
    elseif not app.state:IsFinalDensityUnlocked() then
        enterLabel = string.format("星辰 %d/%d", starCount, Config.STARDROPS_FOR_FINAL_DENSITY)
    end
    renderer:DrawButton("world_tree_enter_abyss", enterLabel,
        383, 4, 88, 20, canEnter, app.worldTreeHover == "world_tree_enter_abyss",
        renderer.worldTreeButtons)

    renderer:FillRect(0, 240, Config.DESIGN_WIDTH, 30, { 26, 21, 35, 242 })
    local hardcoreUnlocked = WorldTree.IsFullyMaxed(app.state)
    if capstoneCount < #WorldTree.CAPSTONES then
        renderer:Text(string.format("世界树：四大终极技能 %d/4", capstoneCount),
            8, 244, 7, Config.Palette.gold, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        renderer:Text("缺少：" .. table.concat(WorldTree.GetMissingCapstoneNames(app.state), "、"),
            8, 254, 6, Config.Palette.creamDim, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    elseif not app.state:IsFinalDensityUnlocked() then
        renderer:Text("世界树已苏醒", 8, 244, 7, Config.Palette.green,
            NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        renderer:Text(string.format("深渊开启条件 · 星辰 %d/%d", starCount,
            Config.STARDROPS_FOR_FINAL_DENSITY), 8, 254, 6, Config.Palette.creamDim,
            NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    else
        renderer:Text(hardcoreUnlocked and "世界树全部满级 · 硬核模式已解锁"
            or "世界树全部满级后解锁硬核模式",
            8, 249, 7,
            hardcoreUnlocked and Config.Palette.red or Config.Palette.creamDim,
            NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    end
    renderer:DrawButton("weapon_codex", "专武图鉴", 204, 244, 58, 20, true,
        app.worldTreeHover == "weapon_codex", renderer.worldTreeButtons)
    renderer:DrawButton("blacksmith", "装备仓库", 266, 244, 58, 20, true,
        app.worldTreeHover == "blacksmith", renderer.worldTreeButtons)
    if hardcoreUnlocked then
        renderer:DrawButton("world_tree_enter_hardcore", "硬核", 328, 244, 42, 20, true,
            app.worldTreeHover == "world_tree_enter_hardcore", renderer.worldTreeButtons)
    end
    renderer:DrawButton("world_tree_leaderboard", "深度榜", 374, 244, 97, 20, true,
        app.worldTreeHover == "world_tree_leaderboard", renderer.worldTreeButtons)

    local selected = app.selectedWorldTreeNode and WorldTree.NODE_BY_ID[app.selectedWorldTreeNode]
    if app.selectedAbyssLootSlot then
        drawLootTooltip(renderer, app, app.selectedAbyssLootSlot)
    elseif selected and WorldTree.IsVisible(app.state, selected) then
        drawTooltip(renderer, app, selected)
    end
    if app.showBlacksmith then
        AbyssMetaRenderer.DrawBlacksmith(renderer, app)
    elseif app.showWeaponCodex then
        AbyssMetaRenderer.DrawWeaponCodex(renderer, app)
    end
end

return WorldTreeRenderer
