-- ============================================================
-- GameState_Items.lua  —— 物品/装备/附魔/精炼/强化/背包/仓库
-- 由 GameState.lua 拆分，通过 init(M) 挂载到主模块
-- ============================================================

local sub = {}

function sub.init(M)

-- ====================================================================
-- 附魔池
-- ====================================================================
-- tiers[1]=T0 .. tiers[10]=T9；nil 表示该等阶不进入随机池
M.ENCHANT_POOL = {
    -- 八维属性（防具池 ×2）
    { attr = "str",       name = "力量",       tiers = { 0.6, 1.0, 1.6, 2.0, 2.6, 3.0, 3.6, 4.0, 4.6, 5.0 } },
    { attr = "agi",       name = "敏捷",       tiers = { 0.6, 1.0, 1.6, 2.0, 2.6, 3.0, 3.6, 4.0, 4.6, 5.0 } },
    { attr = "con",       name = "体质",       tiers = { 0.6, 1.0, 1.6, 2.0, 2.6, 3.0, 3.6, 4.0, 4.6, 5.0 } },
    { attr = "wis",       name = "智慧",       tiers = { 0.6, 1.0, 1.6, 2.0, 2.6, 3.0, 3.6, 4.0, 4.6, 5.0 } },
    { attr = "foc",       name = "专注",       tiers = { 0.6, 1.0, 1.6, 2.0, 2.6, 3.0, 3.6, 4.0, 4.6, 5.0 } },
    { attr = "per",       name = "感知",       tiers = { 0.6, 1.0, 1.6, 2.0, 2.6, 3.0, 3.6, 4.0, 4.6, 5.0 } },
    { attr = "wil",       name = "意念",       tiers = { 0.6, 1.0, 1.6, 2.0, 2.6, 3.0, 3.6, 4.0, 4.6, 5.0 } },
    { attr = "luk",       name = "幸运",       tiers = { 0.6, 1.0, 1.6, 2.0, 2.6, 3.0, 3.6, 4.0, 4.6, 5.0 } },
    { attr = "cha",       name = "魅力",       tiers = { 0.6, 1.0, 1.6, 2.0, 2.6, 3.0, 3.6, 4.0, 4.6, 5.0 } },
    -- 攻防
    { attr = "atk",       name = "物理攻击力", tiers = { 2, 4, 6, 8, 10, 12, 14, 16, 18, 20 } },
    { attr = "mAtk",      name = "魔法攻击力", tiers = { 2, 4, 6, 8, 10, 12, 14, 16, 18, 20 } },
    { attr = "def",       name = "物理防御力", tiers = { 3, 6, 9, 12, 15, 18, 21, 24, 27, 30 } },
    { attr = "mDef",      name = "魔法防御力", tiers = { 3, 6, 9, 12, 15, 18, 21, 24, 27, 30 } },
    -- 暴击
    { attr = "critVal",   name = "物理暴击值", tiers = { 2, 4, 6, 8, 10, 12, 14, 16, 18, 20 } },
    { attr = "critDmg",   name = "物理暴击伤害", tiers = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, suffix = "%" },
    { attr = "mCritRate", name = "魔法暴击值", tiers = { 2, 4, 6, 8, 10, 12, 14, 16, 18, 20 } },
    { attr = "mCritDmg",  name = "魔法暴击伤害", tiers = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, suffix = "%" },
    -- 速度（防具池 ×2）
    { attr = "atkSpeed",  name = "攻击速度",   tiers = { 0.4, 0.6, 1.0, 1.2, 1.6, 1.8, 2.2, 2.4, 2.8, 3.0 } },
    { attr = "castSpeed", name = "吟唱速度",   tiers = { 0.4, 0.6, 1.0, 1.2, 1.6, 1.8, 2.2, 2.4, 2.8, 3.0 } },
    -- 武器伤害加成（防具池 ×2，T5 起可用）
    { attr = "swordDmgBonus",  name = "剑伤害加成",   tiers = { nil, nil, nil, nil, nil, 3.0, 3.5, 4.0, 5.0, 6.0 }, suffix = "%" },
    { attr = "daggerDmgBonus", name = "匕首伤害加成", tiers = { nil, nil, nil, nil, nil, 3.0, 3.5, 4.0, 5.0, 6.0 }, suffix = "%" },
    { attr = "maceDmgBonus",   name = "钉锤伤害加成", tiers = { nil, nil, nil, nil, nil, 3.0, 3.5, 4.0, 5.0, 6.0 }, suffix = "%" },
    { attr = "bowDmgBonus",    name = "弓伤害加成",   tiers = { nil, nil, nil, nil, nil, 3.0, 3.5, 4.0, 5.0, 6.0 }, suffix = "%" },
    { attr = "staffDmgBonus",  name = "法杖伤害加成", tiers = { nil, nil, nil, nil, nil, 3.0, 3.5, 4.0, 5.0, 6.0 }, suffix = "%" },
    -- 通用伤害加成（防具池 ×2，T5 起可用）
    { attr = "physDmgBonus",   name = "物理伤害加成", tiers = { nil, nil, nil, nil, nil, 2.0, 2.4, 2.8, 3.4, 4.0 }, suffix = "%" },
    { attr = "magDmgBonus",    name = "魔法伤害加成", tiers = { nil, nil, nil, nil, nil, 2.0, 2.4, 2.8, 3.4, 4.0 }, suffix = "%" },
    -- 元素伤害加成（防具池 ×2，T5 起可用）
    { attr = "fireDmgBonus",   name = "火焰伤害加成", tiers = { nil, nil, nil, nil, nil, 3.0, 3.5, 4.0, 5.0, 6.0 }, suffix = "%" },
    { attr = "iceDmgBonus",    name = "冰冻伤害加成", tiers = { nil, nil, nil, nil, nil, 3.0, 3.5, 4.0, 5.0, 6.0 }, suffix = "%" },
    { attr = "elecDmgBonus",   name = "雷电伤害加成", tiers = { nil, nil, nil, nil, nil, 3.0, 3.5, 4.0, 5.0, 6.0 }, suffix = "%" },
    { attr = "lightDmgBonus",  name = "神圣伤害加成", tiers = { nil, nil, nil, nil, nil, 3.0, 3.5, 4.0, 5.0, 6.0 }, suffix = "%" },
    -- 元素抗性（防具池 ×2，T5 起可用）
    { attr = "resFire",   name = "火焰抗性",   tiers = { nil, nil, nil, nil, nil, 1.8, 2.2, 2.4, 2.8, 3.0 }, suffix = "%" },
    { attr = "resIce",    name = "冰冻抗性",   tiers = { nil, nil, nil, nil, nil, 1.8, 2.2, 2.4, 2.8, 3.0 }, suffix = "%" },
    { attr = "resElec",   name = "雷电抗性",   tiers = { nil, nil, nil, nil, nil, 1.8, 2.2, 2.4, 2.8, 3.0 }, suffix = "%" },
    { attr = "resLight",  name = "神圣抗性",   tiers = { nil, nil, nil, nil, nil, 1.8, 2.2, 2.4, 2.8, 3.0 }, suffix = "%" },
    { attr = "resDark",   name = "暗影抗性",   tiers = { nil, nil, nil, nil, nil, 1.8, 2.2, 2.4, 2.8, 3.0 }, suffix = "%" },
    { attr = "resNature", name = "自然抗性",   tiers = { nil, nil, nil, nil, nil, 1.8, 2.2, 2.4, 2.8, 3.0 }, suffix = "%" },
    -- 吸血（防具池 ×2）
    { attr = "physLifesteal", name = "物理吸血", tiers = { 0.50, 0.54, 0.60, 0.64, 0.70, 0.74, 0.80, 0.84, 0.90, 1.00 }, suffix = "%" },
    { attr = "magLifesteal",  name = "法术吸血", tiers = { 0.50, 0.54, 0.60, 0.64, 0.70, 0.74, 0.80, 0.84, 0.90, 1.00 }, suffix = "%" },
    -- 命中/闪避/避开要害
    { attr = "hit",       name = "命中值",     tiers = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 } },
    { attr = "dodge",     name = "闪避值",     tiers = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 } },
    { attr = "avoidCrit", name = "避开要害",   tiers = { 2, 4, 6, 8, 10, 12, 14, 16, 18, 20 } },
    -- 生命/魔法
    { attr = "hp",        name = "最大生命值", tiers = { 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 } },
    { attr = "mp",        name = "最大魔法值", tiers = { 5, 10, 15, 20, 25, 30, 35, 40, 45, 50 } },
    { attr = "hpRegen",   name = "HP回复",     tiers = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 } },
    { attr = "mpRegen",   name = "MP回复",     tiers = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 } },
    -- 魔力回收（根据魔法伤害百分比回复MP）
    { attr = "manaLeech", name = "魔力回收",   tiers = { 0.20, 0.22, 0.24, 0.26, 0.28, 0.30, 0.32, 0.34, 0.36, 0.40 }, suffix = "%" },
}
M.ENCHANT_CHANCE = 0.33  -- 33% 附魔概率

