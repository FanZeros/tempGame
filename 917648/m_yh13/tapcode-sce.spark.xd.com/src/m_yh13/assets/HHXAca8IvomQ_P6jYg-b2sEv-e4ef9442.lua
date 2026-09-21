local Config = require("diggin.Config")
local WorldTree = require("diggin.WorldTree")
local AbyssPassives = require("diggin.AbyssPassives")
local AbyssInscriptions = require("diggin.AbyssInscriptions")

local AbyssRunTools = {}
local Synergies = require("diggin.AbyssSynergies")

AbyssRunTools.MAX_SLOTS = 5
AbyssRunTools.MAX_LEVEL = 5

-- Cycle-normalized S2 balance.  Large multi-hit/AoE tools pay a small damage
-- or cadence tax, while narrow and utility-heavy tools receive compensation.
-- Keeping the profile in one table makes the draft text, combat logic and
-- regression tests agree instead of hiding one-off multipliers in effects.
AbyssRunTools.BALANCE = {
    DynamiteActive = { damage = 1.08, cooldown = 0.96 },
    Shrapnel = { damage = 0.65, cooldown = 1.10 },
    Boomerang = { damage = 1.32, cooldown = 0.86 },
    DrillMissiles = { damage = 1.12, cooldown = 0.94 },
    BouncingBall = { damage = 1.30, cooldown = 0.86 },
    BulletWorms = { damage = 1.36, cooldown = 0.84 },
    DrillDrones = { damage = 1.12, cooldown = 0.94 },
    SpinningPickaxe = { damage = 1.28, cooldown = 0.88 },
    ShockwaveActive = { damage = 1.24, cooldown = 0.88 },
    starcore_bomb = { damage = 0.92, cooldown = 1.05 },
    magma_lance = { damage = 0.90, cooldown = 1.05 },
    crystal_saw = { damage = 0.90, cooldown = 1.05 },
    amber_swarm = { damage = 1.08, cooldown = 0.95 },
    prism_borer = { damage = 1.08, cooldown = 0.95 },
    void_mine = { damage = 1.25, cooldown = 0.90 },
    echo_charge = { damage = 1.15, cooldown = 0.92 },
    magnetic_harpoon = { damage = 1.30, cooldown = 0.90 },
    rift_beacon = { damage = 1.12, cooldown = 0.90 },
    root_aegis = { cooldown = 0.90 },
    frost_capsule = { cooldown = 0.90 },
    phoenix_fuel = { cooldown = 0.90 },
    chronobloom = { cooldown = 0.90 },
}

local CAPSTONE_BASE_TOOL = {
    AbyssBombardment = "DynamiteActive", ShardTyphoon = "Shrapnel",
    FallingPickaxe = "Boomerang", MeteorDrillArray = "DrillMissiles",
    SingularityDrill = "BouncingBall", TermiteDrones = "DrillDrones",
    Molenir = "ShockwaveActive", TheWorm = "BulletWorms",
}

local CAPSTONE_INTERNAL_AMOUNT = {
    AbyssBombardment = true, ShardTyphoon = true,
    MeteorDrillArray = true, SingularityDrill = true,
}

local function balanceFor(key)
    return AbyssRunTools.BALANCE[CAPSTONE_BASE_TOOL[key] or key] or {}
end

AbyssRunTools.DEFINITIONS = {
    { node = "DynamiteActive", name = "爆破炸弹", description = "周期性投掷炸弹，造成大范围钻头伤害", color = Config.Palette.orange },
    { node = "ShockwaveActive", name = "震荡波", description = "周期性释放环形冲击，击碎周围矿层", color = Config.Palette.gold },
    { node = "Shrapnel", name = "爆裂弹片", description = "向钻探方向发射多枚穿矿弹片", color = Config.Palette.orange },
    { node = "Boomerang", name = "回旋镐", description = "投出后返回，来回切割矿层与怪物", color = Config.Palette.cyan },
    { node = "DrillMissiles", name = "钻头导弹", description = "从上方落下并爆破目标区域", color = Config.Palette.red },
    { node = "BouncingBall", name = "弹跳钻球", description = "在矿层间反弹并持续造成钻头伤害", color = Config.Palette.purple },
    { node = "BulletWorms", name = "子弹蠕虫", description = "连续射出钻地蠕虫，贯穿前方矿层", color = Config.Palette.green },
    { node = "DrillDrones", name = "钻地无人机", description = "召唤常驻无人机自动寻找并钻击目标", color = Config.Palette.cyan },
    { node = "SpinningPickaxe", name = "旋转镐阵", description = "召唤常驻旋转镐保护并切割周围目标", color = Config.Palette.gold },
}

