local Config = require("diggin.Config")
local Util = require("diggin.Util")
local SkillText = require("diggin.SkillText")
local ArtefactCodex = require("diggin.ArtefactCodex")
local EffectRenderer = require("diggin.EffectRenderer")
local WorldTree = require("diggin.WorldTree")
local WorldTreeRenderer = require("diggin.WorldTreeRenderer")
local AbyssRenderer = require("diggin.AbyssRenderer")
local AbyssLoot = require("diggin.AbyssLoot")
local AbyssLeaderboardRenderer = require("diggin.AbyssLeaderboardRenderer")
local AbyssRunTools = require("diggin.AbyssRunTools")
local AbyssDraft = require("diggin.AbyssDraft")
local Cosmetics = require("diggin.Cosmetics")
local MobileControlLayout = require("diggin.MobileControlLayout")

local Renderer = {}
Renderer.__index = Renderer

local FONT_DEFINITIONS = {
    safe = { name = "safe", path = "Fonts/MiSans-Regular.ttf" },
    pixel = { name = "pixel", path = Config.Paths.fontLatin },
    zh = { name = "zh", path = Config.Paths.fontChinese },
}

local ORE_HUD_ORDER = {
    "Stone", "Silver", "Gold", "Platinum", "Iridium", "Ruby",
    "Emerald", "Diamond", "Starmetal", "RubyUnsmelted",
    "EmeraldUnsmelted", "DiamondUnsmelted", "StarDebris", "StarStone",
    "FactoryOre", "MissionRewardOre",
}

local ALL_RESOURCE_ORDER = {
    "Stone", "Silver", "Gold", "Platinum", "Iridium", "Ruby",
    "Emerald", "Diamond", "Starmetal", "RubyUnsmelted",
    "EmeraldUnsmelted", "DiamondUnsmelted", "StarDebris", "StarStone",
    "FactoryOre", "MissionRewardOre",
}

local ACTIVE_COOLDOWN_ORDER = {
    { node = "DynamiteActive", id = "dynamite" },
    { node = "ShockwaveActive", id = "shockwave" },
    { node = "Shrapnel", id = "shrapnel_debris" },
    { node = "Boomerang", id = "pickarang" },
    { node = "DrillMissiles", id = "drill_missile" },
    { node = "BouncingBall", id = "bouncing_ball" },
    { node = "BulletWorms", id = "bullet_worms" },
    { node = "DrillDrones", id = "drill_drones", persistent = true },
    { node = "SpinningPickaxe", id = "pickaxe_orbit", persistent = true },
    { node = "AbyssBombardment", iconNode = "DynamiteActive", cooldown = 8, capstone = true },
    { node = "ShardTyphoon", iconNode = "Shrapnel", cooldown = 5.5, capstone = true },
    { node = "FallingPickaxe", cooldown = 5, capstone = true },
    { node = "MeteorDrillArray", iconNode = "DrillMissiles", cooldown = 6.5, capstone = true },
    { node = "SingularityDrill", iconNode = "BouncingBall", cooldown = 7, capstone = true },
    { node = "TermiteDrones", cooldown = 1, capstone = true },
    { node = "Molenir", cooldown = 5, capstone = true },
    { node = "TheWorm", cooldown = 5, capstone = true },
}

local GUIDE_PAGES = {
    {
        title = "1/7  操作与主动技能",
        body = "左侧摇杆移动，右下圆盘可 360° 瞄准并钻探。轻点或按住圆盘都会生效；“锁·向下”会持续向正下方钻，点“停”解除。\n\n已经购买的主动技能会显示冷却；冷却完成后，下一次钻探立即自动释放。红色技能数值表示伤害，百分比表示相对钻头伤害的倍率。",
    },
    {
        title = "2/7  层数、密度与星辰",
        body = "每个密度都有 10 层。到达更深层会逐步开放下一密度；第 10 层首次贯穿可获得 1 颗星辰。集齐 10 颗星辰后开放终极密度。\n\n星辰是永久进度，不会因本局结束或重新进入而消失。可在主菜单的密度选择器查看总进度。",
    },
    {
        title = "3/7  星尘、星石与任务徽章",
        body = "星尘和星石是技能树资源：星金属会掉落它们，终极密度也会生成星金属；终极密度每局首次抵达第 10 层固定获得 1 颗星石。首次到达第 3、5、7、10 层还会稳定奖励星尘。\n\n主菜单可自愿观看一次支持广告领取 1 颗星石。任务徽章来自各密度每层首次到达；所有材料的持有量和来源可在“材料图鉴”查看。",
    },
    {
        title = "4/7  两种遗物",
        body = "普通遗物：宝箱发现后，用遗物核心研究，最多装备 4 件；只有已装备的效果生效。\n\n天赋遗物：同样由宝箱发现，但会镶入技能树节点并永久生效，不占普通遗物栏。已消耗的旧天赋遗物仍会保留在图鉴中。",
    },
    {
        title = "5/7  结算与 HUD",
        body = "燃料耗尽时可选择安全结算，或完整观看一次广告恢复 30% 燃料；救援每局限一次，硬核深渊禁用。想提前返航时，打开暂停菜单并选择“结束并结算”；飞行中的掉落物也会先收拢再入账。结算页也可自愿看广告追加一份本局矿石，星辰、徽章和遗物不会重复。\n\n右上“收/展”可折叠技能、遗物和资源信息；“?” 可随时重新打开本说明。",
    },
    {
        title = "6/7  深渊无尽与硬核模式",
        body = "无尽模式没有终点：普通层可持续挖掘下潜；第3～48层每3层、第50层固定、51～100层每5层、100层后每10层出现三格传送门。破坏左、中、右任意核心都能贯通入口并进行构筑选择。本局显示得分与层数，深度榜只比较单局抵达的最深层，不累计局数、金币或得分。W／↑跳跃，空格向准星闪现。深渊激光会自动攻击射程内最近怪物，有目标时消耗激光值，耗尽并冷却完成后会自动恢复。\n\n深渊Boss每10层进化并增加一种攻击，红框出现后及时离开。世界树全部节点满级后，入口会出现独立的硬核模式：矿石、怪物、追击与Boss攻击全面加强，并使用单独的硬核深度榜。",
    },
    {
        title = "7/7  深渊局内构筑",
        body = "每局最多5件道具、5个被动，各最高5级。前30层每3层选择；31～100层每5层；100层后每10层。主动与被动混合出现，没有可升级构筑就直接下潜，不再每层选择普通加成。\n\n卡片显示道具作用与联动所需被动；对应被动Lv.2可触发额外能力。8种指定道具Lv.5并积累3点锻造进度后，可在构筑层进化。每50层为安全商店。结算点击“本局战报”查看实际伤害、燃料恢复和技能搭配。",
    },
}

function Renderer.New(vg, state)
    local self = setmetatable({}, Renderer)
    self.vg = vg
    self.state = state
    self.images = {}
    self.menuButtons = {}
    self.endButtons = {}
    self.skillNodeRects = {}
    self.hudButtons = {}
    self.relicButtons = {}
    self.materialButtons = {}
    self.guideButtons = {}
    self.worldTreeButtons = {}
    self.leaderboardButtons = {}
    self.time = 0
    self.fontIds = {}
    self.fontFallbackLinked = {}
    self.fontRetryTimer = 0
    self.fontRetryCount = 0
    self.fontsReady = false
    self.fontWaitLogged = false
    self:TryLoadFonts()
    return self
end

function Renderer:Update(dt)
    self.time = self.time + dt
    if not self.fontsReady then
        self.fontRetryTimer = math.max(0, (self.fontRetryTimer or 0) - dt)
        if self.fontRetryTimer <= 0 then
            self.fontRetryTimer = 0.5
            self:TryLoadFonts()
        end
    end
end

-- Project fonts are downloaded on demand on real devices. The entry script
-- can run several frames before a large CJK TTF becomes available, so one
-- eager nvgCreateFont call is not sufficient. Keep actual handles separate
-- from display fallbacks and retry only missing fonts at a bounded cadence.
function Renderer:TryLoadFonts()
    self.fontIds = self.fontIds or {}
    self.fontFallbackLinked = self.fontFallbackLinked or {}
    self.fontRetryCount = (self.fontRetryCount or 0) + 1
    for key, definition in pairs(FONT_DEFINITIONS) do
        if self.fontIds[key] == nil then
            local fontId = nvgCreateFont(self.vg, definition.name, definition.path)
            if fontId and fontId >= 0 then self.fontIds[key] = fontId end
        end
    end

    local safeId = self.fontIds.safe
    if safeId then
        for _, key in ipairs({ "pixel", "zh" }) do
            local fontId = self.fontIds[key]
            if fontId and fontId ~= safeId and not self.fontFallbackLinked[key] then
                nvgAddFallbackFontId(self.vg, fontId, safeId)
                self.fontFallbackLinked[key] = true
            end
        end
    end

    self.fontsReady = self.fontIds.safe ~= nil
        and self.fontIds.pixel ~= nil and self.fontIds.zh ~= nil
    if self.fontsReady then
        if self.fontWaitLogged then
            print("INFO: Diggin fonts recovered after deferred resource download")
        end
    elseif not self.fontWaitLogged then
        self.fontWaitLogged = true
        print("INFO: Diggin fonts are still downloading; fallback/retry enabled")
    end
    return self.fontsReady
end

function Renderer:GetFontId(fontName)
    local ids = self.fontIds or {}
    return ids[fontName] or ids.safe or ids.zh or ids.pixel
end

function Renderer:GetImage(path)
    if not path then return nil end
    if self.images[path] == nil then
        local handle = nvgCreateImage(self.vg, path, NVG_IMAGE_NEAREST)
        self.images[path] = handle and handle > 0 and handle or false
    end
    if self.images[path] == false then return nil end
    return self.images[path]
end

function Renderer:DrawImage(path, x, y, w, h, alpha)
    local image = self:GetImage(path)
    if not image then return false end
    nvgBeginPath(self.vg)
    nvgRect(self.vg, x, y, w, h)
    nvgFillPaint(self.vg, nvgImagePattern(self.vg, x, y, w, h, 0, image, alpha or 1))
    nvgFill(self.vg)
    return true
end

-- Draw one cell from a transparent grid sheet without creating one texture
-- resource per frame. The scissor is restored immediately afterwards.
function Renderer:DrawSheetCell(path, columns, rows, cellIndex, x, y, w, h, alpha)
    local image = self:GetImage(path)
    if not image then return false end
    columns, rows = math.max(1, math.floor(columns or 1)), math.max(1, math.floor(rows or 1))
    local index = Util.Clamp(math.floor(tonumber(cellIndex) or 1), 1, columns * rows) - 1
    local column, row = index % columns, math.floor(index / columns)
    nvgSave(self.vg)
    nvgScissor(self.vg, x, y, w, h)
    nvgBeginPath(self.vg)
    nvgRect(self.vg, x, y, w, h)
    nvgFillPaint(self.vg, nvgImagePattern(self.vg,
        x - column * w, y - row * h, w * columns, h * rows, 0, image, alpha or 1))
    nvgFill(self.vg)
    nvgRestore(self.vg)
    return true
end

function Renderer:DrawAtlasCell(path, cellIndex, x, y, w, h, alpha)
    return self:DrawSheetCell(path, 3, 3, cellIndex, x, y, w, h, alpha)
end

function Renderer:FillRect(x, y, w, h, color)
    nvgBeginPath(self.vg)
    nvgRect(self.vg, x, y, w, h)
    nvgFillColor(self.vg, Util.Color(color))
    nvgFill(self.vg)
end

function Renderer:StrokeRect(x, y, w, h, color, width)
    nvgBeginPath(self.vg)
    nvgRect(self.vg, x + 0.5, y + 0.5, w - 1, h - 1)
    nvgStrokeColor(self.vg, Util.Color(color))
    nvgStrokeWidth(self.vg, width or 1)
    nvgStroke(self.vg)
end

