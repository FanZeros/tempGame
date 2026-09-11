local LootSystem = {}

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

function LootSystem.RollGoldReward(baseReward, stats, enemy, randomFn)
    stats = stats or {}
    randomFn = randomFn or math.random
    local reward = math.max(0, tonumber(baseReward) or 0)
    if enemy and enemy.boss then
        reward = reward * (1 + math.max(0, tonumber(stats.bossGoldBonus) or 0))
    end
    if enemy and enemy.elite then
        reward = reward * (1 + math.max(0, tonumber(stats.eliteRewardBonus) or 0))
    end

    local jackpotChance = clamp(tonumber(stats.jackpotChance) or 0.001, 0, 0.01)
    local quadChance = clamp(tonumber(stats.rewardQuadChance) or 0.006, 0, 0.08)
    local tripleChance = clamp(tonumber(stats.rewardTripleChance) or 0.02, 0, 0.15)
    local doubleChance = clamp(tonumber(stats.rewardDoubleChance) or 0.06, 0, 0.35)
    local roll = clamp(tonumber(randomFn()) or 1, 0, 1)
    local multiplier = 1
    local tier = "normal"
    local threshold = jackpotChance
    if roll < threshold then
        multiplier = math.max(20, math.floor(tonumber(stats.jackpotMultiplier) or 20))
        tier = "jackpot"
    else
        threshold = threshold + quadChance
        if roll < threshold then
            multiplier, tier = 4, "quad"
        else
            threshold = threshold + tripleChance
            if roll < threshold then
                multiplier, tier = 3, "triple"
            else
                threshold = threshold + doubleChance
                if roll < threshold then multiplier, tier = 2, "double" end
            end
        end
    end
    return math.max(0, math.floor(reward * multiplier + 0.5)), multiplier, tier
end

function LootSystem.GetTierPresentation(tier, multiplier)
    if tier == "jackpot" then
        return "超级大奖 ×" .. tostring(multiplier), { 255, 240, 83, 255 }, 29, "jackpot"
    elseif tier == "quad" then
        return "四倍奖励 ×4", { 255, 113, 49, 255 }, 23, "reward"
    elseif tier == "triple" then
        return "三倍奖励 ×3", { 218, 139, 255, 255 }, 21, "reward"
    elseif tier == "double" then
        return "双倍奖励 ×2", { 87, 225, 255, 255 }, 19, "reward"
    end
    return nil
end

return LootSystem
