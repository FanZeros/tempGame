local UI = require("urhox-libs/UI")
local Config = require("nightgate.Config")
local Skills = require("nightgate.Skills")
local HeroSkillData = require("nightgate.HeroSkillData")
local AnimatedButton = require("nightgate.AnimatedButton")

local CharacterDetails = {}
CharacterDetails.__index = CharacterDetails

local WHITE = { 241, 236, 220, 255 }
local MUTED = { 176, 164, 177, 255 }
local GREEN = { 116, 218, 61, 255 }
local RED = { 220, 94, 88, 255 }
local TRANSPARENT = { 0, 0, 0, 0 }
local PANEL_IMAGE = "image/nightgate/ui/equipment/detail_window.png"
local CLOSE_IMAGE = "image/nightgate/ui/equipment/detail_close.png"
local LOCK_IMAGE = "image/nightgate/ui/lock.png"

local function containsCharacter(list, id)
    for index = 1, #list do
        if list[index].id == id then return true end
    end
    return false
end

function CharacterDetails.New(app)
    local self = setmetatable({ app = app, rowIndex = nil }, CharacterDetails)
    self:Build()
    return self
end

function CharacterDetails:BuildSkillCard(y)
    local p = function(v) return self.app:P(v) end
    local icon = UI.Panel {
        pointerEvents = "none", position = "absolute", left = p(18), top = p(22), width = p(76), height = p(76),
        backgroundFit = "contain", backgroundColor = TRANSPARENT,
    }
    local lock = UI.Panel {
        pointerEvents = "none", visible = false, position = "absolute", left = p(37), top = p(41), width = p(38), height = p(38),
        backgroundImage = LOCK_IMAGE, backgroundFit = "contain", backgroundColor = TRANSPARENT,
    }
    local name = UI.Label {
        pointerEvents = "none", text = "", position = "absolute", left = p(112), top = p(14), width = p(468), height = p(35),
        fontSize = p(23), fontWeight = "bold", fontColor = WHITE,
    }
    local description = UI.Label {
        pointerEvents = "none", text = "", position = "absolute", left = p(112), top = p(51), width = p(468), height = p(66),
        fontSize = p(20), fontColor = MUTED, textAlign = "left",
    }
    local status = UI.Label {
        pointerEvents = "none", text = "", position = "absolute", right = p(18), top = p(14), width = p(210), height = p(32),
        fontSize = p(19), fontColor = RED, textAlign = "right",
    }
    local root = UI.Panel {
        position = "absolute", left = p(50), top = p(y), width = p(620), height = p(132),
        backgroundColor = { 12, 8, 17, 245 }, borderColor = { 86, 64, 90, 255 }, borderWidth = p(2),
        children = { icon, lock, name, description, status },
    }
    return { root = root, icon = icon, lock = lock, name = name, description = description, status = status }
end

