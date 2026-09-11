-- ====================================================================
-- Event/Event_Awakening.lua - "苏醒时" 事件（事件 #1）
-- ====================================================================
-- 触发时机：角色创建后
-- 流程：
--   1. 玩家在地图中央，1只哥布林在附近
--   2. 等待几秒，6只哥布林从边缘涌入
--   3. 哥布林向玩家靠近（2回合）
--   4. ???对话："你们这些怪物！"
--   5. 芙蕾雅（显示为???）从顶部出现
--   6. 所有哥布林冒出感叹号
--   7. 4只哥布林逃跑
--   8. 芙蕾雅自动战斗（玩家锁定观看）
--   9. 杀光后芙蕾雅走到玩家上方2格
--  10. 对话
--  11. 事件结束
-- ====================================================================

local GS = require("GameState")
local EventManager = require("Event.EventManager")
local DialogueManager = require("DialogueManager")
local ImageManager = require("ImageManager")

local M = {}
M.id = "awakening"
M.name = "苏醒时"

-- ================================================================
-- 阶段常量
-- ================================================================
local PHASE_BLACK_SCREEN     = "black_screen"
local PHASE_INIT             = "init"
local PHASE_PAUSE            = "pause"
local PHASE_SPAWN_WAVE       = "spawn_wave"
local PHASE_GOBLIN_ADVANCE   = "goblin_advance"
local PHASE_DIALOGUE_1       = "dialogue_1"
local PHASE_FREYA_ENTER      = "freya_enter"
local PHASE_EXCLAMATION      = "exclamation"
local PHASE_FLEE_PAUSE       = "flee_pause"
local PHASE_FREYA_FIGHT      = "freya_fight"
local PHASE_CLEANUP_WAIT     = "cleanup_wait"
local PHASE_FREYA_WALK       = "freya_walk"
local PHASE_DIALOGUE_2       = "dialogue_2"
local PHASE_WALK_EXIT        = "walk_exit"
local PHASE_SCENE_FADE       = "scene_fade"
local PHASE_GUILD_SCENE      = "guild_scene"
local PHASE_DIALOGUE_3A      = "dialogue_3a"
local PHASE_NAME_INPUT       = "name_input"
local PHASE_DIALOGUE_3B      = "dialogue_3b"
local PHASE_CLASS_SELECT     = "class_select"
local PHASE_CLASS_CONFIRM    = "class_confirm"
local PHASE_DIALOGUE_3C      = "dialogue_3c"
local PHASE_QA_SELECT        = "qa_select"
local PHASE_QA_ANSWER        = "qa_answer"
local PHASE_QA_EXIT          = "qa_exit"

-- ================================================================
-- Q&A 选项问答数据（会长办公室末尾）
-- ================================================================
local QA_OPTIONS = {
    {
        label = "我好像失忆了……",
        dialogues = {
            { speaker = "芙蕾雅", text = "放轻松，你会想起来的。在那之前，先随便找点事情做吧。" },
            { speaker = "芙蕾雅", text = "比如说变强？现在的你太弱小了，连哥布林都对付不了。" },
            { speaker = "芙蕾雅", text = "努力成长起来，只要你也这么想，我会帮你。" },
        },
    },
    {
        label = "你怎么知道我在那里？",
        dialogues = {
            { speaker = "芙蕾雅", text = "是神谕，我们的神明知道你碰到了麻烦，所以她让我去接引你。" },
        },
    },
    {
        label = "阿妮塔是谁？",
        dialogues = {
            { speaker = "芙蕾雅", text = "阿妮塔是我们的神明，正义、美德和清澈泉眼的神。" },
            { speaker = "芙蕾雅", text = "我们崇敬她，向她祈求赐福，才能在这个混乱的世界中找到栖身之所。" },
        },
        subChoice = {
            choiceLabel = "所以你说的神谕是阿妮塔的神谕？",
            response = { speaker = "芙蕾雅", text = "是的，但我今天没有时间完整说明了。" },
        },
    },
    {
        label = "妮可是谁？",
        dialogues = {
            { speaker = "芙蕾雅", text = "妮可是冒险者公会的接待员，如果好奇的话，你一会儿领取物资的时候就能见到她了。" },
        },
    },
    {
        label = "关于这个世界",
        dialogues = {
            { speaker = "芙蕾雅", text = "这个问题太大了，与其我说，不如由你自己去探索吧。但记住，外面的世界可不像清水镇这样风平浪静。" },
        },
    },
    {
        label = "没什么要问的了",
        isExit = true,
        dialogues = {
            { speaker = "芙蕾雅", text = "我也确实要离开了，谢谢你这么善解人意。" },
            { speaker = "芙蕾雅", text = "那么，道别之前，我代表公会向你发布第一个委托。" },
            { speaker = "芙蕾雅", text = "公会侦查到慈爱平原入口处有到处吞噬的史莱姆变种，交给你来解决吧。" },
            { speaker = "芙蕾雅", text = "去之前请你记得去找妮可领取物资，镇子里也有各种商铺和设施帮助你做好其他准备。" },
        },
    },
}

-- ================================================================
-- 内部状态
-- ================================================================
M.phase = nil
M.timer = 0
M.turnCount = 0
M.autoTurnTimer = 0
M.freya = nil
M._waitForAnims = false
M._phaseInited = false  -- 标记当前阶段是否已执行初始化

-- 黑屏文本序列
-- disclaimer 段（前3条）用米白底+黑灰字；之后用黑底+白字
local BLACK_SCREEN_TEXTS = {
    "本游戏纯属虚构，游玩过程中不设教程，完全由您自由进行。",
    "由于开发者的不成熟，本游戏后续极有可能发生平衡性调整，您已实现的游戏内容，如角色、装备、技能等可能在未经您同意的情况下发生不同幅度的增强或削弱。向您致歉。",
    "觉浅湖工作室",
    "喂……",
    "喂！",
    "终于等到你了",
    "我们需要你",
    "第三意志",
}
local BLACK_SCREEN_DISCLAIMER_COUNT = 3  -- 前3条是声明文本
local BLACK_SCREEN_TYPE_SPEED = 0.08  -- 每字打出间隔（秒）
local BLACK_SCREEN_HOLD       = 1.0   -- 打完后停留时间
local BLACK_SCREEN_FADE_OUT   = 0.5   -- 文字淡出时间

-- 哥布林波次配置（固定6只）
local WAVE_GOBLINS = {
    "goblin", "goblin_club", "goblin_shield",
    "goblin_archer", "goblin", "goblin_club",
}

-- ================================================================
-- 工具函数
-- ================================================================

--- 从 MONSTER_DB 创建一个怪物实例
local function createMonster(defKey, x, y)
    local def = GS.MONSTER_DB[defKey]
    if not def then
        print("[Event_Awakening] Unknown monster: " .. tostring(defKey))
        return nil
    end
    return {
        x = x, y = y,
        name = def.name .. " Lv." .. def.level,
        level = def.level or 1,
        hp = def.hp, maxHp = def.hp,
        atk = def.atk, def = def.def, mdef = def.mdef or def.def,
        mAtk = def.mAtk or 0,
        critVal = def.critVal or 0,
        critDmg = def.critDmg or 50,
        hit = def.hit or 0,
        dodge = def.dodge or 0,
        moveRange = def.moveRange, atkRange = def.atkRange,
        atkSpeed = def.atkSpeed or 0,
        color = { def.color[1], def.color[2], def.color[3] },
        image = def.image,
        rarity = def.rarity,
        isMonster = true, acted = false,
        facing = GS.facingToCenter(x, y),
    }
end

