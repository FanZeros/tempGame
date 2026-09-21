local Config = require("diggin.Config")
local AbyssDifficulty = require("diggin.AbyssDifficulty")

local AbyssPassives = {}

AbyssPassives.MAX_SLOTS = 5
AbyssPassives.MAX_LEVEL = 5
AbyssPassives.START_REROLLS = 5

AbyssPassives.DEFINITIONS = {
    { id = "giant_core", name = "巨化核心", iconName = "DynamiteRadius", color = Config.Palette.orange,
        description = "道具体积 +10%/级", stats = { size_pct = 10 } },
    { id = "echo_chamber", name = "增殖腔室", iconName = "DynamiteAmount", color = Config.Palette.gold,
        description = "Lv.3/Lv.5时，道具数量 +1", stats = { amount_progress = 0.4 } },
    { id = "rift_compass", name = "裂隙罗盘", iconName = "ShockwaveRadius", color = Config.Palette.purple,
        description = "释放范围 +12%/级", stats = { range_pct = 12 } },
    { id = "coolant_loop", name = "永冻回路", iconName = "DynamiteCooldown", color = Config.Palette.cyan,
        description = "道具冷却 -5%/级（总缩减上限70%）", stats = { cooldown_pct = 5 } },
    { id = "power_prism", name = "增幅棱镜", iconName = "DynamiteDamage", color = Config.Palette.red,
        description = "道具攻击伤害 +10%/级", stats = { damage_pct = 10 } },
    { id = "swift_bearing", name = "迅捷轴承", iconName = "DrillDroneSpeed", color = Config.Palette.cyan,
        description = "投射与攻击速度 +9%/级", stats = { attack_speed_pct = 9 } },
    { id = "crit_lens", name = "暴击透镜", iconName = "CritChance1", color = Config.Palette.gold,
        description = "道具暴击率 +5%/级", stats = { critical_chance = 5 } },
    { id = "ruin_crown", name = "毁灭冠冕", iconName = "CritDamage1", color = Config.Palette.red,
        description = "道具暴击伤害 +30%/级", stats = { critical_damage_pct = 30 } },
    { id = "legendary_ember", name = "传奇余烬", iconName = "Feverstone", color = Config.Palette.purple,
        description = "传奇一击率 +1.2%/级（造成4倍伤害）", stats = { legendary_chance = 1.2 } },
    { id = "lucky_clover", name = "幸运星芽", iconName = "GoldBonanza", color = Config.Palette.green,
        description = "幸运 +12/级；提升装备与传奇概率", stats = { luck = 12 } },
}

local BY_ID = {}
for _, definition in ipairs(AbyssPassives.DEFINITIONS) do
    definition.maxLevel = AbyssPassives.MAX_LEVEL
    definition.icon = Config.Paths.generatedRoot .. "skill_icons/" .. definition.iconName .. ".png"
    BY_ID[definition.id] = definition
end

local REWARDS = {
    { id = "reward_fuel", reward = true, name = "紧急燃芯", description = "立即恢复25%燃料",
        color = Config.Palette.green },
    { id = "reward_coins", reward = true, name = "深渊钱袋", description = "立即获得本层金币补给",
        color = Config.Palette.gold },
    { id = "reward_reroll", reward = true, name = "命运重置", description = "刷新次数 +1",
        color = Config.Palette.cyan },
}

function AbyssPassives.GetRewardOptions()
    return REWARDS
end

function AbyssPassives.GetDefinition(id)
    return BY_ID[id]
end

function AbyssPassives.GetLevel(abyss, id)
    return math.max(0, math.floor(tonumber(abyss and abyss.passives and abyss.passives[id]) or 0))
end

function AbyssPassives.GetSlotCount(abyss)
    local count = 0
    for _, definition in ipairs(AbyssPassives.DEFINITIONS) do
        if AbyssPassives.GetLevel(abyss, definition.id) > 0 then count = count + 1 end
    end
    return count
end