function CharacterDetails:Build()
    local p = function(v) return self.app:P(v) end
    self.portrait = UI.Panel {
        pointerEvents = "none", position = "absolute", left = p(57), top = p(80), width = p(112), height = p(112),
        backgroundFit = "contain", backgroundColor = TRANSPARENT,
    }
    self.title = UI.Label {
        pointerEvents = "none", text = "角色详情", position = "absolute", left = p(165), top = p(28), width = p(390), height = p(45),
        fontSize = p(29), fontWeight = "bold", fontColor = WHITE, textAlign = "center",
    }
    self.name = UI.Label {
        pointerEvents = "none", text = "", position = "absolute", left = p(190), top = p(82), width = p(450), height = p(42),
        fontSize = p(28), fontWeight = "bold", fontColor = WHITE,
    }
    self.profession = UI.Label {
        pointerEvents = "none", text = "", position = "absolute", left = p(190), top = p(128), width = p(450), height = p(30),
        fontSize = p(18), fontColor = { 226, 161, 40, 255 },
    }
    self.unlock = UI.Label {
        pointerEvents = "none", text = "", position = "absolute", left = p(190), top = p(162), width = p(450), height = p(30),
        fontSize = p(17), fontColor = RED,
    }
    self.attributes = UI.Label {
        pointerEvents = "none", text = "", position = "absolute", left = p(58), top = p(215), width = p(604), height = p(140),
        fontSize = p(21), fontColor = WHITE, textAlign = "left",
        backgroundColor = { 10, 7, 13, 218 }, borderColor = { 70, 55, 75, 255 }, borderWidth = p(1), padding = p(16),
    }
    self.skillOne = self:BuildSkillCard(370)
    self.skillTwo = self:BuildSkillCard(520)
    self.hint = UI.Label {
        pointerEvents = "none", text = "技能解锁状态直接读取原版技能树节点", position = "absolute", left = p(50), top = p(675), width = p(620), height = p(34),
        fontSize = p(19), fontColor = MUTED, textAlign = "center",
    }
    local backdrop = AnimatedButton {
        position = "absolute", left = 0, top = 0, width = p(1920), height = p(1080), text = "",
        backgroundColor = { 0, 0, 0, 155 }, hoverBackgroundColor = { 0, 0, 0, 155 }, pressedBackgroundColor = { 0, 0, 0, 170 },
        borderWidth = 0, motionHoverScale = 1, motionPressedScale = 1,
        onClick = function() self:Close() end,
    }
    local close = AnimatedButton {
        position = "absolute", right = p(20), top = p(18), width = p(48), height = p(48), text = "",
        backgroundImage = CLOSE_IMAGE, backgroundFit = "contain", backgroundColor = TRANSPARENT, borderWidth = 0,
        onClick = function() self:Close() end,
    }
    local window = UI.Panel {
        position = "absolute", left = p(400), top = p(135), width = p(720), height = p(740),
        backgroundImage = PANEL_IMAGE, backgroundFit = "stretch", backgroundColor = { 17, 10, 21, 252 },
        children = {
            self.title, self.portrait, self.name, self.profession, self.unlock, self.attributes,
            self.skillOne.root, self.skillTwo.root, self.hint, close,
        },
    }
    self.root = UI.Panel {
        visible = false, position = "absolute", left = 0, top = 0, width = p(1920), height = p(1080),
        children = { backdrop, window },
    }
end

function CharacterDetails:SetSkillCard(card, number, skill, unlocked, unlockText)
    card.icon:SetStyle({ backgroundImage = skill.icon or "", backgroundImageOpacity = unlocked and 1 or 0.34 })
    card.name:SetText("第" .. tostring(number) .. "技能 · " .. skill.name)
    card.description:SetText(skill.description or "")
    card.description:SetStyle({ fontColor = unlocked and MUTED or { 116, 107, 119, 255 } })
    card.lock:SetVisible(not unlocked)
    card.status:SetText(unlocked and "已解锁" or (unlockText or "未解锁"))
    card.status:SetStyle({ fontColor = unlocked and GREEN or RED })
    card.root:SetStyle({ borderColor = unlocked and { 104, 91, 144, 255 } or { 74, 55, 76, 255 } })
end

