-- ============================================================
-- Combat_Turns.lua  —— 回合管理/AI/伙伴系统
-- 由 Combat.lua 拆分，通过 init(M) 挂载到主模块
-- ============================================================
local GS = require("GameState")
local DungeonManager = require("Dungeon.DungeonManager")
local WE = require("WeatherEffects")

local sub = {}

function sub.init(M)

-- 桥接：从主模块获取共享 local 函数
local applyElementBonus      = M._applyElementBonus
local tickBlessingBuffs      = M._tickBlessingBuffs

-- 回合管理
-- ====================================================================

--- 怪物 debuff 回合递减（在敌人回合结束后、玩家回合开始前调用）
function M.tickMonsterDebuffs()
    local anyKilled = false
    for _, m in ipairs(GS.monsters) do
        if m.taunted and m.taunted > 0 then
            m.taunted = m.taunted - 1
            if m.taunted <= 0 then
                m.taunted = nil
                m.tauntAtkPct = nil
                m.tauntDefPct = nil
            end
        end
        if m.stunned and m.stunned > 0 then
            if not m.brawlStunned then  -- 肉搏击晕永不解除
                m.stunned = m.stunned - 1
                if m.stunned <= 0 then
                    m.stunned = nil
                end
            end
        end
        if m.feared and m.feared > 0 then
            m.feared = m.feared - 1
            if m.feared <= 0 then
                m.feared = nil
            end
        end
        if m.frozen and m.frozen > 0 then
            m.frozen = m.frozen - 1
            if m.frozen <= 0 then
                m.frozen = nil
            end
        end
        -- 中毒tick：每回合受到最大HP百分比的真实伤害，按回合递减
        if m.poisoned and m.poisoned > 0 and m.hp > 0 then
            local poisonDmg = math.max(1, math.floor(m.maxHp * m.poisoned / 100))
            -- 中毒伤害上限：不超过施加者ATK的200%
            if m.poisonApplierAtk and m.poisonApplierAtk > 0 then
                local cap = math.floor(m.poisonApplierAtk * 2)
                poisonDmg = math.min(poisonDmg, cap)
            end
            m.hp = m.hp - poisonDmg
            if GS.trainingMode and m.isTrainingDummy then GS.trainingTurnDmg = GS.trainingTurnDmg + poisonDmg end
            M.addDamageText(m.x, m.y - 0.3, "" .. poisonDmg, {180, 80, 220})
            if m.hp <= 0 then
                m.hp = 0
                M.processMonsterKill(GS.player, m)
                anyKilled = true
            end
            -- 回合递减
            if m.poisonTurns then
                m.poisonTurns = m.poisonTurns - 1
                if m.poisonTurns <= 0 then
                    m.poisoned = nil
                    m.poisonTurns = nil
                    m.poisonApplierAtk = nil
                end
            end
        end
        -- 灼伤tick：遍历所有灼伤层，每层独立计算伤害
        -- 兼容旧存档：将旧字段迁移到 burnStacks
        if m.burned and m.burnedTurns and not m.burnStacks then
            m.burnStacks = { { turns = m.burnedTurns, mAtk = m.burnedMAtk or 0 } }
            m.burnedTurns = nil
            m.burnedMAtk = nil
        end
        if m.burnStacks and #m.burnStacks > 0 and m.hp > 0 then
            local totalBurnDmg = 0
            local burnDef = m.mdef or 0
            -- 蒸腾检查（一次性判断）
            local evaporate = m.chilled or (m.frozen and m.frozen > 0)
            local totalBurnSC = #m.burnStacks  -- 蒸腾倍率基于灼烧总层数
            local chillSC = evaporate and M.getEffectiveChillStacks(m) or 0
            local evapBonus = evaporate and (WE.getEvaporationBonus() * (totalBurnSC + chillSC)) or 0
            for si = #m.burnStacks, 1, -1 do
                local stack = m.burnStacks[si]
                local burnAtk = stack.mAtk or 0
                local fullDmg = math.floor(burnAtk * burnAtk / (burnAtk + math.max(1, burnDef)))
                local burnDmg = math.max(1, math.floor(fullDmg * 0.30))
                burnDmg = applyElementBonus(burnDmg, "fire")
                -- 玩家火焰伤害/魔法伤害加成（加算）
                local p = GS.player
                if p then
                    local bonusPct = (p.fireDmgBonus or 0) + (p.magDmgBonus or 0)
                    if bonusPct > 0 then
                        burnDmg = math.max(1, math.floor(burnDmg * (1 + bonusPct / 100)))
                    end
                    -- 燃火（乘算）
                    if (p._ragingFireBonus or 0) > 0 then
                        burnDmg = math.max(1, math.floor(burnDmg * (1 + p._ragingFireBonus / 100)))
                    end
                end
                -- 抗性检查：火抗减伤30%
                if m.resistance then
                    for _, r in ipairs(m.resistance) do
                        if r == "fire" then
                            burnDmg = math.max(1, math.floor(burnDmg * 0.7))
                            break
                        end
                    end
                end
                -- 蒸腾加成
                if evaporate then
                    burnDmg = math.floor(burnDmg * (1 + evapBonus))
                end
                totalBurnDmg = totalBurnDmg + burnDmg
                -- 回合递减
                stack.turns = stack.turns - 1
                if stack.turns <= 0 then
                    table.remove(m.burnStacks, si)
                end
            end
            -- 蒸腾：清除冰冻/灼伤状态
            if evaporate then
                m.chilled = nil
                m.chilledTurns = nil
                m.chillStacks = nil
                m.frozen = nil
                M.clearBurnDebuff(m)
                M.addDamageText(m.x, m.y - 0.8, "蒸腾!", {255, 50, 50})
            end
            if totalBurnDmg > 0 then
                -- 灼烧暴击判定（魔法暴击）
                local burnCrit = false
                local p = GS.player
                if p then
                    local critVal = p.mCritRate or 0
                    local targetLv = math.max(1, m.level or 1)
                    local critChance = critVal > 0 and (critVal / (targetLv * 4)) or 0
                    if critVal > 0 then
                        local playerLv = math.max(1, p.level or 1)
                        critChance = math.min(critChance, playerLv / 100)
                    end
                    if critChance > 0 and math.random() < critChance then
                        local critDmgPct = p.mCritDmg or 25
                        totalBurnDmg = math.floor(totalBurnDmg * (1 + critDmgPct / 100))
                        burnCrit = true
                    end
                end
                m.hp = m.hp - totalBurnDmg
                if GS.trainingMode and m.isTrainingDummy then GS.trainingTurnDmg = GS.trainingTurnDmg + totalBurnDmg end
                if burnCrit then
                    M.addDamageText(m.x, m.y - 0.3, totalBurnDmg .. "!", {255, 120, 40}, 1.5)
                    GS.setScreenShake(0.15, 2, M._damageTextDelay or 0)
                else
                    M.addDamageText(m.x, m.y - 0.3, "" .. totalBurnDmg, {255, 120, 40})
                end
                if m.hp <= 0 then
                    m.hp = 0
                    M.processMonsterKill(GS.player, m)
                    anyKilled = true
                end
            end
            -- 所有层耗尽后清除 burned 标记
            if m.burnStacks and #m.burnStacks == 0 then
                M.clearBurnDebuff(m)
            end
        end
        -- 冻僵持续回合递减
        if m.chilledTurns and m.chilledTurns > 0 then
            m.chilledTurns = m.chilledTurns - 1
            if m.chilledTurns <= 0 then
                m.chilled = nil
                m.chilledTurns = nil
                m.chillStacks = nil
            end
        end
        -- 破甲持续回合递减
        if m.armorBrokenTurns and m.armorBrokenTurns > 0 then
            m.armorBrokenTurns = m.armorBrokenTurns - 1
            if m.armorBrokenTurns <= 0 then
                m.armorBroken = nil
                m.armorBrokenTurns = nil
            end
        end
        -- 泼沙致盲持续回合递减
        if m.sandBlindedTurns and m.sandBlindedTurns > 0 then
            m.sandBlindedTurns = m.sandBlindedTurns - 1
            if m.sandBlindedTurns <= 0 then
                m.sandBlinded = nil
                m.sandBlindedTurns = nil
            end
        end
        -- 预告信暴击易伤递减
        if m.noticeCritDmgTurns and m.noticeCritDmgTurns > 0 then
            m.noticeCritDmgTurns = m.noticeCritDmgTurns - 1
            if m.noticeCritDmgTurns <= 0 then
                m.noticeCritDmgBonus = nil
                m.noticeCritDmgTurns = nil
            end
        end
        -- 自愈词缀：每回合恢复5%最大生命
        if m.selfHeal and m.hp > 0 and m.hp < m.maxHp then
            local healAmt = math.max(1, math.floor(m.maxHp * 0.05))
            m.hp = math.min(m.maxHp, m.hp + healAmt)
            M.addDamageText(m.x, m.y - 0.3, "+" .. healAmt, {100, 220, 100})
        end
        -- 守门人闪烁突袭CD递减
        if m._flashCD and m._flashCD > 0 then
            m._flashCD = m._flashCD - 1
        end
        -- 迪拉边缘闪现CD递减
        if m._edgeBlinkCD and m._edgeBlinkCD > 0 then
            m._edgeBlinkCD = m._edgeBlinkCD - 1
        end
        -- 迪卡塔被动：战意叠加（每回合结束+1层，每层攻击力+2、攻速+0.5，最多100层）
        if m.defId == "goblin_boss_dikata" and m.hp > 0 then
            local stacks = m._battleIntentStacks or 0
            if stacks < 100 then
                stacks = stacks + 1
                m._battleIntentStacks = stacks
                m.atk = m.atk + 2
                m.atkSpeed = (m.atkSpeed or 0) + 0.5
                M.addDamageText(m.x, m.y - 0.8, "战意 ×" .. stacks, {255, 200, 60})
            end
        end
        -- 迪哈塔被动：战斗意志叠加（每回合结束+1层，每层攻速+1，无上限）
        if m.defId == "goblin_hero_dihata" and m.hp > 0 then
            local stacks = m._dihataWillStacks or 0
            stacks = stacks + 1
            m._dihataWillStacks = stacks
            m.atkSpeed = (m.atkSpeed or 0) + 1
            M.addDamageText(m.x, m.y - 0.8, "战斗意志 ×" .. stacks, {60, 200, 255})
        end
    end
    -- 中毒/灼伤 DOT 击杀后必须清理尸体，否则副本通关判定永远不触发
    if anyKilled then
        M.removeDeadMonsters()
    end
end

