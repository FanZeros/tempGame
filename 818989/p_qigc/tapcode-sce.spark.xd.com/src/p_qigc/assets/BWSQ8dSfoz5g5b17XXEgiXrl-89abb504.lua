-- ============================================================
-- Combat_AOE.lua  —— AOE魔法/地面技能（圣树/冰墙/火球/雷击/暴风雪等）
-- 由 Combat.lua 拆分，通过 init(M) 挂载到主模块
-- ============================================================
local GS = require("GameState")
local WE = require("WeatherEffects")

local sub = {}

function sub.init(M)

-- 桥接：从主模块获取共享 local 函数
local inCircleRange          = M._inCircleRange
local calcSkillDamage        = M._calcSkillDamage
local applyDamageAndCheck    = M._applyDamageAndCheck
local forEachAdjacentMonster = M._forEachAdjacentMonster
local getPlayerWeaponTag     = M._getPlayerWeaponTag
local applyElementBonus      = M._applyElementBonus
local playAttackSound        = M._playAttackSound
local tryMarkTarget          = M._tryMarkTarget
local isHeroUnit             = M._isHeroUnit
local getAoeRangeBonus       = M._getAoeRangeBonus
local rollDodge              = M._rollDodge
local isMultiCastableRangedSkill = M._isMultiCastableRangedSkill
local getMultiCastCount      = M._getMultiCastCount
local pickMultiCastTargets   = M._pickMultiCastTargets

