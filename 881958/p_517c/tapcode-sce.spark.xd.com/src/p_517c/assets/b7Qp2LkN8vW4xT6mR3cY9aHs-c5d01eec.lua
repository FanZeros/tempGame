-- 弹射 4096 动态难度生成管理器。
-- 只调整下一枚方块的生成概率，不修改发射、碰撞或合成规则。

---@class SpawnManager
---@field config table
---@field recentLaunches table[]
---@field recentMergeTimes number[]
---@field lastMergeTime number|nil
---@field combo integer
---@field lastSpawnValue integer|nil
---@field sameSpawnStreak integer
---@field lastProbabilities table<integer, number>
---@field lastDebug table|nil
---@field runStartedAt number
---@field profile { completedRuns: integer, averageRunDuration: number, shortGameStreak: integer }
local SpawnManager = {}
SpawnManager.__index = SpawnManager

-- ==========================================================================
-- DDA 可调参数集中区
-- ==========================================================================

---@type table
local CONFIG = {
    pool = { 2, 4, 8, 16 },
    baseWeights = {
        [2] = 60,
        [4] = 30,
        [8] = 8,
        [16] = 2,
    },

    history = {
        launchWindow = 10,
        recentMergeWindowSeconds = 12.0,
        comboWindowSeconds = 2.0,
        staleMergeSeconds = 10.0,
    },

    mergeOpportunity = {
        oneMatchingBlockFactor = 1.28,
        pairFactor = 2.0,
        extraMatchingBlockFactor = 0.12,
        noMergeAssistBoost = 0.55,
        failureAssistBoost = 0.38,
        maxExtraMatchingBlocks = 3,
        maxFactor = 2.85,
    },

    board = {
        -- 面积按完整托盘面积计算；占用率会被限制在 0%~100%。
        occupancyAreaScale = 1.0,
        pressureStart = 0.62,
        criticalOccupancy = 0.80,
        nearFailureZMargin = 1.2,
        nearFailureMinAge = 1.0,
        stationarySpeed = 0.85,
        safetyFactors = {
            [2] = 2.25,
            [4] = 1.30,
            [8] = 0.30,
            [16] = 0.16,
        },
    },

    performance = {
        comboForMaxPressure = 5,
        recentMergesForMaxPressure = 7,
        scoreForMaxPressure = 12000,
        highestValueBaseline = 16,
        highestValueForMaxPressure = 2048,
        comboContribution = 0.45,
        recentMergeContribution = 0.30,
        scoreContribution = 0.10,
        highestValueContribution = 0.15,
        boardPressureSuppression = 0.82,
        failureAssistSuppression = 0.72,
        factors = {
            [2] = 0.82,
            [4] = 0.94,
            [8] = 1.34,
            [16] = 1.62,
        },
    },

    failureAssist = {
        consecutiveMissesForFullAssist = 5,
        shortGamesForAssist = 3,
        shortGameRatio = 0.78,
        minimumHistoricalGames = 3,
        factors = {
            [2] = 1.28,
            [4] = 1.24,
            [8] = 0.82,
            [16] = 0.62,
        },
    },

    randomness = {
        perturbation = 0.08,
        minimumProbability = 0.01,
        maximumProbability = 0.82,
        maximumProbabilityStep = 0.08,
        repeatStreakThreshold = 3,
        repeatWeightFactor = 0.36,
    },

    persistence = {
        fileName = "bounce4096_dda_profile.json",
        version = 1,
    },

    debug = {
        enabledByDefault = false,
        printSelections = false,
        toggleKey = KEY_F3,
        toggleKeyLabel = "F3",
    },
}

SpawnManager.CONFIG = CONFIG

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function Lerp(a, b, t)
    return a + (b - a) * Clamp(t, 0, 1)
end

local function SmoothStep(t)
    local value = Clamp(t, 0, 1)
    return value * value * (3 - 2 * value)
end

