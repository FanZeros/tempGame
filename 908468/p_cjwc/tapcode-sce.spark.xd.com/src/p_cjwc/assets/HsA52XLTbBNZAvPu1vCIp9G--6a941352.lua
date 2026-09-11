local Config = require("nightgate.Config")

local BattleEffects = {}

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

function BattleEffects.Install(Battle)
    function Battle:AddParticle(x, y, color, vx, vy, life, size)
        if #self.particles >= Config.MAX_PARTICLES then table.remove(self.particles, 1) end
        self.particles[#self.particles + 1] = {
            x = x, y = y, color = color, vx = vx or 0, vy = vy or 0,
            life = life or 0.45, maxLife = life or 0.45, size = size or 3,
        }
    end

    function Battle:AddBurst(x, y, color, count, force)
        for index = 1, count do
            local angle = math.random() * math.pi * 2
            local speed = force * (0.45 + math.random() * 0.55)
            self:AddParticle(x, y, color, math.cos(angle) * speed, math.sin(angle) * speed,
                0.28 + math.random() * 0.35, 2 + math.random() * 3)
        end
    end

    function Battle:AddRing(x, y, color, radius, speed, life, style)
        self.rings[#self.rings + 1] = {
            x = x, y = y, color = color, radius = radius or 8,
            speed = speed or 80, life = life or 0.5, maxLife = life or 0.5, style = style,
        }
    end

    function Battle:AddSkillEffect(skillId, x, y, radius, sideIndex)
        if #self.skillEffects >= 48 then table.remove(self.skillEffects, 1) end
        local lifeBySkill = {
            [2002] = 0.48, [2003] = 0.58, [2004] = 0.68,
            [2005] = 0.62, [2007] = 0.72, [2008] = 0.54, [2009] = 0.64,
        }
        local life = lifeBySkill[skillId] or 0.5
        self.skillEffects[#self.skillEffects + 1] = {
            skillId = skillId, x = x, y = y, radius = radius or 42,
            side = sideIndex or 1, age = 0, life = life, maxLife = life,
        }
    end

    function Battle:AddGoldPickups(x, y, amount)
        amount = math.max(0, math.floor(tonumber(amount) or 0))
        if amount <= 0 then return end
        local stats = self:GetStats()
        local exactAmount = amount * (1 + (stats.goldGainBonus or 0)) + (self.goldGainRemainder or 0)
        amount = math.floor(exactAmount + 0.000001)
        self.goldGainRemainder = exactAmount - amount
        if amount <= 0 then return end
        local count = math.min(6, amount)
        local baseValue = math.floor(amount / count)
        local remainder = amount % count
        for index = 1, count do
            local angle = math.random() * math.pi * 2
            local scatter = 20 + math.random() * 34
            local flightSpeed = math.max(1, tonumber(stats.coinFlightSpeed) or 1)
            local duration = (0.64 + (index - 1) * 0.045 + math.random() * 0.08) / flightSpeed
            self.coinPickups[#self.coinPickups + 1] = {
                x = x, y = y, startX = x, startY = y,
                burstX = x + math.cos(angle) * scatter,
                burstY = y + math.sin(angle) * scatter - 10,
                targetX = 47.5, targetY = 118.5,
                value = baseValue + (index <= remainder and 1 or 0),
                age = -math.random() * 0.08, scatterTime = 0.18, duration = duration,
                rotation = math.random() * math.pi * 2,
            }
        end
    end

    function Battle:UpdateCoinPickups(dt)
        for index = #self.coinPickups, 1, -1 do
            local coin = self.coinPickups[index]
            coin.age = coin.age + dt
            if coin.age >= coin.duration then
                self.gold = self.gold + coin.value
                self.dirtySave = true
                self:PushEvent("coin")
                table.remove(self.coinPickups, index)
            elseif coin.age >= 0 then
                if coin.age < coin.scatterTime then
                    local t = coin.age / coin.scatterTime
                    local ease = 1 - (1 - t) * (1 - t)
                    coin.x = coin.startX + (coin.burstX - coin.startX) * ease
                    coin.y = coin.startY + (coin.burstY - coin.startY) * ease
                else
                    local t = clamp((coin.age - coin.scatterTime)
                        / math.max(0.01, coin.duration - coin.scatterTime), 0, 1)
                    local ease = t * t * (3 - 2 * t)
                    coin.x = coin.burstX + (coin.targetX - coin.burstX) * ease
                    coin.y = coin.burstY + (coin.targetY - coin.burstY) * ease - math.sin(t * math.pi) * 42
                end
                coin.rotation = coin.rotation + dt * 11
            end
        end
    end

    function Battle:CollectPendingGold()
        local pending = 0
        for index = 1, #self.coinPickups do
            pending = pending + math.max(0, math.floor(tonumber(self.coinPickups[index].value) or 0))
        end
        self.coinPickups = {}
        if pending > 0 then
            self.gold = self.gold + pending
            self.dirtySave = true
            self:PushEvent("coin")
        end
        return pending
    end

    function Battle:AddFloatingText(x, y, text, color, size, style)
        if #self.floatingText >= Config.MAX_FLOATING_TEXT then table.remove(self.floatingText, 1) end
        local life = style == "jackpot" and 1.65
            or (style == "reward" and 1.15 or (style == "cursor" and 0.92 or 0.8))
        self.floatingText[#self.floatingText + 1] = {
            x = x, y = y, text = text, color = color, size = size or 13,
            style = style, life = life, maxLife = life,
        }
    end
end

return BattleEffects