--- 为物品随机附魔
---@param item table 物品实例
---@param tier number 0-9
function M.rollEnchantment(item, tier)
    if not item then return end
    -- 按 tier 过滤可用属性（tiers[tier+1] 非 nil 才进入池）
    local candidates = {}
    for _, entry in ipairs(M.ENCHANT_POOL) do
        if entry.tiers[tier + 1] then
            candidates[#candidates + 1] = entry
        end
    end
    if #candidates == 0 then return end
    local roll = candidates[math.random(#candidates)]
    item.enchantment = {
        attr       = roll.attr,
        name       = roll.name,
        value      = roll.tiers[tier + 1],
        suffix     = roll.suffix or "",
        rolledTier = tier,
    }
end



-- ====================================================================
-- 深渊词缀系统
-- ====================================================================
M.ABYSS_AFFIX_CHANCE = 0.33  -- 33% 深渊词缀概率

--- 深渊词缀池
--- id: 唯一标识, name: 显示名, desc: 效果描述, mechanic: 战斗机制标识
M.ABYSS_AFFIX_POOL = {
    {
        id   = "ranged_bounce",
        name = "弹射",
        desc = "远程普攻命中后向3格内另一名敌军弹射，造成100%伤害",
        mechanic = "ranged_bounce",
    },
    {
        id   = "multi_cast",
        name = "多重远程技能",
        desc = "施放远程技能时，额外选择攻击范围内1个目标释放同一技能",
        mechanic = "multi_cast",
    },
    {
        id   = "ranged_scatter",
        name = "散射",
        desc = "远程普攻额外攻击攻击范围内1个其他目标",
        mechanic = "ranged_scatter",
    },
    {
        id   = "melee_splash",
        name = "溅射",
        desc = "近战攻击对周围敌人造成30%溅射伤害",
        mechanic = "melee_splash",
    },
    {
        id   = "melee_splash_range",
        name = "溅射扩展",
        desc = "近战攻击溅射范围+1",
        mechanic = "melee_splash_range",
    },
    {
        id   = "skill_aoe_range",
        name = "技能扩展",
        desc = "技能作用范围+1",
        mechanic = "skill_aoe_range",
    },
    {
        id   = "melee_phantom",
        name = "幻影",
        desc = "近战普通攻击时，幻影在范围内额外敌人背后发动一次普通攻击",
        mechanic = "melee_phantom",
    },
    {
        id   = "chain_lightning",
        name = "闪电链",
        desc = "攻击时50%概率触发闪电链",
        mechanic = "chain_lightning",
    },
    {
        id   = "radiance",
        name = "辉光",
        desc = "根据治疗量的300%对2格范围内的敌人造成神圣魔法伤害",
        mechanic = "radiance",
    },
    {
        id   = "thorns",
        name = "利刺",
        desc = "格挡时，根据玩家物理防御力的80%对目标造成物理伤害",
        mechanic = "thorns",
    },
    {
        id   = "quick_cooldown",
        name = "极速冷却",
        desc = "主动技能冷却时间-1",
        mechanic = "quick_cooldown",
    },
}

--- 为深渊掉落的物品随机附加深渊词缀
---@param item table 物品实例
function M.rollAbyssAffix(item)
    if not item then return end
    if math.random() >= M.ABYSS_AFFIX_CHANCE then return end
    local roll = M.ABYSS_AFFIX_POOL[math.random(#M.ABYSS_AFFIX_POOL)]
    item.abyssAffix = {
        id   = roll.id,
        name = roll.name,
        desc = roll.desc,
        mechanic = roll.mechanic,
    }
end

--- 根据模板 + 保存的档位索引重建深渊装备的 effects / extraEffects
--- 用于存档加载时，让模板变更自动同步到已有装备
---@param item table 物品实例（必须有 templateId、abyssStatTiers）
function M.rebuildAbyssStats(item)
    if not item or not item.templateId then return end
    local tpl = M.itemTemplates[item.templateId]
    if not tpl or not tpl.abyssRandomStats then return end
    local abyssRand = tpl.abyssRandomStats
    local tiers = item.abyssStatTiers or {}

    -- 从模板基础值开始重建 effects
    local newEff = {}
    for k, v in pairs(tpl.effects or {}) do newEff[k] = v end
    if abyssRand.effects then
        for k, rule in pairs(abyssRand.effects) do
            local idx = tiers[k]
            if idx and rule.values and rule.values[idx] then
                if rule.type == "pct_uniform" and newEff[k] then
                    local pct = rule.values[idx]
                    newEff[k] = math.floor(newEff[k] * (1 + pct / 100) + 0.5)
                elseif rule.type == "uniform" then
                    newEff[k] = rule.values[idx]
                end
            end
        end
    end
    item.effects = newEff

    -- 从模板基础值开始重建 extraEffects
    local newExtra = {}
    for k, v in pairs(tpl.extraEffects or {}) do newExtra[k] = v end
    if abyssRand.extraEffects then
        for k, rule in pairs(abyssRand.extraEffects) do
            local idx = tiers[k]
            -- 兼容老存档：模板新增了词条但存档中没有对应 tier，随机一个档位
            if not idx and rule.type == "uniform" and rule.values and #rule.values > 0 then
                idx = math.random(#rule.values)
                tiers[k] = idx
                item.abyssStatTiers = tiers
            end
            if idx and rule.type == "uniform" and rule.values and rule.values[idx] then
                newExtra[k] = rule.values[idx]
            end
        end
    end
    -- allstat_lines：根据保存的档位重建
    if abyssRand.allstat_lines and item.allstatLines then
        local asl = abyssRand.allstat_lines
        for i, line in ipairs(item.allstatLines) do
            local idx = line.tier
            if idx and asl.values and asl.values[idx] then
                local val = asl.values[idx]
                line.value = val  -- 更新保存的 value
                for _, ak in ipairs(asl.keys) do
                    newExtra[ak] = (newExtra[ak] or 0) + val
                end
            end
        end
    end
    -- randomResist：根据保存的 key+档位重建，支持单对象或数组（多段独立随机池）
    -- 若模板 templateVersion 与存档不符，重新随机所有词条（结构变更迁移）
    if abyssRand.randomResist then
        local rrList = abyssRand.randomResist
        if rrList.pool then rrList = { rrList } end  -- 单对象兼容

        local currentVer = tpl.templateVersion or 1
        local savedVer   = item.templateVersion or 1
        local needReroll = (currentVer ~= savedVer) or (not item.randomResistLines)

        if needReroll then
            -- 版本不一致或首次：重新随机，丢弃旧词条（有放回抽样，允许重复）
            local resistResults = {}
            for _, rr in ipairs(rrList) do
                local pool = rr.pool
                for i = 1, rr.count or 3 do
                    local key = pool[math.random(#pool)]
                    local idx = math.random(#rr.values)
                    local val = rr.values[idx]
                    newExtra[key] = (newExtra[key] or 0) + val
                    resistResults[#resistResults + 1] = { key = key, value = val, tier = idx }
                end
            end
            item.randomResistLines = resistResults
            item.abyssStatTiers    = tiers
            item.templateVersion   = currentVer
        else
            -- 版本一致：按存档 tier 重建数值（数值可随模板更新）
            local keyValues = {}
            for _, rr in ipairs(rrList) do
                for _, k in ipairs(rr.pool) do keyValues[k] = rr.values end
            end
            for _, entry in ipairs(item.randomResistLines) do
                local idx  = entry.tier
                local vals = keyValues[entry.key]
                if idx and vals and vals[idx] then
                    local val = vals[idx]
                    entry.value = val
                    newExtra[entry.key] = (newExtra[entry.key] or 0) + val
                end
            end
        end
    end
    -- randomMainBase：根据保存的 key 重建基础属性（支持固定值和多档位）
    if abyssRand.randomMainBase and item.randomMainBaseLines then
        local rmb = abyssRand.randomMainBase
        for _, entry in ipairs(item.randomMainBaseLines) do
            local val
            if rmb.values and entry.tier and rmb.values[entry.tier] then
                val = rmb.values[entry.tier]
            else
                val = rmb.value or entry.value or 1
            end
            entry.value = val
            newEff[entry.key] = (newEff[entry.key] or 0) + val
            tiers[entry.key] = entry.tier  -- 记录档位，用于 tooltip 档位颜色/三角指示
        end
    end
    -- randomMainExtra：根据保存的 key+档位重建附加属性词缀
    if abyssRand.randomMainExtra and item.randomMainExtraLines then
        local rme = abyssRand.randomMainExtra
        for _, entry in ipairs(item.randomMainExtraLines) do
            local idx = entry.tier
            if idx and rme.values and rme.values[idx] then
                local val = rme.values[idx]
                entry.value = val
                newExtra[entry.key] = (newExtra[entry.key] or 0) + val
            end
        end
    end
    item.effects = newEff
    item.extraEffects = newExtra

    -- 同步模板可能变更的固定字段
    item.name = tpl.name
    if item.enhanceLevel and item.enhanceLevel > 0 then
        item.name = tpl.name .. " +" .. item.enhanceLevel
    end
    item.desc = tpl.desc
    item.icon = tpl.icon
    item.category = tpl.category
    item.rarity = tpl.rarity
    item.level = tpl.level
    item.special = tpl.special
    item.setId = tpl.setId
    item.weaponTag = tpl.weaponTag
    item.offhandTag = tpl.offhandTag
    item.heroAffix = tpl.heroAffix
end

-- ====================================================================
-- 精炼系统
-- ====================================================================
--- 精炼槽位概率表（索引 0-9 对应 T0-T9，值为 {0槽概率, 1槽, 2槽, 3槽, 4槽}）
M.REFINE_SLOT_CHANCES = {
    [0] = { 0.50, 0.40, 0.10, 0,    0    },  -- T0
    [1] = { 0.40, 0.40, 0.20, 0,    0    },  -- T1
    [2] = { 0.30, 0.30, 0.30, 0.10, 0    },  -- T2
    [3] = { 0.20, 0.30, 0.30, 0.20, 0    },  -- T3
    [4] = { 0.10, 0.20, 0.30, 0.30, 0.10 },  -- T4
    [5] = { 0,    0.20, 0.40, 0.30, 0.10 },  -- T5
    [6] = { 0,    0.10, 0.40, 0.40, 0.10 },  -- T6
    [7] = { 0,    0,    0.50, 0.40, 0.10 },  -- T7
    [8] = { 0,    0,    0.40, 0.50, 0.10 },  -- T8
    [9] = { 0,    0,    0.30, 0.50, 0.20 },  -- T9
}
-- 铁匠铺费率表（稀有度×T级），用于：精炼燃料费、强化加工费、精炼加工费
local SMITHING_FEE_TABLE = {
    common   = { 109,  164,  246,  370,  555,  833, 1000, 1200, 1440, 1727 },
    uncommon = { 131,  197,  296,  444,  666, 1000, 1200, 1440, 1728, 2073 },
    rare     = { 157,  236,  355,  532,  799, 1200, 1440, 1728, 2073, 2487 },
    fine     = { 188,  283,  426,  638,  958, 1440, 1728, 2073, 2487, 2984 },
    superior = { 675, 1017, 1533, 2295, 3447, 5184, 6219, 7461, 8952, 10740 },
}

--- 查询铁匠铺费率（根据稀有度和T级）
--- 判断是否为深渊装备（按 templateId 前缀，不依赖词缀）
local function isAbyssEquip(item)
    local tid = item and item.templateId
    return tid and tid:sub(1, 6) == "abyss_"
end

---@param item table 装备物品实例
---@return number fee 单项费率（金币）
local function lookupSmithingFee(item)
    if not item then return 0 end
    local tpl = item.templateId and M.itemTemplates[item.templateId]
    local rarity = tpl and tpl.rarity or item.rarity or "common"
    local level = tpl and tpl.level or item.level or 1
    local tier = math.max(0, math.min(9, math.floor((level - 1) / 10)))
    local tbl = SMITHING_FEE_TABLE[rarity]
    if not tbl then return 109 end  -- fallback to N-T0
    return tbl[tier + 1] or tbl[10]
end

--- 获取加工费（强化/精炼通用）
---@param item table 装备物品实例
---@return number fee 加工费（金币）
function M.getProcessingFee(item)
    if M.homeCraftMode then return 0 end
    return lookupSmithingFee(item)
end

--- 获取精炼总费用（燃料费 + 加工费）
---@param item table 装备物品实例
---@return number cost 精炼总费用（金币）
function M.getRefineCost(item)
    local fuelCost = lookupSmithingFee(item)
    if isAbyssEquip(item) then fuelCost = fuelCost * 2 end
    local processingFee = M.getProcessingFee(item)
    return fuelCost + processingFee
end

--- 获取精炼费用明细（燃料费 + 加工费分开）
---@param item table 装备物品实例
---@return number fuelCost 燃料费
---@return number processingFee 加工费
function M.getRefineCostBreakdown(item)
    if not item then return 0, 0 end
    local fuelCost = lookupSmithingFee(item)
    if isAbyssEquip(item) then fuelCost = fuelCost * 2 end
    local processingFee = M.getProcessingFee(item)
    return fuelCost, processingFee
end
M.TOUGHNESS_REPAIR_COST = 1  -- 韧性修复费用（金币）-- 已弃用，保留兼容

--- 获取修复费用明细（燃料费30% + 加工费50%，基于装备当前价值）
---@param item table 装备物品实例
---@return number fuelCost 燃料费
---@return number processingFee 加工费
function M.getRepairCostBreakdown(item)
    if not item then return 0, 0 end
    local val = item.value or 0
    local tpl = M.itemTemplates[item.templateId]
    if tpl and tpl.value and tpl.value > val then val = tpl.value end
    local fuelCost = math.max(1, math.floor(val * 0.3))
    if isAbyssEquip(item) then fuelCost = fuelCost * 2 end
    local processingFee = M.homeCraftMode and 0 or math.max(1, math.floor(val * 0.5))
    return fuelCost, processingFee
end

--- 获取修复总费用
---@param item table 装备物品实例
---@return number totalCost
function M.getRepairCost(item)
    local f, p = M.getRepairCostBreakdown(item)
    return f + p
end
M.REFINE_STONE_DROP_CHANCE = 0.07  -- 精炼石掉落概率（7%）

--- 根据装备等级获取所需精炼石阶数（1~10）
---@param item table 装备物品实例
---@return number tier 精炼石阶数 1~10
function M.getRequiredStoneTier(item)
    local level = item.level or 0
    return math.max(2, math.min(10, math.ceil(level / 10)))
end

--- 获取装备所需精炼石的模板ID（精确匹配阶数）
---@param item table 装备物品实例
---@return string templateId 精炼石模板ID
function M.getRequiredStoneId(item)
    return "refine_stone_" .. M.getRequiredStoneTier(item)
end

--- 获取背包中指定装备可用的精炼石总数（高阶石兼容低阶装备）
--- 从装备所需阶数开始，向上累加所有可用精炼石
---@param item table 装备物品实例
---@return number count 精炼石总数
function M.countRefineStones(item)
    local minTier = M.getRequiredStoneTier(item)
    local total = 0
    for t = minTier, 10 do
        total = total + M.countInventoryItem("refine_stone_" .. t)
    end
    return total
end

--- 查找实际将被消耗的精炼石阶数（优先低阶，逐步向高阶检索）
--- 高阶精炼石兼容低阶装备
---@param item table 装备物品实例
---@return number|nil tier 实际可用的精炼石阶数，无库存返回 nil
function M.findAvailableStoneTier(item)
    local minTier = M.getRequiredStoneTier(item)
    for t = minTier, 10 do
        if M.countInventoryItem("refine_stone_" .. t) > 0 then
            return t
        end
    end
    return nil
end

--- 消耗一个精炼石（优先消耗最低可用阶数，高阶石兼容低阶装备）
---@param item table 装备物品实例
---@return boolean success 是否成功
function M.consumeRefineStone(item)
    local tier = M.findAvailableStoneTier(item)
    if not tier then return false end
    return M.removeInventoryItem("refine_stone_" .. tier, 1)
end

--- 获取装备的最大精炼韧性（基于 T 级）
---@param item table
---@return number
function M.getMaxRefineToughness(item)
    local tier = M.getItemTier(item)
    return (tier + 1) * 5  -- T0=5, T1=10, T2=15, T3=20 ...
end

--- 确保装备拥有 refineToughness 字段（初始化）
---@param item table
function M.ensureRefineToughness(item)
    if item.refineToughness == nil and item.refineSlots then
        item.refineToughness = M.getMaxRefineToughness(item)
    end
end

--- 修复精炼韧性（补充10点，需要金币 + 神炼增韧剂）
---@return boolean, string
function M.repairToughness()
    local item = M.repairSlotItem
    if not item then return false, "未放入物品" end
    M.ensureRefineToughness(item)
    local max = M.getMaxRefineToughness(item)
    if not item.refineToughness or item.refineToughness >= max then
        return false, "韧性已满，无需修复"
    end
    local cost = M.getRepairCost(item)
    if M.gold < cost then return false, "金币不足（需要 " .. cost .. "G）" end

    local agentCount = M.countInventoryItem("divine_toughness_agent")
    if agentCount < 1 then return false, "需要1瓶神炼增韧剂" end

    M.gold = M.gold - cost
    M.removeInventoryItem("divine_toughness_agent", 1)
    local before = item.refineToughness
    item.refineToughness = math.min(max, item.refineToughness + 10)
    local restored = item.refineToughness - before
    return true, "韧性修复+" .. restored .. "点！（消耗1瓶神炼增韧剂）"
end

--- 精炼词缀池（独立于附魔池，数值和条目不同）
M.REFINE_POOL = {
    -- 八维属性 (T0-T9)
    { attr = "str",       name = "力量",         tiers = { 0.3, 0.5, 0.8, 1.0, 1.3, 1.5, 1.8, 2.0, 2.3, 2.5 } },
    { attr = "agi",       name = "敏捷",         tiers = { 0.3, 0.5, 0.8, 1.0, 1.3, 1.5, 1.8, 2.0, 2.3, 2.5 } },
    { attr = "con",       name = "体质",         tiers = { 0.3, 0.5, 0.8, 1.0, 1.3, 1.5, 1.8, 2.0, 2.3, 2.5 } },
    { attr = "wis",       name = "智慧",         tiers = { 0.3, 0.5, 0.8, 1.0, 1.3, 1.5, 1.8, 2.0, 2.3, 2.5 } },
    { attr = "foc",       name = "专注",         tiers = { 0.3, 0.5, 0.8, 1.0, 1.3, 1.5, 1.8, 2.0, 2.3, 2.5 } },
    { attr = "per",       name = "感知",         tiers = { 0.3, 0.5, 0.8, 1.0, 1.3, 1.5, 1.8, 2.0, 2.3, 2.5 } },
    { attr = "wil",       name = "意念",         tiers = { 0.3, 0.5, 0.8, 1.0, 1.3, 1.5, 1.8, 2.0, 2.3, 2.5 } },
    { attr = "luk",       name = "幸运",         tiers = { 0.3, 0.5, 0.8, 1.0, 1.3, 1.5, 1.8, 2.0, 2.3, 2.5 } },
    { attr = "cha",       name = "魅力",         tiers = { 0.3, 0.5, 0.8, 1.0, 1.3, 1.5, 1.8, 2.0, 2.3, 2.5 } },
    -- 攻防
    { attr = "atk",       name = "物理攻击力",   tiers = { 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0 } },
    { attr = "mAtk",      name = "魔法攻击力",   tiers = { 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0 } },
    { attr = "def",       name = "物理防御力",   tiers = { 1.5, 3.0, 4.5, 6.0, 7.5, 9.0, 10.5, 12.0, 13.5, 15.0 } },
    { attr = "mDef",      name = "魔法防御力",   tiers = { 1.5, 3.0, 4.5, 6.0, 7.5, 9.0, 10.5, 12.0, 13.5, 15.0 } },
    -- 暴击
    { attr = "critVal",   name = "物理暴击值",   tiers = { 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0 } },
    { attr = "critDmg",   name = "物理暴击伤害", tiers = { 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0 }, suffix = "%" },
    { attr = "mCritRate", name = "魔法暴击值",   tiers = { 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0 } },
    { attr = "mCritDmg",  name = "魔法暴击伤害", tiers = { 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0 }, suffix = "%" },
    -- 速度
    { attr = "atkSpeed",  name = "攻击速度",     tiers = { 0.2, 0.3, 0.5, 0.6, 0.8, 0.9, 1.1, 1.2, 1.4, 1.5 } },
    { attr = "castSpeed", name = "吟唱速度",     tiers = { 0.2, 0.3, 0.5, 0.6, 0.8, 0.9, 1.1, 1.2, 1.4, 1.5 } },
    -- 武器伤害加成 (T5起)
    { attr = "swordDmgBonus",  name = "剑伤害加成",   tiers = { nil, nil, nil, nil, nil, 1.5, 1.75, 2.0, 2.5, 3.0 }, suffix = "%" },
    { attr = "daggerDmgBonus", name = "匕首伤害加成", tiers = { nil, nil, nil, nil, nil, 1.5, 1.75, 2.0, 2.5, 3.0 }, suffix = "%" },
    { attr = "maceDmgBonus",   name = "钉锤伤害加成", tiers = { nil, nil, nil, nil, nil, 1.5, 1.75, 2.0, 2.5, 3.0 }, suffix = "%" },
    { attr = "bowDmgBonus",    name = "弓伤害加成",   tiers = { nil, nil, nil, nil, nil, 1.5, 1.75, 2.0, 2.5, 3.0 }, suffix = "%" },
    { attr = "staffDmgBonus",  name = "法杖伤害加成", tiers = { nil, nil, nil, nil, nil, 1.5, 1.75, 2.0, 2.5, 3.0 }, suffix = "%" },
    -- 通用伤害加成 (T5起)
    { attr = "physDmgBonus",   name = "物理伤害加成", tiers = { nil, nil, nil, nil, nil, 1.0, 1.2, 1.4, 1.7, 2.0 }, suffix = "%" },
    { attr = "magDmgBonus",    name = "魔法伤害加成", tiers = { nil, nil, nil, nil, nil, 1.0, 1.2, 1.4, 1.7, 2.0 }, suffix = "%" },
    -- 元素伤害加成 (T5起)
    { attr = "fireDmgBonus",   name = "火焰伤害加成", tiers = { nil, nil, nil, nil, nil, 1.5, 1.75, 2.0, 2.5, 3.0 }, suffix = "%" },
    { attr = "iceDmgBonus",    name = "冰冻伤害加成", tiers = { nil, nil, nil, nil, nil, 1.5, 1.75, 2.0, 2.5, 3.0 }, suffix = "%" },
    { attr = "elecDmgBonus",   name = "雷电伤害加成", tiers = { nil, nil, nil, nil, nil, 1.5, 1.75, 2.0, 2.5, 3.0 }, suffix = "%" },
    { attr = "lightDmgBonus",  name = "神圣伤害加成", tiers = { nil, nil, nil, nil, nil, 1.5, 1.75, 2.0, 2.5, 3.0 }, suffix = "%" },
    -- 元素抗性 (T5起)
    { attr = "resFire",   name = "火焰抗性",   tiers = { nil, nil, nil, nil, nil, 0.9, 1.1, 1.2, 1.4, 1.5 }, suffix = "%" },
    { attr = "resIce",    name = "冰冻抗性",   tiers = { nil, nil, nil, nil, nil, 0.9, 1.1, 1.2, 1.4, 1.5 }, suffix = "%" },
    { attr = "resElec",   name = "雷电抗性",   tiers = { nil, nil, nil, nil, nil, 0.9, 1.1, 1.2, 1.4, 1.5 }, suffix = "%" },
    { attr = "resLight",  name = "神圣抗性",   tiers = { nil, nil, nil, nil, nil, 0.9, 1.1, 1.2, 1.4, 1.5 }, suffix = "%" },
    { attr = "resDark",   name = "暗影抗性",   tiers = { nil, nil, nil, nil, nil, 0.9, 1.1, 1.2, 1.4, 1.5 }, suffix = "%" },
    { attr = "resNature", name = "自然抗性",   tiers = { nil, nil, nil, nil, nil, 0.9, 1.1, 1.2, 1.4, 1.5 }, suffix = "%" },
    -- 吸血
    { attr = "physLifesteal", name = "物理吸血", tiers = { 0.25, 0.27, 0.30, 0.32, 0.35, 0.37, 0.40, 0.42, 0.45, 0.50 }, suffix = "%" },
    { attr = "magLifesteal",  name = "法术吸血", tiers = { 0.25, 0.27, 0.30, 0.32, 0.35, 0.37, 0.40, 0.42, 0.45, 0.50 }, suffix = "%" },
    -- 命中/闪避/避开要害
    { attr = "hit",       name = "命中值",     tiers = { 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0 } },
    { attr = "dodge",     name = "闪避值",     tiers = { 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0 } },
    { attr = "avoidCrit", name = "避开要害",   tiers = { 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0 } },
    -- 生命/魔法
    { attr = "hp",        name = "最大生命值", tiers = { 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0 } },
    { attr = "mp",        name = "最大魔法值", tiers = { 2.5, 5.0, 7.5, 10.0, 12.5, 15.0, 17.5, 20.0, 22.5, 25.0 } },
    { attr = "hpRegen",   name = "HP回复",     tiers = { 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0 } },
    { attr = "mpRegen",   name = "MP回复",     tiers = { 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0 } },
    -- 魔力回收（根据魔法伤害百分比回复MP）
    { attr = "manaLeech", name = "魔力回收",   tiers = { 0.10, 0.11, 0.12, 0.13, 0.14, 0.15, 0.16, 0.17, 0.18, 0.20 }, suffix = "%" },
}

--- 为物品随机生成精炼槽位
---@param item table 物品实例
---@param tier number 0-9
function M.rollRefineSlots(item, tier)
    if not item then return end
    local chances = M.REFINE_SLOT_CHANCES[tier]
    if not chances then return end
    -- 按概率表随机决定槽位数
    local roll = math.random()
    local cumulative = 0
    local slotCount = 0
    for i = 1, 5 do
        cumulative = cumulative + chances[i]
        if roll <= cumulative then
            slotCount = i - 1  -- chances[1]=0槽概率, chances[2]=1槽概率, ...
            break
        end
    end
    if slotCount <= 0 then return end
    -- 创建空精炼槽数组
    item.refineSlots = {}
    for i = 1, slotCount do
        item.refineSlots[i] = {}
    end
    -- 掉落时每个空槽都自动随机携带一个精炼词缀
    for i = 1, slotCount do
        M.refineItem(item)
    end
end

--- 宝石插槽判定：10%概率获得1个宝石插槽
---@param item table 物品实例
function M.rollGemSlots(item)
    if not item or not item.slot then return end
    if math.random() < 0.10 then
        item.gemSlots = { {} }  -- 1个空宝石插槽
    end
end

--- 精炼物品：填充第一个空槽位
---@param item table 物品实例（必须有 refineSlots，tier 缺失时按 level 推算）
---@return boolean 是否成功
function M.refineItem(item)
    if not item or not item.refineSlots then return false end
    -- 找到第一个空槽
    local emptyIdx = nil
    for i, slot in ipairs(item.refineSlots) do
        if not slot.attr then
            emptyIdx = i
            break
        end
    end
    if not emptyIdx then return false end  -- 没有空槽
    -- 收集其他槽位已有的 attr（同装备同类型词条只能有一条）
    local usedAttrs = {}
    for i, slot in ipairs(item.refineSlots) do
        if i ~= emptyIdx and slot.attr then
            usedAttrs[slot.attr] = true
        end
    end
    -- 从 REFINE_POOL 中 T0~tier 所有可用条目等权重随机（排除已有类型）
    -- tier 缺失时（如兑换码直接发放的装备）按 level 推算，确保精炼可正常进行
    local tier = M.getItemTier(item)
    local candidates = {}
    for _, entry in ipairs(M.REFINE_POOL) do
        if not usedAttrs[entry.attr] then
            for t = 0, tier do
                if entry.tiers[t + 1] then
                    candidates[#candidates + 1] = { entry = entry, rolledTier = t }
                end
            end
        end
    end
    if #candidates == 0 then return false end
    local pick = candidates[math.random(#candidates)]
    item.refineSlots[emptyIdx] = {
        attr       = pick.entry.attr,
        name       = pick.entry.name,
        value      = pick.entry.tiers[pick.rolledTier + 1],
        suffix     = pick.entry.suffix or "",
        rolledTier = pick.rolledTier,
    }
    return true
end

--- 精炼物品：填充指定空槽位
---@param item table 物品实例（必须有 refineSlots，tier 缺失时按 level 推算）
---@param slotIdx number 目标槽位索引
---@return boolean 是否成功
function M.refineItemSlot(item, slotIdx)
    if not item or not item.refineSlots then return false end
    -- 韧性检查
    M.ensureRefineToughness(item)
    if item.refineToughness and item.refineToughness <= 0 then return false end
    local slot = item.refineSlots[slotIdx]
    if not slot or slot.attr then return false end  -- 槽位不存在或已填充
    -- 收集其他槽位已有的 attr（同装备同类型词条只能有一条）
    local usedAttrs = {}
    for i, s in ipairs(item.refineSlots) do
        if i ~= slotIdx and s.attr then
            usedAttrs[s.attr] = true
        end
    end
    -- 从 REFINE_POOL 中 T0~tier 所有可用条目等权重随机（排除已有类型）
    -- tier 缺失时（如兑换码直接发放的装备）按 level 推算，确保精炼可正常进行
    local tier = M.getItemTier(item)
    local candidates = {}
    for _, entry in ipairs(M.REFINE_POOL) do
        if not usedAttrs[entry.attr] then
            for t = 0, tier do
                if entry.tiers[t + 1] then
                    candidates[#candidates + 1] = { entry = entry, rolledTier = t }
                end
            end
        end
    end
    if #candidates == 0 then return false end
    local pick = candidates[math.random(#candidates)]
    item.refineSlots[slotIdx] = {
        attr       = pick.entry.attr,
        name       = pick.entry.name,
        value      = pick.entry.tiers[pick.rolledTier + 1],
        suffix     = pick.entry.suffix or "",
        rolledTier = pick.rolledTier,
    }
    -- 扣减韧性
    if item.refineToughness then
        item.refineToughness = item.refineToughness - 1
    end
    return true
end

--- 重铸精炼槽：对已有词缀的槽位重新随机
---@param item table 物品实例（必须有 refineSlots 和 tier）
---@param slotIdx number 目标槽位索引
---@return boolean 是否成功
function M.rerollRefineSlot(item, slotIdx)
    if not item or not item.refineSlots then return false end
    -- 韧性检查
    M.ensureRefineToughness(item)
    if item.refineToughness and item.refineToughness <= 0 then return false end
    local slot = item.refineSlots[slotIdx]
    if not slot or not slot.attr then return false end  -- 槽位不存在或为空
    -- 收集其他槽位已有的 attr（同装备同类型词条只能有一条，排除自身槽位）
    local usedAttrs = {}
    for i, s in ipairs(item.refineSlots) do
        if i ~= slotIdx and s.attr then
            usedAttrs[s.attr] = true
        end
    end
    -- 从 REFINE_POOL 中 T0~tier 所有可用条目等权重随机（排除已有类型）
    -- tier 缺失时按 level 推算
    local tier = M.getItemTier(item)
    local candidates = {}
    for _, entry in ipairs(M.REFINE_POOL) do
        if not usedAttrs[entry.attr] then
            for t = 0, tier do
                if entry.tiers[t + 1] then
                    candidates[#candidates + 1] = { entry = entry, rolledTier = t }
                end
            end
        end
    end
    if #candidates == 0 then return false end
    local pick = candidates[math.random(#candidates)]
    item.refineSlots[slotIdx] = {
        attr       = pick.entry.attr,
        name       = pick.entry.name,
        value      = pick.entry.tiers[pick.rolledTier + 1],
        suffix     = pick.entry.suffix or "",
        rolledTier = pick.rolledTier,
    }
    -- 扣减韧性
    if item.refineToughness then
        item.refineToughness = item.refineToughness - 1
    end
    return true
end

-- ====================================================================
-- 掉落组
-- ====================================================================
--- 野外基础掉落组（10件绿色装备，手动维护，不要自动按稀有度归入）
--- 基础 ID 列表（T0），高等级模板由 UNCOMMON_TIERED_IDS 索引
M.DROP_GROUP_FIELD_BASIC = {
    "copper_iron_sword",
    "inlaid_copper_bow",
    "copper_handle_dagger",
    "copper_handle_mace",
    "inlaid_copper_staff",
    "copper_wood_shield",
    "copper_chest_armor",
    "copper_leg_armor",
    "copper_helmet",
    "copper_shoulder",
    "copper_cloak",
    "copper_gloves",
    "copper_belt",
    "copper_boots",
    "copper_quiver",
    "copper_crystal_ball",
}

--- 吞下物品的史莱姆 Lv3 掉落组（等概率必掉其中一个）
M.DROP_GROUP_ITEM_SLIME = {
    "charm_sachet",
    "repel_sachet",
    "lucky_charm",
}

--- 吸血蝙蝠 Lv7 掉落组
M.DROP_GROUP_RARE_BAT = {
    "nature_cloak",
    "bat_fang_trinket",
    "bat_fang_dagger",
}

--- 白狼王 Lv10 掉落组
M.DROP_GROUP_WOLF_KING = {
    "wolf_fang_sword",
    "wolf_fang_dagger",
    "wolf_fang_mace",
    "wolf_fang_bow",
    "wolf_fang_staff",
}

--- 野猪王 Lv15 掉落组
M.DROP_GROUP_BOAR_KING = {
    "tough_belt",
    "tough_boots",
    "tough_hat",
}

--- 宝箱哥布林 Lv19 掉落组
M.DROP_GROUP_CHEST_GOBLIN = {
    "plain_ruby_ring",
    "plain_sapphire_ring",
    "plain_emerald_ring",
    "plain_obsidian_ring",
    "plain_opal_ring",
    "plain_topaz_ring",
    "plain_amethyst_ring",
    "plain_pink_ring",
    "plain_cyan_ring",
}

--- 幼年狼人 Lv24 掉落组
M.DROP_GROUP_WEREWOLF_PUP = {
    "wolf_ear_clip",
    "wolf_fur_cloak",
    "wolf_fang_pendant",
}

--- 吸血少女 Lv30 掉落组（吸血少年共用）
M.DROP_GROUP_VAMPIRE_GIRL = {
    "amethyst_necklace",
    "black_cat_trinket",
    "violent_bow_necklace",
}

--- 小黄金树根精 Lv34 掉落组
M.DROP_GROUP_GOLDEN_TREE = {
    "golden_tree_shield",
    "golden_tree_quiver",
    "golden_tree_crystal",
}

--- 奇怪的恶魔史莱姆 Lv38 掉落组
M.DROP_GROUP_STRANGE_DEMON = {
    "traveler_belt",
    "traveler_boots",
    "traveler_bow",
}

--- 骷髅王 Lv42 掉落组
M.DROP_GROUP_SKELETON_KING = {
    "skeleton_king_greatsword",
    "skeleton_king_mace",
    "skeleton_king_shoulder",
    "skeleton_king_cloak",
}

--- 阿灰 Lv46 掉落组
M.DROP_GROUP_GREY_GHOST = {
    "her_handkerchief",
    "magic_cloth_hat",
    "magic_cloth_belt",
}

--- 黑熊王 Lv47 掉落组
M.DROP_GROUP_BLACK_BEAR = {
    "bear_shield",
    "bear_mace",
    "bear_dagger",
}

--- 圆滚滚上等星恶魔 Lv80 掉落组
M.DROP_GROUP_STAR_DEMON = {
    "star_staff",
    "star_crystal_ball",
    "star_trinket",
}

--- 钢琴妖怪 Lv55 掉落组
M.DROP_GROUP_PIANO = {
    "classic_gloves",
    "classic_dress",
    "classic_watch",
}

--- 铜壳龟 Lv59 掉落组
M.DROP_GROUP_COPPER_TURTLE = {
    "copper_turtle_shield",
    "fortress_belt",
    "turtle_amulet",
}

--- 骑士人偶 Lv63 掉落组
M.DROP_GROUP_KNIGHT_DOLL = {
    "manor_knight_helmet",
    "manor_knight_legs",
    "manor_knight_chest",
    "manor_knight_shoulder",
    "manor_knight_gloves",
    "manor_knight_boots",
    "manor_knight_belt",
    "manor_knight_cloak",
}

--- 木乃伊法老 Lv68 掉落组
M.DROP_GROUP_PHARAOH = {
    "pharaoh_crown",
    "pharaoh_ring",
}

--- 大黄金树根精 Lv71 掉落组
M.DROP_GROUP_GOLDEN_GIANT_TREE = {
    "big_golden_tree_shield",
    "big_golden_tree_bow",
    "big_golden_tree_quiver",
    "big_golden_tree_ball",
    "big_golden_tree_mace",
}

--- 鱼人战士 Lv75 掉落组
M.DROP_GROUP_FISHMAN = {
    "fishman_gloves",
    "fishman_dagger",
    "fishman_necklace",
}

--- 半人马祭司 Lv80 掉落组
M.DROP_GROUP_CENTAUR_PRIEST = {
    "shadow_staff",
    "shadow_bow",
    "shadow_quiver",
    "shadow_hood",
    "shadow_robe",
    "shadow_bracers",
}

--- 胖乎乎上等星恶魔 Lv84 掉落组
M.DROP_GROUP_STAR_FAT = {
    "starlight_crystal",
    "starlight_sword",
    "starlight_mace",
    "starlight_dagger",
}

--- 形似章鱼的生物 Lv88 掉落组
M.DROP_GROUP_NAMELESS = {
    "mystery_boots",
    "mystery_trinket",
    "mystery_belt",
}

--- 花仙妖精 Lv92 掉落组
M.DROP_GROUP_FLOWER_FAIRY = {
    "sunflower_necklace",
    "flower_crown",
    "flower_bow",
    "lily_cloak",
}

--- 巴洛伯爵 Lv100 掉落组
M.DROP_GROUP_BARON = {
    "baron_helmet",
    "baron_legs",
    "baron_chest",
    "baron_shoulder",
    "baron_gloves",
    "baron_boots",
    "baron_sword",
    "baron_dagger",
    "baron_mace",
    "baron_shield",
}

--- 上等宇宙恶魔 Lv100 掉落组
M.DROP_GROUP_COSMOS_ELITE = {
    "arcane_hat",
    "arcane_pants",
    "arcane_robe",
    "arcane_shoulder",
    "arcane_gloves",
    "arcane_boots",
    "arcane_staff",
    "arcane_dagger",
    "arcane_crystal",
}

--- 伪奇美拉 Lv100 掉落组
M.DROP_GROUP_FAKE_CHIMERA = {
    "sly_mask",
    "sly_pants",
    "sly_chest",
    "sly_shoulder",
    "sly_gloves",
    "sly_boots",
    "sly_sword",
    "sly_bow",
    "sly_dagger",
    "sly_quiver",
}

-- ====================================================================
-- 套装定义
-- ====================================================================
M.SET_DEFS = {

    baron_baro = {
        name   = "伯爵",
        pieces = {
            "baron_helmet", "baron_legs", "baron_chest", "baron_shoulder",
            "baron_gloves", "baron_boots", "baron_sword", "baron_dagger",
            "baron_mace", "baron_shield",
        },
        bonuses = {
            { count = 2, effects = { hp = 150, mp = -30 },              desc = "最大生命值+150、最大魔法值-30" },
            { count = 4, effects = { critVal = 10, mp = -30 },          desc = "物理暴击值+10、最大魔法值-30" },
            { count = 6, effects = { str = 10, mp = -30 },              desc = "力量+10、最大魔法值-30" },
            { count = 8, effects = { critDmg = 20, mp = -30 },          desc = "物理暴击伤害+20%、最大魔法值-30" },
        },
    },
    arcane_cosmos = {
        name   = "宇宙奥秘",
        pieces = {
            "arcane_hat", "arcane_pants", "arcane_robe", "arcane_shoulder",
            "arcane_gloves", "arcane_boots", "arcane_staff", "arcane_dagger",
            "arcane_crystal",
        },
        bonuses = {
            { count = 2, effects = { mp = 150, hp = -50 },              desc = "最大魔法值+150、最大生命值-50" },
            { count = 4, effects = { manaLeech = 5, hp = -50 },         desc = "魔力回收：根据魔法伤害的5%回复魔法值、最大生命值-50" },
            { count = 6, effects = { magicShieldDouble = 1, hp = -50 }, desc = "允许魔法盾抵挡的伤害百分比翻倍、最大生命值-50" },
            { count = 8, effects = { manaPctMagDmg = 0.2, hp = -50 },  desc = "根据当前魔力百分比提高魔法伤害，系数0.2、最大生命值-50" },
        },
    },
    sly_chimera = {
        name   = "狡诈奇美拉",
        pieces = {
            "sly_mask", "sly_pants", "sly_chest", "sly_shoulder",
            "sly_gloves", "sly_boots", "sly_sword", "sly_bow",
            "sly_dagger", "sly_quiver",
        },
        bonuses = {
            { count = 2, effects = { dodge = 10, critVal = -5 },         desc = "闪避值+10、物理暴击值-5" },
            { count = 4, effects = { atkSpeed = 5, critVal = -5 },       desc = "攻击速度+5、物理暴击值-5" },
            { count = 6, effects = { atkSpeed = 10, critVal = -5 },      desc = "攻击速度+10、物理暴击值-5" },
            { count = 8, effects = { hitCountDmgAmp = 3, critVal = -5 }, desc = "根据你和友军在上回合造成的伤害次数（最多10次），以3%的系数增幅本回合所有伤害（最高30%）、物理暴击值-5" },
        },
    },
    goblin_hero = {
        name   = "哥布林英雄",
        pieces = {
            "goblin_hero_helmet", "goblin_hero_shoulder", "goblin_hero_chest",
            "goblin_hero_legs", "goblin_hero_gloves", "goblin_hero_boots",
        },
        bonuses = {
            { count = 2, effects = { atkSpeed = 10 },  desc = "攻击速度+10" },
            { count = 4, effects = { atkSpeed = 15 },  desc = "攻击速度+15" },
            { count = 6, effects = { atkSpeed = 25 },  desc = "攻击速度+25" },
        },
    },
}

--- 计算当前装备中激活的套装加成
---@return table 汇总的套装效果 { hp=100, atk=20, ... }
---@return table 激活的套装信息 { {setId, name, count, activeBonuses={desc...}} }
function M.getSetBonus()
    local bonus = {}
    local activeInfo = {}
    -- 统计每个套装已装备的件数
    local setCounts = {}
    for _, item in pairs(M.equipment) do
        if item then
            local sid = item.setId
            if not sid and item.templateId then
                local tpl = M.itemTemplates[item.templateId]
                if tpl then sid = tpl.setId end
            end
            if sid then
                setCounts[sid] = (setCounts[sid] or 0) + 1
            end
        end
    end
    -- 计算激活的套装加成
    for setId, count in pairs(setCounts) do
        local def = M.SET_DEFS[setId]
        if def then
            local info = { setId = setId, name = def.name, count = count, total = #def.pieces, activeBonuses = {} }
            for _, b in ipairs(def.bonuses) do
                if count >= b.count then
                    for k, v in pairs(b.effects) do
                        bonus[k] = (bonus[k] or 0) + v
                    end
                    table.insert(info.activeBonuses, { count = b.count, desc = b.desc })
                end
            end
            table.insert(activeInfo, info)
        end
    end
    return bonus, activeInfo
end

--- 通用等级→Tier映射：1-10=T0, 11-20=T1, ..., 91-100=T9
---@param level number 等级 1-100
---@return number tier 0-9
function M.getTierByLevel(level)
    return math.min(9, math.max(0, math.floor((level - 1) / 10)))
end

--- 获取装备的有效 T 级（优先 item.tier，fallback 用装备等级推算）
---@param item table
---@return number tier 0-9
function M.getItemTier(item)
    if item.tier then return item.tier end
    if item.level then return M.getTierByLevel(item.level) end
    return 0
end

--- 根据怪物等级从野外基础掉落组随机选一个 templateId
--- 职业专属武器映射：weaponTag/offhandTag → 唯一可掉落的职业
--- 不在此表中的装备（护甲、盾牌等）对所有职业通用掉落
local CLASS_EXCLUSIVE_WEAPON = {
    ["匕首"]  = "assassin",
    ["弓"]    = "hunter",
    ["箭袋"]  = "hunter",
    ["单手剑"] = "warrior",
    ["法杖"]  = "mage",
    ["法器"]  = "mage",
    ["锤"]    = "priest",
}

---@param monsterLevel number
---@return string templateId
---@return number tier 0-9
function M.rollFieldBasicDrop(monsterLevel)
    -- 1-10级→T0, 11-20级→T1, 21-30级→T2, ... 91-100级→T9
    local tier = math.min(9, math.max(0, math.floor((monsterLevel - 1) / 10)))
    local baseList = M.DROP_GROUP_FIELD_BASIC

    -- 按当前职业过滤掉落池：排除其他职业专属武器
    local playerClass = M.currentClass or "warrior"
    local filtered = {}
    for _, id in ipairs(baseList) do
        local tpl = M.itemTemplates[id]
        if tpl then
            local tag = tpl.weaponTag or tpl.offhandTag
            local exclusive = tag and CLASS_EXCLUSIVE_WEAPON[tag]
            if not exclusive or exclusive == playerClass then
                filtered[#filtered + 1] = id
            end
        else
            filtered[#filtered + 1] = id
        end
    end
    if #filtered == 0 then filtered = baseList end  -- 安全回退

    local baseId = filtered[math.random(#filtered)]
    if tier == 0 then
        return baseId, tier
    end
    -- T1+ 从 UNCOMMON_TIERED_IDS 查找
    local tieredIds = M.UNCOMMON_TIERED_IDS and M.UNCOMMON_TIERED_IDS[baseId]
    if tieredIds and tieredIds[tier] then
        return tieredIds[tier], tier
    end
    return baseId, tier  -- fallback
end

--- 物品模板库（数据已提取到 data/ItemTemplates.lua）
M.itemTemplates = require("data.ItemTemplates")
M.STACK_MAX = 99  -- 消耗品最大堆叠数

-- 八维主属性池（用于随机属性装备）
local MAIN_ATTR_POOL = {
    { attr = "str", name = "力量" },
    { attr = "agi", name = "敏捷" },
    { attr = "con", name = "体质" },
    { attr = "wis", name = "智慧" },
    { attr = "foc", name = "专注" },
    { attr = "per", name = "感知" },
    { attr = "wil", name = "意念" },
    { attr = "luk", name = "幸运" },
    { attr = "cha", name = "魅力" },
}

--- 解析含 randomMain/randomSub 的 effects/extraEffects，返回实际属性表和描述片段
---@param tbl table|nil 原始 effects 或 extraEffects
---@param usedAttrs table 已使用的属性集合（避免重复）
---@return table resolved 解析后的属性表
---@return string[] descParts 描述文本片段
local function resolveRandomEffects(tbl, usedAttrs)
    if not tbl then return nil, {} end
    local resolved = {}
    local descParts = {}
    for k, v in pairs(tbl) do
        if k == "randomMain" or k == "randomSub" then
            -- 从未使用的属性中随机选一个
            local candidates = {}
            for _, entry in ipairs(MAIN_ATTR_POOL) do
                if not usedAttrs[entry.attr] then
                    candidates[#candidates + 1] = entry
                end
            end
            if #candidates == 0 then
                -- fallback: 全部可选
                for _, entry in ipairs(MAIN_ATTR_POOL) do
                    candidates[#candidates + 1] = entry
                end
            end
            local picked = candidates[math.random(1, #candidates)]
            usedAttrs[picked.attr] = true
            resolved[picked.attr] = v
            local sign = v >= 0 and "+" or ""
            descParts[#descParts + 1] = picked.name .. sign .. v
        else
            resolved[k] = v
        end
    end
    return resolved, descParts
end

--- 根据模板ID创建物品实例
---@param templateId string
---@param quantity number|nil 堆叠数量（仅消耗品有效）
---@return table|nil
function M.createItem(templateId, quantity)
    local tpl = M.itemTemplates[templateId]
    if not tpl then return nil end
    local stackable = (tpl.consumable ~= nil or tpl.category == "材料" or tpl.stackable) and tpl.slot == nil

    -- 解析随机属性（randomMain / randomSub）
    local effects = tpl.effects
    local extraEffects = tpl.extraEffects
    local desc = tpl.desc
    local hasRandom = (tpl.effects and (tpl.effects.randomMain or tpl.effects.randomSub))
                   or (tpl.extraEffects and (tpl.extraEffects.randomMain or tpl.extraEffects.randomSub))
    if hasRandom then
        local usedAttrs = {}
        effects = resolveRandomEffects(tpl.effects, usedAttrs)
        extraEffects = resolveRandomEffects(tpl.extraEffects, usedAttrs)
        -- desc 保留模板原始描述，解析出的属性已显示为绿色词条，无需在此重复
    end

    return {
        templateId = tpl.id,
        name       = tpl.name,
        category   = tpl.category,
        rarity     = tpl.rarity,
        level      = tpl.level,
        slot       = tpl.slot,
        icon       = tpl.icon,
        effects    = effects,
        extraEffects = extraEffects,
        desc       = desc,
        special    = tpl.special,
        setId      = tpl.setId,
        weaponTag  = tpl.weaponTag,
        offhandTag = tpl.offhandTag,
        consumable = tpl.consumable,
        value      = tpl.value,
        stackable  = stackable,
        quantity   = stackable and math.min(quantity or 1, M.STACK_MAX) or nil,
        enhanceLevel = (tpl.slot and (tpl.rarity == "common" or tpl.rarity == "uncommon" or tpl.maxEnhance)) and 0 or nil,
        hasRandom = hasRandom or nil,
        heroAffix = tpl.heroAffix,
        noShieldPassive = tpl.noShieldPassive,
    }
end

--- 向背包添加物品（支持堆叠）
---@param templateId string 物品模板ID
---@param qty number|nil 数量（默认1）
---@return boolean 是否成功
---@return string 提示消息
function M.addToInventory(templateId, qty)
    qty = qty or 1
    local tpl = M.itemTemplates[templateId]
    if not tpl then return false, "未知物品" end
    local stackable = (tpl.consumable ~= nil or tpl.category == "材料" or tpl.stackable) and tpl.slot == nil
    if stackable then
        -- 先尝试合并到已有堆叠
        for i = 1, M.bagSlots do
            local inv = M.inventory[i]
            if inv and inv.templateId == templateId and inv.stackable then
                local canAdd = M.STACK_MAX - inv.quantity
                if canAdd > 0 then
                    local add = math.min(qty, canAdd)
                    inv.quantity = inv.quantity + add
                    qty = qty - add
                    if qty <= 0 then return true, tpl.name .. " x" .. (qty + add) end
                end
            end
        end
        -- 还有剩余，放新格子
        local anyLost = false
        while qty > 0 do
            local emptySlot = nil
            for i = 1, M.bagSlots do
                if not M.inventory[i] then emptySlot = i; break end
            end
            local add = math.min(qty, M.STACK_MAX)
            if not emptySlot then
                -- 背包满，放入遗失物品
                M.addToLostItems(M.createItem(templateId, add))
                anyLost = true
            else
                M.inventory[emptySlot] = M.createItem(templateId, add)
            end
            qty = qty - add
        end
        if anyLost then
            return true, tpl.name .. " 已放入遗失物品（背包已满）"
        end
        return true, tpl.name .. " 已添加"
    else
        -- 不可堆叠（装备）
        local lastItem = nil
        local anyLost = false
        for _ = 1, qty do
            local emptySlot = nil
            for i = 1, M.bagSlots do
                if not M.inventory[i] then emptySlot = i; break end
            end
            local newItem = M.createItem(templateId)
            lastItem = newItem  -- 无论是否背包满，都保留引用（供调用方赋予特殊属性）
            if not emptySlot then
                -- 背包满，放入遗失物品
                M.addToLostItems(newItem)
                anyLost = true
            else
                M.inventory[emptySlot] = newItem
            end
        end
        if anyLost then
            return true, tpl.name .. " 已放入遗失物品（背包已满）", lastItem
        end
        return true, tpl.name .. " 已添加", lastItem
    end
end

--- 判断当前是否允许切换装备
--- 战斗关卡中仅玩家回合的移动阶段可换装备，非战斗状态（菜单等）不限制
---@return boolean 是否可以切换装备
function M.canChangeEquip()
    -- 非战斗状态：不限制
    if M.gameState == M.STATE_MENU or M.gameState == M.STATE_GAMEOVER then
        return true
    end
    -- 战斗中：仅玩家回合移动阶段允许（含选中单位后尚未移动 / 撤销移动后）
    return (M.gameState == M.STATE_PLAYER or M.gameState == M.STATE_SELECT)
        and M.turnPhase == M.PHASE_MOVE
end

-- 装备槽遍历顺序（用于生效唯一等按序判定）
local EQUIP_SLOT_ITERATE_ORDER = {
    "weapon_r", "weapon_l",
    "hat", "shoulder", "cloak", "chest", "gloves", "pants", "boots",
    "necklace", "belt", "trinket", "ring1", "ring2",
}

--- 装备物品：从背包移到装备栏
---@param slotIdx number 背包格子索引
---@return boolean 是否成功装备
function M.equipItem(slotIdx)
    -- 战斗关卡中仅移动阶段可切换装备
    if not M.canChangeEquip() then return false, "仅移动阶段可切换装备" end
    local item = M.inventory[slotIdx]
    if not item or not item.slot then return false, "无法装备" end
    -- 等级限制
    if item.level and M.player and M.player.level < item.level then
        return false, "等级不足（需要Lv." .. item.level .. "）"
    end
    -- 右手武器栏职业武器类型限制
    if item.slot == "weapon_r" and item.weaponTag then
        local allowed = M.CLASS_WEAPON_R and M.CLASS_WEAPON_R[M.currentClass]
        if allowed and not allowed[item.weaponTag] then
            return false, "当前职业无法装备" .. item.weaponTag
        end
    end
    -- 副手职业限制
    if item.slot == "weapon_l" and item.offhandTag then
        local allowed = M.CLASS_OFFHAND and M.CLASS_OFFHAND[M.currentClass]
        if not allowed or not allowed[item.offhandTag] then
            return false, "当前职业无法装备" .. item.offhandTag
        end
    end
    -- 卓越装备生效唯一：同 templateId 的卓越装备不能重复装备
    if item.rarity == "superior" and item.templateId then
        for _, slotId in ipairs(EQUIP_SLOT_ITERATE_ORDER) do
            local existing = M.equipment[slotId]
            if existing and existing.templateId == item.templateId then
                return false, "同名卓越装备只能装备一件"
            end
        end
    end
    local targetSlot = item.slot
    -- 戒指特殊处理：优先填空槽，都满则替换 ring1
    if targetSlot == "ring1" then
        if not M.equipment["ring1"] then
            targetSlot = "ring1"
        elseif not M.equipment["ring2"] then
            targetSlot = "ring2"
        else
            targetSlot = "ring1"
        end
    end
    -- 匕首双持：装备匕首且 weapon_r 已有匕首时，放入 weapon_l（仅刺客可双持）
    if targetSlot == "weapon_r" and item.weaponTag == "匕首" then
        local existingR = M.equipment["weapon_r"]
        if existingR and existingR.weaponTag == "匕首" then
            if M.currentClass == "assassin" then
                targetSlot = "weapon_l"
            else
                -- 非刺客：替换右手匕首而不是双持
            end
        end
    end
    -- 弓+箭袋限制：装备弓时左手只能装箭袋，装备左手非箭袋时禁止右手有弓
    if targetSlot == "weapon_l" then
        local existingR = M.equipment["weapon_r"]
        if existingR and existingR.weaponTag == "弓" and item.category ~= "箭袋" then
            return false, "装备弓时左手只能装备箭袋"
        end
    end
    -- 如果目标装备栏已有物品，交换回背包
    local oldEquip = M.equipment[targetSlot]
    M.equipment[targetSlot] = item
    M.inventory[slotIdx] = oldEquip  -- nil 或旧装备
    if M.player then M.recalcStats(M.player) end
    -- 武器变更 或 猎犬数量相关装备变更 → 智能更新猎犬（保留血量和位置）
    local houndRelated = targetSlot == "weapon_r"
        or (item.extraEffects and item.extraEffects.houndCountBonus)
        or (oldEquip and oldEquip.extraEffects and oldEquip.extraEffects.houndCountBonus)
    if houndRelated then M.updateHounds() end
    return true
end

--- 卸下装备：从装备栏移回背包
---@param equipSlotId string 装备槽 id
---@return boolean 是否成功卸下
function M.unequipItem(equipSlotId)
    -- 战斗关卡中仅移动阶段可切换装备
    if not M.canChangeEquip() then return false, "仅移动阶段可切换装备" end
    local item = M.equipment[equipSlotId]
    if not item then return false end
    -- 找第一个空背包格子
    for i = 1, M.bagSlots do
        if not M.inventory[i] then
            M.inventory[i] = item
            M.equipment[equipSlotId] = nil
            if M.player then M.recalcStats(M.player) end
            -- 卸下武器 或 猎犬数量相关装备 → 智能更新猎犬（保留血量和位置）
            local houndRelated = equipSlotId == "weapon_r"
                or (item.extraEffects and item.extraEffects.houndCountBonus)
            if houndRelated then M.updateHounds() end
            return true
        end
    end
    return false  -- 背包已满
end

--- 使用消耗品
---@param slotIdx number 背包格子索引
---@return boolean
---@return string
function M.useConsumable(slotIdx)
    local item = M.inventory[slotIdx]
    if not item or not item.consumable then return false, "不是消耗品" end
    if type(item.consumable) ~= "table" then return false, "该物品无法直接饮用" end
    local p = M.player
    if not p then return false, "没有玩家" end
    if p.hp <= 0 then return false, "玩家已阵亡" end
    if M.consumableCooldown > 0 then
        return false, "消耗品冷却中（剩余" .. M.consumableCooldown .. "回合）"
    end
    if item.level and p.level < item.level then
        return false, "等级不足（需要Lv." .. item.level .. "）"
    end
    local c = item.consumable
    if c.stat == "hp" then
        if p.hp >= p.maxHp then return false, "生命值已满" end
        local healAmt = c.amount
        -- 装备效果：药水治疗加成（药水等级低于阈值时额外增加固定治疗量）
        if (p.potionHealBonus or 0) > 0 and (p.potionHealBonusMaxLv or 0) > 0
           and (item.level or 0) < p.potionHealBonusMaxLv then
            healAmt = healAmt + p.potionHealBonus
        end
        p.hp = math.min(p.maxHp, p.hp + healAmt)
    elseif c.stat == "mp" then
        if p.mp >= p.maxMp then return false, "魔法值已满" end
        p.mp = math.min(p.maxMp, p.mp + c.amount)
    elseif c.stat and c.stat:sub(1, 5) == "buff_" then
        -- buff 药水：同一时间只能保持1种药水buff生效（HP/MP药水不受影响）
        M.potionBuffs = {}
        local dur = (c.duration or 6) * 60  -- 转换为 weatherTime 分钟
        M.potionBuffs[c.stat] = {
            amount = c.amount or 0,
            expireTime = M.weatherTime + dur,
            isPercent = c.isPercent or false,
        }
        M.recalcStats(p)
    else
        return false, "未知效果"
    end
    -- 消耗物品（堆叠数量减1，为0时移除）
    if item.stackable and item.quantity and item.quantity > 1 then
        item.quantity = item.quantity - 1
    else
        M.inventory[slotIdx] = nil
    end
    -- 设置公共CD
    M.consumableCooldown = M.CONSUMABLE_CD_TURNS
    return true, item.name .. " 使用成功"
end

--- 使用特殊效果道具（扩充券等）
---@param slotIdx number 背包格子索引
---@return boolean
---@return string
function M.useSpecialItem(slotIdx)
    local item = M.inventory[slotIdx]
    if not item then return false, "空格子" end
    local tpl = M.itemTemplates[item.templateId]
    if not tpl or not tpl.useEffect then return false, "不是可使用的道具" end

    local effect = tpl.useEffect
    if effect == "expand_backpack" then
        M.bagSlots = M.bagSlots + 1
        -- 消耗物品
        if item.stackable and item.quantity and item.quantity > 1 then
            item.quantity = item.quantity - 1
        else
            M.inventory[slotIdx] = nil
        end
        return true, "背包扩充成功！当前上限: " .. M.bagSlots .. " 格"
    elseif effect == "expand_warehouse" then
        M.warehouseSlots = M.warehouseSlots + 1
        -- 消耗物品
        if item.stackable and item.quantity and item.quantity > 1 then
            item.quantity = item.quantity - 1
        else
            M.inventory[slotIdx] = nil
        end
        return true, "所有储物箱扩充成功！当前上限: " .. M.warehouseSlots .. " 格"
    elseif effect == "respec_skills" then
        local p = M.player
        if not p then return false, "没有玩家" end
        -- 重置技能点：所有技能等级归零，退还全部已花费的技能点
        M.skillLevels = {}
        M.skillPoints = p.level  -- 1级起就有1点，每级+1，100级=100点
        M.activeSkills = {}
        M.skillCooldowns = {}
        -- 关闭魔法盾（技能归零后不再拥有）
        M.magicShieldActive = false
        -- 清除猎犬（技能归零后不再拥有）
        for i = #M.companions, 1, -1 do
            if M.companions[i].isHound then
                table.remove(M.companions, i)
            end
        end
        M.homeHound = nil
        -- 消耗物品
        if item.stackable and item.quantity and item.quantity > 1 then
            item.quantity = item.quantity - 1
        else
            M.inventory[slotIdx] = nil
        end
        return true, "技能点已全部重置！"
    elseif effect == "food" then
        -- 食物：单食物覆盖机制，新食物覆盖旧食物增益，持续8小时（480分钟）
        local fe = tpl.foodEffect or {}
        M.foodBuff = {
            foodId = item.templateId,
            name = tpl.name,
            expireTime = M.weatherTime + 480,  -- 8小时 = 480 weatherTime分钟
            hpRegen = fe.hpRegen or 0,
            mpRegen = fe.mpRegen or 0,
            str  = fe.str  or 0,
            foc  = fe.foc  or 0,
            wis  = fe.wis  or 0,
            con  = fe.con  or 0,
            agi  = fe.agi  or 0,
            per  = fe.per  or 0,
            wil  = fe.wil  or 0,
            luk  = fe.luk  or 0,
            physCrit      = fe.physCrit      or 0,
            magicCrit     = fe.magicCrit     or 0,
            fireDmgPct    = fe.fireDmgPct    or 0,
            iceDmgPct     = fe.iceDmgPct     or 0,
            thunderDmgPct = fe.thunderDmgPct or 0,
            holyDmgPct    = fe.holyDmgPct    or 0,
        }
        -- 消耗物品
        if item.stackable and item.quantity and item.quantity > 1 then
            item.quantity = item.quantity - 1
        else
            M.inventory[slotIdx] = nil
        end
        M.recalcStats(M.player)
        return true, tpl.name .. " 食用成功！效果持续8小时"
    elseif effect == "respec_stats" then
        local p = M.player
        if not p then return false, "没有玩家" end
        -- 重置属性点：所有属性回到初始值1，退还全部已花费的属性点
        for k, _ in pairs(p.stats) do
            p.stats[k] = 1
        end
        p.statPoints = p.level * 3  -- 1级初始3点 + 每升一级+3属性点
        M.recalcStats(p)
        if p.hp > p.maxHp then p.hp = p.maxHp end
        if p.mp > p.maxMp then p.mp = p.maxMp end
        -- 消耗物品
        if item.stackable and item.quantity and item.quantity > 1 then
            item.quantity = item.quantity - 1
        else
            M.inventory[slotIdx] = nil
        end
        return true, "属性点已全部重置！"
    elseif effect == "food_harm" then
        -- 有害食物：直接扣除当前HP（不会致死，最低保留1HP）
        local harmHP = tpl.foodHarmHP or 0
        local p = M.player
        if p then
            p.hp = math.max(1, p.hp - harmHP)
        end
        -- 消耗物品
        if item.stackable and item.quantity and item.quantity > 1 then
            item.quantity = item.quantity - 1
        else
            M.inventory[slotIdx] = nil
        end
        return true, tpl.name .. " 食用了...HP-" .. harmHP .. "！"
    elseif effect == "select_box" then
        -- 自选箱：弹出选择面板，不立即消耗（等选择后再消耗）
        local SignInSystem = require("SignInSystem")
        if tpl.selectOptions == "superior_gems" then
            SignInSystem._gemSelectVisible = true
            SignInSystem._gemSelectBoxes = nil
            SignInSystem._pendingGemSlotIdx = slotIdx
            -- 预加载所有宝石图标，避免首帧黑块闪烁
            SignInSystem.preloadGemIcons()
            -- 清除签到来源标记（区分来源）
            SignInSystem._pendingGemDay = nil
            SignInSystem._pendingGemRewardType = nil
            return true, ""  -- 静默成功，等选择后再提示
        elseif tpl.selectOptions == "hero_offhand" then
            SignInSystem._offhandSelectVisible = true
            SignInSystem._offhandSelectBoxes = nil
            SignInSystem._pendingOffhandSlotIdx = slotIdx
            SignInSystem.preloadOffhandIcons()
            return true, ""  -- 静默成功，等选择后再提示
        else
            return false, "未知的自选类型"
        end
    else
        return false, "未知效果"
    end
end

-- 稀有度排序权重（越高越靠后）
local RARITY_ORDER = {
    common = 1, uncommon = 2, rare = 3, fine = 4, superior = 5, epic = 6, legendary = 7, divine = 8,
}

-- 水晶自定义排序权重（红绿黑蓝白黄紫）
local CRYSTAL_ORDER = {
    hongshuijing_cujing   = 1,  -- 红
    lvshuijing_cujing     = 2,  -- 绿
    heishuijing_cujing    = 3,  -- 黑
    lanshuijing_cujing    = 4,  -- 蓝
    baishuijing_cujing    = 5,  -- 白
    huangshuijing_cujing  = 6,  -- 黄
    zijing                = 7,  -- 紫
}

-- 装备槽位排序权重（延迟初始化）
local SLOT_ORDER = nil

-- 装备类别排序权重（同槽位内细分，用 weaponTag 或 category）
local WEAPON_CAT_ORDER = {
    ["单手剑"] = 1, ["锤"] = 2, ["盾牌"] = 3, ["匕首"] = 4,
    ["弓"] = 5, ["箭袋"] = 6, ["法杖"] = 7, ["法器"] = 8, ["水晶球"] = 8,
}

--- 整理背包：按 稀有度(降序) > 槽位 > 类别 > 等级(降序) > 名称 排序
function M.sortInventory()
    -- 首次调用时构建槽位排序表（整理专用顺序，武器优先）
    if not SLOT_ORDER then
        local order = {
            "weapon_r", "weapon_l",
            "hat", "shoulder", "cloak", "chest", "gloves", "pants", "boots",
            "necklace", "belt", "trinket", "ring1", "ring2",
        }
        SLOT_ORDER = {}
        for i, id in ipairs(order) do
            SLOT_ORDER[id] = i
        end
    end
    -- 收集所有非空物品
    local items = {}
    for i = 1, M.bagSlots do
        if M.inventory[i] then
            items[#items + 1] = M.inventory[i]
            M.inventory[i] = nil
        end
    end
    -- 合并同类堆叠物品
    local merged = {}
    for _, item in ipairs(items) do
        if item.stackable then
            local found = false
            for _, m in ipairs(merged) do
                if m.stackable and m.templateId == item.templateId and m.quantity < M.STACK_MAX then
                    local canAdd = M.STACK_MAX - m.quantity
                    local add = math.min(item.quantity or 1, canAdd)
                    m.quantity = m.quantity + add
                    item.quantity = (item.quantity or 1) - add
                    if item.quantity <= 0 then found = true; break end
                end
            end
            if not found then
                merged[#merged + 1] = item
            end
        else
            merged[#merged + 1] = item
        end
    end
    items = merged
    -- 排序
    table.sort(items, function(a, b)
        -- 收藏置顶（starred 优先）
        local fa = a.starred and 1 or 0
        local fb = b.starred and 1 or 0
        if fa ~= fb then return fa > fb end
        -- 分类权重：装备=1, 消耗品=2, 材料=3
        local function catOrder(item)
            if item.slot then return 1 end        -- 装备
            if item.consumable then return 2 end  -- 消耗品
            return 3                              -- 材料
        end
        local ca, cb = catOrder(a), catOrder(b)
        if ca ~= cb then return ca < cb end
        -- 消耗品：稀有度(降序) > 等级(降序) > 名称(升序) > 数量(降序)
        if ca == 2 then
            local ra = RARITY_ORDER[a.rarity or "common"] or 0
            local rb = RARITY_ORDER[b.rarity or "common"] or 0
            if ra ~= rb then return ra > rb end
            local la = a.level or 0
            local lb = b.level or 0
            if la ~= lb then return la > lb end
            local na = a.name or ""
            local nb = b.name or ""
            if na ~= nb then return na < nb end
            local qa = a.quantity or 1
            local qb = b.quantity or 1
            if qa ~= qb then return qa > qb end
            return false
        end
        -- 材料：稀有度(降序) > 等级(降序) > 水晶专属顺序 > 名称(升序) > 数量(降序)
        if ca == 3 then
            local ra = RARITY_ORDER[a.rarity or "common"] or 0
            local rb = RARITY_ORDER[b.rarity or "common"] or 0
            if ra ~= rb then return ra > rb end
            local la = a.level or 0
            local lb = b.level or 0
            if la ~= lb then return la > lb end
            -- 水晶按自定义顺序排列
            local crystA = CRYSTAL_ORDER[a.templateId or ""]
            local crystB = CRYSTAL_ORDER[b.templateId or ""]
            if crystA or crystB then
                return (crystA or 99) < (crystB or 99)
            end
            local na = a.name or ""
            local nb = b.name or ""
            if na ~= nb then return na < nb end
            local qa = a.quantity or 1
            local qb = b.quantity or 1
            if qa ~= qb then return qa > qb end
            return false
        end
        -- 装备：按稀有度(降序) → 槽位 → 类别 → 等级(降序) → 名称
        local ra = RARITY_ORDER[a.rarity or "common"] or 0
        local rb = RARITY_ORDER[b.rarity or "common"] or 0
        if ra ~= rb then return ra > rb end
        local sa = SLOT_ORDER[a.slot or ""] or 99
        local sb = SLOT_ORDER[b.slot or ""] or 99
        if sa ~= sb then return sa < sb end
        local catA = WEAPON_CAT_ORDER[a.weaponTag or a.category or ""] or 99
        local catB = WEAPON_CAT_ORDER[b.weaponTag or b.category or ""] or 99
        if catA ~= catB then return catA < catB end
        local la = a.level or 0
        local lb = b.level or 0
        if la ~= lb then return la > lb end
        return (a.name or "") < (b.name or "")
    end)
    -- 重新放回
    for i, item in ipairs(items) do
        M.inventory[i] = item
    end
end

--- 销毁多选的物品
function M.destroySelectedItems()
    local count = 0
    for idx in pairs(M.invSelected) do
        if M.inventory[idx] and not M.inventory[idx].locked then
            M.inventory[idx] = nil
            count = count + 1
        end
    end
    M.invSelected = {}
    M.invMultiSelect = false
    -- 销毁后自动整理
    if count > 0 then
        M.sortInventory()
    end
    return count
end

--- 关闭悬停面板
function M.closeTooltip()
    M.tooltipItem = nil
    M.tooltipSlotIdx = 0
    M.tooltipSource = "inventory"
    M.tooltipEquipSlotId = nil
    M.tooltipPinned = false
    M.tooltipRect = nil
    M.tooltipEquipBtnRect = nil
    M.tooltipLockBtnRect = nil
    M.tooltipFavBtnRect = nil
    M.tooltipPinnedPos = nil
    M.setDetailBtnRect = nil
    M.setDetailData = nil
    M.setDetailHover = false
    M.setDetailPinned = false
    M.setDetailPanelRect = nil
    M.tooltipScrollY = 0
    M.tooltipNeedScroll = false
    M.tooltipMaxScrollY = 0
    M.tooltipCmpScrollY = 0
    M.tooltipCmpNeedScroll = false
    M.tooltipCmpMaxScrollY = 0
    M.tooltipCmpRect = nil
    M.tooltipTouchStartY = nil
    M.tooltipTouchTarget = nil
end

M.bagSlots = 15             -- 背包格子上限
M.invScrollY = 0            -- 背包滚动偏移（像素）
M.invDragging = false       -- 是否正在拖动背包
M.invDragStartY = 0         -- 拖动起始 Y
M.invDragStartScroll = 0    -- 拖动起始滚动值
M.invClipRect = nil         -- 背包可视区域（用于裁剪和拖动判定）
M.invContentH = 0           -- 背包内容总高度
M.invVisibleH = 0           -- 背包可视区域高度
M.invScrollBarRect = nil    -- 滚动条滑块区域 {x,y,w,h}
M.invScrollBarTrack = nil   -- 滚动条轨道区域 {x,y,w,h}
M.invScrollBarDragging = false  -- 是否正在拖动滚动条
M.invScrollBarDragStartY = 0    -- 拖动起始鼠标Y
M.invScrollBarDragStartScroll = 0 -- 拖动起始滚动值

-- 背包操作按钮
M.invMultiSelect = false    -- 多选模式
M.invSelected = {}          -- 多选选中的格子索引集合 { [idx]=true }
M.invActionBtnRects = {}    -- 按钮屏幕区域 { btn1={x,y,w,h}, btn2={x,y,w,h} }
M.lootFilterVisible = false   -- 拾取过滤面板是否展开
M.lootFilterNoFine = false    -- 不拾取优秀稀有度装备（基础掉落组）
M.lootFilterNoRare = false    -- 不拾取稀有稀有度装备
M.lootFilterNoFineGrade = false -- 不拾取精良稀有度装备
M.lootFilterPanelRect = nil   -- 拾取过滤面板区域（用于点击检测）
M.lootFilterCheckRect = nil   -- 优秀勾选框区域
M.lootFilterCheckRectRare = nil   -- 稀有勾选框区域
M.lootFilterCheckRectFine = nil   -- 精良勾选框区域

-- 堆叠物品拆分
M.splitBtnRect = nil            -- 拆分按钮屏幕区域
M.splitPopupVisible = false     -- 拆分弹窗是否显示
M.splitPopupItem = nil          -- 要拆分的物品引用
M.splitPopupSlotIdx = nil       -- 要拆分的背包格子索引
M.splitPopupTotal = 0           -- 总堆叠数
M.splitPopupValue = 1           -- 滑动条当前值（拆出的数量）
M.splitPopupSliderRect = nil    -- 滑动条轨道区域
M.splitPopupSliderDragging = false -- 是否正在拖动滑动条
M.splitPopupConfirmRect = nil   -- 确认按钮区域
M.splitPopupCancelRect = nil    -- 取消按钮区域

-- ====================================================================
-- 仓库系统（多储物箱独立空间，容量上限共享）
-- ====================================================================
M.WAREHOUSE_COUNT = 4           -- 最大储物箱数量
M.warehouseSlots = 12           -- 仓库格子上限（6列），所有储物箱共享此上限
M.warehouses = { {}, {}, {}, {} } -- 4个独立仓库，indexed 1-12
M.activeWarehouseId = 1         -- 当前打开的仓库编号
M.warehouse = M.warehouses[1]   -- 当前活跃仓库的引用（兼容现有代码）
M.warehouseMode = false         -- 是否处于仓库模式
M.warehouseMultiSelect = false  -- 仓库多选模式
M.warehouseSelected = {}        -- 仓库多选选中 { [idx]=true }
M.warehouseBtnRects = {}        -- 仓库底部按钮区域
M.warehouseScrollY = 0          -- 仓库滚动偏移（像素）
M.warehouseCloseRect = nil      -- 关闭按钮区域
M.warehouseSlotAreas = {}       -- 仓库格子命中区域 { [idx] = {x,y,w,h} }
M.warehouseClipRect = nil       -- 仓库可视裁剪区域
M.warehouseContentH = 0         -- 仓库内容总高度
M.warehouseVisibleH = 0         -- 仓库可视区域高度
M.warehouseScrollBarRect = nil  -- 滚动条滑块区域
M.warehouseScrollBarTrack = nil -- 滚动条轨道区域
M.warehouseScrollBarDragging = false
M.warehouseScrollBarDragStartY = 0
M.warehouseScrollBarDragStartScroll = 0
M.warehouseDragging = false     -- 仓库面板内拖动状态
M.warehouseDragStartY = 0
M.warehouseDragStartScroll = 0
M.warehouseDragMoved = false
M.dragWarehouseIdx = nil        -- 从仓库格子发起拖拽的源索引

-- ====================================================================
-- 共享仓库 UI 状态（数据在 GameState_Shop.lua，存档在 GameState_Save.lua）
-- ====================================================================
M.sharedStorageMode = false         -- 是否处于共享仓库模式
M.sharedStorageSlotAreas = {}       -- 格子命中区域 { [idx] = {x,y,w,h} }
M.sharedStorageCloseRect = nil      -- 关闭按钮区域
M.sharedStorageBtnRects = {}        -- 底部按钮区域
M.dragSharedStorageIdx = nil        -- 从共享仓库格子发起拖拽的源索引

-- ====================================================================
-- 遗失物品系统（背包满时自动暂存，FIFO 先进先出，超出上限丢弃）
-- ====================================================================
M.LOST_ITEMS_MAX = 10           -- 遗失物品格子上限
M.lostItems = {}                -- indexed 1-10，与 inventory 同格式
M.lostItemsMode = false         -- 是否处于遗失物品面板
M.lostItemsScrollY = 0
M.lostItemsSlotAreas = {}
M.lostItemsClipRect = nil
M.lostItemsCloseRect = nil
M.lostItemsBtnRects = {}
M.lostItemsContentH = 0
M.lostItemsVisibleH = 0
M.lostItemsScrollBarRect = nil
M.lostItemsScrollBarTrack = nil
M.lostItemsScrollBarDragging = false
M.lostItemsScrollBarDragStartY = 0
M.lostItemsScrollBarDragStartScroll = 0
M.lostItemsDragging = false
M.lostItemsDragStartY = 0
M.lostItemsDragStartScroll = 0
M.lostItemsDragMoved = false

--- 向遗失物品列表添加物品（FIFO，超出上限则最早的被丢弃）
---@param item table 物品对象（与 inventory 格式相同）
function M.addToLostItems(item)
    if not item then return end
    -- 可堆叠物品先尝试合并（受 STACK_MAX 限制）
    if item.stackable and item.quantity then
        for i = 1, M.LOST_ITEMS_MAX do
            local existing = M.lostItems[i]
            if existing and existing.templateId == item.templateId and existing.stackable then
                local canAdd = M.STACK_MAX - (existing.quantity or 1)
                if canAdd > 0 then
                    local add = math.min(item.quantity or 1, canAdd)
                    existing.quantity = (existing.quantity or 1) + add
                    item.quantity = (item.quantity or 1) - add
                    if item.quantity <= 0 then return end
                end
            end
        end
    end
    -- 找空格子
    for i = 1, M.LOST_ITEMS_MAX do
        if not M.lostItems[i] then
            M.lostItems[i] = item
            return
        end
    end
    -- 满了，先进先出：移除第1个，后面前移，新物品放最后
    for i = 1, M.LOST_ITEMS_MAX - 1 do
        M.lostItems[i] = M.lostItems[i + 1]
    end
    M.lostItems[M.LOST_ITEMS_MAX] = item
end

--- 获取遗失物品数量
---@return number
function M.getLostItemCount()
    local count = 0
    for i = 1, M.LOST_ITEMS_MAX do
        if M.lostItems[i] then count = count + 1 end
    end
    return count
end

--- 从遗失物品取出到背包
---@param lostIdx number 遗失物品格子索引
---@return boolean
---@return string
function M.withdrawFromLostItems(lostIdx)
    local item = M.lostItems[lostIdx]
    if not item then return false, "空格子" end
    -- 可堆叠物品先尝试合并已有堆叠（受 STACK_MAX 限制）
    if item.stackable and item.quantity then
        for i = 1, M.bagSlots do
            local inv = M.inventory[i]
            if inv and inv.templateId == item.templateId and inv.stackable then
                local canAdd = M.STACK_MAX - (inv.quantity or 1)
                if canAdd > 0 then
                    local add = math.min(item.quantity or 1, canAdd)
                    inv.quantity = (inv.quantity or 1) + add
                    item.quantity = (item.quantity or 1) - add
                    if item.quantity <= 0 then
                        M.lostItems[lostIdx] = nil
                        return true, "已取回物品"
                    end
                end
            end
        end
    end
    -- 找背包空位（若堆叠合并后仍有剩余，或不可堆叠物品）
    local emptySlot = nil
    for i = 1, M.bagSlots do
        if not M.inventory[i] then emptySlot = i; break end
    end
    if not emptySlot then
        -- 部分合并了但剩余放不下，保留遗失物品中的剩余数量
        if item.stackable and item.quantity and item.quantity > 0 then
            return false, "背包已满（部分已合并）"
        end
        return false, "背包已满"
    end
    M.inventory[emptySlot] = item
    M.lostItems[lostIdx] = nil
    return true, "已取回物品"
end

--- 整理遗失物品（消除空隙）
function M.compactLostItems()
    local compacted = {}
    for i = 1, M.LOST_ITEMS_MAX do
        if M.lostItems[i] then
            compacted[#compacted + 1] = M.lostItems[i]
        end
    end
    M.lostItems = {}
    for i = 1, #compacted do
        M.lostItems[i] = compacted[i]
    end
end

--- 全部取回遗失物品
---@return number count 成功取回数量
---@return number failCount 失败数量（背包满）
function M.withdrawAllLostItems()
    local count = 0
    local failCount = 0
    for i = 1, M.LOST_ITEMS_MAX do
        if M.lostItems[i] then
            local ok, _ = M.withdrawFromLostItems(i)
            if ok then
                count = count + 1
            else
                failCount = failCount + 1
            end
        end
    end
    M.compactLostItems()
    return count, failCount
end

--- 进入遗失物品面板
function M.enterLostItemsMode()
    M.lostItemsMode = true
    M.lostItemsScrollY = 0
    M.lostItemsSlotAreas = {}
    M.lostItemsClipRect = nil
    M.lostItemsCloseRect = nil
    M.lostItemsBtnRects = {}
end

--- 退出遗失物品面板
function M.exitLostItemsMode()
    M.lostItemsMode = false
end

-- 启动家具交互进度条（实时，无失败）
-- action: 进度条完成后执行的回调函数
-- furnW/furnH: 家具宽高（格数），用于进度条居中显示，默认1
function M.startFurnitureInteract(targetX, targetY, name, action, duration, furnW, furnH)
    M.furnitureInteract = {
        targetX = targetX,
        targetY = targetY,
        furnW = furnW or 1,
        furnH = furnH or 1,
        name = name or "交互",
        progress = 0,
        duration = duration or 1.2,
        action = action,
        _displayProgress = 0,
    }
end

function M.enterWarehouseMode(warehouseId)
    warehouseId = warehouseId or 1
    M.activeWarehouseId = warehouseId
    M.warehouse = M.warehouses[warehouseId]
    M.warehouseMode = true
    M.warehouseScrollY = 0
    M.warehouseSlotAreas = {}
    M.warehouseClipRect = nil
    M.warehouseCloseRect = nil
    M.warehouseMultiSelect = false
    M.warehouseSelected = {}
    M.warehouseBtnRects = {}
    M.closeTooltip()
end

function M.exitWarehouseMode()
    M.warehouseMode = false
    M.warehouseScrollY = 0
    M.warehouseSlotAreas = {}
    M.warehouseClipRect = nil
    M.warehouseCloseRect = nil
    M.warehouseScrollBarRect = nil
    M.warehouseScrollBarTrack = nil
    M.warehouseScrollBarDragging = false
    M.warehouseDragging = false
    M.dragWarehouseIdx = nil
    M.warehouseMultiSelect = false
    M.warehouseSelected = {}
    M.warehouseBtnRects = {}
    M.closeTooltip()
    -- 退出时触发自动保存，防止仓库变更丢失
    if M.autoSave and M.autoSave.enabled then
        M.autoSave.dirty = true
    end
end

-- ====================================================================
-- 共享仓库进入/退出
-- ====================================================================
function M.enterSharedStorageMode()
    if not M.sharedStorageUnlocked then
        return
    end
    M.sharedStorageMode = true
    M.sharedStorageSlotAreas = {}
    M.sharedStorageCloseRect = nil
    M.sharedStorageBtnRects = {}
    M.dragSharedStorageIdx = nil
    M.closeTooltip()
end

function M.exitSharedStorageMode()
    M.sharedStorageMode = false
    M.sharedStorageSlotAreas = {}
    M.sharedStorageCloseRect = nil
    M.sharedStoragePanelRect = nil
    M.sharedStorageBtnRects = {}
    M.dragSharedStorageIdx = nil
    -- 重置日志面板状态
    M.sharedStorageLogOpen = false
    M.sharedStorageLogLines = nil
    M.sharedStorageLogScroll = 0
    M.sharedStorageLogCloseRect = nil
    M.sharedStorageLogPanelRect = nil
    M.sharedStorageLogScrollUpRect = nil
    M.sharedStorageLogScrollDownRect = nil
    M.sharedStorageLogDragging = false
    M.sharedStorageLogDragStartY = 0
    M.sharedStorageLogDragStartScroll = 0
    M.sharedStorageLogRowH = 20
    M.sharedStorageLogVisibleRows = 10
    M.closeTooltip()
    -- 退出时自动保存
    if M.autoSave and M.autoSave.dirty then
        M.saveToCloud()
    end
end

--- 仓库整理（与背包整理逻辑一致：按槽位+稀有度+等级排序，压到前面）
function M.sortWarehouse()
    -- reuse module-level RARITY_ORDER
    local items = {}
    for i = 1, M.warehouseSlots do
        if M.warehouse[i] then
            items[#items + 1] = M.warehouse[i]
            M.warehouse[i] = nil
        end
    end
    -- 合并同类堆叠物品
    local merged = {}
    for _, item in ipairs(items) do
        if item.stackable then
            local found = false
            for _, m in ipairs(merged) do
                if m.stackable and m.templateId == item.templateId and m.quantity < M.STACK_MAX then
                    local canAdd = M.STACK_MAX - m.quantity
                    local add = math.min(item.quantity or 1, canAdd)
                    m.quantity = m.quantity + add
                    item.quantity = (item.quantity or 1) - add
                    if item.quantity <= 0 then found = true; break end
                end
            end
            if not found then
                merged[#merged + 1] = item
            end
        else
            merged[#merged + 1] = item
        end
    end
    items = merged
    table.sort(items, function(a, b)
        local ra = RARITY_ORDER[a.rarity or "common"] or 0
        local rb = RARITY_ORDER[b.rarity or "common"] or 0
        if ra ~= rb then return ra > rb end
        local la = a.level or 0
        local lb = b.level or 0
        if la ~= lb then return la > lb end
        -- 水晶按自定义顺序排列
        local crystA = CRYSTAL_ORDER[a.templateId or ""]
        local crystB = CRYSTAL_ORDER[b.templateId or ""]
        if crystA or crystB then
            return (crystA or 99) < (crystB or 99)
        end
        return (a.name or "") < (b.name or "")
    end)
    for i, item in ipairs(items) do
        M.warehouse[i] = item
    end
end

--- 将背包物品存入仓库（可堆叠物品优先合并，再找空位）
---@param bagIdx number 背包格子索引
---@return boolean 是否成功（含部分合并成功）
function M.storeToWarehouse(bagIdx)
    local item = M.inventory[bagIdx]
    if not item then return false end

    -- 可堆叠物品：先尝试合并到仓库已有同类
    if item.stackable and item.quantity then
        local origQty = item.quantity
        for i = 1, M.warehouseSlots do
            local wh = M.warehouse[i]
            if wh and wh.stackable and wh.templateId == item.templateId then
                local canAdd = M.STACK_MAX - wh.quantity
                if canAdd >= item.quantity then
                    -- 全部合入
                    wh.quantity = wh.quantity + item.quantity
                    M.inventory[bagIdx] = nil
                    return true
                elseif canAdd > 0 then
                    -- 部分合入，剩余继续找下一个位置
                    wh.quantity = M.STACK_MAX
                    item.quantity = item.quantity - canAdd
                end
            end
        end
        -- 如果发生了部分合入但没有空位，剩余留在背包，仍视为成功
        if item.quantity < origQty then
            -- 找空位放剩余
            for i = 1, M.warehouseSlots do
                if not M.warehouse[i] then
                    M.warehouse[i] = item
                    M.inventory[bagIdx] = nil
                    return true
                end
            end
            -- 没有空位，部分已合入，剩余留背包
            return true
        end
    end

    -- 不可堆叠或仓库无同类：找第一个空位
    for i = 1, M.warehouseSlots do
        if not M.warehouse[i] then
            M.warehouse[i] = item
            M.inventory[bagIdx] = nil
            return true
        end
    end
    return false  -- 仓库已满
end

--- 批量存入仓库（多选模式）
---@param selectedMap table { [bagIdx]=true }
---@return number 成功存入数量
function M.batchStoreToWarehouse(selectedMap)
    local count = 0
    local indices = {}
    for idx in pairs(selectedMap) do indices[#indices + 1] = idx end
    table.sort(indices)
    for _, idx in ipairs(indices) do
        if M.storeToWarehouse(idx) then
            count = count + 1
        end
    end
    return count
end

--- 从仓库取出到背包（找第一个空位）
---@param whIdx number 仓库格子索引
---@return boolean 是否成功
function M.withdrawFromWarehouse(whIdx)
    local item = M.warehouse[whIdx]
    if not item then return false end
    for i = 1, M.bagSlots do
        if not M.inventory[i] then
            M.inventory[i] = item
            M.warehouse[whIdx] = nil
            return true
        end
    end
    return false  -- 背包已满
end

--- 批量从仓库取出（多选模式）
---@param selectedMap table { [whIdx]=true }
---@return number 成功取出数量
function M.batchWithdrawFromWarehouse(selectedMap)
    local count = 0
    local indices = {}
    for idx in pairs(selectedMap) do indices[#indices + 1] = idx end
    table.sort(indices)
    for _, idx in ipairs(indices) do
        if M.withdrawFromWarehouse(idx) then
            count = count + 1
        end
    end
    return count
end
M.RARITY_ENHANCE_BONUS = {
    common   = 0,
    uncommon = 1,
    rare     = 2,
    fine     = 3,
    superior = 4,
    epic      = 5,
    legendary = 6,
    divine    = 7,
}

function M.getMaxEnhance(item)
    if not item then return 0 end
    local tpl = M.itemTemplates[item.templateId]
    if not tpl then return 0 end
    if not tpl.slot then return 0 end
    -- 自定义最大强化等级（优先使用）
    if tpl.maxEnhance then return tpl.maxEnhance end
    local tier = M.getTierByLevel(tpl.level or 1)
    local rarityBonus = M.RARITY_ENHANCE_BONUS[tpl.rarity] or 0
    return tier + 1 + rarityBonus
end

--- 获取装备的基础属性（用于强化加成计算）
--- block_chance 不参与强化（格挡几率固定不变）
--- 优先使用物品实例的 effects（随机属性已解析），fallback 到模板
function M.getBaseEffects(item)
    if not item then return {} end
    local eff = item.effects
    if not eff then
        local tpl = M.itemTemplates[item.templateId]
        if not tpl or not tpl.effects then return {} end
        eff = tpl.effects
    end
    local base = {}
    for k, v in pairs(eff) do
        if k ~= "block_chance" then
            base[k] = v
        end
    end
    return base
end

--- 强化倍率表（强化等级 → 基础属性乘数）
M.ENHANCE_MULTIPLIERS = {
    1.05, 1.10, 1.15, 1.20, 1.27,
    1.34, 1.42, 1.50, 1.60, 1.70,
    1.85, 2.00, 2.20, 2.50, 3.00,
    3.70,
    5.00,
}

--- 计算指定强化等级下的总属性加成（基于倍率表）
--- 每项属性保底至少 +1
---@param item table
---@param enhLv number|nil  强化等级，默认取 item.enhanceLevel
---@return table  { atk = N, def = N, ... } 总加成值
function M.getEnhanceGain(item, enhLv)
    if not item then return {} end
    enhLv = enhLv or (item.enhanceLevel or 0)
    if enhLv <= 0 then return {} end
    local base = M.getBaseEffects(item)
    local mult = M.ENHANCE_MULTIPLIERS[enhLv] or (1 + enhLv * 0.05)
    -- 模板可指定 enhanceGain 覆盖特定属性的每级增量
    local tpl = item.templateId and M.itemTemplates[item.templateId]
    local overrides = tpl and tpl.enhanceGain
    local gain = {}
    for k, v in pairs(base) do
        if overrides and overrides[k] then
            -- 使用模板指定的每级增量（如 hpDrain = -1 表示每级减少1）
            gain[k] = overrides[k] * enhLv
        else
            local bonus = math.floor(v * mult + 0.5) - v
            gain[k] = math.max(enhLv, bonus)
        end
    end
    return gain
end

--- 强化等级 → 稀有度映射（返回稀有度 key 和颜色）
function M.getEnhanceRarity(enhLv)
    local r
    if enhLv <= 4 then r = "common"
    elseif enhLv <= 7 then r = "uncommon"
    elseif enhLv <= 10 then r = "rare"
    elseif enhLv <= 12 then r = "fine"
    elseif enhLv <= 14 then r = "superior"
    elseif enhLv == 15 then r = "epic"
    elseif enhLv == 16 then r = "legendary"
    else r = "divine"
    end
    local def = M.RARITY[r]
    return r, def and def.color or {200, 200, 200}
end

--- 强化费用倍率表：从 +N-1 升到 +N 时，消耗 value × 倍率[N] 的金币
local ENHANCE_COST_MULTIPLIER = {
    [1]  = 1.00,
    [2]  = 1.20,
    [3]  = 1.48,
    [4]  = 1.87,
    [5]  = 2.44,
    [6]  = 3.24,
    [7]  = 4.44,
    [8]  = 6.22,
    [9]  = 8.89,
    [10] = 13.07,
    [11] = 19.60,
    [12] = 29.99,
    [13] = 47.08,
    [14] = 75.33,
    [15] = 128.07,
}

--- 计算强化总费用（燃料费 + 加工费）
--- 燃料费 = baseValue × 倍率，加工费 = 铁匠铺费率表
function M.getEnhanceCost(item)
    if not item then return 0 end
    local enhLv = item.enhanceLevel or 0
    local targetLv = enhLv + 1
    local mul = ENHANCE_COST_MULTIPLIER[targetLv]
    if not mul then return 0 end  -- 超出强化上限
    local tpl = M.itemTemplates[item.templateId]
    local baseValue = tpl and tpl.value or item.value or 0
    local fuelCost = math.floor(baseValue * mul)
    local processingFee = M.getProcessingFee(item)
    return fuelCost + processingFee
end

--- 获取强化费用明细（燃料费 + 加工费分开）
---@param item table 装备物品实例
---@return number fuelCost 燃料费
---@return number processingFee 加工费
function M.getEnhanceCostBreakdown(item)
    if not item then return 0, 0 end
    local enhLv = item.enhanceLevel or 0
    local targetLv = enhLv + 1
    local mul = ENHANCE_COST_MULTIPLIER[targetLv]
    if not mul then return 0, 0 end
    local tpl = M.itemTemplates[item.templateId]
    local baseValue = tpl and tpl.value or item.value or 0
    local fuelCost = math.floor(baseValue * mul)
    if isAbyssEquip(item) then fuelCost = fuelCost * 2 end
    local processingFee = M.getProcessingFee(item)
    return fuelCost, processingFee
end

--- 计算装备从 +0 到当前强化等级的累计投资（燃料费 + 耗材价值）
--- 纯查表计算，不需要存储历史记录
---@param item table 装备物品实例
---@return number totalInvestment 累计投资额
function M.calcEnhanceTotalInvestment(item)
    if not item then return 0 end
    local enhLv = item.enhanceLevel or 0
    if enhLv <= 0 then return 0 end
    local tpl = M.itemTemplates[item.templateId]
    local baseValue = tpl and tpl.value or 0
    local total = 0
    for lv = 1, enhLv do
        -- 燃料费
        local mul = ENHANCE_COST_MULTIPLIER[lv]
        if mul then
            total = total + math.floor(baseValue * mul)
        end
        -- 耗材价值
        local cfg = M.ENHANCE_LEVEL_CONFIG[lv]
        if cfg and cfg.materialId then
            local matTpl = M.itemTemplates[cfg.materialId]
            total = total + (matTpl and matTpl.value or 0) * (cfg.materialQty or 0)
        end
    end
    return total
end

-- ====================================================================
-- 强化等级配置表：材料需求 + 成功概率
-- materialId: 所需金属锭模板ID（nil = 无需材料）
-- materialQty: 所需数量
-- rate: 成功概率 (1.0 = 100%)
-- ====================================================================
M.ENHANCE_LEVEL_CONFIG = {
    [1]  = { materialId = nil,                  materialQty = 0, rate = 1.00 },
    [2]  = { materialId = nil,                  materialQty = 0, rate = 1.00 },
    [3]  = { materialId = "iron_ingot",         materialQty = 1, rate = 1.00 },
    [4]  = { materialId = "iron_ingot",         materialQty = 3, rate = 1.00 },
    [5]  = { materialId = "iron_ingot",         materialQty = 5, rate = 1.00 },
    [6]  = { materialId = "copper_ingot",       materialQty = 3, rate = 1.00 },
    [7]  = { materialId = "copper_ingot",       materialQty = 5, rate = 0.85 },
    [8]  = { materialId = "silver_ingot",       materialQty = 5, rate = 0.67 },
    [9]  = { materialId = "gold_ingot",         materialQty = 5, rate = 0.55 },
    [10] = { materialId = "blue_silver_ingot",  materialQty = 5, rate = 0.45 },
    [11] = { materialId = "radiant_gold_ingot", materialQty = 5, rate = 0.37 },
    [12] = { materialId = "black_steel_ingot",  materialQty = 5, rate = 0.30 },
    [13] = { materialId = "mithril_ingot",      materialQty = 5, rate = 0.25 },
    [14] = { materialId = "true_silver_ingot",  materialQty = 5, rate = 0.20 },
    [15] = { materialId = "true_gold_ingot",    materialQty = 5, rate = 0.15 },
}

--- 获取指定强化等级的配置（目标等级 = 当前等级+1）
---@param targetLv number 目标强化等级
---@return table|nil config {materialId, materialQty, rate}
function M.getEnhanceLevelConfig(targetLv)
    return M.ENHANCE_LEVEL_CONFIG[targetLv]
end

--- 获取强化所需材料信息（返回 materialId, materialQty, 背包持有数量）
---@return string|nil materialId
---@return number materialQty 所需数量
---@return number ownedQty 持有数量
function M.getEnhanceMaterialInfo(item)
    if not item then return nil, 0, 0 end
    local enhLv = item.enhanceLevel or 0
    local cfg = M.getEnhanceLevelConfig(enhLv + 1)
    if not cfg or not cfg.materialId then return nil, 0, 0 end
    local owned = M.countInventoryItem(cfg.materialId)
    return cfg.materialId, cfg.materialQty, owned
end

--- 获取强化成功率
function M.getEnhanceSuccessRate(item)
    if not item then return 1.0 end
    local enhLv = item.enhanceLevel or 0
    local cfg = M.getEnhanceLevelConfig(enhLv + 1)
    if not cfg then return 1.0 end
    return cfg.rate
end

--- 统计背包中某模板物品的总数量
---@param templateId string
---@return number
function M.countInventoryItem(templateId)
    local total = 0
    for i = 1, M.bagSlots do
        local it = M.inventory[i]
        if it and it.templateId == templateId then
            total = total + (it.quantity or 1)
        end
    end
    return total
end

--- 从背包中扣除指定模板物品若干个（堆叠物品优先扣减数量）
---@param templateId string
---@param qty number
---@return boolean success
function M.removeInventoryItem(templateId, qty)
    if qty <= 0 then return true end
    if M.countInventoryItem(templateId) < qty then return false end
    local remaining = qty
    for i = 1, M.bagSlots do
        if remaining <= 0 then break end
        local it = M.inventory[i]
        if it and it.templateId == templateId then
            local has = it.quantity or 1
            if has <= remaining then
                remaining = remaining - has
                M.inventory[i] = nil
            else
                it.quantity = has - remaining
                remaining = 0
            end
        end
    end
    return true
end

--- 执行强化（使用强化槽中的物品）
---@return boolean success
---@return string message
function M.enhanceItem()
    local item = M.enhanceSlotItem
    if not item then return false, "未放入物品" end

    local maxLv = M.getMaxEnhance(item)
    if maxLv <= 0 then return false, "该装备无法强化" end

    local enhLv = item.enhanceLevel or 0
    if enhLv >= maxLv then return false, "已达最大强化等级" end

    -- 脆化装备无法强化
    if item.brittle then
        return false, "装备已脆化，需先修复"
    end

    local cost = M.getEnhanceCost(item)
    if M.gold < cost then return false, "金币不足（需要 " .. cost .. "G）" end

    -- 检查材料需求
    local matId, matQty, matOwned = M.getEnhanceMaterialInfo(item)
    if matId and matOwned < matQty then
        local matTpl = M.itemTemplates[matId]
        local matName = matTpl and matTpl.name or matId
        return false, matName .. "不足（需要" .. matQty .. "个，持有" .. matOwned .. "个）"
    end

    -- 扣除金币和材料（失败也不返还）
    M.gold = M.gold - cost
    if matId and matQty > 0 then
        M.removeInventoryItem(matId, matQty)
    end

    local rate = M.getEnhanceSuccessRate(item)
    -- 催化剂加成
    if M.enhanceUseCatalyst then
        local catCount = M.countInventoryItem("divine_catalyst")
        if catCount >= 1 then
            M.removeInventoryItem("divine_catalyst", 1)
            rate = math.min(1.0, rate + 0.05)
        end
        M.enhanceUseCatalyst = false  -- 每次强化后重置勾选
    end
    if math.random() <= rate then
        item.enhanceLevel = enhLv + 1
        -- 更新物品显示名称
        local tpl = M.itemTemplates[item.templateId]
        item.name = (tpl and tpl.name or item.name) .. " +" .. item.enhanceLevel
        -- 更新价值：基础价值 + 累计投资（查表计算）
        local baseValue = tpl and tpl.value or 0
        item.value = baseValue + M.calcEnhanceTotalInvestment(item)
        -- 重算属性
        M.recalcStats(M.player)
        return true, "强化成功！+" .. item.enhanceLevel
    else
        -- 强化失败：33%无事 / 33%脆化 / 33%降级+脆化
        local fate = math.random(1, 3)
        if fate == 1 then
            return false, "强化失败！金币和材料已消耗"
        elseif fate == 2 then
            item.brittle = true
            return false, "强化失败！装备已脆化"
        else
            -- 降级 + 脆化
            if enhLv > 0 then
                item.enhanceLevel = enhLv - 1
                local tpl = M.itemTemplates[item.templateId]
                if item.enhanceLevel > 0 then
                    item.name = (tpl and tpl.name or item.name) .. " +" .. item.enhanceLevel
                else
                    item.name = tpl and tpl.name or item.name
                end
                -- 回退价值：基础价值 + 降级后的累计投资（查表计算）
                local baseValue = tpl and tpl.value or 0
                item.value = baseValue + M.calcEnhanceTotalInvestment(item)
                M.recalcStats(M.player)
            end
            item.brittle = true
            if enhLv > 0 then
                return false, "强化失败！等级-1 且装备已脆化"
            else
                return false, "强化失败！装备已脆化"
            end
        end
    end
end

--- 修复脆化装备（需要金币 + 神炼修复剂）
---@return boolean success
---@return string message
function M.repairItem()
    local item = M.repairSlotItem
    if not item then return false, "未放入物品" end
    if not item.brittle then return false, "该装备未脆化" end

    local cost = M.getRepairCost(item)
    if M.gold < cost then return false, "金币不足（需要 " .. cost .. "G）" end

    local agentCount = M.countInventoryItem("divine_repair_agent")
    if agentCount < 1 then return false, "需要1瓶神炼修复剂" end

    M.gold = M.gold - cost
    M.removeInventoryItem("divine_repair_agent", 1)
    item.brittle = nil
    return true, "修复成功！（消耗1瓶神炼修复剂）"
end

-- ====================================================================
-- 萃取系统（强化等级转移）
-- ====================================================================

--- 计算指定物品从 +0 强化到指定等级的累计燃料费（不含耗材）
---@param item table 装备物品实例
---@param enhLv number 目标强化等级
---@return number totalFuel 累计燃料费
local function calcEnhanceFuelToLevel(item, enhLv)
    if not item or enhLv <= 0 then return 0 end
    local tpl = M.itemTemplates[item.templateId]
    local baseValue = tpl and tpl.value or item.value or 0
    local total = 0
    for lv = 1, enhLv do
        local mul = ENHANCE_COST_MULTIPLIER[lv]
        if mul then
            total = total + math.floor(baseValue * mul)
        end
    end
    return total
end

--- 获取萃取费用明细
--- 差额 = 目标装备从当前等级强化到源等级的费用 - 源装备同区间的费用，最低为0
--- 燃料费/加工费 = 目标装备精炼一次的费率
---@param sourceItem table 源装备（有较高强化等级）
---@param targetItem table 目标装备（强化等级低于源装备）
---@return number goldDiff 强化费用差额
---@return number fuelCost 燃料费（参考目标装备精炼费率）
---@return number processingFee 加工费
function M.getExtractCostBreakdown(sourceItem, targetItem)
    if not sourceItem or not targetItem then return 0, 0, 0 end
    local srcEnhLv = sourceItem.enhanceLevel or 0
    local tgtEnhLv = targetItem.enhanceLevel or 0
    if srcEnhLv <= 0 or srcEnhLv <= tgtEnhLv then return 0, 0, 0 end
    -- 只计算从 tgtEnhLv 到 srcEnhLv 这段区间的费用差
    local srcFuelFull = calcEnhanceFuelToLevel(sourceItem, srcEnhLv)
    local srcFuelBase = calcEnhanceFuelToLevel(sourceItem, tgtEnhLv)
    local tgtFuelFull = calcEnhanceFuelToLevel(targetItem, srcEnhLv)
    local tgtFuelBase = calcEnhanceFuelToLevel(targetItem, tgtEnhLv)
    local goldDiff = math.max(0, (tgtFuelFull - tgtFuelBase) - (srcFuelFull - srcFuelBase))
    local fuelCost = lookupSmithingFee(targetItem)
    if isAbyssEquip(targetItem) then fuelCost = fuelCost * 2 end
    local processingFee = M.getProcessingFee(targetItem)
    return goldDiff, fuelCost, processingFee
end

--- 获取萃取总费用
---@param sourceItem table 源装备
---@param targetItem table 目标装备
---@return number totalCost 总费用（金币）
function M.getExtractCost(sourceItem, targetItem)
    local d, f, p = M.getExtractCostBreakdown(sourceItem, targetItem)
    return d + f + p
end

--- 根据源装备强化等级计算萃取剂消耗数量
---@param enhLv number 源装备强化等级
---@return number count 需要消耗的萃取剂数量
function M.getExtractAgentCost(enhLv)
    if enhLv <= 7 then return 1 end
    if enhLv <= 9 then return 2 end
    if enhLv <= 11 then return 3 end
    if enhLv <= 13 then return 4 end
    if enhLv == 14 then return 5 end
    return 7  -- +15
end

--- 检查是否可以萃取（返回 canDo, reason）
---@param sourceItem table 源装备（低等级，有强化）
---@param targetItem table 目标装备（高等级，+0）
---@return boolean canDo
---@return string reason 不可萃取的原因
function M.canExtract(sourceItem, targetItem)
    if not sourceItem then return false, "请放入源装备（提供强化等级）" end
    if not targetItem then return false, "请放入目标装备（接收强化等级）" end
    local srcTpl = M.itemTemplates[sourceItem.templateId]
    local tgtTpl = M.itemTemplates[targetItem.templateId]
    if not srcTpl or not srcTpl.slot then return false, "源物品不是装备" end
    if not tgtTpl or not tgtTpl.slot then return false, "目标物品不是装备" end
    local srcEnhLv = sourceItem.enhanceLevel or 0
    if srcEnhLv <= 0 then return false, "源装备未强化" end
    local tgtEnhLv = targetItem.enhanceLevel or 0
    if tgtEnhLv >= srcEnhLv then return false, "目标强化等级不低于源装备" end
    local srcLevel = srcTpl.level or 1
    local tgtLevel = tgtTpl.level or 1
    if tgtLevel < srcLevel then return false, "目标装备等级不能低于源装备" end
    if sourceItem.brittle then return false, "源装备已脆化，请先修复" end
    if targetItem.brittle then return false, "目标装备已脆化，请先修复" end
    local maxEnh = M.getMaxEnhance(targetItem)
    if srcEnhLv > maxEnh then return false, "源强化等级超过目标上限(+" .. maxEnh .. ")" end
    local agentNeed = M.getExtractAgentCost(srcEnhLv)
    local agentCount = M.countInventoryItem("divine_extract_agent")
    if agentCount < agentNeed then return false, "需要" .. agentNeed .. "瓶神炼萃取剂（当前" .. agentCount .. "瓶）" end
    local totalCost = M.getExtractCost(sourceItem, targetItem)
    if M.gold < totalCost then return false, "金币不足（需要 " .. totalCost .. "G）" end
    return true, ""
end

--- 执行萃取（转移强化等级）
---@param sourceItem table 源装备
---@param targetItem table 目标装备
---@return boolean success
---@return string msg
function M.extractEnhancement(sourceItem, targetItem)
    local canDo, reason = M.canExtract(sourceItem, targetItem)
    if not canDo then return false, reason end
    local srcEnhLv = sourceItem.enhanceLevel or 0
    local tgtEnhLv = targetItem.enhanceLevel or 0
    local totalCost = M.getExtractCost(sourceItem, targetItem)
    -- 扣除费用和材料
    M.gold = M.gold - totalCost
    local agentNeed = M.getExtractAgentCost(srcEnhLv)
    M.removeInventoryItem("divine_extract_agent", agentNeed)
    -- 转移强化等级：源装备归零，目标获得源等级
    targetItem.enhanceLevel = srcEnhLv
    sourceItem.enhanceLevel = 0
    -- 更新物品名称和价值
    local srcTpl = M.itemTemplates[sourceItem.templateId]
    local tgtTpl = M.itemTemplates[targetItem.templateId]
    local srcBaseName = srcTpl and srcTpl.name or sourceItem.name:gsub(" %+%d+$", "")
    local tgtBaseName = tgtTpl and tgtTpl.name or targetItem.name:gsub(" %+%d+$", "")
    -- 源装备归零
    sourceItem.name = srcBaseName
    local srcBaseVal = srcTpl and srcTpl.value or 0
    sourceItem.value = srcBaseVal
    -- 目标装备获得源强化等级
    targetItem.name = tgtBaseName .. " +" .. srcEnhLv
    local tgtBaseVal = tgtTpl and tgtTpl.value or 0
    targetItem.value = tgtBaseVal + M.calcEnhanceTotalInvestment(targetItem)
    -- 重算玩家属性
    M.recalcStats(M.player)
    return true, "萃取成功！+" .. srcEnhLv .. " 已转移"
end

-- ====================================================================
-- 属性计算
-- ====================================================================

--- 判断玩家是否双持匕首
---@return boolean
function M.isDualDagger()
    local r = M.equipment["weapon_r"]
    local l = M.equipment["weapon_l"]
    return r ~= nil and l ~= nil and r.weaponTag == "匕首" and l.weaponTag == "匕首"
end

--- 判断玩家是否剑匕双持（右手单手剑+左手匕首）
---@return boolean
function M.isSwordDagger()
    local r = M.equipment["weapon_r"]
    local l = M.equipment["weapon_l"]
    return r ~= nil and l ~= nil and r.weaponTag == "单手剑" and l.weaponTag == "匕首"
end

--- 判断玩家是否任一形式的双持近战（双匕首或剑匕双持）
---@return boolean
function M.isDualMelee()
    return M.isDualDagger() or M.isSwordDagger()
end

--- 汇总所有已装备物品的属性加成（含强化加成）
---@return table<string, number> 各属性键对应的总加成值
function M.getEquipBonus()
    local bonus = {}
    local veilApplied = false  -- "朱莉"的面纱生效唯一标记
    local superiorApplied = {}  -- 卓越装备生效唯一：记录已生效的 templateId
    for _, slotId in ipairs(EQUIP_SLOT_ITERATE_ORDER) do
    local item = M.equipment[slotId]
        if item then
            -- 卓越装备生效唯一：同 templateId 只有第一件生效
            if item.rarity == "superior" and item.templateId then
                if superiorApplied[item.templateId] then
                    goto continueSlot
                end
                superiorApplied[item.templateId] = true
            end
            -- 基础属性（模板 effects，受强化影响）
            if item.effects then
                for k, v in pairs(item.effects) do
                    -- 兼容旧存档：maxMp → mp（养雷壶模板已修正）
                    if k == "maxMp" then k = "mp" end
                    bonus[k] = (bonus[k] or 0) + v
                end
            end
            -- 附加属性（extraEffects，不受强化影响；兼容旧实例从模板回填）
            local extra = item.extraEffects
            if not extra and item.templateId then
                local tpl = M.itemTemplates[item.templateId]
                if tpl then extra = tpl.extraEffects end
            end
            if extra then
                for k, v in pairs(extra) do
                    bonus[k] = (bonus[k] or 0) + v
                end
            end
            -- 强化加成（倍率表）
            local enhLv = item.enhanceLevel or 0
            if enhLv > 0 then
                local gain = M.getEnhanceGain(item, enhLv)
                for k, v in pairs(gain) do
                    bonus[k] = (bonus[k] or 0) + v
                end
            end
            -- 附魔加成
            local ench = item.enchantment
            if ench and ench.attr and ench.value then
                -- 附魔 attr 直接对应 bonus key（如 atk/mAtk/def/mDef/critVal 等）
                local key = ench.attr
                bonus[key] = (bonus[key] or 0) + ench.value
            end
            -- 精炼槽加成
            if item.refineSlots then
                for _, slot in ipairs(item.refineSlots) do
                    if slot.attr and slot.value then
                        bonus[slot.attr] = (bonus[slot.attr] or 0) + slot.value
                    end
                end
            end
            -- 宝石镶嵌加成
            if item.gemSlots then
                for _, slot in ipairs(item.gemSlots) do
                    -- "朱莉"的面纱生效唯一：按装备槽顺序只有第一颗生效
                    if slot.gemId == "gem_rainbow_masterwork" then
                        if veilApplied then
                            goto continueGemSlot  -- 已有一颗生效，跳过
                        end
                        veilApplied = true
                    end
                    if slot.gemEffect then
                        for k, v in pairs(slot.gemEffect) do
                            bonus[k] = (bonus[k] or 0) + v
                        end
                    end
                    ::continueGemSlot::
                end
            end
        end
        ::continueSlot::
    end
    -- 所有加成汇总后向下取整（如 str +0.5 和 +0.8 合计 +1.3 → +1）
    -- 百分比/小数属性不取整，否则 0.25% 吸血等会被截断为 0
    local noFloorAttrs = {
        physLifesteal = true, magLifesteal = true, lifesteal = true, batFangLifesteal = true,
        atkSpeed = true, critDmg = true, mCritDmg = true,
        pDmgReduce = true, mDmgReduce = true, onMagDmgHeal = true,
        resFire = true, resIce = true, resLightning = true, resShadow = true, resNature = true,
        healEffectPct = true,
        agiToAtkSpeedEff = true,  -- 每5点敏捷攻速系数（0.6~1.0），不能取整否则低档位变0
        perToHealEffPct = true,   -- 每5点感知治疗效果系数（0.15~0.35），不能取整
        counterRangedPct = true,  -- 反击倍率（0.6~1.0），不能取整否则低档位变0
        mpCostDmgCoeff = true,    -- 魔贯：施法消耗MP增伤系数（0.02~0.06），不能取整否则变0
        manaLeech = true,         -- 魔力回收（0.10~0.40%），不能取整否则变0
        dmgToMpPct = true,        -- 魔法石：伤害转魔法比例（0.5~2.5%），不能取整否则低档位变0
        mpToMagDmgPct = true,     -- 魔法石：每100最大MP法伤加成（0.7~1.5%），不能取整否则低档位变0
        aspdSkillDmgPct = true,   -- 极重月：攻速转技能伤害系数（0.2~0.6%），不能取整否则低档位变0
    }
    for k, v in pairs(bonus) do
        if not noFloorAttrs[k] then
            bonus[k] = math.floor(v)
        end
    end
    -- 兼容旧存档：pAtk 是 atk 的错误命名，合并进 atk
    if (bonus.pAtk or 0) > 0 then
        bonus.atk = (bonus.atk or 0) + bonus.pAtk
        bonus.pAtk = nil
    end
    -- 伴随星：根据装备槽位将条件属性转换为标准属性
    local wr = M.equipment["weapon_r"]
    local wl = M.equipment["weapon_l"]
    local inLeft  = (wl and wl.templateId == "companion_star")
    local inRight = (wr and wr.templateId == "companion_star")
    if inLeft then
        bonus.agi      = (bonus.agi or 0)      + (bonus.cstarAgiL or 0)
        bonus.atkSpeed = (bonus.atkSpeed or 0)  + (bonus.cstarAtkSpdL or 0)
    elseif inRight then
        bonus.str      = (bonus.str or 0)      + (bonus.cstarStrR or 0)
        bonus.wis      = (bonus.wis or 0)      + (bonus.cstarWisR or 0)
        bonus.critDmg  = (bonus.critDmg or 0)  + (bonus.cstarCritDmgR or 0)
        bonus.mCritDmg = (bonus.mCritDmg or 0) + (bonus.cstarMCritDmgR or 0)
    end
    return bonus
end

-- ====================================================================
-- 词缀数值同步：加载存档后根据当前池子定义刷新所有词缀 value
-- ====================================================================

--- 构建 attr → tiers 查找表
---@param pool table ENCHANT_POOL 或 REFINE_POOL
---@return table<string, table>
local function buildAffixLookup(pool)
    local lookup = {}
    for _, entry in ipairs(pool) do
        lookup[entry.attr] = entry.tiers
    end
    return lookup
end

--- 同步单个物品的附魔和精炼词缀数值
---@param item table
---@param enchLookup table
---@param refLookup table
local function syncItemAffixes(item, enchLookup, refLookup)
    if not item then return end
    -- 同步附魔
    if item.enchantment and item.enchantment.attr and item.enchantment.rolledTier then
        local tiers = enchLookup[item.enchantment.attr]
        if tiers then
            local newVal = tiers[item.enchantment.rolledTier + 1]
            if newVal then
                item.enchantment.value = newVal
            end
        end
    end
    -- 同步精炼槽位
    if item.refineSlots then
        for _, slot in ipairs(item.refineSlots) do
            if slot.attr and slot.rolledTier then
                local tiers = refLookup[slot.attr]
                if tiers then
                    local newVal = tiers[slot.rolledTier + 1]
                    if newVal then
                        slot.value = newVal
                    end
                end
            end
        end
    end
end

--- 同步所有已实例化装备的附魔/精炼词缀数值（存档加载后调用）
function M.syncAllAffixValues()
    local enchLookup = buildAffixLookup(M.ENCHANT_POOL)
    local refLookup  = buildAffixLookup(M.REFINE_POOL)
    local count = 0
    -- 背包
    if M.inventory then
        for _, item in pairs(M.inventory) do
            syncItemAffixes(item, enchLookup, refLookup)
            if item then count = count + 1 end
        end
    end
    -- 装备栏
    if M.equipment then
        for _, item in pairs(M.equipment) do
            syncItemAffixes(item, enchLookup, refLookup)
            count = count + 1
        end
    end
    -- 仓库
    if M.warehouses then
        for _, wh in ipairs(M.warehouses) do
            for _, item in pairs(wh) do
                syncItemAffixes(item, enchLookup, refLookup)
                if item then count = count + 1 end
            end
        end
    end
    print("[Items] Synced affix values for " .. count .. " items")
end

end  -- sub.init

return sub
