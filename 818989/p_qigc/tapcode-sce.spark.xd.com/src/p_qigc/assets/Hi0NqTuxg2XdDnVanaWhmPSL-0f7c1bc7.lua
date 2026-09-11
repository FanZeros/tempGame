-- ============================================================================
-- WeatherEffects.lua — 天气战斗效果模块（纯机制，不含视觉特效）
-- ============================================================================
-- 晴天：无效果（标准天气）
-- 暴晒：火伤+15%/冰伤-15%/雷伤+7%，灼伤持续+4，燃烧地面持续+4，
--        冻僵持续-1，蒸腾+50%，爆炸+50%
-- 下雨：冰伤+15%/火伤-15%/雷伤+7%，潮湿(移动-1,攻速-10)，
--        冻僵冻结持续+2，施加冻僵33%升级冻结，燃烧地面减半，失感+100%
-- 狂风：顺风(移动+1,射程+1,弹道伤害+15%)，
--        逆风(移动-1,射程-1,弹道伤害-15%)，
--        侧风(弹道命中率固定-20%)
-- ============================================================================

local GS = require("GameState")
local BoardOverlay = require("BoardOverlay")

local M = {}

-- 8方向向量（与 WindEffect.lua 一致）
local DIR_VECTORS = {
    [1] = { 0, -1},   -- 北
    [2] = { 1, -1},   -- 东北
    [3] = { 1,  0},   -- 东
    [4] = { 1,  1},   -- 东南
    [5] = { 0,  1},   -- 南
    [6] = {-1,  1},   -- 西南
    [7] = {-1,  0},   -- 西
    [8] = {-1, -1},   -- 西北
}

--- 判断是否室内（室内不受天气影响）
function M.isIndoor()
    if BoardOverlay.active and BoardOverlay.overlayType == "town" then
        return BoardOverlay.inSubScene()
    end
    return GS.isIndoorStage() or BoardOverlay.inSubScene()
end

--- 天气效果是否激活（室外才生效）
function M.isActive()
    return not M.isIndoor()
end

-- ====================================================================
-- 元素伤害倍率（全场所有单位）
-- ====================================================================
---@param element string|nil 元素类型 "fire"/"ice"/"thunder"
---@return number 伤害倍率（1.0 = 无变化）
function M.getElementDmgMul(element)
    if not element or not M.isActive() then return 1.0 end
    if GS.isScorching then
        if element == "fire" then return 1.15
        elseif element == "ice" then return 0.85
        elseif element == "thunder" then return 1.07
        end
    elseif GS.isRaining then
        if element == "ice" then return 1.15
        elseif element == "fire" then return 0.85
        elseif element == "thunder" then return 1.07
        end
    end
    return 1.0
end

-- ====================================================================
-- 灼伤 DEBUFF 持续时间修正值（加到基础持续回合上）
-- ====================================================================
---@return number 修正值（暴晒 +4，其他 0）
function M.getBurnDurationMod()
    if not M.isActive() then return 0 end
    if GS.isScorching then return 4 end
    return 0
end

-- ====================================================================
-- 燃烧地面持续时间修正（返回修正后的持续回合数）
-- ====================================================================
---@param baseDuration number 基础持续回合
---@return number 修正后的持续回合
function M.adjustBurningGroundDuration(baseDuration)
    if not M.isActive() then return baseDuration end
    if GS.isScorching then return baseDuration + 4 end
    if GS.isRaining then return math.max(1, math.floor(baseDuration * 0.5)) end
    return baseDuration
end

-- ====================================================================
-- 冻僵持续时间修正值
-- ====================================================================
---@return number 修正值（暴晒 -1，下雨 +2，其他 0）
function M.getChillDurationMod()
    if not M.isActive() then return 0 end
    if GS.isScorching then return -1 end
    if GS.isRaining then return 2 end
    return 0
end

-- ====================================================================
-- 冻结持续时间修正值
-- ====================================================================
---@return number 修正值（下雨 +2，其他 0）
function M.getFreezeDurationMod()
    if not M.isActive() then return 0 end
    if GS.isRaining then return 2 end
    return 0
end

-- ====================================================================
-- 施加冻僵时是否升级为冻结（下雨: 33%概率）
-- ====================================================================
---@return boolean 是否升级为冻结
function M.shouldUpgradeChillToFreeze()
    if not M.isActive() then return false end
    if GS.isRaining then return math.random(1, 100) <= 33 end
    return false
end

-- ====================================================================
-- 蒸腾伤害加成系数（暴晒: 0.20→0.30，即+50%）
-- ====================================================================
---@return number 蒸腾加成系数（默认 0.20）
function M.getEvaporationBonus()
    if not M.isActive() then return 0.20 end
    if GS.isScorching then return 0.30 end
    return 0.20
