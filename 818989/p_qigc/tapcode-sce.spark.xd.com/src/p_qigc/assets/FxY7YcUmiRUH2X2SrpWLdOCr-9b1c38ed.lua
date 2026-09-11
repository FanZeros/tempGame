-- ============================================================
-- GameState_Skills.lua  —— 技能系统（技能树/施放/冷却/生活技能）
-- 由 GameState.lua 拆分，通过 init(M) 挂载到主模块
-- ============================================================

local sub = {}

function sub.init(M)

--- 检查当前职业能否装备指定副手类型
---@param offhandTag string|nil
---@return boolean
function M.checkOffhand(offhandTag)
    if not offhandTag then return true end
    local allowed = M.CLASS_OFFHAND and M.CLASS_OFFHAND[M.currentClass]
    return allowed ~= nil and allowed[offhandTag] == true
end
--- 各职业右手武器栏可装备的武器类型（weaponTag）
M.CLASS_WEAPON_R = {
    warrior  = { ["单手剑"] = true, ["匕首"] = true, ["锤"] = true },
    assassin = { ["单手剑"] = true, ["匕首"] = true },
    hunter   = { ["单手剑"] = true, ["匕首"] = true, ["弓"] = true },
    mage     = { ["法杖"] = true, ["单手剑"] = true, ["匕首"] = true },
    priest   = { ["单手剑"] = true, ["锤"] = true, ["法杖"] = true },
    traveler = { ["单手剑"] = true, ["匕首"] = true },
}

--- 各职业可装备的副手类型（offhandTag）
M.CLASS_OFFHAND = {
    warrior  = { ["盾牌"] = true },
    assassin = { ["盾牌"] = true },
    hunter   = { ["盾牌"] = true, ["箭袋"] = true },
    mage     = { ["盾牌"] = true, ["法器"] = true },
    priest   = { ["盾牌"] = true, ["法器"] = true },
    traveler = { ["盾牌"] = true },
}

--- 各职业技能树布局：6行4列，nil 表示空格
M.CLASS_SKILL_TREE_LAYOUTS = {
    warrior = {
        { nil,        "strike",     "charge",      "w_hp_up"      },
        { "pwr_stk",  "counter",    "whirlwind",   "sword_prof"   },
        { "mighty",   "shield_prof","charge_roar",   "w_blood_drink"  },
        { "dual_wield","shield_bash","cleave",     "crit_rate"    },
        { "sup_stk",  "shield_master","deriv_storm", "sword_master" },
        { "mst_stk",  "mst_counter","mst_whirl",   "crit_dmg"    },
    },
    hunter = {
        { nil,             "h_power_shot",   nil,              "h_hit_up"         },
        { "h_enh_shot",    "h_hound",        "h_scatter",      "h_shoot_prof"     },
        { "h_patk_up",     "h_beast_prof",   "h_distraction",  "h_mark_target"    },
        { "h_stun_shot",   "h_bond_link",    "h_aim",          "h_pcrit_up"       },
        { "h_full_draw",   "h_beast_master", "h_chase_arrow",  "h_shoot_master"   },
        { "h_snipe",       "h_wild",         "h_shuttle",      "h_pcrit_dmg"      },
    },
    assassin = {
        { nil,             "a_weapon_throw", "a_flash_assault","a_dodge_up"       },
        { "a_enh_throw",   "a_dual_prof",    "a_stealth",      "a_dagger_prof"    },
        { "a_poison_throw","a_double_strike","a_moon_shadow",  "a_sand_throw"     },
        { "a_spare_weapon","a_aspd_up",      "a_deflect",      "a_assassinate"    },
        { "a_armor_break", "a_dual_master",  "a_full_moon",    "a_dagger_master"  },
        { "a_notice",      "a_storm_rain",   "a_phantom",      "a_pcrit_dmg"      },
    },
    mage = {
        { "m_spark",       "m_ice_spike",    "m_lightning",    "m_mp_up"          },
        { "m_fire_shield", "m_ice_ring",     "m_chain_light",  "m_magic_shield"   },
        { "m_fire_prof",   "m_ice_prof",     "m_elec_prof",    "m_mp_regen"       },
        { "m_fireball",    "m_ice_wall",     "m_thunder",      "m_blink"          },
        { "m_fire_master", "m_ice_master",   "m_elec_master",  "m_matk_up"        },
        { "m_meteor",      "m_blizzard",     "m_thunder_cloud","m_cast_spd"       },
    },
    priest = {
        { "p_baptism",     nil,              "p_radiance",     "p_prayer"         },
        { "p_bless",       "p_hp_regen",     "p_holy_spring",  "p_restore"        },
        { "p_mace_prof",   "p_shield_prof",  "p_piety",        "p_hp_up"          },
        { "p_patk_up",     "p_dmg_reduce",   "p_conquer_bless","p_holy_purity"    },
        { "p_mace_master", "p_shield_master","p_shelter_bless", "p_holy_heal"      },
        { "p_exorcism",    "p_divine_grace", "p_miracle_bless","p_holy_tree"      },
    },
    traveler = {
        { nil, nil, nil, nil },
        { nil, nil, nil, nil },
        { nil, nil, nil, nil },
        { nil, nil, nil, nil },
        { nil, nil, nil, nil },
        { nil, nil, nil, nil },
    },
}

