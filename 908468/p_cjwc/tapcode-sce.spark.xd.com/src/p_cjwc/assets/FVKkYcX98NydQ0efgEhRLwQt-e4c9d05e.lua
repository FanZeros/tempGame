local Config = require("nightgate.Config")

local ProjectileSystem = {}

local function distance(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

function ProjectileSystem.Install(Battle)
    function Battle:UpdateProjectiles(dt)
        for index = #self.projectiles, 1, -1 do
            local projectile = self.projectiles[index]
            projectile.life = projectile.life - dt
            local target = projectile.target
            if projectile.life <= 0 then
                self:ReleaseProjectileReservation(projectile)
                table.remove(self.projectiles, index)
            else
                if not target or target.dead then
                    self:ReleaseProjectileReservation(projectile)
                    target = self:FindTarget(projectile.side)
                    if target then
                        self:AssignProjectileTarget(projectile, target)
                    else
                        table.remove(self.projectiles, index)
                    end
                end
                if target then
                    local d = distance(projectile.x, projectile.y, target.x, target.y)
                    local step = projectile.speed * dt
                    if d <= step + 3 then
                        self:ReleaseProjectileReservation(projectile)
                        if projectile.skillId == 2009 then
                            target.seedDamage = projectile.damage
                            target.seedRadius = math.max(44, (projectile.projectileSize or 2) * 24)
                        end
                        self:DamageEnemy(target, projectile.damage, projectile.color, projectile.critical or false, projectile.source)
                        if projectile.explosive then
                            self:AddRing(target.x, target.y, Config.COLORS.gold, 5, 125, 0.34, "explosive_arrow")
                            self:DamageEnemiesInRadius(target.x, target.y,
                                38 * (1 + (projectile.radiusBonus or 0)), projectile.damage,
                                Config.COLORS.gold, nil, projectile.critical, "archer")
                        end
                        if projectile.special then
                            self:AddRing(target.x, target.y, projectile.color, 6, 120, 0.35, "hero_skill")
                            self:AddSkillEffect(projectile.skillId, target.x, target.y,
                                math.max(34, (projectile.projectileSize or 1) * 24), projectile.side)
                        end

                        local nextTarget = nil
                        local nextDistance = math.huge
                        local remaining = math.max(0, math.floor(projectile.remainingPenetrations or 0))
                        local canPenetrate = remaining > 0 or math.random() < (projectile.penetration or 0)
                        if canPenetrate then
                            for enemyIndex = 1, #self.enemies do
                                local enemy = self.enemies[enemyIndex]
                                if enemy ~= target and not enemy.dead and enemy.side == projectile.side
                                    and (tonumber(enemy.hp) or math.huge) - (enemy.incomingDamage or 0) > 0 then
                                    local candidateDistance = distance(projectile.x, projectile.y, enemy.x, enemy.y)
                                    if candidateDistance < nextDistance then
                                        nextDistance = candidateDistance
                                        nextTarget = enemy
                                    end
                                end
                            end
                        end
                        if nextTarget then
                            self:AssignProjectileTarget(projectile, nextTarget)
                            if remaining > 0 then
                                projectile.remainingPenetrations = remaining - 1
                            else
                                projectile.penetration = math.max(0, (projectile.penetration or 0) - 0.15)
                            end
                        else
                            table.remove(self.projectiles, index)
                        end
                    else
                        projectile.x = projectile.x + (target.x - projectile.x) / d * step
                        projectile.y = projectile.y + (target.y - projectile.y) / d * step
                    end
                end
            end
        end
    end
end

return ProjectileSystem
