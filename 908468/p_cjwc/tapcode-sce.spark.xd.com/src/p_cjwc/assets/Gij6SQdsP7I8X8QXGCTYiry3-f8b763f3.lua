local UI = require("urhox-libs/UI")
local EconomySkills = require("nightgate.EconomySkills")
local SkillCanvas = require("nightgate.SkillCanvas")
local Save = require("nightgate.Save")

local EconomyPage = {}

local TRANSPARENT = { 0, 0, 0, 0 }
local WHITE = { 241, 236, 220, 255 }
local GOLD = { 255, 205, 57, 255 }
local MUTED = { 176, 169, 178, 255 }
local PANEL = { 15, 11, 20, 248 }
local BORDER = { 104, 82, 126, 255 }
local ORANGE_BUTTON = "image/nightgate/ui/1_orange_button_s.png"

local function percent(value)
    value = (tonumber(value) or 0) * 100
    if math.abs(value - math.floor(value + 0.5)) < 0.001 then
        return tostring(math.floor(value + 0.5)) .. "%"
    end
    return string.format("%.2f%%", value)
end

function EconomyPage.TryUpgrade(self, id, source)
    local definition = EconomySkills.GetDefinition(id)
    if not definition then return false end
    self.selectedEconomySkill = id
    local cost = EconomySkills.GetCost(self.battle.economyLevels, id)
    local ok, message = EconomySkills.TryUpgrade(self.battle, id)
    if ok then Save.Store(self.battle) end
    local level = EconomySkills.GetLevel(self.battle.economyLevels, id)
    if ok then
        message = definition.name .. " 已升至 Lv." .. tostring(level) .. "，消耗 " .. tostring(cost or 0) .. " 金币"
    else
        message = "无法加点：" .. tostring(message or "条件未满足")
    end
    self.economyFeedbackText = message
    self.economyFeedbackTimer = 2.2
    self.economyCanvas:FlashNode(id, ok)
    self.battle.message = message
    self.battle.messageTimer = 2.2
    print("EconomyUpgrade source=" .. tostring(source or "unknown") .. " id=" .. tostring(id) .. " ok=" .. tostring(ok))
    EconomyPage.Refresh(self)
    return ok
end

