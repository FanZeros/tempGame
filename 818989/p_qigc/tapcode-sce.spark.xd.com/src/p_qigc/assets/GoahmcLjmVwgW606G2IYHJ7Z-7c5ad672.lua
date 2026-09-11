-- ====================================================================
-- data/SkillDefs.lua - 技能定义数据（从 GameState.lua 提取）
-- ====================================================================
-- 纯数据模块，desc函数中通过require("GameState")读取技能等级以动态展示
-- 用法: local SKILL_DEFS = require("data.SkillDefs")
-- ====================================================================

return {
    strike       = { name = "强击",       col = {220, 160, 60},  type = "active",
                     cd = 2, mpCost = 8, mpCostPerLv = 1, dmgMul = 1.2, dmgMulPerLv = 0.05,
                     reqWeaponTag = "单手剑",
                     desc = function(lv)
                         local mul = math.floor((1.2 + (lv - 1) * 0.05) * 100 + 0.5)
                         return "蓄力发动强力攻击，根据物理攻击力，对单体目标造成" .. mul .. "%伤害。"
                     end },
    hp_up        = { name = "生命值UP",   col = {80, 200, 80},   type = "passive",
                     bonus = "maxHp", bonusPct = true, bonusPerLv = 1, bonusMaxLvExtra = 10,
                     desc = function(lv)
                         local total = 1 * lv
                         return "提高" .. total .. "%最大生命值（1%/等级）。"
                     end },

    counter      = { name = "反击",       col = {80, 160, 200},  type = "passive",
                     procType = "counter", procChancePerLv = 3, counterDmgRate = 0.65,
                     condTag = "单手剑",
                     desc = function(lv)
                         local chance = 3 * lv
                         local dmg = 65
                         local maxCount = 1
                         return "伺机而动。被近战范围内的敌人攻击时有" .. chance .. "%概率进行反击，根据物理攻击力，对攻击你的敌人造成" .. dmg .. "%伤害。每回合最多" .. maxCount .. "次。"
                     end },
    whirlwind    = { name = "旋风斩",     col = {100, 200, 100}, type = "active",
                     cd = 2, mpCost = 6, mpCostPerLv = 1, dmgMul = 0.8, dmgMulPerLv = 0.05,
                     aoe = true, reqWeaponTag = "单手剑",
                     desc = function(lv)
                         local mul = math.floor((0.8 + (lv - 1) * 0.05) * 100 + 0.5)
                         return "将武器舞成旋风。根据物理攻击力，对以自身为中心3x3范围的所有敌人造成" .. mul .. "%伤害。"
                     end },
    sword_prof   = { name = "剑术熟练",   col = {180, 140, 220}, type = "passive",
                     condTag = "单手剑",
                     condBonus = { dmgPct = 1, hitFlat = 2 },
                     desc = function(lv)
                         local dmg = 1 * lv
                         local hit = 2 * lv
                         return "提高使用单手剑时造成的伤害" .. dmg .. "%（1%/等级），命中值" .. hit .. "点（2点/等级）。"
                     end },
    mighty       = { name = "攻击力UP",   col = {220, 120, 60},  type = "passive",
                     bonus = "atk", bonusPct = true, bonusPerLv = 1, bonusMaxLvExtra = 10,
                     desc = function(lv)
                         local total = 1 * lv
                         return "提高" .. total .. "%物理攻击力（1%/等级）。"
                     end },
    shield_master= { name = "盾牌专精",   col = {80, 120, 200},  type = "passive",
                     condTag = "盾",
                     shieldBlockChancePerLv = 2, shieldBlockConRatioPerLv = 0.05,
                     reqSkill = "shield_prof", reqSkillLv = 10,
                     desc = function(lv)
                         local chance = 2 * lv
                         local conRatio = string.format("%.2f", 0.05 * lv)
                         return "提高使用盾牌时的格挡概率" .. chance .. "%（2%/等级），根据体质提高盾牌格挡伤害，每1点体质额外格挡" .. conRatio .. "点伤害（0.05点/等级）。"
                     end },
    w_blood_drink = { name = "饮血", col = {180, 40, 40}, type = "passive",
                     desc = function(lv)
                         local capPct = 2 * lv
                         return "你的过量吸血的50%会储存为护甲值抵挡伤害。护甲值存储上限为最大生命值的" .. capPct .. "%（2%/等级）。"
                     end },
    charge       = { name = "冲锋",       col = {220, 130, 50},  type = "active",
                     cd = 6, mpCost = 12, mpCostPerLv = 1, skillRange = 3,
                     charge = true,
                     cdBreaks = {3, 6, 10},   -- 3/6/10级各-1冷却
                     rangeBreaks = {5},        -- 5级+1施法距离
                     chargeLifestealPerLv = 3, -- 每级3%吸血
                     desc = function(lv)
                         local lifesteal = 3 * lv
                         return "战士向目标发起冲锋，并发动一次必定暴击的普通攻击，对目标施加1回合晕眩。冲锋技能有" .. lifesteal .. "%（3%/等级）吸血效果。冲锋技能在3/6/10级时冷却时间减少1回合，在5级时施展距离增加1格。"
                     end },
    w_hp_up      = { name = "生命值UP",   col = {80, 200, 80},   type = "passive",
                     bonus = "maxHp", bonusPct = true, bonusPerLv = 1,
                     desc = function(lv)
                         return "提高" .. (1 * lv) .. "%最大生命值（1%/等级）。"
                     end },
    charge_roar  = { name = "冲锋怒吼",   col = {240, 160, 40},  type = "passive",
                     reqSkill = "charge", reqSkillLv = 5,
                     chargeRoarDmgPerLv = 1,    -- 每级+1%伤害加成
                     chargeRoarReducePerLv = 1, -- 每级+1%伤害减免
                     desc = function(lv)
                         local dmgPct = 1 * lv
                         local reducePct = 1 * lv
                         return "冲锋后获得1回合战意激昂：伤害提高" .. dmgPct .. "%（1%/等级），受到伤害减少" .. reducePct .. "%（1%/等级）。持续到冲锋后的下回合结束。"
                     end },
    pwr_stk      = { name = "强化强击",   col = {230, 170, 50},  type = "passive",
                     enhance = "strike", mpCostRedPerLv = 1, dmgMulAddPerLv = 0.05,
                     cdRedAtMax = 1, reqSkill = "strike",
                     desc = function(lv)
                         local dmgAdd = 5 * lv
                         local mpRed = 1 * lv
                         return '强化你的"强击"技能，提高"强击"伤害' .. dmgAdd .. '%（5%/等级），降低MP消耗' .. mpRed .. '点（-1点/等级）。本技能满级时额外降低强击冷却时间1回合。'
                     end },
    shield_bash  = { name = "盾击",       col = {120, 150, 200}, type = "active",
                     cd = 3, mpCost = 10, mpCostPerLv = 1, dmgMul = 1.0, dmgMulPerLv = 0,
                     stunChance = 50, stunChancePerLv = 5, stunMaxChance = 95, stunDuration = 1,
                     stunDurBP = {[3] = 1, [6] = 1, [10] = 1},
                     reqSkill = "shield_prof", reqSkillLv = 5, reqLeftCategory = "盾牌",
                     desc = function(lv)
                         local mul = 100
                         local stun = math.min(50 + 5 * lv, 95)
                         local dur = 1
                         if lv >= 3 then dur = dur + 1 end
                         if lv >= 6 then dur = dur + 1 end
                         if lv >= 10 then dur = dur + 1 end
                         return '使用盾牌猛击敌人，根据物理攻击力，造成' .. mul .. '%伤害，并有' .. stun .. '%概率击晕敌人，附加' .. dur .. '回合"晕眩"状态。'
                     end },
    cleave       = { name = "顺劈",       col = {180, 200, 80},  type = "passive",
                     cleave = true, cleavePct = 33, cleavePctPerLv = 3, condTag = "单手剑",
                     reqSkill = "whirlwind", reqSkillLv = 10,
                     desc = function(lv)
                         local pct = 33 + (lv - 1) * 3
                         return "横向大范围的攻击技巧，普通攻击造成的伤害有" .. pct .. "%溅射至侧方和斜前方的所有敌人。"
                     end },
    crit_rate    = { name = "物理暴击值UP",   col = {255, 100, 80},  type = "passive",
                     bonus = "critVal", bonusPct = true, bonusPerLv = 1,
                     reqSkill = "sword_prof", reqSkillLv = 5,
                     desc = function(lv)
                         local total = 1 * lv
                         return "提高物理暴击值" .. total .. "%（1%/等级，至少" .. total .. "点）。"
                     end },
    sup_stk      = { name = "超强击",     col = {240, 180, 40},  type = "active",
                     cd = 1, mpCost = 15, mpCostPerLv = 2, dmgMul = 2.1, dmgMulPerLv = 0.1,
                     enhancedAs = "strike", reqSkill = "pwr_stk", reqWeaponTag = "单手剑",
                     desc = function(lv)
                         local mul = math.floor((2.1 + (lv - 1) * 0.1) * 100 + 0.5)
                         return '升级"强击"技能，积蓄更大的力量发动强力攻击。根据物理攻击力，对单体目标造成' .. mul .. '%伤害。"强化强击"的效果对本技能亦有作用。'
                     end },
    shield_prof  = { name = "盾牌熟练",   col = {100, 130, 190}, type = "passive",
                     shieldProf = true, blockAmountPerLv = 1, blockChancePerLv = 2,
                     condTag = "盾",
                     desc = function(lv)
                         local chance = 2 * lv
                         local amount = 1 * lv
                         return "提高你使用盾牌时的格挡概率" .. chance .. "%（2%/等级），格挡伤害" .. amount .. "点（1点/等级）。"
                     end },
    deriv_storm  = { name = "衍生飓风",   col = {80, 220, 160},  type = "passive",
                     derivStorm = true, derivBasePct = 55, derivPctPerLv = 5,
                     condTag = "单手剑", reqSkill = "cleave", reqSkillLv = 5,
                     desc = function(lv)
                         local pct = 55 + (lv - 1) * 5
                         return '将剑挥舞成小型旋风收尾的战斗技巧。每回合结束时发动一次小型旋风斩，根据物理攻击力，对以自身为中心3x3范围内的所有敌人造成' .. pct .. '%伤害。'
                     end },
    sword_master = { name = "剑术专精",   col = {160, 120, 220}, type = "passive",
                     condTag = "单手剑",
                     condBonus = { dmgPct = 1.5, atkSpdFlat = 1 },
                     reqSkill = "sword_prof", reqSkillLv = 10,
                     desc = function(lv)
                         local dmg = string.format("%.1f", 1.5 * lv)
                         local spd = 1 * lv
                         return '提高使用单手剑时造成的伤害' .. dmg .. '%（1.5%/等级），提高攻击速度' .. spd .. '点（1点/等级）。'
                     end },
    dual_wield   = { name = "双手持握",   col = {200, 160, 60},  type = "passive",
                     dualWield = true, dualWieldAtkSpdPenalty = 50,
                     dualWieldWeaponAtkBonusBase = 75, dualWieldWeaponAtkBonusPerLv = 5,
                     dualWieldExtraChancePerLv = 3, dualWieldExtraDmgMul = 0.5,
                     condTag = "单手剑", condRequireEmptyLeft = true,
                     desc = function(lv)
                         local atkBonus = 75 + 5 * lv
                         local extraChance = 3 * lv
                         return "使用双手同时握住单手剑进行攻击的技巧，攻击速度-50。右手武器栏所装备的武器基础攻击力加成提高" .. atkBonus .. "%（+5%/等级）。普通攻击有" .. extraChance .. "%概率（3%/等级）造成额外50%伤害。"
                     end },
    mst_stk      = { name = "碎星",       col = {255, 200, 50},  type = "active",
                     cd = 2, mpCost = 23, mpCostPerLv = 3, dmgMul = 4.3, dmgMulPerLv = 0.3,
                     reqSkill = "sup_stk", cdReducedBy = "sup_stk", reqWeaponTag = "单手剑",
                     desc = function(lv)
                         local mul = math.floor((4.3 + (lv - 1) * 0.3) * 100 + 0.5)
                         return '一击似乎可以击碎星辰。根据物理攻击力，对单体目标造成' .. mul .. '%伤害。"碎星"处于冷却状态时，使用"超强击"会使"碎星"剩余冷却时间减少1回合。'
                     end },
    mst_counter  = { name = "复仇",       col = {60, 180, 220},  type = "passive",
                     mstCounter = true, mstCounterChance = 53, mstCounterChancePerLv = 3,
                     mstCounterDmgRate = 0.73, mstCounterDmgRatePerLv = 0.03, mstCounterTrueDmg = true,
                     condTag = "单手剑",
                     desc = function(lv)
                         local chance = 53 + (lv - 1) * 3
                         local dmg = math.floor((0.73 + (lv - 1) * 0.03) * 100 + 0.5)
                         return '升级"反击"技能。被近战范围内的敌人攻击时有' .. chance .. '%概率进行复仇反击，根据物理攻击力，造成' .. dmg .. '%的真实伤害。每回合不限次数。'
                     end },
    mst_whirl    = { name = "风暴",       col = {60, 220, 80},   type = "active",
                     cd = 3, mpCost = 52, mpCostPerLv = 2,
                     selfCast = true, stormBuff = true, stormDuration = 3,
                     stormStartCount = 1, stormStartBreaks = {7},
                     stormEndCount = 0, stormEndBreaks = {4, 10},
                     stormDurBreaks = {2, 3, 5, 6, 8, 9},
                     reqSkill = {"whirlwind", "deriv_storm"}, reqWeaponTag = "单手剑",
                     desc = function(lv)
                         local dur = 3
                         for _, b in ipairs({2, 3, 5, 6, 8, 9}) do
                             if lv >= b then dur = dur + 1 end
                         end
                         local startN = 1
                         for _, b in ipairs({7}) do
                             if lv >= b then startN = startN + 1 end
                         end
                         local endN = 0
                         for _, b in ipairs({4, 10}) do
                             if lv >= b then endN = endN + 1 end
                         end
                         local endTxt = endN .. '次旋风斩。'
                         if endN == 0 then
                             endTxt = endN .. '次旋风斩（升级可以提高）。'
                         end
                         return '你成为风暴本身。使用后自身获得"风暴"状态，持续' .. dur .. '回合。风暴状态下，回合开始时自动施展' .. startN .. '次旋风斩，回合结束时自动施展' .. endTxt
                     end },
    crit_dmg     = { name = "物理暴击伤害UP", col = {255, 80, 60},   type = "passive",
                     bonus = "critDmg", bonusPerLv = 2,
                     reqSkill = "sword_master", reqSkillLv = 5,
                     desc = function(lv)
                         local total = 2 * lv
                         return "提高" .. total .. "%暴击伤害（2%/等级）。"
                     end },

    -- ========== 猎人技能 ==========
    h_power_shot   = { name = "劲射",       col = {120, 200, 80},  type = "active",
                       cd = 3, mpCost = 8, mpCostPerLv = 1, dmgMul = 1.25, dmgMulPerLv = 0.05,
                       reqWeaponTag = "弓",
                       desc = function(lv)
                           local mul = math.floor((1.25 + (lv - 1) * 0.05) * 100 + 0.5)
                           return "射出一支强力箭矢，根据物理攻击力，对单体目标造成" .. mul .. "%伤害。"
                       end },
    h_hit_up       = { name = "命中值UP",   col = {180, 200, 80},  type = "passive",
                       bonus = "hit", bonusPct = true, bonusPerLv = 1,
                       reqWeaponTag = "弓",
                       desc = function(lv)
                           local total = 1 * lv
                           return "提高命中值" .. total .. "%（1%/等级，至少" .. total .. "点）。"
                       end },
    h_enh_shot     = { name = "强化劲射",   col = {140, 210, 60},  type = "passive",
                       enhance = "h_power_shot", dmgMulAddPerLv = 0.05, mpCostRedPerLv = 1,
                       reqSkill = "h_power_shot", reqWeaponTag = "弓",
                       desc = function(lv)
                           local dmg = math.floor(0.05 * lv * 100 + 0.5)
                           local mp = 1 * lv
                           return "强化你的\"劲射\"技能，提高\"劲射\"伤害" .. dmg .. "%（5%/等级），降低MP消耗" .. mp .. "点（1点/等级）。"
                       end },
    h_hound        = { name = "猎犬",       col = {160, 140, 80},  type = "passive",
                       hound = true,
                       desc = "获得一只猎犬伙伴，它的属性以一定比例继承自猎人。继承比例随着技能等级提高而提高。" },
    h_scatter      = { name = "多重射",       col = {100, 180, 100}, type = "active",
                       cd = 2, mpCost = 10, mpCostPerLv = 1, dmgMul = 0.85, dmgMulPerLv = 0.05,
                       scatter = true, scatterExtra = 2, reqWeaponTag = "弓",
                       desc = function(lv)
                           local mul = math.floor((0.85 + (lv - 1) * 0.05) * 100 + 0.5)
                           return "同时射出多只箭矢，根据物理攻击力，对主目标及攻击范围内额外2个敌方目标射出箭矢，合计3个目标，造成" .. mul .. "%伤害。"
                       end },
    h_distraction  = { name = "分心",       col = {140, 160, 100}, type = "passive",
                       reqSkill = "h_scatter", reqSkillLv = 5,
                       desc = function(lv)
                           local pct = 2 * lv
                           return "你的普通攻击有" .. pct .. "%概率（2%/每等级）触发一次当前等级的多重射。满级时，散射+1，你的普通攻击可以额外命中攻击范围内一个敌方目标。"
                       end },
    h_shoot_prof   = { name = "射击熟练",   col = {180, 160, 100}, type = "passive",
                       condTag = "弓",
                       condBonus = { dmgPct = 1, critFlat = 2 },
                       desc = function(lv)
                           local dmg = 1 * lv
                           local crit = 2 * lv
                           return "提高使用弓时造成的伤害" .. dmg .. "%（1%/等级），暴击值" .. crit .. "点（2点/等级）。"
                       end },
    h_patk_up      = { name = "物理攻击力UP", col = {220, 120, 60}, type = "passive",
                       bonus = "atk", bonusPct = true, bonusPerLv = 1,
                       reqWeaponTag = "弓",
                       desc = function(lv)
                           local total = 1 * lv
                           return "提高" .. total .. "%物理攻击力（1%/等级）。"
                       end },
    h_beast_prof   = { name = "驯兽熟练",   col = {140, 160, 80},  type = "passive",
                       reqSkill = "h_hound", reqSkillLv = 1,
                       houndDmgPctPerLv = 2,
                       desc = function(lv)
                           local total = 2 * lv
                           return "提高你的猎犬所造成的伤害" .. total .. "%（2%/等级）。本技能满级以后，猎犬获得特性，优先攻击猎人最近一次攻击的目标。满级时猎犬移动速度+1。"
                       end },
    h_hp_regen     = { name = "生命回复UP", col = {60, 200, 120},  type = "passive",
                       bonus = "hpRegen", bonusPerLv = 1, bonusPct = true,
                       desc = function(lv)
                           local total = 1 * lv
                           return "提高HP自然回复" .. total .. "%（1%/等级，至少" .. total .. "点）。"
                       end },
    h_mark_target  = { name = "标记目标",   col = {200, 80, 60},   type = "passive",
                       markDmgPctPerLv = 2,
                       desc = function(lv)
                           local total = 2 * lv
                           return "标记猎人攻击的目标，提高猎人和猎犬对标记目标造成的伤害" .. total .. "%（2%/等级）。同一时间只能维持一个标记。"
                       end },
    h_stun_shot    = { name = "晕眩射击",   col = {200, 180, 60},  type = "active",
                       cd = 3, mpCost = 8, mpCostPerLv = 1, dmgMul = 0.8, dmgMulPerLv = 0,
                       stunChance = 55, stunChancePerLv = 5, stunMaxChance = 100, stunDuration = 1,
                       stunDurBP = {[5] = 1, [10] = 1},
                       reqWeaponTag = "弓",
                       desc = function(lv)
                           local mul = math.floor(0.8 * 100)
                           local chance = math.min(55 + (lv - 1) * 5, 100)
                           local dur = 1
                           if lv >= 5 then dur = dur + 1 end
                           if lv >= 10 then dur = dur + 1 end
                           return "射出使目标陷入晕眩的强力箭矢。根据物理攻击力，对单体目标造成" .. mul .. "%伤害，并有" .. chance .. "%概率击晕敌人，附加" .. dur .. "回合\"晕眩\"状态。"
                       end },
    h_bond_link    = { name = "羁绊链接",   col = {180, 120, 160}, type = "passive",
                       reqSkill = "h_beast_prof", reqSkillLv = 5,
                       bondHealPctPerLv = 1.5,
                       desc = function(lv)
                           local total = 1.5 * lv
                           return "猎人和猎犬存在羁绊，以各自对敌人造成伤害的" .. total .. "%治疗对方（1.5%/等级）。"
                       end },
    h_aim          = { name = "瞄准",       col = {160, 200, 80},  type = "passive",
                       aimChanceBase = 10, aimChancePerLv = 2,
                       aimDmgPct = 30,
                       aimRangeLvs = {3, 6, 10},
                       reqWeaponTag = "弓", reqSkill = "h_shoot_prof", reqSkillLv = 5,
                       desc = function(lv)
                           local chance = 10 + 2 * lv
                           local range = 0
                           for _, b in ipairs({3, 6, 10}) do
                               if lv >= b then range = range + 1 end
                           end
                           return "瞄准目标。当使用弓与箭矢进行攻击时，有" .. chance .. "%（2%/等级）概率额外造成30%伤害，攻击距离提高" .. range .. "格（3/6/10等级时攻击距离各+1）。"
                       end },
    h_pcrit_up     = { name = "物理暴击值UP", col = {255, 120, 80}, type = "passive",
                       bonus = "critVal", bonusPct = true, bonusPerLv = 1,
                       reqWeaponTag = "弓", reqSkill = "h_shoot_prof", reqSkillLv = 5,
                       desc = function(lv)
                           local total = 1 * lv
                           return "提高物理暴击值" .. total .. "%（1%/等级，至少" .. total .. "点）。"
                       end },
    h_full_draw    = { name = "满弓",       col = {100, 220, 60},  type = "passive",
                       fullDraw = true, fullDrawAtkSpdPenalty = 20,
                       fullDrawDmgPctPerLv = 5, fullDrawKBChancePerLv = 4, fullDrawKBDist = 1,
                       reqWeaponTag = "弓", reqSkill = "h_power_shot", reqSkillLv = 5,
                       desc = function(lv)
                           local dmg = 5 * lv
                           local kb = 4 * lv
                           return "每一击都拉满弓的射术风格，攻击速度-20。提高使用弓与箭矢造成的伤害" .. dmg .. "%（5%/等级），并且有" .. kb .. "%概率（4%/等级）击退被攻击的敌方目标1格。"
                       end },
    h_beast_master = { name = "驯兽专精",   col = {120, 180, 60},  type = "passive",
                       reqSkill = "h_beast_prof", reqSkillLv = 10,
                       houndAtkPctPerLv = 3, houndCritPctPerLv = 2, houndHitPctPerLv = 2,
                       houndAtkSpdPctPerLv = 2, houndDodgePctPerLv = 2,
                       desc = function(lv)
                           return "提高猎犬的物理攻击力" .. (3*lv) .. "%（3%/等级），暴击值" .. (2*lv) .. "%（2%/等级），命中值" .. (2*lv) .. "%（2%/等级），攻击速度" .. (2*lv) .. "%（2%/等级），闪避值" .. (2*lv) .. "%（2%/等级）。满级时猎犬移动速度+1。"
                       end },
    h_chase_arrow  = { name = "追身箭",     col = {140, 200, 100}, type = "passive",
                       chaseDmgMul = 0.55, chaseDmgMulPerLv = 0.05,
                       reqWeaponTag = "弓", reqSkill = "h_shoot_prof", reqSkillLv = 10,
                       desc = function(lv)
                           local mul = math.floor((0.55 + (lv - 1) * 0.05) * 100 + 0.5)
                           return "以最后一支箭矢收尾，猎人在每回合结束时对主目标额外射出一支箭矢，造成" .. mul .. "%伤害（5%/等级）。"
                       end },
    h_shoot_master = { name = "射击专精",   col = {200, 180, 60},  type = "passive",
                       condTag = "弓",
                       condBonus = { dmgPct = 1.5, atkSpdFlat = 1 },
                       reqSkill = "h_shoot_prof", reqSkillLv = 10,
                       desc = function(lv)
                           local dmg = math.floor(1.5 * lv)
                           local spd = 1 * lv
                           return "提高使用弓时造成的伤害" .. dmg .. "%（1.5%/等级），攻击速度" .. spd .. "点（1点/等级）。"
                       end },
    h_snipe        = { name = "狙击",       col = {80, 200, 80},   type = "active",
                       cd = 3, mpCost = 20, mpCostPerLv = 1, dmgMul = 2.3, dmgMulPerLv = 0.3,
                       distDmgBonusPerGrid = 0.5, reqWeaponTag = "弓",
                       reqSkill = "h_full_draw", reqSkillLv = 10,
                       desc = function(lv)
                           local mul = math.floor((2.3 + (lv - 1) * 0.3) * 100 + 0.5)
                           return "以精准的射术狙杀目标。根据物理攻击力，对单体目标造成" .. mul .. "%伤害。与目标的距离每增加1格（曼哈顿距离），伤害提高50%。"
                       end },
    h_wild         = { name = "野性",       col = {180, 140, 60},  type = "passive",
                       reqSkill = "h_beast_master", reqSkillLv = 5,
                       wildAtkSpdFlatPerLv = 2, wildHoundAtkSpdFlatPerLv = 5,
                       wildFearBaseChance = 1, wildFearChancePerLv = 1, wildFearDuration = 1,
                       desc = function(lv)
                           local hSpd = 5 * lv
                           local pSpd = 2 * lv
                           local fear = 1 + 1 * lv
                           return "你和猎犬习惯了大自然的方式，猎犬的攻击速度+" .. hSpd .. "（5/等级），猎人的攻击速度+" .. pSpd .. "（2/等级）。猎犬攻击时有" .. fear .. "%几率使目标感到极致的害怕，附加1回合\"恐惧\"状态。满级时猎犬移动速度+1。"
                       end },
    h_shuttle      = { name = "静神",       col = {100, 180, 200}, type = "passive",
                       focusBuff = true,
                       focusDmgPctBase = 12, focusDmgPctPerLv = 2,
                       focusAtkSpdPerLv = 2,
                       reqWeaponTag = "弓", reqSkill = "h_shoot_master", reqSkillLv = 5,
                       desc = function(lv)
                           local pct = 12 + 2 * (lv - 1)
                           local spd = 2 * lv
                           return "本回合未移动时，使用弓攻击或技能时自动进入静神状态，提高弓和箭矢伤害" .. pct .. "%（2%/等级），攻击速度+" .. spd .. "（2/等级），本回合生效。"
                       end },
    h_pcrit_dmg    = { name = "物理暴击伤害UP", col = {255, 80, 60}, type = "passive",
                       bonus = "critDmg", bonusPerLv = 2,
                       reqWeaponTag = "弓", reqSkill = "h_shoot_master", reqSkillLv = 5,
                       desc = function(lv)
                           local total = 2 * lv
                           return "提高" .. total .. "%暴击伤害（2%/等级）。"
                       end },

    -- ========== 刺客技能 ==========
    a_weapon_throw = { name = "武器投掷",   col = {180, 100, 200}, type = "active",
                       cd = 2, mpCost = 7, mpCostPerLv = 1, dmgMul = 1.15, dmgMulPerLv = 0.05,
                       skillRange = 3, throwSkill = true, reqWeaponTag = "匕首",
                       desc = function(lv)
                           local mul = math.floor((1.15 + (lv - 1) * 0.05) * 100 + 0.5)
                           return "将手中的匕首向敌人投掷而去。根据物理攻击力，对单体目标造成" .. mul .. "%伤害。"
                       end },

    a_enh_throw    = { name = "强化投掷",   col = {200, 120, 220}, type = "passive",
                       reqSkill = "a_weapon_throw", reqSkillLv = 10,
                       enhanceTag = "throwSkill", mpCostRedPerLv = 1, dmgMulAddPerLv = 0.05,
                       condTag = "匕首",
                       desc = function(lv)
                           local dmg = math.floor(0.05 * lv * 100 + 0.5)
                           local mp = 1 * lv
                           return "强化你的投掷类技能。提高所有投掷类技能造成的伤害" .. dmg .. "%（5%/等级），降低MP消耗" .. mp .. "点（1点/等级）。"
                       end },
    a_double_strike= { name = "二连击",     col = {200, 80, 180},  type = "passive",
                       doubleStrikeBaseChance = 2, doubleStrikeChancePerLv = 2,
                       condTag = "匕首",
                       desc = function(lv)
                           local chance = 2 * lv
                           return "使用匕首快速连续攻击的战斗技巧。刺客使用匕首进行普通攻击时有" .. chance .. "%概率（" .. 2 .. "%/等级）额外再发动一次普通攻击。"
                       end },
    a_dodge_up     = { name = "闪避值UP",   col = {160, 180, 200}, type = "passive",
                       bonus = "dodge", bonusPct = true, bonusPerLv = 1,
                       desc = function(lv)
                           local total = 1 * lv
                           return "提高闪避值" .. total .. "%（1%/等级，至少" .. total .. "点）。"
                       end },
    a_dagger_prof  = { name = "匕首熟练",   col = {180, 140, 160}, type = "passive",
                       condTag = "匕首",
                       condBonus = { dmgPct = 1, atkSpdFlat = 1 },
                       desc = function(lv)
                           local dmg = 1 * lv
                           local spd = 1 * lv
                           return "提高使用匕首时的伤害" .. dmg .. "%（1%/等级），攻击速度" .. spd .. "点（1点/等级）。"
                       end },
    a_poison_throw = { name = "带毒投掷",   col = {120, 200, 80},  type = "active",
                       reqSkill = "a_weapon_throw", reqSkillLv = 10,
                       cd = 2, mpCost = 10, mpCostPerLv = 1, dmgMul = 0.85, dmgMulPerLv = 0.05,
                       skillRange = 3, throwSkill = true, reqWeaponTag = "匕首",
                       poisonPct = 5, poisonChance = 63, poisonChancePerLv = 3, poisonDuration = 3,
                       desc = function(lv)
                           local mul = math.floor((0.85 + (lv - 1) * 0.05) * 100 + 0.5)
                           local chance = math.min(63 + (lv - 1) * 3, 90)
                           return "向敌人投掷带毒的匕首，根据物理攻击力，对单体目标造成" .. mul .. "%伤害，并有" .. chance .. "%概率使目标中毒，附加3回合\"中毒\"状态。"
                       end },
    a_dual_prof    = { name = "双持熟练",   col = {200, 160, 60},  type = "passive",
                       dualExtraHitsPerLv = 0, dualDmgPctPerLv = 2, dualAtkSpdPerLv = 1,
                       condDualDagger = true,
                       desc = function(lv)
                           local pct = 50 + 2 * lv
                           local spd = 1 * lv
                           return "提高双持匕首时的攻击力计算比例，从初始50%提升至" .. pct .. "%（" .. 2 .. "%/等级）。同时，双持匕首时攻击速度提高" .. spd .. "点（1点/等级）。"
                       end },
    a_stealth      = { name = "隐匿",       col = {100, 100, 160}, type = "active",
                       cd = 4, mpCost = 9, mpCostPerLv = -1,
                       selfCast = true, stealthBuff = true, stealthMoveBase = 1,
                       stealthMoveLvs = {3, 6, 10}, stealthDurBase = 1, stealthDurPerLv = 1,
                       revealStrikeBase = 50, revealStrikePerLv = 5,
                       desc = function(lv)
                           local move = 1
                           for _, brk in ipairs({3, 6, 10}) do
                               if lv >= brk then move = move + 1 end
                           end
                           local rsPct = 50 + 5 * lv
                           return "遁入暗影，你进入\"隐身\"状态，移动距离固定为" .. move .. "（3/6/10级时移动距离各+1）。隐身状态下发动的第一下普通攻击或技能伤害提高" .. rsPct .. "%（5%/等级）。"
                       end },
    a_sand_throw   = { name = "泼沙",       col = {200, 180, 120}, type = "active",
                       cd = 3, mpCost = 5, mpCostPerLv = 0,
                       sandBlind = true, sandHitRedPerLv = 3,
                       sandDurBase = 3, sandDurLvs = {3, 6, 10},
                       desc = function(lv)
                           local hitRed = 3 * lv
                           local dur = 3
                           for _, b in ipairs({3, 6, 10}) do
                               if lv >= b then dur = dur + 1 end
                           end
                           return "向周围一圈敌人泼沙，降低命中值" .. hitRed .. "点（3点/等级），持续" .. dur .. "回合，并对最近的敌人发动一次普通攻击。"
                       end },
    a_spare_weapon = { name = "备用武器",   col = {160, 140, 120}, type = "passive",
                       spareWeaponCritDmgPerLv = 1,
                       spareWeaponThrowsBP = {[5]=1, [10]=2},
                       desc = function(lv)
                           local critBonus = 1 * lv
                           local throws = 0
                           for bpLv, n in pairs({[5]=1, [10]=2}) do
                               if lv >= bpLv then throws = n end
                           end
                           local s = "你使用投掷技能后，暴击伤害+" .. critBonus .. "%（" .. 1 .. "%/级）。"
                           if throws > 0 then
                               s = s .. "备用武器技能等级达到5/10级时，在使用投掷技能后，额外使用" .. throws .. "次当前技能等级的武器投掷。"
                           else
                               s = s .. "备用武器技能等级达到5/10级时，在使用投掷技能后，额外使用1/2次当前技能等级的武器投掷。"
                           end
                           return s
                       end },
    a_aspd_up      = { name = "攻击速度UP", col = {200, 200, 80},  type = "passive",
                       bonus = "atkSpeed", bonusPerLv = 1,
                       desc = function(lv)
                           return "提高攻击速度" .. (1*lv) .. "点（1点/等级）。"
                       end },
    a_flash_assault= { name = "闪烁突袭",   col = {180, 80, 220},  type = "active",
                       cd = 2, mpCost = 9, mpCostPerLv = 1, skillRange = 3,
                       flashAssault = true, flashAtkSpdPerLv = 5,
                       desc = function(lv)
                           local spd = 5 * lv
                           return "如同闪电，刺客瞬移到目标身后发动一次普通攻击，本回合内提高攻击速度" .. spd .. "点（" .. 5 .. "点/等级）。"
                       end },
    a_moon_shadow  = { name = "月影",       col = {120, 140, 200}, type = "passive",
                       reqSkill = "a_stealth", reqSkillLv = 5,
                       moonShadowDodgePctPerLv = 1.5,
                       bonus = "dodge", bonusPerLv = 2,
                       desc = function(lv)
                           local pct = 1.5 * lv
                           local dodgeFlat = 2 * lv
                           return "月影护佑。提高闪避值" .. dodgeFlat .. "点（2点/等级）。刺客本回合未打出的连击次数，每一次转化为1层\"月影\"，每层月影提供" .. pct .. "%（1.5%/等级）的额外闪避率，持续1回合。满级时，幻影+1。"
                       end },
    a_full_moon    = { name = "满月",         col = {200, 210, 255}, type = "passive",
                       reqSkill = "a_stealth", reqSkillLv = 5,
                       bonus = "dodge", bonusPerLv = 2,
                       fullMoon = true,
                       fullMoonDodgePerCharge = {20,19,18,17,16,15,14,13,12,10},
                       fullMoonDmgReduce = 0.95,
                       fullMoonDuration = 10,
                       fullMoonMaxStacks = {0,0,1,1,1,2,2,2,2,3},
                       desc = function(lv)
                           local dodgeFlat = 2 * lv
                           local maxStacks = ({0,0,1,1,1,2,2,2,2,3})[lv] or 0
                           local chargeCount = ({20,19,18,17,16,15,14,13,12,10})[lv] or 20
                           return "形似满月。闪避值提高" .. dodgeFlat .. "点/等级。满月技能3级以上时，每成功进行" .. chargeCount .. "次闪避或偏斜可以存储一层\"满月\"BUFF，持续10回合。当刺客遭受致死伤害时，消耗一层\"满月\"，使本次伤害下降95%。\"满月\"BUFF的存储上限在3/6/10级分别为1层、2层、3层。"
                       end },
    a_assassinate  = { name = "暗杀",         col = {255, 120, 80}, type = "passive",
                       reqSkill = "a_dagger_prof", reqSkillLv = 5,
                       assassinBackDmgPerLv = 2,
                       assassinSideDmgPerLv = 1,
                       desc = function(lv)
                           return "暗影无声。你和你的幻影及影子从敌人背后发动的攻击，伤害提高" .. (2*lv) .. "%（2%/等级）；从侧面发动的攻击，伤害提高" .. (1*lv) .. "%（1%/等级）。"
                       end },
    a_armor_break  = { name = "破甲投掷",   col = {220, 100, 60},  type = "active",
                       reqSkill = "a_poison_throw", reqSkillLv = 10,
                       cd = 2, mpCost = 10, mpCostPerLv = 1, dmgMul = 0.95, dmgMulPerLv = 0.05,
                       skillRange = 3, throwSkill = true, reqWeaponTag = "匕首",
                       armorBreakPct = 15, armorBreakDuration = 3,
                       armorBreakChance = 63, armorBreakChancePerLv = 3,
                       desc = function(lv)
                           local mul = math.floor((0.95 + (lv - 1) * 0.05) * 100 + 0.5)
                           local chance = math.min(63 + (lv - 1) * 3, 90)
                           return "精确投掷匕首损毁敌人防守。根据物理攻击力，对单体目标造成" .. mul .. "%伤害，并有" .. chance .. "%概率破坏敌人防御，附加3回合\"破甲\"状态，物理防御力下降15%。"
                       end },
    a_dual_master  = { name = "双持专精",   col = {220, 180, 40},  type = "passive",
                       reqSkill = "a_dual_prof", reqSkillLv = 10,
                       dualExtraHitsPerLv = 0, dualDmgPctPerLv = 3, dualAtkSpdPerLv = 1,
                       condDualDagger = true,
                       desc = function(lv)
                           local pct = 70 + 3 * lv
                           local spd = 1 * lv
                           return "在\"双持熟练\"的基础上，进一步提高双持匕首时的攻击力计算比例，从初始70%提升至" .. pct .. "%（" .. 3 .. "%/等级）。同时，双持匕首时攻击速度提高" .. spd .. "点（1点/等级）。"
                       end },
    a_deflect      = { name = "偏斜",       col = {180, 160, 120}, type = "passive",
                       deflectBaseEff = 37, deflectEffPerLv = 7,
                       desc = function(lv)
                           local eff = math.min(37 + 7 * (lv - 1), 100)
                           return "当刺客闪避失败时，重新进行一次闪避检定，成功时触发\"偏斜\"，根据避开要害值的" .. eff .. "%和敌人命中的关系降低该次伤害。"
                       end },
    a_dagger_master= { name = "匕首专精",   col = {200, 120, 180}, type = "passive",
                       condTag = "匕首",
                       condBonus = { dmgPct = 1.5, atkSpdFlat = 1 },
                       reqSkill = "a_dagger_prof", reqSkillLv = 10,
                       desc = function(lv)
                           local dmg = math.floor(1.5 * lv)
                           local spd = 1 * lv
                           return "提高使用匕首时造成的伤害" .. dmg .. "%（1.5%/等级），攻击速度" .. spd .. "点（1点/等级）。"
                       end },
    a_notice       = { name = "预告信",     col = {220, 200, 100}, type = "active",
                       reqSkill = "a_armor_break", reqSkillLv = 10,
                       cd = 3, mpCost = 15, mpCostPerLv = 1, dmgMul = 2.20, dmgMulPerLv = 0.20,
                       skillRange = 3, throwSkill = true, reqWeaponTag = "匕首",
                       poisonPct = 5, armorBreakPct = 15, armorBreakDuration = 3,
                       noticeCritDmgPerLv = 2, noticeCritDmgDuration = 3,
                       desc = function(lv)
                           local mul = math.floor((2.20 + (lv - 1) * 0.20) * 100 + 0.5)
                           local critDmg = 2 * lv
                           return "你的匕首是死亡预告。根据物理攻击力，对单体目标造成" .. mul .. "%伤害，并且使刺客对该目标的后续暴击伤害提高" .. critDmg .. "%（2%/等级）。同时，预告信会给目标附加3回合\"中毒\"效果和3回合\"破甲\"效果。"
                       end },
    a_storm_rain   = { name = "暴雨",       col = {100, 140, 220}, type = "passive",
                       reqSkill = "a_dual_master", reqSkillLv = 10,
                       stormPctPerLv = 0.5, condTag = "匕首",
                       desc = function(lv)
                           local pct = 0.5 * lv
                           return "你是一场暴雨。同一个回合对同一个目标连续造成伤害时，每一次伤害递增" .. pct .. "%（" .. 0.5 .. "%/等级）。"
                       end },
    a_phantom      = { name = "影人众",     col = {140, 80, 200},  type = "active",
                       reqSkill = {"a_moon_shadow", "a_assassinate"}, reqSkillLv = 5,
                       cd = 5, mpCost = 15, mpCostPerLv = 1,
                       selfCast = true, phantom = true,
                       phantomAtkPctBase = 30, phantomAtkPctPerLv = 10,
                       phantomCritPctPerLv = 5,
                       phantomHitBase = 55, phantomHitPerLv = 5,
                       phantomAspdBase = 55, phantomAspdPerLv = 5,
                       phantomHitsBase = 2, phantomHitsLvs = {3, 6, 10},
                       desc = function(lv)
                           local atkPct = 30 + 10 * lv
                           local critPct = 5 * lv
                           local hitPct = 55 + 5 * (lv - 1)
                           local aspdPct = 55 + 5 * (lv - 1)
                           local hits = 2
                           for _, brk in ipairs({3, 6, 10}) do
                               if lv >= brk then hits = hits + 1 end
                           end
                           return "皆为幻梦。刺客发动一次当前等级的\"隐匿\"并随机移动到附近位置，在原地留下自身的影子，影子继承刺客自身攻击力的" .. atkPct .. "%、暴击值的" .. critPct .. "%、命中值的" .. hitPct .. "%、攻击速度的" .. aspdPct .. "%，承受" .. hits .. "次伤害后消失。满级时，被动幻影+1、幻影检索范围+2。"
                       end },
    a_pcrit_dmg    = { name = "物理暴击伤害UP", col = {255, 80, 60}, type = "passive",
                       reqSkill = "a_dagger_master", reqSkillLv = 5,
                       bonus = "critDmg", bonusPerLv = 2,
                       desc = function(lv)
                           return "提高" .. (2*lv) .. "%物理暴击伤害（2%/等级）。"
                       end },

    -- ========== 法师技能 ==========
    m_spark        = { name = "火花术",     col = {220, 100, 40},  type = "active",
                       cd = 0, mpCost = 7, mpCostPerLv = 1, dmgMul = 1.21, dmgMulPerLv = 0.11,
                       useMagic = true, element = "fire", skillRange = 3, castStages = 1,
                       burnDuration = 2,
                       desc = function(lv)
                           local mul = math.floor((1.21 + (lv - 1) * 0.11) * 100 + 0.5)
                           return '向敌人投射小型火焰，根据魔法攻击力，造成' .. mul .. '%的火焰伤害，并附加2回合"灼伤"状态。'
                       end },
    m_ice_spike    = { name = "冰锥术",     col = {100, 180, 240}, type = "active",
                       cd = 0, mpCost = 6, mpCostPerLv = 1, dmgMul = 1.15, dmgMulPerLv = 0.10,
                       useMagic = true, element = "ice", skillRange = 3, castStages = 1,
                       chillDuration = 2,
                       desc = function(lv)
                           local mul = math.floor((1.15 + (lv - 1) * 0.10) * 100 + 0.5)
                           return '向敌人投射小型冰锥，根据魔法攻击力，造成' .. mul .. '%的冰冻伤害，并附加2回合"冻僵"状态。'
                       end },
    m_lightning    = { name = "电击术",     col = {240, 220, 60},  type = "active",
                       cd = 0, mpCost = 5, mpCostPerLv = 1, dmgMul = 1.17, dmgMulPerLv = 0.10,
                       useMagic = true, element = "thunder", skillRange = 3, castStages = 1,
                       stunChance = 7, stunDuration = 1,
                       desc = function(lv)
                           local mul = math.floor((1.17 + (lv - 1) * 0.10) * 100 + 0.5)
                           return '向敌人发射小型闪电，根据魔法攻击力，造成' .. mul .. '%的雷电伤害。电击术有7%的概率击晕敌人，附加1回合"晕眩"。'
                       end },
    m_mp_up        = { name = "魔法值UP",   col = {80, 120, 220},  type = "passive",
                       bonus = "maxMp", bonusPct = true, bonusPerLv = 1,
                       desc = function(lv)
                           local total = 1 * lv
                           return "提高" .. total .. "%最大魔法值（1%/等级）。"
                       end },
    m_fire_shield  = { name = "火焰护盾",   col = {220, 80, 40},   type = "active",
                       cd = 3, mpCost = 15, mpCostPerLv = 1, castStages = 2,
                       useMagic = true, element = "fire",
                       reqSkill = "m_spark", reqSkillLv = 5,
                       selfCast = true, needTarget = true, fireShieldBuff = true,
                       fireShieldDuration = 3, fireShieldDurPerLv = 1,   -- 持续 3+(lv-1)*1 回合，满级12
                       fireShieldReducePct = 2,                          -- 受伤减免 2%/级，满级20%
                       fireShieldReflectBase = 25, fireShieldReflectPerLv = 5, -- 反伤 matk 的 25%+(lv-1)*5%，满级70%
                       desc = function(lv)
                           local reduce = 2 * lv
                           local reflect = 25 + (lv - 1) * 5
                           local duration = 3 + (lv - 1) * 1 + 1
                           return "召唤火焰护盾保护目标，使目标受到的伤害减少" .. reduce .. "%。根据魔法攻击力，对敢于近战攻击火焰护盾的敌人造成" .. reflect .. "%的火焰属性反射伤害。持续期间免疫燃烧地面伤害。持续" .. duration .. "回合（+1/等级）。"
                       end },
    m_ice_ring     = { name = "冰环术",     col = {80, 160, 220},  type = "active",
                       cd = 4, mpCost = 8, mpCostPerLv = 1, dmgMul = 0.55, dmgMulPerLv = 0.05, castStages = 2,
                       useMagic = true, element = "ice",
                       reqSkill = "m_ice_spike", reqSkillLv = 5,
                       groundTarget = true, skillRange = 3, iceRingAoe = true,
                       freezeChanceBase = 64, freezeChancePerLv = 4, freezeDuration = 1, freezeDurBreaks = {3, 6, 10},
                       desc = function(lv)
                           local mul = math.floor((0.55 + (lv - 1) * 0.05) * 100 + 0.5)
                           local chance = 64 + (lv - 1) * 4
                           local freezeDur = 1
                           for _, b in ipairs({3, 6, 10}) do
                               if lv >= b then freezeDur = freezeDur + 1 end
                           end
                           return '对目标地点施放扩散性的冰环法术，根据魔法攻击力，对3x3范围内的敌方目标造成' .. mul .. '%的冰冻伤害，并有' .. chance .. '%概率附加' .. freezeDur .. '回合"冰冻"状态。'
                       end },
    m_chain_light  = { name = "闪电链",     col = {240, 200, 40},  type = "active",
                       cd = 3, mpCost = 16, mpCostPerLv = 1, dmgMul = 2.0, dmgMulPerLv = 0.2, castStages = 2,
                       useMagic = true, element = "thunder", skillRange = 3,
                       reqSkill = "m_lightning", reqSkillLv = 5,
                       chainLightning = true, chainBounceBase = 2, chainBounceBreaks = {3, 6, 10},
                       chainBounceRange = 3, stunChance = 7, stunDuration = 1,
                       desc = function(lv)
                           local mul = math.floor((2.0 + (lv - 1) * 0.2) * 100 + 0.5)
                           local bounces = 2
                           local breaks = {3, 6, 10}
                           for _, b in ipairs(breaks) do
                               if lv >= b then bounces = bounces + 1 end
                           end
                           return '施放闪电链攻击目标，根据魔法攻击力，造成' .. mul .. '%雷电伤害。闪电链会在3格内的敌人间弹射，最多' .. bounces .. '次。闪电链有7%的概率击晕敌人，附加1回合"晕眩"。'
                       end },
    m_magic_shield = { name = "魔法盾",     col = {120, 120, 200}, type = "active",
                       cd = 0, mpCost = 0, castStages = 1, element = "arcane",
                       selfCast = true, magicShieldToggle = true,
                       magicShieldAbsorbBase = 5, magicShieldAbsorbPerLv = 5,   -- 伤害转MP比例: 5%+5%/级，满级50%
                       magicShieldRatioBase = 1, magicShieldRatioPerLv = 0, -- 每点MP抵扣伤害: 始终1:1
                       desc = function(lv)
                           local absorbPct = 5 + (lv - 1) * 5
                           return "用魔力凝结护盾保护自身。开关技能，需要1段咏唱。开启后，将自身受到伤害的" .. absorbPct .. "%改为消耗魔法值，每1点魔法值抵扣1点伤害。"
                       end },
    m_fire_prof    = { name = "火焰熟练",   col = {220, 120, 60},  type = "passive",
                       elementProf = "fire", elementProfPctPerLv = 1,
                       elementProfRangeAtMax = 1,
                       elementMCritPerLv = 2,
                       desc = function(lv)
                           local dmg = 1 * lv
                           local mcrit = 2 * lv
                           return "你的火焰法术伤害提高" .. dmg .. "%（1%/等级），施展火焰法术时魔法暴击值+" .. mcrit .. "（2点/等级）。本技能满级时，所有火焰法术的施展距离+1。"
                       end },
    m_ice_prof     = { name = "冰冻熟练",   col = {80, 140, 200},  type = "passive",
                       elementProf = "ice", elementProfPctPerLv = 1,
                       elementProfRangeAtMax = 1,
                       elementMCritPerLv = 2,
                       desc = function(lv)
                           local dmg = 1 * lv
                           local mcrit = 2 * lv
                           return "你的冰冻法术伤害提高" .. dmg .. "%（1%/等级），施展冰冻法术时魔法暴击值+" .. mcrit .. "（2点/等级）。本技能满级时，所有冰冻法术的施展距离+1。"
                       end },
    m_elec_prof    = { name = "雷电熟练",   col = {220, 200, 40},  type = "passive",
                       elementProf = "thunder", elementProfPctPerLv = 1,
                       elementProfRangeAtMax = 1,
                       elementMCritPerLv = 2,
                       desc = function(lv)
                           local dmg = 1 * lv
                           local mcrit = 2 * lv
                           return "你的雷电法术伤害提高" .. dmg .. "%（1%/等级），施展雷电法术时魔法暴击值+" .. mcrit .. "（2点/等级）。本技能满级时，所有雷电法术的施展距离+1。"
                       end },
    m_mp_regen     = { name = "魔法攻击力UP", col = {160, 80, 220},  type = "passive",
                       bonus = "mAtk", bonusPct = true, bonusPerLv = 1,
                       desc = function(lv)
                           return "提高" .. (1 * lv) .. "%魔法攻击力（1%/等级，至少" .. (1 * lv) .. "点）。"
                       end },
    m_fireball     = { name = "火球术",     col = {240, 80, 20},   type = "active",
                       cd = 2, mpCost = 32, mpCostPerLv = 1, dmgMul = 3.3, dmgMulPerLv = 0.3, castStages = 3,
                       useMagic = true, element = "fire",
                       reqSkill = "m_fire_shield", reqSkillLv = 5,
                       groundTarget = true, skillRange = 3, fireballAoe = true,
                       fireballRadius = 2,
                       burnDuration = 3, burnPctBase = 22, burnPctPerLv = 2,
                       desc = function(lv)
                           local mul = math.floor((3.3 + (lv - 1) * 0.3) * 100 + 0.5)
                           return '向目标地点投射大型火球，根据魔法攻击力对目标及2格距离范围内的所有敌人造成' .. mul .. '%的火焰伤害，并附加2回合"灼伤"状态。同时燃烧地面。'
                       end },
    m_ice_wall     = { name = "冰墙术",     col = {60, 160, 240},  type = "active",
                       cd = 5, mpCost = 30, mpCostPerLv = 1, castStages = 3, element = "ice",
                       reqSkill = "m_ice_ring", reqSkillLv = 5,
                       groundTarget = true, skillRange = 3, iceWallSkill = true,
                       iceWallBaseLen = 3, iceWallLenBreaks = {3, 6, 10},
                       iceWallDuration = 3, iceWallHits = 2, iceWallHitsBreaks = {2, 4, 6, 8, 10},
                       iceWallIceDmgBonusPerLv = 2,
                       desc = function(lv)
                           local len = 3
                           local dur = 3
                           local lenBreaks = {3, 6, 10}
                           for _, b in ipairs(lenBreaks) do
                               if lv >= b then len = len + 1 end
                               if lv >= b then dur = dur + 1 end
                           end
                           local hits = 2
                           local hitsBreaks = {2, 4, 6, 8, 10}
                           for _, b in ipairs(hitsBreaks) do
                               if lv >= b then hits = hits + 1 end
                           end
                           local iceDmg = 2 * lv
                           return "驱动寒冰奥秘在目标范围内构造冰墙的一端，并可以点击相邻格子向该方向展开寒冰城墙，最多" .. len .. "格。冰墙持续存在" .. dur .. "回合，可承受" .. hits .. "次攻击。冰墙存在时，会使周围1格内的敌人移动距离减少1点，受到冰冻伤害提高" .. iceDmg .. "%。"
                       end },
    m_thunder      = { name = "落雷术",     col = {255, 240, 40},  type = "active",
                       cd = 3, mpCost = 31, mpCostPerLv = 1, dmgMul = 2.23, dmgMulPerLv = 0.23, castStages = 3,
                       useMagic = true, element = "thunder", skillRange = 3,
                       reqSkill = "m_chain_light", reqSkillLv = 5,
                       groundTarget = true, thunderAoe = true, thunderAoeRadius = 1,
                       stunChance = 7, stunDuration = 1,
                       desc = function(lv)
                           local mul = math.floor((2.23 + (lv - 1) * 0.23) * 100 + 0.5)
                           return '召唤雷电轰击目标地点及距离1格范围内的所有敌人，根据魔法攻击力，造成' .. mul .. '%雷电伤害。落雷术有7%概率击晕敌人，附加1回合"晕眩"状态。'
                       end },
    m_blink        = { name = "闪烁",       col = {140, 100, 220}, type = "active",
                       cd = 8, cdBreaks = {3, 5, 7, 9}, mpCost = 7, mpCostPerLv = 1, element = "arcane",
                       groundTarget = true, blinkSkill = true, castStages = 1,
                       skillRange = 2, rangeBreaks = {2, 4, 6, 8, 10},
                       desc = function(lv)
                           local range = 2
                           local breaks = {2, 4, 6, 8, 10}
                           for _, b in ipairs(breaks) do
                               if lv >= b then range = range + 1 end
                           end
                           local regenPct = 2 * lv
                           return "驱动奥秘能量，将自身瞬间移动到距离" .. range .. "格以内的目标空地，并回复最大生命值和魔法值的" .. regenPct .. "%（2%/等级）。"
                       end },
    m_fire_master  = { name = "火焰专精",   col = {240, 100, 40},  type = "passive",
                       reqSkill = "m_fire_prof", reqSkillLv = 10,
                       elementProf = "fire", elementMasterPctPerLv = 2,
                       elementProfRangeAtMax = 1,
                       elementMCritDmgPerLv = 2,
                       desc = function(lv)
                           local dmg = 2 * lv
                           local mcd = 2 * lv
                           return "你的火焰法术伤害提高" .. dmg .. "%（2%/等级），施展火焰法术时魔法暴击伤害+" .. mcd .. "%（2%/等级）。本技能满级时，所有火焰法术的施展距离+1。"
                       end },
    m_ice_master   = { name = "冰冻专精",   col = {60, 140, 220},  type = "passive",
                       reqSkill = "m_ice_prof", reqSkillLv = 10,
                       elementProf = "ice", elementMasterPctPerLv = 2,
                       elementProfRangeAtMax = 1,
                       elementMCritDmgPerLv = 2,
                       desc = function(lv)
                           local dmg = 2 * lv
                           local mcd = 2 * lv
                           return "你的冰冻法术伤害提高" .. dmg .. "%（2%/等级），施展冰冻法术时魔法暴击伤害+" .. mcd .. "%（2%/等级）。本技能满级时，所有冰冻法术的施展距离+1。"
                       end },
    m_elec_master  = { name = "雷电专精",   col = {240, 220, 20},  type = "passive",
                       reqSkill = "m_elec_prof", reqSkillLv = 10,
                       elementProf = "thunder", elementMasterPctPerLv = 2,
                       elementProfRangeAtMax = 1,
                       elementMCritDmgPerLv = 2,
                       desc = function(lv)
                           local dmg = 2 * lv
                           local mcd = 2 * lv
                           return "你的雷电法术伤害提高" .. dmg .. "%（2%/等级），施展雷电法术时魔法暴击伤害+" .. mcd .. "%（2%/等级）。本技能满级时，所有雷电法术的施展距离+1。"
                       end },
    m_cast_spd     = { name = "吟唱速度UP", col = {180, 160, 220}, type = "passive",
                       castSpdPerLv = 5,
                       desc = function(lv)
                           local total = 5 * lv
                           return "你的吟唱速度提高" .. total .. "点（5点/等级）。"
                       end },
    m_meteor       = { name = "陨石术",     col = {255, 60, 20},   type = "active",
                       cd = 3, mpCost = 42, mpCostPerLv = 2, castStages = 4,
                       dmgMul = 5.5, dmgMulPerLv = 0.5,
                       useMagic = true, element = "fire",
                       reqSkill = "m_fireball", reqSkillLv = 5,
                       groundTarget = true, skillRange = 4, meteorAoe = true,
                       meteorRadius = 2,
                       burnDuration = 5, burnPctBase = 22, burnPctPerLv = 2,
                       desc = function(lv)
                           local mul = math.floor((5.5 + (lv - 1) * 0.5) * 100 + 0.5)
                           return '召唤陨石轰击目标地点，根据魔法攻击力，对目标地点及距离2格范围内的所有敌人造成' .. mul .. '%火焰伤害，并附加2回合"灼伤"状态。同时燃烧地面。'
                       end },
    m_blizzard     = { name = "暴风雪",     col = {40, 120, 240},  type = "active",
                       cd = 5, mpCost = 42, mpCostPerLv = 2, castStages = 4,
                       dmgMul = 1.6, dmgMulPerLv = 0.1,
                       useMagic = true, element = "ice",
                       reqSkill = "m_ice_wall", reqSkillLv = 5,
                       groundTarget = true, skillRange = 3, blizzardAoe = true,
                       blizzardRadius = 2,
                       blizzardDurationBase = 3, blizzardDurationBreaks = {3, 6, 10},
                       blizzardSlowDur = 3, blizzardSlowVal = 1, blizzardSlowVal10 = 2,
                       desc = function(lv)
                           local mul = math.floor((1.6 + (lv - 1) * 0.1) * 100 + 0.5)
                           local dur = 3
                           local breaks = {3, 6, 10}
                           for _, b in ipairs(breaks) do
                               if lv >= b then dur = dur + 1 end
                           end
                           return '召唤暴风雪打击目标地点，根据魔法攻击力，对目标及距离目标2格范围内的所有敌人造成' .. mul .. '%的冰冻伤害，并附加2回合"冻僵"状态。暴风雪持续打击' .. dur .. '回合。'
                       end },
    m_thunder_cloud= { name = "雷云术",     col = {255, 220, 0},   type = "active",
                       cd = 5, mpCost = 42, mpCostPerLv = 2, castStages = 4,
                       dmgMul = 2.1, dmgMulPerLv = 0.1,
                       useMagic = true, element = "thunder",
                       reqSkill = "m_thunder", reqSkillLv = 5,
                       thunderCloud = true, skillRange = 4,
                       cloudDurationBase = 3, cloudDurationBreaks = {3, 6, 10},
                       cloudAoeRadius = 8, stunChance = 7, stunDuration = 1,
                       desc = function(lv)
                           local mul = math.floor((2.1 + (lv - 1) * 0.1) * 100 + 0.5)
                           local dur = 3
                           local breaks = {3, 6, 10}
                           for _, b in ipairs(breaks) do
                               if lv >= b then dur = dur + 1 end
                           end
                           return '召唤雷云追踪目标敌人，根据魔法攻击力，对以目标为中心的3x3范围内的所有敌人造成' .. mul .. '%雷电伤害。雷云持续' .. dur .. '回合。雷云术有7%概率击晕敌人，附加1回合"晕眩"状态。'
                       end },
    m_matk_up      = { name = "节能施法", col = {100, 180, 220}, type = "passive",
                       mpCostRedPctPerLv = 3,
                       desc = function(lv)
                           local total = 3 * lv
                           local ratioBonus = 3 * lv
                           return "你施展所有法术时的MP消耗减少" .. total .. "%（3%/等级）。同时魔法盾每1点MP抵扣的伤害提高" .. ratioBonus .. "%（3%/等级），即每1点MP抵扣" .. string.format("%.2f", 1 + ratioBonus / 100) .. "点伤害。"
                       end },

    -- ========== 牧师技能 ==========
    p_baptism      = { name = "受洗",       col = {220, 180, 80},  type = "passive",
                       baptismStunChancePerLv = 2, baptismStunDuration = 1,
                       desc = function(lv)
                           local chance = 2 * lv
                           return "你需要培养信仰。普通攻击、\"祝福术\"和超度有" .. chance .. "%概率（2%/等级）击晕目标1回合。"
                       end },
    p_prayer       = { name = "祈祷术",     col = {220, 200, 60},  type = "active",
                       element = "holy", cd = 0, mpCost = 7, mpCostPerLv = 1, castStages = 1,
                       selfCast = true, needTarget = true, skillRange = 3, prayerBuff = true, prayerHealPctPerLv = 0.5, prayerDuration = 10,
                       desc = function(lv)
                           local pct = 0.5 * lv
                           return "向神明祈祷佑护，为友方目标附加10回合\"祈祷\"状态，在每个回合开始时回复最大生命值的" .. pct .. "%（" .. 0.5 .. "%/等级）。"
                       end },
    p_radiance     = { name = "辉光",       col = {255, 230, 140}, type = "passive",
                       radiancePctBase = 120, radiancePctPerLv = 20,
                       radianceRangeBonusAtMax = 1,
                       desc = function(lv)
                           local pct = 120 + 20 * (lv - 1)
                           return "根据你的治疗量的" .. pct .. "%（+20%/每等级）对2格范围内的敌人造成神圣魔法伤害。满级时，作用范围+1。"
                       end },
    p_bless        = { name = "\"祝福术\"", col = {220, 220, 100}, type = "active",
                       element = "holy", cd = 0, mpCost = 5, mpCostPerLv = 1, dmgMul = 1.1, dmgMulPerLv = 0.1,
                       reqWeaponTag = "锤",
                       desc = function(lv)
                           local mul = 110 + 10 * (lv - 1)
                           return "给它上个\"祝福\"。根据物理攻击力和额外附加50%的魔法攻击力，对单体目标造成" .. mul .. "%神圣混合伤害。"
                       end },
    p_hp_regen     = { name = "生命回复UP", col = {60, 200, 120},  type = "passive",
                       bonus = "hpRegen", bonusPct = true, bonusPerLv = 1,
                       desc = "HP自然回复+1%/级（满级+10%，至少10点）。" },
    p_holy_spring  = { name = "圣泉祝福",   col = {100, 200, 220}, type = "active",
                       element = "holy", cd = 0, mpCost = 5, mpCostPerLv = 1, castStages = 1,
                       selfCast = true, needTarget = true, skillRange = 3, holySpringBuff = true, holySpringRegenPctPerLv = 5, holySpringDuration = 10,
                       reqSkill = "p_prayer", reqSkillLv = 10,
                       desc = function(lv)
                           local dur = 10
                           local gs = require("GameState")
                           local pietyLv = gs.skillLevels and gs.skillLevels["p_piety"] or 0
                           if pietyLv > 0 then dur = dur + pietyLv * 5 end
                           local regen = 5 * lv
                           return "向泉水之神祈求祝福。为友方目标附加" .. dur .. "回合\"圣泉祝福\"，提高HP和MP自然回复" .. regen .. "%（5%/等级）。"
                       end },
    p_restore      = { name = "恢复术",     col = {80, 220, 120},  type = "active",
                       element = "holy", cd = 3, mpCost = 9, mpCostPerLv = 1, castStages = 2,
                       selfCast = true, needTarget = true, skillRange = 3, restoreHeal = true, restoreMatkPctBase = 33, restoreMatkPctPerLv = 3, isHealSkill = true,
                       reqSkill = "p_prayer", reqSkillLv = 5,
                       desc = function(lv)
                           local pct = 33 + 3 * (lv - 1)
                           return "借复苏之神的力量，治疗单体友方目标，根据魔法攻击力的" .. pct .. "%回复生命值。"
                       end },
    p_mace_prof    = { name = "钉锤熟练",   col = {180, 140, 100}, type = "passive",
                       condTag = "锤",
                       condBonus = { dmgPct = 1, critFlat = 2 },
                       desc = function(lv)
                           local dmg = 1 * lv
                           local crit = 2 * lv
                           return "提高使用钉锤时的伤害" .. dmg .. "%（1%/等级），物理暴击值" .. crit .. "点（2点/等级）。"
                       end },
    p_shield_prof  = { name = "盾牌熟练",   col = {100, 130, 190}, type = "passive",
                       shieldProf = true, blockAmountPerLv = 1, blockChancePerLv = 2,
                       condTag = "盾",
                       desc = function(lv)
                           local chance = 2 * lv
                           local amount = 1 * lv
                           return "提高你使用盾牌时的格挡概率" .. chance .. "%（2%/等级），格挡伤害" .. amount .. "点（1点/等级）。"
                       end },
    p_piety        = { name = "虔诚",       col = {200, 180, 100}, type = "passive",
                       pietyDurPerLv = 5, pietyDoubleBlessAtMax = true,
                       desc = function(lv)
                           local dur = 5 * lv
                           local gs = require("GameState")
                           local maxLv = gs.SKILL_MAX_LEVEL or 10
                           local extra = ""
                           if lv >= maxLv then
                               extra = "满级效果：所有祝福类技能的效果翻倍。"
                           else
                               extra = "满级时，所有祝福类技能的效果翻倍。"
                           end
                           return "虔诚者引来更多神明注视。加强所有祝福类技能的持续时间，增加" .. dur .. "回合（5回合/等级）。" .. extra
                       end },
    p_holy_purity  = { name = "圣洁",       col = {255, 240, 200}, type = "passive",
                       healEffectPerLv = 2, healCdBreaks = {5, 10},
                       desc = function(lv)
                           local healPct = 2 * lv
                           return "圣光纯洁。治疗效果提高" .. healPct .. "%（2%/等级）。5/10级时，治疗技能的冷却时间分别减少1回合。"
                       end },
    p_patk_up      = { name = "物理攻击力UP", col = {220, 120, 60}, type = "passive",
                       bonus = "atk", bonusPct = true, bonusPerLv = 1,
                       desc = function(lv)
                           return "提高" .. (1 * lv) .. "%物理攻击力（1%/等级，至少" .. (1 * lv) .. "点）。"
                       end },
    p_dmg_reduce   = { name = "受伤降低",     col = {80, 160, 220}, type = "passive",
                       dmgReducePerLv = 1,
                       desc = function(lv)
                           return "你受到的所有伤害减少" .. (1 * lv) .. "%（1%/每等级）。"
                       end },
    p_conquer_bless= { name = "征服祝福",   col = {220, 160, 60},  type = "active",
                       element = "holy", cd = 0, mpCost = 7, mpCostPerLv = 1, castStages = 1,
                       selfCast = true, needTarget = true, skillRange = 3, conquerBuff = true, conquerAtkPctPerLv = 1, conquerDuration = 10,
                       reqSkill = "p_holy_spring", reqSkillLv = 5,
                       desc = function(lv)
                           local dur = 10
                           local gs = require("GameState")
                           local pietyLv = gs.skillLevels and gs.skillLevels["p_piety"] or 0
                           if pietyLv > 0 then dur = dur + pietyLv * 5 end
                           local atk = 1 * lv
                           return "向征服之神祈求祝福，为友方目标附加" .. dur .. "回合\"征服祝福\"，提高物理攻击力和魔法攻击力" .. atk .. "%（1%/等级）。"
                       end },
    p_hp_up        = { name = "生命值UP",   col = {80, 200, 80},   type = "passive",
                       bonus = "maxHp", bonusPct = true, bonusPerLv = 1,
                       desc = function(lv)
                           return "提高" .. (1 * lv) .. "%最大生命值（1%/等级）。"
                       end },
    p_mace_master  = { name = "钉锤专精",   col = {200, 160, 80},  type = "passive",
                       condTag = "锤",
                       condBonus = { dmgPct = 1.5, pCritDmgPct = 2 },
                       reqSkill = "p_mace_prof", reqSkillLv = 10,
                       desc = function(lv)
                           local dmg = 1.5 * lv
                           local cd = 2 * lv
                           return "提高使用钉锤时的伤害" .. dmg .. "%（1.5%/等级），物理暴击伤害" .. cd .. "%（2%/等级）。"
                       end },
    p_shield_master= { name = "盾牌专精",   col = {80, 120, 200},  type = "passive",
                       condTag = "盾",
                       shieldBlockChancePerLv = 2, shieldBlockConRatioPerLv = 0.05,
                       reqSkill = "p_shield_prof", reqSkillLv = 10,
                       desc = function(lv)
                           local chance = 2 * lv
                           local conRatio = string.format("%.2f", 0.05 * lv)
                           return "提高使用盾牌时的格挡概率" .. chance .. "%（2%/等级），根据体质提高盾牌格挡伤害，每1点体质额外格挡" .. conRatio .. "点伤害（0.05点/等级）。"
                       end },
    p_shelter_bless= { name = "庇护祝福",   col = {180, 200, 100}, type = "active",
                       element = "holy", cd = 0, mpCost = 5, mpCostPerLv = 1, castStages = 1,
                       selfCast = true, needTarget = true, skillRange = 3, shelterBuff = true, shelterDefPctPerLv = 1, shelterDuration = 10,
                       reqSkill = "p_conquer_bless", reqSkillLv = 5,
                       desc = function(lv)
                           local dur = 10
                           local gs = require("GameState")
                           local pietyLv = gs.skillLevels and gs.skillLevels["p_piety"] or 0
                           if pietyLv > 0 then dur = dur + pietyLv * 5 end
                           local def = 1 * lv
                           return "向庇护之神祈求祝福，为友方目标附加" .. dur .. "回合\"庇护祝福\"，提高物理防御力和魔法防御力" .. def .. "%（1%/等级）。"
                       end },
    p_holy_heal    = { name = "圣疗术",     col = {60, 220, 160},  type = "active",
                       element = "holy", cd = 4, mpCost = 18, mpCostPerLv = 2, castStages = 3,
                       selfCast = true, needTarget = true, skillRange = 3, restoreHeal = true, restoreMatkPctBase = 55, restoreMatkPctPerLv = 5, isHealSkill = true,
                       reqSkill = "p_restore", reqSkillLv = 5,
                       desc = function(lv)
                           local pct = 55 + 5 * (lv - 1)
                           return "借复苏之神的力量，大幅治疗单体友方目标，根据魔法攻击力的" .. pct .. "%回复生命值。"
                       end },
    p_exorcism     = { name = "超度",       col = {240, 220, 80},  type = "active",
                       element = "holy", cd = 2, mpCost = 10, mpCostPerLv = 1, dmgMul = 3.3, dmgMulPerLv = 0.3,
                       reqSkill = {"p_mace_master", "p_bless"}, reqSkillLv = 10, reqWeaponTag = "锤",
                       desc = function(lv)
                           local mul = 330 + 30 * (lv - 1)
                           return "亲手为敌人超度。根据物理攻击力和额外附加50%的魔法攻击力，对单体目标造成" .. mul .. "%神圣混合伤害。"
                       end },
    p_divine_grace = { name = "神佑",       col = {220, 200, 120}, type = "passive",
                       divineGraceHealPerLv = 2, reqLeftCategory = "盾牌",
                       desc = function(lv)
                           local pct = 2 * lv
                           return "神明护佑。牧师使用盾牌触发格挡时，根据魔法攻击力的" .. pct .. "%（2%/等级）治疗自身。"
                       end },
    p_miracle_bless= { name = "奇迹祝福",   col = {200, 220, 60},  type = "active",
                       element = "holy", cd = 0, mpCost = 20, mpCostPerLv = 1, castStages = 4,
                       selfCast = true, needTarget = true, skillRange = 3, miracleBuff = true, miracleDuration = 10, miraclePerLv = 1,
                       reqSkill = "p_shelter_bless", reqSkillLv = 5,
                       desc = function(lv)
                           local dur = 10
                           local gs = require("GameState")
                           local pietyLv = gs.skillLevels and gs.skillLevels["p_piety"] or 0
                           if pietyLv > 0 then dur = dur + pietyLv * 5 end
                           local val = 1 * lv
                           local critDmg = 2 * lv
                           return "向此间真神祈求祝福，为友方目标附加" .. dur .. "回合\"奇迹祝福\"，提高暴击值、闪避值和命中值" .. val .. "%（1%/等级，至少" .. val .. "点），提高暴击伤害" .. critDmg .. "%（2%/等级）。同时为友方目标分别施加当前等级的\"圣泉祝福\"、\"征服祝福\"和\"庇护祝福\"。"
                       end },
    p_holy_tree    = { name = "圣树",       col = {60, 200, 60},   type = "active",
                       isHealSkill = true,
                       element = "holy", cd = 5, mpCost = 28, mpCostPerLv = 1, castStages = 4,
                       groundTarget = true, skillRange = 3,
                       holyTree = true, holyTreeDuration = 5, holyTreeHits = 5,
                       holyTreeHealPctBase = 13, holyTreeHealPctPerLv = 3,
                       holyTreeRangeBreaks = {3, 6, 10},
                       holyTreeDurBreaks = {2, 4, 6, 8, 10},
                       reqSkill = "p_holy_heal", reqSkillLv = 5,
                       desc = function(lv)
                           local dur = 5
                           for _, brk in ipairs({2, 4, 6, 8, 10}) do
                               if lv >= brk then dur = dur + 1 end
                           end
                           local healPct = 13 + 3 * (lv - 1)
                           local range = 1
                           for _, brk in ipairs({3, 6, 10}) do
                               if lv >= brk then range = range + 1 end
                           end
                           return "唤醒复苏之神以圣树姿态现世，在指定地点召唤圣树，持续" .. dur .. "回合（2/4/6/8/10级时+1）。圣树不可被攻击，每回合治疗以自身为中心" .. range .. "格范围内（3/6/10级时+1）的所有友方单位，根据牧师魔法攻击力的" .. healPct .. "%回复生命。"
                       end },
}
