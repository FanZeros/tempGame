local Config = require("nightgate.Config")
local Skills = require("nightgate.Skills")
local Equipment = require("nightgate.Equipment")
local Prestige = require("nightgate.Prestige")
local WallData = require("nightgate.OriginalWallData")
local ProjectileSystem = require("nightgate.ProjectileSystem")
local LootSystem = require("nightgate.LootSystem")
local MonsterAffixes = require("nightgate.MonsterAffixes")
local BattleExpansion = require("nightgate.BattleExpansion")
local BattleEffects = require("nightgate.BattleEffects")

local Battle = {}
Battle.__index = Battle

local HERO_SKILL_COLORS = {
    [1] = { 255, 210, 83, 255 },
    [2] = { 143, 119, 255, 255 },
    [3] = { 91, 213, 107, 255 },
    [4] = { 255, 112, 52, 255 },
}

local CURSOR_DAMAGE_COLOR = { 255, 247, 153, 255 }
local CURSOR_CRIT_COLOR = { 255, 194, 55, 255 }

local NIGHT_SUPPLY_NIGHTS = { [5] = true, [10] = true, [15] = true, [20] = true, [25] = true, [30] = true }
local NIGHT_SUPPLY_WALL_BONUS = 30
local DEFEAT_REVIVE_WALL_PERCENT = 35
local DEFEAT_REVIVE_FREEZE_SECONDS = 2.2

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function distance(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

local function weightedChoice(pairs, fallback)
    local total = 0
    for index = 1, #(pairs or {}) do
        total = total + math.max(0, tonumber(pairs[index][2]) or 0)
    end
    if total <= 0 then
        return fallback
    end
    local roll = math.random() * total
    for index = 1, #pairs do
        roll = roll - math.max(0, tonumber(pairs[index][2]) or 0)
        if roll <= 0 then
            return tonumber(pairs[index][1]) or fallback
        end
    end
    return fallback
end

local function copyTable(source)
    local result = {}
    if type(source) == "table" then
        for key, value in pairs(source) do
            if type(value) == "table" then
                result[key] = copyTable(value)
            else
                result[key] = value
            end
        end
    end
    return result
end

local function normalizeSpeedMultiplier(value)
    value = math.floor(tonumber(value) or 1)
    if value == 2 or value == 3 then return value end
    return 1
end

local function normalizeVolume(value)
    return clamp(tonumber(value) or 1, 0, 1)
end

function Battle.New(saveData)
    local self = setmetatable({}, Battle)
    saveData = type(saveData) == "table" and saveData or {}
    local rawPrestigeCount = math.max(0, math.floor(tonumber(saveData.prestigeCount) or 0))
    local legacyPrestige = rawPrestigeCount > 0 and saveData.prestigePoints == nil and saveData.prestigeLevels == nil
    self.gold = saveData.gold or 3
    self.crystals = saveData.crystals or 0
    self.bestNight = saveData.bestNight or 1
    self.nextNight = clamp(saveData.nextNight or 1, 1, #Config.LEVELS)
    self.finalDifficultyUnlocked = clamp(math.floor(tonumber(saveData.finalDifficultyUnlocked) or 0), 0, Config.MAX_FINAL_DIFFICULTY)
    self.finalDifficultySelected = clamp(math.floor(tonumber(saveData.finalDifficultySelected) or 0), 0, Config.MAX_FINAL_DIFFICULTY)
    self.selectedArchers = copyTable(saveData.selectedArchers)
    self.selectedHeroes = copyTable(saveData.selectedHeroes)
    self.skillLevels = copyTable(saveData.skillLevels)
    self.quickDamageLevel = saveData.quickDamageLevel or 0
    self.quickWallLevel = saveData.quickWallLevel or 0
    self.inventory = Equipment.NormalizeInventory(saveData.inventory)
    self.equipment = Equipment.NormalizeEquipped(saveData.equipment)
    self.equipmentShards = math.max(0, math.floor(tonumber(saveData.equipmentShards) or 0))
    self.prestigeCount = rawPrestigeCount
    local milestoneSource = saveData.prestigeMilestone
    if milestoneSource == nil and rawPrestigeCount > 0 then milestoneSource = 10 end
    self.prestigeMilestone = Prestige.GetMilestone(milestoneSource)
    self.prestigePoints = math.max(0, math.floor(tonumber(saveData.prestigePoints) or 0))
    self.prestigePointsTotal = math.max(self.prestigePoints, math.floor(tonumber(saveData.prestigePointsTotal) or self.prestigePoints))
    self.prestigeLevels = copyTable(saveData.prestigeLevels)
    self.economyLevels = copyTable(saveData.economyLevels)
    if legacyPrestige then
        self.prestigeLevels.p_root = math.max(1, Prestige.GetLevel(self.prestigeLevels, "p_root"))
        self.prestigePoints = math.max(self.prestigePoints, 5)
        self.prestigePointsTotal = math.max(self.prestigePointsTotal, 6)
        self.gold = math.max(self.gold, 6)
    end
    self.speedMultiplier = normalizeSpeedMultiplier(saveData.speedMultiplier)
    self.musicVolume = normalizeVolume(saveData.musicVolume)
    self.sfxVolume = normalizeVolume(saveData.sfxVolume)
    self.tutorialCompleted = saveData.tutorialCompleted == true
    self.adSupplyClaimKey = type(saveData.adSupplyClaimKey) == "string" and saveData.adSupplyClaimKey or nil
    self.adSupplyReadyKey = type(saveData.adSupplyReadyKey) == "string" and saveData.adSupplyReadyKey or nil
    self.speed = Config.GAME_TIME_SCALE * self.speedMultiplier
    self.events = {}
    self.dirtySave = false
    self.arena = { x = 210, y = 38, size = 440 }
    self.cursor = { x = 430, y = 270, visible = false, pulse = 0 }
    self.state = "home"
    self.activeMode = "campaign"
    self.finalDifficulty = 0
    self.resultMessage = ""
    self.message = ""
    self.messageTimer = 0
    self.runSequence = 0
    self:ClearTransient()
    return self
end

function Battle:ClearTransient()
    self.enemies = {}
    self.projectiles = {}
    self.particles = {}
    self.rings = {}
    self.skillEffects = {}
    self.coinPickups = {}
    self.floatingText = {}
    self.defenderTimers = { 0.1, 0.25, 0.4, 0.55 }
    self.heroTimers = { 0.35, 0.55, 0.75, 0.95 }
    self.heroShots = { 0, 0, 0, 0 }
    self.cursorTimer = 0.2
    self.randomCursorTimer = 4
    self.wallRegenTimer = 4
    self.equipmentDrops = 0
    self.runDrops = {}
    ---@type number[]
    self.wallFlash = { 0, 0, 0, 0 }
    self.shake = 0
    self.dragonAssistsRemaining = 0
    self.dragonAssistTimer = 0
    self.dragonAssistLife = 0
    self.dragonAssistShotTimer = 0
    self.dragonAssistType = 1
    self.goldGainRemainder = 0
    self.spawnBudget = 0
    self.initialBudget = 0
    self.spawnedDifficulty = 0
    self.spawnTimer = 0
    self.spawnInterval = 1
    self.waveSpawnCounts = {}
    self.crystalRemaining = 0
    self.bossSpawned = false
    self.runStartGold = nil
    self.runStartCrystals = nil
    self.nightGoldEarned = 0
    self.nightGoldAdClaimed = false
    self.nightResultId = nil
    self.nightSupplyActive = false
    self.nightReviveAdUsed = false
    BattleExpansion.Initialize(self)
end

function Battle:SetArena(x, y, size)
    self.arena.x = x
    self.arena.y = y
    self.arena.size = size
    if not self.cursor.visible then
        self.cursor.x = x + size * 0.5
        self.cursor.y = y + size * 0.68
    end
end

function Battle:SetSpeedMultiplier(value)
    local nextValue = normalizeSpeedMultiplier(value)
    if self.speedMultiplier == nextValue then return false end
    self.speedMultiplier = nextValue
    self.speed = Config.GAME_TIME_SCALE * nextValue
    self.message = tostring(nextValue) .. "倍速"
    self.messageTimer = 1.2
    self.dirtySave = true
    return true
end

function Battle:GetSpeedMultiplier()
    return self.speedMultiplier or 1
end

function Battle:SetMusicVolume(value)
    local nextValue = normalizeVolume(value)
    if self.musicVolume == nextValue then return false end
    self.musicVolume = nextValue
    self.dirtySave = true
    return true
end

function Battle:GetMusicVolume()
    return normalizeVolume(self.musicVolume)
end

function Battle:SetSfxVolume(value)
    local nextValue = normalizeVolume(value)
    if self.sfxVolume == nextValue then return false end
    self.sfxVolume = nextValue
    self.dirtySave = true
    return true
end

function Battle:GetSfxVolume()
    return normalizeVolume(self.sfxVolume)
end

function Battle:GetLevelConfig()
    return Config.LEVELS[clamp(self.night or self.nextNight, 1, #Config.LEVELS)]
end

function Battle:GetEnemyCombatStats(archetype, levelConfig)
    levelConfig = levelConfig or self.levelConfig or self:GetLevelConfig()
    local hpScale = 1 + (levelConfig.hp or 0) / 100
    local atkScale = 1 + (levelConfig.atk or 0) / 100
    return {
        hp = math.max(1, math.floor(archetype.hp * hpScale + 0.5)),
        wallDamage = math.max(0, math.floor(archetype.wallDamage * atkScale + 0.5)),
        speed = archetype.speed * self.arena.size / 12 * (1 + (levelConfig.moveSpeed or 0) / 100),
    }
end

function Battle:GetStats()
    return Skills.GetStats(self)
end

function Battle:GetArcherCountForSide(sideIndex, stats)
    sideIndex = clamp(math.floor(tonumber(sideIndex) or 1), 1, 4)
    local total = math.max(0, math.floor((stats or self:GetStats()).archerCount or 0))
    local base = math.floor(total / 4)
    return base + (sideIndex <= total % 4 and 1 or 0)
end

function Battle:GetArcherCountPerSide(sideIndex, stats)
    return self:GetArcherCountForSide(sideIndex, stats)
end

function Battle:IsArcherUnlocked()
    return Skills.IsArcherUnlocked(self.skillLevels)
end

function Battle:GetUnlockedArchers()
    return Skills.GetUnlockedArchers(self.skillLevels)
end

function Battle:GetArcherForSide(sideIndex)
    return Skills.GetArcherForSide(self.skillLevels, self.selectedArchers, sideIndex)
end

function Battle:CycleArcher(sideIndex)
    sideIndex = clamp(math.floor(tonumber(sideIndex) or 1), 1, 4)
    local archers = self:GetUnlockedArchers()
    if #archers == 0 then
        self.message = self:GetRoleUnlockMessage(sideIndex, "captain")
        self.messageTimer = 1.8
        return false
    end
    local current = self:GetArcherForSide(sideIndex)
    local nextIndex = 1
    for index = 1, #archers do
        if current and archers[index].id == current.id then
            nextIndex = index % #archers + 1
            break
        end
    end
    self.selectedArchers[sideIndex] = archers[nextIndex].id
    self.message = "已选择 " .. archers[nextIndex].name
    self.messageTimer = 1.8
    self.dirtySave = true
    return true
end

function Battle:IsFinalNightUnlocked()
    return self.prestigeCount > 0
end

function Battle:CanPrestige()
    if self.bestNight < Config.PRESTIGE_UNLOCK_NIGHT then
        return false, "完成第 " .. tostring(Config.PRESTIGE_UNLOCK_NIGHT) .. " 晚后可转生"
    end
    return true
end

function Battle:ResetProgress(keepPrestige)
    local prestigeCount = keepPrestige and self.prestigeCount or 0
    local prestigeMilestone = keepPrestige and self.prestigeMilestone or 0
    local prestigePoints = keepPrestige and self.prestigePoints or 0
    local prestigePointsTotal = keepPrestige and self.prestigePointsTotal or 0
    local prestigeLevels = keepPrestige and copyTable(self.prestigeLevels) or {}
    local tutorialCompleted = keepPrestige and self.tutorialCompleted == true or false
    self.gold = 3 + (keepPrestige and (3 + Prestige.GetStartingGold(prestigeLevels)) or 0)
    self.crystals = 0
    self.equipmentShards = 0
    self.bestNight = 1
    self.nextNight = 1
    self.finalDifficultyUnlocked = 0
    self.finalDifficultySelected = 0
    self.selectedArchers = {}
    self.selectedHeroes = {}
    self.skillLevels = {}
    self.economyLevels = {}
    self.quickDamageLevel = 0
    self.quickWallLevel = 0
    self.inventory = Equipment.NormalizeInventory(nil)
    self.equipment = Equipment.NormalizeEquipped(nil)
    self.prestigeCount = prestigeCount
    self.prestigeMilestone = prestigeMilestone
    self.prestigePoints = prestigePoints
    self.prestigePointsTotal = prestigePointsTotal
    self.prestigeLevels = prestigeLevels
    self.tutorialCompleted = tutorialCompleted
    self.adSupplyClaimKey = nil
    self.adSupplyReadyKey = nil
    self.speed = Config.GAME_TIME_SCALE * self:GetSpeedMultiplier()
    self.state = "home"
    self.activeMode = "campaign"
    self.finalDifficulty = 0
    self.night = nil
    self.levelConfig = nil
    self.cursor.visible = false
    self:ClearTransient()
    self.dirtySave = true
end

function Battle:StartNewSave()
    self:ResetProgress(false)
    self.resultMessage = "新存档已创建"
    self.message = ""
    self.messageTimer = 0
    return true
end

function Battle:CompleteTutorial()
    if self.tutorialCompleted then return false end
    self.tutorialCompleted = true
    self.dirtySave = true
    return true
end

function Battle:PerformPrestige()
    local canPrestige, reason = self:CanPrestige()
    if not canPrestige then
        return false, reason
    end
    local reward = Prestige.CalculateReward(self.bestNight)
    local previousMilestone = self.prestigeMilestone
    self.prestigeMilestone = math.max(self.prestigeMilestone, Prestige.GetMilestone(self.bestNight))
    self.prestigeCount = self.prestigeCount + 1
    self.prestigePoints = self.prestigePoints + reward
    self.prestigePointsTotal = self.prestigePointsTotal + reward
    self:ResetProgress(true)
    self.resultMessage = "转生成功 · 获得 " .. tostring(reward) .. " 转生点"
    if self.prestigeMilestone > previousMilestone then
        self.resultMessage = self.resultMessage .. " · 解锁第" .. tostring(self.prestigeMilestone) .. "夜祝福"
    end
    self.message = self.resultMessage
    self.messageTimer = 2.5
    self:PushEvent("upgrade")
    return true, self.resultMessage
end

function Battle:GetPrestigeReward()
    return Prestige.CalculateReward(self.bestNight)
end

function Battle:TryPrestigeUpgrade(id)
    local ok, message = Prestige.TryUpgrade(self, id)
    self.message = message
    self.messageTimer = 1.8
    if ok then self:PushEvent("upgrade") end
    return ok, message
end

function Battle:GetUnlockedHeroes()
    return Skills.GetUnlockedHeroes(self.skillLevels)
end

function Battle:GetHeroForSide(sideIndex)
    return Skills.GetHeroForSide(self.skillLevels, self.selectedHeroes, sideIndex)
end

function Battle:IsRoleUnlocked(sideIndex, role)
    if role == "captain" then
        return self:IsArcherUnlocked()
    elseif role == "hero" then
        return self:GetHeroForSide(sideIndex) ~= nil
    end
    return false
end

function Battle:GetRoleUnlockMessage(sideIndex, role)
    if role == "captain" then
        return "需在技能树点亮「召唤弓箭手人数」"
    elseif #self:GetUnlockedHeroes() == 0 then
        return "需先在技能树单独解锁英雄"
    elseif not self:GetHeroForSide(sideIndex) then
        return "点击头像为这面城墙部署英雄"
    end
    return "角色已解锁"
end

function Battle:CycleHero(sideIndex)
    sideIndex = clamp(math.floor(tonumber(sideIndex) or 1), 1, 4)
    local heroes = self:GetUnlockedHeroes()
    if #heroes == 0 then
        self.message = "尚未在技能树中解锁英雄"
        self.messageTimer = 1.8
        return false
    end
    local current = self:GetHeroForSide(sideIndex)
    local nextIndex = 1
    for index = 1, #heroes do
        if current and heroes[index].id == current.id then
            nextIndex = index % #heroes + 1
            break
        end
    end
    self.selectedHeroes[sideIndex] = heroes[nextIndex].id
    self.message = "已选择 " .. heroes[nextIndex].name
    self.messageTimer = 1.8
    self.dirtySave = true
    return true
end

function Battle:GetFinalDifficultyConfig(difficulty)
    difficulty = clamp(math.floor(tonumber(difficulty) or 0), 0, Config.MAX_FINAL_DIFFICULTY)
    return Config.FINAL_NIGHT_DIFFICULTIES[difficulty]
end

function Battle:BuildFinalLevelConfig(difficulty)
    local source = Config.FINAL_NIGHT_LEVEL
    local difficultyConfig = self:GetFinalDifficultyConfig(difficulty)
    local modifiers = difficultyConfig.modifiers or {}
    local level = copyTable(source)
    level.difficulty = level.difficulty + (difficultyConfig.levelDifficultyAdd or 0)
    level.hp = level.hp + (modifiers[79] or 0)
    level.atk = level.atk + (modifiers[80] or 0)
    level.moveSpeed = modifiers[81] or 0
    level.crystal = level.crystal + (modifiers[59] or 0)
    level.settlementGoldBonus = modifiers[64] or 0
    level.settlementCrystalBonus = modifiers[65] or 0
    level.dropRateBonus = modifiers[82] or 0
    level.finalDifficulty = difficultyConfig.difficulty
    return level
end

function Battle:GetNightSupplyKey(night)
    night = clamp(math.floor(tonumber(night) or self.nextNight or 1), 1, Config.CAMPAIGN_NIGHT_COUNT)
    return tostring(math.max(0, math.floor(tonumber(self.prestigeCount) or 0))) .. ":" .. tostring(night)
end

function Battle:IsNightSupplyNight(night)
    night = clamp(math.floor(tonumber(night) or self.nextNight or 1), 1, Config.CAMPAIGN_NIGHT_COUNT)
    return NIGHT_SUPPLY_NIGHTS[night] == true
end

function Battle:IsNightSupplyReady()
    return self.adSupplyReadyKey == self:GetNightSupplyKey(self.nextNight)
end

function Battle:UnlockFinalDifficulty(difficulty)
    difficulty = clamp(math.floor(tonumber(difficulty) or 0), 0, Config.MAX_FINAL_DIFFICULTY)
    if not self:IsFinalNightUnlocked() then
        return false, "最终之夜尚未解锁"
    end
    if difficulty <= self.finalDifficultyUnlocked then
        return true, "已解锁"
    end
    if difficulty ~= self.finalDifficultyUnlocked + 1 then
        return false, "请先解锁上一难度"
    end
    local config = self:GetFinalDifficultyConfig(difficulty)
    if self.gold < config.cost then
        return false, "金币不足"
    end
    self.gold = self.gold - config.cost
    self.finalDifficultyUnlocked = difficulty
    self.finalDifficultySelected = difficulty
    self.dirtySave = true
    return true, "难度 " .. tostring(difficulty) .. " 已解锁"
end

function Battle:BeginLevel(levelConfig, mode)
    self.levelConfig = levelConfig
    self.activeMode = mode or "campaign"
    self.state = "running"
    self.resultMessage = ""
    self:ClearTransient()
    self.runSequence = (self.runSequence or 0) + 1
    self.nightResultId = self.runSequence
    local supplyKey = self:GetNightSupplyKey(self.night)
    if self.activeMode == "campaign" and self.adSupplyReadyKey == supplyKey then
        self.nightSupplyActive = true
        self.adSupplyReadyKey = nil
        self.dirtySave = true
    end
    local stats = self:GetStats()
    local wallMultiplier = self.nightSupplyActive and (1 + NIGHT_SUPPLY_WALL_BONUS / 100) or 1
    self.wallMax = math.max(1, math.floor(stats.wallMax * wallMultiplier + 0.5))
    self.wallHP = self.wallMax
    self.spawnBudget = self.levelConfig.difficulty
    self.initialBudget = self.spawnBudget
    self.spawnedDifficulty = 0
    local earlyPace = self.activeMode == "campaign" and (Config.EARLY_SPAWN_MULTIPLIER[self.night] or 1) or 1
    self.spawnTimer = earlyPace > 1 and 0.7 or 0.25
    self.bossSpawned = false
    self.waveSpawnCounts = {}
    self.crystalRemaining = (self.levelConfig.crystal or 0) + math.floor(stats.extraCrystalMonsters or 0)
    self.dragonAssistsRemaining = math.max(0, math.floor(stats.dragonAssist or 0))
    self.dragonAssistTimer = 3.5 + math.random() * 2.5
    self.dragonAssistLife = 0
    self.dragonAssistShotTimer = 0
    self.runStartGold = self.gold
    self.runStartCrystals = self.crystals
    local averageDifficulty = 0
    local normalCount = 0
    for index = 1, #self.levelConfig.waves do
        local wave = Config.MONSTER_WAVES[self.levelConfig.waves[index]]
        if wave and not wave.boss then
            averageDifficulty = averageDifficulty + wave.difficulty
            normalCount = normalCount + 1
        end
    end
    averageDifficulty = normalCount > 0 and averageDifficulty / normalCount or 1
    local expectedCount = math.max(1, self.levelConfig.difficulty / averageDifficulty)
    self.spawnInterval = math.max(0.08, self.levelConfig.duration / expectedCount) * earlyPace
    self.message = self.activeMode == "final" and ("最终之夜 · 难度 " .. tostring(self.finalDifficulty)) or ("第 " .. tostring(self.night) .. " 晚")
    if self.nightSupplyActive then
        self.message = self.message .. " · 战备城墙 +" .. tostring(NIGHT_SUPPLY_WALL_BONUS) .. "%"
    end
    self.messageTimer = 2.2
    self.cursor.visible = true
    self:PushEvent("wave")
    return true
end

function Battle:StartNight()
    self.night = self.nextNight
    self.finalDifficulty = 0
    return self:BeginLevel(Config.LEVELS[self.night], "campaign")
end

function Battle:StartFinalNight(difficulty)
    difficulty = clamp(math.floor(tonumber(difficulty) or self.finalDifficultySelected or 0), 0, Config.MAX_FINAL_DIFFICULTY)
    if not self:IsFinalNightUnlocked() then
        self.message = "完成一次转生后解锁最终之夜"
        self.messageTimer = 1.8
        return false
    end
    if difficulty > self.finalDifficultyUnlocked then
        self.message = "该难度尚未解锁"
        self.messageTimer = 1.8
        return false
    end
    self.night = Config.CAMPAIGN_NIGHT_COUNT
    self.finalDifficulty = difficulty
    self.finalDifficultySelected = difficulty
    return self:BeginLevel(self:BuildFinalLevelConfig(difficulty), "final")
end

function Battle:ReturnHome()
    if self.state == "running" then
        self.state = "home"
        self.resultMessage = "本轮已暂停"
    end
end

function Battle:DismissResult()
    if self.state == "victory" or self.state == "defeat" then
        self.state = "home"
        self.cursor.visible = false
        return true
    end
    return false
end

function Battle:PushEvent(name)
    if #self.events >= 32 then
        table.remove(self.events, 1)
    end
    self.events[#self.events + 1] = name
end

function Battle:DrainEvents()
    local events = self.events
    self.events = {}
    return events
end

function Battle:GetWallTarget(sideIndex)
    local side = Config.SIDES[sideIndex]
    local arena = self.arena
    -- The shipped arena's damage line is the inner edge of its thick stone wall.
    local inset = 82
    local along = 0.18 + math.random() * 0.64
    if side.id == "top" then
        return arena.x + arena.size * along, arena.y + inset
    elseif side.id == "right" then
        return arena.x + arena.size - inset, arena.y + arena.size * along
    elseif side.id == "bottom" then
        return arena.x + arena.size * along, arena.y + arena.size - inset
    end
    return arena.x + inset, arena.y + arena.size * along
end

function Battle:ChooseMonsterId()
    if self.crystalRemaining > 0 and self.spawnedDifficulty >= self.initialBudget * 0.16 then
        self.crystalRemaining = self.crystalRemaining - 1
        local stats = self:GetStats()
        local crystalWaveId = math.random() < stats.crystalQualityChance and "高品质晶石怪" or "低品质晶石怪"
        local crystalWave = Config.MONSTER_WAVES[crystalWaveId]
        return crystalWave.monsterIds[math.random(1, #crystalWave.monsterIds)], 0, crystalWaveId
    end
    local candidates = {}
    local bossWaves = {}
    local totalBossDifficulty = 0
    local minimumNormalDifficulty = math.huge
    for index = 1, #self.levelConfig.waves do
        local waveId = self.levelConfig.waves[index]
        local wave = Config.MONSTER_WAVES[waveId]
        local spawned = self.waveSpawnCounts[waveId] or 0
        local withinLimit = wave and (wave.maxRandomCount < 0 or spawned < wave.maxRandomCount)
        if wave and withinLimit and wave.boss and wave.difficulty <= self.spawnBudget then
            bossWaves[#bossWaves + 1] = wave
            totalBossDifficulty = totalBossDifficulty + wave.difficulty
        elseif wave and withinLimit and not wave.boss and wave.difficulty <= self.spawnBudget then
            candidates[#candidates + 1] = wave
            minimumNormalDifficulty = math.min(minimumNormalDifficulty, wave.difficulty)
        end
    end
    if #bossWaves > 0 and (#candidates == 0 or self.spawnBudget <= totalBossDifficulty + minimumNormalDifficulty) then
        local bossWave = bossWaves[1]
        local monsterId = bossWave.monsterIds[math.random(1, #bossWave.monsterIds)]
        return monsterId, bossWave.difficulty, bossWave.id
    end
    if #candidates == 0 then
        return nil
    end
    local wave = candidates[math.random(1, #candidates)]
    local monsterId = wave.monsterIds[math.random(1, #wave.monsterIds)]
    return monsterId, wave.difficulty, wave.id
end

function Battle:SpawnEnemy()
    if #self.enemies >= Config.MAX_ENEMIES or self.spawnBudget <= 0 then
        return false
    end
    local id, difficulty, waveId = self:ChooseMonsterId()
    if not id then
        self.spawnBudget = 0
        return false
    end
    local archetype = Config.MONSTERS[id]
    local sideIndex = math.random(1, 4)
    local tx, ty = self:GetWallTarget(sideIndex)
    local arena = self.arena
    local combat = self:GetEnemyCombatStats(archetype, self.levelConfig)
    local enemy = {
        id = id,
        name = archetype.name,
        sprite = archetype.sprite,
        side = sideIndex,
        x = arena.x + arena.size * 0.5 + (math.random() - 0.5) * 18,
        y = arena.y + arena.size * 0.5 + (math.random() - 0.5) * 18,
        tx = tx,
        ty = ty,
        hp = combat.hp,
        maxHP = combat.hp,
        speed = combat.speed,
        wallDamage = combat.wallDamage,
        attackInterval = archetype.attackInterval,
        attackTimer = 0.2 + math.random() * 0.35,
        wait = archetype.wait or 0.2,
        reward = archetype.reward,
        crystal = archetype.crystal or 0,
        difficulty = difficulty,
        size = archetype.size,
        boss = archetype.boss,
        flash = 0,
        bob = math.random() * math.pi * 2,
        atWall = false,
        dead = false,
        incomingDamage = 0,
    }
    MonsterAffixes.Apply(enemy, self.night or self.bestNight, self:GetStats())
    self.enemies[#self.enemies + 1] = enemy
    if difficulty > 0 then
        self.spawnBudget = math.max(0, self.spawnBudget - difficulty)
        self.spawnedDifficulty = self.spawnedDifficulty + difficulty
        self.waveSpawnCounts[waveId] = (self.waveSpawnCounts[waveId] or 0) + 1
    end
    return true
end

function Battle:SpawnBonusEnemy(id, x, y, sideIndex)
    if #self.enemies >= Config.MAX_ENEMIES then return false end
    local archetype = Config.MONSTERS[id]
    if not archetype then return false end
    sideIndex = clamp(math.floor(tonumber(sideIndex) or 1), 1, 4)
    local tx, ty = self:GetWallTarget(sideIndex)
    local combat = self:GetEnemyCombatStats(archetype, self.levelConfig)
    self.enemies[#self.enemies + 1] = {
        id = id, name = archetype.name, sprite = archetype.sprite, side = sideIndex,
        x = x, y = y, tx = tx, ty = ty,
        hp = combat.hp, maxHP = combat.hp, speed = combat.speed, wallDamage = combat.wallDamage,
        attackInterval = archetype.attackInterval, attackTimer = archetype.attackInterval,
        wait = archetype.wait or 0, reward = archetype.reward, crystal = archetype.crystal or 0,
        difficulty = 0, size = archetype.size, boss = false, flash = 0,
        bob = math.random() * math.pi * 2, atWall = false, dead = false,
        incomingDamage = 0, bonus = true, noChestSpawn = true,
    }
    return true
end

function Battle:GetDefenderPosition(sideIndex, slot, count)
    local sidePositions = WallData.positions[sideIndex]
    local source = sidePositions and sidePositions[math.max(1, math.min(#sidePositions, slot))]
    if source then
        return WallData.centerX + source[1] * WallData.pixelsPerWorldUnit,
            WallData.centerY - source[2] * WallData.pixelsPerWorldUnit
    end
    local arena = self.arena
    local t = count <= 1 and 0.5 or (slot - 0.5) / count
    local padding = 0.12
    t = padding + t * (1 - padding * 2)
    if sideIndex == 1 then
        return arena.x + arena.size * t, arena.y + 45
    elseif sideIndex == 2 then
        return arena.x + arena.size - 45, arena.y + arena.size * t
    elseif sideIndex == 3 then
        return arena.x + arena.size * (1 - t), arena.y + arena.size - 45
    end
    return arena.x + 45, arena.y + arena.size * (1 - t)
end

function Battle:GetHeroPosition(sideIndex)
    local source = WallData.heroes[sideIndex]
    if source then
        return WallData.centerX + source[1] * WallData.pixelsPerWorldUnit,
            WallData.centerY - source[2] * WallData.pixelsPerWorldUnit
    end
    return self:GetDefenderPosition(sideIndex, 1, 1)
end

function Battle:FindTarget(sideIndex, excluded)
    local target, fallback = nil, nil
    local best, fallbackBest = math.huge, math.huge
    for index = 1, #self.enemies do
        local enemy = self.enemies[index]
        if enemy ~= excluded and not enemy.dead and enemy.side == sideIndex then
            local remaining = distance(enemy.x, enemy.y, enemy.tx, enemy.ty)
            if remaining < fallbackBest then
                fallbackBest = remaining
                fallback = enemy
            end
            local effectiveHP = (tonumber(enemy.hp) or math.huge) - (enemy.incomingDamage or 0)
            if effectiveHP > 0 and remaining < best then
                best = remaining
                target = enemy
            end
        end
    end
    return target or fallback
end

function Battle:ReleaseProjectileReservation(projectile)
    local target = projectile and projectile.reservedTarget or nil
    if target then
        target.incomingDamage = math.max(0, (target.incomingDamage or 0) - (projectile.reservedDamage or 0))
    end
    if projectile then
        projectile.reservedTarget = nil
        projectile.reservedDamage = 0
    end
end

function Battle:AssignProjectileTarget(projectile, target)
    self:ReleaseProjectileReservation(projectile)
    projectile.target = target
    if target then
        local reserved = math.max(0, tonumber(projectile.damage) or 0)
        target.incomingDamage = (target.incomingDamage or 0) + reserved
        projectile.reservedTarget = target
        projectile.reservedDamage = reserved
    end
end

function Battle:QueueProjectile(projectile, target)
    if #self.projectiles >= Config.MAX_PROJECTILES or not target then return false end
    self:AssignProjectileTarget(projectile, target)
    self.projectiles[#self.projectiles + 1] = projectile
    return true
end

function Battle:ShootSide(sideIndex)
    local stats = self:GetStats()
    local total = self:GetArcherCountForSide(sideIndex, stats)
    if total <= 0 then
        return
    end
    local archer = self:GetArcherForSide(sideIndex) or Config.ARCHER
    local visualCount = math.min(12, total)
    local damageScale = total / visualCount
    for slot = 1, visualCount do
        local rapidFire = archer.id == 20001 and stats.archerEileenPassiveUnlocked and math.random() < 0.02
        local shotCount = rapidFire and 2 or 1
        for shot = 1, shotCount do
            if #self.projectiles >= Config.MAX_PROJECTILES then break end
            local target = self:FindTarget(sideIndex)
            if not target then break end
            local x, y = self:GetDefenderPosition(sideIndex, slot, visualCount)
            local berserk = math.random() < stats.archerBerserkChance
            local critical = math.random() < stats.archerCrit
            local bossMultiplier = target.boss and (1 + stats.archerBossBonus) or 1
            local projectile = BattleExpansion.ConfigureArcherProjectile({
                x = x + (shot - 1) * 3, y = y,
                side = sideIndex,
                damage = stats.archerDamage * damageScale * stats.archerDamageMultiplier * bossMultiplier
                    * (berserk and 2 or 1) * (critical and stats.archerCritDamageMultiplier or 1),
                speed = Config.ARCHER.projectileSpeed,
                color = (berserk or critical) and Config.COLORS.danger or Config.COLORS.gold,
                penetration = stats.archerProjectilePenetration,
                projectileSize = 1 + stats.archerProjectileRadiusBonus * 0.5,
                radiusBonus = stats.archerProjectileRadiusBonus,
                critical = critical,
                source = "archer",
                life = 2.2,
                archerId = archer.id,
                explosive = stats.explosiveArrowUnlocked and math.random() < 0.05,
            }, stats)
            self:QueueProjectile(projectile, target)
        end
    end
    BattleExpansion.OnArcherRound(self, stats)
    self:PushEvent("bow")
end

function Battle:DamageEnemiesInRadius(x, y, radius, amount, color, status, critical, source)
    local hit = 0
    for index = 1, #self.enemies do
        local enemy = self.enemies[index]
        if not enemy.dead and distance(x, y, enemy.x, enemy.y) <= radius then
            if status == "burn" then
                enemy.burnLife = math.max(enemy.burnLife or 0, 3)
                enemy.burnTimer = math.min(enemy.burnTimer or 0.5, 0.5)
                enemy.burnDamage = math.max(enemy.burnDamage or 0, amount * 0.2)
            end
            self:DamageEnemy(enemy, amount, color, critical or false, source)
            hit = hit + 1
        end
    end
    return hit
end

function Battle:ActivateHeroSpecial(sideIndex, hero, target, x, y, stats)
    local skill = hero.specialSkill
    if not skill then return false end
    local color = HERO_SKILL_COLORS[hero.profession] or Config.COLORS.crystal
    local critical = math.random() < stats.heroCrit
    local damage = (skill.damage + stats.heroDamage + (stats.heroSkillDamageByAttribute[hero.skillAttribute] or 0))
        * stats.heroDamageMultiplier * (critical and stats.heroCritDamageMultiplier or 1)
    local radius = math.max(34, (skill.size or 1) * 22 * (1 + stats.heroProjectileRadiusBonus))
    self:AddFloatingText(target.x, target.y - target.size * 0.85, skill.name, color, 16)
    self:AddSkillEffect(skill.id, target.x, target.y, radius, sideIndex)

    if skill.skillType == 3 or skill.skillType == 5 or skill.skillType == 6
        or skill.skillType == 7 or skill.skillType == 9 or skill.skillType == 10 then
        local hits = skill.hitCount or math.max(1, skill.count or 1)
        self:AddRing(target.x, target.y, color, radius * 0.25, radius * 2.4, 0.42, "hero_skill")
        self:AddBurst(target.x, target.y, color, 10 + hits * 2, 95)
        for hitIndex = 1, hits do
            self:DamageEnemiesInRadius(target.x, target.y, radius, damage, color, skill.skillType == 9 and "burn" or nil, critical, "hero")
        end
        BattleExpansion.OnHeroSpecial(self, stats)
        return true
    end

    local projectileCount = math.max(1, skill.count or 1) + stats.heroProjectileExtraCount
    if math.random() < stats.heroProjectileExtraChance then projectileCount = projectileCount + 1 end
    for projectileIndex = 1, math.min(6, projectileCount) do
        if #self.projectiles >= Config.MAX_PROJECTILES then break end
        local projectileTarget = self:FindTarget(sideIndex) or target
        self:QueueProjectile({
            x = x + (projectileIndex - 1) * 3, y = y, side = sideIndex,
            damage = damage, speed = (skill.speed or 10) * 42, color = color,
            penetration = stats.heroProjectilePenetration,
            remainingPenetrations = math.max(0, skill.penetration or 0),
            projectileSize = (skill.size or 1) * stats.heroProjectileSizeMultiplier,
            critical = critical, source = "hero", heroProfession = hero.profession,
            life = 2.4, special = true, skillId = skill.id, skillName = skill.name,
        }, projectileTarget)
    end
    BattleExpansion.OnHeroSpecial(self, stats)
    return true
end

function Battle:HeroShoot(sideIndex)
    local target = self:FindTarget(sideIndex)
    local hero = self:GetHeroForSide(sideIndex)
    if not hero or not target or #self.projectiles >= Config.MAX_PROJECTILES then
        return
    end
    local x, y = self:GetHeroPosition(sideIndex)
    self.heroShots[sideIndex] = self.heroShots[sideIndex] + 1
    local stats = self:GetStats()
    local specialEvery = BattleExpansion.GetHeroSpecialEvery(hero, stats)
    local special = self.heroShots[sideIndex] % specialEvery == 0
    if special and self:ActivateHeroSpecial(sideIndex, hero, target, x, y, stats) then
        return
    end
    local projectileCount = 1 + stats.heroProjectileExtraCount
    if math.random() < stats.heroProjectileExtraChance then
        projectileCount = projectileCount + 1
    end
    local baseDamage = hero.damage + stats.heroDamage
    local normalSkill = hero.normalSkill or {}
    local color = HERO_SKILL_COLORS[hero.profession] or { 119, 174, 255, 255 }
    for projectileIndex = 1, math.min(6, projectileCount) do
        local projectileTarget = self:FindTarget(sideIndex) or target
        local critical = math.random() < stats.heroCrit
        self:QueueProjectile({
            x = x + (projectileIndex - 1) * 2, y = y, side = sideIndex,
            damage = baseDamage * stats.heroDamageMultiplier * (critical and stats.heroCritDamageMultiplier or 1),
            speed = hero.projectileSpeed,
            color = color,
            penetration = stats.heroProjectilePenetration,
            remainingPenetrations = math.max(0, normalSkill.penetration or 0),
            projectileSize = (normalSkill.size or 0.8) * stats.heroProjectileSizeMultiplier,
            skillId = normalSkill.id,
            critical = critical, source = "hero", heroProfession = hero.profession,
            life = 2.2,
            special = false,
        }, projectileTarget)
    end
end

function Battle:ExplodeSeed(enemy)
    local damage = enemy.seedDamage
    if not damage or damage <= 0 then return end
    enemy.seedDamage = nil
    local radius = enemy.seedRadius or 52
    local color = HERO_SKILL_COLORS[3]
    self:AddSkillEffect(2009, enemy.x, enemy.y, radius, enemy.side)
    self:AddRing(enemy.x, enemy.y, color, 8, radius * 2.8, 0.42, "seed")
    self:AddBurst(enemy.x, enemy.y, color, 14, 115)
    for index = 1, #self.enemies do
        local target = self.enemies[index]
        if target ~= enemy and not target.dead and distance(enemy.x, enemy.y, target.x, target.y) <= radius then
            self:DamageEnemy(target, damage, color, false)
        end
    end
end

function Battle:TrySpawnCursorChest(enemy, stats)
    if not enemy or enemy.noChestSpawn then return false end
    local chance = clamp(tonumber(stats and stats.cursorChestChance) or 0, 0, 1)
    if chance <= 0 or math.random() >= chance then return false end
    if not self:SpawnBonusEnemy("宝箱怪", enemy.x, enemy.y, enemy.side) then return false end
    self:AddRing(enemy.x, enemy.y, Config.COLORS.gold, 8, 105, 0.45, "chest")
    self:AddFloatingText(enemy.x, enemy.y - enemy.size * 0.8, "宝箱怪出现", Config.COLORS.gold, 18)
    return true
end

function Battle:DamageEnemy(enemy, amount, color, critical, source)
    if not enemy or enemy.dead then
        return
    end
    enemy.hp = enemy.hp - amount
    enemy.flash = 0.1
    local text = (critical and "暴击 " or "") .. tostring(math.max(1, math.floor(amount + 0.5)))
    local textColor = color or Config.COLORS.text
    local textSize = critical and 17 or 13
    local textStyle = nil
    if source == "cursor" then
        textColor = critical and CURSOR_CRIT_COLOR or CURSOR_DAMAGE_COLOR
        textSize = critical and 29 or 23
        textStyle = "cursor"
    end
    self:AddFloatingText(enemy.x, enemy.y - enemy.size * 0.55, text, textColor, textSize, textStyle)
    if enemy.hp <= 0 then
        enemy.dead = true
        local stats = self:GetStats()
        local baseGoldReward = math.max(0, enemy.reward + math.floor(stats.goldDropFlat or 0))
        local goldReward, rewardMultiplier, rewardTier = LootSystem.RollGoldReward(baseGoldReward, stats, enemy)
        local crystalReward = enemy.crystal
        if crystalReward <= 0 and not enemy.boss and math.random() < stats.normalCrystalChance then
            crystalReward = 1
        end
        self.crystals = self.crystals + crystalReward
        if source == "cursor" then
            self:TrySpawnCursorChest(enemy, stats)
        end
        self:RollEquipmentDrop(enemy, stats)
        self:AddBurst(enemy.x, enemy.y, enemy.crystal > 0 and Config.COLORS.crystal or Config.COLORS.gold, enemy.boss and 22 or 8, enemy.boss and 150 or 75)
        local rewardText, rewardColor, rewardSize, rewardStyle = LootSystem.GetTierPresentation(rewardTier, rewardMultiplier)
        if rewardText then
            self:AddFloatingText(enemy.x, enemy.y - enemy.size, rewardText, rewardColor, rewardSize, rewardStyle)
            self:AddRing(enemy.x, enemy.y, rewardColor, 8, rewardTier == "jackpot" and 170 or 105, rewardTier == "jackpot" and 0.85 or 0.5, rewardStyle)
        end
        if goldReward > 0 then
            self:AddGoldPickups(enemy.x, enemy.y, goldReward)
        end
        if crystalReward > 0 then
            self:AddFloatingText(enemy.x, enemy.y + 2, "+" .. tostring(crystalReward), Config.COLORS.crystal, 14)
        end
        self.dirtySave = true
        self:PushEvent("kill")
        self:ExplodeSeed(enemy)
    else
        self:AddBurst(enemy.x, enemy.y, color or Config.COLORS.text, 2, 35)
        self:PushEvent("hit")
    end
end

function Battle:SetCursor(x, y)
    if self.state ~= "running" then
        return
    end
    local arena = self.arena
    self.cursor.x = clamp(x, arena.x + 18, arena.x + arena.size - 18)
    self.cursor.y = clamp(y, arena.y + 18, arena.y + arena.size - 18)
    self.cursor.visible = true
end

function Battle:CursorAttack()
    if not self.cursor.visible then
        return
    end
    local stats = self:GetStats()
    local didHit = false
    local critical = math.random() < stats.cursorCrit
    local damage = stats.cursorBase * stats.damageMultiplier * (critical and stats.cursorCritDamageMultiplier or 1)
    local hitCount = math.random() < stats.cursorDoubleChance and 2 or 1
    for index = 1, #self.enemies do
        local enemy = self.enemies[index]
        if not enemy.dead and distance(self.cursor.x, self.cursor.y, enemy.x, enemy.y) <= stats.cursorRadius then
            for hitIndex = 1, hitCount do
                self:DamageEnemy(enemy, damage, Config.COLORS.cursor, critical, "cursor")
            end
            didHit = true
        end
    end
    self.cursor.pulse = 0.28
    self:AddRing(self.cursor.x, self.cursor.y, Config.COLORS.cursor, stats.cursorRadius * 0.45, stats.cursorRadius * 1.7, 0.36, "cursor")
    BattleExpansion.OnCursorAttack(self, stats, damage)
    if didHit then
        self:PushEvent("hit")
    end
end

function Battle:RandomCursorAttack()
    local stats = self:GetStats()
    if stats.randomCursorEnabled <= 0 or #self.enemies == 0 then
        return
    end
    local shots = math.max(1, 1 + math.floor(stats.randomCursorCount))
    for shotIndex = 1, shots do
        local candidates = {}
        for enemyIndex = 1, #self.enemies do
            if not self.enemies[enemyIndex].dead then
                candidates[#candidates + 1] = self.enemies[enemyIndex]
            end
        end
        if #candidates == 0 then
            break
        end
        local target = candidates[math.random(1, #candidates)]
        self:AddRing(target.x, target.y, Config.COLORS.cursor, 6, 100, 0.3)
        self:DamageEnemy(target, stats.cursorBase * stats.damageMultiplier, Config.COLORS.cursor, false, "cursor")
    end
end

local DRAGON_ASSISTS = {
    { name = "红龙", color = { 255, 91, 45, 255 }, penetration = 3 },
    { name = "冰龙", color = { 92, 196, 255, 255 }, penetration = 5 },
    { name = "土龙", color = { 212, 155, 71, 255 }, penetration = 5 },
    { name = "雷龙", color = { 190, 111, 255, 255 }, penetration = 5 },
}

function Battle:StartDragonAssist()
    if self.dragonAssistsRemaining <= 0 or #self.enemies == 0 then
        return false
    end
    self.dragonAssistType = math.random(1, #DRAGON_ASSISTS)
    self.dragonAssistLife = 10
    self.dragonAssistShotTimer = 0
    local assist = DRAGON_ASSISTS[self.dragonAssistType]
    local cx = self.arena.x + self.arena.size * 0.5
    local cy = self.arena.y + self.arena.size * 0.5
    self.message = assist.name .. "降临 · 随机助战"
    self.messageTimer = 2.2
    self:AddRing(cx, cy, assist.color, 12, 118, 0.65, "dragon")
    self:AddBurst(cx, cy, assist.color, 18, 125)
    self:PushEvent("upgrade")
    return true
end

function Battle:UpdateDragonAssist(dt)
    if self.dragonAssistLife > 0 then
        self.dragonAssistLife = math.max(0, self.dragonAssistLife - dt)
        self.dragonAssistShotTimer = self.dragonAssistShotTimer - dt
        if self.dragonAssistShotTimer <= 0 and #self.projectiles < Config.MAX_PROJECTILES then
            local candidates = {}
            for index = 1, #self.enemies do
                if not self.enemies[index].dead then
                    candidates[#candidates + 1] = self.enemies[index]
                end
            end
            if #candidates > 0 then
                local assist = DRAGON_ASSISTS[self.dragonAssistType]
                local target = candidates[math.random(1, #candidates)]
                local stats = self:GetStats()
                self:QueueProjectile({
                    x = self.arena.x + self.arena.size * 0.5,
                    y = self.arena.y + self.arena.size * 0.5,
                    side = target.side,
                    damage = math.max(1, stats.cursorBase * 0.5) * stats.damageMultiplier,
                    speed = 300,
                    color = assist.color,
                    penetration = 0,
                    remainingPenetrations = assist.penetration,
                    projectileSize = 2.2,
                    life = 2.5,
                    special = true,
                    source = "dragon",
                }, target)
            end
            self.dragonAssistShotTimer = self.dragonAssistShotTimer + 0.3
        end
        if self.dragonAssistLife <= 0 then
            self.dragonAssistsRemaining = math.max(0, self.dragonAssistsRemaining - 1)
            self.dragonAssistTimer = 4 + math.random() * 3
        end
    elseif self.dragonAssistsRemaining > 0 then
        self.dragonAssistTimer = self.dragonAssistTimer - dt
        if self.dragonAssistTimer <= 0 then
            self:StartDragonAssist()
        end
    end
end

function Battle:TryUpgrade(id)
    local ok, message = Skills.TryUpgrade(self, id)
    self.message = message
    self.messageTimer = 1.4
    self:PushEvent(ok and "upgrade" or "deny")
    return ok
end

function Battle:FinalizeNightGold()
    self.nightGoldEarned = math.max(0, math.floor((tonumber(self.gold) or 0) - (tonumber(self.runStartGold) or self.gold)))
    self.nightGoldAdClaimed = false
    return self.nightGoldEarned
end

function Battle:GetNightGoldAdOffer()
    local resultId = self.nightResultId
    if self.state ~= "victory" and self.state ~= "defeat" then
        return nil, "仅可在每夜结算时领取", resultId
    end
    if self.nightGoldAdClaimed then
        return nil, "本夜金币翻倍已领取", resultId
    end
    local amount = math.max(0, math.floor(tonumber(self.nightGoldEarned) or 0))
    if amount <= 0 then
        return nil, "本夜没有可翻倍金币", resultId
    end
    return amount, nil, resultId
end

function Battle:ClaimNightGoldFromRewardAd(resultId)
    if resultId == nil or resultId ~= self.nightResultId then
        return false, 0, "本夜结算已经结束"
    end
    local amount, reason = self:GetNightGoldAdOffer()
    if not amount then
        return false, 0, reason
    end
    self.nightGoldAdClaimed = true
    self.gold = self.gold + amount
    self.dirtySave = true
    self:PushEvent("upgrade")
    print("RewardAd night gold added: +" .. tostring(amount) .. "; total=" .. tostring(math.floor(self.gold)))
    return true, amount, "额外获得 +" .. tostring(amount) .. " 金币"
end

function Battle:GetDefeatReviveAdOffer()
    local resultId = self.nightResultId
    if self.state ~= "defeat" then
        return nil, "仅在城墙失守时可以续战", resultId
    end
    if self.nightReviveAdUsed then
        return nil, "本次挑战的续战机会已使用", resultId
    end
    return DEFEAT_REVIVE_WALL_PERCENT, nil, resultId
end

function Battle:ClaimDefeatReviveFromRewardAd(resultId)
    if resultId == nil or resultId ~= self.nightResultId then
        return false, 0, "本次挑战已经结束"
    end
    local amount, reason = self:GetDefeatReviveAdOffer()
    if not amount then
        return false, 0, reason
    end

    self.nightReviveAdUsed = true
    self.state = "running"
    self.wallHP = math.max(1, math.floor((self.wallMax or 1) * amount / 100 + 0.5))
    self.cursor.visible = true
    self.resultMessage = ""
    self.message = "城墙复苏 · 恢复 " .. tostring(amount) .. "%"
    self.messageTimer = 2.2
    for index = 1, #self.enemies do
        local enemy = self.enemies[index]
        enemy.wait = math.max(tonumber(enemy.wait) or 0, DEFEAT_REVIVE_FREEZE_SECONDS)
        enemy.attackTimer = math.max(tonumber(enemy.attackTimer) or 0, DEFEAT_REVIVE_FREEZE_SECONDS)
    end
    self:PushEvent("upgrade")
    print("RewardAd defeat revive granted; wall=" .. tostring(self.wallHP) .. "/" .. tostring(self.wallMax))
    return true, amount, "城墙恢复 " .. tostring(amount) .. "% · 敌人短暂停顿"
end

function Battle:GetNightSupplyAdOffer()
    local night = clamp(math.floor(tonumber(self.nextNight) or 1), 1, Config.CAMPAIGN_NIGHT_COUNT)
    local requestId = self:GetNightSupplyKey(night)
    if self.state ~= "home" then
        return nil, "请先返回备战界面", requestId
    end
    if not self:IsNightSupplyNight(night) then
        return nil, "战备补给在第5、10、15、20、25、30夜开放", requestId
    end
    if self.adSupplyClaimKey == requestId then
        if self.adSupplyReadyKey == requestId then
            return nil, "第" .. tostring(night) .. "夜战备已就绪", requestId
        end
        return nil, "第" .. tostring(night) .. "夜战备已经使用", requestId
    end
    return NIGHT_SUPPLY_WALL_BONUS, nil, requestId
end

function Battle:ClaimNightSupplyFromRewardAd(requestId)
    local amount, reason, currentId = self:GetNightSupplyAdOffer()
    if requestId == nil or requestId ~= currentId then
        return false, 0, "备战夜次已经变化"
    end
    if not amount then
        return false, 0, reason
    end
    self.adSupplyClaimKey = requestId
    self.adSupplyReadyKey = requestId
    self.dirtySave = true
    self:PushEvent("upgrade")
    print("RewardAd night supply granted; request=" .. tostring(requestId))
    return true, amount, "第" .. tostring(self.nextNight) .. "夜城墙上限 +" .. tostring(amount) .. "%"
end

function Battle:TryQuickUpgrade(kind)
    local ok, message = Skills.TryQuickUpgrade(self, kind)
    self.message = message
    self.messageTimer = 1.4
    self:PushEvent(ok and "upgrade" or "deny")
    return ok
end

function Battle:AddEquipmentDrop(drop, stats)
    if #self.inventory >= Config.EQUIPMENT_CAPACITY then
        return false
    end
    local quality = weightedChoice(drop.commonWeights, 0)
    quality = clamp(quality, 0, drop.maxQuality or 0)
    local position = weightedChoice(drop.weaponWeights, math.random(1, 4))
    local candidates = {}
    for index = 1, #Config.EQUIPMENT_ORDER do
        local item = Config.EQUIPMENT_BY_ID[Config.EQUIPMENT_ORDER[index]]
        if item.quality == quality and item.pos == position then
            candidates[#candidates + 1] = item.id
        end
    end
    if #candidates == 0 then
        return false
    end
    local itemId = candidates[math.random(1, #candidates)]
    self.inventory[#self.inventory + 1] = { id = itemId, level = 0, locked = false, new = true }
    self.runDrops[#self.runDrops + 1] = { id = itemId, level = 0, locked = false, new = true }
    self.equipmentDrops = self.equipmentDrops + 1
    local item = Config.EQUIPMENT_BY_ID[itemId]
    self:AddFloatingText(self.arena.x + self.arena.size * 0.5, self.arena.y + self.arena.size * 0.42, "获得 " .. item.name, Config.COLORS.crystal, 15)
    self:PushEvent("upgrade")
    if stats.materialDoubleChance > 0 and math.random() < stats.materialDoubleChance and #self.inventory < Config.EQUIPMENT_CAPACITY then
        self.inventory[#self.inventory + 1] = { id = itemId, level = 0, locked = false, new = true }
        self.runDrops[#self.runDrops + 1] = { id = itemId, level = 0, locked = false, new = true }
        self.equipmentDrops = self.equipmentDrops + 1
    end
    return true
end

function Battle:RollEquipmentDrop(enemy, stats)
    local drop = Config.LEVEL_DROPS[self.levelConfig.dropDay or self.night]
    if not drop or #self.inventory >= Config.EQUIPMENT_CAPACITY then
        return false
    end
    if self.equipmentDrops >= (drop.maxPerRun or 0) then
        return false
    end
    local guaranteed = enemy.boss and (drop.bossGuaranteed or 0) > 0
    local dropRate = (drop.dropRate or 0) + (self.levelConfig.dropRateBonus or 0)
    if not guaranteed and math.random() * 100 >= dropRate then
        return false
    end
    return self:AddEquipmentDrop(drop, stats or self:GetStats())
end

local function finishEquipmentAction(self, ok, message)
    self.message = message
    self.messageTimer = 1.8
    self:PushEvent(ok and "upgrade" or "deny")
    if ok then
        self.dirtySave = true
    end
    return ok, message
end

function Battle:EquipInventoryItem(inventoryIndex, sideIndex)
    return finishEquipmentAction(self, Equipment.EquipInventoryItem(self, inventoryIndex, sideIndex))
end

function Battle:UnequipItem(sideIndex, role, slot)
    return finishEquipmentAction(self, Equipment.Unequip(self, sideIndex, role, slot))
end

function Battle:SortInventory()
    return finishEquipmentAction(self, Equipment.SortInventory(self))
end

function Battle:QuickMergeEquipment()
    return finishEquipmentAction(self, Equipment.QuickMerge(self))
end

function Battle:RecycleInventory()
    return finishEquipmentAction(self, Equipment.RecycleInventory(self))
end

function Battle:StrengthenEquipment(sideIndex, role, slot)
    return finishEquipmentAction(self, Equipment.Strengthen(self, sideIndex, role, slot))
end

function Battle:FinishVictory()
    self.state = "victory"
    local stats = self:GetStats()
    local levelConfig = self.levelConfig or {}
    local earnedGold = math.max(0, self.gold - (self.runStartGold or self.gold))
    local earnedCrystals = math.max(0, self.crystals - (self.runStartCrystals or self.crystals))
    local goldBonusPercent = (levelConfig.settlementGoldBonus or 0) + (stats.goldSettlementBonus or 0)
    local crystalBonusPercent = (levelConfig.settlementCrystalBonus or 0) + (stats.crystalSettlementBonus or 0)
    local bonusGold = math.floor(earnedGold * goldBonusPercent / 100 + 0.5)
    local bonusCrystals = math.floor(earnedCrystals * crystalBonusPercent / 100 + 0.5)
    self.gold = self.gold + bonusGold
    self.crystals = self.crystals + bonusCrystals
    if self.activeMode == "final" then
        self.resultMessage = "最终之夜 · 难度 " .. tostring(self.finalDifficulty) .. " 通关"
        self.finalDifficultySelected = self.finalDifficulty
    else
        self.bestNight = math.max(self.bestNight, self.night)
    end
    if self.activeMode == "campaign" and self.night < Config.CAMPAIGN_NIGHT_COUNT then
        self.nextNight = self.night + 1
        self.resultMessage = "第 " .. tostring(self.night) .. " 晚守卫成功"
    elseif self.activeMode == "campaign" then
        self.nextNight = Config.CAMPAIGN_NIGHT_COUNT
        self.resultMessage = "第 30 晚守卫成功 · 最终之夜已解锁"
    end
    if self.night == 1 then
        self.gold = self.gold + math.floor(3 * (1 + (stats.goldGainBonus or 0)) + 0.5)
    end
    self:FinalizeNightGold()
    self.dirtySave = true
    self:PushEvent("win")
end

function Battle:FinishDefeat()
    self:CollectPendingGold()
    self.state = "defeat"
    self.resultMessage = "城墙失守 · 可重新挑战第 " .. tostring(self.night) .. " 晚"
    self:FinalizeNightGold()
    self.dirtySave = true
    self:PushEvent("defeat")
end

function Battle:UpdateEnemies(dt)
    local stats = self:GetStats()
    for index = #self.enemies, 1, -1 do
        local enemy = self.enemies[index]
        if enemy.dead then
            table.remove(self.enemies, index)
        else
            if (enemy.burnLife or 0) > 0 then
                enemy.burnLife = math.max(0, enemy.burnLife - dt)
                enemy.burnTimer = (enemy.burnTimer or 0.5) - dt
                if enemy.burnTimer <= 0 then
                    enemy.burnTimer = 0.5
                    self:DamageEnemy(enemy, math.max(1, enemy.burnDamage or 1), HERO_SKILL_COLORS[4], false)
                end
            end
            enemy.flash = math.max(0, enemy.flash - dt)
            enemy.bob = enemy.bob + dt * 4
            if enemy.wait > 0 then
                enemy.wait = enemy.wait - dt
            elseif not enemy.atWall then
                local d = distance(enemy.x, enemy.y, enemy.tx, enemy.ty)
                local step = enemy.speed * dt
                if d <= step + 3 then
                    enemy.x, enemy.y = enemy.tx, enemy.ty
                    enemy.atWall = true
                else
                    enemy.x = enemy.x + (enemy.tx - enemy.x) / d * step
                    enemy.y = enemy.y + (enemy.ty - enemy.y) / d * step
                end
            else
                enemy.attackTimer = enemy.attackTimer - dt
                if enemy.attackTimer <= 0 then
                    enemy.attackTimer = enemy.attackInterval
                    if math.random() < stats.wallDodge then
                        self:AddFloatingText(enemy.x, enemy.y - 15, "闪避", Config.COLORS.crystal, 15)
                    else
                        local damage = math.max(1, enemy.wallDamage - stats.wallDefense)
                        self.wallHP = math.max(0, self.wallHP - damage)
                        self.wallFlash[enemy.side] = 0.16
                        self.shake = math.min(7, self.shake + 2.5)
                        self:AddBurst(enemy.x, enemy.y, Config.COLORS.danger, 5, 60)
                        self:AddFloatingText(enemy.x, enemy.y - 15, "-" .. tostring(damage), Config.COLORS.danger, 15)
                        self:PushEvent("wall_hit")
                        BattleExpansion.OnWallDamage(self, enemy, stats)
                    end
                end
            end
        end
    end
end

function Battle:UpdateVFX(dt)
    self.messageTimer = math.max(0, self.messageTimer - dt)
    self.cursor.pulse = math.max(0, self.cursor.pulse - dt)
    self:UpdateCoinPickups(dt)
    self.shake = math.max(0, self.shake - dt * 18)
    for index = 1, 4 do
        local flash = tonumber(self.wallFlash[index]) or 0
        self.wallFlash[index] = math.max(0, flash - dt)
    end
    for index = #self.particles, 1, -1 do
        local particle = self.particles[index]
        particle.life = particle.life - dt
        if particle.life <= 0 then
            table.remove(self.particles, index)
        else
            particle.x = particle.x + particle.vx * dt
            particle.y = particle.y + particle.vy * dt
            particle.vx = particle.vx * (1 - math.min(0.9, dt * 3))
            particle.vy = particle.vy * (1 - math.min(0.9, dt * 3))
        end
    end
    for index = #self.rings, 1, -1 do
        local ring = self.rings[index]
        ring.life = ring.life - dt
        if ring.life <= 0 then
            table.remove(self.rings, index)
        else
            ring.radius = ring.radius + ring.speed * dt
        end
    end
    for index = #self.skillEffects, 1, -1 do
        local effect = self.skillEffects[index]
        effect.age = effect.age + dt
        effect.life = effect.life - dt
        if effect.life <= 0 then
            table.remove(self.skillEffects, index)
        end
    end
    for index = #self.floatingText, 1, -1 do
        local item = self.floatingText[index]
        item.life = item.life - dt
        if item.life <= 0 then
            table.remove(self.floatingText, index)
        else
            item.y = item.y - 22 * dt
        end
    end
end

function Battle:Update(timeStep)
    local dt = math.min(0.05, timeStep) * self.speed
    self:UpdateVFX(dt)
    if self.state ~= "running" then
        return
    end

    self.spawnTimer = self.spawnTimer - dt
    local spawnGuard = 0
    while self.spawnBudget > 0 and self.spawnTimer <= 0 and spawnGuard < 8 do
        spawnGuard = spawnGuard + 1
        if not self:SpawnEnemy() then break end
        self.spawnTimer = self.spawnTimer + self.spawnInterval
    end

    local stats = self:GetStats()
    self.wallRegenTimer = self.wallRegenTimer - dt
    if stats.wallRegen > 0 and self.wallRegenTimer <= 0 then
        local recovered = math.min(stats.wallRegen, self.wallMax - self.wallHP)
        if recovered > 0 then
            self.wallHP = self.wallHP + recovered
            self:AddFloatingText(self.arena.x + self.arena.size * 0.5, self.arena.y + 18, "+" .. tostring(recovered), Config.COLORS.unlocked, 14)
        end
        self.wallRegenTimer = 4
    end
    self.randomCursorTimer = self.randomCursorTimer - dt
    if stats.randomCursorEnabled > 0 and self.randomCursorTimer <= 0 then
        self:RandomCursorAttack()
        self.randomCursorTimer = stats.randomCursorInterval
    end
    for sideIndex = 1, 4 do
        self.defenderTimers[sideIndex] = self.defenderTimers[sideIndex] - dt
        if self.defenderTimers[sideIndex] <= 0 then
            self:ShootSide(sideIndex)
            self.defenderTimers[sideIndex] = Config.ARCHER.interval / stats.archerSpeed
        end
        self.heroTimers[sideIndex] = self.heroTimers[sideIndex] - dt
        if self.heroTimers[sideIndex] <= 0 then
            local hero = self:GetHeroForSide(sideIndex)
            if hero then
                self:HeroShoot(sideIndex)
                self.heroTimers[sideIndex] = hero.interval / stats.heroSpeed
            else
                self.heroTimers[sideIndex] = 0.5
            end
        end
    end

    self.cursorTimer = self.cursorTimer - dt
    if self.cursorTimer <= 0 then
        self:CursorAttack()
        self.cursorTimer = Config.CURSOR.interval / stats.cursorSpeed
    end

    self:UpdateDragonAssist(dt)
    BattleExpansion.Update(self, dt, stats)
    self:UpdateProjectiles(dt)
    self:UpdateEnemies(dt)

    if self.wallHP <= 0 then
        self:FinishDefeat()
    elseif self.spawnBudget <= 0 and #self.enemies == 0 and #self.coinPickups == 0 then
        self:FinishVictory()
    end
end

ProjectileSystem.Install(Battle)
BattleEffects.Install(Battle)

return Battle
