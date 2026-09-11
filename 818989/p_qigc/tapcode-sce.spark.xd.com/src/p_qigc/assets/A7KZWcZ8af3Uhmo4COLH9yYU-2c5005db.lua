-- ====================================================================
-- Combat.lua - 战斗系统、怪物AI、怪物生成、回合管理
-- ====================================================================
-- 为联机做准备：战斗逻辑独立于渲染，可整体迁移到服务端
-- ====================================================================

local GS = require("GameState")
local DungeonManager = require("Dungeon.DungeonManager")
local BoardOverlay = require("BoardOverlay")
local WE = require("WeatherEffects")

local M = {}

-- 前向声明（定义在后方，但需在 updateChainAttacks 中调用）
local applyRangedScatter

-- ====================================================================
-- 英雄单位：免疫晕眩、冰冻、恐惧等无法行动效果，免疫击退
-- ====================================================================
local HERO_UNITS = {
    slime_prince       = true,
    slime_princess     = true,
    slime_king         = true,
    slime_king_enraged = true,
    goblin_boss_diwu   = true,
    goblin_boss_dila   = true,
    goblin_boss_dikata = true,
    tidal_boss_jeni    = true,
    tidal_boss_kuadi   = true,
    tidal_boss_unknown = true,
    red_dragon_young   = true,
    goblin_hero_dihata = true,
}

local function isHeroUnit(unit)
    return unit and unit.defId and HERO_UNITS[unit.defId]
end

-- ====================================================================
-- 音效引用（由 main.lua 注入）
-- ====================================================================
M.sfxAttack = nil
M.sfxSlimeHit = nil
M.sfxMaceHit = nil
M.sfxWhirlwind = nil
---@type Scene|nil
M.scene_ = nil

-- ====================================================================
-- 祝福 Buff 注册表（统一施加 / 衰减逻辑）
-- ====================================================================
---@class BlessingBuffDef
---@field flag       string   技能定义中的标识字段（如 "prayerBuff"）
---@field statField  string   挂在 unit 上的数值字段
---@field turnsField string   挂在 unit 上的回合计数字段
---@field durField   string   技能定义中的持续时间字段
---@field calcValue  fun(def:table, lv:number):number  计算数值
---@field fmtApply   fun(val:number, dur:number):string 施加时的文本
---@field applyName  string   施加时飘字标题
---@field expireName string   消散时飘字文本
---@field color      number[] 飘字颜色 {r,g,b}
---@field needRecalc boolean? 施加/消散时是否需要 recalcStats
---@field isPiety    boolean? 是否受虔诚加成影响（祝福类技能）

local BLESSING_BUFFS = {
    {
        flag = "prayerBuff", statField = "prayerHealPct", turnsField = "prayerTurns",
        durField = "prayerDuration", isPiety = true,
        calcValue = function(def, lv) return (def.prayerHealPctPerLv or 0.5) * lv end,
        applyName = nil, expireName = nil,
        fmtApply = nil,
        color = {255, 220, 100},
    },
    {
        flag = "holySpringBuff", statField = "holySpringRegenPct", turnsField = "holySpringTurns",
        durField = "holySpringDuration", isPiety = true,
        calcValue = function(def, lv) return (def.holySpringRegenPctPerLv or 5) * lv end,
        applyName = "圣泉祝福!", expireName = nil,
        fmtApply = function(val, dur) return "回复+" .. val .. "% " .. dur .. "回合" end,
        color = {255, 220, 100},
    },
    {
        flag = "conquerBuff", statField = "conquerAtkPct", turnsField = "conquerTurns",
        durField = "conquerDuration", isPiety = true, needRecalc = true,
        calcValue = function(def, lv) return (def.conquerAtkPctPerLv or 1) * lv end,
        applyName = "征服祝福!", expireName = nil,
        fmtApply = function(val, dur) return "物攻/魔攻+" .. val .. "% " .. dur .. "回合" end,
        color = {255, 220, 100},
    },
    {
        flag = "shelterBuff", statField = "shelterDefPct", turnsField = "shelterTurns",
        durField = "shelterDuration", isPiety = true, needRecalc = true,
        calcValue = function(def, lv) return (def.shelterDefPctPerLv or 1) * lv end,
        applyName = "庇护祝福!", expireName = nil,
        fmtApply = function(val, dur) return "防御力+" .. val .. "% " .. dur .. "回合" end,
        color = {255, 220, 100},
    },
    {
        flag = "miracleBuff", statField = "miracleVal", turnsField = "miracleTurns",
        durField = "miracleDuration", isPiety = true, needRecalc = true,
        calcValue = function(def, lv) return (def.miraclePerLv or 1) * lv end,
        applyName = "奇迹祝福!", expireName = nil,
        fmtApply = function(val, dur) return "暴+" .. val .. "% 闪+" .. val .. "% 命+" .. val .. "% 暴伤+" .. (val*2) .. "% " .. dur .. "回合" end,
        color = {255, 220, 100},
    },
}

--- 欧几里得距离范围判定（匹配圆形视觉显示）
--- 视觉圆圈半径为 (radius + 0.5) 格，判定也用 +0.5 保持一致
local function inCircleRange(x1, y1, x2, y2, radius)
    local dx, dy = x1 - x2, y1 - y2
    local r = radius + 0.5
    return dx * dx + dy * dy <= r * r
end

--- 显示施法回血/回魔浮动文字（消费 GS._pendingCastHeal / GS._pendingCastMpRegen）
local function showPendingCastEffects(x, y, unit)
    if GS._pendingCastHeal then
        M.addDamageText(x, y - 0.3, "施法回血+" .. GS._pendingCastHeal, {100, 255, 100})
        M.addHealEffect(x, y, unit)
        GS._pendingCastHeal = nil
    end
    if GS._pendingCastMpRegen then
        GS._pendingCastMpRegen = nil
    end
    if GS._pendingRadianceHeal then
        M.triggerRadianceDamage(GS._pendingRadianceHeal)
        GS._pendingRadianceHeal = nil
    end
end

--- 通用施加祝福 Buff
---@param target table 目标单位
---@param skillId string 技能ID
---@param buffDef BlessingBuffDef Buff配置
---@return boolean 是否成功施加
local function applyBlessingBuff(target, skillId, buffDef)
    GS.useSkill(skillId)
    showPendingCastEffects(target.x, target.y, target)
    local lv = GS.skillLevels[skillId] or 1
    local def = GS.SKILL_DEFS[skillId]
    local val = buffDef.calcValue(def, lv)
    local dur = (def[buffDef.durField] or 10)
    -- 虔诚被动加成
    if buffDef.isPiety then
        local pietyLv = GS.skillLevels["p_piety"] or 0
        if pietyLv > 0 then
            dur = dur + pietyLv * ((GS.SKILL_DEFS["p_piety"] or {}).pietyDurPerLv or 5)
            -- 虔诚满级：祝福效果翻倍
            if pietyLv >= GS.SKILL_MAX_LEVEL then
                val = val * 2
            end
        end
    end
    target[buffDef.statField] = val
    target[buffDef.turnsField] = dur + 1  -- +1 补偿当回合递减
    if buffDef.needRecalc then GS.recalcStats(target) end
    if buffDef.applyName then
        M.addDamageText(target.x, target.y, buffDef.applyName, buffDef.color)
    end
    if buffDef.fmtApply then
        M.addDamageText(target.x, target.y - 0.5, buffDef.fmtApply(val, dur), buffDef.color)
    end
    return true
end

--- 通用祝福 Buff 回合衰减（在 endPlayerTurn 中调用）
---@param unit table 目标单位
local function tickBlessingBuffs(unit)
    if not unit then return end
    for _, b in ipairs(BLESSING_BUFFS) do
        if unit[b.turnsField] then
            unit[b.turnsField] = unit[b.turnsField] - 1
            if unit[b.turnsField] <= 0 then
                unit[b.statField] = nil
                unit[b.turnsField] = nil
                if b.needRecalc then GS.recalcStats(unit) end
                if b.expireName then
                    M.addDamageText(unit.x, unit.y, b.expireName, b.color)
                end
            end
        end
    end
end

--- 检查技能定义是否为祝福 Buff（用于 isBuff 判断）
---@param def table 技能定义
---@return boolean
local function isBlessingBuff(def)
    for _, b in ipairs(BLESSING_BUFFS) do
        if def[b.flag] then return true end
    end
    return false
end

--- 施加祝福 Buff（不消耗技能资源，用指定技能的等级计算数值）
---@param target table 目标单位
---@param extraSkillId string 额外祝福的技能ID
---@param buffDef BlessingBuffDef Buff配置
local function applyBlessingBuffFree(target, extraSkillId, buffDef)
    local lv = GS.skillLevels[extraSkillId] or 1
    local sDef = GS.SKILL_DEFS[extraSkillId]
    if not sDef then return end
    local val = buffDef.calcValue(sDef, lv)
    local dur = (sDef[buffDef.durField] or 10)
    if buffDef.isPiety then
        local pietyLv = GS.skillLevels["p_piety"] or 0
        if pietyLv > 0 then
            dur = dur + pietyLv * ((GS.SKILL_DEFS["p_piety"] or {}).pietyDurPerLv or 5)
            -- 虔诚满级：祝福效果翻倍
            if pietyLv >= GS.SKILL_MAX_LEVEL then
                val = val * 2
            end
        end
    end
    target[buffDef.statField] = val
    target[buffDef.turnsField] = dur + 1
    if buffDef.needRecalc then GS.recalcStats(target) end
    if buffDef.applyName then
        M.addDamageText(target.x, target.y, buffDef.applyName, buffDef.color)
    end
    if buffDef.fmtApply then
        M.addDamageText(target.x, target.y - 0.5, buffDef.fmtApply(val, dur), buffDef.color)
    end
end

--- 奇迹祝福附带的额外祝福技能ID映射
local MIRACLE_EXTRA_BLESSINGS = {
    { skillId = "p_holy_spring",   flag = "holySpringBuff" },
    { skillId = "p_conquer_bless", flag = "conquerBuff" },
    { skillId = "p_shelter_bless", flag = "shelterBuff" },
}

--- 尝试施加祝福 Buff（遍历注册表匹配）
---@param target table 目标单位
---@param skillId string 技能ID
---@param def table 技能定义
---@return boolean 是否匹配并施加了 Buff
local function tryApplyBlessingBuff(target, skillId, def)
    for _, b in ipairs(BLESSING_BUFFS) do
        if def[b.flag] then
            local ok = applyBlessingBuff(target, skillId, b)
            -- 奇迹祝福：额外施加圣泉、征服、庇护祝福（不消耗资源）
            if ok and b.flag == "miracleBuff" then
                for _, extra in ipairs(MIRACLE_EXTRA_BLESSINGS) do
                    for _, bb in ipairs(BLESSING_BUFFS) do
                        if bb.flag == extra.flag then
                            applyBlessingBuffFree(target, extra.skillId, bb)
                            break
                        end
                    end
                end
            end
            return ok
        end
    end
    return false
end

-- ====================================================================
-- 技能处理器注册表（替换 executePlayerAttack 中的 if-else 链）
-- ====================================================================
-- 每个 handler(attacker, target, skillId, def) 返回 true 表示已处理

--- 风暴buff
local function handleStormBuff(attacker, target, skillId, def)
    GS.useSkill(skillId)
    showPendingCastEffects(attacker.x, attacker.y, attacker)
    local slv = GS.skillLevels[skillId] or 1
    -- 计算持续时间
    local dur = def.stormDuration or 3
    if def.stormDurBreaks then
        for _, b in ipairs(def.stormDurBreaks) do
            if slv >= b then dur = dur + 1 end
        end
    end
    GS.stormBuffTurns = dur + 1
    -- 计算回合开始/结束触发次数
    local startN = def.stormStartCount or 1
    if def.stormStartBreaks then
        for _, b in ipairs(def.stormStartBreaks) do
            if slv >= b then startN = startN + 1 end
        end
    end
    local endN = def.stormEndCount or 0
    if def.stormEndBreaks then
        for _, b in ipairs(def.stormEndBreaks) do
            if slv >= b then endN = endN + 1 end
        end
    end
    GS.stormStartCount = startN
    GS.stormEndCount = endN
    M.addSkillCastText(attacker.x, attacker.y, skillId)
    M.addWhirlwindEffect(attacker.x, attacker.y)
    GS.setScreenShake(0.3, 2, 0.1)
    return true
end

--- 隐匿buff
local function handleStealthBuff(attacker, target, skillId, def)
    GS.useSkill(skillId)
    showPendingCastEffects(attacker.x, attacker.y, attacker)
    GS.stealthActive = true
    -- 持续回合数：base + (lv-1)*perLv，+1补偿当回合立即递减
    local lv = GS.skillLevels[skillId] or 1
    local dur = (def.stealthDurBase or 1) + (lv - 1) * (def.stealthDurPerLv or 1)
    GS.stealthTurns = dur + 1
    -- 烟雾弹特效
    GS.stealthSmokeEffect = {
        x = attacker.x, y = attacker.y,
        timer = 0, duration = 1.0,
    }
    M.addSkillCastText(attacker.x, attacker.y, skillId)
    return true
end

--- 火焰护盾buff
local function handleFireShieldBuff(attacker, target, skillId, def)
    GS.useSkill(skillId)
    showPendingCastEffects(attacker.x, attacker.y, attacker)
    local lv = GS.skillLevels[skillId] or 1
    local duration = (def.fireShieldDuration or 3) + (lv - 1) * (def.fireShieldDurPerLv or 1) + 1
    local reducePct = (def.fireShieldReducePct or 2) * lv
    local reflectPct = (def.fireShieldReflectBase or 22) + (lv - 1) * (def.fireShieldReflectPerLv or 2)
    -- 判断目标是冰墙还是玩家/友方单位
    if target and target.isIceWall then
        target.fireShieldTurns = duration
        target.fireShieldReducePct = reducePct
        target.fireShieldReflectPct = reflectPct
        M.addSkillCastText(target.x, target.y, skillId)
    else
        GS.fireShieldTurns = duration
        GS.fireShieldReducePct = reducePct
        GS.fireShieldReflectPct = reflectPct
        M.addSkillCastText(attacker.x, attacker.y, skillId)
    end
    return true
end

--- 魔法盾（toggle 开关）
local function handleMagicShieldToggle(attacker, target, skillId, def)
    -- 不消耗技能资源（cd=0, mpCost=0），仅切换状态
    GS.magicShieldActive = not GS.magicShieldActive
    if GS.magicShieldActive then
        M.addSkillCastText(attacker.x, attacker.y, skillId)
        M.addMagicShieldEffect(attacker.x, attacker.y, true)
    else
        M.addDamageText(attacker.x, attacker.y, "魔法盾 关闭", {160, 160, 160})
        M.addMagicShieldEffect(attacker.x, attacker.y, false)
    end
    return true
end

--- 静神buff
local function handleFocusBuff(attacker, target, skillId, def)
    GS.useSkill(skillId)
    showPendingCastEffects(attacker.x, attacker.y, attacker)
    local focusDur = def.focusDuration or 3
    if def.focusDurBP then
        local slv = GS.skillLevels[skillId] or 0
        for bpLv, add in pairs(def.focusDurBP) do
            if slv >= bpLv then focusDur = focusDur + add end
        end
    end
    GS.focusBuffTurns = focusDur + 1
    GS.recalcStats(attacker)  -- 立即刷新 dmgPctBonus 使静神加成生效
    M.addSkillCastText(attacker.x, attacker.y, skillId)
    return true
end

--- 祝福类buff（祈祷/圣泉/征服/庇护/奇迹）
local function handleBlessingBuff(attacker, target, skillId, def)
    return tryApplyBlessingBuff(attacker, skillId, def)
end

--- 恢复术
local function handleRestoreHeal(attacker, target, skillId, def)
    GS.useSkill(skillId)
    showPendingCastEffects(attacker.x, attacker.y, attacker)
    local lv = GS.skillLevels[skillId] or 1
    local pct = (def.restoreMatkPctBase or 33) + (def.restoreMatkPctPerLv or 3) * lv
    local heal = math.floor(attacker.mAtk * pct / 100)
    if heal < 1 then heal = 1 end
    -- 深度思维：额外吟唱段数增效
    if (attacker._deepThinkBonus or 0) > 0 then
        heal = math.floor(heal * (1 + attacker._deepThinkBonus / 100))
    end
    -- 治疗效果加成
    if (attacker.healEffectPct or 0) > 0 then
        heal = math.floor(heal * (1 + attacker.healEffectPct / 100))
    end
    local oldHp = attacker.hp
    attacker.hp = math.min(attacker.hp + heal, attacker.maxHp)
    local actualHeal = attacker.hp - oldHp
    M.addSkillCastText(attacker.x, attacker.y, skillId)
    M.addDamageText(attacker.x, attacker.y, "+" .. heal, {255, 220, 100})
    M.addDivineGraceEffect(attacker.x, attacker.y)
    if not attacker.isMonster then M.triggerRadianceDamage(heal) end
    return true
end

--- 冰环术 AOE（自动战斗时以目标为中心）
local function handleIceRingAOE(attacker, target, skillId, def)
    M.performIceRingAOE(attacker, target.x, target.y, skillId)
    return true
end

--- 闪电链
local function handleChainLightning(attacker, target, skillId, def)
    M.performChainLightning(attacker, target, skillId)
    return true
end

--- 雷云术
local function handleThunderCloud(attacker, target, skillId, def)
    M.performThunderCloud(attacker, target, skillId)
    return true
end

--- AOE
local function handleAOE(attacker, target, skillId, def)
    M.performAOE(attacker, skillId)
    M._pendingChaseArrow = { attacker = attacker, target = target }
    return true
end

--- 散射
local function handleScatter(attacker, target, skillId, def)
    M.performScatter(attacker, target, skillId)
    M._pendingChaseArrow = { attacker = attacker, target = target }
    return true
end

--- 冲锋（替代嘲讽）
local function handleCharge(attacker, target, skillId, def)
    GS.useSkill(skillId)
    showPendingCastEffects(attacker.x, attacker.y, attacker)
    M.addSkillCastText(attacker.x, attacker.y, skillId)
    local lv = GS.skillLevels[skillId] or 1

    -- 寻找目标相邻的空格作为冲锋落点（优先正面）
    local dx = target.x - attacker.x
    local dy = target.y - attacker.y
    local frontDx, frontDy = 0, 0
    if math.abs(dx) >= math.abs(dy) then
        frontDx = dx > 0 and -1 or 1
    else
        frontDy = dy > 0 and -1 or 1
    end
    -- 候选落点：正面 → 两侧 → 背后
    local candidates = {
        { target.x + frontDx, target.y + frontDy },
    }
    if frontDx ~= 0 then
        table.insert(candidates, { target.x, target.y - 1 })
        table.insert(candidates, { target.x, target.y + 1 })
        table.insert(candidates, { target.x - frontDx, target.y })
    else
        table.insert(candidates, { target.x - 1, target.y })
        table.insert(candidates, { target.x + 1, target.y })
        table.insert(candidates, { target.x, target.y - frontDy })
    end
    local teleX, teleY
    for _, c in ipairs(candidates) do
        -- 冲锋排除毒雾格子
        if GS.isPoisonFogTile(c[1], c[2]) then goto continue_charge_pick end
        -- 攻击者自身位置视为可用（已挨着目标时原地冲锋）
        if (c[1] == attacker.x and c[2] == attacker.y) or GS.isCellEmpty(c[1], c[2]) then
            teleX, teleY = c[1], c[2]
            break
        end
        ::continue_charge_pick::
    end

    if teleX then
        local origX, origY = attacker.x, attacker.y
        attacker.x = teleX
        attacker.y = teleY
        -- 冲锋移动动画（从原始位置冲向目标旁）
        M.startMoveAnim(attacker, origX, origY)
        if attacker.moveAnim then
            attacker.moveAnim.chargeTrail = true   -- 橙金色拖尾
            attacker.moveAnim.duration = 0.18      -- 快速冲锋
        end
        -- 强制暴击 + 禁止连击
        attacker._forceCrit = true
        attacker._atkSpeedChaining = true
        attacker._dualDaggerChaining = true
        attacker._doubleStrikeChaining = true
        -- 冲锋吸血：临时叠加到通用吸血字段，由 applyLifesteal 自动处理
        local chargeLifesteal = (def.chargeLifestealPerLv or 1) * lv
        local origLifesteal = attacker.lifesteal or 0
        attacker.lifesteal = origLifesteal + chargeLifesteal
        M.performAttack(attacker, target, nil)
        -- 清除临时标记，恢复原始吸血值
        attacker.lifesteal = origLifesteal
        attacker._forceCrit = nil
        attacker._atkSpeedChaining = nil
        attacker._dualDaggerChaining = nil
        attacker._doubleStrikeChaining = nil
        -- 施加1回合晕眩（英雄单位免疫）
        if target.hp and target.hp > 0 and target.isMonster and not isHeroUnit(target) then
            local oldDur = target.stunned or 0
            target.stunned = 1
            if 1 > oldDur then
                M.addDamageText(target.x, target.y - 0.5, "晕眩!", {255, 220, 60})
            end
        end
        -- 冲锋怒吼：被动技能，冲锋后获得伤害加成+伤害减免
        local roarLv = GS.skillLevels["charge_roar"] or 0
        if roarLv > 0 then
            local roarDef = GS.SKILL_DEFS["charge_roar"]
            local dmgPct = (roarDef.chargeRoarDmgPerLv or 1) * roarLv
            local reducePct = (roarDef.chargeRoarReducePerLv or 1) * roarLv
            attacker.chargeRoarDmgPct = dmgPct
            attacker.chargeRoarReducePct = reducePct
            attacker.chargeRoarTurns = 2  -- 持续到下回合结束（endPlayerTurn递减：2→1→0）
            attacker.floatingText = { text = "呀啊！", duration = 2.0, fadeStart = 1.2, timer = 0, color = {255, 60, 60} }
        end
    else
        M.addDamageText(target.x, target.y - 0.5, "无法冲锋!", {200, 200, 200})
    end
    return true
end

--- 泼沙致盲（范围技能：对周围一圈敌人致盲，然后对最近的敌人发动普通攻击）
local function handleSandBlind(attacker, target, skillId, def)
    GS.useSkill(skillId)
    showPendingCastEffects(attacker.x, attacker.y, attacker)
    local lv = GS.skillLevels[skillId] or 1
    local hitRed = (def.sandHitRedPerLv or 2) * lv
    local sandDur = def.sandDurBase or 3
    if def.sandDurLvs then
        for _, threshold in ipairs(def.sandDurLvs) do
            if lv >= threshold then sandDur = sandDur + 1 end
        end
    end
    M.addSkillCastText(attacker.x, attacker.y, skillId)

    -- 对周围一圈所有敌人施加致盲（range=1，即 3×3）
    local nearest = nil
    local nearestDist = math.huge
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 then
            local s = GS.unitSize(m)
            local adjacent = false
            for dy = 0, s - 1 do
                if adjacent then break end
                for dx = 0, s - 1 do
                    local mx, my = m.x + dx, m.y + dy
                    local ddx = math.abs(mx - attacker.x)
                    local ddy = math.abs(my - attacker.y)
                    if ddx <= 1 and ddy <= 1 and (ddx + ddy) >= 1 then
                        adjacent = true
                        break
                    end
                end
            end
            if adjacent then
                m.sandBlinded = hitRed
                m.sandBlindedTurns = sandDur
                M.addSandBlindEffect(attacker.x, attacker.y, m.x, m.y)
                M.addDamageText(m.x, m.y, "致盲!", {200, 180, 120})
                -- 记录最近的敌人（切比雪夫距离）
                local dist = math.max(math.abs(m.x - attacker.x), math.abs(m.y - attacker.y))
                if dist < nearestDist then
                    nearestDist = dist
                    nearest = m
                end
            end
        end
    end

    -- 对最近的敌人发动一次普通攻击（可触发连击）
    if nearest and nearest.hp > 0 then
        M.performAttack(attacker, nearest, nil)
        applyRangedScatter(attacker, nearest)
        M._pendingChaseArrow = { attacker = attacker, target = nearest }
    end
    return true
end

--- 幻影分身
local function handlePhantom(attacker, target, skillId, def)
    GS.useSkill(skillId)
    showPendingCastEffects(attacker.x, attacker.y, attacker)
    M.addSkillCastText(attacker.x, attacker.y, skillId)
    local lv = GS.skillLevels[skillId] or 1
    local p = attacker
    local origX, origY = p.x, p.y

    -- BFS 寻找最近空格
    local visited = {}
    local queue = {}
    local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
    for _, d in ipairs(dirs) do
        local nx, ny = origX + d[1], origY + d[2]
        local key = nx .. "," .. ny
        if not visited[key] then
            visited[key] = true
            table.insert(queue, {nx, ny})
        end
    end
    local foundX, foundY
    local qi = 1
    while qi <= #queue do
        local pos = queue[qi]
        qi = qi + 1
        if GS.isCellEmpty(pos[1], pos[2]) then
            foundX, foundY = pos[1], pos[2]
            break
        end
        for _, d in ipairs(dirs) do
            local nx, ny = pos[1] + d[1], pos[2] + d[2]
            local key = nx .. "," .. ny
            if not visited[key] and GS.isInBoard(nx, ny) then
                visited[key] = true
                table.insert(queue, {nx, ny})
            end
        end
    end

    if foundX then
        -- 找到空格：移动玩家，创建幻影，进入隐匿
        p.x = foundX
        p.y = foundY

        local atkPct = (def.phantomAtkPctBase or 0) + (def.phantomAtkPctPerLv or 3) * lv
        local critPct = (def.phantomCritPctPerLv or 5) * lv
        local hitPct = (def.phantomHitBase or 55) + (def.phantomHitPerLv or 5) * (lv - 1)
        hitPct = math.min(hitPct, 100)
        local aspdPct = (def.phantomAspdBase or 55) + (def.phantomAspdPerLv or 5) * (lv - 1)
        aspdPct = math.min(aspdPct, 100)

        local hits = def.phantomHitsBase or 2
        if def.phantomHitsLvs then
            for _, reqLv in ipairs(def.phantomHitsLvs) do
                if lv >= reqLv then hits = hits + 1 end
            end
        end

        -- 移除旧幻影
        for i = #GS.companions, 1, -1 do
            if GS.companions[i].isPhantom then
                table.remove(GS.companions, i)
            end
        end

        -- 创建幻影友军
        local phantom = {
            x = origX, y = origY,
            name = "幻影",
            hp = hits, maxHp = hits,
            atk = math.floor(p.atk * atkPct / 100),
            def = math.floor(p.def * 0.5),
            mdef = math.floor((p.mDef or p.mdef or 0) * 0.5),
            critVal = math.floor(p.critVal * critPct / 100),
            critDmg = p.critDmg or 25,
            hit = math.floor(p.hit * hitPct / 100),
            dodge = 0,
            atkSpeed = math.floor(p.atkSpeed * aspdPct / 100),
            hpRegen = 0, mpRegen = 0,
            moveRange = p.moveRange or 3,
            atkRange = p.atkRange or 1,
            color = {140, 80, 200},
            isMonster = false, isCompanion = true, isPhantom = true,
            acted = true,
            level = lv,
        }
        table.insert(GS.companions, phantom)
    end

    -- 无论是否找到空格，都进入隐匿
    GS.stealthActive = true
    local stealthLv = GS.skillLevels["a_stealth"] or 1
    local stealthDef = GS.SKILL_DEFS["a_stealth"]
    local stealthDur = 1
    if stealthDef then
        stealthDur = (stealthDef.stealthDurBase or 1) + (stealthLv - 1) * (stealthDef.stealthDurPerLv or 1)
    end
    GS.stealthTurns = stealthDur + 1
    GS.stealthSmokeEffect = {
        x = p.x, y = p.y,
        timer = 0, duration = 1.0,
    }
    M.addDamageText(p.x, p.y, "隐匿!", {100, 200, 220})
    return true
end

--- 闪烁突袭
local function handleFlashAssault(attacker, target, skillId, def)
    GS.useSkill(skillId)
    showPendingCastEffects(attacker.x, attacker.y, attacker)
    M.addSkillCastText(attacker.x, attacker.y, skillId)
    local lv = GS.skillLevels[skillId] or 1

    local s = GS.unitSize(target)  -- 1 或 2
    local facing = target.facing

    -- 收集目标边缘外侧的候选格，按方位分组：behind > side > front
    -- 对 size=1: 每个方位 1 格；对 size=2: 每个方位 2 格
    local function edgeCells(dir)
        local cells = {}
        if dir == "up" then         -- 目标上方 = y-1 那一行
            for dx = 0, s - 1 do cells[#cells+1] = { target.x + dx, target.y - 1 } end
        elseif dir == "down" then   -- 目标下方 = y+s 那一行
            for dx = 0, s - 1 do cells[#cells+1] = { target.x + dx, target.y + s } end
        elseif dir == "left" then   -- 目标左侧 = x-1 那一列
            for dy = 0, s - 1 do cells[#cells+1] = { target.x - 1, target.y + dy } end
        elseif dir == "right" then  -- 目标右侧 = x+s 那一列
            for dy = 0, s - 1 do cells[#cells+1] = { target.x + s, target.y + dy } end
        end
        return cells
    end

    -- 从候选格列表中找到第一个空格（优先离攻击者近的）
    -- 攻击者自身所在格也视为可用（玩家已在目标背后时不必闪烁到侧面）
    -- 排除毒雾格子，避免闪烁突袭后进入毒雾
    local function pickEmpty(cells)
        -- 按与攻击者的曼哈顿距离排序，近的优先
        table.sort(cells, function(a, b)
            local da = math.abs(a[1] - attacker.x) + math.abs(a[2] - attacker.y)
            local db = math.abs(b[1] - attacker.x) + math.abs(b[2] - attacker.y)
            return da < db
        end)
        for _, c in ipairs(cells) do
            if GS.isPoisonFogTile(c[1], c[2]) then goto continue_pick end
            if (c[1] == attacker.x and c[2] == attacker.y) or GS.isCellEmpty(c[1], c[2]) then
                return c[1], c[2]
            end
            ::continue_pick::
        end
        return nil, nil
    end

    -- 方位映射：facing 的反方向 = behind
    local opposite = { up = "down", down = "up", left = "right", right = "left" }

    -- 确定搜索优先级：behind > side > front
    local behind, front, sides
    if facing and opposite[facing] then
        behind = opposite[facing]
        front  = facing
        if facing == "up" or facing == "down" then
            sides = { "left", "right" }
        else
            sides = { "up", "down" }
        end
    else
        -- 无朝向：根据攻击方向确定 behind（穿透方向）
        local dx = target.x - attacker.x
        local dy = target.y - attacker.y
        if math.abs(dx) >= math.abs(dy) then
            behind = dx > 0 and "right" or "left"
            front  = dx > 0 and "left" or "right"
            sides  = { "up", "down" }
        else
            behind = dy > 0 and "down" or "up"
            front  = dy > 0 and "up" or "down"
            sides  = { "left", "right" }
        end
    end

    local teleX, teleY
    -- 优先身后
    teleX, teleY = pickEmpty(edgeCells(behind))
    -- 其次两侧
    if not teleX then
        for _, side in ipairs(sides) do
            teleX, teleY = pickEmpty(edgeCells(side))
            if teleX then break end
        end
    end
    -- 最后正面
    if not teleX then
        teleX, teleY = pickEmpty(edgeCells(front))
    end
    local atkSpdBonus = (def.flashAtkSpdPerLv or 3) * lv
    attacker._flashAtkSpdBonus = atkSpdBonus
    GS.recalcStats(attacker)  -- recalcStats 内部已纳入 _flashAtkSpdBonus
    if teleX then
        attacker.x = teleX
        attacker.y = teleY
        M.performAttack(attacker, target, nil)
        M._pendingChaseArrow = { attacker = attacker, target = target }
    else
        M.addDamageText(target.x, target.y - 0.5, "无法突入!", {200, 200, 200})
        -- 无法突入时：闪烁突袭本身算 1 次未打出 + 模拟连击随机检定
        if attacker == GS.player and (GS.skillLevels["a_moon_shadow"] or 0) > 0 then
            local missed = 1  -- 闪烁突袭本身
            -- 攻速连击检定
            if not attacker.noCombo then
                local wr = GS.equipment and GS.equipment["weapon_r"]
                local wTag = wr and wr.weaponTag or "拳"
                if wTag ~= "法杖" then
                    local spd = (attacker.atkSpeed or 0) + WE.getRainAtkSpeedMod()
                    if spd > 0 then
                        local totalPct = spd * 2
                        local guaranteed = math.floor(totalPct / 100)
                        local remainChance = (totalPct % 100) / 100
                        missed = missed + guaranteed
                        if math.random() < remainChance then
                            missed = missed + 1
                        end
                    end
                end
                -- 双持不额外计数（双持两下算一组，月影只算1次）
                -- 二连击检定
                local dsLv = GS.skillLevels["a_double_strike"] or 0
                if dsLv > 0 then
                    local dsDef = GS.SKILL_DEFS["a_double_strike"]
                    local chance = (dsDef.doubleStrikeBaseChance or 2) + (dsDef.doubleStrikeChancePerLv or 2) * (dsLv - 1)
                    if math.random(1, 100) <= chance then
                        missed = missed + 1
                    end
                end
            end
            M._moonShadowMissed = (M._moonShadowMissed or 0) + missed
            -- 无法突入不走连击队列，立即结算月影
            if not M.chainActive then
                local totalMissed = M._moonShadowMissed or 0
                if totalMissed > 0 then
                    local p = GS.player
                    local oldStacks = p._moonShadowStacks or 0
                    p._moonShadowStacks = oldStacks + totalMissed
                    M.addDamageText(p.x, p.y - 0.5, "月影+" .. totalMissed, {120, 160, 255})
                end
                M._moonShadowMissed = nil
            end
        end
    end
    return true
end

--- 献礼：自动闪烁突袭（连击中断时触发，不授予攻击速度加成）
--- 在范围内寻找最佳目标，优先级：可突入 > 远程 > 血少
local function offeringAutoFlashAssault(attacker)
    if not attacker or attacker.hp <= 0 then return false end
    local baseRange = 3  -- 闪烁突袭基础施展距离
    local bonusRange = attacker.offeringFlashRangeBonus or 0
    local totalRange = baseRange + bonusRange

    -- 收集范围内存活目标
    local candidates = {}
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 and not m.brawlStunned then
            local dist = GS.manhattanToUnit(attacker.x, attacker.y, m)
            if dist <= totalRange then
                candidates[#candidates + 1] = m
            end
        end
    end
    if #candidates == 0 then
        -- 范围内无目标：归还月影计数（献礼入队时已预扣）
        M._moonShadowMissed = (M._moonShadowMissed or 0) + 1
        return false
    end

    -- 判断能否突入目标（返回闪烁目的地坐标，复用 handleFlashAssault 逻辑）
    local function findTeleportDest(target)
        local s = GS.unitSize(target)
        local facing = target.facing
        local function edgeCells(dir)
            local cells = {}
            if dir == "up" then
                for dx = 0, s - 1 do cells[#cells+1] = { target.x + dx, target.y - 1 } end
            elseif dir == "down" then
                for dx = 0, s - 1 do cells[#cells+1] = { target.x + dx, target.y + s } end
            elseif dir == "left" then
                for dy = 0, s - 1 do cells[#cells+1] = { target.x - 1, target.y + dy } end
            elseif dir == "right" then
                for dy = 0, s - 1 do cells[#cells+1] = { target.x + s, target.y + dy } end
            end
            return cells
        end
        local function pickEmpty(cells)
            table.sort(cells, function(a, b)
                local da = math.abs(a[1] - attacker.x) + math.abs(a[2] - attacker.y)
                local db = math.abs(b[1] - attacker.x) + math.abs(b[2] - attacker.y)
                return da < db
            end)
            for _, c in ipairs(cells) do
                if GS.isPoisonFogTile(c[1], c[2]) then goto continue_offering_pick end
                if (c[1] == attacker.x and c[2] == attacker.y) or GS.isCellEmpty(c[1], c[2]) then
                    return c[1], c[2]
                end
                ::continue_offering_pick::
            end
            return nil, nil
        end
        local opposite = { up = "down", down = "up", left = "right", right = "left" }
        local behind, front, sides
        if facing and opposite[facing] then
            behind = opposite[facing]
            front  = facing
            if facing == "up" or facing == "down" then sides = { "left", "right" }
            else sides = { "up", "down" } end
        else
            local dx2 = target.x - attacker.x
            local dy2 = target.y - attacker.y
            if math.abs(dx2) >= math.abs(dy2) then
                behind = dx2 > 0 and "right" or "left"
                front  = dx2 > 0 and "left" or "right"
                sides  = { "up", "down" }
            else
                behind = dy2 > 0 and "down" or "up"
                front  = dy2 > 0 and "up" or "down"
                sides  = { "left", "right" }
            end
        end
        local teleX, teleY = pickEmpty(edgeCells(behind))
        if not teleX then
            for _, side in ipairs(sides) do
                teleX, teleY = pickEmpty(edgeCells(side))
                if teleX then break end
            end
        end
        if not teleX then teleX, teleY = pickEmpty(edgeCells(front)) end
        return teleX, teleY
    end

    -- 标记每个候选是否可突入
    for _, m in ipairs(candidates) do
        local tx, _ = findTeleportDest(m)
        m._offeringCanTele = (tx ~= nil)
    end
    -- 按优先级排序：可突入 > 远程 > 血少
    table.sort(candidates, function(a, b)
        local aT = a._offeringCanTele and 1 or 0
        local bT = b._offeringCanTele and 1 or 0
        if aT ~= bT then return aT > bT end
        local aR = (a.atkRange or 1) > 1 and 1 or 0
        local bR = (b.atkRange or 1) > 1 and 1 or 0
        if aR ~= bR then return aR > bR end
        return a.hp < b.hp
    end)
    local target = candidates[1]
    -- 清理临时标记
    for _, m in ipairs(candidates) do m._offeringCanTele = nil end

    -- 执行突袭（不授予攻击速度加成）
    local teleX, teleY = findTeleportDest(target)
    if teleX then
        attacker.x = teleX
        attacker.y = teleY
        M.addDamageText(attacker.x, attacker.y - 0.5, "献礼突袭", {220, 160, 80})
        M.performAttack(attacker, target, nil)
        M._pendingChaseArrow = { attacker = attacker, target = target }
    else
        M.addDamageText(target.x, target.y - 0.5, "无法突入!", {200, 200, 200})
        -- 突入失败：归还月影计数（献礼入队时已预扣）
        M._moonShadowMissed = (M._moonShadowMissed or 0) + 1
    end
    return true
end

-- ====================================================================
-- 深渊词缀：多重施法（辅助函数）
-- ====================================================================

--- 统计装备中指定深渊词缀的叠加层数（上限 3 + abyssAffixLimitBonus）
local ABYSS_AFFIX_BASE_MAX = 3
-- 装备槽遍历顺序（与 getEquipBonus 一致，用于面纱生效唯一判定）
local EQUIP_SLOT_ORDER = {
    "weapon_r", "weapon_l",
    "hat", "shoulder", "cloak", "chest", "gloves", "pants", "boots",
    "necklace", "belt", "trinket", "ring1", "ring2",
}
--- 计算当前深渊词缀生效上限（基础3 + 装备 abyssAffixLimitBonus）
local function getAbyssAffixMax()
    return ABYSS_AFFIX_BASE_MAX
end

--- 获取指定深渊词缀 mechanic 的额外生效上限（来自 abyssAffixLimitTarget）
local function getAbyssAffixMechanicBonus(mechanic)
    local bonus = 0
    if GS.equipment then
        local superiorSeen = {}
        for _, slotId in ipairs(EQUIP_SLOT_ORDER) do
            local slot = GS.equipment[slotId]
            if slot then
                -- 卓越装备生效唯一
                if slot.rarity == "superior" and slot.templateId then
                    if superiorSeen[slot.templateId] then goto continueAffixMB end
                    superiorSeen[slot.templateId] = true
                end
                if slot.abyssAffixLimitTarget and slot.abyssAffixLimitTarget.mechanic == mechanic then
                    local tpl = slot.templateId and GS.itemTemplates[slot.templateId]
                    bonus = bonus + (tpl and tpl.randomAbyssAffixLimit or 1)
                end
                ::continueAffixMB::
            end
        end
    end
    return bonus
end
local function countAbyssAffix(mechanic)
    local affixMax = getAbyssAffixMax() + getAbyssAffixMechanicBonus(mechanic)
    local count = 0
    local veilApplied = false  -- "朱莉"的面纱生效唯一标记
    local superiorApplied = {}  -- 卓越装备生效唯一
    if GS.equipment then
        for _, slotId in ipairs(EQUIP_SLOT_ORDER) do
            local slot = GS.equipment[slotId]
            if slot then
                -- 卓越装备生效唯一：同 templateId 只统计一次
                if slot.rarity == "superior" and slot.templateId then
                    if superiorApplied[slot.templateId] then
                        goto continueSlotAbyss
                    end
                    superiorApplied[slot.templateId] = true
                end
                if slot.abyssAffix and slot.abyssAffix.mechanic == mechanic then
                    count = count + 1
                    if count >= affixMax then return affixMax end
                end
                if slot.heroAffix and slot.heroAffix.mechanic == mechanic then
                    count = count + 1
                    if count >= affixMax then return affixMax end
                end
                -- 宝石槽内的深渊词缀（如"朱莉"的面纱）
                if slot.gemSlots then
                    for _, gs in ipairs(slot.gemSlots) do
                        -- 面纱生效唯一：只有第一颗面纱的词缀生效
                        if gs.gemId == "gem_rainbow_masterwork" then
                            if veilApplied then
                                goto continueGemAbyss
                            end
                            veilApplied = true
                        end
                        if gs.abyssAffix and gs.abyssAffix.mechanic == mechanic then
                            count = count + 1
                            if count >= affixMax then return affixMax end
                        end
                        ::continueGemAbyss::
                    end
                end
                ::continueSlotAbyss::
            end
        end
    end
    return count
end
M.countAbyssAffix = function(mechanic) return countAbyssAffix(mechanic) end

local getPlayerWeaponTag  -- 前向声明（实际定义在下方，供 isPlayerLittleZeus 等早期函数使用）

--- 判断玩家是否装备了"小宙斯"（锤+littleZeusRange>0）
local function isPlayerLittleZeus()
    local wTag = getPlayerWeaponTag()
    if wTag ~= "锤" then return false end
    local eb = GS.getEquipBonus and GS.getEquipBonus() or {}
    return (eb.littleZeusRange or 0) > 0
end

--- 聚焦器：统计被封印的词缀总数并计算增伤倍率
--- 统计所有来源（深渊词缀 + 装备特效 + 被动技能），但不含千军令
--- 千军令仅提供幻影额外用途（旋风斩），不增加幻影数量
--- 返回增伤百分比（已乘以生效条数），0 表示不生效
local function calcFocuserDmgBonus(attacker)
    local dmgPer = attacker.focuserDmgPer or 0
    local maxStacks = attacker.focuserMaxStacks or 0
    if dmgPer <= 0 or maxStacks <= 0 then return 0 end
    local count = 0
    -- 仅统计深渊词缀来源，装备/技能来源不计入（它们不受聚焦器屏蔽）
    -- 散射：仅深渊词缀（军火库箭袋、英雄长弓不计入）
    count = count + countAbyssAffix("ranged_scatter")
    -- 弹射：仅深渊词缀（英雄箭袋、英雄晶球不计入）
    count = count + countAbyssAffix("ranged_bounce")
    -- 幻影：仅深渊词缀（heroPhantom、月影满级被动不计入）
    count = count + countAbyssAffix("melee_phantom")
    -- 溅射：深渊词缀
    count = count + countAbyssAffix("melee_splash")
    -- 溅射范围扩展：深渊词缀
    count = count + countAbyssAffix("melee_splash_range")
    -- 技能范围扩展：深渊词缀
    count = count + countAbyssAffix("skill_aoe_range")
    -- 多重施法：深渊词缀
    count = count + countAbyssAffix("multi_cast")
    -- 辉光：深渊词缀
    count = count + countAbyssAffix("radiance")
    -- 闪电链：深渊词缀
    count = count + countAbyssAffix("chain_lightning")
    -- 利刺：深渊词缀
    count = count + countAbyssAffix("thorns")
    -- 极速冷却：深渊词缀
    count = count + countAbyssAffix("quick_cooldown")
    -- 千军令不计入（仅提供旋风斩幻影用途，不增加幻影数量）
    local stacks = math.min(count, maxStacks)
    if stacks <= 0 then return 0 end
    return stacks * dmgPer
end

--- 深渊词缀：技能范围+1（统计装备中的 skill_aoe_range 词缀数量）
local function getAoeRangeBonus()
    local bonus = 0
    -- 聚焦器：屏蔽技能范围扩展词缀
    if not (GS.player and (GS.player.focuserDmgPer or 0) > 0) then
        bonus = countAbyssAffix("skill_aoe_range")
    end
    -- 装备提供的技能范围加成（如托马斯：左手为空时+N）——不受聚焦器影响
    if GS.player and (GS.player.equipAoeBonus or 0) > 0 then
        bonus = bonus + GS.player.equipAoeBonus
    end
    return bonus
end

local function getMultiCastCount()
    -- 聚焦器：屏蔽多重施法
    if GS.player and (GS.player.focuserDmgPer or 0) > 0 then return 0 end
    return countAbyssAffix("multi_cast")
end

--- 判断技能是否为可触发多重远程技能的技能
--- 适配：法师魔法(useMagic)、刺客投掷(throwSkill)、猎人射击(reqWeaponTag="弓" 的主动技能)
local function isMultiCastableRangedSkill(skillId)
    if not skillId then return false end
    local def = GS.SKILL_DEFS[skillId]
    if not def then return false end
    if def.type ~= "active" then return false end
    -- 排除 buff/toggle/selfCast 类
    if def.selfCast then return false end
    if def.fireShieldBuff then return false end
    if def.magicShieldToggle then return false end
    if def.prayerBuff then return false end
    if def.holySpringBuff then return false end
    -- 法师魔法技能
    if def.useMagic then return true end
    -- 刺客投掷技能
    if def.throwSkill then return true end
    -- 猎人弓箭主动技能（排除散射，散射自身已有多目标）
    if def.reqWeaponTag == "弓" and not def.scatter then return true end
    return false
end

--- 在攻击范围内选取次级目标（排除已命中的目标列表）
--- @param caster table 施法者
--- @param excludes table 已排除目标列表
--- @param count number 需要选取的目标数量
--- @param range number 搜索范围（曼哈顿距离）
--- @return table 选中的次级目标列表
local function pickMultiCastTargets(caster, excludes, count, range)
    local candidates = {}
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 then
            local excluded = false
            for _, ex in ipairs(excludes) do
                if m == ex then excluded = true; break end
            end
            if not excluded then
                local dist = GS.manhattanToUnit(caster.x, caster.y, m)
                if dist <= range then
                    candidates[#candidates + 1] = { target = m, dist = dist }
                end
            end
        end
    end
    table.sort(candidates, function(a, b) return a.dist < b.dist end)
    local result = {}
    for i = 1, math.min(count, #candidates) do
        result[#result + 1] = candidates[i].target
    end
    return result
end

--- 幻影专用目标选取：优先远程 > 生命比例低 > 距离近
--- @param caster table 施法者
--- @param count number 需要选取的目标数量
--- @param range number 搜索范围（曼哈顿距离）
--- @return table 选中的目标列表
local function pickPhantomTargets(caster, count, range)
    local candidates = {}
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 then
            local dist = GS.manhattanToUnit(caster.x, caster.y, m)
            if dist <= range then
                local isRanged = (m.atkRange or 1) > 1
                local hpRatio = m.hp / (m.maxHp or m.hp)
                candidates[#candidates + 1] = { target = m, dist = dist, isRanged = isRanged, hpRatio = hpRatio }
            end
        end
    end
    table.sort(candidates, function(a, b)
        -- 1) 远程优先
        if a.isRanged ~= b.isRanged then return a.isRanged end
        -- 2) 生命比例低优先
        if a.hpRatio ~= b.hpRatio then return a.hpRatio < b.hpRatio end
        -- 3) 距离近优先
        return a.dist < b.dist
    end)
    local result = {}
    for i = 1, math.min(count, #candidates) do
        result[#result + 1] = candidates[i].target
    end
    return result
end

-- 导出多重施法辅助函数，供 Combat_AOE.lua 使用
M._isMultiCastableRangedSkill = isMultiCastableRangedSkill
M._getMultiCastCount    = getMultiCastCount
M._pickMultiCastTargets = pickMultiCastTargets

--- 哈雷努拉：祝福术/超度 AOE 化 — 前向声明（实际实现在 calcSkillDamage 等定义之后）
local isHolyAoeSkill   ---@type fun(def: table): boolean
local handleHolyAoe    ---@type fun(attacker: table, target: table, skillId: string, def: table): boolean

--- 技能处理器注册表
--- field: 技能定义中的标识字段（匹配条件）
--- match: 自定义匹配函数（优先于 field）
--- noBreakStealth: 施放时不解除隐匿
--- handler: 处理函数(attacker, target, skillId, def)
local SKILL_HANDLERS = {
    -- 哈雷努拉：祝福术/超度 AOE 化（优先级高，必须在默认路径前拦截）
    -- 注意：用包装函数延迟引用，因为实际实现在文件后方才赋值
    { match = function(def) return isHolyAoeSkill and isHolyAoeSkill(def) end,
      noBreakStealth = false,
      handler = function(a, t, s, d) return handleHolyAoe(a, t, s, d) end },
    -- 银色狮子：强击/超强击/碎星 AOE 化
    { match = function(def) return isStrikeAoeSkill and isStrikeAoeSkill(def) end,
      noBreakStealth = false,
      handler = function(a, t, s, d) return handleStrikeAoe(a, t, s, d) end },
    { field = "stormBuff",    noBreakStealth = true,  handler = handleStormBuff },
    { field = "stealthBuff",  noBreakStealth = true,  handler = handleStealthBuff },
    -- focusBuff 已改为被动，不再需要主动施法入口
    { field = "fireShieldBuff",   noBreakStealth = true, handler = handleFireShieldBuff },
    { field = "magicShieldToggle", noBreakStealth = true, handler = handleMagicShieldToggle },
    { match = isBlessingBuff,  noBreakStealth = true,  handler = handleBlessingBuff },
    { field = "restoreHeal",  noBreakStealth = true,  handler = handleRestoreHeal },
    { field = "iceRingAoe",      noBreakStealth = false, handler = handleIceRingAOE },
    { field = "chainLightning", noBreakStealth = false, handler = handleChainLightning },
    { field = "thunderCloud",   noBreakStealth = false, handler = handleThunderCloud },
    { field = "aoe",             noBreakStealth = false, handler = handleAOE },
    { field = "scatter",      noBreakStealth = false, handler = handleScatter },
    { field = "charge",       noBreakStealth = false, handler = handleCharge },
    { field = "sandBlind",    noBreakStealth = false, handler = handleSandBlind },
    { field = "phantom",      noBreakStealth = true,  handler = handlePhantom },
    { field = "flashAssault", noBreakStealth = false, handler = handleFlashAssault },
}

--- 判断技能是否为不破隐的 buff 类技能（由注册表驱动）
local function isNonBreakSkill(def)
    for _, entry in ipairs(SKILL_HANDLERS) do
        if entry.noBreakStealth then
            if entry.field and def[entry.field] then return true end
            if entry.match and entry.match(def) then return true end
        end
    end
    return false
end

--- 分发技能到注册表处理器（返回 true 表示已处理）
local function dispatchSkillHandler(attacker, target, skillId, def)
    for _, entry in ipairs(SKILL_HANDLERS) do
        local matches = false
        if entry.match then
            matches = entry.match(def)
        elseif entry.field then
            matches = def[entry.field]
        end
        if matches then
            return entry.handler(attacker, target, skillId, def)
        end
    end
    return false
end

-- ====================================================================
-- 待执行动作（等待移动动画完成后执行）
-- ====================================================================
M.pendingAutoAction = nil   -- 自动战斗移动后的待执行攻击
M.pendingManualAction = nil -- 手动操作移动后的待执行行动
M.pendingAutoGather = nil   -- 自动采集移动后的待执行采集
M.pendingStageSwitch = nil  -- 自动战斗中延迟执行的地图切换回调

--- 地狱踏：沿移动路径放置燃烧地面（含终点）
--- @param path table 移动路径 {{x,y}, ...}
function M.placeHellStompBurning(path)
    if not GS.player or GS.player.isMonster then return end
    if (GS.player.hellStompBurnPct or 0) <= 0 then return end
    if not path or #path < 2 then return end
    local placed = {}
    for i = 1, #path do
        local px, py = path[i][1], path[i][2]
        if px >= 1 and px <= GS.BOARD_SIZE and py >= 1 and py <= GS.BOARD_SIZE then
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
            placed[#placed + 1] = { x = px, y = py }
        end
    end
    GS._hellStompPlaced = placed
end

--- 判断自动战斗回合是否正在进行中（非玩家待命状态）
function M.isTurnBusy()
    if not GS.autoMode then return false end
    if GS.gameState ~= GS.STATE_PLAYER then return true end
    if GS.player and GS.player.acted then return true end
    if M.chainActive then return true end
    if GS.pendingEndPlayerTurn then return true end
    return false
end

--- 切换地图时清理所有残留战斗状态（待执行动作、猎犬目标等）
function M.clearPendingState()
    M.pendingAutoAction = nil
    M.pendingManualAction = nil
    M.pendingAutoGather = nil
    GS.pendingBounces = {}
    GS.lastPlayerTarget = nil
    for _, c in ipairs(GS.companions) do
        c.plannedAttack = nil
        c.plannedTarget = nil
    end
end

--- 每帧检查：玩家移动动画结束后执行待定动作
function M.processPendingActions(dt)
    -- 玩家移动动画仍在播放，等待
    if GS.player and GS.player.moveAnim then return end

    -- 自动战斗待定动作
    if M.pendingAutoAction then
        local pa = M.pendingAutoAction
        M.pendingAutoAction = nil

        -- 标记本回合是否移动（供静神被动判定）
        if pa.movePath and #pa.movePath >= 2 then
            GS._playerMovedThisTurn = true
        end
        -- 地狱踏：自动战斗移动后放置燃烧地面
        M.placeHellStompBurning(pa.movePath)

        local isCaster = (GS.currentClass == "mage" or GS.currentClass == "priest")
        local wTag = GS.equipment and GS.equipment["weapon_r"] and GS.equipment["weapon_r"].weaponTag
        local isStaffWeapon = (wTag == "法杖")
        local isMeleeCasterWeapon = isCaster and wTag ~= "法杖"

        local useSkillId = nil
        if pa.target and pa.target.hp > 0 and GS.player and GS.player.hp > 0 then
            -- 施法职业自动战斗：选段数足够的技能（优先使用移动时确定的技能）
            useSkillId = pa.forcedSkillId or GS.pickActiveSkill()
            if isCaster and useSkillId then
                local stages = GS.getSkillCastStages(useSkillId)
                if stages > 0 and (GS.chantStages or 0) < stages then
                    useSkillId = nil  -- 段数不够，回退普攻
                end
            end
            -- 法杖普攻需要1段，段数不足则无法攻击（近战武器普攻不需要段数）
            if not useSkillId and isCaster and isStaffWeapon and (GS.chantStages or 0) < 1 then
                -- 段数不足，跳过攻击
            else
                GS.lastActionTargetX = pa.target.x
                GS.lastActionTargetY = pa.target.y
                GS.lastActionAoeRadius = nil
                -- groundTarget 技能（火球术/陨石术/暴风雪/落雷术等）走专用 AOE 流程
                local useDef = useSkillId and GS.SKILL_DEFS[useSkillId]
                if useDef and useDef.groundTarget and not useDef.selfCast then
                    -- 吟唱段数由下方统一消耗逻辑处理，此处不重复扣除
                    local aoeR = useDef.fireballRadius or useDef.meteorRadius or useDef.blizzardRadius or useDef.thunderAoeRadius or 0
                    if aoeR == 0 and (useDef.iceRingAoe or useDef.holyTree) then aoeR = 1 end
                    GS.lastActionAoeRadius = aoeR > 0 and aoeR or nil
                    M.addSkillCastText(GS.player.x, GS.player.y, useSkillId)
                    M.executeGroundSkill(GS.player, useSkillId, pa.target.x, pa.target.y)
                    -- 多重施法已移入 executeGroundSkill 内部统一处理
                else
                    M.executePlayerAttack(GS.player, pa.target, useSkillId)
                end
            end
        end

        -- 深度思维：每次行动前重置增伤
        if GS.player then GS.player._deepThinkBonus = 0 end
        -- 祝福术/超度：无论目标是否存活，都消耗全部剩余吟唱段数
        if isCaster and useSkillId and (useSkillId == "p_bless" or useSkillId == "p_exorcism") then
            -- 深度思维：清空吟唱并计算额外增伤
            if GS.player and (GS.player.deepThinkDmgPer or 0) > 0 and (GS.chantStages or 0) > 0 then
                local stagesNeeded = GS.getSkillCastStages(useSkillId)
                local extra = math.max(0, (GS.chantStages or 0) - stagesNeeded)
                if extra > 0 then
                    GS.player._deepThinkBonus = extra * GS.player.deepThinkDmgPer
                end
            end
            GS.chantStages = 0
        -- 施法职业近战武器普攻：消耗全部剩余吟唱段数
        elseif not useSkillId and isMeleeCasterWeapon then
            GS.chantStages = 0
        -- 法杖普攻：消耗1段（无论目标是否存活）
        elseif not useSkillId and isCaster and isStaffWeapon then
            GS.chantStages = math.max(0, (GS.chantStages or 0) - 1)
        -- 地面技能（火球术/陨石术/暴风雪/落雷术等）：无目标 HP 判断，直接消耗吟唱段数
        elseif isCaster and useSkillId and GS.SKILL_DEFS[useSkillId] and GS.SKILL_DEFS[useSkillId].groundTarget and GS.player and GS.player.hp > 0 then
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
        -- 施法职业吟唱段数消耗（目标和玩家都存活时）
        elseif isCaster and pa.target and pa.target.hp > 0 and GS.player and GS.player.hp > 0 then
            if useSkillId then
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
        end

        M.removeDeadMonsters()

        -- 施法职业回合继续判断
        if isCaster and (GS.chantStages or 0) > 0 and not GS.chanting then
            -- 检查攻击范围内是否有敌人（排除已击晕的肉搏混混）
            local hasTarget = false
            local atkRange = GS.player.atkRange or 1
            for _, m in ipairs(GS.monsters) do
                if m.hp > 0 and not m.brawlStunned and GS.manhattanToUnit(GS.player.x, GS.player.y, m) <= atkRange then
                    hasTarget = true
                    break
                end
            end
            if not hasTarget then
                -- 检查可用技能范围
                local sk = GS.pickActiveSkill()
                if sk then
                    local sd = GS.SKILL_DEFS[sk]
                    local stages = GS.getSkillCastStages(sk)
                    if stages <= 0 or (GS.chantStages or 0) >= stages then
                        if sd and sd.selfCast then
                            hasTarget = true
                        else
                            local sr = sd and sd.skillRange or atkRange
                            for _, m in ipairs(GS.monsters) do
                                if m.hp > 0 and not m.brawlStunned and GS.manhattanToUnit(GS.player.x, GS.player.y, m) <= sr then
                                    hasTarget = true
                                    break
                                end
                            end
                        end
                    end
                end
            end

            if hasTarget then
                -- 法师继续行动：重置阶段
                GS.mageActionTaken = true
                GS.turnPhase = GS.PHASE_ACTION
                GS.autoTimer = -(GS.AUTO_DELAY * 2)  -- 法师连续使用段数间隔：总等待约0.45秒
                return
            end
        end

        GS.advanceTurnPhase()
        GS.player.acted = true
        if M.startChainIfNeeded(function()
            M.endPlayerTurn()
        end) then
            -- 连击队列中
        else
            M.endPlayerTurn()
        end
        return
    end

    -- 手动操作待定动作
    -- 自动采集待定动作（移动到采集物旁后开始采集）
    if M.pendingAutoGather then
        local g = M.pendingAutoGather
        M.pendingAutoGather = nil
        -- 检查目标是否仍然有效（未消失且仍有采集次数）
        if not g.vanishing and (g.harvestsLeft or 1) > 0 then
            GS.advanceTurnPhase()  -- ACTION → END
            GS.movableCells = {}
            GS.attackableCells = {}
            GS.selectedUnit = nil
            GS.gameState = GS.STATE_PLAYER  -- 确保退出 SELECT 状态
            local playerHLv = GS.getLifeSkillHiddenLevel(g.lifeSkill or "gathering")
            local gatherHLv = g.hiddenLevel or 0
            local lvDiff = playerHLv - gatherHLv
            local ppt = lvDiff >= 200 and 1.0 or (lvDiff >= 100 and 0.50 or 0.34)
            GS.gatheringState = {
                target      = g,
                progress    = 0,
                turnCount   = 0,
                successRate = GS.calcGatherSuccessRate(playerHLv, gatherHLv),
                progressPerTurn = ppt,
            }
            return
        end
    end

    if M.pendingManualAction then
        local pm = M.pendingManualAction
        M.pendingManualAction = nil

        -- 标记本回合是否移动（供静神被动判定）
        if pm.movePath and #pm.movePath >= 2 then
            GS._playerMovedThisTurn = true
        end
        -- 地狱踏：移动后在路径上放置燃烧地面
        M.placeHellStompBurning(pm.movePath)

        GS.attackableCells = GS.getAttackableCells(GS.selectedUnit, GS.selectedUnit.x, GS.selectedUnit.y)

        local hasTarget = false
        for _, m in ipairs(GS.monsters) do
            if m.hp > 0 and GS.attackableCells[GS.cellKey(m.x, m.y)] then
                hasTarget = true
                break
            end
        end

        if not GS.autoMode then
            GS.movableCells = {}
            GS.actionMenuVisible = true
            GS.actionChoice = nil
            GS.actionChosenSkillId = nil
            GS.actionPreMoveX = pm.oldX
            GS.actionPreMoveY = pm.oldY
        else
            if not hasTarget then
                GS.advanceTurnPhase()
                GS.selectedUnit.acted = true
                GS.selectedUnit = nil
                GS.movableCells = {}
                GS.attackableCells = {}
                M.endPlayerTurn()
            else
                GS.movableCells = {}
            end
        end
        return
    end
end

-- ====================================================================
-- 通用：玩家死亡检查，触发复活流程。返回 true 表示已阵亡
-- ====================================================================
function M.checkPlayerDeath()
    if GS.gameState == GS.STATE_RESPAWN then return true end  -- 已在复活中，不重复触发
    if not GS.player then return true end  -- 玩家对象不存在，视为已阵亡
    if GS.player.hp <= 0 then
        -- 酒馆肉搏：玩家被打倒 → 1滴血回清水镇，不走正常死亡流程
        -- 如果胜利已触发（done），优先走胜利流程，不触发死亡
        if GS.tavernBrawlState and not GS.tavernBrawlState.done then
            GS.player.hp = 1
            GS.chanting = nil
            local DM = require("DialogueManager")
            DM.startDynamic({
                { speaker = "旁白", text = "（你被混混们打倒在地……安吉莉娅赶紧跑来扶起了你。）" },
                { speaker = "安吉莉娅", text = "你没事吧？快离开这里……" },
            }, function()
                GS.tavernBrawlState = nil
                GS.startSceneTransition(function()
                    GS.currentBattleBg = "image/bg_grass.png"
                    GS.currentAreaName = "清水镇"
                    GS.currentStageName = "清水镇"
                    BoardOverlay.show("town", "clearwater", "清水镇")
                    print("[酒馆肉搏] 玩家被打倒，1滴血返回清水镇")
                end)
            end)
            return true
        end

        -- 【重生】铸甲匠项链被动：抵挡致死伤害，保留1点HP（3天CD）
        if (GS.player.rebirth or 0) > 0 then
            local currentDay = math.floor(((GS.weatherTime or 1) - 1) / 1440)
            local cdDay = GS.rebirthCooldownDay or -999
            if currentDay >= cdDay + 3 then
                -- 重生触发：保留1HP，进入3天冷却
                GS.player.hp = 1
                GS.rebirthCooldownDay = currentDay
                print("[重生] 铸甲匠项链被动触发！抵挡致死伤害，保留1HP (CD至第" .. (currentDay + 3) .. "天)")
                -- 显示特效提示
                table.insert(GS.damageTexts, {
                    x = GS.player.x, y = GS.player.y,
                    text = "重生！", color = {255, 215, 0},
                    timer = 0, duration = 1.5,
                    floatSpeed = 25, fontSize = 18,
                })
                return false  -- 没有死亡，继续游戏
            end
        end

        GS.chanting = nil
        GS.deathX, GS.deathY = GS.player.x, GS.player.y

        -- 玩家死亡特效（与怪物同款：缩小+变红+淡出+粒子飘散）
        local particles = {}
        local pCount = math.random(8, 12)
        for pi = 1, pCount do
            local angle = math.random() * math.pi * 2
            local speed = 20 + math.random() * 30
            particles[pi] = {
                ox = 0, oy = 0,
                vx = math.cos(angle) * speed,
                vy = math.sin(angle) * speed - 15,
                size = 2 + math.random() * 3,
            }
        end
        local deathDelay = 0
        local deathPending = false
        local deathProjId = nil
        for _, d in ipairs(GS.damageTexts) do
            if d.x == GS.player.x and d.y == GS.player.y then
                if d.pendingHit then
                    deathPending = true
                    deathProjId = d.projectileId
                end
                if d.delay and d.delay > deathDelay then deathDelay = d.delay end
            end
        end
        table.insert(GS.deathEffects, {
            x = GS.player.x, y = GS.player.y,
            isPlayer = true,
            unitScale = 1,
            timer = 0, duration = 0.55,
            particles = particles,
            delay = deathDelay,
            pendingHit = deathPending,
            projectileId = deathProjId,
        })

        -- 死亡惩罚：30级以上扣除10%最大经验值，等级不下降，最低为0
        if GS.player.level >= 30 then
            local maxExp = GS.expToNextLevel(GS.player.level)
            local penalty = math.floor(maxExp * 0.10)
            GS.player.exp = math.max(0, GS.player.exp - penalty)
            GS.displayExp = GS.player.exp
            print("=== 死亡惩罚: 扣除经验 " .. penalty .. " (当前 " .. GS.player.exp .. "/" .. maxExp .. ") ===")
        end

        -- 清除不可知物凝视 debuff
        if (GS.player._unknownGaze or 0) > 0 then
            print("[不可知物] 玩家死亡，凝视消散 (移除 " .. GS.player._unknownGaze .. " 层)")
            GS.player._unknownGaze = 0
            GS.player._gazePer = 0
            GS.player._gazeFoc = 0
            GS.recalcStats(GS.player)
        end

        -- 异世深渊：扣减生命次数
        if GS.isAbyssWorld then
            GS.abyssWorldLives = GS.abyssWorldLives - 1
            print("=== 异世深渊: 剩余生命 " .. GS.abyssWorldLives .. "/" .. GS.ABYSS_WORLD_MAX_LIVES .. " ===")
            if GS.abyssWorldLives <= 0 then
                -- 最后一条命用完，通道关闭
                GS.abyssWorldActive = false
                print("=== 异世深渊: 通道关闭 ===")
                -- 立即存档，防止强退后状态未保存
                GS.saveToCloud()
            end
        end

        -- 史莱姆国王大反击：保存历史最高累积伤害到云端（账户级）
        if GS.currentStage == GS.STAGE_SLIME_KING_REVENGE then
            local accDmg = GS.slimeRevengeAccDmg or 0
            if accDmg > (GS.slimeRevengeBestDmg or 0) then
                local oldBest = GS.slimeRevengeBestDmg or 0
                GS.slimeRevengeBestDmg = accDmg
                if clientCloud then
                    -- 同时保存总排行伤害 + 职业专属排行伤害
                    local cls = GS.currentClass or "warrior"
                    local classKey = "slime_rev_" .. cls
                    local batch = clientCloud:BatchSet()
                        :SetInt("slime_revenge_best", accDmg)
                        :SetInt(classKey, accDmg)
                    -- 只有当本次伤害刷新了总榜最高时，才更新职业标识
                    -- （SetInt 保留最大值，但 Set 会覆写，需本地比较）
                    if accDmg > oldBest then
                        batch:Set("slime_rev_class", cls)
                    end
                    batch:Save("[大反击] 保存最高伤害+职业", {
                        ok = function()
                            print("[大反击] 历史最高伤害已保存: " .. accDmg .. " 职业: " .. cls)
                        end,
                        error = function(code, reason)
                            print("[大反击] 保存最高伤害失败: " .. tostring(code) .. " " .. tostring(reason))
                        end,
                    })
                end
            end
        end

        -- 迪哈塔大反击：保存历史最高累积伤害到云端（账户级）
        if GS.currentStage == GS.STAGE_DIHATA_REVENGE then
            local accDmg = math.floor(GS.dihataRevengeAccDmg or 0)
            local bestDmg = GS.dihataRevengeBestDmg or 0
            if accDmg > bestDmg then
                local oldBest = GS.dihataRevengeBestDmg or 0
                GS.dihataRevengeBestDmg = accDmg
                if clientCloud then
                    local cls = GS.currentClass or "warrior"
                    local classKey = "dihata_rev_" .. cls
                    local batch = clientCloud:BatchSet()
                        :SetInt("dihata_revenge_best", accDmg)
                        :SetInt(classKey, accDmg)
                    if accDmg > oldBest then
                        batch:Set("dihata_rev_class", cls)
                    end
                    batch:Save("[迪哈塔大反击] 保存最高伤害+职业", {
                        ok = function()
                            print("[迪哈塔大反击] 历史最高伤害已保存: " .. accDmg .. " 职业: " .. cls)
                        end,
                        error = function(code, reason)
                            print("[迪哈塔大反击] 保存最高伤害失败: " .. tostring(code) .. " " .. tostring(reason))
                        end,
                    })
                end
            end
        end

        -- 大反击关卡：死亡即结束，立即存档防止作弊
        if GS.currentStage == GS.STAGE_SLIME_KING_REVENGE then
            GS.saveToCloud()
            print("=== 史莱姆大反击: 死亡，已存档 ===")
        end
        if GS.currentStage == GS.STAGE_DIHATA_REVENGE then
            GS.saveToCloud()
            print("=== 迪哈塔大反击: 死亡，已存档 ===")
        end

        GS.gameState = GS.STATE_RESPAWN
        GS.respawnTimer = GS.RESPAWN_TIME
        GS.respawnMoveCD = 0
        GS.tombstoneAnim = nil
        GS.tombstoneDropAnim = { timer = 0, duration = 0.4 }
        GS.selectedUnit = nil
        GS.movableCells = {}
        GS.attackableCells = {}
        -- 猎人死亡时移除所有猎犬（复活时会重新生成）
        for i = #GS.companions, 1, -1 do
            if GS.companions[i].isHound then
                table.remove(GS.companions, i)
            end
        end
        print("=== 玩家阵亡! 复活倒计时 " .. GS.RESPAWN_TIME .. " 秒 ===")
        return true
    end
    return false
end

-- ====================================================================
-- 连击队列（攻速连击延迟执行）
-- ====================================================================
M.chainQueue = {}        -- 待执行的额外攻击队列
M.chainTimer = 0         -- 当前延迟计时器
M.chainDelay = 0.3       -- 每次连击间隔（秒）
M.stormHitCounts = {}    -- 暴雨被动：回合内对各目标的命中次数
M.chainActive = false    -- 是否正在处理连击队列
M.chainCallback = nil    -- 连击全部完成后的回调
M._projectileIdCounter = 0   -- 弹道ID计数器（每个弹道唯一）
M._currentProjectileId = nil -- 当前弹道ID（addDamageText时关联）

--- 连击队列是否正在处理中
function M.isChaining()
    return M.chainActive
end

--- 处理连击队列（每帧调用）
function M.updateChainAttacks(dt)
    if not M.chainActive or #M.chainQueue == 0 then return end

    M.chainTimer = M.chainTimer - dt
    if M.chainTimer > 0 then return end

    -- 取出下一个连击
    local entry = table.remove(M.chainQueue, 1)
    local didAct = false  -- 是否产生了实际动作（用于决定是否需要间隔延迟）
    -- 通用动作类型（风暴旋风斩、衍生飓风等）
    if entry.action then
        entry.action()
        didAct = true
    else
        -- 主目标已死亡时的处理
        local target = entry.defender
        if target.hp <= 0 then
            if entry.attacker.isMonster then
                -- 怪物连击：目标死亡直接停止，不转火（避免误打自己或友军）
                target = nil
            else
                -- 玩家/同伴连击：转火到普攻范围内最近的存活敌人
                local atk = entry.attacker
                local atkRange = atk.atkRange or 1
                local bestDist = math.huge
                local bestTarget = nil
                for _, m in ipairs(GS.monsters) do
                    if m.hp > 0 and not m.brawlStunned then
                        local dist = GS.manhattanToUnit(atk.x, atk.y, m)
                        if dist <= atkRange and dist < bestDist then
                            bestDist = dist
                            bestTarget = m
                        end
                    end
                end
                target = bestTarget
            end
        end
        if target then
            didAct = true
            M.addDamageText(entry.attacker.x, entry.attacker.y - 0.5, entry.label, entry.color)
            -- 设置标志：连击攻击不再触发攻速连击
            entry.attacker._atkSpeedChaining = true
            -- 双持连击标志：防止双持第二击再触发双持入队
            if entry.isDualDagger then
                entry.attacker._dualDaggerChaining = true
            end
            -- 二连击标志：阻止再次二连击和攻速连击（_atkSpeedChaining 保持 true）
            if entry.isDoubleStrike then
                entry.attacker._doubleStrikeChaining = true
            end
            M.performAttack(entry.attacker, target, nil)
            -- 连击可触发散射（散射内部已阻止反向触发连击）
            applyRangedScatter(entry.attacker, target)
            entry.attacker._atkSpeedChaining = nil
            entry.attacker._dualDaggerChaining = nil
            entry.attacker._doubleStrikeChaining = nil
        else
            -- 月影：目标死亡且无转火目标，记录未打出的连击次数
            -- 双持第二击不单独计算月影（与主攻击作为一组，只算1次）
            if not entry.action and entry.attacker == GS.player and not entry.isDualDagger then
                M._moonShadowMissed = (M._moonShadowMissed or 0) + 1
            end
        end
    end

    -- 设置下一次延迟：有实际动作时正常间隔，空跑时跳过
    M.chainTimer = didAct and M.chainDelay or 0

    -- 队列清空后结束连击状态
    if #M.chainQueue == 0 then
        M.chainActive = false
        -- 献礼：连击中断时自动闪烁突袭（优先于月影结算）
        if not M._offeringDone then
            M._offeringDone = true
            local moonMissed = M._moonShadowMissed or 0
            -- _offeringMissed：击杀目标时预计入的非双持连击数
            -- 取二者较大值确保击杀后连击转火成功时也能触发献礼
            local missed = math.max(moonMissed, M._offeringMissed or 0)
            local p = GS.player
            local maxFlash = p and (p.offeringAutoFlashMax or 0) or 0
            if missed > 0 and maxFlash > 0 and p and p.hp > 0 then
                -- 检查范围内是否有存活目标，无目标时跳过献礼（避免空跑延迟）
                local baseRange = 3
                local bonusRange = p and (p.offeringFlashRangeBonus or 0) or 0
                local totalRange = baseRange + bonusRange
                local hasAlive = false
                for _, m in ipairs(GS.monsters) do
                    if m.hp > 0 and not m.brawlStunned and GS.manhattanToUnit(p.x, p.y, m) <= totalRange then
                        hasAlive = true; break
                    end
                end
                if hasAlive then
                    local count = math.min(missed, maxFlash)
                    for i = 1, count do
                        M.chainQueue[#M.chainQueue + 1] = {
                            action = function()
                                offeringAutoFlashAssault(GS.player)
                            end
                        }
                    end
                    -- 月影剩余量从 moonMissed 中扣除（不能用 missed，否则预计入会错误给月影加层）
                    M._moonShadowMissed = math.max(0, moonMissed - count)
                    M.chainActive = true
                    M.chainTimer = M.chainDelay
                    return
                end
            end
        end
        -- 月影：未打出的连击叠加闪避BUFF（献礼消耗后剩余的中断次数）
        if (M._moonShadowMissed or 0) > 0 and (GS.skillLevels["a_moon_shadow"] or 0) > 0 then
            local missed = M._moonShadowMissed
            local p = GS.player
            local oldStacks = p._moonShadowStacks or 0
            p._moonShadowStacks = oldStacks + missed
            M.addDamageText(p.x, p.y - 0.5, "月影+" .. missed, {120, 160, 255})
        end
        M._moonShadowMissed = nil
        M._offeringDone = nil
        M._offeringMissed = nil
        -- 连击全部结束后触发追身箭（收尾一箭）
        M.flushPendingChaseArrow()
        -- 追身箭入队后继续处理链式队列，不要提前结束回合
        if M.chainActive then return end
        M.removeDeadMonsters()
        if M.chainCallback then
            local cb = M.chainCallback
            M.chainCallback = nil
            cb()
        end
    end
end

--- 触发暂存的追身箭（所有连击结束后调用）
--- 将追身箭作为 chainQueue 条目排队，让弹道飞行动画可见
function M.flushPendingChaseArrow()
    local pending = M._pendingChaseArrow
    M._pendingChaseArrow = nil
    if not pending then return end
    -- 检查追身箭是否应触发（提前校验，避免无效入队）
    local attacker = pending.attacker
    if not attacker or attacker.isMonster or attacker.isCompanion then return end
    local lv = GS.skillLevels["h_chase_arrow"] or 0
    if lv <= 0 then return end
    local target = pending.target
    -- 不再要求目标存活，执行时由 triggerChaseArrow 转火
    -- 入队：追身箭排在所有连击后面，使用更长的延迟让前一个伤害飘字充分错开
    table.insert(M.chainQueue, {
        action = function()
            M.triggerChaseArrow(attacker, target)
        end,
    })
    if not M.chainActive then
        M.chainActive = true
    end
    M.chainTimer = 0.45  -- 追身箭专用延迟（默认连击 0.2s 太短，飘字会重叠）
end

--- 启动连击队列处理（由调用方在攻击后调用）
function M.startChainIfNeeded(callback)
    if #M.chainQueue > 0 then
        M.chainActive = true
        M.chainTimer = M.chainDelay
        M.chainCallback = callback
        return true  -- 有连击，调用方应延迟结束回合
    end
    -- 无连击，尝试将追身箭入队
    M.flushPendingChaseArrow()
    -- 追身箭可能入队了，再次检查
    if #M.chainQueue > 0 then
        M.chainCallback = callback
        return true
    end
    return false  -- 无连击也无追身箭，调用方立即结束回合
end

-- ====================================================================
-- 音效播放
-- ====================================================================
--- 通用音效播放
---@param sfx userdata 音效资源
---@param gain number 音量增益
local function playSound(sfx, gain)
    if not sfx or not M.scene_ then return end
    local soundNode = M.scene_:CreateChild("SFX")
    local source = soundNode:CreateComponent("SoundSource")
    source.gain = gain * GS.masterVolume
    source.autoRemoveMode = REMOVE_COMPONENT
    source:Play(sfx)
end

local function playAttackSound(weaponTag)
    if weaponTag == "锤" and M.sfxMaceHit then
        playSound(M.sfxMaceHit, 0.6)
    else
        playSound(M.sfxAttack, 0.6)
    end
end
function M.playSlimeHitSound()   playSound(M.sfxSlimeHit, 0.5) end
function M.playTauntSound()      playSound(M.sfxTaunt, 0.7) end
function M.playWhirlwindSound()  playSound(M.sfxWhirlwind, 0.7) end
function M.playShieldBlockSound()
    playSound(M.sfxShieldBlock, 2.0)
end

-- ====================================================================
-- 战斗工具函数
-- ====================================================================

--- 百分比伤害加成
---@param attacker table
---@param dmg number
---@return number
local function applyDmgPctBonus(attacker, dmg)
    local totalPct = (attacker.dmgPctBonus or 0)
    -- 聚焦器：封印词缀增伤（与装备加成叠加）
    if not attacker.isMonster then
        totalPct = totalPct + calcFocuserDmgBonus(attacker)
    end
    if totalPct > 0 then
        dmg = math.floor(dmg * (1 + totalPct / 100))
        dmg = math.max(1, dmg)
    end
    return dmg
end

--- 标记目标伤害加成（猎人/猎犬攻击被标记目标时）
---@param attacker table
---@param defender table
---@param dmg number
---@return number
local function applyMarkBonus(attacker, defender, dmg)
    if not GS.markedTarget or GS.markedTarget ~= defender then return dmg end
    if GS.markedTarget.hp <= 0 then GS.markedTarget = nil; return dmg end
    if attacker.isMonster then return dmg end -- 只有玩家和猎犬享受加成
    local lv = GS.skillLevels["h_mark_target"] or 0
    if lv <= 0 then return dmg end
    local def = GS.SKILL_DEFS["h_mark_target"]
    if not def then return dmg end
    local bonusPct = (def.markDmgPctPerLv or 1) * lv
    dmg = math.floor(dmg * (1 + bonusPct / 100))
    return math.max(1, dmg)
end

--- 元素熟练 → 技能ID 映射
local ELEMENT_PROF_MAP = {
    fire    = "m_fire_prof",
    ice     = "m_ice_prof",
    thunder = "m_elec_prof",
}

local ELEMENT_MASTER_MAP = {
    fire    = "m_fire_master",
    ice     = "m_ice_master",
    thunder = "m_elec_master",
}

--- 元素属性 → 玩家抗性字段映射
local ELEMENT_RES_MAP = {
    fire    = "resFire",
    ice     = "resIce",
    thunder = "resElec",
    light   = "resLight",
    shadow  = "resDark",
    nature  = "resNature",
}

--- 元素熟练+专精伤害加成：按伤害属性（fire/ice/thunder）应用对应被动加成
---@param dmg number
---@param element string|nil  伤害属性："fire"/"ice"/"thunder"
---@return number
local function applyElementBonus(dmg, element)
    if not element then return dmg end
    local totalPct = 0
    -- 熟练加成
    local profId = ELEMENT_PROF_MAP[element]
    if profId then
        local lv = GS.skillLevels[profId] or 0
        if lv > 0 then
            local profDef = GS.SKILL_DEFS[profId]
            if profDef then
                totalPct = totalPct + (profDef.elementProfPctPerLv or 1) * lv
            end
        end
    end
    -- 专精加成
    local masterId = ELEMENT_MASTER_MAP[element]
    if masterId then
        local lv = GS.skillLevels[masterId] or 0
        if lv > 0 then
            local masterDef = GS.SKILL_DEFS[masterId]
            if masterDef then
                totalPct = totalPct + (masterDef.elementMasterPctPerLv or 2) * lv
            end
        end
    end
    if totalPct > 0 then
        local orig = dmg
        dmg = math.floor(dmg * (1 + totalPct / 100))
        if dmg <= orig then dmg = orig + 1 end
    end
    -- 天气元素伤害倍率（全场所有单位）
    local weMul = WE.getElementDmgMul(element)
    if weMul ~= 1.0 then
        dmg = math.max(1, math.floor(dmg * weMul))
    end
    return math.max(1, dmg)
end

--- 猎人攻击后标记目标（替换之前的标记）
---@param attacker table
---@param defender table
local function tryMarkTarget(attacker, defender)
    if attacker.isMonster or attacker.isCompanion then return end
    if not defender or not defender.isMonster then return end
    local lv = GS.skillLevels["h_mark_target"] or 0
    if lv <= 0 then return end
    GS.markedTarget = defender
end

--- 元素熟练魔法暴击加成：施展对应元素法术时，获得该元素熟练提供的魔法暴击值
---@param element string|nil  伤害属性："fire"/"ice"/"thunder"
---@return number 额外魔法暴击值
local function getElementProfMCrit(element)
    if not element then return 0 end
    local profId = ELEMENT_PROF_MAP[element]
    if not profId then return 0 end
    local lv = GS.skillLevels[profId] or 0
    if lv <= 0 then return 0 end
    local profDef = GS.SKILL_DEFS[profId]
    if not profDef or not profDef.elementMCritPerLv then return 0 end
    return profDef.elementMCritPerLv * lv
end

--- 元素专精魔法暴击伤害加成：施展对应元素法术时，获得该元素专精提供的魔法暴击伤害%
---@param element string|nil  伤害属性："fire"/"ice"/"thunder"
---@return number 额外魔法暴击伤害%
local function getElementMasterMCritDmg(element)
    if not element then return 0 end
    local masterId = ELEMENT_MASTER_MAP[element]
    if not masterId then return 0 end
    local lv = GS.skillLevels[masterId] or 0
    if lv <= 0 then return 0 end
    local masterDef = GS.SKILL_DEFS[masterId]
    if not masterDef or not masterDef.elementMCritDmgPerLv then return 0 end
    return masterDef.elementMCritDmgPerLv * lv
end

--- 暴击判定：暴击率 = 暴击值 / (目标等级 * 4)，上限 = 攻击方等级%
--- 魔法攻击时使用 mCritRate/mCritDmg，并叠加元素熟练的魔法暴击加成
---@param attacker table
---@param target table
---@param dmg number
---@param dirBonus number|nil
---@param opts table|nil  { useMagic?, element? }
---@return number dmg, boolean isCrit
local function rollCrit(attacker, target, dmg, dirBonus, opts)
    opts = opts or {}
    local isMagic = opts.useMagic
    local critVal, critDmgBase
    if opts.lzPhysRatio then
        -- 小宙斯：按物理/魔法伤害占比加权暴击值与暴击伤害
        local pR = opts.lzPhysRatio
        local mR = opts.lzMagRatio or (1 - pR)
        local physCrit = (attacker.critVal or 0)
        local magCrit  = (attacker.mCritRate or 0) + getElementProfMCrit(opts.element)
        critVal = math.floor(physCrit * pR + magCrit * mR) - (target.avoidCrit or 0)
        critDmgBase = math.floor((attacker.critDmg or 50) * pR + (attacker.mCritDmg or 25) * mR)
    elseif isMagic then
        critVal = (attacker.mCritRate or 0) + getElementProfMCrit(opts.element)
                  - (target.avoidCrit or 0)
        critDmgBase = attacker.mCritDmg or 25
    else
        critVal = (attacker.critVal or 0) - (target.avoidCrit or 0)
        critDmgBase = attacker.critDmg or 25
    end
    -- 强制暴击（冲锋技能等）：跳过概率判定，直接走暴击伤害
    if attacker._forceCrit then
        local totalCritDmg = critDmgBase
        if not isMagic and attacker._spareWeaponCritDmg and attacker._spareWeaponCritDmg > 0
           and (attacker._spareWeaponCritTurns or 0) > 0 then
            totalCritDmg = totalCritDmg + attacker._spareWeaponCritDmg
        end
        if target.noticeCritDmgBonus and target.noticeCritDmgTurns and target.noticeCritDmgTurns > 0 then
            totalCritDmg = totalCritDmg + target.noticeCritDmgBonus
        end
        return math.floor(dmg * (1 + totalCritDmg / 100)), true
    end
    -- 方向暴击率加成（仅背后+10%）即使 critVal<=0 也生效
    dirBonus = dirBonus or 0
    local dirCritBonus = 0
    if dirBonus == 2 then dirCritBonus = 0.10 end
    if critVal <= 0 and dirCritBonus <= 0 then return dmg, false end
    local targetLv = math.max(1, target.level or 1)
    local critChance = critVal > 0 and (critVal / (targetLv * 4)) or 0
    if not attacker.isMonster and critVal > 0 then
        local attackerLv = math.max(1, attacker.level or 1)
        critChance = math.min(critChance, attackerLv / 100)
    end
    critChance = critChance + dirCritBonus
    if math.random() < critChance then
        local totalCritDmg = critDmgBase
        -- 元素专精魔法暴击伤害加成
        if isMagic then
            totalCritDmg = totalCritDmg + getElementMasterMCritDmg(opts.element)
        end
        -- 备用武器暴击伤害加成（BUFF持续中）
        if not isMagic and attacker._spareWeaponCritDmg and attacker._spareWeaponCritDmg > 0
           and (attacker._spareWeaponCritTurns or 0) > 0 then
            totalCritDmg = totalCritDmg + attacker._spareWeaponCritDmg
        end
        -- 预告信暴击伤害易伤
        if target.noticeCritDmgBonus and target.noticeCritDmgTurns and target.noticeCritDmgTurns > 0 then
            totalCritDmg = totalCritDmg + target.noticeCritDmgBonus
        end
        return math.floor(dmg * (1 + totalCritDmg / 100)), true
    end
    return dmg, false
end

-- ====================================================================
-- 方向性攻击判定（背刺/侧击）
-- ====================================================================
--- 判断攻击者相对于防御者朝向的方向
---@return number 0=正面, 1=侧面, 2=背后
local function getDirectionalBonus(attacker, defender)
    if not attacker or not defender then return 0 end
    local facing = defender.facing
    if not facing then return 0 end
    -- 幻影攻击时使用幻影位置判断方向
    local ax, ay = attacker.x, attacker.y
    if attacker._phantomPos then ax, ay = attacker._phantomPos[1], attacker._phantomPos[2] end
    local dx = ax - defender.x
    local dy = ay - defender.y
    if dx == 0 and dy == 0 then return 0 end
    local atkDir
    if math.abs(dx) >= math.abs(dy) then
        atkDir = dx > 0 and "right" or "left"
    else
        atkDir = dy > 0 and "down" or "up"
    end
    -- 侧前方45°归为正面：|dx|==|dy|时若在前方半球则视为正面
    if math.abs(dx) == math.abs(dy) then
        local frontHalf = false
        if facing == "down"  and dy > 0 then frontHalf = true
        elseif facing == "up"    and dy < 0 then frontHalf = true
        elseif facing == "left"  and dx < 0 then frontHalf = true
        elseif facing == "right" and dx > 0 then frontHalf = true
        end
        if frontHalf then return 0 end
    end
    -- 背后：攻击者方向与朝向相反
    local backMap = { up = "down", down = "up", left = "right", right = "left" }
    if atkDir == backMap[facing] then return 2 end
    -- 正面：攻击者方向与朝向一致
    if atkDir == facing then return 0 end
    -- 其余：侧面
    return 1
end

-- ====================================================================
-- 通用闪避判定（可复用）
-- 返回 true 表示闪避成功（Miss），false 表示命中
-- 参数:
--   attacker: 攻击方 (player/companion/monster)
--   defender: 防守方 (monster/player)
--   skillId: 技能ID（可选，用于判断弹道类攻击的侧风惩罚）
-- ====================================================================
local function rollDodge(attacker, defender, skillId)
    -- 确定当前武器标签供风效果判定使用
    local currentWeaponTag = (not attacker.isMonster and not attacker.isCompanion) and getPlayerWeaponTag() or nil

    -- 闪避率 = (防守方闪避 - 攻击方命中) / 防守方闪避
    local defDodge = defender.dodge or 0
    -- 玩家闪避 debuff（电史莱姆精锐）
    if not defender.isMonster and #GS.playerDebuffs > 0 then
        for _, db in ipairs(GS.playerDebuffs) do
            if db.type == "dodge" then defDodge = defDodge - db.val end
        end
        defDodge = math.max(0, defDodge)
    end
    local atkHit = attacker.hit or 0
    -- 泼沙debuff：命中值下降
    if attacker.sandBlinded and attacker.sandBlindedTurns and attacker.sandBlindedTurns > 0 then
        atkHit = math.max(0, atkHit - attacker.sandBlinded)
    end
    -- 狂风：弹道类攻击侧风命中惩罚
    local windHitPenalty = 0
    if WE.isProjectileAttack(attacker, skillId, currentWeaponTag) then
        windHitPenalty = WE.getWindProjectileHitPenalty(attacker.x, attacker.y, defender.x, defender.y)
    end
    local dodgeRate = 0
    if defDodge > 0 and defDodge > atkHit then
        dodgeRate = (defDodge - atkHit) / defDodge
    end
    -- 侧风命中惩罚
    dodgeRate = dodgeRate + windHitPenalty
    -- 背后攻击：闪避率固定减少10%
    local dirBonusDodge = getDirectionalBonus(attacker, defender)
    if dirBonusDodge == 2 then
        dodgeRate = dodgeRate - 0.10
    end
    -- 闪避率额外提高（沉没披风等装备提供的固定百分比加成）
    if not defender.isMonster and (defender.dodgeRateBonus or 0) > 0 then
        dodgeRate = dodgeRate + defender.dodgeRateBonus / 100
    end
    -- 月影：每层+1.5%×技能等级 闪避率
    if not defender.isMonster and (defender._moonShadowStacks or 0) > 0 then
        local msLv = GS.skillLevels["a_moon_shadow"] or 0
        if msLv > 0 then
            dodgeRate = dodgeRate + defender._moonShadowStacks * (1.5 * msLv) / 100
        end
    end
    -- 闪避率硬上限 95%（保证至少 5% 命中率）
    if dodgeRate > 0.95 then dodgeRate = 0.95 end
    if dodgeRate > 0 and math.random() < dodgeRate then
        -- 满月：玩家成功闪避时累加计数
        if not defender.isMonster then
            local fmLv = GS.skillLevels["a_full_moon"] or 0
            if fmLv >= 3 then
                local def = GS.SKILL_DEFS["a_full_moon"]
                local maxStacks = def.fullMoonMaxStacks[fmLv] or 0
                if maxStacks > 0 then
                    defender._fullMoonDodgeCount = (defender._fullMoonDodgeCount or 0) + 1
                    local chargeNeed = def.fullMoonDodgePerCharge[fmLv] or 20
                    if defender._fullMoonDodgeCount >= chargeNeed then
                        defender._fullMoonDodgeCount = 0
                        local duration = def.fullMoonDuration
                        if not defender._fullMoonStackList then defender._fullMoonStackList = {} end
                        local curStacks = #defender._fullMoonStackList
                        if curStacks < maxStacks then
                            defender._fullMoonStackList[#defender._fullMoonStackList + 1] = duration
                        else
                            -- 满层时覆盖剩余持续时间最短的
                            local minIdx, minVal = 1, defender._fullMoonStackList[1]
                            for si = 2, #defender._fullMoonStackList do
                                if defender._fullMoonStackList[si] < minVal then
                                    minIdx, minVal = si, defender._fullMoonStackList[si]
                                end
                            end
                            defender._fullMoonStackList[minIdx] = duration
                        end
                        defender._fullMoonStacks = #defender._fullMoonStackList
                        M.addDamageText(defender.x, defender.y - 0.5, "满月+" .. defender._fullMoonStacks, {200, 210, 255})
                    end
                end
            end
        end
        return true
    end
    -- 偏斜：闪避失败时二次闪避检定，成功则根据避开要害减伤
    if not defender.isMonster then
        local deflectLv = GS.skillLevels["a_deflect"] or 0
        if deflectLv > 0 and dodgeRate > 0 and math.random() < dodgeRate then
            -- 二次闪避成功，计算减伤比例：(avoidCrit×效率 - atkHit) / (avoidCrit×效率)
            local rawAvoidCrit = defender.avoidCrit or 0
            local effPct = 37 + 7 * (deflectLv - 1)  -- 1级37%，满级100%
            local defAvoidCrit = rawAvoidCrit * math.min(effPct, 100) / 100
            local dmgReduce = 0
            if defAvoidCrit > 0 and defAvoidCrit > atkHit then
                dmgReduce = (defAvoidCrit - atkHit) / defAvoidCrit
            end
            if dmgReduce > 0.95 then dmgReduce = 0.95 end
            if dmgReduce > 0 then
                defender._deflectDmgReduce = dmgReduce
                M.addDamageText(defender.x, defender.y - 0.5, "偏斜!", {180, 160, 120})
                -- 偏斜成功也计入满月叠层计数
                local fmLv2 = GS.skillLevels["a_full_moon"] or 0
                if fmLv2 >= 3 then
                    local fmDef2 = GS.SKILL_DEFS["a_full_moon"]
                    local maxSt2 = fmDef2.fullMoonMaxStacks[fmLv2] or 0
                    if maxSt2 > 0 then
                        defender._fullMoonDodgeCount = (defender._fullMoonDodgeCount or 0) + 1
                        local chargeNeed2 = fmDef2.fullMoonDodgePerCharge[fmLv2] or 20
                        if defender._fullMoonDodgeCount >= chargeNeed2 then
                            defender._fullMoonDodgeCount = 0
                            local duration2 = fmDef2.fullMoonDuration
                            if not defender._fullMoonStackList then defender._fullMoonStackList = {} end
                            local cur2 = #defender._fullMoonStackList
                            if cur2 < maxSt2 then
                                defender._fullMoonStackList[#defender._fullMoonStackList + 1] = duration2
                            else
                                local minIdx2, minVal2 = 1, defender._fullMoonStackList[1]
                                for si2 = 2, #defender._fullMoonStackList do
                                    if defender._fullMoonStackList[si2] < minVal2 then
                                        minIdx2, minVal2 = si2, defender._fullMoonStackList[si2]
                                    end
                                end
                                defender._fullMoonStackList[minIdx2] = duration2
                            end
                            defender._fullMoonStacks = #defender._fullMoonStackList
                            M.addDamageText(defender.x, defender.y - 0.5, "满月+" .. defender._fullMoonStacks, {200, 210, 255})
                        end
                    end
                end
            end
        end
    end
    return false
end

-- ====================================================================
-- 统一伤害加成管线（新增加成只需改这一个函数）
-- ====================================================================
--- 对已计算好的基础伤害施加所有通用加成 + 暴击
--- performAttack 和 calcSkillDamage 都通过此函数保持一致。
---@param attacker table
---@param defender table
---@param dmg number       已含倍率的基础伤害
---@param opts table       { element?, noCrit?, noMark? }
---@return number dmg, boolean isCrit
local function applyDmgBonuses(attacker, defender, dmg, opts)
    opts = opts or {}
    -- 百分比加成（剑术熟练等条件被动）
    dmg = applyDmgPctBonus(attacker, dmg)

    -- 装备伤害加成（精炼词缀提供）
    if not attacker.isMonster then
        local equipBonusPct = 0
        -- 1) 武器类型加成：匹配当前武器
        local wt = attacker.weaponTag
        if wt == "单手剑" then
            equipBonusPct = equipBonusPct + (attacker.swordDmgBonus or 0)
        elseif wt == "匕首" then
            equipBonusPct = equipBonusPct + (attacker.daggerDmgBonus or 0)
        elseif wt == "钉锤" then
            equipBonusPct = equipBonusPct + (attacker.maceDmgBonus or 0)
        elseif wt == "弓" then
            equipBonusPct = equipBonusPct + (attacker.bowDmgBonus or 0)
        elseif wt == "法杖" then
            equipBonusPct = equipBonusPct + (attacker.staffDmgBonus or 0)
        end
        -- 2) 物理/魔法通用加成
        if opts.useMagic then
            equipBonusPct = equipBonusPct + (attacker.magDmgBonus or 0)
        else
            equipBonusPct = equipBonusPct + (attacker.physDmgBonus or 0)
        end
        -- 3) 元素伤害加成
        local elem = opts.element
        if elem == "fire" then
            equipBonusPct = equipBonusPct + (attacker.fireDmgBonus or 0)
        elseif elem == "ice" then
            equipBonusPct = equipBonusPct + (attacker.iceDmgBonus or 0)
        elseif elem == "thunder" then
            equipBonusPct = equipBonusPct + (attacker.elecDmgBonus or 0)
        elseif elem == "light" or elem == "holy" then
            equipBonusPct = equipBonusPct + (attacker.lightDmgBonus or 0)
        end
        -- 3.5) 元素流转：上回合造成过元素伤害且buff未过期，本次使用不同元素时增伤
        if elem and (attacker.eleFlowBonus or 0) > 0
            and GS._eleFlowLastElem and (GS._eleFlowTurns or 0) > 0 then
            if elem ~= GS._eleFlowLastElem then
                equipBonusPct = equipBonusPct + attacker.eleFlowBonus
            end
        end
        -- 4) 未知异瞳：对处于恐惧状态的目标造成伤害+10%
        if defender and (defender.feared or 0) > 0 then
            local trinketItem = GS.equipment and GS.equipment["trinket"]
            if trinketItem and trinketItem.id == "unknown_eye_trinket" then
                equipBonusPct = equipBonusPct + 10
            end
        end
        -- 宇宙奥秘8件套：根据当前魔力百分比提高魔法伤害
        if opts.useMagic then
            local setB8 = GS.getSetBonus()
            local coeff = setB8.manaPctMagDmg or 0
            if coeff > 0 and GS.player and (GS.player.maxMp or 0) > 0 then
                local mpPct = (GS.player.mp or 0) / GS.player.maxMp
                equipBonusPct = equipBonusPct + math.floor(mpPct * coeff * 100)
            end
        end
        -- 狡诈奇美拉8件套：根据上回合伤害次数增幅本回合所有伤害
        do
            local setB8 = GS.getSetBonus()
            local ampCoeff = setB8.hitCountDmgAmp or 0
            if ampCoeff > 0 and (GS._slyLastTurnHitCount or 0) > 0 then
                local count = math.min(GS._slyLastTurnHitCount, 10)
                equipBonusPct = equipBonusPct + (count * ampCoeff)
            end
        end
        -- 5) 全能者腰带：全属性伤害加成
        equipBonusPct = equipBonusPct + (attacker.allStatDmgBonus or 0)
        -- 6) 近处敌人伤害加成（暴风眼：切比雪夫距离<=1，即周围一圈8格）
        if (attacker.nearDmgBonus or 0) > 0 and defender and attacker.x and defender.x then
            local dx = math.abs(attacker.x - defender.x)
            local dy = math.abs(attacker.y - defender.y)
            if math.max(dx, dy) <= 1 then
                equipBonusPct = equipBonusPct + attacker.nearDmgBonus
            end
        end
        -- 7) 冲锋怒吼：伤害加成
        if (attacker.chargeRoarTurns or 0) > 0 and (attacker.chargeRoarDmgPct or 0) > 0 then
            equipBonusPct = equipBonusPct + attacker.chargeRoarDmgPct
        end
        -- 8) 魔贯：使用预计算的加成（MP已在攻击发起时消耗，无论命中与否）
        if (GS._mpCostBonusThisAtk or 0) > 0 then
            equipBonusPct = equipBonusPct + GS._mpCostBonusThisAtk
            GS._mpCostBonusThisAtk = nil  -- 用完清除，防止连锁伤害复用
        end
        -- 应用总伤害加成
        if equipBonusPct > 0 then
            dmg = math.floor(dmg * (1 + equipBonusPct / 100))
            dmg = math.max(1, dmg)
        end
        -- 燃火BUFF：独立乘算，在其他加成基础上额外提高火焰伤害
        if elem == "fire" and (attacker._ragingFireBonus or 0) > 0 then
            dmg = math.floor(dmg * (1 + attacker._ragingFireBonus / 100))
            dmg = math.max(1, dmg)
        end
    end

    -- 元素熟练加成（按伤害属性）
    dmg = applyElementBonus(dmg, opts.element)
    -- 冰墙减益：冰墙1格内的敌人受冰冻伤害增加
    if opts.element == "ice" and defender and #GS.iceWalls > 0 then
        local nearWall = false
        for _, w in ipairs(GS.iceWalls) do
            if math.abs(defender.x - w.x) + math.abs(defender.y - w.y) <= 1 then
                nearWall = true
                break
            end
        end
        if nearWall then
            local wallDef = GS.SKILL_DEFS["m_ice_wall"]
            local wallLv = GS.skillLevels["m_ice_wall"] or 1
            local bonusPct = (wallDef and wallDef.iceWallIceDmgBonusPerLv or 2) * wallLv
            bonusPct = math.min(bonusPct, 20) -- 满级20%上限
            dmg = math.floor(dmg * (1 + bonusPct / 100))
        end
    end
    -- 元素反应：蒸腾（火+冻僵/冻结 或 冰+灼伤 → +20%伤害，清除debuff；暴晒+50%）
    local evapBonus = WE.getEvaporationBonus()  -- 默认0.20，暴晒0.30
    if defender then
        if opts.element == "fire" and (defender.chilled or (defender.frozen and defender.frozen > 0)) then
            local burnSC = defender.burnStacks and #defender.burnStacks or 0
            local chillSC = M.getEffectiveChillStacks(defender)
            dmg = math.floor(dmg * (1 + evapBonus * (math.max(1, burnSC) + chillSC)))
            defender.chilled = nil
            defender.chilledTurns = nil
            defender.chillStacks = nil
            defender.frozen = nil
            M.clearBurnDebuff(defender)
            defender._noElementDebuff = true
            M.addDamageText(defender.x, defender.y - 0.8, "蒸腾!", {255, 50, 50})
        elseif opts.element == "ice" and defender.burned then
            local burnSC = defender.burnStacks and #defender.burnStacks or 1
            local chillSC = M.getEffectiveChillStacks(defender)
            dmg = math.floor(dmg * (1 + evapBonus * (burnSC + math.max(1, chillSC))))
            M.clearBurnDebuff(defender)
            defender.chilled = nil
            defender.chilledTurns = nil
            defender.chillStacks = nil
            defender.frozen = nil
            defender._noElementDebuff = true
            M.addDamageText(defender.x, defender.y - 0.8, "蒸腾!", {255, 50, 50})
        end
    end
    -- 元素反应：爆炸（雷电+灼伤 → 每层灼烧10% mAtk AOE，不消除灼伤）
    if opts.element == "thunder" and defender and defender.burned then
        local burnSC = defender.burnStacks and #defender.burnStacks or 1
        defender._explosionPending = { mAtk = attacker.mAtk or attacker.atk, burnSC = burnSC }
    end
    -- 元素反应：失感（雷电+冻僵 → 每层冻僵+5%晕眩概率，不消除冻僵）
    if opts.element == "thunder" and defender and defender.chilled then
        defender._numbingPending = defender.chillStacks or 1
        M.addDamageText(defender.x, defender.y - 0.8, "失感!", {120, 120, 120})
    end
    -- 标记目标加成
    if not opts.noMark then
        dmg = applyMarkBonus(attacker, defender, dmg)
    end
    -- 方向性攻击加成（背刺/侧击）+ 暗杀（加算）
    local dirBonus = getDirectionalBonus(attacker, defender)
    if dirBonus >= 1 then
        local basePct = dirBonus == 2 and 10 or 5  -- 背后+10%, 侧面+5%
        local assPct = 0
        local assLv = GS.skillLevels["a_assassinate"] or 0
        if assLv > 0 then
            assPct = dirBonus == 2 and (2 * assLv) or (1 * assLv)
        end
        dmg = math.floor(dmg * (1 + (basePct + assPct) / 100))
    end
    -- 怪物抗性/弱点：抗性减伤30%，弱点增伤30%
    if opts.element and defender and defender.isMonster then
        if defender.resistance then
            for _, r in ipairs(defender.resistance) do
                if r == opts.element then
                    dmg = math.max(1, math.floor(dmg * 0.7))
                    break
                end
            end
        end
        if defender.weakness then
            for _, w in ipairs(defender.weakness) do
                if w == opts.element then
                    dmg = math.max(1, math.floor(dmg * 1.3))
                    break
                end
            end
        end
    end
    -- 暴击判定（含方向暴击率加成）
    local isCrit = false
    if not opts.noCrit then
        dmg, isCrit = rollCrit(attacker, defender, dmg, dirBonus,
            { useMagic = opts.useMagic, element = opts.element })
    end
    -- 狂血：未暴击的物理伤害惩罚
    if not isCrit and not opts.useMagic and not attacker.isMonster
       and (attacker.nonCritPhysPenalty or 0) ~= 0 then
        dmg = math.floor(dmg * (1 + attacker.nonCritPhysPenalty / 100))
        dmg = math.max(1, dmg)
    end
    -- 元素流转：记录本次造成的元素伤害类型（供下回合判断）
    local eleFlowElem = opts and opts.element
    if eleFlowElem and dmg > 0 and (attacker.eleFlowBonus or 0) > 0 then
        GS._eleFlowElem = eleFlowElem
    end

    return dmg, isCrit
end

-- ====================================================================
-- 统一伤害计算（基础伤害 + 倍率 + 加成管线）
-- ====================================================================
--- 一站式技能伤害：攻防公式 → 倍率 → 加成 → 暴击
--- 适用于不需要特殊前/后处理的技能（AOE、冰环、闪电链、散射等）。
---@param attacker table     攻击者
---@param defender table     防御者
---@param opts table         选项表:
---   mul:       number      伤害倍率（默认1.0）
---   skillId:   string|nil  技能ID
---   element:   string|nil  伤害属性（"fire"/"ice"/"thunder"，用于元素熟练加成）
---   useMagic:  boolean     是否用 mAtk/mdef（默认false）
---   noCrit:    boolean     跳过暴击判定（默认false）
---   noMark:    boolean     跳过标记加成（默认false）
---@return number dmg, boolean isCrit
local function calcSkillDamage(attacker, defender, opts)
    opts = opts or {}
    local mul = opts.mul or 1.0
    local useMagic = opts.useMagic or false

    -- 1) 攻防取值
    local holySkill = opts.holySkill or false
    local atkVal, defVal
    if holySkill then
        -- 神圣伤害：物攻 + 魔攻/2，防御取 (物防+魔防)/2
        atkVal = attacker.atk + math.floor((attacker.mAtk or 0) / 2)
        defVal = math.floor((defender.def + (defender.mdef or 0)) / 2)
    elseif useMagic then
        atkVal = attacker.mAtk or attacker.atk
        defVal = defender.mdef or defender.def
    else
        atkVal = attacker.atk
        defVal = defender.def
    end

    -- 1.5) 双持伤害惩罚（普攻和技能均受影响）
    -- 刺客投掷类技能豁免双持减值
    local csSkillId = opts.skillId
    local csIsThrow = csSkillId == "a_weapon_throw" or csSkillId == "a_poison_throw"
        or csSkillId == "a_armor_break" or csSkillId == "a_notice"
    if not csIsThrow and not attacker.isMonster and not (attacker.isCompanion) and GS.isDualMelee() then
        local dualPct = 50
        if GS.isDualDagger() then
            for _, sid in ipairs({"a_dual_prof", "a_dual_master"}) do
                local lv = GS.skillLevels[sid] or 0
                if lv > 0 then
                    local sd = GS.SKILL_DEFS[sid]
                    if sd and sd.dualDmgPctPerLv then
                        dualPct = dualPct + sd.dualDmgPctPerLv * lv
                    end
                end
            end
        end
        dualPct = math.min(dualPct, 100)
        atkVal = math.floor(atkVal * dualPct / 100)
    end

    -- 2) 嘲讽 debuff
    if attacker.taunted and attacker.taunted > 0 then
        atkVal = math.floor(atkVal * (1 + (attacker.tauntAtkPct or 0) / 100))
    end
    if defender.taunted and defender.taunted > 0 then
        defVal = math.max(0, math.floor(defVal * (1 + (defender.tauntDefPct or 0) / 100)))
    end

    -- 3) 破甲 debuff（仅物理）
    if not useMagic and defender.armorBroken and defender.armorBrokenTurns and defender.armorBrokenTurns > 0 then
        defVal = math.max(0, math.floor(defVal * (1 - defender.armorBroken / 100)))
    end

    -- 4) 基础伤害 + 浮动
    local dmg = math.floor(atkVal * atkVal / math.max(1, atkVal + defVal))
    dmg = math.max(1, dmg)
    local variance = math.floor(dmg * 0.1)
    dmg = dmg + math.random(-variance, variance)
    dmg = math.max(1, dmg)

    -- 5) 技能倍率
    dmg = math.floor(dmg * mul)
    dmg = math.max(1, dmg)

    -- 5.5) 极重月：攻速转技能伤害加成
    if opts.skillId and not attacker.isMonster and (attacker.aspdSkillDmgPct or 0) > 0 then
        local atkSpd = attacker.atkSpeed or 0
        if atkSpd > 0 then
            local bonusPct = atkSpd * attacker.aspdSkillDmgPct
            dmg = math.floor(dmg * (1 + bonusPct / 100))
            dmg = math.max(1, dmg)
        end
    end

    -- 5.6) 深度思维：额外吟唱段数增伤
    if not attacker.isMonster and (attacker._deepThinkBonus or 0) > 0 then
        dmg = math.floor(dmg * (1 + attacker._deepThinkBonus / 100))
        dmg = math.max(1, dmg)
    end

    -- 6) 通用加成管线
    return applyDmgBonuses(attacker, defender, dmg, opts)
end

--- 对目标施加伤害并检测击杀
--- 训练场伤害跟踪
local function trackTrainingDamage(target, dmg)
    if GS.trainingMode and target and target.isTrainingDummy and dmg > 0 then
        GS.trainingTurnDmg = GS.trainingTurnDmg + dmg
    end
end

-- ====================================================================
-- 暴怒BUFF系统 - 史莱姆国王大反击关卡专用
-- ====================================================================

--- 暴怒层数累计伤害阈值表（前40层预定义）
local RAGE_THRESHOLDS = {
    1000, 2000, 4000, 8000, 16000,             -- 1-5
    32000, 64000, 128000, 256000, 512000,       -- 6-10
    768000, 1152000, 1728000, 2592000, 3888000, -- 11-15
    5832000, 8748000, 13122000, 19683000, 29524500, -- 16-20
    38381850, 49896405, 64865327, 84324924, 109622402, -- 21-25
    131546882, 157856259, 189427510, 227313012, 272775615, -- 26-30
    327330738, 392796885, 471356262, 565627515, 678753018, -- 31-35
    814503621, 977404346, 1172885215, 1407462258, 1688954709, -- 36-40
}

--- 根据暴怒层数计算怪物等级
--- 叠加1层后变为50级，之后每4层所有怪物等级提高10级
local function getRageLevelByLayer(layer)
    if layer <= 0 then return nil end
    return 50 + math.floor((layer - 1) / 4) * 10
end

--- 获取第 layer 层的累计伤害阈值
--- 前40层使用预定义表，之后按 ×1.2 递推
local function getRageThreshold(layer)
    if layer <= #RAGE_THRESHOLDS then
        return RAGE_THRESHOLDS[layer]
    end
    -- 超过预定义表：从最后一个阈值开始按 ×1.2 递推
    local val = RAGE_THRESHOLDS[#RAGE_THRESHOLDS]
    for i = #RAGE_THRESHOLDS + 1, layer do
        val = math.floor(val * 1.2)
    end
    return val
end

--- 判断怪物是否为暴怒关卡的暴怒系怪物（boss 或暴怒杂兵）
local function isEnragedSlime(monster)
    if not monster or not monster.isMonster or monster.hp <= 0 then return false end
    local did = monster.defId
    return did == "slime_king_enraged"
        or did == "fire_slime_enraged"
        or did == "ice_slime_enraged"
        or did == "elec_slime_enraged"
end

--- 判断怪物是否为迪哈塔大反击的暴怒系怪物
local function isDihataUnit(monster)
    if not monster or not monster.isMonster or monster.hp <= 0 then return false end
    return monster.defId == "goblin_hero_dihata"
end

--- 判断怪物是否属于任一大反击关卡的暴怒系怪物
local function isRevengeUnit(monster)
    return isEnragedSlime(monster) or isDihataUnit(monster)
end

--- 将暴怒BUFF应用到单个怪物（设置/更新基础属性缓存 + 重新计算当前属性）
--- @param monster table 怪物实例
--- @param rageLayer number 当前暴怒层数
local function applyRageBuff(monster, rageLayer)
    if not isRevengeUnit(monster) then return end

    -- 首次调用时缓存基础属性（从定义获取原始值）
    if not monster._rageBase then
        monster._rageBase = {
            atk = monster.atk,
            mAtk = monster.mAtk,
            def = monster.def,
            mdef = monster.mdef,
            critVal = monster.critVal or 0,
            critDmg = monster.critDmg or 50,
            hit = monster.hit or 0,
            dodge = monster.dodge or 0,
            hp = monster.maxHp,
            level = monster.level,
        }
    end

    local base = monster._rageBase
    local mult = 1 + 0.2 * rageLayer   -- 每层 +20%
    local newLevel = getRageLevelByLayer(rageLayer)

    monster.atk     = math.floor(base.atk * mult)
    monster.mAtk    = math.floor(base.mAtk * mult)
    monster.def     = math.floor(base.def * mult)
    monster.mdef    = math.floor(base.mdef * mult)
    monster.critVal = math.floor(base.critVal * mult)
    monster.critDmg = math.floor(base.critDmg * mult)
    monster.hit     = math.floor(base.hit + rageLayer * 2)
    monster.dodge   = math.floor(base.dodge + rageLayer * 5)

    -- 非 boss 杂兵：血量也提升（按比例提升 maxHp，并等比恢复当前 hp）
    if not monster.immortal then
        local newMaxHp = math.floor(base.hp * mult)
        if newMaxHp > monster.maxHp then
            local ratio = monster.hp / math.max(1, monster.maxHp)
            monster.maxHp = newMaxHp
            monster.hp = math.max(1, math.floor(newMaxHp * ratio))
        end
    end

    -- 等级更新（迪哈塔从基础等级开始叠加，史莱姆系用原公式）
    local finalLevel
    if isDihataUnit(monster) then
        -- 迪哈塔：基础等级 + 每层+5级
        finalLevel = base.level + rageLayer * 5
    else
        finalLevel = newLevel
    end
    if finalLevel then
        monster.level = finalLevel
        if not monster._rageBase._baseName then
            monster._rageBase._baseName = monster.name:gsub(" Lv%.%d+", "")
        end
        monster.name = (monster._rageBase._baseName or monster.name:gsub(" Lv%.%d+", "")) .. " Lv." .. finalLevel
    end

    -- 迪哈塔暴怒散射：每3层+1散射，最多10层散射
    if isDihataUnit(monster) then
        monster.rageScatter = math.min(math.floor(rageLayer / 3), 10)
    end

    monster._rageLayer = rageLayer
end

--- 对所有暴怒系怪物应用暴怒BUFF
local function applyRageBuffToAll(rageLayer)
    for _, m in ipairs(GS.monsters) do
        applyRageBuff(m, rageLayer)
    end
end

--- 获取当前大反击关卡的累计伤害和暴怒层数引用
--- @return number accDmg, number curLayer, string accKey, string layerKey
local function getRevengeAccState()
    if GS.currentStage == GS.STAGE_SLIME_KING_REVENGE then
        return GS.slimeRevengeAccDmg or 0, GS.slimeRevengeRageLayer or 0,
               "slimeRevengeAccDmg", "slimeRevengeRageLayer"
    elseif GS.currentStage == GS.STAGE_DIHATA_REVENGE then
        return GS.dihataRevengeAccDmg or 0, GS.dihataRevengeRageLayer or 0,
               "dihataRevengeAccDmg", "dihataRevengeRageLayer"
    end
    return 0, 0, nil, nil
end

--- 判断当前是否处于任一大反击关卡
local function isRevengeStage()
    return GS.currentStage == GS.STAGE_SLIME_KING_REVENGE
        or GS.currentStage == GS.STAGE_DIHATA_REVENGE
end

--- 检查累计伤害是否突破新的暴怒阈值，触发暴怒BUFF叠层
local function checkRageThresholds()
    if not isRevengeStage() then return end
    local accDmg, curLayer, accKey, layerKey = getRevengeAccState()

    -- 计算当前累计伤害应达到的层数
    local newLayer = curLayer
    while true do
        local nextThreshold = getRageThreshold(newLayer + 1)
        if accDmg >= nextThreshold then
            newLayer = newLayer + 1
        else
            break
        end
    end

    -- 如果有新层数，应用暴怒BUFF
    if newLayer > curLayer then
        local layersGained = newLayer - curLayer
        GS[layerKey] = newLayer

        -- 对所有暴怒系怪物应用
        applyRageBuffToAll(newLayer)

        -- 飘字提示
        local oldScatter = math.min(math.floor(curLayer / 5), 10)
        local newScatter = math.min(math.floor(newLayer / 5), 10)
        for _, m in ipairs(GS.monsters) do
            if isRevengeUnit(m) and m.hp > 0 then
                local cx, cy = GS.unitCenterPos(m)
                if layersGained == 1 then
                    M.addDamageText(cx, cy - 0.5, "暴怒！Lv." .. newLayer, {255, 80, 40}, 1.2)
                else
                    M.addDamageText(cx, cy - 0.5, "暴怒！+" .. layersGained .. " → Lv." .. newLayer, {255, 80, 40}, 1.2)
                end
                -- 迪哈塔散射层数变化提示
                if isDihataUnit(m) and newScatter > oldScatter then
                    M.addDamageText(cx, cy - 1.0, "散射+" .. newScatter, {255, 160, 40}, 1.0)
                end
            end
        end
        print("[Rage] 暴怒层数: " .. curLayer .. " → " .. newLayer .. " (累计伤害: " .. math.floor(accDmg) .. ")")
    end
end

--- 不死怪物守卫：累计伤害追踪 + 防止死亡
--- 在每次 hp = hp - dmg 之后调用，确保 immortal 怪物不会死亡
local function immortalGuard(target, dmg)
    if target and target.immortal and target.isMonster then
        if dmg and dmg > 0 then
            -- 根据当前关卡累加到对应的累计伤害字段
            if GS.currentStage == GS.STAGE_DIHATA_REVENGE then
                GS.dihataRevengeAccDmg = (GS.dihataRevengeAccDmg or 0) + dmg
            else
                GS.slimeRevengeAccDmg = (GS.slimeRevengeAccDmg or 0) + dmg
            end
        end
        if target.hp <= 0 then
            target.hp = 1
        end
        -- 检查是否突破暴怒阈值
        checkRageThresholds()
    end
end

---@param attacker table
---@param target table
---@param dmg number
---@param label string 伤害飘字前缀
---@param color table RGB颜色
---@param isCrit boolean|nil 是否暴击
---@param useMagic boolean|nil 是否法术伤害（用于吸血/回蓝判定）
local function applyDamageAndCheck(attacker, target, dmg, label, color, isCrit, useMagic)
    -- 偏斜：根据避开要害减伤
    if target._deflectDmgReduce and dmg > 0 then
        dmg = math.max(1, math.floor(dmg * (1 - target._deflectDmgReduce)))
        target._deflectDmgReduce = nil
    end
    -- 解放日胸甲：玩家受伤时，将 deferDmgPct% 的伤害延迟到回合结束结算
    if target == GS.player and (target.deferDmgPct or 0) > 0 and dmg > 0 then
        local deferred = math.max(1, math.floor(dmg * target.deferDmgPct / 100))
        dmg = dmg - deferred
        GS._deferredDmg = (GS._deferredDmg or 0) + deferred
    end
    -- 饮血护甲值：先用护甲值抵扣伤害
    if target == GS.player and (GS.bloodShield or 0) > 0 and dmg > 0 then
        local absorbed = math.min(GS.bloodShield, dmg)
        GS.bloodShield = GS.bloodShield - absorbed
        dmg = dmg - absorbed
        if absorbed > 0 then
            M.addDamageText(target.x, target.y + 0.3, "-" .. absorbed, {200, 180, 80})
        end
        -- 巴洛庄园飓风：护甲值被清空时标记待触发（扣血后再执行，见函数末尾）
        if GS.bloodShield <= 0 and (GS.player and (GS.player.derivStormDmgBonus or 0) > 0) then
            if (GS._armorClearHurricaneCount or 0) < 1 then
                GS._armorClearHurricaneCount = 1
                GS._pendingHurricane = true
            end
        end
    end
    target.hp = target.hp - dmg
    trackTrainingDamage(target, dmg)
    immortalGuard(target, dmg)
    -- 满月：遭受致死伤害时，消耗一层满月BUFF，将伤害减少95%并恢复HP
    if target == GS.player and target.hp <= 0 and dmg > 0 then
        local fmList = target._fullMoonStackList
        if fmList and #fmList > 0 then
            -- 移除剩余持续时间最小的那层（最大化剩余价值）
            local minIdx, minVal = 1, fmList[1]
            for si = 2, #fmList do
                if fmList[si] < minVal then
                    minIdx, minVal = si, fmList[si]
                end
            end
            table.remove(fmList, minIdx)
            target._fullMoonStacks = #fmList
            local reducedDmg = math.max(1, math.floor(dmg * 0.05))
            local restored = dmg - reducedDmg
            target.hp = target.hp + restored
            dmg = reducedDmg
            M.addDamageText(target.x, target.y - 0.5, "满月护佑！", {200, 210, 255})
            if #fmList <= 0 then
                target._fullMoonStackList = nil
                target._fullMoonStacks = nil
                target._fullMoonDodgeCount = nil
            end
        end
    end
    -- 血屠：狂怒叠层（暴击叠加，未暴击衰减）——所有攻击路径均生效
    if attacker and not attacker.isMonster and (attacker.furyMaxStacks or 0) > 0
       and target.isMonster and dmg > 0 then
        local maxStk = attacker.furyMaxStacks
        local curStk = attacker._furyStacks or 0
        local newStk = curStk
        if isCrit then
            local addN = attacker.furyStackPerCrit or 1
            newStk = math.min(curStk + addN, maxStk)
        else
            if curStk > 0 then
                local decay = attacker.furyDecayOnNonCrit or 7
                newStk = math.max(0, curStk - decay)
            end
        end
        if newStk ~= curStk then
            attacker._furyStacks = newStk
            GS.recalcStats(attacker)
        end
    end
    -- 狡诈奇美拉8件套：统计玩家和友军本回合的伤害次数
    if target.isMonster and (attacker == GS.player or (attacker and attacker.isCompanion)) then
        GS._slyHitCount = (GS._slyHitCount or 0) + 1
    end
    -- 玩家受伤：强制红色
    if target == GS.player then color = {255, 80, 80} end
    if isCrit then
        M.addDamageText(target.x, target.y, dmg .. "!", color, 1.5)
        -- 暴击画面震动
        if M._pendingProjectileHit then
            -- 弹道类：震动延迟到弹道命中时触发（由 main.lua 弹道命中检测处理）
            GS._pendingCritShake = true
        else
            GS.setScreenShake(0.15, 2, M._damageTextDelay or 0)
        end
    else
        M.addDamageText(target.x, target.y, "" .. dmg, color)
    end
    M.addHurtFlash(target)
    M.applyLifesteal(attacker, dmg, useMagic)
    M.applyBondLink(attacker, dmg)
    if target.hp <= 0 then
        -- 酒馆肉搏混混：不死亡，HP最低为1，进入永久眩晕
        if target.isBrawlThug then
            target.hp = 1
            if not target.brawlStunned then
                target.brawlStunned = true
                target.stunned = 9999  -- 永久眩晕
                M.addDamageText(target.x, target.y, "击晕!", {255, 200, 50})
            end
        else
            target.hp = 0
            if target.isMonster then
                M.processMonsterKill(attacker, target)
            end
        end
    end
    -- 元素反应：爆炸（雷电+灼伤 → 每层灼烧10% mAtk AOE伤害）
    if target._explosionPending then
        local expData = target._explosionPending
        target._explosionPending = nil
        local expDmg = math.max(1, math.floor(expData.mAtk * 0.10 * expData.burnSC * WE.getExplosionMul()))
        -- 爆炸暴击判定（魔法暴击）
        local expCrit = false
        local critVal = (attacker.mCritRate or 0)
        local targetLv = math.max(1, target.level or 1)
        local critChance = critVal > 0 and (critVal / (targetLv * 4)) or 0
        if critVal > 0 and not attacker.isMonster then
            local attackerLv = math.max(1, attacker.level or 1)
            critChance = math.min(critChance, attackerLv / 100)
        end
        if critChance > 0 and math.random() < critChance then
            local critDmgPct = attacker.mCritDmg or 25
            expDmg = math.floor(expDmg * (1 + critDmgPct / 100))
            expCrit = true
        end
        M.addDamageText(target.x, target.y - 0.8, "爆炸!", {255, 140, 0})
        -- 对目标自身造成爆炸伤害
        if target.hp > 0 and not target.brawlStunned then
            target.hp = target.hp - expDmg
            trackTrainingDamage(target, expDmg)
            immortalGuard(target, expDmg)
            if expCrit then
                M.addDamageText(target.x, target.y, expDmg .. "!", {255, 140, 0}, 1.5)
                GS.setScreenShake(0.15, 2, M._damageTextDelay or 0)
            else
                M.addDamageText(target.x, target.y, "" .. expDmg, {255, 140, 0})
            end
            M.addHurtFlash(target)
            if target.hp <= 0 then
                if target.isBrawlThug then
                    target.hp = 1
                    if not target.brawlStunned then
                        target.brawlStunned = true
                        target.stunned = 9999
                        M.addDamageText(target.x, target.y, "击晕!", {255, 200, 50})
                    end
                else
                    target.hp = 0
                    if target.isMonster then
                        M.processMonsterKill(attacker, target)
                    end
                end
            end
        end
        -- 对周围1格内的其他怪物造成爆炸伤害
        local ts = GS.unitSize(target)
        for _, m in ipairs(GS.monsters) do
            if m ~= target and m.hp > 0 then
                local ms = GS.unitSize(m)
                local inRange = false
                for tdy = 0, ts - 1 do
                    if inRange then break end
                    for tdx = 0, ts - 1 do
                        if inRange then break end
                        for mdy = 0, ms - 1 do
                            if inRange then break end
                            for mdx = 0, ms - 1 do
                                if math.abs((target.x + tdx) - (m.x + mdx)) + math.abs((target.y + tdy) - (m.y + mdy)) <= 1 then
                                    inRange = true
                                end
                            end
                        end
                    end
                end
                if inRange and not m.brawlStunned then
                    m.hp = m.hp - expDmg
                    trackTrainingDamage(m, expDmg)
                    immortalGuard(m, expDmg)
                    if expCrit then
                        M.addDamageText(m.x, m.y, expDmg .. "!", {255, 140, 0}, 1.5)
                    else
                        M.addDamageText(m.x, m.y, "" .. expDmg, {255, 140, 0})
                    end
                    M.addHurtFlash(m)
                    if m.hp <= 0 then
                        if m.isBrawlThug then
                            m.hp = 1
                            if not m.brawlStunned then
                                m.brawlStunned = true
                                m.stunned = 9999
                                M.addDamageText(m.x, m.y, "击晕!", {255, 200, 50})
                            end
                        else
                            m.hp = 0
                            if m.isMonster then
                                M.processMonsterKill(attacker, m)
                            end
                        end
                    end
                end
            end
        end
    end
end

--- 遍历攻击者周围存活怪物（切比雪夫距离 ≤ range，默认1即3×3）
---@param attacker table
---@param callback fun(monster: table)
---@param range? number 切比雪夫距离，默认1
local function forEachAdjacentMonster(attacker, callback, range)
    range = range or 1
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 then
            local adjacent = false
            local s = GS.unitSize(m)
            for dy = 0, s - 1 do
                if adjacent then break end
                for dx = 0, s - 1 do
                    local mx, my = m.x + dx, m.y + dy
                    local ddx = math.abs(mx - attacker.x)
                    local ddy = math.abs(my - attacker.y)
                    if ddx <= range and ddy <= range and (ddx + ddy) >= 1 then
                        adjacent = true
                        break
                    end
                end
            end
            if adjacent then callback(m) end
        end
    end
end

-- ====================================================================
-- 统一击杀结算：击杀计数 + 金币 + 经验 + 掉落
-- ====================================================================
--- 怪物被击杀后的统一战利品结算
---@param attacker table 攻击者（用于 goldBonus、经验计算）
---@param monster table 被击杀的怪物
function M.processMonsterKill(attacker, monster)
    -- 酒馆肉搏混混：不触发击杀逻辑
    if monster.isBrawlThug then return end
    -- 训练假人：不触发击杀逻辑，立即恢复满血
    if monster.isTrainingDummy then
        monster.hp = monster.maxHp
        return
    end
    -- 防止同一只怪被重复处理（如猎犬攻击路径曾重复调用此函数）
    if monster._killProcessed then return end
    monster._killProcessed = true
    -- 击杀奖励归属：伴侣（猎犬等）击杀的经验和回血归给玩家
    local creditAttacker = (attacker and attacker.isCompanion) and GS.player or attacker
    -- 不可知物被击杀：清除玩家凝视加成
    if monster.defId == "tidal_boss_unknown" and GS.player and (GS.player._unknownGaze or 0) > 0 then
        local gaze = GS.player._unknownGaze
        GS.player._unknownGaze = 0
        GS.player._gazePer = 0
        GS.player._gazeFoc = 0
        GS.recalcStats(GS.player)
        M.addDamageText(GS.player.x, GS.player.y - 0.5, "凝视消散", {160, 200, 255})
        print("[不可知物] BOSS死亡，凝视消散 (移除 " .. gaze .. " 层)")
    end
    -- 击杀计数 & 布告栏委托进度
    GS.onMonsterKill(monster.defId)
    -- 追踪特定怪物击杀（用于冒险者等级晋升条件）
    if monster.defId then
        GS.trackMonsterKill(monster.defId)
    end
    -- 竞技场/副本BOSS击杀：在死亡位置生成宝箱
    if GS.isDungeon then
        local phase = DungeonManager.getPhase()
        local chestRule = phase and phase.chestRule

        if GS.dungeonId == "goblin_arena" then
            -- 哥布林竞技场：每个BOSS都掉宝箱
            local bossChestDefs = {
                goblin_boss_diwu = true,
                goblin_boss_dila = true,
                goblin_boss_dikata = true,
            }
            if monster.defId and bossChestDefs[monster.defId] then
                local chest = {
                    x = monster.x, y = monster.y,
                    gold = 30000, opened = false,
                }
                -- 迪呜宝箱掉落：6件装备等概率随机1件
                if monster.defId == "goblin_boss_diwu" then
                    local diwuDropPool = {
                        "duel_dagger", "duel_sword", "duel_bow",
                        "duel_quiver", "shadow_cloak", "silver_needle_necklace",
                    }
                    local diwuPick = diwuDropPool[math.random(#diwuDropPool)]
                    chest.drops = { { id = diwuPick, enchantTier = 6 } }
                    print("[竞技场] 迪呜宝箱掉落: " .. diwuPick)
                end
                -- 迪拉宝箱掉落：6件装备等概率随机1件
                if monster.defId == "goblin_boss_dila" then
                    local dilaDropPool = {
                        "duel_staff", "duel_mace", "duel_crystal_ball",
                        "enlighten_necklace", "omniscient_trinket", "transcend_pants",
                    }
                    local dilaPick = dilaDropPool[math.random(#dilaDropPool)]
                    chest.drops = { { id = dilaPick, enchantTier = 6 } }
                    print("[竞技场] 迪拉宝箱掉落: " .. dilaPick)
                end
                -- 迪卡塔宝箱掉落：8件装备等概率随机1件
                if monster.defId == "goblin_boss_dikata" then
                    local dikataDropPool = {
                        "goblin_hero_helmet", "goblin_hero_shoulder", "goblin_hero_chest",
                        "goblin_hero_legs", "goblin_hero_gloves", "goblin_hero_boots",
                        "brave_necklace", "duel_shield",
                    }
                    local dikataPick = dikataDropPool[math.random(#dikataDropPool)]
                    chest.drops = { { id = dikataPick, enchantTier = 6 } }
                    print("[竞技场] 迪卡塔宝箱掉落: " .. dikataPick)
                end
                GS.arenaChests[#GS.arenaChests + 1] = chest
                print("[竞技场] BOSS宝箱生成于 (" .. monster.x .. "," .. monster.y .. ")")
            end
        elseif GS.dungeonId == "slime_kingdom" then
            if chestRule == "last_killed_boss" then
                -- 公主王子关：只在最后一个BOSS死亡时生成1个宝箱
                local slimeBossDefs = { slime_prince = true, slime_princess = true }
                if monster.defId and slimeBossDefs[monster.defId] then
                    -- 检查是否还有其他存活的BOSS
                    local otherBossAlive = false
                    for _, m in ipairs(GS.monsters) do
                        if m ~= monster and m.hp > 0 and m.defId and slimeBossDefs[m.defId] then
                            otherBossAlive = true
                            break
                        end
                    end
                    if not otherBossAlive then
                        -- 最后一个BOSS死亡，在其位置生成宝箱（含装备掉落）
                        local slimeDropPool = {
                            "holy_bow_trinket", "vengeance_gloves",
                            "prince_crown", "princess_crown",
                            "heart_dagger", "heart_sword",
                        }
                        local pick = slimeDropPool[math.random(#slimeDropPool)]
                        GS.arenaChests[#GS.arenaChests + 1] = {
                            x = monster.x, y = monster.y,
                            gold = 15000, opened = false,
                            drops = { { id = pick, enchantTier = 4 } },
                        }
                        print("[史莱姆王国] 王子公主宝箱生成于最后击杀位置 (" .. monster.x .. "," .. monster.y .. "), 掉落: " .. pick)
                    end
                end
            elseif chestRule == "boss_bottom_left" then
                -- 史莱姆王关：宝箱生成在4格BOSS身体的左下角
                if monster.defId == "slime_king" then
                    -- size=2 BOSS 占据 (x,y),(x+1,y),(x,y+1),(x+1,y+1)，左下角是 (x, y+1)
                    local chestX = monster.x
                    local chestY = monster.y + 1
                    -- 确保在棋盘内
                    if not GS.isInBoard(chestX, chestY) then
                        chestX, chestY = monster.x, monster.y
                    end
                    -- 国王宝箱掉落：6件装备等概率随机1件
                    local kingDropPool = {
                        "heart_staff", "heart_mace", "heart_bow",
                        "king_crown", "king_pants", "heart_necklace",
                    }
                    local kingPick = kingDropPool[math.random(#kingDropPool)]
                    GS.arenaChests[#GS.arenaChests + 1] = {
                        x = chestX, y = chestY,
                        gold = 15000, opened = false,
                        drops = { { id = kingPick, enchantTier = 4 } },
                    }
                    print("[史莱姆王国] 国王宝箱生成于左下角 (" .. chestX .. "," .. chestY .. "), 掉落: " .. kingPick)
                end
            end
        elseif GS.dungeonId == "tidal_sanctuary" then
            if chestRule == "boss_drop" then
                -- 杰尼/夸迪关：BOSS死亡时在其位置生成宝箱
                local tidalBossDefs = { tidal_boss_jeni = true, tidal_boss_kuadi = true }
                if monster.defId and tidalBossDefs[monster.defId] then
                    local chest = {
                        x = monster.x, y = monster.y,
                        gold = 50000, opened = false,
                    }
                    -- 杰尼宝箱掉落：5件装备等概率随机1件
                    if monster.defId == "tidal_boss_jeni" then
                        local jeniDropPool = {
                            "fish_scale_armor", "fish_scale_legs", "jessie_shell",
                            "fishman_turtle_shield", "iron_mountain_necklace",
                        }
                        local jeniPick = jeniDropPool[math.random(#jeniDropPool)]
                        chest.drops = { { id = jeniPick, enchantTier = 8 } }
                        print("[潮汐圣所] 杰尼宝箱掉落: " .. jeniPick)
                    end
                    -- 夸迪宝箱掉落：5件装备等概率随机1件；若命中元素亲和挂饰则再随机子类型
                    if monster.defId == "tidal_boss_kuadi" then
                        local kuadiDropPool = {
                            "fish_scale_helmet", "fish_scale_gloves", "fish_scale_shoulder_kuadi",
                            "elemental_trinket",
                            "horseshoe_necklace",
                            "thunder_amulet_necklace",
                        }
                        local kuadiPick = kuadiDropPool[math.random(#kuadiDropPool)]
                        if kuadiPick == "elemental_trinket" then
                            local elemVariants = { "elemental_trinket_fire", "elemental_trinket_ice",
                                                   "elemental_trinket_thunder", "elemental_trinket_holy" }
                            kuadiPick = elemVariants[math.random(#elemVariants)]
                        end
                        chest.drops = { { id = kuadiPick, enchantTier = 8 } }
                        print("[潮汐圣所] 夸迪宝箱掉落: " .. kuadiPick)
                    end
                    GS.arenaChests[#GS.arenaChests + 1] = chest
                    print("[潮汐圣所] BOSS宝箱生成于 (" .. monster.x .. "," .. monster.y .. ")")
                end
            elseif chestRule == "boss_bottom_left" then
                -- 不可知物关：宝箱生成在4格BOSS身体的左下角
                if monster.defId == "tidal_boss_unknown" then
                    local chestX = monster.x
                    local chestY = monster.y + 1
                    if not GS.isInBoard(chestX, chestY) then
                        chestX, chestY = monster.x, monster.y
                    end
                    local unknownChest = {
                        x = chestX, y = chestY,
                        gold = 50000, opened = false,
                    }
                    -- 不可名物宝箱掉落：5件装备等概率随机1件
                    local unknownDropPool = {
                        "heresy_dagger", "heresy_staff", "heresy_bow",
                        "heresy_cloak", "unknown_eye_trinket", "insight_necklace",
                    }
                    local unknownPick = unknownDropPool[math.random(#unknownDropPool)]
                    unknownChest.drops = { { id = unknownPick, enchantTier = 8 } }
                    print("[潮汐圣所] 不可知物宝箱掉落: " .. unknownPick)
                    GS.arenaChests[#GS.arenaChests + 1] = unknownChest
                    print("[潮汐圣所] 不可知物宝箱生成于左下角 (" .. chestX .. "," .. chestY .. ")")
                end
            end
        end
    end
    -- 按关卡击杀计数（用于关卡解锁）
    if GS.currentStage then
        GS.stageKillCounts[GS.currentStage] = (GS.stageKillCounts[GS.currentStage] or 0) + 1
    end

    -- 采集区清空检测：noRespawn 关卡中所有怪物死亡时标记 stageClearedOnce
    if GS.currentStage and not GS.stageClearedOnce[GS.currentStage] then
        local curStage = GS.STAGE_DEFS[GS.currentStage]
        if curStage and curStage.noRespawn then
            local allDead = true
            for _, m in ipairs(GS.monsters) do
                if m.hp > 0 then allDead = false; break end
            end
            if allDead then
                GS.stageClearedOnce[GS.currentStage] = true
                print("[采集] 关卡 " .. GS.currentStage .. " 首次清空！")
            end
        end
    end

    -- 事件怪物：跳过所有掉落和经验
    if monster.noDrop then return end

    -- 经验奖励（含等级衰减）
    -- creditAttacker：伴侣击杀时归给玩家，否则归给攻击者本身
    local baseExp = monster.expReward or 0
    if not creditAttacker.isMonster and creditAttacker.exp and baseExp > 0 then
        local finalExp = M.calcExp(creditAttacker.level or 1, monster.level or 1, baseExp)
        -- 装备击杀经验加成（killExpBonus 为百分比值，如 20 代表 +20%）
        local eb = GS.getEquipBonus and GS.getEquipBonus() or {}
        local killExpPct = eb.killExpBonus or 0
        if killExpPct > 0 then
            finalExp = math.floor(finalExp * (1 + killExpPct / 100))
        end
        if finalExp > 0 then
            creditAttacker.exp = creditAttacker.exp + finalExp
            if creditAttacker.level >= 100 then
                creditAttacker.exp = math.min(creditAttacker.exp, 99999999)
            else
                M.checkLevelUp(creditAttacker)
            end
        end
    end

    -- 掉落物品
    if monster.drops then
        for _, drop in ipairs(monster.drops) do
            if math.random() < (drop.chance or 0) then
                -- 如果 drop 有 pool（多选一），从 pool 中随机选一个 id
                local dropId = drop.id
                if drop.pool then
                    dropId = drop.pool[math.random(#drop.pool)]
                end
                -- 特殊掉落：金币（@gold）
                if dropId == "@gold" then
                    local amount = drop.amount or 1
                    GS.gold = GS.gold + amount
                    GS.score = GS.score + amount
                    M.addDamageText(monster.x, monster.y - 1.0,
                        "+" .. amount .. "G", {255, 215, 0})
                else
                    -- 拾取过滤：基础掉落组装备（enchantTier 不为 nil，且非宝箱哥布林掉落）可按稀有度过滤丢弃
                    if drop.enchantTier ~= nil and not drop.isChestGoblinDrop then
                        local tpl = GS.itemTemplates[dropId]
                        if tpl then
                            local r = tpl.rarity or "common"
                            if (GS.lootFilterNoFine and r == "uncommon")
                                or (GS.lootFilterNoRare and r == "rare")
                                or (GS.lootFilterNoFineGrade and r == "fine") then
                                local dropName = tpl.name or dropId
                                M.addDamageText(monster.x, monster.y - 1.0,
                                    dropName .. "[已弃置]", {160, 160, 160})
                                goto continueDropLoop
                            end
                        end
                    end
                    local ok, msg, addedItem = GS.addToInventory(dropId, 1)
                    if ok then
                        -- 附魔判定（仅基础掉落组的优秀装备）
                        if addedItem and drop.enchantTier ~= nil then
                            addedItem.tier = drop.enchantTier  -- 保存 T 级（精炼系统需要）
                            -- forceEnchant=true 时必定附魔，否则按概率
                            if drop.forceEnchant or math.random() < GS.ENCHANT_CHANCE then
                                GS.rollEnchantment(addedItem, drop.enchantTier)
                            end
                            -- 精炼槽位判定（noRefineSlots=true 时跳过）
                            if not drop.noRefineSlots then
                                GS.rollRefineSlots(addedItem, drop.enchantTier)
                            end
                            -- 宝石插槽判定（noGemSlots=true 时跳过）
                            if not drop.noGemSlots then
                                GS.rollGemSlots(addedItem)
                            end
                            -- 深渊词缀判定
                            if drop.isAbyssDrop then
                                -- 深渊掉落：33%概率
                                GS.rollAbyssAffix(addedItem)
                            end
                        end
                        local tpl = GS.itemTemplates[dropId]
                        local dropName = tpl and tpl.name or dropId
                        M.addDamageText(monster.x, monster.y - 1.0,
                            "+" .. dropName, {180, 220, 255})
                    else
                        local tpl = GS.itemTemplates[dropId]
                        M.addDamageText(monster.x, monster.y - 1.0,
                            "背包已满! " .. (tpl and tpl.name or dropId) .. " 丢失", {255, 80, 80})
                    end
                end
            end
            ::continueDropLoop::
        end
    end

    -- 装备效果：击杀回血（归属给 creditAttacker，伴侣击杀时触发玩家装备效果）
    if not creditAttacker.isMonster and (creditAttacker.onKillHealHp or 0) > 0 and creditAttacker.hp > 0 then
        local healAmt = creditAttacker.onKillHealHp
        -- 治疗效果加成
        if (creditAttacker.healEffectPct or 0) > 0 then
            healAmt = math.floor(healAmt * (1 + creditAttacker.healEffectPct / 100))
        end
        local oldHp = creditAttacker.hp
        creditAttacker.hp = math.min(creditAttacker.hp + healAmt, creditAttacker.maxHp)
        if creditAttacker.hp > oldHp then
            M.addHealEffect(creditAttacker.x, creditAttacker.y, creditAttacker)
        end
        M.triggerRadianceDamage(healAmt)
    end

    -- 莉娜任务「睹物思人」：巴洛庄园每层掉落一种物品（独立任务）
    -- 睹物思人一: manor_2=手帕(1楼), manor_3=胸针(2楼), manor_4=怀表(3楼)
    -- 睹物思人二: manor_5=狮子玩偶(4楼)
    if not attacker.isMonster and GS.currentStage then
        local QM = require("QuestManager")
        local LINA_MANOR_DROPS = {
            { stage = GS.STAGE_GHOST,     itemId = "old_handkerchief",  questId = "side_lina_manor_2" },
            { stage = GS.STAGE_FURNITURE, itemId = "old_brooch",        questId = "side_lina_manor_3" },
            { stage = GS.STAGE_DOLLS,     itemId = "old_pocket_watch",  questId = "side_lina_manor_4" },
            { stage = GS.STAGE_VAMPIRES,  itemId = "old_lion_doll",     questId = "side_lina_manor_5" },
        }
        for _, ld in ipairs(LINA_MANOR_DROPS) do
            if GS.currentStage == ld.stage then
                local st = QM.questStates[ld.questId]
                if st and st.status == QM.STATUS_ACTIVE then
                    -- 已提交过的物品不再掉落
                    if st.submittedItems and st.submittedItems[ld.itemId] then
                        break
                    end
                    -- 背包中已有此物品则不再掉落
                    local hasItem = false
                    for _, inv in ipairs(GS.inventory) do
                        if inv.templateId == ld.itemId then hasItem = true; break end
                    end
                    if not hasItem and math.random() < 0.03 then
                        local ok2, _, _ = GS.addToInventory(ld.itemId, 1)
                        if ok2 then
                            local tpl = GS.itemTemplates[ld.itemId]
                            M.addDamageText(monster.x, monster.y - 1.0,
                                "+" .. (tpl and tpl.name or ld.itemId) .. " [任务]",
                                {255, 200, 50})
                        else
                            local tpl = GS.itemTemplates[ld.itemId]
                            M.addDamageText(monster.x, monster.y - 1.0,
                                "背包已满! " .. (tpl and tpl.name or ld.itemId) .. " 丢失",
                                {255, 80, 80})
                        end
                    end
                end
                break
            end
        end
    end

    -- 精炼石独立掉落（3%概率，根据怪物等级决定阶数，11级以下不掉）
    local mLv = monster.level or 1
    local stoneTier = math.min(10, math.ceil(mLv / 10))  -- 1~10级→1阶(不存在), 11~20级→2阶, ...
    if stoneTier >= 2 and math.random() < 0.03 then
        local stoneId = "refine_stone_" .. stoneTier
        local ok, msg, addedItem = GS.addToInventory(stoneId, 1)
        if ok then
            local tpl = GS.itemTemplates[stoneId]
            M.addDamageText(monster.x, monster.y - 1.0,
                "+" .. (tpl and tpl.name or stoneId), {255, 200, 100})
        else
            local tpl = GS.itemTemplates[stoneId]
            M.addDamageText(monster.x, monster.y - 1.0,
                "背包已满! " .. (tpl and tpl.name or stoneId) .. " 丢失", {255, 80, 80})
        end
    end

    -- 异世深渊卓越武器掉落（词缀怪 1%，普通怪 0.01%）
    local abyssWeaponDropChance = 0
    if GS.isAbyssWorld then
        if monster.affix then
            abyssWeaponDropChance = 0.01    -- 词缀怪 1%
        else
            abyssWeaponDropChance = 0.0001  -- 普通怪 0.01%
        end
    end
    if abyssWeaponDropChance > 0 and math.random() < abyssWeaponDropChance then
        -- 确定当前深渊层数（1~5）
        local abyssFloor = nil
        for i = 1, 5 do
            if GS.currentStage == GS["STAGE_ABYSS_" .. i] then
                abyssFloor = i
                break
            end
        end
        if abyssFloor and GS.ABYSS_WEAPON_POOLS then
            -- 构建当前层的合并武器池（自身池 + 继承层池）
            local combinedPool = {}
            for _, wId in ipairs(GS.ABYSS_WEAPON_POOLS[abyssFloor] or {}) do
                combinedPool[#combinedPool + 1] = wId
            end
            local inherit = GS.ABYSS_POOL_INHERIT and GS.ABYSS_POOL_INHERIT[abyssFloor]
            if inherit then
                for _, inheritFloor in ipairs(inherit) do
                    for _, wId in ipairs(GS.ABYSS_WEAPON_POOLS[inheritFloor] or {}) do
                        combinedPool[#combinedPool + 1] = wId
                    end
                end
            end
            if #combinedPool > 0 then
                local chosenId = combinedPool[math.random(#combinedPool)]
                local tpl = GS.itemTemplates[chosenId]
                local ok2, _, addedItem = GS.addToInventory(chosenId, 1)
                if ok2 and addedItem then
                    -- 使用物品等级确定 tier
                    local itemLevel = (tpl and tpl.level) or 1
                    local tier = GS.getTierByLevel(itemLevel)
                    addedItem.tier = tier
                    -- 附魔（33%概率）
                    if math.random() < GS.ENCHANT_CHANCE then
                        GS.rollEnchantment(addedItem, tier)
                    end
                    -- 精炼槽
                    GS.rollRefineSlots(addedItem, tier)
                    -- 宝石槽
                    GS.rollGemSlots(addedItem)
                    -- 深渊武器随机属性（创建独立副本后随机化）
                    local abyssRand = tpl and tpl.abyssRandomStats
                    if abyssRand then
                        -- 创建 effects / extraEffects 独立副本
                        local newEff = {}
                        for k, v in pairs(addedItem.effects or {}) do newEff[k] = v end
                        addedItem.effects = newEff
                        local newExtra = {}
                        for k, v in pairs(addedItem.extraEffects or {}) do newExtra[k] = v end
                        addedItem.extraEffects = newExtra
                        local statTiers = {}
                        -- 随机化 effects（pct_uniform：五档百分比浮动；uniform：等权重列表）
                        if abyssRand.effects then
                            for k, rule in pairs(abyssRand.effects) do
                                if rule.type == "pct_uniform" and newEff[k] and rule.values and #rule.values > 0 then
                                    local base = newEff[k]
                                    local idx = math.random(#rule.values)
                                    local pct = rule.values[idx]
                                    newEff[k] = math.floor(base * (1 + pct / 100) + 0.5)
                                    statTiers[k] = idx
                                elseif rule.type == "uniform" and rule.values and #rule.values > 0 then
                                    local idx = math.random(#rule.values)
                                    newEff[k] = rule.values[idx]
                                    statTiers[k] = idx
                                end
                            end
                        end
                        -- 随机化 extraEffects（uniform：等权重列表）
                        if abyssRand.extraEffects then
                            for k, rule in pairs(abyssRand.extraEffects) do
                                if rule.type == "uniform" and rule.values and #rule.values > 0 then
                                    local idx = math.random(#rule.values)
                                    newExtra[k] = rule.values[idx]
                                    -- tier：索引即档位（1=N … 5=SSR）
                                    statTiers[k] = idx
                                end
                            end
                        end
                        -- allstat_lines：N条全属性词缀，每条独立随机一个值加到所有属性
                        if abyssRand.allstat_lines then
                            local asl = abyssRand.allstat_lines
                            local lineResults = {}
                            for i = 1, (asl.count or 1) do
                                local idx = math.random(#asl.values)
                                local val = asl.values[idx]
                                lineResults[i] = { value = val, tier = idx }
                                for _, k in ipairs(asl.keys) do
                                    newExtra[k] = (newExtra[k] or 0) + val
                                end
                            end
                            addedItem.allstatLines = lineResults
                        end
                        -- randomResist：从 pool 中随机选 count 个不重复的抗性键，各自独立随机档位
                        -- 支持单对象或数组（多段独立随机池）
                        if abyssRand.randomResist then
                            local rrList = abyssRand.randomResist
                            if rrList.pool then rrList = { rrList } end  -- 单对象兼容
                            local resistResults = {}
                            for _, rr in ipairs(rrList) do
                                local pool = {}
                                for i, v in ipairs(rr.pool) do pool[i] = v end
                                for i = #pool, 2, -1 do
                                    local j = math.random(i)
                                    pool[i], pool[j] = pool[j], pool[i]
                                end
                                for i = 1, math.min(rr.count or 3, #pool) do
                                    local key = pool[i]
                                    local idx = math.random(#rr.values)
                                    local val = rr.values[idx]
                                    newExtra[key] = val
                                    statTiers[key] = idx
                                    resistResults[#resistResults + 1] = { key = key, value = val, tier = idx }
                                end
                            end
                            addedItem.randomResistLines = resistResults
                        end
                        -- randomMainBase：从 pool 中随机选 count 种主属性作为基础效果
                        if abyssRand.randomMainBase then
                            local rmb = abyssRand.randomMainBase
                            local pool = {}
                            for i, v in ipairs(rmb.pool) do pool[i] = v end
                            for i = #pool, 2, -1 do
                                local j = math.random(i)
                                pool[i], pool[j] = pool[j], pool[i]
                            end
                            local baseLines = {}
                            for i = 1, math.min(rmb.count or 1, #pool) do
                                local key = pool[i]
                                local val = rmb.value or 1
                                newEff[key] = (newEff[key] or 0) + val
                                baseLines[i] = { key = key, value = val }
                            end
                            addedItem.randomMainBaseLines = baseLines
                        end
                        -- randomMainExtra：从 pool 中随机选 count 条主属性词缀（可重复），值随机
                        if abyssRand.randomMainExtra then
                            local rme = abyssRand.randomMainExtra
                            local extraLines = {}
                            for i = 1, (rme.count or 1) do
                                local key = rme.pool[math.random(#rme.pool)]
                                local idx = math.random(#rme.values)
                                local val = rme.values[idx]
                                newExtra[key] = (newExtra[key] or 0) + val
                                extraLines[i] = { key = key, value = val, tier = idx }
                            end
                            addedItem.randomMainExtraLines = extraLines
                        end
                        addedItem.abyssStatTiers = statTiers
                        addedItem.hasRandom = true
                    end
                    -- forceAbyssAffix：必定携带深渊词缀的卓越装备
                    if tpl and tpl.forceAbyssAffix then
                        local roll = GS.ABYSS_AFFIX_POOL[math.random(#GS.ABYSS_AFFIX_POOL)]
                        addedItem.abyssAffix = {
                            id = roll.id, name = roll.name,
                            desc = roll.desc, mechanic = roll.mechanic,
                        }
                    end
                    -- randomAbyssAffixLimit：随机1种深渊词缀的生效上限（值从模板读取）
                    if tpl and tpl.randomAbyssAffixLimit then
                        local roll = GS.ABYSS_AFFIX_POOL[math.random(#GS.ABYSS_AFFIX_POOL)]
                        addedItem.abyssAffixLimitTarget = {
                            id = roll.id, name = roll.name, mechanic = roll.mechanic,
                        }
                    end
                    local dropName = (tpl and tpl.name) or chosenId
                    M.addDamageText(monster.x, monster.y - 1.5,
                        "【卓越】" .. dropName .. " 已获得！", {255, 215, 0})
                    -- 触发橙光闪烁特效
                    GS.triggerSuperiorDropFlash()
                else
                    local dropName = (tpl and tpl.name) or chosenId
                    M.addDamageText(monster.x, monster.y - 1.5,
                        "背包已满! 【" .. dropName .. "】丢失", {255, 80, 80})
                end
            end
        end
    end
end

-- ====================================================================
-- 经验衰减：玩家超过怪物7级后，第8级起每级线性衰减20%，超过12级为0
-- ====================================================================
function M.calcExp(playerLevel, monsterLevel, baseExp)
    local diff = playerLevel - monsterLevel
    if diff <= 7 then return baseExp end
    if diff >= 12 then return 0 end
    -- diff 8~11: 80%→60%→40%→20%
    local rate = (100 - (diff - 7) * 20) / 100
    return math.floor(baseExp * rate * 10) / 10
end

-- ====================================================================
-- 伤害飘字
-- ====================================================================
function M.addDamageText(x, y, text, color, scale)
    -- 将文本中的数字限制为最多1位小数
    text = tostring(text):gsub("(%d+%.%d+)", function(n)
        local v = tonumber(n)
        if v and v == math.floor(v) then
            return tostring(math.floor(v))
        end
        return string.format("%.1f", v)
    end)
    local baseDelay = M._damageTextDelay or 0

    -- 自动错开：仅对非数字文本（状态/技能名等）生效，纯伤害数字不错开
    local yOffset = 0
    local xOffset = 0
    local isNumericText = text:match("^[%d%-%+%.!]+$") ~= nil or text == "Miss"  -- 纯数字/符号/Miss文本
    if not isNumericText then
        -- 随机向四周偏移，避免重叠
        local spread = 12
        xOffset = math.random(-spread, spread)
        yOffset = math.random(-spread, spread)
    end

    table.insert(GS.damageTexts, {
        x = x, y = y, text = text,
        timer = 0, duration = 1.0,
        color = color or {255, 50, 50},
        scale = scale or 1.0,
        yOffset = yOffset,  -- 自动错开偏移（Y）
        xOffset = xOffset,  -- 自动错开偏移（X）
        isNumeric = isNumericText,  -- 纯数字文本标记
        style = M._damageTextStyle or nil,  -- 特殊样式："block"=格挡碰撞感
        pendingHit = M._pendingProjectileHit or false,  -- 弹道类：等命中后才显示
        projectileId = M._pendingProjectileHit and M._currentProjectileId or nil,  -- 关联弹道ID
        delay = baseDelay,  -- 延迟显示（秒），用于技能特效同步
    })
    M._damageTextStyle = nil
end

--- 技能施放文本：根据技能元素自动选择颜色
local ELEMENT_COLORS = {
    fire    = {255, 120, 40},   -- 火焰橙红
    ice     = {100, 200, 255},  -- 冰蓝
    thunder = {255, 220, 60},   -- 雷电黄
    holy    = {255, 220, 100},  -- 神圣金色
    arcane  = {160, 120, 240},  -- 奥术紫色
}
function M.addSkillCastText(x, y, skillId)
    local def = GS.SKILL_DEFS[skillId]
    if not def or not def.name then return end
    -- 防重复：同一 skillId 同一帧只显示一次（Input 层先调用，Combat 内部再调用时跳过）
    if M._lastSkillTextId == skillId then return end
    M._lastSkillTextId = skillId
    local color = ELEMENT_COLORS[def.element] or {255, 255, 255}  -- 默认白色（物理）
    M.addDamageText(x, y - 0.5, def.name .. "!", color)
end

-- ====================================================================
-- 治疗特效（羁绊链接等）
-- 全局限制：同时最多1个治疗/吸血特效（上一个播完才能创建下一个）
-- ====================================================================
function M.addHealEffect(x, y, unit)
    -- 允许同时显示多个治疗特效（羁绊链接等需要同时治疗多个目标）
    -- 同一单位不重复添加
    for _, e in ipairs(GS.healEffects) do
        if e.unit == unit then return end
    end
    table.insert(GS.healEffects, {
        x = x, y = y,
        unit = unit,
        timer = 0, duration = 0.8,
    })
end

-- ====================================================================
-- 吸血公共函数：计算回复 + 飘字 + 粒子特效
-- useMagic: true=法术伤害, false/nil=物理伤害
-- ====================================================================
--- 羁绊链接：玩家/猎犬造成伤害时互相治疗
function M.applyBondLink(attacker, dmg)
    if M._bondLinkProcessing then return end
    if not dmg or dmg <= 0 then return end
    if (GS.skillLevels["h_bond_link"] or 0) <= 0 then return end
    local blDef = GS.SKILL_DEFS["h_bond_link"]
    local blLv = GS.skillLevels["h_bond_link"] or 0
    local healPct = (blDef.bondHealPctPerLv or 1) * blLv
    local heal = math.floor(dmg * healPct / 100)
    if GS.player and (GS.player.healEffectPct or 0) > 0 then
        heal = math.floor(heal * (1 + GS.player.healEffectPct / 100))
    end
    if heal <= 0 then return end
    M._bondLinkProcessing = true
    if attacker == GS.player then
        for _, c in ipairs(GS.companions) do
            if c.hp and c.hp > 0 then
                local actualH = math.min(heal, c.maxHp - c.hp)
                c.hp = c.hp + actualH
                M.addHealEffect(c.x, c.y, c)
            end
        end
    elseif attacker and attacker.isCompanion then
        if GS.player and GS.player.hp > 0 then
            local actualH = math.min(heal, GS.player.maxHp - GS.player.hp)
            GS.player.hp = GS.player.hp + actualH
            M.addHealEffect(GS.player.x, GS.player.y, GS.player)
            M.triggerRadianceDamage(heal)
        end
    end
    M._bondLinkProcessing = nil
end

function M.applyLifesteal(attacker, dmg, useMagic)
    if not attacker or not attacker.hp or not attacker.maxHp then return end

    -- 1) 蝙蝠牙吸血（专属），每件装备独立上限10点
    local batPct = attacker.batFangLifesteal or 0
    local batHeal = 0
    if batPct > 0 then
        batHeal = math.floor(dmg * batPct / 100)
        local batCap = attacker.batFangLifestealCap or 10
        if batCap > 0 then batHeal = math.min(batHeal, batCap) end
    end

    -- 2) 通用吸血（无上限）
    local basePct = attacker.lifesteal or 0
    local baseHeal = 0
    if basePct > 0 then
        baseHeal = math.floor(dmg * basePct / 100)
    end

    -- 3) 精炼词缀吸血（物理/法术，无上限）
    local refinePct = 0
    if useMagic then
        refinePct = attacker.magLifesteal or 0
    else
        refinePct = attacker.physLifesteal or 0
    end
    local refineHeal = 0
    if refinePct > 0 then
        refineHeal = math.floor(dmg * refinePct / 100)
    end

    local heal = batHeal + baseHeal + refineHeal
    if heal > 0 then
        local actualHeal = math.min(heal, attacker.maxHp - attacker.hp)
        attacker.hp = attacker.hp + actualHeal
        M.addHealEffect(attacker.x, attacker.y, attacker)
        -- 饮血：过量吸血存储为护甲值
        if not attacker.isMonster then
            local bloodDrinkLv = GS.skillLevels["w_blood_drink"] or 0
            if bloodDrinkLv > 0 then
                local overheal = heal - actualHeal
                if overheal > 0 then
                    local cap = math.floor(attacker.maxHp * 0.02 * bloodDrinkLv)
                    local oldShield = GS.bloodShield or 0
                    local storeAmount = math.floor(overheal * 0.5)
                    GS.bloodShield = math.min(cap, oldShield + storeAmount)
                    local gained = GS.bloodShield - oldShield
                end
            end
        end
    end

    -- 魔力回收：魔法伤害的一定百分比回复MP（套装+装备词缀叠加）
    if useMagic and not attacker.isMonster and (attacker.maxMp or 0) > 0 then
        local setB4 = GS.getSetBonus()
        local leechPct = (setB4.manaLeech or 0) + (attacker.manaLeech or 0)
        if leechPct > 0 then
            local mpRestore = math.floor(dmg * leechPct / 100)
            if mpRestore > 0 then
                table.insert(GS.pendingMpRestores, {
                    target = attacker,
                    amount = mpRestore,
                    delay = M._damageTextDelay or 0,
                    pendingHit = M._pendingProjectileHit or false,
                    projectileId = M._pendingProjectileHit and M._currentProjectileId or nil,
                })
            end
        end
    end

    -- 魔法石项链：根据造成伤害的百分比回复魔法值（所有伤害类型）
    if not attacker.isMonster and (attacker.maxMp or 0) > 0 then
        local dtmPct = attacker.dmgToMpPct or 0
        if dtmPct > 0 then
            local mpRestore = math.floor(dmg * dtmPct / 100)
            if mpRestore > 0 then
                table.insert(GS.pendingMpRestores, {
                    target = attacker,
                    amount = mpRestore,
                    delay = M._damageTextDelay or 0,
                    pendingHit = M._pendingProjectileHit or false,
                    projectileId = M._pendingProjectileHit and M._currentProjectileId or nil,
                })
            end
        end
    end
end

-- ====================================================================
-- 神佑特效（神圣金色粒子蒸腾）
-- ====================================================================
function M.addDivineGraceEffect(x, y)
    table.insert(GS.divineGraceEffects, {
        x = x, y = y,
        timer = 0, duration = 0.9,
    })
end

-- ====================================================================
-- 圣树冲击波特效（圆环向外扩散）
-- ====================================================================
function M.addHolyTreeWaveEffect(x, y, healRange)
    table.insert(GS.holyTreeWaveEffects, {
        x = x, y = y,
        healRange = healRange,
        timer = 0, duration = 0.7,
    })
end

-- ====================================================================
-- 辉光系统：被动技能 + 深渊词缀（治疗量→对周围敌人造成神圣魔法伤害，受魔防减免）
-- ====================================================================

--- 统计装备中辉光词缀叠加层数（深渊词缀部分）
local function getRadianceStacks()
    -- 聚焦器：屏蔽辉光
    if GS.player and (GS.player.focuserDmgPer or 0) > 0 then return 0 end
    local stacks = countAbyssAffix("radiance")
    return stacks
end

--- 获取辉光被动技能的伤害百分比（0 表示未学习）
local function getRadianceSkillPct()
    local lv = GS.skillLevels and GS.skillLevels["p_radiance"] or 0
    if lv <= 0 then return 0 end
    -- 120% + 20%/等级（lv1=120%, lv2=140%, ..., lv10=300%）
    return 120 + 20 * (lv - 1)
end

--- 获取辉光被动技能的额外范围加成（满级+1）
local function getRadianceSkillRangeBonus()
    local lv = GS.skillLevels and GS.skillLevels["p_radiance"] or 0
    if lv >= (GS.SKILL_MAX_LEVEL or 10) then return 1 end
    return 0
end

--- 触发辉光伤害（治疗时调用，healAmount 为治疗量，含过量治疗）
--- 伤害类型：神圣属性魔法伤害
---   · 受怪物魔防（mdef）减免：mAtk / (mAtk + mdef)
---   · 受玩家神圣伤害加成（lightDmgBonus）
---   · 受怪物神圣属性抗性（×0.7）/ 弱点（×1.3）影响
--- 注意：辉光伤害不触发吸血，避免无限递归
function M.triggerRadianceDamage(healAmount)
    if not healAmount or healAmount <= 0 then return end
    -- 圣光结晶：治疗存储（在辉光判断之前，存储不受隐匿影响）
    do
        local pl = GS.player
        if pl and pl.hp > 0 and (pl.healStoreRate or 0) > 0 and not pl._holyCrystalReleasing then
            local storeAmt = math.floor(healAmount * pl.healStoreRate / 100)
            if storeAmt > 0 then
                pl._holyCrystalStore = (pl._holyCrystalStore or 0) + storeAmt
            end
        end
    end
    -- 隐匿期间不触发辉光（包括幻影技能触发的隐匿）
    if GS.stealthActive then return end
    -- 辉光伤害 = 词缀部分(300%×层数) + 技能被动部分(120%+20%/lv)
    local stacks = getRadianceStacks()
    local skillPct = getRadianceSkillPct()
    if stacks <= 0 and skillPct <= 0 then return end
    -- 词缀：healAmount × 3.0 × stacks；技能：healAmount × skillPct/100
    local baseDmg = math.floor(healAmount * (3.0 * stacks + skillPct / 100))
    if baseDmg <= 0 then return end
    -- 辉光作用范围：基础2格（欧几里得距离，圆形）+ 技能扩展加成 + 被动满级加成
    local p = GS.player
    local radianceRange = 2 + getAoeRangeBonus() + getRadianceSkillRangeBonus()
    -- 添加辉光扩散特效（从玩家位置向外扩散，携带范围信息）
    if p and p.hp > 0 then
        table.insert(GS.radianceWaveEffects, {
            x = p.x, y = p.y,
            timer = 0, duration = 0.8,
            range = radianceRange,
        })
    end
    -- ── 辉光全局加成 ────────────────────────────────────────────────────────
    -- 第一层：加算池（神圣/辉光专属/魔法/武器/全属性），合并后一次乘入
    local globalPct = 0
    globalPct = globalPct + (p and (p.lightDmgBonus    or 0) or 0)  -- 神圣伤害加成
    globalPct = globalPct + (p and (p.radianceDmgBonus or 0) or 0)  -- 辉光专属加成
    globalPct = globalPct + (p and (p.magDmgBonus      or 0) or 0)  -- 魔法伤害加成
    -- 武器类型加成：装备对应武器才生效（牧师可用：单手剑/锤/法杖）
    local wt = p and p.weaponTag or ""
    if     wt == "单手剑" then globalPct = globalPct + (p.swordDmgBonus or 0)
    elseif wt == "锤"     then globalPct = globalPct + (p.maceDmgBonus  or 0)
    elseif wt == "法杖"   then globalPct = globalPct + (p.staffDmgBonus or 0)
    end
    globalPct = globalPct + (p and (p.allStatDmgBonus  or 0) or 0)  -- 全属性伤害加成
    if globalPct > 0 then
        baseDmg = math.max(1, math.floor(baseDmg * (1 + globalPct / 100)))
    end
    -- 第二层：宇宙奥秘8件套（乘算，独立）
    do
        local setB8 = GS.getSetBonus()
        local coeff = setB8.manaPctMagDmg or 0
        if coeff > 0 and p and (p.maxMp or 0) > 0 then
            local mpPct   = (p.mp or 0) / p.maxMp
            local bonusPct = math.floor(mpPct * coeff * 100)
            if bonusPct > 0 then
                baseDmg = math.max(1, math.floor(baseDmg * (1 + bonusPct / 100)))
            end
        end
    end
    -- 第三层：狡诈奇美拉8件套（乘算，独立）
    do
        local setB8    = GS.getSetBonus()
        local ampCoeff = setB8.hitCountDmgAmp or 0
        if ampCoeff > 0 and (GS._slyLastTurnHitCount or 0) > 0 then
            local count    = math.min(GS._slyLastTurnHitCount, 10)
            local bonusPct = count * ampCoeff
            baseDmg = math.max(1, math.floor(baseDmg * (1 + bonusPct / 100)))
        end
    end
    -- ────────────────────────────────────────────────────────────────────────
    -- 玩家魔攻（用于魔防减免比例计算）
    local mAtk = math.max(1, p and (p.mAtk or p.atk or 1) or 1)
    -- 对玩家周围 radianceRange 格（欧几里得距离，圆形）内的怪物造成神圣属性魔法伤害
    local anyKilled = false
    local totalRadianceDmg = 0  -- 累计辉光总伤害，循环后统一吸血
    local px, py = p and p.x or 0, p and p.y or 0
    for _, m in ipairs(GS.monsters) do
        if m.hp and m.hp > 0 and inCircleRange(m.x, m.y, px, py, radianceRange) then
            -- 闪避判定
            if rollDodge(p, m, nil) then
                M.addDamageText(m.x, m.y, "Miss", {255, 255, 255})
            else
                -- 1) 魔防减免：mAtk / (mAtk + mdef)
                local mdef = m.mdef or m.def or 0
                local dmg = math.floor(baseDmg * mAtk / math.max(1, mAtk + mdef))
                dmg = math.max(1, dmg)
                -- 2) 神圣属性抗性（-30%）/ 弱点（+30%）
                if m.resistance then
                    for _, r in ipairs(m.resistance) do
                        if r == "holy" then
                            dmg = math.max(1, math.floor(dmg * 0.7))
                            break
                        end
                    end
                end
                if m.weakness then
                    for _, w in ipairs(m.weakness) do
                        if w == "holy" then
                            dmg = math.max(1, math.floor(dmg * 1.3))
                            break
                        end
                    end
                end
                -- 近处额外加成：nearDmgBonus（暴风眼）+ radianceNearDmgBonus（辉光专属），加算
                do
                    local nearPct = (p and (p.nearDmgBonus or 0) or 0)
                                  + (p and (p.radianceNearDmgBonus or 0) or 0)
                    if nearPct > 0 then
                        local dx = math.abs(m.x - px)
                        local dy = math.abs(m.y - py)
                        if math.max(dx, dy) <= 1 then
                            dmg = math.max(1, math.floor(dmg * (1 + nearPct / 100)))
                        end
                    end
                end
                -- 暴击判定（使用魔法暴击属性：mCritRate / mCritDmg）
                local isCrit
                dmg, isCrit = rollCrit(p, m, dmg, nil, { useMagic = true })
                m.hp = m.hp - dmg
                trackTrainingDamage(m, dmg)
                immortalGuard(m, dmg)
                if isCrit then
                    M.addDamageText(m.x, m.y, dmg .. "!", {255, 230, 140}, 1.5)
                    GS.setScreenShake(0.15, 2, M._damageTextDelay or 0)
                else
                    M.addDamageText(m.x, m.y, "" .. dmg, {255, 230, 140})
                end
                M.addHurtFlash(m)
                totalRadianceDmg = totalRadianceDmg + dmg
                -- 辉光晕眩判定（至高天+天使联动词条，英雄单位免疫）
                if m.hp > 0 and not m.stunned and not isHeroUnit(m) then
                    local stunChance = p and (p.radianceStunChance or 0) or 0
                    if stunChance > 0 and math.random(100) <= stunChance then
                        m.stunned = 1
                        M.addDamageText(m.x, m.y - 0.5, "晕眩!", {255, 220, 60})
                    end
                end
                if m.hp <= 0 then
                    m.hp = 0
                    M.processMonsterKill(p, m)
                    anyKilled = true
                end
            end
        end
    end
    -- 辉光总伤害统一触发一次法术吸血（合并特效，避免 N 只怪物叠 N 次回血粒子）
    if totalRadianceDmg > 0 then
        M.applyLifesteal(p, totalRadianceDmg, true)
    end
    -- 辉光击杀怪物后必须清理尸体，否则副本通关判定永远不触发
    if anyKilled then
        M.removeDeadMonsters()
    end
end

-- ====================================================================
-- 升级检查
-- ====================================================================
function M.checkLevelUp(unit)
    if unit.level >= 100 then return end
    local needed = GS.expToNextLevel(unit.level)
    local didLevelUp = false
    while unit.exp >= needed do
        didLevelUp = true
        unit.exp = unit.exp - needed
        unit.level = unit.level + 1
        unit.statPoints = unit.statPoints + 3
        if unit == GS.player then
            GS.skillPoints = GS.skillPoints + 1
        end
        if unit.level >= 100 then
            unit.level = 100
            unit.exp = math.min(unit.exp, 99999999)  -- 保留溢出经验，上限99999999
            M.addDamageText(unit.x, unit.y, "满级! Lv.100", {255, 255, 100})
            break
        end
        needed = GS.expToNextLevel(unit.level)
        M.addDamageText(unit.x, unit.y, "升级! Lv." .. unit.level, {255, 255, 100})
    end
    -- 升级后更新商店商品档次
    if unit == GS.player then
        GS.updateShopByLevel()
    end
    -- 仅在实际升级时：先重算属性（提高maxHp/maxMp上限），再回满HP/MP
    if didLevelUp then
        GS.recalcStats(unit)
        unit.hp = unit.maxHp
        unit.mp = unit.maxMp
    end
end

-- ====================================================================
-- 特效辅助
-- ====================================================================

--- 获取玩家当前武器标签（赤手空拳时返回 "拳"，双持匕首返回 "双匕首"）
--- 弓必须同时装备箭袋才算装备弓，否则视为赤手空拳
--- 计算攻击者最近的目标格子（多格单位返回最近的一格，单格直接返回位置）
local function getDefenderEffectPos(attacker, defender)
    if defender._clickedTileX then
        return defender._clickedTileX, defender._clickedTileY
    end
    local s = GS.unitSize(defender)
    if s <= 1 then
        return defender.x, defender.y
    end
    -- 多格单位：钳制攻击者坐标到目标占据区域，得到最近格子
    local ax, ay = attacker.x, attacker.y
    local cx = math.max(defender.x, math.min(ax, defender.x + s - 1))
    local cy = math.max(defender.y, math.min(ay, defender.y + s - 1))
    return cx, cy
end

getPlayerWeaponTag = function()
    local wr = GS.equipment and GS.equipment["weapon_r"]
    local wl = GS.equipment and GS.equipment["weapon_l"]
    if not wr and not wl then return "拳" end  -- 赤手空拳
    -- 双持匕首
    if wr and wr.weaponTag == "匕首" and wl and wl.weaponTag == "匕首" then
        return "双匕首"
    end
    -- 剑匕双持（右手单手剑 + 左手匕首）
    if wr and wr.weaponTag == "单手剑" and wl and wl.weaponTag == "匕首" then
        return "剑匕双持"
    end
    -- 弓必须同时装备箭袋
    if wr and wr.weaponTag == "弓" then
        if wl and wl.category == "箭袋" then
            return "弓"
        end
        return "拳"  -- 有弓无箭袋，视为赤手空拳
    end
    if wr and wr.weaponTag then return wr.weaponTag end
    -- 右手无有效武器，检查左手是否有武器标签（如单持匕首）
    if wl and wl.weaponTag then return wl.weaponTag end
    return "拳"  -- 无有效武器，视为赤手空拳
end

--- 哈雷努拉：祝福术/超度 AOE 化 — 实际实现（前向声明在上方）
isHolyAoeSkill = function(def)
    return def and (def == GS.SKILL_DEFS["p_bless"] or def == GS.SKILL_DEFS["p_exorcism"])
        and GS.player and (GS.player.holyAoePct or 0) > 0
end

handleHolyAoe = function(attacker, target, skillId, def)
    GS.useSkill(skillId)
    showPendingCastEffects(attacker.x, attacker.y, attacker)
    M.addSkillCastText(attacker.x, attacker.y, skillId)
    local isExorcism = (skillId == "p_exorcism")

    -- 攻击方向：从玩家到目标
    local fdx = target.x - attacker.x
    local fdy = target.y - attacker.y
    if fdx ~= 0 then fdx = fdx > 0 and 1 or -1 end
    if fdy ~= 0 then fdy = fdy > 0 and 1 or -1 end
    -- 垂直方向（用于展开3列宽度）
    local ldx, ldy = -fdy, fdx   -- 左侧
    local rdx, rdy = fdy, -fdx   -- 右侧

    -- 技能扩展词缀：每层宽度+2（左右各+1）、纵深+1
    local rb = getAoeRangeBonus()
    local maxPerp  = 1 + rb   -- 基础1（中+左+右=3列），每层+1
    local maxDepth = 2 + rb   -- 基础2排，每层+1

    -- 构建 AOE 区域格子
    local aoeCells = {}
    for depth = 1, maxDepth do
        -- 中心列
        aoeCells[#aoeCells + 1] = { attacker.x + fdx * depth, attacker.y + fdy * depth }
        -- 左右扩展列
        for p = 1, maxPerp do
            aoeCells[#aoeCells + 1] = { attacker.x + fdx * depth + ldx * p, attacker.y + fdy * depth + ldy * p }
            aoeCells[#aoeCells + 1] = { attacker.x + fdx * depth + rdx * p, attacker.y + fdy * depth + rdy * p }
        end
    end

    -- AOE 伤害倍率
    local holyAoePct = attacker.holyAoePct or 100
    local mul = GS.getSkillDmgMul(skillId) * holyAoePct / 100

    -- 对区域内所有怪物造成伤害
    local hitCount = 0
    local hitTargets = {}
    for _, pos in ipairs(aoeCells) do
        local t = GS.getUnitAt(pos[1], pos[2])
        if t and t.isMonster and t.hp > 0 and not hitTargets[t] then
            hitTargets[t] = true
            if rollDodge(attacker, t, skillId) then
                M.addDamageText(t.x, t.y, "Miss", {255, 255, 255})
            else
                local dmg, isCrit = calcSkillDamage(attacker, t,
                    { mul = mul, skillId = skillId, holySkill = true, element = "holy" })
                applyDamageAndCheck(attacker, t, dmg, "", {255, 220, 100}, isCrit)
                hitCount = hitCount + 1
                -- 受洗：AOE 命中也触发击晕判定
                if t.hp > 0 and not isHeroUnit(t) then
                    local baptismLv = GS.skillLevels["p_baptism"] or 0
                    if baptismLv > 0 then
                        local bChance = 2 * baptismLv
                        if math.random(1, 100) <= bChance then
                            local oldDur = t.stunned or 0
                            if 1 > oldDur then
                                t.stunned = 1
                                M.addDamageText(t.x, t.y - 0.5, "晕眩!", {255, 220, 60})
                            end
                        end
                    end
                end
            end
            M.addBlessEffect(attacker.x, attacker.y, t.x, t.y, isExorcism, rb)
        end
    end

    -- AOE 区域特效（金色神圣光域，范围随技能扩展放大）
    M.addHolyAoeEffect(attacker.x, attacker.y, fdx, fdy, maxPerp, maxDepth, isExorcism)

    local wTag = getPlayerWeaponTag()
    playAttackSound(wTag)

    if hitCount == 0 then
        M.addDamageText(attacker.x, attacker.y - 0.5, "Miss", {255, 255, 255})
    end

    if isExorcism then
        GS.setScreenShake(0.3, 4, 0.1)
    else
        GS.setScreenShake(0.2, 3, 0.05)
    end

    M._pendingChaseArrow = { attacker = attacker, target = target }
    return true
end

--- 银色狮子：强击/超强击/碎星 AOE 化
isStrikeAoeSkill = function(def)
    return def and (def == GS.SKILL_DEFS["strike"] or def == GS.SKILL_DEFS["sup_stk"] or def == GS.SKILL_DEFS["mst_stk"])
        and GS.player and (GS.player.strikeAoePct or 0) > 0
end

handleStrikeAoe = function(attacker, target, skillId, def)
    GS.useSkill(skillId)
    showPendingCastEffects(attacker.x, attacker.y, attacker)
    M.addSkillCastText(attacker.x, attacker.y, skillId)
    local isMasterStrike = (skillId == "mst_stk")

    -- 攻击方向：从玩家到目标
    local fdx = target.x - attacker.x
    local fdy = target.y - attacker.y
    if fdx ~= 0 then fdx = fdx > 0 and 1 or -1 end
    if fdy ~= 0 then fdy = fdy > 0 and 1 or -1 end
    -- 垂直方向（用于展开3列宽度）
    local ldx, ldy = -fdy, fdx   -- 左侧
    local rdx, rdy = fdy, -fdx   -- 右侧

    -- 强击系 AOE 扩展规则：横向仅2层词缀时+1，纵深每层+1
    local rb = getAoeRangeBonus()
    local strikeWidthBonus = (rb >= 2) and 1 or 0
    local maxPerp  = 1 + strikeWidthBonus   -- 基础1（中+左+右=3列），2层词缀时+1变5列
    local maxDepth = 4 + rb                  -- 基础4排纵深，每层+1

    -- 构建 AOE 区域格子（3×4 基础区域）
    local aoeCells = {}
    for depth = 1, maxDepth do
        -- 中心列
        aoeCells[#aoeCells + 1] = { attacker.x + fdx * depth, attacker.y + fdy * depth }
        -- 左右扩展列
        for p = 1, maxPerp do
            aoeCells[#aoeCells + 1] = { attacker.x + fdx * depth + ldx * p, attacker.y + fdy * depth + ldy * p }
            aoeCells[#aoeCells + 1] = { attacker.x + fdx * depth + rdx * p, attacker.y + fdy * depth + rdy * p }
        end
    end

    -- AOE 伤害倍率
    local strikeAoePct = attacker.strikeAoePct or 100
    local mul = GS.getSkillDmgMul(skillId) * strikeAoePct / 100

    -- 对区域内所有怪物造成伤害
    local hitCount = 0
    local hitTargets = {}
    for _, pos in ipairs(aoeCells) do
        local t = GS.getUnitAt(pos[1], pos[2])
        if t and t.isMonster and t.hp > 0 and not hitTargets[t] then
            hitTargets[t] = true
            if rollDodge(attacker, t, skillId) then
                M.addDamageText(t.x, t.y, "Miss", {255, 255, 255})
            else
                local dmg, isCrit = calcSkillDamage(attacker, t,
                    { mul = mul, skillId = skillId })
                applyDamageAndCheck(attacker, t, dmg, "", {200, 210, 230}, isCrit)
                hitCount = hitCount + 1
            end
            M.addStrikeEffect(attacker.x, attacker.y, t.x, t.y, skillId)
        end
    end

    -- 剑挥舞攻击特效（朝原始目标方向）
    local wTag = getPlayerWeaponTag()
    M.addAttackEffect(attacker.x, attacker.y, target.x, target.y, wTag, false, nil, nil, skillId)

    -- 银色冲击波特效
    M.addStrikeAoeEffect(attacker.x, attacker.y, fdx, fdy, maxPerp, maxDepth, isMasterStrike)

    playAttackSound(wTag)

    if hitCount == 0 then
        M.addDamageText(attacker.x, attacker.y - 0.5, "Miss", {255, 255, 255})
    end

    if isMasterStrike then
        GS.setScreenShake(0.35, 5, 0.12)
    else
        GS.setScreenShake(0.2, 3, 0.06)
    end

    M._pendingChaseArrow = { attacker = attacker, target = target }
    return true
end

--- 判断技能是否为范围化地面可施放（银色狮子强击系 / 哈雷努拉祝福超度）
function M.isAoeGroundSkill(skillId)
    local def = GS.SKILL_DEFS[skillId]
    if not def then return false end
    if isStrikeAoeSkill and isStrikeAoeSkill(def) then return true end
    if isHolyAoeSkill and isHolyAoeSkill(def) then return true end
    return false
end

--- 计算 AOE 预览格子列表（用于悬停预览和渲染）
--- 返回 { {x,y}, {x,y}, ... }
function M.getAoePreviewCells(skillId, ax, ay, tx, ty)
    local def = GS.SKILL_DEFS[skillId]
    if not def then return {} end

    local fdx = tx - ax
    local fdy = ty - ay
    if fdx ~= 0 then fdx = fdx > 0 and 1 or -1 end
    if fdy ~= 0 then fdy = fdy > 0 and 1 or -1 end
    if fdx == 0 and fdy == 0 then return {} end

    local ldx, ldy = -fdy, fdx
    local rdx, rdy = fdy, -fdx
    local rb = getAoeRangeBonus()
    local cells = {}

    if isStrikeAoeSkill and isStrikeAoeSkill(def) then
        local strikeWidthBonus = (rb >= 2) and 1 or 0
        local maxPerp  = 1 + strikeWidthBonus
        local maxDepth = 4 + rb
        for depth = 1, maxDepth do
            cells[#cells+1] = { ax + fdx * depth, ay + fdy * depth }
            for p = 1, maxPerp do
                cells[#cells+1] = { ax + fdx * depth + ldx * p, ay + fdy * depth + ldy * p }
                cells[#cells+1] = { ax + fdx * depth + rdx * p, ay + fdy * depth + rdy * p }
            end
        end
    elseif isHolyAoeSkill and isHolyAoeSkill(def) then
        local maxPerp  = 1 + rb
        local maxDepth = 2 + rb
        for depth = 1, maxDepth do
            cells[#cells+1] = { ax + fdx * depth, ay + fdy * depth }
            for p = 1, maxPerp do
                cells[#cells+1] = { ax + fdx * depth + ldx * p, ay + fdy * depth + ldy * p }
                cells[#cells+1] = { ax + fdx * depth + rdx * p, ay + fdy * depth + rdy * p }
            end
        end
    end

    return cells
end

--- 添加银色冲击波 AOE 区域特效
function M.addStrikeAoeEffect(ax, ay, fdx, fdy, maxPerp, maxDepth, enhanced)
    table.insert(GS.strikeAoeEffects, {
        x = ax, y = ay, fdx = fdx, fdy = fdy,
        maxPerp = maxPerp, maxDepth = maxDepth,
        enhanced = enhanced or false,
        timer = 0, duration = 0.7,
    })
end

function M.addAttackEffect(fromX, fromY, targetX, targetY, weaponTag, isCompanion, skillStyle, throwSkillId, skillId, monsterProjectile)
    -- 弹道类攻击：标记命中时间比例，用于同步伤害文字显示
    -- 小宙斯锤普攻也作为弹道攻击
    local isLittleZeusProj = (weaponTag == "锤") and not skillStyle and isPlayerLittleZeus()
    local isProjectile = (weaponTag == "弓") or (weaponTag == "法杖") or (skillStyle == "throw") or isLittleZeusProj
    -- 投掷/弓箭弹道固定 0.7 秒，不受双匕首等武器特殊时长影响
    -- 预告信稍长（0.9秒）以容纳爆炸效果
    -- 电击术使用更短的持续时间（闪电瞬发）
    local dur
    if skillId == "m_lightning" then
        dur = 0.6
    elseif skillStyle == "throw" and throwSkillId == "a_notice" then
        dur = 0.9
    elseif isProjectile then
        dur = 0.7
    elseif (weaponTag == "双匕首" or weaponTag == "剑匕双持") then
        dur = 1.5
    elseif skillStyle then
        dur = 0.7
    else
        dur = 0.5
    end
    local hitRatioVal = (skillId == "m_lightning") and 0.15 or (isProjectile and 0.55 or nil)
    -- 弹道特效关联唯一ID，用于精确关联伤害文字
    -- 优先复用 performAttack 预分配的 ID，否则新分配
    local projId = nil
    if hitRatioVal then
        if M._currentProjectileId then
            projId = M._currentProjectileId
        else
            M._projectileIdCounter = M._projectileIdCounter + 1
            projId = M._projectileIdCounter
            M._currentProjectileId = projId
        end
    end
    table.insert(GS.attackEffects, {
        x = targetX, y = targetY,
        fx = fromX, fy = fromY,
        timer = 0, duration = dur,
        weaponTag = weaponTag,
        isCompanion = isCompanion,
        skillStyle = skillStyle,
        throwSkillId = throwSkillId,
        skillId = skillId,
        monsterProjectile = monsterProjectile,
        hitRatio = hitRatioVal,
        hitFired = false,
        projectileId = projId,
        isLittleZeus = isLittleZeusProj or nil,
    })
end

function M.addPhantomAttackEffect(phantomX, phantomY, targetX, targetY, weaponTag)
    table.insert(GS.phantomAttackEffects, {
        px = phantomX, py = phantomY,
        tx = targetX, ty = targetY,
        weaponTag = weaponTag,
        timer = 0, duration = 0.8,
    })
end

-- ====================================================================
-- 远程反击剑气飞行特效（天蝎座盾牌）
-- ====================================================================
function M.addSwordQiEffect(fromX, fromY, targetX, targetY, delay)
    M._projectileIdCounter = M._projectileIdCounter + 1
    local projId = M._projectileIdCounter
    M._currentProjectileId = projId
    table.insert(GS.swordQiEffects, {
        x = targetX, y = targetY,
        fx = fromX, fy = fromY,
        timer = 0, duration = 0.5,
        delay = delay or 0,
        hitRatio = 0.55,
        hitFired = false,
        projectileId = projId,
    })
    return projId
end

function M.addStrikeEffect(fromX, fromY, targetX, targetY, skillId)
    table.insert(GS.strikeEffects, {
        x = targetX, y = targetY,
        fx = fromX, fy = fromY,
        timer = 0, duration = 0.8,
        skillId = skillId,
    })
    -- 击中时触发屏幕震动（延迟到冲击阶段）
    GS.setScreenShake(0.35, 4, 0.30)
end

-- ====================================================================
-- 祝福术专属特效（神圣锤击）
-- ====================================================================
function M.addBlessEffect(fromX, fromY, targetX, targetY, enhanced, rangeBonus)
    table.insert(GS.blessEffects, {
        x = targetX, y = targetY,
        fx = fromX, fy = fromY,
        timer = 0, duration = enhanced and 1.0 or 0.8,
        enhanced = enhanced or false,
        rangeBonus = rangeBonus or 0,
    })
    if enhanced then
        GS.setScreenShake(0.15, 3, 0)
    else
        GS.setScreenShake(0.15, 2, 0)
    end
end

function M.addPowerShotEffect(fromX, fromY, targetX, targetY)
    table.insert(GS.powerShotEffects, {
        x = targetX, y = targetY,
        fx = fromX, fy = fromY,
        timer = 0, duration = 0.75,
    })
    GS.setScreenShake(0.3, 3, 0.28)
end

function M.addSnipeEffect(fromX, fromY, targetX, targetY)
    table.insert(GS.snipeEffects, {
        x = targetX, y = targetY,
        fx = fromX, fy = fromY,
        timer = 0, duration = 0.9,
    })
    GS.setScreenShake(0.35, 5, 0.25)
end

function M.addStunShotEffect(fromX, fromY, targetX, targetY)
    table.insert(GS.stunShotEffects, {
        x = targetX, y = targetY,
        fx = fromX, fy = fromY,
        timer = 0, duration = 0.70,
    })
    GS.setScreenShake(0.25, 2.5, 0.25)
end

-- ====================================================================
-- 嘲讽技能特效（施法者→目标的激怒冲击波）
-- ====================================================================
-- ====================================================================
-- 顺劈溅射特效（半圆扩散弧）
-- ====================================================================
function M.addCleaveEffect(ax, ay, fdx, fdy)
    table.insert(GS.cleaveEffects, {
        x = ax, y = ay,
        fdx = fdx, fdy = fdy,  -- 攻击方向（归一化）
        timer = 0, duration = 0.45,
    })
end

-- 深渊溅射特效（扩散弧，范围随 rangeBonus 扩大）
function M.addMeleeSplashEffect(ax, ay, fdx, fdy, rangeBonus)
    table.insert(GS.meleeSplashEffects, {
        x = ax, y = ay,
        fdx = fdx, fdy = fdy,
        rangeBonus = rangeBonus or 0,
        timer = 0, duration = 0.5,
    })
end

-- 哈雷努拉：祝福/超度 AOE 区域特效（金色神圣光域，范围随技能扩展放大）
function M.addHolyAoeEffect(ax, ay, fdx, fdy, maxPerp, maxDepth, enhanced)
    table.insert(GS.holyAoeEffects, {
        x = ax, y = ay,
        fdx = fdx, fdy = fdy,
        maxPerp = maxPerp,
        maxDepth = maxDepth,
        enhanced = enhanced or false,
        timer = 0, duration = 0.6,
    })
end

--- 爆炸信：远程技能爆炸特效（红色爆炸圈，以目标为中心）
--- 支持 pendingHit：弹道命中后才播放爆炸特效
--- @param range number|nil 爆炸半径（格数），默认1
function M.addRangedExplosionEffect(tx, ty, range)
    table.insert(GS.rangedExplosionEffects, {
        x = tx, y = ty,
        timer = 0, duration = 0.55,
        range = range or 1,
        pendingHit = M._pendingProjectileHit or false,
        projectileId = M._pendingProjectileHit and M._currentProjectileId or nil,
    })
end

function M.addTauntEffect(targetUnit)
    table.insert(GS.tauntEffects, {
        target = targetUnit,
        timer = 0, duration = 0.9,
    })
end

function M.addSandBlindEffect(fromX, fromY, targetX, targetY)
    table.insert(GS.sandBlindEffects, {
        x = targetX, y = targetY,
        fx = fromX, fy = fromY,
        timer = 0, duration = 0.7,
    })
end

function M.addHurtFlash(unit)
    -- 如果有 damageTextDelay，hurtFlash 也同步延迟（避免火球/陨石未到就闪红）
    local delay = M._damageTextDelay or 0
    if delay > 0 then
        unit.hurtTimer = -delay  -- 负值表示延迟中，倒计时到 0 后才开始闪红
    else
        unit.hurtTimer = 0
    end
    unit.hurtDuration = 0.35
end

function M.addSlamAnim(unit, targetX, targetY)
    local ucx, ucy = GS.unitCenterPos(unit)
    local dx = targetX - ucx
    local dy = targetY - ucy
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 0.01 then return end
    unit.slamAnim = {
        dirX = dx / dist,
        dirY = dy / dist,
        timer = 0,
        duration = 0.32,
        slamDist = GS.CELL * 0.6,
    }
end

function M.startMoveAnim(unit, fromX, fromY, path)
    if fromX == unit.x and fromY == unit.y then return end
    -- 更新朝向：取路径最后一段的方向
    if path and #path >= 2 then
        local lastSeg = path[#path]
        local prevSeg = path[#path - 1]
        GS.updateFacing(unit, prevSeg[1], prevSeg[2], lastSeg[1], lastSeg[2])
    else
        GS.updateFacing(unit, fromX, fromY, unit.x, unit.y)
    end
    if path and #path >= 2 then
        -- 多段路径动画：每段 0.12s，最少 0.2s
        local segs = #path - 1
        unit.moveAnim = {
            fromX = fromX, fromY = fromY,
            path = path,
            timer = 0, duration = math.max(0.2, segs * 0.12),
        }
    else
        unit.moveAnim = {
            fromX = fromX, fromY = fromY,
            timer = 0, duration = 0.25,
        }
    end
end

-- ====================================================================
-- 执行攻击
-- ====================================================================

-- ====================================================================
-- performAttack 辅助函数（从主函数提取的独立逻辑块）
-- ====================================================================

--- 顺劈溅射：对玩家左右两侧及左右斜前方共4格的敌人造成溅射伤害
local function applyCleaveEffect(attacker, defender, dmg)
    if not attacker.isMonster and not attacker._cleaving and not attacker._phantomAttacking then
        local cleaveLv = GS.skillLevels["cleave"] or 0
        if cleaveLv > 0 and defender.isMonster then
            local cleaveDef = GS.SKILL_DEFS["cleave"]
            local basePct = cleaveDef and cleaveDef.cleavePct or 33
            local perLv = cleaveDef and cleaveDef.cleavePctPerLv or 0
            local pct = (basePct + (cleaveLv - 1) * perLv) / 100
            local splashDmg = math.max(1, math.floor(dmg * pct))
            -- 攻击方向（归一化为-1/0/1）
            local fdx = defender.x - attacker.x
            local fdy = defender.y - attacker.y
            if fdx ~= 0 then fdx = fdx > 0 and 1 or -1 end
            if fdy ~= 0 then fdy = fdy > 0 and 1 or -1 end
            -- 计算左右方向向量（perpendicular）
            -- 前方(fdx,fdy) → 左侧(-fdy,fdx), 右侧(fdy,-fdx)
            local ldx, ldy = -fdy, fdx   -- 左侧
            local rdx, rdy = fdy, -fdx   -- 右侧
            local ax, ay = attacker.x, attacker.y
            M.addCleaveEffect(ax, ay, fdx, fdy)
            -- 溅射4格：左侧、右侧、左斜前方、右斜前方
            local splashCells = {
                { ax + ldx, ay + ldy },             -- 左侧
                { ax + rdx, ay + rdy },             -- 右侧
                { ax + ldx + fdx, ay + ldy + fdy }, -- 左斜前方
                { ax + rdx + fdx, ay + rdy + fdy }, -- 右斜前方
            }
            attacker._cleaving = true
            for _, pos in ipairs(splashCells) do
                local splashTarget = GS.getUnitAt(pos[1], pos[2])
                if splashTarget and splashTarget.isMonster and splashTarget.hp > 0
                   and splashTarget ~= defender then
                    splashTarget.hp = splashTarget.hp - splashDmg
                    trackTrainingDamage(splashTarget, splashDmg)
                    immortalGuard(splashTarget, splashDmg)
                    M.addDamageText(splashTarget.x, splashTarget.y, "" .. splashDmg, {255, 255, 255})
                    M.addHurtFlash(splashTarget)
                    M.applyLifesteal(attacker, splashDmg)
                    if splashTarget.hp <= 0 then
                        splashTarget.hp = 0
                        M.processMonsterKill(attacker, splashTarget)
                    end
                end
            end
            attacker._cleaving = nil
        end
    end
end

--- 深渊词缀：近战攻击溅射（与顺劈相同4格范围，30%伤害/件，与顺劈叠加）
local function applyMeleeSplash(attacker, defender, dmg)
    if attacker.isMonster or attacker.isCompanion or attacker._meleeSplashing or attacker._phantomAttacking then return end
    if not defender.isMonster or dmg <= 0 then return end
    -- 聚焦器：禁用溅射
    if (attacker.focuserDmgPer or 0) > 0 then return end
    -- 仅近战武器触发
    local wTag = getPlayerWeaponTag()
    if wTag == "弓" or wTag == "法杖" then return end
    -- 统计装备中溅射词缀数量（可叠加，每件+30%）及范围扩展数量（上限3）
    local splashCount = countAbyssAffix("melee_splash")
    local rangeBonus = countAbyssAffix("melee_splash_range")
    if splashCount <= 0 then return end
    local pct = splashCount * 0.30
    local splashDmg = math.max(1, math.floor(dmg * pct))
    -- 溅射中心：幻影攻击时以幻影位置为中心，否则以攻击者位置为中心
    local ax, ay = attacker.x, attacker.y
    if attacker._phantomPos then
        ax, ay = attacker._phantomPos[1], attacker._phantomPos[2]
    end
    -- 攻击方向（归一化为-1/0/1）——与顺劈相同
    local fdx = defender.x - ax
    local fdy = defender.y - ay
    if fdx ~= 0 then fdx = fdx > 0 and 1 or -1 end
    if fdy ~= 0 then fdy = fdy > 0 and 1 or -1 end
    local ldx, ldy = -fdy, fdx   -- 左侧
    local rdx, rdy = fdy, -fdx   -- 右侧
    -- 溅射特效
    M.addMeleeSplashEffect(ax, ay, fdx, fdy, rangeBonus)
    -- 基础4格（与顺劈相同）+ defender背后，每个范围词缀向两侧各扩展1格且纵深+1行
    local maxPerp = 1 + rangeBonus
    local maxDepth = 2 + rangeBonus   -- 基础纵深2（defender行+背后1行），每层+1
    local splashCells = {}
    -- 背后各行中心格（depth 2 ~ maxDepth）
    for d = 2, maxDepth do
        splashCells[#splashCells + 1] = { ax + d * fdx, ay + d * fdy }
    end
    for p = 1, maxPerp do
        splashCells[#splashCells + 1] = { ax + ldx * p, ay + ldy * p }                 -- 攻击者行：左 p
        splashCells[#splashCells + 1] = { ax + rdx * p, ay + rdy * p }                 -- 攻击者行：右 p
        splashCells[#splashCells + 1] = { ax + ldx * p + fdx, ay + ldy * p + fdy }     -- defender行：左 p
        splashCells[#splashCells + 1] = { ax + rdx * p + fdx, ay + rdy * p + fdy }     -- defender行：右 p
        -- 背后各行：左右各 p（depth 2 ~ maxDepth）
        for d = 2, maxDepth do
            splashCells[#splashCells + 1] = { ax + ldx * p + d * fdx, ay + ldy * p + d * fdy }
            splashCells[#splashCells + 1] = { ax + rdx * p + d * fdx, ay + rdy * p + d * fdy }
        end
    end
    attacker._meleeSplashing = true
    local splashHit = {}  -- 去重：防止2x2大型单位被多个溅射格子重复命中
    for _, pos in ipairs(splashCells) do
        local splashTarget = GS.getUnitAt(pos[1], pos[2])
        if splashTarget and splashTarget.isMonster and splashTarget.hp > 0
           and splashTarget ~= defender and not splashHit[splashTarget] then
            splashHit[splashTarget] = true
            splashTarget.hp = splashTarget.hp - splashDmg
            trackTrainingDamage(splashTarget, splashDmg)
            immortalGuard(splashTarget, splashDmg)
            M.addDamageText(splashTarget.x, splashTarget.y, "" .. splashDmg, {255, 180, 80})
            M.addHurtFlash(splashTarget)
            M.applyLifesteal(attacker, splashDmg)
            M.applyBondLink(attacker, splashDmg)
            if splashTarget.hp <= 0 then
                splashTarget.hp = 0
                M.processMonsterKill(attacker, splashTarget)
            end
        end
    end
    attacker._meleeSplashing = nil
end

--- 驯兽圈：猎犬攻击溅射（装备 houndSplashPct 时猎犬攻击产生溅射）
--- 溅射伤害加成（melee_splash 词缀）和溅射范围扩展（melee_splash_range 词缀）也作用于猎犬
local function applyHoundSplash(attacker, defender, dmg)
    if not attacker.isCompanion or attacker._houndSplashing then return end
    if not defender.isMonster or dmg <= 0 then return end
    -- 检查玩家装备的猎犬溅射百分比
    local eb = GS.getEquipBonus and GS.getEquipBonus() or {}
    local houndPct = eb.houndSplashPct or 0
    if houndPct <= 0 then return end
    -- 基础溅射百分比（驯兽圈装备效果，不受聚焦器影响）
    local pct = houndPct / 100
    -- 溅射伤害加成作用于猎犬：玩家的 melee_splash 词缀每件+30%（聚焦器屏蔽深渊词缀部分）
    if (GS.player.focuserDmgPer or 0) <= 0 then
        local splashBonus = countAbyssAffix("melee_splash")
        if splashBonus > 0 then
            pct = pct + splashBonus * 0.30
        end
    end
    local splashDmg = math.max(1, math.floor(dmg * pct))
    -- 魅力加成：同伴溅射伤害 +1%/点
    local ownerCha = GS.player and GS.player.cha or 0
    if ownerCha > 0 then
        splashDmg = math.max(1, math.floor(splashDmg * (1 + ownerCha / 100)))
    end
    -- 溅射范围扩展作用于猎犬（聚焦器屏蔽深渊词缀部分）
    local rangeBonus = 0
    if (GS.player.focuserDmgPer or 0) <= 0 then
        rangeBonus = countAbyssAffix("melee_splash_range")
    end
    -- 溅射中心：猎犬位置
    local ax, ay = attacker.x, attacker.y
    -- 攻击方向（归一化为-1/0/1）
    local fdx = defender.x - ax
    local fdy = defender.y - ay
    if fdx ~= 0 then fdx = fdx > 0 and 1 or -1 end
    if fdy ~= 0 then fdy = fdy > 0 and 1 or -1 end
    local ldx, ldy = -fdy, fdx   -- 左侧
    local rdx, rdy = fdy, -fdx   -- 右侧
    -- 溅射特效
    M.addMeleeSplashEffect(ax, ay, fdx, fdy, rangeBonus)
    -- 基础4格 + defender背后，每个范围词缀向两侧各扩展1格且纵深+1行（与 applyMeleeSplash 相同）
    local maxPerp = 1 + rangeBonus
    local maxDepth = 2 + rangeBonus   -- 基础纵深2（defender行+背后1行），每层+1
    local splashCells = {}
    -- 背后各行中心格（depth 2 ~ maxDepth）
    for d = 2, maxDepth do
        splashCells[#splashCells + 1] = { ax + d * fdx, ay + d * fdy }
    end
    for p = 1, maxPerp do
        splashCells[#splashCells + 1] = { ax + ldx * p, ay + ldy * p }                 -- 攻击者行：左 p
        splashCells[#splashCells + 1] = { ax + rdx * p, ay + rdy * p }                 -- 攻击者行：右 p
        splashCells[#splashCells + 1] = { ax + ldx * p + fdx, ay + ldy * p + fdy }     -- defender行：左 p
        splashCells[#splashCells + 1] = { ax + rdx * p + fdx, ay + rdy * p + fdy }     -- defender行：右 p
        -- 背后各行：左右各 p（depth 2 ~ maxDepth）
        for d = 2, maxDepth do
            splashCells[#splashCells + 1] = { ax + ldx * p + d * fdx, ay + ldy * p + d * fdy }
            splashCells[#splashCells + 1] = { ax + rdx * p + d * fdx, ay + rdy * p + d * fdy }
        end
    end
    attacker._houndSplashing = true
    local splashHit = {}
    for _, pos in ipairs(splashCells) do
        local splashTarget = GS.getUnitAt(pos[1], pos[2])
        if splashTarget and splashTarget.isMonster and splashTarget.hp > 0
           and splashTarget ~= defender and not splashHit[splashTarget] then
            splashHit[splashTarget] = true
            splashTarget.hp = splashTarget.hp - splashDmg
            trackTrainingDamage(splashTarget, splashDmg)
            immortalGuard(splashTarget, splashDmg)
            M.addDamageText(splashTarget.x, splashTarget.y, "" .. splashDmg, {180, 140, 220})
            M.addHurtFlash(splashTarget)
            M.applyLifesteal(attacker, splashDmg)
            M.applyBondLink(attacker, splashDmg)
            if splashTarget.hp <= 0 then
                splashTarget.hp = 0
                M.processMonsterKill(attacker, splashTarget)
            end
        end
    end
    attacker._houndSplashing = nil
end

--- 默示录：普通攻击时对自身周围N格内怪物造成魔法伤害（基于魔攻百分比）
local function applyApocalypseAoe(attacker)
    if attacker.isMonster or attacker.isCompanion then return end
    local coeff = attacker.normalAtkMatkCoeff or 0
    if coeff <= 0 then return end
    local range = attacker.normalAtkMatkRange or 0
    if range <= 0 then return end
    local mAtk = attacker.mAtk or 0
    if mAtk <= 0 then return end

    local p = GS.player
    local px, py = p.x, p.y

    -- 双持攻击力惩罚 + 双持熟练/专精补正（与 performAttack 一致）
    if GS.isDualMelee() then
        local dualPct = 40
        if GS.isDualDagger() then
            for _, sid in ipairs({"a_dual_prof", "a_dual_master"}) do
                local lv = GS.skillLevels[sid] or 0
                if lv > 0 then
                    local sd = GS.SKILL_DEFS[sid]
                    if sd and sd.dualDmgPctPerLv then
                        dualPct = dualPct + sd.dualDmgPctPerLv * lv
                    end
                end
            end
        end
        dualPct = math.min(dualPct, 100)
        mAtk = math.floor(mAtk * dualPct / 100)
    end

    local baseDmg = math.floor(mAtk * coeff / 100)

    -- 双持匕首伤害衰减（默示录自身词缀）
    local ddPct = p.dualDaggerDmgPct or 0
    if ddPct > 0 and GS.isDualDagger() then
        baseDmg = math.floor(baseDmg * ddPct / 100)
    end

    -- 技能作用范围加成（深渊词缀 skill_aoe_range + 装备 equipAoeBonus）
    range = range + getAoeRangeBonus()

    -- 插入紫色爆炸光环特效
    table.insert(GS.apocalypseAoeEffects, {
        x = px, y = py, range = range,
        timer = 0, duration = 0.65,
    })

    -- 暴雨被动预计算（循环外只算一次）
    local srLv = GS.skillLevels["a_storm_rain"] or 0
    local srIncPct = 0
    if srLv > 0 then
        local srDef = GS.SKILL_DEFS["a_storm_rain"]
        srIncPct = (srDef.stormPctPerLv or 0.5) * srLv
    end

    for _, m in ipairs(GS.monsters) do
        if m.hp and m.hp > 0 then
            local dist = math.abs(m.x - px) + math.abs(m.y - py)
            if dist <= range then
                if rollDodge(p, m, nil) then
                    M.addDamageText(m.x, m.y, "Miss", {255, 255, 255})
                else
                    local mdef = m.mdef or m.def or 0
                    local dmg = math.floor(baseDmg * mAtk / math.max(1, mAtk + mdef))
                    dmg = math.max(1, dmg)
                    -- 统一加成管线（百分比、武器类型、魔法伤害、元素、标记、方向、暴击等）
                    local isCrit
                    dmg, isCrit = applyDmgBonuses(p, m, dmg, { useMagic = true })
                    -- 暴雨被动：同一回合对同一目标命中次数越多，伤害越高
                    if srIncPct > 0 then
                        local hits = M.stormHitCounts[m] or 0
                        if hits > 0 then
                            dmg = math.floor(dmg * (1 + hits * srIncPct / 100))
                            dmg = math.max(1, dmg)
                        end
                        M.stormHitCounts[m] = hits + 1
                    end
                    -- 统一伤害结算（扣血、暴击!、震动、吸血、击杀等）
                    applyDamageAndCheck(p, m, dmg, "", {200, 150, 255}, isCrit, true)
                end
            end
        end
    end
end

--- 深渊词缀：近战普通攻击幻影（在额外敌人背后生成幻影发动一次普通攻击，可叠加）
local function applyPhantomAttack(attacker, defender)
    if attacker.isMonster or attacker.isCompanion or attacker._phantomAttacking then return end
    if not defender.isMonster then return end
    -- 默示录：魔法爆炸普攻不触发幻影
    if (attacker.normalAtkMatkCoeff or 0) > 0 then return end
    -- 小宙斯：远程雷电普攻不触发幻影
    local eb0 = GS.getEquipBonus and GS.getEquipBonus() or {}
    if (eb0.littleZeusRange or 0) > 0 then return end
    -- 仅近战武器触发
    local wTag = getPlayerWeaponTag()
    if wTag == "弓" or wTag == "法杖" then return end
    -- 聚焦器：仅屏蔽深渊词缀幻影，保留装备/技能来源
    local phantomCount = 0
    if (attacker.focuserDmgPer or 0) <= 0 then
        phantomCount = phantomCount + countAbyssAffix("melee_phantom")
    end
    -- 装备 heroPhantom 独立叠加（不受聚焦器影响）
    local eb = GS.getEquipBonus and GS.getEquipBonus() or {}
    phantomCount = phantomCount + (eb.heroPhantom or 0)
    -- 月影满级被动：幻影+1（不受聚焦器影响）
    if (GS.skillLevels["a_moon_shadow"] or 0) >= GS.SKILL_MAX_LEVEL then
        phantomCount = phantomCount + 1
    end
    -- 幻影技能满级被动：幻影+1（不受聚焦器影响）
    if (GS.skillLevels["a_phantom"] or 0) >= GS.SKILL_MAX_LEVEL then
        phantomCount = phantomCount + 1
    end
    if phantomCount <= 0 then return end
    -- 在曼哈顿距离内寻找目标（基础4，幻影技能满级+2，装备 illusionSearchRange 扩展）
    local phantomSearchRange = 4 + (attacker.illusionSearchRange or 0)
    if (GS.skillLevels["a_phantom"] or 0) >= GS.SKILL_MAX_LEVEL then
        phantomSearchRange = phantomSearchRange + 2
    end
    local targets = pickPhantomTargets(attacker, phantomCount, phantomSearchRange)
    if #targets == 0 then return end
    -- 极影之形：当幻影数量 > 目标数量时，多余幻影可重复攻击已有目标
    local illusionSingleExtra = attacker.illusionSingleExtra or 0
    if illusionSingleExtra > 0 and #targets < phantomCount then
        local uniqueCount = #targets
        -- 每个目标最多额外承受 illusionSingleExtra 次幻影攻击
        local extraSlots = math.min(phantomCount - uniqueCount, uniqueCount * illusionSingleExtra)
        for i = 1, extraSlots do
            targets[#targets + 1] = targets[((i - 1) % uniqueCount) + 1]
        end
    end
    attacker._phantomAttacking = true
    -- 极影之形：追踪每个目标已被攻击次数，第2次起标记为额外幻影
    local targetHitCount = {}
    -- 已被幻影占据的格子集合（key = "x,y"）
    local occupiedByPhantom = {}

    -- 朝向 → 四方向偏移，优先级：背后 > 右侧 > 左侧 > 正面
    local dirOffsets = {
        up    = { { 0,  1}, { 1,  0}, {-1,  0}, { 0, -1} },  -- 背后(+y) > 右(+x) > 左(-x) > 正面(-y)
        down  = { { 0, -1}, {-1,  0}, { 1,  0}, { 0,  1} },  -- 背后(-y) > 右(-x) > 左(+x) > 正面(+y)
        left  = { { 1,  0}, { 0,  1}, { 0, -1}, {-1,  0} },  -- 背后(+x) > 右(+y) > 左(-y) > 正面(-x)
        right = { {-1,  0}, { 0, -1}, { 0,  1}, { 1,  0} },  -- 背后(-x) > 右(-y) > 左(+y) > 正面(+x)
    }

    --- 从偏移计算幻影候选坐标列表（目标边缘向外延伸1格）
    --- size>1 时，沿边缘展开多个候选格（如背后2格）
    local function offsetToPosList(target, off, tcx, tcy, ts)
        local list = {}
        if off[1] ~= 0 and off[2] == 0 then
            -- 水平方向（左/右）：x 固定，y 沿边缘展开 ts 格
            local px = off[1] > 0 and (target.x + ts) or (target.x - 1)
            for dy = 0, ts - 1 do
                list[#list + 1] = { px, target.y + dy }
            end
        elseif off[2] ~= 0 and off[1] == 0 then
            -- 垂直方向（上/下）：y 固定，x 沿边缘展开 ts 格
            local py = off[2] > 0 and (target.y + ts) or (target.y - 1)
            for dx = 0, ts - 1 do
                list[#list + 1] = { target.x + dx, py }
            end
        else
            -- 对角方向（不应出现，兜底）
            local px = off[1] > 0 and (target.x + ts) or (target.x - 1)
            local py = off[2] > 0 and (target.y + ts) or (target.y - 1)
            list[#list + 1] = { px, py }
        end
        return list
    end

    --- 检查格子是否被占用（玩家或已生成的幻影）
    local function isOccupied(px, py)
        if px == attacker.x and py == attacker.y then return true end
        if occupiedByPhantom[px .. "," .. py] then return true end
        return false
    end

    for _, target in ipairs(targets) do
        -- 计算幻影位置
        local tcx, tcy = GS.unitCenterPos(target)
        local ts = GS.unitSize(target)
        local phantomX, phantomY
        local facing = target.facing
        -- 极影之形：标记额外幻影攻击（同一目标第2次起）
        targetHitCount[target] = (targetHitCount[target] or 0) + 1
        local isExtra = targetHitCount[target] > 1
        if isExtra then
            attacker._illusionSingleBonus = true
        end
        -- 按优先级（背后>右侧>左侧>正面）选择不与玩家/其他幻影重叠的格子
        -- size>1 时每个方向展开多个候选格（如背后2格）
        if facing and dirOffsets[facing] then
            local offList = dirOffsets[facing]
            local placed = false
            for _, off in ipairs(offList) do
                local posList = offsetToPosList(target, off, tcx, tcy, ts)
                for _, pos in ipairs(posList) do
                    if not isOccupied(pos[1], pos[2]) then
                        phantomX, phantomY = pos[1], pos[2]
                        placed = true
                        break
                    end
                end
                if placed then break end
            end
            -- 所有格子都被占用时，使用背后第一格（允许重叠，保证幻影一定生成）
            if not placed then
                local fallback = offsetToPosList(target, offList[1], tcx, tcy, ts)
                phantomX, phantomY = fallback[1][1], fallback[1][2]
            end
        else
            -- 无朝向时回退：根据玩家→目标方向推导四方向候选（展开多格）
            local dirX = tcx - attacker.x
            local dirY = tcy - attacker.y
            local candidates = {}
            if math.abs(dirX) >= math.abs(dirY) then
                -- 水平方向为主轴：背后=沿主轴延伸，侧面=垂直方向
                local behindX = dirX > 0 and (target.x + ts) or (target.x - 1)
                local frontX  = dirX > 0 and (target.x - 1) or (target.x + ts)
                for dy = 0, ts - 1 do candidates[#candidates + 1] = { behindX, target.y + dy } end
                for dx = 0, ts - 1 do candidates[#candidates + 1] = { target.x + dx, target.y + ts } end
                for dx = 0, ts - 1 do candidates[#candidates + 1] = { target.x + dx, target.y - 1 } end
                for dy = 0, ts - 1 do candidates[#candidates + 1] = { frontX, target.y + dy } end
            else
                -- 垂直方向为主轴
                local behindY = dirY > 0 and (target.y + ts) or (target.y - 1)
                local frontY  = dirY > 0 and (target.y - 1) or (target.y + ts)
                for dx = 0, ts - 1 do candidates[#candidates + 1] = { target.x + dx, behindY } end
                for dy = 0, ts - 1 do candidates[#candidates + 1] = { target.x + ts, target.y + dy } end
                for dy = 0, ts - 1 do candidates[#candidates + 1] = { target.x - 1, target.y + dy } end
                for dx = 0, ts - 1 do candidates[#candidates + 1] = { target.x + dx, frontY } end
            end
            local placed = false
            for _, c in ipairs(candidates) do
                if not isOccupied(c[1], c[2]) then
                    phantomX, phantomY = c[1], c[2]
                    placed = true
                    break
                end
            end
            if not placed then
                phantomX, phantomY = candidates[1][1], candidates[1][2]
            end
        end
        -- 记录此幻影占据的格子
        occupiedByPhantom[phantomX .. "," .. phantomY] = true
        -- 添加幻影棋子出现/消散视觉特效（视觉目标指向中心）
        M.addPhantomAttackEffect(phantomX, phantomY, math.floor(tcx), math.floor(tcy), wTag)
        -- 设置幻影坐标，让 performAttack 的武器攻击特效从幻影位置出发
        attacker._phantomPos = {phantomX, phantomY}
        -- 幻影攻击不触发连击（攻速/双持/二连击），防止攻击次数膨胀
        -- 保存原始标记，避免覆盖连击队列设置的标记
        local savedAtkSpeed = attacker._atkSpeedChaining
        local savedDualDagger = attacker._dualDaggerChaining
        local savedDoubleStrike = attacker._doubleStrikeChaining
        attacker._atkSpeedChaining = true
        attacker._dualDaggerChaining = true
        attacker._doubleStrikeChaining = true
        -- 执行实际攻击（attacker仍为玩家，保留伤害/吸血/击杀逻辑）
        M.performAttack(attacker, target)
        attacker._phantomPos = nil
        attacker._illusionSingleBonus = nil
        attacker._atkSpeedChaining = savedAtkSpeed
        attacker._dualDaggerChaining = savedDualDagger
        attacker._doubleStrikeChaining = savedDoubleStrike
    end
    attacker._phantomAttacking = nil
end

-- ====================================================================
--- 深渊词缀：闪电链（攻击时50%概率触发，等级=叠加层数，伤害取物攻/魔攻孰高）
--- 完全复制法师闪电链的弹射机制，区别：
---   1. 伤害取 max(atk, mAtk)
---   2. 等级由词缀叠加层数决定（最高14）
---   3. 所有攻击类型均可触发（近战/远程/技能），但递归不触发
-- ====================================================================
local function applyAffixChainLightning(attacker, defender, dmg)
    local isCompOrPhantom = attacker.isCompanion or attacker._phantomAttacking
    if attacker.isMonster or attacker._affixChainLightning then return end
    -- 同伴/幻影：需要蕴雷（compChainLightningMax > 0），且受每回合次数限制
    if isCompOrPhantom then
        local eb = GS.getEquipBonus and GS.getEquipBonus() or {}
        local maxComp = eb.compChainLightningMax or 0
        if maxComp <= 0 then return end
        local used = GS._compChainLightningCount or 0
        if used >= maxComp then return end
    end
    if not defender.isMonster or dmg <= 0 then return end
    -- 聚焦器：屏蔽闪电链（玩家本体和同伴/幻影均受限）
    -- 蕴雷仍依赖玩家本体的 chain_lightning 词缀层数，词缀被封印则幻影也无从触发
    if (GS.player and (GS.player.focuserDmgPer or 0) > 0) then return end
    -- 统计装备中闪电链词缀叠加层数（上限3）
    local chainStack = countAbyssAffix("chain_lightning")
    -- 无闪电链词缀则不触发（蕴雷仅允许同伴/幻影触发，但仍需有词缀）
    if chainStack <= 0 then return end
    -- 叠加数→闪电链等级：1→1, 2→3, 3→6, 4→10（三角数 n*(n+1)/2）
    local chainLevel = chainStack * (chainStack + 1) / 2
    -- 触发概率：默认50%，小宙斯提升至 littleZeusChainProb%
    local chainProb = 50
    if isPlayerLittleZeus() then
        local eb = GS.getEquipBonus and GS.getEquipBonus() or {}
        chainProb = eb.littleZeusChainProb or chainProb
    end
    if math.random(1, 100) > chainProb then return end
    attacker._affixChainLightning = true
    -- 蕴雷：同伴/幻影触发时递增每回合计数
    if isCompOrPhantom then
        GS._compChainLightningCount = (GS._compChainLightningCount or 0) + 1
    end

    -- === 闪电链等级参数（复制法师 m_chain_light 数据并外推11-14级） ===
    -- 伤害倍率：2.0 + (lv-1)*0.2
    local mul = 2.0 + (chainLevel - 1) * 0.2
    -- 弹射次数：基础2，等级达到 3/6/10/14 时各+1，养雷壶额外加成
    local maxBounce = 2
    local breaks = {3, 6, 10, 14}
    for _, brk in ipairs(breaks) do
        if chainLevel >= brk then maxBounce = maxBounce + 1 end
    end
    maxBounce = maxBounce + (attacker.thunderJarBounce or 0)
    -- 弹射范围、击晕（养雷壶额外加成范围）
    local bounceRange = 3 + (attacker.thunderJarRange or 0)
    local stunChance = 7
    local stunDuration = 1

    -- 伤害计算：取 max(atk, mAtk) 作为攻击力（返回是否命中）
    local function hitTarget(m)
        -- 闪避判定
        if rollDodge(attacker, m, nil) then
            M.addDamageText(m.x, m.y, "Miss", {255, 255, 255})
            return false
        end
        local phys = attacker.atk or 0
        local mag  = attacker.mAtk or 0
        local useMag = mag > phys
        local atkVal = useMag and mag or phys
        local defVal = useMag and (m.mdef or m.def or 0) or (m.def or 0)
        local baseDmg = math.floor(atkVal * atkVal / math.max(1, atkVal + defVal))
        baseDmg = math.max(1, baseDmg)
        local variance = math.floor(baseDmg * 0.1)
        baseDmg = baseDmg + math.random(-variance, variance)
        baseDmg = math.max(1, baseDmg)
        baseDmg = math.floor(baseDmg * mul)
        baseDmg = math.max(1, baseDmg)
        -- 通用加成管线（暴击、标记、元素等）
        local finalDmg, isCrit = applyDmgBonuses(attacker, m, baseDmg, { element = "thunder", useMagic = useMag })
        -- 魅力加成：同伴闪电链伤害 +1%/点
        if attacker.isCompanion then
            local ownerCha = GS.player and GS.player.cha or 0
            if ownerCha > 0 then
                finalDmg = math.max(1, math.floor(finalDmg * (1 + ownerCha / 100)))
            end
        end
        applyDamageAndCheck(attacker, m, finalDmg, "", {255, 220, 60}, isCrit, true)
        -- 击晕判定（英雄单位免疫）
        if m.hp > 0 and not m.stunned and not isHeroUnit(m) then
            local chance = stunChance
            -- 失感：每层冻僵+5%晕眩概率
            if m._numbingPending then
                chance = chance + m._numbingPending * 5
                m._numbingPending = nil
            end
            if math.random(1, 100) <= chance then
                m.stunned = stunDuration
                M.addDamageText(m.x, m.y - 0.5, "晕眩!", {255, 220, 60})
            end
        end
        return true
    end

    -- 屏幕震动
    GS.setScreenShake(0.3, 2, 0.1)

    -- 链路径特效
    local chainPath = { { fx = attacker.x, fy = attacker.y, tx = defender.x, ty = defender.y } }

    -- 命中主目标
    hitTarget(defender)

    -- 弹射逻辑
    local hitSet = { [defender] = true }
    local current = defender
    local bounceCount = 0
    while bounceCount < maxBounce do
        local best = nil
        local bestDist = bounceRange + 1
        for _, m in ipairs(GS.monsters) do
            if m.hp > 0 and not hitSet[m] then
                local dist = GS.manhattanToUnit(current.x, current.y, m)
                if dist <= bounceRange and dist < bestDist then
                    bestDist = dist
                    best = m
                end
            end
        end
        if not best then break end
        hitSet[best] = true
        chainPath[#chainPath + 1] = { fx = current.x, fy = current.y, tx = best.x, ty = best.y }
        hitTarget(best)
        current = best
        bounceCount = bounceCount + 1
    end

    -- 闪电链特效（复用法师的特效系统）
    M.addLightningChainEffect(chainPath)



    attacker._affixChainLightning = nil
end

--- 迪哈塔暴怒散射：怪物攻击后，根据 rageScatter 攻击额外友方目标（含冰墙）
--- @param attacker table 攻击者（怪物）
--- @param target table 主目标
function M.applyMonsterRageScatter(attacker, target)
    if not attacker or not attacker.isMonster then return end
    if M._monsterRageScattering then return end
    local sc = attacker.rageScatter or 0
    if sc <= 0 then return end
    -- 收集攻击范围内的友方单位（玩家+同伴+冰墙），排除主目标
    local range = attacker.atkRange or 1
    local candidates = {}
    local allies = {}
    if GS.player and GS.player.hp > 0 then allies[#allies + 1] = GS.player end
    for _, c in ipairs(GS.companions) do
        if c.hp and c.hp > 0 then allies[#allies + 1] = c end
    end
    for _, a in ipairs(allies) do
        if a ~= target then
            local dist = GS.manhattanToUnit(attacker.x, attacker.y, a)
            if dist <= range then
                candidates[#candidates + 1] = { target = a, dist = dist, isIceWall = false }
            end
        end
    end
    -- 冰墙也作为散射候选目标
    if GS.iceWalls then
        for _, w in ipairs(GS.iceWalls) do
            if w ~= target and w.hitsLeft and w.hitsLeft > 0 then
                local dist = math.abs(attacker.x - w.x) + math.abs(attacker.y - w.y)
                if dist <= range then
                    candidates[#candidates + 1] = { target = w, dist = dist, isIceWall = true }
                end
            end
        end
    end
    if #candidates == 0 then return end
    table.sort(candidates, function(a, b) return a.dist < b.dist end)
    local count = math.min(sc, #candidates)
    M._monsterRageScattering = true
    for i = 1, count do
        local c = candidates[i]
        if c.isIceWall then
            M.attackIceWall(c.target, attacker)
        else
            M.performAttack(attacker, c.target)
        end
    end
    M._monsterRageScattering = nil
end

--- 深渊词缀：远程普攻散射（提取为独立函数，连击和主攻击共用）
--- 散射额外攻击不触发攻速连击/双持/二连击，防止攻击次数膨胀
applyRangedScatter = function(attacker, target)
    if not target or not target.isMonster then return end
    if attacker.isMonster or M._rangedScattering then return end
    if attacker ~= GS.player then return end
    local wTag = getPlayerWeaponTag()
    if wTag ~= "弓" and wTag ~= "法杖" and not isPlayerLittleZeus() then return end
    -- 聚焦器：仅屏蔽深渊词缀散射，保留装备来源
    local scatterCount = 0
    if (attacker.focuserDmgPer or 0) <= 0 then
        scatterCount = scatterCount + countAbyssAffix("ranged_scatter")
    end
    -- 英雄长弓独立计算（不走深渊词缀，不受聚焦器影响）
    local weaponR_sc = GS.equipment and GS.equipment["weapon_r"]
    if weaponR_sc and weaponR_sc.templateId == "hero_bow" then scatterCount = scatterCount + 1 end
    -- 军火库箭袋提供的散射（不受聚焦器影响）
    scatterCount = scatterCount + (GS.player.arsenalScatter or 0)
    -- 分心满级：散射+1
    local distractLv = GS.skillLevels and GS.skillLevels["h_distraction"] or 0
    if distractLv >= (GS.SKILL_MAX_LEVEL or 10) then
        scatterCount = scatterCount + 1
    end
    if scatterCount <= 0 then return end
    local range = GS.player.atkRange or 1
    local extras = pickMultiCastTargets(attacker, {target}, scatterCount, range)
    if #extras <= 0 then return end
    M._rangedScattering = true
    local savedAtkSpeed = attacker._atkSpeedChaining
    local savedDualDagger = attacker._dualDaggerChaining
    local savedDoubleStrike = attacker._doubleStrikeChaining
    attacker._atkSpeedChaining = true
    attacker._dualDaggerChaining = true
    attacker._doubleStrikeChaining = true
    for _, et in ipairs(extras) do
        M.performAttack(attacker, et, nil)
    end
    attacker._atkSpeedChaining = savedAtkSpeed
    attacker._dualDaggerChaining = savedDualDagger
    attacker._doubleStrikeChaining = savedDoubleStrike
    M._rangedScattering = nil
end

--- 分心：普攻概率触发一次当前等级的多重射（扣蓝，不设CD）
local function tryDistraction(attacker, target)
    if not target or attacker.isMonster or attacker ~= GS.player then return end
    if M._distracting or M._rangedScattering then return end
    local lv = GS.skillLevels and GS.skillLevels["h_distraction"] or 0
    if lv <= 0 then return end
    -- 需要装备弓
    local wTag = getPlayerWeaponTag()
    if wTag ~= "弓" then return end
    -- 2% per level
    local chance = 2 * lv
    if math.random(100) > chance then return end
    -- 检查蓝量（按多重射当前等级计算消耗）
    local mpCost = GS.getSkillMpCost("h_scatter")
    if (GS.player.mp or 0) < mpCost then return end
    -- 手动扣蓝
    GS.player.mp = GS.player.mp - mpCost
    -- 触发多重射（跳过 useSkill 避免设置CD）
    M._distracting = true
    GS._skipUseSkill = true
    M.performScatter(attacker, target, "h_scatter")
    GS._skipUseSkill = nil
    M._distracting = nil
end

--- 反击/复仇：玩家被怪物攻击后概率反击
local function tryCounterAttack(attacker, defender, dodged)
    if attacker.isMonster and not defender.isMonster and defender.hp > 0 then
        -- 反击/复仇仅在右手装备单手剑时生效
        local wr = GS.equipment and GS.equipment["weapon_r"]
        if not wr or wr.weaponTag ~= "单手剑" then return end
        -- 近战范围判定：攻击者在玩家前后左右（曼哈顿距离≤1）即视为近战范围
        local dist = math.abs(attacker.x - defender.x) + math.abs(attacker.y - defender.y)
        local inMeleeRange = dist <= 1
        -- 超出近战范围：需要天蝎座等盾牌的 counterRangedPct 才能触发
        if not inMeleeRange and (defender.counterRangedPct or 0) <= 0 then return end
        local rangedMult = inMeleeRange and 1.0 or (defender.counterRangedPct or 1.0)

        -- 水中蛇词条1：左手武器栏为空时，反击概率提高
        local wl = GS.equipment and GS.equipment["weapon_l"]
        local snakeChanceBonus = (not wl) and (defender.dodgeCounterChanceBonus or 0) or 0
        -- 水中蛇词条2：闪避可以触发反击，反击伤害提高（不受左手限制）
        local snakeDodgeCounter = (defender.dodgeCounterDmgBonus or 0) > 0
        local snakeDmgMul = snakeDodgeCounter and (1 + (defender.dodgeCounterDmgBonus or 0) / 100) or 1

        local mstLv = GS.skillLevels["mst_counter"] or 0
        local counterLv = GS.skillLevels["counter"] or 0
        if mstLv > 0 then
            local mstDef = GS.SKILL_DEFS["mst_counter"]
            local chance = (mstDef.mstCounterChance or 53) + (mstLv - 1) * (mstDef.mstCounterChancePerLv or 3) + snakeChanceBonus
            -- 水中蛇：闪避时必定触发反击
            if snakeDodgeCounter and dodged then chance = 100 end
            if math.random(1, 100) <= chance then
                -- 复仇命中判定：被对方闪避则miss
                if rollDodge(defender, attacker) then
                    M.addDamageText(attacker.x, attacker.y, "闪避!", {200, 200, 200})
                else
                -- 复仇发光：耀眼红光 + 画面震动
                defender.counterGlow = { timer = 0, duration = 0.5, r = 255, g = 40, b = 40 }
                GS.setScreenShake(0.15, 2, 0)
                local dmgRate = ((mstDef.mstCounterDmgRate or 0.73) + (mstLv - 1) * (mstDef.mstCounterDmgRatePerLv or 0.03)) * rangedMult
                local cdmg, isCrit
                if mstDef.mstCounterTrueDmg then
                    -- 真实伤害：atk * rate，无视防御，走加成管线（暴击/标记等）
                    cdmg = math.max(1, math.floor(defender.atk * dmgRate))
                    local variance = math.floor(cdmg * 0.1)
                    cdmg = cdmg + math.random(-variance, variance)
                    cdmg = math.max(1, cdmg)
                    cdmg, isCrit = applyDmgBonuses(defender, attacker, cdmg, {})
                else
                    -- 常规公式：走完整 calcSkillDamage
                    cdmg, isCrit = calcSkillDamage(defender, attacker, { mul = dmgRate })
                end
                -- 水中蛇：反击伤害加成（仅闪避触发时生效）
                if dodged and snakeDmgMul > 1 then cdmg = math.max(1, math.floor(cdmg * snakeDmgMul)) end
                M.addDamageText(defender.x, defender.y - 0.5, "复仇!", {255, 60, 60})
                if not inMeleeRange then
                    -- 远程反击：发射剑气弹道，伤害延迟到命中时显示
                    M._pendingProjectileHit = true
                    M.addSwordQiEffect(defender.x, defender.y, attacker.x, attacker.y, 0)
                    applyDamageAndCheck(defender, attacker, cdmg, "-", {255, 255, 255}, isCrit)
                    M._pendingProjectileHit = false
                    M._currentProjectileId = nil
                else
                    M.addAttackEffect(defender.x, defender.y, attacker.x, attacker.y, "单手剑")
                    applyDamageAndCheck(defender, attacker, cdmg, "-", {255, 255, 255}, isCrit)
                end
                -- 大剧院：反击连击（复仇后追加，体质规则：每1点体质提供counterComboConRate%概率，封顶counterComboMax次）
                if attacker.hp > 0 and (defender.counterComboMax or 0) > 0 and (defender.counterComboConRate or 0) > 0 then
                    local conStat = defender.con or 0
                    local ratePer = defender.counterComboConRate or 0
                    local totalPct = conStat * ratePer  -- 总概率百分比
                    if totalPct > 0 then
                        local guaranteed = math.floor(totalPct / 100)
                        local remainChance = (totalPct % 100) / 100
                        local extraCount = guaranteed
                        if math.random() < remainChance then extraCount = extraCount + 1 end
                        extraCount = math.min(extraCount, defender.counterComboMax)
                        for ci = 1, extraCount do
                            if attacker.hp <= 0 then break end
                            local comboDmg, comboCrit
                            if mstDef.mstCounterTrueDmg then
                                comboDmg = math.max(1, math.floor(defender.atk * dmgRate))
                                local variance = math.floor(comboDmg * 0.1)
                                comboDmg = comboDmg + math.random(-variance, variance)
                                comboDmg = math.max(1, comboDmg)
                                comboDmg, comboCrit = applyDmgBonuses(defender, attacker, comboDmg, {})
                            else
                                comboDmg, comboCrit = calcSkillDamage(defender, attacker, { mul = dmgRate })
                            end
                            -- 水中蛇：连击伤害加成（仅闪避触发时生效）
                            if dodged and snakeDmgMul > 1 then comboDmg = math.max(1, math.floor(comboDmg * snakeDmgMul)) end
                            if not inMeleeRange then
                                -- 远程连击：依次发射剑气，每枚间隔0.35秒
                                M._pendingProjectileHit = true
                                M.addSwordQiEffect(defender.x, defender.y, attacker.x, attacker.y, ci * 0.35)
                                applyDamageAndCheck(defender, attacker, comboDmg, "-", {255, 255, 255}, comboCrit)
                                M._pendingProjectileHit = false
                                M._currentProjectileId = nil
                            else
                                M.addAttackEffect(defender.x, defender.y, attacker.x, attacker.y, "单手剑")
                                applyDamageAndCheck(defender, attacker, comboDmg, "-", {255, 255, 255}, comboCrit)
                            end
                        end
                    end
                end
                end -- else (not dodged)
            end
        elseif counterLv > 0 and not GS.counterUsedThisTurn then
            local chance = counterLv * 3 + snakeChanceBonus
            -- 水中蛇：闪避时必定触发反击
            if snakeDodgeCounter and dodged then chance = 100 end
            if math.random(1, 100) <= chance then
                GS.counterUsedThisTurn = true
                -- 反击发光：蓝光 + 画面震动
                defender.counterGlow = { timer = 0, duration = 0.5, r = 60, g = 140, b = 255 }
                GS.setScreenShake(0.15, 2, 0)
                local counterDef = GS.SKILL_DEFS["counter"]
                local cdmg, isCrit = calcSkillDamage(defender, attacker, { mul = (counterDef.counterDmgRate or 0.65) * rangedMult })
                -- 水中蛇：反击伤害加成（仅闪避触发时生效）
                if dodged and snakeDmgMul > 1 then cdmg = math.max(1, math.floor(cdmg * snakeDmgMul)) end
                M.addDamageText(defender.x, defender.y - 0.5, "反击!", {192, 192, 200})
                if not inMeleeRange then
                    M._pendingProjectileHit = true
                    M.addSwordQiEffect(defender.x, defender.y, attacker.x, attacker.y, 0)
                    applyDamageAndCheck(defender, attacker, cdmg, "-", {255, 255, 255}, isCrit)
                    M._pendingProjectileHit = false
                    M._currentProjectileId = nil
                else
                    M.addAttackEffect(defender.x, defender.y, attacker.x, attacker.y, "单手剑")
                    applyDamageAndCheck(defender, attacker, cdmg, "-", {255, 255, 255}, isCrit)
                end
                -- 大剧院：反击连击（反击后追加，体质规则：每1点体质提供counterComboConRate%概率，封顶counterComboMax次）
                if attacker.hp > 0 and (defender.counterComboMax or 0) > 0 and (defender.counterComboConRate or 0) > 0 then
                    local conStat = defender.con or 0
                    local ratePer = defender.counterComboConRate or 0
                    local totalPct = conStat * ratePer  -- 总概率百分比
                    if totalPct > 0 then
                        local guaranteed = math.floor(totalPct / 100)
                        local remainChance = (totalPct % 100) / 100
                        local extraCount = guaranteed
                        if math.random() < remainChance then extraCount = extraCount + 1 end
                        extraCount = math.min(extraCount, defender.counterComboMax)
                        for ci = 1, extraCount do
                            if attacker.hp <= 0 then break end
                            local comboDmg, comboCrit = calcSkillDamage(defender, attacker, { mul = (counterDef.counterDmgRate or 0.65) * rangedMult })
                            -- 水中蛇：连击伤害加成（仅闪避触发时生效）
                            if dodged and snakeDmgMul > 1 then comboDmg = math.max(1, math.floor(comboDmg * snakeDmgMul)) end
                            if not inMeleeRange then
                                M._pendingProjectileHit = true
                                M.addSwordQiEffect(defender.x, defender.y, attacker.x, attacker.y, ci * 0.35)
                                applyDamageAndCheck(defender, attacker, comboDmg, "-", {255, 255, 255}, comboCrit)
                                M._pendingProjectileHit = false
                                M._currentProjectileId = nil
                            else
                                M.addAttackEffect(defender.x, defender.y, attacker.x, attacker.y, "单手剑")
                                applyDamageAndCheck(defender, attacker, comboDmg, "-", {255, 255, 255}, comboCrit)
                            end
                        end
                    end
                end
            end
        -- 水中蛇独立分支：无反击/复仇技能，但闪避时水中蛇必定触发反击
        elseif snakeDodgeCounter and dodged then
            defender.counterGlow = { timer = 0, duration = 0.5, r = 100, g = 220, b = 120 }
            GS.setScreenShake(0.15, 2, 0)
            -- 基础伤害倍率0.65（与反击技能1级相同），乘以水中蛇加成
            local baseMul = 0.65 * rangedMult
            local cdmg, isCrit = calcSkillDamage(defender, attacker, { mul = baseMul })
            cdmg = math.max(1, math.floor(cdmg * snakeDmgMul))
            M.addDamageText(defender.x, defender.y - 0.5, "蛇击!", {100, 220, 120})
            if not inMeleeRange then
                M._pendingProjectileHit = true
                M.addSwordQiEffect(defender.x, defender.y, attacker.x, attacker.y, 0)
                applyDamageAndCheck(defender, attacker, cdmg, "-", {255, 255, 255}, isCrit)
                M._pendingProjectileHit = false
                M._currentProjectileId = nil
            else
                M.addAttackEffect(defender.x, defender.y, attacker.x, attacker.y, "单手剑")
                applyDamageAndCheck(defender, attacker, cdmg, "-", {255, 255, 255}, isCrit)
            end
        end
    end
end

--- 特殊怪物击中效果（精锐debuff + 史莱姆王击退）
local function applyMonsterHitEffects(attacker, defender)
    -- 电/冰史莱姆精锐攻击 debuff
    if attacker.isMonster and attacker.eliteType and not defender.isMonster and defender.hp > 0 then
        if attacker.eliteType == "elec" then
            local existed = false
            for _, db in ipairs(GS.playerDebuffs) do
                if db.source == "elec" and db.type == "dodge" then
                    existed = true
                    if 3 > db.turns then db.turns = 3; M.addDamageText(defender.x, defender.y - 0.5, "麻痹!", {255, 220, 60}) end
                    break
                end
            end
            if not existed then
                table.insert(GS.playerDebuffs, { type = "dodge", val = 10, turns = 3, source = "elec" })
                M.addDamageText(defender.x, defender.y - 0.5, "麻痹!", {255, 220, 60})
            end
        elseif attacker.eliteType == "ice" then
            local existed = false
            for _, db in ipairs(GS.playerDebuffs) do
                if db.source == "ice" and db.type == "move" then
                    existed = true
                    if 3 > db.turns then db.turns = 3; M.addDamageText(defender.x, defender.y - 0.5, "冻僵!", {100, 200, 255}) end
                    break
                end
            end
            if not existed then
                table.insert(GS.playerDebuffs, { type = "move", val = 1, turns = 3, source = "ice" })
                M.addDamageText(defender.x, defender.y - 0.5, "冻僵!", {100, 200, 255})
            end
        end
    end

    -- 史莱姆王被动：击退 + 撞墙伤害
    if attacker.isMonster and attacker.knockbackDist and attacker.knockbackDist > 0
       and not defender.isMonster and defender.hp > 0 then
        local kbDist = attacker.knockbackDist
        local wallDmg = attacker.knockbackWallDmg or 300
        if GS.currentStage == GS.STAGE_SLIME_KING_REVENGE then
            wallDmg = (attacker.level or 1) * 20
        end
        local kcx, kcy = GS.unitCenterPos(attacker)
        local dx = defender.x - kcx
        local dy = defender.y - kcy
        local kbDx, kbDy = 0, 0
        if math.abs(dx) >= math.abs(dy) then
            kbDx = dx > 0 and 1 or -1
        else
            kbDy = dy > 0 and 1 or -1
        end
        local actualKB = 0
        local newX, newY = defender.x, defender.y
        for step = 1, kbDist do
            local nx = defender.x + kbDx * step
            local ny = defender.y + kbDy * step
            if GS.isInBoard(nx, ny) and GS.isCellEmpty(nx, ny) then
                newX, newY = nx, ny
                actualKB = step
            else
                break
            end
        end
        if actualKB > 0 then
            local oldX, oldY = defender.x, defender.y
            defender.x = newX
            defender.y = newY
            M.startMoveAnim(defender, oldX, oldY)
            -- M.addDamageText(newX, newY, "击退!", {255, 180, 50})
        end
        -- 迪哈塔关卡：击退是纯位移，不产生任何撞击伤害
        if actualKB < kbDist and GS.currentStage ~= GS.STAGE_DIHATA_REVENGE then
            local nextX = newX + kbDx
            local nextY = newY + kbDy
            if not GS.isInBoard(nextX, nextY) then
                -- 撞墙伤害
                defender.hp = defender.hp - wallDmg
                trackTrainingDamage(defender, wallDmg)
                immortalGuard(defender, wallDmg)
                M.addDamageText(newX, newY, "撞击边缘!", {255, 50, 50})
                M.addDamageText(newX, newY - 0.4, "" .. wallDmg, {255, 50, 50})
                M.addHurtFlash(defender)
                if defender.hp <= 0 then
                    defender.hp = 0
                end
            elseif GS.currentStage == GS.STAGE_SLIME_KING_REVENGE then
                -- 大反击关卡：撞到有碰撞体积的单位时受到 暴怒史莱姆王等级×3 伤害
                local blocker = GS.getUnitAt(nextX, nextY)
                if blocker and blocker.hp and blocker.hp > 0 then
                    local collisionDmg = (attacker.level or 1) * 3
                    defender.hp = defender.hp - collisionDmg
                    M.addDamageText(newX, newY, "撞击!", {255, 120, 50})
                    M.addDamageText(newX, newY - 0.4, "" .. collisionDmg, {255, 120, 50})
                    M.addHurtFlash(defender)
                    if defender.hp <= 0 then
                        defender.hp = 0
                    end
                end
            end
        end
    end
end

--- 连击入队：双匕首/攻速连击/二连击
local function enqueueChainAttacks(attacker, defender, skillId)
    -- 极重月：禁止触发所有连击
    if not attacker.isMonster and attacker.noCombo then return end
    local queueBefore = #M.chainQueue  -- 记录入队前的队列长度，用于检测零连击击杀
    -- 双持第二击（双匕首或剑匕双持）
    if not skillId and not attacker.isMonster and not attacker.isCompanion
       and not attacker._dualDaggerChaining
       and GS.isDualMelee() then
        local extraHits = 1
        table.insert(M.chainQueue, {
            attacker = attacker, defender = defender,
            label = "", color = {200, 150, 255},
            isDualDagger = true,
        })
        for i = 2, extraHits do
            table.insert(M.chainQueue, {
                attacker = attacker, defender = defender,
                label = "", color = {200, 150, 255},
                isDualDagger = true,
            })
        end
    end

    -- 攻速连击（法杖普攻不受攻击速度影响，不触发连击）
    local weaponTag = not attacker.isMonster and getPlayerWeaponTag() or nil
    -- 怪物拥有 atkSpeed 时（急速词缀）也可触发连击
    local canAtkSpeedChain = not skillId and not attacker._atkSpeedChaining
        and (not attacker.isMonster and weaponTag ~= "法杖" or (attacker.isMonster and (attacker.atkSpeed or 0) > 0))
    if canAtkSpeedChain then
        local spd = (attacker.atkSpeed or 0) + WE.getRainAtkSpeedMod()
        if spd > 0 then
            local totalPct = spd * 2
            local guaranteed = math.floor(totalPct / 100)
            local remainChance = (totalPct % 100) / 100
            local extraCount = guaranteed
            if math.random() < remainChance then
                extraCount = extraCount + 1
            end
            for i = 1, extraCount do
                table.insert(M.chainQueue, {
                    attacker = attacker, defender = defender,
                    label = "", color = {255, 200, 50},
                })
            end
        end
    end

    -- 二连击
    if not skillId and not attacker.isMonster and not attacker.isCompanion
       and not attacker._atkSpeedChaining and not attacker._dualDaggerChaining
       and not attacker._doubleStrikeChaining then
        local dsLv = GS.skillLevels["a_double_strike"] or 0
        if dsLv > 0 then
            local dsDef = GS.SKILL_DEFS["a_double_strike"]
            local chance = (dsDef.doubleStrikeBaseChance or 2) + (dsDef.doubleStrikeChancePerLv or 2) * (dsLv - 1)
            if math.random(1, 100) <= chance then
                table.insert(M.chainQueue, {
                    attacker = attacker, defender = defender,
                    label = "", color = {255, 120, 200},
                    isDoubleStrike = true,
                })
            end
        end
    end

    -- 击杀预计入：普攻击杀目标时，非双持连击虽已入队但注定转火失败
    -- （目标已死，转火找不到时 _moonShadowMissed 才会 +1），
    -- 但实际上连击可能找到其他活着的目标并成功攻击，导致 _moonShadowMissed 为 0。
    -- 解决方案：提前将击杀本回合入队的非双持连击数记录为 _offeringMissed，
    -- 献礼结算时取 max(moonShadowMissed, offeringMissed) 确保能正常触发。
    if attacker == GS.player and not skillId and defender.hp <= 0 then
        local nNonDual = 0
        for i = queueBefore + 1, #M.chainQueue do
            if not M.chainQueue[i].isDualDagger then
                nNonDual = nNonDual + 1
            end
        end
        if nNonDual > 0 then
            M._offeringMissed = (M._offeringMissed or 0) + nNonDual
        end
    end
end
-- 远程弹道怪物ID集合
-- 远程怪物弹道配置：
--   "bow"  = 弓箭弹道（weaponTag "弓"）
--   其他   = 魔法飞弹弹道（weaponTag "法杖"），值作为 monsterProjectile 传递给渲染
local RANGED_MONSTER_IDS = {
    goblin_archer      = "bow",       -- 弓箭弹道
    centaur_hunter     = "bow",       -- 弓箭弹道
    skeleton_archer    = "bow",       -- 弓箭弹道
    fire_slime         = "fire",      -- 火焰飞弹（元素史莱姆）
    ice_slime          = "ice",       -- 冰冻飞弹（元素史莱姆）
    elec_slime         = "lightning",  -- 电击术弹道（闪电弧线）
    elec_slime_enraged = "lightning",  -- 暴怒雷史莱姆（闪电弧线）
    candle_monster     = "fire",      -- 火焰飞弹
    tree_fairy         = "nature",    -- 绿色自然飞弹
    five_eye_starfish  = "ice",       -- 冰冻飞弹
    cosmos_demon_a     = "dark",      -- 暗黑紫色飞弹
    maid_doll          = "arcane",    -- 奥术紫色飞弹
    vampire_girl       = "dark",      -- 暗影魔法（shadow→dark）
    vampire_female     = "dark",      -- 暗影魔法（shadow→dark）
    centaur_priest     = "dark",      -- 暗影魔法（shadow→dark）
    nameless_horror    = "dark",      -- 暗影魔法（shadow→dark）
    flower_fairy       = "nature",    -- 自然魔法（element=nature）
    cosmos_demon_elite = "dark",      -- 暗黑飞弹（与普通版统一）
    red_dragon_young   = "fireball",   -- 红龙幼龙火球术弹道（3x3 AOE）
    goblin_boss_dila   = "ice_spike", -- 冰锥术弹道（哥布林竞技场BOSS）
    tidal_boss_kuadi   = "lightning",  -- 电击术弹道（先知"夸迪"，雷电）
    tidal_boss_unknown = "dark",       -- 暗影魔法（不可知物，shadow→dark）
    goblin_hero_dihata = "bow",        -- 哥布林英雄迪哈塔（弓箭弹道）
}

-- ====================================================================
-- 装备效果：技能使用触发技能（如全知挂饰：33%概率对最近敌人使用1级冰锥术）
-- 由 performAttack（伤害技能）和 executePlayerAttack（治疗/增益技能）共同调用
-- ====================================================================
--- @param attacker table 攻击者
--- @param fallbackTarget table|nil 默认目标（伤害技能传 defender，治疗/增益传 nil）
local function trySkillUseProc(attacker, fallbackTarget)
    if attacker.isMonster then return end
    if attacker._skillUseProcing or attacker._normalAtkProcing or attacker._phantomAttacking then return end
    if not GS.equipment then return end
    for _, slotId in ipairs({"hat","necklace","ring","weapon_r","weapon_l","body","legs","feet","shoulder","gloves","trinket","cloak"}) do
        local slot = GS.equipment[slotId]
        if slot and slot.templateId then
            local tpl = GS.itemTemplates[slot.templateId]
            if tpl and tpl.skillUseProc then
                local proc = tpl.skillUseProc
                if math.random(1, 100) <= (proc.chance or 0) then
                    attacker._skillUseProcing = true
                    -- 查找目标：targetNearest 时选最近存活敌人，否则用 fallbackTarget
                    local procTarget = fallbackTarget
                    if proc.targetNearest or not procTarget then
                        local bestDist = math.huge
                        for _, m in ipairs(GS.monsters) do
                            if m.hp > 0 then
                                local dx = math.abs(m.x - attacker.x)
                                local dy = math.abs(m.y - attacker.y)
                                local dist = math.max(dx, dy)
                                if dist < bestDist then
                                    bestDist = dist
                                    procTarget = m
                                end
                            end
                        end
                    end
                    if procTarget and procTarget.hp > 0 then
                        local pPhys = attacker.atk or 0
                        local pMag  = attacker.mAtk or 0
                        local useMag = pMag > pPhys
                        local spAtk = useMag and pMag or pPhys
                        local sDef = GS.SKILL_DEFS[proc.skillId]
                        if sDef then
                            local procLv = proc.level or 1
                            local mulBase = sDef.dmgMul or 1.0
                            local mulPerLv = sDef.dmgMulPerLv or 0
                            local mul = mulBase + (procLv - 1) * mulPerLv
                            local tDef = useMag and (procTarget.mdef or procTarget.def or 0) or (procTarget.def or 0)
                            local baseDmg = math.floor(spAtk * spAtk / math.max(1, spAtk + tDef))
                            baseDmg = math.max(1, baseDmg)
                            local spVar = math.floor(baseDmg * 0.1)
                            baseDmg = baseDmg + math.random(-spVar, spVar)
                            baseDmg = math.max(1, baseDmg)
                            baseDmg = math.floor(baseDmg * mul)
                            baseDmg = math.max(1, baseDmg)
                            local spFinalDmg, spCrit = applyDmgBonuses(attacker, procTarget, baseDmg,
                                { element = sDef.element or "ice", useMagic = useMag })
                            if proc.dmgCap and spFinalDmg > proc.dmgCap then
                                spFinalDmg = proc.dmgCap
                            end
                            M.addAttackEffect(attacker.x, attacker.y, procTarget.x, procTarget.y,
                                "法杖", false, nil, nil, proc.skillId, proc.skillId == "m_ice_spike" and "ice_spike" or nil)
                            applyDamageAndCheck(attacker, procTarget, spFinalDmg, "", {100, 180, 240}, spCrit, true)
                            local spName = sDef.name or "技能"
                            M.addDamageText(procTarget.x, procTarget.y - 0.5, spName .. "!", {100, 180, 240})
                            if procTarget.hp > 0 and sDef.stunChance and (sDef.stunChance or 0) > 0 then
                                if math.random(1, 100) <= sDef.stunChance then
                                    procTarget.stunned = sDef.stunDuration or 2
                                    M.addDamageText(procTarget.x, procTarget.y - 0.5, "冻僵!", {100, 180, 240})
                                end
                            end
                            GS.setScreenShake(0.12, 2, 0)
                        end
                    end
                    attacker._skillUseProcing = nil
                    break
                end
            end
        end
    end
end

function M.performAttack(attacker, defender, skillId)
    -- 静神被动：玩家本回合未移动 + 持弓 + 已学静神 → 自动施加/刷新 buff
    if attacker == GS.player and not GS._playerMovedThisTurn then
        local fDef = GS.SKILL_DEFS["h_shuttle"]
        local fLv = GS.skillLevels["h_shuttle"] or 0
        if fDef and fLv > 0 then
            local wTag = GS.equipment and GS.equipment["weapon_r"] and GS.equipment["weapon_r"].weaponTag
            if wTag == "弓" then
                GS.focusBuffTurns = 1  -- 仅本回合生效，回合结束自动递减为0
                GS.recalcStats(attacker)
            end
        end
    end
    -- 攻击时面向目标
    GS.faceTarget(attacker, defender)
    -- 弹道类攻击：标记后续伤害文字为"待命中"，由攻击特效到达目标时触发显示
    M._pendingProjectileHit = false
    M._currentProjectileId = nil
    if attacker.isMonster and (RANGED_MONSTER_IDS[attacker.defId] or attacker.affixRangedStyle) then
        M._pendingProjectileHit = true
    elseif not attacker.isMonster then
        local sDef = skillId and GS.SKILL_DEFS[skillId]
        if sDef and sDef.throwSkill then
            M._pendingProjectileHit = true
        else
            local wTag = attacker.isCompanion and (attacker.weaponTag or "爪") or getPlayerWeaponTag()
            if wTag == "弓" or wTag == "法杖" then
                M._pendingProjectileHit = true
            end
        end
    end
    -- 预分配弹道ID：确保后续 addDamageText 能拿到正确的 projectileId
    -- （addDamageText 在 addAttackEffect 之前调用，必须提前分配）
    if M._pendingProjectileHit then
        M._projectileIdCounter = M._projectileIdCounter + 1
        M._currentProjectileId = M._projectileIdCounter
    end
    -- 设置怪物远程标记供 WeatherEffects 使用
    if attacker.isMonster then
        attacker._isRangedMonster = (RANGED_MONSTER_IDS[attacker.defId] or attacker.affixRangedStyle) ~= nil
    end
    -- 确定当前武器标签供风效果判定使用
    local currentWeaponTag = (not attacker.isMonster and not attacker.isCompanion) and getPlayerWeaponTag() or nil

    -- 闪避判定（使用通用函数）
    local dodged = rollDodge(attacker, defender, skillId)
    if dodged then
        M.addDamageText(defender.x, defender.y, "Miss", {255, 255, 255})
        -- 攻击特效仍然播放
        local rangedStyle = attacker.isMonster and (RANGED_MONSTER_IDS[attacker.defId] or attacker.affixRangedStyle)
        local atkCX, atkCY = GS.unitCenterPos(attacker)
        if attacker._phantomPos then atkCX, atkCY = attacker._phantomPos[1], attacker._phantomPos[2] end
        local defTX, defTY = getDefenderEffectPos(attacker, defender)
        if rangedStyle == "bow" then
            local dihataStyle = isDihataUnit(attacker) and "stun_shot" or nil
            M.addAttackEffect(atkCX, atkCY, defTX, defTY, "弓", false, dihataStyle)
        elseif rangedStyle == "ice_spike" then
            M.addAttackEffect(atkCX, atkCY, defTX, defTY, "法杖", false, nil, nil, "m_ice_spike", rangedStyle)
        elseif rangedStyle == "lightning" or rangedStyle == "thunder" then
            M.addAttackEffect(atkCX, atkCY, defTX, defTY, "法杖", false, nil, nil, "m_lightning", rangedStyle)
        elseif rangedStyle then
            M.addAttackEffect(atkCX, atkCY, defTX, defTY, "法杖", false, nil, nil, nil, rangedStyle)
        elseif attacker.isMonster and attacker.weaponTag then
            M.addAttackEffect(atkCX, atkCY, defTX, defTY, attacker.weaponTag, false)
        elseif attacker.isMonster then
            M.addSlamAnim(attacker, defender.x, defender.y)
        else
            local wTag
            if attacker.isCompanion then
                wTag = attacker.weaponTag or "爪"
            else
                wTag = getPlayerWeaponTag()
            end
            -- 闪避时也播放正确的技能特效（与命中路径一致）
            if skillId and GS.SKILL_DEFS[skillId] and GS.SKILL_DEFS[skillId].useMagic then
                wTag = "法杖"
            end
            if skillId and (skillId == "strike" or skillId == "sup_stk" or skillId == "mst_stk") then
                M.addStrikeEffect(atkCX, atkCY, defTX, defTY, skillId)
            elseif skillId and skillId == "p_bless" then
                M.addBlessEffect(atkCX, atkCY, defTX, defTY, false)
            elseif skillId and skillId == "p_exorcism" then
                M.addBlessEffect(atkCX, atkCY, defTX, defTY, true)
            elseif skillId and skillId == "h_power_shot" then
                M.addAttackEffect(atkCX, atkCY, defTX, defTY, wTag, attacker.isCompanion, "power_shot")
            elseif skillId and skillId == "h_stun_shot" then
                M.addAttackEffect(atkCX, atkCY, defTX, defTY, wTag, attacker.isCompanion, "stun_shot")
            elseif skillId and skillId == "h_snipe" then
                M.addAttackEffect(atkCX, atkCY, defTX, defTY, wTag, attacker.isCompanion, "snipe")
            elseif skillId and GS.SKILL_DEFS[skillId] and GS.SKILL_DEFS[skillId].throwSkill then
                M.addAttackEffect(atkCX, atkCY, defTX, defTY, wTag, attacker.isCompanion, "throw", skillId)
            elseif skillId and skillId == "m_thunder" then
                M.addThunderStrikeEffect(defender.x, defender.y)
            else
                M.addAttackEffect(atkCX, atkCY, defTX, defTY, wTag, attacker.isCompanion, nil, nil, skillId)
            end
            playAttackSound(wTag)
        end
    end

    -- 魔贯：施法即消耗MP，无论命中与否（风险机制）
    do
        local isMagicSkill = skillId and GS.SKILL_DEFS[skillId] and GS.SKILL_DEFS[skillId].useMagic
        local isStaffNormal = (not skillId) and not attacker.isMonster and not attacker.isCompanion
            and getPlayerWeaponTag() == "法杖"
        if (isMagicSkill or isStaffNormal) and (attacker.mpCostDmgCoeff or 0) > 0 then
            local curMp = GS.player and GS.player.mp or 0
            if curMp > 0 then
                local consumed = math.floor(curMp * 0.3)
                GS.player.mp = math.max(0, curMp - consumed)
                GS._mpCostBonusThisAtk = consumed * attacker.mpCostDmgCoeff
            else
                GS._mpCostBonusThisAtk = 0
            end
        else
            GS._mpCostBonusThisAtk = nil
        end
    end

  if not dodged then
    -- 魔法技能 或 法杖普攻：使用 matk/mdef 计算伤害
    local isMagicSkill = skillId and GS.SKILL_DEFS[skillId] and GS.SKILL_DEFS[skillId].useMagic
    -- 神圣伤害：祝福术/超度 使用 (物攻+魔攻)/2 和 (物防+魔防)/2
    local isHolySkill = skillId and (skillId == "p_bless" or skillId == "p_exorcism")
    -- 法杖普攻也走魔攻/魔防
    local isStaffNormal = (not skillId) and not attacker.isMonster and not attacker.isCompanion
        and getPlayerWeaponTag() == "法杖"
    -- 魔法系怪物走魔法伤害（对应玩家 mdef）；元素词缀怪也走魔法伤害
    local rangedStyle = attacker.isMonster and (RANGED_MONSTER_IDS[attacker.defId] or attacker.affixRangedStyle)
    local isMonsterMagic = rangedStyle and rangedStyle ~= "bow"
    local useMagic = isMagicSkill or isStaffNormal or isMonsterMagic
    -- 小宙斯普攻：物攻*physPct% + 魔攻*magPct%，防御取 (物防+魔防)/2
    local isLittleZeusNormal = (not skillId) and not attacker.isMonster and not attacker.isCompanion
        and isPlayerLittleZeus()
    local atkVal, defVal
    local _lzPhysRatio, _lzMagRatio  -- 小宙斯物理/魔法占比（供暴击/吸血复用）
    if isLittleZeusNormal then
        local eb = GS.getEquipBonus and GS.getEquipBonus() or {}
        local physPct = (eb.littleZeusPhysPct or 80) / 100
        local magPct  = (eb.littleZeusMagPct or 80) / 100
        local totalPct = physPct + magPct
        _lzPhysRatio = totalPct > 0 and (physPct / totalPct) or 0.5
        _lzMagRatio  = 1 - _lzPhysRatio
        atkVal = math.floor(attacker.atk * physPct + (attacker.mAtk or 0) * magPct)
        defVal = math.floor(defender.def * _lzPhysRatio + (defender.mdef or 0) * _lzMagRatio)
        useMagic = false  -- 暴击判定走特殊逻辑，此处标记为非魔法
    elseif isHolySkill then
        atkVal = attacker.atk + math.floor((attacker.mAtk or 0) / 2)
        defVal = math.floor((defender.def + (defender.mdef or 0)) / 2)
    elseif useMagic then
        atkVal = attacker.mAtk or attacker.atk
        defVal = defender.mdef or defender.def
    else
        atkVal = attacker.atk
        defVal = defender.def
    end
    -- 双持攻击伤害修正（基础40%；双匕首和剑匕双持共用基础惩罚，普攻和技能均受影响）
    -- 刺客投掷类技能豁免双持减值
    local isThrowSkill = skillId == "a_weapon_throw" or skillId == "a_poison_throw"
        or skillId == "a_armor_break" or skillId == "a_notice"
    if not isThrowSkill and not attacker.isMonster and not attacker.isCompanion
       and GS.isDualMelee() then
        local dualPct = 40
        -- 双持熟练/双持专精仅对双匕首生效
        if GS.isDualDagger() then
            for _, sid in ipairs({"a_dual_prof", "a_dual_master"}) do
                local lv = GS.skillLevels[sid] or 0
                if lv > 0 then
                    local sd = GS.SKILL_DEFS[sid]
                    if sd and sd.dualDmgPctPerLv then
                        dualPct = dualPct + sd.dualDmgPctPerLv * lv
                    end
                end
            end
        end
        dualPct = math.min(dualPct, 100) -- 上限100%
        atkVal = math.floor(atkVal * dualPct / 100)
    end
    -- 嘲讽 debuff：被嘲讽的单位攻击+X%、防御-X%
    if attacker.taunted and attacker.taunted > 0 then
        atkVal = math.floor(atkVal * (1 + (attacker.tauntAtkPct or 0) / 100))
    end
    if defender.taunted and defender.taunted > 0 then
        defVal = math.max(0, math.floor(defVal * (1 + (defender.tauntDefPct or 0) / 100)))
    end
    -- 破甲debuff：物理防御降低（仅影响物理伤害）
    if not useMagic and defender.armorBroken and defender.armorBrokenTurns and defender.armorBrokenTurns > 0 then
        defVal = math.max(0, math.floor(defVal * (1 - defender.armorBroken / 100)))
    end
    local dmg = math.floor(atkVal * atkVal / math.max(1, atkVal + defVal))
    dmg = math.max(1, dmg)
    local variance = math.floor(dmg * 0.1)
    dmg = dmg + math.random(-variance, variance)
    dmg = math.max(1, dmg)

    -- 主动技能伤害倍率
    local skillName = nil
    if skillId then
        local mul = GS.getSkillDmgMul(skillId)
        -- 距离加成（如狙击：每格距离+50%伤害）
        local sDef = GS.SKILL_DEFS[skillId]
        if sDef and sDef.distDmgBonusPerGrid then
            local dist = math.abs(attacker.x - defender.x) + math.abs(attacker.y - defender.y)
            mul = mul + math.max(0, dist - 1) * sDef.distDmgBonusPerGrid
        end
        dmg = math.floor(dmg * mul)
        dmg = math.max(1, dmg)
        -- 备用武器额外投掷：正常消耗MP，但不进入冷却
        GS.useSkill(skillId)
        if GS._spareWeaponFreeThrow then
            GS.skillCooldowns[skillId] = 0
        end
        skillName = sDef and sDef.name
        M.addSkillCastText(attacker.x, attacker.y, skillId)
        showPendingCastEffects(attacker.x, attacker.y, attacker)
    end

    -- 追身箭伤害倍率（走普攻流程但使用独立倍率）
    if attacker._chaseArrowDmgMul then
        dmg = math.floor(dmg * attacker._chaseArrowDmgMul)
        dmg = math.max(1, dmg)
    end

    -- 装备效果：神射手 — 远程普通攻击距离伤害加成（每格+X%）
    if not skillId and not attacker.isMonster then
        local distPctPerGrid = attacker.distDmgPctPerGrid or 0
        if distPctPerGrid > 0 then
            local dist = math.abs(attacker.x - defender.x) + math.abs(attacker.y - defender.y)
            if dist > 1 then
                local bonusPct = (dist - 1) * distPctPerGrid
                dmg = math.floor(dmg * (1 + bonusPct / 100))
                dmg = math.max(1, dmg)
            end
        end
    end

    -- 驯兽熟练：猎犬伤害+2%/级
    if attacker.isCompanion then
        local bpLv = GS.skillLevels["h_beast_prof"] or 0
        if bpLv > 0 then
            local bpDef = GS.SKILL_DEFS["h_beast_prof"]
            local bonusPct = (bpDef.houndDmgPctPerLv or 0) * bpLv
            dmg = math.floor(dmg * (1 + bonusPct / 100))
            dmg = math.max(1, dmg)
        end
    end

    -- 魅力加成：召唤物/同伴造成伤害 +1%/点
    if attacker.isCompanion then
        local ownerCha = GS.player and GS.player.cha or 0
        if ownerCha > 0 then
            dmg = math.floor(dmg * (1 + ownerCha / 100))
            dmg = math.max(1, dmg)
        end
    end

    -- 通用加成管线（百分比、元素熟练、标记），暴击延后到暴雨/破隐之后
    local skillDefForElem = skillId and GS.SKILL_DEFS[skillId]
    local dmgElement = skillDefForElem and skillDefForElem.element or nil
    -- 怪物普攻：使用怪物自身的元素属性
    if not dmgElement and attacker.isMonster and attacker.element then
        dmgElement = attacker.element
    end
    -- 小宙斯普攻：雷电属性伤害（受雷电伤害加成/雷电抗性影响）
    if isLittleZeusNormal and not dmgElement then
        dmgElement = "thunder"
    end
    dmg = applyDmgBonuses(attacker, defender, dmg, { element = dmgElement, noCrit = true, useMagic = useMagic })

    -- 默示录：技能伤害减免（仅对玩家使用技能时生效）
    if skillId and not attacker.isMonster and (attacker.skillDmgReduction or 0) > 0 then
        dmg = math.floor(dmg * (1 - attacker.skillDmgReduction / 100))
        dmg = math.max(0, dmg)
    end

    -- 幻影伤害加成：装备 illusionDmgPct 时幻影攻击额外伤害
    if attacker._phantomAttacking then
        local illusionPct = GS.player and GS.player.illusionDmgPct or 0
        if illusionPct > 0 then
            dmg = math.floor(dmg * (1 + illusionPct / 100))
            dmg = math.max(1, dmg)
        end
        -- 极影之形：所有幻影伤害加成
        local singlePct = GS.player and GS.player.illusionSingleDmgPct or 0
        if singlePct > 0 then
            dmg = math.floor(dmg * (1 + singlePct / 100))
            dmg = math.max(1, dmg)
        end
    end

    -- 元素抗性减伤：防御方对应元素抗性百分比降低伤害
    if dmgElement and not defender.isMonster then
        local resField = ELEMENT_RES_MAP[dmgElement]
        if resField then
            local resPct = math.min(defender[resField] or 0, 30)
            if resPct > 0 then
                dmg = math.max(1, math.floor(dmg * (1 - resPct / 100)))
            end
        end
    end

    -- 暴雨被动：同一回合对同一目标命中次数越多，伤害越高
    if not attacker.isMonster and not attacker.isCompanion then
        local srLv = GS.skillLevels["a_storm_rain"] or 0
        if srLv > 0 then
            local srDef = GS.SKILL_DEFS["a_storm_rain"]
            local incPct = (srDef.stormPctPerLv or 0.5) * srLv
            local hits = M.stormHitCounts[defender] or 0
            if hits > 0 then
                dmg = math.floor(dmg * (1 + hits * incPct / 100))
                dmg = math.max(1, dmg)
            end
            M.stormHitCounts[defender] = hits + 1
        end
    end

    -- 隐匿：隐身状态发动的第一下攻击伤害加成（5%/等级）
    if attacker._stealthBreaking then
        local stLv = GS.skillLevels["a_stealth"] or 0
        if stLv > 0 then
            local stDef = GS.SKILL_DEFS["a_stealth"]
            local bonusPct = (stDef.revealStrikeBase or 0) + (stDef.revealStrikePerLv or 5) * stLv
            dmg = math.floor(dmg * (1 + bonusPct / 100))
            M.addDamageText(attacker.x, attacker.y - 0.8, "破隐一击!", {200, 60, 160})
        end
        attacker._stealthBreaking = nil
    end

    -- 方向性攻击加成已在 applyDmgBonuses 中计算，此处仅获取方向供 rollCrit 使用
    local dirBonus = getDirectionalBonus(attacker, defender)

    -- 狂风：弹道类攻击伤害修正（顺风+15%，逆风-15%）
    if WE.isProjectileAttack(attacker, skillId, currentWeaponTag) then
        local windDmgMul = WE.getWindProjectileDmgMul(attacker.x, attacker.y, defender.x, defender.y)
        if windDmgMul ~= 1.0 then
            dmg = math.max(1, math.floor(dmg * windDmgMul))
        end
    end

    -- 集风袋：起风时所有伤害加成（仅玩家本体）
    if GS.isWindy and WE.isActive() and not attacker.isMonster and not attacker.isCompanion then
        local eb = GS.getEquipBonus and GS.getEquipBonus() or {}
        local windPct = eb.windDmgPct or 0
        if windPct > 0 then
            dmg = math.max(1, math.floor(dmg * (1 + windPct / 100)))
        end
    end

    -- 暴击判定（含方向暴击率加成）
    local isCrit
    dmg, isCrit = rollCrit(attacker, defender, dmg, dirBonus,
        { useMagic = useMagic, element = dmgElement,
          lzPhysRatio = _lzPhysRatio, lzMagRatio = _lzMagRatio })

    -- 狂血：未暴击的物理伤害惩罚（普通攻击）
    if not isCrit and not useMagic and not attacker.isMonster
       and (attacker.nonCritPhysPenalty or 0) ~= 0 then
        dmg = math.floor(dmg * (1 + attacker.nonCritPhysPenalty / 100))
        dmg = math.max(1, dmg)
    end


    -- 血屠狂怒叠层已移至 applyDamageAndCheck，此处无需重复处理

    -- 怕疼杰尼被动：必定格挡500伤害（物理+魔法），完全格挡背后攻击
    local jeniFullBlock = false
    if defender.defId == "tidal_boss_jeni" and defender.hp > 0 then
        local jeniDirBonus = getDirectionalBonus(attacker, defender)
        if jeniDirBonus == 2 then
            -- 背后攻击：完全格挡
            dmg = 0
            jeniFullBlock = true
            M.addDamageText(defender.x, defender.y - 0.5, "完全格挡!", {180, 220, 255})
        else
            -- 正面/侧面：固定格挡350
            if dmg > 0 then
                local blockAmt = math.min(dmg, 350)
                dmg = math.max(0, dmg - 350)
                M.addDamageText(defender.x, defender.y - 0.5, "格挡 -" .. blockAmt, {180, 220, 255})
            end
        end
    end

    -- 盾牌格挡判定（物理伤害100%格挡，魔法伤害30%格挡）
    local blocked = 0
    if not defender.isMonster and GS.equipment then
        local shield = GS.equipment["weapon_l"]
        if shield and shield.effects and shield.effects.block_chance then
            local enhLv = shield.enhanceLevel or 0
            local enhGain = enhLv > 0 and GS.getEnhanceGain(shield, enhLv) or {}
            local chance = shield.effects.block_chance  -- 格挡几率固定不变
            local amount = (shield.effects.block_amount or 1) + (enhGain.block_amount or 0)
            -- 盾牌熟练加成（战士 + 牧师）—— 白木胁差等 noShieldPassive 盾牌跳过
            if not shield.noShieldPassive then
                for _, spId in ipairs({"shield_prof", "p_shield_prof"}) do
                    local spLv = GS.skillLevels[spId] or 0
                    if spLv > 0 then
                        local spDef = GS.SKILL_DEFS[spId]
                        chance = chance + (spDef.blockChancePerLv or 0) * spLv / 100
                        amount = amount + (spDef.blockAmountPerLv or 0) * spLv
                    end
                end
                -- 盾牌专精加成（战士 + 牧师）：格挡概率 + 体质格挡伤害
                for _, smId in ipairs({"shield_master", "p_shield_master"}) do
                    local smLv = GS.skillLevels[smId] or 0
                    if smLv > 0 then
                        local smDef = GS.SKILL_DEFS[smId]
                        chance = chance + (smDef.shieldBlockChancePerLv or 0) * smLv / 100
                        local conVal = 0
                        if GS.player and GS.player.stats then
                            conVal = GS.player.stats.con or 0
                            local eqB = GS.getEquipBonus and GS.getEquipBonus() or {}
                            conVal = conVal + (eqB.con or 0)
                        end
                        local conRatio = (smDef.shieldBlockConRatioPerLv or 0.1) * smLv
                        amount = amount + math.floor(conVal * conRatio)
                    end
                end
            end
            -- 魔法伤害格挡效果降为30%
            if useMagic then
                amount = math.floor(amount * 0.3)
            end
            if math.random() < chance then
                blocked = amount
                dmg = math.max(1, dmg - blocked)
            end
        end
    end

    -- 双手持剑：普通攻击/连击命中后概率造成额外50%伤害（并入总伤害）
    local dualWieldTriggered = false
    if not skillId and not attacker.isMonster and not dodged then
        local dwLv = GS.skillLevels["dual_wield"] or 0
        if dwLv > 0 then
            local weaponR = GS.equipment and GS.equipment["weapon_r"]
            local weaponL = GS.equipment and GS.equipment["weapon_l"]
            if weaponR and weaponR.weaponTag == "单手剑" and not weaponL then
                local dwDef = GS.SKILL_DEFS["dual_wield"]
                local chance = dwLv * (dwDef.dualWieldExtraChancePerLv or 3)
                if math.random(1, 100) <= chance then
                    local extraDmg = math.max(1, math.floor(dmg * (dwDef.dualWieldExtraDmgMul or 0.5)))
                    dmg = dmg + extraDmg
                    dualWieldTriggered = true
                end
            end
        end
    end

    -- 深渊词缀：重击（17%概率额外造成17点固定伤害，可叠加层数提高概率和伤害）
    local heavyStrikeTriggered = false
    if not attacker.isMonster and not dodged then
        local hsCount = countAbyssAffix("heavy_strike")
        if hsCount > 0 then
            local hsChance = 17 * hsCount
            local hsExtraDmg = 17 * hsCount
            if math.random(1, 100) <= hsChance then
                dmg = dmg + hsExtraDmg
                heavyStrikeTriggered = true
            end
        end
    end

    -- 英雄之剑专属：50%概率重击，额外造成33点固定伤害（独立于深渊词缀系统）
    local heroHeavyStrikeTriggered = false
    if not attacker.isMonster and not dodged then
        local weaponR = GS.equipment and GS.equipment["weapon_r"]
        if weaponR and weaponR.templateId == "hero_sword" then
            if math.random(1, 100) <= 50 then
                dmg = dmg + 33
                heroHeavyStrikeTriggered = true
            end
        end
    end

    -- 火焰护盾：伤害减免
    local fireShieldActive = false
    if not defender.isMonster and GS.fireShieldTurns > 0 and GS.fireShieldReducePct > 0 then
        local reducedDmg = math.floor(dmg * GS.fireShieldReducePct / 100)
        dmg = math.max(1, dmg - reducedDmg)
        fireShieldActive = true
    end

    -- 冲锋怒吼：伤害减免
    if not defender.isMonster and (defender.chargeRoarTurns or 0) > 0 and (defender.chargeRoarReducePct or 0) > 0 then
        local roarReduced = math.floor(dmg * defender.chargeRoarReducePct / 100)
        dmg = math.max(1, dmg - roarReduced)
    end

    -- 魔法盾：部分伤害由 MP 抵扣
    local magicShieldAbsorbed = 0
    local magicShieldMpCost = 0
    if not defender.isMonster and GS.magicShieldActive and (defender.mp or 0) > 0 then
        local msDef = GS.SKILL_DEFS["m_magic_shield"]
        local msLv = GS.skillLevels["m_magic_shield"] or 0
        if msDef and msLv > 0 then
            local absorbPct = (msDef.magicShieldAbsorbBase or 5) + (msLv - 1) * (msDef.magicShieldAbsorbPerLv or 5)
            absorbPct = math.min(absorbPct, 50)
            -- 宇宙奥秘6件套：魔法盾吸收百分比翻倍
            local setB = GS.getSetBonus()
            if (setB.magicShieldDouble or 0) > 0 then
                absorbPct = math.min(absorbPct * 2, 100)
            end
            local ratio = (msDef.magicShieldRatioBase or 1.1) + (msLv - 1) * (msDef.magicShieldRatioPerLv or 0.1)
            -- 节能施法加成：每级提高魔法盾抵扣效率3%
            local matkUpLv = GS.skillLevels["m_matk_up"] or 0
            if matkUpLv > 0 then
                ratio = ratio + 0.03 * matkUpLv
            end
            local dmgToAbsorb = math.floor(dmg * absorbPct / 100)
            if dmgToAbsorb > 0 then
                local mpNeeded = math.floor(dmgToAbsorb / ratio + 0.5)
                local mpAvail = defender.mp
                if mpNeeded > mpAvail then
                    -- MP 不够全额抵扣，按可用 MP 部分抵扣
                    dmgToAbsorb = math.floor(mpAvail * ratio)
                    mpNeeded = mpAvail
                end
                if dmgToAbsorb > 0 and mpNeeded > 0 then
                    defender.mp = defender.mp - mpNeeded
                    dmg = math.max(0, dmg - dmgToAbsorb)
                    magicShieldAbsorbed = dmgToAbsorb
                    magicShieldMpCost = mpNeeded
                end
            end
        end
    end

    -- 装备效果：物理/魔法伤害减免（乘算递减：reducePct 越高，每点收益越低，永远不会到 100%）
    if not defender.isMonster then
        local reducePct = 0
        if useMagic then
            reducePct = reducePct + (defender.mDmgReduce or 0)
        else
            reducePct = reducePct + (defender.pDmgReduce or 0)
        end
        if reducePct > 0 then
            -- 乘算公式：实际伤害倍率 = 100 / (100 + reducePct)
            -- 例：reducePct=25 → 倍率 0.80（减免20%）；50 → 0.667（减免33%）；100 → 0.50（减免50%）
            dmg = math.max(1, math.floor(dmg * 100 / (100 + reducePct)))
        end
    end

    -- 山脉盾：远程攻击减伤（物理防御超过700的部分，每10点降低 rangedDefRate% 远程伤害，至多 rangedDefCap%）
    if not defender.isMonster and rangedStyle and (defender.rangedDefRate or 0) > 0 then
        local defOver = math.max(0, (defender.def or 0) - 700)
        if defOver > 0 then
            local segments = math.floor(defOver / 10)
            local reducePctRanged = math.min(segments * defender.rangedDefRate, defender.rangedDefCap or 20)
            if reducePctRanged > 0 then
                dmg = math.max(1, math.floor(dmg * (1 - reducePctRanged / 100)))
            end
        end
    end

    -- 魅力加成：召唤物/同伴受到伤害 -0.1%/点
    if defender.isCompanion then
        local ownerCha = GS.player and GS.player.cha or 0
        if ownerCha > 0 then
            local chaReduce = ownerCha * 0.1
            dmg = math.max(1, math.floor(dmg * (1 - chaReduce / 100)))
        end
    end

    -- 瞄准：射击时概率造成额外百分比伤害（合入本次攻击总伤害）
    if not attacker.isMonster and not attacker.isCompanion then
        local aimLv = GS.skillLevels["h_aim"] or 0
        if aimLv > 0 then
            local aimDef = GS.SKILL_DEFS["h_aim"]
            local aimChance = (aimDef.aimChanceBase or 12) + (aimDef.aimChancePerLv or 2) * aimLv
            if math.random(1, 100) <= aimChance then
                local pct = aimDef.aimDmgPct or 30
                local aimDmg = math.max(1, math.floor((attacker.atk or 0) * pct / 100))
                dmg = dmg + aimDmg
            end
        end
    end

    -- 不可知物凝视：每点感知+专注造成3点额外真实伤害（对猎犬无效）
    if attacker.defId == "tidal_boss_unknown" and not defender.isCompanion then
        local perFoc = (defender.per or 0) + (defender.foc or 0)
        if perFoc > 0 then
            local extraDmg = perFoc * 3
            dmg = dmg + extraDmg
            M.addDamageText(defender.x, defender.y - 0.8, "凝视 +" .. extraDmg, {180, 120, 255})
        end
    end

    -- 默示录：普攻伤害由 AOE 替代，不再对 defender 单独扣血
    local apocalypseReplace = false
    if not skillId and not attacker.isMonster and not attacker.isCompanion
       and (attacker.normalAtkMatkCoeff or 0) > 0 then
        apocalypseReplace = true
    end

    -- 偏斜：根据避开要害减伤（rollDodge 中设置的标记）
    if defender._deflectDmgReduce and dmg > 0 then
        dmg = math.max(1, math.floor(dmg * (1 - defender._deflectDmgReduce)))
        defender._deflectDmgReduce = nil
    end

    -- 幻影：每次受击只扣1点HP（不论实际伤害大小）
    if apocalypseReplace then
        -- 默示录替代普攻：不对 defender 扣血，由 applyApocalypseAoe 统一处理
    elseif defender.isPhantom then
        -- 暴怒史莱姆王：一击摧毁幻影分身
        local pDmg = (attacker and attacker.defId == "slime_king_enraged") and defender.hp or 1
        defender.hp = defender.hp - pDmg
        trackTrainingDamage(defender, pDmg)
        immortalGuard(defender, pDmg)
    else
        -- 饮血护甲值：先用护甲值抵扣伤害
        if defender == GS.player and (GS.bloodShield or 0) > 0 and dmg > 0 then
            local absorbed = math.min(GS.bloodShield, dmg)
            GS.bloodShield = GS.bloodShield - absorbed
            dmg = dmg - absorbed
            if absorbed > 0 then
                M.addDamageText(defender.x, defender.y + 0.3, "-" .. absorbed, {200, 180, 80})
            end
            -- 巴洛庄园飓风：护甲值被清空时标记待触发（扣血后再执行，见 performAttack 末尾）
            if GS.bloodShield <= 0 and (GS.player and (GS.player.derivStormDmgBonus or 0) > 0) then
                if (GS._armorClearHurricaneCount or 0) < 1 then
                    GS._armorClearHurricaneCount = 1
                    GS._pendingHurricane = true
                end
            end
        end
        defender.hp = defender.hp - dmg
        trackTrainingDamage(defender, dmg)
        immortalGuard(defender, dmg)
    end

    -- 满月：遭受致死伤害时，消耗一层满月BUFF，将伤害减少95%并恢复HP
    if defender == GS.player and defender.hp <= 0 and dmg > 0 then
        local fmList = defender._fullMoonStackList
        if fmList and #fmList > 0 then
            -- 移除剩余持续时间最小的那层（最大化剩余价值）
            local minIdx, minVal = 1, fmList[1]
            for si = 2, #fmList do
                if fmList[si] < minVal then
                    minIdx, minVal = si, fmList[si]
                end
            end
            table.remove(fmList, minIdx)
            defender._fullMoonStacks = #fmList
            local reducedDmg = math.max(1, math.floor(dmg * 0.05))
            local restored = dmg - reducedDmg
            defender.hp = defender.hp + restored
            dmg = reducedDmg
            M.addDamageText(defender.x, defender.y - 0.5, "满月护佑！", {200, 210, 255})
            if #fmList <= 0 then
                defender._fullMoonStackList = nil
                defender._fullMoonStacks = nil
                defender._fullMoonDodgeCount = nil
            end
        end
    end

    -- 怕疼杰尼被动：一次性受到2000+伤害陷入恐惧2回合（BOSS自身机制，不受英雄免疫影响）
    if defender.defId == "tidal_boss_jeni" and defender.hp > 0 and dmg >= 2000 then
        defender.feared = 2
        M.addDamageText(defender.x, defender.y - 1.0, "恐惧!", {200, 100, 255})
    end

    -- 异度信仰匕首/法杖/长弓：攻击有3%概率令目标陷入恐惧1回合（英雄单位免疫）
    if not attacker.isMonster and defender.isMonster and defender.hp > 0
       and not defender.feared and not defender.isTrainingDummy and not isHeroUnit(defender) then
        local wr = GS.equipment and GS.equipment["weapon_r"]
        if wr and (wr.id == "heresy_dagger" or wr.id == "heresy_staff" or wr.id == "heresy_bow") then
            if math.random(1, 100) <= 3 then
                defender.feared = 1
                M.addDamageText(defender.x, defender.y - 0.8, "恐惧!", {180, 80, 220})
            end
        end
    end

    -- 异度信仰披风：受到攻击有5%概率令攻击者陷入恐惧1回合
    if attacker.isMonster and not defender.isMonster and attacker.hp > 0
       and not attacker.feared then
        local cloakItem = GS.equipment and GS.equipment["cloak"]
        if cloakItem and cloakItem.id == "heresy_cloak" then
            if math.random(1, 100) <= 5 then
                attacker.feared = 1
                M.addDamageText(attacker.x, attacker.y - 0.8, "恐惧!", {180, 80, 220})
            end
        end
    end

    -- 不可知物凝视叠加：攻击使目标感知+专注各+7（最多100层，对猎犬无效）
    -- 通过 _gazePer/_gazeFoc 存储，recalcStats 时纳入主属性计算
    if attacker.defId == "tidal_boss_unknown" and not defender.isCompanion
       and defender.hp > 0 then
        local gaze = defender._unknownGaze or 0
        if gaze < 100 then
            defender._unknownGaze = gaze + 1
            defender._gazePer = (gaze + 1) * 7
            defender._gazeFoc = (gaze + 1) * 7
            GS.recalcStats(defender)
            M.addDamageText(defender.x, defender.y - 1.2, "凝视 ×" .. (gaze + 1), {180, 120, 255})
        end
    end

    -- 火焰护盾：对近战攻击者造成反伤（基于玩家 matk）
    if fireShieldActive and attacker.isMonster and attacker.hp > 0 then
        local dist = math.abs(attacker.x - defender.x) + math.abs(attacker.y - defender.y)
        if dist <= 1 then
            local reflectDmg = math.max(1, math.floor((GS.player.mAtk or 0) * GS.fireShieldReflectPct / 100))
            reflectDmg = applyElementBonus(reflectDmg, "fire")
            -- 蒸腾：火盾反伤（火属性）击中冻僵/冻结目标
            if attacker.chilled or (attacker.frozen and attacker.frozen > 0) then
                local burnSC = attacker.burnStacks and #attacker.burnStacks or 0
                local chillSC = M.getEffectiveChillStacks(attacker)
                reflectDmg = math.floor(reflectDmg * (1 + WE.getEvaporationBonus() * (math.max(1, burnSC) + chillSC)))
                attacker.chilled = nil
                attacker.chilledTurns = nil
                attacker.chillStacks = nil
                attacker.frozen = nil
                M.clearBurnDebuff(attacker)
                attacker._noElementDebuff = true  -- 蒸腾中和，跳过后续debuff施加
                M.addDamageText(attacker.x, attacker.y - 0.8, "蒸腾!", {255, 50, 50})
            end
            attacker.hp = attacker.hp - reflectDmg
            immortalGuard(attacker, reflectDmg)
            M.addDamageText(attacker.x, attacker.y, "" .. reflectDmg, {255, 120, 40})
            M.addBurnEffect(attacker.x, attacker.y)
            -- 火盾反伤致死：计入玩家击杀
            if attacker.hp <= 0 then
                attacker.hp = 0
                if attacker.isMonster then
                    M.processMonsterKill(defender, attacker)
                end
            end
            -- 火盾反伤施加灼伤debuff（叠层）
            if attacker.hp > 0 then
                if attacker._noElementDebuff then
                    attacker._noElementDebuff = nil  -- 蒸腾中和，不施加灼伤
                else
                    local newDur = 3 + WE.getBurnDurationMod()
                    M.applyBurnDebuff(attacker, GS.player.mAtk or 0, newDur)
                    local stacks = attacker.burnStacks and #attacker.burnStacks or 0
                    M.addDamageText(attacker.x, attacker.y - 0.5, "灼伤!" .. (stacks > 1 and (" x" .. stacks) or ""), {255, 120, 40})
                end
            end
        end
    end

    if magicShieldAbsorbed > 0 then
        M.addDamageText(defender.x, defender.y - 0.5, "-" .. magicShieldMpCost, {80, 160, 255})
    end

    if apocalypseReplace then
        -- 默示录替代普攻：跳过普攻伤害数字/格挡/受击闪烁（由 applyApocalypseAoe 统一处理）
    elseif blocked > 0 then
        M._damageTextStyle = "block"
        M.addDamageText(defender.x, defender.y - 0.5, "格挡！", {192, 192, 200})
        M.addDamageText(defender.x, defender.y, "" .. dmg, {255, 50, 50})
        M.playShieldBlockSound()
        -- 神佑被动：格挡后根据魔攻治疗自身（需要左手装备盾牌）
        local dgLv = GS.skillLevels["p_divine_grace"] or 0
        local dgWeaponL = GS.equipment and GS.equipment["weapon_l"]
        local dgHasShield = dgWeaponL and dgWeaponL.category == "盾牌"
        if dgLv > 0 and dgHasShield and defender.hp > 0 then
            local dgDef = GS.SKILL_DEFS["p_divine_grace"]
            local healPct = (dgDef.divineGraceHealPerLv or 1) * dgLv
            local heal = math.max(1, math.floor((defender.mAtk or 0) * healPct / 100))
            -- 治疗效果加成
            if (defender.healEffectPct or 0) > 0 then
                heal = math.floor(heal * (1 + defender.healEffectPct / 100))
            end
            local oldHp = defender.hp
            defender.hp = math.min(defender.hp + heal, defender.maxHp)
            local actualHeal = defender.hp - oldHp
            M.addDamageText(defender.x, defender.y - 0.5, "神佑+" .. heal, {255, 220, 100})
            M.addDivineGraceEffect(defender.x, defender.y)
            if not defender.isMonster then M.triggerRadianceDamage(heal) end
        end
        -- 深渊词缀：利刺（格挡时以玩家物防100%为攻击力，走完整伤害管线，必定命中，可叠加）
        -- 聚焦器：屏蔽利刺
        if not defender.isMonster and attacker and attacker.hp and attacker.hp > 0
           and defender.hp > 0
           and (defender.focuserDmgPer or 0) <= 0 then
            local thornsCount = countAbyssAffix("thorns")
            if thornsCount > 0 then
                -- 以玩家物防80%为atkVal，怪物物防为defVal，走标准伤害公式
                local tAtkVal = math.floor((defender.def or 0) * 0.8)
                local tDefVal = attacker.def or 0
                local thornsDmg = math.floor(tAtkVal * tAtkVal / math.max(1, tAtkVal + tDefVal))
                thornsDmg = math.max(1, thornsDmg)
                local thornsVar = math.floor(thornsDmg * 0.1)
                thornsDmg = thornsDmg + math.random(-thornsVar, thornsVar)
                thornsDmg = math.max(1, thornsDmg)
                -- 仅物理伤害提高 + 暴击，不走其他加成
                local physBonus = defender.physDmgBonus or 0
                if physBonus > 0 then
                    thornsDmg = math.floor(thornsDmg * (1 + physBonus / 100))
                    thornsDmg = math.max(1, thornsDmg)
                end
                local thornsIsCrit
                thornsDmg, thornsIsCrit = rollCrit(defender, attacker, thornsDmg, nil, {})
                -- 叠加词缀层数
                thornsDmg = math.floor(thornsDmg * thornsCount)
                thornsDmg = math.max(1, thornsDmg)
                attacker.hp = attacker.hp - thornsDmg
                immortalGuard(attacker, thornsDmg)
                trackTrainingDamage(attacker, thornsDmg)
                if thornsIsCrit then
                    M.addDamageText(attacker.x, attacker.y, thornsDmg .. "!", {255, 255, 255}, 1.5)
                    GS.setScreenShake(0.15, 2, 0)
                else
                    M.addDamageText(attacker.x, attacker.y, "" .. thornsDmg, {255, 255, 255})
                end
                M.addHurtFlash(attacker)
                -- 利刺伤害触发吸血（物理）
                M.applyLifesteal(defender, thornsDmg, false)
                if attacker.hp <= 0 then
                    attacker.hp = 0
                    if attacker.isMonster then M.processMonsterKill(defender, attacker) end
                end
            end
        end
        -- 装备效果：格挡回血
        if (defender.blockHeal or 0) > 0 and defender.hp > 0 then
            local healAmt = defender.blockHeal
            if (defender.healEffectPct or 0) > 0 then
                healAmt = math.floor(healAmt * (1 + defender.healEffectPct / 100))
            end
            local oldHp = defender.hp
            defender.hp = math.min(defender.hp + healAmt, defender.maxHp)
            -- 满血时也显示绿字和特效
            M.addDamageText(defender.x, defender.y, "+" .. healAmt, {100, 255, 100})
            M.addHealEffect(defender.x, defender.y, defender)
            if not defender.isMonster then M.triggerRadianceDamage(healAmt) end
        end
    else
        -- 根据技能元素属性决定颜色（玩家受伤强制红色）
        local dmgColor = {255, 255, 255}  -- 默认物理白色
        if defender == GS.player or defender.isHound then
            dmgColor = {255, 80, 80}
        elseif isLittleZeusNormal then
            dmgColor = {255, 220, 60}    -- 雷电黄（小宙斯普攻）
        elseif skillId then
            if skillId == "p_bless" or skillId == "p_exorcism" then
                dmgColor = {255, 220, 100}  -- 神圣暖金
            elseif skillId == "m_spark" or skillId == "m_fireball" or skillId == "m_meteor" or skillId == "m_fire_shield" then
                dmgColor = {255, 120, 40}   -- 火焰橙
            elseif skillId == "m_ice_spike" or skillId == "m_ice_ring" or skillId == "m_blizzard" or skillId == "m_ice_wall" then
                dmgColor = {100, 200, 255}   -- 冰冻蓝
            elseif skillId == "m_lightning" or skillId == "m_thunder" or skillId == "m_chain_light" or skillId == "m_thunder_cloud" then
                dmgColor = {255, 220, 60}    -- 雷电黄
            end
        end
        if isCrit then
            M.addDamageText(defender.x, defender.y, dmg .. "!", dmgColor, 1.5)
            -- 弹道类攻击：暴击震动延迟到弹道命中时触发
            if M._pendingProjectileHit then
                GS._pendingCritShake = true
            else
                GS.setScreenShake(0.15, 2, 0)
            end
        else
            M.addDamageText(defender.x, defender.y, "" .. dmg, dmgColor)
        end
    end
    if not apocalypseReplace then
        M.addHurtFlash(defender)
        -- 小宙斯混合伤害：按物理/魔法比例分别触发两种吸血
        if isLittleZeusNormal and dmg > 0 then
            local eb2 = GS.getEquipBonus and GS.getEquipBonus() or {}
            local pPct = (eb2.littleZeusPhysPct or 80) / 100
            local mPct = (eb2.littleZeusMagPct or 80) / 100
            local totalPct = pPct + mPct
            if totalPct > 0 then
                local physDmg = math.floor(dmg * pPct / totalPct)
                local magDmg  = dmg - physDmg
                if physDmg > 0 then M.applyLifesteal(attacker, physDmg, false) end
                if magDmg  > 0 then M.applyLifesteal(attacker, magDmg,  true)  end
            else
                M.applyLifesteal(attacker, dmg, useMagic)
            end
        else
            M.applyLifesteal(attacker, dmg, useMagic)
        end
        -- 羁绊链接：玩家/猎犬造成伤害时互相治疗
        M.applyBondLink(attacker, dmg)
    end

    -- 装备效果：受伤回血（受到伤害时治疗自身固定HP）
    if not defender.isMonster and (defender.onDamageTakenHeal or 0) > 0 and defender.hp > 0 and dmg > 0 and not blocked then
        local healAmt = defender.onDamageTakenHeal
        -- 治疗效果加成
        if (defender.healEffectPct or 0) > 0 then
            healAmt = math.floor(healAmt * (1 + defender.healEffectPct / 100))
        end
        local oldHp = defender.hp
        defender.hp = math.min(defender.hp + healAmt, defender.maxHp)
        if defender.hp > oldHp then
            M.addHealEffect(defender.x, defender.y, defender)
        end
        M.triggerRadianceDamage(healAmt)
    end

    -- 装备效果：受击反伤（受到攻击时对攻击者造成固定物理伤害）
    if not defender.isMonster and (defender.equipThorns or 0) > 0
       and attacker and attacker.hp and attacker.hp > 0 and attacker.isMonster then
        local tDmg = defender.equipThorns
        attacker.hp = attacker.hp - tDmg
        immortalGuard(attacker, tDmg)
        trackTrainingDamage(attacker, tDmg)
        M.addDamageText(attacker.x, attacker.y, "" .. tDmg, {255, 255, 255})
        M.addHurtFlash(attacker)
        if attacker.hp <= 0 then
            attacker.hp = 0
            if attacker.isMonster then M.processMonsterKill(defender, attacker) end
        end
    end

    -- 装备效果：命中回血（攻击命中时回复固定HP）
    if not attacker.isMonster and (attacker.onHitHeal or 0) > 0 and attacker.hp > 0 and dmg > 0 then
        local healAmt = attacker.onHitHeal
        if (attacker.healEffectPct or 0) > 0 then
            healAmt = math.floor(healAmt * (1 + attacker.healEffectPct / 100))
        end
        local oldHp = attacker.hp
        attacker.hp = math.min(attacker.hp + healAmt, attacker.maxHp)
        if attacker.hp > oldHp then
            M.addHealEffect(attacker.x, attacker.y, attacker)
        end
        M.triggerRadianceDamage(healAmt)
    end

    -- 装备效果：命中减防（攻击命中时降低目标防御，同一目标最多生效一次）
    if not attacker.isMonster and (attacker.onHitDefReduce or 0) > 0 and defender.hp > 0 and dmg > 0 then
        if not defender._defReducedBy then defender._defReducedBy = {} end
        local attackerId = attacker.unitId or "player"
        if not defender._defReducedBy[attackerId] then
            defender._defReducedBy[attackerId] = true
            local reduce = attacker.onHitDefReduce
            if useMagic then
                defender.mDef = math.max(0, (defender.mDef or 0) - reduce)
                defender.mdef = defender.mDef  -- 同步小写别名
            else
                defender.def = math.max(0, (defender.def or 0) - reduce)
            end
        end
    end

    -- 装备效果：魔伤回血（造成魔法伤害时回复伤害百分比的HP）
    if not attacker.isMonster and useMagic and (attacker.onMagDmgHeal or 0) > 0 and attacker.hp > 0 and dmg > 0 then
        local heal = math.max(1, math.floor(dmg * attacker.onMagDmgHeal / 100))
        if (attacker.healEffectPct or 0) > 0 then
            heal = math.floor(heal * (1 + attacker.healEffectPct / 100))
        end
        local oldHp = attacker.hp
        attacker.hp = math.min(attacker.hp + heal, attacker.maxHp)
        if attacker.hp > oldHp then
            M.addHealEffect(attacker.x, attacker.y, attacker)
        end
        M.triggerRadianceDamage(heal)
    end

    -- 攻击特效
    local rangedStyle2 = attacker.isMonster and (RANGED_MONSTER_IDS[attacker.defId] or attacker.affixRangedStyle)
    local atkCX2, atkCY2 = GS.unitCenterPos(attacker)
    if attacker._phantomPos then atkCX2, atkCY2 = attacker._phantomPos[1], attacker._phantomPos[2] end
    local defTX2, defTY2 = getDefenderEffectPos(attacker, defender)
    if rangedStyle2 == "bow" then
        local dihataStyle2 = isDihataUnit(attacker) and "stun_shot" or nil
        M.addAttackEffect(atkCX2, atkCY2, defTX2, defTY2, "弓", false, dihataStyle2)
    elseif rangedStyle2 == "ice_spike" then
        M.addAttackEffect(atkCX2, atkCY2, defTX2, defTY2, "法杖", false, nil, nil, "m_ice_spike", rangedStyle2)
    elseif rangedStyle2 == "lightning" or rangedStyle2 == "thunder" then
        M.addAttackEffect(atkCX2, atkCY2, defTX2, defTY2, "法杖", false, nil, nil, "m_lightning", rangedStyle2)
    elseif rangedStyle2 then
        M.addAttackEffect(atkCX2, atkCY2, defTX2, defTY2, "法杖", false, nil, nil, nil, rangedStyle2)
    elseif attacker.isMonster and attacker.weaponTag then
        M.addAttackEffect(atkCX2, atkCY2, defTX2, defTY2, attacker.weaponTag, false)
    elseif attacker.isMonster then
        M.addSlamAnim(attacker, defender.x, defender.y)
    else
        local wTag
        if attacker.isCompanion then
            wTag = attacker.weaponTag or "爪"
        else
            wTag = getPlayerWeaponTag()
        end
        -- 法术技能（useMagic）强制使用法杖弹道动画，即使装备的不是法杖
        if skillId and GS.SKILL_DEFS[skillId] and GS.SKILL_DEFS[skillId].useMagic then
            wTag = "法杖"
        end
        -- 强击系/祝福术/劲射技能使用专属特效
        if skillId and (skillId == "strike" or skillId == "sup_stk" or skillId == "mst_stk") then
            M.addStrikeEffect(atkCX2, atkCY2, defTX2, defTY2, skillId)
        elseif skillId and skillId == "p_bless" then
            M.addBlessEffect(atkCX2, atkCY2, defTX2, defTY2, false)
        elseif skillId and skillId == "p_exorcism" then
            M.addBlessEffect(atkCX2, atkCY2, defTX2, defTY2, true)
        elseif skillId and skillId == "h_power_shot" then
            M.addAttackEffect(atkCX2, atkCY2, defTX2, defTY2, wTag, attacker.isCompanion, "power_shot")
            GS.setScreenShake(0.3, 3, 0.28)
        elseif skillId and skillId == "h_stun_shot" then
            M.addAttackEffect(atkCX2, atkCY2, defTX2, defTY2, wTag, attacker.isCompanion, "stun_shot")
            GS.setScreenShake(0.25, 3, 0.25)
        elseif skillId and skillId == "h_snipe" then
            M.addAttackEffect(atkCX2, atkCY2, defTX2, defTY2, wTag, attacker.isCompanion, "snipe")
            GS.setScreenShake(0.35, 5, 0.25)
        elseif skillId and GS.SKILL_DEFS[skillId] and GS.SKILL_DEFS[skillId].throwSkill then
            M.addAttackEffect(atkCX2, atkCY2, defTX2, defTY2, wTag, attacker.isCompanion, "throw", skillId)
            local shakeIntensity = (skillId == "a_notice") and 5 or 3
            GS.setScreenShake(0.25, shakeIntensity, 0.28)
        elseif skillId and skillId == "m_thunder" then
            M._pendingProjectileHit = true  -- 延迟到雷电劈地时显示伤害
            M.addThunderStrikeEffect(defender.x, defender.y)
        else
            M.addAttackEffect(atkCX2, atkCY2, defTX2, defTY2, wTag, attacker.isCompanion, nil, nil, skillId)
        end
        playAttackSound(wTag)
    end

    -- 盾击晕眩判定（英雄单位免疫）
    if skillId and defender.hp > 0 and not isHeroUnit(defender) then
        local sDef = GS.SKILL_DEFS[skillId]
        if sDef and sDef.stunChance then
            local lv = GS.skillLevels[skillId] or 1
            local chance = sDef.stunChance + (sDef.stunChancePerLv or 0) * (lv - 1)
            if sDef.stunMaxChance then chance = math.min(chance, sDef.stunMaxChance) end
            -- 失感：每层冻僵+5%晕眩概率
            if defender._numbingPending then
                chance = chance + defender._numbingPending * 5
                defender._numbingPending = nil
            end
            if math.random(1, 100) <= chance then
                local newDur = sDef.stunDuration or 1
                if sDef.stunDurBP then
                    for bpLv, add in pairs(sDef.stunDurBP) do
                        if lv >= bpLv then newDur = newDur + add end
                    end
                end
                local oldDur = defender.stunned or 0
                defender.stunned = newDur
                if newDur > oldDur then
                    M.addDamageText(defender.x, defender.y - 0.5, "晕眩!", {255, 220, 60})
                end
            end
        end
    end

    -- 洗礼：牧师被动，普攻/祝福术/超度有概率击晕
    if defender.hp > 0 and not isHeroUnit(defender) and attacker == GS.player then
        local baptismLv = GS.skillLevels["p_baptism"] or 0
        if baptismLv > 0 and (skillId == nil or skillId == "p_bless" or skillId == "p_exorcism") then
            local chance = 2 * baptismLv
            if math.random(1, 100) <= chance then
                local newDur = 1
                local oldDur = defender.stunned or 0
                if newDur > oldDur then
                    defender.stunned = newDur
                    M.addDamageText(defender.x, defender.y - 0.5, "晕眩!", {255, 220, 60})
                end
            end
        end
    end

    -- 带毒投掷：命中后按概率施加中毒
    if skillId and defender.hp > 0 then
        local sDef = GS.SKILL_DEFS[skillId]
        if sDef and sDef.poisonPct then
            local slv = GS.skillLevels[skillId] or 1
            local chance = (sDef.poisonChance or 100) + (sDef.poisonChancePerLv or 0) * (slv - 1)
            chance = math.min(chance, 90)
            if skillId == "a_notice" or math.random(100) <= chance then
                local newDur = sDef.poisonDuration or 3
                local oldDur = defender.poisonTurns or 0
                local hadPoison = defender.poisoned and oldDur > 0
                defender.poisoned = sDef.poisonPct
                defender.poisonTurns = newDur
                defender.poisonApplierAtk = attacker.atk or 0
                if not hadPoison or newDur > oldDur then
                    M.addDamageText(defender.x, defender.y - 0.5, "中毒!", {180, 80, 220})
                end
            end
        end
    end

    -- 冰锥术：命中后施加冻僵debuff（移动距离-1）（英雄单位免疫）
    if skillId and skillId == "m_ice_spike" and defender.hp > 0 and defender.isMonster and not isHeroUnit(defender) then
        if defender._noElementDebuff then
            defender._noElementDebuff = nil  -- 蒸腾中和，不施加冻僵
        elseif WE.shouldUpgradeChillToFreeze() then
            local newDur = 1 + WE.getFreezeDurationMod()
            local oldDur = defender.frozen or 0
            defender.frozen = math.max(oldDur, newDur)
            if newDur > oldDur then
                M.addDamageText(defender.x, defender.y - 0.5, "冻结!", {100, 200, 255})
            end
        else
            local newDur = 2 + WE.getChillDurationMod()
            local oldDur = defender.chilledTurns or 0
            local hadChill = defender.chilled and oldDur > 0
            defender.chilled = 1
            defender.chilledTurns = newDur
            defender.chillStacks = math.min((defender.chillStacks or 0) + 1, M.CHILL_MAX_STACKS)
            if not hadChill then
                M.addDamageText(defender.x, defender.y - 0.5, "冻僵!", {100, 200, 255})
            elseif defender.chillStacks > 1 then
                M.addDamageText(defender.x, defender.y - 0.5, "冻僵 x" .. defender.chillStacks, {100, 200, 255})
            end
        end
    end

    -- 迪拉冰锥术：怪物命中玩家/友军时施加冻僵debuff（移动距离-1，2回合）
    if attacker.isMonster and attacker.defId == "goblin_boss_dila" and defender.hp > 0 and not defender.isMonster then
        local newDur = 2
        local oldDur = defender.chilledTurns or 0
        local hadChill = defender.chilled and oldDur > 0
        defender.chilled = 1
        defender.chilledTurns = newDur
        defender.chillStacks = math.min((defender.chillStacks or 0) + 1, M.CHILL_MAX_STACKS)
        if not hadChill then
            M.addDamageText(defender.x, defender.y - 0.5, "冻僵!", {100, 200, 255})
        elseif defender.chillStacks > 1 then
            M.addDamageText(defender.x, defender.y - 0.5, "冻僵 x" .. defender.chillStacks, {100, 200, 255})
        end
    end

    -- 火花术：命中后施加灼伤debuff（叠层，每回合受到施法者魔攻vs敌方魔防后30%的火属性伤害）
    if skillId and skillId == "m_spark" and defender.hp > 0 and defender.isMonster then
        if defender._noElementDebuff then
            defender._noElementDebuff = nil  -- 蒸腾中和，不施加灼伤
        else
            local newDur = 3 + WE.getBurnDurationMod()
            M.applyBurnDebuff(defender, attacker.mAtk or 0, newDur)
            local stacks = defender.burnStacks and #defender.burnStacks or 0
            M.addDamageText(defender.x, defender.y - 0.5, "灼伤!" .. (stacks > 1 and (" x" .. stacks) or ""), {255, 120, 40})
        end
    end

    -- 破甲投掷：命中后按概率降低目标物理防御
    if skillId and defender.hp > 0 then
        local sDef = GS.SKILL_DEFS[skillId]
        if sDef and sDef.armorBreakPct then
            local slv = GS.skillLevels[skillId] or 1
            local chance = (sDef.armorBreakChance or 100) + (sDef.armorBreakChancePerLv or 0) * (slv - 1)
            chance = math.min(chance, 90)
            if skillId == "a_notice" or math.random(100) <= chance then
                local newDur = sDef.armorBreakDuration or 3
                local oldDur = defender.armorBrokenTurns or 0
                local hadBreak = defender.armorBroken and oldDur > 0
                defender.armorBroken = sDef.armorBreakPct
                defender.armorBrokenTurns = newDur
                if not hadBreak or newDur > oldDur then
                    if skillId == "a_notice" then M._damageTextDelay = 0.3 end
                    M.addDamageText(defender.x, defender.y - 0.5, "破甲!", {220, 100, 60})
                    if skillId == "a_notice" then M._damageTextDelay = 0 end
                end
            end
        end
    end

    -- 预告信：命中后施加暴击伤害易伤
    if skillId and defender.hp > 0 then
        local sDef = GS.SKILL_DEFS[skillId]
        if sDef and sDef.noticeCritDmgPerLv then
            local slv = GS.skillLevels[skillId] or 1
            local newDur = (sDef.noticeCritDmgDuration or 3) + 1  -- +1 因为当回合结束会减1
            local oldDur = defender.noticeCritDmgTurns or 0
            local hadNotice = defender.noticeCritDmgBonus and oldDur > 0
            defender.noticeCritDmgBonus = sDef.noticeCritDmgPerLv * slv
            defender.noticeCritDmgTurns = newDur
            if not hadNotice or newDur > oldDur then
                M._damageTextDelay = 0.6
                M.addDamageText(defender.x, defender.y - 0.5, "暴伤易伤!", {220, 200, 100})
                M._damageTextDelay = 0
            end
        end
    end

    -- 野性：猎犬攻击时恐惧判定（训练假人、英雄单位免疫）
    if attacker.isCompanion and defender.isMonster and defender.hp > 0 and not defender.stunned and not defender.isTrainingDummy and not isHeroUnit(defender) then
        local wildLv = GS.skillLevels["h_wild"] or 0
        if wildLv > 0 then
            local wDef = GS.SKILL_DEFS["h_wild"]
            local fearChance = (wDef.wildFearBaseChance or 1) + (wDef.wildFearChancePerLv or 1) * (wildLv - 1)
            if math.random(1, 100) <= fearChance then
                local newDur = wDef.wildFearDuration or 1
                local oldDur = defender.feared or 0
                defender.feared = newDur
                if newDur > oldDur then
                    M.addDamageText(defender.x, defender.y - 0.5, "恐惧!", {180, 80, 220})
                end
            end
        end
    end

    -- 满弓击退判定（玩家本人攻击怪物时，需要装备弓；训练假人、英雄单位免疫）
    if attacker == GS.player and defender.isMonster and defender.hp > 0 and not defender.isTrainingDummy and not isHeroUnit(defender) then
        local fdLv = GS.skillLevels["h_full_draw"] or 0
        local weaponR = GS.equipment and GS.equipment["weapon_r"]
        local hasBow = weaponR and weaponR.weaponTag == "弓"
        if fdLv > 0 and hasBow then
            local fdDef = GS.SKILL_DEFS["h_full_draw"]
            local kbChance = (fdDef.fullDrawKBChancePerLv or 4) * fdLv
            if math.random(1, 100) <= kbChance then
                local kbDist = fdDef.fullDrawKBDist or 1
                -- 击退方向始终以玩家位置为基准，朝远离玩家的方向击退
                local dx = defender.x - GS.player.x
                local dy = defender.y - GS.player.y
                local kbDx, kbDy = 0, 0
                if math.abs(dx) >= math.abs(dy) then
                    kbDx = dx > 0 and 1 or -1
                else
                    kbDy = dy > 0 and 1 or -1
                end
                local newX, newY = defender.x, defender.y
                for step = 1, kbDist do
                    local tx, ty = newX + kbDx, newY + kbDy
                    if GS.isInBoard(tx, ty) and not GS.getUnitAt(tx, ty) then
                        newX, newY = tx, ty
                    else
                        break
                    end
                end
                if newX ~= defender.x or newY ~= defender.y then
                    local oldX, oldY = defender.x, defender.y
                    defender.x = newX
                    defender.y = newY
                    M.startMoveAnim(defender, oldX, oldY)
                    -- M.addDamageText(newX, newY, "击退!", {120, 200, 80})
                end
            end
        end
    end

    if defender.hp <= 0 then
        defender.hp = 0
        if defender.isMonster then
            M.processMonsterKill(attacker, defender)
        end
    end

    -- 元素反应：爆炸（雷电+灼伤 → 每层灼烧10% mAtk AOE伤害）
    if defender._explosionPending then
        local expData = defender._explosionPending
        defender._explosionPending = nil
        local expDmg = math.max(1, math.floor(expData.mAtk * 0.10 * expData.burnSC * WE.getExplosionMul()))
        -- 爆炸暴击判定（魔法暴击）
        local expCrit = false
        local critVal = (attacker.mCritRate or 0)
        local targetLv = math.max(1, defender.level or 1)
        local critChance = critVal > 0 and (critVal / (targetLv * 4)) or 0
        if critVal > 0 and not attacker.isMonster then
            local attackerLv = math.max(1, attacker.level or 1)
            critChance = math.min(critChance, attackerLv / 100)
        end
        if critChance > 0 and math.random() < critChance then
            local critDmgPct = attacker.mCritDmg or 25
            expDmg = math.floor(expDmg * (1 + critDmgPct / 100))
            expCrit = true
        end
        M.addDamageText(defender.x, defender.y - 0.8, "爆炸!", {255, 140, 0})
        -- 对目标自身造成爆炸伤害
        if defender.hp > 0 then
            defender.hp = defender.hp - expDmg
            immortalGuard(defender, expDmg)
            if expCrit then
                M.addDamageText(defender.x, defender.y, expDmg .. "!", {255, 140, 0}, 1.5)
                GS.setScreenShake(0.15, 2, M._damageTextDelay or 0)
            else
                M.addDamageText(defender.x, defender.y, "" .. expDmg, {255, 140, 0})
            end
            M.addHurtFlash(defender)
            if defender.hp <= 0 then
                defender.hp = 0
                if defender.isMonster then
                    M.processMonsterKill(attacker, defender)
                end
            end
        end
        -- 对周围1格内的其他怪物造成爆炸伤害
        local ts = GS.unitSize(defender)
        for _, m in ipairs(GS.monsters) do
            if m ~= defender and m.hp > 0 then
                local ms = GS.unitSize(m)
                local inRange = false
                for tdy = 0, ts - 1 do
                    if inRange then break end
                    for tdx = 0, ts - 1 do
                        if inRange then break end
                        for mdy = 0, ms - 1 do
                            if inRange then break end
                            for mdx = 0, ms - 1 do
                                if math.abs((defender.x + tdx) - (m.x + mdx)) + math.abs((defender.y + tdy) - (m.y + mdy)) <= 1 then
                                    inRange = true
                                end
                            end
                        end
                    end
                end
                if inRange then
                    m.hp = m.hp - expDmg
                    immortalGuard(m, expDmg)
                    if expCrit then
                        M.addDamageText(m.x, m.y, expDmg .. "!", {255, 140, 0}, 1.5)
                    else
                        M.addDamageText(m.x, m.y, "" .. expDmg, {255, 140, 0})
                    end
                    M.addHurtFlash(m)
                    if m.hp <= 0 then
                        m.hp = 0
                        if m.isMonster then
                            M.processMonsterKill(attacker, m)
                        end
                    end
                end
            end
        end
    end

    applyCleaveEffect(attacker, defender, dmg)
    applyMeleeSplash(attacker, defender, dmg)
    applyHoundSplash(attacker, defender, dmg)
    if not skillId then applyApocalypseAoe(attacker) end
    applyAffixChainLightning(attacker, defender, dmg)

    -- 装备效果：普攻触发技能（如王子冠冕：25%概率触发1级电击术）
    if not skillId and not attacker.isMonster and not attacker._normalAtkProcing
       and not attacker._phantomAttacking
       and defender.isMonster and defender.hp > 0 and dmg > 0 then
        if GS.equipment then
            for _, slotId in ipairs({"hat","necklace","ring","weapon_r","weapon_l","body","legs","feet","shoulder","gloves"}) do
                local slot = GS.equipment[slotId]
                if slot and slot.templateId then
                    local tpl = GS.itemTemplates[slot.templateId]
                    if tpl and tpl.normalAtkProc then
                        local proc = tpl.normalAtkProc
                        if math.random(1, 100) <= (proc.chance or 0) then
                            attacker._normalAtkProcing = true
                            -- 采用深渊闪电链的攻击力选取逻辑：取 max(atk, mAtk)
                            local pPhys = attacker.atk or 0
                            local pMag  = attacker.mAtk or 0
                            local useMag = pMag > pPhys
                            local procAtk = useMag and pMag or pPhys
                            local sDef = GS.SKILL_DEFS[proc.skillId]
                            if sDef then
                                local procLv = proc.level or 1
                                local mulBase = sDef.dmgMul or 1.0
                                local mulPerLv = sDef.dmgMulPerLv or 0
                                local mul = mulBase + (procLv - 1) * mulPerLv
                                local procDef = useMag and (defender.mdef or defender.def or 0) or (defender.def or 0)
                                local baseDmg = math.floor(procAtk * procAtk / math.max(1, procAtk + procDef))
                                baseDmg = math.max(1, baseDmg)
                                local procVar = math.floor(baseDmg * 0.1)
                                baseDmg = baseDmg + math.random(-procVar, procVar)
                                baseDmg = math.max(1, baseDmg)
                                baseDmg = math.floor(baseDmg * mul)
                                baseDmg = math.max(1, baseDmg)
                                local procFinalDmg, procCrit = applyDmgBonuses(attacker, defender, baseDmg,
                                    { element = sDef.element or "thunder", useMagic = useMag })
                                -- 伤害上限
                                if proc.dmgCap and procFinalDmg > proc.dmgCap then
                                    procFinalDmg = proc.dmgCap
                                end
                                -- 电击术视觉特效（与法杖电击术相同的闪电动画）
                                M.addAttackEffect(attacker.x, attacker.y, defender.x, defender.y,
                                    "法杖", false, nil, nil, "m_lightning", "lightning")
                                applyDamageAndCheck(attacker, defender, procFinalDmg, "", {255, 220, 60}, procCrit, true)
                                M.addDamageText(defender.x, defender.y - 0.5, "电击!", {255, 220, 60})
                                -- 击晕判定
                                if defender.hp > 0 and not defender.stunned and (sDef.stunChance or 0) > 0 then
                                    if math.random(1, 100) <= sDef.stunChance then
                                        defender.stunned = sDef.stunDuration or 1
                                        M.addDamageText(defender.x, defender.y - 0.5, "晕眩!", {255, 220, 60})
                                    end
                                end
                                GS.setScreenShake(0.15, 2, 0)
                            end
                            attacker._normalAtkProcing = nil
                            break  -- 每次普攻只触发一个装备的技能
                        end
                    end
                end
            end
        end
    end

    applyMonsterHitEffects(attacker, defender)

    -- 红龙幼龙 3x3 AOE 溅射：对主目标周围 3x3 范围内的其他友方单位造成相同伤害
    if attacker.isMonster and attacker.defId == "red_dragon_young" and dmg > 0 then
        local aoeCX, aoeCY = defender.x, defender.y
        -- 收集 3x3 范围内的其他友方目标（玩家/同伴）
        local splashTargets = {}
        -- 检查玩家
        if GS.player and GS.player.hp > 0 and GS.player ~= defender then
            if math.abs(GS.player.x - aoeCX) <= 1 and math.abs(GS.player.y - aoeCY) <= 1 then
                table.insert(splashTargets, GS.player)
            end
        end
        -- 检查同伴
        if GS.companions then
            for _, c in ipairs(GS.companions) do
                if c.hp and c.hp > 0 and c ~= defender then
                    local cs = GS.unitSize(c)
                    local inRange = false
                    for dy = 0, cs - 1 do
                        if inRange then break end
                        for dx = 0, cs - 1 do
                            if math.abs((c.x + dx) - aoeCX) <= 1 and math.abs((c.y + dy) - aoeCY) <= 1 then
                                inRange = true
                            end
                        end
                    end
                    if inRange then
                        table.insert(splashTargets, c)
                    end
                end
            end
        end
        -- 对溅射目标造成伤害
        for _, st in ipairs(splashTargets) do
            local splashDmg = dmg
            if st == GS.player then
                M.addDamageText(st.x, st.y, "" .. splashDmg, {255, 80, 80})
            else
                M.addDamageText(st.x, st.y, "" .. splashDmg, {255, 140, 40})
            end
            M.addHurtFlash(st)
            if st.isPhantom then
                -- 暴怒史莱姆王：一击摧毁幻影分身
                local pDmg = (attacker and attacker.defId == "slime_king_enraged") and st.hp or 1
                st.hp = st.hp - pDmg
                immortalGuard(st, pDmg)
            else
                st.hp = st.hp - splashDmg
                immortalGuard(st, splashDmg)
            end
            if st.hp <= 0 then
                st.hp = 0
            end
        end
    end
    -- 英雄法杖专属：普通攻击100%概率对目标施放1级电击术（独立于深渊词缀系统）
    if not skillId and not attacker.isMonster and not attacker.isCompanion
       and dmg > 0 and defender.isMonster and defender.hp > 0 then
        local weaponR = GS.equipment and GS.equipment["weapon_r"]
        if weaponR and weaponR.templateId == "hero_staff" then
            -- 1级电击术消耗5MP，MP不足时不触发
            local hlMpCost = 5
            if (attacker.mp or 0) >= hlMpCost and math.random(1, 100) <= 100 then
                attacker.mp = attacker.mp - hlMpCost
                -- 1级电击术：dmgMul=1.17, element=thunder, stunChance=7, stunDuration=1
                local mAtkVal = attacker.mAtk or 0
                local mDefVal = defender.mdef or defender.def or 0
                local hlBaseDmg = math.floor(mAtkVal * mAtkVal / math.max(1, mAtkVal + mDefVal))
                hlBaseDmg = math.max(1, hlBaseDmg)
                local hlVariance = math.floor(hlBaseDmg * 0.1)
                hlBaseDmg = hlBaseDmg + math.random(-hlVariance, hlVariance)
                hlBaseDmg = math.max(1, hlBaseDmg)
                hlBaseDmg = math.floor(hlBaseDmg * 1.17)
                hlBaseDmg = math.max(1, hlBaseDmg)
                local hlFinalDmg, hlIsCrit = applyDmgBonuses(attacker, defender, hlBaseDmg, { element = "thunder" })
                applyDamageAndCheck(attacker, defender, hlFinalDmg, "", {255, 220, 60}, hlIsCrit, true)
                -- 击晕判定（7%概率，1回合）
                if defender.hp > 0 and not defender.stunned then
                    local sChance = 7
                    -- 失感：每层冻僵+5%晕眩概率
                    if defender._numbingPending then
                        sChance = sChance + defender._numbingPending * 5
                        defender._numbingPending = nil
                    end
                    if math.random(1, 100) <= sChance then
                        defender.stunned = 1
                        M.addDamageText(defender.x, defender.y - 0.5, "晕眩!", {255, 220, 60})
                    end
                end
                -- 闪电视觉特效
                M.addAttackEffect(attacker.x, attacker.y, defender.x, defender.y, "法杖", false, nil, nil, "m_lightning", "lightning")
                -- 英雄晶球：电击术触发远程单体技能弹射+1
                if defender.hp > 0 and not M._abyssBouncing then
                    local weaponL_hl = GS.equipment and GS.equipment["weapon_l"]
                    if weaponL_hl and weaponL_hl.templateId == "hero_orb" then
                        table.insert(GS.pendingBounces, {
                            attacker = attacker,
                            startUnit = defender,
                            bounceCount = 1,
                            dmg = hlFinalDmg,
                            wTag = "法杖",
                            useMagic = true,
                            bounceIndex = 0,
                            prevUnit = defender,
                            _cooldown = 0.4,
                            bounceDmgInc = attacker.bounceDmgInc or 0,
                            skillId = "m_lightning",
                        })
                    end
                end
            end
        end
    end

    -- 英雄晶球专属：普通攻击命中时MP回复3点（独立于深渊词缀系统）
    if not skillId and not attacker.isMonster and not attacker.isCompanion
       and dmg > 0 then
        local weaponL_orb = GS.equipment and GS.equipment["weapon_l"]
        if weaponL_orb and weaponL_orb.templateId == "hero_orb" then
            local orbMpRegen = 3
            local oldMp = attacker.mp or 0
            attacker.mp = math.min(oldMp + orbMpRegen, attacker.maxMp or oldMp + orbMpRegen)
            if attacker.mp > oldMp then
                -- MP回复效果仍生效，仅移除浮动文本
            end
        end
    end

    -- 深渊词缀：远程普攻弹射（弓/法杖普攻命中后向3格内另一名敌军弹射，造成100%伤害，可叠加）
    if not skillId and not attacker.isMonster and not attacker.isCompanion
       and dmg > 0 and defender.isMonster then
        local wTag = getPlayerWeaponTag()
        if wTag == "弓" or wTag == "法杖" or isPlayerLittleZeus() then
            -- 聚焦器：仅屏蔽深渊词缀弹射，保留装备来源
            local bounceCount = 0
            if (attacker.focuserDmgPer or 0) <= 0 then
                bounceCount = bounceCount + countAbyssAffix("ranged_bounce")
            end
            -- 英雄箭袋独立计算弹射+1（不受聚焦器影响）
            local weaponL_bn = GS.equipment and GS.equipment["weapon_l"]
            if weaponL_bn and weaponL_bn.templateId == "hero_quiver" then bounceCount = bounceCount + 1 end
            if bounceCount > 0 and not M._abyssBouncing then
                -- 弹射延迟入队，初始冷却等散射箭矢命中后再开始弹射（避免弹道叠加）
                table.insert(GS.pendingBounces, {
                    attacker = attacker,
                    startUnit = defender,
                    bounceCount = bounceCount,
                    dmg = dmg,
                    wTag = wTag,
                    useMagic = useMagic,
                    bounceIndex = 0,       -- 当前已弹射次数
                    prevUnit = defender,    -- 当前弹射起点
                    _cooldown = 0.4,       -- 等原始箭矢命中后再弹射（0.7*0.55≈0.39s）
                    bounceDmgInc = attacker.bounceDmgInc or 0,  -- 弹射伤害每跳递增(%)
                })
            end
        end
    end

    -- 银鹿：远程单体技能弹射（使深渊弹射词缀对技能也生效，上限2次）
    if skillId and not attacker.isMonster and not attacker.isCompanion
       and dmg > 0 and defender.isMonster and not M._abyssBouncing then
        local hasRangeBounce = (attacker.rangeBounceCount or 0) > 0
        if hasRangeBounce then
            local sDef = GS.SKILL_DEFS[skillId]
            -- 仅远程单体技能：有 skillRange 或弓箭技能(reqWeaponTag=="弓")，且非 AOE/散射/连锁/地面目标/自施放
            if sDef and (sDef.skillRange or sDef.reqWeaponTag == "弓") and not sDef.aoe and not sDef.scatter
               and not sDef.groundTarget and not sDef.selfCast
               and not sDef.chainLightning and not sDef.thunderCloud
               and not sDef.iceRingAoe and not sDef.fireballAoe
               and not sDef.meteorAoe and not sDef.blizzardAoe
               and not sDef.iceWallSkill then
                -- 弹射次数 = min(银鹿档位上限, 深渊弹射词缀数量)
                local abyssBounces = countAbyssAffix("ranged_bounce")
                local rbCount = math.min(attacker.rangeBounceCount, abyssBounces)
                if rbCount > 0 then
                    local wTag = getPlayerWeaponTag()
                    local rbDmgMul = attacker.rangeBounceDmgMul or 100
                    local bounceDmg = math.max(1, math.floor(dmg * rbDmgMul / 100))
                    table.insert(GS.pendingBounces, {
                        attacker = attacker,
                        startUnit = defender,
                        bounceCount = rbCount,
                        dmg = bounceDmg,
                        wTag = wTag,
                        useMagic = useMagic,
                        bounceIndex = 0,
                        prevUnit = defender,
                        _cooldown = 0.4,
                        bounceDmgInc = attacker.bounceDmgInc or 0,
                        skillId = skillId,  -- 保留技能ID，弹射弹道使用原技能特效
                    })
                end
            end
        end
    end

    -- 英雄晶球：远程单体技能弹射+1（独立于深渊词缀系统，与银鹿可叠加）
    if skillId and not attacker.isMonster and not attacker.isCompanion
       and dmg > 0 and defender.isMonster and not M._abyssBouncing then
        local weaponL_hsb = GS.equipment and GS.equipment["weapon_l"]
        if weaponL_hsb and weaponL_hsb.templateId == "hero_orb" then
            local sDef = GS.SKILL_DEFS[skillId]
            -- 仅远程单体技能（与银鹿相同条件）
            if sDef and (sDef.skillRange or sDef.reqWeaponTag == "弓") and not sDef.aoe and not sDef.scatter
               and not sDef.groundTarget and not sDef.selfCast
               and not sDef.chainLightning and not sDef.thunderCloud
               and not sDef.iceRingAoe and not sDef.fireballAoe
               and not sDef.meteorAoe and not sDef.blizzardAoe
               and not sDef.iceWallSkill then
                local wTag = getPlayerWeaponTag()
                table.insert(GS.pendingBounces, {
                    attacker = attacker,
                    startUnit = defender,
                    bounceCount = 1,
                    dmg = dmg,
                    wTag = wTag,
                    useMagic = useMagic,
                    bounceIndex = 0,
                    prevUnit = defender,
                    _cooldown = 0.4,
                    bounceDmgInc = attacker.bounceDmgInc or 0,
                    skillId = skillId,
                })
            end
        end
    end

    -- 爆炸信：远程单体技能命中后在目标周围1格引发爆炸（不伤害目标本身）
    if skillId and not attacker.isMonster and not attacker.isCompanion
       and dmg > 0 and defender.isMonster then
        local explosionPct = attacker.rangedExplosionPct or 0
        if explosionPct > 0 then
            local sDef = GS.SKILL_DEFS[skillId]
            -- 仅远程单体技能（与银鹿相同条件）：有 skillRange 或弓箭技能
            if sDef and (sDef.skillRange or sDef.reqWeaponTag == "弓") and not sDef.aoe and not sDef.scatter
               and not sDef.groundTarget and not sDef.selfCast
               and not sDef.chainLightning and not sDef.thunderCloud
               and not sDef.iceRingAoe and not sDef.fireballAoe
               and not sDef.meteorAoe and not sDef.blizzardAoe
               and not sDef.iceWallSkill then
                local explosionDmg = math.max(1, math.floor(dmg * explosionPct / 100))
                -- 技能扩展词缀影响爆炸范围：基础1格，受 explosionAoeMax 上限截断
                local aoeMax = attacker.explosionAoeMax or 0
                local explosionRange = 1 + math.min(getAoeRangeBonus(), aoeMax)
                -- 爆炸特效
                M.addRangedExplosionEffect(defender.x, defender.y, explosionRange)
                -- 对目标周围 explosionRange 格（切比雪夫距离）的所有怪物造成伤害，不包括目标本身
                local dx, dy = defender.x, defender.y
                local explosionHit = {}
                for ox = -explosionRange, explosionRange do
                    for oy = -explosionRange, explosionRange do
                        if ox ~= 0 or oy ~= 0 then
                            local target = GS.getUnitAt(dx + ox, dy + oy)
                            if target and target.isMonster and target.hp > 0
                               and target ~= defender and not explosionHit[target] then
                                explosionHit[target] = true
                                target.hp = target.hp - explosionDmg
                                trackTrainingDamage(target, explosionDmg)
                                immortalGuard(target, explosionDmg)
                                M.addDamageText(target.x, target.y, "" .. explosionDmg, {255, 80, 40})
                                M.addHurtFlash(target)
                                M.applyLifesteal(attacker, explosionDmg)
                                if target.hp <= 0 then
                                    target.hp = 0
                                    M.processMonsterKill(attacker, target)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 装备效果：技能使用触发技能（如全知挂饰：33%概率对最近敌人使用冰锥术）
    if skillId and defender.isMonster and defender.hp >= 0 and dmg > 0 then
        trySkillUseProc(attacker, defender)
    end

  end -- if not dodged

    -- 幻影：普通攻击触发（未命中也可触发）
    if not skillId then applyPhantomAttack(attacker, defender) end

    -- 反击/复仇：闪避也能触发
    tryCounterAttack(attacker, defender, dodged)

    -- 标记目标：猎人攻击后标记敌人
    tryMarkTarget(attacker, defender)

    enqueueChainAttacks(attacker, defender, skillId)

    -- 清除弹道标记
    M._pendingProjectileHit = false
    M._currentProjectileId = nil

    -- 巴洛庄园飓风：护甲被打穿且本次攻击未致死，在此次攻击完全结算后立即触发
    if GS._pendingHurricane and defender == GS.player then
        GS._pendingHurricane = false
        if defender.hp > 0 then
            M._execDerivStorm(GS.player)
        end
    end
end


-- ====================================================================
-- 白木胁差：伤害类技能额外施展（排入 chainQueue）
-- ====================================================================

--- 判断技能是否为伤害类技能（排除 buff/自身施法/治疗/幻影/闪烁突袭）
local function isDamageSkill(skillId)
    if not skillId then return false end
    local def = GS.SKILL_DEFS[skillId]
    if not def then return false end
    if def.type ~= "active" then return false end
    -- buff / 自身施法 / 治疗 / 幻影 / 切换类 / 风暴 / 隐匿 / 专注 → 不是伤害技能
    if def.selfCast then return false end
    if def.restoreHeal then return false end
    if def.phantom then return false end
    if def.stormBuff then return false end
    if def.stealthBuff then return false end
    -- focusBuff 已改为被动，无需在此排除
    if def.fireShieldBuff then return false end
    if def.magicShieldToggle then return false end
    if def.flashAssault then return false end
    if def.sandBlind then return false end
    if def.blinkSkill then return false end
    if def.holyTree then return false end
    if def.iceWallSkill then return false end
    if isBlessingBuff and isBlessingBuff(def) then return false end
    return true
end

--- 将额外施展排入 chainQueue（白木胁差核心逻辑）
--- AOE 技能：在同一目标位置/方向重新施放
--- 单体技能：对同一目标重新施放
--- 地面目标技能：在同一地面坐标重新施放（传入 tx, ty）
--- 每次额外施展消耗 MP，不消耗吟唱段数
function M.enqueueExtraDmgSkillCasts(attacker, target, skillId, tx, ty)
    -- 仅玩家、非递归、有技能
    if not skillId then return end
    if M._extraDmgCasting then return end
    if not attacker or attacker ~= GS.player then return end

    local extraCast = attacker.extraDmgSkillCast or 0
    if extraCast <= 0 then return end
    if not isDamageSkill(skillId) then return end

    local def = GS.SKILL_DEFS[skillId]
    if not def then return end
    local mpCost = GS.getSkillMpCost(skillId)

    -- 判断是否为地面目标技能（陨石/火球/暴风雪/冰环/落雷等）
    local isGround = tx and ty and def.groundTarget

    -- 判断是否为 handler 路径（AOE 型技能）
    local usesHandler = false
    if not isGround then
        for _, entry in ipairs(SKILL_HANDLERS) do
            local matches = false
            if entry.match then
                matches = entry.match(def)
            elseif entry.field then
                matches = def[entry.field]
            end
            if matches then
                -- 只有非 buff 的 handler 才算 AOE/特殊伤害
                if not entry.noBreakStealth then
                    usesHandler = true
                end
                break
            end
        end
    end

    for i = 1, extraCast do
        table.insert(M.chainQueue, {
            action = function()
                -- MP 不足则跳过
                if mpCost > 0 and (GS.player.mp or 0) < mpCost then return end
                if mpCost > 0 then
                    GS.player.mp = GS.player.mp - mpCost
                end
                M._extraDmgCasting = true
                GS._skipUseSkill = true
                -- (不显示浮动文本)
                if isGround then
                    -- 地面目标技能：在同一地面坐标重新施放
                    M.executeGroundSkill(attacker, skillId, tx, ty)
                elseif usesHandler then
                    -- AOE / 特殊 Handler 技能：在同一目标位置重新施放
                    dispatchSkillHandler(attacker, target, skillId, def)
                else
                    -- 单体目标技能：对同一目标重新攻击
                    M.performAttack(attacker, target, skillId)
                end
                GS._skipUseSkill = nil
                M._extraDmgCasting = nil
            end,
        })
    end

    -- 确保 chainQueue 激活
    if #M.chainQueue > 0 and not M.chainActive then
        M.chainActive = true
        M.chainTimer = M.chainDelay
    end
end

-- ====================================================================
-- 统一玩家攻击入口（区分单体/AOE）
-- ====================================================================
function M.executePlayerAttack(attacker, target, skillId)
    -- 攻击时解除隐匿状态（buff类技能不在此解除）
    if GS.stealthActive and attacker == GS.player then
        local shouldBreak = true
        if skillId then
            local d = GS.SKILL_DEFS[skillId]
            if d and isNonBreakSkill(d) then shouldBreak = false end
        end
        if shouldBreak then
            attacker._stealthBreaking = true
            GS.stealthActive = false
            GS.stealthTurns = 0
        end
    end
    -- 记录玩家最近攻击的目标（驯兽熟练满级用）
    if target and target.isMonster then
        GS.lastPlayerTarget = target
    end
    -- 技能分发：注册表匹配
    if skillId then
        local def = GS.SKILL_DEFS[skillId]
        if def and dispatchSkillHandler(attacker, target, skillId, def) then
            -- 深渊词缀：Handler 派发法术多重施法（闪电链/雷云术等）
            if not M._multiCasting and attacker == GS.player and isMultiCastableRangedSkill(skillId) then
                local mcCount = getMultiCastCount()
                if mcCount > 0 then
                    local range = (def.skillRange or 3) + GS.getElementRangeBonus(skillId)
                    local extras = pickMultiCastTargets(attacker, {target}, mcCount, range)
                    if #extras > 0 then
                        local mpCost = GS.getSkillMpCost(skillId)
                        M._multiCasting = true
                        for _, et in ipairs(extras) do
                            if mpCost > 0 and (GS.player.mp or 0) < mpCost then break end
                            if mpCost > 0 then
                                GS.player.mp = GS.player.mp - mpCost
                            end
                            GS._skipUseSkill = true
                            dispatchSkillHandler(attacker, et, skillId, def)
                            GS._skipUseSkill = nil
                        end
                        M._multiCasting = nil
                    end
                end
            end
            -- ── 白木胁差：Handler 路径伤害技能额外施展 ──
            M.enqueueExtraDmgSkillCasts(attacker, target, skillId)
            -- ── skillUseProc：治疗/增益技能也触发（魔法盾开关除外） ──
            if not def.magicShieldToggle then
                trySkillUseProc(attacker, nil)
            end
            return
        end
    end
    -- 默认路径：普通攻击
    M.performAttack(attacker, target, skillId)
    -- 深渊词缀：远程普攻散射
    if not skillId then
        applyRangedScatter(attacker, target)
        -- 分心：普攻概率触发多重射
        tryDistraction(attacker, target)
    end
    -- 深渊词缀：单目标法术多重施法
    if not M._multiCasting and attacker == GS.player and isMultiCastableRangedSkill(skillId) then
        local mcCount = getMultiCastCount()
        if mcCount > 0 then
            local def = GS.SKILL_DEFS[skillId]
            local range = (def.skillRange or 3) + GS.getElementRangeBonus(skillId)
            local extras = pickMultiCastTargets(attacker, {target}, mcCount, range)
            if #extras > 0 then
                local mpCost = GS.getSkillMpCost(skillId)
                M._multiCasting = true
                for _, et in ipairs(extras) do
                    if mpCost > 0 and (GS.player.mp or 0) < mpCost then break end
                    if mpCost > 0 then
                        GS.player.mp = GS.player.mp - mpCost
                    end
                    M.performAttack(attacker, et, skillId)
                end
                M._multiCasting = nil
            end
        end
    end
    -- 备用武器：投掷技能后施加暴击伤害加成 + 记录目标用于免费武器投掷
    if skillId and attacker == GS.player then
        local sDef = GS.SKILL_DEFS[skillId]
        if sDef and sDef.throwSkill then
            local swLv = GS.skillLevels["a_spare_weapon"] or 0
            if swLv > 0 then
                local swDef = GS.SKILL_DEFS["a_spare_weapon"]
                -- 暴击伤害加成（1%/级），持续3回合BUFF
                local critBonus = (swDef.spareWeaponCritDmgPerLv or 1) * swLv
                attacker._spareWeaponCritDmg = critBonus
                attacker._spareWeaponCritTurns = 3 + 1  -- +1 因为当回合结束会递减1
                -- 免费武器投掷（5级1次，10级2次）
                local throws = 0
                if swDef.spareWeaponThrowsBP then
                    for bpLv, n in pairs(swDef.spareWeaponThrowsBP) do
                        if swLv >= bpLv and n > throws then throws = n end
                    end
                end
                if throws > 0 and target and target.hp > 0 then
                    attacker._spareWeaponTarget = target
                    attacker._spareWeaponThrows = throws
                end
            end
        end
    end
    -- 追身箭延迟到连击队列结束后触发（见 startChainIfNeeded / flushPendingChaseArrow）
    M._pendingChaseArrow = { attacker = attacker, target = target }

    -- ── 白木胁差：伤害类技能额外施展（chainQueue 延迟） ──
    M.enqueueExtraDmgSkillCasts(attacker, target, skillId)
end

--- 追身箭：攻击回合结束后对主目标额外射出一支箭矢
--- 走 performAttack 普攻流程，自动享受散射、弹射、闪电链
--- skillId=nil（普攻），银鹿和爆炸信不会触发（它们要求 skillId 存在）
function M.triggerChaseArrow(attacker, target)
    -- 只有玩家本人触发（猎犬不触发）
    if not attacker or attacker.isMonster or attacker.isCompanion then return end
    local lv = GS.skillLevels["h_chase_arrow"] or 0
    if lv <= 0 then return end
    -- 主目标已死亡时，转火到攻击范围内最近的存活敌人
    if not target or target.hp <= 0 then
        local atkRange = attacker.atkRange or 1
        local bestDist = math.huge
        local bestTarget = nil
        for _, m in ipairs(GS.monsters) do
            if m.hp > 0 then
                local dist = GS.manhattanToUnit(attacker.x, attacker.y, m)
                if dist <= atkRange and dist < bestDist then
                    bestDist = dist
                    bestTarget = m
                end
            end
        end
        target = bestTarget
        if not target then return end
    end
    local def = GS.SKILL_DEFS["h_chase_arrow"]
    if not def then return end
    local mul = (def.chaseDmgMul or 0.55) + (def.chaseDmgMulPerLv or 0.05) * (lv - 1)
    -- 设置追身箭伤害倍率（performAttack 内部读取并应用）
    attacker._chaseArrowDmgMul = mul
    -- 阻止追身箭触发攻速连击/双持/二连击，防止攻击次数膨胀
    local savedAtkSpeed = attacker._atkSpeedChaining
    local savedDualDagger = attacker._dualDaggerChaining
    local savedDoubleStrike = attacker._doubleStrikeChaining
    attacker._atkSpeedChaining = true
    attacker._dualDaggerChaining = true
    attacker._doubleStrikeChaining = true
    -- 走普攻流程：自动享受弹射、闪电链
    M.performAttack(attacker, target, nil)
    -- 深渊词缀：远程普攻散射（散射目标也带追身箭倍率）
    applyRangedScatter(attacker, target)
    -- 清理
    attacker._chaseArrowDmgMul = nil
    attacker._atkSpeedChaining = savedAtkSpeed
    attacker._dualDaggerChaining = savedDualDagger
    attacker._doubleStrikeChaining = savedDoubleStrike
end

--- 衍生飓风入队：延迟执行，让玩家看清攻击层次
function M.queueDerivStorm(attacker)
    local lv = GS.skillLevels["deriv_storm"] or 0
    if lv <= 0 then return end
    table.insert(M.chainQueue, {
        action = function() M._execDerivStorm(attacker) end,
    })
    if not M.chainActive then
        M.chainActive = true
        M.chainTimer = M.chainDelay
    end
end

--- 衍生飓风：攻击后对周围敌人造成溅射伤害（走统一伤害管线）
function M._execDerivStorm(attacker)
    local lv = GS.skillLevels["deriv_storm"] or 0
    if lv <= 0 then return end
    -- 触发者已死亡（本回合更早的攻击已将HP打至≤0但死亡判定尚未执行）：
    -- 跳过飓风，防止吸血将负血拉回绕过死亡判定
    if not attacker or attacker.hp <= 0 then return end
    local sDef = GS.SKILL_DEFS["deriv_storm"]
    if not sDef then return end
    local mul = ((sDef.derivBasePct or 33) + (sDef.derivPctPerLv or 3) * (lv - 1)) / 100
    -- 巴洛庄园飓风：衍生飓风伤害倍率提高
    mul = mul + (attacker.derivStormDmgBonus or 0) / 100
    local whirlRange = 1 + getAoeRangeBonus()
    local hit = false
    forEachAdjacentMonster(attacker, function(m)
        local dmg, isCrit = calcSkillDamage(attacker, m, { mul = mul, skillId = "deriv_storm" })
        applyDamageAndCheck(attacker, m, dmg, "", {255, 255, 255}, isCrit)
        hit = true
    end, whirlRange)
    if hit then
        M.addWhirlwindEffect(attacker.x, attacker.y, whirlRange)
        M.playWhirlwindSound()
    end
end

-- ====================================================================
-- 风暴旋风斩：免费触发一次旋风斩（使用旋风斩的伤害倍率）
-- ====================================================================
function M.triggerStormWhirlwind(attacker)
    if not attacker or attacker.hp <= 0 then return end
    local whirlLv = GS.skillLevels["whirlwind"] or 0
    if whirlLv <= 0 then return end
    local whirlDef = GS.SKILL_DEFS["whirlwind"]
    if not whirlDef then return end
    local mul = GS.getSkillDmgMul("whirlwind")
    local whirlRange = 1 + getAoeRangeBonus()

    local hit = false
    forEachAdjacentMonster(attacker, function(m)
        if rollDodge(attacker, m, "whirlwind") then
            M.addDamageText(m.x, m.y, "Miss", {255, 255, 255})
        else
            local dmg, isCrit = calcSkillDamage(attacker, m, { mul = mul, skillId = "whirlwind" })
            applyDamageAndCheck(attacker, m, dmg, "", {255, 255, 255}, isCrit)
        end
        hit = true
    end, whirlRange)
    if hit then
        M.addWhirlwindEffect(attacker.x, attacker.y, whirlRange)
        M.playWhirlwindSound()
        GS.setScreenShake(0.25, 2, 0)
    end
    -- 千军令：风暴旋风斩也触发幻影
    M.triggerWhirlPhantoms(attacker)
end


-- ====================================================================
-- 千军令：旋风斩触发幻影旋风斩
-- 在玩家使用旋风斩（手动或风暴触发）后，额外触发 N 次幻影旋风斩
-- 幻影旋风斩使用千军令的独立倍率（whirlPhantomMul%）
-- ====================================================================
function M.triggerWhirlPhantoms(attacker)
    if not attacker or attacker.hp <= 0 then return end
    if attacker._whirlPhantoming then return end
    local pCap = attacker.whirlPhantomCount or 0
    if pCap <= 0 then return end
    -- 聚焦器：仅屏蔽深渊词缀幻影数，保留装备/技能来源
    local phantomCount = 0
    if (attacker.focuserDmgPer or 0) <= 0 then
        phantomCount = phantomCount + countAbyssAffix("melee_phantom")
    end
    local eb = GS.getEquipBonus and GS.getEquipBonus() or {}
    phantomCount = phantomCount + (eb.heroPhantom or 0)
    if (GS.skillLevels["a_moon_shadow"] or 0) >= GS.SKILL_MAX_LEVEL then
        phantomCount = phantomCount + 1
    end
    local pCount = math.min(phantomCount, pCap)
    if pCount <= 0 then return end
    local pMulPct = attacker.whirlPhantomMul or 60

    local whirlLv = GS.skillLevels["whirlwind"] or 0
    if whirlLv <= 0 then return end
    local whirlDef = GS.SKILL_DEFS["whirlwind"]
    if not whirlDef then return end

    -- 幻影倍率 = 旋风斩完整倍率（含强化被动加成） × (whirlPhantomMul / 100)
    local fullMul = GS.getSkillDmgMul("whirlwind")
    local phantomMul = fullMul * pMulPct / 100
    local whirlRange = 1 + getAoeRangeBonus()

    -- 按标准幻影规则：在周围敌人背后生成幻影，以幻影位置为中心施展旋风斩
    local targets = pickPhantomTargets(attacker, pCount, 4)
    if #targets == 0 then return end
    -- 极影之形：当幻影数量 > 目标数量时，多余幻影可重复攻击已有目标
    local illusionSingleExtra = attacker.illusionSingleExtra or 0
    if illusionSingleExtra > 0 and #targets < pCount then
        local uniqueCount = #targets
        local extraSlots = math.min(pCount - uniqueCount, uniqueCount * illusionSingleExtra)
        for i = 1, extraSlots do
            targets[#targets + 1] = targets[((i - 1) % uniqueCount) + 1]
        end
    end

    attacker._whirlPhantoming = true

    -- 朝向 → 背后偏移
    local behindOffset = {
        up    = { 0,  1},
        down  = { 0, -1},
        left  = { 1,  0},
        right = {-1,  0},
    }

    for _, target in ipairs(targets) do
        -- 计算幻影位置：目标背后
        local tcx, tcy = GS.unitCenterPos(target)
        local ts = GS.unitSize(target)
        local phantomX, phantomY
        local facing = target.facing
        if facing and behindOffset[facing] then
            local off = behindOffset[facing]
            -- size>1 时沿边缘展开多个候选格，选第一个未被占用的
            local candidates = {}
            if off[1] ~= 0 and off[2] == 0 then
                local px = off[1] > 0 and (target.x + ts) or (target.x - 1)
                for dy = 0, ts - 1 do candidates[#candidates + 1] = { px, target.y + dy } end
            elseif off[2] ~= 0 and off[1] == 0 then
                local py = off[2] > 0 and (target.y + ts) or (target.y - 1)
                for dx = 0, ts - 1 do candidates[#candidates + 1] = { target.x + dx, py } end
            end
            phantomX, phantomY = candidates[1][1], candidates[1][2]
            for _, c in ipairs(candidates) do
                if c[1] ~= attacker.x or c[2] ~= attacker.y then
                    phantomX, phantomY = c[1], c[2]
                    break
                end
            end
        else
            local dirX = tcx - attacker.x
            local dirY = tcy - attacker.y
            local candidates = {}
            if math.abs(dirX) >= math.abs(dirY) then
                local behindX = dirX > 0 and (target.x + ts) or (target.x - 1)
                for dy = 0, ts - 1 do candidates[#candidates + 1] = { behindX, target.y + dy } end
            else
                local behindY = dirY > 0 and (target.y + ts) or (target.y - 1)
                for dx = 0, ts - 1 do candidates[#candidates + 1] = { target.x + dx, behindY } end
            end
            phantomX, phantomY = candidates[1][1], candidates[1][2]
            for _, c in ipairs(candidates) do
                if c[1] ~= attacker.x or c[2] ~= attacker.y then
                    phantomX, phantomY = c[1], c[2]
                    break
                end
            end
        end

        -- 添加幻影出现特效
        M.addPhantomAttackEffect(phantomX, phantomY, math.floor(tcx), math.floor(tcy), "单手剑")

        -- 以幻影位置为中心施展旋风斩AOE
        local hit = false
        forEachAdjacentMonster({x = phantomX, y = phantomY}, function(m)
            if rollDodge(attacker, m, "whirlwind") then
                M.addDamageText(m.x, m.y, "Miss", {255, 255, 255})
            else
                local dmg, isCrit = calcSkillDamage(attacker, m, { mul = phantomMul, skillId = "whirlwind" })
                applyDamageAndCheck(attacker, m, dmg, "", {200, 180, 255}, isCrit)
            end
            hit = true
        end, whirlRange)
        if hit then
            M.addWhirlwindEffect(phantomX, phantomY, whirlRange)
        end
    end
    attacker._whirlPhantoming = nil
end

-- ============================================================
-- 桥接：将子模块需要的 local 函数暴露到 M 上
-- ============================================================
M._inCircleRange          = inCircleRange
M._calcSkillDamage        = calcSkillDamage
M._applyDamageAndCheck    = applyDamageAndCheck
M._forEachAdjacentMonster = forEachAdjacentMonster
M._getPlayerWeaponTag     = getPlayerWeaponTag
M._applyElementBonus      = applyElementBonus
M._tickBlessingBuffs      = tickBlessingBuffs
M._isHeroUnit             = isHeroUnit
M._playAttackSound        = playAttackSound
M._tryMarkTarget          = tryMarkTarget
M._getDirectionalBonus    = getDirectionalBonus
M._getAoeRangeBonus       = getAoeRangeBonus
M._rollDodge              = rollDodge
M._applyRageBuff          = applyRageBuff
M._isEnragedSlime         = isEnragedSlime

-- ============================================================
-- 冻僵叠层系统：最多 5 层，仅影响蒸腾伤害计算
-- ============================================================
M.CHILL_MAX_STACKS = 5

--- 获取单位的有效冻僵层数（用于蒸腾伤害计算）
--- 冻结状态下层数翻倍
---@param unit table 目标单位
---@return number 有效冻僵层数
function M.getEffectiveChillStacks(unit)
    local sc = unit.chillStacks or 0
    -- 有冻僵/冻结但无层数记录时保底1层
    if sc == 0 and (unit.chilled or (unit.frozen and unit.frozen > 0)) then
        sc = 1
    end
    -- 冻结状态层数翻倍
    if unit.frozen and unit.frozen > 0 then
        sc = sc * 2
    end
    return sc
end

--- 清除冻僵叠层
---@param unit table 目标单位
function M.clearChillStacks(unit)
    unit.chillStacks = nil
end

-- ============================================================
-- 灼伤叠层系统：最多 15 层，每层独立持续时间和魔攻快照
-- ============================================================
M.BURN_MAX_STACKS = 15

--- 为单位施加一层灼伤 debuff
---@param unit table 目标单位
---@param mAtk number 施法者魔攻（快照）
---@param duration number 持续回合数
function M.applyBurnDebuff(unit, mAtk, duration)
    if not unit or unit.hp <= 0 then return end
    if not unit.burnStacks then unit.burnStacks = {} end
    if #unit.burnStacks < M.BURN_MAX_STACKS then
        unit.burnStacks[#unit.burnStacks + 1] = { turns = duration, mAtk = mAtk }
    else
        -- 已满 15 层：替换最弱的一层（魔攻最低）
        local minIdx, minAtk = 1, unit.burnStacks[1].mAtk
        for si = 2, #unit.burnStacks do
            if unit.burnStacks[si].mAtk < minAtk then
                minIdx = si
                minAtk = unit.burnStacks[si].mAtk
            end
        end
        if mAtk > minAtk then
            unit.burnStacks[minIdx] = { turns = duration, mAtk = mAtk }
        end
    end
    unit.burned = true
end

--- 清除单位所有灼伤状态
---@param unit table 目标单位
function M.clearBurnDebuff(unit)
    unit.burned = nil
    unit.burnedTurns = nil   -- 兼容旧字段
    unit.burnedMAtk = nil    -- 兼容旧字段
    unit.burnStacks = nil
end

-- ============================================================
-- 子模块挂载
-- ============================================================
--- 并行处理所有弹射链：每帧所有链各推进一跳，散射多目标的弹射同时飞行
--- _abyssBouncing 防止递归创建新链
function M.processPendingBounces()
    if #GS.pendingBounces == 0 then return end

    local dt = GS.dt or 0.016
    local toRemove = {}

    for i, b in ipairs(GS.pendingBounces) do
        -- 攻击者已死亡则标记移除
        if not b.attacker or b.attacker.hp <= 0 then
            toRemove[#toRemove + 1] = i
            goto continueBounce
        end

        -- 冷却计时
        if b._cooldown and b._cooldown > 0 then
            b._cooldown = b._cooldown - dt
            goto continueBounce
        end

        b.bounceIndex = b.bounceIndex + 1
        do
            local prevUnit = b.prevUnit

            -- 从上一个被弹射目标的3格范围内找最近的怪物
            local bestTarget, bestDist = nil, 999
            for _, m in ipairs(GS.monsters) do
                if m.hp > 0 and m ~= prevUnit then
                    local dist = math.abs(m.x - prevUnit.x) + math.abs(m.y - prevUnit.y)
                    if dist <= 3 and dist < bestDist then
                        bestDist = dist
                        bestTarget = m
                    end
                end
            end

            if not bestTarget then
                toRemove[#toRemove + 1] = i
                goto continueBounce
            end

            local bSrcX, bSrcY = GS.unitCenterPos(prevUnit)
            local bDstX, bDstY = GS.unitCenterPos(bestTarget)

            -- 弹道特效：弓箭/法球飞行到目标后触发伤害
            M._currentProjectileId = nil
            M._pendingProjectileHit = true

            -- 银鹿技能弹射：使用原技能的弹道特效，而非普攻弹道
            if b.skillId then
                local sid = b.skillId
                if sid == "h_power_shot" then
                    M.addAttackEffect(bSrcX, bSrcY, bDstX, bDstY, b.wTag, false, "power_shot")
                elseif sid == "h_stun_shot" then
                    M.addAttackEffect(bSrcX, bSrcY, bDstX, bDstY, b.wTag, false, "stun_shot")
                elseif sid == "h_snipe" then
                    M.addAttackEffect(bSrcX, bSrcY, bDstX, bDstY, b.wTag, false, "snipe")
                elseif GS.SKILL_DEFS[sid] and GS.SKILL_DEFS[sid].throwSkill then
                    M.addAttackEffect(bSrcX, bSrcY, bDstX, bDstY, b.wTag, false, "throw", sid)
                else
                    M.addAttackEffect(bSrcX, bSrcY, bDstX, bDstY, b.wTag, false, nil, nil, sid)
                end
            else
                M.addAttackEffect(bSrcX, bSrcY, bDstX, bDstY, b.wTag, false)
            end
            local lastFx = GS.attackEffects[#GS.attackEffects]
            if lastFx then
                lastFx.duration = 0.35
            end

            -- 弹射伤害递增（如装备"华尔兹"，每跳伤害按 bounceDmgInc% 递乘）
            if (b.bounceDmgInc or 0) > 0 then
                b.dmg = math.floor(b.dmg * (1 + b.bounceDmgInc / 100))
            end
            -- 弹射伤害文字颜色：有技能时使用技能元素颜色，否则白色
            local bounceColor = {255, 255, 255}
            if b.skillId then
                local bsDef = GS.SKILL_DEFS[b.skillId]
                if bsDef and bsDef.col then bounceColor = bsDef.col end
            end
            M._abyssBouncing = true
            applyDamageAndCheck(b.attacker, bestTarget, b.dmg, "", bounceColor, nil, b.useMagic)
            M._abyssBouncing = false

            -- 银鹿技能弹射：施加技能附加效果（晕眩除外）
            if b.skillId and bestTarget.hp > 0 then
                local bsDef = GS.SKILL_DEFS[b.skillId]
                if bsDef then
                    -- 中毒（带毒投掷 a_poison_throw、预告信 a_notice）
                    if bsDef.poisonPct then
                        local slv = GS.skillLevels[b.skillId] or 1
                        local chance = (bsDef.poisonChance or 100) + (bsDef.poisonChancePerLv or 0) * (slv - 1)
                        chance = math.min(chance, 90)
                        if b.skillId == "a_notice" or math.random(100) <= chance then
                            local newDur = bsDef.poisonDuration or 3
                            local oldDur = bestTarget.poisonTurns or 0
                            local hadPoison = bestTarget.poisoned and oldDur > 0
                            bestTarget.poisoned = bsDef.poisonPct
                            bestTarget.poisonTurns = newDur
                            bestTarget.poisonApplierAtk = b.attacker.atk or 0
                            if not hadPoison or newDur > oldDur then
                                M.addDamageText(bestTarget.x, bestTarget.y - 0.5, "中毒!", {180, 80, 220})
                            end
                        end
                    end
                    -- 冻僵/冻结（冰锥术 m_ice_spike）
                    if b.skillId == "m_ice_spike" and bestTarget.isMonster and not isHeroUnit(bestTarget) then
                        if bestTarget._noElementDebuff then
                            bestTarget._noElementDebuff = nil
                        elseif WE.shouldUpgradeChillToFreeze() then
                            local newDur = 1 + WE.getFreezeDurationMod()
                            local oldDur = bestTarget.frozen or 0
                            bestTarget.frozen = math.max(oldDur, newDur)
                            if newDur > oldDur then
                                M.addDamageText(bestTarget.x, bestTarget.y - 0.5, "冻结!", {100, 200, 255})
                            end
                        else
                            local newDur = 2 + WE.getChillDurationMod()
                            local oldDur = bestTarget.chilledTurns or 0
                            local hadChill = bestTarget.chilled and oldDur > 0
                            bestTarget.chilled = 1
                            bestTarget.chilledTurns = newDur
                            bestTarget.chillStacks = math.min((bestTarget.chillStacks or 0) + 1, M.CHILL_MAX_STACKS)
                            if not hadChill then
                                M.addDamageText(bestTarget.x, bestTarget.y - 0.5, "冻僵!", {100, 200, 255})
                            elseif bestTarget.chillStacks > 1 then
                                M.addDamageText(bestTarget.x, bestTarget.y - 0.5, "冻僵 x" .. bestTarget.chillStacks, {100, 200, 255})
                            end
                        end
                    end
                    -- 灼伤（火花术 m_spark）
                    if b.skillId == "m_spark" and bestTarget.isMonster then
                        if bestTarget._noElementDebuff then
                            bestTarget._noElementDebuff = nil
                        else
                            local newDur = 3 + WE.getBurnDurationMod()
                            M.applyBurnDebuff(bestTarget, b.attacker.mAtk or 0, newDur)
                            local stacks = bestTarget.burnStacks and #bestTarget.burnStacks or 0
                            M.addDamageText(bestTarget.x, bestTarget.y - 0.5, "灼伤!" .. (stacks > 1 and (" x" .. stacks) or ""), {255, 120, 40})
                        end
                    end
                    -- 破甲（破甲投掷 a_armor_break、预告信 a_notice）
                    if bsDef.armorBreakPct then
                        local slv = GS.skillLevels[b.skillId] or 1
                        local chance = (bsDef.armorBreakChance or 100) + (bsDef.armorBreakChancePerLv or 0) * (slv - 1)
                        chance = math.min(chance, 90)
                        if b.skillId == "a_notice" or math.random(100) <= chance then
                            local newDur = bsDef.armorBreakDuration or 3
                            local oldDur = bestTarget.armorBrokenTurns or 0
                            local hadBreak = bestTarget.armorBroken and oldDur > 0
                            bestTarget.armorBroken = bsDef.armorBreakPct
                            bestTarget.armorBrokenTurns = newDur
                            if not hadBreak or newDur > oldDur then
                                M.addDamageText(bestTarget.x, bestTarget.y - 0.5, "破甲!", {220, 100, 60})
                            end
                        end
                    end
                    -- 暴伤易伤（预告信 a_notice）
                    if bsDef.noticeCritDmgPerLv then
                        local slv = GS.skillLevels[b.skillId] or 1
                        local newDur = (bsDef.noticeCritDmgDuration or 3) + 1
                        local oldDur = bestTarget.noticeCritDmgTurns or 0
                        local hadNotice = bestTarget.noticeCritDmgBonus and oldDur > 0
                        bestTarget.noticeCritDmgBonus = bsDef.noticeCritDmgPerLv * slv
                        bestTarget.noticeCritDmgTurns = newDur
                        if not hadNotice or newDur > oldDur then
                            M.addDamageText(bestTarget.x, bestTarget.y - 0.5, "暴伤易伤!", {220, 200, 100})
                        end
                    end
                    -- 注意：晕眩效果(h_stun_shot stunChance / m_lightning stunChance)被故意跳过
                    -- 银鹿不传递晕眩效果
                end
            end

            M._pendingProjectileHit = false
            M._currentProjectileId = nil
            b.prevUnit = bestTarget

            if b.bounceIndex >= b.bounceCount then
                toRemove[#toRemove + 1] = i
            else
                b._cooldown = 0.38
            end
        end

        ::continueBounce::
    end

    -- 倒序移除已完成的链
    for j = #toRemove, 1, -1 do
        table.remove(GS.pendingBounces, toRemove[j])
    end
end

require("Combat_AOE").init(M)
require("Combat_Turns").init(M)
require("Combat_Spawn").init(M)

return M
