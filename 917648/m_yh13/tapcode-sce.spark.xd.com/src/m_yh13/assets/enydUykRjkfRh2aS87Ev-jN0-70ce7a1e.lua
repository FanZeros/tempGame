local Config = require("diggin.Config")

local Laser = {}

local function traceBeam(app, angle)
    local dx, dy = math.cos(angle), math.sin(angle)
    local endX = app.player.x + dx * 128
    local endY = app.player.y + dy * 128
    local hitTile = nil
    for distance = 8, 128, 3 do
        local wx = app.player.x + dx * distance
        local wy = app.player.y + dy * distance
        local tile = app.world:GetTile(
            math.floor(wx / Config.TILE_SIZE),
            math.floor(wy / Config.TILE_SIZE)
        )
        if tile then
            hitTile = tile
            endX, endY = wx, wy
            break
        end
    end
    return hitTile, endX, endY
end

local function damageBeam(app, hitTile, endX, endY, damage)
    local destroyed, damagedTile = app.world:DamageTile(hitTile, damage, false, "laser")
    app:AddMaterialBurst(hitTile, 3, false)
    app:AddBurst(endX, endY, Config.Palette.cyan, 2)
    if destroyed then
        app:OnTileDestroyed(damagedTile, "laser")
    else
        app:AddHitFlash(hitTile, false)
    end
end

function Laser.Update(app, dt)
    if not app.state:IsNodeBought("Laser") then
        app.laserActive = false
        app.laserBeams = {}
        return
    end
    if not app.laserActive then
        app.laserEnergy = math.min(app.laserMax, app.laserEnergy + dt * 0.5)
        app.laserBeams = {}
        return
    end

    local efficiency = math.max(0.001, app.state:GetActiveStat("overheat", "laser_efficiency"))
    app.laserEnergy = math.max(0, app.laserEnergy - dt * 5 / efficiency)
    if app.laserEnergy <= 0 then
        app.laserActive = false
        app.laserBeams = {}
        return
    end

    app.laserHitTimer = app.laserHitTimer - dt
    local interval = app.overdriveActive and 0.02 or 0.2
    local shouldDamage = app.laserHitTimer <= 0
    local baseDamage = app.state:GetActiveStat("overheat", "laser_strength")
        + app.state:GetGeneralStat("drill_damage")
            * app.state:GetActiveStat("overheat", "laser_drill_scaling") / 100
    if app.overdriveActive then baseDamage = baseDamage * 25 end

    local offsets = { 0 }
    if app.state:GetLevel("LaserDamage") >= 3 then offsets = { 0, -0.14, 0.14 } end
    app.laserBeams = {}
    local damagedAny = false
    for index, offset in ipairs(offsets) do
        local hitTile, endX, endY = traceBeam(app, app.aimAngle + offset)
        app.laserBeams[index] = {
            endX = endX,
            endY = endY,
            secondary = index > 1,
        }
        if index == 1 then app.laserEndX, app.laserEndY = endX, endY end
        if shouldDamage and hitTile then
            damageBeam(app, hitTile, endX, endY, baseDamage * (index == 1 and 1 or 0.55))
            damagedAny = true
        end
    end
    if damagedAny then app.laserHitTimer = interval end
end

return Laser
