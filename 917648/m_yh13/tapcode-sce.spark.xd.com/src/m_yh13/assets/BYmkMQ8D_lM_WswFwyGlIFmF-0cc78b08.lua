local Config = require("diggin.Config")
local Util = require("diggin.Util")
local WorldTree = require("diggin.WorldTree")
local AbyssRunTools = require("diggin.AbyssRunTools")
local AbyssDraft = require("diggin.AbyssDraft")
local AbyssInscriptions = require("diggin.AbyssInscriptions")

local ActiveEffects = {}
local addExplosion

local ACTIVE_DEFINITIONS = {
    { node = "DynamiteActive", id = "dynamite", kind = "dynamite", color = Config.Palette.orange },
    { node = "ShockwaveActive", id = "shockwave", kind = "shockwave", color = Config.Palette.gold },
    { node = "Shrapnel", id = "shrapnel_debris", kind = "projectile", spread = 1.5, speed = 125, color = Config.Palette.orange },
    { node = "Boomerang", id = "pickarang", kind = "projectile", spread = 0.5, speed = 90, color = Config.Palette.cyan },
    { node = "DrillMissiles", id = "drill_missile", kind = "projectile", spread = 0.8, speed = 145, color = Config.Palette.red },
    { node = "BouncingBall", id = "bouncing_ball", kind = "projectile", spread = 0.9, speed = 105, color = Config.Palette.purple },
    { node = "BulletWorms", id = "bullet_worms", kind = "projectile", spread = 1.1, speed = 118, color = Config.Palette.green },
}

local CAPSTONES = {
    { node = "AbyssBombardment", cooldown = 8 },
    { node = "ShardTyphoon", cooldown = 5.5 },
    { node = "FallingPickaxe", cooldown = 5 },
    { node = "MeteorDrillArray", cooldown = 6.5 },
    { node = "SingularityDrill", cooldown = 7 },
    { node = "TermiteDrones", cooldown = 1 },
    { node = "Molenir", cooldown = 5 },
    { node = "TheWorm", cooldown = 5 },
}

local function toolKeyForEffect(effectId)
    return AbyssInscriptions.NormalizeKey(effectId)
end

