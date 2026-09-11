local EconomySkills = {}

EconomySkills.Definitions = {
    {
        id = "e_root", name = "招财火种", description = "点亮财富树。所有怪物金币获取提高10%。",
        icon = "image/nightgate/currency/asset_632cd9da.png", parents = {}, x = 410, y = 330,
        costs = { 20 }, values = { 10 }, effect = "goldGainBonus", effectText = "金币获取", suffix = "%",
    },
    {
        id = "e_gain", name = "金币增幅", description = "稳定提高每一枚飞入金币栏的金币价值。",
        icon = "image/nightgate/achievements/totalgold_76e38729.png", parents = { "e_root" }, x = 190, y = 190,
        costs = { 35, 75, 140, 240 }, values = { 10, 10, 10, 10 }, effect = "goldGainBonus", effectText = "金币获取", suffix = "%",
    },
    {
        id = "e_magnet", name = "黄金磁力", description = "金币更快飞入左侧计数，缩短等待时间。",
        icon = "image/nightgate/achievements/boxkilled_c837b95f.png", parents = { "e_gain" }, x = 20, y = 70,
        costs = { 75, 150, 300 }, values = { 25, 25, 25 }, effect = "coinFlightSpeed", effectText = "金币飞行速度", suffix = "%",
    },
    {
        id = "e_settle", name = "守夜红利", description = "每晚胜利时，按本夜已获得金币追加结算奖励。",
        icon = "image/nightgate/achievements/survivalday_a86b9cd8.png", parents = { "e_gain" }, x = 20, y = 300,
        costs = { 50, 100, 200 }, values = { 10, 10, 10 }, effect = "goldSettlementBonus", effectText = "结算金币", suffix = "%",
    },
    {
        id = "e_boss", name = "首领悬赏", description = "击败首领时获得更多基础金币，可继续触发倍率奖励。",
        icon = "image/nightgate/achievements/bossdefeated_4a433817.png", parents = { "e_settle" }, x = 20, y = 530,
        costs = { 120, 240, 480 }, values = { 25, 25, 25 }, effect = "bossGoldBonus", effectText = "首领金币", suffix = "%",
    },
    {
        id = "e_double", name = "双倍猎赏", description = "提高怪物掉落2倍金币的概率。基础概率为6%。",
        icon = "image/nightgate/achievements/enemieskilled_281a9c96.png", parents = { "e_root" }, x = 410, y = 90,
        costs = { 60, 120, 220 }, values = { 2, 2, 2 }, effect = "rewardDoubleChance", effectText = "2倍奖励概率", suffix = "%",
    },
    {
        id = "e_triple", name = "三倍猎赏", description = "提高怪物掉落3倍金币的概率。基础概率为2%。",
        icon = "image/nightgate/achievements/skilltreecount_e7f1479b.png", parents = { "e_double" }, x = 410, y = -120,
        costs = { 120, 240, 420 }, values = { 0.75, 0.75, 0.75 }, effect = "rewardTripleChance", effectText = "3倍奖励概率", suffix = "%",
    },
    {
        id = "e_quad", name = "四倍猎赏", description = "提高怪物掉落4倍金币的概率。基础概率为0.6%。",
        icon = "image/nightgate/achievements/skilltreecollected_340b1cd3.png", parents = { "e_triple" }, x = 630, y = -120,
        costs = { 240, 480, 800 }, values = { 0.25, 0.25, 0.25 }, effect = "rewardQuadChance", effectText = "4倍奖励概率", suffix = "%",
    },
    {
        id = "e_jackpot", name = "超级奖池", description = "超级大奖概率固定0.1%。每级把大奖倍率提高10倍。",
        icon = "image/nightgate/achievements/prestiged_8b334685.png", parents = { "e_quad" }, x = 800, y = 70,
        costs = { 500, 1000 }, values = { 10, 10 }, effect = "jackpotMultiplier", effectText = "大奖倍率", suffix = "倍",
    },
    {
        id = "e_elite", name = "淘金目光", description = "提高普通怪物变为带词缀精英怪的概率。",
        icon = "image/nightgate/achievements/equipcollected_bd3a6ed7.png", parents = { "e_root" }, x = 630, y = 190,
        costs = { 80, 160, 300 }, values = { 3, 3, 3 }, effect = "eliteChanceBonus", effectText = "精英怪概率", suffix = "%",
    },
    {
        id = "e_elite_reward", name = "精英悬赏", description = "迅捷、重甲、狂暴、富矿与梦魇怪掉落更多金币。",
        icon = "image/nightgate/achievements/survivorinfinal_5772b72d.png", parents = { "e_elite" }, x = 800, y = 300,
        costs = { 140, 280, 520 }, values = { 25, 25, 25 }, effect = "eliteRewardBonus", effectText = "精英金币", suffix = "%",
    },
    {
        id = "e_fever", name = "黄金狂潮", description = "财富树终点。所有金币获取额外提高25%。",
        icon = "image/nightgate/achievements/gameplayed_6c82dbdc.png", parents = { "e_boss", "e_jackpot", "e_elite_reward" }, x = 410, y = 580,
        costs = { 1500 }, values = { 25 }, effect = "goldGainBonus", effectText = "金币获取", suffix = "%",
    },
}

