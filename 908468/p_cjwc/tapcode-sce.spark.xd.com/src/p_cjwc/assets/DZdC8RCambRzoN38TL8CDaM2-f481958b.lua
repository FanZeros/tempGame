local Config = require("nightgate.Config")

local BattleExpansion = {}

local ECHO_COLOR = { 255, 215, 71, 255 }
local UNITY_COLOR = { 185, 103, 255, 255 }
local SPIRIT_COLOR = { 255, 198, 76, 255 }

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function queueSpiritArrow(battle, sideIndex, target, stats, damageScale)
    if not target or #battle.projectiles >= Config.MAX_PROJECTILES then return false end
    local x, y = battle:GetDefenderPosition(sideIndex, 1, 1)
    return battle:QueueProjectile({
        x = x, y = y, side = sideIndex,
        damage = math.max(1, (stats.cursorBase + stats.archerDamage) * 0.5)
            * stats.damageMultiplier * (damageScale or 1),
        speed = Config.ARCHER.projectileSpeed * 1.15,
        color = SPIRIT_COLOR, penetration = 0.25, remainingPenetrations = 0,
        projectileSize = 1.25, critical = false, source = "spirit", life = 2.4,
    }, target)
end

function BattleExpansion.Initialize(battle)
    battle.expansionEchoes = {}
    battle.expansionCursorAttacks = 0
    battle.expansionHeroSpecials = 0
    battle.expansionArcherRounds = 0
    battle.expansionLastStandReady = true
    battle.expansionSpiritTimer = 0.8
end

function BattleExpansion.OnCursorAttack(battle, stats, damage)
    local echoChance = clamp(tonumber(stats.cursorEchoChance) or 0, 0, 1)
    if echoChance > 0 and math.random() < echoChance then
        battle.expansionEchoes[#battle.expansionEchoes + 1] = {
            x = battle.cursor.x, y = battle.cursor.y, timer = 0.18,
            radius = stats.cursorRadius, damage = damage * 0.65,
        }
    end

    local stormEvery = math.max(0, math.floor(tonumber(stats.cursorStormEvery) or 0))
    if stormEvery <= 0 then return end
    battle.expansionCursorAttacks = battle.expansionCursorAttacks + 1
    if battle.expansionCursorAttacks % stormEvery ~= 0 then return end
    for sideIndex = 1, 4 do
        local target = battle:FindTarget(sideIndex)
        if target then
            battle:AddRing(target.x, target.y, ECHO_COLOR, 5, 112, 0.36, "cursor_storm")
            battle:DamageEnemy(target, damage * 0.9, ECHO_COLOR, false, "cursor")
        end
    end
    battle:AddFloatingText(battle.arena.x + battle.arena.size * 0.5,
        battle.arena.y + battle.arena.size * 0.5, "四壁雷鸣", ECHO_COLOR, 20)
end

function BattleExpansion.ConfigureArcherProjectile(projectile, stats)
    local chance = clamp(tonumber(stats.archerRicochetChance) or 0, 0, 1)
    if chance > 0 and math.random() < chance then
        projectile.remainingPenetrations = math.max(0, math.floor(projectile.remainingPenetrations or 0)) + 1
        projectile.ricochet = true
    end
    return projectile
end

function BattleExpansion.OnArcherRound(battle, stats)
    local barrageEvery = math.max(0, math.floor(tonumber(stats.archerBarrageEvery) or 0))
    if barrageEvery <= 0 then return end
    battle.expansionArcherRounds = battle.expansionArcherRounds + 1
    if battle.expansionArcherRounds % barrageEvery ~= 0 then return end
    local fired = false
    for sideIndex = 1, 4 do
        local target = battle:FindTarget(sideIndex)
        if target then
            local x, y = battle:GetDefenderPosition(sideIndex, 1, 1)
            fired = battle:QueueProjectile({
                x = x, y = y, side = sideIndex,
                damage = stats.archerDamage * stats.archerDamageMultiplier * 1.4,
                speed = Config.ARCHER.projectileSpeed * 1.2,
                color = ECHO_COLOR, penetration = stats.archerProjectilePenetration,
                remainingPenetrations = 1, projectileSize = 1.4,
                critical = false, source = "archer", life = 2.4,
            }, target) or fired
        end
    end
    if fired then
        battle:AddFloatingText(battle.arena.x + battle.arena.size * 0.5,
            battle.arena.y + 34, "四墙齐射", ECHO_COLOR, 20)
        battle:PushEvent("bow")
    end