-- ====================================================================
-- 地面目标技能（圣树等）
-- ====================================================================
function M.executeGroundSkill(caster, skillId, tx, ty)
    local def = GS.SKILL_DEFS[skillId]
    if not def then return end

    -- 冰环术：走专用 AOE 流程（内部会调用 useSkill）
    if def.iceRingAoe then
        M.performIceRingAOE(caster, tx, ty, skillId)

    -- 火球术：走火球 AOE 流程（内部会调用 useSkill）
    elseif def.fireballAoe then
        M.performFireballAOE(caster, tx, ty, skillId)

    -- 陨石术：走陨石 AOE 流程（内部会调用 useSkill）
    elseif def.meteorAoe then
        M.performMeteorAOE(caster, tx, ty, skillId)

    -- 落雷术：走落雷 AOE 流程
    elseif def.thunderAoe then
        M.performThunderAOE(caster, tx, ty, skillId)

    -- 暴风雪：创建持续 AOE 区域
    elseif def.blizzardAoe then
        M.performBlizzardAOE(caster, tx, ty, skillId)

    -- 闪烁：传送到目标空地（延迟移动，等特效飞到终点后再显示角色）
    elseif def.blinkSkill then
        local oldX, oldY = caster.x, caster.y
        GS.useSkill(skillId)
        M.addSkillCastText(caster.x, caster.y, skillId)
        -- 闪烁回复：每等级回复最大HP/MP的2%
        local blinkLv = GS.skillLevels[skillId] or 1
        local regenPct = 2 * blinkLv
        local hpHeal = math.max(1, math.floor(caster.maxHp * regenPct / 100))
        local mpHeal = math.max(1, math.floor(caster.maxMp * regenPct / 100))
        caster.hp = math.min(caster.hp + hpHeal, caster.maxHp)
        caster.mp = math.min(caster.mp + mpHeal, caster.maxMp)
        M.addDamageText(caster.x, caster.y - 0.3, "+" .. hpHeal, {100, 255, 100})
        M.addDamageText(caster.x, caster.y + 0.1, "+" .. mpHeal, {100, 180, 255})
        M.addBlinkEffect(oldX, oldY, tx, ty)
        -- 延迟移动：特效总时长0.9s，在40%时角色出现在终点
        GS.pendingBlinkMove = {
            unit = caster,
            tx = tx, ty = ty,
            delay = 0.9 * 0.4,  -- 0.36s后移动
            timer = 0,
        }
        -- 立即隐藏角色（设置标记，渲染时跳过）
        caster.blinkHidden = true
        return  -- 闪烁不参与多重施法，保持提前返回

    else
        GS.useSkill(skillId)
        M.addSkillCastText(caster.x, caster.y, skillId)

        if def.holyTree then
            local lv = GS.skillLevels[skillId] or 1
            -- 计算治疗范围：基础1格，在3/6/10级各+1
            local healRange = 1
            local breaks = def.holyTreeRangeBreaks or {3, 6, 10}
            for _, brk in ipairs(breaks) do
                if lv >= brk then healRange = healRange + 1 end
            end
            -- 计算治疗百分比
            local healPct = (def.holyTreeHealPctBase or 13) + (def.holyTreeHealPctPerLv or 3) * lv
            -- 计算持续时间：基础5回合，在2/4/6/8/10级各+1
            local baseDur = def.holyTreeDuration or 5
            local durBreaks = def.holyTreeDurBreaks or {2, 4, 6, 8, 10}
            for _, brk in ipairs(durBreaks) do
                if lv >= brk then baseDur = baseDur + 1 end
            end
            -- 移除旧圣树（同时只能存在一棵）
            for i = #GS.holyTrees, 1, -1 do
                -- M.addDamageText(GS.holyTrees[i].x, GS.holyTrees[i].y, "圣树消散", {120, 180, 100})
                table.remove(GS.holyTrees, i)
            end
            -- 创建圣树前推开占据者
            GS.displaceUnitAt(tx, ty)
            local tree = {
                x = tx, y = ty,
                isHolyTree = true,
                turnsLeft = baseDur + 1, -- +1 补偿当回合递减
                hitsLeft = def.holyTreeHits or 5,
                hp = def.holyTreeHits or 5,
                maxHp = def.holyTreeHits or 5,
                healRange = healRange,
                healPct = healPct,
                casterMAtk = caster.mAtk or 0,
                image = "image/holy_tree.png",
            }
            table.insert(GS.holyTrees, tree)
        end
    end

    -- 深渊词缀：地面目标 AOE 法术多重施法（所有调用点统一处理）
    if not M._multiCasting and caster == GS.player and isMultiCastableRangedSkill(skillId) then
        local mcCount = getMultiCastCount()
        if mcCount > 0 then
            local range = (def.skillRange or 3) + GS.getElementRangeBonus(skillId)
            -- 排除主目标位置的怪物，确保选择不同位置的次级目标
            local primaryExcludes = {}
            for _, m in ipairs(GS.monsters) do
                if m.hp > 0 and m.x == tx and m.y == ty then
                    primaryExcludes[#primaryExcludes + 1] = m
                end
            end
            local extras = pickMultiCastTargets(caster, primaryExcludes, mcCount, range)
            if #extras > 0 then
                local mpCost = GS.getSkillMpCost(skillId)
                M._multiCasting = true
                for _, et in ipairs(extras) do
                    if mpCost > 0 and (GS.player.mp or 0) < mpCost then break end
                    if mpCost > 0 then
                        GS.player.mp = GS.player.mp - mpCost
                    end
                    GS._skipUseSkill = true
                    M.executeGroundSkill(caster, skillId, et.x, et.y)
                    GS._skipUseSkill = nil
                end
                M._multiCasting = nil
            end
        end
    end

    -- 白木胁差：地面目标伤害技能额外施展（chainQueue 延迟）
    -- 交叉保护：多重施法的子调用不触发白木胁差
    if not M._extraDmgCasting and not M._multiCasting then
        M.enqueueExtraDmgSkillCasts(caster, nil, skillId, tx, ty)
    end
end

--- 圣树每回合治疗逻辑（在 endPlayerTurn 中调用）
function M.tickHolyTrees()
    for i = #GS.holyTrees, 1, -1 do
        local tree = GS.holyTrees[i]
        tree.turnsLeft = tree.turnsLeft - 1

        if tree.turnsLeft <= 0 then
            -- M.addDamageText(tree.x, tree.y, "圣树消散", {120, 180, 100})
            table.remove(GS.holyTrees, i)
        else
            -- 治疗范围内的玩家和友军
            local heal = math.floor(tree.casterMAtk * tree.healPct / 100)
            if heal < 1 then heal = 1 end
            -- 治疗效果加成（施法者的healEffectPct）
            if GS.player and (GS.player.healEffectPct or 0) > 0 then
                heal = math.floor(heal * (1 + GS.player.healEffectPct / 100))
            end

            -- 发出冲击波特效
            M.addHolyTreeWaveEffect(tree.x, tree.y, tree.healRange)

            -- 治疗玩家
            if GS.player and GS.player.hp > 0 then
                if inCircleRange(GS.player.x, GS.player.y, tree.x, tree.y, tree.healRange) then
                    local actualHeal = math.min(heal, GS.player.maxHp - GS.player.hp)
                    GS.player.hp = GS.player.hp + actualHeal
                    M.addDamageText(GS.player.x, GS.player.y, "+" .. heal, {255, 220, 100})
                    M.addDivineGraceEffect(GS.player.x, GS.player.y)
                    M.triggerRadianceDamage(heal)
                end
            end

            -- 治疗友军
            for _, c in ipairs(GS.companions) do
                if c.hp > 0 then
                    if inCircleRange(c.x, c.y, tree.x, tree.y, tree.healRange) then
                        local actualHeal = math.min(heal, c.maxHp - c.hp)
                        c.hp = c.hp + actualHeal
                        M.addDamageText(c.x, c.y, "+" .. heal, {255, 220, 100})
                        M.addDivineGraceEffect(c.x, c.y)
                    end
                end
            end
        end
    end
end

--- 圣树被攻击（敌人攻击圣树时调用，返回true表示已处理）
function M.attackHolyTree(tree)
    tree.hitsLeft = tree.hitsLeft - 1
    tree.hp = tree.hitsLeft
    -- M.addDamageText(tree.x, tree.y, "圣树受击!", {220, 120, 60})
    if tree.hitsLeft <= 0 then
        -- 移除被摧毁的圣树
        for i = #GS.holyTrees, 1, -1 do
            if GS.holyTrees[i] == tree then
                table.remove(GS.holyTrees, i)
                break
            end
        end
        -- M.addDamageText(tree.x, tree.y - 0.3, "圣树被摧毁!", {220, 60, 60})
    end
end

function M.attackIceWall(wall, attacker)
    -- 冰墙按次数摧毁，每次攻击固定消耗1点hit
    wall.hitsLeft = wall.hitsLeft - 1
    wall.hp = wall.hitsLeft
    -- M.addDamageText(wall.x, wall.y, "冰墙受击!", {80, 160, 220})
    -- 火焰护盾反伤：对近战攻击者造成火焰伤害
    if wall.fireShieldTurns and wall.fireShieldTurns > 0 and wall.fireShieldReflectPct then
        if attacker and attacker.hp > 0 then
            local dist = math.abs(attacker.x - wall.x) + math.abs(attacker.y - wall.y)
            if dist <= 1 then
                local reflectDmg = math.max(1, math.floor((GS.player.mAtk or 0) * wall.fireShieldReflectPct / 100))
                reflectDmg = applyElementBonus(reflectDmg, "fire")
                attacker.hp = attacker.hp - reflectDmg
                M.addDamageText(attacker.x, attacker.y, "" .. reflectDmg, {255, 120, 40})
                M.addBurnEffect(attacker.x, attacker.y)
            end
        end
    end
    if wall.hitsLeft <= 0 then
        for i = #GS.iceWalls, 1, -1 do
            if GS.iceWalls[i] == wall then
                table.remove(GS.iceWalls, i)
                break
            end
        end
        -- M.addDamageText(wall.x, wall.y - 0.3, "冰墙被摧毁!", {220, 60, 60})
    end
end

-- ====================================================================
-- 冰墙术（放置冰墙阻挡 + 减益光环）
-- ====================================================================
function M.placeIceWalls(caster, skillId, wallCells)
    local def = GS.SKILL_DEFS[skillId]
    if not def then return end

    GS.useSkill(skillId)

    local lv = GS.skillLevels[skillId] or 1
    local duration = def.iceWallDuration or 3
    local breaks = def.iceWallLenBreaks or {3, 6, 10}
    for _, brk in ipairs(breaks) do
        if lv >= brk then duration = duration + 1 end
    end
    local hits = def.iceWallHits or 2
    if def.iceWallHitsBreaks then
        for _, brk in ipairs(def.iceWallHitsBreaks) do
            if lv >= brk then hits = hits + 1 end
        end
    end

    -- 移除旧冰墙（同时只能存在一组）
    for i = #GS.iceWalls, 1, -1 do
        -- M.addDamageText(GS.iceWalls[i].x, GS.iceWalls[i].y, "冰墙消散", {100, 160, 220})
        table.remove(GS.iceWalls, i)
    end

    for _, c in ipairs(wallCells) do
        -- 推开占据格子的单位
        GS.displaceUnitAt(c.x, c.y)
        local wall = {
            x = c.x, y = c.y,
            turnsLeft = duration + 1 + 1, -- +1 补偿当回合递减, +1 确保完整存在 duration 个后续回合
            hitsLeft = hits,
            hp = hits, maxHp = hits,
            isIceWall = true,
            image = "image/skill_ice_wall.png",
        }
        table.insert(GS.iceWalls, wall)
    end

    M.addIceWallCreateEffect(wallCells)
    M.addSkillCastText(caster.x, caster.y, skillId)

    -- 冰墙创建时对相邻怪物施加冻僵debuff
    M.applyIceWallChill()
end

--- 冰墙每回合递减（在 endPlayerTurn 中调用）
function M.tickIceWalls()
    for i = #GS.iceWalls, 1, -1 do
        local w = GS.iceWalls[i]
        w.turnsLeft = w.turnsLeft - 1
        -- 冰墙上的火焰护盾递减
        if w.fireShieldTurns and w.fireShieldTurns > 0 then
            w.fireShieldTurns = w.fireShieldTurns - 1
            if w.fireShieldTurns <= 0 then
                w.fireShieldReducePct = nil
                w.fireShieldReflectPct = nil
            end
        end
        if w.turnsLeft <= 0 then
            -- M.addDamageText(w.x, w.y, "冰墙消散", {100, 160, 220})
            table.remove(GS.iceWalls, i)
        end
    end
    -- 冰墙存续期间每回合对相邻怪物施加冻僵
    if #GS.iceWalls > 0 then
        M.applyIceWallChill()
    end
end

--- 冰墙冻僵：对所有冰墙相邻（曼哈顿距离≤1）的存活怪物施加冻僵debuff
function M.applyIceWallChill()
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 then
            local nearWall = false
            local ms = GS.unitSize(m)
            for dy = 0, ms - 1 do
                if nearWall then break end
                for dx = 0, ms - 1 do
                    if nearWall then break end
                    local mx, my = m.x + dx, m.y + dy
                    for _, w in ipairs(GS.iceWalls) do
                        if math.abs(mx - w.x) + math.abs(my - w.y) <= 1 then
                            nearWall = true
                            break
                        end
                    end
                end
            end
            if nearWall and not isHeroUnit(m) then
                if WE.shouldUpgradeChillToFreeze() then
                    local newDur = 1 + WE.getFreezeDurationMod()
                    local oldDur = m.frozen or 0
                    m.frozen = math.max(oldDur, newDur)
                    if newDur > oldDur then
                        M.addDamageText(m.x, m.y - 0.5, "冻结!", {100, 200, 255})
                    end
                else
                    local newDur = 2 + WE.getChillDurationMod()
                    local oldDur = m.chilledTurns or 0
                    local hadChill = m.chilled and oldDur > 0
                    m.chilled = 1
                    m.chilledTurns = newDur
                    m.chillStacks = math.min((m.chillStacks or 0) + 1, M.CHILL_MAX_STACKS)
                    if not hadChill then
                        M.addDamageText(m.x, m.y - 0.5, "冻僵!", {100, 200, 255})
                    elseif m.chillStacks > 1 then
                        M.addDamageText(m.x, m.y - 0.5, "冻僵 x" .. m.chillStacks, {100, 200, 255})
                    end
                end
            end
        end
    end
end

-- ====================================================================
-- 冰环术 AOE（3×3 范围魔法伤害 + 冰冻）
-- ====================================================================
function M.performIceRingAOE(attacker, cx, cy, skillId)
    local def = GS.SKILL_DEFS[skillId]
    if not def then return end

    GS.useSkill(skillId)
    M.addSkillCastText(attacker.x, attacker.y, skillId)
    local lv = GS.skillLevels[skillId] or 1
    local mul = GS.getSkillDmgMul(skillId)
    local freezeChance = math.min(100, (def.freezeChanceBase or 82) + (lv - 1) * (def.freezeChancePerLv or 2))
    local freezeDur = (def.freezeDuration or 1)
    if def.freezeDurBreaks then
        for _, b in ipairs(def.freezeDurBreaks) do
            if lv >= b then freezeDur = freezeDur + 1 end
        end
    end
    freezeDur = freezeDur + WE.getFreezeDurationMod()

    -- 屏幕震动
    GS.setScreenShake(0.4, 3, 0.15)

    -- 冰环术 AOE 范围（基础1 + 深渊词缀加成）
    local iceRingR = 1 + getAoeRangeBonus()

    -- 冰环术 AOE 特效
    M.addIceRingEffect(cx, cy, iceRingR)

    -- 伤害文字延迟到冰环扩散命中时刻（~0.20, duration=1.2）
    M._damageTextDelay = 0.20 * 1.2

    -- 收集中心点切比雪夫距离 ≤ iceRingR 范围内所有存活怪物
    local hitCount = 0
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 then
            local ms = GS.unitSize(m)
            local inRange = false
            for dy = 0, ms - 1 do
                if inRange then break end
                for dx = 0, ms - 1 do
                    local mx, my = m.x + dx, m.y + dy
                    if math.abs(mx - cx) <= iceRingR and math.abs(my - cy) <= iceRingR then
                        inRange = true
                        break
                    end
                end
            end
            if inRange then
                -- 闪避判定
                if rollDodge(attacker, m, skillId) then
                    M.addDamageText(m.x, m.y, "Miss", {255, 255, 255})
                else
                    local dmg, isCrit = calcSkillDamage(attacker, m, { mul = mul, skillId = skillId, useMagic = true, element = "ice" })
                    applyDamageAndCheck(attacker, m, dmg, "", {100, 200, 255}, isCrit, true)
                    if m._noElementDebuff then
                        m._noElementDebuff = nil  -- 蒸腾中和，不施加冰冻/冻僵
                    elseif isHeroUnit(m) then
                        -- 英雄单位免疫冰冻/冻僵
                    else
                        -- 冰冻判定
                        if m.hp > 0 and math.random(1, 100) <= freezeChance then
                            m.frozen = (m.frozen or 0) > freezeDur and m.frozen or freezeDur
                            M.addDamageText(m.x, m.y - 0.5, "冰冻!", {100, 200, 255})
                        end
                        -- 冻僵debuff（移动距离-1）
                        if m.hp > 0 then
                            if WE.shouldUpgradeChillToFreeze() then
                                m.frozen = math.max(m.frozen or 0, 1 + WE.getFreezeDurationMod())
                                M.addDamageText(m.x, m.y - 0.5, "冻结!", {100, 200, 255})
                            else
                                m.chilled = 1
                                m.chilledTurns = 2 + WE.getChillDurationMod()
                                m.chillStacks = math.min((m.chillStacks or 0) + 1, M.CHILL_MAX_STACKS)
                                if m.chillStacks > 1 then
                                    M.addDamageText(m.x, m.y - 0.5, "冻僵 x" .. m.chillStacks, {100, 200, 255})
                                else
                                    M.addDamageText(m.x, m.y - 0.5, "冻僵!", {100, 200, 255})
                                end
                            end
                        end
                    end
                    hitCount = hitCount + 1
                end
            end
        end
    end

    playAttackSound()
    M._damageTextDelay = 0  -- 清除延迟

    if hitCount == 0 then
        M.addDamageText(attacker.x, attacker.y - 0.5, "Miss", {255, 255, 255})
    end
end

-- ====================================================================
-- 火球术（地面 AOE，曼哈顿距离）
-- ====================================================================
function M.performFireballAOE(attacker, cx, cy, skillId)
    local def = GS.SKILL_DEFS[skillId]
    if not def then return end

    GS.useSkill(skillId)
    M.addSkillCastText(attacker.x, attacker.y, skillId)
    local mul = GS.getSkillDmgMul(skillId)
    local radius = (def.fireballRadius or 2) + getAoeRangeBonus()

    -- 火球弹道特效（从施法者飞向目标点）
    M.addFireballEffect(attacker.x, attacker.y, cx, cy, radius)

    -- 屏幕震动（delay 与火球命中时刻对齐：hitT=0.30 * duration=0.9 ≈ 0.27s）
    GS.setScreenShake(0.5, 5, 0.27)

    -- 伤害文字延迟到火球命中时刻（hitT=0.30, duration=0.9 → 0.27s）
    M._damageTextDelay = 0.30 * 0.9

    -- 收集目标点曼哈顿距离 ≤ radius 内所有存活怪物
    local hitCount = 0
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 then
            local ms = GS.unitSize(m)
            local inRange = false
            for dy = 0, ms - 1 do
                if inRange then break end
                for dx = 0, ms - 1 do
                    local mx, my = m.x + dx, m.y + dy
                    if inCircleRange(mx, my, cx, cy, radius) then
                        inRange = true
                        break
                    end
                end
            end
            if inRange then
                -- 闪避判定
                if rollDodge(attacker, m, skillId) then
                    M.addDamageText(m.x, m.y, "Miss", {255, 255, 255})
                else
                    local dmg, isCrit = calcSkillDamage(attacker, m, { mul = mul, skillId = skillId, useMagic = true, element = "fire" })
                    applyDamageAndCheck(attacker, m, dmg, "", {255, 120, 40}, isCrit, true)
                    hitCount = hitCount + 1
                    -- 火球术施加灼伤debuff（可叠加）
                    if m.hp > 0 then
                        if m._noElementDebuff then
                            m._noElementDebuff = nil  -- 蒸腾中和，不施加灼伤
                        else
                            local newDur = 3 + WE.getBurnDurationMod()
                            M.applyBurnDebuff(m, attacker.mAtk or 0, newDur)
                            local sc = m.burnStacks and #m.burnStacks or 1
                            M.addDamageText(m.x, m.y - 0.5, "灼伤!" .. (sc > 1 and ("x" .. sc) or ""), {255, 120, 40})
                        end
                    end
                end
            end
        end
    end

    playAttackSound()

    M._damageTextDelay = 0  -- 清除延迟

    if hitCount == 0 then
        M.addDamageText(attacker.x, attacker.y - 0.5, "Miss", {255, 255, 255})
    end

    -- 生成燃烧地面（延迟到火球命中时刻再出现：hitT=0.30 * duration=0.9）
    local burnDuration = WE.adjustBurningGroundDuration(def.burnDuration or 3)
    local lv = GS.skillLevels[skillId] or 1
    local burnPct = (def.burnPctBase or 18) + (def.burnPctPerLv or 2) * (lv - 1)
    local casterMAtk = attacker.mAtk or 0

    local pendingItems = {}
    for bx = cx - radius, cx + radius do
        for by = cy - radius, cy + radius do
            if bx >= 1 and bx <= GS.BOARD_SIZE and by >= 1 and by <= GS.BOARD_SIZE then
                if inCircleRange(bx, by, cx, cy, radius) then
                    local dx, dy = bx - cx, by - cy
                    local dist = math.sqrt(dx * dx + dy * dy)
                    local extraTurns = math.max(0, radius - math.floor(dist))
                    local cellTurns = burnDuration + 1 + extraTurns
                    pendingItems[#pendingItems + 1] = {
                        x = bx, y = by,
                        turnsLeft = cellTurns,
                        burnPct = burnPct,
                        casterMAtk = casterMAtk,
                    }
                end
            end
        end
    end
    if #pendingItems > 0 then
        table.insert(GS.pendingBurningGrounds, {
            delay = 0.30 * 0.9,  -- 与火球命中时刻对齐
            items = pendingItems,
        })
    end
end

-- ====================================================================
-- 落雷术 AOE（地面范围雷电伤害 + 击晕）
-- ====================================================================
function M.performThunderAOE(attacker, cx, cy, skillId)
    local def = GS.SKILL_DEFS[skillId]
    if not def then return end

    GS.useSkill(skillId)
    M.addSkillCastText(attacker.x, attacker.y, skillId)
    local mul = GS.getSkillDmgMul(skillId)
    local radius = (def.thunderAoeRadius or 1) + getAoeRangeBonus()

    -- 雷电劈地特效
    M._pendingProjectileHit = true
    M.addThunderStrikeEffect(cx, cy, radius)

    -- 屏幕震动
    GS.setScreenShake(0.35, 5, 0.25)

    -- 收集目标点曼哈顿距离 ≤ radius 内所有存活怪物
    local hitCount = 0
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 then
            local ms = GS.unitSize(m)
            local inRange = false
            for dy = 0, ms - 1 do
                if inRange then break end
                for dx = 0, ms - 1 do
                    local mx, my = m.x + dx, m.y + dy
                    if inCircleRange(mx, my, cx, cy, radius) then
                        inRange = true
                        break
                    end
                end
            end
            if inRange then
                -- 闪避判定
                if rollDodge(attacker, m, skillId) then
                    M.addDamageText(m.x, m.y, "Miss", {255, 255, 255})
                else
                    local dmg, isCrit = calcSkillDamage(attacker, m, { mul = mul, skillId = skillId, useMagic = true, element = "thunder" })
                    applyDamageAndCheck(attacker, m, dmg, "", {255, 220, 60}, isCrit, true)
                    hitCount = hitCount + 1
                    -- 击晕判定（英雄单位免疫）
                    if m.hp > 0 and def.stunChance and not m.stunned and not isHeroUnit(m) then
                        local chance = def.stunChance
                        -- 失感：每层冻僵+5%晕眩概率
                        if m._numbingPending then
                            chance = chance + m._numbingPending * 5
                            m._numbingPending = nil
                        end
                        if math.random(100) <= chance then
                            m.stunned = def.stunDuration or 1
                            M.addDamageText(m.x, m.y - 0.5, "晕眩!", {255, 220, 60})
                        end
                    end
                end
            end
        end
    end

    playAttackSound()

    if hitCount == 0 then
        M.addDamageText(attacker.x, attacker.y - 0.5, "Miss", {255, 255, 255})
    end
end

-- ====================================================================
-- 陨石术 AOE（范围魔法伤害 + 燃烧地面）
-- ====================================================================
function M.performMeteorAOE(attacker, cx, cy, skillId)
    local def = GS.SKILL_DEFS[skillId]
    if not def then return end

    GS.useSkill(skillId)
    M.addSkillCastText(attacker.x, attacker.y, skillId)
    local lv = GS.skillLevels[skillId] or 1
    local mul = GS.getSkillDmgMul(skillId)
    local radius = (def.meteorRadius or 2) + getAoeRangeBonus()

    -- 陨石降落特效
    M.addMeteorEffect(cx, cy, radius)

    -- 伤害文字延迟到陨石落地时刻（impactT=0.33, duration=1.8）
    M._damageTextDelay = 0.33 * 1.8

    -- 收集目标点曼哈顿距离 ≤ radius 内所有存活怪物
    local hitCount = 0
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 then
            local ms = GS.unitSize(m)
            local inRange = false
            for dy = 0, ms - 1 do
                if inRange then break end
                for dx = 0, ms - 1 do
                    local mx, my = m.x + dx, m.y + dy
                    if inCircleRange(mx, my, cx, cy, radius) then
                        inRange = true
                        break
                    end
                end
            end
            if inRange then
                -- 闪避判定
                if rollDodge(attacker, m, skillId) then
                    M.addDamageText(m.x, m.y, "Miss", {255, 255, 255})
                else
                    local dmg, isCrit = calcSkillDamage(attacker, m, { mul = mul, skillId = skillId, useMagic = true, element = "fire" })
                    applyDamageAndCheck(attacker, m, dmg, "", {255, 120, 40}, isCrit, true)
                    hitCount = hitCount + 1
                    -- 陨石术施加灼伤debuff（可叠加）
                    if m.hp > 0 then
                        if m._noElementDebuff then
                            m._noElementDebuff = nil  -- 蒸腾中和，不施加灼伤
                        else
                            local newDur = 3 + WE.getBurnDurationMod()
                            M.applyBurnDebuff(m, attacker.mAtk or 0, newDur)
                            local sc = m.burnStacks and #m.burnStacks or 1
                            M.addDamageText(m.x, m.y - 0.5, "灼伤!" .. (sc > 1 and ("x" .. sc) or ""), {255, 120, 40})
                        end
                    end
                    -- 烈焰书：陨石术25%概率晕眩（训练假人、英雄单位免疫）
                    if m.hp > 0 and (attacker.meteorStunChance or 0) > 0
                       and not m.stunned and not m.isTrainingDummy and not isHeroUnit(m) then
                        if math.random(1, 100) <= attacker.meteorStunChance then
                            local dur = math.max(1, attacker.meteorStunDuration or 1)
                            m.stunned = dur
                            M.addDamageText(m.x, m.y - 0.5, "晕眩!", {255, 220, 60})
                        end
                    end
                end
            end
        end
    end

    playAttackSound()
    M._damageTextDelay = 0  -- 清除延迟

    if hitCount == 0 then
        M.addDamageText(attacker.x, attacker.y - 0.5, "Miss", {255, 255, 255})
    end

    -- 生成燃烧地面（延迟到陨石落地时刻再出现：impactT=0.33 * duration=1.8）
    local burnDuration = WE.adjustBurningGroundDuration(def.burnDuration or 3)
    local burnPct = (def.burnPctBase or 22) + (def.burnPctPerLv or 2) * (lv - 1)
    local casterMAtk = attacker.mAtk or 0

    local pendingItems = {}
    for bx = cx - radius, cx + radius do
        for by = cy - radius, cy + radius do
            if bx >= 1 and bx <= GS.BOARD_SIZE and by >= 1 and by <= GS.BOARD_SIZE then
                if inCircleRange(bx, by, cx, cy, radius) then
                    local dx, dy = bx - cx, by - cy
                    local dist = math.sqrt(dx * dx + dy * dy)
                    local extraTurns = math.max(0, radius - math.floor(dist))
                    local cellTurns = burnDuration + 1 + extraTurns
                    pendingItems[#pendingItems + 1] = {
                        x = bx, y = by,
                        turnsLeft = cellTurns,
                        burnPct = burnPct,
                        casterMAtk = casterMAtk,
                    }
                end
            end
        end
    end
    if #pendingItems > 0 then
        table.insert(GS.pendingBurningGrounds, {
            delay = 0.33 * 1.8,  -- 与陨石落地时刻对齐
            items = pendingItems,
        })
    end
end

-- ====================================================================
-- 燃烧地面：回合递减 + 对站在上面的敌人造成伤害
-- ====================================================================
function M.tickBurningGrounds()
    for i = #GS.burningGrounds, 1, -1 do
        local bg = GS.burningGrounds[i]
        bg.turnsLeft = bg.turnsLeft - 1
        if bg.turnsLeft <= 0 then
            table.remove(GS.burningGrounds, i)
        else
            -- 辅助：判断单位是否占据指定格子
            local function unitOnCell(unit, cx, cy)
                local s = GS.unitSize(unit)
                for dy = 0, s - 1 do
                    for dx = 0, s - 1 do
                        if unit.x + dx == cx and unit.y + dy == cy then return true end
                    end
                end
                return false
            end

            local burnAtk = math.max(1, math.floor(bg.casterMAtk * bg.burnPct / 100))

            -- 辅助：对可燃单位施加灼烧伤害和debuff
            local function applyBurnToUnit(unit)
                -- 地狱踏：免疫燃烧地面，并将伤害转化为治疗
                if not unit.isMonster and (unit.hellStompHealPct or 0) > 0 then
                    local healAmt = math.max(1, math.floor(burnAtk * unit.hellStompHealPct / 100))
                    local oldHp = unit.hp
                    unit.hp = math.min(unit.hp + healAmt, unit.maxHp)
                    local actualHeal = unit.hp - oldHp
                    M.addDamageText(unit.x, unit.y, "+" .. healAmt, {80, 255, 120})
                    if actualHeal > 0 then
                        M.addHealEffect(unit.x, unit.y, unit)
                    end
                    -- 辉光：传入完整治疗量（含过量）
                    M.triggerRadianceDamage(healAmt)
                    return
                end
                -- 火焰护盾：免疫燃烧地面
                if not unit.isMonster and GS.fireShieldTurns > 0 then
                    M.addDamageText(unit.x, unit.y, "免疫", {255, 180, 60})
                    return
                end
                local burnDef = unit.mdef or 0
                local burnDmg = math.floor(burnAtk * burnAtk / (burnAtk + math.max(1, burnDef)))
                burnDmg = math.max(1, burnDmg)
                burnDmg = applyElementBonus(burnDmg, "fire")
                -- 抗性检查：火抗减伤30%
                if unit.resistance then
                    for _, r in ipairs(unit.resistance) do
                        if r == "fire" then
                            burnDmg = math.max(1, math.floor(burnDmg * 0.7))
                            break
                        end
                    end
                end
                -- 蒸腾：燃烧地面（火属性）击中冻僵/冻结目标
                if unit.chilled or (unit.frozen and unit.frozen > 0) then
                    local burnSC = unit.burnStacks and #unit.burnStacks or 0
                    local chillSC = M.getEffectiveChillStacks(unit)
                    burnDmg = math.floor(burnDmg * (1 + WE.getEvaporationBonus() * (math.max(1, burnSC) + chillSC)))
                    unit.chilled = nil
                    unit.chilledTurns = nil
                    unit.chillStacks = nil
                    unit.frozen = nil
                    M.clearBurnDebuff(unit)
                    M.addDamageText(unit.x, unit.y - 0.8, "蒸腾!", {255, 50, 50})
                end
                -- 魔法盾：部分伤害由 MP 抵扣
                if not unit.isMonster and GS.magicShieldActive and (unit.mp or 0) > 0 then
                    local msDef = GS.SKILL_DEFS["m_magic_shield"]
                    local msLv = GS.skillLevels["m_magic_shield"] or 0
                    if msDef and msLv > 0 then
                        local absorbPct = (msDef.magicShieldAbsorbBase or 5) + (msLv - 1) * (msDef.magicShieldAbsorbPerLv or 5)
                        absorbPct = math.min(absorbPct, 50)
                        local ratio = (msDef.magicShieldRatioBase or 1.1) + (msLv - 1) * (msDef.magicShieldRatioPerLv or 0.1)
                        -- 节能施法加成：每级提高魔法盾抵扣效率3%
                        local matkUpLv = GS.skillLevels["m_matk_up"] or 0
                        if matkUpLv > 0 then
                            ratio = ratio + 0.03 * matkUpLv
                        end
                        local dmgToAbsorb = math.floor(burnDmg * absorbPct / 100)
                        if dmgToAbsorb > 0 then
                            local mpNeeded = math.floor(dmgToAbsorb / ratio + 0.5)
                            if mpNeeded > unit.mp then
                                mpNeeded = unit.mp
                                dmgToAbsorb = math.floor(mpNeeded * ratio)
                            end
                            if dmgToAbsorb > 0 and mpNeeded > 0 then
                                unit.mp = unit.mp - mpNeeded
                                burnDmg = math.max(1, burnDmg - dmgToAbsorb)
                                M.addDamageText(unit.x, unit.y - 0.5, "-" .. mpNeeded, {80, 160, 255})
                            end
                        end
                    end
                end
                -- 饮血护甲值：先用护甲值抵扣伤害
                if not unit.isMonster and (GS.bloodShield or 0) > 0 and burnDmg > 0 then
                    local absorbed = math.min(GS.bloodShield, burnDmg)
                    GS.bloodShield = GS.bloodShield - absorbed
                    burnDmg = burnDmg - absorbed
                    if absorbed > 0 then
                        M.addDamageText(unit.x, unit.y + 0.3, "-" .. absorbed .. " 护甲", {200, 180, 80})
                    end
                end
                unit.hp = unit.hp - burnDmg
                if GS.trainingMode and unit.isTrainingDummy then GS.trainingTurnDmg = GS.trainingTurnDmg + burnDmg end
                M.addDamageText(unit.x, unit.y, "" .. burnDmg, {255, 120, 30})
                unit.hurtTimer = 0.3
                unit.hurtDuration = 0.3
                if unit.hp <= 0 then
                    unit.hp = 0
                end
                -- 燃烧地面附加2回合灼伤debuff（可叠加）
                if unit.hp > 0 then
                    if unit._noElementDebuff then
                        unit._noElementDebuff = nil
                    else
                        local newDur = 3 + WE.getBurnDurationMod()
                        M.applyBurnDebuff(unit, bg.casterMAtk, newDur)
                        local sc = unit.burnStacks and #unit.burnStacks or 1
                        M.addDamageText(unit.x, unit.y - 0.5, "灼伤!" .. (sc > 1 and ("x" .. sc) or ""), {255, 120, 40})
                    end
                end
            end

            -- 1) 对怪物造成伤害
            for _, m in ipairs(GS.monsters) do
                if m.hp > 0 and unitOnCell(m, bg.x, bg.y) then
                    applyBurnToUnit(m)
                end
            end

            -- 2) 对玩家造成伤害
            if GS.player and GS.player.hp > 0 and unitOnCell(GS.player, bg.x, bg.y) then
                applyBurnToUnit(GS.player)
            end

            -- 3) 对同伴造成伤害
            for _, c in ipairs(GS.companions) do
                if c.hp > 0 and unitOnCell(c, bg.x, bg.y) then
                    applyBurnToUnit(c)
                end
            end

            -- 4) 对冰墙造成伤害（视为1次攻击）
            for _, w in ipairs(GS.iceWalls) do
                if w.x == bg.x and w.y == bg.y then
                    M.attackIceWall(w, nil)
                end
            end
        end
    end
    M.removeDeadMonsters()
    M.removeDeadCompanions()
    M.checkPlayerDeath()