--- 创建芙蕾雅友军实例
local function createFreya(x, y)
    local def = GS.MONSTER_DB["freya"]
    if not def then
        print("[Event_Awakening] Freya definition not found in MONSTER_DB!")
        return nil
    end
    return {
        x = x, y = y,
        name = "？？？",  -- 事件全程显示为 ？？？
        level = def.level or 100,
        hp = def.hp, maxHp = def.hp,
        atk = def.atk, def = def.def, mdef = def.mdef or def.def,
        mAtk = def.mAtk or 0,
        critVal = def.critVal or 0,
        critDmg = def.critDmg or 50,
        hit = def.hit or 0,
        dodge = def.dodge or 0,
        moveRange = def.moveRange or 4,
        atkRange = def.atkRange or 1,
        atkSpeed = def.atkSpeed or 50,
        color = { def.color[1], def.color[2], def.color[3] },
        image = def.image,
        rarity = def.rarity,
        isCompanion = true,
        isEventAlly = true,
        hasFloatingSword = true,   -- 显示浮空剑
        acted = false,
        facing = "down",
    }
end

--- 获取打乱的边缘空位列表
local function getShuffledEdgePositions()
    local BS = GS.BOARD_SIZE
    local positions = {}
    -- 四条边
    for x = 1, BS do
        if GS.isCellEmpty(x, 1) then positions[#positions + 1] = { x, 1 } end
        if GS.isCellEmpty(x, BS) then positions[#positions + 1] = { x, BS } end
    end
    for y = 2, BS - 1 do
        if GS.isCellEmpty(1, y) then positions[#positions + 1] = { 1, y } end
        if GS.isCellEmpty(BS, y) then positions[#positions + 1] = { BS, y } end
    end
    -- 随机打乱
    for i = #positions, 2, -1 do
        local j = math.random(1, i)
        positions[i], positions[j] = positions[j], positions[i]
    end
    return positions
end

--- 检查是否有任何移动动画正在播放
local function anyMoveAnims()
    for _, m in ipairs(GS.monsters) do
        if m.moveAnim then return true end
    end
    for _, c in ipairs(GS.companions) do
        if c.moveAnim then return true end
    end
    return false
end

--- 检查是否有任何攻击/slam动画正在播放
local function anySlamAnims()
    for _, m in ipairs(GS.monsters) do
        if m.slamAnim then return true end
    end
    for _, c in ipairs(GS.companions) do
        if c.slamAnim then return true end
    end
    return false
end

--- 检查是否有任何攻击/技能特效正在播放
local function anyAttackEffects()
    return #GS.attackEffects > 0 or #GS.strikeEffects > 0
end

--- 统计存活的非逃跑怪物数
local function countAliveNonFleeing()
    local n = 0
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 and not m.fleeing then
            n = n + 1
        end
    end
    return n
end

--- 移除已到达边缘的逃跑怪物
local function removeEdgeFled()
    local Combat = require("Combat")
    for i = #GS.monsters, 1, -1 do
        local m = GS.monsters[i]
        if m.fleeing and m.hp > 0 then
            local edgeDist = math.min(m.x - 1, GS.BOARD_SIZE - m.x, m.y - 1, GS.BOARD_SIZE - m.y)
            -- 只在到达边缘且移动动画播放完毕后才移除
            if edgeDist <= 0 and not m.moveAnim then
                Combat.addDamageText(m.x, m.y, "逃走了", {180, 180, 180})
                table.remove(GS.monsters, i)
            end
        end
    end
end

-- ================================================================
-- 阶段切换
-- ================================================================

function M:setPhase(newPhase)
    print("[Event_Awakening] Phase: " .. tostring(self.phase) .. " -> " .. newPhase)
    self.phase = newPhase
    self.timer = 0
    self.autoTurnTimer = 0
    self._waitForAnims = false
    self._freyaPendingAttack = nil
    self._goblinPendingAttacks = nil
    self._phaseInited = false  -- 重置初始化标记
end

-- ================================================================
-- 生命周期
-- ================================================================

function M:onEnter()
    -- 苏醒事件期间静音BGM，直到到达公会会长办公室
    GS.bgmMuted = true

    -- 1. 设置背景
    GS.currentBattleBg = "image/bg_grass.png"

    -- 设置下雨天气
    GS.setWeather("rain")

    -- 2. 放置玩家到中央，并恢复满血满蓝（防止中途退出再进入时残留低HP）
    if GS.player then
        GS.player.x = 6
        GS.player.y = 6
        GS.player.facing = "right"
        GS.player.hp = GS.player.maxHp
        GS.player.mp = GS.player.maxMp
    end

    -- 3. 在玩家右侧2格放1只哥布林，面朝玩家，每次只移动1格
    local goblin = createMonster("goblin", 9, 6)
    if goblin then
        goblin.facing = "left"
        goblin.moveRange = 1
        goblin.noDrop = true           -- 事件哥布林不掉落任何物品
        goblin.isInitialGoblin = true  -- 标记为初始哥布林，供芙蕾雅冲锋定位
        table.insert(GS.monsters, goblin)
    end

    -- 4. 锁定玩家输入
    GS.eventInputLocked = true

    print("[Event_Awakening] Init: player at (6,6), 1 goblin at (8,7)")

    -- 进入黑屏阶段
    self:setPhase(PHASE_BLACK_SCREEN)
end

function M:onExit()
    self.freya = nil
    self.phase = nil
    self.timer = 0
    self.turnCount = 0
    self.autoTurnTimer = 0
    self._waitForAnims = false
    -- 清理 QA_EXIT 相关状态，防止重入时残留
    self._qaDialogueEnded = nil

    GS.stealthActive = false
    GS.stealthTurns = 0
    GS.eventInputLocked = false
    GS.eventBlackScreen = nil
    GS.eventWhiteFlash = nil
    GS.eventSceneImage = nil
    if GS.eventNameInput then
        input:SetScreenKeyboardVisible(false)
    end
    GS.eventNameInput = nil
    GS._nameInputConfirmRect = nil
    GS._nameInputRect = nil
    GS._choiceRects = nil
end

-- ================================================================
-- 每帧更新
-- ================================================================

function M:update(dt)
    if not self.phase then return end

    self.timer = self.timer + dt

    -- 更新白色闪烁计时器
    if GS.eventWhiteFlash then
        GS.eventWhiteFlash.timer = GS.eventWhiteFlash.timer + dt
        if GS.eventWhiteFlash.timer >= GS.eventWhiteFlash.duration then
            GS.eventWhiteFlash = nil
        end
    end

    -- 更新友军浮动文本计时器
    for _, c in ipairs(GS.companions) do
        if c.floatingText then
            c.floatingText.timer = c.floatingText.timer + dt
            if c.floatingText.timer >= c.floatingText.duration then
                c.floatingText = nil
            end
        end
    end

    -- 更新怪物感叹号计时器
    for _, m in ipairs(GS.monsters) do
        if m.showAlert and m.showAlertTimer then
            m.showAlertTimer = m.showAlertTimer - dt
            if m.showAlertTimer <= 0 then
                m.showAlert = false
                m.showAlertTimer = nil
            end
        end
    end

    -- ============================================================
    -- 各阶段逻辑
    -- ============================================================

    if self.phase == PHASE_BLACK_SCREEN then
        if not self._phaseInited then
            self._phaseInited = true
            self._bsTextIdx = 1      -- 当前文本索引
            self._bsTextTimer = 0    -- 当前文本计时器
            self._bsPhase = "typing" -- typing → hold → fadeout
            local fullText = BLACK_SCREEN_TEXTS[1]
            local isLast = (1 == #BLACK_SCREEN_TEXTS)
            local isDisclaimer = (1 <= BLACK_SCREEN_DISCLAIMER_COUNT)
            -- 用 utf8.len 计算字符数
            local charCount = utf8.len(fullText) or #fullText
            GS.eventBlackScreen = {
                fullText = fullText,
                charCount = charCount,
                visibleChars = 0,
                alpha = 1.0,
                isLast = isLast,
                isDisclaimer = isDisclaimer,
            }
        end

        self._bsTextTimer = self._bsTextTimer + dt
        local bs = GS.eventBlackScreen

        if self._bsPhase == "typing" then
            -- 打字机效果：按时间逐字显示
            local chars = math.floor(self._bsTextTimer / BLACK_SCREEN_TYPE_SPEED)
            if chars > bs.charCount then chars = bs.charCount end
            bs.visibleChars = chars
            bs.alpha = 1.0
            -- 全部字打完后进入 hold
            if chars >= bs.charCount then
                self._bsPhase = "hold"
                self._bsTextTimer = 0
            end

        elseif self._bsPhase == "hold" then
            -- 停留一段时间
            bs.visibleChars = bs.charCount
            bs.alpha = 1.0
            if self._bsTextTimer >= BLACK_SCREEN_HOLD then
                self._bsPhase = "fadeout"
                self._bsTextTimer = 0
            end

        elseif self._bsPhase == "fadeout" then
            -- 淡出
            bs.visibleChars = bs.charCount
            local fadeProgress = self._bsTextTimer / BLACK_SCREEN_FADE_OUT
            if fadeProgress > 1 then fadeProgress = 1 end
            bs.alpha = 1.0 - fadeProgress

            if fadeProgress >= 1 then
                -- 当前文本结束，切换下一段
                self._bsTextIdx = self._bsTextIdx + 1
                self._bsTextTimer = 0
                if self._bsTextIdx > #BLACK_SCREEN_TEXTS then
                    -- 所有文本显示完毕
                    GS.eventBlackScreen = nil
                    self._bsTextIdx = nil
                    self._bsTextTimer = nil
                    self._bsPhase = nil
                    GS.eventWhiteFlash = { timer = 0, duration = 0.6 }
                    self:setPhase(PHASE_PAUSE)
                else
                    -- 检查是否从免责声明段切换到正文段，需要背景渐变过渡
                    local prevWasDisclaimer = (self._bsTextIdx - 1) <= BLACK_SCREEN_DISCLAIMER_COUNT
                    local nextIsDisclaimer = (self._bsTextIdx) <= BLACK_SCREEN_DISCLAIMER_COUNT
                    if prevWasDisclaimer and not nextIsDisclaimer then
                        -- 进入背景渐变过渡：黑色 → 米白色
                        self._bsPhase = "bg_transition"
                        bs.visibleChars = 0
                        bs.alpha = 0
                    else
                        -- 准备下一段文本
                        self._bsPhase = "typing"
                        local fullText = BLACK_SCREEN_TEXTS[self._bsTextIdx]
                        local isLast = (self._bsTextIdx == #BLACK_SCREEN_TEXTS)
                        local isDisclaimer = (self._bsTextIdx <= BLACK_SCREEN_DISCLAIMER_COUNT)
                        local charCount = utf8.len(fullText) or #fullText
                        bs.fullText = fullText
                        bs.charCount = charCount
                        bs.visibleChars = 0
                        bs.alpha = 1.0
                        bs.isLast = isLast
                        bs.isDisclaimer = isDisclaimer
                    end
                end
            end

        elseif self._bsPhase == "bg_transition" then
            -- 背景从黑色渐变到米白色（0.8秒）
            local BG_TRANSITION_DUR = 0.8
            local tProgress = self._bsTextTimer / BG_TRANSITION_DUR
            if tProgress > 1 then tProgress = 1 end
            bs.bgBlend = tProgress
            bs.visibleChars = 0
            bs.alpha = 0

            if tProgress >= 1 then
                -- 渐变完成，进入停顿阶段
                self._bsPhase = "bg_hold"
                self._bsTextTimer = 0
                bs.bgBlend = 1.0
            end

        elseif self._bsPhase == "bg_hold" then
            -- 米白色背景停顿1.5秒
            local BG_HOLD_DUR = 1.5
            bs.visibleChars = 0
            bs.alpha = 0
            bs.bgBlend = 1.0

            if self._bsTextTimer >= BG_HOLD_DUR then
                -- 停顿结束，开始下一段文本
                self._bsPhase = "typing"
                self._bsTextTimer = 0
                local fullText = BLACK_SCREEN_TEXTS[self._bsTextIdx]
                local isLast = (self._bsTextIdx == #BLACK_SCREEN_TEXTS)
                bs.fullText = fullText
                bs.charCount = utf8.len(fullText) or #fullText
                bs.visibleChars = 0
                bs.alpha = 1.0
                bs.isLast = isLast
                bs.isDisclaimer = false
                bs.bgBlend = 1.0
            end
        end

    elseif self.phase == PHASE_PAUSE then
        -- 玩家跳跃 + 感叹号（进入场景的惊醒反应）
        if not self._phaseInited then
            self._phaseInited = true
            if GS.player then
                GS.player.jumpAnim = { timer = 0, duration = 0.35 }
                GS.player.showAlert = true
                GS.player.showAlertTimer = 2.0
            end
        end
        -- 更新玩家 jumpAnim 计时器
        if GS.player and GS.player.jumpAnim then
            GS.player.jumpAnim.timer = GS.player.jumpAnim.timer + dt
            if GS.player.jumpAnim.timer >= GS.player.jumpAnim.duration then
                GS.player.jumpAnim = nil
            end
        end
        -- 更新玩家感叹号计时器
        if GS.player and GS.player.showAlert and GS.player.showAlertTimer then
            GS.player.showAlertTimer = GS.player.showAlertTimer - dt
            if GS.player.showAlertTimer <= 0 then
                GS.player.showAlert = false
                GS.player.showAlertTimer = nil
            end
        end
        -- 等待 2.5 秒后生成哥布林波次
        if self.timer >= 2.5 then
            self:setPhase(PHASE_SPAWN_WAVE)
        end

    elseif self.phase == PHASE_SPAWN_WAVE then
        -- 同时生成 6 只哥布林从边缘
        local edgePos = getShuffledEdgePositions()
        local idx = 1
        for _, defKey in ipairs(WAVE_GOBLINS) do
            while idx <= #edgePos do
                local pos = edgePos[idx]
                idx = idx + 1
                if GS.isCellEmpty(pos[1], pos[2]) then
                    local monster = createMonster(defKey, pos[1], pos[2])
                    if monster then
                        monster.noDrop = true  -- 事件哥布林不掉落
                        table.insert(GS.monsters, monster)
                    end
                    break
                end
            end
        end
        print("[Event_Awakening] Wave spawned, total goblins: " .. #GS.monsters)

        self.turnCount = 0
        self:setPhase(PHASE_GOBLIN_ADVANCE)

    elseif self.phase == PHASE_GOBLIN_ADVANCE then
        -- 每 2 秒一个回合，哥布林向玩家靠近
        -- 等动画播完才开始计时
        if self._waitForAnims then
            if not anyMoveAnims() and not anySlamAnims() and not anyAttackEffects() then
                self._waitForAnims = false
                self.autoTurnTimer = 0
                -- 检查是否完成 2 回合
                if self.turnCount >= 2 then
                    self:setPhase(PHASE_DIALOGUE_1)
                    return
                end
            else
                return
            end
        end

        self.autoTurnTimer = self.autoTurnTimer + dt
        if self.autoTurnTimer >= 1.0 then
            self.autoTurnTimer = 0
            self.turnCount = self.turnCount + 1

            -- 芙蕾雅冲锋预留位（初始哥布林最终位置(7,6)的上方1格，固定锁死）
            local reservedX, reservedY = 7, 5

            -- 手动移动每只哥布林向玩家靠近
            for _, m in ipairs(GS.monsters) do
                if m.hp > 0 and not m.fleeing then
                    local movable, parents = GS.getMovableCellsForMonster(m)
                    local bestX, bestY = m.x, m.y
                    local bestDist = GS.manhattan(m.x, m.y, GS.player.x, GS.player.y)
                    for key, _ in pairs(movable) do
                        local cy = math.floor(key / 100)
                        local cx = key - cy * 100
                        -- 排除芙蕾雅冲锋预留位
                        local isReserved = (reservedX and cx == reservedX and cy == reservedY)
                        if not isReserved and (GS.isCellEmpty(cx, cy) or (cx == m.x and cy == m.y)) then
                            local d = GS.manhattan(cx, cy, GS.player.x, GS.player.y)
                            if d < bestDist then
                                bestDist = d
                                bestX = cx
                                bestY = cy
                            end
                        end
                    end
                    if bestX ~= m.x or bestY ~= m.y then
                        local oldX, oldY = m.x, m.y
                        local path = GS.reconstructPath(parents, oldX, oldY, bestX, bestY)
                        m.x = bestX
                        m.y = bestY
                        local Combat = require("Combat")
                        Combat.startMoveAnim(m, oldX, oldY, path)
                    end
                    m.facing = GS.facingToCenter(m.x, m.y)
                end
            end

            self._waitForAnims = true
            print("[Event_Awakening] Goblin advance turn " .. self.turnCount)
        end

    elseif self.phase == PHASE_DIALOGUE_1 then
        if not self._phaseInited then
            self._phaseInited = true
            -- 启动对话（只执行一次）
            DialogueManager.start("event_awakening_1")
        end
        -- 对话结束后进入下一阶段
        if self._phaseInited and not DialogueManager.active and self.timer > 0.3 then
            self:setPhase(PHASE_FREYA_ENTER)
        end

    elseif self.phase == PHASE_FREYA_ENTER then
        -- 分步骤：1=生成芙蕾雅 2=冲锋移动 3=攻击初始哥布林 4=哥布林惊叹
        if not self._phaseInited then
            self._phaseInited = true
            self._freyaStep = 1
            self._freyaStepTimer = 0
        end

        self._freyaStepTimer = self._freyaStepTimer + dt

        if self._freyaStep == 1 then
            -- Step 1: 生成芙蕾雅在初始哥布林正上方列 (7,1)
            local freya = createFreya(7, 1)
            if freya then
                self.freya = freya
                table.insert(GS.companions, freya)
                if freya.image then
                    ImageManager.lazyGet("companion", freya.image)
                end
                print("[Event_Awakening] Freya entered at (7, 1)")
            end
            -- 找到初始哥布林
            self._initialGoblin = nil
            for _, m in ipairs(GS.monsters) do
                if m.isInitialGoblin and m.hp > 0 then
                    self._initialGoblin = m
                    break
                end
            end
            self._freyaStep = 2
            self._freyaStepTimer = 0

        elseif self._freyaStep == 2 then
            -- Step 2: 短暂停顿后芙蕾雅冲锋到初始哥布林上方1格
            if self._freyaStepTimer >= 0.5 then
                if self.freya and self._initialGoblin then
                    local targetX = self._initialGoblin.x
                    local targetY = self._initialGoblin.y - 1
                    if targetY < 1 then targetY = 1 end
                    local oldX, oldY = self.freya.x, self.freya.y
                    self.freya.x = targetX
                    self.freya.y = targetY
                    self.freya.facing = "down"
                    local Combat = require("Combat")
                    Combat.startMoveAnim(self.freya, oldX, oldY, nil)
                    print("[Event_Awakening] Freya charging to (" .. targetX .. "," .. targetY .. ")")
                end
                self._freyaStep = 3
                self._freyaStepTimer = 0
            end

        elseif self._freyaStep == 3 then
            -- Step 3: 等移动动画完成后发动碎星攻击
            if not anyMoveAnims() and self._freyaStepTimer >= 0.15 then
                if self.freya and self._initialGoblin and self._initialGoblin.hp > 0 then
                    local Combat = require("Combat")
                    Combat.performAttack(self.freya, self._initialGoblin, "mst_stk")
                    if self._initialGoblin.hp <= 0 then
                        Combat.processMonsterKill(GS.player, self._initialGoblin)
                    end
                    print("[Event_Awakening] Freya attacks initial goblin with mst_stk!")
                end
                self._freyaStep = "3b"
                self._freyaStepTimer = 0
            end

        elseif self._freyaStep == "3b" then
            -- Step 3b: 等攻击动画完成后触发死亡特效
            if not anySlamAnims() and not anyAttackEffects() and self._freyaStepTimer >= 0.1 then
                local Combat = require("Combat")
                Combat.removeDeadMonsters()
                self._freyaStep = 4
                self._freyaStepTimer = 0
            end

        elseif self._freyaStep == 4 then
            -- Step 4: 等攻击动画完成后，哥布林惊叹+面向芙蕾雅
            if not anySlamAnims() and not anyAttackEffects() and self._freyaStepTimer >= 0.3 then
                -- 计算芙蕾雅当前位置（冲锋后）
                local freyaX = self.freya and self.freya.x or 7
                local freyaY = self.freya and self.freya.y or 5
                for _, m in ipairs(GS.monsters) do
                    if m.hp > 0 then
                        m.showAlert = true
                        m.showAlertTimer = 1.0
                        -- 朝向面向芙蕾雅（而非全部朝上）
                        local dx = freyaX - m.x
                        local dy = freyaY - m.y
                        if math.abs(dx) >= math.abs(dy) then
                            m.facing = dx > 0 and "right" or "left"
                        else
                            m.facing = dy > 0 and "down" or "up"
                        end
                        m.jumpAnim = { timer = 0, duration = 0.35 }
                    end
                end
                print("[Event_Awakening] All goblins alerted, facing Freya at (" .. freyaX .. "," .. freyaY .. ")")
                self._freyaStep = 5
                self._freyaStepTimer = 0
            end

        elseif self._freyaStep == 5 then
            -- Step 5: 等感叹号显示一段时间后进入逃跑阶段
            if self._freyaStepTimer >= 1.0 then
                self._freyaStep = nil
                self._freyaStepTimer = nil
                self._initialGoblin = nil
                self:setPhase(PHASE_FLEE_PAUSE)
            end
        end

    elseif self.phase == PHASE_FLEE_PAUSE then
        if not self._phaseInited then
            self._phaseInited = true
            -- 随机选4只哥布林逃跑（只执行一次）
            local alive = {}
            for _, m in ipairs(GS.monsters) do
                if m.hp > 0 then
                    alive[#alive + 1] = m
                end
            end
            -- 打乱
            for i = #alive, 2, -1 do
                local j = math.random(1, i)
                alive[i], alive[j] = alive[j], alive[i]
            end
            -- 前4只逃跑
            local fleeCount = math.min(4, #alive)
            for i = 1, fleeCount do
                alive[i].fleeing = true
            end

            -- 让敌人只攻击芙蕾雅（隐匿玩家）
            GS.stealthActive = true
            GS.stealthTurns = 999

            print("[Event_Awakening] " .. fleeCount .. " goblins fleeing, " ..
                  (#alive - fleeCount) .. " remaining to fight")
        end
        -- 短暂停顿后开始战斗
        if self.timer >= 1.0 then
            self.turnCount = 0
            self:setPhase(PHASE_FREYA_FIGHT)
        end

    elseif self.phase == PHASE_FREYA_FIGHT then
        -- 自动战斗：芙蕾雅 vs 剩余哥布林
        -- 移除已逃到边缘的哥布林（显示"逃走了"文本）
        removeEdgeFled()

        -- 检查是否战斗结束（非逃跑怪物全部死亡）
        if countAliveNonFleeing() <= 0 then
            -- 检查是否还有逃跑中的哥布林
            local hasFleeing = false
            for _, m in ipairs(GS.monsters) do
                if m.fleeing and m.hp > 0 then
                    hasFleeing = true
                    break
                end
            end
            if hasFleeing then
                -- 仍有逃跑哥布林：等动画播完后让它们继续移动到边缘
                if not anyMoveAnims() and not anySlamAnims() and not anyAttackEffects() then
                    -- 给逃跑哥布林执行一次移动（向边缘）
                    self.autoTurnTimer = (self.autoTurnTimer or 0) + dt
                    if self.autoTurnTimer >= 0.3 then
                        self.autoTurnTimer = 0
                        local Combat = require("Combat")
                        for _, m in ipairs(GS.monsters) do
                            if m.hp > 0 and m.fleeing then
                                local movable, parents = GS.getMovableCellsForMonster(m)
                                local bestX, bestY = m.x, m.y
                                local bestEdgeDist = math.min(m.x - 1, GS.BOARD_SIZE - m.x, m.y - 1, GS.BOARD_SIZE - m.y)
                                for key, _ in pairs(movable) do
                                    local cy = math.floor(key / 100)
                                    local cx = key - cy * 100
                                    if GS.isCellEmpty(cx, cy) or (cx == m.x and cy == m.y) then
                                        local edgeDist = math.min(cx - 1, GS.BOARD_SIZE - cx, cy - 1, GS.BOARD_SIZE - cy)
                                        if edgeDist < bestEdgeDist then
                                            bestEdgeDist = edgeDist
                                            bestX = cx
                                            bestY = cy
                                        end
                                    end
                                end
                                if bestX ~= m.x or bestY ~= m.y then
                                    local oldX, oldY = m.x, m.y
                                    local path = GS.reconstructPath(parents, oldX, oldY, bestX, bestY)
                                    m.x = bestX
                                    m.y = bestY
                                    Combat.startMoveAnim(m, oldX, oldY, path)
                                end
                            end
                        end
                    end
                end
                return
            end
            -- 所有怪物（含逃跑的）都已移除
            self:setPhase(PHASE_CLEANUP_WAIT)
            return
        end

        -- 等动画播完才进行下一回合（包括攻击特效）
        if self._waitForAnims then
            if not anyMoveAnims() and not anySlamAnims() and not anyAttackEffects() then
                -- 所有移动动画播完后，统一执行待定攻击（芙蕾雅 + 哥布林）
                local hasPending = false

                -- 芙蕾雅待定攻击
                if self._freyaPendingAttack then
                    local pa = self._freyaPendingAttack
                    self._freyaPendingAttack = nil
                    if pa.target and pa.target.hp > 0 then
                        local Combat = require("Combat")
                        Combat.performAttack(self.freya, pa.target, "mst_stk")
                        if pa.target.hp <= 0 then
                            Combat.processMonsterKill(GS.player, pa.target)
                        end
                    end
                    hasPending = true
                end

                -- 哥布林待定攻击
                if self._goblinPendingAttacks then
                    local Combat = require("Combat")
                    for _, pa in ipairs(self._goblinPendingAttacks) do
                        if pa.attacker and pa.attacker.hp > 0 and pa.target and pa.target.hp > 0 then
                            Combat.performAttack(pa.attacker, pa.target)
                        end
                    end
                    self._goblinPendingAttacks = nil
                    hasPending = true
                end

                if hasPending then
                    local Combat = require("Combat")
                    Combat.removeDeadMonsters()
                    -- 继续等待攻击动画播完
                    return
                end

                self._waitForAnims = false
                self.autoTurnTimer = 0
            else
                return
            end
        end

        -- 自动回合计时（与正常游戏节奏一致，动画播完即进入下一回合）
        self.autoTurnTimer = self.autoTurnTimer + dt
        if self.autoTurnTimer >= 0.3 then
            self.autoTurnTimer = 0
            self.turnCount = self.turnCount + 1

            local Combat = require("Combat")

            -- === 芙蕾雅行动 ===
            if self.freya and self.freya.hp > 0 then
                -- 找最近的非逃跑敌人
                local bestTarget = nil
                local bestDist = 9999
                for _, m in ipairs(GS.monsters) do
                    if m.hp > 0 and not m.fleeing then
                        local d = GS.manhattan(self.freya.x, self.freya.y, m.x, m.y)
                        if d < bestDist then
                            bestDist = d
                            bestTarget = m
                            bestDist = d
                        end
                    end
                end

                if bestTarget then
                    if bestDist <= self.freya.atkRange then
                        -- 攻击距离内 → 直接攻击（使用碎星技能特效）
                        Combat.performAttack(self.freya, bestTarget, "mst_stk")
                        if bestTarget.hp <= 0 then
                            Combat.processMonsterKill(GS.player, bestTarget)
                        end
                    else
                        -- 不在攻击距离 → 移动靠近
                        local movable, parents = GS.getMovableCellsForMonster(self.freya)
                        local bestX, bestY = self.freya.x, self.freya.y
                        local bestMoveDist = bestDist
                        for key, _ in pairs(movable) do
                            local cy = math.floor(key / 100)
                            local cx = key - cy * 100
                            if GS.isCellEmpty(cx, cy) or (cx == self.freya.x and cy == self.freya.y) then
                                local d = GS.manhattan(cx, cy, bestTarget.x, bestTarget.y)
                                if d < bestMoveDist then
                                    bestMoveDist = d
                                    bestX = cx
                                    bestY = cy
                                end
                            end
                        end
                        if bestX ~= self.freya.x or bestY ~= self.freya.y then
                            local oldX, oldY = self.freya.x, self.freya.y
                            local path = GS.reconstructPath(parents, oldX, oldY, bestX, bestY)
                            self.freya.x = bestX
                            self.freya.y = bestY
                            Combat.startMoveAnim(self.freya, oldX, oldY, path)
                        end
                        -- 移动后记录待定攻击，等移动动画播完后同回合内执行碎星
                        local newDist = GS.manhattan(self.freya.x, self.freya.y, bestTarget.x, bestTarget.y)
                        if newDist <= self.freya.atkRange then
                            self._freyaPendingAttack = { target = bestTarget }
                        end
                    end
                end
            end

            -- === 哥布林行动 ===
            for _, m in ipairs(GS.monsters) do
                if m.hp <= 0 then goto cont_m end

                if m.fleeing then
                    -- 逃跑：向最近边缘移动
                    local movable, parents = GS.getMovableCellsForMonster(m)
                    local bestX, bestY = m.x, m.y
                    local bestEdgeDist = math.min(m.x - 1, GS.BOARD_SIZE - m.x, m.y - 1, GS.BOARD_SIZE - m.y)
                    for key, _ in pairs(movable) do
                        local cy = math.floor(key / 100)
                        local cx = key - cy * 100
                        if GS.isCellEmpty(cx, cy) or (cx == m.x and cy == m.y) then
                            local edgeDist = math.min(cx - 1, GS.BOARD_SIZE - cx, cy - 1, GS.BOARD_SIZE - cy)
                            if edgeDist < bestEdgeDist then
                                bestEdgeDist = edgeDist
                                bestX = cx
                                bestY = cy
                            end
                        end
                    end
                    if bestX ~= m.x or bestY ~= m.y then
                        local oldX, oldY = m.x, m.y
                        local path = GS.reconstructPath(parents, oldX, oldY, bestX, bestY)
                        m.x = bestX
                        m.y = bestY
                        Combat.startMoveAnim(m, oldX, oldY, path)
                    end
                else
                    -- 非逃跑：向芙蕾雅靠近，移动后记录待定攻击（等所有移动结束再统一攻击）
                    local target = self.freya
                    if target and target.hp > 0 then
                        local dist = GS.manhattan(m.x, m.y, target.x, target.y)
                        if dist <= m.atkRange then
                            -- 已在攻击距离内，不需要移动，记录待定攻击
                            if not self._goblinPendingAttacks then self._goblinPendingAttacks = {} end
                            self._goblinPendingAttacks[#self._goblinPendingAttacks + 1] = { attacker = m, target = target }
                        else
                            -- 移动靠近
                            local movable, parents = GS.getMovableCellsForMonster(m)
                            local bestX, bestY = m.x, m.y
                            local bestMoveDist = dist
                            for key, _ in pairs(movable) do
                                local cy = math.floor(key / 100)
                                local cx = key - cy * 100
                                if GS.isCellEmpty(cx, cy) or (cx == m.x and cy == m.y) then
                                    local d = GS.manhattan(cx, cy, target.x, target.y)
                                    if d < bestMoveDist then
                                        bestMoveDist = d
                                        bestX = cx
                                        bestY = cy
                                    end
                                end
                            end
                            if bestX ~= m.x or bestY ~= m.y then
                                local oldX, oldY = m.x, m.y
                                local path = GS.reconstructPath(parents, oldX, oldY, bestX, bestY)
                                m.x = bestX
                                m.y = bestY
                                Combat.startMoveAnim(m, oldX, oldY, path)
                            end
                            -- 移动后检查是否能攻击，记录待定攻击
                            local newDist = GS.manhattan(m.x, m.y, target.x, target.y)
                            if newDist <= m.atkRange then
                                if not self._goblinPendingAttacks then self._goblinPendingAttacks = {} end
                                self._goblinPendingAttacks[#self._goblinPendingAttacks + 1] = { attacker = m, target = target }
                            end
                        end
                    end
                end

                ::cont_m::
            end

            -- 移除死亡怪物
            Combat.removeDeadMonsters()

            self._waitForAnims = true
            print("[Event_Awakening] Fight turn " .. self.turnCount)
        end

    elseif self.phase == PHASE_CLEANUP_WAIT then
        -- 等待动画播放完毕，然后停顿1秒再让芙蕾雅移动
        if not anyMoveAnims() and not anySlamAnims() and not anyAttackEffects() then
            if not self._cleanupReady then
                self._cleanupReady = true
                self._cleanupTimer = 0
                -- 芙蕾雅头顶显示"呼……"渐隐文本
                if self.freya then
                    self.freya.floatingText = {
                        text = "呼……",
                        timer = 0,
                        duration = 2.0,  -- 总持续时间2秒
                        fadeStart = 1.0, -- 1秒后开始渐隐
                    }
                end
            end
            self._cleanupTimer = (self._cleanupTimer or 0) + dt
            if self._cleanupTimer >= 1.0 then
                self._cleanupReady = nil
                self._cleanupTimer = nil
                self:setPhase(PHASE_FREYA_WALK)
            end
        end

    elseif self.phase == PHASE_FREYA_WALK then
        if not self._phaseInited then
            self._phaseInited = true
            -- 芙蕾雅走到玩家上方 2 格（只执行一次）
            -- 使用 L 型路径（先横后竖或先竖后横），不穿过玩家
            if self.freya and GS.player then
                local targetX = GS.player.x
                local targetY = GS.player.y - 2
                if targetY < 1 then targetY = 1 end
                local oldX, oldY = self.freya.x, self.freya.y

                -- 构建 L 型路径：逐格横竖移动
                -- 选择路线：先横后竖 vs 先竖后横，避开玩家所在格
                local px, py = GS.player.x, GS.player.y
                local path = {}

                -- 生成先横后竖的路径
                local function buildPathHV(sx, sy, tx, ty)
                    local p = { {sx, sy} }
                    local cx, cy = sx, sy
                    local stepX = tx > cx and 1 or (tx < cx and -1 or 0)
                    while cx ~= tx do
                        cx = cx + stepX
                        p[#p + 1] = {cx, cy}
                    end
                    local stepY = ty > cy and 1 or (ty < cy and -1 or 0)
                    while cy ~= ty do
                        cy = cy + stepY
                        p[#p + 1] = {cx, cy}
                    end
                    return p
                end

                -- 生成先竖后横的路径
                local function buildPathVH(sx, sy, tx, ty)
                    local p = { {sx, sy} }
                    local cx, cy = sx, sy
                    local stepY = ty > cy and 1 or (ty < cy and -1 or 0)
                    while cy ~= ty do
                        cy = cy + stepY
                        p[#p + 1] = {cx, cy}
                    end
                    local stepX = tx > cx and 1 or (tx < cx and -1 or 0)
                    while cx ~= tx do
                        cx = cx + stepX
                        p[#p + 1] = {cx, cy}
                    end
                    return p
                end

                -- 检查路径是否经过玩家位置（不含起点和终点）
                local function pathHitsPlayer(p)
                    for i = 2, #p - 1 do
                        if p[i][1] == px and p[i][2] == py then
                            return true
                        end
                    end
                    return false
                end

                local pathHV = buildPathHV(oldX, oldY, targetX, targetY)
                local pathVH = buildPathVH(oldX, oldY, targetX, targetY)

                -- 优先选不经过玩家的路径
                if not pathHitsPlayer(pathHV) then
                    path = pathHV
                elseif not pathHitsPlayer(pathVH) then
                    path = pathVH
                else
                    -- 两条L路径都穿过玩家（芙蕾雅在玩家正下方），生成绕行路径
                    -- 先向左或右偏移1格，再竖直上行，最后横移回来
                    local detourX = oldX - 1
                    if detourX < 1 then detourX = oldX + 1 end
                    local p = { {oldX, oldY} }
                    -- 横移到偏移列
                    local stepX = detourX > oldX and 1 or -1
                    local cx = oldX
                    while cx ~= detourX do
                        cx = cx + stepX
                        p[#p + 1] = {cx, oldY}
                    end
                    -- 竖直上行到目标Y
                    local cy = oldY
                    while cy ~= targetY do
                        cy = cy - 1
                        p[#p + 1] = {detourX, cy}
                    end
                    -- 横移回目标X
                    if detourX ~= targetX then
                        local stepX2 = targetX > detourX and 1 or -1
                        local cx2 = detourX
                        while cx2 ~= targetX do
                            cx2 = cx2 + stepX2
                            p[#p + 1] = {cx2, targetY}
                        end
                    end
                    path = p
                end

                self.freya.x = targetX
                self.freya.y = targetY
                self.freya.facing = "down"
                local Combat = require("Combat")
                Combat.startMoveAnim(self.freya, oldX, oldY, path)
                print("[Event_Awakening] Freya walking to (" .. targetX .. "," .. targetY .. ") via L-path, " .. #path .. " steps")
            end
        end
        -- 等移动动画完成
        if self.timer >= 0.3 and not anyMoveAnims() then
            self:setPhase(PHASE_DIALOGUE_2)
        end

    elseif self.phase == PHASE_DIALOGUE_2 then
        if not self._phaseInited then
            self._phaseInited = true
            self._d2FloatingShown = false  -- 第3句悬浮文本是否已触发
            -- 对话时双方面朝彼此
            if self.freya and GS.player then
                self.freya.facing = "down"
                GS.player.facing = "up"
            end
            DialogueManager.start("event_awakening_2")
        end
        -- 第3句对话时，在芙蕾雅头上显示悬浮文本
        if not self._d2FloatingShown and DialogueManager.active and DialogueManager.lineIndex == 3 then
            self._d2FloatingShown = true
            if self.freya then
                self.freya.floatingText = {
                    text = "（湿透了的感觉真烦人，衣服黏糊糊的……）",
                    timer = 0,
                    duration = 4.0,
                    fadeStart = 2.5,
                }
            end
        end
        -- 等对话结束 → 进入离场阶段
        if self._phaseInited and not DialogueManager.active and self.timer > 0.3 then
            self:setPhase(PHASE_WALK_EXIT)
        end

    elseif self.phase == PHASE_WALK_EXIT then
        -- 芙蕾雅和玩家一起向上走到棋盘边缘后消失
        if not self._phaseInited then
            self._phaseInited = true
            self._exitStep = 1  -- 1=走路中 2=已消失等待过渡
            local Combat = require("Combat")

            -- 芙蕾雅向上走到 Y=1
            if self.freya then
                local oldX, oldY = self.freya.x, self.freya.y
                local targetY = 1
                self.freya.facing = "up"
                -- 生成逐格向上路径
                local path = { {oldX, oldY} }
                for y = oldY - 1, targetY, -1 do
                    path[#path + 1] = {oldX, y}
                end
                self.freya.x = oldX
                self.freya.y = targetY
                Combat.startMoveAnim(self.freya, oldX, oldY, path)
            end

            -- 玩家向上走到 Y=1
            if GS.player then
                local oldX, oldY = GS.player.x, GS.player.y
                local targetY = 1
                GS.player.facing = "up"
                local path = { {oldX, oldY} }
                for y = oldY - 1, targetY, -1 do
                    path[#path + 1] = {oldX, y}
                end
                GS.player.x = oldX
                GS.player.y = targetY
                Combat.startMoveAnim(GS.player, oldX, oldY, path)
            end

            print("[Event_Awakening] Both walking to board edge")
        end

        if self._exitStep == 1 then
            -- 等待移动动画完成（到达Y=1边缘）
            local playerDone = not GS.player or not GS.player.moveAnim
            local freyaDone = not self.freya or not self.freya.moveAnim
            if playerDone and freyaDone and self.timer >= 0.3 then
                -- 短暂停留后开始渐隐
                self._exitStep = 2
                self._fadeTimer = 0
                self._fadeDuration = 0.8  -- 渐隐持续时间
                -- 稍作停留
                self._pauseTimer = 0
            end
        elseif self._exitStep == 2 then
            -- 停留0.3秒后开始渐隐
            self._pauseTimer = self._pauseTimer + dt
            if self._pauseTimer >= 0.3 then
                self._exitStep = 3
                self._fadeTimer = 0
            end
        elseif self._exitStep == 3 then
            -- 渐隐动画
            self._fadeTimer = self._fadeTimer + dt
            local alpha = 1.0 - math.min(1.0, self._fadeTimer / self._fadeDuration)
            if GS.player then GS.player.drawAlpha = alpha end
            if self.freya then self.freya.drawAlpha = alpha end
            if self._fadeTimer >= self._fadeDuration then
                -- 完全消失，保持 drawAlpha=0 防止闪现
                if GS.player then GS.player.drawAlpha = 0 end
                if self.freya then self.freya.drawAlpha = 0 end
                self._exitStep = 4
                self._exitWaitTimer = 0
            end
        elseif self._exitStep == 4 then
            -- 短暂停顿后开始黑屏过渡
            self._exitWaitTimer = self._exitWaitTimer + dt
            if self._exitWaitTimer >= 0.3 then
                self:setPhase(PHASE_SCENE_FADE)
            end
        end

    elseif self.phase == PHASE_SCENE_FADE then
        -- 使用与关卡切换完全相同的 sceneTransition 转场效果
        if not self._phaseInited then
            self._phaseInited = true
            self._transitionStarted = false
        end

        if not self._transitionStarted then
            self._transitionStarted = true
            local selfRef = self
            GS.startSceneTransition(function()
                -- 全黑保持期间执行场景切换（与关卡切换逻辑一致）
                -- 恢复玩家位置到清水镇（清理渐隐状态）
                if GS.player then
                    GS.player.x = 6
                    GS.player.y = 6
                    GS.player.facing = "right"
                    GS.player.drawAlpha = nil
                end
                -- 清除苏醒事件关卡的怪物
                GS.monsters = {}
                -- 移除芙蕾雅同伴
                if selfRef.freya then
                    for i = #GS.companions, 1, -1 do
                        if GS.companions[i] == selfRef.freya then
                            table.remove(GS.companions, i)
                        end
                    end
                    selfRef.freya = nil
                end
                -- 关闭隐匿（但保持 isEvent=true，让事件继续运行）
                GS.stealthActive = false
                GS.stealthTurns = 0

                -- 显示清水镇
                local BoardOverlay = require("BoardOverlay")
                BoardOverlay.show("town", "clearwater", "清水镇")

                -- 进入公会会长办公室（真正的建筑物，带离开按钮、禁雨等）
                BoardOverlay.enterSubScene("guild_master_office")

                -- 事件期间隐藏"回到前台"按钮，只允许退出到清水镇
                if BoardOverlay.subScene then
                    for i = #BoardOverlay.subScene.buttons, 1, -1 do
                        if BoardOverlay.subScene.buttons[i].action == "back_to_guild" then
                            table.remove(BoardOverlay.subScene.buttons, i)
                        end
                    end
                end

                print("[Event_Awakening] Switched to town, entered guild master office")
            end)
        end

        -- 等待转场动画完成后进入下一阶段
        if not GS.sceneTransition then
            self:setPhase(PHASE_GUILD_SCENE)
        end

    elseif self.phase == PHASE_GUILD_SCENE then
        -- 公会场景：短暂停顿后开始对话
        if not self._phaseInited then
            self._phaseInited = true
            -- 到达会长办公室，解除BGM静音，恢复播放清水镇BGM
            GS.bgmMuted = false
        end
        if self.timer >= 0.8 then
            self:setPhase(PHASE_DIALOGUE_3A)
        end

    elseif self.phase == PHASE_DIALOGUE_3A then
        -- 对话 3A：前4句（???介绍 → 芙蕾雅自报 → 询问名字）
        if not self._phaseInited then
            self._phaseInited = true
            local selfRef = self
            GS.learnNPCName("guild_master")
            DialogueManager.startDynamic({
                { speaker = "？？？", text = "累了吧？请坐。" },
                { speaker = "？？？", text = "自我介绍一下，我的名字是芙蕾雅，是冒险者公会的会长。" },
                { speaker = "芙蕾雅", text = "我知道你有很多疑惑，但现阶段需要你先回答我几个问题。" },
                { speaker = "芙蕾雅", text = "你的名字是？" },
            }, function()
                selfRef:setPhase(PHASE_NAME_INPUT)
            end)
        end

    elseif self.phase == PHASE_NAME_INPUT then
        -- 名字输入
        if not self._phaseInited then
            self._phaseInited = true
            GS.eventNameInput = {
                active = true,
                text = "冒险者",
                placeholder = "请输入名字...",
                confirmed = false,
                imeComposing = false,
                imeComposition = nil,
            }
            -- 启用文本输入（桌面端激活 IME，移动端弹出软键盘）
            input:SetScreenKeyboardVisible(true)
            print("[Event_Awakening] Name input started")
        end
        -- 检测确认
        local ni = GS.eventNameInput
        if ni and ni.confirmed then
            GS.charName = ni.text or "旅人"
            print("[Event_Awakening] Player name set: " .. GS.charName)
            -- 关闭名字输入面板
            GS.eventNameInput = nil
            GS._nameInputConfirmRect = nil
            GS._nameInputRect = nil
            -- 停用文本输入（桌面端关闭 IME，移动端收起软键盘）
            input:SetScreenKeyboardVisible(false)
            self:setPhase(PHASE_DIALOGUE_3B)
        end

    elseif self.phase == PHASE_DIALOGUE_3B then
        -- 对话 3B：第6-10句（含{玩家}占位符），结束后进入职业选择
        if not self._phaseInited then
            self._phaseInited = true
            local selfRef = self
            DialogueManager.startDynamic({
                { speaker = "芙蕾雅", text = "{玩家}……这和神谕里一样。" },
                { speaker = "芙蕾雅", text = "无论如何，我们冒险者公会都会为你提供必要的帮助，但并非毫无条件。" },
                { speaker = "芙蕾雅", text = "最近，周遭的魔物越来越猖獗了，也请你尽可能帮助城镇消灭魔物的威胁吧。" },
                { speaker = "芙蕾雅", text = "我们会提供与你所做贡献对等的服务。资源是有限的，你要证明你值得投入。" },
                { speaker = "芙蕾雅", text = "对了，你的职业是什么？还没有？那就现在选择一个吧，我们需要登记。" },
            }, function()
                selfRef:setPhase(PHASE_CLASS_SELECT)
            end)
        end

    elseif self.phase == PHASE_CLASS_SELECT then
        -- 职业选择（5个选项）
        if not self._phaseInited then
            self._phaseInited = true
            GS._choiceBadges = nil  -- 清除残留的任务徽章，避免职业选项误显图标
            local selfRef = self
            DialogueManager.startDynamic({
                {
                    speaker = "芙蕾雅",
                    text = "你想选择什么职业？",
                    choices = { "战士", "法师", "猎人", "刺客", "牧师" },
                    onChoice = function(index, label)
                        -- 映射选项到职业 ID
                        local classMap = { "warrior", "mage", "hunter", "assassin", "priest" }
                        selfRef._selectedClassId = classMap[index]
                        selfRef._selectedClassName = label
                        print("[Event_Awakening] Class selected: " .. label .. " (" .. classMap[index] .. ")")
                        -- 选择后自动推进（关闭当前对话，进入确认阶段）
                        DialogueManager.advance()
                    end,
                },
            }, function()
                selfRef:setPhase(PHASE_CLASS_CONFIRM)
            end)
        end

    elseif self.phase == PHASE_CLASS_CONFIRM then
        -- 确认职业（可循环回选择）
        if not self._phaseInited then
            self._phaseInited = true
            local selfRef = self
            local className = selfRef._selectedClassName or "战士"
            DialogueManager.startDynamic({
                {
                    speaker = "芙蕾雅",
                    text = className .. "吗？",
                    choices = { "确定", "我再想想" },
                    onChoice = function(index)
                        if index == 1 then
                            -- 确定：应用职业变更
                            GS.changeClass(selfRef._selectedClassId)
                            GS.confirmedClass = selfRef._selectedClassId  -- 合法职业变更，同步确认标记
                            print("[Event_Awakening] Class confirmed: " .. selfRef._selectedClassId)
                            DialogueManager.advance()
                        else
                            -- 重新选择：先显示安慰对话，再回到选择
                            DialogueManager.advance()  -- 关闭当前对话
                        end
                    end,
                },
            }, function()
                if GS.currentClass == selfRef._selectedClassId then
                    -- 职业已确认，进入后续对话
                    selfRef:setPhase(PHASE_DIALOGUE_3C)
                else
                    -- 选了"我再想想"，显示过渡对话后回到选择
                    selfRef._phaseInited = false  -- 标记需要重新初始化
                    selfRef._showReconsider = true
                end
            end)
        end
        -- "我再想想"的过渡对话
        if self._showReconsider then
            self._showReconsider = false
            local selfRef = self
            DialogueManager.startDynamic({
                { speaker = "芙蕾雅", text = "没关系，你可以再想想。" },
            }, function()
                selfRef:setPhase(PHASE_CLASS_SELECT)
            end)
        end

    elseif self.phase == PHASE_DIALOGUE_3C then
        -- 对话 3C：最后2句
        if not self._phaseInited then
            self._phaseInited = true
            local selfRef = self
            DialogueManager.startDynamic({
                { speaker = "芙蕾雅", text = "我会让妮可准备一些初始物资给你作为见面礼，请你稍后到冒险者公会接待处领取。" },
                { speaker = "芙蕾雅", text = "我还有事，重要的事。那么，在我离开前，你有什么想问我的吗？" },
            }, function()
                selfRef:setPhase(PHASE_QA_SELECT)
            end)
        end

    elseif self.phase == PHASE_QA_SELECT then
        -- Q&A 选项：显示剩余未问过的问题
        if not self._phaseInited then
            self._phaseInited = true
            if not self._askedQuestions then self._askedQuestions = {} end
            local selfRef = self

            -- 构建剩余选项（1~5中未问过的 + 始终保留第6个退出选项）
            local choiceLabels = {}
            local choiceMapping = {}
            for i = 1, #QA_OPTIONS - 1 do
                if not self._askedQuestions[i] then
                    choiceLabels[#choiceLabels + 1] = QA_OPTIONS[i].label
                    choiceMapping[#choiceLabels] = i
                end
            end
            -- 始终添加退出选项在最后
            choiceLabels[#choiceLabels + 1] = QA_OPTIONS[#QA_OPTIONS].label
            choiceMapping[#choiceLabels] = #QA_OPTIONS

            DialogueManager.startDynamic({
                {
                    speaker = "芙蕾雅",
                    text = "……",
                    choices = choiceLabels,
                    onChoice = function(choiceIdx)
                        local qaIdx = choiceMapping[choiceIdx]
                        selfRef._currentQA = qaIdx
                        if not QA_OPTIONS[qaIdx].isExit then
                            selfRef._askedQuestions[qaIdx] = true
                        end
                        DialogueManager.advance()
                    end,
                },
            }, function()
                local qaIdx = selfRef._currentQA
                if QA_OPTIONS[qaIdx].isExit then
                    selfRef:setPhase(PHASE_QA_EXIT)
                else
                    selfRef:setPhase(PHASE_QA_ANSWER)
                end
            end)
        end

    elseif self.phase == PHASE_QA_ANSWER then
        -- Q&A 回答：播放选中问题的回答对话
        if not self._phaseInited then
            self._phaseInited = true
            local selfRef = self
            local qa = QA_OPTIONS[self._currentQA]

            -- 构建对话序列
            local lines = {}
            for _, d in ipairs(qa.dialogues) do
                lines[#lines + 1] = { speaker = d.speaker, text = d.text }
            end

            -- 如有子选项（阿妮塔问题），附加到最后一句对话上
            if qa.subChoice then
                lines[#lines].choices = { qa.subChoice.choiceLabel }
                lines[#lines].onChoice = function() DialogueManager.advance() end
                lines[#lines + 1] = { speaker = qa.subChoice.response.speaker, text = qa.subChoice.response.text }
            end

            DialogueManager.startDynamic(lines, function()
                selfRef:setPhase(PHASE_QA_SELECT)
            end)
        end

    elseif self.phase == PHASE_QA_EXIT then
        -- Q&A 退出：播放告别对话，对话结束后立即完成事件
        if not self._phaseInited then
            self._phaseInited = true
            self._qaDialogueEnded = false
            local qa = QA_OPTIONS[#QA_OPTIONS]
            DialogueManager.startDynamic(qa.dialogues)
            print("[Event_Awakening] QA_EXIT dialogue started")
        end
        -- 对话结束即完成事件（不再等待2秒）
        if not self._qaDialogueEnded then
            if not DialogueManager.active then
                self._qaDialogueEnded = true
                print("[Event_Awakening] QA_EXIT dialogue ended, completing event immediately")

                -- 清理事件残留
                GS.eventSceneImage = nil
                GS.eventBlackScreen = nil

                -- 标记苏醒事件完成
                GS.awakeningCompleted = true
                GS.weatherTime = 428  -- 设定为早上 7:07
                GS.eventCompleted["awakening"] = true

                -- 激活主线「第三意志」、支线「清水镇的人们」和斩首系列第一个任务
                local QuestManager = require("QuestManager")
                QuestManager.activateQuest("main_third_will")
                QuestManager.activateQuest("side_townspeople")
                QuestManager.activateQuest("main_freya_bounty_item_slime")
                GS.eventInputLocked = false

                -- 退出事件（保留子场景，玩家留在会长办公室）
                local Combat = require("Combat")
                EventManager.exit(true)  -- skipRestore=true

                -- 生成清水镇内容（exit 会清空 monsters/companions）
                Combat.spawnGatherables()
                Combat.spawnMonsters()
                GS.spawnHound()

                -- 存档
                GS.updateAutoSaveSnapshot()
                GS.saveToCloud()
                GS.autoSave.enabled = true

                -- 在子场景中添加"交谈"按钮，替换原有的通用交谈按钮
                local BoardOverlay = require("BoardOverlay")
                if BoardOverlay.subScene then
                    -- 移除原有的 talk 按钮，避免出现两个"交谈"
                    for i = #BoardOverlay.subScene.buttons, 1, -1 do
                        if BoardOverlay.subScene.buttons[i].action == "talk" then
                            table.remove(BoardOverlay.subScene.buttons, i)
                        end
                    end
                    table.insert(BoardOverlay.subScene.buttons, 1, { label = "交谈", action = "talk_freya" })
                end

                print("[Event_Awakening] Event complete, cloud saved. Player stays in guild master office.")
            end
        end
    end
end

-- ================================================================
-- 注册到 EventManager
-- ================================================================
EventManager.register("awakening", M)

return M
