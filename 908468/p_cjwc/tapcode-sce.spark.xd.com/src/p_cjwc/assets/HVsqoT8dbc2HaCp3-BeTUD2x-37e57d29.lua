local UI = require("urhox-libs/UI")
local Config = require("nightgate.Config")
local Skills = require("nightgate.Skills")
local Equipment = require("nightgate.Equipment")
local Prestige = require("nightgate.Prestige")
local UIData = require("nightgate.OriginalUIData")
local SkillCanvas = require("nightgate.SkillCanvas")
local SkillPage = require("nightgate.SkillPage")
local EconomyPage = require("nightgate.EconomyPage")
local SettingsPage = require("nightgate.SettingsPage")
local Tutorial = require("nightgate.Tutorial")
local AnimatedButton = require("nightgate.AnimatedButton")
local CharacterDetails = require("nightgate.CharacterDetails")
local Save = require("nightgate.Save")
local RewardAds = require("nightgate.RewardAds")

---@type any
local sdkApi = rawget(_G, "sdk")

local AppUI = {}
AppUI.__index = AppUI

local WHITE = { 241, 236, 220, 255 }
local MUTED = { 172, 157, 172, 255 }
local DARK = { 13, 8, 17, 255 }
local PANEL = { 24, 15, 28, 250 }
local BORDER = { 89, 61, 91, 255 }
local GOLD = { 226, 161, 40, 255 }
local TRANSPARENT = { 0, 0, 0, 0 }

local QUALITY_COLORS = {
    [0] = { 146, 146, 146, 255 }, [1] = { 66, 186, 75, 255 },
    [2] = { 70, 119, 220, 255 }, [3] = { 157, 72, 208, 255 },
    [4] = { 226, 142, 42, 255 }, [5] = { 218, 64, 66, 255 },
}

local BUTTON = "image/nightgate/ui/1_basic_button.png"
local BLUE_BUTTON = "image/nightgate/ui/1_blue_button_s.png"
local GRAY_BUTTON = "image/nightgate/ui/1_gray_button_s.png"
local ORANGE_BUTTON = "image/nightgate/ui/1_orange_button_s.png"
local VIOLET_BUTTON = "image/nightgate/ui/1_violet_button_s.png"
local EQUIPMENT_UI = "image/nightgate/ui/equipment/"
local EQUIPMENT_CELL_BG = EQUIPMENT_UI .. "equipment_cell_bg.png"
local EQUIPMENT_CELL_BORDER = EQUIPMENT_UI .. "equipment_cell_border.png"
local EQUIPMENT_ADD_BG = EQUIPMENT_UI .. "equipment_add_bg.png"
local EQUIPMENT_ADD_ICON = EQUIPMENT_UI .. "equipment_add_icon.png"
local EQUIPMENT_DETAIL_WINDOW = EQUIPMENT_UI .. "detail_window.png"
local EQUIPMENT_DETAIL_CLOSE = EQUIPMENT_UI .. "detail_close.png"
local EQUIPMENT_DETAIL_LOCK = EQUIPMENT_UI .. "detail_lock_button.png"
local EQUIPMENT_DETAIL_BUTTON = EQUIPMENT_UI .. "detail_button.png"
local EQUIPMENT_DETAIL_ACTION = EQUIPMENT_UI .. "detail_action_button.png"
local TOPBAR_UI = "image/nightgate/ui/topbar/"
local ROLE_LOCK = "image/nightgate/ui/lock.png"

local RESOURCE_INFO = {
    gold = {
        title = "金币", icon = "image/nightgate/currency/asset_632cd9da.png",
        description = "击杀怪物掉落\n\n用于强化技能树",
    },
    crystal = {
        title = "晶石", icon = "image/nightgate/currency/asset_90278eb1.png",
        description = "击杀晶石怪物、宝箱怪掉落\n\n用于快速强化",
    },
    shard = {
        title = "装备碎片", icon = "image/nightgate/currency/asset_b85ca26f.png",
        description = "通过分解未装备且未锁定的装备获得\n\n用于强化已经装配的装备",
    },
}

local DIRECTION_IMAGES = {
    EQUIPMENT_UI .. "direction_up.png",
    EQUIPMENT_UI .. "direction_right.png",
    EQUIPMENT_UI .. "direction_down.png",
    EQUIPMENT_UI .. "direction_left.png",
}

local function transparentButton(props)
    props.backgroundColor = TRANSPARENT
    props.borderColor = TRANSPARENT
    props.borderWidth = 0
    props.backgroundImageOpacity = 0
    props.text = props.text or ""
    return AnimatedButton(props)
end

function AppUI.New(battle, audioManager)
    local self = setmetatable({}, AppUI)
    self.battle = battle
    self.audioManager = audioManager
    self.screen = "mainmenu"
    self.selectedTab = "skills"
    self.selectedSkill = nil
    self.pinnedSkill = nil
    self.hoveredSkill = nil
    self.selectedEquip = nil
    self.selectedInventory = nil
    self.equipmentDetailTarget = nil
    self.equipmentDrag = nil
    self.updateTimer = 0
    self.recycleConfirmTimer = 0
    self.prestigeConfirmTimer = 0
    self.rewardAds = RewardAds.New(battle, sdkApi)
    self.resultAdStatusRunId = nil
    self.supplyAdMessage = ""
    self.supplyAdMessageTimer = 0
    self.supplyAdMessageError = false
    self.skillHintPulse = 0
    self.skillFeedbackTimer = 0
    self.skillFeedbackText = ""
    self.skillFeedbackSuccess = false
    self.resourceInfoKey = nil
    self.difficultySelected = battle.finalDifficultySelected or 0
    self.skillNodes = {}
    self.prestigeNodes = {}
    self.selectedPrestigeSkill = "p_root"
    self.selectedEconomySkill = "e_root"
    self.economyFeedbackTimer = 0
    self.economyFeedbackText = ""
    self.characterRows = {}
    self.inventoryButtons = {}
    self:UpdateViewportMetrics()
    self:Build()
    return self
end

function AppUI:UpdateViewportMetrics()
    local viewportW, viewportH = UI.GetViewportSize()
    viewportW = math.max(1, tonumber(viewportW) or UIData.designWidth)
    viewportH = math.max(1, tonumber(viewportH) or UIData.designHeight)
    self.viewportW = viewportW
    self.viewportH = viewportH
    self.scale = math.max(0.01, math.min(viewportW / UIData.designWidth, viewportH / UIData.designHeight))
    self.offsetX = (viewportW - UIData.designWidth * self.scale) * 0.5
    self.offsetY = (viewportH - UIData.designHeight * self.scale) * 0.5
end

function AppUI:P(value)
    return math.floor(value * self.scale + 0.5)
end

function AppUI:Rect(x, y, w, h)
    return { position = "absolute", left = self:P(x), top = self:P(y), width = self:P(w), height = self:P(h) }
end

function AppUI:ImageButton(text, x, y, w, h, image, onClick)
    local props = self:Rect(x, y, w, h)
    props.text = text
    props.fontSize = self:P(23)
    props.fontWeight = "bold"
    props.fontColor = WHITE
    props.backgroundImage = image or BUTTON
    props.backgroundFit = "stretch"
    props.backgroundColor = TRANSPARENT
    props.borderWidth = 0
    props.padding = 0
    props.onClick = onClick
    return AnimatedButton(props)
end

function AppUI:GetSkillNode(skillId)
    return SkillPage.GetNode(self, skillId)
end

function AppUI:PositionSkillDetail(skillId, locked)
    SkillPage.PositionDetail(self, skillId, locked)
end

function AppUI:ShowSkillFeedback(message, success)
    SkillPage.ShowFeedback(self, message, success)
end

function AppUI:SetAudioVolume(kind, percent)
    SettingsPage.SetVolume(self, kind, percent)
end

function AppUI:RefreshSettings()
    SettingsPage.Refresh(self)
end

function AppUI:OpenSettings()
    SettingsPage.Open(self)
end

function AppUI:CloseSettings()
    SettingsPage.Close(self)
end

function AppUI:BuildMainMenu()
    local p = function(v) return self:P(v) end
    self.mainMenuMessage = UI.Label {
        text = "", position = "absolute", left = p(735), top = p(805), width = p(450), height = p(52),
        fontSize = p(21), fontColor = WHITE, textAlign = "center", visible = false,
        backgroundColor = { 12, 8, 17, 225 }, borderColor = BORDER, borderWidth = p(2),
    }
    self.newGameConfirm = UI.Panel {
        visible = false, position = "absolute", left = 0, top = 0, width = p(1920), height = p(1080),
        backgroundColor = { 0, 0, 0, 205 },
        children = {
            UI.Panel {
                position = "absolute", left = p(650), top = p(300), width = p(620), height = p(465),
                backgroundImage = "image/nightgate/ui/popup_window.png", backgroundFit = "stretch", backgroundColor = TRANSPARENT,
                children = {
                    UI.Label { text = "开始新游戏？", position = "absolute", left = p(95), top = p(52), width = p(430), height = p(52), fontSize = p(34), fontWeight = "bold", fontColor = WHITE, textAlign = "center" },
                    UI.Label {
                        text = "以下数据会全部重置：\n技能树、快速升级、装备、货币、存活天数、转生与天赋\n\n新存档建立后，原存档不可恢复。",
                        position = "absolute", left = p(70), top = p(125), width = p(480), height = p(190),
                        fontSize = p(22), fontColor = { 222, 205, 214, 255 }, textAlign = "center",
                    },
                    self:ImageButton("确认新存档", 80, 335, 210, 72, ORANGE_BUTTON, function()
                        self.newGameConfirm:SetVisible(false)
                        self:EnterGame(true)
                    end),
                    self:ImageButton("取消", 330, 335, 210, 72, GRAY_BUTTON, function() self.newGameConfirm:SetVisible(false) end),
                },
            },
        },
    }
    self.mainMenu = UI.Panel {
        position = "absolute", left = 0, top = 0, width = p(1920), height = p(1080),
        backgroundImage = "image/nightgate/ui/home_cn_clean.png", backgroundFit = "stretch",
        children = {
            transparentButton { position = "absolute", left = p(810), top = p(466), width = p(300), height = p(69), onClick = function() self:EnterGame() end },
            transparentButton { position = "absolute", left = p(810), top = p(545), width = p(300), height = p(70), onClick = function() self.newGameConfirm:SetVisible(true) end },
            transparentButton { position = "absolute", left = p(810), top = p(626), width = p(300), height = p(69), onClick = function() self:OpenSettings() end },
            transparentButton { position = "absolute", left = p(810), top = p(705), width = p(300), height = p(70), onClick = function() self:ShowMainMenuMessage("请使用手机系统返回键退出游戏") end },
            self.mainMenuMessage, self.newGameConfirm,
        },
    }
    return self.mainMenu
end

function AppUI:ShowMainMenuMessage(text)
    self.mainMenuMessage:SetText(text)
    self.mainMenuMessage:SetVisible(true)
end

function AppUI:EnterGame(newGame)
    if newGame then
        self.battle:StartNewSave()
        Save.Store(self.battle)
        self.selectedTab = "skills"
        self.selectedSkill = nil
        self.selectedEquip = nil
        self.selectedInventory = nil
    end
    self.screen = "game"
    self:Refresh(true)
end