end

-- ====================================================================
-- 暴风雪：创建持续 AOE 区域（首次即命中 + 减速）
-- ====================================================================
function M.performBlizzardAOE(attacker, cx, cy, skillId)
    local def = GS.SKILL_DEFS[skillId]
    if not def then return end

    GS.useSkill(skillId)
    M.addSkillCastText(attacker.x, attacker.y, skillId)
    local lv = GS.skillLevels[skillId] or 1
    local mul = GS.getSkillDmgMul(skillId)
    local radius = (def.blizzardRadius or 2) + getAoeRangeBonus()
    local casterMAtk = attacker.mAtk or 0

    -- 计算持续回合数（基础 + 等级突破）
    local duration = def.blizzardDurationBase or 3
    if def.blizzardDurationBreaks then
        for _, reqLv in ipairs(def.blizzardDurationBreaks) do
            if lv >= reqLv then duration = duration + 1 end
        end
    end

    -- 减速参数
    local slowDur = def.blizzardSlowDur or 3
    local slowVal = (lv >= 10 and def.blizzardSlowVal10 or def.blizzardSlowVal) or 1

    -- 触发冰锥坠落特效（首次施法）
    M.addBlizzardIceEffect(cx, cy, radius)

    -- 伤害文字延迟到冰锥落地时刻（~0.35, duration=1.4）
    M._damageTextDelay = 0.35 * 1.4

    -- 首次即造成伤害 + 减速
    M.blizzardDealDamage(attacker, cx, cy, radius, mul, slowDur, slowVal, def.name)
    M._damageTextDelay = 0  -- 清除延迟

    -- 创建暴风雪区域（turnsLeft 不需要 +1，因为首次伤害已在此处执行）
    -- 后续 tick 在 endPlayerTurn 中执行，剩余 duration-1 次
    -- 检查是否已有暴风雪区域在同位置（替换）
    local found = false
    for _, bz in ipairs(GS.blizzardZones) do
        if bz.cx == cx and bz.cy == cy then
            bz.radius = radius
            bz.turnsLeft = duration  -- 含本回合，tick 时先减再伤害
            bz.mul = mul
            bz.casterMAtk = casterMAtk
            bz.skillId = skillId
            bz.slowDur = slowDur
            bz.slowVal = slowVal
            bz.skillName = def.name
            found = true
            break
        end
    end
    if not found then
        table.insert(GS.blizzardZones, {
            cx = cx, cy = cy, radius = radius,
            turnsLeft = duration,
            mul = mul, casterMAtk = casterMAtk,
            skillId = skillId, skillName = def.name,
            slowDur = slowDur, slowVal = slowVal,
        })
    end
