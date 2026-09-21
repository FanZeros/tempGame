local Config = require("diggin.Config")
local Util = require("diggin.Util")

local AbyssInscriptions = {}

AbyssInscriptions.MAX_SLOTS_PER_TOOL = 3

local BASIC = 80
local SPECIALIST = 150
local CORE = 220

AbyssInscriptions.DEFINITIONS = {
    { id = "power", name = "强攻", description = "该道具伤害 +22%", iconIndex = 1, baseCost = BASIC,
        stats = { damage_pct = 22 } },
    { id = "haste", name = "急速", description = "冷却 -10% · 攻击速度 +10%", iconIndex = 2, baseCost = BASIC,
        stats = { cooldown_pct = 10, speed_pct = 10 } },
    { id = "expanse", name = "扩域", description = "范围 +18% · 体积 +12%", iconIndex = 3, baseCost = BASIC,
        stats = { range_pct = 18, size_pct = 12 } },
    { id = "multiply", name = "增殖", description = "数量 +1 · 单体伤害 -10%", iconIndex = 4, baseCost = BASIC,
        stats = { amount_bonus = 1 }, damageMultiplier = 0.90 },
    { id = "precision", name = "精准", description = "暴击率 +8%", iconIndex = 5, baseCost = BASIC,
        stats = { critical_chance = 8 } },
    { id = "fortune", name = "幸运", description = "传奇一击率 +2% · 幸运 +12", iconIndex = 6, baseCost = BASIC,
        stats = { legendary_chance = 2, luck = 12 } },
    { id = "efficiency", name = "节能", description = "发动时缓慢返还燃料，每秒最多触发一次", iconIndex = 7,
        baseCost = BASIC, stats = { fuel_restore_pct = 0.35 } },

    { id = "fission", name = "裂变", description = "额外分裂2个攻击体 · 单体伤害 -28%", iconIndex = 8,
        baseCost = CORE, category = "trajectory", offensive = true,
        stats = { amount_bonus = 2 }, damageMultiplier = 0.72 },
    { id = "blast_core", name = "爆芯", description = "命中附加爆破 · 范围 +24%", iconIndex = 9,
        baseCost = CORE, category = "payload", offensive = true,
        stats = { range_pct = 24, blast_pct = 45 } },
    { id = "chain", name = "雷链", description = "攻击可传导2次 · 单体伤害 -15%", iconIndex = 10,
        baseCost = CORE, category = "payload", offensive = true,
        stats = { chain_hits = 2, amount_bonus = 1 }, damageMultiplier = 0.85 },
    { id = "echo", name = "回声", description = "追加一次较弱回响 · 冷却 +12%", iconIndex = 11,
        baseCost = CORE, category = "trigger", stats = { amount_bonus = 1 },
        cooldownMultiplier = 1.12, damageMultiplier = 0.82 },
    { id = "pierce", name = "穿界", description = "持续时间 +45% · 伤害 +10%", iconIndex = 12,
        baseCost = SPECIALIST, category = "trajectory", projectile = true,
        stats = { lifetime_pct = 45, damage_pct = 10 } },
    { id = "returning", name = "归返", description = "飞行攻击会折返 · 返程伤害 +20%", iconIndex = 13,
        baseCost = SPECIALIST, category = "trajectory", projectile = true,
        stats = { return_damage_pct = 20 } },
    { id = "ricochet", name = "折跃", description = "撞击矿层时最多折射3次", iconIndex = 14,
        baseCost = SPECIALIST, category = "trajectory", projectile = true,
        stats = { ricochet = 3 } },
    { id = "hunter_eye", name = "猎眼", description = "飞行攻击追踪附近怪物 · 速度 +15%", iconIndex = 15,
        baseCost = SPECIALIST, category = "trajectory", projectile = true,
        stats = { homing = 1, speed_pct = 15 } },
    { id = "colossus", name = "巨像", description = "体积 +50% · 伤害 +60% · 冷却 +30%", iconIndex = 16,
        baseCost = CORE, category = "form", offensive = true,
        stats = { size_pct = 50, damage_pct = 60 }, cooldownMultiplier = 1.30 },
    { id = "swarm", name = "蜂群", description = "数量 +3 · 体积 -25% · 单体伤害 -38%", iconIndex = 17,
        baseCost = CORE, category = "form", offensive = true,
        stats = { amount_bonus = 3, size_pct = -25 }, damageMultiplier = 0.62 },
    { id = "frost", name = "寒狱", description = "发动时短暂冻结巨物追击", iconIndex = 18,
        baseCost = SPECIALIST, stats = { freeze_seconds = 0.8 } },
    { id = "corrosion", name = "熔蚀", description = "对矿层与装甲怪伤害 +30%", iconIndex = 19,
        baseCost = SPECIALIST, offensive = true, stats = { damage_pct = 30 } },
    { id = "siphon", name = "汲能", description = "发动时恢复少量燃料，每秒最多一次", iconIndex = 20,
        baseCost = SPECIALIST, stats = { fuel_restore_pct = 0.65 } },
    { id = "execute", name = "斩决", description = "对残血目标增伤 · 基础伤害 +18%", iconIndex = 21,
        baseCost = SPECIALIST, offensive = true, stats = { damage_pct = 18, execute_pct = 35 } },
    { id = "violent", name = "暴烈", description = "暴击会附带一次不可递归的小型爆破", iconIndex = 22,
        baseCost = CORE, offensive = true, stats = { critical_chance = 5, crit_blast_pct = 35 } },
    { id = "resonance", name = "同调", description = "发动后使其他道具冷却缩短0.55秒", iconIndex = 23,
        baseCost = SPECIALIST, stats = { sync_seconds = 0.55 } },
    { id = "bloodfire", name = "血燃", description = "每次发动消耗1.2%燃料 · 伤害 +65%", iconIndex = 24,
        baseCost = CORE, offensive = true, stats = { fuel_cost_pct = 1.2 }, damageMultiplier = 1.65 },
    { id = "chaos", name = "混沌", description = "伤害在75%～185%间波动，幸运偏向高值", iconIndex = 25,
        baseCost = CORE, offensive = true, stats = { chaos = 1 } },
}