function AppUI:BuildTopBar()
    local p = function(v) return self:P(v) end
    self.goldLabel = UI.Label { text = "0", position = "absolute", left = p(816), top = p(25), width = p(125), height = p(42), fontSize = p(27), fontColor = WHITE, textAlign = "left" }
    self.crystalLabel = UI.Label { text = "0", position = "absolute", left = p(1008), top = p(25), width = p(105), height = p(42), fontSize = p(27), fontColor = WHITE, textAlign = "left" }
    self.shardLabel = UI.Label { text = "0", position = "absolute", left = p(1193), top = p(25), width = p(105), height = p(42), fontSize = p(27), fontColor = WHITE, textAlign = "left" }
    self.skillTabButton = self:ImageButton("技能树", 15, 15, 150, 70, BLUE_BUTTON, function() self.selectedTab = "skills"; self:HideResourceInfo(); self:Refresh(true) end)
    self.equipTabButton = self:ImageButton("装备", 180, 15, 150, 70, BLUE_BUTTON, function() self.selectedTab = "equipment"; self:HideResourceInfo(); self:Refresh(true) end)
    self.economyTabButton = self:ImageButton("财富", 345, 15, 150, 70, BLUE_BUTTON, function() self.selectedTab = "economy"; self:HideResourceInfo(); self:Refresh(true) end)
    self.prestigeTabButton = self:ImageButton("转生", 510, 15, 150, 70, BLUE_BUTTON, function() self.selectedTab = "prestige"; self:HideResourceInfo(); self:Refresh(true) end)
    return UI.Panel {
        position = "absolute", left = 0, top = 0, width = p(1520), height = p(110),
        backgroundColor = { 7, 5, 9, 255 },
        children = {
            self.skillTabButton, self.equipTabButton, self.economyTabButton,
            self.prestigeTabButton,
            UI.Panel { position = "absolute", left = p(775), top = p(27), width = p(36), height = p(36), backgroundImage = "image/nightgate/currency/asset_632cd9da.png", backgroundFit = "contain" }, self.goldLabel,
            UI.Panel { position = "absolute", left = p(967), top = p(27), width = p(36), height = p(36), backgroundImage = "image/nightgate/currency/asset_90278eb1.png", backgroundFit = "contain" }, self.crystalLabel,
            UI.Panel { position = "absolute", left = p(1152), top = p(27), width = p(36), height = p(36), backgroundImage = "image/nightgate/currency/asset_b85ca26f.png", backgroundFit = "contain" }, self.shardLabel,
            transparentButton { position = "absolute", left = p(760), top = p(12), width = p(185), height = p(70), onClick = function() self:ShowResourceInfo("gold") end },
            transparentButton { position = "absolute", left = p(952), top = p(12), width = p(165), height = p(70), onClick = function() self:ShowResourceInfo("crystal") end },
            transparentButton { position = "absolute", left = p(1137), top = p(12), width = p(165), height = p(70), onClick = function() self:ShowResourceInfo("shard") end },
            self:ImageButton("", 1360, 10, 43, 74, TOPBAR_UI .. "quest.png", function() self.screen = "mainmenu"; self:Refresh(true) end),
            self:ImageButton("", 1413, 10, 43, 74, TOPBAR_UI .. "options.png", function() self:OpenSettings() end),
            self:ImageButton("", 1466, 10, 43, 74, TOPBAR_UI .. "achievement.png", function() end),
            UI.Panel { position = "absolute", left = 0, top = p(98), width = p(1520), height = p(12), backgroundImage = TOPBAR_UI .. "separator.png", backgroundFit = "stretch", backgroundColor = TRANSPARENT },
        },
    }
end

function AppUI:BuildResourceInfoModal()
    local p = function(v) return self:P(v) end
    self.resourceInfoIcon = UI.Panel {
        position = "absolute", left = p(66), top = p(76), width = p(82), height = p(82),
        backgroundFit = "contain", backgroundColor = TRANSPARENT,
    }
    self.resourceInfoTitle = UI.Label {
        text = "装备碎片", position = "absolute", left = p(175), top = p(69), width = p(360), height = p(55),
        fontSize = p(34), fontWeight = "bold", fontColor = GOLD,
    }
    self.resourceInfoDescription = UI.Label {
        text = "", position = "absolute", left = p(175), top = p(130), width = p(385), height = p(105),
        fontSize = p(23), fontColor = WHITE,
    }
    self.resourceInfoCloseButton = self:ImageButton("关闭", 210, 280, 200, 65, GRAY_BUTTON, function()
        self:HideResourceInfo()
    end)
    self.resourceInfoModal = UI.Panel {
        visible = false, position = "absolute", left = p(720), top = p(125), width = p(620), height = p(365),
        backgroundImage = "image/nightgate/ui/popup_window.png", backgroundFit = "stretch", backgroundColor = TRANSPARENT,
        children = {
            self.resourceInfoIcon, self.resourceInfoTitle, self.resourceInfoDescription, self.resourceInfoCloseButton,
        },
    }
    return self.resourceInfoModal
end

function AppUI:ShowResourceInfo(key)
    local info = RESOURCE_INFO[key]
    if not info or not self.resourceInfoModal then return end
    self.resourceInfoKey = key
    self.resourceInfoIcon:SetStyle({ backgroundImage = info.icon })
    self.resourceInfoTitle:SetText(info.title)
    self.resourceInfoDescription:SetText(info.description)
    self.resourceInfoModal:SetVisible(true)
end

function AppUI:HideResourceInfo()
    self.resourceInfoKey = nil
    if self.resourceInfoModal then self.resourceInfoModal:SetVisible(false) end
end

