local Config = require("nightgate.Config")
local OriginalData = require("nightgate.OriginalData")
local Prestige = require("nightgate.Prestige")
local EconomySkills = require("nightgate.EconomySkills")
local ExpansionSkills = require("nightgate.ExpansionSkills")

local Skills = {}

-- Preserve all 78 source-derived records, then append release expansion nodes.
-- Copying the references into a new array keeps OriginalData immutable and old
-- save IDs fully compatible.
Skills.Definitions = {}
for index = 1, #OriginalData.SkillDefinitions do
    Skills.Definitions[#Skills.Definitions + 1] = OriginalData.SkillDefinitions[index]
end
for index = 1, #ExpansionSkills.Definitions do
    Skills.Definitions[#Skills.Definitions + 1] = ExpansionSkills.Definitions[index]
end

local byId = {}
local unlockSkillByAttribute = {}
for index = 1, #Skills.Definitions do
    local definition = Skills.Definitions[index]
    byId[definition.id] = definition
    if definition.attribute >= 37 and definition.attribute <= 45 then
        unlockSkillByAttribute[definition.attribute] = definition.id
    end
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function getItemInstance(value)
    if type(value) == "number" then
        return value, 0
    end
    if type(value) == "table" then
        return tonumber(value.id), math.max(0, math.floor(tonumber(value.level) or 0))
    end
    return nil, 0
end

function Skills.GetDefinition(id)
    return byId[id]
end

function Skills.GetUnlockedHeroes(levels)
    local heroes = {}
    for index = 1, #Config.HEROES do
        local hero = Config.HEROES[index]
        local skillId = unlockSkillByAttribute[hero.unlockAttribute]
        if skillId and Skills.GetLevel(levels, skillId) > 0 then
            heroes[#heroes + 1] = hero
        end
    end
    return heroes
end

function Skills.GetHeroForSide(levels, selectedHeroes, sideIndex)
    sideIndex = clamp(math.floor(tonumber(sideIndex) or 1), 1, 4)
    local heroes = Skills.GetUnlockedHeroes(levels)
    local selectedId = tonumber(selectedHeroes and (selectedHeroes[sideIndex] or selectedHeroes[tostring(sideIndex)]))
    if selectedId then
        for index = 1, #heroes do
            if heroes[index].id == selectedId then
                return heroes[index]
            end
        end
    end
    return heroes[sideIndex]
end

function Skills.GetArcherCount(levels)
    local count = 0
    for index = 1, #Skills.Definitions do
        local definition = Skills.Definitions[index]
        if definition.attribute == 33 then
            local level = math.min(Skills.GetLevel(levels, definition.id), #definition.values)
            for valueIndex = 1, level do
                count = count + (tonumber(definition.values[valueIndex]) or 0)
            end
        end
    end
    return math.max(0, math.floor(count + 0.5))
end

function Skills.IsArcherUnlocked(levels)
    return Skills.GetArcherCount(levels) > 0
end

function Skills.GetAttributeValue(levels, attribute)
    local total = 0
    for index = 1, #Skills.Definitions do
        local definition = Skills.Definitions[index]
        if definition.attribute == attribute then
            local level = math.min(Skills.GetLevel(levels, definition.id), #definition.values)
            for valueIndex = 1, level do
                total = total + (tonumber(definition.values[valueIndex]) or 0)
            end
        end
    end
    return total
end

function Skills.GetUnlockedArchers(levels)
    local archers = {}
    if not Skills.IsArcherUnlocked(levels) then
        return archers
    end
    for index = 1, #Config.ARCHERS do
        local archer = Config.ARCHERS[index]
        if archer.unlockAttribute == 0 or Skills.GetAttributeValue(levels, archer.unlockAttribute) > 0 then
            archers[#archers + 1] = archer
        end
    end
    return archers
end

function Skills.GetArcherForSide(levels, selectedArchers, sideIndex)
    sideIndex = clamp(math.floor(tonumber(sideIndex) or 1), 1, 4)
    local archers = Skills.GetUnlockedArchers(levels)
    local selectedId = tonumber(selectedArchers and (selectedArchers[sideIndex] or selectedArchers[tostring(sideIndex)]))
    if selectedId then
        for index = 1, #archers do
            if archers[index].id == selectedId then
                return archers[index]
            end
        end
    end
    return archers[1]
end

function Skills.GetLevel(levels, id)
    return math.max(0, math.floor(tonumber(levels and levels[id]) or 0))
end

function Skills.GetUnlockReason(levels, definition, bestNight)
    bestNight = math.max(0, math.floor(tonumber(bestNight) or 0))
    if bestNight < definition.survivorNight then
        return "需守过第 " .. tostring(definition.survivorNight) .. " 晚"
    end
    for index = 1, #definition.parents do
        local parentId = definition.parents[index]
        local parentLevel = Skills.GetLevel(levels, parentId)
        local parentDefinition = byId[parentId]
        if parentLevel < 1 then
            local parentName = parentDefinition and parentDefinition.name or parentId
            return "前置“" .. tostring(parentName) .. "”需先点亮1级"
        end
    end
    return nil
end

function Skills.IsUnlocked(levels, definition, bestNight)
    return Skills.GetUnlockReason(levels, definition, bestNight) == nil
end

function Skills.GetNodeState(levels, definition, bestNight)
    local level = Skills.GetLevel(levels, definition.id)
    if not Skills.IsUnlocked(levels, definition, bestNight) then
        return "locked"
    elseif level >= #definition.costs then
        return "maxed"
    elseif level > 0 then
        return "owned"
    end
    return "available"
end

function Skills.IsRevealed(levels, definition)
    if not definition then
        return false
    end
    if #definition.parents == 0 or Skills.GetLevel(levels, definition.id) > 0 then
        return true
    end
    for index = 1, #definition.parents do
        if Skills.GetLevel(levels, definition.parents[index]) > 0 then
            return true
        end
    end
    return false
end

function Skills.GetCost(levels, id)
    local definition = byId[id]
    if not definition then
        return nil
    end
    return definition.costs[Skills.GetLevel(levels, id) + 1]
end

function Skills.GetEffectText(definition, levelIndex)
    levelIndex = math.max(1, math.floor(tonumber(levelIndex) or 1))
    if definition.levelTexts then
        return definition.levelTexts[levelIndex] or definition.levelTexts[#definition.levelTexts]
    end
    local value = definition.values[levelIndex] or definition.values[#definition.values] or 0
    if string.sub(definition.name, 1, 6) == "解锁" then
        return definition.name
    end
    return definition.name .. " +" .. tostring(value) .. (definition.percent and "%" or "")
end

local function addAttribute(stats, attribute, value, effectTarget)
    effectTarget = math.floor(tonumber(effectTarget) or 0)
    if attribute == 3 then
        stats.wallDefense = stats.wallDefense + value
    elseif attribute == 4 then
        if effectTarget == 1 then
            stats.archerCrit = stats.archerCrit + value / 100
        elseif effectTarget == 2 then
            stats.heroCrit = stats.heroCrit + value / 100
        else
            stats.globalCrit = stats.globalCrit + value / 100
        end
    elseif attribute == 5 then
        if effectTarget == 1 then
            stats.archerCritDamage = stats.archerCritDamage + value / 100
        elseif effectTarget == 2 then
            stats.heroCritDamage = stats.heroCritDamage + value / 100
        else
            stats.globalCritDamage = stats.globalCritDamage + value / 100
        end
    elseif attribute == 7 then
        stats.wallDodge = stats.wallDodge + value / 100
    elseif attribute == 8 then
        if effectTarget == 1 then
            stats.archerAllDamageBonus = stats.archerAllDamageBonus + value / 100
        elseif effectTarget == 2 then
            stats.heroAllDamageBonus = stats.heroAllDamageBonus + value / 100
        else
            stats.allDamageBonus = stats.allDamageBonus + value / 100
        end
    elseif attribute == 9 then
        stats.wallRegen = stats.wallRegen + value
    elseif attribute == 13 then
        if effectTarget == 2 then
            stats.heroProjectilePoints = stats.heroProjectilePoints + value
        else
            stats.projectilePoints = stats.projectilePoints + value
        end
    elseif attribute == 15 then
        if effectTarget == 2 then
            stats.heroProjectileSizeBonus = stats.heroProjectileSizeBonus + value / 100
        else
            stats.projectileSizeBonus = stats.projectileSizeBonus + value / 100
        end
    elseif attribute == 16 then
        if effectTarget == 1 then
            stats.archerProjectilePenetration = stats.archerProjectilePenetration + value / 100
        elseif effectTarget == 2 then
            stats.heroProjectilePenetration = stats.heroProjectilePenetration + value / 100
        else
            stats.projectilePenetration = stats.projectilePenetration + value / 100
        end
    elseif attribute == 17 then
        if effectTarget == 1 then
            stats.archerProjectileRadiusBonus = stats.archerProjectileRadiusBonus + value / 100
        elseif effectTarget == 2 then
            stats.heroProjectileRadiusBonus = stats.heroProjectileRadiusBonus + value / 100
        else
            stats.projectileRadiusBonus = stats.projectileRadiusBonus + value / 100
        end
    elseif attribute == 24 then
        stats.cursorBase = stats.cursorBase + value
    elseif attribute == 26 then
        stats.cursorCrit = stats.cursorCrit + value / 100
    elseif attribute == 27 then
        stats.cursorCritDamage = stats.cursorCritDamage + value / 100
    elseif attribute == 28 then
        stats.cursorRadiusBonus = stats.cursorRadiusBonus + value / 100
    elseif attribute == 29 then
        stats.cursorCooldownReduction = stats.cursorCooldownReduction + value / 100
    elseif attribute == 30 then
        stats.cursorDoubleChance = stats.cursorDoubleChance + value / 100
    elseif attribute == 31 then
        stats.archerDamage = stats.archerDamage + value
    elseif attribute == 32 then
        stats.archerCooldownReduction = stats.archerCooldownReduction + value / 100
    elseif attribute == 33 then
        stats.archerCount = stats.archerCount + value
    elseif attribute == 34 then
        stats.archerBerserkChance = stats.archerBerserkChance + value / 100
    elseif attribute == 35 then
        stats.archerBossBonus = stats.archerBossBonus + value / 100
    elseif attribute >= 37 and attribute <= 45 then
        stats.heroUnlocks[attribute] = true
    elseif attribute == 46 then
        stats.heroDamage = stats.heroDamage + value
    elseif attribute == 47 then
        stats.heroCooldownReduction = stats.heroCooldownReduction + value / 100
    elseif attribute == 48 or attribute == 49 or attribute == 50 then
        stats.heroSkillDamageByAttribute[attribute] = stats.heroSkillDamageByAttribute[attribute] + value
    elseif attribute == 52 then
        stats.wallFlat = stats.wallFlat + value
    elseif attribute == 54 then
        stats.randomCursorEnabled = stats.randomCursorEnabled + value
    elseif attribute == 55 then
        stats.randomCursorCooldownReduction = stats.randomCursorCooldownReduction + value / 100
    elseif attribute == 56 then
        stats.randomCursorCount = stats.randomCursorCount + value
    elseif attribute == 57 then
        stats.cursorChestChance = stats.cursorChestChance + value / 100
    elseif attribute == 58 then
        stats.goldDropFlat = stats.goldDropFlat + value
    elseif attribute == 59 then
        stats.extraCrystalMonsters = stats.extraCrystalMonsters + value
    elseif attribute == 60 then
        stats.materialDoubleChance = stats.materialDoubleChance + value / 100
    elseif attribute == 61 then
        stats.crystalQualityChance = stats.crystalQualityChance + value / 100
    elseif attribute == 63 then
        stats.normalCrystalChance = stats.normalCrystalChance + value / 100
    elseif attribute == 64 then
        stats.goldSettlementBonus = stats.goldSettlementBonus + value
    elseif attribute == 65 then
        stats.crystalSettlementBonus = stats.crystalSettlementBonus + value
    elseif attribute == 66 then
        stats.dragonAssist = stats.dragonAssist + value
    elseif attribute == 69 then
        stats.archerEileenPassiveUnlocked = value > 0 or stats.archerEileenPassiveUnlocked
    elseif attribute == 70 then
        stats.archerMiaUnlocked = value > 0 or stats.archerMiaUnlocked
    elseif attribute == 71 then
        stats.explosiveArrowUnlocked = value > 0 or stats.explosiveArrowUnlocked
    end
end

local function roleIsActive(battle, wallIndex, role, archerUnlocked)
    if role == "captain" then
        return archerUnlocked
    elseif role == "hero" then
        return Skills.GetHeroForSide(battle.skillLevels, battle.selectedHeroes, wallIndex) ~= nil
    end
    return false
end

local function addEquipment(stats, equipment, battle, archerUnlocked)
    if type(equipment) ~= "table" then
        return
    end
    for wallKey, wall in pairs(equipment) do
        if type(wall) == "table" then
            local wallIndex = clamp(math.floor(tonumber(wallKey) or 1), 1, 4)
            for role, roleSlots in pairs(wall) do
                if type(roleSlots) == "table" and roleIsActive(battle, wallIndex, role, archerUnlocked) then
                    for _, instance in pairs(roleSlots) do
                        local itemId, level = getItemInstance(instance)
                        local item = Config.EQUIPMENT_BY_ID[itemId]
                        if item then
                            local strengthen = Config.EQUIPMENT_STRENGTHEN[level + 1]
                            local multiplier = 1 + (strengthen and strengthen.effectAdd or 0)
                            for attrIndex = 1, #item.attributes do
                                local attr = item.attributes[attrIndex]
                                addAttribute(stats, attr.type, attr.value * multiplier, role == "captain" and 1 or 2)
                            end
                        end
                    end
                end
            end
        end
    end
end

function Skills.GetStats(battle)
    local stats = {
        cursorBase = Config.CURSOR.baseDamage,
        cursorCooldownReduction = 0,
        cursorRadiusBonus = 0,
        cursorCrit = 0,
        cursorCritDamage = 0.5,
        cursorDoubleChance = 0,
        wallFlat = 0,
        wallDefense = 0,
        wallDodge = 0,
        wallRegen = 0,
        archerCount = 0,
        archerDamage = Config.ARCHER.damage,
        archerCooldownReduction = 0,
        archerBerserkChance = 0,
        archerBossBonus = 0,
        heroDamage = 0,
        heroCooldownReduction = 0,
        heroSkillDamageByAttribute = { [48] = 0, [49] = 0, [50] = 0 },
        heroUnlocks = {},
        allDamageBonus = 0,
        archerAllDamageBonus = 0,
        heroAllDamageBonus = 0,
        globalCrit = 0,
        globalCritDamage = 0,
        archerCrit = 0,
        archerCritDamage = 0,
        heroCrit = 0,
        heroCritDamage = 0,
        projectilePoints = 0,
        heroProjectilePoints = 0,
        projectileSizeBonus = 0,
        heroProjectileSizeBonus = 0,
        projectilePenetration = 0,
        archerProjectilePenetration = 0,
        heroProjectilePenetration = 0,
        projectileRadiusBonus = 0,
        archerProjectileRadiusBonus = 0,
        heroProjectileRadiusBonus = 0,
        randomCursorEnabled = 0,
        randomCursorCooldownReduction = 0,
        randomCursorCount = 0,
        cursorChestChance = 0,
        goldDropFlat = 0,
        extraCrystalMonsters = 0,
        materialDoubleChance = 0,
        crystalQualityChance = 0,
        normalCrystalChance = 0,
        goldGainBonus = 0,
        goldSettlementBonus = 0,
        crystalSettlementBonus = 0,
        dragonAssist = 0,
        archerEileenPassiveUnlocked = false,
        archerMiaUnlocked = false,
        explosiveArrowUnlocked = false,
    }
    local levels = battle.skillLevels or {}
    for index = 1, #Skills.Definitions do
        local definition = Skills.Definitions[index]
        local level = math.min(Skills.GetLevel(levels, definition.id), #definition.values)
        for valueIndex = 1, level do
            addAttribute(stats, definition.attribute, definition.values[valueIndex], definition.effectTarget)
        end
    end
    ExpansionSkills.ApplyStats(stats, levels)
    Prestige.ApplyStats(stats, battle.prestigeLevels or {}, battle)
    EconomySkills.ApplyStats(stats, battle.economyLevels or {})
    local prestigeMilestone = Prestige.GetMilestone(battle.prestigeMilestone)
    for index = 1, #Config.PRESTIGE_BLESSINGS do
        local blessing = Config.PRESTIGE_BLESSINGS[index]
        if prestigeMilestone >= blessing.night then
            addAttribute(stats, blessing.attribute, blessing.value)
        end
    end
    stats.unlockedHeroes = Skills.GetUnlockedHeroes(levels)
    stats.archerCount = math.max(0, math.floor(stats.archerCount + 0.5))
    stats.archerUnlocked = stats.archerCount > 0
    addEquipment(stats, battle.equipment, battle, stats.archerUnlocked)

    local damageLevel = math.max(0, math.floor(tonumber(battle.quickDamageLevel) or 0))
    local wallLevel = math.max(0, math.floor(tonumber(battle.quickWallLevel) or 0))
    stats.damageMultiplier = 1 + stats.allDamageBonus + damageLevel * 0.05
    stats.archerDamageMultiplier = stats.damageMultiplier * (1 + stats.archerAllDamageBonus)
    stats.heroDamageMultiplier = stats.damageMultiplier * (1 + stats.heroAllDamageBonus)
    stats.wallMax = math.max(1, math.floor((110 + stats.wallFlat) * (1 + wallLevel * 0.10) + 0.5))
    stats.cursorRadius = Config.CURSOR.radius * (1 + stats.cursorRadiusBonus)
    stats.cursorSpeed = 1 / math.max(0.15, 1 - clamp(stats.cursorCooldownReduction, 0, 0.85))
    stats.archerSpeed = 1 / math.max(0.15, 1 - clamp(stats.archerCooldownReduction, 0, 0.85))
    stats.heroSpeed = 1 / math.max(0.15, 1 - clamp(stats.heroCooldownReduction, 0, 0.85))
    stats.wallDodge = clamp(stats.wallDodge, 0, 0.85)
    stats.cursorCrit = clamp(stats.cursorCrit + stats.globalCrit, 0, 1)
    stats.cursorCritDamageMultiplier = 1 + stats.cursorCritDamage + stats.globalCritDamage
    stats.archerCrit = clamp(stats.archerCrit + stats.globalCrit, 0, 1)
    stats.archerCritDamageMultiplier = 1.5 + stats.archerCritDamage + stats.globalCritDamage
    stats.heroCrit = clamp(stats.heroCrit + stats.globalCrit, 0, 1)
    stats.heroCritDamageMultiplier = 1.5 + stats.heroCritDamage + stats.globalCritDamage
    stats.cursorDoubleChance = clamp(stats.cursorDoubleChance, 0, 1)
    stats.archerBerserkChance = clamp(stats.archerBerserkChance, 0, 1)
    stats.archerBossBonus = math.max(0, stats.archerBossBonus)
    stats.archerProjectilePenetration = clamp(stats.projectilePenetration + stats.archerProjectilePenetration, 0, 1)
    stats.heroProjectilePenetration = clamp(stats.projectilePenetration + stats.heroProjectilePenetration, 0, 1)
    stats.archerProjectileRadiusBonus = stats.projectileRadiusBonus + stats.archerProjectileRadiusBonus
    stats.heroProjectileRadiusBonus = stats.projectileRadiusBonus + stats.heroProjectileRadiusBonus
    stats.heroProjectileSizeMultiplier = 1 + stats.projectileSizeBonus + stats.heroProjectileSizeBonus
    local heroProjectilePoints = stats.projectilePoints + stats.heroProjectilePoints
    stats.heroProjectileExtraCount = math.floor(heroProjectilePoints / 100)
    stats.heroProjectileExtraChance = (heroProjectilePoints % 100) / 100
    -- Backward-compatible aliases for renderer/UI code while all combat paths
    -- migrate to the explicitly hero-scoped values above.
    stats.projectileExtraCount = stats.heroProjectileExtraCount
    stats.projectileExtraChance = stats.heroProjectileExtraChance
    stats.projectilePenetration = stats.heroProjectilePenetration
    stats.projectileRadiusBonus = stats.heroProjectileRadiusBonus
    stats.randomCursorInterval = 4 * math.max(0.15, 1 - clamp(stats.randomCursorCooldownReduction, 0, 0.85))
    stats.materialDoubleChance = clamp(stats.materialDoubleChance, 0, 1)
    stats.normalCrystalChance = clamp(stats.normalCrystalChance, 0, 1)
    return stats
end

function Skills.TryUpgrade(battle, id)
    local definition = byId[id]
    if not definition then
        return false, "未知技能"
    end
    local reason = Skills.GetUnlockReason(battle.skillLevels, definition, battle.bestNight)
    if reason then
        return false, reason
    end
    local level = Skills.GetLevel(battle.skillLevels, id)
    local cost = definition.costs[level + 1]
    if not cost then
        return false, "已满级"
    end
    if battle.gold < cost then
        return false, "金币不足"
    end
    battle.gold = battle.gold - cost
    battle.skillLevels[id] = level + 1
    battle.dirtySave = true
    return true, "节点已点亮"
end

function Skills.GetQuickCost(kind, level)
    level = math.max(0, math.floor(tonumber(level) or 0))
    local definition = OriginalData.QuickUpgrade[kind]
    if definition and definition.costs[level + 1] then
        return definition.costs[level + 1]
    end
    if kind == "damage" then
        return math.floor(level * 0.75 + 0.5) + 1
    end
    return math.floor(level * 0.8 + 0.5) + 3
end

function Skills.TryQuickUpgrade(battle, kind)
    local definition = OriginalData.QuickUpgrade[kind]
    if not definition then
        return false, "未知强化"
    end
    local field = kind == "damage" and "quickDamageLevel" or "quickWallLevel"
    local level = math.max(0, math.floor(tonumber(battle[field]) or 0))
    if level >= definition.maxLevel then
        return false, "已满级"
    end
    local cost = Skills.GetQuickCost(kind, level)
    if battle.crystals < cost then
        return false, "晶石不足"
    end
    battle.crystals = battle.crystals - cost
    battle[field] = level + 1
    battle.dirtySave = true
    return true, "强化成功"
end

return Skills