function M.startPlayerTurn()
    -- 延迟地图切换：回合结束后执行
    if M.pendingStageSwitch then
        local fn = M.pendingStageSwitch
        M.pendingStageSwitch = nil
        GS.autoMode = false
        fn()
        return
    end

    -- 事件关卡：跳过所有正常回合逻辑，由 EventManager 控制
    -- （允许正常回合的事件除外，如迪芬复仇关卡）
    if GS.isEvent and not GS.eventAllowNormalTurns then
        GS.gameState = GS.STATE_PLAYER
        GS.turnPhase = GS.PHASE_MOVE
        return
    end

    -- eventAllowNormalTurns 事件关卡：执行基本回合初始化，跳过关卡推进/刷怪/吟唱等
    if GS.isEvent and GS.eventAllowNormalTurns then
        GS.turnNumber = (GS.turnNumber or 0) + 1
        GS.selectedUnit = nil
        GS.movableCells = {}
        GS.attackableCells = {}
        if GS.player then
            GS.player.acted = false
            GS.counterUsedThisTurn = false
        end
        -- 友军重置
        for _, c in ipairs(GS.companions) do
            if c.hp > 0 then c.acted = false end
        end
        GS.gameState = GS.STATE_PLAYER
        GS.turnPhase = GS.PHASE_PRE
        GS.advanceTurnPhase()  -- PRE → MOVE
        print("[Event] 回合 " .. GS.turnNumber .. " 玩家回合")
        return
    end

    -- 训练场：结算上一回合伤害统计，重置假人HP
    if GS.trainingMode then
        GS.trainingTurnCount = GS.trainingTurnCount + 1
        GS.trainingTotalDmg = GS.trainingTotalDmg + GS.trainingTurnDmg
        GS.trainingDmgLog[#GS.trainingDmgLog + 1] = GS.trainingTurnDmg
        GS.trainingTurnDmg = 0
        -- 确保训练假人满血（防止各种边界情况）
        for _, m in ipairs(GS.monsters) do
            if m.isTrainingDummy then
                m.hp = m.maxHp
            end
        end
    end

    GS.turnNumber = GS.turnNumber + 1

    -- 狡诈奇美拉8件套：保存上回合伤害次数，重置当前回合计数
    GS._slyLastTurnHitCount = GS._slyHitCount or 0
    GS._slyHitCount = 0

    -- 蕴雷：重置同伴/幻影闪电链每回合触发计数
    GS._compChainLightningCount = 0
    -- 巴洛庄园飓风：重置护甲清零触发衍生飓风每回合计数；防御性清除待触发标志
    GS._armorClearHurricaneCount = 0
    GS._pendingHurricane = false

    -- 元素流转：保存上回合元素，设置持续1回合，重置当前回合
    if GS._eleFlowElem then
        GS._eleFlowLastElem = GS._eleFlowElem
        GS._eleFlowTurns = 1   -- 持续到下回合结束
    end
    GS._eleFlowElem = nil

    -- 天气变更计时：战斗中每回合结束+1
    GS.tickWeatherTime(1)

    -- 采集区重置计时：每回合+1，到720时重置所有采集区
    GS.tickGatherReset()

    GS.selectedUnit = nil
    GS.movableCells = {}
    GS.attackableCells = {}
    if not GS.player then return end
    GS.player.acted = false
    GS.counterUsedThisTurn = false
    GS._playerMovedThisTurn = false  -- 重置移动标记（静神被动判定用）
    GS.mageActionTaken = false
    GS.mageWaitingForClick = nil

    -- 月影：每回合开始清除上回合叠加的月影闪避BUFF
    if (GS.player._moonShadowStacks or 0) > 0 then
        GS.player._moonShadowStacks = nil
    end

    -- 满月：每层独立回合衰减
    if GS.player._fullMoonStackList and #GS.player._fullMoonStackList > 0 then
        for i = #GS.player._fullMoonStackList, 1, -1 do
            GS.player._fullMoonStackList[i] = GS.player._fullMoonStackList[i] - 1
            if GS.player._fullMoonStackList[i] <= 0 then
                table.remove(GS.player._fullMoonStackList, i)
            end
        end
        GS.player._fullMoonStacks = #GS.player._fullMoonStackList
        if GS.player._fullMoonStacks <= 0 then
            GS.player._fullMoonStackList = nil
            GS.player._fullMoonStacks = nil
            GS.player._fullMoonDodgeCount = nil
        end
    end

    -- 玩家冻僵 debuff tick 递减
    if GS.player and GS.player.chilledTurns and GS.player.chilledTurns > 0 then
        GS.player.chilledTurns = GS.player.chilledTurns - 1
        if GS.player.chilledTurns <= 0 then
            GS.player.chilled = nil
            GS.player.chilledTurns = nil
            GS.player.chillStacks = nil
        end
    end
    -- 友军冻僵 debuff tick 递减
    for _, c in ipairs(GS.companions) do
        if c.hp > 0 and c.chilledTurns and c.chilledTurns > 0 then
            c.chilledTurns = c.chilledTurns - 1
            if c.chilledTurns <= 0 then
                c.chilled = nil
                c.chilledTurns = nil
                c.chillStacks = nil
            end
        end
    end

    -- 燃火BUFF：回合开始时，若玩家站在灼烧地面上则激活额外火焰伤害加成
    GS.player._ragingFireBonus = nil
    if GS.player and (GS.player.ragingFireBonus or 0) > 0 and GS.burningGrounds then
        local px, py = GS.player.x, GS.player.y
        for _, bg in ipairs(GS.burningGrounds) do
            if bg.x == px and bg.y == py and (bg.turnsLeft or 0) > 0 then
                GS.player._ragingFireBonus = GS.player.ragingFireBonus
                break
            end
        end
    end

    -- 暴风雪 & 雷云持续效果 tick（回合开始时触发，动画有充足时间播放）
    if GS.turnNumber > 1 then
        M.tickBlizzardZones()
        M.tickThunderClouds()
        if M.checkPlayerDeath then M.checkPlayerDeath() end
    end

    -- 深渊二层环境效果：毒雾（棋盘四角曼哈顿距离≤2，回合开始造成1500自然伤害）
    if GS.getAbyssFloorIndex() == 2 then
        local p = GS.player
        if p and p.hp > 0 then
            local bs = GS.BOARD_SIZE
            local corners = {{1,1},{bs,1},{1,bs},{bs,bs}}
            local inCornerFog = false
            for _, c in ipairs(corners) do
                if math.abs(p.x - c[1]) + math.abs(p.y - c[2]) <= 2 then
                    inCornerFog = true
                    break
                end
            end
            if inCornerFog then
                local dmg = 1500
                p.hp = math.max(0, p.hp - dmg)
                M.addDamageText(p.x, p.y, "-" .. dmg, {80, 200, 50})
                M.addDamageText(p.x, p.y - 0.4, "毒雾!", {120, 220, 80})
                if M.checkPlayerDeath() then return end
            end
        end
    end

    -- 深渊三层环境效果：毒雾（棋盘外两圈，回合开始造成1500自然伤害）
    if GS.getAbyssFloorIndex() == 3 then
        local p = GS.player
        if p and p.hp > 0 then
            local edgeDist = math.min(p.x - 1, GS.BOARD_SIZE - p.x, p.y - 1, GS.BOARD_SIZE - p.y)
            if edgeDist < 2 then
                local dmg = 1500
                p.hp = math.max(0, p.hp - dmg)
                M.addDamageText(p.x, p.y, "-" .. dmg, {80, 200, 50})
                M.addDamageText(p.x, p.y - 0.4, "毒雾!", {120, 220, 80})
                if M.checkPlayerDeath() then return end
            end
        end
    end

    -- 友军复活倒计时
    M.tickCompanionRespawn()

    -- 火史莱姆精锐尸体倒计时与爆炸
    if #GS.fireCorpses > 0 then
        for i = #GS.fireCorpses, 1, -1 do
            local corpse = GS.fireCorpses[i]
            corpse.turns = corpse.turns - 1
            if corpse.turns <= 0 then
                -- 爆炸伤害：暴怒火史莱姆 = 等级×15，普通精锐 = 800
                local expDmg = 800
                if corpse.defId == "fire_slime_enraged" and corpse.level then
                    expDmg = corpse.level * 15
                end
                -- 爆炸！对周围8格+自身格造成真实伤害
                M.addDamageText(corpse.x, corpse.y, "爆炸!", {255, 120, 40})
                GS.setScreenShake(0.5, 5, 0)
                local px = GS.player and GS.player.x or -99
                local py = GS.player and GS.player.y or -99
                for dy = -1, 1 do
                    for dx = -1, 1 do
                        local tx, ty = corpse.x + dx, corpse.y + dy
                        -- 伤害玩家（真实伤害，无视防御）
                        if GS.player and GS.player.hp > 0 and tx == px and ty == py then
                            GS.player.hp = GS.player.hp - expDmg
                            M.addDamageText(px, py, "" .. expDmg, {255, 120, 40})
                            M.addHurtFlash(GS.player)
                            if GS.player.hp <= 0 then GS.player.hp = 0 end
                        end
                        -- 也伤害周围怪物（真实伤害）
                        for _, m in ipairs(GS.monsters) do
                            if m.hp > 0 then
                                local hit = false
                                local ms = GS.unitSize(m)
                                for my = m.y, m.y + ms - 1 do
                                    for mx = m.x, m.x + ms - 1 do
                                        if mx == tx and my == ty then hit = true end
                                    end
                                end
                                if hit and not m._fireExpHit then
                                    m._fireExpHit = true
                                    m.hp = m.hp - expDmg
                                    local cx, cy = GS.unitCenterPos(m)
                                    M.addDamageText(cx, cy, "" .. expDmg, {255, 120, 40})
                                    M.addHurtFlash(m)
                                    if m.hp <= 0 then
                                        m.hp = 0
                                        M.processMonsterKill(GS.player, m)
                                    end
                                end
                            end
                        end
                    end
                end
                -- 清除防重复标记
                for _, m in ipairs(GS.monsters) do m._fireExpHit = nil end
                table.remove(GS.fireCorpses, i)
            else
                -- M.addDamageText(corpse.x, corpse.y, corpse.turns .. "回合后爆炸", {255, 160, 60})
            end
        end
        M.removeDeadMonsters()
        if M.checkPlayerDeath() then return end
    end

    -- 祈祷术BUFF：回合开始回复最大生命值百分比
    local p = GS.player
    if p and p.hp > 0 and p.prayerHealPct and p.prayerHealPct > 0 and p.prayerTurns and p.prayerTurns > 0 then
        local heal = math.floor(p.maxHp * p.prayerHealPct / 100)
        heal = math.max(1, heal)
        local actualHeal = math.min(heal, p.maxHp - p.hp)
        p.hp = p.hp + actualHeal
        M.addDamageText(p.x, p.y, "+" .. heal, {255, 220, 100})
        M.addDivineGraceEffect(p.x, p.y)
        M.triggerRadianceDamage(heal)
    end

    -- HP/MP 自然恢复（采集区无怪物时跳过，改由 main.lua 实时回复）
    local skipTurnRegen = false
    local curStageRegen = GS.STAGE_DEFS[GS.currentStage]
    if curStageRegen and curStageRegen.noRespawn then
        local hasEnemy = false
        for _, m in ipairs(GS.monsters) do
            if m.hp > 0 then hasEnemy = true; break end
        end
        if not hasEnemy then skipTurnRegen = true end
    end
    if not skipTurnRegen and p and p.hp > 0 then
        local hpRegen = p.hpRegen or 0
        local mpRegen = p.mpRegen or 0
        -- 圣泉祝福加成已在 recalcStats 中计算到 hpRegen/mpRegen，此处不再重复
        -- 治疗效果加成（仅影响HP回复）
        if (p.healEffectPct or 0) > 0 then
            hpRegen = hpRegen * (1 + p.healEffectPct / 100)
        end
        local hpHealed = 0
        local mpHealed = 0

        if hpRegen > 0 then
            local actualHpHeal = math.min(hpRegen, p.maxHp - p.hp)
            p.hp = p.hp + actualHpHeal
            -- 显示计算的恢复量（非实际恢复量），取整显示
            hpHealed = math.floor(hpRegen * 10 + 0.5) / 10
            -- 触发辉光（深渊词缀 + 英雄钉锤，过量治疗也计算）
            M.triggerRadianceDamage(hpRegen)
        end
        if mpRegen > 0 and p.mp and p.maxMp and p.mp < p.maxMp then
            mpHealed = math.min(mpRegen, p.maxMp - p.mp)
            p.mp = p.mp + mpHealed
            mpHealed = math.floor(mpHealed * 10 + 0.5) / 10
        end

        -- HP流失：每回合损失HP（不会致死，最低保留1HP）
        local hpDrain = p.hpDrain or 0
        local hpDrained = 0
        if hpDrain > 0 and p.hp > 1 then
            hpDrained = math.min(hpDrain, p.hp - 1)
            p.hp = p.hp - hpDrained
            hpDrained = math.floor(hpDrained * 10 + 0.5) / 10
        end

        -- 飘字动画（绿色HP，蓝色MP，红色HP流失，上下错开）
        -- 暂时不显示HP/MP自然回复数字
        -- if hpHealed > 0 then
        --     M.addDamageText(p.x, p.y, "+" .. string.format("%.1f", hpHealed), {80, 230, 80})
        -- end
        if hpDrained > 0 then
            M.addDamageText(p.x, p.y, "-" .. string.format("%.1f", hpDrained), {255, 100, 100})
        end
        -- if mpHealed > 0 then
        --     M.addDamageText(p.x, p.y - 0.4, "+" .. string.format("%.1f", mpHealed), {80, 160, 255})
        -- end
    end

    -- 逃散中：跳过刷怪和召唤
    local monstersAreFleeing = false
    for _, m in ipairs(GS.monsters) do
        if m.fleeing and m.hp > 0 then monstersAreFleeing = true; break end
    end

    -- 副本 / 普通关卡 分支处理
    if monstersAreFleeing then
        -- 逃散期间不刷怪、不召唤
    elseif GS.isDungeon then
        -- 副本：阶段完成检查 + 阶段刷怪
        local phaseChanged = DungeonManager.checkPhaseComplete()
        if phaseChanged and GS.arenaTransition then
            -- 竞技场过场：跳过滚动和刷怪，由过场状态机控制
            -- （不做任何事，过场在 main.lua 的 updateArenaTransition 中驱动）
        elseif phaseChanged and DungeonManager.getPhase() and GS.player and GS.player.hp > 0 then
            -- 过关且还有下一阶段：棋盘内容向下滑动
            local targetY = GS.BOARD_SIZE
            local deltaY = targetY - GS.player.y
            if deltaY > 0 then
                GS.dungeonScrollAnim = {
                    targetX = GS.player.x,
                    targetY = targetY,
                    totalOffset = deltaY * GS.CELL, -- 正值=内容向下滑
                    timer = 0,
                    duration = 0.6,
                }
            end
        end
        if DungeonManager.isActive() and not GS.dungeonScrollAnim and not GS.arenaTransition then
            DungeonManager.spawnForPhase()
        end
    else
        -- 普通关卡刷怪已移至 endPlayerTurn 末尾，让新怪当回合即可行动
    end

    -- 竞技场过场中：阻止后续逻辑，保持 STATE_ENEMY 状态让过场状态机驱动
    if GS.arenaTransition then
        return
    end

    -- 史莱姆王被动：每N回合召唤随机精英史莱姆（逃散期间跳过）
    if not monstersAreFleeing then for _, m in ipairs(GS.monsters) do
        if m.hp > 0 and m.summonEliteInterval and m.summonEliteInterval > 0
           and GS.turnNumber > 1 then
            -- 暴怒关卡：根据暴怒层数调整召唤间隔和数量
            local summonInterval = m.summonEliteInterval
            local summonCount = 1
            if GS.currentStage == GS.STAGE_SLIME_KING_REVENGE then
                local rl = GS.slimeRevengeRageLayer or 0
                if rl >= 11 then
                    summonInterval = 1      -- 层11+: 每回合
                elseif rl >= 6 then
                    summonInterval = 2      -- 层6-10: 每2回合
                else
                    summonInterval = 3      -- 层0-5: 每3回合
                end
                if rl >= 21 then
                    summonCount = 3         -- 层21+: 每次3只
                elseif rl >= 16 then
                    summonCount = 2         -- 层16-20: 每次2只
                else
                    summonCount = 1         -- 层0-15: 每次1只
                end
            end
            if GS.turnNumber % summonInterval == 0 then
                -- 随机选择精英类型（大反击关卡使用暴怒版本）
                local eliteTypes
                if GS.currentStage == GS.STAGE_SLIME_KING_REVENGE then
                    eliteTypes = { "fire_slime_enraged", "ice_slime_enraged", "elec_slime_enraged" }
                else
                    eliteTypes = { "fire_slime_elite", "ice_slime_elite", "elec_slime_elite" }
                end
                local summoned = 0
                for sc = 1, summonCount do
                    local eliteKey = eliteTypes[math.random(#eliteTypes)]
                    local eDef = GS.MONSTER_DB[eliteKey]
                    if eDef then
                        -- 每次召唤重新收集边缘空位（前一只已占位）
                        local edgeCells = {}
                        for i = 1, GS.BOARD_SIZE do
                            if GS.isCellEmpty(i, 1) then edgeCells[#edgeCells + 1] = {i, 1} end
                            if GS.isCellEmpty(i, GS.BOARD_SIZE) then edgeCells[#edgeCells + 1] = {i, GS.BOARD_SIZE} end
                            if GS.isCellEmpty(1, i) then edgeCells[#edgeCells + 1] = {1, i} end
                            if GS.isCellEmpty(GS.BOARD_SIZE, i) then edgeCells[#edgeCells + 1] = {GS.BOARD_SIZE, i} end
                        end
                        if #edgeCells == 0 then break end  -- 没有空位了
                        local pos = edgeCells[math.random(#edgeCells)]
                        local elite = {
                            x = pos[1], y = pos[2],
                            defId = eDef.id,
                            name = eDef.name .. " Lv." .. eDef.level,
                            level = eDef.level or 1,
                            hp = eDef.hp, maxHp = eDef.maxHp or eDef.hp,
                            atk = eDef.atk, mAtk = eDef.mAtk, def = eDef.def, mdef = eDef.mdef or eDef.def,
                            critVal = eDef.critVal or 0, critDmg = eDef.critDmg or 50,
                            hit = eDef.hit or 0, dodge = eDef.dodge or 0,
                            atkSpeed = eDef.atkSpeed or 1,
                            moveRange = eDef.moveRange, atkRange = eDef.atkRange,
                            color = {eDef.color[1], eDef.color[2], eDef.color[3]},
                            expReward = eDef.expReward or 0,
                            rarity = eDef.rarity, image = eDef.image,
                            drops = eDef.drops, ai = eDef.ai,
                            eliteType = eDef.eliteType,
                            atkAttr = eDef.atkAttr,
                            element = eDef.element,
                            resistance = eDef.resistance,
                            weakness = eDef.weakness,
                            isMonster = true, acted = false,
                            facing = GS.facingToCenter(pos[1], pos[2]),
                        }
                        elite.defId = eliteKey  -- MonsterDB 无显式 id 字段，用 key 作为 defId
                        table.insert(GS.monsters, elite)
                        -- 暴怒关卡：新召唤的小怪继承当前暴怒层数
                        local rageLayer = GS.slimeRevengeRageLayer or 0
                        if rageLayer > 0 and M._applyRageBuff then
                            M._applyRageBuff(elite, rageLayer)
                        end
                        M.addDamageText(pos[1], pos[2], eDef.name, {eDef.color[1], eDef.color[2], eDef.color[3]})
                        print("史莱姆王召唤了 " .. eDef.name .. " 于 (" .. pos[1] .. "," .. pos[2] .. ")")
                        summoned = summoned + 1
                    end
                end
                if summoned > 0 then
                    local kcx, kcy = GS.unitCenterPos(m)
                    if summonCount > 1 then
                        M.addDamageText(kcx, kcy - 0.5, "召唤精锐x" .. summoned .. "!", {220, 180, 60})
                    else
                        M.addDamageText(kcx, kcy - 0.5, "召唤精锐!", {220, 180, 60})
                    end
                end
            end
            break -- 每回合只由一个史莱姆王召唤
        end
    end end -- if not monstersAreFleeing

    -- 先知夸迪被动：引雷/落雷交替
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 and m.defId == "tidal_boss_kuadi" then
            local phase = m._lightningPhase or "warn"
            if phase == "warn" then
                -- 引雷阶段：随机标记20个棋盘格子
                GS.lightningWarnings = {}
                local cells = {}
                for cx = 1, GS.BOARD_SIZE do
                    for cy = 1, GS.BOARD_SIZE do
                        cells[#cells + 1] = { x = cx, y = cy }
                    end
                end
                -- Fisher-Yates 洗牌取前20个
                local count = math.min(20, #cells)
                for i = #cells, 2, -1 do
                    local j = math.random(1, i)
                    cells[i], cells[j] = cells[j], cells[i]
                end
                for i = 1, count do
                    GS.lightningWarnings[#GS.lightningWarnings + 1] = cells[i]
                end
                m.floatingText = { text = "引雷!", duration = 2.0, fadeStart = 1.2, timer = 0 }
                local kcx, kcy = GS.unitCenterPos(m)
                M.addDamageText(kcx, kcy - 0.5, "引雷!", {255, 220, 60})
                m._lightningPhase = "strike"
                print("[夸迪] 引雷标记 " .. count .. " 个格子")
            else
                -- 落雷阶段：对标记格子及十字区域上的非怪物单位造成魔法伤害
                local warnings = GS.lightningWarnings
                if #warnings > 0 then
                    m.floatingText = { text = "落雷!", duration = 2.0, fadeStart = 1.2, timer = 0 }
                    local kcx, kcy = GS.unitCenterPos(m)
                    M.addDamageText(kcx, kcy - 0.5, "落雷!", {255, 220, 60})
                    -- 收集所有受击格子（十字区域：中心+上下左右），去重
                    local hitCells = {}
                    local hitSet = {}
                    local crossDirs = {{0,0},{0,-1},{0,1},{-1,0},{1,0}}
                    for _, w in ipairs(warnings) do
                        for _, cd in ipairs(crossDirs) do
                            local cx, cy = w.x + cd[1], w.y + cd[2]
                            if GS.isInBoard(cx, cy) then
                                local key = cx .. "," .. cy
                                if not hitSet[key] then
                                    hitSet[key] = true
                                    hitCells[#hitCells + 1] = { x = cx, y = cy }
                                end
                            end
                        end
                        -- 落雷特效（仅在引雷标记点播放）
                        M.addThunderStrikeEffect(w.x, w.y)
                    end
                    -- 对所有受击格子上的非怪物单位造成伤害
                    local hitTargets = {} -- 防止同一单位被多个格子重复伤害
                    for _, cell in ipairs(hitCells) do
                        -- 玩家
                        if GS.player and GS.player.hp > 0
                           and GS.player.x == cell.x and GS.player.y == cell.y
                           and not hitTargets[GS.player] then
                            hitTargets[GS.player] = true
                        end
                        -- 猎犬/友军
                        for _, c in ipairs(GS.companions) do
                            if c.hp > 0 and c.x == cell.x and c.y == cell.y
                               and not hitTargets[c] then
                                hitTargets[c] = true
                            end
                        end
                    end
                    for target, _ in pairs(hitTargets) do
                        local atkVal = 1380
                        local defVal = target.mdef or target.def or 0
                        local ldmg = math.floor(atkVal * atkVal / (atkVal + defVal))
                        if ldmg < 1 then ldmg = 1 end
                        target.hp = target.hp - ldmg
                        if target.hp < 0 then target.hp = 0 end
                        M.addDamageText(target.x, target.y, "" .. ldmg, {255, 220, 60})
                        print("[夸迪] 落雷命中 " .. (target.name or "玩家") .. " 伤害 " .. ldmg)
                    end
                    GS.lightningWarnings = {}
                    -- 落雷后检查玩家是否死亡
                    if M.checkPlayerDeath() then return end
                end
                m._lightningPhase = "warn"
            end
            break -- 只处理一个夸迪
        end
    end

    -- 元素流转buff递减
    if (GS._eleFlowTurns or 0) > 0 then
        GS._eleFlowTurns = GS._eleFlowTurns - 1
        if GS._eleFlowTurns <= 0 then
            GS._eleFlowLastElem = nil
            GS._eleFlowTurns = nil
        end
    end

    -- 风暴buff递减 + 回合开始触发
    if GS.stormBuffTurns > 0 then
        GS.stormBuffTurns = GS.stormBuffTurns - 1
        if GS.stormBuffTurns > 0 and GS.player and GS.player.hp > 0 then
            local startN = GS.stormStartCount or 1
            if startN == 1 then
                M.triggerStormWhirlwind(GS.player)
            elseif startN > 1 then
                -- 多次旋风斩入队，通过延迟间隔展示
                for i = 1, startN do
                    table.insert(M.chainQueue, {
                        action = function() M.triggerStormWhirlwind(GS.player) end,
                    })
                end
                M.chainActive = true
                M.chainTimer = 0  -- 第一次立即执行
            end
        end
    end

    -- 静神buff递减
    if GS.focusBuffTurns > 0 then
        GS.focusBuffTurns = GS.focusBuffTurns - 1
        GS.recalcStats(GS.player)  -- 刷新 dmgPctBonus（含静神加成或移除）
        if GS.focusBuffTurns <= 0 then
        end
    end

    -- 火焰护盾递减
    if GS.fireShieldTurns > 0 then
        GS.fireShieldTurns = GS.fireShieldTurns - 1
        if GS.fireShieldTurns <= 0 then
            GS.fireShieldReducePct = 0
            GS.fireShieldReflectPct = 0
        end
    end

    -- 备用武器暴击伤害BUFF递减
    if GS.player and (GS.player._spareWeaponCritTurns or 0) > 0 then
        GS.player._spareWeaponCritTurns = GS.player._spareWeaponCritTurns - 1
        if GS.player._spareWeaponCritTurns <= 0 then
            GS.player._spareWeaponCritDmg = nil
            GS.player._spareWeaponCritTurns = nil
        end
    end

    -- 隐匿持续回合递减
    if GS.stealthActive and GS.stealthTurns > 0 then
        GS.stealthTurns = GS.stealthTurns - 1
        if GS.stealthTurns <= 0 then
            GS.stealthActive = false
            GS.stealthTurns = 0
        end
    end

    -- 消耗品公共CD递减
    if GS.consumableCooldown > 0 then
        GS.consumableCooldown = GS.consumableCooldown - 1
    end

    -- 处理敌人回合中排队的消耗品
    if #GS.pendingConsumableSlots > 0 then
        for _, slotIdx in ipairs(GS.pendingConsumableSlots) do
            local item = GS.inventory[slotIdx]
            if item and item.consumable then
                local itemName = item.name or "消耗品"
                local ok, msg = GS.useConsumable(slotIdx)
                if ok and GS.player then
                    M.addDamageText(GS.player.x, GS.player.y, "使用:" .. itemName, {80, 230, 180})
                end
            end
        end
        GS.pendingConsumableSlots = {}
    end

    -- 吟唱系统：施法职业回合开始获得吟唱段数（一次性立即完成）
    if (GS.currentClass == "mage" or GS.currentClass == "priest") and GS.player and GS.player.hp > 0 then
        local gained = GS.rollChantStages()
        if GS._chantPendingReset then
            -- 上回合结束标记了清零，直接覆盖（避免视觉上先变0再变大）
            GS.chantStages = gained
            GS._chantPendingReset = nil
        else
            GS.chantStages = GS.chantStages + gained
        end
        GS.chantStagesMax = GS.chantStages  -- 记录本回合总段数（用于UI方块显示）

        -- 如果正在吟唱中，启动消耗动画（每0.7秒填充1段）
        if GS.chanting then
            local ch = GS.chanting
            local needed = ch.stagesNeeded - ch.stagesAccum
            local consume = math.min(needed, GS.chantStages)
            if consume > 0 then
                GS._chantConsumeAnim = {
                    total    = consume, -- 本回合要消耗的段数
                    consumed = 0,       -- 已消耗的段数
                    timer    = 0,       -- 计时器
                    interval = 0.7,     -- 每段间隔秒数
                }
                GS._chantGainBlocking = true
                GS.gameState = GS.STATE_PLAYER
                return  -- 后续逻辑由 processChantConsumeAnim 完成
            end
            -- consume == 0 的情况：没有段数可消耗，直接结束回合
            GS.player.acted = true
            M.endPlayerTurn()
            return
        end
    end

    GS.gameState = GS.STATE_PLAYER
    GS.turnPhase = GS.PHASE_PRE
    GS.advanceTurnPhase()  -- PRE → MOVE
    print("[TIMING] 8-startPlayerTurn done, STATE_PLAYER @ " .. tostring(os.clock()))
    print("=== 关卡 " .. GS.currentStage .. " 回合 " .. GS.turnNumber .. " 玩家回合 [" .. GS.turnPhase .. "] ===")
end

-- ====================================================================
-- 吟唱消耗动画：每0.7秒从吟唱段数中消耗1段填充到法术
-- ====================================================================
function M.processChantConsumeAnim(dt)
    local anim = GS._chantConsumeAnim
    if not anim then return false end

    anim.timer = anim.timer + dt
    if anim.timer >= anim.interval then
        anim.timer = anim.timer - anim.interval
        anim.consumed = anim.consumed + 1
        -- 从可用段数扣除1段，填充到法术
        GS.chantStages = math.max(0, (GS.chantStages or 0) - 1)
        local ch = GS.chanting
        if ch then
            ch.stagesAccum = ch.stagesAccum + 1
        end

        if anim.consumed >= anim.total then
            -- 本回合消耗完毕，结束动画
            GS._chantConsumeAnim = nil
            GS._chantGainBlocking = nil
            M.finishChantConsume()
            return true
        end
    end
    return true  -- 动画仍在进行，阻塞其他操作
end

--- 消耗动画完成后：检查吟唱是否完成，执行释放或继续等待
function M.finishChantConsume()
    local ch = GS.chanting
    if not ch then return end

    if ch.stagesAccum >= ch.stagesNeeded then
        -- 吟唱完成！释放法术
        -- 深度思维：吟唱完成后消耗剩余段数转化为增伤
        GS.consumeRemainingChantForDeepThink()
        local skillId = ch.skillId
        local def = GS.SKILL_DEFS[skillId]
        if def then
            -- 吟唱开始时已调用过 useSkill（消耗MP+设CD），跳过技能内部的重复调用
            GS._skipUseSkill = true
            if ch.castType == "self" then
                M.executePlayerAttack(GS.player, GS.player, skillId)
            elseif ch.castType == "selfTarget" then
                local target = ch.target
                if not target or (target.hp and target.hp <= 0) or (target.hitsLeft and target.hitsLeft <= 0) then
                    target = GS.player
                end
                M.executePlayerAttack(GS.player, target, skillId)
            elseif ch.castType == "aoe" then
                M.performAOE(GS.player, skillId)
                M.removeDeadMonsters()
            elseif ch.castType == "ground" then
                M.executeGroundSkill(GS.player, skillId, ch.tx, ch.ty)
                M.removeDeadMonsters()
            elseif ch.castType == "icewall" then
                M.placeIceWalls(GS.player, skillId, ch.wallCells or {})
            elseif ch.castType == "single" then
                local target = ch.target
                if target and target.hp and target.hp > 0 then
                    M.executePlayerAttack(GS.player, target, skillId)
                    M.removeDeadMonsters()
                else
                    M.addDamageText(GS.player.x, GS.player.y, "目标已消失", {200, 200, 200})
                end
            end
            GS._skipUseSkill = nil
        end
        GS.chanting = nil
        if M.checkPlayerDeath() then return end
        GS.player.acted = true
        M.endPlayerTurn()
    else
        -- 吟唱未完成，继续等待，跳过本回合行动
        GS.player.acted = true
        M.endPlayerTurn()
    end
end

-- ====================================================================
-- 敌人移动规划（所有敌人同时）
-- ====================================================================
-- 辅助：标记/取消单位占据的所有格子到 claimed 表
local function claimUnit(claimed, unit, value)
    local s = GS.unitSize(unit)
    for dy = 0, s - 1 do
        for dx = 0, s - 1 do
            claimed[GS.cellKey(unit.x + dx, unit.y + dy)] = value
        end
    end
end

-- 辅助：检查锚点 (x,y) 处 sxs 区域是否全部未被 claimed
local function isAreaUnclaimed(claimed, x, y, s)
    for dy = 0, s - 1 do
        for dx = 0, s - 1 do
            if claimed[GS.cellKey(x + dx, y + dy)] then return false end
        end
    end
    return true
end

-- ====================================================================
-- 暴怒史莱姆王踩踏（移动后摧毁目的地的杂兵和圣树）
-- ====================================================================

--- 暴怒史莱姆王移动到目的地后，摧毁其占据格子上的杂兵怪物和圣树
--- 火史莱姆被踩踏时触发自爆逻辑（创建火尸体，延迟1回合后爆炸）
function M.enragedKingTrample(king)
    local ms = GS.unitSize(king)
    local trampled = {}

    for dy = 0, ms - 1 do
        for dx = 0, ms - 1 do
            local cx, cy = king.x + dx, king.y + dy

            -- 踩踏杂兵怪物
            for _, m in ipairs(GS.monsters) do
                if m ~= king and m.hp > 0 and not trampled[m] then
                    local s = m.size or 1
                    for my = m.y, m.y + s - 1 do
                        for mx = m.x, m.x + s - 1 do
                            if mx == cx and my == cy then
                                trampled[m] = true
                                m.hp = 0
                                local mcx, mcy = GS.unitCenterPos(m)
                                M.addDamageText(mcx, mcy, "踩踏!", {255, 140, 30})
                                M.addHurtFlash(m)
                                -- 火史莱姆：触发自爆逻辑
                                if (m.eliteType == "fire" or m.defId == "fire_slime_enraged")
                                   and not m._fireCorpseCreated then
                                    m._fireCorpseCreated = true
                                    table.insert(GS.fireCorpses, {
                                        x = m.x, y = m.y,
                                        turns = 2,  -- 延迟1回合后爆炸（与正常击杀一致，给玩家躲避时间）
                                        realTimer = 0,
                                        image = m.image,
                                        color = {220, 80, 40},
                                        name = m.name,
                                        level = m.level or 45,
                                        defId = m.defId,
                                    })
                                    M.addDamageText(m.x, m.y - 0.5, "即将爆炸!", {255, 120, 40})
                                end
                                M.processMonsterKill(GS.player, m)
                            end
                        end
                        if trampled[m] then break end
                    end
                end
            end

            -- 踩踏圣树
            for i = #GS.holyTrees, 1, -1 do
                local t = GS.holyTrees[i]
                if t.x == cx and t.y == cy then
                    M.addDamageText(t.x, t.y, "踩踏摧毁!", {255, 140, 30})
                    table.remove(GS.holyTrees, i)
                end
            end

            -- 踩踏冰墙
            for i = #GS.iceWalls, 1, -1 do
                local w = GS.iceWalls[i]
                if w.x == cx and w.y == cy then
                    M.addDamageText(w.x, w.y, "踩踏摧毁!", {80, 180, 255})
                    table.remove(GS.iceWalls, i)
                end
            end


        end
    end
end

-- ====================================================================
-- 敌人目标选择（后续可扩展为仇恨系统）
-- ====================================================================

--- 获取所有友方单位（玩家+友军），hp > 0
---@return table[]
function M.getAllPlayerAllies()
    local allies = {}
    if GS.player and GS.player.hp > 0 then
        allies[#allies + 1] = GS.player
    end
    for _, c in ipairs(GS.companions) do
        if c.hp > 0 then
            allies[#allies + 1] = c
        end
    end
    -- 圣树不可被攻击（无敌）
    -- 冰墙也作为可被攻击的友方目标
    for _, w in ipairs(GS.iceWalls) do
        if w.hitsLeft > 0 then
            allies[#allies + 1] = w
        end
    end
    return allies
end

--- 为敌方单位 m 选择攻击目标
--- 规则：距离最近 → 同距离取生命百分比最低
--- @param m table 敌方单位
--- @param allies table[]|nil 友方列表（可选，默认 getAllPlayerAllies()）
--- @return table|nil target, number dist
function M.pickEnemyTarget(m, allies)
    allies = allies or M.getAllPlayerAllies()
    local best = nil
    local bestDist = 9999
    local bestHpPct = 2.0
    for _, a in ipairs(allies) do
        local d = GS.manhattanToUnit(a.x, a.y, m)
        local hpPct = a.hp / math.max(a.maxHp, 1)
        if d < bestDist or (d == bestDist and hpPct < bestHpPct) then
            bestDist = d
            bestHpPct = hpPct
            best = a
        end
    end
    return best, bestDist
end

--- 隐匿状态：所有怪物随机移动，不攻击
function M.planEnemyRandomMoves()
    local claimed = {}
    claimed[GS.cellKey(GS.player.x, GS.player.y)] = true
    for _, c in ipairs(GS.companions) do
        if c.hp > 0 then claimed[GS.cellKey(c.x, c.y)] = true end
    end
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 then claimUnit(claimed, m, true) end
    end
    for _, m in ipairs(GS.monsters) do
        if m.hp <= 0 then goto continue end
        m.acted = true
        m.plannedTarget = nil
        m.plannedHeal = nil
        local ms = GS.unitSize(m)
        if m.stunned and m.stunned > 0 then goto continue end
        if m.frozen and m.frozen > 0 then goto continue end  -- 冰冻也不能移动
        claimUnit(claimed, m, nil)
        local movable, mParents = GS.getMovableCellsForMonster(m)
        -- 收集可移动到的位置，随机选一个
        local candidates = {}
        for key, _ in pairs(movable) do
            local cy = math.floor(key / 100)
            local cx = key - cy * 100
            if isAreaUnclaimed(claimed, cx, cy, ms) then
                candidates[#candidates + 1] = {cx, cy}
            end
        end
        if #candidates > 0 then
            local pick = candidates[math.random(1, #candidates)]
            local oldX, oldY = m.x, m.y
            local path = GS.reconstructPath(mParents, oldX, oldY, pick[1], pick[2])
            m.x = pick[1]
            m.y = pick[2]
            claimUnit(claimed, m, true)
            M.startMoveAnim(m, oldX, oldY, path)
        else
            claimUnit(claimed, m, true)
        end
        ::continue::
    end
end

function M.planAllEnemyMoves()
    if not GS.player or GS.player.hp <= 0 then return end

    local allies = M.getAllPlayerAllies()
    -- 隐匿状态：从敌人目标列表中移除玩家
    if GS.stealthActive then
        local filtered = {}
        for _, a in ipairs(allies) do
            if a ~= GS.player then filtered[#filtered + 1] = a end
        end
        allies = filtered
    end
    if #allies == 0 then
        -- 全部目标不可见（隐匿且无同伴），怪物随机移动
        M.planEnemyRandomMoves()
        return
    end

    local claimed = {}
    claimed[GS.cellKey(GS.player.x, GS.player.y)] = true
    for _, c in ipairs(GS.companions) do
        if c.hp > 0 then
            claimed[GS.cellKey(c.x, c.y)] = true
        end
    end

    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 then
            claimUnit(claimed, m, true)
        end
    end

    for _, m in ipairs(GS.monsters) do
        if m.hp <= 0 then goto continue end
        m.acted = true
        m.plannedTarget = nil
        m.plannedHeal = nil
        local ms = GS.unitSize(m)

        -- 新刷怪物首回合：移动距离固定1，攻击距离固定2，之后恢复正常
        if m.justSpawned then
            m._origMoveRange = m.moveRange
            m._origAtkRange  = m.atkRange
            m.moveRange = 1
            m.atkRange  = math.min(2, m._origAtkRange)  -- 不超过原始值（避免给近战怪增加射程）
            m.justSpawned = nil
            m._restoreRangeAfterTurn = true
        end

        -- 英雄单位：兜底清除控制效果（Combat_AOE 施加时可能遗漏检查）
        if M._isHeroUnit(m) then
            m.stunned = nil
            m.frozen  = nil
            m.feared  = nil
        end

        -- 晕眩的怪物跳过行动
        if m.stunned and m.stunned > 0 then
            goto continue
        end

        -- 冰冻：不能移动，但可以攻击范围内的目标
        if m.frozen and m.frozen > 0 then
            local target, dist = M.pickEnemyTarget(m, allies)
            if target and dist <= m.atkRange then
                m.plannedTarget = target
            end
            goto continue
        end

        -- 恐惧：远离猎犬逃跑，不攻击
        if m.feared and m.feared > 0 then
            claimUnit(claimed, m, nil)
            local movable, mParents = GS.getMovableCellsForMonster(m)
            -- 找到最近的猎犬作为恐惧源
            local fearSrcX, fearSrcY = GS.player.x, GS.player.y
            for _, c in ipairs(GS.companions) do
                if c.isHound and c.hp > 0 then
                    fearSrcX, fearSrcY = c.x, c.y
                    break
                end
            end
            local bestX, bestY = m.x, m.y
            local bestDist = math.abs(m.x - fearSrcX) + math.abs(m.y - fearSrcY)
            for key, _ in pairs(movable) do
                local cy = math.floor(key / 100)
                local cx = key - cy * 100
                if isAreaUnclaimed(claimed, cx, cy, ms) then
                    local d = math.abs(cx - fearSrcX) + math.abs(cy - fearSrcY)
                    if d > bestDist then
                        bestDist = d
                        bestX = cx
                        bestY = cy
                    end
                end
            end
            local oldX, oldY = m.x, m.y
            local path = GS.reconstructPath(mParents, oldX, oldY, bestX, bestY)
            m.x = bestX
            m.y = bestY
            claimUnit(claimed, m, true)
            M.startMoveAnim(m, oldX, oldY, path)
            goto continue
        end

        -- 鸟兽散：向最近的棋盘边缘逃跑，不攻击
        if m.fleeing then
            claimUnit(claimed, m, nil)
            local movable, mParents = GS.getMovableCellsForMonster(m)
            local bestX, bestY = m.x, m.y
            local bestEdgeDist = math.min(m.x - 1, GS.BOARD_SIZE - m.x, m.y - 1, GS.BOARD_SIZE - m.y)
            for key, _ in pairs(movable) do
                local cy = math.floor(key / 100)
                local cx = key - cy * 100
                if isAreaUnclaimed(claimed, cx, cy, ms) then
                    local edgeDist = math.min(cx - 1, GS.BOARD_SIZE - cx, cy - 1, GS.BOARD_SIZE - cy)
                    if edgeDist < bestEdgeDist then
                        bestEdgeDist = edgeDist
                        bestX = cx
                        bestY = cy
                    end
                end
            end
            local oldX, oldY = m.x, m.y
            local path = GS.reconstructPath(mParents, oldX, oldY, bestX, bestY)
            m.x = bestX
            m.y = bestY
            claimUnit(claimed, m, true)
            M.startMoveAnim(m, oldX, oldY, path)
            goto continue
        end

        -- 史莱姆王子特殊 AI：公主存活时优先治疗公主
        if m.image == "image/monster_slime_prince.png" then
            local princess = nil
            for _, other in ipairs(GS.monsters) do
                if other.hp > 0 and other.image == "image/monster_slime_princess.png" then
                    princess = other
                    break
                end
            end
            if princess then
                local distToPrincess = GS.manhattanToUnit(m.x, m.y, princess)
                if distToPrincess <= 3 then
                    -- 在施法范围内，直接治疗，不移动
                    m.plannedHeal = princess
                    goto continue
                else
                    -- 不在范围内，向公主移动
                    claimUnit(claimed, m, nil)
                    local movable, mParents = GS.getMovableCellsForMonster(m)
                    local bestX, bestY = m.x, m.y
                    local bestDist = distToPrincess
                    for key, _ in pairs(movable) do
                        local cy = math.floor(key / 100)
                        local cx = key - cy * 100
                        if isAreaUnclaimed(claimed, cx, cy, ms) then
                            local d = GS.manhattanToUnit(cx, cy, princess)
                            if d < bestDist then
                                bestDist = d
                                bestX = cx
                                bestY = cy
                            end
                        end
                    end
                    local oldX, oldY = m.x, m.y
                    local path = GS.reconstructPath(mParents, oldX, oldY, bestX, bestY)
                    m.x = bestX
                    m.y = bestY
                    claimUnit(claimed, m, true)
                    M.startMoveAnim(m, oldX, oldY, path)
                    if GS.manhattanToUnit(m.x, m.y, princess) <= 3 then
                        m.plannedHeal = princess
                    end
                    goto continue
                end
            end
            -- 公主已死，王子按正常 AI 行动（继续往下走）
        end

        -- 逃跑型 AI：远离玩家，不攻击
        if m.ai == "flee" then
            local movable, mParents = GS.getMovableCellsForMonster(m)
            claimUnit(claimed, m, nil)
            local bestX, bestY = m.x, m.y
            local bestDist = GS.manhattan(m.x, m.y, GS.player.x, GS.player.y)
            for key, _ in pairs(movable) do
                local cy = math.floor(key / 100)
                local cx = key - cy * 100
                if isAreaUnclaimed(claimed, cx, cy, ms) then
                    local d = GS.manhattan(cx, cy, GS.player.x, GS.player.y)
                    if d > bestDist then
                        bestDist = d
                        bestX = cx
                        bestY = cy
                    end
                end
            end
            local oldX, oldY = m.x, m.y
            local path = GS.reconstructPath(mParents, oldX, oldY, bestX, bestY)
            m.x = bestX
            m.y = bestY
            claimUnit(claimed, m, true)
            M.startMoveAnim(m, oldX, oldY, path)
            goto continue
        end

        -- 背刺 AI（迪呜）：优先移动到目标背后 > 侧面 > 正面（即使已在攻击范围内也尝试绕位）
        if m.ai == "flank" then
            local target, dist = M.pickEnemyTarget(m, allies)
            if not target then goto continue end

            claimUnit(claimed, m, nil)
            local movable, mParents = GS.getMovableCellsForMonster(m)

            --- 内联方向判定：返回 0=正面, 1=侧面, 2=背后
            local function getDirScore(cx, cy, tgt)
                local facing = tgt.facing
                if not facing then return 0 end
                local dx = cx - tgt.x
                local dy = cy - tgt.y
                if dx == 0 and dy == 0 then return 0 end
                local atkDir
                if math.abs(dx) >= math.abs(dy) then
                    atkDir = dx > 0 and "right" or "left"
                else
                    atkDir = dy > 0 and "down" or "up"
                end
                if math.abs(dx) == math.abs(dy) then
                    local frontHalf = false
                    if facing == "down"  and dy > 0 then frontHalf = true
                    elseif facing == "up"    and dy < 0 then frontHalf = true
                    elseif facing == "left"  and dx < 0 then frontHalf = true
                    elseif facing == "right" and dx > 0 then frontHalf = true
                    end
                    if frontHalf then return 0 end
                end
                local backMap = { up = "down", down = "up", left = "right", right = "left" }
                if atkDir == backMap[facing] then return 2 end
                if atkDir == facing then return 0 end
                return 1
            end

            local bestX, bestY = m.x, m.y
            local bestDist = dist
            local bestCanAtk = (dist <= m.atkRange)
            local bestDir = bestCanAtk and getDirScore(m.x, m.y, target) or -1

            for key, _ in pairs(movable) do
                local cy = math.floor(key / 100)
                local cx = key - cy * 100
                if isAreaUnclaimed(claimed, cx, cy, ms) then
                    local d = GS.manhattanToUnit(target.x, target.y, {x = cx, y = cy, size = ms})
                    local canAtk = (d <= m.atkRange)
                    local dirScore = canAtk and getDirScore(cx, cy, target) or -1

                    -- 优先级：能攻击 > 不能攻击; 能攻击时方向分高优先; 同分距离近优先
                    if canAtk and not bestCanAtk then
                        bestCanAtk = true
                        bestDir = dirScore
                        bestDist = d
                        bestX, bestY = cx, cy
                    elseif canAtk and bestCanAtk then
                        if dirScore > bestDir then
                            bestDir = dirScore
                            bestDist = d
                            bestX, bestY = cx, cy
                        elseif dirScore == bestDir and d < bestDist then
                            bestDist = d
                            bestX, bestY = cx, cy
                        end
                    elseif not canAtk and not bestCanAtk then
                        if d < bestDist then
                            bestDist = d
                            bestX, bestY = cx, cy
                        end
                    end
                end
            end

            local oldX, oldY = m.x, m.y
            local path = GS.reconstructPath(mParents, oldX, oldY, bestX, bestY)
            m.x = bestX
            m.y = bestY
            claimUnit(claimed, m, true)
            M.startMoveAnim(m, oldX, oldY, path)

            local finalTarget, finalDist = M.pickEnemyTarget(m, allies)
            if finalTarget and finalDist <= m.atkRange then
                m.plannedTarget = finalTarget
            end
            goto continue
        end

        -- ice_mage（迪拉）边缘闪现：到达棋盘边缘且周围2格有敌人时，闪现到对面半边（10回合CD）
        if m.ai == "ice_mage" then
            if not m._edgeBlinkCD then m._edgeBlinkCD = 0 end
            local BS = GS.BOARD_SIZE
            local atEdge = (m.x == 1 or m.x == BS or m.y == 1 or m.y == BS)
            if atEdge and m._edgeBlinkCD <= 0 then
                -- 检查周围2格内是否有敌方单位
                local nearbyEnemy = false
                for _, a in ipairs(allies) do
                    if a.hp > 0 and GS.manhattan(m.x, m.y, a.x, a.y) <= 2 then
                        nearbyEnemy = true
                        break
                    end
                end
                if nearbyEnemy then
                    -- 确定"对面半边"：基于当前位置选择对称半区
                    local midX = BS / 2  -- 6
                    local midY = BS / 2
                    local candidates = {}
                    for cy = 1, BS do
                        for cx = 1, BS do
                            -- 对面半边判定：主要按 x 轴划分，如果 x 在中间则按 y 轴
                            local isOpposite = false
                            if m.x <= midX and cx > midX then isOpposite = true
                            elseif m.x > midX and cx <= midX then isOpposite = true
                            elseif m.x > midX == (cx > midX) then
                                -- x 在同侧，按 y 判断
                                if m.y <= midY and cy > midY then isOpposite = true
                                elseif m.y > midY and cy <= midY then isOpposite = true
                                end
                            end
                            if isOpposite and GS.isInBoard(cx, cy) and GS.isCellEmpty(cx, cy)
                               and not claimed[GS.cellKey(cx, cy)] then
                                -- 确保目标格没有任何单位
                                local occupied = false
                                if GS.player and GS.player.hp > 0 and GS.player.x == cx and GS.player.y == cy then
                                    occupied = true
                                end
                                if not occupied then
                                    for _, c in ipairs(GS.companions) do
                                        if c.hp > 0 and c.x == cx and c.y == cy then
                                            occupied = true; break
                                        end
                                    end
                                end
                                if not occupied then
                                    for _, om in ipairs(GS.monsters) do
                                        if om ~= m and om.hp > 0 and om.x == cx and om.y == cy then
                                            occupied = true; break
                                        end
                                    end
                                end
                                if not occupied then
                                    candidates[#candidates + 1] = { x = cx, y = cy }
                                end
                            end
                        end
                    end
                    if #candidates > 0 then
                        local pick = candidates[math.random(#candidates)]
                        local oldX, oldY = m.x, m.y
                        claimUnit(claimed, m, nil)
                        m.x = pick.x
                        m.y = pick.y
                        claimUnit(claimed, m, true)
                        -- 添加闪现特效（与法师闪烁相同）
                        M.addBlinkEffect(oldX, oldY, pick.x, pick.y)
                        -- 隐藏怪物直到特效结束
                        m.blinkHidden = true
                        m._blinkTimer = 0
                        m._blinkDelay = 0.9 * 0.4  -- 与玩家闪现同步
                        m._edgeBlinkCD = 10  -- 进入10回合冷却
                        print("[AI] ice_mage 边缘闪现: (" .. oldX .. "," .. oldY .. ") → (" .. pick.x .. "," .. pick.y .. ")")
                        -- 闪现后只选目标攻击，不再移动
                        local blinkTarget, blinkDist = M.pickEnemyTarget(m, allies)
                        if blinkTarget and blinkDist <= m.atkRange then
                            m.plannedTarget = blinkTarget
                        end
                        goto continue
                    end
                end
            end
        end

        -- 守门人 AI：闪烁突袭优先，CD 时正常攻击
        if m.ai == "gatekeeper" then
            -- 初始化闪烁突袭 CD（0=可用）
            if not m._flashCD then m._flashCD = 0 end
            local flashRange = m.gatekeeperFlashRange or 3
            local flashCD = m.gatekeeperFlashCD or 2

            local target, dist = M.pickEnemyTarget(m, allies)
            if not target then goto continue end

            -- 闪烁突袭可用：距离在技能范围内时直接突袭，超出范围时先移动靠近再突袭
            if m._flashCD <= 0 then
                if dist <= flashRange then
                    -- 在闪烁突袭范围内：标记闪烁突袭
                    m._plannedFlashAssault = target
                    m._flashCD = flashCD  -- 进入冷却
                    goto continue
                else
                    -- 超出闪烁范围，移动靠近目标
                    claimUnit(claimed, m, nil)
                    local movable, mParents = GS.getMovableCellsForMonster(m)
                    local bestX, bestY = m.x, m.y
                    local bestDist = dist
                    for key, _ in pairs(movable) do
                        local cy = math.floor(key / 100)
                        local cx = key - cy * 100
                        if isAreaUnclaimed(claimed, cx, cy, ms) then
                            local d = GS.manhattanToUnit(cx, cy, target)
                            if d < bestDist then
                                bestDist = d
                                bestX = cx
                                bestY = cy
                            end
                        end
                    end
                    local oldX, oldY = m.x, m.y
                    local path = GS.reconstructPath(mParents, oldX, oldY, bestX, bestY)
                    m.x = bestX
                    m.y = bestY
                    claimUnit(claimed, m, true)
                    M.startMoveAnim(m, oldX, oldY, path)
                    -- 移动后如果在闪烁范围内则使用
                    local newDist = GS.manhattanToUnit(m.x, m.y, target)
                    if newDist <= flashRange then
                        m._plannedFlashAssault = target
                        m._flashCD = flashCD
                    elseif newDist <= m.atkRange then
                        m.plannedTarget = target
                    end
                    goto continue
                end
            else
                -- 闪烁突袭冷却中：正常移动+攻击
                if dist <= m.atkRange then
                    m.plannedTarget = target
                    goto continue
                end
                claimUnit(claimed, m, nil)
                local movable, mParents = GS.getMovableCellsForMonster(m)
                local bestX, bestY = m.x, m.y
                local bestDist = dist
                for key, _ in pairs(movable) do
                    local cy = math.floor(key / 100)
                    local cx = key - cy * 100
                    if isAreaUnclaimed(claimed, cx, cy, ms) then
                        local d = GS.manhattanToUnit(cx, cy, target)
                        if d < bestDist then
                            bestDist = d
                            bestX = cx
                            bestY = cy
                        end
                    end
                end
                local oldX, oldY = m.x, m.y
                local path = GS.reconstructPath(mParents, oldX, oldY, bestX, bestY)
                m.x = bestX
                m.y = bestY
                claimUnit(claimed, m, true)
                M.startMoveAnim(m, oldX, oldY, path)
                local finalTarget, finalDist = M.pickEnemyTarget(m, allies)
                if finalTarget and finalDist <= m.atkRange then
                    m.plannedTarget = finalTarget
                end
                goto continue
            end
        end

        -- 选择最优目标（距离最近 → 同距离血量百分比最低）
        -- 暴怒史莱姆王：只攻击玩家/分身/猎犬，不攻击冰墙和圣树
        local effectiveAllies = allies
        if m.defId == "slime_king_enraged" then
            effectiveAllies = {}
            for _, a in ipairs(allies) do
                if not a.isIceWall and not a.isHolyTree then
                    effectiveAllies[#effectiveAllies + 1] = a
                end
            end
        end
        local target, dist = M.pickEnemyTarget(m, effectiveAllies)
        if not target then goto continue end

        -- 深渊毒雾规避：即使已在攻击范围内，如果站在毒雾中也尝试移出
        local inFogAndAbyss = m.isAbyss and m.atkRange > 1 and GS.isPoisonFogTile(m.x, m.y)
        -- [DEBUG] 毒雾前置诊断（所有在攻击范围内的深渊怪物）
        if dist <= m.atkRange and m.isAbyss then
            local floorIdx = GS.getAbyssFloorIndex()
            local edgeDist = math.min(m.x - 1, GS.BOARD_SIZE - m.x, m.y - 1, GS.BOARD_SIZE - m.y)
            print(string.format("[FOG-DBG] %s@(%d,%d) isAbyss=%s floor=%s edgeDist=%d isFogTile=%s inFogAndAbyss=%s dist=%d atkRange=%d",
                m.name or m.defId or "?", m.x, m.y,
                tostring(m.isAbyss), tostring(floorIdx), edgeDist,
                tostring(GS.isPoisonFogTile(m.x, m.y)), tostring(inFogAndAbyss),
                dist, m.atkRange))
        end
        if dist <= m.atkRange and not inFogAndAbyss then
            m.plannedTarget = target
            goto continue
        end

        claimUnit(claimed, m, nil)

        -- 暴怒史莱姆王：移动时无碰撞体积，可穿过杂兵怪物和圣树
        local isEnragedKing = (m.defId == "slime_king_enraged")
        if isEnragedKing then GS._enragedKingMoving = true end
        local movable, mParents = GS.getMovableCellsForMonster(m)
        GS._enragedKingMoving = nil

        -- 预计算目标周围的空位（攻击范围内、未被占用的格子）
        local targetAdj = {}
        for dy = -m.atkRange, m.atkRange do
            for dx = -m.atkRange, m.atkRange do
                if math.abs(dx) + math.abs(dy) <= m.atkRange and (dx ~= 0 or dy ~= 0) then
                    local ax, ay = target.x + dx, target.y + dy
                    if GS.isInBoard(ax, ay) then
                        local ak = GS.cellKey(ax, ay)
                        if isEnragedKing or not claimed[ak] then
                            targetAdj[#targetAdj + 1] = {x = ax, y = ay, key = ak}
                        end
                    end
                end
            end
        end

        local bestX, bestY = m.x, m.y
        local bestDist = dist
        local bestCanAtk = false
        local isRanged = (m.atkRange or 1) > 1  -- 远程怪物：能攻击时优先保持距离
        -- 深渊毒雾规避：记录当前最佳格子是否在毒雾外
        local bestNotFog = not inFogAndAbyss  -- 不在毒雾场景 → true; 当前在毒雾中 → false

        --- 比较两个候选格：返回 true 则新格子更优
        local function isBetterCandidate(canAtk, d, notFog, cx, cy)
            -- 毒雾优先级最高：非毒雾 > 毒雾（仅深渊毒雾场景）
            if inFogAndAbyss then
                if notFog and not bestNotFog then return true end   -- 逃出毒雾优先
                if not notFog and bestNotFog then return false end  -- 不回毒雾
            end
            -- 攻击能力次之：能攻击 > 不能攻击
            if canAtk and not bestCanAtk then return true end
            if not canAtk and bestCanAtk then return false end
            -- 同级比较
            if canAtk and isRanged then
                return d > bestDist  -- 远程：保持距离，选最远
            elseif d < bestDist then
                return true
            elseif d == bestDist and not canAtk then
                -- 同距离不能攻击：选离目标周围空位更近的
                local curMinToAdj = 999
                for _, adj in ipairs(targetAdj) do
                    curMinToAdj = math.min(curMinToAdj, GS.manhattan(bestX, bestY, adj.x, adj.y))
                end
                local newMinToAdj = 999
                for _, adj in ipairs(targetAdj) do
                    newMinToAdj = math.min(newMinToAdj, GS.manhattan(cx, cy, adj.x, adj.y))
                end
                return newMinToAdj < curMinToAdj
            end
            return false
        end

        -- [DEBUG] 毒雾回避日志
        local dbgMovableCount = 0
        local dbgNotFogCount = 0
        local dbgUnclaimedCount = 0
        for key, _ in pairs(movable) do
            local cy = math.floor(key / 100)
            local cx = key - cy * 100
            dbgMovableCount = dbgMovableCount + 1
            if isEnragedKing or isAreaUnclaimed(claimed, cx, cy, ms) then
                dbgUnclaimedCount = dbgUnclaimedCount + 1
                local d = GS.manhattanToUnit(target.x, target.y, {x = cx, y = cy, size = ms})
                local canAtk = (d <= m.atkRange)
                local notFog = not inFogAndAbyss or (not GS.isPoisonFogTile(cx, cy))
                if notFog then dbgNotFogCount = dbgNotFogCount + 1 end

                if isBetterCandidate(canAtk, d, notFog, cx, cy) then
                    bestCanAtk = canAtk
                    bestDist = d
                    bestX = cx
                    bestY = cy
                    bestNotFog = notFog
                end
            end
        end
        if inFogAndAbyss then
            print(string.format("[FOG-AI] %s@(%d,%d) inFog=%s movable=%d unclaimed=%d notFog=%d → best=(%d,%d) bestNotFog=%s bestCanAtk=%s",
                m.name or m.defId or "?", m.x, m.y, tostring(inFogAndAbyss),
                dbgMovableCount, dbgUnclaimedCount, dbgNotFogCount,
                bestX, bestY, tostring(bestNotFog), tostring(bestCanAtk)))
        end

        local oldX, oldY = m.x, m.y
        local path = GS.reconstructPath(mParents, oldX, oldY, bestX, bestY)
        m.x = bestX
        m.y = bestY
        claimUnit(claimed, m, true)
        M.startMoveAnim(m, oldX, oldY, path)

        -- 暴怒史莱姆王踩踏：摧毁移动目的地的杂兵和圣树
        if isEnragedKing and (bestX ~= oldX or bestY ~= oldY) then
            M.enragedKingTrample(m)
        end

        -- 移动后重新选择目标（可能移动后离另一个友方更近了）
        local finalTarget, finalDist = M.pickEnemyTarget(m, effectiveAllies)
        if finalTarget and finalDist <= m.atkRange then
            m.plannedTarget = finalTarget
        end
        ::continue::
    end

    -- 新刷怪物首回合限制：规划完成后统一恢复原始移动/攻击范围
    for _, m in ipairs(GS.monsters) do
        if m._restoreRangeAfterTurn then
            m.moveRange = m._origMoveRange
            m.atkRange  = m._origAtkRange
            m._origMoveRange = nil
            m._origAtkRange  = nil
            m._restoreRangeAfterTurn = nil
        end
    end
end

function M.endPlayerTurn()
    -- 酒馆肉搏胜利已触发，冻结回合推进（对话/结算中）
    if GS.tavernBrawlState and GS.tavernBrawlState.done then return end
    print("[TIMING] 1-endPlayerTurn called @ " .. tostring(os.clock()))

    -- 解放日胸甲：结算延迟伤害（最先结算）
    if (GS._deferredDmg or 0) > 0 and GS.player and GS.player.hp > 0 then
        local dd = GS._deferredDmg
        GS._deferredDmg = 0
        GS.player.hp = GS.player.hp - dd
        M.addDamageText(GS.player.x, GS.player.y, dd .. "(延迟)", {200, 160, 120})
        M.addHurtFlash(GS.player)
        if GS.player.hp <= 0 then GS.player.hp = 0 end
    end

    -- 地狱踏：本回合未移动，在脚下生成燃烧地面
    if GS.player and not GS.player.isMonster
        and (GS.player.hellStompBurnPct or 0) > 0
        and not GS._hellStompPlaced then
        local px, py = GS.player.x, GS.player.y
        local bg = {
            x = px, y = py,
            turnsLeft = 3,
            burnPct = GS.player.hellStompBurnPct,
            casterMAtk = GS.player.mAtk or 0,
            hellStomp = true,
        }
        local found = false
        for _, existing in ipairs(GS.burningGrounds) do
            if existing.x == px and existing.y == py then
                existing.turnsLeft = bg.turnsLeft
                existing.burnPct = bg.burnPct
                existing.casterMAtk = bg.casterMAtk
                existing.hellStomp = true
                found = true
                break
            end
        end
        if not found then
            GS.burningGrounds[#GS.burningGrounds + 1] = bg
        end
    end
    -- 地狱踏：回合结束，清除撤销记录（移动已确认）
    GS._hellStompPlaced = nil

    -- 竞技场：玩家在出口格子上结束回合 → 自动进入下一关
    if GS.arenaWaitForExit and GS.arenaExitTiles and GS.player and GS.player.hp > 0 then
        for _, tile in ipairs(GS.arenaExitTiles) do
            if GS.player.x == tile.x and GS.player.y == tile.y then
                local DM = require("Dungeon.DungeonManager")
                print("[竞技场] 玩家在出口格子上结束回合，自动进入下一关")
                DM.triggerArenaExit()
                return
            end
        end
    end

    -- ── 备用武器处理（优先于其他动画等待，实现均匀间隔） ──

    -- 备用武器延迟投掷：已在 pending 中，按 0.2s 间隔触发
    if GS.player and GS.player._spareWeaponPending then
        local p = GS.player._spareWeaponPending
        p.delay = p.delay - (GS._pendingEndTurnTimer or 0)
        GS._pendingEndTurnTimer = 0
        if p.delay > 0 then
            GS.pendingEndPlayerTurn = true
            return
        end
        local target = p.target
        if target and target.hp > 0 and GS.player.hp > 0 then
            M.addDamageText(GS.player.x, GS.player.y - 0.5, "备用武器!", {160, 140, 120})
            GS._spareWeaponFreeThrow = true
            M.performAttack(GS.player, target, "a_weapon_throw")
            GS._spareWeaponFreeThrow = nil
        end
        p.remaining = p.remaining - 1
        if p.remaining > 0 and target and target.hp > 0 then
            p.delay = 0.2
            GS._pendingEndTurnTimer = 0
            GS.pendingEndPlayerTurn = true
            return
        end
        GS.player._spareWeaponPending = nil
        -- 注意：_spareWeaponCritDmg 是持续3回合的BUFF，不在投掷完成时清除
        -- 全部投掷完成，继续正常 endPlayerTurn 流程
    end

    -- 备用武器首次触发：只等弹道命中，不等后续动画（伤害文字延迟/屏幕震动等）
    if GS.player and GS.player._spareWeaponThrows and GS.player._spareWeaponThrows > 0 then
        -- 仅检查弹道是否到达目标
        local projectileFlying = false
        for _, d in ipairs(GS.damageTexts) do
            if d.pendingHit then projectileFlying = true; break end
        end
        if projectileFlying then
            GS._pendingEndTurnTimer = (GS._pendingEndTurnTimer or 0)
            if GS._pendingEndTurnTimer < 3.0 then
                GS.pendingEndPlayerTurn = true
                return
            end
        end
        -- 弹道已命中，转为 pending 并开始 0.2s 倒计时
        local target = GS.player._spareWeaponTarget
        local throws = GS.player._spareWeaponThrows
        GS.player._spareWeaponTarget = nil
        GS.player._spareWeaponThrows = nil
        if target and target.hp > 0 then
            GS.player._spareWeaponPending = {
                target = target,
                remaining = throws,
                delay = 0.2,
            }
            GS._pendingEndTurnTimer = 0
            GS.pendingEndPlayerTurn = true
            return
        end
    end

    -- ── 正常动画等待 ──

    local needWait = false

    -- 1) 等待弹道类攻击的伤害数字解锁
    for _, d in ipairs(GS.damageTexts) do
        if d.pendingHit then
            needWait = true
            break
        end
    end

    -- 2) 等待火球弹道到达目标（hitT=0.38）
    if not needWait then
        for _, e in ipairs(GS.fireballEffects) do
            if e.timer / e.duration < 0.42 then  -- 略晚于 hitT=0.38，留出爆炸闪光时间
                needWait = true
                break
            end
        end
    end

    -- 3) 等待陨石落地（impactT=0.33）
    if not needWait then
        for _, e in ipairs(GS.meteorEffects) do
            if e.timer / e.duration < 0.37 then  -- 略晚于 impactT=0.33，留出撞击闪光时间
                needWait = true
                break
            end
        end
    end

    -- 4) 等待冰环扩散命中（hitT=0.20）
    if not needWait then
        for _, e in ipairs(GS.iceRingEffects) do
            if e.timer / e.duration < 0.25 then  -- 略晚于 hitT=0.20，留出冰环扩散时间
                needWait = true
                break
            end
        end
    end

    -- 5) 等待伤害文字延迟结束（火球/陨石/冰环的 damageTextDelay）
    if not needWait then
        for _, d in ipairs(GS.damageTexts) do
            if d.delay and d.delay > 0 then
                needWait = true
                break
            end
        end
    end

    -- 6) 等待深渊弹射队列清空
    if not needWait and #GS.pendingBounces > 0 then
        needWait = true
    end

    -- 7) 屏幕震动
    if not needWait and GS.screenShake then
        local s = GS.screenShake
        if s.timer < (s.delay or 0) + s.duration then
            needWait = true
        end
    end

    if needWait then
        -- 超时保护：基础 3 秒 + 弹射队列额外时间（每条弹射链约 0.5s/跳）
        local bounceExtra = 0
        for _, b in ipairs(GS.pendingBounces) do
            local remaining = (b.bounceCount or 0) - (b.bounceIndex or 0)
            bounceExtra = bounceExtra + remaining * 0.5
        end
        local timeout = 3.0 + bounceExtra
        GS._pendingEndTurnTimer = (GS._pendingEndTurnTimer or 0)
        if GS._pendingEndTurnTimer < timeout then
            GS.pendingEndPlayerTurn = true
            return
        end
        -- 超时：强制清理所有等待状态并继续
        for _, d in ipairs(GS.damageTexts) do
            if d.pendingHit then d.pendingHit = false; d.timer = 0 end
            if d.delay and d.delay > 0 then d.delay = 0 end
        end
        GS.pendingBounces = {}
    end

    GS.pendingEndPlayerTurn = false
    GS._pendingEndTurnTimer = nil
    print("[TIMING] 2-endPlayerTurn executing (no wait) @ " .. tostring(os.clock()))

    -- 闪烁突袭：清除临时攻速加成（用 recalcStats 重算，避免中途 recalcStats 已覆盖导致减多）
    if GS.player and GS.player._flashAtkSpdBonus then
        GS.player._flashAtkSpdBonus = nil
        GS.recalcStats(GS.player)
    end

    -- 祝福类 Buff 统一回合递减（祈祷/圣泉/征服/庇护/奇迹）
    tickBlessingBuffs(GS.player)

    -- 冲锋怒吼 Buff 回合递减
    if GS.player and (GS.player.chargeRoarTurns or 0) > 0 then
        GS.player.chargeRoarTurns = GS.player.chargeRoarTurns - 1
        if GS.player.chargeRoarTurns <= 0 then
            GS.player.chargeRoarTurns = nil
            GS.player.chargeRoarDmgPct = nil
            GS.player.chargeRoarReducePct = nil
        end
    end

    -- 圣树每回合治疗 + 回合递减
    M.tickHolyTrees()

    -- 圣光结晶：每3回合释放存储的治疗能量
    if GS.player and GS.player.hp > 0 and (GS.player.healReleaseRate or 0) > 0 then
        GS._holyCrystalTurnCount = (GS._holyCrystalTurnCount or 0) + 1
        if GS._holyCrystalTurnCount >= 3 then
            GS._holyCrystalTurnCount = 0
            local stored = GS.player._holyCrystalStore or 0
            if stored > 0 then
                local releaseAmt = math.floor(stored * GS.player.healReleaseRate / 100)
                if releaseAmt > 0 then
                    -- healEffectPct 应用于释放治疗
                    if (GS.player.healEffectPct or 0) > 0 then
                        releaseAmt = math.floor(releaseAmt * (1 + GS.player.healEffectPct / 100))
                    end
                    local oldHp = GS.player.hp
                    GS.player.hp = math.min(GS.player.hp + releaseAmt, GS.player.maxHp)
                    if GS.player.hp > oldHp then
                        M.addHealEffect(GS.player.x, GS.player.y, GS.player)
                    end
                    -- 释放的治疗也触发辉光（防止递归存储）
                    GS.player._holyCrystalReleasing = true
                    M.triggerRadianceDamage(releaseAmt)
                    GS.player._holyCrystalReleasing = nil
                end
                GS.player._holyCrystalStore = 0
            end
        end
    end

    -- 冒险英雄钉锤：回合结束时治疗自身
    if GS.player and GS.player.hp > 0 then
        local weaponR = GS.equipment and GS.equipment["weapon_r"]
        if weaponR and (weaponR.extraEffects or {}).heroMaceHeal then
            local healAmt = weaponR.extraEffects.heroMaceHeal
            -- healEffectPct 应用于英雄钉锤治疗
            if (GS.player.healEffectPct or 0) > 0 then
                healAmt = math.floor(healAmt * (1 + GS.player.healEffectPct / 100))
            end
            local oldHp = GS.player.hp
            GS.player.hp = math.min(GS.player.hp + healAmt, GS.player.maxHp)
            -- 满血时也显示绿字和触发辉光（用意图治疗量）
            M.addDamageText(GS.player.x, GS.player.y, "+" .. healAmt, {100, 255, 100})
            M.addHealEffect(GS.player.x, GS.player.y, GS.player)
            M.triggerRadianceDamage(healAmt)
        end
    end

    -- 冰墙回合递减
    M.tickIceWalls()

    -- 燃烧地面回合递减 + 灼烧伤害
    M.tickBurningGrounds()
    -- 灼烧地面可能烧死玩家，检查是否已进入复活状态
    if GS.gameState == GS.STATE_RESPAWN then return end

    -- 暴风雪 & 雷云 tick 已移至 startPlayerTurn（回合开始时触发，动画有充足时间播放）

    -- 怪物减速 debuff 递减
    M.tickMonsterSlowDebuffs()

    -- 暴雨被动：重置回合内命中计数
    M.stormHitCounts = {}

    -- 风暴buff：回合结束触发
    if GS.stormBuffTurns > 0 and GS.player and GS.player.hp > 0 then
        local endN = GS.stormEndCount or 0
        if endN == 1 then
            M.triggerStormWhirlwind(GS.player)
        elseif endN > 1 then
            for i = 1, endN do
                table.insert(M.chainQueue, {
                    action = function() M.triggerStormWhirlwind(GS.player) end,
                })
            end
            M.chainActive = true
            M.chainTimer = 0
        end
    end

    -- 衍生飓风：玩家回合结束时以玩家为中心触发一次小型旋风斩
    if GS.player and GS.player.hp > 0 then
        local derivLv = GS.skillLevels["deriv_storm"] or 0
        if derivLv > 0 then
            M.queueDerivStorm(GS.player)
        end
    end

    -- 施法职业吟唱段数标记清零（回合开始时直接覆盖，避免视觉闪烁）
    if (GS.currentClass == "mage" or GS.currentClass == "priest") and not GS.chanting then
        GS._chantPendingReset = true
    end

    -- 技能冷却递减
    GS.tickSkillCooldowns()

    -- 怪物 debuff 递减已移至 tickMonsterDebuffs()，在敌人回合结束后调用

    -- 不可知物凝视消散：玩家背对不可知物时清除所有凝视层数
    if GS.player and GS.player.hp > 0 and (GS.player._unknownGaze or 0) > 0 then
        for _, m in ipairs(GS.monsters) do
            if m.hp > 0 and m.defId == "tidal_boss_unknown" then
                local dirBonus = M._getDirectionalBonus(m, GS.player)
                if dirBonus == 2 then  -- 不可知物在玩家背后 = 玩家背对不可知物
                    local gaze = GS.player._unknownGaze
                    GS.player._unknownGaze = 0
                    GS.player._gazePer = 0
                    GS.player._gazeFoc = 0
                    GS.recalcStats(GS.player)
                    M.addDamageText(GS.player.x, GS.player.y - 0.5, "凝视消散", {160, 200, 255})
                    print("[不可知物] 玩家背对，凝视消散 (移除 " .. gaze .. " 层)")
                end
                break
            end
        end
    end

    -- 玩家 debuff 持续回合递减
    if #GS.playerDebuffs > 0 then
        for i = #GS.playerDebuffs, 1, -1 do
            GS.playerDebuffs[i].turns = GS.playerDebuffs[i].turns - 1
            if GS.playerDebuffs[i].turns <= 0 then
                table.remove(GS.playerDebuffs, i)
            end
        end
    end

    -- 幻纱：回合结束时将 mpToHpPct% 的当前魔法值转化为生命值（非治疗效果）
    if GS.player and GS.player.hp > 0 and (GS.player.mpToHpPct or 0) > 0 and GS.player.mp > 0 then
        local convertAmt = math.floor(GS.player.mp * GS.player.mpToHpPct / 100)
        if convertAmt > 0 then
            local oldHp = GS.player.hp
            GS.player.hp = math.min(GS.player.hp + convertAmt, GS.player.maxHp)
            local actualHeal = GS.player.hp - oldHp
            if actualHeal > 0 then
                M.addDamageText(GS.player.x, GS.player.y - 0.5, "+" .. actualHeal .. "(幻纱)", {180, 140, 255})
            end
        end
    end

    -- 普通关卡刷怪（玩家回合结束时刷入，新怪当回合即可行动）
    if not GS.isDungeon then
        local anyFleeing = false
        for _, m in ipairs(GS.monsters) do
            if m.fleeing and m.hp > 0 then anyFleeing = true; break end
        end
        if not anyFleeing then
            local curStage = GS.STAGE_DEFS[GS.currentStage]
            if not (curStage and curStage.noRespawn) then
                local interval = (curStage and curStage.spawnInterval) or 2
                if GS.turnNumber % interval == 0 then
                    M.spawnMonsters()
                end
            end
        end
    end

    -- 检查是否有存活友军 → 友军回合；否则直接敌人回合
    local hasCompanion = false
    for _, c in ipairs(GS.companions) do
        if c.hp > 0 then hasCompanion = true; break end
    end

    if hasCompanion then
        print("[TIMING] 3-endPlayerTurn → startCompanionTurn @ " .. tostring(os.clock()))
        M.startCompanionTurn()
    else
        print("[TIMING] 3-endPlayerTurn → startEnemyTurn (no companion) @ " .. tostring(os.clock()))
        M.startEnemyTurn()
    end
end

--- 开始敌人回合（从 endPlayerTurn 或 companion 回合结束后调用）
function M.startEnemyTurn()
    -- 酒馆肉搏胜利已触发，冻结回合推进（对话/结算中）
    if GS.tavernBrawlState and GS.tavernBrawlState.done then return end
    print("[TIMING] 6-startEnemyTurn @ " .. tostring(os.clock()))
    -- 训练模式：假人不移动不攻击，进入短暂空转后回到玩家回合
    if GS.trainingMode then
        GS.gameState = GS.STATE_ENEMY
        GS._trainingIdleTimer = 0
        return
    end

    GS.gameState = GS.STATE_ENEMY
    GS.turnPhase = GS.PHASE_PRE
    GS.advanceTurnPhase()  -- PRE → MOVE
    GS.enemyAttackFired = false
    GS._enemyMoveEndLogged = false
    for _, m in ipairs(GS.monsters) do m.acted = false end
    M.planAllEnemyMoves()
    print("=== 敌人回合 [" .. GS.turnPhase .. "] ===")
end



-- ====================================================================
-- 采集回合推进（回合制采集，每玩家回合 +34% 进度）
-- ====================================================================
function M.processGatheringTurn(dt)
    if not GS.gatheringState then return false end

    -- 累计超时保护：防止因任何原因卡死
    GS.gatheringState._totalTimer = (GS.gatheringState._totalTimer or 0) + dt

    -- 等待敌人/友军回合完成（兼容 STATE_SELECT 防御性）
    if GS.gameState ~= GS.STATE_PLAYER and GS.gameState ~= GS.STATE_SELECT then return true end
    if not GS.player or GS.player.hp <= 0 then return false end

    -- 处理延迟的 endPlayerTurn（上一回合进度推进后被挂起）
    if GS.pendingEndPlayerTurn then
        return true  -- main.lua:638 会重试 endPlayerTurn
    end

    -- 闪烁阶段：变色闪烁完成后触发采集结果
    if GS.gatheringState._flashPhase then
        GS.gatheringState._flashTimer = (GS.gatheringState._flashTimer or 0) + dt
        if GS.gatheringState._flashTimer >= 0.7 then
            M.finishGathering()
        end
        return true
    end

    -- 等待填充动画完成后，预判结果并进入闪烁阶段
    if GS.gatheringState._waitFill then
        if (GS.gatheringState._displayProgress or 0) >= 0.99 then
            local gs = GS.gatheringState
            gs._result = math.random() <= gs.successRate  -- 预判成功/失败
            gs._flashPhase = true
            gs._flashTimer = 0
        end
        return true
    end

    -- 已行动过，等待回合循环回来（敌人→新玩家回合）
    if GS.player.acted then return true end

    -- 成功率为0：进度条以红色填满状态闪烁
    if (GS.gatheringState.successRate or 0) <= 0 and not GS.gatheringState._zeroRateTriggered then
        GS.gatheringState._zeroRateTriggered = true
        GS.gatheringState._turnDelay = -0.3
    end
    if GS.gatheringState._zeroRateTriggered and not GS.gatheringState._flashPhase then
        GS.gatheringState._turnDelay = (GS.gatheringState._turnDelay or 0) + dt
        if GS.gatheringState._turnDelay < 0.4 then return true end
        local gs = GS.gatheringState
        gs._result = false
        gs._zeroRate = true
        gs._displayProgress = 1.0  -- 进度条填满
        gs.progress = 1.0
        gs._flashPhase = true
        gs._flashTimer = 0
        return true
    end

    -- 短暂延迟，让玩家看到进度条变化
    GS.gatheringState._turnDelay = (GS.gatheringState._turnDelay or 0) + dt
    if GS.gatheringState._turnDelay < 0.4 then return true end
    GS.gatheringState._turnDelay = 0

    local gs = GS.gatheringState
    local ppt = gs.progressPerTurn or 0.34
    gs.progress = (gs.progress or 0) + ppt
    gs.turnCount = (gs.turnCount or 0) + 1
    print("[采集] 回合 " .. gs.turnCount .. " 进度 " .. string.format("%.0f%%", gs.progress * 100) .. "（每回合+" .. math.floor(ppt*100) .. "%）")

    if gs.progress >= 1.0 then
        gs.progress = 1.0
        gs._waitFill = true  -- 等填充动画追上再完成
    else
        -- 进度未满：结束玩家回合，让怪物行动
        GS.player.acted = true
        GS.selectedUnit = nil
        M.endPlayerTurn()
    end
    return true
end

-- ====================================================================
-- 自动战斗逻辑
-- ====================================================================
function M.processAutoCombat(dt)
    if not GS.autoMode then return false end
    -- 充能动画进行中，阻塞自动战斗
    if GS._chantGainBlocking then return false end
    -- 竞技场过场或对话期间暂停自动战斗
    if GS.arenaTransition then return false end
    local DialogueManager = require("DialogueManager")
    if DialogueManager.active then return false end
    if GS.gameState == GS.STATE_PLAYER and GS.player and not GS.player.acted and not GS.gatheringState then
        print("[TIMING] 9-autoCombat ready @ " .. tostring(os.clock()))
    end
    if GS.homeMode then return false end
    if GS.gameState ~= GS.STATE_PLAYER then return false end
    if not GS.player or GS.player.hp <= 0 or GS.player.acted then return false end
    -- 正在采集中，等待进度条完成，不要重新触发
    if GS.gatheringState then return false end

    GS.autoTimer = GS.autoTimer + dt
    if GS.autoTimer < GS.AUTO_DELAY then return false end
    GS.autoTimer = 0

    -- 自动使用消耗品：检查 HP/MP 是否低于阈值
    for i = 1, GS.AUTO_CONSUMABLE_SLOTS do
        local tid = GS.autoConsumables[i]
        if tid then
            local stat = GS.AUTO_CONSUMABLE_SLOT_STAT[i] -- "hp" or "mp"
            local cur, max
            if stat == "hp" then
                cur, max = GS.player.hp, GS.player.maxHp
            elseif stat == "mp" then
                cur, max = GS.player.mp, GS.player.maxMp
            end
            if cur and max and max > 0 then
                local ratio = cur / max * 100
                local threshold = GS.autoConsumableThresholds[i] or 50
                if ratio < threshold then
                    -- 在背包中找到匹配 templateId 的消耗品
                    for slotIdx = 1, GS.bagSlots do
                        local item = GS.inventory[slotIdx]
                        if item and item.templateId == tid and item.consumable then
                            local itemName = item.name or "消耗品"
                            local ok, msg = GS.useConsumable(slotIdx)
                            if ok then
                                M.addDamageText(GS.player.x, GS.player.y - 0.4, "自动:" .. itemName, {80, 230, 180})
                            end
                            break
                        end
                    end
                end
            end
        end
    end

    -- 自动食物：食物buff不存在或已过期时自动使用
    if GS.autoFood then
        local needFood = false
        if not GS.foodBuff then
            needFood = true
        elseif GS.weatherTime >= GS.foodBuff.expireTime then
            needFood = true
        end
        if needFood then
            for slotIdx = 1, GS.bagSlots do
                local item = GS.inventory[slotIdx]
                if item and item.templateId == GS.autoFood then
                    local tpl = GS.itemTemplates[item.templateId]
                    if tpl and tpl.useEffect == "food" then
                        local ok, msg = GS.useSpecialItem(slotIdx)
                        if ok then
                            M.addDamageText(GS.player.x, GS.player.y - 0.4, "自动:" .. (tpl.name or "食物"), {80, 230, 180})
                        end
                        break
                    end
                end
            end
        end
    end

    -- 自动增强药剂：对应buff不存在或已过期时自动使用
    if GS.autoBuffPotion then
        local needBuff = false
        -- 找到该药剂的 stat 类型
        local potionStat = nil
        for slotIdx = 1, GS.bagSlots do
            local item = GS.inventory[slotIdx]
            if item and item.templateId == GS.autoBuffPotion and item.consumable then
                potionStat = item.consumable.stat
                break
            end
        end
        if potionStat then
            local existingBuff = GS.potionBuffs[potionStat]
            if not existingBuff then
                needBuff = true
            elseif GS.weatherTime >= existingBuff.expireTime then
                needBuff = true
            end
        end
        if needBuff and GS.consumableCooldown <= 0 then
            for slotIdx = 1, GS.bagSlots do
                local item = GS.inventory[slotIdx]
                if item and item.templateId == GS.autoBuffPotion and item.consumable then
                    local itemName = item.name or "增强药剂"
                    local ok, msg = GS.useConsumable(slotIdx)
                    if ok then
                        M.addDamageText(GS.player.x, GS.player.y - 0.4, "自动:" .. itemName, {80, 230, 180})
                    end
                    break
                end
            end
        end
    end

    --- 检查怪物是否可被玩家接近攻击（排除完全被毒雾包围的不可达怪物）
    local function isMonsterApproachable(m)
        if not GS.isPoisonFogTile(m.x, m.y) then return true end
        -- 怪物在毒雾中，检查攻击范围内是否有非毒雾的可站位置
        local range = GS.player.atkRange or 1
        local ms = GS.unitSize(m)
        for dy = -range, ms - 1 + range do
            for dx = -range, ms - 1 + range do
                local ax, ay = m.x + dx, m.y + dy
                if GS.isInBoard(ax, ay) and not GS.isPoisonFogTile(ax, ay)
                   and GS.manhattanToUnit(ax, ay, m) <= range then
                    return true
                end
            end
        end
        return false
    end

    local bestMonster = nil
    local bestDist = 9999
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 and isMonsterApproachable(m) then
            local d = GS.manhattanToUnit(GS.player.x, GS.player.y, m)
            if d < bestDist then
                bestDist = d
                bestMonster = m
            end
        end
    end

    if bestMonster then
        local function pickWeakestInRange(px, py)
            local atkCells = GS.getAttackableCells(GS.player, px, py)
            local target = nil
            local lowestRatio = 2.0
            for _, m in ipairs(GS.monsters) do
                if m.hp > 0 then
                    -- 多格怪物：任意占据格子在攻击范围内即可
                    local ms = GS.unitSize(m)
                    local inRange = false
                    for oy = 0, ms - 1 do
                        for ox = 0, ms - 1 do
                            if atkCells[GS.cellKey(m.x + ox, m.y + oy)] then
                                inRange = true
                                break
                            end
                        end
                        if inRange then break end
                    end
                    if inRange then
                        local ratio = m.hp / m.maxHp
                        if ratio < lowestRatio then
                            lowestRatio = ratio
                            target = m
                        end
                    end
                end
            end
            return target
        end

        -- ── 施法职业自动战斗辅助 ──
        local isCaster = (GS.currentClass == "mage" or GS.currentClass == "priest")
        local autoWTag = GS.equipment and GS.equipment["weapon_r"] and GS.equipment["weapon_r"].weaponTag
        local isStaffWeapon = (autoWTag == "法杖")
        local isMeleeCasterWeapon = isCaster and autoWTag ~= "法杖"

        --- 为施法职业自动战斗挑选一个段数足够的技能
        --- 按槽位优先级遍历，跳过段数不够的技能，找到第一个可用的
        local function pickMageAutoSkill()
            if not isCaster then return GS.pickActiveSkill() end
            for i = 1, GS.ACTIVE_SKILL_SLOTS do
                local skillId = GS.activeSkills[i]
                if skillId and GS.isSkillReady(skillId) then
                    -- 跳过已生效的 buff 技能（复用 pickActiveSkill 的逻辑）
                    local def = GS.SKILL_DEFS[skillId]
                    if def then
                        local buffActive = false
                        -- 魔法盾 toggle：已开启则跳过
                        if def.magicShieldToggle and GS.magicShieldActive then buffActive = true end
                        -- 检查全局 buff
                        if def.stormBuff and (GS.stormBuffTurns or 0) > 0 then buffActive = true end
                        -- focusBuff 已改为被动，无需在自动战斗中判断
                        if def.stealthBuff and (GS.stealthTurns or 0) > 0 then buffActive = true end
                        if def.fireShieldBuff and (GS.fireShieldTurns or 0) > 1 then buffActive = true end
                        -- 圣树已存在则跳过
                        if def.holyTree and #GS.holyTrees > 0 then buffActive = true end
                        -- 检查玩家 buff
                        if GS.player then
                            if def.prayerBuff and (GS.player.prayerTurns or 0) > 0 then buffActive = true end
                            if def.holySpringBuff and (GS.player.holySpringTurns or 0) > 0 then buffActive = true end
                            if def.conquerBuff and (GS.player.conquerTurns or 0) > 0 then buffActive = true end
                            if def.shelterBuff and (GS.player.shelterTurns or 0) > 0 then buffActive = true end
                            if def.miracleBuff and (GS.player.miracleTurns or 0) > 0 then buffActive = true end
                        end
                        if buffActive then goto continueMagePick end
                    end
                    -- 检查吟唱段数是否足够（治疗/祝福技能跳过段数检查，段数不足时进入吟唱状态）
                    local stages = GS.getSkillCastStages(skillId)
                    local skipChantCheck = def.restoreHeal or def.holyTree
                        or def.prayerBuff or def.holySpringBuff or def.conquerBuff or def.shelterBuff or def.miracleBuff
                    if not skipChantCheck and stages > 0 and (GS.chantStages or 0) < stages then
                        goto continueMagePick  -- 段数不够，跳过尝试下一个
                    end
                    return skillId
                end
                ::continueMagePick::
            end
            return nil  -- 没有可用技能，回退到普攻
        end

        --- 检查法师在攻击范围（普攻+技能）内是否有可打的敌人
        local function mageHasTargetInRange()
            local px, py = GS.player.x, GS.player.y
            -- 普攻范围内是否有敌人（含风向调整）
            local atkCells = GS.getAttackableCells(GS.player, px, py)
            for _, m in ipairs(GS.monsters) do
                if m.hp > 0 then
                    local ms = GS.unitSize(m)
                    for oy = 0, ms - 1 do
                        for ox = 0, ms - 1 do
                            if atkCells[GS.cellKey(m.x + ox, m.y + oy)] then
                                return true
                            end
                        end
                    end
                end
            end
            -- 检查可用技能（段数足够）的 skillRange 是否够得到
            local sk = pickMageAutoSkill()
            if sk then
                local sd = GS.SKILL_DEFS[sk]
                if sd and sd.selfCast then return true end
                local sr = sd and sd.skillRange and (sd.skillRange + GS.getElementRangeBonus(sk)) or (GS.player.atkRange or 1)
                local WE_m = require("WeatherEffects")
                local isProj = WE_m.isProjectileType(GS.player, sk, GS.player.weaponTag)
                local skillCells = GS.getAttackableCells(GS.player, px, py, sr, isProj)
                for _, m in ipairs(GS.monsters) do
                    if m.hp > 0 then
                        local ms = GS.unitSize(m)
                        for oy = 0, ms - 1 do
                            for ox = 0, ms - 1 do
                                if skillCells[GS.cellKey(m.x + ox, m.y + oy)] then
                                    return true
                                end
                            end
                        end
                    end
                end
            end
            return false
        end

        --- 施法职业自动战斗回合结束判断：
        --- 返回 true = 继续行动（下一tick再来），false = 结束回合
        local function mageAutoContinue()
            if not isCaster then return false end
            if (GS.chantStages or 0) <= 0 then return false end
            if GS.chanting then return false end
            -- 有段数，检查是否有可打的目标
            if not mageHasTargetInRange() then
                -- 没有目标且不可移动（已使用段数），结束回合
                return false
            end
            -- 有段数且有目标，继续行动
            GS.mageActionTaken = true
            return true
        end

        --- 执行自动战斗攻击后的结束/继续逻辑
        --- @param useSkillId string|nil 使用的技能ID
        local function autoFinishOrContinue(useSkillId)
            -- 消耗吟唱段数
            if isCaster then
                -- 深度思维：每次行动前重置增伤
                if GS.player then GS.player._deepThinkBonus = 0 end
                if useSkillId then
                    -- 祝福术/超度：消耗全部剩余吟唱段数（走物理逻辑，使用1次即结束回合）
                    if useSkillId == "p_bless" or useSkillId == "p_exorcism" then
                        -- 深度思维：清空吟唱并计算额外增伤
                        if GS.player and (GS.player.deepThinkDmgPer or 0) > 0 and (GS.chantStages or 0) > 0 then
                            local stagesNeeded = GS.getSkillCastStages(useSkillId)
                            local extra = math.max(0, (GS.chantStages or 0) - stagesNeeded)
                            if extra > 0 then
                                GS.player._deepThinkBonus = extra * GS.player.deepThinkDmgPer
                            end
                        end
                        GS.chantStages = 0
                    else
                        local stages = GS.getSkillCastStages(useSkillId)
                        -- 深度思维：清空所有吟唱段数并计算额外增伤
                        if GS.player and (GS.player.deepThinkDmgPer or 0) > 0 then
                            local extra = math.max(0, (GS.chantStages or 0) - stages)
                            if extra > 0 then
                                GS.player._deepThinkBonus = extra * GS.player.deepThinkDmgPer
                            end
                            GS.chantStages = 0
                        elseif stages > 0 then
                            GS.chantStages = math.max(0, (GS.chantStages or 0) - stages)
                        end
                    end
                elseif isMeleeCasterWeapon then
                    -- 施法职业近战武器普攻：消耗全部吟唱段数
                    GS.chantStages = 0
                elseif isStaffWeapon then
                    -- 法杖普攻消耗1段
                    GS.chantStages = math.max(0, (GS.chantStages or 0) - 1)
                end
            end

            M.removeDeadMonsters()

            if mageAutoContinue() then
                -- 法师还有段数且有目标：不结束回合，重置阶段让下一tick继续
                -- 回退 turnPhase 到 ACTION 以便下次能正常推进
                GS.turnPhase = GS.PHASE_ACTION
                GS.autoTimer = -(GS.AUTO_DELAY * 2)  -- 法师连续使用段数间隔：总等待约0.45秒
                return
            end

            -- 正常结束回合
            GS.player.acted = true
            if not M.startChainIfNeeded(function()
                M.endPlayerTurn()
            end) then
                M.endPlayerTurn()
            end
        end

        -- 自动战斗：优先检查 selfCast / 治疗类技能（buff类/治疗类，无需目标）
        local selfCastUsed = false
        do
            local trySkill = pickMageAutoSkill()
            if trySkill then
                local sd = GS.SKILL_DEFS[trySkill]
                if sd and sd.selfCast then
                    local castStages = GS.getSkillCastStages(trySkill)
                    if castStages > 0 and (GS.chantStages or 0) < castStages then
                        -- 吟唱段数不足，进入吟唱状态（与手动释放一致）
                        local consume = math.min(castStages, GS.chantStages or 0)
                        GS.chantStages = (GS.chantStages or 0) - consume
                        GS.useSkill(trySkill)
                        GS.chanting = { skillId = trySkill, stagesNeeded = castStages, stagesAccum = consume, castType = "self" }
                        GS.advanceTurnPhase()
                        GS.player.acted = true
                        M.endPlayerTurn()
                    else
                        -- 段数充足，直接释放（段数由 autoFinishOrContinue 统一消耗）
                        GS.advanceTurnPhase()
                        M.executePlayerAttack(GS.player, GS.player, trySkill)
                        GS.advanceTurnPhase()
                        autoFinishOrContinue(trySkill)
                    end
                    selfCastUsed = true
                end
            end
        end
        if selfCastUsed then return end

        -- 圣树独立处理：不依赖附近有敌人，CD好+有蓝就找空位释放（场上已有圣树则跳过）
        do
            local trySkill = pickMageAutoSkill()
            if trySkill then
                local sd = GS.SKILL_DEFS[trySkill]
                if sd and sd.holyTree and #GS.holyTrees == 0 then
                    local px, py = GS.player.x, GS.player.y
                    local skillRange = (sd.skillRange or 3) + GS.getElementRangeBonus(trySkill)
                    local htBestX, htBestY, htBestDist = nil, nil, math.huge
                    for dy = -skillRange, skillRange do
                        for dx = -skillRange, skillRange do
                            local tx, ty = px + dx, py + dy
                            local dist = math.abs(dx) + math.abs(dy)
                            if dist >= 1 and dist <= skillRange
                               and GS.isInBoard(tx, ty)
                               and GS.getUnitAt(tx, ty) == nil
                               and dist < htBestDist then
                                htBestDist = dist
                                htBestX, htBestY = tx, ty
                            end
                        end
                    end
                    if htBestX then
                        local castStages = GS.getSkillCastStages(trySkill)
                        if castStages > 0 and (GS.chantStages or 0) < castStages then
                            -- 吟唱段数不足，进入吟唱状态（与手动释放一致）
                            local consume = math.min(castStages, GS.chantStages or 0)
                            GS.chantStages = (GS.chantStages or 0) - consume
                            GS.useSkill(trySkill)
                            GS.chanting = { skillId = trySkill, tx = htBestX, ty = htBestY, stagesNeeded = castStages, stagesAccum = consume, castType = "ground" }
                            GS.advanceTurnPhase()
                            GS.player.acted = true
                            M.endPlayerTurn()
                        else
                            -- 段数充足，直接释放（段数由 autoFinishOrContinue 统一消耗）
                            GS.advanceTurnPhase()
                            M.executeGroundSkill(GS.player, trySkill, htBestX, htBestY)
                            GS.advanceTurnPhase()
                            autoFinishOrContinue(trySkill)
                        end
                        return
                    end
                end
            end
        end

        local inRangeTarget = pickWeakestInRange(GS.player.x, GS.player.y)
        -- 没有近身目标时，检查是否有带 skillRange 的技能可打到更远的敌人
        local forcedSkillId = nil
        if not inRangeTarget then
            local trySkillId = pickMageAutoSkill()
            if trySkillId then
                local sd = GS.SKILL_DEFS[trySkillId]
                -- blinkSkill 有专用逃脱路径，不参与普通「扩展射程找目标」逻辑
                -- 否则会以怪物坐标为目标直接闪现过去
                if sd and sd.blinkSkill then trySkillId = nil end
                local skRangeWithBonus = trySkillId and sd.skillRange and (sd.skillRange + GS.getElementRangeBonus(trySkillId)) or 0
                if trySkillId and skRangeWithBonus > (GS.player.atkRange or 1) then
                    -- 用技能距离（含元素熟练加成）重新找目标（含风向调整）
                    local WE_sk = require("WeatherEffects")
                    local isProjSk = WE_sk.isProjectileType(GS.player, trySkillId, GS.player.weaponTag)
                    local skCells = GS.getAttackableCells(GS.player, GS.player.x, GS.player.y, skRangeWithBonus, isProjSk)
                    local skillTarget = nil
                    local lowestRatio = 2.0
                    for _, m in ipairs(GS.monsters) do
                        if m.hp > 0 then
                            local ms = GS.unitSize(m)
                            local inSk = false
                            for oy = 0, ms - 1 do
                                for ox = 0, ms - 1 do
                                    if skCells[GS.cellKey(m.x + ox, m.y + oy)] then
                                        inSk = true; break
                                    end
                                end
                                if inSk then break end
                            end
                            if inSk then
                                local ratio = m.hp / m.maxHp
                                if ratio < lowestRatio then
                                    lowestRatio = ratio
                                    skillTarget = m
                                end
                            end
                        end
                    end
                    if skillTarget then
                        inRangeTarget = skillTarget
                        forcedSkillId = trySkillId
                    end
                end
            end
        end

        -- ── 闪烁突袭特殊自动战斗：优先有空位可突入的目标，其次远程目标 ──
        do
            local flashSkillId = nil
            for i = 1, GS.ACTIVE_SKILL_SLOTS do
                local sid = GS.activeSkills[i]
                if sid and GS.isSkillReady(sid) then
                    local sd = GS.SKILL_DEFS[sid]
                    if sd and sd.flashAssault then
                        flashSkillId = sid
                        break
                    end
                end
            end
            if flashSkillId and not forcedSkillId then
                local flashDef = GS.SKILL_DEFS[flashSkillId]
                local flashRange = flashDef.skillRange or 3
                -- 献礼：闪烁突袭施展距离加成
                if GS.player then
                    flashRange = flashRange + (GS.player.offeringFlashRangeBonus or 0)
                end

                --- 检测目标周围是否有空位可突入（背后/侧面/正面任意一格为空即可）
                --- 排除毒雾格子，与实际执行 handleFlashAssault 的判定保持一致
                local function hasEmptySlot(m)
                    local s = GS.unitSize(m)
                    local dirs = { {0,-1}, {0,s}, {-1,0}, {s,0} }  -- up,down,left,right
                    for _, d in ipairs(dirs) do
                        for k = 0, s - 1 do
                            local cx, cy
                            if d[1] == 0 then       -- up/down
                                cx, cy = m.x + k, m.y + d[2]
                            else                    -- left/right
                                cx, cy = m.x + d[1], m.y + k
                            end
                            if not GS.isPoisonFogTile(cx, cy) then
                                if (cx == GS.player.x and cy == GS.player.y) or GS.isCellEmpty(cx, cy) then
                                    return true
                                end
                            end
                        end
                    end
                    return false
                end

                local flashBest = nil
                local flashBestScore = nil  -- { isRanged(bool), ratio, dist }
                for _, m in ipairs(GS.monsters) do
                    if m.hp > 0 then
                        local dist = GS.manhattanToUnit(GS.player.x, GS.player.y, m)
                        if dist <= flashRange and hasEmptySlot(m) then
                            local isRanged = (m.atkRange or 1) >= 2
                            local ratio = m.hp / m.maxHp
                            local better = false
                            if not flashBestScore then
                                better = true
                            elseif isRanged and not flashBestScore.isRanged then
                                better = true  -- 远程优先
                            elseif isRanged == flashBestScore.isRanged then
                                if ratio < flashBestScore.ratio then
                                    better = true
                                elseif ratio == flashBestScore.ratio and dist < flashBestScore.dist then
                                    better = true
                                end
                            end
                            if better then
                                flashBest = m
                                flashBestScore = { isRanged = isRanged, ratio = ratio, dist = dist }
                            end
                        end
                    end
                end
                if flashBest then
                    inRangeTarget = flashBest
                    forcedSkillId = flashSkillId
                end
            end
        end

        -- ── 冲锋技能特殊自动战斗：移动+施展距离内搜索远程优先目标 ──
        local chargeAutoMoveX, chargeAutoMoveY, chargeAutoPath, chargeAutoParents
        do
            local chargeSkillId = nil
            -- 在技能槽中寻找 ready 的冲锋技能
            for i = 1, GS.ACTIVE_SKILL_SLOTS do
                local sid = GS.activeSkills[i]
                if sid and GS.isSkillReady(sid) then
                    local sd = GS.SKILL_DEFS[sid]
                    if sd and sd.charge then
                        chargeSkillId = sid
                        break
                    end
                end
            end
            if chargeSkillId and not forcedSkillId then
                local chargeDef = GS.SKILL_DEFS[chargeSkillId]
                local chargeLv = GS.skillLevels[chargeSkillId] or 1
                -- 计算冲锋施法距离（含 rangeBreaks）
                local chargeRange = chargeDef.skillRange or 3
                if chargeDef.rangeBreaks then
                    for _, brk in ipairs(chargeDef.rangeBreaks) do
                        if chargeLv >= brk then chargeRange = chargeRange + 1 end
                    end
                end
                -- 收集所有可移动位置（含当前位置）
                local movable, parents = GS.getMovableCells(GS.player)
                chargeAutoParents = parents
                movable[GS.player.y * 100 + GS.player.x] = true  -- 确保当前位置也在候选中
                -- 在所有可站位置搜索冲锋可及的怪物
                --- 检测从(fromX,fromY)冲锋到target是否有非毒雾的空落点
                --- 与 handleCharge 的候选落点逻辑一致
                local function hasChargeLanding(fromX, fromY, target)
                    local dx = target.x - fromX
                    local dy = target.y - fromY
                    local frontDx, frontDy = 0, 0
                    if math.abs(dx) >= math.abs(dy) then
                        frontDx = dx > 0 and -1 or 1
                    else
                        frontDy = dy > 0 and -1 or 1
                    end
                    local cands = {
                        { target.x + frontDx, target.y + frontDy },
                    }
                    if frontDx ~= 0 then
                        cands[#cands+1] = { target.x, target.y - 1 }
                        cands[#cands+1] = { target.x, target.y + 1 }
                        cands[#cands+1] = { target.x - frontDx, target.y }
                    else
                        cands[#cands+1] = { target.x - 1, target.y }
                        cands[#cands+1] = { target.x + 1, target.y }
                        cands[#cands+1] = { target.x, target.y - frontDy }
                    end
                    for _, c in ipairs(cands) do
                        if not GS.isPoisonFogTile(c[1], c[2]) then
                            if (c[1] == fromX and c[2] == fromY) or GS.isCellEmpty(c[1], c[2]) then
                                return true
                            end
                        end
                    end
                    return false
                end

                local chargeBestTarget = nil
                local chargeBestFromX, chargeBestFromY = nil, nil
                local chargeBestScore = nil
                local chargeMode = GS.autoChargeMode or "flank"
                for key, _ in pairs(movable) do
                    local cy = math.floor(key / 100)
                    local cx = key - cy * 100
                    -- 自动冲锋排除毒雾格子（移动落点）
                    if GS.isPoisonFogTile(cx, cy) then goto continue_charge_move end
                    local steps = GS.manhattan(GS.player.x, GS.player.y, cx, cy)
                    for _, m in ipairs(GS.monsters) do
                        if m.hp > 0 then
                            local dist = GS.manhattanToUnit(cx, cy, m)
                            if dist <= chargeRange and hasChargeLanding(cx, cy, m) then
                                local isRanged = (m.atkRange or 1) >= 2
                                local ratio = m.hp / m.maxHp
                                local better = false
                                if not chargeBestScore then
                                    better = true
                                elseif chargeMode == "front" then
                                    -- 正面冲锋：总距离(移动+冲锋)最近 > HP%最低
                                    local totalDist = steps + dist
                                    local bestTotal = chargeBestScore.steps + chargeBestScore.dist
                                    if totalDist < bestTotal then
                                        better = true
                                    elseif totalDist == bestTotal and ratio < chargeBestScore.ratio then
                                        better = true
                                    end
                                else
                                    -- 侧翼冲锋：远程优先 > HP%最低 > 步数最少
                                    if isRanged and not chargeBestScore.isRanged then
                                        better = true
                                    elseif isRanged == chargeBestScore.isRanged then
                                        if ratio < chargeBestScore.ratio then
                                            better = true
                                        elseif ratio == chargeBestScore.ratio and steps < chargeBestScore.steps then
                                            better = true
                                        end
                                    end
                                end
                                if better then
                                    chargeBestTarget = m
                                    chargeBestFromX, chargeBestFromY = cx, cy
                                    chargeBestScore = { isRanged = isRanged, ratio = ratio, steps = steps, dist = dist }
                                end
                            end
                        end
                    end
                    ::continue_charge_move::
                end
                if chargeBestTarget then
                    -- 冲锋目标找到：覆盖 inRangeTarget 和 forcedSkillId
                    inRangeTarget = chargeBestTarget
                    forcedSkillId = chargeSkillId
                    -- 如果需要先移动，记录移动目标
                    if chargeBestFromX ~= GS.player.x or chargeBestFromY ~= GS.player.y then
                        chargeAutoMoveX = chargeBestFromX
                        chargeAutoMoveY = chargeBestFromY
                    end
                end
            end
        end

        -- ═══ 闪烁逃脱自动战斗：怪物距离过近时优先使用闪烁远离 ═══
        local blinkEscapeX, blinkEscapeY
        do
            local blinkSkillId = nil
            for i = 1, GS.ACTIVE_SKILL_SLOTS do
                local sid = GS.activeSkills[i]
                if sid and GS.isSkillReady(sid) then
                    local sd = GS.SKILL_DEFS[sid]
                    if sd and sd.blinkSkill then
                        -- 检查吟唱段数是否足够
                        local stages = GS.getSkillCastStages(sid)
                        if stages <= 0 or (GS.chantStages or 0) >= stages then
                            blinkSkillId = sid
                        end
                        break
                    end
                end
            end
            if blinkSkillId and not forcedSkillId then
                -- 检查是否有怪物距离过近（≤2格）
                local closestDist = math.huge
                for _, m in ipairs(GS.monsters) do
                    if m.hp > 0 then
                        local d = GS.manhattanToUnit(GS.player.x, GS.player.y, m)
                        if d < closestDist then closestDist = d end
                    end
                end
                if closestDist <= 2 then
                    -- 计算闪烁范围
                    local blinkDef = GS.SKILL_DEFS[blinkSkillId]
                    local blinkRange = blinkDef.skillRange or 2
                    local lv = GS.skillLevels[blinkSkillId] or 1
                    if blinkDef.rangeBreaks then
                        for _, brk in ipairs(blinkDef.rangeBreaks) do
                            if lv >= brk then blinkRange = blinkRange + 1 end
                        end
                    end
                    blinkRange = blinkRange + GS.getElementRangeBonus(blinkSkillId)
                    -- 寻找最优逃脱格（最大化与所有怪物的最小距离）
                    local px, py = GS.player.x, GS.player.y
                    local bestEscX, bestEscY, bestMinDist = nil, nil, -1
                    for dy = -blinkRange, blinkRange do
                        for dx = -blinkRange, blinkRange do
                            local tx, ty = px + dx, py + dy
                            local dist = math.abs(dx) + math.abs(dy)
                            if dist >= 1 and dist <= blinkRange
                               and GS.isInBoard(tx, ty)
                               and GS.isCellEmpty(tx, ty)
                               and not GS.isPoisonFogTile(tx, ty) then
                                -- 该格到所有怪物的最小距离
                                local minMD = math.huge
                                for _, m in ipairs(GS.monsters) do
                                    if m.hp > 0 then
                                        local md = GS.manhattanToUnit(tx, ty, m)
                                        if md < minMD then minMD = md end
                                    end
                                end
                                if minMD > bestMinDist then
                                    bestMinDist = minMD
                                    bestEscX, bestEscY = tx, ty
                                end
                            end
                        end
                    end
                    if bestEscX and bestMinDist > closestDist then
                        -- 闪烁后确实能拉开距离，使用闪烁
                        blinkEscapeX, blinkEscapeY = bestEscX, bestEscY
                        forcedSkillId = blinkSkillId
                        inRangeTarget = bestMonster  -- 仅需非nil以进入执行分支
                    end
                end
            end
        end

        -- ═══ 范围化 AOE 地面技能自动战斗：搜索最优位置+方向 ═══
        -- 适用于银色狮子强击系（strike/sup_stk/mst_stk）和哈雷努拉祝福/超度
        -- 在所有可移动位置 × 8方向中，找到命中怪物最多的组合
        local aoeAutoMoveX, aoeAutoMoveY, aoeAutoParents, aoeAutoTarget, aoeForcedSkillId
        if not forcedSkillId then  -- 闪击/冲锋已设置 forcedSkillId，跳过
            -- 查找可用的 AOE 地面技能（遍历技能槽）
            local aoeSkillId = nil
            for i = 1, GS.ACTIVE_SKILL_SLOTS do
                local sid = GS.activeSkills[i]
                if sid and GS.isSkillReady(sid) and M.isAoeGroundSkill(sid) then
                    -- 检查吟唱段数是否足够
                    local stages = GS.getSkillCastStages(sid)
                    if stages <= 0 or (GS.chantStages or 0) >= stages then
                        aoeSkillId = sid
                        break
                    end
                end
            end

            if aoeSkillId then
                -- 统计从位置(ax,ay)向方向(dirX,dirY)释放 AOE 能命中的怪物数
                local function countAoeHits(ax, ay, dirX, dirY)
                    local cells = M.getAoePreviewCells(aoeSkillId, ax, ay,
                                                       ax + dirX, ay + dirY)
                    local hitSet = {}
                    local count = 0
                    for _, c in ipairs(cells) do
                        for _, m in ipairs(GS.monsters) do
                            if m.hp > 0 and not hitSet[m] then
                                local ms = GS.unitSize(m)
                                for oy = 0, ms - 1 do
                                    for ox = 0, ms - 1 do
                                        if m.x + ox == c[1] and m.y + oy == c[2] then
                                            hitSet[m] = true
                                            count = count + 1
                                        end
                                    end
                                end
                            end
                        end
                    end
                    return count
                end

                -- 4 个正方向（强击/祝福 AOE 是矩形区域，斜向释放会产生异形覆盖）
                local aoeDirs = {
                    {1,0}, {-1,0}, {0,1}, {0,-1},
                }

                -- 收集可移动位置（含当前位置）
                local movable, parents = GS.getMovableCells(GS.player)
                aoeAutoParents = parents
                movable[GS.player.y * 100 + GS.player.x] = true

                local bestHits = 0
                local bestSteps = 9999
                local bestPosX, bestPosY = nil, nil
                local bestDirX, bestDirY = 0, 0

                for key, _ in pairs(movable) do
                    local cy = math.floor(key / 100)
                    local cx = key - cy * 100
                    -- 排除毒雾格子（当前位置除外，玩家已站在那里）
                    if (cx ~= GS.player.x or cy ~= GS.player.y)
                       and GS.isPoisonFogTile(cx, cy) then
                        goto continue_aoe_search
                    end
                    local steps = GS.manhattan(GS.player.x, GS.player.y, cx, cy)
                    for _, dir in ipairs(aoeDirs) do
                        local hits = countAoeHits(cx, cy, dir[1], dir[2])
                        if hits > bestHits
                           or (hits == bestHits and hits > 0 and steps < bestSteps) then
                            bestHits = hits
                            bestSteps = steps
                            bestPosX, bestPosY = cx, cy
                            bestDirX, bestDirY = dir[1], dir[2]
                        end
                    end
                    ::continue_aoe_search::
                end

                if bestHits > 0 and bestPosX then
                    -- 虚拟目标：坐标编码了释放方向
                    -- handleStrikeAoe/handleHolyAoe 用 target.x-attacker.x 计算方向
                    local vTarget = {
                        x = bestPosX + bestDirX,
                        y = bestPosY + bestDirY,
                        hp = 1,  -- pendingAutoAction 兼容（pa.target.hp > 0）
                    }
                    if bestPosX == GS.player.x and bestPosY == GS.player.y then
                        -- 不需要移动，立即攻击
                        inRangeTarget = vTarget
                        forcedSkillId = aoeSkillId
                    else
                        -- 需要先移动，走 pendingAutoAction 延迟攻击
                        aoeAutoMoveX = bestPosX
                        aoeAutoMoveY = bestPosY
                        aoeAutoTarget = vTarget
                        aoeForcedSkillId = aoeSkillId
                    end
                end
            end
        end

        -- AOE 移动优先：如果 AOE 搜索找到了需要移动的更优位置，
        -- 清除基础攻击目标以让 AOE 移动分支执行（AOE 搜索已包含
        -- 当前位置的评估，选择移动说明移动后命中数严格更多）
        if aoeAutoMoveX then
            inRangeTarget = nil
            forcedSkillId = nil
        end

        if inRangeTarget then
            -- 冲锋需要先移动到施法位置
            if chargeAutoMoveX then
                local oldX, oldY = GS.player.x, GS.player.y
                local path = GS.reconstructPath(chargeAutoParents, oldX, oldY, chargeAutoMoveX, chargeAutoMoveY)
                GS.recordPlayerPath(path)
                GS.player.x = chargeAutoMoveX
                GS.player.y = chargeAutoMoveY
                M.startMoveAnim(GS.player, oldX, oldY, path)
                -- 标记本回合移动（供静神被动判定）
                if path and #path >= 2 then GS._playerMovedThisTurn = true end
                -- 地狱踏：冲锋移动路径放置燃烧地面
                M.placeHellStompBurning(path)
            end
            GS.advanceTurnPhase()
            local useSkillId = forcedSkillId or pickMageAutoSkill()
            GS.lastActionTargetX = inRangeTarget.x
            GS.lastActionTargetY = inRangeTarget.y
            GS.lastActionAoeRadius = nil
            -- groundTarget 技能（火球术/陨石术/暴风雪/落雷术等）走专用 AOE 流程
            local useDef = useSkillId and GS.SKILL_DEFS[useSkillId]
            if useDef and useDef.groundTarget and not useDef.selfCast then
                -- 吟唱段数由 autoFinishOrContinue 统一消耗，此处不重复扣除
                -- 记录 AOE 半径用于菜单避让
                local aoeR = useDef.fireballRadius or useDef.meteorRadius or useDef.blizzardRadius or useDef.thunderAoeRadius or 0
                if aoeR == 0 and (useDef.iceRingAoe or useDef.holyTree) then aoeR = 1 end
                GS.lastActionAoeRadius = aoeR > 0 and aoeR or nil
                -- 圣树特殊处理：在玩家施法范围内寻找最近的空格放置
                local gtX, gtY = inRangeTarget.x, inRangeTarget.y
                local iwHandled = false
                if useDef.holyTree then
                    local px, py = GS.player.x, GS.player.y
                    local skillRange = (useDef.skillRange or 3) + GS.getElementRangeBonus(useSkillId)
                    local htBestX, htBestY, htBestDist = nil, nil, math.huge
                    for dy = -skillRange, skillRange do
                        for dx = -skillRange, skillRange do
                            local tx, ty = px + dx, py + dy
                            local dist = math.abs(dx) + math.abs(dy)
                            if dist >= 1 and dist <= skillRange
                               and GS.isInBoard(tx, ty)
                               and GS.getUnitAt(tx, ty) == nil
                               and dist < htBestDist then
                                htBestDist = dist
                                htBestX, htBestY = tx, ty
                            end
                        end
                    end
                    if htBestX then
                        gtX, gtY = htBestX, htBestY
                    end
                elseif useDef.iceWallSkill then
                    -- 冰墙自动战斗：在玩家与怪物中间放置垂直于接近方向的冰墙
                    local px, py = GS.player.x, GS.player.y
                    local ex, ey = inRangeTarget.x, inRangeTarget.y
                    local skillRange = (useDef.skillRange or 3) + GS.getElementRangeBonus(useSkillId)
                    local lv = GS.skillLevels[useSkillId] or 1
                    -- 计算最大墙长
                    local iwMaxLen = useDef.iceWallBaseLen or 3
                    local iwLenBreaks = useDef.iceWallLenBreaks or {3, 6, 10}
                    for _, brk in ipairs(iwLenBreaks) do
                        if lv >= brk then iwMaxLen = iwMaxLen + 1 end
                    end
                    -- 接近方向：垂直于玩家→怪物轴线放置冰墙以阻挡
                    local adx, ady = ex - px, ey - py
                    local iwDirs
                    if math.abs(adx) >= math.abs(ady) then
                        iwDirs = {{0, 1}, {0, -1}}  -- 水平接近 → 纵向墙
                    else
                        iwDirs = {{1, 0}, {-1, 0}}  -- 纵向接近 → 横向墙
                    end
                    -- 中点：墙尽量靠近玩家与怪物的中间位置
                    local midX, midY = (px + ex) / 2, (py + ey) / 2
                    local iwBestCells, iwBestScore = nil, -math.huge
                    for sdy = -skillRange, skillRange do
                        for sdx = -skillRange, skillRange do
                            local tx, ty = px + sdx, py + sdy
                            local dist = math.abs(sdx) + math.abs(sdy)
                            if dist >= 1 and dist <= skillRange
                               and GS.isInBoard(tx, ty)
                               and GS.isCellEmpty(tx, ty) then
                                for _, wd in ipairs(iwDirs) do
                                    local cells = {}
                                    for i = 0, iwMaxLen - 1 do
                                        local wx, wy = tx + wd[1] * i, ty + wd[2] * i
                                        if not GS.isInBoard(wx, wy) then break end
                                        if not GS.isCellEmpty(wx, wy) then break end
                                        cells[#cells + 1] = {x = wx, y = wy}
                                    end
                                    if #cells > 0 then
                                        -- 评分：墙长 × 10 - 墙中心到中点的距离
                                        local ci = math.ceil(#cells / 2)
                                        local cx, cy = cells[ci].x, cells[ci].y
                                        local dMid = math.abs(cx - midX) + math.abs(cy - midY)
                                        local score = #cells * 10 - dMid
                                        if score > iwBestScore then
                                            iwBestScore = score
                                            iwBestCells = cells
                                        end
                                    end
                                end
                            end
                        end
                    end
                    if iwBestCells then
                        -- placeIceWalls 内部已调用 useSkill + addSkillCastText
                        M.placeIceWalls(GS.player, useSkillId, iwBestCells)
                        iwHandled = true
                    end
                end
                if useDef.blinkSkill and blinkEscapeX then
                    -- 闪烁逃脱：使用预计算的最优逃脱坐标
                    gtX, gtY = blinkEscapeX, blinkEscapeY
                end
                if not iwHandled then
                    M.addSkillCastText(GS.player.x, GS.player.y, useSkillId)
                    M.executeGroundSkill(GS.player, useSkillId, gtX, gtY)
                end
            else
                M.executePlayerAttack(GS.player, inRangeTarget, useSkillId)
            end
            GS.advanceTurnPhase()
            autoFinishOrContinue(useSkillId)
        elseif aoeAutoMoveX then
            -- ═══ AOE 地面技能：移动到最优位置，等动画结束再释放 ═══
            local oldX, oldY = GS.player.x, GS.player.y
            local path = GS.reconstructPath(aoeAutoParents, oldX, oldY, aoeAutoMoveX, aoeAutoMoveY)
            GS.recordPlayerPath(path)
            GS.player.x = aoeAutoMoveX
            GS.player.y = aoeAutoMoveY
            M.startMoveAnim(GS.player, oldX, oldY, path)
            if path and #path >= 2 then GS._playerMovedThisTurn = true end
            M.placeHellStompBurning(path)
            GS.advanceTurnPhase()
            M.pendingAutoAction = {
                target = aoeAutoTarget,
                forcedSkillId = aoeForcedSkillId,
                movePath = path,
            }
        else
            -- 施法职业已使用段数后不可移动
            if isCaster and GS.mageActionTaken then
                -- 无法移动，无目标在范围内，结束回合
                GS.advanceTurnPhase()
                GS.advanceTurnPhase()
                GS.player.acted = true
                M.endPlayerTurn()
                return
            end

            local movable, autoParents = GS.getMovableCells(GS.player)
            local bestX, bestY = GS.player.x, GS.player.y
            local bestMoveDist = bestDist
            local bestSteps = 9999
            local bestCanAtk = false
            local atkRange = GS.player.atkRange or 1
            -- 考虑带 skillRange 的可用技能扩展攻击距离
            local trySkill = pickMageAutoSkill()
            local moveSkillIsProj = false
            if trySkill then
                local sd = GS.SKILL_DEFS[trySkill]
                local trySkillRange = sd and sd.skillRange and (sd.skillRange + GS.getElementRangeBonus(trySkill)) or 0
                if trySkillRange > atkRange then
                    atkRange = trySkillRange
                    local WE_mv = require("WeatherEffects")
                    moveSkillIsProj = WE_mv.isProjectileType(GS.player, trySkill, GS.player.weaponTag)
                end
            end
            -- 判断普攻是否弹道（弓/法杖）
            local moveNormalIsProj = (GS.player.weaponTag == "弓" or GS.player.weaponTag == "法杖")
            -- 是否需要风向射程调整
            local WE_mv2 = require("WeatherEffects")
            local moveUseWind = GS.isWindy and WE_mv2.isActive() and (moveNormalIsProj or moveSkillIsProj)
            -- 辅助：检查怪物是否在风调整后的攻击范围内
            local bms = GS.unitSize(bestMonster)
            local function canAttackFrom(px, py)
                for oy = 0, bms - 1 do
                    for ox = 0, bms - 1 do
                        local mx, my = bestMonster.x + ox, bestMonster.y + oy
                        local dist = math.abs(px - mx) + math.abs(py - my)
                        local effRange = atkRange
                        if moveUseWind then
                            effRange = atkRange + WE_mv2.getWindRangeMod(px, py, mx, my)
                        end
                        if dist <= effRange then return true end
                    end
                end
                return false
            end

            for key, _ in pairs(movable) do
                local cy = math.floor(key / 100)
                local cx = key - cy * 100
                -- 自动战斗排除毒雾格子
                if GS.isPoisonFogTile(cx, cy) then goto continue_auto_move end
                local d = GS.manhattanToUnit(cx, cy, bestMonster)
                local canAtk = canAttackFrom(cx, cy)
                local steps = GS.manhattan(GS.player.x, GS.player.y, cx, cy)

                if canAtk and not bestCanAtk then
                    -- 首次找到可攻击位置，优先选择
                    bestCanAtk = true
                    bestMoveDist = d
                    bestSteps = steps
                    bestX = cx
                    bestY = cy
                elseif canAtk and bestCanAtk then
                    -- 多个可攻击位置：选步数最少的（尽量少走）
                    if steps < bestSteps then
                        bestMoveDist = d
                        bestSteps = steps
                        bestX = cx
                        bestY = cy
                    end
                elseif not canAtk and not bestCanAtk then
                    -- 都够不到：选距离最近的，同距离步数最少
                    if d < bestMoveDist or (d == bestMoveDist and steps < bestSteps) then
                        bestMoveDist = d
                        bestSteps = steps
                        bestX = cx
                        bestY = cy
                    end
                end
                ::continue_auto_move::
            end

            local oldX, oldY = GS.player.x, GS.player.y
            local path = GS.reconstructPath(autoParents, oldX, oldY, bestX, bestY)
            GS.recordPlayerPath(path)
            GS.player.x = bestX
            GS.player.y = bestY
            M.startMoveAnim(GS.player, oldX, oldY, path)

            GS.advanceTurnPhase()

            -- 延迟攻击：等移动动画完成后再执行
            -- 优先检查自动设置的技能范围，再回退到普攻范围
            local moveTarget = nil
            local moveForcedSkillId = nil
            local trySkillId = pickMageAutoSkill()
            if trySkillId then
                local sd = GS.SKILL_DEFS[trySkillId]
                local skRange = sd and sd.skillRange and (sd.skillRange + GS.getElementRangeBonus(trySkillId)) or (GS.player.atkRange or 1)
                if skRange > (GS.player.atkRange or 1) then
                    -- 技能范围大于普攻范围，用技能范围找目标
                    local WE_sk = require("WeatherEffects")
                    local isProjSk = WE_sk.isProjectileType(GS.player, trySkillId, GS.player.weaponTag)
                    local skCells = GS.getAttackableCells(GS.player, GS.player.x, GS.player.y, skRange, isProjSk)
                    local lowestRatio = 2.0
                    for _, m in ipairs(GS.monsters) do
                        if m.hp > 0 then
                            local ms = GS.unitSize(m)
                            local inSk = false
                            for oy = 0, ms - 1 do
                                for ox = 0, ms - 1 do
                                    if skCells[GS.cellKey(m.x + ox, m.y + oy)] then
                                        inSk = true; break
                                    end
                                end
                                if inSk then break end
                            end
                            if inSk then
                                local ratio = m.hp / m.maxHp
                                if ratio < lowestRatio then
                                    lowestRatio = ratio
                                    moveTarget = m
                                    moveForcedSkillId = trySkillId
                                end
                            end
                        end
                    end
                end
            end
            -- 技能范围没找到目标，回退到普攻范围
            if not moveTarget then
                moveTarget = pickWeakestInRange(GS.player.x, GS.player.y)
                moveForcedSkillId = nil
            end
            M.pendingAutoAction = { target = moveTarget, forcedSkillId = moveForcedSkillId, movePath = path }
        end
    else
        -- 没有怪物：尝试自动采集
        -- 收集所有可采集物并按距离排序
        local gatherRange = 1  -- 采集距离固定为1（不受武器攻击距离影响）
        local gatherCandidates = {}
        for _, g in ipairs(GS.gatherables) do
            if not g.vanishing and (g.harvestsLeft or 1) > 0 then
                local pHLv = GS.getLifeSkillHiddenLevel(g.lifeSkill or "gathering")
                local gHLv = g.hiddenLevel or 0
                if GS.calcGatherSuccessRate(pHLv, gHLv) > 0 then
                    local d = math.abs(GS.player.x - g.x) + math.abs(GS.player.y - g.y)
                    gatherCandidates[#gatherCandidates + 1] = { g = g, dist = d }
                end
            end
        end
        table.sort(gatherCandidates, function(a, b) return a.dist < b.dist end)

        -- 预计算玩家可移动格子（只算一次，供所有候选目标复用）
        local autoMoves, autoParents
        if #gatherCandidates > 0 then
            autoMoves, autoParents = GS.getMovableCells(GS.player)
        end

        -- 按距离从近到远尝试每个采集物，跳过被友军/构造物堵死的
        local bestGather = nil
        local bestGDist = 9999
        local bestMX, bestMY, bestMDist, bestMSteps
        for _, cand in ipairs(gatherCandidates) do
            local g = cand.g
            local d = cand.dist
            if d <= gatherRange then
                -- 已在采集范围内，直接选中
                bestGather = g
                bestGDist = d
                break
            end
            -- 检查是否有可达的移动格子能让玩家进入采集范围
            local foundMX, foundMY = nil, nil
            local foundMDist = 9999
            local foundMSteps = 9999
            for cellK, _ in pairs(autoMoves) do
                local cx = cellK % 100
                local cy = math.floor(cellK / 100)
                -- 自动采集排除毒雾格子
                if not GS.isPoisonFogTile(cx, cy) then
                local cd = math.abs(cx - g.x) + math.abs(cy - g.y)
                if cd <= gatherRange then
                    -- 这个格子可以采集到目标，计算步数选最优
                    local steps = 0
                    local pk = cellK
                    while autoParents[pk] do pk = autoParents[pk]; steps = steps + 1 end
                    if cd < foundMDist or (cd == foundMDist and steps < foundMSteps) then
                        foundMDist = cd
                        foundMSteps = steps
                        foundMX = cx
                        foundMY = cy
                    end
                end
                end -- not isPoisonFogTile
            end
            if foundMX then
                -- 找到可达的邻接格，选中这个采集物
                bestGather = g
                bestGDist = d
                bestMX = foundMX
                bestMY = foundMY
                bestMDist = foundMDist
                bestMSteps = foundMSteps
                break
            end
            -- 没有可达邻接格（被友军/构造物堵死），尝试能否靠近（减少距离）
            local approachMX, approachMY = nil, nil
            local approachMDist = d  -- 当前距离作为基准
            local approachMSteps = 9999
            for cellK, _ in pairs(autoMoves) do
                local cx = cellK % 100
                local cy = math.floor(cellK / 100)
                -- 自动采集靠近排除毒雾格子
                if not GS.isPoisonFogTile(cx, cy) then
                local cd = math.abs(cx - g.x) + math.abs(cy - g.y)
                local steps = 0
                local pk = cellK
                while autoParents[pk] do pk = autoParents[pk]; steps = steps + 1 end
                if cd < approachMDist or (cd == approachMDist and steps < approachMSteps) then
                    approachMDist = cd
                    approachMSteps = steps
                    approachMX = cx
                    approachMY = cy
                end
                end -- not isPoisonFogTile
            end
            if approachMX and approachMDist < d then
                -- 虽然不能直接采集，但可以靠近，选中这个目标
                bestGather = g
                bestGDist = d
                bestMX = approachMX
                bestMY = approachMY
                bestMDist = approachMDist
                bestMSteps = approachMSteps
                break
            end
            -- 这个采集物完全无法接近，跳过尝试下一个
        end

        if bestGather then
            if bestGDist <= gatherRange then
                -- 已在采集范围内：直接采集
                GS.advanceTurnPhase()  -- MOVE → ACTION
                GS.advanceTurnPhase()  -- ACTION → END
                GS.movableCells = {}
                GS.attackableCells = {}
                GS.selectedUnit = nil
                GS.gameState = GS.STATE_PLAYER  -- 确保退出 SELECT 状态
                local pHLv = GS.getLifeSkillHiddenLevel(bestGather.lifeSkill or "gathering")
                local gHLv = bestGather.hiddenLevel or 0
                local lvDiff = pHLv - gHLv
                local ppt = lvDiff >= 200 and 1.0 or (lvDiff >= 100 and 0.50 or 0.34)
                GS.gatheringState = {
                    target      = bestGather,
                    progress    = 0,
                    turnCount   = 0,
                    successRate = GS.calcGatherSuccessRate(pHLv, gHLv),
                    progressPerTurn = ppt,
                }
            else
                -- 需要移动：使用已计算好的最佳移动位置
                local oldX, oldY = GS.player.x, GS.player.y
                local path = GS.reconstructPath(autoParents, oldX, oldY, bestMX, bestMY)
                GS.recordPlayerPath(path)
                GS.player.x = bestMX
                GS.player.y = bestMY
                M.startMoveAnim(GS.player, oldX, oldY, path)
                -- 标记本回合移动（供静神被动判定）
                if path and #path >= 2 then GS._playerMovedThisTurn = true end
                -- 地狱踏：自动采集移动路径放置燃烧地面
                M.placeHellStompBurning(path)
                GS.advanceTurnPhase()

                -- 移动后检查是否到达采集范围
                local newDist = math.abs(bestMX - bestGather.x) + math.abs(bestMY - bestGather.y)
                if newDist <= gatherRange then
                    -- 到达采集范围：移动完成后自动采集
                    M.pendingAutoGather = bestGather
                else
                    -- 未到达（靠近中）：结束回合
                    M.pendingAutoAction = { target = nil, movePath = path }
                end
            end
        else
            -- 没有怪物也没有采集物
            local curStage = GS.STAGE_DEFS[GS.currentStage]
            if curStage and curStage.noRespawn then
                -- 采集区（不再刷怪）：保持自动战斗，停止回合流转
                -- 由 main.lua 非战斗回复逻辑自动触发 HP/MP 自然回复
                -- 若玩家持有静神BUFF，此处回合不流转导致静神永不递减 → 立即清除
                if GS.focusBuffTurns > 0 then
                    GS.focusBuffTurns = 0
                    GS.recalcStats(GS.player)
                    M.addDamageText(GS.player.x, GS.player.y - 0.5, "静神消散", {180, 220, 255})
                end
            elseif GS.isDungeon and GS.arenaWaitForExit then
                -- 深渊区副本阶段完成：自动取消自动战斗，进入自由移动模式
                GS.autoMode = false
                GS.autoTimer = 0
                print("[竞技场] 阶段完成，自动取消自动战斗")
            else
                -- 普通关卡：自动结束回合，让回合循环继续触发刷怪
                GS.player.acted = true
                M.endPlayerTurn()
            end
        end
    end

    return true
end

-- ====================================================================
-- 敌人回合更新（动画驱动的状态机）
-- ====================================================================
function M.processEnemyTurn(dt)
    if GS.gameState ~= GS.STATE_ENEMY then return end

    -- 竞技场过场中：不处理敌人回合逻辑
    if GS.arenaTransition then return end

    -- 训练模式：假人空转 0.3 秒后回到玩家回合
    if GS.trainingMode and GS._trainingIdleTimer then
        GS._trainingIdleTimer = GS._trainingIdleTimer + dt
        if GS._trainingIdleTimer >= 0.5 then
            GS._trainingIdleTimer = nil
            M.tickMonsterDebuffs()
            M.startPlayerTurn()
        end
        return
    end

    -- 等待弹道类伤害文字解锁后再开始敌人行动（近战特效不阻塞）
    for _, d in ipairs(GS.damageTexts) do
        if d.pendingHit then return end
    end

    if GS.turnPhase == GS.PHASE_MOVE then
        -- 怪物闪现延迟恢复（与玩家 pendingBlinkMove 类似）
        for _, m in ipairs(GS.monsters) do
            if m.blinkHidden and m._blinkDelay then
                m._blinkTimer = (m._blinkTimer or 0) + dt
                if m._blinkTimer >= m._blinkDelay then
                    m.blinkHidden = nil
                    m._blinkTimer = nil
                    m._blinkDelay = nil
                end
            end
        end

        local anyMoving = false
        for _, m in ipairs(GS.monsters) do
            if m.hp > 0 and (m.moveAnim or m.blinkHidden) then
                anyMoving = true
                break
            end
        end
        -- 闪现特效仍在播放也视为移动中
        if not anyMoving and #GS.blinkEffects > 0 then
            anyMoving = true
        end
        if not anyMoving and not GS._enemyMoveEndLogged then
            print("[TIMING] 6a-enemy MOVE done → ACTION next frame @ " .. tostring(os.clock()))
            GS._enemyMoveEndLogged = true
        end
        if not anyMoving then
            -- 逃跑怪物到达边缘后消失
            for i = #GS.monsters, 1, -1 do
                local m = GS.monsters[i]
                if m.fleeing and m.hp > 0 then
                    local edgeDist = math.min(m.x - 1, GS.BOARD_SIZE - m.x, m.y - 1, GS.BOARD_SIZE - m.y)
                    -- 到达边缘 或 超过8回合仍未逃出（被堵死兜底）
                    if edgeDist == 0 or (m._fleeTurns and m._fleeTurns >= 8) then
                        M.addDamageText(m.x, m.y, "逃走了", {180, 180, 180})
                        table.remove(GS.monsters, i)
                    end
                end
            end
            -- 仍有逃跑中的怪物：跳过攻击阶段，直接进入下一回合
            local stillFleeing = false
            for _, m in ipairs(GS.monsters) do
                if m.fleeing and m.hp > 0 then stillFleeing = true; break end
            end
            if stillFleeing then
                -- 累计逃跑回合数，超过8回合强制消失（防止被堵死卡关）
                for _, m in ipairs(GS.monsters) do
                    if m.fleeing and m.hp > 0 then
                        m._fleeTurns = (m._fleeTurns or 0) + 1
                    end
                end
                M.tickMonsterDebuffs()
                M.startPlayerTurn()
                return
            end

            GS.advanceTurnPhase()
            GS.enemyAttackFired = false
            GS.animTimer = 0
        end

    elseif GS.turnPhase == GS.PHASE_ACTION then
        GS.animTimer = (GS.animTimer or 0) + dt
        if not GS.enemyAttackFired and GS.animTimer >= 0.15 then
            print("[TIMING] 6b-enemy ACTION fire attacks @ " .. tostring(os.clock()))
            GS.enemyAttackFired = true
            for _, m in ipairs(GS.monsters) do
                if m.hp > 0 and m.plannedHeal then
                    -- 史莱姆王子治疗公主
                    local target = m.plannedHeal
                    if target.hp > 0 then
                        local healAmt = math.min(500, target.maxHp - target.hp)
                        target.hp = target.hp + healAmt
                        M.addDamageText(m.x, m.y - 0.5, "为我而战，我的女士！", {160, 200, 240})
                        if healAmt > 0 then
                            local tcx, tcy = GS.unitCenterPos(target)
                            M.addDamageText(tcx, tcy, "+" .. healAmt, {80, 230, 80})
                        end
                    end
                    m.plannedHeal = nil
                elseif m.hp > 0 and m._plannedFlashAssault and m._plannedFlashAssault.hp > 0 then
                    -- 守门人闪烁突袭：传送到目标身后并攻击
                    local target = m._plannedFlashAssault
                    M.addDamageText(m.x, m.y - 0.5, "闪烁突袭!", {180, 100, 255})
                    -- 根据目标朝向确定"身后"位置
                    local behindOffset = {
                        up    = { 0,  1},
                        down  = { 0, -1},
                        left  = { 1,  0},
                        right = {-1,  0},
                    }
                    local facing = target.facing
                    local behindX, behindY
                    if facing and behindOffset[facing] then
                        local off = behindOffset[facing]
                        behindX = target.x + off[1]
                        behindY = target.y + off[2]
                    else
                        local dx = target.x - m.x
                        local dy = target.y - m.y
                        local tdx, tdy = 0, 0
                        if math.abs(dx) >= math.abs(dy) then
                            tdx = dx > 0 and 1 or -1
                        else
                            tdy = dy > 0 and 1 or -1
                        end
                        behindX = target.x + tdx
                        behindY = target.y + tdy
                    end
                    local teleX, teleY
                    if GS.isInBoard(behindX, behindY) and GS.isCellEmpty(behindX, behindY) then
                        teleX, teleY = behindX, behindY
                    else
                        -- 身后不可用：优先两侧，最后正面
                        local fallback
                        if facing == "up" or facing == "down" then
                            local front = facing == "up" and -1 or 1
                            fallback = {{-1, 0}, {1, 0}, {0, -front}}
                        elseif facing == "left" or facing == "right" then
                            local front = facing == "left" and -1 or 1
                            fallback = {{0, -1}, {0, 1}, {-front, 0}}
                        else
                            fallback = {{0,-1},{0,1},{-1,0},{1,0}}
                        end
                        for _, d in ipairs(fallback) do
                            local nx, ny = target.x + d[1], target.y + d[2]
                            if GS.isInBoard(nx, ny) and GS.isCellEmpty(nx, ny) then
                                teleX, teleY = nx, ny
                                break
                            end
                        end
                    end
                    if teleX then
                        local oldX, oldY = m.x, m.y
                        m.x = teleX
                        m.y = teleY
                        M.addBlinkEffect(oldX, oldY, teleX, teleY)
                        -- 短暂隐藏配合闪烁特效（位置已同步，攻击后立即恢复）
                        m.blinkHidden = true
                        -- 攻击速度加成（模拟10级闪烁突袭）
                        local atkSpdBonus = (m.gatekeeperFlashAtkSpd or 50)
                        m.atkSpeed = (m.atkSpeed or 0) + atkSpdBonus
                        M.performAttack(m, target)
                        m.atkSpeed = (m.atkSpeed or 0) - atkSpdBonus
                        -- 迪哈塔暴怒散射
                        M.applyMonsterRageScatter(m, target)
                        -- 攻击完成后立即恢复显示（不依赖计时器，避免回合切换后永久隐形）
                        m.blinkHidden = nil
                        m._blinkTimer = nil
                        m._blinkDelay = nil
                        -- 怪物连击（extraStrike）
                        if m.extraStrike and m.extraStrike > 0 and target.hp > 0 then
                            for _es = 1, m.extraStrike do
                                table.insert(M.chainQueue, {
                                    attacker = m, defender = target,
                                    label = "", color = {180, 100, 255},
                                })
                            end
                        end
                    else
                        M.addDamageText(target.x, target.y - 0.5, "无法突入!", {200, 200, 200})
                        -- 退回普通攻击
                        local dist = GS.manhattanToUnit(m.x, m.y, target)
                        if dist <= m.atkRange then
                            M.performAttack(m, target)
                            -- 迪哈塔暴怒散射
                            M.applyMonsterRageScatter(m, target)
                            if m.extraStrike and m.extraStrike > 0 and target.hp > 0 then
                                for _es = 1, m.extraStrike do
                                    table.insert(M.chainQueue, {
                                        attacker = m, defender = target,
                                        label = "", color = {255, 120, 80},
                                    })
                                end
                            end
                        end
                    end
                    m._plannedFlashAssault = nil
                elseif m.hp > 0 and m.plannedTarget and m.plannedTarget.hp > 0
                       and not (m.stunned and m.stunned > 0) then
                    -- 不可知物：无视主目标类型，同帧向场上所有友方单位发射弹道
                    if m.defId == "tidal_boss_unknown" then
                        local allAllies = M.getAllPlayerAllies()
                        for _, a in ipairs(allAllies) do
                            if a.isIceWall then
                                if (a.hitsLeft or 0) > 0 then
                                    -- 先发射 dark 弹道特效，再扣冰墙耐久
                                    local atkCX, atkCY = GS.unitCenterPos(m)
                                    local defTX, defTY = GS.unitCenterPos(a)
                                    M.addAttackEffect(atkCX, atkCY, defTX, defTY, "法杖", false, nil, nil, nil, "dark")
                                    M.attackIceWall(a, m)
                                end
                            elseif (a.hp or 0) > 0 then
                                M.performAttack(m, a)
                            end
                        end
                    -- 圣树/冰墙目标：特殊处理（每次攻击减1点，不走正常伤害）
                    -- 暴怒史莱姆王：一击摧毁（将 hitsLeft 强制设为1，走正常流程直接摧毁）
                    elseif m.plannedTarget.isHolyTree then
                        if m.defId == "slime_king_enraged" then
                            m.plannedTarget.hitsLeft = 1
                        end
                        M.attackHolyTree(m.plannedTarget)
                        M.applyMonsterRageScatter(m, m.plannedTarget)
                        -- 攻速连击：额外攻击圣树
                        local spd = m.atkSpeed or 0
                        if spd > 0 and m.plannedTarget.hitsLeft and m.plannedTarget.hitsLeft > 0 then
                            local totalPct = spd * 2
                            local extra = math.floor(totalPct / 100)
                            if math.random() < (totalPct % 100) / 100 then extra = extra + 1 end
                            for _i = 1, extra do
                                if m.plannedTarget.hitsLeft and m.plannedTarget.hitsLeft > 0 then
                                    M.attackHolyTree(m.plannedTarget)
                                    M.applyMonsterRageScatter(m, m.plannedTarget)
                                end
                            end
                        end
                    elseif m.plannedTarget.isIceWall then
                        if m.defId == "slime_king_enraged" then
                            m.plannedTarget.hitsLeft = 1
                        end
                        M.attackIceWall(m.plannedTarget, m)
                        M.applyMonsterRageScatter(m, m.plannedTarget)
                        -- 攻速连击：额外攻击冰墙
                        local spd = m.atkSpeed or 0
                        if spd > 0 and m.plannedTarget.hitsLeft and m.plannedTarget.hitsLeft > 0 then
                            local totalPct = spd * 2
                            local extra = math.floor(totalPct / 100)
                            if math.random() < (totalPct % 100) / 100 then extra = extra + 1 end
                            for _i = 1, extra do
                                if m.plannedTarget.hitsLeft and m.plannedTarget.hitsLeft > 0 then
                                    M.attackIceWall(m.plannedTarget, m)
                                    M.applyMonsterRageScatter(m, m.plannedTarget)
                                end
                            end
                        end
                    else
                        M.performAttack(m, m.plannedTarget)
                        -- 迪哈塔暴怒散射：攻击额外友方目标
                        M.applyMonsterRageScatter(m, m.plannedTarget)
                        -- 怪物连击：extraStrike 标记
                        if m.extraStrike and m.extraStrike > 0 and m.plannedTarget.hp > 0 then
                            for _es = 1, m.extraStrike do
                                table.insert(M.chainQueue, {
                                    attacker = m, defender = m.plannedTarget,
                                    label = "", color = {255, 120, 80},
                                })
                            end
                        end
                        -- 迪拉（ice_mage）攻击后向远离目标方向移动1格
                        if m.ai == "ice_mage" and m.hp > 0 then
                            local tgt = m.plannedTarget
                            local dx = m.x - tgt.x
                            local dy = m.y - tgt.y
                            -- 选择远离方向的1格
                            local retreatX, retreatY = m.x, m.y
                            if math.abs(dx) >= math.abs(dy) then
                                retreatX = m.x + (dx >= 0 and 1 or -1)
                            else
                                retreatY = m.y + (dy >= 0 and 1 or -1)
                            end
                            -- 确保目标格在棋盘内且可通行
                            if GS.isInBoard(retreatX, retreatY) and GS.isCellEmpty(retreatX, retreatY) then
                                local rk = GS.cellKey(retreatX, retreatY)
                                -- 检查目标格没有其他单位
                                local occupied = false
                                for _, om in ipairs(GS.monsters) do
                                    if om ~= m and om.hp > 0 and om.x == retreatX and om.y == retreatY then
                                        occupied = true; break
                                    end
                                end
                                if not occupied and GS.player and not (GS.player.x == retreatX and GS.player.y == retreatY) then
                                    for _, c in ipairs(GS.companions) do
                                        if c.hp > 0 and c.x == retreatX and c.y == retreatY then
                                            occupied = true; break
                                        end
                                    end
                                end
                                if not occupied then
                                    local oldRX, oldRY = m.x, m.y
                                    m.x = retreatX
                                    m.y = retreatY
                                    -- 添加闪烁传送特效（仅视觉，不设 blinkHidden——ACTION 阶段无法由定时器恢复，会永久隐形）
                                    M.addBlinkEffect(oldRX, oldRY, retreatX, retreatY)
                                    print("[AI] ice_mage 后退闪烁: (" .. oldRX .. "," .. oldRY .. ") → (" .. retreatX .. "," .. retreatY .. ")")
                                end
                            end
                        end
                    end
                end
            end
            GS.animTimer = 0
        end

        if GS.enemyAttackFired then
            local anySlam = false
            for _, m in ipairs(GS.monsters) do
                if m.slamAnim then
                    anySlam = true
                    break
                end
            end
            -- 等待远程怪物弓箭弹道完成（只检查怪物的弹道，不被玩家/友军特效阻塞）
            local anyProjectile = false
            for _, ae in ipairs(GS.attackEffects) do
                if ae.monsterProjectile and ae.timer < ae.duration then
                    anyProjectile = true
                    break
                end
            end
            if not anySlam and not anyProjectile and not M.chainActive then
                print("[TIMING] 7-enemy post-attack → startPlayerTurn @ " .. tostring(os.clock()))
                    -- 敌人连击队列：先处理完再结束回合
                    if #M.chainQueue > 0 then
                        M.chainActive = true
                        M.chainTimer = M.chainDelay
                        M.chainCallback = function()
                            GS.advanceTurnPhase()
                            M.removeDeadMonsters()
                            M.removeDeadCompanions()
                            if not M.checkPlayerDeath() then
                                M.tickMonsterDebuffs()
                                M.startPlayerTurn()
                            end
                        end
                        return
                    end

                    GS.advanceTurnPhase()
                    M.removeDeadMonsters()
                    M.removeDeadCompanions()

                    if not M.checkPlayerDeath() then
                        M.tickMonsterDebuffs()
                        M.startPlayerTurn()
                    end
            end
        end

    elseif GS.turnPhase == GS.PHASE_END then
        -- 保底：如果异常进入 PHASE_END，直接推进到下一回合
        -- 防止跨回合吟唱在 startPlayerTurn 中施法后 processEnemyTurn 重入，
        -- 导致刚施加的晕眩被 tickMonsterDebuffs 再次递减而消失
        if not GS.pendingEndPlayerTurn then
            M.tickMonsterDebuffs()
            M.startPlayerTurn()
        end
    end
end

-- ====================================================================
-- 复活逻辑
-- ====================================================================
--- 复活期间怪物随机移动（每秒一次）
local function respawnMonsterWander()
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 and not (m.frozen and m.frozen > 0) then
            -- 随机移动步数：1 ~ moveRange
            local maxSteps = m.moveRange or 1
            local steps = maxSteps > 1 and math.random(1, maxSteps) or 1
            local ms = GS.unitSize(m)

            -- 限制步数的 BFS（支持大型单位）
            local reachable = {}
            local visited = {}
            local rParents = {}
            local queue = {{m.x, m.y, 0}}
            visited[GS.cellKey(m.x, m.y)] = true
            while #queue > 0 do
                local cur = table.remove(queue, 1)
                local cx, cy, cost = cur[1], cur[2], cur[3]
                if cost > 0 then
                    if ms > 1 then
                        if GS.isAreaEmpty(cx, cy, ms, m) then
                            reachable[#reachable + 1] = {cx, cy}
                        end
                    else
                        if GS.isCellEmpty(cx, cy) then
                            reachable[#reachable + 1] = {cx, cy}
                        end
                    end
                end
                if cost < steps then
                    local dirs = {{0,-1},{0,1},{-1,0},{1,0}}
                    for _, d in ipairs(dirs) do
                        local nx, ny = cx + d[1], cy + d[2]
                        local nk = GS.cellKey(nx, ny)
                        if not visited[nk] then
                            local canPass = false
                            if ms > 1 then
                                canPass = GS.isAreaInBoard(nx, ny, ms) and GS.isAreaEmpty(nx, ny, ms, m)
                            else
                                canPass = GS.isInBoard(nx, ny) and GS.isCellEmpty(nx, ny)
                            end
                            if canPass then
                                visited[nk] = true
                                rParents[nk] = {cx, cy}
                                table.insert(queue, {nx, ny, cost + 1})
                            end
                        end
                    end
                end
            end

            if #reachable > 0 then
                local pick = reachable[math.random(1, #reachable)]
                local oldX, oldY = m.x, m.y
                local path = GS.reconstructPath(rParents, oldX, oldY, pick[1], pick[2])
                m.x = pick[1]
                m.y = pick[2]
                M.startMoveAnim(m, oldX, oldY, path)
            end
        end
    end
end

function M.processRespawn(dt)
    if GS.gameState ~= GS.STATE_RESPAWN then return end

    -- 副本模式：等待玩家点击"再战"按钮，不自动倒计时
    if GS.isDungeon then return end

    -- 每秒怪物随机移动一次，同时结算debuff（每秒视为1回合）
    GS.respawnMoveCD = GS.respawnMoveCD + dt
    if GS.respawnMoveCD >= 1.0 then
        GS.respawnMoveCD = GS.respawnMoveCD - 1.0
        -- 训练模式：假人不需要在复活期间移动
        if not GS.trainingMode then
            respawnMonsterWander()
        end
        -- 怪物每秒回复10%最大生命值
        for _, m in ipairs(GS.monsters) do
            if m.hp > 0 and m.hp < m.maxHp then
                local heal = math.max(1, math.floor(m.maxHp * 0.10))
                m.hp = math.min(m.maxHp, m.hp + heal)
                M.addDamageText(m.x, m.y - 0.3, "+" .. heal, {80, 220, 80})
            end
        end

        -- 每秒视为1回合，结算所有buff/debuff/场地效果
        M.tickMonsterDebuffs()
        M.tickMonsterSlowDebuffs()
        M.tickHolyTrees()
        M.tickIceWalls()
        M.tickBurningGrounds()
        M.tickBlizzardZones()
        M.tickThunderClouds()
        M.tickCompanionRespawn()
        tickBlessingBuffs(GS.player)
        GS.tickSkillCooldowns()
        -- 玩家debuff递减
        if #GS.playerDebuffs > 0 then
            for i = #GS.playerDebuffs, 1, -1 do
                GS.playerDebuffs[i].turns = GS.playerDebuffs[i].turns - 1
                if GS.playerDebuffs[i].turns <= 0 then
                    table.remove(GS.playerDebuffs, i)
                end
            end
        end
        -- 元素流转buff递减（自动训练场）
        if (GS._eleFlowTurns or 0) > 0 then
            GS._eleFlowTurns = GS._eleFlowTurns - 1
            if GS._eleFlowTurns <= 0 then
                GS._eleFlowLastElem = nil
                GS._eleFlowTurns = nil
            end
        end
    end

    -- 异世深渊死亡且生命耗尽：不走自动复活倒计时，玩家必须点击"返回清水镇"
    if GS.isAbyssWorld and GS.abyssWorldLives <= 0 then
        return
    end

    -- 史莱姆国王大反击/迪哈塔大反击死亡：不能复活，必须点击"返回清水镇"
    if GS.currentStage == GS.STAGE_SLIME_KING_REVENGE
    or GS.currentStage == GS.STAGE_DIHATA_REVENGE then
        return
    end

    GS.respawnTimer = GS.respawnTimer - dt
    if GS.respawnTimer <= 0 then
        -- 在墓碑位置复活（deathX, deathY）
        local revX, revY = GS.deathX, GS.deathY

        -- 深渊毒雾区域死亡：复活到地图中央，避免反复毒雾致死
        local abyssFloor = GS.getAbyssFloorIndex()
        if abyssFloor == 2 then
            local bs = GS.BOARD_SIZE
            local corners = {{1,1},{bs,1},{1,bs},{bs,bs}}
            for _, c in ipairs(corners) do
                if math.abs(revX - c[1]) + math.abs(revY - c[2]) <= 2 then
                    revX = math.floor(bs / 2) + 1
                    revY = math.floor(bs / 2) + 1
                    break
                end
            end
        elseif abyssFloor == 3 then
            local edgeDist = math.min(revX - 1, GS.BOARD_SIZE - revX, revY - 1, GS.BOARD_SIZE - revY)
            if edgeDist < 2 then
                local bs = GS.BOARD_SIZE
                revX = math.floor(bs / 2) + 1
                revY = math.floor(bs / 2) + 1
            end
        end

        -- 安全检查：如果墓碑位置有怪物（极端情况），击退它
        local dirs = {{0,-1},{0,1},{-1,0},{1,0},{-1,-1},{1,-1},{-1,1},{1,1}}
        for _, m in ipairs(GS.monsters) do
            if m.hp > 0 and m.x == revX and m.y == revY then
                for _, d in ipairs(dirs) do
                    local nx, ny = revX + d[1], revY + d[2]
                    if GS.isInBoard(nx, ny) and GS.getUnitAt(nx, ny) == nil then
                        local oldX, oldY = m.x, m.y
                        m.x = nx
                        m.y = ny
                        M.startMoveAnim(m, oldX, oldY)
                        break
                    end
                end
            end
        end

        GS.player.x = revX
        GS.player.y = revY

        -- 复活时清除所有 BUFF 和 DEBUFF（统一配置在 GS.RESPAWN_CLEAR）
        GS.clearAllBuffsDebuffs()

        -- 复活时清除迪卡塔战意叠层（重置攻击力和攻速到基础值）
        for _, m in ipairs(GS.monsters) do
            if m.defId == "goblin_boss_dikata" and m._battleIntentStacks and m._battleIntentStacks > 0 then
                m.atk = m.atk - m._battleIntentStacks * 2
                m.atkSpeed = (m.atkSpeed or 0) - m._battleIntentStacks * 0.5
                m._battleIntentStacks = nil
                M.addDamageText(m.x, m.y - 0.8, "战意消散", {180, 180, 180})
            end
            -- 复活时清除迪哈塔战斗意志叠层
            if m.defId == "goblin_hero_dihata" and m._dihataWillStacks and m._dihataWillStacks > 0 then
                m.atkSpeed = (m.atkSpeed or 0) - m._dihataWillStacks
                m._dihataWillStacks = nil
                M.addDamageText(m.x, m.y - 0.8, "意志消散", {180, 180, 180})
            end
        end

        GS.recalcStats(GS.player)
        GS.player.hp = GS.player.maxHp
        GS.player.acted = false
        GS.respawnTimer = 0
        GS.tombstoneAnim = { timer = 0, duration = 0.8 }
        GS.reviveEffect = { x = GS.player.x, y = GS.player.y, timer = 0, duration = 1.0 }

        -- 副本死亡：重置阶段（检查点机制）
        if GS.isDungeon then
            DungeonManager.onPlayerDeath()
            DungeonManager.spawnForPhase()
            GS.spawnHound()
            print("=== 副本复活! 重置到阶段 " .. GS.dungeonPhase .. " ===")
        else
            GS.spawnHound()
            print("=== 玩家复活! ===")
        end
        -- debuff已在读秒期间每秒tick，复活时不再额外tick
        M.startPlayerTurn()
    end
end


-- ====================================================================
-- 友军（猎犬）回合
-- ====================================================================

--- 开始友军回合
function M.startCompanionTurn()
    print("[TIMING] 4-startCompanionTurn @ " .. tostring(os.clock()))
    GS.gameState = GS.STATE_COMPANION
    GS.turnPhase = GS.PHASE_PRE
    GS.advanceTurnPhase()  -- PRE → MOVE
    GS.companionAttackFired = false
    GS._compMoveEndLogged = false
    for _, c in ipairs(GS.companions) do
        c.acted = false
        c.plannedAttack = false
        c.plannedTarget = nil
    end
    M.planCompanionMoves()
    print("=== 友军回合 [" .. GS.turnPhase .. "] ===")
end

--- 规划所有友军的移动和攻击
function M.planCompanionMoves()
    local claimed = {}
    if GS.player and GS.player.hp > 0 then
        claimed[GS.cellKey(GS.player.x, GS.player.y)] = true
    end
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 then
            local ms = GS.unitSize(m)
            for dy = 0, ms - 1 do
                for dx = 0, ms - 1 do
                    claimed[GS.cellKey(m.x + dx, m.y + dy)] = true
                end
            end
        end
    end
    for _, c in ipairs(GS.companions) do
        if c.hp > 0 then
            claimed[GS.cellKey(c.x, c.y)] = true
        end
    end

    -- 驯兽熟练满级：猎犬优先攻击玩家最近攻击的目标
    local beastProfMaxed = (GS.skillLevels["h_beast_prof"] or 0) >= GS.SKILL_MAX_LEVEL

    for _, c in ipairs(GS.companions) do
        if c.hp <= 0 then goto comp_continue end

        local bestTarget = nil
        local bestDist = 9999

        -- 检查怪物是否可被猎犬接近攻击（排除完全被毒雾包围的不可达怪物）
        local function isTargetApproachable(m, atkR)
            if not GS.isPoisonFogTile(m.x, m.y) then return true end
            local ms = GS.unitSize(m)
            for dy = -atkR, ms - 1 + atkR do
                for dx = -atkR, ms - 1 + atkR do
                    local ax, ay = m.x + dx, m.y + dy
                    if GS.isInBoard(ax, ay) and not GS.isPoisonFogTile(ax, ay)
                       and GS.manhattanToUnit(ax, ay, m) <= atkR then
                        return true
                    end
                end
            end
            return false
        end

        -- 满级驯兽熟练：优先选择玩家最近攻击的目标（需非毒雾不可达）
        if beastProfMaxed and GS.lastPlayerTarget
           and GS.lastPlayerTarget.hp and GS.lastPlayerTarget.hp > 0
           and isTargetApproachable(GS.lastPlayerTarget, c.atkRange or 1) then
            bestTarget = GS.lastPlayerTarget
            bestDist = GS.manhattanToUnit(c.x, c.y, bestTarget)
        end

        -- 无优先目标或优先目标已死：退回最近目标
        if not bestTarget then
            for _, m in ipairs(GS.monsters) do
                if m.hp > 0 and isTargetApproachable(m, c.atkRange or 1) then
                    local d = GS.manhattanToUnit(c.x, c.y, m)
                    if d < bestDist then
                        bestDist = d
                        bestTarget = m
                    end
                end
            end
        end

        if not bestTarget then
            -- 没有怪物：猎犬跟随玩家轨迹
            -- 多只猎犬时各自跟随不同的轨迹点：第1只往回第2格，第2只往回第3格...
            local trail = GS._playerPosTrail
            local trailLen = #trail
            local followOffset = 2 + (c.houndIndex or 1) - 1  -- 第1只=2，第2只=3，第3只=4...
            local tx, ty
            if trailLen >= followOffset + 1 then
                local entry = trail[trailLen - followOffset]
                tx, ty = entry.x, entry.y
            elseif trailLen >= 1 then
                tx, ty = trail[1].x, trail[1].y
            else
                tx, ty = GS.player.x, GS.player.y
            end
            local distToTarget = GS.manhattan(c.x, c.y, tx, ty)
            if distToTarget > 0 then
                -- 还没到达目标轨迹点，移动靠近
                claimed[GS.cellKey(c.x, c.y)] = nil
                local movable, parents = GS.getMovableCells(c)
                for key, _ in pairs(movable) do
                    if claimed[key] then
                        movable[key] = nil
                    else
                        local ky = math.floor(key / 100)
                        local kx = key - ky * 100
                        if GS.isPoisonFogTile(kx, ky) then
                            movable[key] = nil
                        end
                    end
                end
                local followX, followY = c.x, c.y
                local followDist = distToTarget
                local followSteps = 9999
                for key, _ in pairs(movable) do
                    local cy2 = math.floor(key / 100)
                    local cx2 = key - cy2 * 100
                    local d = GS.manhattan(cx2, cy2, tx, ty)
                    local steps = GS.manhattan(c.x, c.y, cx2, cy2)
                    if d < followDist or (d == followDist and steps < followSteps) then
                        followDist = d
                        followSteps = steps
                        followX = cx2
                        followY = cy2
                    end
                end
                if followX ~= c.x or followY ~= c.y then
                    local oldX, oldY = c.x, c.y
                    local path = GS.reconstructPath(parents, oldX, oldY, followX, followY)
                    c.x = followX
                    c.y = followY
                    claimed[GS.cellKey(c.x, c.y)] = true
                    M.startMoveAnim(c, oldX, oldY, path)
                end
            end
            goto comp_continue
        end

        if bestDist <= c.atkRange then
            c.plannedAttack = true
            c.plannedTarget = bestTarget
            goto comp_continue
        end

        claimed[GS.cellKey(c.x, c.y)] = nil

        local movable, parents = GS.getMovableCells(c, true)  -- 允许穿过友方同伴寻路

        -- 排除已被其他单位 claimed 的格子和毒雾格子
        for key, _ in pairs(movable) do
            if claimed[key] then
                movable[key] = nil
            else
                local ky = math.floor(key / 100)
                local kx = key - ky * 100
                if GS.isPoisonFogTile(kx, ky) then
                    movable[key] = nil
                end
            end
        end

        local bestX, bestY = c.x, c.y
        local bestMoveDist = bestDist
        local bestSteps = 9999
        local bestCanAtk = false

        for key, _ in pairs(movable) do
            local cy2 = math.floor(key / 100)
            local cx2 = key - cy2 * 100
            local d = GS.manhattanToUnit(cx2, cy2, bestTarget)
            local canAtk = (d <= c.atkRange)
            local steps = GS.manhattan(c.x, c.y, cx2, cy2)

            if canAtk and not bestCanAtk then
                -- 首次找到可攻击位置
                bestCanAtk = true
                bestMoveDist = d
                bestSteps = steps
                bestX = cx2
                bestY = cy2
            elseif canAtk and bestCanAtk then
                -- 多个可攻击位置：选步数最少的（尽量少走）
                if steps < bestSteps then
                    bestMoveDist = d
                    bestSteps = steps
                    bestX = cx2
                    bestY = cy2
                end
            elseif not canAtk and not bestCanAtk then
                -- 都够不到：选距离最近的，同距离步数最少
                if d < bestMoveDist or (d == bestMoveDist and steps < bestSteps) then
                    bestMoveDist = d
                    bestSteps = steps
                    bestX = cx2
                    bestY = cy2
                end
            end
        end

        local oldX, oldY = c.x, c.y
        local path = GS.reconstructPath(parents, oldX, oldY, bestX, bestY)
        c.x = bestX
        c.y = bestY
        claimed[GS.cellKey(c.x, c.y)] = true
        M.startMoveAnim(c, oldX, oldY, path)

        if GS.manhattanToUnit(c.x, c.y, bestTarget) <= c.atkRange then
            c.plannedAttack = true
            c.plannedTarget = bestTarget
        end

        ::comp_continue::
    end
end

--- 每帧处理友军回合
function M.processCompanionTurn(dt)
    if GS.gameState ~= GS.STATE_COMPANION then return end

    if GS.turnPhase == GS.PHASE_MOVE then
        local anyMoving = false
        for _, c in ipairs(GS.companions) do
            if c.hp > 0 and c.moveAnim then
                anyMoving = true
                break
            end
        end
        if not anyMoving and not GS._compMoveEndLogged then
            print("[TIMING] 4a-companion MOVE done → ACTION next frame @ " .. tostring(os.clock()))
            GS._compMoveEndLogged = true
        end
        if not anyMoving then
            GS.advanceTurnPhase()
            GS.companionAttackFired = false
            GS.animTimer = 0
        end

    elseif GS.turnPhase == GS.PHASE_ACTION then
        GS.animTimer = (GS.animTimer or 0) + dt
        if not GS.companionAttackFired and GS.animTimer >= 0.15 then
            print("[TIMING] 4b-companion ACTION fire attacks @ " .. tostring(os.clock()))
            GS.companionAttackFired = true
            for _, c in ipairs(GS.companions) do
                if c.hp > 0 and c.plannedAttack and c.plannedTarget then
                    local target = c.plannedTarget
                    if target.hp > 0 then
                        M.performAttack(c, target)
                    end
                    c.plannedAttack = false
                    c.plannedTarget = nil
                end
            end
            GS.animTimer = 0
        end

        if GS.companionAttackFired then
            local anySlam = false
            for _, c in ipairs(GS.companions) do
                if c.slamAnim then anySlam = true; break end
            end
            if not anySlam and not M.chainActive then
                    -- 猎犬连击队列：先处理完再结束回合
                    if #M.chainQueue > 0 then
                        M.chainActive = true
                        M.chainTimer = M.chainDelay
                        M.chainCallback = function()
                            print("[TIMING] 5-companion post-attack (chain done) → startEnemyTurn @ " .. tostring(os.clock()))
                            GS.advanceTurnPhase()
                            M.removeDeadMonsters()
                            M.removeDeadCompanions()
                            M.startEnemyTurn()
                        end
                        return
                    end

                    print("[TIMING] 5-companion post-attack → startEnemyTurn @ " .. tostring(os.clock()))
                    GS.advanceTurnPhase()
                    M.removeDeadMonsters()
                    M.removeDeadCompanions()
                    M.startEnemyTurn()
            end
        end

    elseif GS.turnPhase == GS.PHASE_END then
        -- 保底：如果异常进入 PHASE_END，直接推进到敌方回合
        M.removeDeadMonsters()
        M.removeDeadCompanions()
        M.startEnemyTurn()
    end
end

--- 处理死亡友军：标记复活倒计时而非移除
M.COMPANION_RESPAWN_TURNS = 5

function M.removeDeadCompanions()
    -- 幻影死亡：播放消散特效后从列表移除（不复活）
    for i = #GS.companions, 1, -1 do
        local c = GS.companions[i]
        if c.hp <= 0 and c.isPhantom then
            M.addDamageText(c.x, c.y - 0.5, "幻影消散", {180, 120, 255})
            -- 创建紫色粒子消散特效
            local particles = {}
            for pi = 1, 12 do
                local angle = math.random() * math.pi * 2
                local speed = 15 + math.random() * 25
                particles[pi] = {
                    vx = math.cos(angle) * speed,
                    vy = math.sin(angle) * speed - 10,
                    size = 2 + math.random() * 3,
                }
            end
            table.insert(GS.phantomDissolveEffects, {
                x = c.x, y = c.y,
                timer = 0, duration = 0.7,
                particles = particles,
            })
            table.remove(GS.companions, i)
        end
    end
    -- 其他友军（猎犬等）：标记复活倒计时
    for _, c in ipairs(GS.companions) do
        if c.hp <= 0 and not c.dead then
            c.dead = true
            -- 狼群银哨：自定义猎犬复活回合数
            local eb = GS.getEquipBonus and GS.getEquipBonus() or {}
            local customRespawn = eb.houndRespawnTurns or 0
            c.respawnTurns = customRespawn > 0 and math.floor(customRespawn) or M.COMPANION_RESPAWN_TURNS
            print("[猎犬] " .. c.name .. " 阵亡，" .. c.respawnTurns .. " 回合后复活")
        end
    end
end

--- 每回合递减友军复活倒计时，到0则复活
--- 深渊区副本中猎犬死亡后不允许复活，直到战斗结束
function M.tickCompanionRespawn()
    if GS.isDungeon then return end  -- 副本中不自动复活
    for _, c in ipairs(GS.companions) do
        if c.dead and c.respawnTurns then
            c.respawnTurns = c.respawnTurns - 1
            if c.respawnTurns <= 0 then
                M.respawnCompanion(c)
            end
        end
    end
end

--- 复活友军：满血，放到玩家身旁空位
function M.respawnCompanion(c)
    if not GS.player or GS.player.hp <= 0 then return end

    -- 重新计算属性（玩家可能已升级）
    local fresh = GS.createHound()
    if fresh then
        c.hp = fresh.maxHp
        c.maxHp = fresh.maxHp
        c.atk = fresh.atk
        c.def = fresh.def
        c.mdef = fresh.mdef
        c.critVal = fresh.critVal
        c.hit = fresh.hit
        c.dodge = fresh.dodge
        c.atkSpeed = fresh.atkSpeed
        c.hpRegen = fresh.hpRegen
        c.mpRegen = fresh.mpRegen
        c.level = fresh.level
    else
        c.hp = c.maxHp
    end

    -- 在玩家周围找空位
    local px, py = GS.player.x, GS.player.y
    local offsets = {
        {1,0}, {-1,0}, {0,1}, {0,-1},
        {1,1}, {1,-1}, {-1,1}, {-1,-1},
    }
    local placed = false
    for _, off in ipairs(offsets) do
        local nx, ny = px + off[1], py + off[2]
        if GS.isCellEmpty(nx, ny) then
            c.x = nx
            c.y = ny
            placed = true
            break
        end
    end
    if not placed then
        for dy = -2, 2 do
            for dx = -2, 2 do
                if math.abs(dx) + math.abs(dy) <= 2 then
                    local nx, ny = px + dx, py + dy
                    if GS.isCellEmpty(nx, ny) then
                        c.x = nx
                        c.y = ny
                        placed = true
                        break
                    end
                end
            end
            if placed then break end
        end
    end

    if not placed then return end -- 实在无空位暂不复活

    c.dead = false
    c.respawnTurns = nil
    c.acted = false
    c.hurtTimer = nil
    c.moveAnim = nil
    c.slamAnim = nil
    M.addDamageText(c.x, c.y, "复活!", {80, 255, 120})
    print("[猎犬] " .. c.name .. " 复活在 (" .. c.x .. "," .. c.y .. ") HP=" .. c.hp)
end

end -- sub.init

return sub
