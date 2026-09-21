local Config = require("diggin.Config")
local SkillText = require("diggin.SkillText")

local ArtefactCodex = {}

local BRANCH_NAMES = {
    core = "核心", damage = "伤害", fuel = "燃料", quake = "震荡", world = "世界",
}

local function statusFor(state, node)
    local level = state:GetLevel(node.id)
    if level > 0 then
        return string.format("● 生效 Lv.%d/%d", level, node.max_level or 1), Config.Palette.green
    end
    if state.artefacts[node.id] == true then
        return "◆ 已持有 · 待镶入", Config.Palette.gold
    end
    if state:IsArtefactDiscovered(node.id) then
        return "已发现", Config.Palette.cream
    end
    return "宝箱未发现", Config.Palette.creamDim
end

function ArtefactCodex.Draw(renderer, app)
    local state = renderer.state
    local nodes = state:GetArtefactNodes()
    local selected = state.nodeById[app.selectedArtefact] or nodes[1]
    if not selected then return end
    app.selectedArtefact = selected.id

    local discovered = state:IsArtefactDiscovered(selected.id)
    local active = state:IsArtefactActive(selected.id)
    local held = state.artefacts[selected.id] == true
    local level = state:GetLevel(selected.id)
    local accent = Config.BranchColors[selected.branch] or Config.Palette.gold

    renderer:DrawPanel(8, 34, 172, 198, SkillText.GetName(selected) .. (discovered and "" or " · 未发现"))
    renderer:FillRect(18, 62, 46, 46, Config.Palette.shadow)
    renderer:FillRect(15, 59, 46, 46, { 36, 29, 42, 245 })
    renderer:StrokeRect(15, 59, 46, 46, discovered and accent or { 80, 71, 91, 210 }, discovered and 2 or 1)
    if discovered then
        renderer:DrawSkillIcon(selected, 21, 65, 34, 1)
    else
        renderer:DrawSkillIcon(selected, 21, 65, 34, 0.12)
        renderer:Text("?", 38, 82, 18, Config.Palette.creamDim, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end
    renderer:Text("路线 · " .. (BRANCH_NAMES[selected.branch] or "特殊"), 70, 61, 8, discovered and accent or Config.Palette.creamDim)
    renderer:Text(discovered and string.format("等级 %d/%d", level, selected.max_level or 1) or "图鉴条目未解锁", 70, 78, 8, Config.Palette.creamDim)
    renderer:Text(discovered and (held and "持有中" or (active and "已镶入技能" or "已发现")) or "从任意宝箱随机发现", 70, 94, 7, discovered and Config.Palette.gold or Config.Palette.creamDim)

    renderer:FillRect(15, 113, 158, 1, { 86, 77, 95, 210 })
    renderer:TextBox(discovered and SkillText.GetSummary(selected, state)
        or ("打开任意矿井宝箱可随机发现「" .. SkillText.GetName(selected) .. "」。发现后永久记录，镶入技能也不会从图鉴消失。"),
        15, 121, 158, 8, discovered and Config.Palette.cream or Config.Palette.creamDim)
    local statusText, statusColor = statusFor(state, selected)
    renderer:Text(statusText, 15, 171, 8, statusColor)
    local hint = active and "效果已应用；后续等级只消耗资源"
        or (held and "前往技能树，为对应节点镶入后生效" or "未发现时不能镶入或激活")
    renderer:Text(hint, 15, 186, 7, Config.Palette.creamDim)
    local actionLabel = active and "查看生效天赋" or (held and "前往技能树镶入" or "宝箱随机掉落")
    renderer:DrawButton("talent_action", actionLabel, 70, 204, 102, 20, discovered, app.relicHover == "talent_action", renderer.relicButtons)

    renderer:DrawPanel(188, 34, 284, 198, "天赋遗物图鉴 · 发现 → 镶入技能 → 永久生效")
    for index, node in ipairs(nodes) do
        local column = (index - 1) % 3
        local row = math.floor((index - 1) / 3)
        local x = 196 + column * 90
        local y = 58 + row * 55
        local w, h = 84, 49
        local isSelected = node.id == selected.id
        local isDiscovered = state:IsArtefactDiscovered(node.id)
        local isActive = state:IsArtefactActive(node.id)
        local isHeld = state.artefacts[node.id] == true
        local nodeAccent = Config.BranchColors[node.branch] or Config.Palette.gold
        local border = isSelected and nodeAccent
            or (isActive and Config.Palette.green or (isHeld and Config.Palette.gold or { 80, 71, 91, 210 }))
        renderer:FillRect(x + 3, y + 3, w, h, Config.Palette.shadow)
        renderer:FillRect(x, y, w, h, isSelected and { 57, 49, 75, 255 } or { 36, 31, 43, 245 })
        renderer:StrokeRect(x, y, w, h, border, isSelected and 2 or 1)
        renderer:DrawSkillIcon(node, x + 5, y + 6, 24, isDiscovered and 1 or 0.1)
        if not isDiscovered then
            renderer:Text("?", x + 17, y + 18, 11, Config.Palette.creamDim, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        end
        renderer:Text(SkillText.GetName(node), x + 34, y + 6, 8, isDiscovered and Config.Palette.cream or Config.Palette.creamDim)
        renderer:Text(isDiscovered and (BRANCH_NAMES[node.branch] or "特殊") .. "路线" or "宝箱随机", x + 34, y + 20, 6, isDiscovered and nodeAccent or Config.Palette.creamDim)
        local cellStatus = isActive and ("生效 Lv." .. tostring(state:GetLevel(node.id)))
            or (isHeld and "已持有 · 待镶入" or (isDiscovered and "已发现" or "宝箱未发现"))
        renderer:Text(cellStatus, x + 5, y + h - 6, 6, isActive and Config.Palette.green or (isHeld and Config.Palette.gold or Config.Palette.creamDim), NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
        renderer.relicButtons["talent_select:" .. node.id] = { x = x, y = y, w = w, h = h, enabled = true }
    end
end

return ArtefactCodex