end

-- 暴风雪区域：对范围内怪物造成伤害 + 减速
function M.blizzardDealDamage(attacker, cx, cy, radius, mul, slowDur, slowVal, skillName)
    local hitCount = 0
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 then
            local ms = GS.unitSize(m)
            local inRange = false
            for dy = 0, ms - 1 do
                if inRange then break end
                for dx = 0, ms - 1 do
                    if inCircleRange(m.x + dx, m.y + dy, cx, cy, radius) then
                        inRange = true
                        break
                    end
                end
            end
            if inRange then
                -- 闪避判定
                if rollDodge(attacker, m, nil) then
                    M.addDamageText(m.x, m.y, "Miss", {255, 255, 255})
                else
                    local wasChilled = m.chilled and (m.chilledTurns or 0) > 0  -- 记录施法前是否已冻僵（寒冰书触发条件）
                    local dmg, isCrit = calcSkillDamage(attacker, m, { mul = mul, skillId = nil, useMagic = true, element = "ice" })
                    applyDamageAndCheck(attacker, m, dmg, "", {100, 200, 255}, isCrit, true)
                    hitCount = hitCount + 1
                    if m._noElementDebuff then
                        m._noElementDebuff = nil  -- 蒸腾中和，不施加减速/冻僵
                    elseif isHeroUnit(m) then
                        -- 英雄单位免疫冰冻/冻僵/减速
                    else
                        -- 施加减速 debuff（刷新持续时间）
                        local oldSlowTurns = m.moveSlowTurns or 0
                        local hadSlow = m.moveSlow and oldSlowTurns > 0
                        m.moveSlow = slowVal
                        m.moveSlowTurns = slowDur
                        -- 冻僵debuff（移动距离-1）
                        if m.hp > 0 then
                            if WE.shouldUpgradeChillToFreeze() then
                                local newDur = 1 + WE.getFreezeDurationMod()
                                local oldDur = m.frozen or 0
                                m.frozen = math.max(oldDur, newDur)
                                if newDur > oldDur then
                                    M.addDamageText(m.x, m.y - 0.5, "冻结!", {100, 200, 255})
                                end
                            else
                                local newDur = 2 + WE.getChillDurationMod()
                                local oldDur = m.chilledTurns or 0
                                local hadChill = m.chilled and oldDur > 0
                                m.chilled = 1
                                m.chilledTurns = newDur
                                m.chillStacks = math.min((m.chillStacks or 0) + 1, M.CHILL_MAX_STACKS)
                                if not hadChill then
                                    M.addDamageText(m.x, m.y - 0.5, "冻僵!", {100, 200, 255})
                                elseif m.chillStacks > 1 then
                                    M.addDamageText(m.x, m.y - 0.5, "冻僵 x" .. m.chillStacks, {100, 200, 255})
                                end
                            end
                        end
                        -- 寒冰书：对已冻僵目标额外触发冰冻
                        if m.hp > 0 and wasChilled and (attacker.blizzardFreezeChance or 0) > 0 then
                            if math.random(1, 100) <= attacker.blizzardFreezeChance then
                                local dur = math.max(1, attacker.blizzardFreezeDuration or 1)
                                local oldFrozen = m.frozen or 0
                                m.frozen = math.max(oldFrozen, dur)
                                if dur > oldFrozen then
                                    M.addDamageText(m.x, m.y - 0.5, "冰冻!", {150, 230, 255})
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    playAttackSound()
    if hitCount == 0 then
        M.addDamageText(cx, cy - 0.5, "Miss", {255, 255, 255})
    end