end

function BattleExpansion.GetHeroSpecialEvery(hero, stats)
    return math.max(3, math.floor((hero.specialEvery or 6) - (stats.heroSpecialAcceleration or 0)))
end

function BattleExpansion.OnHeroSpecial(battle, stats)
    local unityEvery = math.max(0, math.floor(tonumber(stats.heroUnityEvery) or 0))
    if unityEvery <= 0 then return end
    battle.expansionHeroSpecials = battle.expansionHeroSpecials + 1
    if battle.expansionHeroSpecials % unityEvery ~= 0 then return end
    local x = battle.arena.x + battle.arena.size * 0.5
    local y = battle.arena.y + battle.arena.size * 0.5
    local radius = battle.arena.size * 0.34
    local damage = math.max(12, stats.heroDamage + stats.cursorBase) * stats.heroDamageMultiplier * 2.2
    battle:AddRing(x, y, UNITY_COLOR, 14, radius * 2.6, 0.58, "hero_unity")
    battle:AddBurst(x, y, UNITY_COLOR, 24, 145)
    battle:AddFloatingText(x, y - 22, "四方合击", UNITY_COLOR, 22)
    battle:DamageEnemiesInRadius(x, y, radius, damage, UNITY_COLOR, nil, false, "hero")
end

function BattleExpansion.OnWallDamage(battle, enemy, stats)
    local thorns = math.max(0, tonumber(stats.wallThornsDamage) or 0)
    if thorns > 0 and enemy and not enemy.dead then
        local damage = thorns * stats.damageMultiplier
        battle:AddRing(enemy.x, enemy.y, Config.COLORS.unlocked, 4, 74, 0.28, "wall_thorns")
        battle:DamageEnemy(enemy, damage, Config.COLORS.unlocked, false, "wall")
    end
    if battle.wallHP > 0 or not stats.wallLastStandEnabled or not battle.expansionLastStandReady then
        return false
    end
    battle.expansionLastStandReady = false
    battle.wallHP = math.max(1, math.floor(battle.wallMax * 0.25 + 0.5))
    local x = battle.arena.x + battle.arena.size * 0.5
    local y = battle.arena.y + battle.arena.size * 0.5
    battle:AddRing(x, y, Config.COLORS.unlocked, 18, battle.arena.size * 1.8, 0.72, "last_stand")
    battle:AddBurst(x, y, Config.COLORS.unlocked, 28, 165)
    battle:AddFloatingText(x, y - 24, "不屈防线 · 恢复25%", Config.COLORS.unlocked, 22)
    for index = 1, #battle.enemies do
        local target = battle.enemies[index]
        if not target.dead then
            target.wait = math.max(target.wait or 0, 1.1)
        end
    end
    battle:PushEvent("upgrade")
    return true
end

function BattleExpansion.Update(battle, dt, stats)
    for index = #battle.expansionEchoes, 1, -1 do
        local echo = battle.expansionEchoes[index]
        echo.timer = echo.timer - dt
        if echo.timer <= 0 then
            battle:AddRing(echo.x, echo.y, ECHO_COLOR, echo.radius * 0.35, echo.radius * 2.1, 0.38, "cursor_echo")
            battle:DamageEnemiesInRadius(echo.x, echo.y, echo.radius, echo.damage, ECHO_COLOR, nil, false, "cursor")
            table.remove(battle.expansionEchoes, index)
        end
    end

    if (stats.spiritVolleyEnabled or 0) <= 0 then return end
    battle.expansionSpiritTimer = battle.expansionSpiritTimer - dt
    if battle.expansionSpiritTimer > 0 then return end
    battle.expansionSpiritTimer = 1.8
    local fired = false
    for sideIndex = 1, 4 do
        fired = queueSpiritArrow(battle, sideIndex, battle:FindTarget(sideIndex), stats, 1) or fired
    end
    if fired then battle:PushEvent("bow") end
end

return BattleExpansion
