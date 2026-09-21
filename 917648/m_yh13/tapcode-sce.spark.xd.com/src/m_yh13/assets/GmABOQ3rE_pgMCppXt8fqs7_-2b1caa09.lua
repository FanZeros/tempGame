local Config = require("diggin.Config")

local AbyssDifficulty = {}

function AbyssDifficulty.GetEarlyStage(floor)
    floor = math.max(1, math.floor(tonumber(floor) or 1))
    return math.min(Config.Abyss.difficultyEarlyCap,
        math.floor((floor - 1) / Config.Abyss.difficultyEarlyInterval))
end

function AbyssDifficulty.GetDeepStage(floor)
    floor = math.max(1, math.floor(tonumber(floor) or 1))
    if floor <= 100 then return 0 end
    return math.max(0, math.floor((floor - 101) / Config.Abyss.difficultyDeepInterval))
end

function AbyssDifficulty.GetStage(floor)
    return AbyssDifficulty.GetEarlyStage(floor) + AbyssDifficulty.GetDeepStage(floor)
end

function AbyssDifficulty.GetTileHealthMultiplier(floor)
    local early = AbyssDifficulty.GetEarlyStage(floor)
    local deep = AbyssDifficulty.GetDeepStage(floor)
    return (1 + early * Config.Abyss.difficultyTilePerEarlyStage)
        * Config.Abyss.difficultyTilePerDeepStage ^ deep
end

function AbyssDifficulty.GetExitHealthMultiplier(floor)
    local tileMultiplier = AbyssDifficulty.GetTileHealthMultiplier(floor)
    return 1 + (tileMultiplier - 1) * Config.Abyss.difficultyExitInheritance
end

function AbyssDifficulty.GetEnemyHealthMultiplier(floor)
    local early = AbyssDifficulty.GetEarlyStage(floor)
    local deep = AbyssDifficulty.GetDeepStage(floor)
    return (1 + early * Config.Abyss.difficultyEnemyHealthPerEarlyStage)
        * Config.Abyss.difficultyEnemyHealthPerDeepStage ^ deep
end

function AbyssDifficulty.GetEnemyDamageMultiplier(floor)
    local early = AbyssDifficulty.GetEarlyStage(floor)
    local deep = AbyssDifficulty.GetDeepStage(floor)
    return (1 + early * Config.Abyss.difficultyEnemyDamagePerEarlyStage)
        * Config.Abyss.difficultyEnemyDamagePerDeepStage ^ deep
end

function AbyssDifficulty.GetChaserSpeedMultiplier(floor)
    local early = AbyssDifficulty.GetEarlyStage(floor)
    local deep = AbyssDifficulty.GetDeepStage(floor)
    local multiplier = (1 + early * Config.Abyss.difficultyChaserSpeedPerEarlyStage)
        * Config.Abyss.difficultyChaserSpeedPerDeepStage ^ deep
    return math.min(Config.Abyss.difficultyChaserSpeedCap, multiplier)
end

function AbyssDifficulty.GetEliteChance(floor)
    local early = AbyssDifficulty.GetEarlyStage(floor)
    local deep = AbyssDifficulty.GetDeepStage(floor)
    return math.min(Config.Abyss.difficultyEliteChanceCap,
        early * Config.Abyss.difficultyEliteChancePerEarlyStage
            + deep * Config.Abyss.difficultyEliteChancePerDeepStage)
end

function AbyssDifficulty.GetNormalEnemyTarget(floor)
    local stage = AbyssDifficulty.GetStage(floor)
    return math.min(Config.Abyss.difficultyMaxNormalEnemies,
        Config.Abyss.enemyBaseCount + math.floor(stage / 2))
end

function AbyssDifficulty.GetSupplyCost(floor)
    return math.min(Config.Abyss.shopCostCap,
        Config.Abyss.shopBaseCost
            + AbyssDifficulty.GetStage(floor) * Config.Abyss.shopCostPerDifficulty)
end

function AbyssDifficulty.GetCoinPouchAmount(floor)
    return math.min(50, 18 + AbyssDifficulty.GetStage(floor) * 4)
end

function AbyssDifficulty.GetNextMilestone(floor)
    floor = math.max(1, math.floor(tonumber(floor) or 1))
    if floor < 100 then
        return (math.floor((floor - 1) / 20) + 1) * 20
    end
    return 100 + (math.floor((floor - 100) / 50) + 1) * 50
end

return AbyssDifficulty
