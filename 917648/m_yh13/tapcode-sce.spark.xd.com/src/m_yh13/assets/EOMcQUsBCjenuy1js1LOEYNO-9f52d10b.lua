local Config = require("diggin.Config")
local Util = require("diggin.Util")
local WorldTree = require("diggin.WorldTree")
local AbyssDraft = require("diggin.AbyssDraft")
local AbyssLoot = require("diggin.AbyssLoot")
local AbyssRunTools = require("diggin.AbyssRunTools")
local AbyssInscriptions = require("diggin.AbyssInscriptions")

local AbyssItems = {}

local ITEM_ORDER = {
    { id = "starcore_bomb", cooldown = 9, firstDelay = 2.5 },
    { id = "magma_lance", cooldown = 7.5, firstDelay = 2.8 },
    { id = "crystal_saw", cooldown = 6.5, firstDelay = 2 },
    { id = "amber_swarm", cooldown = 7, firstDelay = 4 },
    { id = "prism_borer", cooldown = 8, firstDelay = 3 },
    { id = "chain_drill", cooldown = 9.5, firstDelay = 4 },
    { id = "root_aegis", cooldown = 20, firstDelay = 0 },
    { id = "void_mine", cooldown = 11, firstDelay = 4 },
    { id = "frost_capsule", cooldown = 15, firstDelay = 6 },
    { id = "phoenix_fuel", cooldown = 24, firstDelay = 8 },
    { id = "chronobloom", cooldown = 18, firstDelay = 8 },
    { id = "echo_charge", cooldown = 10, firstDelay = 4 },
    { id = "magnetic_harpoon", cooldown = 8.5, firstDelay = 3 },
    { id = "rift_beacon", cooldown = 16, firstDelay = 6 },
}
AbyssItems.ITEM_ORDER = ITEM_ORDER

function AbyssItems.GetLevel(abyss, itemId)
    local value = abyss and abyss.runItems and abyss.runItems[itemId]
    if value == true then return 1 end
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function isOwned(abyss, itemId)
    return AbyssItems.GetLevel(abyss, itemId) > 0
end

local function baseItemPower(app, abyss)
    return WorldTree.GetWorldItemPowerMultiplier(app.state)
        * (1 + AbyssDraft.GetStat(abyss, "item_power_pct") / 100)
        * (1 + AbyssLoot.GetBonus(app.state, "item_power_pct") / 100)
end

local function itemDamage(app, abyss, itemId, baseDamage)
    local mastery = 1 + WorldTree.GetStat(app.state, itemId .. "_power_pct") / 100
    return AbyssRunTools.ResolveDamage(app, itemId, baseDamage * baseItemPower(app, abyss) * mastery)
end

local function itemRangeMultiplier(state, itemId)
    return 1 + WorldTree.GetStat(state, itemId .. "_range_pct") / 100
end

local function damageEnemies(app, x, y, radius, damage, toolKey)
    local tower = app.abyss and app.abyss.tower
    if not tower or not tower.DamageEnemy then return end
    local execute = AbyssInscriptions.GetStat(app.abyss, toolKey, "execute_pct")
    for index = #(tower.enemies or {}), 1, -1 do
        local enemy = tower.enemies[index]
        if Util.Length(enemy.x - x, enemy.y - y) <= radius + (enemy.size or 0) * 0.5 then
            local finalDamage = damage
            if execute > 0 and enemy.hp / math.max(1, enemy.maxHp) <= 0.35 then
                finalDamage = finalDamage * (1 + execute / 100)
            end
            tower:DamageEnemy(app, app.abyss, index, finalDamage, toolKey)
        end
    end
end