--- 兼容：SKILL_TREE_LAYOUT 指向当前职业的布局
M.SKILL_TREE_LAYOUT = M.CLASS_SKILL_TREE_LAYOUTS.warrior

--- 技能定义（数据已提取到 data/SkillDefs.lua）
M.SKILL_DEFS = require("data.SkillDefs")
-- ========== 生活技能 ==========
M.LIFE_SKILL_DEFS = {
    { id = "mining",    name = "采矿", iconPath = "image/life_mining.png",    col = {140, 120, 90} },
    { id = "gathering", name = "采集", iconPath = "image/life_gathering.png", col = {60, 140, 60} },
    { id = "forging",   name = "锻造", iconPath = "image/life_forging.png",   col = {180, 100, 50} },
    { id = "alchemy",   name = "炼金", iconPath = "image/life_alchemy.png",   col = {120, 60, 160} },
    { id = "cooking",   name = "烹饪", iconPath = "image/life_cooking.png",   col = {200, 140, 60} },
}
M.lifeSkillImages = {} -- { [id] = nvgImageHandle }
M.LIFE_SKILL_MAX_LEVEL = 100  -- 每段满级100
M.LIFE_SKILL_TIERS = {
    { id = 1, name = "入门", col = {120, 100, 70} },
    { id = 2, name = "擅长", col = {60, 180, 60} },
    { id = 3, name = "精通", col = {60, 120, 220} },
    { id = 4, name = "专业", col = {180, 80, 220} },
    { id = 5, name = "宗师", col = {255, 180, 0} },
}
M.LIFE_SKILL_MAX_TIER = 5

-- 大成功/特大成功概率（按段位）
-- 大成功: 产出×2, 特大成功: 产出×3
M.LIFE_SKILL_CRIT = {
    [1] = { great = 0.10, super = 0.00 },  -- 入门
    [2] = { great = 0.15, super = 0.00 },  -- 擅长
    [3] = { great = 0.20, super = 0.00 },  -- 精通
    [4] = { great = 0.25, super = 0.05 },  -- 专业
    [5] = { great = 0.30, super = 0.10 },  -- 宗师
}

--- 根据生活技能段位判定大成功/特大成功
--- 先判特大成功，再判大成功，互斥
---@param lifeSkillId string 生活技能 id (forging/alchemy/cooking)
---@return number multiplier 产出倍率 (1/2/3)
---@return string|nil critType 成功类型 (nil/"great"/"super")
function M.rollLifeSkillCrit(lifeSkillId)
    local tier = M.lifeSkillTiers[lifeSkillId] or 1
    local crit = M.LIFE_SKILL_CRIT[tier] or M.LIFE_SKILL_CRIT[1]
    local roll = math.random()
    if crit.super > 0 and roll < crit.super then
        return 3, "super"
    elseif roll < crit.super + crit.great then
        return 2, "great"
    end
    return 1, nil
end

M.lifeSkillLevels = {}  -- { [id] = level (1-100) }
M.lifeSkillTiers = {}   -- { [id] = tier (1-5) }
M.lifeSkillExp = {}     -- { [id] = exp (0-99) } 当前经验值，满100升级
M.lifeSkillSlotAreas = {} -- { [1..5] = {x,y,w,h} } 点击区域

--- 计算生活技能的隐藏等级（累积经验）
--- 隐藏等级 = (当前等阶 - 1) * 100 + 当前经验
--- 例：精通等阶(3) + 20经验 = (3-1)*100 + 20 = 220
---@param skillId string 生活技能 id
---@return number hiddenLevel 隐藏等级
function M.getLifeSkillHiddenLevel(skillId)
    local tier = M.lifeSkillTiers[skillId] or 1
    local exp = M.lifeSkillExp[skillId] or 0
    return (tier - 1) * M.LIFE_SKILL_MAX_LEVEL + exp