end

-- ====================================================================
-- 暴风雪区域：回合 tick（造成伤害 + 减速 + 持续递减）
-- ====================================================================
function M.tickBlizzardZones()
    if #GS.blizzardZones == 0 then return end

    -- 使用快照的施法者属性构造临时攻击者
    for i = #GS.blizzardZones, 1, -1 do
        local bz = GS.blizzardZones[i]
        bz.turnsLeft = bz.turnsLeft - 1
        if bz.turnsLeft <= 0 then
            table.remove(GS.blizzardZones, i)
        else
            -- 触发冰锥坠落特效（后续 tick）
            M.addBlizzardIceEffect(bz.cx, bz.cy, bz.radius)
            -- 延迟伤害文字到冰锥落地时刻（现在在玩家回合开始触发，有充足时间播放）
            M._damageTextDelay = 0.35 * 1.4
            -- 构造临时施法者（使用快照的 mAtk，保留玩家引用以便击杀奖励生效）
            local fakeAttacker = GS.player or { mAtk = bz.casterMAtk, atk = bz.casterMAtk }
            -- 临时覆盖 mAtk 用于伤害计算
            local origMAtk = fakeAttacker.mAtk
            fakeAttacker.mAtk = bz.casterMAtk
            for _, m in ipairs(GS.monsters) do
                if m.hp > 0 then
                    local ms = GS.unitSize(m)
                    local inRange = false
                    for dy = 0, ms - 1 do
                        if inRange then break end
                        for dx = 0, ms - 1 do
                            if inCircleRange(m.x + dx, m.y + dy, bz.cx, bz.cy, bz.radius) then
                                inRange = true
                                break
                            end
                        end
                    end
                    if inRange then
                        -- 闪避判定
                        if rollDodge(fakeAttacker, m, nil) then
                            M.addDamageText(m.x, m.y, "Miss", {255, 255, 255})
                        else
                            local wasChilled = m.chilled and (m.chilledTurns or 0) > 0
                            local dmg, isCrit = calcSkillDamage(fakeAttacker, m, { mul = bz.mul, useMagic = true, element = "ice" })
                            applyDamageAndCheck(fakeAttacker, m, dmg, "", {100, 200, 255}, isCrit, true)
                            -- 英雄单位免疫控制效果（减速/冻僵/冰冻）
                            if not isHeroUnit(m) then
                            -- 刷新减速
                            m.moveSlow = bz.slowVal
                            m.moveSlowTurns = bz.slowDur
                            -- 刷新冻僵 debuff（每次命中均重置持续时间，与初次施法一致）
                            if m.hp > 0 then
                                if WE.shouldUpgradeChillToFreeze() then
                                    local newDur = 1 + WE.getFreezeDurationMod()
                                    local oldDur = m.frozen or 0
                                    m.frozen = math.max(oldDur, newDur)
                                    if newDur > oldDur then
                                        M.addDamageText(m.x, m.y - 0.5, "冻结!", {100, 200, 255})
                                    end
                                else
                                    local newDur = 2 + WE.getChillDurationMod()
                                    local oldDur = m.chilledTurns or 0
                                    local hadChill = m.chilled and oldDur > 0
                                    m.chilled = 1
                                    m.chilledTurns = newDur
                                    m.chillStacks = math.min((m.chillStacks or 0) + 1, M.CHILL_MAX_STACKS)
                                    if not hadChill then
                                        M.addDamageText(m.x, m.y - 0.5, "冻僵!", {100, 200, 255})
                                    elseif m.chillStacks > 1 then
                                        M.addDamageText(m.x, m.y - 0.5, "冻僵 x" .. m.chillStacks, {100, 200, 255})
                                    end
                                end
                                -- 寒冰书：对已冻僵目标额外触发冰冻（zone tick 同样触发）
                                if (fakeAttacker.blizzardFreezeChance or 0) > 0 and wasChilled then
                                    if math.random(1, 100) <= fakeAttacker.blizzardFreezeChance then
                                        local dur = math.max(1, fakeAttacker.blizzardFreezeDuration or 1)
                                        local oldFrozen = m.frozen or 0
                                        m.frozen = math.max(oldFrozen, dur)
                                        if dur > oldFrozen then
                                            M.addDamageText(m.x, m.y - 0.5, "冰冻!", {150, 230, 255})
                                        end
                                    end
                                end
                            end
                            end -- isHeroUnit guard
                        end
                    end
                end
            end
            -- 恢复玩家原始 mAtk
            fakeAttacker.mAtk = origMAtk
            M._damageTextDelay = 0  -- 清除延迟
        end
    end
    M.removeDeadMonsters()