local function addBlast(app, x, y, radius, damage, color, source, critical, legendary)
    local toolKey = AbyssInscriptions.NormalizeKey(source)
    radius = radius * AbyssRunTools.GetSizeMultiplier(app.abyss, toolKey)
    local lifetime = AbyssInscriptions.GetStat(app.abyss, toolKey, "lifetime_pct")
    if lifetime > 0 then damage = damage * (1 + lifetime * 0.25 / 100) end
    local function applyRaw(rawX, rawY, rawRadius, rawDamage, visualAlpha)
        app.effects[#app.effects + 1] = {
            kind = "explosion", x = rawX, y = rawY, radius = rawRadius,
            toolVisual = toolKey, visualScale = 1,
            critical = critical == true, legendary = legendary == true,
            life = 0.48, maxLife = 0.48, alpha = visualAlpha or 1,
        }
        app.world:DamageArea(rawX, rawY, rawRadius, rawDamage, function(tile)
            app:OnTileDestroyed(tile, source)
        end, toolKey)
        damageEnemies(app, rawX, rawY, rawRadius, rawDamage, toolKey)
    end
    applyRaw(x, y, radius, damage, 1)
    local blastPct = AbyssInscriptions.GetStat(app.abyss, toolKey, "blast_pct")
    if blastPct > 0 then applyRaw(x, y, radius * 0.62, damage * blastPct / 100, 0.72) end
    local critBlast = critical and AbyssInscriptions.GetStat(app.abyss, toolKey, "crit_blast_pct") or 0
    if critBlast > 0 then applyRaw(x, y, radius * 0.48, damage * critBlast / 100, 0.75) end
    local returning = AbyssInscriptions.GetStat(app.abyss, toolKey, "return_damage_pct")
    if returning > 0 then
        applyRaw(Util.Lerp(x, app.player.x, 0.55), Util.Lerp(y, app.player.y, 0.55),
            radius * 0.72, damage * (0.45 + returning / 100), 0.66)
    end
    local ricochets = math.min(3, AbyssInscriptions.GetStat(app.abyss, toolKey, "ricochet"))
    for index = 1, ricochets do
        local side = index % 2 == 0 and -1 or 1
        applyRaw(x + side * (radius + 8) * index, y + (radius * 0.55) * index,
            radius * 0.48, damage * 0.28, 0.55)
    end
    if AbyssInscriptions.GetStat(app.abyss, toolKey, "homing") > 0 then
        local nearest, nearestDistance
        for _, enemy in ipairs(app.abyss.tower and app.abyss.tower.enemies or {}) do
            local distance = Util.Length(enemy.x - x, enemy.y - y)
            if not nearestDistance or distance < nearestDistance then nearest, nearestDistance = enemy, distance end
        end
        if nearest and nearestDistance <= 130 then
            applyRaw(nearest.x, nearest.y, radius * 0.5, damage * 0.5, 0.6)
        end
    end
    local chains = math.min(2, AbyssInscriptions.GetStat(app.abyss, toolKey, "chain_hits"))
    if chains > 0 and app.abyss.tower then
        local candidates = {}
        for _, enemy in ipairs(app.abyss.tower.enemies or {}) do
            local distance = Util.Length(enemy.x - x, enemy.y - y)
            if distance > radius then candidates[#candidates + 1] = { enemy = enemy, distance = distance } end
        end
        table.sort(candidates, function(a, b) return a.distance < b.distance end)
        for index = 1, math.min(chains, #candidates) do
            applyRaw(candidates[index].enemy.x, candidates[index].enemy.y, radius * 0.4,
                damage * 0.42, 0.55)
        end
    end
    app:AddBurst(x, y, color, 12)
    app:AddBurst(x, y, Config.Palette.gold, 5)
    if legendary then app:AddBurst(x, y, Config.Palette.purple, 10) end
    app:KickCamera(math.min(5, 1.8 + radius * 0.035), 0.3)
end

local function aimedPoint(app, distance, lateral)
    local angle = app.aimAngle or math.pi * 0.5
    local dx, dy = math.cos(angle), math.sin(angle)
    return app.player.x + dx * distance - dy * (lateral or 0),
        app.player.y + dy * distance + dx * (lateral or 0)
end

local function playExplosion(app, volume)
    if app.audio and app.audio.PlaySfx then
        app.audio:PlaySfx(Config.Audio.explosion, volume or 0.6, 0.96 + math.random() * 0.08)
    end
end

local function triggerStarcore(app, abyss)
    local aimX = math.cos(app.aimAngle or math.pi * 0.5)
    local aimY = math.sin(app.aimAngle or math.pi * 0.5)
    local damage, critical, legendary = itemDamage(app, abyss, "starcore_bomb",
        app.state:GetGeneralStat("drill_damage") * 10)
    local count = 1 + AbyssRunTools.GetAmountBonus(abyss, "starcore_bomb")
    local radius = 42 * AbyssRunTools.GetRangeMultiplier(abyss, "starcore_bomb")
    for index = 1, count do
        local offset = (index - (count + 1) * 0.5) * 22
        local x = app.player.x + aimX * 62 - aimY * offset
        local y = app.player.y + aimY * 62 + aimX * offset
        addBlast(app, x, y, radius, damage, Config.Palette.red, "world_tree_starcore", critical, legendary)
    end
    if legendary then app:ShowToast("传奇一击 ×4 · 星核爆钻", Config.Palette.gold, 1.3) end
    if abyss.OnWorldItemTriggered then abyss:OnWorldItemTriggered(app, "starcore_bomb", damage) end
    app:ShowToast("世界树道具 · 星核爆钻", Config.Palette.red, 1.6)
    playExplosion(app, 0.72)
end

local function triggerAmberSwarm(app, abyss)
    local damage, critical, legendary = itemDamage(app, abyss, "amber_swarm",
        app.state:GetGeneralStat("drill_damage") * 3.5)
    local count = 3 + AbyssRunTools.GetAmountBonus(abyss, "amber_swarm")
    local radius = 18 * AbyssRunTools.GetRangeMultiplier(abyss, "amber_swarm")
    for index = 1, count do
        local angle = (app.aimAngle or math.pi * 0.5) + (index - 2) * 0.7
        local distance = 42 + index * 18
        local x = app.player.x + math.cos(angle) * distance
        local y = app.player.y + math.sin(angle) * distance
        addBlast(app, x, y, radius, damage, Config.Palette.cyan, "world_tree_amber_swarm", critical, legendary)
    end
    if legendary then app:ShowToast("传奇一击 ×4 · 琥珀蜂群", Config.Palette.gold, 1.3) end
    if abyss.OnWorldItemTriggered then abyss:OnWorldItemTriggered(app, "amber_swarm", damage) end
    app:ShowToast("世界树道具 · 琥珀蜂群", Config.Palette.cyan, 1.6)
    playExplosion(app, 0.48)
end

local function triggerChronobloom(app, abyss)
    local mastery = 1 + WorldTree.GetStat(app.state, "chronobloom_power_pct") / 100
    mastery = mastery * (1 + math.max(0, AbyssItems.GetLevel(abyss, "chronobloom") - 1) * 0.15)
    abyss.chronobloomTime = (4 + WorldTree.GetStat(app.state, "chronobloom_duration")) * mastery
        * AbyssRunTools.GetRangeMultiplier(abyss, "chronobloom")
    app:AddBurst(app.player.x, app.player.y, Config.Palette.purple, 18)
    if abyss.OnWorldItemTriggered then abyss:OnWorldItemTriggered(app, "chronobloom", baseItemPower(app, abyss)) end
    app:ShowToast(string.format("世界树道具 · 时光花 · 巨物减速 %.1fs", abyss.chronobloomTime),
        Config.Palette.purple, 2)
end

local function triggerMagmaLance(app, abyss)
    local damage, critical, legendary = itemDamage(app, abyss, "magma_lance",
        app.state:GetGeneralStat("drill_damage") * 5.2)
    local count = 3 + AbyssRunTools.GetAmountBonus(abyss, "magma_lance")
    local radius = 17 * AbyssRunTools.GetRangeMultiplier(abyss, "magma_lance")
    for index = 1, count do
        local x, y = aimedPoint(app, 34 + index * 24, 0)
        addBlast(app, x, y, radius, damage, Config.Palette.orange, "world_tree_magma_lance", critical, legendary)
    end
    app:ShowToast("世界树道具 · 熔脉长枪贯穿", Config.Palette.orange, 1.5)
    playExplosion(app, 0.52)
end

local function triggerCrystalSaw(app, abyss)
    local damage, critical, legendary = itemDamage(app, abyss, "crystal_saw",
        app.state:GetGeneralStat("drill_damage") * 3.4)
    local count = 4 + AbyssRunTools.GetAmountBonus(abyss, "crystal_saw")
    local masteryRange = itemRangeMultiplier(app.state, "crystal_saw")
    local orbit = 35 * AbyssRunTools.GetRangeMultiplier(abyss, "crystal_saw") * masteryRange
    for index = 1, count do
        local angle = (index - 1) / count * math.pi * 2 + (abyss.time or 0)
        addBlast(app, app.player.x + math.cos(angle) * orbit, app.player.y + math.sin(angle) * orbit,
            15 * masteryRange, damage, Config.Palette.cyan, "world_tree_crystal_saw", critical, legendary)
    end
end

local function triggerPrismBorer(app, abyss)
    local damage, critical, legendary = itemDamage(app, abyss, "prism_borer",
        app.state:GetGeneralStat("drill_damage") * 4.2)
    local count = 3 + AbyssRunTools.GetAmountBonus(abyss, "prism_borer")
    local masteryRange = itemRangeMultiplier(app.state, "prism_borer")
    local spread = 18
    for index = 1, count do
        local x, y = aimedPoint(app, 72 * AbyssRunTools.GetRangeMultiplier(abyss, "prism_borer") * masteryRange,
            (index - (count + 1) * 0.5) * spread)
        addBlast(app, x, y, 18 * masteryRange, damage, Config.Palette.cyan, "world_tree_prism_borer", critical, legendary)
    end
end

local function triggerChainDrill(app, abyss)
    local damage, critical, legendary = itemDamage(app, abyss, "chain_drill",
        app.state:GetGeneralStat("drill_damage") * 5)
    local tower = abyss.tower
    local hits = 0
    for index = #(tower and tower.enemies or {}), 1, -1 do
        local enemy = tower.enemies[index]
        addBlast(app, enemy.x, enemy.y, 15 * AbyssRunTools.GetRangeMultiplier(abyss, "chain_drill"), damage, Config.Palette.purple,
            "world_tree_chain_drill", critical, legendary)
        hits = hits + 1
        if hits >= 3 + AbyssRunTools.GetAmountBonus(abyss, "chain_drill") then break end
    end
    if hits == 0 then
        local x, y = aimedPoint(app, 65, 0)
        addBlast(app, x, y, 25 * AbyssRunTools.GetRangeMultiplier(abyss, "chain_drill"), damage, Config.Palette.purple, "world_tree_chain_drill", critical, legendary)
    end
end

local function triggerVoidMine(app, abyss)
    local damage, critical, legendary = itemDamage(app, abyss, "void_mine",
        app.state:GetGeneralStat("drill_damage") * 8 * (1 + AbyssRunTools.GetAmountBonus(abyss, "void_mine") * 0.2))
    local radius = 44 * AbyssRunTools.GetRangeMultiplier(abyss, "void_mine")
        * itemRangeMultiplier(app.state, "void_mine")
    addBlast(app, app.player.x, app.player.y + 34, radius, damage, Config.Palette.purple,
        "world_tree_void_mine", critical, legendary)
    if abyss.tower then
        for _, enemy in ipairs(abyss.tower.enemies or {}) do
            if Util.Length(enemy.x - app.player.x, enemy.y - (app.player.y + 34)) <= radius then
            enemy.x = Util.Lerp(enemy.x, app.player.x, 0.3)
            enemy.y = Util.Lerp(enemy.y, app.player.y + 34, 0.3)
            end
        end
    end
end

local function triggerFrostCapsule(app, abyss)
    local duration = 3.5 * (1 + WorldTree.GetStat(app.state, "frost_capsule_power_pct") / 100)
        * (1 + math.max(0, AbyssItems.GetLevel(abyss, "frost_capsule") - 1) * 0.15)
        * AbyssRunTools.GetRangeMultiplier(abyss, "frost_capsule")
    abyss.chronobloomTime = math.max(abyss.chronobloomTime or 0, duration)
    for _, enemy in ipairs(abyss.tower and abyss.tower.enemies or {}) do
        enemy.slowTime = math.max(enemy.slowTime or 0, duration)
    end
    app:AddBurst(app.player.x, app.player.y, Config.Palette.cyan, 22)
    app:ShowToast(string.format("霜封胶囊 · 怪物减速 %.1fs", duration), Config.Palette.cyan, 1.8)
end

local function triggerPhoenixFuel(app, abyss)
    local mastery = 1 + WorldTree.GetStat(app.state, "phoenix_fuel_power_pct") / 100
    local restored = app.maxFuel * 0.09 * mastery * AbyssRunTools.GetDamageMultiplier(abyss, "phoenix_fuel")
        * (1 + require("diggin.AbyssSynergies").Get(abyss, "phoenix_fuel", "support"))
    require("diggin.RunCombatStats").Record(app.combatStats, "phoenix_fuel", "fuel", restored, app.maxFuel - app.fuel)
    app.fuel = math.min(app.maxFuel, app.fuel + restored)
    app:AddBurst(app.player.x, app.player.y, Config.Palette.gold, 18)
    app:ShowToast(string.format("涅槃燃芯 · 燃料 +%.1f", restored), Config.Palette.gold, 1.6)
end

local function triggerEchoCharge(app, abyss)
    local damage, critical, legendary = itemDamage(app, abyss, "echo_charge",
        app.state:GetGeneralStat("drill_damage") * 5.4)
    for index = 1, 2 + AbyssRunTools.GetAmountBonus(abyss, "echo_charge") do
        local x, y = aimedPoint(app, 44 + index * 28, (index % 2 == 0) and 10 or -10)
        addBlast(app, x, y, 24 * AbyssRunTools.GetRangeMultiplier(abyss, "echo_charge"), damage, Config.Palette.orange, "world_tree_echo_charge", critical, legendary)
    end
    playExplosion(app, 0.58)
end

local function triggerMagneticHarpoon(app, abyss)
    local x, y = aimedPoint(app, 58, 0)
    local range = 76 * AbyssRunTools.GetRangeMultiplier(abyss, "magnetic_harpoon")
        * itemRangeMultiplier(app.state, "magnetic_harpoon")
    for _, pickup in ipairs(abyss.tower and abyss.tower.pickups or {}) do
        if Util.Length(pickup.x - x, pickup.y - y) <= range then
            pickup.x, pickup.y = Util.Lerp(pickup.x, app.player.x, 0.65), Util.Lerp(pickup.y, app.player.y, 0.65)
        end
    end
    for _, enemy in ipairs(abyss.tower and abyss.tower.enemies or {}) do
        if Util.Length(enemy.x - x, enemy.y - y) <= range then
            enemy.x, enemy.y = Util.Lerp(enemy.x, x, 0.55), Util.Lerp(enemy.y, y, 0.55)
        end
    end
    local damage, critical, legendary = itemDamage(app, abyss, "magnetic_harpoon",
        app.state:GetGeneralStat("drill_damage") * 4.5)
    addBlast(app, x, y, 25 * AbyssRunTools.GetRangeMultiplier(abyss, "magnetic_harpoon"),
        damage * (1 + AbyssRunTools.GetAmountBonus(abyss, "magnetic_harpoon") * 0.2), Config.Palette.gold, "world_tree_magnetic_harpoon", critical, legendary)
end

local function triggerRiftBeacon(app, abyss)
    local tower = abyss.tower
    if not tower then return end
    tower.exitRevealed = true
    local x = tower.exitX * Config.TILE_SIZE + Config.TILE_SIZE * 0.5
    local y = tower.exitY * Config.TILE_SIZE + Config.TILE_SIZE * 0.5
    local damage, critical, legendary = itemDamage(app, abyss, "rift_beacon",
        app.state:GetGeneralStat("drill_damage") * 12)
    addBlast(app, x, y, 20 * AbyssRunTools.GetRangeMultiplier(abyss, "rift_beacon"),
        damage * (1 + AbyssRunTools.GetAmountBonus(abyss, "rift_beacon") * 0.2), Config.Palette.cyan, "world_tree_rift_beacon", critical, legendary)
    app:ShowToast("裂隙信标 · 已定位并轰击出口核心", Config.Palette.cyan, 1.8)
end

function AbyssItems.Start(app, abyss)
    abyss.itemTimers = {}
    abyss.chronobloomTime = 0
    abyss.aegisMaxCharges = 0
    abyss.aegisCharges = 0
    abyss.aegisRecharge = 0
end

function AbyssItems.GetCooldown(state, itemId, abyss)
    for _, definition in ipairs(ITEM_ORDER) do
        if definition.id == itemId then
            local multiplier = WorldTree.GetWorldItemCooldownMultiplier(state)
                * math.max(0.3, 1 - AbyssDraft.GetStat(abyss, "item_cooldown_pct") / 100)
                * math.max(0.3, 1 - AbyssLoot.GetBonus(state, "item_cooldown_pct") / 100)
                * AbyssRunTools.GetCooldownMultiplier(abyss, itemId)
                * math.max(0.35, 1 - WorldTree.GetStat(state, itemId .. "_cooldown_pct") / 100)
            multiplier = multiplier / AbyssRunTools.GetAttackSpeedMultiplier(abyss, itemId)
            if itemId == "root_aegis" then
                multiplier = multiplier * math.max(0.3,
                    1 - WorldTree.GetStat(state, "aegis_recharge_pct") / 100)
            end
            return AbyssRunTools.ApplyCooldownFloor(definition.cooldown, definition.cooldown * multiplier)
        end
    end
    return 0
end

function AbyssItems.Activate(app, abyss, itemId)
    if not isOwned(abyss, itemId) then return false end
    for _, definition in ipairs(ITEM_ORDER) do
        if definition.id == itemId then
            if itemId == "root_aegis" then
                local oldMax = abyss.aegisMaxCharges or 0
                abyss.aegisMaxCharges = math.max(1, 1 + math.floor(WorldTree.GetStat(app.state, "aegis_charge_bonus"))
                    + math.floor(WorldTree.GetStat(app.state, "root_aegis_power_pct") / 30)
                    + AbyssRunTools.GetAmountBonus(abyss, itemId))
                abyss.aegisCharges = math.min(abyss.aegisMaxCharges,
                    math.max(abyss.aegisCharges or 0, oldMax > 0 and oldMax or abyss.aegisMaxCharges))
                abyss.aegisRecharge = 0
            elseif abyss.itemTimers[itemId] == nil then
                abyss.itemTimers[itemId] = definition.firstDelay
            end
            return true
        end
    end
    return false
end

function AbyssItems.Unlock(app, abyss, itemId)
    abyss.runItems = abyss.runItems or {}
    if AbyssItems.GetLevel(abyss, itemId) <= 0 then abyss.runItems[itemId] = 1 end
    return AbyssItems.Activate(app, abyss, itemId)
end

function AbyssItems.Update(app, abyss, dt)
    abyss.chronobloomTime = math.max(0, (abyss.chronobloomTime or 0) - dt)

    if isOwned(abyss, "root_aegis") then
        local desiredCharges = math.max(1, 1 + math.floor(WorldTree.GetStat(app.state, "aegis_charge_bonus"))
            + math.floor(WorldTree.GetStat(app.state, "root_aegis_power_pct") / 30)
            + AbyssRunTools.GetAmountBonus(abyss, "root_aegis"))
        if desiredCharges > (abyss.aegisMaxCharges or 0) then
            local gained = desiredCharges - (abyss.aegisMaxCharges or 0)
            abyss.aegisMaxCharges = desiredCharges
            abyss.aegisCharges = math.min(desiredCharges, (abyss.aegisCharges or 0) + gained)
        end
    end

    if isOwned(abyss, "root_aegis")
        and (abyss.aegisCharges or 0) < (abyss.aegisMaxCharges or 0) then
        abyss.aegisRecharge = math.max(0, (abyss.aegisRecharge or 0) - dt)
        if abyss.aegisRecharge <= 0 then
            abyss.aegisCharges = math.min(abyss.aegisMaxCharges, abyss.aegisCharges + 1)
            if abyss.aegisCharges < abyss.aegisMaxCharges then
                abyss.aegisRecharge = AbyssItems.GetCooldown(app.state, "root_aegis", abyss)
            end
        end
    end

    for _, definition in ipairs(ITEM_ORDER) do
        local id = definition.id
        if id ~= "root_aegis" and isOwned(abyss, id) then
            local remaining = math.max(0, (abyss.itemTimers[id] or 0) - dt)
            abyss.itemTimers[id] = remaining
            if remaining <= 0 then
                AbyssInscriptions.OnToolTriggered(app, id)
                if id == "chronobloom" or id == "frost_capsule" or id == "phoenix_fuel" then
                    require("diggin.WorldItemVisuals").Emit(app, id)
                end
                if id == "starcore_bomb" then triggerStarcore(app, abyss)
                elseif id == "magma_lance" then triggerMagmaLance(app, abyss)
                elseif id == "crystal_saw" then triggerCrystalSaw(app, abyss)
                elseif id == "amber_swarm" then triggerAmberSwarm(app, abyss)
                elseif id == "prism_borer" then triggerPrismBorer(app, abyss)
                elseif id == "chain_drill" then triggerChainDrill(app, abyss)
                elseif id == "void_mine" then triggerVoidMine(app, abyss)
                elseif id == "frost_capsule" then triggerFrostCapsule(app, abyss)
                elseif id == "phoenix_fuel" then triggerPhoenixFuel(app, abyss)
                elseif id == "chronobloom" then triggerChronobloom(app, abyss)
                elseif id == "echo_charge" then triggerEchoCharge(app, abyss)
                elseif id == "magnetic_harpoon" then triggerMagneticHarpoon(app, abyss)
                elseif id == "rift_beacon" then triggerRiftBeacon(app, abyss) end
                abyss.itemTimers[id] = AbyssItems.GetCooldown(app.state, id, abyss)
            end
        end
    end
end

function AbyssItems.TryPreventCatch(app, abyss)
    if not isOwned(abyss, "root_aegis") or (abyss.aegisCharges or 0) <= 0 then
        return false
    end
    abyss.aegisCharges = abyss.aegisCharges - 1
    require("diggin.WorldItemVisuals").Emit(app, "root_aegis")
    AbyssInscriptions.OnToolTriggered(app, "root_aegis")
    if abyss.aegisRecharge <= 0 then
        abyss.aegisRecharge = AbyssItems.GetCooldown(app.state, "root_aegis", abyss)
    end
    local push = 52 + WorldTree.GetStat(app.state, "aegis_push")
    abyss.monsterY = abyss.monsterY - push
    if abyss.OnWorldItemTriggered then
        abyss:OnWorldItemTriggered(app, "root_aegis", baseItemPower(app, abyss))
    end
    app:AddBurst(app.player.x, app.player.y - 14, Config.Palette.gold, 24)
    app:KickCamera(4.5, 0.38)
    app:ShowToast("世界树道具 · 生命根盾挡下吞噬并击退巨物", Config.Palette.gold, 2.5)
    return true
end

function AbyssItems.GetHudEntries(state, abyss)
    local entries = {}
    for _, definition in ipairs(ITEM_ORDER) do
        local item = WorldTree.ITEMS[definition.id]
        if item and isOwned(abyss, definition.id) then
            local status
            local remaining
            if definition.id == "root_aegis" then
                remaining = abyss.aegisRecharge or 0
                status = string.format("%d/%d", abyss.aegisCharges or 0, abyss.aegisMaxCharges or 0)
                if (abyss.aegisCharges or 0) <= 0 then status = string.format("%.1f", remaining) end
            elseif definition.id == "chronobloom" and (abyss.chronobloomTime or 0) > 0 then
                remaining = 0
                status = string.format("%.1fs", abyss.chronobloomTime)
            else
                remaining = abyss.itemTimers[definition.id] or 0
                status = remaining <= 0 and "就绪" or string.format("%.1f", remaining)
            end
            entries[#entries + 1] = {
                id = definition.id,
                name = item.name,
                icon = item.icon,
                iconIndex = item.iconIndex,
                color = item.color,
                status = status,
                level = AbyssItems.GetLevel(abyss, definition.id),
                remaining = remaining,
                cooldown = AbyssItems.GetCooldown(state, definition.id, abyss),
            }
        end
    end
    return entries
end

return AbyssItems
