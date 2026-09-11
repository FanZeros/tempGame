local UI = require("urhox-libs/UI")
local Skills = require("nightgate.Skills")

local Tutorial = {}
Tutorial.__index = Tutorial

local TRANSPARENT = { 0, 0, 0, 0 }
local GOLD = { 255, 224, 92, 255 }
local WHITE = { 241, 236, 220, 255 }
local GRAY_BUTTON = "image/nightgate/ui/1_gray_button_s.png"
local ORANGE_BUTTON = "image/nightgate/ui/1_orange_button_s.png"

function Tutorial.ResolveStep(app)
    local battle = app and app.battle
    if not battle or battle.tutorialCompleted or app.screen ~= "game" then return nil end

    if battle.state == "running" then return "battle" end
    if battle.state == "victory" or battle.state == "defeat" then return "result" end

    local rootLevel = Skills.GetLevel(battle.skillLevels, "0_0_0")
    local archerLevel = Skills.GetLevel(battle.skillLevels, "4_1_1")
    if archerLevel > 0 then return "complete" end
    if app.selectedTab ~= "skills" then return "skills_tab" end
    if rootLevel <= 0 then return "root" end
    if battle.gold >= 6 then return "archer" end
    return "start"
end

function Tutorial.New(app)
    local self = setmetatable({}, Tutorial)
    self.app = app
    self.step = nil
    self.pulse = 0
    local p = function(value) return app:P(value) end

    self.focus = UI.Panel {
        visible = false, pointerEvents = "none", position = "absolute",
        left = 0, top = 0, width = p(100), height = p(100),
        backgroundColor = { 255, 224, 92, 24 }, borderColor = GOLD,
        borderWidth = p(6), borderRadius = p(8),
    }
    self.targetCaption = UI.Label {
        visible = false, pointerEvents = "none", position = "absolute",
        left = 0, top = 0, width = p(260), height = p(46),
        text = "点击这里", fontSize = p(25), fontWeight = "bold",
        fontColor = GOLD, textAlign = "center",
        backgroundColor = { 9, 6, 12, 238 }, borderColor = { 226, 161, 40, 255 }, borderWidth = p(2),
    }
    self.title = UI.Label {
        pointerEvents = "none", position = "absolute", left = p(28), top = p(22),
        width = p(584), height = p(48), text = "新手引导", fontSize = p(31),
        fontWeight = "bold", fontColor = GOLD, textAlign = "center",
    }
    self.description = UI.Label {
        pointerEvents = "none", position = "absolute", left = p(34), top = p(82),
        width = p(572), height = p(118), text = "", fontSize = p(23),
        fontColor = WHITE, textAlign = "center",
    }
    self.completeButton = app:ImageButton("完成引导", 198, 205, 250, 64, ORANGE_BUTTON, function()
        app.battle:CompleteTutorial()
        self:Refresh()
        app:Refresh(true)
    end)
    self.card = UI.Panel {
        pointerEvents = "box-none", position = "absolute", left = p(930), top = p(730),
        width = p(640), height = p(290),
        backgroundColor = { 12, 8, 17, 246 }, backgroundImage = "image/nightgate/ui/frame_square_256.png",
        backgroundFit = "stretch", borderWidth = 0,
        children = { self.title, self.description, self.completeButton },
    }
    self.skipButton = app:ImageButton("跳过引导", 1690, 96, 180, 58, GRAY_BUTTON, function()
        app.battle:CompleteTutorial()
        self:Refresh()
        app:Refresh(true)
    end)
    self.root = UI.Panel {
        visible = false, pointerEvents = "box-none", position = "absolute",
        left = 0, top = 0, width = p(1920), height = p(1080), backgroundColor = TRANSPARENT,
        children = { self.focus, self.targetCaption, self.card, self.skipButton },
    }
    return self
end

function Tutorial:SetCard(title, description, x, y, showComplete)
    local p = function(value) return self.app:P(value) end
    self.title:SetText(title)
    self.description:SetText(description)
    self.card:SetStyle({ left = p(x), top = p(y) })
    self.completeButton:SetVisible(showComplete == true)
    self.skipButton:SetVisible(showComplete ~= true)
end