end

--- 根据玩家隐藏等级和采集物隐藏等级计算采集成功率
--- 差额每1点影响1%，等级相同时50%
---@param playerHiddenLv number 玩家隐藏生活等级
---@param gatherHiddenLv number 采集物隐藏等级
---@return number successRate 成功率 (0.0 ~ 1.0)
function M.calcGatherSuccessRate(playerHiddenLv, gatherHiddenLv)
    local diff = playerHiddenLv - gatherHiddenLv
    local rate = 0.50 + diff * 0.01
    return math.max(0.0, math.min(1.0, rate))  -- 限制在 0%~100%（差距>=50级时为0）
end

--- 技能点数（玩家可分配的技能点，区别于属性点 statPoints）
M.skillPoints = 0

--- 各技能当前等级 { [skillId] = level }
M.skillLevels = {}

--- 技能冷却跟踪 { [skillId] = 剩余冷却回合数 }
M.skillCooldowns = {}

--- 获取技能的实际MP消耗
---@param skillId string
---@return number
function M.getSkillMpCost(skillId)
    local def = M.SKILL_DEFS[skillId]
    if not def or def.type ~= "active" then return 0 end
    local lv = M.skillLevels[skillId] or 0
    if lv <= 0 then return 0 end
    local base = def.mpCost or 0
    local perLv = def.mpCostPerLv or 0
    local cost = base + (lv - 1) * perLv
    -- 强化被动减蓝耗（enhancedAs 允许继承强化效果）
    local alias = def.enhancedAs
    local weaponR = M.equipment and M.equipment["weapon_r"]
    local curTag = weaponR and weaponR.weaponTag
    for sid, sdef in pairs(M.SKILL_DEFS) do
        local matched = (sdef.enhance == skillId or (alias and sdef.enhance == alias))
        -- enhanceTag：按标签批量匹配（如 throwSkill 匹配所有投掷类技能）
        if not matched and sdef.enhanceTag and def[sdef.enhanceTag] then
            matched = true
        end
        if matched and sdef.mpCostRedPerLv
           and (not sdef.reqWeaponTag or curTag == sdef.reqWeaponTag) then
            local slv = M.skillLevels[sid] or 0
            if slv > 0 then
                cost = cost - sdef.mpCostRedPerLv * slv
            end
        end
    end
    -- 节能施法：百分比减少所有法术MP消耗
    local manaEffLv = M.skillLevels["m_matk_up"] or 0
    if manaEffLv > 0 then
        local manaEffDef = M.SKILL_DEFS["m_matk_up"]
        if manaEffDef and manaEffDef.mpCostRedPctPerLv then
            local pct = manaEffDef.mpCostRedPctPerLv * manaEffLv
            cost = cost * (1 - pct / 100)
        end
    end
    return math.max(0, math.floor(cost + 0.5))
end

--- 获取技能的实际伤害倍率
---@param skillId string
---@return number
function M.getSkillDmgMul(skillId)
    local def = M.SKILL_DEFS[skillId]
    if not def or not def.dmgMul then return 1.0 end
    local lv = M.skillLevels[skillId] or 0
    if lv <= 0 then return 1.0 end
    local base = def.dmgMul
    local perLv = def.dmgMulPerLv or 0
    local mul = base + (lv - 1) * perLv
    -- 强化被动加伤害（加算，enhancedAs 允许继承）
    local alias = def.enhancedAs
    local weaponR = M.equipment and M.equipment["weapon_r"]
    local curTag = weaponR and weaponR.weaponTag
    for sid, sdef in pairs(M.SKILL_DEFS) do
        local matched = (sdef.enhance == skillId or (alias and sdef.enhance == alias))
        -- enhanceTag：按标签批量匹配
        if not matched and sdef.enhanceTag and def[sdef.enhanceTag] then
            matched = true
        end
        if matched and sdef.dmgMulAddPerLv
           and (not sdef.reqWeaponTag or curTag == sdef.reqWeaponTag) then
            local slv = M.skillLevels[sid] or 0
            if slv > 0 then
                mul = mul + sdef.dmgMulAddPerLv * slv
            end
        end
    end
    return mul
end