end

-- 怪物减速 debuff 递减（每回合调用一次）
function M.tickMonsterSlowDebuffs()
    for _, m in ipairs(GS.monsters) do
        if m.moveSlowTurns and m.moveSlowTurns > 0 then
            m.moveSlowTurns = m.moveSlowTurns - 1
            if m.moveSlowTurns <= 0 then
                m.moveSlow = 0
                m.moveSlowTurns = nil
            end
        end
    end
end

-- ====================================================================
-- 雷云术：在目标头顶创建跟随雷云（首次即命中）
-- ====================================================================
function M.performThunderCloud(attacker, target, skillId)
    local def = GS.SKILL_DEFS[skillId]
    if not def then return end

    GS.useSkill(skillId)
    M.addSkillCastText(attacker.x, attacker.y, skillId)
    local lv = GS.skillLevels[skillId] or 1
    local mul = GS.getSkillDmgMul(skillId)
    local casterMAtk = attacker.mAtk or 0
    local aoeRadius = (def.cloudAoeRadius or 8)
    local strikeRange = 1 + getAoeRangeBonus()  -- 每次打击的AOE范围（切比雪夫距离）
    local skillName = def.name

    -- 计算持续回合数（基础 + 等级突破）
    local duration = def.cloudDurationBase or 3
    if def.cloudDurationBreaks then
        for _, reqLv in ipairs(def.cloudDurationBreaks) do
            if lv >= reqLv then duration = duration + 1 end
        end
    end

    -- 屏幕震动
    GS.setScreenShake(0.4, 4, 0.05)

    -- 触发首次雷云攻击闪电特效
    M.addThunderCloudStrikeEffect(target.x, target.y, strikeRange)
    -- 伤害文字延迟到闪电劈下时刻（~0.08, duration=1.1）
    M._damageTextDelay = 0.08 * 1.1
    -- 首次立即造成伤害（以目标为中心的 AOE）
    M.thunderCloudStrike(attacker, target, aoeRadius, mul, skillName, strikeRange)
    M._damageTextDelay = 0  -- 清除延迟

    -- 创建雷云（跟随 target 引用，后续 tick 自动取 target.x/y）
    -- 检查是否已有雷云跟随同一目标（替换）
    local found = false
    for _, tc in ipairs(GS.thunderClouds) do
        if tc.target == target then
            tc.turnsLeft = duration
            tc.mul = mul
            tc.casterMAtk = casterMAtk
            tc.aoeRadius = aoeRadius
            tc.strikeRange = strikeRange
            tc.skillName = skillName
            tc.chainLightChance = attacker.thunderCloudChainLightChance or 0
            found = true
            break
        end
    end
    if not found then
        table.insert(GS.thunderClouds, {
            target = target,
            turnsLeft = duration,
            mul = mul, casterMAtk = casterMAtk,
            aoeRadius = aoeRadius, strikeRange = strikeRange,
            skillName = skillName,
            chainLightChance = attacker.thunderCloudChainLightChance or 0,
        })
    end
    playAttackSound()
end