function AbyssPassives.GetStat(abyss, statId)
    local total = 0
    for _, definition in ipairs(AbyssPassives.DEFINITIONS) do
        local value = definition.stats and definition.stats[statId]
        if value then total = total + value * AbyssPassives.GetLevel(abyss, definition.id) end
    end
    return total
end

function AbyssPassives.GetAmountBonus(abyss)
    return math.floor(AbyssPassives.GetStat(abyss, "amount_progress"))
end

local function optionFor(abyss, definition)
    local level = AbyssPassives.GetLevel(abyss, definition.id)
    local nextLevel = math.min(AbyssPassives.MAX_LEVEL, level + 1)
    return {
        id = definition.id,
        name = definition.name,
        description = definition.description,
        color = definition.color,
        icon = definition.icon,
        passive = true,
        slotType = "被动",
        level = level,
        nextLevel = nextLevel,
        maxLevel = AbyssPassives.MAX_LEVEL,
    }
end

function AbyssPassives.MakeChoice(abyss, completedFloor)
    local slots = AbyssPassives.GetSlotCount(abyss)
    local candidates = {}
    for _, definition in ipairs(AbyssPassives.DEFINITIONS) do
        local level = AbyssPassives.GetLevel(abyss, definition.id)
        if level > 0 and level < AbyssPassives.MAX_LEVEL then
            candidates[#candidates + 1] = definition
        elseif level == 0 and slots < AbyssPassives.MAX_SLOTS then
            candidates[#candidates + 1] = definition
        end
    end
    if #candidates == 0 then return nil end

    local serial = math.max(1, math.floor(tonumber(abyss.passiveChoiceSerial) or 1))
    local start = ((serial * 7 + completedFloor * 5 - 1) % #candidates) + 1
    local options = {}
    for offset = 0, math.min(2, #candidates - 1) do
        options[#options + 1] = optionFor(abyss, candidates[((start + offset - 1) % #candidates) + 1])
    end
    for _, reward in ipairs(REWARDS) do
        if #options >= 3 then break end
        options[#options + 1] = reward
    end
    abyss.passiveChoiceSerial = serial + 1
    return {
        kind = "passive",
        floor = completedFloor,
        title = "第 " .. tostring(completedFloor) .. " 层 · 被动技能三选一",
        options = options,
    }
end

function AbyssPassives.MakeRewardChoice(completedFloor)
    return {
        kind = "reward",
        floor = completedFloor,
        title = "构筑已满级 · 选择即时补给",
        options = REWARDS,
    }
end

function AbyssPassives.Apply(app, abyss, id)
    local definition = BY_ID[id]
    if not definition then return false end
    abyss.passives = abyss.passives or {}
    local oldLevel = AbyssPassives.GetLevel(abyss, id)
    if oldLevel >= AbyssPassives.MAX_LEVEL then return false end
    if oldLevel == 0 and AbyssPassives.GetSlotCount(abyss) >= AbyssPassives.MAX_SLOTS then return false end

    abyss.passives[id] = oldLevel + 1
    abyss.forgeProgress = math.min(3, (abyss.forgeProgress or 0) + 1)
    if id == "lucky_clover" then
        abyss.rerolls = math.min(9, (abyss.rerolls or 0) + 1)
    end
    return true, optionFor({ passives = { [id] = oldLevel } }, definition)
end

function AbyssPassives.ApplyReward(app, abyss, id, floor)
    if id == "reward_fuel" then
        app.fuel = math.min(app.maxFuel, app.fuel + app.maxFuel * 0.25)
    elseif id == "reward_coins" then
        local amount = AbyssDifficulty.GetCoinPouchAmount(floor)
        abyss.tower.coins = (abyss.tower.coins or 0) + amount
        abyss.tower.coinsEarned = (abyss.tower.coinsEarned or 0) + amount
    elseif id == "reward_reroll" then
        abyss.rerolls = math.min(9, (abyss.rerolls or 0) + 1)
    else
        return false
    end
    for _, reward in ipairs(REWARDS) do
        if reward.id == id then return true, reward end
    end
    return false
end

return AbyssPassives