for _, itemId in ipairs(WorldTree.ITEM_ORDER) do
    local item = WorldTree.ITEMS[itemId]
    if item then
        AbyssRunTools.DEFINITIONS[#AbyssRunTools.DEFINITIONS + 1] = {
            key = itemId,
            itemId = itemId,
            name = item.name,
            description = item.description,
            color = item.color,
            icon = item.icon,
            iconIndex = item.iconIndex,
            worldTreeOnly = true,
        }
    end
end

local BY_KEY = {}
local EVOLUTION_BY_TOOL = {
    DynamiteActive = "AbyssBombardment",
    Shrapnel = "ShardTyphoon",
    Boomerang = "FallingPickaxe",
    DrillMissiles = "MeteorDrillArray",
    BouncingBall = "SingularityDrill",
    DrillDrones = "TermiteDrones",
    ShockwaveActive = "Molenir",
    BulletWorms = "TheWorm",
}

local EVOLUTION_ORDER = {
    "AbyssBombardment", "ShardTyphoon", "FallingPickaxe", "MeteorDrillArray",
    "SingularityDrill", "TermiteDrones", "Molenir", "TheWorm",
}

AbyssRunTools.EVOLUTION_RECIPES = {
    { capstone = "AbyssBombardment", iconNode = "AbyssBombardment", name = "裂界轰天雷", baseTool = "DynamiteActive", baseName = "爆破炸弹",
        recipe = "爆破炸弹 Lv.5 + 锻造进度 3", effect = "双轮重型轰炸，继承道具伤害、范围、冷却、暴击与传奇一击。" },
    { capstone = "ShardTyphoon", iconNode = "ShardTyphoon", name = "万刃矿暴", baseTool = "Shrapnel", baseName = "爆裂弹片",
        recipe = "爆裂弹片 Lv.5 + 锻造进度 3", effect = "释放高密度穿矿弹幕，继承数量、速度、伤害与暴击。" },
    { capstone = "FallingPickaxe", iconNode = "FallingPickaxe", name = "巨镐奔袭", baseTool = "Boomerang", baseName = "回旋镐",
        recipe = "回旋镐 Lv.5 + 锻造进度 3", effect = "巨镐高速往返，继承道具伤害、范围、暴击与传奇一击。" },
    { capstone = "MeteorDrillArray", iconNode = "MeteorDrillArray", name = "天穹钻阵", baseTool = "DrillMissiles", baseName = "钻头导弹",
        recipe = "钻头导弹 Lv.5 + 锻造进度 3", effect = "召唤密集钻头陨雨，继承数量、范围、伤害与暴击。" },
    { capstone = "SingularityDrill", iconNode = "SingularityDrill", name = "奇点钻球", baseTool = "BouncingBall", baseName = "弹跳钻球",
        recipe = "弹跳钻球 Lv.5 + 锻造进度 3", effect = "多重钻球封锁矿层，继承数量、范围、伤害与暴击。" },
    { capstone = "TermiteDrones", iconNode = "TermiteDrones", name = "无人机军团", baseTool = "DrillDrones", baseName = "钻地无人机",
        recipe = "钻地无人机 Lv.5 + 锻造进度 3", effect = "无人机扩编为军团，继承数量、攻击速度、伤害与暴击。" },
    { capstone = "Molenir", iconNode = "Molenir", name = "鼹神之锤", baseTool = "ShockwaveActive", baseName = "震荡波",
        recipe = "震荡波 Lv.5 + 锻造进度 3", effect = "周期召唤鼹神重锤，继承范围、冷却、伤害与传奇一击。" },
    { capstone = "TheWorm", iconNode = "TheWorm", name = "地龙王", baseTool = "BulletWorms", baseName = "子弹蠕虫",
        recipe = "子弹蠕虫 Lv.5 + 锻造进度 3", effect = "蠕虫进化为地龙王，继承数量、攻速、伤害与暴击。" },
}