function Renderer:Text(text, x, y, size, color, align, font)
    local fontName = font or "zh"
    local fontId = self:GetFontId(fontName)
    if fontId then nvgFontFaceId(self.vg, fontId) else nvgFontFace(self.vg, fontName) end
    nvgFontSize(self.vg, size)
    nvgTextAlign(self.vg, align or (NVG_ALIGN_LEFT + NVG_ALIGN_TOP))
    nvgFillColor(self.vg, Util.Color(color or Config.Palette.cream))
    nvgText(self.vg, x, y, tostring(text or ""))
end

function Renderer:TextBox(text, x, y, width, size, color)
    local fontId = self:GetFontId("zh")
    if fontId then nvgFontFaceId(self.vg, fontId) else nvgFontFace(self.vg, "zh") end
    nvgFontSize(self.vg, size)
    nvgTextAlign(self.vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(self.vg, Util.Color(color or Config.Palette.cream))
    nvgTextBox(self.vg, x, y, width, tostring(text or ""), nil)
end

function Renderer:DrawPanel(x, y, w, h, title)
    self:FillRect(x + 3, y + 3, w, h, Config.Palette.shadow)
    self:FillRect(x, y, w, h, Config.Palette.inkSoft)
    self:StrokeRect(x, y, w, h, Config.Palette.creamDim, 1)
    if title then
        self:FillRect(x, y, w, 18, Config.Palette.ink)
        self:Text(title, x + 7, y + 4, 10, Config.Palette.cream)
    end
end

function Renderer:DrawButton(id, label, x, y, w, h, enabled, selected, target)
    local color = enabled and Config.Palette.cream or { 111, 105, 111, 255 }
    local background = selected and Config.Palette.orange or Config.Palette.inkSoft
    self:FillRect(x + 2, y + 2, w, h, Config.Palette.shadow)
    self:FillRect(x, y, w, h, background)
    self:StrokeRect(x, y, w, h, color, 1)
    self:Text(label, x + w * 0.5, y + h * 0.5, 10, color, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    target[id] = { x = x, y = y, w = w, h = h, enabled = enabled }
end

function Renderer:DrawStarfield()
    local top = { 48, 44, 46, 255 }
    local bottom = { 57, 49, 75, 255 }
    nvgBeginPath(self.vg)
    nvgRect(self.vg, 0, 0, Config.DESIGN_WIDTH, Config.DESIGN_HEIGHT)
    nvgFillPaint(self.vg, nvgLinearGradient(self.vg, 0, 0, 0, Config.DESIGN_HEIGHT, Util.Color(top), Util.Color(bottom)))
    nvgFill(self.vg)
    for i = 1, 72 do
        local x = Util.Hash01(i, 1, 93) * Config.DESIGN_WIDTH
        local y = (Util.Hash01(i, 2, 77) * Config.DESIGN_HEIGHT + self.time * (1 + i % 3)) % Config.DESIGN_HEIGHT
        local bright = 110 + (i % 4) * 30
        self:FillRect(math.floor(x), math.floor(y), (i % 13 == 0) and 2 or 1, 1, { bright, bright, bright + 15, 210 })
    end
end

function Renderer:DrawMenu(app)
    self.menuButtons = {}
    self:DrawStarfield()
    self:DrawImage(Config.Paths.parallax1, 0, 0, 480, 270, 0.55)
    self:DrawImage(Config.Paths.parallax2, 0, 0, 480, 270, 0.7)
    self:DrawImage(Config.Paths.logo, 160, 24, 160, 64, 1)
    self:Text("深入地心 · 构筑你的钻探流派", 240, 90, 10, Config.Palette.creamDim, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    self:DrawImage(Config.Paths.worldTree, 395, 34, 40, 54, self.state.worldTreeAwakened and 0.95 or 0.2)
    local capstoneCount = WorldTree.GetCapstoneCount(self.state)
    local worldTreeLabel = self.state.worldTreeAwakened and "世界树"
        or string.format("世界树 %d/4", capstoneCount)
    self:Text("S2 新赛季", 374, 85, 8, Config.Palette.gold)
    self:DrawButton("season_notice", "S2更新公告", 24, 96, 82, 20, true, false, self.menuButtons)
    self:DrawButton("wardrobe", "时装库", 24, 125, 82, 28, true, false, self.menuButtons)
    self:DrawButton("world_tree", worldTreeLabel,
        374, 96, 82, 20, true, app.menuHover == "world_tree", self.menuButtons)

    self:DrawButton("continue", "继续", 113, 125, 78, 28, self.state.runs > 0 or self.state.totalUpgrades > 0, app.menuHover == "continue", self.menuButtons)
    self:DrawButton("new", "新游戏", 199, 125, 82, 28, true, app.menuHover == "new", self.menuButtons)
    self:DrawButton("skills", "技能树", 289, 125, 78, 28, true, app.menuHover == "skills", self.menuButtons)
    local supportClaimed = not self.state:CanClaimSupportStarStone()
    local supportLabel = app.supportAdPending and "广告播放中…"
        or (supportClaimed and "感谢支持" or "支持作者·星石")
    self:DrawButton("support_author", supportLabel, 374, 125, 82, 28,
        not app.adPending and not supportClaimed, app.menuHover == "support_author", self.menuButtons)
    self:Text(supportClaimed and "星石奖励已领取" or "广告得1星石·限一次", 415, 155, 6,
        supportClaimed and Config.Palette.creamDim or Config.Palette.gold,
        NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    self:DrawButton("settings", self.state.muted and "声音：关" or "声音：开", 27, 162, 66, 24, true, app.menuHover == "settings", self.menuButtons)
    self:DrawButton("drill_sound", self.state.drillSoundEnabled == false and "钻头：关" or "钻头：开",
        99, 162, 66, 24, true, app.menuHover == "drill_sound", self.menuButtons)
    self:DrawButton("relics", "遗物库", 171, 162, 66, 24, true, app.menuHover == "relics", self.menuButtons)
    self:DrawButton("materials", "材料图鉴", 243, 162, 66, 24, true, app.menuHover == "materials", self.menuButtons)
    self:DrawButton("guide", "玩法说明", 315, 162, 66, 24, true, app.menuHover == "guide", self.menuButtons)
    self:DrawButton("credits", "制作名单", 387, 162, 66, 24, true, app.menuHover == "credits", self.menuButtons)

    local maxDensity = self.state:GetMaxDensity()
    self:DrawButton("density_prev", "◀", 153, 195, 24, 20, self.state.prestige > 1, app.menuHover == "density_prev", self.menuButtons)
    self:FillRect(181, 195, 118, 20, Config.Palette.inkSoft)
    self:StrokeRect(181, 195, 118, 20, Config.Palette.creamDim, 1)
    local starCount = self.state:GetDensityStarCount()
    local densityText = self.state.prestige == 11 and "终极密度" or string.format("密度 %d/10", self.state.prestige)
    densityText = densityText .. string.format(" · 星辰 %d/%d", starCount, Config.STARDROPS_FOR_FINAL_DENSITY)
    self:Text(densityText, 240, 205, 7, Config.Palette.cream, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    self:DrawButton("density_next", "▶", 303, 195, 24, 20, self.state.prestige < maxDensity, app.menuHover == "density_next", self.menuButtons)

    self:Text("A/D 移动 · 触屏双圆盘 · 左键钻探", 18, 225, 8, Config.Palette.creamDim)
    self:DrawButton("controls", "自定义键位", 372, 220, 96, 22, true,
        app.menuHover == "controls", self.menuButtons)
    self:Text("原版 480×270 像素渲染 · TapTap Maker 云端版", 240, 247, 8, { 130, 123, 145, 255 }, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    if app.showCredits then
        self:DrawPanel(108, 53, 264, 164, "制作名单")
        self:TextBox("DIGGIN 原作团队\n\nTapTap Maker 移植：保留原始美术、音乐、数值、四向技能树与钻探规则。\n\n点击空白处返回", 126, 82, 228, 10, Config.Palette.cream)
    end
    if app.showNewGameConfirm then
        for _, rect in pairs(self.menuButtons) do rect.enabled = false end
        self:FillRect(0, 0, 480, 270, { 10, 7, 12, 205 })
        self:DrawPanel(104, 70, 272, 132, "确认开始新游戏")
        self:Text("警告：这会清空全部进度", 240, 101, 14, Config.Palette.red, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        self:TextBox("资源、技能、遗物、星辰、密度和黄金钻头都会永久重置；一次性广告奖励资格不会恢复。此操作无法撤销。", 124, 127, 232, 9, Config.Palette.cream)
        self:DrawButton("new_cancel", "保留进度", 132, 166, 94, 24, true, app.menuHover == "new_cancel", self.menuButtons)
        self:DrawButton("new_confirm", "确认清空", 254, 166, 94, 24, true, app.menuHover == "new_confirm", self.menuButtons)
    end
end

function Renderer:DrawGuide(app)
    self.guideButtons = {}
    self:DrawStarfield()
    self:DrawPanel(54, 30, 372, 205, "新手说明")
    local pageIndex = Util.Clamp(math.floor(app.guidePage or 1), 1, #GUIDE_PAGES)
    local page = GUIDE_PAGES[pageIndex]
    self:Text(page.title, 240, 57, 14, Config.Palette.gold, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    self:TextBox(page.body, 79, 86, 322, 10, Config.Palette.cream)
    self:DrawButton("guide_prev", "上一页", 79, 202, 74, 22, pageIndex > 1, false, self.guideButtons)
    self:Text(string.format("%d / %d", pageIndex, #GUIDE_PAGES), 240, 213, 9, Config.Palette.creamDim, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    self:DrawButton("guide_next", pageIndex < #GUIDE_PAGES and "下一页" or "看完了", 327, 202, 74, 22, true, false, self.guideButtons)
end

function Renderer:WorldToScreen(player, worldX, worldY, shakeX, shakeY)
    return Config.DESIGN_WIDTH * 0.5 + worldX + (shakeX or 0),
        Config.DESIGN_HEIGHT * 0.5 + worldY - player.y + (shakeY or 0)
end

function Renderer:DrawOre(tile, screenX, screenY)
    local ore = Config.Ores[tile.ore]
    if not ore or not ore.frames then return end
    local frame = tile.variant % (ore.frames or 1)
    local path = Config.Paths.generatedRoot .. "ores/" .. tile.ore .. "_" .. frame .. ".png"
    self:DrawImage(path, screenX, screenY, 16, 16, 1)
end

function Renderer:DrawTile(tile, screenX, screenY)
    local variant = (tile.variant or 0) % 3
    local layerPath = Config.Paths.generatedRoot .. "layers/" .. tile.tilemap .. "_" .. variant .. ".png"
    self:DrawImage(layerPath, screenX, screenY, 16, 16, 1)
    self:DrawOre(tile, screenX, screenY)
    if tile.abyssExit then
        local remaining = tile.maxHealth > 0 and Util.Clamp(tile.health / tile.maxHealth, 0, 1) or 1
        local frame = math.min(8, 1 + math.floor((1 - remaining) * 7.99))
        self:DrawSheetCell(Config.Paths.abyssTowerCore, 4, 2, frame, screenX, screenY, 16, 16, 1)
    end
    if tile.modifier == "boomstone" then
        self:DrawImage(Config.Paths.generatedRoot .. "modifiers/boomstone_" .. variant .. ".png", screenX, screenY, 16, 16, 1)
    elseif tile.modifier == "feverstone" then
        self:DrawImage(Config.Paths.generatedRoot .. "modifiers/feverstone_" .. variant .. ".png", screenX, screenY, 16, 16, 1)
    elseif tile.modifier == "fuelstone" then
        self:DrawImage(Config.Paths.generatedRoot .. "modifiers/fuelstone_0.png", screenX, screenY, 16, 16, 1)
    elseif tile.modifier == "chest" then
        self:DrawImage(Config.Paths.generatedRoot .. "modifiers/chest_0.png", screenX, screenY, 16, 16, 1)
    elseif tile.modifier == "bonanza" then
        self:FillRect(screenX + 2, screenY + 2, 3, 3, Config.Palette.gold)
        self:FillRect(screenX + 11, screenY + 10, 2, 2, Config.Palette.cream)
    end
    if tile.health < tile.maxHealth and tile.maxHealth < math.huge then
        local remaining = Util.Clamp(tile.health / tile.maxHealth, 0, 1)
        -- Original thresholds: 66% / 33% remaining health.
        local frame = remaining >= 0.66 and 0 or (remaining >= 0.33 and 1 or 2)
        self:DrawImage(Config.Paths.generatedRoot .. "damage/crack_" .. frame .. ".png", screenX, screenY, 16, 16, 0.9)
    end
end

function Renderer:GetOreHudLayout(app, inventory, y, order)
    local entries = {}
    inventory = inventory or self.state.runInventory
    order = order or ORE_HUD_ORDER
    local isRunInventory = inventory == self.state.runInventory
    for _, ore in ipairs(order) do
        local amount = inventory[ore] or 0
        local pending = isRunInventory and ((app.pendingOre and app.pendingOre[ore]) or 0) or 0
        if not isRunInventory or amount > 0 or pending > 0 then
            entries[#entries + 1] = { ore = ore, amount = amount, pending = pending }
        end
    end
    if isRunInventory and #entries > 0 then
        local controls = self.state.GetMobileControls and self.state:GetMobileControls() or Config.Controls
        local maxPerRow = controls.oreHudMaxPerRow
        local rowCount = math.ceil(#entries / maxPerRow)
        local baseY = (y or controls.oreHudY) - (rowCount - 1) * controls.oreHudRowStep
        for index, item in ipairs(entries) do
            local row = math.floor((index - 1) / maxPerRow)
            local column = (index - 1) % maxPerRow
            local firstInRow = row * maxPerRow + 1
            local countInRow = math.min(maxPerRow, #entries - firstInRow + 1)
            local gap = 2
            local width = math.min(40,
                math.floor((controls.oreHudWidth - gap * (countInRow - 1)) / countInRow))
            local rowWidth = countInRow * width + (countInRow - 1) * gap
            local rowX = controls.oreHudX + math.floor((controls.oreHudWidth - rowWidth) * 0.5)
            item.x = rowX + column * (width + gap)
            item.y = baseY + row * controls.oreHudRowStep
            item.w = width
            item.h = controls.oreHudItemHeight
        end
        return entries
    end

    local gap = #entries > 12 and 1 or 2
    local width = #entries > 0 and math.floor((456 - gap * (#entries - 1)) / #entries) or 36
    local x = 12
    for _, item in ipairs(entries) do
        item.x = x
        item.y = y or 238
        item.w = width
        item.h = 19
        x = x + width + gap
    end
    return entries
end

function Renderer:GetOreIconPath(ore)
    if ore == "Stardrop" then return Config.Paths.stardrop end
    return Config.Paths.generatedRoot .. "hud_icons/" .. ore .. ".png"
end

function Renderer:GetRelicIconPath(relic)
    if type(relic) == "string" then relic = self.state:GetRelic(relic) end
    return relic and (Config.Paths.generatedRoot .. "skill_icons/" .. relic.icon .. ".png") or nil
end

function Renderer:GetOreHudTarget(app, ore)
    if ore == "Stardrop" then return 245, 77 end
    for _, item in ipairs(self:GetOreHudLayout(app)) do
        if item.ore == ore then return item.x + item.w - 7, item.y + 10 end
    end
    return 24, 248
end

function Renderer:GetAbyssLootHudTarget(slotId)
    for index, slot in ipairs(AbyssLoot.SLOTS) do
        if slot.id == slotId then return 330 + (index - 1) * 29, 56 end
    end
    return 373, 56
end

function Renderer:GetArtefactHudLayout(app)
    local entries = {}
    for _, node in ipairs(self.state.skillData.nodes) do
        if node.is_artefact then
            local level = self.state:GetLevel(node.id)
            local owned = self.state.artefacts[node.id] == true
            local active = level > 0
            local pending = app.pendingArtefacts and app.pendingArtefacts[node.id] == true
            if owned or active or pending then
                entries[#entries + 1] = {
                    id = node.id,
                    node = node,
                    owned = owned,
                    active = active,
                    pending = pending,
                }
            end
        end
    end
    for index, item in ipairs(entries) do
        item.x = 58 + (index - 1) * 20
        item.y = 52
        item.w = 18
        item.h = 18
    end
    return entries
end

function Renderer:GetArtefactHudTarget(app, artefactId)
    for _, item in ipairs(self:GetArtefactHudLayout(app)) do
        if item.id == artefactId then return item.x + 9, item.y + 9 end
    end
    return 67, 61
end

function Renderer:DrawArtefactBar(app)
    self:Text("天赋遗物", 4, 61, 7, Config.Palette.creamDim, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local entries = self:GetArtefactHudLayout(app)
    if #entries == 0 then
        self:FillRect(58, 52, 18, 18, { 24, 20, 29, 170 })
        self:StrokeRect(58, 52, 18, 18, { 80, 71, 91, 150 }, 1)
        self:Text("—", 67, 61, 8, { 100, 92, 108, 220 }, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        return
    end
    for _, item in ipairs(entries) do
        self:FillRect(item.x + 2, item.y + 2, item.w, item.h, Config.Palette.shadow)
        local background = item.active and { 30, 61, 53, 235 } or (item.owned and { 52, 42, 60, 235 } or { 31, 26, 36, 190 })
        local border = item.active and Config.Palette.green or (item.owned and Config.Palette.gold or { 110, 92, 66, 170 })
        self:FillRect(item.x, item.y, item.w, item.h, background)
        self:StrokeRect(item.x, item.y, item.w, item.h, border, item.active and 2 or 1)
        self:DrawImage(Config.Paths.generatedRoot .. "skill_icons/" .. item.id .. ".png", item.x + 2, item.y + 2, 14, 14, (item.owned or item.active) and 1 or 0.25)
        self.hudButtons["artefact:" .. item.id] = {
            x = item.x,
            y = item.y,
            w = item.w,
            h = item.h,
            enabled = item.owned or item.active,
        }
    end
end

function Renderer:GetRelicHudTarget(app, relicId)
    for index, equippedId in ipairs(self.state.equippedRelics) do
        if equippedId == relicId then return 59 + (index - 1) * 20, 42 end
    end
    return 196, 42
end

function Renderer:DrawRelicLoadout(app)
    local equipped = self.state:GetEquippedRelics()
    self:Text("遗物 " .. tostring(#equipped) .. "/4", 12, 42, 7, Config.Palette.creamDim, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    for slot = 1, 4 do
        local x, y = 50 + (slot - 1) * 20, 33
        local relic = equipped[slot]
        self:FillRect(x + 2, y + 2, 18, 18, Config.Palette.shadow)
        self:FillRect(x, y, 18, 18, relic and { 52, 42, 60, 235 } or { 24, 20, 29, 185 })
        local border = relic and (Config.Palette[relic.color] or Config.Palette.gold) or { 80, 71, 91, 160 }
        self:StrokeRect(x, y, 18, 18, border, 1)
        if relic then
            self:DrawImage(self:GetRelicIconPath(relic), x + 2, y + 2, 14, 14, 1)
            self.hudButtons["relic_info:" .. relic.id] = { x = x, y = y, w = 18, h = 18, enabled = true }
        else
            self:Text(tostring(slot), x + 9, y + 9, 6, { 90, 82, 98, 220 }, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        end
    end
    self:FillRect(136, 33, 68, 18, { 24, 20, 29, 190 })
    self:StrokeRect(136, 33, 68, 18, Config.Palette.gold, 1)
    self:Text("核心 +" .. tostring(app.runRelicCoreBonus or 0), 170, 42, 7, Config.Palette.gold, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
end

function Renderer:DrawGoldenDrillAd(app)
    local x, y, w, h = 238, 33, 110, 22
    local enabled = not app.adPending
    local active = self.state.goldenDrillCharges > 0
    self:FillRect(x + 2, y + 2, w, h, Config.Palette.shadow)
    self:FillRect(x, y, w, h, active and { 108, 67, 18, 238 } or Config.Palette.inkSoft)
    self:StrokeRect(x, y, w, h, enabled and Config.Palette.gold or { 107, 99, 111, 220 }, 1)
    self:DrawImage(Config.Paths.goldenDrill, x + 3, y + 2, 18, 18, enabled and 1 or 0.45)
    local label
    if app.adPending then
        label = "广告加载中…"
    elseif active then
        label = "黄金钻头 ×" .. tostring(self.state.goldenDrillCharges)
    else
        label = "看广告得黄金钻"
    end
    self:Text(label, x + 23, y + 11, 7, enabled and Config.Palette.cream or Config.Palette.creamDim, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    self:Text("双倍20% · 三倍5% · 大奖0.1%", x + w * 0.5, y + h + 2, 6, Config.Palette.gold, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    self.hudButtons.reward_ad = { x = x, y = y, w = w, h = h, enabled = enabled }
end

function Renderer:DrawOreCounters(app, inventory, y, order)
    for _, item in ipairs(self:GetOreHudLayout(app, inventory, y, order)) do
        self:FillRect(item.x, item.y, item.w, item.h, { 24, 20, 29, 218 })
        self:StrokeRect(item.x, item.y, item.w, item.h, { 80, 71, 91, 210 }, 1)
        local iconSize = item.w < 32 and 10 or 13
        self:DrawImage(self:GetOreIconPath(item.ore), item.x + 2, item.y + 3, iconSize, iconSize, 1)
        if item.ore:find("Unsmelted", 1, true) then
            self:Text("原", item.x + 2, item.y + 1, 5, Config.Palette.gold)
        end
        self:Text(Util.FormatNumber(item.amount), item.x + item.w - 3, item.y + 10, item.w < 32 and 6 or 7, Config.Palette.cream, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        if item.pending > 0 then
            self:FillRect(item.x + item.w - 4, item.y + 2, 2, 2, Config.Palette.gold)
        end
    end
end

function Renderer:DrawPickupEffects(app, player, shakeX, shakeY)
    for _, effect in ipairs(app.effects) do
        if effect.kind == "ore_drop" or effect.kind == "artefact_drop"
            or effect.kind == "relic_drop" or effect.kind == "abyss_loot_drop" then
            local sx, sy
            if effect.phase == "collect" then
                sx, sy = effect.screenX, effect.screenY
            else
                sx, sy = self:WorldToScreen(player, effect.x, effect.y, shakeX, shakeY)
            end
            local size = effect.phase == "collect" and 10 or 12
            self:FillRect(math.floor(sx - size * 0.5 + 1), math.floor(sy - size * 0.5 + 2), size, size, { 8, 6, 10, 150 })
            local iconPath
            if effect.kind == "abyss_loot_drop" then
                local grade = AbyssLoot.GetGrade(effect.item and effect.item.grade)
                local color = AbyssLoot.GetGradeColor(grade and grade.id or "F", self.time)
                if grade and grade.glow then
                    nvgBeginPath(self.vg)
                    nvgCircle(self.vg, sx, sy, size * (grade.prismatic and 0.9 or 0.72))
                    nvgFillPaint(self.vg, nvgRadialGradient(self.vg, sx, sy, 1, size,
                        Util.Color(color, 170), Util.Color(color, 0)))
                    nvgFill(self.vg)
                end
                self:DrawAtlasCell(Config.Paths.abyssLootAtlas,
                    effect.item and effect.item.iconIndex or 1,
                    math.floor(sx - size * 0.5), math.floor(sy - size * 0.5), size, size, 1)
            elseif effect.kind == "ore_drop" then
                iconPath = self:GetOreIconPath(effect.ore)
            elseif effect.kind == "artefact_drop" then
                iconPath = Config.Paths.generatedRoot .. "skill_icons/" .. effect.artefactId .. ".png"
            else
                iconPath = self:GetRelicIconPath(effect.relicId)
            end
            if effect.kind ~= "abyss_loot_drop" and not self:DrawImage(iconPath,
                math.floor(sx - size * 0.5), math.floor(sy - size * 0.5), size, size, 1) then
                self:FillRect(math.floor(sx - 3), math.floor(sy - 3), 6, 6, Config.Palette.gold)
            end
        elseif effect.kind == "hud_pop" then
            local alpha = Util.Clamp(effect.life / effect.maxLife, 0, 1)
            nvgBeginPath(self.vg)
            nvgCircle(self.vg, effect.x, effect.y, 3 + (1 - alpha) * 8)
            nvgStrokeColor(self.vg, Util.Color(Config.Palette.gold, math.floor(alpha * 255)))
            nvgStrokeWidth(self.vg, 1.5)
            nvgStroke(self.vg)
        elseif effect.kind == "skill_proc" then
            local sx, sy = self:WorldToScreen(player, effect.x, effect.y, shakeX, shakeY)
            local alpha = Util.Clamp(effect.life / effect.maxLife, 0, 1)
            local age = 1 - alpha
            local size = 16 + math.sin(age * math.pi) * 5
            sy = sy - age * 14
            self:FillRect(math.floor(sx - size * 0.5 - 2), math.floor(sy - size * 0.5 - 2), size + 4, size + 4, { 24, 20, 29, math.floor(alpha * 210) })
            self:StrokeRect(math.floor(sx - size * 0.5 - 2), math.floor(sy - size * 0.5 - 2), size + 4, size + 4, { 244, 187, 43, math.floor(alpha * 255) }, 1)
            self:DrawImage(Config.Paths.generatedRoot .. "skill_icons/" .. effect.node .. ".png", sx - size * 0.5, sy - size * 0.5, size, size, alpha)
        end
    end
end

function Renderer:GetActiveCooldown(definition, app)
    if definition.cooldown then
        local multiplier = app and app.isAbyssRun and definition.capstone
            and WorldTree.GetCapstoneCooldownMultiplier(self.state) or 1
        if app and app.isAbyssRun and definition.capstone then
            local reduction = AbyssDraft.GetStat(app.abyss, "capstone_cooldown_pct")
            multiplier = multiplier * math.max(0.25, 1 - reduction / 100)
                * AbyssRunTools.GetCooldownMultiplier(app.abyss, definition.node)
        end
        local cooldown = definition.cooldown * multiplier
        return app and app.isAbyssRun
            and AbyssRunTools.ApplyCooldownFloor(definition.cooldown, cooldown) or cooldown
    end
    local cooldown
    if definition.attackSpeed then
        cooldown = 1 / math.max(0.1, self.state:GetActiveStat(definition.id, "attack_speed"))
    else
        cooldown = self.state:GetActiveStat(definition.id, "cooldown")
    end
    if app and app.isAbyssRun and AbyssRunTools.IsUnlocked(app.abyss, definition.node) then
        cooldown = cooldown * AbyssRunTools.GetCooldownMultiplier(app.abyss, definition.node)
    end
    return cooldown > 0 and cooldown or 5
end

function Renderer:DrawActiveCooldowns(app)
    local entries = {}
    for _, definition in ipairs(ACTIVE_COOLDOWN_ORDER) do
        local abyssCapstone = definition.capstone and app.abyss and app.abyss.runCapstones
            and app.abyss.runCapstones[definition.node] == true
        local normalUnlocked = not app.isAbyssRun and self.state:IsNodeBought(definition.node)
        local abyssTool = app.isAbyssRun and AbyssRunTools.IsUnlocked(app.abyss, definition.node)
            and not AbyssRunTools.IsEvolved(app.abyss, definition.node)
        if normalUnlocked or abyssTool or (app.isAbyssRun and abyssCapstone) then
            entries[#entries + 1] = definition
        end
    end
    if #entries == 0 then return end

    local compact = app.isAbyssRun
    local perRow = 7
    local tileWidth, tileHeight, gap = compact and 52 or 58, compact and 15 or 18, compact and 2 or 3
    for index, definition in ipairs(entries) do
        local isAbyssTool = app.isAbyssRun and AbyssRunTools.IsUnlocked(app.abyss, definition.node)
            and not AbyssRunTools.IsEvolved(app.abyss, definition.node)
        local isAbyssCapstone = app.isAbyssRun and definition.capstone and app.abyss.runCapstones
            and app.abyss.runCapstones[definition.node] == true
        local row, column, x, y
        if compact then
            row = (index - 1) % perRow
            column = math.floor((index - 1) / perRow)
            x = 4 + column * (tileWidth + gap)
            y = 34 + row * (tileHeight + gap)
        else
            row = math.floor((index - 1) / perRow)
            local rowStart = row * perRow + 1
            local rowCount = math.min(perRow, #entries - rowStart + 1)
            local rowWidth = rowCount * tileWidth + (rowCount - 1) * gap
            column = (index - 1) % perRow
            x = math.floor((480 - rowWidth) * 0.5) + column * (tileWidth + gap)
            y = 70 + row * 21
        end
        local cooldown = self:GetActiveCooldown(definition, app)
        local remaining = Util.Clamp(app.activeTimers[definition.node] or 0, 0, cooldown)
        local progress = cooldown > 0 and 1 - remaining / cooldown or 1
        local procActive = false
        for _, effect in ipairs(app.effects) do
            if effect.kind == "skill_proc" and effect.node == definition.node then
                procActive = true
                break
            end
        end

        self:FillRect(x, y, tileWidth, tileHeight, procActive and { 105, 58, 22, 235 } or { 24, 20, 29, 218 })
        self:StrokeRect(x, y, tileWidth, tileHeight, procActive and Config.Palette.gold or { 80, 71, 91, 220 }, 1)
        local iconSize = compact and 11 or 13
        self:DrawImage(Config.Paths.generatedRoot .. "skill_icons/" .. (definition.iconNode or definition.node) .. ".png",
            x + 2, y + 2, iconSize, iconSize, 1)
        local cooldownText = definition.persistent and "常驻" or (remaining <= 0 and "就绪" or string.format("CD %.1f", remaining))
        if isAbyssTool then
            cooldownText = "L" .. tostring(AbyssRunTools.GetLevel(app.abyss, definition.node)) .. " " .. cooldownText
        elseif isAbyssCapstone then
            cooldownText = "进化 " .. cooldownText
        end
        self:Text(cooldownText, x + (compact and 15 or 18), y + tileHeight * 0.5, compact and 5.5 or 7, Config.Palette.cream,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        self:FillRect(x + 1, y + tileHeight - 2, (tileWidth - 2) * progress, 1, Config.Palette.gold)
    end
end

function Renderer:DrawWorld(app)
    local player = app.player
    local shakeX, shakeY = app:GetCameraShake()
    local depth = math.max(0, player.y - Config.SURFACE_Y * Config.TILE_SIZE)
    self:FillRect(0, 0, Config.DESIGN_WIDTH, Config.DESIGN_HEIGHT, Config.Palette.ink)
    if depth < 260 then
        local surfaceY = 135 - player.y + Config.SURFACE_Y * Config.TILE_SIZE
        self:DrawImage(Config.Paths.surface, 0, surfaceY - 220, 480, 270, Util.Clamp(1 - depth / 280, 0, 1))
    end
    self:DrawImage(Config.Paths.parallax1, 0, (self.time * 2 + depth * 0.05) % 270 - 20, 480, 270, 0.25)
    self:DrawImage(Config.Paths.parallax2, 0, (self.time + depth * 0.025) % 270 - 20, 480, 270, 0.35)

    local topWorld = player.y - Config.DESIGN_HEIGHT * 0.5 - 18
    local bottomWorld = player.y + Config.DESIGN_HEIGHT * 0.5 + 18
    local minTileY = math.max(Config.SURFACE_Y, math.floor(topWorld / Config.TILE_SIZE))
    local maxTileY = math.floor(bottomWorld / Config.TILE_SIZE)
    local minTileX = -16
    local maxTileX = 16
    for y = minTileY, maxTileY do
        for x = minTileX, maxTileX do
            local tile = app.world:GetTile(x, y)
            if tile then
                local sx, sy = self:WorldToScreen(player, x * 16, y * 16, shakeX, shakeY)
                self:DrawTile(tile, math.floor(sx), math.floor(sy))
            end
        end
    end

    for _, effect in ipairs(app.effects) do
        local sx, sy = self:WorldToScreen(player, effect.x, effect.y, shakeX, shakeY)
        local alpha = effect.life and Util.Clamp(effect.life / (effect.maxLife or 1), 0, 1) or 1
        if effect.kind == "particle" then
            self:FillRect(math.floor(sx), math.floor(sy), effect.size or 2, effect.size or 2, { effect.r or 244, effect.g or 156, effect.b or 39, math.floor(alpha * 255) })
        elseif effect.kind == "ring" then
            nvgBeginPath(self.vg)
            nvgCircle(self.vg, sx, sy, effect.radius * (1 - alpha * 0.25))
            nvgStrokeColor(self.vg, nvgRGBA(effect.r or 244, effect.g or 156, effect.b or 39, math.floor(alpha * 255)))
            nvgStrokeWidth(self.vg, 2)
            nvgStroke(self.vg)
        elseif EffectRenderer.Draw(self, effect, sx, sy, alpha) then
        elseif effect.kind == "dynamite" then
            nvgSave(self.vg)
            nvgTranslate(self.vg, sx, sy)
            nvgRotate(self.vg, effect.rotation or 0)
            self:DrawImage(Config.Paths.generatedRoot .. "effects/dynamite.png", -8, -8, 16, 16, 1)
            nvgRestore(self.vg)
        elseif effect.kind == "explosion" then
            local age = 1 - alpha
            local frame = math.min(5, math.floor(age * 6))
            local size = Util.Clamp(effect.radius * 2.4, 48, 96)
            self:DrawImage(Config.Paths.generatedRoot .. "effects/explosion_" .. frame .. ".png", sx - size * 0.5, sy - size * 0.5, size, size, 1)
        elseif effect.kind == "hit_flash" then
            local age = effect.maxLife - effect.life
            local flashAlpha = age <= 0.05 and 1 or Util.Clamp(1 - (age - 0.05) / 0.05, 0, 1)
            self:DrawImage(
                Config.Paths.generatedRoot .. "damage/flash_" .. effect.level .. ".png",
                math.floor(sx),
                math.floor(sy),
                16,
                16,
                flashAlpha
            )
        elseif effect.kind == "chest_open" then
            local age = 1 - alpha
            local bounce = math.sin(age * math.pi) * 4
            self:DrawImage(Config.Paths.chestOpen, sx - 11, sy - 11 - bounce, 22, 22, alpha)
        elseif effect.kind == "loot_multiplier" then
            local age = 1 - alpha
            local floatY = sy - age * 18
            local size = effect.jackpot and 22 or 14
            if effect.jackpot then
                self:DrawImage(Config.Paths.goldenDrill, sx - size - 3, floatY - size * 0.5, size, size, alpha)
            end
            self:Text(effect.text, sx, floatY, effect.jackpot and 13 or 10, Config.Palette.gold, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        elseif effect.kind == "relic_proc" then
            local relic = self.state:GetRelic(effect.relicId)
            local age = 1 - alpha
            local floatY = sy - age * 15
            local accent = relic and (Config.Palette[relic.color] or Config.Palette.gold) or Config.Palette.gold
            self:FillRect(sx - 45 + 2, floatY - 10 + 2, 90, 20, { 8, 6, 10, math.floor(alpha * 170) })
            self:FillRect(sx - 45, floatY - 10, 90, 20, { 36, 29, 42, math.floor(alpha * 225) })
            self:StrokeRect(sx - 45, floatY - 10, 90, 20, { accent[1], accent[2], accent[3], math.floor(alpha * 255) }, 1)
            self:DrawImage(self:GetRelicIconPath(relic), sx - 42, floatY - 8, 16, 16, alpha)
            self:Text(effect.text, sx - 22, floatY, 8, { accent[1], accent[2], accent[3], math.floor(alpha * 255) }, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        end
    end

    local px, py = self:WorldToScreen(player, player.x, player.y, shakeX, shakeY)
    if app.isAbyssRun and app.state.abyssCallsign and app.state.abyssCallsign ~= "" then
        self:Text(app.state.abyssCallsign, px, py - 21, 7, Config.Palette.cyan, NVG_ALIGN_CENTER)
    end
    if app.laserActive then
        local beams = (not app.isAbyssRun and app.laserBeams) or nil
        if beams and #beams > 0 then
            for _, beam in ipairs(beams) do
                local lx, ly = self:WorldToScreen(player, beam.endX, beam.endY, shakeX, shakeY)
                nvgBeginPath(self.vg)
                nvgMoveTo(self.vg, px, py)
                nvgLineTo(self.vg, lx, ly)
                nvgStrokeColor(self.vg, nvgRGBA(40, 204, 219, beam.secondary and 90 or 125))
                nvgStrokeWidth(self.vg, beam.secondary and 3 or 5)
                nvgStroke(self.vg)
                nvgBeginPath(self.vg)
                nvgMoveTo(self.vg, px, py)
                nvgLineTo(self.vg, lx, ly)
                nvgStrokeColor(self.vg, nvgRGBA(235, 248, 215, beam.secondary and 185 or 235))
                nvgStrokeWidth(self.vg, beam.secondary and 1 or 1.5)
                nvgStroke(self.vg)
            end
        elseif app.laserEndX and app.laserEndY then
            local lx, ly = self:WorldToScreen(player, app.laserEndX, app.laserEndY, shakeX, shakeY)
            nvgBeginPath(self.vg)
            nvgMoveTo(self.vg, px, py)
            nvgLineTo(self.vg, lx, ly)
            nvgStrokeColor(self.vg, nvgRGBA(95, 245, 255, 225))
            nvgStrokeWidth(self.vg, app.isAbyssRun and 3 or 2)
            nvgStroke(self.vg)
            nvgBeginPath(self.vg)
            nvgMoveTo(self.vg, px, py)
            nvgLineTo(self.vg, lx, ly)
            nvgStrokeColor(self.vg, nvgRGBA(235, 255, 245, 245))
            nvgStrokeWidth(self.vg, 1)
            nvgStroke(self.vg)
        end
    end
    local honorRank = app.isAbyssRun and require("diggin.SeasonHonors").GetCurrentSkinRank()
    local characterSkin = Cosmetics.GetEquipped(self.state, "character")
    if characterSkin then
        Cosmetics.Draw(self, characterSkin, math.floor(px - 10), math.floor(py - 13), 20, 22, 1)
    elseif honorRank then
        self:DrawSheetCell(require("diggin.SeasonHonors").skinAtlas, 3, 2, honorRank,
            math.floor(px - 12), math.floor(py - 17), 24, 30, 1)
    elseif app.laserActive then
        local laserFrame = math.floor(self.time * 7.5) % 4
        self:DrawImage(Config.Paths.generatedRoot .. "player/laser_" .. laserFrame .. ".png", math.floor(px - 13), math.floor(py - 12), 26, 24, 1)
    else
        local playerFrame = math.floor(self.time * 15) % 6
        self:DrawImage(Config.Paths.generatedRoot .. "player/default_" .. playerFrame .. ".png", math.floor(px - 8), math.floor(py - 8), 16, 16, 1)
    end
    nvgSave(self.vg)
    nvgTranslate(self.vg, px, py + 1)
    nvgRotate(self.vg, app.aimAngle)
    local drillSkin = Cosmetics.GetEquipped(self.state, "drill")
    if drillSkin then
        Cosmetics.Draw(self, drillSkin, 2, -8, 21, 16, 1)
    elseif self.state.goldenDrillCharges > 0 then
        self:DrawImage(Config.Paths.goldenDrill, 2, -10, 20, 20, 1)
    else
        local drillFrame = math.floor(self.time * 18) % 6
        self:DrawImage(Config.Paths.generatedRoot .. "player/drill_" .. drillFrame .. ".png", 4, -8, 16, 16, 1)
    end
    nvgRestore(self.vg)

    local fovRadius = math.max(46, self.state:GetGeneralStat("fov_radius") * 2.2)
    nvgBeginPath(self.vg)
    nvgRect(self.vg, 0, 0, 480, 270)
    nvgFillPaint(self.vg, nvgRadialGradient(self.vg, px, py, fovRadius * 0.55, fovRadius, nvgRGBA(0, 0, 0, 0), nvgRGBA(9, 6, 11, 220)))
    nvgFill(self.vg)
    AbyssRenderer.DrawWorldOverlay(self, app)
    self:DrawHud(app)
    self:DrawPickupEffects(app, player, shakeX, shakeY)
end

function Renderer:DrawHud(app)
    self.hudButtons = {}
    local fuelRatio = Util.Clamp(app.fuel / app.maxFuel, 0, 1)
    self:FillRect(12, 12, 150, 16, Config.Palette.shadow)
    self:FillRect(14, 14, 146, 12, Config.Palette.inkSoft)
    self:FillRect(15, 15, 144 * fuelRatio, 10, fuelRatio < 0.2 and Config.Palette.red or Config.Palette.green)
    self:Text(string.format("燃料 %.1f / %.1f", app.fuel, app.maxFuel), 87, 20, 9, Config.Palette.cream, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local tileY = math.floor(app.player.y / Config.TILE_SIZE)
    local layerIndex = app.world:GetLayerIndex(tileY)
    local layer = Config.Layers[layerIndex]
    local runLabel = app.isAbyssRun and (app.abyss:IsHardcore() and "深渊硬核" or "深渊无尽")
        or string.format("密度 %d", self.state.prestige)
    local layerLabel = app.isAbyssRun and string.format("第%d层·Boss形态%d", app.abyss:GetFloor(),
        app.abyss:GetBossEvolutionTier() + 1)
        or string.format("第%d/10层", layerIndex)
    self:Text(string.format("%s · %s · 深度 %dm · %s", runLabel, layerLabel, math.max(0, tileY - Config.SURFACE_Y), layer.zh), 468, 14, 8, Config.Palette.cream, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)

    if not app.hudCollapsed then
        if not app.isAbyssRun then
            self:DrawOreCounters(app, self.state.runInventory, 238, ORE_HUD_ORDER)
            self:DrawRelicLoadout(app)
            self:DrawArtefactBar(app)
            self:DrawGoldenDrillAd(app)
        end
        if not app.isAbyssRun then
            self:DrawImage(Config.Paths.stardrop, 240, 72, 10, 10, 1)
            self:Text(string.format("%d/%d", self.state:GetDensityStarCount(), Config.STARDROPS_FOR_FINAL_DENSITY), 252, 77, 7, Config.Palette.cyan, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            self:Text("徽章 " .. Util.FormatNumber(self.state.inventory.MissionRewardOre or 0), 294, 77, 7, Config.Palette.gold, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        end
        self:DrawActiveCooldowns(app)
    end

    if self.state:IsNodeBought("OverdriveActive") and not app.isAbyssRun then
        local ratio = Util.Clamp(app.overdriveEnergy / app.overdriveMax, 0, 1)
        self:FillRect(356, 36, 112, 10, Config.Palette.shadow)
        self:FillRect(358, 38, 108 * ratio, 6, Config.Palette.orange)
        self:Text("超频", 352, 41, 7, Config.Palette.cream, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    end
    if app.isAbyssRun or (self.state:IsNodeBought("Laser") and not app.isAbyssRun) then
        local cooling = app.isAbyssRun and (app.laserCooldownRemaining or 0) > 0
        local ratio = cooling
            and Util.Clamp(1 - app.laserCooldownRemaining / Config.Abyss.towerLaserCooldown, 0, 1)
            or Util.Clamp(app.laserEnergy / app.laserMax, 0, 1)
        self:FillRect(356, 50, 112, 10, Config.Palette.shadow)
        self:FillRect(358, 52, 108 * ratio, 6, cooling and Config.Palette.purple or Config.Palette.cyan)
        local laserLabel = cooling and string.format("冷却 %.1f", app.laserCooldownRemaining)
            or (app.isAbyssRun and "激光·自动" or "激光")
        self:Text(laserLabel, 352, 55, 7, Config.Palette.cream, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    end
    self.hudButtons.hud_toggle = { x = 402, y = 70, w = 24, h = 22, enabled = true }
    self:FillRect(402, 70, 24, 22, Config.Palette.inkSoft)
    self:StrokeRect(402, 70, 24, 22, Config.Palette.creamDim, 1)
    self:Text(app.hudCollapsed and "展" or "收", 414, 81, 9, Config.Palette.cream, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    self.hudButtons.help = { x = 428, y = 70, w = 24, h = 22, enabled = true }
    self:FillRect(428, 70, 24, 22, Config.Palette.inkSoft)
    self:StrokeRect(428, 70, 24, 22, Config.Palette.creamDim, 1)
    self:Text("?", 440, 81, 11, Config.Palette.gold, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    self.hudButtons.pause = { x = 454, y = 70, w = 24, h = 22, enabled = true }
    self:FillRect(454, 70, 24, 22, Config.Palette.inkSoft)
    self:StrokeRect(454, 70, 24, 22, Config.Palette.creamDim, 1)
    self:Text("Ⅱ", 466, 81, 11, Config.Palette.cream, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    local controlIdle = { 23, 19, 28, 185 }
    local controlActive = { 244, 187, 43, 205 }
    local controls = self.state.GetMobileControls and self.state:GetMobileControls() or Config.Controls
    self.hudButtons.move_pad = {
        x = controls.moveX - controls.moveRadius - controls.moveTouchPadding,
        y = controls.moveY - controls.moveRadius - controls.moveTouchPadding,
        w = (controls.moveRadius + controls.moveTouchPadding) * 2,
        h = (controls.moveRadius + controls.moveTouchPadding) * 2, enabled = true,
        circle = true, cx = controls.moveX, cy = controls.moveY,
        radius = controls.moveRadius + controls.moveTouchPadding,
    }
    if app.isAbyssRun then
        self.hudButtons.abyss_jump = { x = controls.jumpX, y = controls.jumpY,
            w = controls.jumpW, h = controls.jumpH, enabled = true }
    end
    self.hudButtons.aim_pad = {
        x = controls.aimX - controls.aimRadius - controls.aimTouchPadding,
        y = controls.aimY - controls.aimRadius - controls.aimTouchPadding,
        w = (controls.aimRadius + controls.aimTouchPadding) * 2,
        h = (controls.aimRadius + controls.aimTouchPadding) * 2, enabled = true,
        circle = true, cx = controls.aimX, cy = controls.aimY,
        radius = controls.aimRadius + controls.aimTouchPadding,
    }
    self.hudButtons.auto_dig = { x = controls.autoX, y = controls.autoY, w = controls.autoW, h = controls.autoH, enabled = true }
    nvgBeginPath(self.vg)
    nvgCircle(self.vg, controls.moveX, controls.moveY, controls.moveRadius)
    nvgFillColor(self.vg, Util.Color(controlIdle))
    nvgFill(self.vg)
    nvgStrokeColor(self.vg, Util.Color(math.abs(app.mobileMove) > 0.05 and Config.Palette.gold or Config.Palette.creamDim))
    nvgStrokeWidth(self.vg, 1.5)
    nvgStroke(self.vg)
    nvgBeginPath(self.vg)
    nvgCircle(self.vg, controls.moveX + app.mobileMove * controls.moveRadius * 0.58, controls.moveY, 9)
    nvgFillColor(self.vg, Util.Color(math.abs(app.mobileMove) > 0.05 and controlActive or Config.Palette.creamDim))
    nvgFill(self.vg)
    self:Text("移动", controls.moveX, controls.moveY - controls.moveRadius - 8, 6,
        Config.Palette.creamDim, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if app.isAbyssRun then
        local jumping = app.player.onGround == false and (app.player.vy or 0) < 0
        self:FillRect(controls.jumpX, controls.jumpY, controls.jumpW, controls.jumpH,
            jumping and controlActive or controlIdle)
        self:StrokeRect(controls.jumpX, controls.jumpY, controls.jumpW, controls.jumpH,
            jumping and Config.Palette.gold or Config.Palette.cyan, 1)
        self:Text("跳", controls.jumpX + controls.jumpW * 0.5, controls.jumpY + 14, 11,
            Config.Palette.cream, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        self:Text("W/↑", controls.jumpX + controls.jumpW * 0.5, controls.jumpY + 28, 6,
            Config.Palette.creamDim, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end
    nvgBeginPath(self.vg)
    nvgCircle(self.vg, controls.aimX, controls.aimY, controls.aimRadius)
    nvgFillColor(self.vg, Util.Color(app.leftHeld and controlActive or controlIdle))
    nvgFill(self.vg)
    nvgStrokeColor(self.vg, Util.Color(app.leftHeld and Config.Palette.gold or Config.Palette.creamDim))
    nvgStrokeWidth(self.vg, 1.5)
    nvgStroke(self.vg)
    local aimDX, aimDY = math.cos(app.aimAngle), math.sin(app.aimAngle)
    nvgBeginPath(self.vg)
    nvgMoveTo(self.vg, controls.aimX, controls.aimY)
    local aimHandle = controls.aimRadius * 0.55
    nvgLineTo(self.vg, controls.aimX + aimDX * aimHandle, controls.aimY + aimDY * aimHandle)
    nvgStrokeColor(self.vg, Util.Color(Config.Palette.cream))
    nvgStrokeWidth(self.vg, 2)
    nvgStroke(self.vg)
    nvgBeginPath(self.vg)
    nvgCircle(self.vg, controls.aimX + aimDX * aimHandle, controls.aimY + aimDY * aimHandle, 5)
    nvgFillColor(self.vg, Util.Color(Config.Palette.cream))
    nvgFill(self.vg)
    self:Text("360°钻探", controls.aimX, controls.aimY - controls.aimRadius - 9, 6,
        Config.Palette.creamDim, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    self:FillRect(controls.autoX, controls.autoY, controls.autoW, controls.autoH, app.autoDigLocked and controlActive or controlIdle)
    self:StrokeRect(controls.autoX, controls.autoY, controls.autoW, controls.autoH, app.autoDigLocked and Config.Palette.gold or Config.Palette.creamDim, 1)
    self:Text(app.autoDigLocked and "停" or "锁", controls.autoX + controls.autoW * 0.5, controls.autoY + 13, 11, Config.Palette.cream, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    self:Text("向下", controls.autoX + controls.autoW * 0.5, controls.autoY + 27, 6, Config.Palette.creamDim, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if not app.isAbyssRun and self.state:IsNodeBought("Laser") then
        self.hudButtons.laser = { x = controls.laserX, y = controls.laserY, w = controls.laserW, h = controls.laserH, enabled = true }
        self:FillRect(controls.laserX, controls.laserY, controls.laserW, controls.laserH, app.rightHeld and Config.Palette.cyan or controlIdle)
        self:StrokeRect(controls.laserX, controls.laserY, controls.laserW, controls.laserH, Config.Palette.cyan, 1)
        self:Text("光", controls.laserX + controls.laserW * 0.5, controls.laserY + controls.laserH * 0.5, 10, Config.Palette.cream, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end
    if app.frenzyTime > 0 then
        self:Text(string.format("狂热 ×%.1f  %.1fs", app.frenzyMultiplier, app.frenzyTime), 240,
            app.isAbyssRun and 92 or 40, 12, Config.Palette.gold, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    end
    if app:IsLastDitchActive() then
        self:Text("背水一战：钻速 ×2" .. (self.state:IsNodeBought("LastDitchArtefact") and " · 资源 ×2" or ""), 240, 55, 10, Config.Palette.red, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    end
    if app.densityUnlockTimer > 0 then
        self:FillRect(166, 116, 148, 24, { 20, 16, 25, 225 })
        self:StrokeRect(166, 116, 148, 24, Config.Palette.gold, 1)
        self:Text("已解锁密度 " .. tostring(app.newDensityUnlocked), 240, 128, 11, Config.Palette.gold, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end
    AbyssRenderer.DrawHud(self, app)
end

function Renderer:DrawEnd(app)
    self.endButtons = {}
    if app.showCombatReport then require("diggin.CombatReportRenderer").Draw(self, app); return end
    self:DrawWorld(app)
    self:FillRect(0, 0, 480, 270, { 10, 7, 12, 190 })
    local abyssModeName = app.lastAbyssMode == "hardcore" and "硬核模式" or "无尽模式"
    self:DrawPanel(80, 34, 320, 210,
        app.lastRunWasAbyss and ("深渊" .. abyssModeName .. "结算") or "本次钻探结束")
    local total = 0
    for _, value in pairs(self.state.runInventory) do total = total + value end
    local headline
    if app.endReason == "abyss_caught" then headline = "巨物追上了你"
    elseif app.endReason == "abyss_enemy" then headline = "怪物耗尽了燃料"
    elseif app.endReason == "abyss_bombardment" then headline = "深渊轰击耗尽了燃料"
    elseif app.endReason == "manual" or app.endReason == "abyss_extract" then headline = app.lastRunWasAbyss and "安全撤离深渊" or "安全返航 · 已结算"
    else headline = "燃料耗尽" end
    local headlineColor = (app.endReason == "manual" or app.endReason == "abyss_extract") and Config.Palette.green or Config.Palette.red
    self:Text(headline, 240, 61, 18, headlineColor, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    local settlement = app.lastSettlement or {}
    local abyss = settlement.abyss or app.lastAbyssSettlement
    if app.lastRunWasAbyss and abyss then
        self:Text(string.format("生存 %.1fs · 到达第 %d 层 · 深度 %dm", abyss.time or 0,
            abyss.floor or 1, app.runDepth), 240, 88, 10, Config.Palette.cream, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    else
        self:Text(string.format("密度 %d · 到达第 %d/10 层 · 深度 %dm", self.state.prestige,
            app.currentLayerIndex, app.runDepth), 240, 88, 10, Config.Palette.cream, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    end
    local creditedTotal = (settlement.resourceTotal or total) + (settlement.resourceBonus or 0) + (settlement.adBonus or 0)
    local resourceLine = app.lastRunWasAbyss and abyss
        and string.format("金币获得 %d（剩余%d）· 击破怪物 %d · 宝箱 %d", abyss.coinsEarned or abyss.coins or 0,
            abyss.coins or 0, abyss.kills or 0, abyss.chests or 0)
        or string.format("本局矿石入账 %s", Util.FormatNumber(creditedTotal))
    self:Text(resourceLine, 240, 106, 10, Config.Palette.cream, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    local settlementText = app.lastRunWasAbyss and abyss
        and string.format("本局得分 %s · Boss形态%d %s", Util.FormatNumber(abyss.score or 0),
            (abyss.bossEvolution or 0) + 1, abyss.bossEvolutionName or "噬岩幼体")
        or string.format("遗物核心 +%d", settlement.coreReward or 0)
    if not app.lastRunWasAbyss and (settlement.resourceBonus or 0) > 0 then
        settlementText = settlementText .. " · 遗物结算加成 +" .. Util.FormatNumber(settlement.resourceBonus)
    end
    self:Text(settlementText, 240, 124, 9, Config.Palette.gold, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    if app.lastRunWasAbyss and abyss then
        local best = math.max(0, math.floor(abyss.bestTime or 0))
        local bestText = string.format("%02d:%02d", math.floor(best / 60), best % 60)
        self:DrawImage(Config.Paths.worldTreePoint, 159, 140, 13, 13, 1)
        local lootText = (abyss.lootDrops or 0) > 0
            and string.format(" · 装备 %d件 最高%s", abyss.lootDrops, abyss.bestLootGrade or "F") or ""
        local rankText = abyss.leaderboardRank and (" · 排名#" .. tostring(abyss.leaderboardRank))
            or (abyss.leaderboardSubmitted and " · 深度榜已提交" or (abyss.leaderboardPending and " · 排行榜提交中" or ""))
        self:Text(string.format("世界树点数 +%d · 最佳 %s%s%s", abyss.points or 0, bestText, lootText, rankText),
            176, 142, 7, Config.Palette.cyan)
    else
        local starText
        if settlement.finalDensityUnlockedNow then
            starText = "10颗星辰齐聚 · 终极密度开启"
        else
            starText = string.format("星辰 +%d · 终极进度 %d/%d", settlement.newDensityStars or 0,
                settlement.densityStarCount or self.state:GetDensityStarCount(), Config.STARDROPS_FOR_FINAL_DENSITY)
        end
        self:DrawImage(Config.Paths.stardrop, 159, 141, 12, 12, 1)
        self:Text(starText, 176, 142, 8,
            settlement.finalDensityUnlockedNow and Config.Palette.gold or Config.Palette.cyan)
    end

    local eligible = math.max(0, math.floor(tonumber(settlement.adBonusEligibleTotal) or 0))
    local adLabel
    if app.settlementAdPending then
        adLabel = "广告播放中…"
    elseif app.settlementAdClaimed then
        adLabel = "双倍已领取 · 额外 +" .. Util.FormatNumber(settlement.adBonus or 0)
    else
        adLabel = "看广告 · 本局矿石额外 +" .. Util.FormatNumber(eligible)
    end
    self:DrawButton("settlement_double", adLabel, 135, 163, 210, 28,
        eligible > 0 and not app.settlementAdClaimed and not app.adPending,
        app.settlementAdClaimed or app.endHover == "settlement_double", self.endButtons)

    local navigationEnabled = not app.adPending
    self:DrawButton("combat_report", "本局战报", 405, 204, 70, 25,
        navigationEnabled, app.endHover == "combat_report", self.endButtons)
    if abyss and abyss.cosmeticId and Cosmetics.byId[abyss.cosmeticId] then
        self:Text("获得时装：" .. Cosmetics.byId[abyss.cosmeticId].name .. " · 在主菜单时装库装备",
            240, 194, 7, Config.Palette.gold, NVG_ALIGN_CENTER)
    end
    self:DrawButton(app.lastRunWasAbyss and "leaderboard" or "skills", app.lastRunWasAbyss and "深度榜" or "技能树",
        101, 205, 84, 24, navigationEnabled,
        app.endHover == (app.lastRunWasAbyss and "leaderboard" or "skills"), self.endButtons)
    self:DrawButton(app.lastRunWasAbyss and "world_tree" or "relics", app.lastRunWasAbyss and "世界树" or "遗物库",
        198, 205, 84, 24, navigationEnabled,
        app.endHover == (app.lastRunWasAbyss and "world_tree" or "relics"), self.endButtons)
    self:DrawButton("again", app.lastRunWasAbyss and "再次下潜" or "再次钻探", 295, 205, 84, 24,
        navigationEnabled, app.endHover == "again", self.endButtons)
end

function Renderer:GetSkillNodePosition(node, view)
    return view.x + node.position[1] * view.zoom, view.y + node.position[2] * view.zoom
end

function Renderer:DrawSkillIcon(node, x, y, size, alpha)
    return self:DrawImage(Config.Paths.generatedRoot .. "skill_icons/" .. node.id .. ".png", x, y, size, size, alpha)
end

function Renderer:DrawSkills(app)
    self.skillNodeRects = {}
    self.hudButtons = {}
    self:DrawStarfield()
    local view = app.skillView
    for _, node in ipairs(self.state.skillData.nodes) do
        if self.state:IsNodeVisible(node) then
            local x1, y1 = self:GetSkillNodePosition(node, view)
            for _, childId in ipairs(node.unlocks or {}) do
                local child = self.state.nodeById[childId]
                if child and self.state:IsNodeVisible(child) then
                local x2, y2 = self:GetSkillNodePosition(child, view)
                local bought = self.state:GetLevel(node.id) >= (child.level_to_unlock or 1)
                nvgBeginPath(self.vg)
                nvgMoveTo(self.vg, x1, y1)
                nvgLineTo(self.vg, x2, y2)
                nvgStrokeColor(self.vg, Util.Color(bought and Config.BranchColors[node.branch] or { 79, 69, 85, 170 }))
                nvgStrokeWidth(self.vg, bought and 2 or 1)
                nvgStroke(self.vg)
                end
            end
        end
    end

    for _, node in ipairs(self.state.skillData.nodes) do
        if self.state:IsNodeVisible(node) then
            local x, y = self:GetSkillNodePosition(node, view)
            local size = math.max(10, 18 * view.zoom)
            if x > -size and x < 480 + size and y > 48 - size and y < 238 + size then
            local level = self.state:GetLevel(node.id)
            local available = self.state:IsAvailable(node)
            local maxed = level >= (node.max_level or 0)
            local color = Config.BranchColors[node.branch] or Config.Palette.cream
            local alpha = available and 255 or 75
            self:FillRect(x - size * 0.5 + 2, y - size * 0.5 + 2, size, size, Config.Palette.shadow)
            self:FillRect(x - size * 0.5, y - size * 0.5, size, size, level > 0 and color or Config.Palette.inkSoft)
            self:StrokeRect(x - size * 0.5, y - size * 0.5, size, size, maxed and Config.Palette.cream or { color[1], color[2], color[3], alpha }, maxed and 2 or 1)
            self:DrawSkillIcon(node, x - size * 0.38, y - size * 0.38, size * 0.76, available and 1 or 0.28)
            if node.is_artefact then
                local marker = level > 0 and "●" or (self.state.artefacts[node.id] and "◆" or "◇")
                local markerColor = level > 0 and Config.Palette.green or (self.state.artefacts[node.id] and Config.Palette.gold or Config.Palette.creamDim)
                self:Text(marker, x + size * 0.48, y - size * 0.48, math.max(6, 7 * view.zoom), markerColor, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            end
            if level > 0 and (node.max_level or 1) > 1 then
        self:Text(level .. "/" .. node.max_level, x, y + size * 0.52, math.max(6, 7 * view.zoom), Config.Palette.cream, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            end
                self.skillNodeRects[node.id] = { x = x - size * 0.65, y = y - size * 0.65, w = size * 1.3, h = size * 1.3, enabled = true }
            end
        end
    end

    self:FillRect(0, 0, 480, 28, { 32, 27, 36, 245 })
    self:Text("技能树", 12, 7, 12, Config.Palette.cream)
    local maxDensity = self.state:GetMaxDensity()
    self:DrawButton("density_prev", "◀", 78, 4, 18, 20, self.state.prestige > 1, app.skillHover == "density_prev", self.hudButtons)
    self:Text(self.state.prestige == 11 and "终极密度" or string.format("密度 %d/10", self.state.prestige), 139, 14, 8, Config.Palette.cream, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    self:DrawButton("density_next", "▶", 181, 4, 18, 20, self.state.prestige < maxDensity, app.skillHover == "density_next", self.hudButtons)
    self:DrawButton("materials", "材料图鉴", 302, 4, 76, 20, true, app.skillHover == "materials", self.hudButtons)
    self:DrawButton("play", "开始钻探", 385, 4, 84, 20, true, app.skillHover == "play", self.hudButtons)
    self:DrawOreCounters(app, self.state.inventory, 29, ALL_RESOURCE_ORDER)
    self.hudButtons.back = { x = 8, y = 242, w = 54, h = 20, enabled = true }
    self:DrawButton("back", "主菜单", 8, 242, 54, 20, true, app.skillHover == "back", self.hudButtons)
    self:Text("拖动平移 · 滚轮/双指缩放 · 点击节点升级", 240, 251, 8, Config.Palette.creamDim, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

    local selected = app.selectedSkill and self.state.nodeById[app.selectedSkill]
    if selected then self:DrawSkillTooltip(selected, app) end
end

function Renderer:DrawSkillTooltip(node, app)
    local x, y = 294, 45
    local w, h = 174, 184
    self:DrawPanel(x, y, w, h, SkillText.GetName(node))
    self:TextBox(SkillText.GetSummary(node, self.state), x + 8, y + 25, w - 16, 8, Config.Palette.cream)
    self:FillRect(x + 8, y + 70, w - 16, 1, { 86, 77, 95, 210 })
    self:TextBox(SkillText.GetDetail(node, self.state), x + 8, y + 77, w - 16, 7, Config.Palette.creamDim)
    local costParts = {}
    for ore, value in pairs(self.state:GetCost(node)) do
        local oreData = Config.Ores[ore]
        costParts[#costParts + 1] = (oreData and oreData.zh or ore) .. " " .. Util.FormatNumber(value)
    end
    table.sort(costParts)
    local level = self.state:GetLevel(node.id)
    self:Text("等级 " .. level .. "/" .. tostring(node.max_level or 0), x + 8, y + h - 50, 8, Config.Palette.cream)
    self:Text(#costParts > 0 and table.concat(costParts, "  ") or "无需资源", x + 8, y + h - 37, 7, Config.Palette.gold)
    local canBuy = self.state:CanBuy(node)
    local buttonLabel = "资源不足"
    if canBuy then
        buttonLabel = "升级"
    elseif level >= node.max_level then
        buttonLabel = "已满级"
    elseif node.is_artefact and level == 0 and not self.state.artefacts[node.id] then
        buttonLabel = "需宝箱天赋遗物"
    elseif not self.state:IsAvailable(node) then
        buttonLabel = "分支未解锁"
    end
    self:DrawButton("buy_skill", buttonLabel, x + w - 72, y + h - 24, 64, 18, canBuy, app.skillHover == "buy_skill", self.hudButtons)
end

function Renderer:DrawRelics(app)
    self.relicButtons = {}
    self:DrawStarfield()
    self:FillRect(0, 0, 480, 28, { 32, 27, 36, 245 })
    self:Text("遗物库", 12, 7, 12, Config.Palette.cream)
    self:DrawButton("relic_tab_standard", "普通遗物", 66, 4, 62, 20, true, app.relicTab == "standard", self.relicButtons)
    self:DrawButton("relic_tab_talent", "天赋遗物", 132, 4, 62, 20, true, app.relicTab == "talent", self.relicButtons)
    if app.relicTab == "talent" then
        self:Text(string.format("图鉴 %d/%d · 持有 %d · 生效 %d", self.state:GetArtefactDiscoveredCount(), #self.state:GetArtefactNodes(), #self.state:GetArtefactNodeIds(), self.state:GetArtefactActiveCount()), 201, 14, 7, Config.Palette.gold, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    else
        self:Text(string.format("核心 %s · 收藏 %d/20 · 装备 %d/4", Util.FormatNumber(self.state.relicCores), self.state:GetRelicUnlockedCount(), #self.state.equippedRelics), 201, 14, 7, Config.Palette.gold, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    end
    self:DrawButton("back", "主菜单", 352, 4, 54, 20, true, app.relicHover == "back", self.relicButtons)
    self:DrawButton("play", "开始钻探", 412, 4, 58, 20, true, app.relicHover == "play", self.relicButtons)

    if app.relicTab == "talent" then
        ArtefactCodex.Draw(self, app)
        return
    end

    self:DrawPanel(8, 34, 172, 84, "装备栏 · 点击已装备遗物可卸下")
    local equipped = self.state:GetEquippedRelics()
    for slot = 1, 4 do
        local x, y = 16 + (slot - 1) * 40, 59
        local relic = equipped[slot]
        local accent = relic and (Config.Palette[relic.color] or Config.Palette.gold) or { 80, 71, 91, 180 }
        self:FillRect(x + 3, y + 3, 32, 32, Config.Palette.shadow)
        self:FillRect(x, y, 32, 32, relic and { 52, 42, 60, 245 } or { 24, 20, 29, 210 })
        self:StrokeRect(x, y, 32, 32, accent, relic and 2 or 1)
        if relic then
            self:DrawImage(self:GetRelicIconPath(relic), x + 4, y + 4, 24, 24, 1)
        else
            self:Text(tostring(slot), x + 16, y + 16, 9, { 95, 87, 103, 220 }, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        end
        self.relicButtons["relic_slot:" .. tostring(slot)] = { x = x, y = y, w = 32, h = 32, enabled = relic ~= nil }
    end
    self:Text("最多装备 4 件 · 加成在钻探中实时生效", 16, 101, 7, Config.Palette.creamDim)

    local selected = self.state:GetRelic(app.selectedRelic) or self.state.relicData.list[1]
    self:DrawPanel(8, 124, 172, 108, selected.name)
    local selectedAccent = Config.Palette[selected.color] or Config.Palette.gold
    self:FillRect(16 + 2, 149 + 2, 38, 38, Config.Palette.shadow)
    self:FillRect(16, 149, 38, 38, { 36, 29, 42, 240 })
    self:StrokeRect(16, 149, 38, 38, selectedAccent, 2)
    self:DrawImage(self:GetRelicIconPath(selected), 21, 154, 28, 28, 1)
    self:Text("地图 " .. tostring(selected.map) .. " · 研究费用 " .. tostring(selected.cost) .. " 核心", 60, 150, 7, Config.Palette.creamDim)
    self:TextBox(selected.description, 60, 164, 110, 9, Config.Palette.cream)
    local unlocked = self.state:IsRelicUnlocked(selected.id)
    local equippedSelected = self.state:IsRelicEquipped(selected.id)
    local available = self.state:IsRelicMapAvailable(selected)
    local seen = self.state.seenRelics[selected.id] == true
    local status = unlocked and (equippedSelected and "已装备 · 效果生效中" or "已收藏 · 未装备")
        or (available and (seen and "宝箱已发现 · 可用核心研究" or ("去密度 " .. tostring(selected.map) .. " 开宝箱发现")) or ("需先到达密度 " .. tostring(selected.map)))
    self:Text(status, 16, 194, 8, unlocked and Config.Palette.green or (available and Config.Palette.gold or Config.Palette.creamDim))
    local actionLabel
    local actionEnabled = true
    if not unlocked then
        if not available then
            actionLabel = "密度 " .. tostring(selected.map) .. " 解锁"
            actionEnabled = false
        elseif not seen then
            actionLabel = "等待宝箱发现"
            actionEnabled = false
        else
            actionLabel = self.state.relicCores >= selected.cost and "研究并装备" or "核心不足"
            actionEnabled = self.state.relicCores >= selected.cost
        end
    elseif equippedSelected then
        actionLabel = "卸下"
    else
        actionLabel = #self.state.equippedRelics < 4 and "装备" or "装备栏已满"
    end
    self:DrawButton("relic_action", actionLabel, 92, 204, 80, 20, actionEnabled or unlocked, app.relicHover == "relic_action", self.relicButtons)

    self:DrawPanel(188, 34, 284, 198, "宝箱发现线索 → 核心研究 → 装备生效")
    local firstMap = (app.relicPage - 1) * 2 + 1
    local pageRelics = {}
    for map = firstMap, math.min(10, firstMap + 1) do
        for _, relic in ipairs(self.state.relicData.byMap[map] or {}) do pageRelics[#pageRelics + 1] = relic end
    end
    for index, relic in ipairs(pageRelics) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local x = 196 + column * 136
        local y = 58 + row * 70
        local w, h = 130, 64
        local isSelected = relic.id == selected.id
        local isUnlocked = self.state:IsRelicUnlocked(relic.id)
        local isEquipped = self.state:IsRelicEquipped(relic.id)
        local isAvailable = self.state:IsRelicMapAvailable(relic)
        local accent = Config.Palette[relic.color] or Config.Palette.gold
        self:FillRect(x + 3, y + 3, w, h, Config.Palette.shadow)
        self:FillRect(x, y, w, h, isSelected and { 57, 49, 75, 255 } or { 36, 31, 43, 245 })
        self:StrokeRect(x, y, w, h, isSelected and accent or (isUnlocked and Config.Palette.creamDim or { 80, 71, 91, 210 }), isSelected and 2 or 1)
        self:DrawImage(self:GetRelicIconPath(relic), x + 5, y + 6, 28, 28, isAvailable and 1 or 0.28)
        self:Text(relic.name, x + 38, y + 7, 9, isAvailable and Config.Palette.cream or Config.Palette.creamDim)
        self:Text("地图 " .. tostring(relic.map), x + 38, y + 22, 7, accent)
        self:Text(relic.description, x + 5, y + 40, 7, isAvailable and Config.Palette.creamDim or { 95, 87, 103, 220 })
        local relicSeen = self.state.seenRelics[relic.id] == true
        local footer = isEquipped and "◆ 已装备" or (isUnlocked and "已收藏" or (not isAvailable and "尚未到达" or (relicSeen and ("已发现 · 核心 " .. tostring(relic.cost)) or "待宝箱发现")))
        self:Text(footer, x + w - 5, y + h - 6, 7, isEquipped and Config.Palette.gold or Config.Palette.creamDim, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
        self.relicButtons["relic_select:" .. relic.id] = { x = x, y = y, w = w, h = h, enabled = true }
    end
    self:DrawButton("relic_prev", "◀", 274, 204, 28, 20, app.relicPage > 1, app.relicHover == "relic_prev", self.relicButtons)
    self:Text(string.format("地图 %d-%d · %d/5", firstMap, math.min(10, firstMap + 1), app.relicPage), 380, 214, 8, Config.Palette.cream, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    self:DrawButton("relic_next", "▶", 450, 204, 22, 20, app.relicPage < 5, app.relicHover == "relic_next", self.relicButtons)
end

function Renderer:DrawMaterials(app)
    self.materialButtons = {}
    self:DrawStarfield()
    self:FillRect(0, 0, 480, 28, { 32, 27, 36, 245 })
    self:Text("材料图鉴", 12, 7, 12, Config.Palette.cream)
    self:Text("永久库存 · 本次钻探 · 主要来源", 88, 14, 8, Config.Palette.creamDim, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    self:DrawButton("back", "主菜单", 350, 4, 54, 20, true, app.materialHover == "back", self.materialButtons)
    self:DrawButton("play", "开始钻探", 410, 4, 60, 20, true, app.materialHover == "play", self.materialButtons)

    for index, entry in ipairs(Config.MaterialCatalog or {}) do
        local column = (index - 1) % 3
        local row = math.floor((index - 1) / 3)
        local x, y = 8 + column * 157, 35 + row * 33
        local w, h = 150, 29
        local oreData = Config.Ores[entry.ore] or { zh = entry.ore }
        local amount = self.state.inventory[entry.ore] or 0
        local runAmount = self.state.runInventory[entry.ore] or 0
        local owned = amount > 0 or runAmount > 0
        self:FillRect(x + 2, y + 2, w, h, Config.Palette.shadow)
        self:FillRect(x, y, w, h, owned and { 43, 37, 51, 245 } or { 28, 24, 33, 235 })
        self:StrokeRect(x, y, w, h, owned and Config.Palette.cyan or { 76, 68, 84, 210 }, 1)
        self:DrawImage(self:GetOreIconPath(entry.ore), x + 4, y + 5, 18, 18, owned and 1 or 0.45)
        self:Text(oreData.zh, x + 27, y + 4, 8, owned and Config.Palette.cream or Config.Palette.creamDim)
        local amountText = Util.FormatNumber(amount)
        if runAmount > 0 then amountText = amountText .. " +" .. Util.FormatNumber(runAmount) end
        self:Text(amountText, x + w - 5, y + 5, 7, owned and Config.Palette.gold or Config.Palette.creamDim, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        self:Text(entry.source, x + 27, y + 18, 6, Config.Palette.creamDim)
    end
    self:Text("数量为 0 也会显示；原矿需在精炼厂加工为成品宝石。", 240, 244, 7, Config.Palette.creamDim, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
end

function Renderer:DrawToast(app)
    if not app.toastText or app.toastTimer <= 0 then return end
    local alpha = Util.Clamp(app.toastTimer / 0.3, 0, 1)
    local actionWidth = app.mode == "playing" and 62 or 0
    local width = math.min(360, math.max(176, #app.toastText * 9 + 22 + actionWidth))
    local x = (Config.DESIGN_WIDTH - width) * 0.5
    self:FillRect(x + 2, 111, width, 28, { 9, 7, 12, math.floor(190 * alpha) })
    self:FillRect(x, 109, width, 28, { 36, 29, 42, math.floor(235 * alpha) })
    self:StrokeRect(x, 109, width, 28, { app.toastColor[1], app.toastColor[2], app.toastColor[3], math.floor(255 * alpha) }, 1)
    self:Text(app.toastText, x + (width - actionWidth) * 0.5, 123, 10,
        { app.toastColor[1], app.toastColor[2], app.toastColor[3], math.floor(255 * alpha) },
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if app.mode == "playing" then
        local closeX = x + width - actionWidth
        self:FillRect(closeX, 109, actionWidth, 28, { 20, 15, 24, math.floor(220 * alpha) })
        self:StrokeRect(closeX, 109, actionWidth, 28,
            { app.toastColor[1], app.toastColor[2], app.toastColor[3], math.floor(255 * alpha) }, 1)
        self:Text("关闭提示", closeX + actionWidth * 0.5, 123, 8, Config.Palette.cream,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        self.hudButtons.toast_disable = { x = closeX - 2, y = 107, w = actionWidth + 4, h = 32, enabled = true }
    end
end

function Renderer:DrawControlLayout(app)
    self.controlLayoutButtons = {}
    self:DrawStarfield()
    self:FillRect(0, 0, 480, 32, { 26, 21, 35, 248 })
    self:DrawButton("controls_back", "保存返回", 7, 5, 70, 22, true,
        app.controlLayoutHover == "controls_back", self.controlLayoutButtons)
    self:DrawButton("controls_reset", "恢复默认", 398, 5, 74, 22, true,
        app.controlLayoutHover == "controls_reset", self.controlLayoutButtons)
    self:Text("手机键位布局", 240, 9, 13, Config.Palette.cream,
        NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    self:Text("拖动键位；重叠位置不会保存。布局同步到存档。", 240, 36, 8,
        Config.Palette.creamDim, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    self:FillRect(5, 52, 470, 213, { 15, 13, 20, 225 })
    self:StrokeRect(5, 52, 470, 213, Config.Palette.creamDim, 1)

    local idle, active = { 34, 29, 42, 230 }, { 52, 42, 62, 245 }
    local function register(id, bounds)
        bounds.enabled = true
        self.controlLayoutButtons["control_" .. id] = bounds
    end

    for _, id in ipairs(MobileControlLayout.ORDER) do
        local definition = MobileControlLayout.DEFINITIONS[id]
        local bounds = MobileControlLayout.GetBounds(self.state.mobileControlLayout, id)
        register(id, bounds)
        local selected = app.controlLayoutDrag == id
        local border = selected and Config.Palette.gold or Config.Palette.cyan
        if bounds.circle then
            nvgBeginPath(self.vg)
            nvgCircle(self.vg, bounds.cx, bounds.cy, bounds.radius)
            nvgFillColor(self.vg, Util.Color(selected and active or idle))
            nvgFill(self.vg)
            nvgStrokeColor(self.vg, Util.Color(border))
            nvgStrokeWidth(self.vg, selected and 2 or 1)
            nvgStroke(self.vg)
            self:Text(id == "move" and "移动" or "钻头", bounds.cx, bounds.cy, 9,
                Config.Palette.cream, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        else
            self:FillRect(bounds.x, bounds.y, bounds.w, bounds.h, selected and active or idle)
            self:StrokeRect(bounds.x, bounds.y, bounds.w, bounds.h, border, selected and 2 or 1)
            local short = id == "jump" and "跳" or (id == "auto" and "锁" or "激光")
            self:Text(short, bounds.x + bounds.w * 0.5, bounds.y + bounds.h * 0.5, 9,
                Config.Palette.cream, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        end
        local labelY = bounds.circle and bounds.y - 11 or bounds.y - 9
        self:Text(definition.label, bounds.x + bounds.w * 0.5, labelY, 6,
            Config.Palette.creamDim, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    end
    self:Text("移动、钻头、跳跃、自动钻探与激光均可单独调整", 240, 253, 7,
        Config.Palette.creamDim, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
end

function Renderer:DrawPause(app)
    self:DrawWorld(app)
    self:FillRect(0, 0, 480, 270, { 10, 7, 12, 190 })
    self.hudButtons = {}
    if app.showFuelRescue then
        self:DrawPanel(116, 63, 248, 144, "燃料耗尽 · 救援信号")
        self:TextBox("完整观看一次广告，立即恢复 30% 燃料并继续本局。救援每局限一次；退出或广告未完成不会消耗资格。",
            139, 94, 202, 9, Config.Palette.cream)
        self:DrawButton("fuel_rescue_ad", app.fuelRescueAdPending and "广告播放中…" or "看广告救援",
            139, 166, 94, 24, not app.adPending, app.pauseHover == "fuel_rescue_ad", self.hudButtons)
        self:DrawButton("fuel_rescue_settle", "安全结算", 247, 166, 94, 24,
            not app.adPending, app.pauseHover == "fuel_rescue_settle", self.hudButtons)
        return
    end
    local panelY = app.showEndRunConfirm and 57 or 38
    local panelH = app.showEndRunConfirm and 156 or 194
    self:DrawPanel(136, panelY, 208, panelH,
        app.showEndRunConfirm and (app.isAbyssRun and "确认撤离深渊" or "确认安全返航")
        or (app.isAbyssRun and "深渊挑战暂停" or "暂停"))
    if app.showEndRunConfirm then
        self:TextBox("立即结束本次钻探，并把地上及飞行中的全部掉落物安全结算到账户。", 158, 88, 164, 9, Config.Palette.cream)
        self:DrawButton("end_cancel", "继续钻探", 157, 166, 76, 24, true, app.pauseHover == "end_cancel", self.hudButtons)
        self:DrawButton("end_confirm", "确认结算", 247, 166, 76, 24, true, app.pauseHover == "end_confirm", self.hudButtons)
    else
        self:DrawButton("resume", "继续", 191, 68, 98, 24, true, app.pauseHover == "resume", self.hudButtons)
        self:DrawButton("mute", self.state.muted and "声音：关" or "声音：开", 146, 100, 92, 24, true, app.pauseHover == "mute", self.hudButtons)
        self:DrawButton("drill_sound", self.state.drillSoundEnabled == false and "钻头：关" or "钻头：开",
            242, 100, 92, 24, true, app.pauseHover == "drill_sound", self.hudButtons)
        self:DrawButton("toast_toggle", self.state.toastEnabled == false and "提示：关" or "提示：开",
            146, 132, 92, 24, true, app.pauseHover == "toast_toggle", self.hudButtons)
        self:DrawButton("shake_toggle", self.state.screenShakeEnabled == false and "震动：关" or "震动：开",
            242, 132, 92, 24, true, app.pauseHover == "shake_toggle", self.hudButtons)
        self:DrawButton("guide", "玩法说明", 146, 164, 92, 24, true, app.pauseHover == "guide", self.hudButtons)
        self:DrawButton("controls", "自定义键位", 242, 164, 92, 24, true,
            app.pauseHover == "controls", self.hudButtons)
        self:DrawButton("end_run", "结束并结算", 191, 200, 98, 20, true, app.pauseHover == "end_run", self.hudButtons)
    end
end

function Renderer:Draw(app)
    if app.mode == "menu" then
        self:DrawMenu(app)
    elseif app.mode == "season_hub" then
        require("diggin.SeasonHub").Draw(self, app)
    elseif app.mode == "playing" then
        self:DrawWorld(app)
    elseif app.mode == "ended" then
        self:DrawEnd(app)
    elseif app.mode == "skills" then
        self:DrawSkills(app)
    elseif app.mode == "relics" then
        self:DrawRelics(app)
    elseif app.mode == "materials" then
        self:DrawMaterials(app)
    elseif app.mode == "world_tree" then
        WorldTreeRenderer.Draw(self, app)
    elseif app.mode == "abyss_leaderboard" then
        AbyssLeaderboardRenderer.Draw(self, app)
    elseif app.mode == "control_layout" then
        self:DrawControlLayout(app)
    elseif app.mode == "paused" then
        self:DrawPause(app)
    elseif app.mode == "guide" then
        self:DrawGuide(app)
    end
    self:DrawToast(app)
end

return Renderer