function Tutorial:SetFocus(x, y, width, height, caption, captionX, captionY)
    local p = function(value) return self.app:P(value) end
    if not x then
        self.focus:SetVisible(false)
        self.targetCaption:SetVisible(false)
        return
    end
    self.focus:SetVisible(true)
    self.focus:SetStyle({ left = x, top = y, width = width, height = height })
    self.targetCaption:SetVisible(true)
    self.targetCaption:SetText(caption or "点击这里")
    self.targetCaption:SetStyle({ left = captionX or x, top = captionY or (y - p(54)) })
end

function Tutorial:SetSkillFocus(skillId, caption)
    local node = self.app:GetSkillNode(skillId)
    local canvas = self.app.skillCanvas
    if not node or not canvas then
        self:SetFocus(nil)
        return
    end
    local p = function(value) return self.app:P(value) end
    local zoom = canvas:GetZoom()
    local x = canvas.panX_ + node.x * zoom
    local y = p(110) + canvas.panY_ + node.y * zoom
    local size = node.size * zoom
    self:SetFocus(x - p(12), y - p(12), size + p(24), size + p(24), caption,
        x + size + p(20), y + size * 0.5 - p(23))
end

function Tutorial:Refresh()
    local step = Tutorial.ResolveStep(self.app)
    self.step = step
    self.root:SetVisible(step ~= nil)
    if not step then return end

    local p = function(value) return self.app:P(value) end
    if step == "skills_tab" then
        self:SetCard("第1步：打开技能树", "成长和守军都需要从技能树解锁。\n点击左上角“技能树”。", 850, 650, false)
        self:SetFocus(p(9), p(9), p(162), p(82), "点击技能树", p(185), p(28))
    elseif step == "root" then
        self:SetCard("第1步：点亮中央核心", "开局有3金币，正好可以点亮中央技能。\n先单击发光节点，再点详情里的“点亮 / 升级”按钮。", 850, 720, false)
        self:SetSkillFocus("0_0_0", "先单击节点")
    elseif step == "start" then
        self:SetCard("第2步：开始守卫", "弓箭手还需要6金币解锁。\n先开始新轮次，用指针守住城墙并获取金币。", 850, 650, false)
        self:SetFocus(p(1587), p(971), p(265), p(87), "点击新轮次", p(1315), p(985))
    elseif step == "battle" then
        self:SetCard("第3步：拖动指针攻击", "怪物从中央出现，会走向四面城墙。\n按住并拖动扩张圆环攻击；金币飞到左上角后才会入账。", 640, 790, false)
        self:SetFocus(p(450), p(20), p(1020), p(780), "在战场内拖动手指", p(830), p(720))
    elseif step == "result" then
        local failed = self.app.battle.state == "defeat"
        self:SetCard(failed and "本轮失守也会保留收益" or "第4步：返回升级",
            failed and "不用重开存档，已入账的金币会保留。\n返回升级，金币不足时再挑战一轮。"
                or "结算后先回到技能树。\n集齐6金币后即可开启弓箭手自动攻击。",
            80, 330, false)
        self:SetFocus(p(1018), p(808), p(224), p(94), "返回升级", p(1260), p(832))
    elseif step == "archer" then
        self:SetCard("第5步：解锁自动攻击", "先单击发光的弓箭节点，再点详情里的升级按钮，消耗6金币。\n解锁后获得8名弓箭手，四面墙各自自动攻击。", 850, 720, false)
        self:SetSkillFocus("4_1_1", "先单击节点")
    elseif step == "complete" then
        self:SetCard("新手引导完成", "弓箭手已经驻守四面城墙。\n继续点亮分支可提升守军、解锁英雄和装备位。", 640, 390, true)
        self:SetFocus(nil)
    end
end

function Tutorial:Update(dt)
    if not self.root.props.visible then return end
    self.pulse = (self.pulse + (tonumber(dt) or 0)) % 1.1
    local amount = 0.5 + 0.5 * math.sin(self.pulse / 1.1 * math.pi * 2)
    if self.focus.props.visible then
        self.focus:SetStyle({
            backgroundColor = { 255, 224, 92, math.floor(18 + amount * 42) },
            borderColor = { 255, 224, 92, math.floor(145 + amount * 110) },
        })
    end
    self:Refresh()
end

return Tutorial