--- 获取技能的元素熟练施展距离加成
--- 当对应元素的熟练技能满级时，该元素法术施展距离+1
---@param skillId string
---@return number
function M.getElementRangeBonus(skillId)
    local def = M.SKILL_DEFS[skillId]
    if not def then return 0 end
    local bonus = 0
    -- 虚空握：装备施展距离加成（作用于所有带 skillRange 的远程技能）
    if def.skillRange and M.player then
        bonus = bonus + (M.player.castRange or 0)
    end
    if not def.element then return bonus end
    local element = def.element
    for sid, sdef in pairs(M.SKILL_DEFS) do
        if sdef.elementProf == element and sdef.elementProfRangeAtMax then
            local slv = M.skillLevels[sid] or 0
            if slv >= M.SKILL_MAX_LEVEL then
                bonus = bonus + sdef.elementProfRangeAtMax
            end
        end
    end
    return bonus
end

--- 检查技能是否可用（已学习、冷却好、蓝够）
---@param skillId string
---@return boolean
function M.isSkillReady(skillId)
    local def = M.SKILL_DEFS[skillId]
    if not def or def.type ~= "active" then return false end
    local lv = M.skillLevels[skillId] or 0
    if lv <= 0 then return false end
    local cd = M.skillCooldowns[skillId] or 0
    if cd > 0 then return false end
    local cost = M.getSkillMpCost(skillId)
    if M.player and (M.player.mp or 0) < cost then return false end
    -- 武器标签检查（如猎人技能需要装备弓）
    -- 弓必须同时装备箭袋才视为装备弓
    if def.reqWeaponTag then
        local weaponR = M.equipment and M.equipment["weapon_r"]
        local weaponL = M.equipment and M.equipment["weapon_l"]
        local curTag = weaponR and weaponR.weaponTag
        -- 右手无有效武器标签时，检查左手（如单持匕首）
        if not curTag and weaponL and weaponL.weaponTag then
            curTag = weaponL.weaponTag
        end
        if curTag ~= def.reqWeaponTag then return false end
        if def.reqWeaponTag == "弓" then
            if not weaponL or weaponL.category ~= "箭袋" then return false end
        end
    end
    -- 左手装备类别检查（如盾击需要左手装备盾牌）
    if def.reqLeftCategory then
        local weaponL = M.equipment and M.equipment["weapon_l"]
        if not weaponL or weaponL.category ~= def.reqLeftCategory then return false end
    end
    return true
end

--- 从自动技能优先级中选出第一个可用的技能
---@return string|nil skillId
--- 自动战斗时检查 buff 类技能对应的 buff 是否已在生效中
--- 全局 buff（存储在 GameState 上）的 flag → turns 字段映射
local AUTO_BUFF_GLOBAL_TURNS = {
    stormBuff      = "stormBuffTurns",
    focusBuff      = "focusBuffTurns",
    stealthBuff    = "stealthTurns",
    fireShieldBuff = "fireShieldTurns",
}
--- 玩家身上的 buff（存储在 player 上）的 flag → turns 字段映射
local AUTO_BUFF_PLAYER_TURNS = {
    prayerBuff     = "prayerTurns",
    holySpringBuff = "holySpringTurns",
    conquerBuff    = "conquerTurns",
    shelterBuff    = "shelterTurns",
    miracleBuff    = "miracleTurns",
}

---@param skillId string
---@return boolean true表示对应buff已生效，应跳过
local function isBuffAlreadyActive(skillId)
    local def = M.SKILL_DEFS[skillId]
    if not def then return false end
    -- 魔法盾 toggle：已开启则视为生效中，自动战斗不再切换关闭
    if def.magicShieldToggle and M.magicShieldActive then
        return true
    end
    for flag, turnsField in pairs(AUTO_BUFF_GLOBAL_TURNS) do
        if def[flag] then
            -- 火焰护盾：剩1回合时允许续施
            if flag == "fireShieldBuff" then
                return (M[turnsField] or 0) > 1
            end
            return (M[turnsField] or 0) > 0
        end
    end
    if M.player then
        for flag, turnsField in pairs(AUTO_BUFF_PLAYER_TURNS) do
            if def[flag] then
                return (M.player[turnsField] or 0) > 0
            end
        end
    end
    return false
end

function M.pickActiveSkill()
    for i = 1, M.ACTIVE_SKILL_SLOTS do
        local skillId = M.activeSkills[i]
        if skillId and M.isSkillReady(skillId) then
            -- 自动战斗时，跳过已在生效中的 buff 技能
            if M.autoMode and isBuffAlreadyActive(skillId) then
                goto continuePickSkill
            end
            return skillId
        end
        ::continuePickSkill::
    end
    return nil
