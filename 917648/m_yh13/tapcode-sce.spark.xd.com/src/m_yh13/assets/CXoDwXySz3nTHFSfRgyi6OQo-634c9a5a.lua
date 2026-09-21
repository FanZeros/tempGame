local Config = require("diggin.Config")
local Util = require("diggin.Util")
local SkillTreeData = require("diggin.data.SkillTreeData")
local RelicData = require("diggin.data.RelicData")
local WorldTree = require("diggin.WorldTree")
local AbyssLoot = require("diggin.AbyssLoot")
local Cosmetics = require("diggin.Cosmetics")
local MobileControlLayout = require("diggin.MobileControlLayout")

local State = {}
State.__index = State

local SAVE_FILE = "diggin-save-v2.json"
local CLOUD_KEY = "diggin_save_v2"
local SAVE_VERSION = 19

local function cloneTable(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, nested in pairs(value) do result[cloneTable(key)] = cloneTable(nested) end
    return result
end

local THROUGHPUT_ORES = {
    Starmetal = true,
    Ruby = true,
    Emerald = true,
    Diamond = true,
    StarDebris = true,
    StarStone = true,
    FactoryOre = true,
    MissionRewardOre = true,
}

local function effectIdFromNode(node)
    local key = node.name_key or ""
    if key:sub(1, 13) == "SKILLTREEUPG_" then
        return key:sub(14):lower()
    end
    return node.id:lower()
end

local function makeInventory()
    local result = {}
    for _, ore in pairs(Config.OreNames) do
        result[ore] = 0
    end
    return result
end

function State.New()
    local self = setmetatable({}, State)
    self.skillData = SkillTreeData
    self.nodeById = {}
    for _, node in ipairs(SkillTreeData.nodes) do
        self.nodeById[node.id] = node
        node.effect_id = effectIdFromNode(node)
    end
    self.inventory = makeInventory()
    self.cosmetics = Cosmetics.Normalize(nil)
    self.runInventory = makeInventory()
    self.skillLevels = { UpgradeStart = 1 }
    self.artefacts = {}
    self.discoveredArtefacts = {}
    self.relicData = RelicData
    self.relicCores = 0
    self.unlockedRelics = {}
    self.seenRelics = {}
    self.equippedRelics = {}
    self.missionLayerClaims = {}
    self.starDebrisMilestoneClaims = {}
    self.progressionRecoveryVersion = 2
    self.progressionRecoveryGrant = nil
    self.runIridiumPity = 0
    self.runFinalDensityStarStoneClaimed = false
    self.goldenDrillCharges = 0
    -- This entitlement is account-wide and intentionally survives "new game"
    -- so the one-time support reward cannot be reclaimed by resetting progress.
    self.supportStarStoneClaimed = false
    self.worldTreeAwakened = false
    self.worldTreePoints = 0
    self.worldTreeLifetimePoints = 0
    self.worldTreeLevels = {}
    self.testWorldTreeResetVersion = 0
    self.bestAbyssTime = 0
    self.bestAbyssFloor = 0
    self.bestAbyssHardcoreFloor = 0
    self.bestAbyssS2Floor, self.bestAbyssS2HardcoreFloor = 0, 0
    self.abyssRuns = 0
    self.abyssEquipment = {}
    self.abyssEquipmentStorage = {}
    self.nextAbyssEquipmentUid = 1
    self.abyssLootCounts = {}
    self.abyssDiscoveredEquipment = {}
    self.abyssDust = 0
    self.prestige = 1
    self.unlockedPrestige = 1
    self.totalUpgrades = 0
    self.runs = 0
    self.deepestLayer = 0
    self.muted = false
    self.drillSoundEnabled = true
    self.toastEnabled = true
    self.screenShakeEnabled = true
    self.mobileControlLayout = MobileControlLayout.Normalize(nil)
    self.cloudReady = false
    self.cloudError = nil
    self.cloudSaveInFlight = false
    self.pendingCloudSnapshot = nil
    self.saveRevision = 0
    self.loadedSaveVersion = 0
    self.abyssRulesActive = false
    self:LoadLocal()
    self:ApplyTestBuildUnlocks()
    return self
end

function State:ResetProgress()
    self._testOriginalProgress = nil
    self.inventory = makeInventory()
    self.runInventory = makeInventory()
    self.skillLevels = { UpgradeStart = 1 }
    self.artefacts = {}
    self.discoveredArtefacts = {}
    self.relicCores = 0
    self.unlockedRelics = {}
    self.seenRelics = {}
    self.equippedRelics = {}
    self.missionLayerClaims = {}
    self.starDebrisMilestoneClaims = {}
    self.progressionRecoveryVersion = 2
    self.progressionRecoveryGrant = nil
    self.runIridiumPity = 0
    self.runFinalDensityStarStoneClaimed = false
    self.goldenDrillCharges = 0
    self.worldTreeAwakened = false
    self.worldTreePoints = 0
    self.worldTreeLifetimePoints = 0
    self.worldTreeLevels = {}
    self.testWorldTreeResetVersion = 0
    self.bestAbyssTime = 0
    self.bestAbyssFloor = 0
    self.bestAbyssHardcoreFloor = 0
    self.bestAbyssS2Floor, self.bestAbyssS2HardcoreFloor = 0, 0
    self.abyssRuns = 0
    self.abyssEquipment = {}
    self.abyssEquipmentStorage = {}
    self.nextAbyssEquipmentUid = 1
    self.abyssLootCounts = {}
    self.abyssDiscoveredEquipment = {}
    self.abyssDust = 0
    self.prestige = 1
    self.unlockedPrestige = 1
    self.totalUpgrades = 0
    self.runs = 0
    self.deepestLayer = 0
    self.abyssRulesActive = false
    self:ApplyTestBuildUnlocks()
    self:Save()
end

function State:ApplyTestBuildUnlocks()
    if Config.TEST_MAX_SKILL_TREE ~= true then return false end
    if not self._testOriginalProgress then
        self._testOriginalProgress = {
            inventory = cloneTable(self.inventory), skillLevels = cloneTable(self.skillLevels),
            artefacts = cloneTable(self.artefacts), discoveredArtefacts = cloneTable(self.discoveredArtefacts),
            missionLayerClaims = cloneTable(self.missionLayerClaims), totalUpgrades = self.totalUpgrades,
            unlockedPrestige = self.unlockedPrestige, prestige = self.prestige, deepestLayer = self.deepestLayer,
            worldTreeAwakened = self.worldTreeAwakened, worldTreeLevels = cloneTable(self.worldTreeLevels),
            worldTreePoints = self.worldTreePoints, worldTreeLifetimePoints = self.worldTreeLifetimePoints,
            testWorldTreeResetVersion = self.testWorldTreeResetVersion,
        }
    end
    local boughtNodes = 0
    for _, node in ipairs(self.skillData.nodes) do
        self.skillLevels[node.id] = math.max(1, math.floor(tonumber(node.max_level) or 1))
        if node.id ~= "UpgradeStart" then boughtNodes = boughtNodes + 1 end
        if node.is_artefact then
            self.discoveredArtefacts[node.id] = true
            self.artefacts[node.id] = nil
        end
    end
    self.totalUpgrades = math.max(self.totalUpgrades or 0, boughtNodes)
    self.unlockedPrestige = 11
    self.prestige = 11
    self.deepestLayer = math.max(self.deepestLayer or 0, 10)
    self.missionLayerClaims = self.missionLayerClaims or {}
    for density = 1, 10 do
        self.missionLayerClaims[tostring(density) .. ":10"] = true
    end
    self.inventory.Stardrop = Config.STARDROPS_FOR_FINAL_DENSITY
    self.worldTreeAwakened = true
    local resetVersion = math.max(0,
        math.floor(tonumber(Config.TEST_WORLD_TREE_RESET_VERSION) or 0))
    local appliedResetVersion = math.max(0,
        math.floor(tonumber(self.testWorldTreeResetVersion) or 0))
    if resetVersion > appliedResetVersion then
        self.worldTreeLevels = {}
        self.worldTreePoints = 0
        self.worldTreeLifetimePoints = 0
        self.testWorldTreeResetVersion = resetVersion
    end
    if Config.TEST_MAX_WORLD_TREE == true then
        self.worldTreeLevels = self.worldTreeLevels or {}
        local spent = 0
        for _, worldNode in ipairs(WorldTree.NODES or {}) do
            local maxLevel = math.max(1, math.floor(tonumber(worldNode.maxLevel) or 1))
            self.worldTreeLevels[worldNode.id] = maxLevel
            spent = spent + math.max(0, math.floor(tonumber(worldNode.cost) or 0)) * maxLevel
        end
        -- Keep spare points visible for checking future nodes and purchase UI,
        -- while every currently defined node remains at its true max level.
        self.worldTreePoints = math.max(self.worldTreePoints or 0, 9999)
        self.worldTreeLifetimePoints = math.max(self.worldTreeLifetimePoints or 0,
            spent + self.worldTreePoints)
    end
    return true
end

function State:ResetRunInventory()
    self.runInventory = makeInventory()
    self.runIridiumPity = 0
    self.runFinalDensityStarStoneClaimed = false
end

function State:RegisterIridiumPity(layerIndex, oreName)
    if self.prestige < Config.IRIDIUM_PITY_MIN_DENSITY
        or oreName == "Iridium" or oreName == "Bedrock" or oreName == "StarBarrier" then
        return 0
    end
    self.runIridiumPity = (self.runIridiumPity or 0) + 1
    if self.runIridiumPity < Config.IRIDIUM_PITY_BLOCKS then return 0 end
    self.runIridiumPity = self.runIridiumPity - Config.IRIDIUM_PITY_BLOCKS
    return (tonumber(layerIndex) or 1) >= 5 and 2 or 1
end

function State:RefineBacklog(rawOre, refinedOre, multiplier)
    local refinedPerRaw = math.max(1, math.floor(tonumber(multiplier) or 1))
    local consumedTotal = 0
    local refinedTotal = 0
    for _, source in ipairs({ self.runInventory, self.inventory }) do
        local available = math.max(0, math.floor(tonumber(source[rawOre]) or 0))
        if available > 0 then
            local batch = math.max(1, math.ceil(available * Config.REFINERY_BACKLOG_PERCENT / 100))
            batch = math.min(available, batch)
            source[rawOre] = available - batch
            local produced = batch * refinedPerRaw
            source[refinedOre] = (source[refinedOre] or 0) + produced
            consumedTotal = consumedTotal + batch
            refinedTotal = refinedTotal + produced
        end
    end
    return consumedTotal, refinedTotal
end

function State:HasProgress()
    if self.runs > 0 or self.totalUpgrades > 0 or self.relicCores > 0
        or self.goldenDrillCharges > 0 or self:GetDensityStarCount() > 0
        or self.worldTreeLifetimePoints > 0 or self:GetAbyssLootTotal() > 0 then return true end
    if next(self.unlockedRelics) or next(self.artefacts) or next(self.discoveredArtefacts) then return true end
    for _, amount in pairs(self.inventory) do
        if amount > 0 then return true end
    end
    return false
end

function State:GetAbyssLootTotal()
    local total = 0
    for _, amount in pairs(self.abyssLootCounts or {}) do
        total = total + math.max(0, math.floor(tonumber(amount) or 0))
    end
    return total
end

function State:GetBestAbyssFloor(mode, season)
    if season == 2 then
        local key = mode == "hardcore" and "bestAbyssS2HardcoreFloor" or "bestAbyssS2Floor"
        return math.max(0, math.floor(tonumber(self[key]) or 0))
    end
    if mode == "hardcore" then
        return math.max(0, math.floor(tonumber(self.bestAbyssHardcoreFloor) or 0))
    end
    return math.max(0, math.floor(tonumber(self.bestAbyssFloor) or 0))
end

function State:RegisterAbyssDepth(mode, floor)
    floor = math.max(1, math.floor(tonumber(floor) or 1))
    local key = mode == "hardcore" and "bestAbyssHardcoreFloor" or "bestAbyssFloor"
    local previous = math.max(0, math.floor(tonumber(self[key]) or 0))
    self[key] = math.max(previous, floor)
    local seasonKey = mode == "hardcore" and "bestAbyssS2HardcoreFloor" or "bestAbyssS2Floor"
    local seasonPrevious = tonumber(self[seasonKey]) or 0
    self[seasonKey] = math.max(seasonPrevious, floor)
    return self[key] > previous or self[seasonKey] > seasonPrevious
end

function State:GetAbyssEquipmentBonus(statId)
    return AbyssLoot.GetBonus(self, statId)
end

function State:AddAbyssLoot(item)
    if type(item) ~= "table" then return false, 0 end
    local grade = AbyssLoot.GetGrade(item.grade)
    local slot = AbyssLoot.GetSlot(item.slot)
    if not grade or not slot then return false, 0 end
    self.abyssEquipment = self.abyssEquipment or {}
    self.abyssLootCounts = self.abyssLootCounts or {}
    self.abyssDiscoveredEquipment = self.abyssDiscoveredEquipment or {}
    if AbyssLoot.GetArchetype(item.archetypeId) then self.abyssDiscoveredEquipment[item.archetypeId] = true end
    self.abyssLootCounts[grade.id] = math.min(999999,
        math.max(0, math.floor(tonumber(self.abyssLootCounts[grade.id]) or 0)) + 1)

    self.abyssEquipmentStorage = self.abyssEquipmentStorage or {}
    self.nextAbyssEquipmentUid = math.max(1, math.floor(tonumber(self.nextAbyssEquipmentUid) or 1))
    local normalized = AbyssLoot.NormalizeEquipmentEntry(item, slot.id)
    normalized.uid = self.nextAbyssEquipmentUid
    self.nextAbyssEquipmentUid = self.nextAbyssEquipmentUid + 1
    local equipped, stored, dust = false, false, 0
    if not AbyssLoot.GetEquippedItem(self, slot.id) then
        self.abyssEquipment[slot.id] = normalized
        equipped = true
    else
        local capacity = math.max(1, math.floor(tonumber(Config.Abyss.equipmentStorageCapacity) or 60))
        if #self.abyssEquipmentStorage < capacity then
            self.abyssEquipmentStorage[#self.abyssEquipmentStorage + 1] = normalized
            stored = true
        else
            local weakestIndex, weakestScore = 1, math.huge
            for index, storedItem in ipairs(self.abyssEquipmentStorage) do
                local score = AbyssLoot.GetEquipmentScore(storedItem)
                if score < weakestScore then weakestIndex, weakestScore = index, score end
            end
            if AbyssLoot.GetEquipmentScore(normalized) > weakestScore then
                dust = AbyssLoot.GetSalvageValue(self.abyssEquipmentStorage[weakestIndex])
                self.abyssEquipmentStorage[weakestIndex] = normalized
                stored = true
            else
                dust = AbyssLoot.GetSalvageValue(normalized)
            end
        end
    end
    self.abyssDust = math.min(9999999, math.max(0, math.floor(tonumber(self.abyssDust) or 0)) + dust)
    self:Save()
    return equipped, dust, stored
end

function State:GetMobileControls()
    return MobileControlLayout.ToControls(self.mobileControlLayout)
end

function State:SetMobileControlPosition(id, x, y)
    local changed, layout = MobileControlLayout.SetPosition(self.mobileControlLayout, id, x, y)
    if changed then self.mobileControlLayout = layout end
    return changed
end

function State:ResetMobileControls()
    self.mobileControlLayout = MobileControlLayout.Normalize(nil)
    self:Save()
end

function State:GetAbyssStoredItem(uid)
    uid = math.floor(tonumber(uid) or 0)
    for index, item in ipairs(self.abyssEquipmentStorage or {}) do
        if math.floor(tonumber(item.uid) or 0) == uid then return item, index end
    end
    return nil, nil
end

function State:EquipAbyssStoredItem(uid)
    local item, index = self:GetAbyssStoredItem(uid)
    if not item or not AbyssLoot.GetSlot(item.slot) then return false, "装备不存在" end
    local previous = AbyssLoot.GetEquippedItem(self, item.slot)
    self.abyssEquipment[item.slot] = item
    if previous then
        if math.floor(tonumber(previous.uid) or 0) <= 0 then
            previous.uid = self.nextAbyssEquipmentUid
            self.nextAbyssEquipmentUid = self.nextAbyssEquipmentUid + 1
        end
        self.abyssEquipmentStorage[index] = previous
    else table.remove(self.abyssEquipmentStorage, index) end
    self:Save()
    return true, item.slot
end

function State:SalvageAbyssStoredItem(uid)
    local item, index = self:GetAbyssStoredItem(uid)
    if not item then return false, "装备不存在" end
    local dust = AbyssLoot.GetSalvageValue(item)
    table.remove(self.abyssEquipmentStorage, index)
    self.abyssDust = math.min(9999999, (self.abyssDust or 0) + dust)
    self:Save()
    return true, dust
end

local function isBulkSalvageCandidate(state, item, maxGradeIndex)
    if type(item) ~= "table" or item.locked == true or (item.forgeLevel or 0) > 0 then return false end
    local grade = AbyssLoot.GetGrade(item.grade)
    local equipped = AbyssLoot.GetEquippedItem(state, item.slot)
    if not grade or grade.index > maxGradeIndex or not equipped then return false end
    return AbyssLoot.GetEquipmentScore(item) <= AbyssLoot.GetEquipmentScore(equipped)
end

function State:GetAbyssBulkSalvagePreview(maxGradeId)
    local maxGrade = AbyssLoot.GetGrade(maxGradeId or "B") or AbyssLoot.GetGrade("B")
    local count, dust = 0, 0
    for _, item in ipairs(self.abyssEquipmentStorage or {}) do
        if isBulkSalvageCandidate(self, item, maxGrade.index) then
            count = count + 1
            dust = dust + AbyssLoot.GetSalvageValue(item)
        end
    end
    return count, dust
end

function State:SalvageAbyssStoredJunk(maxGradeId)
    local maxGrade = AbyssLoot.GetGrade(maxGradeId or "B") or AbyssLoot.GetGrade("B")
    local count, dust = 0, 0
    self.abyssEquipmentStorage = self.abyssEquipmentStorage or {}
    for index = #self.abyssEquipmentStorage, 1, -1 do
        local item = self.abyssEquipmentStorage[index]
        if isBulkSalvageCandidate(self, item, maxGrade.index) then
            count = count + 1
            dust = dust + AbyssLoot.GetSalvageValue(item)
            table.remove(self.abyssEquipmentStorage, index)
        end
    end
    if count <= 0 then return false, "没有可分解的F～B级弱装备", 0 end
    self.abyssDust = math.min(9999999, (self.abyssDust or 0) + dust)
    self:Save()
    return true, dust, count
end

function State:AddStardrops(amount)
    local limit = Config.STARDROPS_FOR_FINAL_DENSITY
    local before = self:GetDensityStarCount()
    local requested = math.max(0, math.floor(tonumber(amount) or 0))
    local after = Util.Clamp(before + requested, 0, limit)
    local added = after - before
    if added <= 0 then return 0, false end
    self.inventory.Stardrop = after
    self.runInventory.Stardrop = (self.runInventory.Stardrop or 0) + added
    self:Save()
    return added, before < limit and after >= limit
end

function State:AddRunOre(oreName, amount)
    if self.runInventory[oreName] == nil then return 0, false end
    if oreName == "Stardrop" then
        -- Stardrop is the single permanent star progression value. It is
        -- banked immediately so a reload during a run cannot erase it.
        return self:AddStardrops(amount)
    end
    local resourceGain = self:GetGeneralStat("resource_gain")
    local multiplier = Config.PRESTIGE_FACTOR ^ (self.prestige - 1)
    multiplier = multiplier * (1 + resourceGain / 100)
    if self:IsNodeBought("ResourceTripler") and math.random() * 100 < self:GetActiveStat("triple_trouble", "chance") then
        multiplier = multiplier * 3
    end
    local added = math.max(1, math.floor(amount * multiplier))
    self.runInventory[oreName] = self.runInventory[oreName] + added
    return added, false
end

function State:AddGoldenDrillCharges(amount)
    local added = math.max(0, math.floor(tonumber(amount) or 0))
    if added <= 0 then return 0 end
    self.goldenDrillCharges = math.min(9999, self.goldenDrillCharges + added)
    self:Save()
    return added
end

function State:CanClaimSupportStarStone()
    return self.supportStarStoneClaimed ~= true
end

function State:GrantSupportStarStone()
    if not self:CanClaimSupportStarStone() then return false, 0 end
    self.supportStarStoneClaimed = true
    self.inventory.StarStone = math.min(999999,
        math.max(0, math.floor(tonumber(self.inventory.StarStone) or 0)) + 1)
    self:Save()
    return true, 1
end

-- Consumes exactly one charge for a directly drilled block. The probability
-- buckets are exclusive: jackpot 0.1%, triple 5%, double 20%.
function State:RollGoldenDrillReward()
    if self.goldenDrillCharges <= 0 then return 1, nil, false end
    self.goldenDrillCharges = self.goldenDrillCharges - 1
    local roll = math.random() * 100
    local jackpot = Config.GoldenDrill.jackpotChance
    local triple = jackpot + Config.GoldenDrill.tripleChance
    local double = triple + Config.GoldenDrill.doubleChance
    if roll < jackpot then
        return Config.GoldenDrill.jackpotMultiplier, "jackpot", true
    elseif roll < triple then
        return 3, "triple", true
    elseif roll < double then
        return 2, "double", true
    end
    return 1, nil, true
end

function State:CommitRunInventory(context)
    context = context or {}
    local total = 0
    local resourceBonus = 0
    local adBonusEligibleTotal = 0
    local settledResources = {}
    local settlementPct = self:GetRelicBonus("settlement_yield_pct")
    for ore, amount in pairs(self.runInventory) do
        -- Stars were banked immediately by AddRunOre; settlement must not add
        -- them a second time or apply any yield multiplier.
        local bonus = 0
        if ore ~= "Stardrop" then
            bonus = math.floor(amount * settlementPct / 100)
            self.inventory[ore] = (self.inventory[ore] or 0) + amount + bonus
            if ore ~= "MissionRewardOre" and amount + bonus > 0 then
                settledResources[ore] = amount + bonus
                adBonusEligibleTotal = adBonusEligibleTotal + amount + bonus
            end
        end
        total = total + amount
        resourceBonus = resourceBonus + bonus
    end
    local logarithmicYield = math.log(math.max(1, total) + 1) / math.log(10)
    local depthReward = math.min(6, math.floor(math.max(0, tonumber(context.layer) or 1) / 2))
    local chestReward = math.max(0, math.floor(tonumber(context.chestCores) or 0))
    local coreReward = 2 + math.min(14, math.floor(logarithmicYield * 2)) + depthReward + chestReward
    self.relicCores = math.min(999999, self.relicCores + coreReward)
    local newDensityStars = math.max(0, math.floor(tonumber(context.newDensityStars) or 0))
    local densityStarCount = self:GetDensityStarCount()
    local finalDensityUnlockedNow = context.finalDensityUnlockedNow == true
    self.runs = self.runs + 1
    self:Save()
    return {
        resourceTotal = total,
        resourceBonus = resourceBonus,
        coreReward = coreReward,
        chestReward = chestReward,
        newDensityStars = newDensityStars,
        densityStarCount = densityStarCount,
        finalDensityUnlockedNow = finalDensityUnlockedNow,
        settledResources = settledResources,
        adBonusEligibleTotal = adBonusEligibleTotal,
        adBonus = 0,
    }
end

function State:GrantSettlementAdBonus(settledResources)
    if type(settledResources) ~= "table" then return 0 end
    local addedTotal = 0
    for ore, value in pairs(settledResources) do
        local amount = math.max(0, math.floor(tonumber(value) or 0))
        if amount > 0 and ore ~= "Stardrop" and ore ~= "MissionRewardOre"
            and self.inventory[ore] ~= nil then
            self.inventory[ore] = self.inventory[ore] + amount
            addedTotal = addedTotal + amount
        end
    end
    if addedTotal > 0 then self:Save() end
    return addedTotal
end

function State:IsDensityStarClaimed(density)
    density = math.floor(tonumber(density) or 0)
    return density >= 1 and density <= 10
        and self.missionLayerClaims[tostring(density) .. ":10"] == true
end

function State:GetDensityStarCount()
    return Util.Clamp(math.floor(tonumber(self.inventory.Stardrop) or 0), 0, Config.STARDROPS_FOR_FINAL_DENSITY)
end

function State:IsFinalDensityUnlocked()
    return self:GetDensityStarCount() >= Config.STARDROPS_FOR_FINAL_DENSITY
end

function State:GetWorldTreeLevel(nodeId)
    return WorldTree.GetLevel(self, nodeId)
end

function State:IsWorldTreeAwakened()
    return self.worldTreeAwakened == true
end

function State:RefreshWorldTreeAwakening(saveNow)
    if self.worldTreeAwakened == true or not WorldTree.HasAllCapstones(self) then return false end
    self.worldTreeAwakened = true
    if saveNow ~= false then self:Save() end
    return true
end

function State:CanEnterAbyss()
    return WorldTree.CanEnterAbyss(self)
end

function State:BuyWorldTreeNode(nodeId)
    if not WorldTree.CanBuy(self, nodeId) then return false end
    local cost = WorldTree.GetCost(self, nodeId)
    self.worldTreePoints = math.max(0, self.worldTreePoints - cost)
    self.worldTreeLevels[nodeId] = WorldTree.GetLevel(self, nodeId) + 1
    self:Save()
    return true, cost, self.worldTreeLevels[nodeId]
end

function State:GrantWorldTreePoints(amount, saveMode)
    local added = math.max(0, math.floor(tonumber(amount) or 0))
    if added <= 0 then return 0 end
    self.worldTreePoints = math.min(999999, math.max(0, math.floor(tonumber(self.worldTreePoints) or 0)) + added)
    self.worldTreeLifetimePoints = math.min(9999999,
        math.max(0, math.floor(tonumber(self.worldTreeLifetimePoints) or 0)) + added)
    if saveMode == "local" then self:SaveLocalCheckpoint()
    elseif saveMode ~= false then self:Save() end
    return added
end

function State:GetRelic(id)
    return self.relicData.byId[id]
end

function State:GetRelicBonus(bonusId)
    if self.abyssRulesActive then return 0 end
    local total = 0
    for _, id in ipairs(self.equippedRelics) do
        local relic = self:GetRelic(id)
        total = total + (relic and relic.bonuses and relic.bonuses[bonusId] or 0)
    end
    return total
end

function State:GetEquippedRelics()
    local result = {}
    for _, id in ipairs(self.equippedRelics) do
        local relic = self:GetRelic(id)
        if relic then result[#result + 1] = relic end
    end
    return result
end

function State:IsRelicUnlocked(id)
    return self.unlockedRelics[id] == true
end

function State:IsRelicEquipped(id)
    for _, equippedId in ipairs(self.equippedRelics) do
        if equippedId == id then return true end
    end
    return false
end

function State:IsRelicMapAvailable(relic)
    return relic ~= nil and relic.map <= math.min(10, self.unlockedPrestige)
end

function State:GetRelicUnlockedCount()
    local count = 0
    for _, relic in ipairs(self.relicData.list) do
        if self:IsRelicUnlocked(relic.id) then count = count + 1 end
    end
    return count
end

function State:CanUnlockRelic(id)
    local relic = self:GetRelic(id)
    return relic ~= nil
        and self:IsRelicMapAvailable(relic)
        and self.seenRelics[id] == true
        and not self:IsRelicUnlocked(id)
        and self.relicCores >= relic.cost
end

function State:UnlockRelic(id)
    if not self:CanUnlockRelic(id) then return false end
    local relic = self:GetRelic(id)
    self.relicCores = self.relicCores - relic.cost
    self.unlockedRelics[id] = true
    self.seenRelics[id] = true
    if #self.equippedRelics < 4 then
        self.equippedRelics[#self.equippedRelics + 1] = id
    end
    self:Save()
    return true
end

function State:ToggleRelicEquipped(id)
    if not self:IsRelicUnlocked(id) then return false, "locked" end
    for index, equippedId in ipairs(self.equippedRelics) do
        if equippedId == id then
            table.remove(self.equippedRelics, index)
            self:Save()
            return true, "unequipped"
        end
    end
    if #self.equippedRelics >= 4 then return false, "full" end
    self.equippedRelics[#self.equippedRelics + 1] = id
    self:Save()
    return true, "equipped"
end

function State:MarkRelicSeen(id)
    if not self:GetRelic(id) or self.seenRelics[id] == true then return false end
    self.seenRelics[id] = true
    -- A chest discovery is permanent progression and must survive closing the
    -- game before the current run reaches its settlement screen.
    self:Save()
    return true
end

function State:RollMapRelic(map, excluded)
    map = Util.Clamp(math.floor(tonumber(map) or 1), 1, 10)
    local choices = {}
    for _, relic in ipairs(self.relicData.byMap[map] or {}) do
        if self.seenRelics[relic.id] ~= true and not (excluded and excluded[relic.id]) then
            choices[#choices + 1] = relic.id
        end
    end
    if #choices == 0 then return nil end
    return choices[math.random(1, #choices)]
end

function State:GetLevel(nodeId)
    return self.skillLevels[nodeId] or 0
end

function State:IsNodeBought(nodeId)
    return self:GetLevel(nodeId) > 0
end

function State:HasEffect(effectId)
    for nodeId, level in pairs(self.skillLevels) do
        if level > 0 then
            local node = self.nodeById[nodeId]
            if node and node.effect_id == effectId then
                return true
            end
        end
    end
    return false
end

function State:IsAvailable(node)
    if node.starting then return true end
    if self:GetLevel(node.id) > 0 then return true end
    for _, parentId in ipairs(node.parents or {}) do
        if self:GetLevel(parentId) >= (node.level_to_unlock or 1) then
            return true
        end
    end
    return false
end

-- The original tree reveals one step at a time. A node is visible only after
-- one of its parents has reached the authored unlock level (or after the node
-- itself has already been purchased). Keeping this separate from CanBuy also
-- lets maxed nodes remain visible and inspectable.
function State:IsNodeVisible(node)
    return node ~= nil and self:IsAvailable(node)
end

function State:GetMaxDensity()
    if self:IsFinalDensityUnlocked() then return 11 end
    return math.min(10, self.unlockedPrestige)
end

function State:SetDensity(value)
    local density = Util.Clamp(math.floor(tonumber(value) or 1), 1, self:GetMaxDensity())
    if density == self.prestige then return false end
    self.prestige = density
    self:Save()
    return true
end

function State:GetCost(node)
    local result = {}
    for ore, initial in pairs(node.cost or {}) do
        local value = initial
        local rate = node.cost_growth or 0.2
        if THROUGHPUT_ORES[ore] then rate = rate * 0.5 end
        for _ = 1, self:GetLevel(node.id) do
            value = value + math.max(1, math.floor(value * rate))
        end
        result[ore] = value
    end
    return result
end

function State:CanBuy(node)
    if not node or node.demo_locked or not self:IsAvailable(node) then return false end
    if self:GetLevel(node.id) >= (node.max_level or 0) then return false end
    -- A talent relic is the key for the first level only. Once it has been
    -- embedded into the skill, later authored levels cost resources normally
    -- instead of asking for an impossible duplicate relic.
    if node.is_artefact and self:GetLevel(node.id) == 0 and not self.artefacts[node.id] then return false end
    for ore, amount in pairs(self:GetCost(node)) do
        if (self.inventory[ore] or 0) < amount then return false end
    end
    return true
end

function State:Buy(node)
    if not self:CanBuy(node) then return false end
    local previousLevel = self:GetLevel(node.id)
    local cost = self:GetCost(node)
    for ore, amount in pairs(cost) do
        self.inventory[ore] = math.max(0, (self.inventory[ore] or 0) - amount)
    end
    self.skillLevels[node.id] = self:GetLevel(node.id) + 1
    if self.skillLevels[node.id] == 1 and node.id ~= "UpgradeStart" then
        self.totalUpgrades = self.totalUpgrades + 1
    end
    if node.is_artefact then
        self.discoveredArtefacts[node.id] = true
        if previousLevel == 0 then self.artefacts[node.id] = nil end
    end
    local worldTreeAwakenedNow = self:RefreshWorldTreeAwakening(false)
    self:Save()
    return true, worldTreeAwakenedNow
end

function State:RollRandomArtefact(excluded)
    local choices = {}
    for _, node in ipairs(self.skillData.nodes) do
        if node.is_artefact
            and self:GetLevel(node.id) == 0
            and not self.artefacts[node.id]
            and not self.discoveredArtefacts[node.id]
            and not (excluded and excluded[node.id]) then
            choices[#choices + 1] = node.id
        end
    end
    if #choices == 0 then return nil end
    return choices[math.random(1, #choices)]
end

function State:UnlockArtefact(id)
    local node = self.nodeById[id]
    if not node or not node.is_artefact or self:GetLevel(id) > 0
        or self.artefacts[id] or self.discoveredArtefacts[id] then return false end
    self.artefacts[id] = true
    self.discoveredArtefacts[id] = true
    self:Save()
    return true
end

function State:UnlockRandomArtefact(excluded)
    local id = self:RollRandomArtefact(excluded)
    if not id then return nil end
    return self:UnlockArtefact(id) and id or nil
end

function State:GetArtefactNodeIds()
    local result = {}
    for _, node in ipairs(self.skillData.nodes) do
        if node.is_artefact and self.artefacts[node.id] and self:GetLevel(node.id) == 0 then
            result[#result + 1] = node.id
        end
    end
    return result
end

function State:GetArtefactNodes()
    local result = {}
    for _, node in ipairs(self.skillData.nodes) do
        if node.is_artefact then result[#result + 1] = node end
    end
    return result
end

function State:IsArtefactDiscovered(id)
    return self.discoveredArtefacts[id] == true
        or self.artefacts[id] == true
        or self:GetLevel(id) > 0
end

function State:IsArtefactActive(id)
    local node = self.nodeById[id]
    return node ~= nil and node.is_artefact and self:GetLevel(id) > 0
end

function State:GetArtefactDiscoveredCount()
    local count = 0
    for _, node in ipairs(self:GetArtefactNodes()) do
        if self:IsArtefactDiscovered(node.id) then count = count + 1 end
    end
    return count
end

function State:GetArtefactActiveCount()
    local count = 0
    for _, node in ipairs(self:GetArtefactNodes()) do
        if self:IsArtefactActive(node.id) then count = count + 1 end
    end
    return count
end

function State:GetGeneralStat(statId)
    local base = Config.BaseStats[statId] or 0
    local flat = 0
    local multiplier = 1
    for _, node in ipairs(self.skillData.nodes) do
        local level = self:GetLevel(node.id)
        if level > 0 and node.is_stat and node.upgrade_id == "general_stats" and node.stat_id == statId then
            if node.upgrade_type == 1 then
                multiplier = multiplier * ((1 + node.stat_amount / 100) ^ level)
            else
                flat = flat + node.stat_amount * level
            end
        end
    end
    local result = (base + flat) * multiplier
    if statId == "drill_damage" then
        result = result * (1 + self:GetRelicBonus("drill_damage_pct") / 100)
        if self.worldTreeAwakened then result = result * WorldTree.GetDamageMultiplier(self) end
        if self.abyssRulesActive then
            result = result * (1 + WorldTree.GetStat(self, "abyss_drill_damage_pct") / 100)
            result = result * (1 + AbyssLoot.GetBonus(self, "drill_damage_pct") / 100)
            result = result * (1 + ((self.abyssRunBonuses or {}).drill_damage_pct or 0) / 100)
        end
    elseif statId == "movement_speed" then
        result = result * (1 + self:GetRelicBonus("movement_speed_pct") / 100)
        if self.abyssRulesActive then
            result = result * (1 + WorldTree.GetStat(self, "abyss_move_speed_pct") / 100)
            result = result * (1 + AbyssLoot.GetBonus(self, "move_speed_pct") / 100)
            result = result * (1 + ((self.abyssRunBonuses or {}).move_speed_pct or 0) / 100)
        end
    elseif statId == "fuel_efficiency" then
        result = result * (1 + self:GetRelicBonus("fuel_efficiency_pct") / 100)
        if self.abyssRulesActive then
            result = result * (1 + WorldTree.GetStat(self, "fuel_efficiency_pct") / 100)
        end
    elseif statId == "fuel_amount" then
        result = result * (1 + self:GetRelicBonus("fuel_capacity_pct") / 100)
    elseif statId == "critical_chance" then
        result = result + self:GetRelicBonus("critical_chance_flat")
        if self.abyssRulesActive then
            result = result + WorldTree.GetStat(self, "abyss_critical_chance_flat")
        end
    elseif statId == "critical_damage_multiplier" then
        result = result * (1 + self:GetRelicBonus("critical_damage_pct") / 100)
        if self.abyssRulesActive then
            result = result * (1 + WorldTree.GetStat(self, "abyss_critical_damage_pct") / 100)
        end
    elseif statId == "fuel_regeneration" and self.abyssRulesActive then
        result = result + WorldTree.GetStat(self, "abyss_fuel_regen")
    end
    return result
end

function State:GetActiveStat(upgradeId, statId)
    local baseGroup = Config.ActiveBaseStats[upgradeId] or {}
    local base = baseGroup[statId] or 0
    local flat = 0
    local multiplier = 1
    for _, node in ipairs(self.skillData.nodes) do
        local level = self:GetLevel(node.id)
        if level > 0 and node.is_stat and node.upgrade_id == upgradeId and node.stat_id == statId then
            if node.upgrade_type == 1 then
                multiplier = multiplier * ((1 + node.stat_amount / 100) ^ level)
            else
                flat = flat + node.stat_amount * level
            end
        end
    end
    local result = (base + flat) * multiplier
    if statId == "cooldown" then
        result = result * math.max(0.1, 1 - self:GetRelicBonus("active_cooldown_pct") / 100)
    elseif statId == "radius" or statId == "explosion_radius" then
        result = result * (1 + self:GetRelicBonus("explosion_radius_pct") / 100)
    elseif upgradeId == "overdrive" and statId == "overdrive_strength" then
        result = result * (1 + self:GetRelicBonus("overdrive_strength_pct") / 100)
    end
    return result
end

function State:RegisterLayer(layerIndex)
    layerIndex = Util.Clamp(math.floor(tonumber(layerIndex) or 1), 1, 10)
    self.deepestLayer = math.max(self.deepestLayer, layerIndex)

    local missionReward = 0
    local starDebrisReward = 0
    local starStoneReward = 0
    local firstLayerClaim = false
    local missionKey = tostring(self.prestige) .. ":" .. tostring(layerIndex)
    if self.prestige >= 1 and self.prestige <= 10 and self.missionLayerClaims[missionKey] ~= true then
        self.missionLayerClaims[missionKey] = true
        firstLayerClaim = true
        missionReward = Config.MISSION_BADGES_PER_LAYER
        self.inventory.MissionRewardOre = (self.inventory.MissionRewardOre or 0) + missionReward
        local milestoneReward = Config.STAR_DEBRIS_MILESTONES[layerIndex] or 0
        if milestoneReward > 0 and self.starDebrisMilestoneClaims[missionKey] ~= true then
            self.starDebrisMilestoneClaims[missionKey] = true
            starDebrisReward = milestoneReward
            self.inventory.StarDebris = (self.inventory.StarDebris or 0) + starDebrisReward
        end
    end

    -- Ultimate density remains replayable progression: reaching its tenth
    -- layer once per run grants exactly one StarStone, without resource-gain
    -- multipliers. Abyss tower floors use separate rewards and are excluded.
    if self.prestige == 11 and self.abyssRulesActive ~= true and layerIndex == 10
        and self.runFinalDensityStarStoneClaimed ~= true then
        self.runFinalDensityStarStoneClaimed = true
        starStoneReward = 1
        self.runInventory.StarStone = (self.runInventory.StarStone or 0) + starStoneReward
    end

    local unlockedDensity = nil
    if self.prestige == self.unlockedPrestige and layerIndex > self.unlockedPrestige then
        self.unlockedPrestige = math.min(10, self.unlockedPrestige + 1)
        unlockedDensity = self.unlockedPrestige
    end
    if missionReward > 0 or unlockedDensity then self:Save() end
    return unlockedDensity, missionReward, firstLayerClaim, starDebrisReward, starStoneReward
end

function State:Serialize()
    local persisted = self._testOriginalProgress or self
    return {
        version = SAVE_VERSION,
        cosmetics = Cosmetics.Normalize(self.cosmetics),
        saveRevision = self.saveRevision,
        inventory = persisted.inventory,
        skillLevels = persisted.skillLevels,
        artefacts = persisted.artefacts,
        discoveredArtefacts = persisted.discoveredArtefacts,
        relicCores = self.relicCores,
        unlockedRelics = self.unlockedRelics,
        seenRelics = self.seenRelics,
        equippedRelics = self.equippedRelics,
        missionLayerClaims = persisted.missionLayerClaims,
        starDebrisMilestoneClaims = self.starDebrisMilestoneClaims,
        progressionRecoveryVersion = self.progressionRecoveryVersion,
        goldenDrillCharges = self.goldenDrillCharges,
        supportStarStoneClaimed = self.supportStarStoneClaimed == true,
        worldTreeAwakened = persisted.worldTreeAwakened,
        worldTreePoints = persisted.worldTreePoints,
        worldTreeLifetimePoints = persisted.worldTreeLifetimePoints,
        worldTreeLevels = persisted.worldTreeLevels,
        testWorldTreeResetVersion = persisted.testWorldTreeResetVersion,
        bestAbyssTime = self.bestAbyssTime,
        bestAbyssFloor = self.bestAbyssFloor,
        bestAbyssS2Floor = self.bestAbyssS2Floor or 0,
        abyssCallsign = self.abyssCallsign or "",
        bestAbyssS2HardcoreFloor = self.bestAbyssS2HardcoreFloor or 0,
        bestAbyssHardcoreFloor = self.bestAbyssHardcoreFloor,
        abyssRuns = self.abyssRuns,
        abyssEquipment = self.abyssEquipment,
        abyssEquipmentStorage = self.abyssEquipmentStorage,
        nextAbyssEquipmentUid = self.nextAbyssEquipmentUid,
        abyssLootCounts = self.abyssLootCounts,
        abyssDiscoveredEquipment = self.abyssDiscoveredEquipment,
        abyssDust = self.abyssDust,
        prestige = persisted.prestige,
        unlockedPrestige = persisted.unlockedPrestige,
        totalUpgrades = persisted.totalUpgrades,
        runs = self.runs,
        deepestLayer = persisted.deepestLayer,
        muted = self.muted,
        drillSoundEnabled = self.drillSoundEnabled ~= false,
        toastEnabled = self.toastEnabled ~= false,
        screenShakeEnabled = self.screenShakeEnabled ~= false,
        mobileControlLayout = MobileControlLayout.Normalize(self.mobileControlLayout),
    }
end

function State:ApplySave(data)
    if type(data) ~= "table" then return false end
    local oldCosmetics = self.cosmetics
    self.cosmetics = type(data.cosmetics) == "table"
        and Cosmetics.MergeOwnership(data.cosmetics, oldCosmetics)
        or Cosmetics.Normalize(oldCosmetics)
    self._testOriginalProgress = nil
    local savedUnlockedPrestige = Util.Clamp(math.floor(tonumber(data.unlockedPrestige) or 1), 1, 11)
    local savedDeepestLayer = math.max(0, math.floor(tonumber(data.deepestLayer) or 0))
    self.loadedSaveVersion = math.max(0, math.floor(tonumber(data.version) or 0))
    self.saveRevision = math.max(0, math.floor(tonumber(data.saveRevision) or 0))
    if type(data.inventory) == "table" then
        for ore in pairs(self.inventory) do
            self.inventory[ore] = math.max(0, tonumber(data.inventory[ore]) or 0)
        end
    end
    if type(data.skillLevels) == "table" then
        self.skillLevels = { UpgradeStart = 1 }
        for id, level in pairs(data.skillLevels) do
            if self.nodeById[id] then
                self.skillLevels[id] = math.max(0, math.floor(tonumber(level) or 0))
            end
        end
    end
    self.artefacts = {}
    self.discoveredArtefacts = {}
    if type(data.discoveredArtefacts) == "table" then
        for id, discovered in pairs(data.discoveredArtefacts) do
            local node = self.nodeById[id]
            if discovered == true and node and node.is_artefact then
                self.discoveredArtefacts[id] = true
            end
        end
    end
    if type(data.artefacts) == "table" then
        for id, unlocked in pairs(data.artefacts) do
            local node = self.nodeById[id]
            if unlocked == true and node and node.is_artefact and self:GetLevel(id) == 0 then
                self.artefacts[id] = true
                self.discoveredArtefacts[id] = true
            end
        end
    end
    -- Save versions before v8 had no permanent talent-relic codex. Purchased
    -- nodes had already consumed the held relic, so rebuild their discovery
    -- history from skill levels during migration.
    for _, node in ipairs(self.skillData.nodes) do
        if node.is_artefact and self:GetLevel(node.id) > 0 then
            self.discoveredArtefacts[node.id] = true
        end
    end
    self.relicCores = Util.Clamp(math.floor(tonumber(data.relicCores) or 0), 0, 999999)
    self.unlockedRelics = {}
    self.seenRelics = {}
    if type(data.unlockedRelics) == "table" then
        for id, unlocked in pairs(data.unlockedRelics) do
            if unlocked == true and self:GetRelic(id) then
                self.unlockedRelics[id] = true
                self.seenRelics[id] = true
            end
        end
    end
    if type(data.seenRelics) == "table" then
        for id, seen in pairs(data.seenRelics) do
            if seen == true and self:GetRelic(id) then self.seenRelics[id] = true end
        end
    end
    self.equippedRelics = {}
    local equippedSeen = {}
    if type(data.equippedRelics) == "table" then
        for _, id in ipairs(data.equippedRelics) do
            if #self.equippedRelics >= 4 then break end
            if self:IsRelicUnlocked(id) and not equippedSeen[id] then
                equippedSeen[id] = true
                self.equippedRelics[#self.equippedRelics + 1] = id
            end
        end
    end
    self.missionLayerClaims = {}
    self.starDebrisMilestoneClaims = {}
    if type(data.starDebrisMilestoneClaims) == "table" then
        for key, claimed in pairs(data.starDebrisMilestoneClaims) do
            if claimed == true then self.starDebrisMilestoneClaims[tostring(key)] = true end
        end
    end
    if type(data.missionLayerClaims) == "table" then
        for key, claimed in pairs(data.missionLayerClaims) do
            local densityText, layerText = tostring(key):match("^(%d+):(%d+)$")
            local density, layer = tonumber(densityText), tonumber(layerText)
            if claimed == true and density and density >= 1 and density <= 10
                and layer and layer >= 1 and layer <= 10 then
                self.missionLayerClaims[tostring(density) .. ":" .. tostring(layer)] = true
            end
        end
    end
    -- Version 6 and older stored first-clear stars separately. Convert those
    -- claims into the existing layer-10 mission keys, then keep the larger of
    -- the old progress and the already mirrored Stardrop inventory count.
    if type(data.densityStars) == "table" then
        for density = 1, 10 do
            if data.densityStars[tostring(density)] == true or data.densityStars[density] == true then
                self.missionLayerClaims[tostring(density) .. ":10"] = true
            end
        end
    end
    local recoveredStarDebris = 0
    for key, claimed in pairs(self.missionLayerClaims) do
        local layer = tonumber(tostring(key):match(":(%d+)$"))
        local reward = layer and Config.STAR_DEBRIS_MILESTONES[layer] or 0
        if claimed == true and reward > 0 and self.starDebrisMilestoneClaims[key] ~= true then
            self.starDebrisMilestoneClaims[key] = true
            self.inventory.StarDebris = (self.inventory.StarDebris or 0) + reward
            recoveredStarDebris = recoveredStarDebris + reward
        end
    end
    local firstClearCount = 0
    for density = 1, 10 do
        if self.missionLayerClaims[tostring(density) .. ":10"] == true then
            firstClearCount = firstClearCount + 1
        end
    end
    local migratedStars = math.max(self:GetDensityStarCount(), firstClearCount)
    if data.finalDensityUnlocked == true then migratedStars = Config.STARDROPS_FOR_FINAL_DENSITY end
    self.inventory.Stardrop = Util.Clamp(migratedStars, 0, Config.STARDROPS_FOR_FINAL_DENSITY)
    self.goldenDrillCharges = Util.Clamp(math.floor(tonumber(data.goldenDrillCharges) or 0), 0, 9999)
    -- The support reward is irreversible. Preserve an already-claimed local
    -- entitlement even if an older/newer cloud snapshot does not contain it.
    self.supportStarStoneClaimed = self.supportStarStoneClaimed == true
        or data.supportStarStoneClaimed == true
    self.worldTreeAwakened = data.worldTreeAwakened == true
    self.testWorldTreeResetVersion = math.max(0,
        math.floor(tonumber(data.testWorldTreeResetVersion) or 0))
    self.worldTreePoints = Util.Clamp(math.floor(tonumber(data.worldTreePoints) or 0), 0, 999999)
    self.worldTreeLifetimePoints = Util.Clamp(math.floor(tonumber(data.worldTreeLifetimePoints) or 0), 0, 9999999)
    self.worldTreeLevels = {}
    if type(data.worldTreeLevels) == "table" then
        for nodeId, level in pairs(data.worldTreeLevels) do
            local node = WorldTree.NODE_BY_ID[nodeId]
            if node then
                self.worldTreeLevels[nodeId] = Util.Clamp(math.floor(tonumber(level) or 0), 0, node.maxLevel)
            end
            local migratedId = self.loadedSaveVersion < 17
                and WorldTree.LEGACY_ITEM_NODE_MIGRATIONS[nodeId] or nil
            local migratedNode = migratedId and WorldTree.NODE_BY_ID[migratedId] or nil
            if migratedNode then
                self.worldTreeLevels[migratedId] = math.max(
                    self.worldTreeLevels[migratedId] or 0,
                    Util.Clamp(math.floor(tonumber(level) or 0), 0, migratedNode.maxLevel))
            end
        end
    end
    self.bestAbyssTime = math.max(0, tonumber(data.bestAbyssTime) or 0)
    self.bestAbyssFloor = math.max(0, math.floor(tonumber(data.bestAbyssFloor) or 0))
    self.bestAbyssS2Floor = math.max(0, math.floor(tonumber(data.bestAbyssS2Floor) or 0))
    self.abyssCallsign = require("diggin.AbyssIdentity").Clean(data.abyssCallsign)
    self.bestAbyssS2HardcoreFloor = math.max(0, math.floor(tonumber(data.bestAbyssS2HardcoreFloor) or 0))
    self.bestAbyssHardcoreFloor = math.max(0,
        math.floor(tonumber(data.bestAbyssHardcoreFloor) or 0))
    self.abyssRuns = math.max(0, math.floor(tonumber(data.abyssRuns) or 0))
    self.abyssEquipment = {}
    if type(data.abyssEquipment) == "table" then
        for _, slot in ipairs(AbyssLoot.SLOTS) do
            local entry = AbyssLoot.NormalizeEquipmentEntry(data.abyssEquipment[slot.id], slot.id)
            if entry then self.abyssEquipment[slot.id] = entry end
        end
    end
    self.abyssEquipmentStorage = {}
    self.nextAbyssEquipmentUid = math.max(1, math.floor(tonumber(data.nextAbyssEquipmentUid) or 1))
    local seenEquipmentUids = {}
    if type(data.abyssEquipmentStorage) == "table" then
        local capacity = math.max(1, math.floor(tonumber(Config.Abyss.equipmentStorageCapacity) or 60))
        for _, value in ipairs(data.abyssEquipmentStorage) do
            if #self.abyssEquipmentStorage >= capacity then break end
            local slotId = type(value) == "table" and value.slot or nil
            local entry = slotId and AbyssLoot.NormalizeEquipmentEntry(value, slotId) or nil
            if entry then
                local uid = math.max(1, math.floor(tonumber(entry.uid) or self.nextAbyssEquipmentUid))
                while seenEquipmentUids[uid] do uid = uid + 1 end
                entry.uid, seenEquipmentUids[uid] = uid, true
                self.nextAbyssEquipmentUid = math.max(self.nextAbyssEquipmentUid, uid + 1)
                self.abyssEquipmentStorage[#self.abyssEquipmentStorage + 1] = entry
            end
        end
    end
    self.abyssLootCounts = {}
    if type(data.abyssLootCounts) == "table" then
        for _, grade in ipairs(AbyssLoot.GRADES) do
            local amount = math.max(0, math.floor(tonumber(data.abyssLootCounts[grade.id]) or 0))
            if amount > 0 then self.abyssLootCounts[grade.id] = math.min(999999, amount) end
        end
    end
    self.abyssDiscoveredEquipment = {}
    if type(data.abyssDiscoveredEquipment) == "table" then
        for itemId, discovered in pairs(data.abyssDiscoveredEquipment) do
            if discovered == true and AbyssLoot.GetArchetype(itemId) then
                self.abyssDiscoveredEquipment[itemId] = true
            end
        end
    end
    for _, slot in ipairs(AbyssLoot.SLOTS) do
        local equipped = AbyssLoot.GetEquippedItem(self, slot.id)
        if equipped and equipped.archetypeId then self.abyssDiscoveredEquipment[equipped.archetypeId] = true end
    end
    for _, stored in ipairs(self.abyssEquipmentStorage or {}) do
        if stored.archetypeId then self.abyssDiscoveredEquipment[stored.archetypeId] = true end
    end
    self.abyssDust = Util.Clamp(math.floor(tonumber(data.abyssDust) or 0), 0, 9999999)
    self:RefreshWorldTreeAwakening(false)
    self.prestige = Util.Clamp(math.floor(tonumber(data.prestige) or 1), 1, 11)
    self.unlockedPrestige = savedUnlockedPrestige
    self.totalUpgrades = math.max(0, math.floor(tonumber(data.totalUpgrades) or 0))
    self.runs = math.max(0, math.floor(tonumber(data.runs) or 0))
    self.deepestLayer = savedDeepestLayer
    self.progressionRecoveryVersion = math.max(0, math.floor(tonumber(data.progressionRecoveryVersion) or 0))
    local recoveredBadges = 0
    if self.progressionRecoveryVersion < 1 then
        -- Saves from before mission resources existed cannot reconstruct how
        -- many upgrade costs were already paid. Give a bounded catch-up grant
        -- from irreversible density/depth progress, then mark it one-time.
        recoveredBadges = math.max(0, (math.min(10, savedUnlockedPrestige) - 1) * 50
            + math.min(10, savedDeepestLayer) * 5)
        local legacyStarDebris = math.max(0, (math.min(10, savedUnlockedPrestige) - 1) * 2)
        self.inventory.MissionRewardOre = (self.inventory.MissionRewardOre or 0) + recoveredBadges
        self.inventory.StarDebris = (self.inventory.StarDebris or 0) + legacyStarDebris
        recoveredStarDebris = recoveredStarDebris + legacyStarDebris
        self.progressionRecoveryVersion = 1
    end
    if self.progressionRecoveryVersion < 2 then
        local badgeDelta = math.max(0,
            Config.MISSION_BADGES_PER_LAYER - Config.LEGACY_MISSION_BADGES_PER_LAYER)
        local claimedLayers = 0
        for _, claimed in pairs(self.missionLayerClaims) do
            if claimed == true then claimedLayers = claimedLayers + 1 end
        end
        local badgeBackfill = claimedLayers * badgeDelta
        self.inventory.MissionRewardOre = (self.inventory.MissionRewardOre or 0) + badgeBackfill
        recoveredBadges = recoveredBadges + badgeBackfill
        self.progressionRecoveryVersion = 2
    end
    if recoveredBadges > 0 or recoveredStarDebris > 0 then
        self.progressionRecoveryGrant = { badges = recoveredBadges, starDebris = recoveredStarDebris }
    else
        self.progressionRecoveryGrant = nil
    end
    self.muted = data.muted == true
    self.drillSoundEnabled = data.drillSoundEnabled ~= false
    self.toastEnabled = data.toastEnabled ~= false
    self.screenShakeEnabled = data.screenShakeEnabled ~= false
    self.mobileControlLayout = MobileControlLayout.Normalize(data.mobileControlLayout)
    self:ApplyTestBuildUnlocks()
    return true
end

function State:LoadLocal()
    if not fileSystem:FileExists(SAVE_FILE) then return false end
    local file = File(SAVE_FILE, FILE_READ)
    if not file:IsOpen() then return false end
    local raw = file:ReadString()
    file:Close()
    local ok, data = pcall(cjson.decode, raw)
    if not ok then return false end
    local applied = self:ApplySave(data)
    if applied and (self.loadedSaveVersion < SAVE_VERSION or self.progressionRecoveryGrant ~= nil) then
        -- Persist one-time migrations without incrementing the revision. A
        -- same-revision legacy cloud snapshot is still merged afterwards.
        self:SaveLocal(self:Serialize())
        self.loadedSaveVersion = SAVE_VERSION
    end
    return applied
end

function State:SaveLocal(snapshot)
    local file = File(SAVE_FILE, FILE_WRITE)
    if not file:IsOpen() then return false end
    file:WriteString(cjson.encode(snapshot or self:Serialize()))
    file:Close()
    return true
end

function State:SaveLocalCheckpoint()
    self.saveRevision = (self.saveRevision or 0) + 1
    self.loadedSaveVersion = SAVE_VERSION
    -- Test harnesses do not expose the engine File constructor.  The in-memory
    -- checkpoint is still valid there; production always has File available.
    if File == nil then return false end
    return self:SaveLocal(self:Serialize())
end

function State:MergeLegacySave(data)
    if type(data) ~= "table" then return end
    self.cosmetics = Cosmetics.MergeOwnership(self.cosmetics, data.cosmetics)
    local mergedLegacyBadgeClaims = 0
    local mergedRecoveryVersion = math.max(0,
        math.floor(tonumber(data.progressionRecoveryVersion) or 0))
    if type(data.inventory) == "table" then
        for ore in pairs(self.inventory) do
            self.inventory[ore] = math.max(self.inventory[ore] or 0, tonumber(data.inventory[ore]) or 0)
        end
    end
    if type(data.skillLevels) == "table" then
        for id, level in pairs(data.skillLevels) do
            if self.nodeById[id] then
                self.skillLevels[id] = math.max(self:GetLevel(id), math.floor(tonumber(level) or 0))
            end
        end
    end
    if type(data.artefacts) == "table" then
        for id, unlocked in pairs(data.artefacts) do
            local node = self.nodeById[id]
            if unlocked == true and node and node.is_artefact and self:GetLevel(id) == 0 then
                self.artefacts[id] = true
                self.discoveredArtefacts[id] = true
            end
        end
    end
    if type(data.discoveredArtefacts) == "table" then
        for id, discovered in pairs(data.discoveredArtefacts) do
            local node = self.nodeById[id]
            if discovered == true and node and node.is_artefact then
                self.discoveredArtefacts[id] = true
            end
        end
    end
    for _, node in ipairs(self.skillData.nodes) do
        if node.is_artefact and self:GetLevel(node.id) > 0 then
            self.discoveredArtefacts[node.id] = true
        end
    end
    self.relicCores = Util.Clamp(math.max(self.relicCores, math.floor(tonumber(data.relicCores) or 0)), 0, 999999)
    for _, field in ipairs({ "unlockedRelics", "seenRelics" }) do
        if type(data[field]) == "table" then
            for id, value in pairs(data[field]) do
                if value == true and self:GetRelic(id) then self[field][id] = true end
            end
        end
    end
    if #self.equippedRelics == 0 and type(data.equippedRelics) == "table" then
        local seen = {}
        for _, id in ipairs(data.equippedRelics) do
            if #self.equippedRelics >= 4 then break end
            if self:IsRelicUnlocked(id) and not seen[id] then
                seen[id] = true
                self.equippedRelics[#self.equippedRelics + 1] = id
            end
        end
    end
    if type(data.missionLayerClaims) == "table" then
        for key, claimed in pairs(data.missionLayerClaims) do
            local densityText, layerText = tostring(key):match("^(%d+):(%d+)$")
            local density, layer = tonumber(densityText), tonumber(layerText)
            if claimed == true and density and density >= 1 and density <= 10
                and layer and layer >= 1 and layer <= 10 then
                local normalizedKey = tostring(density) .. ":" .. tostring(layer)
                if self.missionLayerClaims[normalizedKey] ~= true and mergedRecoveryVersion < 2 then
                    mergedLegacyBadgeClaims = mergedLegacyBadgeClaims + 1
                end
                self.missionLayerClaims[normalizedKey] = true
            end
        end
    end
    if type(data.starDebrisMilestoneClaims) == "table" then
        for key, claimed in pairs(data.starDebrisMilestoneClaims) do
            if claimed == true then self.starDebrisMilestoneClaims[tostring(key)] = true end
        end
    end
    if type(data.densityStars) == "table" then
        for density = 1, 10 do
            if data.densityStars[tostring(density)] == true or data.densityStars[density] == true then
                local normalizedKey = tostring(density) .. ":10"
                if self.missionLayerClaims[normalizedKey] ~= true and mergedRecoveryVersion < 2 then
                    mergedLegacyBadgeClaims = mergedLegacyBadgeClaims + 1
                end
                self.missionLayerClaims[normalizedKey] = true
            end
        end
    end
    for key, claimed in pairs(self.missionLayerClaims) do
        local layer = tonumber(tostring(key):match(":(%d+)$"))
        local reward = layer and Config.STAR_DEBRIS_MILESTONES[layer] or 0
        if claimed == true and reward > 0 and self.starDebrisMilestoneClaims[key] ~= true then
            self.starDebrisMilestoneClaims[key] = true
            self.inventory.StarDebris = (self.inventory.StarDebris or 0) + reward
        end
    end
    if mergedLegacyBadgeClaims > 0 then
        local badgeDelta = math.max(0,
            Config.MISSION_BADGES_PER_LAYER - Config.LEGACY_MISSION_BADGES_PER_LAYER)
        local badgeBackfill = mergedLegacyBadgeClaims * badgeDelta
        self.inventory.MissionRewardOre = (self.inventory.MissionRewardOre or 0) + badgeBackfill
        local existingGrant = self.progressionRecoveryGrant or { badges = 0, starDebris = 0 }
        existingGrant.badges = (existingGrant.badges or 0) + badgeBackfill
        self.progressionRecoveryGrant = existingGrant
    end
    self.progressionRecoveryVersion = math.max(self.progressionRecoveryVersion or 0, mergedRecoveryVersion)
    local firstClearCount = 0
    for density = 1, 10 do
        if self.missionLayerClaims[tostring(density) .. ":10"] == true then
            firstClearCount = firstClearCount + 1
        end
    end
    local mergedStars = math.max(self:GetDensityStarCount(), firstClearCount)
    if data.finalDensityUnlocked == true then mergedStars = Config.STARDROPS_FOR_FINAL_DENSITY end
    self.inventory.Stardrop = Util.Clamp(mergedStars, 0, Config.STARDROPS_FOR_FINAL_DENSITY)
    self.goldenDrillCharges = Util.Clamp(math.max(self.goldenDrillCharges, math.floor(tonumber(data.goldenDrillCharges) or 0)), 0, 9999)
    self.supportStarStoneClaimed = self.supportStarStoneClaimed == true
        or data.supportStarStoneClaimed == true
    self.worldTreeAwakened = self.worldTreeAwakened == true or data.worldTreeAwakened == true
    local incomingResetVersion = math.max(0,
        math.floor(tonumber(data.testWorldTreeResetVersion) or 0))
    local currentResetVersion = math.max(0,
        math.floor(tonumber(self.testWorldTreeResetVersion) or 0))
    -- A pre-reset cloud snapshot may still contain the old test build's 999
    -- points and 100 maxed nodes.  Never merge that obsolete allocation back
    -- into a save that already carries the current reset marker.
    if incomingResetVersion >= currentResetVersion then
        self.worldTreePoints = Util.Clamp(math.max(self.worldTreePoints or 0,
            math.floor(tonumber(data.worldTreePoints) or 0)), 0, 999999)
        self.worldTreeLifetimePoints = Util.Clamp(math.max(self.worldTreeLifetimePoints or 0,
            math.floor(tonumber(data.worldTreeLifetimePoints) or 0)), 0, 9999999)
        if type(data.worldTreeLevels) == "table" then
            for nodeId, level in pairs(data.worldTreeLevels) do
                local node = WorldTree.NODE_BY_ID[nodeId]
                if node then
                    self.worldTreeLevels[nodeId] = Util.Clamp(math.max(WorldTree.GetLevel(self, nodeId),
                        math.floor(tonumber(level) or 0)), 0, node.maxLevel)
                end
                local migratedId = math.floor(tonumber(data.version) or 0) < 17
                    and WorldTree.LEGACY_ITEM_NODE_MIGRATIONS[nodeId] or nil
                local migratedNode = migratedId and WorldTree.NODE_BY_ID[migratedId] or nil
                if migratedNode then
                    self.worldTreeLevels[migratedId] = Util.Clamp(math.max(
                        WorldTree.GetLevel(self, migratedId), math.floor(tonumber(level) or 0)),
                        0, migratedNode.maxLevel)
                end
            end
        end
    end
    self.testWorldTreeResetVersion = math.max(currentResetVersion, incomingResetVersion)
    self.bestAbyssTime = math.max(self.bestAbyssTime or 0, tonumber(data.bestAbyssTime) or 0)
    self.bestAbyssS2Floor = math.max(self.bestAbyssS2Floor or 0, math.floor(tonumber(data.bestAbyssS2Floor) or 0))
    self.bestAbyssS2HardcoreFloor = math.max(self.bestAbyssS2HardcoreFloor or 0,
        math.floor(tonumber(data.bestAbyssS2HardcoreFloor) or 0))
    self.bestAbyssFloor = math.max(self.bestAbyssFloor or 0,
        math.floor(tonumber(data.bestAbyssFloor) or 0))
    self.bestAbyssHardcoreFloor = math.max(self.bestAbyssHardcoreFloor or 0,
        math.floor(tonumber(data.bestAbyssHardcoreFloor) or 0))
    self.abyssRuns = math.max(self.abyssRuns or 0, math.floor(tonumber(data.abyssRuns) or 0))
    if type(data.abyssEquipment) == "table" then
        for _, slot in ipairs(AbyssLoot.SLOTS) do
            local incomingEntry = AbyssLoot.NormalizeEquipmentEntry(data.abyssEquipment[slot.id], slot.id)
            local incoming = AbyssLoot.GetGrade(incomingEntry)
            local current = AbyssLoot.GetGrade((self.abyssEquipment or {})[slot.id])
            local currentEntry = AbyssLoot.GetEquippedItem(self, slot.id)
            if incoming and (not current or incoming.index > current.index
                or (incoming.index == current.index and (incomingEntry.forgeLevel or 0) > (currentEntry and currentEntry.forgeLevel or 0))) then
                self.abyssEquipment[slot.id] = incomingEntry
            end
        end
    end
    self.abyssEquipmentStorage = self.abyssEquipmentStorage or {}
    self.nextAbyssEquipmentUid = math.max(1, math.floor(tonumber(self.nextAbyssEquipmentUid) or 1))
    if type(data.abyssEquipmentStorage) == "table" then
        local capacity = math.max(1, math.floor(tonumber(Config.Abyss.equipmentStorageCapacity) or 60))
        local seen = {}
        for _, item in ipairs(self.abyssEquipmentStorage) do seen[math.floor(tonumber(item.uid) or 0)] = true end
        for _, value in ipairs(data.abyssEquipmentStorage) do
            if #self.abyssEquipmentStorage >= capacity then break end
            local slotId = type(value) == "table" and value.slot or nil
            local entry = slotId and AbyssLoot.NormalizeEquipmentEntry(value, slotId) or nil
            if entry then
                local uid = math.max(1, math.floor(tonumber(entry.uid) or 0))
                if uid == 1 and seen[uid] then uid = self.nextAbyssEquipmentUid end
                while seen[uid] do uid = uid + 1 end
                entry.uid, seen[uid] = uid, true
                self.nextAbyssEquipmentUid = math.max(self.nextAbyssEquipmentUid, uid + 1)
                self.abyssEquipmentStorage[#self.abyssEquipmentStorage + 1] = entry
            end
        end
    end
    if type(data.abyssLootCounts) == "table" then
        for _, grade in ipairs(AbyssLoot.GRADES) do
            self.abyssLootCounts[grade.id] = math.max(
                math.floor(tonumber(self.abyssLootCounts[grade.id]) or 0),
                math.floor(tonumber(data.abyssLootCounts[grade.id]) or 0))
        end
    end
    self.abyssDiscoveredEquipment = self.abyssDiscoveredEquipment or {}
    if type(data.abyssDiscoveredEquipment) == "table" then
        for itemId, discovered in pairs(data.abyssDiscoveredEquipment) do
            if discovered == true and AbyssLoot.GetArchetype(itemId) then
                self.abyssDiscoveredEquipment[itemId] = true
            end
        end
    end
    self.abyssDust = math.max(self.abyssDust or 0, math.floor(tonumber(data.abyssDust) or 0))
    self:RefreshWorldTreeAwakening(false)
    self.unlockedPrestige = Util.Clamp(math.max(self.unlockedPrestige, math.floor(tonumber(data.unlockedPrestige) or 1)), 1, 11)
    self.prestige = Util.Clamp(self.prestige, 1, self.unlockedPrestige)
    self.totalUpgrades = math.max(self.totalUpgrades, math.floor(tonumber(data.totalUpgrades) or 0))
    self.runs = math.max(self.runs, math.floor(tonumber(data.runs) or 0))
    self.deepestLayer = math.max(self.deepestLayer, math.floor(tonumber(data.deepestLayer) or 0))
end

function State:LoadCloud(onDone)
    if not clientCloud or not clientCloud.Get then
        self.cloudError = "unavailable"
        if onDone then onDone(false) end
        return
    end
    -- The player can start and even finish a short run before the asynchronous
    -- startup read returns. Remember the revision that the request started
    -- from so a newer-looking cloud snapshot cannot erase progress saved while
    -- that request was in flight.
    local requestRevision = math.max(0, math.floor(tonumber(self.saveRevision) or 0))
    clientCloud:Get(CLOUD_KEY, {
        ok = function(values)
            local cloudSave = values and values[CLOUD_KEY]
            if type(cloudSave) == "table" then
                local cloudRevision = math.max(0, math.floor(tonumber(cloudSave.saveRevision) or 0))
                local localRevision = self.saveRevision or 0
                if cloudRevision > localRevision then
                    if localRevision ~= requestRevision then
                        -- A floor checkpoint or settlement completed after the
                        -- read began. Merge monotonic/unlocked progress and
                        -- publish a revision newer than both snapshots instead
                        -- of applying the cloud payload wholesale.
                        self:MergeLegacySave(cloudSave)
                        self.saveRevision = math.max(localRevision, cloudRevision)
                        self:Save()
                    else
                        self:ApplySave(cloudSave)
                        self:SaveLocal(self:Serialize())
                    end
                elseif cloudRevision < localRevision then
                    self:SaveCloud(self:Serialize())
                elseif self.loadedSaveVersion < SAVE_VERSION or math.floor(tonumber(cloudSave.version) or 0) < SAVE_VERSION then
                    -- Legacy saves had no ordering token. Merge irreversible
                    -- progress instead of letting a stale cloud callback erase
                    -- newly earned stars, skills, or old artefact gates.
                    self:MergeLegacySave(cloudSave)
                    self:Save()
                end
            end
            self.cloudReady = true
            self.cloudError = nil
            if onDone then onDone(true) end
        end,
        error = function(_, reason)
            self.cloudError = tostring(reason or "error")
            if onDone then onDone(false) end
        end,
        timeout = function()
            self.cloudError = "timeout"
            if onDone then onDone(false) end
        end,
    })
end

function State:SaveCloud(snapshot)
    if not clientCloud or not clientCloud.Set then return end
    snapshot = snapshot or self:Serialize()
    if self.cloudSaveInFlight then
        -- Keep only the newest snapshot. Sending concurrent Set requests can
        -- complete out of order and let an older inventory overwrite a star
        -- that was earned moments later.
        self.pendingCloudSnapshot = snapshot
        return
    end

    self.cloudSaveInFlight = true
    local function finishCloudSave(reason)
        self.cloudSaveInFlight = false
        if reason then
            self.cloudError = tostring(reason)
        else
            self.cloudReady = true
            self.cloudError = nil
        end
        local pending = self.pendingCloudSnapshot
        self.pendingCloudSnapshot = nil
        if pending then self:SaveCloud(pending) end
    end
    clientCloud:Set(CLOUD_KEY, snapshot, {
        ok = function() finishCloudSave(nil) end,
        error = function(_, reason) finishCloudSave(reason or "error") end,
        timeout = function() finishCloudSave("timeout") end,
    })
end

function State:Save()
    self.saveRevision = (self.saveRevision or 0) + 1
    self.loadedSaveVersion = SAVE_VERSION
    local snapshot = self:Serialize()
    self:SaveLocal(snapshot)
    self:SaveCloud(snapshot)
end

return State