local byId = {}
for index = 1, #EconomySkills.Definitions do
    byId[EconomySkills.Definitions[index].id] = EconomySkills.Definitions[index]
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

function EconomySkills.GetDefinition(id)
    return byId[id]
end

function EconomySkills.GetLevel(levels, id)
    return math.max(0, math.floor(tonumber(levels and levels[id]) or 0))
end

function EconomySkills.GetUnlockReason(levels, definition)
    if not definition then return "未知财富节点" end
    for index = 1, #definition.parents do
        local parentId = definition.parents[index]
        if EconomySkills.GetLevel(levels, parentId) <= 0 then
            local parent = byId[parentId]
            return "需先点亮「" .. tostring(parent and parent.name or parentId) .. "」"
        end
    end
    return nil
end

function EconomySkills.IsRevealed(levels, definition)
    if not definition then return false end
    if #definition.parents == 0 or EconomySkills.GetLevel(levels, definition.id) > 0 then return true end
    for index = 1, #definition.parents do
        if EconomySkills.GetLevel(levels, definition.parents[index]) > 0 then return true end
    end
    return false
end

function EconomySkills.GetNodeState(levels, definition)
    local level = EconomySkills.GetLevel(levels, definition.id)
    if EconomySkills.GetUnlockReason(levels, definition) then return "locked" end
    if level >= #definition.costs then return "maxed" end
    if level > 0 then return "owned" end
    return "available"
end

function EconomySkills.GetCost(levels, id)
    local definition = byId[id]
    return definition and definition.costs[EconomySkills.GetLevel(levels, id) + 1] or nil
end

function EconomySkills.GetEffectText(definition, levelIndex)
    levelIndex = math.max(1, math.floor(tonumber(levelIndex) or 1))
    local value = definition.values[levelIndex] or definition.values[#definition.values] or 0
    return definition.effectText .. " +" .. tostring(value) .. (definition.suffix or "")
end

local function getEffectTotal(levels, effect)
    local total = 0
    for index = 1, #EconomySkills.Definitions do
        local definition = EconomySkills.Definitions[index]
        if definition.effect == effect then
            local level = math.min(EconomySkills.GetLevel(levels, definition.id), #definition.values)
            for valueIndex = 1, level do
                total = total + (tonumber(definition.values[valueIndex]) or 0)
            end
        end
    end
    return total
end

function EconomySkills.ApplyStats(stats, levels)
    stats.rewardDoubleChance = clamp(0.06 + getEffectTotal(levels, "rewardDoubleChance") / 100, 0, 0.35)
    stats.rewardTripleChance = clamp(0.02 + getEffectTotal(levels, "rewardTripleChance") / 100, 0, 0.15)
    stats.rewardQuadChance = clamp(0.006 + getEffectTotal(levels, "rewardQuadChance") / 100, 0, 0.08)
    stats.jackpotChance = 0.001
    stats.jackpotMultiplier = 20 + getEffectTotal(levels, "jackpotMultiplier")
    stats.eliteChanceBonus = clamp(getEffectTotal(levels, "eliteChanceBonus") / 100, 0, 0.20)
    stats.eliteRewardBonus = math.max(0, getEffectTotal(levels, "eliteRewardBonus") / 100)
    stats.bossGoldBonus = math.max(0, getEffectTotal(levels, "bossGoldBonus") / 100)
    stats.coinFlightSpeed = 1 + math.max(0, getEffectTotal(levels, "coinFlightSpeed") / 100)
    stats.goldGainBonus = (stats.goldGainBonus or 0) + getEffectTotal(levels, "goldGainBonus") / 100
    stats.goldSettlementBonus = (stats.goldSettlementBonus or 0) + getEffectTotal(levels, "goldSettlementBonus")
end

function EconomySkills.TryUpgrade(battle, id)
    local definition = byId[id]
    if not definition then return false, "未知财富节点" end
    local levels = battle.economyLevels or {}
    local reason = EconomySkills.GetUnlockReason(levels, definition)
    if reason then return false, reason end
    local level = EconomySkills.GetLevel(levels, id)
    local cost = definition.costs[level + 1]
    if not cost then return false, "已满级" end
    if (tonumber(battle.gold) or 0) < cost then return false, "金币不足，还需 " .. tostring(cost - math.floor(battle.gold or 0)) end
    battle.gold = battle.gold - cost
    battle.economyLevels = levels
    levels[id] = level + 1
    battle.dirtySave = true
    return true, "已点亮「" .. definition.name .. "」"
end

return EconomySkills