end

--- 使用技能：扣蓝、设置冷却
---@param skillId string
function M.useSkill(skillId)
    -- 多重施法额外释放时跳过 CD 消耗（MP 已在多重施法循环中逐次扣除）
    if M._skipUseSkill then return end
    local def = M.SKILL_DEFS[skillId]
    if not def then return end
    local cost = M.getSkillMpCost(skillId)
    if M.player then
        M.player.mp = math.max(0, (M.player.mp or 0) - cost)
    end
    local cd = def.cd or 0
    -- cdBreaks：等级断点减少冷却（如闪烁在3/5/7/9级各-1CD）
    if def.cdBreaks then
        local lv = M.skillLevels[skillId] or 1
        for _, brk in ipairs(def.cdBreaks) do
            if lv >= brk then cd = cd - 1 end
        end
    end
    -- 圣洁：治疗技能冷却缩减（5级-1，10级-2）
    if def.isHealSkill then
        local purityLv = M.skillLevels["p_holy_purity"] or 0
        if purityLv > 0 then
            local purityDef = M.SKILL_DEFS["p_holy_purity"]
            if purityDef and purityDef.healCdBreaks then
                for _, brk in ipairs(purityDef.healCdBreaks) do
                    if purityLv >= brk then cd = cd - 1 end
                end
            end
        end
    end
    -- 检查是否有满级的 enhance 被动减少冷却（enhancedAs 允许继承）
    local alias = def.enhancedAs
    local weaponR = M.equipment and M.equipment["weapon_r"]
    local curTag = weaponR and weaponR.weaponTag
    for sid, sdef in pairs(M.SKILL_DEFS) do
        local matched = (sdef.enhance == skillId or (alias and sdef.enhance == alias))
        if not matched and sdef.enhanceTag and def[sdef.enhanceTag] then
            matched = true
        end
        if matched and sdef.cdRedAtMax
           and (not sdef.reqWeaponTag or curTag == sdef.reqWeaponTag) then
            local slv = M.skillLevels[sid] or 0
            if slv >= M.SKILL_MAX_LEVEL then
                cd = cd - sdef.cdRedAtMax
            end
        end
    end
    -- 深渊词缀：极速冷却（每层 -1 CD，最多叠加 3 层）
    -- 聚焦器：屏蔽极速冷却
    local quickCdStacks = 0
    if M.equipment and not ((M.player and (M.player.focuserDmgPer or 0) > 0)
       or (M.getEquipBonus and (M.getEquipBonus().focuserDmgPer or 0) > 0)) then
        for _, slot in pairs(M.equipment) do
            if slot then
                if slot.abyssAffix and slot.abyssAffix.mechanic == "quick_cooldown" then
                    quickCdStacks = quickCdStacks + 1
                end
                if slot.heroAffix and slot.heroAffix.mechanic == "quick_cooldown" then
                    quickCdStacks = quickCdStacks + 1
                end
                if slot.gemSlots then
                    for _, gs in ipairs(slot.gemSlots) do
                        if gs.abyssAffix and gs.abyssAffix.mechanic == "quick_cooldown" then
                            quickCdStacks = quickCdStacks + 1
                        end
                    end
                end
                if quickCdStacks >= 3 then quickCdStacks = 3; break end
            end
        end
    end
    cd = cd - quickCdStacks
    -- +1 补偿：使用当回合的 tick 会立即 -1，所以多加 1 让实际等待回合数与 CD 值一致
    local finalCd = math.max(0, cd)
    if finalCd > 0 then finalCd = finalCd + 1 end
    M.skillCooldowns[skillId] = finalCd
    -- 使用本技能时，减少关联技能的冷却（如超强击减少碎星冷却）
    for sid, sdef in pairs(M.SKILL_DEFS) do
        if sdef.cdReducedBy == skillId then
            local sLv = M.skillLevels[sid] or 0
            if sLv > 0 then
                local sCd = M.skillCooldowns[sid] or 0
                if sCd > 0 then
                    M.skillCooldowns[sid] = sCd - 1
                end
            end
        end
    end
    -- 装备效果：施法回血（每次使用技能时回复固定HP）
    if M.player and (M.player.castHeal or 0) > 0 and M.player.hp > 0 then
        local healAmt = M.player.castHeal
        if (M.player.healEffectPct or 0) > 0 then
            healAmt = math.floor(healAmt * (1 + M.player.healEffectPct / 100))
        end
        local oldHp = M.player.hp
        M.player.hp = math.min(M.player.hp + healAmt, M.player.maxHp)
        if M.player.hp > oldHp then
            M._pendingCastHeal = M.player.hp - oldHp
        end
        M._pendingRadianceHeal = (M._pendingRadianceHeal or 0) + healAmt
    end
    -- 装备效果：施法回魔（每次使用技能时回复固定MP）
    if M.player and (M.player.castMpRegen or 0) > 0 and M.player.mp and M.player.maxMp then
        local oldMp = M.player.mp
        M.player.mp = math.min(M.player.mp + M.player.castMpRegen, M.player.maxMp)
        if M.player.mp > oldMp then
            M._pendingCastMpRegen = M.player.mp - oldMp
        end
    end