function CharacterDetails:GetRowModel()
    local row = self.app.characterRows[self.rowIndex or 0]
    if not row then return nil end
    local battle = self.app.battle
    local roleUnlocked = battle:IsRoleUnlocked(row.data.wall, row.data.role)
    if row.data.role == "hero" then
        local character = battle:GetHeroForSide(row.data.wall) or Config.HERO_BY_ID[10002] or Config.HEROES[1]
        local unlocked = containsCharacter(battle:GetUnlockedHeroes(), character.id)
        local normal = character.normalSkill or {}
        local special = character.specialSkill or {}
        return {
            character = character,
            unlocked = unlocked and roleUnlocked,
            profession = (HeroSkillData.ProfessionNames[character.profession] or "英雄") .. "英雄",
            unlockText = unlocked and "已由技能树解锁" or ("未解锁 · 技能树属性 " .. tostring(character.unlockAttribute)),
            attributes = table.concat({
                "普通攻击伤害  " .. tostring(normal.damage or character.damage or 0),
                "普通攻击投射速度  " .. tostring(normal.speed or 0),
                "攻击范围  " .. tostring(normal.range or 0) .. "    穿透  " .. tostring(normal.penetration or 0),
                "暴击伤害倍率  150%    默认技能每 " .. tostring(character.specialEvery or 0) .. " 次攻击触发",
            }, "\n"),
            skillOne = {
                name = "英雄普通攻击",
                icon = character.icon,
                description = "基础伤害 " .. tostring(normal.damage or 0) .. " · 投射物大小 " .. tostring(normal.size or 0) .. " · 范围 " .. tostring(normal.range or 0),
            },
            skillTwo = {
                name = special.name or character.specialName or "默认技能",
                icon = special.icon or character.specialIcon,
                description = (special.description or character.specialDescription or "") .. "\n基础伤害 " .. tostring(special.damage or character.specialDamage or 0) .. " · 每 " .. tostring(character.specialEvery or 0) .. " 次普通攻击触发",
            },
            skillOneUnlocked = unlocked and roleUnlocked,
            skillTwoUnlocked = unlocked and roleUnlocked,
            skillOneUnlockText = "随英雄解锁",
            skillTwoUnlockText = "随英雄解锁",
        }
    end

    local character = battle:GetArcherForSide(row.data.wall) or Config.ARCHERS[1]
    local unlocked = containsCharacter(battle:GetUnlockedArchers(), character.id) and roleUnlocked
    local passiveUnlocked = unlocked and (character.passiveUnlockAttribute == 0
        or Skills.GetAttributeValue(battle.skillLevels, character.passiveUnlockAttribute) > 0)
    local traitUnlocked = unlocked and Skills.GetAttributeValue(battle.skillLevels, 71) > 0
    local isEileen = character.id == 20001
    return {
        character = character,
        unlocked = unlocked,
        profession = "弓箭手队长",
        unlockText = unlocked and "已由弓箭分支解锁" or "未解锁 · 先点亮召唤弓箭手人数",
        attributes = table.concat({
            "箭矢基础伤害  " .. tostring(Config.ARCHER.damage),
            "攻击间隔  " .. string.format("%.2fs", Config.ARCHER.interval),
            "同侧弓箭手共享队长装备加成",
            "默认英雄技能 ID  0（原表中无英雄默认技能）",
        }, "\n"),
        skillOne = {
            name = isEileen and "连射" or "散射",
            icon = isEileen and "image/nightgate/items/-_5716c5f7.png" or "image/nightgate/items/-_789ed50f.png",
            description = (isEileen and "弓箭手连射概率 +2%" or "弓箭手散射概率 +1.5%") .. "（battle_tbtrait 原表）",
        },
        skillTwo = {
            name = "爆炸箭",
            icon = "image/nightgate/items/asset_e872f8d7.png",
            description = "5% 概率替换为爆炸箭（battle_tbtrait 属性 75）",
        },
        skillOneUnlocked = passiveUnlocked,
        skillTwoUnlocked = traitUnlocked,
        skillOneUnlockText = isEileen and "技能树属性 69" or "解锁米娅后开启",
        skillTwoUnlockText = "技能树属性 71",
    }
end

function CharacterDetails:Open(rowIndex)
    self.rowIndex = rowIndex
    self.root:SetVisible(true)
    self:Refresh()
end

function CharacterDetails:Close()
    self.rowIndex = nil
    self.root:SetVisible(false)
end

function CharacterDetails:Refresh()
    if not self.root.props.visible then return end
    local model = self:GetRowModel()
    if not model then
        self:Close()
        return
    end
    local character = model.character
    self.portrait:SetStyle({ backgroundImage = character.icon or character.sprite or "", backgroundImageOpacity = model.unlocked and 1 or 0.45 })
    self.name:SetText(character.name or "未知角色")
    self.profession:SetText(model.profession)
    self.unlock:SetText(model.unlockText)
    self.unlock:SetStyle({ fontColor = model.unlocked and GREEN or RED })
    self.attributes:SetText(model.attributes)
    self:SetSkillCard(self.skillOne, 1, model.skillOne, model.skillOneUnlocked, model.skillOneUnlockText)
    self:SetSkillCard(self.skillTwo, 2, model.skillTwo, model.skillTwoUnlocked, model.skillTwoUnlockText)
end

return CharacterDetails