end

-- ====================================================================
-- 爆炸伤害倍率（暴晒: ×1.5，即+50%）
-- ====================================================================
---@return number 爆炸伤害倍率
function M.getExplosionMul()
    if not M.isActive() then return 1.0 end
    if GS.isScorching then return 1.5 end
    return 1.0
end

-- ====================================================================
-- 失感晕眩倍率（正常 ×2，下雨 ×4，即效果+100%）
-- ====================================================================
---@return number 晕眩概率倍率
function M.getNumbingMul()
    if not M.isActive() then return 2 end
    if GS.isRaining then return 4 end
    return 2
end

-- ====================================================================
-- 下雨：潮湿状态 - 移动距离修正
-- ====================================================================
---@return number 移动距离修正值（下雨不再减速）
function M.getRainMoveMod()
    return 0
end

-- ====================================================================
-- 下雨：潮湿状态 - 攻击速度修正
-- ====================================================================
---@return number 攻击速度修正值（下雨 -10）
function M.getRainAtkSpeedMod()
    if not M.isActive() then return 0 end
    if GS.isRaining then return -10 end
    return 0
end

-- ====================================================================
-- 狂风：判断攻击方向与风向的关系（支持复合状态）
-- ====================================================================
-- 不受风影响的法师技能（非弹道类法术）
local NON_PROJECTILE_MAGE_SKILLS = {
    m_lightning = true,     -- 电击术（闪电瞬发）
    m_ice_ring = true,      -- 冰环术（AOE）
    m_chain_light = true,   -- 闪电链（弹射）
    m_fire_shield = true,   -- 火焰护盾（防御）
    m_ice_wall = true,      -- 冰墙术（召唤物）
    m_thunder = true,       -- 落雷术（天降）
    m_magic_shield = true,  -- 魔法盾（防御）
}

--- 纯类型判断：本次攻击是否为弹道类（不检查天气状态）
--- 可用于攻击范围显示等不依赖天气激活状态的场景
---@param attacker table 攻击者单位
---@param skillId string|nil 技能ID
---@param weaponTag string|nil 武器标签（玩家用，怪物可nil）
---@return boolean
function M.isProjectileType(attacker, skillId, weaponTag)
    -- 怪物：查 RANGED_MONSTER_IDS 或词缀远程（由 Combat 调用时已知）
    if attacker.isMonster then
        return attacker._isRangedMonster == true
    end
    -- 猎犬等伙伴不算弹道
    if attacker.isCompanion then return false end
    -- 技能判定
    if skillId then
        local sDef = GS.SKILL_DEFS and GS.SKILL_DEFS[skillId]
        if sDef then
            -- 投掷类技能（throwSkill 标记）
            if sDef.throwSkill then return true end
            -- 泼沙已改为范围技能，不再算弹道
            -- 追身箭现在走 performAttack 普攻流程，弹道由 performAttack 自动处理
            -- 法术技能：排除非弹道法术
            if sDef.useMagic then
                return not NON_PROJECTILE_MAGE_SKILLS[skillId]
            end
        end
    end
    -- 武器普攻判定
    local wTag = weaponTag
    if not wTag then return false end
    return wTag == "弓" or wTag == "法杖"
end

--- 判断本次攻击是否为弹道类且受风效果影响（含天气状态检查）
---@param attacker table 攻击者单位
---@param skillId string|nil 技能ID
---@param weaponTag string|nil 武器标签（玩家用，怪物可nil）
---@return boolean
function M.isProjectileAttack(attacker, skillId, weaponTag)
    if not M.isActive() or not GS.isWindy then return false end
    return M.isProjectileType(attacker, skillId, weaponTag)
end

--- 判断攻击方向与风向的关系（支持复合状态）
--- 返回两个布尔值：isDownOrUp, isCross
---   downwind:  isDown=true,  isCross=false
---   upwind:    isDown=false, isCross=false  (通过 dot<0 区分)
---   crosswind: isDown=false, isCross=true   (纯侧风)
---   boundary:  isDown=true,  isCross=true   (顺+侧 or 逆+侧)
---@param ax number 攻击者 x
---@param ay number 攻击者 y
---@param tx number 目标 x
---@param ty number 目标 y
---@return boolean isDownwind 是否包含顺风分量
---@return boolean isUpwind 是否包含逆风分量
---@return boolean isCrosswind 是否包含侧风分量
function M.getWindRelation(ax, ay, tx, ty)
    if not M.isActive() or not GS.isWindy then return false, false, false end

    local wv = DIR_VECTORS[GS.windDirection] or {1, 0}
    local wdx, wdy = wv[1], wv[2]

    -- 攻击方向（棋盘格子差值）
    local adx, ady = tx - ax, ty - ay
    if adx == 0 and ady == 0 then return false, false, false end

    -- 用风向分量与攻击方向分量的点积和叉积来判断
    -- dot > 0 → 顺风分量, dot < 0 → 逆风分量, cross > 0 → 侧风分量
    local dot = adx * wdx + ady * wdy
    local cross = math.abs(adx * wdy - ady * wdx)

    -- 以45°为分界：dot和cross相等时为边界，两种效果叠加
    local isDown = (dot > 0) and (dot >= cross)   -- 顺风区域（含边界）
    local isUp   = (dot < 0) and (-dot >= cross)  -- 逆风区域（含边界）
    local isCross = (cross > 0) and (cross >= math.abs(dot))  -- 侧风区域（含边界）

    return isDown, isUp, isCross
