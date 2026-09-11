-- ====================================================================
-- Event/Event_DifenRevenge.lua - "复仇" 事件关卡
-- ====================================================================
-- 触发时机：迪芬旅行任务 side_difen_revenge 的战斗阶段
-- 流程：
--   1. 玩家出生在 (6,12)，迪芬在 (7,12)，黑熊王在 (7,3)
--   2. 玩家正常操控，迪芬在友军回合行动
--   3. 击杀黑熊王 → 胜利
--   4. 播放胜利对话后退出事件，回到旅行任务对话流程
-- ====================================================================

local GS = require("GameState")
local EventManager = require("Event.EventManager")
local DialogueManager = require("DialogueManager")
local ImageManager = require("ImageManager")

local M = {}
M.id = "difen_revenge"
M.name = "复仇"

-- ================================================================
-- 阶段常量
-- ================================================================
local PHASE_INIT        = "init"
local PHASE_BATTLE      = "battle"
local PHASE_VICTORY     = "victory"
local PHASE_DIALOGUE    = "dialogue"
local PHASE_EXIT        = "exit"

-- ================================================================
-- 内部状态
-- ================================================================
M.phase = nil
M.timer = 0
M.difen = nil
M._phaseInited = false
M._onBattleEnd = nil  -- 战斗结束回调（由外部设置）

-- ================================================================
-- 工具函数
-- ================================================================

--- 从 MONSTER_DB 创建一个怪物实例
local function createMonster(defKey, x, y)
    local def = GS.MONSTER_DB[defKey]
    if not def then
        print("[Event_DifenRevenge] Unknown monster: " .. tostring(defKey))
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
        noDrop = true,  -- 事件关卡不掉落
    }
end

--- 创建迪芬友军实例
local function createDifen(x, y)
    local def = GS.MONSTER_DB["difen"]
    if not def then
        print("[Event_DifenRevenge] Difen definition not found in MONSTER_DB!")
        return nil
    end
    return {
        x = x, y = y,
        name = "迪芬",
        level = def.level or 45,
        hp = def.hp, maxHp = def.hp,
        atk = def.atk, def = def.def, mdef = def.mdef or def.def,
        mAtk = def.mAtk or 0,
        critVal = def.critVal or 0,
        critDmg = def.critDmg or 50,
        hit = def.hit or 0,
        dodge = def.dodge or 0,
        moveRange = def.moveRange or 2,
        atkRange = def.atkRange or 1,
        atkSpeed = def.atkSpeed or 0,
        color = { def.color[1], def.color[2], def.color[3] },
        image = def.image,
        rarity = def.rarity,
        isCompanion = true,
        isEventAlly = true,
        acted = false,
        facing = "up",
        weaponTag = "单手剑",
        hasFloatingSword = true,
    }
end

-- ================================================================
-- 阶段切换
-- ================================================================

function M:setPhase(newPhase)
    print("[Event_DifenRevenge] Phase: " .. tostring(self.phase) .. " -> " .. newPhase)
    self.phase = newPhase
    self.timer = 0
    self._phaseInited = false
end

-- ================================================================
-- 生命周期
-- ================================================================

function M:onEnter()
    -- 允许正常回合流程（玩家操控+友军回合+敌人回合）
    GS.eventAllowNormalTurns = true

    -- 1. 设置背景（森林矿洞深处）
    GS.currentBattleBg = "image/bg_forest_cave_deep.png"

    -- 2. 放置玩家
    if GS.player then
        GS.player.x = 6
        GS.player.y = 12
        GS.player.facing = "up"
        GS.player.acted = false
    end

    -- 3. 创建迪芬友军
    local difen = createDifen(7, 12)
    if difen then
        self.difen = difen
        table.insert(GS.companions, difen)
        if difen.image then
            ImageManager.lazyGet("companion", difen.image)
        end
        print("[Event_DifenRevenge] Difen placed at (7, 12)")
    end

    -- 4. 创建黑熊王
    local bear = createMonster("black_bear_king", 7, 3)
    if bear then
        bear.facing = "down"
        table.insert(GS.monsters, bear)
        if bear.image then
            ImageManager.lazyGet("monster", bear.image)
        end
        print("[Event_DifenRevenge] Black Bear King placed at (7, 3)")
    end

    -- 5. 解锁玩家输入（玩家正常操控）
    GS.eventInputLocked = false
    GS.gameState = GS.STATE_PLAYER
    GS.turnPhase = GS.PHASE_MOVE
    GS.turnNumber = 0

    print("[Event_DifenRevenge] Battle started: player(6,12) + difen(7,12) vs black_bear_king(7,3)")

    -- 进入战斗阶段
    self:setPhase(PHASE_BATTLE)