function EconomyPage.Refresh(self)
    if not self.economyPage then return end
    local levels = self.battle.economyLevels or {}
    for index = 1, #self.economyNodes do
        local node = self.economyNodes[index]
        node.level = EconomySkills.GetLevel(levels, node.id)
        node.state = EconomySkills.GetNodeState(levels, node.definition)
        node.revealed = EconomySkills.IsRevealed(levels, node.definition)
    end
    self.economyCanvas:SetNodes(self.economyNodes)

    local selected = EconomySkills.GetDefinition(self.selectedEconomySkill)
    if not selected or not EconomySkills.IsRevealed(levels, selected) then
        self.selectedEconomySkill = "e_root"
        selected = EconomySkills.GetDefinition("e_root")
    end
    self.economyCanvas:SetSelected(self.selectedEconomySkill)
    self.economyCanvas:SetAttention(EconomySkills.GetLevel(levels, "e_root") <= 0 and "e_root" or nil)
    local level = EconomySkills.GetLevel(levels, selected.id)
    local cost = EconomySkills.GetCost(levels, selected.id)
    local reason = EconomySkills.GetUnlockReason(levels, selected)
    self.economyDetailTitle:SetText(selected.name .. "  Lv." .. tostring(level) .. "/" .. tostring(#selected.costs))
    self.economyDetailDescription:SetText(reason or selected.description)
    self.economyDetailDescription:SetStyle({ fontColor = reason and { 255, 112, 112, 255 } or WHITE })
    self.economyDetailEffect:SetText(cost and EconomySkills.GetEffectText(selected, level + 1) or "已获得全部效果")
    self.economyDetailCost:SetText(cost and ("消耗 " .. tostring(cost) .. " 金币") or "该节点已满级")
    self.economyDetailCost:SetStyle({ fontColor = cost and (self.battle.gold >= cost and GOLD or { 255, 105, 105, 255 }) or MUTED })
    self.economyUpgradeButton:SetText(cost and (reason and "查看前置条件" or "点亮 / 升级") or "已满级")
    self.economyUpgradeButton:SetDisabled(cost == nil)

    local stats = self.battle:GetStats()
    self.economyOddsLabel:SetText(
        "当前掉落概率\n\n"
        .. "双倍奖励  " .. percent(stats.rewardDoubleChance) .. "\n"
        .. "三倍奖励  " .. percent(stats.rewardTripleChance) .. "\n"
        .. "四倍奖励  " .. percent(stats.rewardQuadChance) .. "\n"
        .. "超级大奖  " .. percent(stats.jackpotChance) .. "（×" .. tostring(stats.jackpotMultiplier) .. "）\n\n"
        .. "精英怪额外概率  " .. percent(stats.eliteChanceBonus)
    )
    self.economyFeedback:SetVisible((self.economyFeedbackTimer or 0) > 0)
    self.economyFeedback:SetText(self.economyFeedbackText or "")
end

function EconomyPage.Build(self)
    local p = function(value) return self:P(value) end
    self.economyNodes = {}
    for index = 1, #EconomySkills.Definitions do
        local definition = EconomySkills.Definitions[index]
        self.economyNodes[#self.economyNodes + 1] = {
            id = definition.id, definition = definition, icon = definition.icon, parents = definition.parents,
            x = p(definition.x + 50), y = p(definition.y + 210), size = p(76),
            state = "locked", level = 0, revealed = #definition.parents == 0,
        }
    end

    self.economyCanvas = SkillCanvas {
        position = "absolute", left = p(20), top = p(180), width = p(950), height = p(850),
        nodes = self.economyNodes, minPanX = p(-260), maxPanX = p(260), minPanY = p(-400), maxPanY = p(280),
        minZoom = 0.72, maxZoom = 2.0, zoom = 1, hitPadding = p(34), tapSlop = p(34), doubleTapInterval = 650,
        onNodeClick = function(node)
            if not node.revealed then return end
            self.selectedEconomySkill = node.id
            EconomyPage.Refresh(self)
        end,
        onNodeDoubleTap = function(node)
            if node.revealed then EconomyPage.TryUpgrade(self, node.id, "double_tap") end
        end,
        onNodeHover = function(node)
            if node and node.revealed then
                self.selectedEconomySkill = node.id
                EconomyPage.Refresh(self)
            end
        end,
    }

    self.economyDetailTitle = UI.Label {
        text = "", pointerEvents = "none", position = "absolute", left = p(24), top = p(24), width = p(422), height = p(48),
        fontSize = p(27), fontWeight = "bold", fontColor = GOLD, textAlign = "center",
    }
    self.economyDetailDescription = UI.Label {
        text = "", pointerEvents = "none", position = "absolute", left = p(28), top = p(82), width = p(414), height = p(108),
        fontSize = p(20), fontColor = WHITE, textAlign = "center", whiteSpace = "normal",
    }
    self.economyDetailEffect = UI.Label {
        text = "", pointerEvents = "none", position = "absolute", left = p(28), top = p(202), width = p(414), height = p(45),
        fontSize = p(22), fontWeight = "bold", fontColor = { 125, 233, 88, 255 }, textAlign = "center",
    }
    self.economyDetailCost = UI.Label {
        text = "", pointerEvents = "none", position = "absolute", left = p(28), top = p(252), width = p(414), height = p(42),
        fontSize = p(22), fontWeight = "bold", fontColor = GOLD, textAlign = "center",
    }
    self.economyUpgradeButton = self:ImageButton("点亮 / 升级", 100, 310, 270, 64, ORANGE_BUTTON, function()
        EconomyPage.TryUpgrade(self, self.selectedEconomySkill, "detail_button")
    end)
    self.economyOddsLabel = UI.Label {
        text = "", pointerEvents = "none", position = "absolute", left = p(28), top = p(400), width = p(414), height = p(270),
        fontSize = p(20), fontColor = WHITE, textAlign = "left", padding = p(20),
        backgroundColor = { 8, 6, 12, 230 }, borderColor = { 115, 86, 135, 255 }, borderWidth = p(2),
    }
    local detailPanel = UI.Panel {
        position = "absolute", left = p(1000), top = p(180), width = p(470), height = p(700),
        backgroundColor = PANEL, borderColor = BORDER, borderWidth = p(2),
        children = {
            self.economyDetailTitle, self.economyDetailDescription, self.economyDetailEffect,
            self.economyDetailCost, self.economyUpgradeButton, self.economyOddsLabel,
        },
    }
    self.economyFeedback = UI.Label {
        text = "", visible = false, pointerEvents = "none", position = "absolute", left = p(1000), top = p(900), width = p(470), height = p(70),
        fontSize = p(19), fontWeight = "bold", fontColor = GOLD, textAlign = "center",
        backgroundColor = { 8, 6, 12, 235 }, borderColor = BORDER, borderWidth = p(2), padding = p(8),
    }
    self.economyPage = UI.Panel {
        visible = false, position = "absolute", left = 0, top = 0, width = p(1520), height = p(1080),
        backgroundColor = { 12, 8, 17, 255 },
        children = {
            UI.Label {
                text = "财富技能树 · 用金币投资金币成长", pointerEvents = "none",
                position = "absolute", left = p(220), top = p(118), width = p(1080), height = p(48),
                fontSize = p(27), fontWeight = "bold", fontColor = GOLD, textAlign = "center",
            },
            UI.Label {
                text = "单击节点查看 → 点右侧升级　也可双击　双指缩放 / 单指拖动", pointerEvents = "none",
                position = "absolute", left = p(220), top = p(153), width = p(1080), height = p(32),
                fontSize = p(17), fontColor = { 219, 201, 236, 255 }, textAlign = "center",
            },
            self.economyCanvas, detailPanel, self.economyFeedback,
        },
    }
    return self.economyPage
end

function EconomyPage.Update(self, dt)
    self.economyFeedbackTimer = math.max(0, (self.economyFeedbackTimer or 0) - (tonumber(dt) or 0))
    if self.economyFeedback then self.economyFeedback:SetVisible(self.economyFeedbackTimer > 0) end
end

return EconomyPage