local function CopyMap(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

---@param values table<integer, number>
---@param pool integer[]
---@return table<integer, number>
local function Normalize(values, pool)
    ---@type number
    local total = 0
    for _, value in ipairs(pool) do total = total + math.max(0, values[value] or 0) end
    local result = {}
    if total <= 0 then
        local equal = 1 / #pool
        for _, value in ipairs(pool) do result[value] = equal end
        return result
    end
    for _, value in ipairs(pool) do result[value] = math.max(0, values[value] or 0) / total end
    return result
end

---@param probabilities table<integer, number>
---@param pool integer[]
---@param minimum number
---@param maximum number
---@return table<integer, number>
local function ApplyProbabilityBounds(probabilities, pool, minimum, maximum)
    local bounded = CopyMap(probabilities)
    for _ = 1, 6 do
        local changed = false
        for _, value in ipairs(pool) do
            if bounded[value] < minimum then
                local deficit = minimum - bounded[value]
                bounded[value] = minimum
                local available = 0
                for _, other in ipairs(pool) do
                    if other ~= value then available = available + math.max(0, bounded[other] - minimum) end
                end
                if available > 0 then
                    for _, other in ipairs(pool) do
                        if other ~= value then
                            local room = math.max(0, bounded[other] - minimum)
                            bounded[other] = bounded[other] - deficit * room / available
                        end
                    end
                end
                changed = true
            elseif bounded[value] > maximum then
                local excess = bounded[value] - maximum
                bounded[value] = maximum
                local headroom = 0
                for _, other in ipairs(pool) do
                    if other ~= value then headroom = headroom + math.max(0, maximum - bounded[other]) end
                end
                if headroom > 0 then
                    for _, other in ipairs(pool) do
                        if other ~= value then
                            local room = math.max(0, maximum - bounded[other])
                            bounded[other] = bounded[other] + excess * room / headroom
                        end
                    end
                end
                changed = true
            end
        end
        bounded = Normalize(bounded, pool)
        if not changed then break end
    end
    return bounded
end

---@param config table
---@return table<integer, number>
local function BaseProbabilities(config)
    return Normalize(config.baseWeights, config.pool)
end

---@param config table|nil
---@return SpawnManager
function SpawnManager.new(config)
    ---@type SpawnManager
    local self = setmetatable({}, SpawnManager)
    self.config = config or CONFIG
    self.recentLaunches = {}
    self.recentMergeTimes = {}
    self.lastMergeTime = nil
    self.combo = 0
    self.lastSpawnValue = nil
    self.sameSpawnStreak = 0
    self.lastProbabilities = BaseProbabilities(self.config)
    self.lastDebug = nil
    self.runStartedAt = 0
    self.profile = {
        completedRuns = 0,
        averageRunDuration = 0,
        shortGameStreak = 0,
    }
    return self
end

---@param now number|nil
function SpawnManager:StartRun(now)
    self.recentLaunches = {}
    self.recentMergeTimes = {}
    self.lastMergeTime = nil
    self.combo = 0
    self.lastSpawnValue = nil
    self.sameSpawnStreak = 0
    self.lastProbabilities = BaseProbabilities(self.config)
    self.lastDebug = nil
    self.runStartedAt = now or 0
end

---@param profile table
function SpawnManager:ImportProfile(profile)
    if type(profile) ~= "table" then return end
    self.profile.completedRuns = math.max(0, math.floor(tonumber(profile.completedRuns) or 0))
    self.profile.averageRunDuration = math.max(0, tonumber(profile.averageRunDuration) or 0)
    self.profile.shortGameStreak = math.max(0, math.floor(tonumber(profile.shortGameStreak) or 0))
end

function SpawnManager:ExportProfile()
    return {
        version = self.config.persistence.version,
        completedRuns = self.profile.completedRuns,
        averageRunDuration = self.profile.averageRunDuration,
        shortGameStreak = self.profile.shortGameStreak,
    }
end

---@param value integer
---@param now number|nil
function SpawnManager:RecordLaunch(value, now)
    self.recentLaunches[#self.recentLaunches + 1] = {
        value = value,
        time = now or 0,
        mergeCount = 0,
    }
    while #self.recentLaunches > self.config.history.launchWindow do
        table.remove(self.recentLaunches, 1)
    end
end

---@param value integer
---@param now number|nil
function SpawnManager:RecordMerge(value, now)
    local timestamp = now or 0
    if #self.recentLaunches > 0 then
        local latestLaunch = self.recentLaunches[#self.recentLaunches]
        latestLaunch.mergeCount = latestLaunch.mergeCount + 1
    end

    if self.lastMergeTime and timestamp - self.lastMergeTime <= self.config.history.comboWindowSeconds then
        self.combo = self.combo + 1
    else
        self.combo = 1
    end
    self.lastMergeTime = timestamp
    self.recentMergeTimes[#self.recentMergeTimes + 1] = timestamp
end

---@param now number|nil
---@return number duration
---@return boolean wasShort
function SpawnManager:RecordGameOver(now)
    local duration = math.max(1, (now or 0) - (self.runStartedAt or 0))
    local assist = self.config.failureAssist
    local oldCount = self.profile.completedRuns
    local oldAverage = self.profile.averageRunDuration
    local isShort = oldCount >= assist.minimumHistoricalGames
        and oldAverage > 0
        and duration < oldAverage * assist.shortGameRatio

    self.profile.shortGameStreak = isShort and (self.profile.shortGameStreak + 1) or 0
    self.profile.completedRuns = oldCount + 1
    self.profile.averageRunDuration = (oldAverage * oldCount + duration) / self.profile.completedRuns
    return duration, isShort
end

---@param now number|nil
function SpawnManager:PruneHistory(now)
    local cutoff = (now or 0) - self.config.history.recentMergeWindowSeconds
    while #self.recentMergeTimes > 0 and self.recentMergeTimes[1] < cutoff do
        table.remove(self.recentMergeTimes, 1)
    end
end

---@param state table
---@param now number|nil
---@return table
function SpawnManager:BuildMetrics(state, now)
    self:PruneHistory(now)
    local successfulLaunches = 0
    local consecutiveMisses = 0
    for _, launch in ipairs(self.recentLaunches) do
        if launch.mergeCount > 0 then successfulLaunches = successfulLaunches + 1 end
    end
    for i = #self.recentLaunches, 1, -1 do
        if self.recentLaunches[i].mergeCount > 0 then break end
        consecutiveMisses = consecutiveMisses + 1
    end

    local launchWindow = self.config.history.launchWindow
    local noMergeLastTen = #self.recentLaunches >= launchWindow and successfulLaunches == 0
    local dryPressure = Clamp(consecutiveMisses / launchWindow, 0, 1)
    if self.lastMergeTime then
        dryPressure = math.max(dryPressure, Clamp(((now or 0) - self.lastMergeTime) / self.config.history.staleMergeSeconds, 0, 1))
    elseif #self.recentLaunches > 0 then
        dryPressure = math.max(dryPressure, Clamp(((now or 0) - self.recentLaunches[1].time) / self.config.history.staleMergeSeconds, 0, 1))
    end

    local currentCombo = self.combo
    local timeSinceMerge = self.lastMergeTime and math.max(0, (now or 0) - self.lastMergeTime) or math.huge
    if timeSinceMerge > self.config.history.comboWindowSeconds then currentCombo = 0 end

    local performance = self.config.performance
    local highestBaselineLevel = math.log(math.max(2, performance.highestValueBaseline), 2)
    local highestTargetLevel = math.log(math.max(performance.highestValueBaseline, performance.highestValueForMaxPressure), 2)
    local highestCurrentLevel = math.log(math.max(2, tonumber(state.highestValue) or 2), 2)
    local highestPressure = Clamp(
        (highestCurrentLevel - highestBaselineLevel) / math.max(1, highestTargetLevel - highestBaselineLevel),
        0,
        1
    )
    local scorePressure = Clamp((tonumber(state.score) or 0) / performance.scoreForMaxPressure, 0, 1)
    local performancePressure = Clamp(
        currentCombo / performance.comboForMaxPressure * performance.comboContribution
        + #self.recentMergeTimes / performance.recentMergesForMaxPressure * performance.recentMergeContribution
        + scorePressure * performance.scoreContribution
        + highestPressure * performance.highestValueContribution,
        0,
        1
    )

    local failure = self.config.failureAssist
    local failurePressure = math.max(
        Clamp(consecutiveMisses / failure.consecutiveMissesForFullAssist, 0, 1),
        Clamp(self.profile.shortGameStreak / failure.shortGamesForAssist, 0, 1)
    )

    local occupancy = Clamp(tonumber(state.boardOccupancy) or 0, 0, 1)
    local boardConfig = self.config.board
    local boardPressure = SmoothStep((occupancy - boardConfig.pressureStart)
        / math.max(0.001, boardConfig.criticalOccupancy - boardConfig.pressureStart))
    if state.nearFailure then boardPressure = 1 end

    return {
        boardOccupancy = occupancy,
        highestValue = math.max(2, tonumber(state.highestValue) or 2),
        score = math.max(0, tonumber(state.score) or 0),
        boardCounts = state.boardCounts or {},
        nearFailure = state.nearFailure == true,
        recentLaunchCount = #self.recentLaunches,
        successfulLaunches = successfulLaunches,
        recentMergeCount = #self.recentMergeTimes,
        timeSinceMerge = timeSinceMerge,
        combo = currentCombo,
        consecutiveMisses = consecutiveMisses,
        noMergeLastTen = noMergeLastTen,
        dryPressure = dryPressure,
        boardPressure = boardPressure,
        performancePressure = performancePressure,
        failurePressure = failurePressure,
        shortGameStreak = self.profile.shortGameStreak,
        averageRunDuration = self.profile.averageRunDuration,
    }
end

---@param state table
---@param now number|nil
---@return integer
---@return table
function SpawnManager:ChooseNext(state, now)
    local config = self.config
    local metrics = self:BuildMetrics(state or {}, now or 0)
    local weights = {}
    local factors = {}

    local dryPressure = tonumber(metrics.dryPressure) or 0
    local boardPressure = tonumber(metrics.boardPressure) or 0
    local performancePressure = tonumber(metrics.performancePressure) or 0
    local failurePressure = tonumber(metrics.failurePressure) or 0

    local boardSuppression = tonumber(config.performance.boardPressureSuppression) or 0.82
    local assistSuppression = tonumber(config.performance.failureAssistSuppression) or 0.72
    local effectivePerformance = performancePressure
        * (1 - boardPressure * boardSuppression)
        * (1 - failurePressure * assistSuppression)

    for _, value in ipairs(config.pool) do
        local count = tonumber(metrics.boardCounts[value]) or 0
        ---@type number
        local opportunity = 1.0
        if count == 1 then
            opportunity = tonumber(config.mergeOpportunity.oneMatchingBlockFactor) or 1
        elseif count >= 2 then
            local pairFactor = tonumber(config.mergeOpportunity.pairFactor) or 1
            local extraFactor = tonumber(config.mergeOpportunity.extraMatchingBlockFactor) or 0
            local maxExtra = tonumber(config.mergeOpportunity.maxExtraMatchingBlocks) or 3
            opportunity = pairFactor + math.min(maxExtra, count - 2) * extraFactor
        end
        local dryBoost = tonumber(config.mergeOpportunity.noMergeAssistBoost) or 0
        opportunity = 1 + (opportunity - 1) * (1 + dryPressure * dryBoost)
        if count > 0 then
            local assistBoost = tonumber(config.mergeOpportunity.failureAssistBoost) or 0
            opportunity = opportunity * (1 + failurePressure * assistBoost)
        end
        opportunity = math.min(tonumber(config.mergeOpportunity.maxFactor) or 2.85, opportunity)

        local spaceSafety = Lerp(1, config.board.safetyFactors[value] or 1, boardPressure)
        local performance = Lerp(1, config.performance.factors[value] or 1, effectivePerformance)
        local failureAssist = Lerp(1, config.failureAssist.factors[value] or 1, failurePressure)
        local disturbance = 1 + (math.random() * 2 - 1) * config.randomness.perturbation
        local repeatGuard = 1
        if value == self.lastSpawnValue and self.sameSpawnStreak >= config.randomness.repeatStreakThreshold then
            repeatGuard = config.randomness.repeatWeightFactor
        end

        factors[value] = {
            opportunity = opportunity,
            spaceSafety = spaceSafety,
            performance = performance,
            failureAssist = failureAssist,
            disturbance = disturbance,
            repeatGuard = repeatGuard,
        }
        weights[value] = (config.baseWeights[value] or 0)
            * opportunity
            * spaceSafety
            * performance
            * failureAssist
            * disturbance
            * repeatGuard
    end

    local targetProbabilities = Normalize(weights, config.pool)
    local smoothed = {}
    for _, value in ipairs(config.pool) do
        local previous = self.lastProbabilities[value] or targetProbabilities[value]
        local maxStep = config.randomness.maximumProbabilityStep
        smoothed[value] = Clamp(targetProbabilities[value], previous - maxStep, previous + maxStep)
    end
    local probabilities = ApplyProbabilityBounds(
        Normalize(smoothed, config.pool),
        config.pool,
        config.randomness.minimumProbability,
        config.randomness.maximumProbability
    )

    local roll = math.random()
    ---@type number
    local cumulative = 0
    local selected = config.pool[#config.pool] or 2
    for _, value in ipairs(config.pool) do
        cumulative = cumulative + probabilities[value]
        if roll <= cumulative then
            selected = value
            break
        end
    end

    if selected == self.lastSpawnValue then
        self.sameSpawnStreak = self.sameSpawnStreak + 1
    else
        self.lastSpawnValue = selected
        self.sameSpawnStreak = 1
    end
    self.lastProbabilities = probabilities
    self.lastDebug = {
        selected = selected,
        roll = roll,
        probabilities = CopyMap(probabilities),
        targetProbabilities = CopyMap(targetProbabilities),
        weights = CopyMap(weights),
        factors = factors,
        metrics = metrics,
    }

    if config.debug.printSelections then
        print(string.format(
            "[SpawnManager] next=%d | 2=%.1f%% 4=%.1f%% 8=%.1f%% 16=%.1f%% | occ=%.1f%% combo=%d misses=%d",
            selected,
            probabilities[2] * 100,
            probabilities[4] * 100,
            probabilities[8] * 100,
            probabilities[16] * 100,
            metrics.boardOccupancy * 100,
            metrics.combo,
            metrics.consecutiveMisses
        ))
    end
    return selected, self.lastDebug
end

function SpawnManager:GetDebugSnapshot()
    return self.lastDebug
end

return SpawnManager