for _, definition in ipairs(AbyssRunTools.DEFINITIONS) do
    definition.key = definition.key or definition.node
    definition.maxLevel = AbyssRunTools.MAX_LEVEL
    definition.icon = definition.icon or (Config.Paths.generatedRoot .. "skill_icons/" .. definition.node .. ".png")
    BY_KEY[definition.key] = definition
end

function AbyssRunTools.GetDefinition(key)
    return BY_KEY[key]
end

function AbyssRunTools.GetRecipeCodex()
    return AbyssRunTools.EVOLUTION_RECIPES
end

function AbyssRunTools.GetLevel(abyss, key)
    local definition = BY_KEY[key]
    if definition and definition.itemId then
        return math.max(0, math.floor(tonumber(abyss and abyss.runItems and abyss.runItems[definition.itemId]) or 0))
    end
    return math.max(0, math.floor(tonumber(abyss and abyss.runTools and abyss.runTools[key]) or 0))
end

function AbyssRunTools.GetSlotCount(abyss)
    local count = 0
    for _, definition in ipairs(AbyssRunTools.DEFINITIONS) do
        if AbyssRunTools.GetLevel(abyss, definition.key) > 0 then count = count + 1 end
    end
    return count
end

function AbyssRunTools.IsUnlocked(abyss, node)
    return AbyssRunTools.GetLevel(abyss, node) > 0
end

function AbyssRunTools.IsEvolved(abyss, node)
    return abyss and abyss.runToolEvolutions and abyss.runToolEvolutions[node] ~= nil
end

function AbyssRunTools.GetEvolutionForTool(node)
    return EVOLUTION_BY_TOOL[node]
end

function AbyssRunTools.GetToolForEvolution(capstone)
    for node, evolved in pairs(EVOLUTION_BY_TOOL) do
        if evolved == capstone then return node end
    end
    return nil
end

function AbyssRunTools.GetEvolutionCount(abyss)
    local count = 0
    for _, capstone in ipairs(EVOLUTION_ORDER) do
        if abyss and abyss.runCapstones and abyss.runCapstones[capstone] then count = count + 1 end
    end
    return count
end

function AbyssRunTools.GetEvolutionTotal()
    return #EVOLUTION_ORDER
end

