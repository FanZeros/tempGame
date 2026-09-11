local UI = require("urhox-libs/UI")
local Skills = require("nightgate.Skills")
local UIData = require("nightgate.OriginalUIData")
local SkillCanvas = require("nightgate.SkillCanvas")

local SkillPage = {}

local TRANSPARENT = { 0, 0, 0, 0 }
local WHITE = { 241, 236, 220, 255 }
local TOPBAR_UI = "image/nightgate/ui/topbar/"
local ORANGE_BUTTON = "image/nightgate/ui/1_orange_button_s.png"

function SkillPage.GetNode(self, skillId)
    for index = 1, #self.skillNodes do
        if self.skillNodes[index].id == skillId then return self.skillNodes[index] end
    end
    return nil
end

function SkillPage.PositionDetail(self, skillId, locked)
    if not skillId or not self.skillCanvas or not self.skillDetail then return end
    local selectedNode = self:GetSkillNode(skillId)
    if not selectedNode then return end

    local width = self:P(354)
    local height = self:P(locked and 304 or 332)
    local canvasTop = self:P(110)
    local gap = self:P(10)
    local zoom = self.skillCanvas:GetZoom()
    local centerX = self.skillCanvas.panX_ + (selectedNode.x + selectedNode.size * 0.5) * zoom
    local nodeTop = canvasTop + self.skillCanvas.panY_ + selectedNode.y * zoom
    local nodeHeight = selectedNode.size * zoom
    local left = centerX - width * 0.5
    local top = nodeTop - height - gap

    left = math.max(self:P(8), math.min(self:P(1520) - width - self:P(8), left))
    if top < canvasTop + self:P(8) then
        top = nodeTop + nodeHeight + gap
    end
    top = math.max(canvasTop + self:P(8), math.min(self:P(1080) - height - self:P(8), top))
    self.skillDetail:SetStyle({ left = math.floor(left + 0.5), top = math.floor(top + 0.5), height = height })
end

function SkillPage.TryUpgrade(self, skillId, source)
    local node = self:GetSkillNode(skillId)
    if not node or not node.revealed then
        self:ShowSkillFeedback("无法加点：该节点尚未显露", false)
        return false
    end
    self.pinnedSkill = node.id
    self.selectedSkill = node.id
    self.skillDetail:SetVisible(true)
    local cost = Skills.GetCost(self.battle.skillLevels, node.id)
    local ok = self.battle:TryUpgrade(node.id)
    local definition = Skills.GetDefinition(node.id)
    local level = Skills.GetLevel(self.battle.skillLevels, node.id)
    local message
    if ok then
        message = (definition and definition.name or "技能") .. " 已升至 Lv." .. tostring(level)
            .. (cost and ("，消耗 " .. tostring(cost) .. " 金币") or "")
        if node.id == "0_0_0" and level == 1 then
            message = message .. "；弓箭手分支已出现"
        elseif node.id == "4_1_1" and level == 1 then
            message = message .. "；弓箭手自动攻击已开启"
        end
    else
        message = "无法加点：" .. tostring(self.battle.message or "条件未满足")
    end
    print("SkillUpgrade source=" .. tostring(source or "unknown") .. " id=" .. tostring(node.id)
        .. " ok=" .. tostring(ok) .. " gold=" .. tostring(math.floor(self.battle.gold or 0)))
    self.skillCanvas:FlashNode(node.id, ok)
    self:ShowSkillFeedback(message, ok)
    self:Refresh(true)
    return ok
end

function SkillPage.ShowFeedback(self, message, success)
    self.skillFeedbackText = tostring(message or "")
    self.skillFeedbackSuccess = success == true
    self.skillFeedbackTimer = 2.2
    if self.skillActionMessage then
        self.skillActionMessage:SetText(self.skillFeedbackText)
        self.skillActionMessage:SetStyle({
            fontColor = self.skillFeedbackSuccess and { 132, 255, 88, 255 } or { 255, 105, 105, 255 },
            borderColor = self.skillFeedbackSuccess and { 102, 203, 57, 255 } or { 206, 66, 66, 255 },
        })
        self.skillActionMessage:SetVisible(true)
    end
end