end

-- ====================================================================
-- 狂风：获取风向分量（用于 BFS 路径标记）
-- ====================================================================
---@return number, number 风向 x/y 分量（各为 -1/0/1），无风返回 0,0
function M.getWindDirComponents()
    if not M.isActive() or not GS.isWindy then return 0, 0 end
    local wv = DIR_VECTORS[GS.windDirection] or {1, 0}
    return wv[1], wv[2]
end

-- ====================================================================
-- 狂风：根据路径标记计算移动距离加成
-- ====================================================================
-- flags 位定义：bit0=走过风向x分量, bit1=走过风向y分量,
--               bit2=走过逆风x分量, bit3=走过逆风y分量
---@param flags number 路径标记位（0~15）
---@param wdx number 风向 x 分量
---@param wdy number 风向 y 分量
---@return number 移动距离加成（+1/0/-1）
function M.calcWindMoveBonus(flags, wdx, wdy)
    if wdx == 0 and wdy == 0 then return 0 end
    local hasDown, hasUp
    if wdx ~= 0 and wdy ~= 0 then
        -- 45度风：任一分量方向走到即算顺/逆风，两者同时触发则抵消
        hasDown = (flags & 1 ~= 0) or (flags & 2 ~= 0)
        hasUp   = (flags & 4 ~= 0) or (flags & 8 ~= 0)
    elseif wdx ~= 0 then
        hasDown = (flags & 1 ~= 0)
        hasUp   = (flags & 4 ~= 0)
    else
        hasDown = (flags & 2 ~= 0)
        hasUp   = (flags & 8 ~= 0)
    end
    return (hasDown and 1 or 0) - (hasUp and 1 or 0)
end

-- ====================================================================
-- 狂风：根据移动方向更新路径标记位
-- ====================================================================
---@param flags number 当前标记位
---@param dx number 移动方向 x（-1/0/1）
---@param dy number 移动方向 y（-1/0/1）
---@param wdx number 风向 x 分量
---@param wdy number 风向 y 分量
---@return number 更新后的标记位
function M.updateWindFlags(flags, dx, dy, wdx, wdy)
    if wdx ~= 0 and dx == wdx  then flags = flags | 1 end  -- 顺风x
    if wdy ~= 0 and dy == wdy  then flags = flags | 2 end  -- 顺风y
    if wdx ~= 0 and dx == -wdx then flags = flags | 4 end  -- 逆风x
    if wdy ~= 0 and dy == -wdy then flags = flags | 8 end  -- 逆风y
    return flags
end

-- ====================================================================
-- 狂风：弹道射程修正（顺风+1，逆风-1，边界也生效）
-- ====================================================================
---@return number 射程修正值（+1/-1/0）
function M.getWindRangeMod(ax, ay, tx, ty)
    local isDown, isUp, _ = M.getWindRelation(ax, ay, tx, ty)
    if isDown then return 1 end
    if isUp then return -1 end
    return 0
end

-- ====================================================================
-- 狂风：弹道伤害倍率（顺风+15%，逆风-15%，边界也生效）
-- ====================================================================
---@return number 伤害倍率
function M.getWindProjectileDmgMul(ax, ay, tx, ty)
    local isDown, isUp, _ = M.getWindRelation(ax, ay, tx, ty)
    if isDown then return 1.15 end
    if isUp then return 0.85 end
    return 1.0
end

-- ====================================================================
-- 狂风：弹道命中固定惩罚（侧风：命中率-20%）
-- ====================================================================
---@return number 命中率固定减值（0 = 无惩罚，0.20 = 侧风惩罚）
function M.getWindProjectileHitPenalty(ax, ay, tx, ty)
    local _, _, isCross = M.getWindRelation(ax, ay, tx, ty)
    if isCross then return 0.10 end
    return 0
end

return M