function AbyssRunTools.GetEvolutionCandidates(abyss)
    local result = {}
    for node, capstone in pairs(EVOLUTION_BY_TOOL) do
        if AbyssRunTools.GetLevel(abyss, node) >= AbyssRunTools.MAX_LEVEL
            and not (abyss.runCapstones or {})[capstone] then
            result[#result + 1] = capstone
        end
    end
    table.sort(result)
    return result
end

function AbyssRunTools.MarkEvolved(abyss, node, capstone)
    if EVOLUTION_BY_TOOL[node] ~= capstone then return false end
    abyss.runToolEvolutions = abyss.runToolEvolutions or {}
    abyss.runToolEvolutions[node] = capstone
    return true
end

function AbyssRunTools.GetDamageMultiplier(abyss, key)
    local innate = 1 + math.max(0, AbyssRunTools.GetLevel(abyss, key) - 1) * 0.25
    return innate * (balanceFor(key).damage or 1)
        * (1 + AbyssPassives.GetStat(abyss, "damage_pct") / 100)
        * (1 + Synergies.Get(abyss, key, "damage"))
        * AbyssInscriptions.GetDamageMultiplier(abyss, key)
end

function AbyssRunTools.GetCooldownMultiplier(abyss, key)
    local innate = math.max(0.6, 1 - math.max(0, AbyssRunTools.GetLevel(abyss, key) - 1) * 0.1)
    local multiplier = innate * (balanceFor(key).cooldown or 1)
        * math.max(0.35, 1 - AbyssPassives.GetStat(abyss, "cooldown_pct") / 100)
        * (1 - Synergies.Get(abyss, key, "cooldown"))
        * AbyssInscriptions.GetCooldownMultiplier(abyss, key)
    return math.max(Config.Abyss.minToolCooldownMultiplier or 0.30, multiplier)
end

function AbyssRunTools.ApplyCooldownFloor(baseCooldown, cooldown)
    baseCooldown = math.max(0, tonumber(baseCooldown) or 0)
    cooldown = math.max(0, tonumber(cooldown) or baseCooldown)
    return math.max(baseCooldown * (Config.Abyss.minToolCooldownMultiplier or 0.30), cooldown)
end

function AbyssRunTools.GetAmountBonus(abyss, key)
    return math.floor(math.max(0, AbyssRunTools.GetLevel(abyss, key) - 1) / 2)
        + Synergies.Get(abyss, key, "amount")
        + AbyssPassives.GetAmountBonus(abyss) + AbyssInscriptions.GetAmountBonus(abyss, key)
end

function AbyssRunTools.GetCapstoneCastCount(abyss, capstone)
    if CAPSTONE_INTERNAL_AMOUNT[capstone] then return 1 end
    return 1 + AbyssRunTools.GetAmountBonus(abyss, capstone)
end

function AbyssRunTools.GetSizeMultiplier(abyss, key)
    return (1 + AbyssPassives.GetStat(abyss, "size_pct") / 100)
        * AbyssInscriptions.GetSizeMultiplier(abyss, key)
end

function AbyssRunTools.GetRangeMultiplier(abyss, key)
    return (1 + AbyssPassives.GetStat(abyss, "range_pct") / 100)
        * (1 + Synergies.Get(abyss, key, "range"))
        * AbyssInscriptions.GetRangeMultiplier(abyss, key)
end

function AbyssRunTools.GetAttackSpeedMultiplier(abyss, key)
    return (1 + AbyssPassives.GetStat(abyss, "attack_speed_pct") / 100)
        * (1 + Synergies.Get(abyss, key, "speed"))
        * AbyssInscriptions.GetSpeedMultiplier(abyss, key)
end

function AbyssRunTools.GetLuck(abyss, key)
    return AbyssPassives.GetStat(abyss, "luck") + AbyssInscriptions.GetStat(abyss, key, "luck")
end

function AbyssRunTools.ResolveDamage(app, key, baseDamage)
    if not app or not app.isAbyssRun or not app.abyss then return baseDamage, false, false end
    local abyss = app.abyss
    local damage = baseDamage * AbyssRunTools.GetDamageMultiplier(abyss, key)
    local luck = AbyssRunTools.GetLuck(abyss, key)
    local criticalChance = math.max(0, app.state:GetGeneralStat("critical_chance")
        + AbyssPassives.GetStat(abyss, "critical_chance")
        + AbyssInscriptions.GetStat(abyss, key, "critical_chance"))
    local legendaryChance = math.max(0, AbyssPassives.GetStat(abyss, "legendary_chance")
        + AbyssInscriptions.GetStat(abyss, key, "legendary_chance") + luck * 0.02)
    local critical = math.random() * 100 < criticalChance
    local legendary = math.random() * 100 < legendaryChance
    if critical then
        damage = damage * app.state:GetGeneralStat("critical_damage_multiplier")
            * (1 + AbyssPassives.GetStat(abyss, "critical_damage_pct") / 100)
    end
    if legendary then damage = damage * 4 end
    return damage, critical, legendary
end

local function choiceOption(abyss, definition)
    local level = AbyssRunTools.GetLevel(abyss, definition.key)
    local synergyText
    for _, recipe in ipairs(Synergies.RECIPES) do
        if recipe.tool == definition.key then
            local passive = AbyssPassives.GetDefinition(recipe.passive)
            synergyText = "联动：" .. passive.name .. " Lv.2"
            break
        end
    end
    return {
        id = definition.key,
        node = definition.node,
        itemId = definition.itemId,
        name = definition.name,
        description = definition.description,
        upgradeText = level == 0 and "新增一槽" or "提升道具等级；冷却缩短",
        synergyText = synergyText,
        color = definition.color,
        icon = definition.icon,
        iconIndex = definition.iconIndex,
        runTool = true,
        slotType = definition.itemId and "树具" or "道具",
        level = level,
        nextLevel = math.min(AbyssRunTools.MAX_LEVEL, level + 1),
        maxLevel = AbyssRunTools.MAX_LEVEL,
    }
end

function AbyssRunTools.MakeChoice(state, abyss, completedFloor)
    if type(state) == "table" and state.runTools then
        completedFloor, abyss, state = abyss, state, nil
    end
    local slots = AbyssRunTools.GetSlotCount(abyss)
    local candidates = {}
    for _, definition in ipairs(AbyssRunTools.DEFINITIONS) do
        local level = AbyssRunTools.GetLevel(abyss, definition.key)
        local available = not definition.worldTreeOnly or (state and WorldTree.IsItemUnlocked(state, definition.itemId))
        if available and ((level > 0 and level < AbyssRunTools.MAX_LEVEL)
            or (level == 0 and slots < AbyssRunTools.MAX_SLOTS)) then
            candidates[#candidates + 1] = definition
        end
    end
    if #candidates == 0 then return nil end

    local serial = math.max(1, math.floor(tonumber(abyss.toolChoiceSerial) or 1))
    local start = ((serial * 4 + completedFloor * 3 - 1) % #candidates) + 1
    local options = {}
    for offset = 0, math.min(2, #candidates - 1) do
        options[#options + 1] = choiceOption(abyss, candidates[((start + offset - 1) % #candidates) + 1])
    end
    for _, reward in ipairs(AbyssPassives.GetRewardOptions()) do
        if #options >= 3 then break end
        options[#options + 1] = reward
    end
    abyss.toolChoiceSerial = serial + 1
    return {
        kind = "tool",
        floor = completedFloor,
        title = "第 " .. tostring(completedFloor) .. " 层 · 道具三选一",
        options = options,
    }
end

function AbyssRunTools.MakeHardcoreStarterChoice(state, abyss)
    local choice = AbyssRunTools.MakeChoice(state, abyss, 1)
    if not choice then return nil end
    choice.hardcoreStarter = true
    choice.title = "硬核起步 · 先选一件道具"
    return choice
end

function AbyssRunTools.Apply(app, abyss, key)
    local definition = BY_KEY[key]
    if not definition then return false end
    local oldLevel = AbyssRunTools.GetLevel(abyss, key)
    if oldLevel >= AbyssRunTools.MAX_LEVEL then return false end
    if oldLevel == 0 and AbyssRunTools.GetSlotCount(abyss) >= AbyssRunTools.MAX_SLOTS then return false end
    if definition.worldTreeOnly and not WorldTree.IsItemUnlocked(app.state, definition.itemId) then return false end

    abyss.runTools = abyss.runTools or {}
    abyss.runItems = abyss.runItems or {}
    if definition.itemId then
        abyss.runItems[definition.itemId] = oldLevel + 1
    else
        abyss.runTools[definition.node] = oldLevel + 1
        app.activeTimers = app.activeTimers or {}
        app.activeTimers[definition.node] = 0
    end
    abyss.forgeProgress = math.min(3, (abyss.forgeProgress or 0) + 1)
    local result = choiceOption({
        runTools = definition.node and { [definition.node] = oldLevel } or {},
        runItems = definition.itemId and { [definition.itemId] = oldLevel } or {},
    }, definition)
    result.firstUnlock = oldLevel == 0
    return true, result
end

return AbyssRunTools