local function addEffect(app, effect)
    effect.kind = "active_effect"
    effect.age = effect.age or 0
    effect.maxLife = effect.maxLife or effect.life
    app.effects[#app.effects + 1] = effect
    return effect
end

local function abyssRunBonus(app, statId)
    if not app or not app.isAbyssRun or not app.state then return 0 end
    -- The state cache may be replaced by a delayed cloud-load callback while a
    -- run is active. The run's boon table is the authoritative source.
    if app.abyss then return AbyssDraft.GetStat(app.abyss, statId) end
    return tonumber((app.state.abyssRunBonuses or {})[statId]) or 0
end

local function activeDamage(app, effectId)
    local node
    for _, definition in ipairs(ACTIVE_DEFINITIONS) do
        if definition.id == effectId then node = definition.node; break end
    end
    local baseDamage = app.state:GetGeneralStat("drill_damage") * app.state:GetActiveStat(effectId, "damage") / 100
    if node and app.isAbyssRun then return AbyssRunTools.ResolveDamage(app, node, baseDamage) end
    return baseDamage, false, false
end

local function activeUnlocked(app, node)
    return app.isAbyssRun and AbyssRunTools.IsUnlocked(app.abyss, node)
            and not AbyssRunTools.IsEvolved(app.abyss, node)
        or (not app.isAbyssRun and app.state:IsNodeBought(node))
end

local function activeCooldown(app, definition)
    local cooldown = app.state:GetActiveStat(definition.id, "cooldown")
    if cooldown <= 0 then cooldown = 5 end
    if app.isAbyssRun then
        cooldown = cooldown * AbyssRunTools.GetCooldownMultiplier(app.abyss, definition.node)
    end
    return cooldown
end

local function activeAmount(app, definition)
    local amount = app.state:GetActiveStat(definition.id, "amount")
    if app.isAbyssRun then amount = amount + AbyssRunTools.GetAmountBonus(app.abyss, definition.node) end
    return math.min(16, math.max(1, amount))
end

local function tileAt(app, x, y)
    return app.world:GetTile(math.floor(x / Config.TILE_SIZE), math.floor(y / Config.TILE_SIZE))
end

local function damageTile(app, effect, source, burstCount)
    if app.isAbyssRun and app.abyss and app.abyss.tower then
        local repeatDelay = (effect.effectId == "drill_drones" or effect.effectId == "pickaxe_orbit") and 0.3 or 9999
        effect.enemyHits = effect.enemyHits or {}
        for index = #(app.abyss.tower.enemies or {}), 1, -1 do
            local enemy = app.abyss.tower.enemies[index]
            local lastHit = effect.enemyHits[enemy.id]
            if (not lastHit or (effect.age or 0) - lastHit >= repeatDelay)
                and Util.Length(effect.x - enemy.x, effect.y - enemy.y)
                    <= (effect.radius or 8) * (effect.visualScale or 1) + enemy.size * 0.5 then
                effect.enemyHits[enemy.id] = effect.age or 0
                app.abyss.tower:DamageEnemy(app, app.abyss, index, effect.damage, effect.toolKey or source)
                app:AddBurst(effect.x, effect.y, Config.Palette.cyan, 3)
            end
        end
    end
    local tile = tileAt(app, effect.x, effect.y)
    if not tile then
        effect.lastTileKey = nil
        return false
    end
    local key = tostring(tile.x) .. ":" .. tostring(tile.y)
    if app.isAbyssRun and effect.effectId == "shrapnel_debris" then
        effect.shrapnelTileHits = effect.shrapnelTileHits or {}
        if effect.shrapnelTileHits[key] then return false end
        effect.shrapnelTileHits[key] = true
    end
    if effect.lastTileKey == key then return true end
    effect.lastTileKey = key
    local critical = effect.critical == true or effect.legendary == true
    local destroyed, damagedTile = app.world:DamageTile(tile, effect.damage, false, effect.toolKey or source)
    app:AddMaterialBurst(damagedTile, burstCount or 2, critical)
    if destroyed then
        app:OnTileDestroyed(damagedTile, source)
    else
        app:AddHitFlash(damagedTile, critical)
    end
    if app.isAbyssRun and not effect.secondaryDamage and not effect.inscriptionBlastTriggered then
        local blastPct = AbyssInscriptions.GetStat(app.abyss,
            effect.toolKey or source, "blast_pct")
        local critBlastPct = effect.critical and AbyssInscriptions.GetStat(app.abyss,
            effect.toolKey or source, "crit_blast_pct") or 0
        if blastPct + critBlastPct > 0 then
            effect.inscriptionBlastTriggered = true
            addExplosion(app, effect.x, effect.y,
                math.max(14, (effect.radius or 8) * 1.6),
                effect.damage * (blastPct + critBlastPct) / 100,
                "inscription_blast", Config.Palette.orange, 1.5)
        end
    end
    return true
end

function ActiveEffects.DamageAbyssEnemies(app, x, y, radius, damage, source)
    if not app.isAbyssRun or not app.abyss or not app.abyss.tower then return 0 end
    local hits = 0
    for index = #(app.abyss.tower.enemies or {}), 1, -1 do
        local enemy = app.abyss.tower.enemies[index]
        if Util.Length(x - enemy.x, y - enemy.y) <= radius + enemy.size * 0.5 then
            app.abyss.tower:DamageEnemy(app, app.abyss, index, damage, source)
            hits = hits + 1
        end
    end
    return hits
end

local function damageArea(app, x, y, radius, damage, source)
    app.world:DamageArea(x, y, radius, damage, function(tile)
        app:OnTileDestroyed(tile, source)
    end, source)
    ActiveEffects.DamageAbyssEnemies(app, x, y, radius, damage, source)
end

addExplosion = function(app, x, y, radius, damage, source, color, strength)
    app.effects[#app.effects + 1] = {
        kind = "explosion",
        -- Visual only: damage is applied once below, never routed back to projectile procs.
        secondaryDamage = source == "inscription_blast",
        x = x,
        y = y,
        radius = radius,
        visualScale = app.isAbyssRun and AbyssRunTools.GetSizeMultiplier(app.abyss, source) or 1,
        life = 0.42,
        maxLife = 0.42,
    }
    app:AddBurst(x, y, color or Config.Palette.orange, 14)
    app:AddBurst(x, y, Config.Palette.gold, 6)
    app:KickCamera(strength or math.min(4.5, 1.8 + radius * 0.04), 0.32)
    damageArea(app, x, y, radius, damage, source)
    app.audio:PlaySfx(Config.Audio.explosion, 0.72, 0.96 + math.random() * 0.08)
end

local function findNearbyTile(app, radius)
    local distance = radius or 76
    for _ = 1, 16 do
        local angle = math.random() * math.pi * 2
        local range = math.random(22, distance)
        local x = app.player.x + math.cos(angle) * range
        local y = app.player.y + math.sin(angle) * range
        local tile = tileAt(app, x, y)
        if tile then
            return tile.x * Config.TILE_SIZE + Config.TILE_SIZE * 0.5,
                tile.y * Config.TILE_SIZE + Config.TILE_SIZE * 0.5
        end
    end
    return app.player.x + math.cos(app.aimAngle) * 48,
        app.player.y + math.sin(app.aimAngle) * 48
end

local function moveTowards(effect, targetX, targetY, speed, dt)
    local dx, dy = targetX - effect.x, targetY - effect.y
    local distance = Util.Length(dx, dy)
    if distance <= 0.001 then return distance end
    local step = math.min(distance, speed * dt)
    effect.vx, effect.vy = dx / distance * speed, dy / distance * speed
    effect.x = effect.x + dx / distance * step
    effect.y = effect.y + dy / distance * step
    return distance
end

local function spawnProjectile(app, effectId, angle, speed, damage, radius, life, color, slot, amount, critical, legendary)
    local toolKey = toolKeyForEffect(effectId)
    if app.isAbyssRun then
        life = (life or 1.8) * (1 + AbyssInscriptions.GetStat(app.abyss, toolKey, "lifetime_pct") / 100)
    end
    local effect = {
        effectId = effectId,
        toolKey = toolKey,
        x = app.player.x,
        y = app.player.y,
        vx = math.cos(angle) * speed,
        vy = math.sin(angle) * speed,
        damage = damage,
        radius = radius or 8,
        life = life or 1.8,
        r = color[1],
        g = color[2],
        b = color[3],
        slot = slot or 1,
        amount = amount or 1,
        rotation = angle,
        critical = critical == true,
        legendary = legendary == true,
        visualScale = app.isAbyssRun and AbyssRunTools.GetSizeMultiplier(app.abyss, toolKey) or 1,
    }

    if app.isAbyssRun then
        effect.inscriptionRicochets = AbyssInscriptions.GetStat(app.abyss, toolKey, "ricochet")
        effect.inscriptionHoming = AbyssInscriptions.GetStat(app.abyss, toolKey, "homing") > 0
        effect.inscriptionReturning = AbyssInscriptions.GetStat(app.abyss, toolKey, "return_damage_pct") > 0
    end

    if effectId == "pickarang" then
        effect.returnAt = math.min(0.72, effect.life * 0.45)
        effect.spinSpeed = 12
    elseif effectId == "bouncing_ball" then
        effect.life = math.max(1, app.state:GetActiveStat(effectId, "lifetime"))
        effect.maxLife = effect.life
        effect.spinSpeed = (slot % 2 == 0) and -7 or 7
    elseif effectId == "drill_missile" then
        effect.targetX = app.player.x + math.random(-170, 170)
        effect.targetY = app.player.y + math.random(-95, 105)
        effect.x = effect.targetX + math.random(-32, 32)
        effect.y = app.player.y - 164
        local dx, dy = effect.targetX - effect.x, effect.targetY - effect.y
        local length = math.max(1, Util.Length(dx, dy))
        effect.vx, effect.vy = dx / length * speed, dy / length * speed
        effect.life = 2.4
        effect.maxLife = 2.4
    end

    return addEffect(app, effect)
end

function ActiveEffects.TriggerShockwave(app, color)
    local effectId = "shockwave"
    local radius = math.max(16, app.state:GetActiveStat(effectId, "radius"))
    if app.isAbyssRun then radius = radius * AbyssRunTools.GetRangeMultiplier(app.abyss, "ShockwaveActive") end
    local damage, critical, legendary = activeDamage(app, effectId)
    addEffect(app, {
        effectId = effectId,
        x = app.player.x,
        y = app.player.y,
        radius = radius,
        damage = damage,
        life = 0.58,
        maxLife = 0.58,
        r = color[1],
        g = color[2],
        b = color[3],
        critical = critical,
        legendary = legendary,
        visualScale = app.isAbyssRun and AbyssRunTools.GetSizeMultiplier(app.abyss, "ShockwaveActive") or 1,
    })
    damageArea(app, app.player.x, app.player.y, radius, damage, effectId)
    app:AddBurst(app.player.x, app.player.y, color, 10)
    app:KickCamera(2.5, 0.28)
    app.audio:PlaySfx(Config.Audio.explosion, 0.55)
end

function ActiveEffects.TriggerProjectiles(app, effectId, amount, spread, speed, color, damageScale)
    local damage, critical, legendary = activeDamage(app, effectId)
    damage = damage * math.max(0, tonumber(damageScale) or 1)
    local radius = effectId == "drill_missile"
        and app.state:GetActiveStat(effectId, "explosion_radius") or 8
    local toolKey = toolKeyForEffect(effectId)
    if app.isAbyssRun then
        radius = radius * AbyssRunTools.GetRangeMultiplier(app.abyss, toolKey)
        speed = speed * AbyssRunTools.GetAttackSpeedMultiplier(app.abyss, toolKey)
    end
    local count = math.min(16, math.max(1, math.floor(amount)))
    for index = 1, count do
        local offset = count == 1 and 0 or ((index - 1) / (count - 1) - 0.5) * spread
        spawnProjectile(app, effectId, app.aimAngle + offset, speed, damage, radius, 1.8, color, index, count,
            critical, legendary)
    end
end

function ActiveEffects.TriggerDynamiteVolley(app, amount, color, damageScale)
    local count = math.max(1, math.floor(amount > 0 and amount or 1))
    local damage = app.state:GetGeneralStat("drill_damage") * app.state:GetActiveStat("dynamite", "damage") / 100
    local radius = math.max(16, app.state:GetActiveStat("dynamite", "radius"))
    local critical, legendary = false, false
    local visualScale = 1
    if app.isAbyssRun then
        damage, critical, legendary = AbyssRunTools.ResolveDamage(app, "DynamiteActive", damage)
        radius = radius * AbyssRunTools.GetRangeMultiplier(app.abyss, "DynamiteActive")
        visualScale = AbyssRunTools.GetSizeMultiplier(app.abyss, "DynamiteActive")
    end
    damage = damage * math.max(0, tonumber(damageScale) or 1)
    app.effects[#app.effects + 1] = {
        kind = "skill_proc", node = "DynamiteActive",
        x = app.player.x, y = app.player.y - 18, life = 0.65, maxLife = 0.65,
    }
    for index = 1, count do
        local spread = (index - (count + 1) * 0.5) * 30
        local fuse = 0.9 + (index - 1) * 0.06
        app.effects[#app.effects + 1] = {
            kind = "dynamite", x = app.player.x, y = app.player.y - 7,
            vx = spread + (math.random() - 0.5) * 18, vy = -118 - math.random() * 18,
            gravity = 240, damage = damage, radius = radius,
            rotation = (math.random() - 0.5) * 0.5,
            rotationSpeed = (math.random() < 0.5 and -1 or 1) * (6 + math.random() * 4),
            sparkTimer = 0, life = fuse, maxLife = fuse,
            r = color[1], g = color[2], b = color[3],
            critical = critical, legendary = legendary, visualScale = visualScale,
        }
    end
end

local function countEffects(app, effectId)
    local count = 0
    for _, effect in ipairs(app.effects) do
        if effect.kind == "active_effect" and effect.effectId == effectId then count = count + 1 end
    end
    return count
end

local function ensureDrillDrones(app)
    if not activeUnlocked(app, "DrillDrones") then return end
    local definition = { node = "DrillDrones", id = "drill_drones" }
    local wanted = math.max(1, math.floor(activeAmount(app, definition)))
    local existing = countEffects(app, "drill_drones")
    for index = existing + 1, wanted do
        local targetX, targetY = findNearbyTile(app, 82)
        local damage, critical, legendary = activeDamage(app, "drill_drones")
        addEffect(app, {
            effectId = "drill_drones",
            x = app.player.x + math.cos(index * 2.4) * 18,
            y = app.player.y + math.sin(index * 2.4) * 18,
            targetX = targetX,
            targetY = targetY,
            orbitAngle = index / wanted * math.pi * 2,
            slot = index,
            damage = damage,
            critical = critical,
            legendary = legendary,
            toolKey = "DrillDrones",
            radius = 8 * (app.isAbyssRun and AbyssRunTools.GetRangeMultiplier(app.abyss, "DrillDrones") or 1),
            visualScale = app.isAbyssRun and AbyssRunTools.GetSizeMultiplier(app.abyss, "DrillDrones") or 1,
            life = 9999,
            maxLife = 9999,
        })
    end
end

local function ensureOrbitingPickaxes(app)
    if not activeUnlocked(app, "SpinningPickaxe") then return end
    local definition = { node = "SpinningPickaxe", id = "pickaxe_orbit" }
    local wanted = math.max(1, math.floor(activeAmount(app, definition)))
    local existing = countEffects(app, "pickaxe_orbit")
    for index = existing + 1, wanted do
        local angle = (index - 1) / wanted * math.pi * 2
        local damage, critical, legendary = activeDamage(app, "pickaxe_orbit")
        local rangeMultiplier = app.isAbyssRun and AbyssRunTools.GetRangeMultiplier(app.abyss, "SpinningPickaxe") or 1
        addEffect(app, {
            effectId = "pickaxe_orbit",
            x = app.player.x + math.cos(angle) * 30,
            y = app.player.y + math.sin(angle) * 30,
            orbitAngle = angle,
            baseOrbitRadius = 28 + (index % 2) * 7,
            orbitRadius = (28 + (index % 2) * 7) * rangeMultiplier,
            slot = index,
            damage = damage,
            critical = critical,
            legendary = legendary,
            radius = 8 * rangeMultiplier,
            toolKey = "SpinningPickaxe",
            visualScale = app.isAbyssRun and AbyssRunTools.GetSizeMultiplier(app.abyss, "SpinningPickaxe") or 1,
            life = 9999,
            maxLife = 9999,
        })
    end
end

local function spawnCapstone(app, node, damageCompensation)
    local abyssMultiplier = app.isAbyssRun and WorldTree.GetCapstoneDamageMultiplier(app.state)
        * (1 + abyssRunBonus(app, "capstone_power_pct") / 100) or 1
    abyssMultiplier = abyssMultiplier * math.max(1, tonumber(damageCompensation) or 1)
    local speedMultiplier = app.isAbyssRun and AbyssRunTools.GetAttackSpeedMultiplier(app.abyss, node) or 1
    local rangeMultiplier = app.isAbyssRun and AbyssRunTools.GetRangeMultiplier(app.abyss, node) or 1
    local visualScale = app.isAbyssRun and AbyssRunTools.GetSizeMultiplier(app.abyss, node) or 1
    if app.isAbyssRun then AbyssInscriptions.OnToolTriggered(app, node) end
    if node == "AbyssBombardment" then
        local amount = 4 + AbyssRunTools.GetAmountBonus(app.abyss, "DynamiteActive")
        for _ = 1, 2 do
            ActiveEffects.TriggerDynamiteVolley(app, amount, Config.Palette.red, 1.8 * abyssMultiplier)
        end
    elseif node == "ShardTyphoon" then
        local amount = 11 + AbyssRunTools.GetAmountBonus(app.abyss, "Shrapnel")
        ActiveEffects.TriggerProjectiles(app, "shrapnel_debris", amount, 2.7, 175,
            Config.Palette.orange, 1.45 * abyssMultiplier)
    elseif node == "FallingPickaxe" then
        local damage, critical, legendary = AbyssRunTools.ResolveDamage(app, node,
            math.max(12, app.state:GetGeneralStat("drill_damage")
                * Config.CapstoneDamageMultipliers.FallingPickaxe * abyssMultiplier))
        addEffect(app, {
            effectId = "falling_pickaxe",
            toolKey = "Boomerang",
            x = app.player.x,
            y = app.player.y - 8,
            vx = math.cos(app.aimAngle) * 92 * speedMultiplier,
            vy = math.sin(app.aimAngle) * 92 * speedMultiplier - 58,
            gravity = 126,
            rotation = app.aimAngle,
            spinSpeed = 5.5,
            damage = damage,
            critical = critical,
            legendary = legendary,
            radius = 28 * rangeMultiplier,
            visualScale = visualScale,
            life = 1.45,
            maxLife = 1.45,
        })
    elseif node == "MeteorDrillArray" then
        local amount = 6 + AbyssRunTools.GetAmountBonus(app.abyss, "DrillMissiles")
        ActiveEffects.TriggerProjectiles(app, "drill_missile", amount, 2.4, 190,
            Config.Palette.red, 2 * abyssMultiplier)
    elseif node == "SingularityDrill" then
        local amount = 5 + AbyssRunTools.GetAmountBonus(app.abyss, "BouncingBall")
        ActiveEffects.TriggerProjectiles(app, "bouncing_ball", amount, 1.9, 145,
            Config.Palette.purple, 2.1 * abyssMultiplier)
    elseif node == "TermiteDrones" then
        local angle = app.aimAngle + (math.random() - 0.5) * 0.7
        local damage, critical, legendary = AbyssRunTools.ResolveDamage(app, node,
            math.max(8, app.state:GetGeneralStat("drill_damage")
                * Config.CapstoneDamageMultipliers.TermiteDrones * abyssMultiplier))
        addEffect(app, {
            effectId = "termite_drone",
            toolKey = "DrillDrones",
            x = app.player.x + math.random(-8, 8),
            y = app.player.y + math.random(-8, 8),
            vx = math.cos(angle) * 100 * speedMultiplier,
            vy = math.sin(angle) * 100 * speedMultiplier,
            orbitAngle = math.random() * math.pi * 2,
            damage = damage,
            critical = critical,
            legendary = legendary,
            radius = 8 * rangeMultiplier,
            visualScale = visualScale,
            life = 6,
            maxLife = 6,
        })
    elseif node == "Molenir" then
        local side = math.random() < 0.5 and -1 or 1
        local targetX, targetY = app.player.x, app.player.y
        local startX, startY = targetX + side * 230, targetY - 150
        local dx, dy = targetX - startX, targetY - startY
        local length = math.max(1, Util.Length(dx, dy))
        local damage, critical, legendary = AbyssRunTools.ResolveDamage(app, node,
            math.max(20, app.state:GetGeneralStat("drill_damage")
                * Config.CapstoneDamageMultipliers.Molenir * abyssMultiplier))
        addEffect(app, {
            effectId = "molenir",
            toolKey = "ShockwaveActive",
            x = startX,
            y = startY,
            targetX = targetX,
            targetY = targetY,
            vx = dx / length * 175 * speedMultiplier,
            vy = dy / length * 175 * speedMultiplier,
            damage = damage,
            critical = critical,
            legendary = legendary,
            radius = 56 * rangeMultiplier,
            visualScale = visualScale,
            life = 2.1,
            maxLife = 2.1,
        })
    elseif node == "TheWorm" then
        local side = math.random() < 0.5 and -1 or 1
        local damage, critical, legendary = AbyssRunTools.ResolveDamage(app, node,
            math.max(4, app.state:GetGeneralStat("drill_damage")
                * Config.CapstoneDamageMultipliers.TheWorm * abyssMultiplier))
        addEffect(app, {
            effectId = "the_worm",
            toolKey = "BulletWorms",
            x = app.player.x + side * 245,
            y = app.player.y + math.random(-88, 88),
            vx = -side * 155 * speedMultiplier,
            vy = math.random(-18, 18),
            damage = damage,
            critical = critical,
            legendary = legendary,
            radius = 22 * rangeMultiplier,
            visualScale = visualScale,
            hitTimer = 0,
            life = 3.4,
            maxLife = 3.4,
        })
    end
end


function ActiveEffects.GetCapstoneSpawnTiming(app, capstone)
    local rawCooldown = capstone.cooldown
        * (app.isAbyssRun and WorldTree.GetCapstoneCooldownMultiplier(app.state) or 1)
        * math.max(0.25, 1 - abyssRunBonus(app, "capstone_cooldown_pct") / 100)
        * (app.isAbyssRun and AbyssRunTools.GetCooldownMultiplier(app.abyss, capstone.node) or 1)
    if app.isAbyssRun then
        rawCooldown = AbyssRunTools.ApplyCooldownFloor(capstone.cooldown, rawCooldown)
    end
    if not app.isAbyssRun then return rawCooldown, 1 end
    local visualCooldown = math.max(Config.Abyss.minCapstoneVisualCooldown or 0.18, rawCooldown)
    return visualCooldown, visualCooldown / math.max(0.001, rawCooldown)
end

function ActiveEffects.UpdateActiveUpgrades(app, dt)
    app.activeTimers.DrillDrones = 0
    app.activeTimers.SpinningPickaxe = 0

    if app.drillingActive then
        ensureDrillDrones(app)
        ensureOrbitingPickaxes(app)
    end
    for _, definition in ipairs(ACTIVE_DEFINITIONS) do
        if activeUnlocked(app, definition.node) then
            local cooldown = activeCooldown(app, definition)
            app.activeTimers[definition.node] = math.max(0, (app.activeTimers[definition.node] or 0) - dt)
            if app.drillingActive and app.activeTimers[definition.node] <= 0 then
                app.activeTimers[definition.node] = cooldown
                if app.isAbyssRun then AbyssInscriptions.OnToolTriggered(app, definition.node) end
                local amount = activeAmount(app, definition)
                if definition.kind == "dynamite" then
                    app:TriggerDynamiteVolley(amount, definition.color)
                elseif definition.kind == "shockwave" then
                    ActiveEffects.TriggerShockwave(app, definition.color)
                else
                    ActiveEffects.TriggerProjectiles(app, definition.id, amount,
                        definition.spread, definition.speed, definition.color)
                end
            end
        end
    end

    for _, capstone in ipairs(CAPSTONES) do
        local normalUnlocked = not app.isAbyssRun and app.state:IsNodeBought(capstone.node)
        local abyssUnlocked = app.isAbyssRun and app.abyss and app.abyss.runCapstones
            and app.abyss.runCapstones[capstone.node] == true
        if normalUnlocked or abyssUnlocked then
            app.activeTimers[capstone.node] = math.max(0, (app.activeTimers[capstone.node] or 0) - dt)
            if app.drillingActive and app.activeTimers[capstone.node] <= 0 then
                local spawnCooldown, damageCompensation = ActiveEffects.GetCapstoneSpawnTiming(app, capstone)
                app.activeTimers[capstone.node] = spawnCooldown
                -- Swarm capstones already consume amount inside spawnCapstone.
                -- Multiplying the outer cast count as well made amount builds
                -- square their projectile count and invalidated every other
                -- passive at high level.
                local count = app.isAbyssRun
                    and AbyssRunTools.GetCapstoneCastCount(app.abyss, capstone.node) or 1
                for _ = 1, math.max(1, count) do spawnCapstone(app, capstone.node, damageCompensation) end
            end
        end
    end
end

local function updateLinear(effect, dt)
    effect.x = effect.x + (effect.vx or 0) * dt
    effect.y = effect.y + (effect.vy or 0) * dt
end

local function updateInscribedProjectile(app, effect, dt)
    if not app.isAbyssRun then return false end
    if effect.inscriptionHoming and app.abyss and app.abyss.tower then
        local nearest, nearestDistance
        for _, enemy in ipairs(app.abyss.tower.enemies or {}) do
            local distance = Util.Length(enemy.x - effect.x, enemy.y - effect.y)
            if distance < 120 and (not nearestDistance or distance < nearestDistance) then
                nearest, nearestDistance = enemy, distance
            end
        end
        if nearest then
            local speed = math.max(1, Util.Length(effect.vx or 0, effect.vy or 0))
            local dx, dy = Util.Normalize(nearest.x - effect.x, nearest.y - effect.y)
            local turn = math.min(0.22, dt * 5)
            effect.vx = Util.Lerp(effect.vx or 0, dx * speed, turn)
            effect.vy = Util.Lerp(effect.vy or 0, dy * speed, turn)
        end
    end
    if effect.inscriptionReturning and effect.effectId ~= "pickarang"
        and effect.age >= (effect.maxLife or 1) * 0.55 then
        if not effect.returnBoostApplied then
            effect.returnBoostApplied = true
            effect.damage = effect.damage * (1 + AbyssInscriptions.GetStat(app.abyss,
                effect.toolKey or effect.effectId, "return_damage_pct") / 100)
        end
        local distance = Util.Length(app.player.x - effect.x, app.player.y - effect.y)
        if distance <= 7 then return true end
        local speed = math.max(90, Util.Length(effect.vx or 0, effect.vy or 0))
        local dx, dy = Util.Normalize(app.player.x - effect.x, app.player.y - effect.y)
        effect.vx, effect.vy = dx * speed, dy * speed
    end
    return false
end

local function updateDrillDrone(app, effect, dt)
    effect.life = effect.maxLife
    if app.isAbyssRun then
        effect.visualScale = AbyssRunTools.GetSizeMultiplier(app.abyss, "DrillDrones")
        effect.radius = 8 * AbyssRunTools.GetRangeMultiplier(app.abyss, "DrillDrones")
    end
    effect.orbitAngle = effect.orbitAngle + dt * (1.7 + effect.slot * 0.08)
    local attackSpeed = math.max(0.1, app.state:GetActiveStat("drill_drones", "attack_speed"))
        * (app.isAbyssRun and AbyssRunTools.GetAttackSpeedMultiplier(app.abyss, "DrillDrones") or 1)
    effect.attackTimer = (effect.attackTimer or 0) - dt
    if not effect.targetX or not tileAt(app, effect.targetX, effect.targetY) then
        effect.targetX, effect.targetY = findNearbyTile(app, 82)
    end
    local distance = moveTowards(effect, effect.targetX, effect.targetY, 68 + attackSpeed * 18, dt)
    if distance <= 7 and effect.attackTimer <= 0 then
        effect.attackTimer = 1 / attackSpeed
        effect.lastTileKey = nil
        damageTile(app, effect, "drill_drones", 3)
        if not tileAt(app, effect.targetX, effect.targetY) then
            effect.targetX, effect.targetY = findNearbyTile(app, 82)
        end
        if app:IsLastDitchActive() and app.state:GetActiveStat("drill_drones", "last_ditch") > 0 then
            local damage, critical, legendary = activeDamage(app, "drill_drones")
            effect.damage, effect.critical, effect.legendary = damage * 2, critical, legendary
        else
            effect.damage, effect.critical, effect.legendary = activeDamage(app, "drill_drones")
        end
    end
end

local function updateOrbitingPickaxe(app, effect, dt)
    effect.life = effect.maxLife
    if app.isAbyssRun then
        effect.visualScale = AbyssRunTools.GetSizeMultiplier(app.abyss, "SpinningPickaxe")
        effect.radius = 8 * AbyssRunTools.GetRangeMultiplier(app.abyss, "SpinningPickaxe")
        effect.orbitRadius = (effect.baseOrbitRadius or effect.orbitRadius or 28)
            * AbyssRunTools.GetRangeMultiplier(app.abyss, "SpinningPickaxe")
        effect.damage, effect.critical, effect.legendary = activeDamage(app, "pickaxe_orbit")
    end
    effect.orbitAngle = effect.orbitAngle + dt * (2.7 + effect.slot * 0.13)
        * (app.isAbyssRun and AbyssRunTools.GetAttackSpeedMultiplier(app.abyss, "SpinningPickaxe") or 1)
    effect.x = app.player.x + math.cos(effect.orbitAngle) * effect.orbitRadius
    effect.y = app.player.y + math.sin(effect.orbitAngle) * effect.orbitRadius
    effect.rotation = effect.orbitAngle + effect.age * 8
    damageTile(app, effect, "pickaxe_orbit", 2)
end

local function updateBoomerang(app, effect, dt)
    if effect.age >= effect.returnAt then
        local distance = moveTowards(effect, app.player.x, app.player.y, 112, dt)
        if distance <= 8 then return true end
    else
        updateLinear(effect, dt)
    end
    effect.rotation = effect.rotation + effect.spinSpeed * dt
    damageTile(app, effect, "pickarang", 2)
    return false
end

local function updateBouncingBall(app, effect, dt)
    local previousX, previousY = effect.x, effect.y
    updateLinear(effect, dt)
    effect.rotation = effect.rotation + effect.spinSpeed * dt
    if damageTile(app, effect, "bouncing_ball", 3) then
        local hitHorizontal = tileAt(app, effect.x, previousY) ~= nil
        local hitVertical = tileAt(app, previousX, effect.y) ~= nil
        if hitHorizontal then effect.vx = -effect.vx end
        if hitVertical then effect.vy = -effect.vy end
        if not hitHorizontal and not hitVertical then
            effect.vx, effect.vy = -effect.vx, -effect.vy
        end
        effect.x, effect.y = previousX, previousY
        effect.lastTileKey = nil
        app:AddBurst(effect.x, effect.y, Config.Palette.purple, 4)
    end
end

local function updateMissile(app, effect, dt)
    updateLinear(effect, dt)
    local distance = Util.Length(effect.targetX - effect.x, effect.targetY - effect.y)
    if distance <= 7 or tileAt(app, effect.x, effect.y) or effect.life <= 0 then
        addExplosion(app, effect.x, effect.y, effect.radius, effect.damage, "drill_missile", Config.Palette.red, 3.3)
        return true
    end
    return false
end

local function updateTermiteDrone(app, effect, dt)
    local targetX = app.player.x + math.cos(app.aimAngle) * 82 + math.cos(effect.orbitAngle) * 14
    local targetY = app.player.y + math.sin(app.aimAngle) * 82 + math.sin(effect.orbitAngle) * 14
    effect.orbitAngle = effect.orbitAngle + dt * 2.2
    moveTowards(effect, targetX, targetY, 118, dt)
    damageTile(app, effect, "TermiteDrones", 2)
end

local function updateFallingPickaxe(app, effect, dt)
    effect.vy = effect.vy + effect.gravity * dt
    updateLinear(effect, dt)
    effect.rotation = effect.rotation + effect.spinSpeed * dt
    damageTile(app, effect, "FallingPickaxe", 4)
    if effect.life <= 0 then
        addExplosion(app, effect.x, effect.y, effect.radius, effect.damage, "FallingPickaxe", Config.Palette.gold, 3.7)
        return true
    end
    return false
end

local function updateMolenir(app, effect, dt)
    updateLinear(effect, dt)
    damageTile(app, effect, "Molenir", 4)
    if Util.Length(effect.targetX - effect.x, effect.targetY - effect.y) <= 10 or effect.life <= 0 then
        addExplosion(app, effect.x, effect.y, effect.radius, effect.damage, "Molenir", Config.Palette.red, 5.5)
        return true
    end
    return false
end

local function updateWorm(app, effect, dt)
    updateLinear(effect, dt)
    effect.hitTimer = effect.hitTimer - dt
    if effect.hitTimer <= 0 then
        effect.hitTimer = effect.hitTimer + 0.11
            / (app.isAbyssRun and AbyssRunTools.GetAttackSpeedMultiplier(app.abyss, "BulletWorms") or 1)
        damageArea(app, effect.x, effect.y, effect.radius, effect.damage, "TheWorm")
        app:AddBurst(effect.x, effect.y, Config.Palette.purple, 2)
    end
end

function ActiveEffects.UpdateEffect(app, effect, dt)
    effect.age = (effect.age or 0) + dt
    if effect.kind == "active_effect" and updateInscribedProjectile(app, effect, dt) then return true end
    if effect.effectId == "drill_drones" then
        updateDrillDrone(app, effect, dt)
    elseif effect.effectId == "pickaxe_orbit" then
        updateOrbitingPickaxe(app, effect, dt)
    elseif effect.effectId == "pickarang" then
        return updateBoomerang(app, effect, dt)
    elseif effect.effectId == "bouncing_ball" then
        updateBouncingBall(app, effect, dt)
    elseif effect.effectId == "drill_missile" then
        return updateMissile(app, effect, dt)
    elseif effect.effectId == "shrapnel_debris" or effect.effectId == "bullet_worms" then
        updateLinear(effect, dt)
        effect.rotation = math.atan(effect.vy or 0, effect.vx or 1)
        if damageTile(app, effect, effect.effectId, 2) and (effect.inscriptionRicochets or 0) > 0 then
            effect.inscriptionRicochets = effect.inscriptionRicochets - 1
            effect.vx, effect.vy = -(effect.vx or 0), -(effect.vy or 0)
            effect.x = effect.x + effect.vx * dt * 1.5
            effect.y = effect.y + effect.vy * dt * 1.5
            effect.lastTileKey = nil
        end
    elseif effect.effectId == "shockwave" then
        -- Damage is applied once on activation; this effect only plays the authored sprite.
    elseif effect.effectId == "termite_drone" then
        updateTermiteDrone(app, effect, dt)
    elseif effect.effectId == "falling_pickaxe" then
        return updateFallingPickaxe(app, effect, dt)
    elseif effect.effectId == "molenir" then
        return updateMolenir(app, effect, dt)
    elseif effect.effectId == "the_worm" then
        updateWorm(app, effect, dt)
    end
    return false
end

return ActiveEffects