local BY_ID = {}
for _, definition in ipairs(AbyssInscriptions.DEFINITIONS) do
    definition.color = definition.color or (definition.baseCost == CORE and Config.Palette.purple
        or (definition.baseCost == SPECIALIST and Config.Palette.cyan or Config.Palette.gold))
    definition.icon = Config.Paths.abyssInscriptionAtlas
    BY_ID[definition.id] = definition
end

local KEY_ALIASES = {
    dynamite = "DynamiteActive", shockwave = "ShockwaveActive", shrapnel_debris = "Shrapnel",
    pickarang = "Boomerang", drill_missile = "DrillMissiles", bouncing_ball = "BouncingBall",
    bullet_worms = "BulletWorms", drill_drones = "DrillDrones", pickaxe_orbit = "SpinningPickaxe",
    AbyssBombardment = "DynamiteActive", ShardTyphoon = "Shrapnel", FallingPickaxe = "Boomerang",
    MeteorDrillArray = "DrillMissiles", SingularityDrill = "BouncingBall", TermiteDrones = "DrillDrones",
    Molenir = "ShockwaveActive", TheWorm = "BulletWorms",
    world_tree_starcore = "starcore_bomb", world_tree_amber_swarm = "amber_swarm",
    world_tree_magma_lance = "magma_lance", world_tree_crystal_saw = "crystal_saw",
    world_tree_prism_borer = "prism_borer", world_tree_chain_drill = "chain_drill",
    world_tree_void_mine = "void_mine", world_tree_echo_charge = "echo_charge",
    world_tree_magnetic_harpoon = "magnetic_harpoon", world_tree_rift_beacon = "rift_beacon",
}

local PROJECTILE_TOOLS = {
    Shrapnel = true, Boomerang = true, DrillMissiles = true, BouncingBall = true,
    BulletWorms = true, DrillDrones = true, SpinningPickaxe = true, amber_swarm = true,
    magma_lance = true, crystal_saw = true, prism_borer = true, chain_drill = true,
    echo_charge = true, magnetic_harpoon = true, rift_beacon = true,
}

local NON_OFFENSIVE_TOOLS = {
    root_aegis = true, chronobloom = true, frost_capsule = true, phoenix_fuel = true,
}

-- Utility items must never roll a rune whose advertised benefit they cannot
-- consume. This keeps all 25 inscriptions honest for the ten World Tree items
-- instead of silently selling damage/critical stats to a shield or fuel heal.
local UTILITY_ALLOWED = {
    root_aegis = { haste = true, multiply = true, efficiency = true, frost = true, siphon = true, resonance = true },
    chronobloom = { haste = true, expanse = true, efficiency = true, frost = true, siphon = true, resonance = true },
    frost_capsule = { haste = true, expanse = true, efficiency = true, frost = true, siphon = true, resonance = true },
    phoenix_fuel = { haste = true, efficiency = true, frost = true, siphon = true, resonance = true },
}