end

--- 每回合结束时减少所有冷却
function M.tickSkillCooldowns()
    for skillId, cd in pairs(M.skillCooldowns) do
        if cd > 0 then
            -- 隐匿激活期间冻结隐匿技能冷却（解除后才开始倒计时）
            if skillId == "a_stealth" and M.stealthActive then
                -- 不递减
            else
                M.skillCooldowns[skillId] = cd - 1
            end
        end
    end
end

--- 技能格子点击区域（供 Input 检测）
M.skillSlotAreas = {}  -- { [skillId] = {x,y,w,h} }

--- 主动技能装备槽（5个）
M.ACTIVE_SKILL_SLOTS = 5
M.activeSkills = {}  -- { [1..5] = skillId or nil }
M.activeSkillSlotAreas = {}  -- { [1..5] = {x,y,w,h} }

--- 技能装备弹窗状态
M.skillEquipPopupVisible = false     -- 弹窗是否打开
M.skillEquipPopupSlot = nil          -- 当前操作的槽位 (1..5)
M.skillEquipPopupSkillRects = {}     -- 弹窗内技能点击区域
M.skillEquipPopupRemoveRect = nil    -- "取消放置"按钮区域
M.skillEquipPopupRect = nil          -- 弹窗整体区域（用于检测外部点击）

--- 行动菜单（移动后弹出）
M.actionMenuVisible = false          -- 主菜单是否显示
M.actionMenuRects = {}               -- 按钮点击区域 { attack, skill, item, wait, undo }
M.actionMenuRect = nil               -- 菜单整体区域
M.actionSkillSubVisible = false      -- 技能子菜单是否显示
M.actionSkillSubRects = {}           -- 技能条目点击区域
M.actionSkillSubRect = nil           -- 子菜单整体区域
M.actionChoice = nil                 -- 已选行动: "attack"|"skill"|nil
M.actionChosenSkillId = nil          -- 已选技能ID
M.actionPreMoveX = nil               -- 移动前的X坐标（用于撤销）
M.actionPreMoveY = nil               -- 移动前的Y坐标（用于撤销）
M.lastActionTargetX = nil            -- 最近攻击/施法目标的棋盘X（用于菜单定位）
M.lastActionTargetY = nil            -- 最近攻击/施法目标的棋盘Y（用于菜单定位）
M.lastActionAoeRadius = nil          -- AOE技能的格子半径（用于菜单避让整个爆炸区域）

function M.closeActionMenu()
    M.actionMenuVisible = false
    M.actionMenuRects = {}
    M.actionMenuRect = nil
    M.actionSkillSubVisible = false
    M.actionSkillSubRects = {}
    M.actionSkillSubRect = nil
    M.actionChoice = nil
    M.actionChosenSkillId = nil
    M.actionPreMoveX = nil
    M.actionPreMoveY = nil
    M.lastActionTargetX = nil
    M.lastActionTargetY = nil
    M.lastActionAoeRadius = nil
    M.aoeGroundMode = false
end