function SkillPage.Refresh(self)
    for index = 1, #self.skillNodes do
        local node = self.skillNodes[index]
        node.level = Skills.GetLevel(self.battle.skillLevels, node.id)
        node.state = Skills.GetNodeState(self.battle.skillLevels, node.definition, self.battle.bestNight)
        node.revealed = Skills.IsRevealed(self.battle.skillLevels, node.definition)
    end
    local selectedDefinition = self.selectedSkill and Skills.GetDefinition(self.selectedSkill) or nil
    if selectedDefinition and not Skills.IsRevealed(self.battle.skillLevels, selectedDefinition) then
        self.selectedSkill = nil
        self.pinnedSkill = nil
        self.hoveredSkill = nil
        self.skillDetail:SetVisible(false)
    end
    local rootLevel = Skills.GetLevel(self.battle.skillLevels, "0_0_0")
    local archerLevel = Skills.GetLevel(self.battle.skillLevels, "4_1_1")
    if rootLevel <= 0 then
        self.skillGestureHint:SetText("单击中央技能 → 点“点亮 / 升级”（3金币）　也可双击")
        self.skillCanvas:SetAttention("0_0_0")
    elseif archerLevel <= 0 then
        self.skillGestureHint:SetText("单击闪烁的弓箭节点 → 点“点亮 / 升级”（6金币）")
        self.skillCanvas:SetAttention("4_1_1")
    else
        self.skillGestureHint:SetText("单击节点后点升级按钮　也可双击　双指缩放　单指拖动")
        self.skillCanvas:SetAttention(nil)
    end
    self.skillCanvas:SetSelected(self.selectedSkill)
    if self.selectedSkill then
        local definition = Skills.GetDefinition(self.selectedSkill)
        local level = Skills.GetLevel(self.battle.skillLevels, self.selectedSkill)
        local cost = Skills.GetCost(self.battle.skillLevels, self.selectedSkill)
        local reason = Skills.GetUnlockReason(self.battle.skillLevels, definition, self.battle.bestNight)
        local locked = reason ~= nil
        local bottomTop = locked and 182 or 210
        local effectLevel = cost and (level + 1) or math.max(1, level)
        self.skillDetailTitle:SetText(definition.name .. "(" .. tostring(level) .. "/" .. tostring(#definition.costs) .. ")")
        self.skillDetailText:SetText(reason or Skills.GetEffectText(definition, effectLevel))
        self.skillDetailText:SetStyle({
            top = self:P(65), height = self:P(bottomTop - 65),
            fontColor = locked and { 219, 211, 205, 255 } or { 116, 218, 61, 255 },
        })
        self.skillDetailDividerBottom:SetStyle({ top = self:P(bottomTop) })
        local showCost = cost ~= nil
        self.skillDetailCostIcon:SetVisible(showCost)
        self.skillDetailCostIcon:SetStyle({ top = self:P(bottomTop + 10) })
        self.skillDetailCost:SetVisible(showCost)
        self.skillDetailCost:SetText(showCost and tostring(cost) or "")
        self.skillDetailCost:SetStyle({
            top = self:P(bottomTop + 7),
            fontColor = self.battle.gold >= (cost or 0) and WHITE or { 224, 91, 91, 255 },
        })
        self.skillDetailHint:SetVisible(not showCost)
        self.skillDetailHint:SetText(showCost and "" or "已满级")
        self.skillDetailHint:SetStyle({ top = self:P(bottomTop + 6) })
        if cost then
            self.skillUpgradeButton:SetText(locked and "查看解锁条件" or "点亮 / 升级")
            self.skillUpgradeButton:SetDisabled(false)
        else
            self.skillUpgradeButton:SetText("已满级")
            self.skillUpgradeButton:SetDisabled(true)
        end
        self.skillUpgradeButton:SetStyle({
            left = self:P(42), top = self:P(bottomTop + 45), width = self:P(270), height = self:P(62),
        })
        self:PositionSkillDetail(self.selectedSkill, locked)
    end
end

function SkillPage.Build(self)
    local p = function(v) return self:P(v) end
    local treeScale = UIData.skillPrefabScale * (4 / 3)
    local nodeSize = UIData.skillNodeSize * (4 / 3)
    for index = 1, #Skills.Definitions do
        local definition = Skills.Definitions[index]
        local source = UIData.skillPositions[definition.id] or definition.position
        if source then
            self.skillNodes[#self.skillNodes + 1] = {
                id = definition.id, definition = definition, icon = definition.icon, parents = definition.parents,
                x = p(UIData.skillOriginX - nodeSize * 0.5 + source[1] * treeScale),
                y = p(UIData.skillOriginY - UIData.topBarHeight - nodeSize * 0.5 - source[2] * treeScale),
                size = p(nodeSize), state = "locked", level = 0, revealed = #definition.parents == 0,
            }
        end
    end
    self.skillCanvas = SkillCanvas {
        position = "absolute", left = 0, top = p(110), width = p(1520), height = p(970), nodes = self.skillNodes,
        minPanX = p(-240), maxPanX = p(240), minPanY = p(-620), maxPanY = p(360),
        minZoom = 0.7, maxZoom = 2.2, zoom = 1,
        hitPadding = p(34), tapSlop = p(34), doubleTapInterval = 650,
        onPanChanged = function(_, _, zoom)
            if self.skillZoomLabel then
                self.skillZoomLabel:SetText(tostring(math.floor((zoom or 1) * 100 + 0.5)) .. "%")
            end
            if self.selectedSkill and self.skillDetail and self.skillDetail.props.visible then
                local definition = Skills.GetDefinition(self.selectedSkill)
                local reason = definition and Skills.GetUnlockReason(self.battle.skillLevels, definition, self.battle.bestNight) or nil
                self:PositionSkillDetail(self.selectedSkill, reason ~= nil)
            end
        end,
        onNodeClick = function(node)
            if not node.revealed then return end
            self.pinnedSkill = node.id
            self.selectedSkill = node.id
            self.skillDetail:SetVisible(true)
            self:Refresh(true)
        end,
        onNodeDoubleTap = function(node)
            if not node.revealed then return end
            SkillPage.TryUpgrade(self, node.id, "double_tap")
        end,
        onNodeHover = function(node)
            self.hoveredSkill = node and node.id or nil
            self.selectedSkill = self.hoveredSkill or self.pinnedSkill
            self.skillDetail:SetVisible(self.selectedSkill ~= nil)
            self:RefreshSkillTree()
        end,
    }
    self.skillDetailTitle = UI.Label { text = "", pointerEvents = "none", position = "absolute", left = p(8), top = p(8), width = p(338), height = p(43), fontSize = p(25), fontWeight = "bold", fontColor = { 163, 168, 255, 255 }, textAlign = "center" }
    self.skillDetailDividerTop = UI.Panel { pointerEvents = "none", position = "absolute", left = p(2), top = p(57), width = p(350), height = p(2), backgroundColor = { 77, 70, 82, 255 } }
    self.skillDetailText = UI.Label { text = "", pointerEvents = "none", position = "absolute", left = p(18), top = p(65), width = p(318), height = p(137), fontSize = p(22), fontColor = { 116, 218, 61, 255 }, textAlign = "center" }
    self.skillDetailDividerBottom = UI.Panel { pointerEvents = "none", position = "absolute", left = p(2), top = p(210), width = p(350), height = p(2), backgroundColor = { 77, 70, 82, 255 } }
    self.skillDetailCostIcon = UI.Panel { pointerEvents = "none", position = "absolute", left = p(126), top = p(220), width = p(28), height = p(28), backgroundImage = "image/nightgate/currency/asset_632cd9da.png", backgroundFit = "contain", backgroundColor = TRANSPARENT }
    self.skillDetailCost = UI.Label { text = "", pointerEvents = "none", position = "absolute", left = p(160), top = p(217), width = p(92), height = p(34), fontSize = p(23), fontColor = { 241, 236, 220, 255 }, textAlign = "left" }
    self.skillDetailHint = UI.Label { text = "", pointerEvents = "none", position = "absolute", left = p(18), top = p(216), width = p(318), height = p(36), fontSize = p(22), fontColor = { 183, 116, 4, 255 }, textAlign = "center" }
    self.skillUpgradeButton = self:ImageButton("点亮 / 升级", 42, 255, 270, 62, ORANGE_BUTTON, function()
        if self.selectedSkill then
            SkillPage.TryUpgrade(self, self.selectedSkill, "detail_button")
        end
    end)
    self.skillDetail = UI.Panel {
        visible = false, pointerEvents = "box-none", position = "absolute", left = p(1125), top = p(205), width = p(354), height = p(332),
        backgroundColor = { 9, 6, 10, 252 }, borderColor = { 77, 70, 82, 255 }, borderWidth = p(2),
        children = { self.skillDetailTitle, self.skillDetailDividerTop, self.skillDetailText, self.skillDetailDividerBottom, self.skillDetailCostIcon, self.skillDetailCost, self.skillDetailHint, self.skillUpgradeButton },
    }
    self.skillGestureHint = UI.Label {
        text = "第一个技能 3 金币　单击节点后点升级按钮　也可双击",
        pointerEvents = "none", position = "absolute", left = p(300), top = p(120), width = p(900), height = p(48),
        fontSize = p(23), fontWeight = "bold", fontColor = { 255, 224, 92, 255 }, textAlign = "center",
        backgroundColor = { 10, 7, 13, 225 }, borderColor = { 226, 161, 40, 255 }, borderWidth = p(2),
    }
    self.skillZoomLabel = UI.Label {
        text = "100%", pointerEvents = "none", position = "absolute", left = p(1300), top = p(122), width = p(130), height = p(42),
        fontSize = p(21), fontWeight = "bold", fontColor = { 211, 203, 255, 255 }, textAlign = "center",
        backgroundColor = { 10, 7, 13, 210 }, borderColor = { 102, 90, 130, 255 }, borderWidth = p(2),
    }
    self.skillActionMessage = UI.Label {
        text = self.skillFeedbackText, visible = self.skillFeedbackTimer > 0, pointerEvents = "none",
        position = "absolute", left = p(380), top = p(176), width = p(760), height = p(52),
        fontSize = p(24), fontWeight = "bold", textAlign = "center",
        fontColor = self.skillFeedbackSuccess and { 132, 255, 88, 255 } or { 255, 105, 105, 255 },
        backgroundColor = { 10, 7, 13, 238 },
        borderColor = self.skillFeedbackSuccess and { 102, 203, 57, 255 } or { 206, 66, 66, 255 }, borderWidth = p(2),
    }
    self.skillPage = UI.Panel {
        position = "absolute", left = 0, top = 0, width = p(1520), height = p(1080),
        children = {
            self.skillCanvas, self.skillGestureHint, self.skillZoomLabel, self.skillActionMessage, self.skillDetail,
            self:ImageButton("", 1450, 132, 60, 60, TOPBAR_UI .. "skill_tip.png", function() end),
        },
    }
    return self.skillPage
end

return SkillPage