local SLOT_FACTORS = { 1, 1.6, 2.5 }

function AbyssInscriptions.NormalizeKey(key)
    return KEY_ALIASES[key] or key
end

function AbyssInscriptions.GetDefinition(id)
    return BY_ID[id]
end

function AbyssInscriptions.IsProjectileTool(key)
    return PROJECTILE_TOOLS[AbyssInscriptions.NormalizeKey(key)] == true
end

function AbyssInscriptions.GetInstalled(abyss, key)
    key = AbyssInscriptions.NormalizeKey(key)
    local installed = abyss and abyss.inscriptions and abyss.inscriptions[key]
    return type(installed) == "table" and installed or {}
end

function AbyssInscriptions.GetSlotCount(abyss, key)
    return #AbyssInscriptions.GetInstalled(abyss, key)
end

function AbyssInscriptions.HasCategory(abyss, key, category)
    if not category or category == "basic" then return false end
    for _, id in ipairs(AbyssInscriptions.GetInstalled(abyss, key)) do
        if BY_ID[id] and BY_ID[id].category == category then return true end
    end
    return false
end

function AbyssInscriptions.Has(abyss, key, inscriptionId)
    for _, id in ipairs(AbyssInscriptions.GetInstalled(abyss, key)) do
        if id == inscriptionId then return true end
    end
    return false
end

function AbyssInscriptions.GetStat(abyss, key, statId)
    local total = 0
    for _, id in ipairs(AbyssInscriptions.GetInstalled(abyss, key)) do
        local definition = BY_ID[id]
        total = total + (definition and definition.stats and definition.stats[statId] or 0)
    end
    return total
end

function AbyssInscriptions.GetDamageMultiplier(abyss, key)
    local multiplier = 1 + AbyssInscriptions.GetStat(abyss, key, "damage_pct") / 100
    for _, id in ipairs(AbyssInscriptions.GetInstalled(abyss, key)) do
        multiplier = multiplier * (BY_ID[id].damageMultiplier or 1)
    end
    if AbyssInscriptions.GetStat(abyss, key, "chaos") > 0 then
        local luck = AbyssInscriptions.GetStat(abyss, key, "luck")
        local roll = math.random()
        roll = Util.Clamp(roll + luck / 240, 0, 1)
        multiplier = multiplier * (0.75 + roll * 1.10)
    end
    return math.max(0.2, multiplier)
end

function AbyssInscriptions.GetCooldownMultiplier(abyss, key)
    local multiplier = math.max(0.5, 1 - AbyssInscriptions.GetStat(abyss, key, "cooldown_pct") / 100)
    for _, id in ipairs(AbyssInscriptions.GetInstalled(abyss, key)) do
        multiplier = multiplier * (BY_ID[id].cooldownMultiplier or 1)
    end
    return multiplier
end

function AbyssInscriptions.GetRangeMultiplier(abyss, key)
    return math.max(0.5, 1 + AbyssInscriptions.GetStat(abyss, key, "range_pct") / 100)
end

function AbyssInscriptions.GetSizeMultiplier(abyss, key)
    return math.max(0.45, 1 + AbyssInscriptions.GetStat(abyss, key, "size_pct") / 100)
end

function AbyssInscriptions.GetSpeedMultiplier(abyss, key)
    return math.max(0.5, 1 + AbyssInscriptions.GetStat(abyss, key, "speed_pct") / 100)
end

function AbyssInscriptions.GetAmountBonus(abyss, key)
    return math.floor(AbyssInscriptions.GetStat(abyss, key, "amount_bonus"))
end

function AbyssInscriptions.IsCompatible(definition, key)
    key = AbyssInscriptions.NormalizeKey(key)
    local allowed = UTILITY_ALLOWED[key]
    if allowed and not allowed[definition.id] then return false end
    if definition.projectile and not PROJECTILE_TOOLS[key] then return false end
    if definition.offensive and NON_OFFENSIVE_TOOLS[key] then return false end
    return true
end

function AbyssInscriptions.GetPrice(abyss, key, inscriptionId)
    local definition = BY_ID[inscriptionId]
    if not definition then return math.huge end
    local nextSlot = math.min(AbyssInscriptions.MAX_SLOTS_PER_TOOL,
        AbyssInscriptions.GetSlotCount(abyss, key) + 1)
    return math.floor(definition.baseCost * SLOT_FACTORS[nextSlot] + 0.5)