--- 施法职业行动后检查是否应继续回合（有剩余吟唱段数且未在吟唱中）
--- 如果应继续，重置行动菜单状态并返回true
---@return boolean 是否继续回合
function M.mageCheckContinueTurn()
    -- 酒馆肉搏胜利已触发，不再继续回合
    if M.tavernBrawlState and M.tavernBrawlState.done then return false end
    if (M.currentClass == "mage" or M.currentClass == "priest") and (M.chantStages or 0) > 0 and not M.chanting then
        M.mageActionTaken = true
        -- 重置行动菜单状态，延迟显示主菜单（等攻击效果播完）
        M.actionChoice = nil
        M.actionChosenSkillId = nil
        M.actionSkillSubVisible = false
        M.actionSkillSubRects = {}
        M.actionSkillSubRect = nil
        M.actionMenuVisible = false
        M.mageWaitingForClick = true  -- 等待玩家点击棋子重新打开菜单
        M.groundTargetCells = nil
        M.iceWallStartX = nil
        M.iceWallStartY = nil
        M.iceWallPreview = nil
        -- 重新计算可攻击格子
        if M.selectedUnit then
            M.attackableCells = M.getAttackableCells(M.selectedUnit, M.selectedUnit.x, M.selectedUnit.y)
            M.movableCells = {}
        end
        return true
    end
    return false
end

--- 获取玩家当前吟唱速度属性值
--- 被动技能加成已在 recalcStats 中合入 player.castSpeed
---@return number
function M.getCastSpeed()
    return (M.player and M.player.castSpeed) or 0
end

--- 消耗吟唱段数（含深度思维逻辑）
--- 如果装备了深度思维，清空所有段数并将额外消耗的段数转化为增伤
---@param skillId string 使用的技能ID
function M.consumeChantForSkill(skillId)
    if not M.player then return end
    M.player._deepThinkBonus = 0
    local castStages = M.getSkillCastStages(skillId)
    if castStages <= 0 then return end
    if (M.player.deepThinkDmgPer or 0) > 0 then
        local extra = math.max(0, (M.chantStages or 0) - castStages)
        if extra > 0 then
            M.player._deepThinkBonus = extra * M.player.deepThinkDmgPer
        end
        M.chantStages = 0
    else
        M.chantStages = math.max(0, (M.chantStages or 0) - castStages)
    end
end

--- 深度思维：消耗吟唱完成后剩余的所有段数（用于多回合吟唱完成时）
function M.consumeRemainingChantForDeepThink()
    if not M.player then return end
    M.player._deepThinkBonus = 0
    if (M.player.deepThinkDmgPer or 0) > 0 and (M.chantStages or 0) > 0 then
        M.player._deepThinkBonus = M.chantStages * M.player.deepThinkDmgPer
        M.chantStages = 0
    end
end

--- 回合开始时计算获得的吟唱段数
--- 基础1段 + 吟唱速度加成（每50点必定+1段，余数每点2%概率+1段，递推）
---@return number 本回合获得的段数
function M.rollChantStages()
    local stages = 1  -- 基础1段
    local castSpd = M.getCastSpeed()
    local remaining = castSpd
    -- 递推：每50点必定+1，余数每点2%概率+1
    while remaining > 0 do
        local guaranteed = math.floor(remaining / 50)
        stages = stages + guaranteed
        local leftover = remaining % 50
        if leftover > 0 then
            local chance = leftover * 2  -- 每点2%
            if math.random(100) <= chance then
                stages = stages + 1
            end
        end
        break  -- 非递归，一次处理完毕
    end
    return stages
end

--- 判断技能是否需要吟唱（法师/牧师有castStages的技能）
---@param skillId string
---@return number 需要的吟唱段数，0表示不需要吟唱
function M.getSkillCastStages(skillId)
    if M.currentClass ~= "mage" and M.currentClass ~= "priest" then return 0 end
    local def = M.SKILL_DEFS[skillId]
    if not def then return 0 end
    if def.freeAction then return 0 end  -- 闪烁等免费行动不需要吟唱
    return def.castStages or 0
end

--- 获取已学的主动技能列表（供行动菜单使用）
---@return table[]
function M.getLearnedActiveSkills()
    local result = {}
    for skillId, def in pairs(M.SKILL_DEFS) do
        if def.type == "active" then
            local lv = M.skillLevels[skillId] or 0
            if lv > 0 then
                -- 武器标签检查：不满足武器要求的技能不显示在菜单中
                if def.reqWeaponTag then
                    local weaponR = M.equipment and M.equipment["weapon_r"]
                    local weaponL = M.equipment and M.equipment["weapon_l"]
                    local curTag = weaponR and weaponR.weaponTag
                    if not curTag and weaponL and weaponL.weaponTag then
                        curTag = weaponL.weaponTag
                    end
                    if curTag ~= def.reqWeaponTag then goto continue end
                    if def.reqWeaponTag == "弓" then
                        if not weaponL or weaponL.category ~= "箭袋" then goto continue end
                    end
                end
                -- 左手装备类别检查
                if def.reqLeftCategory then
                    local weaponL = M.equipment and M.equipment["weapon_l"]
                    if not weaponL or weaponL.category ~= def.reqLeftCategory then goto continue end
                end
                local cd = M.skillCooldowns[skillId] or 0
                local cost = M.getSkillMpCost(skillId)
                local curMp = M.player and M.player.mp or 0
                local stages = M.getSkillCastStages(skillId)
                local chantReady = (stages <= 0) or (M.chantStages >= stages)
                table.insert(result, {
                    skillId = skillId,
                    name = def.name,
                    col = def.col,
                    ready = (cd <= 0 and curMp >= cost),
                    chantReady = chantReady,
                    castStages = stages,
                    cdLeft = cd,
                    mpCost = cost,
                    isAoe = def.aoe or false,
                })
                ::continue::
            end
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

