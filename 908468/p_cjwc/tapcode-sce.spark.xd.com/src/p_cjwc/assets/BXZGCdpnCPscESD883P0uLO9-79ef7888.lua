local MonsterAffixes = {}

MonsterAffixes.Definitions = {
    { id = "swift", name = "迅捷", minNight = 4, weight = 35, color = { 83, 224, 255, 255 }, hp = 0.85, speed = 1.40, reward = 1.5 },
    { id = "armored", name = "重甲", minNight = 7, weight = 30, color = { 191, 205, 219, 255 }, hp = 1.70, speed = 0.85, reward = 2.0 },
    { id = "frenzy", name = "狂暴", minNight = 10, weight = 20, color = { 255, 78, 63, 255 }, hp = 1.10, speed = 1.10, wallDamage = 1.50, attackSpeed = 1.50, reward = 2.5 },
    { id = "golden", name = "富矿", minNight = 12, weight = 12, color = { 255, 205, 57, 255 }, hp = 1.30, size = 1.10, reward = 4.0 },
    { id = "nightmare", name = "梦魇", minNight = 20, weight = 3, color = { 200, 104, 255, 255 }, hp = 2.50, speed = 1.20, wallDamage = 2.0, attackSpeed = 1.35, size = 1.15, reward = 8.0 },
}

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

function MonsterAffixes.GetBaseChance(night)
    night = math.max(0, math.floor(tonumber(night) or 0))
    if night < 4 then return 0 end
    return math.min(0.26, 0.08 + (night - 4) * 0.007)
end

function MonsterAffixes.Apply(enemy, night, stats, randomFn)
    if not enemy or enemy.boss or enemy.bonus or (tonumber(enemy.crystal) or 0) > 0 then return nil end
    randomFn = randomFn or math.random
    local chance = clamp(MonsterAffixes.GetBaseChance(night) + (tonumber(stats and stats.eliteChanceBonus) or 0), 0, 0.42)
    if chance <= 0 or randomFn() >= chance then return nil end

    local eligible = {}
    local totalWeight = 0
    for index = 1, #MonsterAffixes.Definitions do
        local definition = MonsterAffixes.Definitions[index]
        if night >= definition.minNight then
            eligible[#eligible + 1] = definition
            totalWeight = totalWeight + definition.weight
        end
    end
    if totalWeight <= 0 then return nil end
    local roll = randomFn() * totalWeight
    local selected = eligible[#eligible]
    for index = 1, #eligible do
        roll = roll - eligible[index].weight
        if roll <= 0 then selected = eligible[index]; break end
    end

    enemy.elite = true
    enemy.affix = selected.id
    enemy.affixName = selected.name
    enemy.affixColor = selected.color
    enemy.name = selected.name .. "·" .. tostring(enemy.name or "怪物")
    enemy.maxHP = math.max(1, math.floor((enemy.maxHP or enemy.hp or 1) * (selected.hp or 1) + 0.5))
    enemy.hp = enemy.maxHP
    enemy.speed = (enemy.speed or 0) * (selected.speed or 1)
    enemy.wallDamage = math.max(1, math.floor((enemy.wallDamage or 1) * (selected.wallDamage or 1) + 0.5))
    enemy.attackInterval = (enemy.attackInterval or 1) / math.max(0.1, selected.attackSpeed or 1)
    enemy.size = (enemy.size or 24) * (selected.size or 1)
    enemy.reward = math.max(1, math.floor((enemy.reward or 0) * (selected.reward or 1) + 0.5))
    return selected
end

return MonsterAffixes