end

local function ownedToolPairs(abyss, toolDefinitions)
    local pairs = {}
    for _, tool in ipairs(toolDefinitions or {}) do
        local key = tool.key or tool.node
        local level = tool.itemId and tonumber(abyss.runItems and abyss.runItems[tool.itemId])
            or tonumber(abyss.runTools and abyss.runTools[tool.node])
        if key and (level or 0) > 0
            and AbyssInscriptions.GetSlotCount(abyss, key) < AbyssInscriptions.MAX_SLOTS_PER_TOOL then
            for _, inscription in ipairs(AbyssInscriptions.DEFINITIONS) do
                if AbyssInscriptions.IsCompatible(inscription, key)
                    and not AbyssInscriptions.HasCategory(abyss, key, inscription.category)
                    and not AbyssInscriptions.Has(abyss, key, inscription.id) then
                    pairs[#pairs + 1] = { tool = tool, key = key, inscription = inscription }
                end
            end
        end
    end
    return pairs
end

function AbyssInscriptions.MakeShopChoice(abyss, completedFloor, toolDefinitions, offerCount, kind)
    local candidates = ownedToolPairs(abyss, toolDefinitions)
    if #candidates == 0 then return nil end
    abyss.inscriptionShopSerial = math.max(1, math.floor(tonumber(abyss.inscriptionShopSerial) or 1))
    local start = ((abyss.inscriptionShopSerial * 17 + completedFloor * 11 - 1) % #candidates) + 1
    local options, usedRunes, usedTools, usedToolCategories = {}, {}, {}, {}
    offerCount = math.max(1, math.floor(tonumber(offerCount) or 3))
    -- Prefer different tools when possible, then fill the remaining
    -- cards from the same tool so an early run with only one unlocked weapon
    -- still receives a real three-choice shop.
    for pass = 1, 2 do
        for offset = 0, #candidates - 1 do
            local candidate = candidates[((start + offset - 1) % #candidates) + 1]
            local categoryKey = candidate.key .. "|" .. tostring(candidate.inscription.category or "")
            if not usedRunes[candidate.inscription.id]
                and not usedToolCategories[categoryKey]
                and (pass == 2 or not usedTools[candidate.key]) then
                local inscription = candidate.inscription
                local cost = AbyssInscriptions.GetPrice(abyss, candidate.key, inscription.id)
                options[#options + 1] = {
                    id = "inscribe|" .. candidate.key .. "|" .. inscription.id,
                    name = inscription.name,
                    description = inscription.description,
                    color = inscription.color,
                    inscription = true,
                    inscriptionIndex = inscription.iconIndex,
                    inscriptionId = inscription.id,
                    toolKey = candidate.key,
                    toolName = candidate.tool.name,
                    cost = cost,
                }
                usedRunes[inscription.id], usedTools[candidate.key] = true, true
                usedToolCategories[categoryKey] = true
                if #options >= offerCount then break end
            end
        end
        if #options >= offerCount then break end
    end
    abyss.inscriptionShopSerial = abyss.inscriptionShopSerial + 1
    return {
        kind = kind or "inscription_shop", floor = completedFloor,
        title = "第 " .. tostring(completedFloor) .. " 层 · 商人铭刻货架",
        options = options,
    }
end

function AbyssInscriptions.ShouldOpenShop(abyss, completedFloor)
    local interval = Config.Abyss.inscriptionShopInterval
    if completedFloor < interval or completedFloor % interval ~= 0 then return false end
    abyss.inscriptionShopHandled = abyss.inscriptionShopHandled or {}
    if abyss.inscriptionShopHandled[completedFloor] then return false end
    abyss.inscriptionShopHandled[completedFloor] = true
    local forced = completedFloor == interval or abyss.inscriptionShopPity == true
    local seed = math.max(1, math.floor(tonumber(abyss.inscriptionShopSeed) or 1))
    local roll = Util.Hash01(completedFloor, seed, 8191) * 100
    local opened = forced or roll < Config.Abyss.inscriptionShopChance
    abyss.inscriptionShopPity = not opened
    return opened
end

function AbyssInscriptions.OpenShop(abyss, completedFloor, toolDefinitions)
    if not AbyssInscriptions.ShouldOpenShop(abyss, completedFloor) then return nil end
    abyss.inscriptionShopPurchases = 0
    abyss.inscriptionShopRerolls = 0
    return AbyssInscriptions.MakeShopChoice(abyss, completedFloor, toolDefinitions)
end

function AbyssInscriptions.Buy(abyss, tower, offer)
    if not offer or not offer.inscription or not tower then return false, "invalid" end
    if offer.sold then return false, "sold" end
    if (abyss.inscriptionShopPurchases or 0) >= Config.Abyss.inscriptionShopPurchaseLimit then
        return false, "limit"
    end
    local definition = AbyssInscriptions.GetDefinition(offer.inscriptionId)
    if not definition or not AbyssInscriptions.IsCompatible(definition, offer.toolKey)
        or AbyssInscriptions.HasCategory(abyss, offer.toolKey, definition.category)
        or AbyssInscriptions.Has(abyss, offer.toolKey, offer.inscriptionId)
        or AbyssInscriptions.GetSlotCount(abyss, offer.toolKey) >= AbyssInscriptions.MAX_SLOTS_PER_TOOL then
        return false, "incompatible"
    end
    local price = AbyssInscriptions.GetPrice(abyss, offer.toolKey, offer.inscriptionId)
    if (tower.coins or 0) < price then return false, price end
    tower.coins = tower.coins - price
    abyss.inscriptions = abyss.inscriptions or {}
    local key = AbyssInscriptions.NormalizeKey(offer.toolKey)
    abyss.inscriptions[key] = abyss.inscriptions[key] or {}
    abyss.inscriptions[key][#abyss.inscriptions[key] + 1] = offer.inscriptionId
    abyss.inscriptionShopPurchases = (abyss.inscriptionShopPurchases or 0) + 1
    offer.sold = true
    return true, price
end

function AbyssInscriptions.GetRerollCost(abyss)
    local costs = Config.Abyss.inscriptionShopRerollCosts
    local index = math.min(#costs, (abyss.inscriptionShopRerolls or 0) + 1)
    return costs[index]
end

function AbyssInscriptions.Reroll(abyss, tower, completedFloor, toolDefinitions)
    local cost = AbyssInscriptions.GetRerollCost(abyss)
    if not tower or (tower.coins or 0) < cost then return nil, cost end
    if (abyss.inscriptionShopPurchases or 0) >= Config.Abyss.inscriptionShopPurchaseLimit then
        return nil, cost
    end
    local merchant = abyss.choice and abyss.choice.kind == "merchant_shop"
    local replacement = AbyssInscriptions.MakeShopChoice(abyss, completedFloor, toolDefinitions,
        merchant and Config.Abyss.merchantOfferCount or 3,
        merchant and "merchant_shop" or "inscription_shop")
    if not replacement then return nil, cost end
    tower.coins = tower.coins - cost
    abyss.inscriptionShopRerolls = (abyss.inscriptionShopRerolls or 0) + 1
    return replacement, cost
end

function AbyssInscriptions.OnToolTriggered(app, key)
    if not app or not app.abyss then return end
    local abyss = app.abyss
    key = AbyssInscriptions.NormalizeKey(key)
    abyss.inscriptionRuntime = abyss.inscriptionRuntime or { fuelAt = {} }
    local runtime = abyss.inscriptionRuntime
    local now = tonumber(abyss.time) or 0
    local lastFuelAt = runtime.fuelAt[key] or -10
    if now - lastFuelAt >= 1 then
        local restore = AbyssInscriptions.GetStat(abyss, key, "fuel_restore_pct")
        if restore > 0 then
            app.fuel = math.min(app.maxFuel, app.fuel + app.maxFuel * restore / 100)
            runtime.fuelAt[key] = now
        end
    end
    local cost = AbyssInscriptions.GetStat(abyss, key, "fuel_cost_pct")
    if cost > 0 then app.fuel = math.max(1, app.fuel - app.maxFuel * cost / 100) end
    local freeze = AbyssInscriptions.GetStat(abyss, key, "freeze_seconds")
    if freeze > 0 then abyss.rootPauseTime = math.max(abyss.rootPauseTime or 0, freeze) end
    local sync = AbyssInscriptions.GetStat(abyss, key, "sync_seconds")
    if sync > 0 then
        for timerKey, remaining in pairs(app.activeTimers or {}) do
            if AbyssInscriptions.NormalizeKey(timerKey) ~= key then
                app.activeTimers[timerKey] = math.max(0, remaining - sync)
            end
        end
        for timerKey, remaining in pairs(abyss.itemTimers or {}) do
            if AbyssInscriptions.NormalizeKey(timerKey) ~= key then
                abyss.itemTimers[timerKey] = math.max(0, remaining - sync)
            end
        end
    end
end

return AbyssInscriptions