-- 雷云打击：对目标为中心的 AOE 范围内怪物造成伤害
function M.thunderCloudStrike(attacker, centerTarget, aoeRadius, mul, skillName, strikeRange)
    strikeRange = strikeRange or 1
    local cx, cy = centerTarget.x, centerTarget.y
    local hitCount = 0
    local hitMonsters = {}  -- 命中后存活的目标，用于闪电链选取
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 then
            local ms = GS.unitSize(m)
            local inRange = false
            for dy = 0, ms - 1 do
                if inRange then break end
                for dx = 0, ms - 1 do
                    local mdx = math.abs(m.x + dx - cx)
                    local mdy = math.abs(m.y + dy - cy)
                    if math.max(mdx, mdy) <= strikeRange then
                        inRange = true
                        break
                    end
                end
            end
            if inRange then
                -- 闪避判定
                if rollDodge(attacker, m, nil) then
                    M.addDamageText(m.x, m.y, "Miss", {255, 255, 255})
                else
                    local dmg, isCrit = calcSkillDamage(attacker, m, { mul = mul, useMagic = true, element = "thunder" })
                    applyDamageAndCheck(attacker, m, dmg, "", {255, 220, 60}, isCrit, true)
                    -- 击晕判定（英雄单位免疫）
                    local tcDef = GS.SKILL_DEFS["m_thunder_cloud"]
                    if m.hp > 0 and tcDef and tcDef.stunChance and not m.stunned and not isHeroUnit(m) then
                        local chance = tcDef.stunChance
                        -- 失感：每层冻僵+5%晕眩概率
                        if m._numbingPending then
                            chance = chance + m._numbingPending * 5
                            m._numbingPending = nil
                        end
                        if math.random(1, 100) <= chance then
                            m.stunned = tcDef.stunDuration or 1
                            M.addDamageText(m.x, m.y - 0.5, "晕眩!", {255, 220, 60})
                        end
                    end
                    if m.hp > 0 then hitMonsters[#hitMonsters + 1] = m end
                    hitCount = hitCount + 1
                end
            end
        end
    end
    -- 雷电书：每次雷云打击最多触发一次闪电链，随机选一个存活目标
    local chainChance = attacker.thunderCloudChainLightChance or 0
    if chainChance > 0 and #hitMonsters > 0 and math.random(1, 100) <= chainChance then
        M.performChainLightning(attacker, hitMonsters[math.random(1, #hitMonsters)], "m_chain_light")
    end
    if hitCount == 0 then
        M.addDamageText(cx, cy - 0.5, "Miss", {255, 255, 255})
    end
end

-- ====================================================================
-- 雷云：回合 tick（跟随目标造成 AOE 伤害）
-- ====================================================================
function M.tickThunderClouds()
    if #GS.thunderClouds == 0 then return end

    for i = #GS.thunderClouds, 1, -1 do
        local tc = GS.thunderClouds[i]
        tc.turnsLeft = tc.turnsLeft - 1

        -- 目标死亡时，记录固定坐标，雷云留在原地
        if not tc.fixedX and (not tc.target or tc.target.hp <= 0) then
            if tc.target then
                tc.fixedX = tc.target.x
                tc.fixedY = tc.target.y
            end
            tc.target = nil  -- 解除引用
        end

        if tc.turnsLeft <= 0 then
            table.remove(GS.thunderClouds, i)
        else
            -- 确定当前打击中心坐标
            local cx, cy
            if tc.target and tc.target.hp > 0 then
                cx, cy = tc.target.x, tc.target.y
            elseif tc.fixedX then
                cx, cy = tc.fixedX, tc.fixedY
            else
                -- 无有效坐标，跳过
                goto continueTC
            end

            -- 使用快照的 mAtk 构造临时攻击者
            local fakeAttacker = GS.player or { mAtk = tc.casterMAtk, atk = tc.casterMAtk }
            local origMAtk = fakeAttacker.mAtk
            fakeAttacker.mAtk = tc.casterMAtk

            -- 触发雷云攻击闪电特效
            local sr = tc.strikeRange or 1
            M.addThunderCloudStrikeEffect(cx, cy, sr)
            -- 伤害文字延迟到闪电劈下时刻
            M._damageTextDelay = 0.08 * 1.1

            -- 以当前位置为中心打击
            local hitAny = false
            local tickHitMonsters = {}  -- 命中后存活的目标，用于闪电链选取
            for _, m in ipairs(GS.monsters) do
                if m.hp > 0 then
                    local ms = GS.unitSize(m)
                    local inRange = false
                    for dy = 0, ms - 1 do
                        if inRange then break end
                        for dx = 0, ms - 1 do
                            local mdx = math.abs(m.x + dx - cx)
                            local mdy = math.abs(m.y + dy - cy)
                            if math.max(mdx, mdy) <= sr then
                                inRange = true
                                break
                            end
                        end
                    end
                    if inRange then
                        -- 闪避判定
                        if rollDodge(fakeAttacker, m, nil) then
                            M.addDamageText(m.x, m.y, "Miss", {255, 255, 255})
                        else
                            local dmg, isCrit = calcSkillDamage(fakeAttacker, m, { mul = tc.mul, useMagic = true, element = "thunder" })
                            applyDamageAndCheck(fakeAttacker, m, dmg, "", {255, 220, 60}, isCrit, true)
                            if m.hp > 0 then tickHitMonsters[#tickHitMonsters + 1] = m end
                            hitAny = true
                        end
                    end
                end
            end
            -- 雷电书：每次 tick 最多触发一次闪电链，随机选一个存活目标
            local chainChance = tc.chainLightChance or 0
            if chainChance > 0 and #tickHitMonsters > 0 and math.random(1, 100) <= chainChance then
                local player = GS.player
                if player then
                    M.performChainLightning(player, tickHitMonsters[math.random(1, #tickHitMonsters)], "m_chain_light")
                end
            end

            M._damageTextDelay = 0  -- 清除延迟
            fakeAttacker.mAtk = origMAtk
            ::continueTC::
        end
    end
    M.removeDeadMonsters()

    -- 目标死亡时更新固定坐标（不移除）
    for _, tc in ipairs(GS.thunderClouds) do
        if not tc.fixedX and (not tc.target or tc.target.hp <= 0) then
            if tc.target then
                tc.fixedX = tc.target.x
                tc.fixedY = tc.target.y
            end
            tc.target = nil
        end
    end
end

-- ====================================================================
-- 闪电链（单体 + 弹射）
-- ====================================================================
function M.performChainLightning(attacker, target, skillId)
    local def = GS.SKILL_DEFS[skillId]
    if not def then return end

    GS.useSkill(skillId)
    M.addSkillCastText(attacker.x, attacker.y, skillId)
    local lv = GS.skillLevels[skillId] or 1
    local mul = GS.getSkillDmgMul(skillId)
    local bounceRange = (def.chainBounceRange or 3) + getAoeRangeBonus() + (attacker.thunderJarRange or 0)

    -- 计算最大弹射次数：基础 + 等级突破 + 养雷壶加成
    local maxBounce = def.chainBounceBase or 2
    local breaks = def.chainBounceBreaks or {3, 6, 10}
    for _, brk in ipairs(breaks) do
        if lv >= brk then maxBounce = maxBounce + 1 end
    end
    maxBounce = maxBounce + (attacker.thunderJarBounce or 0)

    -- 对单个目标造成伤害的内部函数（返回是否命中）
    local function hitTarget(m)
        -- 闪避判定
        if rollDodge(attacker, m, skillId) then
            M.addDamageText(m.x, m.y, "Miss", {255, 255, 255})
            return false
        end
        local dmg, isCrit = calcSkillDamage(attacker, m, { mul = mul, skillId = skillId, useMagic = true, element = "thunder" })
        applyDamageAndCheck(attacker, m, dmg, "", {255, 220, 60}, isCrit, true)
        -- 击晕判定（英雄单位免疫）
        if m.hp > 0 and def.stunChance and not m.stunned and not isHeroUnit(m) then
            local chance = def.stunChance
            -- 失感：每层冻僵+5%晕眩概率
            if m._numbingPending then
                chance = chance + m._numbingPending * 5
                m._numbingPending = nil
            end
            if math.random(1, 100) <= chance then
                m.stunned = def.stunDuration or 1
                M.addDamageText(m.x, m.y - 0.5, "晕眩!", {255, 220, 60})
            end
        end
        return true, dmg
    end

    -- 屏幕震动
    GS.setScreenShake(0.3, 2, 0.1)

    -- 收集链路径用于特效：{fromX, fromY, toX, toY}
    local chainPath = { { fx = attacker.x, fy = attacker.y, tx = target.x, ty = target.y } }

    -- 1) 命中主目标
    local mainHit, mainDmg = hitTarget(target)
    playAttackSound()

    -- 银鹿：法师闪电链触发额外闪电链弹射（弹射目标各施放一次新闪电链）
    if mainHit and mainDmg and mainDmg > 0 and not attacker.isMonster and not attacker.isCompanion
       and target.isMonster and not M._abyssBouncing and not attacker._silverDeerChainBouncing then
        local hasRangeBounce = (attacker.rangeBounceCount or 0) > 0
        if hasRangeBounce then
            local abyssBounces = M.countAbyssAffix("ranged_bounce")
            local rbCount = math.min(attacker.rangeBounceCount, abyssBounces)
            if rbCount > 0 then
                -- 从主目标周围找 rbCount 个新目标，对每个施放一次闪电链
                local rbDmgMul = attacker.rangeBounceDmgMul or 100
                local usedTargets = { [target] = true }
                for bi = 1, rbCount do
                    -- 找最近的未命中存活敌人
                    local bestT, bestD = nil, bounceRange + 1
                    for _, m in ipairs(GS.monsters) do
                        if m.hp > 0 and not usedTargets[m] then
                            local dist = GS.manhattanToUnit(target.x, target.y, m)
                            if dist <= bounceRange and dist < bestD then
                                bestD = dist
                                bestT = m
                            end
                        end
                    end
                    if not bestT then break end
                    usedTargets[bestT] = true
                    -- 对该目标施放一次新闪电链（伤害按银鹿倍率衰减，防止递归）
                    attacker._silverDeerChainBouncing = true
                    -- 缩放伤害倍率：银鹿弹射的闪电链伤害 = 原伤害 × rbDmgMul%
                    local origMul = mul
                    mul = origMul * rbDmgMul / 100
                    hitTarget(bestT)
                    -- 弹射的闪电链也有自己的链式弹射
                    local subChainPath = { { fx = target.x, fy = target.y, tx = bestT.x, ty = bestT.y } }
                    local subHitSet = { [bestT] = true }
                    -- 也排除主闪电链已命中的目标，避免重复打击
                    subHitSet[target] = true
                    local subCurrent = bestT
                    local subBounceCount = 0
                    while subBounceCount < maxBounce do
                        local subBest = nil
                        local subBestDist = bounceRange + 1
                        for _, m in ipairs(GS.monsters) do
                            if m.hp > 0 and not subHitSet[m] then
                                local dist = GS.manhattanToUnit(subCurrent.x, subCurrent.y, m)
                                if dist <= bounceRange and dist < subBestDist then
                                    subBestDist = dist
                                    subBest = m
                                end
                            end
                        end
                        if not subBest then break end
                        subHitSet[subBest] = true
                        subChainPath[#subChainPath + 1] = { fx = subCurrent.x, fy = subCurrent.y, tx = subBest.x, ty = subBest.y }
                        hitTarget(subBest)
                        subCurrent = subBest
                        subBounceCount = subBounceCount + 1
                    end
                    M.addLightningChainEffect(subChainPath)
                    if subBounceCount > 0 then
                        M.addDamageText(bestT.x, bestT.y - 0.5, "弹射×" .. subBounceCount, {240, 220, 60})
                    end
                    mul = origMul  -- 恢复原倍率
                    attacker._silverDeerChainBouncing = nil
                end
            end
        end
    end

    -- 2) 弹射逻辑：从已命中目标出发，寻找最近的未命中敌人
    local hitSet = { [target] = true }
    local current = target
    local bounceCount = 0

    while bounceCount < maxBounce do
        -- 在 current 的 bounceRange 曼哈顿距离内找最近的未命中存活敌人
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
        -- 记录弹射路径
        chainPath[#chainPath + 1] = { fx = current.x, fy = current.y, tx = best.x, ty = best.y }
        hitTarget(best)
        current = best
        bounceCount = bounceCount + 1
    end

    -- 触发闪电链特效
    M.addLightningChainEffect(chainPath)

    if bounceCount > 0 then
        M.addDamageText(attacker.x, attacker.y - 0.5,
            "弹射×" .. bounceCount, {240, 220, 60})
    end
end

-- ====================================================================
-- AOE 攻击（旋风斩等范围技能）
-- ====================================================================
function M.performAOE(attacker, skillId)
    local def = GS.SKILL_DEFS[skillId]
    if not def then return end

    -- 扣蓝、设置冷却
    GS.useSkill(skillId)
    M.addSkillCastText(attacker.x, attacker.y, skillId)

    local mul = GS.getSkillDmgMul(skillId)

    -- AOE范围加成（深渊词缀）
    local aoeBonus = getAoeRangeBonus()
    local whirlRange = 1 + aoeBonus

    -- 添加旋风斩特效和音效
    M.addWhirlwindEffect(attacker.x, attacker.y, whirlRange)
    M.playWhirlwindSound()
    -- 屏幕震动
    GS.setScreenShake(0.4, 3, 0.15)

    -- 收集周围格内所有存活怪物
    local wTag = getPlayerWeaponTag()
    local hitCount = 0
    forEachAdjacentMonster(attacker, function(target)
        if rollDodge(attacker, target, skillId) then
            M.addDamageText(target.x, target.y, "Miss", {255, 255, 255})
        else
            local dmg, isCrit = calcSkillDamage(attacker, target, { mul = mul, skillId = skillId })
            applyDamageAndCheck(attacker, target, dmg, "", {255, 255, 255}, isCrit)
        end
        hitCount = hitCount + 1
    end, whirlRange)

    playAttackSound(wTag)

    if hitCount == 0 then
        M.addDamageText(attacker.x, attacker.y - 0.5, "Miss", {255, 255, 255})
    end

    -- 千军令：手动旋风斩触发幻影
    if skillId == "whirlwind" then
        M.triggerWhirlPhantoms(attacker)
    end
end

-- ====================================================================
-- 散射：对主目标 + 攻击范围内额外目标射出箭矢
-- ====================================================================
function M.performScatter(attacker, mainTarget, skillId)
    local def = GS.SKILL_DEFS[skillId]
    if not def then return end

    -- 扣蓝、设置冷却
    GS.useSkill(skillId)
    M.addSkillCastText(attacker.x, attacker.y, skillId)

    local mul = GS.getSkillDmgMul(skillId)
    local extraCount = def.scatterExtra or 2

    -- 收集攻击范围内除主目标外的存活怪物
    local candidates = {}
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 and m ~= mainTarget then
            local d = GS.manhattanToUnit(attacker.x, attacker.y, m)
            if d <= attacker.atkRange then
                table.insert(candidates, m)
            end
        end
    end
    -- 按血量比例排序（优先打残血）
    table.sort(candidates, function(a, b)
        return (a.hp / a.maxHp) < (b.hp / b.maxHp)
    end)

    -- 构建目标列表：主目标 + 额外目标
    local targets = { mainTarget }
    for i = 1, math.min(extraCount, #candidates) do
        table.insert(targets, candidates[i])
    end

    -- 对每个目标射箭并计算伤害
    local wTag = getPlayerWeaponTag()
    for _, target in ipairs(targets) do
        -- 添加箭矢特效
        M.addAttackEffect(attacker.x, attacker.y, target.x, target.y, wTag)

        -- 伤害计算
        local dmg, isCrit = calcSkillDamage(attacker, target, { mul = mul, skillId = skillId })
        applyDamageAndCheck(attacker, target, dmg, "", {255, 255, 255}, isCrit)
    end

    -- 标记主目标
    tryMarkTarget(attacker, mainTarget)

    playAttackSound(wTag)
    -- 屏幕震动
    GS.setScreenShake(0.3, 2, 0.1)
end

-- ====================================================================
-- 旋风斩特效
-- ====================================================================
function M.addWhirlwindEffect(x, y, radius)
    table.insert(GS.whirlwindEffects, {
        x = x, y = y,
        radius = radius or 1,
        timer = 0, duration = 0.7,
    })
end

-- ====================================================================
-- 火球术特效（弹道 + 落地爆炸扩散）
-- ====================================================================
function M.addFireballEffect(fromX, fromY, targetX, targetY, radius)
    table.insert(GS.fireballEffects, {
        fx = fromX, fy = fromY,
        x = targetX, y = targetY,
        radius = radius or 2,
        timer = 0, duration = 0.9,
    })
end

-- ====================================================================
-- 陨石术特效（从天降落 + 巨大冲击爆炸）
-- ====================================================================
function M.addMeteorEffect(targetX, targetY, radius)
    table.insert(GS.meteorEffects, {
        x = targetX, y = targetY,
        radius = radius or 2,
        timer = 0, duration = 1.8,
    })
    -- 屏幕震动（delay 与陨石落地时刻对齐：impactT=0.33 * duration=1.8 ≈ 0.59s）
    GS.setScreenShake(0.8, 8, 0.59)
end

-- ====================================================================
-- 冰环术特效
-- ====================================================================
function M.addIceRingEffect(centerX, centerY, radius)
    table.insert(GS.iceRingEffects, {
        x = centerX, y = centerY,
        radius = radius or 1,
        timer = 0, duration = 1.2,
    })
end

-- ====================================================================
-- 闪电链特效（多段链式闪电）
-- ====================================================================
function M.addLightningChainEffect(chainPath)
    table.insert(GS.lightningChainEffects, {
        chain = chainPath,   -- {{fx,fy,tx,ty}, ...}
        timer = 0,
        duration = 0.25 + #chainPath * 0.22, -- 每段0.22秒 + 缓冲
    })
end

-- ====================================================================
-- 落雷术特效（天降粗壮雷电 + 冲击）
-- ====================================================================
function M.addThunderStrikeEffect(targetX, targetY, radius)
    -- 落雷术弹道ID：优先复用 performAttack 预分配的 ID，否则新分配
    local projId
    if M._currentProjectileId then
        projId = M._currentProjectileId
    else
        M._projectileIdCounter = M._projectileIdCounter + 1
        projId = M._projectileIdCounter
        M._currentProjectileId = projId
    end
    table.insert(GS.thunderStrikeEffects, {
        x = targetX, y = targetY,
        radius = radius or 1,
        timer = 0, duration = 1.0,
        projectileId = projId,
    })
    GS.setScreenShake(0.5, 6, 0.28)
end

-- ====================================================================
-- 雷云攻击闪电特效（每次 tick 或首次施法时触发）
-- ====================================================================
function M.addThunderCloudStrikeEffect(cx, cy, strikeRange)
    table.insert(GS.thunderCloudStrikeEffects, {
        x = cx, y = cy,
        radius = strikeRange or 1,
        timer = 0, duration = 1.1,
    })
    GS.setScreenShake(0.35, 4, 0.08)
end

-- ====================================================================
-- 暴风雪冰锥坠落特效（每次 tick 触发）
-- ====================================================================
function M.addBlizzardIceEffect(cx, cy, radius)
    table.insert(GS.blizzardIceEffects, {
        cx = cx, cy = cy, radius = radius,
        timer = 0, duration = 1.4,
    })
    GS.setScreenShake(0.4, 4, 0.45)
end

-- ====================================================================
-- 火焰护盾烧伤特效（反伤时触发）
-- ====================================================================
function M.addBurnEffect(x, y)
    table.insert(GS.burnEffects, {
        x = x, y = y,
        timer = 0, duration = 0.9,
    })
end

-- ====================================================================
-- 魔法盾激活/关闭特效（蓝紫色护盾波纹）
-- ====================================================================
function M.addMagicShieldEffect(x, y, isActivate)
    table.insert(GS.magicShieldEffects, {
        x = x, y = y,
        timer = 0, duration = 0.8,
        isActivate = isActivate,
    })
end

-- ====================================================================
-- 冰墙术创建特效（冰晶从地面升起）
-- ====================================================================
function M.addIceWallCreateEffect(cells)
    table.insert(GS.iceWallCreateEffects, {
        cells = cells,
        timer = 0, duration = 1.0,
    })
end

-- ====================================================================
-- 闪烁传送特效（起点消散 + 终点出现）
-- ====================================================================
function M.addBlinkEffect(fromX, fromY, toX, toY)
    table.insert(GS.blinkEffects, {
        fx = fromX, fy = fromY,
        tx = toX, ty = toY,
        timer = 0, duration = 0.9,
    })
end

end  -- sub.init

return sub