--- 获取可装备到指定槽位的技能列表
---@param slotIndex number 目标槽位 (1..5)
---@return table[] 技能信息数组
function M.getEquippableSkills(slotIndex)
    local layerReq = { 0, 5, 15, 25, 35, 45 }
    local totalInvested = 0
    for _, lv in pairs(M.skillLevels) do
        totalInvested = totalInvested + lv
    end

    local result = {}
    for row = 1, #M.SKILL_TREE_LAYOUT do
        local cols = M.SKILL_TREE_LAYOUT[row]
        local req = layerReq[row] or 0
        if totalInvested >= req then
            for c = 1, #cols do
                local skillId = cols[c]
                if skillId then
                    local def = M.SKILL_DEFS[skillId]
                    local lv = M.skillLevels[skillId] or 0
                    if lv > 0 and def and def.type == "active" then
                        local equippedInSlot = nil
                        for i = 1, M.ACTIVE_SKILL_SLOTS do
                            if M.activeSkills[i] == skillId then
                                equippedInSlot = i
                                break
                            end
                        end
                        -- 检查施展条件（武器标签、左手装备类别）
                        local disabled = false
                        local disabledReason = nil
                        if def.reqWeaponTag then
                            local weaponR = M.equipment and M.equipment["weapon_r"]
                            local weaponL = M.equipment and M.equipment["weapon_l"]
                            local curTag = weaponR and weaponR.weaponTag
                            if not curTag and weaponL and weaponL.weaponTag then
                                curTag = weaponL.weaponTag
                            end
                            if curTag ~= def.reqWeaponTag then
                                disabled = true
                                disabledReason = "需要装备" .. def.reqWeaponTag
                            end
                            if not disabled and def.reqWeaponTag == "弓" then
                                if not weaponL or weaponL.category ~= "箭袋" then
                                    disabled = true
                                    disabledReason = "需要装备箭袋"
                                end
                            end
                        end
                        if not disabled and def.reqLeftCategory then
                            local weaponL = M.equipment and M.equipment["weapon_l"]
                            if not weaponL or weaponL.category ~= def.reqLeftCategory then
                                disabled = true
                                disabledReason = "需要装备" .. def.reqLeftCategory
                            end
                        end
                        -- 冲锋技能拆分为"侧翼冲锋"和"正面冲锋"两个选项
                        if def.charge then
                            local curMode = M.autoChargeMode or "flank"
                            local modes = {
                                { mode = "flank", name = "侧翼冲锋" },
                                { mode = "front", name = "正面冲锋" },
                            }
                            for _, cm in ipairs(modes) do
                                local isThisEquipped = (equippedInSlot ~= nil) and (curMode == cm.mode)
                                table.insert(result, {
                                    skillId = skillId,
                                    name = cm.name,
                                    col = def.col,
                                    row = row,
                                    level = lv,
                                    equipped = isThisEquipped,
                                    equippedInSlot = isThisEquipped and equippedInSlot or nil,
                                    disabled = disabled,
                                    disabledReason = disabledReason,
                                    chargeMode = cm.mode,
                                })
                            end
                        else
                            table.insert(result, {
                                skillId = skillId,
                                name = M.SKILL_DEFS[skillId].name,
                                col = M.SKILL_DEFS[skillId].col,
                                row = row,
                                level = lv,
                                equipped = (equippedInSlot ~= nil),
                                equippedInSlot = equippedInSlot,
                                disabled = disabled,
                                disabledReason = disabledReason,
                            })
                        end
                    end
                end
            end
        end
    end
    return result
end

end  -- sub.init

return sub