end

function M:onExit()
    -- 清理友军浮动文本（防止残留到下一个场景）
    for _, c in ipairs(GS.companions) do
        c.floatingText = nil
    end

    self.difen = nil
    self.phase = nil
    self.timer = 0
    self._phaseInited = false
    self._onBattleEnd = nil

    GS.eventAllowNormalTurns = false
    GS.eventInputLocked = false
    GS._choiceRects = nil
    GS.eventSceneBg = nil  -- 确保场景背景标志被清理
end

-- ================================================================
-- 每帧更新
-- ================================================================

function M:update(dt)
    if not self.phase then return end

    self.timer = self.timer + dt

    -- 更新友军浮动文本计时器
    for _, c in ipairs(GS.companions) do
        if c.floatingText then
            c.floatingText.timer = c.floatingText.timer + dt
            if c.floatingText.timer >= c.floatingText.duration then
                c.floatingText = nil
            end
        end
    end

    if self.phase == PHASE_BATTLE then
        -- 迪芬被动：HP 降到 0 以下时，回复 100 HP（可无限触发）
        if self.difen and self.difen.hp <= 0 then
            self.difen.hp = 100
            self.difen.dead = nil  -- 清除死亡标记（防止被 removeDeadCompanions 标记）
            -- 治疗特效（绿色粒子）
            local Combat = require("Combat")
            Combat.addHealEffect(self.difen.x, self.difen.y, self.difen)
            Combat.addDamageText(self.difen.x, self.difen.y, "+100", {100, 255, 100})
            -- 白色悬浮文字
            self.difen.floatingText = {
                text = "啊啊啊啊啊——！父亲！",
                timer = 0,
                duration = 3.0,
                fadeStart = 2.0,
            }
            print("[Event_DifenRevenge] Difen passive triggered: restored 100 HP")
        end

        -- 战斗中：检查黑熊王是否死亡
        local bearAlive = false
        for _, m in ipairs(GS.monsters) do
            if m.hp > 0 then
                bearAlive = true
                break
            end
        end

        if not bearAlive then
            -- 等待攻击动画播完
            local anyAnim = false
            for _, c in ipairs(GS.companions) do
                if c.slamAnim or c.moveAnim then anyAnim = true; break end
            end
            if GS.player and (GS.player.slamAnim or GS.player.moveAnim) then
                anyAnim = true
            end
            if #GS.attackEffects > 0 or #GS.strikeEffects > 0 then
                anyAnim = true
            end

            if not anyAnim then
                self:setPhase(PHASE_VICTORY)
            end
        end

    elseif self.phase == PHASE_VICTORY then
        if not self._phaseInited then
            self._phaseInited = true
            -- 清除残余怪物
            local Combat = require("Combat")
            Combat.removeDeadMonsters()
            -- 锁定输入
            GS.eventInputLocked = true
            print("[Event_DifenRevenge] Victory! Black Bear King defeated.")
        end
        -- 短暂停顿后播放对话
        if self.timer >= 1.0 then
            self:setPhase(PHASE_DIALOGUE)
        end

    elseif self.phase == PHASE_DIALOGUE then
        if not self._phaseInited then
            self._phaseInited = true
            -- 播放胜利对话
            local selfRef = self
            DialogueManager.startDynamic({
                { speaker = "迪芬", text = "呼……谢谢你，{玩家}……谢谢你……没有你的话，我不可能做得到。父亲，安息吧。" },
                { speaker = "？？？", text = "那个……你们是从镇上过来的吗？" },
                { speaker = "旁白", text = "（在一块岩石后面传出了怯生生的少年声音，你看过去，发现对方约莫16岁，浑身的衣服都脏兮兮的。）" },
                { speaker = "迪芬", text = "我们是从清水镇来的，你叫什么名字？" },
                { speaker = "？？？", text = "约瑟夫……我怕极了。" },
                { speaker = "迪芬", text = "可怜的小家伙，应该是被熊堵在这了，也不知道多久没吃东西了。" },
                { speaker = "迪芬", text = "{玩家}，我们先带他回去再说吧。约瑟夫，跟我们走，我们回去洗个热水澡、再吃烤鸡吃到饱。" },
            }, function()
                selfRef:setPhase(PHASE_EXIT)
            end)
        end

    elseif self.phase == PHASE_EXIT then
        if not self._phaseInited then
            self._phaseInited = true
            -- 通知外部战斗结束
            if self._onBattleEnd then
                self._onBattleEnd()
            else
                -- 默认：直接退出事件
                EventManager.exit()
            end
        end
    end
end

-- ================================================================
-- 注册到 EventManager
-- ================================================================
EventManager.register("difen_revenge", M)

return M
