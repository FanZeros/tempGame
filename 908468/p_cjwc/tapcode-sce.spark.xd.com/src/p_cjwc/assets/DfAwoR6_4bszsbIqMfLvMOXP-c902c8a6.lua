local Save = {}

local FILE_NAME = "nightgate_mobile_save.json"

local function normalizeSpeedMultiplier(value)
    value = math.floor(tonumber(value) or 1)
    if value == 2 or value == 3 then return value end
    return 1
end

local function normalizeVolume(value)
    return math.max(0, math.min(1, tonumber(value) or 1))
end

local function normalize(data)
    data = type(data) == "table" and data or {}
    local hasExistingProgress = (tonumber(data.gold) or 3) > 3
        or (tonumber(data.bestNight) or 1) > 1
        or (tonumber(data.nextNight) or 1) > 1
        or (tonumber(data.prestigeCount) or 0) > 0
        or (type(data.skillLevels) == "table" and next(data.skillLevels) ~= nil)
        or (type(data.inventory) == "table" and #data.inventory > 0)
    if data.tutorialCompleted == nil then
        -- Existing saves predate the tutorial flag. Do not interrupt players who
        -- have already made progress; a genuinely fresh save starts the guide.
        data.tutorialCompleted = hasExistingProgress
    else
        data.tutorialCompleted = data.tutorialCompleted == true
    end
    local rawPrestigeCount = math.max(0, math.floor(tonumber(data.prestigeCount) or 0))
    local legacyPrestige = rawPrestigeCount > 0 and data.prestigePoints == nil and data.prestigeLevels == nil
    data.gold = math.max(0, math.floor(tonumber(data.gold) or 3))
    data.crystals = math.max(0, math.floor(tonumber(data.crystals) or 0))
    data.bestNight = math.max(1, math.floor(tonumber(data.bestNight) or 1))
    data.nextNight = math.max(1, math.floor(tonumber(data.nextNight) or 1))
    data.quickDamageLevel = math.max(0, math.floor(tonumber(data.quickDamageLevel) or 0))
    data.quickWallLevel = math.max(0, math.floor(tonumber(data.quickWallLevel) or 0))
    data.equipmentShards = math.max(0, math.floor(tonumber(data.equipmentShards) or 0))
    data.finalDifficultyUnlocked = math.max(0, math.floor(tonumber(data.finalDifficultyUnlocked) or 0))
    data.finalDifficultySelected = math.max(0, math.floor(tonumber(data.finalDifficultySelected) or 0))
    data.prestigeCount = rawPrestigeCount
    local milestoneSource = data.prestigeMilestone
    if milestoneSource == nil and rawPrestigeCount > 0 then milestoneSource = 10 end
    local milestone = math.max(0, math.floor(tonumber(milestoneSource) or 0))
    data.prestigeMilestone = milestone >= 30 and 30 or (milestone >= 20 and 20 or (milestone >= 10 and 10 or 0))
    data.prestigePoints = math.max(0, math.floor(tonumber(data.prestigePoints) or 0))
    data.prestigePointsTotal = math.max(data.prestigePoints, math.floor(tonumber(data.prestigePointsTotal) or data.prestigePoints))
    data.prestigeLevels = type(data.prestigeLevels) == "table" and data.prestigeLevels or {}
    data.economyLevels = type(data.economyLevels) == "table" and data.economyLevels or {}
    if legacyPrestige then
        data.prestigeLevels.p_root = math.max(1, math.floor(tonumber(data.prestigeLevels.p_root) or 0))
        data.prestigePoints = math.max(data.prestigePoints, 5)
        data.prestigePointsTotal = math.max(data.prestigePointsTotal, 6)
        data.gold = math.max(data.gold, 6)
    end
    data.selectedArchers = type(data.selectedArchers) == "table" and data.selectedArchers or {}
    data.selectedHeroes = type(data.selectedHeroes) == "table" and data.selectedHeroes or {}
    data.skillLevels = type(data.skillLevels) == "table" and data.skillLevels or {}
    data.inventory = type(data.inventory) == "table" and data.inventory or {}
    data.equipment = type(data.equipment) == "table" and data.equipment or {}
    data.speedMultiplier = normalizeSpeedMultiplier(data.speedMultiplier)
    data.musicVolume = normalizeVolume(data.musicVolume)
    data.sfxVolume = normalizeVolume(data.sfxVolume)
    data.adSupplyClaimKey = type(data.adSupplyClaimKey) == "string" and data.adSupplyClaimKey or nil
    data.adSupplyReadyKey = type(data.adSupplyReadyKey) == "string" and data.adSupplyReadyKey or nil
    return data
end

function Save.Load()
    if not fileSystem:FileExists(FILE_NAME) then
        return normalize(nil)
    end
    local file = File(FILE_NAME, FILE_READ)
    if not file:IsOpen() then
        return normalize(nil)
    end
    local raw = file:ReadString()
    file:Close()
    local ok, data = pcall(cjson.decode, raw)
    return normalize(ok and data or nil)
end

function Save.Store(battle)
    local file = File(FILE_NAME, FILE_WRITE)
    if not file:IsOpen() then
        return false
    end
    file:WriteString(cjson.encode({
        gold = math.floor(battle.gold),
        crystals = math.floor(battle.crystals),
        bestNight = math.floor(battle.bestNight),
        nextNight = math.floor(battle.nextNight),
        quickDamageLevel = math.floor(battle.quickDamageLevel),
        quickWallLevel = math.floor(battle.quickWallLevel),
        equipmentShards = math.floor(battle.equipmentShards),
        finalDifficultyUnlocked = math.floor(battle.finalDifficultyUnlocked),
        finalDifficultySelected = math.floor(battle.finalDifficultySelected),
        prestigeCount = math.floor(battle.prestigeCount or 0),
        prestigeMilestone = math.floor(battle.prestigeMilestone or 0),
        prestigePoints = math.floor(battle.prestigePoints or 0),
        prestigePointsTotal = math.floor(battle.prestigePointsTotal or 0),
        prestigeLevels = battle.prestigeLevels,
        economyLevels = battle.economyLevels,
        selectedArchers = battle.selectedArchers,
        selectedHeroes = battle.selectedHeroes,
        skillLevels = battle.skillLevels,
        inventory = battle.inventory,
        equipment = battle.equipment,
        speedMultiplier = normalizeSpeedMultiplier(battle.speedMultiplier),
        musicVolume = normalizeVolume(battle.musicVolume),
        sfxVolume = normalizeVolume(battle.sfxVolume),
        tutorialCompleted = battle.tutorialCompleted == true,
        adSupplyClaimKey = battle.adSupplyClaimKey,
        adSupplyReadyKey = battle.adSupplyReadyKey,
    }))
    file:Close()
    battle.dirtySave = false
    return true
end

return Save