function AppUI:BuildPrestigePage()
    local p = function(v) return self:P(v) end
    local nodeSize = 78
    for index = 1, #Prestige.Definitions do
        local definition = Prestige.Definitions[index]
        self.prestigeNodes[#self.prestigeNodes + 1] = {
            id = definition.id, definition = definition, icon = definition.icon, parents = definition.parents,
            x = p(definition.x), y = p(definition.y), size = p(nodeSize), state = "locked", level = 0,
            revealed = #definition.parents == 0,
        }
    end

    self.prestigePointLabel = UI.Label {
        text = "", position = "absolute", left = p(38), top = p(23), width = p(650), height = p(58),
        fontSize = p(30), fontWeight = "bold", fontColor = { 216, 168, 255, 255 },
    }
    self.prestigeRewardLabel = UI.Label {
        text = "", position = "absolute", left = p(760), top = p(27), width = p(700), height = p(50),
        fontSize = p(23), fontColor = GOLD, textAlign = "right",
    }
    self.prestigeCanvas = SkillCanvas {
        position = "absolute", left = p(35), top = p(100), width = p(930), height = p(820),
        nodes = self.prestigeNodes, minPanX = p(-80), maxPanX = p(80), minPanY = p(-60), maxPanY = p(60),
        onNodeHover = function(node)
            if node then
                self.selectedPrestigeSkill = node.id
                self:RefreshPrestige()
            end
        end,
        onNodeClick = function(node)
            self.selectedPrestigeSkill = node.id
            self:RefreshPrestige()
        end,
    }

    self.prestigeDetailTitle = UI.Label {
        text = "黄金火种", position = "absolute", left = p(28), top = p(24), width = p(424), height = p(48),
        fontSize = p(30), fontWeight = "bold", fontColor = WHITE, textAlign = "center",
    }
    self.prestigeDetailLevel = UI.Label {
        text = "", position = "absolute", left = p(30), top = p(76), width = p(420), height = p(34),
        fontSize = p(20), fontColor = { 205, 188, 222, 255 }, textAlign = "center",
    }
    self.prestigeDetailDescription = UI.Label {
        text = "", position = "absolute", left = p(36), top = p(126), width = p(408), height = p(110),
        fontSize = p(21), fontColor = WHITE, textAlign = "center", whiteSpace = "normal", verticalAlign = "top", lineHeight = 1.2,
    }
    self.prestigeDetailEffect = UI.Label {
        text = "", position = "absolute", left = p(36), top = p(242), width = p(408), height = p(55),
        fontSize = p(23), fontWeight = "bold", fontColor = { 126, 223, 75, 255 }, textAlign = "center",
    }
    self.prestigeDetailCost = UI.Label {
        text = "", position = "absolute", left = p(36), top = p(302), width = p(408), height = p(42),
        fontSize = p(20), fontColor = GOLD, textAlign = "center",
    }
    self.prestigeUpgradeButton = self:ImageButton("点亮节点", 105, 356, 270, 70, VIOLET_BUTTON, function()
        if not self.selectedPrestigeSkill then return end
        local ok = self.battle:TryPrestigeUpgrade(self.selectedPrestigeSkill)
        if ok then Save.Store(self.battle) end
        self:Refresh(true)
    end)
    local detailPanel = UI.Panel {
        position = "absolute", left = p(1000), top = p(100), width = p(480), height = p(450),
        backgroundColor = PANEL, borderColor = BORDER, borderWidth = p(2),
        children = {
            self.prestigeDetailTitle, self.prestigeDetailLevel, self.prestigeDetailDescription,
            self.prestigeDetailEffect, self.prestigeDetailCost, self.prestigeUpgradeButton,
        },
    }

    self.prestigeStatusLabel = UI.Label {
        text = "", position = "absolute", left = p(24), top = p(22), width = p(432), height = p(42),
        fontSize = p(23), fontWeight = "bold", fontColor = GOLD, textAlign = "center",
    }
    self.prestigeRitualRewardLabel = UI.Label {
        text = "", position = "absolute", left = p(24), top = p(70), width = p(432), height = p(38),
        fontSize = p(21), fontColor = { 216, 168, 255, 255 }, textAlign = "center",
    }
    self.prestigeMilestoneTitle = UI.Label {
        text = "里程碑祝福", position = "absolute", left = p(28), top = p(104), width = p(424), height = p(28),
        fontSize = p(18), fontWeight = "bold", fontColor = { 216, 168, 255, 255 }, textAlign = "left",
        textStroke = { width = p(1), color = { 8, 5, 12, 255 } },
    }
    self.prestigeMilestoneRows = {}
    local milestoneChildren = { self.prestigeMilestoneTitle }
    local milestoneDetails = {
        "金币/晶石结算 +50% · 晶石怪 +2",
        "闪避 +10% · 双击 +10% · 指针范围 +15%",
        "狂暴 +5% · Boss增伤 +50% · 古龙助战 +1",
    }
    for index = 1, 3 do
        local top = 132 + (index - 1) * 48
        local status = UI.Label {
            text = "", position = "absolute", left = p(28), top = p(top), width = p(424), height = p(23),
            fontSize = p(16), fontWeight = "bold", fontColor = MUTED, textAlign = "left", whiteSpace = "nowrap",
        }
        local detail = UI.Label {
            text = milestoneDetails[index], position = "absolute", left = p(50), top = p(top + 22), width = p(402), height = p(22),
            fontSize = p(14), fontColor = WHITE, textAlign = "left", whiteSpace = "nowrap",
        }
        self.prestigeMilestoneRows[index] = { status = status, detail = detail }
        milestoneChildren[#milestoneChildren + 1] = status
        milestoneChildren[#milestoneChildren + 1] = detail
    end
    self.prestigeKeepLabel = UI.Label {
        text = "永久保留：转生点、转生树、里程碑祝福",
        position = "absolute", left = p(30), top = p(280), width = p(420), height = p(21),
        fontSize = p(14), fontColor = { 242, 155, 133, 255 }, textAlign = "center", whiteSpace = "nowrap",
    }
    self.prestigeResetLabel = UI.Label {
        text = "重置：普通资源、装备、技能与关卡（基础金币 6）",
        position = "absolute", left = p(30), top = p(302), width = p(420), height = p(21),
        fontSize = p(14), fontColor = { 230, 125, 125, 255 }, textAlign = "center", whiteSpace = "nowrap",
    }
    self.prestigeConfirmButton = self:ImageButton("执行转生", 72, 326, 336, 60, ORANGE_BUTTON, function()
        if self.prestigeConfirmTimer > 0 then
            local ok, message = self.battle:PerformPrestige()
            self.prestigeConfirmTimer = 0
            if ok then Save.Store(self.battle) end
            self.battle.message = message or "无法转生"
            self.battle.messageTimer = 2.2
        else
            self.prestigeConfirmTimer = 3
        end
        self:Refresh(true)
    end)
    local ritualChildren = { self.prestigeStatusLabel, self.prestigeRitualRewardLabel }
    for index = 1, #milestoneChildren do
        ritualChildren[#ritualChildren + 1] = milestoneChildren[index]
    end
    ritualChildren[#ritualChildren + 1] = self.prestigeKeepLabel
    ritualChildren[#ritualChildren + 1] = self.prestigeResetLabel
    ritualChildren[#ritualChildren + 1] = self.prestigeConfirmButton
    local ritualPanel = UI.Panel {
        position = "absolute", left = p(1000), top = p(550), width = p(480), height = p(400),
        backgroundColor = PANEL, borderColor = BORDER, borderWidth = p(2),
        children = ritualChildren,
    }
    self.prestigePage = UI.Panel {
        visible = false, position = "absolute", left = 0, top = p(110), width = p(1520), height = p(970),
        backgroundColor = DARK,
        children = {
            self.prestigePointLabel, self.prestigeRewardLabel, self.prestigeCanvas, detailPanel, ritualPanel,
        },
    }
    return self.prestigePage
end

function AppUI:BuildSkillPage()
    return SkillPage.Build(self)
end

function AppUI:BuildSettingsModal()
    return SettingsPage.Build(self)
end

function AppUI:BuildEconomyPage()
    return EconomyPage.Build(self)
end

function AppUI:CreateEquipmentSlot(rowIndex, slotIndex, x, y)
    local p = function(v) return self:P(v) end
    local row = UIData.characterRows[rowIndex]
    local icon = UI.Panel { position = "absolute", left = p(18), top = p(18), width = p(60), height = p(60), backgroundFit = "contain", backgroundColor = TRANSPARENT }
    local border = UI.Panel { position = "absolute", left = 0, top = 0, width = p(95), height = p(95), backgroundImage = EQUIPMENT_CELL_BORDER, backgroundFit = "stretch", backgroundColor = TRANSPARENT }
    local newLabel = UI.Label { text = "new", visible = false, position = "absolute", right = p(1), top = p(2), width = p(50), height = p(20), fontSize = p(14), fontColor = { 255, 100, 34, 255 }, fontWeight = "bold", textAlign = "center" }
    local levelLabel = UI.Label { text = "", position = "absolute", left = p(8), bottom = p(4), width = p(80), height = p(18), fontSize = p(13), fontColor = { 238, 163, 56, 255 }, textAlign = "center" }
    local lockIcon = UI.Panel { visible = false, position = "absolute", right = p(7), top = p(8), width = p(18), height = p(18), backgroundImage = EQUIPMENT_UI .. "equipment_lock.png", backgroundFit = "contain", backgroundColor = TRANSPARENT }
    local button = transparentButton {
        position = "absolute", left = 0, top = 0, width = p(95), height = p(95),
        onClick = function() self.selectedEquip = { wall = row.wall, role = row.role, slot = slotIndex }; self.selectedInventory = nil; self:Refresh(true) end,
        onDoubleTap = function() self:OpenEquipmentDetail({ kind = "equipped", wall = row.wall, role = row.role, slot = slotIndex }) end,
        onLongPress = function() self:OpenEquipmentDetail({ kind = "equipped", wall = row.wall, role = row.role, slot = slotIndex }) end,
    }
    local root = UI.Panel {
        position = "absolute", left = p(x), top = p(y), width = p(95), height = p(95),
        backgroundImage = EQUIPMENT_ADD_BG, backgroundFit = "stretch", backgroundColor = TRANSPARENT,
        children = { border, icon, lockIcon, newLabel, levelLabel, button },
    }
    self.characterRows[rowIndex].slots[slotIndex] = {
        root = root, border = border, icon = icon, lockIcon = lockIcon,
        newLabel = newLabel, levelLabel = levelLabel, button = button,
    }
    return root
end

function AppUI:BuildCharacterRow(index)
    local p = function(v) return self:P(v) end
    local data = UIData.characterRows[index]
    self.characterRows[index] = { data = data, slots = {} }
    local portraitProps = {
        position = "absolute", left = p(42), top = p(33), width = p(70), height = p(70),
        backgroundImage = data.icon, backgroundFit = "contain", backgroundColor = TRANSPARENT,
        borderColor = TRANSPARENT, borderWidth = 0, text = "",
    }
    local portrait
    if data.role == "hero" then
        portraitProps.onClick = function() self.battle:CycleHero(data.wall); self:Refresh(true) end
    else
        portraitProps.onClick = function() self.battle:CycleArcher(data.wall); self:Refresh(true) end
    end
    portrait = AnimatedButton(portraitProps)
    self.characterRows[index].portrait = portrait
    local direction = UI.Panel { position = "absolute", left = p(4), top = p(8), width = p(31), height = p(23), backgroundImage = DIRECTION_IMAGES[data.wall], backgroundFit = "contain", backgroundColor = TRANSPARENT }
    local tip = AnimatedButton {
        position = "absolute", left = p(97), top = p(18), width = p(30), height = p(30), text = "",
        backgroundImage = EQUIPMENT_UI .. "character_tip.png", backgroundFit = "contain", backgroundColor = TRANSPARENT, borderWidth = 0,
        onClick = function() if self.characterDetails then self.characterDetails:Open(index) end end,
    }
    local change = UI.Panel { position = "absolute", left = p(100), top = p(74), width = p(24), height = p(21), backgroundImage = EQUIPMENT_UI .. "character_change.png", backgroundFit = "contain", backgroundColor = TRANSPARENT }
    local roleLock = UI.Panel { visible = false, pointerEvents = "none", position = "absolute", left = p(50), top = p(40), width = p(54), height = p(54), backgroundImage = ROLE_LOCK, backgroundFit = "contain", backgroundColor = TRANSPARENT }
    local lockLabel = UI.Label { text = "未解锁", pointerEvents = "none", position = "absolute", left = p(8), top = p(94), width = p(128), height = p(20), fontSize = p(12), fontColor = { 215, 94, 88, 255 }, textAlign = "center" }
    self.characterRows[index].tip = tip
    self.characterRows[index].change = change
    self.characterRows[index].roleLock = roleLock
    self.characterRows[index].lockLabel = lockLabel
    return UI.Panel {
        position = "absolute", left = 0, top = p((index - 1) * 120), width = p(350), height = p(120),
        backgroundImage = EQUIPMENT_UI .. "character_row_bg.png", backgroundFit = "stretch", backgroundColor = TRANSPARENT,
        children = {
            direction, portrait, tip, change,
            self:CreateEquipmentSlot(index, 1, 135, 13), self:CreateEquipmentSlot(index, 2, 240, 13),
            roleLock, lockLabel,
        },
    }
end

function AppUI:BuildInventory()
    local p = function(v) return self:P(v) end
    local children = {}
    for index = 1, Config.EQUIPMENT_CAPACITY do
        local slot = index
        local col = (index - 1) % 12
        local row = math.floor((index - 1) / 12)
        local icon = UI.Panel { position = "absolute", left = p(17), top = p(17), width = p(52), height = p(52), backgroundFit = "contain", backgroundColor = TRANSPARENT }
        local border = UI.Panel { position = "absolute", left = 0, top = 0, width = p(86), height = p(86), backgroundImage = EQUIPMENT_CELL_BORDER, backgroundFit = "stretch", backgroundColor = TRANSPARENT }
        local newLabel = UI.Label { text = "new", visible = false, position = "absolute", right = p(1), top = p(1), width = p(43), height = p(18), fontSize = p(13), fontColor = { 255, 100, 34, 255 }, fontWeight = "bold", textAlign = "center" }
        local levelLabel = UI.Label { text = "", position = "absolute", left = p(7), bottom = p(3), width = p(72), height = p(16), fontSize = p(12), fontColor = { 238, 163, 56, 255 }, textAlign = "center" }
        local lockIcon = UI.Panel { visible = false, position = "absolute", right = p(6), top = p(7), width = p(16), height = p(16), backgroundImage = EQUIPMENT_UI .. "equipment_lock.png", backgroundFit = "contain", backgroundColor = TRANSPARENT }
        local button = transparentButton {
            position = "absolute", left = 0, top = 0, width = p(86), height = p(86),
            onClick = function()
                if self.battle.inventory[slot] then
                    if self.selectedInventory == slot then
                        local item = Equipment.GetItem(self.battle.inventory[slot])
                        if item then
                            local wall = self.selectedEquip and self.selectedEquip.wall or 1
                            self.battle:EquipInventoryItem(slot, wall)
                        end
                        self.selectedInventory = nil
                    else
                        self.selectedInventory = slot
                    end
                    self:Refresh(true)
                end
            end,
            onDoubleTap = function() self:OpenEquipmentDetail({ kind = "inventory", index = slot }) end,
            onLongPress = function() self:OpenEquipmentDetail({ kind = "inventory", index = slot }) end,
            onDragStart = function(buttonWidget, event) return self:StartEquipmentDrag(slot, buttonWidget, event) end,
            onDragMove = function(buttonWidget, event) self:MoveEquipmentDrag(buttonWidget, event) end,
            onDragEnd = function(buttonWidget, event) self:EndEquipmentDrag(buttonWidget, event) end,
            onDragCancel = function() self:CancelEquipmentDrag() end,
        }
        local root = UI.Panel {
            visible = false, position = "absolute", left = p(28 + col * 94), top = p(23 + row * 95), width = p(86), height = p(86),
            backgroundImage = EQUIPMENT_CELL_BG, backgroundFit = "stretch", backgroundColor = TRANSPARENT,
            children = { border, icon, lockIcon, newLabel, levelLabel, button },
        }
        self.inventoryButtons[index] = {
            root = root, border = border, icon = icon, lockIcon = lockIcon,
            newLabel = newLabel, levelLabel = levelLabel, button = button,
        }
        children[#children + 1] = root
    end
    self.inventoryCount = UI.Label { text = "", visible = false, position = "absolute", right = p(22), top = p(5), width = p(150), height = p(28), fontSize = p(17), fontColor = MUTED, textAlign = "right" }
    children[#children + 1] = self.inventoryCount
    return UI.Panel { position = "absolute", left = p(350), top = p(120), width = p(1170), height = p(862), backgroundColor = { 12, 8, 16, 255 }, children = children }
end

function AppUI:BuildEquipmentDragGhost()
    local p = function(v) return self:P(v) end
    self.equipmentDragGhostIcon = UI.Panel {
        pointerEvents = "none", position = "absolute", left = p(18), top = p(18), width = p(60), height = p(60),
        backgroundFit = "contain", backgroundColor = TRANSPARENT,
    }
    self.equipmentDragGhost = UI.Panel {
        pointerEvents = "none", visible = false, position = "absolute", left = 0, top = 0, width = p(96), height = p(96),
        backgroundImage = EQUIPMENT_CELL_BG, backgroundFit = "stretch", backgroundColor = { 12, 8, 16, 235 },
        borderColor = WHITE, borderWidth = p(3),
        children = {
            UI.Panel { pointerEvents = "none", position = "absolute", left = 0, top = 0, width = p(96), height = p(96), backgroundImage = EQUIPMENT_CELL_BORDER, backgroundFit = "stretch", backgroundColor = TRANSPARENT },
            self.equipmentDragGhostIcon,
        },
    }
    return self.equipmentDragGhost
end

function AppUI:GetEquipmentDragScreenPoint(buttonWidget, event)
    -- Pointer callbacks are widget-local. Drop targets and the drag overlay use
    -- UI base-pixel screen coordinates, so restore the button's absolute origin.
    local layout = buttonWidget and buttonWidget:GetAbsoluteLayout() or nil
    local localX = event and event.x or 0
    local localY = event and event.y or 0
    return localX + (layout and layout.x or 0), localY + (layout and layout.y or 0)
end

function AppUI:PositionEquipmentDragGhost(screenX, screenY)
    if not self.equipmentDragGhost then return end
    local layout = self.gameOverlay and self.gameOverlay:GetAbsoluteLayout() or nil
    local left = screenX - (layout and layout.x or self.offsetX) - self:P(48)
    local top = screenY - (layout and layout.y or self.offsetY) - self:P(48)
    self.equipmentDragGhost:SetStyle({ left = left, top = top })
end

function AppUI:FindEquipmentDropTarget(x, y)
    for rowIndex = 1, #self.characterRows do
        local row = self.characterRows[rowIndex]
        for slot = 1, 2 do
            local cell = row.slots[slot]
            local layout = cell.root:GetAbsoluteLayout()
            if layout and x >= layout.x and x <= layout.x + layout.w and y >= layout.y and y <= layout.y + layout.h then
                return { row = row, cell = cell, slot = slot, wall = row.data.wall, role = row.data.role }
            end
        end
    end
    return nil
end

function AppUI:ClearEquipmentDragHover()
    local target = self.equipmentDragHover
    if not target then return end
    local selected = self.selectedEquip and self.selectedEquip.wall == target.wall
        and self.selectedEquip.role == target.role and self.selectedEquip.slot == target.slot
    target.cell.root:SetStyle({ borderColor = selected and WHITE or TRANSPARENT, borderWidth = self:P(selected and 3 or 0) })
    self.equipmentDragHover = nil
end

function AppUI:StartEquipmentDrag(index, buttonWidget, event)
    local instance = self.battle.inventory[index]
    local item = Equipment.GetItem(instance)
    if not instance or not item then return false end
    self.equipmentDrag = { index = index, instance = instance, item = item }
    if instance.new then
        instance.new = false
        self.battle.dirtySave = true
    end
    self.selectedInventory = index
    self.equipmentDragGhostIcon:SetStyle({ backgroundImage = item.icon })
    self.equipmentDragGhost:SetStyle({ imageTint = QUALITY_COLORS[item.quality] or WHITE })
    self.equipmentDragGhost:SetVisible(true)
    local screenX, screenY = self:GetEquipmentDragScreenPoint(buttonWidget, event)
    self:PositionEquipmentDragGhost(screenX, screenY)
    return true
end

function AppUI:MoveEquipmentDrag(buttonWidget, event)
    if not self.equipmentDrag then return end
    local screenX, screenY = self:GetEquipmentDragScreenPoint(buttonWidget, event)
    self:PositionEquipmentDragGhost(screenX, screenY)
    self:ClearEquipmentDragHover()
    local target = self:FindEquipmentDropTarget(screenX, screenY)
    if not target then return end
    local item = self.equipmentDrag.item
    local valid = item.role == target.role and item.slot == target.slot
        and self.battle:IsRoleUnlocked(target.wall, target.role)
    target.valid = valid
    target.cell.root:SetStyle({ borderColor = valid and { 104, 221, 96, 255 } or { 225, 74, 74, 255 }, borderWidth = self:P(4) })
    self.equipmentDragHover = target
end

function AppUI:EndEquipmentDrag(buttonWidget, event)
    if not self.equipmentDrag then return end
    local screenX, screenY = self:GetEquipmentDragScreenPoint(buttonWidget, event)
    self:PositionEquipmentDragGhost(screenX, screenY)
    local target = self:FindEquipmentDropTarget(screenX, screenY)
    local drag = self.equipmentDrag
    local valid = target and drag.item.role == target.role and drag.item.slot == target.slot
        and self.battle:IsRoleUnlocked(target.wall, target.role)
    self:ClearEquipmentDragHover()
    self.equipmentDragGhost:SetVisible(false)
    self.equipmentDrag = nil
    if valid then
        self.battle:EquipInventoryItem(drag.index, target.wall)
        self.selectedEquip = { wall = target.wall, role = target.role, slot = target.slot }
        self.selectedInventory = nil
    elseif target then
        local roleName = drag.item.role == "hero" and "英雄" or "弓箭手队长"
        self.battle.message = drag.item.name .. "只能放入" .. roleName .. "第" .. tostring(drag.item.slot) .. "槽"
        self.battle.messageTimer = 1.8
        self.battle:PushEvent("deny")
    end
    self:Refresh(true)
end

function AppUI:CancelEquipmentDrag()
    self:ClearEquipmentDragHover()
    if self.equipmentDragGhost then self.equipmentDragGhost:SetVisible(false) end
    self.equipmentDrag = nil
    self:Refresh(true)
end

function AppUI:BuildEquipmentTooltip()
    local p = function(v) return self:P(v) end
    self.tooltipIcon = UI.Panel { position = "absolute", left = p(18), top = p(18), width = p(60), height = p(60), backgroundFit = "contain" }
    self.tooltipName = UI.Label { text = "", position = "absolute", left = p(92), top = p(18), width = p(270), height = p(31), fontSize = p(24), fontWeight = "bold", fontColor = WHITE }
    self.tooltipQuality = UI.Label { text = "", position = "absolute", left = p(92), top = p(50), width = p(270), height = p(26), fontSize = p(18), fontColor = MUTED }
    self.tooltipEffects = UI.Label {
        text = "", position = "absolute", left = p(18), top = p(92), width = p(364), height = p(150),
        fontSize = p(20), fontColor = { 105, 165, 255, 255 }, textAlign = "left",
        whiteSpace = "normal", verticalAlign = "top", lineHeight = 1.2,
    }
    self.tooltipRecycleIcon = UI.Panel { position = "absolute", left = p(332), top = p(250), width = p(30), height = p(30), backgroundImage = "image/nightgate/currency/asset_b85ca26f.png", backgroundFit = "contain", backgroundColor = TRANSPARENT }
    self.tooltipRecycleValue = UI.Label { text = "", position = "absolute", left = p(362), top = p(250), width = p(30), height = p(30), fontSize = p(18), fontColor = WHITE, textAlign = "left" }
    self.tooltipHint = UI.Label { text = "长按打开详情", position = "absolute", left = p(15), bottom = p(12), width = p(370), height = p(24), fontSize = p(19), fontColor = WHITE, textAlign = "center" }
    self.equipmentTooltip = UI.Panel {
        visible = false, position = "absolute", left = p(267), top = p(241), width = p(400), height = p(340),
        backgroundColor = { 16, 10, 20, 252 }, borderColor = { 94, 70, 96, 255 }, borderWidth = p(2),
        children = { self.tooltipIcon, self.tooltipName, self.tooltipQuality, self.tooltipEffects, self.tooltipRecycleIcon, self.tooltipRecycleValue, self.tooltipHint },
    }
    return self.equipmentTooltip
end

function AppUI:GetEquipmentDetailInstance()
    local target = self.equipmentDetailTarget
    if not target then return nil end
    if target.kind == "inventory" then
        return self.battle.inventory[target.index]
    end
    if target.kind == "equipped" then
        return Equipment.GetEquipped(self.battle, target.wall, target.role, target.slot)
    end
    return nil
end

function AppUI:OpenEquipmentDetail(target)
    self.equipmentDetailTarget = target
    local instance = self:GetEquipmentDetailInstance()
    if not instance then
        self.equipmentDetailTarget = nil
        return
    end
    if instance.new then
        instance.new = false
        self.battle.dirtySave = true
    end
    self.equipmentDetailModal:SetVisible(true)
    self:Refresh(true)
end

function AppUI:CloseEquipmentDetail()
    self.equipmentDetailTarget = nil
    self.equipmentDetailModal:SetVisible(false)
end

function AppUI:BuildEquipmentDetailModal()
    local p = function(v) return self:P(v) end
    self.detailIcon = UI.Panel { position = "absolute", left = p(69), top = p(77), width = p(60), height = p(60), backgroundFit = "contain", backgroundColor = TRANSPARENT }
    self.detailCellBorder = UI.Panel { position = "absolute", left = p(49), top = p(57), width = p(100), height = p(100), backgroundImage = EQUIPMENT_CELL_BORDER, backgroundFit = "stretch", backgroundColor = TRANSPARENT }
    self.detailCellLock = UI.Panel { visible = false, position = "absolute", left = p(122), top = p(68), width = p(18), height = p(18), backgroundImage = EQUIPMENT_UI .. "equipment_lock.png", backgroundFit = "contain", backgroundColor = TRANSPARENT }
    self.detailCellEquipped = UI.Panel { visible = false, position = "absolute", left = p(123), top = p(88), width = p(15), height = p(15), backgroundImage = EQUIPMENT_UI .. "equipment_equipped.png", backgroundFit = "contain", backgroundColor = TRANSPARENT }
    self.detailCellLevel = UI.Label { text = "", position = "absolute", left = p(59), top = p(129), width = p(80), height = p(18), fontSize = p(14), fontColor = { 238, 163, 56, 255 }, textAlign = "center" }
    self.detailName = UI.Label { text = "", position = "absolute", left = p(160), top = p(59), width = p(200), height = p(40), fontSize = p(23), fontWeight = "bold", fontColor = WHITE }
    self.detailQuality = UI.Label { text = "", position = "absolute", left = p(160), top = p(99), width = p(200), height = p(40), fontSize = p(18), fontColor = MUTED }
    self.detailLockButton = self:ImageButton("锁定", 455, 112, 120, 45, EQUIPMENT_DETAIL_LOCK, function()
        local instance = self:GetEquipmentDetailInstance()
        if not instance then return end
        instance.locked = not instance.locked
        self.battle.dirtySave = true
        self:Refresh(true)
    end)
    self.detailEffects = UI.Label {
        text = "", position = "absolute", left = p(39), top = p(177), width = p(540), height = p(464),
        padding = p(10), fontSize = p(24), fontColor = { 105, 165, 255, 255 }, textAlign = "left",
        whiteSpace = "normal", verticalAlign = "top", lineHeight = 1.2,
    }
    self.detailPrimaryButton = self:ImageButton("强化", 84, 666, 200, 70, EQUIPMENT_DETAIL_BUTTON, function()
        local target = self.equipmentDetailTarget
        if not target or target.kind ~= "equipped" then return end
        self.battle:StrengthenEquipment(target.wall, target.role, target.slot)
        self:Refresh(true)
    end)
    self.detailSecondaryButton = self:ImageButton("卸下", 334, 666, 200, 70, EQUIPMENT_DETAIL_BUTTON, function()
        local target = self.equipmentDetailTarget
        if not target or target.kind ~= "equipped" then return end
        local ok = self.battle:UnequipItem(target.wall, target.role, target.slot)
        if ok then self:CloseEquipmentDetail() end
        self:Refresh(true)
    end)
    self.detailFuncButton = self:ImageButton("装配", 209, 666, 200, 70, EQUIPMENT_DETAIL_ACTION, function()
        local target = self.equipmentDetailTarget
        if not target or target.kind ~= "inventory" then return end
        local instance = self:GetEquipmentDetailInstance()
        local item = Equipment.GetItem(instance)
        local wall = self.selectedEquip and self.selectedEquip.wall or 1
        local ok = self.battle:EquipInventoryItem(target.index, wall)
        if ok and item then
            self.equipmentDetailTarget = { kind = "equipped", wall = wall, role = item.role, slot = item.slot }
        end
        self:Refresh(true)
    end)
    self.equipmentDetailModal = UI.Panel {
        visible = false, position = "absolute", left = 0, top = 0, width = p(1920), height = p(1080), backgroundColor = { 0, 0, 0, 170 },
        children = {
            transparentButton { position = "absolute", left = 0, top = 0, width = p(1920), height = p(1080), onClick = function() self:CloseEquipmentDetail() end },
            UI.Panel {
                position = "absolute", left = p(654), top = p(163), width = p(618), height = p(800),
                backgroundImage = EQUIPMENT_DETAIL_WINDOW, backgroundFit = "stretch", backgroundColor = TRANSPARENT,
                children = {
                    UI.Panel { position = "absolute", left = p(49), top = p(57), width = p(100), height = p(100), backgroundImage = EQUIPMENT_CELL_BG, backgroundFit = "stretch", backgroundColor = TRANSPARENT },
                    self.detailCellBorder, self.detailIcon, self.detailCellLock, self.detailCellEquipped, self.detailCellLevel,
                    self.detailName, self.detailQuality, self.detailLockButton, self.detailEffects,
                    self.detailPrimaryButton, self.detailSecondaryButton, self.detailFuncButton,
                    self:ImageButton("", 558, 0, 60, 60, EQUIPMENT_DETAIL_CLOSE, function() self:CloseEquipmentDetail() end),
                },
            },
        },
    }
    return self.equipmentDetailModal
end

function AppUI:BuildEquipmentPage()
    local p = function(v) return self:P(v) end
    local rows = {}
    for index = 1, #UIData.characterRows do rows[index] = self:BuildCharacterRow(index) end
    self.recycleButton = self:ImageButton("批量分解", 368, 982, 147, 67, VIOLET_BUTTON, function()
        if self.recycleConfirmTimer > 0 then self.battle:RecycleInventory(); self.recycleConfirmTimer = 0 else self.recycleConfirmTimer = 3 end
        self:Refresh(true)
    end)
    self.sortButton = self:ImageButton("排序", 532, 982, 147, 67, GRAY_BUTTON, function() self.battle:SortInventory(); self:Refresh(true) end)
    self.mergeButton = self:ImageButton("一键合成", 697, 982, 147, 67, ORANGE_BUTTON, function() self.battle:QuickMergeEquipment(); self:Refresh(true) end)
    self.equipmentPage = UI.Panel {
        visible = false, position = "absolute", left = 0, top = 0, width = p(1520), height = p(1080), backgroundColor = DARK,
        children = {
            UI.Panel { position = "absolute", left = 0, top = p(120), width = p(350), height = p(960), backgroundColor = PANEL, children = rows },
            self:BuildInventory(), self.recycleButton, self.sortButton, self.mergeButton, self:BuildEquipmentTooltip(),
        },
    }
    return self.equipmentPage
end

function AppUI:BuildQuickUpgradeCard(key, y, title, icon, onClick)
    local p = function(v) return self:P(v) end
    local valueLabel = UI.Label { text = "", position = "absolute", left = p(61), top = p(44), width = p(182), height = p(30), fontSize = p(22), fontColor = WHITE }
    local costLabel = UI.Label { text = "", position = "absolute", left = p(285), top = p(27), width = p(66), height = p(40), fontSize = p(24), fontColor = { 126, 223, 75, 255 }, textAlign = "left" }
    local button = transparentButton { position = "absolute", left = 0, top = 0, width = p(360), height = p(90), onClick = onClick }
    self["quick" .. key .. "ValueLabel"] = valueLabel
    self["quick" .. key .. "CostLabel"] = costLabel
    self["quick" .. key .. "Button"] = button
    return UI.Panel {
        position = "absolute", left = p(20), top = p(y), width = p(360), height = p(90),
        backgroundImage = "image/nightgate/ui/quickpanel/cell_bg.png", backgroundFit = "stretch", backgroundColor = TRANSPARENT,
        children = {
            UI.Panel { position = "absolute", left = p(8), top = p(20), width = p(50), height = p(50), backgroundImage = icon, backgroundFit = "contain", backgroundColor = TRANSPARENT },
            UI.Label { text = title, position = "absolute", left = p(61), top = p(11), width = p(182), height = p(30), fontSize = p(23), fontColor = WHITE },
            valueLabel,
            UI.Panel { position = "absolute", left = p(247), top = p(5), width = p(5), height = p(80), backgroundImage = "image/nightgate/ui/separator.png", backgroundFit = "stretch", backgroundColor = TRANSPARENT },
            UI.Panel { position = "absolute", left = p(255), top = p(30), width = p(30), height = p(30), backgroundImage = "image/nightgate/currency/asset_90278eb1.png", backgroundFit = "contain", backgroundColor = TRANSPARENT },
            costLabel, button,
        },
    }
end

function AppUI:BuildQuickPanel()
    local p = function(v) return self:P(v) end
    local damageCard = self:BuildQuickUpgradeCard("Damage", 10, "所有伤害", "image/nightgate/skill_tree/asset_e795ba52.png", function() self.battle:TryQuickUpgrade("damage"); self:Refresh(true) end)
    local wallCard = self:BuildQuickUpgradeCard("Wall", 105, "城墙血量加成", "image/nightgate/skill_tree/asset_63a6ecc0.png", function() self.battle:TryQuickUpgrade("wall"); self:Refresh(true) end)
    self.supplyAdStatus = UI.Label { text = "", position = "absolute", left = p(24), top = p(600), width = p(352), height = p(32), fontSize = p(17), fontColor = MUTED, textAlign = "center" }
    self.supplyAdButton = self:ImageButton("看广告 · 第5夜战备", 55, 637, 290, 56, VIOLET_BUTTON, function()
        self:ShowNightSupplyRewardAd()
    end)
    self.runNightLabel = UI.Label { text = "普通战役  第1晚", position = "absolute", left = p(25), top = p(831), width = p(350), height = p(52), fontSize = p(28), fontWeight = "bold", fontColor = WHITE, textAlign = "center" }
    self.finalNightButton = self:ImageButton("最终之夜", 77, 898, 245, 58, BLUE_BUTTON, function()
        self.difficultySelected = self.battle.finalDifficultySelected or 0
        self.difficultyModal:SetVisible(true)
        self:RefreshDifficultyModal()
    end)
    self.startButton = self:ImageButton("开始本夜", 77, 981, 245, 67, ORANGE_BUTTON, function()
        self.battle:StartNight()
        self:Refresh(true)
    end)
    return UI.Panel {
        position = "absolute", left = p(1520), top = 0, width = p(400), height = p(1080),
        backgroundColor = { 24, 20, 26, 255 }, backgroundImage = "image/nightgate/ui/frame_square_256.png", backgroundFit = "stretch", borderWidth = 0,
        children = {
            damageCard, wallCard,
            self.supplyAdStatus, self.supplyAdButton,
            UI.Panel { position = "absolute", left = p(10), top = p(704), width = p(380), height = p(4), backgroundImage = "image/nightgate/ui/separator.png", backgroundFit = "stretch" },
            UI.Panel { position = "absolute", left = p(133), top = p(735), width = p(134), height = p(118), backgroundImage = "image/nightgate/environment/summon_gate.png", backgroundFit = "contain" },
            self.runNightLabel, self.finalNightButton, self.startButton,
        },
    }
end

function AppUI:BuildDifficultyModal()
    local p = function(v) return self:P(v) end
    self.difficultyNightLabel = UI.Label { text = "难度 1", position = "absolute", left = p(168), top = p(60), width = p(264), height = p(63), fontSize = p(31), fontWeight = "bold", fontColor = WHITE, textAlign = "center", backgroundImage = "image/nightgate/ui/special_button.png", backgroundFit = "stretch" }
    self.difficultyModifiersLabel = UI.Label { text = "", position = "absolute", left = p(32), top = p(147), width = p(536), height = p(410), fontSize = p(24), fontColor = { 242, 139, 51, 255 }, textAlign = "left", backgroundImage = "image/nightgate/ui/skill_paper.png", backgroundFit = "stretch", backgroundColor = TRANSPARENT, padding = p(18) }
    self.difficultyStatusLabel = UI.Label { text = "已解锁", position = "absolute", left = p(150), top = p(577), width = p(300), height = p(60), fontSize = p(24), fontColor = MUTED, textAlign = "center", backgroundImage = BUTTON, backgroundFit = "stretch" }
    self.difficultyCostIcon = UI.Panel { visible = false, position = "absolute", left = p(203), top = p(592), width = p(30), height = p(30), backgroundImage = "image/nightgate/currency/asset_632cd9da.png", backgroundFit = "contain", backgroundColor = TRANSPARENT }
    self.difficultyPrevButton = self:ImageButton("", 113, 67, 50, 50, "image/nightgate/ui/difficulty/previous.png", function() self.difficultySelected = math.max(0, self.difficultySelected - 1); self:RefreshDifficultyModal() end)
    self.difficultyNextButton = self:ImageButton("", 433, 67, 50, 50, "image/nightgate/ui/difficulty/next.png", function() self.difficultySelected = math.min(Config.MAX_FINAL_DIFFICULTY, self.difficultySelected + 1); self:RefreshDifficultyModal() end)
    self.difficultyEnterButton = self:ImageButton("进入", 175, 649, 250, 70, ORANGE_BUTTON, function()
        if self.difficultySelected > self.battle.finalDifficultyUnlocked then
            local ok, message = self.battle:UnlockFinalDifficulty(self.difficultySelected)
            self.battle.message = message
            self.battle.messageTimer = 1.8
            if ok then self:Refresh(true) else self:RefreshDifficultyModal() end
            return
        end
        self.difficultyModal:SetVisible(false)
        self.battle:StartFinalNight(self.difficultySelected)
        self:Refresh(true)
    end)
    self.difficultyModal = UI.Panel {
        visible = false, position = "absolute", left = 0, top = 0, width = p(1920), height = p(1080), backgroundColor = { 0, 0, 0, 170 },
        children = {
            UI.Panel {
                position = "absolute", left = p(660), top = p(165), width = p(600), height = p(750), backgroundColor = TRANSPARENT, backgroundImage = "image/nightgate/ui/frame_square_256.png", backgroundFit = "stretch", borderWidth = 0,
                children = {
                    UI.Panel { position = "absolute", left = p(175), top = p(-37), width = p(250), height = p(70), backgroundImage = "image/nightgate/ui/title_frame_m.png", backgroundFit = "stretch", backgroundColor = TRANSPARENT },
                    UI.Label { text = "难度选择", position = "absolute", left = p(210), top = p(-17), width = p(180), height = p(41), fontSize = p(30), fontWeight = "bold", fontColor = WHITE, textAlign = "center" },
                    self.difficultyNightLabel, self.difficultyPrevButton, self.difficultyNextButton,
                    self.difficultyModifiersLabel, self.difficultyStatusLabel, self.difficultyCostIcon, self.difficultyEnterButton,
                    self:ImageButton("", 540, 0, 60, 60, EQUIPMENT_DETAIL_CLOSE, function() self.difficultyModal:SetVisible(false) end),
                },
            },
        },
    }
    return self.difficultyModal
end

function AppUI:BuildBattleHUD()
    local p = function(v) return self:P(v) end
    self.nightLabel = UI.Label { text = "最终之夜 难度1", position = "absolute", left = p(37), top = p(24), width = p(420), height = p(54), fontSize = p(39), fontWeight = "bold", fontColor = WHITE }
    self.battleGoldLabel = UI.Label { text = "0", position = "absolute", left = p(68), top = p(98), width = p(155), height = p(42), fontSize = p(30), fontColor = WHITE }
    self.battleCrystalLabel = UI.Label { text = "0", position = "absolute", left = p(68), top = p(157), width = p(155), height = p(42), fontSize = p(30), fontColor = WHITE }
    self.battleDefenseHint = UI.Label {
        text = "当前没有守军：本夜先用指针攻击，结算后双击技能树中的弓箭节点即可开启自动攻击",
        visible = false, pointerEvents = "none", position = "absolute", left = p(450), top = p(88), width = p(1020), height = p(52),
        fontSize = p(24), fontWeight = "bold", fontColor = { 255, 225, 94, 255 }, textAlign = "center",
        backgroundColor = { 10, 7, 13, 225 }, borderColor = { 226, 161, 40, 220 }, borderWidth = p(2),
    }
    self.wallBarFill = UI.Panel { position = "absolute", left = p(5), top = p(3), width = p(790), height = p(30), backgroundImage = "image/nightgate/ui/hp_red.png", backgroundFit = "stretch", backgroundColor = TRANSPARENT }
    self.wallLabel = UI.Label { text = "1 / 1", position = "absolute", left = 0, top = 0, width = p(800), height = p(36), fontSize = p(22), fontWeight = "bold", fontColor = WHITE, textAlign = "center" }
    self.wallBar = UI.Panel {
        position = "absolute", left = p(560), top = p(1044), width = p(800), height = p(36), backgroundColor = TRANSPARENT,
        children = {
            self.wallBarFill,
            UI.Panel { position = "absolute", left = 0, top = 0, width = p(800), height = p(36), backgroundImage = "image/nightgate/ui/hp_frame.png", backgroundFit = "stretch", backgroundColor = TRANSPARENT },
            self.wallLabel,
        },
    }
    self.speedButtons = {}
    for multiplier = 1, 3 do
        self.speedButtons[multiplier] = self:ImageButton(tostring(multiplier) .. "×", 1570 + (multiplier - 1) * 82, 20, 72, 58, GRAY_BUTTON, function()
            self.battle:SetSpeedMultiplier(multiplier)
            self:Refresh(true)
        end)
    end
    self.battleHUD = UI.Panel {
        visible = false, position = "absolute", left = 0, top = 0, width = p(1920), height = p(1080), pointerEvents = "box-none",
        children = {
            self.nightLabel, self.battleDefenseHint,
            UI.Panel { position = "absolute", left = p(29), top = p(100), width = p(37), height = p(37), backgroundImage = "image/nightgate/currency/asset_632cd9da.png", backgroundFit = "contain" }, self.battleGoldLabel,
            UI.Panel { position = "absolute", left = p(29), top = p(158), width = p(37), height = p(37), backgroundImage = "image/nightgate/currency/asset_90278eb1.png", backgroundFit = "contain" }, self.battleCrystalLabel,
            UI.Panel { position = "absolute", left = p(42), top = p(224), width = p(85), height = p(70), backgroundImage = "image/nightgate/ui/battle/equip_box.png", backgroundFit = "stretch", backgroundColor = TRANSPARENT },
            self.wallBar, self.speedButtons[1], self.speedButtons[2], self.speedButtons[3],
            transparentButton { position = "absolute", right = p(20), top = p(18), width = p(70), height = p(60), onClick = function() self.battle:ReturnHome(); self:Refresh(true) end },
        },
    }
    return self.battleHUD
end

function AppUI:SetResultAdStatus(text, isError)
    if not self.resultAdStatus then return end
    self.resultAdStatus:SetText(text or "")
    self.resultAdStatus:SetStyle({ fontColor = isError and { 235, 112, 106, 255 } or { 126, 223, 75, 255 } })
end

function AppUI:ShowNightGoldRewardAd()
    self.rewardAds:RequestNightGold(function(event)
        self:SetResultAdStatus(event.message, event.phase == "failure")
        if event.phase == "success" then Save.Store(self.battle) end
        self:Refresh(true)
    end)
    self:Refresh(true)
end

function AppUI:ShowDefeatReviveRewardAd()
    self.rewardAds:RequestDefeatRevive(function(event)
        self:SetResultAdStatus(event.message, event.phase == "failure")
        if event.phase == "success" then Save.Store(self.battle) end
        self:Refresh(true)
    end)
    self:Refresh(true)
end

function AppUI:SetSupplyAdStatus(text, isError)
    self.supplyAdMessage = text or ""
    self.supplyAdMessageError = isError == true
    self.supplyAdMessageTimer = 3.5
end

function AppUI:ShowNightSupplyRewardAd()
    self.rewardAds:RequestNightSupply(function(event)
        self:SetSupplyAdStatus(event.message, event.phase == "failure")
        if event.phase == "success" then Save.Store(self.battle) end
        self:Refresh(true)
    end)
    self:Refresh(true)
end

function AppUI:BuildResultModal()
    local p = function(v) return self:P(v) end
    self.resultAdStatusRunId = nil
    self.resultTitle = UI.Label { text = "守卫成功", position = "absolute", left = p(152), top = p(-26), width = p(255), height = p(56), fontSize = p(34), fontWeight = "bold", fontColor = WHITE, textAlign = "center" }
    self.resultMessage = UI.Label { text = "", position = "absolute", left = p(80), top = p(47), width = p(400), height = p(42), fontSize = p(22), fontColor = WHITE, textAlign = "center" }
    self.resultGold = UI.Label { text = "+0", position = "absolute", left = p(212), top = p(96), width = p(115), height = p(38), fontSize = p(24), fontColor = WHITE }
    self.resultCrystal = UI.Label { text = "+0", position = "absolute", left = p(212), top = p(143), width = p(115), height = p(38), fontSize = p(24), fontColor = WHITE }
    self.resultNone = UI.Label { text = "本轮没有掉落装备", position = "absolute", left = p(130), top = p(330), width = p(300), height = p(50), fontSize = p(20), fontColor = MUTED, textAlign = "center" }
    self.resultDropCells = {}
    local dropChildren = {}
    for index = 1, 20 do
        local col = (index - 1) % 5
        local row = math.floor((index - 1) / 5)
        local icon = UI.Panel { position = "absolute", left = p(13), top = p(13), width = p(52), height = p(52), backgroundFit = "contain", backgroundColor = TRANSPARENT }
        local border = UI.Panel { position = "absolute", left = 0, top = 0, width = p(78), height = p(78), backgroundImage = EQUIPMENT_CELL_BORDER, backgroundFit = "stretch", backgroundColor = TRANSPARENT }
        local root = UI.Panel {
            visible = false, position = "absolute", left = p(11 + col * 90), top = p(18 + row * 82), width = p(78), height = p(78),
            backgroundImage = EQUIPMENT_CELL_BG, backgroundFit = "stretch", backgroundColor = TRANSPARENT,
            children = { border, icon },
        }
        self.resultDropCells[index] = { root = root, border = border, icon = icon }
        dropChildren[#dropChildren + 1] = root
    end
    local dropPanel = UI.Panel { position = "absolute", left = p(35), top = p(190), width = p(490), height = p(349), backgroundImage = "image/nightgate/ui/finish/table_bg.png", backgroundFit = "stretch", backgroundColor = TRANSPARENT, children = dropChildren }
    self.resultAdStatus = UI.Label { text = "", position = "absolute", left = p(55), top = p(540), width = p(450), height = p(28), fontSize = p(18), fontColor = WHITE, textAlign = "center" }
    self.resultAdButton = self:ImageButton("看广告 · 本夜金币×2", 105, 570, 350, 60, ORANGE_BUTTON, function()
        if self.battle.state == "defeat" then
            self:ShowDefeatReviveRewardAd()
        else
            self:ShowNightGoldRewardAd()
        end
    end)
    self.resultReplayButton = self:ImageButton("下一夜", 66, 643, 200, 70, "image/nightgate/ui/finish/button.png", function()
        if self.battle.activeMode == "final" then
            self.battle:StartFinalNight(self.battle.finalDifficulty)
        else
            self.battle:StartNight()
        end
        self:Refresh(true)
    end)
    self.resultUpgradeButton = self:ImageButton("返回升级", 308, 643, 200, 70, "image/nightgate/ui/finish/button.png", function()
        self.battle:DismissResult()
        self:Refresh(true)
    end)
    self.resultModal = UI.Panel {
        visible = false, position = "absolute", left = 0, top = 0, width = p(1920), height = p(1080), backgroundColor = { 0, 0, 0, 215 },
        children = {
            UI.Panel {
                position = "absolute", left = p(722), top = p(205), width = p(560), height = p(729),
                backgroundImage = "image/nightgate/ui/finish/window.png", backgroundFit = "stretch", backgroundColor = TRANSPARENT,
                children = {
                    UI.Panel { position = "absolute", left = p(127), top = p(-42), width = p(305), height = p(85), backgroundImage = "image/nightgate/ui/finish/title.png", backgroundFit = "stretch", backgroundColor = TRANSPARENT },
                    self.resultTitle, self.resultMessage,
                    UI.Panel { position = "absolute", left = p(170), top = p(96), width = p(34), height = p(34), backgroundImage = "image/nightgate/currency/asset_632cd9da.png", backgroundFit = "contain", backgroundColor = TRANSPARENT }, self.resultGold,
                    UI.Panel { position = "absolute", left = p(170), top = p(143), width = p(34), height = p(34), backgroundImage = "image/nightgate/currency/asset_90278eb1.png", backgroundFit = "contain", backgroundColor = TRANSPARENT }, self.resultCrystal,
                    dropPanel, self.resultNone, self.resultAdStatus, self.resultAdButton, self.resultReplayButton, self.resultUpgradeButton,
                },
            },
        },
    }
    return self.resultModal
end

function AppUI:Build(destroyOldRoot)
    local p = function(v) return self:P(v) end
    self.skillNodes = {}
    self.economyNodes = {}
    self.prestigeNodes = {}
    self.characterRows = {}
    self.inventoryButtons = {}
    self.equipmentDrag = nil
    self.equipmentDragHover = nil
    self.gameOverlay = UI.Panel {
        visible = false, position = "absolute", left = 0, top = 0, width = p(1920), height = p(1080), backgroundColor = DARK,
        children = {
            self:BuildSkillPage(), self:BuildEquipmentPage(), self:BuildEconomyPage(), self:BuildPrestigePage(),
            self:BuildTopBar(), self:BuildQuickPanel(), self:BuildEquipmentDragGhost(), self:BuildResourceInfoModal(),
        },
    }
    self.characterDetails = CharacterDetails.New(self)
    self.tutorial = Tutorial.New(self)
    self.designRoot = UI.Panel {
        position = "absolute", left = self.offsetX, top = self.offsetY, width = p(1920), height = p(1080),
        children = { self:BuildMainMenu(), self.gameOverlay, self:BuildBattleHUD(), self:BuildDifficultyModal(), self:BuildEquipmentDetailModal(), self:BuildResultModal(), self.characterDetails.root, self.tutorial.root, self:BuildSettingsModal() },
    }
    -- Raw NanoVG is rendered before the Widget tree. Keep the root transparent so
    -- the battlefield remains visible beneath the battle HUD; individual menu
    -- and progression screens provide their own opaque backgrounds.
    self.fullscreenBackdrop = UI.Panel {
        position = "absolute", left = 0, top = 0, width = "100%", height = "100%", pointerEvents = "none",
        backgroundImage = "image/nightgate/ui/home_cn_clean.png", backgroundFit = "stretch", backgroundColor = DARK,
    }
    self.root = UI.Panel { width = "100%", height = "100%", backgroundColor = TRANSPARENT, children = { self.fullscreenBackdrop, self.designRoot } }
    UI.SetRoot(self.root, destroyOldRoot == true)
    self:Refresh(true)
end

function AppUI:IsBlocking()
    return self.battle.state ~= "running" or (self.settingsModal and self.settingsModal:IsVisible())
end

function AppUI:RefreshSkillTree()
    SkillPage.Refresh(self)
end

function AppUI:RefreshEconomyTree()
    EconomyPage.Refresh(self)
end

function AppUI:RefreshEquipment()
    local unlockedHeroes = self.battle:GetUnlockedHeroes()
    local unlockedArchers = self.battle:GetUnlockedArchers()
    for index = 1, #self.characterRows do
        local row = self.characterRows[index]
        local roleUnlocked = self.battle:IsRoleUnlocked(row.data.wall, row.data.role)
        if row.data.role == "hero" then
            local hero = self.battle:GetHeroForSide(row.data.wall)
            row.portrait:SetStyle({ backgroundImage = hero and hero.sprite or row.data.icon, backgroundFit = "contain" })
            row.portrait:SetDisabled(#unlockedHeroes == 0)
            row.change:SetVisible(#unlockedHeroes > 0)
            row.lockLabel:SetText(hero and hero.name or (#unlockedHeroes > 0 and "点击部署" or "技能树未解锁"))
        else
            local archer = self.battle:GetArcherForSide(row.data.wall)
            row.portrait:SetStyle({ backgroundImage = archer and archer.sprite or row.data.icon, backgroundFit = "contain" })
            row.portrait:SetDisabled(not roleUnlocked)
            row.change:SetVisible(#unlockedArchers > 1)
            row.lockLabel:SetText(archer and archer.name or "技能树未解锁")
        end
        row.roleLock:SetVisible(not roleUnlocked)
        row.lockLabel:SetVisible(true)
        row.lockLabel:SetStyle({ fontColor = roleUnlocked and WHITE or { 215, 94, 88, 255 } })
        row.tip:SetVisible(true)
        for slot = 1, 2 do
            local instance = Equipment.GetEquipped(self.battle, row.data.wall, row.data.role, slot)
            local item = Equipment.GetItem(instance)
            local selected = self.selectedEquip and self.selectedEquip.wall == row.data.wall and self.selectedEquip.role == row.data.role and self.selectedEquip.slot == slot
            local cell = row.slots[slot]
            cell.root:SetStyle({
                backgroundImage = item and EQUIPMENT_CELL_BG or EQUIPMENT_ADD_BG,
                imageTint = not roleUnlocked and { 77, 68, 79, 255 } or (item and (QUALITY_COLORS[item.quality] or WHITE) or WHITE),
                borderColor = selected and WHITE or TRANSPARENT,
                borderWidth = self:P(selected and 3 or 0),
            })
            cell.border:SetVisible(item ~= nil and roleUnlocked)
            cell.border:SetStyle({ imageTint = item and (QUALITY_COLORS[item.quality] or WHITE) or WHITE })
            cell.icon:SetStyle({ backgroundImage = roleUnlocked and (item and item.icon or EQUIPMENT_ADD_ICON) or ROLE_LOCK, backgroundImageOpacity = roleUnlocked and 1 or 0.72 })
            cell.lockIcon:SetVisible(not roleUnlocked or (instance ~= nil and instance.locked == true))
            cell.newLabel:SetVisible(roleUnlocked and instance ~= nil and instance.new == true)
            cell.levelLabel:SetText(instance and ("lv." .. tostring(instance.level or 0)) or "")
            cell.button:SetDisabled(not roleUnlocked and instance == nil)
        end
    end
    for index = 1, #self.inventoryButtons do
        local instance = self.battle.inventory[index]
        local item = Equipment.GetItem(instance)
        local selected = self.selectedInventory == index
        local cell = self.inventoryButtons[index]
        cell.root:SetVisible(instance ~= nil)
        cell.root:SetStyle({
            backgroundImage = EQUIPMENT_CELL_BG,
            imageTint = item and (QUALITY_COLORS[item.quality] or WHITE) or WHITE,
            borderColor = selected and WHITE or TRANSPARENT,
            borderWidth = self:P(selected and 3 or 0),
        })
        cell.border:SetStyle({ imageTint = item and (QUALITY_COLORS[item.quality] or WHITE) or WHITE })
        cell.icon:SetStyle({ backgroundImage = item and item.icon or "", backgroundImageOpacity = 1 })
        cell.lockIcon:SetVisible(instance ~= nil and instance.locked == true)
        cell.newLabel:SetVisible(instance ~= nil and instance.new == true)
        cell.levelLabel:SetText(instance and ("lv." .. tostring(instance.level or 0)) or "")
        cell.button:SetDisabled(instance == nil)
    end
    self.inventoryCount:SetText(tostring(#self.battle.inventory) .. "/" .. tostring(Config.EQUIPMENT_CAPACITY))
    self.equipmentTooltip:SetVisible(self.selectedInventory ~= nil and self.battle.inventory[self.selectedInventory] ~= nil)
    if self.selectedInventory then
        local instance = self.battle.inventory[self.selectedInventory]
        local item = Equipment.GetItem(instance)
        if item then
            self.tooltipIcon:SetStyle({ backgroundImage = item.icon })
            self.tooltipName:SetText(item.name)
            self.tooltipName:SetStyle({ fontColor = QUALITY_COLORS[item.quality] or WHITE })
            self.tooltipQuality:SetText("lv." .. tostring(instance.level or 0) .. "  " .. tostring(item.qualityName or ""))
            self.tooltipEffects:SetText(Equipment.DescribeEffects(instance))
            self.tooltipRecycleValue:SetText(tostring(Config.EQUIPMENT_RECYCLE[item.quality] or 0))
        end
    end
    self.recycleButton:SetText(self.recycleConfirmTimer > 0 and "再次确认分解" or "批量分解")
    self:RefreshEquipmentDetail()
end

function AppUI:RefreshEquipmentDetail()
    if not self.equipmentDetailModal then return end
    local instance = self:GetEquipmentDetailInstance()
    local item = Equipment.GetItem(instance)
    if not instance or not item then
        self.equipmentDetailTarget = nil
        self.equipmentDetailModal:SetVisible(false)
        return
    end
    local target = self.equipmentDetailTarget
    self.equipmentDetailModal:SetVisible(self.screen == "game" and self.selectedTab == "equipment" and self.battle.state ~= "running")
    self.detailCellBorder:SetStyle({ imageTint = QUALITY_COLORS[item.quality] or WHITE })
    self.detailIcon:SetStyle({ backgroundImage = item.icon })
    self.detailName:SetText(item.name)
    self.detailName:SetStyle({ fontColor = QUALITY_COLORS[item.quality] or WHITE })
    self.detailQuality:SetText((item.qualityName or "") .. "  Lv." .. tostring(instance.level or 0))
    self.detailCellLevel:SetText("lv." .. tostring(instance.level or 0))
    self.detailCellLock:SetVisible(instance.locked == true)
    self.detailCellEquipped:SetVisible(target.kind == "equipped")
    self.detailLockButton:SetText(instance.locked and "解除锁定" or "锁定")
    self.detailEffects:SetText(Equipment.DescribeEffects(instance))
    if target.kind == "inventory" then
        local wall = self.selectedEquip and self.selectedEquip.wall or 1
        local roleUnlocked = self.battle:IsRoleUnlocked(wall, item.role)
        self.detailPrimaryButton:SetVisible(false)
        self.detailSecondaryButton:SetVisible(false)
        self.detailFuncButton:SetVisible(true)
        self.detailFuncButton:SetText(roleUnlocked and ("装配 · 第" .. tostring(wall) .. "面") or "角色尚未解锁")
        self.detailFuncButton:SetDisabled(not roleUnlocked)
    else
        local cost = Equipment.GetStrengthenCost(instance)
        local roleUnlocked = self.battle:IsRoleUnlocked(target.wall, target.role)
        self.detailPrimaryButton:SetVisible(true)
        self.detailSecondaryButton:SetVisible(true)
        self.detailFuncButton:SetVisible(false)
        self.detailPrimaryButton:SetText(cost and ("强化  ◆" .. tostring(cost)) or "已满级")
        self.detailPrimaryButton:SetDisabled(not roleUnlocked or cost == nil or self.battle.equipmentShards < (cost or 0))
        self.detailSecondaryButton:SetText("卸下")
    end
end

function AppUI:RefreshDifficultyModal()
    if not self.difficultyNightLabel then return end
    self.difficultySelected = math.max(0, math.min(Config.MAX_FINAL_DIFFICULTY, self.difficultySelected or 0))
    local config = self.battle:GetFinalDifficultyConfig(self.difficultySelected)
    local modifiers = config.modifiers or {}
    self.difficultyNightLabel:SetText("难度 " .. tostring(self.difficultySelected))
    self.difficultyModifiersLabel:SetText(table.concat({
        "关卡难度                         +" .. tostring(config.levelDifficultyAdd or 0),
        "敌人血量额外加成             +" .. tostring(modifiers[79] or 0) .. ".0%",
        "敌人攻击额外加成             +" .. tostring(modifiers[80] or 0) .. ".0%",
        "敌人移动速度                    +" .. tostring(modifiers[81] or 0) .. ".0%",
        "召唤晶石怪个数                 +" .. tostring(modifiers[59] or 0),
        "结算时金币额外获得          +" .. tostring(modifiers[64] or 0) .. ".0%",
        "结算时晶石额外获得          +" .. tostring(modifiers[65] or 0) .. ".0%",
        "装备掉落率加成                 +" .. tostring(modifiers[82] or 0) .. ".0%",
    }, "\n"))
    local unlocked = self.difficultySelected <= self.battle.finalDifficultyUnlocked
    self.difficultyStatusLabel:SetText(unlocked and "已解锁" or ("       " .. tostring(config.cost)))
    self.difficultyCostIcon:SetVisible(not unlocked)
    self.difficultyEnterButton:SetText(unlocked and "进入" or ("解锁 · " .. tostring(config.cost)))
    self.difficultyEnterButton:SetDisabled(not unlocked and (self.difficultySelected ~= self.battle.finalDifficultyUnlocked + 1 or self.battle.gold < config.cost))
    self.difficultyPrevButton:SetDisabled(self.difficultySelected <= 0)
    self.difficultyNextButton:SetDisabled(self.difficultySelected >= Config.MAX_FINAL_DIFFICULTY)
end

function AppUI:RefreshResultModal()
    local isVictory = self.battle.state == "victory"
    local isDefeat = self.battle.state == "defeat"
    self.resultModal:SetVisible(isVictory or isDefeat)
    if not isVictory and not isDefeat then return end
    self.resultTitle:SetText(isVictory and "守卫成功" or "城墙失守")
    self.resultMessage:SetText(self.battle.resultMessage or "")
    self.resultGold:SetText("+" .. tostring(math.max(0, math.floor(self.battle.gold - (self.battle.runStartGold or self.battle.gold)))))
    self.resultCrystal:SetText("+" .. tostring(math.max(0, math.floor(self.battle.crystals - (self.battle.runStartCrystals or self.battle.crystals)))))
    local drops = self.battle.runDrops or {}
    self.resultNone:SetVisible(#drops == 0)
    for index = 1, #self.resultDropCells do
        local cell = self.resultDropCells[index]
        local instance = drops[index]
        local item = Equipment.GetItem(instance)
        cell.root:SetVisible(item ~= nil)
        if item then
            cell.root:SetStyle({ imageTint = QUALITY_COLORS[item.quality] or WHITE })
            cell.border:SetStyle({ imageTint = QUALITY_COLORS[item.quality] or WHITE })
            cell.icon:SetStyle({ backgroundImage = item.icon })
        end
    end
    local adAmount, adReason, resultId
    local adClaimed
    local placementKey
    if isDefeat then
        adAmount, adReason, resultId = self.battle:GetDefeatReviveAdOffer()
        adClaimed = self.battle.nightReviveAdUsed == true
        placementKey = "revive:" .. tostring(resultId)
    else
        adAmount, adReason, resultId = self.battle:GetNightGoldAdOffer()
        adClaimed = self.battle.nightGoldAdClaimed == true
        placementKey = "gold:" .. tostring(resultId)
    end
    local adPending = self.rewardAds:IsPending()
    if self.resultAdStatusRunId ~= placementKey then
        self.resultAdStatusRunId = placementKey
        if adPending then
            self:SetResultAdStatus("请完整观看广告，成功后才会发放奖励", false)
        elseif adClaimed then
            self:SetResultAdStatus(isDefeat and "本次挑战的续战机会已使用" or "本夜金币已翻倍", false)
        elseif adAmount and isDefeat then
            self:SetResultAdStatus("完整观看后恢复35%城墙，敌人短暂停顿", false)
        elseif adAmount then
            self:SetResultAdStatus("完整观看后额外获得 +" .. tostring(adAmount) .. " 金币", false)
        else
            self:SetResultAdStatus(adReason or "当前没有可领取奖励", true)
        end
    end
    if adPending then
        self.resultAdButton:SetText("广告播放中...")
    elseif adClaimed then
        self.resultAdButton:SetText(isDefeat and "本次续战已使用" or "本夜金币已翻倍")
    elseif adAmount and isDefeat then
        self.resultAdButton:SetText("看广告 · 城墙复苏（35%）")
    elseif adAmount then
        self.resultAdButton:SetText("看广告 · 本夜金币×2（+" .. tostring(adAmount) .. "）")
    else
        self.resultAdButton:SetText(isDefeat and "本次无法继续续战" or "本夜没有可翻倍金币")
    end
    self.resultAdButton:SetStyle({ left = self:P(105), top = self:P(570), width = self:P(350), height = self:P(60) })
    self.resultAdButton:SetDisabled(adPending or adClaimed or adAmount == nil)
    self.resultReplayButton:SetDisabled(adPending)
    self.resultUpgradeButton:SetDisabled(adPending)
    self.resultReplayButton:SetText(isVictory and (self.battle.activeMode == "final" and "再次挑战" or "下一夜") or "重新挑战")
end

function AppUI:RefreshPrestige()
    if not self.prestigePage then return end
    local levels = self.battle.prestigeLevels or {}
    for index = 1, #self.prestigeNodes do
        local node = self.prestigeNodes[index]
        node.level = Prestige.GetLevel(levels, node.id)
        node.state = Prestige.GetNodeState(levels, node.definition)
        node.revealed = Prestige.IsRevealed(levels, node.definition)
    end
    self.prestigeCanvas:SetNodes(self.prestigeNodes)
    self.prestigeCanvas:SetSelected(self.selectedPrestigeSkill)

    self.prestigePointLabel:SetText("转生点  " .. tostring(self.battle.prestigePoints)
        .. "    累计  " .. tostring(self.battle.prestigePointsTotal))
    self.prestigeRewardLabel:SetText("本轮最高第 " .. tostring(self.battle.bestNight)
        .. " 晚 · 转生可获 " .. tostring(self.battle:GetPrestigeReward()) .. " 点")

    local canPrestige, reason = self.battle:CanPrestige()
    self.prestigeStatusLabel:SetText(canPrestige
        and ("可执行第 " .. tostring(self.battle.prestigeCount + 1) .. " 次转生")
        or (reason or "尚未满足转生条件"))
    self.prestigeRitualRewardLabel:SetText("本次获得  " .. tostring(self.battle:GetPrestigeReward()) .. "  转生点")
    local currentMilestone = Prestige.GetMilestone(self.battle.prestigeMilestone)
    local pendingMilestone = Prestige.GetMilestone(self.battle.bestNight)
    local function milestoneState(night)
        if currentMilestone >= night then
            return "【已获得】", { 126, 223, 75, 255 }, WHITE
        end
        if pendingMilestone >= night and canPrestige then
            return "【本次结算】", GOLD, { 255, 226, 150, 255 }
        end
        return "【尚未达到】", MUTED, { 142, 132, 145, 255 }
    end
    for index = 1, 3 do
        local night = index * 10
        local stateText, stateColor, detailColor = milestoneState(night)
        local row = self.prestigeMilestoneRows[index]
        row.status:SetText(stateText .. " 第 " .. tostring(night) .. " 夜")
        row.status:SetStyle({ fontColor = stateColor })
        row.detail:SetStyle({ fontColor = detailColor })
    end
    self.prestigeConfirmButton:SetDisabled(not canPrestige)
    self.prestigeConfirmButton:SetText(self.prestigeConfirmTimer > 0 and "再次确认 · 重置进度" or "执行转生")

    local definition = Prestige.GetDefinition(self.selectedPrestigeSkill) or Prestige.GetDefinition("p_root")
    self.selectedPrestigeSkill = definition.id
    local level = Prestige.GetLevel(levels, definition.id)
    local maxLevel = #definition.costs
    local nextCost = Prestige.GetCost(levels, definition.id)
    local unlockReason = Prestige.GetUnlockReason(levels, definition)
    self.prestigeDetailTitle:SetText(definition.name)
    self.prestigeDetailLevel:SetText("等级  " .. tostring(level) .. " / " .. tostring(maxLevel))
    self.prestigeDetailDescription:SetText(definition.description)
    if nextCost then
        self.prestigeDetailEffect:SetText("下一等级：" .. Prestige.GetEffectText(definition, level + 1))
    else
        self.prestigeDetailEffect:SetText("满级效果：" .. Prestige.GetEffectText(definition, math.max(1, level)))
    end
    if unlockReason then
        self.prestigeDetailCost:SetText(unlockReason)
    elseif nextCost then
        self.prestigeDetailCost:SetText("消耗 " .. tostring(nextCost) .. " 转生点")
    else
        self.prestigeDetailCost:SetText("该节点已经满级")
    end
    self.prestigeUpgradeButton:SetDisabled(unlockReason ~= nil or nextCost == nil or self.battle.prestigePoints < (nextCost or 0))
    self.prestigeUpgradeButton:SetText(nextCost and "点亮节点" or "已满级")
end

function AppUI:Refresh(force)
    if not force and self.updateTimer > 0 then return end
    local running = self.battle.state == "running"
    self.fullscreenBackdrop:SetVisible(not running)
    self.mainMenu:SetVisible(not running and self.screen == "mainmenu")
    self.gameOverlay:SetVisible(not running and self.screen == "game")
    self.battleHUD:SetVisible(running)
    self.battleDefenseHint:SetVisible(running and not self.battle:IsArcherUnlocked() and #self.battle:GetUnlockedHeroes() == 0)
    self.skillPage:SetVisible(self.selectedTab == "skills")
    self.equipmentPage:SetVisible(self.selectedTab == "equipment")
    self.economyPage:SetVisible(self.selectedTab == "economy")
    self.prestigePage:SetVisible(self.selectedTab == "prestige")
    self.skillTabButton:SetStyle({ backgroundImage = BLUE_BUTTON })
    self.equipTabButton:SetStyle({ backgroundImage = BLUE_BUTTON })
    self.economyTabButton:SetStyle({ backgroundImage = BLUE_BUTTON })
    self.prestigeTabButton:SetStyle({ backgroundImage = BLUE_BUTTON })
    self.goldLabel:SetText(tostring(math.floor(self.battle.gold)))
    self.crystalLabel:SetText(tostring(math.floor(self.battle.crystals)))
    self.shardLabel:SetText(tostring(math.floor(self.battle.equipmentShards)))
    self.runNightLabel:SetText("普通战役  第" .. tostring(self.battle.nextNight) .. "晚")
    self.finalNightButton:SetVisible(self.battle:IsFinalNightUnlocked())
    local supplyNight = self.battle.nextNight
    local supplyVisible = self.battle:IsNightSupplyNight(supplyNight)
    local anyAdPending = self.rewardAds:IsPending()
    self.supplyAdButton:SetVisible(supplyVisible)
    self.supplyAdStatus:SetVisible(supplyVisible)
    self.startButton:SetDisabled(anyAdPending)
    self.finalNightButton:SetDisabled(anyAdPending)
    if supplyVisible then
        local supplyAmount, supplyReason = self.battle:GetNightSupplyAdOffer()
        local supplyReady = self.battle:IsNightSupplyReady()
        local supplyPending = self.rewardAds:IsPending("night_supply")
        if supplyPending then
            self.supplyAdButton:SetText("广告播放中...")
        elseif supplyReady then
            self.supplyAdButton:SetText("第" .. tostring(supplyNight) .. "夜战备已就绪")
        elseif supplyAmount then
            self.supplyAdButton:SetText("看广告 · 城墙上限 +" .. tostring(supplyAmount) .. "%")
        else
            self.supplyAdButton:SetText("第" .. tostring(supplyNight) .. "夜战备已使用")
        end
        self.supplyAdButton:SetDisabled(anyAdPending or supplyAmount == nil)
        if self.supplyAdMessageTimer > 0 then
            self.supplyAdStatus:SetText(self.supplyAdMessage)
            self.supplyAdStatus:SetStyle({ fontColor = self.supplyAdMessageError and { 235, 112, 106, 255 } or { 126, 223, 75, 255 } })
        elseif supplyReady then
            self.supplyAdStatus:SetText("开战时自动生效 · 本轮只领取一次")
            self.supplyAdStatus:SetStyle({ fontColor = { 126, 223, 75, 255 } })
        elseif supplyAmount then
            self.supplyAdStatus:SetText("每5夜开放一次 · 完整观看才生效")
            self.supplyAdStatus:SetStyle({ fontColor = MUTED })
        else
            self.supplyAdStatus:SetText(supplyReason or "本夜战备已使用")
            self.supplyAdStatus:SetStyle({ fontColor = MUTED })
        end
    end
    self.nightLabel:SetText(self.battle.activeMode == "final" and ("最终之夜  难度" .. tostring(self.battle.finalDifficulty)) or ("第 " .. tostring(self.battle.night or self.battle.nextNight) .. " 晚"))
    self.battleGoldLabel:SetText(tostring(math.floor(self.battle.gold)))
    self.battleCrystalLabel:SetText(tostring(math.floor(self.battle.crystals)))
    local speedMultiplier = self.battle:GetSpeedMultiplier()
    for multiplier = 1, 3 do
        self.speedButtons[multiplier]:SetStyle({ backgroundImage = multiplier == speedMultiplier and ORANGE_BUTTON or GRAY_BUTTON })
    end
    local stats = self.battle:GetStats()
    local wallMax = math.max(1, self.battle.wallMax or stats.wallMax)
    local wallRatio = math.max(0, math.min(1, (self.battle.wallHP or wallMax) / wallMax))
    self.wallBarFill:SetStyle({ width = self:P(790 * wallRatio) })
    self.wallLabel:SetText(tostring(math.floor(self.battle.wallHP or stats.wallMax)) .. " / " .. tostring(math.floor(self.battle.wallMax or stats.wallMax)))
    local damageCost = Skills.GetQuickCost("damage", self.battle.quickDamageLevel)
    local wallCost = Skills.GetQuickCost("wall", self.battle.quickWallLevel)
    self.quickDamageValueLabel:SetText(tostring(self.battle.quickDamageLevel * 5) .. " → " .. tostring((self.battle.quickDamageLevel + 1) * 5) .. "%")
    self.quickWallValueLabel:SetText(tostring(self.battle.quickWallLevel * 10) .. " → " .. tostring((self.battle.quickWallLevel + 1) * 10) .. "%")
    self.quickDamageCostLabel:SetText(tostring(damageCost))
    self.quickWallCostLabel:SetText(tostring(wallCost))
    self.quickDamageCostLabel:SetStyle({ fontColor = self.battle.crystals >= damageCost and { 126, 223, 75, 255 } or { 224, 91, 91, 255 } })
    self.quickWallCostLabel:SetStyle({ fontColor = self.battle.crystals >= wallCost and { 126, 223, 75, 255 } or { 224, 91, 91, 255 } })
    self.quickDamageButton:SetDisabled(self.battle.crystals < damageCost)
    self.quickWallButton:SetDisabled(self.battle.crystals < wallCost)
    self:RefreshSkillTree()
    self:RefreshEconomyTree()
    self:RefreshEquipment()
    self:RefreshDifficultyModal()
    self:RefreshResultModal()
    self:RefreshPrestige()
    if running or self.screen ~= "game" then self:HideResourceInfo() end
    if self.characterDetails then
        if running or self.selectedTab ~= "equipment" then self.characterDetails:Close() else self.characterDetails:Refresh() end
    end
    if self.tutorial then self.tutorial:Refresh() end
    self.updateTimer = 0.08
end

function AppUI:Update(dt)
    local viewportW, viewportH = UI.GetViewportSize()
    if math.abs((viewportW or 0) - (self.viewportW or 0)) > 0.5
        or math.abs((viewportH or 0) - (self.viewportH or 0)) > 0.5 then
        self:UpdateViewportMetrics()
        self:Build(true)
        return
    end
    self.updateTimer = math.max(0, self.updateTimer - dt)
    self.recycleConfirmTimer = math.max(0, self.recycleConfirmTimer - dt)
    self.prestigeConfirmTimer = math.max(0, self.prestigeConfirmTimer - dt)
    self.skillHintPulse = (self.skillHintPulse + dt) % 1.2
    if self.skillGestureHint then
        local pulse = 0.5 + 0.5 * math.sin(self.skillHintPulse / 1.2 * math.pi * 2)
        self.skillGestureHint:SetStyle({
            fontColor = { 255, 224, 92, math.floor(150 + pulse * 105) },
            borderColor = { 226, 161, 40, math.floor(110 + pulse * 145) },
        })
    end
    if self.battleDefenseHint and self.battleDefenseHint.props.visible then
        local pulse = 0.5 + 0.5 * math.sin(self.skillHintPulse / 1.2 * math.pi * 2)
        self.battleDefenseHint:SetStyle({
            fontColor = { 255, 225, 94, math.floor(175 + pulse * 80) },
            borderColor = { 226, 161, 40, math.floor(135 + pulse * 100) },
        })
    end
    self.skillFeedbackTimer = math.max(0, self.skillFeedbackTimer - dt)
    self.supplyAdMessageTimer = math.max(0, self.supplyAdMessageTimer - dt)
    if self.skillActionMessage then
        self.skillActionMessage:SetVisible(self.skillFeedbackTimer > 0)
    end
    if self.rewardAds then self.rewardAds:Update(dt) end
    EconomyPage.Update(self, dt)
    if self.tutorial then self.tutorial:Update(dt) end
    self:Refresh(false)
end

return AppUI
